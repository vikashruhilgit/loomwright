---
name: nextjs-components
version: "1.0.0"
lastUpdated: "2026-03"
description: Implement Server and Client components with proper boundaries, Suspense, and state management. Use when building React components with Next.js App Router.
---

# Next.js App Router Components Skill

Implement Server and Client components with proper boundaries, Suspense, and state management.

## Quick Pattern

```typescript
// Server Component (default, async allowed)
export default async function UserProfile({ userId }: { userId: string }) {
  const user = await db.users.findById(userId)
  return <div>{user.name}</div>
}

// Client Component (interactive, hooks)
'use client'
import { useState } from 'react'

export function Counter() {
  const [count, setCount] = useState(0)
  return <button onClick={() => setCount(count + 1)}>{count}</button>
}
```

## When to Use

- Server components (default, async allowed)
- Client components (hooks, interactivity)
- Suspense boundaries
- Error boundaries
- Sharing state between server and client

## Suspense Boundaries

Wrap async server components in Suspense to show fallback UI while loading:

```typescript
import { Suspense } from 'react'

export default function Dashboard() {
  return (
    <div>
      <h1>Dashboard</h1>
      <Suspense fallback={<UserSkeleton />}>
        <UserProfile userId="123" />
      </Suspense>
      <Suspense fallback={<StatsSkeleton />}>
        <StatsPanel />
      </Suspense>
    </div>
  )
}

// Each component streams independently
async function UserProfile({ userId }: { userId: string }) {
  const user = await db.users.findById(userId) // slow query
  return <div>{user.name}</div>
}
```

## Error Boundaries

Use `error.tsx` for route-level errors and React error boundaries for component-level:

```typescript
// app/dashboard/error.tsx — route-level error boundary
'use client'

export default function DashboardError({
  error,
  reset,
}: {
  error: Error & { digest?: string }
  reset: () => void
}) {
  return (
    <div role="alert">
      <h2>Something went wrong</h2>
      <p>{error.message}</p>
      <button onClick={() => reset()}>Try again</button>
    </div>
  )
}
```

## Streaming SSR

Use `loading.tsx` for instant loading states that leverage streaming:

```typescript
// app/products/loading.tsx — shows immediately while page streams
export default function Loading() {
  return <ProductGridSkeleton count={12} />
}

// app/products/page.tsx — streams in when ready
export default async function ProductsPage() {
  const products = await fetchProducts() // streams after loading.tsx
  return <ProductGrid products={products} />
}
```

## Server Actions

Define server-side mutations callable from client components:

```typescript
// app/actions/user.ts
'use server'

import { revalidatePath } from 'next/cache'

export async function updateProfile(formData: FormData) {
  const name = formData.get('name') as string
  await db.users.update({ name })
  revalidatePath('/profile')
}

// app/profile/edit.tsx (Client Component using Server Action)
'use client'

import { updateProfile } from '@/app/actions/user'
import { useActionState } from 'react'

export function ProfileForm() {
  const [state, action, pending] = useActionState(updateProfile, null)
  return (
    <form action={action}>
      <input name="name" required />
      <button disabled={pending}>
        {pending ? 'Saving...' : 'Save'}
      </button>
    </form>
  )
}
```

## Composition Patterns (Server + Client)

Pass server component output as children to client components:

```typescript
// ServerWrapper.tsx — Server Component (default)
export default async function ServerWrapper() {
  const data = await fetchData()
  return (
    <ClientTabs defaultTab="overview">
      {/* Server components as children of client component */}
      <OverviewPanel data={data} />
      <Suspense fallback={<Spinner />}>
        <DetailsPanel id={data.id} />
      </Suspense>
    </ClientTabs>
  )
}

// ClientTabs.tsx — Client Component
'use client'
import { useState, ReactNode } from 'react'

export function ClientTabs({ children, defaultTab }: {
  children: ReactNode
  defaultTab: string
}) {
  const [tab, setTab] = useState(defaultTab)
  return (
    <div>
      <nav>
        <button onClick={() => setTab('overview')}>Overview</button>
        <button onClick={() => setTab('details')}>Details</button>
      </nav>
      <div>{children}</div>
    </div>
  )
}
```

## Token Cost

- Pattern: 100-150 tokens
- Context7 (if needed): 1000-1500 tokens
