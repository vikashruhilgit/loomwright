---
name: workflow-management
description: Patterns for managing autonomous workflows including context, checkpoints, parallel execution, and permissions. Use when orchestrating multi-stage agent workflows.
allowed-tools: [Read, Bash]
version: "1.0.0"
lastUpdated: "2026-03"
---

# Workflow Management Skill

Patterns for autonomous workflow execution with context management, checkpoints, parallel dispatch, and permission handling.

## Quick Rules

- Keep supervisor context < 400 tokens (externalize via Context-Keeper)
- Save checkpoint after each phase completion (to `.supervisor/`)
- Summarize subagent outputs (< 200 tokens each)
- Pause on NEEDS_HUMAN, retry on FAIL (max 3x), continue on PASS
- Exit gracefully at tool call budget limit
- Always create feature branch before any code work (mandatory)
- Use git worktrees for parallel worker execution

## When to Use This Skill

- Managing multi-phase autonomous workflows (7-phase model — INIT, ACQUIRE, PRE-FLIGHT SYNC, PLAN, EXECUTE, FINALIZE, SELF_HEAL, LOOP)
- Coordinating parallel workers with git worktrees
- Handling context limits and checkpoints
- Implementing permission batching
- Error recovery and escalation
- Execute Manager delegation for Phase 3

## 7-Phase State Machine

> **Phase-numbering convention:** "7-Phase" counts the primary numbered phases. **PRE-FLIGHT SYNC (1.5)** and **SELF_HEAL (4.5)** are `.5` sub-phase *gates* inserted between primary phases — they appear in the diagram below (and the enumeration above) but do not change the "7-Phase" name.

```
INIT → ACQUIRE → PRE-FLIGHT SYNC → PLAN → EXECUTE → FINALIZE → SELF_HEAL → LOOP
                                                                            ↓
                                                                   (back to ACQUIRE or END)
```

### Phase Transitions

```
INIT:
  - env detected, config set → ACQUIRE
  - --continue with state → resume saved phase

ACQUIRE:
  - task selected + branch created → PRE-FLIGHT SYNC
  - no ready tasks → END
  - vague requirements → spawn Product Owner → PRE-FLIGHT SYNC

PRE-FLIGHT SYNC:
  - CLEAR (no remote overlap) → PLAN
  - OVERLAP/SUPERSEDED → AskUserQuestion (proceed/revise/abort); fail-closed under --non-interactive
  - --skip-preflight-sync flag set → PLAN

PLAN:
  - subtasks created + parallelism analyzed → EXECUTE
  - single subtask → EXECUTE (fast-path, no worktrees)
  - --sequential → EXECUTE (no worktrees)

EXECUTE:
  - EXECUTE_RESULT (completed) → FINALIZE
  - EXECUTE_RESULT (escalation) → ESCALATION
  - EXECUTE_CHECKPOINT → spawn fresh Execute Manager or partial merge
  - NEEDS_HUMAN → PAUSED
  - tool budget exceeded → PAUSED

FINALIZE:
  - merge + commit + PR created → SELF_HEAL (always; completion tail runs inside 4.5)
  - merge conflict → PAUSED

SELF_HEAL:
  - review PASS → LOOP (status completed)
  - review NEEDS_HUMAN → LOOP (status completed_with_escalation, reason needs_human)
  - max iterations reached → LOOP (status completed_with_escalation, reason max_iterations_reached)
  - --skip-self-heal flag set → LOOP (status completed, heal_loop_ran=false; loop is short-circuited but phase transition and completion tail still execute)
  - fix task crash → PAUSED (self_heal_resume_count increments on the next --continue only after that resume actually re-runs the code-reviewer Task; 3rd such reviewer-reaching resume escalates as self_heal_resume_thrash. Invariant-violation resumes that skip the reviewer do not increment the counter.)
  - Phase 4.5 invariant violation (code-reviewer not invoked AND --skip-self-heal not set) → status: failed, job stays in in-progress/, no counter mutation

LOOP:
  - consumes heal outcome from SELF_HEAL for reporting (no completion actions — those happened in 4.5 tail)
  - more tasks + tool_calls < 40 (80%) → ACQUIRE
  - tool_calls 40-46 → warn + suggest new session
  - no tasks → END
```

## Context Budget (v4)

| Component | Token Budget | Tool Call Budget |
|-----------|--------------|-----------------|
| Supervisor orchestration state | < 400 tokens | 50 calls |
| Execute Manager (Phase 3) | Isolated context | 60 calls |
| State file (externalized) | Unlimited (managed by Context-Keeper) | — |
| Subagent summaries | < 200 tokens each | — |
| Checkpoint data | < 500 tokens | — |
| Error context | < 300 tokens | — |

**Key difference from v3:** Phase 3 poll loop is delegated to Execute Manager, keeping Supervisor context minimal. Tool call counting replaces unenforceable percentage-based thresholds.

## Checkpoint Format (v4)

Save checkpoint via Context-Keeper after each phase:

```
Context-Keeper(operation: checkpoint, project_dir: {path}, task_id: {id})
```

**State file location:**
- Active: `{scratchpad}/supervisor-state.md`
- Persistent: `{project}/.supervisor/state.md`
- History: `{project}/.supervisor/history/{date}-{task}.md`

## Context Monitoring (Tool Call Counter)

### Supervisor Budget (50 calls, including Phase 4.5)

```
┌─────────────────────────────────────────────────────────┐
│ SUPERVISOR TOOL CALL THRESHOLDS                          │
├─────────────────────────────────────────────────────────┤
│  0-30 (60%)  │ GREEN: Normal operation                  │
│  30-40 (80%) │ YELLOW: Aggressive compression            │
│  40-46 (92%) │ RED: Force checkpoint, suggest new session│
│  46+         │ RED: Checkpoint + exit with resume        │
└─────────────────────────────────────────────────────────┘
```

### Execute Manager Budget (60 calls)

```
┌─────────────────────────────────────────────────────────┐
│ EXECUTE MANAGER TOOL CALL THRESHOLDS                     │
├─────────────────────────────────────────────────────────┤
│  0-36 (60%)  │ GREEN: Normal poll intervals (2s)         │
│  36-48 (80%) │ YELLOW: Longer intervals, batch CK calls  │
│  48-55 (92%) │ ORANGE: Force EXECUTE_CHECKPOINT prep     │
│  55+         │ RED: Output EXECUTE_CHECKPOINT and exit    │
└─────────────────────────────────────────────────────────┘
```

**At budget limit:**
1. Context-Keeper: checkpoint to `.supervisor/`
2. Output resume command
3. Exit gracefully with status summary
4. User runs `/supervisor --continue task: {task_id}` in new session

## Resume Protocol (v4)

**Priority order:**
1. Scratchpad state file (freshest, same session)
2. `.supervisor/state.md` (persistent, cross-session)
3. No state found → start fresh (Phase 0 INIT)

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
| Tool budget exceeded | - | Checkpoint + graceful exit |

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
| Execute Manager | Blocking | Phase 3 poll loop + worker/reviewer lifecycle |
| Worker | Background (via EM) | Implementation (parallel) |
| Code Reviewer | Background (via EM) | Review (parallel) |

### Summary Extraction

After each subagent, extract minimal summary:

| Agent | Summary Template |
|-------|------------------|
| Context-Keeper | `"{operation}: {confirmation}"` |
| Product Owner | `"Story: {title}. Criteria: {count} items."` |
| Orchestrator | `"Created {N} subtasks: {IDs}. Launchable: {IDs}"` |
| Worker (bg) | Parse WORKER_RESULT block |
| Code Reviewer (bg) | Parse REVIEW_RESULT block |

## Task Selection

- User provides task description directly via `task:` parameter
- Task ID is a descriptive slug (e.g., `task-user-auth`)
- All state managed in `.supervisor/state.md` via Context-Keeper
- No external task tracking dependency — state is self-contained

## Plugin Hooks (Quality Gates)

Plugin hooks in `hooks/hooks.json` provide automatic quality gates that run without spawning extra subagents:

### SubagentStop Hook (Worker Validation)

When a Worker subagent completes, a prompt-based hook auto-validates its output:

```json
{
  "SubagentStop": [
    {
      "matcher": "ai-agent-manager-plugin:worker",
      "hooks": [
        {
          "type": "prompt",
          "prompt": "Verify: (1) WORKER_RESULT block present, (2) files_modified not empty, (3) no unresolved errors...",
          "timeout": 30
        }
      ]
    }
  ]
}
```

**What this replaces:** Manual WORKER_RESULT validation in the Supervisor's poll loop. The hook catches malformed or incomplete worker output before the Supervisor processes it.

### TaskCompleted Hook (Closure Validation)

When any task is marked complete, a hook validates it's genuinely done:

```json
{
  "TaskCompleted": [
    {
      "hooks": [
        {
          "type": "prompt",
          "prompt": "Verify task appears genuinely done — not abandoned or skipped...",
          "timeout": 30
        }
      ]
    }
  ]
}
```

**What this prevents:** Premature task closure (tasks marked done that are actually incomplete).

### Why Prompt-Based Hooks

- No shell scripts to maintain — cross-platform (macOS, Linux, Windows)
- Uses fast haiku model for evaluation
- Falls back gracefully if hook fails (doesn't block workflow)
- Lighter than spawning a full reviewer subagent for simple checks

## Alternative Parallel Execution: Agent Teams

For research or exploration tasks, Claude Code Agent Teams provides an alternative to git worktrees:

| Factor | Git Worktrees (Default) | Agent Teams |
|--------|------------------------|-------------|
| File isolation | Full (separate dirs) | None (shared worktree) |
| Git safety | Safe (separate branches) | Risk of conflicts |
| Best for | Implementation | Research, exploration |
| Stability | Stable | Experimental |

See `skills/agent-teams/SKILL.md` for full patterns and decision matrix.

The Supervisor v4 workflow uses git worktrees as the default. Agent Teams is available for manual use in research phases.

## Quality Checklist

Before completing workflow management:
- [ ] Feature branch created before any code work (mandatory)
- [ ] Checkpoint saved after each phase transition
- [ ] Context budget respected (< 400 tokens supervisor state)
- [ ] Subagent outputs summarized (< 200 tokens each)
- [ ] Error handling covers all failure modes
- [ ] Resume command provided at pause points
- [ ] Permission batching applied to reduce friction
- [ ] Escalation format includes context for human
- [ ] Worktrees cleaned up after FINALIZE
- [ ] Tool call budget tracked and respected
- [ ] Plugin hooks active for worker, execute-manager, and task closure validation

## See Also

- `skills/async-orchestration/SKILL.md` - Parallel dispatch patterns
- `skills/state-management/SKILL.md` - State file schema and checkpoints
- `skills/context-summarization/SKILL.md` - Output compression patterns
- `skills/commit/SKILL.md` - Conventional commit format
- `skills/quality-checklist/SKILL.md` - Review gate criteria
- `skills/agent-teams/SKILL.md` - Agent Teams patterns (alternative parallel execution)
- `agents/context-keeper.md` - State management agent
- `agents/worker.md` - Implementation worker agent
- `hooks/hooks.json` - Plugin quality gate hooks
