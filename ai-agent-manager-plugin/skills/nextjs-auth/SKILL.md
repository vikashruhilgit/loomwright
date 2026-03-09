---
name: nextjs-auth
version: "1.0.0"
lastUpdated: "2026-03"
description: Implement authentication with NextAuth.js, session management, and protected routes. Use when implementing user authentication in Next.js applications.
---

# Next.js Authentication Skill

Implement authentication with NextAuth.js, session management, and protected routes.

## Quick Pattern

```typescript
// auth.ts - NextAuth configuration
import NextAuth from 'next-auth'
import CredentialsProvider from 'next-auth/providers/credentials'

export const { handlers, auth, signIn, signOut } = NextAuth({
  providers: [
    CredentialsProvider({
      async authorize(credentials) {
        const user = await db.users.findByEmail(credentials.email)
        if (!user) return null
        return { id: user.id, email: user.email }
      }
    })
  ]
})
```

## When to Use

- NextAuth setup with Credentials provider
- OAuth providers (Google, GitHub)
- Session management
- Middleware for protected routes
- Sign in/out forms

## NextAuth.js v5 Patterns

v5 uses the `auth()` function everywhere and supports Edge runtime:

```typescript
// auth.ts — NextAuth v5 configuration
import NextAuth from 'next-auth'
import GitHub from 'next-auth/providers/github'
import Credentials from 'next-auth/providers/credentials'
import { DrizzleAdapter } from '@auth/drizzle-adapter'

export const { handlers, auth, signIn, signOut } = NextAuth({
  adapter: DrizzleAdapter(db),
  providers: [
    GitHub,
    Credentials({
      credentials: {
        email: { label: 'Email', type: 'email' },
        password: { label: 'Password', type: 'password' },
      },
      async authorize(credentials) {
        const user = await db.users.findByEmail(credentials.email as string)
        if (!user || !await bcrypt.compare(credentials.password as string, user.hash)) {
          return null
        }
        return { id: user.id, name: user.name, email: user.email, role: user.role }
      },
    }),
  ],
  callbacks: {
    async jwt({ token, user }) {
      if (user) token.role = user.role
      return token
    },
    async session({ session, token }) {
      session.user.id = token.sub!
      session.user.role = token.role as string
      return session
    },
  },
})

// app/api/auth/[...nextauth]/route.ts
import { handlers } from '@/auth'
export const { GET, POST } = handlers
```

## Middleware Auth (Matcher Config)

Protect routes at the edge using middleware:

```typescript
// middleware.ts
import { auth } from '@/auth'
import { NextResponse } from 'next/server'

export default auth((req) => {
  const { pathname } = req.nextUrl
  const isLoggedIn = !!req.auth

  // Redirect unauthenticated users to sign-in
  if (!isLoggedIn && pathname.startsWith('/dashboard')) {
    const signInUrl = new URL('/auth/signin', req.url)
    signInUrl.searchParams.set('callbackUrl', pathname)
    return NextResponse.redirect(signInUrl)
  }

  // Role-based route protection
  if (pathname.startsWith('/admin') && req.auth?.user?.role !== 'admin') {
    return NextResponse.redirect(new URL('/unauthorized', req.url))
  }

  return NextResponse.next()
})

export const config = {
  matcher: [
    '/dashboard/:path*',
    '/admin/:path*',
    '/api/protected/:path*',
  ],
}
```

## Protected API Routes with getServerSession

Secure API routes by checking the session server-side:

```typescript
// app/api/protected/profile/route.ts
import { auth } from '@/auth'
import { NextResponse } from 'next/server'

export async function GET() {
  const session = await auth()

  if (!session?.user) {
    return NextResponse.json({ error: 'Not authenticated' }, { status: 401 })
  }

  const profile = await db.profiles.findByUserId(session.user.id)
  return NextResponse.json(profile)
}

export async function PUT(request: Request) {
  const session = await auth()
  if (!session?.user) {
    return NextResponse.json({ error: 'Not authenticated' }, { status: 401 })
  }

  const body = await request.json()
  const updated = await db.profiles.update(session.user.id, body)
  return NextResponse.json(updated)
}

// Server Component usage
import { auth } from '@/auth'
import { redirect } from 'next/navigation'

export default async function SettingsPage() {
  const session = await auth()
  if (!session) redirect('/auth/signin')

  return <SettingsForm user={session.user} />
}
```

## Related Skills

- `nestjs-guards` — NestJS guards for backend API auth (protects endpoints that NextAuth sessions call)
- `gateway-auth-middleware` — API Gateway JWT/API key middleware (validates tokens before requests reach Next.js or NestJS)

## Token Cost

- Pattern: 100-150 tokens
- Context7 (if needed): 1000-1500 tokens
