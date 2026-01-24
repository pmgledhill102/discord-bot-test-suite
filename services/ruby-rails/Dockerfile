# Ruby/Rails Discord webhook service
# Multi-stage build for optimized image size

# Build stage
# Use Ruby 3.4 Alpine for smaller image size
# grpc gem has pre-built musl binaries (aarch64-linux-musl, x86_64-linux-musl)
# See .github/dependabot.yml for version pinning
FROM ruby:3.4-alpine AS builder

WORKDIR /app

# Install gems FIRST without build tools - forces use of pre-built native gems
# This avoids compiling grpc from source (which takes 10+ minutes)
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local deployment true && \
    bundle config set --local without 'development test' && \
    bundle install --jobs 4 || \
    (echo "Pre-built gems failed, installing build tools..." && \
     apk add --no-cache build-base yaml-dev && \
     bundle install --jobs 4)

# Copy application code for bootsnap precompilation
COPY . .

# Precompile bootsnap cache for faster boot times
ENV RAILS_ENV=production
RUN bundle exec bootsnap precompile app/ lib/

# Clean gem build artifacts to reduce image size
RUN rm -rf vendor/bundle/ruby/*/cache/*.gem && \
    rm -rf vendor/bundle/ruby/*/gems/*/spec && \
    rm -rf vendor/bundle/ruby/*/gems/*/test && \
    rm -rf vendor/bundle/ruby/*/gems/*/*.md && \
    rm -rf vendor/bundle/ruby/*/gems/*/*.txt && \
    rm -rf vendor/bundle/ruby/*/gems/*/CHANGELOG* && \
    rm -rf vendor/bundle/ruby/*/gems/*/README* && \
    rm -rf vendor/bundle/ruby/*/gems/*/LICENSE* && \
    rm -rf vendor/bundle/ruby/*/gems/*/.git* && \
    find vendor/bundle/ruby/*/gems -name '*.o' -delete 2>/dev/null || true && \
    find vendor/bundle/ruby/*/gems -name '*.c' -delete 2>/dev/null || true && \
    find vendor/bundle/ruby/*/gems -name '*.h' -delete 2>/dev/null || true

# Production stage
FROM ruby:3.4-alpine

WORKDIR /app

# Install runtime dependencies and create non-root user
RUN apk add --no-cache yaml tzdata && \
    adduser -D -s /bin/sh app

# Copy gems from builder
COPY --from=builder /app/vendor/bundle /app/vendor/bundle
COPY --from=builder /usr/local/bundle/config /usr/local/bundle/config

# Configure bundler
RUN bundle config set --local deployment true && \
    bundle config set --local without 'development test'

# Copy application
COPY . .

# Copy bootsnap cache from builder
COPY --from=builder /app/tmp/cache/bootsnap /app/tmp/cache/bootsnap

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
