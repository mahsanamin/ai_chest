# Commit Message Template

## Format

```
{Short summary - what changed and why, max 72 chars}

{Optional 1-2 sentences of tech context if it adds value.}

Co-Authored-By: Claude <noreply@anthropic.com>
```

## Guidelines

- First line: readable by anyone (product, QA, engineer)
- Body: brief tech context — what components/files changed, only if helpful
- Keep it under 3 lines total (excluding Co-Authored-By trailer)
- ALWAYS include `Co-Authored-By: Claude <noreply@anthropic.com>` as the last line
- No checklists, no bullet lists of files
- No conventional commit prefixes (feat:, fix:) unless the repo uses them
- No ticket numbers unless explicitly asked

## Example

```
Fix payment failure when user switches currency mid-checkout

Updated currency conversion to lock rate at cart creation.
Affects PaymentService and CurrencyProxy.

Co-Authored-By: Claude <noreply@anthropic.com>
```
