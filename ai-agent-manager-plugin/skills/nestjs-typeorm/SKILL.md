---
name: nestjs-typeorm
description: Implement repository patterns with TypeORM in NestJS. Covers entities, repositories, CRUD, relations, transactions, and migrations. Use when building data access layers.
allowed-tools: [Read]
---

# NestJS Repository Patterns (TypeORM)

Repository patterns for TypeORM that follow NestJS best practices.

## Quick Rules

- Use repository pattern with `@InjectRepository`
- Define entities with decorators (`@Entity`, `@Column`, `@PrimaryGeneratedColumn`)
- Use QueryBuilder for complex queries
- Handle transactions with DataSource or QueryRunner
- Use migrations for schema changes (never `synchronize: true` in production)

## When to Use This Skill

- Building CRUD operations with TypeORM
- Complex queries with relations
- Transaction management
- Database migrations
- Entity relationship mapping

## Entity Pattern

```typescript
import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, UpdateDateColumn } from 'typeorm';

@Entity('users')
export class User {
  @PrimaryGeneratedColumn()
  id: number;

  @Column()
  name: string;

  @Column({ unique: true })
  email: string;

  @Column({ default: true })
  isActive: boolean;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
```

## Repository Pattern

```typescript
import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { User } from './user.entity';
import { CreateUserDto, UpdateUserDto } from './dto';

@Injectable()
export class UserService {
  constructor(
    @InjectRepository(User)
    private userRepository: Repository<User>,
  ) {}

  findAll(): Promise<User[]> {
    return this.userRepository.find();
  }

  findOne(id: number): Promise<User | null> {
    return this.userRepository.findOneBy({ id });
  }

  findByEmail(email: string): Promise<User | null> {
    return this.userRepository.findOneBy({ email });
  }

  create(data: CreateUserDto): Promise<User> {
    const user = this.userRepository.create(data);
    return this.userRepository.save(user);
  }

  async update(id: number, data: UpdateUserDto): Promise<User> {
    await this.userRepository.update(id, data);
    return this.findOne(id);
  }

  async remove(id: number): Promise<void> {
    await this.userRepository.delete(id);
  }
}
```

## Relations

### One-to-Many / Many-to-One

```typescript
// User has many Posts
@Entity()
export class User {
  @PrimaryGeneratedColumn()
  id: number;

  @OneToMany(() => Post, (post) => post.author)
  posts: Post[];
}

// Post belongs to User
@Entity()
export class Post {
  @PrimaryGeneratedColumn()
  id: number;

  @ManyToOne(() => User, (user) => user.posts)
  @JoinColumn({ name: 'author_id' })
  author: User;

  @Column()
  authorId: number;
}
```

### Many-to-Many

```typescript
@Entity()
export class User {
  @ManyToMany(() => Role)
  @JoinTable({
    name: 'user_roles',
    joinColumn: { name: 'user_id' },
    inverseJoinColumn: { name: 'role_id' },
  })
  roles: Role[];
}
```

## QueryBuilder for Complex Queries

```typescript
async findWithFilters(filters: UserFilters): Promise<User[]> {
  const qb = this.userRepository
    .createQueryBuilder('user')
    .leftJoinAndSelect('user.posts', 'post');

  if (filters.name) {
    qb.andWhere('user.name LIKE :name', { name: `%${filters.name}%` });
  }

  if (filters.isActive !== undefined) {
    qb.andWhere('user.isActive = :isActive', { isActive: filters.isActive });
  }

  return qb
    .orderBy('user.createdAt', 'DESC')
    .skip(filters.offset || 0)
    .take(filters.limit || 20)
    .getMany();
}
```

## Transactions

```typescript
import { DataSource } from 'typeorm';

@Injectable()
export class TransferService {
  constructor(private dataSource: DataSource) {}

  async transferFunds(fromId: number, toId: number, amount: number): Promise<void> {
    await this.dataSource.transaction(async (manager) => {
      // Deduct from sender
      await manager.decrement(Account, { id: fromId }, 'balance', amount);

      // Add to receiver
      await manager.increment(Account, { id: toId }, 'balance', amount);

      // Log transaction
      const log = manager.create(TransactionLog, { fromId, toId, amount });
      await manager.save(log);
    });
  }
}
```

## Pagination Pattern

```typescript
interface PaginatedResult<T> {
  data: T[];
  total: number;
  page: number;
  limit: number;
  totalPages: number;
}

async findPaginated(page: number, limit: number): Promise<PaginatedResult<User>> {
  const [data, total] = await this.userRepository.findAndCount({
    skip: (page - 1) * limit,
    take: limit,
    order: { createdAt: 'DESC' },
  });

  return {
    data,
    total,
    page,
    limit,
    totalPages: Math.ceil(total / limit),
  };
}
```

## Module Setup

```typescript
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { User } from './user.entity';
import { UserService } from './user.service';
import { UserController } from './user.controller';

@Module({
  imports: [TypeOrmModule.forFeature([User])],
  providers: [UserService],
  controllers: [UserController],
  exports: [UserService],
})
export class UserModule {}
```

## Common Pitfalls

| Pitfall | Solution |
|---------|----------|
| N+1 queries | Use `relations` option or QueryBuilder with joins |
| Missing indexes | Add `@Index()` decorator on frequently queried columns |
| Eager loading everything | Use `{ eager: false }` and load explicitly |
| synchronize in production | Always use migrations |
| Not handling null | Check `findOneBy` returns `null` |

## Quality Checklist

Before completing TypeORM work:
- [ ] Entities have proper column types and constraints
- [ ] Relations are correctly defined with proper cascade options
- [ ] Indexes added for query performance
- [ ] Transactions used for multi-step operations
- [ ] Pagination implemented for list endpoints
- [ ] Error handling for not found cases
- [ ] Migrations created (not synchronize)

## See Also

- `skills/mysql/SKILL.md` - MySQL-specific patterns
- `skills/nestjs-services/SKILL.md` - Service layer patterns

