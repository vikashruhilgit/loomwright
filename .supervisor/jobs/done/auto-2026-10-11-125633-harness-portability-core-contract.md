# Supervisor Job: Harness portability — written core contract (`CORE_CONTRACT.md`) + re-verified Cursor/Codex capability matrix

## Environment
- **Project:** lane clone `L2` of `ai-agent-manager` (`<primary>-lanes/automate-2026-10-11-182243/L2`)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main (lane clone; origin = vikashruhilgit/loomwright)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1
- **Source requirement:** .supervisor/requirements/twin-remediation/10-harness-portability.md
- **Base commit:** 0aa53c37ac59fe86a99bd590b36b379d24f9956b

> **Warning (1):** this checkout is lane `L2` of the `--parallel 2` wave `automate-2026-10-11-182243`. Sibling lane `L1` (churn-ledger/02) runs at the same time in its own clone; its Touches (`pr-postmortem-gather.sh`, its test, the `pr-postmortem` skill/command, `docs/RESULT_SCHEMAS.md`, its fragment) do not intersect this item's. Stay inside this item's `## Touches`. This PR carries a `changelog.d/` fragment and NO version bump (lane PRs never bump; the bump is the wave branch's last commit).

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Markdown + one JSON manifest edit; no code. |
| 2 | Dependency Availability | GO | `curl` reaches the vendor doc sites from this machine (both returned HTTP 200 at planning time); `jq`, `git` present. |
| 3 | Architecture Fit | GO | Writes down the contract the shipped seams already imply: `resolve-loomwright-root.sh` (the one reader of the harness root variable), `check-vendor-coupling.sh` + `vendor-coupling-manifest.json` (CORE/ADAPTER/COUPLED classification), `capabilities.json` / `CAPABILITIES_CONTRACT.md` (outbound host contract), `ARCHITECTURE_CONTRACTS.md` §"Portability". |
| 4 | Scope vs Supervisor Capability | GO | One new doc, one pointer line, one manifest allowance, one fragment — single subtask. |
| 5 | Hard Blockers | GO | Dependency `agnostic-phase1/01-ratchet-hardening.md` is `## Status: done`. |

**Overall Verdict:** GO

## Task
**Goal:** Deliver the two remaining parts of requirement twin-remediation/10 as re-scoped on 2026-10-10: (1) a written, versioned core contract `loomwright/docs/CORE_CONTRACT.md` — the file protocol, the CLI surface, and the five capability ports each with a documented degraded fallback, naming `loomwright/scripts/resolve-loomwright-root.sh` as the one place the harness root variable is read; (2) the Cursor / Codex capability matrix re-verified from CURRENT official vendor docs (each source cited with its fetch date; anything not re-verified labelled UNVERIFIED) and recorded in that document; plus (3) one pointer to the new contract from `ARCHITECTURE_CONTRACTS.md`.

**Problem Statement:** The vendor-neutral core is real (plain-file state, bash+jq engine scripts, a coupling ratchet, a root-resolver seam, a provider-adapter spike) but its contract exists only implicitly, scattered across script headers and docs. An adapter author for another harness has no single document saying what the core requires of a harness, what each capability falls back to when absent, and which file layouts and exit-code conventions are stable. The requirement's 2026-08-22 capability matrix is now seven weeks old and explicitly says "re-verify at adapter-build time".

**Out of scope (requirement Re-scope 2026-10-10):** migrating the remaining scripts that still read the harness root variable directly onto `LOOMWRIGHT_ROOT` (a repo-wide sweep — filed as its own follow-up, not done here); no edits to any script; no prompt-layer porting.

## Acceptance Criteria
- [ ] **AC1 (document exists, versioned, pointer-first).** Given the PR branch, when `loomwright/docs/CORE_CONTRACT.md` is read, then it opens with a one-paragraph purpose (what an adapter implements) and a `core_contract_version: 1` marker (a plain line, plus a short compatibility policy: additive change keeps the version, a removal/rename/meaning change bumps it). Every section points at the AUTHORITATIVE source for detail (script headers, `docs/RESULT_SCHEMAS.md`, `docs/CAPABILITIES_CONTRACT.md`, `docs/ARCHITECTURE_CONTRACTS.md` §"State Ownership" / §"`.supervisor/` retention policy" / §"Metadata branch" / §"Portability", `skills/state-management/SKILL.md`, `docs/vendor-coupling-manifest.json`) instead of restating it. It states NO literal counts of agents/commands/skills/hooks/scripts/refs (house rule: a count lives in one authoritative place) and no plugin version string.
- [ ] **AC2 (file protocol).** Given the doc's "File protocol" section, then it describes the `.supervisor/` layout (jobs lifecycle `pending/ → in-progress/ → done/ | failed/`, `state.md` + session logs `logs/<session_id>.jsonl`, `automate/<run_id>.md` run files and their sidecars, `requirements/` + `requirements/proposed/`, `postmortem/results.jsonl`, `memory/`, `config.json`) and the `.agent/` layout (`rules/`, `orientation/`, `companions.json`, and `lane-policy.json` as an optional file), each with: who writes it (sole-writer where one exists), its lifecycle, whether it is tracked / gitignored / metadata-branch-managed, and its authority pointer. Every path it names is verified to exist in the repo or in a documented writer (a writer script or skill named alongside) — none invented. It states why `.agent/` lives outside the harness config directory (portability by construction).
- [ ] **AC3 (CLI surface + exit-code convention codified).** Given the doc's "CLI surface" section, then it (a) codifies the bimodal failure convention verbatim in substance: correctness gates fail CLOSED (non-zero / a named PARK or refusal) and side-effect emitters fail SAFE (always exit 0), with the `|| true` hooks-wiring rule and its exception for fail-CLOSED blocking hooks (pointer to `docs/HOOKS.md`); (b) lists the engine entry points by role — state/run-file helpers (`automate-helpers.sh`, `run-lock.sh`), result parsing/validation (`result_block_parser.py`, `validate-*-result.py`), progress/state projection (`emit-progress-event.sh`, `build-state.sh`), emitters (`emit-lifecycle.sh`, `send-webhook.sh`, `notify-desktop.sh`), gates (`rules-gate-verdict.sh`, `classify-risk.sh`, `guard-test-integrity.sh`, `guard-finalize-publish.sh`, `verify-provides.sh`), readers (`read-rules.sh`, `read-lessons.sh`, `read-postmortem.sh`, `read-token-ledger.sh`), host contract (`build-capabilities.sh`, `host-mode.sh`), and the root resolver — each row giving argv shape, stdin use, stdout shape, exit codes and failure mode (SAFE/CLOSED) **as read from that script's own header/usage text** (the worker reads every header it cites; a value it could not confirm is written `see header` rather than guessed); (c) states that each script's header is the per-script authority and this table is an index.
- [ ] **AC4 (five capability ports with degraded fallbacks).** Given the doc's "Capability ports" section, then each of the five ports — run-a-subagent, run-in-background, isolate-a-workspace, react-to-an-event, deliver-instructions — has: what the core needs from it (one sentence), the seams in the core that consume it (named files/skills), the Claude Code adapter's binding today, and a **degraded fallback** when a harness lacks it (minimum: no subagents ⇒ the Single-Agent Path / inline execution on the main thread; no background tasks ⇒ foreground polling at the same seam; no worktree isolation ⇒ sequential execution in one checkout; no event hooks ⇒ explicit invocation of the same script at the same seam, with which hook-driven guarantees are LOST named honestly (e.g. a fail-CLOSED `PreToolUse` guard has no explicit-invocation equivalent — state it); no instruction file ⇒ inline the vendor-neutral instruction subset in the first prompt). A fallback the worker cannot ground in an existing seam is labelled `proposed (not implemented)`, never presented as shipped.
- [ ] **AC5 (root resolution).** Given the doc, then a "Root resolution" section names `loomwright/scripts/resolve-loomwright-root.sh` as the ONE place the harness root variable is read, summarises its precedence (harness variable → pre-set `LOOMWRIGHT_ROOT` → dev-checkout location) by pointing at its header, states that it is ADAPTER-classed in the coupling manifest (and why), and states honestly that other scripts still read the harness variable directly today — that migration is a separate follow-up item. No count in `CORE_CONTRACT.md`: the measured list and count live only in the AC9 follow-up draft, which the doc points to.
- [ ] **AC6 (re-verified capability matrix).** Given the doc's "Harness capability matrix" section, then for Cursor and Codex (and Claude Code as the reference column) it records, per port plus `skills`: the capability as stated by CURRENT official vendor documentation, fetched by the worker during this run with `curl -sL` (record the exact URL and the UTC fetch date for every source; vendor docs only — cursor.com/docs, developers.openai.com/codex, docs.anthropic.com / code.claude.com — never blogs or third-party summaries). Every cell is either `VERIFIED <date> [source n]` or `UNVERIFIED` (with why: page not found, behaviour not documented, fetched page did not state it). It contrasts the result with the requirement's 2026-08-22 matrix: rows that changed, rows confirmed, rows that could not be re-verified. It keeps the requirement's standing limit explicit: capability EXISTENCE from docs is not behavioural FIDELITY (e.g. whether Cursor's `subagentStop` payload carries the fields our validators read stays UNVERIFIED unless a doc states the payload schema). If a fetch fails, the cell is UNVERIFIED — the worker never fills a cell from recollection.
- [ ] **AC7 (pointer row).** Given `loomwright/docs/ARCHITECTURE_CONTRACTS.md`, then its `## Portability` section gains ONE short pointer paragraph/bullet to `CORE_CONTRACT.md` (what it holds, in one sentence). The pointer adds no vendor-coupling token (none of the manifest's `token_classes` strings), no count/version claim, and no bare `file:N` citation, so the file's coupling allowance and doc-currency claims are unchanged.
- [ ] **AC8 (coupling ratchet honoured).** Given the new doc names harness-specific tokens (the matrix necessarily does), when `bash scripts/check-vendor-coupling.sh` runs on the branch (after `git add` — the gate scans the tracked tree), then it passes: `loomwright/docs/CORE_CONTRACT.md` (class `coupled` via the `loomwright/docs/*` glob) gets an allowance in `loomwright/docs/vendor-coupling-manifest.json` equal to its measured count, with a NEW one-line `allowance_reasons["loomwright/docs/CORE_CONTRACT.md"]` entry stating why (the contract document's capability matrix and port bindings must name the harness primitives it maps). Keep the count as low as the content allows (write the Claude binding by pointer where a literal token adds nothing). `bash scripts/test-check-vendor-coupling.sh` passes. No other allowance changes.
- [ ] **AC9 (follow-up filed, not executed).** Given the PR is ready, when `.supervisor/requirements/proposed/` is listed, then a follow-up requirement draft for the `LOOMWRIGHT_ROOT` call-site migration (the scripts that still read the harness root variable directly, with the measured list and the base commit) is written to `.supervisor/requirements/proposed/twin-remediation-11-loomwright-root-migration.md` (propose-only; gitignored state, not part of the PR diff) and named in the doc's "Root resolution" section as the follow-up. No script is migrated in this PR.
- [ ] **AC10 (fragment, no bump).** Given the PR diff, then `changelog.d/twin-remediation-10-harness-portability.md` exists (format per `changelog.d/README.md`, `<!-- bump: minor -->`); no version file (`loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CHANGELOG.md`) is touched.
- [ ] **AC11 (CI green).** Given the PR branch, when `bash scripts/ci-local.sh` runs, then it passes — in particular doc-currency, citation drift (no bare unpinned `file.ext:<N>` citation in the new doc; use descriptive anchors), the vendor-coupling ratchet, and the home-path scrub rule (no `/Users/<name>/` or `/home/<name>/` path anywhere in the new doc). The PR body pastes the ci-local result line.

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

## Configuration
- **Mode:** single-agent
- **Base Branch:** main
- **Workers:** 1

## Touched-file invariants

> Grounded at base `0aa53c37ac59fe86a99bd590b36b379d24f9956b`.

- **`loomwright/docs/vendor-coupling-manifest.json`**
  - keep: the allowance is MEASURED, never hand-typed — stage `loomwright/docs/CORE_CONTRACT.md` first (`git add`; the gate enumerates the tracked tree with `git ls-files`, so an unstaged new file is invisible), then read its count from `bash scripts/check-vendor-coupling.sh --print-allowances` and copy that number into `"allowances"`.
  - keep: a NEW `"allowance_reasons"` entry for `loomwright/docs/CORE_CONTRACT.md` (the gate's `raise_check` compares reasons with `origin/main`; an absent or inherited reason fails the raise).
  - keep (self-raise trap): the manifest scans ITSELF (its own allowance is `28` at base). The new reason text must DESCRIBE vendor tokens, never quote one (no `token_classes` string inside the reason), or the manifest's own count rises and AC8's "no other allowance changes" breaks. Re-run `--print-allowances` after the edit and confirm the manifest's own count is still 28.
  - keep: `"token_classes"`, `"classes"`, `"unclassified_default"`, `"policy_reasons"` byte-unchanged; JSON stays valid (`jq empty`); key order/indent style of the existing `allowances` / `allowance_reasons` maps (insert the new key in its sorted position).
  - pinned by: `scripts/test-check-vendor-coupling.sh` (`REAL_MANIFEST` — jq reads of `.token_classes[].tokens[]`, `.classes.adapter.globs`, `.classes.adapter_frontmatter.globs`); the CI gate `scripts/check-vendor-coupling.sh` (its `MANIFEST=` default path), run by `scripts/ci-local.sh`.
- **`loomwright/docs/ARCHITECTURE_CONTRACTS.md`**
  - keep: the `## Portability` heading and every existing paragraph byte-unchanged (append the one pointer; do not reflow); its vendor-coupling allowance (`42` at base) unchanged — the pointer carries no `token_classes` string; no new count/version claim (it is in `scripts/check-doc-currency.sh`'s `FILES` scan list); no bare `file:N` citation.
  - pinned by: `scripts/check-doc-currency.sh` (`FILES`), `loomwright/scripts/test-citation-drift.sh`, `scripts/check-vendor-coupling.sh`.

## Subtask Structure

| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | Write `CORE_CONTRACT.md` (file protocol, CLI surface, five ports + fallbacks, root resolution, re-verified matrix); pointer row; manifest allowance; follow-up draft; fragment | 2 modify, 2 create | LAUNCHABLE |

### Subtask 1 — Core contract + re-verified matrix (LAUNCHABLE)
- **Criteria:** AC1–AC11
- **Files (create):** `loomwright/docs/CORE_CONTRACT.md` (HIGH), `changelog.d/twin-remediation-10-harness-portability.md` (HIGH)
- **Files (modify):** `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (HIGH — one pointer in `## Portability`), `loomwright/docs/vendor-coupling-manifest.json` (HIGH — one allowance + one reason)
- **Files (gitignored, not in the PR):** `.supervisor/requirements/proposed/twin-remediation-11-loomwright-root-migration.md`
- **Read-only inputs:** `loomwright/scripts/resolve-loomwright-root.sh` (+ its test), `scripts/check-vendor-coupling.sh` (header), `loomwright/docs/CAPABILITIES_CONTRACT.md`, `loomwright/docs/HOOKS.md`, `loomwright/docs/RESULT_SCHEMAS.md`, `loomwright/skills/state-management/SKILL.md`, `loomwright/scripts/adapters/providers/*` (the shipped provider spike), every script header the CLI table cites, the source requirement's §"Re-baseline (2026-08-22)" matrix.
- **Research method (AC6):** `curl -sL -m 30 <url>` to official vendor docs, saving each fetch to a scratch file outside the repo and recording URL + `date -u` fetch time; read the fetched text, not memory. Starting points (verify they still resolve; follow the vendor's own nav if moved): Cursor — `https://cursor.com/docs/agent/hooks`, the Cursor docs pages for rules, subagents/background agents, skills and worktrees; Codex — `https://developers.openai.com/codex/hooks`, the Codex docs pages for AGENTS.md, subagents, skills/config; Claude Code reference column — the official Claude Code docs.
- **Skills:** `quality-checklist`

```yaml
# Subtask 1 — Core contract + re-verified matrix (LAUNCHABLE)
provides:
  - {kind: "file", path: "loomwright/docs/CORE_CONTRACT.md"}
  - {kind: "symbol", path: "loomwright/docs/CORE_CONTRACT.md", name: "core_contract_version"}
  - {kind: "symbol", path: "loomwright/docs/CORE_CONTRACT.md", name: "resolve-loomwright-root.sh"}
  - {kind: "symbol", path: "loomwright/docs/CORE_CONTRACT.md", name: "UNVERIFIED"}
  - {kind: "symbol", path: "loomwright/docs/ARCHITECTURE_CONTRACTS.md", name: "CORE_CONTRACT.md"}
  - {kind: "symbol", path: "loomwright/docs/vendor-coupling-manifest.json", name: "loomwright/docs/CORE_CONTRACT.md"}
  - {kind: "file", path: "changelog.d/twin-remediation-10-harness-portability.md"}
requires: []
lanes:
  - "loomwright/docs/CORE_CONTRACT.md"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "changelog.d/twin-remediation-10-harness-portability.md"
external_requires:
  - "network access to cursor.com and developers.openai.com (curl) for the AC6 re-verification"
```

## Parallelism Analysis
single-agent (no fan-out)

- Recommended workers: 1

## Skill References
- `loomwright/skills/quality-checklist/SKILL.md`

## Risk Assessment

| Risk | Level | Source | Mitigation |
|------|-------|--------|------------|
| The contract doc restates facts owned elsewhere and drifts | MEDIUM | House rules (restated-list rule) | Pointer-first: every section links its authority; no literal counts; the CLI table is declared an index over script headers. |
| A matrix cell filled from model recollection rather than a fetched page | HIGH | Requirement (read-before-write rule) | Every cell cites a fetched URL + UTC date or reads `UNVERIFIED`; raw fetches kept in a scratch dir outside the repo; Phase 4.5 reviewer asked to spot-check sources. |
| New doc trips the vendor-coupling ratchet | MEDIUM | `scripts/check-vendor-coupling.sh` | Measure after `git add`; add the allowance + a NEW reason in the same PR (the raise_check compares against `origin/main`); keep literal tokens minimal. |
| A bare `file:N` citation or a home path in the new doc fails ci-local | MEDIUM | `test-citation-drift.sh`, meta-sync `home_path` scrub | Descriptive anchors only; `~/`-relative or placeholder paths. |
| Prior churn on `ARCHITECTURE_CONTRACTS.md` / the manifest (drain_churn, self_heal_churn; a self_heal_miss recorded) | MEDIUM | Prior churn (postmortem ledger) | Keep the `ARCHITECTURE_CONTRACTS.md` edit to one pointer with no tokens/claims; touch exactly one manifest allowance + one reason; run `test-check-vendor-coupling.sh` and doc-currency before push. |
| A degraded fallback is presented as shipped when it is not | MEDIUM | Analysis | AC4 requires `proposed (not implemented)` for any fallback without an existing seam. |
| The manifest scans itself: quoting a vendor token inside the new reason raises the manifest's own count | MEDIUM | Plan Review attempt 1 | Touched-file invariants: describe tokens, never quote them; re-measure the manifest's own count (28 at base) after the edit. |
| Vendor doc URLs moved or a site blocks curl | LOW | Feasibility | Follow the vendor's own navigation; on failure mark the cells `UNVERIFIED` with the reason — never a guessed source. |

## Handoff
/supervisor job: .supervisor/jobs/pending/auto-2026-10-11-125633-harness-portability-core-contract.md

## Outcome
- **Status:** completed
- **Completed:** 2026-10-11T14:37:54Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/479
- **Branch:** feature/twin-remediation-10-harness-portability-core-contract
- **Files changed:** 4
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** CORE_CONTRACT.md (core_contract_version 1: file protocol, CLI index + bimodal exit convention, five ports with fallbacks, root resolution, Cursor/Codex matrix re-verified 2026-10-11), one Portability pointer, measured coupling allowance (1), fragment. Phase 4.5 consistency_audit PASS first pass (1 MEDIUM + 4 LOW + 1 nit dismissed); ground truth 2/2; ci-local 165 PASS / 1 pre-existing env FAIL (test-automate-helpers W19, fails identically on base 0aa53c3).

## Not verified
- **loomwright/docs/CORE_CONTRACT.md §5 harness matrix (Cursor/Codex behaviour)** — no Cursor or Codex runtime observed; capability existence from vendor docs only (subtask 1)
