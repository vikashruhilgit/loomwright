# Launch Pad writes a lane-correct release rule when it plans inside an N > 1 wave lane

## Status: proposed

> Propose-only. Raised by run `automate-2026-11-01-195532` (lane L1, PR #781, 2026-11-01). Not enqueued.

## Problem (read 2026-11-02 against `main` at `38eb8e4`)
Inside a `--parallel 3` lane, Launch Pad saved a brief whose subtask 2 listed
`{kind: "symbol", path: "CHANGELOG.md", name: "heal_review_scope"}` under `provides`
(`.supervisor/jobs/done/2026-11-01-phase45-re-review-converges-on-last-fix.md`, subtask 2 `provides`). Only a
version bump writes `CHANGELOG.md`, and lane PRs in an N > 1 wave carry `changelog.d/` fragments only; `wave-build`
makes the one bump (CLAUDE.md §"`/automate` single-drain ownership", `changelog.d/README.md` §"Who runs the bump").
The worker bumped to v17.25.0 to satisfy the contract. Supervisor reverted the bump, then stopped at a
`SUP-ADJ-GAP` adjudication, which cost an owner question mid-run (the owner chose "D: Update consumer brief").

Root cause: the planning side has no idea it is in a lane.

- `loomwright/agents/launch-pad.md`, `loomwright/commands/launch-pad.md` and
  `loomwright/skills/supervisor-readiness/SKILL.md` contain no `lane-info` / `lane.json` read.
- The guidance they do carry points the wrong way for a lane. `supervisor-readiness/SKILL.md` (the "A provides
  entry must still exist when its subtask completes" bullet) and `agents/plan-reviewer.md` (the "Outputs that
  survive the subtask" check and its HIGH finding) both say: if a subtask runs the version bump, name the folded
  `CHANGELOG.md` entry instead of the fragment. That is right for a sequential run and wrong in a wave lane.
- `agents/plan-reviewer.md` does note that "a lane subtask that never bumps lists the fragment correctly", but
  nothing tells the brief author or the reviewer that this brief IS a lane brief.

## Invariants to keep
- Lane PRs in an N > 1 wave never bump; `scripts/check-version-bump.sh` passes unbumped with the fragment pending.
- Single-lane mode (`--parallel 1`) and sequential runs are unchanged: they still bump in their own PR.
- One authority for "am I in a wave lane": `automate-helpers.sh lane-info` exit 0 and a `lane.json` without
  `"single_lane": true` (the same predicate `lane-park` uses). Never a second detector.

## Suggested direction
1. Launch Pad reads that predicate once at Phase 1, and the brief records it (e.g. a `release: lane-fragment-only`
   line in its header, or a `## Release` subsection).
2. In a lane-fragment-only brief, the readiness skill tells the author: provide the `changelog.d/<slug>.md`
   fragment, never `CHANGELOG.md`, `plugin.json` or `marketplace.json`, and no subtask runs `bump-version.sh`.
   The release acceptance criterion reads "`bash scripts/check-version-bump.sh` passes (not bumped, fragment
   pending)".
3. Plan Reviewer: in a lane-fragment-only brief, a `provides` or step naming `CHANGELOG.md`, a version file or a
   bump is a HIGH finding.

## Tests
- A brief-shape fixture planned in a wave lane: a `CHANGELOG.md` provides entry is flagged HIGH, and a fragment
  provides entry passes.
- The same brief outside a lane: unchanged behaviour (the folded-`CHANGELOG.md` guidance still applies).
- A single-lane `lane.json` behaves like the sequential case.
- Mutation control: drop the lane predicate ⇒ the wave-lane leg turns red.

## Likely touches
`loomwright/agents/launch-pad.md`, `loomwright/commands/launch-pad.md`, `loomwright/agents/plan-reviewer.md`,
`loomwright/skills/supervisor-readiness/SKILL.md`, a seam test under `loomwright/scripts/`,
`loomwright/docs/prompt-token-budgets.json` (and the mirror rows)
