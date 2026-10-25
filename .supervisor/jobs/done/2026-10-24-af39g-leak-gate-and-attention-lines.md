# Supervisor Job: af/39g — a suite that leaves a process behind fails ci-local, and the owner hears about stray processes at session start and run end

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-22-123646/L7
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/automate-followups/39g-leak-gate-and-attention-lines.md
- **Base commit:** 237adab3f71e30ac817b34b9fb630e50e9661cb2

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 / BSD userland scripts + jq + `ps`; `lsof` is present on macOS (`/usr/sbin/lsof`) and on the GitHub Ubuntu runners |
| 2 | Dependency Availability | GO | The dependency 39e (`loomwright/scripts/proc-registry.sh` with `register` / `list` / `reap`) is merged on `main`; no new library |
| 3 | Architecture Fit | GO | The SessionStart line goes into the existing `session-resume.sh` (no new `hooks.json` leaf), and the run-end lines go through `progress-append` beside the existing sweep lines |
| 4 | Scope vs Supervisor Capability | CAUTION | About 21 files across 4 coherent groups, over the context-bound bound, so the work splits (`Split reason: context-bound`) |
| 5 | Hard Blockers | CAUTION | (a) 39e's registry has no single-`ps` summary and no `unregistered` look-alike scan, so a `summary` subcommand is added to `proc-registry.sh` (outside the requirement's Touches list). (b) `/janitor` (39f) is not merged, so the attention line cannot point at it |

**Overall Verdict:** CAUTION

## Task
**Goal:** `scripts/ci-local.sh` fails when a suite leaves a new process behind that belongs to this run. SessionStart prints one attention line when the process registry has anything `overdue` / `orphaned` / `unregistered`. `/automate`'s done exit and fleet close-out each append one registry-summary line to `## Progress`. All three read one new `proc-registry.sh summary` subcommand, which makes a single `ps` snapshot.

**Problem Statement:**
The owner needs stray background processes surfaced without having to run `ps` by hand, because the plugin has leaked processes before: 3 Floor fixture servers in 2026-10-04's inventory, 20 orphaned fixture servers on 2026-10-02, and a 2-day-old merge watcher running old plugin code.
Currently `scripts/ci-local.sh` takes no before/after process snapshot. Nothing at SessionStart or run end mentions overdue or orphaned processes; `lane-status --leaks` reports wave leaks only at fleet close-out. Fixture servers still exist after the Floor removal (98da6ae): `test-verify-walkthrough.sh` and `test-verify-seam.sh` start `verify-fixture-app.py` HTTP servers that only an EXIT trap stops, and a watchdog KILL skips that trap.
Success looks like this: a deliberately leaking fixture turns `ci-local` red, a fixture registry with one `orphaned` entry produces exactly one SessionStart line, and a run reaching `## Status: done` gains one registry-summary Progress line. The owner confirmed the leak gate is still worth its cost (Launch Pad Phase 2, 2026-10-24: "Keep the gate").

## Acceptance Criteria
- [ ] AC1 — Given a registry fixture (`LOOMWRIGHT_PROC_REGISTRY_DIR`) and a `ps` snapshot fixture (new test seam `LOOMWRIGHT_PROC_PS_SNAPSHOT=<file>`, read in place of running `ps`), when `bash loomwright/scripts/proc-registry.sh summary` runs, then it prints exactly ONE line of the form `proc-registry: summary — <E> entries: <r> running, <o> overdue, <a> orphaned, <f> finished` and exits 0. Classification uses the same CLASSES precedence `list` documents (finished → overdue → orphaned → running; a recycled pid with a different lstart or command-line hash is `finished`). It makes at most ONE `ps` call however many entries exist, proven by a PATH-stub `ps` that counts its calls (3 entries ⇒ 1 call; 0 entries ⇒ 0 calls). An empty or missing registry prints `proc-registry: summary — 0 entries: 0 running, 0 overdue, 0 orphaned, 0 finished`. An unavailable registry (an unreadable dir, or the hermetic redirect with no shim dir) prints `proc-registry: summary — unavailable` and exits 0.
- [ ] AC2 — Given `proc-registry.sh summary --scan`, when the same single snapshot contains UNREGISTERED processes that look like the plugin's (a command line containing `/loomwright/scripts/`, or a `python*` command whose script path lies in a temp dir and no longer exists), older than `LOOMWRIGHT_PROC_UNREG_MIN_S` (default 3600 s), not a registered pid and not the caller's own process or its ancestors, then the line gains `; <u> unregistered`. Under `HERMETIC_TEST_ENV=1` with no `LOOMWRIGHT_PROC_PS_SNAPSHOT`, the scan is skipped (`u` = 0), mirroring the registry's HERMETIC REDIRECT, so no other suite reads the live machine. `summary` never sends a signal and never writes a file (a checksum of the registry dir is unchanged).
- [ ] AC3 — Given a fixture registry with one `orphaned` entry, when `session-resume.sh` runs on `startup` and on `resume`, then the output carries exactly ONE line `**Background processes:** <n> item(s) need attention (<o> overdue, <a> orphaned, <u> unregistered) — inspect with \`proc-registry.sh list\`; stop registered ones with \`proc-registry.sh reap\` (dry run first)`. With nothing overdue, orphaned or unregistered there is no line, and a startup with nothing else to say stays byte-identical (empty output). With an unreadable registry there is no line and exit 0. The hook reaches the registry only through `proc-registry.sh summary --scan` (one `ps` call, no network). No new `hooks.json` leaf is added.
- [ ] AC4 — Given a run reaching `## Status: done` by EITHER done exit — `automate-next-step.sh`'s `terminate` step, or `finalize-empty` (`loomwright/scripts/automate-trail.d/finalize.sh`, a run `closeout` finished) — (fixtures), when it terminates, then `## Progress` gains exactly ONE `<ts> process registry: <summary line>` line immediately BEFORE that exit's `sweep (dry run)` line (through `ns_progress` in the driver, through `progress-append` in finalize.sh). When `summary` prints nothing, the line reads `process registry: proc-registry: summary — skipped: no output`. `process registry` and `fleet closeout registry` join the driver's `NS_RESERVED_PREFIXES` and the `progress_note` reserved-prefix list in `loomwright/docs/result-schemas/automate-run.md`, so a model `progress_note` cannot forge either line (R12 in `test-automate-next-step.sh` stays green). The golden case `termination-queue-resolved` (`steps`, `expected.out`, `expected.md`), the per-item-loop prose and the `automate-trail.sh` / finalize.sh headers state the same line, so G golden parity and `test-automate-trail.d/05-finalize-closeout-others.sh` F1 stay green.
- [ ] AC5 — Given a parent run finalized by `fleet-closeout` (`automate-lanes.d/wave.sh` `_lanes_fc_finalize`), when the finalize runs, then `## Progress` gains exactly ONE `fleet closeout registry: <summary line>` line immediately BEFORE the `fleet closeout sweep (dry run)` line. The sweep line stays the run file's last line (AF14c), and a re-run on a done parent records no second registry line.
- [ ] AC6 — Given a fixture repo whose suite contains a deliberately leaking test, when `bash scripts/ci-local.sh --force` runs, then the run prints `ci-local: leak gate — survivor pid=<p> <command>` for each survivor and the verdict `ci-local: FAIL after <N>s — leak gate: <K> process(es) survived the suite (nothing cached)`, exits 1, and leaves no PASS stamp. Two leaking shapes each get their own leg, and both must FAIL:
  - (i) **the real leaker's shape**: a detached `python3 <script OUTSIDE the run's temp dir> --port <N>` listener whose launching test exits 0, mirroring `start_app()` in `test-verify-walkthrough.sh` (`python3 "$FIXTURE_APP" --port "$port" … &`);
  - (ii) **a detached grandchild**: a script runs `nohup sleep <N> >/dev/null 2>&1 &` and exits, so the survivor's command line is only `sleep <N>`.

  **Attribution is by an inherited marker, not by path.** Before the early phase, ci-local exports `LOOMWRIGHT_CI_LOCAL_RUN=<unique run id>`, which the runner and every descendant inherit. A survivor is a process that is all of:
  - absent from the before-snapshot (pid + lstart);
  - owned by this user;
  - still alive after a bounded settle poll (`CI_LOCAL_LEAK_SETTLE`, default 5 s, polling on the condition, never a fixed sleep);
  - carrying `LOOMWRIGHT_CI_LOCAL_RUN=<this run's id>` in its environment.

  The environment comes from ONE env-showing snapshot: `ps -axE -ww -o pid=,lstart=,command=` on BSD/macOS (probed 2026-10-24: a `nohup sleep` grandchild's inherited variable is visible), and `ps axeww`-style or `/proc/<pid>/environ` on Linux. Pick the form by a feature probe, never by `uname` alone.

  New listeners (`lsof -nP -iTCP -sTCP:LISTEN`) are attributed the same way. A new listener WITHOUT this run's marker prints `ci-local: leak gate — note: new listener pid=<p> not attributable to this run (not failed)`, and a leg proves that a concurrent unrelated listener started during the run does not fail it.

  Other required lines and legs:
  - The same fixture without a leak passes and prints `ci-local: leak gate — clean (0 new processes survived)`.
  - With `lsof` absent, the listener half prints `ci-local: leak gate — listeners unchecked (lsof absent)` and the process half still runs.
  - A failing snapshot fails CLOSED: `ci-local: FAIL … — leak gate: ps snapshot failed (nothing cached)`.

  The ci-local header states the honest limits: a process that scrubs its environment (`env -i`, or a daemon that clears it), another user's process, and a platform whose `ps` cannot show the environment. On such a platform the gate prints `ci-local: leak gate — unverifiable (ps cannot show the environment)` and does not FAIL; that is the one documented fail-open case, and a leg pins its wording.

  The gate only reports. It never signals a survivor, and each test leg kills its own leaked processes in its cleanup.
- [ ] AC7 — Given the integrated branch (Subtasks 1, 2 and 4 already merged into the run's branch — Subtask 3 runs last), then a committed evidence file `docs/evidence/af39g-leak-gate-and-attention-lines.md` contains the leak-gate line from one real `bash scripts/ci-local.sh` run on the branch, the attention line or its absence from one fresh `session-resume.sh` startup on this machine (with the `proc-registry.sh summary --scan` line it was derived from), and each AC6 / AC3 mutation control's red output. The PR body links to it.
- [ ] AC8 — `bash scripts/check-version-bump.sh` passes with the `changelog.d/af39g-leak-gate-and-attention-lines.md` fragment, and `loomwright/docs/HOOKS.md`'s SessionStart row plus `session-resume.sh`'s header (the startup-arm block enumeration) name the new line in the same change. `check-doc-currency.sh`, `test-citation-drift.sh` and `test-no-fixed-sleep-race.sh` are green.

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

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| registry-summary | `loomwright/scripts/proc-registry.sh`, `loomwright/scripts/test-proc-registry.sh` | — | HIGH |
| leak-gate | `scripts/ci-local.sh`, `scripts/test-ci-local.sh` | — | HIGH |
| session-start | `loomwright/scripts/session-resume.sh`, `loomwright/scripts/test-session-resume.sh`, `loomwright/docs/HOOKS.md` | `changelog.d/af39g-leak-gate-and-attention-lines.md`, `docs/evidence/af39g-leak-gate-and-attention-lines.md` | HIGH |
| run-end | `loomwright/scripts/automate-next-step.sh`, `loomwright/scripts/test-automate-next-step.sh`, `loomwright/scripts/automate-lanes.d/wave.sh`, `loomwright/scripts/test-automate-lanes.d/04-fleet-closeout-to-optout.sh`, `loomwright/skills/automate-loop/per-item-loop.md`, `loomwright/scripts/fixtures/automate-golden/termination-queue-resolved/steps`, `loomwright/scripts/fixtures/automate-golden/termination-queue-resolved/expected.out`, `loomwright/scripts/fixtures/automate-golden/termination-queue-resolved/expected.md`, `loomwright/scripts/automate-trail.d/finalize.sh`, `loomwright/scripts/automate-trail.sh`, `loomwright/scripts/test-automate-trail.d/05-finalize-closeout-others.sh`, `loomwright/docs/result-schemas/automate-run.md` | — | HIGH (the golden trio: MEDIUM, since `next-step.results` may also need a line) |

> **Validator-owned surfaces:** `check-doc-currency.sh` scans `loomwright/docs/HOOKS.md` and the skills dir, and `check-token-budget.sh` measures `loomwright/skills/automate-loop/` (per-item-loop.md grows by about one clause; its `.skills["automate-loop"]` budget has around 4.4k tokens of headroom). `test-citation-drift.sh` scans committed prose for bare `file:N` citations, so write descriptive anchors. `check-vendor-coupling.sh` reads `loomwright/docs/vendor-coupling-manifest.json`, which holds per-file coupling-token counts (`proc-registry.sh`, `test-proc-registry.sh`, `session-resume.sh` among them). If new code names a counted harness identifier, re-measure, update that file's row, and add the manifest to the owning subtask's lanes.

**Total estimated files:** 19 modify + 2 create

## Touched-file invariants

> Grounded at base `237adab3f71e30ac817b34b9fb630e50e9661cb2`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/proc-registry.sh`** — keep: the header is the contract and no other doc restates it; the new `summary` subcommand is documented there under SUBCOMMANDS beside `list`. Keep the read-only signal rule `NEVER SIGNAL BY PID ALONE` (summary sends nothing), and keep exit codes per the header line `EXIT CODES: register 0 always; list 0 always` (summary: 0 always, usage error 2). Keep the registry resolution order including `HERMETIC REDIRECT` (an unavailable registry ⇒ `unavailable`, never a fallback to `$HOME`). Reuse: the lstart pin `env TZ=UTC0 LC_ALL=C ps -o lstart= -p` (the snapshot's lstart column must be read with the SAME TZ/locale pin, or every entry reads `finished`), plus the existing hash and class helpers, so `summary` and `list` cannot classify differently. Mirror: the dispatch arm `list) cmd_list "$@"; exit 0 ;;` gains a sibling `summary)` arm, and `pr_usage` lists it. Pinned by: `loomwright/scripts/test-proc-registry.sh` (`check() {` harness, its AC legs).
- **`scripts/ci-local.sh`** — keep: a failing verdict removes the stamp (`rm -f "$stamp"`) and says `(nothing cached)` like `see the FAIL banners above (nothing cached)`; a finished log ends with its verdict line (header RUN LOGS: `A finished log ends with its verdict line`), so the leak-gate lines print BEFORE the verdict assignment; INT/TERM traps (`trap 'exit 130' INT`) still leave the log verdict-less (INCOMPLETE). Reuse: the per-run scratch dir `tmpd="$(mktemp -d "${TMPDIR:-/tmp}/ci-local.XXXXXX")"` for the gate's snapshot files (the run id in `LOOMWRIGHT_CI_LOCAL_RUN` may derive from its basename; `TMPDIR` itself is NOT changed); the gate wraps both pool invocations — the full run's early + `bash "$runner" "${pplan[@]}" || rc=$?` and the `--affected` runner call; the cached-PASS exits never run it. bash 3.2: no `timeout`, no empty-array expansion under `set -u`. Pinned by: `scripts/test-ci-local.sh` (`^ci-local: PASS after .* stamped` and the (P)/(B)/(PG) legs, which must stay green with the gate on).
- **`loomwright/scripts/session-resume.sh`** — keep: fail-SAFE, always exit 0; fired by the `SessionStart` leaf in `loomwright/hooks/hooks.json` (`scripts/session-resume.sh\" || true`, unchanged). The startup arm composes ONE envelope (`JOIN RULE (bash 3.2-portable)`), and `When no block has anything to say, startup emits NOTHING` — the new line joins `startup_arm_emit` the same way `automate_watch_lines` does, and on resume/clear/compact it rides next to `WATCH_SR="$(automate_watch_lines 2>/dev/null)"` (own line, no new section heading needed). Update the header's `composes at most FIVE advisory blocks into ONE envelope` enumeration (closed list — see below). Startup stays offline (no `gh`, no `curl`). Pinned by: `loomwright/scripts/test-session-resume.sh` (sources `hermetic-test-env.sh`; its startup cmp-equal legs) and seven other suites that run the hook (`test-host-mode.sh`, `test-reconcile-jobs.sh`, `test-rules-seams.sh`, `test-read-rules.sh`, `test-session-probe.sh`, `test-citation-drift.sh`, `test-no-fixed-sleep-race.sh`) — they stay green because `--scan` is skipped under `HERMETIC_TEST_ENV=1` without the snapshot seam (AC2).
- **`loomwright/scripts/automate-next-step.sh`** — keep: the run file is written only through the helper writers (`The run file is written ONLY through automate-helpers.sh`), so the new line goes through `ns_progress`, placed directly before `ns_progress "$(ns_ts) sweep (dry run): ${sw:-sweep: summary — skipped: no output}" || return 1`, with the same `|| return 1` writer-failure path and before `ns_release`. Mirror: the golden `termination-queue-resolved` `steps` file mirrors the prose loop line-for-line (`sweep (dry run): $(grep` …), so the golden trio and `skills/automate-loop/per-item-loop.md` (`then appends ONE \`<ts> sweep (dry run): <summary line>\` line`) change in the same subtask. Pinned by: `loomwright/scripts/test-automate-next-step.sh` (G golden parity; exports `LOOMWRIGHT_PROC_REGISTRY_DIR="$WORK/procs"`) and `test-automate-golden.sh`.
- **`loomwright/scripts/automate-lanes.d/wave.sh`** — keep: `_lanes_fc_finalize` returns 0 and swallows writer output (`progress-append "$rf" "fleet closeout sweep (dry run): $sw"` … `>/dev/null 2>&1`, with a stderr WARNING on failure); the sweep line stays LAST — pinned by `loomwright/scripts/test-automate-lanes.d/04-fleet-closeout-to-optout.sh` AF14c (`as the run file's last line`), and re-runs on a done parent write nothing (AF14d). Update the header comment's line enumeration for the finalize (`then ONE \`fleet closeout sweep (dry run): <sweep summary>\` line`).
- **`loomwright/scripts/automate-trail.d/finalize.sh`** (+ `loomwright/scripts/automate-trail.sh` header) — keep: the finalize-empty done exit appends its sweep line AFTER the trail line and outside the staged runfile rewrite (`progress-append "$rf_rel" "$ts sweep (dry run): $sw" >/dev/null 2>&1`, run in a subshell so it cannot move cwd or touch the EXIT trap); the registry line goes immediately before it in the same fail-safe form. Update finalize.sh's header (`ONE \`<ts> sweep (dry run): <summary>\``) and the automate-trail.sh header (`\`<ts> sweep (dry run): <summary>\` Progress line`). Pinned by: `loomwright/scripts/test-automate-trail.d/05-finalize-closeout-others.sh` F1 (`finalize-empty appends exactly ONE '<ts> sweep (dry run)`).
- **`loomwright/docs/result-schemas/automate-run.md`** — the `progress_note` reserved-prefix list mirrors the driver's `NS_RESERVED_PREFIXES` (anchor: `` `sweep (dry run)`, `closeout`, `fleet closeout:` ``); R12 in `test-automate-next-step.sh` fails when the doc misses a reserved prefix, so the two change together.
- **`loomwright/docs/HOOKS.md`** — the SessionStart row (`since automate-followups/32 it also surfaces`) gains the background-process line in the same change (house rule: restating copy updated with its authority).

## Closed enumerations touched

> Sibling grep at base `237adab3f71e30ac817b34b9fb630e50e9661cb2`: `grep -rnF 'proc-registry.sh list' --exclude=CHANGELOG.md --exclude-dir=.git --exclude-dir=.supervisor .` → 3 hits in 2 files.

- **`summary`** (sibling: `list`) — must be named in:
  - `loomwright/scripts/proc-registry.sh` — the usage block (`proc-registry.sh list` in `pr_usage`), the header SUBCOMMANDS list, and the dispatch `case` (`list) cmd_list "$@"; exit 0 ;;`) — extend all three.
  - `docs/evidence/af39e-proc-registry-list.md` (2 hits) — a frozen evidence record of 39e's run — no change: historical evidence, not a closed list.
- **Startup-arm block #6, the background-process line** (sibling: `automate_watch_lines`) — `grep -rnF 'automate_watch_lines'` hits only `loomwright/scripts/session-resume.sh`:
  - `loomwright/scripts/session-resume.sh` — header enumeration `composes at most FIVE advisory blocks into ONE envelope` + items 1–5, and `startup_arm_emit`'s join list — extend (SIX, item 6).
  - `loomwright/docs/HOOKS.md` SessionStart row — extend (see invariants).
- **Done-exit Progress line `process registry:`** (sibling: `sweep (dry run)`). Sibling grep at base: `grep -rnF 'sweep (dry run)' --exclude=CHANGELOG.md --exclude-dir=.git --exclude-dir=.supervisor loomwright scripts`. It finds the three writers (driver `terminate`, `finalize-empty`, `fleet-closeout`), their headers and tests, the reserved-prefix list, the prose, the goldens and `supervisor-result.md` fixture text:
  - `loomwright/skills/automate-loop/per-item-loop.md` — the done-exit sentence — extend.
  - `loomwright/scripts/automate-next-step.sh` `ns_terminate` — extend; and `NS_RESERVED_PREFIXES` (its `sweep (dry run)` row) — extend with `process registry` and `fleet closeout registry`.
  - `loomwright/docs/result-schemas/automate-run.md` — the `progress_note` reserved-prefix list (`` `sweep (dry run)`, `closeout`, `fleet closeout:` ``) — extend with the same two (R12 pins doc ⇔ driver).
  - `loomwright/scripts/automate-trail.d/finalize.sh` (finalize-empty's `progress-append "$rf_rel" "$ts sweep (dry run): $sw"` and its header), `loomwright/scripts/automate-trail.sh` header — extend (the second `## Status: done` exit).
  - `loomwright/scripts/test-automate-trail.d/05-finalize-closeout-others.sh` F1 — extend (a leg pins the one registry line before the sweep line).
  - `loomwright/scripts/fixtures/automate-golden/termination-queue-resolved/{steps,expected.out,expected.md}` — extend.
  - `loomwright/scripts/automate-lanes.d/wave.sh` header + `_lanes_fc_finalize` — extend (`fleet closeout registry:`).
  - `loomwright/skills/automate-loop/helpers.md` (`sweep` row) and the `supervisor-result.md` golden fixtures that quote sweep text — no change: they describe the `sweep` helper / archived model output, not the done-exit line list.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `scripts/test-ci-local.sh` — leak-fixture leg (AC6 FAIL + no stamp) | delete `leak gate: ` in `scripts/ci-local.sh` (the line assigning the leak-gate FAIL verdict) — the leaking fixture must then not report the leak-gate FAIL, turning the leg red |
| `scripts/test-ci-local.sh` — leg (i) real-leaker shape `python3 <repo-path script> --port N` FAILs | reviewer-applied: match survivors by command-line path under `$tmpd` instead of by the `LOOMWRIGHT_CI_LOCAL_RUN` marker ⇒ leg (i) passes ⇒ red |
| `scripts/test-ci-local.sh` — leg (ii) detached `nohup sleep` grandchild FAILs | delete `LOOMWRIGHT_CI_LOCAL_RUN=` in `scripts/ci-local.sh` (the export line) — no process carries the marker ⇒ no survivor ⇒ leg red |
| `scripts/test-ci-local.sh` — clean leg prints `clean (0 new processes survived)` and PASSes | reviewer-applied: count the before-snapshot's own processes as new (drop the pid+lstart exclusion) ⇒ the clean fixture FAILs ⇒ red |
| `scripts/test-ci-local.sh` — unrelated concurrent listener ⇒ `not attributable … (not failed)` note, run PASSes | reviewer-applied: fail on every new listener regardless of marker ⇒ red |
| `scripts/test-ci-local.sh` — `lsof` absent ⇒ `listeners unchecked (lsof absent)`, process half still FAILs the leak | reviewer-applied: make the lsof-absent branch skip the whole gate ⇒ the leak leg under no-lsof PASSes ⇒ red |
| `scripts/test-ci-local.sh` — ps snapshot failure (PATH-stub `ps` exiting non-zero) fails CLOSED | reviewer-applied: make the snapshot-failure branch return clean ⇒ red |
| `scripts/test-ci-local.sh` — env-blind `ps` (stub showing no environment) ⇒ `unverifiable` line, no FAIL | reviewer-applied: treat env-blind as zero survivors silently (drop the `unverifiable` line) ⇒ red |
| `loomwright/scripts/test-proc-registry.sh` — empty registry zero line and `unavailable` line | reviewer-applied: print nothing for an unavailable registry ⇒ red |
| `loomwright/scripts/test-proc-registry.sh` — `--scan` counts a fixture look-alike (`; 1 unregistered`) and the registry-dir checksum is unchanged | reviewer-applied: (a) raise the default `LOOMWRIGHT_PROC_UNREG_MIN_S` comparison to never-true ⇒ count 0 ⇒ red; (b) make `summary` touch a file in the registry dir ⇒ checksum leg red |
| `loomwright/scripts/test-automate-next-step.sh` — `summary` prints nothing ⇒ `skipped: no output` placeholder | reviewer-applied: drop the `${…:-…skipped: no output}` default ⇒ the line reads `process registry: ` ⇒ red |
| `loomwright/scripts/test-automate-lanes.d/04-fleet-closeout-to-optout.sh` — re-run on a done parent records no second registry line | reviewer-applied: move the registry append above `_lanes_fc_finalize`'s already-done early return ⇒ a second line ⇒ red |
| `loomwright/scripts/test-session-resume.sh` — one-orphaned ⇒ exactly one line (startup + resume) | delete `need attention` in `loomwright/scripts/session-resume.sh` |
| `loomwright/scripts/test-session-resume.sh` — unreadable registry ⇒ no line, exit 0 | reviewer-applied: make the attention helper print its line when `summary` prints `unavailable` (treat unavailable as 1 item) — the leg must turn red |
| `loomwright/scripts/test-proc-registry.sh` — summary makes ≤1 `ps` call (PATH-stub counter) | reviewer-applied: replace the snapshot lookup with a per-entry `_pr_lstart` call — 3 entries ⇒ >1 call ⇒ red |
| `loomwright/scripts/test-proc-registry.sh` — recycled pid in summary ⇒ `finished` | reviewer-applied: drop the command-line-hash comparison from summary's classification ⇒ the recycled entry reads `running` ⇒ red |
| `loomwright/scripts/test-proc-registry.sh` — hermetic scan skipped | reviewer-applied: remove the `HERMETIC_TEST_ENV` guard on `--scan` with a live look-alike fixture process ⇒ `unregistered` ≥1 ⇒ red |
| `loomwright/scripts/test-automate-next-step.sh` — G parity, `termination-queue-resolved` | delete `process registry: ` in `loomwright/scripts/automate-next-step.sh` |
| `loomwright/scripts/test-automate-lanes.d/04-fleet-closeout-to-optout.sh` — one `fleet closeout registry:` line before the sweep line | delete `fleet closeout registry: ` in `loomwright/scripts/automate-lanes.d/wave.sh` |
| `loomwright/scripts/test-automate-trail.d/05-finalize-closeout-others.sh` — finalize-empty writes one `process registry:` line before its sweep line | delete `process registry: ` in `loomwright/scripts/automate-trail.d/finalize.sh` |
| `loomwright/scripts/test-automate-next-step.sh` — R12 (reserved prefixes ⇔ doc) and the reserved-prefix refusal of a `progress_note` starting `process registry:` | reviewer-applied: remove the `process registry` row from `NS_RESERVED_PREFIXES` ⇒ the forged-note leg / R12 turns red |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | `proc-registry.sh summary [--scan]` — one-`ps` snapshot classification + unregistered look-alike count | AC1, AC2 | 2 modify, 0 create | `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 2 | ci-local leak gate — before/after snapshot attributed by the inherited LOOMWRIGHT_CI_LOCAL_RUN marker, FAIL on survivors, real-leaker-shape legs | AC6 | 2 modify, 0 create | `skills/ci-cd/SKILL.md`, `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 3 | SessionStart attention line + HOOKS.md + changelog fragment + evidence file (runs last, on the integrated tree) | AC3, AC7, AC8 | 3 modify, 2 create | `skills/unit-testing/SKILL.md` | BLOCKED (by #1, #2, #4) |
| 4 | Run-end registry-summary lines — both `/automate` done exits (driver `terminate`, `finalize-empty`), fleet close-out, reserved prefixes, golden trio, prose | AC4, AC5 | 12 modify, 0 create | `skills/automate-loop/SKILL.md`, `skills/unit-testing/SKILL.md` | BLOCKED (by #1) |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/scripts/proc-registry.sh", name: "summary)"}
  - {kind: "symbol", path: "loomwright/scripts/proc-registry.sh", name: "proc-registry: summary — "}
  - {kind: "symbol", path: "loomwright/scripts/proc-registry.sh", name: "LOOMWRIGHT_PROC_PS_SNAPSHOT"}
  - {kind: "symbol", path: "loomwright/scripts/proc-registry.sh", name: "LOOMWRIGHT_PROC_UNREG_MIN_S"}
  - {kind: "symbol", path: "loomwright/scripts/test-proc-registry.sh", name: "summary"}
requires: []
lanes:
  - "loomwright/scripts/proc-registry.sh"
  - "loomwright/scripts/test-proc-registry.sh"
external_requires:
  - "ps (BSD and procps) supporting -axww -o pid=,ppid=,lstart=,etime=,command="

# Subtask 2
provides:
  - {kind: "symbol", path: "scripts/ci-local.sh", name: "ci-local: leak gate — "}
  - {kind: "symbol", path: "scripts/ci-local.sh", name: "CI_LOCAL_LEAK_SETTLE"}
  - {kind: "symbol", path: "scripts/ci-local.sh", name: "LOOMWRIGHT_CI_LOCAL_RUN"}
  - {kind: "symbol", path: "scripts/test-ci-local.sh", name: "leak gate"}
requires: []
lanes:
  - "scripts/ci-local.sh"
  - "scripts/test-ci-local.sh"
external_requires:
  - "lsof (optional — absent ⇒ listener half reported unchecked)"

# Subtask 3
provides:
  - {kind: "symbol", path: "loomwright/scripts/session-resume.sh", name: "need attention"}
  - {kind: "symbol", path: "loomwright/scripts/test-session-resume.sh", name: "Background processes"}
  - {kind: "symbol", path: "loomwright/docs/HOOKS.md", name: "Background processes"}
  - {kind: "file", path: "changelog.d/af39g-leak-gate-and-attention-lines.md"}
  - {kind: "file", path: "docs/evidence/af39g-leak-gate-and-attention-lines.md"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/proc-registry.sh", name: "summary)"}
  - {from: "1", kind: "symbol", path: "loomwright/scripts/proc-registry.sh", name: "LOOMWRIGHT_PROC_PS_SNAPSHOT"}
  - {from: "2", kind: "symbol", path: "scripts/ci-local.sh", name: "ci-local: leak gate — "}
  - {from: "4", kind: "symbol", path: "loomwright/scripts/automate-next-step.sh", name: "process registry: "}
lanes:
  - "loomwright/scripts/session-resume.sh"
  - "loomwright/scripts/test-session-resume.sh"
  - "loomwright/docs/HOOKS.md"
  - "changelog.d/af39g-leak-gate-and-attention-lines.md"
  - "docs/evidence/af39g-leak-gate-and-attention-lines.md"
external_requires: []

# Subtask 4
provides:
  - {kind: "symbol", path: "loomwright/scripts/automate-next-step.sh", name: "process registry: "}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.d/wave.sh", name: "fleet closeout registry: "}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/per-item-loop.md", name: "process registry: "}
  - {kind: "symbol", path: "loomwright/scripts/fixtures/automate-golden/termination-queue-resolved/expected.md", name: "process registry: "}
  - {kind: "symbol", path: "loomwright/scripts/automate-trail.d/finalize.sh", name: "process registry: "}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/automate-run.md", name: "process registry"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/proc-registry.sh", name: "summary)"}
lanes:
  - "loomwright/scripts/automate-trail.d/finalize.sh"
  - "loomwright/scripts/automate-trail.sh"
  - "loomwright/scripts/test-automate-trail.d/05-finalize-closeout-others.sh"
  - "loomwright/docs/result-schemas/automate-run.md"
  - "loomwright/scripts/automate-next-step.sh"
  - "loomwright/scripts/test-automate-next-step.sh"
  - "loomwright/scripts/automate-lanes.d/wave.sh"
  - "loomwright/scripts/test-automate-lanes.d/04-fleet-closeout-to-optout.sh"
  - "loomwright/skills/automate-loop/per-item-loop.md"
  - "loomwright/scripts/fixtures/automate-golden/termination-queue-resolved/*"
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 4 ──→ Subtask 3
Subtask 1 ──→ Subtask 3
Subtask 2 ──→ Subtask 3
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none | NO |
| Subtask 2 | Subtask 4 | none (mutually unreachable — #4 may start while #2 still runs; lanes disjoint) | NO |
| Subtask 2 | Subtask 3 | none | YES (requires) |
| Subtask 1 | Subtask 3 | none (#3 calls `proc-registry.sh summary`, never edits it) | YES (requires) |
| Subtask 1 | Subtask 4 | none (#4 calls `proc-registry.sh summary`, never edits it) | YES (requires) |
| Subtask 3 | Subtask 4 | none | YES (requires) |

### Batch Plan
- **Batch 1:** Subtask 1, Subtask 2 (parallel — empty `requires`, zero overlap)
- **Batch 2:** Subtask 4 (after 1; may overlap #2 in wall-clock — disjoint lanes)
- **Batch 3:** Subtask 3 (after 1, 2 and 4 — captures AC7's evidence on the integrated tree)
- **Recommended workers:** 2
- **Estimated batches:** 3

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md` |
| 2 | `skills/ci-cd/SKILL.md`, `skills/unit-testing/SKILL.md` |
| 3 | `skills/unit-testing/SKILL.md` |
| 4 | `skills/automate-loop/SKILL.md`, `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): scope is about 21 files across 4 groups | MEDIUM | Split `context-bound` into 4 subtasks along file groups with zero lane overlap; 3 and 4 depend on 1's `summary` contract only |
| Feasibility (Phase 2.5): 39e shipped no single-`ps` summary and no `unregistered` scan, so `proc-registry.sh` / its test are touched although the requirement's Touches omits them | MEDIUM | One `summary` subcommand in the registry (the header is the contract) keeps classification in ONE place; session-resume and the run-end seams only call it — never a second classifier in a hook |
| Feasibility (Phase 2.5): `/janitor` (39f) is not merged, so the source's `— run /janitor` pointer would name a non-existent command | MEDIUM | The attention line points at `proc-registry.sh list` / `reap` (dry run first); 39f re-points it when `/janitor` lands — note this in the changelog fragment |
| False FAIL in ci-local from processes not started by this run (another session's suite, an editor) | HIGH | Attribute only by THIS run's inherited `LOOMWRIGHT_CI_LOCAL_RUN=<id>` marker (unique per run, so a concurrent ci-local in the same or another checkout never matches); unattributable new listeners print a `note`, never fail. Leg: a concurrent unrelated listener started during the fixture run does not fail it |
| False PASS in ci-local — the gate misses the real leaker shape (`python3 <repo-path script> --port N`, a `nohup` grandchild) | HIGH | Marker attribution is path-independent; legs (i) and (ii) reproduce both shapes and must FAIL, each with a mutation row. Honest limits (env-scrubbed / other-user / env-blind `ps`) are written in the ci-local header, and env-blind reports `unverifiable` rather than a silent clean |
| `ps -E` / `ps e` output with environments is large on a busy machine | LOW | One snapshot before and one after (plus the settle re-checks on the candidate pids only); grep the marker with a fixed string, never per-process `ps` calls |
| A suite that asserts its inherited environment (e.g. an env-scrub or hermetic-egress test listing allowed variables) trips on the new `LOOMWRIGHT_CI_LOCAL_RUN` variable | MEDIUM | `TMPDIR` is left untouched; the marker is one inert variable. Verify with one full `bash scripts/ci-local.sh` run (AC7) plus `test-hermetic-egress.sh` / `test-host-mode.sh` green; if a suite whitelists env, name the marker there in Subtask 2 |
| Live-machine reads making other suites flaky (eight suites run `session-resume.sh`) | HIGH | `--scan` skipped under `HERMETIC_TEST_ENV=1` without `LOOMWRIGHT_PROC_PS_SNAPSHOT`; the registry already redirects hermetically; new legs use both seams |
| Unregistered false positives at SessionStart (short-lived plugin scripts from other live sessions) | MEDIUM | Age floor `LOOMWRIGHT_PROC_UNREG_MIN_S` (default 3600 s), exclude own pid ancestry and every registered pid; honest limit stated in the proc-registry header (a legit unregistered process older than the floor — e.g. a pre-39e merge watcher — IS reported, which is intended) |
| Settle poll adds wall time / sleep-race scanner | LOW | Condition poll bounded by `CI_LOCAL_LEAK_SETTLE` that ends as soon as no candidate survives; check `test-no-fixed-sleep-race.sh` baseline |
| Golden parity drift (prose ↔ `ns_terminate` ↔ golden trio) | MEDIUM | Subtask 4 owns all of them; G parity in `test-automate-next-step.sh` + `test-automate-golden.sh` must be green |
| Mutation controls that silently no-op (lesson fa32a308) | MEDIUM | Gate every mutant on non-empty + differs-from-original + `bash -n` before trusting it |

## Configuration
- **Workers:** 2
- **Mode:** parallel
- **Estimated batches:** 3
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-24-af39g-leak-gate-and-attention-lines.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-10-24T08:21:42Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/692
- **Branch:** feature/af39g-leak-gate-and-attention-lines
- **Files changed:** 27
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** proc-registry.sh summary [--scan] (one ps snapshot), the ci-local leak gate (marker plus fd-9 attribution, FAILs on survivors), the SessionStart Background-processes attention line, and run-end registry lines at both /automate done exits and fleet close-out. Subtask 3 was re-queued once after hitting its turn limit (owner chose A). Phase 4.5 iteration 1 fixed 3 MEDIUM findings in 37906c6: the lane sampler now self-registers and --scan excludes descendants of registered pids, the --affected leak-gate legs LK10-LK14 were added, and the evidence was clarified. Iteration 2 PASSed. Ubuntu CI (ci/static/suite 1-3) is green. Dismissed follow-ups: automate-run.md/loop-inventory done-exit restatement drift (MEDIUM), lsof without -b (LOW), sampler 24h-cap stranded memory-pressure file (LOW).

## Not verified
- **Linux procps `ps -A -ww` snapshot form for `summary`** — no local Linux runtime (subtask 1)
- **Linux procps `ps axeww` + `lsof` forms of the leak gate (LK1/LK5)** — no local Linux runtime (subtask 2)
- **Full `bash scripts/ci-local.sh` pool on the real suite with the gate on, green** — both real full runs failed on machine load (load average about 78) and lane env leakage (subtasks 2, 3)
- **Live /automate run reaching done with real registry entries** — hermetic fixtures only (subtask 4)
- **`test-automate-trail.sh` runtime on base 237adab vs the 900s watchdog** — not measured (subtask 3)
