# af/39f — `/janitor`: one read-only report of everything the plugin left running or lying around, then act only on what the owner picks

## Status: pending

## Split from
`automate-followups/39d-proc-registry-and-janitor.md`, split 2026-10-22 by the owner. This item owns the Source
text's Scope items 5–7 and item 11's `/janitor` legs; the registry is `39e-proc-registry-and-reap.md` (a
dependency), the leak gate and attention lines are `39g-leak-gate-and-attention-lines.md`. Where the source and
this header differ, this header wins.

## Problem
See the Source text's Problem and the owner's ask there ("a command which shows all with all the details, and the
user can take action based on your suggestions").

## Goal
`/janitor` prints one grouped, read-only report — registered processes (39e `list`), run locks, lanes, worktrees and
branches (39a's `automate-trail.sh sweep` dry run), stale markers — with a suggested action per row, and in an
interactive session executes only the rows the owner selects, each through its guarded helper.

## Scope
1. Source items 5–7, with these 2026-10-22 corrections:
   - The report helper is a NEW script, `janitor-report.sh` (`--json` and a text table); the command doc only
     renders it and runs the owner question. Rows come from existing readers, never re-derived:
     `proc-registry.sh list`, `lane-status --leaks --snapshot` (`automate-lanes.d/park-leaks.sh`), `automate-trail.sh
     sweep` (dry run), `worktree-salvage.sh --check-ignored` per worktree (a worktree is removable only on
     `ignored-check: ok` or after salvage), `retention-sweep.sh` for stale run state.
   - caffeinate and `ci-slot.sh` holders are shown as "plugin-adjacent", report only.
   - Things the plugin did not start are shown, never given an action.
2. A new owner question gate: a row in `docs/ARCHITECTURE_CONTRACTS.md` §"Question-gate inventory" with a named
   can't-ask branch — non-interactive / `--report` / headless lane ⇒ report only, exit 0, never act.
3. A new command: `agent-help` entry, `prompt-token-budgets.json` entry + mirror row; let `check-doc-currency.sh`
   drive the count surfaces and prefer removing a restated count over editing it.

## Non-goals
The registry itself (39e). SessionStart / run-end lines and the `ci-local` gate (39g). Remote resources (GitHub
branches, PRs).

## Owner decisions (from _BACKLOG.md)
- 2026-10-22: 39d is split into 39e / 39f / 39g.
- Open, for Launch Pad to ask: does `/janitor` subsume `lane-status --leaks` (one place) or wrap it (both stay)?

## Acceptance criteria
- Source item 11's `/janitor` legs: `/janitor --report` makes no change (checksum of registry, locks, worktrees and
  branches before/after); the non-interactive path never acts; "not the plugin's" rows have no action.
- Mutation control: dropping the non-interactive guard fails its leg.
- The Source text's first two acceptance criteria hold on a fixture (a leaked fixture server, an old watcher, a dead
  lock holder, a merged clean worktree): every item appears once with owner, age, state, evidence and a suggested
  action; selecting one stops exactly that one after a command-line re-check.
- `bash scripts/check-version-bump.sh` passes with the `changelog.d/af39f-janitor-command.md` fragment.

## Validation (must pass before merge)
1. Targeted tests: `test-janitor-report.sh`, `test-proc-registry.sh`, `check-doc-currency.sh`,
   `test-citation-drift.sh`, `check-token-budget.sh`. Full `ci-local` on GitHub CI.
2. Running system: `/janitor --report` on this machine — paste the report into the PR body; then one interactive
   run where the owner picks one harmless row (or none) — paste what changed.
3. Rollback: `git revert`.

## Depends on
39e-proc-registry-and-reap.md

## Touches
loomwright/commands/janitor.md
loomwright/scripts/janitor-report.sh
loomwright/scripts/test-janitor-report.sh
loomwright/commands/agent-help.md
loomwright/docs/command-parts/agent-help/ops.md
loomwright/docs/ARCHITECTURE_CONTRACTS.md
loomwright/docs/prompt-token-budgets.json
loomwright/.claude-plugin/plugin.json
.claude-plugin/marketplace.json
README.md
CLAUDE.md
changelog.d/af39f-janitor-command.md

## Source text (verbatim from 39d — this item owns items 5–7 and item 11's /janitor legs)

##### Part B — 23 — Process registry + one `/janitor` command: see everything the plugin left running or lying around, act on it safely

###### Problem
Every kind of process the plugin starts in the background is tracked separately, if at all, and nothing shows
them together or cleans up orphans. Each mechanism today:
- merge watcher: a marker plus a pid with a command-line check and a 72h cap;
- run lock: pid liveness plus a 1800s TTL;
- detached review drain: a `.died` marker on a resultless exit;
- planned lanes (`parallel-automate/05`): a lane table;
- every other detached process: nothing.

Evidence, 2026-10-04 (S1, session 0d556d54), one `ps` on this machine:
- **3 Floor fixture HTTP servers** (Python, ports 57368 / 58482 / 59470), 2 days old. Their script paths were in
  deleted `mktemp` dirs, under a scratch worktree from a `ci-local` run. This is the same leak seen on
  2026-10-02, when 20 orphaned `test-setup-ui.sh` fixture servers were killed. `test-setup-ui.sh` already has
  careful EXIT-trap cleanup, so the survivors point to a path where that trap never runs. **Hypothesis to verify
  first:** `run-self-tests.sh`'s watchdog TERMs and, 2 s later, KILLs a timed-out test's process tree. A KILLed
  test cannot run its EXIT trap, and a `serve --detach` child is reparented outside that tree.
- **1 Python server** (port 7811), **27 days old**, started from another project's session scratchpad.
- A plugin merge watcher in another repo running **old plugin code** (15.115.0) for 2d18h. Legitimate, but
  invisible unless someone runs `ps`.
- Claude Code's own background sessions (`bg-pty-host`, about 10 days old) beside them. Those are not the
  plugin's, and nothing told the owner they were there.
- The opposite failure in the same session: headless `claude -p` silently KILLED a lane's background worker at its
  600 s ceiling. Tracking has to cover "died unexpectedly" as well as "never died".

The owner stopped the four strays by hand after each command line was re-checked. The ask: "a way to track
background tasks; I don't want any orphaned or stray task or session running", and "a command which shows all with
all the details, and the user can take action based on your suggestions".

###### Goal
One registry knows every detached process the plugin starts. One command shows the owner everything the plugin
has running or left behind — processes, locks, lanes, worktrees, branches, stale markers — with a suggested action
per row, and executes only the actions the owner picks, each through a guarded helper. Things the plugin did not
start are shown, never touched.

###### Scope

##### A. Registry (`proc-registry.sh`, per user: processes span repos)
1. **`register`** — called by every detached launcher. It records an entry under
   `~/.claude/loomwright/procs/<id>.json`: pid, start time (`ps -o lstart`), a hash of the full command line, the
   owning repo root, run id and lane (if any), purpose, `max_lifetime_s`, the launching session id, and
   `stop_hint` (how to stop it cleanly). Launchers in scope: `automate-merge-watch.sh`, `dispatch-pr-review.sh`
   (detached drain), `dispatch-pr-postmortem.sh`, `setup-ui.sh serve --detach`, and lane `claude -p` (item 05's
   `lane-launch` calls it). Writing the entry is fail-SAFE: a failed write never blocks the launch, but it is
   reported.
2. **Lifetime caps everywhere.** Every registered process has `max_lifetime_s`. Watchers already have 72h. A
   detached drain or postmortem gets its documented bound. A Floor server gets the owner's choice (default 12h).
   A lane gets a cap set at launch.
3. **`list`** — each entry is classified:
   - `live`: the pid is alive AND its command line still matches the hash;
   - `finished`: the pid is gone, or the pid was recycled to another command (never trusted);
   - `overdue`: live and past its cap;
   - `orphaned`: live while its owner is gone (repo removed, run `## Status: done`, lane removed, or the
     launching session ended for a process that should not outlive it).
   It also shows UNREGISTERED processes that look like the plugin's (a command line under any
   `loomwright/scripts/`, or a Python server whose script lives in a deleted `mktemp` dir) as `unregistered`.
4. **`reap [--apply] [<id>...]`** — dry run by default. It stops only `overdue` / `orphaned` registry entries whose
   LIVE command line still matches the hash, sending TERM and then KILL after the entry's grace period, and logs
   one line per process. It never kills by pid alone, and never kills anything that is not in the registry
   (`unregistered` rows need the explicit `/janitor` choice below, re-verified at the moment of the kill).

##### B. The command: `/janitor` (owner-chosen name, 2026-10-04)
5. **Report first, read-only.** One screen, grouped. Each row shows what it is, the owner (repo / run / lane /
   "not the plugin"), its age, its state with evidence, and the **suggested action** with the reason:
   - **Processes:** the registry `list`, plus `unregistered` look-alikes, plus a REPORT-ONLY "not the plugin's"
     group (Claude Code background sessions, other servers) with the native way to close each.
   - **Locks:** `run-lock.sh status` for the primary and every lane, flagging a dead holder.
   - **Lanes:** item 05's `lane-status --leaks` (live processes in lanes, `awaiting_input` lanes, `gone` lanes).
   - **Worktrees and branches:** item 22's `sweep` dry run (plugin-made: removable; app-made: report-only).
   - **Stale run state:** run files `paused` for more than N days, stranded `*.config-backup.json`, stale
     `.merge-watch` markers, `*.meta-push-failed` markers, unpushed metadata (`meta-sync status`).
   - **Background work not running when it should be:** a lane or drain whose run says running while its process
     is gone, i.e. the "killed silently" case.
6. **Then act on the owner's choice.** In an interactive session, `AskUserQuestion` (multi-select) lists the
   suggested actions, grouped; nothing is pre-selected for destructive actions. Each chosen action runs through its
   guarded helper only: `proc-registry.sh reap`, `sweep --apply`, `lane-remove`, `run-lock.sh` (stale reclaim;
   `--force-unlock` only with a second confirmation), `config-restore`, `meta-sync push`. It re-verifies each
   target immediately before acting (command line, cleanliness, PR merged), then prints what it did and a fresh
   one-line summary. `unregistered` look-alikes can be stopped only by the owner's explicit pick, after a
   command-line re-check. "Not the plugin's" rows have no action.
7. **Non-interactive** (`--report`, CI, or a headless lane): report only, exit 0, never act.

##### C. Surfacing and prevention
8. **SessionStart:** one line when anything is `overdue`, `orphaned` or `unregistered`
   (`N background item(s) need attention — run /janitor`). No network, no `ps` storm (one `ps` call).
9. **Run end and fleet close-out:** `/automate`'s `## Status: done` termination and item 06's fleet close-out
   append the registry summary to `## Progress`.
10. **Tests cannot leak (closes the Floor fixture leak at its source):**
    - Verify the hypothesis above with a fixture: time a test out under `run-self-tests.sh` and check for a
      surviving `serve --detach` child.
    - The watchdog stops a timed-out test's process GROUP, and fixture servers are started in that group, or are
      registered and reaped by the watchdog.
    - `ci-local.sh` takes a before/after snapshot of listening processes and of the user's process list filtered to
      the plugin's paths, and FAILS on anything new that survives the suite.
11. **Tests** (`test-proc-registry.sh`, hermetic):
    - register / list / reap round trip;
    - a recycled pid with another command line is classified `finished` and never killed;
    - overdue and orphaned classification;
    - reap dry-run changes nothing;
    - `/janitor --report` makes no change (a checksum of registry, locks, worktrees and branches);
    - the non-interactive path never acts;
    - "not the plugin's" rows have no action.
    **Mutation controls:** dropping the command-line check must fail the recycled-pid leg; dropping the
    non-interactive guard must fail its leg.

###### Non-goals
Managing Claude Code's own sessions or daemon (report and point to the app). Killing anything the plugin did not
start without an explicit per-item owner choice. Remote resources (GitHub branches, PRs).

###### Acceptance criteria
- Given today's machine state (or a fixture reproducing it: a leaked fixture server, an old watcher, a dead lock
  holder, a merged clean worktree), when `/janitor` runs, then every item appears once with owner, age, state,
  evidence and a suggested action, and nothing changes.
- Given the owner selects "stop the leaked fixture servers", then exactly those stop, after a command-line
  re-check, and the next report shows them gone.
- Given a test that times out, when the suite ends, then no fixture server survives, and `ci-local` fails if one
  does (proven with a deliberately leaking fixture).
- `bash scripts/ci-local.sh` green; command count and docs updated by the usual surfaces (`plugin.json`, doc
  currency); a `changelog.d/` fragment; `scripts/bump-version.sh` as the last commit.

###### Provenance
Owner, 2026-10-04, during S1 (session 0d556d54): "we need a way to track background tasks, I don't want any
orphaned or stray task/session running" and "add a command which shows all with all the details and the user can
take action based on your suggestions". Evidence from the same session's `ps` inventory, recorded above.
