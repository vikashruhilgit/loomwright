---
name: commit-skill
description: Create conventional commits linked to Beads tasks. Use when writing commit messages, linking work to issues, or ensuring conventional commit format compliance.
version: "1.1.0"
lastUpdated: "2026-06"
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

## Passing the Message to git — No Code Fences (CRITICAL)

The ```` ```bash ```` / ```` ``` ```` fences shown throughout this skill are **documentation formatting only**. They are **NEVER part of the commit message.** When you call `git commit`, the message text must begin directly with the conventional-commit subject — never with a fence.

- **The first line IS the subject** and must be the real headline (e.g. `feat(scope): summary`). It must NOT be a ```` ``` ```` fence, a ```` ```bash ```` line, or a blank line.
- **Never wrap the commit message in a markdown code block.** If a fence character is the first line, git records ```` ``` ```` as the commit *subject* and shoves the real headline into the body. (Observed in the wild: a PR whose title and every commit headline were literally ```` ``` ````, with the true subject buried in the body.)
- **Multi-line messages:** pass the subject and body as separate `-m` flags, or pipe a fence-free message via `git commit -F -` / a heredoc — do not paste a fenced block.

````bash
# ✅ Correct — subject first; body as a second -m
git commit -m "feat(auth): add jwt token refresh endpoint" -m "Implement refresh token endpoint with sliding window expiration.

Closes BD-45"

# ✅ Correct — multi-line via heredoc; the message has NO fences inside it
git commit -F - <<'EOF'
feat(auth): add jwt token refresh endpoint

Implement refresh token endpoint with sliding window expiration.

Closes BD-45
EOF

# ❌ WRONG — the literal ``` line becomes the git commit subject
git commit -m '```bash
feat(auth): add jwt token refresh endpoint

Closes BD-45
```'
````

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
- ❌ Wrapping the message in a ```` ``` ```` / ```` ```bash ```` code fence (the fence line becomes the git subject — see "Passing the Message to git" above)

## Token Cost

- Invocation: 200 tokens
- Storage: Inline (minimal overhead)
- Context7: Not required










