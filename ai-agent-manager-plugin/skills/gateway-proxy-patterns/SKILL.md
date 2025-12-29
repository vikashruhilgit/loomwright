---
name: gateway-proxy-patterns
description: Implement microservice proxying in API Gateway following gateway patterns. Use when routing requests to backend services, load balancing, or implementing gateway patterns.
---

# Gateway Proxy Patterns Skill

Implement microservice proxying in API Gateway following gateway patterns.

## Quick Pattern

```typescript
import { Controller, All, Req } from '@nestjs/common';
import { HttpService } from '@nestjs/axios';

@Controller()
export class GatewayProxyController {
  constructor(private readonly httpService: HttpService) {}

  @All('api/*')
  async proxy(@Req() request: Request) {
    const targetUrl = `http://service:3000${request.url}`;
    const response = await this.httpService.axiosRef({
      method: request.method,
      url: targetUrl,
      data: request.body,
      headers: this.filterHeaders(request.headers),
    }).toPromise();
    return response.data;
  }

  private filterHeaders(headers: Record<string, any>) {
    const excluded = ['host', 'connection', 'content-length'];
    return Object.fromEntries(
      Object.entries(headers).filter(([key]) => !excluded.includes(key))
    );
  }
}
```

## When to Use

- Service-to-service routing
- Load balancing between service instances
- Request transformation before forwarding
- Response caching
- Circuit breaker pattern

## Token Cost

- Pattern: 150-250 tokens
- Context7 (if needed): 1000-1500 tokens
