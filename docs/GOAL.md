# GOAL.md - North Star Requirements

This document is the single source-of-truth for what this repo is building.

## Goal

Benchmark Cloud Run cold-start latency across many language/framework implementations using a Discord interactions webhook as the workload.

## Request Flow

```
Discord interactions webhook
    ↓
Validate Ed25519 signature
    ↓
┌─────────────────────────────────────────┐
│  Ping (type=1)?                         │
│    → Respond with Pong (type=1)         │
│    → Do NOT publish to Pub/Sub          │
├─────────────────────────────────────────┤
│  Slash command (type=2)?                │
│    → Respond with deferred (type=5)     │
│    → Publish sanitized message to       │
│      Pub/Sub for downstream processing  │
└─────────────────────────────────────────┘
```

## Key Fixed Decisions

1. **Ping/Pong**: Support Ping (type=1) → Pong (type=1). Do NOT publish Ping interactions to Pub/Sub.
2. **Slash commands**: Support Slash command (type=2) → deferred response (type=5, non-ephemeral). Publish sanitized payload to Pub/Sub.
3. **Pub/Sub emulator**: Supported for local development and testing. Use per-test unique topic/subscription names to enable parallel test execution.
4. **Sensitive data redaction**: Redact the following from logs and Pub/Sub messages:
   - `token`
   - Signature material (`X-Signature-Ed25519`, `X-Signature-Timestamp`)
   - Raw request body
5. **Contract tests**: Golden contract test suite written in Go. Black-box container testing—tests run against the container image, not internal code.
6. **Version policy**: Use modern but not bleeding-edge versions. Prioritize stability over newest features.
7. **Phased rollout**:
   - Phase 1: Local-only (emulator, contract tests)
   - Phase 2: Cloud Run + Cloud Logging for one reference service
   - Phase 3: Roll out remaining language implementations

## Language/Framework Matrix

| Language | Framework    | Status  |
|----------|--------------|---------|
| Go       | Gin          | Planned |
| Python   | Django       | Planned |
| Python   | Flask        | Planned |
| PHP      | Laravel      | Planned |
| Ruby     | Rails        | Planned |
| C++      | Drogon       | Planned |
| Node.js  | Express      | Planned |
| Java     | Spring Boot  | Planned |
| Rust     | Actix-web    | Planned |
| C#       | ASP.NET Core | Planned |

## Acceptance Criteria

### MVP
- [ ] At least one service (Go/Gin) passes all contract tests locally
- [ ] Pub/Sub emulator integration works end-to-end
- [ ] CI pipeline runs contract tests on every PR
- [ ] Sensitive fields are never logged or published

### Full Build
- [ ] All language/framework implementations pass contract tests
- [ ] Cloud Run deployment automated for all services
- [ ] Cold-start metrics collected via Cloud Logging
- [ ] Benchmarking dashboard or report available

## Non-Goals

- **Production Discord bot**: This is a benchmarking tool, not a real bot.
- **Slash command business logic**: Downstream processing is out of scope; we only measure webhook handling.
- **Multi-region deployment**: Single region is sufficient for benchmarking.
- **High availability**: No SLO requirements; this is a test harness.
- **User-facing UI**: No web interface needed.
- **Authentication/authorization beyond signature validation**: Discord signature verification is the only auth requirement.
