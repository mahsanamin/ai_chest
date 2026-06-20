# AI Awareness Framework

**Production-proven framework for making your codebases AI-ready.**

## What This Is

This repository contains the SOURCE files for the AI Awareness framework. It's not a project itself — it's a collection of skills, agents, rules, and templates that get INSTALLED into other projects.

Version: v7.17.1

## Non-Obvious Layout Notes

- `setup.md` — procedures reference consumed by the `aa-install` and `aa-upgrade` commands (not just human docs)
- `scripts/` — installed globally to `~/.claude/scripts/` by `aa-install-tools` (not project-local)
- `skills/`, `agents/`, `rules/`, `templates/` — installable artifacts that get copied/adapted into target projects, **not** active rules for this repo

## Version Management

**Canonical version source:** `config_hints.json` → `framework_version` (at the framework root).
The `Version:` line in this file's header is kept in sync for human readability.

See `VERSIONING.md` for bump rules and which files to update.

## Writing Rules and Skills

When creating or updating skills/agents/rules for this framework, follow official Claude Code guidelines:

- [Claude Code Best Practices](https://code.claude.com/docs/en/best-practices)
- [How Claude Code Works](https://code.claude.com/docs/en/how-claude-code-works)

Key principles:
- Avoid redundancy and rule echoes
- Don't document what's inferable from code
- Keep rules token-efficient
- Use YAML frontmatter for skills
- Follow aa-optimizer optimization patterns
- **Skills/agents carry ZERO language/stack idioms** — they're generic procedure that defers to the project's installed rules + `config_hints` command seam. All stack-specific knowledge lives in `rules/`, adapted per stack by the installer. **No supporting prose** (no "Why this exists", origin stories, ticket/trace IDs, version-history markers) — aa-optimizer check 3n enforces this. (Canonical decision; see `docs/plans/stack-agnostic-adaptation.md`.)

## Development Workflow

1. Make changes to skills/agents/rules
2. Use `aa-add-improvement` command to manage version updates
3. Test changes by installing in a test project
4. Commit to this repo
5. Other projects can update by running the `aa-upgrade` command

## Incorporating Improvements (multi-team — these are non-negotiable)

When picking up recorded improvements via `aa-add-improvement`, the command's **Operating Principles** apply (see `.claude/commands/aa-add-improvement/SKILL.md`). Summary, kept here so every session in this repo has it in context:

- **Run it as a goal** — read the whole pending set, finish it, don't stop after one file.
- **Contradiction check FIRST** — before editing any framework file, confirm the picked improvements are mutually consistent and don't conflict with the framework or an open PR. Multiple teams consume this framework; a contradictory change has outsized blast radius. On conflict: STOP, surface both, ask the user which wins, reconcile, then apply.
- **Apply in dependency order** — consume `improvements/ORDER.md` / `sequence:` frontmatter; out-of-order application breaks dependent fixes.
- **Flag time/step cost** — if an addition adds wall-clock time, a round-trip, or a new mandatory step to a frequently-run path, call it out to the user and in the CHANGELOG, and prefer opt-in/configurable designs.
- **One PR when asked** — if an open PR already covers this work, commit to its branch and roll version/CHANGELOG forward in place; don't open a second PR.

## How Target Projects Use This

Target projects install the framework by:
1. Running the `aa-install` command from this repo
2. Getting skills, agents, rules, templates adapted to their stack via Content Adaptation Pipeline
3. Creating `config_hints.json` (specific to their project)
4. Creating `AGENTS.md` (their single source of truth)

See `README.md` for installation instructions.
