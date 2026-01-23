# Java Native Container Optimization

## Services

| Service             | Current Base            | Current Size | Cold Start | Target Base | Status    |
| ------------------- | ----------------------- | ------------ | ---------- | ----------- | --------- |
| java-quarkus-native | quarkus-micro-image:2.0 | 31 MB        | 1.70s      | -           | Optimized |

## Current State

Already optimized with:

- Native AOT compilation via Mandrel
- quarkus-micro-image (minimal runtime)
- 31 MB image size
- 1.70s cold start (fast for Java)

## Optimization Tasks

No further optimization needed. This service represents best practices for Java native compilation.

## Progress Log

### 2026-01-23 - Baseline

- Already using native AOT compilation
- Already using minimal quarkus-micro-image
- No further optimization required

## Files

- `services/java-quarkus-native/Dockerfile` - No changes needed
