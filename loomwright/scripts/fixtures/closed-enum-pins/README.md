# Criterion 19 fixtures: expected findings

This file is the answer key for the four `brief-*.md` fixtures in this directory. It is **never shown to a
reviewer**: a live Plan Reviewer probe passes brief content only, so no brief carries a verdict, a label, a criterion number or a header comment.
`scripts/test-closed-enum-pins-seam.sh` fails if a hint leaks into a brief and pins the rows below.

The three enum briefs share one title and one change: a new Phase 4.5 heal reason `rules_gate_unreadable`, split
from its sibling `rules_gate_unresolved`, plus a new seam pin P11. They name real files in this repo, so a live probe
can run the sibling grep itself. `brief-plain.md` is an ordinary doc edit with no new value and no pin.

Criterion 19 findings are MEDIUM, so none of these moves the decision off PASS on its own (Launch Pad refines a
MEDIUM at the default fix floor). Only the Criterion 19 columns are the answer key; other criteria may add their
own notes on a fixture.

| Fixture | Expected Criterion 19 result |
|---|---|
| `brief-plain.md` | none: no `closed_enumerations` or `pin_mutations` issue (no new value, no pin, so neither section is needed) |
| `brief-bare.md` | 19a MEDIUM `closed_enumerations` (new value, no section) and 19b MEDIUM `pin_mutations` (new pin, no section) |
| `brief-complete.md` | none: both sections present, every closed list it marks `extend` is in its File Impact Map |
| `brief-uncovered.md` | 19c MEDIUM `closed_enumerations` (`loomwright/skills/review-heal/SKILL.md` marked `extend`, not in its File Impact Map or `lanes:`) |
