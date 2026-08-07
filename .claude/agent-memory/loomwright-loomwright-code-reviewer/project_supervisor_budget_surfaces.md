---
name: supervisor-budget-surfaces
description: Supervisor tool-call budget/zone numbers are restated in 9+ surfaces; preloaded skills, FAILURE_ESCALATION.md and IMPROVEMENTS_ROADMAP.md are NOT covered by doc-currency CI and drift silently
metadata:
  type: project
---

The Supervisor tool-call budget (and GREEN/YELLOW/RED zone thresholds) is restated in: agents/supervisor.md (Critical Rules ~40, diagram ~76, budget tables ~1190-1215, Phase 3/4.5/5 status lines), commands/supervisor.md (~97, ~250, ~257-259), commands/agent-help.md (~228), docs/ARCHITECTURE.md, docs/ARCHITECTURE_CONTRACTS.md, docs/FAILURE_ESCALATION.md (~129), docs/IMPROVEMENTS_ROADMAP.md (~350, ~354 — "What's happening now" items state budget + maxTurns as current facts), skills/workflow-management/SKILL.md, skills/context-summarization/SKILL.md. The two skills are PRELOADED into the Supervisor at spawn, so stale numbers there are runtime contradictions, not just doc drift.

**Why:** the June 2026 30→50 budget sweep (second round) fixed all listed surfaces EXCEPT IMPROVEMENTS_ROADMAP.md — check-doc-currency.sh does not scan budget numbers, so CI stayed green both rounds.

**How to apply:** in any consistency audit where a budget/zone/token number changes, grep ALL of the above paths for the old value — do not trust the diff or CI to have found every surface. Related: [[entry-points-gate-blindspot]], [[half-fixed-example-classes]].
