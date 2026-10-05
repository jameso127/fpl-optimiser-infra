# The values the backend repo needs as GitHub Actions variables (see README, "Connect the
# backend repo"). Names match the contract in the backend's CLAUDE.md.
output "github_actions_variables" {
  description = "Set these as GitHub Actions variables on the backend repo."
  value = {
    GCP_PROJECT_ID         = var.project_id
    GCP_REGION             = var.region
    GCP_WIF_PROVIDER       = google_iam_workload_identity_pool_provider.github.name
    GCP_DEPLOYER_SA        = google_service_account.deployer.email
    ARTIFACT_REGISTRY_REPO = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}"
    DATA_BUCKET            = google_storage_bucket.data.name
  }
}

output "api_url" {
  description = "Base URL of fpl-api (the placeholder page until the first deploy)."
  value       = google_cloud_run_v2_service.api.uri
}

output "pipeline_workflow" {
  value = google_workflows_workflow.pipeline.name
}

output "jobs" {
  value = sort(keys(google_cloud_run_v2_job.job))
}
