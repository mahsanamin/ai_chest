---
name: aa-install
description: Install AI Awareness framework into a new project. Uses Content Adaptation Pipeline for stack-aware installation. Say "aa-install" or "install AI awareness".
disable-model-invocation: true
---

# Initialize Project

Install the AI Awareness framework into a new project using the Content Adaptation Pipeline for intelligent, stack-aware file adaptation.

## When to Use

- Fresh install of AI Awareness into a project that has never had it
- Project has NO `.claude/config_hints.json` file
- If the project already has `config_hints.json`, use `aa-upgrade` instead

## Prerequisites

- Working directory: `~/ai-awareness-framework` (framework repo)
- Target project path provided by user
- Claude Opus 4.6 recommended for accuracy

## What This Skill Does

6-phase process with context-efficient agent delegation:
1. **Validate & Gather** — Prerequisites, target path, config → writes `_install_config.json`
2. **Bootstrap** _(greenfield only)_ — `claude init`, deep-read project, generate project-aligned rules
3. **Research** — Stack Analyzer detects stack → writes `_stack_mapping.md`
4. **Install** — Structure Writer + Rules Writer + ERD Writer (parallel), then Config Writer (sequential) → writes `_install_manifest.json`
5. **Verify** — Contamination Checker checks for foreign-stack references in clean context
6. **Summary** — Report what was installed, clean up temp files

**Context efficiency:** All agents communicate through files on disk, not conversation context. The main session stays thin — it orchestrates agent launches and user interactions but never reads setup.md or framework source files itself.

## Phase 1: Validate and Gather Information

This phase runs in the **main session** (interactive with user). Everything collected is written to `_install_config.json` so downstream agents don't depend on conversation history.

**Bash execution rule:** Run each bash command individually — do NOT chain commands with `&&` or `;`. Use absolute paths (e.g., `{TARGET_PROJECT}/CLAUDE.md`) instead of `cd` + relative paths. This avoids permission warnings about ambiguous command separators.

### 1a. Ask for Target Project

**🚨 CRITICAL: Ask ONLY this single free-text question. Do NOT present a menu, numbered list, or suggested paths. No "Current directory" option. No "Choose from:" option. Just this one line:**

```
What is the full path to your target project?
```

Wait for the user to type the actual path. Validate the directory exists. Store as `TARGET_PROJECT`.

Check if this is a fresh install or an existing one:
```bash
ls {TARGET_PROJECT}/.claude/config_hints.json 2>/dev/null
```

If the file exists (output shows the path), this is an **EXISTING_INSTALL**.
If the file does not exist (no output or "No such file"), this is a **FRESH_INSTALL** — continue to Step 1b.

**If EXISTING_INSTALL:**
```
This project already has AI Awareness installed (found .claude/config_hints.json).

Use the "aa-upgrade" skill instead to incrementally update to the latest version.
```
Stop here.

### 1a-2. Detect install_role (NEW in v6.7.0)

`install_role` must be resolved before Step 1b so we can decide whether to create a feature branch. Workspace installs commit directly to their default branch and do not use feature branches or PRs — creating one hides the install commits where the team won't see them.

Auto-detect per `setup.md` Step 4c (the project doesn't yet have `config_hints.json`, so always auto-detect on a fresh install):

```bash
# See setup.md Step 4c for the detect_install_role helper definition.
INSTALL_ROLE=$(detect_install_role "{TARGET_PROJECT}")
echo "Install role: $INSTALL_ROLE"
```

If auto-detection lands on something the user doesn't expect, surface it once before continuing — the user can abort and re-run after setting `install_role` explicitly in a pre-existing `config_hints.json`, or just continue if the detection is fine.

`INSTALL_ROLE` is used by:
- **Step 1b** below — decides whether to create a feature branch
- **Phase 4 Structure Writer** — filters which skills get installed (`target-project` skills for code-repo; `workspace` skills for workspace)
- **Step 10 of `setup.md`** — persisted into `config_hints.json` so future upgrades skip detection

### 1b. Create Install Branch — code-repo installs only

**Workspace installs skip this step.** Workspace/docs/tasks repos commit directly to their default branch. Creating a feature branch for them hides the install commits on a branch the team doesn't look at.

```bash
if [ "$INSTALL_ROLE" = "workspace" ]; then
  current_branch=$(git -C {TARGET_PROJECT} branch --show-current)
  echo "Workspace install — staying on branch '$current_branch' (no feature branch created)."
  BRANCH_NAME="$current_branch"
else
  # code-repo install — original branch-creation flow
  default_branch=$(git -C {TARGET_PROJECT} symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
  [ -z "$default_branch" ] && default_branch="main"
  current_branch=$(git -C {TARGET_PROJECT} branch --show-current)
  DEFAULT_BRANCH="$default_branch"
  CURRENT_BRANCH="$current_branch"
fi
```

**For code-repo installs only** (`INSTALL_ROLE = code-repo`):

**If CURRENT_BRANCH != DEFAULT_BRANCH:** The user is already on a feature branch. Use it silently:
```
Using current branch: {CURRENT_BRANCH}
```
Skip the branch creation prompt entirely.

**If CURRENT_BRANCH == DEFAULT_BRANCH:** Ask the user:
```
You're on {DEFAULT_BRANCH}. Installation should be on a dedicated branch.

1. Create feature/ai-awareness-setup from latest {DEFAULT_BRANCH} (Recommended)
2. Use a different branch name
3. Continue on {DEFAULT_BRANCH} anyway

Your choice?
```

**If choice 1 or 2:** Run these commands individually:
```bash
git -C {TARGET_PROJECT} pull origin {DEFAULT_BRANCH}
```
```bash
git -C {TARGET_PROJECT} checkout -b feature/ai-awareness-setup
```

**If choice 3:** Continue on the default branch (user's choice).

Store `BRANCH_NAME` for reference in the summary.

### 1c. Validate Prerequisites

Follow `setup.md` Step 1 (Validate Prerequisites):
- Check GitHub CLI (gh) installation and authentication
- Validate framework files exist (skills/, rules/, settings.json, config_hints.json)
- Install AI Optimizer skill globally to `~/.claude/skills/`
- Install framework agents globally to `~/.claude/agents/` (copy each `agents/*/AGENT.md` as `~/.claude/agents/{agent-name}.md`)
- Install framework scripts globally to `~/.claude/scripts/` (copy `scripts/` directory, `chmod +x` all `.sh` files)

Read the framework version (canonical source):
```bash
FRAMEWORK_VERSION=$(grep '"framework_version"' {FRAMEWORK_PATH}/config_hints.json | sed 's/.*: *"\(.*\)".*/\1/' | tr -d '[:space:]')
echo "Framework version: v$FRAMEWORK_VERSION"
```

Store `FRAMEWORK_VERSION` — this is written to `_install_config.json` and used by the Config Writer.

### 1d. Gather Project Configuration

Follow `setup.md` Step 3 (Gather Project Configuration):
- Ask for project name
- Ask which issue tracker (default GitHub Issues; Jira / Linear / none). Only ask single vs. multiple Jira spaces when the user picks Jira (GitHub/Linear have no "spaces" — the repo is the scope)
- Collect namespace prefix(es)

Store: `PROJECT_NAME`, `TRACKER` (`{ "type": "...", "url": "..." }`, default `github`), `NAMESPACE` (or `NAMESPACES` list).

### 1e. Check Existing State

Follow `setup.md` Step 4, Step 4a only (existence checks — do not run Step 4b version check):

Run as a single script (no `&&` chaining):
```bash
ls {TARGET_PROJECT}/CLAUDE.md {TARGET_PROJECT}/AGENTS.md {TARGET_PROJECT}/.claude/settings.json 2>/dev/null
ls -d {TARGET_PROJECT}/.claude/skills {TARGET_PROJECT}/.claude/agents 2>/dev/null
ls -d {TARGET_PROJECT}/docs/ai-rules {TARGET_PROJECT}/docs/coding-standards {TARGET_PROJECT}/.cursor/rules {TARGET_PROJECT}/.claude/rules {TARGET_PROJECT}/.aiRules 2>/dev/null
```

Note which files/directories exist from the output. Store the results for `_install_config.json`.

### 1f. Handle CLAUDE.md and AI Files

Follow `setup.md` Step 5 (Handle CLAUDE.md):
- Scan for existing AI instruction files
- Offer to merge content into AGENTS.md
- Save content for Config Writer to use later
- Optionally run `claude init` if no CLAUDE.md exists

Store saved content as strings for `_install_config.json`.

### 1g. Ask Standards Location

```
Where should I place coding standards?

1. docs/ai-rules (Recommended - AI/agent-specific, tool-agnostic)
2. docs/coding-standards (Generic engineering standards, tool-agnostic)
3. .cursor/rules (Keep Cursor IDE location)
4. .claude/rules (Keep Claude Code location)
5. .aiRules (Hidden directory, tool-agnostic)

Your choice (1/2/3/4/5)?
```

Store as `STANDARDS_DIR`.

### 1h. Pre-Detection and Config Handoff

Run the lightweight pre-detection from `setup.md` → Content Adaptation Pipeline → Pre-Detection:

```bash
ls {TARGET_PROJECT}/build.gradle {TARGET_PROJECT}/build.gradle.kts {TARGET_PROJECT}/pom.xml {TARGET_PROJECT}/package.json {TARGET_PROJECT}/Podfile 2>/dev/null
```

Check which build files exist from the output to determine signals (Java build files → JAVA, package.json → NODE, Podfile → IOS).

Set `applicable_rule_dirs` based on the signals detected:
- JAVA_BUILD_DETECTED → `["universal", "java-spring-boot"]`
- NODE_BUILD_DETECTED → `["universal", "react"]`
- IOS_BUILD_DETECTED → `["universal"]`
- ANDROID_BUILD_DETECTED → `["universal"]`
- No signal → `["universal"]` (Stack Analyzer can expand if it discovers more)

This is a **hint**, not a final decision. The Stack Analyzer may override it based on deeper analysis of the target project's actual stack.

**Write `_install_config.json`** to the target project root with ALL gathered data:

```bash
cat > {TARGET_PROJECT}/_install_config.json << 'HEREDOC'
{
  "target_project": "{TARGET_PROJECT}",
  "framework_path": "{FRAMEWORK_PATH}",
  "project_name": "{PROJECT_NAME}",
  "tracker": {TRACKER object, default { "type": "github", "url": "" }},
  "namespace": "{NAMESPACE or null}",
  "namespaces": {NAMESPACES array or null},
  "standards_dir": "{STANDARDS_DIR}",
  "existing_state": {
    "claude_md": {true/false},
    "agents_md": {true/false},
    "skills_dir": {true/false},
    "agents_dir": {true/false},
    "settings": {true/false},
    "rules_dirs": ["{list of existing rule directories}"]
  },
  "saved_claude_md_content": "{saved content or empty}",
  "saved_ai_files_content": {},
  "mode": "fresh",
  "framework_version": "{FRAMEWORK_VERSION}",
  "install_role": "{INSTALL_ROLE}",
  "applicable_rule_dirs": ["{list}"],
  "bootstrap_rules_generated": false
}
HEREDOC
```

Present the detected platform to the user:
```
Pre-detection signals: {what was found}
Applicable rule directories: {list}

This will be verified by the Research agent. Continuing...
```

## Phase 2: Bootstrap (Greenfield Only)

**Skip this phase entirely** if ANY of these are true:
- Step 1e detected existing rules directories (`RULES_EXIST`)
- Step 1f found existing AI instruction files
- Step 1e detected existing `.claude/skills` or `.claude/agents`

This phase only runs for **true greenfield projects** — no prior AI awareness whatsoever.

### 2a. Run `claude init`

If no `CLAUDE.md` exists in the target project (checked in Step 1e/1f):

```bash
cd {TARGET_PROJECT}
claude init
```

This generates a basic `CLAUDE.md` that captures Claude's understanding of the project. The content will be merged into `AGENTS.md` by the Config Writer later.

Read the generated `CLAUDE.md` and save its content to `_install_config.json` → `saved_claude_md_content`.

### 2b. Launch Bootstrap Agent

Launch a **Task** subagent to deep-read the project and generate project-aligned rules.

**Bootstrap Agent prompt:**
```
You are the Bootstrap Agent for the AI Awareness Content Adaptation Pipeline.

Read {TARGET_PROJECT}/_install_config.json for configuration.

This is a greenfield project with NO existing AI awareness. Your job is to
deep-read the project and generate initial coding rules that are aligned to
the project's actual patterns and conventions.

## Step 1: Deep-Read the Project

Analyze the target project thoroughly:
- Build files and dependency manifests (dependencies, versions, plugins)
- Source directory structure and package organization
- 5-10 representative source files to identify coding patterns
- Test infrastructure (framework, directory layout, naming conventions)
- Configuration files (application config, environment files)
- API patterns (REST controllers, GraphQL, gRPC, etc.)
- Database access patterns (ORM, raw SQL, migrations)
- Error handling patterns
- Logging patterns

## Step 2: Generate Project-Aligned Rules

Create rules in {TARGET_PROJECT}/{STANDARDS_DIR}/ that reflect what you found.
Generate ONLY rules that are genuinely relevant — do not generate rules for
technologies the project doesn't use.

For each rule file, follow this structure:
- Title and brief description
- Patterns observed in the actual codebase (cite specific files)
- Do/Don't examples drawn from the project's own code style
- Keep rules concise and actionable

Generate these rule files as applicable:

**Always generate:**
- `project-conventions.md` — Project-specific naming, structure, and style
  conventions observed in the codebase (package naming, class organization,
  import ordering, comment style, etc.)

**Generate if evidence found:**
- `api-patterns.md` — If REST/GraphQL/gRPC endpoints detected: request/response
  patterns, error response format, authentication patterns, versioning approach
- `database-patterns.md` — If ORM/SQL detected: query patterns, transaction
  boundaries, migration conventions, entity relationships
- `testing-patterns.md` — If tests detected: test naming, setup/teardown patterns,
  mocking approach, assertion style, test data management
- `error-handling.md` — If consistent error handling found: exception hierarchy,
  error codes, logging on errors, retry patterns

Do NOT generate rules that overlap with the framework's universal rules
(critical-thinking.md, code-review.md, task.md) — those will be installed
separately by the Rules Writer.

## Step 3: Record What You Generated

Write a summary to stdout listing every file you created and a one-line
description of each. This will be used to update _install_config.json.
```

### 2c. Update Config Handoff

After the Bootstrap Agent completes, update `_install_config.json`:
- Set `bootstrap_rules_generated` to `true`
- Add `bootstrap_rules` array listing the generated rule file paths

Present to the user:
```
Bootstrap complete — generated project-aligned rules:
- {STANDARDS_DIR}/project-conventions.md — {description}
- {STANDARDS_DIR}/testing-patterns.md — {description}
  ...

These will be preserved alongside the framework's universal rules.
Continuing to Research phase...
```

## Phase 3: Research (Stack Analyzer)

Launch the Stack Analyzer as a **Task** subagent. It reads `_install_config.json` and the target project, NOT setup.md.

**Stack Analyzer prompt:**
```
You are the Stack Analyzer of the AI Awareness Content Adaptation Pipeline.

Read {TARGET_PROJECT}/_install_config.json for configuration.

Your job:
1. Detect the target project's complete technology stack by reading its actual files
   (build files, dependency manifests, imports, directory structure, test infrastructure).
   Do NOT use a hardcoded platform list — detect whatever is present.

2. Read the applicable framework source files from {FRAMEWORK_PATH}:
   - skills/*/SKILL.md            (code-repo skills — read these when INSTALL_ROLE=code-repo)
   - workspace-skills/*/SKILL.md  (workspace skills — read these when INSTALL_ROLE=workspace)
   - agents/*/AGENT.md
   - rules/{applicable_rule_dirs}/*.md  (from _install_config.json)
   - templates/*.md
   - settings.json

3. For each framework file, identify every platform-specific element
   (commands, file extensions, directory paths, code patterns, annotations,
   grep expressions, rule file references, project name placeholders).

4. Write {TARGET_PROJECT}/_stack_mapping.md with the full mapping
   (see format in setup.md Content Adaptation Pipeline → Stack Analyzer output).
   Include build commands (setup, compile, test, run) and a project structure
   summary for AGENTS.md generation.

Do NOT read setup.md. Do NOT install any files. Only research and write the mapping.
```

**After the Stack Analyzer completes:** Read the mapping summary and present it to the user:

```
Detected your project stack:
- Language: {from mapping}
- Framework: {from mapping}
- Build Tool: {from mapping}
- Database: {from mapping or "None detected"}

Applicable rules: {from mapping}

Is this correct? (y/n)
```

If no, ask user to describe corrections, update `_stack_mapping.md` accordingly.

## Phase 4: Install (Writer Agents)

Launch writer agents per `setup.md` → Content Adaptation Pipeline → Writer Agents.

**Initialize `_install_manifest.json`:**
```bash
echo '{"files_written":[]}' > {TARGET_PROJECT}/_install_manifest.json
```

### 4a. Launch Structure Writer, Rules Writer, and ERD Writer in Parallel

These three agents are independent. Launch them as parallel Task subagents.

**Structure Writer prompt:**
```
You are the Structure Writer of the AI Awareness Content Adaptation Pipeline.

Read {TARGET_PROJECT}/_install_config.json for configuration. Note especially:
- INSTALL_ROLE: either "code-repo" or "workspace". Used to filter skills (see step 1 below).

Read {TARGET_PROJECT}/_stack_mapping.md for the element mapping.

Your job — install these framework components into the target project:
1. Skills: pick the source directory by INSTALL_ROLE — NO manifest, NO frontmatter filter (v7.0.0 removed both):
     - INSTALL_ROLE = code-repo → source is `{FRAMEWORK_PATH}/skills/`
     - INSTALL_ROLE = workspace → source is `{FRAMEWORK_PATH}/workspace-skills/`
   Bash:
     `SKILLS_SRC=$([ "$INSTALL_ROLE" = "workspace" ] && echo "{FRAMEWORK_PATH}/workspace-skills" || echo "{FRAMEWORK_PATH}/skills")`
   Copy every directory under $SKILLS_SRC into {TARGET_PROJECT}/.claude/skills/. Apply element mapping for platform-specific references to installed skills only. Log every install. No skip-logging is needed — the source directory IS the filter.
2. Settings: Copy {FRAMEWORK_PATH}/settings.json to {TARGET_PROJECT}/.claude/
   Remove allow entries irrelevant to the project's platform per mapping.
3. Agents: Copy {FRAMEWORK_PATH}/agents/ to {TARGET_PROJECT}/.claude/agents/
   Agents are NOT split by install role — they're invoked by skills as needed.
4. Templates: Follow setup.md Step 13 (scan for existing templates at standard locations; install framework default only if none found) AND then ALWAYS run setup.md Step 13c (remove any legacy `.claude/templates/pr-template.md` or `.claude/templates/commit-template.md` duplicates).
5. .gitignore: Add .claude/skill.config and .claude/settings.local.json entries.
6. .dockerignore: If Dockerfile exists, add AI Awareness files to .dockerignore.

Follow setup.md Steps 6 (directory-by-INSTALL_ROLE), 7, 11, 13, 13c, 15 for detailed procedures.
Do NOT invent substitutions not in the mapping.
Append every file you write to {TARGET_PROJECT}/_install_manifest.json.
```

**Rules Writer prompt:**
```
You are the Rules Writer of the AI Awareness Content Adaptation Pipeline.

Read {TARGET_PROJECT}/_install_config.json for configuration (standards_dir, existing_state.rules_dirs).
Read {TARGET_PROJECT}/_stack_mapping.md for the element mapping and applicable rules.

Your job — install and adapt coding standards:
1. If existing rules need migration from old locations, migrate per setup.md Step 8a.
2. Handle renamed files per setup.md Step 8b-rename table.
3. Install universal rules from {FRAMEWORK_PATH}/rules/universal/ to {STANDARDS_DIR}/.
4. If INSTALL_ROLE = workspace: also install workspace-only rules from {FRAMEWORK_PATH}/workspace-rules/ to {STANDARDS_DIR}/. These are leadership/status-report style rules (cross-team framing, document formatting for weekly reports etc.) that v7.0.0 split out of rules/universal/ because they don't apply to code repos. Skip this step entirely for code-repo installs.
5. Install platform-specific rules based on mapping's "Applicable Framework Rules" table.
6. Apply element mapping to adapt ALL rules (package names, directory paths,
   commands, entity names, grep patterns).
7. Handle project-structure.md special translation — detect actual project packages
   and replace generic placeholders with real values.

IMPORTANT: If _install_config.json has "bootstrap_rules_generated": true, the
Bootstrap phase already created project-specific rules in {STANDARDS_DIR}/.
These are PROJECT-CUSTOM content — do NOT overwrite or replace them.
Install framework rules alongside them. If a bootstrap rule covers a topic
that overlaps with a framework rule (e.g., both cover database patterns),
keep both files — the bootstrap rule has project-specific examples and the
framework rule has universal patterns.

When following setup.md Step 9, the platform-specific paths (Java Spring Boot,
React) only apply if the mapping confirms that platform. For any platform not
covered by setup.md Step 9, install only universal rules — the mapping's
"Applicable Framework Rules" table is the authoritative guide for which rule
directories to install.

Follow setup.md Steps 8, 8a, 8b-rename, 8c, 8d, 9 for detailed procedures.
Do NOT invent substitutions not in the mapping.
Append every file you write to {TARGET_PROJECT}/_install_manifest.json.
```

**ERD Writer prompt — only if database detected in mapping:**

Check `_stack_mapping.md` — if Database is "None" and Migration Tool is "None", skip the ERD Writer entirely.

```
You are the ERD Writer of the AI Awareness Content Adaptation Pipeline.

Read {TARGET_PROJECT}/_stack_mapping.md for database information.

Your job — generate ERD documentation:
1. Read migration files and/or entity files at the paths indicated in the mapping.
2. Generate {TARGET_PROJECT}/docs/erd.md with Mermaid diagram, table definitions,
   relationships, and migration history.

Follow setup.md Step 14 for the detailed procedure and output format.
Append every file you write to {TARGET_PROJECT}/_install_manifest.json.
```

### 4b. Wait for Structure Writer + Rules Writer to Complete, Then Launch Config Writer

Config Writer needs to know what was installed by the other writers (for AGENTS.md skill/agent/rule lists).

**Config Writer prompt:**
```
You are the Config Writer of the AI Awareness Content Adaptation Pipeline.

Read {TARGET_PROJECT}/_install_config.json for all project configuration.
Read {TARGET_PROJECT}/_stack_mapping.md for stack details and build commands.
Read {TARGET_PROJECT}/_install_manifest.json for the list of files installed by other writers.

Your job — create configuration and documentation files:

1. config_hints.json: Create {TARGET_PROJECT}/.claude/config_hints.json using the
   project configuration from _install_config.json (project name, namespace(s),
   standards_dir, framework_version) and the detected platform from _stack_mapping.md.
   For the "platform" field, use the actual detected stack description from the mapping
   (e.g., "Java Spring Boot", "React", "Ruby on Rails", "Python/FastAPI") — do NOT
   limit to a hardcoded list.
   Follow setup.md Step 10 for the schema (single-namespace or multi-namespace).
   If _install_config.json has "bootstrap_rules_generated": true, add a
   "bootstrap_rules" field listing the paths of all bootstrap-generated rule files
   (from _install_config.json "bootstrap_rules" array).

2. AGENTS.md: Generate {TARGET_PROJECT}/AGENTS.md using:
   - Build commands from _stack_mapping.md (setup, compile, test, run)
   - Project structure summary from _stack_mapping.md
   - List of installed skills from _install_manifest.json
   - List of installed agents from _install_manifest.json
   - List of installed rules from _install_manifest.json
   - Saved CLAUDE.md / AI file content from _install_config.json (merge if present)
   Follow setup.md Step 12 templates and scanner compatibility rules.
   IMPORTANT: Only backtick-quote actual file paths that exist. Never use
   template variables inside backticks. Never backtick-quote naming patterns.

3. CLAUDE.md: Write the standard @AGENTS.md content per setup.md Step 5:
   <!-- NOTE: Do NOT add content here. All project documentation, skills,
        agents, and guidelines belong in AGENTS.md. This file only exists
        to tell Claude Code to load AGENTS.md. -->
   @AGENTS.md

Append every file you write to {TARGET_PROJECT}/_install_manifest.json.
```

## Phase 5: Verify (Contamination Checker)

Launch the Contamination Checker as a **fresh Task invocation** with clean context.

**CRITICAL:** Do NOT pass any conversation history, mapping file content, or writer outputs. Only pass the target path and manifest path.

**Contamination Checker prompt:**
```
You are the Contamination Checker of the AI Awareness Content Adaptation Pipeline.

Your job: independently verify that no foreign-stack references contaminate
the installed files in {TARGET_PROJECT}.

1. Detect the target project's technology stack yourself by reading its build files,
   dependency manifests, and source imports. Form your OWN understanding — do NOT
   read _stack_mapping.md or _install_config.json.

2. Read {TARGET_PROJECT}/_install_manifest.json to get the list of installed files.

3. Scan every installed file for:
   - Unreplaced placeholders: {project}, {namespace}, {STANDARDS_DIR}, com.example.{  (NOT {platform} — it is a runtime token resolved by skills at execution; leave it intact)
   - Foreign-stack references (e.g., Java references in a React project, Gradle
     references in a Maven project)
   - Rule file references that point to files that don't exist in the project

4. Write your findings as a Verification Report to stdout.
   Verdict: PASS if zero contamination, FAIL if any found.
```

**If PASS:** Proceed to Phase 6.

**If FAIL:** Read the report, identify which writer owns each flagged file, and re-launch that specific writer with the fix instructions. Then re-run the Contamination Checker as a fresh Task. Repeat until PASS.

## Phase 6: Summary and Cleanup

### 6a. Read Install Manifest

Read `_install_manifest.json` to build the summary.

### 6b. Present Summary

```
AI Awareness installed for {PROJECT_NAME}!

What was set up:
- Project: {PROJECT_NAME}
- Install role: {INSTALL_ROLE}
- Tracker: {tracker.type}{if jira/linear and url set: " at {tracker.url}"} ({namespace info})
- Skills: {count} skills installed (filtered to match install_role)
- Agents: {count} agents installed
- Rules: {count} framework rules installed ({rule categories})
  {if bootstrap: + {count} project-specific rules generated}
- AGENTS.md: Single source of truth
- CLAUDE.md: Points to @AGENTS.md
- .gitignore: Updated with AI Awareness exclusions
- {if Dockerfile exists: .dockerignore: Updated to exclude AI Awareness files from Docker builds}
- Verification: PASS (no foreign-stack contamination)

Next steps:

1. Configure your local paths:
   > aa-init-skills

2. Set up issue-tracker integration:
   > aa-init-mcps
   (GitHub default verifies `gh auth status`; Jira/Linear configure their MCP server)

3. Start your first task:
   > aa-task-flow

{If INSTALL_ROLE == "workspace":}
4. Commit and push to main when ready — workspace installs don't use PRs.
   cd {TARGET_PROJECT}
   git add .
   git commit -m "Install AI Awareness framework v{FRAMEWORK_VERSION}"
   git push

{If INSTALL_ROLE == "code-repo":}
4. Push your install branch and open a PR:
   cd {TARGET_PROJECT}
   git push -u origin {BRANCH_NAME}
   gh pr create --base {DEFAULT_BRANCH} --title "Install AI Awareness framework v{FRAMEWORK_VERSION}"
```

### 6c. Cleanup Temporary Files

```bash
rm -f {TARGET_PROJECT}/_install_config.json
rm -f {TARGET_PROJECT}/_stack_mapping.md
rm -f {TARGET_PROJECT}/_install_manifest.json
```

### 6c-2. Append Install Entry to Update History (per-platform — v6.10.0)

**Code-repo installs route audit entries to the LINKED workspace's per-platform subdir.** If the linked-install detection in Phase 1 found a workspace, this code-repo install's audit entry goes there under the correct platform subdirectory. If no linked workspace was detected, skip this step entirely — code repos without a paired workspace have no audit-trail destination.

**Workspace installs** write to the workspace-root `update-history.md` (NOT a platform subdir) and ALSO create the per-platform subdirectories so future per-platform entries from linked code-repo installs have a home.

Follow `setup.md` Step 15c. The helper code there:

1. Calls `resolve_target_platform()` to determine which platform this install belongs to
2. Reverse-lookups the target's git remote against the workspace's `github_repos`
3. If the lookup fails, prompts once for the platform and persists as `parent_workspace_platform` in the target's `config_hints.json`
4. Picks the destination file: workspace root for `INSTALL_ROLE=workspace`, `{Platform}/update-history.md` for code-repo installs
5. Creates parent directories and seeds the file header on first write

After Step 15c sets up paths, prepend the install entry at the top of `update-history.md` (below the header, above any existing entries):

```markdown
## {YYYY-MM-DD} — none → v{FRAMEWORK_VERSION} (install)

**Platform:** {Backend | Frontend | workspace}

**Framework changes applied:**
- Initial install: {N} skills, {M} agents, {K} rules adapted to {platform} stack
- {1–2 highlights from the framework version's CHANGELOG Summary, if relevant to first install}

**Project customizations preserved:** n/a — fresh install

**Optimizer findings:** {one-line summary if Step 6e was accepted, else "Skipped"}
```

7–11 lines per entry.

**Workspace installs additionally:** for each entry in `config_hints.json → platforms[]`, create the corresponding `{Platform}/improvements/` subdirectory empty (so concurrent `aa-record-improvement` runs have a writable target). No README needed — the platform name itself documents the directory.

### 6d. Sync Global Tools

Install framework scripts and agents to `~/.claude/` for this developer — including any `install: "sourced"` scripts (such as `aa-worktree/worktree.sh`) which also get wired into the user's shell-rc.

Read `.claude/commands/aa-install-tools/SKILL.md` from `{FRAMEWORK_PATH}` and execute its Steps 1–4 inline (using `{FRAMEWORK_PATH}` as the working directory for the jq/cp commands). This is idempotent — re-running on every install picks up new scripts without disturbing existing ones.

Skip the migration step (Step 0) if `~/.claude/` already has the current `aa-` namespaced layout (no `migration.json` cleanup needed on a fresh install).

After sync, briefly tell the user:

```
Global tools synced to ~/.claude/.
{If any sourced helpers were wired:}
Shell helpers added to {RC_FILE}. Run 'source {RC_FILE}' or open a new terminal to use them.
```

### 6e. Run AI Optimizer (Recommended)

Tell the user:
```
Installation complete! It's recommended to run the AI Optimizer to optimize
the installed files — it removes redundancy, rule echoes, and token bloat.

Would you like to run AI Optimizer now? (y/n)
```

If yes, the user should open a new Claude session in the target project and say `aa-optimizer`. (The optimizer skill was installed globally in Step 6d, so it's already available.)

### 6f. Post-Setup Validation (Optional)

Follow `setup.md` Step 17 if rubric-scanner is available.
