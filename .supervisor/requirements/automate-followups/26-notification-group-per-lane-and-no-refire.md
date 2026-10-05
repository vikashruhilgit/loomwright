# 26 — Desktop notifications at fleet scale: one group per session, one banner per question

## Status: pending

## Problem
Verified in S1 v2 (2026-10-04) from the lanes' own logs and an owner-confirmed banner test:
- **One group for everything.** `scripts/notify-desktop.sh` passes a fixed `-group "loomwright"` to
  `terminal-notifier`, so every new notification removes the previous one from Notification Center, whichever
  session or lane sent it (v2-a's `notifications.log` removes notifications sent at v2-b's ask times). With 5–10
  lanes, a question that is still waiting loses its notification as soon as another lane asks.
- **Two notifications per question.** The `PreToolUse[AskUserQuestion]` hook fires once when the lane asks and
  again when the resumed session replays the same tool call to deliver the answer (v2-a: 8 `waiting / ask_user`
  rows for 4 questions; v2-b: 10 for 5). The second banner arrives after the owner has already answered.
- (Banners were invisible during S1 only because macOS Do Not Disturb was on; delivery itself worked.)

## Goal
Each session (lane) keeps its own latest notification, and each question produces exactly one banner, at ask time.

## Scope
1. **Group per session:** `-group "loomwright-<short session id>"` (fallback: a hash of the checkout path when no
   session id). Same-session bursts still coalesce; different lanes no longer erase each other.
2. **No re-fire on resume:** record each notified `tool_use_id` in `.supervisor/logs/.notified-ids` (bounded,
   newest 200); a `PreToolUse[AskUserQuestion]` payload whose `tool_use_id` was already notified exits 0 without a
   banner. Apply the same de-duplication to `emit-lifecycle.sh`'s `waiting / ask_user` row, or mark the replay row
   `replay: true`, so lane dashboards count questions correctly.
3. **Fail-safe stays:** both scripts keep exiting 0 on every path (bimodal rule); a missing id file means "notify".
4. **Tests:** two sessions produce two groups; the same `tool_use_id` twice produces one banner and one counted
   waiting row; a missing session id falls back to the path hash; debounce behaviour unchanged.

## Acceptance criteria
- In S2 (five lanes), Notification Center holds one entry per lane with a pending question, and the per-lane
  question count equals the number of asks.

## Validation (must pass before merge)
1. Baseline full loop, `<passed>/<total>` and `SKIP` counts, base and branch.
2. Unchanged path: a single interactive session still gets one banner per question (test).
3. Running system: two sessions each raise a question; paste both lanes' `notifications.log` lines showing distinct
   groups and no re-fire on resume.
4. A failure this must catch: revert to the fixed group ⇒ the two-session test fails.
5. Rollback: `git revert`.

## Evidence
S1 run record (banner investigation and "Park-notification evidence"); archived logs
`ai-agent-manager-lanes-v2/archive/v2-{a,b}/logs/`.

## Depends on
none

## Touches
loomwright/scripts/notify-desktop.sh
loomwright/scripts/test-notify-desktop.sh
loomwright/scripts/emit-lifecycle.sh
loomwright/scripts/test-emit-lifecycle.sh
changelog.d/automate-followups-26-notification-group-per-lane-and-no-refire.md

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-05T01:59:01Z
- **Brief:** .supervisor/jobs/done/2026-10-05-notification-group-per-lane-and-no-refire.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/386
