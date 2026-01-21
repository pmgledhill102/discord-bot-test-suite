package com.discord.webhook

import com.google.api.core.ApiFuture
import com.google.api.gax.core.NoCredentialsProvider
import com.google.api.gax.grpc.GrpcTransportChannel
import com.google.api.gax.rpc.FixedTransportChannelProvider
import com.google.cloud.pubsub.v1.Publisher
import com.google.protobuf.ByteString
import com.google.pubsub.v1.PubsubMessage
import com.google.pubsub.v1.TopicName
import io.grpc.ManagedChannelBuilder
import io.ktor.http.*
import io.ktor.serialization.kotlinx.json.*
import io.ktor.server.application.*
import io.ktor.server.engine.*
import io.ktor.server.netty.*
import io.ktor.server.plugins.contentnegotiation.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*
import org.bouncycastle.crypto.params.Ed25519PublicKeyParameters
import org.bouncycastle.crypto.signers.Ed25519Signer
import java.time.Instant
import java.time.format.DateTimeFormatter

// Interaction types
private const val INTERACTION_TYPE_PING = 1
private const val INTERACTION_TYPE_APPLICATION_COMMAND = 2

// Response types
private const val RESPONSE_TYPE_PONG = 1
private const val RESPONSE_TYPE_DEFERRED_CHANNEL_MESSAGE = 5

// Configuration
private val port = System.getenv("PORT")?.toIntOrNull() ?: 8080
private val publicKeyHex = System.getenv("DISCORD_PUBLIC_KEY") ?: ""
private val projectId = System.getenv("GOOGLE_CLOUD_PROJECT") ?: ""
private val topicName = System.getenv("PUBSUB_TOPIC") ?: ""
private val emulatorHost = System.getenv("PUBSUB_EMULATOR_HOST") ?: ""

private val json = Json { ignoreUnknownKeys = true }

// Pub/Sub publisher (lazy initialized)
private val publisher: Publisher? by lazy {
    if (projectId.isNotEmpty() && topicName.isNotEmpty()) {
        try {
            val topic = TopicName.of(projectId, topicName)
            val builder = Publisher.newBuilder(topic)

            // Configure for emulator if specified
            if (emulatorHost.isNotEmpty()) {
                val channel = ManagedChannelBuilder.forTarget(emulatorHost)
                    .usePlaintext()
                    .build()

                builder.setChannelProvider(
                    FixedTransportChannelProvider.create(GrpcTransportChannel.create(channel))
                )
                builder.setCredentialsProvider(NoCredentialsProvider.create())

                println("Pub/Sub configured for emulator: $emulatorHost")
            }

            builder.build()
        } catch (e: Exception) {
            println("Warning: Failed to create Pub/Sub publisher: ${e.message}")
            e.printStackTrace()
            null
        }
    } else {
        null
    }
}

// Public key (lazy initialized)
private val publicKey: Ed25519PublicKeyParameters? by lazy {
    if (publicKeyHex.isEmpty()) {
        null
    } else {
        try {
            val keyBytes = publicKeyHex.hexToByteArray()
            Ed25519PublicKeyParameters(keyBytes, 0)
        } catch (e: Exception) {
            println("Invalid DISCORD_PUBLIC_KEY: ${e.message}")
            null
        }
    }
}

@Serializable
data class InteractionResponse(val type: Int)

@Serializable
data class ErrorResponse(val error: String)

@Serializable
data class HealthResponse(val status: String)

fun main() {
    if (publicKeyHex.isEmpty()) {
        error("DISCORD_PUBLIC_KEY environment variable is required")
    }

    println("Starting server on port $port")

    embeddedServer(Netty, port = port, host = "0.0.0.0") {
        configureRouting()
    }.start(wait = true)
}

fun Application.configureRouting() {
    install(ContentNegotiation) {
        json(json)
    }

    routing {
        get("/health") {
            call.respond(HealthResponse(status = "ok"))
        }

        post("/") {
            handleInteraction(call)
        }

        post("/interactions") {
            handleInteraction(call)
        }
    }
}

private suspend fun handleInteraction(call: ApplicationCall) {
    // Read raw body for signature verification
    val body = call.receiveText()

    // Validate signature
    if (!validateSignature(call, body)) {
        call.respond(HttpStatusCode.Unauthorized, ErrorResponse(error = "invalid signature"))
        return
    }

    // Parse interaction
    val interaction: JsonObject
    try {
        interaction = json.parseToJsonElement(body).jsonObject
    } catch (e: Exception) {
        call.respond(HttpStatusCode.BadRequest, ErrorResponse(error = "invalid JSON"))
        return
    }

    // Get interaction type
    val typeElement = interaction["type"]
    val type = when {
        typeElement == null -> {
            call.respond(HttpStatusCode.BadRequest, ErrorResponse(error = "missing type field"))
            return
        }
        typeElement is JsonNull -> {
            call.respond(HttpStatusCode.BadRequest, ErrorResponse(error = "invalid type"))
            return
        }
        typeElement is JsonPrimitive && typeElement.isString -> {
            call.respond(HttpStatusCode.BadRequest, ErrorResponse(error = "invalid type"))
            return
        }
        typeElement is JsonPrimitive -> {
            typeElement.intOrNull ?: run {
                call.respond(HttpStatusCode.BadRequest, ErrorResponse(error = "invalid type"))
                return
            }
        }
        else -> {
            call.respond(HttpStatusCode.BadRequest, ErrorResponse(error = "invalid type"))
            return
        }
    }

    // Handle by type
    when (type) {
        INTERACTION_TYPE_PING -> handlePing(call)
        INTERACTION_TYPE_APPLICATION_COMMAND -> handleApplicationCommand(call, interaction)
        else -> {
            if (type <= 0) {
                call.respond(HttpStatusCode.BadRequest, ErrorResponse(error = "invalid type"))
            } else {
                call.respond(HttpStatusCode.BadRequest, ErrorResponse(error = "unsupported interaction type"))
            }
        }
    }
}

private fun validateSignature(call: ApplicationCall, body: String): Boolean {
    val signature = call.request.header("X-Signature-Ed25519") ?: return false
    val timestamp = call.request.header("X-Signature-Timestamp") ?: return false

    // Decode signature
    val sigBytes = try {
        signature.hexToByteArray()
    } catch (e: Exception) {
        return false
    }

    // Check timestamp (must be within 5 seconds)
    val ts = timestamp.toLongOrNull() ?: return false
    val now = Instant.now().epochSecond
    if (now - ts > 5) {
        return false
    }

    // Verify signature: sign(timestamp + body)
    val message = (timestamp + body).toByteArray(Charsets.UTF_8)
    val key = publicKey ?: return false

    return try {
        val verifier = Ed25519Signer()
        verifier.init(false, key)
        verifier.update(message, 0, message.size)
        verifier.verifySignature(sigBytes)
    } catch (e: Exception) {
        false
    }
}

private suspend fun handlePing(call: ApplicationCall) {
    // Respond with Pong - do NOT publish to Pub/Sub
    call.respond(InteractionResponse(type = RESPONSE_TYPE_PONG))
}

private suspend fun handleApplicationCommand(call: ApplicationCall, interaction: JsonObject) {
    // Publish to Pub/Sub in background (if configured)
    publisher?.let { pub ->
        call.application.launch(Dispatchers.IO) {
            publishToPubSub(pub, interaction)
        }
    }

    // Respond with deferred response (non-ephemeral)
    call.respond(InteractionResponse(type = RESPONSE_TYPE_DEFERRED_CHANNEL_MESSAGE))
}

private fun publishToPubSub(publisher: Publisher, interaction: JsonObject) {
    try {
        // Create sanitized copy (remove token field)
        val sanitized = buildJsonObject {
            interaction.forEach { (key, value) ->
                if (key != "token") {
                    put(key, value)
                }
            }
        }

        val data = json.encodeToString(sanitized)

        // Build message with attributes
        val attributes = mutableMapOf<String, String>()
        interaction["id"]?.jsonPrimitive?.contentOrNull?.let { attributes["interaction_id"] = it }
        interaction["type"]?.jsonPrimitive?.intOrNull?.let { attributes["interaction_type"] = it.toString() }
        interaction["application_id"]?.jsonPrimitive?.contentOrNull?.let { attributes["application_id"] = it }
        interaction["guild_id"]?.jsonPrimitive?.contentOrNull?.let { attributes["guild_id"] = it }
        interaction["channel_id"]?.jsonPrimitive?.contentOrNull?.let { attributes["channel_id"] = it }
        attributes["timestamp"] = DateTimeFormatter.ISO_INSTANT.format(Instant.now())

        // Add command name if available
        interaction["data"]?.jsonObject?.get("name")?.jsonPrimitive?.contentOrNull?.let {
            attributes["command_name"] = it
        }

        val message = PubsubMessage.newBuilder()
            .setData(ByteString.copyFromUtf8(data))
            .putAllAttributes(attributes)
            .build()

        val future: ApiFuture<String> = publisher.publish(message)
        future.get() // Wait for publish to complete
    } catch (e: Exception) {
        println("Failed to publish to Pub/Sub: ${e.message}")
    }
}

// Extension function to convert hex string to byte array
private fun String.hexToByteArray(): ByteArray {
    check(length % 2 == 0) { "Hex string must have even length" }
    return chunked(2)
        .map { it.toInt(16).toByte() }
        .toByteArray()
}
