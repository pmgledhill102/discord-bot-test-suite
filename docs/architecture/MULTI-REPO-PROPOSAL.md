# Multi-Repository Architecture Proposal

## Performance Test Suite Restructuring

**Status:** Draft
**Author:** Architecture Review
**Date:** 2026-01-24

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Current State Analysis](#current-state-analysis)
3. [Proposed Architecture](#proposed-architecture)
4. [Architectural Decision Records](#architectural-decision-records)
5. [Critical Analysis: Is This the Right Approach?](#critical-analysis-is-this-the-right-approach)
6. [Performance Test Manager Specification](#performance-test-manager-specification)
7. [Migration Strategy](#migration-strategy)
8. [Risk Assessment](#risk-assessment)

---

## Executive Summary

This document proposes restructuring the current monolithic Cloud Run benchmarking repository into a multi-repository architecture consisting of:

- **1 Performance Test Manager repository** - Orchestration, benchmarking, and reporting
- **5-6 Service Type repositories** - Each containing ~20 language/framework implementations

The goal is to scale from 1 service type (Discord webhook) to 5-6 service types while maintaining testability, enabling independent evolution, and reducing coupling between the test harness and service implementations.

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
│   └── cloudrun/               # Benchmark CLI tool
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

### Current Strengths

1. **Single source of truth** - Contract tests, services, and infrastructure co-located
2. **Atomic changes** - Contract changes and service updates can be committed together
3. **Unified CI/CD** - All workflows in one place, consistent patterns
4. **Easy local development** - Clone once, test everything

### Current Limitations

1. **Scaling burden** - Adding 4-5 more service types would mean:
   - 19 implementations × 5 types = ~95 service directories
   - ~95+ CI/CD workflows in a single repository
   - Unmanageable complexity
2. **Tight coupling** - Benchmark tool changes affect all services
3. **Monolithic releases** - No independent versioning of components
4. **Long CI times** - Any change triggers extensive validation

---

## Proposed Architecture

### Repository Structure

```
Organizations/Repositories:
├── cloudrun-perf-manager/           # Performance Test Manager (orchestration)
│   ├── cmd/                         # CLI entrypoints
│   ├── internal/                    # Core benchmark logic
│   ├── contracts/                   # JSON Schema / OpenAPI definitions
│   ├── terraform/                   # Shared infrastructure
│   └── docs/                        # Specifications
│
├── cloudrun-service-discord/        # Discord webhook service implementations
│   ├── go-gin/
│   ├── rust-actix/
│   └── ... (17 more)
│
├── cloudrun-service-rest-crud/      # REST CRUD API implementations
│   ├── go-gin/
│   └── ...
│
├── cloudrun-service-grpc-unary/     # gRPC unary call implementations
│   ├── go-gin/
│   └── ...
│
├── cloudrun-service-queue-worker/   # Pub/Sub queue worker implementations
│   ├── go-gin/
│   └── ...
│
├── cloudrun-service-websocket/      # WebSocket service implementations
│   ├── go-gin/
│   └── ...
│
└── cloudrun-service-graphql/        # GraphQL API implementations
    ├── go-gin/
    └── ...
```

### Conceptual Relationships

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Performance Test Manager                          │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐   │
│  │ Orchestrator│ │  Deployer   │ │ Benchmarker │ │  Reporter   │   │
│  └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘   │
│                              │                                       │
│                    ┌─────────┴─────────┐                            │
│                    │  SERVICE CONTRACT │                            │
│                    │  (JSON Schema)    │                            │
│                    └─────────┬─────────┘                            │
└─────────────────────────────────────────────────────────────────────┘
                              │
         ┌────────────────────┼────────────────────┐
         │                    │                    │
         ▼                    ▼                    ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│ Discord Service │ │  REST CRUD Svc  │ │   gRPC Service  │
│   Repository    │ │   Repository    │ │   Repository    │
│ ┌─────────────┐ │ │ ┌─────────────┐ │ │ ┌─────────────┐ │
│ │  go-gin     │ │ │ │  go-gin     │ │ │ │  go-gin     │ │
│ │  rust-actix │ │ │ │  rust-actix │ │ │ │  rust-actix │ │
│ │  python-... │ │ │ │  python-... │ │ │ │  python-... │ │
│ │  (19 total) │ │ │ │  (19 total) │ │ │ │  (19 total) │ │
│ └─────────────┘ │ │ └─────────────┘ │ │ └─────────────┘ │
│  contract.json  │ │  contract.json  │ │  contract.json  │
│  (implements)   │ │  (implements)   │ │  (implements)   │
└─────────────────┘ └─────────────────┘ └─────────────────┘
```

---

## Architectural Decision Records

### ADR-001: Multi-Repository vs Monorepo

**Status:** Proposed

**Context:**
We need to scale from 1 service type (19 implementations) to 5-6 service types (~100+ implementations). The current monorepo structure will become unmanageable.

**Options Considered:**

| Option | Description |
|--------|-------------|
| A. Keep Monorepo | Scale within current structure using directories |
| B. Multi-Repository | Split into separate repositories per service type |
| C. Hybrid Monorepo | Use tools like Nx, Turborepo, or Pants for monorepo at scale |

**Analysis:**

| Criteria | Monorepo (A) | Multi-Repo (B) | Hybrid (C) |
|----------|--------------|----------------|------------|
| Cognitive load | High (95+ services in one view) | Low (focused repos) | Medium |
| CI/CD complexity | High (100+ workflows) | Distributed (manageable per repo) | Medium (requires tooling) |
| Independent releases | Not possible | Yes | Partially |
| Cross-repo changes | Atomic | Requires coordination | Atomic within, coordinated across |
| Discoverability | Good (single clone) | Requires documentation | Good |
| Code reuse | Easy | Requires packaging | Easy |
| Language diversity | Works | Works | Varies by tool |

**Decision:** Option B - Multi-Repository

**Rationale:**
1. **Natural service boundaries** - Each service type has distinct contracts and concerns
2. **Team scalability** - Different teams can own different service repos
3. **Focused testing** - Each repo tests only its implementations
4. **Clean versioning** - Manager and services version independently
5. **Familiar workflow** - No specialized tooling required

**Consequences:**
- (+) Clear separation of concerns
- (+) Independent release cycles
- (+) Smaller, more focused CI pipelines
- (-) Cross-repository coordination required for contract changes
- (-) Duplication of CI/CD patterns across repos
- (-) Need robust contract versioning strategy

---

### ADR-002: Contract Definition Format

**Status:** Proposed

**Context:**
The Performance Test Manager needs a formal contract that services must implement. This contract must be:
- Language-agnostic
- Versionable
- Machine-readable for validation
- Human-readable for implementers

**Options Considered:**

| Option | Format |
|--------|--------|
| A | OpenAPI 3.1 (HTTP APIs) |
| B | JSON Schema (generic) |
| C | Protocol Buffers (gRPC) |
| D | AsyncAPI (event-driven) |
| E | Custom Markdown specification |

**Decision:** Combination approach by service type

| Service Type | Primary Contract Format |
|--------------|------------------------|
| Discord Webhook | OpenAPI 3.1 + JSON Schema |
| REST CRUD | OpenAPI 3.1 |
| gRPC Unary | Protocol Buffers |
| Queue Worker | AsyncAPI 2.6 + JSON Schema |
| WebSocket | AsyncAPI 2.6 |
| GraphQL | GraphQL SDL |

**Rationale:**
- Use the natural contract format for each service type
- All formats support code generation and validation
- Semantic versioning applied to contracts

**Consequences:**
- (+) Idiomatic contracts per service type
- (+) Tooling ecosystem for each format
- (-) Multiple contract formats to maintain
- (-) Requires understanding different specifications

---

### ADR-003: Service Repository Structure Convention

**Status:** Proposed

**Context:**
Each service repository will contain ~20 implementations. We need a consistent structure that the Performance Test Manager can rely on.

**Decision:** Standardized structure

```
cloudrun-service-{type}/
├── .github/
│   └── workflows/
│       └── ci.yml                    # Unified workflow for all implementations
├── contract/
│   ├── openapi.yaml                  # Contract definition (format varies by type)
│   ├── test-vectors/                 # Canonical test cases
│   │   ├── happy-path.json
│   │   ├── error-cases.json
│   │   └── edge-cases.json
│   └── README.md                     # Contract documentation
├── implementations/
│   ├── go-gin/
│   │   ├── Dockerfile
│   │   ├── main.go
│   │   └── README.md
│   ├── rust-actix/
│   ├── python-flask/
│   └── ...
├── manifest.yaml                     # Service registry for manager
├── CONTRIBUTING.md
└── README.md
```

**manifest.yaml format:**
```yaml
service_type: discord-webhook
contract_version: 1.2.0
implementations:
  - name: go-gin
    path: implementations/go-gin
    dockerfile: Dockerfile
    build_args: {}
    supported_features: [signature-validation, pubsub-publish]
  - name: rust-actix
    path: implementations/rust-actix
    dockerfile: Dockerfile
    supported_features: [signature-validation, pubsub-publish]
```

**Rationale:**
- Consistent structure enables automation
- Manifest provides machine-readable registry
- Test vectors enable contract testing without manager dependency

**Consequences:**
- (+) Predictable structure for tooling
- (+) Self-contained testing within repo
- (-) Migration effort from current structure

---

### ADR-004: Contract Versioning Strategy

**Status:** Proposed

**Context:**
Contracts will evolve. We need a strategy that allows:
- Breaking changes with clear migration paths
- Backwards compatibility testing
- Independent evolution of manager and services

**Decision:** Semantic versioning with compatibility windows

**Version Format:** `MAJOR.MINOR.PATCH`

| Change Type | Version Bump | Example |
|-------------|--------------|---------|
| Breaking change | MAJOR | Required field added |
| New optional feature | MINOR | Optional header support |
| Bug fix/clarification | PATCH | Documentation update |

**Compatibility Policy:**
- Manager supports `CURRENT` and `CURRENT-1` major versions
- Services declare minimum supported contract version
- Deprecation notices 6 months before MAJOR bump

**Contract URL Convention:**
```
https://raw.githubusercontent.com/org/cloudrun-perf-manager/main/contracts/v2/discord-webhook.yaml
```

**Consequences:**
- (+) Clear upgrade path
- (+) Time for service repos to catch up
- (-) Complexity of maintaining multiple versions
- (-) Testing matrix grows with version support

---

### ADR-005: Benchmark Result Storage and Comparison

**Status:** Proposed

**Context:**
Benchmark results need to be stored, compared over time, and shared across repositories.

**Decision:** Centralized results in Performance Test Manager with GCS backend

**Storage Structure:**
```
gs://cloudrun-benchmark-results/
├── runs/
│   └── {run-id}/
│       ├── metadata.json
│       ├── discord-webhook/
│       │   └── results.json
│       ├── rest-crud/
│       │   └── results.json
│       └── report.md
├── baselines/
│   └── {date}/
│       └── baseline.json
└── comparisons/
    └── {date}/
        └── comparison.md
```

**Rationale:**
- Single source of truth for performance data
- Enables cross-service-type comparisons
- Historical trend analysis

**Consequences:**
- (+) Unified reporting
- (+) Trend analysis possible
- (-) GCS costs (minimal)
- (-) Single point of failure for results

---

## Critical Analysis: Is This the Right Approach?

### Arguments FOR Multi-Repository Split

#### 1. Scalability
**Strong argument.** At 5-6 service types with 20 implementations each, a monorepo would contain:
- 100+ Dockerfiles
- 100+ CI workflows
- Thousands of source files

This becomes genuinely difficult to navigate and maintain.

#### 2. Independence
**Moderate argument.** Service implementations can evolve without coordination. A Python/Flask fix doesn't require touching Rust code.

#### 3. Clear Ownership
**Strong argument for teams.** If different people/teams specialize in different service types, separate repos provide natural boundaries.

#### 4. Focused CI/CD
**Strong argument.** A change to `go-gin` in the Discord repo only triggers Discord-related tests, not all 100+ services.

### Arguments AGAINST Multi-Repository Split

#### 1. Cross-Repository Coordination Complexity
**Significant concern.** Contract changes require:
1. Update contract in Manager
2. Update all N service repositories
3. Coordinate release timing

This is genuinely harder than atomic commits in a monorepo.

**Mitigation:** Strong versioning discipline, compatibility windows, automated contract validation in CI.

#### 2. Duplication of Patterns
**Moderate concern.** Each service repo will duplicate:
- CI/CD workflow structure
- Testing infrastructure patterns
- Documentation templates

**Mitigation:** Template repository, shared CI actions, documentation generators.

#### 3. Discoverability
**Moderate concern.** New contributors must understand the multi-repo structure.

**Mitigation:** Strong README documentation, central catalog in Manager repo.

#### 4. Local Development Experience
**Minor concern.** Developers working across repos need multiple clones.

**Mitigation:** Workspace/dev container configurations, clear setup documentation.

### Alternative Considered: Enhanced Monorepo with Better Tooling

**Could we stay monorepo with better organization?**

```
discord-bot-test-suite/
├── manager/                    # Performance Test Manager
├── services/
│   ├── discord-webhook/
│   │   ├── contract/
│   │   └── implementations/
│   ├── rest-crud/
│   │   ├── contract/
│   │   └── implementations/
│   └── ...
└── infra/
```

**Pros:**
- Atomic cross-service changes
- Single clone for everything
- Unified tooling

**Cons:**
- CI/CD still complex (needs path-based filtering)
- No independent release cycles
- Cognitive overhead of large repo remains
- Git history becomes noisy

### Verdict: Multi-Repository is Appropriate BUT...

**The multi-repo approach is justified** when:
1. You're genuinely scaling to 5-6 service types
2. You want independent versioning/releases
3. Different teams will own different services

**Consider staying monorepo** if:
1. It's just you or a small team
2. Service types are highly coupled
3. Atomic cross-cutting changes are frequent

### Recommendation

**Proceed with multi-repository**, but:
1. **Start with 2 repos** - Manager + one service type (migrate Discord)
2. **Prove the pattern** before creating all 6 repos
3. **Invest heavily** in contract testing and CI templates
4. **Document the workflow** for cross-repo changes

---

## Performance Test Manager Specification

### Functional Requirements

#### FR-001: Service Discovery and Registration
- **SHALL** discover services from configured Git repositories
- **SHALL** parse `manifest.yaml` from each service repository
- **SHALL** validate service metadata against expected schema
- **SHALL** support filtering services by type, language, or framework
- **SHALL** cache service metadata with configurable TTL

#### FR-002: Container Image Management
- **SHALL** build container images from service Dockerfiles
- **SHALL** push images to Artifact Registry with consistent tagging
- **SHALL** support build arguments and multi-stage builds
- **SHALL** validate image build success before proceeding
- **MAY** support pre-built images from external registries

#### FR-003: Cloud Run Deployment
- **SHALL** deploy services to Cloud Run with configurable profiles
- **SHALL** support deployment profiles (CPU, memory, concurrency, etc.)
- **SHALL** wait for service readiness before benchmarking
- **SHALL** support parallel deployment for efficiency
- **SHALL** clean up deployed services after benchmarking

#### FR-004: Contract Validation
- **SHALL** validate deployed services against their contracts
- **SHALL** execute test vectors from contract repository
- **SHALL** report contract validation failures clearly
- **SHALL** support partial contract compliance (feature flags)

#### FR-005: Benchmark Execution
- **SHALL** measure cold start latency (scale-from-zero)
- **SHALL** measure warm request throughput
- **SHALL** measure scale-to-zero timing
- **SHALL** support configurable iteration counts
- **SHALL** calculate statistical metrics (p50, p90, p99, mean, stddev)
- **SHALL** tag measurements with service metadata

#### FR-006: Result Storage
- **SHALL** store results in GCS with structured format
- **SHALL** generate unique run identifiers
- **SHALL** preserve full measurement data for analysis
- **SHALL** support result comparison against baselines

#### FR-007: Reporting
- **SHALL** generate Markdown reports for human consumption
- **SHALL** generate JSON reports for programmatic consumption
- **SHALL** support comparison reports (before/after)
- **SHALL** generate performance ranking tables
- **SHALL** highlight regressions against baselines

#### FR-008: CI/CD Integration
- **SHALL** support execution via Cloud Run Jobs
- **SHALL** support execution from GitHub Actions
- **SHALL** provide exit codes indicating success/failure/regression
- **SHALL** support webhook notifications (optional)

### Non-Functional Requirements

#### NFR-001: Reliability
- **SHALL** handle service deployment failures gracefully
- **SHALL** retry transient failures with exponential backoff
- **SHALL** continue benchmarking other services after individual failures
- **SHALL** report all failures in final summary

#### NFR-002: Observability
- **SHALL** emit structured logs
- **SHALL** report progress during long-running operations
- **SHALL** provide detailed error context for debugging

#### NFR-003: Security
- **SHALL NOT** expose credentials in logs or reports
- **SHALL** use Workload Identity for GCP authentication
- **SHALL** validate input configurations

#### NFR-004: Performance
- **SHOULD** complete full benchmark suite within 2 hours
- **SHOULD** parallelize operations where possible
- **SHOULD** minimize GCP resource consumption

### CLI Interface Specification

```
cloudrun-perf [global-flags] <command> [command-flags]

Global Flags:
  --config <path>       Configuration file path
  --project <id>        GCP project ID
  --region <region>     GCP region (default: us-central1)
  --verbose             Enable verbose logging
  --dry-run             Show what would be done without executing

Commands:
  discover              Discover services from configured repositories
  validate              Validate services against their contracts
  benchmark             Run benchmarks
  report                Generate reports from stored results
  deploy                Deploy services without benchmarking
  cleanup               Remove deployed resources
  compare               Compare two benchmark runs

Examples:
  # Discover and list all services
  cloudrun-perf discover --format table

  # Run full benchmark suite
  cloudrun-perf benchmark --suite full

  # Benchmark specific service type
  cloudrun-perf benchmark --type discord-webhook

  # Benchmark specific implementation
  cloudrun-perf benchmark --type discord-webhook --impl go-gin

  # Compare runs
  cloudrun-perf compare --baseline run-abc123 --current run-def456

  # Generate report from last run
  cloudrun-perf report --run latest --format markdown
```

### Configuration Schema

```yaml
# cloudrun-perf.yaml

version: "1.0"

gcp:
  project_id: ${GCP_PROJECT_ID}
  region: us-central1
  artifact_registry: ${REGION}-docker.pkg.dev/${PROJECT_ID}/services

service_repositories:
  - url: https://github.com/org/cloudrun-service-discord
    ref: main
    type: discord-webhook
  - url: https://github.com/org/cloudrun-service-rest-crud
    ref: main
    type: rest-crud
  # ... more service repositories

deployment_profiles:
  default:
    cpu: "1"
    memory: "512Mi"
    max_instances: 1
    concurrency: 80
    execution_env: gen2
    startup_cpu_boost: true

  constrained:
    cpu: "0.5"
    memory: "256Mi"
    max_instances: 1
    concurrency: 40

benchmark:
  cold_start:
    iterations: 10
    scale_to_zero_timeout: 15m
  warm_requests:
    count: 100
    concurrency: 10

  # Optional: subset of services to benchmark
  filter:
    types: []          # Empty = all types
    implementations: [] # Empty = all implementations

storage:
  results_bucket: gs://cloudrun-benchmark-results
  baseline_path: baselines/latest.json

notifications:
  slack_webhook: ${SLACK_WEBHOOK_URL}
  on_regression: true
  on_completion: true
```

### Service Contract Interface

Each service type defines its contract. The Manager interacts with services through:

#### Required Endpoints (All Service Types)

```yaml
# Universal endpoints
/health:
  GET:
    description: Health check endpoint
    responses:
      200:
        description: Service is healthy

/_benchmark/ready:
  GET:
    description: Benchmark readiness check
    responses:
      200:
        description: Service is ready for benchmarking
```

#### Service-Type-Specific Contracts

**Discord Webhook:**
```yaml
/interactions:
  POST:
    description: Handle Discord interaction
    headers:
      X-Signature-Ed25519: required
      X-Signature-Timestamp: required
    request:
      $ref: "#/components/schemas/DiscordInteraction"
    responses:
      200:
        $ref: "#/components/schemas/InteractionResponse"
      401:
        description: Invalid signature
```

**REST CRUD:**
```yaml
/items:
  GET: List items
  POST: Create item
/items/{id}:
  GET: Get item
  PUT: Update item
  DELETE: Delete item
```

*Additional service types would have their own contracts.*

---

## Migration Strategy

### Phase 1: Extract Performance Test Manager
1. Create `cloudrun-perf-manager` repository
2. Move `tests/cloudrun/` content
3. Adapt to read from external service repositories
4. Publish v1.0.0

### Phase 2: Migrate Discord Webhook Services
1. Create `cloudrun-service-discord` repository
2. Move `services/*` implementations
3. Create `manifest.yaml` and contract definition
4. Validate with Manager

### Phase 3: Create New Service Types
1. Create repositories for additional service types
2. Implement contract tests using test vectors
3. Implement first reference implementation (Go recommended)
4. Gradually add other language implementations

### Phase 4: Deprecate Monorepo
1. Archive original repository
2. Update documentation references
3. Redirect traffic

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Cross-repo coordination complexity | High | Medium | Strong versioning, CI validation |
| Duplicated CI/CD maintenance | Medium | Low | Shared GitHub Actions, templates |
| Contract drift between repos | Medium | High | Automated contract validation |
| Increased onboarding complexity | Medium | Medium | Comprehensive documentation |
| Migration disruption | Medium | Medium | Phased approach, parallel operation |

---

## Appendix A: Proposed Service Types

| Service Type | Purpose | Key Benchmark Focus |
|--------------|---------|---------------------|
| Discord Webhook | Signature validation + Pub/Sub | Cold start, crypto performance |
| REST CRUD | Database CRUD operations | Connection pooling, ORM overhead |
| gRPC Unary | Binary protocol handling | Protobuf serialization |
| Queue Worker | Pub/Sub consumption | Message throughput |
| WebSocket | Persistent connections | Connection establishment |
| GraphQL | Query parsing + execution | Query complexity handling |

---

## Appendix B: Estimated Repository Sizes

| Repository | Implementations | Est. LOC | Est. Files |
|------------|-----------------|----------|------------|
| Performance Test Manager | 1 | ~8,000 | ~100 |
| Discord Webhook Services | 19 | ~6,000 | ~150 |
| REST CRUD Services | 19 | ~8,000 | ~180 |
| gRPC Services | 19 | ~7,000 | ~170 |
| Queue Worker Services | 19 | ~5,000 | ~130 |
| WebSocket Services | 19 | ~6,000 | ~150 |
| GraphQL Services | 19 | ~9,000 | ~200 |

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 0.1 | 2026-01-24 | Architecture Review | Initial draft |
