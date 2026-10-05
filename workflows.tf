resource "google_workflows_workflow" "pipeline" {
  name            = "fpl-pipeline"
  region          = var.region
  description     = "Daily 07:00: ingest, then on deadline days wait and send at 10:00 (or 2.5h before)."
  service_account = google_service_account.workflow.email
  call_log_level  = "LOG_ERRORS_ONLY"

  user_env_vars = {
    DATA_BUCKET   = google_storage_bucket.data.name
    PIPELINE_JOBS = jsonencode(local.pipeline_order)
  }

  source_contents = file("${path.module}/workflows/pipeline.yaml")

  depends_on = [
    google_project_service.api,
    google_cloud_run_v2_job_iam_member.workflow_runs_jobs,
    google_storage_bucket_iam_member.workflow_reads_schedule,
  ]
}
