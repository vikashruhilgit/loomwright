---
name: state-management
description: State file schema, .supervisor/ directory setup, checkpoint and resume protocols. Use when managing Supervisor session state across phases.
allowed-tools: [Read, Write, Edit, Bash]
---

# State Management Skill

Patterns for externalizing Supervisor state to files, enabling cross-session resume and Beads-optional operation.

## Quick Rules

- Only Context-Keeper writes the state file (blocking calls for mutations)
- State file lives in scratchpad during active session
- Persistent copy in `.supervisor/state.md` for cross-session resume
- Beads checkpoints are optional (only if `config.beads: true`)
- State file < 1000 tokens; decisions log and worker results grow unbounded

## When to Use This Skill

- Initializing a new Supervisor session
- Checkpointing state after phase completion
- Resuming from a previous session
- Setting up `.supervisor/` directory in a project
- Recording worker results, decisions, or errors

---

## `.supervisor/` Directory Setup

### Auto-Create on First Run

```bash
# Create directory
mkdir -p .supervisor/history

# Add to .gitignore (idempotent)
grep -qxF '.supervisor/' .gitignore 2>/dev/null || echo '.supervisor/' >> .gitignore
```

### Directory Structure

```
.supervisor/
├── state.md              # Current/last session state
└── history/              # Completed session summaries
    ├── 2024-01-15-BD-15.md
    └── 2024-01-16-BD-18.md
```

### Gitignore Check

Before creating `.supervisor/`, verify `.gitignore` exists. If not, create it with `.supervisor/` entry.

---

## State File Schema

**Active session location:** `{scratchpad}/supervisor-state.md`
**Persistent location:** `{project}/.supervisor/state.md`

```markdown
# Supervisor State

## Config
- beads: true | false
- max_workers: 2
- mode: parallel | sequential

## Session
- session_id: {uuid}
- task_id: BD-XX | task-short-desc
- branch: feature/BD-XX-desc
- phase: INIT | ACQUIRE | PLAN | EXECUTE | FINALIZE | LOOP
- status: running | paused | completed | failed

## Task
- title: {task title}
- acceptance_criteria:
  - AC-1: {text} [met | unmet | untested]
  - AC-2: {text} [met | unmet | untested]

## Subtasks
| ID | Title | Status | Worker | Worktree | Review | Attempts |
|----|-------|--------|--------|----------|--------|----------|
| {id} | {title} | pending/in_progress/completed/failed | {worker-id} | {path} | --/PASS/FAIL | 0/3 |

## Parallelism
- launchable: [{ids}]
- blocked: [{id} (depends on {id})]
- active_worktrees: [{paths}]

## Decisions Log
| # | Phase | Decision | Rationale |

## Worker Results
### {worker-id} ({subtask-id})
- files_modified: [{paths}]
- lines: +{added} -{removed}
- tests: pass/fail ({count})
- review: --/PASS/FAIL/NEEDS_HUMAN

## Error Log
| # | Phase | Error | Retry | Resolution |

## Checkpoint
- last_checkpoint: {timestamp}
- resume_command: /supervisor --continue task: {task-id}
- completed_phases: [{phases}]
- current_phase: {phase}
- subtask_progress: {completed}/{total}
```

---

## Read/Write Protocol

### Reading State

Context-Keeper reads the full state file, extracts the requested section, and returns a summary (< 50 tokens).

```
Read {scratchpad}/supervisor-state.md
→ Parse Markdown sections
→ Return requested data
```

### Writing State (Mutations)

All mutations go through Context-Keeper (blocking call). Never write the state file directly from Supervisor or Workers.

**Supported operations:**

| Operation | What Changes | When |
|-----------|-------------|------|
| `initialize` | Creates full state file | Phase 0 (INIT) |
| `set_task` | Updates Session + Task sections | Phase 1 (ACQUIRE) |
| `set_subtasks` | Updates Subtasks + Parallelism | Phase 2 (PLAN) |
| `record_worker_result` | Updates Worker Results + Subtask row | Phase 3 (EXECUTE) |
| `record_review` | Updates Subtask review column | Phase 3 (EXECUTE) |
| `record_decision` | Appends to Decisions Log | Any phase |
| `record_error` | Appends to Error Log | Any phase |
| `update_phase` | Updates Session.phase + Checkpoint | Phase transitions |
| `checkpoint` | Full state snapshot to `.supervisor/` | After each phase |

### Checkpoint Protocol

After each phase transition:

1. Context-Keeper updates `Session.phase` and `Checkpoint` section
2. Copy scratchpad state → `.supervisor/state.md`
3. If `config.beads: true`: also write summary to Beads comment

```bash
# Checkpoint to .supervisor/
cp {scratchpad}/supervisor-state.md {project}/.supervisor/state.md

# Optional Beads checkpoint
bd comment BD-XX "## Supervisor Checkpoint
- Phase: {current_phase}
- Progress: {completed}/{total} subtasks
- Branch: {branch}
- Resume: /supervisor --continue task: BD-XX"
```

---

## Resume Protocol

### Same-Session Resume (from scratchpad)

If the scratchpad state file exists and `status: running`:

1. Read `{scratchpad}/supervisor-state.md`
2. Parse `current_phase` and `subtask_progress`
3. Resume from the current phase (skip completed phases)
4. Restore worker tracking if EXECUTE phase was interrupted

### Cross-Session Resume (from `.supervisor/`)

If no scratchpad state but `.supervisor/state.md` exists:

1. Read `{project}/.supervisor/state.md`
2. Verify branch still exists: `git branch --list {branch}`
3. Checkout the branch: `git checkout {branch}`
4. Verify worktrees (may need recreation): `git worktree list`
5. Copy to scratchpad: `cp .supervisor/state.md {scratchpad}/supervisor-state.md`
6. Resume from checkpoint

### Resume with Beads (optional)

If Beads is available and `.supervisor/state.md` is missing:

1. Read last checkpoint from Beads task comments
2. Parse checkpoint data
3. Reconstruct state file from checkpoint
4. Resume from checkpoint

### Resume Priority

```
1. Scratchpad state file (freshest, same session)
2. .supervisor/state.md (persistent, cross-session)
3. Beads checkpoint comments (fallback)
4. No state found → start fresh (Phase 0)
```

---

## Session History

When a session completes (Phase 5 LOOP → no more tasks):

1. Copy final state to history:
   ```bash
   cp .supervisor/state.md ".supervisor/history/$(date +%Y-%m-%d)-{task_id}.md"
   ```
2. Clear active state file
3. State file remains for reference but `status: completed`

---

## Beads-Optional Operation

### With Beads (`config.beads: true`)

- Task IDs come from Beads (BD-XX format)
- Checkpoints written to both `.supervisor/` and Beads comments
- Task status updates via `bd update` / `bd close`
- `bd ready` for task selection

### Without Beads (`config.beads: false`)

- Task IDs are descriptive slugs (e.g., `task-user-auth`)
- Checkpoints written only to `.supervisor/`
- Task status tracked only in state file
- User provides task description directly

### Conditional Beads Calls

```
if config.beads:
    bd update {task_id} --status in_progress
    bd comment {task_id} "checkpoint..."
    bd close {task_id}
else:
    # Update state file only
    update_phase(...)
```

---

## Quality Checklist

Before completing state management:
- [ ] `.supervisor/` directory exists with `.gitignore` entry
- [ ] State file has all required sections
- [ ] Checkpoint written after each phase transition
- [ ] Resume tested from both scratchpad and `.supervisor/`
- [ ] Beads calls are conditional on `config.beads`
- [ ] Only Context-Keeper mutates state file
- [ ] Session history saved on completion

## See Also

- `skills/workflow-management/SKILL.md` - Workflow patterns
- `skills/async-orchestration/SKILL.md` - Parallel dispatch patterns
- `agents/context-keeper.md` - State management agent
