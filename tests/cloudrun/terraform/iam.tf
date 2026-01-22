# Service account and IAM bindings for Cloud Run benchmark

resource "google_service_account" "cloudrun_benchmark" {
  account_id   = "cloudrun-benchmark"
  display_name = "Cloud Run Benchmark Service Account"
  description  = "Service account for Cloud Run cold start benchmark tool"

  depends_on = [google_project_service.apis["iam.googleapis.com"]]
}

# Roles required for the benchmark tool
locals {
  benchmark_roles = [
    "roles/run.admin",               # Deploy and manage Cloud Run services
    "roles/artifactregistry.writer", # Push images to AR
    "roles/pubsub.admin",            # Create topics/subscriptions for testing
    "roles/iam.serviceAccountUser",  # Act as service accounts (for Cloud Run)
  ]
}

resource "google_project_iam_member" "benchmark_roles" {
  for_each = toset(local.benchmark_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloudrun_benchmark.email}"
}
