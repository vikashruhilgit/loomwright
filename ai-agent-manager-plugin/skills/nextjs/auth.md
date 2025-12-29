# Next.js Authentication Skill

Implement authentication with NextAuth.js, session management, and protected routes.

## Quick Pattern

```typescript
// auth.ts - NextAuth configuration
import NextAuth from 'next-auth'
import CredentialsProvider from 'next-auth/providers/credentials'
import { db } from '@/lib/db'

export const { handlers, auth, signIn, signOut } = NextAuth({
  providers: [
    CredentialsProvider({
      async authorize(credentials) {
        const user = await db.users.findByEmail(credentials.email as string)

        if (!user) return null

        const isPasswordValid = await verifyPassword(
          credentials.password as string,
          user.password
        )

        if (!isPasswordValid) return null

        return { id: user.id, email: user.email, name: user.name }
      }
    })
  ],
  pages: {
    signIn: '/login'
  },
  callbacks: {
    async jwt({ token, user }) {
      if (user) {
        token.id = user.id
        token.role = (user as any).role || 'user'
      }
      return token
    },
    async session({ session, token }) {
      session.user.id = token.id as string
      session.user.role = token.role as string
      return session
    }
  }
})

// route.ts - API route handler
export const { GET, POST } = handlers

// middleware.ts - Protect routes
import { auth } from '@/auth'

export default auth(req => {
  if (!req.auth && req.nextUrl.pathname.startsWith('/dashboard')) {
    const newUrl = new URL('/login', req.nextUrl.origin)
    return Response.redirect(newUrl)
  }
})

// page.tsx - Get current session
import { auth } from '@/auth'

export default async function DashboardPage() {
  const session = await auth()

  if (!session) {
    return <div>Not authenticated</div>
  }

  return <div>Welcome {session.user?.email}</div>
}

// Client component - Sign in/out
import { signIn, signOut } from '@/auth'

export function SignInButton() {
  return (
    <form action={async () => {
      'use server'
      await signIn('credentials', { redirectTo: '/dashboard' })
    }}>
      <button type="submit">Sign In</button>
    </form>
  )
}
```

## Patterns

### 1. NextAuth Setup with Credentials Provider

**Configuration:**
```typescript
// auth.ts - NextAuth configuration file
import NextAuth, { type NextAuthOptions } from 'next-auth'
import CredentialsProvider from 'next-auth/providers/credentials'
import { db } from '@/lib/db'
import bcrypt from 'bcrypt'

async function verifyPassword(
  plainPassword: string,
  hashedPassword: string
): Promise<boolean> {
  return bcrypt.compare(plainPassword, hashedPassword)
}

export const authOptions: NextAuthOptions = {
  providers: [
    CredentialsProvider({
      name: 'Email and Password',
      credentials: {
        email: { label: 'Email', type: 'email' },
        password: { label: 'Password', type: 'password' }
      },
      async authorize(credentials) {
        if (!credentials?.email || !credentials?.password) {
          return null
        }

        const user = await db.users.findByEmail(credentials.email)

        if (!user) {
          return null
        }

        const passwordMatch = await verifyPassword(
          credentials.password,
          user.password
        )

        if (!passwordMatch) {
          return null
        }

        return {
          id: user.id,
          email: user.email,
          name: user.name,
          image: user.avatar
        }
      }
    })
  ],
  pages: {
    signIn: '/auth/signin',
    error: '/auth/error'
  },
  callbacks: {
    async jwt({ token, user }) {
      if (user) {
        token.id = user.id
        token.role = (user as any).role || 'user'
      }
      return token
    },
    async session({ session, token }) {
      if (session.user) {
        session.user.id = token.id as string
        session.user.role = token.role as string
      }
      return session
    }
  },
  session: {
    strategy: 'jwt',
    maxAge: 24 * 60 * 60  // 24 hours
  },
  secret: process.env.NEXTAUTH_SECRET
}

export const { handlers, auth, signIn, signOut } = NextAuth(authOptions)
```

**Route handler:**
```typescript
// app/api/auth/[...nextauth]/route.ts
import { handlers } from '@/auth'

export const { GET, POST } = handlers
```

### 2. OAuth Providers

**Google OAuth:**
```typescript
import GoogleProvider from 'next-auth/providers/google'

export const authOptions: NextAuthOptions = {
  providers: [
    GoogleProvider({
      clientId: process.env.GOOGLE_CLIENT_ID!,
      clientSecret: process.env.GOOGLE_CLIENT_SECRET!,
      allowDangerousEmailAccountLinking: true
    })
  ],
  callbacks: {
    async signIn({ user, account }) {
      // Create or update user in database
      const dbUser = await db.users.findByEmail(user.email!)

      if (!dbUser) {
        await db.users.create({
          email: user.email!,
          name: user.name,
          image: user.image,
          provider: account?.provider
        })
      }

      return true
    }
  }
}
```

**GitHub OAuth:**
```typescript
import GithubProvider from 'next-auth/providers/github'

export const authOptions: NextAuthOptions = {
  providers: [
    GithubProvider({
      clientId: process.env.GITHUB_ID!,
      clientSecret: process.env.GITHUB_SECRET!
    })
  ]
}
```

### 3. Session Management

**Get current session in server component:**
```typescript
// app/dashboard/page.tsx
import { auth } from '@/auth'
import { redirect } from 'next/navigation'

export default async function DashboardPage() {
  const session = await auth()

  // Redirect to login if not authenticated
  if (!session) {
    redirect('/auth/signin')
  }

  const { user } = session

  return (
    <div>
      <h1>Welcome {user?.name}</h1>
      <p>Email: {user?.email}</p>
      <p>Role: {user?.role}</p>
    </div>
  )
}
```

**Get session in API route:**
```typescript
// app/api/profile/route.ts
import { auth } from '@/auth'
import { NextResponse } from 'next/server'

export async function GET() {
  const session = await auth()

  if (!session?.user) {
    return NextResponse.json(
      { error: 'Unauthorized' },
      { status: 401 }
    )
  }

  return NextResponse.json(session.user)
}
```

**Client-side session (useSession hook - browser only):**
```typescript
'use client'
import { useSession } from 'next-auth/react'

export function UserGreeting() {
  const { data: session, status } = useSession()

  if (status === 'loading') return <div>Loading...</div>

  if (!session) {
    return <div>Not signed in</div>
  }

  return <div>Welcome back, {session.user?.email}</div>
}
```

### 4. Middleware for Protected Routes

**Protect entire directory:**
```typescript
// middleware.ts - At root level, NOT in app/
import { auth } from '@/auth'
import { NextResponse } from 'next/server'

export default auth(req => {
  const isProtectedRoute = req.nextUrl.pathname.startsWith('/dashboard') ||
                          req.nextUrl.pathname.startsWith('/admin')

  if (isProtectedRoute && !req.auth) {
    // Redirect to login
    const loginUrl = new URL('/auth/signin', req.nextUrl.origin)
    loginUrl.searchParams.set('callbackUrl', req.nextUrl.href)
    return NextResponse.redirect(loginUrl)
  }

  // Check role-based access
  if (req.nextUrl.pathname.startsWith('/admin') &&
      req.auth?.user?.role !== 'admin') {
    return NextResponse.redirect(new URL('/unauthorized', req.nextUrl.origin))
  }

  return NextResponse.next()
})

export const config = {
  matcher: ['/dashboard/:path*', '/admin/:path*', '/api/admin/:path*']
}
```

**Protection per endpoint:**
```typescript
// app/api/protected/route.ts
import { auth } from '@/auth'
import { NextResponse } from 'next/server'

export async function GET(request: Request) {
  const session = await auth()

  if (!session) {
    return NextResponse.json(
      { error: 'Not authenticated' },
      { status: 401 }
    )
  }

  if (session.user?.role !== 'admin') {
    return NextResponse.json(
      { error: 'Access denied' },
      { status: 403 }
    )
  }

  return NextResponse.json({ data: 'admin-only-data' })
}
```

### 5. Sign In / Sign Out Forms

**Sign-in form:**
```typescript
// app/auth/signin/page.tsx
import { signIn } from '@/auth'

export default function SignInPage() {
  return (
    <div className="max-w-md mx-auto mt-8">
      <h1>Sign In</h1>

      {/* Server action form */}
      <form action={async (formData) => {
        'use server'
        await signIn('credentials', {
          email: formData.get('email'),
          password: formData.get('password'),
          redirectTo: '/dashboard'
        })
      }}>
        <input
          type="email"
          name="email"
          placeholder="Email"
          required
        />
        <input
          type="password"
          name="password"
          placeholder="Password"
          required
        />
        <button type="submit">Sign In</button>
      </form>

      {/* OAuth buttons */}
      <form action={async () => {
        'use server'
        await signIn('google', { redirectTo: '/dashboard' })
      }}>
        <button type="submit">Sign In with Google</button>
      </form>
    </div>
  )
}
```

**Sign-out:**
```typescript
'use client'
import { signOut } from 'next-auth/react'

export function SignOutButton() {
  return (
    <button onClick={() => signOut({ redirectTo: '/auth/signin' })}>
      Sign Out
    </button>
  )
}

// Or with server action
import { signOut } from '@/auth'

export function SignOutServerButton() {
  return (
    <form action={async () => {
      'use server'
      await signOut({ redirectTo: '/' })
    }}>
      <button type="submit">Sign Out</button>
    </form>
  )
}
```

### 6. JWT vs Session Strategy

**JWT-based (stateless):**
```typescript
export const authOptions: NextAuthOptions = {
  session: {
    strategy: 'jwt'  // Default for Credentials provider
  },
  callbacks: {
    async jwt({ token, user }) {
      // Add to token
      if (user) {
        token.id = user.id
        token.role = user.role
      }
      return token
    },
    async session({ session, token }) {
      // Add from token to session
      session.user.id = token.id as string
      session.user.role = token.role as string
      return session
    }
  }
}
```

**Database session (stateful):**
```typescript
import { PrismaAdapter } from '@next-auth/prisma-adapter'

export const authOptions: NextAuthOptions = {
  adapter: PrismaAdapter(prisma),
  session: {
    strategy: 'database'  // Use database instead of JWT
  },
  providers: [
    // ... providers
  ]
}
```

### 7. CSRF Protection

**Automatic in NextAuth:**
```typescript
// NextAuth automatically includes CSRF tokens in forms
// No additional configuration needed

export async function POST(req: Request) {
  // If using NextAuth's signIn, CSRF is validated automatically
  const session = await auth()  // CSRF-protected
  // ...
}
```

**Custom CSRF (if needed):**
```typescript
import { generateCSRFToken, validateCSRFToken } from '@/lib/csrf'

export async function GET(req: Request) {
  const token = await generateCSRFToken()
  return NextResponse.json({ token })
}

export async function POST(req: Request) {
  const token = req.headers.get('x-csrf-token')

  if (!await validateCSRFToken(token)) {
    return NextResponse.json(
      { error: 'Invalid CSRF token' },
      { status: 403 }
    )
  }

  // Process request
}
```

## When to Use

**Credentials Provider** - Self-managed authentication
- Custom login/password logic
- Database-stored credentials
- Full control over flow

**OAuth Providers** - Third-party authentication
- Reduced complexity
- User convenience (sign in with Google/GitHub)
- Less password management

**Middleware Protection** - Protect multiple routes
- Directory-wide protection (/dashboard/*)
- Role-based access control
- Centralized security

**Server Component Auth** - Render-time protection
- Protected pages that redirect if not authenticated
- Access session data directly
- No client-side auth logic

## Anti-Patterns

❌ **Storing passwords in plain text**
```typescript
// ❌ NO - Never store plain passwords
await db.users.create({
  email,
  password: plainPassword  // NEVER!
})
```

✓ **Hash passwords**
```typescript
// ✓ Always hash passwords
import bcrypt from 'bcrypt'

const hashedPassword = await bcrypt.hash(plainPassword, 10)
await db.users.create({ email, password: hashedPassword })
```

❌ **Mixing JWTs with database sessions**
```typescript
// ❌ Conflicting strategies
export const authOptions = {
  session: { strategy: 'jwt' },
  adapter: PrismaAdapter(prisma)  // Expects database strategy!
}
```

✓ **Pick one session strategy**
```typescript
// ✓ JWT only (no adapter)
export const authOptions = {
  session: { strategy: 'jwt' },
  callbacks: { jwt() {...}, session() {...} }
}

// OR database (with adapter)
export const authOptions = {
  adapter: PrismaAdapter(prisma),
  session: { strategy: 'database' }
}
```

❌ **Not redirecting unauthenticated users**
```typescript
// ❌ Shows private data to anyone
export default async function DashboardPage() {
  const session = await auth()
  // Missing redirect - page renders even if !session!
  return <div>{session?.user?.email}</div>
}
```

✓ **Redirect if not authenticated**
```typescript
// ✓ Protect with redirect
import { redirect } from 'next/navigation'

export default async function DashboardPage() {
  const session = await auth()
  if (!session) {
    redirect('/auth/signin')
  }
  return <div>{session.user?.email}</div>
}
```

❌ **Exposing sensitive data in callbacks**
```typescript
// ❌ Stores database password in JWT
async jwt({ token, user }) {
  token.password = user.password  // NO!
  return token
}
```

✓ **Only include necessary fields**
```typescript
// ✓ Only public/needed fields
async jwt({ token, user }) {
  token.id = user.id
  token.email = user.email
  token.role = user.role
  return token
}
```

## Testing Authentication

```typescript
describe('Authentication', () => {
  it('should authenticate with valid credentials', async () => {
    const response = await fetch('/api/auth/signin', {
      method: 'POST',
      body: JSON.stringify({
        email: 'test@example.com',
        password: 'password123'
      })
    })

    expect(response.status).toBe(200)
    const data = await response.json()
    expect(data.user).toBeDefined()
  })

  it('should reject invalid password', async () => {
    const response = await fetch('/api/auth/signin', {
      method: 'POST',
      body: JSON.stringify({
        email: 'test@example.com',
        password: 'wrongpassword'
      })
    })

    expect(response.status).toBe(401)
  })

  it('should protect routes with middleware', async () => {
    const response = await fetch('/dashboard')
    expect(response.status).toBe(307)  // Redirect to login
  })

  it('should return session data for authenticated user', async () => {
    const session = await auth()
    expect(session?.user?.email).toBeDefined()
  })
})
```

## Token Cost

- Invocation: 100 tokens
- Quick pattern: 100-150 tokens
- Detailed patterns (7 sections): 600-800 tokens
- Session management guide: 200-250 tokens
- Middleware and protection: 250-300 tokens
- OAuth setup: 200-250 tokens
- Anti-patterns: 200-300 tokens
- Testing examples: 150-200 tokens
- **Total:** 1400-2050 tokens per invocation

## When to Lookup Context7

- NextAuth.js version compatibility (v4 vs v5 differences)
- Advanced callback workflows
- Custom session encryption strategies
- OAuth provider specific settings
- Adapter implementation details
- Performance tuning for large user bases
- Multi-tenancy authentication patterns
