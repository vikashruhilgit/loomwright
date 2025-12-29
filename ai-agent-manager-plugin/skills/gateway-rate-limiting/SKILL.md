---
name: gateway-rate-limiting
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

## Token Cost

- Pattern: 150-200 tokens
- Context7 (if needed): 1000-1500 tokens
