#!/bin/bash
# Run performance benchmark for a single service or all services
# Usage: ./scripts/benchmark/run-benchmark.sh [service|--all] [--iterations N]
#
# Measures:
# - Container startup time (to healthy)
# - Time to first ping response
# - Memory usage at idle

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default settings
ITERATIONS=3
TARGET="--all"
RESULTS_DIR="$SCRIPT_DIR/results"
DISCORD_PUBLIC_KEY="398803f0f03317b6dc57069dbe7820e5f6cf7d5ff43ad6219710b19b0b49c159"

# All services
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
    "kotlin-ktor"
    "scala-play"
    "csharp-aspnet"
    "ruby-rails"
    "php-laravel"
)

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --iterations)
            ITERATIONS="$2"
            shift 2
            ;;
        --all)
            TARGET="--all"
            shift
            ;;
        *)
            TARGET="$1"
            shift
            ;;
    esac
done

mkdir -p "$RESULTS_DIR"

# Find a random free port
find_free_port() {
    local port=$((49152 + RANDOM % 16383))
    while lsof -i:"$port" >/dev/null 2>&1; do
        port=$((49152 + RANDOM % 16383))
    done
    echo "$port"
}

# Benchmark a single service
benchmark_service() {
    local service=$1
    local iteration=$2
    local image_name="discord-${service}:benchmark"
    local run_id=$(head -c 8 /dev/urandom | xxd -p)
    local container_name="bench-${service}-${run_id}"
    local port=$(find_free_port)

    # Check image exists
    if ! docker image inspect "$image_name" >/dev/null 2>&1; then
        echo "ERROR: Image $image_name not found. Run build-all-images.sh first."
        return 1
    fi

    local result_file="$RESULTS_DIR/${service}-${iteration}.json"

    # Cleanup function
    cleanup() {
        docker stop "$container_name" >/dev/null 2>&1 || true
        docker rm "$container_name" >/dev/null 2>&1 || true
    }
    trap cleanup EXIT

    echo -n "  Iteration $iteration: "

    # Record start time
    local start_time=$(python3 -c 'import time; print(time.time())')

    # Start container
    docker run -d \
        --name "$container_name" \
        -p "$port:8080" \
        -e "PORT=8080" \
        -e "DISCORD_PUBLIC_KEY=$DISCORD_PUBLIC_KEY" \
        "$image_name" >/dev/null 2>&1

    # Wait for health endpoint (max 60 seconds)
    local healthy_time=""
    local health_ok=false
    for i in {1..600}; do
        if curl -s "http://localhost:$port/health" >/dev/null 2>&1; then
            healthy_time=$(python3 -c 'import time; print(time.time())')
            health_ok=true
            break
        fi
        sleep 0.1
    done

    if ! $health_ok; then
        echo "TIMEOUT (health check failed)"
        cleanup
        echo '{"status": "timeout", "service": "'$service'", "iteration": '$iteration'}' > "$result_file"
        return 1
    fi

    local startup_time=$(python3 -c "print(${healthy_time} - ${start_time})")

    # Measure ping response time (average of 5 requests)
    local ping_times=()
    for i in {1..5}; do
        local ping_start=$(python3 -c 'import time; print(time.time())')
        curl -s "http://localhost:$port/health" >/dev/null 2>&1
        local ping_end=$(python3 -c 'import time; print(time.time())')
        local ping_time=$(python3 -c "print(${ping_end} - ${ping_start})")
        ping_times+=("$ping_time")
    done

    # Calculate average ping time
    local ping_sum=0
    for pt in "${ping_times[@]}"; do
        ping_sum=$(python3 -c "print(${ping_sum} + ${pt})")
    done
    local avg_ping=$(python3 -c "print(${ping_sum} / 5)")

    # Get memory usage
    local memory_bytes=$(docker stats "$container_name" --no-stream --format "{{.MemUsage}}" | awk '{print $1}')
    # Convert to bytes (handles MiB, GiB, KiB)
    local memory_mb=$(python3 -c "
mem = '$memory_bytes'
if 'GiB' in mem:
    print(float(mem.replace('GiB', '')) * 1024)
elif 'MiB' in mem:
    print(float(mem.replace('MiB', '')))
elif 'KiB' in mem:
    print(float(mem.replace('KiB', '')) / 1024)
else:
    print(0)
")

    # Get image size
    local image_size_mb=$(docker image inspect "$image_name" --format='{{.Size}}' | awk '{printf "%.2f", $1/1024/1024}')

    echo "startup=${startup_time}s, ping=${avg_ping}s, mem=${memory_mb}MB"

    # Save result
    cat > "$result_file" << EOF
{
    "service": "$service",
    "iteration": $iteration,
    "status": "success",
    "startup_time_seconds": $startup_time,
    "avg_ping_time_seconds": $avg_ping,
    "memory_usage_mb": $memory_mb,
    "image_size_mb": $image_size_mb,
    "timestamp": "$(date -Iseconds)"
}
EOF

    cleanup
    trap - EXIT
}

# Run benchmarks
run_benchmarks() {
    local services_to_test=()

    if [[ "$TARGET" == "--all" ]]; then
        services_to_test=("${SERVICES[@]}")
    else
        services_to_test=("$TARGET")
    fi

    echo "=========================================="
    echo "Performance Benchmark"
    echo "=========================================="
    echo "Services: ${#services_to_test[@]}"
    echo "Iterations: $ITERATIONS"
    echo "Results: $RESULTS_DIR"
    echo ""

    for service in "${services_to_test[@]}"; do
        echo ""
        echo "Testing: $service"
        echo "----------------------------------------"

        for ((i=1; i<=ITERATIONS; i++)); do
            benchmark_service "$service" "$i" || true
            # Small delay between iterations
            sleep 1
        done
    done

    echo ""
    echo "=========================================="
    echo "Benchmark Complete"
    echo "=========================================="
    echo "Results saved to: $RESULTS_DIR/"
}

run_benchmarks
