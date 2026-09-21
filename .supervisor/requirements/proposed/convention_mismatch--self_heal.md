# Proposed: convention_mismatch findings at the self_heal stage

evidence-set: convention_mismatch/self_heal@L3.1,L3.4,L3.6,L4.3,L4.5

- basis: `.supervisor/floor/floor.json` at `generated_at_epoch: 1788692013`
- ledger: `.supervisor/postmortem/results.jsonl`
- ledger mtime_epoch: 1788669347
- pair entries: 62 (emission threshold 10)
- entries in class `convention_mismatch`: 109
- classified entries in the ledger: 235

## Problem

The ledger holds 62 entries classified `convention_mismatch` attributed to the `self_heal` flow stage,
at or over the emission threshold of 10. That is a repeating pattern, not an incident.
This file states the pattern; it does not state a fix that has not been verified.

## Goal

Decide what, if anything, changes so that `convention_mismatch` findings stop recurring at the
`self_heal` stage - or record why the pattern is acceptable and delete this file.

## Scope

- Re-read the cited entries below at their source lines in the ledger.
- Establish whether they share one cause or several.
- Write the change, or the reason not to, somewhere a future session will read it.

## Acceptance criteria

- [ ] Each cited entry has been read at its source line.
- [ ] The pattern is named as one cause, several, or a mis-classification.
- [ ] Either a change lands, or this candidate is dismissed durably.
      Deleting this file only silences it until the next run recomputes the same
      evidence set. To dismiss it permanently, paste the `evidence-set: convention_mismatch/self_heal@L3.1,L3.4,L3.6,L4.3,L4.5`
      line above into a requirement file stamped `## Status: done`.

## Evidence

Every line below is a ledger entry read from `.supervisor/floor/floor.json`
(`generated_at_epoch: 1788692013`). Nothing here is inferred.

- class `convention_mismatch` - flow_stage `self_heal` - round 2 - line 3 - index 1 - self_heal_miss `miss`
  - evidence: clarify sweep re-review semantics + roadmap currency — doc-currency cross-ref precision (drift class)
- class `convention_mismatch` - flow_stage `self_heal` - round 5 - line 3 - index 4 - self_heal_miss `miss`
  - evidence: single-source the doc-surface/trigger lists — 3 restated copies diverged from authoritative taxonomy (count/cross-ref drift, the PR own checklist class)
- class `convention_mismatch` - flow_stage `self_heal` - round 7 - line 3 - index 6 - self_heal_miss `miss`
  - evidence: doc-surface convention defer to check-doc-currency.sh — enumerated list diverged from its cited authority (cross-ref drift)
- class `convention_mismatch` - flow_stage `self_heal` - round 4 - line 4 - index 3 - self_heal_miss `miss`
  - evidence: stale Save-Findings? heading in red-team example + EXECUTE_RESULT format migration note — doc staleness / cross-surface drift
- class `convention_mismatch` - flow_stage `self_heal` - round 6 - line 4 - index 5 - self_heal_miss `miss`
  - evidence: IMPROVEMENTS_ROADMAP item-16 stale framing + ARCHITECTURE_CONTRACTS timeout-table drift + Launch Pad PASS-on-spawn-3 corner wording — cross-ref drift

Cited 5 of the 62 entries in this pair (citation cap 5).
