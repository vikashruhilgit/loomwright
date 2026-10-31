# Evidence — provider probe (`setup-providers.sh check`)

Real output from this machine (the owner's macOS dev box), captured 2026-10-27 at 11:11 UTC on branch
`feature/providers-probe-setup-check`, base commit `84d9023b2d7561c3c34929df3e64696bad7b2339`. Source requirement:
`.supervisor/requirements/provider-routing/02-providers-probe.md`. This is the input item 03 rewrites its premises
from.

Nothing in the transcript is hand-written. The one edit is path redaction: the repo root reads `<repo>`.

## CLI versions on this machine

| CLI | On PATH | Version |
|-----|---------|---------|
| `claude` | yes | `2.1.309 (Claude Code)` |
| `cursor-agent` | yes | `2026.10.22-27dcf5f` (it was `2026.09.18-9a7762b` earlier the same day; it updated itself between two runs) |
| `codex` | no | — |
| `gemini` | no | — |
| `grok` | no | — |
| `copilot` | no | — |

## The report

```text
$ bash loomwright/scripts/setup-providers.sh check
setup-providers check — read-only probe of the provider table
  date: 2026-10-27T11:11:50Z · providers dir: <repo>/loomwright/scripts/adapters/providers
  smoke: fixed prompt (no repo content) · cwd: a throwaway mktemp -d dir, never the repo · HOME: the REAL HOME (login state lives there; never scrubbed) · timeout 120s (other calls 20s)
  writes: only its own mktemp -d scratch dir, removed on exit · never installs anything · never reads, prints or stores an API key or token
  limit: a provider CLI may write its own session/state files under the real HOME while the smoke runs
  legend: a ":" after a column name marks a column that did not pass

claude: installed 2.1.309 (Claude Code) · auth ok · headless pass · permissions pinnable · browser: unknown => usable for write seats
codex: installed: no => not usable: installed
    install: npm install -g @openai/codex
copilot: installed: no => not usable: installed
    install: npm install -g @github/copilot
cursor (cursor-agent): installed 2026.10.22-27dcf5f · auth ok · headless pass · permissions: unpinnable · browser: unknown => usable for read-only seats
gemini: installed: no => not usable: installed
    install: npm install -g @google/gemini-cli
grok: installed: no => not usable: installed
    install: curl -fsSL https://x.ai/cli/install.sh | bash
$ echo $?
0
```

The run took about 28 seconds; nearly all of it is the two real smokes.

## What the report establishes

- **`claude`: usable for write seats.** Auth came from its own auth-status command, the smoke returned the fixed
  reply inside the `.result` envelope the lens adapter unwraps, and `--help` advertises the same permission-pinning
  flags `dispatch-pr-review.sh` requires before it dispatches.
- **`cursor-agent`: usable for read-only seats, not write seats.** It was logged in on 2026-10-27, which corrects the
  source requirement's premise that it was not. The smoke passed, and the reply came back in a top-level `.result`
  string, so the lens adapter's envelope guess for this CLI held. Permissions are `unpinnable` by its table entry's
  declaration: print mode "Has access to all tools", there is no per-invocation allowlist flag, and the entry never
  adopts `-f`/`--force`. The smoke needs `--trust`. Without it, print mode exits 1 with "Workspace Trust Required"
  for any directory it has not seen, and the smoke's cwd is always new.
- **`grok`: OUTSTANDING.** `grok` was not installed when this item ran, so the row above is the real
  `installed: no` row. The real-binary report AC2 asks for (real values in the installed, auth and headless columns)
  **has not been produced**. It is still owed once the owner installs and logs in to `grok`: re-run the command
  above and append the output here. Until then every `grok` invocation field in `provider-grok.sh` is a DOCUMENTED
  ASSUMPTION taken from docs.x.ai (cited with dates in that file's header). The stub suite covers the code paths, but
  no real `grok` binary has exercised them.
- **`codex`, `gemini`, `copilot`:** not installed. Their rows show the install hint, nothing else ran, and their
  table fields stay DOCUMENTED ASSUMPTIONs.
- **`browser` is `unknown` for every provider.** No probe has shown any of them driving a browser.

## Honest limits

- **The script's own writes are contained. A vendor CLI's writes are not.** `test-setup-providers.sh` asserts, with
  stub CLIs and a temp HOME, that the script writes nothing outside its `mktemp -d` scratch dir and removes that on
  exit. A real smoke runs a real vendor CLI under the real HOME, and that CLI may write its own state. What was
  observed after this run:
  - `cursor-agent` created a per-directory entry under its own projects directory in the home tree, named after the
    smoke's throwaway cwd. Each run adds one. It also updated itself between two runs the same day.
  - `claude` left no project or session entry for the smoke's cwd under its own config tree. The smoke passes
    `--no-session-persistence` and `--safe-mode`, which skips user hooks, plugins and MCP servers.
- **The smoke spends real model calls.** Each installed, logged-in provider answers one short fixed prompt per
  `check` run.
- **`pinnable` means the pinning flags exist in `--help`.** For `claude` that is the same test the drain dispatcher
  already relies on. For `grok` and `copilot` it would mean only that their documented flags are present. No
  denial has been observed on a real binary.
- **Auth for `grok`, `copilot`, `codex` and `gemini` is decided by the smoke.** None of them documents a
  non-interactive auth-status command that this item could find. A passing smoke proves auth. A failing smoke is
  reported `not_logged_in` only when its output matches the table entry's not-logged-in pattern, and that pattern
  is a guess at the vendor's wording until a real logged-out run confirms it.
- **AC6's "the headless smoke is NOT run" for a logged-out CLI holds only for providers with an auth-check
  command** (`claude`, `cursor-agent`). For `grok`, `copilot`, `codex` and `gemini` the smoke is the only auth
  signal, so a logged-out CLI of that kind does have its smoke run, and that smoke is what reports it
  `not_logged_in`. AC2 (real auth and headless values for `grok`) and AC6 cannot both hold without a vendor
  auth-status command; this item chose AC2. This is an open scope decision for the owner, not a settled reading of
  AC6.
- **A smoke that fails for a non-auth reason leaves auth unproven, and the report says so.** Such a row reads
  `auth: unknown (smoke failed: <reason>)` and still ends `not usable: auth` (the first failing column). Its login
  hint is printed as `login (only if not logged in): …`, never as a plain instruction to log in, because the CLI
  may well be logged in.

## Re-run after provider-routing/05 (provider launch parity)

Captured 2026-10-31 between 05:56 and 05:59 UTC on branch `feature/provider-launch-parity`, at commit
`8d3f2705bc6c1ce4435b01f584833120821219b9` plus this item's then-uncommitted `setup-providers.sh` (the version
committed with this section). Source requirement: `.supervisor/requirements/provider-routing/05-provider-launch-parity.md`. Every
CLI call in `check` now goes through `loomwright/scripts/adapters/providers/launch-provider-cli.sh`, the same
launcher `lens-run.sh` uses: scrubbed env, a fresh isolated HOME per call holding only the provider's declared login
files, its own process group. The 02 record above is left as it was; it describes the old launch under the real HOME.

Nothing in the transcripts is hand-written. The one edit is path redaction: the repo root reads `<repo>`.

### CLI versions on this machine

| CLI | On PATH | Version |
|-----|---------|---------|
| `claude` | yes | `2.1.314 (Claude Code)` |
| `cursor-agent` | yes | `2026.10.22-27dcf5f` |
| `grok` | yes | `grok 1.0.70 (f50904eaee6c)` |
| `codex`, `gemini`, `copilot` | no | — |

### Run 1 (full report)

```text
$ bash loomwright/scripts/setup-providers.sh check
setup-providers check — read-only probe of the provider table
  date: 2026-10-31T05:56:29Z · providers dir: <repo>/loomwright/scripts/adapters/providers
  smoke: fixed prompt (no repo content) · cwd: a throwaway mktemp -d dir, never the repo · HOME: an isolated per-call HOME under the shared launcher (launch-provider-cli.sh: env scrubbed, only the provider's declared login files / env vars cross), never the real HOME: the launch a routed step gets · timeout 120s (other calls 20s)
  diagnosis: an isolated auth check or smoke that reports no login is re-run once under the real HOME (env still scrubbed; a smoke rerun is one more model call) only to tell not_logged_in_isolated from not_logged_in; nothing is graded from it
  permission probe: one model call per candidate provider (pin flags advertised + smoke passed): a fixed prompt asks it to create probe.txt in an empty throwaway cwd; pinnable only when it answers and nothing appears there
  writes: only its own mktemp -d scratch dir, removed on exit · never installs anything · never reads, prints or stores an API key or token
  limit: a provider CLI may write its own session/state files under the real HOME during a diagnosis rerun (an isolated HOME is discarded after each call) · the permission probe is one denial observed on one fixed prompt, not a sandbox
  legend: a ":" after a column name marks a column that did not pass

claude: installed 2.1.314 (Claude Code) · auth: not_logged_in_isolated (ok in your shell) · headless: not run (auth not ok) · permissions: pin flags advertised (unverified) · browser: unknown => not usable: auth
    fix: logged in under your real HOME, but the login did not cross the isolated HOME a routed step runs under (declared login files: none; env vars: ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN). Set one of the declared env vars where loomwright runs, or declare where this CLI keeps its login in provider-claude.sh PROVIDER_LOGIN_FILES; a keychain-only login cannot be copied.
codex: installed: no => not usable: installed
    install: npm install -g @openai/codex
copilot: installed: no => not usable: installed
    install: npm install -g @github/copilot
cursor (cursor-agent): installed 2026.10.22-27dcf5f · auth: not_logged_in · headless: not run (auth not ok) · permissions: unpinnable · browser: unknown => not usable: auth
    login: cursor-agent login
gemini: installed: no => not usable: installed
    install: npm install -g @google/gemini-cli
grok: installed grok 1.0.70 (f50904eaee6c) · auth ok (via smoke) · headless pass · permissions: pin flags advertised (unverified) · browser: unknown => usable for read-only seats
$ echo $?
0
```

It took 18 seconds. The grok smoke and the grok permission probe were the only model calls; `claude` and
`cursor-agent` stop at their auth-check commands.

### Runs 2 and 3 (rows only, same code, 05:58:47Z and 05:59:05Z)

```text
claude: installed 2.1.314 (Claude Code) · auth: not_logged_in_isolated (ok in your shell) · headless: not run (auth not ok) · permissions: pin flags advertised (unverified) · browser: unknown => not usable: auth
    fix: logged in under your real HOME, but the login did not cross the isolated HOME a routed step runs under (declared login files: none; env vars: ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN). Set one of the declared env vars where loomwright runs, or declare where this CLI keeps its login in provider-claude.sh PROVIDER_LOGIN_FILES; a keychain-only login cannot be copied.
cursor (cursor-agent): installed 2026.10.22-27dcf5f · auth: not_logged_in_isolated (ok in your shell) · headless: not run (auth not ok) · permissions: unpinnable · browser: unknown => not usable: auth
    fix: logged in under your real HOME, but the login did not cross the isolated HOME a routed step runs under (declared login files: none; env vars: CURSOR_API_KEY). Set one of the declared env vars where loomwright runs, or declare where this CLI keeps its login in provider-cursor.sh PROVIDER_LOGIN_FILES; a keychain-only login cannot be copied.
grok: installed grok 1.0.70 (f50904eaee6c) · auth ok (via smoke) · headless pass · permissions pinnable · browser: unknown => usable for write seats
```

```text
claude: installed 2.1.314 (Claude Code) · auth: not_logged_in_isolated (ok in your shell) · headless: not run (auth not ok) · permissions: pin flags advertised (unverified) · browser: unknown => not usable: auth
    fix: logged in under your real HOME, but the login did not cross the isolated HOME a routed step runs under (declared login files: none; env vars: ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN). Set one of the declared env vars where loomwright runs, or declare where this CLI keeps its login in provider-claude.sh PROVIDER_LOGIN_FILES; a keychain-only login cannot be copied.
cursor (cursor-agent): installed 2026.10.22-27dcf5f · auth: not_logged_in · headless: not run (auth not ok) · permissions: unpinnable · browser: unknown => not usable: auth
    login: cursor-agent login
grok: installed grok 1.0.70 (f50904eaee6c) · auth ok (via smoke) · headless pass · permissions pinnable · browser: unknown => usable for write seats
```

### Where each CLI keeps its login (probed 2026-10-31)

All results come from calls through `launch-provider-cli.sh` from a throwaway cwd. Only pattern-match results and
exit codes were recorded. No credential file was read or printed, and no account name was printed.

| CLI | Login location | Command used | Isolated, nothing copied | Isolated, declared copy | `shell` mode (real HOME, env scrubbed) |
|-----|----------------|--------------|--------------------------|-------------------------|-----------------------------------------|
| `grok` | the file `.grok/auth.json` (relative to `$HOME`), plus the env var `XAI_API_KEY` (unset here) | `grok --no-auto-update models` (no model call) | matches its not-logged-in pattern | `.grok/auth.json` copied: no not-logged-in wording | no not-logged-in wording |
| `cursor-agent` | keychain only: no file carries it. `CURSOR_API_KEY` (unset here) is its env-var login | `cursor-agent status` | `Not logged in` | `.cursor/cli-config.json` copied: still `Not logged in` | `Logged in as …` |
| `claude` | keychain only: `.claude/.credentials.json` is absent. `ANTHROPIC_API_KEY` and `CLAUDE_CODE_OAUTH_TOKEN` (both unset here) are its env-var logins | `claude auth status --json` | `"loggedIn": false`, exit 1 | nothing is declared | `"loggedIn": true`, exit 0 |

File presence was checked with `[ -f "$HOME/<path>" ]`. Whether an env var was set was checked with `${VAR+x}`, and
its value was never expanded.

### What the re-run establishes

- **`grok`: `usable for write seats` in runs 2 and 3, and `usable for read-only seats` in run 1.** Its login crosses
  isolation through the declared `.grok/auth.json` copy, and the smoke passes under the isolated HOME (`auth ok (via
  smoke)`).
- **Grok permission probe:** `--no-auto-update --output-format json --permission-mode dontAsk -p <fixed write
  request>`, with no `--allow` or `--deny` rule, run under the isolated HOME from an empty throwaway cwd. I also ran
  it once by hand through the launcher. Grok exited 0 and answered ("I'll create `probe.txt` …"), and its stderr
  said ``permission required: Write `<cwd>/probe.txt` was not run, as a headless run cannot ask for approval``. The
  cwd stayed empty, which is a denial. The check graded it `pinnable` in runs 2 and 3 and in one instrumented run.
  In run 1 it graded `pin flags advertised (unverified)`. No file appeared in any run, so the probe either did not
  exit 0 or gave no reply the envelope could unwrap. Which of the two is not known: `check` keeps no probe output by
  design. Either way the row fell back to not-pinnable. **So grok graded `pinnable` in 3 of the 4 `check` runs that
  reached the probe: a result that held most of the time, not a constant.**
- **The source requirement's observation was not reproduced under the isolated HOME.** It said that on 1.0.70
  `--permission-mode dontAsk` with no allow rule still wrote a file. This item did not repeat that run under the real
  HOME. Such a run would load the user's own grok config and plugins, and the requirement notes that it fires this
  user's Claude Code plugin hooks. So the cause of the difference is NOT VERIFIED. The real HOME's `.grok/config.toml`
  has no line containing `permission`, `allow` or `mode` (counted, not read out). That rules out a permission rule
  in that file, but not other causes, such as the model choosing a different tool.
- **`claude`: `not usable: auth`, as `not_logged_in_isolated (ok in your shell)`.** Its subscription login is in
  the macOS keychain and cannot cross isolation, so a routed step that launches `claude` through `lens-run.sh`
  would fail at login. That is the truthful verdict. Claude-routed seats run through the Task spawn, not `lens-run.sh`
  (`loomwright/docs/PROVIDER_ROUTING.md` §"Routed seat protocol"), and the 02 row above (`usable for write seats`)
  was graded under the real HOME. The fix hint names `ANTHROPIC_API_KEY` / `CLAUDE_CODE_OAUTH_TOKEN`.
- **`cursor-agent`: `not usable: auth` in all three runs.** The diagnosis read `not_logged_in_isolated (ok in your
  shell)` in run 2, and `not_logged_in` with the login hint in runs 1 and 3. The cause was probed: under the scrubbed
  env, `cursor-agent status` sometimes prints `Logged in (unable to fetch user details)` (seen in 2 of 5
  consecutive `shell`-mode calls, exit 0). That line matches neither of `provider-cursor.sh`'s patterns (`Logged in
  as` / `Not logged in`), so the diagnosis rerun reads unknown, and the row falls back to the isolated result,
  `not_logged_in`. The verdict is right either way. The `login: cursor-agent login` hint in runs 1 and 3 is wrong,
  though: the CLI is logged in. **OPEN FOLLOW-UP:** `provider-cursor.sh`'s `PROBE_AUTH_OK_RE` should also accept
  that wording. That file is outside this item's lane, so it was not changed here. The same gap would make an
  isolated auth check with `CURSOR_API_KEY` set intermittently read `auth: unknown`.

### Honest limits

- **The `shell` diagnosis rerun is the one call left under the real HOME.** It runs only when an isolated auth
  check or smoke reports no login. It runs the auth-check command (no model call) or, for a provider with no
  auth-check command, the smoke a second time (one more model call), and it still loads that CLI's real-HOME config.
  No verdict is graded from it. In these runs it ran only the `claude` and `cursor-agent` auth-check commands.
- **The permission probe is one observed denial on one fixed prompt, not a sandbox.** It does not show that every
  tool, path or prompt is denied, and run 1 shows that its outcome can vary between runs.
- **`copilot`'s `probe_perm_argv` has never run on a real binary** (not installed here). `codex` and `gemini`
  declare no pin flags, so they would grade `permissions: unknown`.
