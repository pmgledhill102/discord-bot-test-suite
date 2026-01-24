# Perf Agent Specification

## Service-Specific Test Executor

**Status:** Draft
**Date:** 2026-01-24

---

## Overview

A Perf Agent is a service-specific test executor that:

- **Knows** how to test its particular service type (Discord, REST, gRPC, etc.)
- **Implements** the standard Agent API for invocation by the Perf Manager
- **Lives** in the same repository as the services it tests
- **Returns** standardized results regardless of internal test mechanics

Each service type has exactly one Perf Agent. The Agent handles all service-specific concerns:

| Service Type | Agent Knows About |
|--------------|-------------------|
| Discord Webhook | Ed25519 signatures, Discord payloads, interaction types |
| REST CRUD | HTTP verbs, SQL setup, database connections |
| gRPC Unary | Protocol Buffers, gRPC calls, binary serialization |
| Queue Worker | Pub/Sub messages, acknowledgment, dead-letter handling |
| WebSocket | Connection establishment, message framing, ping/pong |
| GraphQL | Query parsing, schema validation, resolvers |

---

## Agent Responsibilities

### Must Do

1. **Implement phased API** - `/deploy`, `/measure`, `/status`, `/cleanup` endpoints
2. **Deploy services** - Deploy implementations to Cloud Run with specified configurations
3. **Schedule measurement** - Create Cloud Scheduler job to trigger measurement phase
4. **Manage state in GCS** - Write deployment manifests, status, and results to GCS
5. **Test implementations** - Execute cold start and warm request measurements
6. **Validate contracts** - Run contract tests against services
7. **Return standard results** - Use the defined response schema
8. **Handle errors gracefully** - Report failures, enable recovery

### May Do

1. **Manage dependencies** - Set up databases, message queues, etc.
2. **Custom metrics** - Include service-type-specific measurements
3. **Parallel deployment** - Deploy multiple services concurrently

### Must NOT Do

1. **Expose service internals** - Results must be protocol-agnostic
2. **Require Manager changes** - New Agents work with existing Manager
3. **Break the interface** - Must conform to response schema
4. **Wait for scale-to-zero** - Use scheduled execution instead

---

## Phased Execution Model

The Agent implements a two-phase benchmark execution to avoid idle compute time while waiting for services to scale to zero.

```
┌─────────────────────────────────────────────────────────────────┐
│                    PHASE 1: DEPLOYMENT                           │
│                                                                  │
│  Perf Manager ──► POST /deploy ──► Agent deploys services       │
│                                    Agent writes manifest to GCS  │
│                                    Agent schedules measurement   │
│                                    Agent returns immediately     │
│                                                                  │
│  Duration: ~2-5 minutes (active compute)                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ 15-20 minutes (NO COMPUTE RUNNING)
                              │ Services scale to zero
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    PHASE 2: MEASUREMENT                          │
│                                                                  │
│  Cloud Scheduler ──► POST /measure ──► Agent reads manifest     │
│                                        Agent measures cold start │
│                                        Agent measures warm reqs  │
│                                        Agent writes results      │
│                                                                  │
│  Duration: ~15-30 minutes (active compute)                      │
└─────────────────────────────────────────────────────────────────┘
```

---

## Standard API

### Endpoint: POST /deploy

**Purpose:** Deploy services and schedule measurement phase.

**Request:**
```http
POST /deploy HTTP/1.1
Host: discord-perf-agent-xxxxx-uc.a.run.app
Authorization: Bearer <identity-token>
Content-Type: application/json

{
  "run_id": "2026-01-24-abc123",
  "benchmark_config": {
    "cold_start_iterations": 10,
    "warm_request_count": 100,
    "warm_request_concurrency": 10
  },
  "agent_config": {
    "implementations": ["go-gin", "rust-actix"],
    "test_matrix": {
      "cpu": ["1", "2"],
      "startup_boost": [true]
    }
  },
  "schedule": {
    "measure_delay_minutes": 20
  }
}
```

**Response:**
```json
{
  "run_id": "2026-01-24-abc123",
  "status": "deploying",
  "services_to_deploy": 4,
  "measure_scheduled_at": "2026-01-24T14:20:00Z",
  "state_url": "gs://perf-benchmark-state/runs/2026-01-24-abc123/discord-webhook/",
  "scheduler_job": "discord-measure-2026-01-24-abc123"
}
```

**What the Agent does:**
1. Validates request
2. Expands configuration matrix (e.g., 2 impls × 2 CPUs = 4 deployments)
3. Deploys services to Cloud Run (parallel)
4. Writes deployment manifest to GCS
5. Creates Cloud Scheduler job for measurement phase
6. Returns immediately (does NOT wait for scale-to-zero)

---

### Endpoint: POST /measure

**Purpose:** Execute measurements against deployed services (triggered by Cloud Scheduler).

**Request:**
```http
POST /measure HTTP/1.1
Host: discord-perf-agent-xxxxx-uc.a.run.app
Authorization: Bearer <identity-token>
Content-Type: application/json

{
  "run_id": "2026-01-24-abc123"
}
```

**Response:**
```json
{
  "run_id": "2026-01-24-abc123",
  "status": "measuring",
  "results_url": "gs://perf-benchmark-state/runs/2026-01-24-abc123/discord-webhook/results.json"
}
```

**What the Agent does:**
1. Reads deployment manifest from GCS
2. Verifies services are at zero instances (optional check)
3. For each deployed service:
   - Runs contract validation
   - Measures cold starts (N iterations)
   - Measures warm requests
4. Writes results to GCS
5. Optionally publishes completion event to Pub/Sub
6. Deletes the Cloud Scheduler job (one-time execution)

---

### Endpoint: GET /status/{run_id}

**Purpose:** Check progress of a benchmark run.

**Response:**
```json
{
  "run_id": "2026-01-24-abc123",
  "service_type": "discord-webhook",
  "phase": "measuring",
  "progress": {
    "total_services": 4,
    "deployed": 4,
    "measured": 2
  },
  "timestamps": {
    "deploy_started": "2026-01-24T14:00:00Z",
    "deploy_completed": "2026-01-24T14:03:00Z",
    "measure_started": "2026-01-24T14:20:00Z",
    "measure_completed": null
  },
  "errors": []
}
```

**Phase values:** `pending`, `deploying`, `waiting`, `measuring`, `completed`, `failed`

---

### Endpoint: POST /cleanup

**Purpose:** Remove deployed services and clean up resources.

**Request:**
```http
POST /cleanup HTTP/1.1
Host: discord-perf-agent-xxxxx-uc.a.run.app
Authorization: Bearer <identity-token>
Content-Type: application/json

{
  "run_id": "2026-01-24-abc123"
}
```

**Response:**
```json
{
  "run_id": "2026-01-24-abc123",
  "services_deleted": 4,
  "scheduler_job_deleted": true
}
```

---

### Endpoint: GET /health

**Purpose:** Health check for the Agent itself.

**Response:**
```json
{
  "status": "healthy",
  "version": "1.2.0",
  "service_type": "discord-webhook"
}
```

---

## Legacy Endpoint: POST /benchmark

**Purpose:** Single-phase benchmark execution (for backwards compatibility or simple cases).

**Note:** This endpoint performs deployment, waits, and measurement in a single call. Use only for quick tests or debugging. For production benchmarks, use the phased `/deploy` + `/measure` pattern.

**Request:**
```http
POST /benchmark HTTP/1.1
Host: discord-perf-agent-xxxxx-uc.a.run.app
Authorization: Bearer <identity-token>
Content-Type: application/json

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

**Request Fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `run_id` | string | Yes | Unique identifier for this benchmark run |
| `implementations` | string[] | No | Implementations to test (empty = all active) |
| `config.cold_start_iterations` | int | Yes | Number of cold start measurements |
| `config.warm_request_count` | int | Yes | Number of warm requests to send |
| `config.warm_request_concurrency` | int | Yes | Concurrent warm requests |
| `config.profile` | string | No | Deployment profile (default: "default") |

**Response:**
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
      },
      "metadata": {
        "service_url": "https://discord-go-gin-xxxxx-uc.a.run.app",
        "image_tag": "sha256:abc123...",
        "custom": {}
      }
    }
  ],
  "errors": [
    {
      "implementation": "java-spring3",
      "phase": "contract_validation",
      "message": "3 contract tests failed",
      "details": "..."
    }
  ]
}
```

**Response Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `service_type` | string | The service type this agent tests |
| `agent_version` | string | Agent version for debugging |
| `run_id` | string | Echo of request run_id |
| `start_time` | ISO 8601 | When benchmarking started |
| `end_time` | ISO 8601 | When benchmarking completed |
| `results` | array | Per-implementation results |
| `results[].implementation` | string | Implementation name |
| `results[].status` | string | "success", "failed", "skipped" |
| `results[].contract_compliance` | float | Percentage of contract tests passed |
| `results[].cold_start` | object | Cold start measurements |
| `results[].warm_requests` | object | Warm request measurements |
| `results[].metadata` | object | Additional metadata |
| `errors` | array | Errors that occurred |

---

### Endpoint: GET /health

**Purpose:** Health check for the Agent itself.

**Response:**
```json
{
  "status": "healthy",
  "version": "1.2.0",
  "service_type": "discord-webhook"
}
```

---

### Endpoint: GET /implementations

**Purpose:** List available implementations and their status.

**Response:**
```json
{
  "service_type": "discord-webhook",
  "implementations": [
    {"name": "go-gin", "status": "active", "service_url": "https://..."},
    {"name": "rust-actix", "status": "active", "service_url": "https://..."},
    {"name": "java-spring3", "status": "disabled", "reason": "Known issue #123"}
  ]
}
```

---

## GCS State Management

The Agent uses GCS to persist state between phases, enabling recovery from failures and coordination with the Perf Manager.

### State Structure

```
gs://perf-benchmark-state/
├── runs/
│   └── {run_id}/
│       └── {service_type}/
│           ├── deployment-manifest.json    # Services deployed
│           ├── deployment-status.json      # Deployment progress
│           ├── measurement-status.json     # Measurement progress
│           └── results.json                # Final results
```

### Deployment Manifest Schema

Written by `/deploy`, read by `/measure`:

```json
{
  "run_id": "2026-01-24-abc123",
  "service_type": "discord-webhook",
  "agent_version": "1.2.0",
  "deployed_at": "2026-01-24T14:00:00Z",
  "measure_scheduled_at": "2026-01-24T14:20:00Z",
  "scheduler_job_name": "discord-measure-2026-01-24-abc123",
  "benchmark_config": {
    "cold_start_iterations": 10,
    "warm_request_count": 100,
    "warm_request_concurrency": 10
  },
  "services": [
    {
      "implementation": "go-gin",
      "service_name": "discord-go-gin-abc123-cpu1",
      "service_url": "https://discord-go-gin-abc123-cpu1-xxxxx-uc.a.run.app",
      "image": "us-central1-docker.pkg.dev/project/repo/discord-go-gin:latest",
      "dimensions": {
        "implementation": "go-gin",
        "cpu": "1",
        "memory": "512Mi",
        "startup_boost": true
      },
      "deployed_at": "2026-01-24T14:01:23Z",
      "status": "deployed"
    },
    {
      "implementation": "go-gin",
      "service_name": "discord-go-gin-abc123-cpu2",
      "service_url": "https://discord-go-gin-abc123-cpu2-xxxxx-uc.a.run.app",
      "dimensions": {
        "implementation": "go-gin",
        "cpu": "2",
        "memory": "512Mi",
        "startup_boost": true
      },
      "deployed_at": "2026-01-24T14:01:45Z",
      "status": "deployed"
    }
  ]
}
```

### Status File Schema

Updated during execution:

```json
{
  "run_id": "2026-01-24-abc123",
  "phase": "measuring",
  "started_at": "2026-01-24T14:20:00Z",
  "updated_at": "2026-01-24T14:25:00Z",
  "progress": {
    "total": 4,
    "completed": 2,
    "failed": 0
  },
  "current_service": "discord-rust-actix-abc123-cpu1",
  "errors": []
}
```

---

## Cloud Scheduler Integration

The Agent creates one-time Cloud Scheduler jobs to trigger the measurement phase.

### Creating the Scheduler Job

```go
func (a *Agent) scheduleMeasurement(runID string, delay time.Duration) error {
    ctx := context.Background()

    // Calculate execution time
    executeAt := time.Now().Add(delay)

    // Create scheduler job
    job := &schedulerpb.Job{
        Name: fmt.Sprintf("projects/%s/locations/%s/jobs/%s-measure-%s",
            a.project, a.region, a.serviceType, runID),
        Schedule: executeAt.Format("05 04 15 02 01 ?"), // One-time cron
        HttpTarget: &schedulerpb.HttpTarget{
            Uri:        fmt.Sprintf("https://%s/measure", a.agentURL),
            HttpMethod: schedulerpb.HttpMethod_POST,
            Body:       []byte(fmt.Sprintf(`{"run_id":"%s"}`, runID)),
            Headers:    map[string]string{"Content-Type": "application/json"},
            OidcToken: &schedulerpb.OidcToken{
                ServiceAccountEmail: a.serviceAccount,
            },
        },
    }

    _, err := a.schedulerClient.CreateJob(ctx, &schedulerpb.CreateJobRequest{
        Parent: fmt.Sprintf("projects/%s/locations/%s", a.project, a.region),
        Job:    job,
    })

    return err
}
```

### Cleaning Up the Scheduler Job

After measurement completes (or on cleanup):

```go
func (a *Agent) deleteSchedulerJob(runID string) error {
    ctx := context.Background()

    jobName := fmt.Sprintf("projects/%s/locations/%s/jobs/%s-measure-%s",
        a.project, a.region, a.serviceType, runID)

    return a.schedulerClient.DeleteJob(ctx, &schedulerpb.DeleteJobRequest{
        Name: jobName,
    })
}
```

### Alternative: Cloud Tasks

For more precise timing, Cloud Tasks can be used instead of Cloud Scheduler:

```go
func (a *Agent) scheduleMeasurementWithTasks(runID string, delay time.Duration) error {
    ctx := context.Background()

    task := &taskspb.Task{
        ScheduleTime: timestamppb.New(time.Now().Add(delay)),
        MessageType: &taskspb.Task_HttpRequest{
            HttpRequest: &taskspb.HttpRequest{
                Url:        fmt.Sprintf("https://%s/measure", a.agentURL),
                HttpMethod: taskspb.HttpMethod_POST,
                Body:       []byte(fmt.Sprintf(`{"run_id":"%s"}`, runID)),
                OidcToken: &taskspb.OidcToken{
                    ServiceAccountEmail: a.serviceAccount,
                },
            },
        },
    }

    _, err := a.tasksClient.CreateTask(ctx, &taskspb.CreateTaskRequest{
        Parent: fmt.Sprintf("projects/%s/locations/%s/queues/%s",
            a.project, a.region, "perf-measure-queue"),
        Task: task,
    })

    return err
}
```

---

## Implementation Guide

### Agent Structure

```
cloudrun-service-{type}/
├── agent/
│   ├── Dockerfile
│   ├── main.go                    # Entry point
│   ├── internal/
│   │   ├── api/
│   │   │   ├── handlers.go        # HTTP handlers (deploy, measure, status, cleanup)
│   │   │   └── middleware.go      # Auth, logging
│   │   ├── deploy/
│   │   │   ├── deployer.go        # Cloud Run deployment
│   │   │   └── scheduler.go       # Cloud Scheduler/Tasks integration
│   │   ├── state/
│   │   │   ├── gcs.go             # GCS state management
│   │   │   └── manifest.go        # Manifest read/write
│   │   ├── benchmark/
│   │   │   ├── executor.go        # Orchestrates benchmark
│   │   │   ├── coldstart.go       # Cold start measurement
│   │   │   └── warmrequest.go     # Warm request measurement
│   │   ├── contract/
│   │   │   ├── validator.go       # Contract test runner
│   │   │   └── testvectors.go     # Test vector loader
│   │   ├── service/
│   │   │   ├── discovery.go       # Find deployed services
│   │   │   └── scalecheck.go      # Check if at zero
│   │   └── {type-specific}/
│   │       └── ...                # Service-type-specific code
│   ├── manifest.yaml              # Registration manifest
│   └── go.mod
├── implementations/
│   └── ...
└── contract/
    ├── openapi.yaml
    └── test-vectors/
```

### Core Components

#### 1. Benchmark Executor

Orchestrates the full benchmark flow:

```go
type Executor struct {
    discovery     ServiceDiscovery
    contractTests ContractValidator
    coldStart     ColdStartMeasurer
    warmRequests  WarmRequestMeasurer
}

func (e *Executor) Run(ctx context.Context, req BenchmarkRequest) (*BenchmarkResponse, error) {
    response := &BenchmarkResponse{
        ServiceType:   "discord-webhook",
        AgentVersion:  version,
        RunID:         req.RunID,
        StartTime:     time.Now(),
        Results:       []ImplementationResult{},
        Errors:        []BenchmarkError{},
    }

    implementations := e.getImplementations(req.Implementations)

    for _, impl := range implementations {
        result, err := e.benchmarkOne(ctx, impl, req.Config)
        if err != nil {
            response.Errors = append(response.Errors, BenchmarkError{
                Implementation: impl.Name,
                Phase:          "benchmark",
                Message:        err.Error(),
            })
            continue
        }
        response.Results = append(response.Results, result)
    }

    response.EndTime = time.Now()
    return response, nil
}
```

#### 2. Cold Start Measurer

Measures time to first response when service is at zero instances:

```go
type ColdStartMeasurer struct {
    scaleChecker ScaleChecker
    requestor    ServiceRequestor  // Service-type-specific!
}

func (m *ColdStartMeasurer) Measure(ctx context.Context, impl Implementation, iterations int) (*ColdStartResult, error) {
    measurements := make([]float64, 0, iterations)

    for i := 0; i < iterations; i++ {
        // Verify service is at zero
        if err := m.waitForScaleToZero(ctx, impl); err != nil {
            return nil, fmt.Errorf("scale to zero failed: %w", err)
        }

        // Make request and measure time
        start := time.Now()
        if err := m.requestor.MakeTestRequest(ctx, impl); err != nil {
            return nil, fmt.Errorf("request failed: %w", err)
        }
        elapsed := time.Since(start)

        measurements = append(measurements, float64(elapsed.Milliseconds()))
    }

    return &ColdStartResult{
        Iterations:   iterations,
        Measurements: measurements,
        Statistics:   calculateStatistics(measurements),
    }, nil
}
```

#### 3. Service-Type-Specific Requestor

This is where service-specific knowledge lives:

**Discord Webhook:**
```go
type DiscordRequestor struct {
    privateKey ed25519.PrivateKey
}

func (r *DiscordRequestor) MakeTestRequest(ctx context.Context, impl Implementation) error {
    // Build Discord interaction payload
    payload := buildPingPayload()

    // Sign the request
    timestamp := time.Now().Unix()
    signature := r.sign(timestamp, payload)

    // Make HTTP request
    req, _ := http.NewRequestWithContext(ctx, "POST", impl.ServiceURL+"/interactions", bytes.NewReader(payload))
    req.Header.Set("X-Signature-Ed25519", hex.EncodeToString(signature))
    req.Header.Set("X-Signature-Timestamp", strconv.FormatInt(timestamp, 10))
    req.Header.Set("Content-Type", "application/json")

    resp, err := http.DefaultClient.Do(req)
    if err != nil {
        return err
    }
    defer resp.Body.Close()

    if resp.StatusCode != 200 {
        return fmt.Errorf("unexpected status: %d", resp.StatusCode)
    }
    return nil
}
```

**gRPC Unary:**
```go
type GRPCRequestor struct {
    // gRPC-specific config
}

func (r *GRPCRequestor) MakeTestRequest(ctx context.Context, impl Implementation) error {
    conn, err := grpc.DialContext(ctx, impl.ServiceURL, grpc.WithInsecure())
    if err != nil {
        return err
    }
    defer conn.Close()

    client := pb.NewBenchmarkServiceClient(conn)
    _, err = client.Ping(ctx, &pb.PingRequest{})
    return err
}
```

#### 4. Scale-to-Zero Checker

Uses Cloud Run Admin API to verify service is at zero:

```go
type ScaleChecker struct {
    runClient *run.ServicesClient
    project   string
    region    string
}

func (c *ScaleChecker) IsAtZero(ctx context.Context, serviceName string) (bool, error) {
    name := fmt.Sprintf("projects/%s/locations/%s/services/%s", c.project, c.region, serviceName)

    // Get service status
    svc, err := c.runClient.GetService(ctx, &runpb.GetServiceRequest{Name: name})
    if err != nil {
        return false, err
    }

    // Check active instances
    // Note: This requires appropriate API calls - actual implementation varies
    // You may need to use Cloud Monitoring or instance metadata
    return svc.Status.LatestReadyRevision.Scaling.MinInstanceCount == 0, nil
}

func (c *ScaleChecker) WaitForScaleToZero(ctx context.Context, serviceName string, timeout time.Duration) error {
    deadline := time.Now().Add(timeout)

    for time.Now().Before(deadline) {
        atZero, err := c.IsAtZero(ctx, serviceName)
        if err != nil {
            return err
        }
        if atZero {
            return nil
        }
        time.Sleep(30 * time.Second)
    }

    return fmt.Errorf("service did not scale to zero within %v", timeout)
}
```

#### 5. Contract Validator

Runs contract tests against the service:

```go
type ContractValidator struct {
    testVectors []TestVector
    requestor   ServiceRequestor
}

func (v *ContractValidator) Validate(ctx context.Context, impl Implementation) (*ValidationResult, error) {
    passed := 0
    failed := 0
    failures := []string{}

    for _, vector := range v.testVectors {
        err := v.runTestVector(ctx, impl, vector)
        if err != nil {
            failed++
            failures = append(failures, fmt.Sprintf("%s: %v", vector.Name, err))
        } else {
            passed++
        }
    }

    return &ValidationResult{
        TotalTests:  len(v.testVectors),
        Passed:      passed,
        Failed:      failed,
        Compliance:  float64(passed) / float64(len(v.testVectors)) * 100,
        Failures:    failures,
    }, nil
}
```

---

## Registration Manifest

Each Agent publishes a manifest to the GCS registry:

```yaml
# agent/manifest.yaml (uploaded to gs://perf-agent-registry/agents/discord-webhook.yaml)

schema_version: "1.0"
service_type: discord-webhook
enabled: true
description: "Discord interaction webhook handlers - Ed25519 signature validation and Pub/Sub publishing"

agent:
  endpoint: https://discord-perf-agent-xxxxx-uc.a.run.app
  type: cloud_run_service
  version: "1.2.0"

repository:
  url: https://github.com/org/cloudrun-service-discord
  ref: main

implementations:
  - name: go-gin
    status: active
    service_name: discord-go-gin
  - name: rust-actix
    status: active
    service_name: discord-rust-actix
  - name: python-flask
    status: active
    service_name: discord-python-flask
  - name: java-spring3
    status: disabled
    reason: "Known cold start regression - investigating"
  # ... more implementations

contract:
  path: contract/openapi.yaml
  test_vectors: contract/test-vectors/
  version: "1.0.0"

metadata:
  owner: platform-team
  contact: platform@example.com
  last_updated: 2026-01-24T14:30:00Z
```

---

## Manifest JSON Schema

For validation in CI and by the Perf Manager:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://example.com/perf-agent-manifest.schema.json",
  "title": "Perf Agent Manifest",
  "type": "object",
  "required": ["schema_version", "service_type", "enabled", "agent", "implementations"],
  "properties": {
    "schema_version": {
      "type": "string",
      "pattern": "^[0-9]+\\.[0-9]+$"
    },
    "service_type": {
      "type": "string",
      "pattern": "^[a-z][a-z0-9-]*$"
    },
    "enabled": {
      "type": "boolean"
    },
    "description": {
      "type": "string"
    },
    "agent": {
      "type": "object",
      "required": ["endpoint", "type"],
      "properties": {
        "endpoint": {
          "type": "string",
          "format": "uri"
        },
        "type": {
          "type": "string",
          "enum": ["cloud_run_service", "cloud_run_job"]
        },
        "version": {
          "type": "string"
        }
      }
    },
    "repository": {
      "type": "object",
      "properties": {
        "url": {
          "type": "string",
          "format": "uri"
        },
        "ref": {
          "type": "string"
        }
      }
    },
    "implementations": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["name", "status"],
        "properties": {
          "name": {
            "type": "string",
            "pattern": "^[a-z][a-z0-9-]*$"
          },
          "status": {
            "type": "string",
            "enum": ["active", "disabled"]
          },
          "service_name": {
            "type": "string"
          },
          "reason": {
            "type": "string"
          }
        }
      }
    },
    "metadata": {
      "type": "object",
      "properties": {
        "owner": {"type": "string"},
        "contact": {"type": "string"},
        "last_updated": {"type": "string", "format": "date-time"}
      }
    }
  }
}
```

---

## Deployment

### Dockerfile

```dockerfile
FROM golang:1.22-alpine AS builder

WORKDIR /app
COPY agent/ .
RUN go mod download
RUN CGO_ENABLED=0 go build -o /perf-agent ./cmd/agent

FROM gcr.io/distroless/static-debian12

COPY --from=builder /perf-agent /perf-agent
COPY agent/contract/ /contract/

EXPOSE 8080
ENTRYPOINT ["/perf-agent"]
```

### Terraform

```hcl
# terraform/agent.tf

resource "google_cloud_run_v2_service" "perf_agent" {
  name     = "${var.service_type}-perf-agent"
  location = var.region

  template {
    containers {
      image = "${var.artifact_registry}/${var.service_type}-perf-agent:latest"

      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }

      env {
        name  = "SERVICE_TYPE"
        value = var.service_type
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }
    }

    service_account = google_service_account.perf_agent.email
    timeout         = "1800s"  # 30 minutes for full benchmark
  }
}

# Grant Perf Manager access to invoke this Agent
resource "google_cloud_run_service_iam_member" "perf_manager_invoker" {
  service  = google_cloud_run_v2_service.perf_agent.name
  location = google_cloud_run_v2_service.perf_agent.location
  role     = "roles/run.invoker"
  member   = "serviceAccount:perf-manager@${var.project_id}.iam.gserviceaccount.com"
}

# Agent needs to invoke services under test
resource "google_service_account" "perf_agent" {
  account_id   = "${var.service_type}-perf-agent"
  display_name = "${var.service_type} Perf Agent"
}

# Grant Agent permission to invoke services
resource "google_project_iam_member" "agent_run_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.perf_agent.email}"
}

# Grant Agent permission to check service status
resource "google_project_iam_member" "agent_run_viewer" {
  project = var.project_id
  role    = "roles/run.viewer"
  member  = "serviceAccount:${google_service_account.perf_agent.email}"
}
```

### CI Pipeline - Manifest Upload

```yaml
# .github/workflows/deploy-agent.yml

name: Deploy Perf Agent

on:
  push:
    branches: [main]
    paths:
      - 'agent/**'
      - 'contract/**'

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Authenticate to GCP
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ vars.WIF_PROVIDER }}
          service_account: ${{ vars.WIF_SERVICE_ACCOUNT }}

      - name: Validate manifest schema
        run: |
          npm install -g ajv-cli
          ajv validate -s schemas/agent-manifest.schema.json -d agent/manifest.yaml

      - name: Build and push Agent image
        run: |
          gcloud builds submit agent/ \
            --tag ${{ vars.ARTIFACT_REGISTRY }}/${{ vars.SERVICE_TYPE }}-perf-agent:latest

      - name: Deploy to Cloud Run
        run: |
          gcloud run deploy ${{ vars.SERVICE_TYPE }}-perf-agent \
            --image ${{ vars.ARTIFACT_REGISTRY }}/${{ vars.SERVICE_TYPE }}-perf-agent:latest \
            --region ${{ vars.REGION }}

      - name: Upload manifest to registry
        run: |
          # Update endpoint in manifest
          ENDPOINT=$(gcloud run services describe ${{ vars.SERVICE_TYPE }}-perf-agent \
            --region ${{ vars.REGION }} --format='value(status.url)')

          yq e ".agent.endpoint = \"$ENDPOINT\"" -i agent/manifest.yaml
          yq e ".metadata.last_updated = \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"" -i agent/manifest.yaml

          gsutil cp agent/manifest.yaml gs://perf-agent-registry/agents/${{ vars.SERVICE_TYPE }}.yaml
```

---

## Error Handling

### Error Response Format

When the Agent encounters an error, include it in the response:

```json
{
  "service_type": "discord-webhook",
  "run_id": "2026-01-24-abc123",
  "results": [...],
  "errors": [
    {
      "implementation": "java-spring3",
      "phase": "scale_to_zero",
      "message": "Service did not scale to zero within 15m",
      "details": "Last active instance count: 1",
      "timestamp": "2026-01-24T14:45:00Z"
    },
    {
      "implementation": "php-laravel",
      "phase": "warm_requests",
      "message": "Connection timeout",
      "details": "10 of 100 requests timed out after 30s",
      "timestamp": "2026-01-24T14:50:00Z"
    }
  ]
}
```

### Error Phases

| Phase | Description |
|-------|-------------|
| `discovery` | Finding service URL |
| `scale_to_zero` | Waiting for service to scale down |
| `contract_validation` | Running contract tests |
| `cold_start` | Measuring cold start |
| `warm_requests` | Measuring warm requests |
| `internal` | Agent internal error |

### Partial Results

If some implementations succeed and others fail, return partial results:

- Include successful implementations in `results`
- Include failures in `errors`
- Set overall HTTP status to 200 (partial success is still success)
- Perf Manager handles aggregation

---

## Testing the Agent

### Local Testing

```bash
# Start agent locally
cd agent
go run ./cmd/agent

# In another terminal, invoke benchmark
curl -X POST http://localhost:8080/benchmark \
  -H "Content-Type: application/json" \
  -d '{
    "run_id": "test-001",
    "implementations": ["go-gin"],
    "config": {
      "cold_start_iterations": 2,
      "warm_request_count": 10,
      "warm_request_concurrency": 2
    }
  }'
```

### Integration Testing

```bash
# Deploy agent to test project
gcloud run deploy discord-perf-agent-test \
  --image gcr.io/my-project/discord-perf-agent:test \
  --region us-central1

# Invoke via authenticated request
TOKEN=$(gcloud auth print-identity-token)
curl -X POST https://discord-perf-agent-test-xxxxx-uc.a.run.app/benchmark \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"run_id": "integration-test", "implementations": [], "config": {...}}'
```

---

## Checklist for New Agents

When implementing a new Perf Agent:

- [ ] Implement `/benchmark` endpoint with standard request/response
- [ ] Implement `/health` endpoint
- [ ] Implement `/implementations` endpoint
- [ ] Create service-type-specific requestor
- [ ] Load and run contract tests from `contract/test-vectors/`
- [ ] Implement cold start measurement with scale-to-zero check
- [ ] Implement warm request measurement
- [ ] Create `manifest.yaml` with all implementations listed
- [ ] Validate manifest against JSON schema in CI
- [ ] Deploy Agent to Cloud Run
- [ ] Grant Perf Manager service account invoker permission
- [ ] Upload manifest to GCS registry
- [ ] Test end-to-end with Perf Manager

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 0.1 | 2026-01-24 | Architecture Review | Initial draft |
