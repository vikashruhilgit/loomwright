# Gateway Auth Middleware Skill

Implement authentication and authorization middleware for API Gateway.

## Quick Pattern (Gateway Auth Decorator)

```typescript
import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import { AuthType } from 'src/constants/auth';

// Define auth types
export enum AuthType {
  None = 'None',
  Bearer = 'Bearer',
  ApiKey = 'ApiKey',
  Basic = 'Basic',
}

// Create decorator
export const Auth = createParamDecorator(
  (authType: AuthType, context: ExecutionContext) => {
    const request = context.switchToHttp().getRequest();
    // Will be processed by AuthGuard
    return { authType, request };
  },
);

// Usage in controllers
@Controller('auth')
export class AuthController {
  @Post('sign-in')
  @Auth(AuthType.None) // Public endpoint
  async signIn(@Body() signInDTO: SignInDTO) {
    return this.authService.signIn(signInDTO);
  }

  @Get('profile')
  @Auth(AuthType.Bearer) // Requires JWT token
  async getProfile(@Req() request: Request) {
    return request.user;
  }

  @Delete('resource')
  @Auth(AuthType.ApiKey) // Requires API key
  async deleteResource() { }
}
```

## Patterns

### 1. JWT Guard Implementation

**When:** Bearer token authentication via JWT

```typescript
import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';

@Injectable()
export class JwtGuard implements CanActivate {
  constructor(private jwtService: JwtService) {}

  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest();
    const token = this.extractToken(request);

    if (!token) {
      throw new UnauthorizedException('No token provided');
    }

    try {
      const payload = this.jwtService.verify(token);
      request.user = payload;
      return true;
    } catch (error) {
      throw new UnauthorizedException('Invalid token');
    }
  }

  private extractToken(request: Request): string | undefined {
    const authHeader = request.headers.authorization;
    return authHeader?.split(' ')[1]; // Extract from "Bearer token"
  }
}
```

### 2. Multi-Auth Guard (Auth Decorator Based)

**When:** Endpoint can support multiple auth types

```typescript
@Injectable()
export class AuthGuard implements CanActivate {
  constructor(
    private jwtService: JwtService,
    private configService: ConfigService,
    private reflector: Reflector,
  ) {}

  canActivate(context: ExecutionContext): boolean {
    const authType = this.reflector.get<AuthType>('auth_type', context.getHandler());

    // If no auth decorator, allow all
    if (!authType) return true;

    // If explicitly set to None, allow all
    if (authType === AuthType.None) return true;

    const request = context.switchToHttp().getRequest();

    switch (authType) {
      case AuthType.Bearer:
        return this.verifyBearer(request);
      case AuthType.ApiKey:
        return this.verifyApiKey(request);
      case AuthType.Basic:
        return this.verifyBasic(request);
      default:
        throw new UnauthorizedException('Unknown auth type');
    }
  }

  private verifyBearer(request: Request): boolean {
    const token = request.headers.authorization?.split(' ')[1];
    if (!token) throw new UnauthorizedException('No bearer token');

    try {
      const payload = this.jwtService.verify(token);
      request.user = payload;
      return true;
    } catch (error) {
      throw new UnauthorizedException('Invalid token');
    }
  }

  private verifyApiKey(request: Request): boolean {
    const apiKey = request.headers['x-api-key'];
    if (!apiKey) throw new UnauthorizedException('No API key provided');

    const validKey = this.configService.get('API_KEY');
    if (apiKey !== validKey) {
      throw new UnauthorizedException('Invalid API key');
    }

    return true;
  }

  private verifyBasic(request: Request): boolean {
    const authHeader = request.headers.authorization;
    if (!authHeader?.startsWith('Basic ')) {
      throw new UnauthorizedException('No basic auth provided');
    }

    try {
      const credentials = Buffer.from(
        authHeader.slice(6),
        'base64'
      ).toString();
      const [username, password] = credentials.split(':');

      // Validate credentials (typically against DB)
      const valid = this.validateCredentials(username, password);
      if (!valid) throw new Error();

      request.user = { username };
      return true;
    } catch (error) {
      throw new UnauthorizedException('Invalid credentials');
    }
  }

  private validateCredentials(username: string, password: string): boolean {
    // Check against database or config
    return true;
  }
}

// Set metadata on handler
export const Auth = (authType: AuthType) =>
  SetMetadata('auth_type', authType);
```

### 3. Role-Based Access Control (RBAC) Middleware

**When:** Enforce role permissions after authentication

```typescript
@Injectable()
export class RoleGuard implements CanActivate {
  constructor(private reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const requiredRoles = this.reflector.get<string[]>(
      'required_roles',
      context.getHandler(),
    );

    if (!requiredRoles || requiredRoles.length === 0) {
      return true;
    }

    const request = context.switchToHttp().getRequest();
    const userRoles = request.user?.roles || [];

    const hasRole = requiredRoles.some(role => userRoles.includes(role));
    if (!hasRole) {
      throw new ForbiddenException('Insufficient permissions');
    }

    return true;
  }
}

// Custom decorator for roles
export const RequireRoles = (...roles: string[]) =>
  SetMetadata('required_roles', roles);

// Usage
@Controller('admin')
export class AdminController {
  @Get()
  @RequireRoles('admin')
  getAdminPanel() { }

  @Delete(':id')
  @RequireRoles('admin', 'manager')
  deleteUser() { }
}
```

### 4. Token Refresh Middleware

**When:** Manage access and refresh token lifecycle

```typescript
@Injectable()
export class TokenRefreshService {
  constructor(
    private jwtService: JwtService,
    private configService: ConfigService,
  ) {}

  generateTokens(payload: any) {
    const accessToken = this.jwtService.sign(payload, {
      secret: this.configService.get('JWT_SECRET'),
      expiresIn: '15m',
    });

    const refreshToken = this.jwtService.sign(payload, {
      secret: this.configService.get('JWT_REFRESH_SECRET'),
      expiresIn: '7d',
    });

    return { accessToken, refreshToken };
  }

  refreshAccessToken(refreshToken: string) {
    try {
      const payload = this.jwtService.verify(refreshToken, {
        secret: this.configService.get('JWT_REFRESH_SECRET'),
      });

      const newAccessToken = this.jwtService.sign(
        { sub: payload.sub, email: payload.email },
        {
          secret: this.configService.get('JWT_SECRET'),
          expiresIn: '15m',
        },
      );

      return { accessToken: newAccessToken };
    } catch (error) {
      throw new UnauthorizedException('Invalid refresh token');
    }
  }
}

@Controller('auth')
export class AuthController {
  @Post('refresh-token')
  @Auth(AuthType.None)
  @HttpCode(200)
  async refreshToken(@Body() dto: RefreshTokenDTO) {
    return this.tokenRefreshService.refreshAccessToken(dto.refreshToken);
  }
}
```

### 5. Permission Middleware (Fine-Grained)

**When:** Check specific permissions beyond roles

```typescript
@Injectable()
export class PermissionGuard implements CanActivate {
  constructor(
    private permissionService: PermissionService,
    private reflector: Reflector,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const requiredPermission = this.reflector.get<string>(
      'permission',
      context.getHandler(),
    );

    if (!requiredPermission) return true;

    const request = context.switchToHttp().getRequest();
    const user = request.user;

    const hasPermission = await this.permissionService.checkPermission(
      user.id,
      requiredPermission,
    );

    if (!hasPermission) {
      throw new ForbiddenException(
        `Permission required: ${requiredPermission}`,
      );
    }

    return true;
  }
}

export const RequirePermission = (permission: string) =>
  SetMetadata('permission', permission);

// Usage
@Controller('resources')
export class ResourceController {
  @Delete(':id')
  @RequirePermission('delete:resource')
  async deleteResource(@Param('id') id: string) { }
}
```

### 6. Rate Limiting Middleware

**When:** Prevent abuse by limiting requests per user/IP

```typescript
import { ThrottlerGuard, Throttle } from '@nestjs/throttler';

@Controller('auth')
export class AuthController {
  @Post('sign-in')
  @Throttle({ default: { limit: 5, ttl: 60000 } }) // 5 requests per minute
  @Auth(AuthType.None)
  async signIn(@Body() dto: SignInDTO) {
    return this.authService.signIn(dto);
  }
}

// Global rate limiting
// In app.module.ts
@Module({
  imports: [
    ThrottlerModule.forRoot([
      {
        ttl: 60000,
        limit: 10, // 10 requests per minute
      },
    ]),
  ],
  providers: [
    {
      provide: APP_GUARD,
      useClass: ThrottlerGuard,
    },
  ],
})
export class AppModule { }
```

## Error Handling

```typescript
@Catch(UnauthorizedException)
export class UnauthorizedExceptionFilter implements ExceptionFilter {
  catch(exception: UnauthorizedException, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse();

    response.status(401).json({
      statusCode: 401,
      message: 'Unauthorized',
      error: exception.getResponse(),
    });
  }
}

@Catch(ForbiddenException)
export class ForbiddenExceptionFilter implements ExceptionFilter {
  catch(exception: ForbiddenException, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse();

    response.status(403).json({
      statusCode: 403,
      message: 'Forbidden',
      error: exception.getResponse(),
    });
  }
}
```

## Testing Auth Middleware

```typescript
describe('AuthGuard', () => {
  let guard: AuthGuard;
  let jwtService: JwtService;

  beforeEach(() => {
    jwtService = new JwtService();
    guard = new AuthGuard(jwtService);
  });

  describe('Bearer token', () => {
    it('should verify valid JWT', () => {
      const context = createMockExecutionContext({
        headers: {
          authorization: 'Bearer valid.jwt.token'
        }
      });

      jest.spyOn(jwtService, 'verify').mockReturnValue({
        sub: '1',
        email: 'user@example.com'
      });

      expect(guard.canActivate(context)).toBe(true);
    });

    it('should reject invalid JWT', () => {
      const context = createMockExecutionContext({
        headers: { authorization: 'Bearer invalid' }
      });

      jest.spyOn(jwtService, 'verify').mockThrowValue(new Error());

      expect(() => guard.canActivate(context)).toThrow(UnauthorizedException);
    });
  });
});
```

## Anti-Patterns

❌ Storing secrets in code
```typescript
const SECRET = 'super-secret-key'; // ✗ Never!
```

✓ Use environment variables
```typescript
private secret = this.configService.get('JWT_SECRET');
```

❌ Not validating tokens
```typescript
const payload = jwt.decode(token); // ✗ Doesn't validate!
```

✓ Verify tokens
```typescript
const payload = this.jwtService.verify(token); // ✓ Validates signature
```

❌ Returning sensitive data in errors
```typescript
throw new UnauthorizedException(`Invalid token: ${error.message}`);
```

✓ Generic error messages
```typescript
throw new UnauthorizedException('Invalid credentials');
```

## Token Cost

- Invocation: 150 tokens
- Auth pattern: 200-300 tokens
- Context7 (if needed): 1000-1500 tokens
- **Total:** 350-2000 tokens

## When to Lookup Context7

- OAuth2/OpenID Connect integration
- SAML authentication flows
- Advanced JWT claims validation
- Distributed session management
