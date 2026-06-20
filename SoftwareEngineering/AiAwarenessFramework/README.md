# AI Awareness Framework

**Production-proven framework for making your codebases AI-ready.**

The source files for skills, agents, rules, and templates that get **installed into** other projects to give them a structured, safety-checked AI workflow.

- **Repo:** [your-org/ai-awareness-framework](https://github.com/your-org/ai-awareness-framework)
- **Version:** v7.17.1 (see [`config_hints.json`](./config_hints.json) for the canonical source)
- **License:** MIT (see [`LICENSE`](./LICENSE))

---

## Issue Tracker Support (not just Jira)

This framework is **tracker-agnostic**. Each project declares its tracker in `config_hints.json`:

```json
"tracker": { "type": "github", "url": "" }
```

Supported: **`github`** (GitHub Issues via the `gh` CLI — the default), **`jira`** (Atlassian, via MCP), **`linear`** (via MCP), and **`none`** (no tracker; describe work in prompts). Skills never hardcode a tracker — every ticket operation resolves through the **Tracker Dispatch Table** in [`rules/universal/mcp-integration.md`](./rules/universal/mcp-integration.md). Switching trackers is a one-line config change.

---

## Clone the Framework

This framework is now its own dedicated repository. Clone it once to a stable location on your machine — the path becomes `AA_FRAMEWORK_DIR` and is referenced by your shell startup and all install/upgrade commands.

```bash
git clone git@github.com:your-org/ai-awareness-framework.git \
  ~/ai-awareness-framework
```

> The rest of this README assumes that path. If you cloned elsewhere, substitute your own path everywhere you see `~/ai-awareness-framework`.

---

## Keep Your Global Tools Current

Every developer keeps a per-machine copy of the framework's helper scripts and agents under `~/.claude/` — even teammates who never run `aa-install` or `aa-upgrade` themselves. When the framework adds a new script (like `aa_g_worktree_review`) or refreshes an agent, you need to sync your local copy.

**One command, after `git pull` in the framework repo:**

```bash
cd ~/ai-awareness-framework
git pull
./install-tools.sh
```

That installs/refreshes:

- `~/.claude/scripts/` — every script declared in `scripts/manifest.json` (sonarqube fetch, worktree helpers, …).
- `~/.claude/agents/` — every framework agent (`aa-code-reviewer`, `aa-test-runner`, …).
- `~/.claude/skills/` — every skill listed in `scripts/manifest.json`'s `global_skills` array (currently `aa-optimizer`, `aa-record-improvement`, `aa-global-pr-reviewer`).
- A marker-guarded block in your `~/.zshrc` / `~/.bashrc` that exports `AA_FRAMEWORK_DIR` and sources `worktree.sh` on every new shell.

The script is idempotent — re-running it never duplicates the shell-rc block.

**You don't need to remember to run it.** After the first install, `worktree.sh` checks on every new shell whether the framework repo is behind `origin/main` and prints a one-line nudge:

```
[ai-awareness] Framework updates available:
  • 3 commit(s) on origin/main not pulled
  Refresh: (cd ~/ai-awareness-framework && git pull && ./install-tools.sh)
```

Inside Claude Code you can also say `aa-install-tools` — it's a thin wrapper that runs the same script.

---

## Fresh Install (into a target project)

**Use Claude Opus 4.6+** for setup accuracy.

```bash
cd ~/ai-awareness-framework
claude
```

Say:
```
aa-install
```

The skill walks you through these steps:

1. **Project path** — provide your target project directory
2. **Branch** — creates `feature/ai-awareness-setup` from latest main (pulls first)
3. **Prerequisites** — validates gh CLI, framework files, reads framework version
4. **Configuration** — project name, issue tracker (GitHub Issues by default; Jira/Linear optional), namespace(s), standards location
5. **Bootstrap** _(greenfield only)_ — runs `claude init`, generates project-aligned rules
6. **Stack detection** — Stack Analyzer reads your project and maps the technology stack
7. **Installation** — 4 writer agents adapt and install skills, rules, agents, templates
8. **Verification** — independent Contamination Checker checks for foreign-stack references

After installation completes:
```bash
cd your-project
claude
> aa-init-skills    # configure your local paths
> aa-init-mcps      # connect your issue tracker (GitHub uses gh CLI; Jira/Linear use MCP)
> aa-task-flow      # start your first task
```

---

## Update an Existing Project

```bash
cd ~/ai-awareness-framework
claude
```

Say:
```
aa-upgrade
```

The skill walks you through:

1. **Project path** — provide your target project directory
2. **Branch** — creates `feature/ai-awareness-update` from latest main
3. **Version comparison** — reads installed vs framework version, parses CHANGELOG
4. **Change summary** — shows exactly what changed since your version, asks to proceed
5. **Update** — only processes changed files, preserves your customizations via Smart Diff
6. **Verification** — checks for contamination in clean context
7. **Finalize** — updates version in `config_hints.json`

---

## What You Get

- **Automated workflows** — `aa-task-flow`, `aa-task-flow-resume`, `aa-init-skills`
- **Proven patterns** — Coding rules from 100+ completed tickets
- **Team visibility** — External task directories for collaboration
- **Safety guardrails** — No main commits, mandatory tests, PR reviews
- **Stack-aware installation** — Content Adaptation Pipeline detects your stack and adapts all files
- **Bootstrap rules** _(greenfield)_ — Project-specific conventions generated from your actual code

## What Gets Installed Into Your Project

```
your-project/
├── .claude/
│   ├── skills/              # workflow automation skills
│   ├── agents/              # Background agents (aa-test-runner, aa-plan-verifier, etc.)
│   ├── settings.json        # Claude Code permissions
│   └── config_hints.json    # Project metadata + installed framework version
│
├── {standards_location}/    # Coding patterns (configurable location)
│   ├── critical-thinking.md
│   ├── code-review.md
│   ├── task.md
│   ├── [platform-specific]  # Adapted to your detected stack
│   └── [project-specific]   # Bootstrap-generated (greenfield only)
│
├── AGENTS.md                # Single source of truth
└── CLAUDE.md                # Points to @AGENTS.md
```

---

## This Repository's Layout

```
ai-awareness-framework/
├── config_hints.json         # Framework version (canonical source)
├── README.md                 # This file
├── GUIDE.md                  # Complete user guide
├── CHANGELOG.md              # Per-version changes (drives incremental updates)
├── VERSIONING.md             # Version-bump strategy
├── setup.md                  # Procedures reference used by aa-install / aa-upgrade
├── migration.json            # Versioned skill/agent rename map (for aa-upgrade)
├── install-tools.sh          # Idempotent installer for global tools + shell rc block
├── settings.json             # Default Claude Code permissions copied to targets
├── CLAUDE.md                 # Repo-local guidance for Claude Code
│
├── .claude/commands/         # Framework-operational commands (run inside this repo)
│   ├── aa-install/           # Fresh install into a target project
│   ├── aa-upgrade/           # Incremental update of an existing target
│   ├── aa-install-tools/     # Sync ~/.claude global tools
│   ├── aa-install-context/   # Install context-processing skills into a Docs Project
│   └── aa-add-improvement/   # Framework development helper
│
├── skills/                   # Source skills copied into target projects
│   ├── aa-task-flow/
│   ├── aa-task-flow-planner/
│   ├── aa-ticket-creator/
│   ├── aa-api-dd-compare/
│   ├── aa-dd-api-performance/
│   ├── aa-task-flow-remember/
│   ├── aa-task-flow-resume/
│   ├── aa-task-flow-review/
│   ├── aa-task-flow-fix-comments/
│   ├── aa-commit/
│   ├── aa-pr/
│   ├── aa-review-pr/
│   ├── aa-init-mcps/
│   ├── aa-init-skills/
│   ├── aa-optimizer/             # global-only (installed under ~/.claude/skills/)
│   ├── aa-record-improvement/    # global-only
│   └── aa-global-pr-reviewer/    # global-only
│
├── agents/                   # Background agents (aa-code-reviewer, aa-test-runner, …)
├── rules/
│   ├── universal/            # Patterns that apply to any project
│   ├── java-spring-boot/     # Java Spring Boot specific patterns
│   └── react/                # React SPA specific patterns
├── templates/                # Commit, PR, and shell-hint templates
├── context-skills/           # Templates for Docs-Project context skills
├── workspace-skills/         # Skills installed into workspace projects (not code repos)
├── workspace-rules/          # Rules paired with workspace-skills
└── scripts/                  # Shared scripts installed to ~/.claude/scripts/
    ├── manifest.json
    ├── aa-worktree/
    ├── aa-sonarqube/
    └── aa-freshness/
```

---

## What Makes It Different

- **Stack-agnostic by construction** — skills, agents, and universal rules carry zero language/stack idioms. Stack specifics live in `rules/<stack>/`, adapted to your project at install time.
- **Tracker-agnostic** — GitHub Issues, Jira, Linear, or none, selected by one config key.
- **Safety guardrails** — no main-branch commits, branch-per-task, mandatory tests, PR review gates.
- **Incremental upgrades** — `aa-upgrade` only touches changed files and preserves your customizations via Smart Diff.

This is the open-source distribution of a framework that has been used in day-to-day production engineering across many repositories and developers.

---

## Learn More

- **Complete guide:** [`GUIDE.md`](./GUIDE.md) — architecture, workflows, customization
- **Setup procedures:** [`setup.md`](./setup.md) — referenced by skills, not run directly
- **Changelog:** [`CHANGELOG.md`](./CHANGELOG.md) — version history
- **Versioning:** [`VERSIONING.md`](./VERSIONING.md) — when to bump major / minor / patch
- **Migration map:** [`migration.json`](./migration.json) — skill/agent renames across versions

---

## Requirements

- Claude Code CLI
- Claude Opus 4.6+ recommended for initial setup
- Git access to your repos
- _(Optional)_ External task tracking directory for team collaboration

---

## Contributing

Improvements are made through the `aa-add-improvement` command from inside this repo. See [`VERSIONING.md`](./VERSIONING.md) for when to bump major / minor / patch and which files to update (`config_hints.json`, `CLAUDE.md`, `CHANGELOG.md`). See [`CONTRIBUTING.md`](./CONTRIBUTING.md) for the contribution flow.

---

## License

[MIT](./LICENSE) © Ahsan Amin.

**Maintained by [Ahsan Amin](https://github.com/mahsanamin).**
