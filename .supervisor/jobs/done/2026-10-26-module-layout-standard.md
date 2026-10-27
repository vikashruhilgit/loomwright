# Supervisor Job: Module-layout standard — Launch Pad plans modules, worker follows them, Phase 4.5 reviews structure

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (4 leftover worktrees under `.claude/worktrees/`, unrelated to this item)
- **Source requirement:** .supervisor/requirements/module-layout/01-module-layout-standard.md
- **Base commit:** d251729d3b41988e492063da6072f18137bcf28a

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Markdown prompts, one bash 3.2-safe script and its static `test-*.sh`. This matches the plugin's own stack. |
| 2 | Dependency Availability | GO | Only `git`, `awk`, `grep` and `wc`. No new dependency. |
| 3 | Architecture Fit | GO | Same shape as the existing advisory enrichments (step 1g DEVIATIONS ADVISORY, fail-SAFE readers) and the conditional Plan Reviewer criteria (18–20). |
| 4 | Scope vs Supervisor Capability | CAUTION | About 20 files change (including the bump outputs), which is over the `context-bound` bound in `skills/supervisor-readiness/SKILL.md` §"Decomposition Threshold". Split into 2 sequential subtasks. |
| 5 | Hard Blockers | GO | None. |

**Overall Verdict:** CAUTION

## Task
**Goal:** Make module structure a plugin-wide quality standard. Launch Pad plans each new responsibility's module in the File Impact Map and Plan Reviewer checks that plan (Criterion 21). The worker follows the plan and records departures as `plan:` deviations. Phase 4.5 reviews structure using facts from a new fail-SAFE `module-shape-facts.sh`. The 500-line default lives only in `skills/supervisor-readiness/SKILL.md` §"Module layout", and a committed `.agent/rules/` house rule can override it.

**Problem Statement:**
Maintainers of repos that Loomwright builds in (e.g. `loomwright-studio`) need new code placed in cohesive modules, and shared helpers reused rather than copied, because no pipeline stage treats file size or cohesion as a standard.
Currently, the File Impact Map names one target file per scenario, the worker appends everything there, and Phase 4.5 reviews the diff against that plan. Planned growth therefore passes every gate. In `loomwright-studio`, source files have reached 1,000–2,766 lines and test files 2,000–3,040 lines, and `redact`/`clipped` are each copied into three sibling test files.
Success looks like this: new files stay under the threshold or carry a planned reason, and diffs add no newly copied helpers. This holds in every consumer repo, with no per-repo setup and no new gate.

## Acceptance Criteria

**Happy Path:**
- [ ] AC1 — Given a goal that adds a new responsibility next to a MODIFY path at or past the threshold, when Launch Pad builds the File Impact Map, then the map records the existing file's line count and names a CREATE module for that responsibility (or gives a one-line reason for appending). Phase 3 analysis in `agents/launch-pad.md`, and the step list in `commands/launch-pad.md` in the same change, say so by pointing to §"Module layout".
- [ ] AC2 — Given a goal whose new code needs a helper already defined in 2+ sibling files, when Launch Pad builds the File Impact Map, then the map carries an "extract `<helper>` into `<module>`" row or names the existing shared module to reuse. §"Module layout" defines this row form.
- [ ] AC3 — Given a brief that puts a new responsibility into a MODIFY path at or past the threshold with no reason, when Plan Reviewer runs, then the new conditional Criterion 21 in `agents/plan-reviewer.md` reports a MEDIUM `module_layout` issue and does not FAIL the brief on that issue alone. The criteria count lives only in `agents/plan-reviewer.md`, the authority, where it moves 20 → 21. The Launch Pad surfaces that restated it drop the number (house rule `process-a-count-or-version-claim…`): the spawn line in `agents/launch-pad.md` becomes `Check every review criterion.`, and `commands/launch-pad.md` Phase 5.5 step 2 becomes `Plan Reviewer checks every review criterion`.
- [ ] AC4 — Given a diff that defines the same new helper in two files, when `loomwright/scripts/module-shape-facts.sh` runs against the base ref, then it prints that name with its file count and the files. The MODULE-SHAPE ADVISORY is a **hint, not a directive**. `agents/code-reviewer.md` directs exactly one MEDIUM `category: new` finding naming both files only after the reviewer reads both definitions and confirms they are the same non-trivial logic, and that the copy is not a deliberate per-file self-contained convention.
- [ ] AC4b — Given a diff that adds a new standalone test script carrying only the conventional per-file harness helpers (`ok()`/`no()`/`has()`/`lacks()`, already defined in 150+ files under `loomwright/scripts/` by convention), when the facts script lists those names, then the reviewer raises no structure finding for them. `agents/code-reviewer.md` names this exclusion with the literal phrase `deliberate per-file convention`, and `test-module-shape-facts.sh` pins that phrase. This PR itself, which adds `test-module-shape-facts.sh`, is the live negative case.
- [ ] AC5 — Given a diff that grows a file past the threshold with an unrelated responsibility, when Phase 4.5 reviews it, then `agents/code-reviewer.md` grades the finding LOW. That is below the default `fix_floor` MEDIUM, so the heal loop schedules no fix round for it. Neither structure finding is ever BLOCKING or HIGH, and neither changes `decision` on its own.
- [ ] AC6 — Given the plugin default and no house rule, when any stage judges "large", then it uses the value from `skills/supervisor-readiness/SKILL.md` §"Module layout". `grep -rnE '500[ -]?lines?|500-line' loomwright/agents loomwright/commands loomwright/skills` finds the threshold only in that section. The pattern is line-threshold wording only: it returns 0 hits at base `d251729`, so the bare `500` HTTP-status checks in `skills/error-handling/` and `agents/qa-executor.md` do not match. After the change it returns only §"Module layout" lines of `skills/supervisor-readiness/SKILL.md`. `test-module-shape-facts.sh` carries this as a leg with exactly that pattern, and the section must phrase its default so the pattern matches it (e.g. "500 lines").

**Edge Cases:**
- [ ] AC7 — Given a consumer repo with a house rule that states a different size for some paths, when Launch Pad (action 0c's `applicable_rules`) and the reviewer (the HOUSE-RULES ADVISORY) judge those paths, then they use the rule's size there and the plugin default everywhere else. §"Module layout" states this override and no other surface restates it.
- [ ] AC8 — Given a worker that splits a file the map didn't plan to split (or appends where the map said create), when it reports, then `deviations` carries a `plan:` entry explaining it and `status` is unaffected. `agents/worker.md` gains one short rule: follow the map's module plan, reuse a helper it names, and never copy a function that already exists in a sibling file. There is no new result field and no schema bump.
- [ ] AC9 — Given a brief whose MODIFY paths are all under the threshold, when Plan Reviewer runs, then Criterion 21 is skipped silently.
- [ ] AC10 — Given test files only, when every check above runs, then each one applies to them exactly as to source files. §"Module layout", Criterion 21 and the code-reviewer structure dimension each say so, and `test-module-shape-facts.sh` has a leg whose touched files are all `*.test.*`/`test-*.sh`.

**Error Scenarios:**
- [ ] AC11 — Given `module-shape-facts.sh` runs with a missing base ref, outside a git repo, or on a diff whose only touched file is binary or deleted, when it cannot produce facts, then it exits 0 with empty stdout and a one-line reason on stderr. `test-module-shape-facts.sh` pins each case and asserts the specific stderr reason, not just the empty stdout.
- [ ] AC12 — Given the facts script produced no output, when the Phase 4.5 reviewer runs, then no MODULE-SHAPE ADVISORY line is threaded. The reviewer prompt (`skills/self-heal-advisory/SKILL.md` Part 2) states that an absent advisory means "facts unavailable", not "no structural issue".

**Release / validation:**
- [ ] AC13 — Every grown agent, command and skill has its `loomwright/docs/prompt-token-budgets.json` entry and `docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" mirror row updated in the same change (`bash scripts/check-token-budget.sh` green). `changelog.d/module-layout-standard.md` exists (`<!-- bump: minor -->`), and `bash scripts/check-version-bump.sh` passes.
- [ ] AC14 — `bash loomwright/scripts/test-module-shape-facts.sh` passes and includes one pin mutation per load-bearing check (see `## Pin mutations`). In particular, deleting the "defined in 2+ files" filter turns a test red.

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

> How this brief honors them: the 500-line threshold is written once, in §"Module layout", and every other surface points there. The Plan Reviewer criteria count stays only in its authority, `agents/plan-reviewer.md`, where it moves to 21. The two Launch Pad surfaces that restated it (the `agents/launch-pad.md` spawn line and the `commands/launch-pad.md` step 2) drop the number, so they can no longer drift. The restated *list* of conditional criteria in `commands/launch-pad.md` (`Criteria 11, 13, …, and 20 are conditional`) is a mirror of `agents/plan-reviewer.md`. Per the second rule it is updated in this same change to include 21 and its gate. The seam tests' count pins follow the same split: they pin 21 in `plan-reviewer.md`, and in the Launch Pad files they pin the count-free wording plus the absence of `Check all 20`.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## File Impact Map

> Dogfooding the standard this item ships: each MODIFY path's line count at base `d251729` is recorded. Several paths are past 500 lines. They are appended to because the requirement names them as the single authority for the new rule (this is the plan's one-line reason), and each addition is a short pointer-style paragraph, never a new subsystem. The only new responsibility with code is the facts script, and it is a CREATE.

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| planning (Part A) | `loomwright/skills/supervisor-readiness/SKILL.md` (538 — authority section required here by the requirement), `loomwright/agents/launch-pad.md` (879 — one Phase 3 action plus the spawn-contract count; the agent prompt is the only home), `loomwright/commands/launch-pad.md` (241), `loomwright/agents/plan-reviewer.md` (358), `loomwright/docs/result-schemas/plan-review-result.md` (31) | — | HIGH |
| worker (Part B) | `loomwright/agents/worker.md` (248) | — | HIGH |
| count pins (Part A fallout) | `loomwright/scripts/test-closed-enum-pins-seam.sh` (253), `loomwright/scripts/test-pr-body-evidence-seam.sh` (291), `loomwright/scripts/test-rule-conformance-seam.sh` (462), `loomwright/docs/loop-inventory/launch-pad-autonomous.md` (991 — a generated-style inventory table; LP-274's `q:` anchor must track the command text) | — | HIGH |
| review (Part C) | `loomwright/skills/self-heal-advisory/SKILL.md` (407), `loomwright/skills/self-heal-advisory/on-entry.md` (139 — one pointer line beside its `1g.` pointer), `loomwright/agents/code-reviewer.md` (437), `loomwright/skills/quality-checklist/SKILL.md` (one short "Module shape (Supervisor Phase 4.5 only)" class beside the existing `Brief conformance` / `Deviations conformance` advisory classes, pointing to §"Module layout" and step 1h — it restates that list of advisory review classes), `loomwright/docs/loop-inventory/supervisor.md` (1292 — one new row + `## Counts` for the new step, per `test-loop-inventory.sh` coverage) | `loomwright/scripts/module-shape-facts.sh`, `loomwright/scripts/test-module-shape-facts.sh` | HIGH (inventory row: MEDIUM — needed if the new step adds a heading or rule-stating list item) |
| release / budgets | `loomwright/docs/prompt-token-budgets.json` (93), `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (1049 — mirror rows + raise log are its existing home), `loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CHANGELOG.md`, `loomwright/capabilities.json` (these four are written only by `bash scripts/bump-version.sh`) | `changelog.d/module-layout-standard.md` | HIGH |

> **Validator-owned surfaces:** acceptance depends on `scripts/check-token-budget.sh` (every grown agent/command/skill row), `scripts/check-doc-currency.sh` (doc surface, description counts — no agent/command/skill/hook count changes here), `loomwright/scripts/test-citation-drift.sh` (no new bare `file:N` in committed prose), `scripts/check-prompt-history-refs.sh` (no history refs such as issue numbers or "since vX" added to agent/command/skill text), and `loomwright/scripts/test-loop-inventory.sh` (heading coverage + live `q:` anchors for `agents/launch-pad.md`, `commands/launch-pad.md`, `skills/self-heal-advisory/*.md`). Their scanned files are folded into the map above.

**Not touched (checked):** `loomwright/docs/RESULT_SCHEMAS.md` only points to `result-schemas/plan-review-result.md` (its `## PLAN_REVIEW_RESULT` is a one-line link), so the category enum is extended in the linked file. `CODE_REVIEW_RESULT` categories (`new/pre_existing/nit/drift`) and `WORKER_RESULT.deviations` prefixes (`plan:` already exists) gain no value. `agents/supervisor.md` does not enumerate the 1f/1g enrichments, so it needs no mirror. `docs/rationale/supervisor.md`'s "with 20 criteria and 8 rubric bullets" is about acceptance criteria, not Plan Reviewer criteria, so no change.

## Touched-file invariants

> Grounded at base `d251729d3b41988e492063da6072f18137bcf28a`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/skills/supervisor-readiness/SKILL.md`** — keep: the §"Decomposition Threshold" single-home pattern this item copies (`**Single home:** this section is the sole **authority** for the threshold`); the new §"Module layout" is the ONE home of the 500 default and must carry the same single-home + house-rule-override wording; it is preloaded by `launch-pad` (`- supervisor-readiness` in its frontmatter `skills:`), so its growth also raises the `launch-pad` agent's measured weight. pinned by: `scripts/check-token-budget.sh` row `supervisor-readiness`.
- **`loomwright/agents/launch-pad.md`** — keep: advisory-read contract (`Reading any of them MUST NEVER block the run`); house rules are read only via action 0c (`0c. **Route applicable house rules (advisory`) — the module-size override is read from that same `applicable_rules`, never a new reader; new Phase 3 work is a numbered action pointing to §"Module layout" (format pattern: `11. **Touched-file invariants (conditional`), not a restatement. mirror: `commands/launch-pad.md` Phase 3 step list (`8. Touched-file invariants (conditional`) in the same change. Spawn contract: `Check all 20 review criteria. Output a PLAN_REVIEW_RESULT block.` becomes `Check every review criterion. Output a PLAN_REVIEW_RESULT block.` (count-free, per the house rule). pinned by: `scripts/test-closed-enum-pins-seam.sh`, `scripts/test-pr-body-evidence-seam.sh`, `scripts/test-rule-conformance-seam.sh` (`'Check all 20 review criteria.'` today) and `scripts/test-loop-inventory.sh` (every `###` heading needs an inventory row, so add none or add its row).
- **`loomwright/commands/launch-pad.md`** — keep: Phase 5.5 step 2's conditional-criteria sentence shape (`Criteria 11, 13, 14, 15, 16, 17, 18, 19, and 20 are conditional`). Extend that mirrored list with 21 and a `Criterion 21 runs only when …` gate clause in the style of `Criterion 20 runs only when an acceptance criterion names the PR body as its evidence, and FAILs it`. The count `checks all 20 criteria` becomes `checks every review criterion`. pinned by: the three seam tests (`'checks all 20 criteria'` today) and `docs/loop-inventory/launch-pad-autonomous.md` row LP-274 (`q: Plan Reviewer checks all 20 criteria`). Both its `q:` anchor and its action cell (`20 on PR-body evidence`) gain the new text.
- **`loomwright/agents/plan-reviewer.md`** — keep: the conditional-gate sentence pattern (`Criterion 20 is conditional: skip silently when`), per-criterion `**Issue category:**` line (`**Issue category:** \`pr_body_evidence\`.`), the Decision Matrix row `Only MEDIUM/LOW issues, design approach unambiguous` (a MEDIUM `module_layout` must land in that PASS row, never FAIL/NEEDS_HUMAN); reuse the 19-style MEDIUM wording (`MEDIUM for 19a, 19b and 19c (the decision stays PASS; Launch Pad refines it at its fix floor)`). Count surfaces to move 20 → 21: `## 20 Review Criteria`, `All 20 review criteria must be checked`, `(20 total, Criteria 11, 12, 13, 14, 15, 16, 17, 18, 19, and 20 conditional)`, `- [ ] All 20 criteria checked`, output enum `# optional — emit when a criterion mandates it (12–20)`. pinned by: the three seam tests (e.g. `'## 20 Review Criteria'`, `'| pin_mutations | pr_body_evidence | ...}"  # optional — emit when a criterion mandates it (12'`).
- **`loomwright/docs/result-schemas/plan-review-result.md`** — mirror: both category lists (`"pr_body_evidence" for Criterion 20 findings` and `` `pr_body_evidence` for Criterion 20 ``) gain `module_layout` for Criterion 21. pinned by: `scripts/test-pr-body-evidence-seam.sh` (`'"pr_body_evidence" for Criterion 20 findings'`) — append, do not reword the existing clause.
- **`loomwright/agents/worker.md`** — keep: Step 5.7's REPORT-ONLY contract (`REPORT-ONLY: it never influences \`status\` or \`outputs_gap\``), the 12-entry/200-char cap (`up to 12 entries of up to 200 characters each`), and the existing `plan:` prefix — no new prefix, no new field. pinned by: `scripts/test-deviations-advisory-seam.sh` (prefix convention `plan:`/`edge:`/`open:`/`test:`).
- **`loomwright/skills/self-heal-advisory/SKILL.md`** — keep: `**HARD ADVISORY CONTRACT (applies to every advisory step in every file of this skill):**` (the new step never changes `heal_decision`, triggers no fix by itself, fail-safe); the omit-when-empty line pattern (`**DEVIATIONS ADVISORY (include this line ONLY when \`deviations_advisory\` is non-empty; omit entirely when empty):**`); the new step is `1h.` placed after `1g.` (the seam test reads `grep -E '^1g\. '` — leave the 1g line's text intact). Unlike DEVIATIONS (no sentinel), this line's absence must be explained to the reviewer as "facts unavailable". reuse: the base ref follows the on-entry `touched` rule (`BASE_BRANCH==main -> git diff --name-only origin/main...HEAD` in `on-entry.md`). Step 1h passes `origin/main` when `BASE_BRANCH` is `main` and `$BASE_BRANCH` otherwise (stacked), so the facts describe the same diff the reviewer judges. pinned by: `scripts/test-deviations-advisory-seam.sh`, `scripts/test-brief-conformance-seam.sh`, `scripts/test-loop-inventory.sh` (supervisor group).
- **`loomwright/skills/self-heal-advisory/on-entry.md`** — keep: the pointer-line form (`1g. **Deviations advisory** — runs here AND on every later iteration`); add a `1h.` pointer the same way, no restated body.
- **`loomwright/agents/code-reviewer.md`** — keep: the severity-assignment rule (`MEDIUM/LOW are reserved for maintainability, polish, or non-blocking risk.`) and the decision matrix row (`MEDIUM/LOW never gates`); the existing frontend-only check (`UI structure duplicated 3+ times (suggest extraction)`) stays; the new structure dimension is source-agnostic and test-inclusive and points to §"Module layout" for "large". mirror: the MODULE-SHAPE ADVISORY wording in `self-heal-advisory/SKILL.md` Part 2. pinned by: `scripts/test-validate-code-review-result.sh` (schema keys only; no new key may be introduced).
- **`loomwright/skills/quality-checklist/SKILL.md`** — keep: the advisory-class bullet form (`- [ ] **Deviations conformance (\`deviations\` — Supervisor Phase 4.5 only).**`). The new "Module shape" class follows that form, says it is checkable only when the MODULE-SHAPE ADVISORY line is present, and points to §"Module layout" without restating the number. The skill is preloaded by `code-reviewer`, `launch-pad`, `orchestrator`, `qa-executor`, `qa-strategist` and `review-pr` (`- quality-checklist` in their frontmatter), so re-measure those agent rows and its own skill row in `scripts/check-token-budget.sh`.
- **`loomwright/scripts/test-closed-enum-pins-seam.sh`, `test-pr-body-evidence-seam.sh`, `test-rule-conformance-seam.sh`** — keep: each test's `has`/`lacks` ratchet idiom (`has "$PR" '## 20 Review Criteria' && lacks "$PR" '## 19 Review Criteria'`). For `$PR` (plan-reviewer.md), move both sides up by one (21 present, 20 absent). For `$LP`/`$SPAWN`/`$LPC` (the Launch Pad files), pin the count-free wording and add `lacks … 'Check all 20'` / `lacks … 'all 20 criteria'`. Leave every unrelated pin unchanged. `test-pr-body-evidence-seam.sh` also asserts Criterion 20 is LAST (`[ -z "$(lineno "$PR" '^### 21\. ')" ] && ok "Criterion 20 is the last criterion"`) and bounds its C20 block at `'^## Decision Matrix'`. Re-point both: C20 ends at `'^(### 21\. |## Decision Matrix)'`, Criterion 20 sits before 21, and Criterion 21 is the last one before the Decision Matrix. Keep the PART 7 mutants valid: they delete or move the `### 20.` block, and must still turn red.
- **`loomwright/docs/loop-inventory/launch-pad-autonomous.md`, `loomwright/docs/loop-inventory/supervisor.md`** — keep: nine-cell rows, `q:` anchors that are substrings of a live source line, and `## Counts` lines equal to the table (`- rows: 759` in supervisor.md at base). pinned by: `loomwright/scripts/test-loop-inventory.sh`.
- **`loomwright/docs/prompt-token-budgets.json` / `loomwright/docs/ARCHITECTURE_CONTRACTS.md`** — keep: measured + ~10% headroom convention (`"note": "Re-baselined to live measured + ~10%`) and the mirror table rows (e.g. ``| `plan-reviewer`     | 9451  | 8591¹ | 0 |``); raise only rows that breach, and log raises in the §"Prompt Token Budgets" raise-log style (`> **Raise log (`). pinned by: `scripts/check-token-budget.sh`.

## Closed enumerations touched

> Sibling grep at base `d251729`: `grep -rnF 'pr_body_evidence' --exclude=CHANGELOG.md loomwright scripts .github README.md CLAUDE.md` → 22 hits in 6 files.

- **`module_layout`** (sibling: `pr_body_evidence`) — must be named in:
  - `loomwright/agents/plan-reviewer.md` — output-format category enum (`| pin_mutations | pr_body_evidence | ...}"`) and the new Criterion 21 `**Issue category:**` line — extend (place `module_layout` after `pr_body_evidence`, and update `(12–20)` → `(12–21)` and the seam pin that quotes it).
  - `loomwright/docs/result-schemas/plan-review-result.md` — both canonical-category lists (`"pr_body_evidence" for Criterion 20 findings`) — extend.
  - `loomwright/agents/launch-pad.md` — Phase 5.5 FAIL-branch prose naming the Criterion 20 category — no change: it routes one specific FAIL category; `module_layout` is MEDIUM and goes through the existing at-floor PASS refine branch.
  - `loomwright/docs/ARCHITECTURE_CONTRACTS.md` — historical raise-log line — no change: a dated log entry, not a list.
  - `loomwright/scripts/test-pr-body-evidence-seam.sh` — pins for Criterion 20's own text — no change beyond the count and enum-line pins listed under `## Pin mutations`.
  - `loomwright/scripts/fixtures/pr-body-evidence/README.md` — Criterion 20 answer key — no change: not a category list.
- **Plan Reviewer criteria count `20` → `21`** (sibling literal: `all 20`). `grep -rnE "\b20 (review )?criteria|all 20\b|19, and 20" loomwright` hits: extend in `agents/plan-reviewer.md` (the authority; 4 sites: heading, never-skip rule, decision matrix, quality checklist), and the three seam tests' `$PR` pins. Drop the number (house rule) in `agents/launch-pad.md` (spawn contract `Check all 20 review criteria.`) and `commands/launch-pad.md` (Phase 5.5 step 2 `checks all 20 criteria`). Their mirrored conditional *list* `Criteria 11, 13, 14, 15, 16, 17, 18, 19, and 20 are conditional` gains 21. `docs/loop-inventory/launch-pad-autonomous.md` LP-274 updates its `q:` anchor and action cell. No change: `docs/rationale/supervisor.md` ("20 criteria and 8 rubric bullets" — acceptance criteria), `docs/rationale/subagents.md` (`§20 Review Criteria` — a historical token-diet table quoting the old heading), and `scripts/fixtures/rule-conformance/advisory/*.md` ("all 20 supported delivery cities").

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-module-shape-facts.sh` — helper defined in 2+ files is printed with both files; a helper in only 1 file is not | delete `# pin: defined-in-2+` in `loomwright/scripts/module-shape-facts.sh` (the filter and this marker share ONE self-contained line, so the mutant stays `bash -n`-valid) |
| `loomwright/scripts/test-module-shape-facts.sh` — a name defined in 2+ files but NOT added by the diff is not printed | delete `# pin: added-only` in `loomwright/scripts/module-shape-facts.sh` |
| `loomwright/scripts/test-module-shape-facts.sh` — missing base ref ⇒ exit 0, empty stdout, stderr names the base ref | delete `# pin: base-ref-guard` in `loomwright/scripts/module-shape-facts.sh` |
| `loomwright/scripts/test-module-shape-facts.sh` — outside a git repo ⇒ exit 0, empty stdout, stderr reason | delete `# pin: not-a-repo-guard` in `loomwright/scripts/module-shape-facts.sh` |
| `loomwright/scripts/test-module-shape-facts.sh` — binary-only diff ⇒ empty stdout + reason; binary file never gets a line count | delete `# pin: binary-skip` in `loomwright/scripts/module-shape-facts.sh` |
| `loomwright/scripts/test-module-shape-facts.sh` — deleted-only diff ⇒ empty stdout + reason | delete `# pin: deleted-skip` in `loomwright/scripts/module-shape-facts.sh` |
| `loomwright/scripts/test-module-shape-facts.sh` — single-home leg: the line threshold appears only in §"Module layout" | flip `### 21. Module Layout (conditional)` → `### 21. Module Layout (conditional, over 500 lines)` in `loomwright/agents/plan-reviewer.md` |
| `loomwright/scripts/test-module-shape-facts.sh` — AC10 leg: a diff whose touched files are all `*.test.*`/`test-*.sh` still gets line counts and copied-helper facts | delete `# pin: all-touched-paths` in `loomwright/scripts/module-shape-facts.sh` (the marker sits on the ONE line that feeds every touched path, test paths included, into the per-file loop; deleting it drops the files, so the leg goes red) |
| `loomwright/scripts/test-closed-enum-pins-seam.sh` — Criterion 21 skip clause (AC9, new pin) | flip `no MODIFY path is at or past the threshold → skip silently` → `no MODIFY path exists → skip silently` in `loomwright/agents/plan-reviewer.md` |
| `loomwright/scripts/test-closed-enum-pins-seam.sh` — Criterion 21 severity `**Severity if failed:** MEDIUM` (AC3, new pin) | flip `**Severity if failed:** MEDIUM (the decision stays PASS` → `**Severity if failed:** HIGH (the decision stays PASS` in `loomwright/agents/plan-reviewer.md` (Criterion 21 must hold this literal exactly once; reword Criterion 19's sibling line if it would collide) |
| `loomwright/scripts/test-closed-enum-pins-seam.sh` — command mirror names Criterion 21's gate (new pin) | flip `Criterion 21 runs only when` → `Criterion 21 runs whenever` in `loomwright/commands/launch-pad.md` |
| `loomwright/scripts/test-module-shape-facts.sh` — code-reviewer names the per-file-convention exclusion (AC4b) | flip `deliberate per-file convention` → `per-file helper` in `loomwright/agents/code-reviewer.md` |
| `loomwright/scripts/test-closed-enum-pins-seam.sh` — spawn line is count-free (`Check every review criterion.` present, `Check all 20` absent) | flip `Check every review criterion.` → `Check all 20 review criteria.` in `loomwright/agents/launch-pad.md` |
| `loomwright/scripts/test-closed-enum-pins-seam.sh` — command step 2 is count-free (`checks every review criterion`) | flip `checks every review criterion` → `checks all 20 criteria` in `loomwright/commands/launch-pad.md` |
| `loomwright/scripts/test-closed-enum-pins-seam.sh` — heading `## 21 Review Criteria` | flip `## 21 Review Criteria` → `## 20 Review Criteria` in `loomwright/agents/plan-reviewer.md` |
| `loomwright/scripts/test-closed-enum-pins-seam.sh` — never-skip rule `All 21 review criteria must be checked` | flip `All 21 review criteria must be checked` → `All 20 review criteria must be checked` in `loomwright/agents/plan-reviewer.md` |
| `loomwright/scripts/test-closed-enum-pins-seam.sh` — matrix row `(21 total, … 19, 20, and 21 conditional)` | flip `19, 20, and 21 conditional)` → `19, and 20 conditional)` in `loomwright/agents/plan-reviewer.md` |
| `loomwright/scripts/test-closed-enum-pins-seam.sh` — checklist `All 21 criteria checked` | flip `- [ ] All 21 criteria checked` → `- [ ] All 20 criteria checked` in `loomwright/agents/plan-reviewer.md` |
| `loomwright/scripts/test-closed-enum-pins-seam.sh` — Criterion 21 category line (new pin) | flip `**Issue category:** \`module_layout\`.` → `**Issue category:** \`layout\`.` in `loomwright/agents/plan-reviewer.md` |
| `loomwright/scripts/test-pr-body-evidence-seam.sh` — spawn line count-free | flip `Check every review criterion.` → `Check all 20 review criteria.` in `loomwright/agents/launch-pad.md` |
| `loomwright/scripts/test-pr-body-evidence-seam.sh` — command step 2 count-free | flip `checks every review criterion` → `checks all 20 criteria` in `loomwright/commands/launch-pad.md` |
| `loomwright/scripts/test-pr-body-evidence-seam.sh` — heading `## 21 Review Criteria` | flip `## 21 Review Criteria` → `## 20 Review Criteria` in `loomwright/agents/plan-reviewer.md` |
| `loomwright/scripts/test-pr-body-evidence-seam.sh` — never-skip rule `All 21 review criteria must be checked` | flip `All 21 review criteria must be checked` → `All 20 review criteria must be checked` in `loomwright/agents/plan-reviewer.md` |
| `loomwright/scripts/test-pr-body-evidence-seam.sh` — matrix row `19, 20, and 21 conditional)` | flip `19, 20, and 21 conditional)` → `19, and 20 conditional)` in `loomwright/agents/plan-reviewer.md` |
| `loomwright/scripts/test-pr-body-evidence-seam.sh` — checklist `- [ ] All 21 criteria checked` | flip `- [ ] All 21 criteria checked` → `- [ ] All 20 criteria checked` in `loomwright/agents/plan-reviewer.md` |
| `loomwright/scripts/test-pr-body-evidence-seam.sh` — never-skip conditional list `19, 20, and 21 are conditional` | flip `19, 20, and 21 are conditional` → `19, and 20 are conditional` in `loomwright/agents/plan-reviewer.md` |
| `loomwright/scripts/test-pr-body-evidence-seam.sh` — output enum ends `(12–21)` | flip `mandates it (12–21)` → `mandates it (12–20)` in `loomwright/agents/plan-reviewer.md` |
| `loomwright/scripts/test-pr-body-evidence-seam.sh` — Criterion 21 is the last criterion, after 20, before the Decision Matrix | flip `### 21. Module Layout (conditional)` → `### 21b. Module Layout (conditional)` in `loomwright/agents/plan-reviewer.md` |
| `loomwright/scripts/test-rule-conformance-seam.sh` — spawn line count-free | flip `Check every review criterion.` → `Check all 20 review criteria.` in `loomwright/agents/launch-pad.md` |
| `loomwright/scripts/test-rule-conformance-seam.sh` — command step 2 count-free | flip `checks every review criterion` → `checks all 20 criteria` in `loomwright/commands/launch-pad.md` |
| `loomwright/scripts/test-rule-conformance-seam.sh` — heading `## 21 Review Criteria` | flip `## 21 Review Criteria` → `## 20 Review Criteria` in `loomwright/agents/plan-reviewer.md` |
| `loomwright/scripts/test-rule-conformance-seam.sh` — never-skip rule `All 21 review criteria must be checked` | flip `All 21 review criteria must be checked` → `All 20 review criteria must be checked` in `loomwright/agents/plan-reviewer.md` |
| `loomwright/scripts/test-rule-conformance-seam.sh` — matrix row `19, 20, and 21 conditional)` | flip `19, 20, and 21 conditional)` → `19, and 20 conditional)` in `loomwright/agents/plan-reviewer.md` |
| `loomwright/scripts/test-rule-conformance-seam.sh` — checklist `- [ ] All 21 criteria checked` (both the count pin and the `CHK` grep) | flip `- [ ] All 21 criteria checked` → `- [ ] All 20 criteria checked` in `loomwright/agents/plan-reviewer.md` |

> The new plan-reviewer text must contain each flipped literal exactly once (e.g. write the matrix row as `(21 total, Criteria 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, and 21 conditional)` and the never-skip rule as `Criteria 11, 13, 14, 15, 16, 17, 18, 19, 20, and 21 are conditional`). A flip literal that occurs twice reads `unverified` in `run-pin-mutations.sh`.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Planning + worker standard: §"Module layout", Launch Pad Phase 3 action, Plan Reviewer Criterion 21 (count 20→21 everywhere), worker rule | AC1, AC2, AC3, AC7 (planning half), AC8, AC9, AC10 (planning half) | 10 modify, 0 create | `skills/supervisor-readiness/SKILL.md` | LAUNCHABLE |
| 2 | Review standard + facts script: `module-shape-facts.sh` + test, self-heal step 1h + MODULE-SHAPE ADVISORY line, code-reviewer structure dimension, budgets, changelog + bump | AC4, AC4b, AC5, AC6, AC7 (review half), AC10 (review half), AC11, AC12, AC13, AC14 | 11 modify, 3 create | `skills/self-heal-advisory/SKILL.md`, `skills/quality-checklist/SKILL.md` | BLOCKED (by #1) |

**Subtask 1 notes.** §"Module layout" must define: (a) the 500-line default, stated only here; (b) which File Impact Map facts are required: line count per MODIFY path; per new responsibility, a CREATE beside a file at/over the threshold or a separate-concern file, or the existing shared module, or a one-line reason for appending; an "extract `<helper>` into `<module>`" row when 2+ siblings already copy a helper the change needs; (c) that test files count exactly like source files; (d) that a committed `.agent/rules/` house rule stating a different size for some paths overrides the default for those paths only, read from the rules Launch Pad (action 0c) and the reviewer (HOUSE-RULES ADVISORY) already receive. Criterion 21 is conditional: skip silently when no MODIFY path is at or past the threshold. Its finding is MEDIUM `module_layout`, never FAIL on its own, and it lands in the Decision Matrix's MEDIUM/LOW → PASS row. Launch Pad's existing at-floor refine branch fixes it. `test-closed-enum-pins-seam.sh` also gains behaviour pins for Criterion 21: its skip clause, its `**Severity if failed:** MEDIUM` line, and the `Criterion 21 runs only when` clause in `commands/launch-pad.md` (rows in `## Pin mutations`). **Budget note:** this subtask grows `plan-reviewer`, `worker`, the `launch-pad` command and `supervisor-readiness` (preloaded by `launch-pad`). A `check-token-budget.sh` breach on those rows is expected here and is deferred to Subtask 2, which owns every budget file. Record it as a `plan:` deviation, and do not edit `prompt-token-budgets.json` or `ARCHITECTURE_CONTRACTS.md`.

**Subtask 2 notes.** `module-shape-facts.sh <base_ref> [<head_ref>] [--root <dir>]` mirrors `classify-risk.sh`'s read-only conventions (`git -C "$root"`, three-dot diff, never executes content, always exit 0). It holds no threshold. Per touched file it prints the line count before and after the diff. It also prints every function/helper name the diff ADDS that is defined in 2+ files after the diff, with its file count and the files (the list is capped, with a visible `+N more` marker, so a 160-file harness helper shows up as what it is). Detection is an approximate, language-agnostic definition regex (shell `name()`, `function name`, JS/TS `function name`/`const name = (`/`=>`, Python `def name`); false positives cost reviewer judgement only. The new self-heal step `1h.` runs the script on every review iteration (fixers can add copies too). Its base is `origin/main` when `BASE_BRANCH` is `main`, else `$BASE_BRANCH`, matching on-entry's `touched` rule. It threads its output as **MODULE-SHAPE ADVISORY**, only when non-empty, to the REVIEW lens only and never to workers/fixers. The step's prompt text says an absent line means "facts unavailable", not "no structural issue". `code-reviewer.md` adds structure as a review dimension and treats the advisory as a hint. A helper the diff copies into 2+ files where one shared definition would do → MEDIUM `category: new`, raised only after the reviewer has read the definitions and confirmed they are the same non-trivial logic, and the name is not a `deliberate per-file convention` such as each standalone test script's own `ok()`/`no()` harness; a file given an unrelated responsibility, or grown past the threshold (§"Module layout") where a new module would have done → LOW. Neither is ever BLOCKING/HIGH, and neither changes `decision` on its own. Last of all: measure the budgets, write `changelog.d/module-layout-standard.md` (`<!-- bump: minor -->`), run `bash scripts/bump-version.sh`, then `bash scripts/check-version-bump.sh`.

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/skills/supervisor-readiness/SKILL.md", name: "## Module layout"}
  - {kind: "symbol", path: "loomwright/agents/plan-reviewer.md", name: "### 21. Module Layout (conditional)"}
  - {kind: "symbol", path: "loomwright/agents/plan-reviewer.md", name: "## 21 Review Criteria"}
  - {kind: "symbol", path: "loomwright/agents/launch-pad.md", name: "Check every review criterion."}
  - {kind: "symbol", path: "loomwright/commands/launch-pad.md", name: "checks every review criterion"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/plan-review-result.md", name: "module_layout"}
requires: []
lanes:
  - "loomwright/skills/supervisor-readiness/SKILL.md"
  - "loomwright/agents/launch-pad.md"
  - "loomwright/commands/launch-pad.md"
  - "loomwright/agents/plan-reviewer.md"
  - "loomwright/docs/result-schemas/plan-review-result.md"
  - "loomwright/agents/worker.md"
  - "loomwright/scripts/test-closed-enum-pins-seam.sh"
  - "loomwright/scripts/test-pr-body-evidence-seam.sh"
  - "loomwright/scripts/test-rule-conformance-seam.sh"
  - "loomwright/docs/loop-inventory/launch-pad-autonomous.md"
external_requires: []

# Subtask 2
provides:
  - {kind: "file", path: "loomwright/scripts/module-shape-facts.sh"}
  - {kind: "file", path: "loomwright/scripts/test-module-shape-facts.sh"}
  - {kind: "symbol", path: "loomwright/scripts/module-shape-facts.sh", name: "# pin: defined-in-2+"}
  - {kind: "symbol", path: "loomwright/skills/self-heal-advisory/SKILL.md", name: "MODULE-SHAPE ADVISORY"}
  - {kind: "symbol", path: "loomwright/agents/code-reviewer.md", name: "MODULE-SHAPE ADVISORY"}
  - {kind: "file", path: "changelog.d/module-layout-standard.md"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/skills/supervisor-readiness/SKILL.md", name: "## Module layout"}
  - {from: "1", kind: "symbol", path: "loomwright/agents/plan-reviewer.md", name: "### 21. Module Layout (conditional)"}
lanes:
  - "loomwright/scripts/module-shape-facts.sh"
  - "loomwright/scripts/test-module-shape-facts.sh"
  - "loomwright/skills/self-heal-advisory/SKILL.md"
  - "loomwright/skills/self-heal-advisory/on-entry.md"
  - "loomwright/agents/code-reviewer.md"
  - "loomwright/skills/quality-checklist/SKILL.md"
  - "loomwright/docs/loop-inventory/supervisor.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "changelog.d/module-layout-standard.md"
  - "CHANGELOG.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - "loomwright/capabilities.json"
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none (Subtask 2 only reads §"Module layout" and Criterion 21; it measures budgets for Subtask 1's files after they land) | YES — by `requires`, not overlap |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after Subtask 1)
- **Recommended workers:** 1
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/supervisor-readiness/SKILL.md` |
| 2 | `skills/self-heal-advisory/SKILL.md`, `skills/quality-checklist/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): about 20 changed files exceed the `context-bound` bound | MEDIUM | Two sequential subtasks with disjoint lanes; Subtask 2 owns all budget/release files so measurement happens once, after both land. |
| Prompt growth in already-budgeted files (`launch-pad` has 4324 headroom but preloads `supervisor-readiness`; `plan-reviewer` 860; `worker` 584; `code-reviewer` 1768; `supervisor-readiness` 1155; `self-heal-advisory` 3427; command `launch-pad` 502) | MEDIUM | Keep each addition to a short pointer to §"Module layout". Re-measure with `bash scripts/check-token-budget.sh` and update the JSON entry and the ARCHITECTURE_CONTRACTS mirror row (with a raise-log line) in the same change for each breach. |
| Restated "20 criteria" count drifts on a surface the sweep missed | MEDIUM | `## Closed enumerations touched` lists every hit. After editing, re-run `grep -rnE "\b20 (review )?criteria\|all 20\b\|19, and 20" loomwright` and expect only the three listed no-change hits. |
| `test-loop-inventory.sh` fails on a new `###` heading or a stale `q:` anchor in `agents/launch-pad.md`, `commands/launch-pad.md` or `skills/self-heal-advisory/*.md` | MEDIUM | Add numbered steps, not headings, and update LP-274's anchor. If a heading is unavoidable, add its row and fix `## Counts` in the same commit. |
| The facts script's helper-name regex is only approximately language-agnostic | LOW | It only feeds facts to the reviewer, never a gate. Pin the 2+ filter and the added-only filter with mutations; document the regex's limits in the script header. |
| A pin mutant is silently invalid (sed/perl interpolation, delimiter collision) | MEDIUM | Each pinned marker sits on one self-contained statement line. Before trusting a red, gate every mutant on non-empty, differs-from-original and `bash -n` (verified lesson `fa32a308`). |
| LOW "unrelated responsibility" severity may be too weak to change behaviour | LOW | Out of scope to raise. Measure first on `loomwright-studio` after merge (requirement §Measurements); raising to MEDIUM risks heal-loop oscillation on a subjective finding. |
| A MEDIUM structure false positive at the default fix floor MEDIUM starts a heal round. Example: every new `test-*.sh` adds the conventional `ok()`/`no()` helpers, already defined in 160+ files | HIGH | AC4/AC4b. The advisory is a hint; the MEDIUM finding needs confirmed same non-trivial logic and is never raised for a `deliberate per-file convention`. The facts output shows the file count, so a convention reads as one. This PR's own `test-module-shape-facts.sh` is the live negative case at its Phase 4.5. |
| An empty facts output read as "clean" (fail-SAFE reader consumed by a review lens) | MEDIUM | AC12. The prompt states that absence means "facts unavailable"; the test pins every empty case with its stderr reason. |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 2
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-26-module-layout-standard.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-10-26T16:03:25Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/713
- **Branch:** feature/module-layout-standard
- **Files changed:** 21
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Module-layout standard shipped as v17.18.0 (§"Module layout", Launch Pad action 13, Plan Reviewer Criterion 21, worker rule, module-shape-facts.sh + Phase 4.5 step 1h, code-reviewer step 5d). Phase 4.5 found and fixed 5 at-floor issues over 3 iterations (2dd36bf, 72a95ae, f04e5bf); the iteration-3 fix (NUL-safe byte-framed counter) was not re-reviewed. Ground truth 2/2, pin mutations 33 held / 0 not_held, rules gate none, rules audit clean. Drain dispatch suppressed under /automate (owned drain follows).

## Not verified
- **Plan Reviewer Criterion 21 and Launch Pad Phase 3 action 13 model behaviour** — prompt text only; no live Plan Reviewer / Launch Pad probe run (subtask 1)
- **Phase 4.5 step 1h threading MODULE-SHAPE ADVISORY into a live code-reviewer spawn** — needs a multi-step Supervisor Phase 4.5 run (subtask 2)
- **check-version-bump.sh in the bumped state** — needs the fragment committed, then bump-version.sh run and committed (subtask 2)
