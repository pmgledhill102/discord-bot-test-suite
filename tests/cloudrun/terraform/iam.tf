# Service accounts and IAM bindings for Cloud Run benchmark
#
# Two service accounts with distinct responsibilities:
# 1. cloudrun-benchmark: CI/CD operations (GitHub Actions + terminal)
# 2. cloudrun-runtime: Runtime identity for Cloud Run services

# =============================================================================
# CI/CD Service Account (GitHub Actions + Terminal)
# =============================================================================

resource "google_service_account" "cloudrun_benchmark" {
  account_id   = "cloudrun-benchmark"
  display_name = "Cloud Run Benchmark CI/CD"
  description  = "CI/CD operations: deploy services, push/query images, view logs"

  depends_on = [google_project_service.apis["iam.googleapis.com"]]
}

locals {
  benchmark_roles = [
    "roles/run.admin",               # Deploy and manage Cloud Run services
    "roles/run.invoker",             # Invoke Cloud Run services (IAM-authenticated)
    "roles/artifactregistry.writer", # Push images to AR
    "roles/artifactregistry.reader", # Query/list images in AR
    "roles/pubsub.admin",            # Create test topics/subscriptions
    "roles/logging.viewer",          # View Cloud Run logs
    "roles/monitoring.viewer",       # View metrics and dashboards
    "roles/iam.serviceAccountUser",  # Impersonate runtime SA for deployments
  ]
}

resource "google_project_iam_member" "benchmark_roles" {
  for_each = toset(local.benchmark_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloudrun_benchmark.email}"
}

# =============================================================================
# Runtime Service Account (Cloud Run Services)
# =============================================================================

resource "google_service_account" "cloudrun_runtime" {
  account_id   = "cloudrun-runtime"
  display_name = "Cloud Run Runtime"
  description  = "Runtime identity for Cloud Run services (minimal permissions)"

  depends_on = [google_project_service.apis["iam.googleapis.com"]]
}

locals {
  runtime_roles = [
    "roles/pubsub.publisher", # Publish messages to Pub/Sub topics
  ]
}

resource "google_project_iam_member" "runtime_roles" {
  for_each = toset(local.runtime_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloudrun_runtime.email}"
}
