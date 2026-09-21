# Supervisor Job: check-token-budget.sh — CI-enforced per-agent prompt token budgets

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main (fast-forwarded past PR #100)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/token-economy/02-token-budget-ci-gate.md

## Task
**Problem Statement:** 14 agent prompts × 41 skills accrete words every release and nothing pushes back — prompt inventory weight grows unmeasured, and each spawn pays for it. Make prompt weight a mechanically enforced contract (the doc-currency-gate pattern applied to prompt bytes).

**Goal:** Add a repo-root CI validator `scripts/check-token-budget.sh` that fails CLOSED (non-zero exit) when any agent's effective spawn-time prompt weight (agent `.md` + every frontmatter-preloaded skill's `SKILL.md`) exceeds a declared per-agent budget. Budgets live in ONE authoritative machine-readable source with a documented override path. Follows the existing repo-root `scripts/check-*.sh` CI-validator pattern (offline, deterministic, bash-3.2 safe).

## Acceptance Criteria
- [ ] Given the current repo, when `bash scripts/check-token-budget.sh` runs, then it exits 0 with a per-agent proxy-token report (initial budgets set from measured current values + ~10% headroom).
- [ ] Given a fixture agent inflated past budget, when the self-test runs, then the gate exits 1 with a readable per-agent breach report.
- [ ] Given the budget table, then it contains all 14 agents, is machine-readable (`loomwright/docs/prompt-token-budgets.json`), is mirrored/rendered into `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets", and documents the raise rule (raise in the same PR that breaches, with a one-line justification).
- [ ] Given any surfaced count, then it is labeled "proxy tokens", never an exact Anthropic count; script header + docs state plainly the ratchet controls prompt inventory growth, not live tokenizer inflation.
- [ ] Given macOS bash 3.2, when `bash scripts/test-check-token-budget.sh` runs offline, then it passes and uses no GNU-only stat/sed/date flags; covers pass / breach / missing-frontmatter cases.
- [ ] Given CI, then the gate + self-test are wired into `.github/workflows/ci.yml` alongside the existing validators, and all existing validators still pass.

## Subtask Structure

| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | Token-budget gate + budget table + self-test + CI wiring + version bump | 1 create (gate), 1 create (test), 1 create (json), 3 modify (ARCHITECTURE_CONTRACTS.md, ci.yml, plugin.json/marketplace.json + CHANGELOG) | LAUNCHABLE |

### Subtask 1 — contract
```yaml
provides:
  - {kind: file, path: scripts/check-token-budget.sh}
  - {kind: file, path: scripts/test-check-token-budget.sh}
  - {kind: file, path: loomwright/docs/prompt-token-budgets.json}
  - {kind: section, path: "loomwright/docs/ARCHITECTURE_CONTRACTS.md#Prompt Token Budgets"}
  - {kind: ci-step, path: ".github/workflows/ci.yml#check-token-budget"}
requires: []
```

## Skill References
None — pure bash CI validator; no framework/stackpack skills are injected for this task. All grounding (frontmatter `skills:` parsing, proxy-count rule, bash-3.2 / stat-flavor portability) is in `## Implementation Notes` and `## Risk Assessment`.

## Parallelism Analysis
- Single subtask — fast-path, no worktrees, no Execute Manager.
- Recommended workers: 1

## File Impact Map (verified paths)
- **create** `scripts/check-token-budget.sh` — repo-root CI validator (mirror `scripts/check-doc-currency.sh` conventions: offline, `bash`, exit non-zero on breach; NO `${var//…}` on large strings per bash-3.2 pattern-sub wedge memory).
- **create** `scripts/test-check-token-budget.sh` — self-test with temp fixture agent/skill dirs (pass / breach / missing-frontmatter); no GNU-only `stat -c` / `sed -i` / `date -d` (macOS-green ≠ CI-green memory: prefer portable forms, validate numeric before arithmetic).
- **create** `loomwright/docs/prompt-token-budgets.json` — machine-readable authoritative budget set: `{ "proxy": "bytes/4", "agents": { "<name>": { "budget": N, "measured": M, "note": "..." } }, "raise_rule": "..." }`.
- **modify** `loomwright/docs/ARCHITECTURE_CONTRACTS.md` — new §"Prompt Token Budgets" rendering/mirroring the JSON table + the raise rule + the proxy-not-tokenizer caveat. Do NOT introduce scannable stale count-claims.
- **modify** `.github/workflows/ci.yml` — new step running `bash scripts/test-check-token-budget.sh` then `bash scripts/check-token-budget.sh` (model on the `check-skills-index-sync.sh` self-test-then-gate step).
- **modify** `loomwright/.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` — minor version bump 15.9.0 → 15.10.0, description version string updated IN PLACE (no new version clause appended). Add `CHANGELOG.md` entry.

## Implementation Notes (grounding — read before coding)
- **Skill-set resolution:** parse the frontmatter `skills:` YAML list from each `loomwright/agents/*.md` (the authoritative source — NOT the CLAUDE.md Skills Preloading table, which is a doc mirror). Each list item `- <name>` maps to `loomwright/skills/<name>/SKILL.md`. Agents with no `skills:` block contribute only their own `.md`.
- **Proxy count:** deterministic offline `bytes/4` (or wordcount-calibrated factor), labeled "proxy" everywhere. Never call count_tokens.
- **A missing preloaded SKILL.md** (frontmatter names a skill whose file is absent) is a gate error (readable message) — this is the "missing-frontmatter"/broken-reference case the self-test must cover.
- **Budgets:** initialize each agent's budget = measured proxy value × 1.10 (rounded), so nothing fails at introduction — a ratchet, not a diet.
- **Counts UNCHANGED (14/21/41/22)** — this change adds only repo-root `scripts/` files + docs; no agent/command/skill/hook added. Doc-currency gate must stay green (grep old values if any counts are restated in the new section).

## Constraints / invariants
- Gate fails CLOSED (non-zero exit). It belongs in CI, not hooks.json — so no `|| true`.
- Self-test must be added to CI so it actually runs (repo-root `scripts/test-*.sh` is NOT covered by the plugin-internal `loomwright/scripts/test-*.sh` self-test loop — wire it explicitly in its own ci.yml step).
- Bash 3.2 safe; portable stat/sed/date; validate numeric before arithmetic under `set -u`.

## Out of scope
Actually shrinking any agent prompt; non-frontmatter-preloaded skills; command/skill docs not injected at spawn time; live count_tokens.

## Configuration
- Base Branch: main
- Fast-path: single subtask (no worktree)

## Risk Assessment
| Risk | Severity | Mitigation |
|------|----------|------------|
| Fragile frontmatter YAML parsing (multi-line `skills:` list) | MEDIUM | awk state-machine over the `---`-delimited frontmatter; self-test covers a multi-skill agent + a no-skills agent |
| bash 3.2 pattern-sub wedge on large prompt strings | MEDIUM | never use `${var//…}`; use `wc -c` for byte counts, not in-shell string ops |
| macOS-green ≠ CI-green (stat/date flavor) | MEDIUM | avoid GNU-only flags; `wc -c`-based sizing is portable; self-test asserted offline |
| New ARCHITECTURE_CONTRACTS section introduces stale count-claim | LOW | render numbers from the JSON; no restated 14/21/41/22 literals in the new section |

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-07-17-token-budget-ci-gate.md

## Outcome
- **Status:** completed (RECONCILED POST-HOC 2026-07-21 — the original run's completion tail never executed, so this block is derived from ground truth, not from a live heal record)
- **Evidence:** shipped as PR #101 "feat(ci): per-agent prompt token-budget ratchet (v15.10.0)", MERGED 2026-07-18T09:01:22Z, commit 7ff5114
- **Acceptance criteria verified 2026-07-21 against origin/main:** gate `scripts/check-token-budget.sh` exits 0; `scripts/test-check-token-budget.sh` passes; `loomwright/docs/prompt-token-budgets.json` covers all 14 agents; CI wiring present (.github/workflows/ci.yml:38-39); ARCHITECTURE_CONTRACTS.md §"Prompt Token Budgets" present
- **heal_loop_ran:** unknown (no session record survived — do NOT read this as a heal PASS)
- **rubric_score:** not recorded
