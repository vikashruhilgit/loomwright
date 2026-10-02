---
name: ci_wiring_and_userland_gap
title: ci_wiring_and_userland_gap
description: For a new script's test check CI wiring (glob or ci.yml), macOS-only userland, and git-add before any git-ls-files ratchet
metadata:
  type: feedback
source: dreaming:1378d676-ffcd-40f8-b6be-5e60d2dbd1ec
written_at: 2026-10-02T07:24:48Z
head_sha: c594e83
---

When assessing coverage for a new script's test, check:
(a) it is picked up by the `loomwright/scripts/test-*.sh` glob or named in `ci.yml` — root `scripts/` tests are not globbed;
(b) whether it was exercised only on macOS bash 3.2 + BSD tools — flag "GNU/Linux userland unverified" as a standing gap;
(c) new files were `git add`ed before any `git ls-files`-based ratchet was measured.

**Why:** 3 worker summaries (hermetic-test-egress-1, parallel-automate-01, parallel-automate-02) list GNU/CI as not_verified, and `scripts/test-bump-version.sh` has no ci.yml step. `scripts/ci-local.sh` now covers (a) and (c) in one run.
