# FPL Optimiser: Infrastructure

Terraform for all GCP infrastructure of the FPL optimiser. Application code is in
[`fpl-optimiser-backend`](../fpl-backend); the frontend is `fpl-optimiser-web`.

Designed to stay under **~£2/month**: everything is serverless and scales to zero, and a
billing budget with alerts is part of the config.

```
Cloud Scheduler --daily--> Cloud Workflows (fpl-pipeline)
                              |  only inside the deadline window
                              v
            Cloud Run jobs: fpl-ingest -> fpl-predict -> fpl-optimise -> fpl-notify
Cloud Scheduler --weekly--> Cloud Run job: fpl-train   (train, evaluate, maybe promote a model)

                 Cloud Storage bucket  (season=<s>/gw=<n>/, models/, monitoring/)
                              ^
web --> Cloud Run service: fpl-api   (min instances 0, max 2)

GitHub Actions (backend repo, main branch only) --OIDC/WIF--> fpl-deployer
        pushes images to Artifact Registry and updates the existing jobs/service
```

## What it creates

| Area | Resources |
|---|---|
| Compute | Cloud Run jobs `fpl-ingest`, `fpl-train`, `fpl-predict`, `fpl-optimise`, `fpl-notify`; Cloud Run service `fpl-api`. Created with a placeholder image; CI replaces it, and Terraform ignores image changes. |
| Orchestration | Workflow `fpl-pipeline` (runs the four per-gameweek jobs, only when the next deadline is within `deadline_window_hours`); Scheduler `fpl-pipeline-daily` and `fpl-train-weekly`. |
| Storage | Bucket `<project>-fpl-data` (versioned, 30-day cleanup of old versions, public access blocked); Artifact Registry repo `fpl` (keeps the newest 5 versions of each image). |
| Identity | Service accounts `fpl-runtime`, `fpl-workflow`, `fpl-scheduler`, `fpl-deployer`; Workload Identity Federation pool for GitHub (no keys). |
| Secrets | Secret container `resend-api-key` (optional `odds-api-key`). Values are added by hand. |
| Guardrail | Optional monthly budget with 50/90/100% and forecast alerts. |

### Access, at a glance

| Principal | Can |
|---|---|
| `fpl-runtime` (jobs, API) | read/write the data bucket; read its own secrets |
| `fpl-workflow` | run the four pipeline jobs (`run.developer` on each, needed for env overrides); view Cloud Run operations; write logs |
| `fpl-scheduler` | start workflow executions; run `fpl-train` |
| `fpl-deployer` (GitHub) | push images; update the existing jobs and service; act as `fpl-runtime`. Only workflows in `github_repository` on `deploy_ref` (default `refs/heads/main`) can assume it. |

## Cost

Rough monthly estimate for this usage (verify with the pricing calculator; prices change):

| Item | Why it is ~free |
|---|---|
| Cloud Run jobs | a few minutes a week, inside the monthly free vCPU/memory seconds |
| Cloud Run `fpl-api` | scales to zero, CPU only during requests, ≤ 2 instances |
| Workflows | a few dozen steps a day, inside the free steps |
| Cloud Scheduler | 2 jobs; the first 3 are free |
| Artifact Registry | cleanup policy keeps it near the free 0.5 GB |
| Cloud Storage | a few hundred MB of Parquet and model files |
| Secret Manager | 1 to 2 secrets |

Expect well under £2. The budget alerts at 50%, 90% and 100% (and on forecast) if that changes.
A budget alerts; it does not stop spending.

## Bootstrap (once, by hand)

1. Create a GCP project, link billing, and `gcloud auth application-default login` as a user
   who can create these resources.
2. Create the Terraform state bucket (this is the only thing created outside Terraform, so the
   state has somewhere to live):
   ```
   gcloud storage buckets create gs://<state-bucket> --location=<region> \
     --uniform-bucket-level-access --public-access-prevention
   gcloud storage buckets update gs://<state-bucket> --versioning
   ```
3. `cp terraform.tfvars.example terraform.tfvars` and fill in `project_id` and
   `github_repository` (and optionally `billing_account_id`).
4. ```
   terraform init -backend-config="bucket=<state-bucket>"
   terraform plan -out tfplan      # read it
   terraform apply tfplan          # a human applies; nothing here applies automatically
   ```

## Connect the backend repo

```
./scripts/set-github-variables.sh <owner>/<backend-repo>     # needs gh and jq
```
This copies `GCP_PROJECT_ID`, `GCP_REGION`, `GCP_WIF_PROVIDER`, `GCP_DEPLOYER_SA`,
`ARTIFACT_REGISTRY_REPO` and `DATA_BUCKET` into the repo's GitHub Actions variables (or set
them by hand from `terraform output github_actions_variables`). The backend's `deploy.yml`
then deploys with `google-github-actions/auth` using the provider and service account.

## Seed the data and train once

`fpl-train` needs past seasons' data in the bucket, and `fpl-predict` needs a promoted model,
so after the first deploy:
```
# 1. Import the past seasons locally (backend repo), then copy the Parquet into the bucket
uv run python -m ingest.history
gcloud storage cp --recursive ./data/season=* gs://<data-bucket>/
# 2. Run ingest for the current season, then train once
gcloud run jobs execute fpl-ingest --region=<region> --wait
gcloud run jobs execute fpl-train  --region=<region> --wait
```
Uploading data is not a deploy, so `CLAUDE.md`'s no-local-deploys rule does not apply, but it
needs your credentials; do it yourself. After that, `fpl-train-weekly` keeps the model fresh.

## Secrets

Terraform creates the secret *container* and a placeholder first version (so the notify job
can start). Add the real value:
```
printf '%s' "$RESEND_API_KEY" | gcloud secrets versions add resend-api-key --data-file=-
```
Cloud Run reads `latest`, so the next job run picks it up. Terraform never sees the value.

## First deploy: things to verify

Static validation (`terraform validate`) passes, but these only show up against a real project.
After the first `apply`:

1. **Workflow smoke test**: `gcloud workflows run fpl-pipeline --location=<region> --data='{"dry_run": true}'`.
   Runs ingest, train, predict, optimise and notify in fixture mode. With the placeholder images
   it just succeeds; with the real images it exercises the whole chain on fixture data. If it fails with a permission error on the jobs,
   or on polling operations, the `fpl-workflow` roles in `iam.tf` need adjusting
   (`run.developer` per job is for `jobs.run` with overrides; `run.viewer` at project level is
   for the operation it waits on).
2. **Scheduler to Cloud Run job**: `gcloud scheduler jobs run fpl-train-weekly --location=<region>`.
   The scheduler account has `run.invoker` on `fpl-train`; if the API returns 403 it needs
   `run.developer` there instead.
3. **Deadline logic**: `--data='{}'` should return `skipped - hours until next deadline ...` when
   the deadline is far off, and run the jobs when it is within the window.
4. **API**: `curl "$(terraform output -raw api_url)"` shows the placeholder page, until the
   first backend deploy replaces it.

## Operating notes

- The pipeline runs daily at 17:00 (`pipeline_schedule`) but only acts inside the deadline
  window (`deadline_window_hours`, default 36). `{"force": true}` bypasses the check.
- Training runs weekly (`train_schedule`, Mondays 06:00). The train job promotes a model only
  if it passes its gate; otherwise the serving model is unchanged.
- The data bucket holds snapshots that cannot be recreated (FPL's pre-deadline `ep_next`), so
  versioning is on and `force_destroy` is off. Cloud Run `deletion_protection` is on by default.
- Expected points always come from the model. `fpl-predict` fails with a clear message until
  `fpl-train` has registered and promoted a model, so seed the data and train once (below).

## Not here yet

- BigQuery: planned as external tables over the Parquet files (no duplicated storage, inside
  the free tier). Add when wanted; it needs the BigQuery API and a dataset.
- Betting-odds API key: set `enable_odds_secret = true` when that feature lands.
- The backend's `ci.yml` / `deploy.yml` live in the backend repo.

## Checks

```
terraform fmt -check -recursive
terraform init -backend=false && terraform validate
```
CI runs exactly these, with no cloud credentials.
