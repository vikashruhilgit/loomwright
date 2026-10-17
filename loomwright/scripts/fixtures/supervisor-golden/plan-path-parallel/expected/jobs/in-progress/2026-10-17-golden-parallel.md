# Supervisor Job: Golden parallel

## Environment
- **Base commit:** <SHA>

## Task
**Goal:** Golden parallel.

## Acceptance Criteria
- [ ] AC1 — the first criterion
- [ ] AC2 — the second criterion

## Configuration
- **Workers:** 3
- **Mode:** parallel

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1a | API layer | AC1 | 4 modify | `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 1b | UI layer | AC2 | 5 modify | `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 1c | Wiring | AC1, AC2 | 3 modify | `skills/unit-testing/SKILL.md` | BLOCKED (by 1a, 1b) |

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-17-golden-parallel.md
```
