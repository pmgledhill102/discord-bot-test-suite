#!/bin/bash
# Find a free port using random selection in ephemeral range
# Usage: find-free-port.sh [max_attempts]
# Returns: a free port number
#
# Uses random port selection to avoid race conditions when
# multiple processes are searching for ports simultaneously.

MAX_ATTEMPTS=${1:-50}

for ((i=0; i<MAX_ATTEMPTS; i++)); do
    # Generate random port in ephemeral range (49152-65535)
    port=$((49152 + RANDOM % 16383))

    if ! lsof -i:"$port" >/dev/null 2>&1; then
        echo "$port"
        exit 0
    fi
done

echo "No free port found after $MAX_ATTEMPTS attempts" >&2
exit 1
