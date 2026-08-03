# Supervisor Job: inline flow-style array contracts (sdk-spike test fixture)

Trimmed from two real archived briefs (`.supervisor/jobs/done/2026-06-19-automate-engine.md` and
`.supervisor/jobs/done/2026-07-07-script-test-gaps-and-roadmap-remainders.md`) — gitignored, not
present in a fresh clone, hence this committed fixture. Covers TWO things at once:
  - the "### Provides / Requires Schema" umbrella heading spelling (a fifth accepted spelling
    alongside "Subtask contracts" / "Provides / Requires Contracts")
  - INLINE flow-style `provides: [ {...} ]` / `requires: [ {...} ]` arrays on a single line
    (never the multi-line `- {...}` form), including a bare `S<N>:` id-key form and a
    `from: S<N>` reference that must normalize to the plain numeric id "1".
  - INLINE single-line `lanes: ["a", "b"]` string arrays. Lanes are plain strings, never brace
    objects, so the `{...}`-group scan used for provides/requires finds nothing in them — an
    earlier cut of the parser silently produced an EMPTY `laneGlobs` for this perfectly natural
    authoring form, and `workerPrompt` only emits lane-boundary text when `laneGlobs.length > 0`,
    so a worker spawned from an inline-authored brief received NO lane boundaries at all. This
    fixture pins that regression.

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
  lanes: ["loomwright/scripts/produced.sh", "loomwright/scripts/produced-helper.sh"]
S2:
  provides: [{kind: file, path: loomwright/scripts/consumed.sh}]
  requires:
    - {kind: file, path: loomwright/scripts/produced.sh, from: S1}
  lanes: ["loomwright/scripts/consumed.sh"]
```

## Configuration
- Suggested branch: feature/fixture-inline-array-contracts
