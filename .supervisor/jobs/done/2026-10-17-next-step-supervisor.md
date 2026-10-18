# Supervisor Job: next-step driver for Supervisor Phases 0–4 (supervisor-next-step.sh)

## Environment
- **Project:** automate-2026-10-15-163325/L11 (lane L11 clone of the loomwright repo)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (lane clone: out-of-scope findings go to `.supervisor/requirements/proposed/`, never a new Queue item)
- **Source requirement:** .supervisor/requirements/automate-speed/11-next-step-supervisor.md
- **Base commit:** a8819a38100d77fbeddc2ff1a56963e91f172a5d

## Owner decision (scope split — recorded 2026-10-17, Launch Pad Phase 2 clarification, lane L11)
The requirement's AC "supervisor-group GAP count is 0" cannot be met: `loomwright/docs/loop-inventory/supervisor.md` has 542 GAP rows at base (`## Counts`), of which 248 are `deterministic` and the rest `rule` / `judgment` / `story` rows no golden case covers. The owner chose **"Split: Phases 1–4 now"**:
- **This PR:** a `supervisor-next-step.sh` driver owns the deterministic phase sequencing, Phase Flags, Context-Keeper record calls and FINALIZE checklist steps of Supervisor Phases 0, 1, 1.5, 2, the Supervisor-side routing of Phase 3, and Phase 4, with golden fixtures for those rows; the migrated prose moves out of the default read path; the rows are re-homed.
- **Phase 4.5** (the self-heal loop counter, round bookkeeping, completion tail — 106 deterministic GAP rows, 77 of them in `skills/self-heal-advisory/SKILL.md`) is filed as a propose-only follow-up, `.supervisor/requirements/proposed/automate-speed-11b-next-step-supervisor-phase45.md` (already written by Launch Pad; rides this lane's metadata push). The requirement's own split rule ("split it into Phases 1–4 and Phase 4.5 items") names exactly this cut.
- **GAP AC, as scoped by the owner:** every migrated row is linked to its golden case / driver test; the supervisor GAP count before (542) and after is reported; the residual is named by kind, never faked.

## Feasibility
**Verdict:** CAUTION

| # | Check | Verdict | Detail |
|---|---|---|---|
| 1 | Tech Stack Compatibility | GO | bash 3.2 + BSD userland + jq, the same as `automate-next-step.sh` and every `loomwright/scripts/*.sh` |
| 2 | Dependency Availability | GO | dependency 06 is done (instruction schema in `loomwright/docs/result-schemas/automate-run.md` §"next-step instruction"); `check-children-settled.sh`, `guard-finalize-publish.sh write-marker`, `run-lock.sh`, `reconcile-resume-state.sh`, `verify-provides.sh` exist |
| 3 | Architecture Fit | CAUTION | (a) Context-Keeper is the SOLE writer of `.supervisor/state.md`'s Decisions Log / Worker Results / Error Log / Phase Flags, and `## Session` is derived by `build-state.sh` — the driver therefore must NOT write `state.md`; it emits the exact Context-Keeper operation as an instruction for the model to delegate. (b) The requirement says the pre-merge safety gate and the PR-base self-verify are "already scripts" — they are not: pre-merge gate points 1–4 and FINALIZE step 6.5 are prose + inline `git`/`gh` commands in `skills/async-orchestration/SKILL.md` Part 2; only point 5 (`check-children-settled.sh` + `guard-finalize-publish.sh write-marker`) is scripted. The driver implements points 1–4 and step 6.5 as new deterministic steps. |
| 4 | Scope vs Supervisor Capability | CAUTION | ~122 deterministic GAP rows in Phases 0–4 across four large prose files (agents/supervisor.md 111KB, commands/supervisor.md 58KB, async-orchestration 57KB); split into 3 context-bound subtasks |
| 5 | Hard Blockers | CAUTION | ~17 tests pin supervisor prose (`test-rules-seams.sh`, `test-not-verified-transport-seam.sh`, `test-check-children-settled.sh`, `test-verify-provides.sh`, `test-context-digest.sh`, `test-release-refold.sh`, `test-phase45-rounds-seam.sh`, `test-non-interactive-gates-seam.sh`, `test-run-lock.sh`, `test-build-handoff.sh`, `test-check-contract-parity.sh`, `test-worktree-salvage.sh`, `test-reconcile-resume-state.sh`, `test-pr-body-evidence-seam.sh`, `test-citation-drift.sh`, `scripts/check-contract-parity.sh`, `scripts/check-doc-currency.sh`); moved prose must keep every pin green (moved verbatim + repointed, or left in place) |

## Task
**Goal:** Add `loomwright/scripts/supervisor-next-step.sh`, a step driver that owns Supervisor's deterministic Phase 0–4 sequencing and bookkeeping and hands the main thread ONE instruction at a time in item 06's instruction schema (`{"do":"spawn"|"ask"|"park"|"done",…}`): spawn orchestrator / execute-manager / Single-Agent or Sequential worker / Context-Keeper operation; ask (Phase 1.5 OVERLAP/SUPERSEDED, Phase 3 adjudication, FINALIZE `gh` retry) with each gate's named can't-ask status; run a FINALIZE step; done (hand-over to Phase 4.5). Golden fixtures pin the driver's output first; the migrated prose leaves the default `/supervisor` read path (kept selectable under `/supervisor --legacy`, owner decision D5); the inventory rows are re-homed.

**Problem Statement:**
Supervisor's own protocol is control flow written as prose (`agents/supervisor.md` 111067 B, `commands/supervisor.md` 58190 B, `skills/self-heal-advisory/SKILL.md` 176146 B, `skills/async-orchestration/SKILL.md` 57308 B at base). Phase sequencing, flag recording, Context-Keeper calls and the FINALIZE checklist are deterministic yet re-read and hand-executed every run. Success looks like: the inline Supervisor calls the driver per phase, the driver decides the next step and writes its own records byte-identically to golden expectations, and the default read set shrinks.

## Acceptance Criteria
- [ ] AC1 — Given each Supervisor Phase 0–4 golden case under `loomwright/scripts/fixtures/supervisor-golden/<case>/` (at least: `init-flags-non-interactive`, `init-flags-max-tokens`, `acquire-job-move`, `acquire-branch-reuse-tip-equal`, `acquire-branch-collision`, `acquire-autonomous-state-json`, `preflight-clear`, `preflight-overlap-ask`, `preflight-overlap-non-interactive`, `preflight-skip`, `preflight-unverified`, `plan-path-single-agent`, `plan-path-sequential`, `plan-path-parallel`, `execute-result-complete`, `execute-result-partial`, `execute-result-all-failed`, `execute-adjudication-ask`, `execute-adjudication-non-interactive`, `execute-manager-crash`, `finalize-premerge-gate-fail`, `finalize-children-unsettled`, `finalize-marker-written`, `finalize-pr-base-verified`, `finalize-pr-base-mismatch`, `finalize-pr-base-gh-retry`), when its `input/` tree (`.supervisor/state.md`, `jobs/`, `logs/<sid>.jsonl`, optional `autonomous/<sid>/state.json`) + `gh.stub` + `setup` are driven through `supervisor-next-step.sh` by its `next-step.results` script, then the resulting tree — `.supervisor/state.md`, the job lifecycle directories, the finalize-gate marker, the autonomous `state.json` and the driver's own sidecar — and the printed instruction stream are byte-identical to the case's `expected/` tree and `expected.out` (normalisation: ISO ts → `<TS>`, scratch root → `<ROOT>`, head sha → `<SHA>`), asserted by a new `loomwright/scripts/test-supervisor-next-step.sh` whose `REQUIRED_CASES` lists every case. Each case's `source` file names the real past run it was built from, or says `synthetic` and why (method of item 05).
- [ ] AC2 — Given the driver, then it NEVER writes `.supervisor/state.md` (Context-Keeper stays the sole writer of its non-`## Session` sections; `## Session` stays `build-state.sh`'s): every Phase Flag (`non_interactive`, `max_tokens`, `base_mismatch_detected` set/clear) and every `record_decision` / error record it decides is emitted as `{"do":"spawn","what":"context-keeper",…}` carrying the exact operation text — asserted by a leg that runs every golden case and compares `state.md` before/after the driver calls alone (byte-identical), plus a mutation control (a driver copy that appends to `state.md` ⇒ the leg goes red).
- [ ] AC3 — Given FINALIZE, when the driver reaches the publish step, then it prints the commit / push / `gh pr create` instruction ONLY after (a) pre-merge gate points 1–4 passed (each failure ⇒ the job-to-`failed/` park with a named reason), (b) `check-children-settled.sh --all` read `settled` (or `--skip-children-check` was recorded), and (c) `guard-finalize-publish.sh write-marker` exited 0 — `guard-finalize-publish.sh` itself is byte-unchanged (`git diff --quiet <base> -- loomwright/scripts/guard-finalize-publish.sh`) and FINALIZE point 5 still runs before anything is published; a mutation control (a driver copy that prints the publish instruction before `write-marker`) goes red.
- [ ] AC4 — Given the PR-base self-verify (step 6.5), when `gh pr view --json baseRefName` (through `LOOMWRIGHT_GH_BIN`) returns the expected base ⇒ the driver hands over to Phase 4.5; a different base ⇒ `set_flag base_mismatch_detected` (as a Context-Keeper instruction) and the Phase 4.5 base-mismatch cleanup hand-over; a first `gh` failure ⇒ one retry (the existing 5 s wait is a seam, `SUPERVISOR_NEXT_STEP_RETRY_SECONDS`, 0 in tests); a second failure ⇒ the `ask` (retry / skip-verify-once / abort) interactively, the flag + named status under `--non-interactive` — each branch a golden case (AC1).
- [ ] AC5 — Given an ask the driver emits (Phase 1.5 OVERLAP/SUPERSEDED, Phase 3 adjudication A–D for both `adjudication_kind`s, FINALIZE `gh` retry), then the instruction carries the question, the exact option labels, its catalog `header` only where `scripts/lane-policy.sh catalog` lists one, and the gate's named can't-ask status (`preflight_overlap_detected`, the adjudication's existing non-interactive status, the step-6.5 non-interactive status) — the driver never picks an option itself; under `--non-interactive` it emits the named `park` instead of the `ask`.
- [ ] AC6 — Given the migrated tree, when `bash loomwright/scripts/test-loop-inventory.sh` runs, then it passes; every Phase 0–4 inventory row whose prose was migrated has home `script:supervisor-next-step.sh <step>` naming a real `case` arm of the driver and test cell `test-supervisor-next-step.sh`; Phase 3 rows that belong to the Execute Manager's own poll loop (`async-orchestration` poll/spawn/backoff/checkpoint rows such as SV-599, SV-624…SV-631, SV-641) and every Phase 4.5 row stay `prose` (out of scope; 4.5 is item 11b); the evidence file records the supervisor GAP count before (542) and after, and the residual GAP count by kind.
- [ ] AC7 — Given the migrated steps, when the default `/supervisor` read path is read (Step 0's inline reads — `commands/supervisor.md`, the on-demand phase skills it Reads at phase entry, and `agents/supervisor.md` on the delegated path), then the step-by-step Phase 0–4 bookkeeping prose is replaced by a short "run `supervisor-next-step.sh`" pointer per phase; the only remaining copy is a `--legacy`-only file read solely under `/supervisor --legacy` (moved verbatim; a new `--legacy` row in `commands/supervisor.md`'s parameter table); a committed evidence file `docs/evidence/as11-next-step-supervisor.md` contains `wc -c` of the four files before (`111067`, `58190`, `176146`, `57308`) and after, the default read-set size before/after, the GAP counts (AC6) and `<passed>/<total>` for each Validation-1 suite; the PR body links to it and pastes the read-set line.
- [ ] AC8 — Given the tests that pin supervisor prose (Feasibility row 5 list), when the prose moves, then each pin still finds its anchor where the rule now lives (moved verbatim) or is repointed in the same change with its mutation control kept, and every one of those suites reports 0 failures; a rule that a seam test pins and that is not a step (e.g. the Can't-ask rule, the completion-tail guard, the `--skip-self-heal` warning) stays in place.
- [ ] AC9 — Given the change, when `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not " | cut -d: -f1 | sort -u` runs, then it prints exactly the same file list as base a8819a3 (the driver, its test, the legacy file and the evidence file carry the string only negated, if at all) — asserted by a `test-supervisor-next-step.sh` leg; Phase 4.5 still never merges and no per-subtask LLM reviewer is introduced (a leg asserts the driver emits no `code-reviewer` spawn in any Phase 0–4 step).

## Validation (must pass before merge)
1. `bash loomwright/scripts/test-supervisor-next-step.sh`, `test-loop-inventory.sh`, `test-automate-next-step.sh`, every Feasibility-row-5 suite, `bash scripts/check-doc-currency.sh`, `bash loomwright/scripts/test-citation-drift.sh`, `bash scripts/check-token-budget.sh`, `bash scripts/check-contract-parity.sh`; report `<passed>/<total>` in the evidence file.
2. Mutation controls (inside `test-supervisor-next-step.sh`, each mutant gated non-empty + differs + `bash -n`, the item-06 `build_mutant` pattern): (a) the driver prints the publish instruction before `guard-finalize-publish.sh write-marker` ⇒ red (AC3); (b) the driver writes `state.md` ⇒ red (AC2); (c) the driver skips the step-6.5 retry and sets the mismatch flag on the first `gh` failure ⇒ red (AC4); (d) the driver auto-picks an adjudication option under interactive mode ⇒ red (AC5). The requirement's "Phase 4.5 exceeds max_iterations ⇒ red" control moves to item 11b with the Phase 4.5 scope.
3. Running system (hermetic, the scoping items 06/07 used): in a scratch `git init` repo with a pending brief (gh stubbed, no network), drive one item from Phase 0 through the driver to the Phase 4.5 hand-over: each `spawn` answered with a fixed result (orchestrator plan, EXECUTE_RESULT, Context-Keeper confirmation), the FINALIZE steps run for real against the scratch repo; paste the driver's instruction sequence (one line per instruction: `do` + `step`) fenced into the evidence file AND into the PR body under a `validation 3` line. Validation 1 summary lines and Validation 2 verdict lines are also pasted, fenced, under `validation 1` / `validation 2` lines in the PR body (the `validation-gate` reads all three from the PR body); the evidence file stays the authority. The requirement's "one real item through Supervisor on the driver path; paste the Phase 4.5 iteration lines" is not runnable in a lane PR (the installed plugin runs this very item) and Phase 4.5 is item 11b — stated in the evidence file's "Not verified" note.

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 3
- **Base Branch:** main
- **Split reason:** context-bound — subtask 1 (driver Phases 0–2 + harness + golden cases), subtask 2 (driver Phase 3 routing + Phase 4 FINALIZE steps + their cases + mutation controls) and subtask 3 (prose move across ~226KB of supervisor prose, the `--legacy` file, the ~33KB inventory and ~17 pinned-prose suites) each fill a worker context; 2 extends 1's driver and harness, 3 consumes both subtasks' step names.
- **Lane PR rule:** this runs in a `--parallel` lane — ship a `changelog.d/as11-next-step-supervisor.md` fragment (`<!-- bump: minor -->`), never a version bump; `bash scripts/check-version-bump.sh` passes.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Phase 3: File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|---|---|---|---|
| driver | — | `loomwright/scripts/supervisor-next-step.sh` | HIGH |
| driver-test + fixtures | — | `loomwright/scripts/test-supervisor-next-step.sh`; `loomwright/scripts/fixtures/supervisor-golden/<case>/` (`input/`, `expected/`, `expected.out`, `next-step.results`, `source`, optional `gh.stub` / `setup`) | HIGH |
| schema + release | `loomwright/docs/result-schemas/supervisor-result.md` (a new "supervisor next-step instruction" section that cites `automate-run.md` §"next-step instruction" for the shared `do` enum and lists this driver's `step` arms and `what` values) | `changelog.d/as11-next-step-supervisor.md`, `docs/evidence/as11-next-step-supervisor.md` | MEDIUM |
| prose migration | `loomwright/commands/supervisor.md`, `loomwright/agents/supervisor.md`, `loomwright/skills/async-orchestration/SKILL.md`, `loomwright/skills/supervisor-config/SKILL.md`, `loomwright/skills/preflight-sync/SKILL.md` (phase-entry bookkeeping only; the CLEAR/OVERLAP/SUPERSEDED classification is judgment and stays) | `loomwright/docs/supervisor-legacy-phases.md` (the `--legacy`-only copy; under `docs/` so it adds to no skill's token budget) | MEDIUM |
| pinned-prose tests + gate coverage | the Feasibility-row-5 suites (incl. `loomwright/scripts/test-check-contract-parity.sh`, `loomwright/scripts/test-citation-drift.sh`, `scripts/check-doc-currency.sh`) — ONLY where a pin's anchor moved; `scripts/check-contract-parity.sh` — an ENUMS row for `docs/supervisor-legacy-phases.md` so enum-literal coverage moves with the text | — | MEDIUM |
| inventory | `loomwright/docs/loop-inventory/supervisor.md` (homes, test cells, Gap list, Counts; new heading rows for the new pointer headings) | — | HIGH |

> **Validator-owned surfaces:** `test-loop-inventory.sh` (every `###`/`####` heading of the four source files needs a row; `script:<file> <sub>` must match a `case` arm label in the named file; a non-GAP test cell must name an existing `test-*.sh`; `## Counts` and `## Gap list` must equal the table), `test-result-schemas-split.sh` (owns `docs/result-schemas/*.md`), `check-doc-currency.sh`, `test-citation-drift.sh` (no new bare `file:<N>` citation; pin any line number), `check-token-budget.sh` (shrinking passes; `measured` stays frozen unless its `ARCHITECTURE_CONTRACTS.md` mirror row changes in the same commit), `check-contract-parity.sh`.

## Touched-file invariants
> Grounded at base `a8819a38100d77fbeddc2ff1a56963e91f172a5d`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/automate-next-step.sh`** (NOT edited — the pattern to copy): the closed instruction set `spawn` / `ask` / `park` / `done` printed through `ns_emit` / `ns_emit_ask` / `ns_emit_park`; exit codes `0 an instruction printed`, `1` a helper/writer failure (sidecar stays at the failing step), `2` usage / refusal with nothing written; the idempotent re-print of a pending instruction with no `--result`; pending state in a gitignored `*.json` sidecar bound to one item (`ns_bound`); every side effect behind an overridable seam (`NEXT_STEP_*_CMD`, `LOOMWRIGHT_GH_BIN`); dispatcher `case` arms indented exactly 4 spaces inside `ns_dispatch() {` (the D leg's `sed -n 's/^    \([a-z][a-z-]*\)) .*/\1/p'`). The new driver keeps the same shapes with its own prefix and its own seams.
- **`loomwright/scripts/guard-finalize-publish.sh`** (NOT edited): the fail-CLOSED `PreToolUse[Bash]` leaf with no `|| true` and `"onFailure": "block"` in `hooks.json`; `write-marker [--skip-children-check] [--expect-id <id>]...` is the ONLY writer of `.supervisor/logs/<plugin_session_id>.finalize-gate`; refusals `session_log_missing`, `worker_results_unparsed`, `children_unsettled`, `bad_args`. The driver CALLS it; never writes the marker itself.
- **`loomwright/scripts/check-children-settled.sh`** (NOT edited): always exit 0, one JSON object; `status` ∈ `settled` / `unsettled` / `no_identity_rows` / `unverifiable`; FINALIZE uses `--log <path> --all [--expect-id <id>]...`.
- **`.supervisor/state.md`** (NOT written by the driver): `## Session` is `scripts/build-state.sh`'s ("this is a TARGETED in-place edit"; other sections "preserved byte-for-byte"); Decisions Log / Worker Results / Error Log / Checkpoint / Phase Flags are Context-Keeper's (`skills/state-management/SKILL.md`). Phase 1 and 2 write no progress state ("Progress state is not written here").
- **`loomwright/agents/supervisor.md`** — keep verbatim and in place: the Phase 4.5 completion-tail guard; the Can't-ask rule and its named statuses; Phase 4 FINALIZE's numbered mandatory-gate list (pre-merge safety gate, merge-conflict STOP, salvage before remove, PR-base self-verify) — the pointer replaces the HOW, the gate list stays the WHAT; every anchor the seam tests read (re-check each with `grep -F` before and after).
- **`loomwright/commands/supervisor.md`** — keep: the two top blockquotes (inline-execution + execution contract); the parameter table (add the `--legacy` row); the Observability `awk` snippet ("THIS commands-side copy stays in place because the inline path loads this file"); §"Inline-path canonical state writes" (the cross-layer `state.json` write must stay visible to the inline path — its HOW may become a driver step, the pointer must say so); token ceiling `commands.supervisor` budget 16002 / measured 14547.
- **`loomwright/skills/async-orchestration/SKILL.md`** — keep: Part 2's FINALIZE protocol headings that the Execute Manager and seam tests read; the verbatim Subagent Spawn Contracts; the Execute Manager's own poll-loop prose (SV-599, SV-624…SV-631, SV-641 — out of scope).
- **`loomwright/skills/supervisor-config/SKILL.md`** — keep: the step-0 run-lock acquire carrying `--session-id` (pinned by `test-run-lock.sh`'s `check_acquire_has_session_id "supervisor-config SKILL step 0"`); the `init_input_missing_non_interactive` named status (pinned by `test-non-interactive-gates-seam.sh`); every bare `status:` literal stays within `scripts/check-contract-parity.sh`'s ENUMS row `skills/supervisor-config/SKILL.md|status|failed,enum`. Phase-entry bookkeeping may become a pointer; these anchors stay in place.
- **`loomwright/skills/preflight-sync/SKILL.md`** — keep: the CLEAR / OVERLAP / SUPERSEDED classification protocol (judgment — stays prose); every bare `status:` literal stays within the ENUMS row `skills/preflight-sync/SKILL.md|status|checkpoint,failed,enum`; the `preflight_overlap_detected` named status.
- **`loomwright/docs/result-schemas/supervisor-result.md`** — keep: the `<!-- risk-table:begin -->` … `<!-- risk-table:end -->` block byte-identical and the only copy (pinned by `test-classify-risk.sh` E1/E2); the new section is ADDED after the existing content, never between those markers; the file stays one of the `docs/result-schemas/*.md` split files `test-result-schemas-split.sh` owns (no index change beyond what that test requires).
- **`scripts/check-contract-parity.sh`** (EDITED only to move coverage) — its ENUMS header says "when a refactor moves status-literal-bearing text into a new skill, add a row here so the gate's coverage moves with it": subtask 3 adds a row for `docs/supervisor-legacy-phases.md` carrying the union of the allowlists of the rows its text came from (or, if the moved text carries no bare `status:`/`heal_decision:` literal, records that in the evidence file and adds no row); `loomwright/scripts/test-check-contract-parity.sh` stays green.
- **The pin-repoint suites** (Feasibility row 5 — `test-rules-seams.sh`, `test-not-verified-transport-seam.sh`, `test-check-children-settled.sh`, `test-verify-provides.sh`, `test-context-digest.sh`, `test-release-refold.sh`, `test-phase45-rounds-seam.sh`, `test-non-interactive-gates-seam.sh`, `test-run-lock.sh`, `test-build-handoff.sh`, `test-worktree-salvage.sh`, `test-reconcile-resume-state.sh`, `test-pr-body-evidence-seam.sh`, `test-check-contract-parity.sh`, `test-citation-drift.sh`, `scripts/check-doc-currency.sh`) — shared invariant: every existing leg and every mutation control kept; a needle is changed ONLY to the file its text moved to (verbatim), never weakened, and never deleted to make a suite pass; first grep each suite for the moved anchor (`grep -nF '<anchor>'`) before touching it — most anchors (rules, the Can't-ask rule, the completion-tail guard) stay in place and need no edit.
- **`loomwright/docs/loop-inventory/supervisor.md`**: home grammar `prose, script:<file>[ <sub>], hook:<leaf>, step-scoped, global or rationale:<doc>#<anchor>`; a `prose` row needs a live anchor in its file; ids are never reused.
- **`loomwright/docs/prompt-token-budgets.json` / `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets"**: edit only if a file grows past its budget; `measured` equals the mirror row, changed in the same commit.

## Closed enumerations touched
> Sibling grep at base `a8819a3`: `grep -rn "one of the driver's \`case\` arms" loomwright/docs/` → `loomwright/docs/result-schemas/automate-run.md` only (the automate driver's step list). `grep -rn '"fix-now re-drain"' loomwright/` → `automate-next-step.sh`, `test-automate-next-step.sh`, `result-schemas/automate-run.md`, `skills/automate-loop/legacy-tail.md`.

- **The `do` enum** (`spawn` / `ask` / `park` / `done`) is reused unchanged — no new `do` value. New `what` values (e.g. `"orchestrator"`, `"execute-manager"`, `"worker"`, `"context-keeper"`, `"finalize-publish"` — final strings the worker's) are named in: the new schema section in `loomwright/docs/result-schemas/supervisor-result.md` (modify — new section), the driver (emitter), `test-supervisor-next-step.sh` (a D leg comparing the doc's `step` list with the driver's real `case` arms, same method as `test-automate-next-step.sh`'s D leg).
- **The driver's `step` arms** are named in: the driver's `case` dispatcher + header STEPS block, the schema section's `step` list, and `loomwright/docs/loop-inventory/supervisor.md` homes.
- **No new** `SUPERVISOR_RESULT` key, `status`, `error` or `status_reason` value: named statuses (`acquire_branch_collision`, `preflight_overlap_detected`, `children_unsettled`, the step-6.5 statuses) already exist and are reused verbatim.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `test-supervisor-next-step.sh` — publish-after-marker order leg (AC3) | in a driver copy, move the publish instruction emit before the `write-marker` call |
| `test-supervisor-next-step.sh` — state.md untouched leg (AC2) | in a driver copy, append one line to `.supervisor/state.md` in the INIT step |
| `test-supervisor-next-step.sh` — step-6.5 retry leg (AC4) | in a driver copy, delete the single retry so the first `gh` failure sets the mismatch flag |
| `test-supervisor-next-step.sh` — no-auto-pick leg (AC5) | in a driver copy, emit `done` with option A instead of the adjudication `ask` |
| `test-supervisor-next-step.sh` — D leg (doc step list) | in a driver copy, add one `case` arm not named in the schema section |
| `test-supervisor-next-step.sh` — AC9 merge-surface leg (file list unchanged from base) | in a driver copy, add one un-negated `gh pr merge --squash` line (built at run time so the test source never holds the positive literal on one line, item 06's S-leg method) ⇒ the leg goes red |
| `test-supervisor-next-step.sh` — AC9 no-reviewer leg | in a driver copy, make one Phase 0–4 arm emit `{"do":"spawn","what":"code-reviewer"}` ⇒ the leg goes red |
| Each repointed pin in a Feasibility-row-5 suite (rule for every one subtask 3 repoints; the evidence file lists each repoint with its mutation and verdict) | delete or flip the protected literal at its NEW location (the moved text in `docs/supervisor-legacy-phases.md`, or the driver arm that now implements it) in a scratch copy — never the pin's own needle — and the suite's leg must go red |
| `check-contract-parity.sh` ENUMS row for `docs/supervisor-legacy-phases.md` | in a scratch copy of the legacy file, change one bare `status:` literal to a token outside the row's allowlist ⇒ the enum-literal check reports it |

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory

## Design notes (binding for the worker)
- **Entry and hand-over.** The inline Supervisor calls `supervisor-next-step.sh --job <brief> --session-id <sid> [--non-interactive] [--cheap] [--max-tokens N] [--base-branch B] [--skip-preflight-sync] [--skip-children-check] [--sequential] [--max-workers N]` once at Phase 0 (flags persisted in its sidecar `.supervisor/logs/<sid>.supervisor-next-step.json`, gitignored), then `--result <json>` after each instruction. It prints `{"do":"done","step":"handover","next":"phase-4.5",…}` at the end of FINALIZE (or the base-mismatch hand-over). Phase 4.5 and Phase 5 stay prose (item 11b).
- **Model-owned work stays model-owned.** Spawning subagents, the Phase 1.5 classification itself (judgment — the driver routes on the classification the model hands back), implementing, adjudication choices, conflict STOP decisions. The driver owns: flag parsing/persistence, path selection by subtask count (`skills/supervisor-readiness/SKILL.md` §"Decomposition Threshold"), the `pending/`→`in-progress/` job move and the failed/ move on a FINALIZE abort, the idempotent branch guard (reuse only when the tip equals the base tip, else `acquire_branch_collision`), the autonomous `state.json` ACQUIRE fields (jq atomic write; skip on ambiguity), EXECUTE_RESULT outcome routing (complete / partial / all-failed / adjudication / crash / budget ⇒ checkpoint), pre-merge gate points 1–4, children-settled + `write-marker`, PR-base verify with its retry.
- **Context-Keeper.** The driver emits `{"do":"spawn","what":"context-keeper","op":"set_flag non_interactive …"}`-style instructions and waits for the confirmation `--result`; it never writes `state.md`.
- **Legacy path (D5).** `/supervisor --legacy` reads `loomwright/docs/supervisor-legacy-phases.md` (the moved prose, verbatim) and follows it instead of calling the driver; nothing else changes. Retired later with item 08's retirement pattern. The file opens with a banner naming `supervisor-next-step.sh` as the authority and stating the prose is frozen at base a8819a3 (the house rule on restated lists: the copy points at its authority); the evidence file records the same.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Driver skeleton + Phases 0, 1, 1.5, 2 steps, harness, golden cases for those phases, schema section, changelog fragment | AC1 (Phase 0–2 cases), AC2, AC5 (Phase 1.5 ask), AC9, Validation 2b | 1 modify + driver/test/fixtures/fragment create | `skills/unit-testing/SKILL.md`, `skills/supervisor-config/SKILL.md`, `skills/preflight-sync/SKILL.md` | LAUNCHABLE |
| 2 | Driver Phase 3 Supervisor-side routing + Phase 4 FINALIZE steps (pre-merge gate, children-settled, write-marker, publish, PR-base verify), their golden cases, mutation controls, Validation 3 drive, evidence (driver legs) | AC1 (Phase 3–4 cases), AC3, AC4, AC5 (adjudication, gh retry), Validation 2a/2c/2d, Validation 3 | driver/test/fixtures modify + evidence create | `skills/async-orchestration/SKILL.md` Part 2, `skills/unit-testing/SKILL.md` | BLOCKED (by #1) |
| 3 | Prose move to `docs/supervisor-legacy-phases.md`, per-phase pointers, `--legacy` row, inventory re-home + counts, pinned-prose suites, evidence after-values | AC6, AC7, AC8, Validation 1 | ~8 modify + 1 create | `skills/unit-testing/SKILL.md` | BLOCKED (by #2) |

## Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/supervisor-next-step.sh"}
  - {kind: "file", path: "loomwright/scripts/test-supervisor-next-step.sh"}
  - {kind: "file", path: "loomwright/scripts/fixtures/supervisor-golden/acquire-job-move/next-step.results"}
  - {kind: "file", path: "loomwright/scripts/fixtures/supervisor-golden/preflight-overlap-ask/next-step.results"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/supervisor-result.md", name: "supervisor next-step instruction"}
  - {kind: "file", path: "changelog.d/as11-next-step-supervisor.md"}
requires: []
lanes:
  - "loomwright/scripts/supervisor-next-step.sh"
  - "loomwright/scripts/test-supervisor-next-step.sh"
  - "loomwright/scripts/fixtures/supervisor-golden/**"
  - "loomwright/docs/result-schemas/supervisor-result.md"
  - "changelog.d/as11-next-step-supervisor.md"
external_requires:
  - "jq on PATH"

# Subtask 2
provides:
  - {kind: "file", path: "loomwright/scripts/supervisor-next-step.sh"}
  - {kind: "file", path: "loomwright/scripts/fixtures/supervisor-golden/finalize-marker-written/next-step.results"}
  - {kind: "file", path: "loomwright/scripts/fixtures/supervisor-golden/finalize-pr-base-gh-retry/next-step.results"}
  - {kind: "file", path: "loomwright/scripts/fixtures/supervisor-golden/execute-adjudication-ask/next-step.results"}
  - {kind: "file", path: "docs/evidence/as11-next-step-supervisor.md"}
requires:
  - {from: "1", kind: "file", path: "loomwright/scripts/supervisor-next-step.sh"}
  - {from: "1", kind: "file", path: "loomwright/scripts/test-supervisor-next-step.sh"}
lanes:
  - "loomwright/scripts/supervisor-next-step.sh"
  - "loomwright/scripts/test-supervisor-next-step.sh"
  - "loomwright/scripts/fixtures/supervisor-golden/**"
  - "loomwright/docs/result-schemas/supervisor-result.md"
  - "docs/evidence/as11-next-step-supervisor.md"
external_requires: []

# Subtask 3
provides:
  - {kind: "file", path: "loomwright/docs/supervisor-legacy-phases.md"}
  - {kind: "symbol", path: "loomwright/commands/supervisor.md", name: "--legacy"}
  - {kind: "symbol", path: "loomwright/docs/loop-inventory/supervisor.md", name: "script:supervisor-next-step.sh"}
requires:
  - {from: "2", kind: "file", path: "loomwright/scripts/supervisor-next-step.sh"}
  - {from: "2", kind: "file", path: "docs/evidence/as11-next-step-supervisor.md"}
lanes:
  - "loomwright/commands/supervisor.md"
  - "loomwright/agents/supervisor.md"
  - "loomwright/skills/async-orchestration/SKILL.md"
  - "loomwright/skills/supervisor-config/SKILL.md"
  - "loomwright/skills/preflight-sync/SKILL.md"
  - "loomwright/docs/supervisor-legacy-phases.md"
  - "loomwright/docs/loop-inventory/supervisor.md"
  - "docs/evidence/as11-next-step-supervisor.md"   # sequential share: fills the after-values
  - "loomwright/scripts/test-rules-seams.sh"   # pin repoint only
  - "loomwright/scripts/test-not-verified-transport-seam.sh"   # pin repoint only
  - "loomwright/scripts/test-check-children-settled.sh"   # pin repoint only
  - "loomwright/scripts/test-verify-provides.sh"   # pin repoint only
  - "loomwright/scripts/test-context-digest.sh"   # pin repoint only
  - "loomwright/scripts/test-release-refold.sh"   # pin repoint only
  - "loomwright/scripts/test-phase45-rounds-seam.sh"   # pin repoint only
  - "loomwright/scripts/test-non-interactive-gates-seam.sh"   # pin repoint only
  - "loomwright/scripts/test-run-lock.sh"   # pin repoint only
  - "loomwright/scripts/test-build-handoff.sh"   # pin repoint only
  - "loomwright/scripts/test-worktree-salvage.sh"   # pin repoint only
  - "loomwright/scripts/test-reconcile-resume-state.sh"   # pin repoint only
  - "loomwright/scripts/test-pr-body-evidence-seam.sh"   # pin repoint only
  - "loomwright/scripts/test-check-contract-parity.sh"   # pin repoint only
  - "loomwright/scripts/test-citation-drift.sh"   # pin repoint only
  - "scripts/check-contract-parity.sh"   # ENUMS coverage row for the legacy file
  - "scripts/check-doc-currency.sh"   # pin repoint only
  - "loomwright/docs/prompt-token-budgets.json"   # only if a ceiling is exceeded
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"   # only the matching Prompt Token Budgets mirror row
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2 ──→ Subtask 3
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | driver, test, fixtures, schema section | YES (ordered by `requires`) |
| Subtask 2 | Subtask 3 | `docs/evidence/as11-next-step-supervisor.md` | YES (ordered by `requires`) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2
- **Batch 3:** Subtask 3
- **Recommended workers:** 1
- **Estimated batches:** 3

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `loomwright/skills/supervisor-config/SKILL.md`, `loomwright/skills/preflight-sync/SKILL.md`, `loomwright/scripts/automate-next-step.sh` (pattern), `skills/unit-testing/SKILL.md` |
| 2 | `loomwright/skills/async-orchestration/SKILL.md` Part 2, `loomwright/agents/supervisor.md` Phase 3/4 stanzas, `skills/unit-testing/SKILL.md` |
| 3 | `loomwright/docs/loop-inventory/supervisor.md` header (home grammar), `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| The requirement's GAP-0 AC is unreachable; scope split to Phases 0–4 (source: Feasibility (Phase 2.5); owner decision 2026-10-17) | HIGH | Owner chose the split; Phase 4.5 is item 11b in `proposed/`; GAP before/after + residual by kind in the evidence file |
| The driver writes `state.md` and breaks the Context-Keeper sole-writer contract (source: Feasibility (Phase 2.5)) | HIGH | AC2 + mutation control 2b; every state mutation is a Context-Keeper instruction |
| Pre-merge gate points 1–4 and step 6.5 are not scripts today (source: Feasibility (Phase 2.5)) | MEDIUM | Implemented as driver steps with golden cases (AC3/AC4) — new code, reviewed in Phase 4.5 |
| Publishing before FINALIZE point 5 | HIGH | AC3 + mutation control 2a; `guard-finalize-publish.sh` byte-unchanged and still the fail-CLOSED backstop |
| Moving prose breaks ~17 seam tests that pin supervisor prose (source: Feasibility (Phase 2.5)) | HIGH | AC8: move verbatim + repoint, keep rules in place; run every listed suite before hand-back |
| `test-loop-inventory.sh` heading coverage: new pointer headings need rows; removed headings' rows need homes | MEDIUM | Subtask 3 edits the inventory in the same commit as the prose |
| Golden cases from real runs may not exist for every branch | MEDIUM | `source` file says `synthetic` and why, as item 05 allows |
| `validation-gate` reads `## Validation` 1–3 from the PR body | MEDIUM | FINALIZE pastes fenced output under `validation 1` / `validation 2` / `validation 3` lines and links the evidence file |
| Subtask context overflow — ~122 deterministic rows over ~226KB of prose in four files (source: Feasibility (Phase 2.5), row 4) | MEDIUM | 3-way context-bound split; subtask 3 moves prose verbatim (no rewriting) and works file by file with the inventory |
| Validation 3 is a hermetic drive, not a live `/supervisor` session on the driver | LOW | Stated in the evidence file's "Not verified" note |

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-17-next-step-supervisor.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-10-18T07:02:48Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/601
- **Branch:** feature/as11-next-step-supervisor
- **Files changed:** 284
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 0
- **Heal reason:** needs_human
- **Heal remaining issues:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** supervisor-next-step.sh owns Supervisor Phases 0–4 (init flags/CK ops, job move, branch guard, preflight routing, path selection, EXECUTE routing + adjudication ask, pre-merge 1–4, children-settled, write-marker before publish, PR-base verify w/ one retry); 27 golden cases, 105/105 under bash 3.2+5.3; Phase 0–4 prose moved verbatim to docs/supervisor-legacy-phases.md; inventory GAP 542→491. Phase 4.5 review iteration 1 NEEDS_HUMAN: legacy file also routes --continue/task:/--sdk-runner runs (contradicts AC7 — owner decision) + MEDIUM env-override finding; 2 LOW dismissed. Owner scope split: Phase 4.5 → proposed automate-speed-11b.

## Not verified
- **a live inline /supervisor session on the driver path** — no command doc pointed at the driver until subtask 3; only hermetic drives (subtask 1)
- **test leg B6 on Linux** — the /var to /private/var symlink case exists only on macOS (subtask 1)
- **gh against GitHub (pr view, PR creation)** — stubbed in every case (subtask 2)
- **a real Execute Manager EXECUTE_RESULT / EXECUTE_CHECKPOINT** — no kept run took the Parallel Path (subtask 2)
- **/supervisor --legacy and the runs routed to the legacy file** — no session has followed the legacy file; routing is prose-only (subtask 3)
