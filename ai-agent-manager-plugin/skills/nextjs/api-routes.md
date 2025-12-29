# Next.js API Routes Skill

Implement RESTful API endpoints using route.ts handler functions.

## Quick Pattern

```typescript
// app/api/posts/route.ts - GET and POST handlers
import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'

// GET /api/posts - List all posts
export async function GET(request: NextRequest) {
  try {
    const posts = await db.posts.findAll()
    return NextResponse.json(posts)
  } catch (error) {
    return NextResponse.json(
      { error: 'Failed to fetch posts' },
      { status: 500 }
    )
  }
}

// POST /api/posts - Create post
export async function POST(request: NextRequest) {
  try {
    const body = await request.json()
    const { title, content } = body

    if (!title || !content) {
      return NextResponse.json(
        { error: 'Title and content required' },
        { status: 400 }
      )
    }

    const post = await db.posts.create({ title, content })
    return NextResponse.json(post, { status: 201 })
  } catch (error) {
    return NextResponse.json(
      { error: 'Failed to create post' },
      { status: 500 }
    )
  }
}

// app/api/posts/[id]/route.ts - GET by ID, PUT, DELETE
export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params
  const post = await db.posts.findById(id)

  if (!post) {
    return NextResponse.json({ error: 'Not found' }, { status: 404 })
  }

  return NextResponse.json(post)
}

export async function PUT(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params
  const body = await request.json()

  const post = await db.posts.update(id, body)
  return NextResponse.json(post)
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params
  await db.posts.delete(id)
  return NextResponse.json({ success: true })
}
```

## Patterns

### 1. Basic GET and POST

**GET - List endpoint:**
```typescript
// app/api/users/route.ts
import { NextResponse } from 'next/server'
import { db } from '@/lib/db'

export async function GET() {
  const users = await db.users.findAll()
  return NextResponse.json(users)
}

// GET with query parameters
import { NextRequest } from 'next/server'

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url)
  const limit = searchParams.get('limit') || '10'
  const offset = searchParams.get('offset') || '0'

  const users = await db.users.findAll({
    limit: parseInt(limit),
    offset: parseInt(offset),
  })

  return NextResponse.json({
    data: users,
    total: await db.users.count(),
  })
}
```

**POST - Create endpoint:**
```typescript
import { NextRequest, NextResponse } from 'next/server'

export async function POST(request: NextRequest) {
  try {
    const body = await request.json()

    // Validate input
    if (!body.email || !body.name) {
      return NextResponse.json(
        { error: 'Email and name required' },
        { status: 400 }
      )
    }

    const user = await db.users.create({
      email: body.email,
      name: body.name,
      role: body.role || 'user',
    })

    return NextResponse.json(user, { status: 201 })
  } catch (error: any) {
    if (error.code === '23505') {
      // Unique constraint violation
      return NextResponse.json(
        { error: 'Email already exists' },
        { status: 409 }
      )
    }

    return NextResponse.json(
      { error: 'Failed to create user' },
      { status: 500 }
    )
  }
}
```

### 2. Dynamic Routes with Path Parameters

**Route structure:**
```
app/api/
├── posts/
│   ├── route.ts           → /api/posts (GET, POST)
│   └── [id]/
│       └── route.ts       → /api/posts/[id] (GET, PUT, DELETE)
├── users/
│   ├── route.ts           → /api/users (GET, POST)
│   ├── [userId]/
│   │   ├── route.ts       → /api/users/[userId] (GET, PUT, DELETE)
│   │   └── posts/
│   │       └── route.ts   → /api/users/[userId]/posts (GET)
```

**Get by ID:**
```typescript
// app/api/posts/[id]/route.ts
import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params

  const post = await db.posts.findById(id)
  if (!post) {
    return NextResponse.json(
      { error: 'Post not found' },
      { status: 404 }
    )
  }

  return NextResponse.json(post)
}
```

**Multiple path segments:**
```typescript
// app/api/users/[userId]/posts/[postId]/route.ts
export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ userId: string; postId: string }> }
) {
  const { userId, postId } = await params

  const post = await db.posts.findById(postId)
  if (!post || post.userId !== userId) {
    return NextResponse.json(
      { error: 'Post not found' },
      { status: 404 }
    )
  }

  return NextResponse.json(post)
}
```

### 3. PUT and DELETE Operations

**Update (PUT):**
```typescript
// app/api/posts/[id]/route.ts
export async function PUT(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params
  const body = await request.json()

  // Validate update fields
  const allowed = ['title', 'content', 'published']
  const updates = Object.keys(body)
    .filter(key => allowed.includes(key))
    .reduce((obj, key) => {
      obj[key] = body[key]
      return obj
    }, {} as Record<string, any>)

  const post = await db.posts.update(id, updates)
  return NextResponse.json(post)
}
```

**Delete (DELETE):**
```typescript
export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params

  await db.posts.delete(id)
  return NextResponse.json(
    { message: 'Post deleted' },
    { status: 204 }
  )
}
```

**Partial Update (PATCH):**
```typescript
export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params
  const body = await request.json()

  const post = await db.posts.findById(id)
  if (!post) {
    return NextResponse.json(
      { error: 'Not found' },
      { status: 404 }
    )
  }

  // Merge with existing data
  const updated = await db.posts.update(id, {
    ...post,
    ...body,
  })

  return NextResponse.json(updated)
}
```

### 4. Request Handling (Headers, Cookies, Body)

**Extract headers:**
```typescript
export async function POST(request: NextRequest) {
  const contentType = request.headers.get('content-type')
  const authorization = request.headers.get('authorization')
  const userAgent = request.headers.get('user-agent')

  // Validate auth
  if (!authorization?.startsWith('Bearer ')) {
    return NextResponse.json(
      { error: 'Unauthorized' },
      { status: 401 }
    )
  }

  const token = authorization.slice(7)
  // verify token...

  return NextResponse.json({ success: true })
}
```

**Parse different body types:**
```typescript
export async function POST(request: NextRequest) {
  const contentType = request.headers.get('content-type')

  if (contentType?.includes('application/json')) {
    const body = await request.json()
    // handle JSON
  } else if (contentType?.includes('application/x-www-form-urlencoded')) {
    const body = await request.formData()
    // handle form data
  } else if (contentType?.includes('multipart/form-data')) {
    const formData = await request.formData()
    const file = formData.get('file') as File
    // handle file upload
  } else {
    const text = await request.text()
    // handle text/plain
  }
}
```

**Cookies:**
```typescript
import { cookies } from 'next/headers'

export async function POST(request: NextRequest) {
  const cookieStore = await cookies()

  // Read cookies
  const sessionId = cookieStore.get('sessionId')?.value

  // Set cookies in response
  const response = NextResponse.json({ success: true })
  response.cookies.set('sessionId', 'new-session-123', {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'strict',
    maxAge: 60 * 60 * 24 * 7, // 7 days
  })

  return response
}
```

### 5. Response Handling and Status Codes

**Different status codes:**
```typescript
// 200 OK
return NextResponse.json({ data: item })

// 201 Created
return NextResponse.json(newItem, { status: 201 })

// 204 No Content
return NextResponse.json(null, { status: 204 })

// 400 Bad Request
return NextResponse.json(
  { error: 'Invalid input' },
  { status: 400 }
)

// 401 Unauthorized
return NextResponse.json(
  { error: 'Authentication required' },
  { status: 401 }
)

// 403 Forbidden
return NextResponse.json(
  { error: 'Access denied' },
  { status: 403 }
)

// 404 Not Found
return NextResponse.json(
  { error: 'Resource not found' },
  { status: 404 }
)

// 409 Conflict
return NextResponse.json(
  { error: 'Duplicate entry' },
  { status: 409 }
)

// 500 Server Error
return NextResponse.json(
  { error: 'Internal server error' },
  { status: 500 }
)
```

**Custom headers:**
```typescript
export async function GET() {
  const response = NextResponse.json({ data: [] })

  response.headers.set('X-Custom-Header', 'value')
  response.headers.set('Cache-Control', 'public, max-age=3600')
  response.headers.set('X-Correlation-ID', crypto.randomUUID())

  return response
}
```

### 6. Validation and Error Handling

**Input validation:**
```typescript
import { z } from 'zod'

const PostSchema = z.object({
  title: z.string().min(1).max(200),
  content: z.string().min(1),
  published: z.boolean().optional(),
})

export async function POST(request: NextRequest) {
  try {
    const body = await request.json()
    const validated = PostSchema.parse(body)

    const post = await db.posts.create(validated)
    return NextResponse.json(post, { status: 201 })
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json(
        { error: 'Validation failed', details: error.errors },
        { status: 400 }
      )
    }

    return NextResponse.json(
      { error: 'Server error' },
      { status: 500 }
    )
  }
}
```

**Error handling with logging:**
```typescript
import { logger } from '@/lib/logger'

export async function POST(request: NextRequest) {
  try {
    const body = await request.json()
    return NextResponse.json(await db.posts.create(body), { status: 201 })
  } catch (error) {
    const correlationId = request.headers.get('x-correlation-id')

    logger.error('POST /api/posts failed', {
      error: error instanceof Error ? error.message : String(error),
      correlationId,
      timestamp: new Date().toISOString(),
    })

    return NextResponse.json(
      { error: 'Failed to create post', correlationId },
      { status: 500 }
    )
  }
}
```

## When to Use

**GET**
- Retrieve single resource by ID
- List resources with filtering/pagination
- No side effects

**POST**
- Create new resource
- Accept form submissions
- Status 201 for created resources

**PUT**
- Update entire resource (replace all fields)
- Idempotent (same result on retry)
- Validate all required fields

**PATCH**
- Partial update (only provided fields)
- Merge with existing data
- More flexible than PUT

**DELETE**
- Remove resource permanently
- Status 204 (no content) on success
- Soft delete: mark as deleted but retain data

## Anti-Patterns

❌ **Not validating input**
```typescript
// ❌ No validation - could be any data
export async function POST(request: NextRequest) {
  const body = await request.json()
  await db.posts.create(body)  // What if body is malicious?
}
```

✓ **Validate before processing**
```typescript
// ✓ Validate with Zod
const schema = z.object({ title: z.string(), content: z.string() })
const validated = schema.parse(body)
await db.posts.create(validated)
```

❌ **Exposing sensitive data in response**
```typescript
// ❌ Password exposed
export async function GET() {
  const users = await db.users.findAll()
  return NextResponse.json(users)  // includes password hash!
}
```

✓ **Filter sensitive fields**
```typescript
// ✓ Only return safe fields
export async function GET() {
  const users = await db.users.findAll()
  return NextResponse.json(
    users.map(({ password, ...user }) => user)
  )
}
```

❌ **Not handling errors**
```typescript
// ❌ Unhandled error crashes server
export async function POST(request: NextRequest) {
  const body = await request.json()
  await db.posts.create(body)
  return NextResponse.json({ success: true })
}
```

✓ **Catch and log errors**
```typescript
// ✓ Proper error handling
export async function POST(request: NextRequest) {
  try {
    const body = await request.json()
    await db.posts.create(body)
    return NextResponse.json({ success: true }, { status: 201 })
  } catch (error) {
    logger.error('Creation failed', { error })
    return NextResponse.json(
      { error: 'Failed to create' },
      { status: 500 }
    )
  }
}
```

❌ **Wrong status code**
```typescript
// ❌ Returns 200 for created resource
export async function POST(request: NextRequest) {
  const post = await db.posts.create(await request.json())
  return NextResponse.json(post)  // Should be 201
}
```

✓ **Use correct status codes**
```typescript
// ✓ Returns 201 Created
export async function POST(request: NextRequest) {
  const post = await db.posts.create(await request.json())
  return NextResponse.json(post, { status: 201 })
}
```

## Testing API Routes

```typescript
describe('POST /api/posts', () => {
  it('should create post with valid input', async () => {
    const response = await fetch('/api/posts', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        title: 'Test Post',
        content: 'Test content',
      }),
    })

    expect(response.status).toBe(201)
    const data = await response.json()
    expect(data).toHaveProperty('id')
    expect(data.title).toBe('Test Post')
  })

  it('should reject missing required fields', async () => {
    const response = await fetch('/api/posts', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title: 'No content' }),
    })

    expect(response.status).toBe(400)
  })
})

describe('GET /api/posts/[id]', () => {
  it('should return 404 for non-existent post', async () => {
    const response = await fetch('/api/posts/invalid-id')
    expect(response.status).toBe(404)
  })
})

describe('DELETE /api/posts/[id]', () => {
  it('should delete post and return 204', async () => {
    // Create post
    const createRes = await fetch('/api/posts', {
      method: 'POST',
      body: JSON.stringify({ title: 'Delete me', content: 'Test' }),
    })
    const { id } = await createRes.json()

    // Delete post
    const deleteRes = await fetch(`/api/posts/${id}`, {
      method: 'DELETE',
    })

    expect(deleteRes.status).toBe(204)
  })
})
```

## Token Cost

- Invocation: 100 tokens
- Quick pattern: 100-150 tokens
- Detailed patterns (6 sections): 500-700 tokens
- Request/response handling: 250-350 tokens
- Validation/error handling: 200-300 tokens
- Status codes guide: 150-200 tokens
- Anti-patterns: 200-300 tokens
- Testing examples: 150-200 tokens
- **Total:** 1250-1900 tokens per invocation

## When to Lookup Context7

- Advanced streaming responses (ReadableStream)
- Web API Request/Response with custom protocols
- Multipart form data parsing edge cases
- Next.js middleware and request interceptors
- Performance optimization for large payloads
- Rate limiting and throttling strategies
