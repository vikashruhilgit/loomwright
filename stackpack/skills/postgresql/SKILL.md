---
name: postgresql
description: PostgreSQL patterns for schema design, migrations, query optimization, indexing, and connection pooling. Use when working with PostgreSQL databases.
allowed-tools: [Read, Bash]
version: "1.0.0"
lastUpdated: "2026-03"
---

# PostgreSQL

Patterns for schema design, migrations, query optimization, and operational best practices.

---

## When to Use

- Designing database schemas for new features
- Writing or reviewing migrations
- Optimizing slow queries
- Configuring connection pools
- Reviewing index strategy

## When NOT to Use

- MySQL-specific patterns — use `mysql` skill
- ORM-specific patterns — use `nestjs-typeorm` or `nestjs-drizzle`
- Caching layer — use `redis-caching`

## Core Patterns

### 1. Migration Pattern

Use timestamped, idempotent migrations:

```sql
-- migrations/20260309120000_create_users.sql
-- UP
CREATE TABLE IF NOT EXISTS users (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email         VARCHAR(255) NOT NULL,
  name          VARCHAR(255) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  role          VARCHAR(50) NOT NULL DEFAULT 'member',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT uq_users_email UNIQUE (email)
);

CREATE INDEX idx_users_role ON users (role);
CREATE INDEX idx_users_created_at ON users (created_at DESC);

-- Trigger for updated_at
CREATE OR REPLACE FUNCTION update_modified_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_modified_column();
```

Migration rules:
- Always include both UP and DOWN sections (or use a tool that manages this)
- Never modify a migration that has been applied to any environment
- Use `IF NOT EXISTS` / `IF EXISTS` for idempotency
- Test migrations against a copy of production data

### 2. Index Strategy

```sql
-- B-tree (default): equality and range queries
CREATE INDEX idx_orders_user_id ON orders (user_id);

-- Composite: queries that filter on multiple columns (leftmost prefix rule)
CREATE INDEX idx_orders_user_status ON orders (user_id, status);

-- Partial: index only relevant rows
CREATE INDEX idx_orders_pending ON orders (created_at)
  WHERE status = 'pending';

-- GIN: full-text search and JSONB containment
CREATE INDEX idx_products_tags ON products USING GIN (tags);

-- Expression: computed values
CREATE INDEX idx_users_email_lower ON users (LOWER(email));
```

Index rules:
- Index columns used in WHERE, JOIN, and ORDER BY
- Composite indexes: most selective column first
- Partial indexes save space when queries filter on a constant
- Monitor unused indexes: `pg_stat_user_indexes` where `idx_scan = 0`
- Avoid over-indexing: each index adds write overhead

### 3. Query Optimization

```sql
-- Use EXPLAIN ANALYZE to understand query plans
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT u.name, COUNT(o.id) AS order_count
FROM users u
LEFT JOIN orders o ON o.user_id = u.id
WHERE u.role = 'customer'
GROUP BY u.id
ORDER BY order_count DESC
LIMIT 20;
```

Optimization checklist:
- Check for sequential scans on large tables (should use index scan)
- Look for high `actual rows` vs `estimated rows` mismatch (stale statistics)
- Run `ANALYZE tablename` to update statistics
- Use `EXISTS` instead of `IN` for correlated subqueries
- Avoid `SELECT *` — select only needed columns
- Paginate with keyset (`WHERE id > $1 ORDER BY id LIMIT 20`) not OFFSET

### 4. Connection Pool Configuration

```typescript
// TypeORM configuration
const dataSource = new DataSource({
  type: 'postgres',
  host: process.env.DB_HOST,
  port: parseInt(process.env.DB_PORT ?? '5432'),
  username: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: true } : false,
  extra: {
    max: 20,                    // Max connections in pool
    idleTimeoutMillis: 30000,   // Close idle connections after 30s
    connectionTimeoutMillis: 5000, // Fail if connection not acquired in 5s
  },
  synchronize: false,           // NEVER true in production
  logging: process.env.NODE_ENV !== 'production' ? ['query', 'error'] : ['error'],
});
```

Pool sizing rule of thumb:
```
max_connections = (core_count * 2) + effective_spindle_count
```
For a 4-core server: `max = (4 * 2) + 1 = 9` per instance. Scale horizontally, not by increasing pool size.

### 5. Common Data Types

| Use Case | Type | Not This |
|----------|------|----------|
| Primary key | `UUID` or `BIGSERIAL` | `SERIAL` (32-bit limit) |
| Money | `NUMERIC(12,2)` | `FLOAT` / `DOUBLE` (precision loss) |
| Timestamps | `TIMESTAMPTZ` | `TIMESTAMP` (no timezone) |
| Short strings | `VARCHAR(255)` | `TEXT` (when length is bounded) |
| Arbitrary text | `TEXT` | `VARCHAR(10000)` |
| JSON data | `JSONB` | `JSON` (no indexing) |
| Boolean | `BOOLEAN` | `SMALLINT` |
| IP address | `INET` | `VARCHAR` |

## Example Implementation

A repository method using parameterized queries, keyset pagination, and transactions:

```typescript
// src/repositories/order.repository.ts
@Injectable()
export class OrderRepository {
  constructor(private readonly dataSource: DataSource) {}

  async findByUser(userId: string, cursor?: string, limit = 20): Promise<Order[]> {
    const qb = this.dataSource
      .createQueryBuilder(Order, 'o')
      .where('o.user_id = :userId', { userId })
      .orderBy('o.id', 'ASC')
      .limit(limit);

    if (cursor) {
      qb.andWhere('o.id > :cursor', { cursor });
    }
    return qb.getMany();
  }

  async cancelWithRefund(orderId: string): Promise<void> {
    await this.dataSource.transaction(async (manager) => {
      await manager.update(Order, orderId, { status: 'cancelled' });
      await manager.insert(Refund, { orderId, status: 'pending', createdAt: new Date() });
    });
  }
}
```

## Testing Approach

- Test migrations by running them against an empty database and verifying schema matches expectations
- Test queries with `EXPLAIN ANALYZE` in integration tests to confirm index usage (no sequential scans on large tables)
- Test transactions by simulating a failure mid-transaction and verifying the entire operation is rolled back
- Test connection pool behavior under load using a test that opens concurrent connections up to the pool max

## Anti-Patterns

- **`synchronize: true` in production:** Automatic schema sync can drop columns and data. Always use migrations.
- **Missing indexes on foreign keys:** JOIN performance degrades without indexes on FK columns.
- **N+1 queries:** Use JOINs or batch loading instead of looping single-row fetches.
- **Storing timestamps without timezone:** Always use `TIMESTAMPTZ`. Implicit timezone conversions cause bugs.
- **Large OFFSET pagination:** `OFFSET 10000` scans and discards 10,000 rows. Use keyset pagination.
- **Not using transactions:** Multi-step writes without transactions risk partial updates.

## Related Skills

- `mysql` — MySQL-specific patterns (comparison reference)
- `nestjs-typeorm` — TypeORM integration with NestJS
- `nestjs-drizzle` — Drizzle ORM patterns
- `redis-caching` — Caching layer in front of PostgreSQL
- `monitoring-observability` (loomwright@atelier plugin) — Database connection pool and query metrics

## Quality Gates

- [ ] All schema changes are in versioned migrations (no manual DDL)
- [ ] Foreign key columns have indexes
- [ ] Queries on large tables use EXPLAIN ANALYZE to verify index usage
- [ ] Connection pool max is sized for the deployment (not default 10)
- [ ] `TIMESTAMPTZ` used for all timestamp columns
- [ ] No `SELECT *` in application queries
- [ ] Transactions wrap multi-step writes
- [ ] `synchronize: false` in all non-local environments
