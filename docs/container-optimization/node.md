# Node.js Container Optimization

## Services

| Service            | Current Base   | Current Size | Cold Start | Target Base         | Target Size |
| ------------------ | -------------- | ------------ | ---------- | ------------------- | ----------- |
| node-express       | node:24-alpine | 62 MB        | 2.26s      | distroless/nodejs24 | TBD         |
| typescript-fastify | node:22-alpine | 64 MB        | 3.16s      | distroless/nodejs22 | TBD         |

## Current Issues

- Using node:alpine images (~50MB base)
- Cold starts are 2-3 seconds
- Could benefit from distroless (smaller, more secure)

## Optimization Tasks

### 1. Switch to Distroless Node.js Images

- [ ] node-express: `gcr.io/distroless/nodejs24-debian12`
- [ ] typescript-fastify: `gcr.io/distroless/nodejs22-debian12`

**Implementation:**

```dockerfile
# Runtime stage
FROM gcr.io/distroless/nodejs24-debian12
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
# Must use exec form - no shell in distroless
CMD ["node", "dist/index.js"]
```

**Important**: CMD must be exec form `["node", "..."]` not shell form - distroless has no shell.

### 2. Runtime Configuration

- [ ] Add `ENV MALLOC_ARENA_MAX=2` to both services

## Progress Log

### 2026-01-23 - Baseline

- Measured baseline sizes: 62-64 MB
- Cold starts: 2.26s (express), 3.16s (fastify)
- typescript-fastify already has npm cache cleanup

## Files to Modify

- `services/node-express/Dockerfile`
- `services/typescript-fastify/Dockerfile`
