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

# Runtime stage
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

# Copy the fat JAR from builder
COPY --from=builder /app/build/libs/*-all.jar /app/server.jar

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app/server.jar"]
