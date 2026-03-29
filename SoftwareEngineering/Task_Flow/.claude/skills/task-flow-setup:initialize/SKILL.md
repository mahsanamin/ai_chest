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

**CRITICAL: Use AskUserQuestion with ONLY a text field. Do NOT use selectable options, menus, numbered lists, or suggestions of any kind.**

Ask exactly this — one plain text question, nothing else:

```
What is the full path to your target project?
```

- **NEVER** pass `options` or `choices` to AskUserQuestion — use it in plain text-input mode only
- **NEVER** list directories, suggest paths, or show examples
- Just ask and wait for the user to type the full path

Validate the directory exists. Store as `TARGET_PROJECT`.

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

## Phase 3b: Match Rule Templates

**After stack detection, check if AIRuleTemplates exist as a sibling directory to Task_Flow.**

AIRuleTemplates lives alongside Task_Flow in the repo, NOT inside it:
```
SoftwareEngineering/
├── AIRuleTemplates/    ← rule templates
├── Task_Flow/          ← this framework (FRAMEWORK_PATH)
└── ...
```

Resolve the path:
```bash
# FRAMEWORK_PATH is the Task_Flow root. AIRuleTemplates is a sibling.
REPO_ROOT=$(cd {FRAMEWORK_PATH}/.. && pwd)
TEMPLATES_PATH="$REPO_ROOT/AIRuleTemplates"
ls "$TEMPLATES_PATH/README.md" 2>/dev/null
```

If found, intelligently select templates that match the detected stack:

### Template Matching Logic

**Always include:**
- `AIRuleTemplates/universal/` → ALL projects get these (critical-thinking.md, code-review.md)

**Match by detected stack:**

| Detected Stack | Template Directories |
|---------------|---------------------|
| Any backend (Java, Python, Go, Node.js, etc.) | `universal/` + `backend/` |
| Java + Spring Boot | `universal/` + `backend/` + `java-spring-boot/` |
| React + TypeScript | `universal/` + `react-typescript/` |
| Next.js | `universal/` + `react-typescript/` + `nextjs/` |
| Python + Django/Flask | `universal/` + `backend/` |
| Go | `universal/` + `backend/` |
| Node.js + Express | `universal/` + `backend/` |

**Detection signals:**

| Signal | Indicates |
|--------|-----------|
| `build.gradle`, `pom.xml` with Spring dependencies | Java + Spring Boot |
| `package.json` with `react` dependency | React + TypeScript |
| `package.json` with `next` dependency | Next.js |
| `pyproject.toml`, `requirements.txt` with Django/Flask | Python backend |
| `go.mod` | Go backend |
| Any backend language + SQL/ORM dependencies | Backend templates apply |

### Present template selection to user

```
Based on your stack ({detected}), these rule templates match:

✅ universal/critical-thinking.md — Challenge assumptions (always applied)
✅ universal/code-review.md — Review criteria
✅ backend/query-efficiency.md — N+1 prevention, batch loading
✅ backend/transaction-boundaries.md — Keep transactions short
✅ backend/database-migrations.md — Migration patterns
✅ backend/api-conventions.md — REST API validation & security
✅ java-spring-boot/jpa-repositories.md — JPA patterns
✅ java-spring-boot/coding-conventions.md — Java/Spring conventions

Install these templates to {STANDARDS_DIR}/? (y/n/customize)
```

- **y** → Install all matched templates
- **n** → Skip templates entirely
- **customize** → Let user pick which ones to include

### Install matched templates

Copy each selected template to `{TARGET_PROJECT}/{STANDARDS_DIR}/`:

```bash
cp "$TEMPLATES_PATH/universal/"*.md {TARGET_PROJECT}/{STANDARDS_DIR}/
cp "$TEMPLATES_PATH/backend/"*.md {TARGET_PROJECT}/{STANDARDS_DIR}/
# ... etc based on matched directories
```

**If bootstrap rules from Phase 2 exist**, keep both — bootstrap rules contain project-specific patterns, templates contain general best practices. They complement each other.

**Track what was installed** — store the list of template files for the summary in Phase 6.

## Phase 4: Install

### 4a. Copy Framework Components

Install in this order:

1. **Skills**: Install skills based on scope:
   - **Project skills** (`task-flow-*` without `tool:` prefix): Copy `{FRAMEWORK_PATH}/skills/task-flow-*/SKILL.md` → `{TARGET_PROJECT}/.claude/skills/`
   - **Global tools** (`task-flow-tool:*` prefix): Copy `{FRAMEWORK_PATH}/skills/task-flow-tool:*/SKILL.md` → `~/.claude/skills/` (user-level, shared across all projects)
   - Adapt platform-specific references using detected stack
2. **Agents**: Copy `{FRAMEWORK_PATH}/agents/*/AGENT.md` → `{TARGET_PROJECT}/.claude/agents/`
3. **Rules**: Rule templates were already installed in Phase 3b. Install any additional universal rules here.
   - If bootstrap rules were generated, preserve them alongside templates
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
- Rule templates: {count} from AIRuleTemplates ({list of directories matched})
  {if bootstrap: + {count} project-specific rules generated from codebase analysis}
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
