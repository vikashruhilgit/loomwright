# Supervisor Job: Plan Review checks the brief against the source requirement; Product Owner stories carry Non-goals, Owner decisions and Validation

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-11-02-173506/L2
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1
- **Source requirement:** .supervisor/requirements/2026-11-02-124022-requirement-to-plan-checks.md
- **Base commit:** 38eb8e4627947356b62a7980de90fda6f790beb8

> **Warning (1):** this checkout is lane `L2` of the `/automate --parallel` wave `automate-2026-11-02-173506`. Sibling lane `L1` (`2026-11-02-120032-drain-dismissals-carry-checkable-evidence.md`) runs at the same time in its own clone. Its Touches (`review-heal-next-step.sh`, `automate-dismissed.sh`, their tests, two `result-schemas/review-heal-*.md`, `skills/review-heal/SKILL.md`, its own `changelog.d/` fragment) share no file with this brief. The one possible meeting point is `loomwright/docs/prompt-token-budgets.json` / `ARCHITECTURE_CONTRACTS.md` if L1 also re-baselines a budget (see Risk Assessment). Lane PRs carry a `changelog.d/` fragment only and never bump; `wave-build` folds the bump.

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Markdown prompts, one Python validator, bash tests: all existing stack |
| 2 | Dependency Availability | GO | No new dependency. `claude -p --plugin-dir` (Validation 3–4) is the same CLI the repo already uses for live probes |
| 3 | Architecture Fit | GO | Reuses the existing Plan Reviewer (owner decision: no new agent) and the existing Story Template; the validation gate and lane readiness are unchanged |
| 4 | Scope vs Supervisor Capability | CAUTION | ~31 files across two independent parts; needs a stated split (`genuine-parallelism`) |
| 5 | Hard Blockers | CAUTION | Validation 3–4 need live headless `claude -p` runs from a worker (auth, cost, wall-clock); not a code blocker |

**Overall Verdict:** CAUTION

## Task
**Goal:** Plan Review compares every brief with its source requirement in a two-way, line-by-line mapping (Part A), and Product Owner's Story Template carries Non-goals, Owner decisions and a gate-parseable `## Validation (must pass before merge)` section (Part B).

**Problem Statement:**
The plugin owner, who hands a requirement to `/launch-pad` or `/automate`, needs the plan to be checked against what they asked for, and needs prompt-sourced stories to carry the decisions and proof a run obeys, because each run receives only its item file and its brief.
Currently, Plan Reviewer receives only the brief and a CLAUDE.md excerpt, never the requirement, so a well-formed brief that misreads the requirement passes every check and every later check (Rubric Grader, Phase 4.5) inherits the error. And Product Owner's Story Template (`skills/user-story-writing/SKILL.md` §"Story Template") has no Non-goals, Owner decisions or Validation section, so `validation-gate` prints `none` for every prompt-sourced item and the owner's decisions stay in the chat report.
Success looks like: a brief missing a requirement line FAILs Plan Review (`under`), an extra subtask is a MEDIUM refine (`over`), supporting work is never `extra`; every persisted PO story carries a gate-parseable Validation section, its owner decisions and its non-goals.

**Owner decisions (copied verbatim in meaning from the source requirement — obey them):**
- Part A: the check is a two-way mapping and the rating follows from it (each requirement line → the subtask that covers it, or `missing`; each subtask → the requirement line it serves, or `extra`), not a single free-form verdict. Reuse the existing Plan Reviewer; no new agent. Tests, the changelog fragment and doc or budget updates are supporting work, never `extra`. With a literal one-line goal (no requirement file), only the `extra` check applies. An `extra` subtask is MEDIUM (Launch Pad refines it: removes the subtask or links it to the requirement line it serves); a `missing` requirement line stays a failure.
- Part B: add only Non-goals, Owner decisions and Validation — no other new section. Product Owner still writes outcomes, not implementation: Validation names the proof (what must be shown, and the project's own test or CI command when CLAUDE.md names one), never how to build it.

**Non-goals (from the requirement's owner decisions and assumptions):**
- No new agent, no new Plan Review decision value, no change to Plan Review's other 21 criteria or to the Decision Matrix rows other than the one new requirement-fit row.
- No change to `validation-gate`, `lane-readiness` or their shared reader (`loomwright/scripts/automate-lanes.d/readiness.sh`) — they already read a `## Validation` section.
- No new Story Template section beyond Non-goals, Owner decisions and Validation.
- No new key in `LAUNCH_PAD_RESULT` (its key set is closed; `validate-launch-pad-result.py --raw` blocks unknown keys).

**Design decisions this brief makes (Launch Pad, grounded below — not owner decisions):**
- **D1 — Criterion 22 "Requirement Fit"** is added to `agents/plan-reviewer.md` after Criterion 21. Its `extra` half always runs; its coverage (`missing`) half runs only when the spawn prompt carries the requirement. Requirement lines = each acceptance criterion, each Goal/Scope item, each Validation entry and each non-goal of the requirement. Brief units = each subtask, and, in a single-subtask brief, each acceptance criterion and File Impact Map group (briefs default to one subtask, so a subtask-only mapping could never find `extra`).
- **D2 — rating field.** `PLAN_REVIEW_RESULT` gains an optional top-level `requirement_fit: fulfils | under | over | skipped` (schema_version stays `1`; additive). `under` when ≥1 line is `missing` (wins over `over`); `over` when ≥1 unit is `extra` and none is `missing`; `fulfils` otherwise; `skipped` only when the brief's `## Environment` names a `Source requirement:` but the spawn prompt carries no requirement (an older Launch Pad) — never reported as passed. With a literal goal (no `Source requirement:` line) the rating comes from the `extra` check alone and the summary states `coverage check skipped (literal goal)`.
- **D3 — issue category `requirement_fit`.** `missing` line → HIGH (decision FAIL); a unit that delivers a requirement non-goal → HIGH (FAIL); `extra` unit → MEDIUM (decision stays PASS; Launch Pad refines at its fix floor); `skipped` → one LOW note.
- **D4 — mapping shown line by line.** The reviewer emits a `### Requirement fit` table (one row per requirement line → covering unit or `missing`; one row per brief unit → served line, `supporting`, or `extra`) immediately before its `PLAN_REVIEW_RESULT` block; Launch Pad's Phase 5.5 output carries the table.
- **D5 — validator.** `validate-plan-review-result.py` gains rule 7 (`requirement_fit`, when present, is one of the four values; constant `VALID_REQUIREMENT_FIT = ("fulfils", "under", "over", "skipped")`) and rule 8 (`requirement_fit: under` requires `decision: FAIL`). An absent field passes (an older reviewer, and the routed-seat `--raw` path).
- **D6 — Launch Pad passes the requirement.** When `source_requirement` is set, the Phase 5.5 spawn contract carries the requirement file verbatim between `--- SOURCE REQUIREMENT ---` and `--- SOURCE REQUIREMENT END ---` (omitted, both markers included, otherwise — same convention as `--- APPLICABLE RULES ---`). The routed seat receives it because its prompt is the spawn contract's prompt. The FAIL/at-floor refine branch gains one line: a `requirement_fit` `missing` issue is fixed by adding coverage, never by deleting the requirement line; an `extra` one by removing the unit or linking it to the line it serves.
- **D7 — evidence path.** The requirement names `loomwright/docs/evidence/…`; this brief uses the repo's existing root `docs/evidence/` instead, because FINALIZE lists only `git diff … -- docs/evidence/` files in the PR body's `## Evidence` section (`loomwright/skills/async-orchestration/finalize.md`), so a `loomwright/docs/evidence/` file would never be linked from the PR body as Validation 3–4 require. `loomwright/docs/evidence/` does not exist today; root `docs/evidence/` holds the existing evidence files.
- **D8 — PO template shape.** The Story Template gains `### Non-goals` and `### Owner decisions` (H3, like its other prose sections; `none recorded` when no decision was made) and an **H2** `## Validation (must pass before merge)` placed before `## Depends on` — H2 because the validation gate reads only an H2 section (same rule as `## Depends on` / `## Touches`), as a numbered list whose entries open with a bold title (`1. **Static — <check>:** …`, `2. **Running system — <what is shown>:** …`), the list format `_lanes_validation_rows` parses (`loomwright/scripts/automate-lanes.d/readiness.sh`: title = the entry's first `**…**` span; kind `running-system` when the title contains "running system").

## Acceptance Criteria

**Part A — Plan Review checks the brief against the source requirement** (carried forward from the requirement)
- [ ] **A1.** Given a requirement file and a brief that covers every requirement line with nothing extra, when Plan Review runs, then it rates the brief `fulfils` and raises no requirement-fit issue.
- [ ] **A2.** Given a brief that leaves a requirement line uncovered, when Plan Review runs, then it names that line as `missing`, rates the brief `under`, and the review fails, so Launch Pad revises the brief.
- [ ] **A3.** Given a brief with a subtask that serves no requirement line, when Plan Review runs, then it names that subtask as `extra`, rates the brief `over`, and raises a MEDIUM issue that Launch Pad refines.
- [ ] **A4.** Given the review's result, when the owner or Launch Pad reads it, then the mapping is shown line by line (the `### Requirement fit` table, D4), so each `missing` or `extra` can be checked.
- [ ] **A5.** Given a brief whose only unmapped subtasks are tests, a changelog fragment and doc or budget updates, when Plan Review runs, then they count as supporting work and no issue is raised.
- [ ] **A6.** Given a literal one-line goal, when Plan Review runs, then only the `extra` check runs and the result says the coverage check was skipped.
- [ ] **A7.** Given a brief with a subtask that delivers something the requirement lists as a non-goal, when Plan Review runs, then that subtask is flagged (HIGH `requirement_fit`) and the review fails.
- [ ] **A8.** Given Plan Review cannot see the requirement (an older Launch Pad that does not pass it, while the brief names a `Source requirement:`), when it runs, then it reports the requirement-fit check as `skipped`, never as passed.
- [ ] **A9 (supporting — restating copies move with their authority).** Given the PR diff, then every surface that restates Plan Review's criteria count, conditional list, issue categories or result fields names Criterion 22 / `requirement_fit` in the same change: `agents/plan-reviewer.md` (`## 22 Review Criteria`, the never-skip rule, the Decision Matrix PASS row, the Output Format category list, the Quality Checklist), `commands/launch-pad.md` Phase 5.5 step 2, `docs/result-schemas/plan-review-result.md`, `docs/POINTER_AUDIT.md` (a row beside 7b for the SOURCE REQUIREMENT paste), and the count/enum pins in `test-closed-enum-pins-seam.sh`, `test-pr-body-evidence-seam.sh` and `test-rule-conformance-seam.sh`.

**Part B — PO stories carry what an /automate run needs** (carried forward from the requirement)
- [ ] **B1.** Given a prompt, when Product Owner persists a story, then the file has a `## Validation (must pass before merge)` section with at least one entry, in the list format the validation gate parses.
- [ ] **B2.** Given a story whose outcome can only be shown in a running system (a hook firing, an agent's live answer, a UI flow), when Product Owner writes it, then its Validation has a **Running system** entry, so the validation gate requires pasted evidence before READY.
- [ ] **B3.** Given the owner made decisions during the Product Owner session (an answered question gate, a stated constraint), when the story is persisted, then they are in the story's Owner decisions section.
- [ ] **B4.** Given the owner excluded something in the session, when the story is persisted, then it is listed under the story's Non-goals.
- [ ] **B5.** Given no owner decision was made, when the story is persisted, then Owner decisions reads `none recorded`.
- [ ] **B6.** Given a story with only static proof (tests, lint), when it is persisted, then Validation lists those checks and has no Running system entry, and the validation gate reads `none` because nothing needs pasted evidence.
- [ ] **B7.** Given Product Owner cannot name any proof for a story, when it would persist it, then it does not persist an empty Validation section: it raises a flag at its existing confirmation gate, or, when it cannot ask, persists nothing and counts the flag in its `po_gate: needs_owner` line.
- [ ] **B8 (supporting — every copy of the template changes together).** Given the PR diff, then the Story Template in `skills/user-story-writing/SKILL.md`, its filled-in copy `## Example: Staff Scheduling Story` in the same file, Product Owner's Output Format story block (`agents/product-owner.md`), its command mirror (`commands/product-owner.md`), and the Persist step's "The file holds the full story body (…)" list (byte-identical in agent and command — `test-requirement-shape.sh` S5 pins it) all carry Non-goals, Owner decisions and Validation. The command's shortened usage-example output (the `### BD-15: Staff Shift Assignment` sample) stays as it is: it is a sample, not a copy of the template.

**Validation (from the requirement's `## Validation (must pass before merge)`, numbering kept)**
- [ ] **V1 (Part A).** Given the branch, when `bash loomwright/scripts/test-result-validators.sh` runs, then it accepts a Plan Review result carrying `requirement_fit` (each of the four values) and the `requirement_fit` issue category, and rejects a malformed rating (`requirement_fit: partial`) and a `requirement_fit: under` with `decision: PASS`.
- [ ] **V2 (Part B).** Given the branch, when `bash loomwright/scripts/test-requirement-shape.sh` runs, then a new check (S6) passes: the Story Template (extracted from the skill by its own extractor, scoped to the fenced block under `## Story Template` and stopping at `## Example: Staff Scheduling Story`, so the item shape's `## Non-goals` / `## Validation (must pass before merge)` and the plan doc's `## Owner decisions` elsewhere in the skill cannot satisfy it) carries `### Non-goals`, `### Owner decisions` and `## Validation (must pass before merge)` at exactly those heading levels. Each copy (the PO agent's Output Format and the PO command, which nest stories one level deeper) carries the same three heading texts, matched by text whatever their level. The Persist step's file-body list says the Validation section is written at H2 in the persisted file; and a mutation control (M4) — the Story Template's Validation heading removed, while the item shape's identical line survives — turns S6 red.
- [ ] **V3 (Part A, Running system).** Given four seeded requirement + brief pairs committed under `loomwright/scripts/fixtures/plan-review-requirement-fit/` (fulfils; missing a requirement line; one extra subtask; only unmapped subtasks are tests, a changelog fragment and a budget update) plus a `README.md` answer key that no fixture leaks (precedent: `loomwright/scripts/fixtures/pr-body-evidence/README.md`), when the branch's Plan Reviewer runs headless on each (`claude -p --plugin-dir <branch>/loomwright`, which loads only the branch's copy), then the ratings read `fulfils`, `under`, `over`, `fulfils`, and a committed evidence file `docs/evidence/plan-review-requirement-fit.md` contains the exact command, each fixture's verbatim `requirement_fit` line and decision, and the PR body links to it.
- [ ] **V4 (Part B, Running system).** Given a scratch project, when the branch's `/product-owner` runs headless (`claude -p --plugin-dir <branch>/loomwright`) on two prompts — one whose outcome shows only in a running system, one with static proof only — then both persisted stories pass `automate-helpers.sh plan-waves <file> --lint`, the first has a Running system Validation entry and the second does not, and a committed evidence file `docs/evidence/po-story-validation.md` contains the exact commands and both story files verbatim, and the PR body links to it.
- [ ] **V5 (Parts A and B).** Given the branch, then the `plan-reviewer`, `launch-pad` and `product-owner` agent budgets, the `launch-pad` and `product-owner` command budgets and the `user-story-writing` skill budget are re-measured and updated in `loomwright/docs/prompt-token-budgets.json` and the mirror rows of `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets", and `bash scripts/check-token-budget.sh` passes.
- [ ] **V6 (release and suite).** Given the branch, then `changelog.d/2026-11-02-124022-requirement-to-plan-checks.md` exists (format per `changelog.d/README.md`), `bash scripts/check-version-bump.sh` passes, and `bash scripts/ci-local.sh --affected` is green.

**Evidence rule:** V3 and V4 put their evidence in committed `docs/evidence/*.md` files (File Impact Map creates); those files are the acceptance evidence, and no criterion depends on the PR body. Separately, because the source requirement titles its Validation 3 and 4 "Running system", the `/automate` validation gate (`_lanes_validation_rows`) also looks for fenced output in the PR body. FINALIZE has no step that copies evidence into the PR body: its `## Evidence` section only links to `docs/evidence/` files (`loomwright/skills/async-orchestration/finalize.md`). So the expected outcome is a `validation_unrun` park, where the owner pastes the evidence files' fenced verdict blocks under `Validation 3` / `Validation 4` lines, or waives them (see Risk Assessment). This brief does not change FINALIZE.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

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

> How this brief honors them: the criteria count is owned by `agents/plan-reviewer.md` itself (it is not a plugin.json/hooks.json count); every restating copy named in A9/B8 moves in the same change. No new restated count is introduced anywhere — `commands/launch-pad.md` keeps its existing conditional-criteria list, extended in place.

## Touched-file invariants

> Grounded at base `38eb8e4627947356b62a7980de90fda6f790beb8`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/validate-plan-review-result.py`** — keep: the always-exit-0 contract `INVARIANT: ALWAYS exits 0.` and the import-time guard `except BaseException as _import_exc:` (fail SAFE, `{}` on stdout); the existing six rules and their reason strings (`(rule 6)`), and `VALID_DECISION = ("PASS", "FAIL", "NEEDS_HUMAN")` unchanged; reuse: the shared parser helpers `as_text`, `present`, `is_empty_scalar`, `emit` and the `run_validator(main)` entry point — no second parser; update the docstring's `RULE SOURCE: the SIX numbered rules` to name rules 7–8; mirror: `scripts/check-contract-parity.sh` MANIFEST row `plan-reviewer|plan-reviewer.md|PLAN_REVIEW_RESULT|schema_version,decision,issues,severity,section,description,summary` — `requirement_fit` is optional, so the required-field list is unchanged; fired by: `loomwright/hooks/hooks.json` SubagentStop `"matcher": "loomwright:plan-reviewer"`, and Launch Pad's routed seat (`validate-plan-review-result.py --raw`, `agents/launch-pad.md` §"Seat routing"); pinned by: `loomwright/scripts/test-result-validators.sh` (`V_PLAN="$SCRIPT_DIR/validate-plan-review-result.py"`, section `== F. validate-plan-review-result.py — 6 rules ==`).
- **`loomwright/scripts/test-result-validators.sh`** — keep: the `run_v` / `assert_pass` / `assert_fail` helpers and the `mk <name> <<'EOF'` heredoc idiom; add the new cases inside section `# ── F. plan-reviewer validator` (update its echo `— 6 rules` → `— 8 rules`), never a new section elsewhere; pinned by: itself (CI runs it via the `loomwright/scripts/test-*.sh` glob).
- **`loomwright/agents/plan-reviewer.md`** — keep: read-only tool surface `disallowedTools: Write, Edit, NotebookEdit, Task, Bash` (the reviewer cannot read the requirement path itself — the paste is authoritative, like `--- APPLICABLE RULES ---`); every existing criterion 1–21 and its severity unchanged; the Decision Matrix rows unchanged except adding one requirement-fit row; mirror: the Output Format category list `| pin_mutations | pr_body_evidence | module_layout | ...}"  # optional — emit when a criterion mandates it (12–21)` becomes `… | module_layout | requirement_fit | ...}"  # optional — emit when a criterion mandates it (12–22)`; pinned by: `test-closed-enum-pins-seam.sh` (`'## 21 Review Criteria'`, `'All 21 review criteria must be checked'`, `'(21 total, Criteria 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, and 21 conditional)'`, `'All 21 criteria checked'`), `test-pr-body-evidence-seam.sh` (the same plus `'Criteria 11, 13, 14, 15, 16, 17, 18, 19, 20, and 21 are conditional'` and the `(12–21)` enum line), `test-rule-conformance-seam.sh` (`'## 21 Review Criteria'`, `'- [ ] All 21 criteria checked'`).
- **`loomwright/agents/launch-pad.md`** — keep: the spawn contract's `--- APPLICABLE RULES ---` / `--- APPLICABLE RULES END ---` markers and `subagent_type: "loomwright:plan-reviewer"`; the Can't-ask rule's closed `LAUNCH_PAD_RESULT` key set (`validate-launch-pad-result.py --raw` blocks any unknown key) — add no key; the FAIL-branch sentence `A Criterion 20 \`pr_body_evidence\` issue is fixed by rewriting that criterion in the evidence-file form its suggestion gives` verbatim; reuse: `source_requirement` (Phase 2 step 0 already holds it) as the trigger for the new block; pinned by: `test-rule-conformance-seam.sh` (`bhas "$SPAWN" '--- APPLICABLE RULES ---'`), `test-pr-body-evidence-seam.sh` (the Criterion 20 FAIL-branch sentence).
- **`loomwright/commands/launch-pad.md`** — keep: Phase 5.5 step 2's conditional list `Criteria 11, 13, 14, 15, 16, 17, 18, 19, 20, and 21 are conditional` (extend in place for Criterion 22's coverage half; the list mirrors `agents/plan-reviewer.md`).
- **`loomwright/docs/result-schemas/plan-review-result.md`** — keep: `schema_version: 1` and every existing `**Validation rules:**` bullet unchanged, except the `category` bullet's canonical list, which gains `requirement_fit`; mirror: the category comment and the `category` rule list gain `requirement_fit`; add the `requirement_fit` field and its two rules (D5) exactly as the validator enforces them; pinned by: `test-pr-body-evidence-seam.sh` (`'"pr_body_evidence" for Criterion 20 findings'`, `` '`pr_body_evidence` for Criterion 20 (' ``) — keep both literals intact.
- **`loomwright/docs/POINTER_AUDIT.md`** — keep: row `| 7b | Launch Pad → Plan Reviewer house-rules paste`; add the SOURCE REQUIREMENT paste as its own row beside it (same column shape).
- **`loomwright/scripts/test-closed-enum-pins-seam.sh`, `test-pr-body-evidence-seam.sh`, `test-rule-conformance-seam.sh`** — keep: each file's `has` / `bhas` / `lacks` helpers and the `ok` / `no` tallies; update only the count pins (21 → 22, and `lacks … '## 21 Review Criteria'` in place of `'## 20 Review Criteria'`) and the `(12–21)` enum-line pin; every other pin unchanged.
- **`loomwright/agents/product-owner.md` and `loomwright/commands/product-owner.md`** — keep: the Persist step byte-identical between the two (`test-requirement-shape.sh` S5: `pa="$(grep -F '**Persist**' "$PO_AGENT")"; pc="$(grep -F '**Persist**' "$PO_CMD")"`), with `plan-waves <each persisted file> --lint\`` still before `right-size <each persisted file>\`` and the aim sentence after it; the can't-ask count line `po_gate: needs_owner (<n> flags)` (B7 adds a flag kind, not a new line), and the flag-count formula `` `<n>` = prerequisite flags + architecture conflicts + house-rule conflicts `` extended by APPEND only (`… + house-rule conflicts + missing-proof flags`) so the existing substring survives; the plan-doc pattern `.supervisor/requirements/_BACKLOG-{YYYY-MM-DD-HHMMSS}-{slug}.md` and the `Read prior stories** by globbing` sentence (S4); never write "PR body" / "PR description" in new PO prose unless the same line also names `docs/evidence`, `evidence-file form`, `Criterion 20`, `Evidence rule` or `every review criterion` (the guard below). Pinned by: `test-requirement-shape.sh` (S4, S5); `test-rule-conformance-seam.sh` (`'`<n>` = prerequisite flags + architecture conflicts + house-rule conflicts'`, `'`po_gate: needs_owner (<n> flags)`'`); `test-non-interactive-gates-seam.sh` (`*'`po_gate: needs_owner (<n> flags)`'*`); `test-pr-body-evidence-seam.sh` (the authoring-surface guard `grep -viE 'docs/evidence|evidence-file form|Criterion 20|Evidence rule|every review criterion'` over both PO files). These tests are not in Subtask 2's lanes: Subtask 2 keeps their literals intact and never edits them.
- **`loomwright/skills/user-story-writing/SKILL.md`** — keep: the plan-doc template markers `<!-- plan-doc-template:begin -->` / `<!-- plan-doc-template:end -->` and its eight sections (S1–S3, M1–M2); `Check it with \`automate-helpers.sh right-size <item>\`` (M3's mutant anchor) and the aim sentence; the `**Machine-read sections (\`## Depends on\`, \`## Touches\`).**` rules — `## Depends on` / `## Touches` stay the story's last sections, so the new H2 Validation goes before them. Pinned by: `test-requirement-shape.sh` (S1–S5, M1–M3) and `test-pr-body-evidence-seam.sh` — its `### Item rules` block pins `'**Evidence lives in a committed file, never the PR body.**'` and `` '`## Validation (must pass before merge)` running-system steps are different' ``, and its authoring-surface guard covers this skill too. The same rule applies: new prose naming the PR body must also name `docs/evidence`, the `Evidence rule` or `Criterion 20` on that line.
- **`loomwright/scripts/test-requirement-shape.sh`** — keep: `. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"`, and the idiom of extracting from the skill instead of copying. `extract_template` reads only the plan-doc markers, so S6 needs a sibling extractor scoped to the `## Story Template` fenced block (V2); S1–S5 and M1–M3 unchanged, the closing `[ "$fail" -eq 0 ]`; add S6 and M4 in the same style, and gate M4's mutant on non-empty + differs-from-original before trusting it (lesson `fa32a308`).
- **`loomwright/docs/prompt-token-budgets.json` and `loomwright/docs/ARCHITECTURE_CONTRACTS.md`** — keep: the JSON row shape `{"budget": N, "measured": M, "note": "…"}` and the "Raise rule" (raise in the same PR that breaches it, measured + ~10%, plus the mirror table row); pinned by: `scripts/check-token-budget.sh` (fails CLOSED on a mismatch).

## Closed enumerations touched

> Sibling grep at base `38eb8e4627947356b62a7980de90fda6f790beb8`: `grep -rnF 'module_layout' --exclude=CHANGELOG.md --exclude-dir=.supervisor --exclude-dir=.git .` → 7 hits in 4 files. (`module_layout` is the most recently added Plan Review category.)

- **`requirement_fit`** (issue category; sibling: `module_layout`) — must be named in:
  - `loomwright/agents/plan-reviewer.md` — the Output Format category list (`| module_layout | ...}"`) — extend; the Quality Checklist `All 21 criteria checked (…)` item — extend (names each criterion's category); the new Criterion 22's own `**Issue category:**` line — add.
  - `loomwright/docs/result-schemas/plan-review-result.md` — the `category:` comment and the `category` validation rule's canonical list — extend.
  - `loomwright/scripts/test-pr-body-evidence-seam.sh` — pins the Output Format list line verbatim (`| pin_mutations | pr_body_evidence | module_layout | ...}"`) — extend the pin.
  - `loomwright/scripts/test-closed-enum-pins-seam.sh` — `'**Issue category:** \`module_layout\`.'` — no change: it pins Criterion 21's own category line, not a list of all categories.
- **`fulfils` / `under` / `over` / `skipped`** (new `requirement_fit` values; no sibling — a new field) — must be named in: `loomwright/scripts/validate-plan-review-result.py` (`VALID_REQUIREMENT_FIT`, D5), `loomwright/docs/result-schemas/plan-review-result.md` (field + rule), `loomwright/agents/plan-reviewer.md` (Criterion 22 and the Output Format block). `scripts/check-contract-parity.sh` enum rows (`agents/plan-reviewer.md|decision|PASS,FAIL,NEEDS_HUMAN,enum`) — no change required: the field is optional and parity's MANIFEST lists required fields only; adding an enum row is allowed but not in scope.

- **missing-proof flags** (a new Product Owner can't-ask flag kind, B7; sibling: `house-rule conflicts`) — must be named in:
  - `loomwright/agents/product-owner.md` — the count formula `` `<n>` = prerequisite flags + architecture conflicts + house-rule conflicts `` (Responsibilities 3a, Can't-ask branch) — extend, as an append.
  - `loomwright/commands/product-owner.md` — the same formula in its mirror of that step — extend, as an append (identical text).
  - `loomwright/agents/product-owner.md` / `commands/product-owner.md` — the Assumption Check flag list that the confirmation gate presents (Context Setup step 4 / Output Format `### Assumption Check`) — extend, so the missing-proof flag is raised at the existing gate.
  - `loomwright/scripts/test-rule-conformance-seam.sh` — pins the formula's existing substring — no change: an append keeps it matching (outside Subtask 2's lanes).

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-result-validators.sh` — malformed rating `requirement_fit: partial` rejected (V1) | flip `("fulfils", "under", "over", "skipped")` → `("fulfils", "under", "over", "skipped", "partial")` in `loomwright/scripts/validate-plan-review-result.py` |
| `loomwright/scripts/test-result-validators.sh` — `requirement_fit: under` with `decision: PASS` rejected (V1, rule 8) | delete the rule-8 `emit(False, …)` call for `under` without FAIL in `loomwright/scripts/validate-plan-review-result.py` (reviewer applies it; the worker names the exact literal in its hand-back) |
| `loomwright/scripts/test-requirement-shape.sh` — S6 Story Template carries `## Validation (must pass before merge)` (V2; the test's own M4 is this mutation) | delete the Story Template's `## Validation (must pass before merge)` line (inside `## Story Template`, not the hand-written item shape above it) in `loomwright/skills/user-story-writing/SKILL.md` |
| `loomwright/scripts/test-closed-enum-pins-seam.sh` — `'## 22 Review Criteria'` | flip `## 22 Review Criteria` → `## 21 Review Criteria` in `loomwright/agents/plan-reviewer.md` |
| `loomwright/scripts/test-pr-body-evidence-seam.sh` — `'## 22 Review Criteria'` and the `(12–22)` enum line | flip `| module_layout | requirement_fit |` → `| module_layout |` in `loomwright/agents/plan-reviewer.md` |
| `loomwright/scripts/test-rule-conformance-seam.sh` — `'- [ ] All 22 criteria checked'` | flip `- [ ] All 22 criteria checked` → `- [ ] All 21 criteria checked` in `loomwright/agents/plan-reviewer.md` |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Part A — Plan Review requirement fit (Criterion 22, `requirement_fit` field + validator, Launch Pad passes the requirement, fixtures, live evidence) | A1–A9, V1, V3 | 10 modify, 10 create | `skills/supervisor-readiness/SKILL.md`, `skills/quality-checklist/SKILL.md` | LAUNCHABLE |
| 2 | Part B — Story Template carries Non-goals, Owner decisions, Validation (skill, PO agent + command, shape test, live evidence) | B1–B8, V2, V4 | 4 modify, 1 create | `skills/user-story-writing/SKILL.md`, `skills/quality-checklist/SKILL.md` | LAUNCHABLE |
| 3 | Budgets, changelog fragment, suite | V5, V6 | 2 modify, 1 create | `skills/quality-checklist/SKILL.md` | BLOCKED (by #1, #2) |

### File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| Part A — reviewer | `loomwright/agents/plan-reviewer.md` (374), `loomwright/docs/result-schemas/plan-review-result.md` (34), `loomwright/scripts/validate-plan-review-result.py` (166), `loomwright/scripts/test-result-validators.sh` (4509 — append to its existing § F plan-reviewer block, the single home of this validator's cases) | — | HIGH |
| Part A — Launch Pad seam | `loomwright/agents/launch-pad.md` (885 — extends the Phase 5.5 spawn contract and FAIL branch it already owns), `loomwright/commands/launch-pad.md` (242), `loomwright/docs/POINTER_AUDIT.md` (194) | — | HIGH |
| Part A — restated pins | `loomwright/scripts/test-closed-enum-pins-seam.sh` (262), `loomwright/scripts/test-pr-body-evidence-seam.sh` (295), `loomwright/scripts/test-rule-conformance-seam.sh` (463) | — | HIGH |
| Part A — fixtures + evidence | — | `loomwright/scripts/fixtures/plan-review-requirement-fit/README.md` (answer key) and 8 fixture files (`{fulfils,missing,extra,supporting}-requirement.md`, `{fulfils,missing,extra,supporting}-brief.md`) — a new module (CREATE), `docs/evidence/plan-review-requirement-fit.md` | HIGH (names MEDIUM) |
| Part B | `loomwright/skills/user-story-writing/SKILL.md` (305), `loomwright/agents/product-owner.md` (608 — extends the Persist step and Output Format story block it already owns), `loomwright/commands/product-owner.md` (692 — the mirror the S5 pin keeps byte-identical; must change with the agent), `loomwright/scripts/test-requirement-shape.sh` (181) | `docs/evidence/po-story-validation.md` | HIGH |
| Budgets + release | `loomwright/docs/prompt-token-budgets.json` (93), `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (1051 — the budget mirror rows it already owns) | `changelog.d/2026-11-02-124022-requirement-to-plan-checks.md` | HIGH |

> **Module layout:** every new responsibility has one home — Criterion 22 in `agents/plan-reviewer.md` (374, under the threshold); the `requirement_fit` rules in the existing validator (166); fixtures in a new `fixtures/plan-review-requirement-fit/` module; S6/M4 in the existing shape test (181). Each append to a file at or past 500 lines carries its reason above (an extension of a responsibility that file already owns). No helper is copied: no new script is added.
>
> **Validator-owned surfaces:** `scripts/check-doc-currency.sh` scans `loomwright/agents/`, `loomwright/commands/`, `loomwright/skills/`, `loomwright/docs/ARCHITECTURE_CONTRACTS.md` — no version/count claim it verifies is added. `scripts/check-token-budget.sh` owns `prompt-token-budgets.json` + the mirror rows (subtask 3). `scripts/check-prompt-history-refs.sh` scans agent/command/skill files against `loomwright/docs/prompt-history-refs-baseline.json` (may only go down): no history reference (incident numbers, "added in vX") goes into the new prompt text — put the story in the changelog fragment.

### File Overlap Detection

| Group A | Group B | Overlapping Files | Serialization Required |
|---------|---------|-------------------|----------------------|
| Subtask 1 | Subtask 2 | none | NO |
| Subtask 1 | Subtask 3 | none (3 re-measures 1's files, never edits them) | YES (3 requires 1's final sizes) |
| Subtask 2 | Subtask 3 | none (same) | YES (3 requires 2's final sizes) |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/agents/plan-reviewer.md", name: "22. Requirement Fit"}
  - {kind: "symbol", path: "loomwright/agents/plan-reviewer.md", name: "## 22 Review Criteria"}
  - {kind: "symbol", path: "loomwright/scripts/validate-plan-review-result.py", name: "VALID_REQUIREMENT_FIT"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/plan-review-result.md", name: "requirement_fit"}
  - {kind: "symbol", path: "loomwright/agents/launch-pad.md", name: "--- SOURCE REQUIREMENT ---"}
  - {kind: "symbol", path: "loomwright/docs/POINTER_AUDIT.md", name: "SOURCE REQUIREMENT"}
  - {kind: "file", path: "loomwright/scripts/fixtures/plan-review-requirement-fit/README.md"}
  - {kind: "file", path: "docs/evidence/plan-review-requirement-fit.md"}
requires: []
lanes:
  - "loomwright/agents/plan-reviewer.md"
  - "loomwright/agents/launch-pad.md"
  - "loomwright/commands/launch-pad.md"
  - "loomwright/docs/result-schemas/plan-review-result.md"
  - "loomwright/docs/POINTER_AUDIT.md"
  - "loomwright/scripts/validate-plan-review-result.py"
  - "loomwright/scripts/test-result-validators.sh"
  - "loomwright/scripts/test-closed-enum-pins-seam.sh"
  - "loomwright/scripts/test-pr-body-evidence-seam.sh"
  - "loomwright/scripts/test-rule-conformance-seam.sh"
  - "loomwright/scripts/fixtures/plan-review-requirement-fit/**"
  - "docs/evidence/plan-review-requirement-fit.md"
external_requires:
  - "claude CLI (headless `claude -p --plugin-dir <branch>/loomwright`) for the V3 live runs"

# Subtask 2
provides:
  - {kind: "symbol", path: "loomwright/skills/user-story-writing/SKILL.md", name: "## Validation (must pass before merge)"}
  - {kind: "symbol", path: "loomwright/skills/user-story-writing/SKILL.md", name: "### Owner decisions"}
  - {kind: "symbol", path: "loomwright/skills/user-story-writing/SKILL.md", name: "### Non-goals"}
  - {kind: "symbol", path: "loomwright/agents/product-owner.md", name: "Owner decisions"}
  - {kind: "symbol", path: "loomwright/commands/product-owner.md", name: "Owner decisions"}
  - {kind: "symbol", path: "loomwright/scripts/test-requirement-shape.sh", name: "(S6)"}
  - {kind: "symbol", path: "loomwright/scripts/test-requirement-shape.sh", name: "(M4)"}
  - {kind: "file", path: "docs/evidence/po-story-validation.md"}
requires: []
lanes:
  - "loomwright/skills/user-story-writing/SKILL.md"
  - "loomwright/agents/product-owner.md"
  - "loomwright/commands/product-owner.md"
  - "loomwright/scripts/test-requirement-shape.sh"
  - "docs/evidence/po-story-validation.md"
external_requires:
  - "claude CLI (headless `claude -p --plugin-dir <branch>/loomwright`) for the V4 live runs"

# Subtask 3
provides:
  - {kind: "symbol", path: "loomwright/docs/prompt-token-budgets.json", name: "plan-reviewer"}
  - {kind: "symbol", path: "loomwright/docs/prompt-token-budgets.json", name: "user-story-writing"}
  - {kind: "symbol", path: "loomwright/docs/ARCHITECTURE_CONTRACTS.md", name: "Prompt Token Budgets"}
  - {kind: "file", path: "changelog.d/2026-11-02-124022-requirement-to-plan-checks.md"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/agents/plan-reviewer.md", name: "## 22 Review Criteria"}
  - {from: "1", kind: "symbol", path: "loomwright/agents/launch-pad.md", name: "--- SOURCE REQUIREMENT ---"}
  - {from: "2", kind: "symbol", path: "loomwright/agents/product-owner.md", name: "Owner decisions"}
  - {from: "2", kind: "symbol", path: "loomwright/skills/user-story-writing/SKILL.md", name: "## Validation (must pass before merge)"}
lanes:
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "changelog.d/2026-11-02-124022-requirement-to-plan-checks.md"
external_requires: []
```

> **Fragment, no bump (lane rule):** this lane's PR carries the `changelog.d/` fragment only and never runs `bump-version.sh` (wave-build folds the bump), so the fragment survives subtask 3 and is listed as its `provides`. Bump detection is per run mode: `bash scripts/check-version-bump.sh` is the release check either way.

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──┐
            ├──→ Subtask 3
Subtask 2 ──┘
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none | NO |
| Subtask 1 | Subtask 3 | none | YES (requires) |
| Subtask 2 | Subtask 3 | none | YES (requires) |

### Batch Plan
- **Batch 1:** Subtask 1, Subtask 2 (parallel — both have empty `requires`, zero file overlap)
- **Batch 2:** Subtask 3 (after Subtasks 1 and 2 — re-measures their final prompt sizes)
- **Recommended workers:** 2
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/supervisor-readiness/SKILL.md` (brief sections the reviewer judges), `skills/quality-checklist/SKILL.md` |
| 2 | `skills/user-story-writing/SKILL.md` (the template authority it edits), `skills/quality-checklist/SKILL.md` |
| 3 | `skills/quality-checklist/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Scope: ~31 files across two parts (Feasibility (Phase 2.5), check 4) | MEDIUM | Split `genuine-parallelism` into two zero-overlap parts plus one dependent budgets/release subtask |
| Live headless runs (V3, V4) need `claude` auth, cost and wall-clock inside a worker turn (Feasibility (Phase 2.5), check 5) | MEDIUM | Each is a handful of short `claude -p` calls; record the exact commands in the evidence file. If a run cannot execute in the worker, the evidence file says so explicitly (`not run: <reason>`) — never a fabricated verdict — and the `/automate` validation gate parks for the owner |
| Evidence path deviates from the requirement's literal `loomwright/docs/evidence/` (D7) | MEDIUM | Root `docs/evidence/` is where FINALIZE's `## Evidence` diff filter looks; the requirement's intent ("the PR body links to it") is only met there. State the deviation in the changelog fragment and PR body |
| Each Plan Review spawn grows by the requirement's size (up to 3 spawns/session) — from the requirement's Risks | MEDIUM | Paste only when `source_requirement` is set; budgets re-measured in subtask 3 (V5) |
| A strict reviewer calls a needed refactor `extra` — from the requirement's Risks | LOW | Supporting-work rule (tests, changelog, docs, budgets) and the MEDIUM severity: an `extra` never stops a run |
| Single-subtask briefs could never surface `extra` if units were subtasks only | MEDIUM | D1: in a single-subtask brief the units are its acceptance criteria and File Impact Map groups |
| Count pins in three seam tests break on 21 → 22 (they pin the reviewer's count text) | MEDIUM | Subtask 1 owns all three tests in its lanes and updates only the count/enum pins (Pin mutations above) |
| PO writes weak Validation entries ("tests pass") — from the requirement's Risks | LOW | The Running system rule plus the existing validation gate: only entries needing evidence are gated |
| `prompt-token-budgets.json` / `ARCHITECTURE_CONTRACTS.md` merge conflict with sibling lane L1 at wave-build if L1 re-baselines `review-heal` | LOW | Edit only this brief's six rows; rows are line-separate, so a conflict is textual and resolvable at wave-build |
| V3/V4 are titled "Running system" in the source requirement. A PR body that only links to the evidence file reads NOT-RUN in `validation-gate`, and the lane's READY park escalates `validation_unrun` | MEDIUM | Expected, not avoided. FINALIZE only links to evidence files, so the lane parks `validation_unrun` at READY. The owner then pastes each evidence file's fenced verdict block into the PR body under `Validation 3` / `Validation 4` lines, or waives it (`validation-gate --waive`). The committed evidence file stays the acceptance evidence (Criterion 20) |
| Subtask 2's prose is pinned by tests outside its lanes (`test-pr-body-evidence-seam.sh` and `test-rule-conformance-seam.sh` are in Subtask 1's lanes; `test-non-interactive-gates-seam.sh` is in no lane) | MEDIUM | Touched-file invariants list every such pin. Subtask 2 keeps those literals intact (append-only formula, no bare "PR body" lines) and never edits those tests |
| `check-token-budget.sh` may be red in Subtask 1/2 worktrees, since `plan-reviewer` is at measured 8591 of budget 9451, until Subtask 3 re-measures | LOW | Expected. Workers 1 and 2 do not cut required prose to fit. Subtask 3 re-baselines every budget (measured + ~10%) and owns the green run |
| Prompt history references in new prompt text fail `check-prompt-history-refs.sh` (baseline may only go down) | LOW | Keep incident/version stories in the changelog fragment, never in agent/command/skill text |

## Configuration
- **Workers:** 2
- **Mode:** parallel
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** genuine-parallelism

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-02-requirement-to-plan-checks.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-11-02T14:56:09Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/802
- **Branch:** feature/requirement-to-plan-checks
- **Files changed:** 28
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** unknown (no_driver_handover)
- **Summary:** Resumed via --continue after the prior session ended mid-EXECUTE. Subtasks 1 (Plan Review Criterion 22 requirement fit) and 2 (Story Template Non-goals / Owner decisions / Validation) were gated and merged; subtask 3 re-baselined six prompt budgets and added the minor changelog fragment. The full pre-push ci-local caught a pipefail grep -q violation in test-requirement-shape.sh, which a fix worker corrected before the push; the final full ci-local passed. Phase 4.5 round 1 PASS (consistency_audit) with 3 MEDIUM + 3 LOW findings dismissed below the HIGH fix floor and posted as a round=1 marker comment.

## Not verified
- **A6 (literal goal: only the extra check runs) and A7 (a unit delivering a requirement non-goal)** — not run live; pinned by prompt text and seam tests only (subtask 1)
- **validation-gate Running system rows V3/V4** — PR body links the evidence files but does not paste fenced verdict output, so validation-gate may read them unrun until the owner pastes or waives (subtasks 1, 2)
