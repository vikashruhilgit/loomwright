---
name: nestjs-controllers
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

## Token Cost

- Pattern: 150-200 tokens
- Context7 (if needed): 1000-1500 tokens
