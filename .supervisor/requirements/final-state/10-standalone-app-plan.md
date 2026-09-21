# 10 — Standalone application plan (D2) — BLOCKED on item 05

**Planning-only. /automate should skip until item 05's second arm-3 row exists.** Deliverable is a
design doc, not code.

## Problem
The end state (D2) is a standalone application wrapped around the SDK runner, carrying the
plugin's judgment layers (Twin, lessons, rules, two review lenses). Today the runner is a
quarantined spike and the judgment layers are welded to Claude Code plugin surfaces. The
portability analysis exists (82% of scripts vendor-neutral; lock-in is a thin seam: ~150
CLAUDE_PLUGIN_ROOT refs + 58 Task-spawn refs + hooks.json) — ports-and-adapters, native adoptions
in the Claude adapter, not the core.

## Goal
A committed design doc that turns D2 into a buildable plan, informed by the proven runner.

## Scope
1. Architecture: runner as core; adapter seam enumerated concretely (from the portability
   analysis); which judgment layers ride in core vs adapter.
2. Session-start token floor attacked structurally (D7): composed per-spawn prompts replace the 14
   static agent files; what survives of hooks.json outside Claude Code.
3. Distribution/runtime shape (CLI app vs SDK library vs both), auth model, and what "plugin mode"
   remains as.
4. Incremental path: which final-state items (01–09) land in the plugin first vs move straight to
   the app.

## Non-goals
No implementation. No vendor-parity features (north-star explicit NO). No decision on centralized
user identity (D10 — parked; note the hook point only).

## Acceptance criteria
- Design doc committed under loomwright/docs/SPIKES/ citing FINAL_STATE_GOAL.md and the item-05
  measurement; reviewed via normal PR flow.

## Outcomes Rubric
- Architecture + adapter seam concrete
- Token-floor strategy stated with numbers
- Incremental migration path per item

## Status: blocked (final-state 05 — operator-run arm-3 re-run, D1/D11)
- Not enqueueable until 05's eval row exists. Leave for `/automate` to skip; the engine only honours done/done_with_escalation so this line is informational — the title already says BLOCKED.
