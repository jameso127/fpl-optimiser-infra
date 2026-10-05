# Cloud Run jobs and the API service. The names are the contract with the backend repo
# (fpl-ingest, fpl-train, fpl-predict, fpl-optimise, fpl-notify, fpl-api).
#
# Everything scales to zero: jobs only cost while they run, and the API has no minimum
# instances and only gets CPU while handling a request. Never add an always-on resource.
#
# Resources are created with a Google sample image. GitHub Actions replaces it with the real
# image (tagged with the git SHA) on every deploy, so Terraform ignores image changes.

locals {
  placeholder_job_image     = "us-docker.pkg.dev/cloudrun/container/job:latest"
  placeholder_service_image = "us-docker.pkg.dev/cloudrun/container/hello:latest"

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
    fpl-notify = { RESEND_API_KEY = google_secret_manager_secret.resend.secret_id }
  }

  # The per-gameweek pipeline, in order. fpl-train runs on its own schedule instead; a dry run
  # (smoke test) also runs it, so predict has a model to serve in the dry-run data directory.
  pipeline_order = ["fpl-ingest", "fpl-predict", "fpl-optimise", "fpl-notify"]
  dry_run_order  = ["fpl-ingest", "fpl-train", "fpl-predict", "fpl-optimise", "fpl-notify"]

  common_env = merge(
    {
      GCP_PROJECT_ID = var.project_id
      GCP_REGION     = var.region
      DATA_BUCKET    = google_storage_bucket.data.name
      LOG_LEVEL      = "INFO"
    },
    var.fpl_team_id == null ? {} : { FPL_TEAM_ID = tostring(var.fpl_team_id) },
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
    google_secret_manager_secret_version.resend_placeholder,
    google_secret_manager_secret_iam_member.runtime_reads_resend,
    google_storage_bucket_iam_member.runtime_data,
  ]
}

resource "google_cloud_run_v2_service" "api" {
  name                = "fpl-api"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = var.deletion_protection

  template {
    service_account                  = google_service_account.runtime.email
    max_instance_request_concurrency = 40

    scaling {
      min_instance_count = 0 # scale to zero: no idle cost
      max_instance_count = 2 # also a ceiling on cost if the API is hammered
    }

    containers {
      image = local.placeholder_service_image

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle          = true # CPU is only billed while a request is being handled
        startup_cpu_boost = true
      }

      dynamic "env" {
        for_each = merge(local.common_env, { FRONTEND_ORIGIN = var.frontend_origin })
        content {
          name  = env.key
          value = env.value
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      client,
      client_version,
    ]
  }

  depends_on = [
    google_project_service.api,
    google_storage_bucket_iam_member.runtime_data,
  ]
}

# A public frontend needs a public API. Rate limiting and clear errors live in the app; the
# max_instance_count above bounds the worst-case bill. Set api_allow_unauthenticated = false
# to require IAM auth instead.
resource "google_cloud_run_v2_service_iam_member" "api_public" {
  count = var.api_allow_unauthenticated ? 1 : 0

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
