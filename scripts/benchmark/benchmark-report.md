# Performance Benchmark Results (Full)

Generated: 2026-01-21 21:28:22

## Summary

This benchmark tests each service with two separate cold-start scenarios:

1. **Ping Test**: Container starts, health check, ping latency measured, container killed
2. **Interaction Test**: Container starts (with Pub/Sub), slash command sent, Pub/Sub message verified, container killed

## Ping Test Results

| Service             | Startup | Ping Latency | Memory   | Image Size |
| ------------------- | ------- | ------------ | -------- | ---------- |
| cpp-drogon          | 0.296s  | 29.48ms      | 13.2 MB  | 102.9 MB   |
| java-quarkus-native | 0.323s  | 43.87ms      | 54.7 MB  | 81.2 MB    |
| rust-actix          | 0.323s  | 29.09ms      | 15.9 MB  | 107.0 MB   |
| go-gin              | 0.348s  | 31.26ms      | 26.2 MB  | 25.1 MB    |
| csharp-aspnet       | 0.486s  | 32.45ms      | 69.7 MB  | 130.6 MB   |
| typescript-fastify  | 0.519s  | 32.10ms      | 53.1 MB  | 190.0 MB   |
| node-express        | 0.538s  | 38.78ms      | 49.0 MB  | 202.6 MB   |
| php-laravel         | 0.554s  | 50.75ms      | 75.4 MB  | 128.6 MB   |
| python-django       | 0.637s  | 31.15ms      | 77.2 MB  | 213.6 MB   |
| python-flask        | 0.765s  | 31.19ms      | 85.9 MB  | 189.1 MB   |
| kotlin-ktor         | 0.843s  | 38.88ms      | 129.5 MB | 257.3 MB   |
| java-quarkus        | 1.110s  | 35.45ms      | 147.1 MB | 363.6 MB   |
| java-micronaut      | 1.138s  | 36.37ms      | 145.5 MB | 357.0 MB   |
| ruby-rails          | 1.533s  | 40.32ms      | 87.2 MB  | 448.0 MB   |
| java-spring2        | 1.700s  | 32.49ms      | 211.6 MB | 340.4 MB   |
| java-spring         | 1.766s  | 39.96ms      | 188.9 MB | 265.1 MB   |
| scala-play          | 2.156s  | 44.43ms      | 209.4 MB | 296.8 MB   |

## Interaction Test Results (with Pub/Sub)

| Service             | Startup | Interaction Latency | Pub/Sub | Memory   |
| ------------------- | ------- | ------------------- | ------- | -------- |
| go-gin              | 0.164s  | 36.48ms             | 100%    | 8.6 MB   |
| cpp-drogon          | 0.194s  | 31.79ms             | 100%    | 2.5 MB   |
| rust-actix          | 0.278s  | 31.39ms             | 100%    | 4.8 MB   |
| java-quarkus-native | 0.311s  | 42.83ms             | 100%    | 13.6 MB  |
| typescript-fastify  | 0.389s  | 73.40ms             | 100%    | 81.9 MB  |
| php-laravel         | 0.391s  | 71.74ms             | 100%    | 58.1 MB  |
| python-flask        | 0.447s  | 33.14ms             | 100%    | 60.3 MB  |
| python-django       | 0.473s  | 60.29ms             | 100%    | 69.5 MB  |
| csharp-aspnet       | 0.556s  | 60.65ms             | 100%    | 38.5 MB  |
| kotlin-ktor         | 0.586s  | 311.27ms            | 100%    | 150.1 MB |
| ruby-rails          | 1.017s  | 168.65ms            | 100%    | 82.5 MB  |
| java-micronaut      | 1.045s  | 224.90ms            | 100%    | 189.9 MB |
| java-quarkus        | 1.096s  | 240.09ms            | 100%    | 215.3 MB |
| java-spring         | 1.790s  | 188.03ms            | 100%    | 216.3 MB |
| java-spring2        | 1.930s  | 186.50ms            | 100%    | 254.6 MB |
| scala-play          | 2.113s  | 195.48ms            | 100%    | 245.3 MB |
| node-express        | 3.501s  | 74.88ms             | 100%    | 84.3 MB  |

## Key Findings

- **Fastest Ping Startup**: cpp-drogon (0.296s)
- **Fastest Interaction Startup**: go-gin (0.164s)
- **Smallest Image**: go-gin (25.1 MB)
- **Lowest Memory**: cpp-drogon (13.2 MB)

---

_Benchmarks run with Docker Desktop. Each test uses a completely fresh container (killed between tests)._
