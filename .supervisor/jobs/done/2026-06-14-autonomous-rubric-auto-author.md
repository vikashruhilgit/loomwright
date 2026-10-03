# Supervisor Job: Auto-author Outcomes Rubric in /autonomous multi-iteration mode

## Plan Review: NEEDS_HUMAN (user override)
Plan Reviewer returned NEEDS_HUMAN over two operator-confirmation items, both resolved before save:
1. (MEDIUM, fixed) S5 file list extended to cover `.claude-plugin/marketplace.json` (version + description headline) and the `plugin.json` description headline — the surfaces `scripts/check-doc-currency.sh` scans.
2. (MEDIUM, decided) S3 will **extend existing Criterion 3** (Acceptance Criteria Quality) rather than add Criterion 15 — keeps the "14 criteria" count stable, no drift.
3. (LOW, fixed) S3 `requires` entry made concrete (no ellipsis).
All file paths and line anchors (124, 157, 417, 483) were verified by the reviewer; dependency DAG acyclic; S1/S3 parallel batch touches disjoint files.

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** Found (fresh)
- **Git:** clean (only untracked `.claude/`), branch: main
- **GitHub CLI:** Authenticated (vikashruhilgit)
- **Plugin version:** 14.24.0
- **Blockers:** 0 | **Warnings:** 0
- **Change class:** prompt/skill/doc (markdown only — no executable runtime code)

## Task
**Goal:** When `/autonomous` runs in **multi-iteration mode** and the requirement file has **no `## Outcomes Rubric`**, have the inlined Launch Pad **auto-author one** (3–7 diff-checkable bullets derived from the acceptance criteria + Phase 3 codebase analysis), surface it at Launch Pad Phase 6 for human approval, **persist it back into the requirement body**, and **freeze it** so every subsequent iteration scores against the same yardstick.

**Problem Statement:**
The Outcomes Rubric is the autonomous loop's only measurable iterate-to-target signal, but it has a *consumer* (Supervisor's Rubric Grader in Phase 4.5; the autonomous EVALUATE Signal-1 gate) and **no producer**. Neither Product Owner nor Launch Pad authors it — it lives in a manual placeholder gap (`skills/autonomous-loop/SKILL.md` lines 124 and 157, where the loop only *preserves* a rubric, never *creates* one). Without a rubric, multi-iteration degrades to the no-rubric gate ("run once, ask continue/stop") — the loop's cost without its benefit. This change wires the missing producer at the only seam that needs it: the `/autonomous` → Launch Pad inline call.

## Acceptance Criteria
- [ ] Given a multi-iteration `/autonomous` run whose requirement lacks `## Outcomes Rubric`, when PLAN runs, then the inlined Launch Pad is instructed to author a rubric (the directive at `autonomous-loop` line 157 is **extended, not replaced**).
- [ ] Given Launch Pad authors a rubric, when Phase 6 runs, then the rubric is shown to the user for approve/edit before save (human-gated, never blind-written).
- [ ] Given an approved authored rubric, when iteration 1 completes, then the rubric is written into the requirement body so the refined-requirement templates (`autonomous-loop` lines 417, 483) carry it verbatim into iteration 2+ (frozen target).
- [ ] Given `--single-iteration` mode (or a requirement that already has a rubric), when PLAN runs, then behavior is unchanged (no authoring; preserve-verbatim path intact).
- [ ] Given the change is documentation/prompt only, when CI runs, then `scripts/check-doc-currency.sh` and `scripts/validate-version.sh` stay green across **all** version-bearing surfaces (plugin.json, marketplace.json, CLAUDE.md).

**Edge cases**
- [ ] Goal whose outcomes are partly non-diff-checkable (e.g. visual): the authored rubric captures only the diff-checkable subset; this limitation is documented, not silently dropped.
- [ ] Launch Pad cannot derive ≥3 diff-checkable bullets: fall back to the existing no-rubric gate rather than emit a degenerate rubric.

## Feasibility
| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Markdown prompt/skill/doc edits; no new stack |
| 2 | Dependency Availability | GO | No new deps |
| 3 | Architecture Fit | CAUTION | Cleanest impl adds a small *guarded* Launch Pad Phase 5 step, lightly stretching the "inline-instruction, no source change" convention |
| 4 | Scope vs Supervisor | CAUTION | 5 tightly-coupled prose files; cross-file consistency is the real work, somewhat serial |
| 5 | Hard Blockers | GO | None; doc-currency CI gate exists and must stay green |

**Overall: CAUTION** (findings carried to Risk Assessment).

## Subtask Structure
| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| S2 | Authoring rules (single source) — `supervisor-readiness` Auto-Authoring subsection + Launch Pad Phase 5 guarded step | 2 modify | LAUNCHABLE |
| S1 | Loop wiring — extend inline-instruction, persist+freeze rubric into requirement body, adjust preservation check | 1 modify | BLOCKED (by S2) |
| S3 | Plan Reviewer rubric-quality validation — **extend Criterion 3** (conditional on rubric present) | 1 modify | BLOCKED (by S2) |
| S4 | Command doc + schema (`commands/autonomous.md`, `docs/RESULT_SCHEMAS.md`) | 2 modify | BLOCKED (by S1,S2,S3) |
| S5 | Version bump + doc-currency sweep | ~6 modify | BLOCKED (by S1–S4) |

## Subtask Contracts
```yaml
# S2 — authoring rules (foundational, single source)
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/supervisor-readiness/SKILL.md", name: "Auto-Authoring (multi-iteration)"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/launch-pad.md", name: "Phase 5"}
requires: []
external_requires: []

# S1 — loop wiring
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/autonomous-loop/SKILL.md", name: "Inline-instruction to Launch Pad"}
requires:
  - {from: "S2", kind: "symbol", path: "ai-agent-manager-plugin/skills/supervisor-readiness/SKILL.md", name: "Auto-Authoring (multi-iteration)"}
external_requires: []

# S3 — plan reviewer validation (extends Criterion 3)
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/plan-reviewer.md", name: "3. Acceptance Criteria Quality"}
requires:
  - {from: "S2", kind: "symbol", path: "ai-agent-manager-plugin/skills/supervisor-readiness/SKILL.md", name: "Auto-Authoring (multi-iteration)"}
external_requires: []

# S4 — docs + schema
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/commands/autonomous.md", name: "Inline instruction to Launch Pad (rubric preservation)"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md", name: "AUTONOMOUS_RUN"}
requires:
  - {from: "S1", kind: "symbol", path: "ai-agent-manager-plugin/skills/autonomous-loop/SKILL.md", name: "Inline-instruction to Launch Pad"}
  - {from: "S2", kind: "symbol", path: "ai-agent-manager-plugin/skills/supervisor-readiness/SKILL.md", name: "Auto-Authoring (multi-iteration)"}
  - {from: "S3", kind: "symbol", path: "ai-agent-manager-plugin/agents/plan-reviewer.md", name: "3. Acceptance Criteria Quality"}
external_requires: []

# S5 — version + doc-currency (covers ALL version-bearing surfaces the gate scans)
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/.claude-plugin/plugin.json", name: "version"}
  - {kind: "symbol", path: ".claude-plugin/marketplace.json", name: "version"}
  - {kind: "file", path: "CHANGELOG.md"}
requires:
  - {from: "S4", kind: "symbol", path: "ai-agent-manager-plugin/commands/autonomous.md", name: "Inline instruction to Launch Pad (rubric preservation)"}
external_requires: []
```

## Dependency Graph
```
S2 ──┬──→ S1 ──┐
     └──→ S3 ──┼──→ S4 ──→ S5
```
(Edges derived from `requires.from` entries.)

## Parallelism Analysis
- **Batch 1:** S2 (foundational authoring rules — empty `requires`)
- **Batch 2:** S1, S3 (parallel — distinct files `autonomous-loop/SKILL.md` vs `plan-reviewer.md`, both depend only on S2)
- **Batch 3:** S4 (documents S1+S2+S3)
- **Batch 4:** S5 (version/doc-currency after content settles)
- **Recommended workers:** 2
- **Estimated batches:** 4

## Skill References
- `skills/supervisor-readiness/SKILL.md` (S2 — rubric authoring-rules home; bump `version:`)
- `skills/autonomous-loop/SKILL.md` (S1 — loop protocol; bump `version:`)
- `agents/launch-pad.md`, `agents/plan-reviewer.md` (S2, S3)

## Risk Assessment
| Risk | Impact | Source | Mitigation |
|------|--------|--------|------------|
| Cross-file prose inconsistency across 5 coupled files | HIGH | Feasibility #4 | Single-source the authoring rules in S2; S1/S3/S4 reference, don't restate. Sweep all stale wording in one pass |
| Authored rubric not frozen → score incomparable across iterations | HIGH | Design | S1 MUST persist the approved rubric into the requirement body the templates copy (`autonomous-loop` lines 417/483); add a `grep -F "## Outcomes Rubric"` freeze verification |
| "No source change" convention stretched by Launch Pad Phase 5 step | MEDIUM | Feasibility #3 | Keep the step *guarded* (fires only when the inlined caller requests authoring); document the deviation in S2 |
| Bad auto-rubric gives false confidence | MEDIUM | Design | Human approval at Phase 6 + S3 quality check (3–7, positive, diff-checkable) |
| Version bump misses a scanned surface → doc-currency CI red | MEDIUM | Plan Review #1 | S5 explicitly covers plugin.json + marketplace.json (version + description headlines) + CLAUDE.md; run `check-doc-currency.sh` + `validate-version.sh` before finalize |
| Plan Reviewer "14 criteria" count drift | LOW | Plan Review #2 | Resolved: S3 **extends Criterion 3** rather than adding #15 — count stays 14 |

## Configuration
- **Workers:** 2
- **Mode:** parallel (batched)
- **Estimated batches:** 4
- **Base Branch:** main

## Outcomes Rubric
- `skills/autonomous-loop/SKILL.md`'s Launch Pad inline-instruction (around line 157) contains a conditional auto-authoring directive gated on multi-iteration mode AND an absent requirement rubric.
- `skills/autonomous-loop/SKILL.md` includes a step that writes the approved authored rubric into the requirement body plus a `grep -F "## Outcomes Rubric"` verification of the freeze.
- `skills/supervisor-readiness/SKILL.md` contains a new "Auto-Authoring (multi-iteration)" subsection under the Outcomes Rubric section stating bullets derive from acceptance criteria and must be diff-checkable.
- `agents/plan-reviewer.md` Criterion 3 validates authored-rubric quality conditionally (skips silently when no `## Outcomes Rubric` present) and the "14 criteria" count is unchanged.
- `ai-agent-manager-plugin/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` carry the same bumped `version`, and `CHANGELOG.md` has a matching new entry.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-06-14-autonomous-rubric-auto-author.md

---

## Outcome (Supervisor v4 — 2026-06-14)
- status: completed
- branch: feature/autonomous-rubric-auto-author
- pr: https://github.com/vikashruhilgit/ai-agent-manager/pull/57
- base: main
- subtasks: S2, S1, S3, S4, S5 — all completed (4 batches)
- preflight_sync: clear
- heal_loop_ran: true
- heal_decision: PASS (Code Reviewer consistency_audit — no BLOCKING/HIGH new issues; 1 MEDIUM drift fixed in heal tail)
- heal_iterations: 0 (review PASS; 1 advisory MEDIUM line-ref drift fixed proactively)
- heal_remaining_issues: 0
- rubric_score: 5/5 (advisory)
- gates: validate-version.sh PASS (14.25.0), check-doc-currency.sh PASS (14/18/54/19)
- version: 14.24.0 → 14.25.0
