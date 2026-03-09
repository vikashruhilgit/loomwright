---
name: gateway-auth-middleware
version: "1.0.0"
lastUpdated: "2026-03"
description: Implement authentication and authorization middleware for API Gateway. Use when implementing JWT validation, API key auth, or role-based access control in API Gateway.
---

# Gateway Auth Middleware Skill

Implement authentication and authorization middleware for API Gateway.

## Quick Pattern

```typescript
import { createParamDecorator, ExecutionContext } from '@nestjs/common';

export enum AuthType {
  None = 'None',
  Bearer = 'Bearer',
  ApiKey = 'ApiKey',
}

export const Auth = createParamDecorator(
  (authType: AuthType, context: ExecutionContext) => {
    const request = context.switchToHttp().getRequest();
    return { authType, request };
  },
);

// Usage
@Controller('auth')
export class AuthController {
  @Post('sign-in')
  @Auth(AuthType.None)
  async signIn(@Body() signInDTO: SignInDTO) {
    return this.authService.signIn(signInDTO);
  }
}
```

## When to Use

- JWT guard implementation
- Multi-auth guard (Bearer, API key, Basic)
- Role-based access control (RBAC)
- Permission middleware
- Token refresh middleware

## JWT Validation Flow

Request lifecycle through the auth middleware chain:

```
Client Request
  │
  ├─ 1. Extract token from Authorization header
  │     → Missing? Return 401 Unauthorized
  │
  ├─ 2. Decode JWT header (check alg)
  │     → Unsupported algorithm? Return 401
  │
  ├─ 3. Verify signature + expiration
  │     → Expired? Check refresh flow
  │     → Invalid signature? Return 401
  │
  ├─ 4. Validate claims (iss, aud, scope)
  │     → Wrong issuer/audience? Return 403
  │
  ├─ 5. Attach user to request context
  │
  └─ 6. Pass to next middleware / guard
```

```typescript
// guards/jwt-validation.guard.ts
import { Injectable, CanActivate, ExecutionContext, UnauthorizedException } from '@nestjs/common';
import { JwtService, TokenExpiredError } from '@nestjs/jwt';

@Injectable()
export class JwtValidationGuard implements CanActivate {
  constructor(
    private readonly jwtService: JwtService,
    private readonly configService: ConfigService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();
    const authHeader = request.headers.authorization;

    if (!authHeader?.startsWith('Bearer ')) {
      throw new UnauthorizedException('Missing Bearer token');
    }

    const token = authHeader.slice(7);

    try {
      const payload = await this.jwtService.verifyAsync(token, {
        secret: this.configService.get('JWT_SECRET'),
        issuer: this.configService.get('JWT_ISSUER'),
        audience: this.configService.get('JWT_AUDIENCE'),
      });

      request.user = payload;
      return true;
    } catch (error) {
      if (error instanceof TokenExpiredError) {
        throw new UnauthorizedException('Token expired');
      }
      throw new UnauthorizedException('Invalid token');
    }
  }
}
```

## API Key Rotation Strategy

Support multiple active keys for zero-downtime rotation:

```typescript
// guards/api-key.guard.ts
@Injectable()
export class ApiKeyGuard implements CanActivate {
  constructor(private readonly apiKeyService: ApiKeyService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();
    const apiKey = request.headers['x-api-key'];

    if (!apiKey) {
      throw new UnauthorizedException('Missing API key');
    }

    const keyRecord = await this.apiKeyService.validate(apiKey);
    if (!keyRecord) {
      throw new UnauthorizedException('Invalid API key');
    }

    request.client = keyRecord.client;
    request.scopes = keyRecord.scopes;
    return true;
  }
}

// services/api-key.service.ts — rotation support
@Injectable()
export class ApiKeyService {
  constructor(private readonly repo: ApiKeyRepository) {}

  async validate(key: string): Promise<ApiKeyRecord | null> {
    const hashed = this.hashKey(key);
    const record = await this.repo.findByHash(hashed);

    if (!record) return null;
    if (record.expiresAt && record.expiresAt < new Date()) return null;
    if (record.revokedAt) return null;

    // Track last used for audit
    await this.repo.updateLastUsed(record.id);
    return record;
  }

  async rotate(clientId: string): Promise<{ newKey: string; deprecationDate: Date }> {
    const newKey = this.generateKey();
    const deprecationDate = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000); // 30 days

    // Create new key
    await this.repo.create({
      clientId,
      hash: this.hashKey(newKey),
      expiresAt: null,
    });

    // Mark old keys for deprecation (not immediate revocation)
    await this.repo.markDeprecated(clientId, deprecationDate);

    return { newKey, deprecationDate };
  }
}
```

## RBAC Middleware Chain Pattern

Compose auth middleware in layers:

```typescript
// Layered auth: authenticate → authorize → scope-check
@Controller('api/v1')
@UseGuards(MultiAuthGuard) // Layer 1: authenticate (JWT or API Key)
export class ResourceController {

  @Get('users')
  @UseGuards(RolesGuard) // Layer 2: role check
  @Roles('admin', 'manager')
  @RequireScopes('users:read') // Layer 3: scope check
  @UseGuards(ScopesGuard)
  findAllUsers() {
    return this.userService.findAll();
  }
}

// guards/multi-auth.guard.ts — try JWT first, fall back to API key
@Injectable()
export class MultiAuthGuard implements CanActivate {
  constructor(
    private readonly jwtGuard: JwtValidationGuard,
    private readonly apiKeyGuard: ApiKeyGuard,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();
    const hasBearer = request.headers.authorization?.startsWith('Bearer ');
    const hasApiKey = !!request.headers['x-api-key'];

    if (hasBearer) return this.jwtGuard.canActivate(context);
    if (hasApiKey) return this.apiKeyGuard.canActivate(context);

    throw new UnauthorizedException('No authentication credentials provided');
  }
}
```

## Related Skills

- `nestjs-guards` — NestJS authentication/authorization guards for service-level auth (downstream from gateway middleware)
- `nextjs-auth` — NextAuth.js patterns for frontend session management (consumes tokens validated by gateway)

## Token Cost

- Pattern: 200-300 tokens
- Context7 (if needed): 1000-1500 tokens
