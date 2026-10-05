locals {
  data_bucket = var.data_bucket_name != "" ? var.data_bucket_name : "${var.project_id}-fpl-data"
}

# Parquet data (season=<s>/gw=<n>/...), the model registry (models/...) and monitoring.
# Contains snapshots that cannot be recreated (FPL's pre-deadline ep_next), so versioning is
# on; superseded versions are deleted after 30 days to keep storage in the free tier.
resource "google_storage_bucket" "data" {
  name                        = local.data_bucket
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      days_since_noncurrent_time = 30
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.api]
}
