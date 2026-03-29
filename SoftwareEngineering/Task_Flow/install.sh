#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-.}"
TARGET="$(cd "$TARGET" && pwd)"

echo "=== Task Flow Installer ==="
echo "Target: $TARGET"
echo ""

# Verify target looks like a project
if [ ! -d "$TARGET/.git" ]; then
  read -rp "No .git directory found in $TARGET. Continue anyway? (y/N) " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
fi

# Step 1: Copy project skills (excluding global tools), agents, templates
echo "Installing project skills, agents, and templates..."
mkdir -p "$TARGET/.claude/skills" "$TARGET/.claude/agents" "$TARGET/docs/templates"

# Copy only project-level skills (skip task-flow-tool:* global tools)
for skill_dir in "$SCRIPT_DIR/skills/task-flow"*/; do
  skill_name="$(basename "$skill_dir")"
  # Skip global tools — they are installed separately
  if [[ "$skill_name" == task-flow-tool:* ]]; then
    continue
  fi
  if command -v rsync &>/dev/null; then
    rsync -a "$skill_dir" "$TARGET/.claude/skills/$skill_name/"
  else
    mkdir -p "$TARGET/.claude/skills/$skill_name"
    cp -R "$skill_dir." "$TARGET/.claude/skills/$skill_name/"
  fi
done

# Copy agents and templates
if command -v rsync &>/dev/null; then
  rsync -a "$SCRIPT_DIR/agents/" "$TARGET/.claude/agents/"
  rsync -a "$SCRIPT_DIR/templates/" "$TARGET/docs/templates/"
else
  cp -R "$SCRIPT_DIR/agents/." "$TARGET/.claude/agents/"
  cp -R "$SCRIPT_DIR/templates/." "$TARGET/docs/templates/"
fi

project_skill_count=$(find "$SCRIPT_DIR/skills" -mindepth 1 -maxdepth 1 -type d -not -name 'task-flow-tool:*' | wc -l | tr -d ' ')
global_tool_count=$(find "$SCRIPT_DIR/skills" -mindepth 1 -maxdepth 1 -type d -name 'task-flow-tool:*' | wc -l | tr -d ' ')
echo "  Copied skills:    $project_skill_count project skills (skipped $global_tool_count global tools)"
echo "  Copied agents:    $(find "$SCRIPT_DIR/agents" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ') agents"
echo "  Copied templates: $(find "$SCRIPT_DIR/templates" -mindepth 1 -maxdepth 1 -type f | wc -l | tr -d ' ') templates"

# Step 1b: Install global tools to ~/.claude/skills/
echo ""
echo "Installing global tools to ~/.claude/skills/..."
mkdir -p "$HOME/.claude/skills"
for tool_dir in "$SCRIPT_DIR/skills/task-flow-tool:"*/; do
  [ -d "$tool_dir" ] || continue
  tool_name="$(basename "$tool_dir")"
  if command -v rsync &>/dev/null; then
    rsync -a "$tool_dir" "$HOME/.claude/skills/$tool_name/"
  else
    mkdir -p "$HOME/.claude/skills/$tool_name"
    cp -R "$tool_dir." "$HOME/.claude/skills/$tool_name/"
  fi
  echo "  Installed: $tool_name"
done

# Step 2: Create config_hints.json (interactive)
CONFIG_FILE="$TARGET/.claude/config_hints.json"
if [ -f "$CONFIG_FILE" ]; then
  echo ""
  echo "config_hints.json already exists. Skipping config setup."
  echo "  To reconfigure, delete $CONFIG_FILE and re-run."
else
  echo ""
  echo "--- Project Configuration ---"

  read -rp "Project namespace (e.g., PROJ, AUTH, PAY): " namespace
  read -rp "Project name (e.g., my-project): " project_name
  read -rp "Platform (Backend/Frontend/iOS_Frontend/Android_Frontend): " platform
  read -rp "Standards location (default: docs/ai-rules): " standards_location
  standards_location="${standards_location:-docs/ai-rules}"

  echo ""
  echo "Issue tracker options: jira, github, linear, tiles, none"
  read -rp "Tracker type: " tracker_type
  tracker_type="${tracker_type:-none}"

  tracker_url=""
  if [ "$tracker_type" = "jira" ]; then
    read -rp "Atlassian URL (e.g., your-org.atlassian.net): " tracker_url
  elif [ "$tracker_type" = "tiles" ]; then
    read -rp "Tiles URL: " tracker_url
  elif [ "$tracker_type" = "linear" ]; then
    read -rp "Linear team key (optional, press Enter to skip): " tracker_url
  fi

  # Build JSON safely with jq to avoid injection from special characters
  mkdir -p "$TARGET/.claude"
  jq -n \
    --arg ns "$namespace" \
    --arg name "$project_name" \
    --arg platform "$platform" \
    --arg std "$standards_location" \
    --arg tt "$tracker_type" \
    --arg url "$tracker_url" \
    '{
      project: { namespace: $ns, name: $name },
      platform: $platform,
      standards_location: $std,
      tracker: ({ type: $tt } + if $url != "" then { url: $url } else {} end)
    }' > "$CONFIG_FILE"
  echo "  Created: $CONFIG_FILE"
fi

# Step 3: Create skill.config (interactive, user-specific paths)
SKILL_CONFIG="$TARGET/.claude/skill.config"
if [ -f "$SKILL_CONFIG" ]; then
  echo ""
  echo "skill.config already exists. Skipping path setup."
else
  echo ""
  echo "--- User-Specific Paths (not committed to git) ---"

  read -rp "Tasks root (absolute path, e.g., /Users/you/CodingTasks/Backend): " tasks_root
  read -rp "Docs root (absolute path, e.g., /Users/you/docs): " docs_root
  read -rp "Reviews root (absolute path, optional): " reviews_root

  # Build JSON safely with jq
  jq -n \
    --arg tasks "$tasks_root" \
    --arg docs "$docs_root" \
    --arg reviews "$reviews_root" \
    '{
      paths: ({ tasks_root: $tasks, docs_root: $docs } + if $reviews != "" then { reviews_root: $reviews } else {} end)
    }' > "$SKILL_CONFIG"
  echo "  Created: $SKILL_CONFIG"
fi

# Step 4: Ensure .gitignore entries
GITIGNORE="$TARGET/.gitignore"
touch "$GITIGNORE"
for entry in ".claude/skill.config" ".claude/reviews/"; do
  if ! grep -qF "$entry" "$GITIGNORE" 2>/dev/null; then
    echo "$entry" >> "$GITIGNORE"
    echo "  Added $entry to .gitignore"
  fi
done

# Done
echo ""
echo "=== Task Flow Installed ==="
echo ""
echo "  Project skills: $TARGET/.claude/skills/"
echo "  Agents:         $TARGET/.claude/agents/"
echo "  Templates:      $TARGET/docs/templates/"
echo "  Config:         $TARGET/.claude/config_hints.json"
echo "  Paths:          $TARGET/.claude/skill.config"
echo "  Global tools:   ~/.claude/skills/ (ai-optimizer, review-pr)"
echo ""
echo "Run 'task-flow' in Claude Code to start."
