---
name: aa-record-improvement
description: Record a framework improvement suggestion from any target project. Saves structured improvement files to the workspace's shared improvements/ directory for aa-add-improvement to consume later. Say "aa-record-improvement" or "record improvement".
disable-model-invocation: false
---

# Record Improvement

Quick 4-step capture: describe the issue, confirm category, set priority, done.

## When to Use

- You notice a skill bug or missing feature while working in a target project
- You discover a better pattern that should be in the framework
- You want to suggest a new rule, agent, or template
- You worked around a framework limitation and want it fixed

## Prerequisites

- Current project must be an AI Awareness target project (has `.claude/config_hints.json`)
- The target's `config_hints.json` should reference a workspace via `paths.tasks_root` in `.claude/skill.config`, OR have `parent_workspace_path` set explicitly

## Where output goes (v6.10.0 change)

Improvements are no longer written to each code repo's `.claude/improvements/`. They're written to the **workspace's shared improvements directory** (v7.1.0 change — previously was per-platform under `<Platform>/improvements/`):

```
dirname({workspace install root})/{ProjectName}_AIAwarenessFramework/improvements/{YYYY-MM-DD}-{slug}.md
```

For example, an improvement recorded from `example-service` (Backend code repo) lands in:

```
/path/to/workspace/Example_AIAwarenessFramework/improvements/2026-05-15-aa-pr-retry-rate-limit.md
```

Backend and Frontend devs both write to the same `improvements/` directory. The `platform: <Backend|Frontend|...>` frontmatter field distinguishes platform-specific items when needed. Concurrent same-day-same-slug collisions append `-2`, `-3`, ... (same as before — file-level concurrency safety is unaffected).

**Backward compat:** `aa-add-improvement` still scans the legacy `<Platform>/improvements/` paths for any improvements recorded against older framework versions. Existing files under `<Platform>/improvements/` keep working; new recordings always go to the shared dir.

## Steps

### Step 1: Detect Project Context

```bash
# Verify this is an AI Awareness project
[ -f ".claude/config_hints.json" ] || { echo "ERROR: Not an AI Awareness project"; exit 1; }

# Anchor TARGET_PROJECT to the current working directory. All later steps reference
# $TARGET_PROJECT/.claude/skill.config and $TARGET_PROJECT/.claude/config_hints.json
# explicitly rather than relying on relative paths — this is robust against cd's
# inside the discovery helpers.
TARGET_PROJECT="$(pwd)"

# Read project info
PROJECT_NAME=$(jq -r '.project.name // .project_name' "$TARGET_PROJECT/.claude/config_hints.json")
FRAMEWORK_VERSION=$(jq -r '.framework_version' "$TARGET_PROJECT/.claude/config_hints.json")
INSTALL_ROLE=$(jq -r '.install_role // "code-repo"' "$TARGET_PROJECT/.claude/config_hints.json")
```

### Step 2: Locate the linked workspace + resolve platform

For **code-repo installs** (`INSTALL_ROLE = code-repo`):

The skill discovers the workspace by walking parent directories. It does NOT silently mutate `config_hints.json` (which is install-time configuration, not per-skill cache). Resolved workspace path and platform are cached in `.claude/skill.config` (the runtime config file) under a `record_improvement.*` namespace — this file is already runtime-mutable and gitignored.

```bash
# Walk up from cwd looking for a workspace install whose .claude/config_hints.json
# declares install_role: workspace AND has github_repos containing the current code repo's remote.
# Checks BOTH the directory itself AND its children at each parent level (v7.0.0 fix —
# previous versions only checked children, missing the case where the workspace IS the ancestor).
discover_workspace_for_target() {
  local target="$1"
  local remote_url=$(git -C "$target" remote get-url origin 2>/dev/null)
  local owner_repo=$(echo "$remote_url" | sed -E 's#^git@github.com:##; s#^https?://github.com/##; s#\.git$##')

  # Read cache from runtime config (skill.config) — not config_hints.json
  local skill_config="$target/.claude/skill.config"
  if [ -f "$skill_config" ]; then
    local cached=$(awk -F= '/^record_improvement.workspace_path=/ { sub(/^[^=]+=/, ""); print; exit }' "$skill_config")
    if [ -n "$cached" ] && [ -d "$cached/.claude" ]; then
      echo "$cached"
      return 0
    fi
  fi

  # Inline helper: does this candidate config look like a workspace that owns our remote?
  candidate_matches() {
    local config="$1"
    [ -f "$config" ] || return 1
    local role=$(jq -r '.install_role // ""' "$config" 2>/dev/null)
    [ "$role" = "workspace" ] || return 1
    local matched=$(jq --arg ref "$owner_repo" -r \
      '.github_repos // {} | to_entries[] | select(.value == $ref) | .key' "$config" 2>/dev/null)
    [ -n "$matched" ]
  }

  # Walk up from cwd, up to 6 parent levels. At each level check:
  # (a) the level itself  — `$p/.claude/config_hints.json` — in case the workspace IS the ancestor
  # (b) its immediate children — `$p/*/.claude/config_hints.json` — siblings of our target
  #
  # NOTE: use `find` for the children scan instead of a bare glob loop.
  # zsh's default settings (no `nullglob`) make the glob error out if nothing
  # matches the pattern, which we DO hit at the upper parent levels where
  # there's no .claude/config_hints.json under any sibling.
  local p="$(cd "$target" && pwd)"
  for i in 0 1 2 3 4 5 6; do
    if candidate_matches "$p/.claude/config_hints.json"; then
      echo "$p"
      return 0
    fi
    while IFS= read -r candidate; do
      [ -z "$candidate" ] && continue
      if candidate_matches "$candidate"; then
        echo "$(dirname "$(dirname "$candidate")")"
        return 0
      fi
    done < <(find "$p" -mindepth 3 -maxdepth 3 -path '*/.claude/config_hints.json' 2>/dev/null)
    p="$(dirname "$p")"
    [ "$p" = "/" ] && return 0
  done
}

# Tiny helper to write a key=value into skill.config (creates the file if missing)
cache_resolved() {
  local key="$1" value="$2"
  local cfg="$TARGET_PROJECT/.claude/skill.config"
  [ -d "$(dirname "$cfg")" ] || mkdir -p "$(dirname "$cfg")"
  if [ -f "$cfg" ] && grep -q "^${key}=" "$cfg"; then
    # Replace existing line
    local tmp=$(mktemp)
    awk -F= -v k="$key" -v v="$value" '$1 == k { print k "=" v; next } { print }' "$cfg" > "$tmp" \
      && mv "$tmp" "$cfg"
  else
    printf '%s=%s\n' "$key" "$value" >> "$cfg"
  fi
}

WORKSPACE_INSTALL=$(discover_workspace_for_target ".")
if [ -z "$WORKSPACE_INSTALL" ]; then
  # Last resort: ask the user
  echo "Could not auto-discover the linked workspace for this project."
  echo "Please provide the full path to the workspace install root (e.g., /path/to/workspace/Example_Coding_Tasks):"
  read -r WORKSPACE_INSTALL
fi
[ -n "$WORKSPACE_INSTALL" ] && cache_resolved "record_improvement.workspace_path" "$WORKSPACE_INSTALL"

# Reverse-lookup the platform from the workspace's github_repos
remote_url=$(git remote get-url origin)
owner_repo=$(echo "$remote_url" | sed -E 's#^git@github.com:##; s#^https?://github.com/##; s#\.git$##')
PLATFORM=$(jq --arg ref "$owner_repo" -r '.github_repos // {} | to_entries[] | select(.value == $ref) | .key' "$WORKSPACE_INSTALL/.claude/config_hints.json" | head -1)

# Fallback to cached platform from skill.config
if [ -z "$PLATFORM" ] && [ -f "$TARGET_PROJECT/.claude/skill.config" ]; then
  PLATFORM=$(awk -F= '/^record_improvement.platform=/ { sub(/^[^=]+=/, ""); print; exit }' "$TARGET_PROJECT/.claude/skill.config")
fi

# Last fallback: prompt
if [ -z "$PLATFORM" ]; then
  echo "Could not auto-detect platform. Workspace platforms available:"
  jq -r '.platforms[]?' "$WORKSPACE_INSTALL/.claude/config_hints.json"
  echo "Pick one:"
  read -r PLATFORM
fi
[ -n "$PLATFORM" ] && cache_resolved "record_improvement.platform" "$PLATFORM"
```

For **workspace installs** (`INSTALL_ROLE = workspace`): the cwd is the workspace itself. Ask the user which platform the improvement is for, since improvements are always tied to an actual code project:

```bash
if [ "$INSTALL_ROLE" = "workspace" ]; then
  WORKSPACE_INSTALL="$(pwd)"
  echo "Which platform does this improvement target?"
  jq -r '.platforms[]?' .claude/config_hints.json
  echo "Pick one:"
  read -r PLATFORM
fi
```

### Step 3: Ask What to Improve

```
What improvement do you want to record?

Examples:
  "aa-pr skill should retry on 403 rate limit errors"
  "Add a rule for React Query cache invalidation patterns"
  "aa-task-flow Phase 3 doesn't handle monorepo ticket prefixes"
  "aa-code-reviewer agent flags test files for missing error handling"

Your description:
```

Store as `DESCRIPTION`.

### Step 4: Determine Category

Auto-detect category from the description:
- Mentions a skill name (aa-task-flow, aa-pr, etc.) → `skill`
- Mentions agent (aa-code-reviewer, aa-test-runner, etc.) → `agent`
- Mentions rule, pattern, convention → `rule`
- Mentions setup, installation, update → `setup`
- Mentions template, PR template, commit template → `template`
- Otherwise → `other`

Also extract the specific target name if mentioned (e.g., "aa-pr" from "aa-pr skill should retry").

### Step 4b: For `rule` category — determine the tier (W8)

If `CATEGORY = rule`, also decide which **rule tier** it belongs to, so `aa-add-improvement` places it correctly (rules are tiered: `universal/` = cross-language, plus per-stack `java-spring-boot/`, `react/`, `go/`, …). Misfiling a stack-specific rule under `universal/` would leak it to every stack — the same class of bug we fixed for skills.

Decide `TIER`:
- **`universal`** — the rule is a cross-language principle (review discipline, critical thinking, test-change policy, doc/observability conventions that don't depend on language).
- **`<stack>`** — the rule names language/framework idioms (annotations, ORM, build tool, language-specific patterns). Default `<stack>` to this project's stack from `config_hints.json` (`.stack`, else `.platform`).

Confirm with user:

```
Detected:
  Category: {category}
  Target: {target name or "general"}
{if category == rule:}  Tier: {universal | <stack>}  (where stack-specific rules live)

Correct? (y/n, or type the correct category/tier)
```

Store `CATEGORY`, `TARGET`, and (for rules) `TIER`.

### Step 5: Ask Priority

```
Priority?
  1. bug - Something is broken or produces wrong results
  2. should-fix - Significant gap or frequent pain point
  3. nice-to-have - Would be better but not blocking

Your choice:
```

Store as `PRIORITY`.

### Step 6: Optional Context

```
Want to add context? (code snippet, file path, diff, or workaround you used)

Type it below, or press enter to skip:
```

If provided, store as `CONTEXT`.

### Step 6.5: Dedup + Contradiction Gate (before writing)

**Do not write blind.** Before creating a new file, scan the existing pending backlog and classify the new improvement against it. The goal is a **coherent end state**, not fewer files — never silently drop content.

Scan all `status: pending` items in the shared `improvements/` dir (plus the legacy `<Platform>/improvements/` and code-repo `.claude/improvements/` paths, for backward compat).

**A. Semantic dedup — match on meaning, not slug.** The `-2`/`-3` same-slug suffix only catches *identical* slugs; two recordings of the *same issue* with different wording slip through (this actually happened: `verify-step-skips-opt-in-integration-tests` vs `aa-task-flow-verify-green-skips-opt-in-integration-tests` — same gap, different slugs). Match on frontmatter `target` overlap **AND** topical overlap (keyword/area), not the generated slug.

**B. Contradiction detection.** Flag when an existing pending item proposes an **incompatible direction** for the same target/area (opposite fix, conflicting convention). This matters because multiple teams consume this framework — a contradictory backlog ships an incoherent change.

**Resolution (never silent removal):**

| Finding | Action |
|---|---|
| **Duplicate / overlap** | Default to **enriching the existing canonical record in place** — append a dated `## Update (YYYY-MM-DD)` block, merge the new context, reconcile frontmatter (e.g. raise `priority`). Only create a separate file if the user confirms the slices are genuinely distinct. |
| **Contradiction** | Present **both** to the user, **ask which to prefer**, then **adjust the records** to reflect the decision — reconcile into one, or mark the superseded one `status: superseded` with a pointer to the winner. The loser is annotated, never deleted. |
| **No match** | Proceed to Step 7 (write a new file). |

This mirrors correct manual handling: update-then-dedupe, not delete. A duplicate is removed only *after* its content is folded into the canonical record.

### Step 7: Write Improvement File

```bash
# Derive workspace framework dir. The improvements dir is SHARED across platforms
# (v7.1.0 change — previously was per-platform under <Platform>/improvements/, but
# most improvements are framework-wide so the platform split produced duplicate
# entries when Backend + Frontend devs hit the same skill defect). The
# `platform: <Backend|Frontend|...>` frontmatter field is sufficient to distinguish
# platform-specific items when needed.
#
# Read project_name first (slug is the reliable form for dir derivation).
# jq's // operator does NOT catch type errors, only null/false — so if .project is a
# string (a display name) the bare `.project.name // .project_name` filter ERRORS
# with "Cannot index string with string". Guard the .project lookup explicitly.
workspace_project_name=$(jq -r '.project_name // (.project | if type == "object" then .name else . end)' "$WORKSPACE_INSTALL/.claude/config_hints.json")

# If project_name is already pascal-cased on disk (e.g. "Example_Project"), the awk
# pass below is a no-op. If it's snake/kebab/lower-case, awk pascal-cases it.
case "$workspace_project_name" in
  *_[A-Z]*|[A-Z]*) pascal_name="$workspace_project_name" ;;
  *) pascal_name=$(echo "$workspace_project_name" | awk -F'[_-]' '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)} 1' OFS='_') ;;
esac

fw_dir="$(dirname "$WORKSPACE_INSTALL")/${pascal_name}_AIAwarenessFramework"
improvements_dir="$fw_dir/improvements"
mkdir -p "$improvements_dir"

# Generate a slug from the description (first 5-6 meaningful words, kebab-case)
DATE=$(date +%Y-%m-%d)
slug=$(echo "$DESCRIPTION" | tr '[:upper:]' '[:lower:]' | tr -s ' ' '-' | tr -dc 'a-z0-9-' | cut -c1-60)
filename="${DATE}-${slug}.md"
target_file="$improvements_dir/$filename"

# Collision handling: append -N suffix if file already exists
n=2
while [ -e "$target_file" ]; do
  filename="${DATE}-${slug}-${n}.md"
  target_file="$improvements_dir/$filename"
  n=$((n+1))
done

cat > "$target_file" <<EOF
---
source_project: ${PROJECT_NAME}
platform: ${PLATFORM}
framework_version: ${FRAMEWORK_VERSION}
category: ${CATEGORY}
target: ${TARGET}
${TIER:+tier: ${TIER}
}priority: ${PRIORITY}
recorded: ${DATE}
status: pending
---

${DESCRIPTION}

## Context
${CONTEXT:-No additional context provided.}
EOF
```

### Step 8: Confirm + Auto-Commit

```
Recorded improvement:

  {DESCRIPTION}
  Platform: {PLATFORM}
  Category: {CATEGORY} ({TARGET})
  Priority: {PRIORITY}
  Source: {PROJECT_NAME} (v{FRAMEWORK_VERSION})
  Saved to: {target_file}

This will be picked up next time someone runs "aa-add-improvement" in the ai-awareness-framework repo
and chooses "Review recorded improvements".
```

Then auto-commit and push the workspace docs repo, staging only `$target_file`. v7.1.0 cleanup:

- **Resolve the git repo from `dirname "$target_file"`, not from `$WORKSPACE_INSTALL`.** In the canonical workspace layout the workspace install root (e.g. `Example_Coding_Tasks`) and the `_AIAwarenessFramework` directory are SIBLINGS, so deriving the repo from `$WORKSPACE_INSTALL` would point at the wrong toplevel and `git add` would fail with "pathspec is outside repository". Resolve from the file's own dir instead.
- **No "other-changes" safety guard.** `git add -- "$target_file"` is precise — it cannot pick up unrelated changes. The earlier safety check (porcelain status filter) was over-conservative AND wrong about untracked-directory entries (`git status` reports the parent dir, not the file, so the file-level exclusion didn't match). Dropped.

```bash
# Resolve the git repo that actually owns $target_file.
repo_root=$(git -C "$(dirname "$target_file")" rev-parse --show-toplevel 2>/dev/null)

if [ -z "$repo_root" ]; then
  echo "⚠️  $target_file is not inside a git repo."
  echo "   The improvement was saved locally but NOT committed or pushed."
  echo "   To make it visible to other team members, place $(dirname "$(dirname "$target_file")") under git tracking, or commit the file manually."
else
  git -C "$repo_root" add -- "$target_file"
  if git -C "$repo_root" diff --cached --quiet -- "$target_file"; then
    echo "Note: no staged change for $target_file (already committed in a previous run?). Skipping commit/push."
  else
    git -C "$repo_root" commit -m "aa-record-improvement: $(basename "$target_file" .md)"
    git -C "$repo_root" pull --rebase || {
      echo "⚠️ Pull-rebase failed (likely a conflict). Resolve in $repo_root, then push manually."
    }
    git -C "$repo_root" push || echo "⚠️ Push failed — push manually from $repo_root."
  fi
fi
```

### Step 9: Reconcile + Sequence the backlog (coherence pass)

After recording, run a coherence pass over the **entire** pending set so the backlog stays sane and `aa-add-improvement` knows what order to apply things in. (The user may frame this as a `/goal` so it keeps working until the backlog is coherent.)

1. **Verify internal consistency** — no leftover contradictions, no near-duplicates the new entry introduced (re-run the Step 6.5 checks across the whole set, not just the new file).
2. **Assign a dependency-aware pick-up sequence.** Some fixes depend on others being in place first — e.g. the behaviour-preserving-test improvement's "verify original tests pass against new code" depends on the opt-in-integration-suite fix already landing; applying them out of order gives a false green. Encode the order as an `improvements/ORDER.md` index (and/or a `sequence:` frontmatter field per item) that the adder consumes.

`ORDER.md` format (regenerate on each reconcile; it is an index, not an improvement — give it `kind: index` and no `status: pending` so it isn't itself picked up):

```markdown
---
kind: index
generated: YYYY-MM-DD
note: Pick-up sequence for pending improvements. aa-add-improvement applies in this order.
---
# Pending improvements — pick-up sequence

| # | Order | File | Target | Priority | Depends on |
|---|-------|------|--------|----------|-----------|
| 1 | apply first | <file> | <target> | <priority> | — |
| 2 | after #1 | <file> | <target> | <priority> | #1 |

## Contradictions
(none) — or list each with the user's chosen winner and how the loser was annotated.
```

If a future recording contradicts an existing one, the reconcile pass must surface **both**, ask the user which to prefer, and adjust the records — never silently drop content.

## Notes

- Output lives in the **workspace** (not the code repo). v6.10.0 change — pre-v6.10.0 outputs in code-repo `.claude/improvements/` are still picked up by `aa-add-improvement` for backward compat, but new recordings always go to the workspace.
- File-per-improvement means concurrent workers don't conflict at the file level. Same-day-same-slug collisions append `-2`, `-3`.
- Resolved workspace path and platform are cached in `.claude/skill.config` (runtime config, gitignored) under the `record_improvement.*` namespace — NOT in `config_hints.json`, which is install-time configuration and should not mutate silently. v7.0.0 fix.
- Keep descriptions actionable — say what should change, not just what's wrong.
