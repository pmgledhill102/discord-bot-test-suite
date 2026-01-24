# Multi-Repository Architecture Proposal

## Performance Test Suite Restructuring

**Status:** Draft (Revised)
**Author:** Architecture Review
**Date:** 2026-01-24
**Revision:** 2 - Agent-based architecture

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Current State Analysis](#current-state-analysis)
3. [Proposed Architecture](#proposed-architecture)
4. [Architectural Decision Records](#architectural-decision-records)
5. [Agent Hosting: Options and Trade-offs](#agent-hosting-options-and-trade-offs)
6. [Critical Analysis: Is This the Right Approach?](#critical-analysis-is-this-the-right-approach)
7. [Migration Strategy](#migration-strategy)
8. [Risk Assessment](#risk-assessment)

---

## Executive Summary

This document proposes restructuring the current monolithic Cloud Run benchmarking repository into a multi-repository architecture with a **delegated agent pattern**:

- **1 Perf Manager repository** - Generic orchestration, result aggregation, and reporting
- **5-6 Service Type repositories** - Each containing ~20 language/framework implementations **plus a Perf Agent**

**Key architectural principle:** The Perf Manager has no knowledge of service-type-specific testing. It discovers Perf Agents via a GCS registry, invokes them through a standard interface, and collects standardized results. All service-specific testing logic lives in the Perf Agent within each service repository.

This enables:
- Adding new service types without any Perf Manager code changes
- Co-location of test logic with the services being tested
- Clean separation of orchestration from execution

---

## Current State Analysis

### What We Have Today

```
discord-bot-test-suite/
├── services/                    # 19 implementations of ONE service type
│   ├── go-gin/
│   ├── rust-actix/
│   ├── python-flask/
│   └── ... (16 more)
├── tests/
│   ├── contract/               # Go-based black-box tests
│   └── cloudrun/               # Benchmark CLI tool (knows about Discord)
├── terraform/                  # GCP infrastructure
├── scripts/                    # Build and benchmark scripts
└── .github/workflows/          # 24 CI/CD pipelines
```

### Current Metrics

| Dimension | Count |
|-----------|-------|
| Service implementations | 19 |
| Languages | 12 |
| Frameworks | 19 |
| CI/CD workflows | 24 |
| Service types | 1 (Discord webhook) |

### Current Limitations for Scaling

1. **Benchmark tool knows service specifics** - The CLI contains Discord-specific signature generation, payload structures, and validation logic
2. **Scaling means leaky abstractions** - Adding gRPC, GraphQL, etc. would require the benchmark tool to understand each protocol
3. **100+ always-deployed services** - Current "keep deployed" model doesn't scale economically
4. **Monolithic coupling** - Changes to any service type's testing require benchmark tool releases

---

## Proposed Architecture

### High-Level Design: Delegated Agent Pattern

```
┌─────────────────────────────────────────────────────────────────────┐
│                         PERF MANAGER                                 │
│                                                                      │
│  Responsibilities:                                                   │
│  • Discover Perf Agents from GCS registry                           │
│  • Invoke Agents via standard interface                             │
│  • Aggregate results from all Agents                                │
│  • Store results, generate reports, compare baselines               │
│                                                                      │
│  Does NOT know:                                                      │
│  • How to test Discord webhooks                                     │
│  • How to test gRPC services                                        │
│  • Any service-specific protocols or payloads                       │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                    ┌─────────────┴─────────────┐
                    │   STANDARD AGENT API      │
                    │   (protocol-agnostic)     │
                    │                           │
                    │   Input: which impls,     │
                    │          iterations,      │
                    │          profile          │
                    │                           │
                    │   Output: cold_start_ms,  │
                    │           warm_req_ms,    │
                    │           throughput,     │
                    │           compliance      │
                    └─────────────┬─────────────┘
                                  │
        ┌─────────────────────────┼─────────────────────────┐
        │                         │                         │
        ▼                         ▼                         ▼
┌───────────────┐         ┌───────────────┐         ┌───────────────┐
│    DISCORD    │         │   REST CRUD   │         │     gRPC      │
│  PERF AGENT   │         │  PERF AGENT   │         │  PERF AGENT   │
│               │         │               │         │               │
│ Knows:        │         │ Knows:        │         │ Knows:        │
│ • Ed25519     │         │ • REST verbs  │         │ • Protobuf    │
│ • Signatures  │         │ • CRUD ops    │         │ • gRPC calls  │
│ • Discord API │         │ • SQL setup   │         │ • Streaming   │
│               │         │               │         │               │
│ Lives in:     │         │ Lives in:     │         │ Lives in:     │
│ service repo  │         │ service repo  │         │ service repo  │
└───────┬───────┘         └───────┬───────┘         └───────┬───────┘
        │                         │                         │
        ▼                         ▼                         ▼
┌───────────────┐         ┌───────────────┐         ┌───────────────┐
│  go-gin       │         │  go-gin       │         │  go-gin       │
│  rust-actix   │         │  rust-actix   │         │  rust-actix   │
│  python-flask │         │  python-flask │         │  python-flask │
│  ... (19)     │         │  ... (19)     │         │  ... (19)     │
└───────────────┘         └───────────────┘         └───────────────┘
```

### Repository Structure

```
Organizations/Repositories:

cloudrun-perf-manager/               # Central orchestrator
├── cmd/perf-manager/                # CLI entrypoint
├── internal/
│   ├── discovery/                   # GCS registry reader
│   ├── orchestrator/                # Agent invocation
│   ├── results/                     # Aggregation & storage
│   └── reporting/                   # Report generation
├── schemas/
│   ├── agent-manifest.schema.json   # Manifest validation schema
│   └── results.schema.json          # Results format schema
├── terraform/                       # Shared infrastructure
└── docs/

cloudrun-service-discord/            # Discord service type
├── agent/                           # THE PERF AGENT
│   ├── Dockerfile
│   ├── main.go
│   ├── internal/
│   │   ├── signing/                 # Ed25519 signature generation
│   │   ├── payloads/                # Discord-specific payloads
│   │   ├── validation/              # Contract test logic
│   │   └── benchmark/               # Cold start measurement
│   └── manifest.yaml                # Agent registration manifest
├── implementations/
│   ├── go-gin/
│   ├── rust-actix/
│   └── ... (17 more)
├── contract/
│   ├── openapi.yaml                 # Discord webhook contract
│   └── test-vectors/
└── README.md

cloudrun-service-rest-crud/          # REST CRUD service type
├── agent/                           # Different Perf Agent
│   └── ...                          # Knows REST/SQL, not Discord
├── implementations/
└── contract/

# ... similar structure for other service types
```

### Discovery: GCS-Based Agent Registry

The Perf Manager discovers available Agents by reading manifests from a GCS bucket:

```
gs://perf-agent-registry/
├── agents/
│   ├── discord-webhook.yaml         # Deployed by Discord repo CI
│   ├── rest-crud.yaml               # Deployed by REST CRUD repo CI
│   ├── grpc-unary.yaml              # Deployed by gRPC repo CI
│   └── ...
└── schema/
    └── manifest.schema.json         # For validation
```

**Flow:**

1. Service repository CI builds and deploys its Perf Agent
2. Service repository CI uploads/updates its manifest to GCS
3. Perf Manager lists `gs://perf-agent-registry/agents/*.yaml`
4. Perf Manager validates each manifest against schema
5. Perf Manager invokes each Agent's endpoint
6. Results flow back through standard interface

**Benefits:**

| Aspect | Benefit |
|--------|---------|
| Adding service type | Deploy Agent + upload YAML. No Perf Manager changes. |
| Removing service type | Delete YAML file. |
| Disabling temporarily | Set `enabled: false` in manifest. |
| Versioning | GCS object versioning tracks changes. |
| Debugging | `gsutil cat gs://perf-agent-registry/agents/*.yaml` |

---

## Architectural Decision Records

### ADR-001: Multi-Repository vs Monorepo

**Status:** Accepted

**Decision:** Multi-Repository

**Rationale:** At 5-6 service types with 20 implementations each (~100+ services), a monorepo becomes unmanageable. Each service type has distinct concerns that map well to repository boundaries.

*See full analysis in Critical Analysis section.*

---

### ADR-002: Delegated Agent Pattern

**Status:** Accepted

**Context:**
The Perf Manager needs to benchmark multiple service types (Discord, REST, gRPC, etc.). Each has different protocols, payloads, and validation requirements.

**Options Considered:**

| Option | Description |
|--------|-------------|
| A. Manager knows all protocols | Manager contains Discord, gRPC, REST specific code |
| B. Plugin architecture | Manager loads plugins at runtime |
| C. Delegated Agents | Each service repo provides its own test executor |

**Decision:** Option C - Delegated Agents

**Rationale:**

1. **No leaky abstractions** - Perf Manager interface is purely about results, not test mechanics
2. **Co-location** - Test logic lives with the code it tests
3. **Independent evolution** - Agents evolve with their service type, no Manager release needed
4. **Simpler Manager** - Manager is just orchestration + reporting
5. **Natural ownership** - Service repo owns everything about that service type

**Consequences:**
- (+) Adding new service types requires zero Manager changes
- (+) Each Agent can use the most appropriate tools for its service type
- (+) Service-specific expertise stays in service repo
- (-) Duplication of some benchmark infrastructure in each Agent
- (-) Agents must conform to standard interface

---

### ADR-003: GCS-Based Agent Registry

**Status:** Accepted

**Context:**
The Perf Manager needs to discover which Agents exist and how to invoke them. Options include hardcoded configuration, GitHub API scanning, or external registry.

**Decision:** GCS bucket with YAML manifests

**Manifest Schema:**
```yaml
# gs://perf-agent-registry/agents/discord-webhook.yaml
schema_version: "1.0"
service_type: discord-webhook
enabled: true
description: "Discord interaction webhook handlers"

agent:
  endpoint: https://discord-perf-agent-xxxxx-uc.a.run.app
  type: cloud_run_service  # See ADR-004 for hosting options

  # For on-demand invocation (Cloud Run Job)
  # job_name: discord-perf-agent-job
  # type: cloud_run_job

repository:
  url: https://github.com/org/cloudrun-service-discord
  ref: main

implementations:
  - name: go-gin
    status: active
  - name: rust-actix
    status: active
  - name: java-spring3
    status: disabled  # Temporarily excluded from benchmarks
  # ...

metadata:
  owner: platform-team
  contact: platform@example.com
  last_updated: 2026-01-24T14:30:00Z
  version: "1.2.0"
```

**Schema Validation:**
- JSON Schema defines required fields and formats
- CI pipelines validate manifests before upload
- Perf Manager validates on discovery
- Invalid manifests are logged and skipped (not fatal)

**Rationale:**
- Simple, file-based discovery
- No database or API server required
- Self-service: repos manage their own manifests
- Auditable via GCS versioning
- Cheap and reliable

---

### ADR-004: Agent Hosting Strategy

**Status:** Requires Decision - See detailed analysis below

**Context:**
Perf Agents need to be available when the Perf Manager runs. With 100+ services under test, the hosting model significantly impacts cost, complexity, and benchmark accuracy.

**Key Constraint:** Cloud Run services take ~15 minutes to scale to zero after deployment. Cold start benchmarks require services to be at zero instances.

*See detailed analysis in next section.*

---

### ADR-005: Service Account Authentication

**Status:** Accepted

**Context:**
Perf Manager needs to invoke Perf Agents securely.

**Decision:** GCP Service Account with IAM

**Implementation:**
1. Perf Manager runs under a dedicated service account: `perf-manager@project.iam.gserviceaccount.com`
2. Each Perf Agent grants Cloud Run Invoker role to this service account
3. No shared secrets, API keys, or tokens

**Terraform example for Agent:**
```hcl
resource "google_cloud_run_service_iam_member" "perf_manager_invoker" {
  service  = google_cloud_run_service.perf_agent.name
  location = google_cloud_run_service.perf_agent.location
  role     = "roles/run.invoker"
  member   = "serviceAccount:perf-manager@${var.project_id}.iam.gserviceaccount.com"
}
```

**Rationale:**
- Native GCP authentication
- No secrets to manage or rotate
- Auditable via Cloud Audit Logs
- Principle of least privilege

---

### ADR-006: Manifest Schema Validation

**Status:** Accepted

**Context:**
Agent manifests in GCS need to be valid to ensure reliable discovery and invocation.

**Decision:** JSON Schema validation at multiple points

**Validation Points:**

| Point | When | Action on Failure |
|-------|------|-------------------|
| Pre-commit hook | Before commit | Block commit |
| CI pipeline | On PR/push | Fail build |
| Pre-upload | Before GCS upload | Fail deployment |
| Discovery | When Perf Manager reads | Log warning, skip agent |

**Schema Location:**
- Canonical schema in Perf Manager repo: `schemas/agent-manifest.schema.json`
- Copied/referenced by service repos for local validation

**Tooling:**
- `ajv` (Node.js) or `jsonschema` (Python) for CI validation
- Pre-commit hooks using `check-jsonschema`

---

### ADR-007: Contract Definition Ownership

**Status:** Accepted

**Context:**
Previously proposed that Perf Manager define contracts. With delegated agents, this changes.

**Decision:** Each service repository owns its contract

**Rationale:**
- Perf Manager doesn't need to understand contracts - Agents validate compliance
- Contract evolution is service-type-specific
- Co-location improves maintainability

**Contract Location:**
```
cloudrun-service-discord/
└── contract/
    ├── openapi.yaml           # The contract
    ├── test-vectors/          # Test cases
    └── README.md              # Documentation
```

The Agent uses these to validate services. Perf Manager only sees pass/fail compliance scores in results.

---

## Agent Hosting: Options and Trade-offs

This section analyzes hosting strategies for Perf Agents, given the constraint that Cloud Run services take approximately 15 minutes to scale to zero after deployment.

### The Core Challenge

```
Timeline for cold start measurement:

Deploy Service ──────────────────────────────────► Scale to Zero ────► Measure Cold Start
     │                                                   │                    │
     │◄──────────── ~15 minutes ────────────────────────►│                    │
     │              (minimum wait)                        │                    │
                                                                               │
                                                         Actual cold start ◄──┘
                                                         (what we measure)
```

For 100+ services, if we deploy on-demand and wait for scale-to-zero each time, the benchmark run becomes extremely long and the orchestration complex.

### Option A: Always-Deployed Agents (Current Pattern)

**Description:** Perf Agents are deployed once and remain running. They're available immediately when the Perf Manager needs them.

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Discord   │     │  REST CRUD  │     │    gRPC     │
│ Perf Agent  │     │ Perf Agent  │     │ Perf Agent  │
│  (running)  │     │  (running)  │     │  (running)  │
└─────────────┘     └─────────────┘     └─────────────┘
      │                   │                   │
      └───────────────────┴───────────────────┘
                          │
                    Always available
                    for invocation
```

**Manifest configuration:**
```yaml
agent:
  type: cloud_run_service
  endpoint: https://discord-perf-agent-xxxxx-uc.a.run.app
```

| Aspect | Assessment |
|--------|------------|
| **Simplicity** | ✅ Very simple. Call endpoint, get results. |
| **Latency** | ✅ Immediate response (no deployment wait). |
| **Cost at 19 services** | ✅ Acceptable (~$20-50/month for idle services). |
| **Cost at 100+ services** | ❌ Problematic (~$100-300/month for idle services). |
| **Services under test** | Note: These are the Agents, not the 100+ services being tested. Agents deploy services on-demand. |

**Scaling Analysis:**

With 5-6 Agents (one per service type), always-deployed is reasonable:
- 6 Cloud Run services with minimum instances
- Cost: ~$30-60/month idle
- Complexity: Minimal

**Verdict:** ✅ **Recommended for Agents** (not the services under test)

The Agents themselves are few in number (5-6), not 100+. Each Agent then handles deploying/benchmarking its ~20 implementations.

---

### Option B: On-Demand Agent with Long-Running Job

**Description:** Perf Manager triggers a Cloud Run Job for each Agent. The job runs until all that Agent's benchmarks complete (including 15-min scale-to-zero waits).

```
Perf Manager
     │
     ├──► Invoke Discord Agent Job ──► Deploys 19 services
     │                                 Waits 15 min
     │                                 Runs cold start tests
     │                                 Returns results
     │                                 (Job runs ~2-3 hours)
     │
     ├──► Invoke REST CRUD Agent Job ──► Similar...
     │
     └──► ...
```

**Manifest configuration:**
```yaml
agent:
  type: cloud_run_job
  job_name: discord-perf-agent-job
  region: us-central1
```

| Aspect | Assessment |
|--------|------------|
| **Cost** | ✅ Pay only when running. |
| **Simplicity** | ⚠️ Moderate. Jobs need monitoring. |
| **Total runtime** | ❌ Very long. Sequential = hours. Parallel = resource contention. |
| **Job timeout** | ⚠️ Cloud Run Jobs have 1-hour default timeout (max 24h). |
| **Parallelization** | ⚠️ Can run Agent jobs in parallel, but each Agent still has internal waits. |

**Runtime estimate (sequential Agents):**
- 6 Agents × (15 min wait + 30 min benchmarks) = ~4.5 hours minimum

**Runtime estimate (parallel Agents):**
- 45 min per Agent, but resource contention and quota limits may extend this

**Verdict:** ⚠️ **Viable but slow**

---

### Option C: Scheduled Deferred Execution

**Description:** Separate the deployment phase from the measurement phase. Deploy all services, wait for scale-to-zero, then measure.

```
Phase 1: Deploy (t=0)
┌─────────────┐
│ Deploy all  │
│ 100+ svcs   │──────────────────────────────────────────►
└─────────────┘

Phase 2: Wait (t=0 to t=15min)
                    ┌─────────────┐
                    │ Services    │
                    │ scale to 0  │
                    └─────────────┘

Phase 3: Measure (t=15min+)
                                        ┌─────────────┐
                                        │ Cold start  │
                                        │ measurements│
                                        └─────────────┘
```

**Implementation approaches:**

**C1: Single long-running job with internal phases**
```
Agent Job:
  1. Deploy all 19 implementations
  2. Sleep 15 minutes
  3. Measure cold starts for all 19
  4. Return results
```

**C2: Two-phase scheduled execution**
```
Perf Manager:
  1. Invoke Agent "deploy" endpoint
  2. Schedule measurement for T+20 minutes (Cloud Scheduler)
  3. Agent "measure" endpoint called at scheduled time
  4. Results written to GCS
  5. Perf Manager polls for completion
```

**C3: Event-driven with Pub/Sub**
```
1. Agent deploys services, publishes "ready-for-measurement" event
2. Cloud Scheduler or delayed Pub/Sub triggers measurement
3. Agent measures and publishes results
4. Perf Manager aggregates
```

| Aspect | C1: Internal phases | C2: Scheduled | C3: Event-driven |
|--------|---------------------|---------------|------------------|
| **Complexity** | Low | Medium | High |
| **Job duration** | Long (includes wait) | Short (split) | Short (split) |
| **Coordination** | Simple | Scheduler setup | Pub/Sub setup |
| **Failure handling** | Simple | Need idempotency | Need idempotency |
| **Observability** | Good | Split across jobs | Split, needs tracing |

**Verdict:** ⚠️ **C1 is simplest if job timeout allows**

---

### Option D: Hybrid - Pre-deployed Services with On-Demand Measurement

**Description:** Keep services deployed (but scaled to zero), only invoke the Agent for measurement.

```
Services: Always deployed, scaled to zero (no cost when idle)
Agent: Invoked on-demand, measures cold start, returns results
```

This is essentially the current model, but with recognition that Cloud Run's scale-to-zero means "deployed" services cost nothing when idle.

**Key insight:** The 15-minute wait is only needed after *deployment* or *last request*. If services are deployed but haven't received traffic for >15 minutes, they're already at zero.

**Workflow:**
1. Services deployed once (via CI on merge)
2. Benchmark run starts
3. Services are already at zero (deployed hours/days ago)
4. Agent measures cold start immediately
5. No 15-minute wait needed!

| Aspect | Assessment |
|--------|------------|
| **Cost** | ✅ Zero for idle services (Gen2 Cloud Run). |
| **Cold start accuracy** | ✅ True cold start (services at zero for extended time). |
| **Complexity** | ✅ Simple orchestration. |
| **Freshness** | ⚠️ Must redeploy when code changes (handled by CI). |

**Verdict:** ✅ **Recommended approach**

---

### Recommended Strategy

**For Perf Agents (5-6 total):**
- **Always-deployed Cloud Run services**
- Minimal cost for a small number of agents
- Immediate availability
- Simple invocation

**For Services Under Test (100+ total):**
- **Deployed via CI, remain deployed, scaled to zero**
- Cloud Run Gen2 has no minimum instance charge
- Services naturally at zero between benchmark runs
- Cold start measurement begins immediately

**For Benchmark Orchestration:**
- Perf Manager invokes Agent
- Agent doesn't deploy services (already deployed)
- Agent calls service endpoint, measures response time
- If service was recently active (not at zero), Agent waits or flags the measurement

**Scale-to-Zero Detection:**
```go
// Agent can check if service is at zero via Cloud Run Admin API
instances := getActiveInstances(serviceName)
if instances > 0 {
    // Service is warm - either wait or skip/flag this measurement
    log.Warn("Service not at zero, measurement may not reflect cold start")
}
```

---

### Cost Analysis

**Always-deployed Agents (recommended):**

| Component | Count | Monthly Cost (idle) |
|-----------|-------|---------------------|
| Perf Agents | 6 | ~$30-60 |
| **Total Agents** | | **~$30-60/month** |

**Services under test (deployed, scaled to zero):**

| Component | Count | Monthly Cost (idle) |
|-----------|-------|---------------------|
| Discord implementations | 19 | $0 (at zero) |
| REST CRUD implementations | 19 | $0 (at zero) |
| ... (4 more types) | 76 | $0 (at zero) |
| **Total Services** | ~114 | **$0/month (idle)** |

**Benchmark run cost (when actively testing):**
- ~114 services × 10 cold starts × ~1 second = ~19 minutes of compute
- Plus warm request testing
- Estimated: $5-15 per full benchmark run

---

### Decision Summary

| Component | Hosting Strategy | Rationale |
|-----------|------------------|-----------|
| Perf Agents | Always-deployed Cloud Run services | Few in number, need immediate availability |
| Services under test | Deployed via CI, scaled to zero | Cost-free when idle, true cold starts |
| Perf Manager | Cloud Run Job (triggered) | Runs periodically, no idle cost |

---

## Critical Analysis: Is This the Right Approach?

### Arguments FOR Delegated Agent + Multi-Repo

1. **Clean separation** - Perf Manager truly doesn't know service specifics
2. **Scalability** - New service types require zero Manager changes
3. **Ownership** - Service teams own their testing logic
4. **Flexibility** - Each Agent can use best tools for its domain

### Arguments AGAINST

1. **Duplication** - Some benchmark infrastructure duplicated per Agent
2. **Coordination** - More moving parts to synchronize
3. **Complexity** - GCS registry adds indirection

### Mitigation

- **Duplication:** Shared library/module for common benchmark utilities
- **Coordination:** Strong contracts, version pinning, CI validation
- **Complexity:** Comprehensive documentation, proven patterns

### Verdict

The delegated agent pattern is appropriate for this use case. The alternative (Perf Manager knowing all protocols) would create a monolithic, tightly-coupled system that's hard to extend.

---

## Migration Strategy

### Phase 1: Infrastructure Setup
1. Create GCS bucket for agent registry
2. Define and publish manifest schema
3. Set up Perf Manager service account
4. Create Terraform modules for common infrastructure

### Phase 2: Extract Perf Manager
1. Create `cloudrun-perf-manager` repository
2. Implement discovery from GCS registry
3. Implement standard agent invocation
4. Implement result aggregation and reporting
5. Initially, register one "fake" agent for testing

### Phase 3: Create Discord Perf Agent
1. Create `cloudrun-service-discord` repository
2. Move services from current repo
3. Implement Perf Agent with current benchmark logic
4. Deploy Agent, publish manifest to registry
5. Validate end-to-end flow

### Phase 4: Add Service Types Incrementally
1. For each new service type:
   - Create repository
   - Implement reference implementation (Go recommended)
   - Implement Perf Agent
   - Deploy and register
2. Validate with Perf Manager

### Phase 5: Deprecate Monorepo
1. Archive original repository
2. Update documentation
3. Redirect references

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Agent interface drift | Medium | High | Schema validation, versioning |
| GCS registry corruption | Low | High | Object versioning, backups |
| Complex debugging across repos | Medium | Medium | Distributed tracing, clear logs |
| Duplicate maintenance burden | Medium | Low | Shared libraries, templates |
| Scale-to-zero timing issues | Medium | Medium | Detection logic, flagged measurements |

---

## Appendices

### Appendix A: Standard Agent Interface

See [PERF-AGENT-SPEC.md](./PERF-AGENT-SPEC.md) for complete specification.

### Appendix B: Perf Manager Specification

See [PERF-MANAGER-SPEC.md](./PERF-MANAGER-SPEC.md) for complete specification.

### Appendix C: Proposed Service Types

| Service Type | Purpose | Agent Complexity |
|--------------|---------|------------------|
| Discord Webhook | Signature validation + Pub/Sub | Medium (Ed25519) |
| REST CRUD | Database CRUD operations | Medium (SQL setup) |
| gRPC Unary | Binary protocol handling | Medium (Protobuf) |
| Queue Worker | Pub/Sub consumption | Low |
| WebSocket | Persistent connections | High (stateful) |
| GraphQL | Query parsing + execution | Medium |

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 0.1 | 2026-01-24 | Architecture Review | Initial draft |
| 0.2 | 2026-01-24 | Architecture Review | Revised to delegated agent pattern, GCS registry, hosting analysis |
