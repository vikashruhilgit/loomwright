# 04 — Park the queue on rate-limit, not on a dead worker (Orca: "before an agent stalls")

## Problem
`/automate` runs unattended for hours. When the account hits a rate-limit window, the current turn fails,
the subtask looks like a dead worker, the heal loop may retry into the same wall, and the run file records a
failure that was never about the code. Orca surfaces rate-limit proximity so the human can see it coming.
We DO record the hit after the fact — `failures.log` already carries `"error":"rate_limit"` (2 live lines,
2026-09-12 count) — but nothing CONSUMES it: `automate-helpers.sh` and `skills/automate-loop/SKILL.md` have
0 mentions of `rate_limit` or `StopFailure`.

## Honest limit (verified 2026-09-11)
There is NO local rate-limit-window file under `~/.claude` (`stats-cache.json` is a usage history last
written 2026-04-30; `policy-limits.json` is policy). Orca's "reads local usage state" is unverified for
Claude and may be an OAuth endpoint call. **Do not build on proximity until a source is verified.**
Build on the signal we HAVE: the `StopFailure` hook payload — which is ALREADY classified (corrected
2026-09-12): its `.error` field is one of `rate_limit | server_error | authentication_failed |
model_not_found | unknown`. No message-text parsing is needed for the known classes.
**Second honest limit:** every live `StopFailure` is a MAIN-session turn and the payload has no `agent_id`;
whether a worker subagent's rate-limited turn fires this hook at all is unverified (item 01 §0 probes it).
For `/automate` the main thread IS the loop, so the main-thread signal is the one that matters here; a
worker-turn hit that fires nothing is a named gap, not a solved one.

## Goal
A rate-limit failure is classified as such, the `/automate` queue PARKS with a named reason and a
resume-after time when one is derivable, and nothing retries into the wall.

## Scope
1. **Read the class, don't re-derive it.** Item 01 §3 emits `agent_lifecycle: failed` with `reason` =
   the payload's `.error` verbatim. This item consumes that `reason`. A string table over
   `last_assistant_message` exists ONLY as a fallback for `reason: unknown` (e.g. a `429` in the text) and
   its output is recorded as `reason_hint`, never promoted into `reason`.
2. **Park, fail-closed.** `automate-loop` per-item loop: on `rate_limit`, mark the item `parked:rate_limit`
   in `## Current` (awk edit — never a piped sed into `runfile-write`), append `## Progress`, stop the run
   with exit 0 and the headline. Resume is the existing smart-resume path.
3. **Park vocabulary:** `automate-helpers.sh` already parks items (`awaiting_merge`); `parked:rate_limit`
   joins THAT enumeration and its RESUME reconcile — no second park shape.
4. ~~Probe~~ — moved to `operator-run/04b-rate-limit-proximity-probe.md` (operator-run; 2026-09-12 split). Nothing in this
   item depends on its outcome.

## Non-goals
No proactive proximity gate in this item. No account switching. No retry-with-backoff (that retries into
the wall by design of the window).

## Acceptance criteria
- Fixture `agent_lifecycle: failed` line with `reason: rate_limit` → item parks; `reason: server_error` →
  today's path unchanged; `reason: unknown` + a `429` in `last_assistant_message` → `reason_hint: rate_limit`
  recorded AND the item parks (a hint is enough to stop retrying into a wall, not enough to relabel the
  fact). Mutation control: remove the `reason == rate_limit` branch, the park fixture must fail.
- `/automate` on a `rate_limit` classification parks the item with the reason in the run file and does not
  start the next item; a `network` classification follows today's path unchanged.
- `parked:rate_limit` round-trips through smart-resume's reconcile exactly as `awaiting_merge` does (test both).

## Outcomes Rubric
- Park keyed on the payload's own `.error` class; text parsing only ever yields a `reason_hint`
- Queue parks fail-closed with a named reason, no retry into the wall
- One park vocabulary (`awaiting_merge` + `rate_limit`), one reconcile

## Status: done (PR #235, merge 2ce5f5c)
