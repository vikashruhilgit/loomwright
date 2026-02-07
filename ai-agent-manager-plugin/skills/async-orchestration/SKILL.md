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

### Poll Loop Pattern

```
active_workers = {worker_id: {subtask_id, output_file, status}}
active_reviewers = {reviewer_id: {subtask_id, output_file, status}}

while uncompleted_subtasks > 0:

  # 1. Check running workers (non-blocking)
  for worker_id in active_workers:
    result = TaskOutput(task_id=worker_id, block=false, timeout=1000)
    if result.is_complete:
      → Parse WORKER_RESULT from output
      → Spawn Context-Keeper (blocking) to record result
      → Spawn Reviewer in background
      → Move worker to completed

  # 2. Check running reviewers (non-blocking)
  for reviewer_id in active_reviewers:
    result = TaskOutput(task_id=reviewer_id, block=false, timeout=1000)
    if result.is_complete:
      → Parse review decision
      if PASS:
        → Record in state
        → Check if blocked subtasks now launchable
        → Launch newly launchable subtasks
      if FAIL (attempts < 3):
        → Spawn fix worker (background)
      if FAIL (attempts >= 3):
        → Checkpoint, escalate to human
      if NEEDS_HUMAN:
        → Checkpoint, pause, exit with resume

  # 3. Launch newly launchable subtasks
  for subtask in newly_launchable:
    if active_worktrees < max_workers:
      → Create worktree
      → Spawn worker (background)

  # 4. If nothing ready, block on earliest pending
  if no_results_this_iteration:
    earliest = min(active_workers + active_reviewers, key=start_time)
    TaskOutput(task_id=earliest.id, block=true, timeout=30000)
```

### Result Collection

After TaskOutput returns:

1. Read the output file content
2. Parse the structured result block (WORKER_RESULT or REVIEW_RESULT)
3. Extract: files modified, test results, decision
4. Pass to Context-Keeper for state update

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

The Supervisor holds ONLY:

| Data | Tokens |
|------|--------|
| Config (beads, max_workers, mode) | ~50 |
| Session (task_id, branch, phase) | ~50 |
| Active workers (id, subtask, output_file) | ~100 per worker |
| Active reviewers (id, subtask, output_file) | ~100 per reviewer |
| Parallelism state (launchable, blocked lists) | ~100 |
| **Total (2 workers + 2 reviewers)** | **~600 tokens** |

Everything else lives in the state file, managed by Context-Keeper.

---

## Error Handling

| Situation | Action |
|-----------|--------|
| Worker fails (crash/timeout) | Record error, retry once, then escalate |
| Worker output unparseable | Record error, retry with clearer prompt |
| Worktree creation fails | Fall back to sequential execution |
| Worktree already exists | Remove and recreate, or reuse if clean |
| Disk space concern | Limit to 2 concurrent worktrees |
| Context > 85% | Checkpoint all state, exit with resume |

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
