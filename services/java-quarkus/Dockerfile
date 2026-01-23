# Java/Quarkus Discord webhook service
# Multi-stage build with distroless runtime

# Build stage
FROM maven:3.9-eclipse-temurin-21 AS builder

WORKDIR /app

# Copy pom.xml first for dependency caching
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Copy source and build
COPY src ./src
RUN mvn package -DskipTests -B

# Runtime stage - optimized distroless image
FROM gcr.io/distroless/java21-debian12

WORKDIR /app

# Copy the built Quarkus application
COPY --from=builder /app/target/quarkus-app/lib/ ./lib/
COPY --from=builder /app/target/quarkus-app/*.jar ./
COPY --from=builder /app/target/quarkus-app/app/ ./app/
COPY --from=builder /app/target/quarkus-app/quarkus/ ./quarkus/

# Environment variable for memory optimization
ENV MALLOC_ARENA_MAX=2

# Expose port
EXPOSE 8080

# Run the application
ENTRYPOINT ["java", "-jar", "quarkus-run.jar"]
