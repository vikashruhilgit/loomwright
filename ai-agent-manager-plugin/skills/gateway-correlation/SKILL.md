---
name: gateway-correlation
version: "1.0.0"
lastUpdated: "2026-03"
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

## Distributed Tracing Propagation (OpenTelemetry)

Propagate trace context across service boundaries using W3C Trace Context:

```typescript
// tracing/tracing.module.ts
import { Module } from '@nestjs/common';
import { NodeSDK } from '@opentelemetry/sdk-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { HttpInstrumentation } from '@opentelemetry/instrumentation-http';
import { NestInstrumentation } from '@opentelemetry/instrumentation-nestjs-core';

const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter({
    url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://jaeger:4318/v1/traces',
  }),
  instrumentations: [
    new HttpInstrumentation(),
    new NestInstrumentation(),
  ],
});
sdk.start();

// middleware/tracing.middleware.ts — enrich spans with correlation ID
import { Injectable, NestMiddleware } from '@nestjs/common';
import { trace, context, SpanStatusCode } from '@opentelemetry/api';

@Injectable()
export class TracingMiddleware implements NestMiddleware {
  use(req: Request, res: Response, next: NextFunction) {
    const span = trace.getActiveSpan();
    const correlationId = req.headers['x-correlation-id'] || req.correlationId;

    if (span && correlationId) {
      span.setAttribute('correlation.id', correlationId);
      span.setAttribute('http.route', req.url);
      span.setAttribute('user.id', req.user?.id || 'anonymous');
    }

    next();
  }
}

// Propagate context to downstream HTTP calls
import { W3CTraceContextPropagator } from '@opentelemetry/core';
import { propagation } from '@opentelemetry/api';

async function callDownstreamService(url: string, correlationId: string) {
  const headers: Record<string, string> = {
    'x-correlation-id': correlationId,
  };

  // Inject W3C traceparent header automatically
  propagation.inject(context.active(), headers);

  return fetch(url, { headers });
}
```

## Structured Logging Integration

Embed correlation ID in every log entry for cross-service traceability:

```typescript
// logging/correlation-logger.service.ts
import { Injectable, Scope, Inject, LoggerService } from '@nestjs/common';
import { REQUEST } from '@nestjs/core';
import { Request } from 'express';

@Injectable({ scope: Scope.REQUEST })
export class CorrelationLogger implements LoggerService {
  private readonly correlationId: string;

  constructor(@Inject(REQUEST) private readonly request: Request) {
    this.correlationId = (request as any).correlationId || 'no-correlation-id';
  }

  log(message: string, context?: string) {
    console.log(JSON.stringify({
      level: 'info',
      message,
      context,
      correlationId: this.correlationId,
      timestamp: new Date().toISOString(),
      traceId: (this.request as any).traceId,
    }));
  }

  error(message: string, trace?: string, context?: string) {
    console.error(JSON.stringify({
      level: 'error',
      message,
      trace,
      context,
      correlationId: this.correlationId,
      timestamp: new Date().toISOString(),
    }));
  }

  warn(message: string, context?: string) {
    console.warn(JSON.stringify({
      level: 'warn',
      message,
      context,
      correlationId: this.correlationId,
      timestamp: new Date().toISOString(),
    }));
  }
}

// interceptors/correlation-logging.interceptor.ts — log every request
@Injectable()
export class CorrelationLoggingInterceptor implements NestInterceptor {
  private readonly logger = new Logger('Gateway');

  intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
    const req = context.switchToHttp().getRequest();
    const { method, url, correlationId } = req;
    const start = Date.now();

    return next.handle().pipe(
      tap({
        next: () => {
          this.logger.log(JSON.stringify({
            correlationId,
            method,
            url,
            statusCode: context.switchToHttp().getResponse().statusCode,
            durationMs: Date.now() - start,
          }));
        },
        error: (err) => {
          this.logger.error(JSON.stringify({
            correlationId,
            method,
            url,
            error: err.message,
            statusCode: err.status || 500,
            durationMs: Date.now() - start,
          }));
        },
      }),
    );
  }
}
```

## Token Cost

- Pattern: 150-200 tokens
- Context7 (if needed): 1000-1500 tokens
