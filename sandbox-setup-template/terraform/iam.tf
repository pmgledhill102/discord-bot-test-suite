# Service account for the sandbox VM
# Deliberately limited permissions - sandbox should have minimal GCP access
resource "google_service_account" "sandbox" {
  account_id   = "${var.vm_name}-sa"
  display_name = "Claude Sandbox Service Account"
  description  = "Limited permissions service account for Claude Code sandbox VM"
}

# Minimal permissions for the sandbox
# Add more as needed for your specific use case

# Read container images from Artifact Registry
resource "google_project_iam_member" "artifact_registry_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.sandbox.email}"
}

# Write logs to Cloud Logging
resource "google_project_iam_member" "logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.sandbox.email}"
}

# Write metrics to Cloud Monitoring
resource "google_project_iam_member" "monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.sandbox.email}"
}

# Access specific secrets (API keys, etc.)
# This grants access to secrets with the "claude-sandbox" label only
resource "google_secret_manager_secret_iam_member" "api_key_access" {
  count     = var.create_api_key_secret ? 1 : 0
  project   = var.project_id
  secret_id = google_secret_manager_secret.anthropic_api_key[0].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.sandbox.email}"
}

# Optional: Pub/Sub publisher for agent coordination
# resource "google_project_iam_member" "pubsub_publisher" {
#   project = var.project_id
#   role    = "roles/pubsub.publisher"
#   member  = "serviceAccount:${google_service_account.sandbox.email}"
# }

# Optional: Cloud Storage access for shared assets
# resource "google_storage_bucket_iam_member" "assets_reader" {
#   bucket = google_storage_bucket.assets.name
#   role   = "roles/storage.objectViewer"
#   member = "serviceAccount:${google_service_account.sandbox.email}"
# }

# Secret for Anthropic API key
variable "create_api_key_secret" {
  description = "Create a Secret Manager secret for the Anthropic API key"
  type        = bool
  default     = true
}

resource "google_secret_manager_secret" "anthropic_api_key" {
  count     = var.create_api_key_secret ? 1 : 0
  secret_id = "anthropic-api-key"

  labels = var.labels

  replication {
    auto {}
  }
}

# Note: You'll need to add the secret value manually:
# gcloud secrets versions add anthropic-api-key --data-file=- <<< "your-api-key"
