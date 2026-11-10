# The QA lane earns its cost on the feature scorecard

## Status: pending

Source: `/product-owner` qa-evolution set, 2026-11-09, read against main `8ec200e` / v17.35.1. Plan doc: `00-overview.md` in this folder.

**As the** owner (Vikash), deciding whether the QA side deserves more investment,
**I want** the feature scorecard to carry one row for `/verify` runs and one for QA Executor runs — runs available, ran, caught, cost — read from a record each lane leaves on disk,
**so that** "does QA earn its cost" is answered by the same table that judges every other optional lens, with `unknown` wherever the record cannot say, instead of by the blueprint's unmeasured "60–95% QA effort eliminated".

### Problem (read on main `8ec200e`)

- **No QA or verify row.** `loomwright/docs/feature-scorecard.json` — "the ONE list of scored optional gates, lenses and advisories" — holds `risk_classification`, `red_team_advisory`, `rubric_score`, `contract_conformance`, `ground_truth`, `benchmark_result`, `heal_dismissed`, `fallback_review_ran`, `pin-mutations`, `multi_voter_heal`, `read-orientation`. `loomwright/scripts/build-feature-scorecard.sh` is registry-as-data, read-only and fail-safe: record formats `result_block | text | json | tsv`, "one record file = one run opportunity", `ran` / `caught` rules are matches on ONE field's value, cost comes from `token_ledger` lines whose `agent_type` ends with `cost.agent` (or a `duration` field), and a cost with no record prints `unknown`, never 0. `/propose --from-scorecard` drafts enhance-or-retire for any non-critical `review:` row.
- **Verify leaves a record.** `.supervisor/verify/<run_id>/evidence.jsonl` is append-only, and `verify-helpers.sh summary_build` derives `summary.md` on every append with a ticket-scope counts row `PASS: n · FAIL: n · BLOCKED: n · NOT_VERIFIABLE: n · total: n` (latest line per `ac_id`) and a `## Run end` line `- status: completed|aborted at <ts>`. There are **zero** `.supervisor/verify/` run dirs on this machine today (`find ~/Documents/work -path '*/.supervisor/verify'` is empty): the lane shipped and was never dogfooded (`verify-walkthrough/operator-run/08-dogfood-on-real-app.md` is still pending).
- **Premise correction — QA leaves no record on disk.** The owner's note placed the hook-validated `QA_RESULT` block in `.supervisor/logs/`. Verified 2026-11-09 on this checkout: none of the `.supervisor/logs/*.jsonl` files contains `QA_RESULT`. The qa-executor `SubagentStop` matcher in `loomwright/hooks/hooks.json` runs `validate-qa-result.py` (decision on stdout; the payload is read from stdin and discarded), `send-telemetry.sh` (opt-in egress; its local writes are `telemetry-sent.log` and pending markers) and `emit-token-ledger.sh` (`token_ledger` lines) — none persists the block. The only qa-executor lines in the logs are `agent_lifecycle`, `token_ledger` and `agent_identity`, which carry no verdict. A `qa_result` row with `record: none` would land on the `needs_emitter` list and answer nothing.
- **The ledger seat is shared.** Both lanes run as `qa-executor` and a `token_ledger` line carries no mode marker, so the builder cannot split one seat between a verify row and a QA row.
- **Hook leaves are counted.** `scripts/check-doc-currency.sh` reads `[.hooks[][].hooks[]] | length` from `hooks.json` and checks the "N quality gate hooks" / "N hooks centralized" claims; the qa-executor matcher already chains two scripts inside one leaf (`payload=$(cat); … send-telemetry.sh …; … emit-token-ledger.sh …`), so a third script can join that line without changing any count.

### Scope

**Part A — the `verify_result` row (registry data only).**
- `record`: `{glob: "verify/*/summary.md", format: "text", field: "PASS:", valid: <the five-count row shape>}` — the builder's `text` format takes the rest of the first line containing the field literal, so the value is the whole counts row. `ran`: `total:` ≥ 1 (at least one ticket-scope AC verdicted; a run paused before any verdict is not a run). `caught`: `FAIL:` ≥ 1. `cost`: `{source: "token_ledger", agent: "qa-executor"}` (present ⇒ the seat's total; absent ⇒ `unknown`). `critical: false`. `what` names the lane and that the row reads the ticket-scope row only.
- Reads the derived `summary.md`, not `evidence.jsonl`: the builder's formats take one value per file, and `summary.md` IS the store's derivation on every append (`derived_from:` trailer), so its counts are the evidence's counts. The alternative — a new `jsonl` record format over `evidence.jsonl` — is a builder change and is named for the owner below. `summary.md`'s filename carries no date, so the builder windows it by mtime, which `summary_build`'s rewrite-on-append keeps equal to the last append.

**Part B — the `qa_result` row and the record it needs.**
- New `loomwright/scripts/emit-qa-record.sh`, a fail-SAFE emitter chained onto the qa-executor matcher's EXISTING fan-out leaf (no new leaf; every hook-count claim unchanged), reading the `SubagentStop` payload from stdin. It resolves the agent text exactly as `validate-qa-result.py` does (`result_block_parser.extract_payload` / `find_last_block`) and acts only on a `QA_RESULT` block: a `VERIFY_RESULT` stop or a payload with no block writes nothing (the verify lane's record is its store). It runs the sibling `validate-qa-result.py` on the same payload and writes nothing when that validator blocks (`validator_rejected`, the `send-telemetry-core.sh` precedent), so a rejected-then-retried stop yields exactly one record.
- The record is `.supervisor/logs/<YYYY-MM-DD-HHMMSS>-qa-result-<agent_id>.md`: the hook-validated block **verbatim**, then ONE derived trailer line outside the block — `qa_lane: tests_generated=<n> bugs_found=<n> blocking=<n|unknown> high=<n|unknown>` — where every number is copied from the block (`tests_generated`, `bugs_found`, `bugs_blocking`) or counted from it (`high` = `bugs[]` entries with `severity: HIGH`; list absent ⇒ `unknown`, never 0). Session-id / `agent_id` resolution and the `.supervisor` anchoring follow `emit-token-ledger.sh`. Always exit 0; empty stdin, no session id, an unwritable log dir or a missing `python3` each absorb to exit 0 with one stderr line.
- Registry row `qa_result`: `{glob: "logs/*-qa-result-*.md", format: "text", field: "qa_lane:", valid: <the trailer shape>}`; `ran`: `tests_generated=` ≥ 1 (a `plan_created` stop ran no tests); `caught`: `blocking=` ≥ 1 or `high=` ≥ 1 (a `REAL_BUG` at BLOCKING or HIGH — Phase 13 STEP 2 counts only `REAL_BUG` toward `bugs_found` and `bugs_blocking`); `cost: "none"` (PO default — the shared seat, below); `critical: false`.
- Docs that restate the touched lists move in the same change: the `docs/HOOKS.md` SubagentStop qa-executor row names the chained emitter; the `docs/ARCHITECTURE_CONTRACTS.md` `.supervisor/logs/` ownership row's list of "non-JSONL files written by hooks" gains the record (no retention-table change: the `logs/` policy row sweeps only `*.jsonl`, so `test-retention-sweep.sh` AC-10's two-way mirror is untouched); `docs/result-schemas/qa-result.md` gains a paragraph on the persisted record and the trailer (the block itself is unchanged — no `schema_version` bump, no validator change).
- `build-feature-scorecard.sh` stays byte-identical; `test-build-feature-scorecard.sh` gains fixture cases for both rows (its shipped-registry check (8) reads the real registry's ids dynamically, so new ids pass on their own; the fixtures prove each row's `ran` / `caught` / `valid`).
- **Independent of story 01:** the `qa_result` row reads the hook-validated block, not `.qa-session/results/*.json`. The block is already validated at the seam, and one QA Executor stop is one run; a campaign's per-scope results files would make one session count as many runs. Story 01 may land before or after.

## Acceptance Criteria

Every case builds its state dir and payloads under the test's `mktemp -d` root (hermetic: `scripts/check-test-hermetic.sh`). QA_RESULT payloads reuse the shapes in `loomwright/scripts/result-validator-fixtures/`.

**Part A: `verify_result` (Test: `loomwright/scripts/test-build-feature-scorecard.sh`)**
- [ ] **Row counts a fixture store:** a state dir with three `verify/<run>/summary.md` fixtures — ticket row `FAIL: 1`, ticket row all PASS with `total: 3`, and a paused run with `total: 0` — gives `runs_available 3, ran 2, caught 1`, catch rate `50%`. Test: `test-build-feature-scorecard.sh`.
- [ ] **Ticket scope only:** a summary whose impact-pass counts line shows `FAIL: 2` while the ticket row shows `FAIL: 0` is `ran`, not `caught` (first-line rule). Test: `test-build-feature-scorecard.sh`.
- [ ] **Malformed is local:** a summary whose counts row is garbled makes `verify_result` `unreadable: …` and leaves every other feature's verdict unchanged. Test: `test-build-feature-scorecard.sh`.
- [ ] **Cost from the seat, never 0:** two in-window `token_ledger` lines for `loomwright:loomwright:qa-executor` give `cost_total` equal to their sum in the builder's existing format; with no ledger line `cost_total` is `unknown`. Test: `test-build-feature-scorecard.sh`.
- [ ] **Zero runs read honestly:** an empty `verify/` gives `runs_available 0`, verdict `insufficient data`. Test: `test-build-feature-scorecard.sh`.

**Part B: the emitter (Test: `loomwright/scripts/test-emit-qa-record.sh`)**
- [ ] **One record per accepted stop:** a payload whose text carries a valid `QA_RESULT` (tests_generated 12, bugs_found 3, bugs_blocking 1, `bugs[]` with one HIGH) writes exactly one `logs/<date>-qa-result-<agent_id>.md` whose block is byte-identical to the payload's block, followed by exactly one line `qa_lane: tests_generated=12 bugs_found=3 blocking=1 high=1`; exit 0. Test: `test-emit-qa-record.sh`.
- [ ] **Nothing for the wrong block:** a `VERIFY_RESULT`-only payload, a payload with no block, and a payload the sibling validator blocks (no `summary`) each write nothing; the blocked one names `validator_rejected` on stderr. A mutant that skips the validator writes a file for the blocked payload and fails this case. Test: `test-emit-qa-record.sh`.
- [ ] **Unknown is never 0:** a block with no `bugs[]` yields `high=unknown`; a block with no `bugs_blocking` yields `blocking=unknown`; a block with `bugs: []` and `bugs_blocking: 0` yields `blocking=0 high=0`. Test: `test-emit-qa-record.sh`.
- [ ] **Fail-safe:** empty stdin, a payload with no session id from either source, an unwritable `logs/`, and `python3` removed from `PATH` each exit 0, write nothing, and print one stderr line. Test: `test-emit-qa-record.sh`.
- [ ] **No new leaf:** `jq '[.hooks[][].hooks[]] | length' loomwright/hooks/hooks.json` equals the value on main; the emitter is reached from the qa-executor matcher's existing `payload=$(cat); …` line with its own `|| true` (grep); `bash scripts/check-doc-currency.sh` passes with no count edit. Test: `test-emit-qa-record.sh`, `check-doc-currency.sh`.
- [ ] **Record date is the run's:** the filename's `YYYY-MM-DD-HHMMSS` is the payload's stop time, so `build-feature-scorecard.sh --since` windows it by name, not mtime. Test: `test-emit-qa-record.sh`.

**Part B: `qa_result` row and the docs (Test: `loomwright/scripts/test-build-feature-scorecard.sh`, repo gates)**
- [ ] **Row counts fixture records:** records with `blocking=1`, `blocking=0 high=1`, `blocking=0 high=0` (tests ran, clean) and `tests_generated=0` (plan_created) give `runs_available 4, ran 3, caught 2`, `cost_total unknown`, `cost_per_catch unknown`. Test: `test-build-feature-scorecard.sh`.
- [ ] **Builder untouched:** `git diff --exit-code main -- loomwright/scripts/build-feature-scorecard.sh` is clean, and the suite's shipped-registry check passes with the two new ids. Test: `test-build-feature-scorecard.sh`.
- [ ] **Docs moved together:** `docs/HOOKS.md`'s qa-executor SubagentStop row names `emit-qa-record.sh`; `docs/ARCHITECTURE_CONTRACTS.md`'s `.supervisor/logs/` row lists the record; `docs/result-schemas/qa-result.md` describes the persisted record and the `qa_lane:` trailer; `bash loomwright/scripts/test-retention-sweep.sh` and `bash loomwright/scripts/test-result-schemas-split.sh` pass unchanged. Test: the two suites and a grep of each doc.
- [ ] **No public claim:** `README.md`, `.claude-plugin/marketplace.json` and `loomwright/.claude-plugin/plugin.json` contain no `qa_result`, `verify_result`, catch-rate or effort-eliminated string added by this change; `/insights` renders the rows only because it renders every registry row (`commands/insights.md` unchanged). Test: a grep guard in `test-build-feature-scorecard.sh`.

## Non-goals
- Any gate: neither row changes `heal_decision`, `gate-eval` / `merge-verdict`, Phase 4.5 or the drain. A `review:` verdict on either row is advisory and reaches the owner only through `/propose --from-scorecard`.
- Splitting the shared `qa-executor` ledger seat per mode (a mode marker on the `token_ledger` line is a later item).
- A `jsonl` record format in the builder (the named alternative, not the default).
- A record for the sports-management campaign (no retro-fit; the first real QA record comes from the next run).
- Changing `validate-qa-result.py`, the `QA_RESULT` schema, `/insights` prose, or any agent / command / skill prompt (no budget re-measure in this story).
- Per-scope QA rows, a verify row per AC, or any measurement of the blueprint's effort claims beyond what these two rows show.

## Owner decisions
- 2026-11-09 (Vikash, standing rule): **Not approved to build — requirements only.** Implementation needs the owner's explicit approval.
- 2026-11-09 (Vikash, qa-evolution constraints): QA/verify is advisory and NEVER gating — never a merge-gate condition (`gate-eval` / `merge-verdict` have exactly seven conditions and a sole executor); no public claims about QA results; counts are derived, never agent-written; every new script gets a `test-*.sh`; the PR carries a `changelog.d/<slug>.md` fragment.
- 2026-11-09 (Vikash, in the brief): two registry rows — `verify_result` (record from the verify run's run_end / summary counts, caught = a FAIL, cost from the ledger seat else `unknown`) and `qa_result` (record = the QA_RESULT block the SubagentStop hook validates; caught = a `REAL_BUG` at BLOCKING / HIGH); registry as data; change `build-feature-scorecard.sh` only if a new `record.format` is unavoidable, and say so; independent of story 01.
- PO default, pending owner review (**premise correction**): no QA_RESULT record exists on disk today, so Part B adds a fail-SAFE record emitter chained onto the existing qa-executor hook leaf. Without it the row is `record: none` on the `needs_emitter` list. The emitter is the smallest change that keeps the builder untouched.
- PO default, pending owner review (verify record surface): the derived `summary.md` counts row, read with the existing `text` format — no builder change. Alternative: a new `jsonl` format reading `evidence.jsonl` directly, which changes `build-feature-scorecard.sh` (the owner asked that this be said if chosen).
- PO default, pending owner review (shared ledger seat): `verify_result` carries the `qa-executor` seat and `qa_result` carries `cost: none` (prints `unknown`), because the builder sums by agent type and naming the seat on both rows would count every qa-executor token twice. Alternatives: name it on both and accept the double count; or a later ledger mode marker that splits the seat.
- PO default, pending owner review (how `caught` is read): the one-field builder cannot read "tests ran" and "a BLOCKING / HIGH bug" from the verbatim block's single field (`bugs[]` is optional when `bugs_found` is 0, so `ran` would undercount clean runs), hence the derived `qa_lane:` trailer. Alternative without a trailer: `field: bugs_found`, caught = any `REAL_BUG`, which relaxes the BLOCKING / HIGH rule.
- PO default, pending owner review (record location): `.supervisor/logs/`, as the owner's note placed it, beside the other hook-written non-JSONL files. Alternative: a new `.supervisor/qa/` dir, which needs a retention policy row, an ARCHITECTURE_CONTRACTS.md row and the `test-retention-sweep.sh` mirror.
- PO default, pending owner review (`ran` for verify): at least one ticket-scope AC verdicted (`total:` ≥ 1), not the presence of a `run_end` line — a paused run that verdicted ACs did run; one that paused before any verdict did not.

## Priority: MVP
**Rationale:** the scorecard shipped (v17.25.0) without the QA lanes, so the owner's test is met — a hole in shipped code — and the blueprint's effort claims have never been measured. The story is small (registry data, one emitter, fixtures) and gives every later QA decision a number.

## Assumptions
- `min_sample` stays 5 in the registry, so both rows read `insufficient data` until five runs exist; the first real reading is expected to show zero runs on this machine.
- The builder's `text` format behaves as its header and `extract()` state: the value is the rest of the first line containing the field literal, leading `:` / `=` / space stripped, capped at 200 characters; the five-count row fits.
- The `SubagentStop` payload resolves to agent text through `result_block_parser`'s `PAYLOAD_TEXT_KEYS` / `PAYLOAD_TRANSCRIPT_KEYS` (`last_assistant_message`, `agent_transcript_path`), the same path the validator uses; no new payload field is assumed.
- The record stays local: `.supervisor/` is gitignored and `logs/*.md` is outside `send-telemetry.sh`'s inputs; the owner's plugin-facts-only rule governs egress, which this story does not touch.
- Right-size (advisory, run 2026-11-09): `qa-evolution/03-the-qa-lane-earns-its-cost-on-the-feature-scorecard: ok (10 files, 8 scope items, 15 criteria)`.

## Dependencies
- Depends on: none. Independent of `01-qa-session-accounting-is-derived-never-agent-written.md` (reads the block, not the results files) and of `02-qa-findings-reach-a-consumer-propose-from-qa.md`.
- Blocks: none. `verify-walkthrough/operator-run/08-dogfood-on-real-app.md` produces the first real `verify_result` record; the next `/qa-executor` run produces the first `qa_result` record.

## Risks
- **The shared seat misattributes cost.** Mitigation: `cost: none` on `qa_result`; the row's `what` says so; a mode marker is the fix if the owner wants both costs.
- **The `PASS:` anchor collides** with an AC text or reason that contains the same literal earlier in `summary.md`. Mitigation: `valid` pins the five-count shape, so a collision reads as `unreadable` for that feature (the fail-safe direction, never a false keep); the implementer may choose a more distinctive anchor if `summary_build` offers one.
- **App content in a local record.** The verbatim block carries bug titles and file names from the project under test. Mitigation: the record is project-local under the gitignored `.supervisor/`, never egressed; the same text already flows through the hook payload today.
- **A chained emitter delays the stop.** Mitigation: `python3` block parse on one payload, one file write; the leaf's siblings already do more.

## Validation (must pass before merge)
1. **Static — scorecard and emitter suites:** `bash loomwright/scripts/test-build-feature-scorecard.sh` passes with the fixture cases for both rows, the builder byte-identity guard and the no-public-claim grep; `bash loomwright/scripts/test-emit-qa-record.sh` passes, including the validator-skip mutant and the unknown-never-0 cases.
2. **Static — repo gates:** `bash scripts/ci-local.sh --affected` passes (including `check-doc-currency.sh` with the hook count unchanged, `test-retention-sweep.sh`, `test-hook-payload-contract.sh`, `test-result-validators.sh`, `check-test-hermetic.sh`); `bash scripts/check-version-bump.sh` passes with a `changelog.d/` fragment and no hand-edited version file.
3. **Running system — the first honest reading:** on the branch, `bash loomwright/scripts/build-feature-scorecard.sh --json` against this repo's real `.supervisor/` shows both rows with `runs_available 0` and `insufficient data` (zero verify runs and zero QA records exist on this machine today — the table's first true answer). Then one real qa-executor `SubagentStop` — `/qa-executor --plan` against a locally running app (the sports-management dev server is the owner's only baseline), or the probe recipe in CLAUDE.md §"Plugin Hooks" with a captured payload — produces one `logs/*-qa-result-*.md`, and a second scorecard run shows `qa_result` with `runs_available 1`. Both tables and the record's trailer line go in `docs/evidence/qa-lane-scorecard-first-reading.md` with `Verdict: PASS for Validation 3` at column 0, linked from the PR body; the numbers are not pasted into the PR body or any public surface.

## Depends on
none

## Touches
loomwright/docs/feature-scorecard.json
loomwright/scripts/test-build-feature-scorecard.sh
loomwright/scripts/emit-qa-record.sh
loomwright/scripts/test-emit-qa-record.sh
loomwright/hooks/hooks.json
loomwright/docs/HOOKS.md
loomwright/docs/ARCHITECTURE_CONTRACTS.md
loomwright/docs/result-schemas/qa-result.md
docs/evidence/qa-lane-scorecard-first-reading.md
changelog.d/qa-lane-scorecard-rows.md
