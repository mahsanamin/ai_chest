# Plan: Stack-Agnostic Adaptation (stop language-idiom leakage)

## DECISION (LOCKED 2026-06-05) — do not re-litigate

**Model A is canonical: generic skills/agents + stack-specifics in `rules/`.** Skills/agents carry zero language idioms and **defer to the project's installed rules in `standards_location`** for stack conventions; the installer adapts *rules* per stack (and populates the `config_hints` command seam), never the skill/agent bodies. **Rejected: Model B (per-stack-adapted skill bodies)** — it reopens wrong-language leakage (seen in PR #417), forces per-stack skill variants / re-adaptation on every upgrade, and makes upgrades a drift risk. The only accepted cost of Model A — an agent spends a couple of file-reads to reach the specifics — is mitigated by the v7.7.1 rules-bridge. Per-project inline cues are still allowed via a `<!-- project-override -->` block (Smart Diff preserves it). **The right investment for depth on new stacks is W6 (author `rules/<stack>/`), not forking skills.** Verified end-to-end on PR #418 (Java target, v7.7.1): generic skills + Java-rich rules + populated command seam, validation loops intact.


**Status:** **W2/W5 in v7.5.0; W3/W4 corrected to *fully generic* in v7.5.1.** v7.5.0's detect-and-branch enumerations turned out to still hold language knowledge in skills/agents (PR #417 showed Go/Rails/iOS idioms landing in a Java repo's agents) — v7.5.1 removes them: skills/agents now carry **zero** language knowledge and defer to `config_hints` commands + installed rules; stack handling lives only in the installer/upgrader + the Step 16b guardrail. W1 (config seam) landed via `stack`/`test_command`/`lint_command`/`verify.full_command`. **W7 DONE** (`scripts/aa-lint/generic-skill-lint.sh` — fails on any language idiom in skill/agent bodies; passes today). **W6 DONE/reframed:** `rules/_generic/core-engineering-standards.md` authored (language-neutral fallback, installed for unmatched stacks); `aa-task-flow-review` Java examples cleaned. Per-stack `rules/go|ruby|ios|android/` are **created on-demand via the W8 tier on-ramp** from real recorded improvements — NOT speculatively pre-authored (no real target to validate against, and that's the locked Model-A growth path). · **Owner:** framework · **Target:** installer/upgrader + rules (NOT skill/agent bodies)

## Problem (one sentence)

`aa-install` / `aa-upgrade` write **one language's idioms into a repo of another language** — Java's `gradlew`, `*Test.java`, `@RequestMapping`, JPA Detection Map land in Go / Ruby / any non-Java repo — because stack-awareness is applied only to *which rule files get copied*, not to the *skill/agent content* (and embedded Detection Maps, commands, and rule references) that is authored in Java.

## Scope

**In scope (the one real defect):** never emit a language's idioms / commands / detection-signals / rule-references into a repo that isn't that language. Genericize when no curated stack exists; never borrow the nearest language cousin.

**Explicitly OUT of scope** (these were either the lead's own assumptions or already-correct framework behaviour — do **not** change them here):
- Namespace example rewrites (`OPS`↔`PROJ`) and other project-identity values.
- Change-type-gated rule loading (the lead's optimization).
- Database rename / schema adaptations — these were **correct**.
- Config nits unrelated to language leakage.

## Evidence

1. **Go repo Detection Map diff** — `aa-task-flow` shipped the Java "Signal → rule" table (`@Transactional`, `JpaRepository`, `@RestController`, `build.gradle`) into a Go repo; lead hand-rewrote it to Gin/GORM.
2. **Android detection logic** (`setup.md` pre-detection) — `build.gradle` present → `JAVA_BUILD_DETECTED` → `java-spring-boot` rules. Android is Java/Kotlin but **not** Spring; language match ≠ stack.
3. **pandora upgrade commit** (`7ee9c407`, v3.4→v7.2.0, Go) — message says *"Pandora is Go, only universal rules apply, Java/React stack rules skipped"* yet it wrote into skill/agent **bodies**: `@RequestMapping`/`application.yml`/`pom.xml` (`aa-plan-verifier`), `./gradlew test` (`aa-test-runner`), `*Test.java`/JUnit/Mockito/`checkstyleMain` (`aa-task-flow`), and the full Java Detection Map in `aa-review-pr` — whose grep signals point at `jpa-repositories.md` / `transaction-boundaries.md` / `api-conventions.md`, **rule files the same install deliberately did not install** (dangling references).

## Root cause

**Stack-awareness lives at the wrong layer.** The pipeline decides *which `rules/` dirs to copy* by stack, but:
- **Skills are installed `action: created` (verbatim); only `rules/` are `adapted`** (`setup.md` manifest). So Java idioms embedded in skill/agent prose are copied as-is into every repo.
- The **Detection Map, build/test/lint commands, and test conventions live inside the skill/agent bodies** (Java-authored), not in adaptable rule files.
- There is **no "genericize, don't borrow" fallback** and **no post-write guardrail**, so a non-Java repo silently receives Java idioms and dangling Java rule references.

## Design principles

1. **Language ≠ stack.** A stack's idioms apply only on *positive evidence* of that stack (e.g. Spring import / `@SpringBootApplication`, not merely `build.gradle`). Android (`AndroidManifest.xml` / `com.android.*`) and Spring are different stacks despite sharing the JVM.
2. **Skills/agents are language-neutral.** Their bodies must not hardcode any language's commands, file patterns, or detection signals.
3. **Genericize, never borrow.** No curated rule set for the detected stack → universal + repo-derived conventions. Never substitute the nearest language cousin.
4. **Assert, don't assume.** After install/upgrade, verify no foreign-language idioms were written and no referenced rule file is missing.

## Decomposition (each ≈ one PR; arrows = depends-on)

- **W1 — Stack/language identity contract.** Record the repo's detected language(s) + stack + `standards_dir` + a rule-name map in `config_hints.json` / `skill.config` as the single source of truth. *(foundation)*
- **W2 — Language/stack-aware detection** ← W1. Replace the language-keyed pre-detection with a positive-evidence matrix (Android ≠ Spring; emit `generic` when unmatched).
- **W3 — Neutralize skill bodies** ← W1. Move the Detection Map to an adapted/config-driven artifact; move build/test/lint commands and test conventions to config. Skill prose says "run the project's test command / load the project's detection map," never `./gradlew` / `*Test.java`.
- **W4 — Neutralize agent bodies** ← W1. Same treatment for `aa-plan-verifier`, `aa-test-runner`, `aa-code-reviewer`, etc.
- **W5 — Guardrail + post-write assertion** ← W2,W3,W4. Refuse to write idioms/commands/**rule references** for a language/stack not present; after writing, assert (a) no foreign-language tokens (`gradlew`/`*Test.java`/`@RequestMapping` in a non-JVM repo) and (b) **every referenced rule file exists** in the target's `standards_dir` (kills the dangling-reference case).
- **W6 — Generic fallback set** ← W2. A `rules/_generic/` baseline so unmatched stacks have real content to use instead of Java. (Seeding real `rules/go/`, `rules/android/`, `rules/ios/` is optional follow-up, not required for the fix.)

**Sequencing:** W1 first → W2/W3/W4 in parallel → W5 gate → W6.

## Risks / notes

- W3/W4 touch large skill/agent files — keep diffs mechanical (extract, don't rewrite intent) and lean on W5's assertion to catch regressions.
- `aa-upgrade` must apply the same neutral-content rule on its fast/inline path (once bodies are neutral, verbatim copy is safe for any stack).
- This plan does **not** require per-stack rule authoring to ship the fix; genericize-don't-borrow (W6) + the guardrail (W5) stop the bleeding for every language immediately.

## Audit findings (framework-wide sweep, 2026-06-04)

Sweep of the **verbatim-copied surface** (skills + agents + templates; `rules/` are adapted so excluded). Confirms the leak is framework-wide, not isolated to the reported repos.

**Hard leaks — Java presented as *the* way (must be neutralized: W3/W4):**
- `skills/aa-task-flow/SKILL.md` — `*Test.java` + `src/test/java` (1056), JUnit 5/Mockito/AssertJ (1066), `./gradlew :module-server:test` (1083/1086), `./gradlew checkstyleMain` (1095), Detection Map row `@Transactional → transaction-boundaries.md` (2430), Lombok/Javadoc in always-apply list (1010/2453).
- `skills/aa-review-pr/SKILL.md` — the **entire Java Detection Map** (236–241) + executable grep signals (`@Transactional`/`JpaRepository`/`@RestController`/`@Entity`) loading `transaction-boundaries.md`/`jpa-repositories.md`/`api-conventions.md`/`database-migrations.md` (252–256).
- `skills/aa-task-flow-review/SKILL.md` — `@Transactional` example violations referencing `transaction-boundaries.md` (5 hits).
- `agents/aa-plan-verifier/AGENT.md` — `@RequestMapping`/`@RestController`/`@GetMapping` (27–28), `application.yml` (38), `pom.xml`/`build.gradle` (43). *(Framework source is still Java; the pandora repo's stack-aware version was a project-local hand-fix.)*
- `agents/aa-test-runner/AGENT.md` — Gradle-first default `./gradlew test` (22). Lower risk (lists Maven/npm too) but Gradle-led.

**Dangling rule references — verbatim skills point at Java-only rule files (W5 assertion):**
- 9 `rules/java-spring-boot/` filenames (`api-conventions`, `coding-conventions`, `commands`, `database-migrations`, `jpa-repositories`, `metrics-collection`, `project-structure`, `query-efficiency`, `transaction-boundaries`) are referenced from `aa-task-flow`, `aa-review-pr`, `aa-task-flow-review`.
- `setup.md` (629–631) installs **universal-only** for Frontend/iOS/Android (and any non-Java) — so every one of those references **dangles** in a non-Java repo. This is exactly the pandora symptom, framework-wide.

**Detection conflation (W2):**
- `setup.md` pre-detection: `build.gradle` present → `JAVA_BUILD_DETECTED` → `["universal","java-spring-boot"]` (77/84). Android has `build.gradle`, so it can be routed to Spring — contradicting the table at 628–631 that says Android → universal only. Language ≠ stack, unresolved.

**The good model already in-repo (replicate in W3/W4):**
- `skills/aa-global-pr-reviewer/SKILL.md` (407–523) **detects and branches** the build system at runtime (`if build.gradle … elif pom.xml … elif package.json …`) and only runs the matching commands. Its ~15 "Java" hits are conditional/multi-stack, not assumptions. This is the pattern the per-project skills/agents should follow.

**Verification of *our* PR's own changes:** the v7.3.0/7.4.0/7.4.1 edits are largely language-neutral (Change Class table, `test-change-policy.md`, plan-verifier check #8, `aa-ticket-creator`). The one caveat: the Phase 4g additions in `aa-task-flow` (1412–1443) use `./gradlew test --rerun-tasks` as the worked example — Gradle-flavored — though they introduce `verify.full_command` as the stack-neutral escape hatch W3 will build on. **Our changes did not worsen the leak; they added the config seam the fix needs.**

## Architectural north star (the real target — clarified 2026-06-04)

The framework was *designed* to be generic; the leak was an implementation violation (Java reference impl copied verbatim into the orchestration layer). The end-state, stated as a hard invariant:

> **INVARIANT: no `skills/`, `agents/`, or installer file may contain a language-specific idiom.** All language/stack knowledge lives in `rules/`. Skills are pure orchestration: *detect stack → load `rules/universal/` + `rules/<stack>/` → apply; read commands from `config_hints.json`.*

Layering:
- **Generic tier** (`rules/universal/`) — cross-language: code-review, critical-thinking, test-change-policy, learning-routing, task, mcp-integration.
- **Per-stack tiers** (`rules/java-spring-boot/`, `rules/react/`, and to-be-authored `rules/go/`, `rules/ruby/`, `rules/ios/`, `rules/android/`, …) — everything language-specific: test framework/commands, endpoint idioms, ORM/DB patterns, lint/format, project layout. Adding a language = adding a dir; **skills never change**.
- **Growth mechanism:** `learning-routing.md` + `aa-record-improvement` place a *stack-specific* learning into the matching per-stack tier and a *generic* learning into `universal/` — they must **never** bake stack knowledge into a skill/agent.

**Status of v7.5.0 against this invariant:** the guardrail + positive-evidence detection are end-state-correct and stay. The **detect-and-branch enumerations now inside skills/agents are TRANSITIONAL** — they keep things safe before per-stack rule dirs exist, but they still hold stack knowledge in the wrong layer. W6 moves that knowledge into `rules/<stack>/`; W7 then deletes the enumerations and forbids their return.

### Added work items

- **W7 — Source-side generic-skill lint (makes the invariant enforceable).** A CI/check in the framework repo that scans `skills/` + `agents/` for language idioms (`gradlew`, `@RestController`, `*Test.java`, `JpaRepository`, `application.yml`, …) and **fails** on any hit. This is the framework-repo twin of the Step 16b target-side guardrail. Once green, the transitional detect-and-branch lists (W3/W4) are removed and replaced by pure "load `rules/<stack>/`" deference.
- **W8 — Tier-aware learning routing.** Extend `rules/universal/learning-routing.md` and `aa-record-improvement` with a fourth axis on top of project/framework/conversational: **which tier** — stack-specific learning → per-stack rule dir (`rules/<stack>/` or `docs/ai-rules/<stack>/`); cross-language → `universal/`. Never a skill/agent body.
