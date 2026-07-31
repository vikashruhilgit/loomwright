# Supervisor Job: inline flow-style array contracts (sdk-spike test fixture)

Trimmed from two real archived briefs (`.supervisor/jobs/done/2026-06-19-automate-engine.md` and
`.supervisor/jobs/done/2026-07-07-script-test-gaps-and-roadmap-remainders.md`) — gitignored, not
present in a fresh clone, hence this committed fixture. Covers TWO things at once:
  - the "### Provides / Requires Schema" umbrella heading spelling (a fifth accepted spelling
    alongside "Subtask contracts" / "Provides / Requires Contracts")
  - INLINE flow-style `provides: [ {...} ]` / `requires: [ {...} ]` arrays on a single line
    (never the multi-line `- {...}` form), including a bare `S<N>:` id-key form and a
    `from: S<N>` reference that must normalize to the plain numeric id "1".

## Subtask Structure

| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | Producer | 1 create | LAUNCHABLE |
| 2 | Consumer | 1 modify | BLOCKED (by #1) |

### Provides / Requires Schema

```yaml
S1:
  provides: [{kind: file, path: loomwright/scripts/produced.sh}]
  requires: []
S2:
  provides: [{kind: file, path: loomwright/scripts/consumed.sh}]
  requires:
    - {kind: file, path: loomwright/scripts/produced.sh, from: S1}
```

## Configuration
- Suggested branch: feature/fixture-inline-array-contracts
