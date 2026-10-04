# 08 — Shared CI slots: lanes on one machine take turns at the full suite instead of fighting for the CPUs

## Status: pending

## Depends on
none

## Touches
loomwright/scripts/ci-slot.sh
loomwright/scripts/test-ci-slot.sh
scripts/ci-local.sh
scripts/test-ci-local.sh
AGENT_GUIDELINES.md
changelog.d/parallel-automate-08-shared-ci-slots.md

## Problem
Owner goal (2026-10-04): run **5 to 10 lanes** at once, not 2. S1 v2 measured what happens to the full local
suite when two lanes run it at the same time (`ai-agent-manager-lanes-v2/q6-ci-contention.log`, sampled every
10 s on a 12-core / 24 GB Mac):
- a `ci-local.sh` run alone took **190–380 s**; with both lanes in it at once, **490–820 s** (about 1.7–2.3×);
- 1-minute load average **27** while both ran, against **10** with one; no lock wait, no timeout.

`ci-local.sh` already has the right ideas — "ONE RUN AT A TIME" and a pass cache keyed by tree content — but it
keeps both in `git rev-parse --git-common-dir`/loomwright-ci-local/. A lane is a separate local CLONE (decision
P4), so every lane has its own git dir, its own lock and its own cache. The lanes never see each other, each run
takes `SELF_TEST_JOBS` = every CPU, and N lanes oversubscribe the machine N times.

## Goal
Every checkout of the same repository on one machine (primary, linked worktrees, lane clones) shares ONE pool of
CI slots and ONE pass cache. A run waits its turn in a fair queue, uses only its share of the CPUs, and anyone can
see who holds a slot and who is waiting.

## Scope
1. **A shipped, generic slot helper** `loomwright/scripts/ci-slot.sh` (plugin code: no repo-local paths):
   - `acquire <name> [--slots N] [--wait S]` → prints the slot number and the job share to use; `release`;
     `status [--json]` → holders (pid, checkout path, lane, started) and waiters in queue order.
   - **Shared location keyed by repository identity, not by git dir:** `${XDG_STATE_HOME:-$HOME/.local/state}/
     loomwright/ci-slots/<repo-key>/`, where `<repo-key>` is a hash of the normalised `origin` URL (fall back to
     the git-common-dir path when there is no origin, which is today's behaviour).
   - **N slots** (default `max(1, floor(CPUs / 6))` = 2 on this Mac; override `LOOMWRIGHT_CI_SLOTS`), each an
     atomic `mkdir` lock holding its pid, like today's lock. A slot whose pid is dead is taken over (today's rule).
   - **Fair queue:** a waiter takes a ticket (atomic counter file); slots go to the lowest live ticket, so no run
     starves. Dead waiters' tickets are skipped.
   - **Job share:** prints `jobs = max(2, floor(CPUs / N))` for the caller to pass as `SELF_TEST_JOBS`, so N
     concurrent runs use about the CPU count in total.
   - bash 3.2 / BSD userland safe; no `flock` binary (macOS has none).
2. **`scripts/ci-local.sh` uses it:** the lock becomes `ci-slot.sh acquire`, the job count comes from it (an
   explicit `SELF_TEST_JOBS` still wins), and the PASS-cache stamps move to the same shared, repo-keyed location,
   so a tree that passed in any checkout returns at once in every other. The tree-moved-mid-run rule and
   "only passes are cached" stay exactly as they are.
3. **Visible waiting:** while waiting, `ci-local.sh` prints one line every 30 s (`waiting for a CI slot — position
   3, holders: v2-a (4m), v2-b (1m)`), and `ci-slot.sh status --json` is what item 05's `lane-status` and the lanes
   pane read to show "waiting for CI slot".
4. **`AGENT_GUIDELINES.md` §"Pre-push: one command"** gains one line: concurrent sessions share slots
   automatically; never raise `LOOMWRIGHT_CI_SLOTS` to "go faster".
5. **Tests** (`test-ci-slot.sh`, plus new cases in `test-ci-local.sh`): two checkouts of one repo (a clone and a
   worktree) share one slot set; three concurrent acquirers with N=2 → exactly 2 holders, the third waits and gets
   the slot in ticket order; a dead holder is taken over; a dead waiter's ticket is skipped; different origins never
   share; the cache stamp written by one clone is honoured by another for the same tree; job share math for N=1/2/4.

## Non-goals
- No change to WHAT runs (that is item 09) or to the remote `ci` job.
- No daemon or server process: files and pids only (the "no orphaned process" rule).

## Acceptance criteria
- With 3 lane clones each starting `ci-local.sh` within a second, at most `N` suites run at once, the rest print
  their queue position, and all three finish green.
- The per-clone `loomwright-ci-local/lock` is gone; `grep -n 'git-common-dir' scripts/ci-local.sh` shows it only as
  the no-origin fallback.
- A clone whose tree equals one already passed elsewhere returns `PASS (cached)` without running.

## Validation (must pass before merge)
1. **Baseline:** full loop on base and branch, `<passed>/<total>` and `SKIP` counts for both.
2. **Unchanged path:** a single checkout with no other session behaves as today (one run, full job count when N=1,
   same output apart from the lock line).
3. **Running system:** three throwaway clones of this repo, `ci-local.sh --force` started together; paste
   `ci-slot.sh status` mid-run and the three wall-clocks against one solo run.
4. **A failure this must catch:** remove the ticket ordering ⇒ the fairness test fails; key slots by git dir again
   ⇒ the two-checkout test fails.
5. **Rollback:** `git revert`; stale slot directories under the state dir are harmless (pids dead ⇒ taken over).

## Verified premises (re-check before starting)
- `scripts/ci-local.sh` header blocks "PASS CACHE" and "ONE RUN AT A TIME" put both in the git-common-dir
  (`state=".../loomwright-ci-local"`, `lockdir="$state/lock"`), checked 2026-10-04.
- `loomwright/scripts/run-self-tests.sh`: `SELF_TEST_JOBS` defaults to the CPU count.
- Lanes are clones (P4), so they never share a git-common-dir.

## Evidence
S1 v2 run record (`operator-run/S1-two-lane-spike.md`, "Q6 measured" and the v2 comparison table).
- **Must-pass three-clone check, run by the operator 2026-10-04 (PR #375 head `bce76cf`; the PR listed it as "Not verified"):** three clones with the real origin ran `ci-local.sh --force` together. `ci-slot.sh status` was sampled every 15 s, 70 samples: **at most 2 holders**, the third queued (ticket shown, "waiting for a CI slot — position 1") and ran when a slot freed. Holders were the real `ci-local.sh` pids (the Plan Review risk). Wall-clock: the two concurrent runs 606 s each (6 jobs each), the queued run 449 s once started (1055 s total), solo 453 s; three runs in 1055 s against 1359 s serial. Result: c3 and solo **PASS 143/143**; c1 and c2 each **FAILED 1 test**, `test-lens-run.sh` case H. That is a pre-existing non-hermetic test (fixed stub name + machine-wide `pgrep`, 1 s timeout under load), not a slot defect, filed as `automate-followups/30`. Verdict: the mechanism is verified; merge recommended, with item 30 first in the next wave.

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-04T11:51:32Z
- **Brief:** .supervisor/jobs/done/2026-10-04-shared-ci-slots.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/375
