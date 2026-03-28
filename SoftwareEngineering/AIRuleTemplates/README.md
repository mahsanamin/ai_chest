# AI Rule Templates

Reusable coding rule templates for AI-assisted development. Stack-agnostic structure — pick the directories that match your project.

## Structure

```
AIRuleTemplates/
├── universal/                  # Apply to any project
│   ├── critical-thinking.md    # Challenge assumptions, question instructions
│   └── code-review.md         # Review criteria and severity levels
│
├── backend/                    # Generic backend best practices (any language)
│   ├── query-efficiency.md     # N+1 prevention, selectivity, DataContext pattern
│   ├── transaction-boundaries.md  # Keep transactions short and DB-focused
│   ├── database-migrations.md  # Versioning, naming, indexes, constraints
│   └── api-conventions.md      # REST API patterns, validation, security
│
├── java-spring-boot/           # Java/Spring Boot specific
│   ├── jpa-repositories.md     # PostgreSQL/H2 compat, soft-delete, lazy loading
│   └── coding-conventions.md   # Formatting, imports, Lombok, Javadoc
│
├── react-typescript/           # React/TypeScript SPA
│   ├── coding-conventions.md   # Biome, strict TS, naming, imports
│   ├── state-management.md     # React Query + Zustand + RHF + Context
│   ├── testing.md              # Vitest, Testing Library, MSW
│   ├── forms.md                # React Hook Form + Zod
│   └── project-structure.md    # Standard directory layout
│
└── nextjs/                     # Next.js additions (use with react-typescript/)
    └── conventions.md          # Server/Client components, App Router, Route Handlers
```

## How to Use

### With Task Flow

During `task-flow-setup:initialize`, point your `standards_location` to a directory in your project, then copy relevant templates:

```bash
# Example: Java backend project
cp AIRuleTemplates/universal/*.md my-project/docs/ai-rules/
cp AIRuleTemplates/backend/*.md my-project/docs/ai-rules/
cp AIRuleTemplates/java-spring-boot/*.md my-project/docs/ai-rules/
```

### Standalone

Copy any template into your project's AI rules directory and customize:

1. Replace generic examples with your domain (Order → Invoice, User → Tenant, etc.)
2. Adjust patterns to match your project's conventions
3. Remove sections that don't apply
4. Add project-specific rules

### With Other AI Tools

These templates work with any AI coding assistant that reads markdown rules:
- **Claude Code**: Place in directory referenced by `standards_location` in `config_hints.json`
- **Cursor**: Place in `.cursor/rules/` directory
- **GitHub Copilot**: Place in `.github/copilot-instructions.md` or reference from it
- **Windsurf**: Place in `.windsurfrules`

## Customization Guide

| If your project uses... | Start with... |
|------------------------|---------------|
| Java + Spring Boot + PostgreSQL | `universal/` + `backend/` + `java-spring-boot/` |
| React + TypeScript SPA | `universal/` + `react-typescript/` |
| Next.js | `universal/` + `react-typescript/` + `nextjs/` |
| Python + Django | `universal/` + `backend/` (adapt examples to Django ORM) |
| Go + gin/echo | `universal/` + `backend/` (adapt examples to Go patterns) |
| Node.js + Express | `universal/` + `backend/` (adapt to Prisma/TypeORM) |

## Design Principles

- **Generic over specific** — templates use common patterns, you add project specifics
- **Concise over verbose** — only rules that prevent real mistakes, not style preferences AI already knows
- **Examples over prose** — show the right pattern, don't explain why 5 ways
- **One source of truth** — each concept lives in one file, cross-referenced by others
