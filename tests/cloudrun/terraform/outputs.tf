# Outputs for use in GitHub Actions and other configurations

output "workload_identity_provider" {
  description = "Workload Identity Provider resource name for GitHub Actions"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "service_account_email" {
  description = "CI/CD service account email for Cloud Run benchmark"
  value       = google_service_account.cloudrun_benchmark.email
}

output "runtime_service_account_email" {
  description = "Runtime service account email for Cloud Run services"
  value       = google_service_account.cloudrun_runtime.email
}

output "artifact_registry_url" {
  description = "Artifact Registry repository URL"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.discord_services.repository_id}"
}

output "project_id" {
  description = "GCP project ID"
  value       = var.project_id
}

output "region" {
  description = "GCP region"
  value       = var.region
}

output "benchmark_results_bucket" {
  description = "GCS bucket for benchmark results"
  value       = google_storage_bucket.benchmark_results.name
}
