# Dockerfile for running contract tests
#
# This image contains the Go test suite and can be run against
# any service implementation via the CONTRACT_TEST_TARGET env var.

FROM golang:1.25-alpine

WORKDIR /tests

# Install curl for health checks
RUN apk add --no-cache curl

# Copy go module files first for better layer caching
COPY go.mod go.sum* ./
RUN go mod download || true

# Copy test source code
COPY . .

# Default command runs all tests
CMD ["go", "test", "-v", "./..."]
