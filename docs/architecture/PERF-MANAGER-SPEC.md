# Perf Manager Specification

## Central Orchestration Component

**Status:** Draft (Revised)
**Date:** 2026-01-24
**Revision:** 2 - Simplified for delegated agent pattern

---

## Overview

The Perf Manager is the central orchestration component that:

- **Discovers** Perf Agents from a GCS registry
- **Invokes** Agents through a standard interface
- **Aggregates** results from all Agents
- **Stores** results in GCS
- **Reports** on performance with comparisons to baselines

**Critical design principle:** The Perf Manager has **zero knowledge** of service-specific testing.
It doesn't know how to test Discord webhooks, gRPC services, or REST APIs.
That knowledge lives entirely in the Perf Agents.

---

## What Perf Manager Does NOT Do

| Responsibility               | Owner                 |
| ---------------------------- | --------------------- |
| Ed25519 signature generation | Discord Perf Agent    |
| Protobuf serialization       | gRPC Perf Agent       |
| SQL database setup           | REST CRUD Perf Agent  |
| Contract validation          | Each respective Agent |
| Service-specific payloads    | Each respective Agent |
| Cold start measurement logic | Each respective Agent |

The Perf Manager only sees standardized results.

---

## Architecture

```text
┌─────────────────────────────────────────────────────────────────┐
│                        PERF MANAGER                              │
│                                                                  │
│  ┌──────────────┐                                               │
│  │   Discovery  │──► Read gs://perf-agent-registry/agents/*.yaml│
│  └──────────────┘                                               │
│         │                                                        │
│         ▼                                                        │
│  ┌──────────────┐                                               │
│  │ Orchestrator │──► For each Agent: invoke standard endpoint   │
│  └──────────────┘                                               │
│         │                                                        │
│         ▼                                                        │
│  ┌──────────────┐                                               │
│  │  Aggregator  │──► Combine results from all Agents            │
│  └──────────────┘                                               │
│         │                                                        │
│         ▼                                                        │
│  ┌──────────────┐                                               │
│  │   Storage    │──► Write to gs://perf-results/runs/{run-id}/  │
│  └──────────────┘                                               │
│         │                                                        │
│         ▼                                                        │
│  ┌──────────────┐                                               │
│  │  Reporter    │──► Generate Markdown/JSON reports             │
│  └──────────────┘                                               │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Components

### 1. Discovery

**Purpose:** Find and validate Perf Agents from the GCS registry.

**Process:**

1. List objects in `gs://perf-agent-registry/agents/`
2. Download each `.yaml` manifest
3. Validate against JSON Schema
4. Build in-memory agent catalog
5. Filter by enabled status

**Agent Catalog Entry:**

```go
type AgentEntry struct {
    ServiceType     string   // e.g., "discord-webhook"
    Enabled         bool
    Endpoint        string   // Cloud Run URL
    Type            string   // "cloud_run_service" or "cloud_run_job"
    Implementations []Implementation
    Metadata        AgentMetadata
}

type Implementation struct {
    Name   string // e.g., "go-gin"
    Status string // "active" or "disabled"
}
```

**API:**

```go
type Discovery interface {
    // Refresh agent catalog from GCS
    Refresh(ctx context.Context) error

    // List all discovered agents
    List(ctx context.Context) ([]AgentEntry, error)

    // List enabled agents only
    ListEnabled(ctx context.Context) ([]AgentEntry, error)

    // Get specific agent
    Get(ctx context.Context, serviceType string) (*AgentEntry, error)
}
```

---

### 2. Orchestrator

**Purpose:** Invoke Perf Agents and coordinate benchmark execution.

**Process:**

1. Get list of enabled agents
2. For each agent (parallel or sequential based on config):
   - Build invocation request
   - Call agent endpoint with timeout
   - Collect response
3. Handle failures gracefully (continue with other agents)

**Invocation Request (sent to Agent):**

```json
{
  "run_id": "2026-01-24-abc123",
  "implementations": ["go-gin", "rust-actix"],
  "config": {
    "cold_start_iterations": 10,
    "warm_request_count": 100,
    "warm_request_concurrency": 10,
    "profile": "default"
  }
}
```

If `implementations` is empty or omitted, the Agent benchmarks all active implementations.

**API:**

```go
type Orchestrator interface {
    // Run benchmarks for all enabled agents
    RunAll(ctx context.Context, config BenchmarkConfig) (*AggregatedResults, error)

    // Run benchmark for specific service type
    RunOne(ctx context.Context, serviceType string, config BenchmarkConfig) (*AgentResults, error)

    // Run with custom agent filter
    RunFiltered(ctx context.Context, filter AgentFilter, config BenchmarkConfig) (*AggregatedResults, error)
}
```

**Authentication:**

- Uses GCP service account identity
- Agents grant `roles/run.invoker` to Perf Manager service account
- No API keys or tokens needed

---

### 3. Aggregator

**Purpose:** Combine results from multiple Agents into unified structure.

**Process:**

1. Receive results from each Agent
2. Validate result format against schema
3. Merge into unified results structure
4. Calculate cross-agent statistics (if applicable)

**Aggregated Results Structure:**

```go
type AggregatedResults struct {
    RunID       string
    StartTime   time.Time
    EndTime     time.Time
    Duration    time.Duration
    Config      BenchmarkConfig
    AgentResults []AgentResults
    Summary     ResultsSummary
    Errors      []AgentError
}

type ResultsSummary struct {
    TotalAgents        int
    SuccessfulAgents   int
    FailedAgents       int
    TotalImplementations int
    BenchmarkedImplementations int
}
```

---

### 4. Storage

**Purpose:** Persist benchmark results to GCS.

**Storage Layout:**

```text
gs://perf-results/
├── runs/
│   └── 2026-01-24-abc123/
│       ├── metadata.json           # Run metadata
│       ├── config.json             # Benchmark configuration
│       ├── agents/
│       │   ├── discord-webhook.json  # Raw results from Agent
│       │   ├── rest-crud.json
│       │   └── ...
│       ├── aggregated.json         # Combined results
│       └── report.md               # Generated report
├── baselines/
│   ├── latest.json                 # Symlink/copy to latest baseline
│   └── 2026-01-15.json             # Historical baselines
└── index.json                      # Index of all runs
```

**API:**

```go
type Storage interface {
    // Save complete run results
    SaveRun(ctx context.Context, results *AggregatedResults) error

    // Load run by ID
    LoadRun(ctx context.Context, runID string) (*AggregatedResults, error)

    // List all runs
    ListRuns(ctx context.Context, limit int) ([]RunSummary, error)

    // Get current baseline
    GetBaseline(ctx context.Context) (*AggregatedResults, error)

    // Set new baseline
    SetBaseline(ctx context.Context, runID string) error
}
```

---

### 5. Reporter

**Purpose:** Generate human and machine-readable reports.

**Report Types:**

| Type       | Format   | Purpose                       |
| ---------- | -------- | ----------------------------- |
| Summary    | Markdown | Human-readable overview       |
| Detailed   | Markdown | Full results with all metrics |
| JSON       | JSON     | Programmatic consumption      |
| Comparison | Markdown | Diff against baseline         |

**Report Sections:**

1. Executive Summary (best/worst performers, regressions)
2. Agent-by-Agent Results
3. Implementation Rankings (cold start, warm requests)
4. Regression Alerts
5. Raw Statistics

**Example Summary Report:**

```markdown
# Perf Benchmark Report

**Run ID:** 2026-01-24-abc123
**Date:** 2026-01-24 14:30 UTC
**Duration:** 45 minutes

## Summary

| Metric                 | Value |
| ---------------------- | ----- |
| Service Types Tested   | 6     |
| Implementations Tested | 114   |
| Successful             | 112   |
| Failed                 | 2     |

## Cold Start Rankings (Top 10)

| Rank | Service Type    | Implementation | P50   | P99   | Δ Baseline |
| ---- | --------------- | -------------- | ----- | ----- | ---------- |
| 1    | discord-webhook | go-gin         | 145ms | 220ms | -5%        |
| 2    | discord-webhook | rust-actix     | 160ms | 240ms | +2%        |
| 3    | rest-crud       | go-gin         | 180ms | 280ms | 0%         |

...

## Regressions (>10% slower than baseline)

| Service Type    | Implementation | Metric         | Baseline | Current | Change |
| --------------- | -------------- | -------------- | -------- | ------- | ------ |
| discord-webhook | java-spring3   | cold_start_p50 | 800ms    | 920ms   | +15%   |

## Errors

- rest-crud/php-laravel: Connection timeout after 30s
- grpc-unary/ruby-rails: Contract validation failed (3 tests)
```

**API:**

```go
type Reporter interface {
    // Generate markdown summary
    GenerateSummary(ctx context.Context, results *AggregatedResults) (string, error)

    // Generate detailed markdown report
    GenerateDetailed(ctx context.Context, results *AggregatedResults) (string, error)

    // Generate JSON report
    GenerateJSON(ctx context.Context, results *AggregatedResults) ([]byte, error)

    // Generate comparison against baseline
    GenerateComparison(ctx context.Context, baseline, current *AggregatedResults) (string, error)
}
```

---

## CLI Interface

```text
perf-manager [global-flags] <command> [command-flags]

Global Flags:
  --config <path>       Configuration file (default: perf-manager.yaml)
  --project <id>        GCP project ID (or $GCP_PROJECT_ID)
  --verbose             Enable verbose logging
  --dry-run             Show what would be done

Commands:
  discover              List available Perf Agents
  run                   Execute benchmark suite
  report                Generate report from stored results
  compare               Compare two benchmark runs
  baseline              Manage baselines
  cleanup               Clean up old results

Examples:
  # Discover registered agents
  perf-manager discover

  # Run full benchmark suite
  perf-manager run

  # Run specific service type
  perf-manager run --type discord-webhook

  # Run with specific implementations
  perf-manager run --type discord-webhook --impl go-gin,rust-actix

  # Generate report from latest run
  perf-manager report --run latest

  # Compare runs
  perf-manager compare --baseline 2026-01-15-xyz --current 2026-01-24-abc

  # Set new baseline
  perf-manager baseline set 2026-01-24-abc123
```

---

## Configuration

```yaml
# perf-manager.yaml

version: '1.0'

gcp:
  project_id: ${GCP_PROJECT_ID}
  region: us-central1

registry:
  bucket: perf-agent-registry
  path: agents/

results:
  bucket: perf-results
  retention_days: 90

benchmark:
  cold_start_iterations: 10
  warm_request_count: 100
  warm_request_concurrency: 10
  timeout: 30m # Per-agent timeout

execution:
  parallel_agents: true # Run agents in parallel
  max_parallel: 3 # Max concurrent agent invocations
  continue_on_error: true # Don't abort on single agent failure

reporting:
  generate_on_completion: true
  formats: [markdown, json]
  comparison:
    regression_threshold: 10 # Percent change to flag as regression
    improvement_threshold: 10 # Percent change to flag as improvement

# Optional: filter which agents to run
filter:
  service_types: [] # Empty = all
  exclude_types: [] # Explicit exclusions
```

---

## Deployment

### As Cloud Run Job (Recommended)

```yaml
# terraform/cloudrun-job.tf

resource "google_cloud_run_v2_job" "perf_manager" {
  name     = "perf-manager"
  location = var.region

  template {
    template {
      containers {
        image = "${var.artifact_registry}/perf-manager:latest"

        env {
          name  = "GCP_PROJECT_ID"
          value = var.project_id
        }
      }

      service_account = google_service_account.perf_manager.email
      timeout         = "3600s"  # 1 hour
    }
  }
}

# Schedule: Run daily at 2 AM
resource "google_cloud_scheduler_job" "perf_manager_daily" {
  name     = "perf-manager-daily"
  schedule = "0 2 * * *"

  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_id}/jobs/perf-manager:run"
    oauth_token {
      service_account_email = google_service_account.scheduler.email
    }
  }
}
```

### Service Account Permissions

```yaml
# Required roles for Perf Manager service account

# Read agent registry
- roles/storage.objectViewer # on perf-agent-registry bucket

# Write results
- roles/storage.objectAdmin # on perf-results bucket

# Invoke Perf Agents
- roles/run.invoker # granted per-agent by each agent's IAM

# Optional: Cloud Logging
- roles/logging.logWriter
```

---

## Standard Agent Interface

The Perf Manager invokes Agents using this standardized interface.
See [PERF-AGENT-SPEC.md](./PERF-AGENT-SPEC.md) for complete Agent specification.

### Request (Manager → Agent)

```http
POST /benchmark HTTP/1.1
Host: discord-perf-agent-xxxxx-uc.a.run.app
Authorization: Bearer <identity-token>
Content-Type: application/json

{
  "run_id": "2026-01-24-abc123",
  "implementations": [],
  "config": {
    "cold_start_iterations": 10,
    "warm_request_count": 100,
    "warm_request_concurrency": 10,
    "profile": "default"
  }
}
```

### Response (Agent → Manager)

```json
{
  "service_type": "discord-webhook",
  "agent_version": "1.2.0",
  "run_id": "2026-01-24-abc123",
  "start_time": "2026-01-24T14:30:00Z",
  "end_time": "2026-01-24T14:45:00Z",
  "results": [
    {
      "implementation": "go-gin",
      "status": "success",
      "contract_compliance": 100.0,
      "cold_start": {
        "iterations": 10,
        "measurements_ms": [145, 148, 142, 151, 147, 144, 149, 146, 143, 150],
        "statistics": {
          "min_ms": 142,
          "max_ms": 151,
          "mean_ms": 146.5,
          "median_ms": 146.5,
          "p50_ms": 146,
          "p90_ms": 150,
          "p99_ms": 151,
          "stddev_ms": 2.9
        }
      },
      "warm_requests": {
        "count": 100,
        "concurrency": 10,
        "statistics": {
          "min_ms": 2,
          "max_ms": 15,
          "mean_ms": 4.2,
          "p50_ms": 3,
          "p90_ms": 8,
          "p99_ms": 12
        },
        "throughput_rps": 238.5,
        "error_rate": 0.0
      }
    },
    {
      "implementation": "rust-actix",
      "status": "success",
      ...
    }
  ],
  "errors": []
}
```

---

## Error Handling

### Agent Invocation Errors

| Error Type       | Handling                                         |
| ---------------- | ------------------------------------------------ |
| Network timeout  | Retry once, then mark agent as failed            |
| HTTP 4xx         | Log error, skip agent (configuration issue)      |
| HTTP 5xx         | Retry with backoff, then mark failed             |
| Invalid response | Log warning, include partial results if possible |

### Aggregation Policy

- Continue processing other agents on individual failure
- Include failed agents in report with error details
- Exit code reflects overall success (0 = all pass, 1 = some failures)

---

## Observability

### Structured Logging

```json
{
  "severity": "INFO",
  "time": "2026-01-24T14:30:00Z",
  "component": "orchestrator",
  "event": "agent_invocation_start",
  "run_id": "2026-01-24-abc123",
  "service_type": "discord-webhook",
  "agent_endpoint": "https://discord-perf-agent-xxxxx-uc.a.run.app"
}
```

### Key Events

| Event                       | Severity | Description             |
| --------------------------- | -------- | ----------------------- |
| `run_started`               | INFO     | Benchmark run initiated |
| `agent_invocation_start`    | INFO     | Calling agent endpoint  |
| `agent_invocation_complete` | INFO     | Agent returned results  |
| `agent_invocation_error`    | ERROR    | Agent call failed       |
| `results_saved`             | INFO     | Results written to GCS  |
| `report_generated`          | INFO     | Report created          |
| `run_completed`             | INFO     | Full run finished       |

---

## Security Considerations

1. **No secrets in config** - Use environment variables or Secret Manager
2. **Service account scoping** - Minimal required permissions
3. **Audit logging** - All GCS and Cloud Run operations logged
4. **No credential logging** - Ensure tokens don't appear in logs

---

## Repository Structure

```text
cloudrun-perf-manager/
├── cmd/
│   └── perf-manager/
│       └── main.go
├── internal/
│   ├── discovery/
│   │   ├── discovery.go
│   │   └── discovery_test.go
│   ├── orchestrator/
│   │   ├── orchestrator.go
│   │   └── orchestrator_test.go
│   ├── aggregator/
│   │   ├── aggregator.go
│   │   └── aggregator_test.go
│   ├── storage/
│   │   ├── gcs.go
│   │   └── gcs_test.go
│   └── reporter/
│       ├── markdown.go
│       ├── json.go
│       └── comparison.go
├── schemas/
│   ├── agent-manifest.schema.json
│   ├── agent-request.schema.json
│   ├── agent-response.schema.json
│   └── results.schema.json
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── iam.tf
│   ├── storage.tf
│   └── cloudrun-job.tf
├── configs/
│   ├── default.yaml
│   └── quick.yaml
├── Dockerfile
├── go.mod
├── go.sum
└── README.md
```

---

## Document History

| Version | Date       | Author              | Changes                                |
| ------- | ---------- | ------------------- | -------------------------------------- |
| 0.1     | 2026-01-24 | Architecture Review | Initial draft                          |
| 0.2     | 2026-01-24 | Architecture Review | Simplified for delegated agent pattern |
