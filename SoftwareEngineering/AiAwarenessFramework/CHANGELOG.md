# Changelog

All notable changes to the AI Awareness Framework are documented here. This is
the **public distribution** of the framework. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project uses
[semantic versioning](./VERSIONING.md). The canonical version is
`config_hints.json` → `framework_version`.

The `aa-upgrade` command parses this file to compute what changed between an
installed version and the current one, so keep entries per-version and concrete.

## [7.17.1] — Initial public release

First public, fully generic release. Derived from an internally-developed,
production-proven framework and genericized so it carries **zero** company or
single-vendor assumptions.

### Generic by construction
- **Tracker-agnostic.** The issue tracker is selected by `tracker.type` in
  `config_hints.json`: `github` (GitHub Issues via the `gh` CLI — the default),
  `jira` (Atlassian via MCP), `linear` (via MCP), or `none`. Skills never
  hardcode a tracker; every ticket operation resolves through the **Tracker
  Dispatch Table** in `rules/universal/mcp-integration.md`. Jira is no longer
  required — it is one adapter among several.
- **Stack-agnostic skills and agents.** Skills, agents, and universal rules
  carry no language/stack idioms. Stack specifics live in `rules/<stack>/`
  (`java-spring-boot` and `react` ship as worked examples) and are adapted to
  the target project at install time.
- **No company identity.** Absolute developer paths, internal hostnames,
  package roots, product names, and internal library names were replaced with
  neutral placeholders (`com.example.*`, `your-org.atlassian.net`,
  `example.com`, `~/repos/...`).
- **Configurable noise lint.** `scripts/aa-lint/project-noise-lint.sh` takes its
  product/project slug list from `PROJECT_SLUGS` (env-overridable) instead of a
  hardcoded list.

### Included
- `aa-install` / `aa-upgrade` — stack-aware install and incremental,
  customization-preserving upgrade.
- `aa-task-flow` and its companions (`-planner`, `-resume`, `-remember`,
  `-review`, `-fix-comments`), `aa-commit`, `aa-pr`, `aa-review-pr`,
  `aa-ticket-creator`, `aa-init-skills`, `aa-init-mcps`.
- Background agents: `aa-code-reviewer`, `aa-test-runner`, `aa-plan-verifier`,
  `aa-doc-writer`, `aa-pr-writer`, `aa-commit-writer`.
- Universal + example-stack rules, commit/PR/shell-hint templates, and the
  global tooling installer (`install-tools.sh`, `scripts/`).

[7.17.1]: https://github.com/your-org/ai-awareness-framework/releases/tag/v7.17.1
