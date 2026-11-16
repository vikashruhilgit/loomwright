# Changelog

All notable changes to the selvedge plugin. Selvedge releases on its own: each release bumps
`selvedge/.claude-plugin/plugin.json`, its entry in `.claude-plugin/marketplace.json` and this
file together, never through the repository's `changelog.d/` fragments (those fold into
Loomwright's version only).

Format: each release is a heading `## <X.Y.Z> — <YYYY-MM-DD>`; the first such heading is the
current release, and `selvedge/tests/run.sh` checks it equals `plugin.json`'s `version`.

## 0.4.0 — 2026-11-16

- `selvedge run <run-dir>` executes a frozen `plan.json` in the guarded browser with no model call.
  It refuses, before anything is written or launched, a folder with no `plan.sha256`
  (`not_frozen`), one that already ran (`already_run`) and a `plan.json` whose sha256 changed
  (`plan_modified`). Each criterion runs in a fresh guarded context. The runner writes every line of
  `evidence.jsonl` itself (`run_start`, one `step` line per executed step, `criterion_end`,
  `run_end`; every `{{NAME}}` value written back as `{{NAME}}`) and one end-state screenshot per
  criterion. An `expect` that would FAIL gets a stable wait (network idle, then a settled DOM, within
  5 s) and one re-read. A step that throws is BLOCKED `step_failed` (with its index), three no-change
  actions in a row are BLOCKED `stuck_screen`, and `SELVEDGE_RUN_BUDGET_MS`,
  `SELVEDGE_PLANNER_TOKEN_BUDGET` and `SELVEDGE_STEP_TIMEOUT_MS` bound the run. Approved `reset` /
  `seed` hooks run before the first browser (`data_state: managed`); an unapproved one blocks every
  criterion (`env_hooks_unapproved`). Each run appends exactly one `event: "run"` line to
  `.selvedge/runs.jsonl` (`entry` from `SELVEDGE_ENTRY`: `session`, `ci` or `loomwright`).
- `selvedge verdict <run-dir>` derives PASS / FAIL / BLOCKED / NOT_VERIFIABLE per criterion from
  `evidence.jsonl` and `plan.json` only, into `verdict.json` (schema in
  `schemas/verdict.schema.json`): an empty read is NOT_VERIFIABLE `no_value_read`, never PASS; any
  mismatched `expect` in a criterion FAILs it, carrying `read_value` and `expected` (`changed_from`
  compares a read with the previous read of the same locator and property); a material assumption is NOT_VERIFIABLE
  `material_assumption`; an interrupted criterion is BLOCKED `run_interrupted`; `prior_revisions`
  lists earlier revisions' verdicts. Exit precedence: 1 FAIL, 2 BLOCKED, 3 NOT_VERIFIABLE, 0. `run`
  calls the same derivation; re-running `verdict` appends nothing.
- `selvedge run --replay <frozen-run-dir>` runs a frozen plan again, byte for byte, in a new run
  folder (`replay_of` the frozen run id, the same `plan_revision`, `planner_tokens` 0). A
  `plan.json` that differs from `plan.sha256` or from the run's freeze line in `runs.jsonl` is
  `plan_modified` and no folder is created; a control the frozen locator no longer matches is
  BLOCKED `step_failed`.
- `selvedge run --trace` keeps a Playwright trace per criterion as `traces/<criterion-id>.zip`, with
  `Cookie` / `Set-Cookie` / `Authorization` values, every cookie value seen and every resolved
  `{{NAME}}` value removed. Selvedge rewrites the zip itself on `node:zlib`; a trace it cannot redact
  whole is dropped, never kept.
- `selvedge env init` first adds `.selvedge/` to the repo's `.gitignore` (once, even when
  `selvedge.json` exists or init fails).
- Ten new reasons: `step_failed`, `stuck_screen`, `budget_exceeded`, `run_interrupted` (BLOCKED),
  `no_value_read`, `material_assumption` (NOT_VERIFIABLE), `plan_modified`, `already_run`,
  `not_frozen`, `evidence_missing` (usage). The plan-step executor moved from `lib/snapshot.mjs` to
  `lib/runner/steps.mjs` (one executor for `snapshot` and `run`).

## 0.3.0 — 2026-11-15

- Criteria become a frozen, validated step plan. `selvedge criteria from-pr|from-md|from-text`
  turns acceptance criteria into `criteria.json` (stable `c-<12 hex>` ids, the same bytes from any
  input; schema in `schemas/criteria.schema.json`), and `criteria check` flags vague criteria with a
  deterministic phrase list and a suggested rewrite.
- `selvedge snapshot <url> [--steps <prefix.json>] --run-dir <dir>`: an allowed page's
  accessibility tree through the browser guard, after an optional prefix of up to 15 action steps.
  Unlisted origins, bad prefixes, unset `{{NAME}}` placeholders and a missing Playwright are refused
  before any browser launches. Each call is recorded in `snapshots.jsonl` (no page text) and
  counts against `SELVEDGE_SNAPSHOT_BUDGET` (default 20 per run folder; past it,
  `NOT_VERIFIABLE exploration_budget`, exit 3). Playwright is resolved at run time from
  `SELVEDGE_PLAYWRIGHT_MODULE` or the target project's own `node_modules`.
- `selvedge plan`: `--init` makes a run folder `.selvedge/runs/<run-id>/`; the planner
  (`SELVEDGE_PLANNER`, or by default `claude -p` with the fixed prompt `prompts/planner.md` and only
  `snapshot` allowed) never receives a vague criterion, which `plan` lists under `not_planned`
  itself; `--validate` lints the plan (the PASS rule — a value read after the last action —,
  existence-only checks, negative baselines, interpretation/polarity/assumptions, coverage,
  `criteria_sha256`, step types, fields, locators, code-like content, goto origins; every problem
  listed); `--freeze` lints, stamps `plan_revision`, and writes `plan.sha256` (the hash of the
  bytes written) and `freeze.json`. A frozen folder is never written again (`already_frozen`); each
  re-plan of the same criteria is the next revision, counted from `.selvedge/runs.jsonl`. Planner
  tokens and the snapshot `plan_time_actions` sum are recorded in `freeze.json` and the
  `runs.jsonl` freeze line. Schema in `schemas/plan.schema.json` (`target: "web"`).
- The planner sees no more than the plan: `plan --base <ref>` hands it `SELVEDGE_BASE` (empty for
  the working tree), so every `snapshot` it runs reads the same allowlist, and a `snapshot` whose
  `--base` or `--run-dir` names another source or folder than `SELVEDGE_BASE` / `SELVEDGE_RUN_DIR`
  is a usage error. A resolved `{{NAME}}` value is printed as `{{NAME}}` (tree, error, stderr; as given
  and as Playwright quotes it); any variable name still resolves (an open item, see the README). The lint
  also rejects a final expect any value meets (`contains` a blank string, `matches` a pattern
  matching the empty string or every one of a fixed set of unlike one-line texts, `read count` then
  `lt`) as `existence_only_expect`.
- Ten new reasons: `playwright_unavailable`, `placeholder_unset` (BLOCKED),
  `criterion_not_testable`, `side_effect_not_observable`, `exploration_budget` (NOT_VERIFIABLE, exit
  3), `already_frozen`, `plan_invalid`, `criteria_invalid`, `criteria_not_found`, `planner_failed`.
- Tests: `test-criteria.sh`, `test-plan-validate.sh`, `test-snapshot.sh` and `test-plan.sh` (the
  last two against real Chromium and a fixture app; the planner and `claude` are stubs).

## 0.2.0 — 2026-11-14

- Target safety. A committed `selvedge.json` (schema in `schemas/selvedge-config.schema.json`)
  lists the exact origins the checker's browser may reach; remote origins need `allow_remote`,
  any method other than GET, HEAD or OPTIONS to a remote origin needs `allow_remote_mutation`.
- `selvedge env check|init|approve|hook` (Node.js >= 18). `--base <ref>` reads the committed
  `<ref>:selvedge.json`, so a pull request cannot widen its own allowlist or change its hooks'
  command text. Env hooks run only under a user-scoped sha256 approval in
  `$HOME/.claude/selvedge/approvals.json`, recorded by `env approve` on a TTY, and never while any
  origin is remote. Limit: the approval pins the command text, not the files a hook runs, so a hook
  that calls a repo script runs that script as it is in the current checkout.
- The browser guard: a runner-owned forward proxy (`lib/runner/proxy.mjs`, exact-origin checks,
  one DNS lookup per remote connection with private, loopback, link-local, unique-local, multicast,
  unspecified or reserved results refused, including
  NAT64 and 6to4 addresses that embed a private IPv4, the validated address dialled) and a
  `context.route` second layer (`lib/runner/route-guard.mjs`, service workers blocked, Playwright
  injected by the caller) that also checks each redirect hop that keeps a non-read method (307/308,
  and 301/302 for any method but POST) when a remote origin is listed without
  `allow_remote_mutation`; a request it sends after the proxy is gone is `proxy_unavailable`. It
  follows such a hop itself only for redirect mode `follow` (an init script tags each non-read
  `fetch` with its redirect and credentials modes), dropping `Authorization` and cookies on a
  cross-origin hop as a browser would; for `manual`, `error` or an untagged `fetch` it never sends
  the hop and hands the page the redirect with its `Location` withheld. Every refusal is a named BLOCKED
  reason; the README's reasons table is checked against the code's list.
- Tests: `test-env.sh`, `test-proxy.sh` and `test-route-guard.sh`, the last against real Chromium
  from a pinned Playwright installed into a selvedge-owned cache (`tests/lib/playwright-cache.sh`).

## 0.1.0 — 2026-11-13

- First release: the plugin scaffold. Manifest, the `selvedge` CLI (`--version`, `install-cli`,
  which links the CLI into `~/.local/bin`), and the plugin's own release gate
  (`selvedge/tests/run.sh`, run by CI's `static` job).
- `docs/cli-discovery.md` records whether a plugin's `bin/` reaches `PATH`.
