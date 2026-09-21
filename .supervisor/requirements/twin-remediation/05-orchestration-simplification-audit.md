# 05 — Orchestration simplification audit (propose-only, human-gated)

## Problem
The delivery pipeline itself is now a major source of the churn the Twin exists to reduce: dual until-mergeable dispatch paths (step 5.5 + PostToolUse hook) reconciled by markers, drain worktree isolation, /automate single-drain ownership with config-backup choreography, the 4-PR drain saga (#67/#70/#71/#72), and a family of operational gotchas in memory (drain dies before CI settles, TTY false positives, concurrent-heal sweeps). North star: "be ruthless about existing surface" — applied to skills (stackpack) but never to the orchestration layer.

## Goal
A read-only, evidence-based audit that proposes concrete simplifications/cuts — the orchestration counterpart of the grounded skills-bloat finding. PROPOSE ONLY: every cut is a separate follow-up decision; this item merges a report, not behavior changes.

## Scope
1. **Usage evidence:** mine `.supervisor/logs/`, dispatch markers, worktrees.log, and postmortem data: how often did each mechanism (hook-path dispatch vs step 5.5, detached drain vs inline, /automate, sdk-spike, stacked-branch mode, multi-voter heal, red-team lens) actually fire, succeed, and fail over the recorded history? Use item 01's script output where it exists.
2. **Complexity-vs-value table:** per mechanism — invariants it requires, incidents it caused (cite memory/postmortem), incidents it prevented, opt-in vs default, and a keep / simplify / deprecate recommendation. Specific hypotheses to test, not presume: (a) collapse the dual dispatch paths to one; (b) retire or graduate sdk-spike (live verification still PENDING — an unverified quarantine is standing surface); (c) whether stacked-PR default earns its merge-order burden at observed iteration counts; (d) whether the detached drain should default to inline given the die-before-CI-settles failure mode.
3. **Deliverable:** `loomwright/docs/SPIKES/ORCHESTRATION_SURFACE_AUDIT.md` + one follow-up requirement file per recommended cut (not executed here).

## Non-goals
No behavior changes, no invariant changes, no deletions in this item. Do not touch the sanctioned-merge-executor invariant.

## Acceptance criteria
- Every keep/simplify/deprecate verdict cites concrete fire/success/failure counts from real logs (or explicit `insufficient_data` — never asserted from the mechanism's own docs; read-before-write rule applies).
- The four named hypotheses each get an evidence-based verdict.
- Follow-up requirement stubs written for each deprecation recommendation.

## Outcomes Rubric
- Evidence table covers all listed mechanisms with real counts
- Four hypotheses adjudicated with cited data
- Zero behavior changes in the PR
- Follow-up stubs exist for every recommended cut
