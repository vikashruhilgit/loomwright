# Lane timeline shows "Build · EXECUTE" while Supervisor is in FINALIZE / Phase 4.5

## Status: proposed

> Propose-only follow-up from run `automate-2026-10-12-181635` (lanes L1/L2 read "Build · EXECUTE 100m+" while in
> self-heal). Display-only; nothing behaves wrongly. Not enqueued.

## Root cause (read on main 0b65a93)
`scripts/build-state.sh` projects `## Session` phase from only two log events: `subtask_complete` ⇒ `EXECUTE`,
`session_end` ⇒ `LOOP`. Nothing projects `FINALIZE` or `SELF_HEAL`, so after the last subtask the phase stays
`EXECUTE` through PR creation and the whole Phase 4.5 loop. The `lane-status` timeline (`automate-lanes.sh`, the `sstep`
mapping) moves to Heal only when the phase reads `SELF_HEAL`/`LOOP` or a `SELF_HEAL` decision is logged — in this run
that came only after the first fix iteration; a heal that passes on the first review never shows Heal at all.

## Scope
1. Emit a phase event at FINALIZE entry and at Phase 4.5 entry (Supervisor), and project it in `build-state.sh`
   (same evidence-only ordering rule).
2. The timeline reads Build → Heal at Phase 4.5 entry; a test fixture with only a Phase 4.5 entry event shows Heal.
