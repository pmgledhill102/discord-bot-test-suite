// Discord webhook service implementation using Node.js and Express.
//
// This service handles Discord interactions webhooks:
// - Validates Ed25519 signatures on incoming requests
// - Responds to Ping (type=1) with Pong (type=1)
// - Responds to Slash commands (type=2) with Deferred (type=5)
// - Publishes sanitized slash command payloads to Pub/Sub

const express = require('express');
const nacl = require('tweetnacl');
const { PubSub } = require('@google-cloud/pubsub');

// Interaction types
const INTERACTION_TYPE_PING = 1;
const INTERACTION_TYPE_APPLICATION_COMMAND = 2;

// Response types
const RESPONSE_TYPE_PONG = 1;
const RESPONSE_TYPE_DEFERRED_CHANNEL_MESSAGE = 5;

// Configuration
const PORT = process.env.PORT || 8080;
const DISCORD_PUBLIC_KEY = process.env.DISCORD_PUBLIC_KEY;
const GOOGLE_CLOUD_PROJECT = process.env.GOOGLE_CLOUD_PROJECT;
const PUBSUB_TOPIC = process.env.PUBSUB_TOPIC;

if (!DISCORD_PUBLIC_KEY) {
  console.error('DISCORD_PUBLIC_KEY environment variable is required');
  process.exit(1);
}

// Decode public key from hex
let publicKey;
try {
  publicKey = Buffer.from(DISCORD_PUBLIC_KEY, 'hex');
} catch (err) {
  console.error('Invalid DISCORD_PUBLIC_KEY:', err.message);
  process.exit(1);
}

// Initialize Pub/Sub client
let pubsub = null;
let topic = null;

async function initPubSub() {
  if (GOOGLE_CLOUD_PROJECT && PUBSUB_TOPIC) {
    try {
      pubsub = new PubSub({ projectId: GOOGLE_CLOUD_PROJECT });
      topic = pubsub.topic(PUBSUB_TOPIC);

      // Check if topic exists, create if needed (for emulator)
      const [exists] = await topic.exists();
      if (!exists) {
        [topic] = await pubsub.createTopic(PUBSUB_TOPIC);
        console.log(`Created topic: ${PUBSUB_TOPIC}`);
      }
    } catch (err) {
      console.warn('Warning: Failed to initialize Pub/Sub:', err.message);
    }
  }
}

// Validate Ed25519 signature
function validateSignature(signature, timestamp, body) {
  if (!signature || !timestamp) {
    return false;
  }

  // Validate signature is valid hex (Buffer.from doesn't throw on invalid hex)
  if (!/^[0-9a-fA-F]+$/.test(signature)) {
    return false;
  }

  // Ed25519 signature must be 64 bytes (128 hex chars)
  if (signature.length !== 128) {
    return false;
  }

  // Decode signature from hex
  const sigBytes = Buffer.from(signature, 'hex');

  // Check timestamp (must be within 5 seconds)
  const ts = parseInt(timestamp, 10);
  if (isNaN(ts)) {
    return false;
  }
  const now = Math.floor(Date.now() / 1000);
  if (now - ts > 5) {
    return false;
  }

  // Verify signature: sign(timestamp + body)
  const message = Buffer.concat([Buffer.from(timestamp), body]);
  try {
    return nacl.sign.detached.verify(message, sigBytes, publicKey);
  } catch {
    return false;
  }
}

// Publish to Pub/Sub (non-blocking)
async function publishToPubSub(interaction) {
  if (!topic) return;

  try {
    // Create sanitized copy (remove sensitive fields)
    const sanitized = {
      type: interaction.type,
      id: interaction.id,
      application_id: interaction.application_id,
      // token is intentionally NOT copied - sensitive data
      data: interaction.data,
      guild_id: interaction.guild_id,
      channel_id: interaction.channel_id,
      member: interaction.member,
      user: interaction.user,
      locale: interaction.locale,
      guild_locale: interaction.guild_locale,
    };

    // Build message attributes
    const attributes = {
      interaction_id: interaction.id || '',
      interaction_type: String(interaction.type),
      application_id: interaction.application_id || '',
      guild_id: interaction.guild_id || '',
      channel_id: interaction.channel_id || '',
      timestamp: new Date().toISOString(),
    };

    // Add command name if available
    if (interaction.data && interaction.data.name) {
      attributes.command_name = interaction.data.name;
    }

    const data = Buffer.from(JSON.stringify(sanitized));
    await topic.publishMessage({ data, attributes });
  } catch (err) {
    console.error('Failed to publish to Pub/Sub:', err.message);
  }
}

// Create Express app
const app = express();

// Parse raw body for signature validation
app.use(
  express.raw({
    type: 'application/json',
    limit: '10mb',
  })
);

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

// Discord interactions endpoint
function handleInteraction(req, res) {
  const body = req.body;

  // Validate signature
  const signature = req.headers['x-signature-ed25519'];
  const timestamp = req.headers['x-signature-timestamp'];

  if (!validateSignature(signature, timestamp, body)) {
    return res.status(401).json({ error: 'invalid signature' });
  }

  // Parse JSON
  let interaction;
  try {
    interaction = JSON.parse(body.toString());
  } catch {
    return res.status(400).json({ error: 'invalid JSON' });
  }

  // Validate interaction is an object
  if (!interaction || typeof interaction !== 'object' || Array.isArray(interaction)) {
    return res.status(400).json({ error: 'invalid JSON' });
  }

  // Handle by type
  switch (interaction.type) {
    case INTERACTION_TYPE_PING:
      // Respond with Pong - do NOT publish to Pub/Sub
      return res.json({ type: RESPONSE_TYPE_PONG });

    case INTERACTION_TYPE_APPLICATION_COMMAND:
      // Publish to Pub/Sub (non-blocking)
      publishToPubSub(interaction);
      // Respond with deferred response
      return res.json({ type: RESPONSE_TYPE_DEFERRED_CHANNEL_MESSAGE });

    default:
      return res.status(400).json({ error: 'unsupported interaction type' });
  }
}

app.post('/', handleInteraction);
app.post('/interactions', handleInteraction);

// Start server
async function main() {
  await initPubSub();

  app.listen(PORT, () => {
    console.log(`Starting server on port ${PORT}`);
  });
}

main().catch((err) => {
  console.error('Failed to start server:', err);
  process.exit(1);
});
