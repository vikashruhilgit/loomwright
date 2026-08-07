---
name: agent-help-phase-drift
description: agent-help.md carries Supervisor phase enumerations that the doc-currency CI gate does NOT check — a recurring integration-review-only drift surface
metadata:
  type: project
---

`ai-agent-manager-plugin/commands/agent-help.md` contains two Supervisor phase enumerations: a one-liner (`INIT → ACQUIRE → PLAN → EXECUTE → FINALIZE → SELF_HEAL → LOOP`) and an ASCII "N-Phase Workflow" box. When a new Supervisor phase is added (e.g. Phase 1.5 PRE-FLIGHT SYNC in v14.8.0), these two lists must be updated alongside supervisor.md / commands/supervisor.md / README / CLAUDE.md.

**Why:** `scripts/check-doc-currency.sh` scans only version/count claims, NOT phase enumerations. So a stale phase list in agent-help.md passes CI green and is visible ONLY in an integrated consistency audit. In the v14.8.0 preflight-sync feature, the brief's File Impact Map did not list agent-help.md as a phase-list target (only as a version-bump target), so both phase enumerations were left stale while every other surface gained Phase 1.5.

**How to apply:** During any `consistency_audit` that touches the Supervisor prompt or adds/removes a phase, grep agent-help.md for `INIT → ACQUIRE` and `Phase Workflow` and confirm the new phase appears. Flag omissions as `drift` / `drift_kind: workflow` (HIGH-eligible). Cross-check against [[mirrored-prompt-and-workflow-surfaces]] if that memory exists.
