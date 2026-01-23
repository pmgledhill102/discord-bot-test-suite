# Ruby/Rails Discord webhook service
# Multi-stage build for optimized image size

# Build stage
# Use Ruby 3.4 for pre-built native gems (grpc doesn't have Ruby 4.0 binaries yet)
# See .github/dependabot.yml for version pinning
FROM ruby:3.4-slim AS builder

WORKDIR /app

# Install gems FIRST without build tools - forces use of pre-built native gems
# This avoids compiling grpc from source (which takes 10+ minutes)
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local deployment true && \
    bundle config set --local without 'development test' && \
    bundle install --jobs 4 || \
    (echo "Pre-built gems failed, installing build tools..." && \
     apt-get update && \
     apt-get install -y --no-install-recommends build-essential libyaml-dev && \
     rm -rf /var/lib/apt/lists/* && \
     bundle install --jobs 4)

# Production stage
FROM ruby:3.4-slim

WORKDIR /app

# Install runtime dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    libyaml-0-2 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m -s /bin/bash app

# Copy gems from builder
COPY --from=builder /app/vendor/bundle /app/vendor/bundle
COPY --from=builder /usr/local/bundle/config /usr/local/bundle/config

# Configure bundler
RUN bundle config set --local deployment true && \
    bundle config set --local without 'development test'

# Copy application
COPY . .

# Set ownership
RUN chown -R app:app /app

# Switch to non-root user
USER app

# Set environment
ENV RAILS_ENV=production \
    RAILS_LOG_TO_STDOUT=true \
    BUNDLE_PATH=/app/vendor/bundle

# Expose port
EXPOSE 8080

# Run with puma
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
