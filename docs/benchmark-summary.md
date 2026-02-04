# Cloud Run Cold-Start Benchmark Summary

**Period:** 2026-01-24 to 2026-02-04  
**Total run days:** 12  
**Services tested:** 19  
**Readings per day:** 6 (cold-start iterations)  
**Total data points:** 1368

**Configuration:** 1 vCPU, 512Mi memory, gen2 execution environment, startup CPU boost enabled, europe-west1

## Cold-Start TTFB Rankings (All Days Aggregated)

Ranked by median TTFB across all readings in the period.

| Rank | Service              | Median (ms) | Mean (ms) | Min (ms) | Max (ms) | StdDev (ms) | Readings | Success % |
| ---: | -------------------- | ----------: | --------: | -------: | -------: | ----------: | -------: | --------: |
|    1 | rust-actix           |         298 |       310 |       30 |      452 |          69 |       72 |      100% |
|    2 | csharp-aspnet-native |         334 |       379 |       25 |      774 |         141 |       72 |      100% |
|    3 | go-gin               |         343 |       436 |       40 |     1007 |         208 |       72 |      100% |
|    4 | cpp-drogon           |         375 |       377 |       27 |      569 |          93 |       72 |      100% |
|    5 | java-quarkus-native  |         447 |       729 |       27 |     1888 |         536 |       72 |      100% |
|    6 | csharp-aspnet        |        1013 |      1118 |       25 |     1973 |         375 |       72 |      100% |
|    7 | node-express         |        1636 |      1661 |       41 |     2474 |         392 |       72 |      100% |
|    8 | php-laravel          |        1637 |      1714 |       28 |     3884 |         509 |       72 |      100% |
|    9 | typescript-fastify   |        1988 |      1982 |       35 |     3217 |         505 |       72 |      100% |
|   10 | kotlin-ktor          |        2969 |      2946 |       36 |     4313 |         689 |       72 |      100% |
|   11 | python-flask         |        3283 |      3211 |       24 |     5211 |         704 |       72 |      100% |
|   12 | java-quarkus         |        3452 |      3486 |       37 |     5013 |         781 |       72 |      100% |
|   13 | python-django        |        3566 |      3689 |       28 |     5328 |         845 |       72 |       97% |
|   14 | java-micronaut       |        3823 |      3795 |       35 |     5338 |         794 |       72 |      100% |
|   15 | java-spring2         |        5211 |      5102 |       32 |     6925 |        1067 |       72 |       71% |
|   16 | scala-play           |        5729 |      5608 |       48 |     8508 |        1232 |       72 |       50% |
|   17 | java-spring4         |        6089 |      6016 |       34 |     7703 |        1121 |       72 |       18% |
|   18 | java-spring3         |        6669 |      6528 |       31 |     8359 |        1260 |       72 |        7% |
|   19 | ruby-rails           |        8404 |      8164 |      178 |    12566 |        2346 |       72 |        6% |

## Performance Tiers

**Tier 1 — Sub-second** (<1s median): rust-actix, csharp-aspnet-native, go-gin, cpp-drogon, java-quarkus-native

**Tier 2 — Fast** (1–3s median): csharp-aspnet, node-express, php-laravel, typescript-fastify, kotlin-ktor

**Tier 3 — Moderate** (3–5s median): python-flask, java-quarkus, python-django, java-micronaut

**Tier 4 — Slow** (5s+ median): java-spring2, scala-play, java-spring4, java-spring3, ruby-rails

## Daily Cold-Start Trends (Average TTFB in ms)

| Date       | rust-actix | csharp-aspnet-native | go-gin | cpp-drogon | java-quarkus-native | csharp-aspnet | node-express | php-laravel |
| ---------- | ---------: | -------------------: | -----: | ---------: | ------------------: | ------------: | -----------: | ----------: |
| 2026-01-24 |        285 |                  474 |    454 |        358 |                 766 |          1236 |         1742 |        1560 |
| 2026-01-25 |        243 |                  323 |    319 |        284 |                 502 |           793 |         1307 |        1099 |
| 2026-01-26 |        386 |                  327 |    377 |        364 |                1179 |          1172 |         1801 |        2097 |
| 2026-01-27 |        360 |                  374 |    424 |        433 |                1067 |          1243 |         1813 |        1872 |
| 2026-01-28 |        341 |                  321 |    345 |        404 |                 917 |          1097 |         1798 |        1768 |
| 2026-01-29 |        293 |                  401 |    472 |        378 |                 572 |          1164 |         1920 |        1909 |
| 2026-01-30 |        293 |                  372 |    653 |        384 |                 565 |          1225 |         1483 |        1984 |
| 2026-01-31 |        317 |                  357 |    411 |        400 |                 798 |          1282 |         1632 |        1662 |
| 2026-02-01 |        295 |                  383 |    421 |        361 |                 628 |          1077 |         1734 |        1615 |
| 2026-02-02 |        298 |                  362 |    373 |        387 |                 580 |           945 |         1494 |        1659 |
| 2026-02-03 |        298 |                  438 |    437 |        335 |                 548 |          1133 |         1589 |        1791 |
| 2026-02-04 |        313 |                  417 |    549 |        431 |                 629 |          1045 |         1617 |        1550 |

### Remaining Services

| Date       | typescript-fastify | kotlin-ktor | python-flask | java-quarkus | python-django | java-micronaut | java-spring2 | scala-play | java-spring4 | java-spring3 | ruby-rails |
| ---------- | -----------------: | ----------: | -----------: | -----------: | ------------: | -------------: | -----------: | ---------: | -----------: | -----------: | ---------: |
| 2026-01-24 |               1637 |        2732 |         2895 |         3687 |          4154 |           4441 |         6117 |       5022 |         6228 |         6479 |       9711 |
| 2026-01-25 |               1211 |        2017 |         2401 |         2605 |          2728 |           2864 |         4110 |       3753 |         3867 |         4226 |       5559 |
| 2026-01-26 |               2162 |        2971 |         3534 |         3524 |          3930 |           3813 |         4809 |       5618 |         6232 |         6787 |       9967 |
| 2026-01-27 |               1850 |        2973 |         3362 |         3609 |          3902 |           4109 |         5182 |       5879 |         6183 |         6791 |       6501 |
| 2026-01-28 |               2050 |        2631 |         3067 |         3586 |          3767 |           4036 |         5484 |       5408 |         5954 |         7593 |       7525 |
| 2026-01-29 |               2424 |        3126 |         3375 |         3571 |          3738 |           4076 |         5064 |       5449 |         6132 |         6531 |       7776 |
| 2026-01-30 |               1778 |        3308 |         3252 |         3508 |          3647 |           3801 |         4705 |       5659 |         7182 |         6545 |       8957 |
| 2026-01-31 |               1990 |        3512 |         3168 |         3320 |          3666 |           3533 |         5083 |       5412 |         5953 |         6979 |       7766 |
| 2026-02-01 |               2270 |        3256 |         3269 |         3439 |          3893 |           3811 |         4863 |       6341 |         6198 |         6696 |       8992 |
| 2026-02-02 |               2394 |        3285 |         3635 |         3211 |          3783 |           3956 |         5236 |       6388 |         6201 |         6404 |       9204 |
| 2026-02-03 |               2002 |        2762 |         3291 |         3957 |          3366 |           3630 |         5283 |       6375 |         5895 |         7022 |       8032 |
| 2026-02-04 |               2019 |        2778 |         3279 |         3810 |          3693 |           3467 |         5289 |       5991 |         6171 |         6285 |       7976 |

## Warm Request Performance (Latest Run)

Once warmed up, how do services perform under load (100 requests, concurrency 10)?

| Service              |   RPS | Avg (ms) | P50 (ms) | P95 (ms) | P99 (ms) |
| -------------------- | ----: | -------: | -------: | -------: | -------: |
| csharp-aspnet-native | 931.1 |      9.9 |      7.4 |     22.8 |     36.0 |
| python-flask         | 555.6 |     17.6 |     10.6 |     58.5 |     62.0 |
| python-django        | 510.7 |     19.0 |     11.7 |     63.4 |     65.2 |
| csharp-aspnet        | 454.8 |     21.7 |     10.8 |     59.8 |     64.7 |
| rust-actix           | 223.2 |     40.0 |      6.8 |    308.1 |    309.3 |
| java-spring2         |  15.7 |     43.4 |     19.3 |    152.8 |    190.3 |
| cpp-drogon           | 215.9 |     45.9 |      8.8 |    378.9 |    379.9 |
| go-gin               | 201.1 |     49.4 |      8.0 |    423.0 |    423.4 |
| php-laravel          | 148.0 |     66.0 |     86.8 |     97.6 |     98.2 |
| java-spring4         |  15.2 |     67.9 |     15.7 |    348.6 |    375.0 |
| java-quarkus-native  | 141.6 |     70.3 |     14.9 |    527.2 |    530.2 |
| java-spring3         |  11.7 |     77.3 |     14.9 |    398.7 |    411.3 |
| typescript-fastify   |  48.1 |    198.1 |    203.7 |    243.4 |    262.3 |
| scala-play           |  36.2 |    261.5 |    213.4 |    561.4 |    670.4 |
| kotlin-ktor          |  34.4 |    289.4 |     68.1 |   2436.9 |   2442.5 |
| node-express         |  32.8 |    300.6 |     99.2 |   2115.2 |   2173.6 |
| java-micronaut       |  25.9 |    382.5 |     14.1 |   3575.8 |   3580.9 |
| java-quarkus         |  25.5 |    390.2 |     18.9 |   3583.2 |   3592.1 |
| ruby-rails           |   8.9 |   1126.1 |    403.3 |   4426.4 |   5333.6 |

## Reliability Notes

Services with non-200 status codes during cold-start tests:

- **ruby-rails**: 6% success — non-200 codes: 401 (68x)
- **java-spring3**: 7% success — non-200 codes: 401 (67x)
- **java-spring4**: 18% success — non-200 codes: 401 (59x)
- **scala-play**: 50% success — non-200 codes: 401 (36x)
- **java-spring2**: 71% success — non-200 codes: 401 (21x)
- **python-django**: 97% success — non-200 codes: 401 (2x)

## Variance Analysis

Services with highest day-to-day variance (coefficient of variation):

| Service              | CV (%) | StdDev (ms) | Mean (ms) |
| -------------------- | -----: | ----------: | --------: |
| java-quarkus-native  |   73.6 |         536 |       729 |
| go-gin               |   47.7 |         208 |       436 |
| csharp-aspnet-native |   37.2 |         141 |       379 |
| csharp-aspnet        |   33.6 |         375 |      1118 |
| php-laravel          |   29.7 |         509 |      1714 |
| ruby-rails           |   28.7 |        2346 |      8164 |
| typescript-fastify   |   25.5 |         505 |      1982 |
| cpp-drogon           |   24.7 |          93 |       377 |
| node-express         |   23.6 |         392 |      1661 |
| kotlin-ktor          |   23.4 |         689 |      2946 |
| python-django        |   22.9 |         845 |      3689 |
| java-quarkus         |   22.4 |         781 |      3486 |
| rust-actix           |   22.3 |          69 |       310 |
| scala-play           |   22.0 |        1232 |      5608 |
| python-flask         |   21.9 |         704 |      3211 |
| java-micronaut       |   20.9 |         794 |      3795 |
| java-spring2         |   20.9 |        1067 |      5102 |
| java-spring3         |   19.3 |        1260 |      6528 |
| java-spring4         |   18.6 |        1121 |      6016 |

## Early Exploratory Runs (Jan 22–23)

These runs used a different configuration (1 cold-start iteration, 5 warm requests) and tested a smaller set of services.

### 01-22

**Runs:** 7

**Run 30bb319f** — Services: go-gin, node-express, rust-actix

| Service      | Cold-Start Avg |     Warm Avg | Warm RPS |
| ------------ | -------------: | -----------: | -------: |
| go-gin       |    25.950618ms |  13.559101ms |    128.9 |
| node-express |    350.07572ms | 102.898111ms |     18.6 |
| rust-actix   |    23.224939ms |  11.096461ms |    168.7 |

**Run 7b2e551e** — Services: go-gin, node-express, rust-actix

| Service      | Cold-Start Avg |    Warm Avg | Warm RPS |
| ------------ | -------------: | ----------: | -------: |
| go-gin       |   209.909972ms | 14.221429ms |    127.3 |
| node-express |   300.736932ms | 63.517761ms |     25.6 |
| rust-actix   |    28.400997ms | 12.409128ms |    147.5 |

**Run 8237fb00** — Services: go-gin, node-express, rust-actix

| Service      | Cold-Start Avg |    Warm Avg | Warm RPS |
| ------------ | -------------: | ----------: | -------: |
| go-gin       |    33.686598ms | 12.912381ms |    137.6 |
| node-express |   117.734355ms | 51.443922ms |     36.0 |
| rust-actix   |    32.443119ms | 17.193541ms |    113.7 |

**Run 86b1323d** — Services: go-gin, node-express, rust-actix

| Service      | Cold-Start Avg |    Warm Avg | Warm RPS |
| ------------ | -------------: | ----------: | -------: |
| go-gin       |             0s |           - |        - |
| node-express |    114.02445ms | 31.382026ms |     59.1 |
| rust-actix   |    27.405761ms | 15.635591ms |    120.8 |

**Run 8e28bd16** — Services: go-gin, node-express, rust-actix

| Service      | Cold-Start Avg |    Warm Avg | Warm RPS |
| ------------ | -------------: | ----------: | -------: |
| go-gin       |   218.772524ms | 13.057935ms |    134.5 |
| node-express |    81.369158ms | 75.295322ms |     23.8 |
| rust-actix   |   177.029168ms | 13.153395ms |    135.0 |

**Run a2f801d5** — Services: go-gin, node-express, rust-actix

| Service      | Cold-Start Avg |    Warm Avg | Warm RPS |
| ------------ | -------------: | ----------: | -------: |
| go-gin       |    26.312811ms | 16.560993ms |    106.8 |
| node-express |    85.162444ms | 48.787868ms |     32.1 |
| rust-actix   |    36.473648ms | 17.854967ms |    111.0 |

**Run dd1210b2** — Services: go-gin, node-express, rust-actix

| Service      | Cold-Start Avg |    Warm Avg | Warm RPS |
| ------------ | -------------: | ----------: | -------: |
| go-gin       |    33.450692ms | 16.102965ms |    112.1 |
| node-express |   108.290855ms | 49.574643ms |     31.2 |
| rust-actix   |    38.257583ms | 16.657693ms |    111.2 |

### 01-23

**Runs:** 7

**Run 29b949bc** — Services: go-gin, node-express, rust-actix

| Service      | Cold-Start Avg |    Warm Avg | Warm RPS |
| ------------ | -------------: | ----------: | -------: |
| go-gin       |     27.36678ms | 15.422727ms |    119.7 |
| node-express |    125.79914ms | 120.99911ms |     14.9 |
| rust-actix   |    31.405953ms | 15.523039ms |    116.4 |

**Run 3d5c77f5** — Services: go-gin, node-express, rust-actix

| Service      | Cold-Start Avg |    Warm Avg | Warm RPS |
| ------------ | -------------: | ----------: | -------: |
| go-gin       |    34.157128ms | 18.591535ms |     99.9 |
| node-express |    66.775876ms | 82.883049ms |     23.3 |
| rust-actix   |    27.173168ms | 18.320333ms |     98.5 |

**Run 42cc5aff** — Services: go-gin, node-express, rust-actix

| Service      | Cold-Start Avg |    Warm Avg | Warm RPS |
| ------------ | -------------: | ----------: | -------: |
| go-gin       |    32.129526ms | 16.949188ms |    105.3 |
| node-express |    84.103896ms | 62.457732ms |     30.4 |
| rust-actix   |    30.331306ms | 14.721082ms |    122.0 |

**Run 71cd682a** — Services: go-gin, node-express, rust-actix

| Service      | Cold-Start Avg |    Warm Avg | Warm RPS |
| ------------ | -------------: | ----------: | -------: |
| go-gin       |    35.233758ms | 16.183311ms |    111.0 |
| node-express |    69.015846ms | 61.320878ms |     31.3 |
| rust-actix   |    33.995508ms | 15.607516ms |    116.7 |

**Run 7ca3c7a4** — Services: go-gin, node-express, rust-actix

| Service      | Cold-Start Avg |    Warm Avg | Warm RPS |
| ------------ | -------------: | ----------: | -------: |
| go-gin       |    38.311607ms | 12.497264ms |    137.3 |
| node-express |    81.853902ms |  71.42276ms |     23.3 |
| rust-actix   |     33.38005ms | 15.149984ms |    120.3 |

**Run 8032d27f** — Services: go-gin, node-express, rust-actix

| Service      | Cold-Start Avg |     Warm Avg | Warm RPS |
| ------------ | -------------: | -----------: | -------: |
| go-gin       |    32.410524ms |   14.31217ms |    127.0 |
| node-express |    91.798706ms | 132.943245ms |     14.6 |
| rust-actix   |    26.227869ms |  17.693026ms |    105.8 |

**Run 88458994** — Services: go-gin, node-express, rust-actix

| Service      | Cold-Start Avg |    Warm Avg | Warm RPS |
| ------------ | -------------: | ----------: | -------: |
| go-gin       |    39.459638ms | 16.686081ms |    108.6 |
| node-express |    81.168548ms |  78.33784ms |     21.7 |
| rust-actix   |    37.305657ms |     16.82ms |    114.4 |

---

_Report generated on 2026-02-04 from `gs://cloud-run-test-suite-benchmark-results`_
