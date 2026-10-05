# Cloud Run jobs. The names are the contract with the backend repo
# (fpl-ingest, fpl-train, fpl-predict, fpl-optimise, fpl-notify).
#
# Everything scales to zero: jobs only cost while they run. Never add an always-on resource.
#
# Jobs are created with a Google sample image. GitHub Actions replaces it with the real
# image (tagged with the git SHA) on every deploy, so Terraform ignores image changes.

locals {
  placeholder_job_image = "us-docker.pkg.dev/cloudrun/container/job:latest"

  # fpl-train is the heaviest: it builds features for five seasons and fits two models.
  jobs = {
    fpl-ingest   = { cpu = "1", memory = "1Gi", timeout = "600s" }
    fpl-train    = { cpu = "2", memory = "4Gi", timeout = "1800s" }
    fpl-predict  = { cpu = "1", memory = "2Gi", timeout = "900s" }
    fpl-optimise = { cpu = "1", memory = "1Gi", timeout = "600s" }
    fpl-notify   = { cpu = "1", memory = "512Mi", timeout = "300s" }
  }

  # Environment variables backed by Secret Manager, per job (most jobs have none).
  job_secrets = {
    fpl-notify = { TELEGRAM_BOT_TOKEN = google_secret_manager_secret.telegram.secret_id }
  }

  # The per-gameweek pipeline, in order. fpl-train runs on its own schedule instead.
  pipeline_order = ["fpl-ingest", "fpl-predict", "fpl-optimise", "fpl-notify"]

  common_env = merge(
    {
      GCP_PROJECT_ID = var.project_id
      GCP_REGION     = var.region
      DATA_BUCKET    = google_storage_bucket.data.name
      LOG_LEVEL      = "INFO"
      USERS_BACKEND  = var.users_backend
    },
    var.fpl_team_id == null ? {} : { FPL_TEAM_ID = tostring(var.fpl_team_id) },
    var.telegram_chat_id == null ? {} : { TELEGRAM_CHAT_ID = tostring(var.telegram_chat_id) },
  )
}

resource "google_cloud_run_v2_job" "job" {
  for_each = local.jobs

  name                = each.key
  location            = var.region
  deletion_protection = var.deletion_protection

  template {
    task_count = 1

    template {
      service_account = google_service_account.runtime.email
      max_retries     = 1
      timeout         = each.value.timeout

      containers {
        image = local.placeholder_job_image

        resources {
          limits = {
            cpu    = each.value.cpu
            memory = each.value.memory
          }
        }

        dynamic "env" {
          for_each = local.common_env
          content {
            name  = env.key
            value = env.value
          }
        }

        dynamic "env" {
          for_each = try(local.job_secrets[each.key], {})
          content {
            name = env.key
            value_source {
              secret_key_ref {
                secret  = env.value
                version = "latest"
              }
            }
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].template[0].containers[0].image,
      client,
      client_version,
    ]
  }

  depends_on = [
    google_project_service.api,
    google_secret_manager_secret_version.telegram_placeholder,
    google_secret_manager_secret_iam_member.runtime_reads_telegram,
    google_storage_bucket_iam_member.runtime_data,
  ]
}
