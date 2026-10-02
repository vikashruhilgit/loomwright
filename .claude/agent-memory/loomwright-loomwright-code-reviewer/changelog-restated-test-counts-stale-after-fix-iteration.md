---
name: changelog-restated-test-counts-stale-after-fix-iteration
title: changelog-restated-test-counts-stale-after-fix-iteration
description: A heal fix-iteration that adds test assertions leaves the same release's CHANGELOG entry ("N assertions", "turns N red") stale; no gate scans those numbers
metadata:
  type: project
source: PR #215 heal iteration 2 review, 2026-09-13 — CHANGELOG said 21 assertions / 7 red, suite had 24 / 9 after fix commit 3dcf399
written_at: 2026-10-02T07:21:24Z
head_sha: c594e83
---

When a Phase 4.5 fix commit changes a test suite's assertion count, grep the release's own CHANGELOG entry for restated numbers ("N assertions", "turns N assertions red") — check-doc-currency.sh only scans version/agent/command/skill/hook counts, so these go stale silently.
**Why:** PR #215 iteration 1 added 3 assertions; the v15.69.0 CHANGELOG entry (written in the feature commit) kept 21/7 while the suite reported 24/9. Verified empirically on a scratch copy.
**How to apply:** on any heal iteration >= 2 touching a test-*.sh, diff the suite's RESULT tail against the CHANGELOG entry's numbers.
