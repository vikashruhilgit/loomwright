# NestJS Guards Skill

Implement authentication and authorization guards following NestJS patterns.

## Quick Patterns

### Basic Guard

```typescript
import { Injectable, CanActivate, ExecutionContext } from '@nestjs/common';

@Injectable()
export class AuthGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest();
    const token = request.headers.authorization?.split(' ')[1];
    return !!token;
  }
}

// Usage
@UseGuards(AuthGuard)
@Get()
getUsers() { }
```

### Guard with Dependency Injection

```typescript
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

### Guard with Metadata

```typescript
@Injectable()
export class RoleGuard implements CanActivate {
  constructor(private reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const requiredRoles = this.reflector.get<string[]>('roles', context.getHandler());
    if (!requiredRoles) return true;

    const request = context.switchToHttp().getRequest();
    const user = request.user;
    return requiredRoles.some(role => user.roles.includes(role));
  }
}

// Usage
@UseGuards(JwtGuard, RoleGuard)
@SetMetadata('roles', ['admin'])
@Delete(':id')
deleteUser(@Param('id') id: string) { }
```

### Composing Multiple Guards

```typescript
@UseGuards(JwtGuard, RoleGuard)
@Controller('admin')
export class AdminController {
  @SetMetadata('roles', ['admin'])
  @Get()
  getAdminPanel() { }
}
```

Guard evaluation order: left-to-right. First guard to return `false` short-circuits.

## Patterns

### 1. Guard Composition with Metadata

**When:** Role-based access control (RBAC)

```typescript
// Create decorator for common pattern
export const Roles = (...roles: string[]) =>
  SetMetadata('roles', roles);

// Usage
@UseGuards(JwtGuard, RoleGuard)
@Roles('admin', 'manager')
@Delete(':id')
deleteUser() { }
```

**Trade-off:** Guards evaluated left-to-right; order matters. JWT must run before RoleGuard.

### 2. Custom Decorator Guard

**When:** Complex permission logic

```typescript
@Injectable()
export class PermissionGuard implements CanActivate {
  constructor(private reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const requiredPermission = this.reflector.get<string>(
      'permission',
      context.getHandler()
    );
    if (!requiredPermission) return true;

    const request = context.switchToHttp().getRequest();
    return request.user.permissions.includes(requiredPermission);
  }
}

// Custom decorator
export const Permission = (permission: string) =>
  SetMetadata('permission', permission);

// Usage
@UseGuards(JwtGuard, PermissionGuard)
@Permission('delete:users')
@Delete(':id')
deleteUser() { }
```

### 3. Guard with Class Validator

**When:** Validating guard logic at compile-time

```typescript
@Injectable()
export class ApiKeyGuard implements CanActivate {
  constructor(private configService: ConfigService) {}

  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest();
    const apiKey = request.headers['x-api-key'];
    return apiKey === this.configService.get('API_KEY');
  }
}
```

### 4. Conditional Guard Application

**When:** Guard applies only to certain methods

```typescript
@Controller('users')
export class UserController {
  @Get() // Public
  getAll() { }

  @UseGuards(JwtGuard, RoleGuard)
  @Roles('admin')
  @Delete(':id') // Protected
  deleteUser() { }
}
```

## Advanced Topics

### Guard with Async Logic

```typescript
@Injectable()
export class AsyncGuard implements CanActivate {
  constructor(private userService: UserService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();
    const user = request.user;

    // Async database lookup
    const isActive = await this.userService.isUserActive(user.id);
    return isActive;
  }
}
```

### Global Guard

```typescript
// In module
app.useGlobalGuards(new JwtGuard());

// Or in AppModule
import { APP_GUARD } from '@nestjs/core';

@Module({
  providers: [
    {
      provide: APP_GUARD,
      useClass: JwtGuard,
    },
  ],
})
export class AppModule { }
```

### Guard with Custom Exception

```typescript
@Injectable()
export class AuthGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest();
    const token = request.headers.authorization?.split(' ')[1];

    if (!token) {
      throw new UnauthorizedException('No token provided');
    }

    return true;
  }
}
```

## When to Lookup Context7

Call context7-lookup if:
- Composing guards with complex ExecutionContext logic
- Advanced guard ordering for multiple permissions
- Integrating with external auth providers (OAuth, SAML)
- Custom metadata inheritance across nested guards

## Testing Guards

```typescript
describe('JwtGuard', () => {
  let guard: JwtGuard;
  let jwtService: JwtService;

  beforeEach(() => {
    jwtService = new JwtService();
    guard = new JwtGuard(jwtService);
  });

  it('should return true for valid token', () => {
    const context = createMockExecutionContext({
      headers: {
        authorization: 'Bearer valid.jwt.token'
      }
    });

    jest.spyOn(jwtService, 'verify').mockReturnValue({ sub: '1' });
    expect(guard.canActivate(context)).toBe(true);
  });

  it('should return false for invalid token', () => {
    const context = createMockExecutionContext({
      headers: { authorization: 'Bearer invalid' }
    });

    jest.spyOn(jwtService, 'verify').mockThrowValue(new Error());
    expect(guard.canActivate(context)).toBe(false);
  });
});
```

## Anti-Patterns

❌ Guard without error messages
```typescript
return false; // No indication why
```

✓ Guard with clear exceptions
```typescript
throw new UnauthorizedException('JWT invalid');
```

❌ Guard order matters but not documented
```typescript
@UseGuards(RoleGuard, JwtGuard) // Wrong order!
```

✓ Guard order documented
```typescript
// JwtGuard runs first to populate request.user
@UseGuards(JwtGuard, RoleGuard)
```

❌ Blocking business logic in guard
```typescript
canActivate() {
  // Don't do this - use services for logic
  const result = someComplexCalculation();
  return result;
}
```

✓ Keep guards focused on auth/authz
```typescript
@Injectable()
export class RoleGuard implements CanActivate {
  constructor(private permissionService: PermissionService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const roles = this.reflector.get('roles', context.getHandler());
    return this.permissionService.checkRoles(context.switchToHttp().getRequest().user, roles);
  }
}
```

## Token Cost

- Invocation: 150 tokens
- Guard pattern: 100-150 tokens
- Context7 lookup (if needed): 1000-1500 tokens
- **Total:** 250-1800 tokens depending on complexity

## Common Mistakes

1. **Guard evaluation order:** Guards run left-to-right; JwtGuard must be first
2. **Async guards:** Return `Promise<boolean>` not `boolean`
3. **Metadata inheritance:** Use Reflector to extract class-level metadata
4. **ExecutionContext switching:** `switchToHttp()`, `switchToWs()`, `switchToRpc()`
5. **Exception types:** Use `UnauthorizedException`, `ForbiddenException`
