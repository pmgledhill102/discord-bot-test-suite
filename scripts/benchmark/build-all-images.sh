#!/bin/bash
# Build all service Docker images for benchmarking
# Usage: ./scripts/benchmark/build-all-images.sh [--parallel]
#
# Builds all 14 service images with consistent naming: discord-{service}:benchmark

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESULTS_FILE="$SCRIPT_DIR/build-results.json"

# All services to build
SERVICES=(
    "go-gin"
    "python-flask"
    "cpp-drogon"
    "rust-actix"
    "node-express"
    "typescript-fastify"
    "python-django"
    "java-spring"
    "java-spring2"
    "java-quarkus"
    "kotlin-ktor"
    "scala-play"
    "csharp-aspnet"
    "ruby-rails"
    "php-laravel"
)

PARALLEL=false
if [[ "$1" == "--parallel" ]]; then
    PARALLEL=true
fi

# Initialize results JSON
echo '{"builds": [], "timestamp": "'$(date -Iseconds)'"}' > "$RESULTS_FILE"

build_service() {
    local service=$1
    local service_dir="$PROJECT_ROOT/services/$service"
    local image_name="discord-${service}:benchmark"

    if [[ ! -d "$service_dir" ]]; then
        echo "SKIP: $service (directory not found)"
        return 1
    fi

    echo ""
    echo "=========================================="
    echo "Building: $service"
    echo "=========================================="

    local start_time=$(date +%s.%N)

    # Build the image
    if docker build -t "$image_name" "$service_dir" > /dev/null 2>&1; then
        local end_time=$(date +%s.%N)
        local build_time=$(echo "$end_time - $start_time" | bc)

        # Get image size
        local image_size=$(docker image inspect "$image_name" --format='{{.Size}}')
        local image_size_mb=$(echo "scale=2; $image_size / 1024 / 1024" | bc)

        echo "✓ $service: ${build_time}s, ${image_size_mb}MB"

        # Append to results (using temp file for atomic update)
        local tmp_file=$(mktemp)
        jq --arg svc "$service" \
           --arg img "$image_name" \
           --argjson time "$build_time" \
           --argjson size "$image_size" \
           --argjson size_mb "$image_size_mb" \
           '.builds += [{"service": $svc, "image": $img, "build_time_seconds": $time, "size_bytes": $size, "size_mb": $size_mb, "status": "success"}]' \
           "$RESULTS_FILE" > "$tmp_file" && mv "$tmp_file" "$RESULTS_FILE"

        return 0
    else
        local end_time=$(date +%s.%N)
        local build_time=$(echo "$end_time - $start_time" | bc)

        echo "✗ $service: FAILED after ${build_time}s"

        local tmp_file=$(mktemp)
        jq --arg svc "$service" \
           --argjson time "$build_time" \
           '.builds += [{"service": $svc, "build_time_seconds": $time, "status": "failed"}]' \
           "$RESULTS_FILE" > "$tmp_file" && mv "$tmp_file" "$RESULTS_FILE"

        return 1
    fi
}

echo "Building ${#SERVICES[@]} service images..."
echo "Results will be saved to: $RESULTS_FILE"

TOTAL_START=$(date +%s.%N)

if $PARALLEL; then
    echo "Mode: PARALLEL"
    # Build all in parallel
    for service in "${SERVICES[@]}"; do
        build_service "$service" &
    done
    wait
else
    echo "Mode: SEQUENTIAL"
    # Build sequentially
    for service in "${SERVICES[@]}"; do
        build_service "$service"
    done
fi

TOTAL_END=$(date +%s.%N)
TOTAL_TIME=$(echo "$TOTAL_END - $TOTAL_START" | bc)

# Update total time in results
tmp_file=$(mktemp)
jq --argjson total "$TOTAL_TIME" '.total_build_time_seconds = $total' "$RESULTS_FILE" > "$tmp_file" && mv "$tmp_file" "$RESULTS_FILE"

echo ""
echo "=========================================="
echo "Build Complete"
echo "=========================================="
echo "Total time: ${TOTAL_TIME}s"
echo ""
echo "Image sizes:"
docker images --filter "reference=discord-*:benchmark" --format "table {{.Repository}}\t{{.Size}}" | sort

echo ""
echo "Results saved to: $RESULTS_FILE"
