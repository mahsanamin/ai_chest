---
name: aa-pr
description: Create a pull request using the project's PR template. Say "aa-pr" or "pr" when ready to open a pull request.
disable-model-invocation: false
---

# GitHub PR

Create a pull request using the project's template and conventions.

## Execution Mode

This skill is context-aware — it picks the right approach automatically:

**Standalone (outside aa-task-flow):**
Runs directly in the main session. You already have full conversation context — you know what was built, the approach, trade-offs, and testing done. Use that context to write a great PR. Do NOT delegate to an agent.

**Inside aa-task-flow:**
aa-task-flow Phase 4k handles this by invoking the `aa-pr-writer` agent (Haiku) with explicit context from task files. The skill itself is not called — aa-task-flow uses the agent directly.

## CRITICAL: Always Ask, Never Auto-Execute

**NEVER push or create PRs automatically.** Every action requires explicit user approval:

1. **Show PR content** → Ask user to review title and body
2. **Ask Draft or Ready** → Default to Draft PR (safer)
3. **Confirm push + create** → Ask user before pushing branch and creating PR

The user must explicitly say "yes", "approve", "go ahead", or similar before any action.

**Exception — autonomous permission posture:** if the project has moved `git push` / `gh pr create` into the `allow` list in `.claude/settings.json` (the prompts can no longer gate anything), don't keep asking — but don't get sloppier either. Create the PR carefully: correct base branch, complete template-filled body, only when the work is genuinely PR-ready, narrating *"Creating PR against {base}: {title}"*. Treat the removed prompt as "act with the care a reviewer would," not "act faster." Force-push stays forbidden regardless. See aa-task-flow's "Rule 5: Commit/PR Permission Posture" for the full guidance.

## Instructions

1. **Find the PR template** — check these locations in order (use the first one found):
   - `PULL_REQUEST_TEMPLATE.md` at project root (GitHub standard)
   - `.github/PULL_REQUEST_TEMPLATE.md`
   - `.github/pull_request_template.md`
   - `.github/PULL_REQUEST_TEMPLATE/default.md`
   - `docs/templates/pr-template.md` (framework fallback)

   If a template is found, use it. If none exists, use the default format below.

2. **Read config_hints.json** for project namespace and Atlassian URL:
   ```bash
   cat .claude/config_hints.json
   ```

3. **Detect base branch:**
   ```bash
   # Detect the default branch (main or master)
   base_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
   if [ -z "$base_branch" ]; then
     # Verify each candidate exists rather than assuming master — fail clearly if neither does.
     if git rev-parse --verify origin/main >/dev/null 2>&1; then base_branch="main"
     elif git rev-parse --verify origin/master >/dev/null 2>&1; then base_branch="master"
     else echo "ERROR: cannot determine base branch (neither origin/main nor origin/master exists). Pass it explicitly." >&2; exit 1; fi
   fi
   ```

4. **Understand the full scope of changes:**
   - Run `git status` (never use -uall flag)
   - Run `git log --oneline $base_branch..HEAD` to see all commits in this branch
   - Run `git diff $base_branch...HEAD` to see the full diff against base
   - Check if branch is pushed: `git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null`

5. **Fill in the PR template** with real content:

   **Context section:**
   - What this PR does in plain language (product people will read this)
   - Link to the ticket per tracker: `#{number}` for github, `https://{tracker_url}/browse/{namespace}-XXX` for jira (Tracker Dispatch Table in `rules/universal/mcp-integration.md`)
   - Why the change is needed

   **Approach section:**
   - Brief technical approach — what components changed and why
   - Any trade-offs or alternatives considered
   - Keep it concise, no need to list every file

   **Testing section:**
   - What was tested and how
   - Mention if tests were added/updated

   **Checklist:**
   - Fill in honestly — don't blindly check everything

   **Footer (always add at the end of the PR body):**
   ```
   ---
   Generated with [Claude Code](https://claude.ai/code) by Anthropic

   Co-Authored-By: Claude <noreply@anthropic.com>
   ```

6. **Show the user** the PR content and ask for PR type:
   ```
   Proposed PR:

   Title: {title}

   Body:
   {filled template content}

   PR type:
   1. Draft PR (Recommended) — not ready for review yet
   2. Ready for Review — request reviewers immediately

   Create this PR? (1/2/no)
   ```

   **Default is Draft PR** if user just says "yes" without specifying.

7. **Create the PR per the permission posture** (see the Exception block above / aa-task-flow Rule 5):
   - *Explicit-approval (default `ask`):* push and create the PR ONLY after the user approves step 6.
   - *Autonomous allow-list (`git push` / `gh pr create` in `allow`):* don't ask — narrate *"Creating PR against {base}: {title}"* and proceed, but only when the work is genuinely PR-ready, with the correct base branch and a complete template-filled body. Force-push stays forbidden in both postures.
   - Push branch if not already pushed: `git push -u origin {branch_name}`
   - Use `gh pr create` with the filled template
   - Use `--draft` flag for Draft PRs (the default)
   - Use a HEREDOC for the body to preserve formatting:
   ```bash
   # Draft PR (default)
   gh pr create --draft --title "{title}" --body "$(cat <<'EOF'
   {filled template content}
   EOF
   )"

   # Ready for Review (only if user explicitly chose option 2)
   gh pr create --title "{title}" --body "$(cat <<'EOF'
   {filled template content}
   EOF
   )"
   ```

8. **Return the PR URL** to the user. If it's a draft, remind them:
   ```
   Draft PR created: {url}

   When ready for review, run: gh pr ready
   ```

## PR Title Style

Keep it short and human-readable:
- `Fix payment failure on currency switch` (good)
- `feat(payment): implement currency rate locking mechanism` (too robotic)
- `{namespace}-123: Fix payment` (ok if repo convention includes ticket number)

Match the repo's existing PR title style — check `gh pr list --limit 5` if unsure.

## Default Template (if no project template found)

```markdown
### Context
- {What this PR does and why}
- {Link to Jira/Figma/Sentry if applicable}

### Approach
- {Brief technical approach}
- {Trade-offs if any}

### Testing
- {What was tested}
```

## Log PR in Task Folder

After creating the PR, check if the current branch's task folder exists in OnGoingTasks/ (by matching branch name or ticket ID against folder names). If found, add a `## Pull Request` section **at the top** of `execution-summary.md`:

```markdown
## Pull Request
- **PR:** #{number} — {title}
- **URL:** {pr_url}
- **Status:** Draft / Open
```

If `execution-summary.md` doesn't exist, create it with just the PR section.

**Why:** `aa-pr` can be invoked standalone (outside aa-task-flow). The PR should still be logged for inspector traceability.

## What NOT to do

- Under the default `ask` posture, don't push or create a PR without explicit user approval (under the autonomous allow-list posture, narrate and proceed per the Exception block / aa-task-flow Rule 5). Force-push stays forbidden in both postures.
- Don't default to "Ready for Review" — always default to Draft
- Don't write a novel — keep sections brief and scannable
- Don't list every file changed (that's what the diff is for)
- Don't blindly check all boxes in the checklist
