# Exploratory QA runs under the verify environment contract

## Status: pending

Source: re-validation of `loomwright/docs/QA_SYSTEM_BLUEPRINT.md` against main `8ec200e` / v17.35.1 (2026-11-09). Sibling of the qa-evolution stories in this folder: `01-qa-session-accounting-is-derived-never-agent-written.md`, `02-qa-findings-reach-a-consumer-propose-from-qa.md`, `03-the-qa-lane-earns-its-cost-on-the-feature-scorecard.md`, `04-verify-runs-inside-the-delivery-loop-in-shadow.md`, `05-verify-can-target-a-pull-requests-preview-deployment.md`, `08-the-qa-blueprint-describes-the-two-lane-qa-system.md`, `operator-run/06-dogfood-qa-accounting-and-verify-on-a-real-app.md` (`00-overview.md` was still being written when this was drafted).

**As the** owner (Vikash), running `/qa-executor` against a project that already declares its verification environment in `.agent/verify.json`,
**I want** the exploratory lane to take its base URL, environment name and start/seed/stop lifecycle from that contract and to run the same fail-closed non-prod assertion `/verify` runs before it sends a single request — and, with no contract, to test only a URL that resolves to loopback or a `*.localhost` host,
**so that** both QA lanes share one environment-safety model and a URL found in `.env` can never be tested on the strength of a hostname pattern.

### Problem (read on main `8ec200e`)

- **Two safety models coexist.** `agents/qa-executor.md` §"Phase 3: DETECT URL" resolves the base URL from `playwright.config.ts` `baseURL`, then `.env` / `.env.local` (`APP_URL`, `BASE_URL`, `FRONTEND_URL`), then stops `needs_human`, `error: "base_url_unresolved: …"`; its step 5 classifies `localhost → "local", *.vercel.app → "preview"`. The only production guard in that mode is the §"Critical Rules" bullet "No production testing: Never run tests against production environments" — prose, with no check behind it. A `*.vercel.app` URL in `.env` is classified `preview` and tested today with no proof it is non-prod (a Vercel production deployment also answers on `*.vercel.app`).
- **`/verify` is mechanized and fail-closed.** `verify-run.sh preflight` (its header comment: "(4) `assert-non-prod` — … fail ⇒ the `env` fail line with the executor's own bracketed reason, exit 1, and `start` is NEVER called") makes exactly one executor call, `verify-env.sh assert-non-prod --repo <repo>`. `verify-env.sh`'s header: "EVERY subcommand calls `gate_non_prod` FIRST, in the SAME process … Nothing is persisted between invocations". The `--verify` phase map skips Phase 3 ("`base_url` is the contract's, through `read-verify.sh`; never detected, never asked"). The exploratory mode never reads the contract at all.
- **`--url` bypasses even the legacy detection.** `commands/qa-executor.md` §"Parameters": "`--url` — Override base URL (default: from playwright.config.ts or .env)". Nothing checks what it points at.
- **The contract has no environment name.** `docs/result-schemas/verify-env.md` lists `start, base_url, health, auth, non_prod_assert, seed, reset, stop, ready_timeout_s, notes` — no name field. `read-verify.sh` emits the whole validated object (`"OK\t" + ($o | tojson)`) and its `check_optional` types only `ready_timeout_s` and `notes`, so an added optional key passes through today but is untyped and undocumented. Sibling story `05` adds an optional `preview: {"environment": "<GitHub deployment environment name>"}` to the same contract for `/verify`'s preview resolution — a different fact (which hosted deployment to resolve), so this story's key must not be called `environment`.
- **`QA_RESULT.environment` is a closed enum nobody validates.** `docs/result-schemas/qa-result.md`: `environment: enum [local, preview, staging] # optional — environment classification from Phase 3`. `scripts/validate-qa-result.py` has no `environment` check (grep, 2026-11-09: 0 hits) and no `error` enum — `error` is a free string, required only when `status=failed`.
- **Phase 3's can't-ask status is inventoried.** `docs/ARCHITECTURE_CONTRACTS.md` §"Question-gate inventory", row "qa-executor URL fallback", names `status: needs_human, error: "base_url_unresolved: {what was tried}"`. Any new Phase 3 stop status must be added to that row.
- **The exploratory lane never starts the app.** `.supervisor/requirements/verify-walkthrough/00-overview.md` §"Verified facts": "it **requires the app to already be running** and never starts it. Phase 2 only installs deps." The contract's `start`/`seed`/`stop` are used by `--verify` mode only (agent §"VERIFY MODE" steps 3, 4, 9).

### Scope

**Part 1: one resolver seam, mechanized and tested.**
- New `loomwright/scripts/qa-env-resolve.sh [--repo <dir>] [--url <candidate>]` — the one place the exploratory lane decides where it may point. It loads the contract through `read-verify.sh` (never re-parses the store), calls the existing `verify-env.sh assert-non-prod --repo <dir>` as the assertion (nothing is extracted from `verify-env.sh`, `verify-run.sh` or `verify-helpers.sh`; all three are unchanged by this story — see Owner decisions for why the seam is a sibling script and not a new subcommand), and never runs a contract shell string or contacts the network itself.
- On success it prints, one per line: `source=contract|legacy`, `base_url=<url>`, `environment=<name>`, `start_declared=true|false`, `seed_declared=true|false`, exit 0. On refusal: nothing on stdout, one bracketed reason token on stderr, exit 1 (a refusal) or 3 (contract present but unreadable).
- Decision table (first matching row wins):

  | contract | `--url` | outcome |
  |---|---|---|
  | readable, assertion passes | absent, or equal to `base_url` (trailing slash ignored) | `source=contract`, the contract's `base_url` |
  | readable, assertion passes | differs from `base_url` | exit 1 `[base_url_conflicts_with_contract]` |
  | readable, assertion fails / no usable member | any | exit 1, the executor's own token verbatim (`[non_prod_assert_failed]` / `[non_prod_assert_empty]`) |
  | present but malformed (reader emits nothing) | any | exit 3 `[verify_store_unreadable]` with the reader's tokens forwarded — **no legacy fallback** |
  | absent | host is loopback or `*.localhost` | `source=legacy`, `environment=local` |
  | absent | any other host | exit 1 `[base_url_not_proven_non_prod]` |
  | absent | absent | exit 1 `[base_url_unresolved]` |

- **Loopback rule:** the authority's HOST component (scheme stripped, userinfo stripped, port stripped, nothing after the first `/`, `?` or `#`) must be `localhost`, a `127.0.0.0/8` literal, `::1` / `[::1]`, or end in `.localhost`. `http://localhost.evil.com`, `http://evil.com/localhost`, `http://localhost@` + a real host (the userinfo trick), `http://192.168.1.5:3000` and `https://x.vercel.app` are all refused.
- **Environment rule:** the contract's `environment_name` (a new OPTIONAL string key, see Part 3) when declared; when absent, `local` if `base_url`'s host passes the loopback rule, else `non_prod` (the one fact the assertion proved). Legacy source is always `local`. `preview` and `staging` are no longer produced by classification; a contract may still declare `environment_name: "preview"` and then that is what is reported.

**Part 2: the agent uses the seam; its command mirror says so.**
- `agents/qa-executor.md` §"Phase 3: DETECT URL" becomes "Phase 3: RESOLVE ENVIRONMENT": step 1 shells to `qa-env-resolve.sh` (passing `--url` when the flag was given); a refusal ends the run with `status: needs_human`, `error: "<token>: <detail>"`, `environment` omitted, and nothing has been sent to any URL. Step 2 (`source=contract`, `start_declared=true`, not already running): `verify-env.sh start` (health polled by the executor; fail ⇒ `needs_human`, `error: "env_start_failed: <reason>"`). Step 3: `verify-env.sh seed` when `seed_declared=true`. Step 4: the existing `curl` liveness check, now against the resolved `base_url`. Phase 3 stays in the NON-SKIPPABLE list; Phase 3.6 is unchanged.
- Teardown: when this run's `start` passed, `verify-env.sh stop` runs before Phase 13's EMIT on every path (completion, `needs_human`, RED-zone exit, timeout). `reset` never runs in this mode — the exploratory lane performs no mutations (V7 unchanged).
- The §"Critical Rules" "No production testing" bullet names its mechanism (Phase 3's resolver: the contract's `non_prod_assert`, or loopback-only without a contract). The §"Error Handling" table gains rows for `non_prod_assert_failed`, `non_prod_assert_empty`, `verify_store_unreadable`, `base_url_conflicts_with_contract`, `base_url_not_proven_non_prod`, `env_start_failed`; the `base_url_unresolved` row is reworded to the new order. `QA_RESULT.environment` is the resolver's `environment` line.
- `commands/qa-executor.md`: the `--url` row states the rule (with a contract it must equal `base_url`; without one, loopback-only); §"Requirements" "Application must be running at detected URL" becomes "running, or started by the contract's `start`"; §"What This Does" step 1 names the resolver.

**Part 3: schemas, inventory, test, fragment.**
- `docs/result-schemas/verify-env.md`: optional `environment_name: string` documented (a human label — `local`, `staging-sandbox`, …; never read by `non_prod_assert`; distinct from story `05`'s `preview.environment`, which names a GitHub deployment environment to resolve); `read-verify.sh` `check_optional` types it (present and not a non-empty string ⇒ `[type_invalid:environment_name]`, MALFORMED); `test-verify-seam.sh` gains that case plus the pass-through case.
- `docs/result-schemas/qa-result.md`: `environment` becomes a string — the contract's `environment_name`, else `local` / `non_prod` as derived; `preview` / `staging` noted as legacy values of old artifacts; the `error` comment lists the Phase 3 tokens.
- `docs/ARCHITECTURE_CONTRACTS.md` §"Question-gate inventory" row "qa-executor URL fallback": the new statuses added beside `base_url_unresolved`; the §"Prompt Token Budgets" `qa-executor` row re-baselined only if `check-token-budget.sh` trips.
- `loomwright/scripts/test-qa-env-resolve.sh` — fixture-driven (contracts under `mktemp -d` as `test-verify-seam.sh` does; the REAL `read-verify.sh` and `verify-env.sh` as siblings; a PATH-stubbed `curl` that logs argv so "zero requests" is a log fact), plus prompt-surface arms in the `test-verify-walkthrough.sh` style.
- `changelog.d/qa-exploratory-env-contract.md`.

## Acceptance Criteria

Every resolver case runs in a `mktemp -d` project with its own `.agent/verify.json` fixture and a PATH stub `curl` whose call log is asserted; no network (`scripts/check-test-hermetic.sh`).

- [ ] **Failing assertion sends nothing:** a contract with `non_prod_assert: {"cmd": "false"}` ⇒ exit 1, empty stdout, stderr carries `[non_prod_assert_failed]`, and the `curl` log is empty. `{"non_prod_assert": {}}` ⇒ `[non_prod_assert_empty]`, same silence. Test: `loomwright/scripts/test-qa-env-resolve.sh`.
- [ ] **Contract wins:** `base_url_matches: "^http://127\\.0\\.0\\.1"`, `base_url: "http://127.0.0.1:8765"`, `environment_name: "fixture-local"` ⇒ exit 0 with `source=contract`, `base_url=http://127.0.0.1:8765`, `environment=fixture-local`, `start_declared` / `seed_declared` matching the fixture's null-ness. Test: `test-qa-env-resolve.sh`.
- [ ] **Environment derived when undeclared:** the same contract without `environment_name` ⇒ `environment=local`; a passing `cmd: true` contract with `base_url: "https://sandbox.example.test"` and no `environment_name` ⇒ `environment=non_prod`. Test: `test-qa-env-resolve.sh`.
- [ ] **Malformed contract never falls back:** a store missing the `seed` key, with `--url http://localhost:3000` also given ⇒ exit 3, empty stdout, stderr carries `[verify_store_unreadable]` and the reader's `[required_key_missing:seed]`; `--url` is NOT accepted. Test: `test-qa-env-resolve.sh`.
- [ ] **`--url` against a contract:** equal to `base_url` (with or without trailing slash) ⇒ accepted as the contract's; any other value ⇒ exit 1 `[base_url_conflicts_with_contract]`. Test: `test-qa-env-resolve.sh`.
- [ ] **Legacy is loopback-only:** no contract; `--url` of `http://localhost:3000`, `http://127.0.0.1:3000`, `http://[::1]:3000`, `http://app.localhost:3000` ⇒ `source=legacy`, `environment=local`; `https://myapp.vercel.app`, `https://staging.example.com`, `http://192.168.1.5:3000`, `http://localhost.evil.com`, `http://evil.com/localhost`, `http://localhost@` + a real host (the userinfo trick) ⇒ exit 1 `[base_url_not_proven_non_prod]`; no `--url` ⇒ exit 1 `[base_url_unresolved]`. Test: `test-qa-env-resolve.sh`.
- [ ] **No contract string is ever run by the resolver:** every shell-string member of a fixture contract is `touch <marker>`; after every resolver case no marker exists (the `test-verify-seam.sh` seam pattern). `cmd` is the one exception and runs only inside `verify-env.sh assert-non-prod`. Test: `test-qa-env-resolve.sh`.
- [ ] **Reader types the new key:** `environment_name: 3` and `environment_name: ""` ⇒ `read-verify.sh` emits nothing, stderr `[type_invalid:environment_name]`; `environment_name: "staging-sandbox"` ⇒ emitted and present in the output object; a store without the key is byte-identical in behaviour to today. Test: `loomwright/scripts/test-verify-seam.sh`.
- [ ] **Mutants each fail a case:** (a) a copy with the loopback check deleted accepts `https://x.vercel.app`; (b) a copy that falls back to legacy on an unreadable contract; (c) a copy that reads `base_url` from the file instead of the reader; (d) a copy that prints `environment=preview` from a hostname pattern. Each is gated on "the mutant differs from the original". Test: `test-qa-env-resolve.sh`.
- [ ] **The prompt names the seam (prompt-surface arms):** `agents/qa-executor.md` Phase 3 names `qa-env-resolve.sh`; its Error Handling table carries every token in Part 2; `verify-env.sh stop` appears in an exploratory-mode teardown step; "`*.vercel.app`" and "preview" no longer appear as a classification; `commands/qa-executor.md`'s `--url` row no longer says "default: from playwright.config.ts or .env" without the rule. Test: `test-qa-env-resolve.sh`.
- [ ] **Verify mode is unaffected in behaviour:** `bash loomwright/scripts/test-verify-walkthrough.sh` passes unchanged; `verify-env.sh`, `verify-run.sh`, `verify-helpers.sh` are identical to main (`git diff --exit-code` guard inside `test-qa-env-resolve.sh`; if story `05` has landed first, "main" already carries its `--base-url` flag and the guard compares against that).
- [ ] **Schemas and inventory agree:** `docs/result-schemas/verify-env.md` documents `environment_name`; `docs/result-schemas/qa-result.md` no longer declares `environment` as `enum [local, preview, staging]`; `docs/ARCHITECTURE_CONTRACTS.md`'s "qa-executor URL fallback" row names every new status; `bash loomwright/scripts/test-result-schemas-split.sh` passes. Test: those commands plus greps listed in the PR body.
- [ ] **Hook unchanged, on purpose:** `scripts/validate-qa-result.py` is byte-identical to main (it validates neither `environment` nor an `error` enum — the `git diff --exit-code` guard). Test: `test-qa-env-resolve.sh`.
- [ ] **Gates:** `bash scripts/check-token-budget.sh` passes (re-baseline the `qa-executor` row to measured + ~10% with its mirror row only if it trips); `bash scripts/check-prompt-history-refs.sh` passes with `loomwright/agents/qa-executor.md` at ≤ 3 and `loomwright/commands/qa-executor.md` at ≤ 1 (the baseline may only go down); `bash scripts/check-version-bump.sh` passes with the fragment.

## Non-goals
- Any change to `--verify` mode, its run dir, `preflight`, evidence lines or `VERIFY_RESULT`.
- Resolving a pull request's preview deployment — story `05`, `/verify` only; the exploratory lane never calls `gh`.
- Loosening L1's "never submit forms during discovery" or running `reset` in the exploratory lane; the V7 carve-out stays `--verify`-only (`skills/verify-walkthrough/SKILL.md` §4).
- A new agent or command; Beads; a `/qa-executor --cheap` profile.
- Changing `propose-verify.sh`: the optional `environment_name` key is hand-added in v1 (PO default below).
- Changing `scripts/validate-qa-result.py` (nothing there to change — verified).
- README / `docs/ARCHITECTURE.md` prose about the QA lanes — story `08` in this folder.
- Re-classifying old artifacts; `preview` / `staging` stay accepted as legacy values in the schema text.
- A dogfood `.agent/verify.json` committed to this repo (it has no app).
- Session-mode (`--plan` / `--scope` / `--continue`) semantics beyond "the resolver runs in every mode that reaches Phase 3".

## Owner decisions
- 2026-11-09 (Vikash, re-validation brief): **Not approved to build — requirements only.** The item passes the owner's test: it fixes a hole in shipped code (a `*.vercel.app` URL in `.env` is classified `preview` and tested with no proof it is non-prod).
- 2026-11-09 (Vikash, in the brief): one environment-safety model for both lanes; with a contract, the exploratory lane takes base URL, environment name and start/seed/stop from it and runs the same fail-closed assertion before any request; a failing assertion ⇒ `needs_human`, `error: non_prod_assert_failed: …`, zero requests; legacy `playwright.config.ts` / `.env` detection only without a contract and only for loopback / `*.localhost`; `QA_RESULT.environment` is the contract's environment name.
- PO default, pending owner review (**contract change — the environment name**): `.agent/verify.json` has no name field today, so "the contract's environment name" needs one. Default: a new OPTIONAL `environment_name: string` key in VERIFY_ENV, typed by the reader, passed through, never read by `non_prod_assert`; when absent `QA_RESULT.environment` is derived as `local` (loopback host) or `non_prod` (anything else the assertion proved). It is deliberately not called `environment`: story `05` adds `preview.environment` (a GitHub deployment environment name to resolve), a different fact. Alternatives the owner may prefer: make the key REQUIRED (every existing contract then needs an edit); derive always (no new key, no free label); or reuse `05`'s `preview.environment` as the reported name when a run targets a preview and derive otherwise.
- PO default, pending owner review (where the seam lives): a new sibling script `qa-env-resolve.sh` that calls `verify-env.sh assert-non-prod`, rather than a new `verify-env.sh` subcommand (every `verify-env.sh` subcommand gates on a READABLE contract first — the no-contract legacy path cannot live there without breaking that shape) or `verify-run.sh preflight` (it needs a ticket and mints a run dir). No helper is extracted; the assertion is already the shared one.
- PO default, pending owner review (malformed contract): present-but-unreadable ⇒ stop with `verify_store_unreadable`, never fall back to legacy detection — a typo in the contract must not silently change the safety model.
- PO default, pending owner review (`--url`): with a contract it must equal `base_url`; without one it is the legacy candidate and loopback-only. This closes the `--url https://prod…` bypass.
- PO default, pending owner review (lifecycle): `start` + `seed` when declared, before discovery; `stop` on every path when this run started the app; `reset` never (no mutations in this lane).
- PO default, pending owner review (`preview`): retired as a classification-produced value; the schema keeps it as a legacy value; no validator change.
- PO default, pending owner review (order against `05`): no dependency either way. Both add one optional key through `read-verify.sh`'s `check_optional` and one case to `test-verify-seam.sh`; whichever lands second rebases a few lines. If the owner wants one PR, `05` + `07` share enough files to merge as Parts.

## Priority: MVP
**Rationale:** a safety hole in shipped code: today the exploratory lane will test any URL it finds in `.env`, and `--url` accepts anything. The mechanized assertion already exists in the other lane; this story makes it the only one.

## Assumptions
- right-size (run 2026-11-09, `bash loomwright/scripts/automate-helpers.sh right-size <file>`, defaults small ≤ 3 / large > 30): `qa-evolution/07-exploratory-qa-runs-under-the-verify-environment-contract: ok (11 files, 14 scope items, 14 criteria)`.
- `read-verify.sh` passes an unknown top-level key through (`"OK\t" + ($o | tojson)`; its jq program has no allowlist of top-level keys), so `environment_name` reaches the resolver after a one-line `check_optional` type check; no bootstrap change is needed for v1.
- `scripts/validate-qa-result.py` validates neither `environment` nor an `error` enum (grep on 2026-11-09), so the SubagentStop hook needs no change.
- `verify-env.sh assert-non-prod --repo <dir>` is callable without a run dir — `preflight` already calls it that way — so the exploratory lane reuses it as-is.
- Phase 2's `npm install` contacts the package registry, not the app; the `curl` liveness check and `verify-env.sh start`'s health poll are the first requests to the app, and both come after the resolver.
- Token budget: `qa-executor` is at measured 48483 against budget 53332 (`docs/prompt-token-budgets.json`), about 4.8k tokens of headroom; the Phase 3 rewrite should fit, else re-baseline per CLAUDE.md.
- `.agent/companions.json` adds `prompt-token-budgets.json` and `ARCHITECTURE_CONTRACTS.md` for any `loomwright/agents/*.md` edit; both are listed below anyway because the inventory row is a real edit.
- New `loomwright/scripts/test-*.sh` files are picked up by the CI and `ci-local.sh` globs with no registration.
- `scripts/verify-fixture-app.py` (GET `/health` 200, request log on stderr) plus a minimal `playwright.config.ts` is enough for the running-system proofs.
- Shared files with siblings (read from their `## Touches` on 2026-11-09): `agents/qa-executor.md` is also edited by `01` (Phase 1 session steps) and `05` (VERIFY MODE steps 3/5); `read-verify.sh`, `test-verify-seam.sh` and `docs/result-schemas/verify-env.md` also by `05`; `docs/result-schemas/qa-result.md` also by `03`; `ARCHITECTURE_CONTRACTS.md` and `prompt-token-budgets.json` by `01`, `03`, `04`, `05`, `08`. Different sections in every case; a wave serialises them.

## Dependencies
- Depends on: none — `verify-walkthrough` 01–07 are done on main (`verify-env.sh`, `read-verify.sh`, `verify-run.sh`, `verify-fixture-app.py` exist).
- Blocks: nothing hard. `08-the-qa-blueprint-describes-the-two-lane-qa-system.md` describes this item as planned, by filename.

## Risks
- **A contract with a non-null `start` now has its app started by the exploratory lane** (before: required running). Mitigation: `start` runs only after the assertion passed in this process; `already_started` is handled by the executor; `stop` runs on every path.
- **Teams testing a LAN or staging host without a contract are refused.** Intentional; the refusal names the bootstrap (`propose-verify.sh --non-prod … --confirm`) exactly as `preflight` does.
- **`environment` becomes a free string.** Consumers (`03`'s `qa_result` scorecard row) must not assume the old enum. Mitigation: the schema note and the derived values `local` / `non_prod`.
- **Two optional keys land in one contract from two stories** (`environment_name` here, `preview.environment` in `05`). Mitigation: distinct names, each documented beside the other in `verify-env.md`; the alternative "one key" is an owner decision above.
- **Prompt growth.** Mitigation: the Error Handling rows are one line each; re-baseline only if the gate trips.
- **Five sibling stories share `ARCHITECTURE_CONTRACTS.md` / `prompt-token-budgets.json`, and three share `agents/qa-executor.md` or the verify seam files.** They serialise in a wave; none blocks another.

## Validation (must pass before merge)
1. **Static — resolver suite:** `bash loomwright/scripts/test-qa-env-resolve.sh` passes, including the four mutants, the empty `curl` log on every refusal, the host-parsing adversarial cases, the no-marker seam check, the `git diff --exit-code` guards on the three verify scripts and `validate-qa-result.py`, and the prompt-surface arms.
2. **Static — seam and walkthrough suites:** `bash loomwright/scripts/test-verify-seam.sh` passes with the `environment_name` type cases; `bash loomwright/scripts/test-verify-walkthrough.sh` passes unchanged.
3. **Static — repo gates:** `bash scripts/ci-local.sh --affected` passes (including `check-test-hermetic.sh`, `check-token-budget.sh`, `check-prompt-history-refs.sh`, `test-result-schemas-split.sh`, `check-doc-currency.sh`); `bash scripts/check-version-bump.sh` passes with `changelog.d/qa-exploratory-env-contract.md`.
4. **Running system — the contract path:** in a scratch project with `.agent/verify.json` (`start` = `python3 <plugin>/scripts/verify-fixture-app.py --port 8765`, `base_url` `http://127.0.0.1:8765`, `health` `/health`, `environment_name: "fixture-local"`, a passing `base_url_matches`) and a minimal `playwright.config.ts`, `/qa-executor --depth smoke` emits `QA_RESULT` with `environment: fixture-local`; the fixture's stderr request log shows its first request after the Phase 3 checkpoint line, and the fixture process is gone after EMIT (`stop` ran).
5. **Running system — the refusal path:** the same project with the app pre-started by hand (`start: null`) and `non_prod_assert: {"cmd": "false"}`: `/qa-executor` emits `status: needs_human`, `error: "non_prod_assert_failed: …"`, no `environment`, and the fixture's request log is empty for the whole run.
6. **Running system — legacy refusal:** the same project with `.agent/verify.json` removed and `.env` `APP_URL=https://example.vercel.app`: `status: needs_human`, `error: "base_url_not_proven_non_prod: …"`, and the session transcript holds no `curl`, `page.goto` or `npx playwright` invocation naming that host.

## Depends on
none

## Touches
loomwright/agents/qa-executor.md
loomwright/commands/qa-executor.md
loomwright/scripts/qa-env-resolve.sh
loomwright/scripts/test-qa-env-resolve.sh
loomwright/scripts/read-verify.sh
loomwright/scripts/test-verify-seam.sh
loomwright/docs/result-schemas/verify-env.md
loomwright/docs/result-schemas/qa-result.md
loomwright/docs/ARCHITECTURE_CONTRACTS.md
loomwright/docs/prompt-token-budgets.json
changelog.d/qa-exploratory-env-contract.md
