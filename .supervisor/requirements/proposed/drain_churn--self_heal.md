# Proposed: drain_churn findings at the self_heal stage

evidence-set: drain_churn/self_heal@L44.0,L45.0,L46.0,L47.0,L48.0

- basis: `.supervisor/floor/floor.json` at `generated_at_epoch: 1788692013`
- ledger: `.supervisor/postmortem/results.jsonl`
- ledger mtime_epoch: 1788669347
- pair entries: 34 (emission threshold 10)
- entries in class `drain_churn`: 34
- classified entries in the ledger: 235

## Problem

The ledger holds 34 entries classified `drain_churn` attributed to the `self_heal` flow stage,
at or over the emission threshold of 10. That is a repeating pattern, not an incident.
This file states the pattern; it does not state a fix that has not been verified.

## Goal

Decide what, if anything, changes so that `drain_churn` findings stop recurring at the
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
      evidence set. To dismiss it permanently, paste the `evidence-set: drain_churn/self_heal@L44.0,L45.0,L46.0,L47.0,L48.0`
      line above into a requirement file stamped `## Status: done`.

## Evidence

Every line below is a ledger entry read from `.supervisor/floor/floor.json`
(`generated_at_epoch: 1788692013`). Nothing here is inferred.

- class `drain_churn` - flow_stage `self_heal` - round 2 - line 44 - index 0 - self_heal_miss `hit`
  - evidence: until-mergeable drain, decision=READY, fix_cycles=2
- class `drain_churn` - flow_stage `self_heal` - round 4 - line 45 - index 0 - self_heal_miss `hit`
  - evidence: until-mergeable drain, decision=READY, fix_cycles=4
- class `drain_churn` - flow_stage `self_heal` - round 1 - line 46 - index 0 - self_heal_miss `hit`
  - evidence: until-mergeable drain, decision=READY, fix_cycles=1
- class `drain_churn` - flow_stage `self_heal` - round 5 - line 47 - index 0 - self_heal_miss `hit`
  - evidence: until-mergeable drain, decision=READY, fix_cycles=5
- class `drain_churn` - flow_stage `self_heal` - round 2 - line 48 - index 0 - self_heal_miss `hit`
  - evidence: until-mergeable drain, decision=READY, fix_cycles=2

Cited 5 of the 34 entries in this pair (citation cap 5).
