# af36-remainder/01 — An unrun must-pass running-system step blocks READY (`validation_unrun`)

## Status: pending

## Split from
`automate-followups/36-s3-engine-fixes.md` Part B item A (originally `parallel-automate/20` Part A), split
2026-10-12 per that file's Re-scope section. Scope and acceptance text below is carried VERBATIM from that
part; only Depends on / Touches / Validation are rewritten for today's tree (main 3e354b5).

## Depends on
none

## Touches
loomwright/scripts/automate-lanes.sh
loomwright/scripts/test-automate-lanes.sh
loomwright/scripts/automate-helpers.sh
loomwright/scripts/automate-helpers.d/escalation.sh
loomwright/scripts/test-automate-helpers.sh
loomwright/scripts/fixtures/automate-helpers-help/
loomwright/scripts/automate-merge-watch.sh
loomwright/skills/automate-loop/per-item-loop.md
loomwright/skills/automate-loop/modes-and-merge-gate.md
loomwright/skills/automate-loop/lanes.md
loomwright/docs/result-schemas/automate-run.md
loomwright/docs/LANE_GATES.md
loomwright/scripts/lane-policy.sh
loomwright/scripts/test-lane-policy.sh
changelog.d/af36-01-validation-unrun-gate.md

## Problem
**An unrun "Running system" check passes as READY.** Wave 2's #402 (pa/16) listed its own three-clone
`ci-local` check under "Not verified". The lane parked READY. The operator ran it and it FAILED: load1 63.6 (fixed
on the PR in `cd5f400`). In wave 1 every PR's "Not verified" list hid something the operator then found. Nothing in
the engine stops a lane from parking READY with a must-pass Validation step not run.

## Goal
A lane (or a sequential `/automate` item) cannot park READY with a must-pass running-system check it did not run.

## Scope (verbatim from af/36 Part B, "Part A — an unrun must-pass running-system step blocks READY (owner policy)")
1. Before the READY / `awaiting_merge` park, the engine compares the item's `## Validation (must pass before merge)`
   "Running system" step(s) with the PR body's evidence. A step listed as "Not verified" / not run, or with no pasted
   output, BLOCKS READY: the item parks `escalated` with a named cause (recommended: `automate-followups/31`'s
   `escalation_cause`, new value `validation_unrun`), naming the step.
2. It stays parked until the step is run (evidence pasted, re-checked) or the owner explicitly waives it; the waiver
   is recorded in `## Progress` with the step and the owner's words. No silent default.
3. Can't-ask branch (CLAUDE.md §"Failure-Mode Invariants": every question gate has a named can't-ask branch):
   non-interactive ⇒ stays parked `escalated`, never waived.
4. Relation to `parallel-automate/05` Scope 15a: that report shows NOT-RUN advisorily; this part makes the same
   condition blocking for the park itself. Keep one reader for both.
5. **Tests:** a fixture PR body listing a running-system step under "Not verified" ⇒ `escalated`
   `validation_unrun`; pasted evidence ⇒ READY as today; a recorded waiver ⇒ READY with the waiver line; an item with
   no running-system step ⇒ unchanged. **Mutation control:** skipping the check must fail the first leg.

## Implementation notes (2026-10-12, read-only check of main 3e354b5 — anchors, not decisions)
- The advisory reader Scope 4 means is `lane-readiness` in `scripts/automate-lanes.sh` (its header: "Five checks,
  each PASS / FAIL / NOT-RUN"; the validation check marks a step NOT-RUN when the PR body's matching section is
  absent or carries no fenced output). Factor that check into ONE reader both the advisory report and the new gate
  call — do not write a second parser.
- `escalation_cause`'s enum and its only writer (`current-escalation`) live in `automate-helpers.d/escalation.sh`;
  the enum is documented in `docs/result-schemas/automate-run.md` and `SKILL.md` §3's template line. `validation_unrun`
  is a new value there, and the merge watcher (`automate-merge-watch.sh`) must not report a `validation_unrun`
  escalation as "now mergeable".
- The waiver is a new owner question gate. Decide whether it is a catalogued lane gate (`lane-policy.sh catalog`,
  mirrored in `docs/LANE_GATES.md`) and state it; it must NOT be an `allowed` (policy-answerable) gate — a policy
  answer would be a silent waiver. Add its row to `docs/ARCHITECTURE_CONTRACTS.md` §"Question-gate inventory" only if
  that inventory lists per-gate rows (check first; if it does, add `loomwright/docs/ARCHITECTURE_CONTRACTS.md` to
  this PR and say so in the body).

## Non-goals
Running any validation step automatically. Changing the home-path scrub. Making `ci-local` faster.

## Acceptance criteria
- Replaying #402's park (its PR body's "Not verified" three-clone step) gives `escalated` `validation_unrun`, not
  READY.
- A READY drain whose PR body pastes every running-system step parks `awaiting_merge` (or `ready_for_release` in a
  lane) exactly as before.
- A recorded owner waiver ⇒ READY, with the waiver line (step + owner's words) in `## Progress`.
- Non-interactive ⇒ stays `escalated`, never waived.
- The Scope 5 mutation control holds.
- `CLAUDE.md`'s bimodal-failure invariant holds: the new check fails CLOSED (an unreadable PR body or Validation
  section is NOT-RUN, never PASS).

## Validation (must pass before merge)
1. Targeted tests for every changed script (`test-automate-lanes.sh`, `test-automate-helpers.sh`,
   `test-lane-policy.sh` if touched) + `scripts/check-doc-currency.sh` + `loomwright/scripts/test-citation-drift.sh`
   (+ token-budget and vendor ratchet after `git add`). The full `scripts/ci-local.sh` runs at `wave-build`
   (owner rule 2026-10-12: lanes do not run the full suite). Report `<passed>/<total>` per suite.
2. Unchanged path: a READY drain whose PR body pastes every running-system step parks as before.
3. Running system: one real lane run (or sequential `/automate` item) that parks on an unrun step, then READY after
   the step is run; paste both `## Current`s. If no such run is possible inside this lane, list it under "Not
   verified" with the reason — the owner runs it at wave close.
4. A failure this must catch: the Scope 5 mutation control.
5. Rollback: `git revert`.

## Evidence
S3 record §"Wave 2 result" (pa/16 failed its own running-system Validation) and §"Wave 1 result" / §"Lessons from
wave 1" (merge checks found real gaps the PR bodies left open).
