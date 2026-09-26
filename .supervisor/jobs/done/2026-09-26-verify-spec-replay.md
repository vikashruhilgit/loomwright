# Supervisor Job: `/verify` spec replay — derive a ticket AC's spec once, replay it, re-derive only on a harness-reason BLOCKED

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean code tree (only `.supervisor/` trail, carried separately by PR #268), branch: automate-hardening-2026-09-22 (the run's isolation branch), base main @ 91c117e
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (python3 was blocked by an unaccepted Xcode license earlier this session; owner accepted it, full loop re-verified 114/114 on main @ 91c117e)
- **Source requirement:** .supervisor/requirements/token-economy/07-verify-spec-replay.md
- **Base commit:** 91c117e

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Bash subcommand in `verify-run.sh`, two Python validator extensions, markdown doc edits: the stack these files already use. |
| 2 | Dependency Availability | GO | Reuses `sha256_of` (`verify-run.sh`, `shasum -a 256` → `sha256sum` → empty⇒null), `jq`, `git diff --name-only`; no new dependency. |
| 3 | Architecture Fit | GO | Extends the existing `impact prior-acs` sibling-run-dir scan pattern (lexical run_id sort, never self, copy-out only) and the closed `EVENTS`/`EVENT_CHECKS` validator plug-in shape. |
| 4 | Scope vs Supervisor Capability | CAUTION | 14–16 changed files (> 12) ⇒ `context-bound` split into two sequential subtasks. |
| 5 | Hard Blockers | GO | Dependency harness-port/04 is already merged (#263, e24d7d7), and `summary_build`/`impact_summary_render` already carry its `not_verified` rows. |

**Overall Verdict:** GO (CAUTION #4 → Risk Assessment)

## Task
**Goal:** On a re-run of `/verify <ticket>`, every AC whose `ac_id` AND text are unchanged since a prior run of the SAME ticket reuses that run's spec verbatim (zero authoring calls). A replayed spec that is BLOCKED for a harness reason is re-derived at most once. Every replayed / authored / re-derived spec is labelled in the evidence, and verdict semantics, the four-verdict taxonomy and `counts` are byte-unchanged.

**Problem Statement:** Re-running `/verify` on the same ticket (after a fix, a heal round, or before a merge) pays the full AC → Playwright derivation cost again. `skills/verify-walkthrough/SKILL.md` §6 budgets "about 2–3 calls per AC" of the 80-tool-call budget for authoring. `impact prior-acs` matches on `surfaces` across ANY ticket; it never matches on ticket or AC text and never copies a spec file, so it cannot serve the ticket's own ACs.

## Acceptance Criteria
The source requirement's AC1–AC11 are carried over, with corrections from the premise re-check at main @ 91c117e marked ⚑.

- [ ] **AC1** — Throwaway repo with one prior `completed` run of ticket T (3 ACs). `verify-run.sh spec-replay <run_dir>` on a new run of T copies all 3 specs byte-for-byte into `<run_dir>/specs/` and prints `replayed=3 total=3` LAST. Evidence has exactly 3 `spec_replay` lines, each with `source_run_id` equal to the prior run id.
- [ ] **AC2** — AC #2's text changed by one character ⇒ `replayed=2 total=3`, and no `specs/AC2.spec.ts`.
- [ ] **AC3** — No sibling run at all ⇒ `replayed=0 total=3`, exit 0, no evidence line, and `specs/` absent or empty.
- [ ] **AC4** — A sibling run of a DIFFERENT `ticket_path` with byte-identical AC text ⇒ `replayed=0` (ticket-scoped).
- [ ] **AC5** — `--no-replay` ⇒ `replayed=0`, nothing copied, exit 0.
- [ ] **AC6** — The source run dir is byte-identical before and after (`diff -r`): replay never writes into a prior run (SKILL §10 "Reconcile on every start": a stale run dir is NEVER reused and NEVER deleted).
- [ ] **AC7** — `churn_files` = `|git diff --name-only <source.head_sha>...<this.head_sha> ∩ source ac-line surfaces|` when the source `ac` line has `surfaces`, and `null` (never `0`) when it has none. A `spec_replay` line missing `source_run_id`, or with the `churn_files` KEY absent, is refused by `verify-helpers.sh evidence-append` (non-zero, nothing appended, goes to `rejected.jsonl`).
- [ ] **AC8** — `VERIFY_RESULT` with `spec_sources` absent validates. `{replayed: "3", …}` (a string) is rejected by the new rule V8. Three non-negative ints validate. Any extra or missing key is rejected. V8 lives in `validate_verify()` in `validate-qa-result.py`, mirroring V7's presence-then-shape block. ⚑ Its tests go in `test-result-validators.sh` §E2; there is no `test-qa-result.sh`.
- [ ] **AC9 (mutation control)** — Delete the `text_sha` comparison in `spec-replay` ⇒ AC2 fails. Delete the `ticket_path` comparison ⇒ AC4 fails. Build these the way this repo's other mutation controls do (patch a temp copy of the script, assert the fixture flips).
- [ ] **AC10** — `summary.md` carries one line, `spec sources: replayed n · authored n · re-derived n`, whose numbers equal the evidence counts. Assert it over a fabricated evidence file with 2 `spec_replay` + 1 `spec_rederived` + 1 plain `ac` line. `authored` = ticket-scope `ac` ids with no `spec_replay` line. ⚑ It sits beside, and must not collide with, harness-port/04's impact-scope table (`impact_summary_render`, `verify-helpers.sh`).
- [ ] **AC11 (prose, gate-checked)** — `skills/verify-walkthrough/SKILL.md` §2 states three things:
  - replay-first;
  - the never-re-derive-on-FAIL rule;
  - the ≤1 re-derivation bound.

  ⚑ The drift fallback fires ONLY for a replayed AC whose `walk` verdict is `BLOCKED` with reason `spec_skipped` or `spec_not_run`, the two spec-level harness reasons. Environment-wide BLOCKED reasons (`playwright_unavailable`, `reporter_missing:*`, a `net::ERR_`/`ECONNREFUSED`/`page.goto` timeout message, `session_expired`, `run_paused_session_expired`) are NOT re-derived, because re-authoring cannot fix them. Enumerate them in the SKILL from `verify-run.sh`'s walk classification (read the `case "$rstatus"` block; do not guess).

  Gates: `check-doc-currency.sh` and `test-citation-drift.sh` stay green, and every new `path:line` citation in prose is pinned (CLAUDE.md §"Adding or Modifying Agents" step 5). ⚑ `check-command-sync.sh` pairs only code-reviewer's command and agent, so it neither covers nor gates `commands/verify.md` ↔ `agents/qa-executor.md`. Their consistency is a Phase 4.5 review item.
- [ ] **AC12 (new, honest-limit visibility)** — A replayed spec that FAILS is never re-derived. Because `walk` classifies a locator/selector timeout as FAIL/`REAL_BUG` (only `net::ERR_`/`ECONNREFUSED`/`page.goto` timeouts are BLOCKED), a replayed spec broken by UI drift reports FAIL. To keep that visible rather than silent:
  - the `summary.md` ticket table marks every replayed row (e.g. a `replayed` source marker, derived from `spec_replay` evidence);
  - the SKILL's honest-limits list states the case and its remedy, `/verify --no-replay`.

  Test: a fabricated replayed AC with a FAIL `ac` line shows the replayed marker in `summary.md`.
- [ ] **Validator** — `validate-verify-evidence.py` gains `"spec_replay"` and `"spec_rederived"` in `EVENTS`, one `check_<event>` function each, and one `EVENT_CHECKS` entry each.
  - `spec_replay`: `ac_id`, `source_run_id`, `text_sha` are non-empty strings; `churn_files` is int ≥ 0 or null, with an explicit KEY-presence check (a missing key is rejected, not treated as null).
  - `spec_rederived`: `ac_id`, `reason` are non-empty strings.
- [ ] **Docs:**
  - `commands/verify.md` Parameters table gets a `--no-replay` row, forwarded to `spec-replay`.
  - `agents/qa-executor.md` `### VERIFY MODE` mirrors SKILL §2: author only ids with no file under `specs/` after `spec-replay`; the drift fallback; ≤1 re-derivation.
  - SKILL §6 budget sentence becomes "about 2–3 calls per AUTHORED AC".
  - SKILL §Checklist gets one box: every replayed id has a `spec_replay` line.
  - `docs/RESULT_SCHEMAS.md` §VERIFY_EVIDENCE (two new events) and §VERIFY_RESULT (optional `spec_sources`, V8, no `schema_version` bump, the V7 precedent).
  - One CHANGELOG paragraph; version bump in `plugin.json` + `marketplace.json` + CHANGELOG only.
  - Counts unchanged: 14 agents, 24 commands, 42 skills, 43 hooks.
- [ ] **Token budget** — `agents/qa-executor.md` is budgeted (measured 43786 / budget 48165, 4379 headroom). Re-measure live after editing. If breached, raise per the standard measured+~10% rule in `docs/prompt-token-budgets.json` and the `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" mirror row, with a Re-measure log entry. The skill has no budget row (it is not preloaded).
- [ ] **Invariants** — no new agent, command, skill or hook; `hooks.json` byte-unchanged; `heal_decision` untouched; nothing gating. `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` still resolves to the same 5 sanctioned surfaces.
- [ ] **Full test loop green** — `loomwright/scripts/test-*.sh` + root `scripts/test-*.sh` + `scripts/check-vendor-coupling.sh` + `scripts/check-doc-currency.sh` + `scripts/check-token-budget.sh` + `scripts/check-skills-index-sync.sh`. SKILL frontmatter version bump ⇒ sync `SKILLS_INDEX.md`, which broke CI on PR #266.

## Non-goals
- No change to `walk`'s verdict classification (the locator-timeout ⇒ FAIL rule stays; AC12 only makes a replayed FAIL visible).
- No rewriting of `[ACn]` titles; a renumbered-but-unchanged AC is re-derived (stated limit).
- `churn_files` is RECORDED, never a decision input (D8, `docs/SPIKES/FINAL_STATE_GOAL.md`).
- No store outside the gitignored `.supervisor/verify/`, so there's zero benefit on a fresh clone / worktree / CI (same limit as `prior-acs`).
- **No `## Result` section with the first 5 real re-runs' `spec sources:` lines.** That is D11 post-merge observation, tracked as a follow-up note on the requirement, not achievable inside this PR.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Parallelism Analysis
- **Mode:** sequential. 2 subtasks; subtask 2 documents the exact names and shapes subtask 1 lands.
- **Recommended workers:** 1 at a time

## Skill References
| Skill | Justification |
|---|---|
| quality-checklist | Standard pre/post-implementation gates. |
| verify-walkthrough | Authority for the `/verify` run-dir, evidence, walk and summary contracts this item extends. |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Mechanism: `spec-replay` subcommand, evidence events + validator, V8, `spec sources:` summary line + replayed-row marker, tests | AC1–AC10, AC12 (summary part), Validator | 7 modify, 0 create | quality-checklist, verify-walkthrough | LAUNCHABLE |
| 2 | Contracts + prose: SKILL §2/§6/§Checklist/honest limits, qa-executor mirror, `verify.md` `--no-replay`, RESULT_SCHEMAS, token budget, CHANGELOG + version bump | AC11, AC12 (prose part), Docs, Token budget, Invariants | 7–9 modify, 0 create | quality-checklist, verify-walkthrough | BLOCKED (requires 1) |

```yaml
subtask_id: verify-spec-replay-01
title: "Mechanism: spec-replay + spec_replay/spec_rederived events + V8 + spec sources summary line, with tests"
lanes:
  - loomwright/scripts/verify-run.sh
  - loomwright/scripts/verify-helpers.sh
  - loomwright/scripts/validate-verify-evidence.py
  - loomwright/scripts/validate-qa-result.py
  - loomwright/scripts/test-verify-walkthrough.sh
  - loomwright/scripts/test-verify-evidence.sh
  - loomwright/scripts/test-result-validators.sh
requires: []
external_requires: []
provides:
  - {kind: "symbol", path: "loomwright/scripts/verify-run.sh", name: "spec-replay"}
  - {kind: "symbol", path: "loomwright/scripts/validate-verify-evidence.py", name: "spec_replay"}
  - {kind: "symbol", path: "loomwright/scripts/validate-verify-evidence.py", name: "spec_rederived"}
  - {kind: "symbol", path: "loomwright/scripts/validate-qa-result.py", name: "spec_sources"}
  - {kind: "symbol", path: "loomwright/scripts/verify-helpers.sh", name: "spec sources:"}
out_of_lane: []
---
subtask_id: verify-spec-replay-02
title: "Contracts + prose: SKILL, qa-executor mirror, verify.md --no-replay, RESULT_SCHEMAS, budget, CHANGELOG + version"
lanes:
  - loomwright/skills/verify-walkthrough/SKILL.md
  - loomwright/skills/SKILLS_INDEX.md
  - loomwright/agents/qa-executor.md
  - loomwright/commands/verify.md
  - loomwright/docs/RESULT_SCHEMAS.md
  - loomwright/docs/prompt-token-budgets.json
  - loomwright/docs/ARCHITECTURE_CONTRACTS.md
  - CHANGELOG.md
  - loomwright/.claude-plugin/plugin.json
  - .claude-plugin/marketplace.json
requires:
  - {kind: "symbol", path: "loomwright/scripts/verify-run.sh", name: "spec-replay", from: 1}
  - {kind: "symbol", path: "loomwright/scripts/validate-qa-result.py", name: "spec_sources", from: 1}
external_requires: []
provides:
  - {kind: "symbol", path: "loomwright/commands/verify.md", name: "--no-replay"}
  - {kind: "symbol", path: "loomwright/skills/verify-walkthrough/SKILL.md", name: "spec_rederived"}
  - {kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "spec_sources"}
out_of_lane: []
```

## Configuration
- **Mode:** sequential
- **Recommended workers:** 1
- **Split reason:** context-bound (14–16 files > 12)

## File Impact Map
- **Modify (subtask 1, HIGH confidence):** verify-run.sh, verify-helpers.sh, validate-verify-evidence.py, validate-qa-result.py, test-verify-walkthrough.sh, test-verify-evidence.sh, test-result-validators.sh
- **Modify (subtask 2):** verify-walkthrough/SKILL.md, SKILLS_INDEX.md (HIGH: the frontmatter version bump requires it), qa-executor.md, verify.md, RESULT_SCHEMAS.md, CHANGELOG.md, plugin.json, marketplace.json (HIGH); prompt-token-budgets.json + ARCHITECTURE_CONTRACTS.md (LOW: only if the qa-executor budget is breached)
- **Create:** none

## Risk Assessment
| Risk | Source | Mitigation |
|---|---|---|
| **UI drift on a replayed spec reads as a false FAIL.** `walk` maps a locator timeout to FAIL/`REAL_BUG`, and a replayed FAIL is never re-derived by design (never learn to pass). | Premise re-check (main @ 91c117e) | AC12: the replayed-row marker in `summary.md`, a SKILL honest limit and the `--no-replay` remedy. `churn_files` gives a human the staleness signal. |
| **The ticket match is the whole correctness boundary**: a wrong `ticket_path`/`ac_id`/`text_sha` match replays a spec for a DIFFERENT AC. | Design | AC4 plus AC9's mutation controls prove each comparison is load-bearing. Hash the AC text via the existing `sha256_of` on a temp file (whitespace-normalised). No new hashing routine. |
| **The `churn_files` pathspec trap**: empty `surfaces` ⇒ an empty intersection that looks like "no churn". | preflight-sync SKILL ("never conclude 'no overlap' from an empty pathspec-filtered git log") | Absent/empty `surfaces` ⇒ `null`, never `0` (AC7), plus the validator's presence check. |
| Nullable-required field silently accepted when missing. | Memory `nullable-required-field-needs-presence-check` | An explicit KEY-presence check for `churn_files`, with a test for the absent-key case (AC7). |
| Two workers, and subtask 2 docs drifting from subtask 1's real names. | Feasibility #4 (context-bound split) | Subtask 2 `requires:` subtask 1's symbols. Phase 4.5 consistency review checks the code↔prose mirror; `check-command-sync.sh` does not cover it. |
| The `qa-executor` token budget has 4379 headroom. | Budget file | Re-measure live; raise only if breached, with a log entry. |

## Handoff
Run: `/supervisor job: .supervisor/jobs/pending/2026-09-26-verify-spec-replay.md`

## Environment Validation
- ✓ `gh` authenticated; ✓ `jq`; ✓ `python3` working again (verified; full loop 114/114 on main @ 91c117e); ✓ `shasum`/`sha256sum`.
- ✓ The extension points exist: `test-verify-walkthrough.sh` (`stage()`, `write_specs`), `test-verify-evidence.sh` (`L()`, `AC()`), `test-result-validators.sh` §E2.

---

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/269
- **Reconciled:** lifecycle move completed by reconcile-jobs.sh, not by the completion tail
- **Evidence:** automate engine supplied merge evidence for .supervisor/requirements/token-economy/07-verify-spec-replay.md (https://github.com/vikashruhilgit/loomwright/pull/269) — the engine verified the PR merged against the forge; this reconciler stayed offline
- **Caveat:** fields the completion tail would have recorded (files changed, heal decision and iterations, red-team advisory) are NOT recoverable after the fact and are deliberately omitted rather than invented.
