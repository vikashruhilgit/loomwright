---
name: nestjs-services
description: Implement business logic using the Provider pattern in NestJS. Use when creating services with dependency injection, business logic, or database interactions.
---

# NestJS Services Skill

Implement business logic using the Provider pattern.

## Quick Pattern

```typescript
import { Injectable, NotFoundException } from '@nestjs/common';

@Injectable()
export class UserService {
  constructor(
    private readonly userRepository: UserRepository,
  ) {}

  async findById(id: string) {
    const user = await this.userRepository.findById(id);
    if (!user) {
      throw new NotFoundException(`User ${id} not found`);
    }
    return user;
  }

  async create(createDTO: CreateUserDTO) {
    return this.userRepository.create(createDTO);
  }
}
```

## When to Use

- Service with Provider pattern (delegate to specialized providers)
- Service with Repository dependency injection
- Service with caching
- Service with logging and error handling
- Service with event emission

## Token Cost

- Pattern: 150-200 tokens
- Context7 (if needed): 1000-1500 tokens
