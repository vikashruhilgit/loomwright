# PO stories carry what an /automate run needs

## Status: parked (merged 2026-11-02 into 2026-11-02-124022-requirement-to-plan-checks.md as Part B — do not run this file)

**Story: PO stories carry what an /automate run needs** (type: story)

**As a** plugin owner who turns a prompt into work with `/automate "<prompt>"` or `/product-owner`,
**I want** every story Product Owner writes to carry its non-goals, the owner's decisions and how the change will be
proven before merge,
**so that** the run that builds it, which receives only the story file, obeys those decisions, and the merge gate
actually checks the proof instead of passing an empty section.

### Problem
`/automate "<prompt>"` runs `/product-owner` and queues the story files it writes, unchanged
(`skills/automate-loop/intake.md`). Product Owner's story template (`skills/user-story-writing/SKILL.md` §"Story
Template") has no Non-goals, Owner decisions or Validation section. The hand-written item shape in the same skill
has all three. Effects, checked 2026-11-02:
- **The validation gate passes empty.** With no `## Validation` section, `validation-gate` prints `none` and the item
  reaches the READY park with nothing checked. Lane readiness reports `NOT-RUN`, but it is advisory.
- **Owner decisions are lost.** The skill's own "Honest limit" says a run receives only the item file, so a
  decision must be copied into the item. The template has no place for one; the decisions stay in the chat report.
- **Non-goals are lost.** They are in Product Owner's chat report (Scope Analysis), not in the file, so neither
  Launch Pad nor Plan Review can see what was excluded.

Three requirement files in this repo use the Product Owner template: the two written by `/product-owner` on
2026-11-02, which had no Validation section until one was added by hand, and `module-layout/01-module-layout-standard.md`,
which has one. Most items here are hand-written in the item shape, so the gap shows mainly on prompt-sourced runs.

### Owner decisions (2026-11-02)
- Add only what a run needs and cannot get elsewhere: Non-goals, Owner decisions, Validation. No other new section.
- Product Owner still writes outcomes, not implementation. Validation names the proof (what must be shown, and the
  project's own test or CI command when CLAUDE.md names one), never how to build it.

### Acceptance Criteria

**Happy Path:**
- [ ] Given a prompt, when Product Owner persists a story, then the file has a `## Validation (must pass before
      merge)` section with at least one entry, in the list format the validation gate parses.
- [ ] Given a story whose outcome can only be shown in a running system (a hook firing, an agent's live answer,
      a UI flow), when Product Owner writes it, then its Validation has a **Running system** entry, so the
      validation gate requires pasted evidence before READY.
- [ ] Given the owner made decisions during the Product Owner session (an answered question gate, a stated
      constraint), when the story is persisted, then they are in the story's Owner decisions section.
- [ ] Given the owner excluded something in the session, when the story is persisted, then it is listed under the
      story's Non-goals.

**Edge Cases:**
- [ ] Given no owner decision was made, when the story is persisted, then Owner decisions reads `none recorded`.
- [ ] Given a story with only static proof (tests, lint), when it is persisted, then Validation lists those checks
      and has no Running system entry, and the validation gate reads `none` because nothing needs pasted evidence.

**Error Scenarios:**
- [ ] Given Product Owner cannot name any proof for a story, when it would persist it, then it does not persist an
      empty Validation section: it raises a flag at its existing confirmation gate, or, when it cannot ask, persists
      nothing and counts the flag in its `po_gate: needs_owner` line.

### Priority
- [x] MVP - Core functionality, must ship

**Rationale:** every prompt-sourced `/automate` item today reaches the merge gate with an empty proof check.

### Assumptions
- The Story Template is restated in Product Owner's output format (`agents/product-owner.md`) and in
  `commands/product-owner.md`. All copies change in the same change (house rule: a restating copy moves with its
  authority).
- The validation gate and lane readiness need no change: they already read a `## Validation` section when present.

### Dependencies
- Depends on: none
- Blocks: none
- Related: `2026-11-02-120033-plan-review-checks-the-brief-against-the-source-requirement.md` checks a brief against
  the requirement's non-goals, which Product Owner stories gain here. Neither needs the other to ship.

### Risks
- Larger story files and a larger Product Owner prompt. Token budgets for the agent, command and skill must be
  updated.
- Product Owner may write weak Validation entries ("tests pass"). The Running system rule and the existing
  validation gate limit the damage: only entries that need evidence are gated.

### Success Metrics
- Over the next 10 prompt-sourced `/automate` items: every story has a Validation section, and every item whose
  change shows only in a running system has a gated Running system entry.

### Handoff
Ready for: `/launch-pad goal: ".supervisor/requirements/2026-11-02-121401-po-stories-carry-what-an-automate-run-needs.md"`

## Validation (must pass before merge)
1. **Template tests:** `bash loomwright/scripts/test-requirement-shape.sh` checks that the Story Template carries
   Non-goals, Owner decisions and a Validation section, and that each copy of the template (Product Owner agent,
   Product Owner command) matches it. Mutation control: the test fails when the Validation section is removed from
   the template.
2. **Running system:** run the branch's `/product-owner` headless (`claude -p --plugin-dir <branch>/loomwright`) on
   two prompts in a scratch project: one whose outcome shows only in a running system, and one with static proof
   only. Pass: both persisted stories pass `plan-waves --lint`, the first has a Running system entry and the
   second does not. The two story files go in `loomwright/docs/evidence/po-story-validation.md`, and the PR body
   links to it.
3. **Budgets:** the Product Owner agent, command and `user-story-writing` skill budgets are updated
   (`loomwright/docs/prompt-token-budgets.json` and the mirror rows in `loomwright/docs/ARCHITECTURE_CONTRACTS.md`),
   and `bash scripts/check-token-budget.sh` passes.
4. **Release and suite:** `bash scripts/check-version-bump.sh` passes and `bash scripts/ci-local.sh --affected`
   is green.

## Depends on
none

## Touches
loomwright/skills/user-story-writing/SKILL.md
loomwright/agents/product-owner.md
loomwright/commands/product-owner.md
loomwright/scripts/test-requirement-shape.sh
loomwright/docs/evidence/po-story-validation.md
loomwright/docs/prompt-token-budgets.json
loomwright/docs/ARCHITECTURE_CONTRACTS.md
changelog.d/po-stories-carry-run-needs.md
