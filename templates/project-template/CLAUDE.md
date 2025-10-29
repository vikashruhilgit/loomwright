# [Project Name] Codebase Knowledge

**Update this file with your project's specific patterns, structure, and conventions.**

---

## Structure

Describe your project directory layout:

```
src/
  ├── auth/          — Authentication logic
  ├── api/           — API endpoints
  ├── models/        — Data models
  ├── utils/         — Helper functions
  └── middleware/    — Express/request middleware

tests/
  ├── unit/          — Unit tests
  ├── integration/   — Integration tests
  └── fixtures/      — Test data

config/
  ├── database.js    — DB config
  ├── env.js         — Environment variables
  └── server.js      — Server config
```

---

## Technology Stack

List the key technologies used:

- **Language:** Node.js 18+ / Python 3.10+ / etc.
- **Framework:** Express 4.x / FastAPI / Django / etc.
- **Database:** PostgreSQL 14 / MongoDB / DynamoDB / etc.
- **Testing:** Jest / pytest / Mocha / etc.
- **Package Manager:** npm / pip / yarn / etc.
- **Linting/Formatting:** ESLint / Prettier / pylint / etc.

### Key Libraries

- `jsonwebtoken` — JWT auth (what version?)
- `bcryptjs` — Password hashing
- `express` — HTTP server
- `dotenv` — Environment config

---

## Key Patterns & Conventions

Document how things are done in this project:

### Error Handling

How are errors handled?

```javascript
// Example: Use AppError class with context
throw new AppError('Invalid JWT', { code: 'JWT_INVALID', statusCode: 401 });
```

### Logging

How are logs structured?

```javascript
// Example: Include context, exclude PII
logger.info('User login', { userId: user.id, ip: req.ip });
```

### Cache Invalidation

How is caching handled?

```javascript
// Example: Call CacheManager.flush() after changes
await updateUser(id, data);
CacheManager.flush(`user:${id}`);
```

### Database Queries

Any specific patterns?

```javascript
// Example: Use prepared statements, avoid N+1
const users = await User.find().populate('roles');
```

### Testing

What's the testing convention?

```javascript
// Example: Arrange-Act-Assert with Jest
describe('Auth', () => {
  it('should reject expired tokens', () => {
    const token = createToken({ exp: Date.now() - 1000 });
    expect(() => decode(token)).toThrow('Expired');
  });
});
```

### API Endpoints

Any naming/structure conventions?

```
GET    /api/v1/users
POST   /api/v1/users
GET    /api/v1/users/:id
PUT    /api/v1/users/:id
DELETE /api/v1/users/:id
```

---

## Common Pitfalls & Gotchas

Things agents should watch out for:

- **Cache Invalidation:** Always call `CacheManager.flush()` after updates
- **JWT Tokens:** Always check expiry (`token.exp`) before decoding
- **Error Messages:** Never include PII or internal details in error responses
- **Tests:** Must cover edge cases (empty, null, boundary conditions)
- **Database:** Use transactions for multi-step operations
- **Secrets:** Never hardcode API keys; use `process.env` variables

---

## Quick Commands

Common development tasks:

```bash
# Install dependencies
npm install

# Run tests (all)
npm test

# Run single test file
npm test -- auth.spec.js

# Type checking (if TypeScript)
npm run type-check

# Linting
npm run lint

# Format code
npm run format

# Build
npm run build

# Run locally
npm start

# Run in dev mode (with watch)
npm run dev
```

---

## Recent Changes / Notes

Track what's changed in this project recently:

- **2025-10-29:** Added JWT expiry validation (src/auth.ts)
- **2025-10-27:** Refactored cache logic to src/cache-v2.ts (LRU pattern)
- **2025-10-20:** Migrated to Express 4.18

---

## Questions for Agents

If unsure, ask about:

- Should this change follow the cache pattern in src/cache.js or src/cache-v2.ts?
- Is error message safe to show to users?
- Do we have a test for this edge case?
- Does this need a database migration?

---

## See Also

- **Project setup & agent usage:** agent-manager/README.md
- **Code quality guidelines:** agent-manager/AGENT_GUIDELINES.md
- **Today's tasks:** TODO.md
- **Current state:** memory/context.md
- **Session history:** memory/session/
