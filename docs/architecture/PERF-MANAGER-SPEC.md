# Performance Test Manager Specification

## Detailed Functional Design

---

## Overview

The Performance Test Manager is the central orchestration component that:
- Discovers service implementations from external repositories
- Deploys services to Cloud Run
- Validates services against their contracts
- Executes benchmarks
- Stores and reports results

It operates independently from service implementations, connected only by well-defined contracts.

---

## Core Concepts

### Service Types

A **Service Type** represents a category of workload (e.g., Discord webhook, REST CRUD, gRPC). Each service type has:

- A formal **contract** defining expected behavior
- A **test vector** set for validation
- Multiple **implementations** across languages/frameworks

### Implementations

An **Implementation** is a specific language/framework version of a service type:

- Lives in a service repository
- Contains Dockerfile and source code
- Declares capabilities in manifest

### Benchmark Run

A **Benchmark Run** is a single execution of the performance test suite:

- Has unique identifier
- Targets one or more service types
- Produces measurements and reports
- Can be compared to other runs

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Performance Test Manager                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │   Service    │  │   Contract   │  │   Benchmark  │          │
│  │  Discovery   │  │  Validator   │  │   Executor   │          │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │
│         │                 │                 │                   │
│  ┌──────┴─────────────────┴─────────────────┴───────┐          │
│  │              Orchestration Engine                 │          │
│  └──────────────────────┬───────────────────────────┘          │
│                         │                                       │
│  ┌──────────────┐  ┌────┴─────────┐  ┌──────────────┐          │
│  │    Image     │  │   Cloud Run  │  │    Result    │          │
│  │   Builder    │  │   Deployer   │  │    Store     │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      External Systems                            │
├─────────────┬─────────────┬─────────────┬───────────────────────┤
│   GitHub    │  Artifact   │  Cloud Run  │  Cloud Storage        │
│   Repos     │  Registry   │             │  (Results)            │
└─────────────┴─────────────┴─────────────┴───────────────────────┘
```

---

## Component Specifications

### 1. Service Discovery

**Purpose:** Find and catalog service implementations from configured repositories.

**Inputs:**
- List of service repository URLs
- Git refs (branches/tags) to examine
- Cache invalidation settings

**Process:**
1. Clone/fetch configured repositories
2. Parse `manifest.yaml` from each repo
3. Validate manifest against schema
4. Build service catalog with metadata

**Outputs:**
- Service catalog (in-memory + cached)
- Validation warnings/errors

**Service Catalog Entry:**
```go
type ServiceEntry struct {
    Type           string            // e.g., "discord-webhook"
    Name           string            // e.g., "go-gin"
    Repository     string            // GitHub URL
    Path           string            // Path within repo
    Dockerfile     string            // Relative Dockerfile path
    BuildArgs      map[string]string // Build arguments
    Features       []string          // Supported features
    ContractVersion string           // Contract version implemented
}
```

**API:**
```go
type ServiceDiscovery interface {
    // Refresh service catalog from repositories
    Refresh(ctx context.Context) error

    // List all discovered services
    List(ctx context.Context, filter ServiceFilter) ([]ServiceEntry, error)

    // Get specific service
    Get(ctx context.Context, serviceType, name string) (*ServiceEntry, error)

    // Get services by type
    ByType(ctx context.Context, serviceType string) ([]ServiceEntry, error)
}
```

---

### 2. Contract Validator

**Purpose:** Validate deployed services against their contract specifications.

**Inputs:**
- Deployed service URL
- Contract definition (OpenAPI, Protobuf, etc.)
- Test vectors

**Process:**
1. Load contract for service type
2. Load test vectors (happy path, errors, edge cases)
3. Execute each test vector against service
4. Compare responses to expected outcomes
5. Aggregate results

**Outputs:**
- Validation result (pass/fail per test)
- Detailed error messages
- Contract compliance percentage

**Test Vector Format:**
```yaml
# test-vectors/happy-path.yaml
name: "Valid Discord Ping"
description: "Service responds to valid ping with pong"
request:
  method: POST
  path: /interactions
  headers:
    Content-Type: application/json
    X-Signature-Ed25519: "${COMPUTED_SIGNATURE}"
    X-Signature-Timestamp: "${CURRENT_TIMESTAMP}"
  body:
    type: 1
    id: "123456789"
    application_id: "987654321"
expected:
  status: 200
  headers:
    Content-Type: application/json
  body:
    type: 1
```

**API:**
```go
type ContractValidator interface {
    // Load contract for service type
    LoadContract(ctx context.Context, serviceType string) (*Contract, error)

    // Validate service against contract
    Validate(ctx context.Context, serviceURL string, contract *Contract) (*ValidationResult, error)

    // Run specific test vector
    RunTestVector(ctx context.Context, serviceURL string, vector TestVector) (*TestResult, error)
}

type ValidationResult struct {
    ServiceType    string
    ServiceName    string
    ServiceURL     string
    TotalTests     int
    PassedTests    int
    FailedTests    int
    Compliance     float64 // Percentage
    Results        []TestResult
    Duration       time.Duration
}
```

---

### 3. Image Builder

**Purpose:** Build container images from service Dockerfiles.

**Inputs:**
- Service entry from catalog
- Target image tag
- Build configuration

**Process:**
1. Clone service repository (if not cached)
2. Build Docker image using Cloud Build or local Docker
3. Push to Artifact Registry
4. Return image digest

**Outputs:**
- Image URI with digest
- Build logs
- Build duration

**API:**
```go
type ImageBuilder interface {
    // Build image for a service
    Build(ctx context.Context, service ServiceEntry, tag string) (*BuildResult, error)

    // Check if image exists
    Exists(ctx context.Context, imageURI string) (bool, error)

    // Get image metadata
    Inspect(ctx context.Context, imageURI string) (*ImageInfo, error)
}

type BuildResult struct {
    ImageURI    string        // Full URI with digest
    Digest      string        // Image digest
    Size        int64         // Image size in bytes
    Duration    time.Duration // Build time
    BuildLogs   string        // Build output
}
```

---

### 4. Cloud Run Deployer

**Purpose:** Deploy services to Cloud Run and manage their lifecycle.

**Inputs:**
- Image URI
- Deployment profile
- Service configuration

**Process:**
1. Create/update Cloud Run service
2. Configure resources (CPU, memory, concurrency)
3. Set environment variables
4. Wait for deployment to complete
5. Verify service health

**Outputs:**
- Service URL
- Deployment status
- Readiness confirmation

**Deployment Profile:**
```yaml
profiles:
  default:
    cpu: "1"
    memory: "512Mi"
    max_instances: 1
    min_instances: 0
    concurrency: 80
    timeout: 30s
    execution_env: gen2
    startup_cpu_boost: true
    vpc_connector: null
    env_vars:
      LOG_LEVEL: info
```

**API:**
```go
type CloudRunDeployer interface {
    // Deploy service to Cloud Run
    Deploy(ctx context.Context, req DeployRequest) (*DeployResult, error)

    // Get service status
    Status(ctx context.Context, serviceName string) (*ServiceStatus, error)

    // Delete service
    Delete(ctx context.Context, serviceName string) error

    // Scale service to zero
    ScaleToZero(ctx context.Context, serviceName string) error

    // Wait for service to be ready
    WaitReady(ctx context.Context, serviceName string, timeout time.Duration) error
}

type DeployRequest struct {
    ServiceName string
    ImageURI    string
    Profile     DeploymentProfile
    Labels      map[string]string
}

type DeployResult struct {
    ServiceName string
    ServiceURL  string
    Revision    string
    Region      string
    DeployTime  time.Duration
}
```

---

### 5. Benchmark Executor

**Purpose:** Execute performance measurements against deployed services.

**Inputs:**
- Service URL
- Benchmark configuration
- Test payload generator

**Process:**
1. Verify service is ready
2. Execute cold start measurements
3. Execute warm request measurements
4. Calculate statistics

**Outputs:**
- Raw measurements
- Statistical summaries
- Benchmark metadata

**Measurement Types:**

#### Cold Start Measurement
```go
type ColdStartMeasurement struct {
    Iteration       int
    ScaleDownTime   time.Duration  // Time to scale to zero
    ResponseTime    time.Duration  // Time to first response
    ServerTiming    time.Duration  // Server-reported processing time
    StatusCode      int
    Timestamp       time.Time
}
```

#### Warm Request Measurement
```go
type WarmRequestMeasurement struct {
    RequestNum      int
    ResponseTime    time.Duration
    StatusCode      int
    ContentLength   int64
    Timestamp       time.Time
}
```

**Statistics:**
```go
type BenchmarkStatistics struct {
    Count       int
    Min         time.Duration
    Max         time.Duration
    Mean        time.Duration
    Median      time.Duration
    StdDev      time.Duration
    P50         time.Duration
    P90         time.Duration
    P95         time.Duration
    P99         time.Duration
}
```

**API:**
```go
type BenchmarkExecutor interface {
    // Run full benchmark suite for a service
    Run(ctx context.Context, serviceURL string, config BenchmarkConfig) (*BenchmarkResult, error)

    // Run cold start measurement
    MeasureColdStart(ctx context.Context, serviceURL string, iterations int) ([]ColdStartMeasurement, error)

    // Run warm request measurements
    MeasureWarmRequests(ctx context.Context, serviceURL string, count, concurrency int) ([]WarmRequestMeasurement, error)

    // Measure scale-to-zero time
    MeasureScaleToZero(ctx context.Context, serviceName string, timeout time.Duration) (time.Duration, error)
}
```

---

### 6. Result Store

**Purpose:** Persist benchmark results and enable historical analysis.

**Inputs:**
- Benchmark results
- Run metadata
- Storage configuration

**Process:**
1. Generate unique run ID
2. Serialize results to JSON
3. Upload to GCS
4. Update latest pointers

**Storage Layout:**
```
gs://cloudrun-benchmark-results/
├── runs/
│   ├── 2026-01-24-abc123/
│   │   ├── metadata.json
│   │   ├── services/
│   │   │   ├── discord-webhook/
│   │   │   │   ├── go-gin.json
│   │   │   │   ├── rust-actix.json
│   │   │   │   └── ...
│   │   │   └── rest-crud/
│   │   │       └── ...
│   │   └── summary.json
│   └── ...
├── baselines/
│   ├── latest.json
│   └── 2026-01-01.json
└── indexes/
    └── runs.json
```

**API:**
```go
type ResultStore interface {
    // Save benchmark results
    Save(ctx context.Context, run *BenchmarkRun) error

    // Load benchmark run
    Load(ctx context.Context, runID string) (*BenchmarkRun, error)

    // List runs
    List(ctx context.Context, filter RunFilter) ([]RunSummary, error)

    // Get latest baseline
    GetBaseline(ctx context.Context) (*BenchmarkRun, error)

    // Set new baseline
    SetBaseline(ctx context.Context, runID string) error

    // Compare two runs
    Compare(ctx context.Context, baselineID, currentID string) (*ComparisonResult, error)
}
```

---

### 7. Report Generator

**Purpose:** Generate human and machine-readable reports from benchmark results.

**Inputs:**
- Benchmark run(s)
- Report format
- Comparison baseline (optional)

**Outputs:**
- Markdown reports
- JSON reports
- Comparison reports

**Report Sections:**
1. Executive Summary
2. Service Rankings
3. Per-Service Details
4. Cold Start Analysis
5. Warm Request Analysis
6. Regression Alerts
7. Recommendations

**Markdown Report Example:**
```markdown
# Cloud Run Benchmark Report

**Run ID:** 2026-01-24-abc123
**Date:** 2026-01-24 14:30:00 UTC
**Services Tested:** 19
**Service Types:** discord-webhook

## Executive Summary

| Metric | Best | Worst | Mean |
|--------|------|-------|------|
| Cold Start (p50) | 145ms (go-gin) | 2,340ms (java-spring3) | 890ms |
| Warm Request (p50) | 2ms (rust-actix) | 45ms (ruby-rails) | 12ms |

## Cold Start Rankings

| Rank | Service | P50 | P90 | P99 | Change |
|------|---------|-----|-----|-----|--------|
| 1 | go-gin | 145ms | 180ms | 220ms | -5% |
| 2 | rust-actix | 160ms | 195ms | 240ms | +2% |
| 3 | cpp-drogon | 175ms | 210ms | 260ms | 0% |
...
```

**API:**
```go
type ReportGenerator interface {
    // Generate Markdown report
    GenerateMarkdown(ctx context.Context, run *BenchmarkRun, opts ReportOptions) (string, error)

    // Generate JSON report
    GenerateJSON(ctx context.Context, run *BenchmarkRun) ([]byte, error)

    // Generate comparison report
    GenerateComparison(ctx context.Context, baseline, current *BenchmarkRun) (*ComparisonReport, error)
}

type ReportOptions struct {
    IncludeRawData    bool
    CompareBaseline   bool
    BaselineRunID     string
    Sections          []string
}
```

---

## Orchestration Workflow

### Full Benchmark Flow

```
START
  │
  ▼
┌─────────────────────────────────────────┐
│ 1. Service Discovery                     │
│    - Fetch manifests from repos          │
│    - Build service catalog               │
│    - Apply filters (type, impl)          │
└─────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────┐
│ 2. Image Building                        │
│    - Build images in parallel batches    │
│    - Push to Artifact Registry           │
│    - Verify image availability           │
└─────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────┐
│ 3. Deployment                            │
│    - Deploy to Cloud Run in batches      │
│    - Wait for readiness                  │
│    - Verify health endpoints             │
└─────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────┐
│ 4. Contract Validation                   │
│    - Run test vectors                    │
│    - Record compliance                   │
│    - Flag failures (don't benchmark)     │
└─────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────┐
│ 5. Benchmark Execution                   │
│    For each service:                     │
│    a. Scale to zero, wait                │
│    b. Cold start measurements (N iter)   │
│    c. Warm request measurements          │
│    d. Record results                     │
└─────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────┐
│ 6. Result Storage                        │
│    - Save raw measurements               │
│    - Calculate statistics                │
│    - Upload to GCS                       │
└─────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────┐
│ 7. Report Generation                     │
│    - Compare to baseline                 │
│    - Generate Markdown/JSON              │
│    - Publish reports                     │
└─────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────┐
│ 8. Cleanup                               │
│    - Delete Cloud Run services           │
│    - Clean up images (optional)          │
└─────────────────────────────────────────┘
  │
  ▼
END
```

---

## Configuration

### Main Configuration File

```yaml
# cloudrun-perf.yaml
version: "1.0"

# GCP Settings
gcp:
  project_id: ${GCP_PROJECT_ID}
  region: us-central1
  artifact_registry:
    location: us-central1
    repository: cloudrun-perf-images

# Service Repository Registry
repositories:
  - name: discord-webhook
    url: https://github.com/org/cloudrun-service-discord
    ref: main
    contract: contracts/v1/discord-webhook.yaml

  - name: rest-crud
    url: https://github.com/org/cloudrun-service-rest-crud
    ref: main
    contract: contracts/v1/rest-crud.yaml

# Deployment Profiles
profiles:
  default:
    cpu: "1"
    memory: "512Mi"
    max_instances: 1
    min_instances: 0
    concurrency: 80
    execution_env: gen2
    startup_cpu_boost: true

  constrained:
    cpu: "0.5"
    memory: "256Mi"
    max_instances: 1
    concurrency: 40

# Benchmark Configuration
benchmark:
  cold_start:
    iterations: 10
    scale_to_zero_timeout: 15m
    warmup_requests: 3

  warm_requests:
    count: 100
    concurrency: 10

  timeouts:
    deploy: 5m
    health_check: 30s
    scale_to_zero: 15m

# Result Storage
storage:
  type: gcs
  bucket: cloudrun-benchmark-results
  prefix: ""

# Filtering
filter:
  service_types: []      # Empty = all
  implementations: []    # Empty = all
  exclude: []            # Explicit exclusions

# Notifications (optional)
notifications:
  slack:
    webhook_url: ${SLACK_WEBHOOK}
    on_completion: true
    on_regression: true
    regression_threshold: 10  # Percent
```

---

## Error Handling

### Failure Modes and Recovery

| Failure Mode | Impact | Recovery Strategy |
|--------------|--------|-------------------|
| Git clone fails | Cannot discover service | Retry 3x, then skip with warning |
| Image build fails | Cannot benchmark service | Log error, continue with others |
| Deployment fails | Cannot benchmark service | Retry once, then skip |
| Contract validation fails | Service doesn't meet spec | Skip benchmarking, report failure |
| Benchmark timeout | Incomplete measurements | Record partial data, flag as incomplete |
| GCS upload fails | Results not persisted | Retry 3x, keep local copy |

### Error Reporting

```go
type BenchmarkError struct {
    Phase       string    // discovery, build, deploy, validate, benchmark, report
    ServiceType string
    ServiceName string
    Message     string
    Cause       error
    Timestamp   time.Time
    Recoverable bool
}
```

---

## Observability

### Structured Logging

```json
{
  "level": "info",
  "time": "2026-01-24T14:30:00Z",
  "component": "benchmark-executor",
  "service_type": "discord-webhook",
  "service_name": "go-gin",
  "event": "cold_start_measured",
  "iteration": 3,
  "duration_ms": 145,
  "status_code": 200
}
```

### Metrics (for Cloud Monitoring)

| Metric | Type | Labels |
|--------|------|--------|
| `benchmark_cold_start_duration` | Histogram | service_type, service_name |
| `benchmark_warm_request_duration` | Histogram | service_type, service_name |
| `benchmark_contract_compliance` | Gauge | service_type, service_name |
| `benchmark_run_duration` | Histogram | service_type |
| `benchmark_errors_total` | Counter | phase, error_type |

---

## Security Considerations

1. **Credentials** - Never log or expose GCP credentials
2. **Image signing** - Consider signing images for verification
3. **Network isolation** - Services run in isolated Cloud Run environments
4. **Least privilege** - Service account has minimal required permissions
5. **Audit logging** - All operations logged for audit trail

---

## Future Considerations

1. **Parallel benchmark execution** - Run multiple services simultaneously
2. **Geographic distribution** - Benchmark in multiple regions
3. **Custom test payloads** - Allow service-specific benchmark scenarios
4. **Regression alerting** - Automated alerts on performance degradation
5. **Dashboard integration** - Real-time monitoring during runs
6. **Cost tracking** - Report GCP costs per benchmark run

---

## Implementation Priority

| Component | Priority | Complexity | Dependencies |
|-----------|----------|------------|--------------|
| Service Discovery | P0 | Medium | Git, YAML parsing |
| Contract Validator | P0 | Medium | Test vector format |
| Image Builder | P0 | Low | Cloud Build API |
| Cloud Run Deployer | P0 | Medium | Cloud Run API |
| Benchmark Executor | P0 | High | Request signing |
| Result Store | P1 | Low | GCS API |
| Report Generator | P1 | Medium | Result Store |
| Notifications | P2 | Low | Slack API |

---

*This specification is part of the Multi-Repository Architecture Proposal.*
