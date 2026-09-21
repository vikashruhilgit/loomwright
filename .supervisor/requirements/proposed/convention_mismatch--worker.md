# Proposed: convention_mismatch findings at the worker stage

evidence-set: convention_mismatch/worker@L2.1,L3.3,L6.1,L7.0,L14.1

- basis: `.supervisor/floor/floor.json` at `generated_at_epoch: 1788692013`
- ledger: `.supervisor/postmortem/results.jsonl`
- ledger mtime_epoch: 1788669347
- pair entries: 29 (emission threshold 10)
- entries in class `convention_mismatch`: 109
- classified entries in the ledger: 235

## Problem

The ledger holds 29 entries classified `convention_mismatch` attributed to the `worker` flow stage,
at or over the emission threshold of 10. That is a repeating pattern, not an incident.
This file states the pattern; it does not state a fix that has not been verified.

## Goal

Decide what, if anything, changes so that `convention_mismatch` findings stop recurring at the
`worker` stage - or record why the pattern is acceptable and delete this file.

## Scope

- Re-read the cited entries below at their source lines in the ledger.
- Establish whether they share one cause or several.
- Write the change, or the reason not to, somewhere a future session will read it.

## Acceptance criteria

- [ ] Each cited entry has been read at its source line.
- [ ] The pattern is named as one cause, several, or a mis-classification.
- [ ] Either a change lands, or this candidate is dismissed durably.
      Deleting this file only silences it until the next run recomputes the same
      evidence set. To dismiss it permanently, paste the `evidence-set: convention_mismatch/worker@L2.1,L3.3,L6.1,L7.0,L14.1`
      line above into a requirement file stamped `## Status: done`.

## Evidence

Every line below is a ledger entry read from `.supervisor/floor/floor.json`
(`generated_at_epoch: 1788692013`). Nothing here is inferred.

- class `convention_mismatch` - flow_stage `worker` - round 2 - line 2 - index 1 - self_heal_miss `hit`
  - evidence: fix(docs): tighten self-heal-advisory skill description (round-2 review nit 5)
- class `convention_mismatch` - flow_stage `worker` - round 4 - line 3 - index 3 - self_heal_miss `hit`
  - evidence: honesty/accuracy framing touches from review round 3
- class `convention_mismatch` - flow_stage `worker` - round 2 - line 6 - index 1 - self_heal_miss `hit`
  - evidence: docs(memory): tighten knowledge_sources_used schema + capture Phase 2 (round 2 review-fix commit; schema doc needed precision per repo doc-currency conventions)
- class `convention_mismatch` - flow_stage `worker` - round 1 - line 7 - index 0 - self_heal_miss `hit`
  - evidence: CHANGELOG v14.29.0 R4 clause attributed CI prompt vocab to /pr-postmortem buckets instead of the Self-Heal Miss-Class Checklist; caught by Phase 4.5 self-heal
- class `convention_mismatch` - flow_stage `worker` - round 2 - line 14 - index 1 - self_heal_miss `hit`
  - evidence: docs(pr-postmortem): fix CHANGELOG class taxonomy + overstated diff prose — doc accuracy/convention enforcement

Cited 5 of the 29 entries in this pair (citation cap 5).
