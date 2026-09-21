# Proposed: quality_gap findings at the self_heal stage

evidence-set: quality_gap/self_heal@L7.3,L9.1,L9.4,L10.1,L15.5

- basis: `.supervisor/floor/floor.json` at `generated_at_epoch: 1788692013`
- ledger: `.supervisor/postmortem/results.jsonl`
- ledger mtime_epoch: 1788669347
- pair entries: 15 (emission threshold 10)
- entries in class `quality_gap`: 46
- classified entries in the ledger: 235

## Problem

The ledger holds 15 entries classified `quality_gap` attributed to the `self_heal` flow stage,
at or over the emission threshold of 10. That is a repeating pattern, not an incident.
This file states the pattern; it does not state a fix that has not been verified.

## Goal

Decide what, if anything, changes so that `quality_gap` findings stop recurring at the
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
      evidence set. To dismiss it permanently, paste the `evidence-set: quality_gap/self_heal@L7.3,L9.1,L9.4,L10.1,L15.5`
      line above into a requirement file stamped `## Status: done`.

## Evidence

Every line below is a ledger entry read from `.supervisor/floor/floor.json`
(`generated_at_epoch: 1788692013`). Nothing here is inferred.

- class `quality_gap` - flow_stage `self_heal` - round 4 - line 7 - index 3 - self_heal_miss `miss`
  - evidence: high-risk classifier omitted roadmap workflow/cross-agent-prompt examples; red_team_advisory unset on --skip-self-heal/resume-thrash early-jump paths
- class `quality_gap` - flow_stage `self_heal` - round 2 - line 9 - index 1 - self_heal_miss `miss`
  - evidence: add coverage for gate fallback paths (no "- branch:" line; state.md absent)
- class `quality_gap` - flow_stage `self_heal` - round 5 - line 9 - index 4 - self_heal_miss `miss`
  - evidence: cover fail-safe branches (non-Bash, jq-absent) + document hook-vs-step5.5 timing
- class `quality_gap` - flow_stage `self_heal` - round 2 - line 10 - index 1 - self_heal_miss `miss`
  - evidence: test(webhook): add config-resolution parity tests + migration caveat
- class `quality_gap` - flow_stage `self_heal` - round 6 - line 15 - index 5 - self_heal_miss `miss`
  - evidence: Bot review 10:32 + Phase 4.5 fresh pass 0c7d20e: insights.md documents plugin_version per-run frontmatter field but build-insights.sh never emitted it and test asserted only the aggregate — doc-vs-code drift + missing branch/test coverage.

Cited 5 of the 15 entries in this pair (citation cap 5).
