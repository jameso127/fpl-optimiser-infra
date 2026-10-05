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

variable "users_backend" {
  description = "Where users (chat id, FPL team id, settings) live: \"firestore\", or \"memory\" for none (jobs then do nothing)."
  type        = string
  default     = "firestore"

  validation {
    condition     = contains(["memory", "firestore"], var.users_backend)
    error_message = "users_backend must be \"memory\" or \"firestore\"."
  }
}

variable "pipeline_schedule" {
  description = "Cron for the daily pipeline start, in schedule_time_zone. Data refreshes daily; messages only go out on deadline days."
  type        = string
  default     = "0 7 * * *"
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

variable "deletion_protection" {
  description = "Protect Cloud Run jobs/service from accidental terraform destroy."
  type        = bool
  default     = true
}
