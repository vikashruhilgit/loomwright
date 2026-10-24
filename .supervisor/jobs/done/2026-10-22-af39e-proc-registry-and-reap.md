# Supervisor Job: af/39e — process registry (register / list / reap) for every detached process the plugin starts, plus a watchdog that stops a timed-out test's whole process group

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-22-123646/L2
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/automate-followups/39e-proc-registry-and-reap.md
- **Base commit:** 7b7cb08392ce372c66c0694db7ced666fd0cbba9

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure bash 3.2 / BSD userland + `jq`, like every sibling script (`run-lock.sh`, `automate-lanes.d/common.sh`'s `lanes_proc_alive`). |
| 2 | Dependency Availability | GO | Uses only `ps -o lstart=` / `ps -ww -o command=`, `kill`, `jq`, and `shasum`→`sha1sum`→`cksum` (the fallback chain `automate-lanes.d/park-leaks.sh` already uses). No new dependency. |
| 3 | Architecture Fit | CAUTION | The registry is a user-scope store (`~/.claude/loomwright/procs/`, beside `egress.json` and `drain-allowlist.json`). Tests do not fake HOME the same way everywhere (`hermetic-test-env.sh`: "never touches HOME"), so a launcher that registers inside an existing test would write to the real home unless the registry redirects itself under the hermetic layer. |
| 4 | Scope vs Supervisor Capability | CAUTION | About 17 files and roughly 1,200 changed lines, which is over the `context-bound` bound. Split into 3 subtasks. |
| 5 | Hard Blockers | GO | No touched file is guard-protected (`guard-test-integrity.sh`'s `is_protected_basename` lists `guard-test-integrity.sh|guard-arm.sh|hooks.json|host-mode.sh`, none of them touched). `hooks.json` is not edited. |

**Overall Verdict:** CAUTION

## Task
**Goal:** Ship `loomwright/scripts/proc-registry.sh register | list | reap`. Every detached launcher in the plugin registers its process. `list` classifies each entry `running` / `overdue` / `orphaned` / `finished`. `reap` stops only overdue or orphaned entries whose live command line still matches. `run-self-tests.sh`'s watchdog stops a timed-out test's whole process group, so a double-forked child can no longer outlive it.

**Problem Statement:**
The plugin owner needs one place that knows every background process the plugin started, so that orphaned or stray processes can be listed and stopped safely.
Today each detached process is tracked separately, if at all: the merge watcher has a 72h cap and a marker, the run lock an lstart fingerprint, lanes a `.died` marker, and the drain and postmortem dispatchers nothing at all. Separately, `run-self-tests.sh`'s watchdog collects a timed-out test's descendants by walking ppids. That walk misses children that were double-forked (`( nohup … & )`) and re-parented to pid 1, which is how fixture servers leaked for days (39d's 2026-10-04 evidence).
Success looks like this: a round-trip-tested registry that never signals a recycled pid, every launcher in scope registering (one hermetic test each), and a fixture that proves a timed-out test's double-forked child dies.

**Owner decisions (Launch Pad, 2026-10-22, LP-CLARIFY):**
- **Lifetime caps ("Tight"):** phase session 6h (21600 s), lane 24h (86400 s), review drain 4h (14400 s), postmortem 1h (3600 s), merge watcher 72h. `proc-registry.sh` owns the table for the first four, and it is the only place they live. Each can be overridden per kind with `LOOMWRIGHT_PROC_MAX_S_<KIND>` (`KIND` ∈ `PHASE` `LANE` `DRAIN` `POSTMORTEM`). A launcher passes `--kind`, never a number. The merge watcher's cap already lives in `automate-merge-watch.sh` (`LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS`), so the registry does not restate it: `--kind merge-watch` REQUIRES `--max-lifetime`, has no table default, and the watcher passes its own resolved `$max`. A missing `--max-lifetime` for that kind takes AC3's fail-safe path.
- **Registry location ("User-level"):** `${HOME}/.claude/loomwright/procs/<id>.json`, whatever the host mode. `LOOMWRIGHT_PROC_REGISTRY_DIR` overrides it and is the test seam.

**Scope decisions made here (header wins over the Source text, per the requirement):**
- The four classes are the requirement header's `running` / `overdue` / `orphaned` / `finished`. The Source text's `live` is called `running` here.
- The Source text's `unregistered` look-alike rows (item 3, last paragraph) are **not** in this item. They are a report row, so they belong to 39f's `/janitor` report. `list` shows registry entries only.
- Registration is fail-SAFE. `register` always exits 0. A failed write prints one `proc-registry: register failed — <reason>` line on stderr and never blocks or changes the launch.

## Acceptance Criteria

Registry (Subtask 1):
- [ ] AC1. Given an empty registry dir (`LOOMWRIGHT_PROC_REGISTRY_DIR` = a temp dir), when `proc-registry.sh register --pid <p> --kind <k> --purpose <text> [--repo <root>] [--run-id <id>] [--runfile <path>] [--lane <dir>] [--owner-pid <pid>] [--max-lifetime <s>] [--grace <s>] [--stop-hint <text>] [--expect <substring>]` runs for a live fixture process, then exactly one `<id>.json` exists holding `pid`, `pid_start` (`ps -o lstart=`, C locale), `cmd_hash` (a hash of the full `ps -ww -o command=` line), `kind`, `purpose`, `repo`, `run_id`, `runfile`, `lane`, `owner_pid`, `owner_start`, `max_lifetime_s`, `grace_s`, `registered_at`, `session_id` and `stop_hint`. Absent optionals are JSON `null`. The JSON is built with `jq --arg`/`--argjson` (never shell-templated). The id is derived from pid + start time, so registering the same live process twice rewrites one entry and never creates two. A different process that later reuses the pid (a different start time) gets a NEW entry and never overwrites the old one.
- [ ] AC2. Given `--expect <substring>`, when the process's command line does not yet contain it (a `nohup` that has not exec'd yet), then `register` waits, bounded at about 2.5 s, for the command line to contain it before hashing. If it never appears, `register` still writes the entry and reports one `proc-registry: register — command line never matched --expect` stderr line.
- [ ] AC3. Given `register` cannot write (unwritable dir, `jq` missing, dead pid), when it runs, then it exits 0 and prints exactly one `proc-registry: register failed — <reason>` line on stderr.
- [ ] AC4. Given registered entries, when `proc-registry.sh list` runs, then it prints one row per entry with id, kind, pid, age, class and the evidence for that class. Each entry is classified as:
  - `finished`: the pid is gone, OR its `lstart` differs, OR its live command-line hash differs. A recycled pid is never trusted.
  - `overdue`: running and older than `max_lifetime_s`.
  - `orphaned`: running while its owner is gone, meaning the `repo` dir is missing, OR the `runfile`'s `## Status:` is `done`, OR the `lane` dir is missing, OR the `owner_pid` is dead or recycled (its `owner_start` differs).
  - `running`: otherwise.
  When an entry is both overdue and orphaned, the row prints `overdue`. `list` exits 0 and changes nothing.
- [ ] AC5. Given entries in every class, when `proc-registry.sh reap` runs without `--apply` (dry run), then it prints the action it would take per entry, sends no signal, and the registry dir's checksum (every file's content and name) is unchanged.
- [ ] AC6. Given `reap --apply [<id>...]`, when an entry is `overdue` or `orphaned`, then reap re-reads the live `lstart` + command-line hash immediately before each signal. It sends TERM, waits up to the entry's `grace_s` (default 10), sends KILL only if the process still matches, appends one line per process to `<registry dir>/reap.log` (each append keeps the log to its last 1000 lines, so the user-scope file stays bounded; nothing else rotates it), and removes the entry. `finished` entries are pruned (file removed, no signal). `running` entries are never touched. It never signals by pid alone and never touches a pid that is not in the registry.
- [ ] AC7. Given a recycled pid (an entry whose pid is alive but runs a different command line), when `list` runs, then the row is `finished`; and when `reap --apply` runs, the process is still alive afterwards. **Mutation control** (in `test-proc-registry.sh` itself, built with the lesson-`fa32a308` gate: non-empty, differs from the original, `bash -n`): a copy of `proc-registry.sh` with the command-line-hash comparison removed classifies that fixture as something other than `finished` (or signals it), so the leg goes red on the mutant.
- [ ] AC8. Given `HERMETIC_TEST_ENV=1` and no `LOOMWRIGHT_PROC_REGISTRY_DIR`, when any subcommand runs, then the registry resolves to `$HERMETIC_SHIM_DIR/procs` (never `$HOME/.claude/loomwright/procs`). A test that sets `HERMETIC_TEST_ENV=1` and a fake HOME proves nothing lands under that HOME. `hermetic-test-env.sh` can leave `HERMETIC_SHIM_DIR` empty (both mktemps failed) while still exporting `HERMETIC_TEST_ENV=1`. So when `HERMETIC_TEST_ENV=1` and `HERMETIC_SHIM_DIR` is empty or not a directory, `register` takes AC3's fail-safe path (no write, one `register failed — hermetic registry dir unavailable` stderr line), and `list`/`reap` report an empty registry. The resolver never falls back to `$HOME` and never to `/procs`.
- [ ] AC9. `proc-registry.sh`'s header comment is the contract (no new doc): subcommands, entry keys, the four classes and their precedence, the caps table with its `LOOMWRIGHT_PROC_MAX_S_<KIND>` overrides, the registry location and its override, the hermetic redirect, the exit codes (`register` and `list` always 0; usage error non-zero), and the "never signal by pid alone" rule.

Launchers (Subtask 2): one hermetic test per launcher, no real `claude` (a stub on PATH or `LOOMWRIGHT_CLAUDE_BIN`), every test with its own `LOOMWRIGHT_PROC_REGISTRY_DIR`:
- [ ] AC10. `automate-merge-watch.sh`: given it wins its single-instance marker, then the registry holds one `merge-watch` entry for its own pid (`$$`), with `--max-lifetime "$max"`, the run file and `stop_hint` (TERM the pid; its trap removes the marker). Covered in `test-automate-next-step.sh` (see AC11).
- [ ] AC11. `automate-next-step.sh`: given the default `ns_watch` path (no `NEXT_STEP_WATCH_CMD`) launches the watcher against a fixture run file with a stub `gh` (`LOOMWRIGHT_GH_BIN`) that reports OPEN, then within a bounded wait (`wait-lib.sh`, never a fixed sleep) the registry gains a `merge-watch` entry whose pid is the launched watcher. The test stops that watcher and its marker afterwards. The entry may be written by the watcher itself (AC10), so the next-step side needs no second registration call. If one is added anyway, AC1's pid+start id keeps it to one entry.
- [ ] AC12. `dispatch-pr-review.sh`: given a real (non-DRY_RUN) launch with the stub claude the existing G2 "real launch" fixture uses, then the registry holds one `drain` entry for the detached wrapper's pid (registered from inside the wrapper as `$$`, with the registry script passed as a new trailing positional arg), with `repo`, `stop_hint` and the 4h default cap.
- [ ] AC13. `dispatch-pr-postmortem.sh`: given a real (non-DRY_RUN) launch with a stub `LOOMWRIGHT_CLAUDE_BIN` that sleeps, then the registry holds one `postmortem` entry for the stub's pid (registered from inside the detached subshell with `--pid $!` and `--expect`), with the 1h default cap. The marker-before-launch order is unchanged.
- [ ] AC14. `automate-lanes.d/launch.sh` (`_lanes_spawn`): given `lane-launch` with the suite's stub claude, then the registry holds one `lane` entry for the `_lane-run` wrapper pid with `lane` = the lane dir, `run_id`, and the 24h cap. It is registered after the existing `lanes_proc_alive` wait loop, so the command line is the wrapper's. Test I1's "coordinator never writes into a launched lane" checksum still passes.
- [ ] AC15. `automate-lanes.d/phase.sh` (`_lanes_phase_spawn`): given `phase-launch` with the suite's stub claude, then the registry holds one `phase` entry for the phase wrapper pid with the run file, the phase name in `purpose`, and the 6h cap, registered after the existing `_lanes_phase_alive` wait loop.
- [ ] AC16. For each launcher test, a mutation control that deletes that launcher's one registration call makes its leg red. Each launcher contains exactly one registration call line. Also, a launch whose `proc-registry.sh` call fails (registry dir unwritable) still launches: the launcher's exit code and stdout are unchanged.

Watchdog (Subtask 3):
- [ ] AC17. Given a fixture test that times out under `SELF_TEST_TIMEOUT=2` and leaves a double-forked child (`( nohup sleep 300 & echo $! > <pidfile> )`, re-parented outside the test's ppid tree), when `run-self-tests.sh` finishes, then that child is dead. Proven in `test-run-self-tests.sh` with a new leg beside (T).
- [ ] AC18. The worker starts each test in its own process group (`set -m` around the `bash "$t" … &` fork, then `set +m` so no job-status lines are printed). On timeout it signals the whole group (TERM, then KILL after the existing 2 s) in addition to the existing descendant walk. **Group guard:** it signals `-$pid` ONLY when `ps -o pgid= -p "$pid"` (whitespace-trimmed) equals `$pid`, meaning the test leads its own group. Otherwise, including when `set -m` did not take effect, it signals no group and falls back to the descendant walk alone, so it can never signal the group of xargs or the runner. The live stderr report and the `.hang` file are unchanged, and so is `rc=124`. A TERM/INT/HUP delivered to the worker is forwarded to the running test's group, under the same guard, so a Ctrl-C or a CI cancel still reaches the tests. This forwarding has its own leg in `test-run-self-tests.sh`: TERM a running worker whose test leaves a double-forked child, then check that the test's group (child included) is gone.
- [ ] AC19. **Mutation control:** a copy of `run-self-tests.sh` with the `set -m` line deleted fails AC17's leg: the double-forked child survives. The same leg checks that the mutant runner itself exited normally (exit 1 with the TIMEOUT banner, not killed by a signal), which proves the group guard kept the runner's own group safe. The test builds that mutant itself (lesson-`fa32a308` gate) and kills the surviving child afterwards.

Release and evidence:
- [ ] AC20. Given the branch, when `bash scripts/check-version-bump.sh` runs, then it passes. The branch carries the fragment `changelog.d/af39e-proc-registry.md` (bump `minor`, a new script), folded by `bash scripts/bump-version.sh`.
- [ ] AC21. Given this machine after the change lands in the checkout, when `bash loomwright/scripts/proc-registry.sh list` runs, then a committed evidence file `docs/evidence/af39e-proc-registry-list.md` contains that output, plus one `ps -o pid=,lstart=,etime=,command= -p <pid>` line per row proving its class (home paths written as `~`, never `/Users/<name>/`), and the PR body links to it.

## House Rules

> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

(The caps table lives once, in `proc-registry.sh`. Launchers pass `--kind` and never restate a number, which honors the second rule.)

## File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| registry (S1) | `loomwright/docs/vendor-coupling-manifest.json` (only if the new file's literal vendor tokens need an allowance) | `loomwright/scripts/proc-registry.sh`, `loomwright/scripts/test-proc-registry.sh` | HIGH |
| launchers (S2) | `loomwright/scripts/automate-merge-watch.sh`, `loomwright/scripts/automate-next-step.sh`, `loomwright/scripts/test-automate-next-step.sh`, `loomwright/scripts/dispatch-pr-review.sh`, `loomwright/scripts/test-dispatch-pr-review.sh`, `loomwright/scripts/dispatch-pr-postmortem.sh`, `loomwright/scripts/test-dispatch-pr-postmortem.sh`, `loomwright/scripts/automate-lanes.d/launch.sh`, `loomwright/scripts/automate-lanes.d/phase.sh`, `loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh`, `loomwright/scripts/test-automate-lanes.d/06-phase-sessions.sh`, `loomwright/docs/vendor-coupling-manifest.json` (if counts rise) | `changelog.d/af39e-proc-registry.md`, `docs/evidence/af39e-proc-registry-list.md` | HIGH (launchers), MEDIUM (manifest) |
| watchdog (S3) | `loomwright/scripts/run-self-tests.sh`, `loomwright/scripts/test-run-self-tests.sh` | — | HIGH |

> **Validator-owned surfaces:** `scripts/check-vendor-coupling.sh` counts the literal vendor tokens declared in `loomwright/docs/vendor-coupling-manifest.json` per tracked file and fails CLOSED on a rise without a reasoned allowance. That manifest is in the map. Stage new files before measuring locally, because the gate scans `git ls-files` only. `test-no-fixed-sleep-race.sh` (a ratchet over every `test-*.sh` and `test-*.d/*.sh`) fails on a new fixed `sleep <n>` in a test, so new waits use `loomwright/scripts/wait-lib.sh`. `test-no-pipefail-grep-q.sh` fails on `producer | grep -q` in a test, so use `grep -q PAT < <(producer)`. Files scanned by `check-doc-currency.sh` should need no update: no count changes, because a script is not an agent, command or skill.

**Total estimated files:** 13 modify + 5 create.

## Touched-file invariants

> Grounded at base `7b7cb08392ce372c66c0694db7ced666fd0cbba9`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/automate-merge-watch.sh`** — keep: `# Always exits 0.`. Keep `unset CLAUDE_PID CLAUDECODE` (the closeout holder pin depends on it). Keep the single-instance marker write `( set -C; printf 'pid\t%s\npr_url\t%s\nstarted\t%s\n'` and `trap cleanup EXIT`. Register only AFTER that marker write succeeds (a losing launch prints `already running` and must not register), as a fail-safe call with `>/dev/null 2>&1` / `</dev/null` so it can never kill the watcher under `set -uo pipefail`. Keep the lifetime-cap read `max="${LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS:-259200}"` and pass that `$max` as the entry's cap. Reuse: `HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"` to locate `proc-registry.sh`. Mirror: the watcher's own rule "Count watchers by the marker pid (or `ps -o ppid` lineage), NEVER by `pgrep -f`". Pinned by: `test-automate-next-step.sh` (`leg_watch_note`), `test-session-resume.sh`, `test-automate-lanes.d/02-readiness-to-convert.sh`.
- **`loomwright/scripts/automate-next-step.sh`** — keep the `ns_watch` seam `NEXT_STEP_WATCH_CMD` and the default launch `nohup bash "$HERE/automate-merge-watch.sh" "$RF" "$ITEM" "$PR"`. `ns_watch` keeps ending `return 0`, so a watcher launch problem stays `ns_err` "reported" and never changes the emitted instruction. Pinned by: `test-automate-next-step.sh` (`NEXT_STEP_WATCH_CMD="$CASE_BIN/rec watch"`), `test-automate-helpers.sh`, `test-supervisor-next-step.sh`.
- **`loomwright/scripts/dispatch-pr-review.sh`** — keep: `INVARIANT: ALWAYS exits 0.`. The wrapper stays a `FULLY SINGLE-QUOTED string (no interpolation)` with runtime values passed as positionals. A new registry-path positional is appended AFTER `"$GUARD_SESSION_ID"` and captured into a named var on the first wrapper line (beside `_sid="${15}"`). Keep `ORDER INSIDE THE TRAP IS LOAD-BEARING (do NOT reorder)` (salvage → worktree removal → `rm -rf "$_lock"` LAST). Keep `if grep -q "REVIEW_HEAL_RESULT" "$_log"` as the sole DIED-vs-completed decision. The registration runs before `cd "$_wt" || exit 0` and the `"$_bin" -p` line, never inside `trap_cleanup`, and it is fail-safe (`|| true`, all stdio redirected). Keep the launch `( nohup bash -c "$WRAPPER" _ `. Fired by: the `PostToolUse[Bash]` `gh pr create` hook through `hook-dispatch-on-pr-create.sh` (`DISPATCHER="$SCRIPT_DIR/dispatch-pr-review.sh"`), and Supervisor Phase 4.5's completion tail. Registration runs inside the already-detached wrapper, so neither caller waits on it. Pinned by: `test-dispatch-pr-review.sh` (G2 real launch, the BLOCKING `.died` mutation control, §9 launch-form `nohup claude -p --agent`), `test-worktree-salvage.sh` (AC-7c/AC-7d lock-last), `test-hermetic-egress.sh`.
- **`loomwright/scripts/dispatch-pr-postmortem.sh`** — keep `Write the marker BEFORE launching` and the namespaced command in `( nohup "$CLAUDE_BIN" -p "/loomwright:pr-postmortem $PR_URL" >>"$RUN_LOG" 2>&1 </dev/null & )`. The registration goes INSIDE that subshell after the `&` (`--pid $!`), fully redirected, and itself backgrounded (`… register … </dev/null >/dev/null 2>&1 &`), so its bounded `--expect` wait (AC2, about 2.5 s) never blocks the dispatcher. The trailing `>/dev/null 2>&1 || true` stays. Fired by: `review-heal-next-step.sh`'s `rh_postmortem_call` (the review-heal driver), which keeps returning immediately. Because the registration is asynchronous, AC13's test waits for the entry with `wait-lib.sh`. Keep the DRY_RUN printf `DRY_RUN_DISPATCH: %s -p "/loomwright:pr-postmortem %s"` (DRY_RUN never registers, since nothing launches). Reuse: `CLAUDE_BIN="${LOOMWRIGHT_CLAUDE_BIN:-claude}"` as the stub seam. Pinned by: `test-dispatch-pr-postmortem.sh` (`DRY_RUN_DISPATCH` + `marker_count`), `test-retention-sweep.sh`.
- **`loomwright/scripts/automate-lanes.d/launch.sh`** — keep `# >>> spawn (the only process start; it writes nothing into the lane directory)`. The registry write goes to the user-scope registry only, never into `$LN_DIR` (test I1's `lane_sum` checksum). Register after the `while [ "$i" -lt 25 ] && kill -0 "$pid" … ! lanes_proc_alive` loop and before `_lanes_await_init`. Reuse `lanes_proc_alive` (Q11 pins "one lanes_proc_alive") and `st` (the already-read lstart), never a second liveness helper. Keep `_lanes_launch_unlock` unchanged. Keep the module ≤ 800 lines (`test-automate-lanes-modules.sh` check 2). The bundled single-file copy that `test-automate-lanes.sh` builds must still resolve `proc-registry.sh` via the scripts dir, not `automate-lanes.d/`. Pinned by: `test-automate-lanes.d/01-create-to-wait.sh` (`/# >>> spawn/` awk mutant, I1/I2), `test-automate-lanes-modules.sh` (MODS list, line cap, verbatim-move proof pinned to SPLIT_SHA, unaffected by later edits).
- **`loomwright/scripts/automate-lanes.d/phase.sh`** — keep `# >>> phase spawn (the only process start of this module)` and the pid file `printf '%s\t%s\n' "$pid" "$st" > "$PH_DIR/pid"`. Register after the `_lanes_phase_alive` wait loop. Reuse `PH_PHASE`, `PH_RUN`, `PH_CO` for the entry fields. Keep the module ≤ 800 lines. Pinned by: `test-automate-lanes.d/06-phase-sessions.sh` (AN legs, `claude_calls` counts: registration must not invoke the stub claude).
- **`loomwright/scripts/run-self-tests.sh`** — keep the header's no-`|| true` rule (`anywhere on the gate path`; outside the worker heredoc). Keep the worker contract: it `ALWAYS exits 0 so xargs keeps scheduling`, the verdict file is written LAST via `mv "$SELF_TEST_OUT/$idx.rc.tmp" "$SELF_TEST_OUT/$idx.rc"`, and a timeout is `rc=124`. Keep the live report `run-self-tests: TIMEOUT after ${limit}s: $t — still running; process tree:` and the `descendants` walk, which still names the tree. Keep the `<<'WORKER'` quoted heredoc (no interpolation). bash 3.2: `set -m` works in a non-interactive script (no `setsid` on macOS). Pinned by: `test-run-self-tests.sh` legs (T)/(TJ)/(H)/(S), `test-ci-slot.sh`, `test-hermetic-egress.sh`, `test-suite-helpers-defined.sh`.
- **`loomwright/scripts/test-run-self-tests.sh`, `test-automate-next-step.sh`, `test-dispatch-pr-review.sh`, `test-dispatch-pr-postmortem.sh`, `test-automate-lanes.d/01-create-to-wait.sh`, `test-automate-lanes.d/06-phase-sessions.sh`** — keep each file's existing legs green and unedited in meaning. New waits use `wait-lib.sh` (the `test-no-fixed-sleep-race.sh` ratchet). No `| grep -q` under pipefail (`test-no-pipefail-grep-q.sh`). Each test exports its own `LOOMWRIGHT_PROC_REGISTRY_DIR` temp dir so a standalone run never touches the real home.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-proc-registry.sh` — recycled pid ⇒ `finished`, never killed (AC7) | delete the line in `loomwright/scripts/proc-registry.sh` that compares the live command-line hash with the entry's `cmd_hash` (the test builds this mutant itself) |
| `loomwright/scripts/test-proc-registry.sh` — reap dry run changes nothing (AC5) | delete the `--apply` check in `loomwright/scripts/proc-registry.sh` so `reap` always acts |
| `loomwright/scripts/test-proc-registry.sh` — orphaned on `## Status: done` (AC4) | delete the run-file `## Status:` read in `loomwright/scripts/proc-registry.sh` |
| `loomwright/scripts/test-proc-registry.sh` — overdue past `max_lifetime_s` (AC4) | flip the age comparison in `loomwright/scripts/proc-registry.sh` (`-gt` → `-lt`) |
| `loomwright/scripts/test-proc-registry.sh` — hermetic redirect (AC8) | delete the `HERMETIC_TEST_ENV` branch of the registry-dir resolver in `loomwright/scripts/proc-registry.sh` |
| `loomwright/scripts/test-proc-registry.sh` — empty `HERMETIC_SHIM_DIR` ⇒ no write anywhere (AC8) | delete the empty/not-a-directory check on `HERMETIC_SHIM_DIR` in `loomwright/scripts/proc-registry.sh` (the leg then finds a write under `/procs` attempted, or a `register failed` line missing) |
| `loomwright/scripts/test-proc-registry.sh` — registering one process twice ⇒ one entry (AC1) | derive the entry id from the pid alone (drop the start time) in `loomwright/scripts/proc-registry.sh` (the leg's "a recycled-pid re-register is a NEW entry" half goes red), or append a timestamp to the id (two files) |
| `loomwright/scripts/test-proc-registry.sh` — register always exits 0 with one stderr line (AC3) | change the failure path's `exit 0` to `exit 1` in `loomwright/scripts/proc-registry.sh` |
| `loomwright/scripts/test-proc-registry.sh` — re-check before KILL (AC6) | delete the lstart + command-line re-check that precedes the KILL in `loomwright/scripts/proc-registry.sh` (fixture: a TERM-ignoring process that `exec`s a different command during the grace; the leg sees it KILLed) |
| `loomwright/scripts/test-proc-registry.sh` — `running` entries are never signalled, `finished` pruned, one `reap.log` line per process (AC6) | widen the reap class filter to every class in `loomwright/scripts/proc-registry.sh` (the running fixture dies) |
| one launcher test, e.g. `loomwright/scripts/test-dispatch-pr-postmortem.sh` — a failing registry still launches with unchanged exit/stdout (AC16) | remove the stdio redirect and fail-safe guard from that launcher's registration call, and make `proc-registry.sh` exit 1 (the leg sees changed stdout or a non-zero exit) |
| `loomwright/scripts/test-automate-next-step.sh` — default `ns_watch` registers the watcher (AC10/AC11) | delete the one registration call line in `loomwright/scripts/automate-merge-watch.sh` |
| `loomwright/scripts/test-dispatch-pr-review.sh` — real launch registers a `drain` entry (AC12) | delete the one registration call line inside `WRAPPER` in `loomwright/scripts/dispatch-pr-review.sh` |
| `loomwright/scripts/test-dispatch-pr-postmortem.sh` — real launch registers a `postmortem` entry (AC13) | delete the one registration call line in `loomwright/scripts/dispatch-pr-postmortem.sh` |
| `loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh` — lane launch registers a `lane` entry (AC14) | delete the one registration call line in `loomwright/scripts/automate-lanes.d/launch.sh` |
| `loomwright/scripts/test-automate-lanes.d/06-phase-sessions.sh` — phase launch registers a `phase` entry (AC15) | delete the one registration call line in `loomwright/scripts/automate-lanes.d/phase.sh` |
| `loomwright/scripts/test-run-self-tests.sh` — double-forked child of a timed-out test dies (AC17/AC19) | delete `set -m` in `loomwright/scripts/run-self-tests.sh` |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | `proc-registry.sh` register / list / reap + `test-proc-registry.sh` | AC1–AC9 | 0–1 modify, 2 create | `skills/error-handling/SKILL.md`, `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 2 | Register every launcher (merge watcher, next-step, review drain, postmortem, lane, phase) + tests + fragment + evidence | AC10–AC16, AC20, AC21 | 11–12 modify, 2 create | `skills/unit-testing/SKILL.md`, `skills/async-orchestration/SKILL.md` | BLOCKED (by #1) |
| 3 | `run-self-tests.sh` watchdog stops the timed-out test's process group + fixture + mutation control | AC17–AC19 | 2 modify, 0 create | `skills/unit-testing/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/proc-registry.sh"}
  - {kind: "file", path: "loomwright/scripts/test-proc-registry.sh"}
requires: []
lanes:
  - "loomwright/scripts/proc-registry.sh"
  - "loomwright/scripts/test-proc-registry.sh"
  - "loomwright/docs/vendor-coupling-manifest.json"
external_requires:
  - "jq on PATH (already a plugin-wide dependency)"
  - "ps -o lstart= and ps -ww -o command= (BSD and procps)"
```

```yaml
# Subtask 2
provides:
  - {kind: "file", path: "docs/evidence/af39e-proc-registry-list.md"}
requires:
  - {from: "1", kind: "file", path: "loomwright/scripts/proc-registry.sh"}
lanes:
  - "loomwright/scripts/automate-merge-watch.sh"
  - "loomwright/scripts/automate-next-step.sh"
  - "loomwright/scripts/test-automate-next-step.sh"
  - "loomwright/scripts/dispatch-pr-review.sh"
  - "loomwright/scripts/test-dispatch-pr-review.sh"
  - "loomwright/scripts/dispatch-pr-postmortem.sh"
  - "loomwright/scripts/test-dispatch-pr-postmortem.sh"
  - "loomwright/scripts/automate-lanes.d/launch.sh"
  - "loomwright/scripts/automate-lanes.d/phase.sh"
  - "loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh"
  - "loomwright/scripts/test-automate-lanes.d/06-phase-sessions.sh"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "changelog.d/af39e-proc-registry.md"
  - "docs/evidence/af39e-proc-registry-list.md"
external_requires:
  - "a stub claude on PATH / LOOMWRIGHT_CLAUDE_BIN in every launcher test (no real claude)"
```

```yaml
# Subtask 3
provides:
  - {kind: "symbol", path: "loomwright/scripts/run-self-tests.sh", name: "set -m"}
requires: []
lanes:
  - "loomwright/scripts/run-self-tests.sh"
  - "loomwright/scripts/test-run-self-tests.sh"
external_requires:
  - "bash job control (set -m) in a non-interactive script — bash 3.2 and 5.x"
```

(Subtask 2's changelog fragment is not a `provides` entry: `bump-version.sh` folds and deletes it, so it would not exist on disk afterwards.)

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2
Subtask 3 (independent)
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | `loomwright/docs/vendor-coupling-manifest.json` | YES (already ordered: 2 requires 1, so the shared lane is legal) |
| Subtask 1 | Subtask 3 | none | NO |
| Subtask 2 | Subtask 3 | none | NO |

### Batch Plan
- **Batch 1:** Subtask 1, Subtask 3 (parallel — empty `requires`, zero file overlap)
- **Batch 2:** Subtask 2 (after Subtask 1 — calls `proc-registry.sh register`)
- **Recommended workers:** 2
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/error-handling/SKILL.md`, `skills/unit-testing/SKILL.md` |
| 2 | `skills/unit-testing/SKILL.md`, `skills/async-orchestration/SKILL.md` |
| 3 | `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): existing tests that really launch a watcher, drain or lane (`test-automate-trail.sh`, `test-worktree-salvage.sh`, the lanes suite) would write entries to the real `~/.claude/loomwright/procs/` once launchers register. | HIGH | AC8's hermetic redirect: under `HERMETIC_TEST_ENV=1` with no explicit dir, the registry lives in `$HERMETIC_SHIM_DIR/procs`. Every touched test also sets its own `LOOMWRIGHT_PROC_REGISTRY_DIR`. Known limit: an UNtouched test run standalone (outside `run-self-tests.sh`/`ci-local.sh`) can still register into the real home. List it in the header comment; 39g's leak gate is the backstop. |
| Feasibility (Phase 2.5): scope is over one worker's context (`context-bound`). | HIGH | 3 subtasks. S1's header comment is the interface S2 codes against. S2 reads it, never S1's internals. |
| Registration racing `nohup`'s exec reads the launcher's own command line, so a correct process is later classified `finished` (recycled). | MEDIUM | Fails safe (never killed, just shown `finished`). `--expect <substring>` (AC2) waits for the exec. Lanes and phases register after their existing liveness loops. The drain registers from inside its wrapper as `$$`. |
| Subtask 2 alone is 13–14 files (six launchers plus their tests), itself over the `context-bound` file bound. | MEDIUM | Accepted: each launcher edit is a small call (about 5–15 lines) plus one test leg, about 400 changed lines, well under the 800-line bound. The worker does the launchers one at a time and runs each launcher's test before moving on. If the worker's context runs short, Phase 4.5 can split off the two lanes modules (`launch.sh`, `phase.sh` and their two tests); their lanes do not overlap the others except the manifest. |
| `set -m` changes signal delivery: tests in their own process group no longer get a terminal Ctrl-C / CI cancel. | MEDIUM | AC18: the worker forwards TERM/INT/HUP to the test's group. `set +m` right after the fork suppresses job-status lines. The existing (T)/(S)/(H) legs stay green. |
| A registration error kills a launcher (`set -euo pipefail` in a caller, an unbound var). | MEDIUM | `register` always exits 0 (AC3). Every call is fully redirected and fail-safe. AC16 proves a failing registry still launches with unchanged output. |
| `check-vendor-coupling.sh` fails CLOSED on new literal vendor tokens (e.g. `.claude/` in the default path, a session-id variable). | MEDIUM | Measure with the gate after `git add`. Add a reasoned allowance entry in `vendor-coupling-manifest.json` only for tokens that genuinely remain. |
| `reap` signals the wrong process. | HIGH | It re-checks lstart and command-line hash immediately before EACH signal, never signals by pid alone, never touches unregistered pids, dry run is the default (AC5–AC7), and the recycled-pid mutation control is in the test. |
| Evidence file leaks a home path or a token. | LOW | AC21 writes home paths as `~`. The `list` output holds no secrets (a hash, not the raw command line). |

## Configuration
- **Workers:** 2
- **Mode:** parallel
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-22-af39e-proc-registry-and-reap.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-10-23T17:33:46Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/679
- **Branch:** feature/af39e-proc-registry-and-reap
- **Files changed:** 21
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 3
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** proc-registry.sh register/list/reap plus registration in every detached launcher, and the run-self-tests process-group watchdog. Resumed Phase 4.5 after session ce667b79 died (ENOTFOUND); three fix rounds (5d1bd7a, 592c5f7, dc6d556 + re-fold b3cfdc4). Escalated: iteration 3's findings (drain wrapper grace vs teardown; AC16 one-line-per-launcher vs AC6) were fixed in the final round but not re-reviewed, and the branch CONFLICTS with origin/main (#678) in loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh. That conflict is left for a human; it was never force-resolved.

## Not verified
- **Linux bash5/procps CI** — not run locally (subtask 3)
- **real tty Ctrl-C / Actions cancel** — not exercised (subtask 3)
- **Linux/procps** — not run locally (subtask 1)
- **reap TERM-failed/KILL-failed/survived-KILL branches** — not exercised (subtask 1)
- **launchers with real claude** — stub claude only (subtask 2)
- **PR body evidence link (FINALIZE)** — not checked by the worker (subtask 2)
