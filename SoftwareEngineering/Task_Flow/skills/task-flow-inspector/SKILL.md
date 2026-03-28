---
name: task-flow-inspector
description: Audit OnGoingTasks for health issues — unarchived completions, missing TasksSummary entries, stale tasks, TBD tickets, missing phase files, and already-shipped PRs. Reports findings and offers fixes. Say "task-flow-inspector" or "inspect tasks" to run.
disable-model-invocation: true
---

# Task Flow Inspector

Scan → Check → Report → Fix → Push

## When to Run

- Periodic hygiene check on task workspace
- Before starting a new task (quick health scan)
- When you suspect tasks fell through the cracks
- Developer says "task-flow-inspector", "inspect tasks", or "audit tasks"

## Pre-Flight

**Read configuration and derive paths:**

```bash
if [ ! -f ".claude/skill.config" ]; then
  echo "❌ .claude/skill.config not found. Run 'task-flow-setup:init-skills' first."
  exit 1
fi

tasks_root=$(jq -r '.paths.tasks_root' .claude/skill.config)
platform=$(jq -r '.platform' .claude/config_hints.json)
project_namespace=$(jq -r '.project.namespace' .claude/config_hints.json)

coding_tasks_root=$(dirname "$tasks_root")
ongoing_folder="$tasks_root/OnGoingTasks"
done_folder="$tasks_root/DoneTasks"
task_summary_folder="$coding_tasks_root/TasksSummary"
summary_file="$task_summary_folder/${platform}.md"
```

## Step 1 — Discover

List all task folders in `OnGoingTasks/` and record folder name, files present, and last modified date.

## Step 2 — Analyze

Run 7 checks on each task folder:

### Check 1: Phase Detection
Determine current phase by file existence (same logic as task-flow-resume).

### Check 2: Not Archived
**Condition:** Phase = 4 (has both `ticket.md` and `pr-description.md`) but still in `OnGoingTasks/`.
**Severity:** WARNING

### Check 3: TasksSummary Gaps
- Missing row in TasksSummary
- Missing completion date
- Broken WeeklySummary links

### Check 4: Missing Phase Files
For a task at phase N, earlier phase files should exist.

### Check 5: TBD Ticket
Folder name starts with `TBD-` — ticket should have been assigned by Phase 4.

### Check 6: Stale Task
No file in the task folder modified in the last 7 days.

### Check 7: Already Shipped
Task is Phase 0-3 AND 7+ days stale — check if PR was already merged on GitHub.

## Step 3 — Report

```markdown
# Task Flow Inspector Report

**Scanned:** {n} tasks in OnGoingTasks/
**Issues:** {n} total — {n} WARNING, {n} INFO
**Clean:** {n} tasks with no issues

## Task Status

| # | Task | Phase | Issues |
|---|------|-------|--------|
| 1 | PROJ-195-simplify-api | 4 (Complete) | NOT_ARCHIVED, COMPLETION_DATE |
| 2 | TBD-add-endpoint | 2/3 (Coding) | TBD_TICKET |
| 3 | PROJ-200-fix-auth | 1 (Understood) | STALE (12d) |
```

## Step 4 — Offer Fixes

Present fixable issues grouped by type. **Require explicit approval before any changes.**

### Auto-Fixable
- Archive completed tasks → Move to DoneTasks/
- Fill completion dates in TasksSummary

### Manual Action Required
- Obtain ticket numbers for TBD tasks
- Resume or archive stale tasks

## Step 5 — Apply Fixes

Execute each approved fix, then push docs and verify results.
