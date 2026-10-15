# The original europe-west2 repo (formerly google_artifact_registry_repository.images) is
# released without being destroyed, so its images remain for a rollback. Delete it by hand
# with the old jobs once the europe-west1 deploy works.
removed {
  from = google_artifact_registry_repository.images

  lifecycle {
    destroy = false
  }
}

# Next to the jobs: pulling 300+ MB images across regions on every run would cost egress.
resource "google_artifact_registry_repository" "run_images" {
  repository_id = var.artifact_registry_repo_id
  location      = var.run_region
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
