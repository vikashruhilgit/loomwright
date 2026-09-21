# Supervisor Job: Robustness polish — doc-currency gate blind spot + 2 format-twin-delta notes

> Three small, low-risk, NON-ENGINE polish items batched into one PR (anti-rebloat: don't spin three tiny PRs).
> **Sequencing:** #28 has now MERGED and `main` advanced to **v14.13.0** (#29 notifications also landed) —
> branch from **current `main` (v14.13.0)**; version → **v14.14.0**. (The prior #28 gate is satisfied.)
> No agent prompt / hook / engine file is touched.

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager (plugin's own repo)
- **CLAUDE.md:** ✓ Found, fresh
- **Git:** branch `main` (v14.13.0); `git pull` to current before running.
- **GitHub CLI:** ✓ Authenticated · **Worktrees:** none orphaned
- **Blockers:** 0 | **Warnings:** 0 (#28 merged; ready to run from main)
- **legacy_brief:** false

## Task
**Goal:** Land three independently-verified robustness/polish fixes surfaced by review:
1. **Doc-currency gate blind spot** — `scripts/check-doc-currency.sh` scans `Slash commands (N)` / `N slash commands` but not the `N entry points` phrasing (`CLAUDE.md:30`), so that count surface can drift with CI green. Add a gate pattern for it.
2. **`format-twin-delta.sh` note A (latent float gap)** — `is_int` rejects floats, but the schema permits `benchmark_value`/`benchmark_delta` to be `number` (floats). No present impact (the only producer emits integer counts). Document the constraint near `is_int`.
3. **`format-twin-delta.sh` note B (violations fallback)** — a non-numeric `--violations` silently renders `(0 violations)`, which under `advisory_violations` produces the self-contradictory `conformance ADVISORY_VIOLATIONS (0 violations)`. Omit the count when it isn't a valid integer, so genuine-zero stays distinguishable from unparseable.

## Acceptance Criteria
- [ ] **Gate hardening:** `scripts/check-doc-currency.sh` gains a command-count pattern matching the `N entry points` phrasing (e.g. `[0-9]+ entry points`), so a stale entry-points count fails the gate. The gate still passes on the current tree (`CLAUDE.md:30` is already `15 entry points`).
- [ ] **Note A:** a comment near `format-twin-delta.sh`'s `is_int` (line ~84) states "integer-valued metrics only (today's producer emits integer counts); widen to accept a single decimal point if a float-valued metric is ever introduced — the downstream sign logic is already string-based and float-safe." No behavior change.
- [ ] **Note B:** the conformance segment shows `(N violations)` **only when `--violations` is a valid integer** (including genuine `0`); when it's null/non-numeric the parenthetical is **omitted** (never fabricated as `0`). So `advisory_violations` + unparseable → `Twin: conformance ADVISORY_VIOLATIONS` (no contradictory count); `pass` + `0` → `Twin: conformance PASS (0 violations)` unchanged.
- [ ] **Tests updated:** `test-format-twin-delta.sh` assertions move from `(0 violations)` to the omitted-count form for BOTH the non-numeric `--violations` case (line ~93) AND the **omitted `--violations` case** (line ~64, conformance present with no violations flag); a genuine `--violations 0` case asserts `(0 violations)`; an `advisory_violations` + unparseable case asserts no `(0 violations)`. Self-test stays green (≥ prior 29 assertions).
- [ ] **Anti-rebloat + currency:** no new command/agent/hook/skill (counts stay 13/15/50/19); version → v14.14.0; CHANGELOG entry; `check-doc-currency.sh` + `validate-version.sh` pass.

## Subtask Structure

### ST1 — doc-currency gate hardening  [no deps]
**Files:** `scripts/check-doc-currency.sh` (modify, repo-root).
**Work:** Add a command-count check for the `N entry points` phrasing next to the existing patterns at lines ~124-125 (`check_count '[0-9]+ entry points' "$COMMANDS" "command-count"`). Confirm the gate still passes on the current tree and would FAIL a deliberately-stale `entry points` count. (No self-test file — the gate is its own test; verify by running it.)
```yaml
provides:
  - {kind: capability, path: scripts/check-doc-currency.sh, name: entry_points_gate}
requires: []
```

### ST2 — `format-twin-delta.sh` robustness (notes A + B) + tests  [no deps]
**Files:** `ai-agent-manager-plugin/scripts/format-twin-delta.sh` (modify), `ai-agent-manager-plugin/scripts/test-format-twin-delta.sh` (modify).
**Work:** (A) add the integer-only comment near `is_int` (no behavior change). (B) change the conformance-segment logic (line ~150) so `(N violations)` is emitted only when `is_int "$F_VIOLATIONS"`, else omit the parenthetical. Update the test assertions for non-numeric `--violations` (→ no parenthetical), keep/confirm `--violations 0` → `(0 violations)`, add an `advisory_violations` + unparseable case asserting no `(0 violations)`. Self-test green (≥ prior 29 assertions).
```yaml
provides:
  - {kind: file, path: ai-agent-manager-plugin/scripts/format-twin-delta.sh, name: delta_robustness}
  - {kind: file, path: ai-agent-manager-plugin/scripts/test-format-twin-delta.sh, name: delta_tests}
requires: []
```

### ST3 — docs, version, currency  [dep ST1-2]
**Files:** `ai-agent-manager-plugin/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CLAUDE.md`, `CHANGELOG.md` (modify).
**Work:** version → v14.14.0; CHANGELOG entry; CLAUDE.md banner rotation; **verify `CLAUDE.md:30` entry-points count = authoritative (15); fix if stale** (now covered by ST1's gate pattern). Counts unchanged (no count-string edits). Run both gates from repo root → pass.
```yaml
provides:
  - {kind: capability, path: CHANGELOG.md, name: release_notes}
requires:
  - {kind: capability, name: entry_points_gate, from: ST1}
  - {kind: file, name: delta_robustness, from: ST2}
```

## Parallelism Analysis
- **Batch 1:** ST1 ∥ ST2 (disjoint: `check-doc-currency.sh` vs `format-twin-delta.sh`+test)
- **Batch 2:** ST3 (docs/version — after both)
- **Recommended workers:** 2

## Skill References
- **ST1:** `skills/quality-checklist/SKILL.md`, `skills/claude-md-validation/SKILL.md`
- **ST2:** `skills/quality-checklist/SKILL.md`
- **ST3:** `skills/claude-md-validation/SKILL.md`, `skills/quality-checklist/SKILL.md`

## Risk Assessment
| Risk | Severity | Source | Mitigation |
|---|---|---|---|
| Behavior change to a shipped script (note B) | LOW | scope | Defensive-only edge (real pipeline always supplies an int count); covered by updated self-test; advisory line, non-gating |
| Version/doc conflict with #28 | LOW (resolved) | sequencing | #28 merged; branch from current main (v14.13.0); bump to v14.14.0 |
| Gate pattern too broad (false positives on "entry points" prose) | LOW | ST1 | Scope the regex to the count phrasing; confirm gate passes on current tree |
| Anti-rebloat | LOW | CLAUDE.md | No new command/agent/hook/skill; no engine file touched |

## Configuration
- **Mode:** parallel (2 workers) · **Cost:** default · **Branch:** `feature/polish-gate-and-delta`
- **References:** `scripts/check-doc-currency.sh:124-125` (existing count patterns), `ai-agent-manager-plugin/scripts/format-twin-delta.sh:84,150` (is_int + violations fallback), `docs/RESULT_SCHEMAS.md:711-712` (benchmark_value/delta typed `number|null`), the v14.12.0 review notes.

## Handoff
```
# #28 is merged; from current main (v14.13.0):
git pull
/supervisor job: .supervisor/jobs/pending/2026-06-05-polish-gate-and-delta.md --base-branch main
```

## Outcome
- **Status:** completed
- **Completed:** 2026-06-06T09:14:05Z
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/30
- **Branch:** feature/polish-gate-and-delta
- **Files changed:** 9 (3 ST scripts/tests + 6 docs/manifests)
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0 (review PASSED on first integration pass; no fixes needed)
- **Twin signal:** Twin: conformance ADVISORY_VIOLATIONS (1 violations) · benchmark system-twin-selftest 4
- **Twin note:** the 1 advisory violation was the pre-existing format-twin-delta.sh contract's now-stale "falls back to 0" behavioral_spec — intentionally changed by note B; the Phase 4.5 builder refreshed that contract. Advisory only; never gated the PR.
- **Summary:** Landed 3 NON-ENGINE polish fixes (doc-currency entry-points gate pattern; format-twin-delta note A comment + note B violations-omit behavior + tests; v14.14.0 docs/version). Both gates green, self-test 32/0, integration review PASS.
