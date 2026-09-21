# 03 — Mechanize rules (Bet 6 Tier 1): executable checks over advisory prose

## Problem
"Self-heal PASS but CI bot finds issues" persists because nearly all enforcement is advisory prose read at seams. North star Bet 6: *"'Please follow the style guide' in a prompt is the weakest enforcement; a failing lint rule is the strongest."* Tier 1 (executable `check:` commands) is the least built-out tier — and it's the only form of teeth compatible with the nothing-gating invariant, because checks run at the EXISTING worker Step-5 verify gate and Phase 4.5, not as new gates.

## Goal
Convert every mechanizable existing rule/lesson into a runnable `check:` and make the two existing seams actually execute them.

## Scope
1. **Audit pass:** sweep `.agent/rules/` + AGENT_GUIDELINES + the recurring review findings (postmortem root-cause classes, feedback lessons like stat-flavor/set-u, nullable-required jq `has()`, grep-gate variants) and classify each as mechanizable / prose-only. Deliver the classification table in the PR.
2. **Author checks:** for each mechanizable rule, add/verify a `check:` command in its `.agent/rules/` entry (respecting rules-check.sh's existing trust boundary — unattended execution stays gated via `--no-cmd`; worker/Phase 4.5 run checks only through the sanctioned rules-check.sh path).
3. **Seam execution:** confirm (and fix where prose-only) that worker Step-5 verify and Phase 4.5 actually RUN the fast/local and full/integrated check subsets respectively, per Bet 6's (b)/(c) design; results are findings into the existing self-heal loop (auto-fix for existing-rule violations, human approval only for rule-vs-reality conflicts).
4. **Layer-fires audit (2026-07-23 amendment):** for each existing advisory/verification layer (contract conformance, ground-truth, rubric, red-team lens, rules seams), add a cheap firing-rate check to `/insights` or the invariant script — sessions where the layer was applicable vs actually ran (`skipped` = unverified, not clean; conformance ran 3/7 sessions per LESSONS). A layer that silently doesn't fire is dead weight that still costs prompt tokens.
5. **Invariant self-checks:** add repo-CI checks for 2–3 of this repo's own stated invariants that are today only grep-able prose (e.g. the single-sanctioned `gh pr merge --squash` executor grep, the `|| true`-on-blocking-gate hazard) as a `scripts/check-invariants.sh` CI step.

## Non-goals
No new gating paths, no new hooks, no severity changes to the review contract, no Tier 3 learned-conventions automation (that's item 02's loop).

## Acceptance criteria
- Classification table shipped; every mechanizable rule has a working `check:` (falsified: each check demonstrably FAILS on a seeded violation fixture).
- Worker and Phase 4.5 seam execution traced end-to-end on a fixture run (prompt-is-program: dynamic trace, not just static read).
- `check-invariants.sh` green on main, red on a seeded violation.
- Unattended-execution trust boundary unchanged (rules-check.sh --no-cmd semantics intact, tested).

## Outcomes Rubric
- Mechanizable/prose classification table complete
- Seeded-violation falsification test per authored check
- Both seams execute checks via the sanctioned path
- check-invariants.sh in CI
