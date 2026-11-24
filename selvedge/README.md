# selvedge

Selvedge checks finished work against its brief and reports an **evidenced PASS/FAIL per
acceptance criterion**. It is a sibling plugin in the `atelier` marketplace, next to Loomwright,
and it **releases on its own**: its own version, changelog and CI gate.

What ships today:

- **Target safety** — a committed `selvedge.json` with an exact-origin allowlist, the `selvedge env`
  commands (`check`, `init`, `approve`, `hook`), and the browser guard: a runner-owned proxy plus a
  `context.route` layer that refuse every connection to an origin you did not list.
- **Criteria to a frozen plan** — `selvedge criteria` turns acceptance criteria into
  `criteria.json` and flags vague ones; `selvedge snapshot` shows a planner an allowed page's
  accessibility tree; `selvedge plan` has a planner write typed steps, lints them statically, and
  freezes the plan with its sha256 in a run folder before anything runs.
- **A verdict no model wrote** — `selvedge run` executes the frozen plan's typed steps in the
  guarded browser with no model call and writes every evidence line itself; `selvedge verdict`
  derives PASS / FAIL / BLOCKED / NOT_VERIFIABLE per criterion from those lines and the plan only.
  `run --replay` re-runs a frozen plan unchanged for regression; `run --trace` keeps a redacted
  Playwright trace.
- **The verdict where it is read** — `selvedge comment` puts a run's verdicts on the PR as one
  text-only comment, updated in place; `/selvedge:verify` runs the whole check from Claude Code in a
  separate verifier subagent that has only Bash and Read, and `skills/verify/SKILL.md` gives any
  other agent host the same workflow.

## Quick start

From nothing to a first verdict on the bundled sample app; the target is 15 minutes or less, most
of it reading and the browser download. You need Node.js >= 18, git, and Claude Code signed in with your Claude
login; no other account or key. Each block is one step: copy it, run it, and compare the line after
it. The measured runs are in [`docs/quick-start-timing.md`](docs/quick-start-timing.md).

**1. Install the plugin.** In a Claude Code session (these are session commands, not shell
commands; skip the first one if you already added the `atelier` marketplace):

```
/plugin marketplace add vikashruhilgit/loomwright
```

```
/plugin install selvedge@atelier
```

Expected: Claude Code says `selvedge` is installed. Restart the session if it asks you to.

**2. Put the CLI on your `PATH`** with `selvedge install-cli`. This is required (why:
[Install](#install)). Before the CLI is on `PATH`, run the installed copy's own `install-cli` in a
terminal (a fresh install has exactly one version folder):

```
~/.claude/plugins/cache/atelier/selvedge/*/bin/selvedge install-cli
```

Expected: `selvedge: linked /Users/<you>/.local/bin/selvedge -> …/bin/selvedge`, then a note to
re-run it after each plugin update. If it also prints `… is not on your PATH`, add that folder for
this shell (and to your shell profile, e.g. `~/.zshrc`), then check:

```
export PATH="$HOME/.local/bin:$PATH"
```

```
selvedge --version
```

Expected: `selvedge <version>`.

**3. Make a demo folder** with its own Playwright (Selvedge ships none; it uses the project's):

```
mkdir selvedge-demo && cd selvedge-demo
```

```
git init
```

```
npm init -y
```

```
npm i -D playwright
```

Expected: `Initialized empty Git repository in …/selvedge-demo/.git/`, then a `package.json`, then
`added 2 packages` (the count can differ).

**4. Download Chromium for that Playwright** (about 300 MB: Chromium, its headless shell and
FFmpeg; the slowest command):

```
npx playwright install chromium
```

Expected: three progress bars, each ending in a line such as `Chrome for Testing … downloaded to
…/ms-playwright/chromium-…`, and no error.

**5. Write `selvedge.json`** for the sample app's port:

```
selvedge env init --port 4173
```

Expected:

```
selvedge env: added .selvedge/ to …/selvedge-demo/.gitignore
selvedge env: wrote …/selvedge-demo/selvedge.json (origin http://localhost:4173, port from --port)
```

**6. Check everything with `selvedge doctor`:**

```
selvedge doctor
```

Expected: six `ok` lines, exit 0:

```
ok Node >= 18 (<version>)
ok Playwright library (<version>, from this repo)
ok Chromium browser (<path>)
ok selvedge.json (http://localhost:4173)
ok hook approvals (no hooks)
ok planner (claude at <path>)
```

Any `FAIL <check>: <fix>` line names its own fix: run that, then `selvedge doctor` again. With no
Node at all it prints the Node `FAIL` line and `skipped: the other checks need Node`.

**7. Start the sample app in a second terminal** (it runs until you press Ctrl-C):

```
selvedge sample-app --port 4173
```

Expected:

```
selvedge sample app: serving on http://localhost:4173 (Ctrl-C to stop)
pages: http://localhost:4173/cart, http://localhost:4173/echo, http://localhost:4173/slow
in your demo repo: selvedge env init --port 4173
```

`sample-app` serves the app Selvedge's own tests use (`tests/fixtures/app-server.mjs`; its header
lists every page) on port 4173 unless you pass `--port N`, with no time limit (the tests' own
`serve` mode has a 15-minute watchdog; `sample-app` has none). Before it listens it connects to the
port on 127.0.0.1 and on ::1 (`localhost` can resolve to either), so a port another server already
answers on, whether bound to 127.0.0.1, to ::1 or to every address, exits 1 and names the port.
Pick another with `--port <N>`; step 5 has already written `selvedge.json` (and `env init` will not
overwrite it), so change the origin in its `origins` list to `http://localhost:<N>`, or move the
file aside and re-run `selvedge env init --port <N>`; and use `<N>` in place of 4173 in every URL in
steps 8 and 9 and the terminal check below (an origin `selvedge.json` does not list is BLOCKED).

**8. Verify three criteria.** Back in the demo folder, start Claude Code (`claude`) and send this
one message (the three criteria are plain text, one per line):

```
/selvedge:verify
- On http://localhost:4173/cart, after clicking "Open cart", the Total reads 6
- On http://localhost:4173/echo, after typing Ada in the User field, the page shows "Hello, Ada"
- On http://localhost:4173/slow, after clicking "Load price", the price reads 42
```

A verifier subagent plans the checks, freezes the plan and runs it in the guarded browser; this
takes a minute or more, mostly the planner. Approve its `selvedge` commands when Claude Code asks.

**9. Read the verdict table.** The command shows one row per criterion, then the overall verdict,
the plan sha256 and the run folder (`.selvedge/runs/<run-id>/`), for example:

```
| Verdict | Reason | Criterion |
|---|---|---|
| PASS | | On http://localhost:4173/cart, after clicking "Open cart", the Total reads 6 |
| PASS | | On http://localhost:4173/echo, after typing Ada in the User field, the page shows "Hello, Ada" |
| PASS | | On http://localhost:4173/slow, after clicking "Load price", the price reads 42 |
Overall: PASS
```

The table's layout is Claude's; the verdicts are `verdict.json`'s, which no model wrote. To try a
FAIL, change `6` to `7` in the first criterion and run step 8 again.

**Without Claude Code's slash command**, the same check from the terminal (the planner still uses
the `claude` CLI, or `SELVEDGE_PLANNER`):

```
printf '%s\n' '- On http://localhost:4173/cart, after clicking "Open cart", the Total reads 6' '- On http://localhost:4173/echo, after typing Ada in the User field, the page shows "Hello, Ada"' '- On http://localhost:4173/slow, after clicking "Load price", the price reads 42' | selvedge criteria from-text > criteria.json
```

```
run_dir="$(selvedge plan criteria.json)" && selvedge run "$run_dir"
```

Expected: progress lines on stderr (`selvedge plan: …`, `selvedge run: …`), then one
`PASS <criterion id>` line per criterion and `verdict PASS <run dir>/verdict.json`.

Stop the sample app with Ctrl-C in its terminal when you are done.

## Honest limits

- **Web apps only.** Selvedge checks what a browser can see on the origins you list. Native,
  mobile and desktop targets come later.
- **BLOCKED** means the check could not run: something stopped it before it could decide (an
  unlisted origin, no Playwright, a step whose element was not there, no sign-in). It always names
  its reason.
- **NOT_VERIFIABLE** means the check ran but could not decide the criterion: the criterion is too
  vague to test, or nothing observable was read. It always names its reason too. Every BLOCKED and
  NOT_VERIFIABLE reason, with what it means, is in [BLOCKED and config reasons](#blocked-and-config-reasons).
- **Secrets.** An agent with shell access can read any file you can; Selvedge keeps secrets out of
  plans, evidence and comments but does not claim they are out of reach. The full statement is the
  [**Honest limit** under `auth` and the sign-in check](#auth-and-the-sign-in-check).
- **Accuracy is measured on a small set.** How often a verdict is right on the held-out
  known-answer set (false-PASS, false-FAIL and abstention, each with its 95% interval, and the
  Phase 3 gate verdict) is in [Measuring Selvedge](#measuring-selvedge-the-known-answer-set),
  generated from `eval/results.json`. Read the intervals, not only the point estimates, and for any
  one verdict read the evidence in its run folder.

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
selvedge auth setup [--headed]         # sign in once; the session is kept outside the repo for run
selvedge criteria <command>   # acceptance criteria to criteria.json, and the testability pre-check
selvedge snapshot <url> [--steps <prefix.json>] --run-dir <dir>   # an allowed page's accessibility tree
selvedge plan <criteria.json>          # planner, lint and freeze into .selvedge/runs/<run-id>/
selvedge plan --init | --validate | --freeze …   # the same steps one at a time
selvedge run [--trace] [--non-interactive] <run-dir>   # execute a frozen plan, no model: evidence and verdict
selvedge run --replay <run-dir> [--trace] [--non-interactive]   # the same frozen plan again, in a new run folder
selvedge verdict <run-dir>             # per-criterion verdicts from evidence.jsonl + plan.json
selvedge comment <run-dir> --pr <n> [--yes]   # the verdicts on the PR as ONE text-only comment, updated in place
selvedge doctor          # check Node, Playwright and Chromium, selvedge.json, approvals, the planner: one fix per FAIL
selvedge sample-app [--port N]         # serve the bundled sample app on localhost:N (default 4173) until Ctrl-C
```

`--version` and `install-cli` need only bash and standard userland tools (no `jq`, no Node); the
CLI resolves its own real path through symlinks, so it works when run through the `install-cli`
link. **The `env`, `auth`, `criteria`, `snapshot`, `plan`, `run`, `verdict`, `comment`, `doctor`
and `sample-app` commands need Node.js >= 18 on `PATH`**; without it they exit 1 and say so
(`doctor` as its own Node `FAIL` line). `snapshot`, `run` and
`auth setup --headed` also need Playwright (see [How Playwright is found](#how-playwright-is-found)),
the default planner needs the `claude` CLI, and `comment` (like `criteria from-pr`) needs `gh`.

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
- `auth` — optional; only `env` and `signed_in_check`. `env` lists the names (never the values) of
  the environment variables `auth_setup` reads its credentials from, each `[A-Z_][A-Z0-9_]*`.
  `signed_in_check` is `{"url": …, "locator": …}`: a page on a listed origin and exactly one
  plan-step locator form (`role`, `label`, `text` or `testid`; never CSS or XPath) that matches
  only when signed in. `selvedge auth setup` keeps the session outside the repo
  ([`auth` and the sign-in check](#auth-and-the-sign-in-check)).
- `comment` — optional; only `read_values` (default `false`) and `redact` (default `[]`, a list of
  JavaScript regular expressions). With `"read_values": true` a PR comment shows the value each
  criterion read, after redaction; `redact` adds patterns to the default ones. `selvedge comment`
  reads this key from the PR's base branch only, never the working tree
  ([`comment`](#comment-the-verdict-on-the-pr)).

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
  none of those it exits 2 `port_required`. It never writes a non-local origin. First of all,
  before it looks for `selvedge.json` or a port, it appends the line `.selvedge/` to the repo's
  `.gitignore` (creating the file), unless a line there already ignores `.selvedge` — so the run
  folders and `runs.jsonl` are never committed, even when `selvedge.json` already exists or init
  then fails. The line never changes init's exit code.
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

## `snapshot`

```
selvedge snapshot <url> [--steps <prefix.json>] --run-dir <dir> [--base <ref>]
```

Opens `<url>` in the guarded browser (a fresh browser and context per call), runs an optional
prefix of plan steps, and prints the page's accessibility tree as one JSON object:
`{"schema_version": 1, "url", "steps_run", "failed_step", "error", "aria_snapshot"}`. A planner
uses it to see a page in the state a criterion needs (a dialog open, a form filled) before it
writes locators: content that appears only after a click is not in the tree until a prefix clicks.

- **The prefix** (`--steps`) is a JSON array of at most 15 `goto`, `click`, `fill`, `select`,
  `check`, `press`, `wait_for` and `request` steps (never `read` or `expect`), checked by the same
  step validator as a plan. A `request` in a prefix must be a `GET` (`plan_invalid`
  `prefix_mutation_refused` otherwise: looking never changes the app), to the origin of the page
  it is sent from (`<url>`, or the last prefix `goto`). With one, the output also holds
  `"replies"`: one `{step, method, url, status, content_type, body, truncated}` per request that
  replied, `body` the first 2 KiB of the reply text, redacted like `aria_snapshot`. A `fill`/`select` value may be `{{NAME}}`, read from the environment; an
  unset name is `BLOCKED placeholder_unset`. The value is never printed: every resolved value is
  shown as its `{{NAME}}` in `aria_snapshot`, `error` and on stderr (found as given and as
  Playwright's YAML/JSON quoting and whitespace normalization print it — a page that shows the
  value cut, re-cased or otherwise transformed still shows it). **Open item:** any
  environment variable name resolves, not only names a plan declares, so whoever may run
  `snapshot` (a planner included) can make the page hold any variable's value; the redaction keeps
  the plain value off the output, nothing more. The value of every variable `auth.env` names is
  redacted the same way, prefix or not, so a page that shows a credential hands a planner
  `{{NAME}}`.
- **Before any browser launches** it refuses an unlisted `<url>`, prefix `goto` or prefix `request` origin
  (`BLOCKED host_not_allowed`), a bad prefix (`plan_invalid`, one stderr line per problem), and a
  missing Playwright (`BLOCKED playwright_unavailable`).
- **The budget.** `--run-dir` (or `SELVEDGE_RUN_DIR`) is required: every call appends one line to
  `<dir>/snapshots.jsonl` — `{ts, origin, prefix_steps, plan_time_actions, browser_launched,
  outcome, failed_step}`, the steps as given (a `{{NAME}}` stays literal), no page text — and a
  call past `SELVEDGE_SNAPSHOT_BUDGET` calls (default 20) per run folder prints
  `NOT_VERIFIABLE exploration_budget` and exits 3. `plan_time_actions` counts the action steps
  (`click`, `fill`, `select`, `check`, `press`) the browser attempted: state a planner changed in
  the app before the run. With `SELVEDGE_RUN_DIR` set, a `--run-dir` naming another folder is a
  usage error, so a call cannot be counted outside the folder it was given.
- **The config source.** `SELVEDGE_BASE` (which `plan` sets for its planner) pins where the
  allowlist is read: `<ref>:selvedge.json`, or the working tree when it is empty. A `--base` naming
  another source is a usage error.
- **A failing prefix step** exits 1 with `failed_step` (0-based), the error's first line, and the
  tree as it was at that step.

### How Playwright is found

Selvedge ships no `node_modules`. `snapshot` and `run` load Playwright from `SELVEDGE_PLAYWRIGHT_MODULE` (the
path of an importable entry, e.g. `<dir>/node_modules/playwright/index.mjs`) when it is set, and
from nowhere else; otherwise from the target project's own `node_modules`, resolved from the repo
root's `package.json` as the project's own code would. Neither ⇒ `BLOCKED playwright_unavailable`.
In a project without it: `npm i -D playwright` then `npx playwright install chromium`.

## `plan` commands

```
selvedge plan <criteria.json> [--base <ref>]          --init, the planner, --validate, --freeze in one go
selvedge plan --init <criteria.json>                  a new run folder holding criteria.json
selvedge plan --validate <plan.json> [--criteria <criteria.json>] [--base <ref>]
selvedge plan --freeze <run-dir> [--base <ref>]       lint, stamp plan_revision, hash
```

`--init`, `--freeze` and the bare form print the run folder's path on stdout; the rest goes to
stderr. `--base <ref>` reads the origin allowlist from `<ref>:selvedge.json`, as
`env check --base` does.

**The run folder** is `.selvedge/runs/<run-id>/` at the repo root, run id
`<UTC YYYYMMDDTHHMMSSZ>-<6 hex>`. It holds:

- `criteria.json` — a byte copy of the criteria the plan answers.
- `planner-input.json` — what the planner got: the testable criteria only, the allowed origins,
  `criteria_sha256`, the CLI path, the snapshot and token budgets.
- `snapshots.jsonl` — one line per `snapshot` call made for this folder.
- `planner-usage.json` — the planner's `{"input_tokens", "output_tokens"}`, when it reported them.
- `plan.json` — the plan, rewritten once at freeze with `plan_revision` stamped.
- `plan.sha256` — `<hex>  plan.json`, the sha256 of plan.json's bytes as written (the same line
  `shasum -a 256 plan.json` prints). Its presence means the folder is frozen.
- `freeze.json` — `{schema_version, ts, run_id, criteria_sha256, plan_sha256, plan_revision,
  plan_time_actions, planner_tokens, planner_token_budget}`.

**Freezing** always runs the lint first: an invalid plan is never hashed (`plan_invalid`, no
`plan.sha256`). A frozen folder is never written again: `--freeze` on it exits 2
`already_frozen` and changes nothing. A new plan for the same criteria goes in a new folder
(`--init`), and its `plan_revision` is 1 + the `event: "freeze"` lines in `.selvedge/runs.jsonl`
with the same `criteria_sha256`, so every re-plan is a numbered revision. Each freeze appends one
line to `.selvedge/runs.jsonl`: `{"event": "freeze", ts, run_id, criteria_sha256, plan_sha256,
plan_revision, plan_time_actions, planner_tokens}`. The count is read, not locked: the trail is an
audit record, not a lock.

**Plan-time actions.** The sum of `plan_time_actions` over the folder's `snapshots.jsonl` is
recorded at freeze as `plan_time_actions` in `freeze.json` and in the `runs.jsonl` freeze line, so
a later run can say how much the planner changed in the app before it.

**The planner** (the bare form only):

- Vague criteria (the `criteria check` pre-check) are **never sent** to the planner. `plan` itself
  lists each under `not_planned` with `criterion_not_testable` and its rewrite. With no testable
  criterion at all, no planner runs.
- `SELVEDGE_PLANNER`, when set, is a command run with `/bin/sh -c` at the repo root. It reads
  `$SELVEDGE_CRITERIA` (`planner-input.json`), writes the plan to `$SELVEDGE_PLAN_OUT`, may call
  `$SELVEDGE_BIN snapshot …` (the run folder is `$SELVEDGE_RUN_DIR`, so each call counts against the
  folder's budget, and `$SELVEDGE_BASE` is the plan's `--base`, empty for the working tree, so each
  call reads the allowlist the plan is checked against), and may write `{"input_tokens": N, "output_tokens": M}` to
  `$SELVEDGE_PLANNER_USAGE`. It comes from your environment, never from a file in the repo.
- Unset, the default is `claude -p <prompt> --output-format json --model <model> --allowedTools
  "Bash(<selvedge bin> snapshot:*)"`, with the fixed prompt
  [`prompts/planner.md`](prompts/planner.md) followed by `planner-input.json`. The plan is the JSON
  object in the result text; the result's `usage` is recorded (input tokens include cache reads
  and writes). Honest limit: `--allowedTools` admits only `snapshot`, but `claude` also applies
  your own settings, so a tool they allow is allowed to the planner too.
- A planner that cannot start (no `claude` on `PATH` included), exits non-zero, or leaves no plan
  is `planner_failed` (exit 2). What it wrote stays in the folder: fix `plan.json` there and run
  `selvedge plan --freeze <run-dir>`.

### The lint (`--validate`)

Lints a `plan.json` against the run folder's `criteria.json` (the file beside the plan unless
`--criteria` names another) and `selvedge.json` (the working tree, or `<ref>:selvedge.json` with
`--base`, as `env check --base` reads it). It lists **every** problem, one stderr line each:
`plan_invalid: <criterion id | (plan)>: <code>: <detail>`, and exits 2 when there is any.

A plan is `{"schema_version": 1, "target": "web", "criteria_sha256", "plan_revision"?, "origins",
"steps_by_criterion": {"<id>": {"interpretation", "polarity", "unverified_assumptions", "steps"}},
"not_planned"?: [{"id", "reason", "rewrite"?, "detail"?}]}`. `polarity` is `positive` or
`negative`; each assumption is `{"text", "material"}`; a `not_planned` reason is
`criterion_not_testable` (with a non-empty `rewrite`), `side_effect_not_observable` (with a
non-empty `detail` naming the pages looked at) or `exploration_budget`. The JSON Schema is
[`schemas/plan.schema.json`](schemas/plan.schema.json).

Step types (no field beyond these is accepted):

- `goto` — `url`; its origin must be in the plan's `origins` and allowed by `selvedge.json`.
- `click` — `locator`.
- `fill` — `locator`, `value` (a literal, or `{{NAME}}` read from the environment at run time).
- `select` — `locator`, `value` (as `fill`).
- `check` — `locator`, optional `checked` (true or false).
- `press` — `key`, optional `locator`.
- `wait_for` — `locator`, `state` (`attached`, `detached`, `visible`, `hidden`).
- `request` — `method` (`GET`, `POST`, `PUT`, `PATCH`, `DELETE`), `url`, optional `json` (a plain
  JSON object body, not for `GET`, at most 6 deep and 64 leaves; a string leaf is a literal or
  `{{NAME}}`). No headers field and no raw body. Its origin must be in the plan's `origins`,
  allowed by `selvedge.json`, and the origin of the page the criterion is on at that point (the last
  `goto` before it): a cross-origin fetch would depend on the app's CORS policy, not on Selvedge. A
  request whose method is not `GET` is an action (rule 1 and the negative baseline apply to it).
- `read` — `property`: `text`, `value`, `checked`, `count`, `attribute:<name>` (each with a
  `locator`), or with no locator: `url`; `response_status` (a number), `response_text` (the body,
  as text) or `response_json:<JSON Pointer>` (an [RFC 6901](https://www.rfc-editor.org/rfc/rfc6901)
  pointer into the parsed body, e.g. `response_json:/0/createdBy/name`: a string, number or
  boolean, or no value when the body is not JSON or the pointer names nothing, null, an object or
  an array) of the last `request` before it; or `cookie:<name>`, a fingerprint of that cookie
  (`sha256:` and 16 hex digits of its value's sha256, or no value when it is absent), never the
  value.
- `expect` — `op` and `value`, compared with the last read: `equals`, `contains`, `matches` (a
  regular expression), `gt`, `lt`, or `changed_from` (a boolean: whether the last read must differ
  from the previous read of the same locator and property, a negative criterion's baseline form).

A locator is exactly one of `{"role", "name"?, "exact"?}`, `{"label"}`, `{"text"}` or
`{"testid"}`: Playwright role, label, text and test-id locators, never CSS or XPath.

**The `request` step** is sent as a `fetch` from inside the page: the runner runs one fixed,
runner-owned function through `page.evaluate`, with the method, URL and body passed as arguments,
never as source. So it leaves through the browser, and both guard layers check it as they check
the page's own requests (see [The browser guard](#the-browser-guard)); the context's cookies go
with it (a stored sign-in session included). Playwright's `context.request` is never used, and
neither is an HTTP client in Node: `context.request` skips `context.route`, so the route layer's
`host_not_allowed` and `remote_mutation_refused` would not apply to it. A request the guard
refuses is BLOCKED with the guard's reason. The criterion keeps its last reply (status, up to
64 KiB of text, content type) for the `response_*` reads after it; no reply value is carried into
a later step (write a seeded id into the plan instead). The evidence line of a request records its
method, url, the top-level keys of its `json` and the reply's status, never the body.

Plan-lint problems (the codes after `plan_invalid:`):

- `missing_final_read_expect` — a criterion's steps do not end in `read` then `expect` (a value read after the last action).
- `existence_only_expect` — an `expect` on a `cookie:<name>` read that is not `changed_from` against an earlier read of the same cookie (a cookie read is a fingerprint, so "a cookie exists" is "it changed from its baseline"); or the final `expect` checks only existence or visibility (`visible`, `hidden`, `exists`, `attached`, `detached`, or `read count` then `gt 0`), or holds for any value read (`contains` a blank string, `matches` a pattern that matches the empty string or every one of a fixed set of unlike one-line texts, as `.`, `\S`, `^.+$` or `..` do, while a format such as `^[a-z0-9-]+$` or `^\d+$` passes, or `read count` then `lt`).
- `unknown_step_type` — a step `type` that is not one of the step types above.
- `unknown_field` — a field a step, a criterion entry or the plan does not have.
- `invalid_locator` — a locator that is not exactly one role, label, text or test-id form (CSS, XPath and any other key are refused).
- `code_like_content` — a step string that looks like code: `=>`, `function(`, `<script`, `javascript:`, `${`, a backtick, `eval(`, `document.`, `window.`, `require(`, `import `.
- `origin_not_allowed` — a `goto`, `request` or plan origin not allowed by `selvedge.json`, a `goto` or `request` origin not in the plan's `origins`, or a `request` to an origin other than that of the page it is sent from (its last `goto`).
- `missing_interpretation` — a planned criterion with no one-sentence `interpretation`.
- `missing_polarity` — a planned criterion whose `polarity` is not `positive` or `negative`.
- `invalid_assumptions` — `unverified_assumptions` is not an array of `{"text", "material"}`.
- `negative_without_baseline` — a negative criterion with no `read` before its first action (`click`, `fill`, `select`, `check`, `press`, or a `request` that is not `GET`).
- `negative_absence_only` — a negative criterion whose only check is that an element is absent or hidden (final `read count` + `expect equals 0`, or a `wait_for` `hidden` as the last check).
- `vague_criterion_planned` — a vague criterion has steps; it belongs under `not_planned`.
- `criterion_unaccounted` — a criterion of `criteria.json` that is neither planned nor `not_planned`, or a planned id that is not in `criteria.json`.
- `criteria_sha_mismatch` — `criteria_sha256` is not the hash of the run folder's `criteria.json`.
- `prefix_step_not_allowed` — a snapshot prefix holds a `read` or `expect` step.
- `prefix_too_long` — a snapshot prefix has more than 15 steps.
- `prefix_mutation_refused` — a snapshot prefix holds a `request` whose method is not `GET`.
- `response_without_request` — a `read` of `response_status`, `response_text` or `response_json:…` with no `request` step before it in the criterion.
- `invalid_not_planned` — a `not_planned` entry with an unknown id or key, an unknown reason, a duplicate, a criterion that is also planned, `criterion_not_testable` without a rewrite, or `side_effect_not_observable` without a detail.
- `plan_schema_violation` — the plan or a step is malformed: not JSON, a missing or wrongly typed value, an unknown `op`, `state` or `read` property.

## `run` and `verdict`

```
selvedge run [--trace] [--non-interactive] <run-dir>
                                                  execute a frozen run folder's plan.json
selvedge run --replay <frozen-run-dir> [--trace] [--non-interactive]
                                                  run that frozen plan again, in a new run folder
selvedge verdict <run-dir>                        re-derive verdict.json from the folder's files
```

**`selvedge run`** executes the frozen `plan.json` in the guarded browser. No model is called: every
step is a typed plan step, and the runner writes every evidence line itself. A folder runs once.
Each of these exits 2 before anything is written or launched, in this order: a usage error
(including a bad `SELVEDGE_ENTRY`, `SELVEDGE_RUN_BUDGET_MS` or `SELVEDGE_STEP_TIMEOUT_MS`),
`not_frozen` (no `plan.sha256`), `already_run` (`evidence.jsonl` or `run.claim` exists),
`plan_modified` (the sha256 of `plan.json`'s bytes is not the one `plan.sha256` records, or not the
one the folder's own `event: "freeze"` line in `runs.jsonl` records, so a `plan.json` and
`plan.sha256` edited together are still refused), then a `selvedge.json` reason (including an
`auth.signed_in_check` locator that is CSS or XPath: `config_schema_violation`). The run then claims
the folder by creating `run.claim` exclusively, before any hook runs: of two runs started together
on one folder, one goes on and the other is `already_run` without running a hook. The claim is
removed when the run ends; a run killed outright leaves it, and the folder reads as `already_run`
until it is removed. After that, the planner-token budget (`freeze.json`'s planner tokens above
`SELVEDGE_PLANNER_TOKEN_BUDGET`) or a hook that is not approved makes every criterion BLOCKED
(`budget_exceeded`, `env_hooks_unapproved`) and nothing launches. Approved `reset` then `seed` hooks
run before the first browser, each through `selvedge env hook`, and the run's `data_state` is
`managed`; with neither hook it is `unmanaged` and `plan_time_actions` (what the planner's snapshots
did to the app) is carried into the verdict. A hook that runs and fails exits 1 and writes no
evidence (the claim is removed), so the folder can run again. With `auth.signed_in_check` set, the
sign-in is checked once after the hooks and before the first criterion; a failed check makes every
criterion BLOCKED `needs_auth` (see [`auth` and the sign-in check](#auth-and-the-sign-in-check)).

Each criterion runs in its own fresh guarded context: no cookie or storage carries from one to the
next (with a stored sign-in session, each starts from that same saved session). A `goto` or `request` origin `selvedge.json` no longer allows is BLOCKED `host_not_allowed`, a `request` a guard layer refuses while it runs is BLOCKED with that layer's reason (`host_not_allowed`, `remote_mutation_refused`, …), an unset
`{{NAME}}` is BLOCKED `placeholder_unset`, and a criterion under the plan's `not_planned` is
NOT_VERIFIABLE with the plan's reason. A step that throws (a locator matching nothing or more than
one element, a hidden or covered click target, a step timeout) is BLOCKED `step_failed` with its
0-based `failed_step`, and nothing after it runs; three action steps in a row that leave the page
unchanged (same url and accessibility tree) are BLOCKED `stuck_screen`. The other criteria still
run.

**The stable wait.** Every `expect` after a read waits before it is judged, whether its first read
would match or not (a check that the page did *not* change would otherwise PASS on a read taken
before an in-flight request landed): first the
network goes idle (no request in flight for 500 ms), then the DOM settles (two equal reads of the
page 500 ms apart), both within 5 s; the criterion's last `read` then runs again and the `expect`
is judged on that value. Its evidence lines say `stable_wait: true`. Honest limit: a value that
arrives by a timer alone, with no request and a DOM unchanged for longer than the settle time, is
not waited for.

**What a run leaves in its run folder** (beside the files `plan` wrote):

- `evidence.jsonl` — one JSON object per line, written only by the runner (every `{{NAME}}` value
  is written back as `{{NAME}}`). The line kinds, in order:
  - `run_start` — `ts`, `run_id`, `plan_sha256`, `playwright_version`, `data_state`, `hooks_run`,
    `plan_time_actions`, `replay_of`; exactly one, the first line.
  - `step` — `criterion`, `step` (the 0-based index), `type`, `locator`, `outcome` (`ok` or
    `failed`; `matched` or `mismatched` for an `expect`), `value` (the read value for `read`, the
    plan's own value for `fill` / `select`, else null; a `cookie:<name>` read's value is the
    cookie's fingerprint, never its value), `duration_ms`, and `error` / `stable_wait` when they
    apply; a `request` step also carries `request` — `{method, url, json_keys, status}`, the top-level
    keys of its `json` body but never the body itself; one per executed step (the stable wait's
    re-read is a second `read` line).
  - `criterion_end` — `criterion`, `outcome` (`completed`, `step_failed`, `stuck_screen`,
    `budget_exceeded`, `blocked`, `not_planned`), `reason`, `failed_step`, `screenshot`; one per
    criterion.
  - `run_end` — `ts`, `duration_ms`; the last line.
- `screenshots/<criterion-id>.png` — the end-state screenshot of each criterion that opened a page.
- `verdict.json` — the verdict ([`schemas/verdict.schema.json`](schemas/verdict.schema.json)):
  `schema_version`, `target`, `plan_sha256`, `playwright_version`, `plan_revision`,
  `prior_revisions` (for each earlier revision of the same criteria, ascending, the verdict of its
  own run, or null when it never ran), `replay_of`, `data_state`, `hooks_run`, `plan_time_actions`
  (when `data_state` is `unmanaged`), and per criterion `verdict`, `evidence_class`
  (`structured-read`), `read_value`, `matched`, `expected`, `reason`, `failed_step`,
  `interpretation`, `unverified_assumptions` and `steps` (each step's index, type, outcome and
  duration).
- `traces/<criterion-id>.zip` — with `--trace` only (below).

**`.selvedge/runs.jsonl` gains exactly one run line per run**: `{"event": "run", ts, run_id, entry,
counts, verdict, planner_tokens, duration_ms, plan_sha256, criteria_sha256, plan_revision,
replay_of}`. `entry` is `SELVEDGE_ENTRY` (`session` by default, or `ci` / `loomwright`);
`counts` holds the number of criteria per verdict; `verdict` is the run's overall verdict;
`planner_tokens` is the plan's own planner cost from `freeze.json` (the run itself spends none).

**`selvedge verdict <run-dir>`** turns `evidence.jsonl` and `plan.json` into `verdict.json` and
nothing else decides a verdict: `run` calls the same derivation once its evidence is closed. Per
criterion, the first match wins: no `criterion_end` line is BLOCKED `run_interrupted`; a
`not_planned` end is NOT_VERIFIABLE with its reason; any other end but `completed` is BLOCKED with
its reason; an empty judged read is NOT_VERIFIABLE `no_value_read` (even for `equals ""`); an
`expect` that mismatched after the stable wait is FAIL, with `read_value` and `expected`; an
`expect` that held on an empty read is NOT_VERIFIABLE `no_value_read` even when a later one held
(reported on that pair); a match
with a `material: true` assumption is NOT_VERIFIABLE `material_assumption`; else PASS. Every
`expect` in a criterion is a check: the judged one is the first that mismatched, else the last one,
and the judged read is the read it checked, so an earlier failed check is never outweighed by a
later one that held. Re-running
`verdict` re-derives the same file and appends nothing to `runs.jsonl`. It exits 2
`evidence_missing` when there is no `evidence.jsonl` (or a line cannot be trusted), and
`plan_modified` when `plan.json` is not the plan the run executed.

**Exit precedence** for `run` and `verdict`: `1` any FAIL, else `2` any BLOCKED (or a refusal
above), else `3` any NOT_VERIFIABLE, else `0`. stdout holds one line per criterion,
`<VERDICT> [<reason>] <criterion-id>`, then `verdict <VERDICT> <path to verdict.json>`.

**`--replay <frozen-run-dir>`** runs a frozen plan again, for regression. Every check above runs
against the frozen folder first, except `already_run` (a folder that ran is the one being replayed);
the freeze-line check is that run's own line, so a folder with no freeze line (a replay folder) is
`plan_modified`: replay the folder it replayed. Only then is a new run folder created, holding byte
copies of `criteria.json`, `plan.json`, `plan.sha256` and `freeze.json`, and the plan runs there
unchanged: `replay_of` (in `run_start`, `verdict.json` and the run line) is the frozen run id,
`plan_revision` is the plan's own, and `planner_tokens` is 0 (no planner-token budget applies). A
replay never repairs a plan: a renamed button the frozen locator no longer matches is BLOCKED
`step_failed` at that step. A replay that writes no evidence (a refusal, a failing hook) leaves no
new folder behind.

**`--trace`** keeps a Playwright trace of each criterion as `traces/<criterion-id>.zip`, redacted
before it is written: every `Cookie`, `Set-Cookie` and `Authorization` header value reads
`[redacted]`; every cookie value seen in any of those headers, and every `Authorization` value, is
replaced by `[redacted]` wherever it appears in the trace (a page's HTML or script included); and
every resolved `{{NAME}}` value goes back to `{{NAME}}`. With a stored sign-in session (below), the
storage state Playwright records for the context reads `[redacted]`, and every cookie and local
storage value the session holds is replaced by `[redacted]` wherever it appears, as stored and
URL-encoded; a session value shorter than 8 characters (a `"1"` flag) is left alone outside the
storage state, even where a header replays it (the header itself still reads `[redacted]`), since replacing it everywhere would mangle the trace. A `{{NAME}}` value is caught
URL-encoded too. The raw trace is
written to a private temp folder and deleted. Selvedge reads and rewrites the zip itself (Node's `zlib`, no zip tool),
and a trace it cannot redact whole (zip64, encryption, an unknown compression method, a bad
checksum, a binary entry holding a secret) is dropped, never kept: stderr says
`trace: dropped (<why>)`. Traces carry DOM snapshots but no screenshots (an image of a typed value
cannot be redacted). Honest limit: a value the page shows transformed (cut, re-cased, reversed) is
not caught. Without `--trace` nothing is traced.

## `comment`: the verdict on the PR

```
selvedge comment <run-dir> --pr <n> [--yes] [--base <ref>] [--allow-public-values]
```

Posts a run folder's verdicts to PR `<n>` as **one** comment. The comment carries a hidden marker,
`<!-- selvedge:verdict -->`; `comment` lists the PR's comments (`gh api --paginate`), takes the first
whose body holds the marker **and** whose author is the account `gh` is signed in as (`gh api user`),
updates it in place (`PATCH`), and creates one (`gh pr comment --body-file`) only when none does. The
marker is public text, so a marked comment by anyone else is never updated, and when the signed-in
login cannot be read `comment` exits 1 without posting. A comment without the marker is never touched
(it does not use `gh pr comment --edit-last`, which edits your last comment whatever it is). The body always
reaches `gh` as a file, never as command-line text. stdout is the comment URL, never the body.

**What the body shows.** A summary line (`3 PASS · 1 PASS after revision · 1 FAIL`, zero counts left
out), the short plan sha256 and revision, then one collapsed block per criterion: the criterion text,
the verdict, the planner's interpretation, its unverified assumptions (material ones marked), the
plan's steps as type and locator, the expected value (op and value from the plan), whether it
matched, the evidence class, and for BLOCKED / NOT_VERIFIABLE the reason with a hint to unblock it.
For a criterion the plan did not plan, the block also shows the planner's own `detail` (the pages
it looked at) and `rewrite` when the plan has them, redacted like a read value.

**What it never shows.** No link: a `goto` shows its URL's path only, and every URL in the criterion
text, interpretation, assumptions or expected value is cut to its path (no origin, no query string).
No `fill` or `select` value (those steps show type and locator only), no `{{NAME}}` value, no header
name (`Cookie`, `Set-Cookie`, `Authorization` read `[redacted]` wherever they appear), and nothing
from `evidence.jsonl`, screenshots or traces.

**Read values** (what each criterion's check read from the page or from a reply: a
`response_text` or `response_json:` read is a read value too) are not published unless the
**base branch's** `selvedge.json` sets `"comment": {"read_values": true}`. The base is `--base <ref>`
or, by default, `origin/<the PR's base branch>` (`gh pr view <n> --json baseRefName`); the working
tree's `selvedge.json` is never read here, so a PR cannot opt itself in. A base ref without a
readable `selvedge.json` leaves the defaults (values unpublished). With the opt-in on, `gh repo view
--json visibility` must say `PRIVATE`: a public or internal repo, or one whose visibility cannot be
read, is refused `read_values_public_repo` and nothing is posted, unless you pass
`--allow-public-values`. A published value is redacted first: an email address, a run of 6 or more
digits, a URL query string and a base64 or hex token of 32 or more characters become `[redacted]`,
then every `comment.redact` pattern is applied on top. A criterion whose plan reads a
`cookie:<name>` never shows a read value, opt-in or not: a fingerprint is not published. Honest limit: patterns cannot catch every
personal detail (a name, an address), so publish values only where every reader may see them.

**Revisions.** When the plan is a later revision of the same criteria, each criterion's verdict cell
lists its own verdict on every earlier plan, read from that revision's own run (the `runs.jsonl` run
line, never a replay) and its run folder's `verdict.json`: `FAIL on plan 1 → PASS on plan 2`. A
revision that never ran reads `not run on plan <r>`. When that run folder (it lives under the
gitignored `.selvedge/runs/`, so a fresh clone or a CI runner lacks it), its `verdict.json` or the
criterion's entry is gone, the cell shows the whole run's verdict labelled as such,
`FAIL on plan 1 (whole run) → PASS on plan 2`. The summary counts a criterion as `PASS after
revision` when it passes now and its own verdict on an earlier plan was not PASS; a whole-run
fallback never counts as one.

**Confirmation.** Without `--yes`, `comment` asks once on the terminal (`y` posts; anything else
posts nothing and exits 0); with stdin not a terminal it exits 2 `comment_requires_yes`. A run folder
with no `verdict.json` is refused `verdict_missing`, and one whose `plan.json` sha256 is not
`verdict.json`'s `plan_sha256` is refused `plan_modified`; nothing is posted. A failing `gh` exits 1.

## `/selvedge:verify`: the Claude Code adapter

```
/selvedge:verify <PR number | criteria file | pasted criteria>
```

The check, run from a Claude Code session by an agent that did not write the code: an
implementing agent checking its own work checks its own reading of the brief.

- **The command** ([`commands/verify.md`](commands/verify.md)) resolves its argument to a criteria
  command: a PR number to `selvedge criteria from-pr <n>`, an existing file to
  `selvedge criteria from-md <file>`, anything else to `selvedge criteria from-text` (the text on
  stdin). It spawns the verifier, then reads the run folder's `verdict.json` and `criteria.json`
  itself and shows one row per criterion (verdict, reason, text), the overall verdict, the plan
  sha256 and the run folder. It never writes a plan or a verdict.
- **The verifier** ([`agents/verifier.md`](agents/verifier.md)) is a subagent whose tools are
  exactly Bash and Read. It works only through the CLI, in this order: `criteria` (plus
  `criteria check`), `plan --init`, `snapshot --run-dir <the folder plan --init printed>`,
  `plan --validate` (it writes `plan.json` into the run folder with a shell heredoc, following
  [`prompts/planner.md`](prompts/planner.md)), `plan --freeze`, `run`, `verdict`. It never edits
  `plan.json` after the freeze, never reads `~/.local/state/selvedge/` (the stored sign-in
  session), never runs `comment`, `env approve`, `env hook` or `auth setup`, and never looks at the
  app except through `snapshot`. `maxTurns` bounds its run; its `token_budget` frontmatter bounds
  its prompt, which `tests/test-adapter.sh` measures as the file's bytes / 4.
- **Posting** happens only for a PR source, only after the command asks once and you answer yes,
  and only through `selvedge comment <run-dir> --pr <n> --yes`. A file or pasted-text source, any
  other answer, or a session that cannot ask (`claude -p`) posts nothing.
- **The skill** ([`skills/verify/SKILL.md`](skills/verify/SKILL.md)) is the same workflow, in the
  same command order, for any agent host that can run shell commands and read files; it is listed
  in [`skills/SKILLS_INDEX.md`](skills/SKILLS_INDEX.md).

It needs the CLI on `PATH` (`selvedge install-cli`; the command stops and says so otherwise), the
app running, and the same tools as `run`. The verdict is the CLI's: a live `/selvedge:verify`
session and a hand-run `selvedge run --replay` of its frozen plan gave the same per-criterion
`verdict.json` ([`docs/evidence/verify-adapter-equivalence.md`](docs/evidence/verify-adapter-equivalence.md)).
Honest limit: the verifier's tool list keeps it off Write and Edit, not off the shell; Bash can
still write files, so the prohibitions above are instructions, and the frozen plan's sha256 is what
makes a changed plan detectable (`plan_modified`).

## `auth` and the sign-in check

```
selvedge auth setup [--base <ref>]   run the approved hooks.auth_setup and keep the session it writes
selvedge auth setup --headed         sign in yourself in a visible guarded browser and keep that session
```

A walled page needs a signed-in browser, and an agent that types a password leaves it in its
transcript and in traces. So no model signs in: `selvedge auth setup` does it once, outside any
plan or run, and keeps the session (a Playwright storage state: cookies and local storage) where
`selvedge run` loads it.

- **`setup`** runs `hooks.auth_setup` through `selvedge env hook auth_setup`, so it needs your
  approval (`BLOCKED env_hooks_unapproved` otherwise) and every origin local
  (`BLOCKED env_hooks_remote_origin`). The hook's credentials come only from the environment
  variables `auth.env` names; one unset is `BLOCKED placeholder_unset` (stderr names it, never a
  value) and the hook does not run. The hook writes the storage state as JSON to the path in
  `SELVEDGE_STORAGE_STATE`; a hook that exits 0 without writing it, or writes something that is not a
  storage state Playwright loads (a JSON object whose `cookies` and `origins` have Playwright's
  shape and cookie rules: an `expires` of -1 or a unix time, an `http`/`https` `url`), exits 1 and
  nothing is kept. With no `hooks.auth_setup` and no `--headed` it is a usage
  error naming both.
- **`setup --headed`** needs `auth.signed_in_check`: it opens the guarded browser visibly at its
  `url` and waits (up to `SELVEDGE_AUTH_TIMEOUT_MS`, default 300000) while you sign in, until the
  locator matches, then keeps that session. No hook runs and no credential passes through selvedge.
  It needs a display, so it cannot run in CI; its tests use a stub Playwright.
- **Where the session lives:** `$HOME/.local/state/selvedge/<repo-id>/auth/storageState.json`, where
  `<repo-id>` is the sha256 of the repo's identity (the same identity approvals use). The
  directories are mode `0700` and the file `0600`, set by selvedge whatever the hook's umask. A path
  that would resolve inside the repo is never written or read.

**What `run` does with it.** Only when `selvedge.json` has an `auth` key (without one, `run` is
unchanged): every criterion's context starts from the stored session when the file exists, and the
value of every variable `auth.env` names is redacted like a `{{NAME}}` value (written back as
`{{APP_PASS}}`) in `evidence.jsonl`, `verdict.json` and stderr (and in what `selvedge snapshot`
prints, the page a planner looks at). A stored session file Playwright would not load (not JSON, or
not a storage state's shape or cookie rules) makes every criterion BLOCKED `needs_auth` before any
browser opens, with or without a sign-in check; a session Playwright itself refuses when the context
opens is `needs_auth` too, never `playwright_unavailable`. With `auth.signed_in_check` set, the
run checks the sign-in **once**, after the hooks and before the first criterion: one guarded
context with the stored session opens the check `url`, and the locator must match at least one
element within `SELVEDGE_STEP_TIMEOUT_MS`. When it does not (no session, an expired one, a redirect
to a login page):

- **nobody can sign in** — stdin is not a terminal, or `run --non-interactive` — every criterion is
  BLOCKED `needs_auth` at once, no criterion's steps run, and the run still writes its evidence,
  `verdict.json` and its `runs.jsonl` line (exit 2). There is no retry loop.
- **on a terminal** — stderr says what is needed (`selvedge auth setup --headed`), waits for one
  line (Enter), checks exactly once more, and either goes on or makes every criterion BLOCKED
  `needs_auth`. There is never a third check.

`run` never runs `auth_setup` itself. After signing in, run the plan again with
`selvedge run --replay <run-dir>` (a folder runs once). Wrappers and CI pass `--non-interactive`.
Limit: `selvedge snapshot` (what a planner looks through) does not load the session, so a planner
cannot see a walled page; its steps are written from what it can see, or by hand.

**Honest limit.** An agent with shell access can read any file you can, the session file and your
environment variables included: selvedge keeps secrets out of plans, evidence, PR comments and model
prompts, and does not claim they are out of reach. The redaction finds a value as given, in the
quoted forms Playwright prints and URL-encoded; a page that shows it cut, re-cased or otherwise transformed is not
caught. A hook that prints its own credentials prints them: its output is your command's.

## Environment variables

Read by the CLI only, never from a file in the repo:

- `SELVEDGE_PLANNER` — the planner command (`/bin/sh -c`); unset, `claude -p`.
- `SELVEDGE_PLANNER_MODEL` — the default planner's `--model` (default `sonnet`).
- `SELVEDGE_PLANNER_TOKEN_BUDGET` — a whole number of tokens, given to the planner and recorded in
  `freeze.json` (not enforced at plan time); `run` makes every criterion BLOCKED `budget_exceeded`
  when the plan's planner tokens exceed it.
- `SELVEDGE_SNAPSHOT_BUDGET` — `snapshot` calls per run folder (default 20).
- `SELVEDGE_PLAYWRIGHT_MODULE` — the Playwright entry `snapshot` and `run` load (above).
- `SELVEDGE_ENTRY` — how `run` was started, recorded in its `runs.jsonl` line: `session` (the
  default), `ci` or `loomwright`; any other value is a usage error.
- `SELVEDGE_RUN_BUDGET_MS` — the wall clock a `run` may spend, in milliseconds (default 600000),
  checked before each criterion starts: once it is spent, every criterion not yet started is
  BLOCKED `budget_exceeded` and gets no browser.
- `SELVEDGE_STEP_TIMEOUT_MS` — the time one action of a `run` may take, in milliseconds (default
  5000); a step that runs out is BLOCKED `step_failed`. The sign-in check waits as long for its
  locator.
- `SELVEDGE_AUTH_TIMEOUT_MS` — how long `auth setup --headed` waits for you to sign in, in
  milliseconds (default 300000).
- `SELVEDGE_STORAGE_STATE` — set by `auth setup` for its `auth_setup` hook: the path the hook writes
  the storage state to (selvedge then moves it into place, mode `0600`).
- `SELVEDGE_RUN_DIR` — the run folder `snapshot` records in, when `--run-dir` is not given.
- `SELVEDGE_BASE` — the config source `snapshot` reads (a ref, or empty for the working tree);
  set by `plan` for its planner, and a `--base` naming another is refused.
- `SELVEDGE_CRITERIA`, `SELVEDGE_PLAN_OUT`, `SELVEDGE_BIN`, `SELVEDGE_PLANNER_USAGE` — set by
  `plan` for the planner it runs (above), together with `SELVEDGE_RUN_DIR` and `SELVEDGE_BASE`.

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
`NOT_VERIFIABLE <reason>` and exit 3; a plan also records them per criterion under `not_planned`,
and `verdict.json` records each criterion's reason beside its verdict.

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
| `step_failed` | BLOCKED | a plan step (or a snapshot prefix step) could not be carried out: its locator matched nothing, or the element was hidden, covered or not ready in time; the failing step's index is recorded |
| `stuck_screen` | BLOCKED | consecutive action steps left the page unchanged, so the criterion stopped before its check |
| `budget_exceeded` | BLOCKED | the run's wall-clock or planner-token budget was spent before the criterion started |
| `run_interrupted` | BLOCKED | `evidence.jsonl` has no end line for a planned criterion: the run stopped before the criterion finished |
| `needs_auth` | BLOCKED | `auth.signed_in_check` did not match (no session, or an expired one) and nobody could sign in; run `selvedge auth setup` (or `--headed`) |
| `criterion_not_testable` | NOT_VERIFIABLE | the criterion is vague (no observable value); it is not planned and carries a rewrite |
| `side_effect_not_observable` | NOT_VERIFIABLE | the criterion names no effect a check can read, on any page the planner looked at or in any reply a `request` step can read (an email sent, a queued job no page or endpoint reports); it is not planned, and its detail names the pages and endpoints looked at |
| `exploration_budget` | NOT_VERIFIABLE | the run folder's snapshot calls are used up, so the planner could not explore further |
| `no_value_read` | NOT_VERIFIABLE | the criterion's final `read` gave an empty value (`""` or none: a `response_json:` pointer that names nothing, a body that is not JSON, a `cookie:` that is absent), so nothing was verified, even when the `expect` would hold |
| `material_assumption` | NOT_VERIFIABLE | the `expect` held, but the plan records an assumption marked `material: true` for the criterion; `verdict.json` carries its text |
| `origins_empty` | config | `origins` is absent or empty; add the app you test, e.g. `http://localhost:3000` |
| `origin_invalid` | config | an origin is not exactly `scheme://host[:port]` |
| `remote_origin_without_allow_remote` | config | a non-local origin is listed without `"allow_remote": true` |
| `config_absent` | config | no `selvedge.json` at the repo root; run `selvedge env init` |
| `config_invalid_json` | config | `selvedge.json` is not valid JSON |
| `config_schema_violation` | config | an unknown key (an `auth`, `signed_in_check` or `comment` key included), an unknown hook name, a value of the wrong type (a `comment.redact` entry that is not a valid regular expression included), an `auth.signed_in_check.url` on an origin `origins` does not list, or a sign-in locator that is not one plan-step locator form (CSS or XPath) |
| `base_config_unreadable` | config | `--base <ref>` given, but `<ref>:selvedge.json` cannot be read |
| `approve_requires_tty` | usage | `env approve` was run without an interactive terminal |
| `read_values_public_repo` | usage | `comment`: the base branch's `selvedge.json` sets `comment.read_values`, but the repo is not `PRIVATE` (or its visibility cannot be read) and `--allow-public-values` was not given; nothing is posted |
| `comment_requires_yes` | usage | `comment` was run without `--yes` and stdin is not a terminal; nothing is posted |
| `verdict_missing` | usage | `comment` found no usable `verdict.json` in the run folder; run `selvedge verdict <run-dir>` first |
| `port_required` | usage | `env init` found no port (`--port`, `package.json` scripts, or a TTY prompt) |
| `already_frozen` | usage | `plan --freeze` on a run folder that already holds a frozen plan; a new plan goes in a new folder |
| `plan_invalid` | usage | `plan --validate`, a freeze (`plan`, `plan --freeze`) or a snapshot prefix found problems; each is listed on its own line, and nothing is hashed |
| `criteria_invalid` | usage | a `criteria.json` is not valid JSON or does not match its schema (an id that is not its text's hash included) |
| `criteria_not_found` | usage | no criteria were found in the input, or the `criteria.json` file is missing or empty |
| `planner_failed` | usage | the planner exited non-zero, wrote no plan, or could not be started |
| `plan_modified` | usage | the sha256 of a run folder's `plan.json` is not the one it was frozen (or run) with; nothing runs and no verdict is derived |
| `already_run` | usage | the run folder already holds `evidence.jsonl`, or `run.claim` (another run of it is under way); a frozen plan runs once, a re-run goes through `--replay` |
| `not_frozen` | usage | the run folder holds no frozen plan (no `plan.sha256`, or no `plan.json` for `verdict`); freeze it with `selvedge plan --freeze` |
| `evidence_missing` | usage | `verdict` found no usable `evidence.jsonl` in the run folder: it is absent, or a line is not one of the known evidence line kinds |

## Measuring Selvedge: the known-answer set

`selvedge/eval/` holds a set of acceptance criteria whose right answers are known, used to measure
how often Selvedge says PASS when the answer is FAIL. It is an owner-only measurement tool, not part
of the CLI: nothing in `bin/` or `lib/` reads it. The set is split by underlying defect into a
tuning side and a held-out side, and the held-out answers file lives outside this repository (the
answers of held-out real-bug and non-defect cases can still be worked out from committed data;
the held-out planted variants and their answers are withheld). The set's sizes and the measured rates appear here
only in the results block below, which `node selvedge/eval/harness.mjs readme` generates from
[`eval/results.json`](eval/results.json) and `tests/test-eval-harness.sh` holds equal to it;
`node selvedge/eval/eval-set.mjs count` prints each count beside its floor. The layout, the split
rule, the outside folder, the harness and every command are in [`eval/README.md`](eval/README.md).

<!-- selvedge-eval-results:begin (generated by node selvedge/eval/harness.mjs readme; do not edit) -->

Generated from [`eval/results.json`](eval/results.json), which holds every report; the latest of each set is shown. Gate: false-PASS point estimate at most 0.05 and abstention at most 0.2 on a held-out set with a known-FAIL denominator at or above its floor.

**Held-out set — selvedge 0.11.1, planner sonnet, 2026-11-24, 235 case(s).**

Phase 3 gate: **not met** (abstention 0.4553 > 0.2).

| Rate | Numerator / denominator | Point estimate | 95% interval (Clopper-Pearson) |
|---|---|---|---|
| false-PASS (PASS on known-FAIL) | 0 / 85 | 0.0000 | 0.0000 – 0.0425 |
| false-FAIL (FAIL on known-PASS) | 4 / 150 | 0.0267 | 0.0073 – 0.0669 |
| abstention (BLOCKED + NOT_VERIFIABLE) | 107 / 235 | 0.4553 | 0.3904 – 0.5213 |

model-judged criteria, counted apart: 0. Runner flips: 0 of 212 case(s) over 1 run(s) of one frozen plan; planner flips: 0 of 235 case(s) over 1 fresh plan(s).

**Tuning set — selvedge 0.11.0, planner sonnet, 2026-11-23, 72 case(s).**

Phase 3 gate: not evaluated (the gate reads held-out reports only).

| Rate | Numerator / denominator | Point estimate | 95% interval (Clopper-Pearson) |
|---|---|---|---|
| false-PASS (PASS on known-FAIL) | 0 / 12 | 0.0000 | 0.0000 – 0.2646 |
| false-FAIL (FAIL on known-PASS) | 0 / 60 | 0.0000 | 0.0000 – 0.0596 |
| abstention (BLOCKED + NOT_VERIFIABLE) | 28 / 72 | 0.3889 | 0.2762 – 0.5111 |

model-judged criteria, counted apart: 0. Runner flips: 0 of 63 case(s) over 1 run(s) of one frozen plan; planner flips: 0 of 72 case(s) over 1 fresh plan(s).

<!-- selvedge-eval-results:end -->

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
