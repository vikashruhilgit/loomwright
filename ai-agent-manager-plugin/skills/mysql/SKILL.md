---
name: mysql
description: MySQL database patterns and best practices. Covers connection setup, query optimization, indexing, and common pitfalls. Use when working with MySQL databases.
allowed-tools: [Read]
version: "1.0.0"
lastUpdated: "2026-03"
---

# MySQL Database Patterns

Best practices for MySQL database usage in applications.

## Quick Rules

- Always use parameterized queries (prevent SQL injection)
- Create indexes for frequently queried columns
- Use appropriate data types (INT vs BIGINT, VARCHAR vs TEXT)
- Set connection pool limits
- Use transactions for multi-step operations
- Never use `synchronize: true` in production

## When to Use This Skill

- Setting up MySQL connections
- Optimizing slow queries
- Designing database schema
- Troubleshooting performance issues
- Writing migrations

## Connection Setup (NestJS + TypeORM)

```typescript
// app.module.ts
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

@Module({
  imports: [
    TypeOrmModule.forRoot({
      type: 'mysql',
      host: process.env.DB_HOST || 'localhost',
      port: parseInt(process.env.DB_PORT, 10) || 3306,
      username: process.env.DB_USER,
      password: process.env.DB_PASSWORD,
      database: process.env.DB_NAME,
      entities: [__dirname + '/**/*.entity{.ts,.js}'],
      synchronize: false, // NEVER true in production
      logging: process.env.NODE_ENV === 'development',
      // Connection pool settings
      extra: {
        connectionLimit: 10,
        waitForConnections: true,
        queueLimit: 0,
      },
    }),
  ],
})
export class AppModule {}
```

## Data Types Guide

| Use Case | MySQL Type | TypeORM Decorator |
|----------|------------|-------------------|
| Auto-increment ID | `INT UNSIGNED` | `@PrimaryGeneratedColumn()` |
| UUID | `CHAR(36)` | `@Column('char', { length: 36 })` |
| Short text (<255) | `VARCHAR(n)` | `@Column({ length: n })` |
| Long text | `TEXT` | `@Column('text')` |
| Boolean | `TINYINT(1)` | `@Column('boolean')` |
| Date only | `DATE` | `@Column('date')` |
| Date + time | `DATETIME` | `@Column('datetime')` |
| Timestamp | `TIMESTAMP` | `@CreateDateColumn()` |
| Decimal money | `DECIMAL(10,2)` | `@Column('decimal', { precision: 10, scale: 2 })` |
| JSON data | `JSON` | `@Column('json')` |

## Indexing Best Practices

```sql
-- Single column index
CREATE INDEX idx_users_email ON users(email);

-- Composite index (order matters!)
CREATE INDEX idx_orders_user_status ON orders(user_id, status);

-- Unique index
CREATE UNIQUE INDEX idx_users_email_unique ON users(email);

-- Full-text search
CREATE FULLTEXT INDEX idx_posts_content ON posts(title, content);
```

**Leftmost Prefix Rule:**
```sql
-- Index: (user_id, status, created_at)
-- Uses index:
SELECT * FROM orders WHERE user_id = 1;
SELECT * FROM orders WHERE user_id = 1 AND status = 'active';
SELECT * FROM orders WHERE user_id = 1 AND status = 'active' AND created_at > '2024-01-01';

-- Does NOT use index:
SELECT * FROM orders WHERE status = 'active';  -- Skipped user_id
SELECT * FROM orders WHERE created_at > '2024-01-01';  -- Skipped user_id and status
```

## Query Optimization

### Use EXPLAIN

```sql
EXPLAIN SELECT * FROM users WHERE email = 'test@example.com';
EXPLAIN ANALYZE SELECT * FROM orders WHERE user_id = 1 ORDER BY created_at DESC;
```

### Avoid SELECT *

```typescript
// Bad
const users = await this.userRepository.find();

// Good - select only needed columns
const users = await this.userRepository.find({
  select: ['id', 'name', 'email'],
});
```

### Pagination

```typescript
// Offset-based (simple but slow for large offsets)
const users = await this.userRepository.find({
  skip: (page - 1) * limit,
  take: limit,
  order: { id: 'DESC' },
});

// Cursor-based (better for large datasets)
const users = await this.userRepository
  .createQueryBuilder('user')
  .where('user.id < :cursor', { cursor: lastId })
  .orderBy('user.id', 'DESC')
  .take(limit)
  .getMany();
```

### Avoid N+1 Queries

```typescript
// Bad - N+1 queries
const users = await this.userRepository.find();
for (const user of users) {
  const posts = await this.postRepository.find({ where: { userId: user.id } });
}

// Good - eager loading
const users = await this.userRepository.find({
  relations: ['posts'],
});

// Good - QueryBuilder with join
const users = await this.userRepository
  .createQueryBuilder('user')
  .leftJoinAndSelect('user.posts', 'post')
  .getMany();
```

## Connection Pooling

```typescript
// TypeORM config
{
  type: 'mysql',
  extra: {
    connectionLimit: 10,        // Max connections in pool
    waitForConnections: true,   // Queue requests when pool exhausted
    queueLimit: 0,              // Unlimited queue (0)
    connectTimeout: 10000,      // Connection timeout (ms)
    acquireTimeout: 10000,      // Acquire timeout (ms)
  },
}
```

## Transactions

```typescript
// Using DataSource
await this.dataSource.transaction(async (manager) => {
  await manager.save(order);
  await manager.decrement(Inventory, { productId }, 'quantity', orderQuantity);
});

// Using QueryRunner (more control)
const queryRunner = this.dataSource.createQueryRunner();
await queryRunner.connect();
await queryRunner.startTransaction();

try {
  await queryRunner.manager.save(order);
  await queryRunner.manager.decrement(Inventory, { productId }, 'quantity', orderQuantity);
  await queryRunner.commitTransaction();
} catch (err) {
  await queryRunner.rollbackTransaction();
  throw err;
} finally {
  await queryRunner.release();
}
```

## Common Pitfalls

| Issue | Problem | Solution |
|-------|---------|----------|
| N+1 queries | Multiple queries for related data | Use eager loading or JOINs |
| No connection pooling | Connection overhead | Configure pool size |
| synchronize: true in prod | Data loss risk | Use migrations only |
| No indexes on FKs | Slow JOINs | Add indexes on foreign keys |
| VARCHAR(255) everywhere | Wasted space | Size appropriately |
| SELECT * | Over-fetching data | Select specific columns |
| Large OFFSET | Slow pagination | Use cursor-based pagination |
| No transactions | Inconsistent state | Wrap multi-step ops |

## Migration Example

```typescript
// migrations/1704067200000-CreateUsersTable.ts
import { MigrationInterface, QueryRunner, Table } from 'typeorm';

export class CreateUsersTable1704067200000 implements MigrationInterface {
  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.createTable(
      new Table({
        name: 'users',
        columns: [
          {
            name: 'id',
            type: 'int',
            isPrimary: true,
            isGenerated: true,
            generationStrategy: 'increment',
          },
          {
            name: 'email',
            type: 'varchar',
            length: '255',
            isUnique: true,
          },
          {
            name: 'name',
            type: 'varchar',
            length: '100',
          },
          {
            name: 'created_at',
            type: 'timestamp',
            default: 'CURRENT_TIMESTAMP',
          },
        ],
      }),
    );

    await queryRunner.createIndex('users', new TableIndex({
      name: 'idx_users_email',
      columnNames: ['email'],
    }));
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.dropTable('users');
  }
}
```

## Quality Checklist

Before completing MySQL work:
- [ ] Parameterized queries used (no SQL injection)
- [ ] Indexes created for WHERE, JOIN, ORDER BY columns
- [ ] Connection pool configured appropriately
- [ ] Transactions used for multi-step operations
- [ ] EXPLAIN run on complex queries
- [ ] Pagination implemented for list queries
- [ ] Migrations created (not synchronize)
- [ ] Foreign key indexes added

## See Also

- `skills/nestjs-typeorm/SKILL.md` - TypeORM repository patterns

