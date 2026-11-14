# Criteria become a frozen, validated step plan before anything runs

## Status: pending

> Phase 1, item 03 of `qa-split/00-plan.md` (rev 2, approved 2026-11-12).
> Decisions: D6 (only the plan step uses a model; plan hashed; rev 3 revisions), D7 (static PASS rule; rev 3
> negative criteria + assumptions), D17 (target-agnostic
> schema), P2/P3 (criteria inputs, testability pre-check). Red-team findings: F1, C4, C6.

## Why

The model is good at turning "the cart total updates when quantity changes" into locators and expected
values, and bad at being the judge. So the model only *plans*: it writes typed steps, and the run (item 04)
executes them with no model. A static lint makes the PASS rule ("a value read after the last action")
checkable before anything runs, and the hash makes the plan immutable once written.

## Design

- **`criteria.json`** in: `{schema_version, source, criteria: [{id, text}]}`. Built by
  `selvedge criteria from-pr <n>` (PR body via `gh`), `from-md <file>` (a `- ` list) and `from-text`
  (stdin, e.g. a pasted ticket). Same criteria text → same `criteria.json` (ids are stable hashes of text).
- **Testability pre-check:** each criterion is classified `testable` / `vague` with a suggested rewrite for
  vague ones ("works well", "looks right", no observable value). Vague criteria are not planned; they go to
  the verdict as NOT_VERIFIABLE `criterion_not_testable` with the rewrite.
- **`selvedge snapshot <url> [--steps <prefix.json>]`:** returns the accessibility snapshot (Playwright
  `ariaSnapshot`) of a page on an allowed origin, through item 02's proxy and route guard. The only way the
  planner sees the app. With `--steps`, it first runs a short prefix of typed steps (the plan step types
  except `read`/`expect`), then returns the tree, so the planner can see what only appears after actions:
  a modal, a cart drawer, step 3 of a form. The model still never drives the browser; this is how the
  planner explores without the live MCP loop of Playwright's Test Agents planner.
  - The prefix passes the same validator as a plan (unknown type/field, code-like content, unlisted `goto`
    origin → exit 2) and runs under the same proxy, mutation rule and `{{NAME}}` resolution, in a fresh
    browser context per call (with item 05's `storageState` when present).
  - Bounded: at most 15 steps per prefix and a per-plan cap on snapshot calls (config, default 20); beyond
    it → the criterion is NOT_VERIFIABLE `exploration_budget`.
  - A prefix step that fails returns the tree at the failing step plus the step index, so the planner can
    correct its locator.
  - Plan-time actions change app state. Every prefix step that clicks/fills/presses is counted as a
    plan-time action in `.selvedge/runs/<run-id>/snapshots.jsonl` (prefix, step count, outcome; no page
    text). Before `run`, an approved `reset` hook runs; with none, `verdict.json` records
    `plan_time_actions: N` so a surprising result can be traced.
- **`plan.json`:** `{schema_version, target: "web", criteria_sha256, origins, steps_by_criterion}`. Step
  types only: `goto`, `click`, `fill`, `select`, `check`, `press`, `wait_for`, `read`, `expect`.
  Locators are Playwright role/label/text/test-id locators, never CSS or XPath. `fill` values may be literal
  or `{{NAME}}` (resolved from env by the runner). `read` names a property (`text`, `value`, `checked`,
  `count`, `attribute:<name>`, `url`); `expect` compares the last read (`equals`, `contains`, `matches`,
  `gt`/`lt`, `changed_from`). The schema has `target` from v1 even though only `web` exists (D17).
- **Per criterion, rev 3:** `interpretation` (one sentence: what the planner thinks the criterion means),
  `polarity` (`positive` / `negative`), and `unverified_assumptions: [{text, material}]`. A criterion with
  any `material: true` assumption is still planned and run, but its verdict is capped at NOT_VERIFIABLE
  `material_assumption` (item 04). A `negative` criterion ("must not …") proves the prohibited side effect
  is absent: it reads a baseline of that side effect before the action and reads it again after
  (e.g. `count` unchanged, `changed_from` false). If the planner can't name an observable side effect, the
  criterion goes to the verdict as NOT_VERIFIABLE `side_effect_not_observable`, not planned.
- **`selvedge plan`:** calls the planner from `SELVEDGE_PLANNER` (default: `claude -p` with a fixed prompt
  from `selvedge/prompts/planner.md`, a model and a token budget from config). The planner gets the criteria
  and may request snapshots; it returns `plan.json`. Writes `plan.json` + `plan.sha256` into
  `.selvedge/runs/<run-id>/`. Records tokens used.
- **`selvedge plan --validate <plan>`:** rejects (exit 2, every problem listed) if: a criterion's steps do
  not end in `read` followed by `expect`; an `expect` checks only existence/visibility; an unknown step type
  or field appears; a `goto` origin is not allowed; a step contains anything that looks like code.
  It also rejects: a missing `interpretation` or `polarity`; a `negative` criterion with no baseline `read`
  before its first action, or whose only check is that a UI element is absent or hidden.
  `plan` always runs `--validate` before writing the hash.
- In a Claude session, the verifier subagent (item 06) writes `plan.json` itself and calls `--validate`
  then `selvedge plan --freeze`, which validates and writes the hash. Both paths produce the same artifacts.
- **Revisions (D6 rev 3):** `--freeze` is one-shot per run folder; a second freeze in the same folder exits
  2 `already_frozen`. A new plan for the same `criteria_sha256` goes in a new run folder and is recorded as
  revision N+1 (`plan_revision` in `plan.json`, counted from `.selvedge/runs.jsonl`). Nothing is deleted:
  every earlier revision's plan and verdict stay in their folders.

## Acceptance criteria (each a test)

- A plan whose criterion ends in `click` → rejected, naming the criterion.
- An `expect` of `visible` only → rejected.
- A step with an unknown type or extra field → rejected.
- A vague criterion ("the page looks good") → NOT planned; carried as `criterion_not_testable` with a rewrite.
- `from-pr`, `from-md` and `from-text` with the same three criteria → byte-identical `criteria.json`.
- `plan` with a stub `SELVEDGE_PLANNER` (fixture script) writes `plan.json` + matching `plan.sha256`.
- `snapshot` of an unlisted origin → BLOCKED `host_not_allowed` (reuses item 02's guard).
- A fixture criterion whose target sits inside a modal opened by a button: with `snapshot --steps` the stub
  planner gets the modal's tree and the plan's locators resolve (the run PASSes); without the prefix the
  modal's controls are absent from the tree.
- A prefix with an unknown step type, or a `goto` to an unlisted origin → rejected / BLOCKED, nothing runs.
- The 21st snapshot call in one plan → NOT_VERIFIABLE `exploration_budget`.
- `snapshots.jsonl` counts plan-time actions; with no `reset` hook, `verdict.json` carries
  `plan_time_actions`.
- A `negative` criterion with no baseline read, or checking only that a button is hidden → rejected.
- A plan missing `interpretation` → rejected.
- A second `--freeze` in the same run folder → exit 2 `already_frozen`; a new folder for the same criteria
  → `plan_revision: 2`.

## Depends on

02

## Touches

- `selvedge/bin/selvedge`, `selvedge/lib/criteria*`, `selvedge/lib/plan*`, `selvedge/lib/snapshot*`
- `selvedge/schemas/{criteria,plan}.schema.json`, `selvedge/prompts/planner.md`, `selvedge/tests/**`
