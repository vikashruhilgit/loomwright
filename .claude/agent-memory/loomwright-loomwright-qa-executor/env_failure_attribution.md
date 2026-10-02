---
name: env_failure_attribution
title: env_failure_attribution
description: Classify a failing self-test as ENVIRONMENT_ISSUE only after reproducing the pass on a clean base worktree (known case: orca-mirror leg L vs gitignored sdk-spike/node_modules)
metadata:
  type: feedback
source: dreaming:1378d676-ffcd-40f8-b6be-5e60d2dbd1ec
written_at: 2026-10-02T07:24:47Z
head_sha: c594e83
---

Classify a failing self-test as ENVIRONMENT_ISSUE only after reproducing the pass on a clean base worktree. Known case: `adapters/orca/test-orca-mirror.sh` leg L — the primary checkout's gitignored `loomwright/sdk-spike/node_modules` trips the core-cleanliness scan; it passes on a clean worktree.

**Why:** workers attribute it correctly but each one re-discovers it, and an unproven "pre-existing" label can hide a real regression. Seen in 4 worker summaries (hermetic-test-egress-1, parallel-automate-01, verify-walkthrough, floor-ui).

**How to apply:** record it under environment_issues, not bugs_found; do not count it against tests_failed severity. Mirrors LESSONS 55534238.
