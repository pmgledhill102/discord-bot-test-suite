# Build stage
FROM maven:3.9-eclipse-temurin-17 AS builder

WORKDIR /app

# Copy pom.xml for dependency caching
COPY pom.xml .

# Copy source code
COPY src ./src

# Download dependencies and build
RUN mvn package -DskipTests -q

# Runtime stage
FROM eclipse-temurin:17-jre

WORKDIR /app

# Copy the built JAR
COPY --from=builder /app/target/*.jar app.jar

# Run as non-root user
RUN groupadd -r appgroup && useradd -r -g appgroup appuser
USER appuser

# Expose port
EXPOSE 8080

# Run the application
ENTRYPOINT ["java", "-jar", "app.jar"]
