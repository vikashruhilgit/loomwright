# Supervisor Job: Re-point Loomwright's remaining QA couplings to Selvedge (qa-split item 12)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** dirty (2 untracked dirs: `reports/`, `research_notes/`, unrelated to this item), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 2 (untracked dirs; 6 extra worktrees, one prunable)
- **Source requirement:** .supervisor/requirements/qa-split/12-re-point-qa-couplings-to-selvedge.md
- **Base commit:** 22c70ce4de56477b4a45e71933e899b29f00cd5f

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 + jq + python3 scripts and Markdown docs, as the rest of `loomwright/scripts/` |
| 2 | Dependency Availability | GO | No new dependency. `verdict.json` is read with `jq` as data; its shape is `selvedge/schemas/verdict.schema.json` (`"schema_version": { "const": 1 }`) |
| 3 | Architecture Fit | GO | D4 holds: Loomwright reads one JSON file and imports nothing from `selvedge/` |
| 4 | Scope vs Supervisor Capability | CAUTION | 48 files modified + 1 created + 2 deleted, most of them small doc edits; over the `context-bound` bound, so it is split into 3 serial subtasks |
| 5 | Hard Blockers | GO | 11b2 merged (#950, base `22c70ce`). `check-qa-removal-manifest.sh --expect 12` currently prints 135 MISMATCH rows, all owned by this item |

**Overall Verdict:** CAUTION

## Task
**Goal:** Clear every remaining `check-qa-removal-manifest.sh --expect 12` MISMATCH row. Swap `classify-risk.sh`'s trusted root-only path `.agent/verify.json` → `selvedge.json`, make `/propose --from-verify <run_dir>` read Selvedge's `verdict.json`, and drop the old QA names from the name maps (notify, webhook, telemetry, token ledger, result-block parser, capabilities builder), agent-help, docs and tests. Then wire the `--expect 12` gate into the CI-globbed self-test, so a removed name that returns turns CI red.

**Problem Statement:**
The plugin's maintainer needs every manifest `re-point` row moved to its new target, each pinned by a test, so no surface silently reads a file nothing writes any more and the old names can't creep back.
Currently, after 11b1/11b2, `/propose --from-verify` reads `/verify`'s `evidence.jsonl`, which nothing writes now. `classify-risk.sh` guards `.agent/verify.json`, not Selvedge's `selvedge.json`. And 135 manifest rows still name the old QA agents, schemas and scripts. Nothing in CI runs the manifest gate at any `--expect` level (`grep -rn check-qa-removal-manifest .github scripts` → no hits), so nothing stops the names coming back.
Success looks like: `check-qa-removal-manifest.sh --expect 12` exits 0, and a CI-globbed test fails as soon as any re-pointed reference returns.

## Acceptance Criteria
- [ ] AC1 — Given this branch, when `bash loomwright/scripts/check-qa-removal-manifest.sh --expect 12` runs, then it exits 0 (summary `0 MISMATCH`). If a manifest row turns out wrong or over-broad, the row is corrected in `loomwright/docs/qa-removal-manifest.md` (with its `Row count:` line) in this PR, never worked around.
- [ ] AC2 — Given a PR diff that edits (adds / edits / deletes) a repo-root `selvedge.json`, when `classify-risk.sh` runs, then `high_risk` is `true` with reason `trusted-root: selvedge.json`. Given a diff whose only change is `.agent/verify.json`, then that path alone yields no `trusted-root:` reason and is not high-risk. Given `sub/selvedge.json` (not at the root), then no `trusted-root:` reason. `classify-risk.sh --kind-table` names `selvedge.json`, and the committed table between `<!-- risk-table:begin -->` / `<!-- risk-table:end -->` in `loomwright/docs/result-schemas/supervisor-result.md` matches it byte for byte.
- [ ] AC3 — Given a Selvedge run folder whose `verdict.json` (schema_version 1) has 1 FAIL and 2 PASS criteria, when `propose-from-verify.sh <run_dir>` (`/propose --from-verify <run_dir>`) runs, then it exits 0 and writes exactly one candidate under the output dir (default `.supervisor/requirements/proposed/`). The candidate cites the criterion id, its `interpretation`, the expected value (`op` + `value`, or `none`), the failed step (`failed_step` index and that step's `type`, looked up as `steps[] | select(.step == failed_step)`, never by array position; or `none`), the run id, and the `plan_sha256`. It carries `## Depends on`, `## Touches` and `## Status: proposed`. A re-run against the unchanged folder rewrites the same file byte for byte (no duplicate). BLOCKED and NOT_VERIFIABLE criteria never produce a candidate. Nothing outside the output dir is written (the existing find-diff check is kept).
- [ ] AC4 — Given a run folder with no `verdict.json`, a `verdict.json` that is not valid JSON or lacks a required field (`schema_version`, `plan_sha256`, `criteria`, or a criterion's `verdict`), or one whose `schema_version` is not `1`, when the script runs, then it writes no file, prints a one-line reason on stderr naming the case (`verdict_missing`, `verdict_malformed`, `unknown_schema_version`), and exits non-zero (2). It never writes an empty or partial proposal: the whole file is validated before the first write. The same holds, with reasons `jq_missing` and `run_dir_missing`, when `jq` is absent or the run dir does not exist.
- [ ] AC5 — Given the dreaming agent list and every name map (notify-desktop / send-webhook transcript regex, `send-telemetry-core.sh` `SCHEMA_NAMES` / validator map / rubric, `emit-token-ledger.sh`, `result_block_parser.py`, `build-capabilities.sh` precedence map), then `qa-executor`, `qa-strategist`, `QA_RESULT` and `VERIFY_RESULT` do not appear in them. The `QA_RESULT` telemetry rubric, its `qa-failed.json` fixture and its golden are removed. A test pins this (AC7).
- [ ] AC6 — Given `loomwright/scripts/propose-from-verify.sh`, then it sources nothing and runs nothing from `selvedge/` (no `selvedge/` path, no `selvedge` CLI call, no `node`): it reads `verdict.json` as data with `jq` only (D4). `test-propose-from-verify.sh` pins this with a grep over the script's code lines.
- [ ] AC7 — Given `loomwright/scripts/test-check-qa-removal-manifest.sh` (CI runs it through the `loomwright/scripts/test-*.sh` glob), then it has a live-repo arm, labelled `live-expect-12`, that runs the real checker with `--expect 12` against this checkout and fails on any MISMATCH. Re-adding a removed reference to any re-pointed file (e.g. `/qa-executor` back into `notify-desktop.sh`'s transcript regex) turns it red.
- [ ] AC8 — Given the branch, when `bash scripts/ci-local.sh --affected` runs, then it passes, and `bash scripts/check-version-bump.sh` passes with one `changelog.d/qa-split-12-re-point-qa-couplings.md` fragment (`<!-- bump: minor -->`). CI `ci` is then green.

## Scope widening
- .claude-plugin/README.md
- AGENT_GUIDELINES.md
- README.md
- loomwright/capabilities.json
- loomwright/docs/ARCHITECTURE.md
- loomwright/docs/CAPABILITIES_CONTRACT.md
- loomwright/docs/FAILURE_ESCALATION.md
- loomwright/docs/TELEMETRY.md
- loomwright/docs/command-parts/agent-help/*.md
- loomwright/docs/qa-removal-manifest.md
- loomwright/docs/result-schemas/*.md
- loomwright/docs/result-schemas/automate-run/crash-safety.md
- loomwright/docs/result-schemas/supervisor-result.md
- loomwright/scripts/telemetry-fixtures/golden/*
- loomwright/scripts/telemetry-fixtures/golden/qa-failed__allow_with_repo.golden.txt
- loomwright/scripts/telemetry-fixtures/qa-failed.json
- loomwright/scripts/test-automate-helpers.d/07-rules-gate.sh
- loomwright/scripts/test-check-qa-removal-manifest.sh
- loomwright/scripts/test-committed-twin-scrub.sh
- loomwright/scripts/test-emit-block-parses.sh
- loomwright/scripts/test-insights.sh
- loomwright/scripts/test-not-verified-transport-seam.sh
- loomwright/scripts/test-proc-registry.sh
- loomwright/scripts/test-send-telemetry-core.sh
- loomwright/scripts/test-telemetry.sh
- loomwright/scripts/test-token-ledger.sh
- loomwright/scripts/write-agent-memory.sh
- loomwright/skills/ci-cd/SKILL.md
- loomwright/skills/memory-tool/SKILL.md
- loomwright/skills/telemetry/SKILL.md
- loomwright/skills/unit-testing/SKILL.md
- accepted: LP-SCOPE 2026-11-19

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- Wording that carries a contract — a heading a gate greps for, a sentence that states a guarantee — is treated as an interface: renaming it is a change to that interface and its consumers move with it.
  - id: documentation-wording-that-carries-a-contract-a-heading-a-gate-greps-for-a-sentence-that-states-a-guarantee-is-treated-as-an-interface-renaming-it-is-a-change-to-that-interface-and-its-consumers-move-with-it
  - enforcement: advisory
  - category: documentation
  - check (data only, NOT executed by this reader): (none)
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

## Implementation notes (from analysis)
- **The work list is the checker's own output.** `bash loomwright/scripts/check-qa-removal-manifest.sh --expect 12 2>/dev/null | grep '^MISMATCH'` lists every row. 133 are `re-point` and 2 are `delete` (`loomwright/scripts/telemetry-fixtures/qa-failed.json` and `loomwright/scripts/telemetry-fixtures/golden/qa-failed__allow_with_repo.golden.txt`). Nine of the re-point rows are tagged `11b1` but are still open, and `--expect 12` checks them too: `README.md` and `.claude-plugin/README.md` (`qa-executor`, `qa-strategist`, `/verify`), `loomwright/capabilities.json` (`/verify`, from `/propose`'s description), `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (`qa-executor`, `qa-strategist`, in the dated tool-grant note) and `loomwright/scripts/test-committed-twin-scrub.sh` (a fixture path `loomwright-loomwright-qa-executor`; rename it to another agent's store).
- **The README migration pointers.** The `> /qa-strategist, /qa-executor and /verify were removed — install Selvedge …` lines in `README.md` and `.claude-plugin/README.md` are what trips their rows. Reword them so they point at Selvedge (`/selvedge:verify`) and at `loomwright/docs/rationale/qa-split.md` without the old literal names. `/selvedge:verify` does not contain `/verify`. The migration narrative belongs to item 13 (`changelog.d/` + rationale doc).
- **Keep rows must still hold.** The `qa-executor:` Executable Acceptance kind stays until item 09. The keep rows on `completion-tail.md`, `supervisor-readiness/SKILL.md`, `schema-versioning.md` (`cmd|corpus-task|qa-executor`) and `supervisor-result.md` (`qa-executor`) must still match, so edit around the `qa-executor:` kind text, never through it. `test-classify-risk.sh` keeps `.agent/verify.json` (keep row): it is now the negative case.
- **`verdict.json` contract (read as data, D4):** `selvedge/schemas/verdict.schema.json`. The schema requires ten top-level fields and ten per criterion. Test fixtures carry the full required key set, so they look like real Selvedge output. The fields this script reads and validates are `schema_version` (const 1), `plan_sha256` (64 hex) and `criteria` (an object keyed `c-<12 hex>`). Each criterion has `verdict` ∈ PASS|FAIL|BLOCKED|NOT_VERIFIABLE, `expected` ({op,value} or null), `failed_step` (int or null), `interpretation` (string or null) and `steps[]` ({step,type,outcome,duration_ms}; each entry carries its own `step` index, so the failed step is found with `select(.step == failed_step)`). The run id is the folder's basename (`.selvedge/runs/<run-id>/`). The script reads only these fields and only `verdict.json`: not `criteria.json`, `plan.json` or `evidence.jsonl`.
- **Exit contract change.** The script's header paragraph beginning `FAIL-SAFE. \`set -uo pipefail\``, plus its `Exit:   0 always.` usage line, currently promise exit 0 always. AC4 (owner AC) makes an unusable input exit 2 with nothing written. Rewrite the header's FAIL-SAFE paragraph to the new contract. It is a human-invoked `/propose` basis, not a hook emitter: no hook and no script calls it (`grep -rn 'propose-from-verify.sh' loomwright/hooks` → none). Its only caller is `commands/propose.md`, which must say what a non-zero exit means.
- **Candidate filename** stays derived, never counted: `verify-<run_id>-<criterion_id>.md`, which keeps the `/propose` idempotence rule.

## Touched-file invariants

> Grounded at base `22c70ce4de56477b4a45e71933e899b29f00cd5f`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/classify-risk.sh`**. Keep: `set -fuo pipefail` (noglob: trusted-root entries stay PLAIN words with no `*`, `?` or `[`, and `selvedge.json` is one) and `Output (ONE JSON object on stdout, always exit 0)`. Reuse: the data list `TRUSTED_ROOT_ROOTONLY=`. The swap is a one-word edit to that list, and the symlink-ancestor comment that names `.agent/verify.json` is updated too (the manifest row is a fixed-string grep on the whole file). Mirror: `--kind-table` output must equal the block between `<!-- risk-table:begin -->` / `<!-- risk-table:end -->` in `loomwright/docs/result-schemas/supervisor-result.md`. Pinned by: `test-classify-risk.sh` `E1 --kind-table output == RESULT_SCHEMAS`, the E3 needle ``trusted-root .*`CLAUDE.md`.*`.agent/verify.json``, which moves to `selvedge.json`, and the `tr_case "J2f`/`J3a`/`J3b`/`J3c` cases, which are re-pointed to `selvedge.json` with a new negative `.agent/verify.json` case.
- **`loomwright/scripts/propose-from-verify.sh`**. Keep: the sourced guard `pc_guarded_write` (never an inline write), `PROPOSE_COMMON_SH`, `PROPOSE_FROM_VERIFY_OUT_DIR`, the `## Depends on` / `## Touches` / `## Status: proposed` sections, and the function `vt_touches() {` byte for byte. Also keep `test-propose-from-verify.sh`'s symlink / `.git` Touches-containment fixtures, which `test-automate-dismissed.sh` A12 mirrors (`mirrors test-propose-from-verify.sh`). Feed them through `interpretation` text; never drop them in the rewrite. Grammar copy 3 of 3 is extracted by `sed -n '/^vt_touches() {$/,/^}$/p'` in `test-automate-helpers.d/13-plan-waves.sh` (X7), so feed it `interpretation` text and leave its body unchanged. Pinned by: `test-hermetic-egress.sh`'s `^propose-from-verify: [1-9][0-9]* passed, 0 failed$` (keep the test's summary line format), and the keep rows naming `propose-from-verify.sh` in `propose-common.sh`, `automate-dismissed.sh` and `plan-waves.sh` (keep the filename).
- **`loomwright/scripts/send-telemetry-core.sh`**. Keep: privacy `fail-closed exit 2 BEFORE everything` and the always-exit-0 emitter paths. Fired by: the `send-telemetry` wrapper on `SubagentStop` `loomwright:code-reviewer` and `loomwright:supervisor-runner` (`loomwright/hooks/hooks.json`). The QA matcher went in 11b1, so no remaining matcher feeds a `QA_RESULT`. Mirror: `SCHEMA_NAMES = (` and the schema→validator map lose `QA_RESULT` together with the `Rubric C — QA_RESULT` branch; `loomwright/docs/TELEMETRY.md` and `loomwright/skills/telemetry/SKILL.md` restate the rubric set and move in the same change. Pinned by: `test-send-telemetry-core.sh` (`real_shape_qa_task_type`), whose QA arms are removed, and `test-telemetry.sh`'s fixture matrix row `qa-failed.json`. Regenerate the goldens with `WRITE_GOLDENS=1` only if a remaining golden changes.
- **`loomwright/scripts/notify-desktop.sh`, `loomwright/scripts/send-webhook.sh`** (shared invariant). Keep: final `exit 0` (fail-SAFE emitters) and the transcript detector `grep -qE 'loomwright:|/launch-pad|/supervisor|/autonomous|/code-reviewer|`, minus `/qa-executor|/qa-strategist` only. In `send-webhook.sh` the `verify_needs_auth/verify_first_fail/verify_run_end` event comment that names `verify-helpers.sh` is dropped. Fired by (`loomwright/hooks/hooks.json`): `notify-desktop.sh` on `Notification` (`permission_prompt|idle_prompt|elicitation_dialog|elicitation_complete|elicitation_response`) and `PreToolUse` `AskUserQuestion`; `send-webhook.sh` on `PreToolUse` `AskUserQuestion` and `SubagentStop` `loomwright:supervisor-runner`. Every one of these paths must still exit 0.
- **`loomwright/scripts/build-capabilities.sh`**. Keep: sole writer of `loomwright/capabilities.json`, and `--check     regenerate to a temp file and compare byte-for-byte` (the staleness gate). Mirror: these go together: both block-precedence map entries (`"MISSING_FUNCTIONALITY_REPORT,QA_RESULT,VERIFY_RESULT": "QA_RESULT",` and `"QA_RESULT,VERIFY_RESULT": "QA_RESULT"`), the explanatory comment block naming `qa-executor.md`, and the `w validate-qa-result.py -` row. Fix the trailing comma left on the new last map entry. Regenerate `capabilities.json` with `bash loomwright/scripts/build-capabilities.sh` after every source change (subtasks 1 and 2 both do), and confirm with `--check`. Pinned by: `test-build-capabilities.sh`.
- **`loomwright/scripts/result_block_parser.py`, `loomwright/scripts/emit-token-ledger.sh`, `loomwright/scripts/write-agent-memory.sh`**. These are comment and docstring edits only, and no behavior changes. Anchors: `plan-reviewer, qa-executor)`, `WERE TAKEN WHEN THERE WERE THREE`, `The existing H1 title line is PRESERVED`. `result_block_parser.py`'s command-validator output shape (`{}` / `{"decision": "block", …}`) is untouched. `emit-token-ledger.sh` is fired on `SubagentStop` for every remaining loomwright agent matcher (`loomwright/hooks/hooks.json`). Its edit is comment-only, so its fail-safe exit is unchanged on all of them.
- **Fixture-rename tests: `loomwright/scripts/test-token-ledger.sh`, `test-emit-block-parses.sh`, `test-insights.sh`, `test-proc-registry.sh`, `test-automate-helpers.d/07-rules-gate.sh`, `test-committed-twin-scrub.sh`** (shared invariant). Keep: each test's assertions, its arm count and its summary-line format. Rename only the fixture value, to another real agent or file (for example `agent_type: "loomwright:qa-executor"` → a surviving agent such as `loomwright:code-reviewer`, and `.claude/agent-memory/loomwright-loomwright-qa-executor/MEMORY.md` → another agent's store). In `test-emit-block-parses.sh`, drop `"QA_RESULT", "VERIFY_RESULT",` from the `blocks = ("WORKER_RESULT", "EXECUTE_RESULT", "EXECUTE_CHECKPOINT", ` tuple only together with their emitters (both schemas went in 11b2).
- **`loomwright/skills/self-heal-advisory/completion-tail.md`**. Keep: the `qa-executor:` kind text (keep row). Pinned by: `test-not-verified-transport-seam.sh`, whose case `*'/verify'*'acs <ticket>'*'the PR body'*` pins this file's `/verify` wording. The test and the prose move together (same subtask).
- **`loomwright/scripts/test-check-qa-removal-manifest.sh`**. Keep: first executable line `. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"` and the offline `mktemp -d` fixture arms. The new `live-expect-12` arm only reads the checkout (no writes) and runs the real `check-qa-removal-manifest.sh --expect 12`.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-classify-risk.sh` — the `selvedge.json` trusted-root cases (J2f/J3a–c re-pointed) | flip `.agent/risk.json selvedge.json'` → `.agent/risk.json'` in `loomwright/scripts/classify-risk.sh` |
| `loomwright/scripts/test-classify-risk.sh` — the new negative `.agent/verify.json` case | flip `.agent/risk.json selvedge.json'` → `.agent/risk.json selvedge.json .agent/verify.json'` in `loomwright/scripts/classify-risk.sh` |
| `loomwright/scripts/test-propose-from-verify.sh` — 1 FAIL + 2 PASS ⇒ exactly one candidate | flip `SUPPORTED_SCHEMA_VERSION=1` → `SUPPORTED_SCHEMA_VERSION=2` in `loomwright/scripts/propose-from-verify.sh` |
| `loomwright/scripts/test-propose-from-verify.sh` — only FAIL criteria are drafted (PASS/BLOCKED/NOT_VERIFIABLE never) | flip `select(.value.verdict == "FAIL")` → `select(.value.verdict != "BLOCKED")` in `loomwright/scripts/propose-from-verify.sh` |
| `loomwright/scripts/test-propose-from-verify.sh` — malformed `verdict.json` ⇒ exit 2, zero files | reviewer-applied: move the first `pc_guarded_write` call ahead of the whole-file validation in `loomwright/scripts/propose-from-verify.sh` (a partial write must turn the zero-files assertion red) |
| `loomwright/scripts/test-check-qa-removal-manifest.sh` — `live-expect-12` | flip `/code-reviewer|/red-team-reviewer|` → `/code-reviewer|/qa-executor|/red-team-reviewer|` in `loomwright/scripts/notify-desktop.sh` |
| `loomwright/scripts/test-check-qa-removal-manifest.sh` — `live-expect-12` (telemetry name map) | flip `"CODE_REVIEW_RESULT")` → `"CODE_REVIEW_RESULT", "QA_RESULT")` in `loomwright/scripts/send-telemetry-core.sh` |
| `loomwright/scripts/test-send-telemetry-core.sh` — `no_qa_schema_scored` | flip `"CODE_REVIEW_RESULT")` → `"CODE_REVIEW_RESULT", "QA_RESULT")` in `loomwright/scripts/send-telemetry-core.sh` |
| `loomwright/scripts/test-classify-risk.sh` — E3 needle (now ``trusted-root .*`CLAUDE.md`.*`selvedge.json` ``) | flip `.agent/risk.json selvedge.json'` → `.agent/risk.json'` in `loomwright/scripts/classify-risk.sh` (the `--kind-table` row loses `selvedge.json`, so E3 turns red alongside J2f/J3a–c) |
| `loomwright/scripts/test-propose-from-verify.sh` — `unknown_schema_version` refusal (a `schema_version: 2` fixture ⇒ exit 2, zero files) | reviewer-applied: delete the `schema_version` comparison against `SUPPORTED_SCHEMA_VERSION` in `loomwright/scripts/propose-from-verify.sh` (the v2 fixture is then drafted, so the zero-files / exit-2 assertion turns red) |
| `loomwright/scripts/test-propose-from-verify.sh` — `verdict_missing` / `verdict_malformed` / `jq_missing` / `run_dir_missing` refusals | reviewer-applied: replace the refusal's `exit 2` with `exit 0` in `loomwright/scripts/propose-from-verify.sh` (the exit-code assertion turns red) |
| `loomwright/scripts/test-propose-from-verify.sh` — AC6 D4 grep (no `selvedge/` path, no `selvedge` CLI, no `node` in code lines) | reviewer-applied: add a code line `. "$SCRIPT_DIR/../../selvedge/lib/verdict.mjs"` (or `node selvedge/bin/selvedge verdict "$RUN_DIR"`) to `loomwright/scripts/propose-from-verify.sh` |
| `loomwright/scripts/test-propose-from-verify.sh` — failed-step `type` looked up by `.step`, never array position (the fixture's FAIL criterion lists `steps[]` out of index order, e.g. `step` 2 first, so position and index disagree) | reviewer-applied: replace `select(.step == failed_step)` with a positional `.steps[failed_step]` lookup in `loomwright/scripts/propose-from-verify.sh` (the step-type assertion turns red) |
| `loomwright/scripts/test-classify-risk.sh` — `sub/selvedge.json` negative case (no `trusted-root:` reason off the root) | reviewer-applied: make the root-only match in `loomwright/scripts/classify-risk.sh` also accept a `*/selvedge.json` suffix, i.e. treat `selvedge.json` like the any-depth list (the `sub/selvedge.json` case turns red) |
| `loomwright/scripts/test-propose-from-verify.sh` — AC3 byte-for-byte idempotence on re-run | reviewer-applied: add a `date -u` timestamp line to the candidate body in `loomwright/scripts/propose-from-verify.sh` (the second run differs, so `cmp` turns red) |

The implementing worker writes these literals, each occurring exactly once in its file, so the machine-applicable rows resolve: `SUPPORTED_SCHEMA_VERSION=1`, `select(.value.verdict == "FAIL")`, `.agent/risk.json selvedge.json'`, `/code-reviewer|/red-team-reviewer|` (notify-desktop.sh) and `"CODE_REVIEW_RESULT")` (send-telemetry-core.sh, the `SCHEMA_NAMES = (` line).

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Behavior: `classify-risk.sh` trusted-path swap + `/propose --from-verify` reads `verdict.json` | AC2, AC3, AC4, AC6 | 7 modify, 0 create | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` | LAUNCHABLE |
| 2 | Name maps and their tests: notify, webhook, telemetry, token ledger, parser, capabilities builder | AC5 | 20 modify, 0 create, 2 delete | `skills/unit-testing/SKILL.md` | BLOCKED (by #1) |
| 3 | Docs / agent-help sweep + the live `--expect 12` pin + changelog fragment | AC1, AC7, AC8 | 22 modify, 1 create | `skills/quality-checklist/SKILL.md` | BLOCKED (by #2) |

### File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| 1 risk + propose | `loomwright/scripts/classify-risk.sh` (465), `loomwright/scripts/test-classify-risk.sh` (863 — the existing trusted-root J-series is the one home for these cases; append there), `loomwright/docs/result-schemas/supervisor-result.md` (235), `loomwright/scripts/propose-from-verify.sh` (250), `loomwright/scripts/test-propose-from-verify.sh` (276), `loomwright/commands/propose.md` (143), `loomwright/capabilities.json` (1227 — generated, regenerated not hand-edited) | — | HIGH |
| 2 name maps | `loomwright/scripts/notify-desktop.sh` (563 — one regex alternation removed, no new responsibility), `loomwright/scripts/send-webhook.sh` (670 — same), `loomwright/scripts/send-telemetry-core.sh` (1499 — removal only), `loomwright/scripts/test-send-telemetry-core.sh` (1233 — removal only), `loomwright/scripts/test-telemetry.sh` (559 — removal only), `loomwright/scripts/emit-token-ledger.sh` (948 — comment), `loomwright/scripts/test-token-ledger.sh` (1934 — fixture agent_type rename), `loomwright/scripts/result_block_parser.py` (1635 — comment/docstring), `loomwright/scripts/test-emit-block-parses.sh` (132), `loomwright/scripts/build-capabilities.sh` (592 — map entries removed), `loomwright/capabilities.json` (1227 — regenerated), `loomwright/scripts/write-agent-memory.sh` (1020 — comment), `loomwright/scripts/test-insights.sh` (1211 — fixture agent_type rename), `loomwright/scripts/test-proc-registry.sh` (1111 — fixture filename rename), `loomwright/scripts/test-automate-helpers.d/07-rules-gate.sh` (888 — fixture dir rename), `loomwright/scripts/test-committed-twin-scrub.sh` (585 — fixture path rename), `loomwright/scripts/test-not-verified-transport-seam.sh` (305), `loomwright/skills/self-heal-advisory/completion-tail.md` (522 — wording only), `loomwright/docs/TELEMETRY.md` (2609 — removal only), `loomwright/skills/telemetry/SKILL.md` (232); delete `loomwright/scripts/telemetry-fixtures/qa-failed.json`, `loomwright/scripts/telemetry-fixtures/golden/qa-failed__allow_with_repo.golden.txt` | — | HIGH |
| 3 docs + pin | `AGENT_GUIDELINES.md` (842 — wording only), `README.md` (663 — wording only), `.claude-plugin/README.md` (570 — wording only), `loomwright/commands/agent-help.md` (412), `loomwright/docs/command-parts/agent-help/guide.md` (421), `loomwright/docs/command-parts/agent-help/knowledge.md` (122), `loomwright/docs/command-parts/agent-help/more.md` (49), `loomwright/docs/ARCHITECTURE.md` (178), `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (1040 — wording only), `loomwright/docs/CAPABILITIES_CONTRACT.md` (116), `loomwright/docs/FAILURE_ESCALATION.md` (444), `loomwright/docs/result-schemas/agent-lifecycle-jsonl.md` (293), `loomwright/docs/result-schemas/automate-run/crash-safety.md` (14), `loomwright/docs/result-schemas/execute-result.md` (82), `loomwright/docs/result-schemas/migrate-branch-mode-state.md` (42), `loomwright/docs/result-schemas/schema-versioning.md` (72), `loomwright/docs/result-schemas/validation-location.md` (7), `loomwright/skills/ci-cd/SKILL.md` (252), `loomwright/skills/memory-tool/SKILL.md` (116), `loomwright/skills/unit-testing/SKILL.md` (211), `loomwright/skills/workflow-management/SKILL.md` (442), `loomwright/scripts/test-check-qa-removal-manifest.sh` (519 — the live arm belongs beside the checker's own self-test, its one home), `loomwright/docs/qa-removal-manifest.md` (594 — only if a row is corrected) | `changelog.d/qa-split-12-re-point-qa-couplings.md` | HIGH (MEDIUM for the manifest-row corrections) |

> **Validator-owned surfaces:** AC1's validator is `check-qa-removal-manifest.sh`, and its scan set is exactly the manifest rows, all folded into the map above. `check-doc-currency.sh`, `check-token-budget.sh` (`agent-help`, `propose` command entries; shrinking stays under budget), `check-prompt-history-refs.sh` (baseline may only go down; add no history to a prompt) and `build-capabilities.sh --check` also scan files edited here, so run them through `ci-local.sh --affected`.

Every MODIFY path is a removal or a small rewording, apart from the `propose-from-verify.sh` rewrite (250 lines, under the 500 threshold, the existing home of the verify basis). No new module is warranted, and no helper is copied: the candidate write reuses `propose-common.sh`'s `pc_guarded_write` / `pc_slugify`.

### Subtask Contracts

```yaml
# Subtask 1 — classify-risk trusted-path swap + /propose --from-verify on verdict.json (LAUNCHABLE)
provides:
  - {kind: "symbol", path: "loomwright/scripts/classify-risk.sh", name: "selvedge.json"}
  - {kind: "symbol", path: "loomwright/scripts/propose-from-verify.sh", name: "SUPPORTED_SCHEMA_VERSION"}
  - {kind: "symbol", path: "loomwright/scripts/propose-from-verify.sh", name: "verdict.json"}
  - {kind: "symbol", path: "loomwright/scripts/test-propose-from-verify.sh", name: "unknown_schema_version"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/supervisor-result.md", name: "selvedge.json"}
requires: []
lanes:
  - "loomwright/scripts/classify-risk.sh"
  - "loomwright/scripts/test-classify-risk.sh"
  - "loomwright/docs/result-schemas/supervisor-result.md"
  - "loomwright/scripts/propose-from-verify.sh"
  - "loomwright/scripts/test-propose-from-verify.sh"
  - "loomwright/commands/propose.md"
  - "loomwright/capabilities.json"
external_requires:
  - "jq on PATH (already required by the propose bases)"

# Subtask 2 — name maps and their tests (BLOCKED by #1: shares loomwright/capabilities.json, regenerated after #1's propose.md edit)
provides:
  - {kind: "symbol", path: "loomwright/scripts/send-telemetry-core.sh", name: "SCHEMA_NAMES"}
  - {kind: "symbol", path: "loomwright/scripts/test-send-telemetry-core.sh", name: "no_qa_schema_scored"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/propose-from-verify.sh", name: "verdict.json"}
lanes:
  - "loomwright/scripts/notify-desktop.sh"
  - "loomwright/scripts/send-webhook.sh"
  - "loomwright/scripts/send-telemetry-core.sh"
  - "loomwright/scripts/test-send-telemetry-core.sh"
  - "loomwright/scripts/test-telemetry.sh"
  - "loomwright/scripts/telemetry-fixtures/qa-failed.json"
  - "loomwright/scripts/telemetry-fixtures/golden/qa-failed__allow_with_repo.golden.txt"
  - "loomwright/scripts/telemetry-fixtures/golden/*"
  - "loomwright/scripts/emit-token-ledger.sh"
  - "loomwright/scripts/test-token-ledger.sh"
  - "loomwright/scripts/result_block_parser.py"
  - "loomwright/scripts/test-emit-block-parses.sh"
  - "loomwright/scripts/build-capabilities.sh"
  - "loomwright/capabilities.json"
  - "loomwright/scripts/write-agent-memory.sh"
  - "loomwright/scripts/test-insights.sh"
  - "loomwright/scripts/test-proc-registry.sh"
  - "loomwright/scripts/test-automate-helpers.d/07-rules-gate.sh"
  - "loomwright/scripts/test-committed-twin-scrub.sh"
  - "loomwright/scripts/test-not-verified-transport-seam.sh"
  - "loomwright/skills/self-heal-advisory/completion-tail.md"
  - "loomwright/docs/TELEMETRY.md"
  - "loomwright/skills/telemetry/SKILL.md"
external_requires: []

# Subtask 3 — docs / agent-help sweep, live --expect 12 pin, changelog fragment (BLOCKED by #2: the live arm is green only once every row is cleared)
provides:
  - {kind: "symbol", path: "loomwright/scripts/test-check-qa-removal-manifest.sh", name: "live-expect-12"}
  - {kind: "file", path: "changelog.d/qa-split-12-re-point-qa-couplings.md"}
requires:
  - {from: "2", kind: "symbol", path: "loomwright/scripts/test-send-telemetry-core.sh", name: "no_qa_schema_scored"}
lanes:
  - "AGENT_GUIDELINES.md"
  - "README.md"
  - ".claude-plugin/README.md"
  - "loomwright/commands/agent-help.md"
  - "loomwright/docs/command-parts/agent-help/*.md"
  - "loomwright/docs/ARCHITECTURE.md"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/docs/CAPABILITIES_CONTRACT.md"
  - "loomwright/docs/FAILURE_ESCALATION.md"
  - "loomwright/docs/result-schemas/*.md"
  - "loomwright/docs/result-schemas/automate-run/crash-safety.md"
  - "loomwright/skills/ci-cd/SKILL.md"
  - "loomwright/skills/memory-tool/SKILL.md"
  - "loomwright/skills/unit-testing/SKILL.md"
  - "loomwright/skills/workflow-management/SKILL.md"
  - "loomwright/scripts/test-check-qa-removal-manifest.sh"
  - "loomwright/docs/qa-removal-manifest.md"
  - "changelog.d/qa-split-12-re-point-qa-couplings.md"
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
| Subtask 1 | Subtask 2 | `loomwright/capabilities.json` (regenerated by both) | YES |
| Subtask 1 | Subtask 3 | `loomwright/docs/result-schemas/supervisor-result.md` (in #1's lanes and covered by #3's `result-schemas/*.md` glob) | legal: ordered by 1→2→3, never concurrent; #3 has no row to change there |
| Subtask 2 | Subtask 3 | none | NO (ordered: #3's live gate needs #2's rows cleared) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after #1)
- **Batch 3:** Subtask 3 (after #2)
- **Recommended workers:** 1
- **Estimated batches:** 3

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` |
| 2 | `skills/unit-testing/SKILL.md` |
| 3 | `skills/quality-checklist/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): 48 modify + 1 create + 2 delete exceeds one worker's context | MEDIUM | Split `context-bound` into 3 serial subtasks, each closing its own checker rows; run `check-qa-removal-manifest.sh --expect 12` after each |
| Feasibility (Phase 2.5): the plan needs files outside the requirement's `## Touches` (the manifest's doc and test rows) | MEDIUM | AC1 cannot pass without them; asked once at Phase 6 (`LP-SCOPE`) |
| Prior churn (postmortem ledger): `ARCHITECTURE_CONTRACTS.md`, `.claude-plugin/README.md`, `README.md`, `agent-help.md`, `AGENT_GUIDELINES.md`. Recurring classes: drain_churn, convention_mismatch, self_heal_churn; self_heal_miss seen | HIGH | Doc edits are deletions or minimal rewording with no new counts or versions (house rule on count claims). Run `check-doc-currency.sh`, `check-token-budget.sh` and `check-prompt-history-refs.sh` locally via `ci-local.sh --affected` before push |
| `propose-from-verify.sh` moves from `exit 0 ALWAYS` to exit 2 on unusable input, which reverses its documented fail-safe | MEDIUM | Owner AC4. No hook or script calls it (only `commands/propose.md`). Rewrite the header and the command text in the same change. It stays a propose-only producer that never queues |
| `verdict.json` changes shape in a later Selvedge release | MEDIUM | `SUPPORTED_SCHEMA_VERSION=1`: any other `schema_version` is refused with `unknown_schema_version`, pinned by a test; only documented fields are read |
| Deleting the `qa-failed` telemetry fixture shifts `test-telemetry.sh`'s fixture matrix and goldens | LOW | Remove the matrix rows with the fixture. Regenerate goldens with `WRITE_GOLDENS=1` only if a remaining one changes (project memory) |
| Re-point edits break a keep row (`qa-executor:` kind kept until item 09) | MEDIUM | `--expect 12` checks keep rows too, so run it after every subtask; edit around the kind text |
| A row is a fixed-string grep per file, so a new file that names an old QA string is not caught | LOW | Honest limit of the manifest gate (its header says so); the new live arm covers every re-pointed file |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 3
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-19-qa-split-12-re-point-qa-couplings.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-11-19T20:10:28Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/954
- **Branch:** feature/qa-split-12-re-point-qa-couplings
- **Files changed:** 55
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** armed
- **Summary:** qa-split 12 — classify-risk trusts root selvedge.json (not .agent/verify.json); /propose --from-verify reads a Selvedge verdict.json (v1, FAIL-only, idempotent, exit 2 on unusable input, no selvedge/ import); QA names dropped from every name map, QA telemetry rubric/fixture/golden deleted; docs/agent-help/README sweep; test-check-qa-removal-manifest.sh live-expect-12 arm; release 18.1.0. check-qa-removal-manifest --expect 12: 0 MISMATCH. Phase 4.5: 3 rounds, 3 findings fixed (same-second idempotence pin, QA_RESULT split → manifest row corrected to keep/11b1, untested not-in-steps[] branch), 3 dismissed (pre_existing raw RUN_ID heading injection, LOW clock-shim TZ, nit interp:-none).

## Not verified
- **/propose --from-verify slash command** — no live Claude session run; the script it calls was run directly (subtask 1)
- **a verdict.json written by a real Selvedge run** — fixtures built from selvedge/schemas/verdict.schema.json; no Selvedge run executed (subtask 1)
- **live telemetry GitHub issue posting (consent + gh)** — only --dry-run paths exercised (subtask 2)
- **/agent-help rendered output** — structural test only (test-command-parts.sh 36/36) (subtask 3)
- **GitHub CI ci on the PR** — affected-only local run (subtask 3)
