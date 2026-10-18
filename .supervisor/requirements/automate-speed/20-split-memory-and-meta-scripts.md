# automate-speed/20 — Split setup-memory.sh and meta-sync.sh into sourced modules (move-only)

## Status: pending

## Problem
`loomwright/scripts/setup-memory.sh` is 2,357 lines and `meta-sync.sh` 1,789; their tests are 2,720 and 2,745 lines.
Same maintenance cost as item 19 (owner, 2026-10-15). No token saving by itself.

## Goal
<!-- bump: patch -->
Both scripts become thin entry points sourcing modules from `loomwright/scripts/setup-memory.d/` and
`loomwright/scripts/meta-sync.d/`, with identical behaviour.

## Scope
- Group by concern (meta-sync: managed set, scrub, push/pull, rehearsal hooks; setup-memory: detect, apply, readiness
  verify, migrate). Paths, subcommands, flags, exit codes and output unchanged. Tests split along the same lines.

## Invariants
- meta-sync's scrub rules and managed set are unchanged (a scrub regression publishes home paths to a PUBLIC branch).
- `meta-sync-rehearsal.sh` and `migrate-branch-mode.sh` keep working unchanged.

## Non-goals
- Any behaviour change.

## Owner decisions (from _BACKLOG.md)
- D6: Splits are move-only — no behaviour change, no renamed subcommand, no changed output.

## Acceptance criteria
- Every existing assertion passes unchanged in count; usage/help outputs (where present) byte-identical; no module over ~800 lines.
- `meta-sync.sh status` on this repo prints the same output before and after.

## Validation (must pass before merge)
1. `test-setup-memory.sh`, `test-meta-sync.sh`, `check-vendor-coupling.sh`, `check-test-hermetic.sh`; report
   before/after `<passed>/<total>`.
2. Running system: `meta-sync.sh status --branch <throwaway>` before and after; paste both (identical).

## Depends on
none

## Touches
loomwright/scripts/setup-memory.sh
loomwright/scripts/test-setup-memory.sh
loomwright/scripts/meta-sync.sh
loomwright/scripts/test-meta-sync.sh
loomwright/scripts/setup-memory.d/
loomwright/scripts/meta-sync.d/
changelog.d/as20-split-memory-and-meta-scripts.md

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-18T10:57:16Z
- **Brief:** .supervisor/jobs/done/2026-10-17-split-memory-and-meta-scripts.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/598
