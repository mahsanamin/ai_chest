---
description: React and TypeScript coding conventions
alwaysApply: true
globs: ["**/*.ts", "**/*.tsx"]
---

# React / TypeScript Coding Conventions

## Formatting (Biome)

- **Line length:** 120 characters max.
- **Indentation:** 2 spaces (no tabs).
- **Quotes:** Single quotes for strings, double quotes for JSX attributes.
- **Trailing commas:** Always (ES5+).
- **Semicolons:** Always.

## TypeScript Strict Mode

Enable all strict checks in `tsconfig.json`:

```json
{
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": false
  }
}
```

- Prefer `unknown` over `any`. Use `any` only as a last resort with a comment explaining why.
- Use `satisfies` for type-safe object literals: `const config = { ... } satisfies Config;`

## Zod vs Plain Types

| Scenario                        | Use                  |
|---------------------------------|----------------------|
| API response parsing            | Zod schema           |
| Form validation                 | Zod schema           |
| Component props                 | TypeScript interface |
| Internal function signatures    | TypeScript types     |
| Environment variables           | Zod schema           |

Derive types from Zod schemas with `z.infer<typeof schema>` -- do not duplicate types manually.

## File Naming

| Category      | Convention             | Example                    |
|---------------|------------------------|----------------------------|
| Components    | PascalCase             | `UserProfile.tsx`          |
| Hooks         | camelCase with `use`   | `useAuth.ts`               |
| Utilities     | camelCase              | `formatDate.ts`            |
| Schemas       | camelCase              | `userSchema.ts`            |
| Tests         | match source + `.test` | `UserProfile.test.tsx`     |
| Stores        | camelCase + `Store`    | `authStore.ts`             |
| Constants     | camelCase              | `apiEndpoints.ts`          |
| Types         | camelCase              | `userTypes.ts`             |

## Naming Conventions

- **Components:** PascalCase (`UserProfile`, `OrderList`).
- **Hooks:** camelCase prefixed with `use` (`useAuth`, `useItems`).
- **Boolean variables:** prefix with `is`, `has`, `should`, `can` (`isLoading`, `hasError`).
- **Event handlers:** prefix with `handle` in components, `on` in props (`handleClick`, `onClick`).
- **Constants:** UPPER_SNAKE_CASE only for true global constants; camelCase for module-level values.

## Import Organization

Use the `@/*` path alias mapped to `src/`. Order imports:

```typescript
// 1. React/framework
import { useState } from 'react';

// 2. Third-party libraries
import { useQuery } from '@tanstack/react-query';
import { z } from 'zod';

// 3. Internal modules (via path alias)
import { apiClient } from '@/lib/api/client';
import { useAuth } from '@/hooks/useAuth';
import { UserProfile } from '@/components/UserProfile';

// 4. Relative imports (co-located files only)
import { formatName } from './utils';
```

## Component Patterns

- Use **arrow function** exports for components.
- **Destructure props** in the function signature.
- One component per file (small helper components co-located are fine).

```typescript
interface UserCardProps {
  name: string;
  email: string;
  onEdit: (id: string) => void;
}

export const UserCard = ({ name, email, onEdit }: UserCardProps) => {
  return (
    <div>
      <h2>{name}</h2>
      <p>{email}</p>
      <button type="button" onClick={() => onEdit(name)}>Edit</button>
    </div>
  );
};
```

## Error Handling

- Wrap async operations in try/catch with specific error handling.
- Use Error Boundaries for component-level failures.
- Always provide user-facing feedback for errors (toast, inline message).
- Never silently swallow errors.

```typescript
try {
  await createOrder(data);
} catch (error) {
  if (error instanceof ApiError && error.status === 409) {
    showToast('Order already exists');
  } else {
    showToast('Something went wrong. Please try again.');
    console.error('Failed to create order:', error);
  }
}
```

## Constants

Extract a value to a constant only when it is used **3 or more times**. Do not prematurely extract single-use values.

## Pre-Commit Checks

Before committing, ensure all of the following pass:

1. `npm run test` -- unit tests pass.
2. `npm run lint` -- no lint errors.
3. `npm run typecheck` -- no TypeScript errors.
