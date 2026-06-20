#!/usr/bin/env bash
# AI Awareness — global tools installer (shell-only, no Claude Code required).
#
# Run this from the framework repo root to install/refresh ~/.claude/scripts,
# ~/.claude/agents, and every global skill listed in scripts/manifest.json's
# `global_skills` array. Safe to re-run — every step is idempotent.
#
# Teammates use this to stay current with the framework after a `git pull`.
# The Claude Code skill aa-install-tools is a thin wrapper that calls this script.

set -euo pipefail

# Resolve the framework root from this script's own location, so the script
# works no matter where it's invoked from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$SCRIPT_DIR"

if [ ! -f "$FRAMEWORK_DIR/scripts/manifest.json" ]; then
  echo "Error: $FRAMEWORK_DIR doesn't look like the AI Awareness framework root" >&2
  echo "  (no scripts/manifest.json found)" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required but not installed. brew install jq" >&2
  exit 1
fi

MANIFEST="$FRAMEWORK_DIR/scripts/manifest.json"

echo "AI Awareness tools installer"
echo "  Framework: $FRAMEWORK_DIR"
echo "  Target:    ~/.claude/"
echo ""

# ---------------------------------------------------------------------------
# Step 1: install/refresh scripts declared in manifest.json
# ---------------------------------------------------------------------------
echo "→ Installing scripts (~/.claude/scripts/)"
mkdir -p "$HOME/.claude/scripts"

jq -r '.scripts[] | select(.install == "global" or .install == "sourced") | .name' "$MANIFEST" |
  while read -r rel; do
    src="$FRAMEWORK_DIR/scripts/$rel"
    if [ ! -f "$src" ]; then
      echo "  warn: manifest references missing file: scripts/$rel" >&2
      continue
    fi
    dest="$HOME/.claude/scripts/$rel"
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    chmod +x "$dest" 2>/dev/null || true
    echo "    $rel"
  done

# ---------------------------------------------------------------------------
# Step 2: install/refresh agents
# ---------------------------------------------------------------------------
echo ""
echo "→ Installing agents (~/.claude/agents/)"
mkdir -p "$HOME/.claude/agents"
for agent_dir in "$FRAMEWORK_DIR"/agents/*/; do
  [ -d "$agent_dir" ] || continue
  agent_name="$(basename "$agent_dir")"
  if [ -f "$agent_dir/AGENT.md" ]; then
    cp "$agent_dir/AGENT.md" "$HOME/.claude/agents/$agent_name.md"
    echo "    $agent_name.md"
  fi
done

# ---------------------------------------------------------------------------
# Step 3: install/refresh global skills declared in manifest.json
#
# The list of global skills lives in scripts/manifest.json under
# `global_skills`. Adding a new global skill is a manifest edit — no change
# in this script required. Each entry has `name`, `source` (relative to
# framework root), and `target` (under ~/.claude/skills/).
# ---------------------------------------------------------------------------
echo ""
echo "→ Installing global skills (~/.claude/skills/)"
mkdir -p "$HOME/.claude/skills"

jq -r '.global_skills[]? | "\(.name)\t\(.source)"' "$MANIFEST" |
  while IFS=$'\t' read -r skill_name skill_source; do
    [ -z "$skill_name" ] && continue
    src="$FRAMEWORK_DIR/$skill_source"
    if [ ! -d "$src" ]; then
      echo "  warn: manifest references missing skill source: $skill_source" >&2
      continue
    fi
    dest="$HOME/.claude/skills/$skill_name"
    rm -rf "$dest"
    cp -R "$src" "$dest"
    echo "    $skill_name"
  done

# ---------------------------------------------------------------------------
# Step 4: wire sourced helpers (and AA_FRAMEWORK_DIR) into shell-rc
#
# Idempotent: if the block exists, it's replaced; otherwise appended.
# The block exports AA_FRAMEWORK_DIR so other tools (e.g., worktree.sh's
# startup freshness check) can locate the framework repo without hardcoding.
# ---------------------------------------------------------------------------
echo ""
echo "→ Wiring shell-rc"

RC_FILE=""
if [ -n "${ZSH_VERSION:-}" ] || [[ "${SHELL:-}" == */zsh ]]; then
  RC_FILE="$HOME/.zshrc"
elif [ -n "${BASH_VERSION:-}" ] || [[ "${SHELL:-}" == */bash ]]; then
  RC_FILE="$HOME/.bashrc"
fi

if [ -z "$RC_FILE" ]; then
  echo "    note: unrecognised shell ($SHELL); add the sourced block manually." >&2
else
  MARKER_START="# >>> AI Awareness sourced helpers (managed by install-tools.sh) >>>"
  MARKER_END="# <<< AI Awareness sourced helpers <<<"
  # Also strip the legacy v6.x marker if present, so we don't end up with two blocks.
  LEGACY_START="# >>> AI Awareness sourced helpers (managed by aa-install-tools) >>>"

  SOURCED="$(jq -r '.scripts[] | select(.install == "sourced") | .name' "$MANIFEST")"

  touch "$RC_FILE"

  # Pre-product: if start/end markers are unbalanced (user hand-edited the
  # block and left a dangling start, or deleted only an end line), the awk
  # strip below would set skip=1 at the orphan start and never reset, silently
  # truncating everything from that line to EOF. Refuse to touch the file —
  # the user must reconcile manually.
  start_count=$(grep -cF "$MARKER_START" "$RC_FILE" || true)
  legacy_count=$(grep -cF "$LEGACY_START" "$RC_FILE" || true)
  end_count=$(grep -cF "$MARKER_END" "$RC_FILE" || true)
  total_starts=$((start_count + legacy_count))
  if [ "$total_starts" -ne "$end_count" ]; then
    echo "Error: $RC_FILE has unbalanced AI Awareness markers" >&2
    echo "  starts (current + legacy): $total_starts" >&2
    echo "  ends:                      $end_count" >&2
    echo "  Refusing to edit — stripping would truncate the file." >&2
    echo "  Fix manually: ensure every '$MARKER_START' (or legacy variant)" >&2
    echo "  is paired with a matching '$MARKER_END' line, then re-run." >&2
    exit 1
  fi

  if grep -qF "$MARKER_START" "$RC_FILE" || grep -qF "$LEGACY_START" "$RC_FILE"; then
    tmp="$(mktemp)"
    awk -v s1="$MARKER_START" -v s2="$LEGACY_START" -v e="$MARKER_END" '
      ($0 == s1 || $0 == s2) { skip = 1; next }
      $0 == e                { skip = 0; next }
      !skip
    ' "$RC_FILE" > "$tmp" && mv "$tmp" "$RC_FILE"
    echo "    refreshed existing block in $RC_FILE"
  else
    echo "    appending block to $RC_FILE"
  fi

  {
    echo ""
    echo "$MARKER_START"
    echo "# Auto-generated by install-tools.sh. Re-run after framework updates."
    # printf '%q' quotes $FRAMEWORK_DIR so any shell metacharacter (space,
    # quote, $, backtick, etc.) round-trips safely through being sourced by
    # bash or zsh. Plain `echo "...\"$FRAMEWORK_DIR\""` would break the rc
    # if the path ever contained a `"` or `$`. %q output is bash-quoting;
    # zsh accepts the same form when sourcing.
    printf 'export AA_FRAMEWORK_DIR=%q\n' "$FRAMEWORK_DIR"
    if [ -n "$SOURCED" ]; then
      while IFS= read -r rel; do
        [ -z "$rel" ] && continue
        echo "[ -f \"\$HOME/.claude/scripts/$rel\" ] && source \"\$HOME/.claude/scripts/$rel\""
      done <<< "$SOURCED"
    fi
    echo "$MARKER_END"
  } >> "$RC_FILE"
fi

# ---------------------------------------------------------------------------
# Step 5: write framework state snapshot
#
# Consumed by scripts/aa-freshness/check.sh. Records the installed framework
# SHA + the list of global skills that were installed THIS run, so the
# freshness check can later detect:
#   - The framework was pulled but install-tools.sh wasn't re-run (HEAD SHA
#     drifted from the installed SHA).
#   - New global skills landed in the manifest since the last install.
# ---------------------------------------------------------------------------
echo ""
echo "→ Writing framework state ($HOME/.claude/.aa-framework-state.json)"

# Last commit that actually touched the framework subtree — when the framework
# lives in a monorepo, the overall HEAD changes for unrelated commits and would
# false-positive the freshness check.
HEAD_SHA="$(git -C "$FRAMEWORK_DIR" log -1 --format=%H -- . 2>/dev/null || echo unknown)"
INSTALLED_AT="$(date +%s)"
GLOBAL_SKILLS_JSON="$(jq -c '[.global_skills[].name]' "$MANIFEST")"

cat > "$HOME/.claude/.aa-framework-state.json" <<EOF
{
  "framework_path": "$FRAMEWORK_DIR",
  "framework_sha": "$HEAD_SHA",
  "installed_at_epoch": $INSTALLED_AT,
  "global_skills": $GLOBAL_SKILLS_JSON
}
EOF

# Reset the freshness-check throttle so the user's NEXT terminal-open will
# immediately re-evaluate against the just-written state (otherwise a stale
# throttle file could suppress the "you're now current" silence and confuse
# anyone debugging the helper).
rm -f "$HOME/.claude/.aa-last-freshness-check" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Step 6: install the framework hints file (~/.claude/aa-framework-hints.md)
#
# Curated catalog of global skills + shell helpers + "prefer the framework's
# helper over raw git/shell" guidance. Referenced from the user's global
# ~/.claude/CLAUDE.md in Step 7 so every Claude Code session discovers it.
# ---------------------------------------------------------------------------
echo ""
echo "→ Installing framework hints ($HOME/.claude/aa-framework-hints.md)"

HINTS_SRC="$FRAMEWORK_DIR/templates/aa-framework-hints.md"
HINTS_DEST="$HOME/.claude/aa-framework-hints.md"
if [ -f "$HINTS_SRC" ]; then
  cp "$HINTS_SRC" "$HINTS_DEST"
  echo "    aa-framework-hints.md"
else
  echo "    warn: $HINTS_SRC missing — skipping" >&2
fi

# ---------------------------------------------------------------------------
# Step 7: register a one-line pointer in the user's global ~/.claude/CLAUDE.md
#
# This is the global discovery channel: a managed block in the user's personal
# Claude config that tells every session "the framework is installed; read the
# hints file for the catalog." Without this, Claude defaults to raw `git
# worktree` commands and never discovers the aa_g_worktree_* suite or the
# global skills.
#
# Skipped if AA_SKIP_GLOBAL_HINT=1 — teammates who don't want any automated
# edits to ~/.claude/CLAUDE.md can opt out.
#
# Balanced-marker pre-product (same pattern as Step 4) refuses to edit on
# mismatch so we can't truncate the user's personal config.
# ---------------------------------------------------------------------------
if [ "${AA_SKIP_GLOBAL_HINT:-0}" = "1" ]; then
  echo ""
  echo "→ Skipping global CLAUDE.md hint registration (AA_SKIP_GLOBAL_HINT=1)"
else
  echo ""
  echo "→ Registering global discovery hint in $HOME/.claude/CLAUDE.md"

  GLOBAL_CLAUDE="$HOME/.claude/CLAUDE.md"
  HINT_START="<!-- >>> AI Awareness framework hint (managed by install-tools.sh) >>> -->"
  HINT_END="<!-- <<< AI Awareness framework hint <<< -->"

  touch "$GLOBAL_CLAUDE"

  start_count=$(grep -cF "$HINT_START" "$GLOBAL_CLAUDE" || true)
  end_count=$(grep -cF "$HINT_END" "$GLOBAL_CLAUDE" || true)
  if [ "$start_count" -ne "$end_count" ]; then
    echo "Error: $GLOBAL_CLAUDE has unbalanced AI Awareness hint markers" >&2
    echo "  starts: $start_count" >&2
    echo "  ends:   $end_count" >&2
    echo "  Refusing to edit — stripping would truncate the file." >&2
    echo "  Fix manually: ensure every '$HINT_START' is paired with a matching" >&2
    echo "  '$HINT_END' line, then re-run. To skip this step entirely:" >&2
    echo "    AA_SKIP_GLOBAL_HINT=1 bash install-tools.sh" >&2
    exit 1
  fi

  if grep -qF "$HINT_START" "$GLOBAL_CLAUDE"; then
    tmp="$(mktemp)"
    awk -v s="$HINT_START" -v e="$HINT_END" '
      $0 == s { skip = 1; next }
      $0 == e { skip = 0; next }
      !skip
    ' "$GLOBAL_CLAUDE" > "$tmp" && mv "$tmp" "$GLOBAL_CLAUDE"
    echo "    refreshed existing block"
  else
    echo "    appending block"
  fi

  {
    echo ""
    echo "$HINT_START"
    echo "<!-- Auto-generated by install-tools.sh. Re-run after framework updates."
    echo "     To remove: delete this block (start to end marker, inclusive)."
    echo "     To skip on future installs: AA_SKIP_GLOBAL_HINT=1 bash install-tools.sh -->"
    echo ""
    echo "The AI Awareness framework is installed on this machine. Read \`~/.claude/aa-framework-hints.md\` for the catalog of global skills (\`aa-optimizer\`, \`aa-record-improvement\`, \`aa-global-pr-reviewer\`) and shell helpers (\`aa_g_worktree_*\`, freshness check)."
    echo ""
    echo "**Worktree guidance (inline so it's always in context):** when the user asks about creating, reviewing, listing, or removing git worktrees, prefer the \`aa_g_worktree_*\` helpers (\`aa_g_worktree_init\`, \`_review\`, \`_list\`, \`_remove\`, \`_doctor\`, \`_prune\`, \`_main\`, \`_switch\`) over raw \`git worktree\` commands. From Claude Code's non-interactive Bash tool, invoke the companion scripts directly: \`bash ~/.claude/scripts/aa-worktree/aa_g_worktree_<name> <args>\`. See \`~/.claude/aa-framework-hints.md\` for the full table and examples."
    echo ""
    echo "$HINT_END"
  } >> "$GLOBAL_CLAUDE"
fi

echo ""
echo "Done. Open a new terminal (or 'source $RC_FILE') to pick up the helpers."
