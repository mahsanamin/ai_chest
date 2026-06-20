# AI Awareness Framework — Quick Reference

You're operating on a machine with the AI Awareness framework installed. This file is installed at `~/.claude/aa-framework-hints.md` by the framework's `install-tools.sh`. It is referenced from `~/.claude/CLAUDE.md` so every Claude Code session picks it up. Don't edit it manually — re-run the installer to refresh.

## Global skills (available in any project)

These live at `~/.claude/skills/` and are invocable by the user (slash command or by naming the skill in the prompt). `aa-optimizer` and `aa-global-pr-reviewer` carry `disable-model-invocation: true` — the model does NOT auto-invoke them; invocation is user-driven. `aa-record-improvement` is `disable-model-invocation: false` so the model CAN invoke it mid-task to capture an improvement the moment a correction or limitation surfaces (it stays user-invocable too).

- **aa-optimizer** — Audit a project's rule files for redundancy, `alwaysApply` overuse, and stale references.
- **aa-record-improvement** — Capture a framework-improvement suggestion from inside any project. Writes a structured file to the workspace's `_AIAwarenessFramework/improvements/` for later triage.
- **aa-global-pr-reviewer** — Review any GitHub PR from anywhere on the machine. Clones the target repo, sets up a review worktree, runs the project's tests (best-effort), reviews changed code against the project's rules, dedups against existing PR comments, and posts inline review comments with fix suggestions.

## Shell helpers (sourced into the user's interactive shell)

These live at `~/.claude/scripts/` and are sourced by the user's `.zshrc`/`.bashrc` on terminal open. Two important consequences:

- **In interactive terminals** (the user's own shell), call them by name: `aa_g_worktree_init`, `aa_g_worktree_list`, etc.
- **From Claude Code's Bash tool** (which is non-interactive — `.zshrc` is NOT sourced), shell functions like `aa_g_worktree_init` are NOT in scope. To invoke them from Claude Code, run the companion script under `~/.claude/scripts/aa-worktree/` directly: `bash ~/.claude/scripts/aa-worktree/aa_g_worktree_init <branch>` (note: the non-interactive form does NOT auto-cd into the new worktree).

### `aa_g_worktree_*` — worktree management

**Prefer these over raw `git worktree` commands** when the user asks about worktrees. They auto-cd, validate branch names, integrate with the framework's `story/*` branch convention, and handle a large monorepo-with-many-worktrees topology.

| Helper | Use when |
|---|---|
| `aa_g_worktree_init <branch> [-b <base>]` | Creating a new worktree — auto-detects `story/*` branches as base candidates |
| `aa_g_worktree_review <pr-number\|branch> [-r <remote>]` | Reviewing a teammate's PR or remote branch (creates `review-` prefixed worktree) |
| `aa_g_worktree_list` | Listing worktrees as a box-drawing table (state, ahead/behind, dirty, last-commit age) |
| `aa_g_worktree_remove <worktree>` | Removing a worktree with merge-verification + protected-branch safeguards |
| `aa_g_worktree_doctor` | Read-only health audit (stale registrations, dirty, merged, no-upstream) |
| `aa_g_worktree_prune` | Safe pruning with dry-run preview + Y/N confirmation |
| `aa_g_worktree_main` | Returning to the main repo from any worktree |
| `aa_g_worktree_switch <name>` | Switching to a named worktree |

**Examples (always prefer the helper form):**

- ❌ `git worktree add ~/Repos/foo/wt-feature-x feature/X`
- ✓ `aa_g_worktree_init feature/X`

- ❌ `git worktree add review-pr-123 origin/feature-branch && cd review-pr-123 && git checkout -b review-feature-branch`
- ✓ `aa_g_worktree_review 123`

- ❌ `git worktree list` (raw output, hard to scan)
- ✓ `aa_g_worktree_list` (formatted table with state + ahead/behind)

### When raw `git worktree` is still correct

- The user explicitly asks for the canonical `git worktree` command (e.g., for a runbook they're authoring).
- The helper isn't installed (check `command -v aa_g_worktree_init` — rare).
- An exotic option the helpers don't support: `--lock`, `--track`, `--detach` against a specific commit, etc. The helpers are pragmatic ergonomics, not a `git worktree` superset.

## Framework freshness

`~/.claude/scripts/aa-freshness/check.sh` is sourced from shell-rc and runs once per 24h. It nudges the user when the framework is behind `origin/main`, has been pulled but not re-installed, or has new global skills available. Silent when current. To re-check on demand: `aa_check_freshness --force`.

## Project-level rules

The framework also installs project-level rules into each project (via `aa-install`/`aa-upgrade`). When working in a specific project, also read its `CLAUDE.md`, `AGENTS.md`, `docs/ai-rules/`, and `.claude/ai-rules/` — project-level rules override these global hints when they conflict.

## Refreshing

To refresh this file + the helpers + skills:

```
(cd "$AA_FRAMEWORK_DIR" && git pull && ./install-tools.sh)
```

`$AA_FRAMEWORK_DIR` is exported by the framework's shell-rc block.
