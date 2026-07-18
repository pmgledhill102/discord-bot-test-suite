# Agent Instructions

This project uses **GitHub Issues** for issue tracking — see
`agentic-coding-config` `docs/github-issues-workflow.md` for conventions
(P0-P4 priority labels, `type: *` labels, blocked-by dependencies).

## Quick Reference

```bash
gh issue list --search "is:open -is:blocked"   # Find available work
gh issue view <n>                              # View issue details
gh issue edit <n> --add-assignee @me           # Claim work
gh issue close <n> --comment "Shipped in #<pr>"  # Complete work
```

Use `gh issue list` / direct reads, never `gh search issues`, for anything
time-sensitive (search is eventually consistent).

## Feature Branch Workflow

**All work MUST go through feature branches and pull requests.** Direct pushes to `main` are blocked.

### Creating a Feature Branch

When starting work on an issue:

```bash
gh issue edit <n> --add-assignee @me   # Claim the work
git checkout -b <branch-name>          # Create feature branch
# Branch naming: issue-<n>-<short-description>
# Example: issue-42-fix-ci-failures
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

3. **Wait for CI to pass** - Required status checks:

   - Lint Markdown
   - Lint YAML
   - Lint GitHub Actions
   - Check Formatting (Prettier)

   Additional checks run on path-specific changes:

   - Lint Go Code (when `services/go-gin/**` changes)
   - Contract Tests (when Go service or tests change)
   - Lint Shell Scripts (when `.sh` files change)

4. **Merge when green:**

   ```bash
   gh pr merge --squash --delete-branch
   ```

5. **Close the issue** (automatic if the PR body says `Closes #<n>`):

   ```bash
   git checkout main && git pull
   gh issue close <n> --comment "Shipped in #<pr>"
   ```

### Branch Protection Rules

The `main` branch has these protections enabled:

- **Require pull request** - No direct pushes allowed
- **Require status checks** - All CI jobs must pass
- **Require branch up-to-date** - Must be current with main before merge
- **No force pushes** - History cannot be rewritten

### Issue Lifecycle with PRs

```text
ready → assigned → [branch] → [PR] → [CI passes] → [merge] → closed
```

Each issue maps to one feature branch and one PR. Keep PRs focused and atomic.

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:

   ```bash
   git pull --rebase
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
