# Bootstrap (once, by hand)

The pipeline in `.github/workflows/terraform.yml` needs two Google accounts to log in as. They
are created here by hand, not in the Terraform that the pipeline applies, so the pipeline cannot
widen its own access. There are no keys: GitHub proves who it is with a short-lived token
(Workload Identity Federation).

| Created | Used for | Who can use it |
|---|---|---|
| `fpl-terraform-plan` | plan previews on pull requests; read-only | any branch of the infra repo |
| `fpl-terraform` | apply; project admin in effect, because it manages IAM | only `main` of the infra repo, and only after you approve |
| pool `github-ci`, provider `infra-repo` | the login rule | tokens from the infra repo only |

Set `PROJECT`, `REPO` (`owner/infra-repo`) and `BUCKET` (state bucket), then run these in Git
Bash or Cloud Shell as someone who administers the project.

```bash
PROJECT=fpl-optimizer
REPO=jameso127/fpl-optimiser-infra
BUCKET=fpl-optimizer-terraform-state
NUMBER=$(gcloud projects describe $PROJECT --format='value(projectNumber)')
POOL=projects/$NUMBER/locations/global/workloadIdentityPools/github-ci
APPLY=fpl-terraform@$PROJECT.iam.gserviceaccount.com
PLAN=fpl-terraform-plan@$PROJECT.iam.gserviceaccount.com

# State bucket (the one thing outside Terraform, so state has somewhere to live)
gcloud storage buckets create gs://$BUCKET --project $PROJECT --location europe-west2 \
  --uniform-bucket-level-access --public-access-prevention
gcloud storage buckets update gs://$BUCKET --versioning

# APIs needed to log in and manage IAM
gcloud services enable iam.googleapis.com iamcredentials.googleapis.com sts.googleapis.com \
  cloudresourcemanager.googleapis.com serviceusage.googleapis.com --project $PROJECT

# Accounts
gcloud iam service-accounts create fpl-terraform --project $PROJECT --display-name "Terraform apply"
gcloud iam service-accounts create fpl-terraform-plan --project $PROJECT --display-name "Terraform plan (read-only)"

# Login rule: only tokens from the infra repo are accepted at all
gcloud iam workload-identity-pools create github-ci --location global --project $PROJECT
gcloud iam workload-identity-pools providers create-oidc infra-repo --location global \
  --workload-identity-pool github-ci --project $PROJECT \
  --issuer-uri https://token.actions.githubusercontent.com \
  --attribute-mapping "google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repo_ref=assertion.repository+':'+assertion.ref" \
  --attribute-condition "assertion.repository=='$REPO'"

# Who may use which account: apply only from main, plan from any branch
gcloud iam service-accounts add-iam-policy-binding $APPLY --project $PROJECT \
  --role roles/iam.workloadIdentityUser \
  --member "principalSet://iam.googleapis.com/$POOL/attribute.repo_ref/$REPO:refs/heads/main"
gcloud iam service-accounts add-iam-policy-binding $PLAN --project $PROJECT \
  --role roles/iam.workloadIdentityUser \
  --member "principalSet://iam.googleapis.com/$POOL/attribute.repository/$REPO"

# Roles for apply. projectIamAdmin lets it grant itself any role. The billing budget needs a
# role on the billing account instead, so leave billing_account_id unset in CI.
for role in viewer serviceusage.serviceUsageAdmin iam.serviceAccountAdmin iam.serviceAccountUser \
  iam.workloadIdentityPoolAdmin resourcemanager.projectIamAdmin storage.admin \
  artifactregistry.admin secretmanager.admin run.admin workflows.admin cloudscheduler.admin \
  datastore.owner; do
  gcloud projects add-iam-policy-binding $PROJECT --member serviceAccount:$APPLY \
    --role roles/$role --condition=None >/dev/null
done

# Roles for plan: read the project, read the state, and create/delete lock files only
for role in viewer iam.securityReviewer; do
  gcloud projects add-iam-policy-binding $PROJECT --member serviceAccount:$PLAN \
    --role roles/$role --condition=None >/dev/null
done
gcloud storage buckets add-iam-policy-binding gs://$BUCKET --member serviceAccount:$PLAN \
  --role roles/storage.objectViewer

# Lock files: a conditional binding must be set as a whole policy at version 3 (gcloud's
# add-iam-policy-binding sends version 1 and fails). Export the policy, set "version": 3, add
# this to its "bindings", and set it back with `gcloud storage buckets set-iam-policy`:
#   {"members": ["serviceAccount:<plan account>"], "role": "roles/storage.objectUser",
#    "condition": {"title": "terraform-lock-files-only",
#                  "expression": "resource.name.endsWith('tflock')"}}
gcloud storage buckets get-iam-policy gs://$BUCKET --format=json > policy.json
# ...edit policy.json as above, then:
gcloud storage buckets set-iam-policy gs://$BUCKET policy.json
```

## GitHub settings (infra repo)

**Variables** (Settings > Secrets and variables > Actions > Variables). None are secret:

| Name | Value |
|---|---|
| `GCP_WIF_PROVIDER` | `projects/<number>/locations/global/workloadIdentityPools/github-ci/providers/infra-repo` |
| `GCP_TERRAFORM_SA` | `fpl-terraform@<project>.iam.gserviceaccount.com` |
| `GCP_PLANNER_SA` | `fpl-terraform-plan@<project>.iam.gserviceaccount.com` |
| `TF_STATE_BUCKET`, `PROJECT_ID`, `REGION` | as named |
| `BACKEND_REPOSITORY` | `owner/backend-repo` (the repo that deploys images) |
| `FPL_TEAM_ID`, `TELEGRAM_CHAT_ID` | your ids; use secrets instead if the repo is public |

**Environment** `production` (Settings > Environments): add yourself as a required reviewer, and
allow deployment from the `main` branch only.

**Branch protection** on `main`: require a pull request and the `terraform / validate` and
`terraform / plan` checks.

## Before the first apply

A project has one `(default)` Firestore database. Check there is none yet:
`gcloud firestore databases list --project <project>`. If there is, say so before applying,
because this Terraform creates it.
