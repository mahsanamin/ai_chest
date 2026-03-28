# Task Flow — Structured AI Development Workflow

A complete, production-tested workflow system for [Claude Code](https://claude.ai/code) that takes you from a raw task description to a merged pull request. Built for teams that want consistent, high-quality AI-assisted development.

## What This Is

Task Flow is a structured 5-phase development workflow designed for Claude Code:

```
Raw Prompt → Understand → Plan → Code → Document → PR
```

Each phase produces tracked artifacts, enforces safety checks, and integrates with your existing tools (issue trackers, GitHub, your test suite). It's not just a prompt — it's a full development methodology with session recovery, parallel agents, and automated documentation.

## Components

```
Task_Flow/
├── install.sh                          # Quick installer (copies files + creates config)
├── .claude/skills/                     # Framework-level skills (run FROM this repo)
│   ├── task-flow-setup:initialize/     # Smart stack-aware installer for new projects
│   └── task-flow-setup:update/         # Incremental framework updater
│
├── skills/                             # Workflow skills (installed INTO target projects)
│   ├── task-flow/                      # Main orchestrator — the 5-phase workflow
│   ├── task-flow-resume/               # Resume interrupted tasks across sessions
│   ├── task-flow-review/               # Code review against project rules
│   ├── task-flow-inspector/            # Audit task health and hygiene
│   ├── task-flow-remember/             # Quick context recovery mid-session
│   ├── task-flow-fix-comments/         # Fix PR feedback (SonarQube, CodeRabbit, human)
│   ├── task-flow-setup:init-skills/     # Directory structure + skill.config setup
│   ├── task-flow-review-pr/             # Standalone PR review
│   ├── task-flow-commit/               # Clean, human-readable commits
│   └── task-flow-pr/                   # PR creation with templates
│
├── agents/                             # Background agents (installed INTO target projects)
│   ├── code-reviewer/                  # Reviews code against coding rules (Sonnet)
│   ├── doc-writer/                     # Generates ticket.md + pr-description.md (Haiku)
│   ├── commit-writer/                  # Creates commit messages (Haiku)
│   ├── pr-writer/                      # Fills PR templates (Haiku)
│   ├── test-runner/                    # Runs tests in background (Haiku)
│   └── plan-verifier/                  # Validates execution plans (Sonnet)
│
└── templates/                          # Commit and PR templates
    ├── commit-template.md
    └── pr-template.md
```

## Quick Start

### Option A: Quick Install (shell script)

```bash
# From your project root
bash /path/to/Task_Flow/install.sh
```

Copies files, creates config interactively. Good for simple setups.

### Option B: Smart Install (recommended)

Open Claude Code in the Task_Flow repo directory and say:

```
> task-flow-setup:initialize
```

This runs the full stack-aware installer:
- Detects your project's tech stack (language, framework, build tool)
- Generates project-aligned coding rules from your actual codebase
- Adapts all skills/agents for your stack
- Creates AGENTS.md and CLAUDE.md
- Runs contamination check (no foreign-stack references)

### After installation

In the target project:

```
> task-flow-setup:init-skills    # Set up directory structure and paths
> task-flow            # Start your first task
```

## Configuration

**`.claude/config_hints.json`** (committed — shared project config):

```json
{
  "project": {
    "namespace": "PROJ",
    "name": "my-project"
  },
  "platform": "Backend",
  "standards_location": "docs/ai-rules",
  "tracker": {
    "type": "github"
  },
  "framework_version": "1.0"
}
```

**Supported trackers:** `jira`, `github`, `linear`, `tiles`, `none`

**`.claude/skill.config`** (NOT committed — user-specific paths):

```json
{
  "paths": {
    "tasks_root": "/absolute/path/to/MyProject_Coding_Tasks/Backend",
    "docs_root": "/absolute/path/to/docs"
  }
}
```

## The 5 Phases

### Phase 0: Choose Approach
- **Ticket-First**: Start from an existing ticket/issue (fetches from configured tracker)
- **Ticket-Late**: Start from a raw_prompt.md you've written

### Phase 1: Understand
- Reads your raw prompt, asks clarifying questions
- Creates `prompt-understanding.md`
- Detects which coding rules apply

### Phase 2: Plan
- Explores codebase, creates `execution_plan.md`
- Plan verifier agent cross-checks all claims against actual code
- You review and approve before any code is written

### Phase 3: Code
- Creates feature branch, writes code following your standards
- Updates tests, keeps execution-summary.md updated for recovery

### Phase 4: Finish
- Runs tests, code review, documentation
- Gets ticket number, commits, creates PR (draft by default)

### Phase 5: Archive
- Moves completed task to DoneTasks/

## Key Features

### Session Recovery
Use `task-flow-resume` to pick up exactly where you left off. Use `task-flow-remember` for quick mid-session context recovery.

### Safety Rails
- Never commits to main, never auto-pushes, never fabricates
- Draft PRs by default

### Parallel Agents
Test runner, code reviewer, and doc writer can run simultaneously during Phase 4.

### PR Feedback Loop
After CI runs, use `task-flow-fix-comments` to aggregate and fix SonarQube, CodeRabbit, and human reviewer feedback in priority order.

### Multi-Tracker Support
Jira, GitHub Issues, Linear, Tiles, or no tracker — configure once, workflow adapts.

## All Commands

| Command | Where to Run | Action |
|---------|-------------|--------|
| `task-flow-setup:initialize` | Framework repo | Install into a new project |
| `task-flow-setup:update` | Framework repo | Update existing installation |
| `task-flow-setup:init-skills` | Target project | Set up directory structure + paths |
| `task-flow` | Target project | Start a new task |
| `task-flow-resume` | Target project | Resume an existing task |
| `task-flow-review` | Target project | Code review against rules |
| `task-flow-fix-comments` | Target project | Fix PR feedback |
| `task-flow-inspector` | Target project | Audit task health |
| `task-flow-remember` | Target project | Quick context recovery |
| `task-flow-review-pr` | Target project | Standalone PR review |
| `task-flow-commit` | Target project | Create a git commit |
| `task-flow-pr` | Target project | Create a pull request |

## Adapting to Your Stack

Task Flow is **stack-agnostic**. The `task-flow-setup:initialize` skill auto-detects your stack and generates appropriate rules. You can also create rules manually in your `{standards_location}` directory.

## Requirements

- [Claude Code](https://claude.ai/code) CLI, desktop app, or IDE extension
- `gh` CLI (for PRs and GitHub Issues tracker)
- `jq` (for config parsing)
- Optional: Atlassian MCP server (for Jira tracker)
- Optional: Linear MCP server (for Linear tracker)

## License

Open source. Use, modify, and share freely.
