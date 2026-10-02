---
name: feedback_findings_need_repro_and_anchor
title: feedback_findings_need_repro_and_anchor
description: Every red-team finding carries a pasted repro and is marked reproduced vs read-only, with exact file:line plus a grep-able anchor — authors copy findings into committed docs
metadata:
  type: feedback
source: dreaming:1378d676-ffcd-40f8-b6be-5e60d2dbd1ec
written_at: 2026-10-02T07:14:23Z
head_sha: c594e83
---

Every finding carries a pasted repro (command + output) and is marked **reproduced** vs **read-only**, plus the exact file:line AND a grep-able anchor string.

**Why:** requirement authors copy findings into committed docs, and cited lines were off in 3 of 3 sampled briefs (cost-ceiling, hardening-sweep, test-integrity-guard). Findings with a pasted command + output were adopted as written; read-only ones were re-verified downstream.

**How to apply:** label every unreproduced claim as read-only so the next stage re-verifies it instead of trusting it.
