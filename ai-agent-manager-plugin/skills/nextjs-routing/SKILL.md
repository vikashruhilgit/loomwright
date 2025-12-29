---
name: nextjs-routing
description: Implement routes using Next.js 14+ App Router with file-based routing. Use when creating pages, layouts, dynamic routes, or implementing Next.js routing patterns.
---

# Next.js App Router Routing Skill

Implement routes using Next.js 14+ App Router with file-based routing.

## Quick Pattern

```typescript
// app/page.tsx - Home page
export default function Home() {
  return <h1>Welcome</h1>
}

// app/blog/[slug]/page.tsx - Dynamic route
interface Props {
  params: Promise<{ slug: string }>
}

export default async function BlogPost({ params }: Props) {
  const { slug } = await params
  return <article>Post: {slug}</article>
}
```

## When to Use

- Basic file routing
- Dynamic routes with parameters
- Layouts for shared structure
- Route groups (parentheses)
- Catch-all routes

## Token Cost

- Pattern: 150-200 tokens
- Context7 (if needed): 1000-1500 tokens
