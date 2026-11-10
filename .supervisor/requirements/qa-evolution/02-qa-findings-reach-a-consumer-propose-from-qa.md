# QA findings reach a consumer: /propose --from-qa

## Status: pending

Source: `/product-owner` qa-evolution set, 2026-11-09, read against main `8ec200e` / v17.35.1. Plan doc: `00-overview.md` in this folder.

**As the** owner (Vikash), who watched a QA campaign find 25 blocking bugs on a real app and one of them stay open for five months,
**I want** every BLOCKING or HIGH `REAL_BUG` a QA campaign records to become an evidence-carrying draft under `.supervisor/requirements/proposed/`, one per bug id across scopes and runs,
**so that** `/backlog` lists them beside every other candidate and I can promote the ones I choose into an `/automate` queue with one `mv`, instead of the finding dying in a results file nothing reads.

### Problem (read on main `8ec200e`)

- **QA has no consumer.** `grep -rn "qa-executor\|/verify" loomwright/agents/supervisor.md loomwright/skills/automate-loop loomwright/skills/autonomous-loop` finds no QA or verify call (only `verify-provides.sh`, an unrelated name). `loomwright/commands/qa-executor.md` is a Task-spawn wrapper; the `QA_RESULT` block returns to the spawning session and stops there. The only reader of `.qa-session/results/*.json` is the executor itself (`agents/qa-executor.md` §"Phase 1", `--scope` step 5, the cross-scope regression check).
- **The verify lane already has the consumer this story mirrors.** `loomwright/scripts/propose-from-verify.sh` (`/propose --from-verify <run_id>`) reads exactly one surface, writes one draft per qualifying line with a filename that is a pure function of its inputs, cites the evidence line and artifacts, writes only through `pc_guarded_write` from `propose-common.sh`, and always exits 0. `commands/propose.md` states the shared contract: `proposed/` is deliberately NOT an `/automate --folder` target, promotion is a human moving a file, every draft carries `## Depends on` and `## Touches`, and a token line in a `## Status: done` file is the durable dismissal (checked by the ledger and domain bases, not by the verify basis). `/verify` auto-dispatches the basis at its Report step on ≥1 FAIL (`commands/propose.md` §"See Also").
- **`/backlog` already lists `proposed/` files as items** (`commands/backlog.md` §"The item set"), so a draft written there is visible with no `/backlog` change.
- **Owner-supplied evidence** (the owner's memory notes; recorded as supplied): `BUG-NC-001` — `POST /api/chats` inserting `creatorId` / `description` / `teamId` where the migration defines only `createdById` — was found on 2026-04-06 and was still unfixed on 2026-09-08, because nothing consumed it.
- **The results files it reads are schema'd by story 01**, whose `validate-qa-session-result.py` is the gate and whose `summary-build` derives `.qa-session/summary.md`.

### Scope

- New `loomwright/scripts/propose-from-qa.sh [<session_dir>]` (default `.qa-session`): the QA basis of `/propose`. Sources `propose-common.sh` (never copies the guard). For every `results/*.json` it runs `validate-qa-session-result.py` and **skips an invalid file by name** on stderr — it never drafts from a file that failed the gate and never guesses a missing field. It never reads `coverage.json`, `summary.md` (derived, lossier) or `results/superseded/`.
- **One draft per BLOCKING or HIGH `REAL_BUG` id.** `MEDIUM` / `LOW` bugs and every `DISCOVERY_GAP` / `ENVIRONMENT_ISSUE` entry are never drafted (the run's problem, not the app's; the summary lists them). The filename `qa-<bug_id>-<slug>.md` is a pure function of the id and its title: the same id recorded in two scopes or two runs yields ONE file whose `## Evidence` lists every results file that carries it; a re-run against an unchanged session rewrites byte-identical content through the same guard.
- **Durable dismissal:** an `evidence-set: qa/<bug_id>` line in any file stamped `## Status: done` under `.supervisor/requirements/` suppresses that draft, and the suppression is reported with the file that caused it (the ledger / domain convention).
- **Draft shape** (deterministic — no timestamps, no `$RANDOM`): `# Proposed: QA bug <id> (<severity>)`; the `evidence-set: qa/<bug_id>` token line; `## Depends on` `none`; `## Touches` `unknown`; `## Problem` (title, `classification: REAL_BUG`, severity, route or API); `## Evidence` (each results file path with the bug's `bugs[n]` position and the physical line of its `"id"`, the scope, the failing spec file, the reproduction steps, `report_path`, and the session's `plan.json` `app_url` and `created` date); `## Suggested acceptance` (the named spec passes against the named route or API); `## Status: proposed`.
- **Writes only** under `PROPOSE_FROM_QA_OUT_DIR` (default `.supervisor/requirements/proposed`) through `pc_guarded_write`; `set -uo pipefail`, no `set -e`, a `jq` guard that skips, exit 0 always. It never enqueues, dispatches, ranks, merges, pushes or calls the GitHub CLI.
- `qa-session-helpers.sh summary-build` (story 01) gains a `## Proposals` section computed from `results/` alone — "N draft(s) expected (`qa-<id>-*`) — run `/propose --from-qa`" with the qualifying ids, or the no-draft sentence — so the summary states the truth whether or not this script has run (the verify `## Proposals` precedent).
- `commands/propose.md`: a **QA** row in the basis table (`--from-qa [<session_dir>]`, surface `.qa-session/results/*.json`, "a QA campaign's BLOCKING / HIGH REAL_BUGs", class derived-from-validated-files); the flag row; `PROPOSE_FROM_QA_OUT_DIR` in the env table; a "What the qa basis does" section; the dismiss paragraph's token list; See Also. One basis per invocation — mutually exclusive with every other basis flag.
- `commands/qa-executor.md`: after the spawned executor returns a `QA_RESULT` whose `bugs_blocking ≥ 1` or whose `bugs[]` carries a `HIGH` entry, the command layer runs `/propose --from-qa` and prints the drafts written — the `/verify` Report-step pattern (PO default below).
- Surfaces that restate the basis list are updated in the same change: `README.md` (`/propose` row), `loomwright/docs/command-parts/agent-help/knowledge.md` (`/propose` entry), `loomwright/capabilities.json` regenerated with `build-capabilities.sh` (its `--check` is `test-build-capabilities.sh` (C)), and the basis lists in the header comments of `propose-common.sh` and `test-propose-common.sh`. Budgets re-measured for `.commands["propose"]` and `.commands["qa-executor"]` with the ARCHITECTURE_CONTRACTS.md mirror rows.

## Acceptance Criteria

Every case builds its session dir and its `.supervisor/requirements/` tree under the test's `mktemp -d` root (hermetic: `scripts/check-test-hermetic.sh`); results files are valid under story 01's schema unless a case says otherwise. One fixture is the owner-supplied `BUG-NC-001` shape (`POST /api/chats`, BLOCKING, a spec and three steps).

**The basis (Test: `loomwright/scripts/test-propose-from-qa.sh`)**
- [ ] **One draft per BLOCKING / HIGH id:** a session with three valid results files carrying `BUG-A` (BLOCKING), `BUG-B` (HIGH), `BUG-C` (MEDIUM), `BUG-D` (LOW), one `DISCOVERY_GAP` and one `ENVIRONMENT_ISSUE` entry writes exactly `qa-BUG-A-*.md` and `qa-BUG-B-*.md` and nothing else. Test: `test-propose-from-qa.sh`.
- [ ] **Dedupe across scopes and runs:** `BUG-A` recorded in two scopes' files yields one draft whose `## Evidence` names both files, each with its `bugs[n]` position and the physical line of `"id": "BUG-A"` (the test's `sed -n <line>p` on each cited line contains the id). A second run against the unchanged session changes no byte and adds no file. Test: `test-propose-from-qa.sh`.
- [ ] **Invalid files are skipped by name:** a results file with no `status` (story 01's `missing_key:status`) that carries a BLOCKING bug produces no draft and one stderr line naming the file and the reason; the other files' drafts are still written. A mutant that drops the validator call drafts that bug and fails this case. Test: `test-propose-from-qa.sh`.
- [ ] **One surface:** a malformed `coverage.json`, a `summary.md` naming a bug no results file has, and a `results/superseded/<scope>.<ts>.json` carrying a BLOCKING bug change nothing — no draft from them, no error. Test: `test-propose-from-qa.sh`.
- [ ] **Durable dismissal:** a `## Status: done` file under the fixture `.supervisor/requirements/` carrying `evidence-set: qa/BUG-A` suppresses `qa-BUG-A-*.md`, and stderr names that file; the same token in a `## Status: pending` file suppresses nothing. Test: `test-propose-from-qa.sh`.
- [ ] **The draft carries what a promoter needs:** `# Proposed: QA bug <id> (<severity>)`, the token line, `## Depends on` `none`, `## Touches` `unknown`, the `## Problem` fields, every `## Evidence` item listed in Scope (results path, `bugs[n]`, id line, scope, spec, steps, `report_path`, `app_url`, `created`), `## Suggested acceptance` naming the spec, `## Status: proposed`. A mutant that drops the `## Evidence` section fails this case (the verify basis AC12 precedent). Test: `test-propose-from-qa.sh`.
- [ ] **Lint-clean drafts:** every written draft passes `bash loomwright/scripts/automate-helpers.sh plan-waves <draft> --lint`. Test: `test-propose-from-qa.sh`.
- [ ] **Blast radius:** nothing outside the output directory changes (a `find -newer` sentinel over the fixture root); with the guard removed from a COPY of `propose-common.sh` reached through `PROPOSE_COMMON_SH`, the write goes through unguarded and the test's control detects it (the `test-propose-common.sh` convention); an uncreatable output directory writes nothing and exits 0. Test: `test-propose-from-qa.sh`.
- [ ] **Fail-safe:** `jq` missing, no session dir, an empty `results/`, or a session with only MEDIUM / LOW bugs each give one stderr line, nothing written, no `proposed/` created, exit 0. Test: `test-propose-from-qa.sh`.
- [ ] **Output safety:** a bug title holding a backtick, `|`, `"`, `-->` or a newline yields one well-formed draft with a filesystem-safe slug (`pc_slugify`). Test: `test-propose-from-qa.sh`.
- [ ] **Never a queue, never a gate:** `propose-from-qa.sh` holds no GitHub CLI invocation, no git network verb (no push, no fetch), no `runfile-write`, `queue-`, `/automate` or `lane-` call (a grep guard), and every draft is stamped `## Status: proposed` so `/automate`'s folder and backlog intake skip it. Test: `test-propose-from-qa.sh`.

**The summary and the command surfaces**
- [ ] `qa-session-helpers.sh summary-build` prints `2 draft(s) expected` naming `BUG-A` and `BUG-B` for the fixture session, and the no-draft sentence for a session with only MEDIUM / LOW bugs. Test: `loomwright/scripts/test-qa-session-helpers.sh` (story 01's suite gains the case).
- [ ] `commands/propose.md` has the QA basis row, the `--from-qa` flag row, `PROPOSE_FROM_QA_OUT_DIR`, the "What the qa basis does" section and the `qa/<bug_id>` token in the dismiss paragraph; `commands/qa-executor.md` names the auto-dispatch condition (`bugs_blocking ≥ 1` or a HIGH bug); `README.md` and `knowledge.md` name `--from-qa` in their `/propose` entries. Test: `bash scripts/check-doc-currency.sh` and a grep of each file for `--from-qa`.
- [ ] `bash loomwright/scripts/build-capabilities.sh --check` exits 0 on the committed `loomwright/capabilities.json`; `bash scripts/check-token-budget.sh` passes with the re-measured `propose` and `qa-executor` command entries and their mirror rows. Test: `test-build-capabilities.sh`, `check-token-budget.sh`.
- [ ] `test-propose-common.sh` passes with the new basis named in both header comments and sourcing the shared guard (the grep in that test that lists callers, if present, includes `propose-from-qa.sh`). Test: `test-propose-common.sh`.

## Non-goals
- Drafting MEDIUM / LOW bugs, `DISCOVERY_GAP` or `ENVIRONMENT_ISSUE` entries (summary only).
- Fixing a bug, enqueueing a draft, promoting it, opening a GitHub issue, commenting on a PR, or sending telemetry about it.
- Any gate: nothing here enters `gate-eval` / `merge-verdict`, Phase 4.5 or the drain; `/automate` keeps exactly one drain per item and this basis never dispatches anything.
- Running QA inside `/automate` or Supervisor (stories `04-*.md` / `05-*.md` of this set, by filename only).
- A `## Touches` guess for the app's fix site (PO default below) or a `/backlog` change (it already lists `proposed/`).
- A second copy of the Touches-extraction grammar: the QA draft writes `unknown`, so no fourth copy of the `PW_TOUCHES_GRAMMAR` extractor is added.

## Owner decisions
- 2026-11-09 (Vikash, standing rule): **Not approved to build — requirements only.** Implementation needs the owner's explicit approval.
- 2026-11-09 (Vikash, qa-evolution constraints): NO new agent; QA/verify is advisory and NEVER gating (never a merge-gate condition); `/automate` owns exactly ONE drain per item; no public claims about QA results; every new script gets a `test-*.sh`; every changed command file re-measures its `prompt-token-budgets.json` entry plus the ARCHITECTURE_CONTRACTS.md mirror row; the PR carries a `changelog.d/<slug>.md` fragment.
- 2026-11-09 (Vikash, in the brief): mirror `propose-from-verify.sh`; read the schema'd results files from story 01; draft each BLOCKING / HIGH `REAL_BUG`; dedupe by bug id across runs; a draft names the failing spec, the route or API, the reproduction, the results file and line.
- PO default, pending owner review (`## Touches` in a QA draft): `unknown`. The fix site is app code the results file does not name — the spec is the test, not the change site — and `commands/propose.md` already tells the promoter to replace `unknown` before promoting. Guessing from a spec path would mislead the planner.
- PO default, pending owner review (auto-dispatch): `/qa-executor`'s command layer runs `/propose --from-qa` when the returned `QA_RESULT` has `bugs_blocking ≥ 1` or a HIGH bug — the `/verify` Report-step pattern. The owner may prefer manual-only; then the `commands/qa-executor.md` edit and its budget re-measure drop out.
- PO default, pending owner review (dedupe key): the agent-assigned bug `id`. A re-run that renumbers its bugs yields a second draft for the same defect; the durable-dismissal token is the owner's tool for that case, and a content fingerprint is a later tightening.
- PO default, pending owner review (evidence fields): the draft carries `app_url` and `created` from `plan.json`. Drafts are project-local files under the gitignored `.supervisor/`; nothing here is telemetry, so the plugin-facts-only egress rule is not engaged.

## Priority: MVP
**Rationale:** the owner's test is met by a confirmed failure in shipped code — 25 blocking bugs with no consumer, `BUG-NC-001` open for five months. This is the missing half of story 01: a trustworthy results file is still worthless if nothing reads it.

## Assumptions
- Story 01's schema requires a non-empty `bugs[].id`, `classification`, a `severity` on every `REAL_BUG`, `spec`, `steps[]` and `report_path`; this basis reads those keys and nothing the schema does not promise.
- Bug ids are stable within a campaign (Phase 13 STEP 2 assigns them per run; nothing enforces stability across re-runs — named under Owner decisions).
- `/backlog` needs no change: `commands/backlog.md` lists `proposed/` files as items; a QA draft shows there with the `proposed` state like every other draft.
- A new `loomwright/scripts/test-*.sh` is picked up by CI's and `ci-local.sh`'s globs with no registration.
- Right-size (advisory, run 2026-11-09): `qa-evolution/02-qa-findings-reach-a-consumer-propose-from-qa: ok (15 files, 9 scope items, 15 criteria)`.

## Dependencies
- Depends on: `01-qa-session-accounting-is-derived-never-agent-written.md` (the results schema, `validate-qa-session-result.py`, `qa-session-helpers.sh summary-build`).
- Blocks: none in this set; `04-*.md` / `05-*.md` may cite the drafts as the sink for in-loop QA findings.

## Risks
- **A draft flood on a buggy app** (25 blocking on the baseline). Mitigation: one file per id, deterministic names, `/backlog` lists them in one state; the owner promotes a few, dismisses the rest with the token.
- **A misclassified `REAL_BUG`** (a weak test) becomes a draft. Mitigation: the draft cites the spec and the steps so the promoter can judge; nothing runs until a human moves the file.
- **Id renumbering** across re-runs produces a duplicate. Mitigation: named limit; the dismissal token; a fingerprint later.
- **Two command docs change** (`propose.md`, `qa-executor.md`): mirror drift between agent and command prose (memory `agent-command-mirror-drift-on-fixes`). Mitigation: no agent flag changes here; only command-layer prose, re-measured.

## Validation (must pass before merge)
1. **Static — basis suite:** `bash loomwright/scripts/test-propose-from-qa.sh` passes, including the validator-skip mutant, the Evidence-section mutant and the guard mutant; `bash loomwright/scripts/test-qa-session-helpers.sh` passes with the `## Proposals` case; `bash loomwright/scripts/test-propose-common.sh` passes.
2. **Static — repo gates:** `bash scripts/ci-local.sh --affected` passes (including `test-build-capabilities.sh`, `check-token-budget.sh`, `check-doc-currency.sh`, `check-test-hermetic.sh`); `bash scripts/check-version-bump.sh` passes with a `changelog.d/` fragment and no hand-edited version file.
3. **Running system — the baseline bug becomes a draft:** against a session dir built from the `BUG-NC-001` fixture, `bash loomwright/scripts/propose-from-qa.sh <dir>` writes one `qa-BUG-NC-001-*.md`; `automate-helpers.sh plan-waves <draft> --lint` prints `ok (declared unknown)`; `automate-helpers.sh item-state <draft>` reports the `proposed` state; the draft's text and both command outputs go in `docs/evidence/propose-from-qa-first-draft.md` with `Verdict: PASS for Validation 3` at column 0, linked from the PR body.

## Depends on
01-qa-session-accounting-is-derived-never-agent-written.md

## Touches
loomwright/scripts/propose-from-qa.sh
loomwright/scripts/test-propose-from-qa.sh
loomwright/scripts/qa-session-helpers.sh
loomwright/scripts/test-qa-session-helpers.sh
loomwright/scripts/propose-common.sh
loomwright/scripts/test-propose-common.sh
loomwright/commands/propose.md
loomwright/commands/qa-executor.md
loomwright/docs/command-parts/agent-help/knowledge.md
loomwright/capabilities.json
loomwright/docs/prompt-token-budgets.json
loomwright/docs/ARCHITECTURE_CONTRACTS.md
README.md
docs/evidence/propose-from-qa-first-draft.md
changelog.d/propose-from-qa.md
