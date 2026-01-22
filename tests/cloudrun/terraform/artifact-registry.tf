# Artifact Registry repository for service images

resource "google_artifact_registry_repository" "discord_services" {
  location      = var.region
  repository_id = "discord-services"
  description   = "Container images for Discord bot benchmark services"
  format        = "DOCKER"

  # Cleanup policies to manage storage costs
  # Note: These apply at repository level, not per-image
  cleanup_policies {
    id     = "keep-latest-tag"
    action = "KEEP"
    condition {
      tag_state    = "TAGGED"
      tag_prefixes = ["latest"]
    }
  }

  cleanup_policies {
    id     = "keep-recent-versions"
    action = "KEEP"
    most_recent_versions {
      keep_count = var.ar_cleanup_keep_count
    }
  }

  cleanup_policies {
    id     = "delete-old-untagged"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "${var.ar_cleanup_untagged_days * 24 * 60 * 60}s"
    }
  }

  depends_on = [google_project_service.apis["artifactregistry.googleapis.com"]]
}
