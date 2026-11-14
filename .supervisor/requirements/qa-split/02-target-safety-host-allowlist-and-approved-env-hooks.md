# The browser can only reach allowed origins, and env shell hooks run only with user approval

## Status: done
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/916

> Phase 1, item 02 of `qa-split/00-plan.md` (rev 2, approved 2026-11-12).
> Decisions: D12 (rev 3: proxy-enforced origin allowlist + mutation rule), D15 (b) base-branch config read and
> (c) user-scoped approval of shell hooks. Red-team findings this closes: F1 (part), F2.

## Why

Loomwright's `/verify` had no real production guard: `non_prod_assert` is an unanchored ERE matched against
the `base_url` written in the same file (`loomwright/scripts/verify-env.sh`, `assert_non_prod`), which
`https://shop.example.com/?next=localhost` passes, and nothing looked at the hosts the browser actually
reaches. selvedge enforces safety at the request layer instead, and refuses to let a PR choose its own
targets or shell.

## Design

**`selvedge.json`** (repo root, committed, owned by selvedge only; `.agent/verify.json` is not read):

```json
{
  "schema_version": 1,
  "origins": ["http://localhost:3000"],
  "allow_remote": false,
  "allow_remote_mutation": false,
  "hooks": { "seed": "npm run db:seed", "reset": "npm run db:reset", "auth_setup": "node e2e/login.mjs" }
}
```

- `origins`: exact `scheme://host[:port]` strings. Parsed with a URL parser, compared exactly, no regex,
  no suffix matching. Nothing is implied: an absent or empty list allows no origin, and `env check` says what
  to add. `selvedge env init` writes only a local origin (`http://localhost:<port>`, the port detected or
  asked); any other origin is added by hand.
- A non-local origin (anything but `localhost`, `127.0.0.1`, `[::1]`) is accepted only with
  `"allow_remote": true`.
- **Runtime enforcement (rev 3): a local proxy owned by the runner.** `context.route` alone is not enough:
  Playwright calls a route handler only for the first URL of a redirect chain and the browser follows the
  rest unrouted (`docs/src/network.md`), and WebSockets need the separate `routeWebSocket` API. So:
  - The runner starts a forward proxy on `127.0.0.1:<random port>` and launches Chromium with
    `proxy: { server: 'http://127.0.0.1:<port>' }`. The runner builds that string itself: no `bypass`
    list and no `direct://` fallback (with a fixed proxy and no fallback, an unreachable proxy fails every
    request with `ERR_PROXY_CONNECTION_FAILED`, the safe failure).
  - Loopback goes through the proxy: Playwright adds `--proxy-bypass-list=<-loopback>` unless `bypass`
    names a loopback host or `PLAYWRIGHT_DISABLE_FORCED_CHROMIUM_PROXIED_LOOPBACK` is set
    (`shouldProxyLoopback` in `crBrowser.ts`). The runner refuses to start when that env var is set →
    BLOCKED `proxy_loopback_disabled`.
  - The proxy checks the **origin of every connection**: each HTTP request, each HTTPS/WSS `CONNECT`
    tunnel (host and port only; it never sees the path or messages, and the docs say exactly that), each
    redirect hop (a new connection or request), each `ws` connection. An unlisted origin is refused and
    recorded; the criterion ends BLOCKED `host_not_allowed` naming the host.
  - Local origins match exact host **and port**. A remote origin's name is resolved by the proxy; if any
    resolved address is loopback, private (RFC 1918, `fc00::/7`), link-local (`169.254/16`, `fe80::/10`) or
    unspecified, the connection is refused → BLOCKED `remote_resolves_private`. The proxy connects to the
    address it validated, not a second lookup.
  - `context.route('**/*')` stays as a second layer, installed before any page exists. Service workers
    are blocked (`serviceWorkers: 'block'`), as Playwright recommends with routing.
  - **Scope: the browser only.** The verifier's shell is not behind the proxy (D11's honest limit).
    `env check` and the README say so.
- **Mutation rule:** a POST/PUT/PATCH/DELETE to a non-local origin is aborted unless
  `"allow_remote_mutation": true` → BLOCKED `remote_mutation_refused`. Enforced in the `route` layer and,
  for plain HTTP, in the proxy. For HTTPS the proxy sees no method, so a remote origin with
  `allow_remote_mutation: false` is GET-only only as far as `route` reaches; a 307/308 redirect that
  re-sends a POST to another remote origin is still stopped by the proxy's origin check.
- **Hooks** run only when every origin is local, and only if approved (below).

**Base-branch read (D15b):** `selvedge env check --base <ref>` (and every command taking `--base`) reads
`selvedge.json` from `git show <ref>:selvedge.json`, never the working tree. Without `--base` (a local
session on your own branch) it reads the working tree and says so in the output.

**User-scoped hook approval (D15c):** `~/.claude/selvedge/approvals.json`, keyed by repo identity (origin
remote URL, falling back to the repo root's realpath) → sha256 of the canonical `hooks` object. Hooks run
only when the current hash matches. `selvedge env approve` shows the hooks and asks (interactive only);
non-interactive with no matching approval → hooks don't run → BLOCKED `env_hooks_unapproved`. Nothing in
the repo can write or imply an approval. File mode 0600.

## Acceptance criteria (each a test)

- Direct navigation to an unlisted origin → BLOCKED `host_not_allowed` with that host named.
- A listed page that redirects to an unlisted origin → same; also a two-hop chain (listed → listed →
  unlisted), and a 307 that re-sends a POST to an unlisted origin. The unlisted test server records zero
  connections.
- A listed page that opens `ws://` and `wss://` to an unlisted origin → refused; the test server records no
  handshake.
- A page on `localhost:3000` (listed) that fetches `localhost:5432` (unlisted) → refused.
- A listed remote name that resolves to `127.0.0.1` (and to a `::1` / `fe80::` address) → BLOCKED
  `remote_resolves_private`.
- `PLAYWRIGHT_DISABLE_FORCED_CHROMIUM_PROXIED_LOOPBACK=1` → runner refuses, BLOCKED
  `proxy_loopback_disabled`; and the launched browser's proxy settings contain no `bypass` and no `direct://`.
- Proxy process killed mid-run → the next request fails, criterion BLOCKED; nothing reaches the unlisted
  test server.
- A listed page whose script `fetch`es an unlisted origin → that request is aborted and recorded.
- `https://shop.example.com/?next=localhost` with only localhost listed → blocked (the rev-1 hole).
- Non-local origin without `allow_remote` → `env check` exit 2, named reason.
- Non-local POST without `allow_remote_mutation` → aborted, BLOCKED `remote_mutation_refused`.
- An edit to `selvedge.json` on the PR head is ignored under `--base origin/main`.
- Hooks with no approval, non-interactive → not executed (a marker file the hook would write stays absent),
  BLOCKED `env_hooks_unapproved`. Approve, then change one hook byte → unapproved again.
- Hooks are never run when any origin is non-local.

## Depends on

01

## Touches

- `selvedge/bin/selvedge`, `selvedge/lib/env*`, `selvedge/lib/runner/route-guard*`, `selvedge/lib/runner/proxy*`,
  `selvedge/tests/**`
- `selvedge/schemas/selvedge-config.schema.json`

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-11-14T17:25:00Z
- **Brief:** .supervisor/jobs/done/2026-11-14-qa-split-02-target-safety-allowlist-hooks.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/916
