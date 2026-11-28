# One run root: state, logs and ledger follow the run's checkout, not the first listed worktree

## Status: pending

> GitHub issue: https://github.com/vikashruhilgit/loomwright/issues/996. Part A1 of 2. Part A2:
> `2026-11-28-105408-every-first-worktree-caller-uses-the-run-root.md`.

## Why

On 2026-11-28 an `/automate` run lived in a linked git worktree (created by the host, not by Supervisor), with
its run file in that worktree's `.supervisor/automate/`. Its Supervisor phase (session `ca644240…`) read
`.supervisor/state.md` from the **primary** checkout, which held a different run's 2026-11-21 Worker
Results. That made its finalize gate report an unsettled child, and it replaced that file with its own state
(09:55 IST: `session_id: ca644240…`, `branch: main`, `status: failed`). Another run's state was overwritten.

Cause: the state, log and ledger writers pin their root to the first `git worktree list --porcelain` entry,
never `$PWD`: `build-state.sh`'s `MAIN_ROOT=` block ("never `$PWD`, never a $PWD fallback"),
`emit-progress-event.sh`, `emit-token-ledger.sh`, `emit-agent-identity.sh`, `emit-lifecycle.sh`,
`reproject-state-on-terminal.sh`, `seed-run-owner.sh`, `loom-log-owner.sh`, `close-stranded-run.sh`,
`read-token-ledger.sh` and `run-lock.sh`. That anchoring exists so Supervisor's worker worktrees report into
the run's checkout. But `/automate` keeps its run file in its own checkout, so a run started in a linked
worktree has two roots.

## Story

**As the** owner running Loomwright from a linked worktree (a host such as Orca creates one per task),
**I want** a run's state, logs, token ledger and run lock to live in the checkout where the run started,
**so that** a run never reads or overwrites another checkout's run state, and Supervisor's worker worktrees
still report to the run that created them.

## Acceptance criteria

**Happy path**
- [ ] Given a run started in a checkout (primary or linked), when any state, log, ledger, identity or
  run-lock writer listed in Touches runs from that checkout, then it writes under that checkout's
  `.supervisor/`, and nothing under any other checkout's `.supervisor/`.
- [ ] Given Supervisor creates a worker worktree for a subtask, when a writer runs from inside that worker
  worktree, then it writes under the run's checkout (the one that created the worktree), as today for a run
  in the primary. The link is recorded when the worktree is created, never inferred from list order.
- [ ] Given one resolver for "the run root" (a single function or script every writer in Touches calls),
  when the writers are grepped, then none of them reads `git worktree list --porcelain`'s first entry
  directly.

**Edge cases**
- [ ] Given a run in the primary checkout, when it runs end to end, then every path it writes is
  byte-for-byte the same as today (no behaviour change for the common case).
- [ ] Given a linked worktree with no run started in it and no worker-worktree link, when a hook fires there,
  then the writer resolves that worktree's own root (fail toward the local checkout, never toward another one).

**Error scenarios**
- [ ] Given a worker-worktree link that names a checkout that no longer exists, when a writer runs, then it
  writes nothing and logs one named line (fail-safe, exit 0, as these emitters do today).

## Non-goals

- The other first-worktree callers (meta-sync default root, the trail, lanes, sweep, janitor, guard-arm,
  host-mode, session-resume, telemetry): Part A2.
- The Supervisor ACQUIRE checkout failure in a linked worktree (#997).
- Recovering the overwritten 2026-11-21 state.md (a backup is in that session's scratchpad).

## Owner decisions

- 2026-11-28 (Vikash, PO-ASSUME): the rule is "root = the run's checkout": the checkout where the run started
  is the one root; Supervisor marks each worker worktree it creates with that root; nothing pins to the
  first listed worktree any more.
- 2026-11-28 (Vikash, standing rule): every defect gets a GitHub issue (#996), a linked requirement and a
  scratch-copy repro; fixes run in a later `/automate` run.

## Priority: MVP

**Rationale:** a run in a linked worktree overwrote another run's state on 2026-11-28; every host that runs
tasks in worktrees hits this.

## Assumptions

- Defect evidence: reproduced — 2026-11-28, in a scratch repo (`primary` on `main` plus a linked `linked`
  worktree), piping a SubagentStop payload into `emit-progress-event.sh` (origin/main `9a6a850`) from inside
  `linked` wrote `primary/.supervisor/logs/cc-uuid-1.jsonl` and nothing under `linked/.supervisor/`. The
  incident was observed the same day (`state.md` mtime 09:55 IST, the Supervisor phase's own result block).
- Supervisor creates worker worktrees in a known place (`agents/execute-manager.md`'s `git worktree add`
  steps), so it can write the link at creation.

## Dependencies

- Depends on: none.
- Blocks: Part A2 (it reuses the resolver).

## Risks

- Every hook-fired emitter changes its root logic. A test that runs each one from a primary, from a linked
  worktree and from a worker worktree is the guard.
- Host mode (`host-mode.sh`) moves state to a host directory; the resolver must give the same answer it
  does today when host mode is on.

## Validation (must pass before merge)

1. **Static — affected suites:** `bash scripts/ci-local.sh --affected` passes, with new legs that run each
   writer in Touches from a primary, a linked worktree and a Supervisor worker worktree in scratch repos and
   assert where it wrote.
2. **Running system — the incident replayed:** in a scratch repo (primary on `main` plus a linked worktree),
   the `emit-progress-event.sh` pipe above writes under `linked/.supervisor/logs/` and nothing under
   `primary/.supervisor/`; the command and output are pasted in the PR.

## Depends on
none

## Touches
loomwright/scripts/build-state.sh
loomwright/scripts/emit-progress-event.sh
loomwright/scripts/emit-token-ledger.sh
loomwright/scripts/emit-agent-identity.sh
loomwright/scripts/emit-lifecycle.sh
loomwright/scripts/reproject-state-on-terminal.sh
loomwright/scripts/seed-run-owner.sh
loomwright/scripts/loom-log-owner.sh
loomwright/scripts/close-stranded-run.sh
loomwright/scripts/read-token-ledger.sh
loomwright/scripts/run-lock.sh
loomwright/scripts/run-root.sh
loomwright/agents/execute-manager.md
loomwright/docs/ARCHITECTURE_CONTRACTS.md
loomwright/docs/prompt-token-budgets.json
changelog.d
