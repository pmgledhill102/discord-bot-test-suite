# Rust/Actix-web Discord webhook service
# Optimized multi-stage build with musl for static linking

# Build stage - Alpine with musl
FROM rust:1.93-alpine AS builder

# Install musl build dependencies
RUN apk add --no-cache musl-dev

WORKDIR /app

# Copy manifests first for better caching
COPY Cargo.toml ./

# Create dummy main.rs to build dependencies
RUN mkdir src && \
    echo "fn main() {}" > src/main.rs && \
    cargo build --release && \
    rm -rf src

# Copy actual source
COPY src ./src

# Build for release (touch to ensure rebuild)
RUN touch src/main.rs && cargo build --release

# Runtime stage - distroless static (minimal ~2MB base)
FROM gcr.io/distroless/static-debian12

# Copy statically linked binary from builder
COPY --from=builder /app/target/release/discord-webhook-service /server

# Expose port
EXPOSE 8080

# Run the server
ENTRYPOINT ["/server"]
