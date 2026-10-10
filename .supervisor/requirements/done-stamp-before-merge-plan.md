# Task Plan: done-stamp-before-merge (automate-followups-37)

Source brief: .supervisor/jobs/in-progress/2026-10-09-done-stamp-before-merge.md (base e41f657)

## EPIC done-stamp-before-merge
- [ ] **done-stamp-before-merge-1** Defer requirement done stamp to post-merge closeout + pinning test (single agent, all AC)
  - Lanes: brief Subtask 1 contract lanes PLUS comment-only: loomwright/scripts/automate-helpers.sh (is_done comment ~L174), loomwright/scripts/reconcile-jobs.sh (header L9/L24/L31, L120, L597), loomwright/scripts/test-not-verified-transport-seam.sh (comment L33)
  - Blocked by: none
  - Gate: outputs_verified + bash scripts/ci-local.sh; Phase 4.5 integrated review after FINALIZE (no per-subtask review)
