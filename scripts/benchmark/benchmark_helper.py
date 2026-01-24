#!/usr/bin/env python3
"""
Benchmark helper for Discord webhook service testing.
Provides Ed25519 signing and Pub/Sub interaction utilities.
"""

import hashlib
import json
import sys
import time
from typing import Optional, Tuple

# Ed25519 signing using PyNaCl
try:
    from nacl.signing import SigningKey
    from nacl.encoding import HexEncoder
except ImportError:
    print("ERROR: PyNaCl not installed. Run: pip install pynacl", file=sys.stderr)
    sys.exit(1)

# Google Cloud Pub/Sub
try:
    from google.cloud import pubsub_v1
    from google.api_core import exceptions as gcp_exceptions
except ImportError:
    pubsub_v1 = None

# Test key derivation (matches tests/contract/testkeys/keys.go)
TEST_SEED = "discord-bot-test-suite-ed25519-test-key-seed-v1"


def get_test_keys() -> Tuple[SigningKey, str]:
    """
    Generate deterministic test key pair from fixed seed.
    Returns (signing_key, public_key_hex).
    """
    seed = hashlib.sha256(TEST_SEED.encode()).digest()
    signing_key = SigningKey(seed)
    public_key_hex = signing_key.verify_key.encode(encoder=HexEncoder).decode()
    return signing_key, public_key_hex


def sign_request(body: bytes, timestamp: Optional[str] = None) -> Tuple[str, str]:
    """
    Sign a Discord interaction request.
    Returns (signature_hex, timestamp).
    """
    signing_key, _ = get_test_keys()

    if timestamp is None:
        timestamp = str(int(time.time()))

    # Discord signature format: sign(timestamp + body)
    message = timestamp.encode() + body
    signed = signing_key.sign(message)
    signature_hex = signed.signature.hex()

    return signature_hex, timestamp


def create_ping_request() -> bytes:
    """Create a Discord ping interaction request body."""
    return json.dumps({"type": 1}).encode()


def create_slash_command_request(command_name: str = "test-command") -> bytes:
    """Create a Discord slash command interaction request body."""
    return json.dumps(
        {
            "type": 2,
            "id": "123456789",
            "application_id": "987654321",
            "token": "test-token-should-be-redacted",
            "guild_id": "111222333",
            "channel_id": "444555666",
            "data": {"id": "cmd123", "name": command_name, "type": 1},
            "member": {"user": {"id": "user123", "username": "testuser"}},
        }
    ).encode()


def setup_pubsub(project_id: str, topic_name: str, subscription_name: str) -> bool:
    """
    Set up Pub/Sub topic and subscription for testing.
    Returns True if successful.
    """
    if pubsub_v1 is None:
        print("ERROR: google-cloud-pubsub not installed", file=sys.stderr)
        return False

    try:
        publisher = pubsub_v1.PublisherClient()
        subscriber = pubsub_v1.SubscriberClient()

        topic_path = publisher.topic_path(project_id, topic_name)
        subscription_path = subscriber.subscription_path(project_id, subscription_name)

        # Create topic if not exists
        try:
            publisher.create_topic(request={"name": topic_path})
        except gcp_exceptions.AlreadyExists:
            pass

        # Create subscription if not exists
        try:
            subscriber.create_subscription(
                request={
                    "name": subscription_path,
                    "topic": topic_path,
                    "ack_deadline_seconds": 10,
                }
            )
        except gcp_exceptions.AlreadyExists:
            pass

        return True
    except Exception as e:
        print(f"ERROR: Failed to setup Pub/Sub: {e}", file=sys.stderr)
        return False


def pull_message(
    project_id: str, subscription_name: str, timeout: float = 5.0
) -> Optional[dict]:
    """
    Pull a single message from Pub/Sub subscription.
    Returns message data dict or None if timeout/error.
    """
    if pubsub_v1 is None:
        return None

    try:
        subscriber = pubsub_v1.SubscriberClient()
        subscription_path = subscriber.subscription_path(project_id, subscription_name)

        response = subscriber.pull(
            request={"subscription": subscription_path, "max_messages": 1},
            timeout=timeout,
        )

        if response.received_messages:
            msg = response.received_messages[0]
            # Acknowledge the message
            subscriber.acknowledge(
                request={"subscription": subscription_path, "ack_ids": [msg.ack_id]}
            )
            return {
                "data": msg.message.data.decode(),
                "attributes": dict(msg.message.attributes),
                "message_id": msg.message.message_id,
                "publish_time": msg.message.publish_time.isoformat()
                if msg.message.publish_time
                else None,
            }
        return None
    except Exception as e:
        print(f"ERROR: Failed to pull message: {e}", file=sys.stderr)
        return None


def clear_subscription(project_id: str, subscription_name: str) -> int:
    """
    Clear all pending messages from a subscription.
    Returns number of messages cleared.
    """
    if pubsub_v1 is None:
        return 0

    count = 0
    try:
        subscriber = pubsub_v1.SubscriberClient()
        subscription_path = subscriber.subscription_path(project_id, subscription_name)

        while True:
            response = subscriber.pull(
                request={"subscription": subscription_path, "max_messages": 100},
                timeout=1.0,
            )

            if not response.received_messages:
                break

            ack_ids = [msg.ack_id for msg in response.received_messages]
            subscriber.acknowledge(
                request={"subscription": subscription_path, "ack_ids": ack_ids}
            )
            count += len(ack_ids)
    except Exception:
        pass

    return count


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Benchmark helper utilities")
    subparsers = parser.add_subparsers(dest="command")

    # Get public key
    key_parser = subparsers.add_parser("get-public-key", help="Get test public key hex")

    # Sign request
    sign_parser = subparsers.add_parser("sign", help="Sign a request body")
    sign_parser.add_argument("--body", required=True, help="Request body (JSON)")
    sign_parser.add_argument("--timestamp", help="Timestamp (default: current time)")

    # Create ping request
    ping_parser = subparsers.add_parser(
        "create-ping", help="Create signed ping request"
    )

    # Create slash command request
    slash_parser = subparsers.add_parser(
        "create-slash", help="Create signed slash command request"
    )
    slash_parser.add_argument("--name", default="test-command", help="Command name")

    # Setup Pub/Sub
    setup_parser = subparsers.add_parser(
        "setup-pubsub", help="Setup Pub/Sub topic and subscription"
    )
    setup_parser.add_argument("--project", required=True, help="GCP project ID")
    setup_parser.add_argument("--topic", required=True, help="Topic name")
    setup_parser.add_argument("--subscription", required=True, help="Subscription name")

    # Pull message
    pull_parser = subparsers.add_parser(
        "pull-message", help="Pull message from Pub/Sub"
    )
    pull_parser.add_argument("--project", required=True, help="GCP project ID")
    pull_parser.add_argument("--subscription", required=True, help="Subscription name")
    pull_parser.add_argument(
        "--timeout", type=float, default=5.0, help="Timeout in seconds"
    )

    # Clear subscription
    clear_parser = subparsers.add_parser(
        "clear-subscription", help="Clear pending messages"
    )
    clear_parser.add_argument("--project", required=True, help="GCP project ID")
    clear_parser.add_argument("--subscription", required=True, help="Subscription name")

    args = parser.parse_args()

    if args.command == "get-public-key":
        _, public_key = get_test_keys()
        print(public_key)

    elif args.command == "sign":
        body = args.body.encode()
        sig, ts = sign_request(body, args.timestamp)
        print(json.dumps({"signature": sig, "timestamp": ts}))

    elif args.command == "create-ping":
        body = create_ping_request()
        sig, ts = sign_request(body)
        print(json.dumps({"body": body.decode(), "signature": sig, "timestamp": ts}))

    elif args.command == "create-slash":
        body = create_slash_command_request(args.name)
        sig, ts = sign_request(body)
        print(json.dumps({"body": body.decode(), "signature": sig, "timestamp": ts}))

    elif args.command == "setup-pubsub":
        success = setup_pubsub(args.project, args.topic, args.subscription)
        sys.exit(0 if success else 1)

    elif args.command == "pull-message":
        msg = pull_message(args.project, args.subscription, args.timeout)
        if msg:
            print(json.dumps(msg))
            sys.exit(0)
        else:
            sys.exit(1)

    elif args.command == "clear-subscription":
        count = clear_subscription(args.project, args.subscription)
        print(f"Cleared {count} messages")

    else:
        parser.print_help()
