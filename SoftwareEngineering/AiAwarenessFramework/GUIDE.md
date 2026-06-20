# AI Awareness - Complete Guide

**Production-proven agent-readiness framework for any project**

## Table of Contents

1. [What Is This?](#what-is-this)
2. [Quick Install](#quick-install)
3. [How It Works](#how-it-works)
4. [What Gets Installed](#what-gets-installed)
5. [Using the Framework](#using-the-framework)
6. [System Architecture](#system-architecture)
7. [Customization](#customization)
8. [Team Adoption](#team-adoption)
9. [Troubleshooting](#troubleshooting)

---

## What Is This?

**"AI Awareness"** - A systematic approach to making your codebases AI-ready through:

- **Explicit patterns** - Coding rules document every coding convention
- **Automated workflows** - Skills guide AI through task phases
- **Team collaboration** - External task directories for visibility
- **Safety guardrails** - No main commits, mandatory tests, PR reviews

**Designed for real teams:**
- Branch-per-task with safety guardrails (no main-branch commits)
- Stack-aware install that adapts every rule to your detected stack
- Tracker-agnostic (GitHub Issues by default; Jira / Linear / none optional)
- Incremental, customization-preserving upgrades

---

## Quick Install

### Step 1: Run Installation

```bash
cd ~/ai-awareness-framework
claude
```

Say to Claude:
```
Read setup-instructions.md and setup AI Awareness in my project at /path/to/my-project
```

Claude intelligently:
- Checks existing state
- Asks about conflicts
- Copies skills and rules
- Configures for your infrastructure
- Updates .gitignore and CLAUDE.md

### Step 2: Configure Paths

```bash
cd your-project
claude
> aa-init-skills
```

Provide paths to:
- Platform (Backend/Frontend/iOS/Android)
- {Project}_Coding_Tasks/{Platform}
- {Project}_DocsProject (optional)

### Step 3: Start Working

```bash
> aa-task-flow
```

Choose workflow:
- **Ticket-first** - Start from a tracker ticket (GitHub issue, Jira, Linear)
- **Ticket-late** - Start from an idea, add a ticket later (or never, with `tracker.type: none`)

---

## How It Works

### Phase-Based Workflow

```
Raw Prompt → Understand → Plan → Code → Document → Archive
```

**Phase 1: Understand**
- AI reads requirements (from the tracker or a manual prompt)
- Asks clarifying questions about business logic
- Creates `prompt-understanding.md`
- Product approves before coding

**Phase 2: Plan**
- AI creates `execution_plan.md`
- Defines branch name (feature/{namespace}-XXX-description)
- Lists implementation steps
- Developer approves approach

**Phase 3: Code**
- AI reads coding rules for patterns
- Implements following your project's standards
- Runs tests (mandatory)
- Creates PR (no push to main)

**Phase 4: Document**
- AI updates technical docs
- Creates PR description
- Updates the tracker ticket (if ticket-first)
- Generates task summary

**Phase 5: Archive**
- Moves task to DoneTasks/
- Updates weekly summary
- Creates weekly task file
- Searchable knowledge base

### External Task Structure

All work happens in shared directories:

```
Example_Coding_Tasks/Backend/
├── OnGoingTasks/                # Active work (visible to team)
│   └── PROJ-195-simplify-api/
│       ├── raw_prompt.md
│       ├── prompt-understanding.md
│       ├── execution_plan.md
│       ├── execution-summary.md
│       ├── ticket.md
│       └── pr-description.md
│
├── DoneTasks/                   # Completed (searchable)
├── TasksSummary/Backend.md      # Weekly tracking
└── WeeklySummaries/             # Per-task summaries
```

**Benefits:**
- Team sees what everyone is working on
- Product reviews plans before code
- Search DoneTasks for examples
- Complete audit trail

---

## What Gets Installed

### In Your Project

```
your-project/
├── .claude/
│   ├── skills/
│   │   ├── aa-init-skills/      # Path configuration
│   │   ├── aa-task-flow/        # Main workflow
│   │   ├── aa-task-flow-resume/ # Session recovery
│   │   ├── aa-task-flow-remember/ # Context refresh
│   │   └── aa-init-mcps/        # issue tracker connection
│   │
│   ├── settings.json            # Claude permissions
│   └── config_hints.json        # Project metadata
│
├── .cursor/rules/
│   ├── critical-thinking.md    # Challenge bad ideas
│   ├── code-review.md          # PR quality gates
│   ├── task.md                 # Workflow patterns
│   └── [platform-specific]/     # If Java Spring Boot detected
│
├── CLAUDE.md                    # Framework guide
└── .gitignore                   # Updated (excludes skill.config)
```

### Integrations (optional)

- **Issue tracker** - GitHub Issues (default), Jira, or Linear, selected via `tracker.type`
- **Knowledge base** - Confluence pages (when using the Jira/Atlassian adapter)
- **Documentation updates** - your docs-project structure

### Rules

**Universal (any project):**
- Critical thinking (challenge assumptions)
- Code review standards
- Task workflow patterns
- Issue-tracker integration (dispatch table)

**Java Spring Boot (example stack):**
- Multi-module project structure (`com.example.*` package layout)
- API conventions (versioned response envelopes)
- Database migrations
- JPA repositories (soft deletes)
- Transaction boundaries
- External / partner API integration patterns

> The `react/` rules ship as a second example stack. Add a `rules/<your-stack>/`
> directory to cover any other language or framework.

---

## Using the Framework

### Available Commands

**Setup (once per developer):**
```bash
> aa-init-skills     # Configure local paths
> aa-init-mcps       # Connect your issue tracker (gh CLI for GitHub; MCP for Jira/Linear)
```

**Daily workflows:**
```bash
> aa-task-flow          # Start new task
> aa-task-flow-resume   # Resume incomplete task (new session)
> aa-task-flow-remember # Refresh context (same session)
> aa-task-flow-review   # Code review before commit
```

### Ticket-First Workflow

1. Say: `aa-task-flow`
2. Choose: "Ticket-first"
3. Enter the ticket identifier (e.g. `#247` for GitHub, `PROJ-247` for Jira)
4. AI fetches it via the configured tracker (gh CLI / MCP — see the dispatch table)
5. AI creates task folder and `raw_prompt.md`
6. Follow phases: Understand → Plan → Code → Document
7. AI updates the tracker automatically

**When to use:**
- Feature has a tracker ticket
- Requirements clear in the ticket
- Standard workflow

### Ticket-Late Workflow

1. Say: `aa-task-flow`
2. Choose: "Ticket-late"
3. Provide task title and initial prompt
4. AI creates task folder with `raw_prompt.md`
5. Follow phases: Understand → Plan → Code → Document
6. Add a ticket later (AI updates references) — or skip it entirely with `tracker.type: none`

**When to use:**
- Exploratory work
- Urgent bug fixes
- No ticket yet

### Session Recovery

**New session (closed Claude):**
```bash
> aa-task-flow-resume
```

AI reads execution-summary.md and continues from last phase.

**Same session (Claude forgot context):**
```bash
> aa-task-flow-remember
```

AI re-reads task files and skill instructions.

---

## System Architecture

### Component Diagram

```
┌─────────────────────────────────────────────┐
│         PROJECT CODEBASE                         │
│                                             │
│  .cursor/rules/ ─────> AI Reads Patterns   │
│  .claude/skills/ ───> AI Executes Workflow│
│  .claude/config_hints.json ─> Metadata     │
│                                             │
└─────────────────┬───────────────────────────┘
                  │
                  ↓ Derives Paths
                  │
┌─────────────────┴───────────────────────────┐
│    EXTERNAL TASK DIRECTORY (Shared)         │
│                                             │
│  OnGoingTasks/    ← Team visibility         │
│  DoneTasks/       ← Searchable history     │
│  TasksSummary/    ← Weekly tracking         │
│  WeeklySummaries/ ← Per-task archives       │
└─────────────────────────────────────────────┘
```

### Task-Flow State Machine

```
START
  ↓
Choose: Ticket-First or Ticket-Late
  ↓
UNDERSTAND Phase
  ↓
PLAN Phase
  ↓
CODE Phase
  ↓
DOCUMENT Phase
  ↓
ARCHIVE Phase
  ↓
DONE
```

### Pattern Consistency Flow

```
Developer Request
       ↓
AI Reads .cursor/rules/
       ↓
AI Applies Patterns
       ↓
Generated Code (consistent with codebase)
       ↓
aa-task-flow-review (uses aa-code-reviewer agent)
       ↓
PR Created
```

---

## Customization

### For Your Project

**Must customize if different tech stack:**

1. **Coding rules** - Update for your language/framework:
   ```bash
   cd .cursor/rules
   # Edit: coding-conventions.md
   # Edit: api-conventions.md
   # Add: your-framework-patterns.md
   ```

2. **Config hints** - Update platform:
   ```json
   {
     "platform": "Backend|Frontend|iOS|Android",
     "path_derivation_rules": { ... }
   }
   ```

**Keep as-is:**
- Skill workflow structure
- Safety checks
- External task directories
- Universal rules (critical-thinking, code-review, task)

### Platform Examples

**Backend (Python/Django):**
- Customize coding-conventions.md for Python
- Update api-conventions.md for Django REST
- Keep: transaction patterns, database migrations

**Frontend (React/Vue/Angular):**
- Customize for component patterns
- Update for state management approach
- Keep: testing standards, code review gates

---

## Team Adoption

### Phase 1: Pilot (Week 1)

**Setup:**
- Install framework in 1 project
- 1-2 developers test with real features

**Validate:**
- External tasks visible to team
- Safety checks working
- Tests required before PR
- Documentation generated

### Phase 2: Refine (Week 2-3)

**Customize:**
- Update coding rules for actual patterns
- Add missing conventions
- Adjust execution plan template

**Test:**
- Run similar tasks
- Verify identical code patterns
- Gather feedback

### Phase 3: Rollout (Week 4+)

**Expansion:**
- Rest of team runs `aa-init-skills`
- Start with ticket-late (simpler)
- Gradually adopt ticket-first
- Monitor adoption metrics

**Success Metrics:**
- Feature delivery time
- PR approval rate
- Test coverage
- Team adoption percentage

---

## Troubleshooting

### Installation Issues

**"Coding rules not followed"**
- Check rules in `.cursor/rules/`
- Verify `.md` file extension
- Ensure `alwaysApply: true` in frontmatter

**"Init skills not found"**
- Make sure in project directory
- Run `claude` to enter CLI
- Type without `>` prefix: `aa-init-skills`

### Workflow Issues

**"External tasks not visible"**
- Check tasks_root path in `.claude/skill.config`
- Verify path on shared/network drive
- Confirm team has read access

**"AI not following execution plan"**
- Say: `aa-task-flow-remember`
- AI re-reads task files and skill

**"Can't resume task"**
- Say: `aa-task-flow-resume`
- Provide task folder path
- AI reads execution-summary.md

### Pattern Issues

**"Code doesn't match existing patterns"**
- Update `.cursor/rules/` with actual patterns
- Run: `aa-task-flow-review` before commit
- aa-code-reviewer agent checks patterns

---

## FAQ

**Q: Do I need Claude Code CLI?**
A: Yes, for skills. Coding rules work with any AI.

**Q: Can I use this with my tech stack?**
A: Yes! Customize coding rules for your platform.

**Q: What if we don't use Jira?**
A: GitHub Issues is the default tracker (it uses the `gh` CLI, no MCP). Set `tracker.type` to `github`, `linear`, or `none` in `config_hints.json`. With `none`, run ticket-late exclusively.

**Q: Do I need external task directories?**
A: Recommended for team visibility. Can start local.

**Q: Can I customize aa-task-flow phases?**
A: Yes! Skills are markdown - edit to match process.

---

## Support

**For questions:**
- Check your project's CLAUDE.md
- Browse OnGoingTasks for examples
- Contact the owning team

**For contributions:**
- Document new patterns discovered
- Share coding rules for your stack
- Help other teams adopt

---

**Framework Version:** see `config_hints.json` (canonical source)
