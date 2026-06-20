---
name: sonarqube-test-coverage
description: Drive test coverage up to the SonarQube new-code gate on a chosen scope (specific files, staged/unstaged changes, a diff target, or a module) using the project's own coverage report. Runs the coverage command, identifies uncovered/partially-covered lines, writes targeted tests following the project's installed testing rules, and iterates until the gate is met. No SonarQube API dependency — use when coverage on new code is below the gate and coverage is the only finding (the PR-comment fixer handles full SonarQube findings).
disable-model-invocation: true
---

# SonarQube Test Coverage

Closes coverage gaps on a chosen scope so a PR clears SonarQube's **new-code coverage gate** (commonly 80%). Target **100%** on in-scope lines to keep buffer.

**MANDATORY:** all test code written here must follow the project's installed rules at `{standards_location}` (from `config_hints.json`) — the stack's unit-testing rule (what to test per layer, structure, and how to read the coverage report), its SonarQube/lint-compliance rule (assertion idioms, dead code, matcher rules), its coding-conventions rule (formatting, naming), and its module-boundary rule (don't cross-import across layers in tests). Violations are bugs.

## When to Use

- Raising coverage on specific files before opening a PR
- Closing a coverage-only finding from the SonarQube bot (if there are non-coverage findings too, use the PR-comment fixer)
- Improving coverage on a whole module
- Local pre-push check: "what would Sonar flag as uncovered new code?"

## Scope

The skill asks for the scope if it isn't clear:

1. **Specific files** — production source-file paths
2. **Staged/unstaged changes** — via `git diff --name-only` / `git diff --cached --name-only`
3. **Diff target** — e.g. `origin/main...HEAD` (resolves changed production files)
4. **Module** — a single build module that the coverage tool reports on

Only production source files are in scope. Test files, generated sources, and migrations are filtered out.

## The Coverage Command

Resolve, in order:
1. `config_hints.json` → `coverage.command` (and `coverage.report_glob`, `coverage.report_format`) if present — the project's curated coverage invocation and report location.
2. Otherwise the coverage command documented in the project's installed unit-testing rule (`{standards_location}`).
3. Otherwise derive from `test_command` + the stack's standard coverage task, and **state the assumption** to the user.

**Always bypass the build cache** when running coverage — most runners cache test/coverage results and will serve a stale report that doesn't reflect newly added tests. The stack's unit-testing rule documents the exact cache-bypass flag and report path; follow it.

## Pipeline (every invocation)

### Phase 1 — Run coverage
Map the scope to the coverage command, run it (cache bypassed), and locate the report file(s). For a scope spanning a module the aggregated report doesn't cover, run that module's own coverage task and read its module-local report.

### Phase 2 — Analyze
Parse the report for each in-scope source file and classify every executable line as covered / partially-covered / not-covered / branch-gap, per the line-classification rules in the project's installed unit-testing rule (coverage-report section). When a **diff target** was given, intersect the gaps with `git diff --unified=0 <target> -- <file>` so only **newly added or modified** lines remain in scope; for explicit file scopes, all uncovered lines in those files are in scope.

### Phase 3 — Present gaps
Show a structured report: per file, the in-scope covered/total line count and percentage, and each uncovered/partial line with its code snippet and reason (not covered / partial branch). If every in-scope line is already covered, report success and stop.

### Phase 4 — Write tests
1. Read each production file in full to understand control flow — coverage hits aren't the goal, meaningful tests are.
2. Read existing tests for the affected classes to match fixtures, helpers, and naming.
3. Write targeted tests that cover every uncovered/partial line and branch in scope, placed in the test tree mirroring the production package, following all four installed rules cited above.
4. **Flag unreachable lines.** If a branch can't be hit through the public API (defensive guards on impossible inputs, etc.), don't contort the test — record it under "Remaining gaps" with the reason.

### Phase 5 — Verify
Re-run coverage (cache bypassed) and re-parse. If in-scope coverage is still short, write more tests. **Cap at 3 iterations**, then declare residual lines unreachable and surface them. Then run the project's lint/format check and the affected tests, and a full build, to confirm nothing else broke. Never leave lint red.

### Phase 6 — Summary
Present a per-file before/after table, the tests added (file → method names → what each covers), any remaining gaps with reasons, and the verification results (lint / tests / build pass-fail).

## Rules

- **Be transparent about unreachable code** — flag it, don't contort tests to hit it.
- **This skill does not commit or push** — the caller commits (use the commit skill, which requires user approval).
- **This skill does not touch integration tests** — integration coverage is enforced separately.
