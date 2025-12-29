---
name: nextjs-auth
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

## Token Cost

- Pattern: 100-150 tokens
- Context7 (if needed): 1000-1500 tokens
