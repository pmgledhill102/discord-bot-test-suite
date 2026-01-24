# Kotlin/Ktor Discord webhook service
# Multi-stage build with distroless runtime

# Build stage
FROM gradle:8.12-jdk21 AS builder
WORKDIR /app

# Copy gradle files first for better caching
COPY build.gradle.kts settings.gradle.kts ./
COPY gradle ./gradle

# Download dependencies (cached if build files don't change)
RUN gradle dependencies --no-daemon || true

# Copy source code
COPY src ./src

# Build fat JAR
RUN gradle buildFatJar --no-daemon

# Runtime stage - optimized distroless image
FROM gcr.io/distroless/java21-debian12
WORKDIR /app

# Copy the fat JAR
COPY --from=builder /app/build/libs/*-all.jar /app/server.jar

# Environment variable for memory optimization
ENV MALLOC_ARENA_MAX=2

EXPOSE 8080

# Run the application
ENTRYPOINT ["java", "-jar", "/app/server.jar"]
