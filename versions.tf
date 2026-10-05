terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Partial configuration: the state bucket is passed at init time so no names are
  # hardcoded here. See README.md ("Bootstrap").
  #   terraform init -backend-config="bucket=<state-bucket>"
  backend "gcs" {
    prefix = "fpl-optimiser"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region

  # The Billing Budgets API needs a quota project; harmless for everything else.
  user_project_override = true
  billing_project       = var.project_id
}
