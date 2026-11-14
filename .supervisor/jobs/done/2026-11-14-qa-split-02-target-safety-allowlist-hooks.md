# Supervisor Job: selvedge target safety — origin allowlist proxy, base-branch config read, user-approved env hooks (qa-split/02)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** dirty (2 untracked dirs: `reports/`, `research_notes/`, unrelated), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 2 (untracked dirs; 4 linked worktrees on unrelated branches)
- **Source requirement:** .supervisor/requirements/qa-split/02-target-safety-host-allowlist-and-approved-env-hooks.md
- **Base commit:** 98689975d3fe756b81b9a4522dca25d84f3b78cd

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | CAUTION | selvedge is bash-only today (`selvedge/bin/selvedge`, no `package.json`). The plan (00-plan §5) names the core CLI "bash + Node/Playwright"; this item is the first Node code in selvedge. Node is on the dev machine (v24) and on the `ubuntu-latest` runner image; nothing installs it in the `static` job before the selvedge step |
| 2 | Dependency Availability | CAUTION | Playwright + Chromium are a new test-time dependency for selvedge (~150 MB download). Not reusable from Loomwright's cache (D4: selvedge imports nothing from `loomwright/`). Resolved by Design decision 1 |
| 3 | Architecture Fit | GO | Implements D12 rev 3 + D15 (b)/(c) of the approved plan exactly; selvedge owns its gate (`selvedge/tests/run.sh`, CI `static` step) |
| 4 | Scope vs Supervisor Capability | CAUTION | ~19 files and well over 800 changed lines → `context-bound` split into 2 ordered subtasks |
| 5 | Hard Blockers | GO | Item 01 (scaffold) is merged (#912). No hard blocker |

**Overall Verdict:** CAUTION

## Task
**Goal:** Give selvedge a committed `selvedge.json` with an exact-origin allowlist, enforce it on every browser connection through a runner-owned local proxy plus a `context.route` second layer, read the config from the base branch when `--base` is given, and run env shell hooks only under a user-scoped sha256 approval.

**Problem Statement:**
Selvedge's future runner (items 03–05) needs a real production guard before it can drive a browser unattended. Currently selvedge has no config and no network guard, and Loomwright's `/verify` guard (`assert_non_prod` in `loomwright/scripts/verify-env.sh`) is an unanchored regex on a self-declared URL that `https://shop.example.com/?next=localhost` passes and that never sees where the browser goes. This causes a remote-code / prod-mutation path (red team F1, F2). Success looks like: every connection Chromium makes (direct, redirect hop, `fetch`, `ws`/`wss`, CONNECT) is checked by origin and refused with a named BLOCKED reason when unlisted, a PR cannot widen its own allowlist or hooks, and an unapproved hook never executes — each proven by a test in `selvedge/tests/`.

## Design decisions
- decision: How selvedge's browser tests obtain Playwright + Chromium (T1 — new dependency)
  chosen: each browser test sources `selvedge/tests/lib/playwright-cache.sh`, which installs the pinned `playwright` library (one `PW_VERSION=<x.y.z>` pin line in that helper) into a selvedge-owned cache (`${SELVEDGE_TEST_PW_CACHE:-${TMPDIR:-/tmp}/selvedge-test-pw}`) and runs `playwright install ${CI:+--with-deps} chromium`; under `CI` set, an install failure is a hard FAIL (exit 1, reason `playwright_install_failed`) and no browser arm runs; outside CI it prints `SKIP (playwright_install_failed: …)` and the non-browser arms still decide
  rejected: reuse Loomwright's `LOOMWRIGHT_VERIFY_TEST_CACHE` / `read-playwright-pin.sh` — breaks D4 (selvedge reads nothing under `loomwright/`); "already in the lockfile" = no for selvedge
  rejected: committed `selvedge/package.json` + `package-lock.json` with an `npm ci` + `actions/cache` step in `.github/workflows/ci.yml` — blast radius: two files plus a workflow edit outside the item's Touches, for a dependency that is test-only in this item
  evidence: repo — `selvedge/` has no `package.json`; `loomwright/scripts/test-verify-walkthrough.sh` `acquire_playwright` + its `(AC11i) the install rule is bimodal: CI ⇒ exit 1 playwright_install_failed; no CI ⇒ SKIP + exit 0` arm is the house precedent; `npx --no-install playwright --version` reported `playwright@1.65.1` as the current package (not installed locally)
  revisit when: item 04 makes Playwright a runtime dependency of `selvedge run` — owner note (LP-APPROACH, 2026-11-14): "move to selvedge/package.json + cached npm ci when item 04 makes Playwright a runtime dependency"
  status: confirmed
- decision: Forward-proxy implementation for the runner (T2 — new module `selvedge/lib/runner/proxy.mjs`)
  chosen: Node standard library only (`node:http` for plain-HTTP forwarding and `upgrade`, `node:net` for CONNECT tunnels, `node:dns/promises` `lookup({all: true})` for validation, connecting to the validated address, never a second lookup)
  rejected: an npm proxy package (`http-proxy`, `proxy`) — a new dependency and none exposes "validate every resolved address, then connect to that exact address" without wrapping its socket creation anyway (reversibility: partial, lockfile: no)
  rejected: an external proxy binary (mitmproxy, squid) — not on the stack, an install the user must do, TLS interception is out of scope (D12: HTTPS/WSS is host+port only)
  evidence: CLAUDE.md stack is bash + Node for selvedge per 00-plan §5; the requirement needs only origin checks, DNS validation and byte piping, all in Node core
  revisit when: a measured need for TLS interception (path/method checks on HTTPS) — D12 explicitly excludes it
  status: confirmed
- decision: Where `selvedge.json` parsing, validation, approvals and the `env` subcommands live (T2 — new modules `selvedge/lib/env*.mjs`)
  chosen: Node ESM modules under `selvedge/lib/` invoked by `selvedge/bin/selvedge env …`; the existing `--version` / `install-cli` paths keep needing only bash
  rejected: bash + `jq` in `bin/selvedge` — the CLI header promises "nothing beyond bash 3.2 + BSD/GNU userland: no jq", and the proxy (Node) must share the same origin parser; two parsers of one config would drift
  rejected: Python — not in the plan's stack for selvedge
  evidence: `selvedge/bin/selvedge` header `no jq, no` `readlink -f`; 00-plan §5 "Core CLI (bash + Node/Playwright)"; `loomwright/scripts/resolve-egress-config.sh` derives the same repo identity (`git remote get-url origin`, falling back to the top-level path) for telemetry consent — the idea is copied, the script is not reused (D4)
  revisit when: never for the parser; the CLI shell could move wholly to Node later (item 06c `doctor`)
  status: confirmed

- decision: Shape of the browser-guard module `selvedge/lib/runner/route-guard.mjs` (T2 — new module)
  chosen: a separate module that owns launch options, the loopback env-var refusal, the guarded context (`serviceWorkers: 'block'`, `context.route('**/*')` installed before any page) and the route-layer origin + mutation checks; Playwright's `chromium` is passed in by the caller (`openGuardedContext({ chromium, config, lookup? })`), the module never imports `playwright`
  rejected: fold the browser guard into `proxy.mjs` — two layers in one file defeats the point of a second, independent layer, and the proxy must stay testable with no browser (test-proxy.sh); blast radius / test cost: no
  rejected: `route-guard.mjs` imports `playwright` directly — selvedge has no `package.json` (Design decision 1), so a bare import has nothing to resolve from; item 04 owns runtime packaging; reversibility: partial
  evidence: requirement Design "`context.route('**/*')` stays as a second layer, installed before any page exists. Service workers are blocked"; item 04 Touches `selvedge/lib/runner/**` (it builds the runner on this module)
  revisit when: item 04 adds `selvedge/package.json` with `playwright` as a runtime dependency — then the runner may import it and pass it in; the injection seam stays
  status: confirmed

## Acceptance Criteria

Config and `env` commands (subtask 1):
- [ ] AC1 — Given a `selvedge.json` whose `origins` holds a non-local origin (any host other than `localhost`, `127.0.0.1`, `[::1]`) and no `"allow_remote": true`, when `selvedge env check` runs, then it exits 2 and stderr names the reason `remote_origin_without_allow_remote` and the origin.
- [ ] AC2 — Given `origins` absent or `[]`, when `env check` runs, then it exits 2 with reason `origins_empty` and says what to add (an example `http://localhost:<port>` line); given a malformed origin (a path, query, userinfo, trailing slash beyond the origin, a non-http(s) scheme, or any string that is not exactly `scheme://host[:port]` after URL parsing), then exit 2 `origin_invalid` naming the string. Origins are compared as parsed exact strings — no regex, no suffix or substring match.
- [ ] AC3 — Given `selvedge.json` committed on `main` and a different `selvedge.json` (e.g. an added remote origin and changed hooks) in the working tree of a PR branch, when `selvedge env check --base main` runs, then it reports the `main` content (via `git show main:selvedge.json`) and ignores the working-tree edit; without `--base` it reads the working tree and its output says `config source: working tree (no --base)`. An unreadable `<ref>:selvedge.json` exits 2 `base_config_unreadable`.
- [ ] AC4 — Given hooks in `selvedge.json` with no matching approval in `$HOME/.claude/selvedge/approvals.json`, when `selvedge env hook seed` runs non-interactively, then the hook is not executed (a marker file the hook would write stays absent), stdout carries `BLOCKED env_hooks_unapproved`, and it exits 2 (00-plan D7: env problems are BLOCKED, and BLOCKED is exit 2; exit 3 stays reserved for item 04's NOT_VERIFIABLE).
- [ ] AC5 — Given an approval whose stored sha256 matches the current canonical `hooks` object (sorted keys, no whitespace, sha256 hex) for this repo identity (origin remote URL, else the repo root's realpath), when `env hook seed` runs with every origin local, then the hook runs (`bash -c` at the repo root) and the marker appears; when one byte of any hook then changes, then the same command is BLOCKED `env_hooks_unapproved` again and the marker is not rewritten.
- [ ] AC6 — Given any origin in the config is non-local (even with `allow_remote: true` and a matching approval), when `env hook <name>` runs, then no hook executes and it reports BLOCKED `env_hooks_remote_origin`, exit 2.
- [ ] AC7 — Given no TTY, when `selvedge env approve` runs, then it writes nothing and exits 2 `approve_requires_tty`; on a TTY it prints every hook and its hash and writes the approval only on an explicit `y`. The TTY half is tested by running `env approve` under a pseudo-terminal from `selvedge/tests/test-env.sh` via Python's `pty` module (`python3 -c 'import pty,sys; pty.spawn(sys.argv[1:])'`, present on macOS and the Ubuntu runner) feeding `y` and, in a second arm, `n` (nothing written); no test-only bypass of the TTY check exists in the CLI. The approvals file is mode 0600 (its directory 0700), written atomically, and nothing reads an approval from inside the repo.
- [ ] AC8 — Given no `selvedge.json`, when `selvedge env init [--port N]` runs, then it writes a `selvedge.json` with `schema_version: 1`, exactly one origin `http://localhost:<port>`, `allow_remote: false`, `allow_remote_mutation: false` and no hooks; it never writes a non-local origin, refuses to overwrite an existing file, and with no `--port`, no detectable port (a `--port N` / `-p N` / `PORT=N` in `package.json` `scripts.dev` or `scripts.start`) and no TTY it exits 2 `port_required`.
- [ ] AC9 — Given a valid config, when `env check` passes (exit 0), then its output states that the guard covers the browser only and the verifier's shell is not behind the proxy, and reports hook approval state (`approved` / `unapproved` / `no hooks`).
- [ ] AC10 — `selvedge/schemas/selvedge-config.schema.json` (JSON Schema draft 2020-12) declares `schema_version` (const 1), `origins` (array of strings), `allow_remote`, `allow_remote_mutation` (booleans), `hooks` (object with only `seed`, `reset`, `auth_setup` string keys), `additionalProperties: false`; `test-env.sh` asserts the validator in `selvedge/lib/env-config.mjs` rejects an unknown top-level key and an unknown hook key with exit 2 `config_schema_violation`, and that the schema file's property names equal the validator's accepted key set.

Browser guard (subtask 2) — each against real Chromium launched through `selvedge/lib/runner/route-guard.mjs`, with local fixture servers that record every TCP connection and request:
- [ ] AC11 — Given only `http://localhost:<A>` listed, when the guarded browser navigates directly to `http://localhost:<U>` (unlisted), then the outcome is BLOCKED `host_not_allowed` naming `localhost:<U>`, and server U records zero connections.
- [ ] AC12 — Given a listed page that redirects to an unlisted origin, a two-hop chain (listed A → listed B → unlisted U), and a 307 that re-sends a form POST to U, when each is followed, then each ends BLOCKED `host_not_allowed` naming U and U records zero connections — with the route layer's allowlist check disabled in the test (proxy alone), so the proxy is proven to catch hops the route handler never sees.
- [ ] AC13 — Given a listed page that opens `ws://` and `wss://` to an unlisted origin, when it loads, then both are refused (HTTP upgrade / CONNECT refused by the proxy) and U records no connection.
- [ ] AC14 — Given a page on listed `localhost:<A>` whose script `fetch`es `localhost:<U>` (same host, unlisted port), when it runs, then the request is aborted and recorded `host_not_allowed` naming `localhost:<U>` (local origins match exact host and port).
- [ ] AC15 — Given a listed remote origin (`allow_remote: true`) whose name resolves to `127.0.0.1`, to `::1`, or to an `fe80::` address (proxy constructed with an injected `lookup` — a programmatic option only, settable by no env var or CLI flag), when a request or CONNECT to it reaches the proxy, then it is refused `remote_resolves_private`, the lookup ran once, and no connection is attempted; any one private/loopback/link-local/unspecified address among several resolved refuses.
- [ ] AC16 — Given `PLAYWRIGHT_DISABLE_FORCED_CHROMIUM_PROXIED_LOOPBACK=1` in the environment, when the guard is asked to launch, then it refuses before launching Chromium with BLOCKED `proxy_loopback_disabled`; and the launch options it builds are exactly `{ proxy: { server: 'http://127.0.0.1:<port>' } }` — no `bypass` key, no `direct://` anywhere.
- [ ] AC17 — Given a loaded listed page, when the proxy is killed mid-run and the page then navigates/fetches again, then the request fails (`ERR_PROXY_CONNECTION_FAILED`), the outcome is BLOCKED `proxy_unavailable`, and the unlisted server records zero connections.
- [ ] AC18 — Given only localhost listed, when the browser navigates to `https://shop.example.com/?next=localhost`, then it is BLOCKED `host_not_allowed` naming `shop.example.com`, and the proxy refuses the CONNECT without a DNS lookup (proxy unit test with a counting injected lookup: count 0).
- [ ] AC19 — Given a remote origin listed with `allow_remote: true` and `allow_remote_mutation` false, when a page sends POST, PUT, PATCH or DELETE to it, then the route layer aborts it with BLOCKED `remote_mutation_refused`, and the proxy alone refuses a plain-HTTP POST to it (before any DNS lookup); GET is not refused by this rule. The context is created with `serviceWorkers: 'block'` and `context.route('**/*', …)` is installed before any page exists.

Release and docs (subtask 2):
- [ ] AC20 — `selvedge/README.md` documents `selvedge.json`, the four `env` commands, the BLOCKED reasons, that `env` commands need Node ≥ 18, that the guard covers the browser only (the shell is not contained), and that HTTPS/WSS checks see host and port only; selvedge is released as 0.2.0 (plugin.json, the marketplace selvedge entry and a `## 0.2.0 — <date>` CHANGELOG heading together); the README intro ("This is the scaffold release…") and the selvedge `description` in both `plugin.json` and the marketplace entry drop the "Scaffold release" wording and name the `env` commands and the browser guard, in place, with no version string; and `bash selvedge/tests/run.sh` passes.

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

(Applied here: the README names no selvedge version; the version lives in `plugin.json`, the marketplace entry mirrors it as the existing `validate-version.sh` consumer requires, and the CHANGELOG heading is the release record.)

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| env (config, approvals, CLI) | `selvedge/bin/selvedge` (89) | `selvedge/lib/env.mjs`, `selvedge/lib/env-config.mjs`, `selvedge/lib/env-approvals.mjs`, `selvedge/schemas/selvedge-config.schema.json`, `selvedge/tests/test-env.sh` | HIGH |
| browser guard | — | `selvedge/lib/runner/proxy.mjs`, `selvedge/lib/runner/route-guard.mjs`, `selvedge/tests/lib/playwright-cache.sh`, `selvedge/tests/fixtures/servers.mjs`, `selvedge/tests/fixtures/guard-driver.mjs`, `selvedge/tests/test-proxy.sh`, `selvedge/tests/test-route-guard.sh` | HIGH |
| docs + release | `selvedge/README.md` (70), `selvedge/docs/evidence/gate-scopes.md` (68), `selvedge/CHANGELOG.md` (16), `selvedge/.claude-plugin/plugin.json` (15), `.claude-plugin/marketplace.json` (140) | — | HIGH |

**Module layout (one home per responsibility; no MODIFY path is at the 500-line threshold):**
- origin parsing, local-host test, allowlist membership (`isOriginAllowed(config, origin)`: exact string equality of parsed origins, host AND port — the ONE match both proxy and route layer call), config load (working tree or `git show <ref>:selvedge.json`), schema validation, and the closed `REASONS` list → `selvedge/lib/env-config.mjs` (CREATE; the single shared module the proxy and route guard import — never a second origin parser)
- repo identity, canonical hooks hash, approvals file read/write → `selvedge/lib/env-approvals.mjs` (CREATE)
- `env check|init|approve|hook` argument handling and output → `selvedge/lib/env.mjs` (CREATE)
- `env` dispatch → `selvedge/bin/selvedge` (89 — append one `env)` case arm that execs `node "$BIN_DIR/../lib/env.mjs" "$@"`, plus the help line; the CLI stays the single entry point)
- forward proxy → `selvedge/lib/runner/proxy.mjs` (CREATE); launch options, loopback-env refusal, guarded context, route layer, mutation rule, error→reason mapping → `selvedge/lib/runner/route-guard.mjs` (CREATE)
- Playwright acquisition for tests → `selvedge/tests/lib/playwright-cache.sh` (CREATE; sourced by both browser-facing tests — never copied into each)
- recording fixture servers → `selvedge/tests/fixtures/servers.mjs` (CREATE); browser driver → `selvedge/tests/fixtures/guard-driver.mjs` (CREATE)
- No helper is already copied in 2+ siblings; no extract row.

> **Validator-owned surfaces:** `selvedge/tests/run.sh` globs only `selvedge/tests/test-*.sh` (top level), so the helpers under `tests/lib/` and `tests/fixtures/` must not be named `test-*`. `scripts/check-locale-prefix.sh` scans every tracked `*.sh`, so every new `.sh` here is in its scope. `scripts/validate-version.sh` checks the marketplace selvedge entry against `selvedge/.claude-plugin/plugin.json`; `scripts/check-doc-currency.sh` scans `.claude-plugin/marketplace.json` (its description-length check reads only the loomwright entry).

### File Overlap Detection

| Group A | Group B | Overlapping Files | Serialization Required |
|---------|---------|-------------------|----------------------|
| env | browser guard | `selvedge/tests/test-env.sh` (Subtask 2 adds the README-sync assertion) | YES — ordered by `requires` |
| env | docs + release | none | NO (but docs describe env commands → ordered after 1) |

## Touched-file invariants

> Grounded at base `98689975d3fe756b81b9a4522dca25d84f3b78cd`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`selvedge/bin/selvedge`** — keep: `set -uo pipefail`; the `die()` helper; the symlink-resolving `BIN_DIR` (paths to `lib/` must be built from `BIN_DIR`, so the `install-cli` link still finds them); the top-level `case "${1:-}" in` dispatch with `*) printf 'selvedge: unknown command: %s\n\n'` exiting 2; `--version` and `install-cli` must still run with no Node on PATH (only the new `env)` arm checks `command -v node` and dies naming the need). Update the header's exit-code line `# Exit codes: 0 ok, 1 an operation failed, 2 usage error.` to read `2 usage error or BLOCKED (a named reason on its own line)` in the same change — never add a 3: 00-plan D7 fixes the CLI-wide precedence FAIL → 1, BLOCKED → 2, NOT_VERIFIABLE → 3, and items 04/05 already rely on it. A BLOCKED outcome is told apart from a usage error by its stdout line `BLOCKED <reason>`. pinned by: `selvedge/tests/test-cli.sh` — `unknown command exits 2`, the help pin `grep -qE '^ +install-cli '`, `manifest not found`, `already links`, `refusing to overwrite`.
- **`selvedge/.claude-plugin/plugin.json`, `selvedge/CHANGELOG.md`** — keep: the first `## <X.Y.Z> — <YYYY-MM-DD>` heading equals `version`. pinned by: `selvedge/tests/check-release.sh` — `changelog_version_mismatch`; `selvedge/tests/test-cli.sh` reads `.version` via `jq -r '.version'`.
- **`.claude-plugin/marketplace.json`** — keep: only the `"name": "selvedge"` entry's `version` changes; the loomwright entry is untouched. pinned by: `scripts/validate-version.sh` — `Versions match: $PLUGIN_VERSION`.
- **`selvedge/tests/run.sh`** (not modified; its glob decides what runs) — keep: `for t in "$TESTS_DIR"/test-*.sh; do` picks up the three new top-level tests automatically; selvedge reads nothing under `loomwright/` (`selvedge imports nothing from Loomwright`).

## Closed enumerations touched

> Sibling grep at base `98689975`: `git grep -nF 'host_not_allowed' -- . ':!.supervisor'` → 0 hits (likewise `env_hooks_unapproved`, `remote_resolves_private`, `proxy_loopback_disabled`, `remote_mutation_refused`). No closed list of BLOCKED reasons exists yet; this brief creates the only two.

- **`host_not_allowed`, `remote_resolves_private`, `remote_mutation_refused`, `proxy_loopback_disabled`, `proxy_unavailable`, `env_hooks_unapproved`, `env_hooks_remote_origin`** (BLOCKED reasons) and **`origins_empty`, `origin_invalid`, `remote_origin_without_allow_remote`, `config_absent`, `config_invalid_json`, `config_schema_violation`, `base_config_unreadable`, `approve_requires_tty`, `port_required`** (exit-2 config/usage reasons) — must be named in:
  - `selvedge/lib/env-config.mjs` — the frozen exported `REASONS` object (the one code list; every emitter imports it, no string literal reason elsewhere) — create.
  - `selvedge/README.md` — the reasons table — create (doc list). The sync assertion (every `REASONS` key appears in the README table) is added to `selvedge/tests/test-env.sh` by **Subtask 2**, which writes the table; Subtask 1 does not add it (its own gate would fail with no table yet). Subtask 2 runs strictly after Subtask 1, so its sharing of `test-env.sh` is a legal ordered share.

## Pin mutations

**Layer attribution (makes every pin layer-specific):** each recorded block is `{ reason, origin, host, layer: 'route' | 'proxy' }`. A route-layer arm asserts `layer: 'route'` AND that the proxy's own block log has no entry for that request; a proxy arm runs with the route layer off (`routeLayer: false`, test-only) or against the proxy directly in `test-proxy.sh`. So a mutation to one layer cannot be masked by the other.

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `selvedge/tests/test-route-guard.sh` — direct navigation, route layer (AC11) | make the route handler `route.continue()` every request without the origin check in `selvedge/lib/runner/route-guard.mjs` (the arm asserts `layer: 'route'`) |
| `selvedge/tests/test-route-guard.sh` — direct navigation, proxy only (AC11, `routeLayer: false`) | make the proxy's per-connection origin check in `selvedge/lib/runner/proxy.mjs` return allowed for every origin |
| `selvedge/tests/test-route-guard.sh` — single-hop redirect, two-hop chain and 307 POST re-send (AC12, `routeLayer: false`) | same proxy origin-check mutation (each of the three arms turns red: U records a connection) |
| `selvedge/tests/test-route-guard.sh` — ws/wss refused (AC13) | same proxy origin-check mutation, applied to the `upgrade`/CONNECT path only |
| `selvedge/tests/test-env.sh` — `isOriginAllowed` unit arm: `http://localhost:<A>` listed, `http://localhost:<U>` not allowed (AC14, shared by both layers) | compare hostname only (drop the port) in `isOriginAllowed` in `selvedge/lib/env-config.mjs` |
| `selvedge/tests/test-route-guard.sh` — `localhost:<A>` page fetching `localhost:<U>` (AC14; runs once with the route layer and once with `routeLayer: false`; asserts `localhost:<U>` blocked and U records zero connections in both) | same `isOriginAllowed` host-only mutation (both layers call it, so both runs turn red) |
| `selvedge/tests/test-proxy.sh` — `remote_resolves_private` for 127.0.0.1 / ::1 / fe80:: (AC15) | delete the private/loopback/link-local address check in `selvedge/lib/runner/proxy.mjs` |
| `selvedge/tests/test-proxy.sh` — connects to the validated address (AC15) | make the proxy connect by hostname instead of the validated address (lookup count becomes 2) |
| `selvedge/tests/test-route-guard.sh` — loopback env refusal (AC16) | delete the `PLAYWRIGHT_DISABLE_FORCED_CHROMIUM_PROXIED_LOOPBACK` refusal in `selvedge/lib/runner/route-guard.mjs` |
| `selvedge/tests/test-route-guard.sh` — no bypass / no direct:// (AC16) | add `bypass: '<-loopback>'` to the proxy object `route-guard.mjs` builds |
| `selvedge/tests/test-route-guard.sh` — proxy killed → `proxy_unavailable` (AC17: after the kill the arm requests a LISTED origin and asserts it fails `proxy_unavailable`) | append `;direct://` to the proxy server string `route-guard.mjs` builds (the listed request then succeeds directly instead of failing) |
| `selvedge/tests/test-proxy.sh` — CONNECT `shop.example.com:443` refused with lookup count 0 (AC18, proxy layer) | flip the CONNECT origin check in `proxy.mjs` to allow (the counting lookup then runs) |
| `selvedge/tests/test-route-guard.sh` — `?next=localhost` aborted by the route layer (AC18, asserts `layer: 'route'`) | replace the exact origin match in the route handler with a substring test for `localhost` on the full URL |
| `selvedge/tests/test-route-guard.sh` — remote POST aborted by the route layer (AC19, asserts `layer: 'route'`, proxy log empty) | drop `POST` from the mutating-method set in `route-guard.mjs` |
| `selvedge/tests/test-proxy.sh` — plain-HTTP POST to a remote listed origin refused before lookup (AC19, proxy layer) | drop `POST` from the mutating-method set in `proxy.mjs` |
| `selvedge/tests/test-env.sh` — non-local origin without `allow_remote` (AC1) | delete the `allow_remote` check in `env-config.mjs` |
| `selvedge/tests/test-env.sh` — `origins_empty` and `origin_invalid` (AC2) | treat an absent/empty `origins` as valid, and (second row's arm) drop the "parsed URL serializes back to exactly `scheme://host[:port]`" comparison in `parseOrigin` |
| `selvedge/tests/test-env.sh` — `--base` ignores the PR-head edit (AC3) | read the working tree even when `--base` is given in `env-config.mjs` |
| `selvedge/tests/test-env.sh` — no approval at all → hook not run (AC4) | treat a missing approvals entry for the repo as approved in `env-approvals.mjs` |
| `selvedge/tests/test-env.sh` — one-byte hook change re-blocks (AC5) | skip the hash comparison in `env-approvals.mjs` (approve any stored entry for the repo) |
| `selvedge/tests/test-env.sh` — remote origin blocks hooks (AC6) | delete the all-origins-local check before running a hook in `env.mjs` |
| `selvedge/tests/test-env.sh` — `approve_requires_tty`, nothing written (AC7) | delete the TTY check in `env approve` in `env.mjs` (the arm pipes `y` on stdin, so the mutant writes an approval) |
| `selvedge/tests/test-env.sh` — `port_required`, never a non-local origin (AC8) | default the port to 3000 when none is given or detected in `env init` |
| `selvedge/tests/test-env.sh` — `config_schema_violation` on an unknown key (AC10) | drop the unknown-top-level-key rejection in the validator in `env-config.mjs` |
| `selvedge/tests/test-env.sh` — unknown hook key rejected, and schema property names == validator key set (AC10) | drop `auth_setup` from the validator's accepted hook-key set in `env-config.mjs` (the equality arm goes red) |
| `selvedge/tests/test-env.sh` — `base_config_unreadable` and the `config source: working tree (no --base)` line (AC3) | fall back to the working tree when `git show <ref>:selvedge.json` fails in `env-config.mjs` |
| `selvedge/tests/test-env.sh` — approvals file 0600 / dir 0700 (AC7; the arm writes an approval through the TTY seam below) | write `approvals.json` with mode `0o644` in `env-approvals.mjs` |
| `selvedge/tests/test-env.sh` — `env init` refuses to overwrite (AC8) | delete the existing-file refusal in `env init` in `env.mjs` |
| `selvedge/tests/test-env.sh` — browser-only scope statement and hook approval state (AC9) | delete the scope line printed by `env check` in `env.mjs` |
| `selvedge/tests/test-env.sh` — README-sync: every `REASONS` key appears in the README reasons table (Subtask 2's arm) | add one key to `REASONS` in `env-config.mjs` without a README row |
| `selvedge/tests/test-route-guard.sh` — service workers blocked (AC19: a listed page that registers a service worker; `navigator.serviceWorker.register` rejects / no SW controls the page) | omit `serviceWorkers: 'block'` from the context options in `route-guard.mjs` |
| `selvedge/tests/test-route-guard.sh` — route installed before any page (AC19: the first request of the first page is seen by the route layer, `layer: 'route'`) | move the `context.route('**/*', …)` call after the first `context.newPage()` in `route-guard.mjs` |

Each pin is a test arm that turns red under its mutation; `test-*.sh` arms print `ok`/`FAIL` lines like `test-cli.sh` and exit non-zero on any FAIL.

**Test isolation (every new test):** a fresh temporary `HOME` per test file (AC4–AC7 read and write `$HOME/.claude/selvedge/approvals.json`; the user's real file is never touched), every fixture server and proxy closed in an `EXIT` trap, and `selvedge/tests/lib/playwright-cache.sh` exports `PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-$SELVEDGE_TEST_PW_CACHE/browsers}"` before changing `HOME`, so a temp HOME never triggers a second Chromium download. The only network the suite uses is that install; `selvedge/docs/evidence/gate-scopes.md`'s "makes no network call" line is updated by Subtask 2 to say exactly that.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | `selvedge.json` config, `env check/init/approve/hook`, base-branch read, user-scoped hook approvals | AC1–AC10 | 1 modify, 5 create | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` | LAUNCHABLE |
| 2 | Runner-owned forward proxy + `context.route` guard + browser tests; README reasons table + its sync assertion in `test-env.sh`; gate-scopes note; selvedge 0.2.0 release | AC11–AC20 | 6 modify, 7 create | `skills/playwright-e2e/SKILL.md`, `skills/unit-testing/SKILL.md` | BLOCKED (by #1) |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "selvedge/lib/env-config.mjs"}
  - {kind: "symbol", path: "selvedge/lib/env-config.mjs", name: "parseOrigin"}
  - {kind: "symbol", path: "selvedge/lib/env-config.mjs", name: "isLocalOrigin"}
  - {kind: "symbol", path: "selvedge/lib/env-config.mjs", name: "isOriginAllowed"}
  - {kind: "symbol", path: "selvedge/lib/env-config.mjs", name: "loadConfig"}
  - {kind: "symbol", path: "selvedge/lib/env-config.mjs", name: "REASONS"}
  - {kind: "file", path: "selvedge/lib/env-approvals.mjs"}
  - {kind: "symbol", path: "selvedge/lib/env-approvals.mjs", name: "hooksSha256"}
  - {kind: "file", path: "selvedge/lib/env.mjs"}
  - {kind: "file", path: "selvedge/schemas/selvedge-config.schema.json"}
  - {kind: "file", path: "selvedge/tests/test-env.sh"}
  - {kind: "symbol", path: "selvedge/bin/selvedge", name: "env)"}
requires: []
lanes:
  - "selvedge/bin/selvedge"
  - "selvedge/lib/env*"
  - "selvedge/schemas/selvedge-config.schema.json"
  - "selvedge/tests/test-env.sh"
external_requires:
  - "Node.js >= 18 on PATH (ESM, node:crypto, node:child_process)"
  - "git (for git show <ref>:selvedge.json and repo identity)"

# Subtask 2
provides:
  - {kind: "file", path: "selvedge/lib/runner/proxy.mjs"}
  - {kind: "symbol", path: "selvedge/lib/runner/proxy.mjs", name: "startProxy"}
  - {kind: "file", path: "selvedge/lib/runner/route-guard.mjs"}
  - {kind: "symbol", path: "selvedge/lib/runner/route-guard.mjs", name: "buildLaunchOptions"}
  - {kind: "symbol", path: "selvedge/lib/runner/route-guard.mjs", name: "openGuardedContext"}
  - {kind: "file", path: "selvedge/tests/lib/playwright-cache.sh"}
  - {kind: "file", path: "selvedge/tests/fixtures/servers.mjs"}
  - {kind: "file", path: "selvedge/tests/fixtures/guard-driver.mjs"}
  - {kind: "file", path: "selvedge/tests/test-proxy.sh"}
  - {kind: "file", path: "selvedge/tests/test-route-guard.sh"}
  - {kind: "symbol", path: "selvedge/CHANGELOG.md", name: "## 0.2.0"}
  - {kind: "symbol", path: "selvedge/README.md", name: "env_hooks_unapproved"}
requires:
  - {from: "1", kind: "symbol", path: "selvedge/lib/env-config.mjs", name: "parseOrigin"}
  - {from: "1", kind: "symbol", path: "selvedge/lib/env-config.mjs", name: "isLocalOrigin"}
  - {from: "1", kind: "symbol", path: "selvedge/lib/env-config.mjs", name: "isOriginAllowed"}
  - {from: "1", kind: "symbol", path: "selvedge/lib/env-config.mjs", name: "REASONS"}
lanes:
  - "selvedge/lib/runner/proxy*"
  - "selvedge/lib/runner/route-guard*"
  - "selvedge/tests/lib/**"
  - "selvedge/tests/fixtures/**"
  - "selvedge/tests/test-proxy.sh"
  - "selvedge/tests/test-route-guard.sh"
  - "selvedge/tests/test-env.sh"
  - "selvedge/docs/evidence/gate-scopes.md"
  - "selvedge/README.md"
  - "selvedge/CHANGELOG.md"
  - "selvedge/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
external_requires:
  - "playwright (npm library, pinned by the PW_VERSION line in selvedge/tests/lib/playwright-cache.sh) + its Chromium build, installed at test time"
  - "network access to the npm registry and the Playwright CDN on first run (CI downloads every static run; no ci.yml cache in this item)"
```

**Worker notes (subtask 2):** Playwright is injected (`openGuardedContext({ chromium, config, lookup? })` takes the caller's `chromium`); `route-guard.mjs` never `import`s `playwright` itself, so item 04 decides runtime packaging. The proxy's `lookup` option is programmatic only — no env var or CLI flag can set it. Fixture servers bind `127.0.0.1` on random ports and append every accepted TCP connection and request line (method, path, `Upgrade` header) to a per-server JSON log the tests read; "records zero connections" is asserted on that log. The `wss://` arm needs no TLS server: the proxy refuses the CONNECT before any handshake. AC12's proxy-only arms open the context with the route layer's allowlist check turned off through an explicit test-only option of `openGuardedContext` (e.g. `routeLayer: false`), documented as such; production callers never pass it.

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | `selvedge/tests/test-env.sh` (legal: Subtask 2 is reachable from Subtask 1) | YES (requires) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after Subtask 1)
- **Recommended workers:** 1
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` |
| 2 | `skills/playwright-e2e/SKILL.md`, `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): first Node code in selvedge; the CI `static` job relies on the runner image's preinstalled Node (no `setup-node` before the selvedge step) | MEDIUM | Target Node ≥ 18 features only (ESM `.mjs`, `node:` built-ins); `test-env.sh` fails (never skips) when `node` is absent; README states the requirement |
| Feasibility (Phase 2.5): Playwright + Chromium download in every CI `static` run (~150 MB) — a CDN hiccup reds `ci` | MEDIUM | Owner-accepted (Design decision 1); bimodal rule: CI install failure is a named hard FAIL `playwright_install_failed`, never a vacuous green; move to `package.json` + cached `npm ci` with item 04 |
| Feasibility (Phase 2.5): context-bound size (~19 files) | MEDIUM | Split into 2 ordered subtasks; Subtask 2 imports Subtask 1's origin parser instead of re-implementing it |
| CI `static` job has `timeout-minutes: 20`; the Playwright install (`--with-deps` apt + ~150 MB) and real-browser arms add to it on every run | MEDIUM | Record the selvedge step's added wall time from the first CI run in the PR's evidence (`selvedge/docs/evidence/gate-scopes.md`); if `static` comes within 5 min of its timeout, fall back to the owner's item-04 plan (`package.json` + cached `npm ci`) or a separate job |
| `--with-deps` needs apt/sudo on the runner; may differ on a dev Mac | LOW | `${CI:+--with-deps}` only under CI (house precedent); local runs use the browser only |
| Playwright forces loopback through the proxy only when `bypass` names no loopback host and the env var is unset (`shouldProxyLoopback` in `crBrowser.ts`); a Playwright upgrade could change that | MEDIUM | AC14 (localhost:A → localhost:U refused) fails if loopback stops going through the proxy; AC16 pins the launch options; the pin line makes upgrades explicit |
| Approval file is user-scoped but readable/writable by any process running as the user (an agent with a shell can approve) | LOW | D11's honest limit — stated in README; `env approve` itself refuses without a TTY; nothing inside the repo is read as an approval |
| Port-flaky tests (random ports, slow CI) | LOW | Bind port 0 and read the assigned port; generous per-arm timeouts; every server closed in a trap |
| Item 03/04/05 reuse these modules; a later rename breaks them | LOW | Exported names are pinned in `provides` (`startProxy`, `openGuardedContext`, `buildLaunchOptions`, `REASONS`, `hooksSha256`) |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-14-qa-split-02-target-safety-allowlist-hooks.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-11-14T06:55:34Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/916
- **Branch:** feature/qa-split-02-target-safety-allowlist-hooks
- **Files changed:** 20
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** armed
- **Summary:** selvedge.json exact-origin allowlist + env check/init/approve/hook (sha256 user-scoped approvals, --base reads base-branch config), Node-stdlib forward proxy + context.route guard with real-Chromium tests, selvedge 0.2.0. Three heal rounds fixed 8 reproduced findings (307/301/302 redirect mutation bypasses, GET/HEAD/OPTIONS allow-list, NAT64/6to4, proxy_unavailable labelling, untested branches). Round-3 fix (ea2015b) not re-reviewed; its HIGH (route layer ignores fetch redirect mode; followed cross-origin hop keeps Authorization without preflight) was documented as a known cost, not fixed.

## Not verified
- **test-env.sh pty arms on the Ubuntu CI runner** — no local Linux runtime; verified on macOS python3 3.9 only (subtask 1)
- **Subtask 2 consumers of parseOrigin, isOriginAllowed, REASONS** — not written yet at subtask 1 time (subtask 1)
- **CI static job wall time with playwright install --with-deps** — no CI run yet at hand-back; ~15 s locally warm (subtask 2)
- **test-route-guard.sh on ubuntu-latest** — macOS only at hand-back (subtask 2)
