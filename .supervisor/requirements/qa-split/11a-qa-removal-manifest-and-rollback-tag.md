# A reviewed, committed list of every QA file and reference to remove, with a checker and a rollback point

## Status: done
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/944

> Phase 4, item 11a of the approved plan `qa-split/00-plan.md` (rev 2, owner-approved 2026-11-12).
> Decisions: D1 (remove all QA from Loomwright), Q4 (after Phase 1, which finished 2026-11-18).
> Read the plan's §6 Phase 4 table and red-team rows C7 and W7 before starting.

## Why

The old QA system (2 agents, 3 commands, 6 skills, the `/verify` scripts and tests, two SubagentStop
matchers, schema docs, the CI Playwright cache, an agent-memory dir) has had zero `/verify` runs and two
manual QA runs, ever. Selvedge now does the job. But about 171 files outside `selvedge/` still name it, and
every count, budget and doc gate carries it. Deleting by "grep returns nothing" is how a reference gets
missed or the wrong file goes (red team C7, W7). This item writes the list first, so the deletion
(11b) and the re-pointing (12) each check against it, entry by entry.

## Story

**As** the plugin's maintainer,
**I want** one committed, reviewed list of every QA path and named reference, each marked delete,
re-point or keep, plus a script that checks the repo against it,
**so that** the removal PRs are checked against a list I approved, not against a grep someone ran once.

## Scope

- `loomwright/docs/qa-removal-manifest.md`: one row per entry with the path (or the file plus the named
  reference in it), the action (`delete` / `re-point` / `keep`), the item that acts on it (`11b1` / `11b2` / `12`)
  and a one-line reason. Generated once by searching the whole repo (outside `selvedge/` and gitignored
  dirs) for every QA name: the agent and command names, the six skill names, `QA_SYSTEM_BLUEPRINT`, the
  `/verify` scripts, `.agent/verify.json`, `VERIFY_EVIDENCE`, `QA_RESULT`-style schema names, the Playwright
  pin/cache steps. It must name at least: `capabilities.json`, `.claude-plugin/marketplace.json` (counts and
  keywords), `loomwright/.claude-plugin/plugin.json` (description counts), `.github/workflows/ci.yml` (the
  Playwright pin and cache steps), `loomwright/hooks/hooks.json` (the two matchers), the 9 tracked files in
  `.claude/agent-memory/loomwright-loomwright-qa-executor/`, `loomwright/docs/prompt-token-budgets.json` and
  its mirror table in `ARCHITECTURE_CONTRACTS.md`, and the CLAUDE.md agent-roles table.
- **Keep rows, written down so nothing deletes them by accident:** `verify-provides.sh` and
  `test-verify-provides.sh`, the `outputs_verified` gate, the `unit-testing` and `quality-checklist`
  skills, and `classify_kind`'s `qa-executor` arm in `exec-acceptance-lib.sh` together with
  `run-ground-truth.sh`'s deferred `qa-executor` branch (kept until Phase 3's item 09 or D18 lands; that
  branch records DEFERRED and spawns nothing, so it is safe with the agent gone).
- `loomwright/scripts/check-qa-removal-manifest.sh` with its self-test: parses the manifest and reports,
  per row, whether the repo matches it. `--expect <item>` checks every row up to and including that item (`11b1`, then `11b2`, then `12`): it fails when such a `delete` row's path still exists or a
  `keep` row's path is missing. `--expect 12` also fails when a `re-point` row's file still contains the old
  name. With no `--expect`, it reports and exits 0 (the state before 11b).
- **Rollback note** in the manifest: the tag to restore from (`pre-qa-removal`) and what to re-add by
  hand. The tag itself is created on `origin/main` as 11b1's first step, not here, so it points at the last
  commit with QA in it.

## Acceptance criteria

- Given the merged manifest, when `check-qa-removal-manifest.sh` runs with no `--expect` on `main`, then
  it exits 0 and every `delete` and `re-point` row reports "pending".
- Given a fixture repo where one `delete` path still exists, when it runs `--expect 11b1` (the row marked `11b1`), then it exits
  non-zero and names that path.
- Given a fixture repo where a `keep` path (e.g. `verify-provides.sh`) is missing, when it runs
  `--expect 11b1`, then it exits non-zero and names that path.
- Given a fixture where a `re-point` file still names `qa-executor`, when it runs `--expect 12`, then it
  exits non-zero and names the file and the reference.
- Given a manifest row whose action is not `delete` / `re-point` / `keep`, then the checker refuses the
  manifest (exit 2), never skips the row.
- Every one of the paths named in Scope has a row. The row count is recorded in the manifest header and
  the PR body (the real number red team C7 asked for).
- The PR deletes and re-points nothing.

## Non-goals

- Deleting or editing any QA file (11b, 12).
- Creating the `pre-qa-removal` tag (11b1's first step).
- Anything inside `selvedge/`.

## Owner decisions

- 2026-11-12: remove QA from Loomwright after Phase 1 (Q4, D1).
- 2026-11-18: start Phase 4 now, before Phase 2 (this session).

## Priority: MVP

**Rationale:** 11b and 12 cannot be checked without it.

## Assumptions

- The ~171-file count from a grep on 2026-11-18 is a lower bound; the manifest's own search sets the
  real number.

## Risks

- A reference by a derived name (a path computed at runtime) is invisible to a literal grep. Mitigation:
  also list every script that builds an agent or skill name from a table (the name maps), as `re-point`
  rows.

## Validation (must pass before merge)

1. **Static — the checker's self-test:** `bash loomwright/scripts/test-check-qa-removal-manifest.sh`
   passes, including the four fixture cases above.
2. **Static — repo gates:** `bash scripts/ci-local.sh --affected` passes, then CI `ci` is green.

## Depends on

none

## Touches

loomwright/docs/qa-removal-manifest.md
loomwright/scripts/check-qa-removal-manifest.sh
loomwright/scripts/test-check-qa-removal-manifest.sh
scripts/ci-local.sh
.github/workflows/ci.yml
changelog.d

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-11-18T13:27:49Z
- **Brief:** .supervisor/jobs/done/2026-11-18-qa-removal-manifest-and-checker.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/944
