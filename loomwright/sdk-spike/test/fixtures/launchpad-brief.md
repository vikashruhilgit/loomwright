# Supervisor-Ready Brief: launchpad-shape regression

> REGRESSION FIXTURE — mirrors the SHAPE of a real Launch Pad brief, which differs from
> `mini-brief.md` (the runner's original hand-written contract) on three axes that each silently
> broke the parser. Reduced from the real 2026-07-28 `tree-and-find` brief that aborted
> FABLE_PARITY_EVAL arm 3 with **all 9 dependency edges dropped**:
>
>   1. ids carry an alpha suffix (`1a`, `1b`) — the `\d+`-only row pattern dropped those rows
>   2. subtask keys are `# Subtask 1a — …` comments, not `subtask_1:` YAML keys — so `current`
>      stayed null and every provides/requires line below was discarded
>   3. `provides:` / `requires:` sit at COLUMN 0 — the `^\s+` list-header pattern skipped them
>
> With all three unfixed the graph parsed EMPTY, every subtask looked launchable, and dependents
> spawned concurrently onto files their producers had not written yet.

## Subtask Structure

| # | Title | Est. files | Status |
|---|-------|-----------|--------|
| 1a | shared walker | 2 | LAUNCHABLE |
| 1b | adversarial fixtures | 1 | BLOCKED by #1a |
| 2 | tree subcommand | 2 | BLOCKED by #1a |
| 10 | late subtask (natural-sort guard) | 1 | BLOCKED by #2 |

### Subtask contracts

```yaml
# Subtask 1a — shared walker (LAUNCHABLE)
provides:
  - {kind: "file",   path: "Sources/DirectoryWalker.swift"}
  - {kind: "type",   path: "Sources/DirectoryWalker.swift", name: "DirectoryWalker"}
requires: []
external_requires: []

# Subtask 1b — adversarial fixtures (BLOCKED by #1a)
provides:
  - {kind: "symbol", path: "Tests/DirectoryWalkerTests.swift", name: "testCycleTerminates"}
requires:
  - {from: "1a", kind: "type", path: "Sources/DirectoryWalker.swift", name: "DirectoryWalker"}
external_requires: []

# Subtask 2 — tree subcommand (BLOCKED by #1a)
provides:
  - {kind: "file",   path: "Sources/Tree.swift"}
requires:
  - {from: "1a", kind: "type", path: "Sources/DirectoryWalker.swift", name: "DirectoryWalker"}
external_requires: []

# Subtask 10 — late subtask (BLOCKED by #2)
provides:
  - {kind: "file",   path: "Sources/Late.swift"}
requires:
  - {from: 2, kind: "file", path: "Sources/Tree.swift"}
external_requires: []
```

Suggested branch: feature/launchpad-shape
