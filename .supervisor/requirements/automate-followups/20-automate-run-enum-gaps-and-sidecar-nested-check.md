# AUTOMATE_RUN enum gaps + sidecar-check nested-shape blind spot

## Status: pending

> **Promoted from `proposed/` 2026-10-01** (owner triage session).
> **Origin (2026-09-30).** claude[bot] review of trail PR #311 (item 11, run automate-2026-09-30-054439) — owner chose "record as null + follow-up".

## Problem
1. `owned_drain_result` enum (`READY | ESCALATED | died`, docs/RESULT_SCHEMAS.md §AUTOMATE_RUN, skills/automate-loop/SKILL.md §3) has no value for "owner merged the PR mid-drain, before a terminal REVIEW_HEAL_RESULT" (happened on #305). #311 first recorded it as `null` (off-enum), then — after a second bot review — OMITTED the field (the schema does not say omission is allowed either; no value fits). Decide: add a value, or document that the field is absent when no terminal result exists.
2. `pause_reason` enum has no value for "queue not empty, item done, held for the owner's explicit go before the next PICK" — the standing owner rule (memory: close out before next item). #311 briefly wrote `pause_reason: null` (violates §3 "paused is always paired with a pause_reason"), then reverted to `awaiting_merge` — the protocol's expected steady state until the next `--resume` reconciles, but it does not express "held for the owner's go".
3. `sidecar-check` (automate-trail.sh) validates only top-level keys + `risk_classification.reasons`; a SUPERVISOR_RESULT whose `ground_truth` lacks `checked` passed it (#311). Nested object shapes are unchecked.

## Scope (recommendation)
- Add e.g. `superseded_by_merge` to `owned_drain_result` and `awaiting_go` to `pause_reason` (schema + SKILL §3 + RESULT_SCHEMAS in one change); decide whether the merge watcher/closeout should write them.
- Extend sidecar-check's key tables to the nested objects (`ground_truth`, `risk_classification`, `contract_conformance`, …) pinned to RESULT_SCHEMAS, with fixture legs.

## Related
- Separate pending decision: trail-pr timing (fires at the awaiting_merge park, BEFORE the feature merge, committing a `done` stamp for unmerged work) — owner raised 2026-09-30; not yet written up.
