# 04 — Two review lenses, not four passes (Fix 7, D4)

## Problem
Four review passes run by default on one PR (per-subtask reviewers; Phase 4.5 integrated review;
the detached `/review-pr --until-mergeable` drain's own diff review; CI `claude-review`), each
added independently, each defaulting ON, with no rule that a later pass skips what an earlier one
covered. The duplication is precisely: two LLM reviews of the same diff before a human sees it
(Phase 4.5 + the drain's review half), plus CI. The drain's CHANNEL-DRAINING half is NOT
duplicative — it is the healing arm for CI findings.

## Goal
Two independent lenses with different information: Phase 4.5 (working tree + brief + rubric) and CI
review (independent context, PR-only). Every surviving pass has a stated reason.

## Scope
1. Reduce the drain to its **heal-only** role: drain CI checks/bot threads/comments, skip its own
   redundant diff review. Keep `READY`/`ESCALATED` terminal semantics and never-merges invariant.
2. Per-subtask review pass: dies with item 01's single-agent default below threshold; above
   threshold, keep the deterministic `outputs_verified` gate and drop the per-subtask LLM reviewer
   (integrated Phase 4.5 review covers it — also kills the worktree-isolation cross-file
   false-positive class).
3. Write the counter-pressure rule: when a pass is owed, and what information it must have that the
   prior pass lacked.
4. **Verify before cutting:** confirm the drain's CI-healing role live by asserting on posted
   comments/reviews (`gh pr view --json comments,reviews`), never run conclusion. Remember
   claude-code-action self-skips on workflow-touching PRs with a green check.
5. **Measure after:** `/pr-postmortem` review-round classes from
   `.supervisor/postmortem/results.jsonl` before/after — whether dropping a pass raised defect rate
   is answerable from data already collected.

## Non-goals
Never touch the single-sanctioned-merge-executor invariant. No changes to CI workflow itself. Do
not remove the drain's dispatch paths (step 5.5 + PostToolUse hook) — only its redundant review
half.

## Acceptance criteria
- Default PR flow = exactly two LLM lenses + deterministic gates; each documented with its
  information advantage.
- Drain heal-only mode shipped; all restating surfaces (commands/supervisor.md, review-heal skill,
  RESULT_SCHEMAS if fields change) synced same-PR.
- Live verification of CI-healing recorded before the cut; postmortem baseline captured.

## Outcomes Rubric
- Drain reduced to heal-only with invariants intact
- Per-subtask LLM review removed above/below threshold per item-01 design
- Counter-pressure rule written and cited by the passes that survive
- Before/after measurement plan recorded with baseline

## Status: brief-shipped

Job `.supervisor/jobs/done/2026-07-30-fix7-two-review-lenses.md` completed (reconciled from the job lifecycle, not self-reported).
Acceptance criteria are NOT machine-verified here — review them before promoting this to `## Status: done`.
