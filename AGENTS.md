# Agent Instructions

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
```

## Feature Branch Workflow

**All work MUST go through feature branches and pull requests.** Direct pushes to `main` are blocked.

### Creating a Feature Branch

When starting work on a bead:

```bash
bd update <id> --status in_progress   # Claim the work
git checkout -b <branch-name>          # Create feature branch
# Branch naming: <bead-id>-<short-description>
# Example: c5k.10-fix-ci-failures
```

### Pull Request Workflow

1. **Push your branch:**

   ```bash
   git push -u origin <branch-name>
   ```

2. **Create a pull request:**

   ```bash
   gh pr create --title "Title" --body "Description"
   ```

3. **Wait for CI to pass** - All 7 status checks must succeed:
   - actionlint
   - markdown-lint
   - prettier
   - shellcheck
   - yaml-lint
   - Lint Go Code
   - Contract Tests

4. **Merge when green:**

   ```bash
   gh pr merge --squash --delete-branch
   ```

5. **Close the bead:**

   ```bash
   git checkout main && git pull
   bd close <id>
   bd sync
   git push
   ```

### Branch Protection Rules

The `main` branch has these protections enabled:

- **Require pull request** - No direct pushes allowed
- **Require status checks** - All CI jobs must pass
- **Require branch up-to-date** - Must be current with main before merge
- **No force pushes** - History cannot be rewritten

### Bead Lifecycle with PRs

```text
ready → in_progress → [branch] → [PR] → [CI passes] → [merge] → closed
```

Each bead maps to one feature branch and one PR. Keep PRs focused and atomic.

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:

   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```

5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**

- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds

Use 'bd' for task tracking
