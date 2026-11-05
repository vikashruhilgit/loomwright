# Touches name shared files at intake

## Status: pending

**Story: Touches name shared files at intake** (type: story)

**As a** plugin owner queueing requirement items for `/automate --parallel`,
**I want** the Product Owner to list in `## Touches` the existing files a story must plug into, not only the new files it creates,
**so that** `plan-waves` plans waves from file sets close to the real ones, and lanes stop discovering half their files at Launch Pad.

### Problem
Issue vikashruhilgit/loomwright#808: the Product Owner fills `## Touches` "from your own file-impact reasoning"
before reading the code. Lists name the new files a story creates and miss the existing shared files it must
register in: an index, a policy table, the kernel wiring, the test that asserts the feature is absent. In
loomwright-studio, items 05 and 06 declared 11 and 10 files and needed 26 and 25. `plan-waves --lint` checks
grammar only, and `right-size` counted the declared files, so its verdicts saw half the real size. One widening
also hid a contract change (item 06's `Grant form`: whether `{github: "read"}` must be accepted), which no file
check can catch. `.agent/companions.json` already lets a project name its shared files deterministically, but
nothing points requirement writers at it.

### Owner decisions (2026-11-03)
- Approved: improve intake with a Product Owner prompt step and a pointer to `.agent/companions.json`; no
  `plan-waves --lint --deep` mode (nothing deterministic can know where a feature registers).

### Acceptance Criteria

**Happy Path:**
- [ ] Given a story that adds a new symbol, route, setting or category, when the Product Owner fills
      `## Touches`, then its instructions require finding an existing similar feature in the code and listing the
      existing files that register, dispatch, configure or test it.
- [ ] Given that step finds a contract change (a response shape, an accepted input form, a refusal a test pins),
      then the story states it in its Acceptance Criteria or as an Assumption-Check flag, not as a file only.
- [ ] Given the project has `.agent/companions.json`, then the `user-story-writing` skill tells writers that
      shared files every story of a kind needs belong there, so the planner adds them on its own.

**Edge Cases:**
- [ ] Given no similar feature exists, then the Product Owner says so in the story's Assumptions, and Touches
      lists what it can name (or `unknown` when it truly cannot).
- [ ] Given a shared file is already added by a companions rule, then the story need not list it again.

**Error Scenarios:**
- [ ] Given the Product Owner runs as a subagent or `--non-interactive`, then the step is still followed; it
      adds no question.

### Priority
- [x] Phase 2 — prevention; the gate stories catch the failure whether or not intake improves.

### Assumptions
- A prompt step improves lists but cannot guarantee them; the gate stories remain the safety net.

### Dependencies
- Depends on: none (shares token-budget files with the other two stories, so the planner will order them).
- Blocks: none.

### Risks
- A longer Product Owner prompt costs tokens on every run; budget re-measured in the same change.

### Success Metrics
- On a re-run of the loomwright-studio prompt for item 06, `## Touches` includes `kernel/src/kernel.ts` and
  `kernel/src/sessions/policy.ts`.

### Handoff
Ready for: `/launch-pad goal: ".supervisor/requirements/2026-11-03-174031-touches-name-shared-files-at-intake.md"`

## Validation (must pass before merge)
1. **Static — prompt gates:** `bash scripts/ci-local.sh --affected` passes, including `check-token-budget.sh` with the re-measured Product Owner and skill budgets.
2. **Running system — Product Owner names shared files:** a live `/product-owner` run on a feature request that must register in an existing index lists that existing index file in the persisted story's `## Touches`.

## Depends on
none

## Touches
loomwright/agents/product-owner.md
loomwright/commands/product-owner.md
loomwright/skills/user-story-writing/SKILL.md
loomwright/docs/prompt-token-budgets.json
loomwright/docs/ARCHITECTURE_CONTRACTS.md
changelog.d/touches-name-shared-files-at-intake.md

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-11-05T16:17:34Z
- **Brief:** .supervisor/jobs/done/2026-11-05-touches-name-shared-files-at-intake.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/830
