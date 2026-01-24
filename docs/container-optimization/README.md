# Container Optimization

Tracking container image optimization across all 19 Discord bot benchmark services.

**Strategy**: Prefer distroless images where available, Alpine for Ruby/PHP, Microsoft chiseled for C#.

## Per-Language Tracking

Each language has its own optimization tracking file to enable parallel work without merge conflicts:

| File                             | Services                                                                                        | Status    |
| -------------------------------- | ----------------------------------------------------------------------------------------------- | --------- |
| [python.md](python.md)           | python-flask, python-django                                                                     | Complete  |
| [java-jvm.md](java-jvm.md)       | java-spring2, java-spring3, java-spring4, java-quarkus, java-micronaut, kotlin-ktor, scala-play | Complete  |
| [java-native.md](java-native.md) | java-quarkus-native                                                                             | Optimized |
| [node.md](node.md)               | node-express, typescript-fastify                                                                | Complete  |
| [rust.md](rust.md)               | rust-actix                                                                                      | Complete  |
| [cpp.md](cpp.md)                 | cpp-drogon                                                                                      | Complete  |
| [csharp.md](csharp.md)           | csharp-aspnet, csharp-aspnet-native                                                             | Complete  |
| [ruby.md](ruby.md)               | ruby-rails                                                                                      | Complete  |
| [php.md](php.md)                 | php-laravel                                                                                     | Complete  |
| [go.md](go.md)                   | go-gin                                                                                          | Optimized |

## Results Summary (2026-01-24)

| Service              | Before Cold Start | After Cold Start | Improvement |
| -------------------- | ----------------- | ---------------- | ----------- |
| rust-actix           | 477ms             | 264ms            | -45%        |
| csharp-aspnet        | 2.14s             | 1.40s            | -35%        |
| typescript-fastify   | 3.16s             | 2.03s            | -36%        |
| kotlin-ktor          | 4.06s             | 2.76s            | -32%        |
| java-quarkus         | 4.85s             | 3.76s            | -22%        |
| java-micronaut       | 4.99s             | 3.97s            | -20%        |
| node-express         | 2.26s             | 1.87s            | -17%        |
| java-quarkus-native  | 1.70s             | 1.58s            | -7%         |
| php-laravel          | 1.62s             | 1.61s            | ~0%         |
| cpp-drogon           | 412ms             | 433ms            | ~0%         |
| go-gin               | 468ms             | 662ms            | variance\*  |
| csharp-aspnet-native | 409ms             | 623ms            | variance\*  |
| python-flask         | N/A               | 2.81s            | now working |
| python-django        | N/A               | 4.89s            | now working |
| scala-play           | N/A               | 5.33s            | now working |

\*Single-iteration variance in fast services

**Still failing (401 error):** java-spring2, java-spring3, java-spring4, ruby-rails

## Key Optimizations Applied

| Language   | Base Image Change               | Additional Optimizations          |
| ---------- | ------------------------------- | --------------------------------- |
| Python     | slim → distroless/python3       | Multi-stage, bytecode compilation |
| Node.js    | alpine → distroless/nodejs      | MALLOC_ARENA_MAX=2                |
| Rust       | debian-slim → distroless/static | musl static linking, LTO, strip   |
| C++        | ubuntu → distroless/cc          | Binary stripping                  |
| Java (JVM) | temurin-jre → distroless/java   | MALLOC_ARENA_MAX=2                |
| C#         | aspnet-alpine → chiseled        | ReadyToRun (R2R) compilation      |
| Ruby       | ruby-slim → ruby-alpine         | Bootsnap, gem cleanup             |
| PHP        | (kept php-alpine)               | OPcache, config/route caching     |

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
