---
name: github-pr
description: Create a pull request using the project's PR template. Say "pr" or "github pr" when ready to open a pull request.
disable-model-invocation: true
---

# GitHub PR

Create a pull request using the project's template and conventions.

## Execution Mode

This skill is context-aware:

**Standalone (outside task-flow):**
Runs directly in the main session. Do NOT delegate to an agent.

**Inside task-flow:**
task-flow Phase 4k handles this by invoking the `pr-writer` agent (Haiku).

## CRITICAL: Always Ask, Never Auto-Execute

**NEVER push or create PRs automatically.** Every action requires explicit user approval:

1. **Show PR content** → Ask user to review title and body
2. **Ask Draft or Ready** → Default to Draft PR (safer)
3. **Confirm push + create** → Ask user before pushing branch and creating PR

## Instructions

1. **Find the PR template** — check these locations in order:
   - `PULL_REQUEST_TEMPLATE.md` at project root
   - `.github/PULL_REQUEST_TEMPLATE.md`
   - `.github/pull_request_template.md`
   - `.github/PULL_REQUEST_TEMPLATE/default.md`
   - `docs/templates/pr-template.md` (framework fallback)

2. **Read config_hints.json** for project namespace and tracker configuration.

3. **Understand the full scope of changes:**
   - `git status`, `git log --oneline main..HEAD`, `git diff main...HEAD`

4. **Fill in the PR template** with real content:
   - Context: plain language, link to ticket
   - Approach: brief technical approach, trade-offs
   - Testing: what was tested
   - Checklist: fill in honestly
   - **Footer:**
     ```
     ---
     Generated with [Claude Code](https://claude.ai/code) by Anthropic

     Co-Authored-By: Claude <noreply@anthropic.com>
     ```

5. **Show the user** and ask for PR type (default: Draft).

6. **Create the PR only after explicit approval** using `gh pr create`.

7. **Return the PR URL** to the user.

## PR Title Style

Keep it short and human-readable:
- `Fix payment failure on currency switch` (good)
- `feat(payment): implement currency rate locking mechanism` (too robotic)

Match the repo's existing PR title style — check `gh pr list --limit 5` if unsure.

## Default Template (if no project template found)

```markdown
### Context
- {What this PR does and why}
- {Link to issue tracker if applicable}

### Approach
- {Brief technical approach}
- {Trade-offs if any}

### Testing
- {What was tested}
```

## Log PR in Task Folder

After creating the PR, if a task folder exists, add a `## Pull Request` section to `execution-summary.md`.

## What NOT to do

- Don't push or create PR without explicit user approval — EVER
- Don't default to "Ready for Review" — always default to Draft
- Don't write a novel — keep sections brief and scannable
- Don't list every file changed (that's what the diff is for)
- Don't blindly check all boxes in the checklist
