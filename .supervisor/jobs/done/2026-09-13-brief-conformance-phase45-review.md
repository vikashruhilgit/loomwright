# Supervisor Job: Brief conformance in the Phase 4.5 gating review

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — last commit 2026-09-06)
- **Git:** dirty (1 file — `.supervisor/postmortem/results.jsonl`, +6 tracked ledger lines from prior drains; NOT part of this job — do not stage it), branch: main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 2 (dirty tracked ledger above; 7 unrelated `.claude/worktrees/*` from other Claude sessions — leave untouched)
- **Source requirement:** .supervisor/requirements/review-gate-brief-conformance/01-brief-conformance-in-phase45-review.md

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Markdown prompt files + one bash test (bash 3.2/BSD-safe) + JSON budget file — the plugin's own stack |
| 2 | Dependency Availability | GO | No new dependency; `check-token-budget.sh`, `check-doc-currency.sh`, CI `test-*.sh` glob all exist |
| 3 | Architecture Fit | GO | Adds a THIRD pre-review enrichment shaped exactly like `prior_churn` (step 1c) / `house_rules` (step 1e); R1 (no new gate) preserved — `heal_decision` still derives only from `CODE_REVIEW_RESULT` |
| 4 | Scope vs Supervisor Capability | GO | ~9 files, < 800 changed lines → single-agent (below `context-bound`) |
| 5 | Hard Blockers | GO | none |

**Overall Verdict:** GO

## Task
**Goal:** Feed the in-progress brief's acceptance criteria (and rubric bullets, orientation-only) to the Phase 4.5 gating Code Reviewer as one bounded `BRIEF-CONFORMANCE` enrichment line, so an acceptance criterion the integrated diff does not address becomes an ordinary `category: new` / HIGH finding the existing fix loop already consumes — no new gate, no new schema field.

**Problem Statement:**
The plugin owner needs the only PR-gating LLM lens (Phase 4.5 Code Reviewer) to see what was asked for, because today its spawn prompt (`skills/self-heal-advisory/SKILL.md` Part 2 §"Review-and-fix loop") carries BASE_BRANCH, the diff target, PRIOR-CHURN and HOUSE-RULES lines — no brief path, no criteria. Currently a diff that cleanly implements the wrong or partial thing lands as `heal_decision: PASS` with a low `rubric_score` nobody acts on (surfaced by an external review 2026-09-13; owner decisions R1–R4 in `.supervisor/requirements/review-gate-brief-conformance/00-overview.md`). Success looks like: an unaddressed criterion produces exactly one HIGH `new` finding quoting it verbatim, and the first fix iteration's prompt lists it.

**Owner decisions carried in (do not re-litigate):** R1 no new gate (rubric / ground_truth / contract_conformance stay advisory); R2 enrichment line shaped like PRIOR-CHURN / HOUSE-RULES, findings are ordinary `new` findings; R4 standalone `/review-pr` / `review-heal` OUT of scope (no brief for a bare PR URL).

## Acceptance Criteria
- [ ] AC1 — Given an in-progress brief with 3 acceptance criteria and a feature branch whose diff addresses two of them, when Phase 4.5 spawns the Code Reviewer, then its `CODE_REVIEW_RESULT` contains exactly one `category: new`, severity HIGH finding quoting the third criterion verbatim in `description`, and the first fix iteration's prompt lists it (state-trace the prompt text in `skills/self-heal-advisory/SKILL.md` — the fix prompt's `category=new + severity>=HIGH` selection and step 5 "Do NOT address findings outside the listed classes" must admit it; step 1a "Fix the CLASS" gains ONE sentence saying the class of a conformance finding is the criterion itself).
- [ ] AC2 — Given a brief with a runtime-only criterion (e.g. "p95 latency < 200ms"), when reviewed, then no finding is emitted for it and the reviewer output names it under `cannot_determine` in a one-line summary.
- [ ] AC3 — Given `/supervisor task:"..."` with no brief (no `brief_path`), when Phase 4.5 runs, then the reviewer spawn prompt contains no BRIEF-CONFORMANCE line and the step does not error on the missing path (state-trace this path; same back-compat case the completion tail already handles for `.supervisor/jobs/in-progress/` absence). Same silent skip when the brief has no `## Acceptance Criteria` section or zero bullets parse.
- [ ] AC4 — Given a brief with 40 criteria, when the enrichment is computed, then the line carries 25 bullets (criteria first, then rubric bullets) and the marker `(+15 criteria omitted — see brief)`. N counts ALL omitted bullets (criteria + rubric) — stated once in the Part 1 section; with a rubric present, rubric bullets are the first to be dropped because criteria come first.
- [ ] AC5 — Given the new `loomwright/scripts/test-brief-conformance-seam.sh`, when run, then it passes; and given the BRIEF-CONFORMANCE prompt line is deleted from the skill, then it fails (mutation control — gate the mutant on non-empty + differs-from-original before trusting the red, per `.supervisor/memory/LESSONS.md` [fa32a308]).
- [ ] AC6 — Rubric bullets never produce findings: the line labels them as orientation only (they stay the Rubric Grader's lane, R1); `agents/code-reviewer.md` describes the three-way verdict (`addressed | not_addressed | cannot_determine`) and the HIGH/`new` mapping without duplicating the skill's list.
- [ ] AC7 — `brief_conformance` (the diff does not address a stated criterion) is a named miss-class in BOTH the Self-Heal Miss-Class Checklist (`skills/quality-checklist/SKILL.md`) and the DIFFERENT-LENS DIRECTIVE's parenthetical class list in the reviewer spawn prompt.
- [ ] AC8 — `bash scripts/check-token-budget.sh`, `bash scripts/check-doc-currency.sh`, and the FULL `for t in loomwright/scripts/test-*.sh; do bash "$t"; done` loop are green before push (memory `run-full-ci-suite-loop-before-push`); a budget is raised ONLY if the gate breaches (measured + ~10%, JSON `note` + `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" mirror row in the same edit) — do not chase headroom otherwise.
- [ ] AC9 — Release surfaces: `loomwright/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` versions bumped to the next minor above the LIVE `plugin.json` value read at execution (currently 15.68.0 → 15.69.0), the `vX.Y.Z` string in both `description` fields updated in place (never append a clause), and ONE new top entry in `CHANGELOG.md` in the established bold-paragraph shape naming what changed, the honest limits (the reviewer decides `addressed` from the diff text only — no execution; rubric bullets orientation-only; standalone `/review-pr` untouched per R4), and "Counts unchanged".

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | BRIEF-CONFORMANCE enrichment: step 1f + prompt line + reviewer mirror + miss-class + seam test + release surfaces | all (AC1–AC9) | 8 modify, 1 create | `skills/self-heal-advisory/SKILL.md`, `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1 — brief-conformance enrichment (LAUNCHABLE)
provides:
  - {kind: "symbol", path: "loomwright/skills/self-heal-advisory/SKILL.md", name: "Brief-conformance advisory"}   # Part 1 H2 section, sibling of "## House-rules advisory (…)" — same H2 level as that file's Part 1 sections
  - {kind: "symbol", path: "loomwright/skills/self-heal-advisory/SKILL.md", name: "BRIEF-CONFORMANCE ADVISORY"}   # the reviewer spawn-prompt line, placed directly after the HOUSE-RULES ADVISORY line
  - {kind: "symbol", path: "loomwright/skills/self-heal-advisory/SKILL.md", name: "1f."}                            # Part 2 on-entry step "1f." sibling of 1c/1e (0 hits today)
  - {kind: "symbol", path: "loomwright/agents/code-reviewer.md", name: "not_addressed"}
  - {kind: "symbol", path: "loomwright/skills/quality-checklist/SKILL.md", name: "brief_conformance"}
  - {kind: "file",   path: "loomwright/scripts/test-brief-conformance-seam.sh"}
  - {kind: "symbol", path: "CHANGELOG.md", name: "BRIEF-CONFORMANCE"}   # the new top entry names the prompt line (0 hits today)
requires: []
lanes:
  - "loomwright/skills/self-heal-advisory/SKILL.md"
  - "loomwright/agents/code-reviewer.md"
  - "loomwright/skills/quality-checklist/SKILL.md"
  - "loomwright/scripts/test-brief-conformance-seam.sh"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - "CHANGELOG.md"
external_requires: []
```

**Implementation shape (the DO side — read the two existing enrichments first and copy their shape exactly):**
1. `skills/self-heal-advisory/SKILL.md` **Part 1**: add `## Brief-conformance advisory (acceptance-criteria enrichment)` after `## House-rules advisory (…)`, with the same HARD ADVISORY CONTRACT blockquote (advisory input to the REVIEW lens only; never changes `heal_decision`; never fed to fixers via this seam — fixers receive only the resulting ordinary findings; fail-safe; empty ⇒ line omitted; subordinate to CLAUDE.md). Source = the in-progress brief at `brief_path` (the same path `run-ground-truth.sh --brief` and `parse_rubric` use). Parse rule: every leading-`-` bullet under `## Acceptance Criteria` (strip a `[ ]`/`[x]` checkbox prefix), plus every bullet under `## Outcomes Rubric` when present — each section read up to the next `## ` heading (the rubric parser's rule). Cap 25 bullets total, criteria first; on truncation append `(+N criteria omitted — see brief)` where N = ALL omitted bullets (criteria + rubric). **The cap and the marker are stated here ONCE** (house rule: one authoritative place); step 1f, the prompt line, and the seam test refer to "the cap in Part 1" rather than restating the number. Skip silently (empty `brief_conformance`) when: no `brief_path` (direct `/supervisor task:`), no `## Acceptance Criteria` section, or zero bullets parse.
2. **Part 2** on-entry step `1f.` after `1e.`, same prose shape as 1c/1e (advisory, fail-safe, non-gating, computed BEFORE the first reviewer spawn; `record_decision(phase: SELF_HEAL, decision: "brief_conformance: {non-empty | empty}", …)`).
3. **BRIEF-CONFORMANCE ADVISORY** prompt line directly after HOUSE-RULES ADVISORY in the reviewer spawn prompt: `include this line ONLY when brief_conformance is non-empty; omit entirely when empty`. For each listed criterion decide `addressed | not_addressed | cannot_determine` from the diff; emit one finding per `not_addressed` with `category: new`, severity **HIGH**, the criterion quoted verbatim in `description`, what is missing in `suggestion`; `cannot_determine` (runtime-only criteria) goes in a one-line summary, NOT a finding; rubric bullets are orientation only and never produce findings. Note explicitly that this line, unlike the two advisory lines above it, DOES yield ordinary gating findings — because a `new` HIGH finding is already the existing gate's input (R2), not a new gate.
4. Fix prompt: verify (do not restructure) that the `category=new + severity>=HIGH` selection and step 5 admit a conformance finding; add ONE sentence to step 1a naming the class of a conformance finding as the criterion itself.
5. DIFFERENT-LENS DIRECTIVE parenthetical + `skills/quality-checklist/SKILL.md` §"Self-Heal Miss-Class Checklist": add the `brief_conformance` class bullet (Class signal: a stated acceptance criterion with no corresponding change in the integrated diff).
6. `agents/code-reviewer.md`: add the conformance rule to the reviewer's own Review Process (the three-way verdict, HIGH/`new` mapping, `cannot_determine` summary, rubric = orientation) — describe behaviour, do NOT copy the skill's parse rules; the skill's spawn prompt stays the authoritative wording.
7. `loomwright/scripts/test-brief-conformance-seam.sh` modelled on `test-rules-seams.sh` (pass/fail counters, `ok()`/`no()` helpers actually DEFINED — `test-suite-helpers-defined.sh` meta-gate scans every suite; `RESULT: N passed, M failed` tail; paths from `$BASH_SOURCE`): (a) spawn prompt contains the BRIEF-CONFORMANCE line adjacent to (after) HOUSE-RULES; (b) the bounded cap token `25 bullets` (not a bare-digit match — a future unrelated `25` must not turn this red) appears exactly ONCE in the skill, inside the Part 1 `## Brief-conformance advisory` section, AND step 1f references the cap in Part 1 and names all three skip conditions (no-brief / no `## Acceptance Criteria` / zero bullets); (c) `agents/code-reviewer.md` names `not_addressed` and the HIGH/`new` mapping; (d) the miss-class checklist names `brief_conformance`. Mutation control: copy the skill to a temp file, delete the prompt line, assert non-empty + differs, run (a) against the mutant → must fail. No registration needed — CI's `loomwright/scripts/test-*.sh` glob auto-includes it (verify the glob in `.github/workflows/ci.yml` still matches).
8. Budgets: run `bash scripts/check-token-budget.sh` — `quality-checklist` is preloaded by 6 agents (code-reviewer 2773 headroom, orchestrator 837, plan-reviewer n/a) and `agents/code-reviewer.md` grows; raise only on breach, per AC8.
9. Release surfaces per AC9. Run the full `test-*.sh` loop + both check scripts before push.

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/self-heal-advisory/SKILL.md` (Part 1 §"House-rules advisory" is the shape to copy; Part 2 steps 1c/1e and the spawn prompt), `skills/quality-checklist/SKILL.md` §"Self-Heal Miss-Class Checklist", `skills/unit-testing/SKILL.md` (mutation-control discipline), `AGENT_GUIDELINES.md` (read-before-write rule) |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Prior churn (postmortem ledger): `self_heal_miss` recurred on `CHANGELOG.md` (54 rounds), `marketplace.json`/`plugin.json` (53), `ARCHITECTURE_CONTRACTS.md` (21), `prompt-token-budgets.json` (10); recurring classes `drain_churn`, `convention_mismatch`, `quality_gap` — source: Prior churn (postmortem ledger) | HIGH | Treat the release-surface lockstep as a checklist: both manifests' `version` + in-place `vX.Y.Z` in both descriptions + ONE changelog entry; run `check-doc-currency.sh` AND grep the old version string repo-wide; budget mirror row only if a budget is raised |
| Prompt is a program — the new step 1f / prompt line must state-trace cleanly on the no-brief path (AC3) and on the truncation path (AC4); a half-specified skip condition silently errors at Phase 4.5 entry | HIGH | Write the three skip conditions as an explicit ordered list; trace `/supervisor task:` (no `brief_path`) end-to-end in prose before finishing (memory `feedback_prompt_is_program_state_trace`) |
| Token budget breach: `quality-checklist` is preloaded by 6 agents; `orchestrator` has only 837 proxy-token headroom | MEDIUM | Keep the checklist bullet ≤ ~120 words; run `check-token-budget.sh`; raise only on breach with mirror row |
| Seam test vacuous (mutant invalid, or helpers undefined → 127 swallowed) | MEDIUM | Gate the mutant on non-empty + differs-from-original; define `ok`/`no`; assert the pass count rises by the number of assertions added (`test-suite-helpers-defined.sh` is a CI meta-gate) |
| House rule (`.agent/rules/`, category process): a count/version claim lives in exactly ONE machine-readable place — do not restate the 25-bullet cap or a version in a second prose surface that is not the authority | LOW | The cap is stated once in Part 1 and referenced ("the cap in Part 1") from step 1f and the test; versions only in the two manifests + CHANGELOG |
| Scope creep into `review-heal` / `/review-pr` (R4) or into `heal_decision` derivation (R1) | LOW | Non-goals are explicit; the reviewer prompt line says findings are ordinary `new` findings and nothing else changes |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-13-brief-conformance-phase45-review.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-09-13T04:51:04Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/215
- **Branch:** feature/brief-conformance-phase45-review
- **Files changed:** 11
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** BRIEF-CONFORMANCE enrichment (Part 1 section + step 1f + reviewer prompt line + fix-prompt 1a sentence), mirrored in code-reviewer.md + miss-class checklist; seam test 24 assertions w/ mutation control; v15.68.0 → v15.69.0. Heal iteration 1 fixed 1 HIGH ({brief_path} pointer) + 4 swept drift/contract items; iteration 2 PASS; two doc residuals (changelog counts, RESULT_SCHEMAS sentinel comment) applied by the Supervisor main thread post-PASS. contract_conformance: pass (1 evaluated, 0 violations); benchmark: pass; ground_truth: pass 2/2; rubric: n/a (no rubric). Default drain suppressed by /automate (auto_review=false) — the engine owns the drain.
