---
name: nestjs-controllers
version: "1.0.0"
lastUpdated: "2026-03"
description: Build REST controllers following NestJS and API Gateway patterns. Use when implementing HTTP endpoints, route handlers, or REST APIs with decorators.
---

# NestJS Controllers Skill

Build REST controllers following NestJS and API Gateway patterns.

## Quick Pattern

```typescript
import { Body, Controller, Get, Post } from '@nestjs/common';
import { ApiTags, ApiOperation } from '@nestjs/swagger';

@ApiTags('users')
@Controller('users')
export class UserController {
  constructor(private readonly userService: UserService) {}

  @Get()
  @ApiOperation({ summary: 'List all users' })
  async getAll() {
    return this.userService.findAll();
  }

  @Post()
  @ApiOperation({ summary: 'Create new user' })
  async create(@Body() createUserDTO: CreateUserDTO) {
    return this.userService.create(createUserDTO);
  }
}
```

## When to Use

- Standard REST endpoints for entity management
- Gateway pattern with custom auth decorator
- Nested resources (parent-child relationships)
- Query filtering with optional parameters
- File upload handling

## Validation Pipes (class-validator)

Use DTOs with class-validator decorators and the global ValidationPipe:

```typescript
// dto/create-user.dto.ts
import { IsEmail, IsString, MinLength, IsOptional, IsEnum } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export enum UserRole {
  ADMIN = 'admin',
  USER = 'user',
}

export class CreateUserDTO {
  @ApiProperty({ example: 'user@example.com' })
  @IsEmail()
  email: string;

  @ApiProperty({ minLength: 8 })
  @IsString()
  @MinLength(8)
  password: string;

  @ApiProperty({ required: false, enum: UserRole })
  @IsOptional()
  @IsEnum(UserRole)
  role?: UserRole;
}

// main.ts — enable global validation
app.useGlobalPipes(new ValidationPipe({
  whitelist: true,          // Strip non-decorated properties
  forbidNonWhitelisted: true, // Throw on unknown properties
  transform: true,          // Auto-transform payloads to DTO instances
}));
```

## Interceptors (Logging, Transform)

Apply cross-cutting concerns with interceptors:

```typescript
// interceptors/logging.interceptor.ts
import { Injectable, NestInterceptor, ExecutionContext, CallHandler, Logger } from '@nestjs/common';
import { Observable, tap } from 'rxjs';

@Injectable()
export class LoggingInterceptor implements NestInterceptor {
  private readonly logger = new Logger('HTTP');

  intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
    const req = context.switchToHttp().getRequest();
    const { method, url } = req;
    const start = Date.now();

    return next.handle().pipe(
      tap(() => {
        const ms = Date.now() - start;
        this.logger.log(`${method} ${url} ${ms}ms`);
      }),
    );
  }
}

// interceptors/transform.interceptor.ts — wrap responses
@Injectable()
export class TransformInterceptor<T> implements NestInterceptor<T, { data: T }> {
  intercept(context: ExecutionContext, next: CallHandler): Observable<{ data: T }> {
    return next.handle().pipe(
      map((data) => ({
        data,
        timestamp: new Date().toISOString(),
        statusCode: context.switchToHttp().getResponse().statusCode,
      })),
    );
  }
}

// Apply at controller or global level
@UseInterceptors(LoggingInterceptor, TransformInterceptor)
@Controller('users')
export class UserController { /* ... */ }
```

## Response DTOs

Explicitly define what gets returned to clients:

```typescript
// dto/user-response.dto.ts
import { Exclude, Expose } from 'class-transformer';

export class UserResponseDTO {
  @Expose() id: string;
  @Expose() email: string;
  @Expose() name: string;
  @Expose() role: string;
  @Exclude() password: string;  // Never sent to client
  @Exclude() internalNotes: string;

  constructor(partial: Partial<UserResponseDTO>) {
    Object.assign(this, partial);
  }
}

// Controller usage with ClassSerializerInterceptor
@UseInterceptors(ClassSerializerInterceptor)
@Controller('users')
export class UserController {
  @Get(':id')
  async findOne(@Param('id') id: string): Promise<UserResponseDTO> {
    const user = await this.userService.findById(id);
    return new UserResponseDTO(user);
  }
}
```

## API Versioning

Support multiple API versions simultaneously:

```typescript
// main.ts — enable URI versioning
app.enableVersioning({
  type: VersioningType.URI,  // /v1/users, /v2/users
  defaultVersion: '1',
});

// Controller with versioning
@Controller('users')
export class UserController {
  @Get()
  @Version('1')
  findAllV1() {
    return this.userService.findAllLegacy();
  }

  @Get()
  @Version('2')
  findAllV2() {
    return this.userService.findAllWithPagination();
  }
}

// Or version the entire controller
@Controller({ path: 'users', version: '2' })
export class UserV2Controller {
  @Get()
  findAll(@Query() query: PaginationDTO) {
    return this.userService.findAllPaginated(query);
  }
}
```

## Token Cost

- Pattern: 150-200 tokens
- Context7 (if needed): 1000-1500 tokens
