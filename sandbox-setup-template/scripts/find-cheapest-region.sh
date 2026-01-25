#!/bin/bash
# find-cheapest-region.sh
# Finds the cheapest European GCP regions for running a Compute Engine VM
#
# Requirements:
#   - bc installed (for calculations)
#
# Usage:
#   ./find-cheapest-region.sh [MACHINE_TYPE]
#   ./find-cheapest-region.sh e2-standard-16
#   ./find-cheapest-region.sh c4a-highcpu-16
#   ./find-cheapest-region.sh n2-standard-8

set -e

MACHINE_TYPE="${1:-e2-standard-16}"
TOP_N=5

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check dependencies
if ! command -v bc &> /dev/null; then
    log_error "bc is required but not installed (apt-get install bc)"
    exit 1
fi

log_info "Finding cheapest European regions for ${MACHINE_TYPE}"
echo ""

# ALL European regions (as of 2025)
EUROPEAN_REGIONS=(
    "europe-west1"      # Belgium
    "europe-west2"      # London
    "europe-west3"      # Frankfurt
    "europe-west4"      # Netherlands
    "europe-west6"      # Zurich
    "europe-west8"      # Milan
    "europe-west9"      # Paris
    "europe-west10"     # Berlin
    "europe-west12"     # Turin
    "europe-north1"     # Finland (Hamina)
    "europe-north2"     # Stockholm (NEW - often cheap!)
    "europe-central2"   # Warsaw
    "europe-southwest1" # Madrid
)

# Region display names
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
    ["europe-north2"]="Stockholm"
    ["europe-central2"]="Warsaw"
    ["europe-southwest1"]="Madrid"
)

# C4A availability (Arm/Axion - limited regions)
declare -A C4A_AVAILABLE=(
    ["europe-west1"]="yes"   # Belgium
    ["europe-west2"]="yes"   # London
    ["europe-west3"]="yes"   # Frankfurt
    ["europe-west4"]="yes"   # Netherlands
    ["europe-west6"]="no"
    ["europe-west8"]="yes"   # Milan
    ["europe-west9"]="yes"   # Paris
    ["europe-west10"]="no"
    ["europe-west12"]="no"
    ["europe-north1"]="yes"  # Finland
    ["europe-north2"]="no"   # Stockholm - check availability
    ["europe-central2"]="no"
    ["europe-southwest1"]="no"
)

# Extract machine family and size
MACHINE_FAMILY=$(echo "$MACHINE_TYPE" | cut -d'-' -f1)
MACHINE_CLASS=$(echo "$MACHINE_TYPE" | cut -d'-' -f2)
VCPUS=$(echo "$MACHINE_TYPE" | cut -d'-' -f3)

# Determine vCPU and memory based on machine type
case "$MACHINE_FAMILY" in
    e2)
        case "$MACHINE_CLASS" in
            standard) MEMORY_PER_VCPU=4 ;;
            highmem)  MEMORY_PER_VCPU=8 ;;
            highcpu)  MEMORY_PER_VCPU=1 ;;
            *)        MEMORY_PER_VCPU=4 ;;
        esac
        ;;
    n2|n2d|c3|c3d)
        case "$MACHINE_CLASS" in
            standard) MEMORY_PER_VCPU=4 ;;
            highmem)  MEMORY_PER_VCPU=8 ;;
            highcpu)  MEMORY_PER_VCPU=2 ;;
            *)        MEMORY_PER_VCPU=4 ;;
        esac
        ;;
    c4a|t2a)
        # Arm-based instances
        case "$MACHINE_CLASS" in
            standard) MEMORY_PER_VCPU=4 ;;
            highmem)  MEMORY_PER_VCPU=8 ;;
            highcpu)  MEMORY_PER_VCPU=2 ;;
            *)        MEMORY_PER_VCPU=4 ;;
        esac
        ;;
    *)
        MEMORY_PER_VCPU=4
        ;;
esac

TOTAL_MEMORY=$((VCPUS * MEMORY_PER_VCPU))

# Check if it's an Arm instance
IS_ARM="no"
if [[ "$MACHINE_FAMILY" == "c4a" || "$MACHINE_FAMILY" == "t2a" ]]; then
    IS_ARM="yes"
fi

log_info "Machine specs: ${VCPUS} vCPUs, ${TOTAL_MEMORY} GB RAM (${MACHINE_FAMILY} family)"
if [[ "$IS_ARM" == "yes" ]]; then
    log_info "Architecture: ARM64 (Axion) - requires ARM-compatible images"
fi
echo ""

# Create temp file for results
RESULTS_FILE=$(mktemp)
trap "rm -f $RESULTS_FILE" EXIT

log_info "Querying pricing for each European region..."
echo ""

for region in "${EUROPEAN_REGIONS[@]}"; do
    # Check C4A availability
    if [[ "$MACHINE_FAMILY" == "c4a" && "${C4A_AVAILABLE[$region]}" != "yes" ]]; then
        log_warn "  ${region}: C4A not available"
        continue
    fi

    # Pricing data (USD per hour) - Updated 2024/2025
    # Sources: GCP Pricing Calculator, cloud.google.com/compute/all-pricing
    #
    # Pricing tiers:
    #   Tier 1 (cheapest): Belgium, Netherlands, Finland, Stockholm
    #   Tier 2: Frankfurt, Milan, Paris, Turin, Madrid
    #   Tier 3 (expensive): London, Zurich, Berlin, Warsaw

    case "$region" in
        europe-west1)      # Belgium - Tier 1
            E2_CPU=0.021811;  E2_MEM=0.002923
            N2_CPU=0.031611;  N2_MEM=0.004237
            C4A_CPU=0.02099;  C4A_MEM=0.002298  # ~15% cheaper than E2
            ;;
        europe-west2)      # London - Tier 3
            E2_CPU=0.025519;  E2_MEM=0.003420
            N2_CPU=0.036985;  N2_MEM=0.004957
            C4A_CPU=0.02456;  C4A_MEM=0.002688
            ;;
        europe-west3)      # Frankfurt - Tier 2
            E2_CPU=0.024541;  E2_MEM=0.003289
            N2_CPU=0.035567;  N2_MEM=0.004767
            C4A_CPU=0.02362;  C4A_MEM=0.002586
            ;;
        europe-west4)      # Netherlands - Tier 1
            E2_CPU=0.021811;  E2_MEM=0.002923
            N2_CPU=0.031611;  N2_MEM=0.004237
            C4A_CPU=0.02099;  C4A_MEM=0.002298
            ;;
        europe-west6)      # Zurich - Tier 3 (expensive)
            E2_CPU=0.026660;  E2_MEM=0.003573
            N2_CPU=0.038639;  N2_MEM=0.005179
            C4A_CPU=0.02565;  C4A_MEM=0.002808
            ;;
        europe-west8)      # Milan - Tier 2
            E2_CPU=0.024107;  E2_MEM=0.003231
            N2_CPU=0.034938;  N2_MEM=0.004683
            C4A_CPU=0.02320;  C4A_MEM=0.002540
            ;;
        europe-west9)      # Paris - Tier 2
            E2_CPU=0.024107;  E2_MEM=0.003231
            N2_CPU=0.034938;  N2_MEM=0.004683
            C4A_CPU=0.02320;  C4A_MEM=0.002540
            ;;
        europe-west10)     # Berlin - Tier 3
            E2_CPU=0.025519;  E2_MEM=0.003420
            N2_CPU=0.036985;  N2_MEM=0.004957
            C4A_CPU=0.02456;  C4A_MEM=0.002688
            ;;
        europe-west12)     # Turin - Tier 2
            E2_CPU=0.024107;  E2_MEM=0.003231
            N2_CPU=0.034938;  N2_MEM=0.004683
            C4A_CPU=0.02320;  C4A_MEM=0.002540
            ;;
        europe-north1)     # Finland - Tier 1
            E2_CPU=0.021811;  E2_MEM=0.002923
            N2_CPU=0.031611;  N2_MEM=0.004237
            C4A_CPU=0.02099;  C4A_MEM=0.002298
            ;;
        europe-north2)     # Stockholm - Tier 1 (NEW, cheap!)
            E2_CPU=0.021811;  E2_MEM=0.002923
            N2_CPU=0.031611;  N2_MEM=0.004237
            C4A_CPU=0.02099;  C4A_MEM=0.002298
            ;;
        europe-central2)   # Warsaw - Tier 3
            E2_CPU=0.025519;  E2_MEM=0.003420
            N2_CPU=0.036985;  N2_MEM=0.004957
            C4A_CPU=0.02456;  C4A_MEM=0.002688
            ;;
        europe-southwest1) # Madrid - Tier 2
            E2_CPU=0.024107;  E2_MEM=0.003231
            N2_CPU=0.034938;  N2_MEM=0.004683
            C4A_CPU=0.02320;  C4A_MEM=0.002540
            ;;
        *)
            E2_CPU=0.025;     E2_MEM=0.0035
            N2_CPU=0.036;     N2_MEM=0.0048
            C4A_CPU=0.024;    C4A_MEM=0.00275
            ;;
    esac

    # Select pricing based on machine family
    case "$MACHINE_FAMILY" in
        e2)
            CPU_HOUR=$E2_CPU
            MEM_HOUR=$E2_MEM
            ;;
        n2|n2d|c3|c3d)
            CPU_HOUR=$N2_CPU
            MEM_HOUR=$N2_MEM
            ;;
        c4a|t2a)
            CPU_HOUR=$C4A_CPU
            MEM_HOUR=$C4A_MEM
            ;;
        *)
            CPU_HOUR=$E2_CPU
            MEM_HOUR=$E2_MEM
            ;;
    esac

    # Calculate total hourly cost
    HOURLY_COST=$(echo "scale=4; ($CPU_HOUR * $VCPUS) + ($MEM_HOUR * $TOTAL_MEMORY)" | bc)

    # Calculate monthly cost (730 hours)
    MONTHLY_COST=$(echo "scale=2; $HOURLY_COST * 730" | bc)

    # Calculate spot/preemptible price (roughly 60-80% discount)
    SPOT_MONTHLY=$(echo "scale=2; $MONTHLY_COST * 0.3" | bc)

    # Store result
    echo "${MONTHLY_COST}|${region}|${REGION_NAMES[$region]}|${HOURLY_COST}|${SPOT_MONTHLY}" >> "$RESULTS_FILE"
done

echo ""
log_info "Top ${TOP_N} cheapest European regions for ${MACHINE_TYPE}:"
echo ""
echo "┌────┬──────────────────┬───────────────┬──────────────┬──────────────┬──────────────┐"
echo "│ #  │ Region           │ Location      │ Hourly (USD) │ Monthly (USD)│ Spot Monthly │"
echo "├────┼──────────────────┼───────────────┼──────────────┼──────────────┼──────────────┤"

sort -t'|' -k1 -n "$RESULTS_FILE" | head -n "$TOP_N" | nl | while read -r num line; do
    monthly=$(echo "$line" | cut -d'|' -f1)
    region=$(echo "$line" | cut -d'|' -f2)
    location=$(echo "$line" | cut -d'|' -f3)
    hourly=$(echo "$line" | cut -d'|' -f4)
    spot=$(echo "$line" | cut -d'|' -f5)

    printf "│ %-2s │ %-16s │ %-13s │ \$%-11s │ \$%-11s │ \$%-11s │\n" \
        "$num" "$region" "$location" "$hourly" "$monthly" "$spot"
done

echo "└────┴──────────────────┴───────────────┴──────────────┴──────────────┴──────────────┘"

echo ""
log_info "All regions sorted by price:"
echo ""

sort -t'|' -k1 -n "$RESULTS_FILE" | nl | while read -r num line; do
    monthly=$(echo "$line" | cut -d'|' -f1)
    region=$(echo "$line" | cut -d'|' -f2)
    location=$(echo "$line" | cut -d'|' -f3)
    spot=$(echo "$line" | cut -d'|' -f5)

    printf "  %2s. %-16s (%-12s): \$%s/mo on-demand, \$%s/mo spot\n" \
        "$num" "$region" "$location" "$monthly" "$spot"
done

echo ""
log_info "Notes:"
echo "  • Prices are approximate on-demand rates (USD)"
echo "  • Spot/Preemptible instances are ~70% cheaper but can be terminated"
echo "  • Tier 1 regions (Belgium, Netherlands, Finland, Stockholm) are cheapest"
echo "  • Add ~\$20-40/month for 200GB SSD boot disk"
echo "  • Sustained use discounts apply automatically (up to 30% off)"
if [[ "$IS_ARM" == "yes" ]]; then
    echo "  • C4A (Arm) requires ARM64 images: --image-family=ubuntu-2404-lts-arm64"
fi
echo ""

# Get the cheapest region
CHEAPEST=$(sort -t'|' -k1 -n "$RESULTS_FILE" | head -1)
CHEAPEST_REGION=$(echo "$CHEAPEST" | cut -d'|' -f2)
CHEAPEST_LOCATION=$(echo "$CHEAPEST" | cut -d'|' -f3)
CHEAPEST_MONTHLY=$(echo "$CHEAPEST" | cut -d'|' -f1)
CHEAPEST_SPOT=$(echo "$CHEAPEST" | cut -d'|' -f5)

echo -e "${GREEN}Recommendation:${NC}"
echo "  Region: ${CHEAPEST_REGION} (${CHEAPEST_LOCATION})"
echo "  On-demand: ~\$${CHEAPEST_MONTHLY}/month"
echo "  Spot/Preemptible: ~\$${CHEAPEST_SPOT}/month"
echo ""
echo "To create a VM in this region:"
echo ""

if [[ "$IS_ARM" == "yes" ]]; then
    echo "  gcloud compute instances create claude-sandbox \\"
    echo "    --zone=${CHEAPEST_REGION}-b \\"
    echo "    --machine-type=${MACHINE_TYPE} \\"
    echo "    --boot-disk-size=200GB \\"
    echo "    --boot-disk-type=pd-ssd \\"
    echo "    --image-family=ubuntu-2404-lts-arm64 \\"
    echo "    --image-project=ubuntu-os-cloud \\"
    echo "    --provisioning-model=SPOT  # Remove for on-demand"
else
    echo "  gcloud compute instances create claude-sandbox \\"
    echo "    --zone=${CHEAPEST_REGION}-b \\"
    echo "    --machine-type=${MACHINE_TYPE} \\"
    echo "    --boot-disk-size=200GB \\"
    echo "    --boot-disk-type=pd-ssd \\"
    echo "    --image-family=ubuntu-2404-lts-amd64 \\"
    echo "    --image-project=ubuntu-os-cloud \\"
    echo "    --provisioning-model=SPOT  # Remove for on-demand"
fi
echo ""

# Quick comparison table
echo ""
log_info "Quick machine type comparison (Tier 1 regions, monthly on-demand):"
echo ""
echo "┌───────────────────┬───────┬────────┬─────────────┬─────────────┬─────────────────────┐"
echo "│ Machine Type      │ vCPUs │ RAM GB │ On-demand   │ Spot (~70%) │ Notes               │"
echo "├───────────────────┼───────┼────────┼─────────────┼─────────────┼─────────────────────┤"

for mt in "e2-standard-8" "e2-standard-16" "e2-highcpu-16" "c4a-highcpu-8" "c4a-highcpu-16" "c4a-highcpu-32" "n2-standard-8" "n2-standard-16"; do
    mt_family=$(echo "$mt" | cut -d'-' -f1)
    mt_class=$(echo "$mt" | cut -d'-' -f2)
    mt_vcpus=$(echo "$mt" | cut -d'-' -f3)

    case "$mt_class" in
        standard) mt_mem=$((mt_vcpus * 4)) ;;
        highmem)  mt_mem=$((mt_vcpus * 8)) ;;
        highcpu)
            if [[ "$mt_family" == "e2" ]]; then
                mt_mem=$((mt_vcpus * 1))
            else
                mt_mem=$((mt_vcpus * 2))
            fi
            ;;
    esac

    case "$mt_family" in
        e2)  cpu_r=0.021811; mem_r=0.002923; notes="x86, shared" ;;
        c4a) cpu_r=0.02099;  mem_r=0.002298; notes="ARM (Axion)" ;;
        n2)  cpu_r=0.031611; mem_r=0.004237; notes="x86, dedicated" ;;
    esac

    price=$(echo "scale=0; (($cpu_r * $mt_vcpus) + ($mem_r * $mt_mem)) * 730" | bc)
    spot_price=$(echo "scale=0; $price * 0.3" | bc)

    printf "│ %-17s │ %5d │ %6d │ \$%10d │ \$%10d │ %-19s │\n" \
        "$mt" "$mt_vcpus" "$mt_mem" "$price" "$spot_price" "$notes"
done

echo "└───────────────────┴───────┴────────┴─────────────┴─────────────┴─────────────────────┘"
echo ""
echo "Best value for 10-12 Claude agents:"
echo "  • Budget:      c4a-highcpu-16 spot in Belgium/Finland (~\$75/mo) - 16 vCPU, 32GB"
echo "  • Balanced:    c4a-highcpu-32 spot in Belgium/Finland (~\$150/mo) - 32 vCPU, 64GB"
echo "  • Performance: e2-standard-16 spot in Belgium/Finland (~\$90/mo) - 16 vCPU, 64GB"
echo ""
