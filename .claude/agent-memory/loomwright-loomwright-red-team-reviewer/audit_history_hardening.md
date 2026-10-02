---
name: audit_history_hardening
title: audit_history_hardening
description: Audit history — 2026-09-21 full-plugin audit closed by PRs #248-#256 (do not re-report); 2026-10-01 parallel-automate audit fixed in specs, attack the implementations next
metadata:
  type: project
source: dreaming:1378d676-ffcd-40f8-b6be-5e60d2dbd1ec
written_at: 2026-10-02T07:35:28Z
head_sha: c594e83
---

- **2026-09-21 full-plugin audit** (SHIP_BLOCKED, 2 FATAL / 5 CRITICAL) was closed by 8 items merged as PRs #248–#256. Do not re-report those findings.
- **2026-10-01 parallel-automate audit** (SHIP_BLOCKED, 4 FATAL / 7 CRITICAL) was fixed in the SPECS. Next time attack the IMPLEMENTATIONS of items 03/05/06, not the specs — the meta-sync implementation (item 02) still failed Phase 4.5 three times after its spec passed.

**Unverified lead:** meta-sync's lock-reclaim race may also exist in `run-lock.sh` and `dispatch-pr-review.sh`, whose TTL-reclaim shape it copied. Reproduce before reporting.
