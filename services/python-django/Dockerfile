# Python/Django Discord webhook service
FROM python:3.14-slim

WORKDIR /app

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Install dependencies
COPY pyproject.toml .
RUN uv pip install --system --no-cache -r pyproject.toml

# Copy application
COPY manage.py .
COPY discord_webhook/ discord_webhook/

# Expose port
EXPOSE 8080

# Run with gunicorn for production
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "1", "--threads", "4", "discord_webhook.wsgi:application"]
