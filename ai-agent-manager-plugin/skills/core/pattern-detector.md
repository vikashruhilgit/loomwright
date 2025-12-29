# Pattern Detector Skill

Identify and propose new patterns for CLAUDE.md updates.

## Quick Rules

- **Scope:** Detect patterns during code review or implementation
- **Proposal Location:** Comment in Beads task + memory/context.md
- **Format:** Pattern name + code example + when to use + rationale
- **Approval:** Only humans update CLAUDE.md (agents propose)
- **Threshold:** Pattern must appear 3+ times to propose

## When to Use This Skill

✓ New service pattern in NestJS controllers
✓ Consistent middleware application pattern
✓ Guard composition strategy
✓ Error handling template
✓ Test setup pattern
✓ Configuration pattern
✓ Query builder pattern

✗ One-off implementations
✗ Framework defaults (already documented)
✗ Anti-patterns to deprecate (separate process)

## Pattern Discovery Process

### 1. Identify Candidate Pattern

While reviewing code:

```typescript
// Pattern 1: Guards with metadata
@UseGuards(Guard1, Guard2)
@SetMetadata('roles', ['admin'])
export class Controller1 { }

// Pattern 2: Same guards + metadata
@UseGuards(Guard1, Guard2)
@SetMetadata('roles', ['admin'])
export class Controller2 { }

// Pattern 3: Same guards + metadata
@UseGuards(Guard1, Guard2)
@SetMetadata('roles', ['admin'])
export class Controller3 { }

→ Appears 3+ times = propose pattern
```

### 2. Extract Pattern Details

| Element | Example |
|---------|---------|
| **Name** | Guard Composition with Role Metadata |
| **Code** | `@UseGuards(AuthGuard, RoleGuard)` + `@SetMetadata()` |
| **When** | Every protected endpoint with role checks |
| **Why** | Ensures consistent auth flow, reduces duplication |
| **Location** | All controllers in auth module |
| **Trade-off** | Guards evaluated left-to-right; order matters |
| **Alternative** | Single composite guard (less flexible) |

### 3. Draft Proposal

```markdown
## Pattern Proposal: Guard Composition with Role Metadata

**Appears in:** auth.controller.ts, user.controller.ts, admin.controller.ts

**Usage:**
```typescript
@UseGuards(AuthGuard, RoleGuard)
@SetMetadata('roles', ['admin', 'manager'])
export class AdminController {
  @Post()
  createUser() { }
}
```

**When to Use:**
- All protected endpoints with role-based access
- Guards that depend on execution context
- Metadata passed between guards

**Rationale:**
- Explicit guard order prevents confusion
- Metadata separated from logic
- Easy to audit who can access what

**Trade-offs:**
- Guard order matters (left-to-right evaluation)
- Metadata keys must match guard expectations
- Not suitable for complex permission logic (use policies)

**Alternative:** Single composite guard (less flexible but simpler)

**Files:** `src/auth/auth.controller.ts:24`, `src/user/user.controller.ts:18`, `src/admin/admin.controller.ts:31`
```

### 4. Post to Beads Task

Comment on the task:
```
@codereviewer Pattern detected: Guard Composition with Role Metadata
See memory/context.md#patterns for proposal
Consider adding to CLAUDE.md once approved
```

### 5. Update memory/context.md

Add section:
```markdown
## Proposed Patterns

### Guard Composition with Role Metadata
- Appears: 3 controllers
- Proposal: [link to full proposal]
- Status: PENDING_APPROVAL
```

## Types of Patterns

### Structural Patterns

Control flow, dependency injection, module organization:

```typescript
// Pattern: Repository Pattern in NestJS
@Injectable()
export class UserRepository {
  async findById(id: string) { }
}

// Usage
@Injectable()
export class UserService {
  constructor(private userRepository: UserRepository) { }
}
```

### Behavioral Patterns

Request/response handling, guards, middleware:

```typescript
// Pattern: Authorization Guard with Context
@Injectable()
export class RoleGuard implements CanActivate {
  canActivate(context: ExecutionContext) {
    const metadata = this.reflector.get('roles', context.getHandler());
    // Check if user has roles
  }
}
```

### Data Patterns

Query construction, database access, caching:

```typescript
// Pattern: Drizzle Query with Filters
const users = await db
  .select()
  .from(usersTable)
  .where(eq(usersTable.role, 'admin'))
  .limit(10);
```

### Error Patterns

Exception handling, validation:

```typescript
// Pattern: Custom Exception + HTTP Response
@Catch(NotFoundException)
export class NotFoundExceptionFilter implements ExceptionFilter {
  catch(exception, host) {
    const response = host.switchToHttp().getResponse();
    response.status(404).json({ error: 'Not found' });
  }
}
```

## Proposal Template

```markdown
## Pattern: [Name]

**Frequency:** Appears [N] times

**Example:**
\`\`\`[language]
[Code example]
\`\`\`

**When to Use:**
- [Scenario 1]
- [Scenario 2]

**Rationale:**
- [Benefit 1]
- [Benefit 2]

**Trade-offs:**
- [Limitation 1]
- [Limitation 2]

**Alternatives:**
- [Alternative 1]: [Pros/cons]
- [Alternative 2]: [Pros/cons]

**Files:**
- [File1:Line]
- [File2:Line]
- [File3:Line]

**Status:** PENDING_APPROVAL
```

## Anti-Patterns to Flag

Conversely, flag recurring **anti-patterns** for deprecation:

```markdown
## Anti-Pattern to Remove: Explicit Error Logging

**Appears in:** auth.service.ts, user.service.ts, role.service.ts

**Current:**
```typescript
try {
  await service.doSomething();
} catch (e) {
  console.log(e);  // ← Anti-pattern
  throw e;
}
```

**Proposed:**
```typescript
try {
  await service.doSomething();
} catch (e) {
  this.logger.error(e);  // Use injected Logger
  throw e;
}
```

**Reason:** Winston logger structured, console.log stripped in prod

**Action:** Create BD-XXX to refactor
```

## Approval Workflow

1. **Agent proposes** pattern in Beads task comment
2. **Human reviews** code examples in specified files
3. **Human approves** or requests changes
4. **Human updates** CLAUDE.md (or creates BD-XXX for refactor)
5. **Pattern becomes official** guidance for future code

## Token Cost

- Pattern analysis: 200-300 tokens
- Proposal draft: 400-600 tokens
- Total: ~800 tokens per pattern
- Context7: Not required (analysis of local code)

## Integration Example

During code review:

```
CODE REVIEW: AuthController

Found pattern: Guard composition with metadata
→ Invokes pattern-detector skill
→ Detects 3+ occurrences
→ Drafts proposal for CLAUDE.md
→ Posts comment in Beads task
→ Human reviews and approves
→ Pattern added to CLAUDE.md
→ Future code reviews reference CLAUDE.md
```

## Quality Gates

✓ Pattern appears 3+ times (proven, not hypothetical)
✓ Code examples follow project style
✓ Trade-offs documented
✓ Alternatives considered
✓ Files referenced with line numbers
✓ Proposal is specific, not vague ("improve code" doesn't count)

✗ One-time implementation detail
✗ Framework default behavior
✗ Vague "good practice"
✗ No code examples
