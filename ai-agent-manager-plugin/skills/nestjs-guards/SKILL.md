---
name: nestjs-guards
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

## Token Cost

- Pattern: 100-150 tokens
- Context7 (if needed): 1000-1500 tokens
