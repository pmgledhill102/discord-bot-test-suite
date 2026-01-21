# Performance Benchmark Results (Full)

Generated: 2026-01-21 12:35:10

## Summary

This benchmark tests each service with two separate cold-start scenarios:

1. **Ping Test**: Container starts, health check, ping latency measured, container killed
2. **Interaction Test**: Container starts (with Pub/Sub), slash command sent, Pub/Sub message verified, container killed

## Ping Test Results

| Service            | Startup | Ping Latency | Memory   | Image Size |
| ------------------ | ------- | ------------ | -------- | ---------- |
| cpp-drogon         | 0.282s  | 28.75ms      | 12.9 MB  | 102.9 MB   |
| rust-actix         | 0.284s  | 28.67ms      | 15.5 MB  | 107.0 MB   |
| go-gin             | 0.305s  | 30.00ms      | 27.1 MB  | 25.1 MB    |
| php-laravel        | 0.379s  | 46.16ms      | 56.1 MB  | 128.6 MB   |
| csharp-aspnet      | 0.450s  | 31.26ms      | 69.8 MB  | 130.6 MB   |
| typescript-fastify | 0.530s  | 31.10ms      | 53.5 MB  | 190.0 MB   |
| python-flask       | 0.631s  | 31.01ms      | 86.0 MB  | 189.1 MB   |
| python-django      | 0.632s  | 29.87ms      | 76.6 MB  | 213.6 MB   |
| node-express       | 0.642s  | 30.56ms      | 108.4 MB | 202.6 MB   |
| kotlin-ktor        | 0.718s  | 32.91ms      | 129.2 MB | 257.3 MB   |
| ruby-rails         | 1.311s  | 34.84ms      | 87.8 MB  | 448.0 MB   |
| java-spring2       | 1.521s  | 31.84ms      | 208.0 MB | 340.4 MB   |
| java-spring        | 1.647s  | 31.02ms      | 182.4 MB | 265.1 MB   |
| scala-play         | 1.891s  | 35.13ms      | 203.7 MB | 296.8 MB   |

## Interaction Test Results (with Pub/Sub)

| Service            | Startup | Interaction Latency | Pub/Sub | Memory   |
| ------------------ | ------- | ------------------- | ------- | -------- |
| cpp-drogon         | 0.163s  | 31.60ms             | 100%    | 2.5 MB   |
| go-gin             | 0.168s  | 33.11ms             | 100%    | 8.4 MB   |
| rust-actix         | 0.283s  | 30.18ms             | 100%    | 4.8 MB   |
| typescript-fastify | 0.398s  | 77.52ms             | 100%    | 82.0 MB  |
| php-laravel        | 0.400s  | 61.80ms             | 100%    | 57.7 MB  |
| csharp-aspnet      | 0.436s  | 59.58ms             | 100%    | 38.2 MB  |
| python-django      | 0.444s  | 60.52ms             | 100%    | 69.8 MB  |
| python-flask       | 0.455s  | 33.32ms             | 100%    | 60.3 MB  |
| kotlin-ktor        | 0.593s  | 272.23ms            | 100%    | 148.7 MB |
| ruby-rails         | 0.856s  | 149.11ms            | 100%    | 81.8 MB  |
| java-spring2       | 1.558s  | 186.03ms            | 100%    | 275.0 MB |
| java-spring        | 1.652s  | 185.13ms            | 100%    | 201.0 MB |
| scala-play         | 1.891s  | 173.53ms            | 100%    | 244.1 MB |
| node-express       | 3.534s  | 80.34ms             | 100%    | 84.5 MB  |

## Key Findings

- **Fastest Ping Startup**: cpp-drogon (0.282s)
- **Fastest Interaction Startup**: cpp-drogon (0.163s)
- **Smallest Image**: go-gin (25.1 MB)
- **Lowest Memory**: cpp-drogon (12.9 MB)

---

_Benchmarks run with Docker Desktop. Each test uses a completely fresh container (killed between tests)._
