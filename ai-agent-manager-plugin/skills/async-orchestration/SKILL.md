---
name: async-orchestration
description: Background dispatch patterns, non-blocking polling, parallelism decisions, and git worktree lifecycle. Use when running parallel workers in Supervisor workflows.
allowed-tools: [Read, Bash]
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
