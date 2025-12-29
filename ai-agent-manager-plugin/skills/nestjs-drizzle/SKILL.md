---
name: nestjs-repository-patterns
description: Implement repository patterns with Drizzle ORM in NestJS. Covers CRUD, pagination, transactions, relations, entity mapping for legacy schemas, and optional soft delete/audit fields. Use when building data access layers.
---

# NestJS Repository Patterns (Drizzle ORM)

Repository patterns for Drizzle ORM that work with both ideal and legacy schemas.

## Design Principles

1. **Schema-Agnostic** - Work with what exists, don't assume ideal schema
2. **Optional Features** - Soft delete, audit fields are opt-in based on schema
3. **Mapping Layer** - Transform DB entities to domain models when needed

---

## 1. Base Repository Pattern

```typescript
import { Inject, Injectable } from '@nestjs/common';
import { eq, and, SQL } from 'drizzle-orm';
import { PgTable } from 'drizzle-orm/pg-core';

interface RepositoryConfig {
  softDeleteColumn?: string;  // null if schema lacks it
  timestampColumns?: { createdAt?: string; updatedAt?: string };
}

@Injectable()
export abstract class BaseRepository<TTable extends PgTable, TEntity> {
  constructor(
    @Inject('DATABASE') protected db: any,
    protected table: TTable,
    protected config: RepositoryConfig = {},
  ) {}

  protected get baseConditions(): SQL[] {
    const conditions: SQL[] = [];
    // Only filter soft-deleted if column exists
    if (this.config.softDeleteColumn && this.table[this.config.softDeleteColumn]) {
      conditions.push(eq(this.table[this.config.softDeleteColumn], null));
    }
    return conditions;
  }
}
```

---

## 2. Entity Mapping (Legacy Schemas)

When DB schema differs from domain model:

```typescript
// DB Row (what's in database)
interface UserRow {
  user_id: number;      // snake_case, numeric
  usr_name: string;     // abbreviated names
  is_del: number;       // 0/1 instead of boolean
}

// Domain Entity (what app uses)
interface User {
  id: string;
  name: string;
  isDeleted: boolean;
}

// Mapper
export const userMapper = {
  toDomain(row: UserRow): User {
    return {
      id: String(row.user_id),
      name: row.usr_name,
      isDeleted: row.is_del === 1,
    };
  },
  toDb(user: Partial<User>): Partial<UserRow> {
    const row: Partial<UserRow> = {};
    if (user.name !== undefined) row.usr_name = user.name;
    if (user.isDeleted !== undefined) row.is_del = user.isDeleted ? 1 : 0;
    return row;
  },
};
```

---

## 3. CRUD Operations

```typescript
@Injectable()
export class UserRepository extends BaseRepository<typeof users, User> {
  constructor(@Inject('DATABASE') db: any) {
    super(db, users, { softDeleteColumn: 'deletedAt' }); // null if not available
  }

  async findById(id: string): Promise<User | null> {
    const [row] = await this.db
      .select()
      .from(this.table)
      .where(and(eq(this.table.id, id), ...this.baseConditions))
      .limit(1);
    return row ? userMapper.toDomain(row) : null;
  }

  async create(data: CreateUserDTO): Promise<User> {
    const dbData = userMapper.toDb(data);
    const [row] = await this.db.insert(this.table).values(dbData).returning();
    return userMapper.toDomain(row);
  }

  async update(id: string, data: UpdateUserDTO): Promise<User | null> {
    const dbData = userMapper.toDb(data);
    const [row] = await this.db
      .update(this.table)
      .set(dbData)
      .where(eq(this.table.id, id))
      .returning();
    return row ? userMapper.toDomain(row) : null;
  }

  async delete(id: string): Promise<boolean> {
    // Soft delete if available, otherwise hard delete
    if (this.config.softDeleteColumn) {
      await this.db.update(this.table)
        .set({ [this.config.softDeleteColumn]: new Date() })
        .where(eq(this.table.id, id));
    } else {
      await this.db.delete(this.table).where(eq(this.table.id, id));
    }
    return true;
  }
}
```

---

## 4. Pagination & Filtering

```typescript
interface PaginationParams {
  cursor?: string;  // For cursor-based
  limit: number;
  offset?: number;  // For offset-based
}

async findAll(params: PaginationParams, filters?: Partial<User>): Promise<User[]> {
  const conditions = [...this.baseConditions];
  
  // Dynamic filters
  if (filters?.name) {
    conditions.push(like(this.table.name, `%${filters.name}%`));
  }
  
  // Cursor-based pagination (preferred for large datasets)
  if (params.cursor) {
    conditions.push(gt(this.table.id, params.cursor));
  }

  const rows = await this.db
    .select()
    .from(this.table)
    .where(and(...conditions))
    .orderBy(asc(this.table.id))
    .limit(params.limit)
    .offset(params.offset ?? 0);

  return rows.map(userMapper.toDomain);
}
```

---

## 5. Transactions

```typescript
async transferFunds(fromId: string, toId: string, amount: number): Promise<void> {
  await this.db.transaction(async (tx) => {
    const [from] = await tx.select().from(accounts).where(eq(accounts.id, fromId));
    if (from.balance < amount) throw new Error('Insufficient funds');

    await tx.update(accounts).set({ balance: from.balance - amount }).where(eq(accounts.id, fromId));
    await tx.update(accounts).set({ balance: sql`balance + ${amount}` }).where(eq(accounts.id, toId));
  });
}
```

---

## 6. Relations & Joins

```typescript
// One-to-many with manual join
async findWithOrders(userId: string): Promise<UserWithOrders> {
  const rows = await this.db
    .select({
      user: users,
      order: orders,
    })
    .from(users)
    .leftJoin(orders, eq(users.id, orders.userId))
    .where(eq(users.id, userId));

  // Group orders under user
  const user = userMapper.toDomain(rows[0].user);
  user.orders = rows.filter(r => r.order).map(r => orderMapper.toDomain(r.order));
  return user;
}

// Many-to-many via junction table
async findUserRoles(userId: string): Promise<Role[]> {
  const rows = await this.db
    .select({ role: roles })
    .from(userRoles)  // junction table
    .innerJoin(roles, eq(userRoles.roleId, roles.id))
    .where(eq(userRoles.userId, userId));
  return rows.map(r => roleMapper.toDomain(r.role));
}
```

---

## 7. Optional Features (Schema-Dependent)

### Soft Delete (only if schema has column)
```typescript
// Check if column exists before using
const hasSoftDelete = 'deletedAt' in users || 'is_del' in users;

// Restore soft-deleted record
async restore(id: string): Promise<void> {
  if (!this.config.softDeleteColumn) throw new Error('Soft delete not supported');
  await this.db.update(this.table)
    .set({ [this.config.softDeleteColumn]: null })
    .where(eq(this.table.id, id));
}
```

### Audit Fields (only if schema has columns)
```typescript
// Auto-set timestamps if columns exist
async create(data: CreateDTO): Promise<Entity> {
  const now = new Date();
  const dbData = {
    ...mapper.toDb(data),
    ...(this.table.createdAt && { createdAt: now }),
    ...(this.table.updatedAt && { updatedAt: now }),
  };
  const [row] = await this.db.insert(this.table).values(dbData).returning();
  return mapper.toDomain(row);
}
```

---

## When to Use

- Building data access layer with Drizzle ORM
- Working with legacy databases (mapping layer)
- Need pagination, filtering, transactions
- Optional soft delete or audit fields based on schema

## Token Cost

- Pattern: 800-1000 tokens
- Context7 (if needed): 1500-2000 tokens
