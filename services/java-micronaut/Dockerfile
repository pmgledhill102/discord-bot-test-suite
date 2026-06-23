# Java/Micronaut Discord webhook service
# Multi-stage build with slim JRE runtime

# Build stage
FROM maven:3.9-eclipse-temurin-25 AS builder

WORKDIR /app

# Copy pom.xml first for dependency caching
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Copy source and build
COPY src ./src
RUN mvn package -DskipTests -B

# Runtime stage - slim JRE image
# NOTE: Micronaut 5 has a Java 25 baseline, so the runtime JRE must be 25.
# Google has not yet published a distroless java25-debian12 image; switch back
# to distroless once it ships. eclipse-temurin:25-jre (glibc/debian) keeps the
# runtime behaviour consistent with the previous distroless-debian image.
FROM eclipse-temurin:25-jre

WORKDIR /app

# Copy the built JAR
COPY --from=builder /app/target/*.jar app.jar

# Environment variable for memory optimization
ENV MALLOC_ARENA_MAX=2

# Expose port
EXPOSE 8080

# Run the application
ENTRYPOINT ["java", "-jar", "app.jar"]
