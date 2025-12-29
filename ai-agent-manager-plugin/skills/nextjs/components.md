# Next.js App Router Components Skill

Implement Server and Client components with proper boundaries, Suspense, and state management.

## Quick Pattern

```typescript
// Server Component (default, async allowed)
export default async function UserProfile({ userId }: { userId: string }) {
  const user = await db.users.findById(userId)
  return <div>{user.name}</div>
}

// Client Component (interactive, hooks)
'use client'
import { useState } from 'react'

export function Counter() {
  const [count, setCount] = useState(0)
  return <button onClick={() => setCount(count + 1)}>{count}</button>
}

// Suspense boundary for async loading
import { Suspense } from 'react'

export default function Page() {
  return (
    <Suspense fallback={<div>Loading...</div>}>
      <UserProfile userId="123" />
    </Suspense>
  )
}

// Client component with server data (via props)
'use client'
export function InteractiveUser({ user }: { user: User }) {
  const [liked, setLiked] = useState(false)
  return (
    <div>
      <p>{user.name}</p>
      <button onClick={() => setLiked(!liked)}>
        {liked ? '❤️' : '🤍'} Like
      </button>
    </div>
  )
}

// Server component passes data to client component
import { InteractiveUser } from './interactive-user'

export default async function UserPage() {
  const user = await fetchUser()
  return <InteractiveUser user={user} />
}
```

## Patterns

### 1. Server Components (Default)

**Characteristics:**
- Default in App Router (no `'use client'`)
- Can use async/await directly
- Direct database access (no API layer needed)
- No JavaScript sent to browser
- Perfect for: data fetching, secrets, computations

```typescript
// app/products/page.tsx - Server component
import { db } from '@/lib/db'

export default async function ProductsPage() {
  const products = await db.products.findAll()

  return (
    <div>
      {products.map(product => (
        <div key={product.id}>
          <h3>{product.name}</h3>
          <p>${product.price}</p>
        </div>
      ))}
    </div>
  )
}

// Avoid: This won't work (no hooks in server components)
// const [filter, setFilter] = useState('')  // ❌ ERROR

// With dynamic data
export default async function ProfileCard({ userId }: { userId: string }) {
  const user = await db.users.findById(userId)

  if (!user) {
    notFound()  // 404
  }

  return (
    <card>
      <h2>{user.name}</h2>
      <p>{user.bio}</p>
    </card>
  )
}
```

### 2. Client Components

**Characteristics:**
- Marked with `'use client'` directive
- Can use hooks (useState, useEffect, useContext)
- Run in browser (JavaScript included)
- No direct database access
- Perfect for: interactive features, forms, animations

```typescript
// app/components/like-button.tsx - Client component
'use client'
import { useState } from 'react'

export function LikeButton({ postId }: { postId: string }) {
  const [isLiked, setIsLiked] = useState(false)
  const [count, setCount] = useState(0)

  const handleLike = async () => {
    if (isLiked) {
      await fetch(`/api/posts/${postId}/like`, { method: 'DELETE' })
      setCount(count - 1)
    } else {
      await fetch(`/api/posts/${postId}/like`, { method: 'POST' })
      setCount(count + 1)
    }
    setIsLiked(!isLiked)
  }

  return (
    <button onClick={handleLike} className={isLiked ? 'liked' : ''}>
      {isLiked ? '❤️' : '🤍'} {count}
    </button>
  )
}

// app/components/search-filter.tsx
'use client'
import { useState } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'

export function SearchFilter() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const [query, setQuery] = useState(searchParams.get('q') || '')

  const handleSearch = (e: React.ChangeEvent<HTMLInputElement>) => {
    const newQuery = e.target.value
    setQuery(newQuery)

    if (newQuery) {
      router.push(`?q=${encodeURIComponent(newQuery)}`)
    } else {
      router.push('?')
    }
  }

  return <input value={query} onChange={handleSearch} placeholder="Search..." />
}
```

### 3. Suspense Boundaries

**Pattern:** Wrap async components with Suspense fallback

```typescript
// app/dashboard/page.tsx
import { Suspense } from 'react'
import { UserStats } from './user-stats'
import { RecentActivity } from './recent-activity'

export default function DashboardPage() {
  return (
    <div>
      <h1>Dashboard</h1>

      {/* Suspense shows fallback while UserStats loads */}
      <Suspense fallback={<div>Loading stats...</div>}>
        <UserStats />
      </Suspense>

      {/* Separate Suspense boundary for activity */}
      <Suspense fallback={<div>Loading activity...</div>}>
        <RecentActivity />
      </Suspense>
    </div>
  )
}

// app/dashboard/user-stats.tsx (server component)
async function UserStats() {
  const stats = await db.stats.getUserStats()
  return <div>{/* render stats */}</div>
}

// app/dashboard/recent-activity.tsx (server component)
async function RecentActivity() {
  const activity = await db.activity.getRecent()
  return <div>{/* render activity */}</div>
}
```

**Multiple fallbacks for granular control:**
```typescript
<Suspense fallback={<HeaderSkeleton />}>
  <Header />
</Suspense>

<Suspense fallback={<BodySkeleton />}>
  <MainContent />
</Suspense>

<Suspense fallback={<FooterSkeleton />}>
  <Footer />
</Suspense>
```

### 4. Error Boundaries

**Pattern:** Use error.tsx for component-level error handling

```typescript
// app/dashboard/error.tsx
'use client'
import { useEffect } from 'react'

export default function Error({
  error,
  reset,
}: {
  error: Error & { digest?: string }
  reset: () => void
}) {
  useEffect(() => {
    console.error(error)
  }, [error])

  return (
    <div>
      <h2>Something went wrong!</h2>
      <p>{error.message}</p>
      <button onClick={() => reset()}>Try again</button>
    </div>
  )
}

// app/dashboard/page.tsx (throws error that boundary catches)
export default async function DashboardPage() {
  const data = await fetchDashboardData() // throws on error
  return <Dashboard data={data} />
}
```

### 5. Sharing State Between Server and Client

**Pattern:** Server renders data, client adds interactivity via props

```typescript
// app/blog/[slug]/page.tsx (server component)
import { BlogPost as BlogPostClient } from './blog-post-client'
import { db } from '@/lib/db'

export default async function BlogPostPage({
  params: { slug },
}: {
  params: Promise<{ slug: string }>
}) {
  const { slug: postSlug } = await params
  const post = await db.posts.findBySlug(postSlug)

  if (!post) {
    notFound()
  }

  return (
    <article>
      <h1>{post.title}</h1>
      <p>{post.excerpt}</p>

      {/* Pass server data to client component */}
      <BlogPostClient
        postId={post.id}
        initialLikeCount={post.likeCount}
        initialComments={post.comments}
      />
    </article>
  )
}

// app/blog/[slug]/blog-post-client.tsx (client component)
'use client'
import { useState } from 'react'

interface Comment {
  id: string
  author: string
  content: string
}

export function BlogPostClient({
  postId,
  initialLikeCount,
  initialComments,
}: {
  postId: string
  initialLikeCount: number
  initialComments: Comment[]
}) {
  const [likeCount, setLikeCount] = useState(initialLikeCount)
  const [comments, setComments] = useState(initialComments)
  const [newComment, setNewComment] = useState('')

  const handleLike = async () => {
    await fetch(`/api/posts/${postId}/like`, { method: 'POST' })
    setLikeCount(likeCount + 1)
  }

  const handleAddComment = async () => {
    const response = await fetch(`/api/posts/${postId}/comments`, {
      method: 'POST',
      body: JSON.stringify({ content: newComment }),
    })
    const comment = await response.json()
    setComments([...comments, comment])
    setNewComment('')
  }

  return (
    <section>
      <button onClick={handleLike}>❤️ {likeCount}</button>

      <div>
        <h3>Comments ({comments.length})</h3>
        {comments.map(comment => (
          <div key={comment.id}>
            <strong>{comment.author}</strong>
            <p>{comment.content}</p>
          </div>
        ))}
      </div>

      <div>
        <textarea
          value={newComment}
          onChange={e => setNewComment(e.target.value)}
          placeholder="Add a comment..."
        />
        <button onClick={handleAddComment}>Post Comment</button>
      </div>
    </section>
  )
}
```

### 6. Dynamic Imports for Client Code

**Pattern:** Import client code only in client components

```typescript
// app/editor/page.tsx (server component)
import dynamic from 'next/dynamic'

// Import heavy editor library only on client
const RichEditor = dynamic(
  () => import('./rich-editor'),
  { loading: () => <div>Loading editor...</div> }
)

export default function EditorPage() {
  return (
    <div>
      <h1>Rich Text Editor</h1>
      <RichEditor />
    </div>
  )
}

// app/editor/rich-editor.tsx (client component)
'use client'
import { useEditor } from '@tiptap/react'

export default function RichEditor() {
  const editor = useEditor({
    content: '<p>Hello World</p>',
  })

  return <div>{/* editor UI */}</div>
}
```

### 7. Server Actions for Mutations

**Pattern:** Define async functions in server components, call from client

```typescript
// app/posts/create-post.tsx
'use client'
import { createPost } from './actions'
import { useState } from 'react'

export function CreatePostForm() {
  const [isPending, setIsPending] = useState(false)

  const handleSubmit = async (formData: FormData) => {
    setIsPending(true)
    try {
      await createPost(formData)
    } finally {
      setIsPending(false)
    }
  }

  return (
    <form action={handleSubmit}>
      <input type="text" name="title" placeholder="Post title" />
      <textarea name="content" placeholder="Post content" />
      <button type="submit" disabled={isPending}>
        {isPending ? 'Creating...' : 'Create Post'}
      </button>
    </form>
  )
}

// app/posts/actions.ts (server actions)
'use server'
import { db } from '@/lib/db'

export async function createPost(formData: FormData) {
  const title = formData.get('title') as string
  const content = formData.get('content') as string

  const post = await db.posts.create({
    title,
    content,
  })

  return post
}
```

## When to Use

### Server Components
- **Data fetching** - Direct database/API queries
- **Keep secrets safe** - API keys, tokens stay on server
- **Large dependencies** - Use packages without bloating bundle
- **Direct database access** - No need for API endpoints
- **Read operations** - Data display pages, dashboards

### Client Components
- **Interactivity** - Buttons, forms, state changes
- **Hooks** - useState, useEffect, useContext
- **Event listeners** - Click, input, submit handlers
- **Browser APIs** - localStorage, geolocation, camera
- **Real-time updates** - WebSockets, polling

### Suspense
- **Async component loading** - Show skeleton/fallback while loading
- **Progressive enhancement** - Load critical content first
- **Error handling** - Pair with error.tsx boundary

## Anti-Patterns

❌ **Using hooks in server components**
```typescript
// ❌ ERROR - useState not allowed
export default async function Page() {
  const [count, setCount] = useState(0)  // This will crash
  return <div>{count}</div>
}
```

✓ **Move to client component**
```typescript
// ✓ Correct
'use client'
export default function Page() {
  const [count, setCount] = useState(0)
  return <div>{count}</div>
}
```

❌ **Passing functions as props from server to client**
```typescript
// ❌ Functions can't be serialized
export default async function Page() {
  const handleClick = () => console.log('clicked')
  return <ClientComponent onClickHandler={handleClick} />
}
```

✓ **Define handler in client component**
```typescript
// ✓ Correct
export default async function Page() {
  const data = await fetchData()
  return <ClientComponent data={data} />
}

'use client'
export function ClientComponent({ data }: { data: Data }) {
  const handleClick = () => console.log('clicked')
  return <button onClick={handleClick}>{/* */}</button>
}
```

❌ **Mixing database calls in client components**
```typescript
// ❌ Can't access database from browser
'use client'
export function UserList() {
  const [users, setUsers] = useState([])
  useEffect(() => {
    // ❌ db is not available here
    const u = db.users.findAll()
  }, [])
}
```

✓ **Fetch via API endpoint**
```typescript
// ✓ Correct - fetch from API endpoint
'use client'
export function UserList() {
  const [users, setUsers] = useState([])
  useEffect(() => {
    fetch('/api/users')
      .then(r => r.json())
      .then(setUsers)
  }, [])
}
```

❌ **Suspense around non-async components**
```typescript
// ❌ UserProfile is not async, Suspense has nothing to wait for
<Suspense fallback={<div>Loading...</div>}>
  <UserProfile userId="123" />  {/* sync component */}
</Suspense>
```

✓ **Only wrap async server components**
```typescript
// ✓ Correct - UserProfile is async
async function UserProfile({ userId }: { userId: string }) {
  const user = await db.users.findById(userId)
  return <div>{user.name}</div>
}

<Suspense fallback={<div>Loading...</div>}>
  <UserProfile userId="123" />
</Suspense>
```

## Testing Components

```typescript
describe('UserProfile', () => {
  it('should render user name from server', async () => {
    const { default: UserProfile } = await import('@/app/user-profile')
    const user = { id: '1', name: 'Alice' }

    // Mock database
    jest.mock('@/lib/db', () => ({
      users: {
        findById: jest.fn().mockResolvedValue(user),
      },
    }))

    const result = UserProfile({ userId: '1' })
    expect(result).toBeDefined()
  })
})

describe('LikeButton', () => {
  it('should toggle like on click', async () => {
    const { render, screen } = await import('@testing-library/react')
    const { LikeButton } = await import('@/app/components/like-button')

    render(<LikeButton postId="1" />)
    const button = screen.getByText(/like/i)

    expect(button).toHaveTextContent('🤍')
    button.click()

    // After click, should show filled heart
    expect(button).toHaveTextContent('❤️')
  })
})

describe('Suspense', () => {
  it('should show fallback while loading', async () => {
    const { render, screen } = await import('@testing-library/react')
    const { Suspense } = await import('react')

    const SlowComponent = async () => {
      await new Promise(r => setTimeout(r, 100))
      return <div>Loaded</div>
    }

    render(
      <Suspense fallback={<div>Loading...</div>}>
        <SlowComponent />
      </Suspense>
    )

    expect(screen.getByText('Loading...')).toBeInTheDocument()

    await screen.findByText('Loaded')
  })
})
```

## Token Cost

- Invocation: 100 tokens
- Quick pattern: 100-150 tokens
- Detailed patterns (4 sections): 400-600 tokens
- Suspense/Error boundaries: 200-300 tokens
- Server/Client decision matrix: 150-200 tokens
- Anti-patterns section: 200-300 tokens
- Testing examples: 150-200 tokens
- **Total:** 1100-1750 tokens per invocation

## When to Lookup Context7

- Advanced streaming patterns with React 18 features
- Server Component data prefetching strategies
- Optimization for specific Next.js versions (13 vs 14 vs 15 differences)
- Error boundary recovery patterns
- Suspense boundary performance tuning
- Complex server/client composition patterns
