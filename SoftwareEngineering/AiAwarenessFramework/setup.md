> **STOP — Do not execute this file directly.**
>
> This file is a **procedures reference**, not a runnable script.
>
> - **Fresh install:** Use the `aa-install` skill - say `aa-install at /path/to/project`
> - **Update existing:** Use the `aa-upgrade` skill - say `aa-upgrade at /path/to/project`
> - **Framework development:** Use the `aa-add-improvement` skill
>
> The procedures below are referenced by these skills and should not be run independently.

# AI Awareness Setup Procedures Reference

This document defines reusable procedures referenced by the `aa-install` and `aa-upgrade` skills. It is not intended to be executed directly. See the redirect block above for how to install or update.

**Formatting rules for ALL generated files (AGENTS.md, CLAUDE.md, config files, rule files, etc.):**
- No extra blank lines between sections — one blank line max
- No horizontal rules (`---`) unless explicitly shown in a template
- No trailing whitespace
- No decorative separators or padding
- Keep files compact and scannable — no fluff

## Content Adaptation Pipeline

Agents that adapt framework source files to a target project's stack. Used by both `aa-install` and `aa-upgrade` skills.

**Design for context efficiency:** Each agent receives only the files and information it needs. All shared state passes through files on disk (`_install_config.json`, `_stack_mapping.md`), never through conversation context. Writer agents are split by concern so each one holds a small, focused context.

### File-Based Handoffs

The orchestrating skill (main session) and all agents communicate through temporary files in the target project root. These are deleted after installation completes.

**`_install_config.json`** — Written by Phase 1 (main session). Contains all gathered configuration:
```json
{
  "target_project": "/path/to/project",
  "framework_path": "/path/to/ai-awareness-framework",
  "project_name": "User Service",
  "tracker": { "type": "github", "url": "" },
  "namespace": "SVC",
  "namespaces": null,
  "standards_dir": "docs/ai-rules",
  "existing_state": {
    "claude_md": true,
    "agents_md": false,
    "skills_dir": false,
    "agents_dir": false,
    "settings": false,
    "rules_dirs": []
  },
  "saved_claude_md_content": "...",
  "saved_ai_files_content": {},
  "mode": "fresh",
  "applicable_rule_dirs": ["universal", "java-spring-boot"]
}
```

**`_stack_mapping.md`** — Written by the Stack Analyzer. The contract for all writer agents (see Stack Analyzer output format below).

**`_install_manifest.json`** — Written by each writer agent, merged by the orchestrator. Lists every file written/modified:
```json
{
  "files_written": [
    { "path": ".claude/skills/aa-task-flow/SKILL.md", "action": "created", "source": "skills/aa-task-flow/SKILL.md" },
    { "path": "docs/ai-rules/critical-thinking.md", "action": "adapted", "source": "rules/universal/critical-thinking.md" }
  ]
}
```

### Pre-Detection (Run by Main Session)

Before launching the Stack Analyzer, the main session runs a lightweight platform pre-detection to narrow which framework files the Stack Analyzer needs to read. This prevents the Stack Analyzer from reading ~340KB of irrelevant rule files.

> **🛑 Language ≠ stack.** A build tool or language alone never selects a stack rule set. `java-spring-boot` requires **positive Spring evidence**, not merely a `build.gradle` (Android uses Gradle + Java/Kotlin but is NOT Spring). When no curated stack matches, use **`["universal"]`** — never the nearest language cousin.

```bash
cd {target_project}

# Stack detection by POSITIVE evidence, most-specific first (not language-alone).
STACK="generic"
if [ -f "AndroidManifest.xml" ] || grep -rqsE 'com\.android\.(application|library)' build.gradle build.gradle.kts settings.gradle settings.gradle.kts 2>/dev/null; then
  STACK="android"                       # Java/Kotlin, but NOT Spring
elif ls *.xcodeproj >/dev/null 2>&1 || [ -f "Podfile" ] || [ -f "Package.swift" ]; then
  STACK="ios"
elif grep -rqs "spring-boot" pom.xml build.gradle build.gradle.kts 2>/dev/null \
     || grep -rqsE 'import org\.springframework|@SpringBootApplication' . --include='*.java' --include='*.kt' 2>/dev/null; then
  STACK="java-spring-boot"              # positive Spring evidence
elif [ -f "go.mod" ]; then STACK="go"
elif [ -f "Gemfile" ]; then STACK="ruby"
elif [ -f "Cargo.toml" ]; then STACK="rust"
elif [ -f "pyproject.toml" ] || [ -f "setup.py" ] || [ -f "requirements.txt" ]; then STACK="python"
elif [ -f "package.json" ] && grep -qs '"react"' package.json; then STACK="react"
elif [ -f "package.json" ]; then STACK="node"
elif [ -f "pom.xml" ] || [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then STACK="jvm-generic"  # Java/Kotlin, no Spring
fi
echo "DETECTED_STACK=$STACK"
```

Map `STACK` → `applicable_rule_dirs` in `_install_config.json` (**only map to a stack dir that actually exists under `rules/`; otherwise universal-only — genericize, never borrow**):
- `java-spring-boot` → `["universal", "java-spring-boot"]`
- `react` → `["universal", "react"]`
- `android`, `ios`, `go`, `ruby`, `rust`, `python`, `node`, `jvm-generic`, `generic` → `["universal", "_generic"]` (no curated per-stack set yet → universal + the language-neutral `_generic` fallback; the Stack Analyzer may author project rules from the actual code, but must NOT pull in another stack's set). As `rules/<stack>/` sets are authored (via the `aa-add-improvement` tier on-ramp), add the matching dir here.

This is a **hint**, not a final decision — but the Stack Analyzer may only **narrow or genericize** it, never substitute a different language's stack rules.

### Stack Analyzer (Research)

**Purpose:** Analyze the target project's stack and produce `_stack_mapping.md`.

**Context budget:** Target project files + applicable framework files only. Does NOT read the full setup.md.

**Inputs:**
- `_install_config.json` (for target path, applicable_rule_dirs hint)
- Framework source files: `skills/`, `agents/`, `templates/`, `settings.json`, and ONLY the rule directories listed in `applicable_rule_dirs`
- For updates: CHANGELOG entries listing what changed since PROJECT_VERSION

**Process:**

1. **Detect technology stack** — Do NOT use a hardcoded platform list. Read the target project's actual files to detect whatever is present:

```bash
# Read build/dependency files
ls -la build.gradle build.gradle.kts pom.xml package.json Podfile \
      Makefile Cargo.toml pyproject.toml go.mod settings.gradle \
      settings.gradle.kts *.xcodeproj 2>/dev/null

# Read dependency declarations for framework detection
cat build.gradle 2>/dev/null | head -100
cat build.gradle.kts 2>/dev/null | head -100
cat package.json 2>/dev/null | head -50
cat pom.xml 2>/dev/null | head -100

# Detect frameworks from imports/code
grep -r "import org.springframework" src/ --include="*.java" --include="*.kt" -l 2>/dev/null | head -5
grep -r "from 'react'\|from \"react\"" src/ --include="*.tsx" --include="*.jsx" -l 2>/dev/null | head -5
grep -r "import SwiftUI\|import UIKit" . --include="*.swift" -l 2>/dev/null | head -5
grep -r "import android\." . --include="*.kt" --include="*.java" -l 2>/dev/null | head -5

# Detect test framework
grep -r "import org.junit\|import org.mockito\|@SpringBootTest" src/ --include="*.java" --include="*.kt" -l 2>/dev/null | head -3
grep -r "vitest\|jest\|testing-library\|mocha" package.json 2>/dev/null

# Detect database layer (generalized — not limited to specific tools)
find . -name "*.sql" -path "*/migration*" 2>/dev/null | head -10
find . -name "*.sql" -path "*/migrations/*" 2>/dev/null | head -10
grep -r "@Entity\|@Table" src/ --include="*.java" --include="*.kt" -l 2>/dev/null | head -5
grep -r "mongoose\|sequelize\|typeorm\|prisma\|drizzle" . --include="*.ts" --include="*.js" -l 2>/dev/null | head -5
ls -la alembic.ini 2>/dev/null
find . -name "*.py" -path "*/migrations/*" 2>/dev/null | head -5

# Detect directory structure and package layout
find src/main/java -type d -maxdepth 5 2>/dev/null | head -20
find src -type d -maxdepth 3 2>/dev/null | head -20

# Read existing installed rules and config
ls .claude/rules/*.md 2>/dev/null
cat .claude/config_hints.json 2>/dev/null
```

2. **Validate pre-detection hint** — If the Stack Analyzer discovers the actual stack differs from `applicable_rule_dirs` (e.g., pre-detection said Java but the project is actually Kotlin Multiplatform with React), update the applicable rules accordingly and note the correction.

3. **Read applicable framework source files** — Read ONLY the framework files that will actually be installed (skills, agents, rules from applicable directories, templates). For each file, identify platform-specific elements:
   - Commands (e.g., `./gradlew`, `mvn`, `npm run`)
   - File extensions (e.g., `.java`, `.kt`, `.tsx`, `.swift`)
   - Directory paths (e.g., `src/main/java/`, `module-migrator/`)
   - Code patterns and annotations (e.g., `@Entity`, `@SpringBootTest`)
   - Grep expressions used in rules
   - Output format references
   - Rule file references (e.g., `database-migrations.md`, `jpa-repositories.md`)
   - Project name and namespace placeholders (`{project}`, `{namespace}`)

4. **Write `_stack_mapping.md`** to the target project root — this is the contract for all downstream agents:

```markdown
# Stack Mapping

## Target Project Stack
- **Language:** {detected language and version}
- **Framework:** {detected framework}
- **Build Tool:** {detected build tool and wrapper}
- **ORM:** {detected ORM or "None"}
- **Migration Tool:** {detected migration tool or "None"}
- **Test Framework:** {detected test framework}
- **Database:** {detected database or "None"}
- **Base Package:** {detected base package, e.g., com.example.userservice}
- **Migration Path:** {detected migration directory or "N/A"}
- **Build Command (setup):** {e.g., ./gradlew build}
- **Build Command (compile):** {e.g., ./gradlew build -x test}
- **Test Command:** {e.g., ./gradlew test --rerun-tasks}
- **Run Command:** {e.g., ./gradlew bootRun}

## Applicable Framework Rules
| Rule Directory | Applies? | Reason |
|---|---|---|
| universal/ | Yes | Always applies |
| java-spring-boot/ | {Yes/No} | {Evidence from detection} |
| react/ | {Yes/No} | {Evidence from detection} |

## Element Mapping
| Framework Element | Target Equivalent | Source File(s) | Action |
|---|---|---|---|
| `com.example.{project}` | `com.example.userservice` | project-structure.md | Replace |
| `./gradlew` | `./gradlew` | AGENTS.md template | Keep |
| `module-migrator/src/main/resources/db/migration/` | `src/main/resources/db/migration/` | database-migrations.md | Replace |
| React-specific patterns | N/A | react rules | Remove (not applicable) |
| `{project}` placeholder | `User Service` | config_hints.json, AGENTS.md | Replace |
| `{namespace}` placeholder | `SVC` | config_hints.json, skills | Replace |

## Not Applicable Elements
{List framework elements that have no equivalent in the target project and should be removed or skipped}

## Project Structure Summary
{Brief description of modules, key directories, and package layout — used by the Config Writer for AGENTS.md generation}
```

### Writer Agents

The writer phase is split into focused writer agents, each handling one concern with a small context. The orchestrating skill launches them in the order shown below. **Structure Writer, Rules Writer, and ERD Writer are independent and run in parallel.** Config Writer runs after Structure Writer and Rules Writer complete because it needs to know what was installed.

#### Structure Writer

**Purpose:** Install skills, agents, settings, templates, and .gitignore entries.

**Context:** Reads `_install_config.json` + `_stack_mapping.md` + framework `skills/`, `agents/`, `templates/`, `settings.json`. Does NOT read setup.md or rules.

**Procedure references:** Steps 6 (Skills), 7 (Settings), 11 (Agents), 13 (Templates), 15 (.gitignore) from this document.

**Note:** Step 6r (Resolve standards-path tokens) is NOT run inside this writer — it runs once in the main session AFTER both skills (Step 6) and agents (Step 11) are on disk, alongside the Step 16b guardrail. See Step 6r.

**Process (fresh):**
1. Copy all framework skills to `.claude/skills/` — apply element mapping for any platform-specific references
2. Copy `settings.json` to `.claude/` — remove allow entries irrelevant to the project's platform per mapping
3. Copy all framework agents to `.claude/agents/`
4. Handle PR template (detect existing or copy default) and commit template
5. Add `.claude/skill.config` and `.claude/settings.local.json` to `.gitignore`

**Process (update):**
1. Only process files from CHANGED_FILES list
2. For each existing file, use Smart Diff categories (see "Smart Diff" section below) to merge
3. Preserve project-custom skills/agents

**Output:** Append to `_install_manifest.json` with all files written.

#### Rules Writer

**Purpose:** Install and adapt coding standards (universal + platform-specific rules).

**Context:** Reads `_install_config.json` + `_stack_mapping.md` + framework `rules/` (only applicable directories). Does NOT read setup.md skills or agents.

**Procedure references:** Steps 8 (Coding Standards), 8a (Migration), 8b-rename (Renamed files), 8c (Merge), 8d (Cleanup), 9 (Platform-Specific Rules) from this document.

**Process (fresh):**
1. If existing rules need migration (from `_install_config.json` existing_state), migrate per Step 8a
2. Handle renamed files per Step 8b-rename table
3. Install universal rules to `{STANDARDS_DIR}/`
4. Install platform-specific rules based on mapping's "Applicable Framework Rules" table
5. Apply element mapping to adapt all rules (package names, directory paths, commands, entity names)
6. Handle `project-structure.md` special translation (detect actual packages, replace placeholders)

**Process (update):**
1. Only process rule files from CHANGED_FILES list
2. For each existing rule, use Smart Diff to categorize differences and merge intelligently
3. Preserve project-custom rules

**Output:** Append to `_install_manifest.json` with all files written.

#### Config Writer

**Purpose:** Create `config_hints.json`, `AGENTS.md`, and finalize `CLAUDE.md`. Runs AFTER Structure Writer and Rules Writer complete.

**Context:** Reads `_install_config.json` + `_stack_mapping.md` + `_install_manifest.json` (to know what was installed). Does NOT read framework source files.

**Procedure references:** Steps 5 (CLAUDE.md finalization), 10 (config_hints.json), 12 (AGENTS.md) from this document.

**Process:**
1. Create `.claude/config_hints.json` using gathered configuration from `_install_config.json` (project name, namespace(s), standards_dir, platform from mapping)
2. Generate `AGENTS.md` using:
   - Build commands from `_stack_mapping.md` (setup, build, test, run)
   - Project structure summary from `_stack_mapping.md`
   - List of installed skills/agents/rules from `_install_manifest.json`
   - Saved CLAUDE.md/AI file content from `_install_config.json` (if any)
   - Follow Step 12 templates and scanner compatibility rules
3. Finalize `CLAUDE.md` — write the standard `@AGENTS.md` content per Step 5

**Output:** Append to `_install_manifest.json`.

#### ERD Writer (Conditional)

**Purpose:** Generate ERD documentation if a database layer was detected.

**Context:** Reads `_install_config.json` + `_stack_mapping.md` (database section only) + actual migration/entity files in target project. Does NOT read framework source files.

**Procedure reference:** Step 14 (Generate ERD Documentation) from this document.

**Skip condition:** If `_stack_mapping.md` shows Database as "None" and Migration Tool as "None", do not launch this agent.

**Process:**
1. Read migration files and/or entity files detected by the Stack Analyzer (paths from mapping)
2. Generate `docs/erd.md` with Mermaid diagram, table definitions, relationships, migration history
3. Update `_install_manifest.json`

**Output:** Append to `_install_manifest.json`.

### Contamination Checker (Verification)

**Purpose:** Independently verify that no foreign-stack references contaminate installed files.

**CRITICAL:** This agent MUST run in a clean context. It receives NO conversation history from any writer agent and does NOT read `_stack_mapping.md`. It independently re-detects the target stack.

**Inputs (provided via a fresh Task invocation):**
- Target project path
- `_install_manifest.json` (list of files to check)

**Process:**

1. **Independently detect target stack** — Run the same detection approach as the Stack Analyzer (read build files, scan imports, detect frameworks). Form your own understanding of what this project is.

2. **Scan every installed file** for foreign-stack contamination:

```bash
# Check for unreplaced placeholders.
# NOTE: {platform} is intentionally NOT checked here — it is a RUNTIME token (the platform of
# the current work), resolved by skills at execution time: aa-init-skills resolves it from the
# user's interactive platform selection, aa-task-flow from the task context. It must be LEFT
# INTACT in installed skills, never resolved at install time — hardcoding one platform breaks
# the skills' own platform-handling logic (e.g. aa-init-skills' platform-selection menu).
grep -rn "{project}\|{namespace}\|{STANDARDS_DIR}\|com\.example\.\{" {installed_files}

# If target is NOT a Java/Spring Boot project, check for Java references
grep -rn "import org.springframework\|@Entity\|@Repository\|JPA\|Hibernate\|Flyway\|\.java\b\|gradlew\|build\.gradle" {installed_files}

# If target is NOT a React project, check for React references
grep -rn "from 'react'\|useState\|useEffect\|\.tsx\b\|vitest\|tailwind" {installed_files}

# If target is NOT a Gradle project but files reference Gradle
grep -rn "gradlew\|build\.gradle\|settings\.gradle" {installed_files}

# If target is NOT a Maven project but files reference Maven
grep -rn "mvn \|pom\.xml\|maven" {installed_files}
```

3. **Check rule file references** — For every rule file referenced inside any installed file (e.g., "see `database-migrations.md`"), verify that file actually exists in the target project's standards directory.

4. **Report findings:**

```markdown
# Verification Report

## Stack Detected
{Independent stack detection results}

## Files Scanned: {N}

## Contamination Found

### Foreign-Stack References
| File | Line | Reference | Expected Stack |
|---|---|---|---|
| {file} | {line} | {foreign reference} | {what it should be or "remove"} |

### Unreplaced Placeholders
| File | Line | Placeholder |
|---|---|---|
| {file} | {line} | {placeholder} |

### Missing Rule File References
| Referencing File | Line | Referenced Rule | Exists? |
|---|---|---|---|
| {file} | {line} | {rule-file.md} | No |

## Verdict: PASS / FAIL
```

5. **If FAIL:** Return the contamination report. The orchestrating skill routes it to the appropriate writer agent for fixes, then re-runs verification as a fresh Task. Repeat until PASS.

### Cleanup

After the skill completes (success or failure), delete temporary handoff files:
```bash
rm -f {target_project}/_install_config.json
rm -f {target_project}/_stack_mapping.md
rm -f {target_project}/_install_manifest.json
```

## Step 1: Validate Prerequisites

### 1a. Check GitHub CLI (gh)

```bash
command -v gh >/dev/null 2>&1 && echo "GH_EXISTS" || echo "GH_MISSING"
```

**If `gh` is missing:**
```
GitHub CLI (gh) is not installed. It's needed for:
- Creating pull requests (aa-pr skill)
- Viewing PR checks and comments
- Jira/GitHub workflow integration

Install it now:

  macOS:    brew install gh
  Ubuntu:   sudo apt install gh
  Windows:  winget install GitHub.cli

After installing, authenticate:
  gh auth login

Want me to wait while you install it? (y/n)
```

If yes, wait and re-check. If no, continue (skills that need `gh` will warn at runtime).

**If `gh` exists, check auth:**
```bash
gh auth status 2>&1 | grep -q "Logged in" && echo "GH_AUTHED" || echo "GH_NOT_AUTHED"
```

If not authenticated:
```
gh is installed but not logged in. Run:
  gh auth login

Want me to wait? (y/n)
```

### 1b. Validate Framework

Check this directory contains:
- `config_hints.json` with `framework_version` (canonical version source)
- `skills/` with workflow skills
- `rules/universal/` with universal rules
- `rules/java-spring-boot/` with Java Spring Boot patterns (if applicable)
- `rules/react/` with React SPA patterns (if applicable)
- `settings.json` for Claude permissions

```bash
# Read the canonical framework version from framework's config_hints.json
FRAMEWORK_VERSION=$(grep '"framework_version"' {framework_path}/config_hints.json | sed 's/.*: *"\(.*\)".*/\1/' | tr -d '[:space:]')
echo "Framework version: $FRAMEWORK_VERSION"
```

Store `FRAMEWORK_VERSION` — this is used throughout setup and written to the target project's `config_hints.json`.

### 1c. Install Global Skills

```bash
# Create global skills directory if it doesn't exist
mkdir -p ~/.claude/skills

# Copy global-only skills to global location
cp -r {framework_path}/skills/aa-optimizer ~/.claude/skills/
cp -r {framework_path}/skills/aa-record-improvement ~/.claude/skills/

echo "✓ Global skills installed at ~/.claude/skills/ (aa-optimizer, aa-record-improvement)"
```

### 1d. Install Framework Scripts (Global)

```bash
# Copy framework scripts to global location
mkdir -p ~/.claude/scripts
cp -r {framework_path}/scripts/* ~/.claude/scripts/

# Ensure scripts are executable
find ~/.claude/scripts -name "*.sh" -exec chmod +x {} \;

echo "✓ Framework scripts installed globally at ~/.claude/scripts/"
```

This installs shared scripts (e.g., SonarQube issue fetcher) to `~/.claude/scripts/` so they're available system-wide. Skills in target projects reference these scripts at runtime.

## Step 2: Ask for Target Project

Ask user:
```
What is the path to your project?
Example: ~/repos/your-service
```

Validate directory exists and is a valid project.

## Step 3: Gather Project Configuration

**Ask user for project-specific information:**

```
I need some information about your project to configure the framework correctly.

1. What is your project name?
   Examples: Example, User Service, Products API, Items Backend, the Android app

   Project name:

2. Which issue tracker does your project use?

   a) GitHub Issues (default — uses the `gh` CLI; the repo is the scope, no "spaces")
   b) Jira (Atlassian)
   c) Linear
   d) None (work is described directly in prompts; identifiers managed manually)
```

Store the choice as the `tracker` block in `config_hints.json` (Step 10): `github` →
`{ "type": "github", "url": "" }` (default), `jira` →
`{ "type": "jira", "url": "your-org.atlassian.net" }`, `linear` →
`{ "type": "linear", "url": "..." }`, `none` → `{ "type": "none", "url": "" }`.

**If GitHub Issues / Linear / None:** there are no Jira "spaces". Ask only for a single
project namespace (used as a ticket/branch prefix):
```
What is your project namespace (used for ticket/branch prefixes)?
Examples: PROJ (Example Project), SVC (User Service), API (Products), WEB (Items)

Project namespace:
```
Store as a single namespace in `config_hints.json` (Step 10). For Jira, ask whether the
team works across one or multiple Jira spaces:
```
Does your project work with multiple Jira spaces?
   Some teams (e.g., Mobile) work across multiple Jira projects
   with different ticket prefixes (CORE-XXX, DATA-XXX, OPS-XXX, MOBILE-XXX).

   a) Single Jira space
   b) Multiple Jira spaces
```

**If single Jira space:** ask for the project namespace (same prompt as above) and store
it as a single namespace in `config_hints.json` (Step 10).

**If multiple Jira spaces:**
```
List all Jira spaces your team works with (prefix + description):
Example:
  CORE  => Core Service
  DATA  => Items Meta
  OPS     => Growth Team
  MOBILE => Mobile Platform

Your Jira spaces:
```

After collecting, inform the user:
```
Since your project spans multiple Jira spaces, you'll need to mention
the project alias (e.g., CORE, OPS) in your raw prompt when starting
a task so the AI can create correct branch names and Jira links.

Example raw prompts:
  "CORE-123: Fix product search sorting"
  "OPS-456: Add deep link tracking for growth campaign"
  "MOBILE-789: Upgrade Kotlin to 2.0"

The ticket prefix in your prompt tells aa-task-flow which Jira space to use
for branch naming (feature/core-123-fix-product-search) and Jira links.
```

Store all namespaces in `config_hints.json` (Step 10) — the first namespace listed becomes the `default_namespace`.

**Store this configuration** - it will be saved to `config_hints.json` in Step 10.

**Note:** The tracker defaults to `github` (`{ "type": "github", "url": "" }`). `url` is
only meaningful for `jira` (e.g. `your-org.atlassian.net`) / `linear`.

**Note:** This configuration makes the framework adapt to YOUR project. Skills detect the namespace from the ticket ID in your prompt at runtime, so no manual switching is needed.

## Step 4: Check Existing State

### 4a. Check Existing Files

```bash
cd {target_project}
[ -f "CLAUDE.md" ] && echo "CLAUDE_EXISTS"
[ -f "AGENTS.md" ] && echo "AGENTS_EXISTS"
[ -d ".claude/skills" ] && echo "SKILLS_EXIST"
[ -d ".claude/agents" ] && echo "AGENTS_DIR_EXIST"
[ -f ".claude/settings.json" ] && echo "SETTINGS_EXIST"
[ -f ".claude/config_hints.json" ] && echo "CONFIG_EXISTS"
# Check for existing coding standards in common locations
for dir in docs/ai-rules docs/coding-standards .cursor/rules .claude/rules .aiRules; do
  [ -d "$dir" ] && echo "RULES_EXIST: $dir"
done
```

### 4b. Version Check (Existing Installs)

If `config_hints.json` exists, compare versions to determine if this is a fresh install or an update:

```bash
if [ -f ".claude/config_hints.json" ]; then
  PROJECT_VERSION=$(grep '"framework_version"' .claude/config_hints.json | sed 's/.*: *"\(.*\)".*/\1/')
  echo "Project version: $PROJECT_VERSION"
  echo "Framework version: $FRAMEWORK_VERSION"

  if [ "$PROJECT_VERSION" = "$FRAMEWORK_VERSION" ]; then
    echo "VERSION_MATCH"
  else
    echo "VERSION_MISMATCH"
  fi
fi
```

**If VERSION_MATCH (project is already at current framework version):**

The project is up to date. However, files may have drifted since installation. Run an intelligent diff to detect any framework updates the project is missing:

```
Your project is already at AI Awareness v{FRAMEWORK_VERSION}.

Let me check if any framework source files have been updated since your last install...
```

Run the **Smart Diff** (see below) to identify differences. If no actionable differences found, report "Project is fully up to date" and exit. If differences found, present them to the user with recommendations.

**If VERSION_MISMATCH (project needs updating):**
```
Your project is at AI Awareness v{PROJECT_VERSION}.
Framework is at v{FRAMEWORK_VERSION}.

Let me analyze what needs updating...
```

1. Read `CHANGELOG.md` from framework directory
2. Identify all entries after `v{PROJECT_VERSION}`
3. Present a summary of changes to apply
4. Run the **Smart Diff** to plan the update
5. Apply changes with intelligent merging
6. Update `config_hints.json` → `framework_version` to `FRAMEWORK_VERSION`
7. Update `AGENTS.md` footer version

**If NO config_hints.json (fresh install):**

Continue with Step 5 as a fresh install.

### Smart Diff — Intelligent File Comparison

For each framework file, compare against the installed version in the target project. **Categorize** each difference:

| Category | Description | Action |
|----------|-------------|--------|
| **Custom Addition** | File exists in project but NOT in framework (e.g., a project's own `{project}-code-reviewer/` agent or a domain rule like `payments-api.md`) | NEVER touch — this is the project's own content |
| **Intentional Override** | File exists in both but project deliberately changed behavior (e.g., removed Co-Authored-By, different commit style) | PRESERVE — ask user before reverting |
| **Project-Specific Values** | Framework uses generic placeholders (`{project}`, `com.example.{project}`), project has real values (`wps`, `com.example.app`) | PRESERVE — never replace with generic placeholders |
| **Formatting Preference** | Structural/cosmetic differences (e.g., `---` separators, section ordering) | PRESERVE — these don't affect behavior |
| **Missing Framework Update** | Framework added new content (e.g., YAML frontmatter, new section, new guardrail) that project doesn't have | ADD — merge into project file without disturbing existing content |
| **Outdated Content** | Framework fixed a bug or corrected an error that project still has | UPDATE — apply the fix, preserving project customizations around it |

**How to diff:**

1. Read the target project's `config_hints.json` to get `platform` and `standards_location`
2. For each file category (skills, agents, rules, settings, templates):
   a. List files in BOTH framework source and target project
   b. Identify which files exist in both, which are framework-only, which are project-only
   c. For files that exist in both, diff content and categorize each difference
3. **Only apply "Missing Framework Update" and "Outdated Content" changes**
4. For anything that looks like an intentional override, ask:
   ```
   I noticed your project differs from the framework in {file}:
   - Framework: {brief description of framework version}
   - Your project: {brief description of project version}

   This looks like a deliberate project choice. Keep your version? (y/n)
   ```

**Platform awareness during diff:**
- Read `config_hints.json` → `platform` to know the project type
- Only compare rules relevant to the project's platform:
  - Backend → universal + java-spring-boot rules
  - Frontend → universal rules only (no java rules)
  - iOS → universal rules only
  - Android → universal rules only
- NEVER flag missing Java rules as "outdated" in a non-Java project

## Step 4c: Detect install_role

**Why this matters:** teams typically have two linked AI Awareness installs per project — the code repo (where `aa-task-flow`, `aa-review-pr`, etc. run) and the workspace/tasks repo (where `aa-task-flow-progress-fixer`, `aa-weekly-report`, `aa-task-flow-remember` run). Each install should only carry the skills that actually run from it. Installing `aa-weekly-report` into a code repo is dead weight at best and a footgun at worst (someone invokes it from the wrong directory, hits confusing failures).

Every install has a `install_role` — one of `code-repo` or `workspace`. Read it from `config_hints.json` if explicitly set; otherwise auto-detect.

**Read the explicit override first:**

```bash
explicit_role=$(jq -r '.install_role // "auto"' "$TARGET_PROJECT/.claude/config_hints.json" 2>/dev/null)
```

If `explicit_role` is `code-repo` or `workspace`, use it directly. Otherwise auto-detect:

**Auto-detection (in priority order, first match wins):**

```bash
detect_install_role() {
  local dir="$1"
  local explicit=$(jq -r '.install_role // "auto"' "$dir/.claude/config_hints.json" 2>/dev/null)

  # 1. Explicit override wins
  case "$explicit" in
    code-repo|workspace) echo "$explicit"; return ;;
  esac

  # 2. Directory-name pattern signals workspace
  local basename=$(basename "$dir")
  case "$basename" in
    *_Coding_Tasks|*_DocsProject|*_Tasks|*_Docs)
      echo "workspace"; return ;;
  esac

  # 3. skill.config has paths.tasks_root pointing AT this dir or a subdir → workspace
  if [ -f "$dir/.claude/skill.config" ]; then
    local tasks_root=$(jq -r '.paths.tasks_root // ""' "$dir/.claude/skill.config")
    if [ -n "$tasks_root" ]; then
      local tasks_abs=$(cd "$tasks_root" 2>/dev/null && pwd || echo "")
      local dir_abs=$(cd "$dir" && pwd)
      if [ -n "$tasks_abs" ] && [[ "$tasks_abs" == "$dir_abs"* ]]; then
        echo "workspace"; return
      fi
    fi
  fi

  # 4. Presence of a build file → code-repo
  for build_file in package.json build.gradle build.gradle.kts pom.xml Cargo.toml pyproject.toml go.mod Podfile; do
    if [ -f "$dir/$build_file" ]; then
      echo "code-repo"; return
    fi
  done

  # 5. Default to code-repo (safer default: code repos have richer skill needs;
  #    workspaces are smaller and a misclassification there is easier to spot)
  echo "code-repo"
}

INSTALL_ROLE=$(detect_install_role "$TARGET_PROJECT")
echo "Install role: $INSTALL_ROLE"
```

**What `INSTALL_ROLE` controls:**

- **Step 6 (Install/Update Skills):** picks the source directory by install role — directory location IS the role (v7.0.0 replaced the v6.6.0–v6.10.0 `run-from:` filter / `skills/manifest.json` lookup with a path-based selector):
  - `INSTALL_ROLE=code-repo` → install all skills under `{framework_path}/skills/`
  - `INSTALL_ROLE=workspace` → install all skills under `{framework_path}/workspace-skills/`
  - Framework-repo commands (aa-install, aa-upgrade, etc.) live under `{framework_path}/.claude/commands/` and are never installed into a target.
- **Step 10 (Create config_hints.json):** persists the resolved `install_role` so future upgrades read it directly without re-detecting (project authors can edit it if auto-detection was wrong).
- **`aa-install` Phase 1 step 1b (Create Install Branch):** workspace installs **skip branch creation entirely**. Workspace/docs/tasks repos commit directly to their default branch and don't use feature branches or PRs. Creating one hides the install commits on a branch the team doesn't look at. Code-repo installs keep the normal feature-branch flow.
- **`aa-upgrade` Phase 1 step 1b (Create Update Branch):** same as above — workspace installs skip the branch creation step. If a workspace install is found already on a non-default branch (leftover from a pre-v6.7.0 buggy run), a one-line warning surfaces and the user confirms before proceeding.
- **`aa-install` Phase 6 / `aa-upgrade` Phase 5 final summary:** the post-install/upgrade "next steps" guidance differs:
  - `workspace`: tells the user to commit and push to the default branch. No PR mentioned.
  - `code-repo`: tells the user how to push the install/upgrade branch and open a PR with `gh pr create`.
- **`aa-upgrade` cleanup step:** detects skills already installed that don't match the install_role and offers to remove them (opt-in cleanup of drift from pre-v6.7.0 installs).
- **`aa-upgrade` Phase 5 step 5e-2 (auto commit/push):** workspace installs auto-commit and auto-push silently (matches the Docs Auto-Push convention). Code-repo installs commit locally only — push and PR creation is left to the user.

If auto-detection landed on the wrong role, the user can set `install_role` explicitly in `config_hints.json` and re-run the install/upgrade.

## Step 5: Handle CLAUDE.md

CLAUDE.md should contain **only** `@AGENTS.md` and a notice — nothing else. AGENTS.md is the single source of truth for ALL project documentation including skills, agents, and getting started guides.

**5a. Scan for existing AI instruction files:**

Before doing anything, check for any existing AI-related files that may contain useful project context:

```bash
# Check for common AI instruction files
for f in CLAUDE.md .cursorrules .cursor/rules/README.md .claude/rules/README.md \
         COPILOT.md .github/copilot-instructions.md AI.md .ai/README.md \
         CODEBASE.md CONVENTIONS.md .windsurfrules; do
  if [ -f "$f" ]; then
    echo "FOUND: $f"
  fi
done
```

If any files are found (other than CLAUDE.md), ask user:
```
I found existing AI instruction files in your project:
- {list of found files}

These may contain useful project context (coding conventions,
architecture notes, build instructions, etc.) that should be
included in AGENTS.md.

Would you like me to review and merge their content into AGENTS.md?

1. Yes, merge all into AGENTS.md (Recommended)
2. Let me pick which ones to merge
3. Skip - ignore these files

Your choice?
```

If yes, read and save their content for merging into AGENTS.md in Step 12.

**5b. Handle CLAUDE.md specifically:**

**If CLAUDE.md exists:**
```
Found existing CLAUDE.md with content.

Following AGENTS.md standard, I'll migrate ALL content:
1. Save CLAUDE.md content for merging into AGENTS.md (Step 12)
2. Replace CLAUDE.md with just: @AGENTS.md

Your existing content will be preserved in AGENTS.md.

Proceed? (y/n)
```

If yes, save CLAUDE.md content for Step 12 migration.

**If CLAUDE.md doesn't exist AND running from Claude Code:**

Offer to run `claude init` to bootstrap a smart CLAUDE.md:
```
No CLAUDE.md found. Would you like me to run `claude init` first?

This will:
1. Run `claude init` to auto-generate CLAUDE.md from your project
2. Capture the generated content (build commands, project structure, etc.)
3. Merge it into AGENTS.md (the single source of truth)
4. Replace CLAUDE.md with just: @AGENTS.md

This gives us a better starting point for AGENTS.md since `claude init`
intelligently detects your project setup.

Run claude init first? (y/n)
```

If yes:
```bash
# Run claude init in the target project directory
cd {target_project}
claude init
```

After `claude init` completes:
1. Read the generated CLAUDE.md content
2. Save it for merging into AGENTS.md in Step 12 (same as the "exists" path above)
3. Replace CLAUDE.md with the standard template below

If no (or not running from Claude Code):
Create CLAUDE.md directly.

**Final CLAUDE.md content (all paths lead here):**

```markdown
<!-- NOTE: Do NOT add content here. All project documentation, skills,
     agents, and guidelines belong in AGENTS.md. This file only exists
     to tell Claude Code to load AGENTS.md. -->
@AGENTS.md
```

**Why this works:**
- `@AGENTS.md` tells Claude Code to load AGENTS.md content into context
- AGENTS.md is the single source of truth — project docs, skills, agents, everything
- The notice prevents anyone from accidentally adding content to CLAUDE.md
- No duplication, no drift
- Other tools (Cursor, Windsurf, etc.) also read AGENTS.md directly

## Step 6: Install/Update Skills

**Skill source directory is determined by `INSTALL_ROLE` (resolved in Step 4c) — no metadata, no manifest, no per-skill filter:**

| `INSTALL_ROLE` | Source directory | Skills installed |
|---|---|---|
| `code-repo` | `{framework_path}/skills/` | All directories under `skills/` |
| `workspace` | `{framework_path}/workspace-skills/` | All directories under `workspace-skills/` |

This replaces the v6.6.0–v6.10.0 `run-from:` filter (first SKILL.md frontmatter, then a `skills/manifest.json` lookup). The directory a skill lives in IS its role — no risk of miscategorisation, no metadata to drift.

```bash
# Select source directory by install role
if [ "$INSTALL_ROLE" = "workspace" ]; then
  SKILLS_SRC="{framework_path}/workspace-skills"
else
  SKILLS_SRC="{framework_path}/skills"
fi
```

**If .claude/skills does NOT exist (fresh install):**

```bash
mkdir -p .claude/skills
for skill_dir in "$SKILLS_SRC"/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name=$(basename "$skill_dir")
  cp -r "$skill_dir" .claude/skills/
  echo "Installed: $skill_name"
done
```

**If .claude/skills exists (update):**

Compare each framework skill in the role-appropriate source directory against the installed version:

```bash
for skill_dir in "$SKILLS_SRC"/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name=$(basename "$skill_dir")
  if [ -d ".claude/skills/$skill_name" ]; then
    diff -q "$skill_dir/SKILL.md" ".claude/skills/$skill_name/SKILL.md"
  else
    echo "NEW: $skill_name (will install)"
  fi
done

# Custom skills (exist in project but neither framework source dir) — preserve
for skill_dir in .claude/skills/*/; do
  skill_name=$(basename "$skill_dir")
  if [ ! -d "{framework_path}/skills/$skill_name" ] && \
     [ ! -d "{framework_path}/workspace-skills/$skill_name" ]; then
    echo "CUSTOM: $skill_name (project-specific, will preserve)"
  fi
done
```

For each skill that differs:
1. **Read both versions** (framework and project)
2. **Identify what changed** — project customization, or a missing framework update?
3. **If project customization:** Preserve project version. Merge only non-conflicting framework additions.
4. **If framework update:** Apply the update while preserving project-specific modifications around it.
5. **If unclear:** Ask the user with a specific description of what differs.

For new skills (in framework source dir, not installed): install them.
For custom skills (in project, not in either framework source dir): leave untouched.

**Cleanup of wrongly-placed skills (aa-upgrade only — see `aa-upgrade/SKILL.md`):** If the target's `.claude/skills/` has a skill that exists in the framework's *other* role directory (e.g., `aa-weekly-report` installed in a code-repo target but it lives in `workspace-skills/` in the framework), it's drift from pre-v7.0.0 installs that used the run-from filter and may have mis-installed it. `aa-upgrade` offers to remove with explicit user confirmation. The detection logic is now trivially path-based: a skill is wrongly placed iff it exists in the framework's opposite-role directory.

### Step 6r: Resolve standards-path tokens in installed skills & agents (MANDATORY — install AND upgrade)

Skills/agents reference universal rules via the templated token `{standards_location}/<name>.md`. Some historical source bodies instead used the framework-internal path `rules/universal/<name>.md`. Neither survives into a working target: `rules/universal/` does not exist in the target (universal rules are written to the project's `standards_location`, e.g. `docs/ai-rules/`), and a literal unresolved `{standards_location}` token is meaningless at runtime. After all skills/agents are copied/merged (Step 6 + Step 11), rewrite both forms to the project's real standards path.

```bash
# Read the project's actual standards dir (the only project-specific value these bodies carry)
STANDARDS_DIR=$(jq -r '.standards_location // ".claude/rules"' .claude/config_hints.json)

# Rewrite pass: every installed skill & agent body.
#   rules/universal/<name>.md   -> $STANDARDS_DIR/<name>.md   (dead framework-internal path)
#   {standards_location}/...    -> $STANDARDS_DIR/...         (resolve the template token)
for f in $(find .claude/skills .claude/agents -type f -name '*.md' 2>/dev/null); do
  tmp=$(mktemp)
  sed -e "s#rules/universal/#${STANDARDS_DIR}/#g" \
      -e "s#{standards_location}#${STANDARDS_DIR}#g" "$f" > "$tmp"
  if ! cmp -s "$f" "$tmp"; then
    mv "$tmp" "$f"
    echo "Rewrote standards-path tokens in: $f"
  else
    rm -f "$tmp"
  fi
done
```

**Also resolve the reviewer-agent seam.** `aa-review-pr` ships `subagent_type="{project}-code-reviewer"` as a template seam. It must not survive into the installed copy (an unresolved agent type errors at runtime, and Step 16d check (3) treats a survivor as a blocking violation). Resolve it to the project's custom code-reviewer agent if one exists, else to the stock `aa-code-reviewer`:

```bash
REVIEWER="aa-code-reviewer"
custom=$(find .claude/agents -maxdepth 1 -type d -name '*-code-reviewer' ! -name 'aa-code-reviewer' 2>/dev/null | head -1)
[ -n "$custom" ] && REVIEWER=$(basename "$custom")
for f in $(find .claude/skills -type f -name '*.md' 2>/dev/null); do
  if grep -q '{project}-code-reviewer' "$f"; then
    tmp=$(mktemp)
    sed "s/{project}-code-reviewer/${REVIEWER}/g" "$f" > "$tmp" && mv "$tmp" "$f"
    echo "Resolved reviewer seam to '${REVIEWER}' in: $f"
  fi
done
```

**Post-install/post-upgrade check (FAIL if any survive):** grep the installed skills/agents for either dead form. A survivor means a skill would ship a reference to a path that doesn't exist in the target — exactly the failure this step prevents — so the install/upgrade must fail loudly listing the offenders.

```bash
SURVIVORS=$(grep -rlE 'rules/universal/|\{standards_location\}' .claude/skills .claude/agents 2>/dev/null)
if [ -n "$SURVIVORS" ]; then
  echo "❌ FAIL: installed skills/agents still contain 'rules/universal/' or a literal '{standards_location}':"
  echo "$SURVIVORS" | sed 's/^/  - /'
  echo "These are dead references in the target. Fix the offending files (re-run the Step 6r rewrite) before finalizing."
  exit 1
fi
echo "✅ No surviving 'rules/universal/' or '{standards_location}' tokens in installed skills/agents."
```

## Step 7: Install/Update Settings

**The shipped `{framework_path}/settings.json` CONTAINS a `hooks` block** — a `PreToolUse` / `Bash` matcher hook that enforces two guarantees (exit 2 + stderr → Claude Code sees the refusal reason and routes the work safely): (1) **no `git commit` / `git push` on the code repo's default branch**, and (2) **no force-push on any branch** — it scans the full command for `--force` / `--force-with-lease` / standalone `-f`. This is the PreToolUse hard guarantee referenced by `aa-task-flow` Rule 5 and GOAL B; every guarantee claimed there maps to a line of this hook.

**The default-branch rule is SCOPED to the project's own code repo** — this is the key correctness property. A single Claude session often touches more than one git repo (the code repo *plus* its attached workspace/tasks repo, where committing straight to `main`/`master` is the intended zero-friction flow). The hook therefore:
- resolves the command's **target repo** — the path after a leading `cd <path>` or `git -C <path>`, else `$PWD` — and compares its `git rev-parse --show-toplevel` against the **code repo's** toplevel (`$CLAUDE_PROJECT_DIR`, generically; never a hardcoded repo name);
- blocks commit/push on the default branch **only when the target repo IS the code repo**. Any other repo (attached workspace, sibling repos) is **exempt** and commits/pushes to its default branch freely;
- a code-repo **git worktree** resolves to its own (feature-branch) toplevel, so it's naturally exempt — correct, since task-flow worktrees must auto-commit/push;
- treats `main` **and** `master` as protected names, plus the code repo's **dynamically detected** default via `origin/HEAD` (covers a `develop`-default repo);
- the **force-push guard is global** — rewriting pushed history is wrong in any repo.

**`install_role` gating (code-repo only):** keep the `hooks` block for `INSTALL_ROLE=code-repo`; strip it for `INSTALL_ROLE=workspace` (a workspace install's own `$CLAUDE_PROJECT_DIR` is the workspace repo, and it commits to its default branch by design — it should carry no guard at all).
- `INSTALL_ROLE=code-repo` → keep the `hooks` block (the common case — gets it on a plain copy).
- `INSTALL_ROLE=workspace` → strip the `hooks` block from the settings.json written to the target.

**Self-modification constraint (why this must ship in the template):** an agent running under `auto` permission mode is hard-blocked from editing an installed `.claude/settings.json` safety hook, even on explicit request. So the framework cannot rely on the agent to retrofit this scoped hook in an existing install — the corrected hook ships here in the template (fresh installs + `aa-upgrade` get it directly), and an existing install needs a human to paste it in (the agent can only prepare the proposed file).

**If .claude/settings.json does NOT exist (fresh install):**
```bash
if [ "$INSTALL_ROLE" = "workspace" ]; then
  # Workspace installs commit directly to their default branch — strip the default-branch + force-push guard hook.
  jq 'del(.hooks)' {framework_path}/settings.json > .claude/settings.json
else
  # code-repo: keep the hooks block (default-branch commit/push + force-push guard).
  cp {framework_path}/settings.json .claude/
fi
```

**If .claude/settings.json exists (update):**

Read both settings files and merge intelligently. On update, read the resolved role back from config_hints.json (`jq -r .install_role .claude/config_hints.json`) — same source used elsewhere in this doc — and apply the same code-repo-only gating to the `hooks` block:

1. **Allow list:** Union of framework and project allow entries. Remove entries irrelevant to the project's platform (e.g., don't add `Bash(./mvnw:*)` to a Gradle project, don't add `Bash(./gradlew:*)` to a Maven project).
2. **Deny list:** Union of framework and project deny entries (safety rules are additive — more is better).
3. **Project-specific entries:** Preserve any allow/deny rules the project has that aren't in the framework.
4. **Framework additions:** Add any new allow/deny rules from the framework that the project is missing.
5. **Hooks block (code-repo only):** If the resolved role is `code-repo`, ensure the framework's `hooks` block (default-branch commit/push + force-push guard) is present in the merged result, adding it if the project is missing it. **If the project already has an older main-only guard hook, replace it with the framework's current version** so the dynamic-default-branch + force-push coverage lands. If the resolved role is `workspace`, strip/omit the `hooks` block so the guard never lands in a workspace install.

```bash
INSTALL_ROLE=$(jq -r '.install_role // "code-repo"' .claude/config_hints.json 2>/dev/null)
if [ "$INSTALL_ROLE" = "workspace" ]; then
  # Drop any hooks block from the merged settings written to a workspace target.
  jq 'del(.hooks)' .claude/settings.json > .claude/settings.json.tmp && mv .claude/settings.json.tmp .claude/settings.json
fi
# code-repo: keep/merge the framework hooks block per rule 5 above (replace any stale main-only guard).
```

## Step 8: Install/Update Coding Standards

**Detect existing rules in known locations:**
```bash
# Check .cursor/rules
HAS_CURSOR_RULES=false
if [ -d ".cursor/rules" ] && [ ! -L ".cursor/rules" ]; then
  cursor_mdc=$(ls .cursor/rules/*.mdc 2>/dev/null | wc -l | tr -d ' ')
  cursor_md=$(ls .cursor/rules/*.md 2>/dev/null | wc -l | tr -d ' ')
  cursor_total=$((cursor_mdc + cursor_md))
  [ "$cursor_total" -gt 0 ] && HAS_CURSOR_RULES=true
fi

# Check .claude/rules
HAS_CLAUDE_RULES=false
if [ -d ".claude/rules" ]; then
  claude_count=$(ls .claude/rules/*.md 2>/dev/null | wc -l | tr -d ' ')
  [ "$claude_count" -gt 0 ] && HAS_CLAUDE_RULES=true
fi
```

**Report what was found:**
```bash
$HAS_CURSOR_RULES && echo "Found .cursor/rules/ with $cursor_mdc .mdc and $cursor_md .md files"
$HAS_CLAUDE_RULES && echo "Found .claude/rules/ with $claude_count .md files"
```

**Ask user where to place coding standards:**
```
Where should I place coding standards?

1. docs/ai-rules (Recommended - AI/agent-specific, tool-agnostic)
2. docs/coding-standards (Generic engineering standards, tool-agnostic)
3. .cursor/rules (Keep Cursor IDE location)
4. .claude/rules (Keep Claude Code location)
5. .aiRules (Hidden directory, tool-agnostic)

Your choice (1/2/3/4/5)?
```

Store the choice as `STANDARDS_DIR` variable for use throughout setup.

**If user has existing rules in .cursor/rules OR .claude/rules AND chooses a DIFFERENT location:**

This is the migration path. Existing rules are migrated to the new source of truth.

```
Found existing rules:
{list files from .cursor/rules and/or .claude/rules}

Migrating to {STANDARDS_DIR}/:
1. Move existing rules to {STANDARDS_DIR}/ (rename .mdc → .md if needed)
2. Layer framework rules on top (with conflict resolution)
3. Remove old location(s) (no longer the source of truth)

Your existing rules become the base. Framework rules are added on top.

Continue? (y/n)
```

**Step 8a: Migrate existing rules to new location:**

```bash
mkdir -p $STANDARDS_DIR

# Migrate from .cursor/rules (if exists and different from target)
if $HAS_CURSOR_RULES && [ "$STANDARDS_DIR" != ".cursor/rules" ]; then
  # Move .mdc files → .md (rename extension)
  for f in .cursor/rules/*.mdc; do
    [ -f "$f" ] || continue
    basename=$(basename "$f" .mdc)
    cp "$f" "$STANDARDS_DIR/${basename}.md"
    echo "  Migrated: .cursor/rules/${basename}.mdc → ${basename}.md"
  done

  # Move .md files as-is
  for f in .cursor/rules/*.md; do
    [ -f "$f" ] || continue
    basename=$(basename "$f")
    cp "$f" "$STANDARDS_DIR/${basename}"
    echo "  Migrated: .cursor/rules/${basename}"
  done
fi

# Migrate from .claude/rules (if exists and different from target)
if $HAS_CLAUDE_RULES && [ "$STANDARDS_DIR" != ".claude/rules" ]; then
  for f in .claude/rules/*.md; do
    [ -f "$f" ] || continue
    basename=$(basename "$f")
    # Don't overwrite if already migrated from .cursor/rules
    if [ -f "$STANDARDS_DIR/${basename}" ]; then
      echo "  Skipped: .claude/rules/${basename} (already exists from .cursor/rules migration)"
    else
      cp "$f" "$STANDARDS_DIR/${basename}"
      echo "  Migrated: .claude/rules/${basename}"
    fi
  done
fi
```

**Note:** If rules exist in BOTH `.cursor/rules` and `.claude/rules`, the `.cursor/rules` version is migrated first (it's usually the older, more established set). `.claude/rules` files are only added if they don't conflict.

**Step 8b: Determine which framework rules apply to this project:**

**IMPORTANT:** Do NOT blindly copy all framework rules. Only process rules relevant to the project's actual stack.

**When running via the Content Adaptation Pipeline:** The mapping file from the Stack Analyzer determines which rule directories apply. Use the "Applicable Framework Rules" table from the mapping — it contains evidence-based decisions about which rules to install. Skip this manual detection entirely.

**When running outside the pipeline (legacy reference):** If platform detection is needed without a mapping file, read the project's actual files to determine its stack. The examples below illustrate the kind of evidence to look for — they are not exhaustive:

```bash
# Read config_hints.json if available (existing installs)
if [ -f ".claude/config_hints.json" ]; then
  PLATFORM=$(grep '"platform"' .claude/config_hints.json | sed 's/.*: *"\(.*\)".*/\1/')
fi

# Otherwise detect from project files — look for actual evidence
# Java/Kotlin + Spring Boot → java-spring-boot rules apply
# React/Next.js → react rules apply
# Other stacks → universal rules only (until stack-specific rules exist)
```

**Build the list of applicable framework rules based on detection:**

```bash
# Universal rules always apply (both install roles)
APPLICABLE_RULES="{framework_path}/rules/universal/*.md"

# Workspace-only rules — only for workspace installs.
# v7.0.0 split these out of rules/universal/ because leadership/status-report
# rules like cross-team-framing.md and document-formatting.md were leaking
# into code-repo targets where they don't apply.
if [ "$INSTALL_ROLE" = "workspace" ]; then
  APPLICABLE_RULES="$APPLICABLE_RULES {framework_path}/workspace-rules/*.md"
fi

# Add platform-specific rules based on what was detected
# These are examples — the Research agent may detect stacks not listed here
# Java Spring Boot detected → add java-spring-boot rules
# React detected → add react rules
# Any other stack → universal + workspace-rules (if workspace) only
```

**Step 8b-rename: Handle renamed framework files (run before 8c)**

Some framework files have been renamed across versions. A renamed file will appear as `CUSTOM` in Step 8c (project has old name, framework has new name) — it must be handled explicitly before the main loop runs.

**Current rename table:**

| Old filename | New filename | Introduced in |
|---|---|---|
| `n-plus-1-queries.md` | `query-efficiency.md` | v3.4 |

For each row in the rename table, check if the project has the old file:

```bash
OLD="n-plus-1-queries.md"
NEW="query-efficiency.md"

if [ -f "$STANDARDS_DIR/$OLD" ]; then
  echo "RENAMED: $OLD → $NEW found in project"
fi
```

If the old file exists in the project:
1. **Read both** — the project's old file and the framework's new file
2. **Identify project-specific additions** in the old file (custom examples, project-specific rules added by the team) that are not present in the framework's new file
3. **Merge** those project-specific additions into the new file at the appropriate location
4. **Write** the merged result to `$STANDARDS_DIR/$NEW`
5. **Delete** the old file: `rm $STANDARDS_DIR/$OLD`
6. **Update references** — scan project files (AGENTS.md, any .md files in `$STANDARDS_DIR`) for the old filename and replace with the new filename

```bash
# Update references in project files
grep -rl "$OLD" "$STANDARDS_DIR/" .claude/ | while read f; do
  sed -i '' "s/$OLD/$NEW/g" "$f"
  echo "Updated reference in: $f"
done
```

Tell the user:
```
Renamed: $OLD → $NEW
- Merged project-specific additions into new file
- Updated {N} file references
- Deleted old file
```

**Step 8c: Categorize and merge applicable rules:**

For each applicable framework rule, compare against what already exists in `$STANDARDS_DIR`:

```bash
for framework_rule in $APPLICABLE_RULES; do
  basename=$(basename "$framework_rule")
  if [ -f "$STANDARDS_DIR/$basename" ]; then
    echo "EXISTS: $basename — needs intelligent merge"
  else
    echo "NEW: $basename — will add"
  fi
done

# Identify project-only rules (custom additions not in framework)
for project_rule in $STANDARDS_DIR/*.md; do
  basename=$(basename "$project_rule")
  found=false
  for framework_rule in $APPLICABLE_RULES; do
    [ "$(basename "$framework_rule")" = "$basename" ] && found=true && break
  done
  $found || echo "CUSTOM: $basename — project-specific, will preserve"
done
```

**For NEW rules (no existing version):** Copy from framework to `$STANDARDS_DIR/`.

**For CUSTOM rules (project-only):** Leave untouched. These are the project's own additions.

**For EXISTS rules (both have a version) — intelligent merge:**

The existing project rules may be highly tuned and project-specific. Do NOT blindly replace them. Instead:

1. **Read BOTH versions** — the existing project version and the framework version
2. **Compare and categorize each difference:**
   - **Project-specific content** (examples using actual project packages, entity names, project-specific patterns) → ALWAYS KEEP
   - **Framework structural additions** (e.g., YAML frontmatter for Claude Code rule loading) → ADD without disturbing existing content
   - **Framework content missing from existing** (new sections, additional guardrails) → ADD to the merged result
   - **Overlapping content where both cover the same topic** → Keep the more detailed/project-specific version. If the framework version adds new guardrails not in the existing version, append those sections.
   - **Contradictory guidance** → ASK the user a specific, to-the-point question to resolve the conflict. Do NOT ask generic "which do you prefer?" questions — instead describe the specific contradiction and ask which behavior they want.

3. **Write the merged result** to `$STANDARDS_DIR/$basename`

**Key principle:** The project has been running with these rules — they reflect real decisions made by the team. The framework rules add structure and fill gaps, but should never silently override working project conventions.

**Step 8d: Clean up old locations (migration only)**

Only applies if rules were migrated from a different location (e.g., `.cursor/rules` → `docs/ai-rules`).

```bash
# Remove .cursor/rules if migrated away
if $HAS_CURSOR_RULES && [ "$STANDARDS_DIR" != ".cursor/rules" ]; then
  rm -rf .cursor/rules
  echo "Removed .cursor/rules/ (migrated to $STANDARDS_DIR/)"
fi

# Remove .claude/rules if migrated away
if $HAS_CLAUDE_RULES && [ "$STANDARDS_DIR" != ".claude/rules" ]; then
  rm -rf .claude/rules
  echo "Removed .claude/rules/ (migrated to $STANDARDS_DIR/)"
fi
```

**If no existing rules to migrate (fresh install):**
```bash
mkdir -p $STANDARDS_DIR
# Copy universal rules (apply to both install roles)
cp {framework_path}/rules/universal/*.md $STANDARDS_DIR/

# Workspace-only rules — installed for workspace installs only.
# These are leadership/status-report style rules (cross-team framing, document formatting
# for weekly reports etc.) that don't belong in code repos. v7.0.0 split them out of
# rules/universal/ into a separate top-level workspace-rules/ directory.
if [ "$INSTALL_ROLE" = "workspace" ]; then
  cp {framework_path}/workspace-rules/*.md $STANDARDS_DIR/ 2>/dev/null || true
fi

# Platform-specific rules are added in Step 9
```

**If user chooses to keep existing location (option 3 or 4):**

No migration needed. Rules stay in place. Framework rules are merged on top using the same logic as Step 8c.

**Note:** The source of truth is `$STANDARDS_DIR/*.md`.

## Step 9: Install Platform-Specific Rules

**Note:** Platform was already detected in Step 8b. Use the `$PLATFORM` variable.

**If Backend (Java Spring Boot) — and this is a fresh install or rules are NEW:**

For fresh installs, ask user before adding platform rules:
```
Detected Java Spring Boot project (platform: Backend).

Java Spring Boot rules available:
- api-conventions — REST API patterns (BaseControllerV2, HttpResponseV2)
- coding-conventions — Java code style and patterns
- commands — Spring Batch job patterns
- database-migrations — Flyway migration patterns
- jpa-repositories — JPA/Spring Data patterns (UserHash filtering)
- mcp-integration — MCP server setup
- metrics-collection — in-house MetricsCollectionService facade (installed ONLY if that facade already exists in the repo — see below)
- module-boundaries — module isolation (entities stay in module-server, two-mapper pattern)
- query-efficiency — Query selectivity and N+1 prevention patterns
- project-structure — Module and package layout
- sonarqube-compliance — SonarQube finding prevention (S4973, S135, S2094, AssertJ/Mockito idioms)
- transaction-boundaries — Transaction safety patterns
- unit-testing — Layer-by-layer test strategy, coverage gate, time-dependent-test safety

Install all? (y/n)
Or select specific rules? (y/n)
```

**Infrastructure-dependent rules (probe before install — applies to fresh install AND update):**

Rule files fall into two classes:
- **Universal / process rules** — apply to any repo of the stack (e.g. `api-conventions`, `coding-conventions`, `query-efficiency`, `transaction-boundaries`, `database-migrations`). Install normally.
- **Infrastructure-dependent rules** — document a concrete in-house facade/component that only some repos have. A rule declares this with a `requires:` frontmatter field naming the prerequisite symbol. **Install such a rule ONLY if the target repo already contains that symbol** — otherwise it instructs Claude to call infrastructure that doesn't exist (a fabrication trap). `metrics-collection.md` (`requires: MetricsCollectionService`) is the current example.

Gate each rule that declares `requires:` before copying it (and skip it during the "Install all" path):

```bash
# For each candidate framework rule file about to be installed:
need=$(awk 'NR==1&&$0=="---"{f=1;next} f&&$0=="---"{exit} f&&/^requires:/{sub(/^requires:[[:space:]]*/,"");gsub(/^["'\'']|["'\'']$/,"");print;exit}' "$rule_src")
if [ -n "$need" ]; then
  # Probe from the repo root with a source-file filter — NOT a top-level src/ only.
  # Spring Boot backends are often multi-module (module-api/src/main/java, module-worker/src/…)
  # with no top-level src/, so a `src/`-only grep would silently miss a facade that exists in a submodule.
  if grep -rqsF "$need" "{target_project}" --include='*.java' --include='*.kt' --include='*.kts' 2>/dev/null; then
    cp "$rule_src" "$STANDARDS_DIR/"            # prerequisite present → install
  else
    echo "available but not installed: $(basename "$rule_src") — requires '$need', not found in target" \
      >> "$STANDARDS_DIR/.setup-notes.txt"      # record in the install report; do NOT copy
  fi
else
  cp "$rule_src" "$STANDARDS_DIR/"              # universal/process rule → install normally
fi
```

Surface the skipped infrastructure-dependent rules in the install/upgrade summary so the decision is visible, not silent.

For updates: Platform-specific rules are already handled by Step 8c's intelligent merge. Only NEW rules (ones that exist in the framework but not in the project) need action here — **and the `requires:` probe still applies**: do not introduce an infrastructure-dependent rule on upgrade unless the prerequisite symbol now exists in the repo.

**Already-installed infra-dependent rule whose prerequisite is now absent (upgrade):** if the target already has a rule declaring `requires:` but the symbol is **not** in the repo (e.g. a prior install shipped `metrics-collection.md` into a repo that never had `MetricsCollectionService`), **flag it in the upgrade report** — `"installed but prerequisite missing: <rule> (requires '<symbol>') — build the pattern or remove the rule"`. Do **not** auto-remove it (the team may have customized it); surface it so the decision is deliberate.

**Project-structure rule (special handling for fresh install):**

If `project-structure.md` doesn't exist in the target project yet:
```
The project-structure.md rule contains generic examples.
I'll analyze your project's actual package structure and generate
a project-specific version instead of copying the generic template.
```

1. Detect the project's package structure by scanning `src/main/java/`
2. Identify modules from `settings.gradle` or `settings.gradle.kts`
3. Generate `project-structure.md` using the framework template as a base, replacing all generic placeholders with real project values (package names, entity names, module names)

If `project-structure.md` already exists in the target: leave it alone (it's already project-specific).

**Backend project-structure translation (for Java):**
```
The project-structure.md rule contains examples from other projects.

Would you like me to translate these examples to match your project?

1. Copy with example translation (Recommended)
   - I'll detect your project's package structure (e.g., com.example.{project})
   - Replace example package names with your actual packages
   - Update entity/service names to match your domain

2. Copy as-is (you can adapt examples later)
   - File copied with placeholder examples
   - You'll manually update package names

3. Skip (you'll create your own structure doc)

Your choice?
```

**If choice 1 (Example Translation):**
```bash
# Detect project package structure
base_package=$(find {target_project}/src/main/java -type d -name "com" -o -name "org" | head -1)
if [ -n "$base_package" ]; then
  # Extract package structure (e.g., com/example/userservice)
  project_package=$(echo "$base_package" | sed 's|.*/java/||')

  # Copy and translate
  cp {framework_path}/rules/java-spring-boot/project-structure.md $STANDARDS_DIR/

  # Replace {project} placeholders with detected package name
  sed -i '' "s|com\.example\.{project}|${project_package}|g" $STANDARDS_DIR/project-structure.md

  echo "✓ Translated examples to use package: ${project_package}"
else
  echo "⚠ Could not auto-detect package structure. Copying with placeholders."
  cp {framework_path}/rules/java-spring-boot/project-structure.md $STANDARDS_DIR/
fi
```

**If choice 2:**
```bash
cp {framework_path}/rules/java-spring-boot/project-structure.md $STANDARDS_DIR/
echo "NOTE: Update project-structure.md with your project's package names" >> $STANDARDS_DIR/.setup-notes.txt
```

**If Frontend (React):**

For fresh installs, ask user before adding platform rules:
```
Detected a React project.

React-specific coding rules available:
- api-conventions — REST API patterns (ky, React Query, Zod validation)
- coding-conventions — TypeScript/React code style and patterns
- forms — React Hook Form + Zod patterns
- i18n-rtl — Internationalization and RTL support
- project-structure — React SPA directory layout
- routing — React Router v7 patterns
- state-management — React Query + Zustand patterns
- styling — Tailwind CSS with design tokens
- testing — Vitest + Testing Library patterns

Install all? (y/n)
Or select specific rules? (y/n)
```

For updates: Platform-specific rules are already handled by Step 8c's intelligent merge. Only NEW rules need action.

**Note:** React rules use generic examples (items, users, data). Projects should adapt entity names to match their domain.

**If iOS / Android:**
```
Detected {platform} project.

Platform-specific rules for {platform} are being developed.
Universal rules have been installed. You can add {platform} patterns to $STANDARDS_DIR/ manually.

## Step 10: Create config_hints.json

```
What platform is this project?

Common options:
1. Backend - Java Spring Boot (a backend service service)
2. Frontend - React (web app)
3. iOS (the iOS app app)
4. Android (the Android app app)
5. Other (describe below)

Your choice (enter number or describe your platform, e.g., Python/FastAPI, Ruby/Rails, Go/Gin):
```

If the user enters 5 or types free-form text, store the description as the `platform` value. The platform field is a free-form string — it is not limited to the 4 options above. The Stack Analyzer's detection from `_stack_mapping.md` is the authoritative source when available.

Create `.claude/config_hints.json` with configuration from Steps 3 and 8.

**Single-namespace schema:**

```json
{
  "_comment": "Project configuration for AI Awareness framework. Safe to commit to git.",

  "project": {
    "namespace": "{project_namespace}",
    "name": "{project_name}",
    "tracker": { "type": "github", "url": "" }
  },
  "framework_version": "{FRAMEWORK_VERSION}",
  "install_role": "{INSTALL_ROLE}",
  "platform": "{selected_platform}",
  "standards_location": "{STANDARDS_DIR}",
  "path_derivation_rules": {
    "tasks_folder": "{tasks_root}/OnGoingTasks",
    "done_folder": "{tasks_root}/DoneTasks",
    "task_summary_folder": "{coding_tasks_root}/TasksSummary",
    "templates_folder": "{coding_tasks_root}/Templates",
    "skill_updates_folder": "{docs_root}/AI_Workflows/SkillUpdates"
  }
}
```

**Multi-namespace schema (for teams working across multiple Jira spaces):**

```json
{
  "_comment": "Project configuration for AI Awareness framework. Safe to commit to git.",

  "project": {
    "name": "{project_name}",
    "tracker": { "type": "jira", "url": "your-org.atlassian.net" },
    "default_namespace": "{first_namespace_prefix}",
    "namespaces": [
      { "prefix": "{PREFIX_1}", "name": "{Jira Space 1}" },
      { "prefix": "{PREFIX_2}", "name": "{Jira Space 2}" }
    ]
  },
  "framework_version": "{FRAMEWORK_VERSION}",
  "platform": "{selected_platform}",
  "standards_location": "{STANDARDS_DIR}",
  "path_derivation_rules": {
    "tasks_folder": "{tasks_root}/OnGoingTasks",
    "done_folder": "{tasks_root}/DoneTasks",
    "task_summary_folder": "{coding_tasks_root}/TasksSummary",
    "templates_folder": "{coding_tasks_root}/Templates",
    "skill_updates_folder": "{docs_root}/AI_Workflows/SkillUpdates"
  }
}
```

**How skills resolve the namespace at runtime:**
- If the user's prompt contains a ticket ID (e.g., `CORE-123`), extract the prefix and match against `namespaces[].prefix`
- If no ticket ID in the prompt, use `default_namespace` for branch naming
- The `namespace` field (single) is kept for backward compatibility — skills check `namespaces` first, fall back to `namespace`

**Stack & command fields (REQUIRED — these make skills/agents language-neutral; add to whichever template variant you use):**
```json
  "stack": "{DETECTED_STACK}",          // from pre-detection: java-spring-boot | react | android | ios | go | ruby | rust | python | node | jvm-generic | generic
  "test_command": "",                    // the project's test command (e.g. "go test ./...", "bundle exec rspec"); empty → skills detect from the repo
  "lint_command": "",                    // the project's linter/formatter (e.g. "golangci-lint run", "rubocop"); empty → skills detect
  "verify": { "full_command": "" }       // the "everything green before merge" command (opt-in integration suites); empty → default test task + skipped-suite flagging
```

**Continuous-finish fields (OPTIONAL — only when the team opts into the non-stop Phase 4 flow):**
```json
  "flow": { "continuous": false },       // true = aa-task-flow Phase 4 doesn't ask at commit/PR, creates the PR ready-for-review, runs the 4l CI/quality monitor loop
  "verify_pr": { "timeout_minutes": 30, "coverage_min": null }  // 4l poll window; optional minimum coverage % (below → treated as a failure to fix)
```
Skills (`aa-task-flow` Phase 3/4g, `aa-test-runner`) read these instead of assuming Gradle/JUnit. The **`stack`** field is read by the Step 16b guardrail to decide which language's idioms are legitimate. Persist `stack` from the pre-detection `DETECTED_STACK`; leave the command fields empty if unknown (skills then detect-and-branch from the repo — never assume).

**Detect and persist a CONCRETE `test_command` (best-effort — install AND upgrade):** the Stack Analyzer already detected the test framework (Step Stack-Analyzer "Detect test framework" / `_stack_mapping.md` Test Command line) but the template ships `test_command: ""`. Populate it with the project's real command so skills don't fall back to guessing. Prefer a Makefile `test` target if present (teams wrap the canonical command there); otherwise use the language-native command for the detected stack. **Detection-driven only — never hardcode any single project's command.** If detection is ambiguous, leave it empty (current behavior) and note it.

```bash
CONFIG=.claude/config_hints.json
detect_test_command() {
  # 1. Makefile `test` target wins — teams wrap the canonical command there.
  if [ -f Makefile ] && grep -qE '^test:' Makefile; then echo "make test"; return; fi
  # 2. Language-native command by detected build tooling.
  if [ -f build.gradle ] || [ -f build.gradle.kts ] || [ -f settings.gradle ] || [ -f settings.gradle.kts ]; then
    [ -f gradlew ] && echo "./gradlew test" || echo "gradle test"; return
  fi
  if [ -f pom.xml ]; then [ -f mvnw ] && echo "./mvnw test" || echo "mvn test"; return; fi
  if [ -f go.mod ]; then echo "go test ./..."; return; fi
  if [ -f Cargo.toml ]; then echo "cargo test"; return; fi
  if [ -f Gemfile ] && grep -qiE 'rspec' Gemfile; then echo "bundle exec rspec"; return; fi
  if [ -f Gemfile ]; then echo "bundle exec rake test"; return; fi
  if [ -f pyproject.toml ] || [ -f pytest.ini ] || [ -f setup.cfg ]; then echo "pytest"; return; fi
  if [ -f package.json ] && jq -e '.scripts.test // empty' package.json >/dev/null 2>&1; then echo "npm test"; return; fi
  echo ""  # ambiguous — leave empty
}

TEST_CMD=$(detect_test_command)
if [ -n "$TEST_CMD" ]; then
  # Only write if currently empty/absent — never clobber a value the team already tuned.
  existing=$(jq -r '.test_command // ""' "$CONFIG" 2>/dev/null)
  if [ -z "$existing" ]; then
    tmp=$(mktemp); jq --arg c "$TEST_CMD" '.test_command = $c' "$CONFIG" > "$tmp" && mv "$tmp" "$CONFIG"
    echo "Persisted test_command: $TEST_CMD"
  fi
else
  echo "test_command left empty — detection ambiguous; skills will detect from the repo at runtime."
fi

# verify.full_command: only set when the project clearly exposes a guarded/integration suite
# (e.g. a Makefile `verify`/`integration-test` target, or an npm `test:integration` script).
# Otherwise leave empty — the default test task + skipped-suite flagging applies.
VERIFY_CMD=""
if [ -f Makefile ] && grep -qE '^verify:' Makefile; then VERIFY_CMD="make verify";
elif [ -f Makefile ] && grep -qE '^integration-test:' Makefile; then VERIFY_CMD="make integration-test";
elif [ -f package.json ] && jq -e '.scripts["test:integration"] // empty' package.json >/dev/null 2>&1; then VERIFY_CMD="npm run test:integration";
fi
if [ -n "$VERIFY_CMD" ]; then
  existing=$(jq -r '.verify.full_command // ""' "$CONFIG" 2>/dev/null)
  if [ -z "$existing" ]; then
    tmp=$(mktemp); jq --arg c "$VERIFY_CMD" '.verify = (.verify // {}) + {full_command: $c}' "$CONFIG" > "$tmp" && mv "$tmp" "$CONFIG"
    echo "Persisted verify.full_command: $VERIFY_CMD"
  fi
fi
```

This runs the same way on `aa-upgrade` (where config_hints is refreshed in Phase 5) — the "only write if empty" guard makes it idempotent and never clobbers a tuned value.

**Example for User Service project (single namespace):**
```json
{
  "_comment": "Project configuration for AI Awareness framework. Safe to commit to git.",

  "project": {
    "namespace": "SVC",
    "name": "User Service",
    "tracker": { "type": "github", "url": "" }
  },
  "framework_version": "2.12",
  "platform": "Backend",
  "standards_location": "docs/ai-rules",
  "path_derivation_rules": {
    "tasks_folder": "{tasks_root}/OnGoingTasks",
    "done_folder": "{tasks_root}/DoneTasks",
    "task_summary_folder": "{coding_tasks_root}/TasksSummary",
    "templates_folder": "{coding_tasks_root}/Templates",
    "skill_updates_folder": "{docs_root}/AI_Workflows/SkillUpdates"
  }
}
```

**Example for the Android app project (multiple namespaces):**
```json
{
  "_comment": "Project configuration for AI Awareness framework. Safe to commit to git.",

  "project": {
    "name": "the Android app",
    "tracker": { "type": "jira", "url": "your-org.atlassian.net" },
    "default_namespace": "MOBILE",
    "namespaces": [
      { "prefix": "CORE", "name": "Core Service" },
      { "prefix": "DATA", "name": "Items Meta" },
      { "prefix": "OPS", "name": "Growth Team" },
      { "prefix": "MOBILE", "name": "Mobile Platform" }
    ]
  },
  "framework_version": "2.12",
  "platform": "Android",
  "standards_location": "docs/ai-rules",
  "path_derivation_rules": {
    "tasks_folder": "{tasks_root}/OnGoingTasks",
    "done_folder": "{tasks_root}/DoneTasks",
    "task_summary_folder": "{coding_tasks_root}/TasksSummary",
    "templates_folder": "{coding_tasks_root}/Templates",
    "skill_updates_folder": "{docs_root}/AI_Workflows/SkillUpdates"
  }
}
```

**Note:** This file contains NO absolute paths and is safe to commit to git. All developers on the project will share this configuration.

## Step 11: Install/Update Agents

**If .claude/agents does NOT exist (fresh install):**
```bash
mkdir -p .claude/agents
cp -r {framework_path}/agents/* .claude/agents/
```

**If .claude/agents exists (update):**

Compare each framework agent against the installed version, same approach as Step 6:

```bash
for agent_dir in {framework_path}/agents/*/; do
  agent_name=$(basename "$agent_dir")
  if [ -d ".claude/agents/$agent_name" ]; then
    # Both exist — compare
    diff -q "$agent_dir/AGENT.md" ".claude/agents/$agent_name/AGENT.md"
  else
    echo "NEW: $agent_name (not installed yet)"
  fi
done

# Identify project-only agents (custom additions)
for agent_dir in .claude/agents/*/; do
  agent_name=$(basename "$agent_dir")
  if [ ! -d "{framework_path}/agents/$agent_name" ]; then
    echo "CUSTOM: $agent_name (project-specific, will preserve)"
  fi
done
```

For each agent that differs: Use the same intelligent merge logic as Step 6.
For new agents: Install them.
For custom agents (e.g., a project's own `{project}-code-reviewer/`): Leave untouched — these are project-specific additions.

**What gets installed:**

| Agent | Model | Purpose |
|-------|-------|---------|
| aa-plan-verifier | Opus | Foreground: cross-checks the plan's claims before user review |
| aa-code-reviewer | Opus | Parallel: Reviews code before commit |
| aa-test-runner | Haiku | Background: Runs unit tests while you work |
| aa-doc-writer | Haiku | Optional: Generates ticket.md, pr-description.md |
| aa-commit-writer | Haiku | Write commit messages for aa-task-flow |
| aa-pr-writer | Haiku | Write PR title + body for aa-task-flow |

**Philosophy:**
- Phases 1-3 run in MAIN session (natural conversation flow)
- Agents handle only parallel/background tasks
- No context passing issues

**Model Tier Policy (tier by blast radius of a wrong answer, default to quality):**
- **Opus** = judgment / correctness-critical — a mistake ships a bug (`aa-code-reviewer`) or sends the whole build down a wrong path (`aa-plan-verifier`). These are the highest-leverage places to be correct, so they get the strongest reasoning.
- **Sonnet** = structured analysis with low blast radius (worst case is cheap to catch/fix).
- **Haiku** = mechanical, fully-specified formatting/execution where all context is handed in (`aa-test-runner`, `aa-doc-writer`, `aa-commit-writer`, `aa-pr-writer`) — Opus would be wasted.
- Always use tier **aliases** (`opus`/`sonnet`/`haiku`) in `model:` frontmatter — never pin a strict/dated snapshot, so agents auto-track the latest.
- **⏱ Cost note:** promoting the reviewers + plan-verifier to Opus raises per-task token cost vs an all-Haiku/Sonnet agent set — this is a deliberate **quality-first** choice (a shipped bug or a corrupted plan costs far more than the tokens), **not** a cost optimization.

```
Agents directory structure:
.claude/agents/
├── README.md (agents philosophy and usage)
├── aa-test-runner/AGENT.md
├── aa-code-reviewer/AGENT.md
├── aa-doc-writer/AGENT.md
├── aa-commit-writer/AGENT.md
└── aa-pr-writer/AGENT.md
```

**Format:** Each AGENT.md contains detailed instructions for that agent (model, inputs, instructions, expected output). aa-task-flow reads these and invokes agents using the Task tool.

## Step 12: Create AGENTS.md

**⚠️ IMPORTANT: AGENTS.md vs .claude/agents/**

These are TWO DIFFERENT things:
- **AGENTS.md** (this step) = Repository documentation (setup/build/test/run)
- **.claude/agents/** (Step 11) = Claude workflow automation (background tasks)

Don't confuse them!

**Create AGENTS.md for repository documentation and rubric-scanner validation:**

**Detect build system:**
```bash
if [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
  BUILD_SYSTEM="gradle"
elif [ -f "pom.xml" ]; then
  BUILD_SYSTEM="maven"
elif [ -f "package.json" ]; then
  BUILD_SYSTEM="npm"
elif [ -f "Makefile" ]; then
  BUILD_SYSTEM="make"
fi
```

**Generate AGENTS.md based on detected build system:**

**⚠️ SCANNER COMPATIBILITY RULES — Read before writing AGENTS.md:**

The rubric scanner treats ANY backtick-quoted text as a file path or URL claim and verifies it exists in the repo. To avoid false failures:

1. **Only backtick-quote actual file/directory paths** that exist in the repo
2. **Never use template variables** (like `{project_name}`) inside backticks — resolve them first or use plain text
3. **Never backtick-quote naming patterns** or examples (e.g. write "PascalCase components" not \`PascalCase.tsx\`)
4. **Never backtick-quote localhost URLs** — use plain text for URLs that are only available at runtime
5. **Java/Kotlin package names** (e.g. com.example.server) should be plain text, not backtick-quoted
6. **Sub-package names** (e.g. services, repositories) should be plain text descriptions, not backtick-quoted

**For Gradle (Spring Boot):**
```markdown
# {project_name}

{brief project description}

## Quick Start

### Setup
\`\`\`bash
./gradlew build
\`\`\`

Builds the project and downloads dependencies.

### Build
\`\`\`bash
./gradlew build -x test
\`\`\`

Compiles code without running tests.

### Test
\`\`\`bash
./gradlew test --rerun-tasks
\`\`\`

Runs the full test suite. Use `--rerun-tasks` to bypass Gradle cache.

### Run
\`\`\`bash
./gradlew bootRun
\`\`\`

Starts the Spring Boot application locally. {If multi-module, use ./gradlew :module-name:bootRun with the actual module name.}

## Project Structure

### Modules
{List each top-level Gradle module found in settings.gradle(.kts). Example:}
- \`module-name/\` - Brief description of what this module does

{Only list modules that ACTUALLY exist as directories in the repo.}

### Key Directories
- \`build.gradle\` - Gradle build configuration
{Only include paths below if they actually exist in the repo:}
- \`config/\` - Application configuration (if exists)
- AI coding standards directory (if exists)
- \`.claude/\` - Claude skills, agents, and configuration

### Package Structure

{Describe the Java/Kotlin package layout. IMPORTANT:
- Use FULL FILESYSTEM PATHS in backticks (e.g. \`module-server/src/main/java/com/example/server/\`)
- Do NOT put Java package names in backticks (e.g. com.example.server)
- Do NOT put shorthand sub-package names in backticks (e.g. services, repositories)
- List sub-packages as plain text descriptions, not backtick-quoted paths}

## Documentation
{Only include documentation links for files that ACTUALLY exist in the repo.
Do NOT use template variables like {project_name} inside backticks.}

## AI Awareness Framework

This project uses the AI Awareness framework for structured development.

### Available Skills

- **aa-task-flow** - Structured workflow (Raw Prompt → PR)
  - Phases: Understand → Plan → Code → Document
  - Integrates with Jira/Confluence
  - Automated testing and code review

- **aa-task-flow-resume** - Resume existing task from OnGoingTasks/
- **aa-task-flow-remember** - Quick context recovery if Claude forgets
- **aa-task-flow-review** - Review branch diff before PR (saves to reviews_root, git-ignored)
- **aa-review-pr** - Review any PR by number/URL, supports multiple PRs in parallel, posts PR comments
- **aa-commit** - Clean, human-readable git commits
- **aa-pr** - Create PRs using project template
- **aa-task-flow-planner** - Plan large features: Jira tickets, spec, raw prompts, story branch
- **aa-ticket-creator** - Create one PR-sized Jira ticket under an epic (fast path; sibling of the planner)
- **aa-api-dd-compare** - Audit code assumptions vs production via Datadog traces; emit fix tickets (on-demand; needs Datadog MCP)
- **aa-dd-api-performance** - Recurring Datadog API-performance sweep: gate on p95/error thresholds, sample traces, maintain per-env per-API reports with change detection (on-demand; needs Datadog MCP)
- **aa-init-skills** - Configure local paths (one-time setup)
- **aa-init-mcps** - Setup Jira/Confluence MCP (one-time setup)

### Background Agents

Agents for parallel/background tasks:
- **aa-test-runner** (Haiku) - Run tests in background
- **aa-code-reviewer** (Opus) - Parallel code review
- **aa-doc-writer** (Haiku) - Generates ticket.md, pr-description.md
- **aa-commit-writer** (Haiku) - Write commit messages
- **aa-pr-writer** (Haiku) - Write PR title + body

See \`.claude/agents/README.md\` for details.

### When to Use Which Skill?

| Situation | Use This Skill |
|-----------|---------------|
| Planning a large multi-PR feature (architecture + spec + Story + story branch + N sub-task prompts) | \`aa-task-flow-planner\` |
| Spinning off one PR-sized ticket under an epic (one Task, no spec/decomposition/branch) | \`aa-ticket-creator\` |
| Auditing why a production endpoint is slow/wrong against the code (Datadog trace) | \`aa-api-dd-compare\` |
| Recurring sweep to find/track which APIs are slow (Datadog window scan) | \`aa-dd-api-performance\` |
| Starting a brand new task | \`aa-task-flow\` |
| Closed Claude and want to continue a task | \`aa-task-flow-resume\` |
| Claude forgot what we're working on (same session) | \`aa-task-flow-remember\` |
| Claude is confused about current phase | \`aa-task-flow-remember\` |
| Code complete - want to review before commit | \`aa-task-flow-review\` |
| Review a PR by number or URL | \`aa-review-pr\` |
| Review multiple related PRs together | \`aa-review-pr 219 220 221\` |
| Post review comments on a PR | \`aa-review-pr\` (asks before posting) |
| Ready to commit changes | \`aa-commit\` |
| Ready to open a pull request | \`aa-pr\` |
| Need to set up paths and config | \`aa-init-skills\` |
| Need Jira/Confluence integration | \`aa-init-mcps\` |

### Getting Started

First time:
\`\`\`bash
> aa-init-skills
\`\`\`

Daily workflow:
\`\`\`bash
> aa-task-flow
\`\`\`
\`\`\`

**For Maven (Spring Boot):**
```markdown
### Setup
\`\`\`bash
mvn install
\`\`\`

### Build
\`\`\`bash
mvn package -DskipTests
\`\`\`

### Test
\`\`\`bash
mvn test
\`\`\`

### Run
\`\`\`bash
mvn spring-boot:run
\`\`\`
```

**For Node/npm:**
```markdown
### Setup
\`\`\`bash
npm install
\`\`\`

### Build
\`\`\`bash
npm run build
\`\`\`

### Test
\`\`\`bash
npm test
\`\`\`

### Run
\`\`\`bash
npm start
\`\`\`
```

**Always add the version footer at the end of AGENTS.md:**
```markdown
**Framework Version**: AI Awareness v{FRAMEWORK_VERSION}
**Last Updated**: {current month and year}
**Project Namespace**: {namespace} ({project_name})
```

**Customize paths and modules** based on actual project structure. Before finalizing:
- Verify every backtick-quoted path actually exists in the repo
- Replace all template variables (`{project_name}`, `{STANDARDS_DIR}`) with real values
- Remove any backtick-quoted paths that don't correspond to real files/directories
- Use plain text (no backticks) for naming conventions, patterns, and runtime URLs

**If migrating from existing CLAUDE.md (saved in Step 5):**
Merge any project-specific content from the old CLAUDE.md into AGENTS.md:
- Project descriptions → project description section
- Development guidelines → new section in AGENTS.md
- AI assistant guidelines → new section in AGENTS.md
- Skills/agents info → already covered by the AI Awareness Framework section above
- Discard anything that duplicates what AGENTS.md already covers

## Step 13: Setup Templates

**Two core rules:**

1. **The framework NEVER installs PR or commit templates into `.claude/templates/`.** Project repos hold these at standard locations (root `PULL_REQUEST_TEMPLATE.md`, `.github/`, `docs/templates/`, etc.); installing under `.claude/` creates a duplicate source of truth that the `aa-pr` and `aa-commit-writer` flows would have to disambiguate at runtime. If you find `.claude/templates/pr-template.md` or `.claude/templates/commit-template.md` in a target project, it's leftover drift from a pre-fix version — delete it (see Step 13c at the end of this section).

2. **The full Step 13 install flow (scan-then-prompt-then-install) runs ONLY during `aa-install` (fresh installs).** During `aa-upgrade`, Step 13 is skipped — the upgrade NEVER installs PR/commit templates into a target. The only template-related work an upgrade does is Step 13c (delete any legacy `.claude/templates/{pr,commit}-template.md` duplicates). If `templates/pr-template.md` or `templates/commit-template.md` appears in CHANGED_FILES for an upgrade, the Writer agents IGNORE it. Rationale: an upgrade has no way to know whether the target's existing PR template at a standard location is the framework's default or the team's customised version. Re-installing under a different path (`.github/PULL_REQUEST_TEMPLATE.md` when the team has root `PULL_REQUEST_TEMPLATE.md`) creates the duplicate-source-of-truth problem v7.0.0 explicitly fixes. v6.10.0 upgrades did this incorrectly — example-service ended up with both root-level and `.github/` PR templates after its upgrade. v7.0.0 closes the gap.

**PR Template:**

Scan for existing PR template in standard locations:
```bash
PR_TEMPLATE=""
for f in PULL_REQUEST_TEMPLATE.md .github/PULL_REQUEST_TEMPLATE.md \
         .github/pull_request_template.md .github/PULL_REQUEST_TEMPLATE/default.md \
         docs/templates/pr-template.md; do
  [ -f "$f" ] && PR_TEMPLATE="$f" && break
done
```

**If found:** Keep it where it is. The `aa-pr` skill auto-detects templates at these standard locations. No need to copy or move. Skip the install prompt entirely — the project already has a PR template and overwriting it would clobber their convention.
```
Found PR template at: {PR_TEMPLATE}
The aa-pr skill will use it directly. No framework template will be installed.
```

**If NOT found:**
```
No PR template found. Options:

1. Create one using framework default (Recommended)
2. Paste your own template content
3. Skip

Your choice?
```

If choice 1:
```bash
# Use project root (GitHub standard) — NEVER .claude/templates/
cp {framework_path}/templates/pr-template.md PULL_REQUEST_TEMPLATE.md
```

If choice 2: Ask user to paste content, write to `PULL_REQUEST_TEMPLATE.md`.

**Commit Template:**

Scan for existing commit template (expanded vs pre-v6.10.0 — only checking one path was missing several conventional locations):

```bash
COMMIT_TEMPLATE=""
for f in docs/templates/commit-template.md .gitmessage .github/commit-template.md \
         .github/COMMIT_TEMPLATE.md docs/commit-template.md; do
  [ -f "$f" ] && COMMIT_TEMPLATE="$f" && break
done
# Also honour core.commitTemplate if the team uses git config to point at one
if [ -z "$COMMIT_TEMPLATE" ]; then
  configured=$(git config --get commit.template 2>/dev/null)
  [ -n "$configured" ] && [ -f "$configured" ] && COMMIT_TEMPLATE="$configured"
fi
```

**If found:** keep it in place. Same rule as PR template — don't install a framework duplicate. Skip the install prompt.
```
Found commit template at: {COMMIT_TEMPLATE}
The aa-commit-writer flow will use it directly. No framework template will be installed.
```

**If NOT found:**
```
No commit message template found.

1. Use the framework default template (Recommended)
2. Skip

Your choice?
```

If choice 1:
```bash
mkdir -p docs/templates
cp {framework_path}/templates/commit-template.md docs/templates/
```

**Step 13c: Cleanup of pre-fix `.claude/templates/` duplicates**

Older framework versions (and Writer agents misinterpreting the structural routing rule) sometimes copied `pr-template.md` / `commit-template.md` into `.claude/templates/` mirroring how `.claude/skills/` and `.claude/agents/` work. That path is wrong — it creates a second source of truth that `aa-pr` and `aa-commit-writer` would have to choose between at runtime. Detect and remove:

```bash
DELETED_DUPLICATES=()
for f in .claude/templates/pr-template.md .claude/templates/commit-template.md; do
  if [ -f "$f" ]; then
    rm "$f"
    DELETED_DUPLICATES+=("$f")
  fi
done
# Remove the directory if it's now empty
[ -d .claude/templates ] && rmdir .claude/templates 2>/dev/null

if [ ${#DELETED_DUPLICATES[@]} -gt 0 ]; then
  echo "Removed redundant template duplicates from .claude/templates/:"
  printf '  - %s\n' "${DELETED_DUPLICATES[@]}"
  echo "Project templates at standard locations are the single source of truth."
fi
```

This cleanup runs unconditionally on both `aa-install` and `aa-upgrade` — the `.claude/templates/` location was never correct, so removing it doesn't risk losing tuning. If a project genuinely customized one of those duplicates (rare; nothing reads from there), that's a one-time loss the team will catch in their diff review.

## Step 14: Generate ERD Documentation (Backend Projects)

**Only for backend projects with a database.**

**Detect database layer:**
```bash
# Check for Flyway migrations
FLYWAY_DIR=""
for dir in src/main/resources/db/migration module-migrator/src/main/resources/db/migration; do
  if [ -d "$dir" ]; then
    FLYWAY_DIR="$dir"
    migration_count=$(ls $dir/*.sql 2>/dev/null | wc -l)
    echo "Found $migration_count Flyway migrations in: $dir"
  fi
done

# Check for JPA entities
ENTITY_COUNT=$(find . -name "*.java" -path "*/entities/*" 2>/dev/null | wc -l)
echo "Found $ENTITY_COUNT JPA entity files"
```

**If migrations or entities found, ask user:**
```
Your project has a database layer:
- {migration_count} Flyway migrations in {dir}
- {entity_count} JPA entities

Would you like me to generate docs/erd.md?

This will:
1. Read all migrations/entities to understand your schema
2. Generate a Mermaid ERD diagram with all tables and relationships
3. Document each table's columns, types, and constraints
4. Save to docs/erd.md

The ERD will be kept updated automatically - when aa-task-flow detects
new database migrations, it will prompt you to update docs/erd.md.

Generate ERD? (y/n)
```

**If yes:**

1. Read all Flyway migration files (in version order) OR scan JPA entity files
2. Extract: table names, columns, types, constraints, foreign keys, indexes
3. Generate `docs/erd.md`:

```markdown
# {project_name} - Database ERD

## Entity Relationship Diagram

\`\`\`mermaid
erDiagram
    TABLE_A ||--o{ TABLE_B : "has many"
    TABLE_A {
        bigint id PK
        varchar name
        timestamp created_at
    }
    TABLE_B {
        bigint id PK
        bigint table_a_id FK
        varchar status
    }
\`\`\`

## Tables

### table_a
{Description of what this table stores}

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | bigint | PK, auto-increment | Primary key |
| name | varchar(255) | NOT NULL | ... |
| created_at | timestamp | NOT NULL, default now() | ... |

### table_b
...

## Relationships
- `table_a` 1:N `table_b` (via table_b.table_a_id)
- ...

## Migration History
| Version | Name | Description |
|---------|------|-------------|
| V1.0 | create_table_a | Initial table_a creation |
| V1.1 | create_table_b | Added table_b with FK to table_a |
| ... | ... | ... |
```

4. Update AGENTS.md to reference `docs/erd.md` in Documentation section
5. Store ERD path in config_hints.json for aa-task-flow reference:
   ```json
   "documentation": {
     "erd": "docs/erd.md"
   }
   ```

**aa-task-flow integration:**
When aa-task-flow detects database-related changes (new migrations, entity modifications), it will prompt:
```
Database changes detected. Update docs/erd.md?
- Yes → I'll update the ERD with new tables/columns
- No → Skip (remember to update it later)
```

## Step 15: Update .gitignore

```bash
grep -q ".claude/skill.config" .gitignore || {
  echo "" >> .gitignore
  echo "# AI Awareness - Claude Code" >> .gitignore
  echo ".claude/skill.config" >> .gitignore
}
grep -q ".claude/settings.local.json" .gitignore || {
  echo ".claude/settings.local.json" >> .gitignore
}
grep -q ".claude/reviews/" .gitignore || {
  echo ".claude/reviews/" >> .gitignore
}
```

Both `.claude/skill.config` and `.claude/reviews/` are an **explicit install guarantee** — each `grep || echo` is idempotent (added only if absent), so re-runs and upgrades never duplicate the line.

**What gets ignored (user-specific, NOT committed):**
- `.claude/skill.config` - User-specific paths (tasks root, docs root); also written by the read-only review skills on schema bump
- `.claude/settings.local.json` - User-specific Claude settings overrides
- `.claude/reviews/` - Review output written by `aa-review-pr` / `aa-task-flow-review`

**Note:** the read-only review skills (`aa-review-pr`, `aa-task-flow-review`) write to `.claude/skill.config` (schema bump) and `.claude/reviews/`, both inside the repo tree. Their "no tracked-file modification" guarantee depends on this step always git-ignoring both paths — that is why this install adds them explicitly rather than relying on the project's `.gitignore` covering them by accident.

## Step 15b: Update .dockerignore (if Dockerfile exists)

```bash
if [ -f Dockerfile ] || [ -f dockerfile ] || ls Dockerfile.* 2>/dev/null | head -1 >/dev/null; then
  touch .dockerignore
  for pattern in ".claude/" "AGENTS.md" "CLAUDE.md" "docs/ai-rules/" "docs/coding-standards/" ".cursor/rules/" ".aiRules/"; do
    grep -qF "$pattern" .dockerignore || echo "$pattern" >> .dockerignore
  done
  echo "Updated .dockerignore with AI Awareness exclusions"
fi
```

**Why:** AI Awareness files are development-time only and should not be included in Docker build contexts. This:
- Reduces Docker build context size
- Speeds up builds by excluding unnecessary files
- Prevents AI configuration exposure in container images

**What gets committed (project-level, shared):**
- `.claude/config_hints.json` - Project configuration
- `.claude/settings.json` - Shared Claude permissions
- `.claude/agents/` - Agent definitions
- `.claude/skills/` - Skill definitions

## Step 15c: Append AI Awareness Update History (per-platform, workspace audit only)

**Code-repo installs skip this step.** Code repos get framework files (`.claude/`, AGENTS.md footer with version) and nothing more. Framework metadata (audit trails, recorded improvements) belongs in workspace/docs repos, not deliverable code.

**Workspace audit goes per-platform** (NEW in v6.10.0). A workspace (e.g., `Example_Coding_Tasks`) typically hosts multiple associated projects — a Backend code repo, a Frontend code repo, eventually a mobile app. They're upgraded independently. The audit dir reflects that:

```
dirname({install_root})/{ProjectName}_AIAwarenessFramework/
├── update-history.md            # Workspace-tier upgrades only (workspace install itself was upgraded)
├── Backend/
│   ├── update-history.md        # When the Backend code repo was upgraded
│   └── improvements/            # aa-record-improvement output for Backend
│       └── {YYYY-MM-DD}-{slug}.md
├── Frontend/
│   ├── update-history.md
│   └── improvements/
└── (future: Mobile/, etc.)
```

For example, the Example workspace at `~/repos/example/Example_Coding_Tasks/` gets `~/repos/example/Example_AIAwarenessFramework/` (sibling of `_Coding_Tasks`), with `Backend/` and `Frontend/` subdirs for each project. Concurrent Backend + Frontend workers write to disjoint paths — no file-level collisions.

### Helper: `resolve_target_platform()`

Determines which platform an aa-install or aa-upgrade run is acting on. Reverse-lookups the target's git remote against the workspace's `github_repos`:

```bash
# Returns "Backend", "Frontend", "workspace", or empty (unresolvable).
# Workspace-tier targets (the workspace install itself, not a code repo) return "workspace".
# Code-repo targets are matched against github_repos in the linked workspace's config_hints.json.
resolve_target_platform() {
  local target="$1"
  local workspace_config="$2"   # path to workspace's .claude/config_hints.json (may be empty if target IS the workspace)

  # 1. If target IS a workspace install, return "workspace" sentinel
  if jq -e '.install_role == "workspace"' "$target/.claude/config_hints.json" >/dev/null 2>&1; then
    echo "workspace"
    return 0
  fi

  # 2. If the target's own config has parent_workspace_platform persisted, use it (set on first upgrade)
  local persisted=$(jq -r '.parent_workspace_platform // ""' "$target/.claude/config_hints.json" 2>/dev/null)
  if [ -n "$persisted" ] && [ "$persisted" != "null" ]; then
    echo "$persisted"
    return 0
  fi

  # 3. Reverse-lookup git remote → github_repos in the linked workspace.
  # If we have no workspace config to look up against, give up — caller falls back to prompt.
  if [ -z "$workspace_config" ] || [ ! -f "$workspace_config" ]; then
    return 0
  fi

  local remote_url=$(git -C "$target" remote get-url origin 2>/dev/null)
  # Normalize git@github.com:owner/repo.git → owner/repo
  local owner_repo=$(echo "$remote_url" \
    | sed -E 's#^git@github.com:##; s#^https?://github.com/##; s#\.git$##')

  jq -r --arg owner_repo "$owner_repo" '
    .github_repos // {} | to_entries[]
    | select(.value == $owner_repo)
    | .key
  ' "$workspace_config" | head -1
}
```

The helper does not write any state. Callers persist `parent_workspace_platform` themselves (see the Workspace-dir setup block below) after a user confirms the picked platform — the resolver itself stays pure so it can be called from contexts that don't have write permission on the target's config.

### Workspace dir + per-platform subdir setup

The block below uses a `SKIP_AUDIT` flag instead of `return` so it can be embedded inline in any caller (Writer agent, manual run, sourced helper) without needing function-context semantics:

```bash
SKIP_AUDIT=false

if [ "$INSTALL_ROLE" != "workspace" ]; then
  # Code-repo install: route audit to the LINKED workspace's per-platform subdir, not this code repo
  workspace_install_root="$LINKED_WORKSPACE_PATH"  # resolved earlier via linked-install detection (Phase 1 step 1a-2)
  if [ -z "$workspace_install_root" ]; then
    echo "Note: no linked workspace detected — skipping audit-entry write (code-repo install with no workspace pairing has no audit trail target)."
    SKIP_AUDIT=true
  fi
fi

if [ "$SKIP_AUDIT" = "false" ] && [ "$INSTALL_ROLE" != "workspace" ]; then
  PLATFORM=$(resolve_target_platform "$TARGET_PROJECT" "$workspace_install_root/.claude/config_hints.json")

  if [ -z "$PLATFORM" ]; then
    # Reverse-lookup failed. Prompt user once.
    platforms_list=$(jq -r '.platforms[]?' "$workspace_install_root/.claude/config_hints.json")
    echo "Could not auto-resolve which platform this target belongs to."
    echo "Workspace platforms: $platforms_list"
    echo "Pick one (will be persisted as parent_workspace_platform in this project's config_hints.json):"
    read -r PLATFORM
    # Persist into the target's config_hints.json so future upgrades skip this prompt
    tmp=$(mktemp)
    jq --arg p "$PLATFORM" '.parent_workspace_platform = $p' "$TARGET_PROJECT/.claude/config_hints.json" > "$tmp" \
      && mv "$tmp" "$TARGET_PROJECT/.claude/config_hints.json"
  fi
elif [ "$INSTALL_ROLE" = "workspace" ]; then
  workspace_install_root="$TARGET_PROJECT"
  PLATFORM="workspace"   # sentinel — write to root update-history.md, not a platform subdir
fi

# Everything below runs only when SKIP_AUDIT=false. Callers should gate the rest of the block
# on `[ "$SKIP_AUDIT" = "true" ] && skip-the-audit-write-or-exit-here`.
if [ "$SKIP_AUDIT" = "true" ]; then
  # Caller-specific bail: for aa-install/aa-upgrade Writer agents this means "no audit write,
  # continue with the rest of the install/upgrade normally."
  :
else

# Derive workspace dir name from project_name
project_name=$(jq -r '.project_name // .project.name' "$workspace_install_root/.claude/config_hints.json")
pascal_name=$(echo "$project_name" | awk -F'[_-]' '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)} 1' OFS='_')
fw_dir="$(dirname "$workspace_install_root")/${pascal_name}_AIAwarenessFramework"

# Pick the destination file based on platform
if [ "$PLATFORM" = "workspace" ]; then
  history_file="$fw_dir/update-history.md"
  improvements_dir="$fw_dir/improvements"   # rare: workspace-tier improvements (skill bug, etc.)
else
  history_file="$fw_dir/$PLATFORM/update-history.md"
  improvements_dir="$fw_dir/$PLATFORM/improvements"
fi

mkdir -p "$(dirname "$history_file")"
mkdir -p "$improvements_dir"

# Initialize the file with a header if it doesn't exist yet
if [ ! -f "$history_file" ]; then
  if [ "$PLATFORM" = "workspace" ]; then
    header_title="${pascal_name} — Workspace-tier Update History"
  else
    header_title="${pascal_name} — ${PLATFORM} Update History"
  fi
  cat > "$history_file" <<EOF
# $header_title

Audit trail of every \`aa-install\` and \`aa-upgrade\` run against this $([ "$PLATFORM" = "workspace" ] && echo "workspace's own install" || echo "$PLATFORM project"). Newest-first. Auto-appended by the framework; safe to read, do not hand-edit (entries below the most-recent one are immutable history).

EOF
fi

echo "Audit file: $history_file"
echo "Improvements dir: $improvements_dir"

fi  # end of "if SKIP_AUDIT == false" block opened above
```

### Entry format (compact, appended by aa-install / aa-upgrade)

```markdown
## YYYY-MM-DD — v{from} → v{to} (install | upgrade)

**Platform:** {Backend | Frontend | workspace}

**Framework changes applied:**
- {1–3 headline changes from the version delta — pull from CHANGELOG Summary lines}

**Project customizations preserved:**
- {1–3 specific items the framework kept: tuned thresholds, custom sections, override blocks. "n/a" for install.}

**Optimizer findings:** {one-line summary, or "Clean"}
```

Each entry is 7–13 lines. Each platform's `update-history.md` stays readable on one screen even after 10 upgrades.

### Why per-platform

- Backend and Frontend in the same workspace are upgraded independently. A single workspace-wide `update-history.md` (the v6.8.0 design) conflated them and lost the per-project version state.
- Concurrent workers writing improvements via `aa-record-improvement` need disjoint paths so they don't overwrite each other (v6.10.0 fix).
- The pattern matches existing per-platform conventions in the workspace: `Example_Coding_Tasks/Backend/` vs `/Frontend/`, `TasksSummary/Backend.md` vs `Frontend.md`.

### Migration / backward compatibility

- **Pre-v6.10.0 workspace-root `update-history.md`** (v6.8.0–v6.9.0): file stays in place at workspace root and is treated as the "workspace-tier audit". New per-platform entries go into the new `{Platform}/update-history.md`. No retroactive splitting of historical entries.
- **Pre-v6.4.0/v6.7.0 legacy subdirectories** (`update_reports/`, `planned_updates/`, `update_template/`, `README.md`): leave alone. Teams clean up at leisure with their own `rm -rf`. Framework doesn't auto-delete.
- **Pre-v6.10.0 code-repo `.claude/improvements/`**: backward-compat reader in `aa-add-improvement` checks both old and new locations. Logs a one-line warning if it finds legacy improvements asking the user to manually move them.

### Concurrent worker safety

Each platform writes to a different subdirectory. Within a platform, `update-history.md` is appended to by a single upgrade run (no concurrent upgrades to the same platform). Improvements are file-per-improvement (`{date}-{slug}.md`) so per-improvement writes never share a target file. Same-day-same-slug collisions (rare) append a numeric suffix.

## Step 16: Summary

Show user:

```
✅ AI Awareness installed for {project_name}!

What was set up:
- Project: {project_name}
- Tracker: {tracker.type}{if jira/linear and url set: " at {tracker.url}"}
- Tickets: {if single namespace: "{namespace}-XXX" | if multi: list all namespaces}
- Skills: aa-task-flow, aa-task-flow-planner, aa-ticket-creator, aa-api-dd-compare, aa-dd-api-performance, aa-task-flow-resume, aa-task-flow-remember, aa-task-flow-review, aa-review-pr, aa-commit, aa-pr, aa-init-skills, aa-init-mcps
- Agents: 5 agents (aa-test-runner, aa-code-reviewer, aa-doc-writer, aa-commit-writer, aa-pr-writer)
- AGENTS.md: Single source of truth (project docs + skills + agents)
- CLAUDE.md: Points to @AGENTS.md
- PR Template: PULL_REQUEST_TEMPLATE.md (or existing location)
- Commit Template: docs/templates/commit-template.md
- Universal Rules: critical-thinking.md, code-review.md, task.md
- Platform Rules: [if applicable]
- Settings: Claude Code permissions configured

Next steps:

1. Configure your local paths:
   > aa-init-skills

   You'll be asked for:
   - Platform (Backend/Frontend/iOS/Android)
   - Tasks root: Path to {project_name}_Coding_Tasks/{Platform}
   - Docs root: Path to {project_name}_DocsProject (optional)

2. Set up issue-tracker integration:
   > aa-init-mcps

   For GitHub Issues (default) this just verifies `gh auth status` — no MCP needed.
   For Jira (Atlassian) or Linear it configures the corresponding MCP server.

3. Start your first task:
   > aa-task-flow

   Choose:
   - Ticket-first (include the ticket ID in your prompt, e.g., "CORE-123: Fix search sorting")
   - Ticket-late (if urgent or exploratory)

   **Multi-namespace projects:** Always include the ticket ID (e.g., CORE-123, OPS-456)
   in your prompt so aa-task-flow can determine the correct Jira space and branch prefix.

4. Commit and PR shortcuts:
   > aa-commit   (clean, human-readable commits)
   > aa-pr       (create PR from template)

Your project is now AI-ready with:
- Pattern consistency (production-proven rules)
- Team collaboration (external task visibility)
- Knowledge preservation (complete documentation)
- Safety guardrails (no main commits, mandatory tests)
- Agent readiness (AGENTS.md validated by rubric-scanner)

Welcome to AI Awareness!
```

## Step 16b: Language-Safety Guardrail (MANDATORY — install AND upgrade)

**Run this after skills/agents/rules are written, on every `aa-install` and `aa-upgrade`.** It is the hard backstop that prevents wrong-language noise from shipping (Java idioms in a Go/Ruby/iOS repo, dangling rule references). If it fails, **STOP and fix before committing** — do not hand a polluted install to the user.

**Run Step 6r (Resolve standards-path tokens) immediately BEFORE this guardrail** — also on every install and upgrade, in the main session once skills (Step 6) and agents (Step 11) are on disk. Step 6r resolves `{standards_location}` and rewrites dead `rules/universal/` references to the project's real standards path; running it first ensures this guardrail's dangling-rule-reference scan checks the resolved paths, not unresolved tokens. (On upgrade, both are invoked from aa-upgrade Phase 5 — Step 5a-1 then 5a-2.)

```bash
cd {target_project}
std="$(jq -r '.standards_location // "docs/ai-rules"' .claude/config_hints.json)"
stack="$(jq -r '.stack // .platform // "generic"' .claude/config_hints.json)"
violations=0

# (1) DANGLING RULE REFERENCES — every rule .md referenced by an installed skill/agent must exist in $std.
#     This is the bug that put jpa-repositories.md / transaction-boundaries.md into Go/Ruby reviews.
refs=$(grep -rhoE '[a-z0-9-]+\.md' .claude/skills .claude/agents 2>/dev/null \
        | grep -vE '^(SKILL|AGENT|README|CLAUDE|AGENTS)\.md$' | sort -u)
for r in $refs; do
  # only care about rule-style names (skip prose mentions of other docs)
  case "$r" in
    transaction-boundaries.md|jpa-repositories.md|api-conventions.md|query-efficiency.md|database-migrations.md|project-structure.md|coding-conventions.md|commands.md|metrics-collection.md|controller-error-handling.md|*-rule.md|*-policy.md|*-standards.md|*-conventions.md|*-handlers.md|database-*.md|go-*.md)
      if [ ! -f "$std/$r" ]; then echo "⚠️  dangling rule reference: $r (not in $std/)"; violations=$((violations+1)); fi ;;
  esac
done

# (2) FOREIGN-LANGUAGE IDIOMS — for non-JVM stacks, no Java/Gradle instructions should appear in installed skills/agents.
case "$stack" in
  java-spring-boot|jvm-generic|android|kotlin) ;;  # JVM-family: Java idioms are legitimate
  *)
    foreign=$(grep -rnoE 'gradlew|\*Test\.java|src/test/java|@RestController|@GetMapping|@RequestMapping|@Transactional|JpaRepository|@SpringBootTest|checkstyleMain|application\.yml' \
              .claude/skills .claude/agents 2>/dev/null \
              | grep -vE 'e\.g\.|example|Example|for Gradle|for Java|/Spring|detect|whichever|or the project' )
    if [ -n "$foreign" ]; then
      echo "⚠️  foreign-language (Java/Gradle) idioms in a '$stack' install — should be detected/branched, not hardcoded:"
      echo "$foreign" | head -20
      violations=$((violations + $(echo "$foreign" | grep -c .)))
    fi ;;
esac

if [ "$violations" -gt 0 ]; then
  echo "❌ Language-safety guardrail FAILED ($violations issue(s)). Fix before committing — see docs/plans/stack-agnostic-adaptation.md."
else
  echo "✅ Language-safety guardrail passed: no dangling rule refs, no foreign-language idioms for stack '$stack'."
fi
```

Notes:
- The idiom check **allowlists** lines that clearly frame Java as one labelled example (`e.g.`, `example`, `for Gradle`, `detect`, `whichever`, `or the project`) — those are the neutralized, detect-and-branch forms and are fine.
- For JVM-family stacks (`java-spring-boot`, `android`, `jvm-generic`, `kotlin`) the idiom check is skipped — Java/Gradle tokens are legitimate there. The dangling-reference check (1) always runs.

## Step 16c: Generate Skill Evals (skill-creator — MANDATORY)

After skills/agents are installed and the Step 16b guardrail passes, create evals for the **installed** skills so the team can verify skill behaviour in THIS project (skill + this project's rules/config + any project overrides).

1. **Prerequisite (MUST): the `skill-creator` plugin.** Detect it by whether `skill-creator:skill-creator` appears in this session's available skills. It is a **plugin, not a global skill** — do **not** test for `~/.claude/skills/skill-creator/`; that path never exists for a plugin and reports a false "missing". If you need a filesystem check, look for `skill-creator@claude-plugins-official` in `~/.claude/plugins/installed_plugins.json`. If genuinely missing, **STOP the install/upgrade** and guide the user:
   ```
   🛑 skill-creator is required for eval generation and is not installed.
   Install it, then re-run this install/upgrade:
     # Skip the next line if "claude-plugins-official" is already in
     # ~/.claude/plugins/known_marketplaces.json (marketplace already added).
     /plugin marketplace add anthropics/claude-plugins-official
     /plugin install skill-creator@claude-plugins-official
     /reload-plugins
   ```
   Do **NOT** proceed without it — eval generation is part of the process, not optional.
2. For each installed skill/agent (`.claude/skills/*`, `.claude/agents/*`), invoke `skill-creator` to **create an eval set**, stored at `.claude/skills/<name>/evals/` (skill-creator's convention takes precedence if it has one). Focus eval cases on each skill's safety-critical behaviours (e.g. aa-task-flow: on-main STOP, Change Class branch; aa-review-pr: loads only rules that exist in `standards_location`; aa-ticket-creator: asks for the epic, never searches).
3. Run each eval set once to record a passing baseline; report any failure to the user before finishing the install.
4. **⏱ Cost:** eval generation+baseline adds time at install. It runs once per skill version — upgrades only refresh evals for **changed** skills (see `aa-upgrade` Phase 5a-3).

Global skills (`aa-optimizer`, `aa-record-improvement`, `aa-global-pr-reviewer`) get their evals via `aa-install-tools` (same procedure, `~/.claude/skills/<name>/evals/`).

## Step 16d: Installed-Reference Validation (MANDATORY — install AND upgrade)

**Run after Step 16c, against the TARGET repo.** This is the backstop for the class of bugs that ship silently because every review thread is resolved and CI is green: doc-update steps pointing at files that don't exist in the target, an agent that's present + documented but invoked by no skill, a skill on disk that no routing table reaches, and install-resolved placeholders that never got resolved. None of these are caught by language/token guardrails. Collect **violations** (block) and **warnings** (report); on any violation, **STOP and fix before finalizing**.

```bash
cd {target_project}
viol=0; warn=0
SKILLS=.claude/skills; AGENTS=.claude/agents; AG=AGENTS.md
# On-demand allowlist: project artifacts intentionally not wired into a routing table / not skill-invoked.
ON_DEMAND='aa-optimizer|aa-record-improvement|aa-global-pr-reviewer|aa-task-flow-inspector'
# GLOBAL/command skills: legitimately referenced in AGENTS.md routing but NOT installed under .claude/skills
# (they live globally or are slash-commands). Never flag these as "routes to a missing skill".
GLOBAL_SKILLS='aa-upgrade|aa-install|aa-install-tools|aa-add-improvement|aa-record-improvement|aa-optimizer|aa-global-pr-reviewer'

# (1) ORPHANED AGENTS — on disk + named in AGENTS.md, but invoked by no installed skill.
#     Only SKILL.md bodies count as invocation sites — a README/catalog mention is NOT an invocation
#     (that miss is exactly how an orphaned agent hides: the catalog still lists it after its real
#     invocation sites were deleted from the skills).
for d in "$AGENTS"/*/; do
  [ -d "$d" ] || continue; a=$(basename "$d")
  echo "$a" | grep -qE "$ON_DEMAND" && continue
  invoked=$(grep -rl --include='SKILL.md' -F "$a" "$SKILLS" 2>/dev/null | head -1)
  in_agents=$(grep -lF "$a" "$AG" 2>/dev/null | head -1)
  if [ -z "$invoked" ] && [ -n "$in_agents" ]; then
    echo "❌ orphaned agent: '$a' is documented in AGENTS.md but invoked by no installed skill"; viol=$((viol+1))
  elif [ -z "$invoked" ]; then
    echo "⚠️  agent '$a' is on disk but invoked by no skill (mark on-demand or wire it up)"; warn=$((warn+1))
  fi
done

# (2) AGENTS.md routing → skills must exist on disk (excluding global/command skills); skills on disk
#     should be reachable. Capture-then-count (not `for … in $(…)`) → correct under both bash and zsh.
miss=$(grep -oE 'aa-[a-z-]+' "$AG" 2>/dev/null | sort -u | while IFS= read -r s; do
  [ -z "$s" ] && continue
  echo "$s" | grep -qE "^($GLOBAL_SKILLS)$" && continue
  [ ! -d "$SKILLS/$s" ] && [ ! -d "$AGENTS/$s" ] && echo "❌ AGENTS.md routes to '$s' which is not installed under .claude/skills or .claude/agents"
done)
[ -n "$miss" ] && { printf '%s\n' "$miss"; viol=$((viol + $(printf '%s\n' "$miss" | grep -c .))); }
for d in "$SKILLS"/*/; do
  [ -d "$d" ] || continue; s=$(basename "$d")
  echo "$s" | grep -qE "$ON_DEMAND" && continue
  reachable=$(grep -lF "$s" "$AG" 2>/dev/null; grep -rl --include='SKILL.md' -F "$s" "$SKILLS" 2>/dev/null | grep -v "/$s/")
  [ -z "$reachable" ] && { echo "⚠️  skill '$s' is installed but reachable from no routing table or other skill"; warn=$((warn+1)); }
done

# (3) UNRESOLVED INSTALL PLACEHOLDERS — narrowly: an unresolved subagent/agent-type reference that will
#     ERROR at runtime (e.g. subagent_type="{project}-code-reviewer"). NOT broad template tokens like
#     {project_name}/{platform}/{namespace}, which skills legitimately carry and resolve at runtime —
#     flagging those floods the report with false positives and gets the whole check ignored.
ph=$(grep -rnoE '\{[a-z_]+\}-[a-z-]*reviewer|subagent_type=["'\'']?\{[a-z_]+\}' "$SKILLS" "$AGENTS" 2>/dev/null)
if [ -n "$ph" ]; then echo "❌ unresolved agent-type placeholders:"; echo "$ph" | head -20; viol=$((viol + $(echo "$ph" | grep -c .))); fi

# (4) OPERATIVE FILE PATHS — repo-relative paths referenced in skills/agents that don't exist (warn).
#     Exclude obvious illustrative paths (com/example, path/to, your-, <placeholder>).
miss4=$(grep -rhoE '(docs|src|app|lib)/[A-Za-z0-9_./-]+\.(md|java|kt|go|rb|ts|tsx|sql|ya?ml)' "$SKILLS" "$AGENTS" 2>/dev/null \
        | grep -vE 'example|path/to|your[-/]|/foo/|/bar/|<' | sort -u \
        | while IFS= read -r p; do [ -z "$p" ] && continue; [ -e "$p" ] || echo "⚠️  referenced path not in repo: $p"; done)
[ -n "$miss4" ] && { printf '%s\n' "$miss4"; warn=$((warn + $(printf '%s\n' "$miss4" | grep -c .))); }

echo "---"
if [ "$viol" -gt 0 ]; then
  echo "❌ Installed-reference validation FAILED: $viol violation(s), $warn warning(s). Fix before finalizing."
else
  echo "✅ Installed-reference validation passed: 0 violations, $warn warning(s)."
fi
```

**Tuning notes:** the `ON_DEMAND` allowlist names artifacts intentionally invoked by humans, not routed (extend it per project rather than suppressing a real orphan). Check (4) bounds itself to `docs|src|app|lib` path-like references to avoid flagging illustrative examples; a hit means a skill will instruct Claude to read/update a file the repo doesn't have. Record the full violation+warning list — it becomes part of the install report and (on upgrade) the upgrade PR body, so reviewers see exactly what was checked.

## Step 17: Post-Setup Validation (Optional)

**Use rubric-scanner to validate AGENTS.md quality:**

If you have access to the example-playbook repo:

```bash
cd ~/repos/example/example-playbook
bun run scanner:eval --repos file://{target_project_path}
```

**What it validates:**
- ✓ Setup/build/test/run commands are runnable
- ✓ All referenced file paths exist
- ✓ All documented URLs are reachable

**Example output:**
```
{project_name} - Score: 0.85/1.0

Commands: 4/4 verified ✓
Paths: 12/14 verified (2 broken)
URLs: 5/5 verified ✓

Issues:
- Broken path: $STANDARDS_DIR/old-rule.md (AGENTS.md:45)
- Broken path: docs/old-api.md (AGENTS.md:67)
```

**If score < 1.0:**
- Fix broken paths in AGENTS.md
- Fix broken URLs
- Update commands if not runnable
- Re-run scanner to verify fixes

## Project Configuration Reference

After setup completes, your project has these configurations:

**Ticket Format:** {project_namespace}-XXX (from config_hints.json)
**Branch Format:** feature/{lowercase_namespace}-XXX-description
**Tracker:** {tracker.type} (from config_hints.json; `tracker.url` set for jira/linear)

**External Tasks:** {project_name}_Coding_Tasks structure (configured during aa-init-skills)
**Documentation:** {project_name}_DocsProject standard locations (optional)
**the base framework:** Rules include the base framework framework patterns (if Java Spring Boot)

These values are read from `.claude/config_hints.json` at runtime by skills and can be updated if your project conventions change.

## Versioning

See `VERSIONING.md` for the full versioning strategy:
- **Decimal updates** (2.1 → 2.11): Bug fixes, wording, new optional rules
- **Major updates** (2.x → 3.0): New skills/agents, breaking changes, workflow changes

Current version is read from the framework's `config_hints.json` (`framework_version` field).

**Where version is tracked:**
- `config_hints.json` (this framework root) — canonical source of truth for the current framework version
- `CLAUDE.md` (this framework) — `Version:` line kept in sync for human readability
- `.claude/config_hints.json` → `framework_version` (each target project) — tracks which version was installed
- `AGENTS.md` footer (each target project) — human-readable version display
- `CHANGELOG.md` (this framework) — detailed per-version changes for incremental updates

**When bumping framework version:**
1. Update `framework_version` in this framework's `config_hints.json`
2. Update `Version:` line in this framework's `CLAUDE.md`
3. Add entry to `CHANGELOG.md` with file changes
4. Commit to framework repo

## Updating Existing Projects

When updating an already-installed project (not fresh setup):

1. Read `framework_version` from this framework's `config_hints.json` → `FRAMEWORK_VERSION`
2. Read the target project's `.claude/config_hints.json` → `framework_version` (= `PROJECT_VERSION`)
3. Compare:
   - If `PROJECT_VERSION` == `FRAMEWORK_VERSION` → project is up to date (run Smart Diff to check for drift, see Step 4b)
   - If `PROJECT_VERSION` < `FRAMEWORK_VERSION` → apply incremental updates
4. Read `CHANGELOG.md` and apply all changes listed after `PROJECT_VERSION`
5. Preserve project-specific customizations (custom agents, adapted rules, deliberate overrides)
6. Update `config_hints.json` → `framework_version` to `FRAMEWORK_VERSION`
7. Update `AGENTS.md` footer to match

**Example:** Project is on v2.11, framework is at 2.12 → apply only the v2.12 changes from CHANGELOG.md.
