# Requirement to plan: Plan Review checks fit, PO stories carry what a run needs

## Status: pending

## Merged from (2026-11-02)
- Part A: `2026-11-02-120033-plan-review-checks-the-brief-against-the-source-requirement.md` — Plan Review checks the brief against the source requirement
- Part B: `2026-11-02-121401-po-stories-carry-what-an-automate-run-needs.md` — PO stories carry what an /automate run needs

The originals are parked with a pointer here. Their text is kept below VERBATIM as parts (headings
demoted one level, their Status / Depends on / Touches folded into this file's own sections). Nothing was paraphrased.

Edited by hand after the merge (2026-11-02): the parts' two Validation sections, demoted to `###` by the merge, are
moved into one `## Validation` section (the validation gate reads only an H2 section), and each part's Handoff and
cross-reference now point at this merged item instead of the parked originals.

## Goal
Close the two unchecked steps between what the owner asks for and what gets planned: Plan Review compares the brief with the source requirement (Part A), and Product Owner stories carry the Non-goals, Owner decisions and Validation that the run and Plan Review need (Part B).

## Part A — Plan Review checks the brief against the source requirement

**Story: Plan Review checks the brief against the source requirement** (type: story)

**As a** plugin owner who hands a requirement to `/launch-pad` or `/automate`,
**I want** Plan Review to confirm the brief builds what the requirement asks, no less and no more,
**so that** a misread requirement is caught before any code is written, instead of after a PR is reviewed.

#### Problem
Plan Reviewer is given the brief text and a CLAUDE.md excerpt, never the original requirement. The brief carries
only the requirement's path. So a well-formed brief that misreads the requirement passes all of Plan Review's
checks, and every later check inherits the error: the Rubric Grader and Phase 4.5 measure the code against the
brief, which Launch Pad wrote. No step compares the requirement with the brief.

#### Owner decisions (2026-11-02)
- The check is a two-way mapping, and the rating follows from it: each requirement line maps to the subtask that
  covers it, or to `missing`; each subtask maps to the requirement line it serves, or to `extra`. Not a single
  free-form verdict.
- Reuse the existing Plan Reviewer. No new agent.
- Tests, the changelog fragment, and doc or budget updates are supporting work, never `extra`.
- With a literal one-line goal (no requirement file), only the `extra` check applies.
- An `extra` subtask is **MEDIUM**: Launch Pad refines it (removes the subtask or links it to the requirement line
  it serves) and the run continues. Not NEEDS_HUMAN, which would stop an unattended run for small, usually harmless
  extra work. A `missing` requirement line stays a failure.

#### Acceptance Criteria

**Happy Path:**
- [ ] Given a requirement file and a brief that covers every requirement line with nothing extra, when Plan Review
      runs, then it rates the brief `fulfils` and raises no requirement-fit issue.
- [ ] Given a brief that leaves a requirement line uncovered, when Plan Review runs, then it names that line as
      `missing`, rates the brief `under`, and the review fails, so Launch Pad revises the brief.
- [ ] Given a brief with a subtask that serves no requirement line, when Plan Review runs, then it names that
      subtask as `extra`, rates the brief `over`, and raises a MEDIUM issue that Launch Pad refines.
- [ ] Given the review's result, when the owner or Launch Pad reads it, then the mapping is shown line by line, so
      each `missing` or `extra` can be checked.

**Edge Cases:**
- [ ] Given a brief whose only unmapped subtasks are tests, a changelog fragment and doc or budget updates, when
      Plan Review runs, then they count as supporting work and no issue is raised.
- [ ] Given a literal one-line goal, when Plan Review runs, then only the `extra` check runs and the result says
      the coverage check was skipped.
- [ ] Given a brief with a subtask that delivers something the requirement lists as a non-goal, when Plan Review
      runs, then that subtask is flagged and the review fails.

**Error Scenarios:**
- [ ] Given Plan Review cannot see the requirement (an older Launch Pad that does not pass it), when it runs, then
      it reports the requirement-fit check as skipped, never as passed.

#### Priority
- [x] MVP - Core functionality, must ship

**Rationale:** it closes the only unchecked step between what the owner asked for and what gets built.

#### Assumptions
- Requirement files have enough structure (criteria, scope, non-goals) to map line by line. Files that don't still
  get the `extra` check.
- Plan Review's other checks and its decision rules stay as they are. Every surface that restates Plan Review's
  criteria, issue categories or result fields is updated in the same change (house rule: a restating copy moves
  with its authority).
- A Plan Reviewer routed to another provider receives the requirement in its prompt, the same way it receives the
  brief.

#### Dependencies
- Depends on: none
- Blocks: none

#### Risks
- Each Plan Review spawn grows by the requirement's size (a few thousand tokens, up to 3 spawns per Launch Pad
  session). The agent's declared token budgets must be updated.
- A strict reviewer may call a needed refactor `extra`. The supporting-work rule and the owner's severity choice
  limit how much that can cost: a MEDIUM issue never stops a run.

#### Success Metrics
- Over the next 10 briefs: the number of `missing` failures (each a misread caught before build), and how many
  `extra` flags the owner judged real. If most `extra` flags are noise, widen the supporting-work list.

#### Handoff
Ready for: `/launch-pad goal: ".supervisor/requirements/2026-11-02-124022-requirement-to-plan-checks.md"` (this merged item; Part A's own Validation entries are in the merged `## Validation` section below)

## Part B — PO stories carry what an /automate run needs

**Story: PO stories carry what an /automate run needs** (type: story)

**As a** plugin owner who turns a prompt into work with `/automate "<prompt>"` or `/product-owner`,
**I want** every story Product Owner writes to carry its non-goals, the owner's decisions and how the change will be
proven before merge,
**so that** the run that builds it, which receives only the story file, obeys those decisions, and the merge gate
actually checks the proof instead of passing an empty section.

#### Problem
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

#### Owner decisions (2026-11-02)
- Add only what a run needs and cannot get elsewhere: Non-goals, Owner decisions, Validation. No other new section.
- Product Owner still writes outcomes, not implementation. Validation names the proof (what must be shown, and the
  project's own test or CI command when CLAUDE.md names one), never how to build it.

#### Acceptance Criteria

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

#### Priority
- [x] MVP - Core functionality, must ship

**Rationale:** every prompt-sourced `/automate` item today reaches the merge gate with an empty proof check.

#### Assumptions
- The Story Template is restated in Product Owner's output format (`agents/product-owner.md`) and in
  `commands/product-owner.md`. All copies change in the same change (house rule: a restating copy moves with its
  authority).
- The validation gate and lane readiness need no change: they already read a `## Validation` section when present.

#### Dependencies
- Depends on: none
- Blocks: none
- Related: Part A of this item checks a brief against the requirement's non-goals, which Product Owner stories gain
  here. Neither part needs the other to ship.

#### Risks
- Larger story files and a larger Product Owner prompt. Token budgets for the agent, command and skill must be
  updated.
- Product Owner may write weak Validation entries ("tests pass"). The Running system rule and the existing
  validation gate limit the damage: only entries that need evidence are gated.

#### Success Metrics
- Over the next 10 prompt-sourced `/automate` items: every story has a Validation section, and every item whose
  change shows only in a running system has a gated Running system entry.

#### Handoff
Ready for: `/launch-pad goal: ".supervisor/requirements/2026-11-02-124022-requirement-to-plan-checks.md"` (this merged item)

## Validation (must pass before merge)
Merged from both parts' Validation sections (each entry says which part it proves). The two Budgets entries and the
two Release entries are combined into one each.

1. **Result validator (Part A):** `bash loomwright/scripts/test-result-validators.sh` accepts a Plan Review result
   carrying the requirement-fit rating and issue category, and rejects a malformed rating.
2. **Template tests (Part B):** `bash loomwright/scripts/test-requirement-shape.sh` checks that the Story Template
   carries Non-goals, Owner decisions and a Validation section, and that each copy of the template (Product Owner
   agent, Product Owner command) matches it. Mutation control: the test fails when the Validation section is removed
   from the template.
3. **Running system — Plan Review (Part A):** run the branch's Plan Reviewer headless (`claude -p --plugin-dir
   <branch>/loomwright`, which loads only the branch's copy) on four seeded requirement + brief pairs committed under
   `loomwright/scripts/fixtures/`: one that fulfils, one missing a requirement line, one with an extra subtask, and
   one whose only unmapped subtasks are tests, a changelog fragment and a budget update. Pass: the ratings read
   `fulfils`, `under`, `over` and `fulfils`. The verdicts go in `loomwright/docs/evidence/plan-review-requirement-fit.md`,
   and the PR body links to it.
4. **Running system — Product Owner (Part B):** run the branch's `/product-owner` headless (`claude -p --plugin-dir
   <branch>/loomwright`) on two prompts in a scratch project: one whose outcome shows only in a running system, and
   one with static proof only. Pass: both persisted stories pass `plan-waves --lint`, the first has a Running system
   entry and the second does not. The two story files go in `loomwright/docs/evidence/po-story-validation.md`, and the
   PR body links to it.
5. **Budgets (Parts A and B):** the Plan Reviewer, Launch Pad, Product Owner agent and command, and
   `user-story-writing` skill token budgets are updated (`loomwright/docs/prompt-token-budgets.json` and the mirror
   rows in `loomwright/docs/ARCHITECTURE_CONTRACTS.md`), and `bash scripts/check-token-budget.sh` passes.
6. **Release and suite:** `bash scripts/check-version-bump.sh` passes and `bash scripts/ci-local.sh --affected`
   is green.

## Depends on
none

## Touches
changelog.d/2026-11-02-124022-requirement-to-plan-checks.md
loomwright/agents/launch-pad.md
loomwright/agents/plan-reviewer.md
loomwright/agents/product-owner.md
loomwright/commands/launch-pad.md
loomwright/commands/product-owner.md
loomwright/docs/ARCHITECTURE_CONTRACTS.md
loomwright/docs/evidence/plan-review-requirement-fit.md
loomwright/docs/evidence/po-story-validation.md
loomwright/docs/prompt-token-budgets.json
loomwright/docs/result-schemas/plan-review-result.md
loomwright/scripts/fixtures/plan-review-requirement-fit/
loomwright/scripts/test-requirement-shape.sh
loomwright/scripts/test-result-validators.sh
loomwright/scripts/validate-plan-review-result.py
loomwright/skills/user-story-writing/SKILL.md
