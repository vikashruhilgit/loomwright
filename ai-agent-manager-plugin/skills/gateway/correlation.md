# Gateway Correlation ID Skill

Implement request correlation IDs for tracing across microservices.

## Quick Pattern

```typescript
import { Injectable, NestMiddleware } from '@nestjs/common';
import { Request, Response, NextFunction } from 'express';
import { v4 as uuidv4 } from 'uuid';

@Injectable()
export class CorrelationIdMiddleware implements NestMiddleware {
  use(req: Request, res: Response, next: NextFunction) {
    // Generate or extract correlation ID
    const correlationId =
      req.headers['x-correlation-id'] ||
      req.headers['x-request-id'] ||
      uuidv4();

    // Attach to request and response
    req.correlationId = correlationId;
    res.setHeader('X-Correlation-ID', correlationId);
    res.setHeader('X-Request-ID', correlationId);

    next();
  }
}

// Register in app.module.ts
@Module({
  imports: [],
})
export class AppModule implements NestModule {
  configure(consumer: MiddlewareConsumer) {
    consumer.apply(CorrelationIdMiddleware).forRoutes('*');
  }
}

// Usage in controllers
@Controller('users')
export class UserController {
  @Get(':id')
  async getUser(
    @Param('id') id: string,
    @Req() request: Request
  ) {
    console.log(`Correlation ID: ${request.correlationId}`);
    return { id, correlationId: request.correlationId };
  }
}
```

## Patterns

### 1. Correlation ID Extraction/Generation

**When:** Incoming request may or may not have correlation ID

```typescript
@Injectable()
export class CorrelationIdService {
  private readonly logger = new Logger(CorrelationIdService.name);

  generateOrExtract(headers: Record<string, any>): string {
    // Check multiple header formats
    const correlationId =
      headers['x-correlation-id'] ||
      headers['x-request-id'] ||
      headers['correlation-id'] ||
      headers['traceparent']?.split('-')[1]; // W3C Trace Context

    if (correlationId) {
      this.logger.debug(`Using existing correlation ID: ${correlationId}`);
      return correlationId;
    }

    const newId = this.generateId();
    this.logger.debug(`Generated new correlation ID: ${newId}`);
    return newId;
  }

  private generateId(): string {
    return `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
  }
}

@Injectable()
export class CorrelationIdMiddleware implements NestMiddleware {
  constructor(private correlationIdService: CorrelationIdService) {}

  use(req: Request, res: Response, next: NextFunction) {
    const correlationId = this.correlationIdService.generateOrExtract(
      req.headers as Record<string, any>,
    );

    req.correlationId = correlationId;
    res.setHeader('X-Correlation-ID', correlationId);

    next();
  }
}
```

### 2. Propagating Correlation ID to Microservices

**When:** Forward correlation ID in proxy requests

```typescript
@Injectable()
export class ProxyService {
  constructor(private readonly httpService: HttpService) {}

  async proxyRequest(
    request: Request,
    targetUrl: string,
  ) {
    const headers = this.addCorrelationId(request.headers, request.correlationId);

    return this.httpService.axiosRef({
      method: request.method as any,
      url: targetUrl,
      data: request.body,
      headers,
    }).toPromise();
  }

  private addCorrelationId(
    headers: Record<string, any>,
    correlationId: string,
  ): Record<string, any> {
    return {
      ...this.filterHeaders(headers),
      'X-Correlation-ID': correlationId,
      'X-Request-ID': correlationId,
    };
  }

  private filterHeaders(headers: Record<string, any>) {
    const excluded = ['host', 'connection', 'content-length'];
    return Object.fromEntries(
      Object.entries(headers).filter(([key]) => !excluded.includes(key)),
    );
  }
}

@Controller()
export class ProxyController {
  constructor(private proxyService: ProxyService) {}

  @All('api/*')
  async proxy(@Req() request: Request) {
    const targetUrl = `http://microservice:3000${request.url}`;
    return this.proxyService.proxyRequest(request, targetUrl);
  }
}
```

### 3. Logging with Correlation ID

**When:** Include correlation ID in all log entries

```typescript
import { Logger as WinstonLogger } from 'winston';

@Injectable()
export class CorrelatedLoggerService {
  private logger = new Logger();

  log(message: string, correlationId: string, meta?: any) {
    this.logger.log({
      message,
      correlationId,
      ...meta,
    });
  }

  error(message: string, error: any, correlationId: string, meta?: any) {
    this.logger.error({
      message,
      error: error.message,
      stack: error.stack,
      correlationId,
      ...meta,
    });
  }

  debug(message: string, correlationId: string, meta?: any) {
    this.logger.debug({
      message,
      correlationId,
      ...meta,
    });
  }
}

// Usage in service
@Injectable()
export class UserService {
  constructor(private logger: CorrelatedLoggerService) {}

  async getUser(id: string, correlationId: string) {
    this.logger.log('Fetching user', correlationId, { userId: id });
    try {
      const user = await this.userRepository.findById(id);
      this.logger.log('User fetched', correlationId, { userId: id, found: !!user });
      return user;
    } catch (error) {
      this.logger.error('Failed to fetch user', error, correlationId, { userId: id });
      throw error;
    }
  }
}
```

### 4. Correlation ID in Request Context

**When:** Access correlation ID throughout request lifecycle

```typescript
import { createNamespace } from 'cls-hooked';

const requestContext = createNamespace('request');

@Injectable()
export class CorrelationIdMiddleware implements NestMiddleware {
  use(req: Request, res: Response, next: NextFunction) {
    const correlationId = req.headers['x-correlation-id'] || uuidv4();

    requestContext.run(() => {
      requestContext.set('correlationId', correlationId);
      requestContext.set('userId', req.user?.id);
      requestContext.set('timestamp', new Date());

      res.setHeader('X-Correlation-ID', correlationId);
      next();
    });
  }
}

// Usage: Access context anywhere
@Injectable()
export class ContextAwareService {
  doSomething() {
    const correlationId = requestContext.get('correlationId');
    const userId = requestContext.get('userId');
    console.log(`Request ${correlationId} from user ${userId}`);
  }
}
```

### 5. Correlation ID in Error Responses

**When:** Include correlation ID in error messages for debugging

```typescript
@Catch()
export class GlobalExceptionFilter implements ExceptionFilter {
  constructor(private logger: Logger) {}

  catch(exception: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const request = ctx.getRequest<Request>();
    const response = ctx.getResponse<Response>();

    const status = exception instanceof HttpException
      ? exception.getStatus()
      : 500;

    const correlationId = request.correlationId || 'unknown';

    this.logger.error(
      `Error in request ${correlationId}`,
      exception instanceof Error ? exception.stack : '',
    );

    response.status(status).json({
      statusCode: status,
      message: exception instanceof HttpException
        ? exception.getResponse()
        : 'Internal server error',
      correlationId, // Include in response
      timestamp: new Date().toISOString(),
    });
  }
}
```

### 6. Datadog Integration with Correlation ID

**When:** Send correlation ID to observability platform

```typescript
import { trace } from 'dd-trace';

@Injectable()
export class DatadogInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler) {
    const request = context.switchToHttp().getRequest<Request>();
    const correlationId = request.correlationId;

    return next.handle().pipe(
      tap(() => {
        const span = trace.getSpan();
        if (span) {
          span.setTag('correlation_id', correlationId);
          span.setTag('user_id', request.user?.id);
          span.setTag('method', request.method);
          span.setTag('url', request.url);
        }
      }),
    );
  }
}

@Module({
  providers: [
    {
      provide: APP_INTERCEPTOR,
      useClass: DatadogInterceptor,
    },
  ],
})
export class AppModule { }
```

### 7. Correlation ID in Database Audit

**When:** Track database changes with correlation ID

```typescript
@Injectable()
export class UserService {
  constructor(
    private userRepository: UserRepository,
    private auditRepository: AuditRepository,
  ) {}

  async updateUser(id: string, updateDTO: UpdateUserDTO, correlationId: string) {
    const user = await this.userRepository.update(id, updateDTO);

    // Log audit trail
    await this.auditRepository.create({
      entityType: 'User',
      entityId: id,
      action: 'UPDATE',
      changes: updateDTO,
      correlationId,
      timestamp: new Date(),
    });

    return user;
  }
}

// Query audit logs by correlation ID
async getAuditTrail(correlationId: string) {
  return this.auditRepository.find({ correlationId });
}
```

## Header Formats

### Standard Headers

| Header | Format | Usage |
|--------|--------|-------|
| `X-Correlation-ID` | UUID or custom | De facto standard |
| `X-Request-ID` | UUID or custom | AWS ALB standard |
| `Correlation-ID` | UUID or custom | Alternative format |

### W3C Trace Context

```typescript
// W3C format: traceparent: version-trace_id-parent_id-flags
// Example: traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01

const traceparent = headers['traceparent'];
if (traceparent) {
  const [version, traceId, parentId, flags] = traceparent.split('-');
  // Use traceId as correlation ID
}
```

## Querying with Correlation ID

### Elasticsearch Example

```typescript
// Query logs by correlation ID
GET /logs-*/_search
{
  "query": {
    "match": {
      "correlation_id": "550e8400-e29b-41d4-a716-446655440000"
    }
  }
}
```

### CloudWatch Logs Example

```bash
# Query AWS CloudWatch for correlation ID
aws logs filter-log-events \
  --log-group-name /aws/gateway \
  --filter-pattern "{ $.correlationId = \"550e8400-e29b-41d4-a716-446655440000\" }"
```

## Testing Correlation ID

```typescript
describe('Correlation ID', () => {
  let app: INestApplication;

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = module.createNestApplication();
    await app.init();
  });

  it('should generate correlation ID if missing', async () => {
    const response = await request(app.getHttpServer())
      .get('/users/1')
      .expect(200);

    const correlationId = response.headers['x-correlation-id'];
    expect(correlationId).toBeDefined();
  });

  it('should preserve provided correlation ID', async () => {
    const providedId = '550e8400-e29b-41d4-a716-446655440000';

    const response = await request(app.getHttpServer())
      .get('/users/1')
      .set('X-Correlation-ID', providedId)
      .expect(200);

    expect(response.headers['x-correlation-id']).toBe(providedId);
  });

  it('should propagate correlation ID to downstream services', async () => {
    const correlationId = '550e8400-e29b-41d4-a716-446655440000';

    const response = await request(app.getHttpServer())
      .get('/api/data')
      .set('X-Correlation-ID', correlationId)
      .expect(200);

    // Verify downstream service received the ID (via mock)
    expect(httpService.axiosRef).toHaveBeenCalledWith(
      expect.objectContaining({
        headers: expect.objectContaining({
          'X-Correlation-ID': correlationId,
        }),
      }),
    );
  });
});
```

## Anti-Patterns

❌ Losing correlation ID at any point
```typescript
// Request has ID, but it's not propagated to service
await this.userService.getUser(id); // Missing correlationId
```

✓ Pass through entire request context
```typescript
// Request has ID, pass it everywhere
await this.userService.getUser(id, request.correlationId);
```

❌ Different correlation ID per layer
```typescript
// Each service generates new ID instead of inheriting
const id = uuidv4(); // New ID!
```

✓ Inherit from request
```typescript
// Use existing ID from headers
const id = headers['x-correlation-id'] || uuidv4();
```

## Token Cost

- Invocation: 100 tokens
- Pattern: 150-200 tokens
- Context7 (if needed): 1000-1500 tokens
- **Total:** 250-1900 tokens

## When to Lookup Context7

- Distributed tracing with OpenTelemetry
- Advanced correlation ID propagation
- Microservice choreography patterns
- Cross-region request tracking
