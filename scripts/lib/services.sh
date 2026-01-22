#!/bin/bash
# Shared library for reading service definitions from YAML files
#
# Usage:
#   source "$(dirname "$0")/../lib/services.sh"
#   SERVICES=($(get_all_services))
#
# Environment variables:
#   SERVICES_FILE - Path to services YAML file (default: services/services-discord-bot.yaml)
#   PROJECT_ROOT  - Project root directory (auto-detected if not set)
#
# Dependencies:
#   - yq (https://github.com/mikefarah/yq) v4+
#   - OR python3 with PyYAML (fallback)

set -euo pipefail

# Auto-detect project root if not set
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    # Find project root by looking for services directory
    _SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$_SCRIPT_DIR/../.." && pwd)"
fi

# Default services file path
SERVICES_FILE="${SERVICES_FILE:-$PROJECT_ROOT/services/services-discord-bot.yaml}"

# Check if yq is available
_has_yq() {
    command -v yq &>/dev/null
}

# Check if python3 with yaml is available
_has_python_yaml() {
    python3 -c "import yaml" &>/dev/null 2>&1
}

# Validate that we have a YAML parser available
_check_yaml_parser() {
    if ! _has_yq && ! _has_python_yaml; then
        echo "ERROR: No YAML parser found." >&2
        echo "Please install one of:" >&2
        echo "  - yq: brew install yq (recommended)" >&2
        echo "  - PyYAML: pip install pyyaml" >&2
        return 1
    fi
}

# Parse YAML using available tool
# Arguments: $1 = expression (yq syntax), $2 = file (optional, defaults to SERVICES_FILE)
_yaml_query() {
    local expr="$1"
    local file="${2:-$SERVICES_FILE}"

    if [[ ! -f "$file" ]]; then
        echo "ERROR: Services file not found: $file" >&2
        return 1
    fi

    if _has_yq; then
        yq -r "$expr" "$file"
    elif _has_python_yaml; then
        python3 -c "
import yaml
import sys

with open('$file') as f:
    data = yaml.safe_load(f)

# Simple expression parser for common queries
expr = '''$expr'''
if expr == '.services | keys | .[]':
    for key in sorted(data.get('services', {}).keys()):
        print(key)
elif expr.startswith('.services.') and expr.endswith(' | keys | .[]'):
    service = expr.split('.')[2].split()[0]
    if service in data.get('services', {}):
        for key in data['services'][service].keys():
            print(key)
elif expr.startswith('.services.'):
    parts = expr.split('.')
    result = data
    for part in parts[1:]:
        if part and result:
            result = result.get(part)
    if result is not None:
        print(result)
"
    else
        echo "ERROR: No YAML parser available" >&2
        return 1
    fi
}

# Get list of all service names
# Output: One service name per line
get_all_services() {
    _check_yaml_parser || return 1
    _yaml_query '.services | keys | .[]'
}

# Get service count
# Output: Number of services
get_service_count() {
    _check_yaml_parser || return 1
    get_all_services | wc -l | tr -d ' '
}

# Get a specific service attribute
# Arguments: $1 = service name, $2 = attribute path (e.g., "language", "build.tool")
# Output: Attribute value
get_service_attr() {
    local service="$1"
    local attr="$2"
    _check_yaml_parser || return 1
    _yaml_query ".services.${service}.${attr}"
}

# Check if a service exists
# Arguments: $1 = service name
# Returns: 0 if exists, 1 otherwise
service_exists() {
    local service="$1"
    _check_yaml_parser || return 1
    local result
    result=$(_yaml_query ".services.${service}" 2>/dev/null)
    [[ -n "$result" && "$result" != "null" ]]
}

# Get all services as a bash array (for sourcing scripts)
# Output: Space-separated list suitable for array assignment
get_services_array() {
    _check_yaml_parser || return 1
    get_all_services | tr '\n' ' '
}

# Validate services file exists and is readable
# shellcheck disable=SC2120
validate_services_file() {
    local file="${1:-$SERVICES_FILE}"

    if [[ ! -f "$file" ]]; then
        echo "ERROR: Services file not found: $file" >&2
        return 1
    fi

    if [[ ! -r "$file" ]]; then
        echo "ERROR: Services file not readable: $file" >&2
        return 1
    fi

    _check_yaml_parser || return 1

    # Verify it's valid YAML with expected structure
    local schema_version
    schema_version=$(_yaml_query '.schema_version' "$file" 2>/dev/null)
    if [[ -z "$schema_version" || "$schema_version" == "null" ]]; then
        echo "ERROR: Invalid services file - missing schema_version" >&2
        return 1
    fi

    return 0
}

# Print library info (for debugging)
services_lib_info() {
    echo "Services Library Info:"
    echo "  PROJECT_ROOT: $PROJECT_ROOT"
    echo "  SERVICES_FILE: $SERVICES_FILE"
    echo "  Has yq: $(_has_yq && echo "yes" || echo "no")"
    echo "  Has python yaml: $(_has_python_yaml && echo "yes" || echo "no")"
    # shellcheck disable=SC2119
    if validate_services_file 2>/dev/null; then
        echo "  Service count: $(get_service_count)"
    else
        echo "  Service count: (file not valid)"
    fi
}
