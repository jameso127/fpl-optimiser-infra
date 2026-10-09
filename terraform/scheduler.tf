# Two cheap triggers (Cloud Scheduler gives 3 jobs free per month):
#   daily  -> the pipeline workflow, which runs every job; notify only sends on deadline days
#   weekly -> the train job, which trains, evaluates and (if it passes the gate) promotes

resource "google_cloud_scheduler_job" "pipeline" {
  name             = "fpl-pipeline-daily"
  description      = "Start the pipeline workflow each morning; it only sends on deadline days."
  region           = var.region
  schedule         = var.pipeline_schedule
  time_zone        = var.schedule_time_zone
  attempt_deadline = "60s"

  http_target {
    http_method = "POST"
    uri         = "https://workflowexecutions.googleapis.com/v1/${google_workflows_workflow.pipeline.id}/executions"
    headers     = { "Content-Type" = "application/json" }
    body        = base64encode(jsonencode({ argument = jsonencode({}) }))

    oauth_token {
      service_account_email = google_service_account.scheduler.email
    }
  }

  depends_on = [google_project_iam_member.scheduler_starts_workflows]
}

resource "google_cloud_scheduler_job" "train" {
  name             = "fpl-train-weekly"
  description      = "Train, evaluate and maybe promote a new model."
  region           = var.region
  schedule         = var.train_schedule
  time_zone        = var.schedule_time_zone
  attempt_deadline = "60s"

  http_target {
    http_method = "POST"
    uri         = "https://run.googleapis.com/v2/projects/${var.project_id}/locations/${var.region}/jobs/fpl-train:run"
    headers     = { "Content-Type" = "application/json" }
    body        = base64encode("{}")

    oauth_token {
      service_account_email = google_service_account.scheduler.email
    }
  }

  depends_on = [google_cloud_run_v2_job_iam_member.scheduler_runs_train]
}
