# Contract Tests

Golden contract test suite written in Go. These tests validate service implementations via black-box HTTP testing against containerized services.

## Overview

Contract tests verify that each service implementation correctly:
1. Validates Ed25519 signatures
2. Handles Ping/Pong interactions
3. Handles Slash command interactions
4. Publishes to Pub/Sub (with sensitive data redacted)
5. Returns appropriate error responses

See [docs/CONTRACT-TESTS.md](/docs/CONTRACT-TESTS.md) for the full test specification.

## Running Tests

```bash
# Set required environment variables
export CONTRACT_TEST_TARGET=http://localhost:8080
export PUBSUB_EMULATOR_HOST=localhost:8085

# Run all tests
go test ./...

# Run specific test category
go test ./... -run TestSignature
go test ./... -run TestPing
go test ./... -run TestSlashCommand
go test ./... -run TestError

# Run with verbose output
go test -v ./...
```

## Test Structure

```
tests/contract/
├── README.md           # This file
├── go.mod              # Go module definition
├── go.sum              # Dependency checksums
├── main_test.go        # Test setup and helpers
├── signature_test.go   # Signature validation tests
├── ping_test.go        # Ping/Pong tests
├── slash_test.go       # Slash command tests
├── error_test.go       # Error handling tests
├── testdata/           # Test fixtures and payloads
└── testkeys/           # Ed25519 key pair for signing test requests
    ├── keys.go         # Key generation and signing helpers
    └── keys_test.go    # Key verification tests
```

## Prerequisites

- Go 1.21+
- Docker (for running services and Pub/Sub emulator)
- Service under test running on `CONTRACT_TEST_TARGET`
- Pub/Sub emulator running on `PUBSUB_EMULATOR_HOST`

## Test Configuration

Tests use a deterministic Ed25519 key pair for reproducible signature validation.

**Test Public Key:**
```
398803f0f03317b6dc57069dbe7820e5f6cf7d5ff43ad6219710b19b0b49c159
```

The service under test must be configured with this key:
```bash
DISCORD_PUBLIC_KEY=398803f0f03317b6dc57069dbe7820e5f6cf7d5ff43ad6219710b19b0b49c159
```

The `testkeys` package provides:
- `TestPublicKey` / `TestPublicKeyHex` - The public key for services
- `SignRequest(body)` - Signs a request body, returns signature and timestamp
- `SignRequestWithTimestamp(body, ts)` - Signs with a specific timestamp
- `ExpiredTimestamp()` - Returns a timestamp older than 5 seconds
- `InvalidSignature()` - Returns a syntactically valid but incorrect signature
