# The Floor (`/setup ui`)

How the plugin's optional local run view works: what it renders, where the data comes from, what it deliberately does **not** claim, and how to take it away again. Configured via `/setup ui` (authority: the `setup` skill — `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md`); this document is the reference companion, in the same relationship to that skill as `OBSERVABILITY.md` is for the observability module.

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
                    python3 -m http.server --bind 127.0.0.1
                          │
                          ▼  fetch('floor.json', {cache: 'no-store'}) every 2 s
                    index.html + floor.css + floor.js            (the page)
```

The count of inputs on the first line is stated **once**, in `build-floor.sh`'s own header — "spread across FOURTEEN projected surfaces in five formats" — with the counting basis (one key under `surfaces`, which is *not* the number of directories read) spelled out beside it. That sentence is quoted here rather than paraphrased into a fourth independent copy of the number: this document carried the previous, smaller count for a release after the projector had already outgrown it, and no gate could see it because nothing tied the two sentences together. `test-setup-ui.sh` case (z8) now reads the words out of `build-floor.sh` and requires this quote to match them.

The page shows, top to bottom:

| Region | Source | Rendering rule |
|---|---|---|
| The **projects** picker | `index.json` (the served index `serve` writes into the ui directory) | Every registered project with its slug, path and last-regenerated age, plus the module's own state. Selecting one switches which already-written `projects/<slug>/floor.json` the page READS — it sends nothing and cannot cause a regeneration. A project whose directory has gone renders `unavailable` **with the engine's reason** and is never dropped from the list; one this serve has not reached yet says `never regenerated` rather than showing an empty floor. The registry's own state distinguishes **absent** (no projects registered yet) from **unparseable** (the file is there and this module refuses to touch it) — two different claims, never collapsed. With no served index at this origin the section says so and the page goes on rendering the single root `floor.json`. The cadence note is read from the index, never assumed: the selected project regenerates on `--interval`, every other one at a time on the slower cadence, because one projector run costs about a second and regenerating all of them every tick would starve the loop. |
| Five **stages** — Queue · Plan · Execute · Review · Shipped | `jobs_pending.count`, `state.detail.phase`, `jobs_done.count` | `PLAN`/`ACQUIRE`/`INIT` highlight Plan, `EXECUTE` highlights Execute, `FINALIZE`/`SELF_HEAL` highlight Review. `LOOP` — the seventh member of the closed phase set, Supervisor's Phase 5, which runs *between* items — highlights **nothing**, and neither would a phase added to that set later: the map is deliberately partial. A surface with **no** `count` renders `—` with its `reason` as the cell's `title` — never `0`. |
| The **phase note** under the stages | `state.mtime_epoch`, `state.detail.{branch,run_status,phase}` | The `state.md` write age, plus the branch and `run_status` when recorded. A phase the stage map does not carry is named here — `recorded phase LOOP — no pipeline stage corresponds to it` — because all three middle cells sit at `—` for it, which is *also* what an unrecorded phase looks like; without the note, a **measured** phase would be indistinguishable from a missing one. The no-phase case says `no phase is recorded` instead. Fixture: `floor-loop.json`. |
| One **lane per agent** in the newest session | `sessions.detail.current.agents[]` | Ordered by `last_ts` descending. Label: name (or `identity unknown`) · event count · last-event age. A typed lane takes the colour of the matching roster row; an untyped lane is neutral and dashed. |
| The permanent **liveness note** | — | `liveness unavailable — a lane shows recorded events, never a running process`. Always rendered; see §"What it does not claim". |
| The **roster strip** | `agents.detail.roster[]` | Every agent the plugin ships, with colour swatch, `model`, `maxTurns` as "budget", and a hollow swatch + the text `read-only` where applicable. |
| The **rules browser** | `rules.detail` | Every rule in the committed `.agent/rules/` store, grouped by category and then by `applies_to` scope. `applies_to`, `check` and `supersedes` are each read by **key presence**, not truthiness, so absent / present-and-`null` / a value / present-but-malformed are four distinct texts — a rule whose `applies_to` was written as a bare string says so rather than reading as though no scope were declared. `provenance` is rendered as its `source` and `added` fields, never as the object. Supersession history shows chains in order, dangling pointers, and cycles whole. A file the projector could not parse is NAMED with its reason, and `read_completeness` (`all` / `partial` / `none`) states whether anything went unread — "could not examine" is never displayed as "examined and clean". |
| The **churn view** | `postmortem.detail` | The review-churn ledger as two distributions — root-cause class and flow stage — each sorted **by key, never by count**, because ordering by size is the ranking this view refuses to do. The flow-stage basis is printed from the projection's own `flow_stage_basis` field rather than restated here: the ledger carries a second, disagreeing representation, and `flow_stage_counter_disagreements` publishes how far apart they are. Malformed lines are counted and named, never folded into a class. Correlations between a rule's scope and the ledger are labelled observations and carry their evidence; an uncomputable one is omitted rather than shown as a zero. |
| The **projector notes** strip | `notes[]` | Printed verbatim. This is where a skipped or unverifiable surface explains itself. |

## The serve loop

`setup-ui.sh serve` does three things per tick and nothing else:

1. runs `build-floor.sh` from the **current project root** (skip this with `--no-regen`),
2. copies `.supervisor/floor/floor.json` into the ui directory,
3. serves the ui directory with `python3 -m http.server --bind 127.0.0.1 --directory <ui dir> <port>`.

- **Interval** is `--interval` seconds, default **2**, minimum 1. `build-floor.sh` takes ~0.5 s on a 13k-line log tree here, and the loop runs it **synchronously**, so two regenerations can never overlap regardless of interval.
- **Port** is `--port`, default **7734**. A busy port is **reported and the server does not start** — this module never moves the port for you, because a silently moved port is a browser tab reading bytes from something else.
- `--detach` returns immediately and records the pids in `<ui dir>/serve.pid`; `setup-ui.sh stop` kills only pids whose command line names `http.server` or `setup-ui.sh`. Foreground is the default and Ctrl-C is enough.
- **`python3 >= 3.7`** is the only runtime requirement, and only for `serve` (both `--bind` and `--directory` date from 3.7). `jq` is a dependency of `build-floor.sh`, not of this engine: without it the page still serves and simply says how stale the copy it is showing has become.

### Query parameters (both read from the page URL)

| Parameter | Default | Meaning |
|---|---|---|
| `?stall=<seconds>` | `300` | how old a lane's last event may get before that lane reads **stalled** |
| `?stale=<seconds>` | `6` — `3 ×` the **page's own 2 s poll**, *not* `serve --interval` | how old `floor.json` itself may get before the page says so |

`?stale=` exists for a specific reason worth stating: a **committed fixture's `generated_at_epoch` is always in the past**, so without it every fixture would render under the stale banner and nothing else about the page could be demonstrated. Raise it when loading `fixtures/floor-ui/*.json` by hand.

It has a second, less obvious use. The page has **no way to observe `serve --interval`** — it polls on its own fixed 2 s clock, and its default threshold is three of those. With a perfectly legal `--interval 10` every render is older than that default, so the page would report a document that is being regenerated exactly as configured. Two things keep that from becoming a false claim: the banner states only what the page measured (the age, and the threshold it was measured against), never a cause it cannot see; and `serve` prints the URL to open — including `?stale=<3 × interval>` whenever its own interval outgrows the page default, and the bare URL when it does not.

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

## Motion is evidence, never decoration

There is exactly **one** timer in `floor.js` — the 2 s poll — and re-render is keyed on a changed `generated_at_epoch`. A lane's shuttle advances only when that lane's `events` count changed between two renders; a lane whose count did not change does not move. The single stated exemption is the `.pulse` keyframe, which is present **only on a non-stalled lane** — its absence *is* the stall signal, so it is state-driven even though a keyframe drives its frames.

Accessibility follows from the same rule: `@media (prefers-reduced-motion: reduce)` removes every animation and transition while leaving every state class rendered, and no state depends on colour alone — stalled is a dashed border plus `no event for <age>`, a read-only agent is a hollow dot plus the word `read-only`, identity-unknown is a dashed chip plus its own text, and absent/empty/stale are text banners. Both a light and a dark palette are defined, and `data-theme` overrides the system preference.

## What it does not claim

These limits are copied from the source requirement's 2026-09-03 amendment and are **design, not gaps**:

- **There is no "currently running agent" and no liveness anywhere on the page.** No spawn event exists in any log, so liveness could only be inferred from the recency of some other record — that is a guess, and the note under the lanes says so permanently.
- **Identity is partial.** `agent_type` is carried by a small minority of recorded events, so a lane whose `agent_id` never appeared on a typed line is drawn `identity unknown` rather than assigned a plausible role. `read_only` on a roster row is a **tri-state**: `true`, `false`, or **omitted entirely** when the agent declares no `disallowedTools` line at all — the third renders as `read-only unknown`, never silently as "not read-only".
- **A lane's number is events, not turns and not progress.** It counts recorded log lines for that `agent_id` in the newest session. Two lanes with the same count have not necessarily done the same amount of work.
- **The `state.md` phase can be stale on a real machine** (it has read `status: running` for long stretches). The page shows the state surface's own `mtime_epoch` age beside the phase and never labels a run "live".

## Local-only posture

`floor.json` is a projection of this machine's run state and **it carries branch names, session ids and agent ids**. Treat it as local data:

- `serve` **always** passes `--bind 127.0.0.1`. There is no flag to change that and no code path that omits it — the bind address is the whole security posture and it is deliberately not negotiable at the command line.
- `index.html` carries a `Content-Security-Policy` meta with `default-src 'self'` (and `connect-src 'self'`), `floor.js` fetches only the relative path `floor.json`, and the bundle contains no absolute URL, no protocol-relative reference, no `@import`, no preconnect and no web font — system font stacks only. `test-setup-ui.sh` scans all three files for each of those and carries a mutation control, so the scan cannot rot into a check that passes on anything.
- `python3 -m http.server` serves the **whole ui directory**, which is why the ui directory holds only the three bundle files, the marker, an optional `serve.pid` and the `floor.json` copy — nothing else is ever written there.

## What it writes — the whole list

1. **The ui directory** (default `$HOME/.claude/loomwright/ui`, overridable with `--ui-dir`, which is how every self-test runs inside a `mktemp -d`): the three bundle files, the ownership marker `.loomwright-ui-module`, an optional `serve.pid`, and a copy of `floor.json`.
2. **`.supervisor/floor/floor.json` under the current project root** — and only ever by running `build-floor.sh`, never by writing that path directly. `serve --no-regen` makes even that write impossible.

Nothing else, anywhere. It never touches the user-scope settings document (that is the `statusline` module's one write domain), never writes a project `.gitignore`, and never runs a history-touching git command. `test-setup-ui.sh` hashes two whole trees — the fixture parent and a fixture git repo used as the working directory — before and after a full `apply` → `serve` → `stop` → `remove` sequence, and asserts the only difference is that one regenerated file.

## Removing it

```
/setup ui              # check → report → offer, including remove when it is installed
```

`remove` deletes the ui directory **only** when the `.loomwright-ui-module` marker is present *at the resolved path*, and it additionally refuses `/`, `$HOME`, and anything at or under the plugin install directory. The resolved path is the **physical** one (`cd -P` / `pwd -P`): bash's logical `pwd` hands back the path you typed with its symlinks intact, so those three refusals would never see a target reached through a symlinked parent. A `--ui-dir` that is **itself a symlink** is refused outright — unlinking it would leave every byte of the target in place under a report saying it was removed, and a false "removed" is worse than a refusal. A directory without the marker is **reported and preserved** — `--ui-dir` is user-supplied, and a typo pointing at a real directory must not cost you that directory. Removal takes the bundle, the marker, the pidfile and the `floor.json` copy with it; the projection under `.supervisor/floor/` is regenerable and is left alone.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `serve: ABORTED — python3 not found` | `serve` is the only subcommand that needs it. Everything else (`check`, `apply`, `remove`) still works. |
| `serve: ABORTED — port <n> is already in use` | Something else holds the port. Re-run with `--port <n>`; the module will not move it for you. |
| The page says `floor.json is stale` under a live serve loop | Either `build-floor.sh` is not producing output — most often `jq` is missing (`serve` warns about this at startup) or the working directory is not the project root — **or `--interval` is longer than the page's 6 s default threshold**, in which case `serve` has already printed the `?stale=` URL to open instead. |
| The page says `no floor.json at this origin` | `serve` has not copied one yet (first tick), or you are serving a ui dir that was never applied to. Run `/setup ui` and re-check. |
| Everything renders but every lane says `identity unknown` | Expected on most sessions — see §"What it does not claim". The roster strip is still complete, because it comes from agent frontmatter rather than from logs. |
| `apply: WITHHELD — … carries no .loomwright-ui-module marker` | The ui directory exists but this module did not create it. Nothing was written. Point `--ui-dir` somewhere else, or remove that directory yourself. |

## Reference

- Engine: `loomwright/scripts/setup-ui.sh` (`check` / `apply` / `serve` / `stop` / `remove`; always exits 0 — "fails closed" means refuse-to-write plus a named-reason headline, never a non-zero exit)
- Bundle: `loomwright/scripts/floor-ui/{index.html,floor.css,floor.js}`
- Projector: `loomwright/scripts/build-floor.sh` → `.supervisor/floor/floor.json`
- Schema: `loomwright/docs/RESULT_SCHEMAS.md` §`FLOOR_PROJECTION`
- Self-test: `loomwright/scripts/test-setup-ui.sh` (static half; the browser halves are verified against the committed fixtures and recorded in the PR body)
- Module contract: `loomwright/skills/setup/SKILL.md` Pattern 2, flow in `loomwright/commands/setup.md` §"Module: ui"
