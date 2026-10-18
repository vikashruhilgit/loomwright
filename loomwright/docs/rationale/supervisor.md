# Rationale — Supervisor

Stories, history, examples and explanations moved out of the runtime prompts of the `supervisor` loop group (`agents/supervisor.md`, `commands/supervisor.md`; `skills/async-orchestration/SKILL.md` and `skills/self-heal-advisory/SKILL.md` add their own sections as their diets land). Nothing here is read at runtime and nothing here is a rule: every rule stayed in a runtime prompt or moved to the script that enforces it (`docs/loop-inventory/supervisor.md` records each row's home). A `story` row's home is `rationale:docs/rationale/supervisor.md#<slug>`, where `<slug>` is one of the headings below (lowercase, spaces to `-`, other characters dropped). Text moved here verbatim keeps its original wording, including dated incident notes; the runtime prompts no longer carry those dates.

## Supervisor agent — inputs, outputs and shape

### Supervisor model choice

> **Model Warning:** Supervisor orchestrates complex 7-phase workflows with parallel execution, merge conflict detection, post-merge self-heal, and multi-agent coordination. Models below Sonnet may produce suboptimal plans and miss merge conflicts. Use Sonnet or Opus for best results.

### Supervisor inputs

- **Task source:** User description, `task:` parameter, or `.supervisor/state.md` (resume)
- **Job file:** (optional) Pre-computed plan from `.supervisor/jobs/` via Launch Pad (skips Phases 0-2)
- **CLAUDE.md:** Project context and patterns
- **Git state:** Current branch, working tree status
- **Resume data:** (optional) State from previous session
- **Flags:** `--max-workers N`, `--sequential`, `--continue`, `--dry-run`, `job: {path}`, `--skip-self-heal`, `--heal-iterations N` (default 3), `--cheap`, `--base-branch <name>` (default `main`), `--non-interactive`, `--skip-preflight-sync`, `--skip-children-check`, `--no-auto-review`, `--auto-review`, `--no-until-mergeable`, `--check-wait-timeout N`, `--review-check-pattern <glob>`, `--no-red-team`, `--red-team`

The `job:` brief and the flags are the inputs the runtime prompt still names where they are consumed (Phase 0 INIT, the Flags and Options table).

### Supervisor outputs

- **Completed tasks:** With PRs
- **Progress summaries:** Compressed phase outputs
- **Escalation requests:** When NEEDS_HUMAN or max retries reached
- **State file:** Persistent in `.supervisor/` for cross-session resume

The escalation request's shape (the `## ESCALATION REQUIRED` block) stays in the agent prompt's Error Handling section.

### Supervisor architecture diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                     SUPERVISOR (Pure Orchestrator)                │
│  Holds: phase, task_id, branch only (~400 tokens)                │
│  Budget: 50 tool calls                                           │
│  Does: INIT → ACQUIRE → PRE-FLIGHT SYNC → PLAN → [delegate] → FINALIZE → SELF_HEAL → LOOP │
└──────────┬──────────────┬────────────────────────────────────────┘
           │              │
    ┌──────▼──────┐ ┌────▼──────────────────────────────────────┐
    │  Context    │ │  Execute Manager (Phase 3, budget: 60)     │
    │  Keeper     │ │  Owns: poll loop, worker lifecycle          │
    │  (on-demand)│ └────┬──────────────┬──────────────────────┘
    └──────┬──────┘      │              │
           │       ┌─────▼─────────┐ ┌──▼────────────────┐
    ┌──────▼──────┐│  Worker A     │ │  Worker B         │
    │  State File ││  (background) │ │  (background)     │
    │  (.super-   ││  worktree A   │ │  worktree B       │
    │   visor/)   │└────┬──────────┘ └──────┬────────────┘
    └─────────────┘     │                    │
                   ┌────▼──────────┐ ┌──────▼────────────┐
                   │  Gate A       │ │  Gate B           │
                   │  (determ.)    │ │  (determ.)        │
                   └───────────────┘ └───────────────────┘
```

No per-subtask LLM reviewer is spawned at any threshold — Phase 4.5's holistic Code Reviewer is the sole LLM review, run once over the integrated diff after FINALIZE (see `agents/orchestrator.md` §"Review Gate Policy").

### Why inline execution is preferred

Running `/supervisor` inline on the main thread is preferred because a delegated `supervisor-runner` subagent loses the ask tool (every question gate then takes its can't-ask branch) and spends one layer of subagent nesting depth — `docs/ARCHITECTURE_CONTRACTS.md` §"Subagent nesting". The host allows nesting three layers deep by default and a host setting can lower it (the Claude Code sub-agents documentation, re-read 2026-10-12); under a lowered limit the workflow aborts with "Task/Agent tool unavailable". Inline execution never waives the child-agent spawns: the rule and its completion-tail backstop stay in both runtime prompts.

## Preloaded skill routing (4f)

### Why the frontmatter preloads nothing

**Why this section exists:** prior to this change, `loomwright:supervisor-runner`'s frontmatter `skills:` list frontmatter-preloaded all seven of the skills below at spawn time — a fixed cost paid on EVERY invocation, regardless of which phases actually ran. The inline `/supervisor` path (`commands/supervisor.md`) has always preloaded NONE of them and instead Reads each protocol skill on demand at phase entry (`skills/supervisor-config/SKILL.md` at Phase 0, `skills/preflight-sync/SKILL.md` at Phase 1.5, `skills/self-heal-advisory/SKILL.md` at Phase 4.5) — proof, in production, that preloading is not required for correct execution. This section routes `loomwright:supervisor-runner` to the same on-demand pattern and records, skill by skill, what changed and why. The frontmatter `skills:` list is now empty (the key is omitted entirely, matching the zero-preloaded-skill convention already used by `agents/worker.md`, `agents/context-keeper.md`, and `agents/plan-reviewer.md`).

All seven were audited against the actual body of `agents/supervisor.md` (`grep -n` for each skill name, cross-checked against every phase's prose) — not assumed. Findings:

### Async-orchestration routing

1. **`async-orchestration` (~9,889 proxy tokens) — ROUTED, replacement Reads added.** This is 4f's actual double-pay target (per the brief's Verified Premises). Genuinely needed at two distinct points: Phase 2 PLAN (Part 2 §"Subagent Spawn Contracts" — the Orchestrator/Execute Manager/Single-Agent-Worker spawn shapes, consumed through Phase 3 EXECUTE too) and Phase 4 FINALIZE (Part 2 — Supervisor FINALIZE Protocol, the merge/commit/PR mechanics). **Replacement:** a new Read of `skills/async-orchestration/SKILL.md` at Phase 2 PLAN entry (this session's FIRST load of the file — see Phase 2's "Protocol authority" line below), plus the Phase 4 FINALIZE entry already had an explicit Read of the same file. **This directly engages the "refresh guarantee for compressed contexts" rationale that previously justified the Phase 4 Read of a *preloaded* skill:** before this change, the parenthetical at Phase 4 §"Protocol authority (read at phase entry)" read *"This skill IS in the Supervisor's preloaded `skills:` list — the Read at Phase 4 entry is a refresh guarantee for compressed contexts, not the first load."* That specific justification (preloaded → refreshed) no longer applies verbatim, because the skill is no longer preloaded. But the underlying rationale — that Phase 3 EXECUTE can be a long, sprawling span (multiple worker Tasks, worktree operations, EXECUTE_RESULT parsing) that risks compacting Phase 2's earlier context out of the window before Phase 4 needs it — **still holds**, and is **preserved in the same location**: Phase 2's Read is now the genuine first load, and Phase 4's Read is now a genuine second load acting as exactly that same compaction refresh. See Phase 4's updated "Protocol authority" line for the rewritten parenthetical.

### Commit routing

2. **`commit` (~1,134 proxy tokens) — ROUTED, replacement Read added.** Single point of use: Phase 4 FINALIZE's commit-message construction ("per `skills/commit/SKILL.md`, never code-fenced"). Small enough, and single-phase enough, that it does not warrant its own phase-entry stanza — bundled into the same Phase 4 entry Read alongside `async-orchestration` (see Phase 4's "Protocol authority" line).

### State-management routing

3. **`state-management` (~6,885 proxy tokens) — ROUTED, replacement Read added.** Two candidate uses, examined separately:
   - **Phase 0 resume validation gate — NO replacement Read needed here.** `skills/supervisor-config/SKILL.md` (already Read at Phase 0 entry, deliberately not preloaded) embeds the full operational resume-gate procedure verbatim (steps a–d, including the `reconcile-resume-state.sh` ground-truth check) — its citation of `state-management` is attributional ("the authoritative contract"), not a runtime dependency; the actual steps the agent executes are already in the skill it already Reads at Phase 0.
   - **Phase 4.5 completion-tail `session_end` JSONL emission — genuine dependency.** `skills/self-heal-advisory/SKILL.md` Part 1 §"Hard-signal dual emission" (already Read at Phase 4.5 entry) embeds the flat-field correspondence table (`contract_conformance_status`, `benchmark_status`, `ground_truth_status`, etc.) but explicitly defers to `state-management` for "the exact shape" of the base `session_end` line (the `ts`/`event`/`type`/`task_id`/`status`/`plugin_version`/`knowledge_sources_used` wrapper). **Replacement:** a second Read of `skills/state-management/SKILL.md` added at Phase 4.5 entry, alongside the existing `self-heal-advisory` Read (see Phase 4.5's "Protocol authority" line).

### Workflow-management removal

4. **`workflow-management` (~4,267 proxy tokens) — REMOVED, no replacement Read.** Most of the skill's content (7-phase state machine diagram, tool-call budget tables, resume protocol, plugin-hooks description) is a near-duplicate of content already stated directly in `agents/supervisor.md`'s own "7-Phase Workflow", "Context Management", and Quality Checklist sections — cross-checked section by section. One piece is not a duplicate: the skill's Permission Batching subsection (Layer 1/2/3 auto-approve tables, batch-by-phase example, approval-checkpoints table) has no counterpart anywhere in `agents/supervisor.md` — it is dropped without replacement, the same disposition as items 5–7 below. This is a genuine content loss, not a de-duplication; the justification for accepting it is that the inline `/supervisor` path has run in production without this content. The only body citation (the Phase-numbering-convention footnote just above the 7-Phase Workflow heading, "mirrors `skills/workflow-management/SKILL.md`") is decorative attribution: the convention it describes is stated inline at that exact spot, not sourced from the skill at runtime. No phase genuinely needs to Read it.

### Context-summarization removal

5. **`context-summarization` (~1,792 proxy tokens) — REMOVED, no replacement Read.** Zero citations anywhere in `agents/supervisor.md`'s body (verified by grepping the full file for the skill name — the only hit was the frontmatter list itself, now removed). Its per-agent Summary Templates are already duplicated inline in the "Summary Extraction" table (§"Subagent Orchestration" below); its Quick Rules / Compression Rules (<200 tokens, strip code, keep IDs/decisions/paths/counts) are generic conventions the model already applies without a dedicated skill Read.

### Supervisor-readiness removal

6. **`supervisor-readiness` (~6,926 proxy tokens) — REMOVED, no replacement Read.** The single body citation is Phase 3 EXECUTE's "Single-Agent Path" reference to the skill's "Decomposition Threshold" section for path selection (Single-Agent vs. Sequential vs. Parallel) — but that threshold rule is *applied* by the Orchestrator (who decides subtask count), not by the Supervisor, and per the skill's own text, "Orchestrator does not preload this skill and cites this section by path" either. The Supervisor's Phase 2 action 4 merely counts the subtasks the Orchestrator already produced (`== 1` / `--sequential with > 1` / otherwise) — a simple comparison, not a rule requiring the skill's content. The rest of the skill (pre-flight checklist, Supervisor-Ready Brief template, jobs-folder convention) is Launch-Pad-facing, not Supervisor-facing.

### Quality-checklist removal

7. **`quality-checklist` (~3,209 proxy tokens) — REMOVED, no replacement Read.** Zero citations anywhere in `agents/supervisor.md`'s body (verified by grep). The skill's content (pre/post-task checklists, Review Decision Matrix, Repo Consistency Checks, Self-Heal Miss-Class Checklist) is entirely Code-Reviewer-facing: `agents/code-reviewer.md` already frontmatter-preloads `quality-checklist` directly, and `skills/self-heal-advisory/SKILL.md` Part 2 (already Read at Phase 4.5 entry) directs the **Code Reviewer** — not the Supervisor — to additionally apply the skill's "Self-Heal Miss-Class Checklist" during the heal review. The Supervisor itself never consumed this content; the frontmatter copy was pure double-pay on top of the Code Reviewer's own preload.

### Net effect of the routing

**Net effect:** `async-orchestration`, `commit`, and `state-management` move from always-paid frontmatter preload to genuinely-needed, phase-scoped Reads (see the "Protocol authority" lines at Phase 2, Phase 4, and Phase 4.5 below). `workflow-management`, `context-summarization`, `supervisor-readiness`, and `quality-checklist` are removed outright with no replacement — the audit above found no point in `agents/supervisor.md`'s own procedure that actually consumes their content.

### What the budget number claims

**What the budget number does and does NOT claim (read this before quoting the savings).** The re-baseline recorded in `docs/prompt-token-budgets.json` — measured 51814 → ~20.6k — is **spawn-time frontmatter weight**, i.e. what is injected before the agent does anything. It is **not** a session total, and quoting it as one overstates the win. The four skills removed outright ARE a genuine unconditional saving on every run. The three ROUTED skills are a **redistribution, not an elimination**: a session that reaches the phase where a routed skill is needed still pays that skill's tokens, just later and only when actually required. `async-orchestration` (~9,889) is the honest edge case — it is Read at **both** Phase 2 PLAN and Phase 4 FINALIZE, so a session that runs to FINALIZE pays it roughly **twice**, where the old preload paid it once. That double-pay is the deliberate price of the compaction-refresh guarantee (see Phase 4's "Protocol authority" line), and it is the correct trade only because Phase 3 EXECUTE can be long enough to compact Phase 2's context away. The unambiguous wins are: runs that never reach a given phase never pay for it at all, and short/aborted runs pay almost nothing. Benchmark real session usage before claiming a session-level number.

### Phase 4 refresh read

Before the 4f routing change (v15.19.0) `async-orchestration` was preloaded, and the Phase 4 Read was described as "a refresh guarantee for compressed contexts, not the first load". That framing (preloaded → refreshed) no longer applies verbatim, but the rationale holds in the same place: Phase 2 PLAN performs this session's first Read of `skills/async-orchestration/SKILL.md`, and the Phase 4 Read is a genuine second Read acting as the compaction refresh — Phase 3 EXECUTE's long, multi-Task span can push Phase 2's context out of the window before FINALIZE needs the merge/PR mechanics. `skills/commit/SKILL.md` is small (~1,134 proxy tokens) and single-use at Phase 4, so it is Read fresh there with no phase-entry stanza of its own. Likewise the resume gate's operational steps run from `skills/supervisor-config/SKILL.md`'s embedded copy (Read at Phase 0), not from a `state-management` preload, and the Phase 4.5 `state-management` Read exists because self-heal-advisory's §"Hard-signal dual emission" gives the flat-field table but defers to `state-management` for the exact base `session_end` line shape (the `ts`/`event`/`type`/`task_id`/`status`/`plugin_version`/`knowledge_sources_used` wrapper).

## Supervisor agent — why the rules read as they do

### Phase-numbering convention source

The "7-Phase" naming convention mirrors `skills/workflow-management/SKILL.md`; the agent prompt states the convention inline, so that skill is never read for it at runtime.

### Phase 1 base-branch ancestry

The HARD RULE that the feature branch's parent commit is the tip of `$BASE_BRANCH` matters because an unhonored `$BASE_BRANCH` silently breaks stacked iterations: the PR gets the right `--base` name but the wrong ancestry. The idempotent reuse path (reuse only at a byte-identical tip) leaves `--base-branch` and stacked-iteration behaviour unaffected. The "(unchanged)" label the rule used to carry recorded that the branch guard, when it landed, did not alter this rule.

### Phase 1 progress-state window

The branch guard turns a crash in the projector-blind window — between branch creation and the first worker completion, when no derived `state.md` exists yet — into a survivable resume rather than a hard error. The window itself is unchanged and is documented as a residual in `docs/TELEMETRY.md`. The `## Session` block is derived at the worker stop hook by `scripts/emit-progress-event.sh` and projected by `scripts/build-state.sh`; see CLAUDE.md §"Failure-Mode Invariants".

### Single-Agent lane recording

The Single-Agent worker inherits the Sequential-path spawn template, which pastes `lanes:`, so it emits `out_of_lane`. Escalation is vacuous with exactly one subtask — there is no sibling lane to collide with (the Sequential Path's reason is that it is ordered; this path's is that it is singular). The record is still required: the Single-Agent Path became the default after Fix 1, so omitting it would no-op the lane gate on the path most runs take. `not_verified` aggregation into the PR body and the done brief's completion tail came with harness-port/04.

### Single-Agent gate citation

The Single-Agent gate cites `agents/execute-manager.md` §"v12 outputs_verified gate" by anchor, not by line number: edits to `agents/supervisor.md` drifted a line-number reference twice.

### Single-Agent child-settled join

The worker Task call on the Single-Agent and Sequential paths is BLOCKING, so the stop-hook emitters (`emit-progress-event.sh` / `emit-agent-identity.sh`, which write to the same `.supervisor/logs/{session_id}.jsonl`) have normally already written a terminal row (`subtask_complete` / `agent_lifecycle: failed` / `agent_lifecycle: ended`) by the time step 3b runs. `unsettled` is therefore NOT the steady state it is in the Execute Manager's async poll loop; it signals a lagging or failed hook. `rejected_stops > 0` (v15.83.0) means a stop `validate-worker-result.py` rejected with `decision: block`: the blocking Task call only returned because the worker finally produced an accepted result or hit the runtime's continuation cap. There is no next poll iteration to defer to on these paths, which is why the retry is bounded at one. Surfacing `agent_id` for an `ended_without_result` worker follows the lesson recorded in project memory as `subagents-hit-turn-limit-resume-via-sendmessage`.

### Sequential lane reports

The divergent-interface hazard the lane gate exists to catch is two subtasks writing the same file *without being able to see each other*. The Sequential Path executes subtasks strictly serially in one working tree, so a later subtask always observes everything an earlier one wrote — the concurrent-sibling condition can never hold, and the Execute Manager's reachability-based escalation (`agents/execute-manager.md`) has nothing to fire on. What remains is the visibility-vs-preservation case (a later subtask clobbering an earlier one's `provides` symbol), a manual authoring and review discipline documented in `skills/supervisor-readiness/SKILL.md` §"Lane Declaration Schema" and deliberately not an automated gate.

### Sequential token ceiling scope

The per-subtask token-ceiling check (red-team-hardening/06) is implemented on the Sequential Path's own loop. The Parallel Path's poll loop, delegated to the Execute Manager, does not re-check the ledger per worker spawn — an honest limit, not yet extended to that path. With `MAX_TOKENS` unset the check is skipped and behaviour is byte-identical.

### Why skip-self-heal leaves no review

`--skip-self-heal` leaving NO semantic review is a behaviour change from the pre-v15.15.0 fast path (which spawned a per-subtask reviewer on Single-Agent-shaped jobs regardless of the flag) and from the pre-Fix-7 Sequential/Parallel paths (which spawned a per-subtask reviewer unconditionally). Since then no Phase 3 path spawns a per-subtask reviewer (`AGENT_GUIDELINES.md` §"Review Counter-Pressure Rule"), so Phase 4.5's Code Reviewer is the only LLM lens at every threshold.

### Lane collision adjudication

The `requires_gap` options are defined over a producer/consumer `requires` edge that does not exist for a lane collision — there is no "producing subtask", no "missing item", no "failing `requires` entry" to remove. Option C's `inter_subtask_gap` is a control signal, not a label: `/autonomous` EVALUATE Signal 2 keys re-planning on that exact string (`skills/autonomous-loop/SKILL.md`; `commands/autonomous.md`), so emitting it for a lane collision would make another agent re-plan for a contract gap that never happened. A lane collision resolved via Option C ends the loop as a plain `failed` because the brief's lane declarations are an authoring defect that Plan Reviewer Criterion 16 should have caught; silently re-planning around it would hide that. Auto-selecting an option is forbidden because the consequences differ and are irreversible: job failure, brief mutation, plan mutation.

### Completion-tail guard purpose

This guard exists so that if inline main-thread execution "forgot" to spawn `code-reviewer` in Phase 4.5, the run self-reports as failed rather than silently passing. Prose convention alone is insufficient — the guard is load-bearing. (The guard's conditions and actions stay verbatim in `agents/supervisor.md`; only this explanatory sentence moved.)

### Run lock release and reclaim

Releasing the lock on every completion-tail outcome and on every earlier Phase 4 abort means the lock acquired at Phase 0 INIT is held for at most one session and never carried across a crash into a state that blocks the NEXT session's INIT. A genuinely crashed session leaves a lock that `run-lock.sh acquire`'s dead-pid+TTL reclaim (or a human `--force-unlock`) resolves (`docs/ARCHITECTURE_CONTRACTS.md` §"Run lock"). The explicit `--session-id` on acquire is what lets `close-stranded-run.sh` (which matches on `session_id`, not `owner`) release a crashed session's stranded lock; omitting it leaves the lock meta's `session_id` empty.

### Tool call budget estimates

The per-phase table below is an illustrative happy-path estimate, not a binding trigger — the GREEN/YELLOW/RED bands in the agent prompt are the adaptive thresholds, and they fire only while a phase is still running at the threshold; a normal CLEAR run finishes near the 50-call budget without forcing a checkpoint.

| Phase | Estimated Calls | Cumulative |
|-------|----------------|------------|
| Phase 0 (INIT) | ~5 | 5 |
| Phase 1 (ACQUIRE) | ~5 | 10 |
| Phase 1.5 (PRE-FLIGHT SYNC) | ~2-3 (reuses Phase 1's fetch, so incremental cost is small; bounded at ≤6 tool calls per the Phase 1.5 spec) | 13 |
| Phase 2 (PLAN) | ~5 | 18 |
| Phase 3 (Execute Manager spawn) | 1 | 19 |
| Phase 4 (FINALIZE) | ~8 | 27 |
| Phase 4.5 (SELF_HEAL) | ~15-20 (reviewer Task + up to 3 fix tasks + rubric grader + twin/ground-truth scripts + gh calls + Context-Keeper updates; advisory steps degrade gracefully under budget pressure) | 45 |
| Phase 5 (LOOP) | ~3 | 48 |

> The Cumulative column assumes Phase 1.5's **typical** cost (~2-3, reusing Phase 1's `git fetch`); the common CLEAR path is ~2 and the `unverified` / `--skip-preflight-sync` paths cost less. Phase 1.5's **hard cap is ≤6** — if a cold fetch plus several per-PR file scans push it toward that ceiling, the extra calls are governed by the Supervisor's standard tool-budget thresholds (YELLOW at 30, RED at 40), forcing an earlier checkpoint rather than silently overrunning the 50-call budget.
>
> The **Cumulative column is an illustrative happy-path estimate, not a binding trigger** — the GREEN/YELLOW/RED bands below are the adaptive thresholds, and they fire only when a phase is *still running* at the threshold; a normal CLEAR run finishes near the 50-call budget without forcing a checkpoint.
>
> **Cold-fetch caveat:** when Phase 1 did NOT just fetch `$BASE_BRANCH` (so Phase 1.5 cannot reuse it), Phase 1.5 can cost up to its full ≤6 cap, leaving correspondingly less budget for Phases 2–5. A downstream phase that then runs over its estimate will checkpoint (and emit a resume command) rather than overrun — i.e. the gate trades a little downstream headroom for the overlap check, never a silent budget breach.

### Result block field history

`knowledge_sources_used` (v14.28.0) and the System Twin objects (`contract_conformance`, `benchmark_result`, `ground_truth`) follow the `branch_base` / `pr_state` / `preflight_sync` precedent: purely additive, so blocks with or without them validate unchanged and `schema_version` stays `1`. The `brain_context` source tag stays in the open-set vocabulary for past-emission validity but has had no live plugin-side emitter since the graphify-tier retirement (2026-08-17). `build-insights.sh` (ST4) aggregates the `contract_*` / `benchmark_*` flat fields today; `ground_truth_*` is written now and its aggregation is a forward-compatible follow-up (`docs/RESULT_SCHEMAS.md`). The flat `knowledge_sources_used` array is the surface `/insights` reads, the same dual shape `contract_conformance` uses.

## Supervisor — examples

### Agent invocation examples

```
/supervisor                                    # Interactive task selection
/supervisor task: "add user authentication"    # Work on specific task
/supervisor --continue task: user-auth         # Resume specific task from checkpoint
/supervisor job: .supervisor/jobs/pending/2026-02-08-jwt-auth.md   # Execute from Launch Pad brief
```

All flags in the "Flags and Options" table above combine with these shapes; the full user-facing Parameters table lives in `commands/supervisor.md`.

### Command usage examples

```bash
/supervisor                                    # Auto-select next ready task
/supervisor task: BD-XX                        # Work on specific task
/supervisor --max-workers 3                    # Up to 3 parallel workers
/supervisor --sequential                       # Force sequential (no worktrees)
/supervisor --continue                         # Resume from last checkpoint
/supervisor --continue task: BD-XX             # Resume specific task
/supervisor --dry-run                          # Preview workflow without executing
/supervisor job: .supervisor/jobs/pending/2026-02-08-jwt-auth.md   # Execute from Launch Pad brief
/supervisor --skip-self-heal                   # Skip Phase 4.5 review+fix loop (emergency bypass)
/supervisor --heal-iterations 5                # Allow up to 5 fix iterations before escalating (default 3)
/supervisor --cheap                            # Cost-optimized: orchestrator, execute-manager, workers, code-reviewer, fix tasks run on Sonnet
/supervisor --base-branch feature/v14-iter1    # Stack PR on a non-main base (v14 autonomous-loop multi-iter)
/supervisor --non-interactive                  # Fail closed instead of prompting on gh/adjudication gates (set by /autonomous loop)
/supervisor --skip-preflight-sync              # Short-circuit the Phase 1.5 remote-overlap reconciliation gate (escape hatch)
/supervisor --skip-children-check              # Short-circuit Phase 4 FINALIZE's children-settled pre-merge check (escape hatch)
/supervisor                                    # DEFAULT: after PR creation, auto-dispatch the detached until-mergeable review drain (opt-out below)
/supervisor --no-until-mergeable               # Opt the auto-dispatched drain out of --until-mergeable (runner runs plain diff-only /review-pr)
/supervisor --no-auto-review                   # Suppress the post-completion review-drain dispatch entirely (overrides config)
/supervisor --check-wait-timeout 300           # Forward a scoped check-wait bound (seconds) to the until-mergeable drain
/supervisor --review-check-pattern 'claude*'   # Forward a review-producing check selector glob to the until-mergeable drain
/supervisor --red-team                         # Opt in: advisory (non-gating) red-team review of high-risk integrated diffs in Phase 4.5
/supervisor --no-red-team                      # Suppress the advisory red-team review (overrides config)
/supervisor --multi-voter-heal                 # Opt in (default OFF): Phase 4.5 review spawns a second independent red-team-reviewer verification vote + refute check before fixing
/supervisor --no-multi-voter-heal              # Suppress multi-voter heal (overrides config)
/supervisor --voter-provider cursor:gpt-5      # With --multi-voter-heal: cast the verification vote via lens-run.sh (isolated provider CLI) instead of the red-team-reviewer Task
/supervisor --fix-floor HIGH                    # Phase 4.5 fixes only BLOCKING/HIGH this run (default MEDIUM; config .fix_floor)
/supervisor --sdk-runner                       # EXPERIMENTAL (opt-in, default OFF): Phase 3 shells out to the quarantined SDK spike runner; fail-closed if node/runner absent
/supervisor --max-tokens 50000                 # Opt-in token-spend ceiling (red-team-hardening/06): Phase 3 poll loop parks BEFORE spawning another worker/reviewer round once the session's own ledger exceeds N
/supervisor --legacy                           # Run Phases 0–4 from the pre-driver prose (docs/supervisor-legacy-phases.md) instead of scripts/supervisor-next-step.sh
```

### Complete session output

```markdown
## SUPERVISOR v4: Starting Parallel Workflow

## ENVIRONMENT
**Path:** ~/my-project
**CLAUDE.md:** ✓ Found
**Git:** clean
**Branch:** main
**Config:** workers=2, mode=parallel

---

### Phase 1: ACQUIRE
- Task: user-auth
- Title: User authentication with JWT
- Criteria: 5 items
- Branch: feature/user-auth ← CREATED
- Requirements: Clear

… (Phases 1.5–4 example blocks omitted — the per-phase Output pointers above define the shapes; Phase 1.5's block is defined in `skills/preflight-sync/SKILL.md`)

### Phase 4.5: SELF_HEAL
- Heal loop ran: true
- Iterations: 1
- Decision: PASS
- Fixable issues fixed: 2
- Remaining issues: 0
- Resume count: 0
- Task: user-auth [COMPLETED]
- Tool calls: Supervisor 38/50

### Phase 5: LOOP
- Completed: user-auth — User authentication with JWT
- Outcome: completed (heal_decision=PASS, iterations=1, remaining=0)
- Remaining: ask user
- Tool calls: 41/50
- Action: Session complete
```

### Example session

```bash
$ /supervisor

## SUPERVISOR v4: Starting Parallel Workflow

## ENVIRONMENT
**Path:** ~/my-project
**CLAUDE.md:** ✓ Found
**Git:** clean
**Branch:** main
**Config:** workers=2, mode=parallel

---

### Phase 1: ACQUIRE
- Task: BD-15 (high)
- Title: User authentication with JWT
- Criteria: 5 items
- Branch: feature/BD-15-user-auth ← CREATED

### Phase 1.5: PRE-FLIGHT SYNC (abbreviated — full output adds "Open PRs scanned", "Recent commits scanned", "PRs file-inspected" lines; see `skills/preflight-sync/SKILL.md`)
- Canonical version: 14.8.0 | Base tip: a1b2c3d
- Classification: CLEAR (no same-file overlap, no superseding merge)
- Decision: proceed (silent)

### Phase 2: PLAN
- Subtasks: 3 (BD-15a, BD-15b, BD-15c)
- Parallelism: 2 launchable, 1 blocked
- First batch: [BD-15a, BD-15c]

### Phase 3: EXECUTE — BD-15a
- Worker: parallel
- Files: src/auth/jwt.guard.ts
- Gate: outputs_verified + tests/lint PASS ✓

### Phase 3: EXECUTE — BD-15c
- Worker: parallel
- Files: src/auth/cookie.service.ts
- Gate: outputs_verified + tests/lint PASS ✓

### Phase 3: EXECUTE — BD-15b (unblocked)
- Worker: parallel
- Files: src/auth/refresh.controller.ts
- Gate: outputs_verified + tests/lint PASS ✓

### Phase 4: FINALIZE
- Merges: 3 branches → feature/BD-15-user-auth
- Commit: a1b2c3d — feat(auth): implement JWT auth
- PR: #42 — https://github.com/org/repo/pull/42
- Task: BD-15 [MERGED — pending self-heal]

### Phase 4.5: SELF_HEAL
- Heal loop ran: true
- Iterations: 1 (review: FAIL → fix task fixed 2 issues → review: PASS)
- Decision: PASS
- Fixable issues fixed: 2
- Remaining issues: 0
- Task: BD-15 [COMPLETED]

### Phase 5: LOOP
- Outcome: completed (heal_decision=PASS, iterations=1, remaining=0)
- Continuing with BD-18...
```

### Dry run output

Preview without executing:

```bash
$ /supervisor --dry-run

## SUPERVISOR v4: Dry Run Mode

**Would execute:**
Phase 0: INIT — Detect env, configure session
Phase 1: ACQUIRE — Task BD-15, branch feature/BD-15-user-auth
Phase 2: PLAN — Orchestrator decompose, parallelism analysis
Phase 3: EXECUTE — 3 subtasks (2 parallel, 1 sequential)
Phase 4: FINALIZE — Merge, commit, PR
Phase 5: LOOP — Check for next task

**Estimated parallel batches:** 2 (batch 1: BD-15a,BD-15c; batch 2: BD-15b)

**No changes made.** Run `/supervisor` to execute.
```

## /supervisor command — usage notes

### Seven-phase workflow diagram

The Supervisor executes a **7-phase parallel workflow**:

```
┌─────────────────────────────────────────────────────────────────┐
│              SUPERVISOR v4 — PARALLEL WORKFLOW                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Phase 0: INIT (Interactive Configuration)                      │
│     └─> Detect env, ask preferences, create .supervisor/        │
│                                                                 │
│  Phase 1: ACQUIRE (Task Selection + Branch — MANDATORY)         │
│     └─> Select task → Create feature branch (NON-NEGOTIABLE)    │
│                                                                 │
│  Phase 1.5: PRE-FLIGHT SYNC (Remote-State Reconciliation) [NEW] │
│     └─> Fetch + scan recent commits/open PRs → classify         │
│         CLEAR/OVERLAP/SUPERSEDED → silent | ask | fail-closed   │
│                                                                 │
│  Phase 2: PLAN (Decompose + Parallelism Analysis)               │
│     └─> Orchestrator → Subtasks → Parallelism graph             │
│                                                                 │
│  Phase 3: EXECUTE (Delegated to Execute Manager)                │
│     └─> Execute Manager → Worktrees → Workers → Gate            │
│                                                                 │
│  Phase 4: FINALIZE (Merge + Commit + PR)                        │
│     └─> Sequential merge → Commit → Push → PR → exit            │
│                                                                 │
│  Phase 4.5: SELF_HEAL (Integration Review + Fix Loop)  [NEW]    │
│     └─> Holistic Code Reviewer → bounded auto-fix loop →        │
│         completion tail (job → done/, state completed)          │
│                                                                 │
│  Phase 5: LOOP (Next Task or Exit)                              │
│     └─> More tasks? → Phase 1 | No tasks → Done                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Command architecture diagram

```
SUPERVISOR (pure orchestrator, budget: 50 tool calls)
    ├─> Context-Keeper (blocking, state mutations)
    ├─> Product Owner (blocking, if vague requirements)
    ├─> Orchestrator (blocking, task decomposition)
    └─> Execute Manager (blocking, Phase 3, budget: 60 tool calls)
        ├─> Worker A (background, git worktree A) → outputs_verified gate
        └─> Worker B (background, git worktree B) → outputs_verified gate
        (no per-subtask reviewer — Phase 4.5's holistic Code Reviewer is the sole LLM review, run once after FINALIZE)
```

### Parallel execution via git worktree

```
project/                    ← main worktree (feature branch)
project-BD-15a/             ← worktree for worker A
project-BD-15c/             ← worktree for worker C
```

Each parallel worker operates in its own worktree — no file conflicts, no git stash dance. After review passes, subtask branches merge sequentially into the feature branch.

### Plan-first workflow

For complex tasks, use Launch Pad to plan and Supervisor to execute:

```bash
# 1. Prepare the brief (analyzes codebase, decomposes subtasks)
/launch-pad goal: "add JWT authentication"

# 2. Review the brief
# Launch Pad presents the brief for your review
# Choose: Save / Refine / Edit / Discard

# 3. Execute in a fresh session (clean context)
/supervisor job: .supervisor/jobs/pending/2026-02-08-jwt-auth.md
```

**Benefits:**
- **Planning context freed** for execution (Supervisor skips Phases 0-2 — pre-answered by the brief)
- **Plan review** before any code is written
- **File impact analysis** prevents parallelism mistakes
- **Clean context** — fresh session for Supervisor

**When to use Plan-First:**
- Complex tasks (>3 expected subtasks)
- Want to review plan before workers start
- Need accurate file overlap detection
- Working on unfamiliar codebase

### Workflow comparison

| Feature | Manual Workflow | Supervisor v3 | Supervisor v4 |
|---------|-----------------|---------------|---------------|
| Task pickup | Manual | Auto (Beads optional) | Auto (`.supervisor/` only) |
| Branch creation | Manual | **MANDATORY** | **MANDATORY** |
| Agent coordination | Run each manually | Parallel (inline poll) | **Parallel (Execute Manager)** |
| State management | In-context only | Externalized | **Externalized + tool call budget** |
| Cross-session resume | Not possible | `.supervisor/` + Beads | **`.supervisor/` only** |
| Parallel workers | Not possible | Git worktrees | **Git worktrees** |
| Context growth | Unbounded | Unbounded in Phase 3 | **Bounded via Execute Manager** |

### Tips

1. **Start with dry-run:** Use `--dry-run` to preview before executing
2. **Use sequential for debugging:** `--sequential` simplifies troubleshooting
3. **Monitor .supervisor/:** Check `.supervisor/state.md` for current state
4. **Resume after pause:** `/supervisor --continue` picks up exactly where it left off
5. **Limit workers:** Use `--max-workers 1` for resource-constrained environments
6. **Plan first for complex tasks:** Use `/launch-pad` to prepare a brief, then `/supervisor job:` for clean-context execution

### Related commands

| Command | Purpose |
|---------|---------|
| `/launch-pad` | Prepare brief for clean-context execution |
| `/orchestrator` | Plan tasks without executing |
| `/code-reviewer` | Review specific files |
| `/commit` | Create commits manually |
| `/product-owner` | Refine requirements |
| `/red-team-reviewer` | Adversarial audit |

### Troubleshooting

**"No tasks provided"**
- Provide task description directly with `task:` parameter
- Or run interactively and describe the task when prompted

**"Dirty working tree"**
- Commit or stash changes before running Supervisor
- Supervisor will warn and ask for approval

**"Context limit reached"**
- Supervisor exits with a resume command; `.supervisor/state.md` reflects whatever the derivation mechanism (`scripts/build-state.sh`) last projected as of the most recent worker completion or session end — not a fresh write at this exact moment
- Resume with: `/supervisor --continue task: BD-XX`

**"Resume aborted with `resume_state_invalid`"**
- `--continue` loaded a state file (scratchpad or `.supervisor/state.md`) that failed the fail-closed **resume validation gate**: missing `## Session` block, `phase`/`status` outside the closed enums (`phase`: `INIT | ACQUIRE | PLAN | EXECUTE | FINALIZE | SELF_HEAL | LOOP`; `status`: `running | paused | completed | completed_with_escalation | failed`), or an asserted `branch:` that no longer exists locally (`git rev-parse --verify` failed). Authoritative contract: `skills/state-management/SKILL.md` §"Resume validation gate"
- Recover: inspect `.supervisor/state.md` and fix the offending field, or delete the file and start fresh without `--continue`. There is deliberately no override flag — deleting the bad state file IS the escape hatch
- The Supervisor never silently falls back to a fresh start on an invalid file (that would mask corruption); a *missing* state file still starts fresh normally

**"Resume aborted with `resume_state_stale`"**
- Distinct from `resume_state_invalid`, and the recovery is the **opposite**. The file is intact and schema-valid — it is simply **behind reality**: subtasks it lists as pending are already committed on the branch. Resuming would re-execute merged work. Detected by `scripts/reconcile-resume-state.sh`, which reconciles the `## Subtasks` rows against `subtask:` / `merge:` commits reachable from the asserted branch
- Recover: **do NOT delete the state file** (that is the `invalid` remedy and would discard a usable session). The refusal prints one `stale_subtask:` line per divergence plus the branch carrying the real work — correct those rows' `Status` to match, then `--continue` again. Or, if the run is not worth resuming, delete it deliberately and start fresh
- `VERDICT: UNKNOWN` (ground truth unreadable — no git, unresolvable branch) also refuses, by design: this gate fails closed
- Real incident it exists to prevent (2026-07-27): all 5 subtasks merged while `state.md` read `phase: ACQUIRE` / all `PENDING`. Schema-valid, therefore invisible to the checks above

**"NEEDS_HUMAN escalation"**
- Read the escalation message for context
- Fix the issue manually
- Resume with: `/supervisor --continue`

**"Merge conflict in FINALIZE"**
- Supervisor reports conflicting files
- Resolve manually in the feature branch
- Resume with: `/supervisor --continue`

**"Worktree creation failed"**
- Supervisor automatically falls back to sequential mode
- Check disk space and git worktree state: `git worktree list`

### See also

- `agents/supervisor.md` - Full agent prompt (7-phase model; Phase 4.5 stanza + completion-tail guard)
- `skills/self-heal-advisory/SKILL.md` - Phase 4.5 protocol authority (Part 1 advisory machinery + Part 2 loop protocol; Read at Phase 4.5 entry)
- `agents/execute-manager.md` - Phase 3 execution agent
- `agents/context-keeper.md` - State management agent
- `agents/worker.md` - Implementation worker agent
- `skills/async-orchestration/SKILL.md` - Parallel dispatch patterns
- `skills/state-management/SKILL.md` - State file schema
- `skills/workflow-management/SKILL.md` - Workflow patterns
- `skills/supervisor-readiness/SKILL.md` - Pre-flight checklist and brief template
- `skills/context-summarization/SKILL.md` - Output compression

### Dispatch observability false negative

The marker-reconcile rule (resolve `until_mergeable_dispatched` from the on-disk per-PR dispatch marker, never from "did I dispatch") exists because a prior inline run misreported "not dispatched" while the drain was live (PID alive, marker written): the `PostToolUse[Bash]` hook backstop had dispatched it out-of-band. The awk marker-check snippet's agent-side copy moved from `agents/supervisor.md` to `skills/self-heal-advisory/SKILL.md` completion-tail step 5.5; the commands-side copy stays because the inline path loads `commands/supervisor.md`.

### Drain timing and the retired workaround

The detached drain runs in its own dispatcher-created sibling worktree (detached HEAD at the PR head SHA — `scripts/dispatch-pr-review.sh`), with a separate working directory and index, so it can no longer check out, stage or commit in the self-heal's working tree. Writing `.supervisor/config.json {"auto_review": false}` was once the workaround for that collision; it is retired, and the flag remains only a general opt-out. The timing note moved into `skills/self-heal-advisory/SKILL.md` completion-tail step 5.5 from `agents/supervisor.md`.

### Inline-path state.json write

The `/autonomous`-only `state.json` ACQUIRE write (Fix B producer) is a cross-layer write — the inlined Supervisor updating the autonomous loop's own `state.json` — and is the placement-risk site, which is why the directive lives in the loaded `commands/supervisor.md` and not only in `agents/supervisor.md`. Before it, `current_branch` was `null`/absent in every `state.json`; the branch reached `iterations[-1].branch` only at EVALUATE, which is post-PR and too late for the consumer hook.

### Resume state stale incident

`resume_state_stale` exists because of a real incident (2026-07-27): all 5 subtasks had merged while `state.md` read `phase: ACQUIRE` with every subtask `PENDING` — schema-valid, and therefore invisible to the resume validation gate's schema checks. `scripts/reconcile-resume-state.sh` reconciles the `## Subtasks` rows against `subtask:` / `merge:` commits reachable from the asserted branch. The two refusals take opposite remedies on purpose: an invalid file is fixed or deleted, a stale file must not be deleted (it is a usable session that only needs its rows corrected).

## Async orchestration — why the rules read as they do

Stories, examples and explanations moved out of `skills/async-orchestration/SKILL.md` (automate-speed/15, subtask 2). The rules they explain stay in `SKILL.md` or `skills/async-orchestration/finalize.md`.

### FINALIZE split to finalize.md

`SKILL.md` is read twice per run without FINALIZE: by Phase 2 PLAN (for §"Subagent Spawn Contracts") and by every Execute Manager spawn (it is that agent's one preloaded skill). Before this split both reads paid for the Phase 4 FINALIZE procedure and the PR Body Template, which only the Supervisor at Phase 4 executes. They now live in `finalize.md`, read only at Phase 4 entry. `SKILL.md` keeps its `# Part 2` heading and a `## Phase 4 FINALIZE procedure (steps 1–7)` stub naming `finalize.md`, so the next-step driver's instruction strings (`skills/async-orchestration/SKILL.md Part 2 steps 2-5.5`, `Part 2 PR Body Template`) and the golden fixtures pinned on them stay valid without editing the driver. The Phase 4 Read no longer re-reads `SKILL.md`: its old purpose, a compaction refresh of the Part 2 FINALIZE procedure after a long Phase 3, is served by reading `finalize.md` itself.

### Async orchestration Part 2 provenance

> **Provenance & authority:** the three sections below were moved VERBATIM from
> `agents/supervisor.md` (slice D of the supervisor prompt refactor, following the
> `self-heal-advisory` Part 2 precedent). Zero behavior change: every gate, command
> shape, bound, and grep-stable string keeps identical semantics. `agents/supervisor.md`
> keeps the short Phase 4 stanza (entry/exit conditions, the mandatory 4-point pre-merge
> safety gate, the merge-conflict STOP rule, the salvage-before-remove gate (v15.67.0), the
> PR-base self-verify requirement, and the phase Output block), the "Agents Spawned by Supervisor" table + Summary Extraction
> rules, and the worktree-ownership invariant (branches + worktrees are created by the
> Execute Manager in Phase 3 Step 2a, never in Phase 2) — and points here for the
> procedures. The Supervisor Reads this file at Phase 4 FINALIZE entry. As of the 4f
> routing change (v15.19.0) this skill is no longer in the Supervisor's preloaded
> `skills:` list (the list is now empty) — Phase 2 PLAN performs the session's genuine
> first Read of this file, and the Phase 4 FINALIZE Read is a second, refresh Read, not
> the first load. Step numbering (1–7 incl. 6.5) is preserved verbatim,
> so cross-file references to e.g. "Phase 4 self-verify (step 6.5)" remain valid — they
> now resolve here.

The "three sections" were the FINALIZE procedure, the Subagent Spawn Contracts and the worktree-lifecycle phase sequence. After automate-speed/15 the FINALIZE procedure is in `finalize.md`, the spawn contracts stay in `SKILL.md` Part 2, and the phase sequence collapsed into `SKILL.md` §"Git Worktree Lifecycle" (Phase 3) plus `finalize.md` steps 2–4 (Phase 4), which restated it.

### Async orchestration examples

File overlap, as the Orchestrator's file lists show it:

```
subtask_a.files = [src/auth/guard.ts, src/auth/guard.spec.ts]
subtask_b.files = [src/auth/refresh.ts, src/auth/refresh.spec.ts]
subtask_c.files = [src/auth/guard.ts, src/auth/module.ts]

→ A and B: no overlap → can run in parallel
→ A and C: overlap (guard.ts) → must serialize
→ B and C: no overlap → can run in parallel
```

Worktree layout under the `{project-dir}-{subtask-id}` naming convention:

```
my-project/                    ← main worktree (feature/BD-XX-desc)
my-project-BD-XXa/             ← worktree for subtask a
my-project-BD-XXc/             ← worktree for subtask c
```

The Supervisor state tracks, per dispatched worker: `worker_id`, `subtask_id`, `output_file`, `worktree`, `status`. The skill used to show an illustrative `WORKER_RESULT` block (an older field set with `notes:`); the schema is `docs/RESULT_SCHEMAS.md` §WORKER_RESULT, so the example was dropped rather than kept as a second, drifting copy.

### Execute context budget

Execute Manager holds (isolated from Supervisor):

| Data | Tokens |
|------|--------|
| Config (max_workers, mode) | ~50 |
| Active workers (id, subtask, worktree_path) | ~100 per worker |
| Parallelism state (launchable, blocked lists) | ~100 |
| **Total (2 workers, no reviewer — none is spawned above threshold or on the Sequential Path)** | **~350 tokens** |

Supervisor holds during Phase 3:

| Data | Tokens |
|------|--------|
| Single Task call to Execute Manager | ~50 |
| **Total** | **~50 tokens** |

Phase 3 poll loop context stays in Execute Manager, not Supervisor. Everything else lives in the state file, managed by Context-Keeper.

### Why the pre-spawn gate exists

The producer branch claimed to provide an item — this gate verifies the claim against disk. Without it, a worker would be spawned into a worktree that doesn't actually contain the symbols/types/files it expects, and would either fabricate them, fail mid-implementation, or silently drift. The gate fails fast at the boundary between producer and consumer. A failed check means the producer's `provides` declaration was a lie or the producer drifted from its acceptance criteria — neither is something the Execute Manager can resolve unilaterally, hence the adjudication checkpoint. The four adjudication options' full cost notes: A costs one extra worker run; B costs an extra subtask and dependency edge, and downstream telemetry/audit becomes harder to interpret; C costs a full restart but catches structural problems before deeper damage; D's silent scope reduction can break callers of the consumer downstream, because the consumer no longer integrates the producer's output.

### Why the worker contract pastes provides and lanes

`provides:` is REQUIRED input — the worker's Step 5.5 outputs-verification re-reads it from the spawn brief; omitting it silently no-ops the v12 outputs gate. `lanes:` is REQUIRED input for the SAME reason — the worker's lane-check step re-reads `lanes:` from the spawn brief to populate `out_of_lane`; omitting it silently no-ops the lane gate. This paste MUST match the parallel path (`agents/execute-manager.md` §Task template), which already marks it REQUIRED — and it matters MOST here, because the Single-Agent path is the DEFAULT shape post-Fix-1, so a gap on this template no-ops the lane gate on the path most runs actually take. Both are deliberate paste exceptions (`docs/POINTER_AUDIT.md`): the `provides:` YAML is small, and a pointer would make the gate depend on a file read the worker may skip. The acceptance criteria travel as pointer + bounded summary instead.

House rules are injected VERBATIM because a paraphrase drops rules (#431). The reader always exits 0 and emits EMPTY on no valid rule — never a "no rules" sentinel — so empty output means inject nothing. The injection is advisory and fail-safe: it never fails a worker, never gates a PR, is never a `SUPERVISOR_RESULT` field and never bumps `schema_version`; a rule's `check` is surfaced to the worker as DATA, never executed.

`subtask_ordinal` was added by harness-port/01-worker-rules; absent the shared-local-services rule's `<PORT_ENV>` mechanism the field is inert by design, per that requirement's Non-goals. The context digest pointer was added in v15.20.0 (D6); a pre-v15.20.0 brief, or a job whose Launch Pad Phase 5 has not run yet, has no digest file, which is why its absence never blocks a spawn.

## Phase 4 FINALIZE — why the steps read as they do

Explanations moved out of the FINALIZE procedure (now `skills/async-orchestration/finalize.md`).

### Salvage before remove

Salvage before remove arrived in v15.67.0. The salvage line runs as its own statement, never joined to the remove by `&&`, because an absent script exits 127 and would otherwise skip the remove. The removals themselves are unchanged by it.

### Worktree cleanup audit

Cleanup is verifiable (v15.66.0): the worktree observer hook records both the literal `../{project}-{subtask_id}` add and the remove (a path token left unexpanded — `$(basename $(pwd))` — is recovered through the branch argument only when the resulting worktree's path ends with the literal suffix after the `$(…)`, so a failed add pairs with a foreign worktree only when that worktree's path ends with the same literal suffix — an advisory-only phantom row, never a removal; it is gated on `.supervisor/` existing, which it always does here), and `bash scripts/worktree-audit.sh report` (plugin-relative, read-only) lists any sibling recorded as created that git still shows.

### Release re-fold placement

The same re-fold line runs before every Phase 4.5 heal push and every `/review-pr` fix push, so no later commit can leave a fragment unfolded (in this plugin's own repo, CI's `scripts/check-version-bump.sh` re-checks the content on every PR to `main`).

### Stacked base branches

The autonomous-loop multi-iteration mode passes a sibling feature branch (e.g., `feature/v14-iter1`) as `--base-branch`, so iteration N+1 stacks on iteration N's PR. The PR-base self-verify (step 6.5) arrived in v14.0.0 (AC-7 + AC-14).

### FINALIZE scope reduction

FINALIZE exits without marking the task completed or moving the job file (v11.0.0): Phase 4.5 SELF_HEAL's completion tail does both, so self-heal outcomes reach the completion record.

### PR body evidence and not-verified sections

The `## Evidence` section (#511) only points at files: a brief criterion's evidence lives in the committed file, which the review reads in the diff and a fix task can heal, never in the PR body, which FINALIZE writes once before Phase 4.5 and nothing edits afterwards (Plan Reviewer Criterion 20). A file a Phase 4.5 fix adds later is in the diff but not listed. When every worker's `not_verified` list is empty, the PR body is byte-identical to the template with the `## Not verified` block removed.
