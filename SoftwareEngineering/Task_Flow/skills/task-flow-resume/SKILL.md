---
name: task-flow-resume
description: Resume an ongoing task from where you left off. Use when user says "task-flow-resume" or "resume task". Asks for task folder path and continues from the last phase.
disable-model-invocation: true
---

# Task Flow Resume

Resume an ongoing task by providing the task folder path.

## Prerequisites

- `.claude/skill.config` must exist (run `task-flow-setup:init-skills` if missing)

## Workflow

**Trigger:** User says "task-flow-resume" or "resume task"

**Steps:**

1. Read `skill.config` for paths

2. **Ask for specific task folder path:**
   ```
   Give me the path to your task folder (e.g., {tasks_folder}/PROJ-195-my-task)
   ```

3. **Read task context:**

   Once user provides the path, read all available files:
   - `raw_prompt.md` (required - if missing, invalid task folder)
   - `prompt-understanding.md` (if exists)
   - `execution_plan.md` (if exists)
   - `execution-summary.md` (if exists - prioritize this for state)

4. **Determine current phase:**

   | Files Present | Phase | Next Action |
   |--------------|-------|-------------|
   | Only `raw_prompt.md` | 0 | Ask clarifying questions, create `prompt-understanding.md` |
   | + `prompt-understanding.md` | 1 | Create `execution_plan.md` |
   | + `execution_plan.md` | 2 | Check branch, start/continue coding |
   | + `ticket.md` + `pr-description.md` | 4 | Ask about commit or archive |

5. **Check git branch status:**
   ```bash
   git branch --show-current
   ```
   - If on feature branch matching task → Good, continue
   - If on main → May need to create/checkout branch

6. **Present resumption summary:**
   ```
   Resuming task: {task_name}

   Current state:
   - Phase: {phase}
   - Branch: {branch_status}
   - Last action: {from execution-summary.md if available}

   Next step: {what will happen next}

   Ready to continue? (yes/no)
   ```

7. **📤 Push docs on resume:** After user confirms, push any uncommitted changes in `coding_tasks_root`. Follow the full **Push-Docs Procedure** from `task-flow/SKILL.md`.

8. **Continue with task-flow phases:**

   Once user confirms, continue with the appropriate phase from task-flow:
   - Phase 1 → Create prompt-understanding.md
   - Phase 2 → Create execution_plan.md
   - Phase 3 → Code (follow task-flow Phase 3 rules)
   - Phase 4 → Finish (create ticket.md, pr-description.md, commit)

## Quick Commands

| Say | Action |
|-----|--------|
| "task-flow-resume" | Ask for task path and resume |
| "resume task" | Same as above |

## Relationship to task-flow

- **task-flow** = Start a NEW task (ticket-first or ticket-late)
- **task-flow-resume** = Continue an EXISTING task

Both skills share the same phase definitions (1-5) and follow the same rules for coding, commits, and archiving.

## References

See `.claude/skills/task-flow/SKILL.md` for:
- Phase definitions and detailed steps
- Safety rules for commits
- Coding conventions
- Documentation requirements
