# Contributing Guidelines

This document outlines the standards and processes for contributing to this repository.

## Development Setup

### Pre-commit Hooks

Install pre-commit hooks to ensure code quality before committing:

```bash
pip install pre-commit
pre-commit install
```

Run hooks manually on all files:

```bash
pre-commit run --all-files
```

### Editor Configuration

This repo uses EditorConfig for consistent formatting. Most editors support it natively or via plugin.
See `.editorconfig` for language-specific settings.

## Git Standards

### Branch Naming

Use descriptive branch names with prefixes:

- `feature/` - New functionality
- `fix/` - Bug fixes
- `docs/` - Documentation changes
- `refactor/` - Code restructuring
- `test/` - Test additions/changes
- `ci/` - CI/CD changes

Examples: `feature/go-gin-service`, `fix/signature-validation`, `docs/pubsub-schema`

### Commit Messages

Follow conventional commit format:

```text
<type>(<scope>): <description>

[optional body]

[optional footer]
```

**Types:** `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `ci`, `deps`, `chore`

**Scopes:** `go-gin`, `contract-tests`, `ci`, `docs`, or omit for repo-wide changes

Examples:

- `feat(go-gin): add Ed25519 signature validation`
- `fix(contract-tests): correct Pub/Sub timeout handling`
- `docs: update CONTRACT-TESTS.md with new test cases`
- `ci: add branch protection workflow`

### Pull Requests

1. Create a feature branch from `main`
2. Make changes and ensure all checks pass
3. Open PR using the template
4. Ensure contract tests pass
5. Request review from CODEOWNERS
6. Squash merge to `main`

## Version Policy

### Selection Criteria

Use **modern but stable** versions—not bleeding-edge:

- Prefer LTS releases where available
- Avoid versions less than 3 months old
- Check for known security vulnerabilities before adopting

### Language/Runtime Versions

| Language  | Version Policy      |
| --------- | ------------------- |
| Go        | Latest stable (1.x) |
| Python    | Latest 3.x LTS      |
| Node.js   | Latest LTS          |
| Java      | Latest LTS (17, 21) |
| Rust      | Latest stable       |
| C# / .NET | Latest LTS          |
| Ruby      | Latest stable       |
| PHP       | Latest stable 8.x   |
| C++       | C++17 or C++20      |

### Framework Versions

Prefer the latest stable release of each framework unless there are known stability issues. Avoid alpha/beta releases.

## Code Style

### Language-Specific Linters

Each service should include appropriate linting configuration:

| Language              | Linter           | Config File      |
| --------------------- | ---------------- | ---------------- |
| Go                    | golangci-lint    | `.golangci.yml`  |
| Python                | flake8, black    | `pyproject.toml` |
| JavaScript/TypeScript | ESLint, Prettier | `.eslintrc.js`   |
| Java                  | Checkstyle       | `checkstyle.xml` |
| Rust                  | clippy, rustfmt  | `rustfmt.toml`   |
| C#                    | dotnet format    | `.editorconfig`  |
| Ruby                  | RuboCop          | `.rubocop.yml`   |
| PHP                   | PHP_CodeSniffer  | `phpcs.xml`      |

### General Guidelines

- Follow language idioms and conventions
- Keep functions focused and small
- Prefer clarity over cleverness
- Match existing patterns in the codebase

## CI Requirements

### GitHub Actions Security

**All GitHub Actions must be pinned to full SHA hashes** to prevent supply chain attacks.

```yaml
# ✅ Correct - pinned to SHA with version comment
uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5  # v4.3.1

# ❌ Wrong - using version tag only
uses: actions/checkout@v4
```

When adding or updating actions:

1. Find the SHA for the specific version tag on GitHub (Releases page → commit SHA)
2. Use the full 40-character SHA in the `uses:` line
3. Add a version comment (e.g., `# v4.3.1`) for maintainability
4. Run `actionlint` to verify workflow syntax

This policy is enforced by actionlint in CI.

### Required Status Checks

All PRs must pass:

- Contract tests (when services exist)
- Pre-commit hooks
- Language-specific linters

### Branch Protection

The `main` branch is protected:

- Require PR reviews before merging
- Require status checks to pass
- No force pushes
- No deletion

## Issue Tracking

This repo uses **beads** (`bd`) for issue tracking. See `AGENTS.md` for commands.

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress
bd close <id>
bd sync               # Sync with git
```

## Testing

### Contract Tests

All service implementations must pass the golden contract test suite. See `docs/CONTRACT-TESTS.md` for the full specification.

```bash
# Run contract tests
CONTRACT_TEST_TARGET=http://localhost:8080 \
PUBSUB_EMULATOR_HOST=localhost:8085 \
go test ./tests/contract/...
```

### Adding New Tests

When adding contract tests:

1. Tests must be language-agnostic
2. Tests must clean up Pub/Sub resources
3. Tests must not depend on execution order
4. Tests must complete within 30 seconds
