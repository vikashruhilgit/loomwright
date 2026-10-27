**Module-layout standard: Launch Pad plans modules, worker follows them, Phase 4.5 reviews structure** (type: story)

## Status: pending

Source: https://github.com/vikashruhilgit/loomwright/issues/687

**As a** maintainer of a repo that Loomwright builds in (for example `loomwright-studio`),
**I want** the pipeline to plan, write and review code as cohesive modules, with new code placed beside an already-large file rather than into it and shared helpers reused rather than copied,
**so that** files stop growing without bound in every consumer repo, with no per-repo setup and no new gate.

## Problem

No stage of the pipeline treats file size or module cohesion as a quality standard. Measured in `loomwright-studio` (Loomwright 17.14.1, 2026-10-24): source files at 2,766 / 1,094 / 1,087 lines, two app screens at 1,019 / 1,008, tests at 3,040 / 2,146 / 2,041. One automate item (one PR) added a 1,114-line and a 778-line test file in a single pass. `redact` and `clipped` are each defined in three sibling `phase-*-exit-live.test.ts` files, though the directory already has shared `*-helpers.ts` modules.

Root cause, verified in the plugin on 2026-10-24: the brief's File Impact Map is the plan of record. It names one target file per scenario, and the worker puts everything there. Phase 4.5 then reviews the diff against the brief, so growth that was planned in passes. Specifically:
- `skills/supervisor-readiness/SKILL.md` §"Decomposition Threshold" has three split reasons (`file-conflict`, `context-bound`, `genuine-parallelism`). Module structure isn't one of them, and the File Impact Map has no notion of "new module" vs "append to existing file".
- `agents/worker.md` reports `lines_added` and has no guidance to split a file or reuse a shared helper.
- `agents/code-reviewer.md`'s only duplication check is frontend-only ("UI structure duplicated 3+ times"). Nothing reviews cohesion or helpers copied across files.
- Nothing in `loomwright/` mentions `file_size`, `modularity` or `cohesion`.

## Goal

The standard ships **in the plugin** and applies in every consumer repo with no configuration: planning (Launch Pad + Plan Reviewer), implementation (worker) and review (Phase 4.5) each apply it as judgement. A repo may tune what it calls "large" with a committed house rule in `.agent/rules/`. That rule is an override of the plugin default, never a requirement for the standard to work.

## Scope

### Part A — Launch Pad plans the module layout; Plan Reviewer checks the plan
- `skills/supervisor-readiness/SKILL.md` gains ONE authoritative section, §"Module layout". It defines what the File Impact Map must say about module structure, and holds the plugin's default "large file" threshold: **500 lines**, the single place that number lives. Every other surface points to this section and never restates the number (house rules `process-a-count-or-version-claim…` and `process-when-one-surface-restates…`).
- Launch Pad's Phase 3 analysis (`agents/launch-pad.md`, mirrored in `commands/launch-pad.md`'s step list in the same change) records the current line count of every MODIFY path. For each new responsibility the change introduces, the File Impact Map names its module: a CREATE beside an existing file when that file is already at or past the threshold, or when the new code is a separate concern; or the existing shared helper module when one already provides it. When the change needs a helper that 2+ siblings already copy, the map carries an explicit "extract `<helper>` into `<module>`" row. This applies to test files exactly as to source files.
- A repo-specific threshold comes from the applicable house rules Launch Pad already reads (action 0c, `read-rules.sh`). A rule stating a different size for some paths overrides the default for those paths.
- `agents/plan-reviewer.md` gains **Criterion 21** (conditional; skip silently when no MODIFY path is at or past the threshold). A brief that puts a new responsibility into such a file without a one-line reason in the File Impact Map is a MEDIUM `module_layout` finding, which the refine loop fixes. It never fails the brief on its own.

### Part B — Worker follows the layout
- `agents/worker.md` gains one short rule: follow the File Impact Map's module plan, reuse a helper it names instead of rewriting it, and never copy a function that already exists in a sibling file. Where the worker has to depart from the plan (it splits a file the map didn't, or appends where the map said create), it records a `plan:` entry in the existing `deviations` field (Step 5.7). No new result field and no schema bump.

### Part C — Phase 4.5 reviews structure, fed by facts
- New script `loomwright/scripts/module-shape-facts.sh`, fail-SAFE (always exits 0, empty output on any failure, reason on stderr), with its test `loomwright/scripts/test-module-shape-facts.sh`. Given the base ref, it prints for each file the diff touches its line count before and after the diff, plus every function or helper name the diff *adds* that is defined in 2+ files after the diff. It holds no threshold, so the size judgement stays with the reviewer and the default stays in one place.
- `skills/self-heal-advisory/SKILL.md` gains a step beside 1g that runs the script and threads its output to the review lens as a **MODULE-SHAPE ADVISORY** line, only when non-empty. It is fed to the reviewer only, never to workers or fixers as an instruction. Its empty output must never read as "clean" (the CLAUDE.md "fail-SAFE reader consumed by a gate" corollary): the review lens is told that an absent advisory means "facts unavailable", not "no issue".
- `agents/code-reviewer.md` adds structure as a review dimension with fixed severities:
  - a helper the diff copies into 2+ files, where one shared definition would do → **MEDIUM** (at the default `fix_floor` MEDIUM, so the heal loop fixes it);
  - a file the diff gave an unrelated responsibility, or grew past the threshold when a new module would have done → **LOW** (advisory, below the default fix floor, so it never adds a heal round on its own).
  - Neither is ever BLOCKING or HIGH, and neither changes `decision` on its own.

### Shared
- Token budgets: every grown agent, command and skill gets its `loomwright/docs/prompt-token-budgets.json` entry and `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" mirror row updated in the same change.
- New enum values (`module_layout` finding kind, any new decision-record string): grep a sibling value repo-wide and extend every closed list it appears in (`docs/RESULT_SCHEMAS.md` when a schema enum is touched).
- A `changelog.d/` fragment; no hand-edit of version files.

## Non-goals
- Refactoring existing oversized files automatically, in any repo. The standard stops new growth and steers new code into modules; splitting legacy files stays explicit work.
- Any CI gate or fail-CLOSED check on a consumer repo's file sizes. Every part is judgement plus advisory facts.
- A `.supervisor/config.json` key for the threshold (the issue's proposal 4). `.supervisor/` is gitignored, so the key would be missing from fresh worktrees and `--parallel` lane clones. The override lives in committed `.agent/rules/` instead.
- A new portable seed in `scripts/seed-rules.sh`. The standard already ships in the plugin, so a seed would only duplicate it. Revisit if repos ask for a visible rule to edit.
- Product Owner story sizing (`skills/user-story-writing`). The growth starts at the File Impact Map, not at story size.

## Acceptance Criteria

**Happy Path:**
- [ ] Given a goal that adds a new responsibility next to a MODIFY path of ≥ 500 lines, when Launch Pad builds the File Impact Map, then the map names a CREATE module for that responsibility (or a one-line reason for appending), and records the existing file's line count.
- [ ] Given a goal whose new code needs a helper already defined in 2+ sibling files, when Launch Pad builds the File Impact Map, then the map carries an "extract `<helper>` into `<module>`" row, or names the existing shared module to reuse.
- [ ] Given a brief that puts a new responsibility into a ≥ 500-line MODIFY path with no reason, when Plan Reviewer runs, then Criterion 21 reports a MEDIUM `module_layout` issue, and does not FAIL the brief on that issue alone.
- [ ] Given a diff that defines the same new helper in two files, when `module-shape-facts.sh` runs against the base ref, then it prints that name with both files; and when the Phase 4.5 reviewer receives the MODULE-SHAPE ADVISORY, then it reports one MEDIUM `category: new` finding naming both files.
- [ ] Given a diff that grows a file past the threshold with an unrelated responsibility, when Phase 4.5 reviews it, then the finding is LOW, and the heal loop at the default `fix_floor` does not schedule a fix round for it.
- [ ] Given the plugin default and no house rule, when any of the stages above judges "large", then it uses the value from `skills/supervisor-readiness/SKILL.md` §"Module layout". `grep -rn "500 lines"` (and the threshold number in any phrasing) over `loomwright/agents loomwright/commands loomwright/skills` finds it only in that section.

**Edge Cases:**
- [ ] Given a consumer repo with a house rule stating a different size for some paths, when Launch Pad and the reviewer judge those paths, then they use the rule's size, and the plugin default everywhere else.
- [ ] Given a worker that splits a file the map didn't plan to split, when it reports, then `deviations` carries a `plan:` entry explaining it and `status` is unaffected.
- [ ] Given a brief whose MODIFY paths are all under the threshold, when Plan Reviewer runs, then Criterion 21 is skipped silently.
- [ ] Given test files only, when every check above runs, then each one applies to them the same as to source files.

**Error Scenarios:**
- [ ] Given `module-shape-facts.sh` runs with a missing base ref, outside a git repo, or on a binary or deleted file, when it fails, then it exits 0 with empty stdout and a reason on stderr; `test-module-shape-facts.sh` pins each case.
- [ ] Given the facts script produced no output, when the Phase 4.5 reviewer runs, then no MODULE-SHAPE ADVISORY line is threaded, and the reviewer prompt states that an absent advisory means "facts unavailable", not "no structural issue".

## Validation (must pass before merge)
- `bash scripts/ci-local.sh` green (includes `check-token-budget.sh`, `check-doc-currency.sh`, `test-citation-drift.sh`, `check-prompt-history-refs.sh`).
- `bash scripts/check-version-bump.sh` passes.
- `bash loomwright/scripts/test-module-shape-facts.sh` passes, and includes a pin mutation per load-bearing check: deleting the "defined in 2+ files" filter must turn a test red.

## Measurements
- After merge, re-measure `loomwright-studio` over its next 3 automate items, frozen at this item's merge commit (`git worktree add <tmp> <merge-sha>`, loaded with `--plugin-dir <tmp>/loomwright`): line counts of new and modified files vs the 2026-10-24 baseline above, and count of helper names defined in 2+ files that those diffs added (baseline: `redact`, `clipped` ×3 each). Record the result in the issue, not as acceptance.

### Priority
- [x] MVP — the issue is a standing quality gap that compounds every automate item in every consumer repo.

### Assumptions
- 500 lines is a reasonable default for "large" across languages. Owner may change it; it lives in exactly one place, so changing it later is a one-line edit.
- An LLM stage can read a size from a house rule's statement text. No new member is added to the frozen rule schema.
- Launch Pad can count lines of MODIFY paths during Phase 3 within its existing budget.

### Dependencies
- Depends on: none
- Blocks: none

### Risks
- Prompt growth in five already-budgeted files. Keep each addition short, and point to §"Module layout" instead of restating it.
- The LOW severity for "unrelated responsibility" may be too weak to change behaviour. Measure first (above) before raising it; raising it to MEDIUM risks heal-loop oscillation on a subjective finding.
- The helper-name heuristic in the facts script is language-agnostic only approximately. False positives cost a reviewer judgement, never a gate, since the script only feeds facts.

### Success Metrics
- New files that `loomwright-studio` items add stay under the threshold, or carry a planned reason.
- Zero newly copied helpers across files in those diffs.

### Handoff
Ready for: `/automate --folder .supervisor/requirements/module-layout`

## Depends on
none

## Touches
loomwright/skills/supervisor-readiness/SKILL.md
loomwright/agents/launch-pad.md
loomwright/commands/launch-pad.md
loomwright/agents/plan-reviewer.md
loomwright/agents/worker.md
loomwright/agents/code-reviewer.md
loomwright/skills/self-heal-advisory/SKILL.md
loomwright/scripts/module-shape-facts.sh
loomwright/scripts/test-module-shape-facts.sh
loomwright/docs/prompt-token-budgets.json
loomwright/docs/ARCHITECTURE_CONTRACTS.md
loomwright/docs/RESULT_SCHEMAS.md
changelog.d/module-layout-standard.md

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-27T01:34:11Z
- **Brief:** .supervisor/jobs/done/2026-10-26-module-layout-standard.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/713
