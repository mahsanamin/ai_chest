---
name: task-flow-setup:initialize
description: Install Task Flow framework into a new project. Uses stack detection for intelligent, stack-aware file adaptation. Say "task-flow-setup:initialize" or "initialize project".
disable-model-invocation: true
---

# Initialize Project

Install the Task Flow framework into a new project with intelligent stack detection and content adaptation.

## When to Use

- Fresh install into a project that has never had Task Flow
- Project has NO `.claude/config_hints.json` file
- If the project already has `config_hints.json`, use `update-project` instead

## Prerequisites

- Working directory: Task Flow framework repo (this repo)
- Target project path provided by user
- `jq` installed

## What This Skill Does

6-phase process:
1. **Validate & Gather** — Prerequisites, target path, config
2. **Bootstrap** _(greenfield only)_ — Deep-read project, generate project-aligned rules
3. **Research** — Stack detection → technology mapping
4. **Install** — Copy and adapt skills, agents, rules, templates, config
5. **Verify** — Scan for foreign-stack references or unreplaced placeholders
6. **Summary** — Report what was installed, next steps

## Phase 1: Validate and Gather

### 1a. Ask for Target Project

Ask: **"What is the path to your project?"**

Wait for the user to type the actual path. Validate the directory exists. Store as `TARGET_PROJECT`.

```bash
ls {TARGET_PROJECT}/.claude/config_hints.json 2>/dev/null
```

If found → tell user to run `update-project` instead. Stop.

### 1b. Create Install Branch

```bash
git -C {TARGET_PROJECT} symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'
```
```bash
git -C {TARGET_PROJECT} branch --show-current
```

If on default branch, offer to create `feature/task-flow-setup`. If already on a feature branch, use it silently.

### 1c. Validate Prerequisites

- Check `gh` CLI: `command -v gh`
- Check `jq`: `command -v jq`
- Validate framework files exist: `ls {FRAMEWORK_PATH}/skills/ {FRAMEWORK_PATH}/agents/ {FRAMEWORK_PATH}/templates/`

### 1d. Gather Project Configuration

Ask for:
- **Project name** (e.g., "my-project")
- **Namespace prefix** (e.g., "PROJ", "AUTH") — used for ticket IDs and branch names
- **Tracker type** (jira / github / linear / tiles / none)
- **Tracker URL** (if jira or tiles)

Store all values.

### 1e. Check Existing State

```bash
ls {TARGET_PROJECT}/CLAUDE.md {TARGET_PROJECT}/AGENTS.md {TARGET_PROJECT}/.claude/settings.json 2>/dev/null
ls -d {TARGET_PROJECT}/.claude/skills {TARGET_PROJECT}/.claude/agents 2>/dev/null
```

Note which files/directories already exist.

### 1f. Ask Standards Location

```
Where should I place coding standards?

1. docs/ai-rules (Recommended - AI/agent-specific, tool-agnostic)
2. docs/coding-standards (Generic engineering standards)
3. .cursor/rules (Cursor IDE location)
4. .claude/rules (Claude Code location)
5. Custom path

Your choice?
```

Store as `STANDARDS_DIR`.

### 1g. Pre-Detection

```bash
ls {TARGET_PROJECT}/build.gradle {TARGET_PROJECT}/build.gradle.kts {TARGET_PROJECT}/pom.xml {TARGET_PROJECT}/package.json {TARGET_PROJECT}/Podfile {TARGET_PROJECT}/Cargo.toml {TARGET_PROJECT}/pyproject.toml {TARGET_PROJECT}/go.mod 2>/dev/null
```

Detect build system signals for stack identification.

## Phase 2: Bootstrap (Greenfield Only)

**Skip if** the target already has coding rules, AI files, or `.claude/skills/`.

This phase deep-reads the project and generates project-aligned coding rules.

### 2a. Run `claude init` (if no CLAUDE.md)

```bash
cd {TARGET_PROJECT} && claude init
```

### 2b. Deep-Read and Generate Rules

Analyze the target project:
- Build files, dependencies, plugins
- Source directory structure, package organization
- 5-10 representative source files for coding patterns
- Test infrastructure (framework, naming conventions)
- API patterns, database access, error handling

Generate rules in `{TARGET_PROJECT}/{STANDARDS_DIR}/` that reflect actual project patterns:

**Always generate:**
- `project-conventions.md` — Naming, structure, style conventions observed

**Generate if evidence found:**
- `api-patterns.md` — REST/GraphQL/gRPC endpoint patterns
- `database-patterns.md` — Query patterns, transaction boundaries, migrations
- `testing-patterns.md` — Test naming, mocking approach, assertion style
- `error-handling.md` — Exception hierarchy, error codes, retry patterns

Keep rules concise and cite specific files from the codebase as examples.

## Phase 3: Research (Stack Detection)

Detect the target project's complete technology stack:

1. Read build files, dependency manifests, imports, directory structure
2. Read the framework source files from `{FRAMEWORK_PATH}/skills/`, `agents/`, `templates/`
3. For each framework file, identify platform-specific elements (commands, file extensions, directory paths, code patterns)
4. Build a mapping of what needs adaptation

**Present to user:**
```
Detected your project stack:
- Language: {detected}
- Framework: {detected}
- Build Tool: {detected}
- Database: {detected or "None"}

Is this correct? (y/n)
```

## Phase 4: Install

### 4a. Copy Framework Components

Install in this order:

1. **Skills**: Copy `{FRAMEWORK_PATH}/skills/*/SKILL.md` → `{TARGET_PROJECT}/.claude/skills/`
   - Adapt platform-specific references using detected stack
2. **Agents**: Copy `{FRAMEWORK_PATH}/agents/*/AGENT.md` → `{TARGET_PROJECT}/.claude/agents/`
3. **Rules**: Install universal rules to `{STANDARDS_DIR}/`
   - If bootstrap rules were generated, preserve them alongside framework rules
4. **Templates**: Copy PR and commit templates
   - Detect existing PR template first; merge if found
5. **Settings**: Create `.claude/settings.json` with appropriate permissions
6. **.gitignore**: Add `.claude/skill.config` and `.claude/reviews/`

### 4b. Create Configuration Files

**config_hints.json** (committed to git):
```json
{
  "project": {
    "namespace": "{NAMESPACE}",
    "name": "{PROJECT_NAME}"
  },
  "platform": "{DETECTED_PLATFORM}",
  "standards_location": "{STANDARDS_DIR}",
  "tracker": {
    "type": "{TRACKER_TYPE}",
    "url": "{TRACKER_URL if applicable}"
  },
  "framework_version": "{FRAMEWORK_VERSION}"
}
```

**AGENTS.md** — Generate with:
- Build commands from detected stack
- Project structure summary
- List of installed skills, agents, and rules
- Saved CLAUDE.md content (merged if it existed)

**CLAUDE.md** — Standard pointer:
```markdown
@AGENTS.md
```

## Phase 5: Verify

Scan every installed file for:
- Unreplaced placeholders: `{project}`, `{namespace}`, `{platform}`, `{STANDARDS_DIR}`
- Foreign-stack references (e.g., Java references in a Python project)
- Rule file references pointing to files that don't exist

**If issues found**: fix them, then re-verify. Repeat until clean.

## Phase 6: Summary

```
Task Flow installed for {PROJECT_NAME}!

What was set up:
- Skills: {count} skills installed
- Agents: {count} agents installed
- Rules: {count} framework rules
  {if bootstrap: + {count} project-specific rules generated}
- Config: .claude/config_hints.json
- AGENTS.md: Single source of truth
- CLAUDE.md: Points to @AGENTS.md
- Verification: PASS

Next steps:

1. Configure your local paths:
   > task-flow-setup:init-skills

2. Start your first task:
   > task-flow
```

### Cleanup

Delete any temporary files created during installation.

### Optional: Run AI Sanitizer

```
Would you like to run AI Sanitizer to optimize the installed files? (y/n)
```

If yes, user should open a new Claude session in the target project and say `task-flow-tool:optimize-ai-setup`.
