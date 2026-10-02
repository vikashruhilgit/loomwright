---
name: attack_failclosed_vs_failsafe_split
title: attack_failclosed_vs_failsafe_split
description: This plugin's failure philosophy is bimodal — correctness gates fail CLOSED, side-effect emitters fail SAFE; attack any deviation, including a fail-SAFE reader feeding a gate and an unscoped fail-CLOSED enumeration
metadata:
  type: project
source: dreaming:1378d676-ffcd-40f8-b6be-5e60d2dbd1ec
written_at: 2026-10-02T07:14:20Z
head_sha: c594e83
---

This plugin's failure philosophy is intentionally bimodal. Attack any deviation as a security regression.

**Why:** Correctness gates and side-effect emitters have opposite correct postures; inverting either flips the security posture silently.

**How to apply:** (a) CI / `--non-interactive` / stdin-not-tty correctness gates MUST fail CLOSED — `preflight-sync-gate` aborts with `preflight_overlap_detected`, autonomous loop aborts with `non_interactive_without_fallback`, rubric gate aborts with `rubric_gate_closed_non_interactive`. A gate that silently proceeds under automation without an explicit `--skip-*` is FATAL. (b) Runtime emitters (telemetry wrapper, webhook POST, session-resume observability probe) MUST fail SAFE — always `exit 0`, never block a session. A runtime emitter with a non-zero exit on a normal failure path is a regression. (c) A fail-SAFE reader (exit 0, empty output) feeding a correctness gate turns 'could not read' into 'clean' — for every gate name the reader it consumes and test the empty case (stripped clone, missing ledger, absent remote branch). (d) Fail-CLOSED must be scoped to the managed roots: an unscoped `find` over a state dir refused 3 of 10 legitimate pushes under worktree churn (parallel-automate-02, 2026-10-02).
