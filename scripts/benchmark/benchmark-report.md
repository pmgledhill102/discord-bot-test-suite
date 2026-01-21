# Performance Benchmark Results (Full)

Generated: 2026-01-21 10:44:59

## Summary

This benchmark tests each service with two separate cold-start scenarios:
1. **Ping Test**: Container starts, health check, ping latency measured, container killed
2. **Interaction Test**: Container starts (with Pub/Sub), slash command sent, Pub/Sub message verified, container killed

## Ping Test Results

| Service | Startup | Ping Latency | Memory | Image Size |
|---------|---------|--------------|--------|------------|
| rust-actix | 0.161s | 30.40ms | 1.9 MB | 105.6 MB |
| cpp-drogon | 0.177s | 31.47ms | 2.4 MB | 102.9 MB |
| go-gin | 0.202s | 32.02ms | 5.2 MB | 25.1 MB |
| csharp-aspnet | 0.326s | 32.39ms | 21.3 MB | 130.6 MB |
| php-laravel | 0.377s | 45.47ms | 56.2 MB | 128.6 MB |
| typescript-fastify | 0.396s | 32.30ms | 51.6 MB | 190.0 MB |
| node-express | 0.400s | 32.20ms | 45.8 MB | 202.6 MB |
| python-flask | 0.450s | 31.25ms | 55.5 MB | 189.1 MB |
| kotlin-ktor | 0.603s | 35.08ms | 129.4 MB | 257.3 MB |
| python-django | 0.607s | 32.93ms | 64.6 MB | 213.6 MB |
| ruby-rails | 0.973s | 36.41ms | 64.6 MB | 448.0 MB |
| java-spring2 | 1.427s | 33.59ms | 168.8 MB | 340.4 MB |
| java-spring | 1.564s | 33.11ms | 159.0 MB | 265.1 MB |
| scala-play | 1.815s | 39.42ms | 208.7 MB | 296.8 MB |

## Interaction Test Results (with Pub/Sub)

| Service | Startup | Interaction Latency | Pub/Sub | Memory |
|---------|---------|---------------------|---------|--------|
| cpp-drogon | 0.153s | 32.16ms | N/A | 2.6 MB |
| go-gin | 0.171s | 33.47ms | 100% | 7.4 MB |
| rust-actix | 0.225s | 31.49ms | N/A | 1.7 MB |
| php-laravel | 0.378s | 1580.38ms | N/A | 56.0 MB |
| python-flask | 0.424s | 34.19ms | 100% | 56.5 MB |
| python-django | 0.449s | 54.32ms | 100% | 65.7 MB |
| typescript-fastify | 0.532s | 89.56ms | 100% | 82.2 MB |
| kotlin-ktor | 0.598s | 205.09ms | N/A | 103.0 MB |
| ruby-rails | 0.966s | 163.22ms | 100% | 82.7 MB |
| java-spring2 | 1.547s | 178.49ms | 100% | 239.3 MB |
| java-spring | 1.654s | 178.89ms | 100% | 206.4 MB |
| csharp-aspnet | 1.935s | 44.81ms | N/A | 32.4 MB |
| scala-play | 2.029s | 191.53ms | 100% | 242.4 MB |
| node-express | 3.503s | 74.86ms | 100% | 82.9 MB |

## Key Findings

- **Fastest Ping Startup**: rust-actix (0.161s)
- **Fastest Interaction Startup**: cpp-drogon (0.153s)
- **Smallest Image**: go-gin (25.1 MB)
- **Lowest Memory**: rust-actix (1.9 MB)

---

*Benchmarks run with Docker Desktop. Each test uses a completely fresh container (killed between tests).*