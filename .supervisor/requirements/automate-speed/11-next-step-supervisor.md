# automate-speed/11 — Apply the next-step pattern inside Supervisor (phases 1–4.5)

## Status: pending

## Problem
Supervisor's own protocol is the same mix of control flow written as prose: `agents/supervisor.md` 111KB,
`commands/supervisor.md` 58KB, `skills/self-heal-advisory/SKILL.md` 176KB (the largest prompt in the plugin),
`skills/async-orchestration/SKILL.md` 57KB. Phase 4.5 alone took 85 minutes on PR #533 and every item since
2026-10-12 has used all 3 heal rounds (plan doc §Why now). The phase sequencing, flags, Context-Keeper record calls,
FINALIZE checklist and the heal-loop bookkeeping are deterministic; reviewing and fixing are judgment.

## Goal
<!-- bump: minor -->
A `supervisor-next-step.sh` driver owns Supervisor's deterministic phase sequencing and bookkeeping and hands the model
one instruction at a time (spawn orchestrator / execute-manager / code-reviewer / fix worker; ask; finalize step;
done), using the instruction schema from item 06.

## Scope
- Use `loomwright/docs/loop-inventory/supervisor.md` (item 04) to pick the deterministic rows; write golden fixtures
  for the group's GAP rows first (same method as item 05), then migrate.
- Migrate phase sequencing, phase flags, FINALIZE's checklist steps that are already scripts (pre-merge safety gate,
  PR-base self-verify, children-settled, finalize-gate marker), and the Phase 4.5 loop counter and round bookkeeping.
- Delete the migrated prose; update the inventory homes.
- If the item exceeds 7 subtasks at Launch Pad, split it into Phases 1–4 and Phase 4.5 items under this theme.

## Invariants
- FINALIZE point 5 still runs before anything is published; the fail-CLOSED `guard-finalize-publish.sh` leaf is
  unchanged.
- Phase 4.5 never merges; `READY`/`PASS`/`ESCALATED` stay terminal-stop.
- No per-subtask LLM reviewer is introduced; Phase 4.5 stays the sole LLM gate.

## Non-goals
- Waiting for items 07–08: this item runs alongside them. It builds its own driver script and shares only the
  instruction schema item 06 fixed; a schema change in 07/08 is additive.
- Changing review content, the EXECUTION DIRECTIVE, or pin mutations.
- The prompt diet of what remains (item 15).

## Owner decisions (from _BACKLOG.md)
- D1, D3, D5.

## Acceptance criteria
- Given each Supervisor golden case, when driven through the driver, then `.supervisor/state.md` and the result
  sidecars are byte-identical to the expected ones.
- `test-loop-inventory.sh` passes; supervisor-group GAP count is 0.
- The supervisor read set (`wc -c` of the four files) is recorded before and after in the PR body.
- The CLAUDE.md `gh pr merge --squash` invariant grep resolves to the same surfaces.

## Validation (must pass before merge)
1. The new driver's test, the golden tests, `test-loop-inventory.sh`, the self-heal seam tests,
   `check-token-budget.sh`; report `<passed>/<total>`.
2. Mutation control: let Phase 4.5 exceed max_iterations ⇒ red.
3. Running system: one real item through Supervisor on the driver path; paste the Phase 4.5 iteration lines.

## Depends on
06

## Touches
loomwright/scripts/supervisor-next-step.sh
loomwright/scripts/test-supervisor-next-step.sh
loomwright/scripts/fixtures/supervisor-golden/
loomwright/agents/supervisor.md
loomwright/commands/supervisor.md
loomwright/skills/self-heal-advisory/SKILL.md
loomwright/skills/async-orchestration/SKILL.md
loomwright/docs/loop-inventory/supervisor.md
changelog.d/as11-next-step-supervisor.md

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-18T10:56:22Z
- **Brief:** .supervisor/jobs/done/2026-10-17-next-step-supervisor.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/601
