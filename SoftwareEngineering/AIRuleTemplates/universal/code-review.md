---
description: Code review standards and severity criteria for AI-assisted reviews
alwaysApply: false
---

# Code Review Standards

## Review Criteria

Every code review should evaluate the following areas. Reference the relevant rule file for detailed guidance.

### 1. Architecture & Design

- Does the change follow established layering (Controller -> Service -> Repository)?
- Are module boundaries respected?
- Is business logic in the correct layer?
- See `{critical-thinking}.md` for when to push back on design decisions.

### 2. Transaction Boundaries

- Are transactions scoped to database operations only?
- No external calls (HTTP, message queues, file I/O) inside transactions?
- See `{transaction-boundaries}.md` for detailed rules.

### 3. Query Efficiency

- No N+1 query patterns (repository calls inside loops)?
- Are queries selective (using IDs/indexes, not scanning)?
- Is available data reused rather than re-fetched?
- See `{query-efficiency}.md` for detailed rules.

### 4. Database Migrations

- Follows versioning and naming conventions?
- Uses IF NOT EXISTS / IF EXISTS for safety?
- Indexes justified and properly constructed?
- See `{database-migrations}.md` for detailed rules.

### 5. API Conventions

- URL structure follows conventions (versioned, kebab-case)?
- Query parameters validated (especially all-optional scenarios)?
- Request/Response DTOs properly defined?
- See `{api-conventions}.md` for detailed rules.

### 6. Code Quality

- Methods are focused and reasonably sized (< 30 lines preferred)
- Error handling is explicit, not swallowed
- No magic numbers or hardcoded strings
- Tests cover the change adequately

### 7. Module Structure

- Files are in the correct package/directory
- Naming follows existing conventions
- No circular dependencies introduced

### 8. Critical Thinking

- Does the change actually solve the stated problem?
- Are there edge cases not handled?
- Could this break existing functionality?
- See `{critical-thinking}.md` for the full checklist.

---

## Severity Criteria

### MUST Block Merge

These issues must be resolved before the PR can be approved:

- **Data loss risk:** Migration drops column, missing cascade protection, no backup path
- **Security vulnerability:** Missing auth check, SQL injection, secrets in code
- **N+1 query pattern:** Repository call inside a loop without batch alternative
- **Transaction violation:** External API call or long-running operation inside a transaction
- **Breaking API change:** Removed or renamed field in public API without versioning
- **Missing validation:** User input reaches business logic or database unchecked
- **Incorrect business logic:** Code does not match the stated requirement

### Should Review (Non-Blocking)

These should be discussed but do not block merge:

- Naming improvements
- Minor refactoring opportunities
- Missing logging or observability
- Test coverage gaps on non-critical paths
- Documentation updates
- Performance improvements with low risk

### Does Not Block

These are informational or stylistic:

- Formatting preferences already handled by linters
- Alternative approaches that are equally valid
- Future improvement suggestions (note as TODO with ticket)
- Personal style preferences

---

## Review Comment Format

Use clear, actionable comments:

```
[MUST FIX] N+1 query: `findOrderById` is called inside the loop at line 42.
Fetch all orders in one query using `findAllByIdIn(orderIds)`.
See {query-efficiency}.md for the batch pattern.

[SUGGESTION] Consider extracting lines 30-55 into a private method
for readability. Not blocking.

[QUESTION] Is the null check on line 18 intentional? The field is
marked @NotNull in the entity. Might indicate a deeper issue.
```

---

## Review Checklist (Quick Reference)

- [ ] No N+1 queries
- [ ] Transactions contain only DB operations
- [ ] Migrations are safe and reversible
- [ ] API changes are backward-compatible
- [ ] Auth/ownership checks in place
- [ ] Error handling is explicit
- [ ] Tests cover the happy path and key edge cases
- [ ] No hardcoded secrets or credentials
