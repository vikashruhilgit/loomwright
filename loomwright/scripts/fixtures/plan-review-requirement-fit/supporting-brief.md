# Supervisor Job: Exit-code tables for /janitor, /handoff and /obsidian

## Environment
- **Project:** ai-agent-manager (Loomwright plugin repo)
- **Source requirement:** .supervisor/requirements/fixture-small-commands-exit-codes.md
- **Base commit:** 0000000000000000000000000000000000000000

## Task
**Goal:** Each of `/janitor`, `/handoff` and `/obsidian` documents its exit codes in an `## Exit codes` table on its own command page, matching the script it runs.

**Problem Statement:** A user who sees a non-zero exit from one of these three commands has to open the script behind it (`janitor-report.sh`, `build-handoff.sh`, `build-vault.sh`) to learn what the code means.

**Non-goals (from the requirement):** no exit code or script changes; no `## Exit codes` section on any other command.

## Acceptance Criteria
- [ ] **AC1:** Given `loomwright/commands/janitor.md`, when a user reads it, then an `## Exit codes` table lists each exit code `/janitor` can return and what it means.
- [ ] **AC2:** Given `loomwright/commands/handoff.md`, when a user reads it, then an `## Exit codes` table lists each exit code `/handoff` can return and what it means.
- [ ] **AC3:** Given `loomwright/commands/obsidian.md`, when a user reads it, then an `## Exit codes` table lists each exit code `/obsidian` can return and what it means.
- [ ] **AC4:** Given each table, when it is compared with the `exit` statements of the script the command runs, then every reachable code is listed and no unreachable one is.
- [ ] **AC5:** Given the branch, when `bash scripts/check-doc-currency.sh` runs, then it passes.
- [ ] **AC6:** Given the branch, when `bash loomwright/scripts/test-command-exit-codes.sh` runs, then it passes, and it fails when a table row is deleted.
- [ ] **AC7:** Given the branch, when `bash scripts/check-token-budget.sh` runs, then it passes, and `changelog.d/fixture-small-commands-exit-codes.md` exists.

## Executable Acceptance
- corpus-task: doc-currency-green

## Touched-file invariants
- **`loomwright/docs/prompt-token-budgets.json`** — keep: the row shape `{"budget": N, "measured": M, "note": "…"}`; update only the `janitor`, `handoff` and `obsidian` rows under `.commands`; mirror: the same three rows in `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets"; pinned by: `scripts/check-token-budget.sh` (fails closed on a mismatch).

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-command-exit-codes.sh` — each table lists every code its script returns | delete the `0` row of the `## Exit codes` table in `loomwright/commands/handoff.md` |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Exit-code tables on three command pages | AC1–AC5 | 3 modify | agent-output | LAUNCHABLE |
| 2 | Test for the exit-code tables | AC6 | 3 create | unit-testing | LAUNCHABLE |
| 3 | Budgets and changelog fragment | AC7 | 2 modify, 1 create | agent-output | BLOCKED (by #1) |

### File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| commands | `loomwright/commands/janitor.md` (44), `loomwright/commands/handoff.md` (54), `loomwright/commands/obsidian.md` (61) | — | HIGH |
| tests | — | `loomwright/scripts/test-command-exit-codes.sh`, `loomwright/scripts/fixtures/command-exit-codes/README.md`, `loomwright/scripts/fixtures/command-exit-codes/scripts.tsv` — a new test module | HIGH |
| budgets + release | `loomwright/docs/prompt-token-budgets.json` (93), `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (1051 — the budget mirror rows it already owns) | `changelog.d/fixture-small-commands-exit-codes.md` | HIGH |

### File Overlap Detection

| Group A | Group B | Overlapping Files | Serialization Required |
|---------|---------|-------------------|----------------------|
| Subtask 1 | Subtask 2 | none | NO |
| Subtask 1 | Subtask 3 | none | YES (3 re-measures 1's pages) |
| Subtask 2 | Subtask 3 | none | NO |

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
  - {kind: "file", path: "loomwright/scripts/test-command-exit-codes.sh"}
  - {kind: "file", path: "loomwright/scripts/fixtures/command-exit-codes/README.md"}
  - {kind: "file", path: "loomwright/scripts/fixtures/command-exit-codes/scripts.tsv"}
requires: []
lanes:
  - "loomwright/scripts/test-command-exit-codes.sh"
  - "loomwright/scripts/fixtures/command-exit-codes/**"
external_requires: []

# Subtask 3
provides:
  - {kind: "symbol", path: "loomwright/docs/prompt-token-budgets.json", name: "janitor"}
  - {kind: "file", path: "changelog.d/fixture-small-commands-exit-codes.md"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/commands/janitor.md", name: "## Exit codes"}
lanes:
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "changelog.d/fixture-small-commands-exit-codes.md"
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 3
Subtask 2 (independent)
```

### Batch Plan
- **Batch 1:** Subtask 1, Subtask 2 (parallel — zero file overlap)
- **Batch 2:** Subtask 3
- **Recommended workers:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/agent-output/SKILL.md` |
| 2 | `skills/unit-testing/SKILL.md` |
| 3 | `skills/agent-output/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| A table drifts from its script when the script later adds an exit code | LOW | Subtask 2's test compares each table with the script's `exit` statements on every CI run |
| Subtask 2's test is written before Subtask 1's tables exist | LOW | It reads the table shape AC1–AC3 define; it is run against the merged result in Batch 2 |
| The three command pages grow past their token budgets | LOW | Subtask 3 re-measures the three rows (measured + ~10%) |

## Configuration
- **Workers:** 2
- **Mode:** parallel
- **Estimated batches:** 2
- **Split reason:** genuine-parallelism

## Handoff
```
/supervisor job: .supervisor/jobs/pending/fixture-small-commands-exit-codes.md
```
