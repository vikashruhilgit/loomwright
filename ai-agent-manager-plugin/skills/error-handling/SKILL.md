---
name: error-handling
description: Error handling patterns across the stack. Covers custom error hierarchies, NestJS exception filters, React error boundaries, retry with backoff, and graceful degradation. Use when implementing or reviewing error handling.
allowed-tools: [Read]
version: "1.0.0"
lastUpdated: "2026-03"
---

# Error Handling

Patterns for consistent, debuggable error handling across backend and frontend.

---

## When to Use

- Adding error handling to new services, controllers, or components
- Reviewing code for missing error paths
- Implementing retry logic for unreliable external services
- Setting up global error handling infrastructure

## When NOT to Use

- Monitoring and alerting setup — use `monitoring-observability`
- Security-specific error masking — consult `gateway-auth-middleware`
- Test error assertions — see `unit-testing`

## Core Patterns

### 1. Custom Error Hierarchy

Define a base error class and extend for specific domains:

```typescript
// src/common/errors/app.error.ts
export class AppError extends Error {
  constructor(
    message: string,
    public readonly code: string,
    public readonly statusCode: number = 500,
    public readonly isOperational: boolean = true,
  ) {
    super(message);
    this.name = this.constructor.name;
    Error.captureStackTrace(this, this.constructor);
  }
}

export class NotFoundError extends AppError {
  constructor(resource: string, id: string) {
    super(`${resource} with id ${id} not found`, 'NOT_FOUND', 404);
  }
}

export class ValidationError extends AppError {
  constructor(message: string, public readonly fields: Record<string, string>) {
    super(message, 'VALIDATION_ERROR', 400);
  }
}

export class ConflictError extends AppError {
  constructor(message: string) {
    super(message, 'CONFLICT', 409);
  }
}
```

### 2. NestJS Exception Filter

Catch all errors and return consistent API responses:

```typescript
// src/common/filters/global-exception.filter.ts
@Catch()
export class GlobalExceptionFilter implements ExceptionFilter {
  constructor(private readonly logger: Logger) {}

  catch(exception: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<Request>();

    const { statusCode, body } = this.buildResponse(exception, request);

    if (statusCode >= 500) {
      this.logger.error('Unhandled exception', { exception, path: request.url });
    }

    response.status(statusCode).json(body);
  }

  private buildResponse(exception: unknown, request: Request) {
    if (exception instanceof AppError) {
      return {
        statusCode: exception.statusCode,
        body: {
          error: exception.code,
          message: exception.message,
          path: request.url,
          timestamp: new Date().toISOString(),
        },
      };
    }

    if (exception instanceof HttpException) {
      return { statusCode: exception.getStatus(), body: exception.getResponse() };
    }

    return {
      statusCode: 500,
      body: {
        error: 'INTERNAL_ERROR',
        message: 'An unexpected error occurred',
        path: request.url,
        timestamp: new Date().toISOString(),
      },
    };
  }
}
```

### 3. React Error Boundary

Catch render errors and show fallback UI:

```tsx
// src/components/ErrorBoundary.tsx
interface Props { children: React.ReactNode; fallback?: React.ReactNode; }
interface State { hasError: boolean; error: Error | null; }

export class ErrorBoundary extends React.Component<Props, State> {
  state: State = { hasError: false, error: null };

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, info: React.ErrorInfo) {
    console.error('ErrorBoundary caught:', error, info.componentStack);
    // Send to error tracking service
  }

  render() {
    if (this.state.hasError) {
      return this.props.fallback ?? <DefaultErrorFallback error={this.state.error} />;
    }
    return this.props.children;
  }
}
```

### 4. Retry with Exponential Backoff

For transient failures (network, rate limits):

```typescript
export async function withRetry<T>(
  fn: () => Promise<T>,
  options: { maxAttempts?: number; baseDelayMs?: number; maxDelayMs?: number } = {},
): Promise<T> {
  const { maxAttempts = 3, baseDelayMs = 200, maxDelayMs = 5000 } = options;

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (error) {
      if (attempt === maxAttempts || !isRetryable(error)) throw error;
      const delay = Math.min(baseDelayMs * 2 ** (attempt - 1), maxDelayMs);
      const jitter = delay * (0.5 + Math.random() * 0.5);
      await new Promise((resolve) => setTimeout(resolve, jitter));
    }
  }
  throw new Error('Unreachable');
}

function isRetryable(error: unknown): boolean {
  if (error instanceof AppError) return !error.isOperational;
  if (error instanceof Error && 'status' in error) {
    const status = (error as { status: number }).status;
    return status === 429 || status >= 500;
  }
  return true;
}
```

### 5. Graceful Degradation

Return cached or default data when a dependency fails:

```typescript
async function getUserProfile(id: string): Promise<UserProfile> {
  try {
    return await userService.fetchProfile(id);
  } catch (error) {
    const cached = await cache.get<UserProfile>(`profile:${id}`);
    if (cached) {
      logger.warn('Serving cached profile due to service failure', { id, error });
      return { ...cached, _stale: true };
    }
    throw error; // No fallback available
  }
}
```

## Example Implementation

A service using the error hierarchy with retry and graceful degradation together:

```typescript
// src/services/order.service.ts
@Injectable()
export class OrderService {
  constructor(
    private readonly orderRepo: OrderRepository,
    private readonly paymentClient: PaymentClient,
    private readonly logger: Logger,
  ) {}

  async placeOrder(dto: CreateOrderDto): Promise<Order> {
    const order = await this.orderRepo.create(dto);

    try {
      const payment = await withRetry(
        () => this.paymentClient.charge(order.id, dto.amount),
        { maxAttempts: 3, baseDelayMs: 500 },
      );
      return this.orderRepo.save({ ...order, paymentId: payment.id, status: 'confirmed' });
    } catch (error) {
      this.logger.error({ err: error, orderId: order.id }, 'Payment failed');
      await this.orderRepo.save({ ...order, status: 'payment_failed' });
      throw new AppError('Payment processing failed', 'PAYMENT_FAILED', 502, true);
    }
  }
}
```

## Testing Approach

- Test each custom error class instantiation verifying `code`, `statusCode`, and `isOperational` fields
- Test the global exception filter with mock requests for `AppError`, `HttpException`, and unknown error types
- Test `withRetry` with a mock function that fails N times then succeeds, and verify jitter/backoff behavior
- Test graceful degradation by mocking a service failure and verifying the cached fallback is returned

## Anti-Patterns

- **Swallowing errors silently:** Never `catch (e) {}`. Always log or rethrow.
- **Leaking internal details:** Never send stack traces or internal paths in API responses to clients.
- **Catching too broadly:** Catch specific error types; let unexpected errors bubble to the global handler.
- **Retry non-idempotent operations:** Only retry reads and idempotent writes.
- **Using error strings for control flow:** Use error types and codes, not string matching.

## Related Skills

- `monitoring-observability` — Logging and alerting for caught errors
- `nestjs-controllers` — Controller-level error handling in NestJS
- `unit-testing` — Testing error paths and exception scenarios
- `gateway-auth-middleware` — Auth error handling at the gateway layer

## Quality Gates

- [ ] All public API endpoints return consistent error shape (code, message, timestamp)
- [ ] Custom error classes extend a base AppError
- [ ] 5xx errors are logged with full context; 4xx errors logged at warn level
- [ ] No stack traces or internal paths exposed to API clients
- [ ] Retry logic includes jitter and max attempts
- [ ] React components wrapped in error boundaries at route level
- [ ] Error paths have unit tests
