# Supervisor Job: Exit-code tables for /janitor, /handoff and /obsidian

## Environment
- **Project:** ai-agent-manager (Loomwright plugin repo)
- **Source requirement:** .supervisor/requirements/fixture-small-commands-exit-codes.md
- **Base commit:** 0000000000000000000000000000000000000000

## Task
**Goal:** Each of `/janitor`, `/handoff` and `/obsidian` documents its exit codes in an `## Exit codes` table on its own command page, matching the script it runs; and `/review-pr`, `/backlog` and `/pr-postmortem` each gain a `## Troubleshooting` section listing their three most common failure messages and what to do about each.

**Problem Statement:** A user who sees a non-zero exit from `/janitor`, `/handoff` or `/obsidian` has to open the script behind it (`janitor-report.sh`, `build-handoff.sh`, `build-vault.sh`) to learn what the code means. Users of `/review-pr`, `/backlog` and `/pr-postmortem` likewise have no single place that explains their common failure messages.

**Non-goals (from the requirement):** no exit code or script changes; no `## Exit codes` section on any other command.

## Acceptance Criteria
- [ ] **AC1:** Given `loomwright/commands/janitor.md`, when a user reads it, then an `## Exit codes` table lists each exit code `/janitor` can return and what it means.
- [ ] **AC2:** Given `loomwright/commands/handoff.md`, when a user reads it, then an `## Exit codes` table lists each exit code `/handoff` can return and what it means.
- [ ] **AC3:** Given `loomwright/commands/obsidian.md`, when a user reads it, then an `## Exit codes` table lists each exit code `/obsidian` can return and what it means.
- [ ] **AC4:** Given each exit-code table, when it is compared with the `exit` statements of the script the command runs, then every reachable code is listed and no unreachable one is.
- [ ] **AC5:** Given `loomwright/commands/review-pr.md`, `loomwright/commands/backlog.md` and `loomwright/commands/pr-postmortem.md`, when a user reads each, then a `## Troubleshooting` section lists three failure messages the command prints and the action for each.
- [ ] **AC6:** Given the branch, when `bash scripts/check-doc-currency.sh` runs, then it passes.

## Executable Acceptance
- corpus-task: doc-currency-green

## Touched-file invariants
- **`loomwright/docs/prompt-token-budgets.json`** — keep: the row shape `{"budget": N, "measured": M, "note": "…"}`; update only the six touched command rows under `.commands`; mirror: the same six rows in `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets"; pinned by: `scripts/check-token-budget.sh` (fails closed on a mismatch).

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Exit-code tables on three command pages | AC1–AC4 | 3 modify | agent-output | LAUNCHABLE |
| 2 | Troubleshooting sections on three command pages | AC5 | 3 modify | agent-output | LAUNCHABLE |
| 3 | Budgets and changelog fragment | AC6 | 2 modify, 1 create | agent-output | BLOCKED (by #1, #2) |

### File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| exit codes | `loomwright/commands/janitor.md` (44), `loomwright/commands/handoff.md` (54), `loomwright/commands/obsidian.md` (61) | — | HIGH |
| troubleshooting | `loomwright/commands/review-pr.md` (71), `loomwright/commands/backlog.md` (73), `loomwright/commands/pr-postmortem.md` (79) | — | HIGH |
| budgets + release | `loomwright/docs/prompt-token-budgets.json` (93), `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (1051 — the budget mirror rows it already owns) | `changelog.d/fixture-small-commands-exit-codes.md` | HIGH |

### File Overlap Detection

| Group A | Group B | Overlapping Files | Serialization Required |
|---------|---------|-------------------|----------------------|
| Subtask 1 | Subtask 2 | none | NO |
| Subtask 1 | Subtask 3 | none | YES (3 re-measures 1's pages) |
| Subtask 2 | Subtask 3 | none | YES (3 re-measures 2's pages) |

## Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/commands/janitor.md", name: "## Exit codes"}
  - {kind: "symbol", path: "loomwright/commands/handoff.md", name: "## Exit codes"}
  - {kind: "symbol", path: "loomwright/commands/obsidian.md", name: "## Exit codes"}
requires: []
lanes:
  - "loomwright/commands/janitor.md"
  - "loomwright/commands/handoff.md"
  - "loomwright/commands/obsidian.md"
external_requires: []

# Subtask 2
provides:
  - {kind: "symbol", path: "loomwright/commands/review-pr.md", name: "## Troubleshooting"}
  - {kind: "symbol", path: "loomwright/commands/backlog.md", name: "## Troubleshooting"}
  - {kind: "symbol", path: "loomwright/commands/pr-postmortem.md", name: "## Troubleshooting"}
requires: []
lanes:
  - "loomwright/commands/review-pr.md"
  - "loomwright/commands/backlog.md"
  - "loomwright/commands/pr-postmortem.md"
external_requires: []

# Subtask 3
provides:
  - {kind: "symbol", path: "loomwright/docs/prompt-token-budgets.json", name: "janitor"}
  - {kind: "file", path: "changelog.d/fixture-small-commands-exit-codes.md"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/commands/janitor.md", name: "## Exit codes"}
  - {from: "2", kind: "symbol", path: "loomwright/commands/review-pr.md", name: "## Troubleshooting"}
lanes:
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "changelog.d/fixture-small-commands-exit-codes.md"
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──┐
            ├──→ Subtask 3
Subtask 2 ──┘
```

### Batch Plan
- **Batch 1:** Subtask 1, Subtask 2 (parallel — zero file overlap)
- **Batch 2:** Subtask 3
- **Recommended workers:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/agent-output/SKILL.md` |
| 2 | `skills/agent-output/SKILL.md` |
| 3 | `skills/agent-output/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| A table drifts from its script when the script later adds an exit code | LOW | AC4 compares each table with the script's `exit` statements at authoring time |
| The six command pages grow past their token budgets | LOW | Subtask 3 re-measures the six rows (measured + ~10%) |

## Configuration
- **Workers:** 2
- **Mode:** parallel
- **Estimated batches:** 2
- **Split reason:** genuine-parallelism

## Handoff
```
/supervisor job: .supervisor/jobs/pending/fixture-small-commands-exit-codes.md
```
