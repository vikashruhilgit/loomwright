---
name: context-summarization
description: Summarize agent outputs to minimize context usage. Use after each subagent call to compress results.
allowed-tools: [Read]
---

# Context Summarization Skill

Patterns for compressing agent outputs to minimize context usage in multi-agent workflows.

## Quick Rules

- Keep summaries < 200 tokens
- Strip code snippets (can re-read if needed)
- Keep: IDs, decisions, file paths, counts
- Remove: explanations, examples, alternatives
- Use structured format for easy parsing

## When to Use This Skill

- After subagent returns results
- Before storing checkpoint data
- When context usage exceeds 70%
- Compressing error messages for escalation

## Summary Templates

### Product Owner Output

**Input:** Full story with acceptance criteria, assumptions, risks

**Summary Format:**
```
Story BD-XX: [title]
Type: [story|feature|epic]
Priority: [critical|high|medium|low]
Criteria: [N] items
Dependencies: [list or "none"]
```

**Example:**
```
Story BD-23: User authentication with JWT
Type: feature
Priority: high
Criteria: 5 items
Dependencies: BD-21 (database schema)
```

### Orchestrator Output

**Input:** Full task breakdown with subtasks, review gates, skill references

**Summary Format:**
```
Created [N] subtasks: [ID1], [ID2], [ID3]
First: [ID] - [title]
Review gates: [N]
Estimated: [time]
```

**Example:**
```
Created 3 subtasks: BD-23a, BD-23b, BD-23c
First: BD-23a - Implement JwtGuard
Review gates: 3
Estimated: 2-3 hours
```

### Implementer Output

**Input:** Full code changes with explanations

**Summary Format:**
```
Modified: [file1], [file2], [file3]
Created: [new files]
Deleted: [removed files]
Lines: +[added] -[removed]
Tests: [pass|fail] ([N] tests)
```

**Example:**
```
Modified: src/auth/auth.module.ts
Created: src/auth/jwt.guard.ts, src/auth/jwt.guard.spec.ts
Deleted: none
Lines: +145 -12
Tests: pass (8 tests)
```

### Code Reviewer Output

**Input:** Full review with issues, suggestions, CLAUDE.md proposals

**Summary Format:**
```
Decision: [PASS|FAIL|NEEDS_HUMAN]
Issues: [N] ([blocking], [high], [medium], [low])
Files: [reviewed files]
Proposals: [N] CLAUDE.md updates
```

**Example:**
```
Decision: FAIL
Issues: 3 (1 blocking, 2 high, 0 medium, 0 low)
Files: jwt.guard.ts, jwt.guard.spec.ts
Proposals: 1 CLAUDE.md update (error handling pattern)
```

### Red Team Reviewer Output

**Input:** Full adversarial audit with findings

**Summary Format:**
```
Findings: [N] ([fatal], [critical], [warning], [weakness])
Top issue: [brief description]
Risk areas: [list]
```

**Example:**
```
Findings: 5 (0 fatal, 1 critical, 2 warning, 2 weakness)
Top issue: Token expiry not validated on refresh
Risk areas: auth, session management
```

### Worker Result Output

**Input:** Full WORKER_RESULT block from background worker

**Summary Format:**
```
Worker {worker_id}: {subtask_id} {status}
Files: {modified + created count}
Lines: +{added} -{removed}
Tests: {pass|fail} ({count})
```

**Example:**
```
Worker w-001: BD-15a completed
Files: 3 (1 modified, 2 created)
Lines: +145 -3
Tests: pass (8)
```

### Context-Keeper Response

**Input:** Context-Keeper operation confirmation

**Summary Format:**
```
CK: {operation} — {confirmation}
```

**Example:**
```
CK: record_worker_result — BD-15a completed, +145 -3
CK: update_phase — EXECUTE, progress 1/3
CK: checkpoint — saved to .supervisor/ + Beads
```

## Compression Rules

### Keep

- Task/Issue IDs (BD-XX)
- Decision outcomes (PASS/FAIL/NEEDS_HUMAN)
- File paths (relative)
- Counts (issues, lines, tests)
- Status indicators
- Blocking information
- Error codes/types

### Remove

- Code snippets (can re-read files)
- Explanations (why something was done)
- Examples (how to fix)
- Alternatives (other approaches)
- Praise/encouragement
- Verbose formatting
- Redundant context

## Error Summary Format

**Input:** Full error with stack trace, context

**Summary Format:**
```
Error: [error type]
Location: [file:line]
Cause: [one-line cause]
Retry: [N]/[max]
```

**Example:**
```
Error: TypeCheck
Location: jwt.guard.ts:45
Cause: Implicit 'any' type on parameter 'token'
Retry: 1/3
```

## Checkpoint Data Compression

Compress for `.supervisor/` and optional Beads comments (< 500 tokens):

```markdown
## Supervisor Checkpoint
- Phase: [INIT|ACQUIRE|PLAN|EXECUTE|FINALIZE|LOOP]
- Progress: [X]/[Y] subtasks complete
- Branch: [branch name]
- Active worktrees: [count]
- Workers: [running count]
- Last review: [PASS|FAIL|NEEDS_HUMAN]
- Resume: /supervisor --continue task: BD-XX
```

**Avoid in checkpoints:**
- Full file contents
- Complete error traces
- Agent conversation history
- Implementation details
- Worker output details (stored in state file)

## Progressive Compression

When context exceeds thresholds:

| Context Level | Action |
|---------------|--------|
| < 70% | Normal summaries (< 200 tokens) |
| 70-85% | Aggressive compression (< 100 tokens) |
| > 85% | Minimal checkpoint only (< 50 tokens) |

**Aggressive Compression Example:**

Normal:
```
Created 3 subtasks: BD-23a, BD-23b, BD-23c
First: BD-23a - Implement JwtGuard
Review gates: 3
Estimated: 2-3 hours
```

Aggressive:
```
3 subtasks (BD-23a/b/c). Next: BD-23a
```

Minimal:
```
BD-23: 3 tasks, stage 4/9
```

## Multi-Agent Summary Chain

For complex workflows with multiple agents:

```
[PO] Story BD-23: JWT auth, 5 criteria
  ↓
[Orch] 3 subtasks: BD-23a/b/c. Launchable: a,c. Blocked: b
  ↓
[CK] State initialized, phase PLAN
  ↓
[Worker-A] BD-23a: +145 lines, tests pass (parallel)
[Worker-C] BD-23c: +67 lines, tests pass (parallel)
  ↓
[Review-A] PASS, 0 issues → BD-23b unblocked
[Review-C] PASS, 0 issues
  ↓
[Worker-B] BD-23b: +89 lines, tests pass
  ↓
[Review-B] PASS, 0 issues
  ↓
[CK] Checkpoint: 3/3 complete, phase FINALIZE
```

Total: ~80 tokens for entire parallel chain vs ~3000+ tokens for full outputs.

## Quality Checklist

Before outputting summary:
- [ ] Under 200 tokens (or threshold for context level)
- [ ] Contains all IDs and decisions
- [ ] File paths are relative
- [ ] No code snippets embedded
- [ ] Parseable by supervisor
- [ ] Resume command included if paused

## See Also

- `skills/workflow-management/SKILL.md` - Checkpoint and context patterns
- `skills/quality-checklist/SKILL.md` - Review decision criteria

