# 07 — The floor acts: guarded writes from the page

## Problem

Item 06 makes the page *show* everything the command reports — module state, the project
registry, per-project freshness. It still cannot *do* anything: adding a project means
leaving the page for a command, which is the same friction that produced item 06 in the
first place, one level up.

The blocker is structural, not cosmetic. The module serves the bundle with
`python3 -m http.server`, which is a static file server: **it answers `501` to any write**
(verified 2026-09-03 against a live server — `POST` → `501`, `GET` → `200`). There is no
endpoint to call because there is no request handler that accepts one.

Item 04 also declared, deliberately, that the view "renders; it does not act", and justified
having no authentication layer with "there is nothing to authenticate against on loopback".
**That justification was sound for a read-only page and stops being sound here**, which is
the real content of this item: a loopback port is not a security boundary in a browser. Any
site open in another tab can `fetch` a POST at `127.0.0.1:<port>`; the attacker cannot read
the response, but the write has already landed. DNS rebinding extends the same reach to a
remote origin. So this item is not "add some buttons" — it is "earn the right to have
buttons".

## Goal

The registry operations and a server stop, performed from the page, behind a guard designed
for the actual threat: a hostile page in another tab, not a hostile user at the keyboard.

## Scope

1. **Replace the static server with a small stdlib request handler.**
   `ThreadingHTTPServer` + `BaseHTTPRequestHandler` (Python ≥ 3.7; 3.9.6 confirmed present).
   Static `GET` behaviour is preserved byte-for-byte — **no new dependency, no Node, no npm,
   no CDN**, which keeps item 04's constraint intact. Everything not explicitly routed keeps
   returning what it returns today, including `501` for unrouted writes.

2. **Exactly four mutating endpoints, and no more:** `add`, `forget`, `scan`, `stop`.
   `apply` and `remove` are **excluded by decision, not by omission** — they are
   install-level, and a page able to uninstall itself buys nothing and risks something.

3. **The guard, all four parts required together** (any one alone is defeatable):
   - **A per-run bearer token**, minted fresh by `serve`, never written to a
     world-readable path, never logged, never printed into the served HTML. `serve` prints
     the URL carrying it once; the page stores it and strips it from the address bar so it
     cannot leak through history, a bookmark, or a shared screenshot.
   - **Sent in a custom request header** — which forces a CORS preflight that a hostile
     cross-origin page cannot satisfy, closing the "simple request" hole where a write lands
     even though the attacker never reads the reply.
   - **`Origin` validated** on every mutating request; absent or foreign is refused.
   - **`Host` validated** against the loopback names, which is what actually defeats DNS
     rebinding — an `Origin` check alone does not.

4. **Path handling on `add` and `scan` is treated as untrusted input.** A path supplied
   through the page becomes a directory the projector runs in, so it is resolved, confined,
   and rejected when it is not an existing directory. Traversal sequences, symlinks that
   escape, and non-directories are refused with a named reason, and nothing is registered.

5. **`stop` leaves an honest page.** The server the page is served by is gone, so the page
   must render a clear stopped state rather than a spinner, a stale floor presented as live,
   or a console error — the same standard the four existing render states already meet.

## Non-goals

- **No new capability beyond the four endpoints.** No merging, approving, retrying, running
  a supervisor, or editing project files from the page. Item 04's "it renders; it does not
  act" is relaxed exactly as far as managing which projects the page shows, and no further.
- **No binding beyond loopback, ever.** The guard is defence in depth for a loopback
  listener; it is not permission to expose one.
- **No user accounts, no passwords, no sessions.** The token authenticates *this browser tab
  to this server run*, nothing more, and dies with the server.
- **No write into any registered project.** Unchanged from 06: the only write inside a
  project remains the projector's own artefact.
- **No remembering the token across runs.** A per-run secret that survives restarts is a
  stored credential with none of the handling a stored credential deserves.

## Depends on

**06 merged** (hard — this adds writes to the registry and the page 06 introduces).

## Release-surface obligations

- Command count is **unchanged at 22** — `/ui` gains no new verb; the page gains the ability
  to invoke ones that already exist. **If a verb does turn out to be needed, bump every doc
  surface in the same commit.**
- No new agent (no token-budget entry) and no new hook.
- `setup-ui.sh` grows a request handler; it is CORE, so **measure the ratchet with
  `--print-allowances` after staging** and declare the measured value. If the handler is
  split into its own file, classify it explicitly rather than letting it fall to a default.
- `FLOOR_UI.md` must document the threat model in plain terms — *why* a loopback port needs a
  token at all — because a future reader who does not understand the reason will remove the
  guard as ceremony.

## Acceptance criteria

- [ ] **Static behaviour is unchanged.** Every `GET` the current server answers returns
      byte-identical content under the new handler, and an unrouted write still returns
      `501`. Asserted by diffing responses for the bundle files and the served JSON.
- [ ] **A mutating request with no token is refused** (`403`), and the registry is
      byte-identical afterwards. Asserted for all four endpoints, each with a hash of the
      registry before and after.
- [ ] **A mutating request with a wrong or expired token is refused**, and a token from a
      *previous* `serve` run is refused by the current one — proving the token is per-run.
- [ ] **A cross-origin request is refused**: one carrying a foreign `Origin` and one carrying
      none are both rejected, with the registry unchanged in each case.
- [ ] **A request whose `Host` is not a loopback name is refused**, which is the
      DNS-rebinding case; asserted by sending a forged `Host` header to the loopback socket.
- [ ] **The token never appears where it could leak**: not in the served HTML, not in any
      file inside the ui directory, not in the server's own log output. Asserted by grepping
      the served bytes and every file the module writes.
- [ ] **`add` rejects untrusted paths**: a traversal sequence, a path that is not a
      directory, and a symlink resolving outside the permitted root are each refused with a
      named reason and register nothing. A legitimate absolute path succeeds, proving the
      check discriminates rather than blanket-refusing.
- [ ] **`scan` from the page proposes and does not write**, matching the command's behaviour:
      the proposal response lists candidates, the registry is unchanged, and only an explicit
      confirming request registers anything.
- [ ] **`forget` removes only a registry entry** — the project directory is hashed before and
      after and is identical.
- [ ] **`stop` stops the server and the page says so**: after the stop the page renders a
      distinct stopped state (not a spinner, not a stale floor shown as current, no console
      error), browser-verified with the console read.
- [ ] **Every failure path still exits 0 and writes nothing** — the engine's fail-safe
      convention (refuse-to-write plus a named reason, never a non-zero exit) holds for the
      server exactly as it does for the subcommands.
- [ ] **Each guard is proven load-bearing by removing it.** For all four parts of the guard,
      a mutation control disables that part alone and shows the previously-refused request
      succeeding — otherwise the tests cannot distinguish a working guard from a guard that
      never fires. The mutants must be valid (non-empty, changed, syntax-clean) before the
      result counts.
- [ ] The server still binds loopback only and the page still issues zero requests to any
      other origin — re-asserted here, not inherited, because the server was replaced.
- [ ] The vendor-coupling ratchet is measured before and after and the delta reported.

## Outcomes Rubric

- Managing which projects the floor shows never requires leaving the floor.
- A hostile page in another tab cannot add, forget, scan or stop anything.
- Every guard is proven to fire by a control that removes it and watches the attack succeed.
- A path supplied through the browser is treated as untrusted input, not as a filename.
- Static rendering, loopback-only binding and zero egress survive the server being replaced.

## Status: brief-shipped

Job `.supervisor/jobs/done/2026-09-04-ui-guarded-writes.md` completed (reconciled from the job lifecycle, not self-reported).
Acceptance criteria are NOT machine-verified here — review them before promoting this to `## Status: done`.
