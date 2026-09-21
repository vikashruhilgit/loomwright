# 02 — One writer for progress state, derived state.md (Fix 3, D5)

## Problem
Progress is recorded by SIX prompt-instructed mechanisms. Measured adherence: 560 hook-written
`token_ledger` events vs 6 agent-written `phase_transition` events across 11+ sessions. Observed
consequence: state.md read `phase: ACQUIRE`/all-PENDING while all 5 subtasks were merged —
`--continue` would have re-executed the whole job. The read-side guard shipped
(`scripts/reconcile-resume-state.sh`, PR #110); it detects the lie but does not stop it being
written. Prior art: `.supervisor/requirements/one-writer-derived-state.md` (fold in, then retire).

## Goal
State never lies because nothing that can lie is left writing it.

## Scope
1. **One writer, and it is a hook:** extend the SubagentStop/worker hook to append one
   `subtask_complete` event to the session JSONL — modelled on `emit-token-ledger.sh` (fail-safe,
   always exit 0). Payload shape is `last_assistant_message` + `agent_transcript_path`, NOT
   `result_block` — verify empirically.
2. **`state.md` becomes derived** — projected from the append-only log on demand. Append-only has
   no write conflicts, sidestepping (not fighting) the Context-Keeper sole-writer contract.
3. **DELETE the other five mechanisms** (~200 prompt lines across supervisor.md,
   execute-manager.md, context-keeper.md, state-management/SKILL.md). Deprecating is not enough —
   a surviving instruction re-introduces the miss rate.
4. **Prove it:** re-run the event-count measurement after the change.

## Non-goals
Do not patch any gap by adding another "write your state" instruction (explicit anti-pattern from
the resume-state incident). No change to the resume reconciler (already shipped, stays as
defense-in-depth).

## Acceptance criteria
- Hook-written `subtask_complete` events appear for every worker completion; hook is always-exit-0.
- `state.md` regenerable from the log; `--continue` works against derived state.
- Zero remaining prompt instructions telling an agent to write progress state (grep-verified).
- Post-change measurement recorded in the PR.

## Outcomes Rubric
- Hook writer shipped, fail-safe
- state.md derived, resume-compatible
- Five prompt mechanisms deleted, not deprecated
- Adherence measurement re-run and recorded

## Status: brief-shipped

Job `.supervisor/jobs/done/2026-07-28-one-writer-derived-state.md` completed (reconciled from the job lifecycle, not self-reported).
Acceptance criteria are NOT machine-verified here — review them before promoting this to `## Status: done`.
