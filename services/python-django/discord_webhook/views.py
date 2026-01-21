"""Discord webhook views for handling Discord interactions.

This module handles Discord interactions webhooks:
- Validates Ed25519 signatures on incoming requests
- Responds to Ping (type=1) with Pong (type=1)
- Responds to Slash commands (type=2) with Deferred (type=5)
- Publishes sanitized slash command payloads to Pub/Sub
"""

import json
import logging
import os
import time
from datetime import UTC, datetime
from threading import Thread

from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_GET, require_POST
from nacl.exceptions import BadSignatureError
from nacl.signing import VerifyKey

# Optional Pub/Sub import
try:
    from google.cloud import pubsub_v1

    PUBSUB_AVAILABLE = True
except ImportError:
    PUBSUB_AVAILABLE = False

logger = logging.getLogger(__name__)

# Interaction types
INTERACTION_TYPE_PING = 1
INTERACTION_TYPE_APPLICATION_COMMAND = 2

# Response types
RESPONSE_TYPE_PONG = 1
RESPONSE_TYPE_DEFERRED_CHANNEL_MESSAGE = 5


class Config:
    """Service configuration initialized from environment variables."""

    _instance = None
    _initialized = False

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance

    def __init__(self):
        if Config._initialized:
            return
        Config._initialized = True

        # Load Discord public key
        public_key_hex = os.getenv("DISCORD_PUBLIC_KEY")
        if not public_key_hex:
            raise ValueError("DISCORD_PUBLIC_KEY environment variable is required")

        try:
            self.public_key = VerifyKey(bytes.fromhex(public_key_hex))
        except Exception as e:
            raise ValueError(f"Invalid DISCORD_PUBLIC_KEY: {e}") from e

        # Initialize Pub/Sub client
        self.pubsub_publisher = None
        self.pubsub_topic_path = None

        project_id = os.getenv("GOOGLE_CLOUD_PROJECT")
        topic_name = os.getenv("PUBSUB_TOPIC")

        if project_id and topic_name and PUBSUB_AVAILABLE:
            try:
                self.pubsub_publisher = pubsub_v1.PublisherClient()
                self.pubsub_topic_path = self.pubsub_publisher.topic_path(project_id, topic_name)

                # Ensure topic exists (for emulator)
                try:
                    self.pubsub_publisher.get_topic(topic=self.pubsub_topic_path)
                except Exception:
                    # Topic doesn't exist, create it
                    try:
                        self.pubsub_publisher.create_topic(name=self.pubsub_topic_path)
                        logger.info(f"Created topic: {self.pubsub_topic_path}")
                    except Exception as create_err:
                        logger.warning(f"Failed to create topic: {create_err}")

                logger.info(f"Pub/Sub configured: {self.pubsub_topic_path}")
            except Exception as e:
                logger.warning(f"Failed to initialize Pub/Sub client: {e}")
                self.pubsub_publisher = None
                self.pubsub_topic_path = None


def get_config() -> Config:
    """Get the singleton configuration instance."""
    return Config()


def validate_signature(signature_hex: str, timestamp: str, body: bytes) -> bool:
    """Validate Discord Ed25519 signature.

    Args:
        signature_hex: Hex-encoded Ed25519 signature
        timestamp: Unix timestamp string
        body: Raw request body bytes

    Returns:
        True if signature is valid, False otherwise
    """
    config = get_config()

    if not signature_hex or not timestamp:
        return False

    # Check timestamp (must be within 5 seconds)
    try:
        ts = int(timestamp)
        if int(time.time()) - ts > 5:
            return False
    except ValueError:
        return False

    # Verify signature: verify(timestamp + body)
    try:
        signature = bytes.fromhex(signature_hex)
        message = timestamp.encode() + body
        config.public_key.verify(message, signature)
        return True
    except (ValueError, BadSignatureError):
        return False


def publish_to_pubsub(interaction: dict) -> None:
    """Publish sanitized interaction to Pub/Sub.

    Args:
        interaction: The interaction dict (will be sanitized before publishing)
    """
    config = get_config()

    if not config.pubsub_publisher or not config.pubsub_topic_path:
        return

    # Create sanitized copy (remove sensitive fields)
    sanitized = {
        "type": interaction.get("type"),
        "id": interaction.get("id"),
        "application_id": interaction.get("application_id"),
        # Token is intentionally NOT copied - sensitive data
        "data": interaction.get("data"),
        "guild_id": interaction.get("guild_id"),
        "channel_id": interaction.get("channel_id"),
        "member": interaction.get("member"),
        "user": interaction.get("user"),
        "locale": interaction.get("locale"),
        "guild_locale": interaction.get("guild_locale"),
    }

    # Remove None values
    sanitized = {k: v for k, v in sanitized.items() if v is not None}

    data = json.dumps(sanitized).encode("utf-8")

    # Build attributes
    attributes = {
        "interaction_id": interaction.get("id", ""),
        "interaction_type": str(interaction.get("type", "")),
        "application_id": interaction.get("application_id", ""),
        "guild_id": interaction.get("guild_id", ""),
        "channel_id": interaction.get("channel_id", ""),
        "timestamp": datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }

    # Add command name if available
    if interaction.get("data") and isinstance(interaction["data"], dict):
        command_name = interaction["data"].get("name")
        if command_name:
            attributes["command_name"] = command_name

    try:
        future = config.pubsub_publisher.publish(config.pubsub_topic_path, data, **attributes)
        future.result(timeout=10)
    except Exception as e:
        logger.error(f"Failed to publish to Pub/Sub: {e}")


@require_GET
def health(request):
    """Health check endpoint."""
    return JsonResponse({"status": "ok"})


@csrf_exempt
@require_POST
def handle_interaction(request):
    """Handle Discord interaction webhook."""
    # Get raw body for signature verification
    body = request.body

    # Get signature headers
    signature = request.headers.get("X-Signature-Ed25519", "")
    timestamp = request.headers.get("X-Signature-Timestamp", "")

    # Validate signature
    if not validate_signature(signature, timestamp, body):
        return JsonResponse({"error": "invalid signature"}, status=401)

    # Parse interaction
    try:
        interaction = json.loads(body)
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid JSON"}, status=400)

    # Ensure interaction is a dict (not null, array, or primitive)
    if not isinstance(interaction, dict):
        return JsonResponse({"error": "invalid JSON"}, status=400)

    interaction_type = interaction.get("type")

    # Handle by type
    if interaction_type == INTERACTION_TYPE_PING:
        return _handle_ping()
    elif interaction_type == INTERACTION_TYPE_APPLICATION_COMMAND:
        return _handle_application_command(interaction)
    else:
        return JsonResponse({"error": "unsupported interaction type"}, status=400)


def _handle_ping():
    """Handle Ping interaction - respond with Pong."""
    return JsonResponse({"type": RESPONSE_TYPE_PONG})


def _handle_application_command(interaction: dict):
    """Handle Application Command (slash command) interaction."""
    config = get_config()

    # Publish to Pub/Sub in background thread
    if config.pubsub_publisher:
        thread = Thread(target=publish_to_pubsub, args=(interaction,))
        thread.daemon = True
        thread.start()

    # Respond with deferred response (non-ephemeral)
    return JsonResponse({"type": RESPONSE_TYPE_DEFERRED_CHANNEL_MESSAGE})
