# Stranded-brief residual gaps — the three consumers still lied to, and the missing `## Outcome`

> Provenance: found 2026-09-01 while inspecting worktrees after shipping v15.39.0
> (`reconcile-jobs.sh`, PR #161). The analysis below is largely **recovered from an
> abandoned earlier attempt** dated 2026-08-03, still sitting uncommitted in the worktree
> `.claude/worktrees/busy-darwin-7b336a` as `reconcile-inprogress-jobs.sh` (344 lines) +
> `test-reconcile-inprogress-jobs.sh` (363 lines). That worktree is deliberately RETAINED —
> it is the only copy. Every claim below was re-verified against `main` at `8b8ef70`,
> not carried over on trust.

## Problem

v15.39.0 fixed the brief-move strand, but only partly. Three residual gaps remain.

### Gap 1 — three consumers still read a stranded brief as "Supervisor is active"

The completion tail's `in-progress/` → `done/` move is prompt-instructed, so a strand is
always possible. v15.39.0 made **one** consumer honest (`session-resume.sh`). Three others
still treat a non-empty `in-progress/` as a live run (verified on `main` 2026-09-01):

- `loomwright/scripts/hook-dispatch-on-pr-create.sh:163` [pins: `[ -d .supervisor/jobs/in-progress ]`] — session-scope gate condition (i)
- `loomwright/scripts/notify-desktop.sh:79` [pins: `compgen -G ".supervisor/jobs/in-progress/*.md"`] — "Supervisor is active"
- `loomwright/scripts/send-webhook.sh:288` [pins: `PLUGIN_CONTEXT=1`] — plugin-context gate

**Partially mitigated, not closed.** `reconcile-jobs.sh --repair` clears the strand at
source, which fixes all four consumers at once. But an `unknown`-classified strand is
never repaired by design, and for those three of the four remain wrong.

### Gap 2 — briefs land in `done/` with no `## Outcome` block

Appending `## Outcome` is completion-tail step 2's second half and has **no reconciler**.
The abandoned attempt measured 6 of 73 on 2026-08-03. Re-measured 2026-09-01: **12 of 88**.
Live and growing, not historical. Consequence: a brief in `done/` may carry no PR, no heal
decision, and no outcome at all, so post-hoc analysis over `done/` silently under-reports.

### Gap 3 — an unratified second writer to `.supervisor/jobs/`

`docs/ARCHITECTURE_CONTRACTS.md:145` [pins: `Supervisor remains the sole writer`] states
Supervisor is the sole writer of `.supervisor/jobs/`. `reconcile-jobs.sh --repair`
(v15.39.0) writes there, making it a second writer. The 2026-08-03 attempt cited exactly
this sentence as its reason to stay **detect-only**.

Two honest counterweights, recorded so this is not re-litigated from scratch:
1. That sentence sits in an autonomous-loop scoping paragraph and is **already loose** — it
   names `state.md` as Supervisor-sole-write too, yet `build-state.sh` writes `state.md`.
2. `--repair` is opt-in, evidence-gated, and never touches an `unknown` brief.

**But the resolution taken in v15.39.0 was to edit the State Ownership table to list the
new writer** — i.e. the doc was changed to match the code, without the tradeoff being put
to a human. That is the part worth revisiting, more than the behaviour itself.

## Goal

Close gaps 1 and 2 mechanically, and settle gap 3 as an explicit decision rather than a
side effect of a doc edit.

## Non-goals

- **No change to the completion tail.** It is prompt-instructed; an instruction cannot be
  made atomic against the agent dying before it is read. Reconciliation remains the shape.
- No new advisory store, no new hook entry.
- Not a rewrite of `reconcile-jobs.sh` — gaps 1 and 2 are additive to it.

## Acceptance criteria

- [ ] Given a brief stranded in `in-progress/` that a reconciler classifies as stranded,
      when `hook-dispatch-on-pr-create.sh`, `notify-desktop.sh` and `send-webhook.sh`
      evaluate their "Supervisor is active" condition, then it does NOT read as active —
      and each has an executed assertion proving it, with a control proving a genuinely
      active run still does.
- [ ] Given a brief in `done/` with no `## Outcome` block, when the reconciler runs, then
      the omission is reported; and any block it writes states which fields were not
      recoverable rather than inventing them (mirroring the v15.39.0 convention).
- [ ] The `done/`-without-`## Outcome` count is measured before and after, and the measured
      figures are recorded — the 12-of-88 baseline must not be restated from this file
      without re-measuring.
- [ ] Gap 3 is resolved by an explicit written decision (ratify the second writer in
      CLAUDE.md, or demote `--repair` to detect-only), NOT by editing a table to match code.
- [ ] The abandoned `reconcile-inprogress-jobs.sh` is read before implementing, and any
      case it covers that the shipped script does not is either adopted or explicitly
      declined with a reason.
- [ ] Every new mechanism is mutation-verified: reverting it fails exactly its own cases.

## Outcomes Rubric

- The three consumers are provably no longer misled by a stranded brief (executed, not argued).
- The missing-`## Outcome` gap is measured, reported, and its baseline re-derived not copied.
- Gap 3 carries a dated human decision with its reasoning.
- No new claim that no check backs.
