# Supervisor Phases 0–4 — the pre-driver prose (legacy path only)

> **Read ONLY on the legacy path:** `/supervisor --legacy` (automate-speed/11, owner decision D5 — retired later, the automate-speed/08 retirement pattern), and the runs the driver does not cover: `--continue` (after the Resume validation gate passes), a run with no `job:` brief (`task:`, interactive or auto-selected), and `--sdk-runner`. Everywhere else the authority for every step below is `scripts/supervisor-next-step.sh` — its instruction and `--result` shapes: `docs/result-schemas/supervisor-result.md` §"supervisor next-step instruction"; how the main thread calls it: `commands/supervisor.md` §"Next-step driver (Phases 0–4)".
>
> **Frozen at base `a8819a3`.** Each block below was moved VERBATIM out of the file and section its heading names, where a short pointer to the driver step now stands in its place. It is not maintained: a behaviour change goes into the driver and its golden cases (`scripts/fixtures/supervisor-golden/`), never here. Phase 4.5 and Phase 5 never moved — they stay in `skills/self-heal-advisory/SKILL.md` Part 2 and `agents/supervisor.md`.

## How to read it

Run each phase from its usual stanza (`commands/supervisor.md`, the phase skill Read at phase entry, `agents/supervisor.md` on the delegated path). Where that stanza now names a driver step, follow the matching block below instead, in the place it held. Cross-references inside a block ("step 4 above", "see Phase 1 ACQUIRE step 5", "the skill Part 2") resolve in the block's source file. A block cut from a numbered list keeps its original numbering and indentation.

## Phase 0 INIT

### `commands/supervisor.md` §"What This Does" — the Phase 0 paragraph

**Phase 0 (INIT):** Session configuration resolution before any work begins — environment auto-detection, resume-state loading behind the fail-closed resume validation gate, config prompts, cost-profile resolution (`--cheap`), base-branch handling (`--base-branch`, else `scripts/resolve-base-branch.sh`), `--non-interactive` recording as a Phase Flag, `.supervisor/` bootstrap, and job-brief loading. Protocol authority: `skills/supervisor-config/SKILL.md` (Read at phase entry — deliberately not preloaded); `agents/supervisor.md` "Phase 0: INIT" keeps the short phase stanza with entry/exit conditions. The user-facing flag table above remains this command surface's own authority for flag syntax.

### `agents/supervisor.md` §"Phase 0: INIT" — the Entry paragraph

**Entry:** Session start — every invocation, fresh or `--continue` resume. When a `job:` brief is supplied, the planning questions are pre-answered by the brief: environment validation is skipped (already done by Launch Pad), the brief is moved `pending/` → `in-progress/` (skip the move if the path doesn't match `pending/` — backward compatibility with the old flat `jobs/` layout), and the session jumps to Phase 1 with enriched context — planning phases are pre-answered by the brief, freeing budget for Phase 3 execution. The flag-parsing preamble still runs on every entry.

### `agents/supervisor.md` §"Phase 0: INIT" — two exit conditions (Phase Flags, cost profile)

These two bullets followed the run-lock and Session Configuration bullets, which stay in place.

- `--non-interactive` recorded as a Phase Flag (`set_flag non_interactive`) when true, so later phases can re-read it after context loss; stale crash-recovery flags (`base_mismatch_detected`, `non_interactive`) cleared on entry. `--max-tokens N`, when present, is likewise recorded as a Phase Flag so Phase 3 can re-read it after context loss.
- `cost_profile` resolved: `--cheap` → `cheap`, else `default` (resume hydrates from saved state) — consumed at every subagent spawn in Phases 2, 3, and 4.5. Loop-shaping flags (`--skip-self-heal`, `--heal-iterations`) are likewise INIT-parsed and consumed by Phase 4.5.

### `skills/supervisor-config/SKILL.md` §"Protocol" — steps 3a, 4 and 5

3a. Parse cost profile flag (fresh start only — the resume path is handled by the resume-state check above):
   - If `--cheap` was passed: set `cost_profile = cheap`.
   - Otherwise: `cost_profile = default`.
   - Record in session memory — used at every subagent spawn in the Supervisor's Phases 2, 3, and 4.5.
4. Create `.supervisor/` directory structure if not exists:
   ```bash
   mkdir -p .supervisor/history .supervisor/jobs/pending .supervisor/jobs/in-progress .supervisor/jobs/done .supervisor/jobs/failed .supervisor/logs
   # `.supervisor/` must stay ignored (a bare line, or `/setup memory`'s managed block). Ask git, not the
   # file text: the managed block ignores the contents (`.supervisor/*` + `!.supervisor/memory/`) with no
   # bare line, and a bare line appended after it re-ignores the memory store. `.supervisor` itself is not
   # reliably reported, so probe two child paths; outside a repo / without git, fall back to the exact line
   gi=ignored
   for p in .supervisor/state.md .supervisor/logs/x.json; do
     git check-ignore -q --no-index "$p" >/dev/null 2>&1
     case $? in 0) ;; 1) gi=append ;; *) gi=fallback; break ;; esac
   done
   [ "$gi" = fallback ] && grep -qxF '.supervisor/' .gitignore 2>/dev/null && gi=ignored
   [ "$gi" = ignored ] || echo '.supervisor/' >> .gitignore
   ```
5. Initialize scratchpad state file via Context-Keeper:
   ```
   Context-Keeper(operation: initialize, config: {max_workers, mode, cost_profile}, session: {...})
   ```

### `skills/supervisor-config/SKILL.md` step 5a — items 0.5, 1, 2 and 2.5

Item 0 (the run-lock acquire) and items 2.6–2.10 (the Phase 4.5 flags) stay in place around these.

   0.5. **`--max-tokens N` token ceiling (red-team-hardening/06).** Parse `--max-tokens N` from argv (mirrors `--cheap`'s flag-vs-forwarded resolution — it arrives either directly or forwarded by `/autonomous`/`/automate`, unconditional-when-present). Default: unset (no ceiling — opt-in, byte-identical behavior). Record `MAX_TOKENS` in session memory AND as a Phase Flag (same re-read-after-context-loss convention as `NON_INTERACTIVE`, step 2 below) so Phase 3 can re-read it after a context-summarization round-trip. Consumed by the Phase 3 poll loop — see `agents/supervisor.md` Phase 3 "per-iteration token-ceiling check".
   1. Parse `--base-branch <name>` from argv. Default to `main` if absent. Record as `BASE_BRANCH` in session memory (used by the Supervisor's Phase 4 FINALIZE PR creation, Phase 4 self-verify, and Phase 4.5 spawn prompts).
   2. Parse `--non-interactive` from argv. Default to `false` if absent. Record as `NON_INTERACTIVE` in session memory. **Subagent context counts as the flag** (the Can't-ask rule — the **Cannot ask** bullet of the INIT config questions above): when this run executes as a subagent — the ask tool is absent from its tool set — set `NON_INTERACTIVE = true` even without the flag, so step 5 re-arms the `non_interactive` Phase Flag exactly as for the explicit flag and every Phase Flag reader (including the FINALIZE `gh` retry in `skills/async-orchestration/SKILL.md`) agrees after a context loss. A main-thread `/supervisor` has the ask tool, so this never fires there; step 4's clear-on-start still runs first on every entry, so the flag never outlives the session that set it.
   2.5. Parse `--skip-preflight-sync` from argv. Default to `false` if absent. Record as `SKIP_PREFLIGHT_SYNC` in session memory (consumed by the Supervisor's Phase 1.5 PRE-FLIGHT SYNC — the skip check in `skills/preflight-sync/SKILL.md` short-circuits the gate as a deliberate choice).

### `skills/supervisor-config/SKILL.md` step 5a — items 3, 4 and 5 (the crash-recovery flags)

   3. **W-NEW-14 mitigation — clear any stale `base_mismatch_detected` flag from a crashed prior session before this session can act on it:**
      ```
      Context-Keeper(operation: clear_flag, key: "base_mismatch_detected")
      ```
   4. **W-NEW-15 mitigation — autonomous-loop's session-scoped `non_interactive` flag is consumed read-once at every Phase 0; standalone `/supervisor` must treat the terminal as interactive:**
      ```
      Context-Keeper(operation: clear_flag, key: "non_interactive")
      ```
   5. **If `NON_INTERACTIVE == true`, re-arm the flag for this session** (so the Supervisor's Phase 4 FINALIZE / Phase 4.5 can re-read it after a context-summarization round-trip — W-NEW-10 LLM-recall residual mitigation):
      ```
      Context-Keeper(operation: set_flag, key: "non_interactive",
                     value: {set_at: "<ISO 8601>", source: "supervisor_flag" | "subagent_context"})
      ```
      When `NON_INTERACTIVE == false` the flag stays cleared.

### `skills/supervisor-config/SKILL.md` §"Protocol" — steps 6 and 7 (the job file, the guard arm)

6. Check for job file:
   - If `job:` parameter provided: read brief from path
   - If no `job:` but `.supervisor/jobs/pending/` has files < 24h old: ask user if they want to use one
   - If job file loaded:
     - Move brief from `pending/` → `in-progress/` (if brief is in `pending/`; skip move if path doesn't match `pending/` for backward compatibility with old flat `jobs/` layout)
     - Skip environment validation (already done by Launch Pad)
     - Pre-populate: task details, acceptance criteria, subtask hints, parallelism analysis, skill references
     - Jump to the Supervisor's Phase 1 with enriched context — planning phases are pre-answered by the brief, freeing budget for Phase 3 execution

7. **Arm the test-integrity guard (six-phase-loop-gaps/02):** run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/guard-arm.sh" arm supervisor`. This is one of the plugin's two prompt-step arm points (the other is `review-heal/SKILL.md`'s loop entry) — the `PreToolUse[Agent|Task]` hook backstop covers most spawns even if this step is skipped (a prompt step skipped is the plugin's own documented failure mode, see `skills/self-heal-advisory/SKILL.md` "Hook backstop"), but arming here as early as INIT closes the window before the first spawn. Record `record_decision("guard_armed: ok")` on exit 0, or `record_decision("guard_armed: failed: <stderr>")` on any non-zero exit — on `failed` the run proceeds visibly unguarded; the completion tail's `**Test guard:**` line states it (`skills/self-heal-advisory/completion-tail.md` step 2 — a run with no driver handover reads `unknown (no_driver_handover)`). Never block INIT on this — a failed arm is logged, not fatal.

## Phase 1 ACQUIRE

### `commands/supervisor.md` §"What This Does" — the Phase 1 paragraph

**Phase 1 (ACQUIRE) — idempotent branch creation (v15.16.x fix):** Task selection and the mandatory feature-branch creation (`git checkout -b feature/{task_id}-{short-desc}` off the fetched `$BASE_BRANCH` tip) are specified in `agents/supervisor.md` "Phase 1: ACQUIRE" step 4, which this inline path follows. Branch creation is **idempotent**: it detects an existing same-named branch first, reuses it only when its tip is byte-identical to the current `$BASE_BRANCH` tip (provably zero commits beyond base), and otherwise stops with a diagnostic (`error: "acquire_branch_collision"`) rather than guessing or deleting anything. This closes a hard-error resume gap — see `docs/TELEMETRY.md`'s honest-limits list residual 6: nothing writes `.supervisor/state.md` between branch creation and the first worker completion, so a crash in that window used to make `/supervisor --continue`'s "start fresh" path re-run `git checkout -b` against a branch the crashed run had already created.

### `agents/supervisor.md` §"Phase 1: ACQUIRE" — action 4, the idempotent branch guard

Action 4's HARD RULE paragraph and action 5 stay in place after it.

4. **MANDATORY: Create feature branch** (before ANY code work) — **idempotent** (v15.16.x fix): no `state.md` exists between branch creation and the first worker `SubagentStop` (step 5), so a crash there makes `/supervisor --continue` "start fresh" and re-enter this step for the SAME `{task_id}-{short-desc}`; `git checkout -b` must not hard-error on a branch that already exists:
   ```bash
   # BASE_BRANCH resolved in Phase 0 (skills/supervisor-config/SKILL.md) —
   # default "main", or --base-branch <name> for stacked /autonomous iters.
   BASE_BRANCH="${BASE_BRANCH:-main}"
   git fetch origin "$BASE_BRANCH"
   git checkout "$BASE_BRANCH" && git pull origin "$BASE_BRANCH"

   FEATURE_BRANCH="feature/{task_id}-{short-desc}"
   if git rev-parse --verify --quiet "refs/heads/$FEATURE_BRANCH" >/dev/null; then
     # Exists already — decide SAFELY, never guess, never delete.
     BASE_TIP="$(git rev-parse "$BASE_BRANCH")"
     BRANCH_TIP="$(git rev-parse "$FEATURE_BRANCH")"
     if [ "$BRANCH_TIP" = "$BASE_TIP" ]; then
       # PROVABLY SAFE: zero commits beyond $BASE_BRANCH — its tip IS the
       # current base tip, so reuse == fresh create (HARD RULE below holds).
       # Exactly the shape a crash leaves: branched, nothing committed yet.
       git checkout "$FEATURE_BRANCH"
     else
       # UNSAFE to reuse silently — unattributable commits (another
       # session's in-flight work, a further-along crash, or an unrelated
       # same-named branch). Do not check out, do not delete. STOP.
       echo "error: branch '$FEATURE_BRANCH' already exists and is NOT identical to $BASE_BRANCH tip ($BRANCH_TIP vs $BASE_TIP)." >&2
       echo "Inspect: git log $FEATURE_BRANCH --oneline -5 ; git diff $BASE_BRANCH...$FEATURE_BRANCH --stat" >&2
       echo "Then: resume it yourself if it's your crashed run, delete/rename it if disposable, or pick a different task_id/short-desc." >&2
       exit 1
     fi
   else
     git checkout -b "$FEATURE_BRANCH"
   fi
   ```
   On `exit 1` above: MUST NOT proceed to Phase 1.5/2 — emit `SUPERVISOR_RESULT` with `status: failed`, `error: "acquire_branch_collision: {FEATURE_BRANCH} diverges from {BASE_BRANCH} tip"`; leave any job file untouched (nothing was acquired). Distinct from `resume_state_invalid`/`resume_state_stale` (those are about a wrong existing `state.md`; this is a *branch* with no `state.md` to explain it) — don't conflate the three.

### `commands/supervisor.md` §"Inline-path canonical state writes" — the `state.json` session identification

  **Session identification:** identify the active session as the one whose `current_brief_path` basename matches the `job:` brief this Supervisor run is executing. If that is ambiguous or no such session is identifiable, **SKIP this write** (best-effort). Use a **jq-based atomic update** (read → `jq` set fields → temp-file → rename); fall back to a **logged no-op** on any error. **Best-effort / non-fatal — NEVER gates or fails the run.**

## Phase 1.5 PRE-FLIGHT SYNC

### `commands/supervisor.md` §"What This Does" — the Phase 1.5 paragraph

**Phase 1.5 (v14.8.0):** After ACQUIRE produces a task and a fresh feature branch, and before PLAN spawns the Orchestrator or any worker, Supervisor reconciles the *requested work* against remote state. It fetches `origin/$BASE_BRANCH`, scans recent commits and open PRs (bounded: ≤ 6 tool calls + a short timeout), derives the canonical version + base tip, and classifies the task **CLEAR / OVERLAP / SUPERSEDED** — flagging (a) recent/in-flight work touching the **same files** and (b) an **already-merged equivalent** of the requested work (the v13.1.0→v14.0.0 stale-branch case). CLEAR proceeds silently. OVERLAP/SUPERSEDED prompts the human (proceed-anyway / revise-scope / abort) citing the specific commits/PRs + intersecting paths interactively, or **fails closed** under `--non-interactive`/CI with `status_reason: preflight_overlap_detected`. Degrades gracefully (one warning, `preflight_sync: unverified`, continue) if `gh`/`git fetch` is unavailable, and is short-circuited by `--skip-preflight-sync`. It does **not** duplicate ACQUIRE's fetch/pull or the Phase 4 base-mismatch check — it adds semantic work-overlap reconciliation. Protocol authority: `skills/preflight-sync/SKILL.md` (Read at phase entry — deliberately not preloaded); `agents/supervisor.md` "Phase 1.5: PRE-FLIGHT SYNC" keeps the short phase stanza with entry/exit conditions.

### `agents/supervisor.md` §"Phase 1.5: PRE-FLIGHT SYNC" — the exit conditions

**Exit conditions (summary — the skill is authoritative):**
- **CLEAR** → proceed to Phase 2 silently (`preflight_sync = clear`).
- **OVERLAP / SUPERSEDED (interactive)** → soft-gate `AskUserQuestion` citing the specific commits/PRs + intersecting paths: proceed-anyway / revise-scope (checkpoint) / abort (`status: failed`, `error: "preflight_overlap_detected: {classification} — {cited commits/PRs + paths}"`).
- **OVERLAP / SUPERSEDED under `--non-interactive` / CI / stdin-not-a-TTY** → **fail closed**: `status: failed` with `SUPERVISOR_RESULT.error = "preflight_overlap_detected"` (surfaced by `/autonomous` as `AUTONOMOUS_RUN.status_reason`).
- **Tooling failure (`gh` / `git fetch` / timeout)** → graceful degradation: one warning, set `preflight_sync: unverified`, continue to Phase 2 — never hard-block.
- **`--skip-preflight-sync`** → short-circuit straight to Phase 2 as a deliberate choice, recorded via `Context-Keeper(operation: record_decision, phase: PRE_FLIGHT_SYNC, decision: "preflight_skipped")`, with `preflight_sync = skipped`.

### `skills/preflight-sync/SKILL.md` §"Protocol" — action 1, the skip check

1. **Skip check (AC5):** If `--skip-preflight-sync` was passed (parsed in Phase 0's base-branch / non-interactive preamble — see `skills/supervisor-config/SKILL.md`), record the skip as a deliberate choice and short-circuit straight to Phase 2:
   ```
   Context-Keeper(operation: record_decision, phase: PRE_FLIGHT_SYNC,
                  decision: "preflight_skipped", rationale: "--skip-preflight-sync flag")
   ```
   Set `preflight_sync = skipped` and proceed to Phase 2. Do NOT run any of the steps below.

### `skills/preflight-sync/SKILL.md` §"Protocol" — action 6, acting on the classification

6. **Act on the classification:**

   - **CLEAR (AC2 — silent):** proceed to Phase 2 with no extra prompt. Record a one-line pre-flight summary and set `preflight_sync = clear`:
     ```
     Context-Keeper(operation: record_decision, phase: PRE_FLIGHT_SYNC,
                    decision: "preflight_clear",
                    rationale: "version={canonical_version}, base_tip={BASE_TIP}, no overlap")
     ```

   - **OVERLAP / SUPERSEDED in an interactive session (AC3):** present an `AskUserQuestion` (mirroring **Launch Pad's** Phase 2.5 feasibility soft-gate) BEFORE spawning any worker. The question MUST cite the **specific overlapping commit SHAs / PR numbers AND the intersecting file paths**. Three options:
     - **proceed-anyway** → set `preflight_sync = overlap_proceed` (OVERLAP) or `superseded_proceed` (SUPERSEDED); record the decision (`record_decision(phase: PRE_FLIGHT_SYNC, decision: "preflight_overlap_proceed" | "preflight_superseded_proceed", rationale: "{cited commits/PRs + paths}")`); continue to Phase 2.
     - **revise-scope** → pause and checkpoint; do NOT spawn any worker. Keep the existing feature branch, `record_decision(phase: PRE_FLIGHT_SYNC, decision: "preflight_revise_scope", rationale: "{cited overlap}")`, and emit a single `SUPERVISOR_RESULT` with `status: checkpoint` and `preflight_sync: null` (the classification lives in the Decisions Log entry above, not the field — and a well-formed result block keeps the SubagentStop validator happy), then exit with a resume command. The user re-invokes `/supervisor` with the narrowed/redirected task (reusing the branch, or `git checkout $BASE_BRANCH && git branch -D feature/{old}` first if the new scope warrants a different branch name); Phase 1.5 then re-evaluates the revised scope against remote state on the next run. Do NOT silently fall through to Phase 2.
     - **abort** → fail the run cleanly (no worker spawned): record `record_decision(phase: PRE_FLIGHT_SYNC, decision: "preflight_abort", rationale: "{classification} — {cited commits/PRs + paths}")`, mark the task `failed`, move the job brief to `failed/` if a `job:` was used, and emit a single `SUPERVISOR_RESULT` with `status: failed`, `error: "preflight_overlap_detected: {classification} — {cited commits/PRs + paths}"`. Do NOT proceed to Phase 2.

   - **OVERLAP / SUPERSEDED under CI / non-interactive (AC4 — fail closed):** re-read the non-interactive state LIVE (do NOT trust in-context state alone — W-NEW-10):
     ```
     ni = Context-Keeper(operation: get_flag, key: "non_interactive")
     ```
     If `ni` is set (or `--non-interactive` was passed) OR **stdin is not a TTY**, an OVERLAP/SUPERSEDED classification **FAILS CLOSED** — UNLESS `--skip-preflight-sync` was passed (which would already have short-circuited in step 1). Abort with a diagnostic: mark the task `failed`, move the job brief to `failed/` if a `job:` was used, and emit a single `SUPERVISOR_RESULT` with:
     - `status: failed`
     - `SUPERVISOR_RESULT.error = "preflight_overlap_detected"` (the dedicated reason — surfaced by the `/autonomous` loop as `AUTONOMOUS_RUN.status_reason: "preflight_overlap_detected"`)
     Do NOT spawn any worker, do NOT proceed to Phase 2.

## Phase 2 PLAN

### `agents/supervisor.md` §"Phase 2: PLAN" — action 1, the Orchestrator spawn

1. Spawn Orchestrator (blocking):
   - Input: `goal: "{task_id}: {title}"` + brief pointer ({brief_path}, "read only the sections you need") + bounded ≤200-char criteria summary — pointers, not pasted brief bodies; exact shape in `skills/async-orchestration/SKILL.md` Part 2 §"Subagent Spawn Contracts"
   - Capture: subtask list with titles, criteria, dependencies, file estimates
   - When `cost_profile=cheap`: include `model: "sonnet"` in the Task call

### `agents/supervisor.md` §"Phase 2: PLAN" — action 4, path selection

Actions 2 (parallelism analysis) and 3 stay in place between actions 1 and 4.

4. Path selection: exactly 1 subtask → Single-Agent Path (skip worktree setup, execute inline, no per-subtask reviewer); `--sequential` with more than 1 subtask → Sequential Path (skip worktree setup, execute inline, no per-subtask reviewer — same deterministic gate as every other threshold, see `agents/orchestrator.md` §"Review Gate Policy"); otherwise → Parallel Path (Execute Manager, worktrees, no per-subtask reviewer)

## Phase 3 EXECUTE — the Supervisor-side routing

### `agents/supervisor.md` §"Parallel Path (multi-subtask)" — the delegation and its result routing

**Delegate to Execute Manager:**

```
result = Task(
  description: "Execute Phase 3: implement subtasks (deterministic outputs_verified gate; no LLM review subtask)",
  prompt: "Execute Manager prompt with:
    - Brief: {brief_path} — read only the sections you need (## Subtask Structure, ## Subtask Contracts, per-subtask criteria, per-subtask `lanes:`). Gitignored main-checkout path: resolves for the Execute Manager (project root), NOT inside worker worktrees. When no brief file exists (`/supervisor task:` no-brief mode), point at `.supervisor/requirements/{slug}-plan.md` (Beads-absent) or `bd show {id}` (Beads) instead, or pass the criteria inline — a documented exception, see docs/POINTER_AUDIT.md.
    - Context digest: {context_digest_path} — MAIN-CHECKOUT ABSOLUTE path (`.supervisor/jobs/context-digests/{basename(brief_path)}`) + ≤200-char summary + "Read only the sections you need" (`skills/async-orchestration/SKILL.md` §"Context digest pointer"). Advisory only — proceed without it if the file does not exist.
    - Subtask index (compact — ids/titles/deps only, no pasted criteria/file lists): [{ids, titles, deps}]
    - Parallelism graph: [{launchable, blocked}]
    - Config: max_workers={N}, project={name}, feature_branch={branch}
    - State file: {path}
    - cost_profile: {default|cheap}",   # always include so Execute Manager can propagate overrides
  # Pointer, not payload (transport-only; see docs/POINTER_AUDIT.md) — the exact shape mirrors
  # skills/async-orchestration/SKILL.md Part 2 §"Subagent Spawn Contracts" (the authority); keep in sync.
  subagent_type: "loomwright:execute-manager",
  model: "sonnet"   # ONLY when cost_profile=cheap; omit entirely when cost_profile=default
)
tool_calls += 1   # single tool call for entire Phase 3
```

**Parse Execute Manager result:**

EXECUTE_RESULT has no top-level `status:` field — the discriminator is
**`subtasks_failed`: escalation ⇔ `subtasks_failed` is non-empty** (see
`docs/RESULT_SCHEMAS.md` §EXECUTE_RESULT).

**Error handling during EXECUTE:**

| Situation | Action |
|-----------|--------|
| EXECUTE_RESULT, `subtasks_failed` empty (completed) | Extract merge data (`merge_order`, worktrees, branches, review decisions), proceed to FINALIZE |
| EXECUTE_RESULT, `subtasks_failed` non-empty + `subtasks_completed` non-empty (partial escalation — the common shape) | FINALIZE the completed subset per `merge_order` (which already lists only completed branches), THEN report the failed subtasks to the user as an escalation in the same run |
| EXECUTE_RESULT, `subtasks_completed` empty (all-failed escalation) | Checkpoint via Context-Keeper, report to human with resume command — nothing to merge |
| EXECUTE_CHECKPOINT (partial) | Checkpoint via Context-Keeper; ask user: merge completed subset now (→ FINALIZE with subset) or continue (→ spawn fresh Execute Manager with remaining subtasks + resume context) |
| EXECUTE_CHECKPOINT (`adjudication_required: true`) | Pause EXECUTE, surface 4-option choice via AskUserQuestion (see "Adjudication Handling" below) |
| Execute Manager crash | Checkpoint, report worktree state, exit with resume |
| Tool budget warning | Checkpoint, exit with resume command |

### `agents/supervisor.md` §"Adjudication Handling" — steps 1–3 and both option sets

The two-raisers table and its lane-collision rule stand before these steps, step 4 (apply the chosen option) and the hard rule after them — all in place.

For **either** kind, the Supervisor MUST:

1. **Pause the EXECUTE phase** — do not spawn further workers, do not advance the affected subtask, do not return to the Execute Manager until a choice is made.
2. **Read `adjudication_kind`, the matching evidence array, and `adjudication_options[]`** from the CHECKPOINT block, per the table above. When `adjudication_kind` is absent, treat it as `requires_gap` (backward compatibility with pre-v15.20.0 checkpoints). Present the options **verbatim as the CHECKPOINT emitted them** — the Execute Manager already selected the correct set for its kind; never substitute the other gate's wording.
3. **Present all four options to the user via `AskUserQuestion`** (preferred). **Cannot ask** (Can't-ask rule): pick NO option — checkpoint state via Context-Keeper, then emit `SUPERVISOR_RESULT.status: failed` with `error: "adjudication_required_non_interactive: {adjudication_kind}"` (same shape as `children_unsettled`), the options and evidence quoted in the summary for a human to resume from. The brief STAYS in `.supervisor/jobs/in-progress/` — a resumable checkpoint, never moved to `failed/` (that move is Option C's terminal re-plan signal). Use the option set matching `adjudication_kind` — wording stays aligned with the `async-orchestration` skill and the Execute Manager's CHECKPOINT format; do not paraphrase either set.

   **`requires_gap`** (Step 2b pre-spawn verification gate):

   - **A: Re-queue producer** — Execute Manager re-spawns the producing subtask with the missing outputs explicitly added to its acceptance criteria.
   - **B: Insert remediation subtask** — Supervisor inserts a new ad-hoc subtask whose `provides:` covers the missing items, then resumes execution with the original consumer blocked on it.
   - **C: Exit to Launch Pad** — Supervisor checkpoints state, marks the job `failed` with reason `inter_subtask_gap`, and exits cleanly. User must rerun `/launch-pad` to fix the brief.
   - **D: Update consumer brief** — Supervisor edits the in-progress brief to remove the failing `requires` entry from the consumer subtask, then re-emits the consumer to the Execute Manager (consumer may proceed without the missing item).

   **`lane_collision`** (lane-collision gate — `colliding_lanes[]` names the path, its declared owner, and the writer):

   - **A: Re-queue writer with the sibling lane excluded** — Execute Manager re-spawns `this_subtask` with `path` explicitly named as off-limits in its acceptance criteria; the lane owner keeps the file.
   - **B: Serialize the pair (add a requires edge)** — Supervisor adds a `requires` edge in the in-progress brief so the two subtasks are no longer mutually unreachable, making the shared path legal sequential sharing. **Re-verify the graph stays acyclic before applying** — a cycle here is worse than the collision. Note this grants *visibility*, not *preservation* (`skills/supervisor-readiness/SKILL.md` §"Lane Declaration Schema").
   - **C: Exit to Launch Pad** — Supervisor checkpoints state, marks the job `failed` with reason **`lane_collision`** (NOT `inter_subtask_gap` — see the table above), and exits cleanly. User must rerun `/launch-pad` to fix the brief's lane declarations.
   - **D: Widen the writer's declared lane** — Supervisor edits the in-progress brief to add `path` to `this_subtask`'s `lanes:`, accepting the overlap as intentional. **Only sound when the two subtasks do not in fact race** — this suppresses the signal without removing the concurrency, so prefer B when in doubt.

## Phase 4 FINALIZE

### `commands/supervisor.md` §"What This Does" — the Phase 4 paragraph

**Phase 4 (FINALIZE):** The merge/commit/PR protocol authority is `skills/async-orchestration/SKILL.md` **Part 2 — Supervisor FINALIZE Protocol** (the pre-merge safety-gate checklist items, sequential merge, worktree cleanup, commit/push/`gh pr create` mechanics, and the step 6.5 PR-base self-verify procedure; the skill is no longer frontmatter-preloaded as of the 4f routing change (v15.19.0) — Phase 2 PLAN now performs the session's genuine first Read of this file, and this Phase 4 Read is a genuine second load acting as a compaction refresh, guarding against Phase 3 EXECUTE's long multi-Task span compacting Phase 2's context out of the window before FINALIZE needs the merge/PR mechanics) — `agents/supervisor.md` "Phase 4: FINALIZE" keeps the short phase stanza with the mandatory gates (pre-merge safety gate, merge-conflict STOP, salvage before remove — v15.67.0, PR-base self-verify; the agent's numbered gate list is authoritative if this parenthetical ever lags it) and entry/exit conditions.

### `agents/supervisor.md` §"Phase 4: FINALIZE" — gate 1's Point 5

Gate 1's own line and gates 2–5 stay in place.

   **Point 5 — children settled (completion authority, v15.80.0):** run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-children-settled.sh" --log .supervisor/logs/{session_id}.jsonl --all` plus one `--expect-id {worker_id}` per `### {worker-id} ({subtask-id})` heading or `agent_id:` / `worker_id:` key under `.supervisor/state.md`'s `## Worker Results` (Context-Keeper's `record_worker_result`; `{worker-id}` = the Task-returned id this run spawned and already joined in step 3b / the Sequential join / Execute Manager's per-worker join) — for EVERY `agent_identity` row this session ever wrote AND every expected id, there must be a matching terminal lifecycle row (`subtask_complete` / `token_ledger` / `agent_lifecycle: failed` / `ended`) for that same `agent_id`, so a worker whose identity row never landed (hook not fired, log dir unresolvable, non-Claude host) still fails this point; see `scripts/check-children-settled.sh`'s header for the exact join (the same script + join the per-subtask gates above use). `status: "no_identity_rows"` PASSES only when the run spawned nothing — no recorded worker id (so no `--expect-id`) and zero `agent_identity` rows (pre-2026-09-07 logs, or a session that never spawned a Task) — and is reported as `children_check: no_identity_rows`, **never** `settled`. `status: "settled"` PASSES and is reported `children_check: settled`. `status: "unsettled"` FAILS this point: `unsettled_agent_ids` names the offending `agent_id`(s) — interactively, `AskUserQuestion` (proceed anyway / investigate / abort); under `--non-interactive` (or CI / stdin-not-a-TTY), **fail CLOSED**: emit `SUPERVISOR_RESULT.status: failed` with `error: "children_unsettled: {unsettled_agent_ids}"` — same shape as the existing `preflight_overlap_detected` fail-closed path (Phase 1.5 above). `status: "unverifiable"` (`jq_missing`) is treated the same as `unsettled` — an unrun check is never a silent pass. **`--skip-children-check`** (escape hatch, mirrors `--skip-preflight-sync`): short-circuits this ONE point as a deliberate choice, recorded via `Context-Keeper(operation: record_decision, phase: FINALIZE, decision: "user_skipped_children_check")`, and the run summary carries `children_check: skipped`. `ended_without_result_ids` from the script's output (agents whose terminal row was a `subtask_complete` with `result_block_present: false`, an `agent_lifecycle: failed` row, or an `ended`-only worker / turn-limit `ended` row) are surfaced alongside the unsettled ids in the same message/log line so an operator can SendMessage either kind of child to resume it (memory `subagents-hit-turn-limit-resume-via-sendmessage`) rather than re-running cold — this point only surfaces the ids, it does not implement the resume. **Publish is blocked until this point passes (finalize-gate, automate-followups/33):** a `PreToolUse[Bash]` fail-CLOSED hook (`scripts/guard-finalize-publish.sh`) denies `git push` / `gh pr create` in this run until `.supervisor/logs/{session_id}.finalize-gate` exists and names the current HEAD. Write it ONLY with `bash "${CLAUDE_PLUGIN_ROOT}/scripts/guard-finalize-publish.sh" write-marker` (append `--skip-children-check` when that flag is set) — the script re-runs this check itself, with the same `## Worker Results` ids as `--expect-id`, and writes the marker only on `settled` / `no_identity_rows` / skip; a `## Worker Results` section with content but no readable id (a table, prose) refuses `worker_results_unparsed` (fail CLOSED — check the workers, then `--skip-children-check`); never hand-write it. Run it before the push and again before any later push (a moved HEAD invalidates the marker).

### `agents/supervisor.md` §"Phase 4: FINALIZE" — the exit conditions

**Exit conditions:**
- PR created against `$BASE_BRANCH` + base self-verified → exit FINALIZE to Phase 4.5 SELF_HEAL. The task is NOT yet marked completed and the job file is NOT yet moved — those actions live in Phase 4.5 SELF_HEAL's completion tail so heal outcomes are captured in the completion record (FINALIZE scope reduction, v11.0.0 — do not perform them here).
- Base mismatch / unrecoverable `gh` failure → `base_mismatch_detected` flag set, fall through to Phase 4.5 cleanup path (`status: failed` emitted there, never here).
- Merge conflict or failed pre-merge validation → STOP as above; exit with resume command.

### `skills/async-orchestration/SKILL.md` Part 2 — step 1, the pre-merge safety gate

Steps 2–6 (commits, merges, salvage + cleanup, commits, release re-fold, push + PR) stay in place.

1. **Pre-merge safety gate** (ALL must pass before any merge):
   ```
   FINALIZE pre-merge checklist:
     1. All WORKER_RESULT status = completed (no failed/partial in merge set)
     2. All Code Reviewer decisions = PASS (no FAIL/NEEDS_HUMAN in merge set) — **N/A at every threshold**: no per-subtask reviewer runs on the Single-Agent Path, the above-threshold parallel path, or the Sequential Path, so this item produces zero reviewer decisions to check. The deterministic `outputs_verified` + tests/lint (plus the worker's own LSP diagnostics) gate and Phase 4.5's integrated review replace it, so treat this item as vacuously satisfied (mirrors Plan Reviewer Criterion 6's vacuous pass)
     3. No orphaned worktrees (all accounted for in EXECUTE_RESULT)
     4. Feature branch exists and is ahead of base
     5. Every spawned child settled (completion authority, v15.80.0) — see below
   If ANY fail → abort merge, log reason, move job to failed/ (if job file used)
   ```

   **Point 5 in full — children settled:** run
   ```bash
   bash scripts/check-children-settled.sh --log .supervisor/logs/{session_id}.jsonl --all \
     --expect-id {worker_id}   # one per `### {worker-id} ({subtask-id})` heading or `agent_id:`/`worker_id:` key under state.md `## Worker Results`
   ```
   (protocol form — the runtime-resolvable form lives in `agents/supervisor.md` §"Phase 4 FINALIZE" Gates Point 5, same convention as `worktree-salvage.sh` above)
   (`{session_id}` = the session_id already recorded in this run's `.supervisor/state.md` `## Session` block — the SAME per-session log `emit-progress-event.sh` / `emit-agent-identity.sh` / `emit-lifecycle.sh` write to.) The script joins every `agent_identity` row this session ever wrote — and every expected id (the Task-returned worker ids Context-Keeper's `record_worker_result` recorded, each already joined by its per-subtask gate), whether or not its identity row landed — against a terminal lifecycle row (`subtask_complete` / `token_ledger` / `agent_lifecycle: failed` / `agent_lifecycle: ended`) for that same `agent_id` — see `scripts/check-children-settled.sh`'s own header for the exact three-way join; it is the ONE implementation, cited here rather than restated, and is the SAME script + join the per-subtask completion gates in `agents/execute-manager.md` §"v12 outputs_verified gate" and `agents/supervisor.md`'s Single-Agent Path step 3b / Sequential Path use (a per-agent-id check there, `--agent-id <id>` instead of `--all`).
   - `status: "no_identity_rows"` — no expected id and zero `agent_identity` rows, i.e. the run spawned nothing (pre-2026-09-07 logs, or a session that never spawned a Task): PASSES, reported `children_check: no_identity_rows` — **never** `settled` (nothing to check is not evidence of settlement).
   - `status: "settled"` — every `agent_identity` row has a matching terminal row: PASSES, reported `children_check: settled`.
   - `status: "unsettled"` — `unsettled_agent_ids[]` names at least one `agent_identity` row or expected id with NO matching terminal row: FAILS this point. Interactively, `AskUserQuestion` (proceed anyway / investigate / abort) — gate `SUP-CHILDREN`: ask it with `header: "SUP-CHILDREN"` and exactly the options `proceed anyway` · `investigate` · `abort` (gate catalog: `docs/LANE_GATES.md`). Under `--non-interactive` / CI / stdin-not-a-TTY, **fail CLOSED**: `SUPERVISOR_RESULT.status: failed` with `error: "children_unsettled: {unsettled_agent_ids}"` — same shape as the Phase 1.5 `preflight_overlap_detected` fail-closed path (`agents/supervisor.md` §"Phase 1.5: PRE-FLIGHT SYNC").
   - `status: "unverifiable"` (`jq_missing`) — treated the same as `unsettled`: an unrun check is never a silent pass.
   - **`--skip-children-check`** (escape hatch, mirrors `--skip-preflight-sync`): short-circuits this ONE point as a deliberate choice, recorded via `Context-Keeper(operation: record_decision, phase: FINALIZE, decision: "user_skipped_children_check")`; the run summary carries `children_check: skipped`.
   - **finalize-gate — publish blocked until this point passes (automate-followups/33):** the push and the PR are refused by mechanism, not by step order. A fail-CLOSED `PreToolUse[Bash]` hook, `scripts/guard-finalize-publish.sh` (no `|| true` on its leaf), denies `git push` / `gh pr create` in a live Supervisor run ("run FINALIZE point 5 first") until `.supervisor/logs/{session_id}.finalize-gate` exists with `head_sha` equal to the current HEAD. The marker is written ONLY by `bash scripts/guard-finalize-publish.sh write-marker [--skip-children-check]`, which runs the `--all` check above itself (with the same `## Worker Results` ids as `--expect-id` — read from `### {worker-id} ({subtask-id})` headings and from `agent_id:` / `worker_id:` keys on a bullet, YAML-continuation or pipe-separated line, never from a table row or prose) and writes `{children_check: "settled"|"no_identity_rows"|"skipped", children_status, head_sha, ts}` only on `settled` / `no_identity_rows` (recorded verbatim, never as `settled`) / the skip — a missing session log (`session_log_missing`), a `## Worker Results` section with content but zero readable ids (`worker_results_unparsed` — fail CLOSED, since reading it as "no workers" would pass a run that spawned workers as `no_identity_rows`; an absent, blank or `(empty)` section is not refused), or any other outcome removes a stale marker and writes nothing; `--skip-children-check` bypasses every one of these, recorded as `skipped`. Never hand-write it. A moved HEAD (e.g. a Phase 4.5 fix commit) invalidates it: re-run `write-marker` before every push, including each Phase 4.5 heal push (`self-heal-advisory` runs it before its `git push`). Arm/allow/deny contract: `docs/HOOKS.md`.
   - `ended_without_result_ids[]` (agents whose terminal row was a `subtask_complete` with `result_block_present: false`, an `agent_lifecycle: failed` row, or — automate-followups/33 — an `agent_lifecycle: ended` row with no result-bearing row beside it for a worker or a turn-limit `reason`) are surfaced alongside `unsettled_agent_ids[]` in the same message/log line so an operator can `SendMessage` either kind of child's `agent_id` to resume it (memory `subagents-hit-turn-limit-resume-via-sendmessage`) instead of re-running the subtask cold — this point only surfaces the ids, it does not implement the resume.
   - `rejected_stop_ids[]` (v15.83.0, diagnostic only) names every child with at least one `subtask_complete` row carrying `rejected: true` — a stop `validate-worker-result.py` rejected (`decision: block`), which is NOT a terminal row. An id that is in BOTH `unsettled_agent_ids[]` and `rejected_stop_ids[]` is a worker that was told to continue and has not yet produced an accepted result (or was forced to stop at the runtime's continuation cap with a malformed one) — surface it in the same line; the verdict itself is unchanged (`status` alone decides). See `docs/RESULT_SCHEMAS.md` §"Completion authority join".

   ```bash
   # Verify all worktree paths exist
   ls -d ../project-{subtask_a} ../project-{subtask_c} ../project-{subtask_b}
   # Verify all branches exist
   git branch --list feature/{subtask_a} feature/{subtask_c} feature/{subtask_b}
   # Verify each worktree has changes (every branch in merge_order)
   git -C ../project-{subtask_a} diff --stat HEAD
   ```
   The has-changes check, and steps 2–3 below, cover the branches in `merge_order` only. A read-only subtask (`WORKER_RESULT.no_changes: true`) is deliberately absent from `merge_order` — it has nothing to commit or merge — but its worktree is still in `worktrees` and is cleaned up in step 4.
   If any verification fails → checkpoint, report missing worktree/branch, exit with resume.

### `skills/async-orchestration/SKILL.md` Part 2 — step 6.5, the PR-base self-verify

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

### `skills/async-orchestration/SKILL.md` Part 2 — step 7 and the FINALIZE scope reduction

7. **Exit FINALIZE.** Task is NOT yet marked completed, and the job file is NOT yet moved. Those actions happen in Phase 4.5 SELF_HEAL's completion tail so that self-heal outcomes are captured in the completion record.

**FINALIZE scope reduction (v11.0.0):** FINALIZE exits after PR creation. Task-completion side-effects (job-file move from `in-progress/` → `done/`, state marked completed via Context-Keeper) have been relocated to Phase 4.5 SELF_HEAL's completion tail. Do not perform them here.
