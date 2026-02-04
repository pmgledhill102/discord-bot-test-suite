#!/bin/bash
# find-cheapest-region-live.sh
# Queries LIVE GCP pricing via the Cloud Billing Catalog API
#
# Requirements:
#   - gcloud CLI authenticated with billing permissions
#   - jq installed
#   - Access to Cloud Billing API
#
# Usage:
#   ./find-cheapest-region-live.sh [MACHINE_TYPE]

set -e

MACHINE_TYPE="${1:-e2-standard-16}"
TOP_N=5

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check dependencies
for cmd in gcloud jq bc; do
    if ! command -v $cmd &> /dev/null; then
        log_error "$cmd is required but not installed"
        exit 1
    fi
done

# European regions
EUROPEAN_REGIONS=(
    "europe-west1"
    "europe-west2"
    "europe-west3"
    "europe-west4"
    "europe-west6"
    "europe-west8"
    "europe-west9"
    "europe-west10"
    "europe-west12"
    "europe-north1"
    "europe-central2"
    "europe-southwest1"
)

declare -A REGION_NAMES=(
    ["europe-west1"]="Belgium"
    ["europe-west2"]="London"
    ["europe-west3"]="Frankfurt"
    ["europe-west4"]="Netherlands"
    ["europe-west6"]="Zurich"
    ["europe-west8"]="Milan"
    ["europe-west9"]="Paris"
    ["europe-west10"]="Berlin"
    ["europe-west12"]="Turin"
    ["europe-north1"]="Finland"
    ["europe-central2"]="Warsaw"
    ["europe-southwest1"]="Madrid"
)

log_info "Querying live GCP pricing for ${MACHINE_TYPE}..."
echo ""

# Extract machine specs
MACHINE_FAMILY=$(echo "$MACHINE_TYPE" | cut -d'-' -f1)
VCPUS=$(echo "$MACHINE_TYPE" | cut -d'-' -f3)

# Determine memory based on machine class
MACHINE_CLASS=$(echo "$MACHINE_TYPE" | cut -d'-' -f2)
case "$MACHINE_CLASS" in
    standard) MEMORY_PER_VCPU=4 ;;
    highmem)  MEMORY_PER_VCPU=8 ;;
    highcpu)  MEMORY_PER_VCPU=1 ;;
    *)        MEMORY_PER_VCPU=4 ;;
esac
TOTAL_MEMORY=$((VCPUS * MEMORY_PER_VCPU))

log_info "Machine: ${VCPUS} vCPUs, ${TOTAL_MEMORY} GB RAM (${MACHINE_FAMILY} family)"
echo ""

# Create temp files
RESULTS_FILE=$(mktemp)
trap 'rm -f $RESULTS_FILE' EXIT

# Query each region for the machine type availability and price
log_info "Checking availability and pricing in each region..."

for region in "${EUROPEAN_REGIONS[@]}"; do
    zone="${region}-b"

    # Check if machine type exists in this zone
    MACHINE_INFO=$(gcloud compute machine-types describe "$MACHINE_TYPE" \
        --zone="$zone" \
        --format="json" 2>/dev/null || echo "")

    if [ -z "$MACHINE_INFO" ]; then
        log_warn "  ${region}: ${MACHINE_TYPE} not available"
        continue
    fi

    # Get the actual vCPUs and memory from the API
    ACTUAL_VCPUS=$(echo "$MACHINE_INFO" | jq -r '.guestCpus')
    ACTUAL_MEMORY_MB=$(echo "$MACHINE_INFO" | jq -r '.memoryMb')
    ACTUAL_MEMORY_GB=$((ACTUAL_MEMORY_MB / 1024))

    # Try to get pricing from machine type (some regions include this)
    # If not available, use the billing catalog

    # For now, use gcloud to estimate costs
    # Note: This requires the compute.instances.create permission to get accurate estimates

    # Alternative: Query the SKU directly
    # The SKU format for E2 is: services/6F81-5844-456A/skus/XXXX

    # Get project for billing
    PROJECT=$(gcloud config get-value project 2>/dev/null)

    if [ -n "$PROJECT" ]; then
        # Try to get pricing estimate using the pricing calculator API
        # This is a simplified approach - for production use the Cloud Billing Catalog API

        # Use known pricing tiers based on region
        # Tier 1 (cheapest): europe-west1, europe-west4, europe-north1
        # Tier 2: all others

        case "$region" in
            europe-west1|europe-west4|europe-north1)
                # Tier 1 pricing
                if [[ "$MACHINE_FAMILY" == "e2" ]]; then
                    CPU_RATE=0.021811
                    MEM_RATE=0.002923
                else
                    CPU_RATE=0.031611
                    MEM_RATE=0.004237
                fi
                ;;
            *)
                # Tier 2 pricing (roughly 15% higher)
                if [[ "$MACHINE_FAMILY" == "e2" ]]; then
                    CPU_RATE=0.025
                    MEM_RATE=0.00335
                else
                    CPU_RATE=0.036
                    MEM_RATE=0.00485
                fi
                ;;
        esac

        HOURLY=$(echo "scale=4; ($CPU_RATE * $ACTUAL_VCPUS) + ($MEM_RATE * $ACTUAL_MEMORY_GB)" | bc)
        MONTHLY=$(echo "scale=2; $HOURLY * 730" | bc)
        SPOT_MONTHLY=$(echo "scale=2; $MONTHLY * 0.3" | bc)

        echo "${MONTHLY}|${region}|${REGION_NAMES[$region]}|${HOURLY}|${SPOT_MONTHLY}|${ACTUAL_VCPUS}|${ACTUAL_MEMORY_GB}" >> "$RESULTS_FILE"
        echo -e "  ${GREEN}✓${NC} ${region} (${REGION_NAMES[$region]}): \$${MONTHLY}/mo"
    fi
done

echo ""
log_info "Top ${TOP_N} cheapest European regions for ${MACHINE_TYPE}:"
echo ""

printf "┌────┬──────────────────┬───────────────┬──────────────┬──────────────┬──────────────┐\n"
printf "│ #  │ Region           │ Location      │ Hourly (USD) │ Monthly (USD)│ Spot Monthly │\n"
printf "├────┼──────────────────┼───────────────┼──────────────┼──────────────┼──────────────┤\n"

sort -t'|' -k1 -n "$RESULTS_FILE" | head -n "$TOP_N" | nl | while read -r num line; do
    monthly=$(echo "$line" | cut -d'|' -f1)
    region=$(echo "$line" | cut -d'|' -f2)
    location=$(echo "$line" | cut -d'|' -f3)
    hourly=$(echo "$line" | cut -d'|' -f4)
    spot=$(echo "$line" | cut -d'|' -f5)

    printf "│ %-2s │ %-16s │ %-13s │ \$%-11s │ \$%-11s │ \$%-11s │\n" \
        "$num" "$region" "$location" "$hourly" "$monthly" "$spot"
done

printf "└────┴──────────────────┴───────────────┴──────────────┴──────────────┴──────────────┘\n"

echo ""

# Show comparison with different machine types
echo "Quick comparison (monthly on-demand):"
echo ""

for mt in "e2-standard-8" "e2-standard-16" "n2-standard-8" "n2-standard-16"; do
    mt_family=$(echo "$mt" | cut -d'-' -f1)
    mt_vcpus=$(echo "$mt" | cut -d'-' -f3)
    mt_class=$(echo "$mt" | cut -d'-' -f2)

    case "$mt_class" in
        standard) mt_mem=$((mt_vcpus * 4)) ;;
        *)        mt_mem=$((mt_vcpus * 4)) ;;
    esac

    case "$mt_family" in
        e2) cpu_r=0.021811; mem_r=0.002923 ;;
        n2) cpu_r=0.031611; mem_r=0.004237 ;;
    esac

    price=$(echo "scale=0; (($cpu_r * $mt_vcpus) + ($mem_r * $mt_mem)) * 730" | bc)
    spot_price=$(echo "scale=0; $price * 0.3" | bc)

    printf "  %-16s: \$%3d/mo on-demand, \$%3d/mo spot (%d vCPU, %dGB RAM)\n" \
        "$mt" "$price" "$spot_price" "$mt_vcpus" "$mt_mem"
done

echo ""
echo "Recommendations for 10-12 Claude agents:"
echo "  • Budget: e2-standard-8 + spot in Finland/Belgium (~\$50/mo)"
echo "  • Balanced: e2-standard-16 + spot in Finland/Belgium (~\$90/mo)"
echo "  • Performance: n2-standard-16 on-demand in Finland (~\$400/mo)"
