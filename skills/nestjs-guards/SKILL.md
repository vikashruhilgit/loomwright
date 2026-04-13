---
name: nestjs-guards
version: "1.0.0"
lastUpdated: "2026-03"
description: Implement authentication and authorization guards following NestJS patterns. Use when implementing auth guards, role-based access control, or permission checks.
---

# NestJS Guards Skill

Implement authentication and authorization guards following NestJS patterns.

## Quick Pattern

```typescript
import { Injectable, CanActivate, ExecutionContext } from '@nestjs/common';

@Injectable()
export class JwtGuard implements CanActivate {
  constructor(private jwtService: JwtService) {}

  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest();
    try {
      const token = request.headers.authorization?.split(' ')[1];
      const payload = this.jwtService.verify(token);
      request.user = payload;
      return true;
    } catch {
      return false;
    }
  }
}
```

## When to Use

- Guard composition with metadata
- Role-based access control (RBAC)
- Custom decorator guard
- Async guard logic
- Global guard registration

## Role-Based Guards

Use custom decorators with metadata to enforce role requirements:

```typescript
// decorators/roles.decorator.ts
import { SetMetadata } from '@nestjs/common';
export const ROLES_KEY = 'roles';
export const Roles = (...roles: string[]) => SetMetadata(ROLES_KEY, roles);

// guards/roles.guard.ts
import { Injectable, CanActivate, ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const requiredRoles = this.reflector.getAllAndOverride<string[]>(ROLES_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (!requiredRoles) return true; // No roles required, allow

    const { user } = context.switchToHttp().getRequest();
    return requiredRoles.some((role) => user.roles?.includes(role));
  }
}

// Usage on controller
@UseGuards(JwtGuard, RolesGuard)
@Controller('admin')
export class AdminController {
  @Get('users')
  @Roles('admin', 'super-admin')
  findAll() {
    return this.adminService.findAllUsers();
  }

  @Delete('users/:id')
  @Roles('super-admin')
  remove(@Param('id') id: string) {
    return this.adminService.removeUser(id);
  }
}
```

## Policy-Based Guards (CASL/Abilities)

Fine-grained permission checks using CASL abilities:

```typescript
// casl/casl-ability.factory.ts
import { AbilityBuilder, createMongoAbility, MongoAbility } from '@casl/ability';

export type Actions = 'manage' | 'create' | 'read' | 'update' | 'delete';
export type Subjects = 'Article' | 'User' | 'Comment' | 'all';
export type AppAbility = MongoAbility<[Actions, Subjects]>;

@Injectable()
export class CaslAbilityFactory {
  createForUser(user: User): AppAbility {
    const { can, cannot, build } = new AbilityBuilder<AppAbility>(createMongoAbility);

    if (user.role === 'admin') {
      can('manage', 'all');
    } else {
      can('read', 'Article');
      can('create', 'Comment');
      can('update', 'Article', { authorId: user.id }); // Only own articles
      cannot('delete', 'Article');
    }

    return build();
  }
}

// guards/policies.guard.ts
@Injectable()
export class PoliciesGuard implements CanActivate {
  constructor(
    private reflector: Reflector,
    private caslAbilityFactory: CaslAbilityFactory,
  ) {}

  canActivate(context: ExecutionContext): boolean {
    const policies = this.reflector.get<PolicyHandler[]>('policies', context.getHandler()) || [];
    const { user } = context.switchToHttp().getRequest();
    const ability = this.caslAbilityFactory.createForUser(user);
    return policies.every((handler) => handler(ability));
  }
}

// Usage
@Get(':id')
@CheckPolicies((ability: AppAbility) => ability.can('read', 'Article'))
findOne(@Param('id') id: string) { /* ... */ }
```

## Guard Composition

Apply multiple guards in sequence (all must pass):

```typescript
// All guards must return true — evaluated left to right
@UseGuards(ThrottlerGuard, JwtGuard, RolesGuard, PoliciesGuard)
@Controller('articles')
export class ArticleController {
  // ThrottlerGuard → rate limit check
  // JwtGuard → validate token, attach user
  // RolesGuard → check user.roles metadata
  // PoliciesGuard → fine-grained ability check
}

// Global + local composition
// main.ts — global guard applies first
app.useGlobalGuards(new ThrottlerGuard());

// Controller adds additional guards on top
@UseGuards(JwtGuard, RolesGuard)
@Controller('admin')
export class AdminController { /* ... */ }
```

## JWT Integration with Passport

Use @nestjs/passport for standardized JWT authentication:

```typescript
// auth/jwt.strategy.ts
import { Injectable } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(private configService: ConfigService) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: configService.get<string>('JWT_SECRET'),
    });
  }

  async validate(payload: { sub: string; email: string; roles: string[] }) {
    return { id: payload.sub, email: payload.email, roles: payload.roles };
  }
}

// auth/jwt-auth.guard.ts
import { AuthGuard } from '@nestjs/passport';
export class JwtAuthGuard extends AuthGuard('jwt') {}

// Usage — cleaner than manual token verification
@UseGuards(JwtAuthGuard, RolesGuard)
@Controller('protected')
export class ProtectedController {
  @Get('me')
  getProfile(@Req() req: Request) {
    return req.user; // Populated by JwtStrategy.validate()
  }
}
```

## Related Skills

- `gateway-auth-middleware` — JWT validation, API key auth, and RBAC at the API Gateway layer (complementary to NestJS guards for multi-tier auth)
- `nextjs-auth` — NextAuth.js session management and protected routes (frontend auth that pairs with NestJS guard-protected APIs)

## Token Cost

- Pattern: 100-150 tokens
- Context7 (if needed): 1000-1500 tokens
