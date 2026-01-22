# Dockerfile for Cloud Run benchmark tool
# Builds the benchmark CLI and runs it as a Cloud Run Job

# Build stage
FROM golang:1.24-alpine AS builder

WORKDIR /app

# Install git for go mod download (some dependencies may need it)
RUN apk add --no-cache git

# Copy go mod files first for better layer caching
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build the benchmark tool
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /cloudrun-benchmark ./cmd/cloudrun-benchmark

# Runtime stage - use distroless for minimal attack surface
FROM gcr.io/distroless/static-debian12

# Copy the binary
COPY --from=builder /cloudrun-benchmark /cloudrun-benchmark

# Copy config files
COPY configs/ /configs/

# Set the entrypoint
ENTRYPOINT ["/cloudrun-benchmark"]

# Default command runs the benchmark in batch mode
CMD ["run", "--batch", "--config", "/configs/default.yaml"]
