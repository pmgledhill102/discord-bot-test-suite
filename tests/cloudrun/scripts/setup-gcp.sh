#!/usr/bin/env bash
#
# setup-gcp.sh - Initialize GCP infrastructure for Cloud Run benchmarks
#
# This script is idempotent and can be run multiple times safely.
#
# Usage:
#   export PROJECT_ID=your-project-id
#   ./setup-gcp.sh
#
set -euo pipefail

# Configuration
REGION="${REGION:-us-central1}"
SERVICE_ACCOUNT_NAME="cloudrun-benchmark"
AR_REPOSITORY="discord-services"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Validate required environment variables
if [[ -z "${PROJECT_ID:-}" ]]; then
    log_error "PROJECT_ID environment variable is required"
    echo "Usage: PROJECT_ID=your-project-id ./setup-gcp.sh"
    exit 1
fi

SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

log_info "Setting up GCP infrastructure for Cloud Run benchmarks"
log_info "Project: ${PROJECT_ID}"
log_info "Region: ${REGION}"

# Set the project
log_info "Setting active project..."
gcloud config set project "${PROJECT_ID}"

# Enable required APIs
log_info "Enabling required APIs..."
APIS=(
    "run.googleapis.com"
    "artifactregistry.googleapis.com"
    "pubsub.googleapis.com"
    "logging.googleapis.com"
    "monitoring.googleapis.com"
    "cloudscheduler.googleapis.com"
    "cloudbuild.googleapis.com"
)

for api in "${APIS[@]}"; do
    log_info "  Enabling ${api}..."
    gcloud services enable "${api}" --quiet
done

# Create service account if it doesn't exist
log_info "Creating service account..."
if gcloud iam service-accounts describe "${SERVICE_ACCOUNT_EMAIL}" &>/dev/null; then
    log_warn "Service account ${SERVICE_ACCOUNT_EMAIL} already exists"
else
    gcloud iam service-accounts create "${SERVICE_ACCOUNT_NAME}" \
        --display-name="Cloud Run Benchmark Service Account" \
        --description="Service account for running Cloud Run cold start benchmarks"
    log_info "Created service account ${SERVICE_ACCOUNT_EMAIL}"
fi

# Grant IAM roles to the service account
log_info "Granting IAM roles to service account..."
ROLES=(
    "roles/run.admin"
    "roles/artifactregistry.writer"
    "roles/pubsub.admin"
    "roles/logging.viewer"
    "roles/monitoring.viewer"
    "roles/iam.serviceAccountUser"
)

for role in "${ROLES[@]}"; do
    log_info "  Granting ${role}..."
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
        --role="${role}" \
        --quiet \
        --condition=None
done

# Create Artifact Registry repository if it doesn't exist
log_info "Creating Artifact Registry repository..."
if gcloud artifacts repositories describe "${AR_REPOSITORY}" \
    --location="${REGION}" &>/dev/null; then
    log_warn "Repository ${AR_REPOSITORY} already exists in ${REGION}"
else
    gcloud artifacts repositories create "${AR_REPOSITORY}" \
        --repository-format=docker \
        --location="${REGION}" \
        --description="Docker images for Discord webhook services"
    log_info "Created Artifact Registry repository: ${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPOSITORY}"
fi

# Configure Docker authentication for Artifact Registry
log_info "Configuring Docker authentication for Artifact Registry..."
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

# Output summary
echo ""
log_info "=========================================="
log_info "GCP Infrastructure Setup Complete"
log_info "=========================================="
echo ""
echo "Project ID:        ${PROJECT_ID}"
echo "Region:            ${REGION}"
echo "Service Account:   ${SERVICE_ACCOUNT_EMAIL}"
echo "AR Repository:     ${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPOSITORY}"
echo ""
echo "Next steps:"
echo "  1. Build and push images:  ./build-push-images.sh"
echo "  2. Run benchmarks:         cloudrun-benchmark run --config configs/default.yaml"
echo ""
