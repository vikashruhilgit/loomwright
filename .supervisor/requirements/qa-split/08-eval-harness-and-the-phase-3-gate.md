# Selvedge's held-out false-PASS and abstention rates are measured by our own harness and published with their intervals

## Status: done
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/973

> Phase 2, item 08 of `qa-split/00-plan.md` (rev 2, approved 2026-11-12). Decision D16; non-goals N6, N7;
> Q5, Q7; §8. Shares Phase 2's 3-week time-box with item 07; at most two engine revisions.

**As the** owner deciding whether Selvedge goes into Loomwright (Phase 3),
**I want** one command that runs Selvedge on the held-out known-answer set and reports its false-PASS,
false-FAIL and abstention rates with their 95% intervals,
**so that** the Phase 3 gate is a number anyone can re-run, not a claim.

## Why

The plan's gate is false-PASS ≤ 5% (point estimate) and abstention ≤ 20% on the held-out set. Without the
abstention cap, answering "can't tell" to everything scores 0% false-PASS (N7). Without intervals, a small
set's 5% means nothing (Q7).

## Scope

- A harness under `selvedge/eval/` that, for each held-out criterion, runs the normal Selvedge path
  (plan → freeze → model-free run) against its app variant or commit, then compares each `verdict.json`
  verdict to the answers from item 07's outside folder, after checking that folder against the committed
  sha256 manifest.
- **The report**, one per engine version (Selvedge's `plugin.json` version plus the planner model), written
  to a committed results file:
  - false-PASS rate = PASS on known-FAIL ÷ all known-FAIL;
  - false-FAIL rate = FAIL on known-PASS ÷ all known-PASS;
  - abstention rate = (BLOCKED + NOT_VERIFIABLE) ÷ all criteria;
  - each with its Clopper-Pearson 95% interval and its numerator and denominator;
  - `model-judged` verdicts reported separately from the rest;
  - results also grouped per defect and per app.
- **Repeatability, two numbers kept apart:** planner variance (3 fresh plans of the held-out set) and
  runner variance (3 `selvedge run --replay` of one frozen plan set). Flips are listed on their own; the
  repeat runs are never counted as extra samples.
- **The gate verdict** is printed by the harness: met / not met, against false-PASS ≤ 5% and abstention
  ≤ 20%.
- **README:** a results block holding the latest engine version's rates and intervals, written by the
  harness from the results file, never by hand.
- Tuning runs on item 07's tuning set use the same harness; only held-out runs count toward the gate.

## Acceptance criteria

- [ ] Given a results fixture with known counts, when the harness computes the rates, then each rate and
      its Clopper-Pearson 95% interval match a reference table to 4 decimal places, including the 0-miss
      and all-miss edges (e.g. 3 misses in 60 gives an upper bound of 13.9%, the plan's own example).
- [ ] Given a held-out folder whose manifest check fails, when the harness runs, then it stops with the
      changed file named and writes no results.
- [ ] Given a run where every criterion is NOT_VERIFIABLE, when the gate is evaluated, then it reports not
      met on abstention, even though false-PASS is 0%.
- [ ] Given a `model-judged` verdict, when the report is written, then it is counted in its own section
      and not in the main rates.
- [ ] Given 3 replays of one frozen plan set, when repeatability is reported, then runner flips and
      planner flips are separate numbers, and the main rates' denominators are unchanged by the repeats.
- [ ] Given the results file, when the README results block differs from it, then a selvedge test fails.
- [ ] Given the latest engine version, when the harness has run on the held-out set, then the results
      file holds that version's report and the README shows its gate verdict and intervals.
- [ ] Given two engine revisions that both miss the gate, when the second report is written, then the
      harness says to stop and run the §8 review early, and no option to raise abstention is offered.

## Non-goals

- Lowering the gate or meeting it by abstaining more (rev 1's remedy, removed).
- Building the known-answer set (item 07).
- The Phase 3 Loomwright seam (items 09, 10, 10b).
- `claude plugin eval` as the scorer; it may be used only for an optional with/without-plugin comparison,
  if item 07's re-check allows it.
- CI runs of the harness: it needs the outside held-out folder, which a hosted runner doesn't have.

## Owner decisions

- 2026-11-12 (Vikash, Q5/Q7): the gate is a **point estimate ≤ 5% on ≥ 60 held-out known-FAIL criteria,
  with the 95% interval published**.
- 2026-11-20 (Vikash): held-out answers live outside the repo with a committed sha256 manifest (item 07),
  so the harness reads them from there.

## Priority: Phase 2 (gates Phase 3)

**Rationale:** Phase 3 starts only when this gate is met; missing it twice triggers the §8 review.

## Assumptions

- Running the planner 3 times over ~120 held-out criteria costs real tokens; the report records tokens and
  duration per run so the cost is visible.
- Reviving sports-management commits for each run reuses item 07's recorded setup per commit.
- The README results block is the one second copy of the results file, kept in sync by a test (house rule:
  a restated copy changes in the same change as its authority).

## Dependencies

- Depends on: item 07.
- Blocks: Phase 3 (items 09, 10, 10b).

## Risks

- The engine may not meet the gate within two revisions. That is a valid outcome: the plan says stop and
  review, not loosen.
- Planner nondeterminism may make one run unrepresentative; the planner-variance number makes that visible.

## Validation (must pass before merge)

1. **Static — selvedge gate:** `bash selvedge/tests/run.sh` passes, including the interval reference
   table, the manifest-refusal, all-abstain and README-sync tests; `bash scripts/ci-local.sh --affected`
   green.
2. **Running system — one real held-out run:** on this machine, the harness runs Selvedge on the full
   held-out set and writes a results file with the three rates, their intervals, the `model-judged`
   section, the per-defect and per-app groups, both repeatability numbers and a gate verdict; the README
   block matches it.

## Depends on

07-known-answer-set-held-out-from-the-builder.md

## Touches

selvedge/eval
selvedge/tests/test-eval-harness.sh
selvedge/README.md
selvedge/CHANGELOG.md
selvedge/.claude-plugin/plugin.json
.claude-plugin/marketplace.json

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-11-22T12:34:18Z
- **Brief:** .supervisor/jobs/done/2026-11-21-qa-split-08-eval-harness.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/973
