# Selvedge `run` reads selvedge.json from the base the plan was frozen against

## Status: open

> Closes the gap qa-split/09 ships with
> (`.supervisor/requirements/qa-split/09-loomwright-verify-kind-and-unknown-prefix-root-fix.md`, decision
> D15b, owner decision 2026-11-28 "the merge does NOT wait for a Selvedge release"). That item's open-item
> note points here.

## Why

A plan made with `selvedge plan <criteria.json> --base <ref>` reads `selvedge.json` from the base branch, so
a pull request cannot widen its own checks at plan time. `selvedge run` does not keep that promise: it reads
`selvedge.json` again from the run folder's checkout, which in a PR is the PR head.

Evidence (selvedge 0.12.1, repo at origin/main `9a6a850`):

- `selvedge/lib/runner/run.mjs:308`: `const { config, root } = loadConfig({ cwd: runDir });` — no `base`.
- `selvedge/lib/runner/run.mjs:479` (`replayRun`, `run --replay`): `loadConfig({ cwd: frozenDir })` — no `base`.
- `selvedge/lib/runner/run.mjs` `runHooks` (`spawnSync('bash', [SELVEDGE_BIN, 'env', 'hook', name], …)`)
  runs the reset / seed hooks with no `--base`, so the hook bodies also come from the working tree.
- `loadConfig` already supports a base (`selvedge/lib/env-config.mjs:393`, `loadConfig({ cwd, base })`,
  which reads `<base>:selvedge.json` with `git show`), and `plan`, `plan --validate`, `plan --freeze`,
  `env check`, `env hook`, `auth setup` and `comment` all accept `--base <ref>`. `run`'s help lists no
  `--base`, and `plan --freeze` records nothing about which config source it used.

So a PR that edits `selvedge.json` (the origin allowlist, an env hook, a budget, the sign-in check) changes
what `run` does, even when its plan was made and frozen against the base.

What qa-split/09 assumed: Selvedge reads `selvedge.json` from the base branch at every step (D15b), and a
re-read is "a Selvedge fix, released on its own", never a Loomwright workaround. This story is that fix.

## Story

**As the** owner whose PRs are checked by Selvedge (directly or through Loomwright's `verify:` kind),
**I want** `selvedge run` and `run --replay` to use the same `selvedge.json` the plan was frozen against,
**so that** a pull request can never change its own origin allowlist, hooks or budgets between plan and run.

## Acceptance criteria

**Happy path**
- [ ] Given a plan frozen with `--base <ref>`, when the frozen run is inspected, then it records the config
  source it used (the base ref, or "working tree" when no `--base` was given), and that record is covered by
  the freeze (a later edit to it is refused like any other change to a frozen folder).
- [ ] Given a plan frozen with `--base main` in a repo whose working-tree `selvedge.json` adds an origin and
  changes an env hook compared with `main:selvedge.json`, when `selvedge run` runs, then it uses the
  `main` copy: a goto to the added origin is refused as outside the allowlist, and the hook run is the base
  one. A test pins both.
- [ ] Given the same frozen run, when `selvedge run --replay <frozen-dir>` runs, then the replay uses the same
  recorded source.
- [ ] Given a run with a recorded base, when the reset / seed hooks run, then they are run with that base
  (`env hook <name> --base <ref>`), and hook approval is checked against the hooks of the config actually
  used, never the working-tree copy.

**Edge cases**
- [ ] Given a plan made without `--base`, when `run` runs, then it reads the working-tree `selvedge.json`
  exactly as today (no behaviour change).
- [ ] Given a run folder frozen by a Selvedge version from before this change (no recorded source), when `run`
  runs, then it reads the working tree as today and says once on stderr that the folder records no config
  source; it never fails because the record is missing.

**Error scenarios**
- [ ] Given a recorded base ref that can no longer be read (the ref was deleted, or `<ref>:selvedge.json`
  is absent or invalid), when `run` runs, then it stops with the named reason `base_config_unreadable`,
  writes no verdict and claims no run.
- [ ] Given `run` is passed a `--base <ref>` that differs from the recorded one, when it starts, then it
  refuses with a named reason and claims nothing (the recorded source wins; it is never overridden at run
  time). Whether `run` accepts `--base` at all is the implementer's choice, documented in its help.

## Non-goals

- Changing how `plan`, `env`, `auth` or `comment` read `selvedge.json` (they already accept `--base`).
- Any Loomwright change: qa-split/09 already passes `--base` to `plan` and never passes an unsupported flag to
  `run`. Loomwright reads the new behaviour through Selvedge's public commands only.
- Making a PR's `selvedge.json` edit take effect in the same PR (by design it never does when `--base` is used).

## Owner decisions

- 2026-11-28 (Vikash): qa-split/09 ships without waiting for this fix, with the gap recorded as an open item;
  this requirement is the separate Selvedge fix it points to.
- 2026-11-28 (Vikash): write this with `/loomwright:product-owner`, put it on the metadata branch by its one
  path, queue it after qa-split/09's run, and park at the release step — the owner approves Selvedge
  releases separately.

## Release (final step — owner-approved, not done by the implementer)

This fix changes `selvedge run`'s behaviour, so it ships as a Selvedge release. Selvedge releases on its own:
its own `selvedge/.claude-plugin/plugin.json`, its entry in `.claude-plugin/marketplace.json` and
`selvedge/CHANGELOG.md`, never a `changelog.d/` fragment. The implementer prepares the change and its
`selvedge/CHANGELOG.md` entry text in the PR description only, and must NOT bump the version, tag or publish.
The run parks at that point and reports to the owner, who approves the release separately.

## Priority: MVP

**Rationale:** Loomwright's `verify:` kind (qa-split/09) now relies on D15b, which holds only at plan time
until this ships.

## Assumptions

- Defect evidence: reproduced — on 2026-11-28, `loadConfig` from `selvedge/lib/env-config.mjs` called the way
  `run.mjs:308` calls it (`{ cwd: <run folder> }`) in a scratch repo whose working-tree `selvedge.json` added
  an origin returned source `working tree (no --base)` with both origins, while `{ cwd, base: 'main' }`
  returned `main (git show main:selvedge.json)` with only the base origin.
- The freeze record (freeze line / frozen run files) can take one additive field without breaking frozen
  folders made by older versions (the edge case above covers them).
- `env hook <name> --base <ref>` already reads the hook from the base, so `runHooks` needs only the flag.

## Dependencies

- Depends on: none.
- Blocks: closing qa-split/09's open item on D15b.

## Risks

- Older frozen folders keep the working-tree read until they are re-planned; the stderr line makes that
  visible.
- A base ref that moves between plan and run (a branch, not a sha) reads the moved branch; recording the
  resolved commit sha instead of the ref name avoids that, and is the implementer's call to document.

## Validation (must pass before merge)

1. **Static — Selvedge's own gate:** `bash selvedge/tests/run.sh` passes, with new legs in
   `selvedge/tests/test-run.sh` and `selvedge/tests/test-replay.sh` (base copy wins over a differing working
   tree, hooks run with the base, an unreadable base ref is `base_config_unreadable`, no `--base` unchanged,
   an older frozen folder still runs).
2. **Running system — a real run against the sample app:** in a scratch git repo with `selvedge sample-app`,
   a plan frozen with `--base main` and a working-tree `selvedge.json` that adds an origin, `selvedge run`
   refuses the added origin; the command and output are pasted in the PR.

## Depends on
none

## Touches
selvedge/lib/runner/run.mjs
selvedge/lib/plan.mjs
selvedge/lib/plan-runs.mjs
selvedge/lib/env-config.mjs
selvedge/tests/test-run.sh
selvedge/tests/test-replay.sh
selvedge/README.md
