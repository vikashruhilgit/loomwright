# Lane resume and close-out gaps (#964) — plan doc (index document, not an implementable item)

## Status: done (index document — nothing to implement)

## Why now
One `/automate --parallel 3` run on loomwright 18.1.2 (issue vikashruhilgit/loomwright#964) hit three gaps in how a lane comes back after a pause:
- A held lane built a requirement the owner had already replaced. The drift showed only at wave end, as a meta-push conflict, after a full build, drain and PR.
- A lane whose PR the owner merged by hand while it was `escalated` (or dead mid-phase) could not be closed out. Its Queue rows and the primary's run lock stayed open.
- A killed Supervisor phase was re-planned from a fresh Launch Pad, throwing away finished subtasks.

All three are checked against origin/main (c9fd2f8).

## Owner decisions
none recorded

## Order
| Item | Delivers | Depends on | Can run in parallel with |
|---|---|---|---|
| 01 held-lane-checks-requirement-drift | a held or resumed lane stops before building on a changed requirement | none | none |
| 02 killed-supervisor-phase-resumes | a killed Supervisor phase resumes on its brief instead of re-planning | 01 | 03 |
| 03 lane-with-hand-merged-pr-closes-out | a lane whose PR the owner merged by hand is closed out by the engine | 01 | 02 |

## Run
/automate --backlog .supervisor/requirements/_BACKLOG-2026-11-21-053300-lane-resume-and-closeout-gaps.md --parallel 2
Safe mode (no --auto-merge). No new follow-up items from these runs without the owner's go.
Why N=2: the widest wave is 2. Item 01 changes `automate-next-step.sh` (shared with 02) and the lane docs, gate catalog and lane policy (shared with 03), so it runs alone first. 02 and 03 have disjoint Touches.
wave 1: 2026-11-21-045234-held-lane-checks-requirement-drift-before-it-builds.md
wave 2: 2026-11-21-052813-killed-supervisor-phase-resumes-instead-of-replanning.md, 2026-11-21-052813-lane-with-hand-merged-pr-closes-out.md
Serialisations:
- 02 waits on 01: both edit loomwright/scripts/automate-next-step.sh and its tests.
- 03 waits on 01: both edit skills/automate-loop/lanes.md, docs/LANE_GATES.md, docs/ARCHITECTURE_CONTRACTS.md, lane-policy.sh and automate-lanes.sh.
Hotspots:
- loomwright/docs/prompt-token-budgets.json: owned by 01 in wave 1 and by 03 in wave 2. Item 02's scope note tells it to leave the file alone.
- changelog.d: each item declares only its own fragment file, so the fragments never collide.
No companions rule proposed.

## Considered and not queued
- Merging 01 and 02 into one item with two parts (they share the driver file): `right-size` read it as large (34 files, will not fit one PR), so they stay separate and run in order.
- #942 (a PR opened by FINALIZE orphaned before the Supervisor hand-back): related to 02 but a different case (after the PR opens). It changes the same driver area, so it should not join wave 2 alongside 02.
- #710 (an `escalated` `check_red` park never re-gates after CI turns green): related to 03 but a different case (open PR). Not queued here.

## Revisit when
A lane run shows another resume or close-out path that builds on stale input or never closes. Or #942 is picked up, which must then be sequenced after 02.

## Checklist
- [ ] .supervisor/requirements/2026-11-21-045234-held-lane-checks-requirement-drift-before-it-builds.md
- [ ] .supervisor/requirements/2026-11-21-052813-killed-supervisor-phase-resumes-instead-of-replanning.md
- [ ] .supervisor/requirements/2026-11-21-052813-lane-with-hand-merged-pr-closes-out.md
