# --cheap survives resume in sequential /automate runs

## Status: pending

**Story: --cheap survives resume in sequential /automate runs** (type: story)

**As a** plugin owner who starts an `/automate` run with `--cheap` to save tokens,
**I want** the Sonnet cost profile to stay on across every `--resume` until I turn it off,
**so that** a run I asked to be cheap is never silently charged at the full-cost profile.

## Problem

`scripts/automate-next-step.sh` sets cheap mode only from its own command line, or, inside a lane, from
`.supervisor/lane.json` `"cheap": true` (the line next to the comment "inside a lane, `--cheap` also comes from the
lane's own record"). It never reads it back from the run file. `--max-tokens`, by contrast, falls back to
`## Run Config`'s `- max_tokens:` line at every spawn site, so a bare `/automate --resume` keeps the token ceiling
but silently drops the cost profile. `commands/automate.md` documents this as a warning on the `--cheap` and
`--resume` rows ("omitting it silently reverts the remaining queue to the full-cost profile"). A warning does not
prevent it.

## Evidence (verified 2026-11-03)

- Lanes were fixed in v17.21.1 (`lane-create --cheap` writes `lane.json` `"cheap": true`). That release says "A
  sequential run's `--cheap` stays passthrough-only and is still not written to `## Run Config`."
- The original reason for not persisting it (v15.2.0) was only "same convention as `--notify` /
  `--non-interactive-fallback`". Those two depend on the session that runs. `--cheap` describes the run, like
  `--max-tokens`, which red-team-hardening/06 deliberately persisted so that a bare `--resume` still enforces it.

## Goal

`--cheap` given once at the start of a sequential `/automate` run applies to every spawn the driver prints for the
rest of that run, until the owner explicitly turns it off.

## Scope

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

## Non-goals

- The `/review-pr` drain's cost profile (the companion story
  `2026-11-03-102218-review-drain-honours-cheap.md`).
- Changing which roles `--cheap` covers.
- Persisting `--notify` or `--non-interactive-fallback`; they stay session-scoped.
- CI `claude-review` triggers, the `fix_floor` default, the Phase 4.5 executing-lens scope.

## Owner decisions (2026-11-03)

- The owner ruled that the sequential non-persistence is a bug, not a convention to keep.
- Persistence must come with an explicit off switch (`--no-cheap`).

## Acceptance criteria

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

## Validation (must pass before merge)

- `bash scripts/ci-local.sh --affected` passes, including `check-token-budget.sh`, `check-doc-currency.sh` and
  `check-prompt-history-refs.sh`.
- `bash scripts/check-version-bump.sh` passes; the PR carries a `changelog.d/` fragment and no hand-edited version.

### Priority
- [x] MVP - Core functionality, must ship

**Rationale:** the owner already pays full cost on resumed runs they asked to be cheap; the fix is small.

### Assumptions
- The model writes `## Run Config` at run start from the template, as it already does for `max_tokens`, so this is
  exactly as reliable as that step.

### Dependencies
- Depends on: none
- Blocks: `2026-11-03-102218-review-drain-honours-cheap.md` (it forwards cheap mode using this story's rule)

### Risks
- `commands/automate.md` is near its token budget; the rows must be rewritten, not extended.

### Success Metrics
- No resumed `--cheap` run shows a Supervisor spawn without `--cheap` in its run file's spawn lines.

### Handoff
Ready for: `/automate --backlog .supervisor/requirements/2026-11-03-102216-cheap-is-honoured-end-to-end-in-automate-runs.md`

## Depends on
none

## Touches
loomwright/scripts/automate-next-step.sh
loomwright/scripts/automate-lanes.sh
loomwright/scripts/test-automate-next-step.sh
loomwright/commands/automate.md
loomwright/skills/automate-loop/run-file.md
loomwright/docs/result-schemas/automate-run.md
changelog.d/
