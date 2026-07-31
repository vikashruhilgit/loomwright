# Supervisor Job: positional (id-less) contracts layout (sdk-spike test fixture)

Trimmed from a real archived brief (`.supervisor/jobs/done/2026-06-14-requirement-closeout-loop.md`)
— gitignored, not present in a fresh clone, hence this committed fixture. Covers the POSITIONAL
FALLBACK: no umbrella heading, no per-subtask markdown heading, no `subtask_N:`/`# Subtask N`/
`S<N>:` id marker anywhere — each subtask's own `\`\`\`yaml` fence carries a bare `provides:`/
`requires:` block with NO id of any kind. The id is implied purely by POSITION, matching the
Subtask Structure table's row order (bold prose like "**Subtask 1 — ...**" is present for human
readability only; the parser does not read it).

## Subtask Structure

| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | Producer (id-less) | 1 modify | LAUNCHABLE |
| 2 | Consumer (id-less) | 1 modify | BLOCKED (by #1) |

**Subtask 1 — Producer:**
- Some prose description with no machine-readable id marker.

```yaml
provides:
  - {kind: symbol, path: src/producer.ts, name: 'produced thing'}
requires: []
```

**Subtask 2 — Consumer:**
- References subtask 1's output by an explicit `from: 1` (positional binding only affects WHICH
  subtask a bare block belongs to — `from:` references inside items are unaffected).

```yaml
provides: []
requires:
  - {kind: symbol, path: src/producer.ts, name: 'produced thing', from: 1}
```

## Configuration
- Suggested branch: feature/fixture-positional-no-id
