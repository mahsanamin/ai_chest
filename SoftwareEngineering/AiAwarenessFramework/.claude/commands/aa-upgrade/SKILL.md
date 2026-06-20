---
name: aa-upgrade
description: Update an existing AI Awareness installation to the latest framework version. Auto-selects fast inline mode or full pipeline based on what changed. Say "aa-upgrade" or "upgrade AI awareness".
disable-model-invocation: true
---

# Update Project

Incrementally update an existing AI Awareness installation. Auto-selects the fastest update mode based on what actually changed.

## When to Use

- Project already has AI Awareness installed (`.claude/config_hints.json` exists with `framework_version`)
- Framework version is newer than the project's installed version
- Periodic drift check even at the same version
- If the project does NOT have `config_hints.json`, use `aa-install` instead

## Prerequisites

- Working directory: `~/ai-awareness-framework` (framework repo)
- Target project has `.claude/config_hints.json` with `framework_version` field

## Update Modes

The skill auto-selects the fastest mode that can handle the changes:

| Mode | When | Agents | Speed |
|------|------|--------|-------|
| **Inline** | All changes are skills/agents only (no rules, no settings, no templates) | 0 | Fast — seconds |
| **Single-Agent** | Rules or templates changed, but ≤10 total files | 1 | Medium — under a minute |
| **Full Pipeline** | Major version jump, settings changed, or >10 files | 3-5 | Slow — several minutes |

## Phase 1: Detect Changes

This phase runs in the **main session**.

**Bash execution rule:** Run each bash command individually — do NOT chain commands with `&&` or `;`. Use absolute paths instead of `cd` + relative paths.

### 1a. Ask for Target Project

**🚨 CRITICAL: Ask ONLY this single free-text question. Do NOT present a menu, numbered list, or suggested paths. No "Current directory" option. No "Choose from:" option. Just this one line:**

```
What is the full path to your target project?
```

Wait for the user to type the actual path. Validate the directory exists. Store as `TARGET_PROJECT`.

### 1a-2. Detect Linked AI Awareness Installs (NEW in v6.6.1)

A team typically has **two linked AI Awareness installs**: the code repo (where `aa-task-flow`, `aa-review-pr`, etc. run) and the workspace/tasks repo (where `aa-task-flow-progress-fixer`, `aa-weekly-report`, `aa-task-flow-remember` run). Each has its own `.claude/config_hints.json` and `.claude/skill.config` and they drift independently if upgraded one at a time. This step detects the linked install and offers to queue it for the same upgrade run.

```bash
# Read the target's skill.config to find linked paths
SKILL_CONFIG="$TARGET_PROJECT/.claude/skill.config"
LINKED_TARGETS=()

if [ -f "$SKILL_CONFIG" ]; then
  tasks_root=$(jq -r '.paths.tasks_root // ""' "$SKILL_CONFIG")
  docs_root=$(jq -r '.paths.docs_root // ""' "$SKILL_CONFIG")

  # For each path, walk up looking for a sibling .claude/config_hints.json + .claude/skill.config
  # Use a small helper that walks parents up to 3 levels
  find_install_root() {
    local p="$1"
    [ -z "$p" ] && return
    p=$(cd "$p" 2>/dev/null && pwd) || return
    # Walk up: $p, dirname($p), dirname(dirname($p))
    for i in 0 1 2 3; do
      if [ -f "$p/.claude/config_hints.json" ] && [ -f "$p/.claude/skill.config" ]; then
        echo "$p"
        return 0
      fi
      p=$(dirname "$p")
      [ "$p" = "/" ] && return 1
    done
    return 1
  }

  for candidate_path in "$tasks_root" "$docs_root"; do
    [ -z "$candidate_path" ] && continue
    install_root=$(find_install_root "$candidate_path")
    if [ -n "$install_root" ] && [ "$install_root" != "$TARGET_PROJECT" ]; then
      # Deduplicate
      already_listed=false
      for existing in "${LINKED_TARGETS[@]}"; do
        [ "$existing" = "$install_root" ] && already_listed=true && break
      done
      [ "$already_listed" = false ] && LINKED_TARGETS+=("$install_root")
    fi
  done
fi

# Set scalar LINKED_WORKSPACE_PATH used by Step 5d-2 audit routing and setup.md Step 15c.
# This is the linked install whose install_role is "workspace" — the audit-trail destination
# for code-repo upgrades. Code-repo upgrades read this to find where to append the audit entry.
# (v6.10.0 referenced this variable but never set it — code-repo audit-write was silently a no-op
# from v6.10.0 until this v7.0.0 fix.)
LINKED_WORKSPACE_PATH=""
for linked in "${LINKED_TARGETS[@]}"; do
  linked_role=$(jq -r '.install_role // ""' "$linked/.claude/config_hints.json" 2>/dev/null)
  if [ "$linked_role" = "workspace" ]; then
    LINKED_WORKSPACE_PATH="$linked"
    break
  fi
done
```

**If `LINKED_TARGETS` is non-empty, present each with its detected `framework_version` and ask once:**

```
This project's .claude/skill.config points to additional AI Awareness installs:

{For each linked install:}
  - {linked_path}
    framework_version: {jq -r .framework_version on that install's config_hints.json — or "unversioned" if missing}

Upgrade those too in this run?

1. Yes — queue them and process all targets sequentially (recommended)
2. No — only upgrade the path I gave

Your choice?
```

**If 1:** push each linked install into a `UPGRADE_QUEUE`. Process the original `TARGET_PROJECT` first (so its upgraded `skill.config` is the source of truth if anything changes), then iterate the queue, re-running Phases 1c through 5 against each in turn. Each iteration uses its own `_install_manifest.json`. Workspace installs append a compact entry to `dirname({install})/{ProjectName}_AIAwarenessFramework/update-history.md`; code-repo installs don't write an audit file. The final user-facing summary aggregates across all targets.

**If 2:** proceed with only the original target. Note in the final summary: "Linked installs detected but skipped at user request: {list}. Run aa-upgrade on each manually."

**If `LINKED_TARGETS` is empty:** proceed silently — no prompt, no noise.

### 1a-3. Detect install_role for the primary target (NEW in v6.7.0)

`install_role` must be known before Step 1b so we can decide whether to create a feature branch. Workspace installs commit directly to their default branch — they do not use feature branches or PRs. Creating one for a workspace install hides the upgrade commit on a branch the team doesn't look at.

Resolve `INSTALL_ROLE` now:

```bash
# Use the value persisted in config_hints.json if present; otherwise auto-detect.
INSTALL_ROLE=$(jq -r '.install_role // ""' "{TARGET_PROJECT}/.claude/config_hints.json" 2>/dev/null)
if [ -z "$INSTALL_ROLE" ] || [ "$INSTALL_ROLE" = "auto" ] || [ "$INSTALL_ROLE" = "null" ]; then
  # See setup.md Step 4c for the detect_install_role helper definition.
  INSTALL_ROLE=$(detect_install_role "{TARGET_PROJECT}")
fi
echo "Install role (primary target): $INSTALL_ROLE"
```

**For each entry in `LINKED_TARGETS` (from Step 1a-2):** resolve its own `install_role` the same way and store as `LINKED_INSTALL_ROLES[i]`. Each linked target will use ITS OWN role when we re-run Phase 1b–5 for it, not the primary's.

(Step 1d-2 below still runs per-target during the main loop, as a confirmation point and to persist the resolved role into `config_hints.json` post-upgrade.)

### 1b. Create Update Branch — code-repo installs only

**Workspace installs skip this step.** Workspace/docs/tasks repos commit directly to their default branch and rely on the Docs Auto-Push convention. Creating a feature branch for them hides the upgrade commits where the team won't see them.

```bash
if [ "$INSTALL_ROLE" = "workspace" ]; then
  current_branch=$(git -C {TARGET_PROJECT} branch --show-current)
  default_branch=$(git -C {TARGET_PROJECT} symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
  [ -z "$default_branch" ] && default_branch="main"

  if [ "$current_branch" != "$default_branch" ]; then
    # User is on some other branch in a workspace install — could be a leftover
    # feature branch from a buggy pre-v6.7.0 aa-upgrade run that wrongly created one.
    echo "⚠️  Workspace install is on branch '$current_branch', not '$default_branch'."
    echo "    Workspace installs are meant to track the default branch directly."
    echo "    Before proceeding, please either:"
    echo "      1. Switch to $default_branch and merge any pending changes from $current_branch"
    echo "      2. Confirm you intentionally want to upgrade on $current_branch"
    echo ""
    # Ask, don't auto-switch — branch state is too sensitive to flip silently.
    read -p "    Proceed on $current_branch anyway? (y/n) " ans
    [ "$ans" != "y" ] && echo "Aborted. Switch to $default_branch and re-run aa-upgrade." && exit 1
  fi

  echo "Workspace install — staying on branch '$current_branch' (no feature branch created)."

else
  # code-repo install — original branch-creation flow
  default_branch=$(git -C {TARGET_PROJECT} symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
  [ -z "$default_branch" ] && default_branch="main"
  current_branch=$(git -C {TARGET_PROJECT} branch --show-current)
  DEFAULT_BRANCH="$default_branch"
  CURRENT_BRANCH="$current_branch"
fi
```

**For code-repo installs only** (`INSTALL_ROLE = code-repo`):

**If CURRENT_BRANCH != DEFAULT_BRANCH:** The user is already on a feature branch. Use it silently:
```
Using current branch: {CURRENT_BRANCH}
```
Skip the branch creation prompt entirely.

**If CURRENT_BRANCH == DEFAULT_BRANCH:** Ask the user:
```
You're on {DEFAULT_BRANCH}. Updates should be applied on a dedicated branch.

1. Create feature/ai-awareness-update from latest {DEFAULT_BRANCH} (Recommended)
2. Use a different branch name
3. Continue on {DEFAULT_BRANCH} anyway

Your choice?
```

**If choice 1 or 2:** Run these commands individually:
```bash
git -C {TARGET_PROJECT} pull origin {DEFAULT_BRANCH}
```
```bash
git -C {TARGET_PROJECT} checkout -b feature/ai-awareness-update
```

**If choice 3:** Continue on the default branch (user's choice).

### 1c. Validate Prerequisites

Follow `setup.md` Step 1 (Validate Prerequisites):
- Check GitHub CLI
- Validate framework files exist
- Install/update AI Optimizer skill globally
- Install/update framework agents globally to `~/.claude/agents/`
- Install/update framework scripts globally to `~/.claude/scripts/` (`chmod +x` all `.sh` files)

### 1c-migration. Migrate Old Names (if needed)

Rename/remove old framework components in the target project and in `~/.claude/` using `{FRAMEWORK_PATH}/migration.json`. Global agent deletions are fingerprint-guarded — unmatched files are kept for manual review.

**Schema:** `migration.json` contains a `renames` array. Each entry has:
- `version` — the framework version that introduced the rename
- `applies_to` — semver range; entry applies if the project's current `framework_version` matches (currently only `< X.Y.Z` is supported)
- `skills`, `agents`, `global_skills`, `global_agents` — rename maps (`null` value = removed/moved to global)

Walk the array, apply entries whose `applies_to` covers `PROJECT_VERSION`. Idempotent — if the source directory no longer exists, the rename is silently skipped.

```bash
MIGRATION_FILE="{FRAMEWORK_PATH}/migration.json"
TARGET="{TARGET_PROJECT}"
FINGERPRINT='task-flow|github-pr|github-commit|execution_plan\.md|prompt-understanding\.md|project|commit message writer|PR content writer|test execution agent running in the background'

# Helper: returns 0 (true) if $1 is strictly less than $2 in semver order
version_lt() {
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ] && [ "$1" != "$2" ]
}

# Iterate each rename entry; apply only those whose applies_to covers PROJECT_VERSION
jq -c '.renames[]?' "$MIGRATION_FILE" | while IFS= read -r entry; do
  applies_to=$(echo "$entry" | jq -r '.applies_to // ""')
  entry_version=$(echo "$entry" | jq -r '.version // "?"')

  # Only `< X.Y.Z` form is supported for now
  if [[ "$applies_to" =~ ^[[:space:]]*\<[[:space:]]*([0-9.]+)[[:space:]]*$ ]]; then
    threshold="${BASH_REMATCH[1]}"
    if ! version_lt "$PROJECT_VERSION" "$threshold"; then
      echo "Skip migration entry v$entry_version (applies_to '$applies_to' — project is at $PROJECT_VERSION)"
      continue
    fi
  else
    echo "Warning: migration entry v$entry_version has unsupported applies_to '$applies_to' — skipping"
    continue
  fi

  echo "Applying migration entry v$entry_version (project at $PROJECT_VERSION, $applies_to)"

  # --- Project-level skills ---
  echo "$entry" | jq -r '.skills // {} | to_entries[] | [.key, (.value // "")] | @tsv' | \
    while IFS=$'\t' read -r old new; do
      old_dir="$TARGET/.claude/skills/$old"
      [ -d "$old_dir" ] || continue
      if [ -z "$new" ]; then
        rm -rf "$old_dir"
        echo "  Removed: .claude/skills/$old (moved to global or removed)"
      else
        new_dir="$TARGET/.claude/skills/$new"
        if [ -e "$new_dir" ]; then
          echo "  Skip: .claude/skills/$new already exists"
        else
          mv "$old_dir" "$new_dir"
          echo "  Renamed: .claude/skills/$old -> .claude/skills/$new"
        fi
      fi
    done

  # --- Project-level agents ---
  echo "$entry" | jq -r '.agents // {} | to_entries[] | [.key, (.value // "")] | @tsv' | \
    while IFS=$'\t' read -r old new; do
      old_dir="$TARGET/.claude/agents/$old"
      [ -d "$old_dir" ] || continue
      if [ -z "$new" ]; then
        rm -rf "$old_dir"
        echo "  Removed: .claude/agents/$old"
      else
        new_dir="$TARGET/.claude/agents/$new"
        if [ -e "$new_dir" ]; then
          echo "  Skip: .claude/agents/$new already exists"
        else
          mv "$old_dir" "$new_dir"
          echo "  Renamed: .claude/agents/$old -> .claude/agents/$new"
        fi
      fi
    done

  # --- Global skills (replaced by aa- prefixed versions — safe to remove) ---
  echo "$entry" | jq -r '.global_skills // {} | keys[]?' | \
    while read -r old; do
      old_dir="$HOME/.claude/skills/$old"
      [ -d "$old_dir" ] || continue
      rm -rf "$old_dir"
      echo "  Removed old global skill: $old"
    done

  # --- Global agents (fingerprint-guarded) ---
  echo "$entry" | jq -r '.global_agents // {} | keys[]?' | \
    while read -r old; do
      old_file="$HOME/.claude/agents/$old.md"
      [ -f "$old_file" ] || continue
      if grep -qE "$FINGERPRINT" "$old_file"; then
        rm -f "$old_file"
        echo "  Removed old global agent: $old"
      else
        echo "  Kept (no AI Awareness fingerprint found): $old_file — please review manually"
      fi
    done
done

# --- Legacy fallback: process flat top-level fields too, for migration.json files written before the renames-array schema ---
# These are kept in migration.json for backward compatibility but are a duplicate of the v6.0.0 entry in renames[].
# The directory existence check makes this idempotent — won't re-run renames that already happened above.

# (legacy fallback only runs if NO renames array exists, i.e., this is an old migration.json)
has_renames=$(jq -e '.renames | length > 0' "$MIGRATION_FILE" 2>/dev/null && echo yes || echo no)
if [ "$has_renames" = "no" ]; then
  echo "Note: migration.json has no renames array — falling back to legacy flat schema."

  jq -r '.skills | to_entries[] | [.key, (.value // "")] | @tsv' "$MIGRATION_FILE" | \
    while IFS=$'\t' read -r old new; do
      old_dir="$TARGET/.claude/skills/$old"
      [ -d "$old_dir" ] || continue
      if [ -z "$new" ]; then
        rm -rf "$old_dir"
        echo "Removed: .claude/skills/$old"
      else
        new_dir="$TARGET/.claude/skills/$new"
        [ -e "$new_dir" ] || mv "$old_dir" "$new_dir"
      fi
    done
fi

# --- Project-level agents ---
jq -r '.agents | to_entries[] | [.key, (.value // "")] | @tsv' "$MIGRATION_FILE" | \
  while IFS=$'\t' read -r old new; do
    old_dir="$TARGET/.claude/agents/$old"
    [ -d "$old_dir" ] || continue
    if [ -z "$new" ]; then
      rm -rf "$old_dir"
      echo "Removed: .claude/agents/$old"
    else
      new_dir="$TARGET/.claude/agents/$new"
      if [ -e "$new_dir" ]; then
        echo "Skip: .claude/agents/$new already exists"
      else
        mv "$old_dir" "$new_dir"
        echo "Renamed: .claude/agents/$old -> .claude/agents/$new"
      fi
    fi
  done

# --- Global skills (replaced by aa- prefixed versions — safe to remove) ---
jq -r '.global_skills | keys[]' "$MIGRATION_FILE" | \
  while read -r old; do
    old_dir="$HOME/.claude/skills/$old"
    [ -d "$old_dir" ] || continue
    rm -rf "$old_dir"
    echo "Removed old global skill: $old"
  done

# --- Global agents (fingerprint-guarded) ---
jq -r '.global_agents | keys[]' "$MIGRATION_FILE" | \
  while read -r old; do
    old_file="$HOME/.claude/agents/$old.md"
    [ -f "$old_file" ] || continue
    if grep -qE "$FINGERPRINT" "$old_file"; then
      rm -f "$old_file"
      echo "Removed old global agent: $old"
    else
      echo "Kept (no AI Awareness fingerprint found): $old_file — please review manually"
    fi
  done

# --- settings.json Skill() rename via jq ---
# Aggregate ALL skill renames from .renames[] (and legacy .skills) into one map.
# Safe to include renames the project may not have hit yet — the walk only replaces
# Skill() entries that actually exist in settings.json. If the project is at v6.5.0,
# it has no v6.0.0-era Skill() refs to begin with.
settings_file="$TARGET/.claude/settings.json"
if [ -f "$settings_file" ]; then
  rename_map=$(jq '
    # New: aggregate across versioned renames array
    (reduce (.renames[]?) as $e ({}; . + ($e.skills // {} | with_entries(select(.value != null)))))
    # Legacy fallback: also merge in flat .skills (for migration.json files that lack .renames)
    + (.skills // {} | with_entries(select(.value != null)))
  ' "$MIGRATION_FILE")
  tmp=$(mktemp)
  if jq --argjson map "$rename_map" '
        walk(
          if type == "string" then
            gsub("Skill\\((?<n>[^)]+)\\)";
                 (($map[.n]) // .n) as $new | "Skill(\($new))")
          else . end
        )
      ' "$settings_file" > "$tmp"; then
    mv "$tmp" "$settings_file"
    echo "Updated settings.json Skill() references"
  else
    rm -f "$tmp"
    echo "Warning: could not rewrite settings.json — leaving as-is"
  fi
fi
```

**Rename-completeness check (scan string literals — NEW):** the v6→v7 `aa-*` rename renamed dirs and headers but missed legacy skill names that appear INSIDE body text — echo strings, examples, prose `Skill()` mentions. Those are not caught by the dir/header renames above. After the renames run, scan the target's installed skills/agents for unprefixed legacy skill names appearing as whole tokens and **warn** (do not auto-rewrite — body context is too varied to edit blindly) so they can be fixed.

```bash
# Legacy bare skill names that should now be aa-prefixed.
LEGACY_NAMES='task-flow|task-flow-[a-z-]+|review-pr|github-commit|github-pr|init-skills|init-mcps'

# Whole-token match: preceding char is NOT a letter or hyphen (so "aa-task-flow" and
# "non-task-flow" don't match), and the name is NOT immediately followed by "-<number>"
# (so "review-pr-12" / "review-pr-$PR_NUMBER" — intentional branch/worktree names in
# aa-global-pr-reviewer — are excluded). The negative-lookbehind/lookahead is done with
# grep -oP so we only ever flag the bare standalone skill token.
SURVIVORS=$(grep -rnoP "(?<![A-Za-z-])(${LEGACY_NAMES})(?!-[0-9])(?![A-Za-z-])" \
  "$TARGET/.claude/skills" "$TARGET/.claude/agents" 2>/dev/null \
  | grep -vP ":\s*aa-" || true)

if [ -n "$SURVIVORS" ]; then
  echo "⚠️  Rename-completeness warning: legacy unprefixed skill names found inside installed skill/agent bodies (string literals/examples, not filenames):"
  echo "$SURVIVORS" | sed 's/^/  - /'
  echo "    These were missed by the v6→v7 dir/header rename. Prefix them with 'aa-' (e.g. task-flow → aa-task-flow) where they refer to the skill."
  echo "    (review-pr-<number> / review-pr-\$PR_NUMBER branch names are intentionally NOT flagged.)"
else
  echo "Rename-completeness check: no legacy unprefixed skill-name literals found."
fi
```

This is a scan-string-literals check — it complements the dir/header renames above, it does not replace them. It's a warn-only report so genuine survivors surface without risking an incorrect blind rewrite of prose.

> `grep -oP` (PCRE lookbehind/lookahead) is GNU-grep. On macOS BSD grep it's unavailable — fall back to `ggrep` if present (`brew install grep`), or do the whole-token + `-<number>`-exclusion filtering with `grep -nE` plus an `awk`/`grep -v` post-filter on the matched line. The warn-only nature means a missed scan degrades to "no warning", not a broken upgrade.

Report migration results to the user before continuing.

### 1d. Read Versions

Read framework version (run individually):
```bash
grep '"framework_version"' {FRAMEWORK_PATH}/config_hints.json
```

Read project's installed version:
```bash
grep '"framework_version"' {TARGET_PROJECT}/.claude/config_hints.json
```

Parse the version values from the output. Store as `FRAMEWORK_VERSION` and `PROJECT_VERSION`.

If `{TARGET_PROJECT}/.claude/config_hints.json` does not exist, tell the user:
```
This project doesn't have AI Awareness installed yet (no .claude/config_hints.json).
Use the "aa-install" skill for a fresh install instead.
```
Stop here.

### 1d-2. Confirm install_role and persist (NEW in v6.7.0)

`INSTALL_ROLE` was already resolved in Step 1a-3 (so Step 1b could decide whether to create a feature branch). This step **persists the resolved value** into `config_hints.json` if it wasn't already there, so future upgrades skip auto-detection.

```bash
existing=$(jq -r '.install_role // ""' "{TARGET_PROJECT}/.claude/config_hints.json")
if [ "$existing" != "$INSTALL_ROLE" ]; then
  # Write/update install_role in config_hints.json
  tmp=$(mktemp)
  jq --arg role "$INSTALL_ROLE" '.install_role = $role' "{TARGET_PROJECT}/.claude/config_hints.json" > "$tmp" \
    && mv "$tmp" "{TARGET_PROJECT}/.claude/config_hints.json"
  echo "Persisted install_role: $INSTALL_ROLE"
fi
```

`INSTALL_ROLE` is used by:
- **Step 1b** above — decided whether to create a feature branch (workspace installs skip it)
- **Step 1d-3** below — detects wrong-context skills already present
- **Phase 4 writers** — picks the source directory (`skills/` vs `workspace-skills/`) when installing/updating
- **Phase 5 step 5e-2** — decides whether to auto-push (workspace: yes; code-repo: no, leave for PR)

### 1d-3. Cleanup wrong-context skills (v7.0.0 — directory-based, opt-in)

Detect skills already installed in `{TARGET_PROJECT}/.claude/skills/` that belong in the OTHER role's source directory in the framework. These are drift from pre-v7.0.0 installs that used the `run-from` filter and may have mis-installed a skill before the manifest classification was corrected.

The check is now trivially path-based: a skill is wrongly-placed iff it exists in the framework's opposite-role directory.

```bash
WRONG_CONTEXT_SKILLS=()

# Determine which framework dir holds skills the CURRENT install should have, and which holds the "opposite"
if [ "$INSTALL_ROLE" = "workspace" ]; then
  RIGHT_DIR="{FRAMEWORK_PATH}/workspace-skills"
  WRONG_DIR="{FRAMEWORK_PATH}/skills"
else
  RIGHT_DIR="{FRAMEWORK_PATH}/skills"
  WRONG_DIR="{FRAMEWORK_PATH}/workspace-skills"
fi

for skill_dir in "{TARGET_PROJECT}/.claude/skills"/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name=$(basename "$skill_dir")

  # Wrongly-placed iff the framework has it in the opposite-role directory and NOT in the right-role directory.
  # (If the framework has it in BOTH dirs — shouldn't happen — we leave it alone.)
  if [ -d "$WRONG_DIR/$skill_name" ] && [ ! -d "$RIGHT_DIR/$skill_name" ]; then
    WRONG_CONTEXT_SKILLS+=("$skill_name")
  fi
done

# Read cleanup_dismissed flag to honour an earlier "stop asking" choice
CLEANUP_DISMISSED=$(jq -r '.cleanup_dismissed // false' "{TARGET_PROJECT}/.claude/config_hints.json" 2>/dev/null)

if [ "${#WRONG_CONTEXT_SKILLS[@]}" -gt 0 ] && [ "$CLEANUP_DISMISSED" != "true" ]; then
  echo ""
  echo "Detected ${#WRONG_CONTEXT_SKILLS[@]} skills in this install whose framework source lives under the opposite-role directory (install_role: $INSTALL_ROLE):"
  for skill_name in "${WRONG_CONTEXT_SKILLS[@]}"; do
    echo "  - $skill_name (framework: $WRONG_DIR/$skill_name)"
  done
  echo ""
  echo "These are drift from pre-v7.0.0 installs that mis-classified them via the now-removed run-from filter."
  echo "Removing them is opt-in. They're not breaking anything; they're just dead weight."
  echo ""
  echo "Remove these skills from {TARGET_PROJECT}/.claude/skills/ ?"
  echo "  1. Yes — remove (recommended)"
  echo "  2. No — leave as-is, ask me again next upgrade"
  echo "  3. Skip — leave as-is and stop asking (sets cleanup_dismissed: true in config_hints.json)"
fi
```

On choice 1: `rm -rf` each wrong-context skill directory, log each removal, append to Phase 5 update report. Leave `WRONG_CONTEXT_SKILLS_LEFT_AS_IS=()` empty (the array is consumed by the later `delete_removed_files()` procedure in Step 2c/3c/4e — empty means "don't suppress any Removed-section deletions").

On choice 2 or 3: do not remove. **Populate `WRONG_CONTEXT_SKILLS_LEFT_AS_IS` with the skill names so the later Removed-files delete pass respects the choice:**

```bash
WRONG_CONTEXT_SKILLS_LEFT_AS_IS=("${WRONG_CONTEXT_SKILLS[@]}")
```

Choice 2 stops here. Choice 3 also persists the dismissal:
```bash
tmp=$(mktemp)
jq '.cleanup_dismissed = true' "{TARGET_PROJECT}/.claude/config_hints.json" > "$tmp" \
  && mv "$tmp" "{TARGET_PROJECT}/.claude/config_hints.json"
```
The flag is read at the top of this step (`CLEANUP_DISMISSED`) so future upgrades skip the prompt. Removing the field or setting it to `false` re-enables prompting.

**Edge cases:**
- Project-custom skills (in `.claude/skills/` but not in EITHER framework source dir) — not touched. The cleanup only considers skills the framework manages.
- Skills present in BOTH framework dirs (should never happen, but if it does) — not touched; ambiguous.

### 1e. Compare Versions and Build Changed Files List

**If PROJECT_VERSION == FRAMEWORK_VERSION:**

Run the **Smart Diff** procedure from `setup.md` to check for drift.
- **If no actionable differences:** the project files are up to date — but global tools (scripts under `~/.claude/scripts/` and the helper skills `aa-optimizer` / `aa-record-improvement`) may have changed since the last sync. Don't exit silently. Instead:
  ```
  Project files are fully up to date at v{FRAMEWORK_VERSION}.
  Checking global tools (scripts, helper skills, agents) for updates...
  ```
  Then run the **global-tools sync** inline by invoking the canonical installer at the framework root:
  ```bash
  bash "{FRAMEWORK_PATH}/install-tools.sh"
  ```
  The shell script reads `scripts/manifest.json`, refreshes `~/.claude/scripts/`, `~/.claude/agents/`, and the global helper skills (`aa-optimizer`, `aa-record-improvement`), and refreshes the marker-guarded source block in `~/.zshrc` / `~/.bashrc`. Idempotent — files are only rewritten if their content changed; the shell-rc block is replaced in place, never duplicated. After it completes, report what was synced (or "global tools also up to date — nothing to do") and stop.

  **Rationale:** `aa-upgrade` is the natural single entry point. If a user runs it expecting "make this machine current with the framework", they shouldn't also need to remember to run `aa-install-tools` separately for tools-only updates that don't bump `framework_version` (e.g., new worktree commands, sonarqube script fixes).
- **If differences found:** present them and ask if user wants to apply fixes. If yes, use those files as CHANGED_FILES. The normal Phase 5 step 5d will run the global-tools sync at the end, so we don't duplicate it here.

**If PROJECT_VERSION < FRAMEWORK_VERSION:**

Read `CHANGELOG.md` from the framework directory. Extract all entries after `v{PROJECT_VERSION}`. Parse the section-marker blocks to build deduplicated lists of files that need updating or deleting.

**Recognised section markers** (any of these, in any combination — entries vary by version):

- `**Added:**` — new files to install
- `**Changed:**` — files modified (most common — match this AS WELL AS `**Files changed:**`)
- `**Files changed:**` — older variant of `**Changed:**`, treated identically
- `**Removed:**` — files to delete from target

Extract file paths from each section. **A bullet may contain a file path either as a bare backticked token or as a nested-bullet list under a file path.** Both shapes appear in past entries:

```markdown
**Changed:**
- `skills/aa-task-flow/SKILL.md` — Phase 4k changes, new Framework-Defect Capture section
- `skills/aa-record-improvement/SKILL.md`:
  - Step 7 writes to shared improvements/
  - Step 8 drops over-conservative safety guard
```

Both lines yield the path of their backticked file. Nested sub-bullets are descriptions of what changed inside the file — they don't introduce additional paths.

Use this jq/grep recipe to extract all paths from the section bodies:

```bash
awk -v from="v$PROJECT_VERSION" -v to="v$FRAMEWORK_VERSION" '
  $0 ~ "^## "to {capturing=1; next}
  $0 ~ "^## "from {capturing=0}
  $0 ~ /^\*\*(Changed|Added|Removed|Files changed):\*\*/ {in_section=1; next}
  $0 ~ /^\*\*[A-Z]/ {in_section=0}
  capturing && in_section && /^- `[^`]+`/ {print}
' CHANGELOG.md \
| grep -oE '`[^`]+`' \
| tr -d '`' \
| sort -u
```

(For the actual implementation in the writer agents, prefer reading the CHANGELOG and using LLM judgment over a fragile bash one-liner — but the grammar above is the canonical reference.)

### 1f. Categorize Changed Files and Select Mode

Categorize each file in CHANGED_FILES:

- **code_repo_skill_files** — paths starting with `skills/` (maps to `.claude/skills/` in code-repo target; skipped for workspace target)
- **workspace_skill_files** — paths starting with `workspace-skills/` (maps to `.claude/skills/` in workspace target; skipped for code-repo target) — new in v7.0.0
- **agent_files** — paths starting with `agents/` (maps to `.claude/agents/` in target)
- **universal_rule_files** — paths starting with `rules/universal/` (maps to `{standards_dir}/` in both install roles)
- **stack_rule_files** — paths starting with `rules/java-spring-boot/` or `rules/react/` (maps to `{standards_dir}/` if platform matches, both install roles)
- **workspace_rule_files** — paths starting with `workspace-rules/` (maps to `{standards_dir}/` for workspace targets; skipped for code-repo) — new in v7.0.0. Leadership / status-report rules (cross-team framing, document formatting for weekly reports) that don't belong in code repos.
- **settings_files** — `settings.json`
- **template_files** — paths starting with `templates/`. **v7.0.0: aa-upgrade DROPS these from CHANGED_FILES** — templates are install-time only (see setup.md Step 13 core rule #2). The full scan-and-install flow runs only during `aa-install`. Upgrade-time touching of `templates/*` only happens via Step 13c (delete `.claude/templates/{pr,commit}-template.md` duplicates), which runs unconditionally and doesn't need the file to be in CHANGED_FILES.
- **config_doc_files** — `config_hints.json`, `AGENTS.md`
- **removed_files** — files listed under `**Removed:**` in CHANGELOG. These must be deleted from the target project if present.
- **ignore** — files not installed into target projects. Remove from CHANGED_FILES:
  - `CLAUDE.md`, `README.md`, `VERSIONING.md`, `GUIDE.md`, `setup.md` — framework docs
  - `.claude/commands/` - all framework-operational commands (aa-install, aa-upgrade, aa-add-improvement, aa-install-tools, aa-install-context)
  - `skills/aa-optimizer/` - installed globally to `~/.claude/skills/` by Step 1c prerequisites, not into target project
  - `skills/aa-record-improvement/` - installed globally to `~/.claude/skills/` by Step 1c prerequisites, not into target project
  - `scripts/` - installed globally to `~/.claude/scripts/` by Step 1c prerequisites, not into target project
  - `migration.json` - framework migration config, not installed into target projects
  - `templates/pr-template.md`, `templates/commit-template.md` — install-time only (see template_files note above). Drop from CHANGED_FILES entirely so Writer agents don't attempt to install or merge them.

After categorization, drop entries that don't match `INSTALL_ROLE` from the active skill set:

```bash
if [ "$INSTALL_ROLE" = "workspace" ]; then
  skill_files=("${workspace_skill_files[@]}")
else
  skill_files=("${code_repo_skill_files[@]}")
fi
```

`skill_files` is then used downstream the same way as in v6.x. The categorization above keeps both buckets so the upgrade summary can show the user what was skipped due to install_role.

Same role-based reduction is applied to rules:

```bash
# Combine universal rules + stack-matched rules; add workspace-only rules ONLY for workspace installs
rule_files=("${universal_rule_files[@]}" "${stack_rule_files[@]}")
if [ "$INSTALL_ROLE" = "workspace" ]; then
  rule_files+=("${workspace_rule_files[@]}")
fi
```

The buckets dropped due to `INSTALL_ROLE` (workspace_skill_files for code-repo installs; workspace_rule_files for code-repo installs; code_repo_skill_files for workspace installs) are NOT shown in the upgrade summary today — the role filter is silent. If you want to see what was filtered, inspect the categorized buckets in the verbose log.

**Mode selection logic:**

```
has_rules = rule_files is not empty
has_settings = settings_files is not empty
has_templates = template_files is not empty
total_installable = len(skill_files) + len(agent_files) + len(rule_files) + len(template_files)

if not has_rules and not has_settings and not has_templates:
    MODE = "inline"          # Skills/agents only — no platform adaptation needed
elif total_installable <= 10:
    MODE = "single_agent"    # Rules or templates changed but manageable scope
else:
    MODE = "full_pipeline"   # Large update — use parallel agents
```

### 1g. Present Change Summary

Show the user exactly what will happen — file by file, what will be added, what will be merged, and what will be preserved from their current setup. Don't ask a generic "Proceed?" — ask precise questions only for items the framework genuinely cannot decide on its own.

```
Your project is at AI Awareness v{PROJECT_VERSION}.
Framework is at v{FRAMEWORK_VERSION}.

Changes since your version:

v{X.Y} — {summary}
  - {file1} — {what changed} → action: ADD / UPDATE / RENAME / DELETE
  - {file2} — {what changed} → action: ADD / UPDATE / RENAME / DELETE

v{X.Z} — {summary}
  - {file3} — {what changed} → action: ADD / UPDATE / RENAME / DELETE
  ...

What this upgrade will preserve in your project (Smart Diff):
  - {standards_dir}/{rule_with_tuning} — your customized thresholds, project-specific examples, and override sections will be kept; framework additions will be merged underneath them
  - AGENTS.md — your project description and team-specific sections are untouched; only framework-managed sections get refreshed
  - config_hints.json — only framework_version is updated; all other fields stay verbatim
  - Any file listed in bootstrap_rules: never touched (project-custom by definition)

{N} installable files need updating. Update mode: {MODE}
Update branch: {update branch name from Step 1b}
Audit entry destination: workspace installs append to `dirname({TARGET_PROJECT})/{ProjectName}_AIAwarenessFramework/update-history.md`. Code-repo installs: no separate audit file is created (version is tracked in AGENTS.md footer and config_hints.json).
```

**Precise questions — only ask if at least one is true:**

Ask only the questions below that actually apply. Do NOT ask a blanket "Proceed?" — that hides ambiguity behind a generic prompt.

1. **If any RENAME is in the changelog** and the target has BOTH the old and the new file present (rare, indicates manual intervention):
   ```
   {old_file} was renamed to {new_file} in v{X.Y}, but your project has both files. Which is the source of truth?
     1. {old_file}  (older, preserve any local edits, delete {new_file})
     2. {new_file}  (newer, delete {old_file})
     3. Merge both into {new_file}, delete {old_file}  (recommended if both have local content)
   ```

2. **If any rule file in {standards_dir} has been tuned** (detected via Smart Diff finding non-trivial divergence from the previous framework version) AND that rule is in the changed list:
   ```
   You've tuned {rule_file}:
     - Your version differs from v{PROJECT_VERSION} baseline in these lines: {hunk summary, max 10 lines}
   The framework v{FRAMEWORK_VERSION} version of this rule has these changes: {hunk summary}

   How should I handle this?
     1. Keep your tuning verbatim; merge framework additions as new sections below
     2. Replace with framework version (your tuning will be lost — choose only if your tuning is no longer relevant)
     3. Show me both side-by-side, I'll decide per change
   ```

3. **If any config_hints.json field exists in this project but is missing from the framework's reference config_hints.json** for this version (project has extra fields, framework doesn't):
   ```
   Your config_hints.json has these extra fields not in the framework template: {fields}.
   I'll keep them as-is unless they conflict with renamed/removed fields. Confirm? (y/n)
   ```

4. **Otherwise (no ambiguity):**
   ```
   No ambiguous items. The upgrade is safe to apply automatically.
   Proceed? (y/n)
   ```

If the user declines OR doesn't confirm a precise question, stop and do nothing.

**Why this matters:** generic "Proceed?" prompts hide real decisions behind a single yes/no. Precise questions surface only the items the framework can't safely decide alone — and only when they're real. The user should finish the prompt knowing exactly which files will change, which lines of their tuning will be preserved, and which decisions they made.

---

## Phase 2: Inline Mode (No Agents)

**When:** All changes are skills and/or agents — no rules, settings, or templates.

This mode runs entirely in the main session. No temp files, no agents, no Stack Analyzer, no Contamination Checker. Skills and agents are platform-agnostic — they don't contain Java/React-specific code that needs adaptation.

### 2a. Read Project Config

Read `{TARGET_PROJECT}/.claude/config_hints.json` to get `standards_dir` and `namespace`/`namespaces`. These are the only project-specific values that might appear in skill files (as `{STANDARDS_DIR}` or `{namespace}` references in installed versions).

### 2b. Process Each Changed File

For each file in CHANGED_FILES (skill_files + agent_files):

**Determine source and target paths (v7.0.0: source is path-based — no manifest, no run-from filter):**
- `skills/{name}/SKILL.md` (code-repo skill) → source: `{FRAMEWORK_PATH}/skills/{name}/SKILL.md`. Process only when `INSTALL_ROLE = code-repo`. Skip when `INSTALL_ROLE = workspace`. Target: `{TARGET_PROJECT}/.claude/skills/{name}/SKILL.md`.
- `workspace-skills/{name}/SKILL.md` (workspace skill) → source: `{FRAMEWORK_PATH}/workspace-skills/{name}/SKILL.md`. Process only when `INSTALL_ROLE = workspace`. Skip when `INSTALL_ROLE = code-repo`. Target: `{TARGET_PROJECT}/.claude/skills/{name}/SKILL.md`.
- `agents/{name}/AGENT.md` → source: `{FRAMEWORK_PATH}/agents/{name}/AGENT.md`, target: `{TARGET_PROJECT}/.claude/agents/{name}/AGENT.md`. Agents are NOT split — process for both install roles.

```bash
case "$changed_file" in
  skills/*)           [ "$INSTALL_ROLE" = "code-repo" ] || { echo "Skip: $changed_file (code-repo skill, install_role=$INSTALL_ROLE)"; continue; } ;;
  workspace-skills/*) [ "$INSTALL_ROLE" = "workspace" ] || { echo "Skip: $changed_file (workspace skill, install_role=$INSTALL_ROLE)"; continue; } ;;
  agents/*)           ;;  # always process
esac
```

**If target file does NOT exist (new skill/agent, role matches):**
- Read the framework source file
- Copy it to the target path (create directories if needed)
- No adaptation needed — skills/agents use runtime config resolution (they read `config_hints.json` at execution time)

**If target file exists (update):**
- Read BOTH the framework source file and the installed target file
- Apply Smart Diff logic inline:
  - **Project-Specific Values** (real namespace, project name, paths): PRESERVE
  - **Intentional Overrides** (project deliberately changed behavior): PRESERVE — ask user if unclear
  - **Missing Framework Update** (new sections, new steps, new guardrails in framework): ADD — merge into target without disturbing existing content
  - **Outdated Content** (framework fixed a bug the target still has): UPDATE — apply the fix
  - **Formatting Preferences** (cosmetic differences): PRESERVE
- Write the merged result

**Key principle:** Read both files, identify what the framework ADDED or FIXED since the project's version, and surgically apply only those changes. Never replace project-specific values with generic placeholders.

### 2c. Delete Removed Files

If `removed_files` is not empty, run the **shared delete-removed-files procedure** below. The same procedure runs at the end of Phase 3 (Single-Agent) and Phase 4 (Full-Pipeline) — defined once here, referenced from both.

```bash
# Shared delete-removed-files procedure
# Maps each framework-relative path in removed_files to the corresponding target path
# and deletes the file if it exists. Skips paths that 1d-3 cleanup already handled
# (so a user's "leave as-is" choice in 1d-3 isn't silently overridden).
delete_removed_files() {
  for path in "${removed_files[@]}"; do
    case "$path" in
      skills/*)
        # skills/{name}/SKILL.md → .claude/skills/{name}/SKILL.md (strip "skills/" prefix)
        target_path="$TARGET_PROJECT/.claude/skills/${path#skills/}"
        # If 1d-3 cleanup ran and user picked "leave-as-is" for this skill name, skip the delete.
        skill_name=$(echo "$path" | awk -F/ '{print $2}')
        case " ${WRONG_CONTEXT_SKILLS_LEFT_AS_IS[*]} " in
          *" $skill_name "*) echo "Skipped delete: $path (1d-3 leave-as-is choice)"; continue ;;
        esac
        ;;
      workspace-skills/*)
        target_path="$TARGET_PROJECT/.claude/skills/${path#workspace-skills/}"
        ;;
      rules/universal/*|rules/java-spring-boot/*|rules/react/*|workspace-rules/*)
        # Rules: strip everything before the basename — they all land in $STANDARDS_DIR/
        STANDARDS_DIR=$(jq -r '.standards_dir // ".claude/rules"' "$TARGET_PROJECT/.claude/config_hints.json")
        target_path="$TARGET_PROJECT/$STANDARDS_DIR/$(basename "$path")"
        ;;
      agents/*)
        target_path="$TARGET_PROJECT/.claude/${path}"
        ;;
      *)
        # Non-file entry (helper name, code-path description). Skip silently.
        echo "Skipped (not a target file path): $path"
        continue
        ;;
    esac

    if [ -e "$target_path" ]; then
      rm -rf "$target_path"
      echo "Deleted: $target_path (was: $path)"
      # If deleting a skill file left behind an empty directory, clean it up too
      if [[ "$path" == skills/*/SKILL.md || "$path" == workspace-skills/*/SKILL.md ]]; then
        parent=$(dirname "$target_path")
        [ -d "$parent" ] && [ -z "$(ls -A "$parent" 2>/dev/null)" ] && rmdir "$parent"
      fi
    else
      echo "Already absent: $target_path"
    fi
  done
}

# Invoke
delete_removed_files
```

**`WRONG_CONTEXT_SKILLS_LEFT_AS_IS`:** Step 1d-3 populates this array when the user picks choice 2 ("leave as-is") for skills in the wrong context, so this delete pass respects that choice. If 1d-3 didn't run (e.g., no drift detected), the array is empty and every Removed entry deletes.

### 2d. Skip to Phase 5 (Finalize)

No verification needed — skills/agents don't contain platform-specific code that could be contaminated. Go directly to Phase 5.

---

## Phase 3: Single-Agent Mode

**When:** Rules or templates changed, but total installable files ≤10.

Uses ONE combined writer agent instead of separate Stack Analyzer + Structure Writer + Rules Writer + Config Writer + Contamination Checker (5 agents → 1 agent).

### 3a. Read Project Config

Read `{TARGET_PROJECT}/.claude/config_hints.json` fully — get `platform`, `standards_dir`, `namespace`/`namespaces`, and `bootstrap_rules` (if any).

### 3b. Launch Combined Writer Agent

Launch a single **Task** subagent that handles research, writing, and self-verification:

**Combined Writer prompt:**
```
You are the Combined Writer for an AI Awareness incremental update.

## Project Info
- Target project: {TARGET_PROJECT}
- Framework path: {FRAMEWORK_PATH}
- Platform: {platform from config_hints.json}
- Standards dir: {standards_dir from config_hints.json}
- Namespace: {namespace from config_hints.json}
- Project version: v{PROJECT_VERSION} → v{FRAMEWORK_VERSION}
{if bootstrap_rules: - Bootstrap rules (DO NOT TOUCH): {list from config_hints.json}}

## Changed Files to Process
{list each file with its category: skill/agent/rule/template}

## Your Job

### Step 1: Quick Stack Check
Read {TARGET_PROJECT}/.claude/config_hints.json and one build file (build.gradle,
pom.xml, or package.json) to confirm the platform. You do NOT need a full stack
analysis — just confirm the platform field is still accurate.

### Step 2: Process Each File

For each changed file, determine source and target paths:
- skills/{name}/SKILL.md → {TARGET_PROJECT}/.claude/skills/{name}/SKILL.md — process only if INSTALL_ROLE = code-repo
- workspace-skills/{name}/SKILL.md → {TARGET_PROJECT}/.claude/skills/{name}/SKILL.md — process only if INSTALL_ROLE = workspace
- agents/{name}/AGENT.md → {TARGET_PROJECT}/.claude/agents/{name}/AGENT.md — both install roles
- rules/universal/{name} → {TARGET_PROJECT}/{standards_dir}/{name} — both install roles
- rules/java-spring-boot/{name} → {TARGET_PROJECT}/{standards_dir}/{name} (only if platform contains "Java")
- rules/react/{name} → {TARGET_PROJECT}/{standards_dir}/{name} (only if platform contains "React")
- workspace-rules/{name} → {TARGET_PROJECT}/{standards_dir}/{name} — process only if INSTALL_ROLE = workspace. Leadership/status-report rules that v7.0.0 split out of rules/universal/ because they don't apply to code repos.
- templates/{name} → **NEVER install or merge during upgrade.** Templates are install-time only (setup.md Step 13 core rule #2). The only upgrade-time work is Step 13c (delete `.claude/templates/` duplicates), which is invoked separately and doesn't need the file to be in CHANGED_FILES.
- settings.json → {TARGET_PROJECT}/.claude/settings.json

**Skill source directory by INSTALL_ROLE (v7.0.0 replaces the v6.6.0–v6.10.0 run-from filter — see setup.md Step 6):** the directory the skill lives in IS its role. `skills/foo` is processed for code-repo installs; `workspace-skills/foo` is processed for workspace installs. There is no manifest, no frontmatter field. Skip mismatches with a one-line log: `"Skip: workspace-skills/{name} (install_role=$INSTALL_ROLE)"`. Agents, rules, templates, and settings are not split by install role.

For NEW files (target doesn't exist, role matches): install from framework source, adapting
platform-specific references using the project's actual values from config_hints.json.

For EXISTING files (both exist): read BOTH versions and apply Smart Diff. **The defensive default is to preserve, not update.** When in doubt, ask (via Phase 1g precise-question mechanism) rather than rewriting.

- **PRESERVE (do NOT overwrite):**
  - Project-specific values (package names, paths, namespaces, project-name strings)
  - Tuned thresholds and limits (numeric values the team has changed from defaults)
  - Custom sections the project added that don't exist in the framework version
  - Override blocks marked with `<!-- project-override -->`, `# PROJECT:`, or similar conventions in the project file
  - Ordering preferences (if the project reordered framework sections, keep their order; just add new content)
  - Project-specific examples, code snippets, and quoted patterns that reference real project code
  - Inline comments the project added (Javadoc-style `<!-- ... -->` or `> note:` lines)
- **ADD (safe to merge in):**
  - New sections the framework added that don't exist in the project version
  - New guardrails, safety rules, or workflow steps introduced in this framework version
  - New examples and rule entries from universal/platform rule files
- **UPDATE (carefully):**
  - Framework bug fixes the target still has (e.g., a typo in instruction wording, an outdated path)
  - Framework_version field in config_hints.json
- **NEVER:**
  - Replace project values with generic framework placeholders ({namespace}, {project_name}, etc.)
  - Touch files not in the changed list
  - Touch bootstrap rules listed in config_hints.json `bootstrap_rules` field
  - Silently delete a project's custom section, even if the same area got updated upstream — escalate via the Phase 1g precise question

When you have to choose between "make this look like the framework version" and "keep this project's tuning intact" — keep the tuning. The framework can re-suggest changes later via a new minor version; lost tuning is forgotten team knowledge.

For RENAMED files: check setup.md Step 8b-rename table. If a changed file was
renamed from an old name, delete the old file and install the new one (merging
any project-specific content from the old file).

For RULE files specifically: apply element mapping — replace generic package names
(com.example.{project}) with the project's actual base package, replace generic
directory paths with actual project paths. Read config_hints.json for these values.
If the project has a project-structure.md rule, detect actual project packages
to fill in correctly.

### Step 3: Self-Verify
After all files are written, scan every file you modified for:
- Unreplaced placeholders: {project}, {namespace}, {STANDARDS_DIR}  (NOT {platform} — it is a runtime token resolved by skills at execution; leave it intact)
- Foreign-stack references (Java refs in React project or vice versa)
- Rule file references pointing to nonexistent files
Report any issues found and fix them before finishing.

### Step 4: Output
Print a summary of every file you created or modified, and what you did to each.
```

### 3c. Delete Removed Files

After the Combined Writer completes, if `removed_files` is non-empty, run the shared `delete_removed_files()` procedure defined in Phase 2 step 2c. This step runs in the main session (not the writer agent) because the writer's job is install/merge — deletion is a separate concern with its own ordering relative to Step 1d-3's "leave-as-is" choice.

### 3d. Skip to Phase 5 (Finalize)

Go to Phase 5.

---

## Phase 4: Full Pipeline Mode

**When:** Major version jump, settings changed, or >10 installable files.

This is the heavyweight path with parallel agents. Only used when the scope justifies it.

### 4a. Write Handoff Config

Read the project's existing `config_hints.json` for configuration values.

Run pre-detection to set `applicable_rule_dirs` (see `setup.md` → Content Adaptation Pipeline → Pre-Detection).

**Write `_install_config.json`** to the target project root:

```json
{
  "target_project": "{TARGET_PROJECT}",
  "framework_path": "{FRAMEWORK_PATH}",
  "project_name": "{from existing config_hints.json}",
  "namespace": "{from existing config_hints.json}",
  "namespaces": "{from existing config_hints.json or null}",
  "standards_dir": "{from existing config_hints.json}",
  "install_role": "{INSTALL_ROLE — from Step 1d-2}",
  "mode": "update",
  "project_version": "{PROJECT_VERSION}",
  "framework_version": "{FRAMEWORK_VERSION}",
  "changed_files": ["{deduplicated list from CHANGELOG parsing}"],
  "applicable_rule_dirs": ["{list}"]
}
```

### 4b. Launch Stack Analyzer

Launch as a **Task** subagent:

**Stack Analyzer prompt:**
```
You are the Stack Analyzer of the AI Awareness Content Adaptation Pipeline.

Read {TARGET_PROJECT}/_install_config.json for configuration.

This is an UPDATE (not fresh install). Only the files listed in "changed_files"
need processing.

Your job:
1. Detect the target project's complete technology stack by reading its actual files.
   The existing config_hints.json has a "platform" field you can use as a starting
   point, but verify against actual project files.

2. Read ONLY the changed framework source files from {FRAMEWORK_PATH}
   (listed in _install_config.json changed_files).

3. For each changed framework file, identify every platform-specific element.

4. Write {TARGET_PROJECT}/_stack_mapping.md with the mapping.
   Include build commands and project structure summary.

Do NOT read setup.md. Do NOT install any files. Only research and write the mapping.
```

### 4c. Launch Writers

Categorize CHANGED_FILES into groups:

- **Structure files** (skills/, agents/, settings.json, templates/) → Structure Writer
- **Rule files** (rules/) → Rules Writer
- **Config/doc files** (config_hints.json, AGENTS.md, CLAUDE.md) → Config Writer

Initialize `_install_manifest.json`:
```bash
echo '{"files_written":[]}' > {TARGET_PROJECT}/_install_manifest.json
```

**Launch applicable writers in parallel** (only those with files in their group):

**Structure Writer prompt — if structure files changed:**
```
You are the Structure Writer of the AI Awareness Content Adaptation Pipeline.

Read {TARGET_PROJECT}/_install_config.json for configuration. Note especially:
- INSTALL_ROLE: either "code-repo" or "workspace". Used to filter which skills get processed.

Read {TARGET_PROJECT}/_stack_mapping.md for the element mapping.

This is an UPDATE. Only process these changed files: {structure files from CHANGED_FILES}

**Skill source-directory filter (v7.0.0 — replaces the v6.6.0–v6.10.0 run-from filter):** the directory the changed-file path starts with determines whether to process it. No manifest, no frontmatter:

```bash
case "$changed_file" in
  skills/*)
    if [ "$INSTALL_ROLE" != "code-repo" ]; then
      echo "Skip: $changed_file (code-repo skill, install_role=$INSTALL_ROLE)"
      continue
    fi
    # Target path: .claude/skills/{name}/ (strip the "skills/" prefix)
    ;;
  workspace-skills/*)
    if [ "$INSTALL_ROLE" != "workspace" ]; then
      echo "Skip: $changed_file (workspace skill, install_role=$INSTALL_ROLE)"
      continue
    fi
    # Target path: .claude/skills/{name}/ (strip the "workspace-skills/" prefix — same .claude/skills/ target dir)
    ;;
  agents/*) ;;  # always process
esac
```

Skipped skills are logged but not installed/updated. If a skipped skill exists in the target's `.claude/skills/`, it's drift — the cleanup step (aa-upgrade Phase 1 step 1d-3) already offered to remove it; do NOT remove it here.

For each file that passes the filter:
- If it exists in both framework and project: use Smart Diff (setup.md) to categorize differences. Only apply "Missing Framework Update" and "Outdated Content". PRESERVE project customizations, project-specific values, and intentional overrides.
- If it's NEW (framework only): install it, adapted per mapping.
- NEVER touch project-custom skills/agents not in the framework.

Agents and other structure files (settings.json, templates) are NOT filtered by install role — process them normally per the rules above. For templates specifically, follow setup.md Steps 13 (detect existing → keep; otherwise install default) AND 13c (remove any legacy `.claude/templates/{pr,commit}-template.md` duplicates).

Follow setup.md Steps 6 (directory-by-INSTALL_ROLE), 7, 11, 13, 13c for detailed merge procedures.
Append every file you modify/create to {TARGET_PROJECT}/_install_manifest.json.
```

**Rules Writer prompt — if rule files changed:**
```
You are the Rules Writer of the AI Awareness Content Adaptation Pipeline.

Read {TARGET_PROJECT}/_install_config.json for configuration. Note INSTALL_ROLE — used to filter workspace-only rules.
Read {TARGET_PROJECT}/_stack_mapping.md for the element mapping.

This is an UPDATE. Only process these changed rule files: {rule files from CHANGED_FILES}

**Rule source-directory filter (v7.0.0 — mirrors the skills directory split):**

```bash
case "$changed_file" in
  rules/universal/*)
    # Always process — applies to both install roles
    ;;
  rules/java-spring-boot/*|rules/react/*)
    # Process only if the platform matches (read from _install_config.json)
    ;;
  workspace-rules/*)
    if [ "$INSTALL_ROLE" != "workspace" ]; then
      echo "Skip: $changed_file (workspace-only rule, install_role=$INSTALL_ROLE)"
      continue
    fi
    # Target path: $STANDARDS_DIR/{basename} (strip the "workspace-rules/" prefix)
    ;;
esac
```

For each file that passes the filter:
- If it exists in both: use Smart Diff to merge. Preserve project customizations.
- If it's NEW: install it, adapted per mapping.
- Handle renamed files per setup.md Step 8b-rename table.
- NEVER touch project-custom rules not in the framework.

IMPORTANT: Read {TARGET_PROJECT}/.claude/config_hints.json. If it contains a
"bootstrap_rules" field, those files are PROJECT-CUSTOM content generated during
initial install to match the project's actual patterns. Do NOT overwrite, delete,
or merge-replace these files. Install framework rule updates alongside them.

When following setup.md Step 9, the platform-specific paths (Java Spring Boot,
React) only apply if the mapping confirms that platform. For any platform not
covered by setup.md Step 9, install only universal rules — the mapping's
"Applicable Framework Rules" table is the authoritative guide for which rule
directories to install.

Follow setup.md Steps 8, 8b-rename, 8c, 9 for detailed procedures.
Append every file you modify/create to {TARGET_PROJECT}/_install_manifest.json.
```

**ERD Writer — only if ERD-related files changed and database exists.**

**Launch Config Writer after Structure Writer + Rules Writer complete (if config/doc files changed):**
```
You are the Config Writer of the AI Awareness Content Adaptation Pipeline.

Read {TARGET_PROJECT}/_install_config.json for configuration.
Read {TARGET_PROJECT}/_stack_mapping.md for stack details.
Read {TARGET_PROJECT}/_install_manifest.json for files modified by other writers.

This is an UPDATE. Only process these changed files: {config/doc files from CHANGED_FILES}

For AGENTS.md: use Smart Diff to merge framework updates while preserving
project-specific content (project descriptions, custom sections, adapted examples).
NEVER replace project-specific values with generic placeholders.

For config_hints.json: only update framework_version field. Preserve all other fields.

Follow setup.md Steps 10, 12 for detailed procedures.
Append every file you modify to {TARGET_PROJECT}/_install_manifest.json.
```

### 4d. Verify (Contamination Checker)

Launch as a **fresh Task invocation** with clean context.

**CRITICAL:** Do NOT pass any conversation history, mapping content, or writer outputs beyond the manifest.

```
You are the Contamination Checker of the AI Awareness Content Adaptation Pipeline.

Your job: independently verify that no foreign-stack references contaminate
the updated files in {TARGET_PROJECT}.

1. Detect the target project's technology stack yourself by reading its build files,
   dependency manifests, and source imports. Do NOT read _stack_mapping.md.

2. Read {TARGET_PROJECT}/_install_manifest.json to get the list of modified files.

3. Scan every modified file for:
   - Unreplaced placeholders: {project}, {namespace}, {STANDARDS_DIR}  (NOT {platform} — it is a runtime token resolved by skills at execution; leave it intact)
   - Foreign-stack references
   - Rule file references that point to files that don't exist

4. Report findings. Verdict: PASS if zero contamination, FAIL if any found.
```

**If PASS:** Proceed to Phase 5.

**If FAIL:** Route fixes to the appropriate writer, re-verify. Repeat until PASS.

### 4e. Delete Removed Files

After all writers have completed and the contamination checker has passed, if `removed_files` is non-empty, run the shared `delete_removed_files()` procedure defined in Phase 2 step 2c. Same rationale as Step 3c — deletion is a main-session concern with its own ordering relative to Step 1d-3's "leave-as-is" choice.

### 4f. Cleanup Pipeline Files

```bash
rm -f {TARGET_PROJECT}/_install_config.json
rm -f {TARGET_PROJECT}/_stack_mapping.md
rm -f {TARGET_PROJECT}/_install_manifest.json
```

---

## Phase 5: Finalize (All Modes)

### 5a. Update config_hints.json

Update `framework_version` to `FRAMEWORK_VERSION`. Preserve all other fields.

**Backfill empty command fields:** if `test_command` (or `verify.full_command`) is empty/absent in the target's `config_hints.json`, run **`setup.md` Step 10's detection block** to populate a concrete, detection-driven command (Makefile target if present, else the language-native command for the detected stack). The block's "only write if empty" guard makes this idempotent — it never clobbers a value the team already tuned, and leaves the field empty when detection is ambiguous (skills then detect from the repo at runtime).

### 5a-1. Resolve standards-path tokens in installed skills & agents (MANDATORY)

Run **`setup.md` Step 6r (Resolve standards-path tokens in installed skills & agents)** against the target now. This runs in the main session after all writers (any mode — inline/single-agent/full-pipeline) have finished copying/merging skills and agents, so it catches tokens from both freshly-installed and merged bodies.

It does two things:
1. **Rewrite pass** — rewrites any `rules/universal/<name>.md` → `{standards_dir-resolved}/<name>.md` and resolves the `{standards_location}` template token to the project's actual `standards_location` (read from `config_hints.json`). Net result: installed skill/agent bodies carry the project's real standards path, never `rules/universal/` and never a literal `{standards_location}`.
2. **Post-upgrade check** — greps `.claude/skills/` and `.claude/agents/` for surviving `rules/universal/` OR literal `{standards_location}`. If any survive, **FAIL the upgrade** with the offending file list so a dead reference never silently ships. Fix the offenders (re-run the rewrite) before continuing to 5a-2.

### 5a-2. Language-Safety Guardrail (MANDATORY)

Run **`setup.md` Step 16b (Language-Safety Guardrail)** against the target now. This is the hard backstop against the exact failure this skill caused on Go/Ruby repos — copying Java-flavored skill/agent bodies and dangling Java rule references into a non-Java project. If it reports any violation, **STOP, fix the offending installed files (genericize / detect-and-branch), and re-run** before continuing to 5b. Do not finalize an upgrade that injected wrong-language noise.

### 5a-3. Skill Evals: refresh changed + backfill missing (skill-creator, MANDATORY)

**`skill-creator` is a required prerequisite for both passes:** if it's missing, **STOP the upgrade** and guide the user with Step 16c's install instructions, then re-run. Do not finalize without this step.

**Pass 1 — refresh (changed skills only):** for each skill/agent in CHANGED_FILES that was installed/updated this run, refresh its eval set per **`setup.md` Step 16c** (invoke `skill-creator`, store under `.claude/skills/<name>/evals/`, run once for a baseline).

**Pass 2 — backfill (missing evals):** projects installed before v7.11.0 have no eval sets at all, and upgrade is their only path — so scan for the gap:

```bash
# Framework-managed skills missing evals (skip project-custom skills not in the framework source)
for d in {TARGET_PROJECT}/.claude/skills/*/; do
  name=$(basename "$d")
  [ -d "{FRAMEWORK_PATH}/skills/$name" ] || [ -d "{FRAMEWORK_PATH}/workspace-skills/$name" ] || continue
  [ -f "$d/evals/evals.json" ] || echo "MISSING-EVALS: $name"
done
# Same for framework agents
for d in {TARGET_PROJECT}/.claude/agents/*/; do
  name=$(basename "$d")
  [ -d "{FRAMEWORK_PATH}/agents/$name" ] || continue
  [ -f "$d/evals/evals.json" ] || echo "MISSING-EVALS: agent $name"
done
```

Generate an eval set per Step 16c for every MISSING-EVALS hit. **Never regenerate or overwrite an existing `evals/evals.json`** — backfill fills gaps only, so re-running the upgrade is a no-op for unchanged skills.

**Report in the upgrade summary:** `evals refreshed: {N} changed, {M} backfilled`. Surface any baseline failure before finalizing.

**⏱ Cost:** backfill is a one-time hit on the first post-v7.11.0 upgrade of an older install (one generation per missing skill); every subsequent upgrade finds them present and no-ops.

### 5a-4. Installed-Reference Validation (MANDATORY)

Run **`setup.md` Step 16d (Installed-Reference Validation)** against the target now. This is the backstop for the silent-install-defect class an upgrade can introduce: doc-update steps pointing at files the target doesn't have, an agent left **orphaned** (still documented in `AGENTS.md` but invoked by no installed skill — the exact symptom when an upgrade overwrites a skill that used to invoke a project-custom agent), a skill on disk no routing table reaches, or an install-resolved placeholder that survived. If it reports any **violation**, **STOP and fix before finalizing** — do not hand the user a broken wiring. Carry the full violation+warning list into the Phase 5e upgrade summary and the upgrade PR body so reviewers see what was checked.

**Customization-preservation note:** if this step flags an orphaned agent that the *previous* install wired into a skill (a project customization this upgrade overwrote), that injected wiring must be **re-applied to the new skill version or surfaced to the user for manual re-wiring** — never dropped silently. Smart Diff (Phase 2c/3c) preserves project-tuned *content*; this check catches project-injected *invocations* that content-merge can miss.

### 5b. Update AGENTS.md Footer

```markdown
**Framework Version**: AI Awareness v{FRAMEWORK_VERSION}
**Last Updated**: {current month and year}
```

### 5c. Update .gitignore

Follow `setup.md` Step 15.

### 5d. Sync Global Tools

Re-run the global-tools installation so this developer picks up any new framework scripts and agents — including any `install: "sourced"` scripts (such as `aa-worktree/worktree.sh`) which also get wired into the user's shell-rc.

Invoke the canonical installer at the framework root:
```bash
bash "{FRAMEWORK_PATH}/install-tools.sh"
```
The shell script reads `scripts/manifest.json`, refreshes `~/.claude/scripts/`, `~/.claude/agents/`, and the global helper skills, and refreshes the marker-guarded source block in `~/.zshrc` / `~/.bashrc`. Idempotent — files are only rewritten if their content changed; the shell-rc block is replaced in place, never duplicated.

If the framework version jump introduces new scripts, add them to the Summary in step 5e under "New scripts/agents added".

### 5d-2. Append Upgrade Entry to Update History (per-platform routing — v6.10.0)

**Code-repo installs route audit entries to the LINKED workspace's per-platform subdir.** If a workspace was detected in Phase 1 step 1a-2 (linked-install detection), this code-repo upgrade's audit entry goes to `{Workspace}_AIAwarenessFramework/{Platform}/update-history.md`. Skip this step entirely if no linked workspace was found.

**Workspace installs** write to the workspace-root `update-history.md` (NOT a platform subdir).

**Routing logic** (uses `resolve_target_platform()` from `setup.md` Step 15c). Uses a `SKIP_AUDIT` flag instead of `return` so the block embeds cleanly in any caller context:

```bash
SKIP_AUDIT=false
PLATFORM=""

# Determine which workspace owns the audit trail and which platform subdir gets the entry
if [ "$INSTALL_ROLE" = "workspace" ]; then
  workspace_root="$TARGET_PROJECT"
  PLATFORM="workspace"   # sentinel — entry goes to root update-history.md
else
  # Code-repo install — locate the linked workspace from Phase 1 step 1a-2's detection
  workspace_root="$LINKED_WORKSPACE_PATH"
  if [ -z "$workspace_root" ]; then
    echo "Note: no linked workspace detected for $TARGET_PROJECT — skipping audit-entry write."
    SKIP_AUDIT=true
  else
    PLATFORM=$(resolve_target_platform "$TARGET_PROJECT" "$workspace_root/.claude/config_hints.json")
    if [ -z "$PLATFORM" ]; then
      # Reverse-lookup failed AND no persisted parent_workspace_platform.
      # Prompt once for the platform and persist for next time.
      platforms_list=$(jq -r '.platforms[]?' "$workspace_root/.claude/config_hints.json")
      echo "Could not auto-resolve which platform $TARGET_PROJECT belongs to."
      echo "Workspace platforms available: $platforms_list"
      echo "Pick one (will be persisted as parent_workspace_platform):"
      read -r PLATFORM
      if [ -n "$PLATFORM" ]; then
        tmp=$(mktemp)
        jq --arg p "$PLATFORM" '.parent_workspace_platform = $p' \
          "$TARGET_PROJECT/.claude/config_hints.json" > "$tmp" \
          && mv "$tmp" "$TARGET_PROJECT/.claude/config_hints.json"
      else
        # User skipped the prompt — don't write a corrupt path like $fw_dir//update-history.md.
        echo "No platform provided — skipping audit-entry write for this run."
        SKIP_AUDIT=true
      fi
    fi
  fi
fi
```

If `SKIP_AUDIT=true`, skip the entry-write block below; otherwise proceed.

**Then prepend the entry** (newest-first ordering — never append to the bottom):

```markdown
## {YYYY-MM-DD} — v{PROJECT_VERSION} → v{FRAMEWORK_VERSION} (upgrade)

**Platform:** {Backend | Frontend | workspace}

**Framework changes applied:**
- {1–3 headline changes pulled from CHANGELOG Summary lines between PROJECT_VERSION and FRAMEWORK_VERSION}

**Project customizations preserved:**
- {1–3 specific items kept verbatim: tuned thresholds, custom sections, override blocks. Use "n/a — no project customizations detected" if literally nothing was found, but be honest — vague entries like "various customizations preserved" are forbidden and defeat the purpose of the audit trail.}

**Optimizer findings:** {one-line summary from step 5d-3 below, or "Clean" if nothing flagged}

**Files touched:** {N} files updated, {M} files added, {K} files renamed. (Read `_install_manifest.json` for the per-file detail if needed — the manifest is not persisted in the history file.)
```

9–13 lines per entry. Each platform's history file stays readable on one screen.

**Why per-platform:** Backend's example-service and Frontend's example-web are upgraded independently. The v6.8.0–v6.9.0 design wrote everything to one workspace-root file, conflating per-platform updates. v6.10.0 splits them so each platform has its own clean audit trail.

**Pre-v6.10.0 legacy:** if the workspace has a root `update-history.md` (from v6.8.0–v6.9.0), leave it in place — it stays as the workspace-tier audit. Pre-v6.4.0–v6.7.0 subdirectories (`update_reports/`, `planned_updates/`, `update_template/`, `README.md`) likewise. The framework doesn't auto-clean. Teams remove what they want with their own `rm -rf` at leisure.

### 5d-3. Run Scoped AI Optimizer

Run `aa-optimizer` **scoped to only the files this upgrade touched**, not the whole project. This catches redundancy or staleness introduced specifically by the upgrade without disturbing other tuning elsewhere.

Build the scope file list from `_install_manifest.json` (or inline-mode manifest). Then invoke aa-optimizer with the scope:

```bash
# Build scope from manifest
scope_files=$(jq -r '.files_written[] | "{TARGET_PROJECT}/" + .' {TARGET_PROJECT}/_install_manifest.json 2>/dev/null \
              || echo "{newline-separated list from inline mode}")

# Pass to aa-optimizer (see aa-optimizer SKILL.md "Scoped Mode" section)
# The optimizer's Phase 1 discovery is replaced with this fixed list when scope is provided.
```

Tell the user:

```
Running aa-optimizer scoped to the {N} files updated in this upgrade.
This will NOT audit files outside the upgrade scope — your existing tuning in untouched files is safe.

To audit the full project later: open a new Claude session and say `aa-optimizer` (with no scope).
```

**Where findings land:**
- **Workspace installs:** include the one-line summary in the "Optimizer findings:" line of the audit entry written in step 5d-2.
- **Code-repo installs:** print findings to console only. No persistent file.

### 5e. Summary

```
Updated AI Awareness: v{PROJECT_VERSION} → v{FRAMEWORK_VERSION}
Mode: {inline/single-agent/full-pipeline}
Install role: {INSTALL_ROLE}

Files updated:
- {file1} — {what changed}
- {file2} — {what changed}
...

{if any new skills/agents added:}
New skills/agents added:
- {name} — {description}

Verification: {PASS (inline/single-agent self-verified) | PASS (contamination checker)}

{If INSTALL_ROLE == "workspace":}
Audit entry appended to:
  dirname({TARGET_PROJECT})/{ProjectName}_AIAwarenessFramework/update-history.md

{If INSTALL_ROLE == "code-repo": skip the audit-entry line entirely — code repos don't get one. Framework version is tracked in AGENTS.md footer.}

Scoped optimizer pass:
  {N} files audited (scope = files updated by this upgrade only).
  {findings summary, or "Clean — no issues flagged"}

{If INSTALL_ROLE == "workspace":}
Workspace upgrade complete. Commit and push to main have been done automatically
(see step 5e-2 above). Workspace installs don't use PRs.

{If INSTALL_ROLE == "code-repo":}
Code-repo upgrade complete. Changes committed locally to branch '{BRANCH}'.
To ship: push to origin and open a PR.
  cd {TARGET_PROJECT}
  git push -u origin {BRANCH}
  gh pr create --base {DEFAULT_BRANCH} --title "Update AI Awareness to v{FRAMEWORK_VERSION}"

Next: Run "aa-init-skills" if new skills were added.
```

### 5e-2. Commit and Push (NEW in v6.7.0)

After everything above — framework files updated, optimizer run, audit entry appended for workspace installs — the changes are sitting in the working tree. Leaving them uncommitted creates a half-state: the user reads "Upgraded" but `git status` shows dirty files, and for workspace installs the freshly-appended `update-history.md` is never pushed.

This step closes the loop. **For each target processed in this upgrade run**:

```bash
# Discover the target's git root
target_repo_root=$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)
if [ -z "$target_repo_root" ]; then
  echo "Skip commit/push for $target — not a git repo"
  continue
fi

# Anything to commit?
if [ -z "$(git -C "$target_repo_root" status --porcelain)" ]; then
  echo "Nothing to commit for $target (no working-tree changes)"
  continue
fi

# Stage framework-managed paths
git -C "$target_repo_root" add .claude/ 2>/dev/null || true
[ -f "$target_repo_root/AGENTS.md" ] && git -C "$target_repo_root" add AGENTS.md
[ -f "$target_repo_root/CLAUDE.md" ] && git -C "$target_repo_root" add CLAUDE.md

# v6.10.0 change: stage only the platform-specific audit files touched by THIS upgrade run,
# not the whole {ProjectName}_AIAwarenessFramework/ directory. Prevents cross-platform commits
# when only one platform was upgraded (e.g., Backend upgrade shouldn't include Frontend's audit changes).
#
# For workspace installs: also stage the workspace-root update-history.md (workspace-tier audit).
# For code-repo installs: stage only $PLATFORM/update-history.md inside the linked workspace's audit dir.
# Find the audit dir (may live in a sibling git repo if the workspace repo encompasses the parent of the install root).
ai_fw_dir=$(find "$target_repo_root" -maxdepth 3 -type d -name "*_AIAwarenessFramework" -print -quit 2>/dev/null)
# If not in this repo, check the workspace_root's git repo (linked workspace case)
if [ -z "$ai_fw_dir" ] && [ -n "$workspace_root" ]; then
  workspace_repo_root=$(git -C "$workspace_root" rev-parse --show-toplevel 2>/dev/null)
  if [ -n "$workspace_repo_root" ]; then
    ai_fw_dir=$(find "$workspace_repo_root" -maxdepth 3 -type d -name "*_AIAwarenessFramework" -print -quit 2>/dev/null)
    # Switch to the workspace's repo for the audit-dir staging
    target_repo_root_for_audit="$workspace_repo_root"
  fi
else
  target_repo_root_for_audit="$target_repo_root"
fi

if [ -n "$ai_fw_dir" ] && [ -n "$PLATFORM" ]; then
  if [ "$PLATFORM" = "workspace" ]; then
    # Stage only the workspace-root update-history.md (not platform subdirs)
    [ -f "$ai_fw_dir/update-history.md" ] && \
      git -C "$target_repo_root_for_audit" add "$ai_fw_dir/update-history.md" 2>/dev/null || true
  else
    # Stage only this platform's subdir contents (update-history.md and improvements/ dir as appropriate)
    [ -d "$ai_fw_dir/$PLATFORM" ] && \
      git -C "$target_repo_root_for_audit" add "$ai_fw_dir/$PLATFORM" 2>/dev/null || true
  fi
fi
# Note: do NOT stage other platforms' subdirs. A Backend upgrade should not touch Frontend's audit files,
# and shouldn't include them in this commit even if their state is dirty for some unrelated reason.

# Commit
COMMIT_MSG="aa-upgrade: framework v${PROJECT_VERSION} -> v${FRAMEWORK_VERSION} (${INSTALL_ROLE} install)"
if git -C "$target_repo_root" commit -m "$COMMIT_MSG" 2>&1; then
  echo "✅ Committed: $COMMIT_MSG  (in $target_repo_root)"
else
  echo "⚠️ Commit failed for $target_repo_root — see output above. Resolve manually."
  continue
fi
```

**Push behaviour depends on install_role:**

- **`install_role: "workspace"` → silent auto-push.** Matches the existing **Docs Auto-Push** convention in `aa-task-flow/SKILL.md`: workspace/docs repos don't have PR gating, commits flow directly to the shared branch, and the team relies on auto-push to keep everyone in sync. If push fails (rejected, network), warn but don't block — the developer pushes manually.
- **`install_role: "code-repo"` → DO NOT auto-push.** Code repos have PR conventions and CI; the developer creates a PR themselves. Tell them which branch to push:

```bash
if [ "$INSTALL_ROLE" = "workspace" ]; then
  # Pull-rebase first to absorb any colleague pushes since the report was generated
  if ! git -C "$target_repo_root" pull --rebase 2>/dev/null; then
    echo "⚠️ Pull-rebase failed for workspace at $target_repo_root — resolve conflicts then push manually."
    continue
  fi
  if git -C "$target_repo_root" push 2>&1; then
    echo "✅ Pushed workspace changes to remote ($target_repo_root)"
  else
    echo "⚠️ Push failed for workspace at $target_repo_root — please push manually."
  fi
elif [ "$INSTALL_ROLE" = "code-repo" ]; then
  current_branch=$(git -C "$target_repo_root" branch --show-current)
  echo "📌 Committed locally to branch '$current_branch' in $target_repo_root."
  echo "    To push and open a PR:"
  echo "      cd $target_repo_root"
  echo "      git push -u origin $current_branch"
  echo "      gh pr create --base main --title 'Update AI Awareness to v${FRAMEWORK_VERSION}'"
fi
```

**Why this asymmetry:**

| install_role | Commit | Push | Why |
|---|---|---|---|
| `workspace` | auto | auto (silent) | Docs/tasks repos are shared mutable state; the team's convention is "push so others see it immediately". Mirrors `aa-task-flow`'s Docs Auto-Push. |
| `code-repo` | auto | **NO** — instructs user how | Code repos have PR review and CI; auto-pushing without a PR is wrong. The developer pushes when they're ready to open a PR. |

**Safety rules:**

- Never push if `git status` shows files outside the framework-managed paths above. Suggests the user has uncommitted unrelated work; protect it.
- Never push to `main` or `master` regardless of install_role. If the workspace install's current branch is `main`/`master`, commit only and warn — the team should rebase manually.
- Always pull-rebase before pushing a workspace install, to handle concurrent docs-repo activity from teammates.

**Idempotent re-runs:** If `aa-upgrade` is re-run with no actual changes, the `git status --porcelain` check above returns empty and this step silently no-ops. No empty commits.

### 5f. Run AI Optimizer (Recommended)

Tell the user:
```
Update complete! It's recommended to run the AI Optimizer to optimize
the updated files — it removes redundancy, rule echoes, and token bloat.

Would you like to run AI Optimizer now? (y/n)
```

If yes, the user should open a new Claude session in the target project and say `aa-optimizer`.

### 5g. Post-Setup Validation (Optional)

Follow `setup.md` Step 17 if rubric-scanner is available.
