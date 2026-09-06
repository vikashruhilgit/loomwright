# The Floor (`/setup ui` to install, `/ui` to run)

How the plugin's optional local run view works: what it renders, where the data comes from, what it deliberately does **not** claim, and how to take it away again. **Two entry points, one engine:** `/setup ui` is the *configuration* half (install / uninstall the bundle) and `/ui` is the *operational* half (start it, stop it, and manage the project registry) — see §"Projects". Configured via `/setup ui` (authority: the `setup` skill — `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md`); this document is the reference companion, in the same relationship to that skill as `OBSERVABILITY.md` is for the observability module.

> **Repo vs. runtime paths:** repo-relative paths like `loomwright/scripts/floor-ui/...` below describe this repo's layout only. Anything executed at runtime resolves through `${CLAUDE_PLUGIN_ROOT}/...` (e.g. `${CLAUDE_PLUGIN_ROOT}/scripts/setup-ui.sh`), and the served page is always the **copy** in the ui directory — never the plugin install dir, which `serve` only ever reads.

---

## What it is

The Floor is a single static page — three files, no framework, no bundler, no Node, no package manager — that renders `.supervisor/floor/floor.json` (the projection `build-floor.sh` produces; contract in `RESULT_SCHEMAS.md` §`FLOOR_PROJECTION`). It answers one question the other surfaces do not: **what is happening right now, and has something stopped happening?** `/insights`, `/handoff` and `/obsidian` report history well; this reports the present.

```
Claude Code run  →  .supervisor/{state.md, jobs/, logs/, …}     (the projector's own basis line)
                          │
                          ▼  build-floor.sh (read-only, exit 0 always)
                    .supervisor/floor/floor.json                 (ONE versioned contract)
                          │
                          ▼  setup-ui.sh serve  (copies it into the ui dir on an interval)
              a stdlib request handler bound to 127.0.0.1        (GET unchanged; 4 guarded writes)
                          │
                          ▼  fetch('floor.json', {cache: 'no-store'}) every 2 s
                    index.html + floor.css + floor.js            (the page)
                          │
                          ▲  POST api/{add,forget,scan,stop} + X-Floor-Token   (see §"Why the guard exists")
```

The count of inputs on the first line is stated **once**, in `build-floor.sh`'s own header — "spread across FOURTEEN projected surfaces in five formats" — with the counting basis (one key under `surfaces`, which is *not* the number of directories read) spelled out beside it. That sentence is quoted here rather than paraphrased into a fourth independent copy of the number: this document carried the previous, smaller count for a release after the projector had already outgrown it, and no gate could see it because nothing tied the two sentences together. `test-setup-ui.sh` case (z8) now reads the words out of `build-floor.sh` and requires this quote to match them.

The page shows, top to bottom:

| Region | Source | Rendering rule |
|---|---|---|
| The **projects** picker | `index.json` (the served index `serve` writes into the ui directory) | Every registered project with its slug, path and last-regenerated age, plus the module's own state. Selecting one switches which already-written `projects/<slug>/floor.json` the page READS — it sends nothing and cannot cause a regeneration. A project whose directory has gone renders `unavailable` **with the engine's reason** and is never dropped from the list; one this serve has not reached yet says `never regenerated` rather than showing an empty floor. The registry's own state distinguishes **absent** (no projects registered yet) from **unparseable** (the file is there and this module refuses to touch it) — two different claims, never collapsed. With no served index at this origin the section says so and the page goes on rendering the single root `floor.json`. The cadence note is read from the index, never assumed: the selected project regenerates on `--interval`, every other one at a time on the slower cadence, because one projector run costs about a second and regenerating all of them every tick would starve the loop. |
| Five **stages** — Queue · Plan · Execute · Review · Shipped | `jobs_pending.count`, `state.detail.phase`, `jobs_done.count` | `PLAN`/`ACQUIRE`/`INIT` highlight Plan, `EXECUTE` highlights Execute, `FINALIZE`/`SELF_HEAL` highlight Review. `LOOP` — the seventh member of the closed phase set, Supervisor's Phase 5, which runs *between* items — highlights **nothing**, and neither would a phase added to that set later: the map is deliberately partial. A surface with **no** `count` renders `—` with its `reason` as the cell's `title` — never `0`. |
| The **phase note** under the stages | `state.mtime_epoch`, `state.detail.{branch,run_status,phase}` | The `state.md` write age, plus the branch and `run_status` when recorded. A phase the stage map does not carry is named here — `recorded phase LOOP — no pipeline stage corresponds to it` — because all three middle cells sit at `—` for it, which is *also* what an unrecorded phase looks like; without the note, a **measured** phase would be indistinguishable from a missing one. The no-phase case says `no phase is recorded` instead. Fixture: `floor-loop.json`. |
| One **lane per agent** in the newest session | `sessions.detail.current.agents[]` | Ordered by `last_ts` descending. Label: name (or `main thread`, or `identity unknown`) · event count · last-event age. A typed lane takes the colour of the matching roster row. An untyped lane is neutral, and dashed **only** when nothing identifies it: a row the projector scoped `main` — the thread of the session itself, identified from the transcript path its own events carried — is named `main thread` with a plain chip, because "no role" and "no identity" are different facts. |
| The permanent **liveness note** | — | `liveness unavailable — a lane shows recorded events, never a running process`. Always rendered; see §"What it does not claim". |
| The **roster strip** | `agents.detail.roster[]` | Every agent the plugin ships, with colour swatch, `model`, `maxTurns` as "budget", and a hollow swatch + the text `read-only` where applicable. |
| The **rules browser** | `rules.detail` | Every rule in the committed `.agent/rules/` store, grouped by category and then by `applies_to` scope. `applies_to`, `check` and `supersedes` are each read by **key presence**, not truthiness, so absent / present-and-`null` / a value / present-but-malformed are four distinct texts — a rule whose `applies_to` was written as a bare string says so rather than reading as though no scope were declared. `provenance` is rendered as its `source` and `added` fields, never as the object. Supersession history shows chains in order, dangling pointers, and cycles whole. A file the projector could not parse is NAMED with its reason, and `read_completeness` (`all` / `partial` / `none`) states whether anything went unread — "could not examine" is never displayed as "examined and clean". |
| The **churn view** | `postmortem.detail` | The review-churn ledger as two distributions — root-cause class and flow stage — each sorted **by key, never by count**, because ordering by size is the ranking this view refuses to do. The flow-stage basis is printed from the projection's own `flow_stage_basis` field rather than restated here: the ledger carries a second, disagreeing representation, and `flow_stage_counter_disagreements` publishes how far apart they are. Malformed lines are counted and named, never folded into a class. Correlations between a rule's scope and the ledger are labelled observations and carry their evidence; an uncomputable one is omitted rather than shown as a zero. |
| The **projector notes** strip | `notes[]` | Printed verbatim. This is where a skipped or unverifiable surface explains itself. |

## The serve loop

`setup-ui.sh serve` does three things per tick and nothing else:

1. runs `build-floor.sh` from the **current project root** (skip this with `--no-regen`),
2. copies `.supervisor/floor/floor.json` into the ui directory,
3. serves the ui directory with a **stdlib request handler** (`ThreadingHTTPServer` + a subclass of the very `SimpleHTTPRequestHandler` that `python3 -m http.server` itself instantiates), bound to `127.0.0.1` and rooted at the ui directory.

**`GET` is unchanged by construction, not by care.** The handler subclasses the same class over the same directory and overrides nothing on the read path, so every byte the old static server answered is the byte this one answers — asserted by fetching each document from **both** servers in the same test run and diffing. Anything not explicitly routed still answers exactly what it answered before, `501` for an unrouted write included. Everything added is on the **write** side, and all of it is behind the guard below.

- **Interval** is `--interval` seconds, default **2**, minimum 1. `build-floor.sh` takes ~0.5 s on a 13k-line log tree here, and the loop runs it **synchronously**, so two regenerations can never overlap regardless of interval.
- **Port** is `--port`, default **7734**. A busy port is **reported and the server does not start** — this module never moves the port for you, because a silently moved port is a browser tab reading bytes from something else.
- `--detach` returns immediately and records the pids in `<ui dir>/serve.pid`; `setup-ui.sh stop` kills only pids whose command line names `http.server` or `setup-ui.sh`. That guard was **matched, not widened**, when the server was replaced: the handler is launched with the engine's own path in its argv, so the existing pattern keeps matching it verbatim. The refusal half — a pidfile naming a process that is *not* this module's, reported as `not killed … (not-ours)` and left running — had zero test coverage until item 07 and now has its own case, because a guard nobody exercises is a guard nobody would notice going too far. Foreground is the engine's default and Ctrl-C is enough **for a human running the engine directly in their own terminal**; **an agent-invoked `serve` — every `/ui serve` and every `/setup ui` serve step — must pass `--detach`**, because that caller has no Ctrl-C, blocks until its tool call times out, and then trips the `EXIT` trap that kills the server it just started.
- **`serve` prints one URL carrying this run's token in the `#fragment`.** Open *that* URL. A fragment is never transmitted to any server, so the token cannot reach a request line, an access log, a proxy or a referrer header; the page reads it once and strips it from the address bar, so it cannot leak through history, a bookmark or a screenshot either. Opening a bare `http://127.0.0.1:<port>/` still works — the page reads everything — but the four buttons will be refused, and the page says so rather than failing silently.
- **`python3 >= 3.7`** is the only runtime requirement, and only for `serve` (both `--bind` and `--directory` date from 3.7). `jq` is a dependency of `build-floor.sh`, not of this engine: without it the page still serves and simply says how stale the copy it is showing has become.

### Query parameters (both read from the page URL)

| Parameter | Default | Meaning |
|---|---|---|
| `?stall=<seconds>` | `300` | how old a lane's last event may get before that lane reads **stalled** |
| `?stale=<seconds>` | `6` — `3 ×` the **page's own 2 s poll**, *not* `serve --interval` | how old `floor.json` itself may get before the page says so |

`?stale=` exists for a specific reason worth stating: a **committed fixture's `generated_at_epoch` is always in the past**, so without it every fixture would render under the stale banner and nothing else about the page could be demonstrated. Raise it when loading `fixtures/floor-ui/*.json` by hand.

It has a second, less obvious use. The page has **no way to observe `serve --interval`** — it polls on its own fixed 2 s clock, and its default threshold is three of those. With a perfectly legal `--interval 10` every render is older than that default, so the page would report a document that is being regenerated exactly as configured. Two things keep that from becoming a false claim: the banner states only what the page measured (the age, and the threshold it was measured against), never a cause it cannot see; and `serve` prints the URL to open — including `?stale=<3 × interval>` whenever its own interval outgrows the page default, and the bare URL when it does not.

## Projects

One server on one port can show **more than one project**, and which ones is decided by a registry a human writes — never by discovery.

```
/ui add                 # register the project you are standing in
/ui list                # slug · path · last-regenerated age  (never mutates)
/ui forget <slug>       # drop an entry; the project directory is untouched
/ui scan <dir>          # PROPOSE candidates; writes nothing without --confirm
```

**Where the registry lives, and why it is not in the ui directory.** `projects.json` sits *beside* the ui directory, in its parent — overridable with `--registry`, which is the **only** override (`--ui-dir` provably cannot redirect it, because the two are siblings rather than parent and child). That placement is load-bearing rather than incidental: `remove` deletes the ui directory, and the user's list of projects has to outlive a module teardown. `test-setup-ui.sh` asserts the registry survives a `remove` directly, rather than reasoning from the path.

**`forget` is deliberately not named `remove`.** One word meaning both "tear down the module" and "drop a project from a list" is a data-loss shape. `remove` deletes a directory; `forget` edits one JSON file, and the suite hashes the project tree before and after to prove it.

**What `serve` does with the registry.** It writes a served index — `index.json` in the ui directory — carrying the module's own state, the registry's state, and one row per registered project. The page reads that index for its picker and then reads the selected project's already-written `projects/<slug>/floor.json`. **Selecting a project sends nothing**: it changes which file the page fetches, and it cannot cause a regeneration.

**The cadence is stated, not assumed.** The selected project regenerates every `--interval` seconds; the others are regenerated **one at a time** on a slower cadence, and that ratio is carried in the served index so the page can print it. This is a measured constraint, not a preference: one projector run costs about a second on a 13k-line log tree, so regenerating every project on every tick starves a 2 s loop at **two** projects and would render everything permanently stale. `test-setup-ui.sh` measures elapsed time across a fixed number of ticks against a stub projector of known cost, with a control proving the naive shape really does exceed the budget.

**Four states per project, because they are four different claims:**

| State | What it means |
|---|---|
| `ready` | a floor document exists for this project and its generation time is recorded beside it |
| `never regenerated` | the directory is there, but this serve has not reached it yet — not an empty floor |
| `unavailable` | the registered directory is not present at that path. The entry is **reported and kept**, never dropped: a project silently missing from the picker is indistinguishable from one that was never added. `forget` remains the user's to run. |
| `unreadable` | a slot document exists but its timestamp could not be read, so no age can be claimed for it |

A project whose directory is deleted **while `serve` is running** flips to `unavailable` with its reason at the next poll; the other projects keep rendering and the server does not exit.

**The registry's own state is a separate claim from any project's.** *Absent* (no registry file yet — the ordinary state of a fresh install, never an error) and *unparseable* (the file is there and this module refuses to touch it) are rendered as two different sentences, never collapsed into one. With `jq` unfindable the index still gets written and says so, naming jq: the project list and every project path are **omitted rather than guessed**, because `build-floor.sh` needs jq too and nothing could have been regenerated either.

### The registry lock

Two processes can want the registry at the same time — a terminal running `/ui add` and the page
running the same verb through the server are two processes, not one — so the **write** verbs
(`add`, `forget`, and a **confirmed** `scan`) take a lock. It is a directory, `<registry>.lock`
beside the registry itself, because `flock` is not on stock macOS and `mkdir` is atomic on every
POSIX filesystem: exactly one of N racing callers creates it and the rest see `EEXIST`.

- **The lock is taken before the snapshot, not around the write.** A lock covering only the `mv`
  would serialise two writers that had already read the same document — the same lost update,
  later. Taking it first is the whole point.
- **The read verbs take nothing.** `check`, `list` and an unconfirmed `scan` are already safe
  against a writer, because the registry only ever becomes visible whole, via `mv`. Locking them
  would buy contention and no correctness, and one wedged writer would blind every view.
- **A stale lock is broken, and the reason is named.** Three findings, three sentences, never
  collapsed into one: the recorded owner **has exited**; the recorded pid is alive but **belongs
  to a different program** (it was reused after the holder died); or the lock **records no owner
  and is older** than the few seconds a healthy holder can take between creating it and writing
  its pid. A lock whose owner is alive and *is* this engine is busy, not stale — and so is one
  the engine cannot judge, because `ps` said nothing: refusing to judge means waiting, which is
  the direction that cannot destroy a registry. Breaking is done by renaming the lock aside, so
  two processes that both decide the same lock is stale cannot both proceed.
- **The wait is bounded and ends in a refusal, never a silent proceed.** `--lock-timeout <n>`
  (default **10**, and `0` means do not wait at all) caps it; on timeout the verb names the lock
  path and the timeout, writes nothing, and exits 0 like every other branch in this engine.
- **What it still does not promise.** It serialises *this engine's* writers. A registry edited by
  hand in an editor while a verb runs is outside it, and always was — the lock is a convention
  between processes running this script, not a filesystem-level guarantee.

`test-setup-ui.sh` group `(o)` proves this by running real concurrent invocations rather than by
reading the code: two `add`s under a deliberately slowed `jq` (which widens the critical section
while leaving the engine byte-identical), asserting both registrations survive and that the pair
took materially longer than one writer — with a control that changes **one token** so the write
path takes no lock, where one registration is then lost.

**Nothing is written into a registered project except its own `.supervisor/floor/floor.json`**, and that only by running `build-floor.sh` inside it. `add`, `list`, `forget` and `scan` touch exactly one file between them — the registry — and `list` touches none.

**Four of those verbs can also be reached from the page.** The projects section carries a path field and five buttons — *Add it*, *Scan it for candidates*, *Register the candidates*, *Forget the shown project*, *Stop this server* — covering exactly four endpoints (`scan` proposes and confirms through the same one). Each button **runs the command**: the endpoint shells back into this same engine, so `scan`'s propose-then-`--confirm` contract, `forget`'s registry-only edit and every named refusal are identical whether they were reached from the page or from a terminal. They are **buttons and never a `<form>`** — a form is a cross-origin write primitive that needs no script and cannot carry a custom header, which is the exact shape the guard refuses. Every one of them goes through the four-part guard in §"Why the guard exists"; leaving the path field empty means *the directory this serve was launched in*, which is the one path that skips confinement because it never came from the page.

**After `stop`, the page says so.** It renders a distinct **stopped** state — not a spinner, not the last floor presented as current, and no console error: the single poll keeps ticking and does nothing, the controls disable, and the banner states that this server was stopped from this page and how to start it again.

## Why the guard exists

Read this before removing anything below it. Item 04 shipped the page with **no authentication at all**, and justified it: *"there is nothing to authenticate against on loopback."* That was **sound for a page that could only render**, and it stopped being sound the moment a write existed. The four buttons are the moment.

**A loopback port is not a security boundary in a browser.** Two concrete attacks, neither hypothetical:

1. **The other tab.** Any site you have open in another tab can run `fetch('http://127.0.0.1:7734/api/add', {method: 'POST', …})`. The browser's same-origin policy stops that page **reading the reply** — it does not stop the request being **sent**. For a simple request the write has already landed by the time anything is blocked, and the attacker never needed to see the response: they only needed the write.
2. **DNS rebinding.** A name the attacker controls resolves first to their own server (so their script loads), then re-resolves to `127.0.0.1`. Their page is now *same-origin with your loopback server* as far as the browser is concerned, so even the reply is readable. **In the general case an `Origin` check does not stop this** — the Origin the browser sends is the attacker's own name, and any check that *reflects* the Origin, or matches it against a pattern the attacker can satisfy, is defeated by a name they own. **Stated precisely for this server, because the stronger version of the claim is false here:** `ALLOWED_ORIGINS` is a fixed list of loopback literals, which the rebound name cannot match either — so on this implementation the `Origin` check *also* blocks attack 2, independently. `Host` is still required, for two reasons that survive that. It does not depend on the browser choosing to send an `Origin` at all, so it is the part that holds if the Origin policy is ever loosened to a pattern — the exact edit that would silently re-open this. And it is the check whose *subject* is the attack: `Host` is where a rebound name actually shows up. Keeping both is defence in depth against a future edit to either one, not redundancy.

So every mutating request must satisfy **all four** of these together. Each one alone is defeatable, which is why none of them is optional:

| Part | What it is | What it stops | What it does **not** stop |
|---|---|---|---|
| **A per-run bearer token** | minted fresh by `serve`, handed to the handler through the environment, never in argv (`ps` is world-readable), never written to a file, never logged, never in the served HTML. It dies with the server. | a page that guesses the endpoint but not the secret | nothing, on its own, if the secret can be sent by a channel that needs no preflight |
| **Sent in a custom header** (`X-Floor-Token`) | a custom header makes the request **non-simple**, so the browser must win a CORS **preflight** first — and this server answers no preflight at all | attack 1: the other tab's write is never sent, rather than being sent and merely unreadable | a request that is same-origin already |
| **`Origin` validated** | must be this server, under a loopback spelling. **Absent is refused too** — `fetch` sets an Origin on every cross-origin request, so its absence on a write is not the page this server serves | a scripted cross-origin write that somehow got past the preflight — **and, because the allowlist is loopback literals rather than a pattern, attack 2 as well** | a genuinely same-origin request; and it would stop covering attack 2 the moment this allowlist became a pattern, which is why `Host` is not optional |
| **`Host` validated** | must be `127.0.0.1`, `localhost` or `[::1]`, with or without the port | **attack 2 on every mutating route** — a rebound name reaches this socket carrying the attacker's own name in `Host`. Here it blocks that attack *alongside* the fixed-allowlist `Origin` check rather than instead of it (see attack 2 above); it is the half that does not depend on an `Origin` being sent, or on that allowlist staying literal | a genuinely same-origin request, which is the point — and it is not reached on a `GET` at all: see the note directly below |

**Scope, stated rather than implied: this guard is on the write side and only there.** `_host_ok` is reached from `do_POST` and from nowhere else, so `Host` validation stops attack 2 **for every mutating route** — and for nothing beyond them. A rebound page is still same-origin with this server for a **read**, so it can fetch `floor.json` and `index.json`, which carry branch names, session ids and agent ids. That read exposure is **unchanged from the static-server era**: `GET` is byte-for-byte what `python3 -m http.server` answered (§"The serve loop"), and on the read path the loopback bind is still the whole of the protection, exactly as it was before there were any buttons. Closing it would mean changing `GET`, which this release deliberately does not do — §"Local-only posture" is the standing statement of what follows from that: `floor.json` is local data, and anything with a browser on this machine is inside the boundary.

**A path typed into the page is untrusted input, not a filename.** It becomes a directory the projector runs in, so it is resolved, confined to the permitted root (**your home directory** — the serve's own `$HOME`), and refused **with a named reason** when it is not an existing directory, contains a `..` segment, or is a symlink resolving outside that root. `realpath` is what makes the symlink case work: a link inside your home pointing at `/etc` resolves to `/etc` and is refused by the same comparison that refuses a literal `/etc`. The **command line is deliberately not confined this way** — `setup-ui.sh add /anywhere` still works. That asymmetry is the design: the terminal is the trusted channel and the browser is not.

**Every guard part is proven load-bearing by a control that removes it.** `test-setup-ui.sh` group (n) disables each part **alone** — the token comparison, the header *name* (moved to the CORS-safelisted `Content-Language`, which is exactly the simple-request hole), the `Origin` check, the `Host` check — and requires the previously-refused request to **succeed** against the mutant. Without those four, the suite could not tell a working guard from a guard that never fires, and a fifth assertion goes red if any of the four controls is ever silently skipped.

**What is deliberately NOT here**, so nobody adds it back believing it was an oversight:

- **No fifth endpoint.** `add`, `forget`, `scan`, `stop` — and no more. `apply` and `remove` are excluded **by decision**: they are install-level, and a page able to uninstall itself buys nothing and risks something.
- **No `Access-Control-Allow-Origin` on any response, ever**, and no preflight answer. Adding either re-opens attack 1 in one line.
- **No binding beyond loopback.** The guard is defence in depth for a loopback listener; it is not permission to expose one.
- **No accounts, no passwords, no sessions.** The token authenticates *this browser tab to this server run* and nothing more.
- **No remembering the token across runs.** A per-run secret that survived a restart would be a stored credential with none of the handling a stored credential deserves.

## Honest states

The page never renders a blank screen, a spinner, or a console error. Exactly one of these is shown when there is nothing normal to draw. There were three of them until a review found the fourth hiding inside the second — an idle claim being made from evidence the projector had declined to give:

| Condition | Text |
|---|---|
| `floor.json` returns 404 (or the fetch fails) | `no floor.json at this origin` |
| `sessions` **counted**, a `detail.current` view present, and **zero agents** in it | `no run in flight` |
| any other `sessions` shape with no lanes — surface absent or `unverified`, or `detail.current` **omitted** | `session data unavailable — <the projector's own reason>` |
| `generated_at_epoch` older than the freshness threshold | `floor.json is stale (<age>) - older than the <n>s freshness threshold…` |

The middle two rows are the same rule as the em-dashed count cells, applied to the banner: **idle is a measured state, never a default.** `build-floor.sh` omits `sessions.detail.current` whenever no log line carries a `ts` (the newest session cannot be identified from file order) and reports the surface `unverified` when a log could not be read — in both cases it has *refused* to say whether anything is in flight, and the page must not answer for it. A zero-agent session is the opposite: the session *was* identified and no agent event was recorded in it, which the projector states by omitting `agents` from `current` rather than emitting `[]`, so both readings count as a measured zero. The reason quoted in the second row is taken from the surface's own `reason`, else the `notes[]` line for that surface, else a named fallback — never invented.

Each has a committed fixture — `floor-empty.json` (the earned idle banner), `floor-nosession.json` (counted sessions, no `current`, beside a `state` surface still recording phase `EXECUTE`) and `floor-stale.json` — so the rendering is reproducible rather than argued about. `floor-loop.json` is the same rule one region up the page: every surface counted, lanes present, and the only unusual thing about it is a recorded phase the stage map has no stage for.

**The restyle into the site's design language changed none of these.** All of it is `floor.css` plus static prose in `index.html`; `floor.js` was not touched, so every condition above is still decided by the same code and still renders the same words. What DID change on the page, and is therefore recorded here rather than left for a reader to discover: the header carries a **lede** saying what the page is and what it refuses to claim, and **every one of the seven sections carries a caption** naming what that section shows and what its freshness is measured against. Those captions are static text, not projected data — they add no surface to `floor.json`, and they are counted per section by `test-setup-ui.sh` group (q) so a section cannot quietly lose one. A per-state browser pass against the committed fixtures is recorded in [`FLOOR_UI_VERIFICATION.md`](FLOOR_UI_VERIFICATION.md).

## Motion is evidence, never decoration

There is exactly **one** timer in `floor.js` — the 2 s poll — and re-render is keyed on a changed `generated_at_epoch`. A lane's shuttle advances only when that lane's `events` count changed between two renders; a lane whose count did not change does not move. The single stated exemption is the `.pulse` keyframe, which is present **only on a non-stalled lane** — its absence *is* the stall signal, so it is state-driven even though a keyframe drives its frames.

Accessibility follows from the same rule: `@media (prefers-reduced-motion: reduce)` removes every animation and transition while leaving every state class rendered, and no state depends on colour alone — stalled is a dashed border plus `no event for <age>`, a read-only agent is a hollow dot plus the word `read-only`, identity-unknown is a dashed chip plus its own text, and absent/empty/stale are text banners. Both a light and a dark palette are defined, and `data-theme` overrides the system preference. Both palettes are the loomwright site's own warm cream family — the light one adopted from its `site.css` directly, the dark one derived into the same hues rather than left cold — so the tool and the site read as one product; the type is the site's own declared fallback stacks (`Impact` / `Georgia` / `ui-monospace, Menlo`), which is exactly what the site renders as with no network, and remains the permanent condition of a bundle that fetches nothing.

**That colour rule is now guarded, and until this release it was not.** The skip link, the banner's `role="status"` *and* `aria-live="polite"`, and the label association on every section were the one item on this module's non-negotiables list that no test backed — `skip-link` had zero occurrences in the suite, and the region-parity check `(j36)` read its own section list *out of* `aria-labelledby`, so a section that lost the attribute left the loop's input and `(j36)` passed vacuously. Group (q) of `test-setup-ui.sh` closes it with the per-section equality `count(<section carrying aria-labelledby) == count(<section) == 7` taken over multi-line-comment-stripped text, two removal controls (remove it; and *move* it onto a non-section sibling, which leaves both document-wide totals reading 7), a control for the stripper itself, and an anti-vacuity guard tying `(j36)`'s enumeration input to the section count. Measured contrast ratios for every pair in both themes are tabulated in [`FLOOR_UI_VERIFICATION.md`](FLOOR_UI_VERIFICATION.md).

## What it does not claim

These limits are copied from the source requirement's 2026-09-03 amendment and are **design, not gaps**:

- **There is no "currently running agent" and no liveness anywhere on the page.** No spawn event exists in any log, so liveness could only be inferred from the recency of some other record — that is a guess, and the note under the lanes says so permanently.
- **Identity is partial, and partial in two different ways.** `agent_type` is carried by a small minority of recorded events, so a lane whose `agent_id` never appeared on a typed line is never assigned a plausible role. It is drawn `main thread` when the projector carries `agent_scope: "main"` for it — the emitters derive that from the transcript path in the hook payload itself, so it is a positive identification of the session's own thread rather than an inference from the missing type — and `identity unknown` in every other untyped case, including a spawned `subagent` whose payload named no type. A role is still never guessed; only the question changes from "which agent is this" to "is this an agent at all". `read_only` on a roster row is a **tri-state**: `true`, `false`, or **omitted entirely** when the agent declares no `disallowedTools` line at all — the third renders as `read-only unknown`, never silently as "not read-only". The **one** lane that omits that clause is the `main thread` row: the roster describes agents this plugin ships, the session thread is not one of them, so there is no roster row here to be missing and `read-only unknown` would answer a question that does not apply — a different error from the one the tri-state exists to prevent.
- **A lane's number is events, not turns and not progress.** It counts recorded log lines for that `agent_id` in the newest session. Two lanes with the same count have not necessarily done the same amount of work.
- **The `state.md` phase can be stale on a real machine** (it has read `status: running` for long stretches). The page shows the state surface's own `mtime_epoch` age beside the phase and never labels a run "live".


**It no longer assumes a single writer** — that clause was here for one release and is now
closed. Every registry edit is still a read-modify-write (snapshot the JSON, compute the new
document, write a temp file, `mv` it into place), and the `mv` still makes each write *atomic*.
But atomic is not serialised: two invocations racing on one registry each snapshot the **same**
starting document, and whichever `mv` lands last used to win, silently discarding the other's
`add` or `forget`. See §"The registry lock" for what closed it, including what it still does not
promise.

## Local-only posture

`floor.json` is a projection of this machine's run state and **it carries branch names, session ids and agent ids**. Treat it as local data:

- `serve` **always** binds `127.0.0.1`. There is no flag to change that and no code path that omits it. The bind address is **no longer the whole security posture** — that sentence was here while the page could only render, and §"Why the guard exists" is what replaced it — but it is still not negotiable at the command line.
- `index.html` carries a `Content-Security-Policy` meta with `default-src 'self'` (and `connect-src 'self'`), `floor.js` fetches only relative paths it builds itself — `floor.json`, the served index `index.json`, and `projects/<encoded slug>/floor.json` (the slug is passed through `encodeURIComponent`, and the engine additionally shape-filters it before ever writing such a slot), and the bundle contains no absolute URL, no protocol-relative reference, no `@import`, no preconnect and no web font — system font stacks only. `test-setup-ui.sh` scans all three files for each of those and carries a mutation control, so the scan cannot rot into a check that passes on anything.
- The handler serves the **whole ui directory**, which is why the ui directory holds only the three bundle files, the marker, an optional `serve.pid`, the serve log `serve.log`, the `floor.json` copy, the served index `index.json` and the `projects/<slug>/floor.json` slots — nothing else is ever written there, and every one of those is a projection this machine already produced. The registry itself is deliberately **not** in that directory and is therefore never served: absolute project paths are not something a page needs, and the served index carries only what the picker actually renders.
- **The token appears in none of those bytes.** `test-setup-ui.sh` reads every document back **off the wire** (not off disk — the claim is about what a browser receives), greps every file under the ui directory and the registry beside it, and greps the server's own captured stdout and stderr, with an anti-vacuity case proving that same grep can find a planted token. The one place a human ever sees it is the URL `serve` prints.

## What it writes — the whole list

1. **The ui directory** (default `$HOME/.claude/loomwright/ui`, overridable with `--ui-dir`, which is how every self-test runs inside a `mktemp -d`): the three bundle files, the ownership marker `.loomwright-ui-module`, an optional `serve.pid`, **the serve log `serve.log`**, a copy of `floor.json`, **the served index `index.json`**, and one **`projects/<slug>/floor.json`** per registered project that `serve` has reached. `serve.log` is the request handler's own stdout and stderr, which used to go to `/dev/null` and took every traceback with them; it records **one line per mutating request** — the route and the outcome — **plus one line for a request that could not be answered at all** (`FloorServer.handle_error`, which is what keeps an aborted connection or an unexpected raise to a line instead of a multi-line traceback interleaved across threads), and never a caller-supplied string, so it can be neither injected into nor made to leak the token. A read that completes is not logged, so the page's own two-second poll never grows it. It sits **inside the served root like everything else in that directory**, so `GET /serve.log` returns it — which is precisely why nothing a caller supplied, and no traceback, may ever be written into it. `index.json` is written by `serve` alone — atomically, temp-file-then-`mv`, so a poll landing mid-write reads the previous document rather than half of this one — and it is the page's ONLY source for the project picker, the module's own state and per-project freshness. The page is a reader, so everything it can show has to be a file the static server can already hand it.
2. **`.supervisor/floor/floor.json` under the current project root, and under each registered project root that `serve` regenerates** — and only ever by running `build-floor.sh` in that directory, never by writing that path directly. `serve --no-regen` makes even that write impossible. A project reaches this list only because a human ran `add`.
3. **The project registry `projects.json`**, sitting *beside* the ui directory (in its parent), overridable with `--registry`. Only `add`, `forget` and a **confirmed** `scan` write it; `check`, `list` and an unconfirmed `scan` only read it. Its being a sibling rather than a file inside the ui directory is load-bearing: `remove` deletes the ui directory, and the user's list of projects has to outlive that. Registering a project writes **nothing into the project itself**, and `forget` never touches the directory it is forgetting.

4. **The registry lock `<registry>.lock`** — a *directory* beside the registry, created by a registry-writing verb and removed by an EXIT trap on every path out of it, including the refusals. It is listed here rather than dismissed as transient for one reason: a lock left behind by a killed process is a real file the user can find, and a write list that omitted it would be the reason nobody recognised it. See §"The registry lock".

Nothing else, anywhere. It never touches the user-scope settings document (that is the `statusline` module's one write domain), never writes a project `.gitignore`, and never runs a history-touching git command. `test-setup-ui.sh` hashes two whole trees — the fixture parent and a fixture git repo used as the working directory — before and after a full `apply` → `serve` → `stop` → `remove` sequence, and asserts the only difference is that one regenerated file.

## Removing it

```
/setup ui              # check → report → offer, including remove when it is installed
```

`remove` deletes the ui directory **only** when the `.loomwright-ui-module` marker is present *at the resolved path*, and it additionally refuses `/`, `$HOME`, and anything at or under the plugin install directory. The resolved path is the **physical** one (`cd -P` / `pwd -P`): bash's logical `pwd` hands back the path you typed with its symlinks intact, so those three refusals would never see a target reached through a symlinked parent. A `--ui-dir` that is **itself a symlink** is refused outright — unlinking it would leave every byte of the target in place under a report saying it was removed, and a false "removed" is worse than a refusal. A directory without the marker is **reported and preserved** — `--ui-dir` is user-supplied, and a typo pointing at a real directory must not cost you that directory. Removal takes the bundle, the marker, the pidfile, the serve log and the `floor.json` copy with it; the projection under `.supervisor/floor/` is regenerable and is left alone.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `serve: ABORTED — python3 not found` | `serve` is the only subcommand that needs it. Everything else (`check`, `apply`, `remove`) still works. |
| `serve: ABORTED — port <n> is already in use` | Something else holds the port. Re-run with `--port <n>`; the module will not move it for you. |
| The page says `floor.json is stale` under a live serve loop | Either `build-floor.sh` is not producing output — most often `jq` is missing (`serve` warns about this at startup) or the working directory is not the project root — **or `--interval` is longer than the page's 6 s default threshold**, in which case `serve` has already printed the `?stale=` URL to open instead. |
| The page says `no floor.json at this origin` | `serve` has not copied one yet (first tick), or you are serving a ui dir that was never applied to. Run `/setup ui` and re-check. |
| Everything renders but every lane says `identity unknown` | Expected on most sessions — see §"What it does not claim". A lane that is the session's own thread reads `main thread` instead, but only for events emitted after the `agent_scope` field existed; older lines carry no scope and stay unknown, which is honest rather than retroactively repaired. The roster strip is still complete, because it comes from agent frontmatter rather than from logs. |
| `apply: WITHHELD — … carries no .loomwright-ui-module marker` | The ui directory exists but this module did not create it. Nothing was written. Point `--ui-dir` somewhere else, or remove that directory yourself. |
| A button says the write was **REFUSED by the server guard** | Almost always the token: you opened a bare `http://127.0.0.1:<port>/` rather than the `#token=…` URL `serve` printed, or you are looking at a tab left over from a **previous** run (the token is per-run and dies with the server). Re-open the URL this run printed. The refusal names which of the four parts said no. |
| A path is refused with `path-outside-permitted-root` | A path supplied **through the page** is confined to your home directory, and `realpath` is applied first — so a symlink pointing outside is refused exactly like a literal outside path. Use `setup-ui.sh add <path>` from a terminal, which is the trusted channel and is not confined. |
| `add: ABORTED — the registry lock … did not clear within <n>s` | Another `add`, `forget` or confirmed `scan` is holding the registry — often the page and a terminal at the same moment. Nothing was read or written; run it again, or raise `--lock-timeout`. If you are certain nothing else is running (and the engine has not already reported clearing it as stale), delete that `.lock` directory by hand. |
| `serve: ABORTED — could not mint a per-run access token` | `python3`'s `secrets` module produced nothing usable. Nothing was started and nothing was written; the module will not serve write endpoints without a token rather than serve them unguarded. |

## Reference

- Engine: `loomwright/scripts/setup-ui.sh` (`check` / `apply` / `serve` / `stop` / `remove` / `add` / `list` / `forget` / `scan`; always exits 0 — "fails closed" means refuse-to-write plus a named-reason headline, never a non-zero exit)
- Bundle: `loomwright/scripts/floor-ui/{index.html,floor.css,floor.js}`
- Projector: `loomwright/scripts/build-floor.sh` → `.supervisor/floor/floor.json`
- Schema: `loomwright/docs/RESULT_SCHEMAS.md` §`FLOOR_PROJECTION`
- Self-test: `loomwright/scripts/test-setup-ui.sh` (static half; the browser halves are verified against the committed fixtures and recorded in the PR body)
- Module contract: `loomwright/skills/setup/SKILL.md` Pattern 2, flow in `loomwright/commands/setup.md` §"Module: ui"
