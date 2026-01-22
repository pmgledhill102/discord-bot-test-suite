# Input variables for the Cloud Run benchmark infrastructure

variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region for resources"
  type        = string
  default     = "europe-west1"
}

variable "github_org" {
  description = "GitHub organization name"
  type        = string
  default     = "pmgledhill102"
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "discord-bot-test-suite"
}

variable "ar_cleanup_keep_count" {
  description = "Number of tagged versions to keep per image in Artifact Registry"
  type        = number
  default     = 5
}

variable "ar_cleanup_untagged_days" {
  description = "Days after which untagged images are deleted"
  type        = number
  default     = 7
}

variable "claude_service_account_email" {
  description = "Service account email for Claude Code (grants read access to benchmark results)"
  type        = string
  default     = ""
}
