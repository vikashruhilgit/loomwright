# Session YYYY-MM-DD

**Created by: Summarizer**
**Purpose: Immutable record of what was done today**

---

## What Was Done

### Task: [Task Name]

Brief description of what was accomplished.

- **Files changed:** `file:line-line`, `file:line-line`
- **Commit(s):** `message [hash]`, `message [hash]`
- **Test results:** X pass, Y fail (or N/A)

### Task: [Another Task]

- **Files changed:** ...
- **Commit(s):** ...
- **Test results:** ...

---

## Test Results

Summary of test execution:

- **Total:** 15 pass, 0 fail
- **Coverage:** 85% (line coverage)
- **Regressions:** None detected

Or if not applicable: N/A

---

## Findings & Insights

Any new patterns, discoveries, or important learnings:

- Discovered LRU cache pattern in src/cache-v2.ts (more efficient)
- JWT expiry validation was missing (now fixed)
- Error handling follows AppError pattern (good)

---

## Blockers

What's preventing the next steps?

- Awaiting security review before deploy
- (Or: None)

---

## Next Session

What should the next agent/person pick up:

1. Code review by security team
2. Deploy to staging
3. Monitor auth failures 24h
4. Then: production deployment

---

## See Also

- **Current state:** memory/context.md
- **Today's tasks:** TODO.md
- **Project knowledge:** CLAUDE.md
- **Commits:** Use `git log` to see full details

---

## Template Notes

**What to include:**
- ✅ What files changed (with line numbers)
- ✅ What commits were made
- ✅ Test results
- ✅ New patterns discovered
- ✅ Clear next steps

**What NOT to include:**
- ❌ Secrets or sensitive data
- ❌ Vague status ("did stuff")
- ❌ Unclear or missing next steps
- ❌ Personal opinions or off-topic notes

**Immutability:** Once created, don't edit. Create a new session file tomorrow.
