---
name: task-flow-fix-comments
description: Aggregate and fix PR feedback from SonarQube, CodeRabbit, and human reviewers in priority order. Standalone skill — run after PR feedback arrives. Say "task-flow-fix-comments" or "fix comments".
disable-model-invocation: true
---

# Task Flow Fix Comments

Gather → Prioritize → Fix → Test → Report → Commit → (repeat)

## When to Run

- After CI runs on a PR (SonarQube, CodeRabbit)
- After human reviewers leave comments
- Say "task-flow-fix-comments", "fix comments", or "fix PR feedback"
- Optionally with explicit PR number: `task-flow-fix-comments 286`

## Pre-Flight

```bash
# Detect PR number
if [ -n "$1" ]; then
  pr_number="$1"
else
  pr_number=$(gh pr view --json number -q '.number' 2>/dev/null)
fi

if [ -z "$pr_number" ]; then
  echo "No PR found for current branch. Provide PR number: task-flow-fix-comments {number}"
  exit 1
fi

repo_owner=$(gh repo view --json owner -q '.owner.login')
repo_name=$(gh repo view --json name -q '.name')

echo "Fixing feedback for PR #$pr_number ($repo_owner/$repo_name)"
```

## Phase 1 — Gather Feedback

Fetch from all three sources in parallel. Each source is optional — skip gracefully if unavailable.

### Iteration Awareness

This skill supports multiple iterations. Detect already-handled comments by scanning for our replies:

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  --jq '[.[] | select(.body | test("Fixed in [a-f0-9]|Acknowledged|Not fixing")) | {
    in_reply_to_id: .in_reply_to_id,
    body: .body
  }]'
```

Build `already_handled_ids` set. Skip any comment whose ID is in this set.

### Source A: SonarQube Issues

```bash
if [ -n "$SONARQUBE_URL" ] && [ -n "$SONARQUBE_TOKEN" ]; then
  ~/.claude/scripts/sonarqube/fetch-issues.sh 2>/dev/null || echo "fetch-issues.sh not found"
else
  echo "SonarQube not configured (SONARQUBE_URL + SONARQUBE_TOKEN). Skipping."
fi
```

If not configured, guide setup:
```
SonarQube not configured. To enable:
1. Generate a token at: {SONARQUBE_URL}/account/security
2. Add to shell profile:
   export SONARQUBE_URL="https://your-sonarqube-instance.com"
   export SONARQUBE_TOKEN="your-token"
3. Reload shell and re-run.

Continuing without SonarQube...
```

### Source B: CodeRabbit Comments

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  --jq '[.[] | select(.user.login == "coderabbitai[bot]") | {
    id: .id, path: .path, line: .line, body: .body,
    in_reply_to_id: .in_reply_to_id, created_at: .created_at
  }]'
```

Filter: skip handled, skip replies, skip stale (path:line no longer in current code).

### Source C: Human Reviewer Comments

```bash
# Inline review comments
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  --jq '[.[] | select(.user.login != "coderabbitai[bot]" and .user.type != "Bot") | {
    id: .id, user: .user.login, path: .path, line: .line, body: .body
  }]'

# Top-level review bodies
gh api repos/{owner}/{repo}/pulls/{pr_number}/reviews \
  --jq '[.[] | select(.body != "" and .body != null and .user.type != "Bot") | {
    id: .id, user: .user.login, state: .state, body: .body
  }]'
```

### Summary

```
## PR #{pr_number} Feedback Summary (Iteration {n})

- SonarQube: {n} new issues
- CodeRabbit: {n} unresolved comments
- Human reviewers: {n} new comments

{If all zero: "All feedback resolved!"}
```

## Phase 2 — Fix in Priority Order

### Priority 1: SonarQube (highest confidence)

| Category | Action |
|----------|--------|
| Unused imports/variables | Auto-fix (remove) |
| Empty blocks | Auto-fix (add comment or remove) |
| Missing assertions | Auto-fix (add meaningful assertion) |
| Code style | Auto-fix |
| Cognitive complexity | Flag for manual review |
| Security issues | **NEVER auto-fix** — flag for manual review |
| Concurrency issues | Flag for manual review |

### Priority 2: CodeRabbit (verify before fixing)

For each comment:
1. Read affected code and surrounding context
2. Validate against **current** code (not the diff it reviewed)
3. Decision: **Valid** → fix | **Invalid** → draft reply explaining why | **Ambiguous** → flag

**Reply quality — must be substantive:**

| Scenario | Reply Format |
|----------|-------------|
| Fixed | "Fixed in {sha} — {what changed}" |
| Intentional | "This is intentional: {reason}" |
| Disagree | "Suggested approach would {problem}. Current code {why better}" |
| Separate ticket | "Valid — tracking as {ticket} for dedicated PR" |

### Priority 3: Human Comments

| Intent | Action |
|--------|--------|
| Clear fix request | Attempt fix, present for approval |
| Question | Flag for developer to respond |
| Discussion/opinion | Skip |
| Approval/praise | Skip |

## Phase 3 — Report

```markdown
## PR Feedback Fix Summary — PR #{pr_number}

### SonarQube ({n} fixed, {n} manual)
...
### CodeRabbit ({n} fixed, {n} replied, {n} manual)
...
### Human Reviews ({n} fixed, {n} flagged)
...

Ready to commit fixes? (y/n)
```

**Wait for user approval.**

## Phase 4 — Commit + Reply

### Commit

**Always create a NEW commit** — never amend.

```bash
git add {fixed_files}
git commit -m "[{namespace}-XXX] Fix PR feedback (iteration {n})"
git push
```

### Reply on PR

| Source | Strategy |
|--------|---------|
| SonarQube | No reply — re-scans automatically |
| CodeRabbit (fixed) | "Fixed in {sha} — {description}" |
| CodeRabbit (disagree) | Substantive reply |
| Human (fixed) | "Fixed in {sha} — {description}" |
| Human (skipped) | Developer handles manually |

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments/{comment_id}/replies \
  -f body="{reply_text}"
```

**Show all proposed replies to user before posting.**

## Phase 5 — Integration Tests (MANDATORY)

Run the project's test suite. If failures → stop and present options:
1. Fix failing tests (then re-run)
2. Revert last commit
3. Skip tests (at your own risk)

## Phase 6 — Iteration Check

```
All fixes committed, pushed, and tests passing.

1. Wait for CI and run again
2. Done — all feedback addressed
```

If option 1: restart from Phase 1 (iteration awareness skips handled comments).

## Dependencies

- `gh` CLI — for PR comments and replies
- `SONARQUBE_URL` + `SONARQUBE_TOKEN` — optional, for SonarQube
- Project test suite — for Phase 5
