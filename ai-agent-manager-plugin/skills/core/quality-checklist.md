# Quality Checklist Skill

Pre-task and post-task quality gates (extracted from AGENT_GUIDELINES.md).

## Pre-Task Checklist

Before starting implementation:

- [ ] Task clearly defined in Beads (acceptance criteria listed)
- [ ] Dependencies checked (blocks, subtasks)
- [ ] Related CLAUDE.md patterns understood
- [ ] Test strategy defined (unit/integration/e2e)
- [ ] Framework-specific skills identified
- [ ] Token budget estimated (Context7 needed?)

## Implementation Checklist

During development:

- [ ] Follow CLAUDE.md patterns
- [ ] Use existing code patterns (don't reinvent)
- [ ] Type safety: no implicit `any`
- [ ] Test coverage ≥ 80%
- [ ] No secrets/PII in code or logs
- [ ] Input validation at system boundaries
- [ ] Error handling documented
- [ ] Performance considered (profile if needed)

## Post-Task Checklist (Code Review Gate)

Before marking complete:

- [ ] Tests pass (unit + integration)
- [ ] No linting/type errors (`npm run lint`, `npm run type-check`)
- [ ] Code follows existing patterns
- [ ] Changes minimal and focused (surgical)
- [ ] Coverage ≥ 80%; no regressions
- [ ] No secrets, debug code, console.logs
- [ ] Docs/comments updated
- [ ] Input validation in place
- [ ] Related CLAUDE.md patterns reflected

## Code Quality Standards

### 1. Quality First
- **Principle:** Thorough, well-tested, correct solutions; proven approaches
- **Check:** Does code solve the stated problem completely?
- **Test:** Write test case for each acceptance criterion

### 2. Surgical Changes
- **Principle:** Only modify what's necessary; fix one thing at a time
- **Check:** Are there unrelated changes (formatting, refactoring)?
- **Impact:** Smaller diffs = easier review + less regressions

### 3. Pattern Consistency
- **Principle:** Use existing patterns; learn codebase before implementing
- **Check:** Does code match existing service/controller/guard patterns?
- **Reference:** Point to similar code in same repo

### 4. Type Safety
- **Principle:** Strictest checking; no implicit `any`
- **Check:** All variables typed explicitly
- **Tools:** TypeScript strict mode, ESLint no-implicit-any

### 5. Security
- **Principle:** No secrets/PII in code/logs; validate inputs
- **Check:**
  - No hardcoded API keys, passwords, tokens
  - Env vars for secrets
  - Input validation at boundaries
  - Error messages don't leak sensitive info

### 6. Performance
- **Principle:** Profile before/after; document tradeoffs
- **Check:** No obvious N+1 queries, loops, or inefficiencies
- **Benchmark:** If modifying hot path, include timing data

## Language-Specific Variations

### TypeScript/NestJS

```typescript
// Quality checklist additions
✓ Decorators used correctly (@UseGuards, @UseInterceptors, etc.)
✓ Dependency injection: all services injected, no circular deps
✓ Error handling: all async/await wrapped in try/catch
✓ Tests: at least controller + service tests
✓ Swagger documentation: @ApiResponse, @ApiOperation, @ApiParam
```

### TypeScript/Next.js

```typescript
// Quality checklist additions
✓ Server vs client components properly marked
✓ Suspense boundaries for async components
✓ Layout structure follows app router conventions
✓ Error boundaries in place
✓ ISR/SSG/SSR strategy documented
✓ Image optimization used
```

### Python (MCPs)

```python
# Quality checklist additions
✓ Type hints on all functions
✓ Docstrings for public functions
✓ No hardcoded secrets
✓ Tests with mocking for external calls
✓ Logging structured (not print())
✓ Error handling: specific exception types
```

## Review Decision Matrix

| Finding | Type | Action |
|---------|------|--------|
| Missing test case | FAIL | Request test addition |
| Hardcoded secret | FAIL | Reject, require env var |
| Pattern mismatch | FAIL | Request alignment |
| Performance issue | FAIL | Request optimization |
| Minor style issue | NEEDS_HUMAN | Comment, can be fixed in follow-up |
| Good security practice | PASS | Approve |
| Tests + docs complete | PASS | Approve |

## Anti-Patterns

❌ **Type Safety**
- `any` used without comment
- `as unknown as Type` casting
- Untyped function parameters

❌ **Security**
- Credentials in env defaults (.env.example)
- `console.log(user)` in production code
- SQL strings concatenated with user input
- No input validation on API endpoints

❌ **Performance**
- `SELECT *` without column filtering
- N+1 queries in loops
- No caching on expensive operations
- Synchronous operations in hot paths

❌ **Testing**
- Tests that pass without assertions
- Mock setup that doesn't match real behavior
- No error path tests
- Coverage < 80%

## Commit Message Checklist

- [ ] Type + scope correct (feat/fix/refactor/docs/test/chore)
- [ ] Description concise (< 50 chars)
- [ ] Body explains why (not what)
- [ ] Footer links to Beads task: `Closes BD-XXX`
- [ ] No "WIP", "TODO", "FIX" in message
- [ ] Conventional Commits compliant

## Gate Outcomes

### ✓ PASS
- All checks complete
- No blockers
- Ready to merge/close task

### ✗ FAIL
- Blocking issue found (test, security, pattern)
- Developer must fix
- Re-run review after changes

### ≈ NEEDS_HUMAN
- Minor issues found
- Can be fixed in follow-up task
- Human decides if blocking or not
- Issue created for tracking (BD-XXX)

## Token Cost

- Checklist invocation: 50 tokens
- Framework-specific variations: 100-200 tokens
- Total: ~250 tokens
- Context7: Not required
