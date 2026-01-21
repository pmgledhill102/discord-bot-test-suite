#!/bin/bash
# Run full performance benchmark with Pub/Sub integration testing
# Usage: ./scripts/benchmark/run-benchmark-full.sh [service|--all] [--iterations N]
#
# This benchmark:
# 1. Starts a shared Pub/Sub emulator
# 2. For each service:
#    a. Cold-start ping test: start container, wait healthy, ping, memory, KILL
#    b. Cold-start interaction test: start container, wait healthy, send slash command,
#       verify Pub/Sub message received, KILL
# 3. Cleans up Pub/Sub emulator

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default settings
ITERATIONS=1
TARGET="--all"
RESULTS_DIR="$SCRIPT_DIR/results"
DISCORD_PUBLIC_KEY="398803f0f03317b6dc57069dbe7820e5f6cf7d5ff43ad6219710b19b0b49c159"

# Pub/Sub settings
PUBSUB_PROJECT="benchmark-project"
PUBSUB_TOPIC="discord-interactions"
PUBSUB_SUBSCRIPTION="benchmark-sub"
PUBSUB_CONTAINER_NAME="benchmark-pubsub-emulator"
PUBSUB_PORT=""

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

# Start shared Pub/Sub emulator
start_pubsub_emulator() {
    echo "Starting shared Pub/Sub emulator..."
    PUBSUB_PORT=$(find_free_port)

    docker run -d \
        --name "$PUBSUB_CONTAINER_NAME" \
        -p "$PUBSUB_PORT:8085" \
        gcr.io/google.com/cloudsdktool/google-cloud-cli:emulators \
        gcloud beta emulators pubsub start \
        --host-port=0.0.0.0:8085 \
        --project="$PUBSUB_PROJECT" >/dev/null 2>&1

    # Wait for emulator to be ready
    echo -n "  Waiting for Pub/Sub emulator..."
    for i in {1..60}; do
        if curl -s "http://localhost:$PUBSUB_PORT" >/dev/null 2>&1; then
            echo " ready (port $PUBSUB_PORT)"
            break
        fi
        sleep 0.5
    done

    # Set up topic and subscription
    export PUBSUB_EMULATOR_HOST="localhost:$PUBSUB_PORT"
    python3 "$SCRIPT_DIR/benchmark_helper.py" setup-pubsub \
        --project "$PUBSUB_PROJECT" \
        --topic "$PUBSUB_TOPIC" \
        --subscription "$PUBSUB_SUBSCRIPTION" || true

    echo "  Topic and subscription created"
}

# Stop Pub/Sub emulator
stop_pubsub_emulator() {
    echo "Stopping Pub/Sub emulator..."
    docker stop "$PUBSUB_CONTAINER_NAME" >/dev/null 2>&1 || true
    docker rm "$PUBSUB_CONTAINER_NAME" >/dev/null 2>&1 || true
}

# Clear Pub/Sub subscription
clear_pubsub() {
    export PUBSUB_EMULATOR_HOST="localhost:$PUBSUB_PORT"
    python3 "$SCRIPT_DIR/benchmark_helper.py" clear-subscription \
        --project "$PUBSUB_PROJECT" \
        --subscription "$PUBSUB_SUBSCRIPTION" >/dev/null 2>&1 || true
}

# Pull message from Pub/Sub
pull_pubsub_message() {
    local timeout=${1:-5}
    export PUBSUB_EMULATOR_HOST="localhost:$PUBSUB_PORT"
    python3 "$SCRIPT_DIR/benchmark_helper.py" pull-message \
        --project "$PUBSUB_PROJECT" \
        --subscription "$PUBSUB_SUBSCRIPTION" \
        --timeout "$timeout" 2>/dev/null
}

# Run cold-start ping benchmark
benchmark_ping() {
    local service=$1
    local iteration=$2
    local image_name="discord-${service}:benchmark"
    local run_id=$(head -c 8 /dev/urandom | xxd -p)
    local container_name="bench-ping-${service}-${run_id}"
    local port=$(find_free_port)

    # Check image exists
    if ! docker image inspect "$image_name" >/dev/null 2>&1; then
        echo "    ERROR: Image $image_name not found"
        return 1
    fi

    # Record start time
    local start_time=$(python3 -c 'import time; print(time.time())')

    # Start container (NO Pub/Sub for ping test)
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
        echo "    TIMEOUT (health check failed)"
        docker stop "$container_name" >/dev/null 2>&1 || true
        docker rm "$container_name" >/dev/null 2>&1 || true
        echo "timeout"
        return 1
    fi

    local startup_time=$(python3 -c "print(${healthy_time} - ${start_time})")

    # Measure ping response time (average of 5 requests)
    local ping_sum=0
    for i in {1..5}; do
        local ping_start=$(python3 -c 'import time; print(time.time())')
        curl -s "http://localhost:$port/health" >/dev/null 2>&1
        local ping_end=$(python3 -c 'import time; print(time.time())')
        local ping_time=$(python3 -c "print(${ping_end} - ${ping_start})")
        ping_sum=$(python3 -c "print(${ping_sum} + ${ping_time})")
    done
    local avg_ping=$(python3 -c "print(${ping_sum} / 5)")

    # Get memory usage
    local memory_bytes=$(docker stats "$container_name" --no-stream --format "{{.MemUsage}}" | awk '{print $1}')
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

    # KILL container (not just stop - force immediate termination)
    docker kill "$container_name" >/dev/null 2>&1 || true
    docker rm "$container_name" >/dev/null 2>&1 || true

    echo "${startup_time},${avg_ping},${memory_mb}"
}

# Run cold-start interaction benchmark with Pub/Sub
benchmark_interaction() {
    local service=$1
    local iteration=$2
    local image_name="discord-${service}:benchmark"
    local run_id=$(head -c 8 /dev/urandom | xxd -p)
    local container_name="bench-interact-${service}-${run_id}"
    local port=$(find_free_port)

    # Check image exists
    if ! docker image inspect "$image_name" >/dev/null 2>&1; then
        echo "    ERROR: Image $image_name not found"
        return 1
    fi

    # Clear any pending Pub/Sub messages
    clear_pubsub

    # Record start time
    local start_time=$(python3 -c 'import time; print(time.time())')

    # Start container WITH Pub/Sub configuration
    docker run -d \
        --name "$container_name" \
        -p "$port:8080" \
        -e "PORT=8080" \
        -e "DISCORD_PUBLIC_KEY=$DISCORD_PUBLIC_KEY" \
        -e "PUBSUB_EMULATOR_HOST=host.docker.internal:$PUBSUB_PORT" \
        -e "GOOGLE_CLOUD_PROJECT=$PUBSUB_PROJECT" \
        -e "PUBSUB_TOPIC=$PUBSUB_TOPIC" \
        --add-host=host.docker.internal:host-gateway \
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
        echo "    TIMEOUT (health check failed)"
        docker kill "$container_name" >/dev/null 2>&1 || true
        docker rm "$container_name" >/dev/null 2>&1 || true
        echo "timeout"
        return 1
    fi

    local startup_time=$(python3 -c "print(${healthy_time} - ${start_time})")

    # Create signed slash command request
    local request_data=$(python3 "$SCRIPT_DIR/benchmark_helper.py" create-slash --name "benchmark-test")
    local body=$(echo "$request_data" | python3 -c "import sys,json; print(json.load(sys.stdin)['body'])")
    local signature=$(echo "$request_data" | python3 -c "import sys,json; print(json.load(sys.stdin)['signature'])")
    local timestamp=$(echo "$request_data" | python3 -c "import sys,json; print(json.load(sys.stdin)['timestamp'])")

    # Send interaction request and measure time
    local request_start=$(python3 -c 'import time; print(time.time())')

    local response=$(curl -s -w "\n%{http_code}" \
        -X POST "http://localhost:$port/" \
        -H "Content-Type: application/json" \
        -H "X-Signature-Ed25519: $signature" \
        -H "X-Signature-Timestamp: $timestamp" \
        -d "$body")

    local response_time=$(python3 -c 'import time; print(time.time())')
    local http_code=$(echo "$response" | tail -n1)
    local response_body=$(echo "$response" | sed '$d')

    local interaction_latency=$(python3 -c "print(${response_time} - ${request_start})")

    # Check response
    if [[ "$http_code" != "200" ]]; then
        echo "    ERROR: HTTP $http_code"
        docker kill "$container_name" >/dev/null 2>&1 || true
        docker rm "$container_name" >/dev/null 2>&1 || true
        echo "error,$http_code"
        return 1
    fi

    # Wait for Pub/Sub message (with timeout)
    local pubsub_received="false"
    local pubsub_latency="0"

    # Give service time to publish
    sleep 0.5

    local pubsub_start=$(python3 -c 'import time; print(time.time())')
    local message=$(pull_pubsub_message 5)
    local pubsub_end=$(python3 -c 'import time; print(time.time())')

    if [[ -n "$message" ]]; then
        pubsub_received="true"
        # Total latency from request to message received
        pubsub_latency=$(python3 -c "print(${pubsub_end} - ${request_start})")
    fi

    # Get memory usage
    local memory_bytes=$(docker stats "$container_name" --no-stream --format "{{.MemUsage}}" | awk '{print $1}')
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

    # KILL container
    docker kill "$container_name" >/dev/null 2>&1 || true
    docker rm "$container_name" >/dev/null 2>&1 || true

    echo "${startup_time},${interaction_latency},${pubsub_received},${pubsub_latency},${memory_mb}"
}

# Benchmark a single service
benchmark_service() {
    local service=$1
    local iteration=$2
    local image_name="discord-${service}:benchmark"

    # Check image exists
    if ! docker image inspect "$image_name" >/dev/null 2>&1; then
        echo "ERROR: Image $image_name not found. Run build-all-images.sh first."
        return 1
    fi

    local result_file="$RESULTS_DIR/${service}-${iteration}.json"
    local image_size_mb=$(docker image inspect "$image_name" --format='{{.Size}}' | awk '{printf "%.2f", $1/1024/1024}')

    echo "  Iteration $iteration:"

    # Run ping benchmark
    echo -n "    Ping test: "
    local ping_result=$(benchmark_ping "$service" "$iteration")
    if [[ "$ping_result" == "timeout" ]]; then
        echo "TIMEOUT"
        echo '{"status": "timeout", "service": "'$service'", "iteration": '$iteration', "test": "ping"}' > "$result_file"
        return 1
    fi

    local ping_startup=$(echo "$ping_result" | cut -d',' -f1)
    local ping_latency=$(echo "$ping_result" | cut -d',' -f2)
    local ping_memory=$(echo "$ping_result" | cut -d',' -f3)
    echo "startup=${ping_startup}s, ping=${ping_latency}s, mem=${ping_memory}MB"

    # Run interaction benchmark
    echo -n "    Interaction test: "
    local interact_result=$(benchmark_interaction "$service" "$iteration")
    if [[ "$interact_result" == "timeout" || "$interact_result" == error* ]]; then
        echo "FAILED ($interact_result)"
        echo '{"status": "error", "service": "'$service'", "iteration": '$iteration', "test": "interaction", "error": "'$interact_result'"}' > "$result_file"
        return 1
    fi

    local interact_startup=$(echo "$interact_result" | cut -d',' -f1)
    local interact_latency=$(echo "$interact_result" | cut -d',' -f2)
    local pubsub_received=$(echo "$interact_result" | cut -d',' -f3)
    local pubsub_latency=$(echo "$interact_result" | cut -d',' -f4)
    local interact_memory=$(echo "$interact_result" | cut -d',' -f5)
    echo "startup=${interact_startup}s, latency=${interact_latency}s, pubsub=${pubsub_received}, mem=${interact_memory}MB"

    # Save combined result
    cat > "$result_file" << EOF
{
    "service": "$service",
    "iteration": $iteration,
    "status": "success",
    "image_size_mb": $image_size_mb,
    "ping_test": {
        "startup_time_seconds": $ping_startup,
        "avg_ping_time_seconds": $ping_latency,
        "memory_usage_mb": $ping_memory
    },
    "interaction_test": {
        "startup_time_seconds": $interact_startup,
        "interaction_latency_seconds": $interact_latency,
        "pubsub_received": $pubsub_received,
        "pubsub_latency_seconds": $pubsub_latency,
        "memory_usage_mb": $interact_memory
    },
    "timestamp": "$(date -Iseconds)"
}
EOF
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
    echo "Full Performance Benchmark (with Pub/Sub)"
    echo "=========================================="
    echo "Services: ${#services_to_test[@]}"
    echo "Iterations: $ITERATIONS"
    echo "Results: $RESULTS_DIR"
    echo ""

    # Start shared Pub/Sub emulator
    start_pubsub_emulator

    echo ""
    echo "Running benchmarks..."
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

    # Stop Pub/Sub emulator
    stop_pubsub_emulator
}

# Cleanup on exit
cleanup() {
    stop_pubsub_emulator
}
trap cleanup EXIT

run_benchmarks
