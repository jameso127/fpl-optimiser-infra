#!/usr/bin/env bash
# Copy the Terraform outputs the backend repo needs into its GitHub Actions variables.
# Needs: terraform (already applied), jq, and the GitHub CLI logged in with access to the repo.
#
#   ./scripts/set-github-variables.sh your-github-user/fpl-optimiser-backend
set -euo pipefail

repo="${1:?usage: $0 <owner/backend-repo>}"

terraform output -json github_actions_variables \
  | jq -r 'to_entries[] | "\(.key)=\(.value)"' \
  | while IFS='=' read -r name value; do
      echo "setting ${name}"
      gh variable set "${name}" --repo "${repo}" --body "${value}"
    done
