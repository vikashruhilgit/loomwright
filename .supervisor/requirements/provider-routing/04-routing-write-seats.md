# 04 — Provider routing for write seats (worker, heal fix, drain fix) — STUB

## Status: proposed (stub — depends on 03 shipping and on which providers item 02 found permission-pinnable; rewrite premises then promote)

**As a** maintainer, **I want** to let a non-Claude CLI implement a subtask or apply a fix, **so that** I can use the
model I prefer for code changes — while the plugin, not that CLI, decides whether the work counts and who pushes it.

## Intended shape (to be re-verified, not built from this text)

- **Seats:** `worker`, Phase 4.5 `heal_fix`, drain `drain_fix` (the `routing.seats` keys from 03).
- **Eligibility:** only providers whose 02 verdict is `usable for write seats` (permissions pinnable). Any other provider
  configured for a write seat is refused at config time with a named status.
- **Where:** the provider runs in the worktree Supervisor already creates for the subtask; credentials stripped
  (`env -i`, as `lens-run.sh` does); it never pushes — Supervisor alone commits/pushes/opens the PR.
- **What counts:** the provider's own "done" claim is ignored; the existing disk gate (`verify-provides.sh` /
  `outputs_verified`), tests/lint and Phase 4.5's integrated review decide, exactly as for a Claude worker.
- **Consent:** same user-scoped per-repo grant as 03; write seats need an explicit separate grant (`write: true`).
- **Failure:** provider unavailable/timeout ⇒ the subtask fails through the existing worker-failure path
  (`docs/FAILURE_ESCALATION.md`), or falls back to Claude when `on_unavailable` is `fallback_to_default`.

## Open questions for the owner (answer before promoting)
- Allow mixed workers in one run (some Claude, some Grok), or one provider per run?
- Should the heal/drain fix seat default to the same provider as the worker?

## Depends on
03-routing-config-readonly-seats.md

## Touches
unknown
