# Task Flow — Complete Reference

## Naming Convention

| Namespace | Purpose | Runs From |
|-----------|---------|-----------|
| `task-flow*` | Core workflow phases & actions | Target project |
| `task-flow-setup:*` | Installation, configuration, updates | Framework repo or target project |
| `task-flow-tool:*` | Standalone tools (installed globally to `~/.claude/skills/`) | Any project |

## Skills Inventory

### Core Workflow

| Skill | Description | Trigger |
|-------|-------------|---------|
| `task-flow` | Main 5-phase orchestrator: Understand → Plan → Code → Document → PR | "task-flow" |
| `task-flow-resume` | Resume an interrupted task from a previous session | "task-flow-resume" |
| `task-flow-review` | In-workflow code review against coding rules. Saves local review logs with iteration tracking. | "task-flow-review" |
| `task-flow-inspector` | Audit OnGoingTasks for health issues: stale tasks, missing files, unarchived completions | "task-flow-inspector" |
| `task-flow-remember` | Quick context recovery when Claude loses track mid-session | "task-flow-remember" |
| `task-flow-fix-comments` | Aggregate and fix PR feedback from SonarQube, CodeRabbit, and human reviewers | "task-flow-fix-comments" |
| `task-flow-commit` | Create a clean, human-readable git commit with safety checks | "task-flow-commit" or "commit" |
| `task-flow-pr` | Create a pull request using the project's PR template | "task-flow-pr" or "pr" |

### Setup & Configuration

| Skill | Description | Trigger | Runs From |
|-------|-------------|---------|-----------|
| `task-flow-setup:initialize` | Install Task Flow into a new project with stack detection, rule generation, and contamination checking | "task-flow-setup:initialize" | Framework repo |
| `task-flow-setup:update` | Incremental update of existing installation. Auto-selects inline/single-agent/full-pipeline mode. | "task-flow-setup:update" | Framework repo |
| `task-flow-setup:install-global-tools` | Install/update global tools (ai-optimizer, review-pr) to `~/.claude/skills/`. Independent of any target project. | "task-flow-setup:install-global-tools" | Framework repo |
| `task-flow-setup:init-skills` | Create directory structure (OnGoingTasks, DoneTasks, TasksSummary, WeeklySummaries) and `.claude/skill.config` | "task-flow-setup:init-skills" | Target project |

### Standalone Tools

| Skill | Description | Trigger |
|-------|-------------|---------|
| `task-flow-tool:review-pr` | High-level PR reviewer. Fetches diff, loads relevant coding rules, runs code-reviewer agent, generates scored draft, posts selected comments to GitHub. Supports multi-PR review. | "task-flow-tool:review-pr" |
| `task-flow-tool:optimize-ai-setup` | Audit and optimize AI-awareness files (CLAUDE.md, AGENTS.md, rules). Detects redundancies, conflicts, bloat. Interactive cleanup with before/after token metrics. | "task-flow-tool:optimize-ai-setup" |

## Agents Inventory

All agents run as background subprocesses. They communicate through files, not conversation context.

| Agent | Model | Purpose | Called By |
|-------|-------|---------|-----------|
| `code-reviewer` | Sonnet | Review code against coding rules, execution plan, and best practices | `task-flow-review`, `task-flow-tool:review-pr` |
| `plan-verifier` | Sonnet | Cross-check execution plan claims against actual codebase | `task-flow` (Phase 2) |
| `doc-writer` | Haiku | Generate `ticket.md` and `pr-description.md` | `task-flow` (Phase 4) |
| `commit-writer` | Haiku | Generate commit messages from context + diff | `task-flow-commit`, `task-flow` (Phase 4) |
| `pr-writer` | Haiku | Generate PR title + body from template | `task-flow-pr`, `task-flow` (Phase 4) |
| `test-runner` | Haiku | Run tests in background and report results | `task-flow` (Phase 4), `task-flow-fix-comments` |

## Configuration Files

### `.claude/config_hints.json` (committed — shared)

```json
{
  "project": {
    "namespace": "PROJ",
    "name": "my-project"
  },
  "platform": "Backend",
  "standards_location": "docs/ai-rules",
  "tracker": {
    "type": "github",
    "url": ""
  },
  "framework_version": "1.0"
}
```

| Field | Purpose |
|-------|---------|
| `project.namespace` | Ticket prefix (e.g., PROJ-123), branch naming |
| `project.name` | Project identifier |
| `platform` | Backend / Frontend / iOS_Frontend / Android_Frontend |
| `standards_location` | Path to coding rules directory |
| `tracker.type` | `jira`, `github`, `linear`, `tiles`, `none` |
| `tracker.url` | Tracker instance URL (jira, tiles only) |
| `framework_version` | Installed Task Flow version |

### `.claude/skill.config` (NOT committed — per-user)

```json
{
  "paths": {
    "tasks_root": "/absolute/path/to/CodingTasks/Backend",
    "docs_root": "/absolute/path/to/docs"
  }
}
```

| Field | Purpose |
|-------|---------|
| `paths.tasks_root` | Absolute path to platform task folder (e.g., `.../Backend`) |
| `paths.docs_root` | Absolute path to docs project (optional) |

### Path Derivation (runtime)

From `tasks_root`:
- `coding_tasks_root` = `dirname(tasks_root)`
- `tasks_folder` = `{tasks_root}/OnGoingTasks`
- `done_folder` = `{tasks_root}/DoneTasks`
- `task_summary_folder` = `{coding_tasks_root}/TasksSummary`
- `weekly_summaries_folder` = `{coding_tasks_root}/WeeklySummaries`
- `reviews_root` = `{coding_tasks_root}/CodeReviews`

## Tracker Integration

Configured via `tracker.type` in `config_hints.json`.

| Moment | jira | github | linear | tiles | none |
|--------|------|--------|--------|-------|------|
| **Check configured** | `claude mcp list \| grep atlassian` | `gh auth status` | Check Linear MCP | Check Tiles MCP/API | Skip |
| **Fetch ticket** | `mcp__atlassian__getJiraIssue` | `gh issue view {n}` | Linear MCP/API | Tiles API/MCP | N/A |
| **Ticket link** | `https://{url}/browse/{ns}-XXX` | `#{number}` | `https://linear.app/issue/{id}` | `{url}/tile/{id}` | `{ns}-XXX` |
| **Update on completion** | Archive desc, update with ticket.md | `gh issue comment`, optionally close | Update status | Update tile | Skip |
| **Create ticket** | `mcp__atlassian__createJiraIssue` | `gh issue create` | Linear MCP/API | Tiles API/MCP | Manual identifier |

## Task Folder Structure

```
{coding_tasks_root}/
├── Backend/                    ← tasks_root
│   ├── OnGoingTasks/
│   │   └── PROJ-195-my-task/   ← individual task folder
│   │       ├── raw_prompt.md
│   │       ├── prompt-understanding.md
│   │       ├── execution_plan.md
│   │       ├── execution-summary.md
│   │       ├── ticket.md
│   │       └── pr-description.md
│   └── DoneTasks/
├── TasksSummary/
│   └── Backend.md
├── WeeklySummaries/
│   └── 2026-03-28/
└── CodeReviews/                ← git-ignored
```

## Workflow Phases

```
Phase 0: Choose Approach (Ticket-First or Ticket-Late)
    ↓
Phase 1: Understand → prompt-understanding.md
    ↓
Phase 2: Plan → execution_plan.md (verified by plan-verifier agent)
    ↓
Phase 3: Code → feature branch, tests, docs
    ↓
Phase 4: Finish → ticket.md, pr-description.md, commit, PR
    ↓
Phase 5: Archive → move to DoneTasks/
```

## Safety Rules

1. **Never commit to main** — detect and block with guidance
2. **Never auto-push** — always ask for explicit approval
3. **Never fabricate** — every concrete detail from code reads or user input
4. **Draft PRs by default** — safer than auto-requesting review

## Installation Methods

| Method | Command | What It Does |
|--------|---------|-------------|
| Quick install | `bash install.sh` | Copy files, create config interactively |
| Smart install | `task-flow-setup:initialize` | Stack detection, rule generation, contamination check |
| Global tools | `bash install-global-tools.sh` | Install ai-optimizer, review-pr to `~/.claude/skills/` |
| Update | `task-flow-setup:update` | Incremental update with smart diff |
| Path setup | `task-flow-setup:init-skills` | Directory structure + skill.config |
