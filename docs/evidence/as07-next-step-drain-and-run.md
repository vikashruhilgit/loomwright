# Evidence — automate-speed/07: the next-step driver takes over RUN and DRAIN

Source requirement: `.supervisor/requirements/automate-speed/07-next-step-drain-and-run.md`.
Driver: `loomwright/scripts/automate-next-step.sh`. Suite: `loomwright/scripts/test-automate-next-step.sh`. Per-case
drive files: `loomwright/scripts/fixtures/automate-golden/<case>/next-step.results`. Instruction schema:
`loomwright/docs/result-schemas/automate-run.md` §"next-step instruction". Base commit `c7d4f9a`. macOS. The driver
suite also ran under `/bin/bash` 3.2.57 (`PATH="/bin:$PATH" /bin/bash loomwright/scripts/test-automate-next-step.sh`
→ `PASS: 94 FAIL: 0`, on the tree before leg R9 was added).

This file has two parts. Subtask 1 (the driver) recorded the before-values, the driver legs, the mutation verdicts
and the Validation 3 drive. Subtask 2 (the prose migration) fills the after-values and the migration's suite results.

## Before / after

| Measure | Before (base `c7d4f9a`) | After |
|---|---|---|
| `wc -c loomwright/skills/automate-loop/*.md` (full glob, `legacy-tail.md` included) | `330343 total` | _(subtask 2)_ |
| Default-mode read set: Step 0's **Always** files on a sequential run (`SKILL.md` 86071 + `per-item-loop.md` 79821 + `modes-and-merge-gate.md` 27269 + `invariants.md` 5900), `legacy-tail.md` excluded | `199061` | _(subtask 2)_ |
| Loop-inventory `GAP` count (`docs/loop-inventory/automate-loop.md` `## Counts`, rows 560) | `132` | _(subtask 2)_ |

Per-file `wc -c` at base: `SKILL.md` 86071, `branch-mode.md` 7592, `command-lanes.md` 4111, `intake.md` 10379,
`invariants.md` 5900, `lanes.md` 56932, `legacy-tail.md` 33407, `modes-and-merge-gate.md` 27269, `per-item-loop.md`
79821, `resume.md` 18861.

**Invariant-grep file list** (`grep -rn "<the merge command>" loomwright/ | grep -viE "no |never |not " | cut -d: -f1 |
sort -u`, the CLAUDE.md §Failure-Mode Invariants grep) at base. It is unchanged after subtask 1: the driver, its test,
the fixtures and the schema section add no line to it (the suite's S leg asserts this):

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

## Validation 1 — suite results (subtask 1's run)

```
test-automate-next-step.sh   PASS: 95 FAIL: 0     (baseline 72/0)
test-automate-golden.sh      PASS: 64 FAIL: 0     (unchanged)
test-loop-inventory.sh       RESULT: 43/43 passed (unchanged)
test-automate-dismissed.sh   245 passed, 0 failed
test-automate-loop-split.sh  RESULT: 40 passed, 0 failed
test-result-schemas-split.sh RESULT: 14 passed, 0 failed
check-doc-currency.sh        all checked version/count claims match the authoritative source
test-citation-drift.sh       26 passed, 0 failed
check-token-budget.sh        OK
test-automate-helpers.sh     761 passed, 1 failed — W19 (see Not verified)
```

The eight RUN/DRAIN golden cases run through the driver byte for byte against their existing `expected.md`:
`run-config-suppress-restore`, `run-record-pr`, `drain-owned-drain-started`, `drain-pinned-start-line-current-not-set`
(exit 3, `expect-exit: 3`), `drain-superseded-by-merge`, `learning-emit-end-of-drain` (ledger projection equal to
`expected.out`, `out:`), `rate-limit-park` and `dismissed-fix-now-re-drain`. Every one is in `REQUIRED_CASES`.

## Validation 2 — mutation controls (each gated non-empty + differs + `bash -n`)

```
ok: M7a: restore moved to drain-result ⇒ R1 red (at the owned-drain spawn: config.json not restored byte-for-byte (or the backup left): {"auto_review":false,"keep":[1,2]}); run-config-suppress-restore parity green
ok: M7b: second-drain refusal removed ⇒ R2 red (second spawn before the report ⇒ exit 0 '{"do":"spawn","step":"drain",…}' .supervisor/ CHANGED)
ok: M7c: config-suppress exit ignored ⇒ R3 red (malformed config ⇒ exit 0 '{"do":"spawn","step":"run",…}' .supervisor/ CHANGED)
ok: M7d: sidecar written on the superseded path ⇒ R4 red (a review-heal sidecar was written on the superseded path)
ok: M7e: start-line exit swallowed ⇒ drain-pinned-start-line-current-not-set red (run file differs [call 1 exit 1, want 3; ])
```

M7a (Validation 2a) leaves the `run-config-suppress-restore` run-file parity green. The `auto_review restored` line is
still written; only `config.json`'s state at the drain spawn differs. The order leg R1 is the one that catches it,
which is the "parity and/or an order leg" form Validation 2a allows. Every pre-existing mutant (M2a … MO) still turns
its leg red.

## Validation 3 — running system (hermetic scratch repo, gh stubbed, the real `run-lock.sh` held as PICK holds it)

One item driven from PICK (`## Current` `status: running`, its `picked` line) through `--start run` → the
`/autonomous` spawn answered with a fixed `SUPERVISOR_RESULT` and session id → the owned-drain spawn answered with a
fixed READY `REVIEW_HEAL_RESULT` → the tail (validation gate `none`, the awaiting_merge park, the run lock released).
`config.json` read `{"auto_review":false}` at the `/autonomous` spawn and was absent again at the drain spawn (original
absent). Progress lines from `auto_review suppressed` to `drain READY`:

```
- 2026-10-17T06:21:04Z auto_review suppressed (backup automate-2026-10-17-000000.config-backup.json) — running /autonomous --single-iteration
- 2026-10-17T06:21:04Z auto_review restored (config-restore: original absent)
- 2026-10-17T06:21:04Z session_id auto-2026-10-17-090001 (.supervisor/requirements/v7/01-scratch-item.md)
- 2026-10-17T06:21:05Z ran /autonomous → PR https://github.com/example/scratch/pull/9 (SUPERVISOR_RESULT completed: heal PASS, 1 review)
- 2026-10-17T06:21:05Z owned drain started — /review-pr https://github.com/example/scratch/pull/9 --until-mergeable --no-auto-postmortem @ 2222222222222222222222222222222222222222
- 2026-10-17T06:21:06Z drain round 1: 0 validated findings; ci green on 2222222
- 2026-10-17T06:21:06Z drain READY (converged, 1 round, 0 fix cycles; ci green on 2222222)
```

## Not verified

- No live `/automate` session has consumed the new `/autonomous run` and `owned drain` instructions. Validation 3 is
  a hermetic scratch drive with the model's reports as fixed input. Live consumption is item 08's path, once the
  skill prose points at the driver (subtask 2).
- `test-automate-helpers.sh` W19 fails in this lane clone. It parses the REAL gitignored
  `.supervisor/requirements/parallel-automate/` queue present in this checkout (it SKIPs where that dir is absent, as
  in CI). The failure is in `plan-waves`, which this change does not touch.
- The drain's start line is written when its report arrives, stamped with the spawn time. A crash mid-drain leaves
  no start line in `## Progress`; the sidecar's pending spawn is the evidence (schema doc honest notes).
