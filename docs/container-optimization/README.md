# Container Optimization

Tracking container image optimization across all 19 Discord bot benchmark services.

**Strategy**: Prefer distroless images where available, Alpine for Ruby/PHP, Microsoft chiseled for C#.

## Per-Language Tracking

Each language has its own optimization tracking file to enable parallel work without merge conflicts:

| File                             | Services                                                                                        | Status      |
| -------------------------------- | ----------------------------------------------------------------------------------------------- | ----------- |
| [python.md](python.md)           | python-flask, python-django                                                                     | Not Started |
| [java-jvm.md](java-jvm.md)       | java-spring2, java-spring3, java-spring4, java-quarkus, java-micronaut, kotlin-ktor, scala-play | Not Started |
| [java-native.md](java-native.md) | java-quarkus-native                                                                             | Optimized   |
| [node.md](node.md)               | node-express, typescript-fastify                                                                | Not Started |
| [rust.md](rust.md)               | rust-actix                                                                                      | Not Started |
| [cpp.md](cpp.md)                 | cpp-drogon                                                                                      | Not Started |
| [csharp.md](csharp.md)           | csharp-aspnet, csharp-aspnet-native                                                             | Not Started |
| [ruby.md](ruby.md)               | ruby-rails                                                                                      | Not Started |
| [php.md](php.md)                 | php-laravel                                                                                     | Not Started |
| [go.md](go.md)                   | go-gin                                                                                          | Optimized   |

## Baseline Summary (2026-01-23)

| Service              | Current Size | Cold Start | Target Base          |
| -------------------- | ------------ | ---------- | -------------------- |
| go-gin               | 9 MB         | 468ms      | scratch (done)       |
| csharp-aspnet-native | 10 MB        | 409ms      | chiseled             |
| java-quarkus-native  | 31 MB        | 1.70s      | quarkus-micro (done) |
| cpp-drogon           | 30 MB        | 412ms      | distroless/cc        |
| rust-actix           | 32 MB        | 477ms      | distroless/static    |
| php-laravel          | 47 MB        | 1.62s      | php:alpine           |
| csharp-aspnet        | 57 MB        | 2.14s      | chiseled             |
| node-express         | 62 MB        | 2.26s      | distroless/nodejs24  |
| typescript-fastify   | 64 MB        | 3.16s      | distroless/nodejs22  |
| python-flask         | 73 MB        | N/A\*      | distroless/python3   |
| python-django        | 77 MB        | N/A\*      | distroless/python3   |
| kotlin-ktor          | 127 MB       | 4.06s      | distroless/java21    |
| java-spring3         | 132 MB       | N/A\*      | distroless/java21    |
| java-spring4         | 133 MB       | N/A\*      | distroless/java21    |
| java-spring2         | 149 MB       | N/A\*      | distroless/java17    |
| java-micronaut       | 151 MB       | 4.99s      | distroless/java21    |
| java-quarkus         | 155 MB       | 4.85s      | distroless/java21    |
| scala-play           | 156 MB       | N/A\*      | distroless/java21    |
| ruby-rails           | 222 MB       | N/A\*      | ruby:alpine          |

\*N/A = Cold start test failed (401 error in benchmark)

## Aggregation

After all language-specific optimizations are complete, run:

```bash
# Combine all per-language results into final summary
./scripts/aggregate-optimization-results.sh
```

## Verification Process

After each optimization:

1. Build: `docker build -t <service> ./services/<service>`
2. Measure: `docker images <service>`
3. Test: `CONTRACT_TEST_TARGET=http://localhost:8080 go test ./tests/contract/...`
4. Update the per-language tracking file
5. Commit and push

## Reference Implementation

go-gin demonstrates optimal patterns:

- scratch base image (9 MB)
- Multi-stage build
- Build flags: `-ldflags="-w -s"`
- 468ms cold start
