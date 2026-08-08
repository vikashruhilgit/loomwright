---
name: roadmap-next-order-drift
description: LEARNING_LOOP_ROADMAP.md "Recommended next order" list restates phase status and goes stale when a phase is flipped to shipped elsewhere in the same doc
metadata:
  type: project
---

`loomwright/docs/SPIKES/LEARNING_LOOP_ROADMAP.md` has a **"Recommended next order:"** numbered list (around line 82) that restates each phase as pending work, SEPARATELY from the status table (~line 75) and the per-phase sections. When a PR flips a phase to "shipped" in the table + its section, the next-order list is an easy-to-miss third restatement of the same fact.

**Why:** On PR #66 (v14.33.0 Phase 2B), the table + Phase 2B section + known-gaps were all updated to "SHIPPED", but next-order item 2 still read "Phase 2B measurement close-out: aggregate knowledge_sources_used in /insights" — an internal contradiction (restated-list drift, `drift_kind: workflow`). Item 1 (Phase 3 residual) was ALSO already stale from a prior release, so the whole list runs ahead of reality.

**How to apply:** In any consistency_audit touching this roadmap, after confirming a phase's table/section status changed, grep the "Recommended next order" list for that phase name and flag it if it still lists the now-shipped work as pending. This list is NOT covered by check-doc-currency.sh (prose, not a version/count claim). Related: [[project_agent_help_phase_drift]] (same class — phase enumerations the CI gate doesn't scan).
