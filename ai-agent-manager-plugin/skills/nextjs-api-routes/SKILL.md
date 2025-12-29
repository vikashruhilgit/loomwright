---
name: nextjs-api-routes
description: Implement RESTful API endpoints using route.ts handler functions. Use when creating API endpoints, handling HTTP requests, or building REST APIs in Next.js.
---

# Next.js API Routes Skill

Implement RESTful API endpoints using route.ts handler functions.

## Quick Pattern

```typescript
// app/api/posts/route.ts
import { NextRequest, NextResponse } from 'next/server'

export async function GET(request: NextRequest) {
  const posts = await db.posts.findAll()
  return NextResponse.json(posts)
}

export async function POST(request: NextRequest) {
  const body = await request.json()
  const post = await db.posts.create(body)
  return NextResponse.json(post, { status: 201 })
}
```

## When to Use

- Basic GET and POST endpoints
- Dynamic routes with path parameters
- PUT and DELETE operations
- Request handling (headers, cookies, body)
- Response handling and status codes

## Token Cost

- Pattern: 100-150 tokens
- Context7 (if needed): 1000-1500 tokens
