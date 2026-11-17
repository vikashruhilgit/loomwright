# Supervisor-Ready Brief: qa-split 04 — the run is model-free, the evidence is runner-written, the verdict is derived from it

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** dirty (2 untracked dirs: `reports/`, `research_notes/`, unrelated), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 2 (untracked dirs; 4 linked worktrees on unrelated branches)
- **Source requirement:** .supervisor/requirements/qa-split/04-run-and-verdict-model-free-with-evidence.md
- **Base commit:** bb6ce2b5ce07e7a5e1d27baadbd5254ce7352018

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash CLI + Node ≥ 18 ESM, standard library only, as items 02/03 (`selvedge/lib/*.mjs`, `selvedge/lib/runner/*.mjs`); Playwright resolved at run time by the existing `resolvePlaywright` |
| 2 | Dependency Availability | GO | No new dependency: zip reading/writing for `--trace` uses `node:zlib` (Design decision 2); Playwright already resolved from `SELVEDGE_PLAYWRIGHT_MODULE` / the target repo |
| 3 | Architecture Fit | GO | Implements 00-plan D6 (hash check, no model in the run), D7 (PASS rule, stable wait, exit precedence), D9 (`evidence_class`), D10, D13 (local redacted evidence) on top of item 02's guard (`openGuardedContext`) and item 03's run folders (`plan-runs.mjs`: `readRunsLog`, `runsLogPath`, `RUN_FILES`) |
| 4 | Scope vs Supervisor Capability | CAUTION | ~20 files and well over 800 changed lines → `context-bound` split into 3 ordered subtasks |
| 5 | Hard Blockers | CAUTION | Item 03 is merged (#924). Files outside the item's Touches are needed (`selvedge/bin/selvedge` dispatch, `selvedge/lib/env-config.mjs` `REASONS`, `selvedge/lib/env.mjs` for the `env init` ignore line the requirement itself names, `selvedge/lib/snapshot.mjs` whose step executor moves under `lib/runner/`, README and the three release files) — asked once at Phase 6 (`LP-SCOPE`) |

**Overall Verdict:** CAUTION

## Task
**Goal:** Add `selvedge run <run-dir>` (refuses a changed or already-run plan, executes the frozen `plan.json` through the guarded browser with no model call, writes every evidence line itself, `--replay <frozen-run-dir>` for regression, `--trace` with secrets stripped) and `selvedge verdict <run-dir>` (derives PASS / FAIL / BLOCKED / NOT_VERIFIABLE per criterion from `evidence.jsonl` + `plan.json` only, writes `verdict.json`, exits by D7 precedence), and log one `runs.jsonl` line per run.

**Problem Statement:**
Selvedge's owner (and later item 06's PR comment) needs a verdict no model wrote, because if the model writes the evidence or the summary, the model is the judge.
Currently, item 03 freezes a sha256-hashed `plan.json` but nothing executes it, so there is no evidence and no verdict. This leaves criteria unverified, and a verifier that "runs" a plan through a model could drift from it unnoticed.
Success looks like: `run` refuses a plan whose hash changed, executes only typed steps via Playwright with zero planner calls, writes `evidence.jsonl` itself, and `verdict` turns those lines into per-criterion verdicts with the read value, the expected value and a named reason — each proven by a test in `selvedge/tests/` against the local fixture app.

## Design decisions
- decision: How the run code splits into modules, and where the step executor lives (T2 — new modules under `selvedge/lib/runner/` and `selvedge/lib/verdict.mjs`)
  chosen: `lib/runner/steps.mjs` (the plan-step executor moved out of `lib/snapshot.mjs` — `locate`, `navigate`, `runStep` — extended with `read` and the `expect` matcher; `snapshot.mjs` imports it, so there is one executor), `lib/runner/execute.mjs` (one criterion in a fresh guarded context: steps, stable wait, stuck-screen detection, screenshot, evidence lines), `lib/runner/evidence.mjs` (`evidence.jsonl` writer/reader; every resolved `{{NAME}}` value written back as `{{NAME}}` through the existing `redactValues`), `lib/runner/trace-redact.mjs` (Design decision 2), `lib/runner/run.mjs` (the `run` CLI: hash check, `already_run`, `--replay`, hooks, budget, `runs.jsonl` line), `lib/verdict.mjs` (`deriveVerdict` + the `verdict` CLI)
  rejected: export `locate`/`runStep` from `snapshot.mjs` in place and add `read`/`expect` there — fits the CLAUDE.md stack: partial (`snapshot.mjs` is 521 lines, at the §"Module layout" threshold, so the new `read`/`expect` responsibility needs a CREATE home). The runner still imports `redactValues`/`encodedForms` and `STEP_TIMEOUT_MS` from `snapshot.mjs` unchanged (its `isMain` guard keeps an import side-effect free), so no helper is copied
  rejected: a second executor inside `lib/runner/` — fits the stack: no (two executors drift; item 03's validator was kept single for the same reason)
  evidence: item 03's Design decision 4 `revisit when: item 04 needs the prefix executor for \`run\` — it may move the executor half of \`snapshot.mjs\` into \`selvedge/lib/runner/\` and import \`validateSteps\` unchanged`; `wc -l selvedge/lib/snapshot.mjs` → 521; the requirement's Touches names `selvedge/lib/runner/**` and `selvedge/lib/verdict*`
  revisit when: a second target adapter (D17) needs its own executor — then `steps.mjs` becomes the web adapter's
  status: confirmed
- decision: How `--trace` strips `Cookie`, `Set-Cookie`, `Authorization` values and resolved `{{NAME}}` values from Playwright's trace zip (T2 — `lib/runner/trace-redact.mjs`)
  chosen: platform — a small zip reader/writer on `node:zlib` (`inflateRawSync` for deflate entries, stored entries copied; output written with method 0 "stored" and a table CRC-32, so no deflater is needed and Node 18 works): every text entry (`*.trace`, `*.network`, `resources/*` that decode as UTF-8) has the three header values replaced by `[redacted]`, every cookie value seen in any `Cookie`/`Set-Cookie` header of the trace replaced everywhere, and every resolved `{{NAME}}` value replaced via `redactValues`; a zip it cannot parse (zip64, encryption, an unknown method) is deleted and the run reports `trace: dropped (<why>)`, never kept unredacted
  rejected: a zip dependency (e.g. `jszip`) — already in the lockfile or manifest: no (`selvedge/` has no `package.json`); blast radius: no
  rejected: the `zip`/`unzip` command-line tools — fits the stack: partial (the CLI promises bash 3.2 + BSD/GNU userland only, and `zip` is absent from many CI images); test cost: partial
  evidence: repo — `selvedge/bin/selvedge` header `Runs on user machines, so it needs nothing beyond bash 3.2 + BSD/GNU userland: no jq`; `git ls-files selvedge | grep -c package.json` → 0; Node docs: `zlib.inflateRawSync` is in Node 18, `zlib.crc32` only from Node 20.15/22.2 (hence the table CRC-32)
  revisit when: Playwright gains a built-in header-redaction option for traces
  status: confirmed
- decision: Who writes `verdict.json` and the `runs.jsonl` run line (T2 — `lib/verdict.mjs`, `lib/runner/run.mjs`)
  chosen: `run` executes, closes `evidence.jsonl`, then calls `deriveVerdict(runDir)` from `lib/verdict.mjs`, which reads `evidence.jsonl` + `plan.json` from disk (never in-memory runner state) for every verdict value, writes `verdict.json`, and `run` appends the one `runs.jsonl` line from that result and exits with its exit code; `selvedge verdict <run-dir>` re-derives the same file from disk (idempotent, appends nothing). `prior_revisions` is the only field read from `runs.jsonl` (earlier revisions' run lines); it never changes a criterion's verdict
  rejected: the runner decides verdicts itself and `verdict` only formats — fits the stack: no (the requirement's "`verdict` reads only those lines")
  rejected: `verdict` appends the `runs.jsonl` line — test cost: partial (re-running `verdict` would add a second line for one run, breaking "exactly one line per run")
  evidence: requirement Design: "`selvedge verdict <run-dir>`: reads `evidence.jsonl` + `plan.json` only"; "`runs.jsonl` gains exactly one line per run"; item 03 `plan-runs.mjs` header `Item 04 appends its own \`event: "run"\` lines and reuses nextPlanRevision / readRunsLog / runsLogPath`
  revisit when: item 06's adapter needs `verdict` without a local run (a CI artifact) — then the run line moves to an explicit `--log` flag
  status: confirmed
- decision: How "network idle + a stable DOM" is waited for after an action (T5 — Playwright has a `networkidle` load state)
  chosen: hand-written in `execute.mjs`: an in-flight request counter on `page.on('request'|'requestfinished'|'requestfailed')`, idle = 0 in flight for 500 ms; then `page.content()` read twice 500 ms apart until two equal reads; both capped by `STABLE_TIMEOUT_MS` (default 5000); the expect's read is then re-run once
  rejected: `page.waitForLoadState('networkidle')` — test cost: no (it resolves immediately once the page has loaded, so a fetch started by a later click is not waited for)
  evidence: Playwright API docs for `page.waitForLoadState`: "The promise resolves immediately if the page already reached the required load state" (Context7 not consulted; the doc sentence is the project's pinned 1.65.1 behaviour); the requirement cites "WebTestBench's async-loading false FAILs"
  revisit when: Playwright adds a post-action network-idle wait
  status: confirmed
- decision: How `run` runs an approved `seed`/`reset` hook (T2 — inside `lib/runner/run.mjs`)
  chosen: spawn this CLI's own `selvedge env hook reset` then `env hook seed` (each only when `loadConfig().config.hooks` names it), so the approval check, the remote-origin refusal and the exit codes stay in `env.mjs`'s one `cmdHook`; a hook that is present but unapproved (exit 2) makes every criterion BLOCKED `env_hooks_unapproved` (fail closed); with neither hook, `data_state: unmanaged` and `plan_time_actions` from `freeze.json`
  rejected: export and call `cmdHook` in-process — blast radius: no (`env.mjs` refactor for a second caller), reversibility: partial
  evidence: `selvedge/lib/env.mjs` `function cmdHook(args) {` checks `approvalState` and `env_hooks_remote_origin` before `spawnSync('bash', ['-c', config.hooks[name]]`; `selvedge/docs/evidence/gate-scopes.md` `### Hand-off to item 04` item 2
  revisit when: item 05's `auth_setup` hook needs its output captured (storageState) — then a shared in-process hook runner
  status: confirmed

## Acceptance Criteria

Verdict, vocabulary and schema (subtask 1 — no browser; synthetic `evidence.jsonl` + `plan.json` fixtures):
- [ ] AC1 — Given `REASONS` in `selvedge/lib/env-config.mjs`, then it gains exactly `step_failed`, `stuck_screen`, `budget_exceeded`, `run_interrupted` (BLOCKED), `no_value_read`, `material_assumption` (NOT_VERIFIABLE), `plan_modified`, `already_run`, `not_frozen`, `evidence_missing` (usage); `selvedge/README.md`'s reasons table gains one row each; `test-env.sh`'s closed-list arm and README-sync arm pass with the new set; and a grep arm in each new test fails when `lib/verdict.mjs` or a new `lib/runner/*.mjs` names a reason as a string literal.
- [ ] AC2 — Given synthetic evidence for criteria with verdicts {PASS, NOT_VERIFIABLE, BLOCKED}, when `selvedge verdict <run-dir>` runs, then it exits 2; with a FAIL added, exit 1; with only PASS + NOT_VERIFIABLE, exit 3; with only PASS, exit 0.
- [ ] AC3 — Given a criterion whose final `read` recorded an empty value (`""` or `null`), when `verdict` runs, then that criterion is `NOT_VERIFIABLE` with reason `no_value_read` — never PASS, even when the plan's `expect` is `equals ""`.
- [ ] AC4 — Given a criterion whose final `expect` failed after the stable wait, when `verdict` runs, then it is `FAIL` and its `verdict.json` entry carries both `read_value` and `expected` (plus `matched: false`).
- [ ] AC5 — Given a criterion whose `expect` held but whose plan entry has an `unverified_assumptions` item with `material: true`, when `verdict` runs, then it is `NOT_VERIFIABLE` `material_assumption` and the entry carries the assumption text — never PASS.
- [ ] AC6 — Given `runs.jsonl` holding a revision-1 `event: "run"` line with `verdict: "FAIL"` for the same `criteria_sha256`, when `verdict` runs on the revision-2 folder, then `verdict.json` carries `plan_revision: 2` and `prior_revisions: [{revision: 1, verdict: "FAIL"}]` (one entry per earlier revision, first one first; a replay line is not a revision's own run).
- [ ] AC7 — Given any `verdict` run, then `verdict.json` holds `schema_version`, `target`, `plan_sha256`, `playwright_version`, `plan_revision`, `prior_revisions`, `replay_of`, `data_state`, `hooks_run`, `plan_time_actions` (when `data_state` is `unmanaged`) and per criterion `verdict`, `evidence_class` (`structured-read`), `read_value`, `matched`, `expected`, `reason`, `failed_step`, `interpretation`, `unverified_assumptions`, `steps` (a step summary); the `evidence.jsonl` line kinds are the frozen `EVIDENCE_KINDS` in `selvedge/lib/runner/evidence.mjs`, whose `readEvidence` is what `deriveVerdict` reads through; `selvedge/schemas/verdict.schema.json` (draft 2020-12, `additionalProperties: false`) declares exactly these keys; and a test asserts the schema's `verdict` and `evidence_class` enums equal the frozen `VERDICTS` / `EVIDENCE_CLASSES` in `lib/verdict.mjs`.
- [ ] AC8 — Given a run folder with no `evidence.jsonl`, when `verdict` runs, then exit 2 `evidence_missing`; given evidence with no end line for a planned criterion (an interrupted run), then that criterion is `BLOCKED` `run_interrupted`.

The runner (subtask 2 — real Chromium through item 02's guard against `selvedge/tests/fixtures/app-server.mjs`; "no browser launched" is proven by a recording stub Playwright module set as `SELVEDGE_PLAYWRIGHT_MODULE` whose `chromium.launch` writes a marker file):
- [ ] AC9 — Given a frozen run folder, when one byte of `plan.json` is edited and `selvedge run <run-dir>` runs, then it exits 2 with `plan_modified` on stderr, no `evidence.jsonl` is created and no browser is launched; given a folder with no `plan.sha256`, exit 2 `not_frozen`.
- [ ] AC10 — Given a run folder that already holds `evidence.jsonl`, when `run` runs again, then exit 2 `already_run`, no browser launched, and no file in the folder changes.
- [ ] AC11 — Given a fixture page where a click starts a fetch the server answers after 1.5 s and only then shows the value, when the criterion's plan reads it right after the click and expects it, then the verdict is `PASS` (stable wait + one re-read), and its evidence `expect` line records `stable_wait: true`.
- [ ] AC12 — Given a fixture page showing a genuinely wrong value, when `run` runs, then exit 1 and `verdict.json` carries `FAIL` with `read_value` and `expected` both present (after the stable wait).
- [ ] AC13 — Given a plan whose step 2 (0-based index) clicks a locator that matches nothing, or a click on a hidden or covered element, when `run` runs, then the criterion is `BLOCKED` `step_failed` with `failed_step: 2` (not FAIL) and the remaining criteria still run; given a plan whose `read` locator resolves but yields an empty text, then `NOT_VERIFIABLE` `no_value_read` (the end-to-end form of AC3).
- [ ] AC14 — Given a plan with three consecutive action steps on a control that changes nothing (the fixture's dead button), when `run` runs, then the criterion is `BLOCKED` `stuck_screen` (N = `STUCK_SCREEN_ACTIONS`, 3, identical page snapshots after consecutive actions).
- [ ] AC15 — Given a `negative` criterion (baseline `read` of the fixture's side-effect counter, an action, `read`, `expect changed_from false`) whose counter goes from 0 to 1, when `run` runs, then it is `FAIL`.
- [ ] AC16 — Given any run, then `evidence.jsonl` holds a `run_start` line, one line per executed step (`criterion`, `step` index, `type`, `locator`, `outcome`, `value`, `duration_ms`), one `criterion_end` line per criterion and a `run_end` line; a `fill` whose value is `{{SHOP_USER}}` is written as `{{SHOP_USER}}` in every line (the page received the resolved value); each criterion leaves one end-state screenshot `screenshots/<criterion-id>.png`; each criterion runs in a fresh context (a cookie set by criterion 1 is absent in criterion 2).
- [ ] AC17 — Given `SELVEDGE_PLANNER` set to a recording shim and a PATH-stub `claude` that records its calls, when `run` (and `run --replay` in AC22) runs, then both record zero calls.
- [ ] AC18 — Given two runs, then `.selvedge/runs.jsonl` gains exactly one `event: "run"` line per run with `ts`, `run_id`, `entry` (`session` by default; `ci` / `loomwright` from `SELVEDGE_ENTRY`; any other value is a usage error), `counts` per verdict, `verdict`, `planner_tokens`, `duration_ms`, `plan_sha256`, `criteria_sha256`, `plan_revision`, `replay_of`; re-running `selvedge verdict` on the folder adds no line.
- [ ] AC19 — Given `SELVEDGE_RUN_BUDGET_MS` small enough that the first criterion spends it, when `run` runs, then every remaining criterion is `BLOCKED` `budget_exceeded` (not started, no browser context for it); given `freeze.json` planner tokens above `SELVEDGE_PLANNER_TOKEN_BUDGET`, every criterion is `BLOCKED` `budget_exceeded` and no browser launches.
- [ ] AC20 — Given no `seed`/`reset` hook in `selvedge.json`, when `run` runs, then `verdict.json` has `data_state: "unmanaged"` and `plan_time_actions` equal to `freeze.json`'s; given an approved `reset` hook (writing a marker file), it runs before the first browser launch and `data_state` is `managed` with `hooks_run: ["reset"]`; given a `reset` hook not approved, every criterion is `BLOCKED` `env_hooks_unapproved` and no browser launches.
- [ ] AC21 — Given the modal fixture plan frozen by `tests/fixtures/stub-planner.sh` mode `modal` (item 03's hand-off: open the cart, fill Quantity 2, read the `total` test id, expect `"12"`), when `run` runs on that folder, then its verdict is `PASS` (closes `selvedge/docs/evidence/gate-scopes.md` `### Hand-off to item 04` item 1; AC20 closes item 2).

Replay, trace, ignore line and release (subtask 3):
- [ ] AC22 — Given a frozen run that PASSed, when `selvedge run --replay <frozen-run-dir>` runs against the same app, then it creates a new run folder whose `plan.json` is byte-identical (same `plan_sha256`), `verdict.json` and the `runs.jsonl` line carry `replay_of: <frozen run id>` and the unchanged `plan_revision`, the planner shims record zero calls, and the verdict is PASS again.
- [ ] AC23 — Given the fixture app renames the "Open cart" button's label (a control request to the fixture server), when `run --replay` of the modal folder runs, then the criterion is `BLOCKED` `step_failed` naming the click's step index — not PASS, and the replayed `plan.json` still holds the original locator.
- [ ] AC24 — Given a frozen folder whose `plan.json` was edited, when `run --replay` runs, then exit 2 `plan_modified` and no new run folder is left behind; given `plan.json` and `plan.sha256` both edited consistently, it still exits 2 `plan_modified` (checked against the `plan_sha256` of that run's `event: "freeze"` line in `runs.jsonl`).
- [ ] AC25 — Given a fixture page that sets a cookie (and does not print it), when `run --trace` runs, then the kept `trace.zip`, unzipped, contains no occurrence of the cookie value and no resolved `{{NAME}}` value, and `Cookie`/`Set-Cookie`/`Authorization` header values read `[redacted]`; without `--trace` no trace file is written.
- [ ] AC26 — Given a repo with no `.gitignore` line for `.selvedge/`, when `selvedge env init` runs, then `.gitignore` gains the line `.selvedge/` (created if absent, never duplicated on a re-run, and written first — before the `selvedge.json` existence check and the port detection — so it is added even when `selvedge.json` already exists or init then fails `port_required`; init's exit code is unchanged by it).
- [ ] AC27 — `selvedge/README.md` documents `run` (`--replay`, `--trace`), `verdict`, the run-folder evidence files, the `evidence.jsonl` line kinds, `verdict.json`, the `runs.jsonl` run line, `SELVEDGE_ENTRY`, `SELVEDGE_RUN_BUDGET_MS`, the stable-wait rule and exit precedence; selvedge is released as 0.4.0 (`selvedge/.claude-plugin/plugin.json`, the marketplace selvedge entry and a `## 0.4.0 — <date>` CHANGELOG heading together; both `description`s updated in place to drop "running a plan arrives in later releases" and name `run`/`verdict`, no version string); `bash selvedge/tests/run.sh` passes.

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

(Applied here: the README names no selvedge version; `test-env.sh`'s closed-list arm label keeps deriving its count from `want.length`; the README reasons table is updated in the same subtask as `REASONS` and stays pinned by the README-sync arm; the schema enums are pinned equal to the frozen sets in `lib/verdict.mjs`.)

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| verdict + vocabulary + evidence reader (S1) | `selvedge/bin/selvedge` (118), `selvedge/lib/env-config.mjs` (309), `selvedge/lib/snapshot.mjs` (521 — one-line `OUTCOMES.step_failed` → `REASONS.step_failed`), `selvedge/tests/test-env.sh` (397), `selvedge/README.md` (484) | `selvedge/lib/verdict.mjs`, `selvedge/lib/runner/evidence.mjs` (reader + `EVIDENCE_KINDS`), `selvedge/schemas/verdict.schema.json`, `selvedge/tests/test-verdict.sh` | HIGH |
| runner (S2) | `selvedge/bin/selvedge` (118), `selvedge/lib/snapshot.mjs` (521), `selvedge/tests/fixtures/app-server.mjs` (181), `selvedge/lib/runner/evidence.mjs` (created by S1; S2 adds the writer) | `selvedge/lib/runner/run.mjs`, `selvedge/lib/runner/steps.mjs`, `selvedge/lib/runner/execute.mjs`, `selvedge/tests/fixtures/stub-playwright.mjs`, `selvedge/tests/test-run.sh` | HIGH |
| replay, trace, ignore line, docs, release (S3) | `selvedge/lib/runner/run.mjs` (created by S2), `selvedge/lib/runner/execute.mjs` (created by S2), `selvedge/lib/env.mjs` (328), `selvedge/tests/test-env.sh` (397), `selvedge/tests/fixtures/app-server.mjs` (181), `selvedge/README.md` (484), `selvedge/CHANGELOG.md` (81), `selvedge/.claude-plugin/plugin.json` (15), `.claude-plugin/marketplace.json` (140) | `selvedge/lib/runner/trace-redact.mjs`, `selvedge/tests/test-replay.sh` | HIGH |

**Module layout (one home per responsibility):**
- verdict derivation (`deriveVerdict(runDir)`, frozen `VERDICTS` = `PASS`/`FAIL`/`BLOCKED`/`NOT_VERIFIABLE` and `EVIDENCE_CLASSES` = `structured-read`/`in-process-assert`/`model-judged`, D7 precedence `exitCodeFor`, `prior_revisions` from `readRunsLog`) and the `verdict` CLI → `selvedge/lib/verdict.mjs` (CREATE)
- verdict.json shape → `selvedge/schemas/verdict.schema.json` (CREATE)
- plan-step executor (`locate`, `navigate`, `runStep` moved from `snapshot.mjs`; new `readValue` and `expectMatches` for `read`/`expect`) → `selvedge/lib/runner/steps.mjs` (CREATE). `selvedge/lib/snapshot.mjs` (521 — at the threshold) only loses code: it imports the executor back and gains no responsibility
- one criterion in a fresh guarded context (steps, stable wait, stuck-screen detection, screenshot) → `selvedge/lib/runner/execute.mjs` (CREATE; S3 adds the `--trace` start/stop around the context)
- `evidence.jsonl` lines → `selvedge/lib/runner/evidence.mjs` (CREATE in S1 with the frozen `EVIDENCE_KINDS` and `readEvidence`, which `verdict.mjs` imports; S2 adds `appendEvidence`, the only writer, with `{{NAME}}` redaction)
- the `run` CLI (hash check, `not_frozen`, `already_run`, hooks, budget, `--replay`, `runs.jsonl` run line) → `selvedge/lib/runner/run.mjs` (CREATE in S2, extended in S3)
- trace zip redaction → `selvedge/lib/runner/trace-redact.mjs` (CREATE)
- new reason values → the existing `REASONS` in `selvedge/lib/env-config.mjs` (309 — the one closed list: `Every emitter imports a value from here; no reason is a string literal`)
- dispatch → `selvedge/bin/selvedge` (118 — one `case` arm per command: `run` execs `lib/runner/run.mjs`, `verdict` execs `lib/verdict.mjs`)
- the `env init` ignore line → `selvedge/lib/env.mjs` (328 — `cmdInit`, the only writer of a new target repo's files)
- new fixture pages (slow fetch, wrong value, empty value, dead button, side-effect counter, silent cookie, a label-rename control endpoint) → `selvedge/tests/fixtures/app-server.mjs` (181 — the one fixture app; appending keeps one server per test file)
- launch-recording stub Playwright → `selvedge/tests/fixtures/stub-playwright.mjs` (CREATE; not named `test-*`)
- tests: `test-verdict.sh` (S1), `test-run.sh` (S2), `test-replay.sh` (S3) — each new, none extends a ≥ 500-line test file
- No helper is copied in 2+ siblings: run-folder paths and `runs.jsonl` come from `selvedge/lib/plan-runs.mjs` (`RUN_FILES`, `readRunsLog`, `runsLogPath`, `prettyJson`, imported, never copied); `redactValues`/`encodedForms` from `snapshot.mjs`; `canonicalJson` from `env-approvals.mjs`; `isMain`/`parseCliArgs`/`UsageError` from `env-config.mjs`.

> **Validator-owned surfaces:** `selvedge/tests/run.sh` globs only top-level `selvedge/tests/test-*.sh`, so `fixtures/stub-playwright.mjs` must not be named `test-*`. `scripts/check-locale-prefix.sh` scans every tracked `*.sh` (new: `test-verdict.sh`, `test-run.sh`, `test-replay.sh`). `scripts/validate-version.sh` checks the marketplace selvedge entry against `selvedge/.claude-plugin/plugin.json`; `scripts/check-doc-currency.sh` scans `.claude-plugin/marketplace.json`. `selvedge/tests/check-release.sh` checks the CHANGELOG top heading equals `plugin.json` `version`. `selvedge/tests/test-env.sh`'s README-sync arm scans every README row shaped `| \`<lowercase_name>\` |`.

### File Overlap Detection

| Group A | Group B | Overlapping Files | Serialization Required |
|---------|---------|-------------------|----------------------|
| S1 | S2 | `selvedge/bin/selvedge` | YES — ordered by `requires` (S2 reachable from S1) |
| S1 | S3 | `selvedge/tests/test-env.sh`, `selvedge/README.md` | YES — S3 reachable from S1 |
| S1 | S2 | `selvedge/lib/runner/evidence.mjs`, `selvedge/lib/snapshot.mjs` | YES — S2 reachable from S1 |
| S2 | S3 | `selvedge/lib/runner/run.mjs`, `selvedge/lib/runner/execute.mjs`, `selvedge/tests/fixtures/app-server.mjs` | YES — S3 requires S2 |

## Touched-file invariants

> Grounded at base `bb6ce2b5ce07e7a5e1d27baadbd5254ce7352018`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`selvedge/bin/selvedge`** — keep: `set -uo pipefail`; `die()`; the symlink-resolving `BIN_DIR`; the `case "${1:-}" in` dispatch with `*) printf 'selvedge: unknown command: %s\n\n'` exiting 2; `--version` and `install-cli` run with no Node (only Node arms go through `cmd_node`, whose message is `the $name commands need Node.js >= 18 on PATH`, so the `run` arm passes a readable name or `cmd_node` takes the module path separately); the header line `# Exit codes: 0 ok, 1 an operation failed, 2 usage error or BLOCKED (a named reason on its own line),` stays true. Add help lines for `run` and `verdict`. pinned by: `selvedge/tests/test-cli.sh` — `unknown command exits 2`, `grep -qE '^ +install-cli '`, `manifest not found`; `selvedge/tests/test-env.sh` — `--version still runs with no node on PATH`.
- **`selvedge/lib/env-config.mjs`** — keep: `export const REASONS = Object.freeze({` with value == key for every entry, and its grouping comments (`// BLOCKED outcomes`, `// NOT_VERIFIABLE outcomes`, `// config / usage reasons`) — each new reason goes in its group; `parseOrigin` / `isOriginAllowed` / `loadConfig` / `isMain` unchanged (`This is the ONE origin parser`). pinned by: `selvedge/tests/test-env.sh` — `REASONS is frozen and holds exactly`, `README sync: every REASONS key has exactly one row`; `selvedge/tests/test-snapshot.sh` builds its no-literal grep from `Object.keys(E.REASONS)`, so a new reason that `snapshot.mjs` quotes as a literal turns it red.
- **`selvedge/tests/test-env.sh`** — keep: every existing arm; only the closed-list arm's `const want = [` grows by the ten reasons (its label already derives the count from `want.length`), and S3 adds the `env init` ignore-line arms. pinned by: itself (run by `selvedge/tests/run.sh`).
- **`selvedge/lib/snapshot.mjs`** — keep: every behaviour `test-snapshot.sh` pins (exit codes, `snapshots.jsonl` line, `redactValues`/`encodedForms` exports, budget, pins); its imports `import { ACTION_TYPES, placeholderNames, resolvePlaceholders, validateSteps } from './plan-steps.mjs';` and `openGuardedContext` from `./runner/route-guard.mjs` (pinned by grep); no Playwright import (`grep -cE "(from|import\() *['\"]playwright"` must stay 0); `if (isMain(import.meta.url))` with `isMain` from `./env-config.mjs`. S1 changes only `step_failed: 'step_failed',` in `OUTCOMES` to `step_failed: REASONS.step_failed,` (same value). S2: move `function locate(page, loc) {`, `async function navigate(page, url) {` and `async function runStep(page, step) {` to `lib/runner/steps.mjs` and import them (`steps.mjs` imports `reasonOfResponse` from `./route-guard.mjs`, which `navigate` uses; `snapshot.mjs` keeps its own import of it only if it still uses it); the prefix's `default:` refusal of `read`/`expect` (`cannot run in a snapshot prefix`) stays the snapshot's own (prefix mode still rejects them before launch). pinned by: `selvedge/tests/test-snapshot.sh` (`snapshot.mjs imports validateSteps/resolvePlaceholders, openGuardedContext and isOriginAllowed`, AC15 `failed_step`, AC16 placeholder arms), `selvedge/tests/test-plan.sh` (`guard main() with the one isMain from env-config.mjs`).
- **`selvedge/tests/fixtures/app-server.mjs`** — keep: every existing page (`/`, `/cart`, `/echo`, `/cookie`) byte-for-byte in behaviour (test-snapshot.sh and test-plan.sh read them), `startAppServer() → Promise<{ port, origin, events, close() }>`, the `serve <info.json> [<log dir>]` command, the atomic info write and the 15-minute watchdog; the header page list is extended for each new page. A rename of the `/cart` "Open cart" label is server state set by a control request and reset per server start, never a default. pinned by: `selvedge/tests/test-snapshot.sh`, `selvedge/tests/test-plan.sh` (AC8 modal).
- **`selvedge/lib/env.mjs`** — keep: `cmdInit` never overwrites `selvedge.json` (`openSync(file, 'wx', 0o644)`, `refusing to overwrite`), `REASONS.port_required,` when no port; the ignore line is written with an append that never duplicates an existing `.selvedge/` (or `.selvedge`) line; `cmdHook` unchanged (run spawns it). pinned by: `selvedge/tests/test-env.sh` init arms.
- **`selvedge/README.md`** — keep: the reasons table row shape `| \`<reason>\` | <Kind> | <meaning> |`, and **only the reasons table may have rows whose first cell is a backticked lowercase name** (the README-sync arm scans the whole file with `/^\| \`([a-z_]+)\` \|/gm`) — the evidence line kinds, `verdict.json` keys and `runs.jsonl` fields are bullet lists or tables whose first cell is not a backticked lowercase name; `## Releasing`; no selvedge version string in prose. pinned by: `test-env.sh` README-sync arm.
- **`selvedge/.claude-plugin/plugin.json`, `selvedge/CHANGELOG.md`** — keep: the first `## <X.Y.Z> — <YYYY-MM-DD>` heading equals `version`. pinned by: `selvedge/tests/check-release.sh` — `changelog_version_mismatch`.
- **`.claude-plugin/marketplace.json`** — keep: only the `"name": "selvedge"` entry's `version` and `description` change. pinned by: `scripts/validate-version.sh` — `Versions match`.
- **`selvedge/lib/plan-runs.mjs`** (not modified; consumed) — mirror: `RUN_FILES` names (`plan.json`, `plan.sha256`, `freeze.json`, `criteria.json`), `plan.sha256` content `<hex>  plan.json`, run id `RUN_ID_PATTERN`, `readRunsLog(root) → { entries, unparsable }`, freeze lines `{"event":"freeze", ts, run_id, criteria_sha256, plan_sha256, plan_revision, plan_time_actions, planner_tokens}`; `initRun` copies criteria and is reused for the replay folder only if its signature fits (else the replay folder is made with the same `newRunId` + exclusive `mkdirSync`). The run line uses `event: "run"`, never `freeze`, so `nextPlanRevision`'s count is unchanged. pinned by: `selvedge/tests/test-plan.sh` AC14 (`plan_revision: 2` counted from freeze lines only).
- **`selvedge/lib/runner/route-guard.mjs`** (not modified; consumed) — mirror: `openGuardedContext({ chromium, config, lookup, routeLayer = true })` returns `{ browser, context, page, proxy, blocks, seen, close() }`; every criterion opens its own and always `await close()` in a `finally`.

## Closed enumerations touched

> Sibling grep at base `bb6ce2b`: `git grep -nF 'already_frozen' -- . ':!.supervisor'` → hits in 7 files (`selvedge/CHANGELOG.md`, `selvedge/README.md`, `selvedge/lib/env-config.mjs`, `selvedge/lib/plan-runs.mjs`, `selvedge/lib/plan.mjs`, `selvedge/tests/test-env.sh`, `selvedge/tests/test-plan.sh`); `git grep -nF 'planner_failed'` → `CHANGELOG.md`, `README.md`, `env-config.mjs`, `plan-planner.mjs`, `test-env.sh`, `test-plan.sh`.

- **`step_failed`, `stuck_screen`, `budget_exceeded`, `run_interrupted`, `no_value_read`, `material_assumption`, `plan_modified`, `already_run`, `not_frozen`, `evidence_missing`** (sibling: `already_frozen`) — must be named in:
  - `selvedge/lib/env-config.mjs` — the frozen `REASONS` object — extend (S1).
  - `selvedge/README.md` — the reasons table — extend (S1, same subtask as the code list).
  - `selvedge/tests/test-env.sh` — the closed-list arm's `const want = [` — extend (S1).
  - `selvedge/CHANGELOG.md` — release history — extend in the 0.4.0 entry (S3), not a closed list.
  - `selvedge/lib/plan-runs.mjs`, `selvedge/lib/plan.mjs`, `selvedge/lib/plan-planner.mjs`, `selvedge/tests/test-plan.sh` — emitters/tests of other reasons — no change.
  - `selvedge/lib/snapshot.mjs` `OUTCOMES` holds `step_failed: 'step_failed', // a prefix step failed, exit 1` — extend (S1): the value becomes `REASONS.step_failed` (identical string, so `snapshots.jsonl` is unchanged), because `test-snapshot.sh` and `test-criteria.sh` build their no-string-literal greps from `Object.keys(E.REASONS)` and would match the quoted literal once `step_failed` is a reason.
- **`VERDICTS`** (`PASS`, `FAIL`, `BLOCKED`, `NOT_VERIFIABLE`) and **`EVIDENCE_CLASSES`** (`structured-read`, `in-process-assert`, `model-judged`) — new lists, no siblings in code: `selvedge/lib/verdict.mjs` (frozen exports, create) and `selvedge/schemas/verdict.schema.json` (create), pinned equal by AC7.
- **evidence line kinds** (`run_start`, `step`, `criterion_end`, `run_end`) — new list: `selvedge/lib/runner/evidence.mjs` (frozen `EVIDENCE_KINDS`, created in S1, which `readEvidence` and S2's writer both use) and the README bullet list (S3), pinned by `test-verdict.sh` (an unknown `kind` line is refused by `readEvidence`).

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `selvedge/tests/test-env.sh` — closed-list arm (AC1) | delete `stuck_screen` from `REASONS` in `selvedge/lib/env-config.mjs` |
| `selvedge/tests/test-snapshot.sh` — `snapshot*.mjs` name no reason as a string literal (AC1, with `step_failed` now a reason) | flip `step_failed: REASONS.step_failed,` → `step_failed: 'step_failed',` in `selvedge/lib/snapshot.mjs` |
| `selvedge/tests/test-verdict.sh` — no reason string literal in `verdict.mjs` (AC1) | flip `REASONS.no_value_read` → `'no_value_read'` in `selvedge/lib/verdict.mjs` |
| `selvedge/tests/test-verdict.sh` — {PASS, NV, BLOCKED} → exit 2 (AC2) | swap the BLOCKED and NOT_VERIFIABLE precedence in `exitCodeFor` in `selvedge/lib/verdict.mjs` |
| `selvedge/tests/test-verdict.sh` — FAIL added → exit 1 (AC2) | return 2 for FAIL in `exitCodeFor` in `verdict.mjs` |
| `selvedge/tests/test-verdict.sh` — PASS + NV only → exit 3 (AC2) | return 0 when no FAIL/BLOCKED in `exitCodeFor` in `verdict.mjs` |
| `selvedge/tests/test-verdict.sh` — empty read → `NOT_VERIFIABLE no_value_read` even with `equals ""` (AC3) | delete the empty-read check before the `matched` check in `deriveVerdict` in `verdict.mjs` |
| `selvedge/tests/test-verdict.sh` — FAIL carries `read_value` and `expected` (AC4) | omit `expected` from the per-criterion entry in `verdict.mjs` |
| `selvedge/tests/test-verdict.sh` — material assumption → `NOT_VERIFIABLE` (AC5) | delete the `material === true` check in `deriveVerdict` in `verdict.mjs` |
| `selvedge/tests/test-verdict.sh` — `prior_revisions: [{revision: 1, verdict: FAIL}]` (AC6) | read `prior_revisions` from every run line regardless of `criteria_sha256` (the arm has a run line for other criteria) in `verdict.mjs` |
| `selvedge/tests/test-verdict.sh` — a replay line is not a revision's own run (AC6) | drop the `replay_of` filter in `verdict.mjs` |
| `selvedge/tests/test-verdict.sh` — schema enums == `VERDICTS` / `EVIDENCE_CLASSES` (AC7) | drop `model-judged` from `EVIDENCE_CLASSES` in `verdict.mjs` |
| `selvedge/tests/test-verdict.sh` — `verdict.json` keys == schema keys (AC7) | omit `data_state` from the written object in `verdict.mjs` |
| `selvedge/tests/test-verdict.sh` — interrupted criterion → `BLOCKED run_interrupted` (AC8) | treat a criterion with no `criterion_end` line as PASS when its `expect` line matched in `verdict.mjs` |
| `selvedge/tests/test-verdict.sh` — no `evidence.jsonl` → exit 2 `evidence_missing` (AC8) | return an empty line list when `evidence.jsonl` is absent in `readEvidence` in `selvedge/lib/runner/evidence.mjs` |
| `selvedge/tests/test-verdict.sh` — a line with an unknown `kind` is refused (AC7) | drop the `EVIDENCE_KINDS` membership check in `readEvidence` in `evidence.mjs` |
| `selvedge/tests/test-verdict.sh` — `hooks_run` and `failed_step` in `verdict.json` (AC7) | omit `failed_step` from the per-criterion entry in `verdict.mjs` |
| `selvedge/tests/test-run.sh` — edited `plan.json` → `plan_modified`, no launch (AC9) | delete the sha256 comparison before launch in `selvedge/lib/runner/run.mjs` |
| `selvedge/tests/test-run.sh` — no `plan.sha256` → `not_frozen` (AC9) | delete the `plan.sha256`-exists check in `run.mjs` |
| `selvedge/tests/test-run.sh` — second run → `already_run`, folder unchanged (AC10) | delete the `evidence.jsonl`-exists check in `run.mjs` |
| `selvedge/tests/test-run.sh` — 1.5 s value → PASS (AC11) | skip the stable wait and re-read before a failing `expect` in `selvedge/lib/runner/execute.mjs` |
| `selvedge/tests/test-run.sh` — stable wait waits for the slow fetch (AC11) | flip the network-idle in-flight check to `>= 0` (always idle) in `execute.mjs` |
| `selvedge/tests/test-run.sh` — wrong value → FAIL with both values (AC12) | write `value: null` for `read` steps in `selvedge/lib/runner/evidence.mjs` |
| `selvedge/tests/test-run.sh` — locator matching nothing → `BLOCKED step_failed`, `failed_step: 2` (AC13) | record a failed action step as an `expect` mismatch in `execute.mjs` |
| `selvedge/tests/test-run.sh` — hidden / covered click target → `BLOCKED step_failed` (AC13) | replace the click with `if (await loc.count() > 0) await loc.click({ force: true })` in `steps.mjs` (skips Playwright's actionability checks) |
| `selvedge/tests/test-run.sh` — resolving `read` with empty text → `NOT_VERIFIABLE no_value_read` end to end (AC13) | write the empty read value as `"(empty)"` in `evidence.mjs` |
| `selvedge/tests/test-run.sh` — remaining criteria still run after a `step_failed` (AC13) | `break` out of the criteria loop on the first `step_failed` in `run.mjs` |
| `selvedge/tests/test-run.sh` — dead button ×3 → `stuck_screen` (AC14) | change `STUCK_SCREEN_ACTIONS` from 3 to 99 in `execute.mjs` |
| `selvedge/tests/test-run.sh` — negative 0→1 → FAIL (AC15) | make `changed_from` compare the last read with itself in `selvedge/lib/runner/steps.mjs` |
| `selvedge/tests/test-run.sh` — `{{SHOP_USER}}` written literally in `evidence.jsonl` (AC16) | write the resolved step instead of the plan step in `evidence.mjs` |
| `selvedge/tests/test-run.sh` — one screenshot per criterion (AC16) | delete the end-state `page.screenshot` call in `execute.mjs` |
| `selvedge/tests/test-run.sh` — fresh context per criterion (AC16) | reuse the first criterion's guarded context for every criterion in `run.mjs` |
| `selvedge/tests/test-run.sh` — zero planner calls (AC17) | spawn `$SELVEDGE_PLANNER` once at the start of `run.mjs` |
| `selvedge/tests/test-run.sh` — exactly one `runs.jsonl` line per run, none from `verdict` (AC18) | append a run line in `verdict.mjs`'s CLI as well |
| `selvedge/tests/test-run.sh` — `SELVEDGE_ENTRY=ci` recorded, bad value refused (AC18) | ignore `SELVEDGE_ENTRY` (always `session`) in `run.mjs` |
| `selvedge/tests/test-run.sh` — wall-clock budget → remaining `BLOCKED budget_exceeded` (AC19) | ignore `SELVEDGE_RUN_BUDGET_MS` in `run.mjs` |
| `selvedge/tests/test-run.sh` — planner tokens over budget → all `budget_exceeded`, no launch (AC19) | delete the planner-token budget check in `run.mjs` |
| `selvedge/tests/test-run.sh` — no hook → `data_state: unmanaged` + `plan_time_actions` (AC20) | write `plan_time_actions: 0` instead of `freeze.json`'s value in `run.mjs` |
| `selvedge/tests/test-run.sh` — approved `reset` runs before launch (AC20) | skip the hook spawn in `run.mjs` |
| `selvedge/tests/test-run.sh` — unapproved hook → `BLOCKED env_hooks_unapproved`, no launch (AC20) | treat a hook exit 2 as success in `run.mjs` |
| `selvedge/tests/test-run.sh` — modal plan → PASS (AC21) | delete `await locate(page, step.locator).fill(step.value);` in `selvedge/lib/runner/steps.mjs` (Quantity stays 1, Total reads 6) |
| `selvedge/tests/test-snapshot.sh` — prefix step failure `failed_step` (moved executor) | delete `await locate(page, step.locator).click();` in `selvedge/lib/runner/steps.mjs` |
| `selvedge/tests/test-replay.sh` — replay PASS, same sha, `replay_of`, zero planner calls (AC22) | omit `replay_of` from the run line in `run.mjs` |
| `selvedge/tests/test-replay.sh` — replayed `plan.json` byte-identical (AC22) | write the replay copy as `prettyJson(JSON.parse(...))` with sorted keys instead of a byte copy in `run.mjs` |
| `selvedge/tests/test-replay.sh` — replayed `plan.json` still holds the original locator after the rename (AC23) | rewrite a failing role locator's `name` to the page's current button text in the replay folder's `plan.json` in `run.mjs` |
| `selvedge/tests/test-replay.sh` — renamed label → `BLOCKED step_failed` (AC23) | fall back to `getByText` of the role's name when a role locator matches nothing in `steps.mjs` |
| `selvedge/tests/test-replay.sh` — plan + hash edited together → `plan_modified` (AC24) | delete the `runs.jsonl` freeze-line `plan_sha256` comparison in `run.mjs` |
| `selvedge/tests/test-replay.sh` — edited replay leaves no new folder (AC24) | create the replay folder before the hash checks in `run.mjs` |
| `selvedge/tests/test-replay.sh` — kept trace has no cookie value (AC25) | delete the collected-cookie-values replacement in `selvedge/lib/runner/trace-redact.mjs` |
| `selvedge/tests/test-replay.sh` — `Authorization`/`Cookie` header values `[redacted]` (AC25) | drop `authorization` from the redacted header names in `trace-redact.mjs` |
| `selvedge/tests/test-replay.sh` — kept trace has no resolved `{{NAME}}` value (AC25) | skip the `redactValues` pass over text entries in `trace-redact.mjs` |
| `selvedge/tests/test-replay.sh` — no trace without `--trace` (AC25) | start tracing unconditionally in `execute.mjs` |
| `selvedge/tests/test-env.sh` — `env init` adds `.selvedge/` once (AC26) | append the ignore line without the existing-line check in `selvedge/lib/env.mjs` |
| `selvedge/tests/test-env.sh` — `.gitignore` created when absent (AC26) | write the ignore line only when `.gitignore` already exists in `env.mjs` |
| `selvedge/tests/test-env.sh` — ignore line added even when `selvedge.json` exists (AC26) | return before the ignore-line write when `selvedge.json` exists in `cmdInit` in `env.mjs` |
| `selvedge/tests/test-env.sh` — ignore line added even when init fails `port_required` (AC26) | move the ignore-line write after the port detection in `cmdInit` in `env.mjs` |
| `selvedge/tests/test-replay.sh` — README names `run`, `verdict`, `SELVEDGE_ENTRY`, `SELVEDGE_RUN_BUDGET_MS` (AC27) | delete the `SELVEDGE_RUN_BUDGET_MS` bullet in `selvedge/README.md` |

Each pin is a test arm that turns red under its mutation; `test-*.sh` arms print `ok`/`FAIL` lines like `test-cli.sh` and exit non-zero on any FAIL.

**Test isolation (every new test):** a fresh temporary `HOME` and a temp git repo as the target project per test file; `selvedge/tests/lib/playwright-cache.sh` sourced before `HOME` moves (browser arms in `test-run.sh`, `test-replay.sh`), with its bimodal rule (CI install failure = hard FAIL `playwright_install_failed`; locally SKIP of browser arms only — the no-browser arms of AC9/AC10/AC19/AC20 use `tests/fixtures/stub-playwright.mjs` and always run); plans are hand-written JSON frozen with `selvedge plan --init` + `--freeze` (no planner), except AC21/AC23 which reuse `stub-planner.sh` mode `modal`; `SELVEDGE_PLANNER` and `claude` are recording shims (no model, no network beyond the pinned install). `SELVEDGE_PLANNER`, `SELVEDGE_PLAYWRIGHT_MODULE`, `SELVEDGE_ENTRY`, `SELVEDGE_RUN_BUDGET_MS`, `SELVEDGE_PLANNER_TOKEN_BUDGET`, `SELVEDGE_STEP_TIMEOUT_MS` are unset at the top of each test and set per arm.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Ten new `REASONS` + README rows; `verdict.mjs` (`deriveVerdict`, `VERDICTS`, `EVIDENCE_CLASSES`, D7 exit precedence, `prior_revisions`) and the `selvedge verdict` CLI; `verdict.schema.json`; the evidence line contract (`runner/evidence.mjs`: `EVIDENCE_KINDS` + `readEvidence`) | AC1–AC8 | 5 modify, 4 create | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` | LAUNCHABLE |
| 2 | `selvedge run`: executor moved to `lib/runner/steps.mjs`, criterion execution with stable wait / stuck screen / screenshots, `evidence.jsonl`, hash + `already_run` + `not_frozen` checks, hooks + `data_state`, budgets, `runs.jsonl` run line; fixture pages; stub Playwright | AC9–AC21 | 4 modify, 5 create | `skills/playwright-e2e/SKILL.md`, `skills/unit-testing/SKILL.md` | BLOCKED (by #1) |
| 3 | `run --replay`, `--trace` + `trace-redact.mjs`, `env init` ignore line, README, 0.4.0 release | AC22–AC27 | 9 modify, 2 create | `skills/playwright-e2e/SKILL.md`, `skills/unit-testing/SKILL.md` | BLOCKED (by #2) |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "selvedge/lib/verdict.mjs"}
  - {kind: "symbol", path: "selvedge/lib/verdict.mjs", name: "deriveVerdict"}
  - {kind: "symbol", path: "selvedge/lib/verdict.mjs", name: "VERDICTS"}
  - {kind: "symbol", path: "selvedge/lib/verdict.mjs", name: "EVIDENCE_CLASSES"}
  - {kind: "symbol", path: "selvedge/lib/verdict.mjs", name: "exitCodeFor"}
  - {kind: "file", path: "selvedge/schemas/verdict.schema.json"}
  - {kind: "symbol", path: "selvedge/lib/env-config.mjs", name: "stuck_screen"}
  - {kind: "symbol", path: "selvedge/README.md", name: "material_assumption"}
  - {kind: "symbol", path: "selvedge/bin/selvedge", name: "  verdict) shift;"}
  - {kind: "file", path: "selvedge/lib/runner/evidence.mjs"}
  - {kind: "symbol", path: "selvedge/lib/runner/evidence.mjs", name: "EVIDENCE_KINDS"}
  - {kind: "symbol", path: "selvedge/lib/runner/evidence.mjs", name: "readEvidence"}
  - {kind: "file", path: "selvedge/tests/test-verdict.sh"}
requires: []
lanes:
  - "selvedge/bin/selvedge"
  - "selvedge/lib/verdict.mjs"
  - "selvedge/lib/runner/evidence.mjs"
  - "selvedge/lib/env-config.mjs"
  - "selvedge/lib/snapshot.mjs"
  - "selvedge/schemas/verdict.schema.json"
  - "selvedge/tests/test-verdict.sh"
  - "selvedge/tests/test-env.sh"
  - "selvedge/README.md"
external_requires:
  - "Node.js >= 18 on PATH"

# Subtask 2
provides:
  - {kind: "file", path: "selvedge/lib/runner/run.mjs"}
  - {kind: "file", path: "selvedge/lib/runner/steps.mjs"}
  - {kind: "symbol", path: "selvedge/lib/runner/steps.mjs", name: "runStep"}
  - {kind: "symbol", path: "selvedge/lib/runner/steps.mjs", name: "expectMatches"}
  - {kind: "file", path: "selvedge/lib/runner/execute.mjs"}
  - {kind: "symbol", path: "selvedge/lib/runner/execute.mjs", name: "STUCK_SCREEN_ACTIONS"}
  - {kind: "symbol", path: "selvedge/lib/runner/evidence.mjs", name: "appendEvidence"}
  - {kind: "symbol", path: "selvedge/bin/selvedge", name: "  run) shift;"}
  - {kind: "file", path: "selvedge/tests/fixtures/stub-playwright.mjs"}
  - {kind: "file", path: "selvedge/tests/test-run.sh"}
requires:
  - {from: "1", kind: "symbol", path: "selvedge/lib/verdict.mjs", name: "deriveVerdict"}
  - {from: "1", kind: "symbol", path: "selvedge/lib/env-config.mjs", name: "stuck_screen"}
  - {from: "1", kind: "symbol", path: "selvedge/lib/runner/evidence.mjs", name: "EVIDENCE_KINDS"}
lanes:
  - "selvedge/bin/selvedge"
  - "selvedge/lib/runner/run.mjs"
  - "selvedge/lib/runner/steps.mjs"
  - "selvedge/lib/runner/execute.mjs"
  - "selvedge/lib/runner/evidence.mjs"
  - "selvedge/lib/snapshot.mjs"
  - "selvedge/tests/fixtures/app-server.mjs"
  - "selvedge/tests/fixtures/stub-playwright.mjs"
  - "selvedge/tests/test-run.sh"
external_requires:
  - "playwright (resolved from SELVEDGE_PLAYWRIGHT_MODULE or the target repo; tests use the PW_VERSION pin in selvedge/tests/lib/playwright-cache.sh) + its Chromium build"
  - "item 02's openGuardedContext in selvedge/lib/runner/route-guard.mjs and item 03's selvedge/lib/plan-runs.mjs (merged, not modified)"

# Subtask 3
provides:
  - {kind: "file", path: "selvedge/lib/runner/trace-redact.mjs"}
  - {kind: "symbol", path: "selvedge/lib/runner/trace-redact.mjs", name: "redactTraceZip"}
  - {kind: "symbol", path: "selvedge/lib/runner/run.mjs", name: "replayRun"}
  - {kind: "symbol", path: "selvedge/lib/env.mjs", name: ".selvedge/"}
  - {kind: "file", path: "selvedge/tests/test-replay.sh"}
  - {kind: "symbol", path: "selvedge/CHANGELOG.md", name: "## 0.4.0"}
  - {kind: "symbol", path: "selvedge/README.md", name: "SELVEDGE_RUN_BUDGET_MS"}
requires:
  - {from: "2", kind: "file", path: "selvedge/lib/runner/run.mjs"}
  - {from: "2", kind: "file", path: "selvedge/lib/runner/execute.mjs"}
  - {from: "2", kind: "file", path: "selvedge/tests/fixtures/stub-playwright.mjs"}
lanes:
  - "selvedge/lib/runner/run.mjs"
  - "selvedge/lib/runner/execute.mjs"
  - "selvedge/lib/runner/trace-redact.mjs"
  - "selvedge/lib/env.mjs"
  - "selvedge/tests/test-env.sh"
  - "selvedge/tests/fixtures/app-server.mjs"
  - "selvedge/tests/test-replay.sh"
  - "selvedge/README.md"
  - "selvedge/CHANGELOG.md"
  - "selvedge/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
external_requires:
  - "playwright tracing (context.tracing.start/stop) in the pinned 1.65.1"
```

**Worker notes:**
- **Run folder after a run:** item 03's files plus `evidence.jsonl`, `screenshots/<criterion-id>.png`, `verdict.json`, and with `--trace` one `trace.zip` (redacted) per run (or per criterion: `traces/<criterion-id>.zip` — pick one and document it). `.selvedge/` is the gitignored home (D13; AC26 adds the ignore line).
- **`run` order (each exit 2 before anything launches):** usage → `not_frozen` (no `plan.sha256`) → `already_run` (`evidence.jsonl` exists) → `plan_modified` (sha256 of `plan.json` bytes ≠ `plan.sha256`; for `--replay`, also ≠ the `plan_sha256` of the frozen run's `event: "freeze"` line in `runs.jsonl`, and a missing freeze line is `plan_modified` too) → planner-token budget → hooks → origin allowlist via `loadConfig` (a `goto` origin no longer allowed → BLOCKED `host_not_allowed` for that criterion) → `{{NAME}}` set (`placeholder_unset`) → `resolvePlaywright` (`playwright_unavailable`). A `not_planned` criterion is written to evidence as `criterion_end` with its plan reason and becomes `NOT_VERIFIABLE <reason>`.
- **`--replay <frozen-run-dir>`:** all checks above run against the frozen folder before the new folder exists; the new folder gets `criteria.json`, `plan.json` (byte copy), `plan.sha256`, `freeze.json` (copy); `plan_revision` unchanged; `replay_of` = the frozen folder's run id; planner tokens 0.
- **Evidence lines (`evidence.jsonl`, written only by `evidence.mjs`):** `{"kind":"run_start", ts, run_id, plan_sha256, playwright_version, data_state, hooks_run, plan_time_actions, replay_of}`; per step `{"kind":"step", criterion, step, type, locator, outcome: ok|failed|matched|mismatched, value, duration_ms, error?, stable_wait?}` (`value` = the read value for `read`, the plan's value for `fill`/`select` with `{{NAME}}` kept, `null` otherwise); `{"kind":"criterion_end", criterion, outcome: completed|step_failed|stuck_screen|budget_exceeded|blocked|not_planned, reason, failed_step, screenshot}`; `{"kind":"run_end", ts, duration_ms}`. Every string passes `redactValues` with the run's resolved placeholders before it is written. Outcome values that are also `REASONS` keys (`step_failed`, `stuck_screen`, `budget_exceeded`) are written as `REASONS.<key>`; the `criterion_end` outcome list is a frozen constant in `evidence.mjs` built from them, never quoted literals (AC1's grep arm covers `lib/runner/*.mjs`).
- **Verdict rule (D7):** PASS only when the criterion completed, the final `expect` matched, the final `read` value is non-empty, and no `material: true` assumption; FAIL when the final `expect` mismatched after the stable wait; BLOCKED with the `criterion_end` reason; NOT_VERIFIABLE `no_value_read` / `material_assumption` / a `not_planned` reason. Overall `verdict` for the run line = the highest by precedence FAIL > BLOCKED > NOT_VERIFIABLE > PASS; exit 1 / 2 / 3 / 0.
- **`prior_revisions`:** for each earlier revision (freeze lines of the same `criteria_sha256` with a lower `plan_revision`), the `verdict` of that revision's own run line (`event: "run"`, `replay_of: null`), or `null` when it never ran; ascending by revision.
- **Stable wait:** applies only to an `expect` that would FAIL; network idle (in-flight counter, 500 ms quiet) then two equal `page.content()` reads 500 ms apart, both within `STABLE_TIMEOUT_MS` (5000); re-run the criterion's last `read` once, re-evaluate. The fixture's slow value must arrive by a fetch (a pure timer that leaves the DOM unchanged for > 500 ms is a documented limit).
- **Step timeout:** `SELVEDGE_STEP_TIMEOUT_MS` (default `STEP_TIMEOUT_MS` from `snapshot.mjs`, 5000) bounds each action; tests set it low for the `step_failed` arms to keep CI time down.
- **Wall-clock budget:** `SELVEDGE_RUN_BUDGET_MS` (default 600000) checked before each criterion starts; planner-token budget compares `freeze.json` `planner_tokens` (input + output) with `SELVEDGE_PLANNER_TOKEN_BUDGET` when both are set (replay: 0 tokens).
- `{{NAME}}`: `resolvePlaceholders` from `plan-steps.mjs` at execution only; never written resolved anywhere in the run folder.
- `storageState` (item 05) is not built; the context options take it when item 05 lands.

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2 ──→ Subtask 3
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | `selvedge/bin/selvedge`, `selvedge/lib/runner/evidence.mjs`, `selvedge/lib/snapshot.mjs` (legal: 2 reachable from 1) | YES (requires) |
| Subtask 1 | Subtask 3 | `selvedge/tests/test-env.sh`, `selvedge/README.md` (legal: 3 reachable from 1) | YES (requires) |
| Subtask 2 | Subtask 3 | `selvedge/lib/runner/run.mjs`, `selvedge/lib/runner/execute.mjs`, `selvedge/tests/fixtures/app-server.mjs` (legal: 3 reachable from 2) | YES (requires) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2
- **Batch 3:** Subtask 3
- **Recommended workers:** 1
- **Estimated batches:** 3

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` |
| 2 | `skills/playwright-e2e/SKILL.md`, `skills/unit-testing/SKILL.md` |
| 3 | `skills/playwright-e2e/SKILL.md`, `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): context-bound size (~20 files, > 800 lines) | MEDIUM | 3 ordered subtasks on one worker; S1 is browser-free and fixes the evidence/verdict contract S2 writes to |
| Feasibility (Phase 2.5): paths outside the item's Touches (`bin/selvedge`, `env-config.mjs`, `env.mjs`, `snapshot.mjs`, README, the three release files) | LOW | Asked once at Phase 6 (`LP-SCOPE`); each follows the item 02/03 convention (one reason list, one executor, own release) |
| Stable wait false FAIL: a value that arrives by a timer with no network and an unchanged DOM for > 500 ms still FAILs | MEDIUM | Documented in README; fixture proves the fetch case (the requirement's WebTestBench case); `STABLE_TIMEOUT_MS` is one constant |
| Hand-written zip reader mis-parses a Playwright trace (zip64, data descriptors) and keeps secrets | HIGH | Fail closed: anything not parsed is deleted, never kept; AC25 greps the whole unzipped trace for the cookie and `{{NAME}}` values; traces are off by default |
| Moving the executor out of `snapshot.mjs` changes snapshot behaviour | MEDIUM | Pure move + import; `test-snapshot.sh` and `test-plan.sh` AC8 run unchanged and must stay green; a pin mutation in the moved `click` case |
| `stuck_screen` false BLOCKED on a legitimate idempotent action sequence | MEDIUM | N = 3 consecutive identical snapshots after actions, one constant; reason names the step indices |
| CI `static` time: two more browser test files, step-timeout arms | MEDIUM | `SELVEDGE_STEP_TIMEOUT_MS` low in tests; one fixture server per test file; reuse the cached Playwright install |
| `prior_revisions` / `already_run` read `runs.jsonl`, which is an audit trail, not a lock (item 03) | LOW | Races are documented; `already_run` is keyed on `evidence.jsonl` existence created exclusively (`wx`) |
| `run`/`verdict` never exercised on Linux CI before merge (macOS locally) | MEDIUM | GitHub CI runs `selvedge/tests/run.sh` in the `static` job; treat its first red as a fix-in-PR |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 3
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
`/supervisor job: .supervisor/jobs/pending/2026-11-16-qa-split-04-model-free-run-and-verdict.md`

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-11-16T04:04:01Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/926
- **Branch:** feature/qa-split-04-model-free-run-and-verdict
- **Files changed:** 23
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal reason:** needs_human
- **Heal iterations:** 1
- **Heal remaining issues:** 4
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** armed
- **Summary:** selvedge run/verdict/replay/trace + 0.4.0 built in 3 sequential subtasks (59c9c69, 05e4039+51b1913, f7bd2bb); Phase 4.5 review 1 → NEEDS_HUMAN (stable wait skipped for a matching changed_from false expect, held for the owner) + 3 at-floor findings fixed in ec47317; review 2 → still NEEDS_HUMAN plus 1 HIGH (empty read behind a matched non-final expect can PASS) and 2 MEDIUM (first run skips the runs.jsonl freeze-line check; hooks run before the exclusive claim), left unfixed and posted on the PR. ground_truth pass 2/2; CI pending at review time.

## Not verified
- **selvedge/lib/runner/evidence.mjs writer side (appendEvidence)** — subtask 1 hand-off had only synthetic evidence lines; the writer landed in subtask 2 (subtask 1)
- **selvedge/tests/test-run.sh on Linux CI** — macOS only so far (subtask 2)
- **README and plugin descriptions for run** — owned by subtask 3 (AC27), done there (subtask 2)
- **Playwright trace viewer opening a redacted traces/<id>.zip** — checked with Python zipfile + content greps only (subtask 3)
- **selvedge/tests/test-replay.sh on Linux CI** — macOS only so far (subtask 3)
