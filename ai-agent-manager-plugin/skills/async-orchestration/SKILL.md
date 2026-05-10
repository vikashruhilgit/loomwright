---
name: async-orchestration
description: Background dispatch patterns, non-blocking polling, parallelism decisions, and git worktree lifecycle. Use when running parallel workers in Supervisor workflows.
allowed-tools: [Read, Bash]
version: "1.0.0"
lastUpdated: "2026-03"
---

# Async Orchestration Skill

Patterns for parallel task execution using background workers, git worktrees, and non-blocking polling.

## Quick Rules

- Max concurrent worktrees: `config.max_workers` (default: 2)
- Each worker gets its own git worktree (no file conflicts)
- Only dispatch workers via `run_in_background: true`
- Poll with `block: false` first; fall back to `block: true` on idle
- Sequential merge into feature branch after all workers complete
- Clean up worktrees immediately after merge

## When to Use This Skill

- Dispatching parallel implementation workers
- Managing background task collection
- Creating and managing git worktrees
- Deciding which subtasks can run in parallel
- Merging parallel work back into feature branch

---

## Parallelism Decision Logic

### Determining LAUNCHABLE vs BLOCKED

After the Orchestrator produces a subtask list with dependencies:

```
For each subtask S:
  LAUNCHABLE if:
    1. All depends_on tasks are completed (review PASS)
    2. S.files do NOT overlap with any other LAUNCHABLE subtask's files
    3. Number of active worktrees < config.max_workers

  BLOCKED if:
    1. Has unresolved depends_on (predecessor not completed), OR
    2. Files overlap with a currently LAUNCHABLE subtask, OR
    3. Active worktrees at max capacity
```

### File Overlap Detection

Parse file lists from Orchestrator output. Two subtasks overlap if they modify any of the same files.

```
subtask_a.files = [src/auth/guard.ts, src/auth/guard.spec.ts]
subtask_b.files = [src/auth/refresh.ts, src/auth/refresh.spec.ts]
subtask_c.files = [src/auth/guard.ts, src/auth/module.ts]

→ A and B: no overlap → can run in parallel
→ A and C: overlap (guard.ts) → must serialize
→ B and C: no overlap → can run in parallel
```

### Fast-Path: Skip Worktrees

If total subtasks <= 1:
- Execute inline (no worktree, no background dispatch)
- Standard sequential implementation
- Skip all worktree lifecycle

If `--sequential` flag:
- Execute all subtasks inline, sequentially
- No worktrees, no background dispatch

---

## Git Worktree Lifecycle

### Phase 2 (PLAN): Create Branches

After parallelism analysis, create branches for launchable subtasks:

```bash
# From the feature branch
git checkout feature/BD-XX-desc

# Create subtask branches (from current feature branch HEAD)
git branch feature/BD-XXa
git branch feature/BD-XXc
```

### Phase 3 (EXECUTE): Create Worktrees

```bash
# Create worktrees for parallel workers
# Path: sibling directory with subtask suffix
git worktree add ../$(basename $(pwd))-BD-XXa feature/BD-XXa
git worktree add ../$(basename $(pwd))-BD-XXc feature/BD-XXc
```

**Naming convention:** `{project-dir}-{subtask-id}`

Example:
```
my-project/                    ← main worktree (feature/BD-XX-desc)
my-project-BD-XXa/             ← worktree for subtask a
my-project-BD-XXc/             ← worktree for subtask c
```

### Phase 4 (FINALIZE): Merge and Cleanup

**Sequential merge** (order matters if subtasks have dependencies):

```bash
# Switch to feature branch
git checkout feature/BD-XX-desc

# Merge each subtask branch (in dependency order)
git merge feature/BD-XXa --no-ff -m "merge: BD-XXa implement JwtGuard"
git merge feature/BD-XXc --no-ff -m "merge: BD-XXc cookie storage"
git merge feature/BD-XXb --no-ff -m "merge: BD-XXb refresh endpoint"
```

**Cleanup:**

```bash
# Remove worktrees first, then branches
git worktree remove ../my-project-BD-XXa
git worktree remove ../my-project-BD-XXc

git branch -d feature/BD-XXa
git branch -d feature/BD-XXc
```

### Merge Conflict Handling

If merge fails:
1. **Do NOT force resolve** — escalate to human
2. Report which files conflict
3. Checkpoint current state
4. Provide resume command

```markdown
## MERGE CONFLICT

**Feature branch:** feature/BD-XX-desc
**Merging:** feature/BD-XXb
**Conflicting files:** [list]

**Options:**
1. Resolve manually, then: /supervisor --continue task: BD-XX
2. Abort merge: git merge --abort
```

---

## Background Worker Dispatch

### Spawning a Worker

```
Task(
  description: "Implement subtask BD-XXa",
  prompt: "You are an implementation worker. ...",
  subagent_type: "general-purpose",
  run_in_background: true
)
→ Returns: { task_id: "agent-xxx", output_file: "/path/to/output" }
```

**Track in Supervisor state (minimal):**
```
worker_id: agent-xxx
subtask_id: BD-XXa
output_file: /path/to/output
worktree: ../my-project-BD-XXa
status: running
```

### Worker Prompt Template

```markdown
You are an implementation worker operating in a git worktree.

**Subtask:** {subtask_id} — {title}
**Worktree path:** {worktree_path}
**Acceptance criteria:**
{criteria}

**Skill references:** {skill_refs}

**Instructions:**
1. Work ONLY in the worktree at {worktree_path}
2. Read relevant files to understand context
3. Implement the subtask meeting all acceptance criteria
4. Run tests if test infrastructure exists
5. Output a WORKER_RESULT block

{retry_context if applicable}
```

---

## Non-Blocking Polling

### Poll Loop Pattern (Execute Manager)

The poll loop runs inside the Execute Manager (not the Supervisor), with iteration limits and back-off:

```
active_workers = {worker_id: {subtask_id, output_file, worktree_path, status}}
active_reviewers = {reviewer_id: {subtask_id, output_file, worktree_path, status}}

max_iterations = 30
poll_interval = 2000    # ms, start at 2s
idle_streak = 0
tool_calls = {current count}

for iteration in 1..max_iterations:
  results_found = false

  # 1. Check running workers (non-blocking)
  for worker_id in active_workers:
    result = TaskOutput(task_id=worker_id, block=false, timeout=poll_interval)
    tool_calls += 1
    if result.is_complete:
      results_found = true
      idle_streak = 0
      poll_interval = 2000   # reset on activity

      # Prefer summary file over full TaskOutput
      summary = Read("{worktree_path}/.worker-summary.md")   # ~200 tokens
      tool_calls += 1
      # If missing: fall back to parsing full TaskOutput

      → Queue Context-Keeper batch update
      → Spawn Reviewer in background
      → Move worker to completed

  # 2. Check running reviewers (non-blocking)
  for reviewer_id in active_reviewers:
    result = TaskOutput(task_id=reviewer_id, block=false, timeout=poll_interval)
    tool_calls += 1
    if result.is_complete:
      results_found = true
      idle_streak = 0
      poll_interval = 2000

      # Prefer summary file over full TaskOutput
      review = Read("{worktree_path}/.review-summary.md")
      tool_calls += 1

      if PASS:
        → Queue CK update
        → Check if blocked subtasks now launchable
        → Launch newly launchable subtasks
      if FAIL (attempts < 3):
        → Spawn fix worker (background)
      if FAIL (attempts >= 3):
        → Flush CK batch, escalate to human
      if NEEDS_HUMAN:
        → Flush CK batch, pause, exit with EXECUTE_CHECKPOINT

  # 3. Flush Context-Keeper batch if queued
  if ck_queue has updates:
    → Task(Context-Keeper, operation: record_batch, updates: [...])
    tool_calls += 1

  # 4. Launch newly launchable subtasks
  for subtask in newly_launchable:
    if active_worktrees < max_workers:
      → Create worktree + spawn worker
      tool_calls += 2

  # 5. Back-off on idle
  if not results_found:
    idle_streak += 1
    if idle_streak >= 3:
      poll_interval = min(poll_interval * 2, 30000)  # exponential, cap 30s
    earliest = min(active_workers + active_reviewers, key=start_time)
    TaskOutput(task_id=earliest.id, block=true, timeout=poll_interval)
    tool_calls += 1

  # 6. Tool call budget check
  if tool_calls >= 55:
    → Flush CK batch
    → Output EXECUTE_CHECKPOINT and EXIT
  if tool_calls >= 48:
    poll_interval = max(poll_interval, 5000)  # longer intervals
  if tool_calls >= 36:
    # compress summaries to <100 tokens
    pass
```

### Worker Summary File Protocol

Workers write `.worker-summary.md` in their worktree before outputting WORKER_RESULT. The Execute Manager reads this file (~200 tokens) instead of parsing full TaskOutput (~5,000+ tokens):

```
# After TaskOutput confirms worker is complete:
summary = Read("{worktree_path}/.worker-summary.md")
if summary exists:
  → Use summary data for Context-Keeper recording
else:
  → Fall back to parsing full TaskOutput
```

Same pattern for reviewers with `.review-summary.md`.

### Result Collection

After TaskOutput returns:

1. Read the summary file from worktree (preferred) or parse full output (fallback)
2. Extract: files modified, test results, decision
3. Queue for Context-Keeper batch update (not individual calls)
4. Flush batch periodically or when queue has 2+ items

---

## Worker Result Protocol

### Worker Output Format

Workers MUST output a structured result block:

```markdown
## WORKER_RESULT
- subtask_id: BD-XXa
- status: completed | failed
- files_modified: [file1, file2]
- files_created: [file3]
- lines_added: 145
- lines_removed: 12
- tests_run: 8
- tests_passed: 8
- tests_failed: 0
- error: none | {error description}
- notes: {brief implementation notes}
```

### Reviewer Output Format

Reviewers MUST output a structured decision:

```markdown
## REVIEW_RESULT
- subtask_id: BD-XXa
- decision: PASS | FAIL | NEEDS_HUMAN
- issues_count: 0
- blocking_issues: 0
- high_issues: 0
- medium_issues: 0
- low_issues: 0
- issues: [{severity}: {description} at {file}:{line}]
- proposals: [{CLAUDE.md proposal description}]
```

---

## Context Budget During EXECUTE

### Execute Manager holds (isolated from Supervisor):

| Data | Tokens |
|------|--------|
| Config (max_workers, mode) | ~50 |
| Active workers (id, subtask, worktree_path) | ~100 per worker |
| Active reviewers (id, subtask, worktree_path) | ~100 per reviewer |
| Parallelism state (launchable, blocked lists) | ~100 |
| CK batch queue | ~100 |
| **Total (2 workers + 2 reviewers)** | **~550 tokens** |

### Supervisor holds during Phase 3:

| Data | Tokens |
|------|--------|
| Single Task call to Execute Manager | ~50 |
| **Total** | **~50 tokens** |

Phase 3 poll loop context stays in Execute Manager, not Supervisor. Everything else lives in the state file, managed by Context-Keeper.

---

## Dependency Materialization

BLOCKED subtasks declare `requires` against producing subtasks (see `skills/supervisor-readiness/SKILL.md` for the schema). Before spawning a BLOCKED subtask whose producers are complete, the Execute Manager must materialize each producer's outputs into the dependent worktree by **merging the producer branch into the dependent branch — never onto the main repo HEAD**.

**Materialization steps:**

1. Create the dependent's branch from `feature_branch` **as a ref only — do NOT switch the main worktree's HEAD**:
   ```bash
   git branch feature/<task>-<sub>-dep <feature_branch>
   ```
   `git checkout -b` would move the main worktree off the feature branch and break sibling parallel subtasks; use `git branch` (creates the ref without switching HEAD) instead.

2. Create a worktree for the dependent subtask:
   ```bash
   git worktree add ../<repo>-<sub>-dep feature/<task>-<sub>-dep
   ```
   Equivalent one-shot form: `git worktree add -b feature/<task>-<sub>-dep ../<repo>-<sub>-dep <feature_branch>` — both leave the main worktree's HEAD untouched.

3. Materialize each producer's outputs by merging the producer branch INTO the dependent worktree:
   ```bash
   git -C ../<repo>-<sub>-dep merge --no-ff feature/<task>-<producer-sub>
   ```
   Repeat this for every producer listed in the dependent's `requires` set (one merge per producer).

4. Only then spawn the worker into the dependent worktree.

**Invariants:**

- Merges happen in the dependent worktree only — never on the main repo HEAD
- The integration feature branch HEAD remains untouched until FINALIZE
- Each producer is merged exactly once per dependent worktree (idempotent if re-run after a clean checkout)

**Conflict policy:** If any merge conflicts during materialization, STOP immediately and escalate as a **Dependency Merge Conflict** failure mode. Do NOT auto-resolve, do NOT commit a partial merge. Treat the dependent worktree as quarantined until the user resolves.

---

## Pre-Spawn Verification Gate

After dependency materialization and **before** spawning the worker, the Execute Manager runs a verification gate that proves each declared `requires` entry actually exists in the dependent worktree. The producer branch claimed to provide an item — this gate verifies the claim against disk.

For each `requires` entry on the dependent subtask:

| `kind` | Verification check |
|--------|-------------------|
| `file` | `test -f <worktree>/<path>` — file existence |
| `symbol` | `grep -nE '<escaped name>' <worktree>/<path>` — symbol/heading/frontmatter-key presence |
| `type` | `grep -nE '(type\|interface\|class\|enum)\s+<escaped name>\b' <worktree>/<path>` — language-level type declaration |

**Pass criterion:** ALL checks for ALL `requires` entries must PASS.

**Fail handling:** If any check fails, the dependent subtask is held back (worker is NOT spawned) and an `EXECUTE_CHECKPOINT` is emitted with `adjudication_required: true` (see Scope Expansion Adjudication below). The producer's `provides` declaration was a lie or the producer drifted from its acceptance criteria — neither is something the Execute Manager can resolve unilaterally.

**Why this gate exists:** Without it, a worker would be spawned into a worktree that doesn't actually contain the symbols/types/files it expects, and would either fabricate them, fail mid-implementation, or silently drift. The gate fails fast at the boundary between producer and consumer.

---

## Scope Expansion Adjudication

When pre-spawn verification fails (a producer didn't actually emit the symbol it promised) OR a worker reports `outputs_gap` non-empty in its WORKER_RESULT, the Execute Manager emits an `EXECUTE_CHECKPOINT` with `adjudication_required: true` and presents four options to the Supervisor / user.

The Execute Manager **NEVER picks an option itself** — it always escalates to the Supervisor, which presents options to the user via `AskUserQuestion`.

**The four options:**

- **A: Re-queue producer** — retry the producing subtask with the missing outputs added to its acceptance criteria.
  - Cost: one extra worker run.
  - Risk: same gap recurs if the root cause is brief drift, not worker error.

- **B: Insert remediation subtask** — add a new subtask whose sole job is to provide the missing outputs.
  - Cost: extra subtask + extra dependency edge.
  - Risk: brief no longer matches the executed plan; downstream telemetry/audit becomes harder to interpret.

- **C: Exit to Launch Pad** — abort the run; the brief itself is incoherent and needs replanning.
  - Cost: full restart.
  - Benefit: catches structural problems early before deeper damage.

- **D: Update consumer brief** — consumer no longer needs the missing item; remove the `requires` entry.
  - Cost: silent scope reduction.
  - Risk: callers of the consumer downstream may break because the consumer no longer integrates the producer's output.

**EXECUTE_CHECKPOINT block fields:**

```yaml
adjudication_required: true
missing_outputs:
  - item: "<requires item — file path, symbol, or contract field>"
    producing_subtask: "<producer-sub>"
    check_run: "<exact verification command and its exit/output>"
adjudication_options:
  - "A: Re-queue producer"
  - "B: Insert remediation subtask"
  - "C: Exit to Launch Pad"
  - "D: Update consumer brief"
```

The Supervisor receives the checkpoint, presents the four options to the user (with the `missing_outputs` list and the `check_run` evidence), and only then re-enters Phase 3 with the chosen branch.

---

## Error Handling

| Situation | Action |
|-----------|--------|
| Worker fails (crash/timeout) | Record error, retry once, then escalate |
| Worker output unparseable | Record error, retry with clearer prompt |
| Worktree creation fails | Fall back to sequential execution |
| Worktree already exists | Remove and recreate, or reuse if clean |
| Disk space concern | Limit to 2 concurrent worktrees |
| Tool budget exceeded | Output EXECUTE_CHECKPOINT, exit |
| Summary file missing | Fall back to parsing full TaskOutput |
| Dependency merge conflict | STOP, escalate as Dependency Merge Conflict (do NOT auto-resolve) |
| Pre-spawn verification fails | Hold subtask, emit EXECUTE_CHECKPOINT with `adjudication_required: true` |
| Worker reports `outputs_gap` non-empty | Emit EXECUTE_CHECKPOINT with `adjudication_required: true` (Scope Expansion Adjudication) |

---

## Quality Checklist

Before completing async orchestration:
- [ ] Parallelism analysis correctly identifies LAUNCHABLE vs BLOCKED
- [ ] File overlap detection prevents conflicting workers
- [ ] Worktrees created in sibling directories with correct naming
- [ ] Workers receive complete prompt with worktree path
- [ ] Non-blocking polling handles all worker states
- [ ] Sequential merge preserves dependency order
- [ ] All worktrees cleaned up after merge
- [ ] Error handling covers crash, timeout, conflict
- [ ] Fast-path skips worktrees for single subtask

## See Also

- `skills/state-management/SKILL.md` - State file schema and checkpoints
- `skills/workflow-management/SKILL.md` - Workflow patterns
- `agents/worker.md` - Worker agent template
- `agents/context-keeper.md` - State management agent
