#!/usr/bin/env bash
# One-off, run by a human: creates the identities GitHub Actions uses to run Terraform.
#
# They are created here, by hand, and NOT in the Terraform that CI applies, so the pipeline
# cannot widen its own access. Everything this script makes is listed below; read it first.
#
#   fpl-terraform       applies changes. Usable only by a workflow on refs/heads/main of the
#                       infra repo. Powerful: it can create resources and set IAM on this project.
#   fpl-terraform-plan  previews plans on pull requests. Read-only. Usable by any branch of
#                       the infra repo.
#   pool github-ci      lets GitHub Actions of the infra repo (and no other repo) get
#                       short-lived credentials for those two accounts. No keys are created.
#
# Needs the gcloud CLI, logged in as someone who can administer the project (for example the
# project owner). Safe to re-run: steps that already exist are skipped.
#
#   ./scripts/bootstrap-ci.sh <project-id> <owner/infra-repo> <state-bucket>
set -euo pipefail

project="${1:?usage: $0 <project-id> <owner/infra-repo> <state-bucket>}"
repo="${2:?usage: $0 <project-id> <owner/infra-repo> <state-bucket>}"
state_bucket="${3:?usage: $0 <project-id> <owner/infra-repo> <state-bucket>}"

pool="github-ci"
provider="infra-repo"
apply_sa="fpl-terraform"
plan_sa="fpl-terraform-plan"
apply_email="${apply_sa}@${project}.iam.gserviceaccount.com"
plan_email="${plan_sa}@${project}.iam.gserviceaccount.com"
project_number="$(gcloud projects describe "$project" --format='value(projectNumber)')"
pool_name="projects/${project_number}/locations/global/workloadIdentityPools/${pool}"

# Roles the apply account needs for the resources in this repo. projectIamAdmin lets it grant
# itself any role on the project, so treat it as project admin. The billing budget needs a
# role on the billing account instead, so leave billing_account_id empty in CI.
apply_roles=(
  roles/viewer
  roles/serviceusage.serviceUsageAdmin
  roles/iam.serviceAccountAdmin
  roles/iam.serviceAccountUser
  roles/iam.workloadIdentityPoolAdmin
  roles/resourcemanager.projectIamAdmin
  roles/storage.admin
  roles/artifactregistry.admin
  roles/secretmanager.admin
  roles/run.admin
  roles/workflows.admin
  roles/cloudscheduler.admin
  roles/datastore.owner
)
plan_roles=(roles/viewer roles/iam.securityReviewer)

echo "== APIs needed to log in and manage IAM"
gcloud services enable iam.googleapis.com iamcredentials.googleapis.com sts.googleapis.com \
  cloudresourcemanager.googleapis.com serviceusage.googleapis.com --project "$project"

echo "== Service accounts"
for sa in "$apply_sa" "$plan_sa"; do
  gcloud iam service-accounts describe "${sa}@${project}.iam.gserviceaccount.com" \
    --project "$project" >/dev/null 2>&1 \
    || gcloud iam service-accounts create "$sa" --project "$project" \
         --display-name "Terraform (GitHub Actions, no keys)"
done

echo "== Workload Identity pool and provider (only the infra repo is accepted)"
gcloud iam workload-identity-pools describe "$pool" --location global --project "$project" \
  >/dev/null 2>&1 \
  || gcloud iam workload-identity-pools create "$pool" --location global --project "$project" \
       --display-name "GitHub Actions (Terraform)"
gcloud iam workload-identity-pools providers describe "$provider" --location global \
  --workload-identity-pool "$pool" --project "$project" >/dev/null 2>&1 \
  || gcloud iam workload-identity-pools providers create-oidc "$provider" --location global \
       --workload-identity-pool "$pool" --project "$project" \
       --issuer-uri "https://token.actions.githubusercontent.com" \
       --attribute-mapping "google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repo_ref=assertion.repository+':'+assertion.ref" \
       --attribute-condition "assertion.repository=='${repo}'"

echo "== Who may use which account"
# Apply: only the main branch of the infra repo.
gcloud iam service-accounts add-iam-policy-binding "$apply_email" --project "$project" \
  --role roles/iam.workloadIdentityUser \
  --member "principalSet://iam.googleapis.com/${pool_name}/attribute.repo_ref/${repo}:refs/heads/main" \
  >/dev/null
# Plan: any ref of the infra repo (pull requests run on refs/pull/<n>/merge).
gcloud iam service-accounts add-iam-policy-binding "$plan_email" --project "$project" \
  --role roles/iam.workloadIdentityUser \
  --member "principalSet://iam.googleapis.com/${pool_name}/attribute.repository/${repo}" \
  >/dev/null

echo "== Project roles"
for role in "${apply_roles[@]}"; do
  gcloud projects add-iam-policy-binding "$project" --member "serviceAccount:${apply_email}" \
    --role "$role" --condition=None >/dev/null
done
for role in "${plan_roles[@]}"; do
  gcloud projects add-iam-policy-binding "$project" --member "serviceAccount:${plan_email}" \
    --role "$role" --condition=None >/dev/null
done
# The plan account also reads the Terraform state (the apply account has storage.admin).
gcloud storage buckets add-iam-policy-binding "gs://${state_bucket}" \
  --member "serviceAccount:${plan_email}" --role roles/storage.objectViewer >/dev/null

cat <<EOF

Done. Set these as GitHub Actions variables on ${repo}
(Settings > Secrets and variables > Actions > Variables). None are secret:

  GCP_WIF_PROVIDER = ${pool_name}/providers/${provider}
  GCP_TERRAFORM_SA = ${apply_email}
  GCP_PLANNER_SA   = ${plan_email}
  TF_STATE_BUCKET  = ${state_bucket}
  PROJECT_ID       = ${project}

Also add REGION, BACKEND_REPOSITORY (owner/backend-repo), FPL_TEAM_ID and TELEGRAM_CHAT_ID,
and create an environment called "production" with yourself as a required reviewer
(Settings > Environments). See README, "Terraform in CI".
EOF
