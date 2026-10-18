# Supervisor Job: Name an unreadable rules helper apart from unresolved rules at Phase 4.5

## Environment
- **Project:** ai-agent-manager (Loomwright plugin repo)
- **Base commit:** 0000000000000000000000000000000000000000

## Task
**Goal:** Phase 4.5's fail-CLOSED rules leg escalates with ONE reason, `rules_gate_unresolved`, for two different causes: rules the gate could not resolve, and a rules helper whose output could not be read at all. Give the second cause its own heal reason, `rules_gate_unreadable`, so the outcome tells a broken helper apart from unresolved rules.

**Problem Statement:** A human reading `**Heal reason:** rules_gate_unresolved` cannot tell whether to fix a rule or fix the helper. Part 1 already normalises every unaffirmed helper output to `unreadable`, so the signal exists; only the reason is shared.

## Acceptance Criteria
- [ ] **AC1:** Given an iteration whose `rules.verdict == "unreadable"`, when the fail-CLOSED leg runs, then it records `record_decision(phase: SELF_HEAL, decision: "rules_gate_unreadable", …)` and the PR comment names `rules_gate_unreadable`; an `unresolved` verdict still records `rules_gate_unresolved`.
- [ ] **AC2:** Given the brief Outcome written on ESCALATED, when the cause is an unreadable helper, then `**Heal reason:**` reads `rules_gate_unreadable`.
- [ ] **AC3:** Given `loomwright/scripts/test-rules-gate-seams.sh`, when it runs, then a new pin P11 holds the AC1 decision line and its generated mutant M11 fails.

## Touched-file invariants

> Grounded at base `0000000000000000000000000000000000000000`.

- **`loomwright/scripts/test-rules-gate-seams.sh`** — keep: every pin already listed on its `PINS="` line, plus the new one; keep the gated mutation controls.
- **`loomwright/skills/self-heal-advisory/SKILL.md`** — keep: the leg's allow-list complement `if rules.verdict not in RULES_PASSABLE and rules.verdict != "fail":` (never a deny-list) and `record_decision(phase: SELF_HEAL, decision: "rules_gate_unresolved"` for the `unresolved` case; pinned by: `loomwright/scripts/test-rules-gate-seams.sh`.

## Closed enumerations touched

> Sibling grep at base `0000000000000000000000000000000000000000`: `grep -rnF 'rules_gate_unresolved' --exclude=CHANGELOG.md loomwright` → 8 hits in 2 files.

- **`rules_gate_unreadable`** (sibling: `rules_gate_unresolved`) — must be named in:
  - `loomwright/skills/self-heal-advisory/completion-tail.md` — the closed `**Heal reason:** {needs_human|` list in the completion tail — extend.
  - `loomwright/skills/self-heal-advisory/completion-tail.md` — the dismissed-findings `round=<n>` paragraph's list of loop breaks that skip the round increment (`also pre-increment`) — extend.
  - `loomwright/skills/self-heal-advisory/SKILL.md` — Part 1's `**The verdict decides; the line reports.**` paragraph, which names the reason every unaffirmed verdict escalates with — extend.
  - `loomwright/skills/self-heal-advisory/SKILL.md` — the fail-CLOSED leg's `record_decision` and PR-comment lines (2 hits) — extend: the leg branches on `unreadable`.
  - `loomwright/skills/self-heal-advisory/completion-tail.md` — step 7's `**Rules-check replay line` paragraph (`already escalated with`) — extend.
  - `loomwright/skills/review-heal/SKILL.md` — the drain's escalation comment and its ESCALATED description (2 hits) — extend: the drain names the same two reasons.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-rules-gate-seams.sh` — P11 | delete the `record_decision(phase: SELF_HEAL, decision: "rules_gate_unreadable"` line in `loomwright/skills/self-heal-advisory/SKILL.md` |
| `loomwright/scripts/test-rules-gate-seams.sh` — P11 | flip the new branch's `rules.verdict == "unreadable"` to `rules.verdict == "unresolved"` in `loomwright/skills/self-heal-advisory/SKILL.md` |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Split the unreadable reason + pin | AC1–AC3 | 2 modify, 0 create | self-heal-advisory | LAUNCHABLE |

### File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| phase45 | `loomwright/skills/self-heal-advisory/SKILL.md`, `loomwright/skills/self-heal-advisory/completion-tail.md` | — | HIGH |
| tests | `loomwright/scripts/test-rules-gate-seams.sh` | — | HIGH |

## Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/skills/self-heal-advisory/SKILL.md", name: "rules_gate_unreadable"}
  - {kind: "symbol", path: "loomwright/scripts/test-rules-gate-seams.sh", name: "rules_gate_unreadable"}
requires: []
lanes:
  - "loomwright/skills/self-heal-advisory/SKILL.md"
  - "loomwright/skills/self-heal-advisory/completion-tail.md"
  - "loomwright/scripts/test-rules-gate-seams.sh"
external_requires: []
```

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/self-heal-advisory/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| The split turns the allow-list complement into a deny-list of named verdicts | HIGH | Branch on `unreadable` INSIDE the existing complement leg; every other unaffirmed verdict keeps `rules_gate_unresolved` |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1

## Handoff
```
/supervisor job: .supervisor/jobs/pending/fixture-unreadable-reason.md
```
