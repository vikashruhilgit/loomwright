# automate-speed/11b — Apply the next-step pattern to Supervisor Phase 4.5 (self-heal loop bookkeeping)

## Status: proposed

> Propose-only split of `automate-speed/11` (owner decision 2026-10-17, lane L11 of run `automate-2026-10-15-163325`:
> "Split: Phases 1–4 now"). Item 11 ships `supervisor-next-step.sh` for Supervisor Phases 1–4; this item extends it
> to Phase 4.5. Not enqueued — the owner promotes it.

## Problem
`skills/self-heal-advisory/SKILL.md` (176KB, the largest prompt in the plugin) still states the Phase 4.5 loop
counter, round bookkeeping and completion-tail steps as prose. Phase 4.5 took 85 minutes on PR #533, and every item
since 2026-10-12 has used all 3 heal rounds (automate-speed `_BACKLOG.md` §Why now).

## Goal
<!-- bump: minor -->
`supervisor-next-step.sh` (from item 11) owns the deterministic Phase 4.5 bookkeeping — the iteration counter and
its `--heal-iterations` bound, per-round records, the fix-floor split, the completion-tail steps that are already
scripts — and hands the model one instruction at a time (spawn code-reviewer / fix worker / rubric grader; done).

## Scope
- Golden fixtures first for the supervisor inventory's Phase 4.5 deterministic GAP rows (method of item 05), then
  migrate; re-home each migrated row `script:supervisor-next-step.sh <step>`.
- Delete the migrated prose from `skills/self-heal-advisory/SKILL.md` Part 2 (moved to the driver's `--legacy`
  prose path until golden parity, owner decision D5).

## Invariants
- Phase 4.5 never merges; `READY`/`PASS`/`ESCALATED` stay terminal-stop.
- No per-subtask LLM reviewer is introduced; Phase 4.5 stays the sole LLM gate.
- The completion-tail guard (no `code-reviewer` spawn without `--skip-self-heal` ⇒ failed) is unchanged.

## Acceptance criteria
- Given each Phase 4.5 golden case, when driven through the driver, then `.supervisor/state.md` and the result
  sidecars are byte-identical to the expected ones.
- `test-loop-inventory.sh` passes; every migrated Phase 4.5 row is linked to its golden case; the supervisor GAP
  count before/after is reported with the residual named (rule/story/judgment rows are not faked).
- Mutation control: let Phase 4.5 exceed `max_iterations` ⇒ red.

## Depends on
11

## Touches
loomwright/scripts/supervisor-next-step.sh
loomwright/scripts/test-supervisor-next-step.sh
loomwright/scripts/fixtures/supervisor-golden/
loomwright/skills/self-heal-advisory/SKILL.md
loomwright/docs/loop-inventory/supervisor.md
changelog.d/as11b-next-step-supervisor-phase45.md
