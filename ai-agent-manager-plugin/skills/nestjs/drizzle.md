# NestJS Drizzle ORM Skill

Implement database access using Drizzle ORM in NestJS repositories.

## Quick Pattern

```typescript
import { drizzle } from 'drizzle-orm/postgres-js';
import { eq } from 'drizzle-orm';
import postgres from 'postgres';
import { usersTable } from './schema';

// Setup in app.module.ts
@Module({
  providers: [
    {
      provide: 'DATABASE',
      useFactory: async (configService: ConfigService) => {
        const client = postgres(configService.get('DATABASE_URL'));
        return drizzle(client);
      },
      inject: [ConfigService],
    },
  ],
})
export class DatabaseModule { }

// Repository using Drizzle
@Injectable()
export class UserRepository {
  constructor(@Inject('DATABASE') private db: ReturnType<typeof drizzle>) {}

  async findById(id: string) {
    return this.db.select().from(usersTable).where(eq(usersTable.id, id)).limit(1);
  }

  async findAll(limit = 10, offset = 0) {
    return this.db.select().from(usersTable).limit(limit).offset(offset);
  }

  async create(data: InsertUser) {
    const [user] = await this.db.insert(usersTable).values(data).returning();
    return user;
  }

  async update(id: string, data: Partial<InsertUser>) {
    const [user] = await this.db
      .update(usersTable)
      .set(data)
      .where(eq(usersTable.id, id))
      .returning();
    return user;
  }

  async delete(id: string) {
    await this.db.delete(usersTable).where(eq(usersTable.id, id));
  }
}
```

## Schema Definition

### Basic Schema

```typescript
import { pgTable, serial, varchar, timestamp } from 'drizzle-orm/pg-core';

export const usersTable = pgTable('users', {
  id: serial('id').primaryKey(),
  email: varchar('email', { length: 255 }).notNull().unique(),
  name: varchar('name', { length: 255 }).notNull(),
  password: varchar('password', { length: 255 }).notNull(),
  createdAt: timestamp('created_at').defaultNow(),
  updatedAt: timestamp('updated_at').defaultNow(),
});

export type SelectUser = typeof usersTable.$inferSelect;
export type InsertUser = typeof usersTable.$inferInsert;
```

### Relations

```typescript
export const postsTable = pgTable('posts', {
  id: serial('id').primaryKey(),
  userId: serial('user_id').notNull().references(() => usersTable.id),
  title: varchar('title', { length: 255 }).notNull(),
  content: text('content'),
  createdAt: timestamp('created_at').defaultNow(),
});

export const usersRelations = relations(usersTable, ({ many }) => ({
  posts: many(postsTable),
}));

export const postsRelations = relations(postsTable, ({ one }) => ({
  user: one(usersTable, {
    fields: [postsTable.userId],
    references: [usersTable.id],
  }),
}));
```

## Patterns

### 1. Simple CRUD Repository

```typescript
@Injectable()
export class ProductRepository {
  constructor(@Inject('DATABASE') private db: ReturnType<typeof drizzle>) {}

  async findAll() {
    return this.db.select().from(productsTable);
  }

  async findById(id: number) {
    return this.db.select().from(productsTable).where(eq(productsTable.id, id)).limit(1);
  }

  async create(data: InsertProduct) {
    const [product] = await this.db
      .insert(productsTable)
      .values(data)
      .returning();
    return product;
  }

  async update(id: number, data: Partial<InsertProduct>) {
    const [product] = await this.db
      .update(productsTable)
      .set(data)
      .where(eq(productsTable.id, id))
      .returning();
    return product;
  }

  async delete(id: number) {
    await this.db.delete(productsTable).where(eq(productsTable.id, id));
  }
}
```

### 2. Filtering and Pagination

```typescript
@Injectable()
export class UserRepository {
  constructor(@Inject('DATABASE') private db: ReturnType<typeof drizzle>) {}

  async search(filters: {
    email?: string;
    name?: string;
    page?: number;
    limit?: number;
  }) {
    let query = this.db.select().from(usersTable);

    if (filters.email) {
      query = query.where(ilike(usersTable.email, `%${filters.email}%`));
    }

    if (filters.name) {
      query = query.where(ilike(usersTable.name, `%${filters.name}%`));
    }

    const limit = filters.limit || 10;
    const offset = ((filters.page || 1) - 1) * limit;

    return query.limit(limit).offset(offset);
  }

  async count(email?: string) {
    let query = this.db.select({ count: sql\`count(*)\` }).from(usersTable);

    if (email) {
      query = query.where(eq(usersTable.email, email));
    }

    const [result] = await query;
    return result.count;
  }
}
```

### 3. Aggregations and Grouping

```typescript
@Injectable()
export class OrderRepository {
  constructor(@Inject('DATABASE') private db: ReturnType<typeof drizzle>) {}

  async getSalesPerDay(startDate: Date, endDate: Date) {
    return this.db
      .select({
        date: sql\`DATE(${ordersTable.createdAt})\`,
        total: sql\`SUM(${ordersTable.amount})\`,
        count: sql\`COUNT(*)\`,
      })
      .from(ordersTable)
      .where(
        and(
          gte(ordersTable.createdAt, startDate),
          lte(ordersTable.createdAt, endDate)
        )
      )
      .groupBy(sql\`DATE(${ordersTable.createdAt})\`)
      .orderBy(desc(sql\`DATE(${ordersTable.createdAt})\`));
  }

  async getTopProducts(limit = 10) {
    return this.db
      .select({
        productId: orderItemsTable.productId,
        productName: productsTable.name,
        totalSold: sql\`SUM(${orderItemsTable.quantity})\`,
        totalRevenue: sql\`SUM(${orderItemsTable.price} * ${orderItemsTable.quantity})\`,
      })
      .from(orderItemsTable)
      .innerJoin(productsTable, eq(orderItemsTable.productId, productsTable.id))
      .groupBy(orderItemsTable.productId, productsTable.name)
      .orderBy(desc(sql\`SUM(${orderItemsTable.quantity})\`))
      .limit(limit);
  }
}
```

### 4. Transactions

```typescript
@Injectable()
export class OrderService {
  constructor(
    @Inject('DATABASE') private db: ReturnType<typeof drizzle>,
    private inventoryRepository: InventoryRepository,
    private paymentService: PaymentService,
  ) {}

  async createOrder(createDTO: CreateOrderDTO) {
    return this.db.transaction(async (tx) => {
      // Create order
      const [order] = await tx
        .insert(ordersTable)
        .values({
          userId: createDTO.userId,
          totalAmount: createDTO.totalAmount,
        })
        .returning();

      // Deduct inventory
      for (const item of createDTO.items) {
        await tx
          .update(inventoryTable)
          .set({
            quantity: sql\`${inventoryTable.quantity} - ${item.quantity}\`,
          })
          .where(eq(inventoryTable.productId, item.productId));
      }

      // Process payment
      await this.paymentService.processPayment({
        orderId: order.id,
        amount: createDTO.totalAmount,
      });

      return order;
    });
  }
}
```

### 5. Relations with Eager Loading

```typescript
@Injectable()
export class UserRepository {
  constructor(@Inject('DATABASE') private db: ReturnType<typeof drizzle>) {}

  async findByIdWithPosts(userId: number) {
    const users = await this.db.query.usersTable.findMany({
      where: eq(usersTable.id, userId),
      with: {
        posts: true, // Eager load posts
      },
    });
    return users[0];
  }

  async findAllWithPosts(limit = 10) {
    return this.db.query.usersTable.findMany({
      limit,
      with: {
        posts: {
          limit: 5,
          orderBy: desc(postsTable.createdAt),
        },
      },
    });
  }
}
```

### 6. Batch Operations

```typescript
@Injectable()
export class ProductRepository {
  constructor(@Inject('DATABASE') private db: ReturnType<typeof drizzle>) {}

  async bulkCreate(products: InsertProduct[]) {
    return this.db.insert(productsTable).values(products).returning();
  }

  async bulkUpdate(updates: Array<{ id: number; data: Partial<InsertProduct> }>) {
    return Promise.all(
      updates.map(({ id, data }) =>
        this.db
          .update(productsTable)
          .set(data)
          .where(eq(productsTable.id, id))
          .returning()
      )
    );
  }

  async bulkDelete(ids: number[]) {
    return this.db
      .delete(productsTable)
      .where(inArray(productsTable.id, ids));
  }
}
```

### 7. Complex Queries with Subqueries

```typescript
@Injectable()
export class UserRepository {
  constructor(@Inject('DATABASE') private db: ReturnType<typeof drizzle>) {}

  async findActiveUsersWithMultiplePosts() {
    const postCounts = this.db
      .select({
        userId: postsTable.userId,
        count: sql\`COUNT(*)\`,
      })
      .from(postsTable)
      .groupBy(postsTable.userId)
      .as('post_counts');

    return this.db
      .select()
      .from(usersTable)
      .innerJoin(postCounts, eq(usersTable.id, postCounts.userId))
      .where(
        and(
          eq(usersTable.isActive, true),
          gt(postCounts.count, 5)
        )
      );
  }
}
```

## Migration Management

```typescript
// Create migration file: migrations/001_create_users.ts
import { sql } from 'drizzle-orm';
import { Migration } from 'drizzle-orm/migrator';

export const migration: Migration = {
  sql: sql\`
    CREATE TABLE users (
      id SERIAL PRIMARY KEY,
      email VARCHAR(255) NOT NULL UNIQUE,
      name VARCHAR(255) NOT NULL,
      created_at TIMESTAMP DEFAULT NOW()
    )
  \`,
};
```

Run migrations:

```bash
# Generate migration from schema
drizzle-kit generate:pg

# Apply migrations
drizzle-kit migrate:pg

# Drop everything (development only)
drizzle-kit drop
```

## Error Handling

```typescript
@Injectable()
export class UserRepository {
  constructor(@Inject('DATABASE') private db: ReturnType<typeof drizzle>) {}

  async findByEmail(email: string) {
    try {
      const [user] = await this.db
        .select()
        .from(usersTable)
        .where(eq(usersTable.email, email));
      return user;
    } catch (error) {
      if (error.code === '23505') {
        throw new ConflictException('Email already exists');
      }
      throw error;
    }
  }

  async create(data: InsertUser) {
    try {
      const [user] = await this.db
        .insert(usersTable)
        .values(data)
        .returning();
      return user;
    } catch (error) {
      if (error.code === '23505') {
        throw new ConflictException('Email already exists');
      }
      if (error.code === '23502') {
        throw new BadRequestException('Missing required field');
      }
      throw error;
    }
  }
}
```

## Testing Repositories

```typescript
describe('UserRepository', () => {
  let repository: UserRepository;
  let db: ReturnType<typeof drizzle>;

  beforeEach(async () => {
    // Use test database
    db = drizzle(postgres(process.env.TEST_DATABASE_URL));
    repository = new UserRepository(db);
  });

  afterEach(async () => {
    // Clean up
    await db.delete(usersTable);
  });

  it('should create user', async () => {
    const user = await repository.create({
      email: 'test@example.com',
      name: 'Test User',
      password: 'hashed',
    });

    expect(user.email).toBe('test@example.com');
    expect(user.id).toBeDefined();
  });

  it('should find user by email', async () => {
    await repository.create({
      email: 'test@example.com',
      name: 'Test',
      password: 'hashed',
    });

    const user = await repository.findByEmail('test@example.com');
    expect(user).toBeDefined();
  });
});
```

## Anti-Patterns

❌ N+1 Queries
```typescript
// For each user, query their posts
const users = await this.db.select().from(usersTable);
for (const user of users) {
  user.posts = await this.db.select().from(postsTable).where(eq(postsTable.userId, user.id));
}
```

✓ Eager load relations
```typescript
const users = await this.db.query.usersTable.findMany({
  with: {
    posts: true,
  },
});
```

❌ Raw SQL with string concatenation
```typescript
const email = userInput;
const query = \`SELECT * FROM users WHERE email = '\${email}'\`; // SQL injection!
```

✓ Use parameterized queries
```typescript
const user = await this.db
  .select()
  .from(usersTable)
  .where(eq(usersTable.email, email)); // Safe
```

❌ Returning all columns
```typescript
const users = await this.db.select().from(usersTable); // May include sensitive data
```

✓ Select specific columns
```typescript
const users = await this.db
  .select({
    id: usersTable.id,
    name: usersTable.name,
    email: usersTable.email,
  })
  .from(usersTable);
```

## Token Cost

- Invocation: 150 tokens
- Pattern: 200-300 tokens
- Drizzle syntax: 100-200 tokens
- Context7 (if needed): 1000-1500 tokens
- **Total:** 450-2150 tokens

## When to Lookup Context7

- Complex query optimization
- Advanced Drizzle relational queries
- Custom SQL integration
- Database-specific features (window functions, CTEs)
