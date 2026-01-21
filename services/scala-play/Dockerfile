# Scala/Play Discord webhook service
# Multi-stage build for smaller final image

# Build stage
FROM eclipse-temurin:21-jdk AS builder

WORKDIR /app

# Install sbt
RUN apt-get update && apt-get install -y curl && \
    curl -fsSL "https://github.com/sbt/sbt/releases/download/v1.10.6/sbt-1.10.6.tgz" | tar xz -C /usr/local && \
    ln -s /usr/local/sbt/bin/sbt /usr/local/bin/sbt && \
    rm -rf /var/lib/apt/lists/*

# Copy build files first for better caching
COPY build.sbt ./
COPY project/build.properties project/plugins.sbt ./project/

# Pre-fetch dependencies (creates better layer caching)
RUN sbt update

# Copy source code
COPY app ./app
COPY conf ./conf

# Build the application
RUN sbt stage

# Runtime stage
FROM eclipse-temurin:21-jre-alpine

# Install ca-certificates and bash (required by Play startup script)
RUN apk add --no-cache ca-certificates bash

WORKDIR /app

# Copy the staged application
COPY --from=builder /app/target/universal/stage /app

# Expose port
EXPOSE 8080

# Run the server
ENTRYPOINT ["/app/bin/discord-webhook-service", "-Dplay.server.http.address=0.0.0.0"]
