# Secret *containers* only. Real values never go through Terraform or git: add the bot token with
#   printf '%s' "$TOKEN" | gcloud secrets versions add telegram-bot-token --data-file=-
# The placeholder version below exists only so Cloud Run can start before a real token is added
# (a job that references a secret with no versions fails to deploy); the first real version you
# add becomes "latest". Terraform ignores later changes to the secret data.

resource "google_secret_manager_secret" "telegram" {
  secret_id = "telegram-bot-token"

  replication {
    auto {}
  }

  depends_on = [google_project_service.api]
}

resource "google_secret_manager_secret_version" "telegram_placeholder" {
  secret      = google_secret_manager_secret.telegram.id
  secret_data = "placeholder-replace-with-real-token"

  lifecycle {
    ignore_changes = [secret_data]
  }
}

resource "google_secret_manager_secret_iam_member" "runtime_reads_telegram" {
  secret_id = google_secret_manager_secret.telegram.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime.email}"
}
