---
name: attack-failclosed-vs-failsafe-split
description: This plugin's failure philosophy is bimodal — correctness gates fail CLOSED, side-effect emitters fail SAFE; attack any deviation as a security regression
metadata:
  type: project
---

This plugin's failure philosophy is intentionally bimodal. Attack any deviation as a security regression.

**Why:** Correctness gates and side-effect emitters have opposite correct postures; inverting either flips the security posture silently.

**How to apply:** (a) CI / `--non-interactive` / stdin-not-tty correctness gates MUST fail CLOSED — `preflight-sync-gate` aborts with `preflight_overlap_detected`, autonomous loop aborts with `non_interactive_without_fallback`, rubric gate aborts with `rubric_gate_closed_non_interactive`. A gate that silently proceeds under automation without an explicit `--skip-*` is FATAL. (b) Runtime emitters (telemetry wrapper, webhook POST, session-resume observability probe) MUST fail SAFE — always `exit 0`, never block a session. A runtime emitter with a non-zero exit on a normal failure path is a regression.
