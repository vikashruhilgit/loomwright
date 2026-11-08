# --cheap is honoured end to end in /automate runs

## Merged from (2026-11-05)
- Part A: `2026-11-03-102216-cheap-is-honoured-end-to-end-in-automate-runs.md` — --cheap survives resume in sequential /automate runs
- Part B: `2026-11-03-102218-review-drain-honours-cheap.md` — The /review-pr drain honours --cheap

The originals are parked with a pointer here. Their text is kept below VERBATIM as parts (headings
demoted one level, their Status / Depends on / Touches folded into this file's own sections). Nothing was paraphrased.

## Goal
A run started with --cheap stays on the Sonnet cost profile across every --resume and through the /review-pr drain, until the owner turns it off with --no-cheap.

## Part A — --cheap survives resume in sequential /automate runs

**Story: --cheap survives resume in sequential /automate runs** (type: story)

**As a** plugin owner who starts an `/automate` run with `--cheap` to save tokens,
**I want** the Sonnet cost profile to stay on across every `--resume` until I turn it off,
**so that** a run I asked to be cheap is never silently charged at the full-cost profile.

### Problem

`scripts/automate-next-step.sh` sets cheap mode only from its own command line, or, inside a lane, from
`.supervisor/lane.json` `"cheap": true` (the line next to the comment "inside a lane, `--cheap` also comes from the
lane's own record"). It never reads it back from the run file. `--max-tokens`, by contrast, falls back to
`## Run Config`'s `- max_tokens:` line at every spawn site, so a bare `/automate --resume` keeps the token ceiling
but silently drops the cost profile. `commands/automate.md` documents this as a warning on the `--cheap` and
`--resume` rows ("omitting it silently reverts the remaining queue to the full-cost profile"). A warning does not
prevent it.

### Evidence (verified 2026-11-03)

- Lanes were fixed in v17.21.1 (`lane-create --cheap` writes `lane.json` `"cheap": true`). That release says "A
  sequential run's `--cheap` stays passthrough-only and is still not written to `## Run Config`."
- The original reason for not persisting it (v15.2.0) was only "same convention as `--notify` /
  `--non-interactive-fallback`". Those two depend on the session that runs. `--cheap` describes the run, like
  `--max-tokens`, which red-team-hardening/06 deliberately persisted so that a bare `--resume` still enforces it.

### Goal

`--cheap` given once at the start of a sequential `/automate` run applies to every spawn the driver prints for the
rest of that run, until the owner explicitly turns it off.

### Scope

- The run file's `## Run Config` records `- cheap: true` when the run starts with `--cheap`. The line is absent
  otherwise, mirroring `max_tokens` (`skills/automate-loop/run-file.md` template and
  `docs/result-schemas/automate-run.md`).
- The driver applies cheap mode when either the command line or `## Run Config` says so, read in one place next to
  the existing `lane.json` read.
- A new `--no-cheap` flag on `/automate` (and `--resume`) overrides a persisted `cheap: true` for the rest of the
  run, and the run file records the change, so the override survives the next bare `--resume` too. Persisting is not
  a one-way trap.
- `--no-cheap` on a lane coordinator resume turns the profile off for its lanes too (their `lane.json`).
- `commands/automate.md`'s `--cheap` and `--resume` rows say the profile is persisted, with the warning removed,
  rewritten in place (the command is near its token budget).

### Non-goals

- The `/review-pr` drain's cost profile (the companion story
  `2026-11-03-102218-review-drain-honours-cheap.md`).
- Changing which roles `--cheap` covers.
- Persisting `--notify` or `--non-interactive-fallback`; they stay session-scoped.
- CI `claude-review` triggers, the `fix_floor` default, the Phase 4.5 executing-lens scope.

### Owner decisions (2026-11-03)

- The owner ruled that the sequential non-persistence is a bug, not a convention to keep.
- Persistence must come with an explicit off switch (`--no-cheap`).

### Acceptance criteria

**Happy path:**
- [ ] Given a sequential run started with `--cheap`, when the run file is written at start, then `## Run Config`
      contains `- cheap: true`.
- [ ] Given that run file, when `/automate --resume` runs WITHOUT `--cheap`, then every Supervisor and
      `/autonomous` spawn invocation the driver prints carries `--cheap` (test in `scripts/test-automate-next-step*.sh`).

**Edge cases:**
- [ ] Given a run started without `--cheap`, when it resumes, then no spawn carries `--cheap` and `## Run Config`
      has no `cheap` line.
- [ ] Given a run file with `- cheap: true`, when `/automate --resume --no-cheap` runs, then no later spawn carries
      `--cheap`, and a following bare `--resume` still runs at full cost.
- [ ] Given a lane created with `--cheap`, when the coordinator resumes with `--no-cheap`, then the lane's next
      spawns carry no `--cheap`.
- [ ] Given both `--cheap` and `--no-cheap` on one command, when the driver starts, then it refuses with a named
      error and writes nothing.

**Error scenarios:**
- [ ] Given a `cheap:` line in `## Run Config` with any value other than `true`, when the driver reads it, then it
      treats cheap mode as off and prints one warning line naming the value. It never guesses on.

### Validation (must pass before merge)

- `bash scripts/ci-local.sh --affected` passes, including `check-token-budget.sh`, `check-doc-currency.sh` and
  `check-prompt-history-refs.sh`.
- `bash scripts/check-version-bump.sh` passes; the PR carries a `changelog.d/` fragment and no hand-edited version.

#### Priority
- [x] MVP - Core functionality, must ship

**Rationale:** the owner already pays full cost on resumed runs they asked to be cheap; the fix is small.

#### Assumptions
- The model writes `## Run Config` at run start from the template, as it already does for `max_tokens`, so this is
  exactly as reliable as that step.

#### Dependencies
- Depends on: none
- Blocks: `2026-11-03-102218-review-drain-honours-cheap.md` (it forwards cheap mode using this story's rule)

#### Risks
- `commands/automate.md` is near its token budget; the rows must be rewritten, not extended.

#### Success Metrics
- No resumed `--cheap` run shows a Supervisor spawn without `--cheap` in its run file's spawn lines.

#### Handoff
Ready for: `/automate --backlog .supervisor/requirements/2026-11-03-102216-cheap-is-honoured-end-to-end-in-automate-runs.md`

## Part B — The /review-pr drain honours --cheap

**Story: The /review-pr drain honours --cheap** (type: story)

**As a** plugin owner running `/automate --cheap` or `/review-pr` directly,
**I want** the review drain's reviewer and fix spawns to run on the Sonnet cost profile when I ask for it,
**so that** the most spawn-heavy phase of an item is not the one phase `--cheap` never reaches.

### Problem

The `/automate` driver spawns the owned drain and the fix-now re-drain as
`/review-pr $PR --until-mergeable --no-auto-postmortem`, with no cost flag. `/review-pr` (`commands/review-pr.md`,
`skills/review-heal/SKILL.md`) has no `--cheap` at all. So up to `--max-rounds` (default 5) drain rounds, each with
up to 3 heal iterations of reviewer and fix spawns, run at full cost even when the owner passed `--cheap`.

### Evidence (verified 2026-11-03)

- `docs/ARCHITECTURE_CONTRACTS.md` §"Cost Profiles" lists the `--cheap` roles (worker, code-reviewer,
  execute-manager, orchestrator, Phase 4.5 fix task and multi-voter voters → sonnet) and has no row for the drain's
  reviewer or fix spawns. The drain is uncovered, not deliberately excluded.
- The three drain spawn sites in `scripts/automate-next-step.sh` (owned drain prompt, owned drain instruction,
  fix-now re-drain) all print `/review-pr $PR --until-mergeable --no-auto-postmortem` with no further flags.

### Goal

`/review-pr --cheap` runs its execution-shaped spawns on Sonnet, and `/automate` passes it whenever the run is in
cheap mode.

### Scope

- `/review-pr` accepts `--cheap`. Under it, the drain's code-reviewer review spawn, its fix task spawn, and the
  Earned Fallback Review spawn run on `model: "sonnet"` through the spawn-time Task `model` parameter. No agent
  frontmatter changes. Without the flag nothing changes.
- The `/automate` driver adds `--cheap` to both drain spawns (owned drain and fix-now re-drain) whenever cheap mode
  is on, sequential or lane.
- `docs/ARCHITECTURE_CONTRACTS.md` §"Cost Profiles" gains the drain rows in the same change. Every surface that
  restates that table is updated together or replaced with a pointer (house rule on restated lists).
- `agents/review-pr-runner` prose (if it restates the flag list) is synced with `commands/review-pr.md` in the same
  change.

### Non-goals

- Persisting `--cheap` across resumes (the companion story
  `2026-11-03-102216-cheap-is-honoured-end-to-end-in-automate-runs.md`).
- Changing which Supervisor or Phase 4.5 roles `--cheap` covers.
- CI `claude-review` triggers, model or effort; the `fix_floor` default; the Phase 4.5 executing-lens scope.

### Owner decisions (2026-11-03)

- The owner ruled that `--cheap` not reaching the drain is a bug.

### Acceptance criteria

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

### Validation (must pass before merge)

- `bash scripts/ci-local.sh --affected` passes, including `check-token-budget.sh` (budget entries raised in
  `loomwright/docs/prompt-token-budgets.json` and the mirror table if `commands/review-pr.md` or
  `skills/review-heal/` grow), `check-doc-currency.sh` and `check-prompt-history-refs.sh`.
- `bash scripts/check-version-bump.sh` passes; the PR carries a `changelog.d/` fragment and no hand-edited version.

#### Priority
- [x] MVP - Core functionality, must ship

**Rationale:** the drain is the most spawn-heavy phase per item (up to 5 rounds × 3 heal iterations).

#### Assumptions
- The drain's reviewer and fix spawns go through the Task tool, so the `model` parameter applies.
- The coordinator and drain sessions' own models stay as configured (`coordinator_model`); this changes only the
  spawns inside the drain.

#### Dependencies
- Depends on: `2026-11-03-102216-cheap-is-honoured-end-to-end-in-automate-runs.md` (the driver's cheap-mode rule)
- Blocks: none

#### Risks
- Sonnet as the drain reviewer may raise or miss findings differently than the session model. `--cheap` is opt-in,
  so the default path is unchanged.

#### Success Metrics
- A `--cheap` run's drain-phase tokens (`read-token-ledger.sh --per-item`) drop compared with a `--cheap` run from
  before this change.

#### Handoff
Ready for: `/automate --backlog .supervisor/requirements/2026-11-03-102218-review-drain-honours-cheap.md`

## Depends on
none

## Touches
changelog.d/
loomwright/commands/automate.md
loomwright/commands/review-pr.md
loomwright/docs/ARCHITECTURE_CONTRACTS.md
loomwright/docs/prompt-token-budgets.json
loomwright/docs/result-schemas/automate-run.md
loomwright/scripts/automate-lanes.sh
loomwright/scripts/automate-next-step.sh
loomwright/scripts/test-automate-next-step.2.sh
loomwright/scripts/test-automate-next-step.sh
loomwright/skills/automate-loop/run-file.md
loomwright/skills/review-heal/SKILL.md
loomwright/skills/review-heal/fallback-review.md

## Status: brief-shipped

Job `.supervisor/jobs/done/2026-11-07-cheap-honoured-end-to-end.md` completed (reconciled from the job lifecycle, not self-reported).
Acceptance criteria are NOT machine-verified here — review them before promoting this to `## Status: done`.

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-11-08T03:39:05Z
- **Brief:** .supervisor/jobs/done/2026-11-07-cheap-honoured-end-to-end.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/845
