---
name: nextjs-components
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

## Token Cost

- Pattern: 100-150 tokens
- Context7 (if needed): 1000-1500 tokens
