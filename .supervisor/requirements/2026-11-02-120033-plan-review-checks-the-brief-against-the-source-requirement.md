# Plan Review checks the brief against the source requirement

## Status: parked (merged 2026-11-02 into 2026-11-02-124022-requirement-to-plan-checks.md as Part A — do not run this file)

**Story: Plan Review checks the brief against the source requirement** (type: story)

**As a** plugin owner who hands a requirement to `/launch-pad` or `/automate`,
**I want** Plan Review to confirm the brief builds what the requirement asks, no less and no more,
**so that** a misread requirement is caught before any code is written, instead of after a PR is reviewed.

### Problem
Plan Reviewer is given the brief text and a CLAUDE.md excerpt, never the original requirement. The brief carries
only the requirement's path. So a well-formed brief that misreads the requirement passes all of Plan Review's
checks, and every later check inherits the error: the Rubric Grader and Phase 4.5 measure the code against the
brief, which Launch Pad wrote. No step compares the requirement with the brief.

### Owner decisions (2026-11-02)
- The check is a two-way mapping, and the rating follows from it: each requirement line maps to the subtask that
  covers it, or to `missing`; each subtask maps to the requirement line it serves, or to `extra`. Not a single
  free-form verdict.
- Reuse the existing Plan Reviewer. No new agent.
- Tests, the changelog fragment, and doc or budget updates are supporting work, never `extra`.
- With a literal one-line goal (no requirement file), only the `extra` check applies.
- An `extra` subtask is **MEDIUM**: Launch Pad refines it (removes the subtask or links it to the requirement line
  it serves) and the run continues. Not NEEDS_HUMAN, which would stop an unattended run for small, usually harmless
  extra work. A `missing` requirement line stays a failure.

### Acceptance Criteria

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

### Priority
- [x] MVP - Core functionality, must ship

**Rationale:** it closes the only unchecked step between what the owner asked for and what gets built.

### Assumptions
- Requirement files have enough structure (criteria, scope, non-goals) to map line by line. Files that don't still
  get the `extra` check.
- Plan Review's other checks and its decision rules stay as they are. Every surface that restates Plan Review's
  criteria, issue categories or result fields is updated in the same change (house rule: a restating copy moves
  with its authority).
- A Plan Reviewer routed to another provider receives the requirement in its prompt, the same way it receives the
  brief.

### Dependencies
- Depends on: none
- Blocks: none

### Risks
- Each Plan Review spawn grows by the requirement's size (a few thousand tokens, up to 3 spawns per Launch Pad
  session). The agent's declared token budgets must be updated.
- A strict reviewer may call a needed refactor `extra`. The supporting-work rule and the owner's severity choice
  limit how much that can cost: a MEDIUM issue never stops a run.

### Success Metrics
- Over the next 10 briefs: the number of `missing` failures (each a misread caught before build), and how many
  `extra` flags the owner judged real. If most `extra` flags are noise, widen the supporting-work list.

### Handoff
Ready for: `/launch-pad goal: ".supervisor/requirements/2026-11-02-120033-plan-review-checks-the-brief-against-the-source-requirement.md"`

## Validation (must pass before merge)
1. **Result validator:** `bash loomwright/scripts/test-result-validators.sh` accepts a Plan Review result carrying
   the requirement-fit rating and issue category, and rejects a malformed rating.
2. **Running system:** run the branch's Plan Reviewer headless (`claude -p --plugin-dir <branch>/loomwright`,
   which loads only the branch's copy) on four seeded requirement + brief pairs committed under
   `loomwright/scripts/fixtures/`: one that fulfils, one missing a requirement line, one with an extra subtask, and
   one whose only unmapped subtasks are tests, a changelog fragment and a budget update. Pass: the ratings read
   `fulfils`, `under`, `over` and `fulfils`. The verdicts go in `loomwright/docs/evidence/plan-review-requirement-fit.md`,
   and the PR body links to it.
3. **Budgets:** the Plan Reviewer and Launch Pad token budgets are updated (`loomwright/docs/prompt-token-budgets.json`
   and the mirror rows in `loomwright/docs/ARCHITECTURE_CONTRACTS.md`), and `bash scripts/check-token-budget.sh` passes.
4. **Release and suite:** `bash scripts/check-version-bump.sh` passes and `bash scripts/ci-local.sh --affected`
   is green.

## Depends on
none

## Touches
loomwright/agents/plan-reviewer.md
loomwright/agents/launch-pad.md
loomwright/commands/launch-pad.md
loomwright/docs/result-schemas/plan-review-result.md
loomwright/scripts/validate-plan-review-result.py
loomwright/scripts/test-result-validators.sh
loomwright/scripts/fixtures/plan-review-requirement-fit/
loomwright/docs/evidence/plan-review-requirement-fit.md
loomwright/docs/prompt-token-budgets.json
loomwright/docs/ARCHITECTURE_CONTRACTS.md
changelog.d/plan-review-requirement-fit.md
