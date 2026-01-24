# Configuration Extensibility

## Multi-Dimensional Performance Testing

**Status:** Draft
**Date:** 2026-01-24

---

## Overview

The benchmark suite is designed to test performance across multiple **dimensions**, not just
language/framework variations. This document describes how the architecture supports extensible
configuration while keeping the Perf Manager completely agnostic to what is being tested.

---

## Testing Dimensions

### Current: Language/Framework

The initial focus is comparing implementations across languages and frameworks:

```text
Dimension: implementation
Values: go-gin, rust-actix, python-flask, java-spring3, ...
```

### Future: Cloud Run Configuration

Additional dimensions to investigate:

| Dimension | Values | Research Question |
|-----------|--------|-------------------|
| **CPU allocation** | 0.5, 1, 2, 4 vCPUs | How does CPU affect cold start? Is there diminishing returns? |
| **Memory allocation** | 256Mi, 512Mi, 1Gi, 2Gi | Does more memory help? Language-specific effects? |
| **Startup CPU Boost** | enabled, disabled | Which languages/frameworks benefit most? |
| **Execution environment** | gen1, gen2 | Performance differences? |
| **Concurrency** | 1, 10, 80, 250 | Impact on warm request throughput? |
| **Min instances** | 0, 1 | Cold start elimination vs cost? |

### Research Questions This Enables

1. **CPU scaling:** Does Go benefit from 4 CPUs as much as Java does for cold starts?
2. **Startup Boost effectiveness:** Is Startup Boost most beneficial for JVM languages?
3. **Memory pressure:** Do interpreted languages (Python, Ruby) need more memory?
4. **Cost optimization:** What's the minimum viable configuration per language?
5. **Diminishing returns:** At what point does more resources not help?

---

## Design Principle: Manager Agnosticism

**The Perf Manager must remain agnostic to testing dimensions.**

The Manager doesn't know or care whether the Agent is:

- Testing different implementations
- Testing the same implementation with different CPU allocations
- Testing startup boost on/off
- Testing any combination of the above

The Manager only knows:

- How to pass configuration to Agents
- How to receive results tagged with metadata
- How to aggregate and compare results

**All interpretation of what dimensions mean lives in the Agents.**

---

## Configuration Model

### Layered Configuration

```text
┌─────────────────────────────────────────────────────────────────┐
│                    PERF MANAGER CONFIG                           │
│  (What to run, how many iterations)                             │
├─────────────────────────────────────────────────────────────────┤
│  benchmark:                                                      │
│    cold_start_iterations: 10                                    │
│    warm_request_count: 100                                      │
│    warm_request_concurrency: 10                                 │
│                                                                  │
│  # Opaque to Manager - passed through to Agents                 │
│  agent_config:                                                   │
│    <anything the agent understands>                             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Passed through unchanged
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      AGENT CONFIG                                │
│  (Interpreted by Agent - Manager doesn't understand this)       │
├─────────────────────────────────────────────────────────────────┤
│  test_matrix:                                                    │
│    implementations: [go-gin, rust-actix]                        │
│    cpu_variants: [0.5, 1, 2]                                    │
│    startup_boost: [true, false]                                 │
│    memory_variants: [512Mi]                                     │
│                                                                  │
│  # Or simplified for single-dimension testing:                   │
│  implementations: [go-gin, rust-actix]                          │
│  deployment_profile: default                                     │
└─────────────────────────────────────────────────────────────────┘
```

### Request Schema (Manager → Agent)

```json
{
  "run_id": "2026-01-24-abc123",

  "benchmark_config": {
    "cold_start_iterations": 10,
    "warm_request_count": 100,
    "warm_request_concurrency": 10,
    "timeout_seconds": 1800
  },

  "agent_config": {
    // OPAQUE TO MANAGER - Agent interprets this however it wants
    // Example 1: Simple implementation testing
    "implementations": ["go-gin", "rust-actix"],
    "profile": "default"

    // Example 2: CPU scaling study
    // "implementations": ["go-gin"],
    // "test_matrix": {
    //   "cpu": ["0.5", "1", "2", "4"],
    //   "startup_boost": [true, false]
    // }

    // Example 3: Full matrix
    // "test_matrix": {
    //   "implementations": ["go-gin", "java-spring3"],
    //   "cpu": ["1", "2"],
    //   "memory": ["512Mi", "1Gi"],
    //   "startup_boost": [true]
    // }
  }
}
```

The `agent_config` section is completely opaque to the Manager. It passes it through without validation or interpretation.

### Response Schema (Agent → Manager)

Results include **dimension tags** that describe what configuration produced them:

```json
{
  "service_type": "discord-webhook",
  "run_id": "2026-01-24-abc123",
  "results": [
    {
      "implementation": "go-gin",
      "status": "success",

      "dimensions": {
        "implementation": "go-gin",
        "cpu": "1",
        "memory": "512Mi",
        "startup_boost": true,
        "execution_env": "gen2"
      },

      "cold_start": {
        "p50_ms": 145,
        "p90_ms": 180,
        "p99_ms": 220
      },
      "warm_requests": {
        "p50_ms": 3,
        "throughput_rps": 238
      }
    },
    {
      "implementation": "go-gin",
      "status": "success",

      "dimensions": {
        "implementation": "go-gin",
        "cpu": "2",
        "memory": "512Mi",
        "startup_boost": true,
        "execution_env": "gen2"
      },

      "cold_start": {
        "p50_ms": 98,
        "p90_ms": 125,
        "p99_ms": 160
      },
      "warm_requests": {
        "p50_ms": 2,
        "throughput_rps": 312
      }
    }
  ]
}
```

**Key insight:** The same implementation (`go-gin`) can appear multiple times with different dimension
values. The Manager doesn't need to understand what "cpu" or "startup_boost" mean - it just stores
and reports the data.

---

## Agent Implementation Patterns

### Pattern 1: Simple Implementation Testing (Current)

Test each implementation with a fixed deployment profile:

```go
func (a *Agent) Benchmark(req Request) Response {
    results := []Result{}

    for _, impl := range req.AgentConfig.Implementations {
        // Deploy with default profile
        deploy(impl, defaultProfile)

        // Measure
        result := measure(impl)
        result.Dimensions = map[string]string{
            "implementation": impl,
            "cpu":            defaultProfile.CPU,
            "memory":         defaultProfile.Memory,
            "startup_boost":  fmt.Sprintf("%t", defaultProfile.StartupBoost),
        }

        results = append(results, result)
    }

    return Response{Results: results}
}
```

### Pattern 2: Configuration Matrix Testing

Test implementations across multiple Cloud Run configurations:

```go
func (a *Agent) Benchmark(req Request) Response {
    results := []Result{}

    matrix := req.AgentConfig.TestMatrix
    if matrix == nil {
        // Fall back to simple testing
        return a.simpleBenchmark(req)
    }

    // Generate all combinations
    combinations := generateCombinations(matrix)

    for _, combo := range combinations {
        profile := DeploymentProfile{
            CPU:          combo["cpu"],
            Memory:       combo["memory"],
            StartupBoost: combo["startup_boost"] == "true",
        }

        for _, impl := range matrix.Implementations {
            // Deploy with this specific profile
            serviceName := fmt.Sprintf("%s-%s-%s", impl, combo["cpu"], combo["memory"])
            deploy(impl, serviceName, profile)

            // Measure
            result := measure(serviceName)
            result.Dimensions = combo
            result.Dimensions["implementation"] = impl

            results = append(results, result)

            // Cleanup (or leave deployed for next run)
            cleanup(serviceName)
        }
    }

    return Response{Results: results}
}
```

### Pattern 3: Focused Study

Test a single implementation across one dimension:

```yaml
# Agent config for CPU scaling study
agent_config:
  study_type: cpu_scaling
  implementation: go-gin
  cpu_values: ["0.5", "1", "2", "4"]
  fixed_config:
    memory: "512Mi"
    startup_boost: true
```

The Agent interprets `study_type` and knows how to run a CPU scaling study.

---

## Reporting Extensibility

### Dimension-Aware Aggregation

The Perf Manager aggregates results by dimension values:

```markdown
# Cold Start by CPU Allocation

## go-gin

| CPU | P50 | P90 | P99 | Δ from 1 CPU |
|-----|-----|-----|-----|--------------|
| 0.5 | 210ms | 280ms | 350ms | +45% |
| 1   | 145ms | 180ms | 220ms | baseline |
| 2   | 98ms | 125ms | 160ms | -32% |
| 4   | 85ms | 110ms | 140ms | -41% |

## java-spring3

| CPU | P50 | P90 | P99 | Δ from 1 CPU |
|-----|-----|-----|-----|--------------|
| 0.5 | 2400ms | 3100ms | 3800ms | +50% |
| 1   | 1600ms | 2100ms | 2600ms | baseline |
| 2   | 950ms | 1200ms | 1500ms | -41% |
| 4   | 720ms | 920ms | 1150ms | -55% |

**Insight:** Java benefits more from additional CPUs than Go (55% vs 41% improvement at 4 CPUs).
```

### Comparison Across Dimensions

```markdown
# Startup Boost Effectiveness

| Implementation | Without Boost | With Boost | Improvement |
|----------------|---------------|------------|-------------|
| go-gin         | 145ms         | 140ms      | 3%          |
| rust-actix     | 160ms         | 155ms      | 3%          |
| java-spring3   | 1600ms        | 1100ms     | 31%         |
| java-quarkus   | 800ms         | 650ms      | 19%         |
| python-flask   | 450ms         | 420ms      | 7%          |
| csharp-aspnet  | 900ms         | 700ms      | 22%         |

**Insight:** Startup Boost provides significant benefit (>20%) for JVM and .NET languages,
minimal benefit (<10%) for compiled languages (Go, Rust) and interpreted languages (Python).
```

---

## Configuration Presets

For common testing scenarios, provide preset configurations:

### Preset: Implementation Comparison (Default)

```yaml
# Compare all implementations with standard config
name: implementation-comparison
description: Compare cold start across all language/framework implementations
agent_config:
  implementations: all
  profile: default
```

### Preset: CPU Scaling Study

```yaml
name: cpu-scaling-study
description: Measure cold start impact of CPU allocation
agent_config:
  test_matrix:
    implementations: [go-gin, java-spring3, python-flask, csharp-aspnet]
    cpu: ["0.5", "1", "2", "4"]
    memory: ["512Mi"]
    startup_boost: [true]
```

### Preset: Startup Boost Analysis

```yaml
name: startup-boost-analysis
description: Measure effectiveness of Startup CPU Boost across implementations
agent_config:
  test_matrix:
    implementations: all
    cpu: ["1"]
    memory: ["512Mi"]
    startup_boost: [true, false]
```

### Preset: Memory Scaling Study

```yaml
name: memory-scaling-study
description: Measure impact of memory allocation on cold start
agent_config:
  test_matrix:
    implementations: [java-spring3, python-django, ruby-rails]
    cpu: ["1"]
    memory: ["256Mi", "512Mi", "1Gi", "2Gi"]
    startup_boost: [true]
```

### Preset: Cost Optimization

```yaml
name: cost-optimization
description: Find minimum viable configuration per implementation
agent_config:
  test_matrix:
    implementations: all
    cpu: ["0.5", "1"]
    memory: ["256Mi", "512Mi"]
    startup_boost: [false]
  acceptance_criteria:
    cold_start_p99_max_ms: 1000
```

---

## Implementation in Agents

### Deployment Profile Management

Agents need to deploy services with different configurations:

```go
type DeploymentProfile struct {
    CPU          string // "0.5", "1", "2", "4"
    Memory       string // "256Mi", "512Mi", "1Gi", "2Gi"
    StartupBoost bool
    MaxInstances int
    Concurrency  int
    ExecutionEnv string // "gen1", "gen2"
}

func (a *Agent) deployWithProfile(impl string, profile DeploymentProfile) (string, error) {
    // Generate unique service name for this configuration
    serviceName := fmt.Sprintf("%s-%s-cpu%s-mem%s-boost%t",
        a.serviceType,
        impl,
        strings.ReplaceAll(profile.CPU, ".", ""),
        strings.TrimSuffix(profile.Memory, "i"),
        profile.StartupBoost,
    )

    // Deploy via Cloud Run API or gcloud
    cmd := exec.Command("gcloud", "run", "deploy", serviceName,
        "--image", a.getImage(impl),
        "--cpu", profile.CPU,
        "--memory", profile.Memory,
        "--max-instances", "1",
        "--region", a.region,
    )

    if profile.StartupBoost {
        cmd.Args = append(cmd.Args, "--cpu-boost")
    }

    return serviceName, cmd.Run()
}
```

### Matrix Expansion

```go
func expandMatrix(matrix TestMatrix) []map[string]string {
    // Start with implementations
    results := []map[string]string{}

    for _, impl := range matrix.Implementations {
        results = append(results, map[string]string{
            "implementation": impl,
        })
    }

    // Cross product with each dimension
    if len(matrix.CPU) > 0 {
        results = crossProduct(results, "cpu", matrix.CPU)
    }
    if len(matrix.Memory) > 0 {
        results = crossProduct(results, "memory", matrix.Memory)
    }
    if len(matrix.StartupBoost) > 0 {
        boostStrings := []string{}
        for _, b := range matrix.StartupBoost {
            boostStrings = append(boostStrings, fmt.Sprintf("%t", b))
        }
        results = crossProduct(results, "startup_boost", boostStrings)
    }

    return results
}

// Example:
// Input:  implementations=[go-gin, java-spring3], cpu=[1, 2], startup_boost=[true, false]
// Output: [
//   {impl: go-gin, cpu: 1, startup_boost: true},
//   {impl: go-gin, cpu: 1, startup_boost: false},
//   {impl: go-gin, cpu: 2, startup_boost: true},
//   {impl: go-gin, cpu: 2, startup_boost: false},
//   {impl: java-spring3, cpu: 1, startup_boost: true},
//   {impl: java-spring3, cpu: 1, startup_boost: false},
//   {impl: java-spring3, cpu: 2, startup_boost: true},
//   {impl: java-spring3, cpu: 2, startup_boost: false},
// ]
```

---

## Scaling Considerations

### Matrix Explosion

A full matrix can create many combinations:

- 19 implementations × 4 CPU values × 4 memory values × 2 boost values = 608 configurations

**Mitigations:**

1. Subset of implementations for focused studies
2. Run studies separately, not all at once
3. Parallelization within Agent
4. Pre-deployed services for commonly tested configurations

### Cost Management

Each configuration requires a deployed service:

- Idle cost: $0 (scaled to zero)
- Benchmark cost: ~$0.05 per cold start measurement

Full 608-config matrix with 10 iterations each:

- 608 × 10 = 6,080 cold starts
- ~$300 in compute costs per full run

**Recommendation:** Run full matrix quarterly, focused studies weekly.

---

## Future Dimensions

Beyond Cloud Run configuration, the framework could support:

| Dimension | Values | Research Question |
|-----------|--------|-------------------|
| **Region** | us-central1, europe-west1, asia-east1 | Regional performance differences? |
| **VPC connector** | with, without | Network latency impact? |
| **Custom domain** | with, without | SSL/routing overhead? |
| **Container base image** | distroless, alpine, debian | Image size impact on cold start? |
| **Build optimization** | debug, release, size-optimized | Binary size vs performance? |

These would require Agent modifications but zero Perf Manager changes.

---

## Summary

The configuration extensibility model ensures:

1. **Manager stays agnostic** - It passes `agent_config` through without interpretation
2. **Agents interpret freely** - Each agent decides what dimensions to test
3. **Results are tagged** - Dimension metadata travels with results
4. **Reports are flexible** - Manager can group/compare by any dimension
5. **Future-proof** - New dimensions require only Agent changes

This enables the framework to evolve from "which language is fastest?" to "what's the optimal
configuration for each language?" without architectural changes.

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 0.1 | 2026-01-24 | Architecture Review | Initial draft |
