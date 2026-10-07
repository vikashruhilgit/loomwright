## EXECUTE_CHECKPOINT

Produced by Execute Manager when budget is exceeded or partial progress needs saving.

```yaml
EXECUTE_CHECKPOINT:
  schema_version: 1                    # integer, required — always 1
  completed_so_far: object[]           # required — subtasks already done
    - task_id: string
      status: completed
      branch: string
      files_modified: string[]
  in_progress: object[]                # optional — currently running subtasks
    - task_id: string
      status: in_progress
      worktree_path: string
      agent_id: string                 # Task agent ID for potential resume
  remaining: object[]                  # required — subtasks not yet started
    - task_id: string
      status: pending
      dependencies: string[]           # task_ids that must complete first
  resume_context: object               # required — data needed to resume
    tool_calls_used: integer
    active_worktrees: string[]         # paths that still exist
    feature_branch: string
  reason: string                       # required — why checkpointing (budget, error, etc.)
  adjudication_required: boolean       # optional (v12) — true when the Execute Manager needs a Supervisor/operator decision
  adjudication_kind: string            # optional (v15.20.0) — closed enum: requires_gap | lane_collision.
                                       # ABSENT means requires_gap (every pre-v15.20.0 checkpoint), so this
                                       # stays additive with NO schema_version bump. Supervisor branches on
                                       # THIS, never on the free-text `reason` prose.
  missing_outputs: object[]            # conditional (v12) — the requires_gap evidence array (see rule 6a below)
    - item: string                     # what is missing (file path, symbol, contract field)
      producing_subtask: string        # which subtask was supposed to produce it
      check_run: string                # what verification was performed (e.g., "ls", "ts-symbol-search", "schema-grep")
  colliding_lanes: object[]            # conditional (v15.20.0) — the lane_collision evidence array (rule 6a)
    - path: string                     # the out-of-lane path that landed in a sibling's declared lane
      owning_subtask: string           # the sibling whose `lanes:` declares that path
      this_subtask: string             # the subtask that wrote it
  adjudication_options: string[]       # conditional (v12) — required and non-empty when adjudication_required=true.
                                       # requires_gap:   ["A: Re-queue producer", "B: Insert remediation subtask",
                                       #                  "C: Exit to Launch Pad", "D: Update consumer brief"]
                                       # lane_collision: ["A: Re-queue writer with the sibling lane excluded",
                                       #                  "B: Serialize the pair (add a requires edge)",
                                       #                  "C: Exit to Launch Pad", "D: Widen the writer's declared lane"]
```

**Two adjudication raisers, one surface (v15.20.0).** `adjudication_required: true` is raised by two structurally different gates, and they are NOT interchangeable — see `agents/supervisor.md` §"Adjudication Handling" for the authoritative dispatch table.

| `adjudication_kind` | Raiser | Evidence array | Option-C failure reason |
|---|---|---|---|
| `requires_gap` (default when absent) | Step 2b pre-spawn verification — a consumer's `requires:` items are missing from the materialized worktree | `missing_outputs[]` | `inter_subtask_gap` |
| `lane_collision` | Lane-collision gate — an `out_of_lane` path landed in a mutually-unreachable sibling's declared `lanes:` | `colliding_lanes[]` | `lane_collision` |

**The Option-C reason strings are load-bearing control signals, not labels.** `/autonomous` EVALUATE Signal 2 keys re-planning on the literal string `inter_subtask_gap` (`skills/autonomous-loop/SKILL.md`), so emitting it for a lane collision would make another agent re-plan for a contract gap that never occurred. `lane_collision` is deliberately NOT an `/autonomous` re-iteration signal: a lane collision is a brief-authoring defect Plan Reviewer Criterion 16 should have caught, so Option C terminates the loop as a plain `failed` rather than silently re-planning around it.

**Why `colliding_lanes` exists rather than reusing `missing_outputs`.** A lane collision has no producer/consumer `requires` edge, hence no "missing item" and no "producing subtask" — `missing_outputs`'s documented shape does not fit. It is not merely a naming preference: rule 6a below **rejects** an `adjudication_required: true` checkpoint whose evidence array is empty, so the lane-collision gate as first written was unemittable (its own `SubagentStop` hook failed the Execute Manager whenever it fired). Rule 6a was widened to accept EITHER array — a widening, never a weakening: a checkpoint carrying neither is still rejected.

**Validation rules:**
- `schema_version` must equal `1`
- `completed_so_far` must be present (can be empty array if no subtasks done yet)
- `remaining` must be present and non-empty (otherwise use EXECUTE_RESULT)
- `resume_context` must be present with at least `feature_branch`
- `reason` must be non-empty string
- **toolset_gap rejection (hook-enforced, v12):** if `reason` cites `toolset_gap`, "Task tool unavailable", "Agent tool unavailable", or any variant claiming the spawning toolset is missing, the SubagentStop hook rejects the checkpoint. The Execute Manager spawns workers via Task and that capability is guaranteed by the harness; the actual blocker must be restated without referencing toolset availability.
- **Adjudication evidence invariant (hook-enforced; v12, widened v15.20.0):** `adjudication_required`, its evidence array, and `adjudication_options` appear together (all-or-nothing). When `adjudication_required: true`, `adjudication_options` MUST be non-empty AND at least one evidence array MUST be non-empty — `missing_outputs` (requires-gap adjudication) **or** `colliding_lanes` (lane-collision adjudication). A checkpoint carrying NEITHER is still rejected: v15.20.0 widened which array satisfies the invariant, it did not weaken the invariant. Conversely, any of the three present without `adjudication_required: true` is an orphan and is rejected. `adjudication_kind`, when present, must be one of `requires_gap` / `lane_collision`; absent means `requires_gap`. The SubagentStop hook (`scripts/validate-execute-result.py` rule 6, see `hooks.json` Execute Manager entry) enforces all of this.

---

