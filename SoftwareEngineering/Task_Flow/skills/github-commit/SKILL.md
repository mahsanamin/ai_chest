---
name: github-commit
description: Create a clean, human-readable git commit. Say "commit" or "github commit" when you're ready to commit your changes.
disable-model-invocation: true
---

# GitHub Commit

Create clean, to-the-point commit messages that product people can read and engineers can learn from.

## Style

Write commits like a human, not a robot. No checklists, no bullet storms, no noise.

**Format:**
```
{Short summary - what changed and why, max 72 chars}

{Optional 1-2 sentences for tech context: what specifically changed
in the code, only if it adds value beyond the summary.}
```

**Good example:**
```
Fix payment failure when user switches currency mid-checkout

Updated currency conversion to lock rate at cart creation instead
of at payment time. Affects PaymentService and CurrencyProxy.
```

**Bad example (don't do this):**
```
feat(payment): implement currency rate locking mechanism with
transactional boundaries and proxy layer updates

- Updated PaymentService.java to add rate locking
- Modified CurrencyProxy.java to cache rates
- Added unit tests for rate locking
- Updated application.yml with new config
- Refactored error handling in PaymentController

Closes PROJ-123
```

## Execution Mode

This skill is context-aware — it picks the right approach automatically:

**Standalone (outside task-flow):**
Runs directly in the main session. You already have full conversation context. Do NOT delegate to an agent.

**Inside task-flow:**
task-flow Phase 4j handles this by invoking the `commit-writer` agent (Haiku) with explicit context from task files.

## CRITICAL: Always Ask, Never Auto-Execute

**NEVER commit or push automatically.** Every destructive git action requires explicit user approval:

1. **Show staged files** → Ask user to confirm what to include
2. **Show commit message** → Ask user to approve before committing
3. **After commit** → Ask user if they want to push (never auto-push)

## Instructions

1. **Read the template** at `docs/templates/commit-template.md` if it exists.

2. **Read config_hints.json** for project namespace.

3. **Check what changed:**
   - Run `git status` (never use -uall flag)
   - Run `git diff --staged` and `git diff`
   - Run `git log --oneline -5` to match the repo's commit style

4. **Stage files** — add specific files, never `git add -A` or `git add .`

5. **Draft the message** following the style above:
   - No ticket numbers unless the user asks
   - No `feat:`, `fix:`, `chore:` prefixes unless the repo already uses them
   - ALWAYS add `Co-Authored-By: Claude <noreply@anthropic.com>` as the last line

6. **Show the user** the proposed commit message and staged files. Wait for approval.

7. **Commit ONLY after explicit user approval.**

8. **After commit, ask about push** (never auto-push).

## What NOT to do

- Don't commit without showing the user first and getting approval
- Don't push without asking — EVER
- Don't add checklists or bullet lists of every file changed
- Don't use conventional commit prefixes unless the repo already does
- Don't write essays — if it needs more than 3 lines, the commit is too big
- Don't add emoji
