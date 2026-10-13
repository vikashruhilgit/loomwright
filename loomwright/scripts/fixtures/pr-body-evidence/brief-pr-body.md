# Supervisor Job: Add a prompt-size table to the QA blueprint

## Environment
- **Project:** ai-agent-manager (Loomwright plugin repo)
- **Base commit:** 0000000000000000000000000000000000000000

## Task
**Goal:** Add a `## Prompt sizes` table to `loomwright/docs/QA_SYSTEM_BLUEPRINT.md` that gives the line count of `loomwright/agents/qa-strategist.md` and `loomwright/agents/qa-executor.md`, so a reader can see how large each QA prompt is.

**Problem Statement:** Readers of the QA blueprint cannot tell how large the two QA prompts are without opening them, and earlier size notes in review threads were never reproducible because nobody recorded how the numbers were taken.

## Acceptance Criteria
- [ ] **AC1:** Given `loomwright/docs/QA_SYSTEM_BLUEPRINT.md`, when a reader opens `## Prompt sizes`, then a two-row table gives the line count of `qa-strategist.md` and `qa-executor.md`.
- [ ] **AC2:** Given the PR, when it is opened, then the PR body pastes the exact command that produced every number in the table.
- [ ] **AC3:** Given the finished branch, when Supervisor completes, then a PR against `main` is open.

## Executable Acceptance
- corpus-task: doc-currency-green

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Add the prompt-size table | AC1–AC3 | 1 modify, 0 create | qa-strategy | LAUNCHABLE |

### File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| docs | `loomwright/docs/QA_SYSTEM_BLUEPRINT.md` | — | HIGH |

## Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/docs/QA_SYSTEM_BLUEPRINT.md", name: "## Prompt sizes"}
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
| The line counts go stale when either prompt changes | LOW | The table names the date it was taken; AC2 keeps the command so anyone can re-run it |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1

## Handoff
```
/supervisor job: .supervisor/jobs/pending/fixture-qa-prompt-sizes.md
```
