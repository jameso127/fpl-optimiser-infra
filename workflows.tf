resource "google_workflows_workflow" "pipeline" {
  name            = "fpl-pipeline"
  region          = var.region
  description     = "Pipeline: ingest, predict, optimise, notify."
  service_account = google_service_account.workflow.email
  call_log_level  = "LOG_ERRORS_ONLY"

  user_env_vars = {
    DEADLINE_WINDOW_HOURS = tostring(var.deadline_window_hours)
    PIPELINE_JOBS         = jsonencode(local.pipeline_order)
  }

  source_contents = file("${path.module}/workflows/pipeline.yaml")

  depends_on = [
    google_project_service.api,
    google_cloud_run_v2_job_iam_member.workflow_runs_jobs,
  ]
}
