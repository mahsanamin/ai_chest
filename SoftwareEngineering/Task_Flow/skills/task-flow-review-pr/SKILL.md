---
name: task-flow-review-pr
description: Review pull requests against project coding rules. Accepts PR numbers/URLs. Say "task-flow-review-pr" or "review pr".
disable-model-invocation: true
---

# Review PR

Standalone code review skill. Reviews any PR against project coding rules. Generates a lean draft with only real problems — user controls which comments get posted.

## When to Use

- Review a teammate's PR before approving
- Review your own PR before requesting review
- Review multiple related PRs together
- Quick review by number: `task-flow-review-pr 216`

## How to Use

```
> task-flow-review-pr 216
> task-flow-review-pr https://github.com/{org}/{repo}/pull/216
> task-flow-review-pr 219 220 221
> task-flow-review-pr                    # Will ask for PR number
```

## Working Directory

Review files saved to `reviews_root`, resolved:
1. `reviews_root` from `.claude/skill.config` (explicit)
2. Derived from `tasks_root` → sibling `CodeReviews/`
3. Fallback: `.claude/reviews`

```
{reviews_root}/
├── PR-220-cancellation-processor/
│   ├── review.diff
│   └── review-draft.md
└── PR-219-batch-cancel-api/
    ├── review.diff
    └── review-draft.md
```

## Implementation

**Only 2 interaction points:**
1. **Step 1** — Ask which PR (only if not provided)
2. **Step 10** — Present draft and ask which comments to post

Everything else runs without prompting.

### 1. Resolve Pull Request(s)

Parse input: numbers → use directly, URLs → extract number, no input → ask user.

### 2. Resolve Working Directory

```bash
reviews_root=$(jq -r '.paths.reviews_root // ""' .claude/skill.config 2>/dev/null)
if [ -z "$reviews_root" ]; then
  tasks_root=$(jq -r '.paths.tasks_root // ""' .claude/skill.config 2>/dev/null)
  if [ -n "$tasks_root" ]; then
    reviews_root="$(dirname "$tasks_root")/CodeReviews"
    mkdir -p "$reviews_root"
  else
    reviews_root=".claude/reviews"
  fi
fi
```

### 3. Fetch PR Details

```bash
gh pr view {pr_number} --json number,title,body,author,baseRefName,headRefName,url,additions,deletions,changedFiles
```

### 4. Detect Ticket

Silently extract from branch name or PR title using namespace from config_hints.json. Don't prompt.

### 5. Create Review Folder & Diff

```bash
review_dir="{reviews_root}/PR-{pr_number}-{sanitized_title}"
mkdir -p "$review_dir"
gh pr diff {pr_number} > "$review_dir/review.diff"
```

### 6. Fetch Existing PR Comments

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments --paginate
gh api repos/{owner}/{repo}/issues/{pr_number}/comments --paginate
```

Pass to agent as context. Truncate to 30 most recent if >50KB.

### 7. Large Diff Triage

| Additions | Strategy |
|-----------|----------|
| < 400 lines | Full review |
| 400-800 lines | Prioritized — deep on logic, skim tests/config |
| > 800 lines | Tiered — classify files first |

### 8. Load Coding Rules (Selective)

```bash
standards_dir=$(jq -r '.standards_location // "docs/ai-rules"' .claude/config_hints.json 2>/dev/null)
```

**Always load:** `code-review.md`, `critical-thinking.md`, `coding-conventions.md`

**Load based on diff signals:** Grep the diff for framework-specific patterns (e.g., `@Transactional` → `transaction-boundaries.md`, `@RestController` → `api-conventions.md`). Also scan remaining rule files by filename stem.

### 9. Run Code Review

Launch code reviewer agent with:
- PR context (number, title, author, branch, stats)
- PR description
- Relevant coding rules (pre-selected)
- Diff file path
- Existing PR comments

**Agent review process:**
1. Business flow analysis — understand operations, failure modes
2. File-by-file review against coding rules
3. Self-review — re-verify every comment against actual code, drop hallucinations
4. Draft output — only problems and decision-relevant notes

**Comment types:** Bug/Error, Security, Missing, Question, Trade-off

**Scoring:** Score 0-100 (normal), Urgent 0-100 (for urgent merges)

### 10. Present Draft

```
Review draft saved to {review_dir}/review-draft.md

Verdict: {APPROVED / NEEDS WORK / BLOCKED}

| # | Type | File | Description | Action |
|---|------|------|-------------|--------|
| 1 | Bug | File:line | what's wrong | Post |
| 2 | Trade-off | File:line | what to verify | Internal |

{N} to post, {M} internal. Post all? Or tell me which to adjust.
```

### 11. User Selects Comments

Accept: `yes` / `post 1,3` / `skip 2` / `skip` / `none`

### 12. Post Comments (Batch)

Post as a single batch review for clean notifications:

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/reviews \
  --method POST --input /tmp/pr-review.json
```

Fallback to individual comments if batch fails. Clean up temp files.

**NEVER post without user approval.**

## Multi-PR Workflow

1. Launch review agents in parallel (one per PR)
2. Each PR gets its own draft
3. Consolidated summary with cross-PR dependencies
4. User selects per-PR which comments to post

## What This Skill Does NOT Do

- Does NOT modify repo files
- Does NOT require a task folder or task-flow context
- Does NOT auto-post — always asks first
- Does NOT checkout or modify branches
