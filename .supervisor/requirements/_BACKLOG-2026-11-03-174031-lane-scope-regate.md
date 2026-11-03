# Lane scope re-gate (issue #808) — plan doc (index document, not an implementable item)

## Status: done (index document — nothing to implement)

## Why now
Issue vikashruhilgit/loomwright#808: `/automate --parallel` plans waves from declared `## Touches` lists that miss
the existing shared files a story plugs into. In loomwright-studio run `automate-2026-11-02-150636` wave 3, items
05 and 06 grew from 11 to 26 and from 10 to 25 files during Launch Pad. Item 06 alone asked about files outside its
Touches four times under four headers, one of them folded into a save question, and nothing re-checked the wave,
so two lanes edited `kernel.ts`, `sessions/policy.ts`, `triggers/poll.ts` and a shared test in parallel. Wave 2
(PR #221) had already reported 3 files changed by 2+ lanes.

## Owner decisions
none recorded

## Order
| Item | Delivers | Depends on | Can run in parallel with |
|---|---|---|---|
| 2026-11-03-174840-lane-scope-regate | Part A: one catalog question for files outside Touches, never folded into a save question; improvised questions use `LP-CLARIFY`. Part B: lanes held at the end of Launch Pad until the coordinator checks overlap; one owner question on overlap | none | none (shares the token-budget and contracts files) |
| 2026-11-03-174031-touches-name-shared-files-at-intake | Product Owner lists the existing shared files and contract changes in Touches; points writers at `.agent/companions.json` | none | none (shares the token-budget and contracts files) |

The first row merges the two original stories (owner decision 2026-11-03, via `merge-items`); the originals
`2026-11-03-174029-one-question-for-files-outside-touches.md` and
`2026-11-03-174030-re-check-lane-overlap-before-coding-starts.md` are parked as its Parts A and B.

## Run
/automate --backlog .supervisor/requirements/_BACKLOG-2026-11-03-174031-lane-scope-regate.md
Safe mode, sequential: two jobs, two PRs. The two items conflict on `loomwright/docs/prompt-token-budgets.json` and
`loomwright/docs/ARCHITECTURE_CONTRACTS.md`, so `--parallel` buys nothing. The intake story stays separate so a
problem in the lane re-gate does not hold it back, and so the merged item keeps headroom under the 30-file size
limit. No new follow-up items beyond these two.

## Considered and not queued
- `plan-waves --lint --deep`: nothing deterministic can know where a feature registers.
- A separate `touches_effective` field in `lane.json`: a second copy of the lane's set; the saved brief read through
  `_lanes_declared` already is that set.
- Planning every wave from saved briefs (Launch Pad on every item before any wave runs): removes the root cause, but
  costs one Launch Pad run per item up front, and later-wave briefs go stale as earlier waves merge.
- Making the new scope question `allowed` (lane-policy answerable) now: only after the re-gate story ships.
- loomwright-studio `.agent/companions.json` rules for its shared kernel files: owner's task in that repo, not this one.

## Revisit when
A wave-build reports `overlap` files after the re-gate story has shipped, or a lane asks about files outside its
Touches under any header other than the new catalog code.

## Checklist
- [ ] .supervisor/requirements/2026-11-03-174840-lane-scope-regate.md
- [ ] .supervisor/requirements/2026-11-03-174031-touches-name-shared-files-at-intake.md
