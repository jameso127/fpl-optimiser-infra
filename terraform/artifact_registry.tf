resource "google_artifact_registry_repository" "images" {
  repository_id = var.artifact_registry_repo_id
  location      = var.region
  format        = "DOCKER"
  description   = "Images for the FPL optimiser jobs and API, tagged with the git SHA."

  # Keep storage inside the free tier: the newest N versions of each image survive, anything
  # older than 30 days that is not among them is deleted.
  cleanup_policy_dry_run = false

  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = var.image_keep_count
    }
  }

  cleanup_policies {
    id     = "delete-old"
    action = "DELETE"
    condition {
      older_than = "2592000s"
    }
  }

  depends_on = [google_project_service.api]
}
