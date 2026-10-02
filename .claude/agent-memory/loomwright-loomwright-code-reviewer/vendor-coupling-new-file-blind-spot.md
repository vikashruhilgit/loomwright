---
name: vendor-coupling-new-file-blind-spot
title: vendor-coupling-new-file-blind-spot
description: A new test file that spells a `.claude/...` path (e.g. the rules-check stamp STAMP_REL) trips check-vendor-coupling.sh in CI, but a worker's pre-`git add` local run is green — the gate enumerates `git ls-files` only.
metadata:
  type: project
source: PR #294 Phase 4.5 review (2026-09-28) — AC12 claimed the full loop green, ground truth 2/2, yet CI `ci` failed at the vendor-coupling ratchet (test-worker-rule-selfcheck.sh core +1, no manifest allowance; sibling test-rules-check.sh carries allowance 1 in loomwright/docs/vendor-coupling-manifest.json). In any review adding a file under loomwright/, run check-vendor-coupling.sh against the COMMITTED tree and check the manifest.
written_at: 2026-10-02T07:21:40Z
head_sha: c594e83
---

A new test file that spells a `.claude/...` path (e.g. the rules-check stamp STAMP_REL) trips check-vendor-coupling.sh in CI, but a worker's pre-`git add` local run is green — the gate enumerates `git ls-files` only.

**Evidence / how to apply:** PR #294 Phase 4.5 review (2026-09-28) — AC12 claimed the full loop green, ground truth 2/2, yet CI `ci` failed at the vendor-coupling ratchet (test-worker-rule-selfcheck.sh core +1, no manifest allowance; sibling test-rules-check.sh carries allowance 1 in loomwright/docs/vendor-coupling-manifest.json). In any review adding a file under loomwright/, run check-vendor-coupling.sh against the COMMITTED tree and check the manifest.
