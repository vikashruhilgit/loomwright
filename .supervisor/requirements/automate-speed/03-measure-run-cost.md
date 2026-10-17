# automate-speed/03 — Per-item cost report: tokens, turns, peak context and wall time for every /automate item

## Status: pending

## Problem
Nobody can see what an `/automate` item costs. The token ledger records a transcript-bytes proxy per stopping
agent, and `/insights` shows per-session context size, but neither answers "what did item X cost, and where".
The numbers behind this whole queue had to be computed by hand from `~/.claude/projects` transcripts on
2026-10-15 (plan doc §Why now):
- Main-thread sessions held **68%** of all context tokens over 7 days (110 sessions, ~104 turns each, ~380K context
  re-read per turn, peaks 750–858K; 1 compaction in 110 sessions).
- Lane item sessions: median 65M main-session tokens, 146 turns, 647K peak. Inline `/automate` sessions: 54M, 160
  turns, 494K peak.
- PR #533: Launch Pad 13m, build 40m, Phase 4.5 85m, drain 2h11m for one round.
Every later item in this set claims a saving. Without a committed, repeatable measurement those claims cannot be
checked.

## Goal
<!-- bump: minor -->
One read-only command reports, per `/automate` item (and per phase inside it): context tokens (input + cache
creation + cache read), output tokens, turns, peak context, subagent tokens by agent type, and wall time — read
from the real per-message `usage` fields in the session transcripts, not the bytes proxy. A committed baseline
file records today's numbers so later items are measured against them.

## Scope
- Extend the existing readers; do NOT add a parallel tool. `read-token-ledger.sh` gains a per-item report mode keyed
  by run id + item (it already finds every session of a run via the `session_id` Progress lines);
  `build-insights.sh` shows the same per-item table.
- Read `usage` per assistant message, de-duplicated by message id (one message is written to the transcript several
  times). Main session and `subagents/agent-*.jsonl` (agent type from the `.meta.json` sidecar) are reported
  separately. Lane sessions (`*-lanes-automate-*` project dirs) are included.
- Phase attribution from the run file's pinned `## Progress` timestamps (picked → launch-pad saved → FINALIZE →
  Phase 4.5 iterations → drain started → drain READY/ESCALATED → park).
- Write `docs/evidence/automate-speed-baseline.md` with the report for the last 7 days and for run
  `automate-2026-10-13-181331` (PR #533). Include the exact command used.
- Label every figure: real usage tokens vs proxy. Fail SAFE (exit 0, named reason on stderr) when transcripts are
  missing; never print a zero that reads as "cheap".

## Non-goals
- Dollar cost. Tokens only (the owner runs on a subscription).
- Changing what the ledger emits at SubagentStop.
- Any per-item budget enforcement (`--max-tokens` already exists).

## Owner decisions (from _BACKLOG.md)
- D5: Phase 0 lands before any Phase 1 prose is deleted; this report is the baseline every later item is measured
  against.

## Acceptance criteria
- Given a run id, when `read-token-ledger.sh --per-item <runfile>` runs, then it prints one row per item with
  context tokens, output tokens, turns, peak context, subagent tokens by type and wall time, and one row per phase
  under each item.
- Given a transcript where one message id appears 3 times, then its usage is counted once (fixture test).
- Given a lane run, then the lane clone's sessions are attributed to the lane's item.
- Given no transcripts for a run, then the command exits 0, prints a named `no_transcripts` reason and no number.
- `/insights` renders the same per-item table.
- `docs/evidence/automate-speed-baseline.md` exists, contains the command and its output for PR #533's item and the
  7-day window, and the PR body links to it.

## Validation (must pass before merge)
1. `test-read-token-ledger.sh` and `test-insights.sh`; report `<passed>/<total>`.
2. Mutation control: drop the message-id de-duplication ⇒ the duplicate-message fixture goes red.
3. Running system: run the per-item report on `automate-2026-10-13-181331`; paste the rows into the PR body. The
   drain row must show ~2h11m wall time (matches the run file's Progress lines).

## Depends on
none

## Touches
loomwright/scripts/read-token-ledger.sh
loomwright/scripts/test-read-token-ledger.sh
loomwright/scripts/token-ledger-fixtures/
loomwright/scripts/build-insights.sh
loomwright/scripts/test-insights.sh
loomwright/docs/OBSERVABILITY.md
docs/evidence/automate-speed-baseline.md
changelog.d/as03-measure-run-cost.md

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-17T03:46:40Z
- **Brief:** .supervisor/jobs/done/2026-10-16-as03-measure-run-cost.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/570
