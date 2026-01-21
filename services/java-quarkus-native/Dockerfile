# Java/Quarkus Native Discord webhook service
# Multi-stage build using GraalVM for native compilation

# Build stage: Compile native executable using Mandrel builder
FROM quay.io/quarkus/ubi-quarkus-mandrel-builder-image:jdk-21 AS builder

USER root
WORKDIR /app

# Install newer Maven (the microdnf version is too old)
ENV MAVEN_VERSION=3.9.9
RUN curl -fsSL https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz \
    | tar -xzC /opt && \
    ln -s /opt/apache-maven-${MAVEN_VERSION}/bin/mvn /usr/local/bin/mvn

# Copy pom.xml first for dependency caching
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Copy source
COPY src ./src

# Build native executable
RUN mvn package -Pnative -DskipTests -B \
    -Dquarkus.native.container-build=false

# Runtime stage - minimal image
FROM quay.io/quarkus/quarkus-micro-image:2.0

WORKDIR /app

# Copy the native executable
COPY --from=builder /app/target/*-runner /app/application

# Expose port
EXPOSE 8080

# Run the native application
ENTRYPOINT ["/app/application"]
