# Changelog

All notable changes to the selvedge plugin. Selvedge releases on its own: each release bumps
`selvedge/.claude-plugin/plugin.json`, its entry in `.claude-plugin/marketplace.json` and this
file together, never through the repository's `changelog.d/` fragments (those fold into
Loomwright's version only).

Format: each release is a heading `## <X.Y.Z> — <YYYY-MM-DD>`; the first such heading is the
current release, and `selvedge/tests/run.sh` checks it equals `plugin.json`'s `version`.

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
  `allow_remote_mutation`; a request it sends after the proxy is gone is `proxy_unavailable`. Known
  cost of that path (README §"The browser guard"): it follows hops itself, so it ignores a
  `fetch`'s `redirect: 'manual'|'error'` and skips a cross-origin hop's CORS preflight. Every refusal is a named BLOCKED
  reason; the README's reasons table is checked against the code's list.
- Tests: `test-env.sh`, `test-proxy.sh` and `test-route-guard.sh`, the last against real Chromium
  from a pinned Playwright installed into a selvedge-owned cache (`tests/lib/playwright-cache.sh`).

## 0.1.0 — 2026-11-13

- First release: the plugin scaffold. Manifest, the `selvedge` CLI (`--version`, `install-cli`,
  which links the CLI into `~/.local/bin`), and the plugin's own release gate
  (`selvedge/tests/run.sh`, run by CI's `static` job).
- `docs/cli-discovery.md` records whether a plugin's `bin/` reaches `PATH`.
