# Supervisor Job: Verification environment contract (`.agent/verify.json`) — schema, fail-safe reader, propose-only bootstrap, executor, seam test

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — matches plugin.json 15.72.0, no version claims of its own)
- **Git:** dirty (1 file — `.supervisor/postmortem/results.jsonl`, 3 appended engine-native ledger lines for PRs #215/#217/#219 left uncommitted by the 2026-09-13 `/automate` run; precedent commit `5a8b8b0` folded the same class into a `chore(postmortem)` commit on `main`), branch: main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 2 (dirty ledger above; 3 stale briefs in `.supervisor/jobs/in-progress/` from 2026-09-03..05 — unrelated, do not touch)
- **Source requirement:** .supervisor/requirements/verify-walkthrough/01-verify-env-contract.md
- **Base commit:** c30a1dba4d07505bd41cae83712bc75209debbb9

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure bash 3.2 + jq + `git ls-files`-style tooling, exactly the stack every `read-*.sh` / `propose-*.sh` in `loomwright/scripts/` already uses. No new runtime. |
| 2 | Dependency Availability | GO | `jq` is the only dependency and every sibling reader already carries the `command -v jq` skip-not-fail guard. The `start` fixture uses `python3 -m http.server` (present on macOS + ubuntu CI). |
| 3 | Architecture Fit | GO | The item is the `.agent/product.json` pattern applied verbatim: `propose-product.sh` (sole writer, `--confirm`) / `read-product.sh` (advisory, exit 0, empty stdout on absence) / `RESULT_SCHEMAS.md` §PRODUCT_CONTEXT (no `schema_version`, documented exception) / co-located `test-*.sh`. Bimodal failure philosophy (CLAUDE.md §Failure-Mode Invariants) is preserved: the reader fails SAFE, `assert-non-prod` fails CLOSED. |
| 4 | Scope vs Supervisor Capability | GO (split) | 5 modify + 4 create = 9 files, but the four new scripts alone will exceed the 800-changed-line `context-bound` bound (the product-pattern equivalents total 1,837 lines on disk). Split reason `context-bound` → 2 sequential subtasks. |
| 5 | Hard Blockers | GO | No migrations, no credentials (V8: the plugin never handles credentials; `auth.storage_state_path` is only a file path the executor READS), no new agent (V1). |

**Overall Verdict:** GO

## Task
**Goal:** Ship the committed `.agent/verify.json` verification-environment contract — its `RESULT_SCHEMAS.md` §VERIFY_ENV schema, a fail-safe `read-verify.sh` reader, a propose-only `--confirm`-gated `propose-verify.sh` bootstrap that never guesses `non_prod_assert`, a `verify-env.sh` executor that refuses to run anything before `assert-non-prod` passes, and `test-verify-seam.sh` with a mutation control — so a later `/verify` (item 03) can start / health-check / seed / reset / probe-auth an app under test and prove it is not production.

**Problem Statement:**
The owner's `/verify <ticket>` lane (`.supervisor/requirements/verify-walkthrough/00-overview.md`, decisions V1–V8) needs to drive a running app, but nothing in the plugin can start the app under test, seed it, reset it, sign in to it, or prove the target is non-production — `agents/qa-executor.md` Phase 3 requires the app to already be running, Phase 5 only inventories seed data, and auth is one `--auth-state` flag.
Currently, every future `/verify` run would re-guess all five per app. This causes either per-run flag re-typing or an unvalidatable CLAUDE.md section, and — worst — a run that touches production because nothing asserts it cannot.
Success looks like: a project declares the contract once in a committed file; a reader hands it to `/verify`; absence is announced by name and stops the run before the app is touched; every mutating subcommand is gated behind a fail-CLOSED non-prod assertion in the same invocation.

## Acceptance Criteria
- [ ] AC1 Given no `.agent/verify.json`, when `read-verify.sh` runs, then stdout is empty, exit is 0, and stderr names the path.
- [ ] AC2 Given a store missing any one required key (`start`, `base_url`, `health`, `auth`, `non_prod_assert`, `seed`, `reset`, `stop`), when `read-verify.sh` runs, then stdout is empty (malformed, reason on stderr); given a store with every key present and `seed: null`, `reset: null`, `start: null`, then it reads as valid (validated object on stdout).
- [ ] AC3 Given `{"non_prod_assert":{}}`, when `verify-env.sh assert-non-prod` runs, then exit is non-zero with reason `non_prod_assert_empty`; given `base_url_matches: "^http://localhost"` and `base_url: "https://app.example.com"`, then exit is non-zero with `non_prod_assert_failed`; given a matching regex, then exit is 0.
- [ ] AC4 Given a fixture whose `health` never returns 2xx, when `verify-env.sh start` runs, then it exits non-zero after `ready_timeout_s` with `health_timeout` and has run `stop`; given a fixture whose `start` is `python3 -m http.server <port>` and whose `health` is served by it, then it exits 0 within the timeout.
- [ ] AC5 Given `loomwright/scripts/`, when grepping for `verify.json` write paths, then exactly one `mv` target exists — in `propose-verify.sh` (the sole writer); `read-verify.sh` and `verify-env.sh` never write the store.
- [ ] AC6 Given `RESULT_SCHEMAS.md`, when `## VERIFY_ENV` is added (with the `schema_version` exception note extended to name it), then `scripts/check-doc-currency.sh` is green.
- [ ] AC7 Given `propose-verify.sh`, when run without `--non-prod`, then it writes nothing and exits non-zero; with `--non-prod <regex|env=NAME=VAL>` and no `--confirm`, then it prints the proposal and writes nothing (exit 0); with both, then it writes exactly one file (`.agent/verify.json`, same-dir temp + atomic `mv`) — verified in the test under a `mktemp -d` project, never in this repo.
- [ ] AC8 Given `test-verify-seam.sh`, when the reader's presence check (`has("seed")`) is deleted from a COPY of the reader, then the missing-`seed` case fails the suite (mutation control gated on non-empty + differs-from-original + `bash -n`).
- [ ] AC9 Given `verify-env.sh`, when any of `start|stop|seed|reset|auth-probe` is invoked, then it refuses (non-zero, named reason) unless `assert-non-prod` has passed in the SAME invocation; the reader (`read-verify.sh`) never executes any contract string.
- [ ] AC10 Given the full `loomwright/scripts/test-*.sh` loop plus root `scripts/test-*.sh` and `scripts/check-vendor-coupling.sh`, when run, then all are green (the four new scripts carry ZERO vendor tokens — no `CLAUDE_PLUGIN_ROOT`, no `~/.claude` — so no manifest allowance change is needed).

## Outcomes Rubric
- Store absent ⇒ announced, never guessed
- Every required key presence-checked, null-legal keys tested both ways
- `non_prod_assert` fails CLOSED and is never inferred by the scanner
- Exactly one writer, propose-only, `--confirm`-gated
- Reader never executes a contract string

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | VERIFY_ENV schema + `read-verify.sh` reader + `propose-verify.sh` bootstrap + seam test (reader/bootstrap cases + mutation control) | AC1, AC2, AC5, AC6, AC7, AC8 | 2 modify, 3 create | `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 2 | `verify-env.sh` executor + executor cases appended to the seam test + release entry (CHANGELOG + version bump) | AC3, AC4, AC9, AC10 | 4 modify, 1 create | `skills/quality-checklist/SKILL.md`, `skills/error-handling/SKILL.md` | BLOCKED (by #1) |

### Subtask Contracts

```yaml
# Subtask 1 — schema + reader + bootstrap + seam test (LAUNCHABLE)
provides:
  - {kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "## VERIFY_ENV"}
  - {kind: "file", path: "loomwright/scripts/read-verify.sh"}
  - {kind: "file", path: "loomwright/scripts/propose-verify.sh"}
  - {kind: "file", path: "loomwright/scripts/test-verify-seam.sh"}
  - {kind: "symbol", path: "AGENT_GUIDELINES.md", name: "propose-verify.sh"}
requires: []
lanes:
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/scripts/read-verify.sh"
  - "loomwright/scripts/propose-verify.sh"
  - "loomwright/scripts/test-verify-seam.sh"
  - "AGENT_GUIDELINES.md"
external_requires:
  - "jq (already required by every sibling reader; skip-not-fail guard)"

# Subtask 2 — executor + executor test cases + release entry (BLOCKED by #1)
provides:
  - {kind: "file", path: "loomwright/scripts/verify-env.sh"}
  - {kind: "symbol", path: "loomwright/scripts/test-verify-seam.sh", name: "== (AC3) assert-non-prod"}
  - {kind: "symbol", path: "CHANGELOG.md", name: "verify-env.sh"}
requires:
  - {from: "1", kind: "file", path: "loomwright/scripts/read-verify.sh"}
  - {from: "1", kind: "file", path: "loomwright/scripts/propose-verify.sh"}
  - {from: "1", kind: "file", path: "loomwright/scripts/test-verify-seam.sh"}
  - {from: "1", kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "## VERIFY_ENV"}
lanes:
  - "loomwright/scripts/verify-env.sh"
  - "loomwright/scripts/test-verify-seam.sh"
  - "CHANGELOG.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
external_requires:
  - "python3 (for the `python3 -m http.server` start/health fixture in AC4; present on macOS and ubuntu CI)"
  - "curl (health poll + auth probe; PATH-stubbable in the test)"
```

**Shared-file note (`test-verify-seam.sh`):** Subtask 2 is reachable from Subtask 1 in the `requires` DAG, so the shared lane is sequential and legal. Sequential sharing grants visibility, not preservation — Subtask 2 MUST re-run the whole suite after appending its cases and confirm Subtask 1's reader/bootstrap cases and the AC8 mutation control still pass (never edit or delete Subtask 1's cases).

## Implementation notes (per subtask — the precedent to copy, not re-invent)

**Subtask 1**
- `read-verify.sh`: model on `loomwright/scripts/read-product.sh` — `set -uo pipefail` (NO `set -e`), `diag()` to stderr, `--store <file>` / `--repo <dir>` flags plus `VERIFY_STORE` / `VERIFY_REPO_DIR` env overrides for tests, `command -v jq` skip-not-fail. Contract per the requirement: root must be an object; required keys `start`, `base_url`, `health`, `auth` (object: `method` ∈ `none|storage_state`, `storage_state_path`, `probe_path`), `non_prod_assert` (object with ≥1 usable member of `base_url_matches` (string) / `env_var_equals` (`{name,value}`) / `cmd` (string)), `seed`, `reset`, `stop`; optional `ready_timeout_s` (default 60, applied by the executor not the reader), `notes`. Nullable-but-required keys (`start`, `seed`, `reset`, `stop`) are checked with jq `has()` — NEVER `.key // …` (memory `nullable-required-field-needs-presence-check`; the `//`-collapses-null defect shipped once in `read-rules.sh`). Malformed ⇒ empty stdout + reason on stderr + exit 0. Valid ⇒ the validated JSON object on stdout (machine consumers gate on non-empty stdout). It is a READER: it never executes any of the shell strings.
- `propose-verify.sh`: model on `loomwright/scripts/propose-product.sh` — `set -euo pipefail`, `die()`, scan `package.json` scripts (`dev|start|serve`, `db:seed|db:reset`), `playwright.config.*` (`baseURL`, `webServer`), `.env*` (`APP_URL|BASE_URL|PORT`), `docker-compose*.yml`, `prisma/seed*`, `Makefile` targets; print the proposal; `--non-prod <regex|env=NAME=VAL>` is REQUIRED and never guessed (the `--stance` analogue — refuse + write nothing + exit non-zero without it, even with `--confirm`); shape validation runs BEFORE the confirm gate; write ONLY on `--confirm` (or interactive TTY "y"): `mkdir -p .agent`, same-dir `mktemp`, atomic `mv -f`. Sole writer: exactly one `mv` onto `verify.json` across `loomwright/scripts/`. Honour `--repo <dir>` so the test writes under a `mktemp -d` project, never this repo's `.agent/`.
- `RESULT_SCHEMAS.md`: add `## VERIFY_ENV` (a state-file schema like §PRODUCT_CONTEXT — document the nullable-required rule, the `non_prod_assert` fail-CLOSED semantics, the reader contract, "absence is the CONSUMER's to announce", and the TRUST SURFACE: the shell-string members are executed by `verify-env.sh` with full shell privileges and are trusted exactly like `package.json` scripts) and extend the existing "Deliberate exception to the `schema_version` rule" blockquote (near the top) to name `VERIFY_ENV` alongside `PRODUCT_CONTEXT`. Place the section immediately after `## PRODUCT_CONTEXT`, before `## Validation Location`.
- `AGENT_GUIDELINES.md` §"Sole-writer confirm gates": add the `propose-verify.sh` / `.agent/verify.json` / tracked-by-destination / **required** row and update the prose counts ("seven sole writers" → eight; "Six of the seven writers share `validate-entry.sh`" → six of the eight; the "`propose-product.sh` is the seventh" sentence gains `propose-verify.sh` as the eighth with the same shape-validation-instead-of-validator rationale). Grep the OLD count repo-wide before finishing (lesson `0d7865dc`: `check-doc-currency.sh` does not scan this).
- `test-verify-seam.sh`: model on `loomwright/scripts/test-read-product.sh` + `test-propose-product.sh` — `set -uo pipefail`, `ok()/no()` counters, every fixture under `mktemp -d`, PATH stubs for `jq`-absent, exit 0/1. Cases: absent store; unparseable JSON; non-object root; each of the 8 required keys missing (loop); `non_prod_assert` with no usable member; `seed: null` valid vs `seed` missing invalid (both directions, AC2); `propose-verify.sh` without `--non-prod` writes nothing + non-zero; with `--non-prod` and no `--confirm` writes nothing; `--confirm` writes exactly one file; AC5 sole-writer grep; AC8 mutation control (sed the `has("seed")` check out of a COPY, gate the mutant on non-empty + differs + `bash -n`, assert the missing-`seed` case now FAILS against the mutant). Leave a clearly marked `# --- executor cases (Subtask 2 appends below this line) ---` anchor at the end, before the final summary/exit. Do NOT emit the literal `== (AC3) assert-non-prod` anywhere in this file — that case-header string is Subtask 2's `provides` token and must first appear with Subtask 2's executor cases.

**Subtask 2**
- `verify-env.sh`: the ONLY thing that runs the contract's shell strings. `set -uo pipefail`; loads the contract via `read-verify.sh` (never re-parses; empty stdout ⇒ `verify_store_unreadable`, non-zero). Subcommands: `assert-non-prod` (fail CLOSED — `non_prod_assert_empty` when no usable member; evaluates `base_url_matches` (ERE against `base_url`), `env_var_equals`, `cmd` (exit 0 = pass); ≥1 pass ⇒ exit 0, else `non_prod_assert_failed` exit 1), `start` (run `start` if non-null via `bash -c` in the background, record pid to a marker under `--state-dir` (default `.supervisor/verify/env/`), poll `health` with `curl -fsS -o /dev/null` every 1s until 2xx or `ready_timeout_s` (default 60); on timeout run `stop` then exit non-zero with `health_timeout`), `stop` (run `stop` if non-null, else kill the recorded pid), `seed`, `reset`, `auth-probe` (GET `probe_path` with the storage-state cookies — read `storage_state_path` cookies with jq into a `Cookie:` header; print `authenticated|anonymous` by 2xx vs 401/302; `method: none` ⇒ print `anonymous` without a request). EVERY subcommand runs `assert-non-prod` first in the same invocation and refuses (`non_prod_not_asserted`) before touching anything; `--health-timeout`/`--ready-timeout-s` override for tests. Never writes `.agent/verify.json`.
- Append executor cases to `test-verify-seam.sh` after the anchor, each under an `echo "== (ACn) <name> =="` case header — the AC3 block MUST be headed exactly `echo "== (AC3) assert-non-prod =="` (this literal is the subtask's `provides` token): AC3 (three assert-non-prod arms + `env_var_equals` + `cmd`), AC4 (never-2xx fixture with `ready_timeout_s: 2` ⇒ `health_timeout` + evidence `stop` ran (a `stop` that touches a marker file); `python3 -m http.server` on a free port ⇒ exit 0), AC9 (a `start` fixture whose `non_prod_assert` fails ⇒ `start` never executed — the `start` string touches a marker file that must NOT exist afterwards). Re-run the FULL suite and confirm Subtask 1's cases + AC8 still pass.
- Release: read the LIVE `loomwright/.claude-plugin/plugin.json` version at execution time (lesson `16ffd26d`) and bump the minor (15.72.0 → 15.73.0 if unchanged) in BOTH `plugin.json` and `.claude-plugin/marketplace.json` (the `vX.Y.Z` in each `description` in place — never append a clause); add ONE `**v15.73.0 — …:**` paragraph directly after the historical-entries blockquote in `CHANGELOG.md`, ending with "Counts unchanged: 14 agents, 23 commands, 41 skills, 36 hooks." Do NOT touch README.md / CLAUDE.md (memory `release-surfaces-readme-claude-md-no-longer-bump`).
- Run `bash scripts/check-doc-currency.sh`, `bash scripts/check-vendor-coupling.sh`, and the full `for t in loomwright/scripts/test-*.sh` loop before declaring done.

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | `loomwright/scripts/test-verify-seam.sh` | YES (already ordered by `requires`) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after Subtask 1)
- **Recommended workers:** 1
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md` |
| 2 | `skills/quality-checklist/SKILL.md`, `skills/error-handling/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Prior churn (postmortem ledger): `CHANGELOG.md` (57 entries), both manifests (56), `RESULT_SCHEMAS.md` (20), `AGENT_GUIDELINES.md` (12) — recurring classes `convention_mismatch` / `quality_gap`, `self_heal_miss` recurred | HIGH | Source: "Prior churn (postmortem ledger)". Reviewers apply the miss-class checklist as a DIFFERENT lens (lesson `d8f68195`): a green `heal_decision: PASS` is not evidence. Specifically re-check: CHANGELOG entry shape (single `**vX.Y.Z — title:**` paragraph, no `##`), `description` version in place in BOTH manifests, the RESULT_SCHEMAS exception blockquote names VERIFY_ENV, AGENT_GUIDELINES count words updated (grep "seven"). |
| `//`-default collapses a legal `null` into missing-key (the canonical `read-rules.sh` self-heal miss) | HIGH | Presence via jq `has()` for all four nullable-required keys; AC8 mutation control proves the check is load-bearing; test both directions (AC2). Lesson `f0d8d600` / memory `nullable-required-field-needs-presence-check`. |
| Contract strings are a TRUST SURFACE: every `start|stop|seed|reset` value and the `non_prod_assert.cmd` member is arbitrary shell that `verify-env.sh` runs via `bash -c` with the caller's full privileges, from a committed project-authored file — the same class as Criterion 14's `cmd:` bullets | MEDIUM | State it explicitly in `## VERIFY_ENV` ("trusted exactly like `package.json` scripts; the executor is the only surface that runs them; never run `verify-env.sh` against a store you have not read"). Item 03 (`/verify`) decides whether the unattended path may invoke `verify-env.sh` at all — out of scope here, but the schema must not imply the strings are inert data. |
| Executor runs a contract string before the non-prod gate (production touched) | HIGH | `assert-non-prod` is called unconditionally at the top of every subcommand in the same process; AC9 test uses a marker-touching `start` string under a failing assertion and asserts the marker is absent. Fail CLOSED with a named reason. |
| macOS bash 3.2 / BSD userland (`timeout` absent, `${empty[@]}` under `set -u`, `stat -f`) | MEDIUM | Poll with a `while`/`sleep 1` loop and a counter — never `timeout`; use `"$@"` not `"${arr[@]}"` on possibly-empty arrays (memory `ead04b14`); no `stat`/`sed -i`/`date -d` GNU-isms; macOS-green ≠ CI-green. |
| `producer \| grep -q` SIGPIPE under `pipefail`; `grep -c … \|\| echo 0` double line | MEDIUM | Memory `bash-grep-pipefail-nul-traps`: capture to a variable then test; never `grep -q` on the right of a pipe under `pipefail`. |
| Root `scripts/check-vendor-coupling.sh` ratchet trips on a `${CLAUDE_PLUGIN_ROOT}` / `~/.claude` mention in a core script COMMENT | MEDIUM | New scripts are core and must carry zero vendor tokens (reader/bootstrap/test precedents all count 0). Word comments neutrally; run the root gate before pushing (memory `run-full-ci-suite-loop-before-push`). |
| Mutation control silently invalid (sed matched nothing ⇒ mutant == original) | MEDIUM | Lesson `fa32a308`: gate every mutant on non-empty + differs-from-original + `bash -n`; report "UNPROVEN" not "ok" when the sed matches nothing (as `test-read-product.sh` case (i) does). |
| `provides` symbol `## VERIFY_ENV` is an H2 in an all-H2 file — token must match the file's convention | LOW | RESULT_SCHEMAS.md uses `## NAME` for every schema (`## PRODUCT_CONTEXT`, `## FLOOR_PROJECTION`); an H2 is the convention, so the token is satisfiable without a malformed doc (memory `provides-token-zero-hit-is-not-enough`). |
| Concurrent writer on this checkout sweeps uncommitted edits | LOW | Single `/automate` run; no other Claude session was found working this repo at brief time (worktrees under `.claude/worktrees/` are idle desktop worktrees). Workers commit per subtask. |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-14-verify-env-contract.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-09-14T05:24:19Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/220
- **Branch:** feature/verify-env-contract
- **Files changed:** 9
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** .agent/verify.json contract shipped — §VERIFY_ENV schema, fail-safe read-verify.sh, propose-only propose-verify.sh (--non-prod never guessed), fail-CLOSED verify-env.sh executor, test-verify-seam.sh 180/180; Phase 4.5 iteration 1 FAIL (HIGH start replay hole + 3 MEDIUM) → fixed 06127c3 → iteration 2 PASS; rubric 5/5; ground_truth 2/2 pass; release v15.73.0. Default until-mergeable dispatch suppressed by the /automate engine (owned inline drain follows).
