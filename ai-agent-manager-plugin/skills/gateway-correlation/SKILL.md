---
name: gateway-correlation
description: Implement request correlation IDs for tracing across microservices. Use when implementing request tracing, logging, or distributed system debugging.
---

# Gateway Correlation ID Skill

Implement request correlation IDs for tracing across microservices.

## Quick Pattern

```typescript
import { Injectable, NestMiddleware } from '@nestjs/common';
import { v4 as uuidv4 } from 'uuid';

@Injectable()
export class CorrelationIdMiddleware implements NestMiddleware {
  use(req: Request, res: Response, next: NextFunction) {
    const correlationId =
      req.headers['x-correlation-id'] ||
      uuidv4();

    req.correlationId = correlationId;
    res.setHeader('X-Correlation-ID', correlationId);
    next();
  }
}
```

## When to Use

- Correlation ID extraction/generation
- Propagating correlation ID to microservices
- Logging with correlation ID
- Correlation ID in request context
- Error responses with correlation ID

## Token Cost

- Pattern: 150-200 tokens
- Context7 (if needed): 1000-1500 tokens
