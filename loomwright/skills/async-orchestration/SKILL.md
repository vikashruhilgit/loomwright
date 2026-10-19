---
name: async-orchestration
description: Background dispatch patterns, non-blocking polling, parallelism decisions, git worktree lifecycle and the verbatim Subagent Spawn Contracts. Use when running parallel workers in Supervisor workflows. The Supervisor Phase 4 FINALIZE procedure and PR Body Template live in finalize.md, Read at Phase 4 entry only.
allowed-tools: [Read, Bash]
version: "1.7.0"
lastUpdated: "2026-10-19"
---

# Async Orchestration Skill

Parallel task execution with background workers, git worktrees and non-blocking polling. Why the rules read as they do: `docs/rationale/supervisor.md` §"Async orchestration — why the rules read as they do".

## Quick Rules

- Max concurrent worktrees: `config.max_workers` (default: 2)
- Each worker gets its own git worktree (no file conflicts)
- Only dispatch workers via `run_in_background: true`
- Poll with `block: false` first; fall back to `block: true` on idle
- Sequential merge into feature branch after all workers complete
- Clean up worktrees immediately after merge
- No per-subtask reviewer at any threshold, on any path: the `outputs_verified` gate + tests/lint is the per-subtask gate; Phase 4.5's integrated review is the sole LLM gate (`agents/orchestrator.md` §"Review Gate Policy")

---

## Parallelism Decision Logic

### Determining LAUNCHABLE vs BLOCKED

```
For each subtask S:
  LAUNCHABLE if:
    1. All depends_on tasks are completed (per-subtask gate passed)
    2. S.files do NOT overlap with any other LAUNCHABLE subtask's files
    3. Number of active worktrees < config.max_workers

  BLOCKED if:
    1. Has unresolved depends_on (predecessor not completed), OR
    2. Files overlap with a currently LAUNCHABLE subtask, OR
    3. Active worktrees at max capacity
```

### File Overlap Detection

Parse file lists from Orchestrator output. Two subtasks overlap if they modify any of the same files; overlapping subtasks must serialize.

### Single-Agent / Sequential Paths: Skip Worktrees

**Single-Agent Path** (exactly 1 subtask — default per `supervisor-readiness/SKILL.md` §"Decomposition Threshold"):
- Execute inline, no worktree/background dispatch; ONE worker runs ALL acceptance criteria
- NO per-subtask Code Reviewer — Phase 4.5 holistic review is the single review
- Skip all worktree lifecycle

**Sequential Path** (`--sequential`, more than 1 subtask — per `agents/supervisor.md` §"Sequential Path"):
- Execute all subtasks inline, sequentially; no worktrees, no background dispatch
- **NO per-subtask Code Reviewer** (Quick Rules)

---

## Git Worktree Lifecycle

### Phase 3 (EXECUTE — Execute Manager Step 2a): Create Branches

The **Execute Manager** creates branches for launchable subtasks at Phase 3 entry (its Step 2a) — never the Supervisor in Phase 2; Phase 2 (PLAN) runs no git commands:

```bash
git checkout feature/BD-XX-desc
git branch feature/BD-XXa      # from the feature branch HEAD
git branch feature/BD-XXc
```

### Phase 3 (EXECUTE): Create Worktrees

```bash
# Path: sibling directory with subtask suffix — write the LITERAL project name
# (the form execute-manager.md uses), never `$(basename $(pwd))`: the worktree
# audit observer parses the command string unexpanded (see its header, limit e)
git worktree add ../{project}-BD-XXa feature/BD-XXa
git worktree add ../{project}-BD-XXc feature/BD-XXc
```

**Naming convention:** `{project-dir}-{subtask-id}`

### Phase 4 (FINALIZE): Merge and Cleanup

Supervisor-only, at Phase 4: `skills/async-orchestration/finalize.md` steps 2–4 (commit each worktree, merge `--no-ff` in dependency order, salvage → remove each worktree → delete its branch).

### Merge Conflict Handling

If a merge fails: **Do NOT force resolve** — escalate to human (report, checkpoint and resume command: `finalize.md` step 3).

---

## Background Worker Dispatch

### Spawning a Worker

```
Task(
  description: "Implement subtask BD-XXa",
  prompt: "You are an implementation worker. ...",
  subagent_type: "loomwright:worker",
  run_in_background: true
)
→ Returns: { task_id: "agent-xxx", output_file: "/path/to/output" }
```

A worker is always `loomwright:worker`: the worker hooks (`validate-worker-result.py`, `emit-progress-event.sh`, `guard-arm.sh arm-from-payload`) match that type, so a `general-purpose` worker runs with none of them.

### Worker Prompt Template

```markdown
You are an implementation worker operating in a git worktree.

**Subtask:** {subtask_id} — {title}
**Worktree path:** {worktree_path}
**Brief (PINNED MAIN-CHECKOUT ABSOLUTE path):** {main_checkout_abs_brief_path} — read only your subtask's section. The gitignored brief does NOT exist inside your worktree; this path points at the main checkout.
**Acceptance-criteria summary (≤200 chars):** {bounded summary}

**Skill references:** {skill_refs}

**Instructions:**
1. Work ONLY in the worktree at {worktree_path}
2. Read relevant files to understand context
3. Implement the subtask meeting all acceptance criteria (full criteria: your subtask's section of the brief above)
4. Run tests if test infrastructure exists: run `bash scripts/ci-local.sh --affected` (the project's affected plan, which includes every static CI gate) where the project has it, else the project's own targeted check — never the full `ci-local.sh` pool from a background worker
5. Output a WORKER_RESULT block

{retry_context if applicable}
```

Pointer, not payload: the criteria travel as the summary + pinned brief path. Full spawn shapes: §"Subagent Spawn Contracts" below and `agents/execute-manager.md` Step 3.

---

## Non-Blocking Polling

### Poll Loop Pattern (Execute Manager)

The poll loop runs inside the Execute Manager (not the Supervisor), with iteration limits and back-off; `agents/execute-manager.md` Step 4 is the authoritative pseudocode.

```
active_workers = {worker_id: {subtask_id, output_file, worktree_path, status}}

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

      # Record worker result (direct call — one call per event)
      Task(Context-Keeper, operation: record_worker_result,
           worker_id: {worker_id}, subtask_id: {subtask_id},
           result: {files_modified, lines_added, lines_removed, tests_run, tests_passed, status, error},
           state_file: {state_file_path})
      tool_calls += 1
      # No reviewer is spawned here. If the on-disk outputs_verified gate passed
      # (verify-provides.sh, no gap), the subtask is complete — no record_review call.
      → Move worker to completed
      → Check if blocked subtasks now launchable

  # 2. Launch newly launchable subtasks
  for subtask in newly_launchable:
    if active_worktrees < max_workers:
      → Create worktree + spawn worker
      tool_calls += 2

  # 3. Back-off on idle
  if not results_found:
    idle_streak += 1
    if idle_streak >= 3:
      poll_interval = min(poll_interval * 2, 30000)  # exponential, cap 30s
    earliest = min(active_workers, key=start_time)
    TaskOutput(task_id=earliest.id, block=true, timeout=poll_interval)
    tool_calls += 1

  # 4. Tool call budget check
  if tool_calls >= 55:
    → Output EXECUTE_CHECKPOINT and EXIT
  if tool_calls >= 48:
    poll_interval = max(poll_interval, 5000)  # longer intervals
  if tool_calls >= 36:
    # compress summaries to <100 tokens
    pass
```

### Worker Summary File Protocol

Workers write `.worker-summary.md` in their worktree before outputting WORKER_RESULT. After TaskOutput confirms the worker is complete, the Execute Manager reads that file (~200 tokens); if it does not exist, it falls back to parsing the full TaskOutput.

### Result Collection

Record each completed worker's files modified, test results and `outputs_verified` outcome to Context-Keeper via `record_worker_result` (no `record_review` call). Only `## Session` is hook-derived (`scripts/emit-progress-event.sh`); `## Worker Results` and the `## Subtasks` table stay this step's job.

---

## Worker Result Protocol

### Worker Output Format

Workers emit a `WORKER_RESULT` block (`docs/RESULT_SCHEMAS.md` §WORKER_RESULT; hook-validated by `validate-worker-result.py`).

### No Per-Subtask Reviewer Output

None to collect (Quick Rules): the gate reads the worker's own `WORKER_RESULT.outputs_verified`.

---

## Dependency Materialization

BLOCKED subtasks declare `requires` against producing subtasks (schema: `skills/supervisor-readiness/SKILL.md`). Before spawning a BLOCKED subtask whose producers are complete, the Execute Manager must materialize each producer's outputs into the dependent worktree by **merging the producer branch into the dependent branch — never onto the main repo HEAD**.

**Materialization steps:**

1. Create the dependent's branch from `feature_branch` **as a ref only — do NOT switch the main worktree's HEAD**:
   ```bash
   git branch feature/<task>-<sub>-dep <feature_branch>
   ```
   Never `git checkout -b` — it moves the main worktree off the feature branch and breaks sibling parallel subtasks.

2. Create a worktree for the dependent subtask:
   ```bash
   git worktree add ../<repo>-<sub>-dep feature/<task>-<sub>-dep
   ```
   Equivalent one-shot form: `git worktree add -b feature/<task>-<sub>-dep ../<repo>-<sub>-dep <feature_branch>`.

3. Materialize each producer's outputs by merging the producer branch INTO the dependent worktree:
   ```bash
   git -C ../<repo>-<sub>-dep merge --no-ff feature/<task>-<producer-sub>
   ```
   One merge per producer listed in the dependent's `requires` set.

4. Only then spawn the worker into the dependent worktree.

**Invariants:**

- Merges happen in the dependent worktree only — never on the main repo HEAD
- The integration feature branch HEAD remains untouched until FINALIZE
- Each producer is merged exactly once per dependent worktree (idempotent if re-run after a clean checkout)

**Conflict policy:** If any merge conflicts during materialization, STOP immediately and escalate as a **Dependency Merge Conflict** failure mode. Do NOT auto-resolve, do NOT commit a partial merge. Treat the dependent worktree as quarantined until the user resolves.

---

## Pre-Spawn Verification Gate

After dependency materialization and **before** spawning the worker, the Execute Manager runs a verification gate that proves each declared `requires` entry actually exists in the dependent worktree.

For each `requires` entry on the dependent subtask, run one check against `<worktree>/<path>`: the commands are the three rows `scripts/verify-provides.sh --kind-table` prints (the ONE implementation; runtime invocation: Execute Manager Step 2b) with `<root>` = the worktree — never restated here.

**Pass criterion:** ALL checks for ALL `requires` entries must PASS.

**Fail handling:** If any check fails, the dependent subtask is held back (worker is NOT spawned) and an `EXECUTE_CHECKPOINT` is emitted with `adjudication_required: true` (see Scope Expansion Adjudication below) — the Execute Manager cannot resolve a producer's false `provides` claim unilaterally.

---

## Scope Expansion Adjudication

When pre-spawn verification fails OR a worker reports `outputs_gap` non-empty in its WORKER_RESULT, the Execute Manager emits an `EXECUTE_CHECKPOINT` with `adjudication_required: true` carrying four options.

The Execute Manager **NEVER picks an option itself** — it always escalates to the Supervisor.

**The four options:**

- **A: Re-queue producer** — retry the producing subtask with the missing outputs added to its acceptance criteria. Risk: the gap recurs on brief drift.
- **B: Insert remediation subtask** — add a new subtask whose sole job is to provide the missing outputs. Risk: the brief no longer matches the executed plan.
- **C: Exit to Launch Pad** — abort the run; the brief itself is incoherent and needs replanning.
- **D: Update consumer brief** — consumer no longer needs the missing item; remove the `requires` entry. Risk: silent scope reduction.

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
- [ ] No per-subtask reviewer is spawned at any threshold

---

# Part 2 — Supervisor FINALIZE Protocol (`finalize.md`) & Spawn Contracts

## Phase 4 FINALIZE procedure (steps 1–7)

Steps 1–7 (incl. 5.5, 6.5), the safety guarantees and the **PR Body Template** live in `skills/async-orchestration/finalize.md`, Read at Phase 4 FINALIZE entry only; a citation of this file's "Part 2" steps or "Part 2 PR Body Template" (the next-step driver's included) means that file. §"Subagent Spawn Contracts" stays here (needed from Phase 2 on).

## Subagent Spawn Contracts

Exact Task tool call shapes for each subagent.

**Prompt-cache discipline:** Within each `prompt:` string, put stable content (role/skill guidance, project patterns, cost_profile notes, house-rules advisory text) before volatile interpolations (task id, title, criteria, worktree/feature_branch/state_file paths, resume context, files_modified, operation/data payloads). Prompt caching is prefix-match — an early volatile value invalidates the cache for every subsequent spawn.

**Pointers, not payloads (transport discipline):** pass a file-backed spawn input (brief, plan file, corpus) as its PATH + a ≤200-char summary + "Read only the sections you need" — never the body. Gitignored `.supervisor/` artifacts do NOT exist inside linked worktrees: a worktree-resident consumer gets the MAIN-CHECKOUT absolute path, said so in the prompt; project-root consumers use the repo-relative path. **No brief file** (`/supervisor task:` no-brief mode, or `task: BD-XX` Beads mode): every `Brief:` line below points at `.supervisor/requirements/{slug}-plan.md` (Beads-absent) or `bd show {id}` (Beads) instead, or passes the criteria inline. Paste exceptions (e.g. the worker `provides:` YAML) and the no-brief exception: `docs/POINTER_AUDIT.md`. Transport-only: never changes which gates, schemas, decisions or spawn cardinality apply.

**Context digest pointer:** every worker spawn also carries the per-job `CONTEXT_DIGEST` (`docs/RESULT_SCHEMAS.md` §"CONTEXT_DIGEST") as a pointer — **path + ≤200-char summary + "Read only the sections you need"**, never pasted: repo-relative `.supervisor/jobs/context-digests/{basename(brief_path)}` for project-root workers; **parallel-path (worktree-resident) workers MUST receive the MAIN-CHECKOUT ABSOLUTE path instead, and the prompt text must say so** (the Supervisor hands it to Execute Manager, which forwards it unchanged). An absent digest never blocks a spawn — the worker proceeds without it.

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
  prompt: "Project context: {CLAUDE.md summary}\ngoal: \"{task_id}: {title}\"\nBrief: {brief_path} — read only the sections you need (## Task, ## Acceptance Criteria, ## Subtask Structure if present).\nAcceptance-criteria summary (≤200 chars): {bounded summary}",
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
    Brief: {brief_path} — read only the sections you need (## Subtask Structure, ## Subtask Contracts, per-subtask criteria, per-subtask `lanes:`). Gitignored main-checkout path: it resolves for YOU (you run at the project root) but NOT inside worker worktrees.
    Context digest: {context_digest_path} — MAIN-CHECKOUT ABSOLUTE path (resolves for you at the project root; forward it UNCHANGED, still as the main-checkout absolute path, to each worker you spawn into a worktree — see §"Context digest pointer" above) + ≤200-char summary + "Read only the sections you need". Advisory only — proceed without it if the file does not exist.
    Subtask index (compact — ids/titles/deps only, no pasted criteria/file lists): [{ids, titles, deps}]
    Parallelism graph: [{launchable, blocked}]
    Resume context: {optional, from previous EXECUTE_CHECKPOINT}",
  subagent_type: "loomwright:execute-manager",
  model: "sonnet"   # ONLY when cost_profile=cheap; omit entirely when cost_profile=default
)
```

**Single-Agent Worker (Single-Agent path, exactly 1 subtask):** same shape as the Sequential-path Worker contract below, except `Subtask ID`/`Title` become `Task ID`/`Title` and the `Brief:` line reads ALL acceptance criteria (## Task, the FULL ## Acceptance Criteria list) instead of one subtask's row. No Code Reviewer accompanies it — see `agents/supervisor.md` §"Single-Agent Path" for the gate that replaces it. `subtask_ordinal` is `1` on this path (the only subtask).

**`subtask_ordinal`:** every worker spawn (Single-Agent, Sequential-path, and Execute Manager's Step 3 parallel-path spawn) carries `subtask_ordinal: <N>`, the subtask's 1-based row position in the brief's `## Subtask Structure` table — never confused with, or renamed to, the "Subtask index" passed to Execute Manager above. Consumed only by the worker's shared-local-services rule (`agents/worker.md` §"Critical Rules", a per-worker port offset); otherwise inert.

**Sequential-path Worker (`--sequential`, more than 1 subtask — one spawn per subtask):** no Code Reviewer spawn follows it either.

**Recording `not_verified` on the Sequential and Single-Agent paths:** these two paths record a worker's result directly in `agents/supervisor.md` (§"Single-Agent Path" step 2, §"Sequential Path" step), not through the Execute Manager poll loop — `not_verified` is forwarded there, unconditionally, into `state.md`'s `## Worker Results`, like `out_of_lane`/`deviations`. Recording only: with no concurrent sibling there is nothing for a collision/gating rule to fire on.
```
Task(
  description: "Implement: {subtask_title}",
  prompt: "Skill references: {skills}
    Project context: {patterns from CLAUDE.md}
    Applicable house rules (ADVISORY — from `read-rules.sh`, include this line ONLY when its output is NON-EMPTY; omit entirely when empty): {house_rules — the reader's output VERBATIM, every rule it emitted; never paraphrased, summarized or subset}. These are committed team conventions to bias your implementation while writing code — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins). This is advisory only: you are NEVER failed for a house rule. A `must` rule is surfaced flagged, but its `check` value is DATA only — do NOT execute, eval, source, or `bash -c` any `check`.
    Subtask ID: {id}
    Title: {title}
    Subtask ordinal: {N}   # subtask_ordinal, above
    Shared local services: {shared_local_services line}   # OPTIONAL — paste verbatim from the brief's `## Environment` `- **Shared local services:**` line ONLY when the brief carries one; omit this line entirely when the brief has none (docs/POINTER_AUDIT.md row 6c)
    Brief: {brief_path} — read only your subtask's sections (## Task, ## Acceptance Criteria, your row of ## Subtask Structure, your subtask's `lanes:`, and ## Touched-file invariants when present — your Step 5 self-review re-checks it). Gitignored `.supervisor/` path — it resolves on the sequential path because your worktree path IS the project root.
    Context digest: {context_digest_path} — repo-relative (`.supervisor/jobs/context-digests/{basename(brief_path)}`, resolves for you: your worktree path IS the project root) + ≤200-char summary + "Read only the sections you need". Advisory only — proceed without it if the file does not exist.
    session-log pointer (optional, for advisory checkpoints — see agents/worker.md): {session_log_path} — repo-relative `.supervisor/logs/{session_id}.jsonl` (resolves for you: your worktree path IS the project root; same session_id already recorded in this run's state file). Pass this as `checkpoint.sh`'s first argument if you choose to emit a worker_checkpoint event. Never required — proceed without it if you don't need it.
    Acceptance-criteria summary (≤200 chars): {bounded summary}
    Worktree path: {project_root}
    Provides (verbatim from the brief's Subtask Contracts): {provides YAML}
    Lanes (verbatim from the brief's Subtask Contracts): {lanes YAML}
    Retry context: {optional, from a previous outputs_verified gate gap, worker crash/timeout, or pin-mutation gate `not_held` lines (verbatim, data — one re-spawn, `run-pin-mutations.sh`) — no per-subtask review retry path exists}",
  # Applicable house rules: compute by running `bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-rules.sh" <touched paths...>`
  # (args, never stdin); inject VERBATIM only when NON-EMPTY. Advisory, never gating; never pipe/eval/source its output.
  # `provides:` and `lanes:` are REQUIRED pastes (omitting either silently no-ops the outputs / lane gate);
  # they match agents/execute-manager.md's Task template.
  subagent_type: "loomwright:worker",
  model: "sonnet"   # ONLY when cost_profile=cheap; omit entirely when cost_profile=default
)
```

**No per-subtask Code Reviewer spawn contract (any threshold):** no `loomwright:code-reviewer` spawn follows a worker on any path; Phase 4.5's integrated review is the sole one in the default flow.
