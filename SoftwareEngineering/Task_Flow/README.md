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
├── install.sh                 # Installer script — sets up everything
├── skills/                    # Workflow skills (install to .claude/skills/)
│   ├── task-flow/             # Main orchestrator — the 5-phase workflow
│   ├── task-flow-resume/      # Resume interrupted tasks across sessions
│   ├── task-flow-review/      # Code review against project rules
│   ├── task-flow-inspector/   # Audit task health and hygiene
│   ├── task-flow-remember/    # Quick context recovery mid-session
│   ├── github-commit/         # Clean, human-readable commits
│   └── github-pr/             # PR creation with templates
│
├── agents/                    # Background agents (install to .claude/agents/)
│   ├── code-reviewer/         # Reviews code against coding rules (Sonnet)
│   ├── doc-writer/            # Generates ticket.md + pr-description.md (Haiku)
│   ├── commit-writer/         # Creates commit messages (Haiku)
│   ├── pr-writer/             # Fills PR templates (Haiku)
│   ├── test-runner/           # Runs tests in background (Haiku)
│   └── plan-verifier/         # Validates execution plans (Sonnet)
│
└── templates/                 # Commit and PR templates
    ├── commit-template.md
    └── pr-template.md
```

## Quick Start

### 1. Install into your project

```bash
# From your project root
bash /path/to/Task_Flow/install.sh
```

The installer will:
- Copy skills, agents, and templates into your project
- Interactively create `.claude/config_hints.json` (project config)
- Interactively create `.claude/skill.config` (user-specific paths)
- Add appropriate `.gitignore` entries

### 2. Project configuration

The installer creates `.claude/config_hints.json` (committed to repo — shared config):

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
  }
}
```

**Supported trackers:** `jira`, `github`, `linear`, `tiles`, `none`

For trackers that need a URL (jira, tiles), the config includes:
```json
"tracker": {
  "type": "jira",
  "url": "your-org.atlassian.net"
}
```

And `.claude/skill.config` (NOT committed — user-specific paths):

```json
{
  "paths": {
    "tasks_root": "/absolute/path/to/MyProject_Coding_Tasks/Backend",
    "docs_root": "/absolute/path/to/docs",
    "reviews_root": "/absolute/path/to/CodeReviews"
  }
}
```

### 3. Start using it

```
> task-flow
```

Claude will guide you through the workflow.

## The 5 Phases

### Phase 0: Choose Approach
- **Ticket-First**: Start from an existing ticket/issue (fetches from your configured tracker)
- **Ticket-Late**: Start from a raw_prompt.md you've written

### Phase 1: Understand
- Reads your raw prompt
- Asks clarifying questions (never skipped)
- Creates `prompt-understanding.md` — a refined version of requirements
- Detects which coding rules apply to this task

### Phase 2: Plan
- Explores your codebase structure
- Creates `execution_plan.md` with files to change, test plan, branch name
- **Plan verifier agent** cross-checks all claims against actual code
- You review and approve before any code is written

### Phase 3: Code
- Creates feature branch from main
- Writes code following your project's coding standards
- Updates tests, documentation
- Keeps execution-summary.md updated for session recovery

### Phase 4: Finish
- Runs full test suite
- Code review agent checks against coding rules
- Creates `ticket.md` (product-level) and `pr-description.md` (technical)
- Gets ticket number, renames branch
- Commits (with safety checks — never to main)
- Creates PR (draft by default)

### Phase 5: Archive
- Moves completed task to DoneTasks/
- Pushes documentation

## Key Features

### Session Recovery
Task flow creates `execution-summary.md` at every phase — if Claude loses context or you start a new session, use `task-flow-resume` to pick up exactly where you left off.

### Safety Rails
- **Never commits to main** — detects and blocks with clear guidance
- **Never auto-pushes** — always asks for explicit approval
- **Never fabricates** — Rule 4 ensures every detail comes from actual code reads
- **Draft PRs by default** — safer than auto-requesting review

### Parallel Agents
During Phase 4, multiple agents can run simultaneously:
- Test runner validates in background
- Code reviewer checks compliance
- Doc writer generates documentation

### Task Tracking
Built-in weekly task logging with `TasksSummary/` tables and `WeeklySummaries/` files — useful for standups and weekly reports.

### Multi-Tracker Support
Configure your issue tracker once in `config_hints.json` and the workflow adapts:
- **Jira** — Fetch/create/update tickets via Atlassian MCP
- **GitHub Issues** — Fetch/create/close issues via `gh` CLI
- **Linear** — Fetch/update issues via Linear MCP
- **Tiles** — Fetch/update tiles via Tiles API/MCP
- **None** — Manual mode, no tracker integration

## Quick Commands

| Command | Action |
|---------|--------|
| `task-flow` | Start a new task |
| `task-flow-resume` | Resume an existing task |
| `task-flow-review` | Run code review |
| `task-flow-inspector` | Audit task health |
| `task-flow-remember` | Quick context recovery |
| `commit` | Create a git commit |
| `pr` | Create a pull request |

## Adapting to Your Stack

Task Flow is **stack-agnostic**. The skills reference `{standards_location}` for coding rules — you provide the rules for your stack:

- **Java/Spring Boot**: Create rules for JPA, transactions, migrations
- **React/TypeScript**: Create rules for components, hooks, state management
- **Python/Django**: Create rules for models, views, serializers
- **Go**: Create rules for error handling, concurrency, testing

The workflow itself (understand → plan → code → document) works the same regardless of language.

## Integrations

- **Issue Trackers** — Jira, GitHub Issues, Linear, Tiles (configurable via `tracker.type`)
- **GitHub** — Create PRs, check merged status (via `gh` CLI)
- **Any test framework** — Gradle, Maven, npm, pytest, cargo, go test
- **Any CI system** — Works alongside your existing CI/CD

## Requirements

- [Claude Code](https://claude.ai/code) CLI, desktop app, or IDE extension
- `gh` CLI (for PR creation and GitHub Issues tracker)
- `jq` (for config parsing)
- Optional: Atlassian MCP server (for Jira tracker)
- Optional: Linear MCP server (for Linear tracker)

## Contributing

Contributions welcome! If you adapt Task Flow for a new stack or add useful features:

1. Keep skills stack-agnostic where possible
2. Use `{standards_location}` for stack-specific rules
3. Test with Claude Code before submitting
4. Remove any org-specific references

## License

Open source. Use, modify, and share freely.
