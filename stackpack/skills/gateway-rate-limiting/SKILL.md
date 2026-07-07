---
name: gateway-rate-limiting
version: "1.0.0"
lastUpdated: "2026-03"
description: Implement request rate limiting to prevent abuse and ensure fair resource usage. Use when implementing rate limiting, throttling, or API quota management.
---

# Gateway Rate Limiting Skill

Implement request rate limiting to prevent abuse and ensure fair resource usage.

## Quick Pattern

```typescript
import { Injectable } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';

@Controller('auth')
export class AuthController {
  @Post('sign-in')
  @Throttle({ default: { limit: 5, ttl: 60000 } }) // 5 requests/minute
  async signIn(@Body() dto: SignInDTO) {
    return this.authService.signIn(dto);
  }
}

// Global rate limiting (in app.module.ts)
@Module({
  imports: [
    ThrottlerModule.forRoot([
      { ttl: 60000, limit: 100 }
    ]),
  ],
  providers: [
    { provide: APP_GUARD, useClass: ThrottlerGuard }
  ],
})
export class AppModule { }
```

## When to Use

- Basic rate limiting
- Per-user rate limiting
- Tiered rate limiting (free vs premium)
- Redis-based rate limiting (distributed)
- Custom rate limit response

## Sliding Window vs Token Bucket

Two main rate limiting algorithms with different tradeoffs:

```
┌─────────────────────────────────────────────────────────┐
│ Sliding Window                                          │
│ - Counts requests in a rolling time window              │
│ - Smooth, no burst spikes at window boundaries          │
│ - Higher memory (stores timestamps per request)         │
│ - Best for: API quotas, fair usage enforcement          │
│                                                         │
│ Token Bucket                                            │
│ - Tokens refill at fixed rate, each request costs 1     │
│ - Allows short bursts up to bucket capacity             │
│ - Low memory (just counter + timestamp)                 │
│ - Best for: Bursty traffic, real-time APIs              │
└─────────────────────────────────────────────────────────┘
```

```typescript
// Token bucket implementation
export class TokenBucket {
  private tokens: number;
  private lastRefill: number;

  constructor(
    private readonly capacity: number,   // Max burst size
    private readonly refillRate: number,  // Tokens per second
  ) {
    this.tokens = capacity;
    this.lastRefill = Date.now();
  }

  consume(count = 1): boolean {
    this.refill();
    if (this.tokens >= count) {
      this.tokens -= count;
      return true;
    }
    return false;
  }

  private refill() {
    const now = Date.now();
    const elapsed = (now - this.lastRefill) / 1000;
    this.tokens = Math.min(this.capacity, this.tokens + elapsed * this.refillRate);
    this.lastRefill = now;
  }
}
```

## Per-User Rate Limiting

Apply different limits based on user identity or subscription tier:

```typescript
// guards/user-rate-limit.guard.ts
import { Injectable, CanActivate, ExecutionContext, HttpException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';

interface RateLimitTier {
  limit: number;
  windowSec: number;
}

const TIERS: Record<string, RateLimitTier> = {
  free:       { limit: 100,   windowSec: 3600 },   // 100/hour
  pro:        { limit: 1000,  windowSec: 3600 },   // 1000/hour
  enterprise: { limit: 10000, windowSec: 3600 },   // 10000/hour
};

@Injectable()
export class UserRateLimitGuard implements CanActivate {
  constructor(private readonly rateLimitStore: RateLimitStore) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();
    const userId = request.user?.id || request.ip;
    const tier = request.user?.tier || 'free';
    const config = TIERS[tier] || TIERS.free;

    const key = `rate:${userId}:${Math.floor(Date.now() / (config.windowSec * 1000))}`;
    const current = await this.rateLimitStore.increment(key, config.windowSec);

    const response = context.switchToHttp().getResponse();
    response.setHeader('X-RateLimit-Limit', config.limit);
    response.setHeader('X-RateLimit-Remaining', Math.max(0, config.limit - current));

    if (current > config.limit) {
      throw new HttpException(
        { error: 'Rate limit exceeded', retryAfter: config.windowSec },
        429,
      );
    }

    return true;
  }
}
```

## Redis-Backed Rate Limiting

Use Redis for distributed rate limiting across multiple gateway instances:

```typescript
// stores/redis-rate-limit.store.ts
import { Injectable } from '@nestjs/common';
import { Redis } from 'ioredis';

@Injectable()
export class RedisRateLimitStore {
  constructor(private readonly redis: Redis) {}

  // Sliding window using sorted sets
  async checkSlidingWindow(
    key: string,
    limit: number,
    windowMs: number,
  ): Promise<{ allowed: boolean; remaining: number; resetMs: number }> {
    const now = Date.now();
    const windowStart = now - windowMs;

    const pipeline = this.redis.pipeline();
    pipeline.zremrangebyscore(key, 0, windowStart);  // Remove expired entries
    pipeline.zadd(key, now, `${now}-${Math.random()}`); // Add current request
    pipeline.zcard(key);                               // Count requests in window
    pipeline.pexpire(key, windowMs);                   // Set TTL

    const results = await pipeline.exec();
    const count = results![2][1] as number;

    return {
      allowed: count <= limit,
      remaining: Math.max(0, limit - count),
      resetMs: windowMs,
    };
  }

  // Simple counter with TTL (fixed window)
  async increment(key: string, ttlSec: number): Promise<number> {
    const multi = this.redis.multi();
    multi.incr(key);
    multi.expire(key, ttlSec);
    const results = await multi.exec();
    return results![0][1] as number;
  }
}

// Module setup
@Module({
  providers: [
    {
      provide: RedisRateLimitStore,
      useFactory: () => {
        const redis = new Redis({
          host: process.env.REDIS_HOST || 'localhost',
          port: parseInt(process.env.REDIS_PORT || '6379'),
          keyPrefix: 'ratelimit:',
        });
        return new RedisRateLimitStore(redis);
      },
    },
  ],
  exports: [RedisRateLimitStore],
})
export class RateLimitModule {}
```

## Token Cost

- Pattern: 150-200 tokens
- Context7 (if needed): 1000-1500 tokens
