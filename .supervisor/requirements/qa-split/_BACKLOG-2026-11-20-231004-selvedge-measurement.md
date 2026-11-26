# Measure Selvedge's accuracy (qa-split Phase 2) — plan doc (index document, not an implementable item)

## Status: done (index document — 07 #968, 08 #973; Phase 3 gate met 2026-11-26, #992)

## Why now
Phase 1 of `qa-split/00-plan.md` finished 2026-11-18 (06c, #939), and Phase 4 is done. Phase 3, which wires
Selvedge into Loomwright, may start only when Phase 2's gate holds: held-out false-PASS ≤ 5% and abstention
≤ 20%, with intervals published. Nothing has been measured yet; `selvedge/eval/` does not exist.

## Owner decisions
none recorded

## Order
| Item | Delivers | Depends on | Can run in parallel with |
|---|---|---|---|
| 07 | 200+ known-answer criteria (≥30 real sports-management bugs), split by defect; held-out answers outside the repo with a committed sha256 manifest; `claude plugin eval` limits re-checked | none | none |
| 08 | Our own harness: false-PASS, false-FAIL and abstention rates with Clopper-Pearson intervals, repeatability, and the Phase 3 gate verdict in the README | 07 | none |

## Run
/automate --backlog .supervisor/requirements/qa-split/_BACKLOG-2026-11-20-231004-selvedge-measurement.md
Sequential, safe mode (no `--auto-merge`). Item 07's planted defects must be written by a separate session
started in a folder with no Selvedge source; start that session by hand, not from the item's own run.
Phase 2 is time-boxed to 3 weeks and at most two engine revisions.

## Considered and not queued
- Phase 2b (native probe sprint): research only, runs alongside; not a Selvedge code item.
- Committing the held-out answers (plain or encrypted): rejected 2026-11-20 by the owner in favour of an
  outside folder plus a committed manifest.
- Running the harness in CI: it needs the outside held-out folder, which a hosted runner doesn't have.

## Revisit when
Item 07's real-bug work shows fewer than 30 revivable sports-management bugs, or item 08's second engine
revision misses the gate (then the plan's §8 review runs early).

## Checklist
- [x] .supervisor/requirements/qa-split/07-known-answer-set-held-out-from-the-builder.md
- [x] .supervisor/requirements/qa-split/08-eval-harness-and-the-phase-3-gate.md
