# Supervisor Job: Clarify the QA blueprint overview

## Environment
- **Project:** ai-agent-manager (Loomwright plugin repo)
- **Base commit:** 0000000000000000000000000000000000000000

## Task
**Goal:** Rewrite the `## Overview` paragraph of `loomwright/docs/QA_SYSTEM_BLUEPRINT.md` so a first-time reader learns, in its first two sentences, which two agents the QA system pairs and what each one owns.

**Problem Statement:** The overview names both agents but never says what each one owns, so a reader has to reach later sections to learn which agent plans and which one runs tests.

## Acceptance Criteria
- [ ] **AC1:** Given `loomwright/docs/QA_SYSTEM_BLUEPRINT.md`, when a reader opens `## Overview`, then its first two sentences name QA Strategist and QA Executor and what each owns.
- [ ] **AC2:** Given the rest of the file, when the change lands, then no other section changes.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Rewrite the overview paragraph | AC1–AC2 | 1 modify, 0 create | qa-strategy | LAUNCHABLE |

### File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| docs | `loomwright/docs/QA_SYSTEM_BLUEPRINT.md` | — | HIGH |

## Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/docs/QA_SYSTEM_BLUEPRINT.md", name: "## Overview"}
requires: []
lanes:
  - "loomwright/docs/QA_SYSTEM_BLUEPRINT.md"
external_requires: []
```

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/qa-strategy/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| The rewrite drops a fact a later section relies on | LOW | AC2 keeps every other section unchanged; read the whole file first |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1

## Handoff
```
/supervisor job: .supervisor/jobs/pending/fixture-qa-overview.md
```
