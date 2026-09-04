---
description: The Floor, directly — start, stop and inspect the local loopback-only run view, and manage the project registry that decides which projects the picker can show (check | serve | stop | add | list | forget | scan). Configuration (apply / remove) stays with /setup ui.
---

> **Read-only on your code. The only files this command's engine writes are the ui directory, the project registry beside it, and `.supervisor/floor/floor.json` under a project it regenerates — and that last one only ever by RUNNING `build-floor.sh`, never by writing the path.** Registering a project writes **nothing into the project**, and `forget` is a registry edit only: it never touches the directory it is forgetting. The deterministic engine is `${CLAUDE_PLUGIN_ROOT}/scripts/setup-ui.sh` and it always exits 0 — "fails closed" here means refuse-to-write plus a named-reason headline, never a non-zero exit. Reference companion: `${CLAUDE_PLUGIN_ROOT}/docs/FLOOR_UI.md`.

# Command: /ui

> **This is the OPERATIONAL half of The Floor.** `/setup ui` is a *configuration* command — check → report → offer → apply → verify — and installing the page is a once-per-machine act. Starting it, stopping it, and deciding which projects it may show are *daily* operations, and routing them through a configuration dashboard is the friction that pushed people back to running the engine by hand in a terminal. `/ui` is that shorter path. It shares one engine with `/setup ui`, so there is no second implementation to drift.

## Purpose

The Floor is a single static page — three files, no framework, no bundler, no Node, no package manager — that renders `.supervisor/floor/floor.json` so a run stops being opaque while it is still running. Two things were awkward about reaching it:

1. **It was reachable only the long way.** `serve` and `stop` lived behind `/setup ui`'s offer flow.
2. **It could only ever look at one project.** The bundle is global but the data was per-directory: whichever directory `serve` was launched in owned the one shared slot. Two projects collided on it, and only the port guard (which refuses to move the port rather than serve wrong bytes) kept that from being silent.

`/ui` fixes the first directly and the second through a **project registry** — a small JSON file, `projects.json`, sitting *beside* the ui directory rather than inside it, so `remove` cannot take the user's list of projects with it. One server on one port then serves every registered project, chosen **in the page** rather than by which terminal you happened to be in.

**A project appears on the page only because a human ran `add` (or confirmed a `scan`).** There is no discovery-on-serve, and the page itself has no write path of any kind — it fetches two documents and sends nothing.

## Usage

```bash
/ui                     # same as `/ui check` — module state and registry state, writes nothing
/ui check               # report both halves in one report
/ui serve               # start the floor on 127.0.0.1:7734 (Ctrl-C stops it)
/ui serve --detach      # start it in the background, pids recorded in <ui dir>/serve.pid
/ui stop                # stop a server this module recorded
/ui add                 # register the CURRENT project
/ui add <path>          # register <path>
/ui list                # every registered project: slug, path, last-regenerated age
/ui forget <slug>       # drop one project from the registry (the directory is untouched)
/ui scan <dir>          # PROPOSE every unregistered git project under <dir> (writes nothing)
/ui scan <dir> --confirm  # register the candidates that proposal listed
```

`/ui` owns the operational and registry subcommands `check` / `serve` / `stop` / `add` / `list` / `forget` / `scan`.

Installing and uninstalling the bundle are configuration, so `apply` and `remove` stay with `/setup ui` — they are the two verbs that materialise and delete a directory of files outside the repo, and both are marker-gated behind an explicit confirm. `/ui` never installs and never deletes. Between the two commands, every subcommand the engine has is documented exactly once as somebody's responsibility; `test-setup-ui.sh` group `(m)` asserts that union against the engine's own dispatch table, so a verb the engine gains and nobody documents fails.

> **`forget` is deliberately not named `remove`.** One word meaning both "tear down the module" and "drop a project from a list" is a data-loss shape. `remove` deletes the ui directory; `forget` edits one JSON file.

## Flags

| Flag | Applies to | Meaning |
|---|---|---|
| `--ui-dir <dir>` | all | where the bundle lives (default `~/.claude/loomwright/ui`). **It cannot redirect the registry** — the registry is a *sibling* of the ui directory, not a file in it. |
| `--registry <file>` | all | override the project registry (default `projects.json` beside the ui directory). The only way to redirect it. |
| `--port <n>` | `serve` | default `7734`. A busy port is **reported and the server does not start**. |
| `--interval <n>` | `serve` | seconds between regenerations of the selected project (default `2`, minimum `1`). |
| `--no-regen` | `serve` | serve the `floor.json` already in the ui directory; run the projector for nothing. |
| `--detach` | `serve` | return immediately, recording pids in `<ui dir>/serve.pid`. |
| `--confirm` | `scan` | actually register the candidates the proposal listed. Without it, `scan` writes nothing. |

## Subcommands

Every flow is the same three steps: run the engine, relay its **headline status line verbatim**, and never paraphrase a refusal into a success.

### `check`

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-ui.sh" check
```

Read-only. Reports **both halves in one report**: the module half (ui dir, bundle `present (3 files)` / `INCOMPLETE — …`, the `python3:` / `jq:` / `build-floor.sh:` availability lines, the `installed:` cell, and the `UI readiness:` verdict `configured` / `not configured` / `stale (run apply)` / `WITHHELD (…)`), then a `== projects ==` section with the registry path and its state.

The registry's four states are four different claims and must be relayed as such:

- `no projects registered (there is no file there yet — 'setup-ui.sh add' creates it)` — **not an error.** A fresh install has no registry and that is the normal case.
- `no projects registered (the file exists but lists none)` — the file is there and empty.
- `N project(s) registered` — the ordinary case.
- `UNREADABLE — …` — either jq is missing, or the file is not valid JSON carrying a `"projects"` array. **Nothing will be written to it until a human fixes or deletes it**, and this module will not guess at its contents.

If `UI readiness:` is `not configured`, say so and point at `/setup ui` — `/ui` does not install.

### `serve`

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-ui.sh" serve
```

Run it **from the project root**. Relay the headline (`serve: 127.0.0.1:<port> — loopback only, this listener is not reachable from any other host`) and the lines under it: the ui dir, whether regeneration is on and from which directory, the `projects:` line, and the `open:` URL — **on one line so it can be copied whole**.

- **The `projects:` line states the cadence, not just the count.** The selected project regenerates every `--interval` seconds; the others one at a time on a slower cadence. That is not an oversight: one projector run costs about a second, so regenerating every project on every tick would starve the loop and render everything permanently stale.
- **The `open:` URL may carry `?stale=<n>`.** The page cannot see `--interval` — it judges freshness against three times its own fixed 2 s poll — so with a longer interval `serve` prints the URL that keeps the page from calling a perfectly current document stale. Relay whichever URL it printed; do not construct one.
- Fail-safe branches to relay **verbatim**: `serve: ABORTED — python3 not found`; `serve: ABORTED — <dir> does not exist. Run 'setup-ui.sh apply' first.`; `serve: ABORTED — build-floor.sh not found …` (suggest `--no-regen`); `serve: ABORTED — port <n> is already in use` — **this module never moves the port for you**, because a silently moved port is a browser tab reading bytes from something else; and the non-fatal `serve: note — jq not found …`.
- Foreground is the default and Ctrl-C is enough. `--detach` records pids in `<ui dir>/serve.pid`.

### `stop`

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-ui.sh" stop
```

Kills **only** pids whose command line names `http.server` or `setup-ui.sh`, and prints `stop: no-op` when there is no recorded server. Relay `no-op` as the ordinary answer it is, never as a failure.

### `add`

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-ui.sh" add           # the current directory
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-ui.sh" add <path>
```

Registers a project with its **absolute** path and a slug derived from it. Exactly one headline is printed:

- `add: registered '<slug>' — <abs path>` — followed by the standing statement that **nothing was written into the project itself; the registry is the only file this touched.** Repeat that to the user; it is the property the whole design rests on.
- `add: no-op — <abs path> is already registered as '<slug>'. Nothing was written.` — the second run in the same project. A no-op, not an error.
- `add: ABORTED — <path> is not an existing directory …` — the reason **names the path**. Nothing was written.

### `list`

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-ui.sh" list
```

Read-only, and read-only **including when an entry is unavailable** — a project whose directory has gone is reported and kept, never quietly dropped, because a project silently missing from the list is indistinguishable from one that was never added. Each entry prints its slug, its path and its last-regenerated age. `list: no projects registered` is the honest empty answer, not an error.

### `forget`

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-ui.sh" forget <slug>
```

Removes one entry from the registry. **The project directory itself is untouched** — the engine says so in its own output and the suite asserts it by hashing the project tree before and after. An unregistered slug is a named no-op (`forget: no-op — '<slug>' is not a registered project slug …`), and a missing slug argument aborts with the advice to run `list`. Neither writes anything.

### `scan`

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-ui.sh" scan <dir>
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-ui.sh" scan <dir> --confirm
```

A convenience over `add`. A candidate is a directory containing `.git`, and the walk is **bounded at 3 directory levels below the scan root — a bound the report PRINTS**, so a project that was never reached is explainable rather than merely missing from a list that looks complete.

**Without `--confirm` it is a PROPOSAL and writes nothing.** Relay the proposal and the line that says so; do not offer to "just apply it" without the user seeing the candidates. A scan finding nothing prints `scan: found no unregistered project here …` — say that, rather than reporting an empty success.

## Constraints

- **Loopback only.** `serve` always passes `--bind 127.0.0.1`. There is no flag to change that and no code path that omits it. `floor.json` carries branch names, session ids and agent ids: the bind address is the whole security posture and it is deliberately not negotiable at the command line.
- **The page only reads.** It fetches two relative paths (the served index, then the selected project's floor document) with no `method` option, and it declares a self-only content policy. Adding a write path here would invalidate the stated reason there is no auth layer.
- **This command never installs and never deletes.** `apply` and `remove` are `/setup ui`'s, and both WITHHOLD on a directory this module did not create.
- **Never re-run a refusal to "get past" it.** `WITHHELD`, `ABORTED` and `no-op` are all exit-0 answers with a named reason; surface the reason and stop.
- Do not hand-edit the registry on the user's behalf. If it is `UNREADABLE`, report the path and the reason and let the user fix or delete it.

## Learn More

- Reference companion: `${CLAUDE_PLUGIN_ROOT}/docs/FLOOR_UI.md` (what the page renders, what it deliberately does not claim, and the whole list of what the module writes).
- Configuration half: `${CLAUDE_PLUGIN_ROOT}/commands/setup.md` §"Module: ui"; the module-contract authority is `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md`.
- Projection contract: `FLOOR_PROJECTION` in `${CLAUDE_PLUGIN_ROOT}/docs/RESULT_SCHEMAS.md`.
