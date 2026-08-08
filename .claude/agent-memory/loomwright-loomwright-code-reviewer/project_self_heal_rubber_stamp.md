---
name: self-heal-rubber-stamp
description: Phase 4.5 heal_decision=PASS with heal_iterations=0 historically did NOT predict zero post-PR review rounds (5/8 such records preceded 3-6 rounds); the v14.x self-heal hardening exists to break this
metadata:
  type: project
---

Across 8 recent session_end records (another repo, 4 PRs + this repo #24/#26/#36/#41) every record reported `heal_decision: PASS` — 5 with `heal_iterations: 0` (heal found nothing) — yet those PRs absorbed 3-6 post-PR review-fix rounds and spawned follow-up PRs (#36, #41). Root cause: Phase 4.5 re-ran the SAME diff-scoped Code Reviewer (inheriting its blind spots) and `ground_truth` was `skipped` everywhere. `2026-06-04-system-twin-foundation` is the in-repo example: heal_iterations:0 in the session_end, then 4 logged `pr_review_fix` rounds (the round-3 sibling fix to `write-project-memory.sh` was only found that late).

**Why:** the holistic re-run inherits the per-subtask reviewer's exact blind spots — same lens, same misses. Fixed by `2026-06-09-self-heal-blind-spot-hardening`: consistency_audit lens for self-repo, repo-agnostic miss-class checklist (validation parity / numeric-falsy / positional-args / branch coverage / count drift), class-level (not instance) fixes, and ground_truth that actually runs via `corpus-task:`.

**How to apply:** do NOT treat heal_decision=PASS as evidence the diff is review-clean. During Phase 4.5 / `/review-pr` heal, actively apply the Self-Heal Miss-Class Checklist (different lens than the per-subtask review), and confirm ground_truth `status != skipped` on plugin-self doc-surface briefs. When evaluating future sessions, check whether post-hardening runs show non-skipped ground_truth and fewer review rounds.
