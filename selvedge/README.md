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
```

`--version` and `install-cli` need only bash and standard userland tools (no `jq`, no Node); the
CLI resolves its own real path through symlinks, so it works when run through the `install-cli`
link. **The `env` commands need Node.js >= 18 on `PATH`**; without it `selvedge env` exits 1 and
says so.

Exit codes: `0` ok, `1` an operation failed, `2` a usage error or **BLOCKED**. A BLOCKED outcome
prints its own stdout line `BLOCKED <reason>`; a config or usage problem names its reason on
stderr. Every reason is in the [table below](#blocked-and-config-reasons).

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
- `allow_remote_mutation` — with it `false` (the default), POST, PUT, PATCH and DELETE to a remote
  origin are refused; GET is not.
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
  tree, so a pull request cannot widen its own allowlist or change its own hooks. Without it the
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
shell included, can write it; `env approve` itself refuses without a TTY.

## The browser guard

The checker's browser (`lib/runner/route-guard.mjs`) runs behind two independent layers, and every
refusal names its layer:

1. **A runner-owned forward proxy** (`lib/runner/proxy.mjs`). Chromium is launched with this proxy
   and nothing else: no bypass list, no `direct://` fallback. Every connection Chromium makes goes
   through it: a navigation, each redirect hop, `fetch`, a `ws`/`wss` handshake, an https CONNECT.
   An unlisted origin is refused before any DNS lookup. A listed remote host is looked up once; if
   any address it resolves to is private, loopback, link-local or unspecified, it is refused and no
   connection is attempted. Otherwise the proxy connects to that validated address, never to the
   name again. If the proxy dies, the browser's requests fail (`proxy_unavailable`); they never go
   direct.
2. **A `context.route('**/*')` layer**, installed before any page exists, refuses unlisted origins
   and remote mutations (POST, PUT, PATCH, DELETE without `allow_remote_mutation`). It also covers
   https, where the proxy cannot see the method. Service workers are blocked.

Playwright sends localhost through the proxy only while
`PLAYWRIGHT_DISABLE_FORCED_CHROMIUM_PROXIED_LOOPBACK` is unset, so the guard refuses to launch if
that variable is set (`proxy_loopback_disabled`).

What the guard does **not** cover:

- **The browser only.** The checker's shell, and the `env` hooks, are not behind the proxy: a
  command run from the shell can reach any host. Hooks therefore never run while any origin is
  remote.
- **HTTPS and WSS are checked by host and port only.** They are tunnelled (CONNECT), so the proxy
  never sees the path or method; there is no TLS interception. The route layer adds the method
  check for https requests the page makes.

## BLOCKED and config reasons

Every reason selvedge prints. `BLOCKED` reasons print as a stdout line `BLOCKED <reason>`; config
and usage reasons print on stderr. Both exit 2.

| Reason | Kind | Meaning |
|---|---|---|
| `host_not_allowed` | BLOCKED | the browser asked for an origin not in `origins` (exact scheme, host and port) |
| `remote_resolves_private` | BLOCKED | a listed remote host resolved to a private, loopback, link-local or unspecified address |
| `remote_mutation_refused` | BLOCKED | POST, PUT, PATCH or DELETE to a remote origin without `allow_remote_mutation` |
| `proxy_loopback_disabled` | BLOCKED | `PLAYWRIGHT_DISABLE_FORCED_CHROMIUM_PROXIED_LOOPBACK` is set, so localhost would skip the proxy |
| `proxy_unavailable` | BLOCKED | the guard's proxy is gone; the request failed instead of going direct |
| `env_hooks_unapproved` | BLOCKED | the hooks have no approval matching their current sha256 for this repo; run `selvedge env approve` |
| `env_hooks_remote_origin` | BLOCKED | a hook was asked to run while an origin is remote |
| `origins_empty` | config | `origins` is absent or empty; add the app you test, e.g. `http://localhost:3000` |
| `origin_invalid` | config | an origin is not exactly `scheme://host[:port]` |
| `remote_origin_without_allow_remote` | config | a non-local origin is listed without `"allow_remote": true` |
| `config_absent` | config | no `selvedge.json` at the repo root; run `selvedge env init` |
| `config_invalid_json` | config | `selvedge.json` is not valid JSON |
| `config_schema_violation` | config | an unknown key, an unknown hook name, or a value of the wrong type |
| `base_config_unreadable` | config | `--base <ref>` given, but `<ref>:selvedge.json` cannot be read |
| `approve_requires_tty` | usage | `env approve` was run without an interactive terminal |
| `port_required` | usage | `env init` found no port (`--port`, `package.json` scripts, or a TTY prompt) |

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
