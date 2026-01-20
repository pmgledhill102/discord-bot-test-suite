/**
 * Discord webhook service implementation using C++ and Drogon.
 *
 * This service handles Discord interactions webhooks:
 * - Validates Ed25519 signatures on incoming requests
 * - Responds to Ping (type=1) with Pong (type=1)
 * - Responds to Slash commands (type=2) with Deferred (type=5)
 * - Publishes sanitized slash command payloads to Pub/Sub
 */

#include <drogon/drogon.h>
#include <sodium.h>

#include <chrono>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

using namespace drogon;

// Interaction types
constexpr int INTERACTION_TYPE_PING = 1;
constexpr int INTERACTION_TYPE_APPLICATION_COMMAND = 2;

// Response types
constexpr int RESPONSE_TYPE_PONG = 1;
constexpr int RESPONSE_TYPE_DEFERRED_CHANNEL_MESSAGE = 5;

// Global configuration
std::vector<unsigned char> g_public_key;
std::string g_pubsub_topic;
std::string g_project_id;

/**
 * Convert hex string to bytes
 */
std::vector<unsigned char> hexToBytes(const std::string& hex) {
    std::vector<unsigned char> bytes;
    bytes.reserve(hex.length() / 2);
    for (size_t i = 0; i < hex.length(); i += 2) {
        unsigned char byte = static_cast<unsigned char>(
            std::stoi(hex.substr(i, 2), nullptr, 16));
        bytes.push_back(byte);
    }
    return bytes;
}

/**
 * Validate Discord Ed25519 signature
 */
bool validateSignature(const std::string& signature_hex,
                       const std::string& timestamp,
                       const std::string& body) {
    if (signature_hex.empty() || timestamp.empty() || g_public_key.empty()) {
        return false;
    }

    // Check timestamp (must be within 5 seconds)
    try {
        int64_t ts = std::stoll(timestamp);
        auto now = std::chrono::system_clock::now();
        auto epoch = now.time_since_epoch();
        auto seconds = std::chrono::duration_cast<std::chrono::seconds>(epoch).count();
        if (seconds - ts > 5) {
            return false;
        }
    } catch (...) {
        return false;
    }

    // Decode signature
    std::vector<unsigned char> signature;
    try {
        signature = hexToBytes(signature_hex);
    } catch (...) {
        return false;
    }

    if (signature.size() != crypto_sign_BYTES) {
        return false;
    }

    // Verify signature: verify(timestamp + body)
    std::string message = timestamp + body;

    int result = crypto_sign_verify_detached(
        signature.data(),
        reinterpret_cast<const unsigned char*>(message.data()),
        message.size(),
        g_public_key.data());

    return result == 0;
}

/**
 * Create JSON error response
 */
HttpResponsePtr errorResponse(int status, const std::string& error) {
    Json::Value json;
    json["error"] = error;
    auto resp = HttpResponse::newHttpJsonResponse(json);
    resp->setStatusCode(static_cast<HttpStatusCode>(status));
    return resp;
}

/**
 * Sanitize interaction for Pub/Sub (remove sensitive fields)
 */
Json::Value sanitizeInteraction(const Json::Value& interaction) {
    Json::Value sanitized;

    // Copy safe fields only (explicitly exclude "token")
    if (interaction.isMember("type")) sanitized["type"] = interaction["type"];
    if (interaction.isMember("id")) sanitized["id"] = interaction["id"];
    if (interaction.isMember("application_id")) sanitized["application_id"] = interaction["application_id"];
    if (interaction.isMember("data")) sanitized["data"] = interaction["data"];
    if (interaction.isMember("guild_id")) sanitized["guild_id"] = interaction["guild_id"];
    if (interaction.isMember("channel_id")) sanitized["channel_id"] = interaction["channel_id"];
    if (interaction.isMember("member")) sanitized["member"] = interaction["member"];
    if (interaction.isMember("user")) sanitized["user"] = interaction["user"];
    if (interaction.isMember("locale")) sanitized["locale"] = interaction["locale"];
    if (interaction.isMember("guild_locale")) sanitized["guild_locale"] = interaction["guild_locale"];

    return sanitized;
}

/**
 * Publish interaction to Pub/Sub (placeholder - would need google-cloud-cpp)
 */
void publishToPubSub(const Json::Value& interaction) {
    if (g_pubsub_topic.empty() || g_project_id.empty()) {
        return;
    }

    Json::Value sanitized = sanitizeInteraction(interaction);

    // Log for now - full Pub/Sub implementation would use google-cloud-cpp
    LOG_INFO << "Would publish to Pub/Sub: " << sanitized.toStyledString();
}

/**
 * Handle Ping interaction
 */
HttpResponsePtr handlePing() {
    Json::Value response;
    response["type"] = RESPONSE_TYPE_PONG;
    return HttpResponse::newHttpJsonResponse(response);
}

/**
 * Handle Application Command (slash command)
 */
HttpResponsePtr handleApplicationCommand(const Json::Value& interaction) {
    // Publish to Pub/Sub in background
    std::thread([interaction]() {
        publishToPubSub(interaction);
    }).detach();

    // Respond with deferred response (non-ephemeral)
    Json::Value response;
    response["type"] = RESPONSE_TYPE_DEFERRED_CHANNEL_MESSAGE;
    return HttpResponse::newHttpJsonResponse(response);
}

/**
 * Main interaction handler
 */
void handleInteraction(const HttpRequestPtr& req,
                       std::function<void(const HttpResponsePtr&)>&& callback) {
    // Get signature headers
    std::string signature = req->getHeader("X-Signature-Ed25519");
    std::string timestamp = req->getHeader("X-Signature-Timestamp");
    std::string body = std::string(req->body());

    // Validate signature
    if (!validateSignature(signature, timestamp, body)) {
        callback(errorResponse(401, "invalid signature"));
        return;
    }

    // Parse JSON
    Json::Value interaction;
    Json::CharReaderBuilder builder;
    std::string errors;
    std::istringstream stream(body);

    if (!Json::parseFromStream(builder, stream, &interaction, &errors)) {
        callback(errorResponse(400, "invalid JSON"));
        return;
    }

    // Ensure interaction is an object (not null, array, or primitive)
    if (!interaction.isObject()) {
        callback(errorResponse(400, "invalid JSON"));
        return;
    }

    // Get interaction type
    if (!interaction.isMember("type") || !interaction["type"].isInt()) {
        callback(errorResponse(400, "unsupported interaction type"));
        return;
    }

    int interactionType = interaction["type"].asInt();

    // Handle by type
    switch (interactionType) {
        case INTERACTION_TYPE_PING:
            callback(handlePing());
            break;
        case INTERACTION_TYPE_APPLICATION_COMMAND:
            callback(handleApplicationCommand(interaction));
            break;
        default:
            callback(errorResponse(400, "unsupported interaction type"));
            break;
    }
}

/**
 * Health check handler
 */
void healthCheck(const HttpRequestPtr& req,
                 std::function<void(const HttpResponsePtr&)>&& callback) {
    Json::Value json;
    json["status"] = "ok";
    callback(HttpResponse::newHttpJsonResponse(json));
}

int main() {
    // Initialize libsodium
    if (sodium_init() < 0) {
        std::cerr << "Failed to initialize libsodium" << std::endl;
        return 1;
    }

    // Load configuration from environment
    const char* port_str = std::getenv("PORT");
    int port = port_str ? std::atoi(port_str) : 8080;

    const char* public_key_hex = std::getenv("DISCORD_PUBLIC_KEY");
    if (!public_key_hex) {
        std::cerr << "DISCORD_PUBLIC_KEY environment variable is required" << std::endl;
        return 1;
    }

    try {
        g_public_key = hexToBytes(public_key_hex);
        if (g_public_key.size() != crypto_sign_PUBLICKEYBYTES) {
            std::cerr << "Invalid DISCORD_PUBLIC_KEY length" << std::endl;
            return 1;
        }
    } catch (...) {
        std::cerr << "Invalid DISCORD_PUBLIC_KEY format" << std::endl;
        return 1;
    }

    // Optional Pub/Sub configuration
    const char* project_id = std::getenv("GOOGLE_CLOUD_PROJECT");
    const char* topic_name = std::getenv("PUBSUB_TOPIC");
    if (project_id) g_project_id = project_id;
    if (topic_name) g_pubsub_topic = topic_name;

    // Configure routes
    app().registerHandler("/health", &healthCheck, {Get});
    app().registerHandler("/", &handleInteraction, {Post});
    app().registerHandler("/interactions", &handleInteraction, {Post});

    // Start server
    std::cout << "Starting server on port " << port << std::endl;
    app().addListener("0.0.0.0", port);
    app().run();

    return 0;
}
