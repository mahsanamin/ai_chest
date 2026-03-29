#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.claude/skills"

echo "=== Task Flow — Install Global Tools ==="
echo "Destination: $DEST"
echo ""

mkdir -p "$DEST"

installed=0
updated=0
current=0

for tool_dir in "$SCRIPT_DIR/skills/task-flow-tool:"*/; do
  [ -d "$tool_dir" ] || continue
  tool_name="$(basename "$tool_dir")"
  source_file="$tool_dir/SKILL.md"
  dest_dir="$DEST/$tool_name"
  dest_file="$dest_dir/SKILL.md"

  [ -f "$source_file" ] || continue

  if [ ! -f "$dest_file" ]; then
    status="NEW"
    ((installed++)) || true
  elif ! diff -q "$source_file" "$dest_file" &>/dev/null; then
    status="UPDATED"
    ((updated++)) || true
  else
    status="current"
    ((current++)) || true
    echo "  ✓ $tool_name (up to date)"
    continue
  fi

  mkdir -p "$dest_dir"
  cp "$source_file" "$dest_file"
  if [ "$status" = "NEW" ]; then
    echo "  + $tool_name (installed)"
  else
    echo "  ~ $tool_name (updated)"
  fi
done

echo ""
if [ $installed -eq 0 ] && [ $updated -eq 0 ]; then
  echo "All global tools are already up to date."
else
  echo "Done: $installed new, $updated updated, $current already current."
fi
echo ""
echo "Global tools are available in ALL projects via Claude Code:"
echo "  - task-flow-tool:ai-optimizer"
echo "  - task-flow-tool:review-pr"
