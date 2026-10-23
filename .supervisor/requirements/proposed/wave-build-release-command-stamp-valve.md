# wave-build: read the ci and release commands from stamped project config, not by fixed repo-local path

## Status: proposed

> Propose-only follow-up named by the parallel pilot report (`docs/evidence/pa07-parallel-pilot-report.md`
> §11 "Defect check (invariants)", PR #673). A source finding in the shipped tree, not a failure the 2026-10-15 run
> hit. Not enqueued. Not fixed in PR #673 (docs only).

## Problem (read 2026-10-22 against the tree at base `7b7cb08`)
`wave-build` in `loomwright/scripts/automate-wave.sh` runs this repo's own scripts by fixed path inside the wave
worktree whenever the worktree has them:
1. **ci step** (the `# 7. local CI, in the worktree` block, header step `7. ci`): `bash scripts/ci-local.sh` when
   `$wt/scripts/ci-local.sh` exists; otherwise it logs `ci — skipped (no scripts/ci-local.sh; …)`.
2. **release step** (the `# 8. release step — the LAST commit` block, header step `8. release`):
   `bash scripts/bump-version.sh` when `$wt/scripts/bump-version.sh` exists, then commits the result as the wave
   branch's last commit; otherwise it logs `release — skipped (no scripts/bump-version.sh; …)`.

`loomwright/scripts/test-wave-build.sh` legs W1f ("ci-local ran inside the temporary worktree") and W1g ("… and
bump-version in the same worktree") pin this behaviour.

Any project that happens to ship a file at either path gets it executed unattended by shipped plugin code, with no
human stamp. That is the arbitrary-shell exposure the `rules-check.sh` valve exists to close.

## Invariants it breaks
- `.supervisor/requirements/parallel-automate/00-overview.md` §"Invariants every item must preserve": "**Shipped
  plugin code never calls a repo-local path** (`scripts/…` of this repo); project-specific commands come from
  tracked project config behind the same human-stamp valve `rules-check.sh` uses."
- `.supervisor/requirements/parallel-automate/21-fleet-operations.md` Part A point 4 (origin:
  `06-wave-close-and-closeout.md` point 4, merged into 21 as Part A): "**Release command = tracked project config,
  behind the human-stamp valve.** The shipped plugin must not call this repo's `scripts/bump-version.sh`. …
  unstamped / absent ⇒ not run, recorded, never a failure. … do not invent a second valve."

No waiver for either exists.

## The valve to reuse (do not invent a second one)
`.agent/lane-policy.json` already rides the existing stamp valve (`loomwright/docs/LANE_GATES.md` §"Where a policy answer comes from", item 1 "Project policy";
`loomwright/scripts/lane-policy.sh`'s "WHEN THE PROJECT POLICY COUNTS AS STAMPED" header): a git-tracked file, bound
by a `must` rule's `binds`, counted only while `rules-check.sh --stamp-state` prints `stamp<TAB>match`
(`loomwright/skills/rules/SKILL.md` §8 / §8.1). Editing the bound file turns it off until a human re-runs
`/rules check --confirm`.

## Suggested direction
1. Read the release command (and the local-CI command) from tracked project config — for example a key in a
   git-tracked `.agent/` file bound by a `must` rule, the same shape `lane-policy.json` uses — and run it only while
   that config counts as stamped.
2. Unstamped, absent or invalid ⇒ the step is not run and says so (`ci — skipped (…)`, `release — skipped (…)`, plus
   the reason), never a failure: the wave PR's own CI stays the gate, and the owner runs the release step on the
   wave branch. Fail-SAFE for the side effect, never a silent run.
3. This repo's values: `bash scripts/ci-local.sh` and `bash scripts/bump-version.sh`, carried in that config and
   stamped by a human.
4. Tests: replace W1f/W1g's fixed-path assumption with a stamped-config leg (runs), an unstamped leg (skipped, reason
   named, red if the guard is removed) and an absent-config leg (skipped); the wave-of-one path is unchanged.
