---
name: context7-lookup
description: On-demand external library documentation lookup with strict token budgets. Use when CLAUDE.md knowledge is insufficient for specific library features or when you need detailed API documentation.
allowed-tools: Read, Grep
---

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

---

## 4-Tier Fallback Strategy

When Context7 MCP is unavailable or fails, use this degradation path:

### Tier 1: Context7 Available (IDEAL)

**When:** MCP is running and responsive

**Action:**
```bash
# Query MCP for fresh documentation
resolve-library-id(libraryName: "nextjs")
query-docs(libraryId: "/vercel/next.js", query: "App Router data fetching")
```

**Confidence:** ✅ HIGH
**Output:** Use fresh documentation directly

---

### Tier 2: Cached Documentation (FALLBACK)

**When:** Context7 unavailable but cache exists

**Action:**
```bash
# Check cache directory
ls -la .cache/context7/nextjs-routing-*.md

# If cache exists and < 7 days old:
CACHE_DATE=$(stat -f "%Sm" -t "%Y-%m-%d" .cache/context7/nextjs-routing-2026-01-01.md)
DAYS_OLD=$(( ($(date +%s) - $(date -j -f "%Y-%m-%d" "$CACHE_DATE" +%s)) / 86400 ))

if [ $DAYS_OLD -lt 7 ]; then
  cat .cache/context7/nextjs-routing-2026-01-01.md
fi
```

**Warning Template:**
```
⚠️ Using cached Next.js docs from 2026-01-01 (3 days old)
→ Context7 MCP unavailable, using local cache
→ Verify critical claims against official docs
```

**Confidence:** ⚠️ MEDIUM
**Output:** Include cache warning in findings

---

### Tier 3: CLAUDE.md Fallback (DEGRADED)

**When:** Context7 unavailable, no cache, but CLAUDE.md has patterns

**Action:**
```bash
# Search project patterns
grep -i "next.js\|nextjs" CLAUDE.md
grep -i "app router\|data fetching" CLAUDE.md
```

**Warning Template:**
```
⚠️ UNVERIFIED - Context7 unavailable, using CLAUDE.md patterns
→ Library claims not verified against current documentation
→ CLAUDE.md may be outdated or incorrect
→ Severity downgraded: FATAL → CRITICAL
```

**Confidence:** ⚠️ LOW
**Severity Downgrade:**
- FATAL → CRITICAL
- CRITICAL → WARNING
- WARNING → WEAKNESS

**Output:** Flag as UNVERIFIED with severity downgrade

---

### Tier 4: Manual Verification (WORST CASE)

**When:** Context7 unavailable, no cache, CLAUDE.md insufficient

**Warning Template:**
```
🚨 NEEDS_MANUAL_VERIFICATION

Library: Next.js
Claim: "App Router supports server-side data fetching with fetch()"
Status: Cannot verify automatically

→ Context7 MCP unavailable
→ No cached documentation found
→ CLAUDE.md does not document this pattern

**Action Required:**
Review official documentation:
- Next.js: https://nextjs.org/docs/app/building-your-application/data-fetching
- Verify claim manually before proceeding
- Update CLAUDE.md if pattern is confirmed

**Temporary Guidance:**
Treat as UNVERIFIED. Flag for user review.
```

**Confidence:** ❌ UNKNOWN
**Output:** Block implementation, require manual verification

---

## Fallback Decision Tree

```
Context7 available?
├─ YES → Tier 1 (fresh docs, HIGH confidence)
└─ NO
   ├─ Cache exists (<7 days)?
   │  ├─ YES → Tier 2 (cached docs, MEDIUM confidence, warn)
   │  └─ NO
   │     ├─ CLAUDE.md has pattern?
   │     │  ├─ YES → Tier 3 (CLAUDE.md, LOW confidence, downgrade severity)
   │     │  └─ NO → Tier 4 (manual verification, UNKNOWN confidence, block)
```

---

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

## Token Cost

- Lookup invocation: 300 tokens
- Query encoding: 200 tokens
- Response processing: 500-1500 tokens
- **Total per lookup:** 1000-2000 tokens
- Fallback to CLAUDE.md: 50 tokens

## Anti-Patterns

- ❌ Calling Context7 for simple syntax (use local docs)
- ❌ Max tokens > 2000 (wastes context)
- ❌ Broad topics like "NestJS" (be specific)
- ❌ Forgetting to check CLAUDE.md first
- ❌ Storing results long-term (query again if needed)
