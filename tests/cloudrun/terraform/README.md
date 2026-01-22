# Terraform Infrastructure for Cloud Run Benchmark

This directory contains Terraform configuration for managing the core GCP infrastructure
required by the Cloud Run cold start benchmark tool.

## Resources Managed

| Resource | Purpose |
|----------|---------|
| GCP APIs | Enable required services (Cloud Run, AR, Pub/Sub, IAM) |
| Artifact Registry | `discord-services` repository for container images |
| Service Account | `cloudrun-benchmark` SA for CI/CD operations |
| IAM Bindings | Roles for Cloud Run, AR, Pub/Sub management |
| Workload Identity | GitHub Actions OIDC authentication |

## Prerequisites

1. **GCP Project**: A dedicated GCP project for benchmarking
2. **gcloud CLI**: Authenticated with project owner/editor permissions
3. **Terraform**: Version 1.5.0 or later

## Initial Setup

### 1. Configure Variables

```bash
cd tests/cloudrun/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
project_id  = "your-project-id"
region      = "europe-west1"
github_org  = "pmgledhill102"
github_repo = "discord-bot-test-suite"
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Import Existing Resources (if applicable)

If you previously created resources using `setup-gcp.sh`, import them:

```bash
# Import Artifact Registry repository
terraform import google_artifact_registry_repository.discord_services \
  projects/YOUR_PROJECT/locations/YOUR_REGION/repositories/discord-services

# Import service account
terraform import google_service_account.cloudrun_benchmark \
  projects/YOUR_PROJECT/serviceAccounts/cloudrun-benchmark@YOUR_PROJECT.iam.gserviceaccount.com

# Import WIF pool (if exists)
terraform import google_iam_workload_identity_pool.github_actions \
  projects/YOUR_PROJECT/locations/global/workloadIdentityPools/github-actions

# Import WIF provider (if exists)
terraform import google_iam_workload_identity_pool_provider.github \
  projects/YOUR_PROJECT/locations/global/workloadIdentityPools/github-actions/providers/github
```

### 4. Plan and Apply

```bash
# Review changes
terraform plan

# Apply changes
terraform apply
```

### 5. Configure GitHub Repository

After applying, configure your GitHub repository with the outputs:

```bash
# Get outputs
terraform output
```

**GitHub Variables** (Settings > Secrets and variables > Actions > Variables):

- `GCP_PROJECT_ID`: Your project ID
- `GCP_REGION`: Your region (e.g., `europe-west1`)

**GitHub Secrets** (Settings > Secrets and variables > Actions > Secrets):

- `GCP_WORKLOAD_IDENTITY_PROVIDER`: Value from `workload_identity_provider` output
- `GCP_SERVICE_ACCOUNT`: Value from `service_account_email` output

## Cleanup Policies

Artifact Registry cleanup policies are configured to manage storage costs:

| Policy | Behavior |
|--------|----------|
| Keep latest tag | Always retain images tagged `latest` |
| Keep recent versions | Keep last N tagged versions (default: 5) |
| Delete old untagged | Remove untagged images after N days (default: 7) |

**Important**: These policies apply at the repository level, not per-image. The
`keep_count` retains N versions across ALL images in the repository. For true
per-image retention, consider a scheduled cleanup job.

## File Structure

```text
terraform/
├── main.tf              # Provider configuration
├── variables.tf         # Input variables
├── outputs.tf           # Output values
├── apis.tf              # API enablement
├── artifact-registry.tf # AR repository + cleanup
├── iam.tf               # Service account + roles
├── workload-identity.tf # WIF pool + provider
├── terraform.tfvars.example
└── README.md
```

## Troubleshooting

### "Resource already exists" errors

Import existing resources (see step 3 above) before running `terraform apply`.

### "Permission denied" errors

Ensure your gcloud identity has:

- `roles/owner` or `roles/editor` on the project
- Or specific roles: `roles/iam.workloadIdentityPoolAdmin`, `roles/artifactregistry.admin`

### Workload Identity not working

1. Verify the attribute condition matches your repository exactly
2. Check GitHub Actions has `id-token: write` permission
3. Confirm the service account email and provider name are correct in GitHub secrets
