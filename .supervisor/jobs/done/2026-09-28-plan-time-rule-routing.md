# Supervisor Job: Rules reach the PLAN — Launch Pad routes applicable house rules into the brief, a `rule:` Executable Acceptance kind delegates to `rules-check.sh`, and Plan Reviewer Criterion 17 gates rule conformance

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** code tree clean apart from the tracked `.supervisor/automate/` run-trail edit; branch: main == origin/main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (there is an orphaned worktree from the merged relicense PR #289 under the f9195faa session scratchpad, on branch `chore/relicense-polyform-shield`. It is unrelated to this job; leave it alone.)
- **Source requirement:** .supervisor/requirements/automate-followups/05-plan-time-rule-routing.md
- **Base commit:** 966ad8a04c6657c481edd4b3f2b1093c482a0c01

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | The change is bash scripts plus agent-prompt markdown. It must stay macOS bash 3.2 compatible. |
| 2 | Dependency Availability | GO | No new dependency. `jq` is already required by every script touched. |
| 3 | Architecture Fit | GO | It extends the existing advisory-reader pattern (`read-rules.sh`, args never stdin) and the existing `## Executable Acceptance` kind dispatch. `rules-check.sh` stays the SOLE executor of a rule's `check` (skills/rules/SKILL.md §9). |
| 4 | Scope vs Supervisor Capability | CAUTION | About 25 files are affected (8 + 12 modify + 5 create), so the `context-bound` predicate (>12 files) fires. It is split into 2 sequential subtasks: runtime scripts first, then prompts, docs and release. Earlier items in this queue hit the 40-turn worker limit even with fewer files. |
| 5 | Hard Blockers | GO | None. The live store (`.agent/rules/*.json`) holds 3 `advisory` rules and 0 `must` rules, so every must-rule behavior has to be exercised against sandbox fixtures, never the live store. |

**Overall Verdict:** CAUTION (scope size — mitigated by the context-bound split)

## Task
**Goal:** A brief carries the house rules that apply to its own File Impact Map. The existing brief-save gate (Plan Review) refuses a plan that contradicts an applicable `must` rule, or that silently drops a checkable `must` rule from its own `## Executable Acceptance`. A `rule: <id>` acceptance bullet is resolved by DELEGATING to `rules-check.sh --if-stamped`. `run-ground-truth.sh` never reads `.agent/rules/` and never runs a `check` itself.

**Problem Statement:** The house-rules store is consumed only downstream of implementation: by the worker's advisory paste and by the Phase 4.5 replay. A plan can therefore propose exactly what a `must` rule forbids, and the cost of discovering that is a full worker run plus a review round. Launch Pad already computes the File Impact Map path set that the reader routes on, and never passes it to the reader. Plan Reviewer, the cheapest gate in the system, cannot see the store.

## Design decisions (settled here so the worker does not choose)
1. **Rule ids must be visible to the planner.** Today `read-rules.sh` renders statement, category and check, but never the `id`, and a `rule: <id>` bullet needs the id. Add an **opt-in `--with-ids` flag** to `read-rules.sh`. When it is present, each rendered rule gains one `  - id: <id>` line and one `  - enforcement: <advisory|must>` line. Default output (flag absent) stays **byte-identical**, so the worker paste, the Phase 4.5 seam and their token budgets are untouched.
   - Argument handling: `--with-ids` is recognized only as an exact token; every other positional stays a touched path, exactly as today.
   - Routing, validation, dedup, supersession and the schema are UNCHANGED (requirement Out of scope).
   - Ids can be long statement slugs. That is accepted: the store owns id length, not this item.
2. **`rules-check.sh --list-selected`** is a new, read-only enumeration mode.
   - It prints the id of every rule the execute loop WOULD select (enforcement `must` AND a non-null string `check`, after the same validation and first-seen dedup), one per line, sorted, and exits 0.
   - It executes NOTHING, writes NO stamp, and never prompts. It short-circuits the MODE block (no TTY prompt, no confirm/if-stamped branch) and exits right after the selection is computed, before the `--if-stamped` comparison and the execute loop. It therefore wins over `--confirm`, `--if-stamped` AND `--no-cmd` when combined with them: listing ids executes nothing, so the no-cmd valve has nothing to guard.
   - This lets a caller learn whether an id is checkable without reading `.agent/rules/` itself. `rules-check.sh` stays the one script that parses a `check`.
3. **`rule:` is a fourth `## Executable Acceptance` kind.**
   - `exec-acceptance-lib.sh`'s `classify_kind` returns `rule` for a `rule:` prefix. This keeps a `rule:` bullet out of the `cmd` class: it is never hashed into the content-keyed brief stamp, never flagged by Criterion 14, and never run as `bash -c "rule: …"`. Today an unrecognized kind falls through to bare `cmd`, which would EXECUTE the literal text. That makes this lib change a precondition, not a nicety.
   - `run-ground-truth.sh` resolves every `rule:` bullet by delegation, as follows.
   - **(a)** Call `bash "$SCRIPT_DIR/rules-check.sh" --list-selected` ONCE, with cwd = `PROJECT_ROOT` and stdin `</dev/null`. An id not in that list gets per_check `fail`, reason `rule_not_found`: named, never a silent pass. This covers an absent id AND an id that names an `advisory` or null-check rule.
   - **(b) No-cmd short-circuit (Plan Review finding: output forgery).** When the runner's own `--no-cmd` / `GROUND_TRUTH_NO_CMD=1` is set, do NOT invoke `rules-check.sh --if-stamped` at all and parse no PASS/FAIL. Record every listed id as `unverified`, reason `rule_cmd_disabled`. A rule check is arbitrary shell, so the unattended valve must reach it, and `rules-check.sh` echoes raw check text on its `[SKIP] <id>: <check> (cmd execution disabled)` lines. A committed, model-writable check containing a newline plus `  [PASS] <id>` could otherwise forge a pass for an unexecuted, unapproved rule. Under no-cmd, `rules-check.sh` never consults the stamp.
   - **(c)** Otherwise, if ≥1 listed id remains, call `bash "$SCRIPT_DIR/rules-check.sh" --if-stamped` ONCE (same cwd, `</dev/null`). Map the per-id output **fail-closed**:
     - `  [SKIP] all (unstamped)` present ⇒ every listed id is `unverified`, reason `rule_unapproved` (checked FIRST — nothing executed);
     - exactly one `  [PASS] <id>` line and no other result line for that id ⇒ `pass`;
     - exactly one `  [FAIL] <id>` line and no other result line for that id ⇒ `fail`, reason `rule_check_failed`;
     - more than one result line for an id, a conflicting PASS+FAIL pair, a result line that is not an exact `^  \[(PASS|FAIL)\] <id>$` whole-line match, or the id absent ⇒ `unverified`, reason `rule_unresolved`. Never `pass`: a forged or ambiguous line can only degrade a result, never promote it.
     - The honest residual goes in the header comment. In execute mode, `rules-check.sh` also echoes `  [RUN ] <id>: <check>` before each check, so a crafted check could still pre-print a forged `[PASS] <id>` for its own id. The conflict/duplicate rule turns that into `rule_unresolved` whenever the real result line also appears. A stamped set's check text was confirmed by a human (the stamp hashes `id\tcheck`), which bounds this case to checks a human already approved.
     - Test case: a must rule whose check contains an embedded newline + `  [PASS] <id>`, run once under `--no-cmd` (⇒ `rule_cmd_disabled`, not pass) and once unstamped (⇒ `rule_unapproved`, not pass).
   - **(d)** `run-ground-truth.sh` must contain NO reference to `.agent/rules` and NO `jq` read of a `check` field. AC2's grep is the proof.
   - **(e)** A `rule:` bullet is NOT subject to the brief `sha256:` stamp gate, and is NEVER routed through `exec-acceptance-lib.sh`'s hash. Its authorization is the user-scope rules stamp only (skills/rules/SKILL.md §8.1: do not conflate the two stamps).
   - **(f)** The honest limit goes in the header comment: `--if-stamped` replays the WHOLE stamped must-set, not just the named ids. This is the pre-existing rules-check contract, which a human already confirmed; the runner reports only the named ids.
4. **Launch Pad (plan side).**
   - **Phase 3, new action 0c.** It runs after action 3 settles the File Impact Map, beside the existing action 0b churn read: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-rules.sh" --with-ids <space-separated File-Impact-Map paths>`, with paths as ARGUMENTS and never stdin. It is advisory and fail-safe, and no wrapper is needed because the reader self-gates on the store and always exits 0. Hold the output as `applicable_rules`.
   - **Phase 5, when `applicable_rules` is non-empty:**
     - **(i)** Emit a `## House Rules` section holding the reader block, with its first line (the reader's H2 banner `## Advisory house rules — subordinate to CLAUDE.md …`) DEMOTED to a plain blockquote line (`> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)`). A second H2 would end the section and split the brief's H2 structure. Every rule bullet below the banner is kept verbatim. This is what makes the worker's constraints brief-scoped (requirement scope (c)).
     - **(ii)** For every `must` rule in the block with a non-`(none)` check, emit `- rule: <id>` in `## Executable Acceptance`, creating the section if absent.
     - When `applicable_rules` is empty, emit NEITHER. The brief is byte-identical to today's: no heading, no placeholder.
     - `rule:` is machine-authorable (it carries no shell). This does not relax the `cmd:` prohibition.
   - **Phase 5.5 spawn contract.** When `applicable_rules` is non-empty, paste it into a new `--- APPLICABLE RULES --- … --- APPLICABLE RULES END ---` block, because Plan Reviewer has no Bash. When it is empty, OMIT the block. "Check all 16 review criteria" becomes 17.
5. **Plan Reviewer Criterion 17 — Rule Conformance.** It is conditional: skip silently when the spawn prompt has no `--- APPLICABLE RULES ---` block or the block lists no rules.
   - **17a:** FAIL (issue severity HIGH, category `rule_conformance`) when the brief's stated approach, Design decisions, or acceptance criteria contradict an applicable `must` rule's statement. The issue quotes the rule id and the contradicting brief text.
   - **17b:** FAIL (HIGH, `rule_conformance`) when an applicable `must` rule with a non-`(none)` check has no matching `- rule: <id>` bullet in `## Executable Acceptance`.
   - An applicable `advisory` rule never FAILs. At most it is a LOW note when the brief visibly ignores it.
   - Criterion 14's classifier text gains `rule:` as a recognized non-`cmd` prefix, in the same sentence that names `corpus-task:` / `qa-executor:`.
   - Add a Decision Matrix row if the matrix enumerates per-criterion outcomes, and add `rule_conformance` to the category enum/list wherever Criterion 14's `executable_acceptance` category is enumerated.
6. **The count 16 ⇒ 17 is a claimed number.** Grep the OLD value repo-wide (CLAUDE.md). Known surfaces at base:
   - `agents/plan-reviewer.md`: the `## 16 Review Criteria` heading, the "All 16" never-skip line with its conditional-criteria list (add 17), the Decision Matrix row "All criteria satisfied (16 total, Criteria 11, 12, 13, 14, 15, and 16 conditional)" (add 17), and the Quality Checklist line;
   - `docs/POINTER_AUDIT.md`: "The reviewer must also check all 16 criteria";
   - `agents/launch-pad.md`: Phase 5.5 spawn "Check all 16";
   - `commands/launch-pad.md`: Phase 5.5 "checks all 16 criteria" and its conditional list.

   Historical CHANGELOG entries, `.supervisor/` trail files, and the historical raise notes inside `docs/prompt-token-budgets.json` are exempt.
7. **Behavioral proof of a prompt change is LIVE, not CI.** Launch Pad and Plan Reviewer are LLM prompts, so CI can only pin their text.
   - Subtask 2 ships committed fixtures under `loomwright/scripts/fixtures/rule-conformance/`:
     - a sandbox `.agent/rules/` store with one `must` rule that has a check, routed by `applies_to` to a fixture path;
     - a CONFORMING brief (it carries the `rule:` bullet and does not contradict);
     - a CONTRADICTING brief (17a);
     - an OMITTING brief (17b).
   - Subtask 2 also ships a static seam test `loomwright/scripts/test-rule-conformance-seam.sh`. It pins:
     - Launch Pad's action-0c shape (args, `--with-ids`, the empty ⇒ omit rule);
     - the APPLICABLE RULES block's conditional emission;
     - Criterion 17's skip clause, its 17a/17b FAIL conditions, and the `rule_conformance` category;
     - the fixtures' well-formedness: the fixture store parses under `read-rules.sh --with-ids`, and each fixture brief's `## Executable Acceptance` classifies through `classify_kind` as expected.
   - **Fixture store staging.** `read-rules.sh` reads `.agent/rules/` relative to the git toplevel of its cwd. So both the seam test and the AC7 probe COPY `fixtures/rule-conformance/rules/*.json` into a sandbox `git init` repo's `.agent/rules/` and run the reader from there, following the existing FIXREPO pattern in `test-rules-seams.sh` PART 2. They never point it at the live store.
   - The AC7 live probe is run by the SUPERVISOR MAIN THREAD at Phase 4.5, because the worker has no Task tool, and is recorded in the PR body.

## Acceptance Criteria
- [ ] **AC1 (plan side, reader):** `read-rules.sh --with-ids <path>` on a sandbox store with a rule routed to `<path>` prints that rule with `  - id: <id>` and `  - enforcement: <enf>` lines. `read-rules.sh <path>` WITHOUT the flag is byte-identical to its pre-change output on the same store, proved by a diff against a captured baseline in `test-read-rules.sh`. On an empty or absent store, both forms print nothing.
- [ ] **AC2 (delegation):** `run-ground-truth.sh` resolves `rule: <id>` by invoking `rules-check.sh`, and a grep proves it neither reads `.agent/rules` nor extracts a `check`. Concretely, `grep -nE '\.agent/rules|\.check\b' loomwright/scripts/run-ground-truth.sh` returns no code line (comment-only hits allowed), asserted in `test-run-ground-truth.sh`.
- [ ] **AC3 (unstamped canary):** in a sandbox repo (own `git init`, own `HOME` so the user-scope stamp file is empty), a `must` rule whose check is `touch <sandbox>/CANARY` resolves through a `rule:` bullet to `unverified` / `rule_unapproved`, and `<sandbox>/CANARY` does NOT exist afterwards. Positive control: run `rules-check.sh --confirm` in the same sandbox, which writes the stamp AND itself runs the check (creating CANARY). Then `rm -f <sandbox>/CANARY`, assert that it is gone, and run the runner again: the same `rule:` bullet resolves `pass` and CANARY is RE-CREATED by the runner's delegated call. Without the rm, the confirm step's own CANARY would make the control pass for the wrong reason.
- [ ] **AC4 (unknown id):** `rule: no-such-id` ⇒ per_check `fail`, reason `rule_not_found`, and the aggregate status is `advisory_failures`, never `pass`. The same applies to an id naming an `advisory` rule.
- [ ] **AC5 (classifier):** `classify_kind 'rule: x'` ⇒ `rule`. A brief carrying only `rule:` + `corpus-task:` bullets has cmd-hash `none`, so it is never subject to `cmd_unapproved`. `--no-cmd` ⇒ `rule:` bullets `unverified` / `rule_cmd_disabled`, and CANARY absent even when stamped. To avoid a false pass, stamp via `--confirm`, then `rm -f` CANARY and assert it is gone BEFORE the `--no-cmd` runner call. Also: the newline-forgery check (decision 3b/3c) never yields `pass` under `--no-cmd` or unstamped, and an ambient `RULES_CHECK_CONFIRM=1` in the runner's environment leaves CANARY absent on an unstamped run. Pinned in `test-exec-acceptance-hash.sh` / `test-run-ground-truth.sh`.
- [ ] **AC6 (`--list-selected`):** prints exactly the must+checkable ids (sorted), executes nothing (a canary check proves it), writes no stamp (the stamp file mtime/content is unchanged), and exits 0. It wins over `--confirm`, `--if-stamped` and `--no-cmd`. Pinned in `test-rules-check.sh`.
- [ ] **AC7 (Criterion 17, LIVE probe — Supervisor main thread at Phase 4.5, evidence in the PR body):** spawn `loomwright:loomwright:plan-reviewer` on each fixture brief with the fixture store's `read-rules.sh --with-ids` output pasted as the APPLICABLE RULES block.
  - CONTRADICTING ⇒ FAIL with a 17a `rule_conformance` issue.
  - OMITTING ⇒ FAIL with a 17b `rule_conformance` issue.
  - CONFORMING ⇒ no `rule_conformance` issue.
  - The CONFORMING brief with the block OMITTED ⇒ no Criterion 17 issue (the empty-store skip).
  - **Mutation control:** the same two FAIL fixtures, reviewed by a `general-purpose` agent given the NEW `agents/plan-reviewer.md` text with the Criterion-17 block deleted, produce no `rule_conformance` finding.
  - This AC is evidence-gated, not CI-gated. A missing transcript is an escalation, not a silent pass.
- [ ] **AC8 (static seam):** `loomwright/scripts/test-rule-conformance-seam.sh` passes and pins the prompt text and fixtures listed in decision 7. Mutation control: deleting Criterion 17's 17b sentence, or Launch Pad's action 0c, from a temp copy makes the seam test fail, with the mutant gated on non-empty + differs + positive control (lesson fa32a308).
- [ ] **AC9 (docs + counts):** the `rule:` kind and its reasons are documented in:
  - `docs/RESULT_SCHEMAS.md` §"`## Executable Acceptance`" (kinds + per_check reasons) and the PLAN_REVIEW_RESULT category list (`rule_conformance`);
  - `skills/supervisor-readiness/SKILL.md` §"Executable Acceptance" (the kind list; the `rule:` bullet is machine-authorable, `cmd:` still forbidden) plus the optional-sections sentence (`House Rules`);
  - `skills/rules/SKILL.md` (the new plan-side consumer + `--with-ids` + `--list-selected`, stated in the §5 READ-contract / §8 area, with the §8.1 two-stamps distinction restated for `rule:` bullets);
  - `docs/POINTER_AUDIT.md` (a row for the APPLICABLE RULES paste).

  Every 16 ⇒ 17 criteria-count surface is updated (decision 6). `scripts/check-doc-currency.sh` and `scripts/check-command-sync.sh` are green.
- [ ] **AC10 (budgets + release):** `scripts/check-token-budget.sh` is green. The launch-pad (902 headroom at base) and plan-reviewer (448 headroom at base) budgets are raised per the measured + ~10% convention, with the mirror row in `docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" and a note appended to each `prompt-token-budgets.json` row. Minor bump 15.108.4 ⇒ 15.109.0 in `plugin.json` + `marketplace.json` (read the live version at execution — lesson 16ffd26d). Add one CHANGELOG paragraph. Counts are unchanged: 14 agents / 24 commands / 42 skills, and `hooks.json` is byte-unchanged.
- [ ] **AC11 (full loop green):** all of the following pass, run under `bash`:
  - every `loomwright/scripts/test-*.sh`, `loomwright/scripts/adapters/*/test-*.sh` and root `scripts/test-*.sh`;
  - `scripts/check-vendor-coupling.sh`, `scripts/check-doc-currency.sh`, `scripts/check-command-sync.sh`, `scripts/check-skills-index-sync.sh`, `scripts/check-token-budget.sh` and `scripts/check-test-hermetic.sh`;
  - `loomwright/scripts/test-citation-drift.sh`.

  Any new test sources `hermetic-test-env.sh` as its first executable line (the #290 ratchet).
- [ ] **Invariants:** `rules-check.sh` remains the only file that executes a rule `check` (grep `bash -c` over `loomwright/scripts/*.sh` shows no new executor). The `gh pr merge --squash` positive grep resolves to the same 5 surfaces. No new agent/command/skill/hook.

## Non-goals
- Changes to `read-rules.sh`'s routing, validation, supersession or the rule schema (7 members + optional `supersedes`, frozen).
- Letting Launch Pad emit `cmd:` bullets.
- Promoting a failing rule check to a blocker at review/merge: that is item 07. Worker self-check is item 06. Store re-audit at Phase 4.5 is item 09.
- Changing the worker's DO-side `read-rules.sh` paste in `skills/async-orchestration/SKILL.md`.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Runtime: `read-rules.sh --with-ids`, `rules-check.sh --list-selected`, `rule:` kind in `exec-acceptance-lib.sh` + `run-ground-truth.sh` delegation, tests | AC1–AC6, AC11 (scripts), Invariants | 8 modify, 0 create | unit-testing, quality-checklist | LAUNCHABLE |
| 2 | Plan side + docs + release: Launch Pad action 0c / House Rules / `rule:` bullets / APPLICABLE RULES paste, Plan Reviewer Criterion 17, fixtures + seam test, docs, 16⇒17 counts, budgets, version | AC7 (fixtures + prompt), AC8–AC11 | 12 modify, 5 create | quality-checklist, unit-testing | BLOCKED (by #1) |

## Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/scripts/read-rules.sh", name: "--with-ids"}
  - {kind: "symbol", path: "loomwright/scripts/rules-check.sh", name: "--list-selected"}
  - {kind: "symbol", path: "loomwright/scripts/exec-acceptance-lib.sh", name: "rule:*)"}
  - {kind: "symbol", path: "loomwright/scripts/run-ground-truth.sh", name: "rule_not_found"}
  - {kind: "symbol", path: "loomwright/scripts/run-ground-truth.sh", name: "rule_unapproved"}
  - {kind: "symbol", path: "loomwright/scripts/test-run-ground-truth.sh", name: "CANARY"}
  - {kind: "symbol", path: "loomwright/scripts/test-rules-check.sh", name: "--list-selected"}
  - {kind: "symbol", path: "loomwright/scripts/test-read-rules.sh", name: "--with-ids"}
requires: []
lanes:
  - "loomwright/scripts/read-rules.sh"
  - "loomwright/scripts/rules-check.sh"
  - "loomwright/scripts/exec-acceptance-lib.sh"
  - "loomwright/scripts/run-ground-truth.sh"
  - "loomwright/scripts/test-read-rules.sh"
  - "loomwright/scripts/test-rules-check.sh"
  - "loomwright/scripts/test-run-ground-truth.sh"
  - "loomwright/scripts/test-exec-acceptance-hash.sh"
external_requires: []

# Subtask 2
provides:
  - {kind: "symbol", path: "loomwright/agents/launch-pad.md", name: "--with-ids"}
  - {kind: "symbol", path: "loomwright/agents/launch-pad.md", name: "APPLICABLE RULES"}
  - {kind: "symbol", path: "loomwright/agents/plan-reviewer.md", name: "### 17. Rule Conformance"}
  - {kind: "symbol", path: "loomwright/agents/plan-reviewer.md", name: "rule_conformance"}
  - {kind: "symbol", path: "loomwright/commands/launch-pad.md", name: "all 17 criteria"}
  - {kind: "file", path: "loomwright/scripts/test-rule-conformance-seam.sh"}
  - {kind: "file", path: "loomwright/scripts/fixtures/rule-conformance/brief-contradicting.md"}
  - {kind: "file", path: "loomwright/scripts/fixtures/rule-conformance/brief-omitting.md"}
  - {kind: "file", path: "loomwright/scripts/fixtures/rule-conformance/brief-conforming.md"}
  - {kind: "file", path: "loomwright/scripts/fixtures/rule-conformance/rules/must.json"}
  - {kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "rule_not_found"}
  - {kind: "symbol", path: "loomwright/skills/supervisor-readiness/SKILL.md", name: "rule: <id>"}
  - {kind: "symbol", path: "loomwright/skills/rules/SKILL.md", name: "--list-selected"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/read-rules.sh", name: "--with-ids"}
  - {from: "1", kind: "symbol", path: "loomwright/scripts/exec-acceptance-lib.sh", name: "rule:*)"}
  - {from: "1", kind: "symbol", path: "loomwright/scripts/run-ground-truth.sh", name: "rule_not_found"}
lanes:
  - "loomwright/agents/launch-pad.md"
  - "loomwright/commands/launch-pad.md"
  - "loomwright/agents/plan-reviewer.md"
  - "loomwright/scripts/test-rule-conformance-seam.sh"
  - "loomwright/scripts/fixtures/rule-conformance/**"
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/docs/POINTER_AUDIT.md"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/skills/supervisor-readiness/SKILL.md"
  - "loomwright/skills/rules/SKILL.md"
  - "loomwright/commands/rules.md"
  - "CHANGELOG.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
external_requires: []
```

## Parallelism Analysis
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after Subtask 1 — its `requires` point at Subtask 1's `--with-ids`, `rule:*)` and `rule_not_found`)
- **Recommended workers:** 1 (sequential)
- **Estimated batches:** 2

## File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| runtime (S1) | `loomwright/scripts/read-rules.sh`, `loomwright/scripts/rules-check.sh`, `loomwright/scripts/exec-acceptance-lib.sh`, `loomwright/scripts/run-ground-truth.sh`, `loomwright/scripts/test-read-rules.sh`, `loomwright/scripts/test-rules-check.sh`, `loomwright/scripts/test-run-ground-truth.sh`, `loomwright/scripts/test-exec-acceptance-hash.sh` | — | HIGH |
| prompts (S2) | `loomwright/agents/launch-pad.md`, `loomwright/commands/launch-pad.md`, `loomwright/agents/plan-reviewer.md` | `loomwright/scripts/test-rule-conformance-seam.sh`, `loomwright/scripts/fixtures/rule-conformance/{brief-contradicting,brief-omitting,brief-conforming}.md`, `loomwright/scripts/fixtures/rule-conformance/rules/must.json` | HIGH |
| docs + release (S2) | `loomwright/docs/RESULT_SCHEMAS.md`, `loomwright/docs/POINTER_AUDIT.md`, `loomwright/docs/ARCHITECTURE_CONTRACTS.md`, `loomwright/docs/prompt-token-budgets.json`, `loomwright/skills/supervisor-readiness/SKILL.md`, `loomwright/skills/rules/SKILL.md`, `loomwright/commands/rules.md` (MEDIUM — only if it enumerates rule consumers/flags), `CHANGELOG.md`, `loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` | — | HIGH |

> **Validator-owned surfaces:** AC9–AC11 depend on `scripts/check-doc-currency.sh`, `scripts/check-token-budget.sh`, `scripts/check-command-sync.sh`, `scripts/check-test-hermetic.sh` and `loomwright/scripts/test-citation-drift.sh`. Files those validators scan (version/count claims, budget mirror rows, pinned `file:N` citations — e.g. the pinned `result_block_parser.py` / `read-postmortem.sh` citations in prose near any edited section) may need updates to stay green. Any NEW prose citation uses a descriptive anchor, never a bare `file:N`.

## Skill References
- `skills/unit-testing/SKILL.md` (Subtasks 1, 2 — bash self-tests, sandbox `HOME` + `git init`, PATH stubs)
- `skills/quality-checklist/SKILL.md` (Subtasks 1, 2)
- `skills/rules/SKILL.md` §4 (reader args-never-stdin), §8/§8.1 (`--if-stamped`, the two-stamps distinction), §9 (trust boundary) — read, then extend
- `skills/self-heal-advisory/SKILL.md` (how Phase 4.5 already calls `run-ground-truth.sh --brief … $NO_CMD_FLAG` — the `rule:` kind must slot into that call unchanged)

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - category: process
  - check (data only, NOT executed by this reader): (none)
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - category: process
  - check (data only, NOT executed by this reader): (none)

> Advisory only (no `must` rules apply, so no `rule:` bullets). Applied here: the new `rule:` kind and reasons are documented ONCE, in RESULT_SCHEMAS.md, with the other surfaces pointing there. The 16⇒17 criteria count is updated at every existing surface in the same change, because these surfaces already restate it (decision 6).

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| A `rule:` bullet falls through `classify_kind` to bare `cmd` and gets EXECUTED as shell text | HIGH | Decision 3: the lib change lands first (Subtask 1) and is pinned by AC5. |
| `run-ground-truth.sh` quietly grows its own store read or check execution (a second executor, breaking the §9 trust boundary) | HIGH | AC2 grep + Invariants grep; `--list-selected` exists precisely so the runner never needs to read the store. |
| A committed check with an embedded newline forges a `[PASS] <id>` line in `rules-check.sh` output (Plan Review attempt 1, MEDIUM) | HIGH | Decision 3b: under no-cmd the runner never calls or parses rules-check. Decision 3c: an exact whole-line match, with duplicate/conflicting lines ⇒ `rule_unresolved` (can only degrade a result, never promote it). A newline-forgery test case covers it. |
| `--if-stamped` replays the whole stamped set, not just the named ids | MEDIUM | This is the pre-existing contract (a human confirmed that set). It is documented as an honest limit in the runner header; only the named ids are reported. |
| An ambient `RULES_CHECK_CONFIRM=1` in the Phase 4.5 environment launders an unstamped run | MEDIUM | Already neutralized inside `rules-check.sh` when `--if-stamped` is on argv (the PR #267 anti-laundering rule). The runner never passes `--confirm`. Add one test case with the env var set, asserting that CANARY is still absent. |
| Criterion 17 is an LLM judgment; CI can only pin text | MEDIUM | AC7 is a live probe with a mutation control, run by the Supervisor main thread (the pattern from item 02, AC-R). AC8 pins the text. |
| Token budgets breach (launch-pad 902 / plan-reviewer 448 headroom at base) | MEDIUM | AC10: raise per the measured + ~10% convention, re-measuring AFTER the last prose edit. |
| The criteria count is restated in more places than the known list | MEDIUM | Decision 6: grep the old value repo-wide (lesson 0d7865dc: a green doc-currency run is necessary, not sufficient). |
| A test reads the real user-scope stamp or store | MEDIUM | Every rules test uses a sandbox `HOME` + its own `git init`; the live store has no `must` rules anyway. |
| Worker turn limit (items 02/04 hit 40 turns) | LOW | Context-bound split; resume via SendMessage on a turn-limit, never respawn. |

## Configuration
- **Mode:** sequential
- **Recommended workers:** 1
- **Estimated batches:** 2
- **Split reason:** context-bound (~25 files changed across the two groups, > 12)

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-09-28-plan-time-rule-routing.md

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/292 (merged 1721946, 2026-09-28)
- **Branch:** feature/automate-followups-05-plan-time-rule-routing
- **Files changed:** 27
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Launch Pad action 0c reads `read-rules.sh --with-ids` over the File Impact Map. When rules apply, the brief gets a `## House Rules` section and `rule: <id>` bullets, and Plan Reviewer gets an APPLICABLE RULES block. Plan Reviewer Criterion 17 fails a brief that contradicts an applicable must rule (17a) or omits its `rule:` bullet (17b). `rule:` is a new Executable Acceptance kind: `run-ground-truth.sh` delegates it to `rules-check.sh --list-selected` + `--if-stamped`, with a fail-closed mapping (trailer and rc gate, duplicate/near-miss downgrade). Version 15.109.0, delivered in 2 sequential subtasks: 024cf1a, then 1729fb9 + 1562aa8. Phase 4.5 consistency_audit PASSed on the first review (0 HIGH), and every execution-directive repro held. Its 2 MEDIUM + 2 LOW advisories were fixed in 5d5ce65. Fixture verdict hints were neutralized in 824d0e9. The AC7 live Criterion-17 probe gave the expected verdict on all three fixtures, and a valid mutation control (the origin/main prompt) missed both failures (PR comment). The owned drain was READY after 2 rounds, with 1 fix cycle (3e689ee). risk_classification high_risk=true. Pre-existing environment-only failure: orca-mirror case L. The CI run on 824d0e9 stalled in its self-test step on the runner; the next run on 3e689ee passed in 6.5 min.

## Not verified
- **Criterion 17 on the installed agent.** The live probes read the branch prompt; the installed plugin cache (15.108.4) has 16 criteria until it is updated.
- **Cause of the 824d0e9 CI self-test stall.** Run 36416045257: it did not reproduce locally or on the next commit.
- **auto_review restore timing.** It was restored after the owned drain instead of before it. No detached dispatch occurred, so this had no effect.
