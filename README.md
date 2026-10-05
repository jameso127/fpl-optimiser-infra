# FPL Optimiser: Infrastructure

Terraform for all GCP infrastructure of the FPL optimiser. Application code is in
`fpl-optimiser-backend`.

Designed to stay under **~£2/month**: everything is serverless and scales to zero, and a
billing budget with alerts is part of the config.

```
Cloud Scheduler --10:00 daily--> Cloud Workflows (fpl-pipeline)
      check the schedule (fpl-ingest, SCHEDULE_ONLY); on a deadline day run
      fpl-ingest -> fpl-predict -> fpl-optimise -> fpl-notify (Telegram)
Cloud Scheduler --weekly--> Cloud Run job: fpl-train   (train, evaluate, maybe promote a model)

                 Cloud Storage bucket  (season=<s>/gw=<n>/, models/, monitoring/, schedule.json)

GitHub Actions (backend repo, main branch only) --OIDC/WIF--> fpl-deployer
        pushes images to Artifact Registry and updates the existing jobs
```

## What it creates

| Area | Resources |
|---|---|
| Compute | Cloud Run jobs `fpl-ingest`, `fpl-train`, `fpl-predict`, `fpl-optimise`, `fpl-notify`. Created with a placeholder image; CI replaces it, and Terraform ignores image changes. |
| Orchestration | Workflow `fpl-pipeline` (checks `schedule.json`, runs the four jobs on deadline days); Scheduler `fpl-pipeline-daily` and `fpl-train-weekly`. |
| Storage | Bucket `<project>-fpl-data` (versioned, 30-day cleanup of old versions, public access blocked); Artifact Registry repo `fpl` (keeps the newest 5 versions of each image). |
| Identity | Service accounts `fpl-runtime`, `fpl-workflow`, `fpl-scheduler`, `fpl-deployer`; Workload Identity Federation pool for GitHub (no keys). |
| Users | Firestore (Native mode, a named database, `fpl-users` by default) for the bot's users, with TTL policies that expire declared transfers and invites automatically. |
| Secrets | Secret container `telegram-bot-token`. The value is added by hand. |
| Guardrail | Optional monthly budget with 50/90/100% and forecast alerts. |

### Access, at a glance

| Principal | Can |
|---|---|
| `fpl-runtime` (jobs) | read/write the data bucket; read its own secrets; read/write Firestore (`datastore.user`) |
| `fpl-workflow` | run the pipeline jobs, with overrides (custom role `fplJobRunner` on each); read the bucket (`schedule.json`); view Cloud Run operations; write logs |
| `fpl-scheduler` | start workflow executions; run `fpl-train` |
| `fpl-deployer` (GitHub) | push images; update the existing jobs; act as `fpl-runtime`. Only workflows in `github_repository` on `deploy_ref` (default `refs/heads/main`) can assume it. |

## Cost

Rough monthly estimate for this usage (verify with the pricing calculator; prices change):

| Item | Why it is ~free |
|---|---|
| Cloud Run jobs | a few minutes a week, inside the monthly free vCPU/memory seconds |
| Workflows | a few dozen steps a day, inside the free steps |
| Cloud Scheduler | 2 jobs; the first 3 are free |
| Artifact Registry | cleanup policy keeps it near the free 0.5 GB |
| Cloud Storage | a few hundred MB of Parquet and model files |
| Secret Manager | 1 to 2 secrets |

Expect well under £2. The budget alerts at 50%, 90% and 100% (and on forecast) if that changes.
A budget alerts; it does not stop spending.

## Terraform in CI

One pipeline, `.github/workflows/terraform.yml`, with three stages:

| Stage | Pull request | Merge to `main` |
|---|---|---|
| validate | `fmt` and `validate`, no credentials | same |
| plan | read-only preview, posted as a comment | full plan, shown in the run summary |
| apply | not run | waits for you to approve the `production` environment, then applies that exact plan |

No keys anywhere: GitHub proves who it is with a short-lived token, and Google only accepts
this repo. The plan account can read but not change anything. The apply account can create
resources and only `main` can use it; it is effectively project admin because it manages IAM,
which is why it sits behind your approval and why the accounts are created by hand, outside
this Terraform, so the pipeline cannot widen its own access (see [docs/bootstrap.md](docs/bootstrap.md),
which also has the one-off setup). A dedicated project would limit the blast radius further.

Run `terraform plan` locally (in `terraform/`) whenever you like; only the pipeline applies.

## Connect the backend repo

After the first apply, read the values the backend needs:
```
cd terraform
terraform init -backend-config="bucket=<state-bucket>"
terraform output github_actions_variables
```
Set `GCP_PROJECT_ID`, `GCP_REGION`, `GCP_WIF_PROVIDER`, `GCP_DEPLOYER_SA`,
`ARTIFACT_REGISTRY_REPO` and `DATA_BUCKET` as GitHub Actions variables on the backend repo
(none are secret). Its `deploy.yml` then deploys with `google-github-actions/auth` using that
provider and service account.

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
printf '%s' "$TELEGRAM_BOT_TOKEN" | gcloud secrets versions add telegram-bot-token --data-file=-
```
Cloud Run reads `latest`, so the next job run picks it up. Terraform never sees the value.

## First deploy: things to verify

Static validation (`terraform validate`) passes, but these only show up against a real project.
After the first `apply`:

1. **Workflow run**: `gcloud workflows run fpl-pipeline --location=<region> --data='{"force": true}'`.
   Runs ingest, predict, optimise and notify for real, so it sends you a Telegram message. If it
   fails with a permission error on the jobs, or on polling operations, the `fpl-workflow`
   roles in `iam.tf` need adjusting (`fplJobRunner` per job is for `jobs.run` and its overrides;
   `run.viewer` at project level is for the operation it waits on).
2. **Scheduler to Cloud Run job**: `gcloud scheduler jobs run fpl-train-weekly --location=<region>`.
   The scheduler account has `run.invoker` on `fpl-train`; if the API returns 403 it needs
   `run.developer` there instead.
3. **Schedule check**: `--data='{}'` on a day that is not a deadline day should end with "the
   next deadline (gameweek N) is not today, so nothing was run". That proves the
   `SCHEDULE_ONLY` override works (a 403 means `fplJobRunner` is wrong) and that the workflow
   can read `schedule.json`. If the step fails on the file's content type, adjust
   `parse_schedule` in `workflows/pipeline.yaml`.

## Operating notes

- The workflow starts daily at 10:00 UK (`pipeline_schedule`). It only runs the pipeline, and
  so only sends, on deadline days. A deadline before 10:00 is missed (accepted for now).
  `{"force": true}` skips the check.
- Training runs weekly (`train_schedule`, Mondays 06:00). The train job promotes a model only
  if it passes its gate; otherwise the serving model is unchanged.
- The data bucket holds snapshots that cannot be recreated (FPL's pre-deadline `ep_next`), so
  versioning is on and `force_destroy` is off. Cloud Run `deletion_protection` is on by default.
- Expected points always come from the model. `fpl-predict` fails with a clear message until
  `fpl-train` has registered and promoted a model, so seed the data and train once (below).

## Firestore

One database holds `users/{chat_id}` (with a `declared` subcollection of transfers the user
says they have made) and `invites/{code}`. Both `declared` and `invites` carry an `expires_at`
with a TTL policy, so the database deletes stale data itself. Notes:

- It is a named database (`firestore_database`, default `fpl-users`), so it does not touch any
  `(default)` database the project already has. The location is permanent (set from `region`)
  and delete protection is on.
- TTL deletion is not instant (usually within a day), so the application also checks
  `expires_at`.
- Nothing connects to Firestore from a client: Telegram talks to our service, and our service
  talks to Firestore as `fpl-runtime`, so there are no security rules to maintain.
- The backend's contract tests run against the Firestore emulator in CI.

### Adding yourself (until the bot can register people)

Nobody's ids live in Terraform or GitHub. Users are documents in Firestore. In the Google Cloud
console go to Firestore > Data > Start collection `users`, with document id = your Telegram chat
id, and these fields:

| Field | Type | Value |
|---|---|---|
| `chat_id` | number | your Telegram chat id |
| `fpl_team_id` | number | your FPL team id |
| `active` | boolean | `true` |

The jobs pick it up on the next run. The bot's `/start` will replace this step. To pause
yourself, set `active` to `false`.

## Not here yet

- An API service (Cloud Run, scale to zero) and the Telegram bot webhook: both are planned and
  both are small additions here.
- BigQuery: planned as external tables over the Parquet files (no duplicated storage, inside
  the free tier). Add when wanted; it needs the BigQuery API and a dataset.
- The backend's `ci.yml` / `deploy.yml` live in the backend repo.

## Checks

```
cd terraform
terraform fmt -check -recursive
terraform init -backend=false && terraform validate
```
CI runs exactly these, with no cloud credentials.
