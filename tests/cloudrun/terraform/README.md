# Terraform Infrastructure for Cloud Run Benchmark

This directory contains Terraform configuration for managing the core GCP infrastructure
required by the Cloud Run cold start benchmark tool.

## Resources Managed

| Resource          | Purpose                                                        |
| ----------------- | -------------------------------------------------------------- |
| GCP APIs          | Enable required services (Cloud Run, AR, Pub/Sub, IAM)         |
| Artifact Registry | `discord-services` repository for container images             |
| Service Accounts  | `cloudrun-benchmark` (CI/CD) and `cloudrun-runtime` (services) |
| IAM Bindings      | Roles for Cloud Run, AR, Pub/Sub, logging, monitoring          |
| Workload Identity | GitHub Actions OIDC authentication                             |

## Service Accounts

Two service accounts with distinct responsibilities:

### `cloudrun-benchmark` (CI/CD + Terminal)

Used by GitHub Actions and terminal via `gcloud auth`.

| Role                            | Purpose                                |
| ------------------------------- | -------------------------------------- |
| `roles/run.admin`               | Deploy and manage Cloud Run services   |
| `roles/artifactregistry.writer` | Push images to AR                      |
| `roles/artifactregistry.reader` | List/query images in AR                |
| `roles/pubsub.admin`            | Create test topics/subscriptions       |
| `roles/logging.viewer`          | View Cloud Run logs                    |
| `roles/monitoring.viewer`       | View metrics and dashboards            |
| `roles/iam.serviceAccountUser`  | Impersonate runtime SA for deployments |

### `cloudrun-runtime` (Cloud Run Services)

Used by Cloud Run services at runtime. Specified via `--service-account` when deploying.

| Role                     | Purpose                            |
| ------------------------ | ---------------------------------- |
| `roles/pubsub.publisher` | Publish messages to Pub/Sub topics |

## Prerequisites

1. **GCP Project**: A dedicated GCP project for benchmarking
2. **gcloud CLI**: Authenticated with project owner/editor permissions
3. **Terraform**: Version 1.5.0 or later
4. **GitHub CLI**: Authenticated with `gh auth login` (for `./tf.sh` wrapper)

## Remote State

Terraform state is stored in a GCS bucket for collaboration across devices:

- **Bucket**: `{project-id}-terraform-state`
- **Prefix**: `cloudrun-benchmark`
- **Versioning**: Enabled (for state recovery)

The bucket must be created before `terraform init` (chicken-and-egg problem).

## Initial Setup

### 1. Set GitHub Variables

Ensure these GitHub repository variables are set (used by `./tf.sh`):

```bash
gh variable set GCP_PROJECT_ID --body "your-project-id"
gh variable set GCP_REGION --body "europe-west1"
```

### 2. Create State Bucket

Create the GCS bucket for Terraform state (must exist before `terraform init`):

```bash
PROJECT_ID=$(gh variable get GCP_PROJECT_ID)
REGION=$(gh variable get GCP_REGION)

gcloud storage buckets create gs://${PROJECT_ID}-terraform-state \
  --project=${PROJECT_ID} \
  --location=${REGION} \
  --uniform-bucket-level-access \
  --public-access-prevention

gcloud storage buckets update gs://${PROJECT_ID}-terraform-state --versioning
```

### 3. Initialize Terraform

```bash
cd tests/cloudrun/terraform
terraform init
```

### 4. Plan and Apply

Use the `./tf.sh` wrapper script which fetches variables from GitHub:

```bash
# Review changes
./tf.sh plan

# Apply changes
./tf.sh apply
```

The wrapper fetches `GCP_PROJECT_ID` and `GCP_REGION` from GitHub variables and
derives `github_org`/`github_repo` from the current repository. This avoids
storing project-specific values in the repo.

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
- `GCP_RUNTIME_SERVICE_ACCOUNT`: Value from `runtime_service_account_email` output (for Cloud Run deployments)

## Cleanup Policies

Artifact Registry cleanup policies are configured to manage storage costs:

| Policy               | Behavior                                         |
| -------------------- | ------------------------------------------------ |
| Keep latest tag      | Always retain images tagged `latest`             |
| Keep recent versions | Keep last N tagged versions (default: 5)         |
| Delete old untagged  | Remove untagged images after N days (default: 7) |

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
├── iam.tf               # Service accounts + roles
├── workload-identity.tf # WIF pool + provider
├── tf.sh                # Wrapper script (fetches vars from GitHub)
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
