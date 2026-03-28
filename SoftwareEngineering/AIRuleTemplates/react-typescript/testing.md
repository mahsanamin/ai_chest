---
description: React testing conventions
globs: ["**/*.test.ts", "**/*.test.tsx", "**/*.spec.ts", "**/*.spec.tsx"]
---

# React Testing Conventions

## Stack

| Tool              | Purpose                             |
|-------------------|-------------------------------------|
| Vitest            | Test runner and assertions          |
| happy-dom         | Lightweight DOM environment         |
| Testing Library   | Component rendering and queries     |
| MSW               | API mocking (network-level)         |
| Playwright        | End-to-end browser tests            |

## Test Types

| Type        | Location                    | Scope                                  | Runner     |
|-------------|-----------------------------|----------------------------------------|------------|
| Unit        | `*.test.ts`                 | Functions, hooks, schemas, stores      | Vitest     |
| Component   | `*.test.tsx`                | Single component rendering + behavior  | Vitest     |
| Integration | `*.test.tsx`                | Multiple components + API interactions | Vitest+MSW |
| E2E         | `e2e/*.spec.ts`             | Full user flows in real browser        | Playwright |

## Test Structure

Follow the Arrange-Act-Assert pattern:

```typescript
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';
import { UserCard } from './UserCard';

describe('UserCard', () => {
  it('should display user name when rendered', () => {
    // Arrange
    render(<UserCard name="Jane Doe" email="jane@example.com" onEdit={vi.fn()} />);

    // Act (none needed for render test)

    // Assert
    expect(screen.getByText('Jane Doe')).toBeInTheDocument();
  });

  it('should call onEdit when edit button is clicked', async () => {
    // Arrange
    const user = userEvent.setup();
    const handleEdit = vi.fn();
    render(<UserCard name="Jane Doe" email="jane@example.com" onEdit={handleEdit} />);

    // Act
    await user.click(screen.getByRole('button', { name: /edit/i }));

    // Assert
    expect(handleEdit).toHaveBeenCalledOnce();
  });
});
```

## Conventions

### Test Naming

Use the pattern: **"should [expected behavior] when [condition]"**

```typescript
it('should show error message when form submission fails');
it('should disable submit button when inputs are invalid');
it('should redirect to dashboard when login succeeds');
```

### Query Priority (Testing Library)

Prefer queries in this order:

1. `getByRole` -- accessible roles (button, heading, textbox)
2. `getByLabelText` -- form elements
3. `getByPlaceholderText` -- input placeholders
4. `getByText` -- visible text content
5. `getByTestId` -- last resort only

```typescript
// GOOD
screen.getByRole('button', { name: /submit/i });
screen.getByLabelText(/email/i);

// AVOID
screen.getByTestId('submit-btn');
```

### Wrapping with Providers

Create a test utility for rendering with providers:

```typescript
// test/utils.tsx
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';

export const renderWithProviders = (
  ui: React.ReactElement,
  { route = '/' } = {},
) => {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false, gcTime: 0 } },
  });

  return render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={[route]}>{ui}</MemoryRouter>
    </QueryClientProvider>,
  );
};
```

### Store Tests

Reset Zustand stores before each test:

```typescript
import { useItemStore } from '@/stores/itemStore';

beforeEach(() => {
  useItemStore.getState().reset();
});
```

### Schema Tests

Test Zod schemas with valid and invalid payloads:

```typescript
import { userSchema } from '@/schemas/userSchema';

describe('userSchema', () => {
  it('should parse valid user data', () => {
    const result = userSchema.safeParse({ name: 'Jane', email: 'jane@example.com' });
    expect(result.success).toBe(true);
  });

  it('should reject invalid email', () => {
    const result = userSchema.safeParse({ name: 'Jane', email: 'not-an-email' });
    expect(result.success).toBe(false);
  });
});
```

## MSW (Mock Service Worker)

### Handler Pattern

```typescript
// mocks/handlers/items.ts
import { http, HttpResponse } from 'msw';

export const itemHandlers = [
  http.get('/api/items', () => {
    return HttpResponse.json([
      { id: '1', name: 'Item One', status: 'active' },
      { id: '2', name: 'Item Two', status: 'inactive' },
    ]);
  }),

  http.post('/api/items', async ({ request }) => {
    const body = await request.json();
    return HttpResponse.json({ id: '3', ...body }, { status: 201 });
  }),

  http.delete('/api/items/:id', ({ params }) => {
    return new HttpResponse(null, { status: 204 });
  }),
];
```

### MSW Rules

- Define handlers in `mocks/handlers/` grouped by resource.
- Combine all handlers in `mocks/handlers/index.ts`.
- Setup server in `mocks/server.ts`:

```typescript
import { setupServer } from 'msw/node';
import { handlers } from './handlers';

export const server = setupServer(...handlers);
```

- Wire up in Vitest setup file:

```typescript
// test/setup.ts
import { afterAll, afterEach, beforeAll } from 'vitest';
import { server } from '@/mocks/server';

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
```

### Overriding Handlers in Tests

Override default handlers for error or edge-case scenarios:

```typescript
import { http, HttpResponse } from 'msw';
import { server } from '@/mocks/server';

it('should show error state when API fails', async () => {
  server.use(
    http.get('/api/items', () => {
      return HttpResponse.json({ message: 'Server error' }, { status: 500 });
    }),
  );

  renderWithProviders(<ItemList />);

  expect(await screen.findByText(/something went wrong/i)).toBeInTheDocument();
});
```

## What to Test

### Always Test

- User-visible behavior (render output, interactions, navigation).
- Form validation and submission (happy path + error states).
- Loading and error states.
- Conditional rendering logic.
- Zod schemas with valid and invalid data.
- Zustand store actions and state transitions.

### Skip or Defer

- Implementation details (internal state, private methods).
- Third-party library behavior.
- Styles and CSS (unless visually critical).
- 1:1 snapshot tests (fragile and low-value).

## Browser Tests (Playwright)

Use Playwright for critical user journeys:

```typescript
// e2e/create-order.spec.ts
import { expect, test } from '@playwright/test';

test('user can create a new order', async ({ page }) => {
  await page.goto('/orders/new');

  await page.getByLabel(/product/i).fill('Widget');
  await page.getByLabel(/quantity/i).fill('5');
  await page.getByRole('button', { name: /submit/i }).click();

  await expect(page.getByText(/order created/i)).toBeVisible();
});
```

### Browser Test Guidelines

- Test full user flows, not individual components.
- Use `getByRole` and `getByLabel` for resilient selectors.
- Keep E2E tests focused -- fewer, broader tests beat many narrow ones.
- Run against a real (or realistic) backend, not MSW.
- Store E2E tests in the `e2e/` directory, separate from unit/component tests.
