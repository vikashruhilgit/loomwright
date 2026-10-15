# automate-speed/19 — Split automate-lanes.sh and automate-trail.sh into sourced modules (move-only)

## Status: pending

## Problem
`loomwright/scripts/automate-lanes.sh` is 3,692 lines and `automate-trail.sh` 2,189; their tests are 2,981 and 3,362
lines. Every lane, wave and trail change edits the same file, so parallel lanes collide on it and reviews read far more
than the change (owner, 2026-10-15: smaller files make changes and maintenance easier). This is maintenance only:
scripts are not loaded into model context unless read, so it saves no tokens by itself.

## Goal
<!-- bump: patch -->
Each script becomes a thin entry point that sources one module per concern (the repo's existing `<script>.d/` convention, as
`automate-helpers.d/`) from
`loomwright/scripts/automate-lanes.d/` and `loomwright/scripts/automate-trail.d/`, with identical behaviour.

## Scope
- Group functions by concern (e.g. lanes: create/remove, status/feed, wave plan/close, question relay, leaks; trail:
  pr, stage/unstage, meta push). Entry-point paths, subcommand names, flags, exit codes and output stay identical.
- Split each test file along the same lines; every existing assertion is kept.
- Modules resolve their own directory (`${BASH_SOURCE[0]}`), work under bash 3.2 and with `set -u`.

## Invariants
- External consumers keep working unchanged: `loomwright-lanes` (`lane-status` / `lane-feed` / `lane-answer`),
  hooks in `hooks.json`, `capabilities.json`.
- `check-vendor-coupling.sh`, `check-test-hermetic.sh` and `test-lanes-addon.sh` pass.

- Start only after `feature/af39a-sweep` (live on 2026-10-15 with uncommitted edits to `automate-helpers.sh` and
  `automate-lanes.sh`) has merged; rebase onto that main.

## Non-goals
- Any behaviour change, refactor of logic, or output change. Terse output is item 24.

## Owner decisions (from _BACKLOG.md)
- D6: Splits are move-only — no behaviour change, no renamed subcommand, no changed output.

## Acceptance criteria
- Every existing test assertion passes unchanged in count (`<passed>/<total>` equal before and after).
- Each script's usage/help output (where it has one) is byte-identical before and after.
- No module exceeds ~800 lines.

## Validation (must pass before merge)
1. `test-automate-lanes.sh`, `test-automate-trail.sh`, `scripts/test-lanes-addon.sh`, `check-vendor-coupling.sh`,
   `check-test-hermetic.sh`; report before/after `<passed>/<total>`.
2. Running system: `automate-lanes.sh lane-status` on a real run file; output byte-identical to before.

## Depends on
none

## Touches
loomwright/scripts/automate-lanes.sh
loomwright/scripts/test-automate-lanes.sh
loomwright/scripts/automate-trail.sh
loomwright/scripts/test-automate-trail.sh
loomwright/scripts/automate-lanes.d/
loomwright/scripts/automate-trail.d/
changelog.d/as19-split-lanes-and-trail-scripts.md
