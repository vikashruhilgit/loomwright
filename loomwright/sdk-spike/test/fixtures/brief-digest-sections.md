# Supervisor Job: digest section-shape fixture (sdk-spike + context-digest test fixture)

Trimmed/synthesized to match the REAL, measured shape of Launch Pad briefs (2026-07-31 corpus
sweep of 73 briefs: `## File Impact Map` appears in only 10/73; `**Tech Stack:**`/
`**Architecture:**` bold lines appear in 0/73). This fixture deliberately carries NEITHER of
those, so it exercises `build-context-digest.sh`'s fallback sourcing:
  - File Impact Map falls back to `## Subtask Structure` + `### File Overlap Matrix`
  - Conventions falls back to `## Environment` + `## Skill References`

Consumed by both `loomwright/scripts/test-context-digest.sh` (digest builder) and
`loomwright/sdk-spike/test/digest-lanes.test.sh` (brief parser) — a shared fixture keeps the two
suites from drifting on what "a real brief shape" means.

## Environment
- **Project:** /fixture/not-a-real-repo
- **CLAUDE.md:** ✓ Found (fixture)
- **Git:** clean, branch: main
- **Blockers:** 0 | **Warnings:** 0

## Task
**Goal:** Fixture-only — exercises digest section fallback sourcing, not a real job.

## Subtask Structure

| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | Producer | 1 modify | LAUNCHABLE |
| 2 | Consumer | 1 modify | BLOCKED (by #1) |

### Subtask contracts

```yaml
# Subtask 1 — Producer (LAUNCHABLE)
provides:
  - {kind: "file", path: "src/producer.ts"}
  - {kind: "symbol", path: "src/producer.ts", name: "ProducerGuard"}
requires: []
lanes:
  - "src/producer.ts"

# Subtask 2 — Consumer (BLOCKED by #1)
provides:
  - {kind: "file", path: "src/consumer.ts"}
requires:
  - {from: "1", kind: "file", path: "src/producer.ts"}
  - {from: "1", kind: "symbol", path: "src/producer.ts", name: "ProducerGuard"}
lanes:
  - "src/consumer.ts"
```

## Parallelism Analysis

### File Overlap Matrix

| | 1 | 2 |
|---|---|---|
| **1** | — | none |
| **2** | none | — |

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/supervisor-readiness/SKILL.md` |
| 2 | `skills/async-orchestration/SKILL.md` |

## Configuration
- Suggested branch: feature/fixture-digest-sections
