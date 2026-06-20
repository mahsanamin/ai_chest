---
name: aa-install-tools
description: Install or update global framework scripts and agents on your machine. Every developer should run this once. Say "aa-install-tools" or "setup tools".
disable-model-invocation: true
---

# Initialize Tools

Installs framework scripts and agents globally to `~/.claude/` so they're available system-wide on this developer's machine.

This skill is a **thin wrapper around `install-tools.sh`** at the framework repo root. The shell script is the canonical implementation — it can be run on its own without Claude Code:

```bash
cd ~/ai-awareness-framework
./install-tools.sh
```

Teammates who don't use the Claude Code skill should run the shell script directly after `git pull`.

## When to Run

- First time a developer starts using AI Awareness (one-time setup on each developer's machine).
- After a framework update adds new scripts or agents.
- If shell startup prints "Framework is N commit(s) behind" — that's the freshness check in `worktree.sh` telling you a teammate has pushed new tools.

## Prerequisites

- Working directory: the framework repo root (this script's parent directory).
- `jq` installed (`brew install jq`).

## What Gets Installed

| Source (framework repo) | Destination (per-developer global) |
|---|---|
| `scripts/**` declared in `scripts/manifest.json` | `~/.claude/scripts/` |
| `agents/*/AGENT.md` | `~/.claude/agents/{name}.md` |
| `skills/aa-optimizer/` | `~/.claude/skills/aa-optimizer/` |
| `skills/aa-record-improvement/` | `~/.claude/skills/aa-record-improvement/` |
| (managed block) | `~/.zshrc` or `~/.bashrc` — exports `AA_FRAMEWORK_DIR` and sources `worktree.sh` |

## Steps

### 1. Run the installer

```bash
bash "{FRAMEWORK_PATH}/install-tools.sh"
```

That's it. The script handles everything:

- Reads `scripts/manifest.json` and copies every script with `install: "global"` or `install: "sourced"` to `~/.claude/scripts/` (preserving subdir structure, marking `.sh` files executable).
- Copies every `agents/*/AGENT.md` to `~/.claude/agents/{name}.md`.
- Refreshes every entry in `scripts/manifest.json`'s `global_skills` array (currently `aa-optimizer`, `aa-record-improvement`, `aa-global-pr-reviewer`).
- Updates the marker-guarded block in the user's shell-rc (idempotent — refreshed in place if present, appended if absent). The block exports `AA_FRAMEWORK_DIR` so other tools can locate the framework repo, and sources every `install: "sourced"` script.
- Strips any legacy `# >>> AI Awareness sourced helpers (managed by aa-install-tools) >>>` block from older installs so there's only ever one managed block in the shell-rc.

### 2. Report what was installed

The script prints each file as it's copied. After it completes, surface the bottom line back to the user:

```
Tools synced from {FRAMEWORK_PATH} → ~/.claude/

Open a new terminal (or `source ~/.zshrc`) for sourced helpers to take effect.
```

### 3. Generate evals for global skills (skill-creator — MANDATORY)

For each global skill that was installed/updated (`manifest.json` → `global_skills`), create/refresh its eval set per `setup.md` Step 16c — invoke `skill-creator`, store under `~/.claude/skills/<name>/evals/`, run once for a baseline. Only changed skills need a refresh — **plus a backfill pass:** any manifest global skill in `~/.claude/skills/` with no `evals/evals.json` gets one generated (never overwrite an existing set; re-runs are a no-op). **`skill-creator` is a required prerequisite:** detect it by whether `skill-creator:skill-creator` is in this session's available skills — it's a **plugin, not a global skill**, so never test for `~/.claude/skills/skill-creator/` (false "missing"); for a filesystem check look in `~/.claude/plugins/installed_plugins.json`. If genuinely missing, **STOP** and guide the user with Step 16c's install instructions (skip the `marketplace add` line if `claude-plugins-official` is already in `~/.claude/plugins/known_marketplaces.json`), then re-run this step.

## Migration notes

- Pre-v6.0.0 global tools (e.g., `~/.claude/skills/ai-sanitizer/`) are no longer auto-deleted by this skill. They were cleaned up during the v6.0.0 → v7.0.0 upgrades. If a stray legacy directory survives, remove it manually — `install-tools.sh` is intentionally non-destructive outside of the files it owns.
