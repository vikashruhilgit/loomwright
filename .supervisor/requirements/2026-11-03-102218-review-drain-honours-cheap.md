# The /review-pr drain honours --cheap

## Status: pending

**Story: The /review-pr drain honours --cheap** (type: story)

**As a** plugin owner running `/automate --cheap` or `/review-pr` directly,
**I want** the review drain's reviewer and fix spawns to run on the Sonnet cost profile when I ask for it,
**so that** the most spawn-heavy phase of an item is not the one phase `--cheap` never reaches.

## Problem

The `/automate` driver spawns the owned drain and the fix-now re-drain as
`/review-pr $PR --until-mergeable --no-auto-postmortem`, with no cost flag. `/review-pr` (`commands/review-pr.md`,
`skills/review-heal/SKILL.md`) has no `--cheap` at all. So up to `--max-rounds` (default 5) drain rounds, each with
up to 3 heal iterations of reviewer and fix spawns, run at full cost even when the owner passed `--cheap`.

## Evidence (verified 2026-11-03)

- `docs/ARCHITECTURE_CONTRACTS.md` §"Cost Profiles" lists the `--cheap` roles (worker, code-reviewer,
  execute-manager, orchestrator, Phase 4.5 fix task and multi-voter voters → sonnet) and has no row for the drain's
  reviewer or fix spawns. The drain is uncovered, not deliberately excluded.
- The three drain spawn sites in `scripts/automate-next-step.sh` (owned drain prompt, owned drain instruction,
  fix-now re-drain) all print `/review-pr $PR --until-mergeable --no-auto-postmortem` with no further flags.

## Goal

`/review-pr --cheap` runs its execution-shaped spawns on Sonnet, and `/automate` passes it whenever the run is in
cheap mode.

## Scope

- `/review-pr` accepts `--cheap`. Under it, the drain's code-reviewer review spawn, its fix task spawn, and the
  Earned Fallback Review spawn run on `model: "sonnet"` through the spawn-time Task `model` parameter. No agent
  frontmatter changes. Without the flag nothing changes.
- The `/automate` driver adds `--cheap` to both drain spawns (owned drain and fix-now re-drain) whenever cheap mode
  is on, sequential or lane.
- `docs/ARCHITECTURE_CONTRACTS.md` §"Cost Profiles" gains the drain rows in the same change. Every surface that
  restates that table is updated together or replaced with a pointer (house rule on restated lists).
- `agents/review-pr-runner` prose (if it restates the flag list) is synced with `commands/review-pr.md` in the same
  change.

## Non-goals

- Persisting `--cheap` across resumes (the companion story
  `2026-11-03-102216-cheap-is-honoured-end-to-end-in-automate-runs.md`).
- Changing which Supervisor or Phase 4.5 roles `--cheap` covers.
- CI `claude-review` triggers, model or effort; the `fix_floor` default; the Phase 4.5 executing-lens scope.

## Owner decisions (2026-11-03)

- The owner ruled that `--cheap` not reaching the drain is a bug.

## Acceptance criteria

**Happy path:**
- [ ] Given an `/automate` run in cheap mode, when the driver prints the owned-drain spawn and the fix-now re-drain
      spawn, then each invocation is `/review-pr <pr> --until-mergeable --no-auto-postmortem --cheap` (driver test
      in `scripts/test-automate-next-step*.sh`).
- [ ] Given `/review-pr --cheap`, when review-heal spawns its reviewer, fix and Earned Fallback Review tasks, then
      each spawn carries `model: "sonnet"` (test or pinned prose check, whichever review-heal's existing tests use).

**Edge cases:**
- [ ] Given an `/automate` run not in cheap mode, when the driver prints the drain spawns, then none carries
      `--cheap`.
- [ ] Given `/review-pr` without `--cheap`, when it spawns, then no spawn sets `model`.
- [ ] Given a lane created with `--cheap`, when the lane reaches its drain, then the drain spawn carries `--cheap`.
- [ ] Given a drain spawn routed through `lens-run.sh` (a Bash shell-out, not a Task spawn), when `--cheap` is on,
      then the Cost Profiles table marks it N/A the same way it does for routed voters, and nothing errors.

**Error scenarios:**
- [ ] Given `/review-pr` with an unknown cost flag, when it parses its arguments, then it refuses with its existing
      unknown-flag error rather than ignoring it.

## Validation (must pass before merge)

- `bash scripts/ci-local.sh --affected` passes, including `check-token-budget.sh` (budget entries raised in
  `loomwright/docs/prompt-token-budgets.json` and the mirror table if `commands/review-pr.md` or
  `skills/review-heal/` grow), `check-doc-currency.sh` and `check-prompt-history-refs.sh`.
- `bash scripts/check-version-bump.sh` passes; the PR carries a `changelog.d/` fragment and no hand-edited version.

### Priority
- [x] MVP - Core functionality, must ship

**Rationale:** the drain is the most spawn-heavy phase per item (up to 5 rounds × 3 heal iterations).

### Assumptions
- The drain's reviewer and fix spawns go through the Task tool, so the `model` parameter applies.
- The coordinator and drain sessions' own models stay as configured (`coordinator_model`); this changes only the
  spawns inside the drain.

### Dependencies
- Depends on: `2026-11-03-102216-cheap-is-honoured-end-to-end-in-automate-runs.md` (the driver's cheap-mode rule)
- Blocks: none

### Risks
- Sonnet as the drain reviewer may raise or miss findings differently than the session model. `--cheap` is opt-in,
  so the default path is unchanged.

### Success Metrics
- A `--cheap` run's drain-phase tokens (`read-token-ledger.sh --per-item`) drop compared with a `--cheap` run from
  before this change.

### Handoff
Ready for: `/automate --backlog .supervisor/requirements/2026-11-03-102218-review-drain-honours-cheap.md`

## Depends on
2026-11-03-102216-cheap-is-honoured-end-to-end-in-automate-runs.md

## Touches
loomwright/scripts/automate-next-step.sh
loomwright/scripts/test-automate-next-step.2.sh
loomwright/commands/review-pr.md
loomwright/skills/review-heal/SKILL.md
loomwright/skills/review-heal/fallback-review.md
loomwright/docs/ARCHITECTURE_CONTRACTS.md
loomwright/docs/prompt-token-budgets.json
changelog.d/
