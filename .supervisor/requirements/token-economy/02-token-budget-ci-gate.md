# 02 — check-token-budget.sh: CI-enforced per-agent prompt token budgets

> Motivation: 14 agent prompts × 41 skills accrete words every release and nothing pushes
> back. The fattened tokenizer (Opus 4.7+ family, ~1×–1.35× vs pre-4.7) makes that
> inventory growth more expensive per spawn — but this gate measures **prompt inventory
> weight**, not tokenizer inflation. Offline proxy (`bytes/4` or calibrated word factor)
> will not track Opus vs pre-4.7 token ratios; that is environmental context for why the
> ratchet matters now. Follow the doc-currency-gate pattern: make prompt weight a
> mechanically enforced contract.

## Goal
CI fails when any agent's effective spawn-time prompt weight (agent .md + its preloaded
skills from frontmatter) exceeds a declared budget, with budgets declared in one
authoritative table and an explicit, documented override path for deliberate increases.

## Evidence
- Precedent gates: `scripts/check-doc-currency.sh`, `scripts/check-skills-index-sync.sh`,
  `scripts/check-command-sync.sh` — same repo-root `scripts/` convention, offline, exit
  non-zero on violation.
- Skills preloading table (CLAUDE.md §Skills Preloading) defines which skills are
  injected per agent; the gate must resolve the SAME set from agent frontmatter (read the
  frontmatter, not the CLAUDE.md table — the table is a doc mirror).
- No network in CI: use a deterministic offline proxy for token count (bytes/4 or a
  wordcount-calibrated factor), clearly labeled as a proxy. Do NOT call the Anthropic
  count_tokens API from the gate.

## Scope
1. **`scripts/check-token-budget.sh`** (repo-root CI validator): for each agent .md in
   `loomwright/agents/`, compute proxy-token weight of the agent prompt plus every
   frontmatter-preloaded skill's SKILL.md; compare against the budget table; print a
   per-agent report; exit 1 on any breach, 0 otherwise. Deterministic, offline, bash-3.2
   safe (memory: bash 3.2 pattern-sub wedge — avoid `${var//...}` on large strings).
2. **Budget table** in `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (new §"Prompt Token
   Budgets"): one row per agent — budget, current measured value at authoring time, and
   the rule for raising a budget (raise in the same PR that breaches it, with a one-line
   justification; the gate reads the table, so a raise is visible in diff review).
   **Preferred implementer path:** if parsing Markdown rows is fragile, keep a small
   machine-readable source of truth (e.g. `loomwright/docs/prompt-token-budgets.json` or
   adjacent) that the script reads, and have ARCHITECTURE_CONTRACTS.md render or mirror
   that table — still one authoritative budget set, still visible in PR diffs. Do not
   maintain two conflicting number sources.
3. **Self-test** `scripts/test-check-token-budget.sh`: fixture agent + skill files,
   pass/breach/missing-frontmatter cases.
4. Wire into CI alongside the existing validators (same workflow step list).
5. Set initial budgets from measured current values + ~10% headroom (no agent should
   fail at introduction) — this is a ratchet, not a diet; shrinking prompts is follow-up.

## Constraints / invariants
- The gate is a correctness gate: it fails CLOSED (non-zero exit). Per the `|| true`
  convention note in CLAUDE.md, if it is ever wired as a hook it must NOT carry `|| true`
  — but it belongs in CI, not hooks.json.
- Counts UNCHANGED (14/21/41/22). Minor version bump + CHANGELOG; description version
  string updated in place.
- Doc-currency: adding the new §Prompt Token Budgets section to ARCHITECTURE_CONTRACTS
  must not introduce scannable stale claims; grep old values repo-wide if any counts are
  restated.
- Proxy counting must be labeled as proxy everywhere it is surfaced — never present it
  as an exact Anthropic token count.

## Acceptance criteria
- [ ] `check-token-budget.sh` passes on the current repo with the initial budgets.
- [ ] Artificially inflating a fixture (self-test) or a real agent prompt past budget
      fails the gate with a readable per-agent report.
- [ ] Budget table exists in ARCHITECTURE_CONTRACTS.md (and optional machine-readable
      twin if used) with all 14 agents and the raise rule documented; labels everywhere
      say "proxy tokens," never exact Anthropic counts.
- [ ] Gate docs / script header state plainly: this ratchet controls prompt inventory
      growth, not live tokenizer inflation.
- [ ] Self-test passes offline on macOS bash 3.2 AND is free of GNU-only stat/sed/date
      flags (memory: stat-flavor set-u trap; macOS-green ≠ CI-green).
- [ ] Existing CI validators still pass.

## Test plan
`bash scripts/test-check-token-budget.sh` (offline). Run the gate against the live repo
and paste the per-agent report into the PR description.

## Out of scope
Actually shrinking any agent prompt (follow-up jobs), skills not preloaded via
frontmatter, command/skill docs not injected at spawn time, live count_tokens calls.

## Status: done
- Shipped via PR #101 (v15.10.0), merged 2026-07-18. Job record reconciled post-hoc 2026-07-21 (original completion tail never ran).
