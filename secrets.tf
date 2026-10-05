# Secret *containers* only. Real values never go through Terraform or git: add them with
#   printf '%s' "$KEY" | gcloud secrets versions add resend-api-key --data-file=-
# The placeholder version below exists only so Cloud Run can start before a real key is added
# (a job that references a secret with no versions fails to deploy); the first real version you
# add becomes "latest". Terraform ignores later changes to the secret data.

resource "google_secret_manager_secret" "resend" {
  secret_id = "resend-api-key"

  replication {
    auto {}
  }

  depends_on = [google_project_service.api]
}

resource "google_secret_manager_secret_version" "resend_placeholder" {
  secret      = google_secret_manager_secret.resend.id
  secret_data = "placeholder-replace-with-real-key"

  lifecycle {
    ignore_changes = [secret_data]
  }
}

resource "google_secret_manager_secret_iam_member" "runtime_reads_resend" {
  secret_id = google_secret_manager_secret.resend.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_secret_manager_secret" "odds" {
  count     = var.enable_odds_secret ? 1 : 0
  secret_id = "odds-api-key"

  replication {
    auto {}
  }

  depends_on = [google_project_service.api]
}

resource "google_secret_manager_secret_iam_member" "runtime_reads_odds" {
  count     = var.enable_odds_secret ? 1 : 0
  secret_id = google_secret_manager_secret.odds[0].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime.email}"
}
