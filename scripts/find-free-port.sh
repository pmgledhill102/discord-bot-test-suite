#!/bin/bash
# Find a free port in the specified range
# Usage: find-free-port.sh [start_port] [end_port]
# Returns: a free port number

START_PORT=${1:-10000}
END_PORT=${2:-65000}

for port in $(seq $START_PORT $END_PORT); do
    if ! lsof -i:$port >/dev/null 2>&1; then
        echo $port
        exit 0
    fi
done

echo "No free port found in range $START_PORT-$END_PORT" >&2
exit 1
