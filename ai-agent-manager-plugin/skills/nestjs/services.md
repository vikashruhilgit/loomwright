# NestJS Services Skill

Implement business logic using the Provider pattern.

## Quick Pattern

```typescript
import { Injectable, NotFoundException } from '@nestjs/common';
import { SignInDTO } from './dtos/sign-in.dto';
import { SignInProvider } from './provider/sign-in.provider';
import { RefreshTokenProvider } from './provider/refresh-token.provider';

@Injectable()
export class AuthService {
  constructor(
    private readonly signInProvider: SignInProvider,
    private readonly refreshTokenProvider: RefreshTokenProvider,
  ) {}

  async signIn(signInDTO: SignInDTO) {
    return this.signInProvider.signIn(signInDTO);
  }

  async refreshToken(refreshTokenDTO: RefreshTokenDTO) {
    return this.refreshTokenProvider.refreshToken(refreshTokenDTO);
  }
}
```

## Patterns

### 1. Service with Provider Pattern

**When:** Service delegates to specialized providers for complex logic

```typescript
@Injectable()
export class UserService {
  constructor(
    private readonly userRepository: UserRepository,
    private readonly encryptionProvider: EncryptionProvider,
    private readonly emailProvider: EmailProvider,
  ) {}

  async create(createDTO: CreateUserDTO) {
    // Validate data
    if (await this.userRepository.findByEmail(createDTO.email)) {
      throw new ConflictException('Email already exists');
    }

    // Encrypt password using provider
    const hashedPassword = await this.encryptionProvider.hash(createDTO.password);

    // Create user
    const user = await this.userRepository.create({
      ...createDTO,
      password: hashedPassword,
    });

    // Send welcome email using provider
    await this.emailProvider.sendWelcome(user.email);

    return user;
  }
}
```

### 2. Service with Repository Dependency Injection

**When:** Service manages CRUD operations via repository

```typescript
@Injectable()
export class ProductService {
  constructor(private readonly productRepository: ProductRepository) {}

  async findAll(filters?: { category?: string; minPrice?: number }) {
    return this.productRepository.find(filters);
  }

  async findById(id: string) {
    const product = await this.productRepository.findById(id);
    if (!product) {
      throw new NotFoundException(`Product ${id} not found`);
    }
    return product;
  }

  async create(createDTO: CreateProductDTO) {
    return this.productRepository.create(createDTO);
  }

  async update(id: string, updateDTO: UpdateProductDTO) {
    const product = await this.findById(id);
    return this.productRepository.update(id, updateDTO);
  }

  async delete(id: string) {
    const product = await this.findById(id);
    return this.productRepository.delete(id);
  }
}
```

### 3. Service with Caching

**When:** Performance optimization for frequently accessed data

```typescript
import { Cache } from '@nestjs/cache-manager';

@Injectable()
export class CategoryService {
  constructor(
    private readonly categoryRepository: CategoryRepository,
    @Inject(CACHE_MANAGER) private cacheManager: Cache,
  ) {}

  async findAll() {
    const cached = await this.cacheManager.get('all_categories');
    if (cached) return cached;

    const categories = await this.categoryRepository.findAll();
    await this.cacheManager.set('all_categories', categories, 3600000);
    return categories;
  }

  async update(id: string, updateDTO: UpdateCategoryDTO) {
    const category = await this.categoryRepository.update(id, updateDTO);
    // Invalidate cache
    await this.cacheManager.del('all_categories');
    return category;
  }
}
```

### 4. Service with Logging

**When:** Audit trail for important operations

```typescript
import { Logger } from '@nestjs/common';

@Injectable()
export class PaymentService {
  private logger = new Logger(PaymentService.name);

  constructor(
    private readonly paymentRepository: PaymentRepository,
    private readonly notificationService: NotificationService,
  ) {}

  async processPayment(paymentDTO: ProcessPaymentDTO) {
    this.logger.log(`Processing payment for order ${paymentDTO.orderId}`);

    try {
      const payment = await this.paymentRepository.create(paymentDTO);
      this.logger.log(`Payment created: ${payment.id}`);

      await this.notificationService.sendConfirmation(paymentDTO.email);
      return payment;
    } catch (error) {
      this.logger.error(`Payment failed: ${error.message}`, error.stack);
      throw error;
    }
  }
}
```

### 5. Service with Transaction Management

**When:** Multiple operations must succeed or fail together

```typescript
@Injectable()
export class OrderService {
  constructor(
    private readonly orderRepository: OrderRepository,
    private readonly inventoryRepository: InventoryRepository,
    private readonly paymentService: PaymentService,
  ) {}

  async createOrder(createDTO: CreateOrderDTO) {
    // Use transaction if DB supports it (Drizzle example)
    try {
      const order = await this.orderRepository.create(createDTO);

      for (const item of createDTO.items) {
        await this.inventoryRepository.decreaseStock(item.productId, item.quantity);
      }

      await this.paymentService.processPayment({
        orderId: order.id,
        amount: createDTO.totalAmount,
      });

      return order;
    } catch (error) {
      // Transaction rolled back automatically
      throw error;
    }
  }
}
```

### 6. Service with Event Emission

**When:** Triggering actions after successful operations

```typescript
@Injectable()
export class RegistrationService {
  constructor(
    private readonly userRepository: UserRepository,
    private eventEmitter: EventEmitter2,
  ) {}

  async register(registerDTO: RegisterDTO) {
    const user = await this.userRepository.create(registerDTO);

    // Emit event for listeners
    this.eventEmitter.emit(
      'user.registered',
      { userId: user.id, email: user.email }
    );

    return user;
  }
}

@Injectable()
export class EmailService {
  constructor(private eventEmitter: EventEmitter2) {}

  @OnEvent('user.registered')
  async handleUserRegistered(payload: { email: string }) {
    await this.sendWelcomeEmail(payload.email);
  }
}
```

## Dependency Injection

Services use constructor injection pattern:

```typescript
@Injectable()
export class MyService {
  // Private readonly dependencies injected via constructor
  constructor(
    private readonly repository: MyRepository,
    private readonly otherService: OtherService,
  ) {}

  async doSomething() {
    return this.repository.findAll();
  }
}
```

**Module registration:**

```typescript
@Module({
  providers: [MyService, MyRepository, OtherService],
  exports: [MyService], // Export for other modules
})
export class MyModule {}
```

## Error Handling

Use NestJS exceptions for HTTP responses:

```typescript
@Injectable()
export class UserService {
  async findById(id: string) {
    const user = await this.userRepository.findById(id);

    if (!user) {
      throw new NotFoundException(`User ${id} not found`);
    }

    if (!user.isActive) {
      throw new ForbiddenException('User account is inactive');
    }

    return user;
  }

  async update(id: string, updateDTO: UpdateUserDTO) {
    if (await this.userRepository.findByEmail(updateDTO.email)) {
      throw new ConflictException('Email already in use');
    }

    return this.userRepository.update(id, updateDTO);
  }
}
```

**Common exceptions:**

| Exception | HTTP | Use |
|-----------|------|-----|
| `NotFoundException` | 404 | Resource not found |
| `BadRequestException` | 400 | Invalid input |
| `UnauthorizedException` | 401 | Auth required |
| `ForbiddenException` | 403 | No permission |
| `ConflictException` | 409 | Resource conflict |
| `InternalServerErrorException` | 500 | Unexpected error |

## Testing Services

```typescript
describe('UserService', () => {
  let service: UserService;
  let repository: UserRepository;

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      providers: [
        UserService,
        {
          provide: UserRepository,
          useValue: {
            findById: jest.fn(),
            create: jest.fn(),
            update: jest.fn(),
            delete: jest.fn(),
          },
        },
      ],
    }).compile();

    service = module.get(UserService);
    repository = module.get(UserRepository);
  });

  describe('findById', () => {
    it('should return user if found', async () => {
      const user = { id: '1', name: 'John' };
      jest.spyOn(repository, 'findById').mockResolvedValue(user);

      expect(await service.findById('1')).toEqual(user);
    });

    it('should throw NotFoundException if not found', async () => {
      jest.spyOn(repository, 'findById').mockResolvedValue(null);

      await expect(service.findById('1')).rejects.toThrow(NotFoundException);
    });
  });
});
```

## Anti-Patterns

❌ Service too large (god object)
```typescript
@Injectable()
export class AppService {
  // 500 lines of mixed concerns
  async handleUsers() { }
  async handleProducts() { }
  async handleOrders() { }
  async handlePayments() { }
}
```

✓ Separate concerns
```typescript
@Injectable()
export class UserService { /* User logic */ }

@Injectable()
export class ProductService { /* Product logic */ }

@Injectable()
export class OrderService { /* Order logic */ }

@Injectable()
export class PaymentService { /* Payment logic */ }
```

❌ Circular dependencies
```typescript
// ServiceA → ServiceB → ServiceC → ServiceA (cycle!)
```

✓ Clear dependency hierarchy
```typescript
// ServiceA → Repository
// ServiceB → ServiceA (uses results)
```

❌ No error handling
```typescript
async findById(id: string) {
  return this.repository.findById(id); // May return undefined
}
```

✓ Explicit error handling
```typescript
async findById(id: string) {
  const user = await this.repository.findById(id);
  if (!user) throw new NotFoundException();
  return user;
}
```

## Token Cost

- Invocation: 150 tokens
- Service pattern: 150-200 tokens
- Error handling: 50-100 tokens
- Context7 (if needed): 1000-1500 tokens
- **Total:** 350-2000 tokens

## When to Lookup Context7

- Complex transaction management
- Advanced caching strategies
- Event-driven architecture patterns
- Circular dependency resolution
