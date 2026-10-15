# automate-speed/01 — An unanswered question must not stall a parked or curated run

## Status: pending

> Propose-only, from the timing analysis of run `automate-2026-10-13-181331` (item `verified-rule-checks`, PR #533).
> Promoted 2026-10-14 (owner); decisions resolved below.

## Source
Run `automate-2026-10-13-181331`, measured from its `## Progress` lines (UTC):
- `12:43:31 run created` → `15:31:50 AUT-QUEUE: owner chose Process` — **2h48m** with nothing running, waiting on the
  Queue confirm for a backlog doc the owner had already curated and ordered by hand.
- `20:03:50 drain READY` → `00:59:48 dismissed: drop …` / `01:00:27 parked awaiting_merge` — **4h56m** waiting on the
  dismissed-findings decision step, which runs BEFORE the park is written and the merge watcher is armed.
Together ≈ 7h45m of a 12h20m item (63%). Engine work was ≈ 4h.

## Depends on
none

## Touches
loomwright/skills/automate-loop/intake.md
loomwright/skills/automate-loop/per-item-loop.md
loomwright/skills/automate-loop/SKILL.md
loomwright/commands/automate.md
loomwright/scripts/automate-helpers.sh
loomwright/scripts/test-automate-helpers.sh
loomwright/docs/LANE_GATES.md
changelog.d/automate-speed-01-question-gates.md

## Problem
Two owner question gates block the whole run while the owner is away:
1. **`AUT-QUEUE`** (`skills/automate-loop/intake.md` §"`--limit N`") asks to confirm the Queue for every source. Its
   purpose is "a prompt that explodes into 40 files never runs silently". A `--backlog` doc the owner wrote and ordered
   is already an explicit choice; asking again adds nothing but latency. The lane carve-out (parallel-automate/21 B8)
   already accepts this reasoning for `lane-create`'s one-line backlog.
2. **Dismissed-findings decision step** (`per-item-loop.md` §"Dismissed-findings decision step (before the park)")
   holds the park until every drafted finding is decided. While it waits, the PR is mergeable but the run has not
   recorded `awaiting_merge`, the merge watcher is not armed, and no "ready to merge" notification fires. The
   decisions are about follow-up drafts, which do not change the PR. The one exception is fix-now, which re-drains it.

## Goal
A question the owner has not answered yet never holds work that does not depend on the answer.

## Scope
1. **`AUT-QUEUE` on a backlog-doc source** — per owner decision D1.
2. **Park first, then ask.** At a READY GATE with drafted dismissed findings, write the `awaiting_merge` park, arm the
   merge watcher and notify FIRST. Then ask the decisions. Fix-now stays possible only while the PR is still OPEN
   and the watcher has not closed it out. The fix-now re-drain then re-parks as today (the single-open-PR invariant
   and "fix-now at most once per item" are unchanged). Per owner decision D2.
3. Every skipped or deferred question writes one `## Progress` line naming the gate and why, like the lane's
   `skipped AUT-QUEUE:` line.

## Owner decisions (resolved 2026-10-14)
- **D1 → (b).** For `--backlog <doc>`, ask `AUT-QUEUE` only when the resolved Queue is longer than `--limit`; otherwise
  skip it and write one `## Progress` line `skipped AUT-QUEUE: backlog queue <n> ≤ limit <N>`.
- **D2 → (a).** Park first, ask after: write the `awaiting_merge` park, arm the merge watcher and notify, THEN ask the
  dismissed-findings decisions. Fix-now stays possible only while the PR is still OPEN and not closed out.
- **D3 → follow-up.** A fix-now answer given after the PR already merged becomes a follow-up draft in
  `.supervisor/requirements/proposed/` (never silently dropped), with one `## Progress` line naming it.
## Acceptance criteria
- Given a `--backlog` run under the D1 choice, when the Queue resolves, then the run asks or skips `AUT-QUEUE` exactly
  as D1 says, and a skip appends a `skipped AUT-QUEUE: <reason>` Progress line.
- Given a READY drain with ≥1 drafted dismissed finding, when GATE runs, then `## Current` reads `awaiting_merge`,
  the merge watcher marker exists and the notify fired BEFORE the first decision question is asked.
- Given the owner merges while a decision question is pending, when the watcher's `closeout` runs, then close-out
  completes and the undecided drafts stay `undecided` (`pending_decisions` set); no fix-now push follows a merge.
- Given a fix-now answer while the PR is still OPEN, when it runs, then the single re-drain and re-park behave as
  today (one re-drain, `fix_now_reentered: true`).
- `--non-interactive-fallback` and lane behaviour are unchanged.

## Validation (must pass before merge)
1. `test-automate-helpers.sh` (and any split test) legs for each criterion; report `<passed>/<total>`.
2. Mutation control: move the park write back after the decision step ⇒ the "park before ask" leg goes red.
3. Running system: one real `/automate --backlog` run in this repo; paste the Progress lines showing park-then-ask.
4. Rollback: `git revert`.

## Non-goals
- Changing what the dismissed-findings drafts contain, the threshold, or the ledger.
- Auto-answering any human-only gate.

