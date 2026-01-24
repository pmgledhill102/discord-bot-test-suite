# Linting Strategy

This document describes the linting strategy for the discord-bot-test-suite repository.

## Philosophy

**Agent-first approach**: Agents benefit from running all checks (no distraction concern). The `HUMAN_HERE=1`
environment variable allows humans to opt out of slower/noisier checks during local development.

**Critical principle**: Pre-commit and CI must use the exact same tool version and configuration. If it passes
locally, it must pass in CI, and vice versa.

## HUMAN_HERE Environment Variable

Some linting checks are slower and can be skipped during local development by setting the `HUMAN_HERE=1` environment
variable. This is useful when you want faster feedback during iterative development.

```bash
# Run all pre-commit hooks (agent behavior)
pre-commit run --all-files

# Skip slower checks (human development mode)
HUMAN_HERE=1 pre-commit run --all-files
```

### Checks that respect HUMAN_HERE

| Check               | Tool              | Why skippable            |
| ------------------- | ----------------- | ------------------------ |
| cspell              | Spell checker     | Slower, can be noisy     |
| markdownlint        | Markdown linter   | Slower                   |
| golangci-lint       | Go linter         | Slower (5m timeout)      |
| rubocop             | Ruby linter       | Slower                   |
| eslint (TypeScript) | TypeScript linter | Requires npm install     |
| eslint (Node.js)    | JavaScript linter | Requires npm install     |
| clang-format        | C++ formatter     | Requires clang installed |

### Checks that always run

These checks are fast and always run regardless of HUMAN_HERE:

- check-yaml, check-json (pre-commit-hooks)
- trailing-whitespace, end-of-file-fixer
- prettier (JSON, YAML, Markdown formatting)
- yamllint (YAML linting)
- actionlint (GitHub Actions linting)
- ruff (Python linting and formatting)
- shellcheck (Shell script linting)
- hadolint (Dockerfile linting)
- clang-format (C++ formatting)

## Pre-commit Setup

Install pre-commit hooks:

```bash
pip install pre-commit
pre-commit install
```

Run all hooks manually:

```bash
pre-commit run --all-files
```

## Per-Language Linting

### Go (go-gin, contract tests)

- **Tool**: golangci-lint v2.8.0
- **Config**: `.golangci.yml` in each Go directory
- **Timeout**: 5 minutes
- **CI**: `golangci/golangci-lint-action@v9.2.0`
- **Pre-commit**: Local hook with HUMAN_HERE wrapper

### Python (python-flask, python-django)

- **Tool**: ruff
- **Config**: `pyproject.toml` in each Python service
- **CI**: `ruff check .` and `ruff format --check .`
- **Pre-commit**: `astral-sh/ruff-pre-commit`

### Ruby (ruby-rails)

- **Tool**: RuboCop
- **Config**: `services/ruby-rails/.rubocop.yml`
- **CI**: `rubocop --config .rubocop.yml`
- **Pre-commit**: Local hook with HUMAN_HERE wrapper

### TypeScript (typescript-fastify)

- **Tool**: ESLint with typescript-eslint
- **Config**: `services/typescript-fastify/eslint.config.mjs`
- **CI**: `npm run lint`
- **Pre-commit**: Local hook with HUMAN_HERE wrapper

### Node.js (node-express)

- **Tool**: ESLint
- **Config**: `services/node-express/eslint.config.mjs`
- **CI**: `npm run lint`
- **Pre-commit**: Local hook with HUMAN_HERE wrapper

### C++ (cpp-drogon)

- **Tool**: clang-format
- **Config**: `services/cpp-drogon/.clang-format`
- **Static analysis config**: `services/cpp-drogon/.clang-tidy` (for future use)
- **CI**: `clang-format --dry-run --Werror` <!-- cspell:disable-line -->
- **Pre-commit**: Local hook with HUMAN_HERE wrapper

### Shell Scripts

- **Tool**: ShellCheck
- **Pre-commit**: `shellcheck-py/shellcheck-py`
- **No CI-specific job** (runs in pre-commit only)

### Dockerfiles

- **Tool**: Hadolint
- **Pre-commit**: `hadolint/hadolint`
- **No CI-specific job** (runs in pre-commit only)

## Generic Linting

### YAML

- **Tool**: yamllint
- **Config**: Inline in `.pre-commit-config.yaml`
- **CI**: `ibiqlik/action-yamllint@v3.1.1`

### JSON/YAML/Markdown Formatting

- **Tool**: Prettier
- **CI**: `prettier --check`
- **Pre-commit**: `pre-commit/mirrors-prettier`

### Markdown

- **Tool**: markdownlint-cli2
- **Config**: `.markdownlint.json`
- **CI**: `DavidAnson/markdownlint-cli2-action@v19.1.0`
- **Pre-commit**: Local hook with HUMAN_HERE wrapper

### Spell Check

- **Tool**: cspell
- **CI**: `streetsidesoftware/cspell-action@v8.1.2`
- **Pre-commit**: Local hook with HUMAN_HERE wrapper

### GitHub Actions

- **Tool**: actionlint
- **CI**: `raven-actions/actionlint@v2.1.0`
- **Pre-commit**: `rhysd/actionlint`

## CI-Only Checks

These checks run only in CI and are not part of pre-commit:

### Terraform

- **CI job**: `terraform` in `.github/workflows/lint.yml`
- **Checks**: `terraform fmt -check`, `terraform init`, `terraform validate`
- **Why CI-only**: Requires Terraform installation, complex setup

### Services YAML Validation

- **CI job**: `services-yaml` in `.github/workflows/lint.yml`
- **Script**: `tests/validate-services-yaml.sh`
- **Why CI-only**: Custom validation script, requires yq

## Adding New Linting

When adding linting for a new language or service:

1. **Choose the tool**: Prefer tools with good pre-commit support
2. **Add configuration**: Create config file in the service directory
3. **Add pre-commit hook**: Use HUMAN_HERE wrapper if the check is slow
4. **Add CI step**: Ensure same tool version and config
5. **Document**: Update this file with the new linting setup

### Incremental vs Whole-Directory Linting

Pre-commit hooks can operate in two modes:

| Mode                | When to Use                                         | `pass_filenames` |
| ------------------- | --------------------------------------------------- | ---------------- |
| **Incremental**     | Tool can lint individual files correctly            | `true` (default) |
| **Whole-directory** | Tool needs full context (e.g., cross-file analysis) | `false`          |

**Incremental linting** (preferred): The hook receives only the changed files and lints just those.
This is faster for typical commits that touch few files.

**Whole-directory linting**: The hook runs on all files in a directory when any file changes.
Required when the linter needs to see all files for correct analysis (e.g., Go's cross-package checks).

#### Decision Guide

Use **incremental** (`pass_filenames: true` or omit) when:

- The linter works correctly on individual files (most formatters, spell checkers)
- Files are independent (no cross-file analysis needed)
- The service has many source files

Use **whole-directory** (`pass_filenames: false`) when:

- The linter requires package/module context (e.g., `golangci-lint` for Go)
- The service has only 1-2 source files (no benefit to incremental)
- Cross-file analysis is needed for correctness

#### Examples from this repo

| Hook             | Mode            | Reason                                        |
| ---------------- | --------------- | --------------------------------------------- |
| cspell           | Incremental     | Spell checking is per-file                    |
| markdownlint     | Incremental     | Markdown linting is per-file                  |
| clang-format     | Incremental     | Formatting is per-file                        |
| rubocop          | Incremental     | Ruby linting works per-file                   |
| golangci-lint    | Whole-directory | Go needs package context for type checking    |
| eslint (node/ts) | Whole-directory | Only 1 source file, no benefit to incremental |

### HUMAN_HERE Hook Templates

**Incremental linting** (lints only changed files):

```yaml
- repo: local
  hooks:
    - id: my-linter-service-name
      name: my-linter service-name (agent-only)
      entry: bash -c '[ -n "$HUMAN_HERE" ] && exit 0 || my-linter --config path/to/config "$@"' --
      language: system
      files: ^services/service-name/.*\.ext$
```

Note: The `"$@"' --` pattern passes filenames from pre-commit to the linter command.

**Whole-directory linting** (lints all files when any change):

```yaml
- repo: local
  hooks:
    - id: my-linter-service-name
      name: my-linter service-name (agent-only)
      entry: bash -c '[ -n "$HUMAN_HERE" ] && exit 0 || cd services/service-name && my-linter run'
      language: system
      files: ^services/service-name/.*\.ext$
      pass_filenames: false
```
