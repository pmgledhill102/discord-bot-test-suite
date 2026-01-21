# Build stage: use Mandrel for GraalVM native-image compilation
FROM quay.io/quarkus/ubi-quarkus-mandrel-builder-image:jdk-21 AS builder

# Copy source code
COPY --chown=quarkus:quarkus pom.xml /app/
COPY --chown=quarkus:quarkus src /app/src/

USER quarkus
WORKDIR /app

# Install Maven (not included in Mandrel image)
RUN curl -sL https://archive.apache.org/dist/maven/maven-3/3.9.9/binaries/apache-maven-3.9.9-bin.tar.gz | tar xz -C /tmp \
    && export PATH="/tmp/apache-maven-3.9.9/bin:$PATH" \
    && mvn package -Pnative -DskipTests -Dquarkus.native.container-build=false

# Runtime stage: minimal container with only the native binary
FROM quay.io/quarkus/quarkus-micro-image:2.0

WORKDIR /work/
COPY --from=builder /app/target/*-runner /work/application

# Non-root user for security
USER 1001

EXPOSE 8080

CMD ["./application", "-Dquarkus.http.host=0.0.0.0"]
