# 07 — Fixed-sleep test races: wait on the condition, not the clock (S6 and its class), plus a guard

## Status: parked — superseded by `.supervisor/requirements/implementation-quality/02-iq01-and-throughput-merged.md` (owner decision 2026-10-09: implementation-quality/01 + throughput/01–09 merged into ONE item / ONE PR; this file is kept as that file's Part source)

## Depends on
none

## Touches
loomwright/scripts/test-automate-lanes.sh
loomwright/scripts/test-automate-trail.sh
loomwright/scripts/test-setup-ui.sh
loomwright/scripts/wait-lib.sh
loomwright/scripts/test-wait-lib.sh
loomwright/scripts/test-no-fixed-sleep-race.sh
changelog.d/throughput-07-fixed-sleep-test-races.md

## Problem
**S6 is a confirmed flake that was never filed.** In `loomwright/scripts/test-automate-lanes.sh`, the `# ---- S: keep-awake` block runs `out="$(run lane-status "$RF2" --keep-awake)"; sleep 0.3` and then asserts `has "S6 --keep-awake starts it, tied to the coordinator" "$(cat "$CAFF_LOG")" "caffeinate -i -w 4242"`. The caffeinate stub (`$T/caff-stub`, which appends `caffeinate $*` to `$CAFF_LOG`) is started in the background by `lane-status --keep-awake` (`automate-lanes.sh`, `LOOMWRIGHT_LANES_CAFFEINATE`). The 0.3 s sleep races that background write. The ci-slot run logs (`~/.local/state/loomwright/ci-slots/dd8a9612cd818d9a/runs/`) show `FAIL - S6 --keep-awake starts it, tied to the coordinator`, with S6b ("and says so") green, in two runs:
- `5656bf…-20261008T093018Z` (09:30Z, a 4190 s run under heavy load);
- `e615441…-20261008T144512Z` (14:45Z, 658 s). The same tree passed on the immediate rerun at 14:56Z (`e615441…-145627Z`).

That cost PR #435's item one full 658 s run (`00-overview.md`: "1× S6 `sleep 0.3` race").

**The class.** `grep -nE "sleep 0\.[0-9]" loomwright/scripts/test-*.sh scripts/test-*.sh` matches **95** lines today, across 19 files. Classified by reading each site:

- **(a) inside a bounded poll loop — fine (80 lines).** For example `wait_gone`, the `i=0; while … && [ "$i" -lt N ]; do sleep 0.1; …` waits, `nwait`/`xwait` in test-ci-slot, `s_wait_gone`/`n_wait_up` in test-setup-ui, and the meta-sync rendezvous loops.
- **(b) fixed sleep, then an assertion on async state — a race. Fix all in this item (5 lines):**

  | File | Case | Site |
  |---|---|---|
  | `test-automate-lanes.sh` | **S6** `--keep-awake starts it, tied to the coordinator` | `lane-status … --keep-awake; sleep 0.3`, then reads `$CAFF_LOG` (failed twice, above) |
  | `test-automate-lanes.sh` | **N8** `live merge watcher refused` | backgrounds the merge-watch stub, `sleep 0.3`, then `lane-remove`, whose `_lanes_live_watchers` matches the pid's `ps` command line (`*automate-merge-watch*<pr_url>*`). Under load the child may not have exec'd yet. |
  | `test-automate-trail.sh` | `== W. merge watcher ==`, **"dead-pid marker is reclaimed"** | `( sleep 0 & echo $! > "$TOP/deadpid" ); sleep 0.2` assumes that pid is already dead before the reclaim launch |
  | `test-automate-trail.sh` | **(E7) AC9 (1)–(3)** in `dbl_arm` | after the first status line appears in the second launch's log, `sleep 0.3`, then asserts that log's WHOLE content equals one line and the first watcher is alive. This is a fixed quiet period. Wait for the second launcher to exit instead (it exits after `already running`). |
  | `test-setup-ui.sh` | the reap helper behind **(p6)** ("a TERM-ignoring process is gone") | after `kill_if_fixture … KILL`, `sleep 0.25`, then the survivors are read into `REAP_LEFT`, which (p6) asserts empty. A KILLed, reparented process can still be listed until it is reaped. |

- **(c) settle-before-action or quiet-period negatives — keep, but annotate why (4 lines).** None of these assert on async output directly. They are either vacuity risks (too short ⇒ the test exercises a different path and still passes) or absence checks a condition-wait cannot express:
  - `test-automate-lanes.sh` `aa_feed` (AA-F12a–c): `sleep 0.3; kill -"$sig"`;
  - `test-automate-trail.sh` M2: `sleep 0.5   # A is now inside its 30s interval nap`;
  - `test-ci-slot.sh` (X) `mixed_ok`: `sleep 0.6`, then "N=1 waiter took a slot";
  - `test-ci-slot.sh` interrupt arm: `sleep 0.3   # past the claim attempt, into the poll wait`.
- **(d) not a wait (6 lines):**
  - `test-ci-slot.sh`: two comments, the `slowsleep` stub's content, and the G13 `sed` mutant pattern;
  - `test-token-ledger.sh`: a `sleep 0.3` injected into a mutant to widen a race on purpose;
  - `test-setup-memory.sh`: a `sleep 0.05` capability probe.

**The brief's regex misses whole-second sleeps.** A second heuristic, `sleep [1-9]…` excluding `sleep N &` holder processes, matches ~66 more lines. Most of them are legitimate:
- mtime or timestamp separation: `test-set-otel-resource-attrs.sh`, `test-token-ledger.sh`, `test-verify-queue.sh`, `test-worktree-audit.sh`;
- stub bodies;
- `test-agent-identity.sh`'s "The `sleep 1` is the assertion" case.

At least one more belongs to this item's class: `test-automate-lanes.sh` **AA-F12e** ("the unescaped pattern T8 used never matched a live tail") runs `sleep 1; pgrep -f "<unescaped>" && echo matched || echo unmatched` and expects `unmatched`. On a slow start the tail is not up yet, so `unmatched` passes for the wrong reason. It should first wait until the ESCAPED pattern sees the tail, as `aa_feed` does, then probe the unescaped one. `test-harvest-conventions.sh` (M1)'s `sleep 1` PTY feed is item 06's.

**Is there a shared helper to put a wait function in? Not really.** The only file every test sources is `loomwright/scripts/hermetic-test-env.sh` (all 143 covered test files today; it must be the first executable line, `scripts/check-test-hermetic.sh`). Its header scopes it to egress: (a) scrub egress env vars, (b) desktop-notification opt-out, (c) the notifier/curl/wget recording stubs, (d) `HERMETIC_TEST_ENV=1`, (e) never touch HOME. A wait helper there would mix an unrelated concern into a fail-closed egress layer, which `run-self-tests.sh` also sources for every worker. No other sourced test library exists, and each test defines its own poll loop today.

## Goal
No test asserts on async output after a fixed sleep. Every such wait is a bounded poll on the condition the assertion reads, and a deadline miss fails with the condition named. A new fixed-sleep-then-assert cannot land unnoticed.

## Scope
1. **Shared helper (NEW `loomwright/scripts/wait-lib.sh`).** A sourced library. It is deliberately NOT named `test-*.sh`: the `run-self-tests.sh` glob would run it as a test, and `check-test-hermetic.sh` covers only `test-*.sh`. It holds a few bounded waits, bash 3.2 safe, with no GNU-only flags:
   - `wait_for_file_content <file> <fixed-string> <timeout_s>`
   - `wait_for_pid_gone <pid> <timeout_s>`
   - `wait_for_cmd <timeout_s> <cmd…>` (true when the command succeeds)

   Each polls at 0.1 s, bounds by the CLOCK rather than an iteration count (the G13 lesson in `test-ci-slot.sh`: a slow `sleep` stretched a count-bounded wait to ~15 s), returns 0 or 1, and never exits the caller. Its own self-test is NEW `loomwright/scripts/test-wait-lib.sh`, with the hermetic source line first. It covers: a condition that becomes true after 0.5 s, a timeout, a slow `sleep` on PATH (the clock bound holds), and a mutation control (a count-bounded copy fails under the slow sleep).
2. **Fix every (b) site in the table, plus AA-F12e,** using the helper or an equivalent local bounded poll:
   - **S6:** `wait_for_file_content "$CAFF_LOG" "caffeinate -i -w 4242" 5`, then assert.
   - **N8:** wait until `ps -o command= -p "$WPID"` shows the watcher, then run `lane-remove`.
   - **Dead-pid reclaim:** `wait_for_pid_gone` on the recorded pid before writing the marker.
   - **(E7) `dbl_arm`:** capture the second launcher's pid and wait for it to exit before reading its log.
   - **(p6) reap helper:** poll for the survivors to clear with a bound before setting `REAP_LEFT`.

   Each fix keeps its assertion's meaning, and each must FAIL when the condition never becomes true. Show this with a stub that never writes, plus a mutation control per fixed case.
3. **Annotate the (c) lines.** Give each a short trailing comment saying why it is a settle or quiet period, and the vacuity risk if it is too short. Change one to a condition wait only where that is clearly possible: `aa_feed` already waits for the tail to be seen, so its `sleep 0.3` may not be needed at all. Measure before removing it.
4. **Guard (NEW `loomwright/scripts/test-no-fixed-sleep-race.sh`).** A lint-as-self-test, modeled on `loomwright/scripts/test-no-pipefail-grep-q.sh`: a per-file count RATCHET (its `WRITER_BASELINE` pattern) over `loomwright/scripts/test-*.sh`, `loomwright/scripts/adapters/*/test-*.sh` and `scripts/test-*.sh`. It is auto-included by the suite glob, so CI runs it with no ci.yml edit.
   - **What it counts:** a `sleep <literal>` statement that is not on a loop line (`while`/`until`/`for` … `do`, or inside a `do … done` body) and not on a comment line. Heredoc bodies are skipped, reusing the heredoc-awareness approach of `test-suite-helpers-defined.sh`.
   - **The ratchet:** any increase, or any file not in the baseline, is red. A count that falls without the baseline being lowered is also red, so the baseline only shrinks.
   - **Escape hatch:** a trailing `# fixed-sleep-ok: <reason>` on the same line exempts that site. This is how the (c) and (d) sites and the legitimate whole-second ones stay green with a written reason.
   - **Controls:** the guard ships with controls proving it can fire, e.g. a fixture with a new `sleep 0.3` + `has …` pair ⇒ red, and the same pair inside a bounded `while` ⇒ green.
5. **Sequencing.**
   - `automate-followups/34` touches `test-automate-trail.sh` and `test-setup-ui.sh`.
   - `automate-followups/36` touches `test-automate-trail.sh`.
   - Item 06 may split `test-automate-trail.sh`.

   The shared Touches lines keep these items out of one wave. Whichever lands second rebases onto the other's version of the file.

## Acceptance criteria
- S6 passes 50/50 under a loaded pool, e.g. `run-self-tests.sh` over `test-automate-lanes.sh` ×1 plus the heaviest tests at 6 jobs, repeated. On the base commit it fails at least once in the same harness with the stub delayed: a `caffeinate` stub that sleeps 0.5 s before writing reproduces the race deterministically, so the PR shows red on base and green on branch.
- Every (b) site in the table and AA-F12e is rewritten. For each one, a delayed-stub (or never-writing-stub) variant shows: the new wait succeeds when the condition arrives late (but within the bound), and fails, naming the condition, when it never arrives.
- `wait-lib.sh` exists with `test-wait-lib.sh` green, including the slow-`sleep` mutation control.
- `test-no-fixed-sleep-race.sh` is green on the branch. It is red on a fixture adding one new fixed-sleep-then-assert, green on the same sleep inside a bounded loop, and green on a `# fixed-sleep-ok:` annotated line. Its baseline lists every file and count it accepts, and the PR body explains each non-zero count, or each count is covered by annotations.
- The (c) lines carry their reason comments, and no (b)-class site remains un-annotated, as the guard proves.

## Validation (must pass before merge)
1. `bash scripts/ci-local.sh` green.
2. The S6 delayed-stub repro: red on the base commit, green on the branch (commands and output in the PR body).
3. The loaded-pool 50× run for `test-automate-lanes.sh` (count of passes in the PR body).

## Non-goals
- Rewriting (a) poll loops onto the new helper. They are correct, and churn there is risk without benefit.
- Making the quiet-period negatives (c) event-driven. "Nothing happened for T seconds" has no event to wait on. They get a reason comment and stay under the guard's annotation.
- Whole-second sleeps that separate timestamps or mtimes (e.g. `test-set-otel-resource-attrs.sh`, `test-token-ledger.sh`). They are not waits on async output, and the guard exempts them by annotation.
- `test-harvest-conventions.sh` (M1)'s PTY feed and the serial markers (item 06).
- A guard with no false positives. The ratchet-plus-annotation shape accepts that a line-based heuristic cannot fully parse bash. It only has to stop the count from growing silently.
