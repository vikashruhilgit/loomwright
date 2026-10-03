# 01 — Single-agent default + fan-out threshold (Fix 1, D3)

## Problem
Three rules combine to guarantee fan-out with nothing opposing them (all `file:line`-cited in
`EVAL_FINDINGS_AND_FIXES.md` Fix 1): `supervisor-readiness/SKILL.md:359` "map each criterion to
exactly one subtask" manufactures subtasks; orchestrator.md (×5) doubles them with mandatory paired
review; the fast path (`supervisor.md:216,253`) needs ≤1 subtask so it is unreachable for any
multi-criterion requirement. No phase anywhere asks "could one agent do this?" Measured cost: 6.4×
and 4× wall clock vs bare Claude for the same 0-defect outcome. `--sequential` does NOT fix it — it
still pays all cold starts.

## Goal
Small tasks cost bare-Claude money: one agent reads the codebase once, implements everything, gets
one integrated review. Fan-out survives above a stated threshold as insurance.

## Scope
1. **Invert the decomposition default** (Launch Pad + Orchestrator — they decide subtask count;
   Supervisor only executes): default to ONE subtask; split only for a stated concrete reason
   (same-file conflict between subtasks, work exceeds one context, genuine parallelism). Acceptance
   criteria become a checklist for one worker, not a subtask generator.
2. **Add a true single-agent path:** one worker executes all criteria in one context, then ONE
   review of the integrated result. This path does not exist today in any mode.
3. **Threshold, not removal:** fan out above a bound (file count / estimated context / detected
   file conflicts); stay single-agent below it. Keep the deterministic per-subtask gate
   (`outputs_verified`) + tests/lint on the branch as the zero-token safety net below the threshold.
4. Sync every restating surface (commands/*.md prose, skills, ARCHITECTURE_CONTRACTS) in the same
   change — check-command-sync does not cover Parameters-table prose.

## Non-goals
No review-pass changes beyond what the single-agent path implies (that is item 04). No deletion of
worktree/Execute Manager machinery — it remains the above-threshold path.

## Acceptance criteria
- A multi-criterion requirement with no stated split reason produces 1 subtask end-to-end.
- The threshold and its inputs are written down in one place and cited by Launch Pad + Orchestrator.
- Above-threshold behavior unchanged (existing tests/CI gates green).
- Verification plan recorded: re-run arm 2 on tree-and-find (same base 5df1ded) targeting
  arm-1-like cost/wall-clock while retaining plan review, PR, and the doc-drift catch.

## Outcomes Rubric
- Decomposition default inverted with stated-reason rule
- True single-agent path exists and is the default below threshold
- Threshold documented + cited by both deciding agents
- All restating surfaces synced in the same PR

## Status: done
