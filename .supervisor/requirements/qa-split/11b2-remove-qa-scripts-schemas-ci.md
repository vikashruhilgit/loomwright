# Part 2 of the QA removal: the QA scripts, schema docs, blueprint and CI Playwright steps are gone

## Status: pending

> Phase 4, item 11b (part 2 of 2) of the approved plan `qa-split/00-plan.md` (rev 2, owner-approved
> 2026-11-12). Decisions: D1, Q4. Works strictly from 11a's manifest rows marked `11b2`. Part 1
> (`11b1-remove-qa-agents-commands-skills.md`) removed every caller of these files.

## Why

After part 1, the `/verify` and QA scripts, their tests, schema docs, `QA_SYSTEM_BLUEPRINT.md` and the CI
Playwright pin and cache steps have no caller. They still cost CI time (a ~150 MB Playwright download path)
and doc-gate upkeep.

## Story

**As** the plugin's maintainer,
**I want** the remaining QA scripts, tests, schemas and CI steps (manifest rows `11b2`) deleted,
**so that** no QA code is left in Loomwright and CI stops caching a browser it no longer uses.

## Scope

- Delete every manifest `delete` row marked `11b2`: `validate-qa-result.py`, `validate-verify-evidence.py`,
  `verify-run.sh`, `verify-env.sh`, `verify-helpers.sh`, `verify-fixture-app.py`, `read-verify.sh`,
  `read-playwright-pin.sh` and their tests (`test-read-playwright-pin.sh`, `test-verify-evidence.sh`,
  `test-verify-queue.sh`, `test-verify-seam.sh`, `test-verify-walkthrough.sh`), the QA and verify schema docs
  under `loomwright/docs/result-schemas/` and their `RESULT_SCHEMAS.md` rows, `QA_SYSTEM_BLUEPRINT.md`, and
  the Playwright pin and cache steps in `.github/workflows/ci.yml`; plus their `ci-local.sh` suite entries.
- **Keep** every `keep` row: `verify-provides.sh` and `test-verify-provides.sh`, `classify_kind`'s
  `qa-executor` arm, `run-ground-truth.sh`'s deferred branch.
- `/propose --from-verify` still reads `/verify`'s `evidence.jsonl` format here; item 12 re-points it. Its
  own test keeps its fixtures, so it stays green.

## Acceptance criteria

- Given this branch, when `check-qa-removal-manifest.sh --expect 11b2` runs, then it exits 0 (every
  `11b1` and `11b2` delete row gone, every keep row present).
- Given CI on this PR, then no step installs or caches Playwright or Chromium for Loomwright's suites.
- Given a brief with a `qa-executor: x` Executable Acceptance bullet, when ground truth runs, then it still
  records the bullet as deferred and spawns nothing (existing test).
- `bash scripts/check-doc-currency.sh` passes.

## Non-goals

- Re-pointing `/propose --from-verify`, `classify-risk.sh` or the name maps (item 12).
- Touching `verify-provides.sh` or the `outputs_verified` gate (not QA).
- Changing anything in `selvedge/` (its own CI steps stay).

## Owner decisions

- 2026-11-12: remove QA after Phase 1; keep the `qa-executor` arm until item 09 or D18 lands.
- 2026-11-18: start Phase 4 now; 11b split in two parts (this session).

## Priority: MVP

**Rationale:** Finishes the deletion D1 asks for.

## Assumptions

- A `changelog.d/` fragment is needed only if the gate requires one for a script-only removal; the
  user-facing note shipped in part 1.

## Risks

- A test outside the manifest sources a deleted helper (e.g. `verify-helpers.sh`). Mitigation: the full CI
  run on the PR; any such file becomes a manifest row before merge.

## Validation (must pass before merge)

1. **Static — manifest:** `bash loomwright/scripts/check-qa-removal-manifest.sh --expect 11b2` exits 0.
2. **Static — repo gates:** `bash scripts/ci-local.sh --affected` passes, then CI `ci` is green.

## Depends on

11b1-remove-qa-agents-commands-skills.md

## Touches

loomwright/scripts/validate-qa-result.py
loomwright/scripts/validate-verify-evidence.py
loomwright/scripts/verify-run.sh
loomwright/scripts/verify-env.sh
loomwright/scripts/verify-helpers.sh
loomwright/scripts/verify-fixture-app.py
loomwright/scripts/read-verify.sh
loomwright/scripts/read-playwright-pin.sh
loomwright/scripts/test-read-playwright-pin.sh
loomwright/scripts/test-verify-evidence.sh
loomwright/scripts/test-verify-queue.sh
loomwright/scripts/test-verify-seam.sh
loomwright/scripts/test-verify-walkthrough.sh
loomwright/scripts/test-result-validators.sh
loomwright/docs/result-schemas
loomwright/docs/RESULT_SCHEMAS.md
loomwright/docs/QA_SYSTEM_BLUEPRINT.md
.github/workflows/ci.yml
scripts/ci-local.sh
changelog.d
