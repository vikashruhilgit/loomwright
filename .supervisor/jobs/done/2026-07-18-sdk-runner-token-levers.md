# Supervisor Job: SDK-runner token levers (effort / task_budget / context-editing gap) + token accounting

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh, v15.10.0)
- **Git:** clean (2 stray untracked junk files `--help`, `--run-id` at root — pre-existing, do not touch), branch: main @ 7ff5114
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (stray untracked files)
- **Source requirement:** .supervisor/requirements/token-economy/03-sdk-runner-token-levers.md

## Task
**Goal:** The quarantined `loomwright/sdk-spike/` runner gains per-role `effort` config, opt-in per-subtask `task_budget`, a doc-verified context-editing capability entry (gap, not hack), and first-class per-subtask token accounting in its EXECUTE_RESULT-equivalent output — plus self-test coverage and additive doc/eval amendments. Quarantine posture and default path unchanged.

## Acceptance Criteria
- [ ] Given the runner config table, when worker/reviewer roles are resolved, then worker default effort is `medium` and reviewer is a higher value from the table (not hard-coded inline); invalid effort/budget values fail closed (non-zero exit, no query issued).
- [ ] Given `task_budget` set for a subtask query, when < 20000, then the runner fails closed citing the documented 20k minimum; when unset, `taskBudget` is omitted entirely from `Options`.
- [ ] Given a `--dry-run` run, when the EXECUTE_RESULT-equivalent block is emitted, then each subtask entry carries additive per-subtask token-accounting fields (from result `usage`/`total_cost_usd`/`num_turns`; fixtures carry representative values, proxy-labeled where synthetic).
- [ ] Given `docs/SPIKES/SDK_RUNNER_SPIKE.md`, when read, then the capability/parity matrices carry doc-verified rows for effort (supported, `sdk.d.ts:1620`), taskBudget (supported @alpha, `sdk.d.ts:1647-1649`), and context editing (NOT exposed per-query in 0.3.202 — hooks/`getContextUsage()` only; recorded as gap), and the 25/25 self-test count is updated honestly to the new N/N.
- [ ] Given `docs/SPIKES/FABLE_PARITY_EVAL.md`, when read, then token-cost-per-subtask appears as a recorded (not decision-changing) observable, added as a datestamped additive amendment BEFORE any run; the 1.5× decision rule is byte-unchanged.
- [ ] Given `--sdk-runner` off, when the plugin runs, then the default path is byte-identical (diff proof: no file outside `loomwright/sdk-spike/`, `docs/SPIKES/`, CHANGELOG/version metadata changes).
- [ ] `npm run self-test` passes offline with new checks for config parsing (valid/invalid effort, budget floor, omission) and accounting fields in dry-run output.

## Key Facts (verified 2026-07-18)
- Runner: `loomwright/sdk-spike/src/runner.ts` (696 lines). Query seam `QueryFn` at :101-106; live options built :383-401 (`maxTurns: 40` hardcoded, global `--model`/`--effort` passed identically to both roles at :566-567/:593-594 — no per-role differentiation today). Result consumption :404-425 reads NO usage fields — that is the accounting gap.
- No config module exists — flat CLI args only (`CliArgs` :76-84, `parseArgs` :116-156). The config table is NEW code.
- SDK pin `^0.3.202` (lockfile exact 0.3.202; node_modules present). Types: `effort?: EffortLevel ('low'|'medium'|'high'|'xhigh'|'max')` sdk.d.ts:1620/:522; `taskBudget?: {total: number}` @alpha :1647-1649 (beta header task-budgets-2026-03-13; NO documented type-level floor — enforce 20k in runner); `SDKResultSuccess` at sdk.d.ts:4024 with `num_turns`/`total_cost_usd`/`usage`/`modelUsage` at :4037-4042. Context editing: NO per-query Options flag; only PreCompact/PostCompact hooks, `getContextUsage()` :2369, nested settings-level autoCompact* — record as not-exposed gap per requirement constraint (do NOT upgrade the pin).
- Output block built in `main()` runner.ts:648-687, type `ExecuteResultEquivalent` schemas.ts:256-281. Accounting fields are additive there.
- Fixtures: `src/dry-run-fixtures/` (4 files), selected by `makeDryRunQuery` :342-360, schema-revalidated before return.
- Self-test: `test/self-test.sh` (328 lines, bash-3.2-safe); "25/25" is the full-install pass count cited at SDK_RUNNER_SPIKE.md:40 — update in same change.
- FABLE_PARITY_EVAL.md: decision rule :23-35 (1.5× cap :29-31), metric table :39-44, "no metric added after first run" :49-50, results still pending — amendment window is open.

## Subtask Structure

| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | Runner config layer (per-role effort table + task_budget w/ 20k floor + fail-closed validation) + per-subtask token accounting (read usage, extend ExecuteResultEquivalent + fixtures) + context-editing gap left code-untouched | modify: sdk-spike/src/runner.ts, src/schemas.ts, 4 fixture files, sdk-spike/README.md | LAUNCHABLE |
| 2 | Self-test extension: config parse valid/invalid, budget floor, budget omission, accounting-fields-in-dry-run checks; update pass-count references | modify: sdk-spike/test/self-test.sh | BLOCKED (by #1) |
| 3 | Docs: SDK_RUNNER_SPIKE capability/parity matrix rows (3 levers, doc-verified w/ sdk.d.ts line refs) + token-per-subtask metric note + honest N/N; FABLE_PARITY_EVAL datestamped additive amendment (recorded observable, decision rule unchanged); plugin.json/marketplace.json minor bump + CHANGELOG + CLAUDE.md release banner rotation | modify: docs/SPIKES/SDK_RUNNER_SPIKE.md, docs/SPIKES/FABLE_PARITY_EVAL.md, loomwright/.claude-plugin/plugin.json, .claude-plugin/marketplace.json, CHANGELOG.md, CLAUDE.md, .claude-plugin/README.md (version string) | BLOCKED (by #2 — needs final self-test count) |

## Skill References
| Subtask | Skills to inject |
|---|---|
| 1 | quality-checklist, error-handling, unit-testing |
| 2 | unit-testing, quality-checklist |
| 3 | quality-checklist, commit |

## Subtask Contracts
```yaml
subtask_1:
  provides: [roleConfig table + resolveRoleConfig() fail-closed validation in runner.ts, taskBudget plumbing (20k floor / omit-when-unset), per-subtask usage accounting fields on ExecuteResultEquivalent (schemas.ts) + fixtures]
  requires: []
subtask_2:
  provides: [extended self-test with final N/N pass count]
  requires: [subtask_1 runner behavior (config parsing, budget floor, accounting fields in dry-run output)]
subtask_3:
  provides: [doc-verified matrices, eval amendment, version bump]
  requires: [subtask_2 final self-test pass count]
```

## Parallelism Analysis
- Batch 1: Subtask 1 | Batch 2: Subtask 2 | Batch 3: Subtask 3 (strictly sequential — #2 asserts on #1's behavior; #3 cites #2's final count)
- Recommended workers: 1 (sequential; worktree overhead unnecessary but harmless)

## Configuration
- Max workers: 1
- Base Branch: main
- Heal iterations: 3

## Risk Assessment
| Risk | Severity | Mitigation |
|------|----------|------------|
| `taskBudget` is `@alpha` — runtime behavior unverified offline | MEDIUM | Type-verified only; self-test covers config plumbing, not live API; spike doc records "live verification pending" per requirement test plan |
| Self-test count drift vs SDK_RUNNER_SPIKE.md:40 citation | LOW | Subtask 3 updates the citation from subtask 2's actual final count |
| Doc-currency CI gate on version bump | MEDIUM | Subtask 3 updates plugin.json + marketplace description version-in-place + CLAUDE.md banner (keep only 2 release notes) + counts UNCHANGED 14/21/41/22 |
| Pre-registration violation (eval metric) | LOW | Amendment is additive recorded-observable only, datestamped, decision rule byte-unchanged; runs table still empty (verified) |
| Token-budget CI gate (v15.10.0, new) | LOW | No agents/*.md or preloaded-skill changes → gate unaffected |

## Outcomes Rubric
- Config table in runner encodes worker=medium, reviewer=higher named level; invalid values exit non-zero before any query
- task_budget < 20000 fails closed; unset omits the field from Options (grep-provable)
- Per-subtask token fields present in dry-run EXECUTE_RESULT-equivalent output
- Capability matrix has doc-verified rows for all three levers incl. honest context-editing not-exposed entry
- FABLE_PARITY_EVAL amendment additive + datestamped; decision-rule section diff-empty
- Self-test count updated honestly everywhere it is cited; suite passes offline
- No file outside sdk-spike/, docs/SPIKES/, and version/changelog metadata is modified

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-07-18-sdk-runner-token-levers.md

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/102
- **Branch:** feature/sdk-runner-token-levers
- **heal_loop_ran:** true
- **heal_decision:** PASS
- **heal_iterations:** 0
- **heal_remaining_issues:** 0 (1 MEDIUM drift finding fixed inline: README v15.11.0 banner; 2 LOW deferred to live eval)
- **rubric_score:** 7/7
- **Until-mergeable dispatched:** false (suppressed_default_dispatch — /automate owns the drain)
