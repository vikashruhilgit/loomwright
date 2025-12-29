# Next.js Data Fetching & Revalidation Skill

Fetch data with caching, revalidation, and rendering strategies (SSR, SSG, ISR).

## Quick Pattern

```typescript
// Server-Side Rendering (SSR) - Fresh data on every request
export default async function Page() {
  const data = await fetch('https://api.example.com/data', {
    cache: 'no-store'  // Don't cache - fresh on every request
  }).then(r => r.json())

  return <div>{data.name}</div>
}

// Static Site Generation (SSG) - Cache forever
export default async function StaticPage() {
  const data = await fetch('https://api.example.com/data', {
    cache: 'force-cache'  // Cache forever (default)
  }).then(r => r.json())

  return <div>{data.name}</div>
}

// Incremental Static Regeneration (ISR) - Revalidate periodically
export default async function RevalidatedPage() {
  const data = await fetch('https://api.example.com/data', {
    next: { revalidate: 3600 }  // Revalidate every 1 hour
  }).then(r => r.json())

  return <div>{data.name}</div>
}

// Dynamic rendering - when you need fresh data
export const dynamic = 'force-dynamic'

export default async function DynamicPage() {
  const data = await fetch('https://api.example.com/data').then(r => r.json())
  return <div>{data.name}</div>
}
```

## Patterns

### 1. Fetch with Caching Options

**No cache (SSR - fresh every request):**
```typescript
// app/blog/page.tsx - Latest posts always fresh
export default async function BlogPage() {
  const posts = await fetch('https://api.example.com/posts', {
    cache: 'no-store'  // No caching, fresh on every request
  }).then(r => r.json())

  return (
    <div>
      {posts.map(post => (
        <article key={post.id}>
          <h2>{post.title}</h2>
          <p>{post.excerpt}</p>
        </article>
      ))}
    </div>
  )
}
```

**Force cache (SSG - cache forever):**
```typescript
// app/pricing/page.tsx - Pricing rarely changes
export default async function PricingPage() {
  const plans = await fetch('https://api.example.com/plans', {
    cache: 'force-cache'  // Cache forever (default in Next.js)
  }).then(r => r.json())

  return (
    <div>
      {plans.map(plan => (
        <div key={plan.id}>
          <h3>{plan.name}</h3>
          <p>${plan.price}</p>
        </div>
      ))}
    </div>
  )
}
```

**Time-based revalidation (ISR):**
```typescript
// app/news/page.tsx - Revalidate every 10 minutes
export default async function NewsPage() {
  const articles = await fetch('https://api.example.com/news', {
    next: { revalidate: 600 }  // Revalidate every 600 seconds (10 minutes)
  }).then(r => r.json())

  return (
    <div>
      {articles.map(article => (
        <article key={article.id}>
          <h2>{article.headline}</h2>
          <time>{article.publishedAt}</time>
        </article>
      ))}
    </div>
  )
}
```

**Fetch with timeout:**
```typescript
// With abort controller for timeout
const controller = new AbortController()
const timeoutId = setTimeout(() => controller.abort(), 5000)

try {
  const data = await fetch('https://slow-api.com/data', {
    signal: controller.signal,
    next: { revalidate: 3600 }
  }).then(r => r.json())
} finally {
  clearTimeout(timeoutId)
}
```

### 2. Server-Side Rendering (SSR)

**Characteristics:**
- Fresh data on every request
- `cache: 'no-store'` required
- Slower (must fetch on each request)
- Best for: Real-time data, personalized content, live stats

```typescript
// app/dashboard/page.tsx - Real-time user stats
export default async function DashboardPage() {
  // Fetch fresh stats on every page load
  const stats = await fetch('https://api.example.com/stats', {
    cache: 'no-store'
  }).then(r => r.json())

  const events = await fetch('https://api.example.com/events', {
    cache: 'no-store'
  }).then(r => r.json())

  return (
    <div>
      <h1>Dashboard</h1>
      <div>Users online: {stats.activeUsers}</div>
      <div>Recent events: {events.length}</div>
    </div>
  )
}

// With dynamic helper
export const dynamic = 'force-dynamic'  // Alternative syntax

export default async function Page() {
  const data = await fetch('https://api.example.com/data').then(r => r.json())
  return <div>{data.value}</div>
}
```

### 3. Static Site Generation (SSG)

**Characteristics:**
- Generated once at build time
- `cache: 'force-cache'` (default)
- Instant on every request (static HTML)
- Best for: Blog posts, documentation, landing pages

```typescript
// app/blog/[slug]/page.tsx - Static blog posts
export async function generateStaticParams() {
  // Pre-generate pages for these slugs at build time
  const posts = await fetch('https://api.example.com/posts').then(r => r.json())
  return posts.map(post => ({ slug: post.slug }))
}

export default async function BlogPostPage({
  params: { slug }
}: {
  params: Promise<{ slug: string }>
}) {
  const { slug: postSlug } = await params

  const post = await fetch(
    `https://api.example.com/posts/${postSlug}`,
    { cache: 'force-cache' }
  ).then(r => r.json())

  return (
    <article>
      <h1>{post.title}</h1>
      <time>{post.publishedAt}</time>
      <div dangerouslySetInnerHTML={{ __html: post.html }} />
    </article>
  )
}

// Return 404 for unknown slug
export async function generateMetadata({
  params: { slug }
}: {
  params: Promise<{ slug: string }>
}) {
  const { slug: postSlug } = await params
  const post = await fetch(
    `https://api.example.com/posts/${postSlug}`
  ).then(r => r.json())

  if (!post) {
    return { robots: 'noindex' }  // Hide from search
  }

  return {
    title: post.title,
    description: post.excerpt
  }
}
```

### 4. Incremental Static Regeneration (ISR)

**Characteristics:**
- Built at build time, revalidated periodically
- `next: { revalidate: seconds }` required
- Fresh enough for most use cases
- Best for: Product catalogs, news, frequently-updated content

```typescript
// app/products/page.tsx - Revalidate every 1 hour
export default async function ProductsPage() {
  const products = await fetch(
    'https://api.example.com/products',
    { next: { revalidate: 3600 } }  // 1 hour
  ).then(r => r.json())

  return (
    <div>
      {products.map(product => (
        <div key={product.id}>
          <h2>{product.name}</h2>
          <p>${product.price}</p>
        </div>
      ))}
    </div>
  )
}

// Dynamic product pages with ISR
export async function generateStaticParams() {
  const products = await fetch('https://api.example.com/products').then(r => r.json())
  return products.map(product => ({ id: product.id }))
}

export default async function ProductPage({
  params: { id }
}: {
  params: Promise<{ id: string }>
}) {
  const { id: productId } = await params

  const product = await fetch(
    `https://api.example.com/products/${productId}`,
    { next: { revalidate: 3600 } }  // Revalidate hourly
  ).then(r => r.json())

  return (
    <div>
      <h1>{product.name}</h1>
      <p>{product.description}</p>
      <p>${product.price}</p>
    </div>
  )
}
```

### 5. On-Demand Revalidation

**Pattern:** Manually trigger revalidation when data changes

```typescript
// app/api/revalidate/route.ts - Webhook endpoint
import { revalidatePath, revalidateTag } from 'next/cache'
import { NextRequest, NextResponse } from 'next/server'

export async function POST(request: NextRequest) {
  const secret = request.headers.get('x-revalidation-secret')

  if (secret !== process.env.REVALIDATION_SECRET) {
    return NextResponse.json(
      { error: 'Unauthorized' },
      { status: 401 }
    )
  }

  const { type, slug } = await request.json()

  if (type === 'blog-post') {
    // Revalidate specific path
    revalidatePath(`/blog/${slug}`)
    revalidatePath('/blog')  // Also revalidate blog listing
  } else if (type === 'product') {
    // Revalidate by tag
    revalidateTag('products')
  }

  return NextResponse.json({ revalidated: true })
}

// Usage: POST /api/revalidate with webhook from CMS
// When blog post is published, CMS calls this endpoint
```

### 6. Tag-Based Revalidation

**Pattern:** Group related data with tags, revalidate together

```typescript
// Fetch with tags
export default async function BlogPage() {
  const posts = await fetch('https://api.example.com/posts', {
    next: { tags: ['posts'] }  // Tag this fetch
  }).then(r => r.json())

  return <div>{posts.map(p => <div key={p.id}>{p.title}</div>)}</div>
}

// Revalidate all 'posts' tagged fetches at once
export async function revalidateAllPosts() {
  revalidateTag('posts')
}

// API endpoint to trigger revalidation
export async function POST(request: NextRequest) {
  const { tag } = await request.json()
  revalidateTag(tag)
  return NextResponse.json({ revalidated: true })
}
```

### 7. Database Queries vs. API Fetches

**Direct database access in server components:**
```typescript
import { db } from '@/lib/db'

export default async function UsersPage() {
  // Direct database query - no HTTP request
  const users = await db.users.findAll()

  return (
    <div>
      {users.map(user => (
        <div key={user.id}>{user.name}</div>
      ))}
    </div>
  )
}
```

**API requests from client components:**
```typescript
'use client'
import { useEffect, useState } from 'react'

export function UsersList() {
  const [users, setUsers] = useState([])

  useEffect(() => {
    // Must fetch from client via API endpoint
    fetch('/api/users')
      .then(r => r.json())
      .then(setUsers)
  }, [])

  return (
    <div>
      {users.map(user => (
        <div key={user.id}>{user.name}</div>
      ))}
    </div>
  )
}
```

## When to Use

| Strategy | Use Case | Revalidation | Performance |
|----------|----------|--------------|-------------|
| SSR (`cache: 'no-store'`) | Real-time data, user-specific content, dashboards | Every request | Slowest |
| ISR (`next: { revalidate: 3600 }`) | Blogs, product catalogs, frequently-updated content | Hourly/interval | Fast + fresh |
| SSG (`cache: 'force-cache'`) | Landing pages, docs, never-changing content | Never | Fastest |
| Dynamic (`force-dynamic`) | APIs, always-fresh rendering | Every request | Slowest |
| Tag-based revalidation | CMS-driven content | On-demand via webhook | Variable |

## Anti-Patterns

❌ **Fetching inside loops (N+1 queries)**
```typescript
// ❌ 10 requests for 10 users
export default async function UsersList({ userIds }: { userIds: string[] }) {
  return (
    <div>
      {userIds.map(async id => {
        const user = await fetch(`/api/users/${id}`)  // One request per user!
        return <div key={id}>{user.name}</div>
      })}
    </div>
  )
}
```

✓ **Batch fetch once, then map**
```typescript
// ✓ One request for all users
export default async function UsersList({ userIds }: { userIds: string[] }) {
  const users = await fetch(`/api/users?ids=${userIds.join(',')}`)
    .then(r => r.json())

  return (
    <div>
      {users.map(user => (
        <div key={user.id}>{user.name}</div>
      ))}
    </div>
  )
}
```

❌ **No error handling**
```typescript
// ❌ Site crashes if API is down
export default async function Page() {
  const data = await fetch('https://api.example.com/data').then(r => r.json())
  return <div>{data.name}</div>
}
```

✓ **Handle fetch failures gracefully**
```typescript
// ✓ Fallback to cached/default data
export default async function Page() {
  try {
    const data = await fetch('https://api.example.com/data', {
      next: { revalidate: 3600 }
    }).then(r => {
      if (!r.ok) throw new Error('API error')
      return r.json()
    })
    return <div>{data.name}</div>
  } catch (error) {
    return <div>Failed to load data</div>
  }
}
```

❌ **Caching user-specific data globally**
```typescript
// ❌ User A sees User B's data!
export default async function ProfilePage() {
  const user = await fetch('https://api.example.com/user', {
    cache: 'force-cache'  // Wrong - caches for all users
  }).then(r => r.json())

  return <div>{user.email}</div>
}
```

✓ **Don't cache user-specific data**
```typescript
// ✓ Fetch fresh for each user
export default async function ProfilePage() {
  const user = await fetch('https://api.example.com/user', {
    cache: 'no-store'  // Fresh for each user
  }).then(r => r.json())

  return <div>{user.email}</div>
}
```

## Testing Data Fetching

```typescript
describe('Data fetching', () => {
  it('should fetch and render posts with ISR', async () => {
    const { default: BlogPage } = await import('@/app/blog/page')

    // Mock fetch
    global.fetch = jest.fn(() =>
      Promise.resolve({
        ok: true,
        json: () => Promise.resolve([
          { id: 1, title: 'Post 1', excerpt: 'Excerpt 1' }
        ])
      })
    )

    const result = await BlogPage()
    expect(global.fetch).toHaveBeenCalledWith(
      'https://api.example.com/posts',
      expect.objectContaining({ next: { revalidate: 3600 } })
    )
  })

  it('should handle fetch errors', async () => {
    global.fetch = jest.fn(() =>
      Promise.reject(new Error('API unavailable'))
    )

    const { default: Page } = await import('@/app/page')
    const result = await Page()
    // Should render fallback UI
  })

  it('should use correct cache strategy', async () => {
    const { default: Page } = await import('@/app/dynamic/page')
    expect(Page.dynamic).toBe('force-dynamic')
  })
})
```

## Token Cost

- Invocation: 100 tokens
- Quick pattern: 100-150 tokens
- Detailed patterns (7 sections): 600-800 tokens
- Caching strategies guide: 200-300 tokens
- SSR/SSG/ISR comparison: 200-250 tokens
- Revalidation patterns: 200-300 tokens
- Anti-patterns: 200-300 tokens
- Testing examples: 150-200 tokens
- **Total:** 1350-2150 tokens per invocation

## When to Lookup Context7

- Advanced ISR fallback strategies
- Next.js cache behavior with middleware
- Performance optimization for large datasets
- Edge function data fetching patterns
- Streaming responses from fetch
- Advanced revalidation scheduling
- Handling concurrent fetch requests
