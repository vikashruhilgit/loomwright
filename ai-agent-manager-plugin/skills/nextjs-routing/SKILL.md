---
name: nextjs-routing
version: "1.0.0"
lastUpdated: "2026-03"
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

## Intercepting Routes

Intercept a route to show it in a modal while preserving the URL:

```
app/
├── @modal/
│   ├── (.)photo/[id]/
│   │   └── page.tsx        # Intercepted: shows photo in modal
│   └── default.tsx         # Returns null (no modal by default)
├── photo/[id]/
│   └── page.tsx            # Full page: direct navigation or refresh
└── layout.tsx              # Renders {children} + {modal}
```

```typescript
// app/layout.tsx
export default function Layout({
  children,
  modal,
}: {
  children: React.ReactNode
  modal: React.ReactNode
}) {
  return (
    <>
      {children}
      {modal}
    </>
  )
}

// app/@modal/(.)photo/[id]/page.tsx — intercepted route
export default async function PhotoModal({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const photo = await getPhoto(id)
  return (
    <dialog open>
      <img src={photo.url} alt={photo.title} />
    </dialog>
  )
}
```

## Parallel Routes

Render multiple pages simultaneously in named slots:

```
app/
├── @analytics/
│   ├── page.tsx            # Analytics panel
│   └── default.tsx         # Fallback for unmatched routes
├── @team/
│   ├── page.tsx            # Team panel
│   └── default.tsx
├── layout.tsx              # Renders both slots
└── page.tsx                # Main content
```

```typescript
// app/layout.tsx — parallel route layout
export default function DashboardLayout({
  children,
  analytics,
  team,
}: {
  children: React.ReactNode
  analytics: React.ReactNode
  team: React.ReactNode
}) {
  return (
    <div className="grid grid-cols-2">
      <main>{children}</main>
      <aside>{analytics}</aside>
      <aside>{team}</aside>
    </div>
  )
}
```

## Route Groups

Organize routes without affecting URL structure using `(groupName)`:

```
app/
├── (marketing)/
│   ├── layout.tsx          # Marketing-specific layout
│   ├── about/page.tsx      # /about
│   └── blog/page.tsx       # /blog
├── (shop)/
│   ├── layout.tsx          # Shop layout with cart sidebar
│   ├── products/page.tsx   # /products
│   └── cart/page.tsx       # /cart
└── layout.tsx              # Root layout
```

## Middleware Patterns

Use `middleware.ts` at the project root for request interception:

```typescript
// middleware.ts
import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'

export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl

  // Locale redirect
  if (pathname === '/') {
    const locale = request.headers.get('accept-language')?.split(',')[0] || 'en'
    return NextResponse.redirect(new URL(`/${locale}`, request.url))
  }

  // Add custom headers
  const response = NextResponse.next()
  response.headers.set('x-pathname', pathname)
  return response
}

export const config = {
  matcher: ['/((?!api|_next/static|_next/image|favicon.ico).*)'],
}
```

## Token Cost

- Pattern: 150-200 tokens
- Context7 (if needed): 1000-1500 tokens
