resource "google_workflows_workflow" "pipeline" {
  name            = "fpl-pipeline"
  region          = var.region
  description     = "Daily 10:00: run ingest, predict, optimise, notify. Notify only sends on deadline days."
  service_account = google_service_account.workflow.email
  call_log_level  = "LOG_ERRORS_ONLY"

  user_env_vars = {
    PIPELINE_JOBS = jsonencode(local.pipeline_order)
  }

  source_contents = file("${path.module}/workflows/pipeline.yaml")

  depends_on = [
    google_project_service.api,
    google_cloud_run_v2_job_iam_member.workflow_runs_jobs,
  ]
}
