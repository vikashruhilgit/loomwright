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

## Inter-Subtask Gap / Scope Expansion

```
Pre-spawn verification gate FAILs (Execute Manager Step 2b)
    OR Worker emits WORKER_RESULT with non-empty outputs_gap
    ↓
Execute Manager emits EXECUTE_CHECKPOINT with:
    - adjudication_required: true
    - missing_outputs: [...]
    - adjudication_options:
        A. Re-queue producer (re-run the producer subtask)
        B. Insert remediation subtask (new subtask to fill the gap)
        C. Exit to Launch Pad (re-plan from scratch)
        D. Update consumer brief (reduce consumer scope)
    ↓
Supervisor pauses EXECUTE phase
    ↓
Supervisor presents 4 options to user via AskUserQuestion (NEVER auto-picks)
    ↓
User selects option → Supervisor applies it and resumes EXECUTE
```

> When option C is selected, the job is marked `failed` with `reason: inter_subtask_gap` (this string is grep-stable and is what telemetry / `state.md` will record).

**Detection:**
- Execute Manager Step 2b runs `test -f` / `grep` against each `requires` entry in the dependent subtask's brief; missing entries fail the gate
- SubagentStop hook on `worker` flags any WORKER_RESULT with non-empty `outputs_gap` (drift detection)

**Rules:**
- **NEVER retry silently** — gaps and scope expansions are real specification disagreements, not transient flakes
- Always escalate immediately; no automatic remediation
- Supervisor must use AskUserQuestion (no silent default selection)
- The dependent worktree is not modified by Execute Manager — it remains in its pre-spawn state until the user resolves

**Cross-references:**
- `agents/execute-manager.md` Step 2b (pre-spawn verification gate)
- `skills/async-orchestration/SKILL.md` §"Scope Expansion Adjudication"
- `agents/supervisor.md` §"Adjudication Handling"
- `agents/worker.md` Step 5.5 (`outputs_verified` / `outputs_gap` emission)
- `hooks/hooks.json` outputs_gap validation rule

---

## Dependency Merge Conflict

```
Execute Manager Step 2a (dependency materialization)
    ↓
git -C <dependent_worktree> merge --no-ff feature/<task>-<producer>
    ↓ (exit code != 0 with conflict)
Execute Manager emits EXECUTE_CHECKPOINT noting conflicting files
    ↓
Dependent worktree LEFT in conflicted state (for user inspection)
    ↓
Supervisor pauses EXECUTE phase
    ↓
Supervisor surfaces conflict + file list to user
    ↓
User manually resolves → Supervisor resumes EXECUTE on user signal
```

**Rules:**
- **NEVER retry** — merge conflicts between two completed producers reflect real semantic disagreement, not noise
- Execute Manager does NOT run `git merge --abort`; the worktree stays in conflicted state so the user can inspect both sides
- Supervisor never force-resolves; the user must complete the merge (or instruct Supervisor to discard the dependent worktree)

**Cross-references:**
- `agents/execute-manager.md` Step 2a (dependency materialization)
- `skills/async-orchestration/SKILL.md` §"Dependency Materialization"

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

## Launch Pad Feasibility (Phase 2.5) — Soft Gate

```
Feasibility returns GO
    → Proceed to Phase 3 (ANALYZE) silently

Feasibility returns CAUTION
    → Proceed to Phase 3
    → CAUTION findings auto-injected into Risk Assessment (Phase 5)
    → Source: "Feasibility (Phase 2.5)", Impact: MEDIUM (HIGH if scope-related)

Feasibility returns NO-GO
    → Pipeline stops
    → AskUserQuestion: "Override" | "Revise goal" | "Abort"
    → Override: proceed to Phase 3; NO-GO findings become HIGH risks in Phase 5
    → Revise: loop back to Phase 2 DISCOVER (max 1 revision)
    → Abort: exit Launch Pad without saving
```

**Rules:**
- Soft gate — user can always override NO-GO (feasibility checks are heuristic)
- Max 1 goal revision loop (prevents infinite Phase 2 ↔ 2.5 cycling)
- Override converts NO-GO findings into HIGH risks tagged with source
- CAUTION auto-proceeds (no user prompt) — informational, feeds risk assessment
- No subagent spawned — Launch Pad performs checks directly using Read/Glob/Grep

---

## Launch Pad Plan Review Failure

```
Plan Reviewer returns PASS
    → Proceed to Phase 6 (save enabled)

Plan Reviewer returns FAIL (attempt 1 or 2)
    → Launch Pad fixes issues from feedback
    → Re-assembles affected brief sections
    → Re-spawns Plan Reviewer

Plan Reviewer returns FAIL (attempt 3)
    → Launch Pad presents all unresolved issues to user
    → Options: "Refine further" or "Discard"
    → Does NOT save to pending/ (hard gate)

Plan Reviewer returns NEEDS_HUMAN
    → Launch Pad presents issues to user
    → Options: "Override and save" (user responsibility) or "Refine further" or "Discard"
```

**Rules:**
- Max 3 FAIL retries (fix + re-review)
- NEEDS_HUMAN: 0 auto-retries, user decides
- PASS enables save; NEEDS_HUMAN enables save only with explicit user override; FAIL never enables save
- Failed briefs are NEVER saved to the runnable queue

---

## Escalation Summary

| Agent | Failure Type | Max Retries | Escalation Target |
|-------|-------------|-------------|-------------------|
| Worker | Implementation failure | 1 | Execute Manager → Supervisor |
| Execute Manager | Budget exceeded | 1 (fresh spawn) | Supervisor → Human |
| Execute Manager | Inter-subtask gap / outputs_gap | 0 (immediate) | Supervisor → User AskUserQuestion (4 options) |
| Execute Manager | Dependency merge conflict | 0 (never) | Supervisor → User manual resolution |
| Code Reviewer | FAIL decision | 3 (fix + re-review) | Supervisor → Human |
| Code Reviewer | NEEDS_HUMAN | 0 (immediate) | Supervisor → Human (3x = halt) |
| QA Executor | Test failure | 0 | Partial result (non-blocking) |
| QA Strategist | Analysis failure | 0 | Partial classification (non-blocking) |
| Supervisor | Budget/conflict | 0 | Human (checkpoint + exit) |
| Context-Keeper | State error | 1 | Degraded mode |
| Launch Pad | Env blocker | 0 | User fixes manually |
| Launch Pad (Feasibility NO-GO) | Infeasible goal | 0 (user decides) | User override, revise (max 1), or abort |
| Launch Pad (Feasibility CAUTION) | Risky goal | 0 (auto-proceed) | Findings injected into Risk Assessment |
| Launch Pad (Plan Review FAIL) | FAIL decision | 3 (fix + re-review) | Block save, user refines |
| Launch Pad (Plan Review NEEDS_HUMAN) | NEEDS_HUMAN | 0 | User override or refine |
