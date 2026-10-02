---
name: attack_self_heal_pass_not_review_clean
title: attack_self_heal_pass_not_review_clean
description: A green heal_decision=PASS does NOT mean the PR is reviewer-clean, and a max-iteration ESCALATED's final fix commit is unreviewed code
metadata:
  type: project
source: dreaming:1378d676-ffcd-40f8-b6be-5e60d2dbd1ec
written_at: 2026-10-02T07:14:22Z
head_sha: c594e83
---

A green `heal_decision: PASS` does NOT mean the PR is reviewer-clean. Do not treat PASS as proof of quality.

**Why:** Since the execution-grounded lens, Phase 4.5 failed iteration 1 with reproduced HIGHs in 4 of 5 in-window runs (2026-09-30..10-02), yet PASS is still not drain-clean (1c7be561 PASSed then needed 3 drain fix cycles), and a max-iteration ESCALATED's final fix commit is unreviewed (704a1d9, 59ad2ad). PASS only means "no NEW BLOCKING/HIGH in the Phase-4.5 diff," not "no findings a reviewer would raise."

**How to apply:** When auditing the self-heal gate, treat PASS as a weak signal. Probe whether ground-truth/conformance actually ran (they're often skipped) before crediting a PASS. See also code-reviewer `self-heal-rubber-stamp` and project MEMORY "PR churn = self-heal blind spot".
