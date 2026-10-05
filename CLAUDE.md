# FPL Optimiser: Infrastructure

Terraform for ALL GCP infrastructure of the FPL optimiser demo: Cloud Run jobs and service,
Cloud Workflows, Cloud Scheduler, Artifact Registry, the data bucket, IAM, Workload Identity
Federation and Secret Manager. The application code lives in `fpl-optimiser-backend`
(this repo's sibling); the React frontend in `fpl-optimiser-web`.

**Hard constraint: must stay cheap (target < £2/month).** Scale-to-zero only. Never add an
always-on resource (no minimum instances, no VMs, no Cloud SQL, no load balancers, no NAT).
Say what a new resource costs before adding it.

## Rules

- **Never run `terraform apply` or `terraform destroy`**, or any `gcloud` command that creates,
  changes or deletes resources. Changes go through a pull request: CI previews the plan, and
  `apply.yml` applies it after merge once the human approves the `production` environment.
  Read-only commands (`fmt`, `validate`, `plan`, `output`) are fine. The CI identities are
  created once, by hand, with `scripts/bootstrap-ci.sh` (written for the human to run).
- No secrets in this repo, state or variables: secret *containers* only; values are added by
  hand with `gcloud secrets versions add`. No service account keys, ever.
- CI credentials come only from Workload Identity Federation. `ci.yml` has none (`fmt` and
  `validate`); `plan.yml` uses a read-only account; `apply.yml` uses the apply account, which only
  `refs/heads/main` of this repo can assume. These accounts are NOT managed by this Terraform, so
  the pipeline cannot change its own access.
- Least privilege: grant roles on the narrowest resource that works; explain any project-level
  role in a comment.
- Pin provider versions (`~>`), actions to a version or SHA, and give each workflow minimal
  `permissions:`.

## Contract with the backend repo (names must match)

Outputs `github_actions_variables` provide `GCP_PROJECT_ID`, `GCP_REGION`, `GCP_WIF_PROVIDER`,
`GCP_DEPLOYER_SA`, `ARTIFACT_REGISTRY_REPO`, `DATA_BUCKET`. Cloud Run jobs `fpl-ingest`,
`fpl-train`, `fpl-predict`, `fpl-optimise`, `fpl-notify` are created here
with placeholder images; GitHub Actions in the backend repo replaces the image on deploy, so
Terraform ignores image changes. There is no API service yet. Bucket layout: `season=<s>/gw=<n>/...`, `models/...`,
`monitoring/...`. If the backend needs a new job, bucket prefix needing IAM, secret or API,
it is added here first.

## Workflow

1. Change `.tf` files. 2. `terraform fmt -recursive` and `terraform validate`.
3. `terraform plan` and read it. 4. A human applies. Conventional commits.
