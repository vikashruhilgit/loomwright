# Supervisor Job: A countable rules `fail` that turns `unstamped` mid-loop escalates instead of passing silently

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes-v2/v2-b
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (installed plugin 15.119.2 runs this workflow; the repo is at 15.120.0 — the edited skills are the repo copies under `loomwright/`)
- **Source requirement:** .supervisor/requirements/automate-followups/18-fail-to-unstamped-escalates.md
- **Base commit:** 6a048be267c5526c23f2fdc5ee00841f85157f89

## Feasibility (optional — Launch Pad v10.3+)

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Prose-as-program skill edits (markdown pseudocode) plus one bash static pin test, same shape as automate-followups/07 |
| 2 | Dependency Availability | GO | `rules-gate-verdict.sh` already emits `countable` on an `unstamped` verdict (its `--list-gateable` step runs before both `unstamped` exits); no new helper output is needed |
| 3 | Architecture Fit | GO | Mirrors existing cross-iteration accumulators: `heal_dismissed` / `fixer_deviations` (Phase 4.5) and `checks_ever_fixed` (drain) |
| 4 | Scope vs Supervisor Capability | GO | ~7 files, one coherent change; below the Decomposition Threshold |
| 5 | Hard Blockers | GO | None. `review-pr` token budget has ~961 tokens headroom — see Risk Assessment |

**Overall Verdict:** GO

## Task
**Goal:** Within ONE Phase 4.5 self-heal loop and ONE `--until-mergeable` drain, remember every gate-countable rule id seen failing; a later round whose rules verdict is `unstamped` while that memory is non-empty ESCALATES (named `rules_fail_then_unstamped`) instead of passing — owner decision Option A (2026-10-01).

**Problem Statement:**
A human merging after `/supervisor` or `/review-pr` needs a stamped countable `must`-rule failure to stay visible because the fixer can "clear" it by editing a file the rule `binds`.
Currently, a round that FAILs a countable check synthesises a BLOCKING finding; the fix worker then edits a bound file, the stamp hash moves, the next round reads `unstamped` — which is in `RULES_PASSABLE` — and Phase 4.5 reaches PASS / the drain reaches READY with only a `rules_check: unstamped` line. Nothing records the earlier FAIL. Under `/automate` the merge gate still parks `rules_unstamped`, but outside it nothing warns.
Success looks like: the fail→unstamped transition escalates at both seams with a named reason, while a rule NEVER seen failing in that loop stays advisory when `unstamped` (owner decision D3 otherwise unchanged).

## Acceptance Criteria
- [ ] AC1 — Given Phase 4.5's review-and-fix loop (`loomwright/skills/self-heal-advisory/SKILL.md` Part 2), when the loop initialises its accumulators, then a `rules_failed_seen` set is initialised beside `heal_dismissed`, and every iteration whose `rules.verdict == "fail"` adds each failing id that is in `rules.countable` to it (the same countable filter `rule_findings` uses), persisted with a `record_decision` the same way `fixer_deviations` is, so it survives resume/compaction.
- [ ] AC2 — Given an iteration whose `rules.verdict == "unstamped"` and `rules_failed_seen` is non-empty, when Part 2 branches on the verdict, then — BEFORE the `if iter_decision == PASS:` exit — `heal_decision = ESCALATED`, `record_decision(phase: SELF_HEAL, decision: "rules_fail_then_unstamped", …)` naming the remembered ids, a PR comment names `rules_fail_then_unstamped`, the ids and the rules_check_line, `heal_remaining_issues` counts at least `len(rules_failed_seen)`, and the loop breaks (terminal, like `rules_gate_unresolved`). An `unstamped` verdict with an EMPTY `rules_failed_seen` remains in `RULES_PASSABLE` and is byte-identical to today.
- [ ] AC3 — Given the drain (`loomwright/skills/review-heal/SKILL.md` §U4), when a round's rules verdict is `fail`, then each countable failing id is added to a cross-round `rules_failed_seen` (initialised before `loop:` with the other cross-round variables such as `checks_ever_fixed`); and when a later round reads `unstamped` with a non-empty `rules_failed_seen`, then `rules_escalates` is true (decision ESCALATED, `termination_reason` left UNSET exactly as for `rules_gate_unresolved`, comment names `rules_fail_then_unstamped`) — at BOTH drain sites: the main `rules_escalates` computation AND the sub-floor `rules_after` re-read (so a remembered fail can never reach `sub_floor_converged` READY).
- [ ] AC4 — Given both skills' prose, when the change lands, then the comments/bullets that currently say `unstamped` ⇒ "BYTE-IDENTICAL" / "advisory at the drain" are amended to state the one exception (a rule that FAILED earlier in the same loop), and every existing `test-rules-gate-seams.sh` pin needle (P1–P8) still matches verbatim.
- [ ] AC5 — Given the restated D3 invariant, when the change lands, then `CLAUDE.md` §"Failure-Mode Invariants", `loomwright/skills/rules/SKILL.md` §8.1, and `loomwright/docs/RESULT_SCHEMAS.md`'s `rules_gate` description ("READY implies `ok`, `none`, `unstamped` or `cmd_disabled` …") each carry the fail→unstamped exception in one sentence — the P5 CLAUDE.md needle stays verbatim.
- [ ] AC6 — Given `loomwright/scripts/test-rules-gate-seams.sh`, when it runs, then new pins P9 (self-heal-advisory: the `rules_failed_seen` accumulation and the `rules_fail_then_unstamped` escalation leg) and P10 (review-heal: the accumulation and the `rules_failed_seen` term inside `rules_escalates` and the sub-floor re-read) are in `PINS`, their generated M9/M10 mutants fail, the unmutated positive controls pass, and the whole script exits 0.
- [ ] AC7 — Given the repo's release convention, when the change lands, then a `changelog.d/fail-to-unstamped-escalates.md` fragment exists (no hand edit to `plugin.json`, `marketplace.json` or `CHANGELOG.md`), and `bash scripts/ci-local.sh` (which runs `check-doc-currency.sh`, `check-token-budget.sh` and every `loomwright/scripts/test-*.sh`) is green — if `review-pr`'s preloaded review-heal grows past its declared budget, the budget in `loomwright/docs/prompt-token-budgets.json` and its `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" mirror row are raised in the same change.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Remember countable fails across rounds; escalate fail→unstamped at Phase 4.5 and the drain; pin + document | all | 5 modify (+2 conditional), 1 create | `skills/rules/SKILL.md`, `skills/review-heal/SKILL.md`, `skills/self-heal-advisory/SKILL.md` | LAUNCHABLE |

### File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| phase45 | `loomwright/skills/self-heal-advisory/SKILL.md` (Part 1 §"Rules-check replay" rule bullet; Part 2 loop init, RULES GATE block, escalation leg before `if iter_decision == PASS:`) | — | HIGH |
| drain | `loomwright/skills/review-heal/SKILL.md` (§U4 `rules_gate_read` consumers, `rules_escalates`, sub-floor `rules_after` check, READY comment, loop-init variables) | — | HIGH |
| invariant docs | `CLAUDE.md`, `loomwright/skills/rules/SKILL.md` (§8.1), `loomwright/docs/RESULT_SCHEMAS.md` (`rules_gate` row/line) | — | HIGH |
| tests | `loomwright/scripts/test-rules-gate-seams.sh` (P9, P10, header comment) | — | HIGH |
| release | — | `changelog.d/fail-to-unstamped-escalates.md` | HIGH |
| budget (conditional) | `loomwright/docs/prompt-token-budgets.json`, `loomwright/docs/ARCHITECTURE_CONTRACTS.md` | — | LOW (only if `check-token-budget.sh` fails for `review-pr`) |

> **Validator-owned surfaces:** acceptance depends on `scripts/check-doc-currency.sh` and `scripts/check-token-budget.sh` (via `ci-local.sh`). Files they scan may need updates; the edited docs above are in their scan sets. `scripts/test-citation-drift.sh` fails any NEW bare unpinned `file:N` citation in committed prose — use descriptive anchors.

## Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/skills/self-heal-advisory/SKILL.md", name: "rules_failed_seen"}
  - {kind: "symbol", path: "loomwright/skills/self-heal-advisory/SKILL.md", name: "rules_fail_then_unstamped"}
  - {kind: "symbol", path: "loomwright/skills/review-heal/SKILL.md", name: "rules_failed_seen"}
  - {kind: "symbol", path: "loomwright/skills/review-heal/SKILL.md", name: "rules_fail_then_unstamped"}
  - {kind: "symbol", path: "loomwright/scripts/test-rules-gate-seams.sh", name: "rules_fail_then_unstamped"}
  - {kind: "file", path: "changelog.d/fail-to-unstamped-escalates.md"}
requires: []
lanes:
  - "loomwright/skills/self-heal-advisory/SKILL.md"
  - "loomwright/skills/review-heal/SKILL.md"
  - "loomwright/skills/rules/SKILL.md"
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/scripts/test-rules-gate-seams.sh"
  - "CLAUDE.md"
  - "changelog.d/fail-to-unstamped-escalates.md"
external_requires: []
```

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/rules/SKILL.md` (§8.1 countability, D3), `skills/review-heal/SKILL.md` §U4, `skills/self-heal-advisory/SKILL.md` Part 1 §"Rules-check replay" + Part 2 loop |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Tying `unstamped` to the specific remembered id is impossible: on `unstamped` the replay never runs, so `rules.failing` is always empty. Scoping the escalation to `rules_failed_seen ∩ rules.countable` would let a fix that ALSO drops the rule's countability (removes `binds`, demotes it) clear the fail silently | HIGH | Escalate when `rules.verdict == "unstamped"` and `rules_failed_seen` is NON-EMPTY — not intersected with the current `countable` (fail closed toward escalating; an unstamped verdict leaves every countable check unverified, so a remembered fail is never confirmed cleared). Name the remembered ids in the comment |
| The sub-floor `rules_after` re-read in the drain is a second pass path; changing only `rules_escalates` would let a remembered fail reach `sub_floor_converged` READY | HIGH | AC3 names both sites; P10 pins both |
| Existing P1–P8 needles are verbatim substrings of the lines being edited (e.g. `rules_escalates = rules.verdict not in RULES_PASSABLE and rules.verdict != "fail"`, `and rules_after.verdict in RULES_PASSABLE:`) | MEDIUM | Extend those lines by APPENDING a clause (e.g. `… != "fail" or (rules.verdict == "unstamped" and rules_failed_seen)`) so the old needle stays a prefix; run `bash loomwright/scripts/test-rules-gate-seams.sh` before committing |
| `review-pr` preloads review-heal and has ~961 tokens of budget headroom; `check-token-budget.sh` fails CI closed | MEDIUM | Keep the drain addition terse; if it still exceeds, raise the `review-pr` budget per `raise_rule` and update the ARCHITECTURE_CONTRACTS mirror row in the same change |
| `cmd_disabled` after an earlier `fail` has the same "no replay" shape | LOW | Out of scope (requirement names only `unstamped`; flipping `RULES_CHECK_NO_CMD` mid-loop requires an environment change). Record it as an honest-limit sentence in the Phase 4.5 rule bullet, do not change behaviour |
| Doc-currency / citation-drift gates on the edited prose | LOW | Descriptive anchors only; `bash scripts/ci-local.sh` before push (the ONLY pre-push test command) |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-04-fail-to-unstamped-escalates.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-10-04T08:15:03Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/372
- **Branch:** feature/automate-followups-18-fail-to-unstamped-escalates
- **Files changed:** 10
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Phase 4.5 + both drain sites remember countable fails (rules_failed_seen); a later unstamped escalates rules_fail_then_unstamped. Iteration 1 FAIL on a workflow-drift restatement (commands/rules.md) fixed in 8b53caa; iteration 2 PASS. 8 MEDIUM/LOW findings dismissed for owner decision. ground_truth 2/2 pass; rules_check: none; rules_audit: clean; risk_classification high_risk=true (skills/ paths).

## Not verified
- **Phase 4.5 / drain live fail-then-unstamped escalation path** — prose-as-program; only static pins + mutation controls exercised, no live loop run (subtask 1)
