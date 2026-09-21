# Proposed: convention_mismatch findings at the unknowable stage

evidence-set: convention_mismatch/unknowable@L3.0,L4.0,L4.1,L4.2,L4.4

- basis: `.supervisor/floor/floor.json` at `generated_at_epoch: 1788692013`
- ledger: `.supervisor/postmortem/results.jsonl`
- ledger mtime_epoch: 1788669347
- pair entries: 18 (emission threshold 10)
- entries in class `convention_mismatch`: 109
- classified entries in the ledger: 235

## Problem

**Read this first: `flow_stage: unknowable` means the flow stage could not be attributed** - the ledger record carried no stage, so these entries name a pattern without naming where in the pipeline it arose. This candidate is therefore not directly actionable as written. Closing the attribution gap is the first thing to decide about it.

The ledger holds 18 entries classified `convention_mismatch` attributed to the `unknowable` flow stage,
at or over the emission threshold of 10. That is a repeating pattern, not an incident.
This file states the pattern; it does not state a fix that has not been verified.

## Goal

Decide what, if anything, changes so that `convention_mismatch` findings stop recurring at the
`unknowable` stage - or record why the pattern is acceptable and delete this file.

## Scope

- Re-read the cited entries below at their source lines in the ledger.
- Establish whether they share one cause or several.
- Write the change, or the reason not to, somewhere a future session will read it.

## Acceptance criteria

- [ ] Each cited entry has been read at its source line.
- [ ] The pattern is named as one cause, several, or a mis-classification.
- [ ] Either a change lands, or this candidate is dismissed durably.
      Deleting this file only silences it until the next run recomputes the same
      evidence set. To dismiss it permanently, paste the `evidence-set: convention_mismatch/unknowable@L3.0,L4.0,L4.1,L4.2,L4.4`
      line above into a requirement file stamped `## Status: done`.

## Evidence

Every line below is a ledger entry read from `.supervisor/floor/floor.json`
(`generated_at_epoch: 1788692013`). Nothing here is inferred.

- class `convention_mismatch` - flow_stage `unknowable` - round 1 - line 3 - index 0 - self_heal_miss `hit`
  - evidence: counting artifact: initial feature commit subject contains self-heal, matching the fix-commit regex — not real churn (low confidence)
- class `convention_mismatch` - flow_stage `unknowable` - round 1 - line 4 - index 0 - self_heal_miss `hit`
  - evidence: bot round 1 verified trap-fix coherence across hooks/schemas/prompts; a follow-up push implies residual nits not visible in snippet (low confidence)
- class `convention_mismatch` - flow_stage `unknowable` - round 2 - line 4 - index 1 - self_heal_miss `hit`
  - evidence: round 2 re-verified sweep completeness (skill paths, preload table); push followed (low confidence)
- class `convention_mismatch` - flow_stage `unknowable` - round 3 - line 4 - index 2 - self_heal_miss `hit`
  - evidence: round 3 verified budget-sweep + gate-semantics consistency; push followed (low confidence)
- class `convention_mismatch` - flow_stage `unknowable` - round 5 - line 4 - index 4 - self_heal_miss `hit`
  - evidence: round 5 re-verification (dead refs, enum hits, budget bands); push followed (low confidence)

Cited 5 of the 18 entries in this pair (citation cap 5).
