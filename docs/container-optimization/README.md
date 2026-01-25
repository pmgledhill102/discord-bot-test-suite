# Container Optimization

This document summarizes the container optimization work completed across all 19 Discord bot
benchmark services.

## Image Size Comparison

| Service              | Before Optimization | After Optimization | Reduction | Base Image Change                         |
| -------------------- | ------------------- | ------------------ | --------- | ----------------------------------------- |
| rust-actix           | 32 MB               | 4.1 MB             | -87%      | debian:bookworm-slim → distroless/static  |
| ruby-rails           | 222 MB              | 122.5 MB           | -45%      | ruby:3.4-slim → ruby:alpine               |
| python-flask         | 73 MB               | 36.8 MB            | -50%      | python:3.14-slim → distroless/python3     |
| python-django        | 77 MB               | 43.3 MB            | -44%      | python:3.14-slim → distroless/python3     |
| cpp-drogon           | 30 MB               | 18.3 MB            | -39%      | ubuntu:24.04 → distroless/cc              |
| java-micronaut       | 151 MB              | 125.5 MB           | -17%      | temurin:21-jre → distroless/java21        |
| java-quarkus         | 155 MB              | 129.7 MB           | -16%      | temurin:21-jre → distroless/java21        |
| scala-play           | 156 MB              | 141.3 MB           | -9%       | temurin:21-jre-alpine → distroless/java21 |
| go-gin               | 9 MB                | 9.6 MB             | ~0%       | scratch (already optimal)                 |
| java-spring2         | 149 MB              | 149.1 MB           | ~0%       | temurin:17-jre → distroless/java17        |
| java-spring3         | 132 MB              | 132.2 MB           | ~0%       | temurin:21-jre-alpine → distroless/java21 |
| java-spring4         | 133 MB              | 133.1 MB           | ~0%       | temurin:21-jre-alpine → distroless/java21 |
| kotlin-ktor          | 127 MB              | 127.1 MB           | ~0%       | temurin:21-jre-alpine → distroless/java21 |
| java-quarkus-native  | 31 MB               | 31.5 MB            | ~0%       | quarkus-micro-image (already optimal)     |
| csharp-aspnet        | 57 MB               | 56.7 MB            | ~0%       | aspnet:alpine → chiseled                  |
| csharp-aspnet-native | 10 MB               | 12.0 MB            | +20%      | runtime-deps:alpine → chiseled            |
| php-laravel          | 47 MB               | 47.5 MB            | ~0%       | php:alpine (no distroless for PHP)        |
| node-express         | 62 MB               | 67.0 MB            | +8%       | node:alpine → distroless/nodejs           |
| typescript-fastify   | 64 MB               | 67.8 MB            | +6%       | node:alpine → distroless/nodejs           |

**Total reduction**: ~200 MB across all services (1,497 MB → 1,297 MB)

## Cold Start Performance (Post-Optimization)

| Service              | Cold Start | Notes                        |
| -------------------- | ---------- | ---------------------------- |
| rust-actix           | 264ms      | Fastest (-45% from baseline) |
| csharp-aspnet-native | 623ms      | Native AOT                   |
| go-gin               | 662ms      | Scratch image                |
| cpp-drogon           | 433ms      | ~0% change                   |
| csharp-aspnet        | 1.40s      | -35% improvement             |
| java-quarkus-native  | 1.58s      | Native AOT                   |
| php-laravel          | 1.61s      | ~0% change                   |
| node-express         | 1.87s      | -17% improvement             |
| typescript-fastify   | 2.03s      | -36% improvement             |
| kotlin-ktor          | 2.76s      | -32% improvement             |
| python-flask         | 2.81s      | Now working                  |
| java-quarkus         | 3.76s      | -22% improvement             |
| java-micronaut       | 3.97s      | -20% improvement             |
| python-django        | 4.89s      | Now working                  |
| scala-play           | 5.33s      | Now working                  |

## Optimization Strategy

### Distroless Images

Distroless images contain only the application and its runtime dependencies, without package
managers, shells, or other OS utilities. This reduces attack surface and image size.

| Language | Distroless Image                      | Typical Savings |
| -------- | ------------------------------------- | --------------- |
| Go       | `scratch` (no OS at all)              | N/A (baseline)  |
| Rust     | `gcr.io/distroless/static-debian12`   | 80-90%          |
| C++      | `gcr.io/distroless/cc-debian12`       | 30-50%          |
| Python   | `gcr.io/distroless/python3-debian12`  | 40-50%          |
| Node.js  | `gcr.io/distroless/nodejs*-debian12`  | Varies          |
| Java     | `gcr.io/distroless/java*-debian12`    | 10-20%          |
| C#       | `mcr.microsoft.com/dotnet/*-chiseled` | 10-20%          |

### Language-Specific Optimizations

#### Go (go-gin)

- Scratch base image (0 bytes)
- Static binary with CGO_ENABLED=0
- Strip symbols: `-ldflags="-w -s"`
- Only ca-certificates copied

#### Rust (rust-actix)

- musl target for fully static binary
- distroless/static base (smallest possible)
- LTO and strip enabled in Cargo.toml

#### Python (python-flask, python-django)

- Multi-stage build with distroless runtime
- Bytecode precompilation (`compileall`)
- `MALLOC_ARENA_MAX=2` for memory efficiency

#### Node.js (node-express, typescript-fastify)

- distroless/nodejs runtime
- `MALLOC_ARENA_MAX=2` for memory efficiency
- Exec form CMD (no shell in distroless)

#### Java JVM (spring, quarkus, micronaut, ktor, scala-play)

- distroless/java runtime
- `MALLOC_ARENA_MAX=2` for memory efficiency
- Future: CDS (Class Data Sharing) for faster startup

#### Java Native (java-quarkus-native)

- Native AOT compilation via Mandrel
- quarkus-micro-image (minimal runtime)
- Already optimal at 31 MB

#### C++ (cpp-drogon)

- distroless/cc runtime
- Binary stripping
- Shared library copying from builder

#### C# (csharp-aspnet, csharp-aspnet-native)

- Microsoft chiseled images
- ReadyToRun (R2R) precompilation
- Native AOT for csharp-aspnet-native

#### Ruby (ruby-rails)

- Alpine base (no distroless for Ruby)
- Bootsnap precompilation
- Gem build artifact cleanup

#### PHP (php-laravel)

- Alpine base (no distroless for PHP)
- OPcache configuration
- Config and route caching

## Build Patterns

### Multi-Stage Build Template

```dockerfile
# Build stage
FROM <language>:<version> AS builder
WORKDIR /app
COPY . .
RUN <build commands>

# Runtime stage
FROM <distroless-image>
COPY --from=builder /app/<artifact> /<artifact>
ENTRYPOINT ["/<artifact>"]
```

### Key Principles

1. **Separate build and runtime** - Build dependencies stay in builder stage
2. **Copy only artifacts** - Don't copy source code to runtime
3. **Use exec form** - `ENTRYPOINT ["binary"]` not `ENTRYPOINT binary`
4. **Strip binaries** - Remove debug symbols where possible
5. **Prefer static linking** - Reduces runtime dependencies
