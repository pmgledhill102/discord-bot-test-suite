# Python Container Optimization

## Services

| Service       | Current Base     | Current Size | Cold Start | Target Base        | Target Size |
| ------------- | ---------------- | ------------ | ---------- | ------------------ | ----------- |
| python-flask  | python:3.14-slim | 73 MB        | N/A\*      | distroless/python3 | TBD         |
| python-django | python:3.14-slim | 77 MB        | N/A\*      | distroless/python3 | TBD         |

\*Cold start test failed (401 error)

## Current Issues

- Single-stage builds (no separation of build/runtime)
- Using python:3.14-slim (~150MB compressed base)
- No bytecode precompilation

## Optimization Tasks

### 1. Multi-stage Build with Distroless

- [ ] python-flask: Convert to multi-stage with `gcr.io/distroless/python3-debian12:nonroot`
- [ ] python-django: Convert to multi-stage with `gcr.io/distroless/python3-debian12:nonroot`

**Implementation:**

```dockerfile
# Build stage
FROM python:3.14-slim AS builder
WORKDIR /app
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/
COPY pyproject.toml .
RUN uv pip install --system --no-cache -r pyproject.toml

# Runtime stage
FROM gcr.io/distroless/python3-debian12:nonroot
WORKDIR /app
COPY --from=builder /usr/local/lib/python3.14/site-packages /usr/local/lib/python3.14/site-packages
COPY app.py .
CMD ["python", "app.py"]
```

### 2. Bytecode Precompilation

- [ ] Add `python -m compileall` in build stage

### 3. Runtime Configuration

- [ ] Add `ENV MALLOC_ARENA_MAX=2`

## Progress Log

### 2026-01-23 - Baseline

- Measured baseline sizes: flask 73 MB, django 77 MB
- Cold start tests failing (401 error - likely signature validation issue)

## Files to Modify

- `services/python-flask/Dockerfile`
- `services/python-django/Dockerfile`
