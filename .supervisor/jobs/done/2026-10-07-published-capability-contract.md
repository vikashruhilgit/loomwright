# Supervisor Job: Publish a generated, versioned capability contract (loomwright/capabilities.json)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes-v2/s3-k
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (requirement `## Touches` omits `loomwright/docs/vendor-coupling-manifest.json`, which this change very likely needs — see Risk Assessment)
- **Source requirement:** .supervisor/requirements/host-contract/01-published-capability-contract.md
- **Base commit:** f4b0732b8f3e6a7b64fc960073e8ab680d5af9f0

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2-safe + jq generator, the repo's standard shape for `loomwright/scripts/*.sh`; Python allowed if JSON assembly is cleaner (repo already ships `.py` validators) |
| 2 | Dependency Availability | GO | Inputs all exist: `loomwright/.claude-plugin/plugin.json`, `loomwright/agents/*.md`, `loomwright/commands/*.md`, `loomwright/skills/*/SKILL.md`, `loomwright/hooks/hooks.json`, `loomwright/docs/RESULT_SCHEMAS.md` (now an index over `loomwright/docs/result-schemas/*.md`, after pa/11 merged in `88c3c02`) |
| 3 | Architecture Fit | GO | Additive outward contract; distinct from the inbound `loomwright/docs/CAPABILITY_BASELINE.json` |
| 4 | Scope vs Supervisor Capability | GO | ~10 files (5 modify, 5 create), single coherent change — one subtask (no Decomposition Threshold reason fires) |
| 5 | Hard Blockers | CAUTION | Several fail-CLOSED CI ratchets react to new files: vendor-coupling (new literal `.claude/`, `CLAUDE_PLUGIN_ROOT`, `SubagentStop` tokens), egress-hermetic tests, locale-prefix, citation-drift (ci.yml line shifts). Manageable, but must be run, not assumed. |

**Overall Verdict:** CAUTION

## Task
**Goal:** Ship `loomwright/capabilities.json` — generated from the plugin's own sources by a deterministic script, documented by a versioned schema + compatibility policy in `loomwright/docs/CAPABILITIES_CONTRACT.md`, and kept current by a CI/ci-local staleness gate — so a host can learn what the installed Loomwright offers without parsing internal files.

**Problem Statement:**
A host (generic consumer; Loomwright Studio is the first) needs a stable, versioned description of the installed plugin's agents (with the exact runtime `agent_type`), commands, skills, result schemas and hooks (including what each hook writes into the session's working directory), because Loomwright's internal layout and counts change between releases.
Currently the only sources are `plugin.json`, agent/command/skill frontmatter, `hooks.json` and the result-schema docs, whose shapes are Loomwright's to change. This forces hosts to scrape internals that break silently (e.g. the `validate-*-result.py` count moved from six to seven between September and 15.123.0).
Success looks like every release carrying a byte-reproducible `loomwright/capabilities.json` that CI refuses to let drift.

## Acceptance Criteria
- [ ] AC1 — Given the repo at HEAD, when `bash loomwright/scripts/build-capabilities.sh` runs, then it writes `loomwright/capabilities.json` that validates against the schema documented in `loomwright/docs/CAPABILITIES_CONTRACT.md` (fields: `contract_schema_version` int, `plugin_version` string == `plugin.json` `.version`, `agents[]`, `commands[]`, `skills[]`, `result_schemas[]`, `hooks[]`, `host_switch: null`).
- [ ] AC2 — Given an unchanged tree, when the generator runs twice, then both outputs are byte-identical (sorted keys and sorted lists, no timestamps, no absolute paths, no environment-dependent values).
- [ ] AC3 — Given a committed `loomwright/capabilities.json` that no longer matches the sources, when CI (a dedicated `.github/workflows/ci.yml` step) or `bash scripts/ci-local.sh` runs, then it fails with ONE line telling the developer to run `bash loomwright/scripts/build-capabilities.sh` and commit; `loomwright/scripts/test-build-capabilities.sh` proves it with a mutation control (delete an agent file in a fixture copy of the plugin tree ⇒ `--check` exits non-zero), and the mutant is gated as VALID (non-empty, differs from original) before the assertion is trusted.
- [ ] AC4 — Given each agent, when its entry is generated, then `runtime_agent_type` is `<plugin.json .name>:<frontmatter name>` (e.g. `loomwright:loomwright:worker`) — derived, not hard-coded per agent — and the contract doc cites the observed evidence `loomwright/scripts/fixtures/subagentstop-decision-shape-probe.json` (`agent_type_observed: "loomwright:loomwright:worker"`); `tools[]` is the frontmatter `tools` list minus `disallowedTools`; `model` is the frontmatter `model` value verbatim (e.g. `inherit`, `haiku`); `result_block` is the PRIMARY result block the agent emits or `null`, plus an additive `result_blocks[]` listing every block it emits — both derived by the documented rule in Implementation Notes (not a hand-typed per-agent table).
- [ ] AC5 — Given each `hooks.json` leaf (one `hooks[]` entry per leaf — count must equal the leaf count in `hooks.json`), when generated, then it carries `event`, `matcher` (string or null), `script` (the plugin script it invokes, or null for prompt/inline-shell leaves), `blocking` (true only for a `type: command` leaf whose command does NOT carry `|| true` — today the two `guard-test-integrity.sh` leaves), and `writes[]` filled from a per-script audit recorded IN the generator with an evidence comment per entry; a script with no audit entry emits `writes: ["unknown"]` (never a silent `[]`), and the doc says so. At minimum `set-otel-resource-attrs.sh`, `emit-lifecycle.sh`, `emit-token-ledger.sh` and `stamp-requirement-status.sh` have non-empty, audited `writes[]`.
- [ ] AC6 — Given the new doc, when read, then `loomwright/docs/CAPABILITIES_CONTRACT.md` documents the schema, the compatibility policy (adding fields/entries is non-breaking; removing/renaming/changing meaning bumps `contract_schema_version`; hosts ignore unknown fields), and that `docs/CAPABILITY_BASELINE.json` is a different, INBOUND file; and `loomwright/docs/ARCHITECTURE_CONTRACTS.md` carries a pointer to it.
- [ ] AC7 — Given the PR, when diffed, then no existing behaviour changes, a `changelog.d/host-contract-01-published-capability-contract.md` fragment is added, and NO version file (`plugin.json`, `marketplace.json`, `CHANGELOG.md`) is edited (wave lane — the wave branch carries the one bump, decision P7).
- [ ] AC8 — Given the change, when `bash scripts/ci-local.sh` runs (after `git add` of the new files), then it is green — including the vendor-coupling, egress-hermetic, locale-prefix, citation-drift, doc-currency and ci-local self-test gates.
- [ ] AC9 — Given the plugin tree, when `loomwright/scripts/test-build-capabilities.sh` runs, then it asserts each of `agents[]`, `commands[]`, `skills[]` and `hooks[]` has exactly ONE entry per source (`loomwright/agents/*.md`, `loomwright/commands/*.md`, `loomwright/skills/*/SKILL.md`, `hooks.json` leaves) with no duplicate names — the expected counts derived from the source dirs at test time, never hard-coded.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - enforcement: advisory
  - category: process
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - enforcement: advisory
  - category: process

(Applied here: `capabilities.json` IS a second static copy, justified because hosts genuinely need one; the staleness gate is the required sync check. `CAPABILITIES_CONTRACT.md` must NOT restate any count — point at the generated file / `hooks.json` instead.)

## Implementation Notes (from Phase 3 analysis — for the worker)
- **Inputs and derivation rules.**
  - `plugin_version` ⇐ `loomwright/.claude-plugin/plugin.json` `.version`; plugin name ⇐ `.name`.
  - `agents[]` ⇐ the leading YAML frontmatter of each `loomwright/agents/*.md` (`name`, `model`, `tools`, `disallowedTools`). Frontmatter is the block between line-1 `---` and the next `---`. `runtime_agent_type` = `<plugin name>:<frontmatter name>` (frontmatter names already carry `loomwright:`, so the result is the doubled prefix the runtime reports).
  - `result_block` / `result_blocks[]`: `result_blocks[]` (additive) = every `<NAME>_RESULT` block the agent prompt instructs it to EMIT (an emission template line such as `QA_RESULT:` / `## QA_RESULT`, not a prose mention), sorted; `result_block` = the PRIMARY one — the only one when there is one; when there are several, the one the agent's `SubagentStop` validator gives precedence to (documented per case from the validator's own rule, e.g. `qa-executor` emits `VERIFY_RESULT` in `--verify` mode and `QA_RESULT` otherwise, and `RESULT_SCHEMAS.md` says `QA_RESULT` wins whenever present ⇒ `result_block: QA_RESULT`, `result_blocks: [QA_RESULT, VERIFY_RESULT]`); none ⇒ `null` / `[]`. If several blocks exist and no documented precedence decides, `result_block` is `null` (never a guess) — `result_blocks[]` still lists them. The contract doc explains how multi-mode agents are represented.
  - `commands[]` ⇐ `loomwright/commands/*.md` (`name` = file stem; `description` = frontmatter `description`, first line).
  - `skills[]` ⇐ `loomwright/skills/*/SKILL.md` (`name` from frontmatter `name`, else the dir name).
  - `result_schemas[]` ⇐ the `## …` headings of the `loomwright/docs/RESULT_SCHEMAS.md` index whose FIRST non-blank body line is `See [result-schemas/<x>.md](result-schemas/<x>.md).` (this excludes `## Cited sub-section anchors`, whose body is a prose table). Two headings pass that shape but are NOT schemas — `## Schema Versioning` (schema-versioning.md) and `## Validation Location` (validation-location.md) — and are removed by an explicit, documented exclusion list in the generator. The test asserts none of `Schema Versioning`, `Validation Location`, `Cited sub-section anchors` (nor their normalized forms) appear in `result_schemas[]`. **Name normalization (contract surface — a later rename is a breaking change):** strip backticks and any trailing parenthetical from the heading text, then take the leading identifier token (`EVAL_RESULT (System Twin eval harness)` ⇒ `EVAL_RESULT`; `` `session_end` JSONL hard-signal fields (System Twin) `` ⇒ `session_end`; `` `agent_lifecycle` JSONL event records … `` ⇒ `agent_lifecycle`); document the rule in the contract doc; the test pins `WORKER_RESULT` (2), `CODE_REVIEW_RESULT` (3), `REVIEW_HEAL_RESULT` (2), `LAUNCH_PAD_RESULT` (1) and one decorated heading's normalized name. **`schema_version` source:** the linked `result-schemas/<x>.md` file is AUTHORITATIVE (its current `schema_version:` value); the generator fails CLOSED (non-zero, naming the schema) when the index's opening paragraph names a different current version for the same schema. Schemas that deliberately carry none — e.g. PRODUCT_CONTEXT, VERIFY_ENV, CONTEXT_DIGEST — get `schema_version: null`, documented.
  - `hooks[]` ⇐ every leaf of `loomwright/hooks/hooks.json` (`.hooks.<Event>[].hooks[]`). `script`: the first `${CLAUDE_PLUGIN_ROOT}/scripts/<x>` referenced by the command (basename or `scripts/<x>` relative to the plugin root); when a leaf invokes several plugin scripts, ALSO emit an additive `scripts[]` (all, in order) and document it. A `type: prompt` leaf (TaskCompleted) gets `script: null`, `scripts: []`, `writes: []`. **Mixed leaves:** a command leaf can combine inline shell writes with plugin scripts (the `StopFailure` leaf appends to `.supervisor/logs/failures.log` inline AND then runs `emit-lifecycle.sh failed`) or run several scripts (the SubagentStop telemetry + token-ledger leaves, the supervisor-runner leaf that also runs `stamp-requirement-status.sh`, the SessionStart leaf running `session-resume.sh` + `stamp-requirement-status.sh`). For every leaf: `script` = the first plugin script referenced (null only when the leaf references none), `scripts[]` = every plugin script referenced, in order, and `writes[]` = the sorted, de-duplicated UNION of the leaf's inline-audited writes (parsed from the command text, e.g. a `>> <path>` / `mkdir -p <dir>` redirect) and each listed script's audited writes; if ANY part is unaudited, `writes` is exactly `["unknown"]` (unknown wins — never a partial list that looks complete). `/dev/null` and file-descriptor duplications (`2>&1`, `N>&M`) are NOT writes; the test pins the `StopFailure` leaf's `writes[]` exactly (`.supervisor/logs/failures.log` ∪ `emit-lifecycle.sh`'s audited writes) and asserts no `hooks[]` entry lists `/dev/null` or an `&N` target.
  - Hook leaf identity: entries are sorted deterministically (e.g. by event, matcher, then position) — document the sort key.
- **`writes[]` audit** lives in the generator (a keyed table: script basename → list of repo-relative paths / settings keys, each entry with a one-line evidence comment naming the line/construct in that script that writes it). Paths use placeholders, e.g. `.supervisor/logs/<session>.jsonl`, `.claude/settings.local.json#env.OTEL_RESOURCE_ATTRIBUTES`. Read each script; do not infer from its name. Unaudited ⇒ `["unknown"]`. Scope: writes into the session's working directory (the user project), not `~/` or `$TMPDIR` — document that scope.
- **Modes:** `build-capabilities.sh` (write), `--check` (regenerate to a temp file, diff against the committed file, exit 1 with one line: `capabilities.json is stale — run: bash loomwright/scripts/build-capabilities.sh and commit`), `--root <dir>` (plugin root to read — lets the test run against a fixture copy). Bash 3.2-safe, no GNU-only flags, `env LC_ALL=C sort` (never a temporary `LC_ALL=C sort` prefix — `check-locale-prefix.sh`), jq for JSON construction.
- **CI wiring:** add a dedicated `ci.yml` step running `bash loomwright/scripts/build-capabilities.sh --check`. `scripts/ci-local.sh` derives its gate list ONLY from `bash scripts/<x>.sh` lines in `ci.yml` (the `grep -oE 'bash scripts/…'` in its plan section), so a `bash loomwright/scripts/…` step is invisible to it — make ci-local run the check too (either extend its extraction or add an explicit entry), and keep `scripts/test-ci-local.sh` green (it pins how ci-local mirrors ci.yml). `loomwright/scripts/test-build-capabilities.sh` is auto-included by `loomwright/scripts/run-self-tests.sh` (glob `loomwright/scripts/test-*.sh`).
- **Test file must source `loomwright/scripts/hermetic-test-env.sh` as its first executable line** (`check-test-hermetic.sh` ratchet) and be static-only (no network, no gh).
- **Vendor-coupling ratchet:** `loomwright/` is a scan root; any new literal `CLAUDE_PLUGIN_ROOT`, `.claude/`, `SubagentStop`, `CLAUDE_CODE_` etc. in the generator, the generated JSON, or the doc counts against a zero default allowance for new files. Expected resolution: classify `loomwright/capabilities.json` as an `adapter` surface (it is the host-facing contract, like `hooks.json`) and give the generator/doc reasoned allowances — a reviewed edit to `loomwright/docs/vendor-coupling-manifest.json` with `allowance_reasons`. Measure with `git add` first (the gate scans `git ls-files`).
- **Citation drift:** inserting lines into `ci.yml` may shift pinned `ci.yml:N` citations elsewhere; `test-citation-drift.sh` (run by ci-local) will name any — re-derive pins, or write descriptive anchors.
- **Doc:** no literal counts in `CAPABILITIES_CONTRACT.md` (house rule above); say "see `capabilities.json`".

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Capability contract: generator, generated JSON, contract doc, staleness gate, tests | AC1–AC9 | 5 modify, 5 create | `skills/ci-cd/SKILL.md`, `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/build-capabilities.sh"}
  - {kind: "file", path: "loomwright/scripts/test-build-capabilities.sh"}
  - {kind: "file", path: "loomwright/capabilities.json"}
  - {kind: "symbol", path: "loomwright/capabilities.json", name: "contract_schema_version"}
  - {kind: "symbol", path: "loomwright/capabilities.json", name: "runtime_agent_type"}
  - {kind: "file", path: "loomwright/docs/CAPABILITIES_CONTRACT.md"}
  - {kind: "symbol", path: "loomwright/docs/CAPABILITIES_CONTRACT.md", name: "CAPABILITY_BASELINE.json"}
  - {kind: "symbol", path: "loomwright/docs/ARCHITECTURE_CONTRACTS.md", name: "CAPABILITIES_CONTRACT.md"}
  - {kind: "symbol", path: ".github/workflows/ci.yml", name: "build-capabilities.sh --check"}
  - {kind: "file", path: "changelog.d/host-contract-01-published-capability-contract.md"}
requires: []
lanes:
  - "loomwright/scripts/build-capabilities.sh"
  - "loomwright/scripts/test-build-capabilities.sh"
  - "loomwright/capabilities.json"
  - "loomwright/docs/CAPABILITIES_CONTRACT.md"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "scripts/ci-local.sh"
  - "scripts/test-ci-local.sh"
  - ".github/workflows/ci.yml"
  - "changelog.d/host-contract-01-published-capability-contract.md"
external_requires:
  - "jq (already a hard dependency of the repo's scripts and CI runner)"
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 (independent)
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | — | none | NO |

### Batch Plan
- **Batch 1:** Subtask 1
- **Recommended workers:** 1
- **Estimated batches:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/ci-cd/SKILL.md`, `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): new files trip fail-CLOSED ratchets — vendor-coupling (literal `.claude/`, `CLAUDE_PLUGIN_ROOT`, `SubagentStop` tokens in generator / JSON / doc), egress-hermetic, locale-prefix | HIGH | `git add` the new files, then run `bash scripts/ci-local.sh`; resolve vendor-coupling with a reasoned manifest edit (classify `capabilities.json` as adapter, reasoned allowances for the generator/doc) — never by obfuscating tokens |
| Requirement `## Touches` omits `loomwright/docs/vendor-coupling-manifest.json` (and possibly `scripts/test-ci-local.sh`); the plan-waves conflict set is therefore understated for this wave | MEDIUM | Both are in this brief's lanes; call the deviation out in the PR body so the wave operator can re-check overlap with other open items |
| `writes[]` is a hand audit embedded in the generator — it can drift from the scripts it describes (the staleness gate only re-runs the generator, it does not re-audit) | MEDIUM | Evidence comment per audit entry naming the writing construct; unaudited script ⇒ `["unknown"]`; test asserts every hook script has an audit entry and the four named scripts are non-empty; doc states this honest limit |
| `result_block` derivation rule misattributes an agent (several agents mention multiple result blocks in prose) | MEDIUM | Rule anchored on explicit emission templates + the SubagentStop validator's documented precedence; undecidable ⇒ `null` with `result_blocks[]` still listing them; test pins known pairs (qa-executor pinned as `result_block: QA_RESULT`, `result_blocks` containing `QA_RESULT` and `VERIFY_RESULT`) (worker→WORKER_RESULT, code-reviewer→CODE_REVIEW_RESULT, plan-reviewer→PLAN_REVIEW_RESULT, launch-pad-runner→LAUNCH_PAD_RESULT, supervisor-runner→SUPERVISOR_RESULT, execute-manager→EXECUTE_RESULT, qa-executor→QA_RESULT) |
| Non-determinism (locale sort order, jq key order, BSD vs GNU tools) makes CI and macOS disagree | MEDIUM | `env LC_ALL=C sort`, `jq -S`, no `stat`/`date`; determinism test runs the generator twice and `cmp`s |
| Prior churn (postmortem ledger): `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (37), `.github/workflows/ci.yml` (10), `scripts/ci-local.sh` (2) — recurring `drain_churn`, `convention_mismatch`, `self_heal_churn`; a `self_heal_miss` has occurred on these paths | HIGH | Keep the ARCHITECTURE_CONTRACTS edit to a short pointer; follow the existing ci.yml comment convention (why + "No `\|\| true`: fail-CLOSED") for the new step; re-run ci-local after every fix round |
| `claude-review` skips PRs that edit a workflow file (green, no comment) — this PR edits `ci.yml` | LOW | Review comes from Phase 4.5 + the drain's earned-fallback code-reviewer; assert on posted reviews, never on the check colour |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-07-published-capability-contract.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-10-07T08:47:52Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/412
- **Branch:** feature/host-contract-01-published-capability-contract
- **Files changed:** 13
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Generated, versioned loomwright/capabilities.json + build-capabilities.sh (write/--check/--root), CAPABILITIES_CONTRACT.md, ci.yml + ci-local staleness gate, bump-version.sh contract refresh; Phase 4.5 PASS on review 3 after 2 fix iterations (fail-closed hook-writes parser, release-path regeneration, explicit-emission result_blocks); 9 below-floor findings dismissed; ground_truth 2/2 pass; risk_classification high_risk true (advisory).

## Not verified
- **hooks[].writes audit** — hand audit from static reading of each hook script and its sub-scripts; no hook was executed to observe its actual file writes (subtask 1)
