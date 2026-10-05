# 30 — `test-lens-run.sh` case H is safe when two suites run at once

## Status: pending

## Problem
Found 2026-10-04 while verifying `parallel-automate/08` (PR #375, shared CI slots) with its must-pass three-clone
check: three clones ran `ci-local.sh --force` together; the slot cap held (2 holders, the third queued and later
passed 143/143), but **both concurrently running suites failed the same case**,
`loomwright/scripts/adapters/providers/test-lens-run.sh` case H ("hung CLI times out, process group killed, no
leftover children"), and a solo run passed:
- c1: `FAIL: H no leftover stub CLI processes (expected [0] got [1])`
- c2: `FAIL: H CLI never wrote its pid — timeout path may not have reached exec` and `… never wrote a child pid`

Causes, read from the test (pre-existing — last changed in `4865f06`, not by #375):
1. **A machine-wide check on a fixed name.** `STUB_CLI_NAME="loomwright-test-stub-cli"` is the same in every run, and
   the leftover check is `pgrep -f "$STUB_CLI_NAME"` across the whole machine — a second suite's live stub reads as
   this suite's leftover.
2. **A 1-second timeout under load.** `LOOMWRIGHT_LENS_CLI_TIMEOUT=1`: with 12 test jobs busy on 12 cores, the stub
   sometimes does not even exec (write its pid) inside a second, so the process-group proof has nothing to prove.

With item 08, two suites at once is the designed normal (default 2 slots on this Mac), so lanes will hit this flake
whenever two of them overlap on case H — a false red that costs a full re-run and teaches people to ignore reds.

## Goal
Case H proves the same things (timeout fires, process group killed, nothing left behind) and is independent of any
other suite running on the machine and of CPU load.

## Scope
1. **Per-run stub identity:** derive the stub's name from the test's own `$TMP` (or `$$`), so no two runs share it.
2. **Scoped leftover check:** check only the processes this case started — the recorded leader and child pids and
   their process group (`kill -0` on each, or `pgrep -g <pgid>`), never a machine-wide name match.
3. **Load-tolerant timing:** keep the timeout short for the timing assertion, but wait for the stub's pid file
   (bounded, e.g. up to 10 s) before starting the clock, so "never wrote its pid" means the stub really failed to
   run, not that the machine was busy; keep the "finished well inside the hung sleep" bound.
4. **Concurrency regression check:** a test leg (or a documented `ci-local` recipe) running case H twice at once in
   two temp dirs, both passing.
5. Grep the other self-tests for the same shape (`pgrep -f` on a fixed name, `ps | grep` machine-wide) and fix any
   found in the same PR, or list them in it.

## Acceptance criteria
- Two clones running `ci-local.sh --force` together pass case H in both, three times in a row.

## Validation (must pass before merge)
1. Baseline full loop, `<passed>/<total>` and `SKIP` counts, base and branch.
2. Unchanged path: case H still fails when the timeout kill is removed (mutation), and when the child is left alive.
3. Running system: paste two concurrent `ci-local.sh --force` runs both green.
4. A failure this must catch: revert to the fixed stub name ⇒ the concurrency leg fails.
5. Rollback: `git revert`.

## Evidence
Three-clone check of PR #375 (2026-10-04, this session): `c1.log` / `c2.log` FAIL banners, solo and c3 PASS; the
slot samples showing at most 2 holders.

## Depends on
none

## Touches
loomwright/scripts/adapters/providers/test-lens-run.sh
changelog.d/automate-followups-30-lens-run-test-concurrency-safe.md

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-04T16:52:25Z
- **Brief:** .supervisor/jobs/done/2026-10-04-lens-run-test-concurrency-safe.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/379
