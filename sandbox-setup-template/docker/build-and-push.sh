#!/bin/bash
set -e

# Build and push Claude Code agent images to Artifact Registry

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
REGION="${REGION:-us-central1}"
REGISTRY="${REGION}-docker.pkg.dev/${PROJECT_ID}/claude-sandbox"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check prerequisites
if [ -z "$PROJECT_ID" ]; then
    log_error "PROJECT_ID not set. Run: gcloud config set project YOUR_PROJECT"
    exit 1
fi

log_info "Project: $PROJECT_ID"
log_info "Registry: $REGISTRY"

# Create Artifact Registry repository if it doesn't exist
log_info "Ensuring Artifact Registry repository exists..."
gcloud artifacts repositories describe claude-sandbox \
    --location="$REGION" \
    --project="$PROJECT_ID" 2>/dev/null || \
gcloud artifacts repositories create claude-sandbox \
    --repository-format=docker \
    --location="$REGION" \
    --description="Claude Code sandbox agent images" \
    --project="$PROJECT_ID"

# Configure Docker to use gcloud credentials
log_info "Configuring Docker authentication..."
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

# Build base image
log_info "Building base image..."
docker build \
    -t claude-sandbox-base:latest \
    -t "${REGISTRY}/base:latest" \
    -t "${REGISTRY}/base:$(date +%Y%m%d)" \
    -f "${SCRIPT_DIR}/Dockerfile.base" \
    "${SCRIPT_DIR}/.."

# Build agent image
log_info "Building agent image..."
docker build \
    --build-arg BASE_IMAGE=claude-sandbox-base:latest \
    -t claude-sandbox-agent:latest \
    -t "${REGISTRY}/agent:latest" \
    -t "${REGISTRY}/agent:$(date +%Y%m%d)" \
    -f "${SCRIPT_DIR}/Dockerfile" \
    "${SCRIPT_DIR}"

# Push images
log_info "Pushing images to Artifact Registry..."
docker push "${REGISTRY}/base:latest"
docker push "${REGISTRY}/base:$(date +%Y%m%d)"
docker push "${REGISTRY}/agent:latest"
docker push "${REGISTRY}/agent:$(date +%Y%m%d)"

log_info "Done! Images pushed to:"
log_info "  - ${REGISTRY}/base:latest"
log_info "  - ${REGISTRY}/agent:latest"
