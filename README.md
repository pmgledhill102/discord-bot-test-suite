# Cloud Run Cold Start Benchmark Suite

A comprehensive test suite for benchmarking Cloud Run cold-start latency across
17 language/framework implementations using a Discord interactions webhook as the workload.

**This is NOT a production Discord bot**—it's a test harness for measuring webhook
handling performance and cold start characteristics across different runtimes.

## Purpose

Cloud Run services scale to zero when idle, meaning the first request after a period of
inactivity must start a new container instance. This "cold start" latency varies significantly
based on the language runtime, framework, container size, and other factors.

This benchmark suite:

- Measures cold start latency for Discord webhook handlers across 17 implementations
- Compares warm request performance after containers are running
- Provides reproducible, automated benchmarking on Cloud Run
- Validates service correctness via black-box contract tests

## Architecture

### Request Flow

```text
Discord Webhook Request
        │
        ▼
┌─────────────────────────┐
│  Cloud Run Service      │
│                         │
│  1. Validate Ed25519    │
│     signature           │
│                         │
│  2. Route by type:      │
│     - Ping (type=1)     │──────▶ Return Pong (type=1)
│     - Slash cmd (type=2)│
│                         │
│  3. For slash commands: │
│     - Respond deferred  │──────▶ Return type=5
│     - Publish to Pub/Sub│──────▶ Sanitized payload
└─────────────────────────┘
```

### Testing Approach

Black-box contract tests written in Go validate service behavior by making HTTP requests
to containerized services. Tests run against container images, not internal code, ensuring
all implementations behave identically regardless of language.

## Service Implementations

| Service               | Language   | Framework        | Status      |
| --------------------- | ---------- | ---------------- | ----------- |
| `go-gin`              | Go         | Gin              | ✅ Complete |
| `rust-actix`          | Rust       | Actix-web        | ✅ Complete |
| `cpp-drogon`          | C++        | Drogon           | ✅ Complete |
| `java-spring3`        | Java       | Spring Boot (v3) | ✅ Complete |
| `java-spring2`        | Java       | Spring Boot (v2) | ✅ Complete |
| `java-quarkus`        | Java       | Quarkus          | ✅ Complete |
| `java-quarkus-native` | Java       | Quarkus (Native) | ✅ Complete |
| `java-micronaut`      | Java       | Micronaut        | ✅ Complete |
| `kotlin-ktor`         | Kotlin     | Ktor             | ✅ Complete |
| `node-express`        | Node.js    | Express          | ✅ Complete |
| `typescript-fastify`  | TypeScript | Fastify          | ✅ Complete |
| `python-django`       | Python     | Django           | ✅ Complete |
| `python-flask`        | Python     | Flask            | ✅ Complete |
| `php-laravel`         | PHP        | Laravel          | ✅ Complete |
| `ruby-rails`          | Ruby       | Rails            | ✅ Complete |
| `csharp-aspnet`       | C#         | ASP.NET Core     | ✅ Complete |
| `scala-play`          | Scala      | Play             | ✅ Complete |

## Quick Start

### Prerequisites

- Go 1.21+
- Docker
- Google Cloud SDK (`gcloud`)
- A GCP project with billing enabled

### Local Development

```bash
# Clone the repository
git clone https://github.com/your-org/discord-bot-test-suite.git
cd discord-bot-test-suite

# Start the Pub/Sub emulator
./scripts/pubsub-emulator.sh start

# Build and run a service locally
docker build -t go-gin-test ./services/go-gin
docker run -p 8080:8080 \
  -e DISCORD_PUBLIC_KEY=398803f0f03317b6dc57069dbe7820e5f6cf7d5ff43ad6219710b19b0b49c159 \
  -e PUBSUB_EMULATOR_HOST=host.docker.internal:8085 \
  -e GOOGLE_CLOUD_PROJECT=test-project \
  -e PUBSUB_TOPIC=test-topic \
  go-gin-test

# Run contract tests against the service
CONTRACT_TEST_TARGET=http://localhost:8080 \
PUBSUB_EMULATOR_HOST=localhost:8085 \
go test ./tests/contract/...
```

## Project Structure

```text
discord-bot-test-suite/
├── services/                    # Language/framework implementations
│   ├── go-gin/
│   ├── python-flask/
│   ├── java-spring3/
│   └── ...
├── tests/
│   ├── contract/               # Black-box contract tests
│   └── cloudrun/               # Cloud Run benchmark tooling
│       ├── cmd/cloudrun-benchmark/
│       ├── configs/
│       ├── internal/
│       └── scripts/
├── scripts/
│   ├── benchmark/              # Benchmark execution scripts
│   ├── pubsub-emulator.sh
│   └── run-contract-tests.sh
├── CLAUDE.md                   # AI assistant guidance
└── README.md
```

## Contract Tests

Contract tests validate that each service implementation correctly handles Discord webhook requests.

```bash
# Run all contract tests
CONTRACT_TEST_TARGET=http://localhost:8080 \
PUBSUB_EMULATOR_HOST=localhost:8085 \
go test ./tests/contract/...

# Run specific test categories
go test ./tests/contract/... -run TestSignature
go test ./tests/contract/... -run TestPing
go test ./tests/contract/... -run TestSlashCommand
```

### Test Categories

- **TestSignature**: Validates Ed25519 signature verification
- **TestPing**: Tests Discord ping/pong handshake
- **TestSlashCommand**: Tests slash command handling and Pub/Sub publishing

## Cloud Run Benchmarking

### GCP Security & Sandboxing

#### For Claude Code / AI Assistant Usage

Before running Claude Code or any AI assistant with GCP access:

1. **Use a dedicated GCP project** for benchmarking—never your production project

2. **Verify your active project** before starting:

   ```bash
   gcloud config get-value project
   # Should show your benchmark project, NOT production
   ```

3. **Consider using gcloud configurations** to isolate benchmark credentials:

   ```bash
   gcloud config configurations create benchmark
   gcloud config set project YOUR_BENCHMARK_PROJECT
   gcloud auth login
   ```

#### Project Isolation (Required)

Create a **dedicated GCP project** for benchmarks (e.g., `mycompany-discord-benchmark`):

| Why Isolation Matters                                            |
| ---------------------------------------------------------------- |
| Prevents accidental access to production resources               |
| Claude/AI can only affect resources in the authenticated project |
| Benchmark costs are isolated and easy to track                   |
| Easy cleanup without affecting other workloads                   |

#### Service Account & Permissions

The setup script creates a service account with minimal required permissions:

| IAM Role                        | Purpose                          |
| ------------------------------- | -------------------------------- |
| `roles/run.admin`               | Deploy/manage Cloud Run services |
| `roles/artifactregistry.writer` | Push container images            |
| `roles/pubsub.admin`            | Create topics/subscriptions      |
| `roles/logging.viewer`          | Read logs for metrics            |
| `roles/monitoring.viewer`       | Read monitoring data             |
| `roles/iam.serviceAccountUser`  | Run services as the SA           |

**What Claude CAN do** (with proper scoping):

- Deploy Cloud Run services
- Build and push container images
- Read logs and metrics
- Clean up benchmark resources

**What Claude CANNOT do** (with proper project isolation):

- Access other GCP projects
- Modify IAM policies
- Access production secrets
- Incur costs outside the benchmark project

### GCP Setup

1. **Create or select a dedicated benchmark project**:

   ```bash
   # Create a new project (recommended)
   gcloud projects create your-benchmark-project --name="Discord Benchmark"

   # Or use an existing project
   gcloud config set project your-benchmark-project
   ```

2. **Enable billing** on the project (required for Cloud Run)

3. **Verify your active project**:

   ```bash
   gcloud config get-value project
   # MUST show your benchmark project before proceeding
   ```

4. **Run the setup script**:

   ```bash
   cd tests/cloudrun
   export PROJECT_ID=your-benchmark-project
   ./scripts/setup-gcp.sh
   ```

   This script (idempotent—safe to run multiple times):

   - Enables required APIs (Cloud Run, Artifact Registry, Pub/Sub, etc.)
   - Creates a service account with minimal permissions
   - Creates an Artifact Registry repository for images
   - Configures Docker authentication

### Build and Push Images

```bash
# Build all service images
cd scripts/benchmark
./build-all-images.sh

# Or build a specific service
docker build -t us-central1-docker.pkg.dev/$PROJECT_ID/discord-services/go-gin:latest ./services/go-gin
docker push us-central1-docker.pkg.dev/$PROJECT_ID/discord-services/go-gin:latest
```

### Run Benchmarks

```bash
# Build the benchmark CLI
cd tests/cloudrun
go build -o cloudrun-benchmark ./cmd/cloudrun-benchmark

# Run full benchmark suite
./cloudrun-benchmark run --config configs/default.yaml

# Run with specific services only
./cloudrun-benchmark run --config configs/default.yaml --services go-gin,rust-actix

# Quick benchmark (fewer iterations)
./cloudrun-benchmark run --config configs/quick.yaml
```

### Benchmark Configuration

Configuration files are in `tests/cloudrun/configs/`:

```yaml
# default.yaml
gcp:
  project_id: '' # Set via PROJECT_ID env var
  region: 'us-central1'

profiles:
  default:
    cpu: '1'
    memory: '512Mi'
    max_instances: 1
    concurrency: 80
    execution_env: 'gen2'
    startup_cpu_boost: true

benchmark:
  cold_start_iterations: 5
  scale_to_zero_timeout: '15m'
  warm_requests: 100
  warm_concurrency: 10

services:
  enabled:
    - go-gin
    - rust-actix
    # ... additional services
```

### Understanding Results

Benchmark results are written to the `results/` directory:

- `results.json`: Raw benchmark data
- `results.md`: Human-readable Markdown report
- `comparison.md`: Comparison with local benchmark data (if provided)

Key metrics:

- **Cold Start Latency**: Time from request to first response when scaling from zero
- **Warm Request Latency**: Request latency with a warm container
- **P50/P95/P99**: Latency percentiles

### Cleanup

The benchmark tool automatically cleans up Cloud Run services after each run. To manually clean up:

```bash
./cloudrun-benchmark cleanup --config configs/default.yaml
```

Or delete resources directly:

```bash
# Delete all benchmark Cloud Run services
gcloud run services list --filter="metadata.labels.benchmark=true" --format="value(name)" | \
  xargs -I {} gcloud run services delete {} --region=us-central1 --quiet

# Delete the Artifact Registry repository (and all images)
gcloud artifacts repositories delete discord-services --location=us-central1 --quiet
```

## Environment Variables

| Variable               | Description                                 |
| ---------------------- | ------------------------------------------- |
| `PORT`                 | HTTP server port (default: 8080)            |
| `DISCORD_PUBLIC_KEY`   | Ed25519 public key for signature validation |
| `PUBSUB_TOPIC`         | Pub/Sub topic for publishing slash commands |
| `PUBSUB_EMULATOR_HOST` | Pub/Sub emulator endpoint (local dev only)  |
| `GOOGLE_CLOUD_PROJECT` | GCP project ID                              |
| `PROJECT_ID`           | GCP project for benchmark scripts           |

## Key Constraints

- **Sensitive data redaction**: Services must never log or publish `token`, signature headers, or raw request body
- **Pub/Sub emulator**: Tests use per-test unique topic/subscription names for parallel execution
- **Test public key**: `398803f0f03317b6dc57069dbe7820e5f6cf7d5ff43ad6219710b19b0b49c159`
- **Test timeout**: All tests must complete within 30 seconds

## Additional Documentation

- [Service Implementation Details](./services/README.md)
