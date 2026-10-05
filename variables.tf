variable "project_id" {
  description = "GCP project that hosts everything. Dedicated to this app is best, so the budget and IAM stay simple."
  type        = string
}

variable "region" {
  description = "Region for Cloud Run, Artifact Registry, the bucket, Workflows and Scheduler."
  type        = string
  default     = "europe-west2"
}

variable "github_repository" {
  description = "owner/name of the backend repo whose GitHub Actions may deploy (via Workload Identity Federation)."
  type        = string
}

variable "deploy_ref" {
  description = "Git ref allowed to authenticate as the deployer. Only merges to this ref can deploy."
  type        = string
  default     = "refs/heads/main"
}

variable "data_bucket_name" {
  description = "Name of the Parquet/model bucket. Empty means <project_id>-fpl-data."
  type        = string
  default     = ""
}

variable "artifact_registry_repo_id" {
  description = "Artifact Registry Docker repository id."
  type        = string
  default     = "fpl"
}

variable "image_keep_count" {
  description = "Most recent versions of each image to keep (older ones are cleaned up to stay in the free tier)."
  type        = number
  default     = 5
}

variable "xpts_source" {
  description = "Expected-points source for the predict job: model or ep_next."
  type        = string
  default     = "model"

  validation {
    condition     = contains(["model", "ep_next"], var.xpts_source)
    error_message = "xpts_source must be \"model\" or \"ep_next\"."
  }
}

variable "frontend_origin" {
  description = "Origin allowed by the API's CORS policy (the web app's URL). Empty until the frontend exists."
  type        = string
  default     = ""
}

variable "api_allow_unauthenticated" {
  description = "Let anyone on the internet call fpl-api (needed for a public frontend). Set false to require IAM auth."
  type        = bool
  default     = true
}

variable "deadline_window_hours" {
  description = "The pipeline only runs when the next gameweek deadline is within this many hours."
  type        = number
  default     = 36
}

variable "pipeline_schedule" {
  description = "Cron for the daily pipeline check (the workflow itself decides whether a deadline is close enough to run)."
  type        = string
  default     = "0 17 * * *"
}

variable "train_schedule" {
  description = "Cron for the weekly model training job."
  type        = string
  default     = "0 6 * * 1"
}

variable "schedule_time_zone" {
  type    = string
  default = "Europe/London"
}

variable "billing_account_id" {
  description = "Billing account id (XXXXXX-XXXXXX-XXXXXX). If set, a monthly budget with alerts is created."
  type        = string
  default     = ""
}

variable "monthly_budget" {
  description = "Monthly budget amount in budget_currency. The project's hard constraint is < 2 GBP."
  type        = number
  default     = 2
}

variable "budget_currency" {
  type    = string
  default = "GBP"
}

variable "enable_odds_secret" {
  description = "Create a Secret Manager secret for a betting-odds API key (not used yet)."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Protect Cloud Run jobs/service from accidental terraform destroy."
  type        = bool
  default     = true
}
