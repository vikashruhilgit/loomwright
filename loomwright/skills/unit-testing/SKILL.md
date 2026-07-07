---
name: unit-testing
description: Unit testing patterns with Jest and Vitest. Covers AAA pattern, mocking, coverage thresholds, fixtures, and snapshot testing. Use when writing or reviewing tests.
allowed-tools: [Read, Bash]
version: "1.0.0"
lastUpdated: "2026-03"
---

# Unit Testing

Patterns for writing reliable, maintainable unit tests with Jest and Vitest.

---

## When to Use

- Writing tests for new modules, services, or utilities
- Reviewing test quality and coverage during code review
- Setting up testing infrastructure for a new project
- Refactoring existing tests for maintainability

## When NOT to Use

- E2E or integration tests spanning multiple services — use `playwright-e2e`
- Database query testing — use the `mysql` or `postgresql` skills (stackpack@atelier plugin)
- Load/performance testing — use dedicated performance tools

## Core Patterns

### 1. Arrange-Act-Assert (AAA)

Every test follows three distinct sections:

```typescript
describe('UserService', () => {
  it('should return user by ID', async () => {
    // Arrange
    const mockUser = { id: '1', name: 'Alice', email: 'alice@example.com' };
    userRepository.findOne.mockResolvedValue(mockUser);

    // Act
    const result = await userService.findById('1');

    // Assert
    expect(result).toEqual(mockUser);
    expect(userRepository.findOne).toHaveBeenCalledWith({ where: { id: '1' } });
  });
});
```

### 2. Module Mocking

Mock external dependencies at the module boundary:

```typescript
// Jest
jest.mock('@/services/email.service');
const mockEmailService = jest.mocked(EmailService);

// Vitest
vi.mock('@/services/email.service');
const mockEmailService = vi.mocked(EmailService);
```

For NestJS, use the testing module:

```typescript
const module = await Test.createTestingModule({
  providers: [
    UserService,
    { provide: UserRepository, useValue: { findOne: vi.fn(), save: vi.fn() } },
    { provide: EmailService, useValue: { send: vi.fn() } },
  ],
}).compile();

const service = module.get<UserService>(UserService);
```

### 3. Test Fixtures

Centralize test data creation with factory functions:

```typescript
// test/fixtures/user.fixture.ts
export function createUserFixture(overrides: Partial<User> = {}): User {
  return {
    id: 'usr_001',
    name: 'Test User',
    email: 'test@example.com',
    role: 'member',
    createdAt: new Date('2026-01-01'),
    ...overrides,
  };
}

// In tests
const admin = createUserFixture({ role: 'admin' });
const inactive = createUserFixture({ status: 'inactive' });
```

### 4. Snapshot Testing

Use sparingly — only for serializable output that changes infrequently:

```typescript
it('should generate correct API response shape', () => {
  const response = formatUserResponse(createUserFixture());
  expect(response).toMatchSnapshot();
});
```

Update snapshots deliberately: `npx jest --updateSnapshot` or `npx vitest -u`.

### 5. Coverage Configuration

```typescript
// vitest.config.ts
export default defineConfig({
  test: {
    coverage: {
      provider: 'v8',
      reporter: ['text', 'lcov', 'json-summary'],
      thresholds: {
        branches: 80,
        functions: 80,
        lines: 80,
        statements: 80,
      },
      exclude: ['**/*.spec.ts', '**/*.test.ts', 'test/**', 'dist/**'],
    },
  },
});
```

## Example Implementation

A complete NestJS service test using fixtures, mocking, and AAA pattern:

```typescript
// src/services/user.service.spec.ts
describe('UserService', () => {
  let service: UserService;
  let userRepo: { findOne: ReturnType<typeof vi.fn>; save: ReturnType<typeof vi.fn> };
  let emailService: { send: ReturnType<typeof vi.fn> };

  beforeEach(async () => {
    userRepo = { findOne: vi.fn(), save: vi.fn() };
    emailService = { send: vi.fn() };
    const module = await Test.createTestingModule({
      providers: [
        UserService,
        { provide: UserRepository, useValue: userRepo },
        { provide: EmailService, useValue: emailService },
      ],
    }).compile();
    service = module.get(UserService);
  });

  it('should send welcome email on registration', async () => {
    const user = createUserFixture({ email: 'new@example.com' });
    userRepo.save.mockResolvedValue(user);
    emailService.send.mockResolvedValue(undefined);

    const result = await service.register({ name: user.name, email: user.email });

    expect(result).toEqual(user);
    expect(emailService.send).toHaveBeenCalledWith('new@example.com', expect.stringContaining('Welcome'));
  });
});
```

## Anti-Patterns

- **Testing implementation details:** Do not assert on private methods or internal state. Test the public API.
- **Shared mutable state between tests:** Always reset mocks in `beforeEach`. Use `vi.clearAllMocks()` or `jest.clearAllMocks()`.
- **Snapshot overuse:** Snapshots for large objects become noise. Use targeted assertions instead.
- **Ignoring async cleanup:** Always await async operations and clean up timers with `vi.useRealTimers()`.
- **Copy-paste test bodies:** Extract shared setup into `beforeEach` or fixture factories.

## Testing Approach

```bash
# Run all unit tests
npx vitest run

# Run with coverage
npx vitest run --coverage

# Run in watch mode during development
npx vitest

# Run specific file
npx vitest run src/services/user.service.spec.ts
```

## Related Skills

- `playwright-e2e` — E2E and integration testing with Playwright
- `quality-checklist` — Coverage thresholds and review criteria
- `nestjs-services` (stackpack@atelier plugin) — NestJS service patterns that need unit tests
- `error-handling` — Testing error paths and exception scenarios

## Quality Gates

- [ ] Every public method has at least one happy-path and one error-path test
- [ ] Mocks are reset between tests (no shared mutable state)
- [ ] Coverage meets threshold (branches >= 80%, lines >= 80%)
- [ ] No `any` type in test files — mock types match real interfaces
- [ ] Async tests use `await` and handle rejections
- [ ] Snapshot tests are intentional and reviewed on change
- [ ] Test names describe behavior, not implementation (`should return error when...` not `calls method X`)
