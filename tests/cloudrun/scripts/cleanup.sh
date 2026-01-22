#!/usr/bin/env bash
#
# cleanup.sh - Delete GCP resources created by benchmark runs
#
# Usage:
#   export PROJECT_ID=your-project-id
#   ./cleanup.sh [options]
#
# Options:
#   --run-id <id>       Delete only resources for a specific run
#   --all               Delete everything including AR images
#   --keep-images       Preserve Artifact Registry images (default)
#   --dry-run           Show what would be deleted without deleting
#   --older-than <dur>  Delete resources older than duration (e.g., "1h", "24h")
#
set -euo pipefail

# Configuration
REGION="${REGION:-us-central1}"
AR_REPOSITORY="discord-services"

# Options
RUN_ID=""
DELETE_IMAGES=false
DRY_RUN=false
OLDER_THAN=""

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

log_dry() {
    echo -e "${BLUE}[DRY-RUN]${NC} Would delete: $1"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --run-id)
            RUN_ID="$2"
            shift 2
            ;;
        --all)
            DELETE_IMAGES=true
            shift
            ;;
        --keep-images)
            DELETE_IMAGES=false
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --older-than)
            OLDER_THAN="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: ./cleanup.sh [options]"
            echo ""
            echo "Options:"
            echo "  --run-id <id>       Delete only resources for a specific run"
            echo "  --all               Delete everything including AR images"
            echo "  --keep-images       Preserve Artifact Registry images (default)"
            echo "  --dry-run           Show what would be deleted without deleting"
            echo "  --older-than <dur>  Delete resources older than duration (e.g., '1h', '24h')"
            echo ""
            echo "Environment variables:"
            echo "  PROJECT_ID          GCP project ID (required)"
            echo "  REGION              GCP region (default: us-central1)"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate required environment variables
if [[ -z "${PROJECT_ID:-}" ]]; then
    log_error "PROJECT_ID environment variable is required"
    exit 1
fi

log_info "Cleaning up GCP resources"
log_info "Project: ${PROJECT_ID}"
log_info "Region: ${REGION}"
if [[ -n "${RUN_ID}" ]]; then
    log_info "Run ID: ${RUN_ID}"
fi
if [[ "${DRY_RUN}" == "true" ]]; then
    log_warn "DRY RUN MODE - No resources will be deleted"
fi
echo ""

# Track what was deleted
DELETED_SERVICES=0
DELETED_TOPICS=0
DELETED_SUBSCRIPTIONS=0
DELETED_IMAGES=0

# Delete Cloud Run services
log_info "Checking Cloud Run services..."
SERVICES=$(gcloud run services list \
    --project="${PROJECT_ID}" \
    --region="${REGION}" \
    --format="value(name)" \
    --filter="name~^discord-" 2>/dev/null || echo "")

for service in ${SERVICES}; do
    # If run-id specified, only delete matching services
    if [[ -n "${RUN_ID}" ]] && [[ ! "${service}" == *"-${RUN_ID}" ]]; then
        continue
    fi

    # Check age if --older-than specified
    if [[ -n "${OLDER_THAN}" ]]; then
        CREATE_TIME=$(gcloud run services describe "${service}" \
            --project="${PROJECT_ID}" \
            --region="${REGION}" \
            --format="value(metadata.creationTimestamp)" 2>/dev/null || echo "")

        if [[ -n "${CREATE_TIME}" ]]; then
            CREATE_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${CREATE_TIME%Z}" "+%s" 2>/dev/null || echo "0")
            NOW_EPOCH=$(date "+%s")

            # Parse duration (simple h/d/m parsing)
            OLDER_SECONDS=0
            if [[ "${OLDER_THAN}" =~ ^([0-9]+)h$ ]]; then
                OLDER_SECONDS=$((${BASH_REMATCH[1]} * 3600))
            elif [[ "${OLDER_THAN}" =~ ^([0-9]+)d$ ]]; then
                OLDER_SECONDS=$((${BASH_REMATCH[1]} * 86400))
            elif [[ "${OLDER_THAN}" =~ ^([0-9]+)m$ ]]; then
                OLDER_SECONDS=$((${BASH_REMATCH[1]} * 60))
            fi

            AGE=$((NOW_EPOCH - CREATE_EPOCH))
            if [[ ${AGE} -lt ${OLDER_SECONDS} ]]; then
                continue
            fi
        fi
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Cloud Run service: ${service}"
    else
        log_info "Deleting Cloud Run service: ${service}"
        if gcloud run services delete "${service}" \
            --project="${PROJECT_ID}" \
            --region="${REGION}" \
            --quiet 2>/dev/null; then
            ((DELETED_SERVICES++))
        else
            log_warn "Failed to delete service: ${service}"
        fi
    fi
done

# Delete Pub/Sub subscriptions
log_info "Checking Pub/Sub subscriptions..."
SUBSCRIPTIONS=$(gcloud pubsub subscriptions list \
    --project="${PROJECT_ID}" \
    --format="value(name)" \
    --filter="name~discord-benchmark" 2>/dev/null || echo "")

for sub in ${SUBSCRIPTIONS}; do
    # Extract subscription name from full path
    SUB_NAME=$(basename "${sub}")

    # If run-id specified, only delete matching subscriptions
    if [[ -n "${RUN_ID}" ]] && [[ ! "${SUB_NAME}" == *"${RUN_ID}"* ]]; then
        continue
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Pub/Sub subscription: ${SUB_NAME}"
    else
        log_info "Deleting Pub/Sub subscription: ${SUB_NAME}"
        if gcloud pubsub subscriptions delete "${SUB_NAME}" \
            --project="${PROJECT_ID}" \
            --quiet 2>/dev/null; then
            ((DELETED_SUBSCRIPTIONS++))
        else
            log_warn "Failed to delete subscription: ${SUB_NAME}"
        fi
    fi
done

# Delete Pub/Sub topics
log_info "Checking Pub/Sub topics..."
TOPICS=$(gcloud pubsub topics list \
    --project="${PROJECT_ID}" \
    --format="value(name)" \
    --filter="name~discord-benchmark" 2>/dev/null || echo "")

for topic in ${TOPICS}; do
    # Extract topic name from full path
    TOPIC_NAME=$(basename "${topic}")

    # If run-id specified, only delete matching topics
    if [[ -n "${RUN_ID}" ]] && [[ ! "${TOPIC_NAME}" == *"${RUN_ID}"* ]]; then
        continue
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Pub/Sub topic: ${TOPIC_NAME}"
    else
        log_info "Deleting Pub/Sub topic: ${TOPIC_NAME}"
        if gcloud pubsub topics delete "${TOPIC_NAME}" \
            --project="${PROJECT_ID}" \
            --quiet 2>/dev/null; then
            ((DELETED_TOPICS++))
        else
            log_warn "Failed to delete topic: ${TOPIC_NAME}"
        fi
    fi
done

# Delete Artifact Registry images (if --all specified)
if [[ "${DELETE_IMAGES}" == "true" ]]; then
    log_info "Checking Artifact Registry images..."
    IMAGES=$(gcloud artifacts docker images list \
        "${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPOSITORY}" \
        --format="value(package)" \
        --include-tags 2>/dev/null || echo "")

    for image in ${IMAGES}; do
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_dry "AR image: ${image}"
        else
            log_info "Deleting AR image: ${image}"
            if gcloud artifacts docker images delete "${image}" \
                --quiet \
                --delete-tags 2>/dev/null; then
                ((DELETED_IMAGES++))
            else
                log_warn "Failed to delete image: ${image}"
            fi
        fi
    done
else
    log_info "Skipping Artifact Registry images (use --all to delete)"
fi

# Summary
echo ""
log_info "=========================================="
log_info "Cleanup Summary"
log_info "=========================================="
if [[ "${DRY_RUN}" == "true" ]]; then
    echo "DRY RUN - No resources were deleted"
else
    echo "Cloud Run services deleted: ${DELETED_SERVICES}"
    echo "Pub/Sub topics deleted: ${DELETED_TOPICS}"
    echo "Pub/Sub subscriptions deleted: ${DELETED_SUBSCRIPTIONS}"
    if [[ "${DELETE_IMAGES}" == "true" ]]; then
        echo "AR images deleted: ${DELETED_IMAGES}"
    fi
fi
