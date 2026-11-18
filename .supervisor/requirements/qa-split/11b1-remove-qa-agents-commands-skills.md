# Part 1 of the QA removal: the QA agents, commands, skills, hooks and memory are gone, with a migration note

## Status: pending

> Phase 4, item 11b (part 1 of 2) and item 13 of the approved plan `qa-split/00-plan.md` (rev 2, owner-approved 2026-11-12).
> Item 13 (the migration note and rationale doc) is folded in here: the release that removes
> `/qa-executor` is the one whose changelog must say what replaced it.
> Decisions: D1, Q4. Works strictly from 11a's manifest rows marked `11b1`. Part 2
> (`11b2-remove-qa-scripts-schemas-ci.md`) deletes the scripts, schemas and CI steps left without a caller.

## Why

D1: no QA agent, command, skill, schema, hook, CI cache or agent-memory dir stays in Loomwright. Selvedge
replaces it. Every release still pays for the old QA in counts, token budgets and doc gates.

## Story

**As** the plugin's maintainer,
**I want** every user-facing QA surface (manifest rows `11b1`) removed in one green release, with a changelog entry and a
rationale doc,
**so that** Loomwright stops carrying an unused QA system and a `/qa-executor` user knows what replaced it.

## Scope

- **First step, before any deletion:** make sure the tag `pre-qa-removal` exists on `origin/main` at the
  commit this branch starts from; create and push it if absent (the owner approved this tag in the plan).
- Delete every manifest `delete` row marked `11b1`: the agents `qa-executor` and `qa-strategist`; the
  commands `qa-executor`, `qa-strategist` and `verify`; the skills `playwright-e2e`, `qa-gates`,
  `qa-orchestration`, `qa-strategy`, `qa-test-patterns` and `verify-walkthrough` (and their
  `SKILLS_INDEX.md` rows); the two SubagentStop matchers in `hooks.json`; their token-budget entries and
  mirror rows; the tracked agent-memory dir `.claude/agent-memory/loomwright-loomwright-qa-executor/`.
- Scripts, schema docs, `QA_SYSTEM_BLUEPRINT.md` and the CI Playwright steps stay for part 2, unless a
  gate in this PR needs one gone.
- Update every count the doc-currency gate checks (plugin and marketplace descriptions, CLAUDE.md's
  agent-roles heading and table, README) to the new numbers.
- Make only the edits other files need for this PR's own gates to pass; behaviour-changing re-points are
  item 12.
- **Keep** every manifest `keep` row, in particular `classify_kind`'s `qa-executor` arm and
  `run-ground-truth.sh`'s deferred branch, `verify-provides.sh` and its test.
- **Migration note (was item 13):** a `changelog.d/` fragment saying which commands and agents were
  removed, that Selvedge (`/selvedge:verify`, the `selvedge` CLI) replaces them, and how to install it;
  plus `loomwright/docs/rationale/qa-split.md` with the why (zero runs, the drift cost, D1) pointing to
  the plan.

## Acceptance criteria

- Given this branch, when `check-qa-removal-manifest.sh --expect 11b1` runs, then it exits 0.
- Given a brief whose Executable Acceptance has a `qa-executor: x` bullet, when ground truth runs, then it
  still records the bullet as deferred and spawns nothing (unchanged behaviour, pinned by the existing
  test).
- `bash scripts/check-doc-currency.sh` passes with the new counts, and `check-token-budget.sh` has no entry
  for a deleted file.
- The tag `pre-qa-removal` exists on the remote and points at the commit this branch started from.
- The changelog fragment names `/qa-executor`, `/qa-strategist` and `/verify` and says what replaces each.

## Non-goals

- Deleting the QA scripts, schema docs, `QA_SYSTEM_BLUEPRINT.md` or the CI Playwright steps (part 2).
- Re-pointing `/propose --from-verify`, `classify-risk.sh` or the name maps (item 12), beyond what this
  PR's gates need.
- Adding a `verify:` kind or touching `classify_kind` (Phase 3, item 09).
- Changing anything in `selvedge/`.

## Owner decisions

- 2026-11-12: remove QA after Phase 1; keep the `qa-executor` arm until item 09 or D18 lands; tag
  `pre-qa-removal` before deleting (plan §6, item 11a).
- 2026-11-18: start Phase 4 now; item 13 folded into this item; 11b split in two parts (this session).

## Priority: MVP

**Rationale:** This is the removal itself.

## Assumptions

- Removing the skills and commands first leaves their scripts without a caller but still passing their
  own tests, so this PR stays green with them in place.

## Risks

- A deleted script is still called by a test or a hook not on the manifest. Mitigation: the manifest
  checker plus the full CI run on the PR.
- Users with `/qa-executor` in muscle memory. Mitigation: the changelog fragment and rationale doc.

## Validation (must pass before merge)

1. **Static — manifest:** `bash loomwright/scripts/check-qa-removal-manifest.sh --expect 11b1` exits 0.
2. **Static — repo gates:** `bash scripts/ci-local.sh --affected` passes, then CI `ci` is green
   (doc currency, token budgets, version bump included).
3. **Running system — the installed plugin:** after `/plugin install loomwright@atelier` from this
   branch, `/agent-help` lists no QA command and `/loomwright:qa-executor` is an unknown command.

## Depends on

11a-qa-removal-manifest-and-rollback-tag.md

## Touches

loomwright/agents/qa-executor.md
loomwright/agents/qa-strategist.md
loomwright/commands/qa-executor.md
loomwright/commands/qa-strategist.md
loomwright/commands/verify.md
loomwright/skills/playwright-e2e
loomwright/skills/qa-gates
loomwright/skills/qa-orchestration
loomwright/skills/qa-strategy
loomwright/skills/qa-test-patterns
loomwright/skills/verify-walkthrough
loomwright/skills/SKILLS_INDEX.md
loomwright/hooks/hooks.json
loomwright/docs/prompt-token-budgets.json
loomwright/docs/ARCHITECTURE_CONTRACTS.md
loomwright/docs/rationale/qa-split.md
loomwright/.claude-plugin/plugin.json
.claude-plugin/marketplace.json
.claude/agent-memory/loomwright-loomwright-qa-executor
CLAUDE.md
README.md
changelog.d
