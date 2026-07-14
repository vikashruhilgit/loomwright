---
name: async-orchestration
description: Background dispatch patterns, non-blocking polling, parallelism decisions, and git worktree lifecycle. Use when running parallel workers in Supervisor workflows. Part 2 — the Supervisor Phase 4 FINALIZE protocol (pre-merge safety gate, sequential merge, worktree cleanup, commit/push/PR creation, PR-base self-verify), the verbatim Subagent Spawn Contracts, and the worktree-lifecycle phase sequence, moved from agents/supervisor.md.
allowed-tools: [Read, Bash]
version: "1.2.0"
lastUpdated: "2026-07-14"
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

### Phase 3 (EXECUTE — Execute Manager Step 2a): Create Branches

After Phase 2's parallelism analysis, the **Execute Manager** creates branches for launchable subtasks at Phase 3 entry (its Step 2a) — never the Supervisor in Phase 2; Phase 2 (PLAN) runs no git commands (the same ownership invariant stated in Part 2 §"Git Worktree Lifecycle (phase sequence)"):

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

      # Parse CODE_REVIEW_RESULT from the reviewer's TaskOutput
      # (no summary file — the Code Reviewer is read-only and cannot write one)
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

Reviewers have NO summary file — the Code Reviewer is read-only (`disallowedTools: Write, Edit`); parse `CODE_REVIEW_RESULT` from its TaskOutput directly.

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

**EXECUTE_CHECKPOINT block fields** (adjudication-specific additions — the emission must ALSO carry the hook-required base fields `schema_version`, `completed_so_far`, `remaining`, `resume_context`, `reason`):

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

---

# Part 2 — Supervisor FINALIZE Protocol, Spawn Contracts & Worktree Lifecycle (moved from `agents/supervisor.md`)

> **Provenance & authority:** the three sections below were moved VERBATIM from
> `agents/supervisor.md` (slice D of the supervisor prompt refactor, following the
> `self-heal-advisory` Part 2 precedent). Zero behavior change: every gate, command
> shape, bound, and grep-stable string keeps identical semantics. `agents/supervisor.md`
> keeps the short Phase 4 stanza (entry/exit conditions, the mandatory 4-point pre-merge
> safety gate, the merge-conflict STOP rule, the PR-base self-verify requirement, and the
> phase Output block), the "Agents Spawned by Supervisor" table + Summary Extraction
> rules, and the worktree-ownership invariant (branches + worktrees are created by the
> Execute Manager in Phase 3 Step 2a, never in Phase 2) — and points here for the
> procedures. The Supervisor Reads this file at Phase 4 FINALIZE entry (this skill is
> ALSO in the Supervisor's preloaded `skills:` list, so that Read is a refresh
> guarantee, not the first load). Step numbering (1–7 incl. 6.5) is preserved verbatim,
> so cross-file references to e.g. "Phase 4 self-verify (step 6.5)" remain valid — they
> now resolve here.

## Phase 4 FINALIZE procedure (steps 1–7)

**Actions:**

1. **Pre-merge safety gate** (ALL must pass before any merge):
   ```
   FINALIZE pre-merge checklist:
     1. All WORKER_RESULT status = completed (no failed/partial in merge set)
     2. All Code Reviewer decisions = PASS (no FAIL/NEEDS_HUMAN in merge set)
     3. No orphaned worktrees (all accounted for in EXECUTE_RESULT)
     4. Feature branch exists and is ahead of base
   If ANY fail → abort merge, log reason, move job to failed/ (if job file used)
   ```

   ```bash
   # Verify all worktree paths exist
   ls -d ../project-{subtask_a} ../project-{subtask_c} ../project-{subtask_b}
   # Verify all branches exist
   git branch --list feature/{subtask_a} feature/{subtask_c} feature/{subtask_b}
   # Verify each worktree has changes
   git -C ../project-{subtask_a} diff --stat HEAD
   ```
   If any verification fails → checkpoint, report missing worktree/branch, exit with resume.

2. **Commit worker changes in worktrees** (before merging):
   ```bash
   # For each completed subtask (in merge_order from EXECUTE_RESULT):
   git -C ../project-{subtask_a} add -A
   git -C ../project-{subtask_a} commit -m "subtask: {subtask_a} — {title}"
   ```
   This ensures worker code is committed to the subtask branch before merge.

3. **Sequential merge** of each subtask branch into feature branch (in merge_order):
   ```bash
   git checkout feature/{task_id}-{desc}
   git merge feature/{subtask_a} --no-ff -m "merge: {subtask_a} {title}"
   git merge feature/{subtask_c} --no-ff -m "merge: {subtask_c} {title}"
   git merge feature/{subtask_b} --no-ff -m "merge: {subtask_b} {title}"
   ```
   If merge conflict: **STOP** — never force-resolve. Report conflicting files. Checkpoint with list of already-merged and not-yet-merged branches. Exit with resume command.

4. **Cleanup worktrees** (ONLY after successful merge):
   ```bash
   # Remove worktrees first, then branches
   git worktree remove ../{project}-{subtask_id}
   git branch -d feature/{subtask_id}
   ```

5. **Create commits** (inline, following `skills/commit/SKILL.md`):
   - Stage all changes
   - Write conventional commit message with task linking
   - Format: `feat|fix|refactor({scope}): {message}\n\nCloses {task_id}`
   - **NEVER code-fence the message.** The first line passed to `git commit` MUST be the conventional-commit subject (e.g. `feat({scope}): {message}`) — never a ```` ``` ```` / ```` ```bash ```` fence. Pass multi-line messages as separate `-m` flags or via `git commit -F -` / a heredoc (see `skills/commit/SKILL.md` → "Passing the Message to git"). A fence as the first line makes ```` ``` ```` the commit/PR subject.

6. **Push and create PR (against `BASE_BRANCH` — defaults to `main`):**
   ```bash
   git push -u origin feature/{task_id}-{desc}
   gh pr create --base "$BASE_BRANCH" --title "{task_id}: {title}" --body "{PR body}"
   ```
   `BASE_BRANCH` is the value resolved at Phase 0 (the base-branch + non-interactive preamble in `skills/supervisor-config/SKILL.md`) from the `--base-branch` flag, defaulting to `main`. The autonomous-loop multi-iteration mode passes a sibling feature branch (e.g., `feature/v14-iter1`) so iteration N+1 stacks on iteration N's PR.

6.5. **Phase 4 FINALIZE self-verify — PR base branch (v14.0.0, AC-7 + AC-14):**

   Immediately after `gh pr create` returns successfully, before declaring Phase 4 complete, verify the created PR's actual base matches `BASE_BRANCH`:

   ```bash
   ACTUAL_BASE=$(gh pr view "$PR_URL" --json baseRefName --jq .baseRefName)
   ```

   **Retry policy (AC-14):**
   - **First `gh pr view` non-zero exit** → `sleep 5; retry once`.
   - **Second non-zero exit AND `NON_INTERACTIVE == true`** (read live from `Context-Keeper(operation: get_flag, key: "non_interactive")` — do NOT trust in-context state alone, W-NEW-10):
     ```
     Context-Keeper(operation: set_flag, key: "base_mismatch_detected",
                    value: {expected: "$BASE_BRANCH", actual: null, pr_url: "$PR_URL",
                            detected_at: "<ISO>", reason: "gh_unavailable_non_interactive"})
     ```
     Fall through to Phase 4.5 — its cleanup block owns the single `SUPERVISOR_RESULT` emission.
   - **Second non-zero exit AND `NON_INTERACTIVE == false`** → `AskUserQuestion` with exactly three options:
     1. **retry** — run `gh pr view --json baseRefName` once more; on success continue verification, on failure treat as user-aborted (option 3).
     2. **skip-verify-once** — record `record_decision(phase: FINALIZE, decision: "user_skipped_base_verify", rationale: "gh repeatedly unavailable")` and continue as if verified (`ACTUAL_BASE := $BASE_BRANCH`).
     3. **abort** — `set_flag base_mismatch_detected value: {expected: "$BASE_BRANCH", actual: null, pr_url: "$PR_URL", detected_at: "<ISO>", reason: "user_aborted_gh_retry"}` and fall through to Phase 4.5 cleanup.

   **Mismatch detection (after `gh pr view` succeeds):**
   - If `ACTUAL_BASE == BASE_BRANCH`: verification passed, continue to step 7.
   - If `ACTUAL_BASE != BASE_BRANCH`: this is a real base-branch mismatch (rare; most likely cause is a misconfigured remote or a race between `gh pr create` and a downstream automation). Set the flag — but **do NOT emit `SUPERVISOR_RESULT` here.** Fall through to Phase 4.5 which owns the single emission per task (W-NEW-14):
     ```
     Context-Keeper(operation: set_flag, key: "base_mismatch_detected",
                    value: {expected: "$BASE_BRANCH", actual: "$ACTUAL_BASE", pr_url: "$PR_URL",
                            detected_at: "<ISO>", reason: "phase4_self_verify"})
     ```

   **Invariant:** Phase 4 sets the flag at most once per session and never emits `SUPERVISOR_RESULT` directly on mismatch. The single emission point for the failure path is Phase 4.5's base-mismatch cleanup block (`skills/self-heal-advisory/SKILL.md` Part 2 §"Phase 4.5 base-mismatch cleanup").

7. **Exit FINALIZE.** Task is NOT yet marked completed, and the job file is NOT yet moved. Those actions happen in Phase 4.5 SELF_HEAL's completion tail so that self-heal outcomes are captured in the completion record.

**FINALIZE scope reduction (v11.0.0):** FINALIZE exits after PR creation. Task-completion side-effects (job-file move from `in-progress/` → `done/`, state marked completed via Context-Keeper) have been relocated to Phase 4.5 SELF_HEAL's completion tail. Do not perform them here.

**Safety guarantees:**
- Worker code lives in git branches until explicitly merged — can always recover
- Worktrees are removed ONLY after successful merge
- Merge conflicts always escalate to human
- Checkpoint includes which branches were merged and which remain
- If EXECUTE_CHECKPOINT (partial): only merge completed+reviewed subtasks, leave in-progress worktrees intact

**PR Body Template:**
```markdown
## Summary
{One paragraph describing the changes}

## Changes
- {Bullet list of key changes}

## Test Plan
- {How to verify the changes}

## Task
Closes {task_id}

---
Generated by Supervisor Agent v4
```

## Subagent Spawn Contracts

Exact Task tool call shapes for each subagent.

**Prompt-cache discipline:** Within each `prompt:` string, put stable content (role/skill guidance, project patterns, cost_profile notes, house-rules advisory text) before volatile interpolations (task id, title, criteria, worktree/feature_branch/state_file paths, resume context, files_modified, operation/data payloads). Prompt caching is prefix-match — an early volatile value invalidates the cache for every subsequent spawn.

**Context-Keeper:**
```
Task(
  description: "CK: {operation} for {task_id}",
  prompt: "state_file: {path}\noperation: {op}\ndata: {payload}",
  subagent_type: "loomwright:context-keeper"
)
```

**Orchestrator:**
```
Task(
  description: "Plan: decompose {task_id}",
  prompt: "Project context: {CLAUDE.md summary}\ngoal: \"{task_id}: {title}\"\nAcceptance criteria: {criteria}",
  subagent_type: "loomwright:orchestrator",
  model: "sonnet"   # ONLY when cost_profile=cheap; omit entirely when cost_profile=default
)
```

**Execute Manager:**
```
Task(
  description: "Execute Phase 3: {task_id}",
  prompt: "cost_profile: {default|cheap}
    Config: max_workers={N}, project={name}, feature_branch={branch}
    State file: {path}
    Subtask list: [{ids, titles, criteria, files, skills, deps}]
    Parallelism graph: [{launchable, blocked}]
    Resume context: {optional, from previous EXECUTE_CHECKPOINT}",
  subagent_type: "loomwright:execute-manager",
  model: "sonnet"   # ONLY when cost_profile=cheap; omit entirely when cost_profile=default
)
```

**Worker (fast-path only):**
```
Task(
  description: "Implement: {subtask_title}",
  prompt: "Skill references: {skills}
    Project context: {patterns from CLAUDE.md}
    Applicable house rules (ADVISORY — from `read-rules.sh`, include this line ONLY when its output is NON-EMPTY; omit entirely when empty): {house_rules summary}. These are committed team conventions to bias your implementation while writing code — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins). This is advisory only: you are NEVER failed for a house rule. A `must` rule is surfaced flagged, but its `check` value is DATA only — do NOT execute, eval, source, or `bash -c` any `check`.
    Subtask ID: {id}
    Title: {title}
    Acceptance criteria: {criteria}
    Worktree path: {project_root}
    Provides (verbatim from the brief's Subtask Contracts): {provides YAML}
    Retry context: {optional, from previous review}",
  # Applicable house rules: compute by running `bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-rules.sh" <touched paths...>`
  # (args, never stdin — no-hang). Inject the output into this worker prompt ONLY when it is NON-EMPTY; empty
  # output ⇒ inject nothing (the reader always exits 0 and emits EMPTY on no valid rule — never a "no rules"
  # sentinel). ADVISORY / fail-safe / NEVER-gating: it never fails a worker, never gates a PR, never a
  # SUPERVISOR_RESULT field, and never bumps `schema_version`. Call the READER ONLY — never pipe/eval/source
  # the reader output; a rule's `check` is surfaced to the worker as DATA, never executed.
  # `provides:` is REQUIRED input — the worker's Step 5.5 outputs-verification
  # re-reads it from the spawn brief; omitting it silently no-ops the v12 outputs gate
  subagent_type: "loomwright:worker",
  model: "sonnet"   # ONLY when cost_profile=cheap; omit entirely when cost_profile=default
)
```

**Code Reviewer (fast-path only):**
```
Task(
  description: "Review: {subtask_title}",
  prompt: "Project patterns: {from CLAUDE.md}
    Task context: {subtask_title} — {criteria}
    Review scope: {files_modified from WORKER_RESULT}",
  subagent_type: "loomwright:code-reviewer",
  model: "sonnet"   # ONLY when cost_profile=cheap; omit entirely when cost_profile=default
)
```

## Git Worktree Lifecycle (phase sequence)

Ownership: subtask branches AND worktrees are both created by the **Execute Manager in
Phase 3** (its Step 2a — see `agents/execute-manager.md`), never by the Supervisor in
Phase 2 — Phase 2 (PLAN) runs no git commands. (The load-bearing ownership invariant
statement stays in `agents/supervisor.md` §"Git Worktree Lifecycle".)

```
Phase 3 (EXECUTE — Execute Manager Step 2a):
  git branch feature/BD-XXa              # from feature branch HEAD (ref only, no checkout)
  git branch feature/BD-XXc
  git worktree add ../{project}-BD-XXa feature/BD-XXa
  git worktree add ../{project}-BD-XXc feature/BD-XXc
  # Workers operate in worktrees...

Phase 4 (FINALIZE):
  git checkout feature/BD-XX-desc
  git merge feature/BD-XXa --no-ff
  git merge feature/BD-XXc --no-ff
  git worktree remove ../{project}-BD-XXa
  git worktree remove ../{project}-BD-XXc
  git branch -d feature/BD-XXa
  git branch -d feature/BD-XXc
```
