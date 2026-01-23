# Rust Container Optimization

## Services

| Service    | Current Base         | Current Size | Cold Start | Target Base       | Target Size |
| ---------- | -------------------- | ------------ | ---------- | ----------------- | ----------- |
| rust-actix | debian:bookworm-slim | 32 MB        | 477ms      | distroless/static | TBD         |

## Current State

- Using debian:bookworm-slim runtime (~30MB)
- Dynamic linking with glibc
- 477ms cold start (very fast)

## Optimization Tasks

### 1. Build with musl for Static Linking

- [ ] Switch build to `rust:alpine` with musl target
- [ ] Enable fully static binary

**Implementation:**

```dockerfile
# Build stage
FROM rust:1.93-alpine AS builder
RUN apk add --no-cache musl-dev
WORKDIR /app
COPY . .
RUN rustup target add x86_64-unknown-linux-musl
RUN cargo build --release --target x86_64-unknown-linux-musl

# Runtime stage - ultra minimal
FROM gcr.io/distroless/static-debian12
COPY --from=builder /app/target/x86_64-unknown-linux-musl/release/server /server
ENTRYPOINT ["/server"]
```

### 2. Configure Cargo.toml for Optimization

- [ ] Add strip and LTO settings

**Add to Cargo.toml:**

```toml
[profile.release]
strip = true
lto = true
codegen-units = 1
```

### 3. Fallback: Use distroless/cc

If musl has compatibility issues:

- [ ] Use `gcr.io/distroless/cc-debian12` with dynamic linking

## Progress Log

### 2026-01-23 - Baseline

- Measured baseline size: 32 MB
- Cold start: 477ms (excellent)
- Target: distroless/static (~2MB base) should significantly reduce size

## Files to Modify

- `services/rust-actix/Dockerfile`
- `services/rust-actix/Cargo.toml`
