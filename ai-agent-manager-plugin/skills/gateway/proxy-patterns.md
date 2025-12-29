# Gateway Proxy Patterns Skill

Implement microservice proxying in API Gateway following gateway patterns.

## Quick Pattern

```typescript
import { Controller, All, Req } from '@nestjs/common';
import { HttpService } from '@nestjs/axios';
import { Request } from 'express';

@Controller()
export class GatewayProxyController {
  constructor(private readonly httpService: HttpService) {}

  @All('api/*')
  async proxy(@Req() request: Request) {
    const target = request.url.replace('/api/', '');
    const targetUrl = `http://${process.env.MICROSERVICE_HOST}:${process.env.MICROSERVICE_PORT}/${target}`;

    try {
      const response = await this.httpService.axiosRef({
        method: request.method as any,
        url: targetUrl,
        data: request.body,
        headers: this.filterHeaders(request.headers),
      }).toPromise();

      return response.data;
    } catch (error) {
      throw new Error(`Proxy failed: ${error.message}`);
    }
  }

  private filterHeaders(headers: Record<string, any>) {
    const excluded = ['host', 'connection', 'content-length'];
    return Object.fromEntries(
      Object.entries(headers).filter(([key]) => !excluded.includes(key))
    );
  }
}
```

## Patterns

### 1. Service-to-Service Routing

**When:** Gateway routes to different microservices based on path

```typescript
@Controller()
export class GatewayController {
  constructor(
    private readonly httpService: HttpService,
    private readonly configService: ConfigService,
  ) {}

  @All('auth/*')
  async authProxy(@Req() request: Request) {
    return this.proxyTo('auth', request);
  }

  @All('users/*')
  async usersProxy(@Req() request: Request) {
    return this.proxyTo('users', request);
  }

  @All('orders/*')
  async ordersProxy(@Req() request: Request) {
    return this.proxyTo('orders', request);
  }

  private async proxyTo(service: string, request: Request) {
    const serviceUrl = this.configService.get(`SERVICES.${service.toUpperCase()}`);
    const targetUrl = `${serviceUrl}${request.url.replace(`/${service}`, '')}`;

    const response = await this.httpService.axiosRef({
      method: request.method as any,
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

### 2. Load Balancing Between Service Instances

**When:** Multiple instances of same service behind gateway

```typescript
@Injectable()
export class LoadBalancerService {
  private currentIndex = 0;
  private instances: string[];

  constructor(private configService: ConfigService) {
    this.instances = this.configService.get('INSTANCES');
  }

  getNextInstance(): string {
    const instance = this.instances[this.currentIndex];
    this.currentIndex = (this.currentIndex + 1) % this.instances.length;
    return instance;
  }
}

@Controller()
export class ProxyController {
  constructor(
    private readonly httpService: HttpService,
    private readonly loadBalancer: LoadBalancerService,
  ) {}

  @All('api/*')
  async proxy(@Req() request: Request) {
    const instance = this.loadBalancer.getNextInstance();
    const targetUrl = `${instance}${request.url}`;

    return this.httpService.axiosRef({
      method: request.method as any,
      url: targetUrl,
      data: request.body,
    }).toPromise();
  }
}
```

### 3. Request Transformation Before Forwarding

**When:** Gateway modifies request before sending to microservice

```typescript
@Injectable()
export class RequestTransformerService {
  transformRequest(request: Request) {
    return {
      method: request.method,
      url: request.url,
      data: request.body,
      headers: {
        ...this.filterHeaders(request.headers),
        'X-User-ID': request.user?.id, // Add user context
        'X-Correlation-ID': request.correlationId, // Add correlation ID
        'X-Request-Path': request.originalUrl,
      },
    };
  }

  private filterHeaders(headers: Record<string, any>) {
    const excluded = ['host', 'connection', 'content-length'];
    return Object.fromEntries(
      Object.entries(headers).filter(([key]) => !excluded.includes(key))
    );
  }
}

@Controller()
export class ProxyController {
  constructor(
    private readonly httpService: HttpService,
    private readonly transformer: RequestTransformerService,
  ) {}

  @All('api/*')
  async proxy(@Req() request: Request) {
    const config = this.transformer.transformRequest(request);
    const targetUrl = `${process.env.SERVICE_URL}${request.url}`;

    return this.httpService.axiosRef({
      ...config,
      url: targetUrl,
    }).toPromise();
  }
}
```

### 4. Response Caching

**When:** Cache responses from microservices to reduce latency

```typescript
import { Cache } from '@nestjs/cache-manager';

@Injectable()
export class CachingProxyService {
  constructor(
    private readonly httpService: HttpService,
    @Inject(CACHE_MANAGER) private cacheManager: Cache,
  ) {}

  async proxy(request: Request, targetUrl: string) {
    // Only cache GET requests
    if (request.method === 'GET') {
      const cached = await this.cacheManager.get(request.url);
      if (cached) return cached;
    }

    const response = await this.httpService.axiosRef({
      method: request.method as any,
      url: targetUrl,
      data: request.body,
    }).toPromise();

    // Cache GET responses for 5 minutes
    if (request.method === 'GET') {
      await this.cacheManager.set(request.url, response.data, 300000);
    }

    return response.data;
  }
}
```

### 5. Error Handling with Fallback

**When:** Microservice unavailable, return fallback response

```typescript
@Injectable()
export class FallbackProxyService {
  private fallbackCache = new Map<string, any>();

  constructor(private readonly httpService: HttpService) {}

  async proxy(request: Request, targetUrl: string) {
    try {
      const response = await this.httpService.axiosRef({
        method: request.method as any,
        url: targetUrl,
        data: request.body,
        timeout: 5000,
      }).toPromise();

      // Store successful response for fallback
      if (request.method === 'GET') {
        this.fallbackCache.set(request.url, response.data);
      }

      return response.data;
    } catch (error) {
      // Return cached response on failure
      if (request.method === 'GET' && this.fallbackCache.has(request.url)) {
        return this.fallbackCache.get(request.url);
      }

      throw new ServiceUnavailableException(
        `Upstream service unavailable: ${error.message}`
      );
    }
  }
}
```

### 6. Circuit Breaker Pattern

**When:** Prevent cascading failures by stopping requests to failing service

```typescript
import { Breaker } from 'opossum';

@Injectable()
export class CircuitBreakerProxyService {
  private breakers: Map<string, any> = new Map();

  constructor(private readonly httpService: HttpService) {}

  getBreaker(service: string) {
    if (!this.breakers.has(service)) {
      const breaker = new Breaker((request) => {
        return this.httpService.axiosRef(request).toPromise();
      }, {
        timeout: 3000, // 3 second timeout
        errorThresholdPercentage: 50, // Open if 50% fail
        resetTimeout: 30000, // Try again after 30 seconds
      });

      this.breakers.set(service, breaker);
    }

    return this.breakers.get(service);
  }

  async proxy(request: Request, service: string, targetUrl: string) {
    const breaker = this.getBreaker(service);

    try {
      return await breaker.fire({
        method: request.method,
        url: targetUrl,
        data: request.body,
      });
    } catch (error) {
      if (breaker.opened) {
        throw new ServiceUnavailableException(
          `Service ${service} circuit breaker is OPEN`
        );
      }
      throw error;
    }
  }
}
```

## Path Rewriting

```typescript
@Controller()
export class ProxyController {
  constructor(private readonly httpService: HttpService) {}

  @All('v1/*')
  async legacyProxy(@Req() request: Request) {
    // Rewrite /v1/users → /users
    const newPath = request.url.replace('/v1', '');
    const targetUrl = `http://service:3000${newPath}`;

    return this.httpService.axiosRef({
      method: request.method as any,
      url: targetUrl,
      data: request.body,
    }).toPromise();
  }
}
```

## Header Management

```typescript
private filterHeaders(headers: Record<string, any>): Record<string, any> {
  // Remove hop-by-hop headers
  const hopByHop = [
    'connection',
    'keep-alive',
    'proxy-authenticate',
    'proxy-authorization',
    'te',
    'trailers',
    'transfer-encoding',
    'upgrade',
    'host', // Important: let target service set its own host
  ];

  return Object.fromEntries(
    Object.entries(headers).filter(([key]) => !hopByHop.includes(key))
  );
}

private addContextHeaders(request: Request): Record<string, any> {
  return {
    'X-Forwarded-For': request.ip,
    'X-Forwarded-Proto': request.protocol,
    'X-Forwarded-Host': request.hostname,
    'X-User-ID': request.user?.id,
    'X-Request-ID': request.id,
  };
}
```

## Testing Proxy Patterns

```typescript
describe('ProxyController', () => {
  let controller: ProxyController;
  let httpService: HttpService;

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      controllers: [ProxyController],
      providers: [
        {
          provide: HttpService,
          useValue: {
            axiosRef: jest.fn(),
          },
        },
      ],
    }).compile();

    controller = module.get(ProxyController);
    httpService = module.get(HttpService);
  });

  it('should proxy request to upstream service', async () => {
    const request = createMockRequest();
    const mockResponse = { data: { id: '1' } };

    jest.spyOn(httpService, 'axiosRef').mockResolvedValue(mockResponse);

    const result = await controller.proxy(request);
    expect(result).toEqual({ id: '1' });
  });
});
```

## Anti-Patterns

❌ Exposing all headers
```typescript
@All('api/*')
async proxy(@Req() request: Request) {
  // Security risk: passes auth headers to microservice
  const response = await this.httpService.axiosRef({
    headers: request.headers,
  }).toPromise();
  return response.data;
}
```

✓ Filter and transform headers
```typescript
private transformHeaders(headers: Record<string, any>) {
  return {
    ...this.filterHeaders(headers),
    'X-User-ID': this.extractUserId(headers),
  };
}
```

❌ No timeout or retry logic
```typescript
// Request hangs forever if microservice is slow
const response = await this.httpService.axiosRef(config).toPromise();
```

✓ Timeout and retry
```typescript
const response = await this.httpService.axiosRef({
  ...config,
  timeout: 5000,
  maxRetries: 2,
}).toPromise();
```

## Token Cost

- Invocation: 100 tokens
- Pattern: 150-250 tokens
- Context7 (if needed): 1000-1500 tokens
- **Total:** 250-1900 tokens

## When to Lookup Context7

- Advanced circuit breaker patterns
- Load balancing algorithms
- Request/response mutation strategies
- Service mesh integration
