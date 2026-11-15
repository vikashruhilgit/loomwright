# Supervisor-Ready Brief: qa-split 03 — criteria become a frozen, validated step plan

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** dirty (2 untracked dirs: `reports/`, `research_notes/`, unrelated), branch: release/v17.39.0 (one commit, the Loomwright 17.39.0 release bump, ahead of origin/main; it touches no `selvedge/` file)
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 2 (untracked dirs; 4 linked worktrees on unrelated branches)
- **Source requirement:** .supervisor/requirements/qa-split/03-plan-step-criteria-to-a-frozen-validated-step-plan.md
- **Base commit:** a77244b6abcccfb55fc41ee681a1f575e12eb471

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash CLI + Node ≥ 18 ESM modules under `selvedge/lib/`, exactly as item 02 set up (`selvedge/lib/env.mjs`, `selvedge/lib/runner/*.mjs`) |
| 2 | Dependency Availability | CAUTION | `selvedge snapshot` is the first CLI command that needs Playwright at run time (item 02 used it in tests only). Resolved by Design decision 1 (owner: project-resolve). The default planner needs the `claude` CLI; CI never calls it (tests use a stub `SELVEDGE_PLANNER` and a PATH-stub `claude`) |
| 3 | Architecture Fit | GO | Implements 00-plan D6 (rev 3 revisions), D7 (static PASS rule, negative criteria, assumptions), D17 (`target` in the schema) and P2/P3 on top of item 02's guard (`openGuardedContext`, `REASONS`, `loadConfig`) |
| 4 | Scope vs Supervisor Capability | CAUTION | ~26 files and well over 800 changed lines → `context-bound` split into 3 ordered subtasks |
| 5 | Hard Blockers | CAUTION | Item 02 is merged (#916). Two acceptance lines describe item 04's run/verdict (the modal plan "run PASSes"; `verdict.json` carries `plan_time_actions`); owner decision LP-CLARIFY 2026-11-15 "Prove what 03 owns" scopes them (see Acceptance Criteria AC8, AC11). Files outside the item's Touches (`selvedge/lib/env-config.mjs`, README, release files) — asked once at Phase 6 (`LP-SCOPE`) |

**Overall Verdict:** CAUTION

## Task
**Goal:** Add `selvedge criteria` (from-pr / from-md / from-text + a testability pre-check), `selvedge snapshot <url> [--steps <prefix.json>]` (accessibility tree of an allowed origin through item 02's guard), and `selvedge plan` (`--validate`, `--freeze`, default planner via `SELVEDGE_PLANNER` or `claude -p`), so acceptance criteria become a typed, statically-linted, sha256-frozen `plan.json` in `.selvedge/runs/<run-id>/` before anything runs.

**Problem Statement:**
Selvedge's verdict must not come from a model (00-plan D6). Today there is no way to turn criteria into a plan the runner (item 04) can execute without a model, and nothing checks the PASS rule ("a value read after the last action", D7) before a run. Success: a model (or a stub) can only produce typed steps that pass a static lint; vague criteria and unobservable negative criteria are never planned; the plan is hashed once per run folder and every re-plan is a numbered revision — each proven by a test in `selvedge/tests/`.

## Design decisions
- decision: How the selvedge CLI obtains Playwright at run time for `snapshot` (T1 — Playwright becomes a runtime dependency)
  chosen: `selvedge/lib/snapshot-playwright.mjs` `resolvePlaywright({ root, env })` loads `playwright` (a) from the path in `SELVEDGE_PLAYWRIGHT_MODULE` when set, else (b) via `createRequire(<repo root>/package.json).resolve('playwright')` — the target project's own `node_modules`; neither resolves → `BLOCKED playwright_unavailable` (exit 2, no browser). The resolved `version` is returned for later evidence (item 04 records it). Tests set `SELVEDGE_PLAYWRIGHT_MODULE="$PW_MODULE"` from the existing pinned cache (`selvedge/tests/lib/playwright-cache.sh`)
  rejected: `selvedge/package.json` + `package-lock.json` pinning `playwright`, with a cached `npm ci` step in `.github/workflows/ci.yml` — already in the lockfile: no; blast radius: no (three files outside the Touches); a marketplace install runs no `npm install`, so users still need a setup step
  rejected: reuse the test cache path (`$SELVEDGE_TEST_PW_CACHE`) at run time — a test-only temp dir; reversibility: no
  evidence: repo — `selvedge/` has no `package.json`; `route-guard.mjs` header `This module never imports \`playwright\`, so the runner decides how it is packaged`; item 06c's quick start runs `npx playwright install chromium` in the target app; the owner's web app (`sports-management`) has a Playwright config
  revisit when: a target repo without Playwright is the common case (06c's timed quick start measures it) — then add the package.json route
  status: confirmed (owner, LP-APPROACH 2026-11-15: "Keep project-resolve")
- decision: How a planner is invoked and returns its plan (T2 — new module `selvedge/lib/plan-planner.mjs`)
  chosen: `selvedge plan` runs `SELVEDGE_PLANNER` with `/bin/sh -c` (a user-scoped env value, never read from the repo) with env `SELVEDGE_RUN_DIR`, `SELVEDGE_CRITERIA` (the run folder's `planner-input.json`: testable criteria + allowed origins), `SELVEDGE_PLAN_OUT` (where it writes `plan.json`), `SELVEDGE_BIN` (this CLI, for `snapshot` calls) and optional `SELVEDGE_PLANNER_USAGE` (a file it may write `{"input_tokens":N,"output_tokens":M}` to). Unset ⇒ the built-in default: `claude -p --output-format json` with the fixed prompt `selvedge/prompts/planner.md`, `--allowedTools "Bash(<SELVEDGE_BIN> snapshot:*)"`, model from `SELVEDGE_PLANNER_MODEL` (default `sonnet`); the JSON result's `result` text is parsed for the plan object, its `usage` for tokens
  rejected: the planner prints the plan on stdout — a model's chatter and the plan would share one stream; reversibility: partial
  rejected: an Anthropic SDK call from Node — a new dependency and an API key; fits the stack: no
  evidence: 00-plan §5 "Uses a model through `SELVEDGE_PLANNER`. The default is `claude -p` with a fixed prompt and a token budget"; red-team C6
  revisit when: item 06's verifier subagent shows the `--freeze` path is the common one
  status: confirmed
- decision: Where the snapshot budget, planner model and token budget are configured (T2/T4 — a config surface)
  chosen: environment variables, read by the CLI only: `SELVEDGE_SNAPSHOT_BUDGET` (default 20 calls per run folder), `SELVEDGE_PLANNER_MODEL`, `SELVEDGE_PLANNER_TOKEN_BUDGET` (passed to the planner and recorded; enforcement is item 04's `budget_exceeded`)
  rejected: new keys in `selvedge.json` — that file is closed (`CONFIG_KEYS` in `selvedge/lib/env-config.mjs`, the schema, `test-env.sh`'s key-set equality) and PR-controlled on the head branch; blast radius: no
  evidence: `export const CONFIG_KEYS = Object.freeze(['schema_version', 'origins', 'allow_remote', 'allow_remote_mutation', 'hooks']);`
  revisit when: a team needs per-repo budgets — then a base-branch-read `selvedge.json` key under D15 (b)
  status: confirmed

- decision: How the new code splits into modules (T2 — `criteria.mjs`, `plan-steps.mjs`, `plan-validate.mjs`, `plan.mjs`, `plan-runs.mjs`, `snapshot.mjs`)
  chosen: one module per responsibility inside the requirement's Touches (`selvedge/lib/criteria*`, `plan*`, `snapshot*`), as listed under Module layout; the step validator lives once in `plan-steps.mjs` and is imported by both the plan lint and the snapshot prefix; `plan-runs.mjs` is a separate module because item 04 reuses its run-folder and `runs.jsonl` helpers
  rejected: a single `plan.mjs` holding criteria, lint, planner, freeze and snapshot — test cost: no (every test would import the Playwright-facing code); blast radius: partial (item 04 would import a CLI module to reach two helpers)
  rejected: put the step executor and validator under `selvedge/lib/runner/` — blast radius: no (`selvedge/lib/runner/**` is item 04's Touches, not this item's)
  evidence: the requirement's Touches names `selvedge/lib/criteria*`, `selvedge/lib/plan*`, `selvedge/lib/snapshot*`; repo — nothing under `selvedge/` parses criteria, validates steps or takes snapshots today (`git grep -nF ariaSnapshot -- selvedge` → 0 hits); item 02's split (`env.mjs` CLI / `env-config.mjs` shared / `env-approvals.mjs`) is the house shape
  revisit when: item 04 needs the prefix executor for `run` — it may move the executor half of `snapshot.mjs` into `selvedge/lib/runner/` and import `validateSteps` unchanged
  status: confirmed

## Acceptance Criteria

Criteria, step schema and the static lint (subtask 1):
- [ ] AC1 — Given a plan whose criterion's steps end in `click`, when `selvedge plan --validate <plan>` runs, then it exits 2 and a stderr line `plan_invalid: <criterion id>: missing_final_read_expect` names that criterion.
- [ ] AC2 — Given a criterion whose final `expect` uses op `visible` (or `hidden`/`exists`/`attached`, or a `read count` followed by `expect gt 0`), when `--validate` runs, then it exits 2 with `existence_only_expect` naming the criterion.
- [ ] AC3 — Given a step with an unknown `type`, or a known type carrying an extra field, or a locator using `css`/`xpath`/any key other than exactly one of `role` (+ optional `name`, `exact`), `label`, `text`, `testid`, when `--validate` runs, then it exits 2 with `unknown_step_type` / `unknown_field` / `invalid_locator`; a step string field that looks like code (`=>`, `function(`, `<script`, `javascript:`, `${`, a backtick, `eval(`, `document.`, `window.`, `require(`, `import `) is rejected `code_like_content`; a `goto` whose origin is not in the plan's `origins` or not allowed by `selvedge.json` (`isOriginAllowed`) is rejected `origin_not_allowed`. One plan with several problems lists every one (one stderr line each), not just the first.
- [ ] AC4 — Given the criterion "the page looks good", when `selvedge criteria check <criteria.json>` runs, then it prints `vague <id>` with a suggested testable rewrite (deterministic: a fixed vague-phrase list — `works well`, `looks good`, `looks right`, `looks nice`, `user-friendly`, `intuitive`, `as expected`, `properly`, `correctly`, `seamless` — and no quoted literal or digit in the text); and `--validate` rejects a plan that plans it (`vague_criterion_planned`) and accepts it only under `not_planned` with `reason: criterion_not_testable` and a non-empty `rewrite`.
- [ ] AC5 — Given the same three criteria as a PR body (under a heading containing "Acceptance criteria", `gh` stubbed on PATH), a markdown file with a `- ` list, and stdin text, when `selvedge criteria from-pr <n>`, `from-md <file>` and `from-text` run, then the three `criteria.json` outputs are byte-identical: `{schema_version: 1, source: null, criteria: [{id, text}]}` with `id` = `c-` + the first 12 hex of sha256(normalized text) (checkbox markers, list markers and surrounding whitespace stripped, inner whitespace collapsed), pretty-printed with 2 spaces and a trailing newline. `source` is `null` unless `--source <label>` is passed (provenance is printed on stderr), which is what keeps the three byte-identical. No criteria found → exit 2 `criteria_not_found`.
- [ ] AC12 — Given a `negative` criterion with no `read` before its first action step (`click`/`fill`/`select`/`check`/`press`), or whose only check is that an element is absent or hidden (final `read count` + `expect equals 0`, or a `wait_for` `hidden` as the last check), when `--validate` runs, then it is rejected `negative_without_baseline` / `negative_absence_only`.
- [ ] AC13 — Given a planned criterion missing `interpretation` or `polarity` (or `unverified_assumptions` not an array of `{text, material}`), when `--validate` runs, then it is rejected `missing_interpretation` / `missing_polarity` / `invalid_assumptions`; a criterion in `criteria.json` that is neither planned nor in `not_planned` is rejected `criterion_unaccounted`; a plan whose `criteria_sha256` differs from the run folder's `criteria.json` is rejected `criteria_sha_mismatch`.
- [ ] AC20 — `REASONS` in `selvedge/lib/env-config.mjs` gains exactly `playwright_unavailable`, `placeholder_unset` (BLOCKED), `criterion_not_testable`, `side_effect_not_observable`, `exploration_budget` (NOT_VERIFIABLE), `already_frozen`, `plan_invalid`, `criteria_invalid`, `criteria_not_found`, `planner_failed` (usage/config); `selvedge/README.md`'s reasons table gains one row each (Kind `NOT_VERIFIABLE` for the three) and a bullet list of every `PLAN_PROBLEMS` code (written in Subtask 1, pinned by `test-plan-validate.sh`), and `test-env.sh`'s closed-list arm and README-sync arm pass with the new set; no new module names a reason as a string literal (a grep arm in each new test, like `test-proxy.sh`'s). `selvedge/schemas/criteria.schema.json` and `plan.schema.json` (draft 2020-12, `additionalProperties: false`) exist, `plan.schema.json` carries `target` (const `"web"`), and a test asserts the schema's step-type enum and per-type field names equal the validator's frozen sets in `selvedge/lib/plan-steps.mjs`.

Snapshot (subtask 2) — against real Chromium through item 02's `openGuardedContext`, with a local fixture app:
- [ ] AC7 — Given `selvedge.json` listing only `http://localhost:<A>`, when `selvedge snapshot http://localhost:<U>/ --run-dir <dir>` runs, then stdout carries `BLOCKED host_not_allowed`, exit 2, the URL is refused before any browser launches (a recording fixture server U logs zero connections), and the call is still counted in `snapshots.jsonl` with outcome `blocked`.
- [ ] AC9 — Given a `--steps` prefix with an unknown step type, or a `read`/`expect` step, or more than 15 steps, then it exits 2 `plan_invalid` listing the problems and nothing launches; given a prefix `goto` to an unlisted origin, then `BLOCKED host_not_allowed`, nothing launches, the fixture logs zero connections.
- [ ] AC10 — Given `SELVEDGE_SNAPSHOT_BUDGET` unset and 20 snapshot calls already recorded in `<run-dir>/snapshots.jsonl`, when the 21st call runs, then stdout carries `NOT_VERIFIABLE exploration_budget`, exit 3, no browser launches; with `SELVEDGE_SNAPSHOT_BUDGET=2` the 3rd call does the same.
- [ ] AC15 — Given a prefix whose 2nd step clicks a locator that matches nothing, when snapshot runs, then it exits 1 and its stdout JSON carries `failed_step: 1` (0-based), the error's first line, and the accessibility tree as it was at the failing step.
- [ ] AC16 — Given a prefix `fill` whose value is `{{SHOP_USER}}`, when `SHOP_USER` is set, then the page receives the resolved value and `snapshots.jsonl` records the step with the literal `{{SHOP_USER}}` (never the value); when unset, `BLOCKED placeholder_unset` naming `SHOP_USER`, nothing launches.
- [ ] AC17 — Given `SELVEDGE_PLAYWRIGHT_MODULE` unset and no `playwright` resolvable from the repo root, when snapshot runs, then `BLOCKED playwright_unavailable`, exit 2 (tested with a temp repo with no `node_modules`).
- [ ] AC11a — Given a prefix of `goto` + `click` + `fill`, when snapshot runs, then `snapshots.jsonl` gains one line `{ts, origin, prefix_steps, plan_time_actions: 2, browser_launched, outcome, failed_step}` (no page text, no aria tree), and each call uses a fresh browser context.

The plan command, freeze and revisions (subtask 3):
- [ ] AC6 — Given a stub `SELVEDGE_PLANNER` (fixture script) and a `criteria.json`, when `selvedge plan <criteria.json>` runs, then it creates `.selvedge/runs/<run-id>/` holding `criteria.json`, `plan.json`, `plan.sha256` (`<hex>  plan.json`, matching `shasum -a 256 plan.json`) and `freeze.json`; `plan` always runs the validator before hashing (a stub that writes an invalid plan → exit 2 `plan_invalid`, no `plan.sha256`); a planner that exits non-zero or writes no plan → exit 2 `planner_failed`; the tokens the stub reports are recorded in `freeze.json` and the `runs.jsonl` freeze line.
- [ ] AC4b — Given the vague criterion among the input, when `selvedge plan` runs with the stub, then the planner never receives it in `planner-input.json` and the frozen `plan.json` carries it under `not_planned` with `criterion_not_testable` and the rewrite (plan adds it itself).
- [ ] AC8 — Given the fixture app's "Open cart" button that opens a dialog holding a "Quantity" spinbutton and a "Total" value, when the stub planner calls `$SELVEDGE_BIN snapshot` without `--steps`, then the returned tree lacks the dialog's controls; with `--steps` (goto + click "Open cart") the tree contains them; the frozen plan's locators resolve: running the plan's steps minus `read`/`expect`, plus a `wait_for` (state `visible`) on the `read` step's locator, as a `snapshot --steps` prefix exits 0 (Playwright's strict mode makes each resolve to exactly one element). The full run and its PASS are item 04's (owner decision LP-CLARIFY 2026-11-15: "Prove what 03 owns").
- [ ] AC11 — Given snapshot calls with plan-time actions in a run folder, when `plan --freeze` runs, then `freeze.json` and the `runs.jsonl` freeze line carry `plan_time_actions` = the sum over `snapshots.jsonl`. `verdict.json`'s `plan_time_actions` (with no `reset` hook) is item 04's, which reads this value (owner decision LP-CLARIFY 2026-11-15).
- [ ] AC14 — Given a run folder already frozen, when `selvedge plan --freeze <run-dir>` runs again, then exit 2 `already_frozen` and no file in the folder changes; given a new run folder (`selvedge plan --init <criteria.json>`) for the same `criteria_sha256`, when its plan is frozen, then `plan.json` has `plan_revision: 2` (counted from `event: "freeze"` lines in `.selvedge/runs.jsonl` with the same `criteria_sha256`) and the first folder is untouched.
- [ ] AC18 — Given `SELVEDGE_PLANNER` unset and a PATH-stub `claude` that records its argv and prints a canned `--output-format json` result, when `selvedge plan` runs, then the stub saw `-p`, `--output-format json`, the text of `selvedge/prompts/planner.md`, and `--allowedTools` limited to `Bash(<SELVEDGE_BIN> snapshot:*)`; with no `claude` on PATH → exit 2 `planner_failed` naming `claude`.
- [ ] AC21 — Given the owner decision LP-CLARIFY 2026-11-15, then `selvedge/docs/evidence/gate-scopes.md`'s qa-split/03 section has a `### Hand-off to item 04` subsection naming the two clauses item 04 must deliver (the modal fixture plan's run PASSes; `verdict.json` carries `plan_time_actions` when no `reset` hook ran, read from `freeze.json`) and the file and key it reads them from; and `selvedge/README.md`'s `plan` section says `plan_time_actions` is recorded in `freeze.json` and `runs.jsonl`.
- [ ] AC19 — `selvedge/README.md` documents `criteria`, `snapshot`, `plan` (`--init`, `--validate`, `--freeze`), the run-folder files, the `SELVEDGE_*` variables, how Playwright is found, and the `plan.json` step types; `selvedge/docs/evidence/gate-scopes.md` gets a qa-split/03 section; selvedge is released as 0.3.0 (`selvedge/.claude-plugin/plugin.json`, the marketplace selvedge entry and a `## 0.3.0 — <date>` CHANGELOG heading together; both `description`s updated in place to name criteria/snapshot/plan, no version string); `bash selvedge/tests/run.sh` passes.

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

(Applied here: the README names no selvedge version. `test-env.sh`'s closed-list arm label drops its literal count ("exactly the 16 named reasons") for a derived one; the README reasons table is updated in the same subtask as `REASONS` and stays pinned by the README-sync arm; the schema enums are pinned equal to the validator's frozen sets.)

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| criteria + step schema + lint (S1) | `selvedge/bin/selvedge` (101), `selvedge/lib/env-config.mjs` (248), `selvedge/tests/test-env.sh` (394), `selvedge/README.md` (252) | `selvedge/lib/criteria.mjs`, `selvedge/lib/plan-steps.mjs`, `selvedge/lib/plan-validate.mjs`, `selvedge/lib/plan.mjs`, `selvedge/schemas/criteria.schema.json`, `selvedge/schemas/plan.schema.json`, `selvedge/tests/test-criteria.sh`, `selvedge/tests/test-plan-validate.sh` | HIGH |
| snapshot (S2) | `selvedge/bin/selvedge` (101) | `selvedge/lib/snapshot.mjs`, `selvedge/lib/snapshot-playwright.mjs`, `selvedge/tests/fixtures/app-server.mjs`, `selvedge/tests/test-snapshot.sh` | HIGH |
| plan command, freeze, revisions, release (S3) | `selvedge/lib/plan.mjs` (created by S1), `selvedge/README.md` (252), `selvedge/docs/evidence/gate-scopes.md` (84), `selvedge/CHANGELOG.md` (43), `selvedge/.claude-plugin/plugin.json` (15), `.claude-plugin/marketplace.json` (140) | `selvedge/lib/plan-planner.mjs`, `selvedge/lib/plan-runs.mjs`, `selvedge/prompts/planner.md`, `selvedge/tests/fixtures/stub-planner.sh`, `selvedge/tests/fixtures/stub-claude.sh`, `selvedge/tests/test-plan.sh` | HIGH |

**Module layout (one home per responsibility; no MODIFY path is at the 500-line threshold):**
- criteria extraction (PR body via `gh pr view <n> --json body`, md list, stdin), normalization, stable ids, `criteriaSha256` (sha256 of `canonicalJson` of the `criteria` array — `source` excluded), testability pre-check `classifyTestability` and the `criteria from-pr|from-md|from-text|check` CLI → `selvedge/lib/criteria.mjs` (CREATE)
- step-type registry (frozen `STEP_TYPES`, per-type field sets, locator forms, `read` properties, `expect` ops), code-like detection, `{{NAME}}` syntax and resolution, `validateSteps(steps, { config, origins, prefix })` — the ONE step validator shared by the plan lint and the snapshot prefix → `selvedge/lib/plan-steps.mjs` (CREATE)
- plan-level lint (D7 PASS rule, negative/baseline, interpretation/polarity/assumptions, `not_planned` reasons, criterion coverage, `criteria_sha256`) with a frozen `PLAN_PROBLEMS` code list → `selvedge/lib/plan-validate.mjs` (CREATE)
- `selvedge plan` CLI: `--validate` (S1), then `--init`, planner run, `--freeze` (S3) → `selvedge/lib/plan.mjs` (CREATE in S1, extended in S3)
- run folder + `runs.jsonl` (run-id, revision count, freeze record, `plan.sha256`, `freeze.json`) → `selvedge/lib/plan-runs.mjs` (CREATE; item 04 reuses it for its run line)
- planner invocation (`SELVEDGE_PLANNER` and the `claude -p` default) → `selvedge/lib/plan-planner.mjs` (CREATE)
- Playwright resolution → `selvedge/lib/snapshot-playwright.mjs` (CREATE); snapshot CLI, prefix executor (guarded context from `openGuardedContext`, one fresh context per call), budget, `snapshots.jsonl` → `selvedge/lib/snapshot.mjs` (CREATE)
- new reason values → the existing `REASONS` in `selvedge/lib/env-config.mjs` (248 — the one closed list; its header: `Every emitter imports a value from here; no reason is a string literal`)
- dispatch → `selvedge/bin/selvedge` (101 — one `case` arm per new command, execs `node "$BIN_DIR/../lib/<module>.mjs"`)
- fixture app (a page with an "Open cart" button opening a `role=dialog` with a Quantity spinbutton and a Total, plus a plain page) → `selvedge/tests/fixtures/app-server.mjs` (CREATE; `servers.mjs` records connections for the guard tests and is reused for the zero-connection U server, not extended)
- No helper is already copied in 2+ siblings; `canonicalJson` is reused from `selvedge/lib/env-approvals.mjs` (never a second copy); `node_eval`/`ok`/`ko` stay per-test as in the existing tests.

> **Validator-owned surfaces:** `selvedge/tests/run.sh` globs only top-level `selvedge/tests/test-*.sh`, so helpers under `tests/fixtures/` must not be named `test-*`. `scripts/check-locale-prefix.sh` scans every tracked `*.sh` (new: `test-criteria.sh`, `test-plan-validate.sh`, `test-snapshot.sh`, `test-plan.sh`, `fixtures/stub-planner.sh`, `fixtures/stub-claude.sh`). `scripts/validate-version.sh` checks the marketplace selvedge entry against `selvedge/.claude-plugin/plugin.json`; `scripts/check-doc-currency.sh` scans `.claude-plugin/marketplace.json` (description length reads only the loomwright entry). `selvedge/tests/test-env.sh`'s README-sync arm scans `selvedge/README.md`'s reasons table.

### File Overlap Detection

| Group A | Group B | Overlapping Files | Serialization Required |
|---------|---------|-------------------|----------------------|
| S1 | S2 | `selvedge/bin/selvedge` | YES — ordered by `requires` |
| S1 | S3 | `selvedge/lib/plan.mjs`, `selvedge/README.md` | YES — ordered by `requires` (S3 reachable from S1) |
| S2 | S3 | none (S3's modal test calls S2's CLI) | YES — S3 requires S2 |

## Touched-file invariants

> Grounded at base `a77244b6abcccfb55fc41ee681a1f575e12eb471`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`selvedge/bin/selvedge`** — keep: `set -uo pipefail`; `die()`; the symlink-resolving `BIN_DIR` (lib paths built from `BIN_DIR`, so the `install-cli` link still finds them); the `case "${1:-}" in` dispatch with `*) printf 'selvedge: unknown command: %s\n\n'` exiting 2; `--version` and `install-cli` still run with no Node on PATH (only Node arms check `command -v node`, as `cmd_env` does with `the env commands need Node.js >= 18`). Update the header line `# Exit codes: 0 ok, 1 an operation failed, 2 usage error or BLOCKED (a named reason on its own line).` to add `3 NOT_VERIFIABLE` (00-plan D7 precedence 1 > 2 > 3 > 0), and add help lines for `criteria`, `snapshot`, `plan`. pinned by: `selvedge/tests/test-cli.sh` — `unknown command exits 2`, `grep -qE '^ +install-cli '`, `manifest not found`; `selvedge/tests/test-env.sh` — `--version still runs with no node on PATH`.
- **`selvedge/lib/env-config.mjs`** — keep: `export const REASONS = Object.freeze({` with value == key for every entry; the BLOCKED vs config/usage grouping comments; `parseOrigin` / `isOriginAllowed` / `loadConfig` unchanged (reuse: new modules import them — never a second origin parser: `This is the ONE origin parser`). Add a `// NOT_VERIFIABLE outcomes` group. pinned by: `selvedge/tests/test-env.sh` — `REASONS is frozen and holds exactly`, `README sync: every REASONS key has exactly one row`.
- **`selvedge/tests/test-env.sh`** — keep: every existing arm; only the `const want = [` list of the closed-list arm grows by the ten new reasons and its label derives the count (`want.length`) instead of the literal `16`. pinned by: itself (run by `selvedge/tests/run.sh`).
- **`selvedge/README.md`** — keep: the reasons table row shape `| \`<reason>\` | <Kind> | <meaning> |`; the README-sync arm runs `md.matchAll(/^\| \`([a-z_]+)\` \|/gm)` over the WHOLE README, so **only the reasons table may have rows whose first cell is a backticked lowercase name** — the `PLAN_PROBLEMS` list, the step-type docs and any other new list are written as bullet lists (`- \`goto\` — …`) or as tables whose first column is not a backticked lowercase name, or the arm reports them as `extra` reasons; the `## Releasing` steps; no selvedge version string in prose. pinned by: `test-env.sh` README-sync arm.
- **`selvedge/.claude-plugin/plugin.json`, `selvedge/CHANGELOG.md`** — keep: first `## <X.Y.Z> — <YYYY-MM-DD>` heading equals `version`. pinned by: `selvedge/tests/check-release.sh` — `changelog_version_mismatch`.
- **`.claude-plugin/marketplace.json`** — keep: only the `"name": "selvedge"` entry's `version` and `description` change; the loomwright entry is untouched. pinned by: `scripts/validate-version.sh` — `Versions match`.
- **`selvedge/lib/runner/route-guard.mjs`** (not modified; consumed) — mirror: `openGuardedContext({ chromium, config, lookup, routeLayer = true })` returns `{ browser, context, page, proxy, blocks, seen, close() }`; snapshot passes `chromium` from `resolvePlaywright`, never `routeLayer`, and always `await close()` in a `finally`. Item 04 owns `selvedge/lib/runner/**`; this item edits nothing there.

## Closed enumerations touched

> Sibling grep at base `a77244b`: `git grep -nF 'port_required' -- . ':!.supervisor'` → hits in 4 files (`selvedge/README.md`, `selvedge/lib/env-config.mjs`, `selvedge/lib/env.mjs`, `selvedge/tests/test-env.sh`); `git grep -nF 'proxy_unavailable'` → hits in `CHANGELOG.md`, `README.md`, `env-config.mjs`, `route-guard.mjs`, `guard-driver.mjs`, `test-env.sh`, `test-proxy.sh`, `test-route-guard.sh`.

- **`playwright_unavailable`, `placeholder_unset`, `criterion_not_testable`, `side_effect_not_observable`, `exploration_budget`, `already_frozen`, `plan_invalid`, `criteria_invalid`, `criteria_not_found`, `planner_failed`** (sibling: `port_required`) — must be named in:
  - `selvedge/lib/env-config.mjs` — the frozen `REASONS` object — extend (S1).
  - `selvedge/README.md` — the reasons table — extend (S1, same subtask as the code list).
  - `selvedge/tests/test-env.sh` — the closed-list arm's `const want = [` — extend (S1).
  - `selvedge/tests/test-proxy.sh`, `selvedge/tests/test-route-guard.sh` — their no-string-literal greps name only their own modules' reasons — no change: not a list of every reason.
  - `selvedge/lib/env.mjs`, `route-guard.mjs`, `guard-driver.mjs`, `selvedge/CHANGELOG.md` — emitters/history of other reasons — no change.
- **`PLAN_PROBLEMS`** (new list, no siblings: `missing_final_read_expect`, `existence_only_expect`, `unknown_step_type`, `unknown_field`, `invalid_locator`, `code_like_content`, `origin_not_allowed`, `missing_interpretation`, `missing_polarity`, `invalid_assumptions`, `negative_without_baseline`, `negative_absence_only`, `vague_criterion_planned`, `criterion_unaccounted`, `criteria_sha_mismatch`, `prefix_step_not_allowed`, `prefix_too_long`, `invalid_not_planned`) — `selvedge/lib/plan-validate.mjs` (frozen export, create) and `selvedge/README.md` (a plan-lint problems bullet list, create in S1 — the same subtask as `PLAN_PROBLEMS`) — `test-plan-validate.sh` asserts each code appears in the README list.
- **Step types** (`goto`, `click`, `fill`, `select`, `check`, `press`, `wait_for`, `read`, `expect`) — `selvedge/lib/plan-steps.mjs` `STEP_TYPES` (create) and `selvedge/schemas/plan.schema.json` (create); pinned equal by AC20.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `selvedge/tests/test-plan-validate.sh` — criterion ending in `click` rejected (AC1) | delete the final-`read`+`expect` check in `selvedge/lib/plan-validate.mjs` |
| `selvedge/tests/test-plan-validate.sh` — `expect` op `visible` rejected (AC2) | remove `visible` from the existence-only op set in `plan-validate.mjs` |
| `selvedge/tests/test-plan-validate.sh` — `read count` + `expect gt 0` rejected (AC2) | delete the count-`gt 0` existence clause in `plan-validate.mjs` |
| `selvedge/tests/test-plan-validate.sh` — unknown step type (AC3) | make `validateSteps` in `selvedge/lib/plan-steps.mjs` skip steps whose type is not in `STEP_TYPES` |
| `selvedge/tests/test-plan-validate.sh` — extra field (AC3) | delete the per-type unknown-field check in `plan-steps.mjs` |
| `selvedge/tests/test-plan-validate.sh` — css locator rejected (AC3) | accept any single-key locator object in `plan-steps.mjs` |
| `selvedge/tests/test-plan-validate.sh` — code-like content (AC3) | delete `=>` from the code-like pattern in `plan-steps.mjs` (the arm's step carries `() => 1`) |
| `selvedge/tests/test-plan-validate.sh` — unlisted `goto` origin (AC3) | delete the `isOriginAllowed` check on `goto` in `plan-steps.mjs` |
| `selvedge/tests/test-plan-validate.sh` — every problem listed (AC3: three problems → three lines) | return after the first problem in `plan-validate.mjs` |
| `selvedge/tests/test-criteria.sh` — "the page looks good" is `vague` (AC4) | delete `looks good` from the vague-phrase list in `selvedge/lib/criteria.mjs` |
| `selvedge/tests/test-plan-validate.sh` — planned vague criterion rejected (AC4) | delete the `vague_criterion_planned` check in `plan-validate.mjs` |
| `selvedge/tests/test-criteria.sh` — byte-identical from-pr/md/text (AC5) | write `source: "pr"` in `from-pr` in `criteria.mjs` |
| `selvedge/tests/test-criteria.sh` — stable ids (AC5) | hash the raw (un-normalized) text in `criteria.mjs` (the md arm has a `- [ ]` marker and double spaces) |
| `selvedge/tests/test-plan-validate.sh` — negative with no baseline (AC12) | delete the baseline-read-before-first-action check in `plan-validate.mjs` |
| `selvedge/tests/test-plan-validate.sh` — negative hidden-only (AC12) | delete the `negative_absence_only` check in `plan-validate.mjs` |
| `selvedge/tests/test-plan-validate.sh` — missing `interpretation` (AC13) | delete the `interpretation` presence check in `plan-validate.mjs` |
| `selvedge/tests/test-plan-validate.sh` — `criterion_unaccounted` (AC13) | delete the coverage loop over `criteria.json` ids in `plan-validate.mjs` |
| `selvedge/tests/test-env.sh` — closed-list arm (AC20) | delete `exploration_budget` from `REASONS` in `env-config.mjs` |
| `selvedge/tests/test-plan-validate.sh` — schema enum == `STEP_TYPES` (AC20) | drop `press` from `STEP_TYPES` in `plan-steps.mjs` |
| `selvedge/tests/test-snapshot.sh` — unlisted origin, no launch, U zero connections (AC7) | delete the pre-launch origin check in `selvedge/lib/snapshot.mjs` (the route layer would still block, but the arm asserts the `snapshots.jsonl` line's `browser_launched: false`) |
| `selvedge/tests/test-snapshot.sh` — prefix with `read` rejected (AC9) | allow `read` in the prefix step set in `plan-steps.mjs` |
| `selvedge/tests/test-snapshot.sh` — 16-step prefix rejected (AC9) | change the prefix cap `15` to `16` in `plan-steps.mjs` |
| `selvedge/tests/test-snapshot.sh` — 21st call `exploration_budget` (AC10) | change the default budget `20` to `21` in `snapshot.mjs` |
| `selvedge/tests/test-snapshot.sh` — `SELVEDGE_SNAPSHOT_BUDGET=2` honored (AC10) | ignore `SELVEDGE_SNAPSHOT_BUDGET` in `snapshot.mjs` |
| `selvedge/tests/test-snapshot.sh` — failing step index + tree (AC15) | omit `failed_step` from the output object in `snapshot.mjs` |
| `selvedge/tests/test-snapshot.sh` — `{{NAME}}` kept unresolved in `snapshots.jsonl` (AC16) | log the resolved steps instead of the given steps in `snapshot.mjs` |
| `selvedge/tests/test-snapshot.sh` — `placeholder_unset` (AC16) | resolve an unset `{{NAME}}` to `''` in `plan-steps.mjs` |
| `selvedge/tests/test-snapshot.sh` — `playwright_unavailable` (AC17) | flip `REASONS.playwright_unavailable` → `REASONS.proxy_unavailable` in `selvedge/lib/snapshot-playwright.mjs` |
| `selvedge/tests/test-snapshot.sh` — `plan_time_actions: 2` (AC11a) | count `goto` as a plan-time action in `snapshot.mjs` |
| `selvedge/tests/test-plan.sh` — `plan.sha256` matches `shasum -a 256 plan.json` (AC6) | hash `canonicalJson(plan)` instead of the written file bytes in `selvedge/lib/plan-runs.mjs` |
| `selvedge/tests/test-plan.sh` — invalid stub plan → no `plan.sha256` (AC6) | skip `validatePlan` before hashing in `selvedge/lib/plan.mjs` |
| `selvedge/tests/test-plan.sh` — vague criterion not sent to the planner (AC4b) | pass every criterion into `planner-input.json` in `plan.mjs` |
| `selvedge/tests/test-plan.sh` — modal: without prefix the dialog is absent, with it present, locators resolve (AC8) | drop the `--steps` prefix execution (snapshot the bare URL) in `snapshot.mjs` |
| `selvedge/tests/test-plan.sh` — `plan_time_actions` summed into `freeze.json` (AC11) | write `plan_time_actions: 0` in `plan-runs.mjs` |
| `selvedge/tests/test-plan.sh` — second freeze `already_frozen`, folder unchanged (AC14) | delete the `plan.sha256`-exists check in `plan-runs.mjs` |
| `selvedge/tests/test-plan.sh` — new folder → `plan_revision: 2` (AC14) | count every `runs.jsonl` line instead of matching `criteria_sha256` (the arm has a freeze line for other criteria) in `plan-runs.mjs` |
| `selvedge/tests/test-plan.sh` — default planner argv (AC18) | drop `--allowedTools` from the `claude` argv in `selvedge/lib/plan-planner.mjs` |
| `selvedge/tests/test-plan.sh` — no `claude` on PATH → `planner_failed` naming `claude` (AC18) | treat a spawn `ENOENT` as an empty successful result in `plan-planner.mjs` |
| `selvedge/tests/test-plan.sh` — stub planner exits 1 → `planner_failed`, no `plan.sha256` (AC6) | ignore the planner's exit status in `plan-planner.mjs` |
| `selvedge/tests/test-plan.sh` — stub exits 0 and writes no plan → `planner_failed` (AC6) | treat a missing `SELVEDGE_PLAN_OUT` file as an empty plan `{}` in `plan-planner.mjs` |
| `selvedge/tests/test-plan-validate.sh` — `not_planned` with an empty `rewrite` rejected `invalid_not_planned` (AC4) | drop the non-empty `rewrite` check in `plan-validate.mjs` |
| `selvedge/tests/test-plan.sh` — stub-reported tokens in `freeze.json` and the `runs.jsonl` freeze line (AC6) | write `planner_tokens: null` in `plan-runs.mjs` |
| `selvedge/tests/test-plan.sh` — first run folder byte-unchanged after the second folder's freeze (AC14) | write `plan_revision` into every folder of the same `criteria_sha256` in `plan-runs.mjs` |
| `selvedge/tests/test-plan-validate.sh` — missing `polarity` (AC13) | delete the `polarity` presence check in `plan-validate.mjs` |
| `selvedge/tests/test-plan-validate.sh` — `invalid_assumptions` (AC13) | delete the `{text, material}` shape check in `plan-validate.mjs` |
| `selvedge/tests/test-plan-validate.sh` — `criteria_sha_mismatch` (AC13) | delete the `criteria_sha256` comparison in `plan-validate.mjs` |
| `selvedge/tests/test-criteria.sh` — no list items → `criteria_not_found` (AC5) | return an empty `criteria` array instead of failing in `criteria.mjs` |
| `selvedge/tests/test-criteria.sh` — new modules name no reason as a string literal (AC20; grep over `criteria.mjs`, `plan*.mjs`, `snapshot*.mjs`) | flip `REASONS.criteria_not_found` → `'criteria_not_found'` in `criteria.mjs` |
| `selvedge/tests/test-plan-validate.sh` — schema per-type field names == `plan-steps.mjs` field sets (AC20) | drop `exact` from the `click` locator field set in `plan-steps.mjs` |
| `selvedge/tests/test-plan-validate.sh` — every `PLAN_PROBLEMS` code is in the README list (AC20) | add one code to `PLAN_PROBLEMS` in `plan-validate.mjs` without a README line |
| `selvedge/tests/test-snapshot.sh` — resolved `{{SHOP_USER}}` value reaches the page (AC16: the fixture echoes the field into the tree) | flip `resolvePlaceholders(steps, env)` → `steps` in `snapshot.mjs` |
| `selvedge/tests/test-snapshot.sh` — fresh context per call (AC11a: a cookie set in call 1 is absent in call 2's tree) | reuse one module-level context across calls in `snapshot.mjs` |
| `selvedge/tests/test-snapshot.sh` — prefix `goto` to an unlisted origin → `BLOCKED host_not_allowed`, fixture zero connections, `browser_launched: false` (AC9) | delete the prefix `goto` origin check before launch in `snapshot.mjs` |
| `selvedge/tests/test-plan.sh` — gate-scopes hand-off names `plan_time_actions` and `freeze.json` (AC21) | delete the `### Hand-off to item 04` subsection in `selvedge/docs/evidence/gate-scopes.md` |

Each pin is a test arm that turns red under its mutation; `test-*.sh` arms print `ok`/`FAIL` lines like `test-cli.sh` and exit non-zero on any FAIL.

**Test isolation (every new test):** a fresh temporary `HOME` and a temp git repo as the target project per test file; `selvedge/tests/lib/playwright-cache.sh` sourced before `HOME` moves (browser arms: `test-snapshot.sh`, `test-plan.sh` AC8), with its bimodal rule (CI install failure = hard FAIL `playwright_install_failed`; locally SKIP of browser arms only); every fixture server closed by its driver; `gh` and `claude` are PATH stubs (no network, no model). `SELVEDGE_PLANNER`, `SELVEDGE_SNAPSHOT_BUDGET`, `SELVEDGE_PLAYWRIGHT_MODULE` are scrubbed with `env -u` where an arm asserts their unset path.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | `criteria` commands + testability pre-check; step registry; `plan --validate` lint; schemas; ten new `REASONS` + README rows | AC1–AC5, AC12, AC13, AC20 | 4 modify, 8 create | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` | LAUNCHABLE |
| 2 | `selvedge snapshot` (Playwright resolution, guarded prefix executor, budget, `snapshots.jsonl`) + fixture app | AC7, AC9, AC10, AC11a, AC15–AC17 | 1 modify, 4 create | `skills/playwright-e2e/SKILL.md`, `skills/unit-testing/SKILL.md` | BLOCKED (by #1) |
| 3 | `selvedge plan` (init, planner, freeze, revisions), `prompts/planner.md`, modal end-to-end; README, gate-scopes (incl. item-04 hand-off), 0.3.0 release | AC4b, AC6, AC8, AC11, AC14, AC18, AC19, AC21 | 6 modify, 6 create | `skills/unit-testing/SKILL.md`, `skills/playwright-e2e/SKILL.md` | BLOCKED (by #2) |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "selvedge/lib/criteria.mjs"}
  - {kind: "symbol", path: "selvedge/lib/criteria.mjs", name: "classifyTestability"}
  - {kind: "symbol", path: "selvedge/lib/criteria.mjs", name: "criteriaSha256"}
  - {kind: "file", path: "selvedge/lib/plan-steps.mjs"}
  - {kind: "symbol", path: "selvedge/lib/plan-steps.mjs", name: "STEP_TYPES"}
  - {kind: "symbol", path: "selvedge/lib/plan-steps.mjs", name: "validateSteps"}
  - {kind: "symbol", path: "selvedge/lib/plan-steps.mjs", name: "resolvePlaceholders"}
  - {kind: "file", path: "selvedge/lib/plan-validate.mjs"}
  - {kind: "symbol", path: "selvedge/lib/plan-validate.mjs", name: "validatePlan"}
  - {kind: "symbol", path: "selvedge/lib/plan-validate.mjs", name: "PLAN_PROBLEMS"}
  - {kind: "file", path: "selvedge/lib/plan.mjs"}
  - {kind: "file", path: "selvedge/schemas/criteria.schema.json"}
  - {kind: "file", path: "selvedge/schemas/plan.schema.json"}
  - {kind: "symbol", path: "selvedge/lib/env-config.mjs", name: "exploration_budget"}
  - {kind: "symbol", path: "selvedge/README.md", name: "criterion_not_testable"}
  - {kind: "symbol", path: "selvedge/bin/selvedge", name: "criteria)"}
  - {kind: "file", path: "selvedge/tests/test-criteria.sh"}
  - {kind: "file", path: "selvedge/tests/test-plan-validate.sh"}
requires: []
lanes:
  - "selvedge/bin/selvedge"
  - "selvedge/lib/criteria*"
  - "selvedge/lib/plan-steps.mjs"
  - "selvedge/lib/plan-validate.mjs"
  - "selvedge/lib/plan.mjs"
  - "selvedge/lib/env-config.mjs"
  - "selvedge/schemas/criteria.schema.json"
  - "selvedge/schemas/plan.schema.json"
  - "selvedge/tests/test-criteria.sh"
  - "selvedge/tests/test-plan-validate.sh"
  - "selvedge/tests/test-env.sh"
  - "selvedge/README.md"
external_requires:
  - "Node.js >= 18 on PATH"
  - "gh CLI for `criteria from-pr` (stubbed on PATH in tests)"

# Subtask 2
provides:
  - {kind: "file", path: "selvedge/lib/snapshot.mjs"}
  - {kind: "file", path: "selvedge/lib/snapshot-playwright.mjs"}
  - {kind: "symbol", path: "selvedge/lib/snapshot-playwright.mjs", name: "resolvePlaywright"}
  - {kind: "symbol", path: "selvedge/bin/selvedge", name: "snapshot)"}
  - {kind: "file", path: "selvedge/tests/fixtures/app-server.mjs"}
  - {kind: "file", path: "selvedge/tests/test-snapshot.sh"}
requires:
  - {from: "1", kind: "symbol", path: "selvedge/lib/plan-steps.mjs", name: "validateSteps"}
  - {from: "1", kind: "symbol", path: "selvedge/lib/plan-steps.mjs", name: "resolvePlaceholders"}
  - {from: "1", kind: "symbol", path: "selvedge/lib/env-config.mjs", name: "exploration_budget"}
lanes:
  - "selvedge/bin/selvedge"
  - "selvedge/lib/snapshot*"
  - "selvedge/tests/fixtures/app-server.mjs"
  - "selvedge/tests/test-snapshot.sh"
external_requires:
  - "playwright (resolved from the target repo or SELVEDGE_PLAYWRIGHT_MODULE; tests use the PW_VERSION pin in selvedge/tests/lib/playwright-cache.sh) + its Chromium build"
  - "item 02's openGuardedContext in selvedge/lib/runner/route-guard.mjs (merged, not modified)"

# Subtask 3
provides:
  - {kind: "file", path: "selvedge/lib/plan-runs.mjs"}
  - {kind: "symbol", path: "selvedge/lib/plan-runs.mjs", name: "freezeRun"}
  - {kind: "symbol", path: "selvedge/lib/plan-runs.mjs", name: "nextPlanRevision"}
  - {kind: "file", path: "selvedge/lib/plan-planner.mjs"}
  - {kind: "symbol", path: "selvedge/lib/plan-planner.mjs", name: "runPlanner"}
  - {kind: "file", path: "selvedge/prompts/planner.md"}
  - {kind: "file", path: "selvedge/tests/fixtures/stub-planner.sh"}
  - {kind: "file", path: "selvedge/tests/fixtures/stub-claude.sh"}
  - {kind: "file", path: "selvedge/tests/test-plan.sh"}
  - {kind: "symbol", path: "selvedge/CHANGELOG.md", name: "## 0.3.0"}
  - {kind: "symbol", path: "selvedge/README.md", name: "SELVEDGE_PLANNER"}
  - {kind: "symbol", path: "selvedge/docs/evidence/gate-scopes.md", name: "### Hand-off to item 04"}
requires:
  - {from: "1", kind: "symbol", path: "selvedge/lib/plan-validate.mjs", name: "validatePlan"}
  - {from: "1", kind: "symbol", path: "selvedge/lib/criteria.mjs", name: "classifyTestability"}
  - {from: "2", kind: "symbol", path: "selvedge/bin/selvedge", name: "snapshot)"}
  - {from: "2", kind: "file", path: "selvedge/tests/fixtures/app-server.mjs"}
lanes:
  - "selvedge/lib/plan.mjs"
  - "selvedge/lib/plan-runs.mjs"
  - "selvedge/lib/plan-planner.mjs"
  - "selvedge/prompts/**"
  - "selvedge/tests/fixtures/stub-planner.sh"
  - "selvedge/tests/fixtures/stub-claude.sh"
  - "selvedge/tests/test-plan.sh"
  - "selvedge/README.md"
  - "selvedge/docs/evidence/gate-scopes.md"
  - "selvedge/CHANGELOG.md"
  - "selvedge/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
external_requires:
  - "claude CLI for the default planner at use time (never called in tests: PATH stub)"
```

**Worker notes:**
- `plan.json` shape: `{schema_version: 1, target: "web", criteria_sha256, plan_revision?, origins: [...], steps_by_criterion: {"<id>": {interpretation, polarity: "positive"|"negative", unverified_assumptions: [{text, material}], steps: [...]}}, not_planned: [{id, reason: criterion_not_testable|side_effect_not_observable|exploration_budget, rewrite?, detail?}]}`. `--freeze` stamps `plan_revision` (overwriting any planner value), writes `plan.json` (2-space, trailing newline), then hashes the written bytes. Steps: `goto {url}`; `click {locator}`; `fill {locator, value}`; `select {locator, value}`; `check {locator, checked?}`; `press {key, locator?}`; `wait_for {locator, state}`; `read {property, locator?}` (`text`, `value`, `checked`, `count`, `attribute:<name>`, `url` — `url` takes no locator); `expect {op, value}` (`equals`, `contains`, `matches`, `gt`, `lt`, `changed_from` — `changed_from` value is a boolean: whether the last read must differ from the previous read of the same locator/property, the negative baseline form).
- README (S1 and S3): only the reasons table may have rows shaped `| \`<lowercase_name>\` |` — write the `PLAN_PROBLEMS` list and step types as bullet lists (see the README invariant above), or `test-env.sh`'s README-sync arm fails.
- `runs.jsonl` lives at `<repo root>/.selvedge/runs.jsonl`; this item appends only `{"event":"freeze", ts, run_id, criteria_sha256, plan_sha256, plan_revision, plan_time_actions, planner_tokens}`. Item 04 appends `event: "run"` lines and counts revisions the same way — `nextPlanRevision` is exported for it. Run id: `<UTC YYYYMMDDTHHMMSSZ>-<6 random hex>`.
- `selvedge plan` flow: `--init <criteria.json>` (creates the folder, copies `criteria.json`, prints the folder path) → planner → `--validate` → `--freeze`. Bare `selvedge plan <criteria.json>` does all four. `--base <ref>` passes through to `loadConfig` for the origin allowlist, as `env check --base` does.
- `snapshot` output (stdout, one JSON object): `{schema_version: 1, url, steps_run, failed_step: null|<index>, error: null|<first line>, aria_snapshot}` from `page.locator('body').ariaSnapshot()`; exit 0 ok, 1 a prefix step failed (tree still printed), 2 usage/BLOCKED, 3 `NOT_VERIFIABLE exploration_budget`. `--run-dir` (or `SELVEDGE_RUN_DIR`) is required, so the budget always has a home. `storageState` (item 05) is not built yet; the context options take it when item 05 lands.

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2 ──→ Subtask 3
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | `selvedge/bin/selvedge` (legal: 2 reachable from 1) | YES (requires) |
| Subtask 1 | Subtask 3 | `selvedge/lib/plan.mjs`, `selvedge/README.md` (legal: 3 reachable from 1) | YES (requires) |

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
| 3 | `skills/unit-testing/SKILL.md`, `skills/playwright-e2e/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): Playwright becomes a runtime dependency resolved from the target repo; its version follows that repo | MEDIUM | Owner-confirmed (Design decision 1); `resolvePlaywright` returns the version for item 04's evidence; `BLOCKED playwright_unavailable` names both lookup paths |
| Feasibility (Phase 2.5): context-bound size (~26 files) | MEDIUM | 3 ordered subtasks on one worker; S2/S3 import S1's `validateSteps` rather than re-implementing it |
| Feasibility (Phase 2.5): two requirement lines describe item 04 (run PASS, `verdict.json` `plan_time_actions`), and item 04's requirement does not mention either | MEDIUM | Owner decision LP-CLARIFY 2026-11-15 "Prove what 03 owns": AC8 proves the locators resolve, AC11 records `plan_time_actions` in `freeze.json` + `runs.jsonl`; AC21 writes the hand-off into committed `selvedge/docs/evidence/gate-scopes.md` (`### Hand-off to item 04`), and Launch Pad's run summary asks the owner to add both clauses to `.supervisor/requirements/qa-split/04-…md` (outside this item's Touches, so not edited here) |
| Feasibility (Phase 2.5): paths outside the item's Touches (`selvedge/lib/env-config.mjs` for `REASONS`, `selvedge/README.md`, `selvedge/docs/evidence/gate-scopes.md`, the three release files) | LOW | Asked once at Phase 6 (`LP-SCOPE`); each follows the item 02 release convention and the one-reason-list rule |
| Deterministic vague-phrase list misses vague criteria or flags testable ones ("totals are correctly computed as 12") | MEDIUM | A quoted literal or a digit exempts a criterion; the planner may also mark criteria `criterion_not_testable`; the list is one frozen constant, cheap to tune |
| Code-like detection false positives on legitimate text (a product named `window.store`) | LOW | The rejection names the field; the planner can rephrase the locator to role/name; the list is in one place (`plan-steps.mjs`) |
| `runs.jsonl` revision counting races when two freezes run at once | LOW | Append-only one line per freeze; revisions are an audit trail, not a lock (00-plan D6 "the revision record is an audit trail, not immutability") |
| CI `static` time: two more browser test files on each run | MEDIUM | Reuse the same cached install; keep browser arms few (AC7–AC10, AC15–AC17 in one driver process, AC8 one more); record the selvedge step's wall time in `gate-scopes.md` |
| The default planner (`claude -p`) is never exercised against a real model in CI | MEDIUM | AC18 pins its argv and parsing with a PATH stub; a real-model trial is item 06/06c's measurement |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 3
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
`/supervisor job: .supervisor/jobs/pending/2026-11-15-qa-split-03-frozen-validated-step-plan.md`

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-11-15T13:05:42Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/924
- **Branch:** feature/qa-split-03-frozen-validated-step-plan
- **Files changed:** 26
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** unarmed (marker_missing)
- **Summary:** selvedge criteria / snapshot / plan (--init/--validate/--freeze) + 0.3.0 release in 3 sequential subtasks; Phase 4.5 fixed 10 findings over 3 rounds (base propagation to planner snapshots, secret redaction in every Playwright encoding, vacuous final-expect lint, run-dir pinning, shared isMain); the round-3 vacuous-matches fix (6d9c5ca) was not re-reviewed — escalated for a human eyeball. selvedge gate PASS on 6d9c5ca; ground truth 2/2. Open owner decision: declared-only {{NAME}} placeholders. 3 LOW follow-ups dismissed.

## Not verified
- **selvedge criteria from-pr against a real GitHub PR** — tests use a PATH-stub gh only (no network) (subtask 1)
- **default claude -p planner invoking snapshot through --allowedTools** — subtask 3 owns the planner (subtask 2)
- **snapshot --base <ref>** — no snapshot arm exercises it (subtask 2)
- **test-snapshot.sh on Linux CI** — run on macOS only locally (subtask 2)
- **project-resolve against a real target repo's installed playwright** — only a stub node_modules/playwright package was exercised (subtask 2)
- **default planner against a real claude model** — argv and parsing pinned only by the PATH-stub claude (subtask 3)
- **claude permission rule Bash(<bin> snapshot:*) admitting the --steps /dev/stdin heredoc form** — needs a real claude -p session (subtask 3)
- **test-plan.sh on GitHub CI (Linux)** — run on macOS only locally (subtask 3)
