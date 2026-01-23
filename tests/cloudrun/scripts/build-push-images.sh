#!/usr/bin/env bash
#
# build-push-images.sh - Build and push all service Docker images to Artifact Registry
#
# Usage:
#   export PROJECT_ID=your-project-id
#   ./build-push-images.sh [service1 service2 ...]
#
# Examples:
#   ./build-push-images.sh                    # Build all services
#   ./build-push-images.sh go-gin rust-actix  # Build specific services
#
set -euo pipefail

# Configuration
REGION="${REGION:-us-central1}"
AR_REPOSITORY="discord-services"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
SERVICES_DIR="${REPO_ROOT}/services"

# Source the services library
export PROJECT_ROOT="${REPO_ROOT}"
source "${REPO_ROOT}/scripts/lib/services.sh"

# Get all available services from YAML (bash 3.2 compatible)
ALL_SERVICES=()
while IFS= read -r service; do
    ALL_SERVICES+=("$service")
done < <(get_all_services)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Validate required environment variables
if [[ -z "${PROJECT_ID:-}" ]]; then
    log_error "PROJECT_ID environment variable is required"
    echo "Usage: PROJECT_ID=your-project-id ./build-push-images.sh [service1 service2 ...]"
    exit 1
fi

# Determine which services to build
if [[ $# -gt 0 ]]; then
    SERVICES=("$@")
else
    SERVICES=("${ALL_SERVICES[@]}")
fi

# Get git SHA for tagging
GIT_SHA=$(git -C "${REPO_ROOT}" rev-parse --short HEAD)
IMAGE_REGISTRY="${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPOSITORY}"

log_info "Building and pushing Docker images"
log_info "Registry: ${IMAGE_REGISTRY}"
log_info "Git SHA: ${GIT_SHA}"
log_info "Services: ${SERVICES[*]}"
echo ""

# Track results
SUCCESSFUL=()
FAILED=()
DIGESTS=()

# Build and push each service
for service in "${SERVICES[@]}"; do
    SERVICE_DIR="${SERVICES_DIR}/${service}"

    if [[ ! -d "${SERVICE_DIR}" ]]; then
        log_error "Service directory not found: ${SERVICE_DIR}"
        FAILED+=("${service}")
        continue
    fi

    if [[ ! -f "${SERVICE_DIR}/Dockerfile" ]]; then
        log_error "Dockerfile not found for ${service}"
        FAILED+=("${service}")
        continue
    fi

    IMAGE_NAME="${IMAGE_REGISTRY}/${service}"

    log_step "Building ${service}..."

    # Build the image (always target linux/amd64 for Cloud Run)
    if ! docker build \
        --platform linux/amd64 \
        -t "${IMAGE_NAME}:${GIT_SHA}" \
        -t "${IMAGE_NAME}:latest" \
        "${SERVICE_DIR}" 2>&1; then
        log_error "Failed to build ${service}"
        FAILED+=("${service}")
        continue
    fi

    log_step "Pushing ${service}..."

    # Push both tags
    if ! docker push "${IMAGE_NAME}:${GIT_SHA}" 2>&1; then
        log_error "Failed to push ${service}:${GIT_SHA}"
        FAILED+=("${service}")
        continue
    fi

    if ! docker push "${IMAGE_NAME}:latest" 2>&1; then
        log_error "Failed to push ${service}:latest"
        FAILED+=("${service}")
        continue
    fi

    # Get the image digest
    DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "${IMAGE_NAME}:${GIT_SHA}" 2>/dev/null || echo "unknown")

    log_info "Successfully built and pushed ${service}"
    SUCCESSFUL+=("${service}")
    DIGESTS+=("${service}:${DIGEST}")
done

# Output summary
echo ""
log_info "=========================================="
log_info "Build Summary"
log_info "=========================================="
echo ""
echo "Successful: ${#SUCCESSFUL[@]}/${#SERVICES[@]}"
for service in "${SUCCESSFUL[@]}"; do
    echo "  ${GREEN}✓${NC} ${service}"
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo ""
    echo "Failed: ${#FAILED[@]}/${#SERVICES[@]}"
    for service in "${FAILED[@]}"; do
        echo "  ${RED}✗${NC} ${service}"
    done
fi

# Output digests for use in deployments
echo ""
log_info "Image Digests:"
for digest in "${DIGESTS[@]}"; do
    echo "  ${digest}"
done

# Write digests to file for later use
DIGEST_FILE="${SCRIPT_DIR}/../results/image-digests.txt"
mkdir -p "$(dirname "${DIGEST_FILE}")"
{
    echo "# Image digests built at $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "# Git SHA: ${GIT_SHA}"
    echo "# Registry: ${IMAGE_REGISTRY}"
    for digest in "${DIGESTS[@]}"; do
        echo "${digest}"
    done
} > "${DIGEST_FILE}"
log_info "Digests written to: ${DIGEST_FILE}"

# Exit with error if any builds failed
if [[ ${#FAILED[@]} -gt 0 ]]; then
    exit 1
fi
