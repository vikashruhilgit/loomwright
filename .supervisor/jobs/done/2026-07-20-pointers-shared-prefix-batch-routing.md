# Supervisor Job: Pointers-not-payloads + shared stable prefix + async downpricing

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh, v15.12.0)
- **Git:** clean, branch: main (eedd3ac)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/token-economy/05-pointers-shared-prefix-batch-routing.md

## Task
**Goal:** Convert spawn prompts / inter-agent handoffs to pass pointers (paths + bounded summaries) instead of pasted bodies; give all 14 agent .md files one byte-identical shared leading block with a fail-CLOSED CI check; route plugin-invoked async analysis surfaces to the cheapest adequate model tier via new Cost Profiles rows. Zero semantic change to any agent's behavior contract.

**HONEST CACHE EXPECTATION (frame the PR this way, never overclaim):** the shared prefix does NOT buy cross-agent cache hits (tools render before the system prompt; each agent's `tools:`/`disallowedTools:` set diverges at position 0). Its value is consistency, dedup, and a smaller prompt inventory. The real cache win is SAME-ROLE respawns (Phase 3 worker waves, heal-loop reviewer/fix-worker spawns) via volatile-last ordering.

## Acceptance Criteria
- [ ] Audit table in the PR: every Task-spawn / handoff site pasting >~1k chars of file-backed content enumerated; each converted (path + ≤200-char summary + "Read only the sections you need") or documented inline as a justified exception.
- [ ] All 14 agents/*.md open with the byte-identical shared block (order: shared → role → preloaded skills → volatile); a new `scripts/check-shared-prefix.sh` proves byte-identity, fails CLOSED (no `|| true`), and its self-test proves failure on a 1-char drift.
- [ ] `scripts/check-token-budget.sh` passes; any budget raises land in the SAME PR in `loomwright/docs/prompt-token-budgets.json` + the ARCHITECTURE_CONTRACTS.md mirror, each with a one-line justification.
- [ ] Cost Profiles table (`ARCHITECTURE_CONTRACTS.md` §Cost Profiles) gains async-analysis rows (verified surfaces only — `/dreaming` reflection spawns qualify; `/pr-postmortem` and `/insights` spawn no models today and must be recorded as such, not given rows) with defaults + override preserved; no correctness-critical role (code-reviewer, red-team as voter) downgraded.
- [ ] Optional additive `shared_prefix: true` marker on the token-ledger JSONL line (same namespace discipline as `orientation_source`); fail-SAFE.
- [ ] Batch-API routing recorded as a roadmap note in the PR/docs, not code.
- [ ] PR states the ledger-based measurement plan for same-role respawn cache-read share and states plainly that cross-agent reuse is structurally zero.
- [ ] check-doc-currency.sh, check-command-sync.sh, check-skills-index-sync.sh, validate-version.sh, check-token-budget.sh + the new prefix check all pass.
- [ ] Version bump 15.12.0 → 15.13.0 (plugin.json + marketplace.json + CLAUDE.md banner + CHANGELOG entry; description version string updated in place, no clause appended).

## Feasibility (Phase 2.5): GO
- All work is in-repo markdown/bash/JSON; strong precedent for every piece (CI validators exist; `orientation_source` shows the additive-ledger-marker pattern; Cost Profiles table exists).
- CAUTION (fed to risks): the shared block will breach thin token budgets by design — the gate's raise rule must be applied in-PR.

## Subtask Structure

| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | Pointer audit + conversion of paste sites | ~5 modify (skills/async-orchestration, skills/self-heal-advisory, agents/supervisor.md, agents/execute-manager.md, commands/dreaming.md as found) — MEDIUM confidence, audit-driven | LAUNCHABLE |
| 2 | Shared stable prefix + check-shared-prefix.sh + budget raises | 14 agents/*.md modify, 1 canonical source create, 2 scripts create (check + self-test), prompt-token-budgets.json + ARCHITECTURE_CONTRACTS.md modify, CI wiring — HIGH confidence | BLOCKED (by #1 — same agent files) |
| 3 | Cost Profiles async rows + ledger marker + version bump/doc currency | ARCHITECTURE_CONTRACTS.md, scripts/emit-token-ledger.sh (+ self-test), plugin.json, marketplace.json, CLAUDE.md, CHANGELOG.md — HIGH confidence | BLOCKED (by #2 — shares ARCHITECTURE_CONTRACTS.md and final counts/version surfaces) |

### Subtask contracts

```yaml
subtask_1:
  provides:
    - {kind: file, path: loomwright/docs/POINTER_AUDIT.md}          # the audit table as an addressable artifact (also summarized in PR body)
    - {kind: file, path: loomwright/skills/async-orchestration/SKILL.md}
    - {kind: file, path: loomwright/skills/self-heal-advisory/SKILL.md}
    - {kind: file, path: loomwright/agents/supervisor.md}
    - {kind: file, path: loomwright/agents/execute-manager.md}
    - {kind: file, path: loomwright/commands/dreaming.md}
  requires: []
subtask_2:
  provides:
    - {kind: file, path: loomwright/docs/shared-agent-prefix.md}    # canonical shared-block source (docs/ placement — agents/ would trip check-token-budget.sh:120 and check-doc-currency.sh:31)
    - {kind: file, path: scripts/check-shared-prefix.sh}
    - {kind: file, path: scripts/test-check-shared-prefix.sh}
    - {kind: file, path: loomwright/docs/prompt-token-budgets.json}
    - {kind: file, path: loomwright/docs/ARCHITECTURE_CONTRACTS.md} # budget mirror rows
  requires:
    - {from: "subtask_1", kind: file, path: loomwright/agents/supervisor.md}
    - {from: "subtask_1", kind: file, path: loomwright/agents/execute-manager.md}
subtask_3:
  provides:
    - {kind: file, path: loomwright/docs/ARCHITECTURE_CONTRACTS.md} # Cost Profiles async rows
    - {kind: file, path: loomwright/scripts/emit-token-ledger.sh}
    - {kind: file, path: loomwright/.claude-plugin/plugin.json}
    - {kind: file, path: .claude-plugin/marketplace.json}
    - {kind: file, path: CLAUDE.md}
    - {kind: file, path: CHANGELOG.md}
  requires:
    - {from: "subtask_2", kind: file, path: loomwright/docs/prompt-token-budgets.json}
    - {from: "subtask_2", kind: file, path: loomwright/docs/ARCHITECTURE_CONTRACTS.md}
```

**Note:** the canonical source deliberately lives under `docs/` — an `agents/`-resident `.md` would be counted as a 15th agent by `scripts/check-token-budget.sh` (agents/*.md loop, fail-CLOSED on missing budget) and `scripts/check-doc-currency.sh` (agent count), per Plan Review attempt-2 evidence. The CI check reads the canonical path from one place.

## Skill References
- Subtask 1: `quality-checklist` (gate discipline for prompt-file edits; "prompt is program" trace)
- Subtask 2: `quality-checklist`; no stackpack skill applies (bash validator work) — none needed beyond it
- Subtask 3: `commit` (conventional release commit), `quality-checklist`

## Parallelism Analysis
- Sequential only (file overlap on agents/*.md and ARCHITECTURE_CONTRACTS.md). Batches: [1] → [2] → [3]. Recommended workers: 1 (`--sequential` semantics; fast-path per subtask).

## Configuration
- Base Branch: main
- Max workers: 1 (sequential)
- Heal iterations: 3 (default)

## Risk Assessment
| Risk | Severity | Mitigation | Source |
|---|---|---|---|
| Token-budget gate breach from shared block | MEDIUM (expected-by-design) | Apply the gate's raise rule in the same PR, net of removed duplicated prose | Feasibility (Phase 2.5) |
| Byte-identity drift between canonical source and 14 copies | HIGH if unchecked | check-shared-prefix.sh fails CLOSED; self-test proves 1-char-drift detection | Requirement |
| Overclaiming cache wins in PR prose | MEDIUM | Honest-cache-expectation block above is normative for PR body | Requirement |
| Doc-currency unscanned surfaces drift (Cost Profiles enumerations) | LOW | Grep old values repo-wide per CLAUDE.md discipline | CLAUDE.md |
| macOS-green ≠ CI-green (bash 3.2 / GNU) | MEDIUM | New scripts follow existing validator conventions; offline self-test; avoid stat/date -i portability traps | Memory |

## Outcomes Rubric
- `loomwright/docs/POINTER_AUDIT.md` exists in the diff, contains an audit table with ≥1 converted site or every site justified as exception, and carries the honest-cache framing (cross-agent reuse structurally zero) plus a Batch-API roadmap note.
- All 14 `loomwright/agents/*.md` files in the diff open with the byte-identical shared block sourced from the canonical file.
- `scripts/check-shared-prefix.sh` and `scripts/test-check-shared-prefix.sh` exist in the diff; the check contains no `|| true`; the self-test includes a 1-char-drift failure case.
- `loomwright/docs/prompt-token-budgets.json` raises (if any) appear in the same diff with matching ARCHITECTURE_CONTRACTS.md mirror rows.
- ARCHITECTURE_CONTRACTS.md §Cost Profiles gains async-analysis rows in the diff; the code-reviewer and red-team voter rows remain non-downgraded.
- `CHANGELOG.md` contains a 15.13.0 entry and `plugin.json`/`marketplace.json`/CLAUDE.md carry 15.13.0 consistently in the diff.

*(Prose note, non-rubric: CI validators passing and the PR-body summary are verified at self-heal/drain time, not from the diff.)*

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-07-20-pointers-shared-prefix-batch-routing.md

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/104
- **Branch:** feature/pointers-shared-prefix
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1 (holistic PASS; 3 per-subtask reviews: FAIL→fix→PASS, PASS, PASS)
- **Heal remaining issues:** 0 BLOCKING/HIGH (residual MEDIUM/LOW folded in 80a68de)
- **Rubric score:** 6/6
- **Until-mergeable dispatched:** false  # default dispatch suppressed by /automate (auto_review=false); engine owns the drain
