---
name: task-flow-review
description: Reviews code changes in task-flow workflow against coding rules. Integrates with task folders, tracks iterations. Use after code implementation. Say "task-flow-review" or "review".
disable-model-invocation: true
---

# Task Flow Review

Comprehensive code review that compares current branch changes with main branch and validates against all coding rules.

## When to Use

- **During task-flow**: After code implementation is complete and ready to commit/push
- **Before creating a pull request**: Final validation before PR
- **After completing a feature**: Verify code quality and standards compliance
- **Standalone review**: Analyze any branch changes against project patterns

## What It Does

1. **Detect Context** - Determines if running within task-flow or standalone
2. **Generate Diff** - Creates detailed diff comparing current branch with main
3. **Load Coding Rules** - Reads all coding standards files from the project's standards directory
4. **Analyze Changes** - Reviews code against architecture, conventions, and best practices
5. **Generate Report** - Saves review logs with findings
6. **Track Iterations** - Maintains review history with fix logs

## How to Use

### Within task-flow
```
# During Code phase of task-flow, after implementation:
> "task-flow-review"

# Reviews are saved to: {review_dir}/review-report.md
# Each review iteration is appended with timestamp
```

### Standalone
```
> "task-flow-review"

# Asks for task folder path OR saves to .claude/reviews/
```

## Review Output Location

All review files go to `reviews_root` from `.claude/skill.config` — fully **git-ignored**.

```
{reviews_root}/
└── feature-proj-372-batch-cancel-api/     ← Named by branch
    ├── review.diff                        ← Latest diff (overwritten each run)
    └── review-report.md                   ← Review iterations (appended)
```

Nothing is committed. The review is a local working artifact.

## Implementation

When this skill is invoked, follow these steps:

### 1. Detect Mode and Task Folder

```bash
# Read skill config
if [ ! -f ".claude/skill.config" ]; then
  MODE="standalone"
else
  tasks_root=$(jq -r '.paths.tasks_root' .claude/skill.config)
  tasks_folder="$tasks_root/OnGoingTasks"
  current_branch=$(git branch --show-current)
  ticket_prefix=$(echo "$current_branch" | grep -oE '[A-Z]+-[0-9]+' | head -1)

  if [ -n "$ticket_prefix" ]; then
    task_folder=$(find "$tasks_folder" -maxdepth 1 -type d -name "${ticket_prefix}*" | head -1)
    if [ -n "$task_folder" ]; then
      MODE="task-flow"
    else
      MODE="standalone"
    fi
  else
    MODE="standalone"
  fi
fi
```

### 2. Determine Review Output Path

```bash
reviews_root=$(jq -r '.paths.reviews_root // ""' .claude/skill.config 2>/dev/null)
if [ -z "$reviews_root" ]; then
  reviews_root=".claude/reviews"
fi

current_branch=$(git branch --show-current)
sanitized_branch=$(echo "$current_branch" | tr '/' '-')
review_dir="$reviews_root/$sanitized_branch"
mkdir -p "$review_dir"
```

### 3. Generate Diff

```bash
current_branch=$(git branch --show-current)
base_branch="main"
git diff "$base_branch"...HEAD > "$diff_file"
```

### 4. Load Coding Rules

```bash
standards_dir=$(jq -r '.standards_location // "docs/ai-rules"' .claude/config_hints.json 2>/dev/null)
coding_rules=$(find "$standards_dir" -name "*.md" -type f | sort)
```

### 5. Run Code Review Analysis

Use the code-reviewer agent to analyze changes against coding rules.

### 6. Save Review Report

Append new iterations to the review report file (git-ignored).

### 7. Display Summary

```
Code Review Complete!
======================================

Branch: {current_branch} vs {base_branch}
Review saved to: {review_dir} (git-ignored)

Verdict: {APPROVED / NEEDS WORK / BLOCKED}

Next Steps:
  1. Address ❌ issues (blocking)
  2. Consider ⚠️ warnings and 💡 suggestions
  3. Run 'task-flow-review' again after fixes to track progress
```

## Review Report Format

```markdown
## Review Iteration {N}
**Date**: {timestamp}
**Branch**: {current_branch}
**Files Changed**: {count}

### Changes Summary
[Brief overview of what changed]

### ✅ Passes
[Things done correctly with file:line references]

### ⚠️ Warnings
[Potential issues to review]

### ❌ Issues (Must Fix)
[Violations with file:line references and rule citations]

### 💡 Suggestions
[Improvements to consider]

### Verdict
[APPROVED / NEEDS WORK / BLOCKED]

### Next Steps
[Actionable items]
```

## Post-Review Fix Rules

When the user approves fixes suggested by the review:

1. Make the code changes
2. Run tests to verify
3. **Create a NEW commit** — never amend the previous one
4. **Push normally** — never force push
5. Optionally re-run `task-flow-review` to verify fixes

**CRITICAL:** Do not use `git commit --amend` or `git push --force-with-lease` for post-review changes.

## Tips

- **Run early, run often**: Don't wait until code is "perfect" - review as you go
- **Track progress**: Each review iteration shows what was fixed
- **Learn patterns**: Reviews teach you project conventions over time
- **Automate compliance**: Use before every PR to catch issues early
