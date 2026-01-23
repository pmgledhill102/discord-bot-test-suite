# Java JVM Container Optimization

## Services

| Service        | Current Base          | Current Size | Cold Start | Target Base       | Target Size |
| -------------- | --------------------- | ------------ | ---------- | ----------------- | ----------- |
| java-spring2   | temurin:17-jre        | 149 MB       | N/A\*      | distroless/java17 | TBD         |
| java-spring3   | temurin:21-jre-alpine | 132 MB       | N/A\*      | distroless/java21 | TBD         |
| java-spring4   | temurin:21-jre-alpine | 133 MB       | N/A\*      | distroless/java21 | TBD         |
| java-quarkus   | temurin:21-jre        | 155 MB       | 4.85s      | distroless/java21 | TBD         |
| java-micronaut | temurin:21-jre        | 151 MB       | 4.99s      | distroless/java21 | TBD         |
| kotlin-ktor    | temurin:21-jre-alpine | 127 MB       | 4.06s      | distroless/java21 | TBD         |
| scala-play     | temurin:21-jre-alpine | 156 MB       | N/A\*      | distroless/java21 | TBD         |

\*Cold start test failed (401 error)

## Current Issues

- java-spring2, java-quarkus, java-micronaut use full JRE (not Alpine)
- No CDS (Class Data Sharing) enabled
- JVM cold starts are 4-5 seconds

## Optimization Tasks

### 1. Switch to Distroless Java Images

- [ ] java-spring2: `gcr.io/distroless/java17-debian12`
- [ ] java-spring3: `gcr.io/distroless/java21-debian12`
- [ ] java-spring4: `gcr.io/distroless/java21-debian12`
- [ ] java-quarkus: `gcr.io/distroless/java21-debian12`
- [ ] java-micronaut: `gcr.io/distroless/java21-debian12`
- [ ] kotlin-ktor: `gcr.io/distroless/java21-debian12`
- [ ] scala-play: `gcr.io/distroless/java21-debian12`

**Implementation:**

```dockerfile
# Runtime stage
FROM gcr.io/distroless/java21-debian12
COPY --from=builder /app/target/*.jar /app/app.jar
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
```

### 2. Enable CDS (Class Data Sharing)

- [ ] Add CDS archive generation at build time
- [ ] Configure runtime to use CDS

**Implementation:**

```dockerfile
# Generate CDS archive
RUN java -Xshare:dump -XX:SharedClassListFile=classlist.txt -XX:SharedArchiveFile=app.jsa -jar app.jar

# Runtime with CDS
ENTRYPOINT ["java", "-Xshare:on", "-XX:SharedArchiveFile=app.jsa", "-jar", "app.jar"]
```

### 3. Runtime Configuration

- [ ] Add `ENV MALLOC_ARENA_MAX=2` to all services

### 4. Investigation: jlink Custom Runtime

- [ ] Research jlink for minimal JRE (lower priority)

## Progress Log

### 2026-01-23 - Baseline

- Measured baseline sizes: 127-156 MB range
- JVM cold starts are 4-5 seconds (slowest of all languages)
- Priority target for optimization

## Files to Modify

- `services/java-spring2/Dockerfile`
- `services/java-spring3/Dockerfile`
- `services/java-spring4/Dockerfile`
- `services/java-quarkus/Dockerfile`
- `services/java-micronaut/Dockerfile`
- `services/kotlin-ktor/Dockerfile`
- `services/scala-play/Dockerfile`
