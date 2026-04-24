---
name: nextjs-api-routes
version: "1.0.0"
lastUpdated: "2026-03"
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

## Middleware Chaining

Compose multiple middleware functions for reusable request processing:

```typescript
// lib/api-middleware.ts
import { NextRequest, NextResponse } from 'next/server'

type Handler = (req: NextRequest, context?: any) => Promise<NextResponse>
type Middleware = (handler: Handler) => Handler

export function withAuth(handler: Handler): Handler {
  return async (req, context) => {
    const token = req.headers.get('authorization')?.replace('Bearer ', '')
    if (!token) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }
    const user = await verifyToken(token)
    ;(req as any).user = user
    return handler(req, context)
  }
}

export function withLogging(handler: Handler): Handler {
  return async (req, context) => {
    const start = Date.now()
    const response = await handler(req, context)
    console.log(`${req.method} ${req.url} ${response.status} ${Date.now() - start}ms`)
    return response
  }
}

export function compose(...middlewares: Middleware[]): Middleware {
  return (handler) => middlewares.reduceRight((h, mw) => mw(h), handler)
}

// app/api/admin/route.ts — usage
import { compose, withAuth, withLogging } from '@/lib/api-middleware'

const enhance = compose(withLogging, withAuth)

export const GET = enhance(async (req) => {
  const user = (req as any).user
  return NextResponse.json({ admin: true, user })
})
```

## Comprehensive Error Handling

Standardize error responses across all API routes:

```typescript
// lib/api-errors.ts
export class ApiError extends Error {
  constructor(
    public statusCode: number,
    message: string,
    public code?: string,
  ) {
    super(message)
  }
}

export function withErrorHandler(handler: Handler): Handler {
  return async (req, context) => {
    try {
      return await handler(req, context)
    } catch (error) {
      if (error instanceof ApiError) {
        return NextResponse.json(
          { error: error.message, code: error.code },
          { status: error.statusCode },
        )
      }
      if (error instanceof z.ZodError) {
        return NextResponse.json(
          { error: 'Validation failed', details: error.flatten().fieldErrors },
          { status: 400 },
        )
      }
      console.error('Unhandled API error:', error)
      return NextResponse.json(
        { error: 'Internal server error' },
        { status: 500 },
      )
    }
  }
}

// Usage in route
export const POST = withErrorHandler(async (req) => {
  const body = await req.json()
  const parsed = CreatePostSchema.parse(body) // throws ZodError if invalid
  const post = await db.posts.create(parsed)
  return NextResponse.json(post, { status: 201 })
})
```

## Streaming Responses with ReadableStream

Stream large datasets or server-sent events:

```typescript
// app/api/stream/route.ts
export async function GET() {
  const encoder = new TextEncoder()

  const stream = new ReadableStream({
    async start(controller) {
      for await (const event of subscribeToEvents()) {
        const data = `data: ${JSON.stringify(event)}\n\n`
        controller.enqueue(encoder.encode(data))
      }
      controller.close()
    },
    cancel() {
      // Clean up subscription on client disconnect
    },
  })

  return new Response(stream, {
    headers: {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      Connection: 'keep-alive',
    },
  })
}

// Large file download with streaming
export async function GET() {
  const stream = new ReadableStream({
    async start(controller) {
      const cursor = db.records.cursor({ batchSize: 1000 })
      for await (const batch of cursor) {
        const csv = batch.map(r => `${r.id},${r.name}\n`).join('')
        controller.enqueue(new TextEncoder().encode(csv))
      }
      controller.close()
    },
  })

  return new Response(stream, {
    headers: {
      'Content-Type': 'text/csv',
      'Content-Disposition': 'attachment; filename="export.csv"',
    },
  })
}
```

## Token Cost

- Pattern: 100-150 tokens
- Context7 (if needed): 1000-1500 tokens
