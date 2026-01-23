# Python/Django Discord webhook service - Optimized build
# Multi-stage build with distroless runtime for minimal cold-start latency

# =============================================================================
# Build stage: Install dependencies and compile bytecode
# =============================================================================
FROM python:3.11-slim AS builder

WORKDIR /app

# Install uv for fast dependency installation
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Install dependencies to site-packages that will be copied to distroless
# Use --target to install to a specific directory compatible with distroless
RUN mkdir -p /install/lib/python3.11/site-packages
COPY pyproject.toml .
RUN uv pip install --no-cache --target /install/lib/python3.11/site-packages -r pyproject.toml

# Copy application source
COPY manage.py .
COPY discord_webhook/ discord_webhook/

# Compile bytecode for faster startup
# -b flag creates .pyc files alongside .py files
RUN python -m compileall -b -q /install/lib/python3.11/site-packages/ /app/

# =============================================================================
# Runtime stage: Minimal distroless image
# =============================================================================
FROM gcr.io/distroless/python3-debian12:nonroot

# Memory optimization for Python in containers
ENV MALLOC_ARENA_MAX=2
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Copy installed packages to distroless Python's site-packages
COPY --from=builder /install/lib/python3.11/site-packages /usr/lib/python3.11/

# Copy application with compiled bytecode
COPY --from=builder /app/manage.py /app/
COPY --from=builder /app/manage.pyc /app/
COPY --from=builder /app/discord_webhook/ /app/discord_webhook/

# Expose port
EXPOSE 8080

# Run with gunicorn for production
# Use Python module execution since gunicorn is installed as a package
ENTRYPOINT ["/usr/bin/python3", "-m", "gunicorn", "--bind", "0.0.0.0:8080", "--workers", "1", "--threads", "4", "discord_webhook.wsgi:application"]
