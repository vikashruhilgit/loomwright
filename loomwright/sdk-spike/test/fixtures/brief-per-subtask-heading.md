# Supervisor Job: per-subtask markdown heading layout (sdk-spike test fixture)

Trimmed from a real archived brief (`.supervisor/jobs/done/2026-07-30-fix7-two-review-lenses.md`)
— gitignored, not present in a fresh clone, hence this committed fixture. Covers parseBrief's
per-subtask MARKDOWN heading anchor: NO umbrella "Subtask Contracts"/"Provides / Requires
Contracts"/"Provides / Requires Schema" heading anywhere in this brief — each subtask's OWN
`### Subtask N — Title` heading is immediately followed by prose and then its OWN ```yaml fence.

## Subtask Structure

| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | Authority rule | 1 modify | LAUNCHABLE |
| 2 | Consumer A | 1 modify | BLOCKED (by #1) |

### Subtask 1 — Authority rule, the base (LAUNCHABLE)

Scope: `AGENT_GUIDELINES.md` ONLY. Add a top-level section stating the rule.

```yaml
provides:
  - {kind: "file", path: "AGENT_GUIDELINES.md"}
  - {kind: "symbol", path: "AGENT_GUIDELINES.md", name: "## Some Rule"}
requires: []
external_requires: []
```

### Subtask 2 — Consumer A (BLOCKED by #1)

Cites the rule from subtask 1 by path.

```yaml
provides:
  - {kind: "file", path: "docs/consumer-a.md"}
requires:
  - {from: "1", kind: "symbol", path: "AGENT_GUIDELINES.md", name: "## Some Rule"}
external_requires: []
```

## Configuration
- Suggested branch: feature/fixture-per-subtask-heading
