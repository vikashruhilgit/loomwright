---
name: redis-caching
description: Redis caching patterns including cache-aside, write-through, invalidation strategies, session storage, and pub/sub. Use when implementing caching or reviewing cache logic.
allowed-tools: [Read]
version: "1.0.0"
lastUpdated: "2026-03"
---

# Redis Caching

Patterns for effective caching, session management, and pub/sub with Redis.

---

## When to Use

- Adding caching to reduce database load or API latency
- Implementing session storage
- Setting up pub/sub for real-time features
- Reviewing cache invalidation logic

## When NOT to Use

- Persistent data storage — Redis is a cache, not a primary database
- Complex queries or joins — use `mysql` or `postgresql`
- Message queuing with delivery guarantees — use a dedicated queue (RabbitMQ, SQS)

## Core Patterns

### 1. Cache-Aside (Lazy Loading)

The most common pattern — read from cache first, fall back to database:

```typescript
// src/services/user-cache.service.ts
@Injectable()
export class UserCacheService {
  private readonly TTL_SECONDS = 300; // 5 minutes

  constructor(
    private readonly redis: Redis,
    private readonly userRepo: UserRepository,
  ) {}

  async findById(id: string): Promise<User | null> {
    const cacheKey = `user:${id}`;

    // 1. Check cache
    const cached = await this.redis.get(cacheKey);
    if (cached) return JSON.parse(cached);

    // 2. Cache miss — fetch from DB
    const user = await this.userRepo.findOne({ where: { id } });
    if (!user) return null;

    // 3. Populate cache
    await this.redis.set(cacheKey, JSON.stringify(user), 'EX', this.TTL_SECONDS);
    return user;
  }

  async invalidate(id: string): Promise<void> {
    await this.redis.del(`user:${id}`);
  }
}
```

### 2. Write-Through

Update cache and database together — keeps cache always fresh:

```typescript
async update(id: string, data: UpdateUserDto): Promise<User> {
  // 1. Update database
  const user = await this.userRepo.save({ id, ...data });

  // 2. Update cache immediately
  const cacheKey = `user:${id}`;
  await this.redis.set(cacheKey, JSON.stringify(user), 'EX', this.TTL_SECONDS);

  return user;
}
```

### 3. TTL Strategy

| Data Type | TTL | Rationale |
|-----------|-----|-----------|
| User profile | 5 min | Changes infrequently, tolerate slight staleness |
| Product listing | 1 min | Prices/stock may change |
| Configuration | 15 min | Rarely changes, expensive to compute |
| Session | 24 hours | Match session expiry policy |
| Rate limit counter | 60 sec | Window-based, auto-expires |

### 4. Cache Invalidation Patterns

```typescript
// Pattern A: Delete on write (simplest)
async updateUser(id: string, data: UpdateUserDto): Promise<User> {
  const user = await this.userRepo.save({ id, ...data });
  await this.redis.del(`user:${id}`);
  return user;
}

// Pattern B: Tag-based invalidation (for collections)
async invalidateUserListings(userId: string): Promise<void> {
  const keys = await this.redis.smembers(`tag:user:${userId}:listings`);
  if (keys.length > 0) {
    await this.redis.del(...keys);
    await this.redis.del(`tag:user:${userId}:listings`);
  }
}

// Pattern C: Versioned keys (avoid thundering herd)
async getWithVersion(key: string, version: number): Promise<string | null> {
  return this.redis.get(`${key}:v${version}`);
}
```

### 5. Session Store

```typescript
// NestJS with express-session and connect-redis
import RedisStore from 'connect-redis';

app.use(session({
  store: new RedisStore({
    client: redisClient,
    prefix: 'sess:',
    ttl: 86400, // 24 hours
  }),
  secret: process.env.SESSION_SECRET,
  resave: false,
  saveUninitialized: false,
  cookie: {
    secure: process.env.NODE_ENV === 'production',
    httpOnly: true,
    maxAge: 86400000,
    sameSite: 'lax',
  },
}));
```

### 6. Pub/Sub for Real-Time

```typescript
// Publisher
await redis.publish('user:updated', JSON.stringify({ userId, changes }));

// Subscriber (separate connection required)
const subscriber = redis.duplicate();
await subscriber.subscribe('user:updated', (message) => {
  const { userId, changes } = JSON.parse(message);
  // Invalidate local in-memory cache, push WebSocket update, etc.
});
```

## Example Implementation

A cache decorator that wraps any service method with cache-aside logic:

```typescript
// src/common/decorators/cacheable.ts
export function Cacheable(prefix: string, ttlSeconds = 300) {
  return function (_target: object, _key: string, descriptor: PropertyDescriptor) {
    const original = descriptor.value;

    descriptor.value = async function (this: { redis: Redis }, ...args: unknown[]) {
      const cacheKey = `${prefix}:${JSON.stringify(args)}`;
      const cached = await this.redis.get(cacheKey);
      if (cached) return JSON.parse(cached);

      const result = await original.apply(this, args);
      if (result != null) {
        await this.redis.set(cacheKey, JSON.stringify(result), 'EX', ttlSeconds);
      }
      return result;
    };
    return descriptor;
  };
}

// Usage
@Cacheable('product', 60)
async findById(id: string): Promise<Product | null> {
  return this.productRepo.findOne({ where: { id } });
}
```

## Testing Approach

- Test cache-aside by mocking Redis `get`/`set` — verify DB is called on miss and skipped on hit
- Test invalidation by calling the write path and asserting `redis.del` was called with the correct key
- Test TTL by verifying `redis.set` is called with the expected `EX` argument
- Test graceful degradation when Redis is unavailable by mocking a connection error and verifying the service falls back to the database

## Anti-Patterns

- **Caching without TTL:** Every key must have an expiry. Unbounded caches grow until OOM.
- **Cache-aside without invalidation on write:** Stale data persists until TTL expires.
- **Storing large objects:** Keep cached values small (< 1MB). Serialize only needed fields.
- **Single Redis connection for pub/sub:** Subscribers block the connection. Use a dedicated client.
- **Ignoring cache stampede:** When a popular key expires, many requests hit the DB simultaneously. Use locking or staggered TTLs.

## Connection Configuration

```typescript
import Redis from 'ioredis';

const redis = new Redis({
  host: process.env.REDIS_HOST ?? 'localhost',
  port: parseInt(process.env.REDIS_PORT ?? '6379'),
  password: process.env.REDIS_PASSWORD,
  maxRetriesPerRequest: 3,
  retryStrategy: (times) => Math.min(times * 200, 5000),
  enableReadyCheck: true,
  lazyConnect: false,
});
```

## Related Skills

- `mysql` / `postgresql` — Primary data store that cache sits in front of
- `error-handling` — Graceful degradation when Redis is unavailable
- `docker` — Redis container setup in docker-compose
- `monitoring-observability` — Cache hit/miss ratio metrics

## Quality Gates

- [ ] Every cache key has a TTL
- [ ] Cache invalidation occurs on every write path
- [ ] Key naming is consistent: `{entity}:{id}` or `{entity}:{id}:{field}`
- [ ] Connection has retry strategy and error handling
- [ ] No sensitive data cached without encryption consideration
- [ ] Pub/sub uses dedicated Redis connection
- [ ] Cache hit/miss ratio is tracked as a metric
