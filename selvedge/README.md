# selvedge

Selvedge checks finished work against its brief and reports an **evidenced PASS/FAIL per
acceptance criterion**. It is a sibling plugin in the `atelier` marketplace, next to Loomwright,
and it **releases on its own**: its own version, changelog and CI gate.

This release ships the target-safety layer the checker drives a browser behind: a committed
`selvedge.json` with an exact-origin allowlist, the `selvedge env` commands (`check`, `init`,
`approve`, `hook`), and the browser guard: a runner-owned proxy plus a `context.route` layer that
refuse every connection to an origin you did not list. Checking a brief arrives in later releases.

## Install

```
/plugin install selvedge@atelier
```

Then put the CLI on your `PATH`:

```
selvedge install-cli        # or, before it is on PATH: <plugin dir>/bin/selvedge install-cli
```

`install-cli` links `$HOME/.local/bin/selvedge` to the plugin's `bin/selvedge`. It is **required**
for now, not optional: a plugin's `bin/` is measured on `PATH` when the plugin is loaded with
`--plugin-dir` (the desktop app's mechanism), but the installed-plugin CLI case is not yet
measured. Evidence and the owner-runnable check: [`docs/cli-discovery.md`](docs/cli-discovery.md).

`install-cli` prints what it did, is safe to re-run, and refuses to replace a regular file at
`$HOME/.local/bin/selvedge` (move that file aside first). If `$HOME/.local/bin` is not on your
`PATH`, it says so.

**Re-run `selvedge install-cli` after every `/plugin update`.** The link points at the installed
copy's real path, which sits in a per-release folder of the plugin cache. An update installs a new
folder, so until you re-run it the link keeps running the old CLI (`selvedge --version` shows the
old version), and it breaks once the old folder is cleaned up. `install-cli` prints this reminder
each time it runs.

## CLI

```
selvedge                 # version and the command list
selvedge --version       # selvedge <version>, read from .claude-plugin/plugin.json at run time
selvedge install-cli     # link the CLI into $HOME/.local/bin (re-run after each plugin update)
selvedge env <command>   # selvedge.json and its env hooks (below); needs Node.js >= 18
selvedge criteria <command>   # acceptance criteria to criteria.json, and the testability pre-check
selvedge plan --validate <plan.json>   # lint a plan before it is frozen
```

`--version` and `install-cli` need only bash and standard userland tools (no `jq`, no Node); the
CLI resolves its own real path through symlinks, so it works when run through the `install-cli`
link. **The `env`, `criteria` and `plan` commands need Node.js >= 18 on `PATH`**; without it they
exit 1 and say so.

Exit codes: `0` ok, `1` an operation failed, `2` a usage error or **BLOCKED**, `3`
**NOT_VERIFIABLE**. A BLOCKED outcome prints its own stdout line `BLOCKED <reason>`, a
NOT_VERIFIABLE one `NOT_VERIFIABLE <reason>`; a config or usage problem names its reason on stderr.
When several apply, the lowest non-zero code wins (1, then 2, then 3). Every reason is in the
[table below](#blocked-and-config-reasons).

## `selvedge.json`

A committed file at the repo root. It says which origins the checker's browser may reach, and the
shell hooks that set up the app under test:

```json
{
  "schema_version": 1,
  "origins": ["http://localhost:3000"],
  "allow_remote": false,
  "allow_remote_mutation": false,
  "hooks": {
    "seed": "npm run db:seed",
    "reset": "npm run db:reset",
    "auth_setup": "node scripts/make-test-user.js"
  }
}
```

- `schema_version` — must be `1`.
- `origins` — each entry exactly `scheme://host[:port]`, `http` or `https`: no path, query,
  fragment, userinfo or trailing slash. Matching is by parsed exact value: scheme, host **and**
  port. `http://localhost:3000` does not admit `http://localhost:3001`, and
  `https://shop.example.com/?next=localhost` is `shop.example.com`, not localhost. No regex, suffix
  or substring match exists anywhere.
- `allow_remote` — an origin whose host is not `localhost`, `127.0.0.1` or `[::1]` is refused
  unless this is `true`.
- `allow_remote_mutation` — with it `false` (the default), a remote origin gets only the read
  methods GET, HEAD and OPTIONS; every other method (POST, PUT, PATCH, DELETE, PROPFIND, MKCOL, a
  custom verb) is refused. This is an allow-list: a method not named here is refused.
- `hooks` — optional; only `seed`, `reset` and `auth_setup`. They run only after you approve them
  (below).

No other key is accepted. The JSON Schema is
[`schemas/selvedge-config.schema.json`](schemas/selvedge-config.schema.json).

## `env` commands

```
selvedge env check [--base <ref>]     validate selvedge.json; report the hook approval state
selvedge env init [--port <N>]        write a local-only selvedge.json; never overwrites one
selvedge env approve [--base <ref>]   show every hook and its sha256; record your approval (TTY only)
selvedge env hook <name> [--base <ref>]
                                      run one approved hook (seed, reset, auth_setup) at the repo root
```

- **`check`** prints where the config came from, the origins (each marked local or remote), the
  hooks with their sha256, the approval state (`approved`, `unapproved` or `no hooks`), and a scope
  line: the guard covers the browser only.
- **`--base <ref>`** reads the committed `<ref>:selvedge.json` (`git show`) and never the working
  tree, so a pull request cannot widen its own allowlist or change its hooks' command text. It
  does not pin the files a hook runs: see the limit under "Where approvals live". Without it the
  working-tree file is read and the output says `config source: working tree (no --base)`. An
  unreadable `<ref>:selvedge.json` is `base_config_unreadable`, never a fallback to the working tree.
- **`init`** writes `schema_version: 1`, exactly one origin `http://localhost:<port>`, both
  `allow_*` keys `false` and no hooks. The port comes from `--port`, else from a `--port N`, `-p N`
  or `PORT=N` in `package.json`'s `scripts.dev` / `scripts.start`, else from a prompt on a TTY; with
  none of those it exits 2 `port_required`. It never writes a non-local origin.
- **`approve`** needs an interactive terminal (`approve_requires_tty` otherwise, nothing written).
  It prints every hook and the sha256 of the canonical `hooks` object (sorted keys, no whitespace)
  and records it only on an explicit `y`.
- **`hook <name>`** runs the hook with `bash -c` at the repo root, only when the current `hooks`
  hash equals your recorded approval for this repo, and only when every origin is local. Changing
  one byte of any hook needs a fresh approval.

**Where approvals live.** `$HOME/.claude/selvedge/approvals.json` only (directory `0700`, file
`0600`, written atomically), keyed by the repo's identity (its `origin` remote URL with any
credentials removed, else the repo root's real path). Nothing inside the repo is ever read as an
approval. Honest limit: the file is user-scoped, so any process running as you, an agent with a
shell included, can write it; `env approve` itself refuses without a TTY. Second honest limit:
**the approval pins the hook command text, not the files it runs.** A hook that calls a repo script
(`node scripts/make-test-user.js`, `bash seed.sh`) runs that script as it is in the current
checkout, so a pull request that edits only the script changes what the approved hook does, even
under `--base`. `env approve` prints this limit with every approval prompt. Read the scripts a hook
calls before running it on a branch you did not write.

## `criteria` commands

```
selvedge criteria from-pr <n> [--source <label>]     the list under the PR body's "Acceptance criteria" heading
selvedge criteria from-md <file> [--source <label>]  a markdown list
selvedge criteria from-text [--source <label>]       stdin: a list, or one criterion per line
selvedge criteria check <criteria.json>              testable / vague, with a rewrite for each vague one
```

- **`from-*`** print `criteria.json` on stdout: `{"schema_version": 1, "source": null, "criteria":
  [{"id", "text"}]}`, pretty-printed with 2 spaces and a trailing newline. `from-pr` reads the PR
  body with `gh pr view <n> --json body` and takes the list under the first heading (a `#` heading
  or a bold line) whose title contains "Acceptance criteria". `from-md` takes that section's list
  when the file has one, else every top-level list item. `from-text` does the same, and with no
  list at all takes each non-blank line. No criteria found exits 2 `criteria_not_found`.
- **The same criteria give the same bytes**, whatever the input. Each text is normalized (list and
  checkbox markers and surrounding whitespace stripped, inner whitespace collapsed) and its `id` is
  `c-` plus the first 12 hex of sha256 of that text. `source` stays `null` unless you pass
  `--source <label>`; where the criteria came from is printed on stderr instead. An indented line
  or a nested item is folded into its parent criterion.
- **`check`** prints `testable <id>` or `vague <id> ("<phrase>"): rewrite: <a testable shape>` per
  criterion. The check is deterministic: a criterion is vague when it uses one of `works well`,
  `looks good`, `looks right`, `looks nice`, `user-friendly`, `intuitive`, `as expected`,
  `properly`, `correctly`, `seamless`, and carries no quoted literal and no digit. A vague criterion
  is never planned: a plan lists it under `not_planned` with `criterion_not_testable` and a rewrite.

The JSON Schema is [`schemas/criteria.schema.json`](schemas/criteria.schema.json).

## `plan --validate`

```
selvedge plan --validate <plan.json> [--criteria <criteria.json>] [--base <ref>]
```

Lints a `plan.json` against the run folder's `criteria.json` (the file beside the plan unless
`--criteria` names another) and `selvedge.json` (the working tree, or `<ref>:selvedge.json` with
`--base`, as `env check --base` reads it). It lists **every** problem, one stderr line each:
`plan_invalid: <criterion id | (plan)>: <code>: <detail>`, and exits 2 when there is any.

A plan is `{"schema_version": 1, "target": "web", "criteria_sha256", "plan_revision"?, "origins",
"steps_by_criterion": {"<id>": {"interpretation", "polarity", "unverified_assumptions", "steps"}},
"not_planned"?: [{"id", "reason", "rewrite"?, "detail"?}]}`. `polarity` is `positive` or
`negative`; each assumption is `{"text", "material"}`; a `not_planned` reason is
`criterion_not_testable` (with a non-empty `rewrite`), `side_effect_not_observable` or
`exploration_budget`. The JSON Schema is [`schemas/plan.schema.json`](schemas/plan.schema.json).

Step types (no field beyond these is accepted):

- `goto` — `url`; its origin must be in the plan's `origins` and allowed by `selvedge.json`.
- `click` — `locator`.
- `fill` — `locator`, `value` (a literal, or `{{NAME}}` read from the environment at run time).
- `select` — `locator`, `value` (as `fill`).
- `check` — `locator`, optional `checked` (true or false).
- `press` — `key`, optional `locator`.
- `wait_for` — `locator`, `state` (`attached`, `detached`, `visible`, `hidden`).
- `read` — `property`: `text`, `value`, `checked`, `count`, `attribute:<name>` (each with a
  `locator`) or `url` (no locator).
- `expect` — `op` and `value`, compared with the last read: `equals`, `contains`, `matches` (a
  regular expression), `gt`, `lt`, or `changed_from` (a boolean: whether the last read must differ
  from the previous read of the same locator and property, a negative criterion's baseline form).

A locator is exactly one of `{"role", "name"?, "exact"?}`, `{"label"}`, `{"text"}` or
`{"testid"}`: Playwright role, label, text and test-id locators, never CSS or XPath.

Plan-lint problems (the codes after `plan_invalid:`):

- `missing_final_read_expect` — a criterion's steps do not end in `read` then `expect` (a value read after the last action).
- `existence_only_expect` — the final `expect` checks only existence or visibility (`visible`, `hidden`, `exists`, `attached`, `detached`, or `read count` then `gt 0`).
- `unknown_step_type` — a step `type` that is not one of the step types above.
- `unknown_field` — a field a step, a criterion entry or the plan does not have.
- `invalid_locator` — a locator that is not exactly one role, label, text or test-id form (CSS, XPath and any other key are refused).
- `code_like_content` — a step string that looks like code: `=>`, `function(`, `<script`, `javascript:`, `${`, a backtick, `eval(`, `document.`, `window.`, `require(`, `import `.
- `origin_not_allowed` — a `goto` or a plan origin not allowed by `selvedge.json`, or a `goto` origin not in the plan's `origins`.
- `missing_interpretation` — a planned criterion with no one-sentence `interpretation`.
- `missing_polarity` — a planned criterion whose `polarity` is not `positive` or `negative`.
- `invalid_assumptions` — `unverified_assumptions` is not an array of `{"text", "material"}`.
- `negative_without_baseline` — a negative criterion with no `read` before its first action (`click`, `fill`, `select`, `check`, `press`).
- `negative_absence_only` — a negative criterion whose only check is that an element is absent or hidden (final `read count` + `expect equals 0`, or a `wait_for` `hidden` as the last check).
- `vague_criterion_planned` — a vague criterion has steps; it belongs under `not_planned`.
- `criterion_unaccounted` — a criterion of `criteria.json` that is neither planned nor `not_planned`, or a planned id that is not in `criteria.json`.
- `criteria_sha_mismatch` — `criteria_sha256` is not the hash of the run folder's `criteria.json`.
- `prefix_step_not_allowed` — a snapshot prefix holds a `read` or `expect` step.
- `prefix_too_long` — a snapshot prefix has more than 15 steps.
- `invalid_not_planned` — a `not_planned` entry with an unknown id or key, an unknown reason, a duplicate, a criterion that is also planned, or `criterion_not_testable` without a rewrite.
- `plan_schema_violation` — the plan or a step is malformed: not JSON, a missing or wrongly typed value, an unknown `op`, `state` or `read` property.

## The browser guard

The checker's browser (`lib/runner/route-guard.mjs`) runs behind two independent layers, and every
refusal names its layer:

1. **A runner-owned forward proxy** (`lib/runner/proxy.mjs`). Chromium is launched with this proxy
   and nothing else: no bypass list, no `direct://` fallback. Every connection Chromium makes goes
   through it: a navigation, each redirect hop, `fetch`, a `ws`/`wss` handshake, an https CONNECT.
   An unlisted origin is refused before any DNS lookup. A listed remote host is looked up once; if
   any address it resolves to is private, loopback, link-local, unique-local, multicast,
   unspecified or reserved (including shared CGNAT and benchmarking ranges; an IPv6 NAT64 or
   6to4 address counts by the IPv4 it embeds; local-use NAT64 and Teredo always count), it is
   refused and no connection is attempted. Otherwise the proxy connects to that validated address,
   never to the name again. If the proxy dies, the browser's requests fail (`proxy_unavailable`); they never go
   direct.
2. **A `context.route('**/*')` layer**, installed before any page exists, refuses unlisted origins
   and, without `allow_remote_mutation`, any remote request whose method is not GET, HEAD or
   OPTIONS. It also covers https, where the proxy cannot see the method. Service workers are
   blocked.

   **Redirects.** Chromium follows a redirect without showing the next hop to the route layer, and
   over https the proxy sees only the CONNECT, so neither would see the method of a redirect hop.
   Chromium keeps the method and body on a 307 or 308, and on a 301 or 302 for every method except
   POST (which becomes GET); a 303 turns every method except HEAD into GET. So when a remote origin
   is listed and `allow_remote_mutation` is off, the route layer sends a non-read request itself
   through the same proxy. A redirect whose next hop is a read is handed to the page and Chromium
   follows it through the proxy. For a redirect whose next hop keeps a method other than GET, HEAD
   or OPTIONS, the route layer needs the request's redirect mode, which Playwright does not show a
   route handler. So under that config an init script wraps the page's `fetch` and tags each
   non-read call with its `redirect` and `credentials` modes (a header the route layer removes
   before anything is sent):
   - **follow** (a navigation, a form, an XHR, or a `fetch` tagged `follow`): the route layer checks
     the hop's target before sending it, refuses a hop to a remote origin
     (`remote_mutation_refused`, layer `route`), and follows the rest itself, one hop at a time, as
     a browser would: `Authorization` is dropped once a hop changes origin, and cookies go only
     where the credentials mode lets them (`include`, or `same-origin` while every URL so far has
     the page's origin; a navigation, form or XHR counts as `same-origin`).
   - **manual** or **error**, or a `fetch` with no tag (one from a Worker, or a `no-cors` POST):
     the route layer never sends the hop. The page gets the redirect with its `Location` replaced by
     an unlisted `.invalid` host, so Chromium applies the page's own mode: an opaque redirect for
     `manual`, a network error for `error`, and for an untagged `fetch` that does follow, a request
     to that host, which the proxy refuses (`host_not_allowed`). Nothing reaches a real server.

   If the proxy is gone, a request the route layer sends fails `proxy_unavailable` like any other.
   The costs of the follow path: the page gets the final response under the URL it asked for, not
   the redirect target's URL; and cookies on a followed hop are the browser context's for that
   URL, without SameSite applied. (While Playwright routes the context, it answers a
   CORS preflight itself: a cross-origin `fetch` that needs one, such as a PUT or a custom header,
   sends no OPTIONS to the server, and the request goes out whatever the server would have
   allowed. `test-route-guard.sh` checks this for a request the route layer passes on and for one
   it sends itself, against a control without routing in which Chromium sends the OPTIONS.) Every request is
   still checked against the allowlist. Every other request is passed on untouched.

Playwright sends localhost through the proxy only while
`PLAYWRIGHT_DISABLE_FORCED_CHROMIUM_PROXIED_LOOPBACK` is unset, so the guard refuses to launch if
that variable is set (`proxy_loopback_disabled`).

What the guard does **not** cover:

- **The browser only.** The checker's shell, and the `env` hooks, are not behind the proxy: a
  command run from the shell can reach any host. Hooks therefore never run while any origin is
  remote.
- **HTTPS and WSS are checked by host and port only.** They are tunnelled (CONNECT), so the proxy
  never sees the path or method; there is no TLS interception. The route layer adds the method
  check for https requests the page makes, including the redirect hops that keep a non-read
  method (above).

## BLOCKED and config reasons

Every reason selvedge prints. `BLOCKED` reasons print as a stdout line `BLOCKED <reason>`; config
and usage reasons print on stderr. Both exit 2. `NOT_VERIFIABLE` reasons print as a stdout line
`NOT_VERIFIABLE <reason>` and exit 3; a plan also records them per criterion under `not_planned`.

| Reason | Kind | Meaning |
|---|---|---|
| `host_not_allowed` | BLOCKED | the browser asked for an origin not in `origins` (exact scheme, host and port) |
| `remote_resolves_private` | BLOCKED | a listed remote host resolved to a private, loopback, link-local, unique-local, multicast, unspecified or reserved address |
| `remote_mutation_refused` | BLOCKED | a method other than GET, HEAD or OPTIONS to a remote origin (directly or as a redirect hop that keeps the method: 307/308, or 301/302 for any method but POST) without `allow_remote_mutation` |
| `proxy_loopback_disabled` | BLOCKED | `PLAYWRIGHT_DISABLE_FORCED_CHROMIUM_PROXIED_LOOPBACK` is set, so localhost would skip the proxy |
| `proxy_unavailable` | BLOCKED | the guard's proxy is gone; the request failed instead of going direct |
| `env_hooks_unapproved` | BLOCKED | the hooks have no approval matching their current sha256 for this repo; run `selvedge env approve` |
| `env_hooks_remote_origin` | BLOCKED | a hook was asked to run while an origin is remote |
| `playwright_unavailable` | BLOCKED | no `playwright` module was found: neither `SELVEDGE_PLAYWRIGHT_MODULE` nor the repo's own `node_modules` |
| `placeholder_unset` | BLOCKED | a step uses `{{NAME}}` and `NAME` is not set in the environment |
| `criterion_not_testable` | NOT_VERIFIABLE | the criterion is vague (no observable value); it is not planned and carries a rewrite |
| `side_effect_not_observable` | NOT_VERIFIABLE | a negative criterion names no side effect a check can read before and after the action; it is not planned |
| `exploration_budget` | NOT_VERIFIABLE | the run folder's snapshot calls are used up, so the planner could not explore further |
| `origins_empty` | config | `origins` is absent or empty; add the app you test, e.g. `http://localhost:3000` |
| `origin_invalid` | config | an origin is not exactly `scheme://host[:port]` |
| `remote_origin_without_allow_remote` | config | a non-local origin is listed without `"allow_remote": true` |
| `config_absent` | config | no `selvedge.json` at the repo root; run `selvedge env init` |
| `config_invalid_json` | config | `selvedge.json` is not valid JSON |
| `config_schema_violation` | config | an unknown key, an unknown hook name, or a value of the wrong type |
| `base_config_unreadable` | config | `--base <ref>` given, but `<ref>:selvedge.json` cannot be read |
| `approve_requires_tty` | usage | `env approve` was run without an interactive terminal |
| `port_required` | usage | `env init` found no port (`--port`, `package.json` scripts, or a TTY prompt) |
| `already_frozen` | usage | `plan --freeze` on a run folder that already holds a frozen plan; a new plan goes in a new folder |
| `plan_invalid` | usage | `plan --validate` (or a snapshot prefix) found problems; each is listed on its own line |
| `criteria_invalid` | usage | a `criteria.json` is not valid JSON or does not match its schema (an id that is not its text's hash included) |
| `criteria_not_found` | usage | no criteria were found in the input, or the `criteria.json` file is missing or empty |
| `planner_failed` | usage | the planner exited non-zero, wrote no plan, or could not be started |

## Releasing

Selvedge never uses the repository's `changelog.d/` fragments or `scripts/bump-version.sh` — those
fold into Loomwright's version only. A selvedge release changes three things together:

1. `version` in `selvedge/.claude-plugin/plugin.json`
2. the `selvedge` entry's `version` in `.claude-plugin/marketplace.json`
3. a new top heading `## <X.Y.Z> — <YYYY-MM-DD>` in `selvedge/CHANGELOG.md`

`scripts/validate-version.sh` checks 1 against 2; selvedge's own gate checks 1 against 3.

## Its own gate

```
bash selvedge/tests/run.sh
```

It checks the manifest is valid JSON with `name`, `version` and `description`, that the version
is the changelog's first release heading, and runs every `selvedge/tests/test-*.sh`. CI's `static`
job runs it. Nothing under `selvedge/` sources, runs or reads a path under `loomwright/`.

The browser tests need Node.js and download the pinned `playwright` library plus its Chromium
build into a selvedge-owned cache (`${TMPDIR:-/tmp}/selvedge-test-pw`, or
`$SELVEDGE_TEST_PW_CACHE`); that download is the only network the suite uses. Under CI a failed
download fails the gate (`playwright_install_failed`); locally the browser arms are skipped and the
rest still decide.

Which of the repository's shared gates reach this plugin, and how:
[`docs/evidence/gate-scopes.md`](docs/evidence/gate-scopes.md).
