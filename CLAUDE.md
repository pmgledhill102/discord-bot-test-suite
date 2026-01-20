# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository benchmarks Cloud Run cold-start latency across multiple language/framework implementations using a Discord interactions webhook as the workload. It is NOT a production Discord bot—it's a test harness for measuring webhook handling performance.

## Architecture

**Request flow:**
1. Discord interactions webhook hits the service
2. Service validates Ed25519 signature
3. For Ping (type=1): Respond with Pong, do NOT publish to Pub/Sub
4. For Slash commands (type=2): Respond with deferred (type=5), publish sanitized message to Pub/Sub

**Testing approach:** Black-box contract tests written in Go validate service behavior by making HTTP requests to containerized services. Tests run against container images, not internal code.

**Language implementations planned:** Go/Gin, Python/Django, Python/Flask, PHP/Laravel, Ruby/Rails, C++/Drogon, Node.js/Express, Java/Spring Boot, Rust/Actix-web, C#/ASP.NET Core

## Commands

### Contract Tests
```bash
# Run all contract tests against a service
CONTRACT_TEST_TARGET=http://localhost:8080 \
PUBSUB_EMULATOR_HOST=localhost:8085 \
go test ./tests/contract/...

# Run specific test category
go test ./tests/contract/... -run TestSignature
go test ./tests/contract/... -run TestPing
go test ./tests/contract/... -run TestSlashCommand
```

### Container Testing
```bash
docker build -t service-under-test ./services/go-gin
docker-compose -f docker-compose.test.yml up -d
go test ./tests/contract/...
docker-compose -f docker-compose.test.yml down
```

### Issue Tracking (bd/beads)
```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress
bd close <id>
bd sync               # Sync with git
```

### Linting
```bash
# Install and run pre-commit hooks
pip install pre-commit
pre-commit install
pre-commit run --all-files
```

## Key Constraints

- **Sensitive data redaction required:** Never log or publish `token`, signature headers (`X-Signature-Ed25519`, `X-Signature-Timestamp`), or raw request body
- **Pub/Sub emulator:** Use per-test unique topic/subscription names for parallel test execution
- **Test public key:** Services must accept `DISCORD_PUBLIC_KEY` environment variable for signature validation
- **Test timeout:** All tests must complete within 30 seconds

## Session Completion Workflow

Work is NOT complete until `git push` succeeds:
```bash
git pull --rebase
bd sync
git push
git status  # Must show "up to date with origin"
```
