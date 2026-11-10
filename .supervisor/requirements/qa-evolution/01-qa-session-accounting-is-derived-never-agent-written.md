# QA session accounting is derived, never agent-written

## Status: pending

Source: `/product-owner` qa-evolution set, 2026-11-09, read against main `8ec200e` / v17.35.1. Plan doc: `00-overview.md` in this folder.

**As the** owner (Vikash), reading a QA campaign's roll-up before deciding what to fix,
**I want** every `.qa-session/results/<scope>.json` to pass a committed schema before it is stored, `coverage.json` and a cumulative campaign summary rebuilt by a script from those files on every write, and every denominator reconciled against `plan.json`,
**so that** a failed scope can never roll up as completed, a tested count can never exceed what discovery found, and the campaign report accumulates instead of being overwritten by the last scope.

### Problem (read on main `8ec200e`)

- **The agent writes the roll-up.** `loomwright/agents/qa-executor.md` §"Phase 1: SESSION PLANNING", `--scope` steps 9–11: "Update .qa-session/coverage.json with cumulative results", "Mark scope status → completed in plan.json", "Save per-scope result to .qa-session/results/{name}.json". `loomwright/skills/qa-orchestration/SKILL.md` §4 "coverage.json Schema" gives the agent "Update rules: After each `--scope` or `--continue` run, merge new coverage into cumulative totals".
- **`coverage.json` has a schema but is agent-maintained; results files have none; nothing validates or derives.** `loomwright/docs/result-schemas/qa-session.md` §QA_SESSION schemas `plan.json` and `coverage.json` and states validation rules (`routes_tested` ≤ `routes_total`, `apis_tested` ≤ `apis_total`, completed + remaining = total scopes) that no code enforces. It does not schema `results/<scope>.json`. No script under `loomwright/scripts/` names `qa-session`. `loomwright/scripts/validate-qa-result.py` validates the `QA_RESULT` markdown block on SubagentStop, not these files.
- **The summary is per scope.** §"Phase 13" STEP 3 writes `.qa-summary.md` ("max 200 tokens") for the Strategist audit; nothing cumulative exists. SKILL §6 "Re-run a failed scope" and §8: a re-run overwrites `results/{name}.json`.
- **Owner-supplied evidence** (the owner's memory notes on the sports-management L1 run, 2026-03-22 → 2026-04-06; recorded here as supplied, not re-read): 16 results files with key counts 8–19 and no two alike, 5 of 16 with no `status`; `coverage.json` said `completed` for the `store` scope whose own file said `failed`; per-scope `apis_tested` summed to 183 against `apis_total` 175, and risk buckets summed to 226 APIs / 98 routes against headers 175 / 97; `.qa-summary.md` held only the last scope; `coverage.json.updated_at` was older than `completed_at` values inside it.
- **The pattern that fixes this class already shipped in the verify lane.** `loomwright/scripts/verify-helpers.sh` `evidence-append` is the store's only writer (canonicalise → validate → one write → `summary-build` on every append; a hand-edited `summary.md` is overwritten), and `loomwright/scripts/validate-verify-evidence.py` is a CLI gate whose exit status is the decision (its header names this as the deliberate deviation from the always-exit-0 hook validators). `docs/result-schemas/verify-evidence.md` forbids counts on the `run_end` line because "a total can only be computed, never written".

### Scope

**Part A — the results schema and its validator.**
- `docs/result-schemas/qa-session.md` gains a `### results/<scope>.json` block (`QA_SESSION_RESULT`, `schema_version: 1`): `scope`, `status` (enum `completed | failed | partial`), `started_at` / `finished_at` (ISO-8601 UTC), `depth`, `report_path` (the Playwright JSON reporter file the counts were copied from), `tests` (`total`, `passed`, `failed`, `skipped` — copied from the reporter, never tallied by hand), `routes_tested` and `apis_tested` as **lists of identifiers** (the plan's own strings), never counts, `bugs[]` (`id`, `classification` enum `REAL_BUG | DISCOVERY_GAP | ENVIRONMENT_ISSUE`, `severity` enum `BLOCKING | HIGH | MEDIUM | LOW` REQUIRED when classification is `REAL_BUG` and FORBIDDEN otherwise — Phase 13 STEP 2's rule "Assign severity only for REAL_BUG", `title`, `spec`, `route` or `api`, `steps[]`). **Forbidden keys:** any `*_total`, `coverage*`, `cumulative*`, `bugs_found`, `bugs_blocking` — a results file states facts, every count is derived (the `run_end_carries_counts` precedent).
- New `loomwright/scripts/validate-qa-session-result.py`: a CLI gate (exit 0 valid / 1 invalid with `{"ok": false, "reason": "<code>"}` / 2 usage), stdlib only, a closed snake_case reason set transcribed from the schema section; the self-test greps both surfaces for the same enum tokens (the verify-evidence seam precedent).

**Part B — one writer, derived views.**
- New `loomwright/scripts/qa-session-helpers.sh` (modelled on `verify-helpers.sh`): `result-write <session_dir> <scope> <json|->` canonicalises to one JSON document, runs the validator, and only on exit 0 writes `results/<scope>.json` atomically (temp + `mv`), then rebuilds `coverage.json` and `summary.md`. Refused input is wrapped raw into `rejected/<scope>.<ts>.json` with the validator's reason; the results file is byte-unchanged; exit 1. `python3` absent ⇒ every write is REFUSED (`validator_unavailable`), never let through — this is a correctness gate, so it fails CLOSED.
- `coverage-build <session_dir>`: the ONLY reader of `results/` for counts. Reads `plan.json` for denominators and the scope list. Derives `coverage.json`: `routes_tested` = number of distinct tested route ids that are in the plan, `apis_tested` likewise, `routes_total` / `apis_total` copied from the plan, `unplanned` = tested ids the plan does not know (listed, never counted into the numerator), `scopes_completed` ONLY from files whose own `status` is `completed`, `scopes_failed`, `scopes_partial`, `scopes_remaining` = plan scopes with no results file, `sessions_completed` = number of results files, `last_updated` = the newest `finished_at`, and a `derived_from` object (file list + sha256). A tested count can therefore never exceed its total; a `failed` scope can never appear under `scopes_completed`.
- `summary-build <session_dir>`: derives `.qa-session/summary.md` — a roll-up header (the same derived counts; bugs by severity, REAL_BUG only; rejected-file count) and one section per scope in plan priority order from the latest results file per scope, ending in a `derived_from:` trailer. A re-run of a scope changes that scope's section only; every other section stays. The replaced results file is kept as `results/superseded/<scope>.<finished_at>.json` and is never read for counts.
- `.qa-summary.md` is **untouched**: it stays the ≤200-token per-scope handoff the QA Strategist audits (`agents/qa-strategist.md` §"Audit Mode"; `commands/qa-strategist.md`; `skills/qa-gates/SKILL.md`).

**Part C — the prompt, the skill and the docs say the same thing.**
- `agents/qa-executor.md`: `--plan` step 7 and `--scope` steps 9–11 become calls to `qa-session-helpers.sh` (`coverage-build` after the plan is written; one `result-write` per scope — the agent never opens `coverage.json`, `summary.md` or `plan.json` scope statuses for writing); `--continue` step 2 picks the first scope, in plan priority order, that the derived `coverage.json` lists under `scopes_remaining`; §"File Output Structure" lists `summary.md`, `rejected/`, `results/superseded/`. Phase 13 STEP 3 (`.qa-summary.md`) is unchanged.
- `skills/qa-orchestration/SKILL.md`: §2 tree, §4 (the agent-side "Update rules" are replaced by the derivation rules and the statement that the file is never edited), §6 re-run text, §8 error table, Quality Checklist.
- `docs/RESULT_SCHEMAS.md` preamble lists `QA_SESSION_RESULT` as CLI-gated (the `VERIFY_EVIDENCE` wording); `docs/ARCHITECTURE_CONTRACTS.md` file-ownership table (the table that holds the `.qa-summary.md` row) gains rows for `.qa-session/results/`, `coverage.json` and `summary.md` naming `qa-session-helpers.sh` as the sole writer; `docs/prompt-token-budgets.json` `.agents["qa-executor"]` and `.skills["qa-orchestration"]` re-measured with the mirror rows in ARCHITECTURE_CONTRACTS.md §"Prompt Token Budgets".

## Acceptance Criteria

Every case builds its session dir under the test's `mktemp -d` tree (hermetic: `scripts/check-test-hermetic.sh`). Fixtures under `loomwright/scripts/fixtures/qa-session/` are the owner-supplied sports-management shapes rebuilt by hand: a results file with no `status`; a `store` file with `status: failed` beside a stale `coverage.json` claiming `store` completed; a scope listing more API ids than the plan has; a set whose key sets differ file to file.

**Part A: schema + validator (Test: `loomwright/scripts/test-qa-session-helpers.sh`)**
- [ ] **Schema is the authority:** `docs/result-schemas/qa-session.md` carries the `QA_SESSION_RESULT` block; the test extracts its `status`, `classification` and `severity` enum tokens and finds the identical tokens in `validate-qa-session-result.py`. Test: `test-qa-session-helpers.sh`.
- [ ] **Every reason fires once:** `missing_key:status`, `unknown_enum:status`, `forbidden_key:<k>` (for `apis_total`, `coverage_weighted`, `bugs_found`), `bad_type:apis_tested` (a number where a list is required), `tests_arithmetic` (`passed + failed + skipped != total`), `duplicate_id:<list>`, `severity_required` (REAL_BUG without severity), `severity_on_non_bug`, `missing_classification`, `not_json`, `not_object`, `schema_version_mismatch` — each provoked by one fixture, exit 1, the code on stdout; a valid file exits 0 with `{"ok": true}`; a missing argument exits 2 with nothing on stdout. Test: `test-qa-session-helpers.sh`.
- [ ] **The owner-supplied shapes are all refused by name:** the no-`status` shape → `missing_key:status`; a file carrying `apis_tested: 23` → `bad_type:apis_tested`; a file carrying `bugs_found` → `forbidden_key:bugs_found`. Test: `test-qa-session-helpers.sh`.

**Part B: writer + derivers (Test: `loomwright/scripts/test-qa-session-helpers.sh`)**
- [ ] **Refusal leaves no trace in results:** `result-write` with an invalid document exits 1, writes `rejected/<scope>.<ts>.json` wrapping the raw input and the reason, and `results/<scope>.json` (absent or present) is byte-identical before and after; `coverage.json` and `summary.md` are not rewritten. Test: `test-qa-session-helpers.sh`.
- [ ] **Accepted write derives both views:** after a valid `result-write`, `results/<scope>.json` holds exactly the canonical bytes that were validated, and `coverage.json` and `summary.md` exist with a `derived_from` naming that file and its sha256. Test: `test-qa-session-helpers.sh`.
- [ ] **A failed scope never rolls up as completed:** with the `store` fixture (`status: failed`) and the stale `coverage.json` claiming it completed, one `result-write` of any scope yields a `coverage.json` that lists `store` under `scopes_failed`, not `scopes_completed`, and `summary.md`'s `store` section reads `failed`. Test: `test-qa-session-helpers.sh`.
- [ ] **A tested count never exceeds its total:** a plan with 175 API ids and results whose `apis_tested` lists sum to 183 entries (overlaps plus 6 ids the plan does not have) derive `apis_tested` ≤ 175 (distinct, in-plan) and `unplanned` listing exactly the 6; `routes_tested` ≤ `routes_total` likewise. A mutant that counts list lengths instead of the distinct in-plan set fails this case. Test: `test-qa-session-helpers.sh`.
- [ ] **Remaining is derived from absence:** a plan scope with no results file is in `scopes_remaining`; `scopes_completed + scopes_failed + scopes_partial + scopes_remaining` equals the plan's scope count; `sessions_completed` equals the number of results files; `last_updated` equals the newest `finished_at` (a mutant stamping the wall clock fails). Test: `test-qa-session-helpers.sh`.
- [ ] **Hand edits do not survive:** editing `coverage.json` (`scopes_completed` gains `store`) or `summary.md` by hand and then running any `result-write` restores both to the derived content. Test: `test-qa-session-helpers.sh`.
- [ ] **The summary accumulates:** three scopes written in turn give a `summary.md` with three scope sections in plan priority order and a header whose counts equal `coverage.json`'s; re-writing the second scope changes only its section; the earlier file is under `results/superseded/<scope>.<finished_at>.json` and is not counted. Test: `test-qa-session-helpers.sh`.
- [ ] **Fails closed without its gate:** with `python3` removed from `PATH`, `result-write` exits 1 with reason `validator_unavailable`, writes nothing under `results/`, and records the refusal. Test: `test-qa-session-helpers.sh`.
- [ ] **Atomic and portable:** no partial `coverage.json` / `summary.md` exists at any point (temp + `mv`); the suite passes under bash 3.2 (no associative arrays, no `stat`, no `${var//…}` over large strings — `AGENT_GUIDELINES.md`). Test: `test-qa-session-helpers.sh`.
- [ ] **`.qa-summary.md` contract untouched:** `agents/qa-strategist.md`, `commands/qa-strategist.md` and `skills/qa-gates/SKILL.md` are byte-identical to main (a `git diff --exit-code` guard). Test: `test-qa-session-helpers.sh`.

**Part C: prompt, skill, docs (Test: repo gates)**
- [ ] `agents/qa-executor.md` names `qa-session-helpers.sh result-write` as the only path to `results/<scope>.json` and no longer instructs a write to `coverage.json` or to a `plan.json` scope status (`grep -n "Update .qa-session/coverage.json\|Mark scope status" loomwright/agents/qa-executor.md` prints nothing); `--continue` reads `scopes_remaining`. Test: `bash scripts/check-token-budget.sh` (re-measured entry) and the grep above.
- [ ] `skills/qa-orchestration/SKILL.md` §4 carries no agent-side "Update rules"; `docs/result-schemas/qa-session.md` holds the new block; `docs/RESULT_SCHEMAS.md`'s preamble names `QA_SESSION_RESULT`; `bash loomwright/scripts/test-result-schemas-split.sh` passes (no new top-level heading, so no new pointer). Test: `test-result-schemas-split.sh`, `bash scripts/check-doc-currency.sh`.
- [ ] `docs/ARCHITECTURE_CONTRACTS.md` file-ownership table has the three `.qa-session/` rows and the two re-measured budget rows; `docs/prompt-token-budgets.json` carries the re-measured `qa-executor` and `qa-orchestration` entries. Test: `bash scripts/check-token-budget.sh`.

## Non-goals
- Changing `.qa-summary.md` or the QA Strategist's audit input in any way (PO default below).
- Rewriting `plan.json`: its scope list, routes, APIs and totals are the deriver's inputs; its per-scope `status` / `completed_at` are no longer consulted and are not rewritten (PO default below).
- A schema for `discovery/*.json`, for `QA_RESULT` (already hook-validated) or for `.qa-summary.md`.
- Any gate: QA stays advisory; nothing here enters `gate-eval` / `merge-verdict`, Phase 4.5 or the drain (owner rule; CLAUDE.md §"Failure-Mode Invariants").
- Running QA on this repo, migrating the sports-management artifacts, or changing what the executor tests (L2 depth stays deferred — `00-overview.md`).
- Consuming the bugs (story `02-qa-findings-reach-a-consumer-propose-from-qa.md`) or scoring the lane (story `03-the-qa-lane-earns-its-cost-on-the-feature-scorecard.md`).
- A new agent, a browser MCP, Beads, telemetry of any QA content.

## Owner decisions
- 2026-11-09 (Vikash, standing rule): **Not approved to build — requirements only.** Implementation needs the owner's explicit approval.
- 2026-11-09 (Vikash, qa-evolution constraints): NO new agent — `qa-executor` is the executor; counts are derived, never agent-written; QA/verify is advisory and NEVER gating; every new script gets a `test-*.sh`; every changed agent/command/skill file re-measures its entry in `loomwright/docs/prompt-token-budgets.json` plus the ARCHITECTURE_CONTRACTS.md mirror row; the PR carries a `changelog.d/<slug>.md` fragment.
- PO default, pending owner review (**the cumulative report's home — a contract-change flag**): the owner's note named `.qa-summary.md` as the cumulative file. `.qa-summary.md` is the QA Strategist's audit input (`agents/qa-strategist.md` "Audit Mode" inputs and "Step 1: READ RESULTS"; `commands/qa-strategist.md` `--audit .qa-summary.md`; `skills/qa-gates/SKILL.md` "written (max 200 tokens)"; `docs/ARCHITECTURE_CONTRACTS.md` file-ownership row), so making it cumulative changes the Strategist's input shape and breaks its 200-token cap. Default: the cumulative report is the derived `.qa-session/summary.md`; `.qa-summary.md` keeps its byte-identical role. The owner may instead choose to re-point the Strategist at the current scope's section of the derived summary — that is a separate, larger item (qa-strategist budget, its command doc, qa-gates).
- PO default, pending owner review (`plan.json` statuses): not rewritten. The derived `coverage.json` is the picker's source of truth (`--continue` reads `scopes_remaining`); a second derived writer for `plan.json` would be a second file to reconcile.
- PO default, pending owner review (counts source): `tests.*` are copied from the Playwright JSON reporter named in `report_path`, and the validator checks the arithmetic; reading the reporter file directly from the helper is a later tightening.
- PO default, pending owner review (superseded results): kept under `results/superseded/`, never counted — history without a second source of truth.
- PO default, pending owner review (list identifiers): `routes_tested` / `apis_tested` carry the plan's own id strings so the deriver can intersect with the plan; a bare count can neither be deduplicated nor bounded.

## Priority: MVP
**Rationale:** the owner's test is met — a confirmed failure in shipped code (the roll-up said `completed` for a `failed` scope; 183 > 175). Story 02 can only consume files that can be trusted, and story 03's catch rule is only as good as the bugs recorded.

## Assumptions
- The owner-supplied shapes (key counts 8–19, 5 of 16 without `status`, 183 > 175, `store` failed-vs-completed) are faithful; the fixtures rebuild them from the notes, not from the sports-management checkout.
- One qa-executor session writes one scope at a time (the `--scope` / `--continue` contract), so `result-write` needs no lock; if a lock is ever added it uses an O_EXCL create (`scripts/check-mkdir-lock.sh`).
- A new `loomwright/scripts/test-*.sh` is picked up by CI's and `ci-local.sh`'s globs with no registration; `--affected` maps it from the changed scripts.
- `verify-helpers.sh` is a model, not a shared library: the two stores stay independent (verify's rows are per fact, QA's are per scope), so no code is extracted from it.
- Right-size (advisory, run 2026-11-09): `qa-evolution/01-qa-session-accounting-is-derived-never-agent-written: ok (12 files, 9 scope items, 16 criteria)`.

## Dependencies
- Depends on: none.
- Blocks: `02-qa-findings-reach-a-consumer-propose-from-qa.md` (reads the schema'd results files through this story's validator and deriver).

## Risks
- **The agent bypasses the helper** and writes `coverage.json` directly out of habit. Mitigation: the prompt names `result-write` as the only path; the next write overwrites any hand-written file; Validation 3 replays a real-shaped session and reads the derived file.
- **A strict schema piles refusals into `rejected/`** on a real run. Mitigation: the reason set is closed and named; `summary.md`'s header counts rejected files so a silent loss is impossible; the first dogfood (operator-run) is where the schema is tuned.
- **Budget growth** in `qa-executor.md` (already the largest agent prompt). Mitigation: the new text replaces the old steps rather than adding to them; the re-measure is in scope.

## Validation (must pass before merge)
1. **Static — helper and validator suite:** `bash loomwright/scripts/test-qa-session-helpers.sh` passes, including the fixture refusals, the two mutants (list-length counting; wall-clock `last_updated`) and the `.qa-summary.md` byte-identity guard.
2. **Static — repo gates:** `bash scripts/ci-local.sh --affected` passes (including `check-test-hermetic.sh`, `check-mkdir-lock.sh`, `check-token-budget.sh`, `check-doc-currency.sh`, `test-result-schemas-split.sh`); `bash scripts/check-version-bump.sh` passes with a `changelog.d/` fragment and no hand-edited version file.
3. **Running system — the owner-supplied shapes replayed:** build a session dir from the fixtures (plan with 97 routes / 175 APIs; `store` failed; API lists summing to 183), run `qa-session-helpers.sh result-write` for each scope, and record in `docs/evidence/qa-session-accounting-replay.md` the derived `coverage.json` (store under `scopes_failed`, `apis_tested` ≤ 175, `unplanned` listed) and the first lines of `summary.md`, with `Verdict: PASS for Validation 3` at column 0. The PR body links the file.

## Depends on
none

## Touches
loomwright/agents/qa-executor.md
loomwright/skills/qa-orchestration/SKILL.md
loomwright/docs/result-schemas/qa-session.md
loomwright/docs/RESULT_SCHEMAS.md
loomwright/docs/ARCHITECTURE_CONTRACTS.md
loomwright/docs/prompt-token-budgets.json
loomwright/scripts/qa-session-helpers.sh
loomwright/scripts/validate-qa-session-result.py
loomwright/scripts/test-qa-session-helpers.sh
loomwright/scripts/fixtures/qa-session/
docs/evidence/qa-session-accounting-replay.md
changelog.d/qa-session-accounting-derived.md
