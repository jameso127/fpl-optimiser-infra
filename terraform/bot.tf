# fpl-bot: the Telegram bot. Telegram posts every message sent to the bot to this service
# (a webhook), and it replies and registers users in Firestore. The service name is the
# contract with the backend repo.
#
# Cost: it scales to zero (no minimum instances) and bills only while handling a request
# (cpu_idle), so a handful of users is well inside the Cloud Run free tier. max_instance_count
# caps what a flood of requests could cost.
#
# It must be public: Telegram cannot authenticate to Google. Instead, Telegram sends a secret
# header with each update and the service drops requests without it. The secret is derived
# from the bot token in the backend, so there is no second secret to manage here.
#
# Created with a Google sample image; GitHub Actions in the backend replaces it on deploy, so
# Terraform ignores image changes. It runs in var.run_region next to the jobs, because it
# calls the FPL API to check team ids (which refuses europe-west2).

resource "google_cloud_run_v2_service" "bot" {
  name                = "fpl-bot"
  location            = var.run_region
  deletion_protection = var.deletion_protection
  ingress             = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.runtime.email
    timeout         = "60s"

    scaling {
      min_instance_count = 0
      max_instance_count = 1
    }

    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello"

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle = true # CPU (and billing) only while a request is being handled
      }

      dynamic "env" {
        for_each = local.common_env
        content {
          name  = env.key
          value = env.value
        }
      }

      env {
        name = "TELEGRAM_BOT_TOKEN"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.telegram.secret_id
            version = "latest"
          }
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
    google_secret_manager_secret_version.telegram_placeholder,
    google_secret_manager_secret_iam_member.runtime_reads_telegram,
  ]
}

# Public, so Telegram can reach it (see above for how requests are authenticated).
resource "google_cloud_run_v2_service_iam_member" "bot_public" {
  project  = var.project_id
  location = var.run_region
  name     = google_cloud_run_v2_service.bot.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# The deployer updates the service's image, and nothing else.
resource "google_cloud_run_v2_service_iam_member" "deployer_updates_bot" {
  project  = var.project_id
  location = var.run_region
  name     = google_cloud_run_v2_service.bot.name
  role     = "roles/run.developer"
  member   = "serviceAccount:${google_service_account.deployer.email}"
}
