---
name: aa-commit
description: Create a clean, human-readable git commit. Say "aa-commit" or "commit" when you're ready to commit your changes.
disable-model-invocation: false
---

# GitHub Commit

Create clean, to-the-point commit messages that product people can read and engineers can learn from.

## Style

Write commits like a human, not a robot. No checklists, no bullet storms, no noise.

**Format:**
```text
{Short summary - what changed and why, max 72 chars}

{Optional 1-2 sentences for tech context: what specifically changed
in the code, only if it adds value beyond the summary.}
```

**Good example:**
```text
Fix payment failure when user switches currency mid-checkout

Updated currency conversion to lock rate at cart creation instead
of at payment time. Affects PaymentService and CurrencyProxy.
```

**Bad example (don't do this):**
```text
feat(payment): implement currency rate locking mechanism with
transactional boundaries and proxy layer updates

- Updated the payment service to add rate locking
- Modified the currency proxy to cache rates
- Added unit tests for rate locking
- Updated app config with new settings
- Refactored error handling in the payment controller

Closes {namespace}-123
```

## Execution Mode

This skill is context-aware — it picks the right approach automatically:

**Standalone (outside aa-task-flow):**
Runs directly in the main session. You already have full conversation context — you know what was discussed, what the user built, and why. Use that context to write a great commit message. Do NOT delegate to an agent.

**Inside aa-task-flow:**
aa-task-flow Phase 4j handles this by invoking the `aa-commit-writer` agent (Haiku) with explicit context from task files. The skill itself is not called — aa-task-flow uses the agent directly.

## CRITICAL: Always Ask, Never Auto-Execute

**NEVER commit or push automatically.** Every destructive git action requires explicit user approval:

1. **Show what files to stage** → Ask user to confirm what to include
2. **Show commit message** → Ask user to approve before committing
3. **After commit** → Ask user if they want to push (never auto-push)

The user must explicitly say "yes", "approve", "go ahead", or similar before any git write operation.

**Exception — autonomous permission posture:** if the project has moved `git add`/`commit`/`push` into the `allow` list in `.claude/settings.json`, the prompts above can no longer gate anything — so don't keep asking, but don't commit noisily either. Commit **deliberately at meaningful logical checkpoints**, not after every small edit: fewer, well-scoped commits with careful messages, the same quality bar the human checkpoint used to enforce. Narrate *"Committing at checkpoint: {what}"* instead of *"May I commit?"*. Force-push stays forbidden regardless. See aa-task-flow's "Rule 5: Commit/PR Permission Posture" for the full guidance.

## Instructions

1. **Read the template** at `docs/templates/commit-template.md` if it exists — follow the project's conventions.

2. **Read config_hints.json** for project namespace:
   ```bash
   cat .claude/config_hints.json
   ```

3. **Check what changed:**
   - Run `git status` (never use -uall flag)
   - Run `git diff --staged` to see staged changes
   - Run `git diff` to see unstaged changes
   - Run `git log --oneline -5` to match the repo's commit style

4. **Stage files** — add specific files, never `git add -A` or `git add .`:
   - Skip `.env`, credentials, large binaries
   - Ask user if unsure what to include

5. **Draft the message** following the style above:
   - Use your conversation context — you know WHY these changes were made
   - First line: what changed, for anyone (product, QA, engineer)
   - Body (optional): brief tech context — what files/components, only if helpful
   - Ticket reference: include one only if the repo's convention uses it — check recent commits and the project's commit template / `AGENTS.md` commit convention. If they prefix a ticket ID (e.g. `OPS-123: ...`), match that, extracting the ID from the branch name when available; otherwise omit. Never invent a ticket number.
   - No `feat:`, `fix:`, `chore:` prefixes unless the repo already uses them
   - ALWAYS add `Co-Authored-By: Claude <noreply@anthropic.com>` as the last line (after a blank line)

6. **Show the user** the proposed commit message and staged files. Ask:
   ```text
   Proposed commit:

   {commit message}

   Files to commit:
   - {file1}
   - {file2}

   Commit these changes? (yes/no)
   ```

7. **Commit per the permission posture** (see the Exception block above / aa-task-flow Rule 5):
   - *Explicit-approval (default `ask`):* commit ONLY after explicit user approval of step 6.
   - *Autonomous allow-list (`git add`/`commit`/`push` in `allow`):* don't ask — narrate *"Committing at checkpoint: {what}"* and proceed, committing deliberately at meaningful logical checkpoints to the same quality bar the approval gate enforced.

8. **Push per the permission posture** (never force-push):
   - *Default (`push` gated by `ask`, or absent from `allow`):* after committing, ask before pushing:
     ```text
     Committed to `{branch}`.

     Push to remote? (yes/no)
     ```
   - *Autonomous (`push` in the `allow` list):* the prompt can no longer gate anything, so push without re-asking — narrate *"Pushing {branch}"*. Force-push stays forbidden regardless.

## What NOT to do

- Under the default `ask` posture: don't commit without showing the user first and getting approval, and don't push without asking. Under the autonomous allow-list posture, narrate and proceed per the Exception block / aa-task-flow Rule 5. Force-push stays forbidden in both postures.
- Don't add checklists or bullet lists of every file changed
- Don't use conventional commit prefixes unless the repo already does
- Don't write essays — if it needs more than 3 lines (excluding Co-Authored-By), the commit is too big
- Don't add emoji
