# 00 — QA evolution set: overview (index document, not an implementable item)

## Status: done (index document — nothing to implement)

## Why now

The owner (Vikash) asked, on 2026-11-09, for requirements that evolve the plugin's QA side. Standing owner rule: requirements are automated; implementation needs the owner's explicit approval — **not approved to build.** The owner's test for an item: it fixes a hole in code that has already shipped, or a failure confirmed on main. No market-news item without a baseline.

- **Where the code was read:** main `8ec200e` / plugin v17.35.1. This checkout sits on a feature branch with a live `/automate` run; nothing was executed against it beyond read-only helpers (`automate-helpers.sh right-size` / `plan-waves --lint` / `plan-waves --explain`), nothing was pushed, no git state changed. Beads is not active; everything is a file in this folder.
- **State of the QA side (verified 2026-11-09):**
  - `loomwright/docs/QA_SYSTEM_BLUEPRINT.md` §"Maturity Levels": Level 1 is built; L2–L5 are not. L4's "Supervisor Phase 3.5 QA Gate" does not exist — `agents/supervisor.md`, `skills/automate-loop/`, `skills/autonomous-loop/` contain no qa-executor or `/verify` call (only `verify-provides.sh`, an unrelated name).
  - The `/verify` lane (`.supervisor/requirements/verify-walkthrough/` items 01–07) is `## Status: done`; `operator-run/08-dogfood-on-real-app.md` is still pending; there are ZERO `.supervisor/verify/` run dirs under `~/Documents/work`. Shipped, never dogfooded.
  - `loomwright/docs/feature-scorecard.json` has no verify or QA row; `build-feature-scorecard.sh` is registry-as-data, read-only, fail-safe.
  - `docs/result-schemas/qa-session.md` schemas `plan.json` and `coverage.json`, but `coverage.json` is agent-maintained (`agents/qa-executor.md` `--scope` step 9; `skills/qa-orchestration/SKILL.md` §4 "Update rules"); `results/<scope>.json` has no schema; nothing validates any of the three or derives coverage (no script under `loomwright/scripts/` names `qa-session`). `validate-qa-result.py` validates the `QA_RESULT` block, not these files.
  - The one real-repo L1 run (owner-supplied, sports-management, 2026-03/04: 887 tests, 52 bugs / 25 blocking) exposed 16 results files with no two alike (5 without `status`), a `coverage.json` saying `completed` for a scope whose own file said `failed`, `apis_tested` 183 > `apis_total` 175, `.qa-summary.md` overwritten per scope, and 25 blocking bugs with NO consumer (`BUG-NC-001`, a DB column mismatch, unfixed five months later). Recorded here as owner-supplied, not fetched.
  - Consumers exist for `/verify` and not for QA: `propose-from-verify.sh` (`/propose --from-verify`), `read-verify.sh`, `verify-helpers.sh evidence-append` (sole writer, append-only, summary derived on every append — the pattern this set mirrors).
- **Premise correction found while writing (story 03):** the owner's note placed the hook-validated `QA_RESULT` block in `.supervisor/logs/`; verified 2026-11-09, none of the `.supervisor/logs/*.jsonl` files contains `QA_RESULT` — the qa-executor hook leaves persist only `token_ledger` / `agent_lifecycle` / `agent_identity` lines. Story 03 therefore adds a fail-safe record emitter (PO default, pending owner review) rather than registering a row with nothing to read.
- **No product context:** `.agent/product.json` is absent (`read-product.sh` emitted nothing), so the framing was taken from the brief and the repo. To record it once: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/propose-product.sh"` (propose-only; re-run with `--stance product|tool` and `--confirm`).

## Blueprint validity (checked 2026-11-09)

`loomwright/docs/QA_SYSTEM_BLUEPRINT.md` has ONE commit at its current path in this repo (`708ae41`, 2026-07-02, the rebrand carry-over); with `--follow`, its content was last substantively edited in `409f8a7` (2026-04-12, v10.3.0 topology auto-detection), and its maturity text says "v10.2.0". It never mentions `/verify` (two hits of the word, both the unrelated "Merge, Verify & Gate" / "Self-verification"), although `/verify` is now the plugin's main QA lane. It is still cited as authority by `agents/qa-strategist.md:522` and `skills/qa-strategy/SKILL.md:494` (and listed in `CLAUDE.md` §References and `README.md`); `scripts/check-doc-currency.sh` does not scan it.

- **Still valid:** dual-agent independence (executor vs. strategist audit); risk-based depth; the §"Governance & Safety Controls" limits table; the non-destructive security scope; the 14-module taxonomy as a map.
- **Stale or conflicting:** L4 "Supervisor Phase 3.5 QA Gate + `--skip-qa`" conflicts with CLAUDE.md's review-lane contract (advisory, never gating; two lenses, not four passes) — replaced by story 04 (advisory in-loop verify, in shadow). L5's own memory JSON schema is superseded by the sole-writer agent-memory proposals (v17.19.0; `agents/qa-executor.md` already follows it — `fb0ae5a`, 2026-10-27). L5 "production feedback batch import" (a CLI agent cannot monitor production) is superseded by the Studio event-trigger / on-call direction. "Estimated QA effort eliminated 60–95%" is unmeasured — no scorecard row (story 03 is the fix). The Level Transition KPIs assume gating.
- **Market (owner-supplied web research, 2026-11-09; recorded, not fetched, not queued):** Devin "Test the app" runs the app after the PR, shares the plan first, attaches a 15–45 s annotated recording, feature-scoped not regression (docs.devin.ai/work-with-devin/testing-and-recordings); Playwright ships planner / generator / healer Test Agents (playwright.dev/docs/test-agents), covering L3 flaky self-healing and much of L1 generation; Momentic / Octomind / QA Wolf / Meticulous own full-suite generation; Cursor's Agent SDK replays real PRs as eval fixtures; Shiplight ships a Claude Code plugin with a `/verify` skill (browser MCP + HTML report) — a plugin-level competitor. **Conclusion:** per-change verification with evidence on the PR is the market's QA shape; suite-generation depth is not where this plugin wins. Story 08 rewrites the blueprint around that.

## Owner decisions
- 2026-11-09 (Vikash, standing rule): **Not approved to build — requirements only.** Every story in this folder is `## Status: pending` and says so in its own Owner decisions.
- 2026-11-09 (Vikash, qa-evolution constraints, already decided — not reopened): NO new agent (`qa-executor` is the executor); Playwright from Bash only, no browser MCPs; QA/verify is advisory and NEVER gating (never a merge-gate condition — `gate-eval` / `merge-verdict` have exactly seven conditions and a sole executor); counts are derived, never agent-written; the plugin never touches credentials; mutations only in `--verify` mode after the non-prod assert; `/verify` state lives in `.supervisor/verify/`, never shared with `/automate`'s run file; `/automate` owns exactly ONE drain per item; no public claims about QA results; every new script gets a `test-*.sh`; every new or changed agent / command / skill file re-measures its entry in `loomwright/docs/prompt-token-budgets.json` plus the ARCHITECTURE_CONTRACTS.md mirror row; each PR carries a `changelog.d/<slug>.md` fragment.
- 2026-11-09 (Vikash, via the coordinating agent): blueprint re-validation recorded above; L2 depth and multi-round debate are REVISIT WHEN, L3 self-healing SUPERSEDED, L4 gate REJECTED, L5 memory schema and batch production feedback SUPERSEDED (table below).
- 2026-11-10 (Vikash): "Yes, add story 09" — electron first, then mobile through a driver seam; written as `09a` (Electron through Playwright `_electron`, dogfood = Loomwright Studio, P2) and `09b` (mobile through `verify-device.sh` + Maestro, iOS and Android simulators only, P3; supersedes archive batch C D1/D2). Approves WRITING, not building: both are `## Status: pending`, "Not approved to build — requirements only." Standing invariants unchanged: no new agent, Playwright-from-Bash only (the `Claude_Browser|computer-use|mcp__` guard stays at 0), advisory never gating, one writer/reader/executor for `.agent/verify.json`, PASS/FAIL only from `walk`'s ingest.

## Order

| # | Item | Delivers | Depends on | Priority |
|---|---|---|---|---|
| 1 | `01-qa-session-accounting-is-derived-never-agent-written.md` | `QA_SESSION_RESULT` schema for `results/<scope>.json` + `validate-qa-session-result.py` (CLI gate); `qa-session-helpers.sh` (`result-write` sole writer, `coverage-build`, `summary-build`); `coverage.json` and `.qa-session/summary.md` derived on every write; denominators reconciled against `plan.json`; `.qa-summary.md` untouched | none | **MVP** |
| 2 | `03-the-qa-lane-earns-its-cost-on-the-feature-scorecard.md` | registry rows `verify_result` (reads the derived `summary.md` counts row) and `qa_result` (reads a per-stop record); `emit-qa-record.sh` chained onto the existing qa-executor hook leaf (no new leaf); builder byte-identical | none | **MVP** |
| 3 | `07-exploratory-qa-runs-under-the-verify-environment-contract.md` | `/qa-executor` exploratory mode takes base URL + lifecycle from `.agent/verify.json` through `verify-env.sh` and runs the same fail-closed non-prod assert as `verify-run.sh preflight` (today Phase 3 DETECT URL reads `playwright.config` / `.env` and calls `*.vercel.app` `preview` with no proof) | none | **MVP** |
| 4 | `08-the-qa-blueprint-describes-the-two-lane-qa-system.md` | docs-only rewrite of the blueprint as two lanes (verification / exploratory) with measured next steps | none | **MVP** |
| 5 | `02-qa-findings-reach-a-consumer-propose-from-qa.md` | `/propose --from-qa` (`propose-from-qa.sh`): one evidence-carrying draft per BLOCKING / HIGH `REAL_BUG` id under `proposed/`, deduped across scopes and runs; `summary.md` `## Proposals`; auto-dispatch from `/qa-executor`'s command layer (PO default) | 01 | **MVP** |
| 6 | `04-verify-runs-inside-the-delivery-loop-in-shadow.md` | advisory `/verify` pass inside the `/automate` item loop, in shadow — the replacement for the blueprint's rejected L4 gate | none | **MVP** |
| 7 | `05-verify-can-target-a-pull-requests-preview-deployment.md` | `/verify` against a hosted per-PR preview when the app is not runnable locally | none | P2 |
| 8 | `09a-verify-targets-an-electron-app-through-playwright.md` | optional `target: web\|electron\|mobile` in `.agent/verify.json` (absent = web, byte-identical); `electron: {app_dir, build, launch_timeout_s?, env?}` replaces `base_url`/`health`; `base_url_matches` unusable on a non-web target; launch-from-source rule (`electron_app_dir_invalid`); `walk` launches through a generated `electron-fixture.mjs` (`_electron.launch`, `firstWindow()`), no `baseURL`; `propose-verify.sh --target electron …`; ingest/evidence/consumers unchanged; dogfood = Loomwright Studio | none | P2 |
| 9 | `09b-verify-walks-mobile-acceptance-criteria-through-a-device-driver.md` | `target: mobile` with a `mobile` object (ios\|android, driver `maestro`); new `verify-device.sh` (`doctor`, headless `start`/`stop`, `run` wrapping `maestro test --format junit`) + `test-verify-device.sh`; per-AC `specs/<ac_id>.flow.yaml`; `walk` ingests JUnit into the same `ac` lines; simulator/emulator only (`physical_device_refused`); visual-only ⇒ `NOT_VERIFIABLE needs_human_visual_signoff`; `flow_no_assertion` refused; supersedes archive D1/D2 | 09a | P3 |
| — | `operator-run/06-dogfood-qa-accounting-and-verify-on-a-real-app.md` | operator-run dogfood of the accounting fix and the in-loop verify pass on a real app; findings amend the items, never a new item | 01 (and 04 for the verify leg), by human ordering | operator-run |

**Why this order:** it is `plan-waves`' own wave order (below) — 01 first because 02 reads its validator and 07 shares `agents/qa-executor.md` with it; 03 and 07 and 08 are independent of each other but share the two doc hotspots with everything; 02 after 01; 04 and 05 late because they carry the largest verify-lane surfaces; 09a after 05 (it shares twelve of 05's fourteen files) and 09b last (declared dependency on 09a). Plain filename order (`--folder`) is also valid: the set's declared dependencies are 02 → 01 and 09b → 09a.

## Run

```
/automate --folder .supervisor/requirements/qa-evolution
```

- Mode: safe (no `--auto-merge`). **No `--parallel`** — N = 1. Not run here: nothing is approved. `--folder` lists `*.md` non-recursively and skips this file's `## Status: done` stamp; the `operator-run/` subfolder IS the skip mechanism for 06. `/automate --backlog .supervisor/requirements/qa-evolution/00-overview.md` reads the Checklist below in the same order.
- `plan-waves --lint .supervisor/requirements/qa-evolution` (2026-11-10, with all nine stories present): every item `Touches ok; Depends on ok`; `0 of 9 items will run alone: none`; `0 of 9 items depend on every earlier item: none`.
- `plan-waves --explain --max 9 .supervisor/requirements/qa-evolution` (2026-11-10, directory = filename order): nine waves of one — `wave 1: 01 · wave 2: 02 · wave 3: 03 · wave 4: 04 · wave 5: 05 · wave 6: 07 · wave 7: 08 · wave 8: 09a · wave 9: 09b`. `09a` waits on 01, 02, 03, 04, 05, 07, 08 (every one on a declared shared file — the two doc hotspots, `agents/qa-executor.md` (01, 05, 07), `commands/verify.md` (04, 05), `verify-run.sh` / `test-verify-walkthrough.sh` / `skills/verify-walkthrough/SKILL.md` (04, 05), `read-verify.sh` / `test-verify-seam.sh` / `result-schemas/verify-env.md` (05, 07), `verify-env.sh` / `propose-verify.sh` / `result-schemas/verify-evidence.md` (05)); `09b` waits on `09a` (declared dependency). Every later item waits on a declared shared file or a declared dependency, never on an unknown.
- `plan-waves --explain` (2026-11-09, `--max 7`, Checklist order, before 09a/09b existed): seven waves of one — `wave 1: 01 · wave 2: 03 · wave 3: 07 · wave 4: 08 · wave 5: 02 · wave 6: 04 · wave 7: 05`. The serialisations:
  - `03 waits on 01`: both edit `loomwright/docs/ARCHITECTURE_CONTRACTS.md`.
  - `07 waits on 01, 03`: `agents/qa-executor.md`, `prompt-token-budgets.json`, `ARCHITECTURE_CONTRACTS.md` (01); `ARCHITECTURE_CONTRACTS.md`, `result-schemas/qa-result.md` (03).
  - `08 waits on 01, 03, 07`: `ARCHITECTURE_CONTRACTS.md`, `prompt-token-budgets.json`.
  - `02 waits on 01` (declared dependency) and on 03, 07, 08: `ARCHITECTURE_CONTRACTS.md`, `prompt-token-budgets.json`, `commands/qa-executor.md` (07), `README.md` (08).
  - `04 waits on 01, 03, 07, 08, 02`: `ARCHITECTURE_CONTRACTS.md`, `prompt-token-budgets.json`, `QA_SYSTEM_BLUEPRINT.md` (08).
  - `05 waits on everything`: the two doc hotspots plus `agents/qa-executor.md` (01, 07), `read-verify.sh` / `test-verify-seam.sh` / `result-schemas/verify-env.md` (07), `commands/verify.md` / `verify-run.sh` / `test-verify-walkthrough.sh` / `skills/verify-walkthrough/SKILL.md` (04).
- **Why N = 1:** every prompt edit must re-measure `prompt-token-budgets.json` and its ARCHITECTURE_CONTRACTS.md mirror row in the same change (`check-token-budget.sh` fails CI closed), so the two files are shared by six of seven items by necessity, not by sloppiness; a wave merges as one PR, and two lanes editing adjacent JSON entries collide. No path was dropped to widen a wave.
- **Hotspots** (declared by several items; each wave has one owner since N = 1): `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (all nine); `loomwright/docs/prompt-token-budgets.json` (all but 03); `loomwright/agents/qa-executor.md` (01, 05, 07, 09a, 09b); `loomwright/commands/qa-executor.md` (02, 07); `loomwright/docs/result-schemas/qa-result.md` (03, 07); `README.md` (02, 08); `loomwright/docs/QA_SYSTEM_BLUEPRINT.md` (04, 08); the verify-lane files (04, 05, 07, 09a, 09b — `09a` shares twelve of `05`'s fourteen files; `09b` shares fourteen of `09a`'s); `loomwright/skills/qa-strategy/SKILL.md` (09b only).
- **Proposed companions rule (owner adds; never written here):** `.agent/companions.json` already adds the two doc hotspots for `loomwright/agents/*.md`. The same coupling holds for command and skill prompts, so the matching rules are `{"when": "loomwright/commands/*.md", "add": ["loomwright/docs/prompt-token-budgets.json", "loomwright/docs/ARCHITECTURE_CONTRACTS.md"]}` and `{"when": "loomwright/skills/*/SKILL.md", "add": [the same two]}` — so a story that forgets to declare them still collides visibly at plan time.
- `right-size` (advisory, 2026-11-09) for the three stories this agent wrote: `01: ok (12 files, 9 scope items, 16 criteria)` · `02: ok (15 files, 9 scope items, 15 criteria)` · `03: ok (10 files, 8 scope items, 15 criteria)`. Stories 04, 05, 07, 08 and operator-run/06 were written by the sibling PO agents, who report their own lines. 2026-11-10: `09a: ok (14 files, 15 scope items, 16 criteria)` · `09b: ok (17 files, 16 scope items, 18 criteria)`.

## Assumption Check flags (recorded; PO-ASSUME gate NOT answered)

This agent ran as a subagent (no `AskUserQuestion`), under the coordinator's instruction to record defaults and proceed — the batches A–H precedent — so the stories are persisted with their flags recorded instead of the can't-ask `po_gate: needs_owner` stop. Each flag is also a "PO default, pending owner review" line in the story it belongs to.

- **Prerequisite (03):** no `QA_RESULT` record exists on disk (verified above). Story 03 Part B adds `emit-qa-record.sh`; without it the `qa_result` row is `record: none` on the `needs_emitter` list.
- **Prerequisite (02):** depends on 01's `validate-qa-session-result.py` and `summary-build` — declared in `## Depends on`.
- **Prerequisite (data):** zero verify runs and zero QA records exist on this machine, so both scorecard rows read `insufficient data` until five runs exist (`min_sample`); operator-run/06 and `verify-walkthrough/operator-run/08` produce the first records.
- **Architecture conflicts:** none. Nothing gates; the sole-executor invariant and the seven gate conditions are untouched; the hook leaf count is unchanged (03 chains onto the qa-executor matcher's existing fan-out leaf); every new emitter is fail-SAFE (exit 0) and every validator used as a gate is fail-CLOSED (`validator_unavailable` refuses).
- **House-rule conflicts:** none. Three advisory rules apply (`read-rules.sh --with-ids`, 2026-11-09) and are honoured: no literal count is restated (03 avoids a new hook leaf for that reason); every restated list moves in the same change (ARCHITECTURE_CONTRACTS.md rows, `HOOKS.md` row, the `/propose` basis table and its restatements in `README.md`, `knowledge.md`, `capabilities.json`, `propose-common.sh`); wording that carries a contract (`.qa-summary.md`'s audit role) is kept byte-identical.
- **Contract-change flag (01):** the owner's note named `.qa-summary.md` as the cumulative file; it is the QA Strategist's audit input (≤200 tokens). PO default: keep it, derive `.qa-session/summary.md` instead. Pending owner review.
- **Missing proof:** none — every story has Static and Running-system Validation entries.

## Already exists (summary; anchors in the stories)

- Verify store: `verify-helpers.sh` (`evidence-append` sole writer, `summary-build` sole deriver, `derived_from:` trailer), `validate-verify-evidence.py` (CLI gate), `summary.md` counts row and `## Run end` line; `propose-from-verify.sh` + `propose-common.sh` (`pc_guarded_write`, `pc_slugify`); `/verify` auto-dispatches `--from-verify` at its Report step.
- Scorecard: `feature-scorecard.json` registry (formats `result_block | text | json | tsv`; one file = one run; one field per feature; ledger cost by agent-type suffix; `unknown` never 0); `test-build-feature-scorecard.sh` (8) reads the real registry's ids dynamically; `/propose --from-scorecard` drafts for `review:` rows.
- Hooks: qa-executor `SubagentStop` matcher runs `validate-qa-result.py` + a `payload=$(cat)` fan-out to `send-telemetry.sh` and `emit-token-ledger.sh`; `check-doc-currency.sh` counts leaves and checks the hook-count claims.
- QA session: `qa-session.md` schemas for `plan.json` / `coverage.json` with unenforced validation rules; `/backlog` lists `proposed/` files as items.

## Overlaps with existing code and requirements (consolidated)

| Existing | This set |
|---|---|
| `verify-walkthrough/00-overview.md` decisions V3 (FAIL → `proposed/` draft) and V5 (own store, derived summaries) | 01 and 02 apply the same two decisions to the QA lane; nothing in the verify queue is edited |
| `2026-11-01-092116-feature-scorecard-shows-which-features-earn-their-cost.md` (shipped v17.25.0) | 03 adds two registry rows and one emitter; the builder is byte-identical |
| `verify-walkthrough/operator-run/08-dogfood-on-real-app.md` (pending) | operator-run/06 dogfoods this set; 08 stays the verify-lane dogfood — the operator may run both in one session on the same app |
| `archive-approved/05-gate-verdict-mode-judges-any-pr-head-without-merging.md` | the MCP exposure of gate + verify waits for it (not queued) |
| Sibling stories 04 / 05 / 07 / 08 | shared hotspots listed under `## Run`; 07 and 01 both edit `agents/qa-executor.md`; 04 and 08 both edit the blueprint |

No existing requirement file was edited.

## Open questions (index; full text in the stories)

- OQ-Q1 (01): cumulative report in derived `.qa-session/summary.md`, `.qa-summary.md` untouched — or re-point the Strategist (separate item).
- OQ-Q2 (01): `plan.json` scope statuses not rewritten; `--continue` reads derived `scopes_remaining`.
- OQ-Q3 (02): QA drafts write `## Touches` `unknown` (the fix site is app code the results file does not name).
- OQ-Q4 (02): `/qa-executor`'s command layer auto-dispatches `/propose --from-qa` on `bugs_blocking ≥ 1` or a HIGH bug.
- OQ-Q5 (02): dedupe key is the agent-assigned bug id; renumbering yields a duplicate (dismissal token is the tool).
- OQ-Q6 (03): `verify_result` reads the derived `summary.md` counts row with the existing `text` format; the alternative is a new `jsonl` format (a builder change).
- OQ-Q7 (03): the shared `qa-executor` ledger seat — `verify_result` carries it, `qa_result` is `cost: none`.
- OQ-Q8 (03): the derived `qa_lane:` trailer vs. a relaxed any-severity `caught`.
- OQ-Q9 (03): record location `.supervisor/logs/` vs. a new `.supervisor/qa/` dir (retention row + contracts row).
- OQ-Q10 (03): `ran` for verify = at least one ticket-scope AC verdicted.
- OQ-Q11 (set): operator-run/06 after 01 (and 04) is a human ordering `--lint` cannot see; the operator runs it when those have merged.

## Considered and not queued

| Candidate | Status | Revisit when |
|---|---|---|
| L2 depth — state modeling, journey graphs, fuzz — and the full multi-round debate | **REVISIT WHEN** | ≥2 more real-repo L1 runs exist (blueprint KPI "L1 tested on 2–3 real repos"; one exists) AND story 02's drafts show the exploratory lane finding bugs the verification lane misses; a measured miss rate for debate |
| L3 flaky analyzer + self-healing | **SUPERSEDED** | Playwright ships planner / generator / healer Test Agents (owner-supplied research); no measured flake cost here either way |
| L4 Supervisor Phase 3.5 QA Gate + `--skip-qa` | **REJECTED** | conflicts with CLAUDE.md's review-lane contract (advisory, never gating; two lenses); story 04 replaces it |
| L5 agent-memory JSON schema | **SUPERSEDED** | sole-writer agent-memory proposals (v17.19.0; `fb0ae5a`) |
| L5 production feedback batch import | **SUPERSEDED** | the Studio event-trigger / on-call direction; revisit when Studio phases 6 / 9 ship |
| Desktop / simulator `/verify` driver | **QUEUED 2026-11-10** as `09a` (Electron) and `09b` (mobile) | the owner deferred archive batch C Android D1 / D2 on 2026-11-09 ("only if a project needs mobile verify"); on 2026-11-10 Loomwright Studio (Electron) became that project, so `09a` is queued at P2 and `09b` absorbs D1 / D2 at P3 (Maestro replaces the hand-rolled `adb` driver; iOS added; `doctor`, emulator-only and visual-signoff rules carried over) |
| Security-scan → fix-PR queue source (Devin Security 2.0 parity) | deferred | a threat model exists first |
| On-call loop | deferred | Studio event triggers exist |
| Exposing gate + verify over MCP | deferred | after `archive-approved/05-gate-verdict-mode-judges-any-pr-head-without-merging.md` lands (owner) |
| Best-of-N judged by Rubric Grader + `/verify` | deferred | a P1 proposal; a separate owner decision |
| `ci-local --affected` map-completeness check for the plugin's own self-tests (193 `test-*.sh` by the owner's count on 2026-11-09) | deferred | hygiene, a different lane |
| Market items (Devin recordings, Playwright Test Agents, suite-generation vendors, Cursor eval replay, Shiplight `/verify`) | recorded, not queued | owner rule: no market-news item without a baseline; the baseline is what 03 and operator-run/06 produce |

## Revisit when

- Two more real-repo L1 runs exist and story 02's drafts can be compared against `/verify` FAILs (the L2 question).
- operator-run/06 (and `verify-walkthrough/operator-run/08`) report findings: amend the affected stories here, never a new item.
- The two scorecard rows reach `min_sample` (five runs): read the first real catch rates before any further QA investment.
- `archive-approved/05` lands: reopen the MCP exposure question.
- Studio phases 6 / 9 ship: reopen the on-call loop and production-feedback direction.
- A project with a mobile ticket is queued (a Flutter app or Block Paradise): approve `09b`; until then it stays P3 behind `09a`. A second driver (mobile-mcp, Callstack agent-device, Appium) or a desktop-native (non-Electron) app: a new `driver` / `target` enum value behind the same seam, a separate item.

## Checklist
- [ ] .supervisor/requirements/qa-evolution/01-qa-session-accounting-is-derived-never-agent-written.md
- [ ] .supervisor/requirements/qa-evolution/03-the-qa-lane-earns-its-cost-on-the-feature-scorecard.md
- [ ] .supervisor/requirements/qa-evolution/07-exploratory-qa-runs-under-the-verify-environment-contract.md
- [ ] .supervisor/requirements/qa-evolution/08-the-qa-blueprint-describes-the-two-lane-qa-system.md
- [ ] .supervisor/requirements/qa-evolution/02-qa-findings-reach-a-consumer-propose-from-qa.md
- [ ] .supervisor/requirements/qa-evolution/04-verify-runs-inside-the-delivery-loop-in-shadow.md
- [ ] .supervisor/requirements/qa-evolution/05-verify-can-target-a-pull-requests-preview-deployment.md
- [ ] .supervisor/requirements/qa-evolution/09a-verify-targets-an-electron-app-through-playwright.md
- [ ] .supervisor/requirements/qa-evolution/09b-verify-walks-mobile-acceptance-criteria-through-a-device-driver.md
- .supervisor/requirements/qa-evolution/operator-run/06-dogfood-qa-accounting-and-verify-on-a-real-app.md — operator-run, deliberately NOT a checkbox: `resolve-backlog` enqueues every `- [ ]` line that names an existing file regardless of its stamp, and `--folder` never descends into `operator-run/`.
