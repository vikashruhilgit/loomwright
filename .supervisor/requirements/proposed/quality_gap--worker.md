# Proposed: quality_gap findings at the worker stage

evidence-set: quality_gap/worker@L2.0,L3.2,L3.5,L5.0,L5.2

- basis: `.supervisor/floor/floor.json` at `generated_at_epoch: 1788692013`
- ledger: `.supervisor/postmortem/results.jsonl`
- ledger mtime_epoch: 1788669347
- pair entries: 30 (emission threshold 10)
- entries in class `quality_gap`: 46
- classified entries in the ledger: 235

## Problem

The ledger holds 30 entries classified `quality_gap` attributed to the `worker` flow stage,
at or over the emission threshold of 10. That is a repeating pattern, not an incident.
This file states the pattern; it does not state a fix that has not been verified.

## Goal

Decide what, if anything, changes so that `quality_gap` findings stop recurring at the
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
      evidence set. To dismiss it permanently, paste the `evidence-set: quality_gap/worker@L2.0,L3.2,L3.5,L5.0,L5.2`
      line above into a requirement file stamped `## Status: done`.

## Evidence

Every line below is a ledger entry read from `.supervisor/floor/floor.json`
(`generated_at_epoch: 1788692013`). Nothing here is inferred.

- class `quality_gap` - flow_stage `worker` - round 1 - line 2 - index 0 - self_heal_miss `hit`
  - evidence: fix(ci): extend contract-parity enum scope to self-heal-advisory skill + round-2 nits
- class `quality_gap` - flow_stage `worker` - round 3 - line 3 - index 2 - self_heal_miss `hit`
  - evidence: language-adapt miss-class signals — checklist examples were JS/TS-only, under-generalized
- class `quality_gap` - flow_stage `worker` - round 6 - line 3 - index 5 - self_heal_miss `hit`
  - evidence: cap class-sweep occurrences + flag final-iteration sweep — missing budget guardrail + ESCALATED transparency
- class `quality_gap` - flow_stage `worker` - round 1 - line 5 - index 0 - self_heal_miss `hit`
  - evidence: commit baseline corpus + harden tool_calls/lookup — fixtures shipped uncommitted; happy path correct but pieces missing/under-hardened
- class `quality_gap` - flow_stage `worker` - round 3 - line 5 - index 2 - self_heal_miss `hit`
  - evidence: address review round 3 — add missing self-test, fully dormant insights heading, date align

Cited 5 of the 30 entries in this pair (citation cap 5).
