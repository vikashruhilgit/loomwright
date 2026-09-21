# 04 — Mechanized scoped wait + detection of a drain that exited without a result

## Status: pending

## Problem
`skills/review-heal/SKILL.md` §"Wait-For-Settled-Checks" is pseudocode (`sleep(poll_interval); re-read
statusCheckRollup` at ~333 and 561–577) executed by the model. Under `claude -p` the model's habit is to start a
background poll and end its turn ("I'll wait for the background poller to notify me…") — and the turn end IS
process exit: the wrapper trap (`dispatch-pr-review.sh` ~589–612) then salvages + removes the worktree and
lock, and nothing records that no `REVIEW_HEAL_RESULT` was ever produced. On this checkout: 35 markers, 4
READY, 5 ESCALATED, 26 no decision; five logs from 2026-09-17 alone end mid-wait. Memory
`drain-dies-before-ci-review-settles` records the symptom; it recurred five times in one day. The marker file
still reads as "dispatched" (memory `drain-dispatch-state-from-marker-not-belief`), so every downstream
consumer — `/automate`'s owned drain, `session-resume.sh`, the postmortem gather — believes a drain ran.

## Goal
The wait is a single foreground script call with a hard bound; a runner that exits without a terminal
`REVIEW_HEAL_RESULT` is recorded as DIED (marker, log, notification, SessionStart surfacing) and never mistaken
for a completed drain; the runner prose forbids background polling in so many words.

## Scope
1. **New `scripts/wait-for-checks.sh <pr_url> --sha <sha> --bound <seconds> [--interval <s>]
   [--required-only | --review-check-pattern <glob>]`** — foreground, blocking, prints ONE final line
   `SETTLED sha=<sha> required=<green|red> review_producing=<settled|elapsed>` or `ELAPSED …`; exit 0 always.
   Implements §U2/§U2.5 exactly (rollup-for-OUR-sha check, re-created-check wait, required-context
   discovery) so the prose can point at the script instead of restating the loop. Bash 3.2 / BSD safe (no
   `timeout`; bound by `$SECONDS`). Fixture-driven test `test-wait-for-checks.sh` with a `$GH` stub that
   returns a scripted sequence of rollups (pending→green, pending→red, wrong-sha→right-sha, never settles).
2. **`skills/review-heal/SKILL.md`:** every `sleep(poll_interval)` pseudocode block becomes a call to
   `wait-for-checks.sh` **run in the FOREGROUND** with this exact sentence beside it: "Never run this wait in
   the background and never end the turn while waiting — under `claude -p` ending the turn ends the process
   and the drain dies with no result." Add `background_wait` to the §"Anti-patterns" list. Same sentence in
   `agents/review-pr.md` (re-measure token budget).
3. **Death detection — `dispatch-pr-review.sh` wrapper trap:** after the runner exits, `grep -q
   'REVIEW_HEAL_RESULT' "$_log"`; if absent, write `<hash>.died` beside the marker with
   `ts`, `pr_url`, `exit_code`, `last_log_line` (tab-separated, via printf), append a `DRAIN_DIED` line to the
   run log, and fire `notify-desktop.sh` + `send-webhook.sh` best-effort (fail-safe). The `.died` marker is
   removed only by a later dispatch of the same PR that reaches a result. Marker semantics documented in
   `review-heal/SKILL.md` §"Detached dispatch" and `docs/OBSERVABILITY.md`.
4. **Re-dispatch policy:** `dispatch-pr-review.sh` treats `<hash>` marker + `<hash>.died` as "not
   dispatched" for the purpose of the `MARKER exists ⇒ skip` check (so the hook backstop can re-dispatch
   once); a second death for the same PR writes `<hash>.died` with `attempt=2` and is NOT re-dispatched
   automatically (bounded).
5. **Surfacing:** `session-resume.sh` lists `.supervisor/review-dispatch/*.died` under a "Drains that died
   without a result" heading (bounded to 5, inside the 8 KB cap); `/automate` RECONCILE (§4) treats a `.died`
   for the current item's PR as `owned_drain_result: died` ⇒ PARK `escalated` with `pause_reason: drain_died`
   (never `awaiting_merge`); `status-line.sh` shows a `⚠ drain died` cell when present.
6. **Docs:** HOOKS.md (PostToolUse dispatch row), ARCHITECTURE_CONTRACTS.md dispatch-shape cell, PITFALLS.md
   ("dispatched ≠ completed" now has a marker), CHANGELOG, bump.

## Non-goals
No change to bounds (`--max-rounds`, check-wait timeout defaults), no auto-retry beyond one, no change to
salvage. Does not fix item 01's permission regime (sequenced after it; both edit the same two files).

## Acceptance criteria
- `test-wait-for-checks.sh`: four scripted sequences produce `SETTLED`/`ELAPSED` lines as specified; a
  rollup for a different SHA is never treated as settled; the bound is honoured within one interval.
- `test-dispatch-pr-review.sh`: with a stub `claude` that exits without printing `REVIEW_HEAL_RESULT`, the
  `.died` marker exists with the four fields and the log carries `DRAIN_DIED`; with a stub that prints a
  result, no `.died`; a second death for the same PR carries `attempt=2` and a third dispatch is refused.
  **Mutation control:** delete the trap grep → the first case must fail.
- `grep -n 'sleep(poll_interval)' skills/review-heal/SKILL.md` → 0; `grep -c 'wait-for-checks.sh'` ≥ 3.
- `session-resume.sh` output (fixture with two `.died` files) shows the heading and both PR URLs.
- Full test loop + root checks green.

## Verified premises
- Wrapper trap text in `dispatch-pr-review.sh` (salvage → `worktree remove --force` → `rm -rf` lock).
- `review-heal/SKILL.md` lines ~333, 561–577 pseudocode; §U2/§U2.5 recipes; `--check-wait-timeout` and
  `LOOMWRIGHT_CHECK_WAIT_TIMEOUT` forwarding.
- `.supervisor/logs/review-pr-dispatch-*.log` tails on 2026-09-17 (five "waiting" endings).
- `session-resume.sh` MAX_CHARS=8000; `automate-loop/SKILL.md` §4 RECONCILE and §9 park reasons.
