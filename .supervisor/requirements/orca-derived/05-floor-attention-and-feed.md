# 05 — Floor: attention columns + catch-up feed (Orca: Agent Dashboard + Agents feed)

## Problem
The Floor renders one lane per agent as *event count + last-event age* under a permanent
"liveness unavailable" note. It cannot say the one thing an operator needs at a glance — is anything
waiting on me — and it cannot say what happened while they were away. Orca's dashboard answers both
from the same hook signals; item 01 makes those signals recorded facts here. Also: FLOOR_UI.md §"What it
does not claim" says "No spawn event exists in any log" — stale since `agent_identity` shipped.

## Goal
Lanes are grouped by derived state — **Needs you · Working · Done · Quiet** — with the honesty stance kept
(every state is "as of the last recorded event, N s ago"); plus a newest-first feed of the events the log
already holds, with previews and per-tab unread.

## Scope
1. **Projector:** `build-floor.sh` adds `sessions.detail.current.agents[].lifecycle` (`state`, `since_epoch`,
   `reason`, `last_checkpoint` from item 03's `worker_checkpoint`, `ended_without_result`) — derived per item
   01 §4. `since_epoch` for a spawn comes from `agent_identity.recorded_at` (that row carries no `ts` by design
   — `RESULT_SCHEMAS.md` §FLOOR_PROJECTION `identified_at`; a `ts`-keyed reader drops it silently); every
   other state's `since_epoch` comes from a real event `ts`. A lane with no lifecycle row at all stays
   `unknown`, never `Quiet`; `ended_without_result` is tri-state (`true`/`false`/absent) exactly as 01 §4 derives it.
2. **Render:** four groups in the Lanes section, `Needs you` first and non-empty groups only; the group
   heading carries the derivation rule in words. Replace the permanent liveness note with "state is inferred
   from the last recorded hook event; a lane can be `Working` and dead" — the claim shrinks, it does not
   disappear.
3. **Feed:** a section listing `subtask_complete` (a worker ended; corrected 2026-09-12 — there is no
   `agent_result` event), `agent_lifecycle:waiting/failed`, `worker_checkpoint`, `pr_created`,
   `self_heal_iteration`, `review_heal_done`, `autonomous_done` newest-first with `last_assistant_message`
   preview when the projector carries it. `token_ledger` (13k lines) is deliberately NOT a feed event — it is
   the same stop moment as `subtask_complete` for non-worker roles and would drown the feed; the projector
   folds it into the lane's lifecycle instead. unread = newer than the last-seen `ts` kept in `sessionStorage`
   beside the token (same lifetime rules). Filter box, no ranking by anything but time.
4. **Doc fix:** FLOOR_UI.md non-claims section updated (spawn events exist; liveness claim rewritten);
   `FLOOR_PROJECTION` schema bump; fixtures for each of the four groups + an `unknown` lane.

## Non-goals
No push/SSE (the 2 s poll stays); no notifications from the page (`notify-desktop.sh` owns that); no write
endpoints beyond the existing four; no framework; no remote asset (CSP `default-src 'self'` unchanged).

## Acceptance criteria
- Fixture with one `waiting` lane, one heartbeat-fresh lane, one `done`, one 40-min-quiet, one with no
  lifecycle row → renders 4 groups + `unknown` label; the stale-fixture `?stale=` convention still applies.
- `test-setup-ui.sh`'s GET-byte-identity assertion for the server still holds (page changes only).
- Feed unread survives reload in the same tab and resets in a new tab (mirrors the token test).
- `check-doc-currency.sh` green after the schema bump.

## Outcomes Rubric
- Four derived groups with the rule stated on the page; `unknown` never collapsed into `Quiet`
- Liveness claim rewritten, not deleted
- Feed is time-ordered only, previews from the projection, unread per tab
- Stale non-claim in FLOOR_UI.md corrected

## Status: done (PR #236, merge ee31cc2)
