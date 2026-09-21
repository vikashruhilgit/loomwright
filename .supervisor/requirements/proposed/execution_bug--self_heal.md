# Proposed: execution_bug findings at the self_heal stage

evidence-set: execution_bug/self_heal@L7.1,L8.0,L9.0,L15.1,L16.0

- basis: `.supervisor/floor/floor.json` at `generated_at_epoch: 1788692013`
- ledger: `.supervisor/postmortem/results.jsonl`
- ledger mtime_epoch: 1788669347
- pair entries: 11 (emission threshold 10)
- entries in class `execution_bug`: 36
- classified entries in the ledger: 235

## Problem

The ledger holds 11 entries classified `execution_bug` attributed to the `self_heal` flow stage,
at or over the emission threshold of 10. That is a repeating pattern, not an incident.
This file states the pattern; it does not state a fix that has not been verified.

## Goal

Decide what, if anything, changes so that `execution_bug` findings stop recurring at the
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
      evidence set. To dismiss it permanently, paste the `evidence-set: execution_bug/self_heal@L7.1,L8.0,L9.0,L15.1,L16.0`
      line above into a requirement file stamped `## Status: done`.

## Evidence

Every line below is a ledger entry read from `.supervisor/floor/floor.json`
(`generated_at_epoch: 1788692013`). Nothing here is inferred.

- class `execution_bug` - flow_stage `self_heal` - round 2 - line 7 - index 1 - self_heal_miss `miss`
  - evidence: red-team gh pr comment masked with || true then unconditionally recorded red_team_advisory=ran, contradicting the contract (comment failure -> error)
- class `execution_bug` - flow_stage `self_heal` - round 1 - line 8 - index 0 - self_heal_miss `miss`
  - evidence: gate term (ii) read `^## Status:` (H2) but canonical schema writes `- status:` lowercase bullet — load-bearing safety term silently never fired; self-test masked it
- class `execution_bug` - flow_stage `self_heal` - round 1 - line 9 - index 0 - self_heal_miss `miss`
  - evidence: gate (ii) read "## Status:" but canonical schema is "- status:" bullet → gate inert vs real state.md (fix: read canonical bullet)
- class `execution_bug` - flow_stage `self_heal` - round 2 - line 15 - index 1 - self_heal_miss `miss`
  - evidence: Bot review 22:44 finding #1: no-arg /setup multi-select emits 5 modules + Nothing = 6 options, exceeding the AskUserQuestion 4-option cap; author: "this one our self-heal loop missed" (fix 0979c44).
- class `execution_bug` - flow_stage `self_heal` - round 1 - line 16 - index 0 - self_heal_miss `miss`
  - evidence: Round-1 bot review: greedy "s/...<!--.*-->...$/" trailer strip over-matches → reader reconstructs wrong text → content_hash mismatch → a provenance-VALID lesson is silently DROPPED. Fixed by self-heal commit "anchor LESSONS trailer strip".

Cited 5 of the 11 entries in this pair (citation cap 5).
