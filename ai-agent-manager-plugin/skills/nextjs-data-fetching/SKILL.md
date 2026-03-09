---
name: nextjs-data-fetching
version: "1.0.0"
lastUpdated: "2026-03"
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

## ISR Patterns

Generate static pages at build time and regenerate on a schedule:

```typescript
// app/products/[id]/page.tsx — ISR with generateStaticParams
export async function generateStaticParams() {
  const products = await db.products.findAll({ select: ['id'] })
  return products.map((p) => ({ id: p.id }))
}

export default async function ProductPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const product = await fetch(`https://api.example.com/products/${id}`, {
    next: { revalidate: 3600 }, // Revalidate every hour
  }).then((r) => r.json())

  return (
    <article>
      <h1>{product.name}</h1>
      <p>{product.description}</p>
      <span>${product.price}</span>
    </article>
  )
}
```

## On-Demand Revalidation

Purge cache instantly using `revalidateTag` and `revalidatePath`:

```typescript
// lib/data.ts — tag your fetches
export async function getProduct(id: string) {
  return fetch(`https://api.example.com/products/${id}`, {
    next: { tags: [`product-${id}`, 'products'] },
  }).then((r) => r.json())
}

export async function getProducts() {
  return fetch('https://api.example.com/products', {
    next: { tags: ['products'] },
  }).then((r) => r.json())
}

// app/api/revalidate/route.ts — webhook endpoint
import { revalidateTag, revalidatePath } from 'next/cache'
import { NextRequest, NextResponse } from 'next/server'

export async function POST(req: NextRequest) {
  const secret = req.headers.get('x-revalidation-secret')
  if (secret !== process.env.REVALIDATION_SECRET) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const { type, id } = await req.json()

  if (type === 'product' && id) {
    revalidateTag(`product-${id}`)  // Invalidate single product
    revalidateTag('products')        // Invalidate product list
  }

  if (type === 'page') {
    revalidatePath(`/products/${id}`) // Invalidate specific page
  }

  return NextResponse.json({ revalidated: true, now: Date.now() })
}
```

## Parallel Fetching with Promise.all

Fetch independent data sources concurrently to reduce waterfall:

```typescript
// app/dashboard/page.tsx — parallel data fetching
export default async function DashboardPage() {
  // BAD: sequential — each awaits before next starts
  // const user = await getUser()
  // const orders = await getOrders()
  // const stats = await getStats()

  // GOOD: parallel — all start simultaneously
  const [user, orders, stats] = await Promise.all([
    getUser(),
    getOrders(),
    getStats(),
  ])

  return (
    <div>
      <UserHeader user={user} />
      <OrderList orders={orders} />
      <StatsPanel stats={stats} />
    </div>
  )
}

// For mixed critical/non-critical data, combine Promise.all with Suspense
export default async function DashboardPage() {
  const user = await getUser() // critical — block render

  return (
    <div>
      <UserHeader user={user} />
      <Suspense fallback={<OrdersSkeleton />}>
        <OrderList userId={user.id} />  {/* async server component, streams in */}
      </Suspense>
    </div>
  )
}
```

## Cache Tags Strategy

Organize cache tags for granular invalidation:

```typescript
// lib/cache-tags.ts — centralize tag naming
export const cacheTags = {
  user: (id: string) => `user-${id}`,
  userList: () => 'users',
  product: (id: string) => `product-${id}`,
  productsByCategory: (cat: string) => `products-cat-${cat}`,
  productList: () => 'products',
} as const

// Usage in data fetching
async function getProductsByCategory(category: string) {
  return fetch(`${API}/products?category=${category}`, {
    next: {
      tags: [
        cacheTags.productsByCategory(category),
        cacheTags.productList(),
      ],
    },
  }).then((r) => r.json())
}
```

## Token Cost

- Pattern: 100-150 tokens
- Context7 (if needed): 1000-1500 tokens
