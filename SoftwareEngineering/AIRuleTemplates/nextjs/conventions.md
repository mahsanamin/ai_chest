---
alwaysApply: true
---
# Next.js Conventions

Additions and overrides for Next.js projects. Use alongside `react-typescript/` rules — everything there applies here unless overridden below.

## Project Structure

```
src/
├── app/                    # App Router (layouts, pages, loading, error)
│   ├── layout.tsx          # Root layout (providers, fonts, metadata)
│   ├── page.tsx            # Home page
│   ├── (auth)/             # Route group (shared layout, no URL segment)
│   │   ├── login/page.tsx
│   │   └── register/page.tsx
│   ├── dashboard/
│   │   ├── layout.tsx      # Dashboard layout
│   │   ├── page.tsx        # Dashboard home
│   │   └── [id]/page.tsx   # Dynamic route
│   └── api/                # Route Handlers (API routes)
│       └── items/route.ts
├── components/             # Shared components
├── lib/                    # Utilities, API clients, auth helpers
├── hooks/                  # Custom hooks
├── stores/                 # Zustand stores (client state)
├── schemas/                # Zod schemas
└── middleware.ts           # Edge middleware (auth, redirects, i18n)
```

## Server vs Client Components

**Default is Server Component.** Only add `'use client'` when needed.

| Need | Component Type |
|------|---------------|
| Data fetching, DB access, secrets | Server |
| Static content, no interactivity | Server |
| `useState`, `useEffect`, `useRef` | Client |
| Event handlers (`onClick`, `onChange`) | Client |
| Browser APIs (`localStorage`, `window`) | Client |
| Zustand stores, React Query | Client |

**Pattern: Server wrapper + Client island**
```tsx
// app/dashboard/page.tsx (Server)
import { getItems } from '@/lib/data'
import { ItemList } from '@/components/ItemList'

export default async function DashboardPage() {
  const items = await getItems()
  return <ItemList initialItems={items} />
}
```

```tsx
// components/ItemList.tsx (Client)
'use client'
export const ItemList = ({ initialItems }: { initialItems: Item[] }) => {
  const [items, setItems] = useState(initialItems)
  // interactive logic...
}
```

## Data Fetching

### Server Components (preferred)
```tsx
// Direct async/await in Server Components
export default async function ItemsPage() {
  const items = await db.items.findMany()
  return <ItemGrid items={items} />
}
```

### Route Handlers (API routes)
```ts
// app/api/items/route.ts
import { NextResponse } from 'next/server'

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url)
  const items = await db.items.findMany({ where: { status: searchParams.get('status') } })
  return NextResponse.json(items)
}

export async function POST(request: Request) {
  const body = await request.json()
  // validate with Zod...
  const item = await db.items.create({ data: body })
  return NextResponse.json(item, { status: 201 })
}
```

### Client Components (React Query)
Use React Query for client-side data that needs caching, polling, or optimistic updates — same patterns as `react-typescript/state-management.md`.

## Metadata

```tsx
// Static metadata
export const metadata: Metadata = {
  title: 'Dashboard',
  description: 'Manage your items',
}

// Dynamic metadata
export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const item = await getItem(params.id)
  return { title: item.name }
}
```

## Loading & Error States

```
app/dashboard/
├── page.tsx        # Page content
├── loading.tsx     # Suspense fallback (automatic)
├── error.tsx       # Error boundary (must be 'use client')
└── not-found.tsx   # 404 page
```

## Middleware

```ts
// middleware.ts
import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'

export function middleware(request: NextRequest) {
  // Auth check, locale redirect, etc.
  const token = request.cookies.get('token')
  if (!token && request.nextUrl.pathname.startsWith('/dashboard')) {
    return NextResponse.redirect(new URL('/login', request.url))
  }
}

export const config = {
  matcher: ['/dashboard/:path*'],
}
```

## Key Differences from Plain React

| Topic | React SPA | Next.js |
|-------|----------|---------|
| Routing | React Router | App Router (file-based) |
| Data fetching | React Query everywhere | Server Components + React Query for client |
| API calls | External API server | Route Handlers (`app/api/`) |
| SSR/SSG | Manual setup | Built-in (`generateStaticParams`, ISR) |
| State on server | N/A | Server Components (no hooks, no state) |
| Environment vars | `VITE_*` | `NEXT_PUBLIC_*` (client) or plain (server) |

## Rules

1. **Default to Server Components** — only use `'use client'` when you need interactivity
2. **Never import server-only code in client components** — use `server-only` package to enforce
3. **Keep client bundles small** — pass data as props from server to client, don't duplicate fetching
4. **Use `loading.tsx` and `error.tsx`** — don't build custom loading/error for every page
5. **Validate at boundaries** — use Zod in Route Handlers and Server Actions
6. **Don't use `useEffect` for data fetching** — use Server Components or React Query
