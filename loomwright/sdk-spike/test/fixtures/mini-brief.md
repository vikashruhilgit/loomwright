# Supervisor Job: Mini fixture brief (sdk-spike self-test only)

## Environment
- **Project:** (fixture — not a real job; consumed only by loomwright/sdk-spike/test/self-test.sh in --dry-run mode)

## Task
**Goal:** Exercise the sdk-spike runner's brief parser, LAUNCHABLE/BLOCKED computation, wave scheduling, and dry-run query seam. Two subtasks: one launchable, one blocked on it.

## Subtask Structure
| # | Title | Est. files | Status |
|---|---|---|---|
| 1 | Create example module | 1 create | LAUNCHABLE |
| 2 | Consume example module | 1 modify | BLOCKED (by #1) |

### Subtask contracts
```yaml
subtask_1:
  provides:
    - {kind: file, path: src/example/created.ts}
    - {kind: symbol, path: src/example/created.ts, name: createdExample}
  requires: []
subtask_2:
  provides:
    - {kind: file, path: src/example/consumer.ts}
  requires:
    - {from: 1, kind: file, path: src/example/created.ts}  # same-file ordering
```

## Configuration
- Base Branch: main
- Suggested branch: feature/sdk-spike-fixture
- Max workers: 2
