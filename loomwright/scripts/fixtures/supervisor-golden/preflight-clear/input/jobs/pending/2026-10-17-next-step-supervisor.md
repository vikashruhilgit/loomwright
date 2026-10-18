# Supervisor Job: next-step driver for Supervisor Phases 0–4 (supervisor-next-step.sh)

## Environment
- **Project:** automate-2026-10-15-163325/L11 (lane L11 clone of the loomwright repo)
- **Source requirement:** .supervisor/requirements/automate-speed/11-next-step-supervisor.md
- **Base commit:** a8819a38100d77fbeddc2ff1a56963e91f172a5d

## Task
**Goal:** Add `loomwright/scripts/supervisor-next-step.sh`, a step driver that owns Supervisor's deterministic Phase 0–4 sequencing and bookkeeping.

## Acceptance Criteria
- [ ] AC1 — golden cases byte-identical
- [ ] AC2 — the driver never writes state.md
- [ ] AC3 — publish only after FINALIZE point 5
- [ ] AC4 — the PR-base self-verify with its retry
- [ ] AC5 — asks carry the catalog labels and the can't-ask status
- [ ] AC6 — test-loop-inventory.sh passes
- [ ] AC7 — the default read path shrinks
- [ ] AC8 — pinned-prose suites stay green
- [ ] AC9 — the merge surface is unchanged

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 3
- **Base Branch:** main
- **Split reason:** context-bound

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Driver skeleton + Phases 0, 1, 1.5, 2 steps, harness, golden cases for those phases, schema section, changelog fragment | AC1 (Phase 0–2 cases), AC2, AC5 (Phase 1.5 ask), AC9, Validation 2b | 1 modify + driver/test/fixtures/fragment create | `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 2 | Driver Phase 3 Supervisor-side routing + Phase 4 FINALIZE steps | AC1 (Phase 3–4 cases), AC3, AC4, AC5 | driver/test/fixtures modify + evidence create | `skills/unit-testing/SKILL.md` | BLOCKED (by #1) |
| 3 | Prose move, per-phase pointers, `--legacy` row, inventory re-home | AC6, AC7, AC8, Validation 1 | ~8 modify + 1 create | `skills/unit-testing/SKILL.md` | BLOCKED (by #2) |

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-17-next-step-supervisor.md
```
