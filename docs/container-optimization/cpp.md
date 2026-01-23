# C++ Container Optimization

## Services

| Service    | Current Base | Current Size | Cold Start | Target Base   | Target Size |
| ---------- | ------------ | ------------ | ---------- | ------------- | ----------- |
| cpp-drogon | ubuntu:24.04 | 30 MB        | 412ms      | distroless/cc | TBD         |

## Current State

- Using ubuntu:24.04 for both build and runtime
- Dynamic linking with required shared libraries
- 412ms cold start (fastest after native AOT)

## Optimization Tasks

### 1. Switch to Distroless/cc Runtime

- [ ] Change runtime from ubuntu:24.04 to `gcr.io/distroless/cc-debian12`
- [ ] Copy required shared libraries from builder

**Implementation:**

```dockerfile
# Runtime stage
FROM gcr.io/distroless/cc-debian12

# Copy required shared libraries from builder
COPY --from=builder /usr/lib/x86_64-linux-gnu/libsodium.so* /usr/lib/x86_64-linux-gnu/
COPY --from=builder /usr/lib/x86_64-linux-gnu/libjsoncpp.so* /usr/lib/x86_64-linux-gnu/
# ... other required libs

COPY --from=builder /app/build/server /server
ENTRYPOINT ["/server"]
```

**Required runtime dependencies:**

- libsodium
- libjsoncpp
- libuuid
- zlib
- libssl
- libc-ares
- libbrotli

### 2. Strip Binary Symbols

- [ ] Add `strip --strip-all` in build stage

**Implementation:**

```dockerfile
RUN strip --strip-all /app/build/server
```

### 3. Investigation: Static Linking

- [ ] Research if Drogon can be statically linked
- [ ] Would enable distroless/static base (~2MB)

## Progress Log

### 2026-01-23 - Baseline

- Measured baseline size: 30 MB
- Cold start: 412ms (excellent - 2nd fastest)
- Main optimization: reduce runtime image from ubuntu to distroless/cc

## Files to Modify

- `services/cpp-drogon/Dockerfile`
