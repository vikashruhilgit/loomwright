# Gateway Rate Limiting Skill

Implement request rate limiting to prevent abuse and ensure fair resource usage.

## Quick Pattern

```typescript
import { Injectable } from '@nestjs/common';
import { ThrottlerGuard, Throttle } from '@nestjs/throttler';

// Per-endpoint rate limiting
@Controller('auth')
export class AuthController {
  @Post('sign-in')
  @Throttle({ default: { limit: 5, ttl: 60000 } }) // 5 requests/minute
  async signIn(@Body() dto: SignInDTO) {
    return this.authService.signIn(dto);
  }

  @Post('refresh-token')
  @Throttle({ default: { limit: 10, ttl: 60000 } }) // 10 requests/minute
  async refreshToken(@Body() dto: RefreshTokenDTO) {
    return this.authService.refreshToken(dto);
  }
}

// Global rate limiting (in app.module.ts)
@Module({
  imports: [
    ThrottlerModule.forRoot([
      {
        ttl: 60000,
        limit: 100, // 100 requests per minute globally
      },
    ]),
  ],
  providers: [
    {
      provide: APP_GUARD,
      useClass: ThrottlerGuard,
    },
  ],
})
export class AppModule { }
```

## Patterns

### 1. Basic Rate Limiting

**When:** Simple request limits per time window

```typescript
import { Throttle } from '@nestjs/throttler';

@Controller('api')
export class ApiController {
  // 100 requests per 15 minutes (900,000ms)
  @Get('data')
  @Throttle({ default: { limit: 100, ttl: 900000 } })
  getData() {
    return { data: 'value' };
  }

  // 10 requests per second for expensive operation
  @Post('process')
  @Throttle({ default: { limit: 10, ttl: 1000 } })
  processData(@Body() dto: any) {
    return { status: 'processing' };
  }
}
```

### 2. Per-User Rate Limiting

**When:** Different limits for authenticated vs anonymous users

```typescript
import { Injectable } from '@nestjs/common';
import { ThrottlerGuard } from '@nestjs/throttler';

@Injectable()
export class CustomThrottlerGuard extends ThrottlerGuard {
  protected getTracker(req: Request): string {
    // Use user ID if authenticated, otherwise use IP
    return req['user']?.id || req.ip;
  }
}

// In app.module.ts
@Module({
  imports: [
    ThrottlerModule.forRoot([
      {
        name: 'anonymous',
        ttl: 60000,
        limit: 10, // Anonymous: 10 req/min
      },
      {
        name: 'authenticated',
        ttl: 60000,
        limit: 100, // Authenticated: 100 req/min
      },
    ]),
  ],
  providers: [
    {
      provide: APP_GUARD,
      useClass: CustomThrottlerGuard,
    },
  ],
})
export class AppModule { }

// Usage
@Controller('api')
export class ApiController {
  @Get('data')
  @Throttle({ anonymous: { limit: 10, ttl: 60000 }, authenticated: { limit: 100, ttl: 60000 } })
  getData() { }
}
```

### 3. Tiered Rate Limiting

**When:** Different limits based on subscription/role

```typescript
@Injectable()
export class TieredThrottlerGuard extends ThrottlerGuard {
  protected getTracker(req: Request): string {
    const user = req['user'];
    if (!user) return req.ip; // Anonymous

    // Return different tracker for different tiers
    return `${user.id}:${user.tier}`;
  }

  protected getLimit(req: Request): number {
    const user = req['user'];
    if (!user) return 10; // Anonymous: 10 req/min

    switch (user.tier) {
      case 'free':
        return 50;
      case 'premium':
        return 500;
      case 'enterprise':
        return 5000;
      default:
        return 50;
    }
  }
}

// Configure in app.module.ts
@Module({
  providers: [
    {
      provide: APP_GUARD,
      useClass: TieredThrottlerGuard,
    },
  ],
})
export class AppModule { }
```

### 4. Redis-Based Rate Limiting (Distributed)

**When:** Rate limiting across multiple server instances

```typescript
import { createClient } from 'redis';
import { RedisStore } from '@nestjs/throttler';

@Module({
  imports: [
    ThrottlerModule.forRootAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: async (configService: ConfigService) => {
        const client = createClient({
          host: configService.get('REDIS_HOST'),
          port: configService.get('REDIS_PORT'),
        });

        await client.connect();

        return {
          throttlers: [
            {
              ttl: 60000,
              limit: 100,
            },
          ],
          storage: new RedisStore(client),
        };
      },
    }),
  ],
  providers: [
    {
      provide: APP_GUARD,
      useClass: ThrottlerGuard,
    },
  ],
})
export class AppModule { }
```

### 5. Custom Rate Limit Response

**When:** Return custom error message or retry-after header

```typescript
@Injectable()
export class CustomThrottlerGuard extends ThrottlerGuard {
  async handleRequest(
    context: ExecutionContext,
    limit: number,
    ttl: number,
  ): Promise<boolean> {
    const { req, res } = this.getRequestResponse(context);
    const tracker = this.getTracker(req);
    const key = `${this.throttlerName}:${tracker}`;

    const { totalHits, resetTime } = await this.throttlerStorage.increment(
      key,
      ttl,
    );

    if (totalHits > limit) {
      res.header('Retry-After', Math.ceil(resetTime / 1000));
      throw new HttpException(
        {
          statusCode: 429,
          message: 'Too many requests',
          retryAfter: Math.ceil(resetTime / 1000),
        },
        429,
      );
    }

    res.header('X-RateLimit-Limit', limit);
    res.header('X-RateLimit-Remaining', limit - totalHits);
    res.header('X-RateLimit-Reset', Math.ceil(resetTime / 1000));

    return true;
  }
}
```

### 6. Endpoint-Specific Strategies

**When:** Different strategies for different endpoint categories

```typescript
@Controller('auth')
export class AuthController {
  // Sensitive: very restrictive
  @Post('sign-in')
  @Throttle({ default: { limit: 5, ttl: 60000 } })
  async signIn() { }

  // Less sensitive: moderate
  @Get('profile')
  @Throttle({ default: { limit: 30, ttl: 60000 } })
  async getProfile() { }

  // Read-only: permissive
  @Get('health')
  @Throttle({ default: { limit: 1000, ttl: 60000 } })
  async health() { }
}

@Controller('api')
export class ApiController {
  // Data download: very restrictive
  @Get('export')
  @Throttle({ default: { limit: 2, ttl: 3600000 } }) // 2 per hour
  async exportData() { }

  // API calls: moderate
  @Get('data')
  @Throttle({ default: { limit: 100, ttl: 60000 } })
  async getData() { }

  // WebSocket: higher limit
  @WebSocketGateway()
  @Throttle({ default: { limit: 500, ttl: 60000 } })
  export class EventsGateway { }
}
```

### 7. Graceful Degradation

**When:** Allow requests exceeding limit but mark them as degraded

```typescript
@Injectable()
export class GracefulThrottlerGuard extends ThrottlerGuard {
  async handleRequest(
    context: ExecutionContext,
    limit: number,
    ttl: number,
  ): Promise<boolean> {
    const { req, res } = this.getRequestResponse(context);
    const tracker = this.getTracker(req);
    const key = `${this.throttlerName}:${tracker}`;

    const { totalHits, resetTime } = await this.throttlerStorage.increment(
      key,
      ttl,
    );

    if (totalHits > limit && totalHits <= limit * 1.2) {
      // 20% grace period
      res.header('X-RateLimit-Degraded', 'true');
      return true; // Allow but mark as degraded
    }

    if (totalHits > limit * 1.2) {
      // Strict enforcement after grace period
      throw new HttpException(
        { message: 'Rate limit exceeded' },
        429,
      );
    }

    return true;
  }
}
```

## Monitoring Rate Limits

```typescript
@Injectable()
export class RateLimitMonitoringService {
  constructor(private throttlerStorage: ThrottlerStorage) {}

  async getStats(tracker: string) {
    // Retrieve current rate limit stats
    const stats = await this.throttlerStorage.getRecord(tracker);
    return {
      tracker,
      hits: stats.totalHits,
      resetTime: stats.resetTime,
    };
  }

  async getAllTrackers() {
    // Get all tracked users/IPs
    return this.throttlerStorage.getKeys();
  }
}
```

## Common Limits

| Endpoint | Anonymous | Authenticated |
|----------|-----------|---------------|
| Sign-in | 5/min | N/A |
| List resources | 20/min | 100/min |
| Create resource | 5/min | 30/min |
| Update resource | 10/min | 100/min |
| Delete resource | 2/min | 10/min |
| Export data | 1/hour | 5/hour |

## Testing Rate Limiting

```typescript
describe('Rate Limiting', () => {
  let app: INestApplication;

  beforeEach(async () => {
    const moduleFixture = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    await app.init();
  });

  it('should enforce rate limit', async () => {
    const limit = 5;

    for (let i = 0; i < limit; i++) {
      await request(app.getHttpServer())
        .get('/api/data')
        .expect(200);
    }

    // Should exceed limit on next request
    await request(app.getHttpServer())
      .get('/api/data')
      .expect(429);
  });

  it('should reset limit after TTL', async () => {
    await request(app.getHttpServer())
      .get('/api/data')
      .expect(200);

    // Wait for TTL
    await new Promise(resolve => setTimeout(resolve, 61000));

    // Should be allowed again
    await request(app.getHttpServer())
      .get('/api/data')
      .expect(200);
  });
});
```

## Anti-Patterns

❌ Same limit for all endpoints
```typescript
// All endpoints get 100 req/min
@Module({
  imports: [
    ThrottlerModule.forRoot([
      { ttl: 60000, limit: 100 }
    ]),
  ],
})
```

✓ Endpoint-specific limits
```typescript
// Sensitive endpoints: lower limits
@Post('sign-in')
@Throttle({ default: { limit: 5, ttl: 60000 } })

// Public endpoints: higher limits
@Get('health')
@Throttle({ default: { limit: 1000, ttl: 60000 } })
```

❌ No monitoring or alerting
```typescript
// Rate limiting enabled but no visibility
```

✓ Monitor and alert
```typescript
const remaining = limit - totalHits;
if (remaining < 10) {
  this.logger.warn(`User near rate limit: ${remaining} requests left`);
}
```

## Token Cost

- Invocation: 100 tokens
- Pattern: 150-200 tokens
- Context7 (if needed): 1000-1500 tokens
- **Total:** 250-1900 tokens

## When to Lookup Context7

- Token bucket algorithms
- Sliding window implementations
- Distributed rate limiting strategies
- Advanced backpressure mechanisms
