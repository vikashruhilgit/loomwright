# Supervisor Job: `learning-emit` records Phase 4.5 self-heal churn (`--self-heal-rounds` → `self_heal_rounds` + `self_heal_churn` category)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean code tree (only the untracked `.supervisor/automate/automate-2026-09-26-115755.md` run file), branch: main == origin/main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (runtime plugin cache is 15.98.0 while the repo is 15.103.0 — the engine executes cached scripts; this item edits the repo copies only)
- **Source requirement:** .supervisor/requirements/automate-followups/01-learning-emit-counts-self-heal-rounds.md
- **Base commit:** 05ad3057a9628992e7f7fbf6f3f62868ca97f85a

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Bash + jq edit inside the existing `learning_emit()`; markdown doc edits. |
| 2 | Dependency Availability | GO | `jq` only (already required by the helper); no new dependency. |
| 3 | Architecture Fit | GO | Same additive-field precedent as `source`/`automate_key`/`changed_paths` (no `schema_version` bump); the helper stays the single source of truth for record building (SKILL §6 "reference-don't-restate"). |
| 4 | Scope vs Supervisor Capability | GO | ~9 files, one coherent change, below the context-bound threshold ⇒ single subtask. |
| 5 | Hard Blockers | GO | None. `SUPERVISOR_RESULT.heal_iterations` is a required field (`docs/RESULT_SCHEMAS.md` SUPERVISOR_RESULT). |

**Overall Verdict:** GO

## Task
**Goal:** One engine-native `automate_drain` learning line records BOTH lenses' churn — the Phase 4.5 self-heal fix iterations AND the owned drain's fix cycles — distinguishably, so `read-postmortem.sh` surfaces a PR whose churn was absorbed in self-heal as a prior-churn hit instead of a false-0.

**Problem Statement:** `learning-emit` derives `review_rounds` and `categories[]` from the drain's `fix_cycles` only. When Phase 4.5 heals findings before the PR reaches the drain (PR #267: round 1 FAIL with 4 HIGH → fix → round 2 PASS; drain 0 fix cycles), the line reads `review_rounds: 0`, `categories: []`, and the reader treats the most-churned area as clean.

## Design decisions (settled here so the worker does not choose for the owner)
1. **`review_rounds` keeps its current meaning (drain-only).** Back-compat: `build-loop-evidence.sh` / `measure-heal-signal.py` join on `review_rounds` with floor-raising (max) semantics; redefining it would silently change historical comparisons. `flow_stages` is also unchanged.
2. **New additive integer field `self_heal_rounds`** = normalized `--self-heal-rounds`. **Presence rule:** the field is emitted ONLY when `--self-heal-rounds` was passed (any value); when the flag is omitted the line is byte-identical to today's (AC2). Normalization: a non-negative integer passes through; anything else (non-numeric, negative, fractional, empty) ⇒ `0` — never a non-zero exit (fail-SAFE).
3. **New `categories[]` class `self_heal_churn`**, emitted when `self_heal_rounds > 0`: `{round: self_heal_rounds, class: "self_heal_churn", self_heal_miss: false, flow_stage: "self_heal", evidence: "Phase 4.5 self-heal, heal_iterations=<n>"}`. It is placed BEFORE any drain entry (chronological order: self-heal precedes the drain). `self_heal_miss: false` because a healed finding is a catch, not a miss. `read-postmortem.sh` already counts every `categories[]` element as one round and groups by `.class` (its `$rounds` / `$classes` jq), so **the reader needs no change** — the worker must confirm this by assertion, not edit the reader.
4. **Zero-rule restated, not broken:** `categories: []` iff `effective_review_rounds == 0` AND `self_heal_rounds == 0` (absent counts as 0). "At most ONE synthetic entry" becomes "at most one drain entry plus at most one `self_heal_churn` entry". The purpose (no fake churn) is preserved — self-heal churn is real.
5. **Default `summary`** is unchanged when `self_heal_rounds` is absent or 0; when > 0 it appends `; self-heal: <n> round(s)` to the existing default text. A caller-supplied `--summary` is emitted verbatim as today.
6. **Idempotency key unchanged** (`run_id|item|pr_url|source|completeness`). `self_heal_rounds` is NOT part of the key.
7. **Flag name is `--self-heal-rounds`, deliberately NOT `--heal-iterations`** (Plan Review attempt 1, MEDIUM; owner-chosen rename, deviating from the source requirement's suggested name). `/supervisor --heal-iterations N` is already the configured MAXIMUM self-heal bound (default 3); reusing that name here invites a caller to pass the bound and record fake churn. The new flag takes the OBSERVED count, `SUPERVISOR_RESULT.heal_iterations`, and both the helper header and SKILL §6 say so explicitly ("the observed count, never the configured `--heal-iterations` bound").
8. **`flow_stages` split is documented, not changed:** `flow_stages.self_heal` keeps counting drain rounds only; self-heal churn appears only in `self_heal_rounds` and `categories[]`. The `automate_drain` variant text states this, since it widens the known counter-vs-categories disagreement (`build-floor.sh`'s `flow_stage_counter_disagreements`), which stays confined to `automate_drain` lines.
9. **Engine wiring (SKILL §6):** the loop reads `heal_iterations` from the verbatim `<run_id>.supervisor-result.md` it wrote at step 2; `null` (heal loop did not run) ⇒ pass `--self-heal-rounds 0`; **no `heal_iterations:` line at all (e.g. a main-thread reconstruction of a resumed item) ⇒ OMIT the flag** — never fabricate a count. `--item` MUST be the full Queue path (the PR #267 short-key drift).

## Acceptance Criteria
- [ ] **AC1** — `learning-emit … --self-heal-rounds 2 --fix-cycles 0 --drain-result READY` (with real `--repo` and a non-empty `--changed-paths-json`) emits a line with `self_heal_rounds: 2`, `review_rounds: 0`, and exactly one `categories[]` entry with `class: "self_heal_churn"`, `round: 2`. **Asserted through the reader's OUTPUT:** in a throwaway git repo whose `origin` remote resolves to the line's `repo`, with the ledger at the reader's default path, `read-postmortem.sh <overlapping path>` prints a prior-churn block whose classes line contains `self_heal_churn (1)` and whose rounds line reports `1`. (Existing F10 reasons via the reader's selection jq; AC1 must run the real reader.)
- [ ] **AC2 (back-compat pin)** — the same call WITHOUT `--self-heal-rounds` produces a line byte-identical (after deleting `ts`) to the line the pre-change helper produces for the same args. Pin the expected line from `git show 05ad3057a9628992e7f7fbf6f3f62868ca97f85a:loomwright/scripts/automate-helpers.sh` (the pinned base commit, never a moving `origin/main`) run on the same args (or an equivalent frozen golden), and assert the new line has no `self_heal_rounds` key.
- [ ] **AC3** — `--self-heal-rounds abc`, `-1`, `1.5`, and `""` each ⇒ exit 0, line emitted, `self_heal_rounds: 0`, no `self_heal_churn` entry. And `--self-heal-rounds 0 --fix-cycles 0 --drain-result READY` ⇒ `self_heal_rounds: 0`, `review_rounds: 0`, `categories: []` exactly (restated zero-rule).
- [ ] **AC3b** — `--self-heal-rounds 1 --fix-cycles 0 --drain-result ESCALATED` ⇒ `review_rounds: 1`, `self_heal_rounds: 1`, categories `[self_heal_churn(round 1), drain_escalation(round 1)]` in that order.
- [ ] **AC4** — combined: `--self-heal-rounds 1 --fix-cycles 3 --drain-result READY` ⇒ `review_rounds: 3`, `self_heal_rounds: 1`, categories `[self_heal_churn(round 1), drain_churn(round 3)]` in that order; reader rounds line reports `2`.
- [ ] **AC5 (idempotency)** — the `automate_key` is byte-identical with and without `--self-heal-rounds`; a re-entry with the same run/item/PR (with or without the flag) writes nothing new.
- [ ] **AC6 (mutation control)** — patch a temp copy of `automate-helpers.sh` so the `--self-heal-rounds` value is never plumbed into the record (e.g. force it to 0 / drop the `--argjson`); AC1 fails against the mutant. Gate the mutant on non-empty + differs-from-original + `bash -n` before trusting the result (lesson fa32a308).
- [ ] **AC7 (docs)** — `docs/RESULT_SCHEMAS.md` POSTMORTEM_RESULT §"`source: \"automate_drain\"` variant" documents `self_heal_rounds` (presence rule, normalization, source = the OBSERVED `SUPERVISOR_RESULT.heal_iterations`, never the `/supervisor --heal-iterations` bound), the `self_heal_churn` class, the restated zero-rule, and the `flow_stages.self_heal`-is-drain-only split (decision 8); one additive-change bullet in the schema's change log; no `schema_version` bump. `skills/automate-loop/SKILL.md` §6 "Learning-emit at end-of-DRAIN" adds `heal_iterations` to "Inputs the engine already holds" with decision 9's null/absent rule and the full-Queue-path `--item` note (reference the helper, do not restate its jq logic). The helper's header comment documents decisions 1–8.
- [ ] **AC8 (versioning)** — SKILL frontmatter version bump + matching `SKILLS_INDEX.md` row (check-skills-index-sync); plugin version bump in `plugin.json` + `marketplace.json` + one CHANGELOG paragraph; counts unchanged (14 agents / 24 commands / 42 skills; `hooks.json` byte-unchanged).
- [ ] **AC9 (full loop green)** — `loomwright/scripts/test-*.sh` + root `scripts/test-*.sh` + `scripts/check-vendor-coupling.sh` + `scripts/check-doc-currency.sh` + `scripts/check-skills-index-sync.sh` + `scripts/check-token-budget.sh` + `loomwright/scripts/test-citation-drift.sh`. Consumers of `categories[].class` (`build-floor.sh`, `build-loop-evidence.sh`, `measure-heal-signal.py`) stay green — verify, do not assume.
- [ ] **Invariants** — `learning-emit` still always exits 0; `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` resolves to the same 5 surfaces; no new agent/command/skill/hook.

## Non-goals
- No change to the drain's `fix_cycles` / `REVIEW_HEAL_RESULT`.
- No back-fill or rewrite of existing corpus lines (append-only; `curate-postmortem.sh` stays the only curator).
- No change to `/pr-postmortem`'s GitHub-derived lines, `read-postmortem.sh`, or `flow_stages`.
- No change to how `<run_id>.supervisor-result.md` is captured beyond the SKILL prose in decision 9.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | `learning-emit --self-heal-rounds` → `self_heal_rounds` + `self_heal_churn`, tests via the real reader, schema + SKILL docs, version bump | AC1–AC9, Invariants | 8 modify, 0 create | quality-checklist, unit-testing | LAUNCHABLE |

```yaml
subtask_id: learning-emit-self-heal-01
title: "learning-emit --self-heal-rounds: self_heal_rounds + self_heal_churn category, reader-asserted tests, docs, version bump"
lanes:
  - loomwright/scripts/automate-helpers.sh
  - loomwright/scripts/test-automate-helpers.sh
  - loomwright/skills/automate-loop/SKILL.md
  - loomwright/skills/SKILLS_INDEX.md
  - loomwright/docs/RESULT_SCHEMAS.md
  - CHANGELOG.md
  - loomwright/.claude-plugin/plugin.json
  - .claude-plugin/marketplace.json
requires: []
external_requires: []
provides:
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "--self-heal-rounds"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "self_heal_churn"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-helpers.sh", name: "self_heal_rounds"}
  - {kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "self_heal_rounds"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/SKILL.md", name: "heal_iterations"}
out_of_lane: []
```

## Parallelism Analysis
single-agent (no fan-out)
- **Recommended workers:** 1
- **Estimated batches:** 1

## Configuration
- **Mode:** single-agent
- **Recommended workers:** 1

## File Impact Map
| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| helper | `loomwright/scripts/automate-helpers.sh` (`learning_emit()` flag parse, jq record, header comment) | — | HIGH |
| tests | `loomwright/scripts/test-automate-helpers.sh` (§F new cases) | — | HIGH |
| contracts | `loomwright/docs/RESULT_SCHEMAS.md`, `loomwright/skills/automate-loop/SKILL.md`, `loomwright/skills/SKILLS_INDEX.md` | — | HIGH |
| release | `CHANGELOG.md`, `loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` | — | HIGH |
| read-only check | `loomwright/scripts/read-postmortem.sh`, `loomwright/scripts/build-floor.sh`, `loomwright/scripts/build-loop-evidence.sh`, `loomwright/scripts/measure-heal-signal.py` (verify only — expected no edit) | — | MEDIUM |

## Skill References
| Skill | Justification |
|---|---|
| quality-checklist | Standard pre/post-implementation gates. |
| unit-testing | New §F cases incl. a real-reader assertion and a mutation control. |

## Risk Assessment
| Risk | Impact | Source | Mitigation |
|---|---|---|---|
| **Recurring self-heal misses on these exact paths** (RESULT_SCHEMAS.md 27 entries, automate-helpers.sh / its test / automate-loop SKILL 4 each; classes drain_churn, convention_mismatch, quality_gap; `self_heal_miss` recurred). | HIGH | Prior churn (postmortem ledger) | Watch convention_mismatch between the helper, RESULT_SCHEMAS and SKILL §6 (the three must agree on the field name, presence rule and zero-rule); run the real reader rather than reasoning about its jq. |
| **Zero-rule regression**: an entry emitted for `self_heal_rounds: 0`, or the drain zero-rule changed while restating it. | HIGH | Design | AC3 (invalid ⇒ 0, no entry) + AC2 (no-flag byte-identity) + an explicit `categories: []` assertion for `--self-heal-rounds 0 --fix-cycles 0 READY`. |
| **Silent flag no-op** (value parsed but never reaches the record — the class of defect this item exists to fix). | HIGH | Design | AC6 mutation control, with a validated mutant. |
| `tonumber? // 0` accepts `-1` / `1.5`. | MEDIUM | Code reading (`learning_emit()` numeric args) | Normalize with an explicit non-negative-integer check, not bare `tonumber?`. |
| A new `class` value surprises a downstream consumer (`build-floor.sh` class distribution, fixtures). | MEDIUM | Consumer scan | AC9 runs those consumers' tests; no fixture rewrite expected. |
| The SUPERVISOR_RESULT artifact may be a reconstruction without `heal_iterations` (run 2026-09-22). | MEDIUM | Requirement premise | Decision 7: absent line ⇒ omit the flag (field absent), never fabricate. |

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-09-26-learning-emit-self-heal-rounds.md

## Outcome
- **Status:** completed
- **Completed:** 2026-09-26T13:12:19Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/272
- **Branch:** feature/automate-followups-01-learning-emit-self-heal-rounds
- **Files changed:** 8
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** learning-emit --self-heal-rounds → self_heal_rounds + self_heal_churn category; Phase 4.5 consistency_audit PASS iteration 1 (2 MEDIUM + 2 LOW advisory, carried to the owned drain); ground_truth 2/2 pass; contract_conformance pass; risk_classification high_risk=true (skills/ + *auth* content match). Gate note: verify-provides.sh could not parse this brief's `subtask_id:` contract anchor (subtask_not_found); 5/5 provides verified on an anchor-corrected scratch copy.

## Not verified
- **/automate §6 live wiring (reading heal_iterations from <run_id>.supervisor-result.md and passing --self-heal-rounds)** — SKILL prose only; the engine executes the cached 15.98.0 plugin scripts (subtask 1)
