# Cloud Run Job for benchmark execution
#
# This job runs the benchmark tool in a containerized environment within GCP,
# providing consistent same-region latency measurements.

# =============================================================================
# Cloud Run Job
# =============================================================================

resource "google_cloud_run_v2_job" "benchmark" {
  name     = "cloudrun-benchmark"
  location = var.region

  template {
    template {
      containers {
        image = "${var.region}-docker.pkg.dev/${var.project_id}/discord-services/cloudrun-benchmark:latest"

        resources {
          limits = {
            cpu    = "2"
            memory = "1Gi"
          }
        }

        env {
          name  = "PROJECT_ID"
          value = var.project_id
        }
        env {
          name  = "REGION"
          value = var.region
        }
        env {
          name  = "GCS_RESULTS_BUCKET"
          value = google_storage_bucket.benchmark_results.name
        }
      }

      # 1 hour max timeout for full benchmark runs
      timeout = "3600s"

      # Use the benchmark service account
      service_account = google_service_account.cloudrun_benchmark.email
    }
  }

  depends_on = [
    google_project_service.apis["run.googleapis.com"],
  ]
}

# =============================================================================
# Cloud Scheduler for Daily Benchmark Runs
# =============================================================================

resource "google_cloud_scheduler_job" "benchmark_daily" {
  name        = "benchmark-daily-full"
  description = "Daily full benchmark run at 01:17 UTC"
  region      = var.region

  # Run at 01:17 UTC daily (unusual time to avoid contention)
  schedule  = "17 1 * * *"
  time_zone = "UTC"

  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_id}/jobs/${google_cloud_run_v2_job.benchmark.name}:run"

    oauth_token {
      service_account_email = google_service_account.cloudrun_benchmark.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }

  # Retry configuration
  retry_config {
    retry_count          = 1
    max_retry_duration   = "0s"
    min_backoff_duration = "5s"
    max_backoff_duration = "60s"
  }

  depends_on = [
    google_project_service.apis["cloudscheduler.googleapis.com"],
    google_cloud_run_v2_job.benchmark,
  ]
}

# =============================================================================
# IAM: Allow scheduler to invoke the job
# =============================================================================

resource "google_cloud_run_v2_job_iam_member" "scheduler_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.benchmark.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.cloudrun_benchmark.email}"
}
