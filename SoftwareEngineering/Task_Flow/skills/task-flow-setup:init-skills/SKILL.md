---
name: task-flow-setup:init-skills
description: Initialize skills configuration and directory structure for this project. Use when setting up for first time or when skill.config is missing. Say "task-flow-setup:init-skills" or "init skills".
disable-model-invocation: true
---

# Initialize Skills

Set up user-specific configuration and directory structure for Task Flow skills.

## When to Use

- First time using skills in this project
- `skill.config` is missing
- New developer joining project

## Directory Structure (Auto-Created)

```
{coding_tasks_root}/                   # User provides this
├── {Platform}/                        # Based on config_hints.json platform
│   ├── OnGoingTasks/
│   └── DoneTasks/
├── TasksSummary/
│   └── {Platform}.md
└── WeeklySummaries/
```

### Platform Types

- **Backend** → `Backend/`
- **Frontend** → `Frontend/`
- **iOS_Frontend** → `iOS_Frontend/`
- **Android_Frontend** → `Android_Frontend/`

### Path Derivation Rules

**Stored in skill.config:** `tasks_root`, `docs_root` (optional)

**Derived at runtime:**
- `coding_tasks_root` = `dirname(tasks_root)`
- `tasks_folder` = `{tasks_root}/OnGoingTasks`
- `done_folder` = `{tasks_root}/DoneTasks`
- `task_summary_folder` = `{coding_tasks_root}/TasksSummary`
- `weekly_summaries_folder` = `{coding_tasks_root}/WeeklySummaries`

## Steps

### 1. Check Prerequisites

```bash
cat .claude/skill.config 2>/dev/null || echo "CONFIG_MISSING"
```

If skill.config exists and is current → tell user and stop (unless they want to reconfigure).

Check `gh` CLI:
```bash
command -v gh >/dev/null 2>&1 && echo "GH_OK" || echo "GH_MISSING"
```

If missing, suggest installation. Continue either way.

### 2. Read Platform from Config

```bash
jq -r '.platform' .claude/config_hints.json 2>/dev/null
```

Map platform to directory name. If config_hints.json doesn't have platform or uses a custom value, ask user to select:

```
What platform are you working on?

1. Backend
2. Frontend Web
3. iOS Frontend
4. Android Frontend

Select (1-4):
```

### 3. Ask for Tasks Root Path

```
I need the path to your coding tasks directory.

This should be the parent folder that contains all platform folders.
Example: /path/to/{project_name}_Coding_Tasks

The platform folder "{platform}" will be created inside this directory.

Tip: Make this folder a Git repo to track task history and collaborate.

What is your coding tasks root path?
```

Construct: `tasks_root = "{user_path}/{platform}"`

### 4. Create Directory Structure

```bash
mkdir -p "$tasks_root/OnGoingTasks"
mkdir -p "$tasks_root/DoneTasks"
mkdir -p "$coding_tasks_root/TasksSummary"
mkdir -p "$coding_tasks_root/WeeklySummaries"
mkdir -p "$coding_tasks_root/CodeReviews"
```

Gitignore CodeReviews:
```bash
if ! grep -q "CodeReviews/" "$coding_tasks_root/.gitignore" 2>/dev/null; then
  echo "CodeReviews/" >> "$coding_tasks_root/.gitignore"
fi
```

Create platform summary file if missing:
```bash
summary_file="$coding_tasks_root/TasksSummary/{platform}.md"
if [ ! -f "$summary_file" ]; then
  echo "# {platform} Tasks Summary" > "$summary_file"
fi
```

### 5. Ask for Docs Path (Optional)

```
Do you have a separate documentation project?
If yes, provide the path. If no, just say "skip".

This is optional but recommended for engineering specs and templates.
```

### 6. Create skill.config

```json
{
  "paths": {
    "tasks_root": "{constructed_tasks_root}",
    "docs_root": "{user_docs_path_or_null}"
  }
}
```

### 7. Update .gitignore

```bash
grep -q "skill.config" .gitignore 2>/dev/null || echo ".claude/skill.config" >> .gitignore
```

### 8. Confirm

```
Skills initialized!

Configuration:
  Platform: {platform}
  Tasks Root: {coding_tasks_root}
    - Tasks: {tasks_root}/OnGoingTasks/
    - Done: {tasks_root}/DoneTasks/
    - Summary: TasksSummary/{platform}.md
    - Weekly: WeeklySummaries/
  Docs: {docs_root or "Not configured"}

Next steps:
  1. Run "task-flow" to begin a new task
```

## Reading Config (For Other Skills)

```bash
# Read user config
tasks_root=$(jq -r '.paths.tasks_root' .claude/skill.config)
docs_root=$(jq -r '.paths.docs_root' .claude/skill.config)

# Read project config
platform=$(jq -r '.platform' .claude/config_hints.json)

# Derive paths at runtime
coding_tasks_root=$(dirname "$tasks_root")
tasks_folder="$tasks_root/OnGoingTasks"
done_folder="$tasks_root/DoneTasks"
task_summary_folder="$coding_tasks_root/TasksSummary"
weekly_summaries_folder="$coding_tasks_root/WeeklySummaries"
```
