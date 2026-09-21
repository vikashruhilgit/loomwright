# Supervisor resume defect: state.md lies about progress, making `--continue` destructive

## Problem
A Supervisor run that dies between EXECUTE and FINALIZE leaves `.supervisor/state.md` claiming work
that is complete is still pending. Observed 2026-07-27 during the FABLE_PARITY_EVAL arm-2 run
(`ntfs-tool`, session `sup-2026-07-27-tree-and-find`):

- **Reality:** all 5 subtasks implemented, reviewed PASS, and merged into
  `feature/tree-and-find-shared-walker` (`52944d1`, 8 files, +1623/−4); worktrees cleaned.
- **`state.md` said:** `status: running`, `phase: ACQUIRE`, and every subtask row `PENDING`.

Context-Keeper never advanced the state past the ACQUIRE write. So `/supervisor --continue` would
load a valid-but-false state and **re-execute the entire job** — re-creating worktrees and
re-implementing five subtasks whose work is already merged on the branch. The v15.3.0 resume
validation gate does not catch this: the state is schema-*valid* (closed `phase`/`status` enums
satisfied, branch verifiable), it is merely **wrong**. Fail-closed validation defends against
malformed state, not against stale state.

This is worse than "resume unavailable". An operator following the documented recovery path
(`/supervisor --continue task: …`) gets silent duplicate execution, and on a repo where subtask
branches were already deleted, likely a merge mess on top.

## Goal
A resume that either reconstructs true progress from ground truth, or refuses — never one that
proceeds on a stale belief.

## Scope
1. **Reproduce deterministically.** A test that drives Supervisor to post-EXECUTE, kills it before
   FINALIZE completes, and asserts `state.md` disagrees with `git log`. Without a repro this stays
   anecdotal.
2. **Find why the writes stop.** Establish whether Context-Keeper is never *invoked* after ACQUIRE
   on this path, is invoked and fails silently, or is invoked only on a phase transition that
   FINALIZE never reached. Name the mechanism — the fix differs per cause. Note the inline
   main-thread Supervisor is permitted a best-effort direct write of the `## Session` block, so
   check both writers.
3. **Ground-truth reconciliation at resume.** Before consuming state, reconcile each subtask
   against observable reality — merge commits on the feature branch, subtask branch existence,
   `git branch --contains` — exactly as `automate-loop` §4 reconciles a run file against `gh`/`git`.
   The precedent exists in this codebase; apply it here. A subtask whose merge commit is present is
   DONE regardless of what the file claims.
4. **Fail closed on unreconcilable divergence.** Where truth cannot be established, refuse with a
   distinct error (`resume_state_stale`, separate from `resume_state_invalid`) naming the specific
   disagreement, rather than proceeding.
5. **Checkpoint on subtask completion, not only on phase transition.** If the cause is
   transition-only writes, a mid-phase crash will always lose everything since the last boundary.

## Non-goals
- Not redesigning Context-Keeper's writer contract or the sole-writer invariant.
- No new gates on the happy path; this is recovery-path only.
- Not fixing the separate headless finding (Supervisor's background-dispatch pattern cannot
  complete under `claude -p`) — related discovery, different defect, own requirement.

## Acceptance criteria
- A test reproduces the divergence and fails before the fix.
- Resume reconciles subtask status against git ground truth; a merged subtask is never re-executed.
- Unreconcilable divergence refuses with `resume_state_stale` and names the disagreement.
- The documented recovery path in CLAUDE.md §"Supervisor workflow interrupted?" is corrected — it
  currently presents `--continue` as safe without qualification.
- Existing resume tests still pass.

## Outcomes Rubric
- Deterministic repro of stale-state divergence, failing pre-fix
- Root cause named (which writer, which path, why it stops) — not just symptom-patched
- Resume reconciles against git ground truth before trusting any subtask row
- Distinct fail-closed error for stale-but-valid state
- CLAUDE.md recovery guidance corrected in the same change

## Provenance
Found 2026-07-27 by accident, while running FABLE_PARITY_EVAL arm 2 for twin-remediation item 07.
Recorded in `loomwright/docs/SPIKES/FABLE_PARITY_EVAL.md` §Results (arm-2 blocked note).
