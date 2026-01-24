# Pre-commit Performance Analysis

This document provides execution time benchmarks for each pre-commit hook and validates the HUMAN_HERE classification.

## Benchmark Environment

- **Machine**: Apple M2 (arm64)
- **OS**: macOS 26.2
- **Cores**: 8
- **Date**: 2026-01-24

## Summary

| Mode             | Total Time | Hooks Run |
| ---------------- | ---------- | --------- |
| Full run         | ~30s       | 37 hooks  |
| HUMAN_HERE=1 run | ~4s        | 10 hooks  |
| **Speedup**      | **~7x**    |           |

## Hook Execution Times

### Always-Run Hooks (fast, run regardless of HUMAN_HERE)

| Hook                    | Time  | Tool             |
| ----------------------- | ----- | ---------------- |
| bd-sync                 | 0.41s | beads            |
| trailing-whitespace     | 0.30s | pre-commit-hooks |
| end-of-file-fixer       | 0.28s | pre-commit-hooks |
| check-yaml              | 0.32s | pre-commit-hooks |
| check-json              | 0.27s | pre-commit-hooks |
| check-added-large-files | 0.31s | pre-commit-hooks |
| check-merge-conflict    | 0.32s | pre-commit-hooks |
| detect-private-key      | 0.29s | pre-commit-hooks |
| no-commit-to-branch     | 0.24s | pre-commit-hooks |
| prettier                | 0.84s | prettier         |
| yamllint                | 0.42s | yamllint         |
| actionlint              | 0.38s | actionlint       |
| ruff                    | 0.25s | ruff             |
| ruff-format             | 0.21s | ruff             |
| shellcheck              | 2.09s | shellcheck       |
| hadolint-docker         | 3.12s | hadolint         |
| **Subtotal**            | ~10s  |                  |

### Agent-Only Hooks (skipped with HUMAN_HERE=1)

| Hook                               | Time  | Tool           | Why Agent-Only            |
| ---------------------------------- | ----- | -------------- | ------------------------- |
| cspell                             | 4.94s | cspell         | Slower, can be noisy      |
| markdownlint                       | 2.35s | markdownlint   | Slower                    |
| golangci-lint-go-gin               | 0.96s | golangci-lint  | Requires Go toolchain     |
| golangci-lint-contract             | 0.52s | golangci-lint  | Requires Go toolchain     |
| rubocop                            | 0.18s | rubocop        | Requires Ruby gems        |
| eslint-typescript-fastify          | 0.99s | eslint         | Requires npm install      |
| eslint-node-express                | 0.59s | eslint         | Requires npm install      |
| clang-format-cpp-drogon            | 0.18s | clang-format   | Requires clang installed  |
| rustfmt-rust-actix                 | 0.41s | rustfmt        | Requires Rust toolchain   |
| clippy-rust-actix                  | 0.43s | clippy         | Requires Rust toolchain   |
| pint-php-laravel                   | 0.17s | pint           | Requires composer install |
| dotnet-format-csharp-aspnet        | 1.98s | dotnet format  | Requires .NET SDK         |
| dotnet-format-csharp-aspnet-native | 1.62s | dotnet format  | Requires .NET SDK         |
| ktlint-kotlin-ktor                 | 4.34s | ktlint/gradle  | Requires Gradle, slower   |
| scalafmt-scala-play                | 0.17s | scalafmt/sbt   | Requires sbt              |
| spotless-java-spring4              | 1.46s | spotless/maven | Requires Maven            |
| spotless-java-spring3              | 1.31s | spotless/maven | Requires Maven            |
| spotless-java-spring2              | 1.29s | spotless/maven | Requires Maven            |
| spotless-java-micronaut            | 1.90s | spotless/maven | Requires Maven            |
| spotless-java-quarkus              | 1.75s | spotless/maven | Requires Maven            |
| spotless-java-quarkus-native       | 1.66s | spotless/maven | Requires Maven            |
| **Subtotal**                       | ~27s  |                |                           |

## HUMAN_HERE Classification Validation

The HUMAN_HERE classification is based on two criteria:

1. **Execution time** - Hooks taking >1s are candidates for skipping
2. **Tool requirements** - Hooks requiring language-specific toolchains

### Correctly Classified as Agent-Only

| Hook              | Time     | Reason                                    |
| ----------------- | -------- | ----------------------------------------- |
| cspell            | 4.94s    | Slowest hook, spell checking can be noisy |
| ktlint            | 4.34s    | Gradle startup overhead                   |
| markdownlint      | 2.35s    | Moderate time, markdown-only              |
| dotnet-format (2) | 1.6-2s   | .NET SDK requirement                      |
| spotless (6)      | 1.3-1.9s | Maven requirement, multiple services      |
| eslint (2)        | 0.6-1s   | npm install requirement                   |
| golangci-lint (2) | 0.5-1s   | Go toolchain requirement                  |

### Fast But Still Agent-Only (toolchain requirement)

These hooks are fast but require specific toolchains that humans may not have installed:

| Hook         | Time  | Required Toolchain |
| ------------ | ----- | ------------------ |
| rubocop      | 0.18s | Ruby + gems        |
| clang-format | 0.18s | LLVM/Clang         |
| pint         | 0.17s | PHP + Composer     |
| scalafmt     | 0.17s | Scala + sbt        |
| rustfmt      | 0.41s | Rust toolchain     |
| clippy       | 0.43s | Rust toolchain     |

## Recommendations

### For Human Developers

Use `HUMAN_HERE=1` during iterative development:

```bash
# Fast feedback loop (~4s)
HUMAN_HERE=1 pre-commit run --all-files

# Or set in shell profile
export HUMAN_HERE=1
```

Run full checks before pushing:

```bash
# Full validation (~30s)
pre-commit run --all-files
```

### For CI/Agents

Always run full checks (no HUMAN_HERE):

```bash
pre-commit run --all-files
```

### Incremental vs Full Runs

For typical commits touching 1-5 files, execution time is dominated by hook startup overhead rather than
file processing. The ~7x speedup from HUMAN_HERE=1 is most noticeable when running `--all-files`.

## Notes

- Times are for a cold run (no caching)
- Gradle/Maven/sbt hooks include JVM startup time
- Go and Rust hooks benefit from incremental compilation on subsequent runs
- shellcheck and hadolint are always-run despite being slower (~2-3s) because they have no toolchain
  requirements beyond the pre-commit environment
