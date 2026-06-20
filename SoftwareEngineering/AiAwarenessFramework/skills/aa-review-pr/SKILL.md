---
name: aa-review-pr
description: Review pull requests against project coding rules. Accepts one or more PR numbers/URLs. Say "aa-review-pr" or "review pr".
disable-model-invocation: true
---

# Review PR

Standalone code review skill that reviews any pull request against project coding rules. Uses the same project code reviewer agent and the same rules as `aa-task-flow-review` — different entry point, same review engine.

Generates a lean draft with only real problems and decision-relevant notes. User controls which comments get posted to GitHub.

## When to Use

- Review a teammate's PR before approving
- Review your own PR before requesting review
- Review multiple related PRs together (e.g., a feature split across PRs)
- Quick review of any open PR by number or URL
- Quick terminal-based review — just say `aa-review-pr` and provide the PR number

## How to Use

```bash
# Single PR by number
> aa-review-pr 216

# Single PR by GitHub URL
> aa-review-pr https://github.com/{org}/{repo}/pull/216

# Multiple related PRs
> aa-review-pr 219 220 221

# No arguments — Claude will ask for PR number/URL
> aa-review-pr
```

## Working Directory

Review working files are saved to the `reviews_root` path, resolved in this order:
1. `reviews_root` from `.claude/skill.config` (explicit)
2. Derived from `tasks_root` → sibling `CodeReviews/` directory (e.g., `.../Coding_Tasks/CodeReviews/`)
3. Fallback: `.claude/reviews`

This directory lives in the coding tasks project (git-ignored from the main repo). The PR itself is the permanent record (comments posted there).

This skill does not modify any **tracked** files — its only writes inside the repo tree are to git-ignored AI-framework paths: the `_schema_version` stamp in `.claude/skill.config` (Step 2) and any review artifacts written to the `reviews_root` / `.claude/reviews/` fallback. These paths MUST be git-ignored — this is guaranteed at install time (`.claude/skill.config` and `.claude/reviews/` are in `.gitignore`). The read-only guarantee depends on that gitignore coverage: if `.claude/skill.config` or `.claude/reviews/` were NOT git-ignored, the schema bump / review artifacts would dirty the repo.

```text
{reviews_root}/
├── PR-220-cancellation-processor/
│   ├── review.diff                      ← Diff for agent to read
│   └── review-draft.md                  ← Draft with checkboxes (user reviews here)
└── PR-219-batch-cancel-api/
    ├── review.diff
    └── review-draft.md
```

Files are overwritten on each run for the same PR — no accumulation.

## Implementation

**Only 2 interaction points — do NOT add more:**
1. **Step 1** — Ask which PR (only if user didn't provide one)
2. **Step 10** — Present draft and ask which comments to post

Everything else (fetching, triage, review, scoring) runs without asking. Show progress with short status messages, never confirmation prompts.

When this skill is invoked, follow these steps:

### 1. Resolve Pull Request(s)

Parse user input to determine which PR(s) to review.

```text
# Parse input:
# - Numbers (219, 220, 221) → use directly as PR numbers
# - GitHub URLs → extract number from /pull/NNN
# - Mixed input → extract all PR numbers
# - No input → ASK the user:
#     "Which PR would you like me to review? Provide a PR number or GitHub URL."
#     Do NOT auto-detect from current branch. Always ask.
```

### 2. Resolve Working Directory

```bash
# Version check — silently update skill.config if behind framework_version
current=$(jq -r '._schema_version // ""' .claude/skill.config 2>/dev/null)
framework=$(jq -r '.framework_version // ""' .claude/config_hints.json 2>/dev/null)
if [ -n "$framework" ] && [ "$current" != "$framework" ]; then
  # Currently just a version stamp. All new paths are derived from tasks_root
  # at runtime, so no migration is needed. If a future version requires
  # structural changes to skill.config, add migration logic here.
  jq --arg v "$framework" '._schema_version = $v' .claude/skill.config > /tmp/skill.config.$$ && mv /tmp/skill.config.$$ .claude/skill.config
fi

# Read reviews_root from skill.config (explicit path takes priority)
reviews_root=$(jq -r '.paths.reviews_root // ""' .claude/skill.config 2>/dev/null)

# Fallback: derive from tasks_root → sibling CodeReviews directory
if [ -z "$reviews_root" ]; then
  tasks_root=$(jq -r '.paths.tasks_root // ""' .claude/skill.config 2>/dev/null)
  if [ -n "$tasks_root" ]; then
    # tasks_root is e.g. .../Example_Coding_Tasks/Backend
    # reviews_root → .../Example_Coding_Tasks/CodeReviews
    reviews_root="$(dirname "$tasks_root")/CodeReviews"
    mkdir -p "$reviews_root"
  else
    reviews_root=".claude/reviews"
  fi
fi
```

### 3. Fetch PR Details (for each PR)

```bash
# Get PR metadata
gh pr view {pr_number} --json number,title,body,author,baseRefName,headRefName,url,additions,deletions,changedFiles
```

Extract: `pr_number`, `pr_title`, `pr_url`, `base_branch`, `head_branch`, `author`, stats.

### 4. Detect Ticket

Silently extract ticket from branch name or PR title. Do NOT prompt the user.

```text
# Read namespace prefix from config_hints.json
namespace=$(jq -r '.project.namespace // .project.default_namespace // ""' .claude/config_hints.json 2>/dev/null)

# Try to extract {NAMESPACE}-XXX pattern from:
# 1. head_branch (e.g., feature/{namespace}-371-attachment-upload → {NAMESPACE}-371)
# 2. pr_title (e.g., "[{NAMESPACE}-371] Add attachment upload" → {NAMESPACE}-371)
# 3. pr_body (look for {NAMESPACE}-XXX or Jira URL)
#
# If found: ticket = "{NAMESPACE}-XXX"
# If not found: ticket = null (proceed without it — don't ask, don't block)
```

### 4b. Locate Originating Task Folder (silent — best-effort)

If we detected a ticket in step 4, try to find the task folder that produced this PR. Reviewing without knowing what the author *intended* is the #1 source of nitpick comments — the agent flags things that contradict the actual goal.

```bash
# tasks_root from skill.config; same source used by aa-task-flow / aa-task-flow-resume
tasks_root=$(jq -r '.paths.tasks_root // ""' .claude/skill.config 2>/dev/null)

if [ -n "$ticket" ] && [ -n "$tasks_root" ]; then
  # Look for a folder under {tasks_root}/OnGoingTasks or {tasks_root}/DoneTasks whose
  # name starts with the ticket id (case-insensitive). Match the convention
  # aa-task-flow uses: {TICKET}-{sanitized-title}/
  task_folder=$(find "$tasks_root"/OnGoingTasks "$tasks_root"/DoneTasks -maxdepth 1 -type d 2>/dev/null \
                | grep -i "/${ticket}-" | head -n 1)
fi
```

If `$task_folder` resolves, collect these files (any subset may exist — read whichever do):

- `executive_summary.md` — the 2–3 line digest of intent (Phase 1 may have created one)
- `prompt-understanding.md` — the human-refined requirements
- `execution_plan.md` — the plan and acceptance criteria
- `acceptance_criteria.json` — machine-checkable contract (every row should be `passes: true` if Phase 4 ran)

Pass their absolute paths into the agent prompt in step 9. **If none resolve** (no ticket, no tasks_root, or no matching folder), proceed — but note `Task intent source: not found` in the agent prompt so the agent explicitly records this in its report header rather than guessing.

This is silent on success and silent on failure. Do not block the review on missing task context.

### 5. Create Review Folder & Generate Diff (for each PR)

```bash
# Create review folder using PR number and sanitized title
review_dir="{reviews_root}/PR-{pr_number}-{sanitized_title}"
mkdir -p "$review_dir"

# Save diff for agent to read
gh pr diff {pr_number} > "$review_dir/review.diff"
```

### 6. Fetch Existing PR Comments

Before reviewing, fetch all existing comments on the PR to avoid duplicating feedback and enable agree/disagree analysis.

**Run these in parallel:**

```bash
# Inline review comments (on specific file+line)
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments --paginate

# PR conversation comments (general timeline)
gh api repos/{owner}/{repo}/issues/{pr_number}/comments --paginate
```

**Pass raw results to the agent as context.** The agent (the actual reviewer) will classify, group, and assess comments during its review. Do NOT pre-process or analyze comments in the main skill — keep orchestration simple.

**Truncation:** If combined comment JSON exceeds ~50KB, keep only the most recent 30 comments (sorted by `updated_at` descending). Large review threads consume agent context that's better spent on the actual diff.

If API calls fail (e.g., permissions), proceed without existing comments and note the limitation.

### 7. Large Diff Triage

Count total additions from the diff. Adjust review strategy:

| Total Additions | Strategy |
|-----------------|----------|
| < 400 lines | **Full review** — all files thoroughly |
| 400–800 lines | **Prioritized** — deep on logic, skim tests/config |
| > 800 lines | **Tiered** — classify files before reviewing |

**Tiered review (>800 lines):**
- **Tier 1 (full)**: Business logic, new classes, security-relevant changes
- **Tier 2 (scan)**: Tests, config, simple renames/moves
- **Tier 3 (skip)**: Generated code, lock files, migration boilerplate

Display to user (informational — do NOT ask for confirmation, just proceed):
```text
Diff: {additions} additions, {file_count} files → {strategy}
```

For tiered reviews, also show the tier breakdown before proceeding.

### 8. Load Coding Rules (Selective)

```bash
standards_dir=$(jq -r '.standards_location // "docs/ai-rules"' .claude/config_hints.json 2>/dev/null || echo "docs/ai-rules")
```

**Do NOT read all rule files.** Scan the diff from Step 5 to detect which patterns are present, then load only the matching rules.

**Always load:**
- `code-review.md` — review format, severity levels, output structure
- `critical-thinking.md` — challenge assumptions, verify before suggesting
- `coding-conventions.md` — general coding standards (if any code files changed)

**Load based on diff detection** — match against the rules **this project actually has** in `{standards_dir}/`. Only ever load a rule file that exists there.

```bash
diff_file="$review_dir/review.diff"

# Add a rule ONLY if it exists in this project's standards_dir.
add_rule() { [ -f "$standards_dir/$1" ] && case " $rules " in *" $1 "*) ;; *) rules="$rules $1";; esac; }

rules="code-review.md"
add_rule critical-thinking.md
add_rule coding-conventions.md   # name varies by project; loaded only if present

# Match the diff against the rules THIS repo has. Detection precedence per rule:
#   1. alwaysApply: true    → load unconditionally (rules that apply to every diff of this stack)
#   2. triggers: [re, …]    → load if the diff matches ANY regex the rule declares in its
#                             `triggers:` frontmatter (the precise signal — each rule names the
#                             symbols/paths/file patterns that should pull it in)
#   3. fallback (no frontmatter signal) → load if the diff matches any hyphen-separated filename
#                             token as a WHOLE WORD. No minimum-length skip — a 3-letter stem like
#                             "abc" matches as \babc\b, never silently dropped for being short.
for rule_file in "$standards_dir"/*.md; do
  [ -f "$rule_file" ] || continue
  base=$(basename "$rule_file")
  [ "$base" = "task.md" ] && continue

  # Read YAML frontmatter (between the first two '---' lines), if any.
  fm=$(awk 'NR==1 && $0=="---"{f=1; next} f && $0=="---"{exit} f' "$rule_file")

  # (1) alwaysApply
  if printf '%s\n' "$fm" | grep -qiE '^alwaysApply:[[:space:]]*true'; then
    add_rule "$base"; continue
  fi

  # (2) triggers: [ "re1", "re2", … ]  (inline array form). Patterns may contain [ ] (e.g. V[0-9])
  #     but MUST NOT contain a comma — items are split on comma. ⚠️ A regex interval quantifier like
  #     `x{2,5}` WOULD split into two broken patterns ("x{2" and "5}"); if you need a bounded repeat,
  #     write it comma-free (e.g. `xx*` or a char class) instead. Use shell trimming, not regex, here
  #     to avoid bracket pitfalls.
  tline=$(printf '%s\n' "$fm" | grep -E '^triggers:[[:space:]]*\[')
  if [ -n "$tline" ]; then
    # Drop the 'triggers:' key and the outer [ ] (anchored, so inner [0-9]/[.] survive), split on comma.
    body=$(printf '%s\n' "$tline" | sed 's/^triggers:[[:space:]]*//; s/^\[//; s/\][[:space:]]*$//')
    if printf '%s\n' "$body" | tr ',' '\n' | while IFS= read -r pat; do
          pat=$(printf '%s' "$pat" | sed 's/^[[:space:]]*["'\'']\{0,1\}//; s/["'\'']\{0,1\}[[:space:]]*$//')
          [ -z "$pat" ] && continue
          grep -qiE "$pat" "$diff_file" && { echo hit; break; }
        done | grep -q hit; then
      add_rule "$base"
    fi
    continue
  fi

  # (3) fallback (rule declares no signal): match any hyphen-separated filename token.
  #     Long tokens (>=4) substring-match — so "controller" still catches "OrderController";
  #     short tokens (<4) match as a WHOLE WORD — so "api"/"jpa"/"mcp" match \bapi\b (the old <4
  #     skip is gone) without "api" spuriously firing inside "rapid"/"capital".
  hit=0
  while IFS= read -r tok; do
    [ -z "$tok" ] && continue
    if [ ${#tok} -lt 4 ]; then rx="\\b${tok}\\b"; else rx="$tok"; fi
    grep -qiE "$rx" "$diff_file" && { hit=1; break; }
  done <<EOF
$(echo "${base%.md}" | tr '-' '\n')
EOF
  [ "$hit" = 1 ] && add_rule "$base"
done
```

Read only the matched rule files. Store as `RELEVANT_RULES` with file names for the agent prompt.

Display: `Rules loaded: {list of loaded rule files} ({count}/{total} rules)`

### 9. Run Code Review Analysis

**Single PR**: One code reviewer agent call.
**Multiple PRs**: Launch agents in **parallel** (one per PR), then consolidate.

The agent performs five phases:
1. **Business flow analysis** — understand operations, failure modes, transaction boundaries
2. **Changes overview** — summarize what changed and why (Before → After)
3. **File-by-file review** — with existing comments context for agree/disagree
4. **Self-review** — re-verify every comment against actual code, drop hallucinations
5. **Draft output** — lean markdown: only problems (postable) and decision-relevant notes (internal)

For each PR, use the Task tool:

```text
Task(
  subagent_type="{project}-code-reviewer",  # or "aa-code-reviewer" if no project-specific agent
  description="Review PR #{pr_number} against rules",
  prompt="Review pull request #{pr_number} against project coding rules.

  ## Fresh-Memory Operating Rule

  You start with no carry-over from the invoking session's conversation. Read everything you need from the files below. If a fact isn't in those files, the diff, or the source code you read — you don't know it. Do not infer caller behavior from your training data; trace actual callers.

  ## PR Context
  - **PR**: #{pr_number} — {pr_title}
  - **URL**: {pr_url}
  - **Author**: {author}
  - **Branch**: {head_branch} → {base_branch}
  - **Ticket**: {ticket or 'None detected'}
  - **Stats**: +{additions} -{deletions}, {changedFiles} files
  - **Review strategy**: {Full / Prioritized / Tiered}

  ## PR Description
  {pr_body}

  ## Task Intent (read these BEFORE the diff)

  {If $task_folder resolved in step 4b, list each file that exists:}
  - {task_folder}/executive_summary.md — 2-3 line digest of what this work was supposed to do (if present)
  - {task_folder}/prompt-understanding.md — human-refined requirements
  - {task_folder}/execution_plan.md — implementation plan and acceptance criteria
  - {task_folder}/acceptance_criteria.json — machine-checkable contract; every row should be passes: true

  {Otherwise:}
  Task intent source: not found (no linked task folder for {ticket}). Review from PR description + diff only. State this explicitly in your report header so the human knows the review wasn't grounded in stated intent.

  Read these files (if any exist) BEFORE reading the diff. They tell you what the author was *trying* to do. A comment that contradicts the stated intent is wrong, not insightful — drop it.

  ## Coding Rules (pre-selected — read these before reviewing)
  {For each file in RELEVANT_RULES:}
  - {standards_dir}/{rule_file}
  {End for}
  Read ONLY these rule files. They were selected based on patterns in the diff.

  ## Diff
  Read: {review_dir}/review.diff
  The diff tells you WHICH files changed. Your review is based on the full
  source files, not the diff.

  ## Existing PR Comments
  {Raw EXISTING_COMMENTS JSON from Step 6, or 'None.'}
  Check existing comments before writing new ones — avoid duplicates,
  agree with valid concerns, disagree (with explanation) if a comment is wrong.

  ## Review Principles

  **A clean PR with zero comments is a good outcome.** Do not manufacture
  issues to fill the review. Only comment when you've found a real problem
  you can prove with a concrete code path.

  - Review against the actual contract: code comments, doc comments, PR description,
    and existing patterns. If the author documents why something is done a
    certain way, the only valid issue is if that reasoning itself is flawed.
  - "What if X changes behavior" is not actionable — it applies to every
    integration and is not a review comment.
  - Every comment must cite evidence: a specific caller, a concrete null
    source, an actual execution path. "This could be X" is not a comment.
    "Caller Y passes null at line Z, which reaches here unchecked" is.

  ## Review Process

  1. **Business flow**: Read the PR description, then read the KEY source
     files (not just the diff) to understand the operation, failure mode,
     caller expectations, and transaction boundaries. Do NOT suggest changes
     that break the intended behavior.

  2. **Review each changed file**: For EACH file in the diff, read the FULL
     source file FIRST, then review the changes with full context. When a
     comment depends on how a method is called or what it returns, trace the
     actual callers/callees in the codebase — do not guess. Apply the coding
     rules above. For each issue assign type (Bug/Error, Security, Missing,
     Question, or Trade-off) and dual score (Score 0-100 for normal review,
     Urgent 0-100 for urgent merge). All comments MUST be inline (file + line).
     Do NOT create Praise or "looks good" comments.

  3. **Self-review — re-read and prove each comment**: For EACH comment you
     wrote, go back to the source file and verify your specific claim:
     - Can you point to a concrete execution path that triggers this issue?
     - Did you check who actually calls this method and what they pass?
     - Did you check what the called method actually returns/throws?
     - Is the issue in the NEW code, or was it pre-existing and unchanged?
     - Does the code comment or PR description explain this choice?
     If you cannot answer these concretely — drop the comment. Do not keep
     comments based on "it seems like" or "it could be." Silently discard.

  ## Output Format — Lean Review

  Every comment in the draft must be USEFUL. If it doesn't help someone make a
  decision or fix a problem, it doesn't belong — not even as an internal note.

  ### What goes in the draft:

  **Context sections** (brief — help the reviewer understand):
  - Changes Overview — 1-3 sentences, Before → After
  - Business Flow — operation, failure mode, boundaries (omit if trivial)
  - Existing PR Comments — only threads needing follow-up (omit if none)

  **Comments** (the core of the review):
  Every comment must be one of:
  - **Bug/Error** — incorrect behavior, logic error, data loss risk
  - **Security** — vulnerability, injection, auth bypass
  - **Missing** — required migration, null check, error handling that will break
  - **Question** — genuinely unclear intent that affects correctness
  - **Trade-off** — reviewer should be aware of this design choice (internal only)

  That's it. No praise, no "checked and looks good", no minor suggestions,
  no style comments, no "consider doing X". If current code works correctly
  and safely — say nothing about it.

  **Verdict** — Score X/10, APPROVED / NEEDS WORK / BLOCKED

  ### Comment format:

  #### #{n} — [{type}] · {file}:{line}
  Score: {normal}/100 | Urgent: {urgent}/100
  📍 `{relative/path/to/File.java}:{line}`

  **Problem:** {one sentence — what is wrong}
  **Fix:** {one sentence — exactly what to change}
  {Optional: 1-2 sentences of context only if the problem isn't obvious}
  **Action:** Post / Internal
  - [ ] Post this comment  ← checked only for Post items

  ### Comment language rules:

  Every comment body — in the draft AND when posted to GitHub — MUST follow
  these rules. Humans read these to understand the issue. AI tools read these
  to apply the fix. Both need clarity.

  1. **Always start with location**: First line is `📍 \`path/to/file:123\`` —
     full relative path and exact line number. This lets anyone (human or AI)
     jump straight to the code without checking GitHub's inline comment context.
     When the comment is copied out of GitHub, the location travels with it.

  2. **Problem in one sentence**: Direct, concrete, no hedging.
     Bad:  "There might be a potential issue with the null handling here."
     Good: "`cancelResult` can be null — `.getStatus()` on line 148 throws NPE."

  3. **Fix in one sentence**: Tell the author exactly what to change.
     Bad:  "Consider adding appropriate validation."
     Good: "Add `if (cancelResult == null) return ErrorResponse.of(...)` before line 148."

  4. **No filler words**: Never start with "I noticed that", "It appears that",
     "It's worth noting", "There seems to be". Start with the fact.

  5. **Use backticks** for all code references: variable names, method names,
     class names, file names. This makes them scannable.

  6. **One comment = one fix**: Don't bundle multiple issues into one comment.
     Each comment should map to exactly one code change.

  ### What gets posted to GitHub (Action: Post):

  **The bar is HIGH.** Only post what the author genuinely needs to act on.
  Every posted comment should make the author think "I'm glad someone caught that."
  If you're unsure — don't post it.

  POST:
  - Bugs, logic errors, incorrect behavior
  - Security issues or data loss risks
  - Critical missing pieces (no migration for schema change, etc.)
  - Questions ONLY if the answer materially affects correctness and you
    genuinely cannot determine it from the code

  NEVER POST:
  - Praise, confirmations, "looks good"
  - Minor suggestions or style improvements
  - Questions you could answer by reading more code
  - "Consider doing X" when current code works fine
  - Anything the author doesn't need to change or respond to

  ### What stays internal (Action: Internal):

  **Only keep if it helps the reviewer decide.** Examples:
  - Trade-off the reviewer should verify (e.g., "chose eventual consistency — confirm this is acceptable")
  - Concern that needs more context the reviewer has but the agent doesn't

  If an internal note doesn't change what the reviewer would do — drop it entirely.
  The goal is a SHORT review, not a thorough one. 5 useful comments beat 20 that
  pad the review.
  "
)
```

### 10. Save & Display Draft

Save the agent's output as the draft file:

```bash
# Save draft (overwritten on re-run)
cat {agent_output} > "$review_dir/review-draft.md"
```

Display a concise summary — only comments that exist, no padding:

```text
Review draft saved to {review_dir}/review-draft.md

Verdict: {APPROVED / NEEDS WORK / BLOCKED}

| # | Type | File | Description | Action |
|---|------|------|-------------|--------|
| 1 | Bug | {File}:{line} | {what's wrong} | Post |
| 2 | Question | {File}:{line} | {what's unclear} | Post |
| 3 | Trade-off | {File}:{line} | {what reviewer should verify} | Internal |

{N} to post, {M} internal. Post all? Or tell me which to adjust.
```

If there are zero comments to post and zero internal notes, just show the verdict.
Do NOT pad the table with "all good" or "no issues" rows.

### 11. User Selects Comments

Wait for user input. Accept these formats:

- `yes` or `post` — post all comments marked "Post"
- `post 1, 3` — post specific comment numbers
- `skip 2` — remove specific comments from the post list
- `skip` or `none` — don't post anything

Parse the draft to extract selected comments. Each comment body keeps the `📍` location line and the Problem/Fix structure — no severity tags or score badges. The location + structured body is what gets posted to GitHub.

### 12. Post Comments (Batch)

Post inline comments as a **single batch review** for cleaner GitHub notifications.

```bash
# Get head commit SHA
gh pr view {pr_number} --json headRefOid -q '.headRefOid'

# Get org/repo
gh repo view --json owner,name -q '"\(.owner.login)/\(.name)"'
```

**Build and post batch review:**

Write review JSON to a temp file, then post:

```bash
# POST batch review with all inline comments
gh api repos/{owner}/{repo}/pulls/{pr_number}/reviews \
  --method POST \
  --input /tmp/pr-{pr_number}-review-$$.json
```

Review JSON structure:
```json
{
  "body": "Code review — {N} comments",
  "event": "COMMENT",
  "commit_id": "{head_sha}",
  "comments": [
    {
      "path": "src/main/java/com/example/Service.java",
      "line": 145,
      "side": "RIGHT",
      "body": "📍 `src/main/java/com/example/Service.java:145`\n\n**Problem:** `cancelResult` can be null — `.getStatus()` on line 148 throws NPE.\n**Fix:** Add `if (cancelResult == null) return ErrorResponse.of(...)` before line 148."
    }
  ]
}
```

**Comment body format**: Each posted comment body MUST start with the `📍` location line followed by the Problem/Fix structure. This ensures that when someone copies the comment text (to paste into an AI tool or share in Slack), the file path and line number travel with it — no need to manually specify "this comment is about file X line Y".

**Fallback**: If batch review fails, post comments individually:

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  -f body="{comment_body}" \
  -f commit_id="{head_sha}" \
  -f path="{file_path}" \
  -F line={line_number} \
  -f side="RIGHT"
```

Clean up temp files after posting. Report: `Posted {count}/{total} comments on PR #{pr_number}`

**IMPORTANT**: NEVER post comments without showing drafts and getting user approval first.

## Multi-PR Workflow

When reviewing multiple PRs:

1. **Parallel execution**: Launch review agents for all PRs simultaneously
2. **Per-PR drafts**: Each PR gets its own draft file in its review folder
3. **Show each draft** as it completes
4. After all complete, produce a **consolidated summary**:

```markdown
## Consolidated Review Summary

| # | Type | PR | File | Description | Action |
|---|------|----|------|-------------|--------|
| 1 | Bug | #{N} | {File}:{line} | {description} | Post |
| 2 | Question | #{N} | {File}:{line} | {description} | Post |
| 3 | Trade-off | #{N} | {File}:{line} | {what to verify} | Internal |

### Cross-PR Dependencies
[Note issues that span PRs — e.g., enum added in #219 resolves missing enum in #220]
[Suggest merge order if PRs depend on each other]
```

5. Show consolidated summary with post counts per PR:
   `PR #219: 2 to post, 1 internal. PR #220: 1 to post, 3 internal. Post all?`

## What This Skill Does NOT Do

- Does NOT create or modify any **tracked** files; the only writes are to git-ignored AI-framework paths (`.claude/skill.config` schema bump, the git-ignored `reviews_root` / `.claude/reviews/` fallback). Those paths are git-ignored at install time — if they were not, those writes would dirty the repo.
- Does NOT save review logs (that's `aa-task-flow-review`'s job for iteration tracking)
- Does NOT require a task folder or task-flow context
- Does NOT block on missing ticket — just notes it
- Does NOT auto-post comments — always shows drafts and asks first
- Does NOT checkout or modify branches

## Tips

- For related PRs (feature split across branches), review them together to catch cross-PR issues
- The agent reads actual source files for exact line numbers — not just diff offsets
- Ticket detection is silent — if your branch follows `feature/{namespace}-XXX-...` naming, it just works
- Posted comments include `📍 file:line` + Problem/Fix structure — copy-paste a comment into any AI tool and it knows exactly where and what to fix
- The self-review step catches hallucinations before they reach the draft
- For urgent merges, Urgent score helps focus on what truly matters
- If you want iteration tracking and review logs, use `aa-task-flow-review` instead
