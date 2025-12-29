# Next.js App Router Routing Skill

Implement routes using Next.js 14+ App Router with file-based routing.

## Quick Pattern

```typescript
// app/page.tsx - Home page
export default function Home() {
  return <h1>Welcome</h1>
}

// app/blog/page.tsx - Blog index
export default function BlogIndex() {
  return <div>Blog posts</div>
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

## Patterns

### 1. Basic File Routing

**Structure:**
```
app/
├── page.tsx              → /
├── blog/
│   ├── page.tsx         → /blog
│   └── [slug]/
│       └── page.tsx     → /blog/:slug
└── dashboard/
    └── page.tsx         → /dashboard
```

**File naming rules:**
- `page.tsx` - Route page component
- `layout.tsx` - Shared layout (applies to child routes)
- `route.ts` - API endpoint
- `error.tsx` - Error boundary
- `loading.tsx` - Suspense fallback
- `not-found.tsx` - 404 page

### 2. Dynamic Routes with Parameters

**Single parameter:**
```typescript
// app/users/[id]/page.tsx
interface Props {
  params: Promise<{ id: string }>
}

export default async function UserPage({ params }: Props) {
  const { id } = await params
  const user = await fetchUser(id)
  return <div>{user.name}</div>
}
```

**Multiple parameters:**
```typescript
// app/blog/[year]/[month]/[day]/page.tsx
interface Props {
  params: Promise<{ year: string; month: string; day: string }>
}

export default async function PostDate({ params }: Props) {
  const { year, month, day } = await params
  return <div>Posts from {year}-{month}-{day}</div>
}
```

**Catch-all routes:**
```typescript
// app/docs/[...slug]/page.tsx (catches /docs/a/b/c)
interface Props {
  params: Promise<{ slug: string[] }>
}

export default async function DocsPage({ params }: Props) {
  const { slug } = await params
  return <div>Path: {slug.join('/')}</div>
}
```

### 3. Layouts for Shared Structure

```typescript
// app/layout.tsx - Root layout
export const metadata = {
  title: 'My App',
  description: 'App description'
}

export default function RootLayout({
  children
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  )
}

// app/dashboard/layout.tsx - Dashboard layout
export default function DashboardLayout({
  children
}: {
  children: React.ReactNode
}) {
  return (
    <div className="flex">
      <Sidebar />
      <main>{children}</main>
    </div>
  )
}
```

### 4. Route Groups (Parentheses)

**Organize without affecting URL:**
```
app/
├── (marketing)/
│   ├── page.tsx          → /
│   ├── about/page.tsx    → /about
│   └── layout.tsx        (applies only to marketing routes)
└── (app)/
    ├── dashboard/page.tsx → /dashboard
    └── layout.tsx        (applies only to app routes)
```

**Usage:**
```typescript
// app/(marketing)/layout.tsx
export default function MarketingLayout({ children }) {
  return (
    <div>
      <Header />
      {children}
      <Footer />
    </div>
  )
}

// app/(app)/layout.tsx
export default function AppLayout({ children }) {
  return (
    <div>
      <Sidebar />
      {children}
    </div>
  )
}
```

### 5. Optional Catch-All

```typescript
// app/[[...slug]]/page.tsx (optional, allows / and /any/path)
interface Props {
  params: Promise<{ slug?: string[] }>
}

export default async function Page({ params }: Props) {
  const { slug } = await params
  const path = slug?.join('/') ?? 'root'
  return <div>Current path: {path}</div>
}
```

### 6. Parallel Routes (Advanced)

```
app/
└── dashboard/
    ├── @analytics/page.tsx   (named slot)
    ├── @users/page.tsx       (named slot)
    └── layout.tsx
```

**Layout with slots:**
```typescript
export default function DashboardLayout({
  children,
  analytics,
  users
}: {
  children: React.ReactNode
  analytics: React.ReactNode
  users: React.ReactNode
}) {
  return (
    <div>
      <div className="grid grid-cols-2">
        <section>{analytics}</section>
        <section>{users}</section>
      </div>
      {children}
    </div>
  )
}
```

## Link Navigation

```typescript
import Link from 'next/link'

// Simple link
<Link href="/blog">Blog</Link>

// With active class
<Link
  href="/blog"
  className={pathname === '/blog' ? 'active' : ''}
>
  Blog
</Link>

// Programmatic navigation
'use client'
import { useRouter } from 'next/navigation'

export function Button() {
  const router = useRouter()
  return (
    <button onClick={() => router.push('/dashboard')}>
      Go to Dashboard
    </button>
  )
}
```

## Metadata

```typescript
import type { Metadata } from 'next'

// Static metadata
export const metadata: Metadata = {
  title: 'My Page',
  description: 'Page description',
  openGraph: {
    title: 'My Page',
    description: 'Page description',
    url: 'https://example.com'
  }
}

// Dynamic metadata
export async function generateMetadata({
  params
}: {
  params: Promise<{ id: string }>
}): Promise<Metadata> {
  const { id } = await params
  const post = await fetchPost(id)
  return {
    title: post.title,
    description: post.excerpt
  }
}
```

## Testing Routes

```typescript
describe('Routing', () => {
  it('should load home page', async () => {
    const { default: Home } = await import('@/app/page')
    expect(Home).toBeDefined()
  })

  it('should load dynamic route with params', async () => {
    const params = { slug: 'test-post' }
    const { default: Post } = await import(
      '@/app/blog/[slug]/page'
    )
    const result = Post({ params: Promise.resolve(params) })
    expect(result).toBeDefined()
  })
})
```

## Anti-Patterns

❌ Using pages/ directory (old Pages Router)
```
// Old way
pages/blog/[slug].js
```

✓ Use app/ directory (App Router)
```
// New way
app/blog/[slug]/page.tsx
```

❌ Hardcoding URLs
```typescript
<a href="/users/123">User</a>
```

✓ Use Link with href
```typescript
<Link href={`/users/${id}`}>User</Link>
```

❌ Next.js routing in client component without dynamic import
```typescript
export default function Page() {
  return <DynamicRoute /> // May cause hydration errors
}
```

✓ Mark client components with 'use client'
```typescript
'use client'
export default function Page() {
  const router = useRouter()
  return <button onClick={() => router.push('/')}>Home</button>
}
```

## Token Cost

- Invocation: 100 tokens
- Pattern: 150-200 tokens
- Context7 (if needed): 1000-1500 tokens
- **Total:** 250-1900 tokens

## When to Lookup Context7

- Advanced parallel routes behavior
- Intercepting routes (advanced pattern)
- Dynamic route optimization strategies
- Performance considerations for large route trees
