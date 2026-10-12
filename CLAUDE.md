# FPL Optimiser: Infrastructure

Terraform for ALL GCP infrastructure of the FPL optimiser demo: Cloud Run jobs,
Cloud Workflows, Cloud Scheduler, Artifact Registry, the data bucket, IAM, Workload Identity
Federation and Secret Manager. The application code lives in the backend repo
(`jameso127/fpl-optimiser`, checked out as `../fpl-backend`); the React frontend
(`fpl-optimiser-web`) is deferred.

**Hard constraint: must stay cheap (target < £2/month).** Scale-to-zero only. Never add an
always-on resource (no minimum instances, no VMs, no Cloud SQL, no load balancers, no NAT).
Say what a new resource costs before adding it.

## Rules

- **Never run `terraform apply` or `terraform destroy`**, or any `gcloud` command that creates,
  changes or deletes resources. Changes go through a pull request: the
  `terraform` workflow validates and previews the plan, and after merge applies it once the
  human approves the `production` environment. Read-only commands (`fmt`, `validate`, `plan`,
  `output`) are fine. The CI identities are created once, by hand (docs/bootstrap.md).
- No secrets in this repo, state or variables: secret *containers* only; values are added by
  hand with `gcloud secrets versions add`. No service account keys, ever.
- CI credentials come only from Workload Identity Federation. `validate` has none; `plan` on
  a pull request uses a read-only account; `apply` uses the apply account, which only
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

The deployer only trusts `refs/heads/main` of the repo in the `BACKEND_REPOSITORY` Actions
variable, which must be exactly `owner/name` (`jameso127/fpl-optimiser`), not a URL. GitHub
variables are pasted by hand: watch for stray spaces.

Schedules: the `fpl-pipeline` workflow runs daily at 10:00 UK and runs ingest, predict,
optimise and notify in order, with no waiting or deadline logic; `fpl-notify` decides whether
today is a deadline day. `fpl-train` has its own weekly schedule.

## Workflow

1. Change the `.tf` files in `terraform/`. 2. In that folder, `terraform fmt -recursive` and
`terraform validate`. 3. `terraform plan` and read it. 4. Open a pull request; a human approves
the apply after merge. Conventional commits.
