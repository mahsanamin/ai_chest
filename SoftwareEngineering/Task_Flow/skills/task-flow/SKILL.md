---
name: task-flow
description: Structured development workflow from raw prompt to PR. Use when user says "task-flow" or provides a task folder path. Follows Raw Prompt → Understand → Plan → Code → Document flow.
disable-model-invocation: true
---

# Task Flow

Structured workflow: Raw Prompt → Understand → Plan → Code → Document

## 🔧 Configuration

**IMPORTANT:** This skill uses project-specific configuration from `.claude/config_hints.json`.

At the start of this workflow, read the configuration:

```bash
# Read project configuration
project_namespace=$(jq -r '.project.namespace' .claude/config_hints.json)
project_name=$(jq -r '.project.name' .claude/config_hints.json)
platform=$(jq -r '.platform' .claude/config_hints.json)
standards_location=$(jq -r '.standards_location' .claude/config_hints.json)

# Read tracker configuration
tracker_type=$(jq -r '.tracker.type // "none"' .claude/config_hints.json)
tracker_url=$(jq -r '.tracker.url // ""' .claude/config_hints.json)
```

**Use these variables throughout the workflow:**
- Ticket format: `{project_namespace}-XXX` (e.g., "PROJ-195", "AUTH-42")
- Branch format: `feature/{lowercase(project_namespace)}-XXX-description`
- Tracker: `{tracker_type}` at `{tracker_url}` (if applicable)
- Task folders: `{project_name}_Coding_Tasks/{platform}/`
- Coding standards: `{standards_location}` (e.g., "docs/ai-rules", "docs/coding-standards", ".aiRules")

**Example for a project:**
- Tickets: PROJ-XXX
- Branches: feature/proj-42-add-auth
- Tracker: jira at your-org.atlassian.net

## 📤 Docs Auto-Push

The docs/tasks directory (`coding_tasks_root`) is a **separate git repo** from the project repo. Task files created there (raw_prompt.md, prompt-understanding.md, execution_plan.md, ticket.md, etc.) must be pushed to avoid losing work.

**Claude automatically pushes at key checkpoints — no need to ask the user.**

### Push-Docs Procedure

Run this at each checkpoint (marked 📤 in the phases below):

```bash
# Step 1: Commit local changes (if any)
cd "$coding_tasks_root"

if git status --porcelain | grep -q .; then
  git add -A
  git commit -m "task-flow: {context_message}"
fi

# Step 2: Pull with rebase to sync remote changes
if ! git pull --rebase 2>/dev/null; then
  # Conflicts detected — resolve intelligently (see below)
  resolve_docs_conflicts
fi

# Step 3: Push
if git push; then
  echo "✓ Docs saved: {context_message}"
else
  echo "⚠️ Docs push failed — push $coding_tasks_root manually"
fi

cd -  # return to project repo
```

### Merge Conflict Resolution

When `git pull --rebase` produces conflicts:

1. List conflicted files: `git diff --name-only --diff-filter=U`
2. Resolve by file type:
   - **`TasksSummary/*.md`** — Keep all unique rows from both sides (dedup by Task column). This is the most common conflict since multiple devs add rows to the same weekly section.
   - **`WeeklySummaries/**/*.md`** — Keep whichever side has more content (`git checkout --ours` or `--theirs`). If both have unique content, manually merge.
   - **Task folder files** — Keep ours: `git checkout --ours {file} && git add {file}`
3. Complete: `git rebase --continue` (repeat if more rounds)
4. Push: `git push`

### Context Messages by Checkpoint

- Phase 0: `"create {task_name}"` — after task folder + raw_prompt.md ready
- Phase 1: `"understand {task_name}"` — after prompt-understanding.md approved
- Phase 2: `"plan {task_name}"` — after execution_plan.md approved + task logged
- Phase 4: `"complete {task_name}"` — after ticket.md, pr-description.md, task log updated
- Phase 5: `"archive {task_name}"` — after task moved to DoneTasks

### Rules

- Do it silently — never ask user, just show a one-line status
- Resolve conflicts autonomously using the strategies above — don't ask user unless content is ambiguous
- If push still fails after conflict resolution, warn but never block the workflow
- If no local changes and no remote changes (`git status` + `git pull` both clean), skip silently

## 🤖 Agents Integration

**This skill uses a hybrid approach:**

**Phases 1-3: Main Session (You)**
- Phase 1: Understand requirements (interactive)
- Phase 2: Create execution plan (builds on understanding)
- Phase 3: Write code (complex, needs context)

**Why:** Natural conversation flow, full context, can ask clarifying questions

**Phase 3-4: Parallel Agents** (Optional)

| Agent | Model | Purpose | When |
|-------|-------|---------|------|
| test-runner | Haiku | Run tests in background | While you continue coding |
| code-reviewer | Sonnet | Review code in parallel | While you write docs |
| doc-writer | Haiku | Generate docs (optional) | If you want to parallelize |
| commit-writer | Haiku | Write commit message | Phase 4j before commit |
| pr-writer | Haiku | Write PR title + body | After commit, when creating PR |

**Agent configurations:** See `.claude/agents/README.md` for details

**Default:** You work in main session. Agents are optional for parallelization.

## 🔗 Tracker Integration

The issue tracker is configured via `tracker.type` in `config_hints.json`. Supported values: `jira`, `github`, `linear`, `tiles`, `none`.

### Tracker Dispatch Table

| Moment | jira | github | linear | tiles | none |
|--------|------|--------|--------|-------|------|
| **Check configured** | `claude mcp list \| grep atlassian` | `gh auth status` | Check Linear MCP | Check Tiles MCP/API | Skip |
| **Fetch ticket** | `mcp__atlassian__getJiraIssue` | `gh issue view {n} --json title,body,labels` | Linear MCP/API | Tiles API/MCP | N/A (ticket-late only) |
| **Ticket link format** | `https://{tracker_url}/browse/{namespace}-XXX` | `#{number}` (auto-links on GitHub) | `https://linear.app/issue/{id}` | `{tracker_url}/tile/{id}` | `{namespace}-XXX` (no URL) |
| **Update on completion** | Archive desc to comment, update with ticket.md content | `gh issue comment {n}`, optionally close | Update status via API | Update tile via API | Skip |
| **Create ticket** | Ask for Epic, use `mcp__atlassian__createJiraIssue` | `gh issue create` | Linear MCP/API | Tiles API/MCP | Ask user for manual identifier |
| **MCP setup** | `claude mcp add --scope user --transport http atlassian https://mcp.atlassian.com/v1/mcp` | N/A (uses `gh` CLI) | Configure Linear MCP | Configure Tiles MCP | N/A |

When instructions below say "fetch ticket", "update tracker", or "create ticket" — use the row matching your `tracker_type` from this table.

### Tracker-Specific Templates

**raw_prompt.md header (ticket-first):**
```markdown
# {Ticket Title}

**{Tracker Label}:** {Ticket Link}
**Type:** {Issue Type}

## Description
{Ticket Description}

---
*Fetched from {tracker_type} on {date}*
```

Where `{Tracker Label}` is: Jira Ticket / GitHub Issue / Linear Issue / Tiles Tile

**ticket.md link line:**
- jira: `**Jira:** https://{tracker_url}/browse/{namespace}-XXX`
- github: `**GitHub Issue:** #{number}`
- linear: `**Linear:** https://linear.app/issue/{id}`
- tiles: `**Tiles:** {tracker_url}/tile/{id}`
- none: `**Ticket:** {namespace}-XXX`

## 🚨 CRITICAL SAFETY RULES - ALWAYS ENFORCE

### Rule 1: Detect Workflow Violations When User Asks to Commit

**The task-flow workflow is:**
1. User starts on main branch (task-flow pulls from main)
2. Create `execution_plan.md` with branch name
3. Create feature branch from main (after execution plan exists)
4. Code on feature branch
5. Commit on feature branch

**When user asks to "commit", "verify and commit", or similar:**

**STEP 1: Check current branch**
```bash
git branch --show-current
```

**STEP 2: If output is "main" → WORKFLOW VIOLATION DETECTED**

This means the user has skipped steps 2-3 above (no execution_plan.md OR didn't create branch).

**IMMEDIATELY STOP and ask:**
```
🚨 STOP: You're on the main branch!

The task-flow workflow requires:
1. Creating execution_plan.md first
2. Creating a feature branch from that plan
3. Then committing on the feature branch

I see you're trying to commit directly to main, which skips this workflow.

Would you like me to help you follow the proper task-flow process?
- Yes → I'll guide you through creating execution_plan.md and feature branch
- No → Please explain your situation and I can suggest alternatives
```

**STEP 3: If output is a feature branch → Safe to proceed**

### Rule 2: Always Ask, Never Assume

When you detect potentially unsafe situations (on main, no execution_plan.md, etc.), **STOP and ASK** instead of assuming what the user wants. Never commit to main without explicit user override.

### Rule 4: Never Fabricate — Extract or Ask

**Every concrete detail in prompt-understanding.md and execution_plan.md must come from code you actually read or from the user — never from inference, memory, or pattern-matching.**

This applies to: URLs, endpoint paths, class names, method names, table names, column names, config keys, enum values, error codes, request/response field names.

**How this fails in practice:**
- You read method bodies but skip the class-level annotation that defines the actual path or name
- You see a similar-looking value in an unrelated file and assume the target shares the same format
- You assume conventional casing or separators instead of checking

**The rule:**
1. If you need a specific value, **read the exact line of code** where it's defined
2. If you haven't read it, **go read it** before writing it into any document
3. If you can't find it in code, **ask the user** — don't guess
4. After writing a document, **spot-check concrete details** against the code you read

**Red flags that you're about to fabricate:**
- Writing a value without being able to point to the file and line number where you read it
- Combining fragments from different files into a composite value that may not exist
- Using a "typical" or "conventional" format instead of the actual one
- Filling in a detail from memory or pattern-matching rather than from a tool result in this session

## Prerequisites

- `.claude/skill.config` must exist (run `task-flow-setup:init-skills` if missing)
- `.claude/config_hints.json` must exist (run `task-flow-setup:initialize` from the framework repo if missing)
- **Ticket-First Approach:** Tracker configured in `config_hints.json` (see Tracker Integration section)
- **Ticket-Late Approach:** User creates task folder under `{tasks_folder}/` with `raw_prompt.md`

## 🚨 CRITICAL: Always Apply Critical Thinking

**Throughout ALL phases of task-flow, follow `{standards_location}/critical-thinking.md`:**

- **Question ambiguous instructions** - "Don't worry about X" could mean many things - ASK what they mean
- **Challenge architectural violations** - Don't put code in wrong modules or break patterns
- **Verify against codebase** - Check if requested changes make sense with existing structure
- **Suggest alternatives** - Propose better approaches when you spot issues

**The cost of asking is 30 seconds. The cost of misunderstanding is hours of rework.**

## MCP Integration Reference

**When `tracker_type` uses MCP (jira, linear, tiles):** Refer to `{standards_location}/mcp-integration.md` for exact tool names, parameters, and error handling patterns.

## Workflow Overview

```
         task-flow
         ↓
    Choose Approach: Ticket-First OR Ticket-Late
         ↓                           ↓
    [Ticket-First Path]         [Ticket-Late Path]
    Check tracker configured    Ask for task folder path
         ↓                           ↓
    Ask for ticket ID/URL       Read raw_prompt.md
         ↓                           ↓
    Fetch ticket via tracker    Ask clarifying questions
         ↓                           ↓
    Create raw_prompt.md    Create prompt-understanding.md
         ↓                           ↓
         └──────────────────────────┘
                     ↓
    User reviews prompt-understanding ← CHECKPOINT
         ↓
    Create execution_plan.md + decide branch name
         ↓
    User reviews plan
         ↓
    Checkout branch + start coding
         ↓
    Write/Update tests for changed code
         ↓
    Run tests + ensure all pass
         ↓
    Keep execution_plan.md updated
         ↓
    Finish → commit? → ticket.md → pr-description.md
         ↓
    [If Ticket-First] Update tracker (see Tracker Integration section)
         ↓
    Archive → move to {done_folder} (read from skill.config, never hardcode)
```

## Phase 0: Choose Approach

**Trigger:** User says "task-flow"

**Steps:**

1. **Read configuration and derive paths**

   ```bash
   # Read user config (absolute paths)
   tasks_root=$(jq -r '.paths.tasks_root' .claude/skill.config)
   docs_root=$(jq -r '.paths.docs_root' .claude/skill.config)

   # Read project hints (platform)
   platform=$(jq -r '.platform' .claude/config_hints.json)

   # Derive all paths at runtime
   coding_tasks_root=$(dirname "$tasks_root")
   tasks_folder="$tasks_root/OnGoingTasks"
   done_folder="$tasks_root/DoneTasks"
   task_summary_folder="$coding_tasks_root/TasksSummary"
   weekly_summaries_folder="$coding_tasks_root/WeeklySummaries"
   ```

2. **Validate and create directories**

   Check that required files exist:
   - `.claude/skill.config` must exist
   - `.claude/config_hints.json` must exist

   **Auto-create directories if missing:**
   ```bash
   mkdir -p "$tasks_folder"
   mkdir -p "$done_folder"
   mkdir -p "$task_summary_folder"
   mkdir -p "$weekly_summaries_folder"
   ```

   **If required files are missing:**
   ```
   ⚠️ Missing required configuration.

   Run "task-flow-setup:init-skills" to configure paths, or "task-flow-setup:initialize" from the framework repo for full setup.
   ```

3. **Ask user to choose workflow approach:**

   **If `tracker_type` is `none`:** Skip option 1 and go directly to ticket-late.

   **Otherwise:**
   ```
   How would you like to start this task?

   1. **Ticket-First Approach** - Start from an existing ticket/issue
      - I'll fetch the ticket description and create raw_prompt.md for you
      - Best when you already have a ticket with details

   2. **Ticket-Late Approach** - Start from a task folder you've already created
      - You've already created raw_prompt.md manually
      - Best for quick tasks or when ticket doesn't exist yet

   Which approach? (1 or 2)
   ```

### Path 1: Ticket-First Approach

If user chooses ticket-first:

**Check Tracker Configured:**
Use the "Check configured" row from the Tracker Dispatch Table. If not configured, show the setup command from the "MCP setup" row and offer to switch to ticket-late.

**Fetch Ticket:**
1. Ask: "What's the ticket URL or ID (e.g., {project_namespace}-XXX)?"
2. Use the "Fetch ticket" method from the Tracker Dispatch Table
3. Automatically create task folder: `{tasks_folder}/{TicketID}-{sanitized-title}/`
4. Inform user: "Created task folder at {tasks_folder}/{TicketID}-{sanitized-title}/"
5. Create `raw_prompt.md` using the tracker-specific template from the Tracker Integration section
6. **📤 Push docs checkpoint:** Run push-docs procedure with `"create {task_name}"`.
7. Proceed to Phase 1

### Path 2: Ticket-Late Approach

If user chooses ticket-late:

**Steps:**
1. Ask user: "Give me the path to your task folder"
2. Verify `raw_prompt.md` exists in that folder
3. Read `raw_prompt.md`
4. **📤 Push docs checkpoint:** Run push-docs procedure with `"create {task_name}"`.
5. Proceed to Phase 1

## Phase 1: Prompt Understanding

**After reading raw_prompt.md:**

### Step 1a: Raw Prompt Quality Check

Before doing anything else, read `raw_prompt.md` and assess whether you can clearly understand what needs to be done.

**First, identify the task type:**

**Tech debt task** (refactor, remove, rename, migrate, clean up, deprecate, fix a bug):
- Technical references are expected and fine — class names, column names, table names, file paths
- The bar is simply: is the intent clear?
- Short and terse is fine. It doesn't need to explain *why* — tech debt is self-evidently technical

**Feature / product task** (new functionality, changed behaviour, user-facing work):
- Should be readable without knowing the codebase
- The *what* and *why* should be clear — what problem is being solved, what the outcome is
- Technical class names and file paths are noise here; business context matters more

**Regardless of type — the prompt fails if:**
- The intent is genuinely unclear or ambiguous (you can't tell what needs to change)
- It's a wall of implementation details with no clear goal
- It mixes multiple unrelated tasks without indicating priority

**If the prompt fails:**

1. Tell the engineer specifically what's unclear — quote the confusing parts:
   ```
   Your raw_prompt is hard to follow in a few spots.

   For example:
   - [quote the specific unclear parts]

   I'll rewrite it to make the intent clearer while keeping all your information.
   Here's what I'm planning to change:
   - [brief list of changes]

   OK to rewrite?
   ```

2. On confirmation:
   - Preserve ALL intent — don't drop any requirement or context
   - For tech debt: keep technical references, just make the goal sentence clear
   - For features: translate class/method names to what they *do*, surface the business problem
   - **Overwrite `raw_prompt.md`** with the improved version

3. If the prompt is clear — proceed silently, no comment needed.

**Phase 1 Steps (main session):**

**Output:**
- prompt-understanding.md (refined requirements)
- execution-summary.md (initial state)

**Steps:**
1. Reads and analyzes raw_prompt.md
2. Reads relevant code to verify claims and understand current state
3. **Asks clarifying questions directly in chat (MANDATORY — do NOT skip)**
   - After reading the code, surface any questions, ambiguities, or assumptions
   - Even if the prompt seems perfectly clear, confirm with the user before proceeding
   - If you genuinely have zero questions, explicitly say: "I've read the code and raw prompt — no clarifying questions. Proceeding to create prompt-understanding.md."
   - **Never silently skip this step.**
4. Identifies applicable coding rules (see "Rule Detection" section)
5. **Verify all concrete details before writing (Rule 4: Never Fabricate)**
6. Creates prompt-understanding.md with:
   - Cleaner, refined version of requirements
   - Same size as original, just easier to understand
   - Product-level focus (no code noise)
   - `## Applicable Rules` section
7. **Self-reviews prompt-understanding.md (Rule 4 check):**
   - Re-read what you just wrote
   - For every concrete detail, ask: "Can I point to the exact file and line where I read this?"
   - If yes — keep it. If no — go read the source now, then fix or remove the detail
8. Creates execution-summary.md for session recovery

**Checkpoint:** Ask user:
```
prompt-understanding.md is ready.

Does this capture your requirements correctly?
- Yes → Proceed to Phase 2
- No → What needs adjustment?
```

**Important:** If the prompt was *not* rewritten in Step 1a, keep `raw_prompt.md` unchanged. All refinements go to `prompt-understanding.md`.

**Trigger for Phase 2:** User says "looks good", "approved", "correct", or similar confirmation.

**📤 Push docs checkpoint:** After user approves, run push-docs procedure with `"understand {task_name}"`.

## Phase 2: Plan

**After user approves prompt-understanding.md:**

**Phase 2 Steps (main session):**

**Output:**
- execution_plan.md (complete implementation plan)
- execution-summary.md (updated)

**Steps:**
1. Reads prompt-understanding.md
2. Explores codebase to understand structure
3. Reads applicable coding rules
4. Designs implementation approach
5. Creates execution_plan.md with:
   - Summary
   - Approach and trade-offs
   - Files to change (implementation + tests + docs)
   - Test plan
   - Database schema details (full SQL if applicable)
   - **Documentation updates** (REQUIRED section)
   - Acceptance criteria
   - Branch name: `feature/{namespace}-XXX-description`
   - **NO time estimates**

7. **Run plan-verifier agent (foreground — MANDATORY before showing plan to user):**

   **🤖 INVOKE AGENT: plan-verifier (Sonnet)**

   The plan-verifier cross-checks every concrete claim in execution_plan.md against the actual source code.

   1. Read `.claude/agents/plan-verifier/AGENT.md` for agent instructions
   2. Pass to agent: execution_plan.md, prompt-understanding.md, project root, config_hints.json
   3. Review agent output:
      - **VERIFIED** → proceed to checkpoint
      - **ISSUES FOUND** → fix each issue in execution_plan.md, then re-run verification
   4. Do NOT present the plan to the user until verification passes

   **Manual Override:** If user says "skip verification", proceed directly to checkpoint.

**Checkpoint:** After plan-verifier passes, ask user:
```
execution_plan.md is ready (verified against codebase).

Review the plan. Approve this implementation approach?
- Yes → Proceed to Phase 3
- No → What needs adjustment?
```

**Post-Approval Steps:**

1. **Log Task Started:**
   - Follow "Task History Logging" section
   - Add entry to `{coding_tasks_root}/TasksSummary/Backend.md` or `Frontend.md`
   - Mark Completed as `-` (will be filled in Phase 4)

2. **Update execution-summary.md:**
   ```markdown
   ## Current State
   - **Phase:** 2 (Plan) → Ready for Phase 3
   - **Branch:** feature/{namespace}-{name}
   - **Last Action:** Plan approved

   ## Q&A Log
   - (carry forward from Phase 1, add new)

   ## Next Steps
   - Create branch and start coding
   ```

3. **📤 Push docs checkpoint:** Run push-docs procedure with `"plan {task_name}"`.

**Manual Override:** If user says "skip agent", perform steps directly without the agent.

## Phase 3: Code

**Trigger:** User says "start coding", "approved", or "looks good"

**Prerequisites:**
- User has approved `execution_plan.md` from Phase 2
- execution_plan.md includes a branch name

**Steps:**

1. **Pull latest changes from main:**
   ```bash
   git pull origin main
   ```

2. **Verify we're still on main before creating branch:**
   ```bash
   git branch --show-current
   ```
   - Expected output: "main"
   - If already on a feature branch → User may have created it manually (safe to proceed)

3. **Create feature branch from main:**
   ```bash
   git checkout -b feature/{namespace}-<branch-name>
   ```
   Use the branch name from execution_plan.md header.

4. **Add execution tracking to `execution_plan.md` header:**
   ```markdown
   ## Execution Tracking
   - **Started:** {today's date, YYYY-MM-DD}
   - **Developer:** developer@example.com
   - **Branch:** feature/{namespace}-XXX-description
   - **Collaborators:** (none yet)
   ```

5. **Create/Update `execution-summary.md`** (for session recovery):
   ```markdown
   ## Pull Request
   - *PR not yet created*

   ## Current State
   - **Phase:** 3 (Code)
   - **Branch:** feature/{namespace}-XXX-description
   - **Last Action:** {what you just did}

   ## Q&A Log
   - Q: {question asked} → A: {user's answer}

   ## Next Steps
   - {what comes next}
   ```
   Keep this file small. Log important Q&A as you go.

6. **Write code** following `{standards_location}/` conventions:

   **Always-apply rules (every task):**
   - `coding-conventions.md` - Formatting, naming, style
   - `project-structure.md` - Correct module placement
   - `critical-thinking.md` - Challenge assumptions, verify against codebase

   **Task-specific rules (from prompt-understanding.md):**
   - Read the `## Applicable Rules` section in `prompt-understanding.md`
   - **Read each listed .md file** before writing code that falls under its scope

   **Key rule:** Apply Rule 4 (Never Fabricate)

7. **Update Documentation (CHECK execution_plan.md):**

   **IMPORTANT:** Check the "Documentation updates" section in your execution_plan.md.
   If docs were listed, update them NOW before proceeding to tests.

   - **API changes** → Update API specification docs
   - **Database changes** → Update ERD/schema docs

   **Triggers requiring doc updates:**
   - New/changed API endpoints or request/response formats → API Specs
   - New/changed DB tables, columns, or constraints → ERD
   - Changed validation rules or business logic → Both if applicable

8. **Testing Requirements (MANDATORY):**

   **All code changes MUST have corresponding test coverage:**

   a. **Find existing tests for modified code:**
      - Look for test files in the same module under `src/test/` (or equivalent for your framework)

   b. **Update existing tests if they exist:**
      - Add test cases for new functionality
      - Ensure existing tests still pass with your changes

   c. **Create new tests if none exist:**
      - Follow existing project test patterns and style
      - Use same testing frameworks as the project
      - Reference similar test classes for structure and mock setup

   d. **What to test:**
      - Happy path (successful execution)
      - Edge cases (null values, empty collections)
      - Error conditions (validation failures, exceptions)
      - Backward compatibility (if applicable)

   e. **Run tests after implementation:**
      ```bash
      # Use the project's test command — examples:
      ./gradlew test --rerun-tasks     # Gradle
      mvn test                          # Maven
      npm test                          # Node.js
      pytest                            # Python
      cargo test                        # Rust
      ```

   f. **If tests fail:** Fix the issue before proceeding. Never commit with failing tests.

9. **Keep files updated as things change (CRITICAL):**

    **After every significant action, update `execution-summary.md`:**
    ```markdown
    ## Current State
    - **Phase:** 3 (Code)
    - **Last Action:** {what you just did}
    - **Next:** {what comes next}
    ```

    **When scope/approach changes, update `execution_plan.md`:**
    - Mark completed items with ✅
    - Add newly discovered files to the list
    - Update approach if it changed
    - Add to Change Log section

    **When user clarifies requirements, update `prompt-understanding.md`**

10. **If someone else joins the task**, add them as collaborator:
    ```markdown
    - **Collaborators:** other@example.com (joined {date})
    ```

11. **If prompt/requirements change**, add to change log at bottom of `execution_plan.md`:
    ```markdown
    ## Change Log
    | Date | Time | Person | Change |
    |------|------|--------|--------|
    | {date} | {time} | dev@example.com | Updated scope to include X |
    ```

## Phase 4: Finish

**Trigger:** User says "done", "finished", "continue", or code is complete

**IMPORTANT:** Always create documentation files FIRST, then ask about commit.

**Steps:**

### 4a. Check Rule Checklists (FIRST)

**If your changes involve:**
- Database migration → Check `{standards_location}/database-migrations.md` checklist
- API endpoints → Check `{standards_location}/api-conventions.md` checklist

**If checklist exists, verify all items before proceeding.**

### 4b-4c. Create Documentation

**🤖 INVOKE AGENT: doc-writer**

**Agent Input:**
- Task folder path
- execution_plan.md
- prompt-understanding.md
- Git diff
- PR template (optional)

**Agent Output:**
- ticket.md (product description for tracker)
- pr-description.md (PR description for GitHub)

**What the agent creates:**

**ticket.md:**
```markdown
# [{project_namespace}-XXX] Task Title
**Tracker:** {tracker_link} ← Use format from Tracker Integration section

## Problem
(user perspective)

## Solution
(what changes)

## Benefits
(why this matters)

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2
```

- Product-level language only
- Allowed: JSON examples, API formats, table names
- NOT allowed: Class names, file paths, code snippets

**pr-description.md:**
- Reads PR template using lookup order: `PULL_REQUEST_TEMPLATE.md` → `.github/` → `docs/templates/pr-template.md`
- Follows template structure exactly
- Includes: Context, Approach, Testing, Checklist
- Uses [{project_namespace}-XXX] format

**Manual Override:** If user says "skip agent", perform steps directly without the agent.

### 4d. Verify Documentation Updates (MANDATORY)

**Before proceeding, check `execution_plan.md` for documentation updates:**

1. Read the "Documentation updates" section from execution_plan.md
2. If docs were listed → Verify they were actually updated
3. If docs were NOT updated but should have been → Update them now

**Common triggers for doc updates:**
- New/changed endpoints
- Changed request/response formats
- New/changed DB tables or columns
- Changed validation rules

**ERD Update Check:**
If `docs/erd.md` exists AND changes include database migrations or entity modifications:
```
Database changes detected. docs/erd.md may be out of date.

Update ERD now?
- Yes → I'll read the new migrations/entities and update the diagram
- No → Skip (remember to update later)
```

### 4e. Update Tracker Ticket (If Ticket-First Approach)

**Only if task started with ticket-first approach and `tracker_type` is not `none`:**

1. **Check if this was a ticket-first task:**
   - Read `raw_prompt.md`
   - Look for a tracker link header (e.g., `**Jira Ticket:**`, `**GitHub Issue:**`, etc.)
   - If not found → Skip this step

2. **If found, update the tracker using the "Update on completion" method from the Tracker Dispatch Table.**

3. **Error Handling:**
   - If tracker update fails → Warn user but continue workflow
   - Never block the workflow due to tracker update failures

### 4f. Log Task Completed

After verifying documentation:
1. Find the task entry in `{coding_tasks_root}/TasksSummary/Backend.md` or `Frontend.md`
2. Update the Completed column with today's date
3. **📤 Push docs checkpoint:** Run push-docs procedure with `"complete {task_name}"`.

### 4g. Run Full Test Suite (MANDATORY)

**🤖 INVOKE AGENT: test-runner**

**Agent Input:**
- Test command (project-specific)
- Project root

**Agent Output:**
- Test results (PASS/FAIL)
- Failure details (if any)

**Important:**
- If tests fail → STOP, fix the issues first
- If tests pass → Proceed to code review
- Never commit with failing tests

**Manual Override:** If user says "skip agent", perform steps directly without the agent.

### 4h. Code Review (BEFORE COMMIT)

**🤖 INVOKE AGENT: code-reviewer**

**Agent Input:**
- Task folder path
- Project root
- Git diff (staged changes)
- execution_plan.md

**Agent Output:**
- Review report
- Status: APPROVED / CHANGES REQUIRED

**Checkpoint:** After agent completes:
```
Code review complete. See review report.

Status: {APPROVED / CHANGES REQUIRED}

{If CHANGES REQUIRED}
Issues found:
1. {issue description}

Fix these issues before committing?

{If APPROVED}
Approve to commit?
```

**Manual Override:** If user says "skip agent", perform steps directly without the agent.

### 4i. Get Ticket Number and Update Everything

After code review approval:

1. **Ask if ticket exists:**
   ```
   Do you have a ticket/issue number for this task yet?

   1. Yes — I have a ticket number
   2. No, create it for me — I'll create it via {tracker_type}
   3. No, I'll create it myself — I'll give you the number/link
   ```

   Use the "Create ticket" method from the Tracker Dispatch Table if user picks option 2.
   If `tracker_type` is `none`, ask for a manual identifier for the branch name.

**🚨 IMMEDIATELY after receiving ticket number, do ALL of these:**

2. **Rename branch to include ticket number:**

   **Step 2a: Detect worktree**
   ```bash
   is_worktree=false
   if git rev-parse --git-dir 2>/dev/null | grep -q "worktrees"; then
     is_worktree=true
   fi

   current_branch=$(git branch --show-current)
   namespace_lower=$(echo "$project_namespace" | tr '[:upper:]' '[:lower:]')
   target_branch="feature/${namespace_lower}-<ticket>-<short-description>"
   ```

   **Step 2b: Rename or set remote branch name**

   **If NOT in a worktree** → Rename the local branch:
   ```bash
   git branch -m "$current_branch" "$target_branch"
   ```

   **If IN a worktree** → Keep local branch name, track a differently-named remote branch:
   ```bash
   remote_branch_name="$target_branch"
   ```
   When pushing later, use a refspec:
   ```bash
   git push -u origin "$current_branch:$remote_branch_name"
   ```

3. **Update ticket.md header** with ticket number and tracker link
4. **Update pr-description.md header** with ticket number
5. **Update TasksSummary and WeeklySummary** (if ticket-late approach — replace TBD with ticket number)
6. **Ask about commit**

### 4j. Commit (DO NOT PUSH)

**CRITICAL:** Run Rule 1 branch check before committing. If on main → STOP. If on feature branch → proceed.

**Commit Flow:**

**INVOKE AGENT: commit-writer (Haiku)**

1. Read `.claude/agents/commit-writer/AGENT.md` for agent instructions
2. Gather context: execution_plan.md, prompt-understanding.md, git diff, git log
3. Agent returns the commit message (must include `Co-Authored-By: Claude <noreply@anthropic.com>` trailer)
4. Show user the proposed commit message and staged files
5. On approval, commit

### Post-Review Fix Commits

When making changes after a review:

- **ALWAYS create a NEW commit** for post-review fixes
- **NEVER amend the previous commit and force push**
- Use a descriptive message like: `[{namespace}-XXX] Address review feedback: add docs and inline comments`
- Then push normally: `git push` (no `--force-with-lease`, no `--force`)

**IMPORTANT:** Do NOT push or create PR automatically. After commit, ask user what they want next (Create PR / Push only / Done for now). Wait for explicit approval at every step.

### 4k. Create PR (Optional)

**If user chooses to create PR:**

**INVOKE AGENT: pr-writer (Haiku)**

1. Read `.claude/agents/pr-writer/AGENT.md` for agent instructions
2. Gather context: pr-description.md, git log, git diff stats, PR template, config
3. Agent returns: title + `---` + body
4. Show user the proposed PR title and body
5. **Ask for PR type (default: Draft)**
6. On explicit approval: push + create PR with `gh pr create`
7. Return PR URL to user
8. **Log PR in `execution-summary.md`**

**Manual Override:** If user says "skip agent", perform steps directly without the agent.

## Phase 5: Archive

**Trigger:** User says "archive task", "move to done", or after PR is merged

**🚨 CRITICAL: Read Configuration First**

Before archiving, you MUST:
1. Read `.claude/skill.config` to get the actual paths
2. Use the EXACT folder paths from config - NEVER hardcode or guess folder names

**Steps:**

1. **Read skill.config and extract paths**
2. Run all tests to verify nothing is broken
3. If tests fail → STOP, fix issues first
4. If tests pass → Ask user: "All tests passing. Move to done folder?"
5. If yes, move the task folder
6. **📤 Push docs checkpoint:** Run push-docs procedure with `"archive {task_name}"`.
7. Confirm: "Task archived."

## Files Created in Task Folder

| File | Who Creates | When | Purpose |
|------|-------------|------|---------|
| `raw_prompt.md` | User or Claude | Phase 0 | Original task description |
| `prompt-understanding.md` | Claude | Phase 1 | Refined, cleaner version of requirements |
| `execution-summary.md` | Claude | Phase 1+ | Session recovery hints (kept small, updated each phase) |
| `execution_plan.md` | Claude | Phase 2 | Implementation plan with branch name |
| `ticket.md` | Claude | Phase 4 | Product-level description for tracker |
| `pr-description.md` | Claude | Phase 4 | PR description for GitHub |

## Tracker Ticket Update (Ticket-First Approach)

When you start a task using the **ticket-first approach**, the tracker ticket gets automatically updated when the task is completed. See Phase 4e and the Tracker Dispatch Table for implementation details per tracker type.

**If tracker is unavailable** → Warning shown, workflow continues. Never block on tracker failures.

## Branch Naming

Format: `feature/{lowercase(project_namespace)}-<ticket>-<short-description>`

Example: `feature/auth-42-add-oauth-endpoint`

If no ticket exists, ask user to create one before commit.

## Quick Commands

| Say | Action |
|-----|--------|
| "task-flow" | Start a NEW task (ticket-first or ticket-late approach) |
| "task-flow-resume" | Resume an EXISTING task from OnGoingTasks |
| "1" or "ticket-first" (after start) | Fetch ticket from configured tracker, create raw_prompt.md |
| "2" or "ticket-late" (after start) | Ask for existing task folder path, read raw_prompt.md |
| "looks good" / "approved" (after prompt-understanding) | Proceed to create execution_plan.md |
| "review plan" | Show plan for approval |
| "start coding" / "approved" (after plan) | ⚠️ Check branch first! Then checkout branch, begin implementation |
| "update plan" | Refresh execution_plan.md with changes |
| "done" / "finished" / "continue" | Create ticket.md + pr-description.md, then commit |
| "task-flow-commit" / "commit" | 🚨 CHECK BRANCH FIRST! Run safety checks before committing |
| "create ticket" | Generate ticket.md |
| "task-flow-pr" / "create PR" | Generate pr-description.md |
| "archive task" | Move task folder to DoneTasks |
| **"task-flow-remember"** or **"remember"** | Quick context recovery when Claude forgets |

## Context Recovery

Use the **task-flow-remember** skill when Claude forgets or loses track mid-session. Use **task-flow-resume** for full recovery after closing Claude.

## Ticket Guidelines

**Good (Product Level):**
```
## Problem
Frontend sends redundant data that backend already has

## Solution
Simplified API - frontend sends only entity ID, backend fetches rest from database
```

**Bad (Code Noise):**
```
Updated OrderService.java to call ProductRepository.findById()
Changed CreateOrderRequest DTO to remove redundant fields
```

**Allowed Details:**
- API request/response JSON
- Database table and column names
- Configuration values

## Skill Updates

When this skill (task-flow) is updated, save the update instructions to:

```
{coding_tasks_root}/SkillUpdates/task-flow-updates.md
```

## Task History Logging

**Purpose:** Track task progress for weekly reports. Tasks are logged to `{coding_tasks_root}/TasksSummary/Backend.md` or `Frontend.md`.

### File Format

```markdown
# Backend Tasks Summary

## Week Ending: January 31, 2026

| Task | Owner | Started | Completed | Description | Weekly Summary |
|------|-------|---------|-----------|-------------|----------------|
| PROJ-193 Fix validation for order flow | dev@example.com | Jan 29 | Jan 30 | Additional context | [Link](../../WeeklySummaries/Week-Ending-2026-01-31/PROJ-193.md) |
| PROJ-191 Payment API changes | dev@example.com | Jan 28 | Jan 29 | Additional context | [Link](../../WeeklySummaries/Week-Ending-2026-01-31/PROJ-191.md) |
| TBD Add new search endpoint | dev@example.com | Jan 30 | - | Additional context | [Link](../../WeeklySummaries/Week-Ending-2026-01-31/TBD-add-search.md) |

## Week Ending: January 24, 2026

| Task | Owner | Started | Completed | Description | Weekly Summary |
|------|-------|---------|-----------|-------------|----------------|
| PROJ-185 Add enrichment endpoint | dev@example.com | Jan 22 | Jan 23 | Additional context | [Link](../../WeeklySummaries/Week-Ending-2026-01-24/PROJ-185.md) |
```

### When to Log

**Task Started (Phase 2):** After `execution_plan.md` is created and approved:

1. **Calculate week ending date** (next Friday from today)
2. **Extract task title/description** from ticket or execution plan
3. **Create weekly summary folder** if it doesn't exist
4. **Create individual weekly summary file**
5. **Add row to TasksSummary**

**Task Completed (Phase 4):** After `pr-description.md` is created:

1. **Update TasksSummary row** — fill in the Completed date
2. **Update weekly summary file** — brief description of what was done

### Week Grouping Rules

- Each week ends on **Friday**
- Calculate week ending: Find the next Friday from current date
- If today is Friday, use today's date
- Tasks appear under the week they were **started**
- If week section doesn't exist, create it (newest weeks at top)

### Determining Platform

Use the `platform` field from `config_hints.json`:
- `"Backend"` → Log to `Backend.md`
- `"Frontend"` → Log to `Frontend.md` (Web)
- `"iOS_Frontend"` → Log to `iOS_Frontend.md`
- `"Android_Frontend"` → Log to `Android_Frontend.md`

### Getting Owner

```bash
git config user.email
```

## Path Configuration Rules

**IMPORTANT:** Never hardcode full paths.

- `skill.config` = user-specific absolute paths (NOT committed)
- `config_hints.json` = project metadata (IS committed, no absolute paths)
- All paths derived at runtime from `tasks_root` and `docs_root`

## Rule Detection

During Phase 1 (Prompt Understanding), analyze the raw prompt to identify which coding rules are especially relevant.

### Detection Map

Match keywords/patterns in the task content to applicable rules:

| Keywords / Patterns in Task | Applicable Rules |
|-----------------------------|-------------------------|
| DB queries, repository, ORM, lazy loading, N+1, batch, performance | `query-efficiency.md`, `orm-repositories.md` |
| External API calls, HTTP client, blocking I/O, transactions | `transaction-boundaries.md` |
| New/changed API endpoint, REST controller, request/response DTOs | `api-conventions.md` |
| External APIs, third-party integrations, API clients | `external-api.md` |
| Background jobs, scheduled tasks, CLI commands | `commands.md` |
| New table, alter table, migration, add column, index | `database-migrations.md` |
| Metrics, monitoring, event tracking, dashboards | `metrics-collection.md` |
| Code review, PR review | `code-review.md` |

**Always-apply rules** (included automatically — no detection needed):
- `coding-conventions.md` — Every code change
- `project-structure.md` — Every file addition/move
- `critical-thinking.md` — Every architectural decision

**Note:** A single task can match multiple rows. List all that apply.

### How It Flows

1. **Phase 1 → Detect:** After writing prompt-understanding.md, scan content against the Detection Map. Append `## Applicable Rules` section listing matched rules with one-line reasoning.
2. **Phase 3 → Apply:** Before coding, read each .md file listed in prompt-understanding.md. Follow their patterns and checklists during implementation.

## References

### Coding Rules
- **Coding Conventions:** `{standards_location}/coding-conventions.md` - Formatting, naming, style
- **API Conventions:** `{standards_location}/api-conventions.md` - API patterns and controller flow
- **Project Structure:** `{standards_location}/project-structure.md` - Module placement
- **ORM/Repositories:** `{standards_location}/orm-repositories.md` - Repository patterns
- **Database Migrations:** `{standards_location}/database-migrations.md` - Migration patterns
- **Commands:** `{standards_location}/commands.md` - Background jobs, CLI commands
- **MCP Integration:** `{standards_location}/mcp-integration.md` - Tracker MCP tool patterns (when using MCP-based trackers)
- **Query Efficiency:** `{standards_location}/query-efficiency.md` - Query optimization, N+1 prevention
- **Transaction Boundaries:** `{standards_location}/transaction-boundaries.md` - Transaction scope rules
- **Metrics Collection:** `{standards_location}/metrics-collection.md` - Monitoring patterns
- **Code Review:** `{standards_location}/code-review.md` - PR review workflow and checklist

**Always refer to these rules during code implementation to ensure consistency.**
