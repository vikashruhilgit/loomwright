# Supervisor Job: Worker rules — honest limits, no self-promotion, shared services read-only

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: automate-hardening-2026-09-22 (worktree; the run's isolation branch, base main @ 0b1975e)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/harness-port/01-worker-rules.md

## Feasibility (optional — Launch Pad v10.3+)

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Markdown agent prompt edit, Python validator rule, bash test cases, JSON budget config — all match the plugin's existing tech stack; no new tooling needed. |
| 2 | Dependency Availability | GO | No new external dependency. Uses existing python3 stdlib (validate-worker-result.py) and bash/jq test harness already present. |
| 3 | Architecture Fit | GO | Directly mirrors the `out_of_lane` (rule 9) / `deviations` (rule 10) precedent already established in WORKER_RESULT — same additive, non-schema-bumping, presence-gated pattern. |
| 4 | Scope vs Supervisor Capability | GO | Requirement explicitly frames this as "ONE edit, ONE budget raise" (decision H1) — fits the single-agent default; no genuine-parallelism/file-conflict/context-bound reason to split. |
| 5 | Hard Blockers | GO | No migration framework, no credentials, no missing modules. |

**Overall Verdict:** GO

## Task
**Goal:** Add three terse, generic rules to `agents/worker.md` (honest limits via `not_verified`, no self-promotion of follow-up work, shared-local-services read-only discipline), extend `WORKER_RESULT` with the optional `not_verified[]` field, validate its shape in `validate-worker-result.py`, add `subtask_ordinal` to the worker spawn contract, and raise the worker token budget once to cover all three rules.

**Problem Statement:**
`loomwright/agents/worker.md` currently has no instruction to (a) name what it could not verify, (b) refrain from stamping its own follow-up work as ready for a queue, or (c) treat shared local services as read-only when running in parallel. Each is a small rule, but the worker prompt has only narrow headroom against its declared token budget, so bundling all three into one PR with one budget raise avoids three separate CI-failing PRs (decision H1 in the source requirement's cross-queue amendment).

## Acceptance Criteria
- [ ] Given an armed worker whose diff affects a surface it did not observe running (a rendered route/view, a CLI path, a consumer of a changed contract), when it finishes, then it emits one `not_verified` item `{surface, reason}` per such surface — and when it verified everything, it omits the field entirely (never `not_verified: []`).
- [ ] Given a worker that creates a follow-up requirement/story file, when it writes that file, then the file carries `## Status: proposed` (or the tracker's "not ready" marker) and is written to a location the intake does not read as ready (e.g. a `proposed/` subfolder).
- [ ] Given a worker whose spawn prompt carries a `Shared local services:` line, when it would reset/seed/migrate/truncate/write one of those services, then it skips that action and reports it via a `not_verified` item instead; if the line names a `<PORT_ENV>`, the worker sets it to `<base> + subtask_ordinal` for any server it starts, and starts nothing that binds a port the line lists when no `<PORT_ENV>` is named.
- [ ] `RESULT_SCHEMAS.md` §WORKER_RESULT documents `not_verified: object[]` as optional/additive (schema_version stays 2), item shape `{surface: string, reason: string}`, "absent by default; empty list MUST be serialised as absent" — mirroring the `out_of_lane`/`deviations` precedent's documentation style.
- [ ] `validate-worker-result.py` gains a new rule (the next number after the live last rule — currently **rule 11**, since rule 10 is already `deviations` from six-phase-loop-gaps/01) that, WHEN PRESENT, requires `not_verified` to be a list of dicts each with non-empty string `surface` and `reason`; `null`, a non-list, or a malformed item blocks with a named reason; absence is accepted at any schema_version. Block output uses the documented `{"decision":"block","reason":…}` shape.
- [ ] `test-result-validators.sh` (the actual shared test file for this validator — the source requirement's "existing test file for this validator" resolves to this file, not a per-validator file) gains present-valid / present-malformed (blocks) / present-null (blocks) / absent (accepted) cases for the new rule, PLUS a mutation control that deletes the new rule and asserts the malformed case then FAILS (mirroring the rule-10 `deviations` mutation control already in this file).
- [ ] `skills/async-orchestration/SKILL.md` Part 2 worker spawn contract gains `subtask_ordinal: <1-based position in the brief's subtask list>` on every worker spawn (parallel, sequential, Single-Agent paths) — name is `subtask_ordinal`, never `subtask_index` (that name is already used for a different field, the compact ids/titles/deps list).
- [ ] `bash scripts/check-token-budget.sh` is green after exactly ONE `worker` budget raise (live-measured + ~10% headroom, with a one-line justification note); the JSON value in `prompt-token-budgets.json` equals the mirror cell in `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" (the gate's own cross-check).
- [ ] `grep -c 'not_verified' loomwright/agents/worker.md` ≥ 2; `grep -c 'Status: proposed' loomwright/agents/worker.md` = 1; `grep -c 'subtask_ordinal' loomwright/agents/worker.md loomwright/skills/async-orchestration/SKILL.md` ≥ 2 (combined).
- [ ] `grep -rn 'subtask_index' loomwright/` introduces zero NEW hits (compare against `git show origin/main:loomwright/agents/worker.md` — the existing use of `subtask_index` elsewhere in the plugin, if any, is untouched).
- [ ] `grep -nE 'localhost|127\.0\.0\.1|:[0-9]{4}\b|postgres|mysql|redis|docker' loomwright/agents/worker.md` introduces zero NEW hits vs `git show origin/main:loomwright/agents/worker.md` (portability — the rule names `<service>`/`<PORT_ENV>` generically, no product/tool names).
- [ ] `scripts/check-contract-parity.sh`'s WORKER_RESULT MANIFEST row gains `not_verified` alongside the existing `out_of_lane,deviations` (Launch Pad addition beyond the literal requirement text — see Risk Assessment; the manifest row is a field-presence/pin-drift check that both prior optional-field additions updated, and the field it lists must include `not_verified` to be validated the same way).
- [ ] CHANGELOG.md gains one paragraph; `plugin.json` + `marketplace.json` version bumps from 15.94.0 to 15.95.0 (patch — additive, non-breaking); README.md/CLAUDE.md are NOT touched (memory: `release-surfaces-readme-claude-md-no-longer-bump`).
- [ ] Full test loop (`loomwright/scripts/test-*.sh` + root `scripts/test-*.sh` + `scripts/check-vendor-coupling.sh` + `scripts/check-doc-currency.sh` + `scripts/check-token-budget.sh` + `scripts/check-contract-parity.sh`) green.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Worker honest-limits/no-self-promotion/shared-services rules + not_verified schema + validator rule 11 + subtask_ordinal + one budget raise | all | 10 modify, 0 create | quality-checklist, agent-output | LAUNCHABLE |

```yaml
# Subtask 1 — worker rules + not_verified schema + validator + spawn contract + budget raise (LAUNCHABLE)
provides:
  - {kind: "symbol", path: "loomwright/agents/worker.md", name: "not_verified"}
  - {kind: "symbol", path: "loomwright/agents/worker.md", name: "Status: proposed"}
  - {kind: "symbol", path: "loomwright/agents/worker.md", name: "subtask_ordinal"}
  - {kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "not_verified"}
  - {kind: "symbol", path: "loomwright/scripts/validate-worker-result.py", name: "REASON_NOT_VERIFIED_SHAPE"}
  - {kind: "symbol", path: "loomwright/scripts/test-result-validators.sh", name: "rule 11"}
  - {kind: "symbol", path: "loomwright/skills/async-orchestration/SKILL.md", name: "subtask_ordinal"}
  - {kind: "symbol", path: "loomwright/docs/prompt-token-budgets.json", name: "worker"}
  - {kind: "symbol", path: "loomwright/docs/ARCHITECTURE_CONTRACTS.md", name: "worker"}
  - {kind: "symbol", path: "scripts/check-contract-parity.sh", name: "not_verified"}
requires: []
lanes:
  - "loomwright/agents/worker.md"
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/scripts/validate-worker-result.py"
  - "loomwright/scripts/test-result-validators.sh"
  - "loomwright/skills/async-orchestration/SKILL.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "scripts/check-contract-parity.sh"
  - "CHANGELOG.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 (single subtask, no split — decision H1: "ONE edit, ONE budget raise")
```

### File Overlap Matrix
N/A — single subtask, no sibling to overlap with.

### Batch Plan
- **Batch 1:** Subtask 1
- **Recommended workers:** 1
- **Estimated batches:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/quality-checklist/SKILL.md`, `skills/agent-output/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Requirement's "Verified premises" cite a stale `check-token-budget.sh` measurement (`worker 5876/5905`, 29 headroom, from commit `05823bf`) — the requirement's own cross-queue amendment note anticipated this drift. | LOW | Launch Pad re-ran the check live: current worker budget is **6781/7459 (678 headroom)** — six-phase-loop-gaps/01 and /02 already raised it along the way. Worker must re-measure again post-edit and raise from THAT live number + ~10%, not from either stale figure. |
| Requirement's "rule (10)" validator-numbering premise is stale — rule 10 is already taken by `deviations` (six-phase-loop-gaps/01, PR #257). | LOW | Confirmed live: highest existing rule in `validate-worker-result.py` is (10) `deviations`. The new `not_verified` rule must be numbered **(11)**, matching the file's own next-number convention (§"Cross-queue amendment" note (a) already flagged this as expected drift). |
| The source requirement's Scope does not explicitly mention `scripts/check-contract-parity.sh`'s WORKER_RESULT MANIFEST row, but both prior optional-field additions (`out_of_lane`, `deviations`) updated it in their own PRs, and RESULT_SCHEMAS.md's own field docs cite that manifest as the enforcement mechanism for "validated when present." | LOW | Added as an explicit acceptance criterion (Launch Pad scope augmentation, not a silent addition) — add `not_verified` to the MANIFEST row alongside `out_of_lane,deviations`, matching precedent. `bash scripts/check-contract-parity.sh` currently passes without it (the gate validates only fields it's told to check, so this is a consistency improvement, not a currently-failing gate) — the augmentation is precedent-following, not fixing a live break. |
| `not_verified` is a NEW, PRESENCE-GATED optional field on a schema_version-2 struct that's already accreted two prior optional fields (`out_of_lane`, `deviations`) without a version bump — a third addition without care could blur whether schema_version 2 has become an unstable moving target. | LOW | Same precedent both prior additions already established (additive, non-breaking, no version bump) — RESULT_SCHEMAS.md's own schema_version note already documents "v1 accepted for the v12.0.0 transition window" as the only version-sensitive boundary; this item does not touch that boundary. |
| Portability constraint (no product/tool/port names in worker.md) is easy to violate accidentally when writing the shared-local-services rule (c), since concrete examples are the natural way to explain "reset/seed/migrate/truncate". | MEDIUM | Acceptance criteria include an explicit zero-new-hits grep for `localhost\|127.0.0.1\|:[0-9]{4}\b\|postgres\|mysql\|redis\|docker` against `origin/main`'s current worker.md — worker must use placeholders (`<service>`, `<PORT_ENV>`) exclusively, matching the source requirement's own explicit instruction. |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-23-harness-port-01-worker-rules.md
```
