# Proposed: execution_bug findings at the worker stage

evidence-set: execution_bug/worker@L5.4,L11.4,L14.3,L15.0,L15.3

- basis: `.supervisor/floor/floor.json` at `generated_at_epoch: 1788692013`
- ledger: `.supervisor/postmortem/results.jsonl`
- ledger mtime_epoch: 1788669347
- pair entries: 25 (emission threshold 10)
- entries in class `execution_bug`: 36
- classified entries in the ledger: 235

## Problem

The ledger holds 25 entries classified `execution_bug` attributed to the `worker` flow stage,
at or over the emission threshold of 10. That is a repeating pattern, not an incident.
This file states the pattern; it does not state a fix that has not been verified.

## Goal

Decide what, if anything, changes so that `execution_bug` findings stop recurring at the
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
      evidence set. To dismiss it permanently, paste the `evidence-set: execution_bug/worker@L5.4,L11.4,L14.3,L15.0,L15.3`
      line above into a requirement file stamped `## Status: done`.

## Evidence

Every line below is a ledger entry read from `.supervisor/floor/floor.json`
(`generated_at_epoch: 1788692013`). Nothing here is inferred.

- class `execution_bug` - flow_stage `worker` - round 5 - line 5 - index 4 - self_heal_miss `hit`
  - evidence: fix corpus README example to use a shipped item id — example keyed a non-existent item, would silently mis-score
- class `execution_bug` - flow_stage `worker` - round 5 - line 11 - index 4 - self_heal_miss `hit`
  - evidence: fix: read-postmortem.sh emits nothing on no-hit (Medium — previously emitted misleading output on no match)
- class `execution_bug` - flow_stage `worker` - round 4 - line 14 - index 3 - self_heal_miss `hit`
  - evidence: fix(pr-postmortem): in-progress CheckRun state fallthrough + banner — genuine state-handling defect
- class `execution_bug` - flow_stage `worker` - round 1 - line 15 - index 0 - self_heal_miss `hit`
  - evidence: Bot review 22:27 + Phase 4.5 report: HIGH integration defect — printed compose restart/repair commands omitted the -p ai-agent-manager-observability project name, forking a second stack with empty volumes (fix 31c3950, class-wide sweep).
- class `execution_bug` - flow_stage `worker` - round 4 - line 15 - index 3 - self_heal_miss `hit`
  - evidence: Bot review 09:51 + triage 6703a57: collector file_storage first-boot permission — distroless UID 10001 vs root-owned named volume → create_directory fails → wait-healthy stalls → smoke test never gates success (fix user:"0:0").

Cited 5 of the 25 entries in this pair (citation cap 5).
