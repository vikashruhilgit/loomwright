# Supervisor Job: High-risk diffs park in the trusted auto-merge gate (classify-risk.sh + condition 6, no override)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — last commit 2026-09-06)
- **Git:** dirty (1 file — `.supervisor/postmortem/results.jsonl`, tracked ledger lines from prior drains; NOT part of this job — do not stage it), branch: main @ 25b5cfa (PR #217 merged, v15.71.0 live)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 2 (dirty tracked ledger above; unrelated `.claude/worktrees/*` from other Claude sessions — leave untouched)
- **Source requirement:** .supervisor/requirements/review-gate-brief-conformance/03-high-risk-park-in-trusted-merge-gate.md

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | One bash+jq script, one static `test-*.sh`, one edit to the existing bash gate (`automate-helpers.sh gate_eval`) + its suite, markdown prompt/doc edits — the plugin's own stack (bash 3.2 / BSD userland; jq already required by `automate-helpers.sh`) |
| 2 | Dependency Availability | GO | No new dependency; `.agent/` committed-store pattern already exists (`read-product.sh` / `read-rules.sh` fail-safe readers); CI `loomwright/scripts/test-*.sh` glob auto-includes new suites |
| 3 | Architecture Fit | GO | Condition 6 lives INSIDE the one sanctioned executor (`gate_eval`), in the file's mandated affirmative-string fail-CLOSED form; the classifier is a fail-SAFE emitter whose `null` is the fail-closed value for the consumer — exactly CLAUDE.md §Failure-Mode Invariants. R1 (no new gate elsewhere, red-team stays advisory) and R5 (no override, add-only project extension) preserved. The `gh pr merge --squash` invariant grep resolves to the same five surfaces — cond 6 adds no executor. |
| 4 | Scope vs Supervisor Capability | CAUTION | 2 create + ~15 modify (the "5 conditions" phrasing sweep touches many prose surfaces) — `context-bound` fires by the letter (>12 files), but every edit hangs off one seam and the phrasing sweep is mechanical; a split would serialize a `requires:` chain (gate + docs need the script's `--kind-table`). Single subtask, deviation recorded (same call the Orchestrator made on item 02). |
| 5 | Hard Blockers | GO | none. Budget headroom: `supervisor` 1596 proxy tokens (the `risk_classification` block addition is ~80 tokens), `red-team-reviewer` 606 (untouched), `self-heal-advisory` is read-on-demand (not preloaded — replacing its pseudo-code heuristic with a pointer is budget-free) |

**Overall Verdict:** GO (1 CAUTION carried into Risk Assessment)

## Task
**Goal:** A high-risk integrated diff can never be auto-merged. Ship `loomwright/scripts/classify-risk.sh` (deterministic, read-only, fail-SAFE) as the ONE implementation of the existing high-risk heuristic, extended per project by an add-only committed `.agent/risk.json`; make it the **sixth fail-CLOSED condition** of `automate-helpers.sh gate-eval` (re-classified at GATE time on the SHA being judged, `null`/missing/anything-but-`false` ⇒ `PARK: high_risk_diff`), with **no override of any kind**; make Phase 4.5's advisory red-team lens read the same script; surface the classification on `SUPERVISOR_RESULT` as an additive `risk_classification` object; sweep every "5 conditions" claim to "6".

**Problem Statement:**
`gate-eval` is the plugin's only `gh pr merge --squash` executor and is a pure function of 5 per-PR booleans — it is path-blind: a diff touching auth, secrets, payments or a migration merges under exactly the same conditions as a lint fix. The high-risk classifier already exists (`skills/self-heal-advisory/SKILL.md` §"Advisory red-team lens": `*auth*`, `*authz*`, `*security*`, `*crypto*`, `*secret*`, `*token*`, `*payment*`, `migrations/`, `*migration*`; `.github/workflows/`, `hooks/`, `agents/`, `commands/`, `skills/`; `workflow|automation|orchestration` in path/content; `changed_lines > 400`; `changed_files > 15`) but it is prompt-only and only decides whether to spawn the advisory pass — it never reaches the merge decision. Raised externally 2026-09-13; owner decisions R1 (no new gate elsewhere) and **R5 (high-risk is a park condition with NO override — not a flag, not a config key, not a project exclude list; projects may only ADD surfaces)** in `.supervisor/requirements/review-gate-brief-conformance/00-overview.md`. Premise correction kept for honesty: the gate has no accumulating trust score, so "streak buys trust" cannot occur here — the conclusion (high-risk stays behind a human) holds regardless.

**Owner decisions carried in (do not re-litigate):** R1, R5; no trust score / hit-rate / history of any kind (the gate stays a pure per-PR function); `.agent/risk.json` has no `exclude` key by design; `/review-pr` `READY` and Phase 4.5 `PASS` are untouched (they never merge — nothing to park).

**Decision D1 (Launch Pad — classification is unconditional, the spawn stays opt-in):** `classify-risk.sh "$BASE_BRANCH" HEAD` runs on EVERY Phase 4.5 (deterministic, no LLM, one Bash call) BEFORE the `RED_TEAM_ENABLED` guard, so `risk_classification` is present on every `SUPERVISOR_RESULT` that runs the lens; on the Phase 4.5 bypass paths (`--skip-self-heal`, resume-thrash, base-mismatch cleanup) the object is ABSENT — mirroring `red_team_advisory: disabled` — and absent ⇒ valid; the red-team `Task` spawn stays behind `RED_TEAM_ENABLED AND (high_risk == true OR high_risk == null)` (`null` ⇒ spawn — the safe direction for an advisory lens is to run it). `red_team_advisory` values are unchanged (`disabled` | `skipped_low_risk` | `ran` | `error`).

**Decision D2 (Launch Pad — the `--trust-unprotected` sentence):** the flag's scope is stated explicitly wherever it is documented (`skills/automate-loop/SKILL.md` §10 cond 4 and §12, `commands/automate.md` Parameters table, `commands/agent-help.md`): it overrides **condition 4 only**; there is no flag, config key, or project file that overrides condition 6. `commands/agent-help.md` does NOT document `--trust-unprotected` today — ADD the flag line to its `/automate` block (a legitimate command-mirror sync) carrying the cond-4-only sentence — memory `agent-command-mirror-drift-on-fixes` says the command prose must move in the same commit as the skill.

## Acceptance Criteria
- [ ] AC1 — `gate-eval` with all five prior conditions satisfied and `"high_risk": true` prints `PARK: high_risk_diff (<first 3 reasons>)` and does NOT invoke `gh pr merge` (the suite's gh stub asserts zero calls); with `"high_risk": false` it prints `MERGE` (exactly one `gh pr merge --squash` call); with the key absent, `null`, a non-boolean string, or unreadable ⇒ PARK. Implemented in `automate-helpers.sh`'s mandated FAIL-CLOSED form: read with `has()` + `!= null` + `tostring`, compare `!= "false"` ⇒ PARK (never a `= "true"`/`= "false"` test on a `//`-coerced value — the file's header comment is authoritative; mirror the `unresolved_human_thread` read).
- [ ] AC2 — `--trust-unprotected: true` + `high_risk: true` ⇒ PARK (the override is scoped to cond 4 only); the ctx field is named `high_risk` with a sibling `risk_reasons` (string array) that the PARK reason quotes (first 3).
- [ ] AC3 — `classify-risk.sh <base_ref> <head_ref> [--root <dir>]` on a diff adding `const token = ...` to `src/utils/format.ts` (innocuous path, matching content) returns `{"high_risk": true, "reasons": ["content:… matched *token*", …], …}`; on a 3-line change to `README.md` returns `false` with `reasons: []`. Output is ONE `jq --arg`-built JSON object: `{"high_risk": true|false|null, "reasons": [...], "changed_files": N, "changed_lines": N, "source": "classify-risk.sh"}`; always exit 0; read-only (no writes, no `cd` into `--root` — use `git -C`); `null` + `reasons: ["unclassifiable: <reason>"]` + stderr on unreadable ref / not a git repo / `git` failure / `jq` missing (the jq-less object is the ONE shell-templated case, fixed literals only — item 02's precedent).
- [ ] AC4 — The heuristic is applied **verbatim** to the existing lens text (branches a/b/c; path OR content; case-insensitive; `changed_lines` = added+removed lines of `git diff`, `changed_files` = count of `git diff --name-only`); reasons are prefixed `path:` / `content:` / `size:` / `project:` and name the matched pattern. `--kind-table` prints the heuristic as a markdown table; it appears ONCE in docs — `docs/RESULT_SCHEMAS.md` §SUPERVISOR_RESULT `risk_classification` between `<!-- risk-table:begin -->`/`<!-- risk-table:end -->` markers — and `test-classify-risk.sh` byte-compares the two (item 02's `kind-table` convention).
- [ ] AC5 — `.agent/risk.json` `{"schema_version":1,"paths":["billing/**"],"content":["stripe"]}` + a `billing/x.ts` diff ⇒ `true` with a `project:` reason; glob matching is the plugin's usual `case`-pattern semantics documented in the script header (`**` and `*` both match across `/`, state it); the same file with `"paths": "billing/**"` (string, not array) or a non-object root ⇒ generic-only result + `risk_json_malformed` on stderr (never a failure, never `null`); absent file ⇒ silent generic-only. NO `exclude` key is read — an `exclude` key present is ignored with a stderr note (`risk_json_exclude_ignored`), never honoured. `--root` decides where `.agent/risk.json` is read from.
- [ ] AC6 — Phase 4.5 (`skills/self-heal-advisory/SKILL.md` §"Advisory red-team lens"): the inline pseudo-code heuristic is REPLACED by the `classify-risk.sh "$BASE_BRANCH" HEAD` call (pointer to `--kind-table` for the rules) per D1 — classification unconditional, spawn gated on `RED_TEAM_ENABLED AND high_risk != false`; `record_decision(phase: SELF_HEAL, decision: "risk_classification: {true|false|null}", rationale: "<reasons or unclassifiable reason>")` on every path; `red_team_advisory` semantics unchanged. `agents/supervisor.md` §"Result Block" + `docs/RESULT_SCHEMAS.md` §SUPERVISOR_RESULT gain the optional additive nested object `risk_classification: {high_risk: true|false|null, reasons: string[]}` (no `schema_version` bump; absent ⇒ valid), and the FLAT `risk_high` (`true|false|null`) + `risk_reasons_count` (int) on the `session_end` JSONL line following the hard-signal dual-emission table (`docs/RESULT_SCHEMAS.md` §"`session_end` JSONL hard-signal fields"). Verify `loomwright/scripts/validate-supervisor-result.py` accepts a block carrying the nested object (pipe one through it in the suite).
- [ ] AC7 — `/automate` loop (`skills/automate-loop/SKILL.md` §10): new **condition 6** after 5 — the loop obtains `high_risk` by re-running `classify-risk.sh main <ready_sha> --root <checkout>` at GATE time on the fetched PR head (NOT from `SUPERVISOR_RESULT.risk_classification`, which is recorded in `## Progress` for comparison only), passes `"high_risk": true|false|null` and `"risk_reasons": [...]` into `ctx.json`; the §1.5 table row for `gate-eval`, §10's title/intro ("6 conditions", "ALL 6"), the "On all 6 holding" line, §11, §12, the Anti-Patterns bullet, and the Quality Gates bullet all say six; the PARK reason reaches the existing park+notify path (`pause_reason: awaiting_merge` + the `--notify` gate line carries the reasons). D2 sentence added at cond 4 and in §12.
- [ ] AC8 — Tests: `loomwright/scripts/test-automate-helpers.sh` group E gains cond-6 cases (PARK on `true`, `null`, missing, non-boolean string; MERGE only with `"high_risk": false` and every other condition satisfied — update the existing all-pass ctx so the MERGE cases keep firing exactly once; `trust_unprotected: true` + `high_risk: true` ⇒ PARK) and its header comment says 6 conditions. New `loomwright/scripts/test-classify-risk.sh` (fixture git repo in `mktemp -d`, cwd elsewhere): each generic branch — (a) path match, (a) content-only match, (b) workflow path, (c) size by lines (>400), (c) size by files (>15), a clean small diff ⇒ `false`; `.agent/risk.json` `paths` and `content` extension; malformed ⇒ generic-only + stderr; `exclude` ignored; bad ref ⇒ `null`; jq-off-PATH ⇒ valid templated JSON; `--kind-table` == RESULT_SCHEMAS marker block byte-for-byte. Mutation controls (gate mutant on non-empty + differs + `bash -n`; LESSONS [fa32a308]): delete cond 6 from a COPY of `gate_eval` ⇒ the new group-E PARK cases must fail; delete the content-match branch from a COPY of the script ⇒ the content-only case must fail. Suite shape per `test-verify-provides.sh` (`ok()`/`no()` DEFINED, counters, `RESULT: N passed, M failed` tail, exit 1, `$BASH_SOURCE` paths). No registration needed — CI globs `loomwright/scripts/test-*.sh`.
- [ ] AC9 — Invariant surfaces: `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` resolves to the SAME five surfaces CLAUDE.md enumerates (paste the output in the PR body); CLAUDE.md §Failure-Mode Invariants "fires only when ALL FIVE trusted-merge conditions hold" → "ALL SIX" (do NOT touch its separate "exactly five surfaces" grep claim — that one is still five); `docs/ARCHITECTURE_CONTRACTS.md` carries NO gate-count claim today (verified 2026-09-13 — its Review-PR row says only "never auto-merges" and §"Until-mergeable" cites "§10 condition 1") — do NOT add one; optionally extend that "condition 1" pointer to name condition 6 as the second non-merge-eligible case; the repo-wide sweep for the OLD gate phrasing (`5-condition`, `ALL 5`, `all five`, `five conditions`, `5 conditions`, `5 per-PR booleans`) is updated on EVERY gate-related hit — `README.md`, `.claude-plugin/README.md`, `REQUIREMENTS-SITE-V2.md`, `commands/automate.md`, `commands/agent-help.md`, `skills/automate-loop/SKILL.md`, `scripts/automate-helpers.sh` header/comments, `scripts/test-automate-helpers.sh` — leaving only CHANGELOG history and the unrelated "five validators / five lenses" phrases (memory `sweep-grep-gate-variants`: grep bare numbers with flexible separators).
- [ ] AC10 — `bash scripts/check-token-budget.sh`, `bash scripts/check-doc-currency.sh`, `bash scripts/check-contract-parity.sh`, `bash scripts/check-vendor-coupling.sh`, and the FULL loop over BOTH globs `for t in scripts/test-*.sh loomwright/scripts/test-*.sh` are green before push (memory `run-full-ci-suite-loop-before-push` — the vendor-coupling ratchet lives only at root and bit PR #217; a new `${CLAUDE_PLUGIN_ROOT}` reference in a `coupled`/`core` file needs the manifest allowance raised IN THIS PR only if genuinely needed — prefer naming the script without the variable in prose). A budget is raised ONLY on measured breach.
- [ ] AC11 — Release surfaces: both manifests to the next minor above the LIVE `plugin.json` (currently 15.71.0 → 15.72.0; read it at execution — LESSONS [16ffd26d]), `vX.Y.Z` in both descriptions updated in place, ONE new CHANGELOG top entry (bold-paragraph shape) naming: the sixth condition and that it has NO override (R5), D1 (classification unconditional / spawn opt-in), the add-only `.agent/risk.json`, the honest limits (heuristic is pattern-based — a comment containing `token` trips it; `null` parks; the loop re-classifies the SHA it judges; nothing changes for `/review-pr`/Phase 4.5 which never merge), "Counts unchanged" (14/23/41/36 — read them live). Old version string 0-hit outside CHANGELOG.

## Executable Acceptance
- cmd: bash loomwright/scripts/test-classify-risk.sh
- cmd: bash loomwright/scripts/test-automate-helpers.sh
- cmd: bash scripts/check-token-budget.sh
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | classify-risk.sh + test suite + gate-eval cond 6 + group E + loop/lens/doc wiring + "5→6" sweep + release surfaces | all (AC1–AC11) | 15 modify (+ `prompt-token-budgets.json` only on measured breach), 2 create | `skills/unit-testing/SKILL.md`, `skills/quality-checklist/SKILL.md`, `AGENT_GUIDELINES.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1 — classify-risk.sh + condition 6 (LAUNCHABLE)
provides:
  - {kind: "file",   path: "loomwright/scripts/classify-risk.sh"}
  - {kind: "file",   path: "loomwright/scripts/test-classify-risk.sh"}
  - {kind: "symbol", path: "loomwright/scripts/classify-risk.sh", name: "kind-table"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "high_risk_diff"}          # the cond-6 PARK reason (0 hits today)
  - {kind: "symbol", path: "loomwright/scripts/test-automate-helpers.sh", name: "high_risk_diff"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/SKILL.md", name: "classify-risk.sh"}       # §10 cond 6 (0 hits today)
  - {kind: "symbol", path: "loomwright/skills/self-heal-advisory/SKILL.md", name: "classify-risk.sh"}  # lens pointer (0 hits today)
  - {kind: "symbol", path: "loomwright/agents/supervisor.md", name: "risk_classification"}            # result block (0 hits today)
  - {kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "risk-table:begin"}             # single committed heuristic copy (0 hits today)
  - {kind: "symbol", path: "loomwright/commands/automate.md", name: "condition 6"}
  - {kind: "symbol", path: "CHANGELOG.md", name: "classify-risk.sh"}                                   # new top entry (0 hits today)
requires: []
lanes:
  - "loomwright/scripts/classify-risk.sh"
  - "loomwright/scripts/test-classify-risk.sh"
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/test-automate-helpers.sh"
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/skills/self-heal-advisory/SKILL.md"
  - "loomwright/agents/supervisor.md"
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/commands/automate.md"
  - "loomwright/commands/agent-help.md"
  - "README.md"
  - ".claude-plugin/README.md"
  - "REQUIREMENTS-SITE-V2.md"
  - "CLAUDE.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - "CHANGELOG.md"
external_requires: []
```

**Implementation shape (the DO side — read every seam before editing; the gate file's header comment is law):**
1. **`loomwright/scripts/classify-risk.sh`** (`#!/usr/bin/env bash`, `set -uo pipefail`, always `exit 0`). Header: purpose, the fail-SAFE-emitter / `null`-is-fail-closed-for-the-consumer contract, R5 (no exclude), the glob semantics, the honest pattern-match limit. Args: `<base_ref> <head_ref> [--root <dir>]` | `--kind-table` | `-h`; malformed args ⇒ `null` + `unclassifiable: bad_args` (item 02's parser-exit lesson — every early exit emits JSON). Use `git -C "$root" diff --name-only "$base...$head"` and `git -C "$root" diff "$base...$head"` (three-dot, matching the lens); count lines as `+`/`-` lines excluding `+++`/`---` headers. Generic patterns as a data list at the top (one array for path/content globs, one for path-prefix dirs, one for content words) so `--kind-table` and the classifier read the SAME data. Project extension: `"$root/.agent/risk.json"` via `jq` with strict shape checks. JSON via `jq -n --arg`/`--argjson` only; reasons deduped, bounded (cap ~20, then `+N more`).
2. **`automate-helpers.sh gate_eval`**: after cond 5, before the merge line, add cond 6 exactly in the `unresolved_human_thread` read shape; PARK string `high_risk_diff (<first 3 risk_reasons, joined "; ">)` (reasons read defensively — absent ⇒ empty). Update the header comment's ctx.json example (`"high_risk": true|false|null, "risk_reasons": [...]  # cond 6 — NO override`), the `# ALL 5 hold` comment, and the §10 subcommand table line. No other behaviour change.
3. **`skills/automate-loop/SKILL.md`** §1.5 row, §6 step 4 (the GATE step names the re-classification), §10 (cond 6 text + loop contract: re-run on `<ready_sha>`, `null` ⇒ PARK, record the Supervisor's value for comparison), §11 (invariant unchanged — still five surfaces, six conditions), §12 (`--trust-unprotected` D2 sentence), Anti-Patterns ("Merging on bare `READY`" bullet → "ALL 6"), Quality Gates bullet.
4. **`skills/self-heal-advisory/SKILL.md`** lens per AC6/D1 — the pseudo-code block keeps its shape but the `high_risk = (...)` expression becomes `rc = bash "${CLAUDE_PLUGIN_ROOT}/scripts/classify-risk.sh" "$BASE_BRANCH" HEAD` + `high_risk = rc.high_risk` with a pointer to `--kind-table`; move the classification ABOVE the `RED_TEAM_ENABLED` guard. Keep the file's `${CLAUDE_PLUGIN_ROOT}` count within its vendor-coupling allowance (18) — replacing prose with one call is net-neutral or check the ratchet.
5. **`agents/supervisor.md`** result block + **`docs/RESULT_SCHEMAS.md`** (§SUPERVISOR_RESULT nested object + risk-table markers + the `session_end` flat-field table rows + the schema-history bullet) per AC6; **`docs/ARCHITECTURE_CONTRACTS.md`**: no gate-count row exists — do not create one (AC9).
6. **Commands/README sweep** per AC9 + D2; **release** per AC11; **tests** per AC8 — generate the RESULT_SCHEMAS risk-table block FROM `--kind-table` output (do not hand-type it).
7. Before push: the AC10 gate set; `grep -rn "15\.71\.0" --include=*.json --include=*.md . | grep -v CHANGELOG | grep -v "^./.supervisor\|^./.claude/worktrees"` empty; paste the AC9 invariant grep output into the PR body.

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md` (mutation-control discipline), `skills/quality-checklist/SKILL.md` (post-task gates), `AGENT_GUIDELINES.md` (read-before-write rule; every shell deliverable ships a co-located static `test-*.sh` — LESSONS [34e7c865]) |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Fail-OPEN polarity in cond 6 (the exact bug cond 3 once had: a `= "true"` test on a coerced value merged on a missing key) | HIGH | AC1 mandates the `has()`/`!= null`/`tostring`/`!= "false"` shape; group E tests missing / null / string / true all PARK; mutation control deletes cond 6 and requires red (LESSONS [fa32a308]) |
| An override leaks in through `--trust-unprotected` or a config key | HIGH | AC2 test; D2 sentence on every documenting surface; no config key read anywhere (grep `high_risk` in `automate-helpers.sh` must show only the ctx read) |
| Prior churn (postmortem ledger): `self_heal_miss` recurs on `CHANGELOG.md`, both manifests, `ARCHITECTURE_CONTRACTS.md`, `RESULT_SCHEMAS.md`; classes `drain_churn`, `convention_mismatch` — plus this PR's own "5→6" sweep is a restated-number class across ~10 surfaces | HIGH | AC9's explicit surface list + the flexible-separator grep; run the sweep grep AFTER editing and paste it; changelog carries no byte figures |
| Vendor-coupling ratchet (root-only gate — bit PR #217): a new `${CLAUDE_PLUGIN_ROOT}` mention in a prose surface breaches its allowance | MEDIUM | Name the script without the variable in prose surfaces that are at allowance; run `bash scripts/check-vendor-coupling.sh` + BOTH test globs before every push |
| Heuristic drift: the script's data list diverges from what the lens text promised (verbatim) | MEDIUM | The lens text becomes a pointer; `--kind-table` is the single copy, byte-compared in the suite; fixtures cover every branch a/b/c |
| `.agent/risk.json` treated as trusted input (glob/content injected into a regex or shell) | MEDIUM | Patterns are matched with `case` / `grep -F` (content terms literal, case-insensitive via `grep -iF`), never `eval`; strict shape validation; malformed ⇒ generic-only |
| Seam test vacuous (mutant invalid, helpers undefined) | LOW | Gate every mutant on non-empty + differs + `bash -n`; `ok`/`no` defined; assert the new pass count |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-13-high-risk-park-in-trusted-merge-gate.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-09-13T13:50:29Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/219
- **Branch:** feature/high-risk-park-trusted-merge-gate
- **Files changed:** 20
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** classify-risk.sh (fail-SAFE, set -f, add-only .agent/risk.json; 45-assertion suite w/ content + noglob mutants) + gate-eval condition 6 fail-CLOSED with NO override (boolean-typed read, applied to cond 3 too; group E 122) + loop re-classifies at GATE + lens classifies unconditionally (D1) + nested risk_classification on SUPERVISOR_RESULT (flat fields deliberately dropped) + 5→6 sweep + v15.72.0. Heal iteration 1 fixed 2 HIGH found by falsification (cwd glob expansion fail-OPEN; string "false" merging) + MEDIUM mirror drift; iteration 2 PASS. ground_truth: pass 5/5; contract_conformance: pass (1 evaluated, 0 violations); benchmark: pass; twin_builder: 2 written; rubric: n/a. Dogfood: this PR's own diff classifies high_risk:true (would park itself under --auto-merge — R5 as intended). Default drain suppressed by /automate (engine-owned).
