# 24 — pa/05 Validation 4/5 fixes B: lane notification, per-lane token counts, and the leaking lane-feed test

## Status: pending

## Depends on
23-pa05-validation-fixes-a.md

## Touches
loomwright/skills/automate-loop/SKILL.md
loomwright/scripts/automate-lanes.sh
loomwright/scripts/test-automate-lanes.sh
loomwright/scripts/read-token-ledger.sh
loomwright/scripts/test-read-token-ledger.sh
loomwright/scripts/emit-token-ledger.sh
loomwright/scripts/test-token-ledger.sh
loomwright/docs/TELEMETRY.md
changelog.d/parallel-automate-24-pa05-validation-fixes-b.md

## Problem
These were found by pa/05's Validation 4/5 (run `automate-2026-10-08-033739`; evidence is in #426's description,
under "Known issues"). The pa/05 release bump waits for this item too.

- **F6 — the "wave open" notification never reaches the owner.** At a lane's `ready_for_release` park (§14 "Terminal
  park"), the lane must notify "do not merge yet — wave open". L1 called `send-webhook.sh`, which printed
  `repo_webhook_ignored` (no user-scope egress grant for this repo). There was no desktop notification, and L1 first
  logged it as sent, then appended a correction. The gate type it used, `automate_ready_for_release`, is not in
  `docs/TELEMETRY.md`'s gate list. L2 reports that it sent a desktop notification, so the two lanes behaved
  differently. The step is prose, with no helper.
- **F8 — per-lane token counts read zero.** `lane-status <rf> --tokens` printed `L1 … TOTAL=0 EVENTS=6`, `L2 …
  TOTAL=0 EVENTS=3`, `parent … LEDGER_UNREADABLE=1`. Meanwhile each lane's stream-json `total_cost_usd` summed to
  about $17.0 (L1) and $8.6 (L2). So the ledger records events with zero tokens inside lane clones, and `--max-tokens
  T` (split as `floor(T/N)` per lane in `lane.json`) can never trip. The cause is not known yet.
- **F12 — the `lane-feed --follow` test leaks a live pipeline on every suite run** (found 2026-10-08 while item 23's
  drain fix ran `ci-local`). Test T8 in `test-automate-lanes.sh` (group "T: --watch, lane-feed", shipped with #426)
  starts `lane-feed "$L6" --follow` in the background, then cleans up with
  `pkill -f "tail -n +1 -f $LR2/L6.stream.log"` and `kill "$FP"`. The `tail` actually runs on the RESOLVED path
  (`/private/var/folders/…/L6.stream.log`, because macOS `/var` is a symlink to `/private/var` and the lane path is
  `pwd -P`-resolved), so the `pkill` pattern never matches; `kill "$FP"` kills only the wrapper shell. The
  `tail -n +1 -f | grep --line-buffered '^{' | jq --unbuffered` pipeline that `lanes_feed --follow` builds is
  orphaned (ppid 1) and runs forever.
  - **Scale:** 55 such orphaned pipelines had accumulated on the owner's Mac between 2026-10-07 23:55 and
    2026-10-08 16:11 (one per suite run: `ci-local`, workers, drains). All were killed by hand.
  - **Why it matters beyond the leak:** each orphan inherits the test's stdout, so it holds the suite's output pipe
    open. Any caller that pipes the suite — `bash scripts/ci-local.sh | tail -15` — never sees EOF and hangs after the
    suite itself has finished. This hung item 23's drain fix worker for ~30 min and explains the fix-now worker's
    background "wait for ci-local" loops.
  - Platform: reproduces on every macOS run. Not verified on Linux CI, where `$TMPDIR` is normally not behind a
    symlink, so the `pkill` pattern may match there — check before claiming either way.

## Goal
Every lane park reaches the owner the same way and through a documented gate type. Per-lane and parent token totals
are real, so a lane's `--max-tokens` share can park the lane.

## Scope
1. **F6:** one helper call does the lane park notification (desktop notify plus webhook, both fail-SAFE, as the
   merge watcher does). §14 "Terminal park" names it, and `automate_ready_for_release` is added to `TELEMETRY.md`'s
   gate types. A lane's `## Progress` records what was actually delivered, never just what was attempted.
2. **F8:** first find why lane ledger events carry zero tokens: the lane's SubagentStop payload, the transcript path
   the emitter reads inside a clone, or the reader's `--root`. Write the finding into the PR. Then fix it so
   `lane-status --tokens` per-lane totals are non-zero for a lane that ran agents, and `ceiling-check` inside a lane
   reads them. If part of the lane's spend cannot be counted (the main thread, for example), §14 and `ARCHITECTURE`'s
   honest limit say exactly which part.
3. **F12:** make T8's cleanup kill the whole `--follow` pipeline it started, independent of path spelling. For
   example: run `lane-feed --follow` in its own process group (`set -m` / a subshell with its own pgid) and kill the
   group; or match on a path-independent token (the fixture's unique temp dir basename) instead of `$LR2/…`; or have
   `lanes_feed --follow` trap TERM/INT/HUP and kill its own pipeline children so killing `$FP` is enough (preferred
   if it also protects real `lane-feed --follow` users who Ctrl-C a parent shell). Then sweep `test-automate-lanes.sh`
   (and the other `test-*.sh` that background a long-running command) for the same `pkill -f "<unresolved path>"`
   cleanup shape.

## Acceptance criteria
- F6: a hermetic test proves the lane park helper calls the desktop notify when the webhook is ignored, and that
  `## Progress` names what was delivered.
- F8: a fixture lane with a real-shaped SubagentStop transcript yields non-zero per-lane `TOTAL`, and `ceiling-check`
  parks a lane over its share.
- F12: after `bash loomwright/scripts/test-automate-lanes.sh` exits, no process whose command line names the
  suite's temp dir is still running (`pgrep -f <the suite's mktemp dir>` is empty) — asserted by the test file
  itself in an EXIT trap or a final leg, and shown failing on the pre-fix head. `bash scripts/ci-local.sh 2>&1 | tail
  -1` returns as soon as the suite finishes (no hang).
- The sequential path is unchanged.

## Validation (must pass before merge)
1. `bash scripts/ci-local.sh` is green.
2. The new tests, shown failing on the pre-fix head and passing on the branch. For F12, also paste
   `pgrep -fl 'tail -n \+1 -f .*L6.stream.log'` before (non-empty after one suite run on the pre-fix head) and after
   (empty after one suite run on the branch).
3. **Running system:** combine with item 23's throwaway run if both are merged before it, otherwise a one-lane
   `--parallel 2` run on a throwaway item. Paste the delivered notification line and `lane-status --tokens` showing
   non-zero lane totals.
4. Rollback: `git revert`.

## Non-goals
F3: lanes inconsistently asking the 1-item queue confirm. This is already item 21's Part B amendment 1 ("Remove
pointless questions at the source"). This run's evidence was added there. F7 is `automate-followups/37`.
