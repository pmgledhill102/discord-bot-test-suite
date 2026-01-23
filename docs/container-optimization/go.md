# Go Container Optimization

## Services

| Service | Current Base | Current Size | Cold Start | Target Base | Status    |
| ------- | ------------ | ------------ | ---------- | ----------- | --------- |
| go-gin  | scratch      | 9 MB         | 468ms      | scratch     | Optimized |

## Current State

Already optimized (gold standard reference implementation):

- scratch base image (0 bytes)
- Multi-stage build with Alpine builder
- Build flags: `-ldflags="-w -s"` (strip debug symbols)
- CGO disabled for static binary
- Only ca-certificates copied to runtime
- 9 MB total image size
- 468ms cold start

## Optimization Tasks

No further optimization needed. This service represents the gold standard for container optimization.

## Reference Implementation

```dockerfile
# Build stage
FROM golang:1.25-alpine AS builder

WORKDIR /app

# Install ca-certificates for HTTPS
RUN apk add --no-cache ca-certificates

# Copy go module files first for better layer caching
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build the binary
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o server .

# Runtime stage
FROM scratch

# Copy CA certificates for HTTPS
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Copy the binary
COPY --from=builder /app/server /server

# Expose port
EXPOSE 8080

# Run the server
ENTRYPOINT ["/server"]
```

## Key Patterns to Follow

1. **scratch base** - 0 bytes, contains nothing
2. **Static binary** - CGO_ENABLED=0
3. **Strip symbols** - `-ldflags="-w -s"`
4. **Layer caching** - Copy go.mod before source
5. **Minimal copies** - Only binary and ca-certificates

## Progress Log

### 2026-01-23 - Baseline

- Already using scratch image
- 9 MB total size
- 468ms cold start
- No further optimization required

## Files

- `services/go-gin/Dockerfile` - No changes needed
