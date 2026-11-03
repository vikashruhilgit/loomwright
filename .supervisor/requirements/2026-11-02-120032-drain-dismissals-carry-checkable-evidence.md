# Drain dismissals carry checkable evidence

## Status: pending

**Story: Drain dismissals carry checkable evidence** (type: story)

**As a** plugin owner deciding fix-now / follow-up / drop on dismissed findings when an `/automate` item parks,
**I want** every finding the `/review-pr --until-mergeable` drain dismisses to name proof I can check,
**so that** I can confirm or overturn a dismissal in seconds, and no finding is dismissed on the author's word alone.

### Problem
In the drain's validate-then-fix step, a confirmed finding must cite a `file:line` on the current branch, but a
dismissed finding needs only a free-text one-line reason ("stale", "invalid", "already-addressed"). The owner's
dismissed-findings draft shows that reason and nothing else, so checking a dismissal means re-investigating it.
The last 60 merged PRs carry 280 dismissals across 43 PRs (counted from the drain's per-round dismissed-findings
comments, 2026-11-02).

### Owner decisions (2026-11-02)
- No new verdict or outcome. The owner already decides drafted dismissals at the park; that is the escalation.
- The PR drain only. Phase 4.5 dismissals are out of scope: `2026-11-01-092114-phase-4-5-re-reviews-converge-on-what-the-last-fix-changed.md` already changes Phase 4.5's dismissal records.
- No memory of dismissals across rounds. Measured: 12 of the 280 dismissals were repeats, and every one was
  re-dismissed the same way.

### Acceptance Criteria

**Happy Path:**
- [ ] Given the drain dismisses a finding, when the round is recorded, then the dismissal carries evidence in one
      of three checkable forms: a repo path with a line, a commit sha, or a quoted span from the PR diff, PR body
      or brief.
- [ ] Given a dismissal with evidence, when the drain posts its round comment and returns its result, then both
      show that evidence next to the reason.
- [ ] Given a drafted dismissed finding with evidence, when `/automate` writes the owner's draft, then the draft
      shows the evidence under the reason.

**Edge Cases:**
- [ ] Given a finding dismissed because its severity is below the fix floor, when it is recorded, then its
      evidence states the severity and the floor, and it is never refused for missing evidence.
- [ ] Given a drain result written before this change (no evidence field), when `/automate` drafts it, then the
      draft says no evidence was recorded and nothing fails.
- [ ] Given a dismissal whose proof is outside the repo (an owner decision, a convention), when the validator has
      no checkable form to cite, then the finding is not dismissed: it stays a confirmed finding that is not
      auto-fixable, and so still blocks READY and reaches the owner.

**Error Scenarios:**
- [ ] Given a dismissal with no evidence, when the validator reports it, then the drain refuses the report with a
      message naming the missing evidence, records nothing, and the validator answers again.
- [ ] Given evidence that matches none of the three forms (for example the single word "intentional"), when the
      validator reports it, then the drain refuses it the same way.

### Priority
- [x] MVP - Core functionality, must ship

**Rationale:** smallest change that closes the gap where the drain's author can dismiss a finding unchecked. No new
gate, no new park.

### Assumptions
- The validating model can name a path:line, sha or quote for a genuine dismissal. If refusals are frequent in the
  first runs, the accepted forms are too strict and should be widened, not removed.
- Every surface that restates the dismissal record's fields (the driver's result schema, the review-heal result
  schema, the review-heal skill) is updated in the same change (house rule: a restating copy moves with its
  authority).

### Dependencies
- Depends on: none
- Blocks: none
- Shares files with pending items, so it cannot run in the same `--parallel` wave as them:
  `dismissed-followups/12-bundle-04ab-drivers-and-gate-tooling.md` (the drain driver) and
  `dismissed-followups/01-follow-up-decision-becomes-tracked-work.md` (the dismissed-findings draft writer).

### Risks
- Each refused report costs one extra validator answer in that round (not a new review).
- Overlap with the two pending items above on the same scripts: whichever lands second must rebase onto the other.

### Success Metrics
- Over the next 10 drains that dismiss anything: every dismissal carries evidence, and the owner's park decisions
  need no re-investigation to confirm a dismissal.

### Handoff
Ready for: `/launch-pad goal: ".supervisor/requirements/2026-11-02-120032-drain-dismissals-carry-checkable-evidence.md"`

## Validation (must pass before merge)
1. **Driver tests:** `bash loomwright/scripts/test-review-heal-next-step.sh` covers every acceptance criterion
   above, each with a mutation control: the test must fail when the evidence check is removed from the driver.
2. **Draft tests:** `bash loomwright/scripts/test-automate-dismissed.sh` covers a draft with an evidence line and
   a draft from an older result with no evidence.
3. **Release and suite:** `bash scripts/check-version-bump.sh` passes and `bash scripts/ci-local.sh --affected`
   is green.

## Depends on
none

## Touches
loomwright/scripts/review-heal-next-step.sh
loomwright/scripts/test-review-heal-next-step.sh
loomwright/scripts/automate-dismissed.sh
loomwright/scripts/test-automate-dismissed.sh
loomwright/docs/result-schemas/review-heal-next-step.md
loomwright/docs/result-schemas/review-heal-result.md
loomwright/skills/review-heal/SKILL.md
changelog.d/drain-dismissals-carry-evidence.md

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-11-03T01:19:14Z
- **Brief:** .supervisor/jobs/done/2026-11-02-drain-dismissals-carry-evidence.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/801
