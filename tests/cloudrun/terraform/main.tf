# Terraform configuration for Cloud Run benchmark infrastructure
#
# This manages the core GCP infrastructure for the benchmark tool:
# - API enablement
# - Artifact Registry repository
# - Service account and IAM bindings
# - Workload Identity Federation for GitHub Actions

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    bucket = "cloud-run-test-suite-terraform-state"
    prefix = "cloudrun-benchmark"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
