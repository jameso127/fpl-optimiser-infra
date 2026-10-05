# Four service accounts, each with only what it needs:
#   fpl-runtime   what the jobs and the API run as: read/write the data bucket, read secrets
#   fpl-workflow  runs the pipeline jobs from Cloud Workflows
#   fpl-scheduler starts the workflow and the weekly train job
#   fpl-deployer  GitHub Actions (no keys: Workload Identity Federation, see wif.tf)

resource "google_service_account" "runtime" {
  account_id   = "fpl-runtime"
  display_name = "FPL jobs and API runtime"
  depends_on   = [google_project_service.api]
}

resource "google_service_account" "workflow" {
  account_id   = "fpl-workflow"
  display_name = "FPL pipeline workflow"
  depends_on   = [google_project_service.api]
}

resource "google_service_account" "scheduler" {
  account_id   = "fpl-scheduler"
  display_name = "FPL Cloud Scheduler"
  depends_on   = [google_project_service.api]
}

resource "google_service_account" "deployer" {
  account_id   = "fpl-deployer"
  display_name = "FPL GitHub Actions deployer"
  depends_on   = [google_project_service.api]
}

# --- runtime: the data bucket only (not the whole project) -------------------------------
resource "google_storage_bucket_iam_member" "runtime_data" {
  bucket = google_storage_bucket.data.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.runtime.email}"
}

# --- workflow: run the pipeline jobs ------------------------------------------------------
# Running a job with env overrides (DRY_RUN) needs run.jobs.runWithOverrides, which sits in
# roles/run.developer, so it is granted per job rather than on the project. fpl-train is
# included because a dry-run smoke test runs it; the weekly real run is started by Scheduler.
resource "google_cloud_run_v2_job_iam_member" "workflow_runs_jobs" {
  for_each = local.jobs

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.job[each.key].name
  role     = "roles/run.developer"
  member   = "serviceAccount:${google_service_account.workflow.email}"
}

# Waiting for a job to finish polls a long-running operation; that is a project-level read.
resource "google_project_iam_member" "workflow_views_run" {
  project = var.project_id
  role    = "roles/run.viewer"
  member  = "serviceAccount:${google_service_account.workflow.email}"
}

resource "google_project_iam_member" "workflow_logs" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.workflow.email}"
}

# --- scheduler: start the workflow, and the train job directly ----------------------------
resource "google_project_iam_member" "scheduler_starts_workflows" {
  project = var.project_id
  role    = "roles/workflows.invoker"
  member  = "serviceAccount:${google_service_account.scheduler.email}"
}

resource "google_cloud_run_v2_job_iam_member" "scheduler_runs_train" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.job["fpl-train"].name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scheduler.email}"
}

# --- deployer: update the existing jobs/service and push images; nothing else -------------
resource "google_artifact_registry_repository_iam_member" "deployer_pushes_images" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.images.repository_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.deployer.email}"
}

resource "google_cloud_run_v2_job_iam_member" "deployer_updates_jobs" {
  for_each = google_cloud_run_v2_job.job

  project  = var.project_id
  location = var.region
  name     = each.value.name
  role     = "roles/run.developer"
  member   = "serviceAccount:${google_service_account.deployer.email}"
}

resource "google_cloud_run_v2_service_iam_member" "deployer_updates_api" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.api.name
  role     = "roles/run.developer"
  member   = "serviceAccount:${google_service_account.deployer.email}"
}

# The optional post-deploy smoke test runs the pipeline workflow in dry-run mode.
resource "google_project_iam_member" "deployer_runs_workflows" {
  project = var.project_id
  role    = "roles/workflows.invoker"
  member  = "serviceAccount:${google_service_account.deployer.email}"
}

# Deploying a revision that runs as fpl-runtime requires permission to act as it.
resource "google_service_account_iam_member" "deployer_acts_as_runtime" {
  service_account_id = google_service_account.runtime.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.deployer.email}"
}
