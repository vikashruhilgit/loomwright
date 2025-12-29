---
name: nextjs-data-fetching
description: Fetch data with caching, revalidation, and rendering strategies (SSR, SSG, ISR). Use when implementing data fetching patterns in Next.js.
---

# Next.js Data Fetching & Revalidation Skill

Fetch data with caching, revalidation, and rendering strategies (SSR, SSG, ISR).

## Quick Pattern

```typescript
// SSR - Fresh data on every request
export default async function Page() {
  const data = await fetch('https://api.example.com/data', {
    cache: 'no-store'
  }).then(r => r.json())
  return <div>{data.name}</div>
}

// ISR - Revalidate periodically
export default async function Page() {
  const data = await fetch('https://api.example.com/data', {
    next: { revalidate: 3600 }
  }).then(r => r.json())
  return <div>{data.name}</div>
}
```

## When to Use

- Server-Side Rendering (SSR)
- Static Site Generation (SSG)
- Incremental Static Regeneration (ISR)
- On-demand revalidation
- Tag-based revalidation

## Token Cost

- Pattern: 100-150 tokens
- Context7 (if needed): 1000-1500 tokens
