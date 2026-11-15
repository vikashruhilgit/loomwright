# Changelog

All notable changes to the selvedge plugin. Selvedge releases on its own: each release bumps
`selvedge/.claude-plugin/plugin.json`, its entry in `.claude-plugin/marketplace.json` and this
file together, never through the repository's `changelog.d/` fragments (those fold into
Loomwright's version only).

Format: each release is a heading `## <X.Y.Z> — <YYYY-MM-DD>`; the first such heading is the
current release, and `selvedge/tests/run.sh` checks it equals `plugin.json`'s `version`.

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
  matching the empty string or any one character, `read count` then `lt`) as `existence_only_expect`.
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
