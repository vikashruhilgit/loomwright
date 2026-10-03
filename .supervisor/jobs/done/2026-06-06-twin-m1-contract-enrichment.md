# Supervisor Job: System Twin M1 — SYSTEM_CONTRACT enrichment (dependency graph + incident history)

> **What:** make Pillar-1 "predict" genuinely richer — add an **incident-history** field to `SYSTEM_CONTRACT`
> and a **derived dependents graph** so blast-radius prediction surfaces "last time this changed, X broke" +
> the full graph (depends-on AND depended-on-by). Advisory/propose-only — never gates. Additive (schema stays v1).
> **Sequencing:** #30 merged; branch from current `main` (**v14.14.0**); version → **v14.15.0**.

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager (plugin's own repo)
- **CLAUDE.md:** ✓ fresh (v14.14.0) · **Git:** `main`; `git pull` first · **gh:** ✓ · **Worktrees:** none orphaned
- **Blockers:** 0 | **Warnings:** 0 | **legacy_brief:** false

## Task
**Goal:** Extend the System Twin's `SYSTEM_CONTRACT` (additive, `schema_version` stays 1) with an **`incident_history[]`** field, and add a **testable graph helper** that computes the full blast-radius graph (depends-on + derived dependents) from the contract store. The Phase 4.5 builder populates `incident_history` from *this run's* conformance violations + self-heal fixes for the touched subsystem; Launch Pad's blast-radius prediction surfaces incident history + the richer graph. Everything advisory — no gate/control-flow change.

## Acceptance Criteria
- [ ] **Schema (additive):** `docs/RESULT_SCHEMAS.md` `## SYSTEM_CONTRACT` gains `incident_history: [ {date, kind, summary, source} ]` (`kind` ∈ `conformance_violation | self_heal_fix | other`); `dependencies[]` clarified as **directional depends-on** edges. `schema_version` stays `1` (additive precedent); a contract without the field stays valid.
- [ ] **Graph helper (testable):** new `scripts/twin-graph.sh` reads `.supervisor/twin/contracts/`, and for a given subsystem outputs its **depends-on** (from its own `dependencies`) AND **depended-on-by** (derived by scanning other contracts) — the full blast-radius set. Fail-safe (no contracts / no jq → empty result, exit 0). Backed by `scripts/test-twin-graph.sh` (mirrors `test-system-contract.sh`).
- [ ] **Builder enrichment:** the Phase 4.5 contract builder (the ephemeral builder invoked from `supervisor.md`'s completion tail) appends an `incident_history` entry for a touched subsystem **only when** this run recorded a `contract_conformance` violation or a self-heal fix for it (bounded; deduped; sourced to the session id). No incident → no entry.
- [ ] **Predict surface:** Launch Pad Phase 3 blast-radius prediction calls `twin-graph.sh` for the full graph and surfaces any `incident_history` ("⚠ last change here: …") — advisory, graceful fallback when absent.
- [ ] **Advisory + anti-rebloat:** nothing gates or self-applies; **no new command/agent/hook/skill** (2 new scripts are uncounted); version → v14.15.0; `check-doc-currency.sh` + `validate-version.sh` pass.

## Subtask Structure

### ST1 — schema + graph helper + self-test  [blocks all]
**Files:** `docs/RESULT_SCHEMAS.md` (modify), `scripts/twin-graph.sh` (create), `scripts/test-twin-graph.sh` (create).
**Work:** add `incident_history[]` + directional-`dependencies` note to the SYSTEM_CONTRACT schema (additive, schema_version 1, define the `incident_history` shape + the result-block-style provenance); create `twin-graph.sh` (depends-on + derived dependents, fail-safe exit 0) + its self-test.
```yaml
provides:
  - {kind: file, path: docs/RESULT_SCHEMAS.md, name: incident_history_schema}
  - {kind: file, path: ai-agent-manager-plugin/scripts/twin-graph.sh, name: graph_helper}
  - {kind: file, path: ai-agent-manager-plugin/scripts/test-twin-graph.sh, name: graph_selftest}
requires: []
```

### ST2 — builder incident enrichment  [dep ST1]
**Files:** `ai-agent-manager-plugin/agents/supervisor.md` (modify).
**Work:** in the Phase 4.5 completion-tail builder step, when deriving a touched subsystem's contract, append an `incident_history` entry **iff** this run had a `contract_conformance` violation or self-heal fix for that subsystem (bounded list, dedupe, `source: <session_id>`). Minimal additive edit; advisory; no control-flow change.
```yaml
provides:
  - {kind: capability, path: ai-agent-manager-plugin/agents/supervisor.md, name: builder_incident_capture}
requires:
  - {kind: file, name: incident_history_schema, from: ST1}
```

### ST3 — Launch Pad predict surface  [dep ST1]
**Files:** `ai-agent-manager-plugin/agents/launch-pad.md` (modify).
**Work:** Phase 3 blast-radius prediction calls `twin-graph.sh` for the full depends-on + dependents set, and surfaces `incident_history` ("⚠ last change here: …") in the prediction. Advisory; graceful fallback when no contract/graph.
```yaml
provides:
  - {kind: capability, path: ai-agent-manager-plugin/agents/launch-pad.md, name: richer_prediction}
requires:
  - {kind: file, name: graph_helper, from: ST1}
  - {kind: file, name: incident_history_schema, from: ST1}
```

### ST4 — docs, version, currency  [dep ST1-3]
**Files:** `ai-agent-manager-plugin/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CLAUDE.md`, `CHANGELOG.md` (modify).
**Work:** version → v14.15.0; CHANGELOG; CLAUDE.md banner; counts unchanged (no command/agent/hook/skill added). Run both gates.
```yaml
provides:
  - {kind: capability, path: CHANGELOG.md, name: release_notes}
requires:
  - {kind: capability, name: builder_incident_capture, from: ST2}
  - {kind: capability, name: richer_prediction, from: ST3}
  - {kind: file, name: graph_helper, from: ST1}
```

## Parallelism Analysis
- **Batch 1:** ST1 · **Batch 2:** ST2 ∥ ST3 (disjoint: `supervisor.md` vs `launch-pad.md`) · **Batch 3:** ST4
- **Recommended workers:** 2

## Skill References
- **ST1:** `skills/state-management/SKILL.md`, `skills/quality-checklist/SKILL.md`
- **ST2:** `skills/quality-checklist/SKILL.md`, `skills/state-management/SKILL.md`
- **ST3:** `skills/supervisor-readiness/SKILL.md`, `skills/quality-checklist/SKILL.md`
- **ST4:** `skills/claude-md-validation/SKILL.md`, `skills/quality-checklist/SKILL.md`

## Risk Assessment
| Risk | Severity | Mitigation |
|---|---|---|
| Touches 2 engine files (supervisor.md, launch-pad.md) | MED | Edits are minimal + additive + advisory; graph logic isolated in tested `twin-graph.sh` |
| Incident-history could grow unbounded / become noise | LOW | Bounded list + dedupe + only this-run incidents; advisory |
| Graph helper miscomputes dependents | LOW | Isolated, self-tested; fail-safe empty/exit 0 |
| Anti-rebloat | LOW | No new command/agent/hook/skill; 2 uncounted scripts; additive schema |

## Configuration
- **Mode:** parallel (2 workers) · **Cost:** default · **Branch:** `feature/twin-m1-enrichment`
- **References:** `docs/RESULT_SCHEMAS.md:645-663` (SYSTEM_CONTRACT), `scripts/{write,read}-system-contract.sh`, `scripts/test-system-contract.sh` (self-test pattern), `docs/SPIKES/SYSTEM_TWIN_ROADMAP.md` (§4 M1).

## Handoff
```
git pull
/supervisor job: .supervisor/jobs/pending/2026-06-06-twin-m1-contract-enrichment.md --base-branch main
```

## Outcome
- **Status:** completed
- **Completed:** 2026-06-06T12:20:14Z
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/31
- **Branch:** feature/twin-m1-enrichment (base: main)
- **Files changed:** 11 (+386 / -20)
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0 (integration review passed first try)
- **Heal remaining issues:** 0
- **Rubric:** null (brief has no ## Outcomes Rubric)
- **Twin:** conformance PASS (0 violations) · benchmark system-twin-selftest=4 · 3 contracts written
- **Summary:** ST1 incident_history schema + twin-graph.sh blast-radius helper (10/10 self-test); ST2 Phase 4.5 builder records this-run incident_history (bounded/deduped/PASS-only); ST3 Launch Pad surfaces full graph + incident history; ST4 v14.15.0 release + docs + currency gates green. All advisory/additive (schema_version stays 1); counts unchanged 13/15/50/19. ST1 had one FAIL→fix (false-edge misattribution) then verified.
