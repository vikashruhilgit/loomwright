# Supervisor Job: Generic Launch Pad + Plan Reviewer prevention guardrails

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh; CLAUDE.md banner still reads v14.28.0 but `plugin.json` is already v14.29.0 — see Risk R5)
- **Git:** dirty (1 file: `ai-agent-manager-plugin/docs/SPIKES/LEARNING_LOOP_ROADMAP.md`), branch: main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 2 (working tree dirty; on `main` — Supervisor will branch before editing)

## Task
**Goal:** Add three **generic, repo-agnostic** prevention guardrails so Launch Pad and Plan Reviewer catch a class of planning gaps that today slip through to review churn — without hard-coding any repo-specific knowledge (that stays in `CLAUDE.md` / skills / roadmap).

**Problem Statement:**
A recent job missed that a "make `check-doc-currency.sh` pass" acceptance criterion implied editing the *files that validator scans* — the impact map omitted the validator-owned surfaces, so the gap surfaced only at review time. The fix must be **generic**, not a special-case for this plugin's version-bump files:
1. **Validator-owned surfaces** — when a task depends on a generated/mechanical validation script, Launch Pad should include the surfaces that validator owns/scans in the impact map (or explicitly note "files scanned by the validator may need updates").
2. **Canonical-list / source-of-truth claims** — when a brief asserts "single source of truth / canonical list / exact names", Plan Reviewer should verify the listed values against the cited source, or flag the mismatch.
3. **Dirty working tree on the source doc** — when the source requirement/doc a brief is planned from is uncommitted, Launch Pad should warn (the staleness/provenance risk).

## Feasibility (optional — Launch Pad v10.3+)
- **Tech Stack Compatibility:** GO — markdown agent-prompt edits only.
- **Dependency Availability:** GO — no new deps.
- **Architecture Fit:** GO — extends existing Launch Pad phases + Plan Reviewer criteria; conditional/advisory, consistent with the v14.x "skip silently when gating signal absent" convention.
- **Scope vs Supervisor Capability:** GO — 3 subtasks, prompt-logic edits + docs.
- **Hard Blockers:** none.

**Overall Verdict:** GO

## Acceptance Criteria
- [ ] **AC1** — Given a goal/brief whose acceptance criteria depend on a generated/mechanical validation script (e.g. a doc-currency / lint / codegen checker), when Launch Pad runs Phase 3 ANALYZE, then it inspects that validator (or its declared scan set) and includes the validator-owned surfaces in the file impact map — stated **generically** (no repo-specific filenames hard-coded into the agent prompt).
- [ ] **AC2** — Given a brief that claims a "single source of truth", "canonical list", or "exact names" against a cited source, when Plan Reviewer evaluates it, then a new **conditional Criterion 15** verifies the listed values against that cited source and flags any mismatch; the criterion **skips silently** when no such claim is present (same convention as conditional Criteria 11/13/14).
- [ ] **AC3** — Given the source requirement/doc a brief is planned from is uncommitted in the working tree, when Launch Pad runs Phase 1 VALIDATE, then it emits a **warning** (not a blocker) noting the source doc is uncommitted and its provenance/staleness is unverified.
- [ ] **AC4** — Given none of the three trigger conditions apply, when Launch Pad / Plan Reviewer run, then behavior is unchanged (all three guardrails are additive and trigger-gated — no false positives on ordinary briefs).
- [ ] **AC5** — Given the changes, when `scripts/check-doc-currency.sh` runs, then it passes (counts unchanged: no new agent/command/skill/hook), and `AGENT_GUIDELINES.md` / `RESULT_SCHEMAS.md` reflect the new Criterion 15 issue category if one is introduced.

## Outcomes Rubric (optional — v12.2.0+)
- `agents/launch-pad.md` Phase 3 (ANALYZE) documents a generic "validator-owned surfaces" impact-map rule with no repo-specific filename hard-coded.
- `agents/launch-pad.md` Phase 1 (VALIDATE) documents a dirty-working-tree warning for the source requirement/doc.
- `agents/plan-reviewer.md` defines a conditional Criterion 15 verifying canonical-list / source-of-truth claims against the cited source.
- `agents/plan-reviewer.md` states Criterion 15 skips silently when no canonical-source claim is present.
- The version string in `plugin.json` is bumped above its current value (14.29.0 at authoring).

## Executable Acceptance (optional — System Twin / M2b, v14.19.0+)
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Launch Pad guardrails: Phase 1 dirty-source warning + Phase 3 validator-owned-surfaces rule | AC1, AC3, AC4 | 1 modify, 0 create | claude-md-validation, supervisor-readiness | LAUNCHABLE |
| 2 | Plan Reviewer conditional Criterion 15: canonical-list / source-of-truth verification | AC2, AC4 | 1 modify, 0 create | quality-checklist | LAUNCHABLE |
| 3 | Version bump + counts + CLAUDE.md banner + AGENT_GUIDELINES note + doc-currency green | AC5 | 4 modify, 0 create | commit | BLOCKED (by #1, #2) |

### Provides / Requires Schema (v12.0.0+)

```yaml
# Subtask 1 — Launch Pad Phase 1 + Phase 3 guardrails (LAUNCHABLE)
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/launch-pad.md", name: "Validator-Owned Surfaces"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/launch-pad.md", name: "Dirty Source Warning"}
requires: []
external_requires: []

# Subtask 2 — Plan Reviewer Criterion 15 (LAUNCHABLE)
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/plan-reviewer.md", name: "Criterion 15"}
requires: []
external_requires: []

# Subtask 3 — version bump + counts + CLAUDE.md banner + doc-currency (BLOCKED by #1,#2)
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/.claude-plugin/plugin.json", name: "version"}
  - {kind: "symbol", path: ".claude-plugin/marketplace.json", name: "version"}
  - {kind: "symbol", path: "CLAUDE.md", name: "Project Overview"}
  - {kind: "symbol", path: "AGENT_GUIDELINES.md", name: "Plan Reviewer Criteria"}
requires:
  - {from: "1", kind: "symbol", path: "ai-agent-manager-plugin/agents/launch-pad.md", name: "Validator-Owned Surfaces"}
  - {from: "2", kind: "symbol", path: "ai-agent-manager-plugin/agents/plan-reviewer.md", name: "Criterion 15"}
external_requires:
  - "scripts/check-doc-currency.sh must pass (validator-owned surface)"
```

**Authoring note (validator-owned surface — dogfooding this very feature):** Subtask 3's acceptance depends on `scripts/check-doc-currency.sh` passing. This change adds **no** new agent/command/skill/hook (Criterion 15 is a criterion *inside* an existing agent, not a new agent), so counts stay **14 / 18 / 55 / 19** — bump only the version string + `description` `vX.Y.Z` token in place; do **not** touch the four count claims. If Criterion 15 introduces a new PLAN_REVIEW_RESULT issue category, document it in `agents/plan-reviewer.md` and `docs/RESULT_SCHEMAS.md` (PLAN_REVIEW_RESULT is not schema-version-bumped for an additive category — follow the existing `executable_acceptance` precedent).

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──┐
Subtask 2 ──┴──→ Subtask 3
```

### File Overlap Matrix
| | S1 | S2 | S3 |
|---|----|----|----|
| **S1** `agents/launch-pad.md` | — | none | none |
| **S2** `agents/plan-reviewer.md` | none | — | none |
| **S3** `plugin.json`, `marketplace.json`, `CLAUDE.md`, `AGENT_GUIDELINES.md` | none | none | — |

No file overlap — Subtasks 1 and 2 touch disjoint agent prompts and run fully in parallel; Subtask 3 (version/docs) depends on both.

### Batches
- **Batch 1:** Subtask 1 ∥ Subtask 2 (parallel — disjoint files)
- **Batch 2:** Subtask 3 (version/docs/doc-currency)
- **Recommended workers:** 2

## Skill References
- `claude-md-validation` — Phase 1 freshness/provenance checks (Subtask 1)
- `supervisor-readiness` — impact-map + brief conventions Phase 3 feeds (Subtask 1)
- `quality-checklist` — Plan Reviewer criteria framing (Subtask 2)
- `commit` — conventional commit + version bump (Subtask 3)

## Risk Assessment
| Risk | Severity | Mitigation |
|------|----------|------------|
| **R1** — "Generic" rule drifts into a repo-specific special-case (e.g. naming `check-doc-currency.sh`). | HIGH | The agent-prompt wording MUST be generic ("when a task depends on a generated/mechanical validation script…"); the doc-currency example belongs in CLAUDE.md / a skill, used only as an *illustrative* example, never as the rule's trigger. AC1/AC2 assert genericity; Plan Review should reject a hard-coded filename in the rule itself. |
| **R2** — Criterion 15 over-fires (flags any brief mentioning "list" or "names"). | MEDIUM | Gate on explicit canonical-claim phrasing ("single source of truth", "canonical list", "exact names", "authoritative") **with a cited source**; skip silently otherwise (Criteria 11/13/14 precedent). Default severity LOW/advisory unless the cited source is readable and a concrete mismatch is found (then MEDIUM/BLOCKING). |
| **R3** — Phase 1 dirty-source warning fires on every dirty tree, becoming noise. | LOW | Scope the warning specifically to the **source requirement/doc** the brief is planned from (when a `.supervisor/requirements/` file or named source doc is resolved and is uncommitted), not the whole working tree. |
| **R4** — Coordination with companion brief `2026-06-17-review-pr-until-mergeable.md` (both bump `plugin.json` version + edit `CLAUDE.md`). | MEDIUM | Run the two briefs **sequentially**. Whichever runs second branches from the first's merged result (or re-bumps the version). Do not run both Supervisors concurrently. |
| **R5** — Brief authored against v14.28.0 snapshot; repo advanced to v14.29.0 mid-planning (commits `7868123`, `3c38767`). | LOW | Subtask 3 must bump above the **live** `plugin.json` value (14.29.0 → 14.30.0), not the stale 14.28.0 in the CLAUDE.md banner. `version-consistent` corpus-task reads the live value. |

## Configuration
- **Base Branch:** main
- **Counts after this change:** 14 agents / 18 commands / 55 skills / 19 hooks (UNCHANGED)
- **Version:** bump from the live `plugin.json` value at **execution time**, not authoring time. This brief is intended to run **after** the companion `--until-mergeable` brief merges, which will have bumped `plugin.json` to ~14.30.0 — so this brief will most likely bump **14.30.0 → 14.31.0**, not 14.30.0. Read the live value; do not assume any literal. `version-consistent` corpus-task validates against the live value.

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-06-17-launchpad-planreviewer-guardrails.md
```
> Run in a fresh Claude Code session, **only after a human has merged the companion `--until-mergeable` PR** — do not run both at once (Risk R4). Neither Supervisor nor the merge-ready loop auto-merges.

## Outcome
- **Status:** completed
- **Completed:** 2026-06-17T17:53:04Z
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/64
- **Branch:** feature/launchpad-planreviewer-guardrails
- **Files changed:** 10
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0
- **Heal remaining issues:** 0
- **Red team advisory:** disabled
- **Rubric score:** 5/5
- **Summary:** Three generic, trigger-gated planning guardrails (Launch Pad validator-owned-surfaces + scoped dirty-source warning; Plan Reviewer conditional Criterion 15 + canonical_source category). Version 14.30.0→14.31.0; counts unchanged 14/18/55/19; validate-version/doc-currency/command-sync all green; Phase 4.5 consistency_audit PASS; rubric 5/5.
