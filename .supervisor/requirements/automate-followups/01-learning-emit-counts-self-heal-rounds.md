# 01 — `learning-emit` counts Phase 4.5 self-heal rounds, not only drain fix cycles

## Status: pending

> **Origin (2026-09-26).** Surfaced by `/automate` run `automate-2026-09-22-013403`, item twin-loop/08
> (PR #267). Phase 4.5 failed round 1 with 4 reproduced HIGH findings, a fix worker healed them, and round 2
> passed. The owned drain then converged in 1 round with 0 fix cycles. The engine-native learning line
> written to `.supervisor/postmortem/results.jsonl` recorded `review_rounds: 0`: the corpus shows the
> most-churned PR of the run as clean.

## Problem
`automate-helpers.sh learning-emit` derives `review_rounds` only from the drain. Its rule is
`effective_review_rounds = fix_cycles>0 → fix_cycles; else ESCALATED → 1; else 0`, and `fix_cycles` is the
owned `/review-pr --until-mergeable` drain's fix→push count. Churn that Phase 4.5 absorbs before the PR
reaches the drain never reaches the corpus. `read-postmortem.sh` feeds that corpus back to future Launch Pad
and Phase 4.5 runs as prior-churn evidence for the same paths, so an area where the review lens repeatedly
finds real bugs looks healthy. This is the same honest-signal failure `automate-loop/SKILL.md` §6
"Learning-emit at end-of-DRAIN" exists to prevent: false-0 lines, just from the other stage.

The data is already in hand. `SUPERVISOR_RESULT` carries `heal_iterations` (a required field) and
`heal_decision` (`docs/RESULT_SCHEMAS.md`, SUPERVISOR_RESULT field list), and the engine writes that block
verbatim to `.supervisor/automate/<run_id>.supervisor-result.md` at §6 step 2. `learning-emit` has no flag
that reads it.

## Goal
One engine-native learning line records BOTH lenses' churn: Phase 4.5 self-heal iterations AND drain fix
cycles. The two stay distinguishable, so trend tooling can tell "caught in self-heal" apart from "caught by
the external bot in the drain".

## Scope
- `loomwright/scripts/automate-helpers.sh` `learning_emit()`:
  - accept an additive `--heal-iterations <n>` (integer; absent or non-integer ⇒ 0, fail-SAFE, never exits
    non-zero);
  - emit it as an additive field;
  - decide, and document in the header comment, whether `review_rounds` becomes `heal_iterations + drain
    rounds` or stays drain-only with a separate field. Recommendation: keep `review_rounds`'s existing meaning
    for back-compat and add `self_heal_rounds`, plus a `categories[]` entry class (e.g. `self_heal_churn`),
    so `read-postmortem.sh` counts it.
- `loomwright/skills/automate-loop/SKILL.md` §6 "Learning-emit at end-of-DRAIN": list `heal_iterations` (from
  the step-2 `SUPERVISOR_RESULT`) among "Inputs the engine already holds" and pass it.
- `loomwright/docs/RESULT_SCHEMAS.md` POSTMORTEM_RESULT §"`source: \"automate_drain\"` variant": document the
  new field(s). Additive, no `schema_version` bump, same precedent as the fields already there.
- `loomwright/scripts/read-postmortem.sh`: only if the new `categories[]` class needs counting. Verify its
  counting rule before changing anything.
- `loomwright/scripts/test-automate-helpers.sh`: new cases (below).

## Non-goals
- No change to the drain's own `fix_cycles` / `REVIEW_HEAL_RESULT`.
- No back-fill of existing corpus lines. They stay append-only, and `curate-postmortem.sh` remains the only
  curator.
- No change to `/pr-postmortem`'s GitHub-derived lines (`source` ≠ `automate_drain`).

## Acceptance criteria
- [ ] `learning-emit … --heal-iterations 2 --fix-cycles 0 --drain-result READY` emits a line whose self-heal
  churn is visible (`self_heal_rounds: 2`, or the chosen equivalent) and which `read-postmortem.sh` returns as a
  prior-churn hit for an overlapping path. Assert the reader's output, not just the ledger line.
- [ ] Omitting `--heal-iterations` produces a line byte-identical (modulo `ts`) to today's output: a
  back-compat pin.
- [ ] `--heal-iterations abc` / `-1` / empty ⇒ treated as 0, exit 0, line still emitted.
- [ ] The idempotency key is unchanged. A re-entry with the same run/item/PR still writes nothing new.
- [ ] Mutation control: dropping the new flag's plumbing makes the first AC fail.
- [ ] The full test loop is green (`loomwright/scripts/test-*.sh` + root `scripts/test-*.sh` +
  `check-vendor-coupling.sh` + `check-doc-currency.sh`).

## Verified premises (re-check before starting)
- **Caveat (found by PR #268's review):** the contract says the engine writes `SUPERVISOR_RESULT`
  verbatim to `<run_id>.supervisor-result.md`, but in run `automate-2026-09-22-013403` that file was a
  main-thread RECONSTRUCTION (item resumed via a worker, no Supervisor block emitted) with no
  `heal_iterations`. Before relying on it, verify that a normal (non-resumed) RUN writes the full block;
  if it does not, this item must also fix that capture, or source the heal count elsewhere.
- **Ledger key drift:** the PR #267 line's `automate_key` item is `twin-loop/08-…md`, while sibling
  lines use the full `.supervisor/requirements/<queue>/<file>.md`; the main thread passed a short
  `--item`. Cosmetic (opaque key), append-only (not rewritten); `--item` must be the full Queue path.
- `automate-helpers.sh` `learning_emit()`'s jq body: the `effective_review_rounds` rule quoted above (read at
  `main @ 91c117e`, 2026-09-26).
- `docs/RESULT_SCHEMAS.md` SUPERVISOR_RESULT: `heal_iterations: integer | null # required`, null when
  `heal_loop_ran=false`. Map null ⇒ 0.
- Evidence: `.supervisor/postmortem/results.jsonl`'s `automate_drain` line for PR #267 shows `review_rounds: 0`,
  while the run file's `## Progress` records Phase 4.5 round 1 FAIL (4 HIGH) → fix → round 2 PASS.
