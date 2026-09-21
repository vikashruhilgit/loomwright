# 06 — `/ui`: a direct command, and one floor for every project

## Problem

Item 04 shipped The Floor, and using it exposed two frictions that are the same
underlying mistake in two places: **the view is reachable only the long way, and it can
only ever look at one project.**

1. **The only entry point is a configuration command.** `/setup ui` configures the module,
   which is correct for `apply` and `remove` — but `serve` and `stop` are *operations* you
   run daily, and running a web server through a setup verb is the wrong shape. In practice
   it pushed the owner back to `bash loomwright/scripts/setup-ui.sh serve` in a terminal,
   which is the friction the module existed to remove.

2. **The bundle is global but the data is per-directory, and nothing reconciles the two.**
   `apply` copies the bundle once to a single user-scope directory; `serve` regenerates
   `floor.json` from whatever directory it was launched in and copies it into that one
   shared slot. Sequential use works. Two projects at once collide on the slot, and the
   port guard — which refuses to move the port rather than silently serve the wrong bytes —
   is what actually saves you today. Per-project isolation exists only as two flags the
   user has to remember to pass (`--ui-dir`, `--port`), which is a workaround, not a
   feature.

## Goal

One always-available floor: a direct `/ui` command for the operational verbs, and a
user-scope project registry so a single page can show any registered project, with the
project chosen in the page rather than by which directory a terminal happened to be in.

## Scope

1. **A new `/ui` command** — `check` · `apply` · `serve` · `stop` · `remove` (module
   lifecycle, mirroring the engine) plus the registry verbs `add` · `list` · `forget` ·
   `scan`. `/setup ui` **stays** and keeps `apply` / `remove`, because those are genuinely
   configuration; the two entry points must not diverge, so the command file is a thin
   wrapper over the same engine and the parity is asserted by a test, not by prose.
   `forget` is deliberately not called `remove` — one word must not mean both
   "tear down the module" and "drop a project".

2. **A project registry at `~/.claude/loomwright/projects.json`** — a **sibling** of the ui
   directory, never inside it, so a module `remove` cannot destroy it (verified: `remove` is
   confined to the ui dir). Same neighbourhood as the existing
   `~/.claude/loomwright/observability`. It is the source of truth; anything the page reads
   is derived from it and lives under a different name so the two can never be confused.

3. **Manual add, opt-in scan, nothing automatic.** `add` with no argument registers the
   current project (the common case, zero friction); `add <path>` registers another;
   `scan <dir>` is bounded, **proposes** what it found, and writes only after an explicit
   confirmation. Nothing is ever auto-discovered or auto-registered — a floor carries branch
   names, session ids and agent ids, so putting a project on a served page is a decision the
   user makes, in the same consent posture the memory module already takes.

4. **One server, one port, a project picker in the page.** The selected project regenerates
   on the normal interval; every other registered project regenerates on a much slower
   cadence. **This scheduling is a hard requirement, not an optimisation:** a projector run
   measured **1.05–1.07 s** on this repo (13,641 log lines) on 2026-09-03 — re-measured after
   item 05 added the rules and churn detail surfaces, superseding the 0.85–0.95 s figure this
   requirement was originally written against (13,412 lines). The number moved for a real
   reason worth carrying: item 05's first cut of those readers was **3.5 s**, which alone
   exceeded `serve`'s 2 s default interval, and it passed 338 assertions and seven repo gates
   in silence. It is back under a second only because the redundant full scans were
   consolidated, and `test-build-floor.sh` case (x) now pins that with a ratio bound against
   the pre-consolidation commit. **So treat sub-second as earned, not given:** any future
   surface added to the projector spends this budget, and at ~1.06 s a naive
   "regenerate every project every tick" starves the loop at **two** projects, not three, and
   renders everything permanently stale. Each project displays its own generation age, so a slow
   project reads as genuinely behind rather than silently wrong.

5. **Per-project honesty, matching what the page already does for surfaces.** A registered
   project whose path no longer exists renders `unavailable` with the reason and is
   **never silently dropped** from the registry. One never yet regenerated says so rather
   than showing an empty floor. One that is not a git repository, or has no run state, still
   registers and still renders — the projector already reports absent surfaces honestly and
   that behaviour must not be special-cased away here.

6. **The page displays what the command reports — read-only, no new surface.** Module state
   (bundle present, registry readable, server interval) and the registry itself (each
   project's label, path, slug, last-regenerated age, and availability) are written into the
   served index the page already fetches, so `check` and `list` are answerable *in the page*
   without adding a single endpoint. **This item adds no request the current static server
   cannot already answer** — the server returns `501` on any write, verified, and it stays
   that way here. Buttons that mutate anything are item 07.

## Non-goals

- **No control plane in THIS item — deliberately, and deferred rather than declined.** Item
  04's non-goal ("it renders; it does not act") is relaxed by item **07**, which adds a
  guarded write API for `add` / `forget` / `scan` and a server `stop`. It is a separate item
  because the moment the page can write, item 04's stated reason for having no auth layer —
  "nothing to authenticate against on loopback" — stops being true: any site open in another
  tab can POST to a loopback port, and the write lands whether or not the attacker can read
  the reply. That deserves its own focused review, not a paragraph inside a UI feature.
- **No change to the security posture.** Still loopback-only, still no egress, and still no
  authentication layer — **valid here precisely because this item adds no write**, which is
  the condition the bullet above says item 07 removes. Read the two together: no auth is
  correct for a page that can only read, and becomes wrong the moment it can write. The
  registry increases what a single page can display, which is a documentation and consent
  obligation, not a reason to add a network surface.
- **No write path into any project.** Registering a project grants the view read access to
  what the projector already produces. `/ui` never writes inside a registered project except
  through `build-floor.sh`, exactly as `serve` does today.
- **No auto-discovery, no background indexing, no watcher.** Scan runs only when invoked.
- **No second agent, no new hook.** This is a command plus engine subcommands.
- **No cross-project aggregation, ranking or comparison.** The picker switches between
  projects; it does not compute a leaderboard. A view that ranks projects becomes a view that
  judges them, which is the same reasoning that keeps item 05 from scoring rules.

## Depends on

**04 merged** (hard — this extends its engine, its bundle and its docs). Independent of 05.

## Release-surface obligations

- **Commands go 21 → 22.** New `loomwright/commands/ui.md`, plus the lockstep: both
  manifests' version and `description` counts updated **in place**, `README.md`,
  `CLAUDE.md`'s latest-change paragraph, `commands/agent-help.md`, and `CHANGELOG.md`.
  `check-doc-currency.sh` fails CI otherwise.
- No new agent (so no token-budget entry) and no new hook — **if either turns out to be
  needed, bump every doc surface in the same commit.**
- `loomwright/commands/*` is ADAPTER-classified, so the new command file moves no ratchet.
  `setup-ui.sh` is CORE and **will** grow registry paths naming the user config directory,
  so its allowance moves: **measure it with `--print-allowances` after staging** and declare
  the measured value, never a hand-typed one.
- The `(z)` release-surface parity group in `test-setup-ui.sh` is the precedent for gating
  what no CI gate covers; extend it rather than trusting prose.

## Acceptance criteria

- [ ] Given a fresh install, `/ui check` reports module state and registry state in one
      report, and writes nothing — including when the registry file does not yet exist,
      which reports as `no projects registered`, never as an error.
- [ ] Given `/ui add` run with no argument inside a project, that project is registered with
      its absolute path and a slug derived from it; running it a second time in the same
      project reports `already registered` and writes nothing. Given `add <path>` where the
      path does not exist, nothing is written and the reason names the path.
- [ ] Given a registry containing three projects, `/ui list` prints each with its path, slug
      and last-regenerated age, marking any whose path is currently missing as `unavailable`
      — and `list` never mutates the registry, including when an entry is unavailable.
- [ ] Given `/ui forget <slug>`, that entry is removed from the registry and **the project
      directory itself is untouched** — asserted by hashing the project tree before and
      after. Given a slug that is not registered, nothing is written and the reason says so.
- [ ] Given `/ui scan <dir>`, candidate projects are listed as a **proposal** and the
      registry is unchanged until an explicit confirmation; the scan is bounded by a stated
      maximum depth, and a scan that finds nothing says so rather than printing an empty
      success. Asserted with a fixture tree, including the unconfirmed path writing nothing.
- [ ] Given two registered projects and `/ui serve`, one server on one port serves a page
      whose picker lists both; selecting the second switches the rendered floor to that
      project's data within one poll interval, and the branch and HEAD shown change with it.
      Browser-verified against committed fixtures, DOM read, with the console read for errors.
- [ ] Given five registered projects, the selected project's floor is regenerated on the
      configured interval while the others regenerate on the slower cadence, and **the loop
      never falls behind its own interval** — asserted by measuring elapsed time across a
      fixed number of ticks against a stub projector with a known cost, not by inspection.
- [ ] Given a registered project whose directory is deleted while `serve` is running, that
      project renders `unavailable` with the reason on the next poll, the other projects keep
      rendering, and the server does not exit.
- [ ] Given a registry file that is not valid JSON, every subcommand refuses to write,
      names the reason, preserves the file byte-for-byte, and exits 0 — the fail-safe
      convention the engine already uses (refuse-to-write plus a named reason, never a
      non-zero exit).
- [ ] `/setup ui` and `/ui` drive the **same** engine with no divergent behaviour, asserted
      mechanically (both paths' documented subcommand sets and the engine's real subcommand
      set agree), so the two entry points cannot drift.
- [ ] A module `remove` leaves the registry intact — asserted directly, because the registry
      living outside the ui directory is the whole reason it survives.
- [ ] Given three registered projects of which one path is missing, the page displays each
      project's label, path, slug and last-regenerated age, marks the missing one
      `unavailable` with the reason, and shows the module's own state (bundle present,
      registry readable) — **without issuing any request the static server cannot serve.**
      Asserted by a browser load against committed fixtures plus a static check that the
      bundle contains no `POST`, no `PUT`, no `DELETE` and no `fetch` with a `method` option.
- [ ] Given a registry that is absent or unparseable, the page says which of the two it is
      and still renders the rest of the floor — never a blank page, never a console error.
- [ ] The page still issues zero requests to any origin but its own, the server still binds
      loopback only, and both are asserted the way item 04 asserts them (a real network log,
      and a refused connection from a non-loopback address).
- [ ] The vendor-coupling ratchet is measured before and after and the delta reported,
      whatever it is.

## Outcomes Rubric

- The floor is reachable in one command, and switching projects never means restarting a
  server or remembering a port.
- A project appears on the page only because a human added it.
- Every project shows its own freshness; a slow or missing project reads as exactly that,
  never as an empty or wrong floor.
- The loop's cost is bounded and measured, not assumed.
- Everything the command can report, the page can show — while remaining a page that only reads.
- Loopback only, no egress, no write path into any registered project.

## Status: brief-shipped

Job `.supervisor/jobs/done/2026-09-04-ui-command-and-projects.md` completed (reconciled from the job lifecycle, not self-reported).
Acceptance criteria are NOT machine-verified here — review them before promoting this to `## Status: done`.

## Status: done (PR #181, merge c5f4e46)
- **Completed:** 2026-09-04T15:10:47Z
- **Brief:** .supervisor/jobs/done/2026-09-04-ui-command-and-projects.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/181
- **Reconciled:** 2026-09-21 by hand from the merged PR — the PR was merged outside the /automate loop, so nothing wrote this stamp at merge time.
