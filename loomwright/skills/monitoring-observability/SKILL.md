---
name: monitoring-observability
description: Monitoring and observability patterns. Covers structured logging, distributed tracing with OpenTelemetry, metrics collection, and alerting thresholds. Use when implementing or reviewing observability.
allowed-tools: [Read]
version: "1.0.0"
lastUpdated: "2026-03"
---

# Monitoring & Observability

Patterns for structured logging, distributed tracing, metrics, and alerting.

---

## When to Use

- Adding logging to new services
- Setting up distributed tracing across microservices
- Defining metrics and alert thresholds
- Reviewing observability coverage during code review or red team audit

## When NOT to Use

- Application error handling logic — use `error-handling`
- CI/CD pipeline monitoring — use `ci-cd`
- Security audit of logging (PII leaks) — consult Red Team Reviewer directly

## Core Patterns

### 1. Structured Logging

Always emit JSON logs with consistent fields:

```typescript
// src/common/logger.ts
import pino from 'pino';

export const logger = pino({
  level: process.env.LOG_LEVEL ?? 'info',
  formatters: {
    level: (label) => ({ level: label }),
  },
  base: {
    service: process.env.SERVICE_NAME ?? 'app',
    environment: process.env.NODE_ENV ?? 'development',
  },
  redact: ['req.headers.authorization', 'password', 'token', 'secret'],
  timestamp: pino.stdTimeFunctions.isoTime,
});

// Usage
logger.info({ userId, action: 'login', duration: 42 }, 'User logged in');
logger.error({ err, orderId }, 'Payment processing failed');
```

Rules:
- Always use structured fields, never string interpolation for variables
- Redact sensitive fields (tokens, passwords, PII)
- Include correlation ID in every log line
- Use appropriate levels: `error` (action needed), `warn` (unexpected but handled), `info` (business events), `debug` (development)

### 2. Correlation ID Propagation

```typescript
// NestJS middleware
@Injectable()
export class CorrelationMiddleware implements NestMiddleware {
  use(req: Request, res: Response, next: NextFunction) {
    const correlationId = req.headers['x-correlation-id'] as string
      ?? crypto.randomUUID();

    req['correlationId'] = correlationId;
    res.setHeader('x-correlation-id', correlationId);

    // Attach to async local storage for downstream access
    asyncLocalStorage.run({ correlationId }, () => next());
  }
}
```

### 3. OpenTelemetry Setup

```typescript
// src/telemetry.ts
import { NodeSDK } from '@opentelemetry/sdk-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { HttpInstrumentation } from '@opentelemetry/instrumentation-http';
import { NestInstrumentation } from '@opentelemetry/instrumentation-nestjs-core';

const sdk = new NodeSDK({
  serviceName: process.env.SERVICE_NAME,
  traceExporter: new OTLPTraceExporter({
    url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT ?? 'http://localhost:4318/v1/traces',
  }),
  instrumentations: [
    new HttpInstrumentation(),
    new NestInstrumentation(),
  ],
});

sdk.start();
process.on('SIGTERM', () => sdk.shutdown());
```

### 4. Key Metrics to Track

```typescript
// Application metrics (Prometheus format)
const httpRequestDuration = new Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request duration in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.01, 0.05, 0.1, 0.5, 1, 5],
});

const httpRequestTotal = new Counter({
  name: 'http_requests_total',
  help: 'Total HTTP requests',
  labelNames: ['method', 'route', 'status_code'],
});

const activeConnections = new Gauge({
  name: 'db_active_connections',
  help: 'Active database connections',
});
```

Essential metrics per service:

| Metric | Type | Alert Threshold |
|--------|------|-----------------|
| Request rate | Counter | Sudden drop > 50% |
| Error rate (5xx) | Counter | > 1% of total requests |
| Latency p99 | Histogram | > 2s for API, > 5s for async |
| DB connection pool | Gauge | > 80% utilization |
| Memory usage | Gauge | > 85% of limit |
| Queue depth | Gauge | Growing for > 5 min |

### 5. Alert Thresholds

```yaml
# Example Prometheus alerting rules
groups:
  - name: app-alerts
    rules:
      - alert: HighErrorRate
        expr: rate(http_requests_total{status_code=~"5.."}[5m]) / rate(http_requests_total[5m]) > 0.01
        for: 5m
        labels:
          severity: critical

      - alert: HighLatency
        expr: histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m])) > 2
        for: 5m
        labels:
          severity: warning
```

## Example Implementation

A NestJS interceptor that logs requests with correlation ID and records duration metrics:

```typescript
// src/common/interceptors/logging.interceptor.ts
@Injectable()
export class LoggingInterceptor implements NestInterceptor {
  constructor(private readonly logger: Logger) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const req = context.switchToHttp().getRequest<Request>();
    const { method, url } = req;
    const correlationId = req['correlationId'] ?? 'unknown';
    const start = Date.now();

    return next.handle().pipe(
      tap(() => {
        const duration = Date.now() - start;
        this.logger.info({ method, url, correlationId, duration }, 'Request completed');
        httpRequestDuration.observe({ method, route: url, status_code: 200 }, duration / 1000);
      }),
      catchError((err) => {
        const duration = Date.now() - start;
        this.logger.error({ method, url, correlationId, duration, err }, 'Request failed');
        httpRequestDuration.observe({ method, route: url, status_code: 500 }, duration / 1000);
        throw err;
      }),
    );
  }
}
```

## Testing Approach

- Test structured logger output by capturing log stream and verifying JSON fields (level, service, correlationId)
- Test correlation middleware by sending a request without `x-correlation-id` and verifying one is generated and propagated
- Test metric recording by invoking the interceptor and checking histogram/counter values via the Prometheus client registry
- Verify PII redaction by logging an object with `password` and `token` fields and asserting they are masked in output

## Anti-Patterns

- **Logging PII:** Never log emails, passwords, tokens, or personal data. Use redaction.
- **Unstructured log strings:** `logger.info("User " + userId + " logged in")` is unsearchable. Use structured fields.
- **Missing correlation IDs:** Without them, tracing requests across services is impossible.
- **Alert fatigue:** Too many low-threshold alerts cause teams to ignore them. Alert on symptoms, not causes.
- **Metrics without labels:** Unlabeled metrics are useless for debugging. Always include route, method, status.

## Related Skills

- `error-handling` — Error classification and logging levels
- `gateway-correlation` (stackpack@atelier plugin) — Correlation ID at the API gateway layer
- `redis-caching` (stackpack@atelier plugin) — Cache hit/miss metrics
- `docker` (stackpack@atelier plugin) — Container health checks and log drivers

## Quality Gates

- [ ] All log statements use structured format (JSON with named fields)
- [ ] Sensitive fields are redacted in log configuration
- [ ] Correlation ID propagated through all service boundaries
- [ ] Key metrics defined: request rate, error rate, latency p99, saturation
- [ ] Alert thresholds set for critical metrics with appropriate `for` duration
- [ ] No PII in logs (verify with grep for email, password, token patterns)
- [ ] Telemetry SDK initializes before application bootstrap
