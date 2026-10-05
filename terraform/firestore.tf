# Firestore (Native mode) holds the bot's users: Telegram chat id, FPL team id, settings, the
# transfers a user says they have made, and invitations. It is serverless and bills per
# operation, with a free tier (1 GiB, 50k reads and 20k writes a day) far above this app's use.
#
# This is a named database (var.firestore_database), not the project's (default) one, so it
# stays separate from anything else in the project. The location cannot be changed after
# creation, so it is a deliberate, permanent choice. Delete protection is on.

resource "google_firestore_database" "default" {
  name                    = var.firestore_database
  location_id             = var.region
  type                    = "FIRESTORE_NATIVE"
  delete_protection_state = "DELETE_PROTECTION_ENABLED"

  depends_on = [google_project_service.api]
}

# Data retention enforced by the database itself: documents are deleted automatically some time
# after their `expires_at` passes. Declared transfers are only useful for a gameweek; invites
# lapse after a week. (Deletion is not instant: it usually happens within a day or so, so code
# must still check expires_at itself, which it does.)
resource "google_firestore_field" "declared_transfers_ttl" {
  database   = google_firestore_database.default.name
  collection = "declared"
  field      = "expires_at"

  ttl_config {}
}

resource "google_firestore_field" "invites_ttl" {
  database   = google_firestore_database.default.name
  collection = "invites"
  field      = "expires_at"

  ttl_config {}
}

# Only the runtime account (jobs and the bot) can touch the data, and only as a Firestore user.
# There are no client-side rules because nothing connects from a browser or phone: Telegram
# talks to our service, never to Firestore.
resource "google_project_iam_member" "runtime_uses_firestore" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.runtime.email}"
}
