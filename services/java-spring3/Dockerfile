# Java/Spring Boot 3 Discord webhook service
# Multi-stage build with distroless runtime

# Build stage
FROM eclipse-temurin:21-jdk-alpine AS builder

WORKDIR /app

# Copy pom.xml for dependency caching
COPY pom.xml .

# Copy source code
COPY src ./src

# Download dependencies and build
# hadolint ignore=DL3018
RUN apk add --no-cache maven && \
    mvn package -DskipTests -q

# Runtime stage - optimized distroless image
FROM gcr.io/distroless/java21-debian12

WORKDIR /app

# Copy the built JAR
COPY --from=builder /app/target/*.jar app.jar

# Environment variable for memory optimization
ENV MALLOC_ARENA_MAX=2

# Expose port
EXPOSE 8080

# Run the application
ENTRYPOINT ["java", "-jar", "app.jar"]
