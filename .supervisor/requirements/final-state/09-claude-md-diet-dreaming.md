# 09 — CLAUDE.md diet, curated by /dreaming (D9; carries twin-remediation 04)

## Problem
CLAUDE.md is huge and grows monotonically (release banners, incident notes, restated tables); there
is no curation path for it — /dreaming curates the three advisory stores (supersede/retract shipped
v15.14.0) but never touches CLAUDE.md. Twin-remediation `04-claude-md-diet.md` holds the original
diet analysis — fold it in as the starting inventory; this item extends it with the standing
curation loop.

## Goal
CLAUDE.md carries only what is not derivable elsewhere, and /dreaming keeps it that way —
human-gated, flag-only, never auto-delete.

## Scope
1. Execute the diet per twin-remediation 04's inventory (move narrative to CHANGELOG/docs, keep
   invariants + gotchas + authoritative tables; the two-most-recent-release-notes rule already
   exists — enforce the analogous rule for other rotting sections).
2. Extend /dreaming with a CLAUDE.md-curation pass: propose prune/merge/supersede candidates as
   per-item Accept/Reject actions (same UX as the v15.14.0 store curation; repo-root only, never
   from a worker worktree).
3. Anything the doc-currency gate scans must stay consistent — run the gate + the OLD-value
   repo-wide grep after every diet cut (sweep-grep-gate-variants lesson).

## Non-goals
No changes to what CLAUDE.md is authoritative FOR (hook table etc. stay); no auto-deletion; no new
gates.

## Acceptance criteria
- CLAUDE.md materially smaller with a recorded before/after byte count; nothing load-bearing lost
  (doc-currency + consistency audit green).
- /dreaming proposes CLAUDE.md curation candidates end-to-end with per-item human gating.
- twin-remediation 04 stamped superseded-by-this-item.

## Outcomes Rubric
- Diet executed with byte-count delta recorded
- /dreaming CLAUDE.md pass shipped, human-gated, flag-only
- All doc gates green post-diet

## Status: brief-shipped

Job `.supervisor/jobs/done/2026-08-03-claude-md-diet-dreaming.md` completed (reconciled from the job lifecycle, not self-reported).
Acceptance criteria are NOT machine-verified here — review them before promoting this to `## Status: done`.
