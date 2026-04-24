---
name: gateway-proxy-patterns
version: "1.0.0"
lastUpdated: "2026-03"
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

## Circuit Breaker Implementation

Prevent cascading failures by tracking error rates and opening the circuit:

```typescript
// lib/circuit-breaker.ts
enum CircuitState {
  CLOSED = 'CLOSED',     // Normal operation
  OPEN = 'OPEN',         // Failing, reject requests
  HALF_OPEN = 'HALF_OPEN', // Testing recovery
}

export class CircuitBreaker {
  private state = CircuitState.CLOSED;
  private failureCount = 0;
  private lastFailureTime = 0;
  private successCount = 0;

  constructor(
    private readonly options = {
      failureThreshold: 5,
      resetTimeoutMs: 30000,
      halfOpenMaxAttempts: 3,
    },
  ) {}

  async execute<T>(fn: () => Promise<T>): Promise<T> {
    if (this.state === CircuitState.OPEN) {
      if (Date.now() - this.lastFailureTime > this.options.resetTimeoutMs) {
        this.state = CircuitState.HALF_OPEN;
        this.successCount = 0;
      } else {
        throw new ServiceUnavailableException('Circuit breaker is OPEN');
      }
    }

    try {
      const result = await fn();

      if (this.state === CircuitState.HALF_OPEN) {
        this.successCount++;
        if (this.successCount >= this.options.halfOpenMaxAttempts) {
          this.state = CircuitState.CLOSED;
          this.failureCount = 0;
        }
      }

      return result;
    } catch (error) {
      this.failureCount++;
      this.lastFailureTime = Date.now();

      if (this.failureCount >= this.options.failureThreshold) {
        this.state = CircuitState.OPEN;
      }

      throw error;
    }
  }

  getState(): CircuitState {
    return this.state;
  }
}

// Usage in proxy service
@Injectable()
export class ProxyService {
  private breakers = new Map<string, CircuitBreaker>();

  private getBreaker(service: string): CircuitBreaker {
    if (!this.breakers.has(service)) {
      this.breakers.set(service, new CircuitBreaker());
    }
    return this.breakers.get(service)!;
  }

  async forward(service: string, config: AxiosRequestConfig) {
    const breaker = this.getBreaker(service);
    return breaker.execute(() => this.httpService.axiosRef(config));
  }
}
```

## Retry with Exponential Backoff

Retry transient failures with increasing delays:

```typescript
// lib/retry.ts
export interface RetryOptions {
  maxRetries: number;
  baseDelayMs: number;
  maxDelayMs: number;
  retryableStatuses: number[];
}

const DEFAULT_RETRY: RetryOptions = {
  maxRetries: 3,
  baseDelayMs: 200,
  maxDelayMs: 5000,
  retryableStatuses: [502, 503, 504, 429],
};

export async function withRetry<T>(
  fn: () => Promise<T>,
  options: Partial<RetryOptions> = {},
): Promise<T> {
  const opts = { ...DEFAULT_RETRY, ...options };

  for (let attempt = 0; attempt <= opts.maxRetries; attempt++) {
    try {
      return await fn();
    } catch (error) {
      const status = error.response?.status;
      const isRetryable = opts.retryableStatuses.includes(status);
      const isLastAttempt = attempt === opts.maxRetries;

      if (!isRetryable || isLastAttempt) throw error;

      // Exponential backoff with jitter
      const delay = Math.min(
        opts.baseDelayMs * Math.pow(2, attempt) + Math.random() * 100,
        opts.maxDelayMs,
      );

      await new Promise((resolve) => setTimeout(resolve, delay));
    }
  }

  throw new Error('Retry exhausted'); // unreachable
}

// Usage
const response = await withRetry(
  () => this.httpService.axiosRef.get(`http://orders-svc/api/orders/${id}`),
  { maxRetries: 3, baseDelayMs: 300 },
);
```

## Timeout Patterns with AbortController

Cancel long-running upstream requests to prevent resource exhaustion:

```typescript
// lib/timeout-fetch.ts
export async function fetchWithTimeout(
  url: string,
  options: RequestInit & { timeoutMs?: number } = {},
): Promise<Response> {
  const { timeoutMs = 5000, ...fetchOptions } = options;
  const controller = new AbortController();

  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch(url, {
      ...fetchOptions,
      signal: controller.signal,
    });
    return response;
  } catch (error) {
    if (error.name === 'AbortError') {
      throw new GatewayTimeoutException(`Upstream request to ${url} timed out after ${timeoutMs}ms`);
    }
    throw error;
  } finally {
    clearTimeout(timeoutId);
  }
}

// Proxy controller with per-route timeouts
@Controller()
export class GatewayController {
  @All('api/orders/*')
  async proxyOrders(@Req() req: Request) {
    const response = await fetchWithTimeout(
      `http://orders-svc${req.url}`,
      {
        method: req.method,
        headers: this.forwardHeaders(req),
        body: ['GET', 'HEAD'].includes(req.method) ? undefined : JSON.stringify(req.body),
        timeoutMs: 10000, // Orders service gets 10s
      },
    );
    return response.json();
  }

  @All('api/search/*')
  async proxySearch(@Req() req: Request) {
    const response = await fetchWithTimeout(
      `http://search-svc${req.url}`,
      { method: req.method, timeoutMs: 3000 }, // Search gets 3s
    );
    return response.json();
  }
}
```

## Token Cost

- Pattern: 150-250 tokens
- Context7 (if needed): 1000-1500 tokens
