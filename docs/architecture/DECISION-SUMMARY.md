# Architecture Decision Summary

## Quick Reference for Multi-Repository Restructuring

**Revision 2:** Delegated Agent Pattern

---

## The Core Design

```
┌─────────────────────────────────────────────────────────────────┐
│                        PERF MANAGER                              │
│                                                                  │
│  • Discovers agents from GCS registry                           │
│  • Invokes agents via standard API                              │
│  • Aggregates results, generates reports                        │
│  • Knows NOTHING about Discord, gRPC, REST, etc.                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                   Standard Agent API
                   (protocol-agnostic)
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
┌───────────────┐     ┌───────────────┐     ┌───────────────┐
│    DISCORD    │     │   REST CRUD   │     │     gRPC      │
│  PERF AGENT   │     │  PERF AGENT   │     │  PERF AGENT   │
│               │     │               │     │               │
│ Knows Ed25519 │     │ Knows SQL     │     │ Knows Protobuf│
│ Knows Discord │     │ Knows REST    │     │ Knows gRPC    │
│               │     │               │     │               │
│ Lives in      │     │ Lives in      │     │ Lives in      │
│ service repo  │     │ service repo  │     │ service repo  │
└───────────────┘     └───────────────┘     └───────────────┘
        │                     │                     │
        ▼                     ▼                     ▼
   19 services           19 services           19 services
```

---

## Key Numbers

| Current State | Future State |
|---------------|--------------|
| 1 service type | 5-6 service types |
| 19 implementations | ~100-120 implementations |
| 1 repository | 7 repositories |
| Benchmark tool knows Discord | Perf Manager knows nothing service-specific |

---

## 7 Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Multi-repository** | Scalability at 100+ services |
| 2 | **Delegated Agent pattern** | No service-specific code in Manager |
| 3 | **GCS-based registry** | Pluggable, no Manager changes for new types |
| 4 | **Service account auth** | Native GCP, no secrets to manage |
| 5 | **Manifest schema validation** | Catch errors early in CI |
| 6 | **Always-deployed Agents** | Only 5-6 agents, immediate availability |
| 7 | **Pre-deployed services (scaled to zero)** | Zero idle cost, true cold starts |

---

## Discovery Flow

```
                                    ┌─────────────────────────┐
                                    │   GCS Bucket            │
                                    │   perf-agent-registry   │
                                    │                         │
Service Repo CI                     │   agents/               │
deploys Agent   ──────────────────► │   ├── discord.yaml     │
uploads manifest                    │   ├── rest-crud.yaml   │
                                    │   └── grpc.yaml        │
                                    └───────────┬─────────────┘
                                                │
                                    Perf Manager reads
                                    discovers endpoints
                                                │
                                                ▼
                                    ┌─────────────────────────┐
                                    │   Invokes each Agent    │
                                    │   via standard API      │
                                    └─────────────────────────┘
```

**Adding a new service type:**
1. Create service repository with Agent
2. Deploy Agent to Cloud Run
3. Upload manifest YAML to GCS
4. Done - no Perf Manager changes needed!

---

## Agent Hosting Analysis

### The Scale-to-Zero Challenge

Cloud Run services take ~15 minutes to scale to zero after deployment. Cold start benchmarks require services at zero.

### Solution

| Component | Strategy | Why |
|-----------|----------|-----|
| **Perf Agents** (5-6) | Always deployed | Few in number, need immediate availability |
| **Services under test** (100+) | Deployed via CI, scaled to zero | Zero idle cost, already at zero when benchmark runs |
| **Perf Manager** | Cloud Run Job | Triggered on schedule, no idle cost |

### Cost Impact

| Component | Idle Cost |
|-----------|-----------|
| 6 Perf Agents | ~$30-60/month |
| 114 Services (at zero) | $0/month |
| Per benchmark run | ~$5-15 |

---

## Standard Agent Interface

**Request (Manager → Agent):**
```json
{
  "run_id": "2026-01-24-abc123",
  "implementations": ["go-gin", "rust-actix"],
  "config": {
    "cold_start_iterations": 10,
    "warm_request_count": 100
  }
}
```

**Response (Agent → Manager):**
```json
{
  "service_type": "discord-webhook",
  "results": [
    {
      "implementation": "go-gin",
      "status": "success",
      "cold_start": { "p50_ms": 145, "p99_ms": 220 },
      "warm_requests": { "p50_ms": 3, "throughput_rps": 238 }
    }
  ]
}
```

The Manager doesn't know or care what "discord-webhook" means internally.

---

## Repository Structure

```
cloudrun-perf-manager/              ← Orchestration only
├── internal/
│   ├── discovery/                  # Read GCS registry
│   ├── orchestrator/               # Invoke agents
│   └── reporter/                   # Generate reports
└── schemas/                        # Manifest validation

cloudrun-service-discord/           ← Discord services + Agent
├── agent/                          # THE PERF AGENT
│   ├── internal/
│   │   └── signing/                # Ed25519 (service-specific)
│   └── manifest.yaml               # Registration
├── implementations/
│   ├── go-gin/
│   └── ... (18 more)
└── contract/

cloudrun-service-rest-crud/         ← REST services + Agent
cloudrun-service-grpc-unary/        ← gRPC services + Agent
...
```

---

## What We Gain

1. **Zero Manager changes** for new service types
2. **Clean separation** - no leaky abstractions
3. **Service-specific logic** co-located with services
4. **Pluggable architecture** via GCS registry
5. **Cost efficiency** at scale (zero idle for 100+ services)

## What Requires Care

1. **Agent interface stability** - schema validation helps
2. **Cross-repo coordination** for interface changes
3. **Manifest correctness** - validated in CI

---

## Migration Path

1. **Phase 1:** Create Perf Manager + GCS registry
2. **Phase 2:** Migrate Discord services + create Discord Agent
3. **Phase 3:** Validate end-to-end
4. **Phase 4:** Add new service types incrementally
5. **Phase 5:** Archive monorepo

---

## Open Questions

1. **Shared utilities** - Common library for Agent implementations?
2. **Feature parity** - Must all 19 implementations exist for every type?
3. **Warm detection** - Best way to verify service is truly at zero?

---

## Documents

| Document | Purpose |
|----------|---------|
| [MULTI-REPO-PROPOSAL.md](./MULTI-REPO-PROPOSAL.md) | Full architecture + ADRs |
| [PERF-MANAGER-SPEC.md](./PERF-MANAGER-SPEC.md) | Manager specification |
| [PERF-AGENT-SPEC.md](./PERF-AGENT-SPEC.md) | Agent specification |

---

*Last updated: 2026-01-24 (Revision 2 - Delegated Agent Pattern)*
