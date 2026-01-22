#!/usr/bin/env bash
# Wrapper script for Terraform that fetches variables from GitHub
# Usage: ./tf.sh plan | ./tf.sh apply | ./tf.sh <any-terraform-command>

set -euo pipefail

# Fetch variables from GitHub
fetch_vars() {
    local var_name="$1"
    local value
    value=$(gh variable get "$var_name" 2>/dev/null) || {
        echo "Error: Failed to fetch GitHub variable '$var_name'" >&2
        echo "Ensure you're authenticated with 'gh auth login' and the variable exists." >&2
        exit 1
    }
    echo "$value"
}

# Required GitHub variables
GCP_PROJECT_ID=$(fetch_vars "GCP_PROJECT_ID")
GCP_REGION=$(fetch_vars "GCP_REGION")

# Get GitHub repo info from current repo
GITHUB_ORG=$(gh repo view --json owner -q '.owner.login')
GITHUB_REPO=$(gh repo view --json name -q '.name')

# Pass variables to terraform
exec terraform "$@" \
    -var="project_id=${GCP_PROJECT_ID}" \
    -var="region=${GCP_REGION}" \
    -var="github_org=${GITHUB_ORG}" \
    -var="github_repo=${GITHUB_REPO}"
