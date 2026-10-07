## CONTEXT_KEEPER_STATE

Schema for `.supervisor/state.md` managed by Context-Keeper.

```yaml
version: integer                       # required — monotonic counter, increments on every write
current_phase: enum [INIT, ACQUIRE, PLAN, EXECUTE, FINALIZE, SELF_HEAL, LOOP]  # required
session_id: string                     # required — unique session identifier
task_id: string                        # required — current task being worked on
task_title: string                     # optional — human-readable task description
branch: string                         # required after ACQUIRE — feature branch name
config:
  max_workers: integer                 # default 2
  mode: enum [parallel, sequential]    # default parallel
  cost_profile: enum [default, cheap]  # optional — default "default"; set from --cheap flag at INIT
active_subtasks: object[]              # required during EXECUTE
  - id: string
    status: enum [pending, in_progress, completed, failed]
    worktree_path: string              # optional — only for parallel mode
    branch: string                     # optional — subtask branch
    agent_id: string                   # optional — Task agent ID
completed_subtasks: string[]           # subtask IDs that are done
failed_subtasks: string[]              # subtask IDs that failed
worktrees: object[]                    # active worktree tracking
  - task_id: string
    path: string
    branch: string
    status: enum [active, merged, cleaned, failed]
agents_running: object[]               # currently spawned agents
  - agent_type: string                 # e.g., "worker", "code-reviewer"
    task_id: string
    started_at: timestamp
self_heal_resume_count: integer        # optional — default 0; increments exactly once per --continue run, at Phase 4.5 entry (on-entry step 3 via record_self_heal_resume) — the single increment site. Repeated broken resumes therefore age into the self_heal_resume_thrash escalation after 3, which is intended: thrash is detected at entry, before the reviewer runs. Resets to 0 in the SELF_HEAL completion tail on the three completion exit paths (PASS, ESCALATED, or loop-skipped via --skip-self-heal); the invariant-violation guard (step 0) exits with status: failed before reaching the reset step and deliberately does NOT reset, preserving prior legitimate reviewer-reaching counts. Thrash guard: if the counter reaches 3, Supervisor aborts the loop and escalates with self_heal_resume_thrash reason. Lazy-added on the first --continue run landing in SELF_HEAL; mutated (and read from the returned count) via the record_self_heal_resume operation at phase entry.
last_updated: timestamp                # required — ISO 8601
```

**Phase note:** `SELF_HEAL` (added in v11.0.0) is the post-FINALIZE holistic review + bounded fix loop. Entered after PR creation; exits to LOOP after PASS or ESCALATED outcome, or when `--skip-self-heal` short-circuits the review loop (completion tail still runs).

**Validation rules:**
- `version` starts at 1 and monotonically increases on every write
- `current_phase` must be one of: `INIT`, `ACQUIRE`, `PLAN`, `EXECUTE`, `FINALIZE`, `SELF_HEAL`, `LOOP`
- `last_updated` must be in ISO 8601 format
- `active_subtasks` required when `current_phase = EXECUTE`
- `branch` required after `ACQUIRE` phase (all subsequent phases)
- `session_id` and `task_id` must be non-empty strings

---

