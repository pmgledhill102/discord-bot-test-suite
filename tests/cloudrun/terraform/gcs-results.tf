# GCS bucket for benchmark results storage
#
# Stores JSON and Markdown reports from benchmark runs for later analysis.

# =============================================================================
# GCS Bucket
# =============================================================================

resource "google_storage_bucket" "benchmark_results" {
  name     = "${var.project_id}-benchmark-results"
  location = var.region

  # Use standard storage class for frequent access
  storage_class = "STANDARD"

  # Enable versioning for result history
  versioning {
    enabled = true
  }

  # Lifecycle rule: delete old versions after 90 days
  lifecycle_rule {
    condition {
      age                = 90
      num_newer_versions = 5
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  # Uniform bucket-level access (recommended)
  uniform_bucket_level_access = true

  depends_on = [
    google_project_service.apis["storage.googleapis.com"],
  ]
}

# =============================================================================
# IAM: Benchmark SA can write results
# =============================================================================

resource "google_storage_bucket_iam_member" "benchmark_writer" {
  bucket = google_storage_bucket.benchmark_results.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.cloudrun_benchmark.email}"
}

# Also grant read access for listing/reading previous results
resource "google_storage_bucket_iam_member" "benchmark_reader" {
  bucket = google_storage_bucket.benchmark_results.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.cloudrun_benchmark.email}"
}

# =============================================================================
# IAM: Claude SA can read results for debugging
# =============================================================================

resource "google_storage_bucket_iam_member" "claude_reader" {
  count = var.claude_service_account_email != "" ? 1 : 0

  bucket = google_storage_bucket.benchmark_results.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${var.claude_service_account_email}"
}
