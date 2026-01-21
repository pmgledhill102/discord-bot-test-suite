//! Discord webhook service implementation using Rust and Actix-web.
//!
//! This service handles Discord interactions webhooks:
//! - Validates Ed25519 signatures on incoming requests
//! - Responds to Ping (type=1) with Pong (type=1)
//! - Responds to Slash commands (type=2) with Deferred (type=5)
//! - Publishes sanitized slash command payloads to Pub/Sub

use actix_web::{web, App, HttpRequest, HttpResponse, HttpServer};
use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use chrono::Utc;
use ed25519_dalek::{Signature, VerifyingKey};
use serde::Deserialize;
use serde_json::{json, Value};
use std::env;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

// Interaction types
const INTERACTION_TYPE_PING: i64 = 1;
const INTERACTION_TYPE_APPLICATION_COMMAND: i64 = 2;

// Response types
const RESPONSE_TYPE_PONG: i64 = 1;
const RESPONSE_TYPE_DEFERRED_CHANNEL_MESSAGE: i64 = 5;

/// Application state shared across handlers
struct AppState {
    public_key: VerifyingKey,
    pubsub_topic: Option<String>,
    project_id: Option<String>,
    pubsub_emulator_host: Option<String>,
    http_client: reqwest::Client,
}

/// Discord interaction request (partial, for type detection)
#[derive(Deserialize)]
#[allow(dead_code)]
struct Interaction {
    #[serde(rename = "type")]
    interaction_type: i64,
}

/// Create a JSON error response
fn error_response(status: u16, error: &str) -> HttpResponse {
    let body = json!({ "error": error });
    match status {
        400 => HttpResponse::BadRequest().json(body),
        401 => HttpResponse::Unauthorized().json(body),
        _ => HttpResponse::InternalServerError().json(body),
    }
}

/// Validate Discord Ed25519 signature
fn validate_signature(
    public_key: &VerifyingKey,
    signature_hex: &str,
    timestamp: &str,
    body: &str,
) -> bool {
    // Check timestamp (must be within 5 seconds)
    let ts: i64 = match timestamp.parse() {
        Ok(t) => t,
        Err(_) => return false,
    };

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);

    if now - ts > 5 {
        return false;
    }

    // Decode signature from hex
    let signature_bytes = match hex::decode(signature_hex) {
        Ok(bytes) => bytes,
        Err(_) => return false,
    };

    let signature = match Signature::try_from(signature_bytes.as_slice()) {
        Ok(sig) => sig,
        Err(_) => return false,
    };

    // Verify signature: verify(timestamp + body)
    let message = format!("{}{}", timestamp, body);

    use ed25519_dalek::Verifier;
    public_key.verify(message.as_bytes(), &signature).is_ok()
}

/// Sanitize interaction for Pub/Sub (remove sensitive fields like token)
fn sanitize_interaction(interaction: &Value) -> Value {
    let mut sanitized = json!({});

    // Copy safe fields only (explicitly exclude "token")
    let safe_fields = [
        "type",
        "id",
        "application_id",
        "data",
        "guild_id",
        "channel_id",
        "member",
        "user",
        "locale",
        "guild_locale",
    ];

    if let Value::Object(obj) = interaction {
        for field in safe_fields {
            if let Some(value) = obj.get(field) {
                sanitized[field] = value.clone();
            }
        }
    }

    sanitized
}

/// Publish interaction to Pub/Sub emulator via REST API
async fn publish_to_pubsub(state: &AppState, interaction: &Value) {
    let (topic, project, emulator_host) = match (
        &state.pubsub_topic,
        &state.project_id,
        &state.pubsub_emulator_host,
    ) {
        (Some(t), Some(p), Some(h)) => (t, p, h),
        _ => return,
    };

    let sanitized = sanitize_interaction(interaction);

    // Base64 encode the JSON data
    let json_str = serde_json::to_string(&sanitized).unwrap_or_default();
    let base64_data = BASE64.encode(json_str.as_bytes());

    // Build attributes
    let mut attributes = serde_json::Map::new();
    if let Some(id) = sanitized.get("id").and_then(|v| v.as_str()) {
        attributes.insert("interaction_id".to_string(), json!(id));
    }
    if let Some(t) = sanitized.get("type").and_then(|v| v.as_i64()) {
        attributes.insert("interaction_type".to_string(), json!(t.to_string()));
    }
    if let Some(app_id) = sanitized.get("application_id").and_then(|v| v.as_str()) {
        attributes.insert("application_id".to_string(), json!(app_id));
    }
    if let Some(guild_id) = sanitized.get("guild_id").and_then(|v| v.as_str()) {
        attributes.insert("guild_id".to_string(), json!(guild_id));
    }
    if let Some(channel_id) = sanitized.get("channel_id").and_then(|v| v.as_str()) {
        attributes.insert("channel_id".to_string(), json!(channel_id));
    }
    if let Some(data) = sanitized.get("data") {
        if let Some(name) = data.get("name").and_then(|v| v.as_str()) {
            attributes.insert("command_name".to_string(), json!(name));
        }
    }
    attributes.insert("timestamp".to_string(), json!(Utc::now().to_rfc3339()));

    // Build Pub/Sub REST API request body
    let request_body = json!({
        "messages": [{
            "data": base64_data,
            "attributes": attributes
        }]
    });

    // URL: http://{emulator}/v1/projects/{project}/topics/{topic}:publish
    let url = format!(
        "http://{}/v1/projects/{}/topics/{}:publish",
        emulator_host, project, topic
    );

    // Send POST request
    match state
        .http_client
        .post(&url)
        .json(&request_body)
        .send()
        .await
    {
        Ok(resp) => {
            if resp.status().is_success() {
                log::info!("Published to Pub/Sub successfully");
            } else {
                let status = resp.status();
                let body = resp.text().await.unwrap_or_default();
                log::error!("Pub/Sub publish failed: HTTP {} - {}", status, body);
            }
        }
        Err(e) => {
            log::error!("Pub/Sub publish failed: {}", e);
        }
    }
}

/// Handle Ping interaction
fn handle_ping() -> HttpResponse {
    HttpResponse::Ok().json(json!({ "type": RESPONSE_TYPE_PONG }))
}

/// Handle Application Command (slash command)
async fn handle_application_command(state: &AppState, interaction: Value) -> HttpResponse {
    // Spawn Pub/Sub publish in background
    let state_topic = state.pubsub_topic.clone();
    let state_project = state.project_id.clone();
    let state_emulator = state.pubsub_emulator_host.clone();
    let http_client = state.http_client.clone();

    if state_topic.is_some() && state_project.is_some() && state_emulator.is_some() {
        let interaction_clone = interaction.clone();
        tokio::spawn(async move {
            let temp_state = AppState {
                public_key: VerifyingKey::from_bytes(&[0u8; 32]).unwrap(), // Dummy, not used
                pubsub_topic: state_topic,
                project_id: state_project,
                pubsub_emulator_host: state_emulator,
                http_client,
            };
            publish_to_pubsub(&temp_state, &interaction_clone).await;
        });
    }

    // Respond with deferred response (non-ephemeral)
    HttpResponse::Ok().json(json!({ "type": RESPONSE_TYPE_DEFERRED_CHANNEL_MESSAGE }))
}

/// Main interaction handler
async fn handle_interaction(
    req: HttpRequest,
    body: web::Bytes,
    state: web::Data<Arc<AppState>>,
) -> HttpResponse {
    // Get signature headers
    let signature = req
        .headers()
        .get("X-Signature-Ed25519")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");

    let timestamp = req
        .headers()
        .get("X-Signature-Timestamp")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");

    let body_str = match std::str::from_utf8(&body) {
        Ok(s) => s,
        Err(_) => return error_response(400, "invalid body encoding"),
    };

    // Validate signature
    if !validate_signature(&state.public_key, signature, timestamp, body_str) {
        return error_response(401, "invalid signature");
    }

    // Parse JSON
    let interaction: Value = match serde_json::from_str(body_str) {
        Ok(v) => v,
        Err(_) => return error_response(400, "invalid JSON"),
    };

    // Ensure interaction is an object (not null, array, or primitive)
    if !interaction.is_object() {
        return error_response(400, "invalid JSON");
    }

    // Get interaction type
    let interaction_type = match interaction.get("type").and_then(|t| t.as_i64()) {
        Some(t) => t,
        None => return error_response(400, "unsupported interaction type"),
    };

    // Handle by type
    match interaction_type {
        INTERACTION_TYPE_PING => handle_ping(),
        INTERACTION_TYPE_APPLICATION_COMMAND => {
            handle_application_command(&state, interaction).await
        }
        _ => error_response(400, "unsupported interaction type"),
    }
}

/// Health check handler
async fn health_check() -> HttpResponse {
    HttpResponse::Ok().json(json!({ "status": "ok" }))
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    env_logger::init();

    // Load configuration from environment
    let port: u16 = env::var("PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(8080);

    let public_key_hex = env::var("DISCORD_PUBLIC_KEY")
        .expect("DISCORD_PUBLIC_KEY environment variable is required");

    let public_key_bytes = hex::decode(&public_key_hex).expect("Invalid DISCORD_PUBLIC_KEY format");

    let public_key_array: [u8; 32] = public_key_bytes
        .try_into()
        .expect("Invalid DISCORD_PUBLIC_KEY length");

    let public_key =
        VerifyingKey::from_bytes(&public_key_array).expect("Invalid DISCORD_PUBLIC_KEY");

    // Optional Pub/Sub configuration
    let project_id = env::var("GOOGLE_CLOUD_PROJECT").ok();
    let pubsub_topic = env::var("PUBSUB_TOPIC").ok();
    let pubsub_emulator_host = env::var("PUBSUB_EMULATOR_HOST").ok();

    // Create HTTP client for Pub/Sub REST API
    let http_client = reqwest::Client::new();

    if let (Some(ref host), Some(ref proj), Some(ref topic)) =
        (&pubsub_emulator_host, &project_id, &pubsub_topic)
    {
        println!(
            "Pub/Sub configured: {} project={} topic={}",
            host, proj, topic
        );
    }

    let state = Arc::new(AppState {
        public_key,
        pubsub_topic,
        project_id,
        pubsub_emulator_host,
        http_client,
    });

    println!("Starting server on port {}", port);

    HttpServer::new(move || {
        App::new()
            .app_data(web::Data::new(state.clone()))
            .route("/health", web::get().to(health_check))
            .route("/", web::post().to(handle_interaction))
            .route("/interactions", web::post().to(handle_interaction))
    })
    .bind(("0.0.0.0", port))?
    .run()
    .await
}
