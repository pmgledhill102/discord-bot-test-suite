#!/usr/bin/env bash
#
# setup-scheduled-cleanup.sh - Set up a Cloud Scheduler job for daily resource cleanup
#
# This creates a Cloud Scheduler job that triggers a Cloud Run Job to clean up
# any orphaned resources in the benchmark project.
#
# Usage:
#   export PROJECT_ID=your-project-id
#   ./setup-scheduled-cleanup.sh
#
set -euo pipefail

# Configuration
REGION="${REGION:-us-central1}"
JOB_NAME="discord-benchmark-cleanup"
SCHEDULE="0 2 * * *"  # 2am UTC daily
SERVICE_ACCOUNT_NAME="cloudrun-benchmark"

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
    exit 1
fi

SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

log_info "Setting up scheduled cleanup job"
log_info "Project: ${PROJECT_ID}"
log_info "Region: ${REGION}"
log_info "Schedule: ${SCHEDULE} (2am UTC daily)"

# Create the Cloud Run Job for cleanup
log_info "Creating Cloud Run cleanup job..."

# First, build and push a cleanup container
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEANUP_IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/discord-services/cleanup:latest"

# Create a simple Dockerfile for cleanup
TEMP_DIR=$(mktemp -d)
cat > "${TEMP_DIR}/Dockerfile" << 'DOCKERFILE'
FROM google/cloud-sdk:slim

# Copy cleanup script
COPY cleanup.sh /cleanup.sh
RUN chmod +x /cleanup.sh

ENTRYPOINT ["/cleanup.sh"]
DOCKERFILE

# Copy cleanup script
cp "${SCRIPT_DIR}/cleanup.sh" "${TEMP_DIR}/"

log_info "Building cleanup container..."
docker build -t "${CLEANUP_IMAGE}" "${TEMP_DIR}"
docker push "${CLEANUP_IMAGE}"

rm -rf "${TEMP_DIR}"

# Create/update the Cloud Run Job
log_info "Creating Cloud Run Job..."
if gcloud run jobs describe "${JOB_NAME}" \
    --project="${PROJECT_ID}" \
    --region="${REGION}" &>/dev/null; then
    log_warn "Job ${JOB_NAME} already exists, updating..."
    gcloud run jobs update "${JOB_NAME}" \
        --project="${PROJECT_ID}" \
        --region="${REGION}" \
        --image="${CLEANUP_IMAGE}" \
        --set-env-vars="PROJECT_ID=${PROJECT_ID},REGION=${REGION}" \
        --service-account="${SERVICE_ACCOUNT_EMAIL}" \
        --task-timeout=600s
else
    gcloud run jobs create "${JOB_NAME}" \
        --project="${PROJECT_ID}" \
        --region="${REGION}" \
        --image="${CLEANUP_IMAGE}" \
        --set-env-vars="PROJECT_ID=${PROJECT_ID},REGION=${REGION}" \
        --service-account="${SERVICE_ACCOUNT_EMAIL}" \
        --task-timeout=600s
fi

# Create/update Cloud Scheduler job
log_info "Creating Cloud Scheduler job..."
SCHEDULER_JOB_NAME="discord-benchmark-daily-cleanup"

if gcloud scheduler jobs describe "${SCHEDULER_JOB_NAME}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" &>/dev/null; then
    log_warn "Scheduler job ${SCHEDULER_JOB_NAME} already exists, updating..."
    gcloud scheduler jobs update http "${SCHEDULER_JOB_NAME}" \
        --project="${PROJECT_ID}" \
        --location="${REGION}" \
        --schedule="${SCHEDULE}" \
        --time-zone="UTC" \
        --uri="https://${REGION}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${PROJECT_ID}/jobs/${JOB_NAME}:run" \
        --http-method=POST \
        --oauth-service-account-email="${SERVICE_ACCOUNT_EMAIL}"
else
    gcloud scheduler jobs create http "${SCHEDULER_JOB_NAME}" \
        --project="${PROJECT_ID}" \
        --location="${REGION}" \
        --schedule="${SCHEDULE}" \
        --time-zone="UTC" \
        --uri="https://${REGION}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${PROJECT_ID}/jobs/${JOB_NAME}:run" \
        --http-method=POST \
        --oauth-service-account-email="${SERVICE_ACCOUNT_EMAIL}"
fi

# Summary
echo ""
log_info "=========================================="
log_info "Scheduled Cleanup Setup Complete"
log_info "=========================================="
echo ""
echo "Cloud Run Job:     ${JOB_NAME}"
echo "Scheduler Job:     ${SCHEDULER_JOB_NAME}"
echo "Schedule:          ${SCHEDULE} (2am UTC daily)"
echo "Service Account:   ${SERVICE_ACCOUNT_EMAIL}"
echo ""
echo "To run cleanup manually:"
echo "  gcloud run jobs execute ${JOB_NAME} --project=${PROJECT_ID} --region=${REGION}"
echo ""
echo "To check scheduler status:"
echo "  gcloud scheduler jobs describe ${SCHEDULER_JOB_NAME} --project=${PROJECT_ID} --location=${REGION}"
