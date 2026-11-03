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
| 2026-11-03-174029-one-question-for-files-outside-touches | One catalog question for files outside Touches, never folded into a save question; improvised questions use `LP-CLARIFY` | none | none (shares the token-budget and contracts files with both others) |
| 2026-11-03-174030-re-check-lane-overlap-before-coding-starts | Lanes held at the end of Launch Pad until the coordinator checks overlap; one owner question on overlap | 2026-11-03-174029-one-question-for-files-outside-touches | none |
| 2026-11-03-174031-touches-name-shared-files-at-intake | Product Owner lists the existing shared files and contract changes in Touches; points writers at `.agent/companions.json` | none | none (shares the token-budget and contracts files) |

## Run
/automate --backlog .supervisor/requirements/_BACKLOG-2026-11-03-174031-lane-scope-regate.md
Safe mode, sequential. `plan-waves --max 2` gives three single-item waves: the second depends on the first, and the
third conflicts with both on `loomwright/docs/prompt-token-budgets.json` and `loomwright/docs/ARCHITECTURE_CONTRACTS.md`,
so `--parallel` buys nothing. No new follow-up items beyond these three.

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
- [ ] .supervisor/requirements/2026-11-03-174029-one-question-for-files-outside-touches.md
- [ ] .supervisor/requirements/2026-11-03-174030-re-check-lane-overlap-before-coding-starts.md
- [ ] .supervisor/requirements/2026-11-03-174031-touches-name-shared-files-at-intake.md
