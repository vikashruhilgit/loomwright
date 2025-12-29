---
name: gateway-auth-middleware
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

## Token Cost

- Pattern: 200-300 tokens
- Context7 (if needed): 1000-1500 tokens
