# One writer, derived state: replace six prompt-instructed bookkeeping mechanisms with one hook

## Problem
Progress recording is spread across **six** prompt-instructed mechanisms — Context-Keeper
`set_task`/`update_phase`, the Supervisor's inline best-effort `## Session` write, `set_subtasks`,
Execute Manager's `queue_ck_update`/`flush_ck_batch`, the Session Logging event catalog, and
`checkpoint`/`record_decision`. Every one is an instruction the model must remember while doing the
real work. **Measured miss rate is roughly nine in ten.**

Evidence from this repo's own session logs (2026-07-28):

| Event | Count | Written by |
|---|---|---|
| `token_ledger` | 560 | hook |
| `phase_transition` | 6 | agent |
| `agent_result` | 4 | agent |
| `agent_spawn` / `subtask_complete` | 3 / 3 | agent |

A single session should emit five or six `phase_transition` events on its own; eleven-plus sessions
produced six total. The documented Session Logging catalog in `state-management/SKILL.md` is, in
practice, **not written at all** — the arm-2 eval run's log contained only hook-written
`token_ledger` lines. Hooks are not more important; they simply do not compete with the task for
attention, and instructions lose that competition exactly when the task is hard — which is when the
state matters most.

The cost is paid twice. **Reliability:** on 2026-07-27 all 5 subtasks were merged while `state.md`
read `phase: ACQUIRE` / all `PENDING`, so `--continue` would have re-executed the entire job.
**Tokens:** ~200 lines of bookkeeping prose across `supervisor.md`, `execute-manager.md`,
`context-keeper.md`, and `state-management/SKILL.md`, inside a 258,110-proxy-token prompt inventory
billed on every spawn — and `execute-manager` is already within 341 tokens of its budget ceiling.

`scripts/reconcile-resume-state.sh` (v15.15.0) is a **read-side safety net**: it detects the lie at
resume time. It does not stop the lie being written, and it does not recover the ~200 lines.

## Goal
Exactly ONE progress-recording mechanism, mechanically triggered, with `state.md` demoted from a
thing agents write to a **view derived from an append-only event log**.

## Scope
1. **One hook writes.** Extend the existing `SubagentStop`/worker hook (which already fires and
   validates `WORKER_RESULT`) to append one `subtask_complete` event to
   `.supervisor/logs/{session_id}.jsonl`. Model it on `emit-token-ledger.sh` — same stdin payload,
   same fail-safe always-exit-0 discipline, same proven reliability. Note the real payload shape is
   `last_assistant_message` + `agent_transcript_path`, **not** `result_block`.
2. **`state.md` becomes derived.** A `build-state.sh` projects the append-only log into the current
   `state.md` view on demand (at resume, and wherever the file is read today). An append-only log
   has no write conflicts, which **sidesteps the Context-Keeper sole-writer contract instead of
   fighting it** — no serialization needed because there is one appender.
3. **Delete the six.** Remove `queue_ck_update`/`flush_ck_batch`, `update_phase`, `set_subtasks`,
   the inline best-effort write, and the Session Logging catalog prose from the agent prompts.
   Report before/after proxy-token counts per agent. Deleting the instruction is the point — a
   surviving instruction re-introduces the miss rate.
4. **Prove the reliability delta.** Re-run the event-count measurement above after the change: the
   ratio of mechanically-written to instruction-written progress events should approach 1:0. Do not
   claim the fix works without the counts.
5. **Keep the read-side net.** `reconcile-resume-state.sh` stays — it protects state written by
   older plugin versions and is the backstop if the hook is ever disabled. Two lines of prompt.

## Non-goals
- Not changing what `--continue` *does* once it has trustworthy state.
- Not touching hook-written telemetry (`token_ledger`, webhooks) — it already works; this makes the
  rest work the same way.
- Not a general "move everything to hooks" refactor. Progress recording only; other advisory prose
  is items 03/04/05's scope.

## Acceptance criteria
- Exactly one code path writes progress events, and it is hook-triggered.
- `state.md` is reproducible from the event log alone; deleting it and rebuilding yields the same view.
- A killed run between EXECUTE and FINALIZE leaves state that matches git reality (the 2026-07-27
  incident shape no longer reproduces).
- The ~200 lines of bookkeeping prose are removed; per-agent token deltas reported in the PR.
- Post-change event counts show mechanically-written progress events, not instruction-written ones.
- `reconcile-resume-state.sh` still passes 17/17 and now reports CLEAN on a killed run.

## Outcomes Rubric
- One hook-triggered writer; the other five mechanisms deleted, not merely deprecated
- `state.md` derived from an append-only log and reproducible from it
- Incident shape no longer reproduces under a kill test
- Token reduction measured and reported per agent
- Reliability delta demonstrated by event counts, not asserted

## Provenance
Owner insight, 2026-07-28: *"why do we need this six times — we only need one time and we need to
make sure it works. If not by prompt then in some different way… lots of repeated tasks or prompt,
which increases token usage."* Grounded by the FABLE_PARITY_EVAL arm-2 incident and the event-count
measurement above. Same underlying thesis as twin-remediation items 03 (executable checks over
advisory prose), 04 (delete-over-gate), and 05 (orchestration simplification) — **mechanism over
instruction**. Sibling read-side fix: `.supervisor/requirements/supervisor-resume-state-lies.md`
(shipped as v15.15.0).

## Status: done

Folded into `.supervisor/jobs/in-progress/2026-07-28-one-writer-derived-state.md` (Fix 3 / D5),
executed as a 4-subtask Supervisor job on branch `feature/one-writer-derived-state`:

- Subtask 1 (mechanism substrate — emitter, projector, self-test, hook wiring): commit `36c39de`
- Subtask 2 (delete the prompt-instructed mechanisms across all 9 files): commit `e644d9f`
  (amended after this stamp's Subtask 2 line was first written; `dd41ab5` is the superseded,
  no-longer-reachable pre-amend SHA — do not cite it)
- Subtask 3 (contract + budget surface — this stamp): in progress at authoring time
- Subtask 4 (release surface: version + hook count): pending

**Honest deltas from this doc's stated scope, recorded per this doc's own "prove the reliability
delta" / "do not claim the fix works without the counts" standard:**

- **"Delete the six" → five deleted, one retained.** `record_decision` (bundled here as
  `checkpoint`/`record_decision`) is **retained**, not deleted — it has 42 live call sites, writes
  the Decisions Log (a different concern from progress state), and its removal would strand the
  Phase 1.5 fail-closed gate. See the executing brief's "Scope deviations (a)". A **sixth**
  mechanism this doc never named — the terminal `- status:` flip at
  `skills/self-heal-advisory/SKILL.md:944–946` — was found during execution and deleted too (brief
  deviation (b)); terminal status is now a `session_end`-derived projection with a documented
  residual (see `docs/TELEMETRY.md` §"Progress state" honest-limits list).
- **"~200 lines of bookkeeping prose" → actual measured Subtask 2 diff: net −46 lines (121
  insertions, 167 deletions) across 11 files**, not the ~200 this doc's Problem section estimated.
  The estimate was not re-verified before being carried into the brief's Problem Statement; the
  authoritative number is `git diff --shortstat 36c39de e644d9f` (Subtask 1's commit against the
  committed Subtask 2 commit) — **145 deletions / 42 insertions / net −103 / 9 files was a real
  number at the time it was written, but it was the pre-heal working-tree diffstat, taken before
  two review-heal iterations restored prose (re-adding the `record_worker_result`/`record_review`
  call sites and expanding residual documentation) and swept in two more files; it went stale the
  moment those heal iterations landed and does not describe what actually got committed.**
- **"Reliability delta demonstrated by event counts" is only partly achievable in-PR.** The
  structural fix (one hook-triggered writer, `state.md` derived) shipped and is self-test-verified
  (`scripts/test-progress-state.sh`, 90/90 passing). A **live post-change adherence re-measurement**
  is not producible inside this PR — the installed plugin under
  `~/.claude/plugins/cache/atelier/loomwright/<version>` is a copy, not a symlink, so the edited
  hook does not fire until reinstall. `docs/TELEMETRY.md` §"Progress state" §"Honest limits" records
  the exact operator procedure to run the real count after reinstall.
- **Per-agent token deltas measured, not uniformly a reduction.** `supervisor` and `context-keeper`
  measured proxy-token reductions from the deletion (−419 and −215 respectively); `execute-manager`
  measured a **net increase** (+423) because the same deletion commit bundled an unrelated bug fix
  (recording `record_review` on previously-unrecorded terminal branches) that added more prose than
  the deletion removed. Full numbers and budget adjustments in `docs/prompt-token-budgets.json`.

Do not re-open this requirement to chase the ~200-line or six-mechanism framing above — those were
this doc's own estimates at authoring time, and the corrected numbers now live in the executing
brief and its commits.
