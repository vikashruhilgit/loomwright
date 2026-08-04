# Supervisor-Ready Brief: legacy alpha ids + 10-subtask ordering regression

> REGRESSION FIXTURE for `normalizeSubtaskIds` (loomwright/sdk-spike/src/runner.ts). Extends
> `launchpad-brief.md`'s 4-row `1a,1b,2,10` shape to a full 11-subtask brief so the natural-sort
> guard is exercised against a REAL 10+ subtask count, not just an id whose numeral happens to be
> "10". Asserts (see `test/self-test.sh`):
>   1. injective   — `1a` and `1b` normalize to two DISTINCT ids, never both to `1`
>   2. numeric     — every normalized id matches the pinned plain-numeric scheme
>   3. ordered     — normalized id N == the subtask's 1-based natural-sort position (so `10`
>                     really does sort after `9`, not lexicographically before `2`)
>   4. zero dangling — every `from:` resolves to a real (post-normalization) subtask id

## Subtask Structure

| # | Title | Est. files | Status |
|---|-------|-----------|--------|
| 1a | shared base | 1 | LAUNCHABLE |
| 1b | base variant | 1 | BLOCKED by #1a |
| 2 | step two | 1 | BLOCKED by #1b |
| 3 | step three | 1 | BLOCKED by #2 |
| 4 | step four | 1 | BLOCKED by #3 |
| 5 | step five | 1 | BLOCKED by #4 |
| 6 | step six | 1 | BLOCKED by #5 |
| 7 | step seven | 1 | BLOCKED by #6 |
| 8 | step eight | 1 | BLOCKED by #7 |
| 9 | step nine | 1 | BLOCKED by #8 |
| 10 | step ten (natural-sort guard) | 1 | BLOCKED by #9 |

### Subtask contracts

```yaml
# Subtask 1a — shared base (LAUNCHABLE)
provides:
  - {kind: "file", path: "src/base.ts"}
requires: []

# Subtask 1b — base variant (BLOCKED by #1a)
provides:
  - {kind: "file", path: "src/base-variant.ts"}
requires:
  - {from: "1a", kind: "file", path: "src/base.ts"}

# Subtask 2 — step two (BLOCKED by #1b)
provides:
  - {kind: "file", path: "src/step2.ts"}
requires:
  - S1b

# Subtask 3 — step three (BLOCKED by #2)
provides:
  - {kind: "file", path: "src/step3.ts"}
requires:
  - {from: 2, kind: "file", path: "src/step2.ts"}

# Subtask 4 — step four (BLOCKED by #3)
provides:
  - {kind: "file", path: "src/step4.ts"}
requires:
  - {from: 3, kind: "file", path: "src/step3.ts"}

# Subtask 5 — step five (BLOCKED by #4)
provides:
  - {kind: "file", path: "src/step5.ts"}
requires:
  - {from: 4, kind: "file", path: "src/step4.ts"}

# Subtask 6 — step six (BLOCKED by #5)
provides:
  - {kind: "file", path: "src/step6.ts"}
requires:
  - {from: 5, kind: "file", path: "src/step5.ts"}

# Subtask 7 — step seven (BLOCKED by #6)
provides:
  - {kind: "file", path: "src/step7.ts"}
requires:
  - {from: 6, kind: "file", path: "src/step6.ts"}

# Subtask 8 — step eight (BLOCKED by #7)
provides:
  - {kind: "file", path: "src/step8.ts"}
requires:
  - {from: 7, kind: "file", path: "src/step7.ts"}

# Subtask 9 — step nine (BLOCKED by #8)
provides:
  - {kind: "file", path: "src/step9.ts"}
requires:
  - {from: 8, kind: "file", path: "src/step8.ts"}

# Subtask 10 — step ten (natural-sort guard) (BLOCKED by #9)
provides:
  - {kind: "file", path: "src/step10.ts"}
requires:
  - {from: 9, kind: "file", path: "src/step9.ts"}
```

Suggested branch: feature/legacy-alpha-ids-regression
