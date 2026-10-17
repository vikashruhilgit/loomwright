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
| `wc -c loomwright/skills/automate-loop/*.md` (full glob, `legacy-tail.md` included) | `330343 total` | `336603 total` |
| Default-mode read set: Step 0's **Always** files on a sequential run (`SKILL.md` 86071 + `per-item-loop.md` 79821 + `modes-and-merge-gate.md` 27269 + `invariants.md` 5900), `legacy-tail.md` excluded | `199061` | `180686` (`SKILL.md` 86697 + `per-item-loop.md` 60818 + `modes-and-merge-gate.md` 27271 + `invariants.md` 5900; −18375, −9.2%) |
| Loop-inventory `GAP` count (`docs/loop-inventory/automate-loop.md` `## Counts`, rows 560) | `132` | `125` (rows 563) |

Per-file `wc -c` at base: `SKILL.md` 86071, `branch-mode.md` 7592, `command-lanes.md` 4111, `intake.md` 10379,
`invariants.md` 5900, `lanes.md` 56932, `legacy-tail.md` 33407, `modes-and-merge-gate.md` 27269, `per-item-loop.md`
79821, `resume.md` 18861.

Per-file `wc -c` after subtask 2: `SKILL.md` 86697, `branch-mode.md` 7592, `command-lanes.md` 4111, `intake.md` 10379,
`invariants.md` 5900, `lanes.md` 56932, `legacy-tail.md` 58018, `modes-and-merge-gate.md` 27271, `per-item-loop.md`
60818, `resume.md` 18885. The full glob grows (+6260 bytes): the moved prose is kept whole in the `--legacy`-only
file and the default path gains its short "run next-step" pointers. The default-mode read set shrinks by the moved
prose less those pointers.

**Invariant-grep file list** (`grep -rn "<the merge command>" loomwright/ | grep -viE "no |never |not " | cut -d: -f1 |
sort -u`, the CLAUDE.md §Failure-Mode Invariants grep) at base. It is unchanged after subtask 1 and after subtask 2: the
driver, its test, the fixtures and the schema section add no line to it, and the one merge-command line that moved to
`legacy-tail.md` (§7's "The drain is inline" note) is negated, so the list is byte-identical (the suite's S leg asserts this):

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

## Validation 1 — suite results (subtask 2's run, after the prose migration)

```
test-automate-next-step.sh   PASS: 95 FAIL: 0
test-automate-golden.sh      PASS: 64 FAIL: 0
test-automate-helpers.sh     RESULT: 761 passed, 1 failed — W19 (see Not verified; unchanged from subtask 1's run)
test-automate-dismissed.sh   245 passed, 0 failed
test-loop-inventory.sh       RESULT: 43/43 passed (GAP automate-loop: 125)
test-automate-loop-split.sh  RESULT: 40 passed, 0 failed
test-result-schemas-split.sh RESULT: 14 passed, 0 failed
check-doc-currency.sh        all checked version/count claims match the authoritative source
test-citation-drift.sh       26 passed, 0 failed
check-token-budget.sh        OK (automate-loop 84147 / 87895, 3748 headroom; automate 7236 / 7565, 329 headroom)
```

Other suites that read the moved prose, run on the same tree: `test-automate-lanes.sh` 911/0 (AJ4e5 reads
`per-item-loop.md` step 2's pinned no-PR line, which the step-2 pointer keeps), `test-automate-trail.sh` 786/0 (NT6 reads
the assembly's `## Legacy tail — ` section), `test-session-resume.sh` 338/0, `test-run-lock.sh` 82/0,
`test-non-interactive-gates-seam.sh` 64/0, `test-classify-risk.sh` 45/0, `test-build-loop-evidence.sh` 30/0,
`test-setup-memory.sh` 574/0, `test-harvest-conventions.sh` 172/0, `test-build-handoff.sh` 93/0, `test-context-digest.sh`
green.

What moved, verbatim (line-exact, checked against a pre-move copy): `per-item-loop.md` §6 step 2 RUN with its
"Session-id recording" paragraph, step 3 DRAIN with its "Drain superseded by a merge" bullet, "Rate-limit park (end of
RUN, before DRAIN)", "Learning-emit at end-of-DRAIN (engine-native ground-truth signal)" and §7's three subsections. They
now sit in `legacy-tail.md`, read only under `--legacy`. `per-item-loop.md` keeps one "run next-step" pointer per step
(steps 2 and 3, and a §7 paragraph). §7's lead paragraph stays where it was: it states the single-drain rule, not a step.
The five moved headings left `MAP.tsv` (units no longer extracted from `per-item-loop.md`), and §6 L1.2 / L1.3 stay as
units. 42 inventory rows were re-homed to `script:automate-next-step.sh <step>`, every one naming a real `case` arm.
AL-387 (§7's "Crash-restore" bullet) keeps `script:automate-helpers.sh config-restore` and never a driver step:
RECONCILE's crash-restore stays prose in `resume.md` §4. Three rows were added for the new pointers. Seven GAP rows now
name the driver suite, because a driver leg covers them (AL-255 R1/M7a, AL-266 R4, AL-288 and AL-290 R8 /
`rate-limit-park`, AL-302 the `learning-emit-end-of-drain` key, AL-390 and AL-393 V7's owned-drain invocation). Five stay
GAP because no leg asserts them (AL-254 passthrough flags beyond `--non-interactive-fallback`, AL-291 other failure
reasons, AL-299 a prose rule, AL-300 / AL-305 the learning line's `--repo` / `--plugin-version`).

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
  a hermetic scratch drive with the model's reports as fixed input. The skill prose now points at the driver (subtask
  2), but no model has followed those pointers yet; live consumption is item 08's path.
- `test-automate-helpers.sh` W19 fails in this lane clone. It parses the REAL gitignored
  `.supervisor/requirements/parallel-automate/` queue present in this checkout (it SKIPs where that dir is absent, as
  in CI). The failure is in `plan-waves`, which this change does not touch.
- The drain's start line is written when its report arrives, stamped with the spawn time. A crash mid-drain leaves
  no start line in `## Progress`; the sidecar's pending spawn is the evidence (schema doc honest notes).
- `test-automate-dismissed.sh`'s B leg "the PICK ask sits inside §6 step 1 (PICK), before RUN" still reads the first
  `2. **RUN**` in the assembly. That anchor now lives only in `legacy-tail.md`, which the assembly places after
  `per-item-loop.md`, so the leg would no longer catch a PICK ask that drifted below the step-2 pointer. The pin was kept
  byte-identical, as the brief asks (repoint only when an anchor cannot stay). Tightening it to the pointer
  (`2. **RUN — run next-step**`) is a follow-up.
- `scripts/check-vendor-coupling.sh` (a CI gate outside Validation 1) flagged subtask 1's driver files after the prose
  move; fixed in the follow-up commit: the plugin-version read now resolves from the script's own location (coupling
  removed), and the one stop-failure payload field the rate-limit hint needs is a declared allowance of 1 for the driver
  and its test, with an `allowance_reasons` entry in `loomwright/docs/vendor-coupling-manifest.json`.

## Full local CI (`bash scripts/ci-local.sh`, on the final tree)

```
1 of 170 self-tests FAILED (wall 826s):
  loomwright/scripts/test-automate-helpers.sh   (RESULT: 761 passed, 1 failed — W19 only)
```

W19 is environmental, not a regression: `test-automate-helpers.sh` run on a clean worktree of the base commit
(c7d4f9a) with the same gitignored `.supervisor/requirements/` queue copied in fails the same leg the same way
(`RESULT: 761 passed, 1 failed`, `FAIL: W19 real 22-split-automate-engine-surfaces.md ## Touches parses (known)`).
In CI the queue is absent and W19 skips. `check-vendor-coupling.sh` passes on this tree.
