---
name: task-flow-setup:update
description: Update an existing Task Flow installation to the latest framework version. Auto-selects fast inline mode or full pipeline based on what changed. Say "task-flow-setup:update" or "update project".
disable-model-invocation: true
---

# Update Project

Incrementally update an existing Task Flow installation. Auto-selects the fastest update mode based on what actually changed.

## When to Use

- Project already has Task Flow installed (`.claude/config_hints.json` exists with `framework_version`)
- Framework version is newer than the project's installed version
- Periodic drift check even at same version
- If the project does NOT have `config_hints.json`, use `initialize-project` instead

## Prerequisites

- Working directory: Task Flow framework repo (this repo)
- Target project has `.claude/config_hints.json` with `framework_version` field

## Update Modes

Auto-selects the fastest mode:

| Mode | When | Speed |
|------|------|-------|
| **Inline** | All changes are skills/agents only | Fast — seconds |
| **Single-Agent** | Rules or templates changed, ≤10 total files | Medium |
| **Full Pipeline** | Major version jump, settings changed, or >10 files | Slow |

## Phase 1: Detect Changes

### 1a. Ask for Target Project

**CRITICAL: Use AskUserQuestion with ONLY a text field. Do NOT use selectable options, menus, numbered lists, or suggestions of any kind.**

Ask exactly this — one plain text question, nothing else:

```
What is the full path to your target project?
```

- **NEVER** pass `options` or `choices` to AskUserQuestion — use it in plain text-input mode only
- **NEVER** list directories, suggest paths, or show examples
- Just ask and wait for the user to type the full path

Validate the directory exists. Store as `TARGET_PROJECT`.

### 1b. Create Update Branch

Detect default branch and current state:
```bash
git -C {TARGET_PROJECT} symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'
```
```bash
git -C {TARGET_PROJECT} branch --show-current
```

If on default branch, offer to create `feature/task-flow-update`. If already on a feature branch, use it silently.

### 1c. Read Versions

```bash
jq -r '.framework_version // empty' {FRAMEWORK_PATH}/config_hints.json 2>/dev/null
```
```bash
jq -r '.framework_version // empty' {TARGET_PROJECT}/.claude/config_hints.json 2>/dev/null
```

If target has no `config_hints.json` → tell user to run `initialize-project` instead. Stop.

### 1d. Compare and Build Changed Files List

**If same version:** Do a Smart Diff to check for drift. If no differences → "Project is up to date." Stop.

**If framework is newer:** Compare installed files against framework source. Build list of files that differ.

### 1e. Categorize and Select Mode

Categorize each changed file:
- **skill_files** — `skills/` (maps to `.claude/skills/` in target)
- **agent_files** — `agents/` (maps to `.claude/agents/` in target)
- **rule_files** — `rules/` (maps to `{standards_dir}/` in target)
- **template_files** — `templates/`
- **settings_files** — `settings.json`

Mode selection:
- No rules/settings/templates changed → **Inline**
- ≤10 total installable files → **Single-Agent**
- Otherwise → **Full Pipeline**

### 1f. Present Summary

```
Your project: Task Flow v{PROJECT_VERSION}
Framework:    Task Flow v{FRAMEWORK_VERSION}

{N} files need updating. Update mode: {MODE}
Proceed? (y/n)
```

## Phase 2: Inline Mode (Skills/Agents Only)

No agents needed. Process each changed file directly:

**New files:** Copy from framework source.

**Existing files:** Read BOTH versions, apply Smart Diff:
- **PRESERVE**: Project-specific values, intentional overrides, formatting preferences
- **ADD**: New framework content (sections, steps, guardrails) missing from target
- **UPDATE**: Framework bug fixes the target still has
- **NEVER** replace project values with generic placeholders

Skip to Phase 5.

## Phase 3: Single-Agent Mode

One combined agent handles research, writing, and self-verification:

1. Quick stack check — confirm platform from config_hints.json against build files
2. Process each changed file with Smart Diff logic
3. Self-verify — scan for unreplaced placeholders, foreign-stack references
4. Report what was modified

Skip to Phase 5.

## Phase 4: Full Pipeline Mode

Parallel agents for large updates:

1. **Stack detection** — Re-analyze target project stack
2. **Parallel writers** — Structure Writer + Rules Writer process their file categories
3. **Config Writer** — Runs after writers complete, updates AGENTS.md/config
4. **Verification** — Independent scan for contamination

Cleanup temp files after verification passes.

## Phase 4b: Check for New/Updated Rule Templates

**After updating skills/agents/rules, check if AIRuleTemplates have new or updated content.**

AIRuleTemplates lives alongside Task_Flow in the repo, NOT inside it:
```
SoftwareEngineering/
├── AIRuleTemplates/    ← rule templates
├── Task_Flow/          ← this framework (FRAMEWORK_PATH)
```

```bash
REPO_ROOT=$(cd {FRAMEWORK_PATH}/.. && pwd)
TEMPLATES_PATH="$REPO_ROOT/AIRuleTemplates"
ls "$TEMPLATES_PATH/README.md" 2>/dev/null
```

If AIRuleTemplates exist:

1. **Read the target project's stack** from `config_hints.json` (platform, standards_location)
2. **Detect stack** from build files (same signals as initialize)
3. **Match template directories** using the same logic as initialize:
   - `universal/` → always
   - `backend/` → any backend project
   - `java-spring-boot/` → Java + Spring
   - `react-typescript/` → React + TS
   - `nextjs/` → Next.js
4. **For each matched template file**, compare against what's already in `{STANDARDS_DIR}/`:
   - **Missing** → New template not yet installed
   - **Differs** → Template was updated in framework
   - **Same** → Already up to date, skip
   - **Exists but not from template** (project-specific rule) → Never touch

5. **If new or updated templates found**, present to user:

```
Rule template updates available:

NEW:
  + backend/api-conventions.md — REST API validation & security patterns

UPDATED:
  ~ backend/query-efficiency.md — Added DataContext pattern section
  ~ universal/critical-thinking.md — Minor wording improvements

Already up to date: 4 templates

Install new and update changed templates? (y/n/customize)
```

- **y** → Install new, update changed (Smart Diff — preserve any project customizations)
- **n** → Skip templates
- **customize** → Pick individually

**Smart Diff for template updates:** When updating an existing template, preserve any project-specific customizations the developer added (e.g., custom examples, domain-specific rules appended at the end). Only add new framework sections and fix framework bugs — never overwrite project additions.

## Phase 5: Finalize (All Modes)

1. Update `framework_version` in `config_hints.json`
2. Update AGENTS.md footer with version and date
3. Update `.gitignore` if needed

**Summary:**
```
Updated Task Flow: v{PROJECT_VERSION} → v{FRAMEWORK_VERSION}
Mode: {inline/single-agent/full-pipeline}

Files updated:
- {file1} — {what changed}
...

{If templates installed/updated:}
Rule templates:
- {N} new templates installed
- {N} templates updated (project customizations preserved)

Verification: PASS
```

### Optional: Run AI Sanitizer

```
Update complete! Run AI Sanitizer to optimize? (y/n)
```
