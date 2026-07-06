---
name: state-management
description: State file schema, .supervisor/ directory setup, checkpoint and resume protocols. Use when managing Supervisor session state across phases.
allowed-tools: [Read, Write, Edit, Bash]
version: "1.2.0"
lastUpdated: "2026-07"
---

# State Management Skill

Patterns for externalizing Supervisor state to files, enabling cross-session resume.

## Quick Rules

- Context-Keeper writes the state file on the **parallel path** (blocking calls for mutations); on the **inline main-thread path** the Supervisor best-effort-writes the same canonical `## Session` block directly — one canonical lowercase format either way (see "Inline-path write responsibility" below). Workers never write the state file.
- State file lives in scratchpad during active session
- Persistent copy in `.supervisor/state.md` for cross-session resume
- Checkpoints saved to `.supervisor/` only
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
- max_workers: 2
- mode: parallel | sequential
- cost_profile: default | cheap   # optional — default "default"; set from --cheap flag at INIT; read back during resume to keep cheap runs cheap across checkpoints

## Session
- session_id: {uuid}
- task_id: BD-XX | task-short-desc
- branch: feature/BD-XX-desc
- phase: INIT | ACQUIRE | PLAN | EXECUTE | FINALIZE | SELF_HEAL | LOOP
- status: running | paused | completed | completed_with_escalation | failed
- self_heal_resume_count: {integer, default 0}   # optional — increments only on resumes that actually execute the `code-reviewer` Task in Phase 4.5 (first loop iteration), NOT on every `--continue` landing in SELF_HEAL. This prevents Phase 4.5 invariant-violation runs (where `code-reviewer` was never invoked and `--skip-self-heal` was not set) from aging into a `self_heal_resume_thrash` escalation. Resets to 0 on every SELF_HEAL completion-tail exit that reaches the reset step (PASS, ESCALATED, or loop-skipped via `--skip-self-heal`); the invariant-violation path deliberately does NOT reset, preserving prior legitimate reviewer-reaching counts. Thrash guard: if the counter reaches 3, Supervisor aborts the loop and escalates with `self_heal_resume_thrash` reason. Mutated via Context-Keeper's `record_self_heal_resume` operation; read non-mutatively via `query(section: session)`. Lazy-added on first SELF_HEAL resume that runs the reviewer; not present in initial state.

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
_The Phase 1.5 PRE-FLIGHT SYNC outcome is recorded here as an ordinary Decisions Log entry via `record_decision(phase: PRE_FLIGHT_SYNC, …)` — there is NO dedicated state-file section for it. See the "Phase 1.5 Pre-Flight Summary" subsection below._
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

## Phase Flags    # optional — created on first set_flag; removed when last flag cleared. See "Phase Flags" subsection below.
- **{flag_key}**: {JSON-rendered value — single-line or fenced multi-line}
```

---

## Phase Flags

Added in v14.0.0 to support short-lived cross-phase markers — most notably the `base_mismatch_detected` and `non_interactive` flags consumed by the autonomous-loop crash-recovery path (W-NEW-14 mitigation). Phase flags are an explicitly *separate* schema region from the main session sections so that callers can add and clear ephemeral markers without touching the structured upper sections (`## Session`, `## Subtasks`, `## Checkpoint`).

### Placement

`## Phase Flags` is the **last** section of the state file, placed **immediately after `## Checkpoint`**. Positional-read verification (`grep -r "## Checkpoint"` across the plugin tree) confirms no parser currently treats `## Checkpoint` as a terminating sentinel — every consumer reads by section header, not by file-end position — so appending a new section after it is safe. If a future positional reader is introduced, this section MUST be relocated to immediately *before* `## Checkpoint` and that change documented here.

### Section format

````markdown
## Phase Flags
- **base_mismatch_detected**: {"detected_at": "2026-05-16T22:00:00Z", "expected_base": "main", "actual_base": "feature/v13.1"}
- **non_interactive**: true
- **resume_payload**:
  ```json
  {
    "phase": "EXECUTE",
    "subtask_progress": "2/5",
    "next_action": "spawn worker for S3"
  }
  ```
````

Each entry is a markdown list item:
- The key is the flag name wrapped in `**bold**`.
- The value is JSON-rendered immediately after the `: ` separator.
- Scalar/object/array values that fit on a single line render inline.
- Multi-line objects are rendered as a fenced ` ```json ` block on the next line for readability — Context-Keeper accepts both forms on read.

### Lifecycle

- The `## Phase Flags` section is **created on first `set_flag`** by Context-Keeper. The section header does not appear in a freshly `initialize`-d state file.
- Entries are added/replaced by `set_flag`, read non-mutatively by `get_flag`, and removed by `clear_flag`.
- When `clear_flag` removes the **last remaining** flag, Context-Keeper also removes the `## Phase Flags` header line so the file does not retain a stub section. The section reappears the next time `set_flag` is invoked.
- `clear_flag` of an absent key (or against a state file with no `## Phase Flags` section at all) is a silent no-op — no error, no write. This is required by AC-8 of v14.0.0.

### Read-on-start, clear-on-start invariant (crash-recovery flags)

Flags written by one phase and *consumed by a later phase on resume* — most prominently `base_mismatch_detected` from the autonomous-loop branch-base check (see W-NEW-14 in the v14.0.0 brief) — follow a **read-on-start, clear-on-start** discipline:

1. The producing phase calls `set_flag(key, value)` before exiting (e.g., before a planned crash, a paused state, or a hand-off).
2. The consuming phase, on entry, calls `get_flag(key)` to retrieve the marker.
3. The consuming phase calls `clear_flag(key)` **immediately after** reading, in the same phase entry — before any work that could itself crash and require recovery.

The order — read, then clear, then act — guarantees that a crash between `set_flag` and the consumer's first action does not lose the marker (the flag survives crashes), while a crash *after* `clear_flag` does not double-replay the marker on the next resume.

Flags that do NOT follow this invariant (for example, run-mode toggles like `non_interactive` that should persist across multiple phases) document their lifecycle separately at the call site.

### Example

A run that pauses mid-execution after detecting a base mismatch and is later resumed in non-interactive mode might briefly hold the following section in `state.md`:

```markdown
## Phase Flags
- **base_mismatch_detected**: {"detected_at": "2026-05-16T22:00:00Z", "expected_base": "main", "actual_base": "feature/v13.1"}
- **non_interactive**: true
```

On resume, the autonomous loop's entry handler reads both flags, then immediately clears `base_mismatch_detected` (a crash-recovery flag) while leaving `non_interactive` set (a run-mode flag with a different lifecycle).

### Operations contract

The full operation specs (parameters, return values, atomicity, error handling) for `set_flag` / `get_flag` / `clear_flag` live in `agents/context-keeper.md` under "Phase Flag Operations (v14.0.0)". Never edit the `## Phase Flags` section by hand — always go through Context-Keeper, like every other section of the state file.

---

## Phase 1.5 Pre-Flight Summary

Added in v14.8.0 to support the Supervisor's **Phase 1.5 PRE-FLIGHT SYNC** gate, which runs *after* Phase 1 ACQUIRE and *before* Phase 2 PLAN. After the gate fetches remote state, derives the canonical version/base branch, and classifies the requested work, Context-Keeper records the outcome as an **ordinary `## Decisions Log` entry** in `state.md` — exactly the way other phases record a one-line outcome. There is **no dedicated state-file section** for the pre-flight summary; it lives in the existing Decisions Log. This makes the gate outcome auditable in the persistent state, consistent with how every other phase's result is captured.

### Mechanism — `record_decision`

The summary is recorded via the **existing** `record_decision` operation (not a new operation), using the `PRE_FLIGHT_SYNC` phase:

```
record_decision(phase: PRE_FLIGHT_SYNC,
                decision: <preflight_clear | preflight_overlap_proceed | preflight_superseded_proceed | preflight_revise_scope | preflight_abort | preflight_skipped>,
                rationale: "<canonical version, base tip SHA, no overlap | overlapping commit SHAs/PR numbers + intersecting file paths>")
```

This matches exactly how `agents/supervisor.md` Phase 1.5 records the gate outcome (`record_decision(phase: PRE_FLIGHT_SYNC, …)`). The `decision` values are verbatim the strings Supervisor emits: `preflight_clear` (CLEAR — AC2 silent record), `preflight_skipped` (`--skip-preflight-sync` escape hatch); for the OVERLAP/SUPERSEDED proceed, revise-scope, and abort paths Supervisor mirrors the same `preflight_` prefix — `preflight_overlap_proceed`, `preflight_superseded_proceed`, `preflight_revise_scope`, and `preflight_abort`. The resulting row appears in `## Decisions Log` like any other decision.

### What the rationale captures

The `rationale` captures four things on one line:

1. the **canonical version** the gate derived;
2. the **base-branch tip SHA** — `origin/$BASE_BRANCH`'s tip at fetch time;
3. the **classification** — the human-readable concept is exactly one of `CLEAR | OVERLAP | SUPERSEDED`; it is carried in the `decision` field as the corresponding verbatim Supervisor string (`preflight_clear` / `preflight_overlap_proceed` / `preflight_superseded_proceed`, or `preflight_abort` on the abort path);
4. the **overlap detail** — the literal string `no overlap` for a `CLEAR` classification, OR the overlapping commit SHAs / PR numbers plus the intersecting file paths for an `OVERLAP` / `SUPERSEDED` classification.

A `CLEAR` example (the AC2 silent record — Supervisor proceeds to Phase 2 with no extra prompt while still capturing the one-line summary), shown as it lands in the Decisions Log:

```markdown
## Decisions Log
| # | Phase | Decision | Rationale |
| 3 | PRE_FLIGHT_SYNC | preflight_clear | version: 14.8.0, base_tip: a1b2c3d, no overlap |
```

An `OVERLAP` example — the rationale cites the specific commits/PRs and the intersecting files (the same evidence the interactive `AskUserQuestion` surfaces and the CI fail-closed abort diagnostic prints):

```markdown
## Decisions Log
| # | Phase | Decision | Rationale |
| 3 | PRE_FLIGHT_SYNC | preflight_overlap_proceed | version: 14.8.0, base_tip: a1b2c3d, PR #41, commit 9f8e7d6 ; files: agents/supervisor.md, docs/RESULT_SCHEMAS.md |
```

### Write path

Like every other Decisions Log entry, the pre-flight summary is written **only by Context-Keeper** — never edited by hand and never written directly by Supervisor. The CLEAR-path write is the silent record AC2 requires (Supervisor proceeds to Phase 2 with no extra prompt while still capturing the one-line summary); the OVERLAP/SUPERSEDED-path write records the classification that drove the interactive escalation or the CI fail-closed abort. The `--skip-preflight-sync` escape hatch likewise records a `record_decision` Decisions Log entry (`decision: preflight_skipped`) per the escape-hatch contract.

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

All mutations go through Context-Keeper (blocking call) on the **parallel path**. Workers never write the state file directly.

#### One on-disk format: the canonical lowercase `## Session` block

There is exactly **ONE on-disk format** for `.supervisor/state.md` — the canonical lowercase schema documented in §"State File Schema" above, where the `## Session` block carries lowercase `- branch: <feature-branch>` and `- status: running | paused | completed | completed_with_escalation | failed`. The **bold display blocks** that agents emit to their OUTPUT (the Supervisor's `## ENVIRONMENT` block, the `## Outcome` block — `- **Branch:** …` style) are **human-readable presentation only** and are NOT the state file. Never let a bold-style block become the on-disk state file.

Two downstream consumers read the on-disk canonical lowercase form and break on anything else:

- **`hook-dispatch-on-pr-create.sh`** — the post-PR review-drain backstop greps `^- status:` and `^- branch:`. A stale or bold-only state file makes its session-scope gate fail-closed, so the until-mergeable drain never dispatches.
- **`/supervisor --continue` resume** — reads the lowercase `status: running` to decide whether/where to resume.

#### Inline-path write responsibility (best-effort, non-fatal)

The canonical `## Session` block MUST land in `.supervisor/state.md` **regardless of whether Context-Keeper was spawned**:

- **Parallel path** (EXECUTE delegated to a Context-Keeper-backed Execute Manager): Context-Keeper is the canonical writer via `set_task` / `update_phase` at ACQUIRE and the SELF_HEAL completion tail.
- **Inline main-thread path** (where the poll loop is NOT delegated, so no Context-Keeper is spawned): the Supervisor writes the canonical lowercase `## Session` block **directly** — at ACQUIRE (`- status: running`, `- branch: <feature-branch>`) and at the SELF_HEAL completion tail (flip `- status:` to `completed`, or `completed_with_escalation` on ESCALATED).

This direct inline write is **best-effort / non-fatal**: it MUST NEVER block ACQUIRE or fail the run (preserving the fail-safe invariant). A write failure is a logged no-op. The direct write produces the SAME single canonical lowercase format — it does NOT introduce a second/competing format.

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
| `record_batch` | Multiple mutations in single call | Phase 3 (EXECUTE) |
| `checkpoint` | Full state snapshot to `.supervisor/` | After each phase |
| `set_flag` / `get_flag` / `clear_flag` | Mutates / reads / removes a key in `## Phase Flags` | Any phase (most often: producer phase sets, consumer phase reads + clears on entry) |

### Checkpoint Protocol

After each phase transition:

1. Context-Keeper updates `Session.phase` and `Checkpoint` section
2. Copy scratchpad state → `.supervisor/state.md`

```bash
# Checkpoint to .supervisor/
cp {scratchpad}/supervisor-state.md {project}/.supervisor/state.md
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

### Resume Priority

```
1. Scratchpad state file (freshest, same session)
2. .supervisor/state.md (persistent, cross-session)
3. No state found → start fresh (Phase 0)
```

### Resume validation gate

**The authoritative validation contract for `/supervisor --continue` (v15.3.0).** The Supervisor runs this gate at the earliest consumption point (Phase 0 INIT step 2), BEFORE any loaded state is consumed — regardless of whether the state came from the scratchpad or `.supervisor/state.md`. Every result block in the system is hook-validated; this gate closes the equivalent hole for resume-loaded local state.

1. **`## Session` block must exist** in the loaded file.
2. **`phase` must be in the closed set** `INIT | ACQUIRE | PLAN | EXECUTE | FINALIZE | SELF_HEAL | LOOP` — verbatim from §"State File Schema" above. `PRE_FLIGHT_SYNC` is a `record_decision`-only phase label used in Decisions Log entries (see §"Phase 1.5 Pre-Flight Summary"); it is NOT a valid state-file `phase` and fails this check.
3. **`status` must be in the closed set** `running | paused | completed | completed_with_escalation | failed` — verbatim from §"State File Schema" above.
4. **If a `branch:` field is asserted** in the `## Session` block, `git rev-parse --verify <branch>` must succeed (the branch must still exist locally). The value comes from an untrusted file (the gate's own premise): pass it as a single quoted argument, and pre-validate with `git check-ref-format --branch <value>` — a value failing ref-format fails this check.

**On ANY violation the resume is REFUSED:** the Supervisor emits `SUPERVISOR_RESULT` with `status: failed` and `error: "resume_state_invalid"`, plus a user instruction to inspect or delete `.supervisor/state.md` (or start fresh without `--continue`). It NEVER silently falls back to a fresh start — that would mask corruption. There is deliberately NO `--skip-*` / `--force-resume` escape hatch in v1: deleting the bad state file IS the escape hatch.

Scope notes:

- **A missing state file is NOT a violation.** "No state found → start fresh" (Resume Priority item 3 above) is unchanged; the gate fires only on a file that loaded but does not parse against this contract.
- **READ-side gate only.** The Context-Keeper sole-writer contract and the inline-path best-effort write responsibility (§"Inline-path write responsibility") are untouched — this gate validates what resume READS; it changes nothing about who WRITES.
- **A valid file resumes exactly as before** — the happy path (including `config.cost_profile` hydration at Phase 0) is behaviorally identical; only invalid files see new behavior.

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

## Quality Checklist

Before completing state management:
- [ ] `.supervisor/` directory exists with `.gitignore` entry
- [ ] State file has all required sections
- [ ] Checkpoint written after each phase transition
- [ ] Resume tested from both scratchpad and `.supervisor/`
- [ ] Batch updates used where possible (Execute Manager)
- [ ] Only Context-Keeper mutates state file
- [ ] Session history saved on completion

## See Also

- `skills/workflow-management/SKILL.md` - Workflow patterns
- `skills/async-orchestration/SKILL.md` - Parallel dispatch patterns
- `agents/context-keeper.md` - State management agent (full operation specs for `set_flag` / `get_flag` / `clear_flag` live there under "Phase Flag Operations (v14.0.0)")
