---
name: workflow-management
description: Patterns for managing autonomous workflows including context, checkpoints, parallel execution, and permissions. Use when orchestrating multi-stage agent workflows.
allowed-tools: [Read, Bash]
---

# Workflow Management Skill

Patterns for autonomous workflow execution with context management, checkpoints, parallel dispatch, and permission handling.

## Quick Rules

- Keep supervisor context < 800 tokens (externalize via Context-Keeper)
- Save checkpoint after each phase completion (to `.supervisor/` + optionally Beads)
- Summarize subagent outputs (< 200 tokens each)
- Pause on NEEDS_HUMAN, retry on FAIL (max 3x), continue on PASS
- Exit gracefully at > 85% context usage
- Always create feature branch before any code work (mandatory)
- Use git worktrees for parallel worker execution

## When to Use This Skill

- Managing multi-phase autonomous workflows (6-phase model)
- Coordinating parallel workers with git worktrees
- Handling context limits and checkpoints
- Implementing permission batching
- Error recovery and escalation
- Beads-optional task management

## 6-Phase State Machine

```
INIT → ACQUIRE → PLAN → EXECUTE → FINALIZE → LOOP
                                                 ↓
                                        (back to ACQUIRE or END)
```

### Phase Transitions

```
INIT:
  - env detected, config set → ACQUIRE
  - --continue with state → resume saved phase

ACQUIRE:
  - task selected + branch created → PLAN
  - no ready tasks → END
  - vague requirements → spawn Product Owner → PLAN

PLAN:
  - subtasks created + parallelism analyzed → EXECUTE
  - single subtask → EXECUTE (fast-path, no worktrees)
  - --sequential → EXECUTE (no worktrees)

EXECUTE:
  - all subtasks PASS → FINALIZE
  - FAIL (< 3x) → retry subtask
  - FAIL (3x) → ESCALATION
  - NEEDS_HUMAN → PAUSED
  - context > 85% → PAUSED

FINALIZE:
  - merge + commit + PR → LOOP
  - merge conflict → PAUSED

LOOP:
  - more tasks + context < 70% → ACQUIRE
  - context 70-85% → warn + suggest new session
  - no tasks → END
```

## Context Budget (v3)

| Component | Token Budget |
|-----------|--------------|
| Supervisor orchestration state | < 800 tokens |
| State file (externalized) | Unlimited (managed by Context-Keeper) |
| Subagent summaries | < 200 tokens each |
| Checkpoint data | < 500 tokens |
| Error context | < 300 tokens |

**Key difference from v2:** State is externalized to a file managed by Context-Keeper. The Supervisor holds only phase, task_id, branch, and active worker IDs.

## Checkpoint Format (v3)

Save checkpoint via Context-Keeper after each phase:

```
Context-Keeper(operation: checkpoint, project_dir: {path}, beads: {bool}, task_id: {id})
```

**State file location:**
- Active: `{scratchpad}/supervisor-state.md`
- Persistent: `{project}/.supervisor/state.md`
- History: `{project}/.supervisor/history/{date}-{task}.md`

**Optional Beads checkpoint (if `config.beads: true`):**
```bash
bd comment BD-XX "## Supervisor Checkpoint
- Phase: {phase}
- Progress: {completed}/{total} subtasks
- Branch: feature/BD-XX-{desc}
- Resume: /supervisor --continue task: BD-XX"
```

## Context Monitoring

```
┌─────────────────────────────────────────────────────────┐
│ CONTEXT THRESHOLDS                                      │
├─────────────────────────────────────────────────────────┤
│  < 70%  │ Normal operation                             │
│  70-85% │ Warning: Force checkpoint, suggest new       │
│         │ session                                       │
│  > 85%  │ Critical: Checkpoint + graceful exit         │
│         │ Output: "Run /supervisor --continue"         │
└─────────────────────────────────────────────────────────┘
```

**At > 85% context:**
1. Context-Keeper: checkpoint to `.supervisor/`
2. Output resume command
3. Exit gracefully with status summary
4. User runs `/supervisor --continue task: BD-XX` in new session

## Resume Protocol (v3)

**Priority order:**
1. Scratchpad state file (freshest, same session)
2. `.supervisor/state.md` (persistent, cross-session)
3. Beads checkpoint comments (fallback, if Beads active)
4. No state found → start fresh (Phase 0 INIT)

**Resume actions:**
```
1. Load state from highest-priority source
2. Verify branch exists: git branch --list {branch}
3. Checkout branch: git checkout {branch}
4. Verify worktrees (if EXECUTE phase): git worktree list
5. Copy to scratchpad if loading from .supervisor/
6. Continue from saved phase
```

## Permission Batching

### Layer 1: Auto-Approve Safe Commands

| Category | Commands |
|----------|----------|
| Git (read) | `status`, `branch`, `log`, `diff`, `worktree list` |
| Git (write) | `checkout`, `add`, `commit`, `push`, `pull` |
| Git (worktree) | `worktree add`, `worktree remove` |
| Beads | All `bd` commands |
| GitHub | `gh pr create`, `gh pr view`, `gh pr list` |
| Build | `npm test`, `npm run lint`, `npm run build` |
| File system | `.supervisor/` directory operations |

### Layer 2: Batch by Phase

Group related actions for single approval:

```markdown
## Supervisor: Phase 1 — ACQUIRE
**Actions to perform:**
1. git checkout main && git pull
2. git checkout -b feature/BD-15-user-auth
3. bd update BD-15 --status in_progress

[Approve All] [Review Each] [Cancel]
```

### Layer 3: Approval Checkpoints

| Phase | Approval Needed |
|-------|-----------------|
| 0. INIT (config) | Interactive (AskUserQuestion) |
| 1. ACQUIRE (branch) | **[APPROVAL NEEDED]** |
| 2. PLAN (decompose) | Auto (subagent) |
| 3. EXECUTE (implement) | **[APPROVAL NEEDED - batch]** |
| 4. FINALIZE (commit+PR) | **[APPROVAL NEEDED]** |
| 5. LOOP (next) | Auto |

## Parallel Execution Patterns

### Git Worktree Lifecycle

```
Phase 2 (PLAN):
  git branch feature/BD-XXa          # from feature branch HEAD
  git branch feature/BD-XXc

Phase 3 (EXECUTE):
  git worktree add ../{project}-BD-XXa feature/BD-XXa
  git worktree add ../{project}-BD-XXc feature/BD-XXc
  # Workers operate independently...

Phase 4 (FINALIZE):
  git checkout feature/BD-XX-desc
  git merge feature/BD-XXa --no-ff
  git merge feature/BD-XXc --no-ff
  git worktree remove ../{project}-BD-XXa
  git worktree remove ../{project}-BD-XXc
  git branch -d feature/BD-XXa
  git branch -d feature/BD-XXc
```

### Worker Dispatch

```
Task(
  description: "Implement {subtask_id}",
  prompt: "Worker prompt...",
  subagent_type: "general-purpose",
  run_in_background: true
)
→ Returns: { task_id, output_file }
→ Track: worker_id, subtask_id, output_file, worktree_path
```

### Non-Blocking Poll Loop

```
while uncompleted > 0:
  # Check workers (non-blocking)
  TaskOutput(worker_id, block=false, timeout=1000)

  # Check reviewers (non-blocking)
  TaskOutput(reviewer_id, block=false, timeout=1000)

  # Launch newly unblocked subtasks
  # If idle, block on earliest pending
  TaskOutput(earliest, block=true, timeout=30000)
```

### Parallelism Decision

```
LAUNCHABLE: no deps + no file overlap + worktrees < max
BLOCKED: has deps OR file overlap OR at capacity
```

See `skills/async-orchestration/SKILL.md` for full details.

## Error Recovery

| Error | Max Retries | Action |
|-------|-------------|--------|
| Code review FAIL | 3 | Fix issues, re-review |
| Code review FAIL (3x) | - | Checkpoint, escalate to human |
| NEEDS_HUMAN decision | - | Checkpoint, pause, await input |
| Merge conflict | - | STOP, report files, await resolution |
| Worker crash/timeout | 1 | Retry once, then escalate |
| Worktree creation fails | - | Fall back to sequential mode |
| No ready tasks | - | Report and exit gracefully |
| Context > 85% | - | Checkpoint + graceful exit |

**Escalation Format:**

```markdown
## ESCALATION REQUIRED

**Task:** {task_id} ({title})
**Phase:** {phase_name}
**Error:** {error_type}

**Context:**
{Brief description}

**Last Issues:**
{Blocking issues}

**State:** Saved to .supervisor/state.md

**Options:**
1. Fix manually and run `/supervisor --continue task: {task_id}`
2. Cancel: `git checkout main`
```

## Subagent Orchestration (v3)

### Agents and Modes

| Agent | Mode | Purpose |
|-------|------|---------|
| Context-Keeper | Blocking | State file mutations |
| Product Owner | Blocking | Requirements refinement |
| Orchestrator | Blocking | Task decomposition |
| Worker | Background | Implementation (parallel) |
| Code Reviewer | Background | Review (parallel) |

### Summary Extraction

After each subagent, extract minimal summary:

| Agent | Summary Template |
|-------|------------------|
| Context-Keeper | `"{operation}: {confirmation}"` |
| Product Owner | `"Story: {title}. Criteria: {count} items."` |
| Orchestrator | `"Created {N} subtasks: {IDs}. Launchable: {IDs}"` |
| Worker (bg) | Parse WORKER_RESULT block |
| Code Reviewer (bg) | Parse REVIEW_RESULT block |

## Beads-Optional Operation

### Conditional Beads Calls

```
if config.beads:
    bd update {task_id} --status in_progress
    bd comment {task_id} "checkpoint..."
    bd close {task_id}
else:
    # State managed via .supervisor/ only
    Context-Keeper(operation: update_phase, ...)
```

### Task Selection Without Beads

- User provides task description directly
- Task ID is a descriptive slug (e.g., `task-user-auth`)
- All state in `.supervisor/state.md`

## Quality Checklist

Before completing workflow management:
- [ ] Feature branch created before any code work (mandatory)
- [ ] Checkpoint saved after each phase transition
- [ ] Context budget respected (< 800 tokens supervisor state)
- [ ] Subagent outputs summarized (< 200 tokens each)
- [ ] Error handling covers all failure modes
- [ ] Resume command provided at pause points
- [ ] Permission batching applied to reduce friction
- [ ] Escalation format includes context for human
- [ ] Worktrees cleaned up after FINALIZE
- [ ] Beads calls conditional on config.beads

## See Also

- `skills/async-orchestration/SKILL.md` - Parallel dispatch patterns
- `skills/state-management/SKILL.md` - State file schema and checkpoints
- `skills/context-summarization/SKILL.md` - Output compression patterns
- `skills/commit/SKILL.md` - Conventional commit format
- `skills/quality-checklist/SKILL.md` - Review gate criteria
- `agents/context-keeper.md` - State management agent
- `agents/worker.md` - Implementation worker agent
