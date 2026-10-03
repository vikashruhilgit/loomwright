# Supervisor Job: Twin inline-delta — surface the hard signal in the completion tail (Level 1)

> Scope: **Level 1 only** — print *this run's* Twin hard signal as one advisory line in the SELF_HEAL completion tail.
> **Level 2 (trend/threshold nudges like "conformance ↓ N runs → run /dreaming") is explicitly OUT OF SCOPE** — deferred
> until real run-history exists to calibrate thresholds honestly.
> **Sequencing:** run this AFTER `2026-06-05-obsidian-vault.md` merges; branch from the updated `main`; version bumps
> from whatever `/obsidian` shipped. Do NOT run in parallel with `/obsidian` (both touch version/doc surfaces).

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager (plugin's own repo)
- **CLAUDE.md:** ✓ Found, fresh (v14.10.0 at authoring; will be higher once `/obsidian` lands)
- **Git:** branch `main`; only `.claude/` untracked (unrelated). `git pull` after `/obsidian` merges, before running.
- **GitHub CLI:** ✓ Authenticated · **Worktrees:** none orphaned
- **Blockers:** 0 | **Warnings:** 1 (must run after `/obsidian` merges — see Sequencing)
- **legacy_brief:** false

## Task
**Goal:** In the Supervisor **SELF_HEAL completion tail**, emit **one advisory human-readable line** summarizing *this run's* System Twin hard signal — contract-conformance (status + violation count) and benchmark (status + value + delta) — using the values **already computed in Phase 4.5** (`SUPERVISOR_RESULT.contract_conformance` / `.benchmark_result` and the flat `session_end` fields). The line is **purely informational**: it never changes `heal_decision`, never blocks the PR, never alters control flow. The formatting lives in a **testable script** (`scripts/format-twin-delta.sh`); `supervisor.md` just calls it and prints the output (minimal engine change).

## Acceptance Criteria
- [ ] **Inline surface:** after Phase 4.5 self-heal completes, the completion tail prints a single line such as `Twin: conformance PASS (0 violations) · benchmark system-twin-selftest 6/6 (Δ +1)` built from this run's already-computed hard-signal values.
- [ ] **Advisory only (hard):** the line NEVER changes `heal_decision`, NEVER blocks the PR, NEVER alters control flow — it is a pure `echo` of `format-twin-delta.sh` output. The Supervisor result/gate behavior is byte-identical with or without this line.
- [ ] **Graceful / sparse:** when this run produced **no** Twin signal (Twin not exercised, contract absent, or fields null), the script emits a benign line (e.g. `Twin: no signal this run`) or nothing, and **always exits 0** — never errors.
- [ ] **Testable, minimal engine change:** formatting logic is in `scripts/format-twin-delta.sh` (with a self-test `scripts/test-format-twin-delta.sh` mirroring `test-system-contract.sh`); the `supervisor.md` edit is limited to *calling* the script in the completion tail and echoing its output — no new control flow.
- [ ] **Anti-rebloat + currency:** **no** new command/agent/hook/skill (scripts are uncounted — counts stay 13/14|15/50/19); version bumped; `scripts/check-doc-currency.sh` passes (no count change, version-only).

## Subtask Structure

### ST1 — `format-twin-delta.sh` + self-test  [blocks all]
**Files:** `ai-agent-manager-plugin/scripts/format-twin-delta.sh` (create), `ai-agent-manager-plugin/scripts/test-format-twin-delta.sh` (create).
**Work:** `format-twin-delta.sh` takes the hard-signal fields (`--conformance-status`, `--violations`, `--benchmark-status`, `--benchmark-value`, `--benchmark-delta`, or reads the `session_end` JSONL line) and emits one human-readable line; handles null/absent fields → `Twin: no signal this run`; always exits 0. Self-test mirrors `test-system-contract.sh`: full-signal line, null/absent → benign line, exit-0 invariants, no-arg safety.
```yaml
provides:
  - {kind: file, path: ai-agent-manager-plugin/scripts/format-twin-delta.sh, name: delta_formatter}
  - {kind: contract, path: ai-agent-manager-plugin/scripts/format-twin-delta.sh, name: delta_iface}
  - {kind: file, path: ai-agent-manager-plugin/scripts/test-format-twin-delta.sh, name: delta_selftest}
requires: []
```

### ST2 — Supervisor completion-tail wiring  [dep ST1]
**Files:** `ai-agent-manager-plugin/agents/supervisor.md` (modify).
**Work:** In the SELF_HEAL completion tail (where the hard-signal fields are already written to `SUPERVISOR_RESULT` + the `session_end` JSONL), add a step that calls `format-twin-delta.sh` with this run's hard-signal values and **echoes** the resulting line. Explicitly advisory: no change to `heal_decision`, PR creation, or any gate. Keep the edit minimal (call + echo only).
```yaml
provides:
  - {kind: capability, path: ai-agent-manager-plugin/agents/supervisor.md, name: completion_tail_delta_line}
requires:
  - {kind: file, name: delta_formatter, from: ST1}
  - {kind: contract, name: delta_iface, from: ST1}
```

### ST3 — docs, version, currency  [dep ST1-2]
**Files:** `ai-agent-manager-plugin/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CLAUDE.md`, `CHANGELOG.md` (modify).
**Work:** version bump (next minor after `/obsidian`'s); CHANGELOG entry; a one-line CLAUDE.md note under the System Twin section. **No command/agent/hook/skill count change** (scripts uncounted) — so the description count strings are untouched; only the version string moves. Confirm `scripts/check-doc-currency.sh` passes (run from repo root).
```yaml
provides:
  - {kind: capability, path: CHANGELOG.md, name: release_notes}
requires:
  - {kind: capability, name: completion_tail_delta_line, from: ST2}
  - {kind: file, name: delta_formatter, from: ST1}
```

## Parallelism Analysis
- **Batch 1:** ST1 · **Batch 2:** ST2 · **Batch 3:** ST3
- **Mode:** sequential. **Recommended workers:** 1. (Genuinely sequential — small, each step consumes the prior.)

## Skill References
- **ST1:** `skills/quality-checklist/SKILL.md`
- **ST2:** `skills/quality-checklist/SKILL.md`, `skills/state-management/SKILL.md` (completion-tail conventions)
- **ST3:** `skills/claude-md-validation/SKILL.md`, `skills/quality-checklist/SKILL.md`

## Risk Assessment
| Risk | Severity | Source | Mitigation |
|---|---|---|---|
| Touches `supervisor.md` (the engine) | MED | scope | Engine edit limited to a call+echo in the completion tail; logic isolated in a tested script; advisory-only hard AC; no control-flow change |
| Version/doc conflict with `/obsidian` | MED | sequencing | Run AFTER `/obsidian` merges; branch from updated `main`; bump version from `/obsidian`'s; never parallel |
| Line printed when there's no Twin signal | LOW | UX | Graceful AC: null/absent → `Twin: no signal this run` or nothing; always exit 0; ST1 test asserts it |
| Scope creep into Level-2 nudges | LOW | design | Level 2 explicitly OUT OF SCOPE; this brief is Level 1 (this-run surface) only |
| Anti-rebloat | LOW | CLAUDE.md | No new command/agent/hook/skill; scripts uncounted; version-only doc change |

## Configuration
- **Mode:** sequential · **Workers:** 1 · **Branch:** `feature/twin-inline-delta` · **Cost:** default
- **References:** `agents/supervisor.md` (Phase 4.5 / SELF_HEAL completion tail — where the hard-signal fields are written), `docs/RESULT_SCHEMAS.md` (`session_end` hard-signal field shape + `SUPERVISOR_RESULT.contract_conformance`/`.benchmark_result`), `scripts/run-benchmark.sh` (already computes `benchmark_result.delta`), `scripts/test-system-contract.sh` (self-test pattern).

## Handoff
```
# ONLY after 2026-06-05-obsidian-vault.md has merged; then on a fresh v14.10.0+ session:
git pull   # get /obsidian's merge
/supervisor job: .supervisor/jobs/pending/2026-06-05-twin-inline-delta.md --base-branch main
```

## Outcome
- **Status:** completed
- **Completed:** 2026-06-05T07:28:29Z
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/28
- **Branch:** feature/twin-inline-delta
- **Files changed:** 10 (8 modified + 2 new scripts)
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0
- **Heal remaining issues:** 0
- **Twin signal:** Twin: benchmark system-twin-selftest 4
- **Summary:** ST1 format-twin-delta.sh + 29-assertion self-test; ST2 supervisor.md step 6 (advisory call+echo); ST3 v14.12.0 bump + CHANGELOG/CLAUDE.md banner + README + currency. Phase 4.5 holistic review PASS; one pre-existing LOW count-drift (CLAUDE.md:30) flagged separately. doc-currency + validate-version pass.
