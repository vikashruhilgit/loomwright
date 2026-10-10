# 39 — Engine hygiene: clean up what the plugin leaves behind, keep its locks and guard arms honest, and fix the rules seam's false lines

## Status: pending

## Merged from (2026-10-10, owner decision: merge the serialized tail — these three cannot share a wave: all three edit `loomwright/skills/automate-loop/SKILL.md`, and af/34 ∩ ag/03 also share `automate-trail.sh` + its test and `automate-merge-watch.sh`)
- Part A: `automate-followups/34-sweep-and-janitor.md` — 34 — Clean up what the plugin left behind: a squash-safe sweep, a process registry and one `/janitor` command
- Part B: `agnostic-phase1/03-silent-script-failures.md` — 03 — Silent script failures (run-lock liveness outside Claude Code; guard hook-arm visibility)
- Part C: `automate-followups/21-rules-seam-dismissed-followups.md` — Rules seam: four dismissed Phase 4.5 findings from PR #319 (item 13)

The originals are parked with a pointer here. Their text is kept below VERBATIM as parts (headings
demoted, their Status / Depends on / Touches folded into this file's own sections). Nothing was paraphrased.
Their changelog.d fragment names are replaced by this item's one fragment. Part A is itself a merged item (its own
Parts A/B — af/22, af/23 — stay nested inside it).

## Depends on
../agnostic-phase1/01-ratchet-hardening.md

## Touches
loomwright/scripts/automate-helpers.sh
loomwright/scripts/fixtures/automate-helpers-help.golden
loomwright/scripts/automate-trail.sh
loomwright/scripts/test-automate-trail.sh
loomwright/skills/automate-loop/SKILL.md
loomwright/commands/automate.md
loomwright/docs/result-schemas/automate-run.md
loomwright/scripts/proc-registry.sh
loomwright/scripts/test-proc-registry.sh
loomwright/scripts/automate-merge-watch.sh
loomwright/scripts/dispatch-pr-review.sh
loomwright/scripts/dispatch-pr-postmortem.sh
loomwright/scripts/setup-ui.sh
loomwright/scripts/session-resume.sh
loomwright/scripts/test-setup-ui.sh
loomwright/scripts/run-self-tests.sh
scripts/ci-local.sh
loomwright/commands/janitor.md
loomwright/commands/agent-help.md
loomwright/scripts/run-lock.sh
loomwright/scripts/test-run-lock.sh
loomwright/scripts/guard-arm.sh
loomwright/scripts/test-guard-test-integrity.sh
loomwright/agents/supervisor.md
loomwright/skills/async-orchestration/SKILL.md
loomwright/skills/autonomous-loop/SKILL.md
loomwright/skills/supervisor-config/SKILL.md
loomwright/docs/HOOKS.md
loomwright/docs/ARCHITECTURE_CONTRACTS.md
loomwright/docs/RESULT_SCHEMAS.md
loomwright/docs/prompt-token-budgets.json
loomwright/docs/vendor-coupling-manifest.json
loomwright/skills/self-heal-advisory/SKILL.md
loomwright/scripts/test-rules-gate-seams.sh
loomwright/scripts/test-rules-seams.sh
changelog.d/automate-followups-39-engine-hygiene.md

## Goal
One change set for engine hygiene: the squash-safe sweep, process registry and `/janitor` (A); a run lock that always
records a live holder and a guard arm that leaves a trace when it did not happen (B); and the rules seam's posted line
matching its verdict, with its sink/reader patterns covering the repo's own idioms (C).

## Acceptance criteria
- Every part's own acceptance criteria hold, on one branch and one PR.

## Validation (must pass before merge)
1. Baseline full loop once for the merged branch, `<passed>/<total>` and `SKIP` counts, base and branch.
2. Every part's own Validation steps, labelled by part in the PR body. A part with no Validation section is
   checked by running its acceptance criteria, and the PR body says so.
3. Any "Running system" step a part names is run, or listed under "Not verified" with the reason.
4. Rollback: `git revert`.

## Parts
### Part A — 34 — Clean up what the plugin left behind: a squash-safe sweep, a process registry and one `/janitor` command

#### Merged from (2026-10-06, owner decision: fewer, larger items — a run costs ~$17–20 plus 4+ owner questions even for a tiny change)
- Part A: `22-squash-safe-sweep.md` — 22 — Squash-safe sweep: clean up worktrees and branches the plugin left behind, with closeout's own rule
- Part B: `23-process-registry-and-janitor-command.md` — 23 — Process registry + one `/janitor` command: see everything the plugin left running or lying around, act on it safely

The originals are parked with a pointer here. Their text is kept below VERBATIM as parts (headings
demoted, their Status / Depends on / Touches folded into this file's own sections). Nothing was paraphrased.

#### Goal
One change set for leftovers: the squash-safe sweep of worktrees and branches with closeout's own rule (A), and the process registry plus `/janitor`, which uses that sweep (B).

#### Acceptance criteria
- Every part's own acceptance criteria hold, on one branch and one PR.

#### Validation (must pass before merge)
1. Baseline full loop once for the merged branch, `<passed>/<total>` and `SKIP` counts, base and branch.
2. Every part's own Validation steps, labelled by part in the PR body. A part with no Validation section is
   checked by running its acceptance criteria, and the PR body says so.
3. Any "Running system" step a part names is run, or listed under "Not verified" with the reason.
4. Rollback: `git revert`.

#### Parts

##### Part A — 22 — Squash-safe sweep: clean up worktrees and branches the plugin left behind, with closeout's own rule

###### Problem
`closeout` (`automate-trail.sh`) cleans up exactly one PR, the one it was called for. It removes that PR-head
worktree only when it is clean after `worktree-salvage.sh`, and deletes the local head branch only when its tip
equals the PR's `headRefOid` (squash merges make ancestry useless, so `-d` and "0 commits outside main" are never
used). Nothing else in the plugin cleans up, so anything that never went through `closeout` stays forever:
- **PRs merged outside `/automate`** (`/supervisor`, `/review-pr` or a hand session). On 2026-10-03 the primary
  carried 5 worktrees whose PRs (#362, #363, #364, #368, and one detached checkout already on `main`) were merged
  and clean. The owner removed them by hand.
- **Old local branches.** 20 local branches (`feature/v12-S1…S5`, `pr-12`, `pr-24`, `release/v13.1.0`, `dev-temp`,
  …) are not ancestors of `origin/main`. Most are probably squash-merged, which no ancestry check can see, so
  each needs the `headRefOid` test to decide.
- **Supervisor's parallel-path worktrees** (`../<project>-<subtask>`, `async-orchestration` FINALIZE) left by a
  run that died before FINALIZE's own cleanup.

###### Goal
One command reports, and on request removes, exactly the worktrees and local branches that are provably done:
the same proof `closeout` already trusts. Anything uncertain is reported and kept.

###### Scope
1. **`automate-helpers.sh sweep [--apply] [--root <checkout>]`** (delegated to `automate-trail.sh`, beside
   `closeout`). Without `--apply`, a DRY RUN: it prints and changes nothing. One line per candidate:
   `sweep: would-remove|removed|kept <kind> <path-or-branch> — <reason>`, then one summary line. Always exit 0
   (fail-SAFE, like `closeout`).
2. **The rule is exactly closeout's**, with no new heuristic. For a local branch `B`:
   - find its PR (`gh pr list --state merged --head B`, the newest);
   - the candidate is removable ONLY when that PR is `MERGED` AND `B`'s tip equals the PR's `headRefOid`;
   - a branch with no PR, an open or closed-unmerged PR, a tip that moved after the merge, or a `gh` failure is
     `kept` with that reason (fail CLOSED toward keeping).
   - Never the current branch, the base branch, or a branch checked out in any worktree that is itself kept.
3. **Worktrees, by owner:**
   - **Plugin-made** (Supervisor's sibling `../<project>-<subtask>` worktrees, `trail-pr`'s temporary worktrees,
     `<primary>-lanes/**` lane clones): removable under rule 2 applied to the worktree's branch, only when clean
     after `worktree-salvage.sh`, and through `git worktree remove` (never `--force`, never `rm -rf`).
     **Lane clones are never swept here.** They belong to `lane-remove` (`parallel-automate/05`), which also
     checks live processes and pending questions. `sweep` reports them as `kept lane — use lane-remove`.
   - **App-made** (`.claude/worktrees/*`, created by the Claude desktop app for its sessions): **report only**,
     never removed, even with `--apply`. The app owns them and has its own cleanup (Settings › Storage). The
     report says which are clean and merged, so the owner can remove them there.
4. **Live processes:** a worktree whose path is the cwd of a live process (`lsof` where available) is `kept`
   with the pid named. No kill.
5. **Where it runs:**
   - on demand (`/automate --sweep`, a flag of the existing command; no new command, so the counts don't move);
   - in dry-run mode at the `## Status: done` run end, with one summary line appended to `## Progress`;
   - by item 06's fleet closeout, in dry-run mode.
   It never runs `--apply` unattended.
6. **Tests** (`test-automate-trail.sh`, new group, `gh` stubbed, real git repos in `mktemp -d`):
   - a merged PR whose tip equals `headRefOid` ⇒ `would-remove`, and `removed` with `--apply`;
   - tip moved after merge ⇒ `kept`;
   - an open PR, a closed-unmerged PR, no PR, a `gh` failure ⇒ `kept`, each with its reason;
   - a dirty worktree ⇒ `kept`;
   - an app-made `.claude/worktrees/x` that is clean and merged ⇒ reported, NOT removed with `--apply`;
   - a lane clone ⇒ `kept lane`;
   - the dry run changes nothing (a checksum of `git worktree list` + `git branch` before and after);
   - always exit 0.
   **Mutation controls:** dropping the `headRefOid` comparison must fail the moved-tip leg; dropping the
   app-made exclusion must fail its leg.

###### Non-goals
Remote branches (GitHub's "delete branch on merge" owns those). Session transcripts (Claude Code's 30-day
`cleanupPeriodDays` owns those). Lane teardown (`parallel-automate/05` `lane-remove`). Any `--force`.

###### Acceptance criteria
- Given this repo's 20 non-ancestor local branches, when `sweep` runs dry, then each is listed as `would-remove`
  or `kept` with a reason, and nothing changes (pasted output + the unchanged `git branch` checksum).
- Given `--apply`, then only `would-remove` items go, and a second dry run lists none of them.
- Given a clean, merged app-made worktree, then `--apply` reports it and leaves it in place.
- `bash scripts/ci-local.sh` green; ship a `changelog.d/` fragment (bump with `scripts/bump-version.sh` as the
  last commit, never by hand).

###### Provenance
Owner, 2026-10-03, during S1 (session 0d556d54): "the cleanup should be handled by the plugin like we are doing
in closeout". The lane-specific half was amended into `parallel-automate/05` (`lane-remove` refusals) and `/06`
(fleet closeout teardown + leak summary) the same day. Evidence: 5 stale worktrees in the primary, removed by hand
with `git worktree remove` after checking each was clean and merged; 20 old local branches still open.

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

#### Touches re-pointed 2026-10-07 (S3 operator f849e0cc, after pa/11's split — #408, v15.124.0)
- `RESULT_SCHEMAS.md` → `result-schemas/automate-run.md` (the sweep's and registry's run-file / `## Progress` lines).
  If Part B's process registry gets its own documented format, add a new `result-schemas/<name>.md` plus the index.
- `automate-helpers.sh` kept (Part A adds the `sweep` dispatcher arm, delegated to `automate-trail.sh`) +
  `fixtures/automate-helpers-help.golden` (a new subcommand regenerates the `--help` golden,
  `test-automate-helpers-dispatch.sh` check 5).

### Part B — 03 — Silent script failures (run-lock liveness outside Claude Code; guard hook-arm visibility)

#### Problem
Two fail-safe scripts fail *silently* in ways that weaken the guarantee they exist for.

1. **`run-lock.sh` records a pid that is already dead.** `holder_pid()` (`scripts/run-lock.sh:173-193`) resolves the
   liveness pid as `CLAUDE_PID` (if alive) → the first non-shell ancestor, but ONLY when `CLAUDECODE` is set → else
   `$PPID`. Outside Claude Code (a CI step, a terminal, any other harness) the `$PPID` is the invoking shell, which
   exits right after `acquire`. Exercised 2026-09-30 against a scratch `--root`: with `CLAUDE_PID`/`CLAUDECODE`
   unset, meta recorded `pid_source ppid` and that pid was dead immediately; a second owner was refused while the
   lock was young (TTL) but TOOK the lock once `ts` was ≥1800 s old — i.e. any run lasting over 30 minutes can be
   double-entered. The header (`:36-38`) acknowledges the TTL degradation but nothing surfaces it at acquire time.
   The ancestor walk itself is harness-neutral; only its `CLAUDECODE` gate is Claude-specific.
2. **The guard's hook arm path fails invisibly.** `guard-arm.sh arm-from-payload` (the `PreToolUse[Agent|Task]`
   backstop, carried with `|| true`) exits 0 without arming when `jq` is missing, the payload's
   `tool_input.subagent_type` is not one of the four armed roles, the payload has no valid `session_id`, or the
   marker write fails — and records nothing anywhere. The prompt-step `arm` is loud (exit 3,
   `guard_arm_failed: no session id`), but when the backstop is the arm that mattered, a session can run a
   Loomwright worker with the test-integrity guard never armed and no one can tell afterwards.

#### Goal
The run lock records a live holder whenever one exists (under any harness) and says so loudly when it cannot; a
guard arm that did not happen leaves a durable, readable trace — without changing either script's exit-code
contract.

#### Scope
1. **run-lock `holder_pid()`**: run the ancestor walk unconditionally (drop the `CLAUDECODE` gate); keep
   `CLAUDE_PID` first; `$PPID` only when the walk finds no non-shell ancestor > 1. Keep the `pid_source` values
   (`claude_pid` | `ancestor` | `ppid`). Consider (and decide in the PR) whether a non-shell ancestor that is a
   short-lived wrapper (e.g. `env`, `timeout`, `xargs`, `sudo`) must be skipped like a shell — add them to the skip
   list only with a test.
2. **Degraded-lock warning**: when the recorded source is `ppid`, `acquire` prints one stderr line
   `run_lock_degraded: pid_source=ppid ttl_only=1800s` (exit code unchanged) and `status` shows it. Callers that
   already surface `run_lock_held` (automate PICK, Supervisor INIT, `/autonomous` INIT) surface this line too —
   verify each caller's prose, do not add new gates.
3. **Guard arm trace**: `arm-from-payload` appends ONE JSONL row to the session log the other emitters use
   (`.supervisor/logs/<session_id>.jsonl`, resolved the same way `emit-agent-identity.sh` resolves it) when it
   declines to arm for a role it SHOULD arm (`subagent_type` in the armed set) — reasons: `jq_missing` (write via
   printf, no jq), `no_session_id`, `marker_write_failed`. Event name `guard_arm_skipped` with `reason` and
   `subagent_type`. Non-armed roles stay silent (that is correct behaviour, not a failure). Still ALWAYS exit 0;
   the hook keeps `|| true`. If no log dir can be resolved, write nothing (fail-safe) — state that limit.
4. **Surface it**: Supervisor FINALIZE (or the run summary it already prints) reports `test_guard: armed | unarmed
   (<reason>) | not_applicable` for its own session, read from the marker file + the `guard_arm_skipped` rows.
   Advisory only — it must not block, park, or change any decision.
5. **Tests**: `test-run-lock.sh` — with `CLAUDE_PID`/`CLAUDECODE` unset and a non-shell parent (spawn the script
   from a `python3 -c 'subprocess…'` or `perl` parent that stays alive), `pid_source` is `ancestor` and the pid is
   alive; with only shells above, `ppid` + the degraded stderr line. Guard: fixture payloads for each skip reason
   ⇒ one `guard_arm_skipped` row, exit 0; non-armed role ⇒ no row. **Mutation control:** re-add the `CLAUDECODE`
   gate ⇒ the ancestor test must fail.
6. Docs: script headers, `HOOKS.md` guard row, CHANGELOG, version bump.

#### Non-goals
Changing the TTL (1800 s), `--force-unlock`, or the reclaim rule (pid dead AND age ≥ TTL). Adding a heartbeat.
Making `arm-from-payload` exit non-zero or removing its `|| true`. Changing which roles arm the guard (item 02 fixes
the spawn shape that bypassed it). Any change to `guard-test-integrity.sh`'s deny logic.

#### Acceptance criteria
- `env -u CLAUDE_PID -u CLAUDECODE <live non-shell parent> bash run-lock.sh acquire --owner t --root <scratch>`
  ⇒ meta `pid_source ancestor`, `kill -0 <pid>` succeeds.
- Only-shell parents ⇒ stderr contains `run_lock_degraded: pid_source=ppid`; exit code as before.
- `printf '{"tool_input":{"subagent_type":"loomwright:loomwright:worker"}}' | bash guard-arm.sh arm-from-payload`
  in a scratch project ⇒ exit 0 and one `guard_arm_skipped` row with `reason: no_session_id`.
- `grep -c '|| true' ` on the hooks.json guard-arm leaves unchanged; the two `guard-test-integrity.sh` leaves still
  carry none.
- Full test loop + root checks green.

#### Verified premises (re-check before starting)
- `run-lock.sh` header resolution order (lines ~26-40, incl. the 2026-09-26 observation) and `holder_pid()`
  (~173-193); reclaim rule (~240-250).
- `guard-arm.sh` `cmd_arm_from_payload` (~193-206): every non-arming branch is a bare `exit 0`.
- Prior decisions NOT to re-litigate: red-team-hardening/06 (lock shape, TTL, human-only `--force-unlock`);
  six-phase-loop-gaps/02 Rev 4 (one marker per session, no overwrite rule, no tool-call disarm, `arm` exits 3 on
  no id).

bump = write a `changelog.d/` fragment and run `scripts/bump-version.sh`

### Part C — Rules seam: four dismissed Phase 4.5 findings from PR #319 (item 13)
> **Promoted from `proposed/` 2026-10-01** (owner triage session). Bundles the four `/automate` gate drafts
> `automate-2026-09-30-054439--13-dismissed-findings-triage-sweep-ce364e--dismissed-{1b4e0236,3d8b82d7,c37bc07f,summary}.md`,
> all recorded with owner decision **follow-up** in that run's `.dismissed-decisions` ledger. Source PR:
> https://github.com/vikashruhilgit/loomwright/pull/319 (round 1, origin `phase_4_5`, source `code_reviewer`).
> The finding text below is the reviewer's, quoted as data. Re-verify each one against `main` before changing anything.

#### Findings

1. **MEDIUM, reproduced (`c37bc07f`, dismissed `pre_existing`).** `rules_check_line` tests `$NO_CMD_FLAG` before
   `unreadable`, so a `--no-cmd` run on an unparseable store escalates `rules_gate_unresolved` while posting
   `rules_check: cmd_disabled`. The posted line and the verdict disagree.
2. **MEDIUM, reproduced (`3d8b82d7`, dismissed `below_severity_floor`).** `SEAM_C_VAR_ASSIGN_RE` misses the repo's own
   `$(cd …)/read-rules.sh` reader idiom, spaced paths, `declare`/`local -r` and alias chains. Its "Limit" comment
   understates the gap.
3. **LOW (`0988b86c`, summary entry, dismissed `below_severity_floor`).** `SEAM_C_SINK_PIPE_RE` misses `| /bin/bash`,
   `| env bash`, `| ksh`; `SEAM_C_SINK_PROCSUB_RE` stops at a nested paren.
4. **LOW (`1b4e0236`, dismissed `pre_existing`).** `skills/automate-loop/SKILL.md` §10 condition 7 `cmd_disabled ⇒ PARK`
   bullet omits that an advisory-only store or an empty selection still reads `none` under `RULES_CHECK_NO_CMD=1`.

#### Scope (recommendation)
- 1: reorder so `unreadable` wins over `cmd_disabled` (fail-CLOSED reading), with a fixture leg for `--no-cmd` +
  unparseable store.
- 2–3: widen the seam regexes or, if a regex cannot express the idiom, state the gap honestly in the Limit comment.
  Add one fixture per missed shape.
- 4: one-sentence doc fix in §10 condition 7.

#### Acceptance criteria
- [ ] Each finding re-verified on `main`, then fixed or recorded as not reproducible.
- [ ] Fixture legs for 1–3; the full `test-*.sh` loop green.
