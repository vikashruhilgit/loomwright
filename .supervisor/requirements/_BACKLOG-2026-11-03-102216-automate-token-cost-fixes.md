# /automate token-cost fixes — plan doc (index document, not an implementable item)

## Status: done (index document — nothing to implement)

## Why now
`--cheap` leaks back to the full-cost profile in two places: a sequential run forgets it on `--resume`, and the
`/review-pr` drain never receives it. The drain is the most spawn-heavy phase per item, at up to 5 rounds × 3 heal
iterations. Separately, summary dismissed-finding drafts are asked about and kept 185 of 194 times, spending a turn per
question for no change. Baseline per item: about 82.7M tokens median (`.supervisor/cost-trials/fix-floor-high.md`,
fix floor MEDIUM, 13 items).

## Owner decisions
none recorded

## Order
| Item | Delivers | Depends on | Can run in parallel with |
|---|---|---|---|
| 2026-11-03-102216 | `--cheap` saved in `## Run Config`, `--no-cheap` off switch | none | none (shares `automate-next-step.sh`) |
| 2026-11-03-102218 | `/review-pr --cheap`, forwarded to both drain spawns | 2026-11-03-102216 | none (shares `automate-next-step.sh`) |
| 2026-11-03-102217 | summary drafts kept automatically, no AUT-SUMMARY ask | none | none (shares `automate-next-step.sh`) |

## Run
/automate --backlog .supervisor/requirements/_BACKLOG-2026-11-03-102216-automate-token-cost-fixes.md
Safe mode, sequential (N = 1): every item edits `loomwright/scripts/automate-next-step.sh` and its tests, so no two
can share a wave. Plan: wave 1: 102216 · wave 2: 102218 (depends on 102216) · wave 3: 102217.
Hotspot: `loomwright/scripts/automate-next-step.sh`, owned by one item at a time by running them in order.

## Considered and not queued
- Scoping the Phase 4.5 executing lens to the claims a fix commit touched: wait for the `fix_floor: HIGH` trial
  readout first, since it targets the same re-rounds.
- Making `fix_floor: HIGH` the default: decide from the trial data, not before.
- Dropping `synchronize` from the CI `claude-review` workflow: the owner keeps per-push re-review on purpose to measure
  review rounds, and it is repo config, not plugin code.
- Recommending `--non-interactive-fallback` to skip dismissed-finding questions: it would lose the 14–22% fix-now
  catches on per-finding drafts.

## Revisit when
The `fix_floor: HIGH` trial (`.supervisor/cost-trials/`) has post-trial results, or a `--cheap` run's ledger still
shows full-model spawns after these items merge.

## Checklist
- [ ] .supervisor/requirements/2026-11-03-102216-cheap-is-honoured-end-to-end-in-automate-runs.md
- [ ] .supervisor/requirements/2026-11-03-102218-review-drain-honours-cheap.md
- [ ] .supervisor/requirements/2026-11-03-102217-stop-asking-about-summary-dismissed-finding-drafts.md
