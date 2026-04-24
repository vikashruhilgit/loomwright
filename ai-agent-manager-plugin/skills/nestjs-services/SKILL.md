---
name: nestjs-services
version: "1.0.0"
lastUpdated: "2026-03"
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

## Repository Pattern Integration

Separate data access from business logic with dedicated repositories:

```typescript
// repositories/user.repository.ts
import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, FindOptionsWhere } from 'typeorm';
import { User } from '../entities/user.entity';

@Injectable()
export class UserRepository {
  constructor(
    @InjectRepository(User)
    private readonly repo: Repository<User>,
  ) {}

  async findById(id: string): Promise<User | null> {
    return this.repo.findOne({ where: { id }, relations: ['profile'] });
  }

  async findByEmail(email: string): Promise<User | null> {
    return this.repo.findOne({ where: { email } });
  }

  async findAll(filter?: FindOptionsWhere<User>): Promise<User[]> {
    return this.repo.find({ where: filter, order: { createdAt: 'DESC' } });
  }

  async create(data: Partial<User>): Promise<User> {
    const entity = this.repo.create(data);
    return this.repo.save(entity);
  }

  async update(id: string, data: Partial<User>): Promise<User> {
    await this.repo.update(id, data);
    return this.findById(id);
  }

  async delete(id: string): Promise<void> {
    await this.repo.softDelete(id); // Prefer soft delete
  }
}
```

## Error Handling (HttpException)

Use typed exceptions for consistent error responses:

```typescript
import {
  Injectable,
  NotFoundException,
  ConflictException,
  BadRequestException,
  ForbiddenException,
} from '@nestjs/common';

@Injectable()
export class UserService {
  constructor(private readonly userRepo: UserRepository) {}

  async findById(id: string): Promise<User> {
    const user = await this.userRepo.findById(id);
    if (!user) {
      throw new NotFoundException(`User with ID "${id}" not found`);
    }
    return user;
  }

  async create(dto: CreateUserDTO): Promise<User> {
    const existing = await this.userRepo.findByEmail(dto.email);
    if (existing) {
      throw new ConflictException(`Email "${dto.email}" is already registered`);
    }

    if (dto.role === 'admin' && !dto.adminCode) {
      throw new ForbiddenException('Admin registration requires an admin code');
    }

    try {
      return await this.userRepo.create(dto);
    } catch (error) {
      throw new BadRequestException(`Failed to create user: ${error.message}`);
    }
  }

  async updateEmail(id: string, newEmail: string): Promise<User> {
    const existing = await this.userRepo.findByEmail(newEmail);
    if (existing && existing.id !== id) {
      throw new ConflictException('Email already in use by another account');
    }
    return this.userRepo.update(id, { email: newEmail });
  }
}
```

## Transaction Patterns with TypeORM

Wrap multi-step mutations in database transactions:

```typescript
import { Injectable } from '@nestjs/common';
import { DataSource, QueryRunner } from 'typeorm';

@Injectable()
export class OrderService {
  constructor(
    private readonly dataSource: DataSource,
    private readonly orderRepo: OrderRepository,
    private readonly inventoryRepo: InventoryRepository,
  ) {}

  // Pattern 1: DataSource.transaction() — simple, auto-managed
  async createOrder(dto: CreateOrderDTO): Promise<Order> {
    return this.dataSource.transaction(async (manager) => {
      const order = manager.create(Order, { userId: dto.userId, status: 'pending' });
      const savedOrder = await manager.save(order);

      for (const item of dto.items) {
        const inv = await manager.findOne(Inventory, { where: { productId: item.productId } });
        if (!inv || inv.quantity < item.quantity) {
          throw new BadRequestException(`Insufficient stock for product ${item.productId}`);
        }
        inv.quantity -= item.quantity;
        await manager.save(inv);

        const lineItem = manager.create(OrderItem, {
          orderId: savedOrder.id,
          productId: item.productId,
          quantity: item.quantity,
        });
        await manager.save(lineItem);
      }

      return savedOrder;
    });
  }

  // Pattern 2: QueryRunner — manual control for complex flows
  async transferCredits(fromId: string, toId: string, amount: number): Promise<void> {
    const queryRunner = this.dataSource.createQueryRunner();
    await queryRunner.connect();
    await queryRunner.startTransaction('SERIALIZABLE');

    try {
      const sender = await queryRunner.manager.findOne(Account, { where: { id: fromId } });
      if (!sender || sender.credits < amount) {
        throw new BadRequestException('Insufficient credits');
      }

      await queryRunner.manager.update(Account, fromId, { credits: sender.credits - amount });
      await queryRunner.manager.increment(Account, { id: toId }, 'credits', amount);

      await queryRunner.commitTransaction();
    } catch (error) {
      await queryRunner.rollbackTransaction();
      throw error;
    } finally {
      await queryRunner.release();
    }
  }
}
```

## Token Cost

- Pattern: 150-200 tokens
- Context7 (if needed): 1000-1500 tokens
