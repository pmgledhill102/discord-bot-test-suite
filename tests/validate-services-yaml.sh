#!/bin/bash
# Validate services YAML file against filesystem
#
# Usage:
#   ./tests/validate-services-yaml.sh [services-file]
#
# This script verifies:
#   1. The YAML file is valid and has the expected schema
#   2. Every service in the YAML has a corresponding directory
#   3. Every service directory has a corresponding entry in the YAML
#   4. Each service has the expected dependency file
#   5. Each service has a Dockerfile
#
# Exit codes:
#   0 - All validations passed
#   1 - Validation failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source the services library
source "$PROJECT_ROOT/scripts/lib/services.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
ERRORS=0
WARNINGS=0

log_pass() {
    echo -e "${GREEN}PASS${NC}: $1"
}

log_fail() {
    echo -e "${RED}FAIL${NC}: $1"
    ((ERRORS++)) || true
}

log_warn() {
    echo -e "${YELLOW}WARN${NC}: $1"
    ((WARNINGS++)) || true
}

log_info() {
    echo -e "INFO: $1"
}

# Allow specifying a different services file
if [[ $# -gt 0 ]]; then
    SERVICES_FILE="$1"
    # Make path absolute if relative
    if [[ ! "$SERVICES_FILE" = /* ]]; then
        SERVICES_FILE="$PWD/$SERVICES_FILE"
    fi
fi

SERVICES_DIR="$PROJECT_ROOT/services"

echo "=========================================="
echo "Services YAML Validation"
echo "=========================================="
echo "Services file: $SERVICES_FILE"
echo "Services dir:  $SERVICES_DIR"
echo ""

# Check 1: YAML file exists and is valid
echo "--- Checking YAML file validity ---"
if validate_services_file "$SERVICES_FILE"; then
    log_pass "YAML file is valid"
else
    log_fail "YAML file validation failed"
    exit 1
fi

# Get all services from YAML (bash 3.2 compatible)
YAML_SERVICES=()
while IFS= read -r service; do
    YAML_SERVICES+=("$service")
done < <(get_all_services)
log_info "Found ${#YAML_SERVICES[@]} services in YAML"
echo ""

# Check 2: Every service in YAML has a directory
echo "--- Checking YAML services have directories ---"
for service in "${YAML_SERVICES[@]}"; do
    service_dir="$SERVICES_DIR/$service"
    if [[ -d "$service_dir" ]]; then
        log_pass "$service has directory"
    else
        log_fail "$service missing directory: $service_dir"
    fi
done
echo ""

# Check 3: Every directory has a YAML entry
echo "--- Checking directories have YAML entries ---"
for dir in "$SERVICES_DIR"/*/; do
    if [[ -d "$dir" ]]; then
        service_name=$(basename "$dir")
        # Skip non-service directories (like README.md parent)
        if [[ -f "$dir/Dockerfile" ]] || [[ -f "$dir/pom.xml" ]] || [[ -f "$dir/package.json" ]] || [[ -f "$dir/go.mod" ]]; then
            if service_exists "$service_name"; then
                log_pass "$service_name has YAML entry"
            else
                log_fail "$service_name missing from YAML"
            fi
        fi
    fi
done
echo ""

# Check 4: Each service has the expected dependency file
echo "--- Checking dependency files ---"
for service in "${YAML_SERVICES[@]}"; do
    service_dir="$SERVICES_DIR/$service"
    if [[ ! -d "$service_dir" ]]; then
        continue
    fi

    dep_file=$(get_service_attr "$service" "build.dependency_file" 2>/dev/null || echo "")
    if [[ -n "$dep_file" && "$dep_file" != "null" ]]; then
        if [[ -f "$service_dir/$dep_file" ]]; then
            log_pass "$service has $dep_file"
        else
            log_fail "$service missing dependency file: $dep_file"
        fi
    else
        log_warn "$service has no dependency_file specified"
    fi
done
echo ""

# Check 5: Each service has a Dockerfile
echo "--- Checking Dockerfiles ---"
for service in "${YAML_SERVICES[@]}"; do
    service_dir="$SERVICES_DIR/$service"
    if [[ ! -d "$service_dir" ]]; then
        continue
    fi

    if [[ -f "$service_dir/Dockerfile" ]]; then
        log_pass "$service has Dockerfile"
    else
        log_fail "$service missing Dockerfile"
    fi
done
echo ""

# Summary
echo "=========================================="
echo "Validation Summary"
echo "=========================================="
echo "Total services: ${#YAML_SERVICES[@]}"
echo -e "Errors:   ${RED}$ERRORS${NC}"
echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"

if [[ $ERRORS -gt 0 ]]; then
    echo ""
    echo -e "${RED}Validation FAILED${NC}"
    exit 1
else
    echo ""
    echo -e "${GREEN}Validation PASSED${NC}"
    exit 0
fi
