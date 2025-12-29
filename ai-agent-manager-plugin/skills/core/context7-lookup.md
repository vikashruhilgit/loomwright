# Context7 Lookup Skill

On-demand external library documentation with strict token budgets.

## Quick Rules

- **Max Tokens:** 2000 per lookup (strict)
- **Topics:** Specific library feature/module only
- **Lazy Loading:** Only call when CLAUDE.md knowledge insufficient
- **Timeout:** 5 seconds max
- **Fallback:** If unavailable, use CLAUDE.md instead

## When to Use This Skill

✓ Need NestJS guard composition patterns
✓ Looking up TypeScript decorator usage
✓ Finding Next.js data fetching options
✓ Understanding ORM query patterns
✓ Checking API endpoint specifications

✗ General questions answerable from CLAUDE.md
✗ Simple syntax lookups (use docs locally)
✗ Framework comparisons (broad context)
✗ When offline or MCP unavailable

## Lookup Strategy

### 1. Prepare Query

**Format:** `library_name + specific_topic`

```
# Good
NestJS + Guard composition with ExecutionContext

# Bad
NestJS guards (too broad)
how do I write guards (too vague)
```

### 2. Check Token Estimate

| Topic | Est. Tokens | Examples |
|-------|-------------|----------|
| Single decorator | 800-1200 | @UseGuards composition |
| Module patterns | 1000-1500 | Microservice module setup |
| Middleware example | 600-1000 | Custom request middleware |
| Query patterns | 900-1400 | Drizzle query filters |
| ORM relations | 1200-1800 | TypeORM relations |

### 3. Invoke Context7

```python
# Pseudo-code
lookup = context7_lookup(
  library="NestJS",
  topic="Guard composition with ExecutionContext",
  max_tokens=2000
)

# Use only if tokens_used <= 2000
if lookup.tokens_used > 2000:
  fallback_to_claude_md()
```

### 4. Extract Patterns

From returned docs, extract:
- Concrete code examples (copy-paste safe)
- Edge cases or gotchas
- Performance implications
- Security considerations

## Library Mappings

| Library | Format | Common Topics |
|---------|--------|----------------|
| NestJS | `/nestjs/{version}` | guards, pipes, interceptors, modules |
| Next.js | `/nextjs/{version}` | routing, data-fetching, middleware, auth |
| TypeScript | `/typescript/{version}` | decorators, generics, types |
| Drizzle | `/drizzle/latest` | queries, relations, migrations |
| PostgreSQL | `/postgresql/{version}` | indexes, queries, transactions |

## Fallback Patterns

If Context7 unavailable:

```markdown
## Quick NestJS Guard Pattern (from CLAUDE.md)

Guards in NestJS follow CanActivate interface:

```typescript
import { Injectable, CanActivate, ExecutionContext } from '@nestjs/common';

@Injectable()
export class MyGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest();
    // Guard logic
    return true;
  }
}
```

For more details, see:
- `mcps/context7-lookup/nestjs-guards.md`
- NestJS docs: guards section
```

## Token Cost

- Lookup invocation: 300 tokens
- Query encoding: 200 tokens
- Response processing: 500-1500 tokens
- **Total per lookup:** 1000-2000 tokens
- Fallback to CLAUDE.md: 50 tokens

## Error Handling

| Error | Fallback |
|-------|----------|
| MCP timeout | Use CLAUDE.md |
| Library not found | Check CLAUDE.md patterns |
| Token overflow | Reduce scope, try narrower topic |
| Network unavailable | Use local docs |

## Example Workflow

**Scenario:** NestJS guard with multiple conditions

```
1. Check CLAUDE.md skills/nestjs/guards.md for common patterns
   → "Guard composition, Guard ordering, Metadata inheritance"

2. If pattern not in CLAUDE.md, invoke Context7:
   context7_lookup(
     library="NestJS",
     topic="Guard composition with multiple CanActivate implementations",
     max_tokens=1500
   )

3. Extract code patterns:
   - How to compose multiple guards
   - ExecutionContext usage
   - Metadata passing between guards

4. Apply to code:
   @UseGuards(Guard1, Guard2, Guard3)
   export class MyController { }
```

## Anti-Patterns

- ❌ Calling Context7 for simple syntax (use local docs)
- ❌ Max tokens > 2000 (wastes context)
- ❌ Broad topics like "NestJS" (be specific)
- ❌ Forgetting to check CLAUDE.md first
- ❌ Storing results long-term (query again if needed)

## Integration with Skills

Skills call this when they hit knowledge gaps:

```
skill: nestjs/guards.md
line 45: "For advanced guard composition patterns, use Context7"
→ invoke context7-lookup(library="NestJS", topic="Advanced guard composition")
```
