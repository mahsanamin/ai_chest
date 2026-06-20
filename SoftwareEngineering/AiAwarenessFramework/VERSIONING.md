# AI Awareness Versioning Strategy

## Version Format

**`{major}.{minor}.{patch}`** — e.g., `5.0.0`, `5.0.1`, `5.1.0`

## When to Bump

### Patch Update: `5.0.0` → `5.0.1`

Small, incremental changes that don't break existing installations:

- Bug fixes in existing skills/agents/rules
- Wording improvements
- New optional rules added (existing rules unchanged)
- Template tweaks
- Documentation updates

**Key signal:** Existing projects continue working without re-running setup.

### Minor Update: `5.0.x` → `5.1.0`

Additive changes that expand framework capabilities:

- New skills or agents added
- Significant enhancements to existing skills/agents
- New rule categories or workflow steps

**Key signal:** Existing projects work but should update to get new capabilities.

### Major Update: `5.x.x` → `6.0.0`

Significant changes that affect how the framework works:

- Skill interface changes (different inputs/outputs)
- Breaking changes to config_hints.json schema
- New required directories or files
- Workflow changes (e.g., new phases in aa-task-flow)
- Structural reorganization (e.g., rules directory layout change)

**Key signal:** Existing projects need to re-run setup or manually update structure.

## Where Version Is Tracked

- **`config_hints.json`** — Canonical source of truth (`framework_version` field)
- **`CLAUDE.md`** — Human-readable (`Version: v{X.Y.Z}` in header)
- **`CHANGELOG.md`** — Detailed per-version file changes (used for incremental updates)
- **`config_hints.json` in target projects** — Tracks which framework version was last installed (used for update detection)

## How to Bump Version

1. Update `framework_version` in `config_hints.json` (canonical source)
2. Update the `Version:` line in `CLAUDE.md`
3. Add entry to `CHANGELOG.md` with detailed file changes
4. Commit to framework repo
