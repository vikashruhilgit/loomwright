# Failure Escalation Rules

> Defines failure paths for all agents. Without defined escalation, agents can loop infinitely or silently fail.
> Referenced by: Supervisor, Execute Manager, Worker, Code Reviewer, QA Strategist, QA Executor.

---

## Worker Failure

```
Worker fails (WORKER_RESULT status=failed)
    ↓
Execute Manager retries ONCE in same worktree
    ↓ (retry succeeds)
    → Continue with review
    ↓ (retry fails)
    → Execute Manager escalates to Supervisor with WORKER_RESULT(status=failed)
    → Supervisor creates bug issue or skips subtask
    → Supervisor continues with remaining subtasks
```

**Rules:**
- Max 1 retry per worker in the same worktree
- Retry includes previous error context in worker prompt
- If retry fails, worker must still produce WORKER_RESULT(status=failed) with error description
- Execute Manager includes failed subtask in EXECUTE_RESULT.subtasks_failed array

---

## Execute Manager Checkpoint

```
Execute Manager hits budget limit (60 tool calls)
    ↓
Returns EXECUTE_CHECKPOINT to Supervisor
    ↓
Supervisor spawns fresh Execute Manager with resume context
    ↓ (fresh Execute Manager completes)
    → Continue to FINALIZE
    ↓ (fresh Execute Manager hits budget again → 2nd checkpoint)
    → Supervisor escalates to human
    → Saves state to .supervisor/state.md
    → Exits with resume command
```

**Rules:**
- Max 2 Execute Manager spawns per Supervisor session
- 2nd checkpoint triggers human escalation (task is too complex for current context)
- All completed worktrees are preserved across checkpoints
- Resume context includes active worktrees, completed branches, remaining subtasks

---

## Code Reviewer Decisions

```
Code Reviewer returns PASS
    → Continue; launch newly unblocked subtasks

Code Reviewer returns FAIL (attempt 1 or 2)
    → Spawn fix worker with retry context (previous issues + review feedback)
    → Re-review after fix

Code Reviewer returns FAIL (attempt 3)
    → Supervisor checkpoints and escalates to human
    → Creates issue describing persistent failure
    → Exits with resume command

Code Reviewer returns NEEDS_HUMAN
    → Supervisor pauses current subtask
    → Creates issue describing what needs human attention
    → Moves to next independent subtask (if any)
    → After 3 consecutive NEEDS_HUMAN across different subtasks:
        → Supervisor halts entire workflow
        → Exits with resume command and full issue list
```

**Rules:**
- Max 3 FAIL retries per subtask before escalation
- NEEDS_HUMAN always creates an issue for tracking
- 3 consecutive NEEDS_HUMAN = workflow halt (not just per-subtask, across the session)
- Supervisor never force-resolves review issues

---

## QA Executor Failure

```
QA Executor fails (crash, timeout, or Playwright errors)
    ↓
Reports partial QA_RESULT with status=failed or status=partial
    ↓
Skips debate loop (no Strategist audit on failed runs)
    ↓
Strategist audit (if run independently later) flags gaps
```

**Rules:**
- QA Executor always emits QA_RESULT, even on failure
- Partial results include whatever tests were generated/run before failure
- No retry — QA is non-blocking for Supervisor workflow
- If Strategist is run independently later, it can audit partial results

---

## QA Strategist Failure

```
QA Strategist fails (analysis error, incomplete classification)
    ↓
Returns partial risk classification with available data
    ↓
Non-blocking for QA Executor (Executor uses default risk levels)
    ↓
No retry needed — read-only agent with no side effects
```

**Rules:**
- QA Strategist is read-only — no retries needed, no side effects on failure
- Partial classifications are still usable (incomplete beats absent)
- If Strategist fails before QA Executor runs, Executor proceeds with default HIGH/MEDIUM/LOW risk levels
- If Strategist fails during audit mode, Executor results remain valid without verdict

---

## Supervisor Failure

```
Supervisor hits tool call budget (30 calls)
    ↓
Checkpoints current state via Context-Keeper
    ↓
Exits with resume command: /supervisor --continue

Supervisor encounters merge conflict in FINALIZE
    ↓
STOPS immediately (never force-resolves)
    ↓
Reports conflicting files
    ↓
Exits with resume command

Supervisor encounters unexpected error
    ↓
Attempts to checkpoint (best effort)
    ↓
Exits with error description and resume command
```

**Rules:**
- Supervisor always attempts to checkpoint before exit
- Merge conflicts are never auto-resolved
- State is always written to `.supervisor/state.md` before exit
- Job file moved to `failed/` on unrecoverable errors

---

## Context-Keeper Failure

```
Context-Keeper fails (state file corrupted, write error)
    ↓
Returns error to caller (Supervisor or Execute Manager)
    ↓
Caller retries once with fresh Context-Keeper spawn
    ↓ (retry fails)
    → Caller falls back to in-context state tracking
    → Logs warning: "Context-Keeper unavailable, state may not persist"
```

**Rules:**
- Context-Keeper has maxTurns: 3 — it either succeeds quickly or fails
- Caller (Supervisor/Execute Manager) retries once
- If Context-Keeper is permanently unavailable, workflow continues with degraded state persistence
- No workflow halt for Context-Keeper failure (it's a convenience, not a hard dependency)

---

## Launch Pad Failure

```
Launch Pad encounters environment blockers
    ↓
Reports blockers with fix instructions
    ↓
Does NOT offer save option
    ↓
User fixes blockers and re-runs

Launch Pad analysis fails (codebase too large, grep errors)
    ↓
Falls back to manual estimation
    ↓
Marks confidence as LOW on affected sections
    ↓
Warns user in brief
```

**Rules:**
- Environment blockers prevent brief creation entirely
- Analysis failures degrade gracefully (LOW confidence, not hard failure)
- User always reviews brief before saving

---

## Escalation Summary

| Agent | Failure Type | Max Retries | Escalation Target |
|-------|-------------|-------------|-------------------|
| Worker | Implementation failure | 1 | Execute Manager → Supervisor |
| Execute Manager | Budget exceeded | 1 (fresh spawn) | Supervisor → Human |
| Code Reviewer | FAIL decision | 3 (fix + re-review) | Supervisor → Human |
| Code Reviewer | NEEDS_HUMAN | 0 (immediate) | Supervisor → Human (3x = halt) |
| QA Executor | Test failure | 0 | Partial result (non-blocking) |
| QA Strategist | Analysis failure | 0 | Partial classification (non-blocking) |
| Supervisor | Budget/conflict | 0 | Human (checkpoint + exit) |
| Context-Keeper | State error | 1 | Degraded mode |
| Launch Pad | Env blocker | 0 | User fixes manually |
