# Supervisor Job: Declare host mode in the capability contract (`host_switch` + per-hook `host_mode`)

## Environment
- **Project:** lane clone `L2` of `ai-agent-manager` (`<primary>-lanes/automate-2026-10-11-082328/L2`)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main (lane clone; origin = vikashruhilgit/loomwright)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1
- **Source requirement:** .supervisor/requirements/host-contract/03-declare-host-mode-in-contract.md
- **Base commit:** da2fac5d4f54bea55fc91700ebe5729755f587ef

> **Warning (1):** this checkout is lane `L2` of the `--parallel 2` wave `automate-2026-10-11-082328`. A sibling lane runs at the same time in its own clone. Stay inside this item's `## Touches` list. This PR carries a `changelog.d/` fragment and NO version bump (lane PRs never bump; the bump is the wave branch's last commit).

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 + `jq` + markdown — the generator's existing surface. |
| 2 | Dependency Availability | GO | `jq`, `git` present; no new dependency. |
| 3 | Architecture Fit | GO | Fills the contract field item 01 reserved (`host_switch: null`) and adds one per-hook field, both generated from sources the plugin already ships (item 02's `docs/HOOKS.md` §"Host mode" classification table and `scripts/host-mode.sh`). |
| 4 | Scope vs Supervisor Capability | GO | One generator, its test, the regenerated JSON, one doc, one fragment — single subtask. |
| 5 | Hard Blockers | GO | Dependencies 01 (`## Status: done`, PR #412) and 02 (`## Status: done_with_escalation`, PR #450) are merged on `origin/main`. |

**Overall Verdict:** GO

## Task
**Goal:** Make `loomwright/capabilities.json` declare host mode, generated from the plugin's sources like every other field: a top-level `host_switch` object naming the switch and state-dir env vars, and a `host_mode` (`"redirects" | "skips" | "unaffected"`) on every `hooks[]` entry, derived from item 02's classification in `docs/HOOKS.md` — never hand-kept.

**Problem Statement:** After items 01 and 02, the contract still says `host_switch: null`, so a host (Loomwright Studio, decision D32) cannot learn from the contract that host mode exists, which env vars switch it, or what each hook does under it — it would have to parse `docs/HOOKS.md`, the internal-file parsing D32 rejects.

## Acceptance Criteria
- [ ] **AC1 (`host_switch`).** Given the generator runs, when `capabilities.json` is produced, then its top-level `host_switch` is an object `{env, state_dir_env, effect}` with `env == "LOOMWRIGHT_HOST_MODE"` and `state_dir_env == "LOOMWRIGHT_HOST_STATE_DIR"` and `effect` a non-empty one-sentence string (switch on only when the value is exactly `1`; under it no hook writes the session's working tree; state goes to `state_dir_env` when valid, else gate state to a per-user temp root and other writes skip). The two env names live in the generator as named constants beside the existing `HOST_VAR` (the generator already names `LOOMWRIGHT_HOST_MODE` once there — reuse it, add `HOST_STATE_VAR` beside it). A test **greps** `loomwright/scripts/host-mode.sh` and asserts that both names published in `host_switch` are actually read there (`${NAME:-` / `"$NAME"` reads), so a rename in `host-mode.sh` fails the test — never an assumed string.
- [ ] **AC2 (`hooks[].host_mode` derived from a source).** Given the `docs/HOOKS.md` §"Host mode" classification table (the `| Script / leaf | Class | Under host mode |` table item 02 shipped — read-only for this item), when the generator builds `hooks[]`, then every entry carries `host_mode`, computed by parsing that table:
  - **Row keys:** the row whose first cell starts with `StopFailure inline leaf` is the inline-leaf row; the row whose first cell is `` `TaskCompleted` `` is the prompt row; every other row is keyed by the FIRST backticked token of its first cell — a script file name (`` `emit-lifecycle.sh` ``) or a glob pattern (`` `validate-*-result.py` ``, matched as a shell glob against a script's basename). The Class cell's first word is the class (`redirects (gate)` ⇒ `redirects`).
  - **Leaf value:** a `type: prompt` leaf ⇒ the prompt row's class. A `type: command` leaf ⇒ the classes of every script in its `scripts[]` (basename looked up in the rows), plus the inline-leaf row's class when the leaf is a `StopFailure` leaf whose command carries an inline redirect (the `failures.log` append), combined by precedence **`redirects` > `skips` > `unaffected`**.
  - **Unknown wins, like `writes[]`:** when any part of a leaf cannot be classified — an invoked script with no matching row, a command leaf with no scripts and no inline-leaf match — the leaf's `host_mode` is `"unknown"` (never a guessed or default value; never a partial answer). This keeps every existing test fixture (the (U) `never-audited.sh` leaf, the scriptless (P) parser leaves) generating, with assertions unchanged. A test asserts the REAL contract has **no** `unknown` `host_mode`, so a new hook script added without a `HOOKS.md` row fails CI (that test is the fail-closed gate for the real tree).
  - **Fail closed on a malformed source:** when `hooks.json` has ≥1 leaf and the table cannot be found, or a row's class word is not one of the three, the generator exits 1 with ONE `build-capabilities: …` line naming the problem. A `hooks.json` with zero leaves reads no table at all (so `scripts/test-bump-version.sh`'s `make_caps_fixture` — `{"hooks": {}}`, no `docs/HOOKS.md` — keeps generating unchanged).
  - The value is never written by hand in the JSON: the only way to change it is to edit the `HOOKS.md` row and regenerate.
- [ ] **AC3 (regenerated, current, deterministic).** `bash loomwright/scripts/build-capabilities.sh` is run and the result committed; `bash loomwright/scripts/build-capabilities.sh --check` exits 0; two runs are byte-identical; a fixture copy at another `--root` yields the same bytes (extend `fixture_copy` in the test to copy `docs/HOOKS.md`, which the generator now reads). Every pre-existing field of every `hooks[]` entry (`event`, `matcher`, `type`, `source`, `script`, `scripts`, `blocking`, `writes`) is byte-unchanged: `jq 'del(.host_switch) | .hooks |= map(del(.host_mode))'` of the new file equals the same projection of the base file (`git show da2fac5:loomwright/capabilities.json`).
- [ ] **AC4 (tests in `test-build-capabilities.sh`).** New/updated cases:
  - (S) `host_switch` is an object with the three keys (replacing the `host_switch == null` pin), env names exact.
  - every `hooks[]` entry of the REAL contract has a `host_mode` in {`redirects`,`skips`,`unaffected`} (no `unknown`); the (U) never-audited leaf reads `unknown`; spot pins: the `set-otel-resource-attrs.sh` leaf ⇒ `skips`; an `emit-lifecycle.sh`-only leaf ⇒ `redirects`; the `TaskCompleted` prompt leaf ⇒ `unaffected`; the StopFailure inline leaf ⇒ `redirects`.
  - the grep check of AC1 against `scripts/host-mode.sh`.
  - **mutation control:** in a fixture copy, change ONE hook's class in `docs/HOOKS.md` (e.g. `set-otel-resource-attrs.sh` `skips` ⇒ `unaffected`); the mutant output is VALID (non-empty, differs from the real one) and `--check` against the committed contract exits 1 with the one staleness line.
  - fail-closed controls in a fixture copy: delete a script's row ⇒ that leaf reads `unknown` (and the real-tree no-`unknown` assertion logic would fail on it); an unknown class word ⇒ exit 1 with one line; no `docs/HOOKS.md` with ≥1 leaf ⇒ exit 1; no `docs/HOOKS.md` with zero leaves ⇒ exit 0.
  - `bash scripts/test-bump-version.sh` passes unchanged (its caps cases build a zero-leaf tree).
- [ ] **AC5 (doc).** `loomwright/docs/CAPABILITIES_CONTRACT.md`: the `host_switch` schema row becomes `object` with its three fields documented (a `### host_switch` subsection); the `hooks[]` table gains a `host_mode` row (values incl. `unknown`, the derivation from `docs/HOOKS.md` §"Host mode" — that table is the source, so editing a row there requires a regeneration — the row-key rule, the precedence rule, and the malformed-source fail-closed exits); the compatibility section states both are **additive** (filling a field reserved as `null`, adding a field), so `contract_schema_version` stays `1`. The generator's own comment block that calls `host_switch` "reserved" is updated. `docs/HOOKS.md` is NOT edited (outside this item's `## Touches`; a sibling lane runs concurrently).
- [ ] **AC6 (fragment, no bump).** `changelog.d/host-contract-03-declare-host-mode-in-contract.md` exists (format per `changelog.d/README.md`); no version file (`plugin.json`, `marketplace.json`, `CHANGELOG.md`) is touched.
- [ ] **AC7 (CI green).** `bash scripts/ci-local.sh` passes on the branch (incl. doc-currency, citation drift, the capabilities staleness step). The PR body pastes base and branch pass/total counts.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Configuration
- **Mode:** single-agent
- **Base Branch:** main
- **Workers:** 1

## Touched-file invariants

> Grounded at base `da2fac5d4f54bea55fc91700ebe5729755f587ef`.

- **`loomwright/scripts/build-capabilities.sh`**
  - keep: determinism and no absolute paths (header: `sorted (jq -S), there are no timestamps, and no path in the output is absolute or depends on --root`); every fail-closed exit prints ONE `build-capabilities: …` line to stderr and exits 1; the `--check` staleness line text (`capabilities.json is stale — run: bash loomwright/scripts/build-capabilities.sh and commit`) byte-unchanged; the HOST-MODE SPLIT parse of the StopFailure leaf (`sub($host_split_re; "\(.off)")`) — `writes[]` still publishes the OFF-mode writes; the one-place constants `ROOT_VAR='CLAUDE_PLUGIN_ROOT'` / `HOST_VAR='LOOMWRIGHT_HOST_MODE'`.
  - reuse: `HOST_VAR` for `host_switch.env`; the hooks jq pipeline (`$s` = the leaf's scripts) to attach `host_mode`; the final `jq -n -S` assembly (replace `host_switch: null`).
  - pinned by: `test-build-capabilities.sh` groups (D) (C) (S) (H) (U) (P) (M) (O); the staleness step in `.github/workflows/ci.yml` (`build-capabilities.sh --check` — `scripts/ci-local.sh` mirrors ci.yml's steps); `scripts/bump-version.sh` `render_capabilities` (runs the generator against a shadow root that symlinks `docs`); `scripts/test-bump-version.sh` `make_caps_fixture` (a zero-leaf `{"hooks": {}}` tree with no `docs/HOOKS.md` — must keep generating).
- **`loomwright/scripts/test-build-capabilities.sh`**
  - keep: the first executable line `. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"`, then `set -uo pipefail`; the `ok`/`no` counters and exit shape; every existing assertion unchanged except the (S) `and .host_switch == null` pin, which this item intentionally replaces. Fixture SETUP may change (`fixture_copy` gains `docs/HOOKS.md`).
- **`loomwright/docs/HOOKS.md`** — READ ONLY (source of `host_mode`): anchors `## Host mode` and `| Script / leaf | Class | Under host mode |`. Not edited.

## Subtask Structure

| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | Generate `host_switch` + per-hook `host_mode` from sources; tests; doc; fragment | 4 modify, 1 create, 1 regenerate | LAUNCHABLE |

### Subtask 1 — Declare host mode in the contract (LAUNCHABLE)
- **Criteria:** AC1–AC7
- **Files (modify):** `loomwright/scripts/build-capabilities.sh` (HIGH), `loomwright/scripts/test-build-capabilities.sh` (HIGH), `loomwright/docs/CAPABILITIES_CONTRACT.md` (HIGH)
- **Files (regenerate):** `loomwright/capabilities.json` (HIGH — generated, never hand-edited)
- **Files (create):** `changelog.d/host-contract-03-declare-host-mode-in-contract.md` (HIGH)
- **Skills:** `unit-testing` (bash self-test conventions), `quality-checklist`

```yaml
# Subtask 1 — Declare host mode in the contract (LAUNCHABLE)
provides:
  - {kind: "file", path: "loomwright/capabilities.json"}
  - {kind: "symbol", path: "loomwright/capabilities.json", name: "host_switch"}
  - {kind: "symbol", path: "loomwright/capabilities.json", name: "host_mode"}
  - {kind: "symbol", path: "loomwright/scripts/build-capabilities.sh", name: "HOST_STATE_VAR"}
  - {kind: "symbol", path: "loomwright/docs/CAPABILITIES_CONTRACT.md", name: "host_switch"}
  - {kind: "file", path: "changelog.d/host-contract-03-declare-host-mode-in-contract.md"}
requires: []
lanes:
  - "loomwright/scripts/build-capabilities.sh"
  - "loomwright/scripts/test-build-capabilities.sh"
  - "loomwright/capabilities.json"
  - "loomwright/docs/CAPABILITIES_CONTRACT.md"
  - "changelog.d/host-contract-03-declare-host-mode-in-contract.md"
external_requires: []
```

## Parallelism Analysis
single-agent (no fan-out)

- Recommended workers: 1

## Skill References
- `loomwright/skills/unit-testing/SKILL.md`
- `loomwright/skills/quality-checklist/SKILL.md`

## Risk Assessment

| Risk | Level | Source | Mitigation |
|------|-------|--------|------------|
| Parsing a markdown table is brittle — a reworded row silently changes a class | MEDIUM | Analysis | Fail closed on every unmatched script / unknown class word; mutation control proves a class edit reaches the output; the HOOKS.md sentence tells editors a regeneration follows. |
| A leaf mixes `redirects` and `skips` scripts; one enum value loses detail | LOW | Analysis | Documented precedence `redirects > skips > unaffected`; per-script detail stays in `HOOKS.md`. |
| `host_switch` changing from `null` to an object could be read as a meaning change | LOW | Compatibility policy | Item 01's doc reserved it "filled by a later item"; the doc states the fill is additive and hosts must ignore unknown fields — `contract_schema_version` stays 1 (requirement Scope bullet 3). |
| `validate-*-result.py` row is a pattern, not one script | LOW | Analysis | Generator matches it as a glob against `scripts[]` basenames; test pins one validator leaf ⇒ `unaffected`. |
| A stricter generator breaks existing fixtures ((U)/(P) leaves with no row; `test-bump-version.sh` zero-leaf tree with no HOOKS.md) | HIGH | Plan Review attempt 1 | `unknown` for unclassifiable leaves (not an exit), the table read only when ≥1 leaf exists; both suites run in ci-local; the real tree is held to no-`unknown` by a test. |
| Concurrent sibling lane (parallel-automate/22) | LOW | Wave | Its Touches (automate-loop skill, automate-helpers*, result schemas, ARCHITECTURE_CONTRACTS) do not intersect this lane; `docs/HOOKS.md` is deliberately not edited. |

## Handoff
/supervisor job: .supervisor/jobs/pending/auto-2026-10-11-032135-declare-host-mode-in-contract.md

## Outcome
- **Status:** completed
- **Completed:** 2026-10-11T05:05:05Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/468
- **Branch:** feature/host-contract-03-declare-host-mode-in-contract
- **Files changed:** 5
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** capabilities.json now publishes host_switch {env, state_dir_env, effect} and a host_mode on every hooks[] entry, generated from the docs/HOOKS.md "Host mode" table (unknown wins; zero unknown in the real contract). Phase 4.5 consistency_audit PASS first pass (3 LOW dismissed); ground truth 2/2; ci-local PASS on 9704818.

## Not verified
- **Base ci-local pass/total for the PR body** — not obtained; base targeted counts are test-build-capabilities 90/90 and test-bump-version 72/72 (subtask 1)
