# Dependabot Strategy

This document describes the two-tier Dependabot strategy for managing dependency updates.

## Overview

Dependencies are managed with a two-tier approach to balance automation with appropriate oversight:

| Tier   | Update Type                   | Action        | Rationale                        |
| ------ | ----------------------------- | ------------- | -------------------------------- |
| Tier 1 | Patch and minor updates       | Auto-merge    | Low risk, high volume            |
| Tier 2 | Major, Docker, GitHub Actions | Manual review | Breaking changes, infrastructure |

## Tier 1: Auto-Merge

Patch and minor version updates are automatically merged after CI passes.

**Ecosystems included:**

- Go modules
- Python (pip)
- Node.js (npm)
- Java (Maven)
- Kotlin/Scala (Gradle)
- Rust (Cargo)
- C# (NuGet)
- Ruby (Bundler)
- PHP (Composer)
- Terraform

**Criteria for auto-merge:**

1. Update type is `patch` or `minor`
2. Not a Docker ecosystem update
3. Not a GitHub Actions update
4. All CI checks pass

## Tier 2: Manual Review

These updates require human review before merging.

### Major Version Updates

Any ecosystem with a major version bump requires review because:

- Breaking API changes
- Migration steps may be needed
- Dependent code changes required

### GitHub Actions Updates

Workflow changes require review because:

- CI/CD infrastructure changes
- Security-sensitive (runs with repo permissions)
- May affect deployment pipeline

### Docker Base Images

Base image updates require review because:

- Runtime environment changes
- May affect application behavior
- Security implications of OS-level changes

## Configuration

### Dependabot Schedule

All ecosystems are checked weekly on Monday. Updates are grouped by service to reduce PR volume.

### Grouping Strategy

Dependencies are grouped by service directory to batch related updates:

```yaml
groups:
  service-deps:
    patterns:
      - '*'
```

This means a service like `java-spring4` gets one PR for all its dependency updates rather than
individual PRs per dependency.

## Workflow

### For Auto-Merged PRs

1. Dependabot opens PR
2. CI runs automatically
3. `dependabot-auto-merge.yml` checks eligibility
4. If eligible and CI passes, PR is squash-merged

### For Manual Review PRs

1. Dependabot opens PR
2. Bot adds comment explaining why manual review is needed
3. Reviewer checks changelog/migration guide
4. Reviewer approves and merges

## Monitoring

To see pending Dependabot PRs:

```bash
gh pr list --author "dependabot[bot]" --state open
```

To see auto-merge status:

```bash
gh pr list --author "dependabot[bot]" --json number,title,autoMergeRequest
```
