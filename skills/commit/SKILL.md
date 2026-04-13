---
name: commit-skill
description: Create conventional commits linked to Beads tasks. Use when writing commit messages, linking work to issues, or ensuring conventional commit format compliance.
version: "1.0.0"
lastUpdated: "2026-03"
---

# Commit Skill

Create conventional commits linked to Beads tasks.

## Quick Rules

- **Format:** `type(scope): description`
- **Types:** `feat`, `fix`, `docs`, `refactor`, `test`, `chore`
- **Scope:** File area or module
- **Description:** What changed, not why
- **Body:** Why this change matters (optional)
- **Footer:** Link to Beads task: `Closes BD-123`

## Common Patterns

```bash
# Feature
feat(auth): add jwt token refresh endpoint
Implement refresh token endpoint with sliding window expiration.
Closes BD-45

# Bug fix
fix(gateway): correlation ID not propagated to upstream
Closes BD-67

# Refactor
refactor(nestjs): extract service validation logic
Closes BD-78

# Chore
chore: update dependencies
Closes BD-89
```

## When to Use This Skill

- Writing commit messages during implementation
- Updating TODO/task lists via commit messages
- Linking work back to Beads issues
- Conventional Commits validation

## Beads Task Linking

Always include `Closes BD-XXX` footer when task is complete:

```
feat(gateway): add request rate limiting

Implement adaptive rate limiting per client ID using
Redis sliding window algorithm. Prevents abuse while
maintaining good UX for legitimate users.

Closes BD-123
```

This auto-closes the Beads task when commit is merged.

## Type Definitions

| Type | When | Example |
|------|------|---------|
| `feat` | New feature | JWT refresh token |
| `fix` | Bug fix | Fix auth guard memory leak |
| `docs` | Documentation | Update API docs |
| `refactor` | Code restructure | Extract validation |
| `test` | Test additions | Add integration tests |
| `chore` | Maintenance | Update deps |

## Scope Guidelines

Use file paths or module names:
- `gateway` - API Gateway module
- `auth` - Authentication
- `guards` - NestJS guards
- `middleware` - Request/response middleware
- `nextjs` - Next.js specific code

## Body Guidelines

- **Why:** Explain the motivation, not the what
- **Impact:** Note any side effects
- **Testing:** How was this tested
- **Linked Issues:** Reference related Beads tasks
- **Breaking Changes:** Mark with `BREAKING CHANGE:` footer

## Anti-Patterns

- ❌ "Fix bug" (too vague)
- ❌ "Update code" (not descriptive)
- ❌ "Work on feature" (not actionable)
- ❌ No Beads link (can't track to task)
- ❌ Multiple topics in one commit (should be separate)

## Token Cost

- Invocation: 200 tokens
- Storage: Inline (minimal overhead)
- Context7: Not required










