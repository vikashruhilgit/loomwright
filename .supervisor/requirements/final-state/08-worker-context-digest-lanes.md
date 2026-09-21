# 08 — Worker shared-context digest + explicit file lanes (D6)

## Problem
Each spawned worker cold-starts with an empty context and re-reads the same files — that
re-acquisition, not prompt overhead, is where the measured 6.4× goes. Launch Pad already computes
file-impact analysis and then throws it away instead of handing it to workers. Workers also lack
explicit ownership boundaries, so siblings can impact each other's work (divergent-interface
incident: ST-1/ST-2 shipped conflicting flag shapes for the same concept because neither could see
the other's worktree).

## Goal
Above-threshold fan-out (post item 01) where every worker starts warm and stays in its lane.

## Scope
1. **Per-job context digest:** Launch Pad's codebase analysis + file-impact output persisted as a
   bounded artifact the Supervisor hands each worker as a pointer (pointer-not-payload per
   POINTER_AUDIT conventions): relevant files, interfaces touched, conventions, sibling-subtask
   summary.
2. **Explicit lanes:** each subtask declares its owned files/interfaces; workers instructed (and
   the deterministic gate extended to verify) that only owned paths are touched; cross-lane
   contracts (producer/consumer shapes) stated in the digest so ST-1/ST-2-style divergence is
   caught at spawn, not at Phase 4.5.
3. **Carrier is the SDK runner** where active (it composes per-spawn prompts); the Task-spawn path
   gets the same digest via the existing spawn-contract pointer shape.

## Non-goals
No cross-worker live communication; no shared mutable state between worktrees.

## Acceptance criteria
- Digest artifact produced per job, bounded, pointer-handed to every worker on both spawn paths.
- Lane declaration in briefs; out-of-lane writes flagged by the existing outputs_verified gate.
- Re-run measurement: worker re-read volume (or cost proxy) down vs the arm-2 baseline.

## Outcomes Rubric
- Digest shipped on both spawn paths
- Lanes declared + mechanically checked
- Cross-lane contracts stated in digest
- Before/after cost or re-read measurement recorded

## Status: brief-shipped

Job `.supervisor/jobs/done/2026-07-31-worker-context-digest-lanes.md` completed (reconciled from the job lifecycle, not self-reported).
Acceptance criteria are NOT machine-verified here — review them before promoting this to `## Status: done`.

### Owed against this requirement (do not close without these)

1. **AC3 — the measurement was NOT taken.** "Re-run measurement: worker re-read volume (or cost
   proxy) down vs the arm-2 baseline" is unmet, deferred by owner decision at the Phase 2.5 gate
   (~$60 multi-session operator-run eval on an external repo). This is the requirement's *premise*,
   not a trailing nice-to-have: the problem statement asserts re-acquisition is where the measured
   6.4x goes, and nothing shipped tests that causal claim. Recorded as an expected rubric FAIL
   (3/4), not laundered into a pass.
2. **AC2 shipped as "record", not "verify".** The AC says out-of-lane writes are "flagged by the
   existing outputs_verified gate"; `out_of_lane` is instead a separate REPORT-ONLY field (correct
   call — folding it into `outputs_gap` would break that field's status biconditional), and
   collision escalation exists ONLY on the parallel Execute-Manager path. It is vacuous on the
   Single-Agent path (the post-Fix-1 DEFAULT) and record-only on the Sequential path.
3. **Scope item 2 unmet: divergence is still not caught at spawn.** The motivating ST-1/ST-2
   incident is two subtasks independently inventing different shapes for the same concept while
   each stays inside its own declared lane — that yields `out_of_lane: []` for both, fires no
   collision, and surfaces at Phase 4.5. Criterion 16 catches *declared* lane overlap at brief
   time (real value) but cannot catch this. A cross-lane contract check over the MERGED diff
   ("do siblings define conflicting shapes for the same `provides` name?") is the missing piece.
