# Architecture Decision Summary

## Quick Reference for Multi-Repository Restructuring

---

## The Question

**Should we split this monorepo into multiple repositories as we scale from 1 service type to 5-6 service types?**

---

## The Answer

**Yes, with caveats.**

Multi-repository is the right choice for this scale (100+ implementations), but the approach requires:
1. Strong contract discipline
2. Investment in automation
3. Phased migration with validation at each step

---

## Key Numbers

| Current State | Future State |
|---------------|--------------|
| 1 service type | 5-6 service types |
| 19 implementations | ~100-120 implementations |
| 24 CI workflows | Would need ~120+ in monorepo |
| 1 repository | 7 repositories |

---

## Repository Structure Summary

```
cloudrun-perf-manager/          ← Orchestration, benchmarking, contracts
cloudrun-service-discord/       ← 19 Discord webhook implementations
cloudrun-service-rest-crud/     ← 19 REST CRUD implementations
cloudrun-service-grpc-unary/    ← 19 gRPC implementations
cloudrun-service-queue-worker/  ← 19 Pub/Sub worker implementations
cloudrun-service-websocket/     ← 19 WebSocket implementations
cloudrun-service-graphql/       ← 19 GraphQL implementations
```

---

## 5 Key Decisions Made

### 1. Multi-Repo over Monorepo
**Why:** Cognitive load, CI complexity, and independent release cycles justify the split at this scale.

### 2. Contract-First Design
**Why:** The Performance Test Manager defines contracts; service repos implement them. This decouples changes.

### 3. Standard Service Repository Structure
**Why:** Predictable `manifest.yaml` + `implementations/` structure enables automation and tooling.

### 4. Semantic Versioning for Contracts
**Why:** Allows services to upgrade on their own timeline with clear compatibility windows.

### 5. Centralized Results Storage
**Why:** Single source of truth enables cross-service-type comparisons and trend analysis.

---

## Honest Assessment

### This approach IS good for:
- Scaling to many service types
- Independent team ownership
- Focused CI pipelines
- Clean versioning

### This approach is NOT good for:
- Solo developer wanting quick iteration
- Frequent cross-cutting changes
- Simple projects that won't grow

### The hardest part will be:
- **Contract evolution** - Coordinating changes across repos
- **Initial migration** - Moving from monorepo without disruption
- **Duplication** - Keeping CI/CD patterns consistent

---

## Migration Recommendation

**Don't create all 7 repos at once.**

1. **First:** Create Manager + migrate Discord services (2 repos)
2. **Validate:** Run benchmarks, confirm workflow works
3. **Then:** Add one new service type
4. **Repeat:** Add remaining types incrementally

This validates the pattern before full commitment.

---

## Performance Test Manager: Core Capabilities

| Capability | Description |
|------------|-------------|
| **Discover** | Find services from configured Git repositories |
| **Build** | Build container images from Dockerfiles |
| **Deploy** | Deploy to Cloud Run with configurable profiles |
| **Validate** | Run contract tests against deployed services |
| **Benchmark** | Measure cold start, warm requests, scale-to-zero |
| **Report** | Generate Markdown/JSON reports with comparisons |
| **Clean** | Remove deployed resources |

---

## What We Gain

1. **Manageable complexity** at scale
2. **Independent releases** for each service type
3. **Focused testing** per repository
4. **Clear ownership** boundaries
5. **Reusable contracts** as formal specifications

## What We Lose

1. **Atomic cross-repo changes** (need coordination)
2. **Single-clone simplicity** (multiple repos to manage)
3. **Some duplication** in CI/CD patterns

---

## Next Steps (If Proceeding)

1. [ ] Review and approve this architecture
2. [ ] Create `cloudrun-perf-manager` repository
3. [ ] Define Discord webhook contract formally (OpenAPI)
4. [ ] Migrate current services to `cloudrun-service-discord`
5. [ ] Validate end-to-end workflow
6. [ ] Document contributor workflow
7. [ ] Plan next service type

---

## Open Questions for Discussion

1. **Naming convention** - Is `cloudrun-service-{type}` the right pattern?
2. **Organization** - Single GitHub org or multiple?
3. **Shared code** - Library repo for common utilities across implementations?
4. **Feature parity** - Must all 19 implementations exist for every service type?
5. **Automation** - Centralized CI/CD templates or per-repo?

---

*Full details in [MULTI-REPO-PROPOSAL.md](./MULTI-REPO-PROPOSAL.md)*
