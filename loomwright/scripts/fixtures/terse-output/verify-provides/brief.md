# Supervisor Job: terse-output verify-provides fixture

Committed fixture for test-verify-provides.sh: the `--verbose` goldens beside it were captured by
running the PRE-change verify-provides.sh from this directory with `--root root`.

### Subtask Contracts

```yaml
# Subtask 1 — two present, two missing
provides:
  - {kind: "file", path: "src/a.ts"}
  - {kind: "symbol", path: "src/a.ts", name: "Sym"}
  - {kind: "symbol", path: "src/a.ts", name: "Gone"}
  - {kind: "file", path: "src/absent.ts"}
requires: []

# Subtask 2 — all present
provides:
  - {kind: "file", path: "src/a.ts"}
  - {kind: "symbol", path: "src/a.ts", name: "Sym"}
requires: []
```
