# Supervisor Job: Exit-code tables for /janitor and /handoff

## Environment
- **Project:** ai-agent-manager (Loomwright plugin repo)
- **Source requirement:** .supervisor/requirements/fixture-small-commands-exit-codes.md
- **Base commit:** 0000000000000000000000000000000000000000

## Task
**Goal:** Each of `/janitor` and `/handoff` documents its exit codes in an `## Exit codes` table on its own command page, matching the script it runs.

**Problem Statement:** A user who sees a non-zero exit from one of these commands has to open the script behind it (`janitor-report.sh`, `build-handoff.sh`) to learn what the code means.

**Non-goals (from the requirement):** no exit code or script changes; no `## Exit codes` section on any other command.

## Acceptance Criteria
- [ ] **AC1:** Given `loomwright/commands/janitor.md`, when a user reads it, then an `## Exit codes` table lists each exit code `/janitor` can return and what it means.
- [ ] **AC2:** Given `loomwright/commands/handoff.md`, when a user reads it, then an `## Exit codes` table lists each exit code `/handoff` can return and what it means.
- [ ] **AC3:** Given each table, when it is compared with the `exit` statements of the script the command runs, then every reachable code is listed and no unreachable one is.
- [ ] **AC4:** Given the branch, when `bash scripts/check-doc-currency.sh` runs, then it passes.

## Executable Acceptance
- corpus-task: doc-currency-green

## Touched-file invariants
- **`loomwright/docs/prompt-token-budgets.json`** — keep: the row shape `{"budget": N, "measured": M, "note": "…"}`; update only the `janitor` and `handoff` rows under `.commands`; mirror: the same two rows in `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets"; pinned by: `scripts/check-token-budget.sh` (fails closed on a mismatch).

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Exit-code tables on two command pages | AC1–AC4 | 4 modify, 1 create | agent-output | LAUNCHABLE |

### File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| commands | `loomwright/commands/janitor.md` (44), `loomwright/commands/handoff.md` (54) | — | HIGH |
| budgets + release | `loomwright/docs/prompt-token-budgets.json` (93), `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (1051 — the budget mirror rows it already owns) | `changelog.d/fixture-small-commands-exit-codes.md` | HIGH |

## Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/commands/janitor.md", name: "## Exit codes"}
  - {kind: "symbol", path: "loomwright/commands/handoff.md", name: "## Exit codes"}
  - {kind: "file", path: "changelog.d/fixture-small-commands-exit-codes.md"}
requires: []
lanes:
  - "loomwright/commands/janitor.md"
  - "loomwright/commands/handoff.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "changelog.d/fixture-small-commands-exit-codes.md"
external_requires: []
```

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/agent-output/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| A table drifts from its script when the script later adds an exit code | LOW | AC3 compares each table with the script's `exit` statements at authoring time |
| The two command pages grow past their token budgets | LOW | The budgets group re-measures the two rows (measured + ~10%) |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1

## Handoff
```
/supervisor job: .supervisor/jobs/pending/fixture-small-commands-exit-codes.md
```
