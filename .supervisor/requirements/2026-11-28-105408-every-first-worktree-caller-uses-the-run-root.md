# Every other first-worktree caller uses the run root

## Status: open

> GitHub issue: https://github.com/vikashruhilgit/loomwright/issues/996. Part A2 of 2. Part A1:
> `2026-11-28-105407-one-run-root-state-logs-and-ledger-follow-the-run-not-the-first-worktree.md`.

## Why

Part A1 makes a run's state, logs, ledger and run lock follow the run's checkout through one resolver. The
rest of the scripts that read `git worktree list --porcelain`'s first entry still pin to the primary. On
2026-11-28 `automate-helpers.sh meta-entry` (`automate-helpers.d/meta.sh`, `_meta_root`), run from a linked
worktree, pulled the metadata branch into the owner's primary checkout instead of the worktree the run lived
in. The other callers at origin/main `9a6a850`: `meta-sync.sh` (default `--root`), `automate-trail.d/closeout.sh`,
`automate-trail.d/sweep.sh`, `automate-lanes.d/park-leaks.sh`, `janitor-report.sh`, `worktree-audit.sh`,
`guard-arm.sh`, `host-mode.sh`, `session-resume.sh`, `send-telemetry.sh`, `notify-desktop.sh`,
`migrate-branch-mode.sh`, `propose-domain.sh` and `prove-rule-check.sh`.

## Story

**As the** owner running Loomwright from a linked worktree,
**I want** every remaining script that today picks the first listed worktree to use Part A1's run root,
**so that** nothing a run does in one checkout reaches into another.

## Acceptance criteria

**Happy path**
- [ ] Given a run in a linked worktree, when `automate-helpers.sh meta-entry` runs with no `--root`, then it
  pulls into that worktree, not the primary.
- [ ] Given each script listed in Touches, when it runs from a linked worktree that holds a run, then it acts
  on that worktree's `.supervisor/` (or reports on it), never another checkout's.
- [ ] Given scripts whose job is to list every worktree (`janitor-report.sh`, `worktree-audit.sh`,
  `automate-trail.d/sweep.sh`, `automate-lanes.d/park-leaks.sh`), when they run, then they still list all
  worktrees; only the "which checkout is mine" answer changes.

**Edge cases**
- [ ] Given a run in the primary checkout, when any of these scripts runs, then its behaviour is unchanged.
- [ ] Given `git grep` over `loomwright/scripts/` (tests excluded), when this lands, then the only reader of
  the first porcelain entry is Part A1's resolver, and a static check pins it.

**Error scenarios**
- [ ] Given the resolver cannot decide (no run and no worker link), when a script needs a root, then it uses
  the current checkout's own toplevel and never the first listed worktree.

## Non-goals

- The resolver itself and the state/log/ledger writers (Part A1).
- Changing what meta-sync syncs, or the lanes' own clone layout.

## Owner decisions

- 2026-11-28 (Vikash, PO-ASSUME): root = the run's checkout (see Part A1).
- 2026-11-28 (Vikash, standing rule): issue #996, linked requirement, scratch repro, later `/automate` run.

## Priority: Phase 2

**Rationale:** Part A1 stops the state overwrite; this part removes the remaining cross-checkout reaches
(the metadata pull into the primary was observed, the others follow the same pattern).

## Assumptions

- Defect evidence: observed — 2026-11-28, `meta-entry` with no `--root`, run in the linked worktree
  `yellowtail`, printed `meta-entry: pulled loomwright-meta` and updated the primary checkout's managed files.
  `meta-entry --root "$PWD"` was needed to pull into the worktree itself.
- Part A1's resolver is callable from every script here.

## Dependencies

- Depends on: Part A1.
- Blocks: none.

## Risks

- `meta-sync.sh` is used by the owner by hand; changing its default root changes a habit. The default stays
  the primary when run there.

## Validation (must pass before merge)

1. **Static — affected suites:** `bash scripts/ci-local.sh --affected` passes, with a static check that only
   the resolver reads the first porcelain entry, and legs that run `meta-entry` from a scratch linked worktree.
2. **Running system — meta-entry in a linked worktree:** in a scratch repo with a local bare `origin` carrying
   a metadata branch, `automate-helpers.sh meta-entry` run in a linked worktree writes the managed files there
   and nothing in the primary; the output is pasted in the PR.

## Depends on
2026-11-28-105407-one-run-root-state-logs-and-ledger-follow-the-run-not-the-first-worktree.md

## Touches
loomwright/scripts/automate-helpers.d/meta.sh
loomwright/scripts/meta-sync.sh
loomwright/scripts/automate-trail.d/closeout.sh
loomwright/scripts/automate-trail.d/sweep.sh
loomwright/scripts/automate-lanes.d/park-leaks.sh
loomwright/scripts/janitor-report.sh
loomwright/scripts/worktree-audit.sh
loomwright/scripts/guard-arm.sh
loomwright/scripts/host-mode.sh
loomwright/scripts/session-resume.sh
loomwright/scripts/send-telemetry.sh
loomwright/scripts/notify-desktop.sh
loomwright/scripts/migrate-branch-mode.sh
loomwright/scripts/propose-domain.sh
loomwright/scripts/prove-rule-check.sh
changelog.d
