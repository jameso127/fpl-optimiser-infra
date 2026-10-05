locals {
  apis = toset(concat(
    [
      "run.googleapis.com",
      "workflows.googleapis.com",
      "workflowexecutions.googleapis.com",
      "cloudscheduler.googleapis.com",
      "artifactregistry.googleapis.com",
      "secretmanager.googleapis.com",
      "storage.googleapis.com",
      "firestore.googleapis.com",
      "iam.googleapis.com",
      "iamcredentials.googleapis.com",
      "sts.googleapis.com",
      "cloudresourcemanager.googleapis.com",
      "serviceusage.googleapis.com",
      "logging.googleapis.com",
    ],
    var.billing_account_id == "" ? [] : ["billingbudgets.googleapis.com"],
  ))
}

resource "google_project_service" "api" {
  for_each = local.apis

  service            = each.value
  disable_on_destroy = false
}

data "google_project" "this" {
  project_id = var.project_id
}
