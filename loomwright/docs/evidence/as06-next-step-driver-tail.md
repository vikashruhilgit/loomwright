# Evidence — automate-speed/06: the next-step driver takes over the loop's tail

Source requirement: `.supervisor/requirements/automate-speed/06-next-step-driver-tail.md`.
Driver: `loomwright/scripts/automate-next-step.sh`. Suite: `loomwright/scripts/test-automate-next-step.sh`. Per-case
drive files: `loomwright/scripts/fixtures/automate-golden/<case>/next-step.results`. Instruction schema:
`loomwright/docs/result-schemas/automate-run.md` §"next-step instruction". Base commit `142540b`. macOS; `bash` on
`PATH` is 5.3, and the suite also ran under `/bin/bash` 3.2.57 (`PATH="/bin:$PATH" /bin/bash
loomwright/scripts/test-automate-next-step.sh` → `PASS: 46 FAIL: 0`).

This file has two parts. Subtask 1 (the driver) recorded the before-values and the driver legs. Subtask 2 (the
prose migration) fills every line marked **AFTER — subtask 2**.

## Before / after

| Measure | Before (base `142540b`) | After |
|---|---|---|
| `wc -c loomwright/skills/automate-loop/*.md` (full glob) | `320545 total` | **AFTER — subtask 2** |
| Default-mode read set: the Step 0 **Always** files on a sequential run (`SKILL.md` 84444 + `per-item-loop.md` 106350 + `modes-and-merge-gate.md` 27163 + `invariants.md` 5900), `legacy-tail.md` excluded | `223857` | **AFTER — subtask 2** |
| Conditional Step 0 reads on a sequential run (recorded separately): `intake.md` (new run) / `resume.md` (resume) | `10379` / `18852` | **AFTER — subtask 2** |
| Loop-inventory `GAP` count (`docs/loop-inventory/automate-loop.md` `## Counts`, rows 552) | `147` | **AFTER — subtask 2** |

Per-file `wc -c` at base: `SKILL.md` 84444, `branch-mode.md` 7592, `command-lanes.md` 4111, `intake.md` 10379,
`invariants.md` 5900, `lanes.md` 55754, `modes-and-merge-gate.md` 27163, `per-item-loop.md` 106350, `resume.md` 18852.

**Invariant-grep file list** (`grep -rn "<the merge command>" loomwright/ | grep -viE "no |never |not " | cut -d: -f1 |
sort -u`, the CLAUDE.md §Failure-Mode Invariants grep). The driver, its test, the schema section and this file add no
line to it:

```
loomwright/commands/agent-help.md
loomwright/docs/loop-inventory/automate-loop.md
loomwright/scripts/automate-helpers.sh
loomwright/scripts/fixtures/automate-golden/drain-superseded-by-merge/tree/dot-supervisor/requirements/automate-followups/11-post-park-lifecycle.md
loomwright/scripts/result_block_parser.py
loomwright/scripts/test-automate-helpers.sh
loomwright/skills/automate-loop/modes-and-merge-gate.md
loomwright/skills/automate-loop/per-item-loop.md
```

After (subtask 1, with the driver in place): identical. `test-automate-next-step.sh` leg S asserts it.
**AFTER — subtask 2:** the list after the prose migration.

## Validation 1 — suites (`<passed>/<total>`)

Driver-leg run (subtask 1, before the prose migration):

```
test-automate-next-step.sh   PASS: 46 FAIL: 0          46/46   (also 46/46 under /bin/bash 3.2.57)
test-automate-golden.sh      PASS: 64 FAIL: 0          64/64
test-automate-helpers.sh     RESULT: 737 passed, 0 failed   737/737
test-automate-dismissed.sh   239 passed, 0 failed      239/239
test-result-schemas-split.sh RESULT: 14 passed, 0 failed    14/14
test-automate-loop-split.sh  RESULT: 39 passed, 0 failed    39/39
test-loop-inventory.sh       RESULT: 39/39 passed      39/39   (pre-migration)
test-citation-drift.sh       citation-drift: 26 passed, 0 failed   26/26
check-doc-currency.sh        OK — all checked version/count claims match
check-token-budget.sh        OK — breaches: 0 | errors: 0
check-version-bump.sh        OK — not bumped; fragments pending (legal)
check-vendor-coupling.sh     OK — no path exceeds its declared allowance
```

**AFTER — subtask 2:** the same suites after the migration, plus `test-loop-inventory.sh` with the re-homed rows.

## Validation 2 — mutation controls (inside `test-automate-next-step.sh`)

Each mutant is gated: non-empty, differs from the driver, `bash -n` clean, and its anchor occurs exactly once.

```
ok: M2a: gate-eval skipped (direct park) ⇒ gate-eval-merge red (run file differs)
ok: M2b: an unguarded merge-command line ⇒ surface leg red
ok: MI: re-run instead of re-print ⇒ idempotency red (run file unchanged on the second call: NO — .supervisor/ changed)
ok: MQ: --non-interactive check dropped ⇒ can't-ask red (AUT-WAIVE case: run file differs [call 1 printed do=ask, want park; ])
ok: MC: "high_risk": false in the ctx ⇒ ctx leg red (ctx keys: drain_result,high_risk,ready_sha,review_heal_result_path,supervisor_result_path,termination_reason,trust_unprotected)
```

The M2b mutant is assembled at run time from two pieces, so the test source never holds the positive literal on one
line.

## Validation 3 — running system

Leg V: a scratch `git init` checkout, `gh` stubbed, no network. The real `run-lock.sh` lock is held as PICK holds it.
The input is a post-drain run file, and the driver gets `--result` = a READY drain report. The tail ends at the
`awaiting_merge` park. The watcher and notify are recorders. The run lock is the real one, and the driver releases it.

```
V3> acquire (PICK's lock, real run-lock.sh): exit 0
V3> driver exit 0, instruction: {"do":"park","step":"decide","run_id":"automate-2026-10-16-000000","item":".supervisor/requirements/v3/01-scratch-item.md","pr":"https://github.com/example/scratch/pull/7","status":"paused","pause_reason":"awaiting_merge","message":"parked; nothing to decide"}
V3> run-lock.sh status after: UNLOCKED
V3> ## Status / ## Current:
V3>   ## Status: paused
V3>   - item: .supervisor/requirements/v3/01-scratch-item.md | status: awaiting_merge | pr: https://github.com/example/scratch/pull/7 | branch: feature/v3-scratch
V3>   - pause_reason: awaiting_merge
V3> tail ## Progress:
V3>   - 2026-10-16T10:00:00Z owned drain started — /review-pr https://github.com/example/scratch/pull/7 --until-mergeable --no-auto-postmortem @ 1111111111111111111111111111111111111111
V3>   - 2026-10-16T10:20:00Z drain READY (converged, 1 round, 0 fix cycles)
V3>   - validation-gate: none — no running-system step in .supervisor/requirements/v3/01-scratch-item.md
V3>   - dismissed-drafts: 0 per-finding + 0 summary (0 listed in summary)
V3>   - 2026-10-16T04:52:08Z parked awaiting_merge https://github.com/example/scratch/pull/7 — 0 dismissed decision(s) pending
V3> recorded side effects:
V3>   watch <scratch>/repo/.supervisor/automate/automate-2026-10-16-000000.md .supervisor/requirements/v3/01-scratch-item.md https://github.com/example/scratch/pull/7
V3>   notify awaiting_merge <scratch>/repo/.supervisor/automate/automate-2026-10-16-000000.md PR https://github.com/example/scratch/pull/7 ready to merge — /automate parked awaiting_merge for .supervisor/requirements/v3/01-scratch-item.md
```

## How the golden cases are driven (honest notes)

- Four cases run end to end with no seam. Each starts from the drain report and ends at its natural instruction:
  `escalated-park`, `gate-validation-gate-unrun-escalated`, `park-first-ready-park` and
  `dismissed-findings-decision-step`.
- The other cases pin one segment of the tail. Each is entered or left through the driver's test-only seams
  `NEXT_STEP_FROM` / `NEXT_STEP_UNTIL` / `NEXT_STEP_CLOSEOUT_OUT`, and every write is still the driver's. One
  exception: `termination-queue-resolved` checks off its last row with a `pre:` helper call, standing in for the
  closeout the case assumes.
- The `gate-eval-*-park` goldens pin the park writes with no `dismissed-drafts` segment, so the test runs them as
  gate-eval, stop, then park. A full run of the driver does run `dismissed-drafts` at that park (prose order).
  Leg B1 runs the whole `--auto-merge` MERGE chain in one call sequence.
- Shapes the driver reproduces from the recorded goldens are listed in the schema section: the lane-only timestamp
  on the `dismissed-drafts` line, and the `— gate-eval PARK: <reason>` park line.
