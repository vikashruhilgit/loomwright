---
name: project_self_heal_rubber_stamp
title: project_self_heal_rubber_stamp
description: Phase 4.5 heal_decision=PASS with heal_iterations=0 historically did NOT predict zero post-PR review rounds; post-hardening (2026-10-02) the heal lens discriminates and the residual gap is skipped conformance
metadata:
  type: project
source: dreaming:1378d676-ffcd-40f8-b6be-5e60d2dbd1ec
written_at: 2026-10-02T07:14:18Z
head_sha: c594e83
---

Across 8 recent session_end records (another repo, 4 PRs + this repo #24/#26/#36/#41) every record reported `heal_decision: PASS` — 5 with `heal_iterations: 0` (heal found nothing) — yet those PRs absorbed 3-6 post-PR review-fix rounds and spawned follow-up PRs (#36, #41). Root cause: Phase 4.5 re-ran the SAME diff-scoped Code Reviewer (inheriting its blind spots) and `ground_truth` was `skipped` everywhere. `2026-06-04-system-twin-foundation` is the in-repo example: heal_iterations:0 in the session_end, then 4 logged `pr_review_fix` rounds (the round-3 sibling fix to `write-project-memory.sh` was only found that late).

**Why:** the holistic re-run inherits the per-subtask reviewer's exact blind spots — same lens, same misses. Fixed by `2026-06-09-self-heal-blind-spot-hardening`: consistency_audit lens for self-repo, repo-agnostic miss-class checklist (validation parity / numeric-falsy / positional-args / branch coverage / count drift), class-level (not instance) fixes, and ground_truth that actually runs via `corpus-task:`.

**How to apply:** do NOT treat heal_decision=PASS as evidence the diff is review-clean. During Phase 4.5 / `/review-pr` heal, actively apply the Self-Heal Miss-Class Checklist (different lens than the per-subtask review), and confirm ground_truth `status != skipped` on plugin-self doc-surface briefs. When evaluating future sessions, check whether post-hardening runs show non-skipped ground_truth and fewer review rounds.

**UPDATE 2026-10-02:** post-hardening the pattern no longer holds — in the last 3 sessions with heal data `heal_iterations` was 1/2/3 (one ESCALATED, parallel-automate-02) and `ground_truth` was pass in all. The residual gap is `contract_conformance_status: skipped` (2/2 where reported), not the heal PASS itself.
