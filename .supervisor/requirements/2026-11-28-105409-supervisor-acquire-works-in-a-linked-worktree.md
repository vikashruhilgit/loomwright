# Supervisor ACQUIRE works in a linked worktree: branch from origin/<base>, never check the base out

## Status: pending

> GitHub issue: https://github.com/vikashruhilgit/loomwright/issues/997.

## Why

On 2026-11-28 the Supervisor phase of an `/automate` run in a linked git worktree reported: "the next-step
driver failed at ACQUIRE (git checkout main is refused while main is checked out in another worktree), so
Phases 1-4 ran on the legacy path". `loomwright/scripts/supervisor-next-step.sh`, `sn_acquire` (Phase 1
step 4, the line after `git fetch -q origin "$base"`), runs `git checkout -q "$base"` and then
`git pull --ff-only`, and builds the feature branch from the local base tip. Git refuses to check out a branch
another worktree has checked out, so ACQUIRE fails in any linked worktree whose primary sits on the base.
`/automate`'s trail-gate sync has the same assumption (`sync skipped — primary checkout is on <branch>, not
main`).

## Story

**As the** owner running Loomwright from a linked worktree,
**I want** Supervisor's ACQUIRE to create (or verify) the feature branch from `origin/<base>` without checking
the base branch out,
**so that** the next-step driver runs its own path in a linked worktree instead of falling back to the
legacy one.

## Acceptance criteria

**Happy path**
- [ ] Given a linked worktree whose primary has `main` checked out, when `supervisor-next-step.sh` runs
  ACQUIRE, then it fetches `origin/main`, creates the feature branch at that commit and checks the feature
  branch out, with no `git checkout main` anywhere on the path.
- [ ] Given a primary checkout, when ACQUIRE runs, then the resulting branch, its start commit and the state
  fields written are the same as today.

**Edge cases**
- [ ] Given the feature branch already exists and equals `origin/<base>`'s tip, when ACQUIRE runs, then it is
  reused (`branch_action REUSED`), as today.
- [ ] Given the feature branch exists and diverges from `origin/<base>`, when ACQUIRE runs, then it parks
  `acquire_branch_collision` exactly as today, comparing against `origin/<base>`.

**Error scenarios**
- [ ] Given the fetch fails (offline), when ACQUIRE runs, then it compares against the last fetched
  `origin/<base>`, says so in one `base sync: fetch_failed` line as today, and never checks out the base.

## Non-goals

- Where state is written (#996).
- `/automate`'s trail-gate base sync in the primary (a separate follow-up if it bites; this story covers
  Supervisor ACQUIRE).

## Owner decisions

- 2026-11-28 (Vikash, standing rule): every defect gets a GitHub issue (#997), a linked requirement and a
  scratch-copy repro; fixes run in a later `/automate` run.

## Priority: MVP

**Rationale:** every Supervisor run in a linked worktree silently loses the next-step driver today.

## Assumptions

- Defect evidence: reproduced — 2026-11-28, in a scratch repo (`primary` on `main` plus a linked `linked`
  worktree), `git checkout -q main` inside `linked` printed `fatal: 'main' is already used by worktree at
  '…/primary'` and exited 128, the command `sn_acquire` runs. The incident was observed the same day in the
  Supervisor phase's own result block.

## Dependencies

- Depends on: none.
- Blocks: none.

## Risks

- `git pull --ff-only` on the local base goes away in favour of `origin/<base>`; anything that relied on the
  local base branch being updated by ACQUIRE has to read `origin/<base>` instead.

## Validation (must pass before merge)

1. **Static — affected suites:** `bash scripts/ci-local.sh --affected` passes, with legs that run ACQUIRE in a
   scratch linked worktree (primary on `main`) and in a primary, asserting the branch, its start commit and
   the reuse/collision paths.
2. **Running system — ACQUIRE in a linked worktree:** in a scratch repo with a local bare `origin`,
   `supervisor-next-step.sh` ACQUIRE from a linked worktree creates the feature branch at `origin/main` and
   exits 0; the output is pasted in the PR.

## Depends on
none

## Touches
loomwright/scripts/supervisor-next-step.sh
loomwright/scripts/test-supervisor-next-step.sh
loomwright/agents/supervisor.md
loomwright/docs/prompt-token-budgets.json
changelog.d
