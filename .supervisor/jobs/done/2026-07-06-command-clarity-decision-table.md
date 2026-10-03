# Supervisor Job: Command clarity — decision table + flag-table completeness audit (docs-only)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh, v15.2.0 banner)
- **Git:** clean, branch: main (up to date with origin)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 0
- **legacy_brief:** true (single-subtask — inter-subtask contracts vacuous)
- **Source requirement:** .supervisor/requirements/review-remediation/01-command-clarity.md

## Task
**Goal:** A user who is not the maintainer can answer "which command do I run?" in one screen, and every real flag in the command docs appears in its Parameters table with default + precondition. Docs-only; no behavior change.

## Acceptance Criteria
- [ ] Given a new user reads README.md, .claude-plugin/README.md, or commands/agent-help.md, when they look at the Commands section, then a "Which command?" decision table (consistent across all three; condensed in agent-help) maps: new task/goal → /launch-pad + /supervisor (or /autonomous); multi-iteration one goal with stacked PRs → /autonomous; queue of independent goals → /automate; existing PR to review-and-heal → /review-pr; review-only of a diff → /code-reviewer. Each row notes what the command does NOT do (none merge except /automate --auto-merge, opt-in).
- [ ] Given commands/supervisor.md, commands/autonomous.md, commands/automate.md, when every `--flag` in the file body is enumerated by grep, then each REAL flag of that command has a Parameters-table row with default + "only meaningful when" precondition where applicable; flags belonging to other commands/tools in prose (e.g. `--squash`, `--force`, `--event-type`, `--base`, `--json`, `--agent`) and explicitly-deferred flags (autonomous.md "Not shipped" list) are excluded with a one-line rationale in the PR body. Per-file grep proof attached to the PR description.
- [ ] Given autonomous.md, when compared to skills/autonomous-loop/SKILL.md §"Auto-forwarded flags" (EXECUTE step 1: `--base-branch` stacked+iter>1 / `--non-interactive` under fallback / `--cheap` unconditional-when-present), then the command-doc forwarded-flag documentation matches exactly, and a terminology note is added: "iteration (this command) ≈ one /launch-pad→/supervisor pass on the SAME goal; /automate's 'item' = one independent goal from a queue."
- [ ] Given automate.md, when audited, then the 5 trusted-merge conditions remain UN-restated (the `--auto-merge` row keeps: opt-in, default OFF, fail-CLOSED, authority = skill §10), and `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` still resolves to exactly the 4 sanctioned surfaces.
- [ ] Given the change, when CI runs, then check-doc-currency.sh, check-command-sync.sh, and validate-version.sh all pass; version bumped 15.2.0 → 15.2.1 (plugin.json + marketplace.json version string updated IN PLACE, description not appended to), CHANGELOG entry added, counts unchanged (14/21/57/21).

## Verified Evidence (Phase 3)
- "Which command" table confirmed ABSENT in all 3 doc surfaces (grep 2026-07-06).
- supervisor.md body-vs-table delta: `--agent` (prose, `claude --agent` — not a /supervisor flag), `--until-mergeable` (drain flag referenced in prose — needs either a row or an explicit "belongs to /review-pr; threaded via env vars" precondition note).
- autonomous.md table has 8 rows; body mentions deferred flags (`--status/--continue/--abort/--background/--auto-merge/--gate-timeout-minutes` — "Not shipped" section) and foreign flags (`--base`, `--force`, `--event-type`, `--json`, `--until-mergeable`, `--base-branch` (forwarded to supervisor), `--non-interactive` (forwarded), `--skip-preflight-sync` (interaction note)). Judgment calls documented per AC 2.
- automate.md table has 9 rows; body extras are inner-command flags (`--requirement`, `--single-iteration`, `--until-mergeable`, `--squash`).

## Subtask Structure

| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | Decision tables (README.md, .claude-plugin/README.md, commands/agent-help.md) + flag-table completeness fixes (supervisor.md, autonomous.md incl. terminology note + forwarded-set parity, automate.md) + version bump 15.2.1 + CHANGELOG | 9 modify, 0 create | LAUNCHABLE |

## Parallelism Analysis
- Single subtask (docs-only, tightly-coupled consistency requirements across files — splitting risks cross-file drift the requirement explicitly warns about).
- Batch 1: Subtask 1. Recommended workers: 1 (fast-path).

## Skills
- quality-checklist; (reference) automate-loop / autonomous-loop skills as flag authorities.

## Configuration
- base branch: main; heal iterations: default 3; docs-only — no test suite beyond CI validator scripts.

## Risk Assessment
| Risk | Severity | Mitigation |
|------|----------|------------|
| Agent↔command mirror drift (Parameters-table prose not covered by check-command-sync.sh) | MEDIUM | Manual sweep of agents/*.md enumerations touched; per memory "agent-command-mirror-drift" |
| Doc-currency gate false-negative on version bump | MEDIUM | Update plugin.json + marketplace.json version string in place; run scripts/check-doc-currency.sh locally before PR |
| Merge-executor invariant grep gains a 5th surface via new decision-table wording | LOW | Phrase decision-table merge notes with "never"/"not" so the filter excludes them; run the grep in test plan |

## Test Plan
- Run: `bash scripts/check-doc-currency.sh && bash scripts/check-command-sync.sh && bash scripts/validate-version.sh`
- Run the merge-executor grep; assert exactly 4 surfaces.
- Per-file flag-completeness greps; paste outputs into the PR description.

## Out of Scope
Removing/renaming flags, demoting flags to config keys, inlining the trusted-merge deep contract, any behavior change.

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-07-06-command-clarity-decision-table.md

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/91
- **heal_loop_ran:** true
- **heal_decision:** PASS
- **heal_iterations:** 0
- **heal_remaining_issues:** 0
- **rubric_score:** null (no Outcomes Rubric)
- **Until-mergeable dispatched:** false (default dispatch suppressed by /automate engine; owned inline drain follows)
