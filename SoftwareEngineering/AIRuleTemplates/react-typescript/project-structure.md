---
description: React SPA project structure conventions
alwaysApply: true
globs: ["**/*.ts", "**/*.tsx"]
---

# React SPA Project Structure

## Core Directories

```
src/
  components/       # Shared UI components (Button, Modal, Layout)
  hooks/            # Custom React hooks (useAuth, useDebounce)
  lib/
    api/            # API client, endpoint functions, query keys
  routes/           # Page-level components, one file per route
  schemas/          # Zod validation schemas
  stores/           # Zustand stores
  contexts/         # React Context providers
  i18n/             # Translations and i18n configuration
  mocks/
    handlers/       # MSW request handlers grouped by resource
    server.ts       # MSW server setup
  test/
    utils.tsx        # renderWithProviders and test helpers
```

## API Layer

All API calls live in `lib/api/`. Each resource gets its own file plus shared query keys:

```
lib/api/
  client.ts         # Configured fetch/axios instance
  items.ts          # fetchItems, createItem, updateItem, deleteItem
  users.ts          # fetchUser, updateUser
  queryKeys.ts      # Query key factories for React Query
```

## State Management

- **Server state** -> React Query (in hooks or `lib/api/`)
- **Client/UI state** -> Zustand (in `stores/`)
- **Form state** -> React Hook Form (in route/component)
- **Global config** -> React Context (in `contexts/`)

## Schemas

Group Zod schemas by domain. Derive TypeScript types from schemas:

```
schemas/
  itemSchema.ts     # itemSchema, itemFormSchema, ItemType
  userSchema.ts     # userSchema, UserType
```

## Components

Shared components go in `components/`. Route-specific components stay co-located with their route file or in a subfolder.

## Routes

One file per route in `routes/`. Use the router's file-based or config-based routing convention. Keep route components thin -- delegate logic to hooks and API functions.
