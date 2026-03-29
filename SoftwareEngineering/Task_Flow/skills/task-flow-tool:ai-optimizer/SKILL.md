---
name: task-flow-tool:ai-optimizer
description: Audit and optimize AI-awareness files. Detects redundancies, conflicts, staleness, example bloat, and fragmentation. Produces detailed reports and interactive cleanup recommendations. Say "task-flow-tool:ai-optimizer" or "optimize AI rules" to run.
disable-model-invocation: true
---

**Version:** 2.0.0

## Purpose

Audit, deduplicate, and harmonize all AI-awareness files across a project based on **official Claude Code best practices**. Produce a report of real, measurable issues and get developer approval before making any changes. Optimize token efficiency by eliminating bloat while preserving all unique intent.

**Detection criteria based on:**
- [Claude Code Best Practices](https://code.claude.com/docs/en/best-practices)
- [How Claude Code Works](https://code.claude.com/docs/en/how-claude-code-works)

**Key principle:** Identifies mistakes that **directly impact Claude's performance** (context bloat, ignored instructions, conflicts) rather than subjective style preferences.

## When to Run

Invoke this skill when:
- Post-setup validation after Task Flow installation
- Developer explicitly asks to "optimize AI rules", "clean up AI files", "audit AI config", or "run ai-optimizer"
- A new AI rules file is added to the project
- Developer suspects conflicts, bloat, or inconsistencies
- Periodic maintenance (quarterly/biannual recommended)
- Pre-release checks to ensure AI documentation is clean

## What This Skill Does

7-step process:
1. **Discover** - Scan ALL AI-awareness files (CLAUDE.md, AGENTS.md, .cursor/rules/, etc.)
2. **Parse & Categorize** - Organize rules by category (CODE_STYLE, ARCHITECTURE, TESTING, etc.)
3. **Detect Issues** - Identify 13 problem types: redundancy, echoes, conflicts, staleness, example bloat, fragmentation, inferable-from-code, standard conventions, embedded docs, missing emphasis, CLAUDE.md size, missing flags, heavy imports
4. **Generate Report** - Create structured audit with tables, metrics, token impact analysis
5. **Ask Questions (REQUIRED)** - Present ALL findings and get explicit approval for each fix
6. **Propose Fix Plan** - Create concrete changeset based on developer's answers
7. **Apply & Verify** - Implement approved changes, show before/after metrics, re-validate

## Expected Outcome

- Detailed audit report showing all issues
- Interactive Q&A for developer decisions
- Optimized, deduplicated, token-efficient AI rules
- Before/after token metrics showing reduction percentage
- Validation confirming zero conflicts/redundancies/bloat

## Pre-Flight Checklist

Before starting:
- [ ] In project root directory
- [ ] Read access to all project files
- [ ] Understand: READ-FIRST process (no changes until Step 7)
- [ ] Will get explicit approval before ANY changes

**Estimated time:** 5-10 minutes for analysis, variable for fixes.

## Step 1 — Discover All AI-Awareness Files (CRITICAL FIRST STEP)

**MUST find ALL AI configuration files** across the entire project, regardless of location or naming convention.

### Discovery Process

**1a. Search by known patterns:**
```bash
# Find all AI config files
find . -name "CLAUDE.md" -o -name "claude.md" -o -type d -name ".claude" \
       -o -name ".cursorrules" -o -path "*/.cursor/rules/*.mdc" \
       -o -name "AGENTS.md" -o -name "agents.md" -o -name "CODEX.md" \
       -o -name "AI.md" -o -name "RULES.md" -o -name "CODING_STANDARDS.md" \
       -o -name "CONVENTIONS.md" -o -name "GEMINI.md" -o -name ".windsurfrules" \
       -o -name ".github/copilot-instructions.md" \
       -o -path "*/.claude/skills/*/SKILL.md" -o -path "*/SKILLS/*.md" \
       -o -name ".aider*"
```

**1b. Search by content (catch custom locations):**
```bash
# Find markdown files with AI instruction phrases
grep -l -i "when working on this project\|AI assistant\|code style\|do not\|always use\|never commit" *.md .*.md 2>/dev/null
```

**1c. Check user-level config:**
```bash
ls -la ~/.claude/CLAUDE.md 2>/dev/null
```

**1d. Understand tech stack (for inferable-from-code detection):**
```bash
# Detect frameworks and build tools
cat package.json 2>/dev/null | grep -E '"(react|vue|angular|express|next)"'
ls -la build.gradle pom.xml Cargo.toml pyproject.toml 2>/dev/null
```

### Produce discovery manifest

Output format:
```markdown
## Discovery Results
**Files found:** {n}

### By Tool: Claude Code | Cursor | Generic | Skills | Custom
### Tech Stack: Languages | Frameworks | Build | Testing

| File | Lines | Est. Tokens | Status |
|------|-------|-------------|--------|
| CLAUDE.md | 250 | 1800 | ⚠️ Warning |
| **Total** | **595** | **4170** | ⚠️ High |
```

**If no files found:** Report "❌ No AI-awareness files found. Recommendation: Create CLAUDE.md to get started"

## Step 2 — Parse & Categorize Each File

Read each discovered file and extract every instruction/rule. Tag into categories:

**Categories:** CODE_STYLE (formatting, naming, imports) | ARCHITECTURE (structure, patterns, boundaries) | TESTING (strategy, coverage, frameworks) | GIT (commits, branching, PRs) | TOOLING (build, CI/CD, setup) | BEHAVIOR (AI persona, tone, verbosity) | WORKFLOW (steps, checklists, verification) | PROJECT_CONTEXT (domain knowledge, business logic) | SAFETY (destructive action guards) | PERFORMANCE (optimization, limits) | SECURITY (auth, secrets, vulnerabilities) | OTHER

**Parsing checklist:**
1. Extract complete context (full rule, not summary)
2. Note location (file path, line numbers)
3. Detect emphasis (**IMPORTANT**, CRITICAL, ALL CAPS)
4. Count examples per rule
5. Track cross-references to other files/sections
6. Estimate tokens (~4 chars per token)

**Output format:**
```markdown
## Parsed Instructions
### CLAUDE.md (1800 tokens)
1. [CODE_STYLE, line 12] "Use 4-space indentation for TypeScript files"
2. [ARCHITECTURE, line 45-60, 3 examples] "Organize code by feature, not type" (420 tokens)
...
**Total instructions parsed:** 47 | **Unique concepts:** ~35 (12 duplicates detected)
```

## Step 3 — Detect Issues

Run 13 checks across ALL parsed instructions based on Claude Code best practices. **Context efficiency principle:** Bloated files cause Claude to ignore instructions. Each issue type directly impacts performance.

### 3a. Redundancy (same idea, multiple locations)

**Detect:** Same semantic instruction in 2+ files or 2+ locations in one file.
**Example:** "Use 4-space indentation" appears in AGENTS.md:12, .cursorrules:5, CLAUDE.md:30
**Report:** `REDUNDANT — Indentation rule repeated 3× across 3 files`

### 3b. In-File Repetition (echo problem)

**Detect:** File restates its own point in different sections (AI-generated bloat pattern).
**Heuristics:** Same key phrase 2+ times in different sections | Numbered list defined once then re-listed | Paragraphs with >70% token overlap
**Report:** `ECHO — "{phrase}" appears {n} times in {file} at lines {lines}`

### 3c. Conflicts (contradictory instructions)

**Detect:** Two instructions oppose each other.
**Example:** AGENTS.md says "Always use named exports" but .cursorrules says "Prefer default exports"
**Report:** `CONFLICT — Export style: named (AGENTS.md:14) vs default (.cursorrules:8)`

### 3d. Staleness

**Detect:** References to deprecated packages/APIs, removed files/directories, outdated version numbers
**Report:** `STALE — Reference to {thing} which no longer exists`

### 3e. Example Bloat (multiple samples for one concept)

**Detect:** Rule illustrated with 2+ examples that teach the same thing (AI-generated over-explanation).
**Heuristics:** 2+ code blocks demonstrating same pattern | Multiple "good vs bad" pairs teaching identical lesson | Verbose before/after comparisons
**Example:** "Use early returns" has 4 examples all showing if/return pattern → 3 are redundant
**Report:** `EXAMPLE_BLOAT — "{rule}" has {n} examples in {file}, {n-1} can be removed`

### 3f. Fragmentation

**Detect:** Closely related instructions scattered across many files instead of co-located.
**Report:** `FRAGMENTED — {category} rules spread across {n} files: {list}`

### 3g. Inferable from Code (best practice violation)

**Detect:** Instructions describing things Claude can determine by reading code.
**Examples:** ❌ "Use React 18" (package.json) | ❌ "Express.js for API" (imports) | ❌ "PostgreSQL database" (config files) | ❌ "Tests are in test/" (folder structure)
**Report:** `INFERABLE — "{instruction}" can be determined from code (file: {file})`
**Best practice:** "Only include what Claude can't infer from code alone"

### 3h. Standard Conventions (unnecessary instructions)

**Detect:** Instructions describing standard language/framework conventions Claude already knows.
**Examples:** ❌ "Use camelCase for JS variables" | ❌ "Import React at top" | ❌ "Close database connections" | ❌ "Write clean code" | ❌ "Follow PEP 8"
**Report:** `STANDARD_CONVENTION — "{instruction}" is standard {language/framework} convention Claude already knows`
**Best practice:** Exclude "Standard language conventions" and "Self-evident practices"

### 3i. Embedded Documentation (should be links)

**Detect:** Long API docs, tutorials, or reference material embedded in rules files.
**Heuristics:** Code blocks >30 lines | Detailed API reference sections | Tutorial "how to" sections >50 lines | Content duplicating external docs
**Report:** `EMBEDDED_DOCS — {n} lines of documentation in {file} should be links to external docs`
**Best practice:** "Exclude detailed API documentation (link to docs instead)"

### 3j. Missing Emphasis on Critical Rules

**Detect:** Rules using "must", "never", "always", "critical" but lacking emphasis formatting.
**Examples:** ❌ "Never commit secrets to git" | ❌ "Always run tests before pushing" | ❌ "You must use git hooks"
**Report:** `MISSING_EMPHASIS — Critical rule "{rule}" in {file} lacks emphasis (IMPORTANT/WARNING/etc.)`
**Best practice:** "Add emphasis (e.g., 'IMPORTANT' or 'YOU MUST') to improve adherence"

### 3k. CLAUDE.md Size Warning

**Detect:** CLAUDE.md token count exceeds recommended size.
**Thresholds:** Warning: >2000 tokens | Critical: >4000 tokens
**Report:** `SIZE_WARNING — CLAUDE.md is {n} tokens ({percent}% of recommended max). Bloated files cause Claude to ignore instructions.`
**Why critical:** CLAUDE.md loads every session. Best practice: "Keep it concise... For each line, ask: 'Would removing this cause Claude to make mistakes?' If not, cut it." Recommended max: 150 lines.

### 3l. Skills Without `disable-model-invocation`

**Detect:** Command-like workflow skills lacking `disable-model-invocation: true` flag.
**Heuristics:** Contains numbered steps | Has side effects (git, file writes, API calls) | Verb-based name (fix-*, deploy-*, run-*)
**Report:** `MISSING_FLAG — Skill "{name}" appears to be a workflow but lacks 'disable-model-invocation: true'`
**Best practice:** "For skills you invoke manually, set `disable-model-invocation: true` to keep descriptions out of context until you need them"

### 3m. Context-Heavy CLAUDE.md Imports

**Detect:** CLAUDE.md imports large files that should be skills instead.
**Heuristics:** `@path/to/file.md` syntax | Imported file >500 tokens | Contains domain knowledge or workflows (not project config)
**Report:** `HEAVY_IMPORT — CLAUDE.md imports {file} ({n} tokens). Consider converting to skill (loads on-demand) instead.`
**Why critical:** CLAUDE.md imports load every session. Skills only load when needed.

## Step 4 — Generate the Report

**Output structured report:**

```markdown
# AI Rules Audit Report

## Summary
- Files scanned: {n} | Total instructions: {n}
- **Context Window Impact:** CLAUDE.md: {n} tokens ({status}) | Heavy imports: {n} files ({n} tokens) | Skills missing flag: {n} | **Wasted context:** {n} tokens/session
- **Critical Issues (Require Decisions):** Conflicts: {n} | Inferable from code: {n} | Standard conventions: {n} | Embedded docs: {n}
- **Quality Issues (Auto-fixable):** Redundancies: {n} | Echoes: {n} | Example bloat: {n} | Missing emphasis: {n} | Stale: {n} | Fragmentation: {n}

## Impact Analysis
**Performance:** Context fill: {n} tokens/session | Risk: {LOW/MEDIUM/HIGH} | Recommendation: {action}
**Token Efficiency:** Current: {n} | Savings: {n} ({percent}%) | Target: {n}
**Why critical:** "Claude's context window fills up fast, and performance degrades as it fills. Bloated CLAUDE.md files cause Claude to ignore your actual instructions!"

## Detailed Findings
### Critical Issues (Conflicts)
| # | Description | File A (line) | File B (line) | Severity |
|---|-------------|---------------|---------------|----------|

### Redundancies
| # | Instruction | Occurrences | Files |
|---|-------------|-------------|-------|

### In-File Echoes
| # | Phrase | File | Lines | Repeated |
|---|--------|------|-------|----------|

### Example Bloat
| # | Rule | File (line) | Found | Keep |
|---|------|-------------|-------|------|

### Stale References
| # | Reference | File (line) | Reason |
|---|-----------|-------------|--------|

### Fragmentation
| # | Category | Files | Recommendation |
|---|----------|-------|----------------|
```

## Step 5 — Ask Developer Questions (REQUIRED - Do Not Skip)

**CRITICAL:** MUST present findings and get explicit approval before ANY changes.

**Format:**
```markdown
## Proposed Actions - Review Required
Found {n} issues needing your review:

### Critical Issues (Require Your Decision)
1. **Conflict: Export style** — AGENTS.md:14 "named exports" vs .cursorrules:8 "default exports"
   → Fix: (a) Keep named (b) Keep default (c) Contextual rule | Your choice: ___

2. **Bloat: Standard convention** — CLAUDE.md:45-60 describes camelCase (Claude knows this)
   → Fix: Remove section (saves 280 tokens) | Approve? (y/n): ___

### Quality Issues (Automated Fixes)
3. **Redundancy** — "Run tests before committing" 3× (AGENTS.md:12, CLAUDE.md:89, .cursorrules:5)
   → Fix: Keep in AGENTS.md only | Approve? (y/n): ___

4. **Example bloat** — "Early returns" has 4 examples in CLAUDE.md:120-180
   → Fix: Keep clearest, remove 3 (saves 340 tokens) | Approve? (y/n): ___

**Before proceeding:** Review each fix | Answer conflict questions | Approve/reject fixes | Type "apply all approved" or "skip"
```

**DO NOT proceed to Step 6 until developer responds.**

## Step 6 — Propose a Fix Plan (only after answers)

After developer answers, produce concrete changeset:

```markdown
## Proposed Changes
**Deletions:** Remove `.cursorrules` line 5 (redundant indentation rule)
**Modifications:** AGENTS.md:14 change "named exports" → "{developer's choice}"
**Consolidations:** Move all CODE_STYLE rules → AGENTS.md § Code Style | Remove CODE_STYLE from CLAUDE.md, .cursorrules
**New Additions:** Add missing SAFETY rule to AGENTS.md: "{rule}"
```

Ask: `Shall I apply these changes? (yes / no / let me adjust)`

## Step 7 — Apply, Optimize & Verify

If confirmed:

**7a. Apply Changes** (in order):
1. Deletions (remove redundant sections)
2. Modifications (fix conflicts, add emphasis)
3. Consolidations (merge scattered rules)
4. New additions (add missing critical rules)

**7b. Optimize Files** - Apply compression rules to every affected file:
- One example per concept (pick clearest)
- Merge duplicate sections
- Remove restated preambles, filler phrases, repeated headings
- Tighten wording (concise imperative sentences over verbose paragraphs)
- Preserve every unique rule; only cut duplication
- Add emphasis (**IMPORTANT**, **CRITICAL**) to safety rules

**7c. Show Before/After:**
```markdown
## Optimization Results
| File | Before | After | Reduction |
|------|--------|-------|-----------|
| CLAUDE.md | 1800 | 980 | -820 (45%) |
| **Total** | **3320** | **2080** | **-1240 (37%)** |
```

**7d. Re-validate** - Re-run Steps 2–4 to confirm:
✅ Zero conflicts | ✅ Zero redundancies | ✅ Zero example bloat | ✅ Zero inferable-from-code bloat | ✅ Zero standard convention bloat | ✅ CLAUDE.md under 2000 tokens | ✅ All critical rules have emphasis

**7e. Final Report:**
```markdown
✅ AI rules optimized successfully!

**Summary:** Issues resolved: {n} | Files optimized: {n} | Files deleted: {n} | Reduction: {before} → {after} ({percent}%)
**Context Impact:** Before: {n} tokens/session | After: {n} tokens/session | Improvement: {n} more tokens available ({percent}%)
**Performance:** Degradation risk: {before_risk} → {after_risk} | CLAUDE.md: {before_status} → {after_status}

**Next Steps:**
1. Test optimized rules in new Claude session
2. Verify Claude behavior matches expectations
3. Commit: git add . && git commit -m "Optimize AI rules configuration"
4. Share with team if in git
5. Run ai-optimizer quarterly for maintenance
```

## Guiding Principles

### Determine Single Source of Truth

**FIRST:** Ask developer which file should be the single source of truth:
```
Multiple AI config files found. Which should be your single source of truth?
(a) AGENTS.md (conventional) | (b) CLAUDE.md (Claude Code) | (c) .cursorrules (Cursor) | (d) Other: ___
Recommendation: Choose file that's most complete, matches primary AI tool, easily imported by others.
```
Once determined, all consolidation recommendations use this file as target.

### Core Principles

- **Single source of truth** - One file contains core rules. Others import, extend for tool-specific needs, or are eliminated.
- **Never delete without asking** - Developer may have reasons for apparent redundancy.
- **Preserve intent** - When merging phrasings, keep the more precise one.
- **Tool-specific overrides OK** - Must be explicitly marked as overrides, not silent contradictions.
- **Less is more** - Fewer, clearer rules beat verbose ones. AI tools perform better with concise instructions.
- **One example per concept** - If one code sample demonstrates clearly, additional examples are noise.
- **Optimize for token efficiency** - Every token consumes context window. Bloated files = less room for code. Aim for smallest file preserving all unique intent.
- **Follow best practices** - All recommendations align with [official Claude Code best practices](https://code.claude.com/docs/en/best-practices).

### Consolidation Strategy

When consolidating:
1. **Keep in single source of truth** - Core rules in chosen main file
2. **Tool-specific files import** - Use `@path/to/main.md` syntax
3. **Overrides explicitly marked** - Example: `# .cursorrules` → `See @AGENTS.md for core rules.` → `## Cursor-specific overrides: [Override] Use inline completions (AGENTS.md says plan first)`
4. **Delete truly redundant files** - If only duplicates, delete entirely

### Edge Cases & Special Situations

**If no issues found:**
```
✅ Congratulations! Your AI rules are already optimized.
No issues: Zero conflicts | Zero redundancies | Zero bloat | CLAUDE.md: {n} tokens (✅ OK)
Your project follows Claude Code best practices!
```

**If CLAUDE.md >4000 tokens (critical):**
```
🚨 CRITICAL: CLAUDE.md is {n} tokens (>400% of recommended max)
This WILL cause Claude to ignore your instructions!
URGENT: 1. Move domain knowledge to skills (.claude/skills/) | 2. Move workflows to skills | 3. Link to external docs instead of embedding | 4. Remove inferable-from-code bloat | 5. Keep only what Claude CANNOT figure out
Target: Get under 2000 tokens
```

**If tool-specific contradictions found:**
```
⚠️ Found tool-specific contradictions (may be intentional)
Example: AGENTS.md "plan before coding" vs .cursorrules "use inline completions"
These might be intentional tool preferences. Mark as [Override] to acknowledge.
```

**If files in git:**
```
ℹ️ AI rules checked into git. This is good! Team shares conventions.
After optimization, commit changes so everyone benefits.
```
