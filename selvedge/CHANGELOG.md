# Changelog

All notable changes to the selvedge plugin. Selvedge releases on its own: each release bumps
`selvedge/.claude-plugin/plugin.json`, its entry in `.claude-plugin/marketplace.json` and this
file together, never through the repository's `changelog.d/` fragments (those fold into
Loomwright's version only).

Format: each release is a heading `## <X.Y.Z> — <YYYY-MM-DD>`; the first such heading is the
current release, and `selvedge/tests/run.sh` checks it equals `plugin.json`'s `version`.

## 0.7.0 — 2026-11-18

- `selvedge doctor` checks, one line each, Node >= 18, the Playwright library (found exactly as `run`
  finds it: `SELVEDGE_PLAYWRIGHT_MODULE`, else the repo's own `node_modules`), that Playwright's
  Chromium on disk, `selvedge.json` (present and valid), hook approvals ("no hooks" when there are
  none) and the planner (`SELVEDGE_PLANNER` set, or `claude` on `PATH`). Each line is `ok <check>`
  or `FAIL <check>: <the one fix>`; exit 0 when all pass, 1 when any fails. The checks live in
  `lib/doctor.mjs` and call the helpers `run`, `snapshot` and `plan` use; the Node check also runs
  in bash first, so a missing or older Node prints its `FAIL` line and
  `skipped: the other checks need Node` instead of crashing.
- `selvedge sample-app [--port N]` serves the bundled fixture app (`tests/fixtures/app-server.mjs`)
  on `http://localhost:N` (default 4173) in the foreground until Ctrl-C, with no watchdog, and prints
  its origin and the `selvedge env init --port N` line. Before it listens it connects to
  127.0.0.1:N and [::1]:N (`localhost` can resolve to either): a connection accepted on either
  (a server bound to 127.0.0.1, to ::1, or to the wildcard, which a bind on 127.0.0.1 alone would
  sit beside) exits 1 naming the port, as does the listen's own EADDRINUSE.
  `startAppServer()` takes an optional port; with none it still binds a random one.
- The README opens with a **Quick start** (install → `install-cli` → a demo folder with Playwright
  → `env init` → `doctor` → `sample-app` → `/selvedge:verify` with three example criteria → the
  verdict table, each command with its expected output) and **Honest limits** (web only, what
  BLOCKED and NOT_VERIFIABLE mean, the secret limit, no accuracy numbers before the Phase 2
  measurement). `docs/quick-start-timing.md` records the timed rehearsal and holds the owner's
  fresh-account run.

## 0.6.0 — 2026-11-18

- `selvedge comment <run-dir> --pr <n> [--yes] [--base <ref>] [--allow-public-values]` posts a run
  folder's verdicts to the PR as ONE comment, found by its `<!-- selvedge:verdict -->` marker on a
  comment authored by the account `gh` is signed in as, and updated in place (`PATCH`); it creates
  one only when no such comment exists, never touches a comment without the marker or one by another
  author, and exits 1 without posting when the signed-in login cannot be read. The body reaches `gh` as a file, never as command-line text. It is
  text only: a summary line, the short plan sha256 and revision, and per criterion the text, verdict,
  interpretation, assumptions, steps as type and locator, the expected value, matched, the evidence
  class and, for BLOCKED / NOT_VERIFIABLE, the reason with an unblock hint. Every URL is cut to its
  path; no `fill` / `select` value, `{{NAME}}` value, header name or evidence file name is shown.
- `selvedge.json` takes a `comment` key: `read_values` (default `false`) and `redact` (default `[]`,
  JavaScript regular expressions). `comment` reads it from the PR's base branch only, never the
  working tree. With the opt-in, a repo that is not `PRIVATE` (or whose visibility cannot be read)
  is refused `read_values_public_repo` unless `--allow-public-values` is given, and every published
  value is redacted (emails, runs of 6+ digits, URL query strings, 32+ character tokens, then the
  configured patterns).
- A later plan revision shows each criterion's own verdict on every earlier plan (`FAIL on plan 1 →
  PASS on plan 2`, `not run on plan <r>`, or the whole run's verdict labelled `(whole run)` when
  the earlier run folder is gone), and the summary counts `PASS after revision` separately.
- New reasons: `read_values_public_repo`, `comment_requires_yes` (no `--yes` and stdin not a
  terminal) and `verdict_missing` (no `verdict.json` in the run folder).
- The Claude Code adapter: `/selvedge:verify [PR number | criteria file | pasted criteria]` resolves
  the source to `selvedge criteria from-pr | from-md | from-text`, spawns the `verifier` subagent
  (tools: Bash and Read only) that runs `criteria`, `plan --init`, `snapshot`, `plan --validate`,
  `plan --freeze`, `run` and `verdict`, reports the table from `verdict.json`, and for a PR posts
  through `selvedge comment … --yes` only after asking. The verifier never edits `plan.json` after
  the freeze and never reads `~/.local/state/selvedge/`.
- `skills/verify/SKILL.md` carries the same workflow, in the same command order, for any agent
  host; `selvedge/tests/test-adapter.sh` pins the tools, the order, the prohibitions, the token
  budget, the posting rule and the plugin description (<= 600 characters, no version token, equal
  to the marketplace entry's). A live session's verdict equals a hand-run `run --replay` of the same
  frozen plan: [`docs/evidence/verify-adapter-equivalence.md`](docs/evidence/verify-adapter-equivalence.md).

## 0.5.0 — 2026-11-17

- `selvedge.json` takes an `auth` key: `env` (the names, never the values, of the environment
  variables the sign-in reads) and `signed_in_check` (`url` on a listed origin, and one plan-step
  locator that matches only when signed in). Every command that loads the config refuses an unknown
  `auth` or `signed_in_check` key, a bad variable name, a check URL on an unlisted origin and a locator
  that is not an object (`config_schema_violation`); `run` and `auth setup --headed` also refuse a
  CSS or XPath locator before anything launches.
- `selvedge auth setup` signs in once, outside any plan or model: it runs the approved
  `hooks.auth_setup` (credentials only from the variables `auth.env` names; an unset one is
  `BLOCKED placeholder_unset` and the hook does not run), and keeps the Playwright storage state it
  writes to `$SELVEDGE_STORAGE_STATE` at `$HOME/.local/state/selvedge/<repo-id>/auth/storageState.json`
  (directories `0700`, file `0600`, never inside the repo). `--headed` lets you sign in yourself in a
  visible guarded browser instead (up to `SELVEDGE_AUTH_TIMEOUT_MS`), with no hook and no credential
  passing through selvedge.
- `selvedge run` loads that session into every criterion's fresh context and checks
  `auth.signed_in_check` once, after the hooks and before the first criterion. A failed check makes
  every criterion BLOCKED `needs_auth` (a new reason) at once when nobody can sign in (stdin not a
  terminal, or the new `--non-interactive` flag), with exactly one check and no retry loop; on a
  terminal it asks for one sign-in, reads one line and checks once more. `run` never runs
  `auth_setup` itself. With no `auth` key, `run` is unchanged.
- Every `auth.env` value is redacted like a `{{NAME}}` value (written back as `{{NAME}}`) in
  `evidence.jsonl`, `verdict.json`, traces and stderr, and in what `selvedge snapshot` prints (the
  page a planner looks at), so a credential a page shows reaches the planner only as `{{NAME}}`.
- `run --trace` with a stored session keeps no session value: the storage state Playwright records
  in the trace's context options reads `[redacted]`, and every cookie and local storage value the
  session holds is replaced by `[redacted]` wherever the trace shows it, as stored and URL-encoded.
  A session value shorter than 8 characters is replaced only inside that storage state, so a `"1"`
  flag neither mangles the kept trace nor drops it. A `{{NAME}}` / `auth.env` value is now also
  redacted in its URL-encoded form.
- A stored session file Playwright would not load (not JSON, a JSON object without a storage
  state's `cookies` / `origins` shape, or a cookie breaking Playwright's rules: `expires` other than
  -1 or a unix time up to year 9999, a `url` that is not `http`/`https`) is BLOCKED `needs_auth`
  before any browser opens, with or without `auth.signed_in_check`; `auth setup` keeps no
  hook-written file of that kind. A session Playwright still refuses when a context opens is
  `needs_auth` too, never `playwright_unavailable`.
- The README documents `auth setup`, where the session lives, the `needs_auth` behaviour, and the
  honest limit: an agent with shell access can read any file you can, so selvedge keeps secrets out
  of plans, evidence, PR comments and model prompts, and does not claim they are out of reach.

## 0.4.1 — 2026-11-17

- `selvedge run` checks a first run's `plan.json` against the folder's own `event: "freeze"` line in
  `.selvedge/runs.jsonl`, as `--replay` already did, so a `plan.json` and `plan.sha256` edited
  together are `plan_modified` and nothing runs.
- `selvedge run` claims the folder (`run.claim`, created exclusively) before any `reset` / `seed`
  hook runs, so of two runs started together on one folder only one runs the hooks; the other is
  `already_run`. The claim is removed when the run ends; a run killed outright leaves it, and the
  folder reads as `already_run` until it is removed.

## 0.4.0 — 2026-11-16

- `selvedge run <run-dir>` executes a frozen `plan.json` in the guarded browser with no model call.
  It refuses, before anything is written or launched, a folder with no `plan.sha256`
  (`not_frozen`), one that already ran (`already_run`) and a `plan.json` whose sha256 changed
  (`plan_modified`). Each criterion runs in a fresh guarded context. The runner writes every line of
  `evidence.jsonl` itself (`run_start`, one `step` line per executed step, `criterion_end`,
  `run_end`; every `{{NAME}}` value written back as `{{NAME}}`) and one end-state screenshot per
  criterion. Every `expect` after a read gets a stable wait (network idle, then a settled DOM, within
  5 s) and one re-read before it is judged, so a check that holds before an in-flight side effect
  lands (`changed_from` false) cannot PASS early. A step that throws is BLOCKED `step_failed` (with its index), three no-change
  actions in a row are BLOCKED `stuck_screen`, and `SELVEDGE_RUN_BUDGET_MS`,
  `SELVEDGE_PLANNER_TOKEN_BUDGET` and `SELVEDGE_STEP_TIMEOUT_MS` bound the run. Approved `reset` /
  `seed` hooks run before the first browser (`data_state: managed`); an unapproved one blocks every
  criterion (`env_hooks_unapproved`). Each run appends exactly one `event: "run"` line to
  `.selvedge/runs.jsonl` (`entry` from `SELVEDGE_ENTRY`: `session`, `ci` or `loomwright`).
- `selvedge verdict <run-dir>` derives PASS / FAIL / BLOCKED / NOT_VERIFIABLE per criterion from
  `evidence.jsonl` and `plan.json` only, into `verdict.json` (schema in
  `schemas/verdict.schema.json`): an empty read is NOT_VERIFIABLE `no_value_read`, never PASS, for
  any `expect` in a criterion, not only the last; any
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
