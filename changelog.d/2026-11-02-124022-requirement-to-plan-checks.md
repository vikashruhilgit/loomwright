<!-- bump: minor -->
Plan Review checks the brief against its source requirement, and Product Owner stories carry Non-goals, Owner decisions and Validation
Part A: Plan Reviewer gains Criterion 22 "Requirement Fit", a two-way mapping between the source requirement and the
brief. Each requirement line (acceptance criterion, Goal or Scope item, Validation entry, non-goal) maps to the brief
unit that covers it or to `missing`; each brief unit maps to the requirement line it serves, to `supporting` (tests,
the changelog fragment, doc or budget updates) or to `extra`. The reviewer prints the mapping as a `### Requirement
fit` table before its result. `PLAN_REVIEW_RESULT` gains an optional `requirement_fit: fulfils | under | over |
skipped` field (schema_version stays 1) and the `requirement_fit` issue category: a `missing` line or a unit that
delivers a requirement non-goal is HIGH and fails the review (`under`), an `extra` unit is MEDIUM that Launch Pad
refines (`over`), and `skipped` (the brief names a `Source requirement:` the reviewer never received) is a LOW note,
never a pass. With a literal one-line goal only the `extra` check runs. `validate-plan-review-result.py` gains rule 7
(`requirement_fit` is one of the four values) and rule 8 (`under` requires `decision: FAIL`); an absent field still
passes. Launch Pad's Phase 5.5 spawn contract now pastes the requirement file verbatim between `--- SOURCE
REQUIREMENT ---` and `--- SOURCE REQUIREMENT END ---` when `source_requirement` is set, the routed seat included, and
its refine branch fixes a `missing` issue by adding coverage, never by deleting the requirement line. The criteria
count pins move from 21 to 22, `POINTER_AUDIT.md` gains a row for the new paste, and four seeded requirement + brief
pairs under `loomwright/scripts/fixtures/plan-review-requirement-fit/` rate `fulfils`, `under`, `over`, `fulfils` in
live headless runs. Part B: the `user-story-writing` Story Template gains `### Non-goals`, `### Owner decisions`
(`none recorded` when the owner made no decision) and an H2 `## Validation (must pass before merge)` before `## Depends
on`, as a numbered list of bold-titled entries the `validation-gate` reader parses; a story whose outcome shows only in
a running system carries a Running system entry. Product Owner's agent and command Output Format and Persist step carry
the same three sections, and a story with no nameable proof is never persisted with an empty Validation section: it is
a missing-proof flag at the existing confirmation gate, counted in `po_gate: needs_owner` when the gate cannot ask.
`test-requirement-shape.sh` gains S6 and its mutation control M4. Budgets re-measured: `plan-reviewer` agent 9451 →
11535 (measured 10528), `user-story-writing` skill 4732 → 5709 (measured 5190) and `product-owner` command 10258 →
11537 (measured 10488) raised to measured + ~10% after breaching; `launch-pad` agent (45127 / 47557), `product-owner`
agent (16719 / 17356) and `launch-pad` command (5326 / 5515) re-measured with no raise. Deviation from the requirement:
the live-run evidence files are `docs/evidence/plan-review-requirement-fit.md` and `docs/evidence/po-story-validation.md`
at the repo root, not under `loomwright/docs/evidence/`, because FINALIZE's PR-body `## Evidence` section links only
root `docs/evidence/` files, so a `loomwright/docs/evidence/` file would never be linked from the PR body.
The `PO-ASSUME` gate catalog purpose in `lane-policy.sh` (and its `LANE_GATES.md` mirror) now names the missing-proof flag.
