---
name: gate-input-swap-orphans-old-branch
title: gate-input-swap-orphans-old-branch
description: When a diff swaps a gate's INPUT (worker self-report -> disk re-check), enumerate every branch of the OLD gate and confirm each still terminates; PR #217 dropped the `status: partial` + `outputs_gap: ""` -> CHECKPOINT branch into a `pass` and a comment-only crash path
metadata:
  type: project
source: PR #217 (v15.70.0) Phase 4.5 review of agents/execute-manager.md §"v12 outputs_verified gate" — old `if partial OR gap != ""` -> checkpoint became `elif ... pass`; the legacy fall-through `disk = worker_result` had ABSENT handled only by a comment
written_at: 2026-10-02T07:21:28Z
head_sha: c594e83
---

When a diff swaps a gate's INPUT (worker self-report -> disk re-check), enumerate every branch of the OLD gate and confirm each still terminates; PR #217 dropped the `status: partial` + `outputs_gap: ""` -> CHECKPOINT branch into a `pass` and a comment-only crash path

**Evidence / how to apply:** PR #217 (v15.70.0) Phase 4.5 review of agents/execute-manager.md §"v12 outputs_verified gate" — old `if partial OR gap != ""` -> checkpoint became `elif ... pass`; the legacy fall-through `disk = worker_result` had ABSENT handled only by a comment
