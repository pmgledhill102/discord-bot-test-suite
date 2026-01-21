/**
 * Discord webhook service implementation using TypeScript and Fastify.
 *
 * This service handles Discord interactions webhooks:
 * - Validates Ed25519 signatures on incoming requests
 * - Responds to Ping (type=1) with Pong (type=1)
 * - Responds to Slash commands (type=2) with Deferred (type=5)
 * - Publishes sanitized slash command payloads to Pub/Sub
 */

import Fastify, { FastifyRequest, FastifyReply } from "fastify";
import nacl from "tweetnacl";
import { PubSub, Topic } from "@google-cloud/pubsub";

// Interaction types
const INTERACTION_TYPE_PING = 1;
const INTERACTION_TYPE_APPLICATION_COMMAND = 2;

// Response types
const RESPONSE_TYPE_PONG = 1;
const RESPONSE_TYPE_DEFERRED_CHANNEL_MESSAGE = 5;

interface Interaction {
  type: number;
  id?: string;
  application_id?: string;
  token?: string;
  data?: Record<string, unknown>;
  guild_id?: string;
  channel_id?: string;
  member?: Record<string, unknown>;
  user?: Record<string, unknown>;
  locale?: string;
  guild_locale?: string;
}

interface InteractionResponse {
  type: number;
  data?: Record<string, unknown>;
}

// Configuration
const port = parseInt(process.env.PORT || "8080", 10);
const publicKeyHex = process.env.DISCORD_PUBLIC_KEY;
const projectId = process.env.GOOGLE_CLOUD_PROJECT;
const topicName = process.env.PUBSUB_TOPIC;

if (!publicKeyHex) {
  console.error("DISCORD_PUBLIC_KEY environment variable is required");
  process.exit(1);
}

const publicKey = Buffer.from(publicKeyHex, "hex");

// Pub/Sub client
let pubsubTopic: Topic | null = null;

async function initPubSub(): Promise<void> {
  if (!projectId || !topicName) {
    return;
  }

  try {
    const pubsub = new PubSub({ projectId });
    pubsubTopic = pubsub.topic(topicName);

    // Ensure topic exists (for emulator, create if not exists)
    const [exists] = await pubsubTopic.exists();
    if (!exists) {
      [pubsubTopic] = await pubsub.createTopic(topicName);
    }
  } catch (err) {
    console.warn(`Warning: Failed to initialize Pub/Sub: ${err}`);
  }
}

function validateSignature(
  signature: string,
  timestamp: string,
  body: Buffer
): boolean {
  if (!signature || !timestamp) {
    return false;
  }

  // Decode signature - must be valid hex
  let sigBytes: Uint8Array;
  try {
    // Validate hex string (only valid hex characters)
    if (!/^[0-9a-fA-F]*$/.test(signature)) {
      return false;
    }
    sigBytes = Uint8Array.from(Buffer.from(signature, "hex"));
    // Ed25519 signature must be 64 bytes
    if (sigBytes.length !== 64) {
      return false;
    }
  } catch {
    return false;
  }

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

async function publishToPubSub(interaction: Interaction): Promise<void> {
  if (!pubsubTopic) {
    return;
  }

  // Create sanitized copy (remove sensitive fields)
  const sanitized: Interaction = {
    type: interaction.type,
    id: interaction.id,
    application_id: interaction.application_id,
    // Token is intentionally NOT copied - sensitive data
    data: interaction.data,
    guild_id: interaction.guild_id,
    channel_id: interaction.channel_id,
    member: interaction.member,
    user: interaction.user,
    locale: interaction.locale,
    guild_locale: interaction.guild_locale,
  };

  const attributes: Record<string, string> = {
    interaction_id: interaction.id || "",
    interaction_type: String(interaction.type),
    application_id: interaction.application_id || "",
    guild_id: interaction.guild_id || "",
    channel_id: interaction.channel_id || "",
    timestamp: new Date().toISOString(),
  };

  // Add command name if available
  if (interaction.data && typeof interaction.data.name === "string") {
    attributes.command_name = interaction.data.name;
  }

  try {
    await pubsubTopic.publishMessage({
      data: Buffer.from(JSON.stringify(sanitized)),
      attributes,
    });
  } catch (err) {
    console.error(`Failed to publish to Pub/Sub: ${err}`);
  }
}

// Create Fastify instance
const fastify = Fastify({
  logger: false,
});

// Register raw body parser
fastify.addContentTypeParser(
  "application/json",
  { parseAs: "buffer" },
  (_req, body, done) => {
    done(null, body);
  }
);

// Health check endpoint
fastify.get("/health", async () => {
  return { status: "ok" };
});

// Discord interactions handler
async function handleInteraction(
  request: FastifyRequest<{ Body: Buffer }>,
  reply: FastifyReply
): Promise<void> {
  const body = request.body;

  // Get headers (normalize to string)
  const signature = request.headers["x-signature-ed25519"] as string || "";
  const timestamp = request.headers["x-signature-timestamp"] as string || "";

  // Validate signature
  if (!validateSignature(signature, timestamp, body)) {
    return reply.code(401).send({ error: "invalid signature" });
  }

  // Parse interaction
  let interaction: Interaction;
  try {
    const parsed = JSON.parse(body.toString());
    // Ensure parsed result is a valid object (not null, array, or primitive)
    if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
      return reply.code(400).send({ error: "invalid JSON" });
    }
    interaction = parsed as Interaction;
  } catch {
    return reply.code(400).send({ error: "invalid JSON" });
  }

  // Handle by type
  switch (interaction.type) {
    case INTERACTION_TYPE_PING:
      return reply.code(200).send({ type: RESPONSE_TYPE_PONG } satisfies InteractionResponse);

    case INTERACTION_TYPE_APPLICATION_COMMAND:
      // Publish to Pub/Sub (fire and forget)
      publishToPubSub(interaction);
      return reply.code(200).send({ type: RESPONSE_TYPE_DEFERRED_CHANNEL_MESSAGE } satisfies InteractionResponse);

    default:
      return reply.code(400).send({ error: "unsupported interaction type" });
  }
}

// Register interaction endpoints
fastify.post("/", handleInteraction);
fastify.post("/interactions", handleInteraction);

// Start server
async function start(): Promise<void> {
  await initPubSub();

  try {
    await fastify.listen({ port, host: "0.0.0.0" });
    console.log(`Starting server on port ${port}`);
  } catch (err) {
    console.error(err);
    process.exit(1);
  }
}

start();
