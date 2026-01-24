# Scala/Play Discord webhook service
# Multi-stage build with distroless runtime

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

# Build fat JAR using sbt-assembly (works with distroless - no shell needed)
RUN sbt assembly

# Runtime stage - optimized distroless image
FROM gcr.io/distroless/java21-debian12

WORKDIR /app

# Copy the fat JAR
COPY --from=builder /app/target/scala-3.3.7/discord-webhook-service-assembly-1.0.0.jar app.jar

# Environment variable for memory optimization
ENV MALLOC_ARENA_MAX=2

# Expose port
EXPOSE 8080

# Run the application
ENTRYPOINT ["java", "-Dplay.server.http.address=0.0.0.0", "-jar", "app.jar"]
