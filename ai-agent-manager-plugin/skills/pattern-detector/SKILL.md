---
name: pattern-detector
description: Identify and propose new patterns for CLAUDE.md updates. Use when discovering reusable code patterns that appear 3+ times, or when reviewing code for pattern consistency.
allowed-tools: Read, Grep
---

# Pattern Detector Skill

Identify and propose new patterns for CLAUDE.md updates.

## Quick Rules

- **Scope:** Detect patterns during code review or implementation
- **Proposal Location:** Comment in Beads task
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

## Token Cost

- Pattern analysis: 200-300 tokens
- Proposal draft: 400-600 tokens
- Total: ~800 tokens per pattern
- Context7: Not required (analysis of local code)








