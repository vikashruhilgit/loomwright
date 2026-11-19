# Supervisor Job: QA removal part 2 (qa-split 11b2) — delete the QA scripts, schema docs, blueprint and CI Playwright steps

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** dirty (2 untracked dirs: `reports/`, `research_notes/` — unrelated), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 2 (untracked dirs; 6 existing worktrees)
- **Source requirement:** .supervisor/requirements/qa-split/11b2-remove-qa-scripts-schemas-ci.md
- **Base commit:** 92e7a4d5dc4ccbe2a6e9d5ee42de8eef09e16010

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Bash/Python/Markdown deletions and edits only; no new tooling |
| 2 | Dependency Availability | GO | Removes a dependency (Playwright/Chromium cache); adds none |
| 3 | Architecture Fit | GO | Follows the reviewed manifest `loomwright/docs/qa-removal-manifest.md` and its checker |
| 4 | Scope vs Supervisor Capability | CAUTION | 25 deletes + 18 modifies (> 12 files) ⇒ `context-bound` split into 2 sequential subtasks |
| 5 | Hard Blockers | CAUTION | The manifest's `11b2` rows reach 16 paths outside the requirement's `## Touches` (e.g. `propose-verify.sh`, `vendor-coupling-manifest.json`, the tests that copy deleted helpers) — needs files outside Touches, asked once at Phase 6 (`LP-SCOPE`) |

**Overall Verdict:** CAUTION

## Task
**Goal:** Delete every `delete` row of `loomwright/docs/qa-removal-manifest.md` marked `11b2` and apply every `re-point` row marked `11b2`, so `check-qa-removal-manifest.sh --expect 11b2` exits 0, CI stops caching Playwright, and every remaining suite stays green.

**Problem Statement:**
The plugin maintainer needs the QA scripts, tests, schema docs, blueprint and CI Playwright steps left without a caller after part 1 (11b1, PR #946) removed, because they still cost CI time (a ~150 MB Playwright download/cache path) and doc-gate upkeep.
Currently, `check-qa-removal-manifest.sh --expect 11b2` exits 1 with 25 `MISMATCH` delete rows, and 50 `re-point` rows marked `11b2` are `pending`.
Success looks like the checker exiting 0 at `--expect 11b2`, no `pending re-point 11b2` line in its report, no Playwright/Chromium step in `.github/workflows/ci.yml`, and the full CI `ci` check green.

**The 25 `11b2` delete rows (from the checker's `MISMATCH` output at base):**
`loomwright/docs/QA_SYSTEM_BLUEPRINT.md`; `loomwright/docs/result-schemas/{gate-verdict,graphql-risk-overrides,missing-functionality-report,qa-result,qa-session,verify-env,verify-evidence,verify-queue,verify-result}.md`; `loomwright/scripts/{propose-verify.sh,read-playwright-pin.sh,read-verify.sh,test-read-playwright-pin.sh,test-verify-evidence.sh,test-verify-queue.sh,test-verify-seam.sh,test-verify-walkthrough.sh,validate-qa-result.py,validate-verify-evidence.py,verify-env.sh,verify-fixture-app.py,verify-helpers.sh,verify-run.sh}`; `loomwright/scripts/result-validator-fixtures/qa-result-valid.md`.

**Note on the requirement's lists vs the manifest:** the requirement says to work "strictly from 11a's manifest rows marked `11b2`". The manifest is the authority, and it adds `propose-verify.sh` and `result-validator-fixtures/qa-result-valid.md` to the delete set and names `11b2` re-point rows in files the requirement's `## Touches` omits. The requirement's "`ci-local.sh` suite entries" are one comment: `scripts/ci-local.sh` globs suites, so the only `11b2` row there is the `playwright pin` comment.

## Acceptance Criteria
- [ ] AC1 — Given this branch, when `bash loomwright/scripts/check-qa-removal-manifest.sh --expect 11b2` runs, then it exits 0 (every `11b1` and `11b2` delete row gone, every keep row present — including `verify-provides.sh`, `test-verify-provides.sh`, the `qa-executor:*)` arm of `exec-acceptance-lib.sh` and `run-ground-truth.sh`'s `qa_executor_dispatch_deferred_m2b_1b`).
- [ ] AC2 — Given this branch, when `bash loomwright/scripts/check-qa-removal-manifest.sh --expect 11b2` runs, then no line of its output begins `pending re-point 11b2` (every `11b2` re-point row applied; rows marked `12` are left alone).
- [ ] AC3 — Given CI on this PR, when `grep -niE 'playwright|chromium|LOOMWRIGHT_VERIFY' .github/workflows/ci.yml` runs, then it prints nothing (no step installs or caches Playwright or Chromium for Loomwright's suites; `selvedge/`'s own CI steps are untouched).
- [ ] AC4 — Given a brief with a `qa-executor: x` Executable Acceptance bullet, when ground truth runs, then it still records the bullet as deferred and spawns nothing: `bash loomwright/scripts/test-run-ground-truth.sh` passes unchanged.
- [ ] AC5 — Given the removal, when `bash loomwright/scripts/test-propose-from-verify.sh` runs, then it passes with its own `evidence.jsonl` fixtures; only the arms that exercised the deleted `verify-helpers.sh` (AC2 summary-build, AC11, AC8-notify, AC9) are removed, and every arm that runs `propose-from-verify.sh` itself stays.
- [ ] AC6 — Given the removal, when `bash loomwright/scripts/test-result-validators.sh` runs, then it passes with the `validate-qa-result.py` arms (sections E and E2, and the `$V_QA` entries of the per-file loops) removed and every other validator's arms unchanged.
- [ ] AC7 — Given the doc surface, when `bash scripts/check-doc-currency.sh` and `bash scripts/check-vendor-coupling.sh` run, then both exit 0 (no stale vendor-coupling allowance for a deleted path).
- [ ] AC8 — Given the branch, when `bash scripts/ci-local.sh --affected` runs, then it passes, and CI's required `ci` check is green on the PR.

## Scope widening
- .claude-plugin/README.md
- AGENT_GUIDELINES.md
- CLAUDE.md
- README.md
- loomwright/docs/vendor-coupling-manifest.json
- loomwright/scripts/build-capabilities.sh
- loomwright/scripts/fixtures/self-test-weights.tsv
- loomwright/scripts/propose-verify.sh
- loomwright/scripts/result-validator-fixtures/qa-result-valid.md
- loomwright/scripts/test-base-branch-single-resolver.sh
- loomwright/scripts/test-no-fixed-sleep-race.sh
- loomwright/scripts/test-no-pipefail-grep-q.sh
- loomwright/scripts/test-propose-from-verify.sh
- loomwright/scripts/test-result-schemas-split.sh
- loomwright/scripts/test-script-event-telemetry.sh
- loomwright/scripts/test-telemetry-threads.sh
- scripts/check-contract-parity.sh
- scripts/test-ci-local.sh
- accepted: LP-SCOPE 2026-11-19

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
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

**How the rules apply here:** `AGENT_GUIDELINES.md` §"Sole-writer confirm gates" says "Which side each of the eight sole writers falls on" and "Six of the eight writers". Removing the `propose-verify.sh` row must not leave a stale literal count. Reword those sentences without the number (first rule), and update the table and both sentences in the same change (second rule).

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Delete | Confidence |
|-------|----------------|-----------------|------------|
| A — deletions + docs (Subtask 1) | `loomwright/docs/RESULT_SCHEMAS.md` (160), `loomwright/docs/vendor-coupling-manifest.json` (807), `AGENT_GUIDELINES.md` (843), `CLAUDE.md` (165), `README.md` (664), `.claude-plugin/README.md` (571) | the 25 `11b2` delete rows listed under `## Task` | HIGH |
| B — CI + test re-points (Subtask 2) | `.github/workflows/ci.yml` (383), `scripts/ci-local.sh` (923), `loomwright/scripts/test-result-validators.sh` (4617), `loomwright/scripts/test-propose-from-verify.sh` (454), `loomwright/scripts/fixtures/self-test-weights.tsv` (154), `loomwright/scripts/test-no-fixed-sleep-race.sh` (262), `loomwright/scripts/test-no-pipefail-grep-q.sh` (616), `loomwright/scripts/test-script-event-telemetry.sh` (362), `loomwright/scripts/test-telemetry-threads.sh` (508), `loomwright/scripts/test-base-branch-single-resolver.sh` (232), `scripts/check-contract-parity.sh` (439), `scripts/test-ci-local.sh` (1193), `loomwright/scripts/test-result-schemas-split.sh` (312), `loomwright/scripts/build-capabilities.sh` (592 — one comment line only) | — | HIGH |

No file is created. **Module layout:** this change only removes things. It adds no responsibility to any MODIFY path, so no home or extract row is needed. The large files (`test-result-validators.sh` 4617, `test-ci-local.sh` 1193, `ci-local.sh` 923, `AGENT_GUIDELINES.md` 843, `vendor-coupling-manifest.json` 807, `README.md` 664, `test-no-pipefail-grep-q.sh` 616, `.claude-plugin/README.md` 571, `test-telemetry-threads.sh` 508) only shrink.

> **Validator-owned surfaces:** AC1/AC2 depend on `check-qa-removal-manifest.sh`, whose scan set is the manifest's rows. Every `11b2` row's file is in the map above. AC7 depends on `check-vendor-coupling.sh` (its allowance map is `vendor-coupling-manifest.json`, in the map) and `check-doc-currency.sh` (files scanned by the validator may need updates — the deleted `QA_SYSTEM_BLUEPRINT.md` link lines in `README.md`, `.claude-plugin/README.md` and `CLAUDE.md` are in the map).

**`changelog.d/`:** no fragment. `bash scripts/check-version-bump.sh` passes with zero fragments and no bump: it checks consistency and does not require a release. The requirement's assumption holds, since the user-facing note shipped in 11b1. If the owner wants this PR to release, add one fragment; the bump folds it.

**Out of scope (rows marked `12`, left alone):** `propose-from-verify.sh`'s and `send-telemetry-core.sh`'s name maps, `classify-risk.sh`, `build-capabilities.sh`'s name map (only its one `§VERIFY_RESULT` comment citation changes here, because `test-result-schemas-split.sh` check F would fail on it), `result_block_parser.py`, `send-webhook.sh`, `completion-tail.md`, `test-not-verified-transport-seam.sh`, `test-proc-registry.sh`, `test-send-telemetry-core.sh`, and every other re-point row whose item is `12`. Two live docs still point at the deleted blueprint after this PR, deliberately: `loomwright/docs/ARCHITECTURE.md` ("QA system blueprint") and `loomwright/docs/command-parts/agent-help/guide.md` (tree line `QA_SYSTEM_BLUEPRINT.md`). Both are manifest re-point rows marked `12`, and no CI link checker fails on them. History keep rows (`docs/evidence/`, `SPIKES/`, `fixtures/corpus-briefs/`, `fixtures/pr-body-evidence/`, `CHANGELOG.md`) stay untouched even where they name a deleted file.

## Touched-file invariants

> Grounded at base `92e7a4d5dc4ccbe2a6e9d5ee42de8eef09e16010`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`.github/workflows/ci.yml`** — keep: the suite step `run: bash loomwright/scripts/run-self-tests.sh --shard ${{ matrix.shard }}/3`, `fail-fast: false`, `timeout-minutes: 30` and every other job's steps byte-identical. Delete exactly the job-level `env:` block carrying `LOOMWRIGHT_VERIFY_TEST_CACHE: /tmp/loomwright-verify-walkthrough`, the comment block above it, the step `Resolve the @playwright/test pin (test-verify-walkthrough.sh cache key)` and the step `Cache @playwright/test + chromium for test-verify-walkthrough.sh`, with their comment blocks. Re-point the shard-sizing comment that names `test-verify-walkthrough.sh, 149 s in the weights file` as the longest test: the next largest weight at base is `146	loomwright/scripts/test-automate-next-step.4.sh`. In the same comment, reword the literal suite total (`1846 test-seconds` … `~615 per shard`) without a number, pointing at `fixtures/self-test-weights.tsv` (House Rules: count claims): removing five weight rows would make it stale. mirror: `scripts/ci-local.sh` turns every `bash scripts/<x>.sh` line in ci.yml into a local gate, so do not add or remove any such line. pinned by: `scripts/test-ci-local.sh` (plan derived from ci.yml).
- **`scripts/ci-local.sh`** — keep: the gate extraction `grep -oE 'bash (scripts/[A-Za-z0-9_.-]+\.sh( --self-test)?|loomwright/scripts/[A-Za-z0-9_.-]+\.sh --check)'` and the zero-gate refusal `refusing to report green on zero gates` unchanged. The only edit is the comment `(the suite runner, the playwright pin, the fitness report)`, which drops "the playwright pin" (manifest row `playwright pin`). No executable line changes.
- **`loomwright/scripts/test-result-validators.sh`** — keep: the helpers `run_v`, `assert_fail` and `k_exact_pass`, the required-files guard `FATAL  required file not found`, and every non-QA section (`# ── F. plan-reviewer validator`, `# ── G. exit-0-by-contract on garbage, per file (R3)`). Remove `V_QA="$SCRIPT_DIR/validate-qa-result.py"`, `$V_QA` from `ALL_PY="$PARSER $V_WORKER $V_EXECUTE $V_SUPERVISOR $V_QA $V_PLAN"` and from the three `for v in $V_WORKER $V_EXECUTE $V_SUPERVISOR $V_QA $V_PLAN; do` loops, `"$FIXDIR/qa-result-valid.md"` from the required-files loop, sections `# ── E. qa-executor validator` and `# ── E2. qa-executor validator — the VERIFY_RESULT branch` (through the line before `# ── F.`), the `validate-qa-result.py: valid block -> exactly {}` arm and the `run_hb "$V_QA" loomwright:loomwright:qa-executor` arm. Also re-point the parser unit case `(R.has_result_block("x\n## WORKER_RESULT\n- status: completed\n", "QA_RESULT"), False)`: change its name argument to `"CODE_REVIEW_RESULT"`, which is absent from that text, so it still expects `False` and no `QA_RESULT` token is left in the file (AC2). Any arm that only names `verify-run.sh` in a comment or fixture keeps working; re-point the comment wording.
- **`loomwright/scripts/test-propose-from-verify.sh`** — keep: `run_sut`, `count_props`, the fixture builder for `$RD/evidence.jsonl`, and the arms `== AC1/AC5/AC10`, `== AC1: all four required sections`, `== AC-supersede`, `== AC3/AC10: idempotency`, `== AC10: a find diff`, `== AC14 (parallel-automate/18b)` and `== usage / fail-safe`. Remove the four arms that need the deleted helper: `== AC2: summary.md's derived ## Proposals section`, `== AC11: send-webhook.sh is invoked at most 3 times`, `== AC8-notify` and `== AC9: LOOMWRIGHT_WEBHOOK_URL unset`. Each copies or runs `verify-helpers.sh` (`cp "$HERE/verify-helpers.sh"`) and ends `no "verify-helpers.sh not found`, so it would go red. The `AC10` containment arm excludes `summary.md` (produced by the removed `summary-build`); keep that exclusion harmless or drop it only if the arm still proves containment. mirror: `propose-from-verify.sh` itself is NOT edited (item 12).
- **`loomwright/docs/vendor-coupling-manifest.json`** — keep: both maps (`allowances` and `allowance_reasons`) and the JSON shape. Remove the entry in BOTH maps for each of the 9 deleted paths it names (`QA_SYSTEM_BLUEPRINT.md`, `result-schemas/{qa-result,verify-evidence,verify-queue,verify-result}.md`, `test-verify-walkthrough.sh`, `validate-qa-result.py`, `validate-verify-evidence.py`, `verify-helpers.sh`), in the same change. A path dropped from one map only trips `allowance_reasons entry with no matching allowances entry — remove the stale reason`, and a kept stale path trips `allowance declared for a path that does not exist — remove the stale entry` (both in `scripts/check-vendor-coupling.sh`). Keep `fixtures/corpus-briefs/done/2026-09-15-verify-auth-pause.md`'s entries (a keep row).
- **`loomwright/scripts/fixtures/self-test-weights.tsv`** — keep: the `<seconds>\t<path>` row format. Remove exactly the 5 rows naming deleted tests (`test-read-playwright-pin.sh`, `test-verify-evidence.sh`, `test-verify-queue.sh`, `test-verify-seam.sh`, `test-verify-walkthrough.sh`). Keep `test-propose-from-verify.sh` and `test-verify-provides.sh`. consumer: `loomwright/scripts/run-self-tests.sh` (shard split), pinned by `test-run-self-tests.sh`.
- **`loomwright/scripts/test-no-fixed-sleep-race.sh`, `loomwright/scripts/test-no-pipefail-grep-q.sh`** — keep: each file's expected-baseline heredoc and its comparison. Remove only the baseline rows for deleted files (`1 loomwright/scripts/test-verify-queue.sh`, `15 loomwright/scripts/test-verify-walkthrough.sh`; `1 loomwright/scripts/verify-run.sh`). Every other row stays byte-identical, so the scan still matches the tree exactly.
- **`loomwright/scripts/test-script-event-telemetry.sh`, `loomwright/scripts/test-telemetry-threads.sh`** — keep: each sibling-copy loop and its `set -u` / `set -o pipefail` header. Remove `validate-qa-result.py` from the copy lists (`validate-code-review-result.py validate-qa-result.py validate-supervisor-result.py`; `validate-qa-result.py validate-supervisor-result.py; do cp "$SCRIPT_DIR/$f" "$dir/"; done`) so no `cp` targets a deleted file.
- **`loomwright/scripts/test-base-branch-single-resolver.sh`, `scripts/check-contract-parity.sh`, `scripts/test-ci-local.sh`** — comment-only edits: re-word `modules and verify-run.sh`, the two `validate-qa-result.py` examples (`deleting the executable rule-4 block from validate-qa-result.py`, `replacing validate-qa-result.py's executable rule-4 block`; also the per-validator tally `4 of the 5 converted validators have them — qa 4 comment-lines`), and `start_app() in test-verify-walkthrough.sh` so none names a deleted file. No executable line changes. `check-contract-parity.sh`'s `exactly 1 required` checks stay as they are.
- **`loomwright/scripts/test-result-schemas-split.sh`** — keep: checks A–F, the fence-aware heading detection, the `## Cited sub-section anchors` resolution and its mutants. `cited_anchors()` scans every tracked citation (`git -C "$REPO" grep -lE 'RESULT_SCHEMAS' -- . ':!CHANGELOG.md'`). Extend that exclusion pathspec by exactly `':!loomwright/scripts/fixtures/corpus-briefs/'`, on the same frozen-history grounds as `CHANGELOG.md`, and update the header comment `CHANGELOG.md is excluded (frozen release history)` and the `cited_anchors` comment to name it. Reason: the history keep-row fixture `fixtures/corpus-briefs/done/2026-09-15-verify-auth-pause.md` cites `docs/RESULT_SCHEMAS.md` §VERIFY_RESULT, a heading this PR deletes, and no split file can resolve it afterwards. No other citation is excluded. Every live citation of a deleted anchor is removed at its source instead (see `build-capabilities.sh` and `AGENT_GUIDELINES.md` below).
- **`loomwright/scripts/build-capabilities.sh`** — comment-only: in `is the --verify mode's block (docs/RESULT_SCHEMAS.md opening paragraph, §VERIFY_RESULT).` drop the `, §VERIFY_RESULT` citation. Every executable line and the rest of the `QA_RESULT`/`VERIFY_RESULT` name-map comment stay for item 12. gated by: ci.yml's `run: bash loomwright/scripts/build-capabilities.sh --check` — a comment edit changes no generated output.
- **`loomwright/docs/RESULT_SCHEMAS.md`** — keep: every non-QA `## <NAME>` section and its `See [result-schemas/<x>.md]` pointer, plus the `FLOOR_PROJECTION` clause of the version list (`scripts/test-build-floor.sh` parses this file). Remove the sections `## QA_RESULT`, `## GATE_VERDICT (pre-execution gate audit)`, `## QA_SESSION`, `## MISSING_FUNCTIONALITY_REPORT`, `## GRAPHQL_RISK_OVERRIDES`, `## VERIFY_ENV`, `## VERIFY_EVIDENCE`, `## VERIFY_RESULT` and `## VERIFY_QUEUE`. Remove the `GATE_VERDICT`, `VERIFY_EVIDENCE` and `VERIFY_RESULT` clauses of the "Current versions" line, and rewrite the "Deliberate exception" paragraph so it covers `PRODUCT_CONTEXT` only, with no `VERIFY_ENV` or `.agent/verify.json`. Every `11b2` re-point token in this file must be absent afterwards.
- **`AGENT_GUIDELINES.md`, `CLAUDE.md`, `README.md`, `.claude-plugin/README.md`** — doc re-points: drop the `propose-verify.sh` row and the `propose-verify.sh` / `read-verify.sh` / `.agent/verify.json` sentences from §"Sole-writer confirm gates", including the `(docs/RESULT_SCHEMAS.md §VERIFY_ENV)` citation (a deleted anchor `test-result-schemas-split.sh` check F would flag), with no literal writer count left (House Rules). Drop `QA_SYSTEM_BLUEPRINT` from `CLAUDE.md`'s References brace list (`ARCHITECTURE,QA_SYSTEM_BLUEPRINT,TELEMETRY`), the `README.md` bullet `**loomwright/docs/QA_SYSTEM_BLUEPRINT.md:** QA system architecture`, and the `.claude-plugin/README.md` tree line `QA_SYSTEM_BLUEPRINT.md           # QA system architecture`. pinned by: `scripts/check-doc-currency.sh`.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-run-ground-truth.sh` — the `qa-executor:` deferred arm (AC4, kept unchanged) | delete `append_check "qa-executor" "$target" "unverified"` in `loomwright/scripts/run-ground-truth.sh` |
| `loomwright/scripts/test-check-qa-removal-manifest.sh` — keep-row presence (AC1, kept unchanged) | delete `qa-executor:*)` in `loomwright/scripts/exec-acceptance-lib.sh` |
| `loomwright/scripts/test-result-validators.sh` — the re-pointed parser case `"CODE_REVIEW_RESULT"), False)` (changed pin) | flip `    if names:` → `    if False:` in `loomwright/scripts/result_block_parser.py` (`has_result_block` then ignores its name argument and matches any `*_RESULT` header, including the text's `## WORKER_RESULT`, so the case returns `True` and turns red) |

The pins this PR removes (sections E/E2 of `test-result-validators.sh`, the four `verify-helpers.sh` arms of `test-propose-from-verify.sh`, the baseline rows) go together with their subjects, so no surviving code is left to mutate. No new pin is added; the one changed pin is the parser case row above.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Delete the 25 `11b2` paths; re-point `RESULT_SCHEMAS.md`, `vendor-coupling-manifest.json` and the four top-level docs | AC1, AC2 (its files), AC7 | 6 modify, 0 create, 25 delete | `skills/quality-checklist/SKILL.md` | LAUNCHABLE |
| 2 | Remove the CI Playwright pin/cache steps; re-point every test/gate that names a deleted file | AC2 (its files), AC3, AC4, AC5, AC6, AC8 | 14 modify, 0 create | `skills/quality-checklist/SKILL.md`, `skills/ci-cd/SKILL.md` | BLOCKED (by #1) |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/docs/RESULT_SCHEMAS.md"}
  - {kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "## CODE_REVIEW_RESULT"}
  - {kind: "file", path: "loomwright/docs/vendor-coupling-manifest.json"}
requires: []
lanes:
  - "loomwright/docs/QA_SYSTEM_BLUEPRINT.md"
  - "loomwright/docs/result-schemas/gate-verdict.md"
  - "loomwright/docs/result-schemas/graphql-risk-overrides.md"
  - "loomwright/docs/result-schemas/missing-functionality-report.md"
  - "loomwright/docs/result-schemas/qa-result.md"
  - "loomwright/docs/result-schemas/qa-session.md"
  - "loomwright/docs/result-schemas/verify-env.md"
  - "loomwright/docs/result-schemas/verify-evidence.md"
  - "loomwright/docs/result-schemas/verify-queue.md"
  - "loomwright/docs/result-schemas/verify-result.md"
  - "loomwright/scripts/propose-verify.sh"
  - "loomwright/scripts/read-playwright-pin.sh"
  - "loomwright/scripts/read-verify.sh"
  - "loomwright/scripts/result-validator-fixtures/qa-result-valid.md"
  - "loomwright/scripts/test-read-playwright-pin.sh"
  - "loomwright/scripts/test-verify-evidence.sh"
  - "loomwright/scripts/test-verify-queue.sh"
  - "loomwright/scripts/test-verify-seam.sh"
  - "loomwright/scripts/test-verify-walkthrough.sh"
  - "loomwright/scripts/validate-qa-result.py"
  - "loomwright/scripts/validate-verify-evidence.py"
  - "loomwright/scripts/verify-env.sh"
  - "loomwright/scripts/verify-fixture-app.py"
  - "loomwright/scripts/verify-helpers.sh"
  - "loomwright/scripts/verify-run.sh"
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "AGENT_GUIDELINES.md"
  - "CLAUDE.md"
  - "README.md"
  - ".claude-plugin/README.md"
external_requires: []

# Subtask 2
provides:
  - {kind: "symbol", path: ".github/workflows/ci.yml", name: "run-self-tests.sh --shard"}
  - {kind: "symbol", path: "loomwright/scripts/test-result-validators.sh", name: "F. plan-reviewer validator"}
  - {kind: "symbol", path: "loomwright/scripts/test-propose-from-verify.sh", name: "AC-supersede"}
requires:
  - {from: "1", kind: "file", path: "loomwright/docs/vendor-coupling-manifest.json"}
lanes:
  - ".github/workflows/ci.yml"
  - "scripts/ci-local.sh"
  - "scripts/check-contract-parity.sh"
  - "scripts/test-ci-local.sh"
  - "loomwright/scripts/test-result-validators.sh"
  - "loomwright/scripts/test-propose-from-verify.sh"
  - "loomwright/scripts/fixtures/self-test-weights.tsv"
  - "loomwright/scripts/test-no-fixed-sleep-race.sh"
  - "loomwright/scripts/test-no-pipefail-grep-q.sh"
  - "loomwright/scripts/test-script-event-telemetry.sh"
  - "loomwright/scripts/test-telemetry-threads.sh"
  - "loomwright/scripts/test-base-branch-single-resolver.sh"
  - "loomwright/scripts/test-result-schemas-split.sh"
  - "loomwright/scripts/build-capabilities.sh"
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2
```

Subtask 2 runs after Subtask 1. Its baseline lists (`test-no-fixed-sleep-race.sh`, `test-no-pipefail-grep-q.sh`) and copy lists only match the tree once Subtask 1's deletions have landed, and its suites (AC4–AC6, AC8) are verified against that tree.

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none (ordered by `requires`, not by overlap) | YES (dependency) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after Subtask 1)
- **Recommended workers:** 1
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/quality-checklist/SKILL.md` |
| 2 | `skills/quality-checklist/SKILL.md`, `skills/ci-cd/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): 25 deletes + 18 modifies exceed one worker's file bound | MEDIUM | `context-bound` split into two sequential subtasks; deletions are `git rm`, and the edits are listed per file under `## Touched-file invariants` |
| Feasibility (Phase 2.5): the manifest's `11b2` rows reach 16 paths outside the requirement's `## Touches` | MEDIUM | Owner decides at Launch Pad Phase 6 (`LP-SCOPE`); the manifest, not the Touches list, is the item's stated authority ("works strictly from 11a's manifest rows marked `11b2`") |
| A test outside the manifest sources or copies a deleted helper (requirement risk) | MEDIUM | Repo-wide `git grep -F` of each deleted basename was run at base; every executable hit is in the File Impact Map. Re-run `git grep -nE 'verify-helpers\.sh\|validate-verify-evidence\|validate-qa-result\|verify-run\.sh\|read-verify\.sh\|read-playwright-pin\|verify-fixture-app\|propose-verify\.sh' -- loomwright scripts .github` after the deletes. Any new executable hit becomes a manifest row before merge, per the requirement |
| A `RESULT_SCHEMAS.md §<anchor>` citation of a deleted section survives in a tracked file and fails `test-result-schemas-split.sh` check F (it scans citations, not script names, so the basename grep above misses it) | MEDIUM | At base, the only surviving citations outside deleted files and removed sections are the corpus-brief fixture (excluded as history), `build-capabilities.sh`'s comment and `AGENT_GUIDELINES.md`'s `§VERIFY_ENV` (both re-pointed). After the deletes, re-run `git grep -nE 'RESULT_SCHEMAS[^§]*§ ?"?(QA_|VERIFY_|GATE_VERDICT|MISSING_FUNCTIONALITY|GRAPHQL_RISK)' -- . ':!CHANGELOG.md' ':!loomwright/scripts/fixtures/corpus-briefs/'` and expect no output, then run `bash loomwright/scripts/test-result-schemas-split.sh` |
| `test-send-telemetry-core.sh` (a manifest row marked `12`) copies `validate-qa-result.py` in `copy_core_siblings`; its header has no `set -e`, so the `cp` likely only prints an error | LOW | If the full CI run shows it red, drop that one name from its copy list in this PR and note it. Its other `12` rows stay for item 12 |
| `scripts/ci-local.sh` derives its gate plan from ci.yml lines; deleting steps could drop a gate | LOW | Only the Playwright `run:` line (`bash loomwright/scripts/read-playwright-pin.sh`, not a gate form) and the cache step go. `test-ci-local.sh` pins the plan |
| No `changelog.d/` fragment ⇒ no version bump, so marketplace installs keep the deleted files until the next release | LOW | Matches the requirement's assumption (the user-facing note shipped in 11b1). The owner may add one fragment at review |
| `build-capabilities.sh --check` regeneration drift after deleting validators it names (item 12 row) | LOW | CI runs the `--check` gate; if it goes stale, regenerate `loomwright/capabilities.json` and say so in the PR |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-19-qa-split-11b2-remove-qa-scripts-ci.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-11-19T13:36:27Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/950
- **Branch:** feature/qa-split-11b2-remove-qa-scripts-ci
- **Files changed:** 51
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** unknown (no_driver_handover)
- **Summary:** Removed the QA scripts, VERIFY_* schema docs, QA blueprint and CI Playwright/Chromium steps (qa-split 11b2), re-pointing every 11b2 manifest row. Phase 4.5: round 1 FAIL (pin-mutation 2 not_held, telemetry-core copy list) fixed in c11445b; round 2 reviewer PASS turned FAIL by two red required checks (qa-failed golden, hermetic-egress leg P) fixed in 1bb0a2f; round 3 PASS with 2 LOW notes dismissed. CI green on 1bb0a2f. Ground truth 2/2 pass; risk classification high_risk (size, workflow path). Until-mergeable drain left to the /automate owned drain (suppressed_default_dispatch).

## Not verified
- **test-result-schemas-split.sh check F3** — green only after subtask 2 (subtask 1)
- **ci-local.sh --affected / CI ci check (AC8)** — owned by subtask 2 (subtask 1)
- **.github/workflows/ci.yml suite job on GitHub Actions** — runs on the PR; YAML parses and ci-local gate plan matches base (subtask 2)
