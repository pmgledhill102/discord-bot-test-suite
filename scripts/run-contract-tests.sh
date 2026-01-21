#!/bin/bash
# Run contract tests for a service with dynamic port allocation
# Usage: run-contract-tests.sh <service-dir>
# Example: run-contract-tests.sh rust-actix
#
# Supports parallel execution - each run gets unique ports and container names.

set -e

SERVICE_DIR=${1:?Usage: run-contract-tests.sh <service-dir>}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Validate service directory exists
if [[ ! -d "$PROJECT_ROOT/services/$SERVICE_DIR" ]]; then
    echo "Error: Service directory 'services/$SERVICE_DIR' does not exist"
    exit 1
fi

# Generate a unique run ID (UUID-like) to avoid collisions
RUN_ID=$(head -c 16 /dev/urandom | xxd -p | head -c 8)

# Find a random free port in the ephemeral range (49152-65535)
# Uses random selection to avoid race conditions with parallel runs
find_random_free_port() {
    local max_attempts=50
    local attempt=0

    while [[ $attempt -lt $max_attempts ]]; do
        # Generate random port in ephemeral range (49152-65535)
        local port=$((49152 + RANDOM % 16383))

        # Check if port is free (not in use)
        if ! lsof -i:"$port" >/dev/null 2>&1; then
            echo "$port"
            return 0
        fi

        ((attempt++))
    done

    echo "No free port found after $max_attempts attempts" >&2
    return 1
}

# Allocate ports with retry logic
allocate_ports() {
    local max_retries=3
    local retry=0

    while [[ $retry -lt $max_retries ]]; do
        SERVICE_PORT=$(find_random_free_port)
        PUBSUB_PORT=$(find_random_free_port)

        # Ensure ports are different
        if [[ "$SERVICE_PORT" != "$PUBSUB_PORT" ]]; then
            return 0
        fi

        ((retry++))
    done

    echo "Failed to allocate unique ports" >&2
    return 1
}

allocate_ports

echo "=== Port Allocation ==="
echo "Run ID: $RUN_ID"
echo "Service port: $SERVICE_PORT"
echo "Pub/Sub port: $PUBSUB_PORT"
echo ""

# Generate unique container names using run ID (more unique than timestamp)
SERVICE_CONTAINER="test-${SERVICE_DIR}-${RUN_ID}"
PUBSUB_CONTAINER="pubsub-${SERVICE_DIR}-${RUN_ID}"
NETWORK_NAME="test-network-${SERVICE_DIR}-${RUN_ID}"

# Cleanup function
cleanup() {
    echo ""
    echo "=== Cleanup ==="
    docker stop "$SERVICE_CONTAINER" 2>/dev/null || true
    docker rm "$SERVICE_CONTAINER" 2>/dev/null || true
    docker stop "$PUBSUB_CONTAINER" 2>/dev/null || true
    docker rm "$PUBSUB_CONTAINER" 2>/dev/null || true
    docker network rm "$NETWORK_NAME" 2>/dev/null || true
    echo "Cleanup complete"
}

# Set up trap for cleanup
trap cleanup EXIT

# Configuration
DISCORD_PUBLIC_KEY="398803f0f03317b6dc57069dbe7820e5f6cf7d5ff43ad6219710b19b0b49c159"
GOOGLE_CLOUD_PROJECT="test-project"
PUBSUB_TOPIC="discord-interactions"

echo "=== Creating Docker Network ==="
docker network create "$NETWORK_NAME"

echo ""
echo "=== Starting Pub/Sub Emulator ==="

# Start container with retry logic for port conflicts
start_pubsub_with_retry() {
    local max_retries=3
    local retry=0

    while [[ $retry -lt $max_retries ]]; do
        if docker run -d \
            --name "$PUBSUB_CONTAINER" \
            --network "$NETWORK_NAME" \
            -p "$PUBSUB_PORT:8085" \
            -e "PUBSUB_PROJECT1=test-project,discord-interactions" \
            gcr.io/google.com/cloudsdktool/google-cloud-cli:emulators \
            gcloud beta emulators pubsub start --host-port=0.0.0.0:8085 2>/dev/null; then
            return 0
        fi

        echo "Port $PUBSUB_PORT may be in use, retrying with new port..."
        docker rm "$PUBSUB_CONTAINER" 2>/dev/null || true
        PUBSUB_PORT=$(find_random_free_port)
        ((retry++))
    done

    echo "Failed to start Pub/Sub emulator after $max_retries attempts" >&2
    return 1
}

start_pubsub_with_retry

# Wait for Pub/Sub emulator
echo "Waiting for Pub/Sub emulator..."
for i in {1..30}; do
    if curl -s "http://localhost:$PUBSUB_PORT" >/dev/null 2>&1; then
        echo "Pub/Sub emulator ready"
        break
    fi
    if [[ $i -eq 30 ]]; then
        echo "Pub/Sub emulator failed to start"
        docker logs "$PUBSUB_CONTAINER"
        exit 1
    fi
    sleep 1
done

echo ""
echo "=== Building Service Image ==="
docker build -t "service-$SERVICE_DIR:test" "$PROJECT_ROOT/services/$SERVICE_DIR"

echo ""
echo "=== Starting Service ==="

# Start service container with retry logic for port conflicts
start_service_with_retry() {
    local max_retries=3
    local retry=0

    while [[ $retry -lt $max_retries ]]; do
        if docker run -d \
            --name "$SERVICE_CONTAINER" \
            --network "$NETWORK_NAME" \
            -p "$SERVICE_PORT:8080" \
            -e "PORT=8080" \
            -e "DISCORD_PUBLIC_KEY=$DISCORD_PUBLIC_KEY" \
            -e "PUBSUB_EMULATOR_HOST=$PUBSUB_CONTAINER:8085" \
            -e "GOOGLE_CLOUD_PROJECT=$GOOGLE_CLOUD_PROJECT" \
            -e "PUBSUB_TOPIC=$PUBSUB_TOPIC" \
            "service-$SERVICE_DIR:test" 2>/dev/null; then
            return 0
        fi

        echo "Port $SERVICE_PORT may be in use, retrying with new port..."
        docker rm "$SERVICE_CONTAINER" 2>/dev/null || true
        SERVICE_PORT=$(find_random_free_port)
        ((retry++))
    done

    echo "Failed to start service after $max_retries attempts" >&2
    return 1
}

start_service_with_retry

# Wait for service
echo "Waiting for service..."
for i in {1..30}; do
    if curl -s "http://localhost:$SERVICE_PORT/health" >/dev/null 2>&1; then
        echo "Service ready"
        break
    fi
    if [[ $i -eq 30 ]]; then
        echo "Service failed to start"
        docker logs "$SERVICE_CONTAINER"
        exit 1
    fi
    sleep 1
done

echo ""
echo "=== Running Contract Tests ==="
cd "$PROJECT_ROOT/tests/contract"
CONTRACT_TEST_TARGET="http://localhost:$SERVICE_PORT" \
PUBSUB_EMULATOR_HOST="localhost:$PUBSUB_PORT" \
GOOGLE_CLOUD_PROJECT="$GOOGLE_CLOUD_PROJECT" \
go test -v -race ./...

echo ""
echo "=== All Tests Passed ==="
