---
description: React state management conventions
globs: ["**/*.ts", "**/*.tsx"]
---

# React State Management

## State Categories

| Category         | Tool            | When to Use                                    |
|------------------|-----------------|------------------------------------------------|
| Server state     | React Query     | API data, caching, background refresh          |
| Client/UI state  | Zustand         | UI toggles, selections, local app state        |
| Form state       | React Hook Form | Form inputs, validation, submission            |
| Global config    | React Context   | Theme, locale, auth token -- rarely changes    |

**Rule:** Never store server data in Zustand. Let React Query own all server state.

## React Query

### Defaults

```typescript
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 5 * 60 * 1000,     // 5 minutes
      gcTime: 10 * 60 * 1000,        // 10 minutes (formerly cacheTime)
      retry: 1,
      refetchOnWindowFocus: false,
    },
  },
});
```

### Query Pattern

```typescript
import { useQuery } from '@tanstack/react-query';
import { itemKeys } from '@/lib/api/queryKeys';
import { fetchItems } from '@/lib/api/items';

export const useItems = (filters: ItemFilters) => {
  return useQuery({
    queryKey: itemKeys.list(filters),
    queryFn: ({ signal }) => fetchItems(filters, signal),
    enabled: !!filters.userId,
  });
};
```

Always pass `signal` to the query function so React Query can abort in-flight requests on unmount or query key changes.

### Mutation Pattern

```typescript
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { createItem } from '@/lib/api/items';
import { itemKeys } from '@/lib/api/queryKeys';

export const useCreateItem = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: createItem,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: itemKeys.all });
    },
    onError: (error) => {
      console.error('Failed to create item:', error);
    },
  });
};
```

### Query Key Conventions

Organize keys as factory functions for consistency and easy invalidation:

```typescript
export const itemKeys = {
  all: ['items'] as const,
  lists: () => [...itemKeys.all, 'list'] as const,
  list: (filters: ItemFilters) => [...itemKeys.lists(), filters] as const,
  details: () => [...itemKeys.all, 'detail'] as const,
  detail: (id: string) => [...itemKeys.details(), id] as const,
};

export const userKeys = {
  all: ['users'] as const,
  detail: (id: string) => [...userKeys.all, id] as const,
  me: () => [...userKeys.all, 'me'] as const,
};
```

- Invalidate broadly: `queryClient.invalidateQueries({ queryKey: itemKeys.all })`.
- Invalidate narrowly: `queryClient.invalidateQueries({ queryKey: itemKeys.detail(id) })`.

## Zustand

### Store Pattern

Separate initial state from actions so stores can be reset in tests.

```typescript
import { create } from 'zustand';

interface SidebarState {
  isOpen: boolean;
  activePanel: string | null;
}

interface SidebarActions {
  toggle: () => void;
  setActivePanel: (panel: string | null) => void;
  reset: () => void;
}

type SidebarStore = SidebarState & SidebarActions;

const initialState: SidebarState = {
  isOpen: false,
  activePanel: null,
};

export const useSidebarStore = create<SidebarStore>()((set) => ({
  ...initialState,
  toggle: () => set((state) => ({ isOpen: !state.isOpen })),
  setActivePanel: (panel) => set({ activePanel: panel }),
  reset: () => set(initialState),
}));
```

### Component Usage

Always use **selectors** to avoid unnecessary re-renders:

```typescript
// GOOD - only re-renders when isOpen changes
const isOpen = useSidebarStore((state) => state.isOpen);
const toggle = useSidebarStore((state) => state.toggle);

// BAD - re-renders on every store change
const { isOpen, toggle } = useSidebarStore();
```

### Testing Zustand Stores

Reset store state in `beforeEach` to prevent test leakage:

```typescript
import { useSidebarStore } from '@/stores/sidebarStore';

beforeEach(() => {
  useSidebarStore.getState().reset();
});

it('should toggle sidebar', () => {
  const store = useSidebarStore.getState();
  expect(store.isOpen).toBe(false);

  store.toggle();
  expect(useSidebarStore.getState().isOpen).toBe(true);
});
```

## React Context

### When to Use

- Theme or locale settings that rarely change.
- Authenticated user info that is set once at login.
- Feature flags loaded at app startup.

### When NOT to Use

- **Frequently changing values** (causes re-renders of all consumers).
- **Server state** (use React Query instead).
- **Complex state with actions** (use Zustand instead).
- **Form state** (use React Hook Form instead).

### Pattern

```typescript
interface AuthContextValue {
  user: User | null;
  isAuthenticated: boolean;
}

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

export const AuthProvider = ({ children }: { children: React.ReactNode }) => {
  const { data: user } = useCurrentUser();
  const value = useMemo(
    () => ({ user: user ?? null, isAuthenticated: !!user }),
    [user],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
};

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within AuthProvider');
  }
  return context;
};
```

## State Decision Guide

```
Is the data from an API?
  YES -> React Query
  NO  -> Is it form input data?
    YES -> React Hook Form
    NO  -> Does it change frequently and affect multiple components?
      YES -> Zustand
      NO  -> Is it app-wide config set once?
        YES -> React Context
        NO  -> useState / useReducer (local component state)
```
