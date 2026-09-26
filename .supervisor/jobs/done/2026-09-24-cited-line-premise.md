# Supervisor Job: Cited-line premise check (Launch Pad Phase 3 + Supervisor Phase 1.5 signal (d)), advisory

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: automate-hardening-2026-09-22 (worktree; the run's isolation branch, base main @ 65ef43a)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/harness-port/03-cited-line-premise.md

## Feasibility (optional — Launch Pad v10.3+)

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure prose additions to existing agent/skill/doc markdown files — no new script, no new dependency, matches the plugin's existing "instructions the model executes directly" pattern (e.g. the Phase 3 blast-radius prediction and prior-churn consult are the same shape: model-judgment steps described in prose, not deterministic scripts). |
| 2 | Dependency Availability | GO | Uses `git show`/`git ls-tree` only, already used elsewhere in this plugin (preflight-sync signal (a)/(b), Supervisor's PRE-FLIGHT SYNC). No new CLI, no new library. |
| 3 | Architecture Fit | GO | Extends Launch Pad Phase 3 ANALYZE with a new numbered action (append-only, no renumber) and Supervisor Phase 1.5 PRE-FLIGHT SYNC with a new lettered signal (d) placed after (c) — both additive, both explicitly advisory-only per the requirement's own repeated wording, matching the established pattern for signal (c) (churn count, also advisory-only, added earlier in the same file). |
| 4 | Scope vs Supervisor Capability | GO | Single, cohesive change spanning 5 markdown/config files that must move together (shared wording between launch-pad.md and preflight-sync/SKILL.md per Scope item 1) plus the mechanical token-budget/doc-currency bookkeeping every prompt change in this repo requires. No file-conflict/context-bound/genuine-parallelism reason to split. |
| 5 | Hard Blockers | GO | No migration framework, no credentials, no missing modules. |

**Overall Verdict:** GO

## Task
**Goal:** Add an advisory "cited-line premise" check to both Launch Pad Phase 3 ANALYZE and Supervisor Phase 1.5 PRE-FLIGHT SYNC signal (d): every `path:line` reference in a goal/requirement is resolved against `origin/$BASE_BRANCH`, judged `HOLDS` / `STALE` / `UNCLEAR` by the running model from a ±4-line excerpt, and surfaced in the brief / Phase 1.5 summary — **advisory by construction**, never able to change CLEAR/OVERLAP/SUPERSEDED, `unverified`, or PASS→NEEDS_HUMAN on its own.

**Problem Statement:**
`skills/preflight-sync/SKILL.md` today classifies CLEAR/OVERLAP/SUPERSEDED from file overlap (a), merged-equivalent (b), and churn count (c) only — nothing checks whether a defect a goal or requirement *describes* is still visible at the exact `path:line` it cites. A brief can be planned against a premise a merged commit already changed — the same failure family as the v13.1.0→v14.0.0 stale-branch incident (`CLAUDE.md` §"Claimed work is already merged... (stale-branch trap)"), one level down: this time the *file* is right but the *line* is stale.

## Acceptance Criteria
- [ ] Fixture goal citing `loomwright/scripts/automate-helpers.sh:244` with the description "matches only done" ⇒ `HOLDS` row; the same goal against a fixture repo where the line was removed ⇒ `STALE` row with both age fields populated.
- [ ] Fixture goal containing only `2026-01-01T10:00`, `host:8080`, `3:1`, `12:15 UTC` (all near-misses the PATH predicate must reject) ⇒ no rows, no heading emitted at all.
- [ ] **Byte-identity:** a goal with zero refs produces a Launch Pad brief identical to `origin/main`'s Launch Pad output for the same goal, modulo the `Base commit` line (trace this — a manual before/after diff recorded in the PR body with the exact diff command used, since the check is prose/model-judgment, not a deterministic script with its own unit test).
- [ ] Phase 1.5: with 5 refs and the PRE-FLIGHT SYNC budget already at 5 of its ≤6 calls, the summary shows `premise_check=skipped_budget` and `preflight_sync` is whatever (a)/(b) produced — trace both paths (refs-present-with-budget, refs-present-without-budget) explicitly in the PR body.
- [ ] `grep -n 'never moves the decision from PASS to NEEDS_HUMAN' loomwright/agents/plan-reviewer.md` → exactly 1 hit; Criterion count stays 16 (`grep -c '^### [0-9]\+\.' loomwright/agents/plan-reviewer.md` = 16); Decision Matrix table unchanged vs `origin/main` (no new row, no row text changed).
- [ ] `grep -nE 'git fetch' loomwright/agents/launch-pad.md` → 0 hits (Launch Pad makes no network calls today and this item must not change that).
- [ ] `grep -nE 'stat -|date -d|date -j' <every file this item touches>` → 0 hits (the honest age column is derived from `find … -mmin` only, per decision H6 — no `stat`/`date -d`/`date -j` portability trap).
- [ ] Fixture goal with an ambiguous ref that resolves to zero or >1 files by unique-suffix match ⇒ `resolves: no` row with `premise: UNCLEAR`; a separate fixture where the cited line moved (same phrase/symbol found at a different line number in the excerpt search) ⇒ `HOLDS (moved to <line>)` row, never `STALE`.
- [ ] `loomwright/skills/preflight-sync/SKILL.md` gains signal **(d)** placed immediately after (c), with the identical advisory-only sentence structure (c) uses (verbatim phrases, quoted exactly from the live `preflight-sync/SKILL.md` signal-(c) paragraph — re-read it at implementation time rather than copying this brief's wording, since a paraphrase here would itself be the drift this item exists to prevent): "MUST NOT, by itself, change the CLEAR | OVERLAP | SUPERSEDED classification", "never turns a CLEAR into an OVERLAP", "never triggers the `AskUserQuestion` soft-gate", "never contributes to a `preflight_overlap_detected` **fail-closed** abort" (note: "fail-closed" is part of the verbatim phrase — do not drop it). Ordering + budget rule per decision H5 — (d) runs LAST (after (a), (b), the corroboration control, and (c)), is ONE batched Bash call, and is skipped silently with `premise_check=skipped_budget` in the summary when fewer than 1 of the ≤6-call budget remains; (d) itself can never be the cause of `preflight_sync = unverified`.
- [ ] `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Supervisor Phase 1.5 PRE-FLIGHT SYNC budget" table's accounting is updated to include the (d) call (common path unchanged when the goal cites no refs; +1 call when refs exist and budget allows).
- [ ] `loomwright/agents/plan-reviewer.md` Criterion 1 gains exactly one sub-check sentence (no new criterion, no renumber): when the brief has a `### Cited-line premise check` section with a STALE row, record a **LOW** `file_path` finding naming the ref, with body text verbatim: "A STALE premise row is advisory; on its own it never moves the decision from PASS to NEEDS_HUMAN or FAIL."
- [ ] `loomwright/skills/supervisor-readiness/SKILL.md`'s brief template documents the optional `### Cited-line premise check` subsection under the Phase-3-derived section the template already has, with the omit-when-empty rule stated (no heading, no "none" line, same convention as `Source requirement`).
- [ ] `loomwright/agents/launch-pad.md` Phase 3 gains a new action appended after the last existing numbered action (action 9, the validator-owned-surfaces check) — not inserted, not renumbering any existing action — running the 4 steps from the source requirement's Scope items 1–4 (reference extraction, resolution by exact/unique-suffix path match, model judgment HOLDS/STALE/UNCLEAR, the honest `find`-based age column) and emitting `### Cited-line premise check` under Phase 3 output when ≥1 ref is found (0 refs ⇒ emit nothing — no heading, no "none" line). Any STALE row is carried to Phase 5 Risk Assessment as a MEDIUM row with `source: "Cited-line premise (Phase 3)"`.
- [ ] Re-measure `launch-pad` and `plan-reviewer` in `loomwright/docs/prompt-token-budgets.json` after the prose additions land (measured proxy weight + ~10% headroom, per this file's own convention) and mirror both rows in `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" — do not trust the source requirement's stale "777 headroom" citation; re-measure live.
- [ ] CHANGELOG.md gains one paragraph; `plugin.json` + `marketplace.json` version bump (patch — additive, advisory-only, non-breaking). README.md/CLAUDE.md are NOT touched (memory: `release-surfaces-readme-claude-md-no-longer-bump`).
- [ ] `check-token-budget.sh`, `check-doc-currency.sh`, full test loop (`loomwright/scripts/test-*.sh` + root `scripts/test-*.sh` + `scripts/check-vendor-coupling.sh`) + `scripts/test-citation-drift.sh` all green.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Cited-line premise check: Launch Pad Phase 3 action + Phase 1.5 signal (d) + plan-reviewer Criterion 1 sub-check + doc/budget sync | all | 9 modify, 0 create | quality-checklist, preflight-sync, supervisor-readiness | LAUNCHABLE |

```yaml
# Subtask 1 — cited-line premise check + doc/budget sync (LAUNCHABLE)
provides:
  - {kind: "symbol", path: "loomwright/agents/launch-pad.md", name: "Cited-line premise check"}
  - {kind: "symbol", path: "loomwright/skills/preflight-sync/SKILL.md", name: "signal (d)"}
  - {kind: "symbol", path: "loomwright/agents/plan-reviewer.md", name: "never moves the decision from PASS to NEEDS_HUMAN"}
  - {kind: "symbol", path: "loomwright/skills/supervisor-readiness/SKILL.md", name: "Cited-line premise check"}
requires: []
lanes:
  - "loomwright/agents/launch-pad.md"
  - "loomwright/skills/preflight-sync/SKILL.md"
  - "loomwright/agents/plan-reviewer.md"
  - "loomwright/skills/supervisor-readiness/SKILL.md"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "CHANGELOG.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 (single subtask — one cohesive advisory check spanning both surfaces that must share
           wording per the requirement's own instruction, plus mechanical budget/doc bookkeeping)
```

### File Overlap Matrix
N/A — single subtask, no sibling to overlap with.

### Batch Plan
- **Batch 1:** Subtask 1
- **Recommended workers:** 1
- **Estimated batches:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/quality-checklist/SKILL.md`, `skills/preflight-sync/SKILL.md`, `skills/supervisor-readiness/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| The requirement explicitly forbids `git fetch` in Launch Pad (non-goal) and forbids `stat -`/`date -d`/`date -j` (decision H6) — both are easy to reach for when computing "age" or resolving a ref, and this repo has a documented, repeated CLAUDE.md-level incident class around exactly these two portability traps (`stat -f %m` succeeds-with-garbage on Linux; macOS-green ≠ CI-green for stat/date/sed -i). | HIGH | Explicit acceptance criteria grep for zero hits of both patterns across every touched file; the age column is spec'd as `find … -mmin +1440/+60` only — implementer must not substitute a `stat`/`date`-based freshness check even though it reads simpler. |
| The reference-extraction PATH predicate is easy to under- or over-specify (the source requirement gives 4 explicit near-miss examples — an ISO timestamp, a host:port, a ratio, a 24h time — that must NOT match `<path>:<digits>`). A regex that's slightly too permissive silently pollutes real briefs with garbage premise rows; slightly too strict silently drops real citations. | MEDIUM | Acceptance criterion requires the exact 4 near-miss fixtures produce zero rows; PR body must trace the regex against all 4 by hand since there is no unit-test harness for this model-judgment prose (no shared script exists to run automated fixture tests against — see the "no sub-agent, no external CLI" constraint in the source requirement). |
| Two independent surfaces (`launch-pad.md` Phase 3 and `preflight-sync/SKILL.md` signal (d)) must describe the SAME reference-extraction/resolution/judgment steps in matching prose per Scope item 1 ("shared wording in both surfaces") — a natural site for the "restated fact must move together" drift class this repo has hit repeatedly (`CLAUDE.md`/memory: `rules-violated-by-their-own-surrounding-text`, `sweep-grep-gate-variants`). | MEDIUM | PR body must diff the two sections side-by-side and confirm the extraction/resolution/judgment wording matches; Phase 4.5 review should specifically check this pairing, not just each file in isolation. |
| Budget/doc-currency bookkeeping (token-budget re-measure for `launch-pad` + `plan-reviewer`, `ARCHITECTURE_CONTRACTS.md` mirror rows, CHANGELOG + version bump) is mechanical but easy to under-shoot — this repo's CI fails CLOSED on an agent with no declared budget and on a stale doc-currency claim. | LOW | Acceptance criteria explicitly require live re-measurement (not trusting the source requirement's stale "777 headroom" figure) and green `check-token-budget.sh`/`check-doc-currency.sh` before FINALIZE. |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-24-cited-line-premise.md
```

---

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/262
- **Reconciled:** lifecycle move completed by reconcile-jobs.sh, not by the completion tail
- **Evidence:** automate engine supplied merge evidence for .supervisor/requirements/harness-port/03-cited-line-premise.md (https://github.com/vikashruhilgit/loomwright/pull/262) — the engine verified the PR merged against the forge; this reconciler stayed offline
- **Caveat:** fields the completion tail would have recorded (files changed, heal decision and iterations, red-team advisory) are NOT recoverable after the fact and are deliberately omitted rather than invented.
