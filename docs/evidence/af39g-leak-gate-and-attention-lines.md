# Evidence — af39g: the ci-local leak gate and the background-process attention lines

Captured 2026-10-24 on macOS (Darwin 25.6.0, BSD `ps`/`lsof`) from inside Claude Code sessions, on the integrated
branch (Subtasks 1, 2 and 4 merged, then Subtask 3), base `237adab`. Home paths are written as `~`; scratch and
temp paths as `<scratch>` / `<tmp>`. The machine was running a 4-lane `/automate --parallel` wave the whole time,
which matters for both sections below. The lane-session variables (`LOOMWRIGHT_PHASE_DIR`,
`LOOMWRIGHT_LANES_COORDINATOR_PID`, `LOOMWRIGHT_LANE_RESUME_PATH`, `LOOMWRIGHT_RUN_LOCK_SESSION_ID`,
`LOOMWRIGHT_WEBHOOK_URL`) were unset with `env -u` for every run in sections 3 to 5.

## 1. The leak gate in a real `bash scripts/ci-local.sh` run on this branch

**Run:** one full `bash scripts/ci-local.sh` at 05:41 UTC (key `658d184b…`, 25 ci.yml gates + 171 self-tests, CI
slot 1, 6 jobs). **It FAILED, and not because of the leak gate.** Load average was about 78 (four lanes running
suites at once), and eight suites hit the 900 s per-suite watchdog (`exit 124`). Separately, `test-lanes-addon`
failed on a `claude plugin test` rollout switch in the local CLI, `test-ci-slot` (G8) reported `read-only
commands took 3s`, and three suites failed outright. Section 3 re-runs those suites on their own.

The gate armed before the early phase:

```
ci-local: CI slot 1, 6 jobs
ci-local: 25 ci.yml gates + 171 self-tests: 17 early, then 179 in one pool (key 658d184ba2fb9f9cd1e1569202bf771c7e9017f9)
ci-local: leak gate — armed (run ci-local.17MDHj-241; environment marker visible; inherited-fd marker on)
```

After the pool, these lines printed before the verdict:

```
ci-local: leak gate — survivor pid=6530 sleep 300
ci-local: leak gate — survivor pid=17251 sleep 300
ci-local: leak gate — survivor pid=28368 sleep 300
ci-local: leak gate — survivor pid=39689 sleep 300
ci-local: leak gate — survivor pid=60209 sleep 300
ci-local: leak gate — survivor pid=65123 sleep 90
ci-local: leak gate — survivor pid=71731 sleep 300
ci-local: leak gate — survivor pid=86119 sleep 300
ci-local: leak gate — survivor pid=95615 sleep 300

ci-local: not run locally — ci.yml's sdk-spike step (npm build + node suites); CI still runs it.
ci-local: FAIL after 2846s — see the FAIL banners above (nothing cached)
```

**What this shows:** nine processes that carried this run's marker outlived the suite. They are the `sleep`
children of suites the watchdog killed at 900 s: killing the suite's shell does not kill a backgrounded `sleep`
it started. The gate is report-only. It named them and signalled none. All nine had exited on their own by 06:57 UTC
(`ps -p` found none of them). Because the run had already failed on the suite banners, the verdict line is the
generic FAIL, not the leak-gate wording. Section 4 shows the leak-gate verdict on a fixture.

**The gate's own FAIL verdicts appear only in fixture runs.** Neither real run in this section reached a leak-gate
verdict, because both failed on suite banners first. Every leak-gate verdict wording is exercised by a
`scripts/test-ci-local.sh` fixture leg instead:

- the survivor verdict on a full run: (LK2), (LK3), (LK5) and (LK8);
- the start-snapshot failure: (LK6);
- the after-suite snapshot failure: (LK11);
- the `--affected` survivor verdict: (LK12);
- the `--affected` start- and after-snapshot failures: (LK13) and (LK14);
- the early-red verdict that stands over a report-only gate: (LK10).

No real green full run is captured here. The machine was loaded by parallel lanes, so none was attempted. The
PR's GitHub Actions run on ubuntu is green on this branch at `f7861e4` (`ci`, `static`, `suite (1)` to
`suite (3)`): https://github.com/vikashruhilgit/loomwright/actions/runs/40074670280. Those suites, including
`test-ci-local.sh` and `test-proc-registry.sh`, are the first exercise of the Linux `ps` / `lsof` forms.

**A second, fresh run: `bash scripts/ci-local.sh --affected`** at 07:07 UTC (load about 6; 24 changed files against
`237adab`, 17 early-set entries + 6 mapped suites in one pool). It ran while the standalone re-runs of section 3
were also running. This run shows the clean and not-attributable lines a real pool produces:

```
ci-local: leak gate — armed (run ci-local.Ir5IQV-99142; environment marker visible; inherited-fd marker on)
…
2 of 23 self-tests FAILED (wall 912s):
  loomwright/scripts/test-automate-next-step.sh
  loomwright/scripts/test-proc-registry.sh
ci-local: leak gate — clean (0 new processes survived)
ci-local: leak gate — note: new listener pid=13562 not attributable to this run (not failed)
ci-local: leak gate — note: new listener pid=34967 not attributable to this run (not failed)

ci-local --affected: FAIL after 913s — see the FAIL banners above
```

The two new listeners belonged to other sessions on the machine. They carried no marker, so the run noted them
and did not fail on them. This run also FAILED, on two suites:

- `test-automate-next-step.sh` hit the 900 s watchdog in the contended pool. On its own it passed in 680 s
  (section 3).
- `test-proc-registry.sh` failed one leg, `AC6 a process that no longer matches after TERM is NOT KILLed (re-check
  before KILL)`. That reap leg was already on base `237adab` (af/39e). On its own, the suite passed `161 passed, 0
  failed`. This branch's change to `proc-registry.sh` only adds a snapshot path that `cmd_summary` alone switches
  on (`PR_SNAP_ON=1`), so `reap` runs the same code as on base. The failure reads as a timing flake under load. It
  was not reproduced.

## 2. The attention line from one fresh `session-resume.sh` startup on this machine

From this branch's worktree, which has a `.supervisor/` (plugin-active), at 06:57:24 UTC, without
`HERMETIC_TEST_ENV`:

```
$ bash loomwright/scripts/proc-registry.sh summary --scan
proc-registry: summary — 0 entries: 0 running, 0 overdue, 0 orphaned, 0 finished; 4 unregistered

$ printf '{"source":"startup",…}' | CLAUDE_PROJECT_DIR="$PWD" bash loomwright/scripts/session-resume.sh
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "**Background processes:** 4 item(s) need attention (0 overdue, 0 orphaned, 4 unregistered) — inspect with `proc-registry.sh list`; stop registered ones with `proc-registry.sh reap` (dry run first)"
  }
}
```

The real registry is empty (`proc-registry.sh list` prints `(no entries)`). The 4 unregistered processes are
plugin command lines older than 3600 s that are not this shell's ancestors:

| pid | age | command (truncated) |
|---|---|---|
| 5492 | 2:42:55 | `bash ~/.claude/plugins/cache/atelier/loomwright/17.14.1/scripts/automate-lanes.sh _lane-run …/L6 …` |
| 33570 | 3:10:13 | `bash ~/.claude/plugins/cache/atelier/loomwright/17.14.1/scripts/lane-sampler.sh --parent-run-id automate-2026-10-22-123646 …` |
| 79011 | 2:41:31 | `bash ~/.claude/plugins/cache/atelier/loomwright/17.14.1/scripts/automate-lanes.sh _lane-run …` |
| 79073 | 2:41:31 | `claude -p … --plugin-dir ~/.claude/plugins/cache/atelier/loomwright/17.14.1 …` |

**Honest reading:** these are live, wanted processes of the running `/automate --parallel` wave, not leaks. They
match the scan's rule as written (a plugin `scripts/` path, older than `LOOMWRIGHT_PROC_UNREG_MIN_S`, not
registered, not an ancestor). The wave was started from the installed plugin 17.14.1, which predates the process
registry (it shipped in 17.15.0), so none of its processes registered and the real registry was empty. On this
branch the picture differs per process:

- The `_lane-run` wrappers and their `claude -p` sessions (pids 5492, 79011, 79073) DO register on this branch:
  `automate-lanes.d/launch.sh` registers each wrapper, and the wrapper registers its session, through its one
  `_lanes_register` call line. A wave started from this branch would not show them as unregistered.
- `lane-sampler.sh` (pid 33570) did NOT register on this branch as first written. The coordinator starts it once
  per wave and it runs for the whole wave, so during any wave longer than an hour every new session would get
  this line about a wanted process. That was a real false positive of the scan, and it is now fixed in two
  ways. First, `lane-sampler.sh` registers itself when its loop starts (kind `lane`, owned by the coordinator
  pid it was given, fail-safe), so it reads `running` while its coordinator lives and `orphaned`, then
  `finished`, once the coordinator is gone and it has exited. Second, `summary --scan` no longer counts a process
  whose snapshot ppid chain reaches a live registered process, so a child of a registered process is never
  counted. Both are pinned by tests: `test-lane-sampler.sh` (R) checks the self-registration, and
  `test-proc-registry.sh`'s `leg_summary_scan` checks the descendant exclusion, with a mutation control.

A wanted long-lived plugin process that neither registers nor descends from a registered one is still counted.
The `proc-registry.sh` header lists that as an honest limit of the scan.

## 3. Triage of the full run's failing suites, re-run standalone

Each was run on its own, one at a time, with the lane variables unset, on this branch (load average about 6):

| suite | in the full run (section 1) | standalone on this branch |
|---|---|---|
| `test-automate-next-step.sh` | exit 124 (900 s watchdog) | rc 0, 680 s |
| `test-automate-trail.sh` | exit 124 (900 s watchdog) | rc 0, 913 s |
| `test-harvest-conventions.sh` | exit 1 (M1a: `the writer did not write even on the prompting path`) | rc 0, 40 s |
| `test-run-pin-mutations.sh` | exit 1 ((B) `unverified (budget_exhausted)`, a time budget) | rc 0, 18 s |

All four pass on their own, so this branch was not compared against base for them. Two of the failures were
timeouts. The (B) failure was a time budget running out. The M1a failure could come from load or from a lane variable leaking into the suite.
The standalone run changed both at once (lower load, variables unset), so it does not tell them apart.
`test-automate-trail.sh` takes 913 s even when run alone, which is longer than ci-local's 900 s per-suite watchdog
on this machine at load about 6. Its runtime on base was not measured. `test-lanes-addon` (a `claude plugin test`
rollout switch in the installed CLI) and `test-ci-slot` G8 (a 3 s timing bound) were not re-run.

The subtask's own suites, run standalone on this branch: `test-session-resume.sh` 358/0, `test-proc-registry.sh`
161/0, `test-read-rules.sh` 117/0, `test-citation-drift.sh` 26/0, `test-no-fixed-sleep-race.sh` 27/0,
`check-doc-currency.sh` OK, `check-version-bump.sh` OK (1 fragment pending, legal).

## 4. AC6 mutation controls — the leak gate (red output)

Baseline: `bash scripts/test-ci-local.sh` on this branch gives `test-ci-local: 104 passed, 0 failed` (104 s), with
these leak legs:

```
ok   (LK1) clean fixture: 'leak gate — clean (0 new processes survived)', PASS, stamped
ok   (LK2) leg (i) detached python3 <repo script> --port listener: FAIL, survivor named, verdict last, stamp removed, survivor not signalled
ok   (LK3) leg (ii) nohup'd grandchild 'sleep 271' (re-parented): FAIL, exactly that survivor, verdict in 4s
ok   (LK4) a concurrent unrelated listener: 'not attributable to this run (not failed)' note, PASS
ok   (LK5) lsof absent: 'listeners unchecked (lsof absent)', the environment marker still FAILs the leak
ok   (LK5) MUTATION CONTROL: without the LOOMWRIGHT_CI_LOCAL_RUN export the leak passes — (LK5) pins the marker
ok   (LK6) ps snapshot fails: 'leak gate: ps snapshot failed (nothing cached)', exit 1, nothing ran, stamp removed
ok   (LK7) env-blind ps + no lsof: 'leak gate — unverifiable (ps cannot show the environment)', not failed
ok   (LK8) env-blind ps + lsof: the inherited fd marker FAILs the nohup'd 'sleep 271'
ok   (LK8) MUTATION CONTROL: without the fd-9 marker the env-blind leak passes — (LK8) pins the fd half
ok   (LK9) a non-integer CI_LOCAL_LEAK_SETTLE: exit 2, nothing ran
```

**Control A — the brief's pin mutation "delete `leak gate: ` in the line assigning the leak-gate FAIL verdict"**,
applied to a scratch export of HEAD (`git archive HEAD`), not to the branch:

```
-  verdict="ci-local: FAIL after ${wall}s — leak gate: ${leak_k} process(es) survived the suite (nothing cached)"; verdict_fd=2
+  verdict="ci-local: FAIL after ${wall}s — ${leak_k} process(es) survived the suite (nothing cached)"; verdict_fd=2
```

```
FAIL (LK2) rc=1 leaked=[31223] key=54fa437d…-Darwin stamp=gone out=ci-local: log <tmp>/ci-local-test.Q9R4mk/state/…/runs/…-28474.log
ci-local: FAIL after 2s — 1 process(es) survived the suite (nothing cached)
FAIL (LK3) rc=1 3s leaked=[36735] out=ci-local: log <tmp>/…-34735.log
ci-local: FAIL after 3s — 1 process(es) survived the suite (nothing cached)
FAIL (LK5) rc=1 leaked=[45785] out=ci-local: log <tmp>/…-44007.log
ci-local: FAIL after 3s — 1 process(es) survived the suite (nothing cached)
FAIL (LK8) rc=1 leaked=[59917] out=ci-local: log <tmp>/…-57553.log
ci-local: FAIL after 2s — 1 process(es) survived the suite (nothing cached)
test-ci-local: 100 passed, 4 failed
```

Each leg kills its own leaked process in cleanup: none of the four pids was alive after the run.

**Controls B and C — the marker halves.** The brief planned "delete the `LOOMWRIGHT_CI_LOCAL_RUN=` export ⇒ leg (ii)
goes red". On macOS that does not hold on its own: `ps -E` hides the environment of Apple platform binaries such as
`/bin/sleep`, so the gate also marks descendants with an inherited fd that `lsof` sees. Each half therefore has its own
in-suite mutation control, (LK5) for the export and (LK8) for fd 9 (both `ok` above). Each control builds the
mutant, checks it differs and parses, and asserts that the leak then PASSES, which is the red outcome for the leg it
pins. The reviewer-applied rows of the brief's pin-mutation table (path matching, dropping the pid+lstart exclusion,
failing on every listener, skipping the gate when lsof is missing, a clean result from a failed snapshot, a silent
env-blind result) were not re-applied by hand here.

## 5. AC3 mutation controls — the attention line (red output)

Baseline: `bash loomwright/scripts/test-session-resume.sh` gives `RESULT: 358 passed, 0 failed`, including:

```
ok: (bp1) startup: one orphaned entry ⇒ exactly one Background processes line
ok: (bp1) resume: one orphaned entry ⇒ exactly one Background processes line
ok: (bp3) startup: nothing else to say ⇒ byte-identical empty output
ok: (bp4) startup: an unreadable registry ⇒ no line, exit 0
ok: (bp4) resume: an unreadable registry ⇒ no line, exit 0
```

**Control M1 — the brief's pin mutation "delete `need attention` in `session-resume.sh`"** (scratch export,
`item(s) need attention (` → `item(s) (`):

```
FAIL: (bp1) startup: **Background processes:** 1 item(s) (0 overdue, 1 orphaned, 0 unregistered) — inspect with `proc-registry.sh list`; stop registered ones with `proc-registry.sh reap` (dry run first)| rc=0
FAIL: (bp1) resume: **Background processes:** 1 item(s) (0 overdue, 1 orphaned, 0 unregistered) — inspect with `proc-registry.sh list`; stop registered ones with `proc-registry.sh reap` (dry run first)| rc=0
FAIL: (bp1) startup body: **Background processes:** 1 item(s) (0 overdue, 1 orphaned, 0 unregistered) — …
FAIL: (bp5) ctx: **Background processes:** 1 item(s) (0 overdue, 0 orphaned, 1 unregistered) — …
RESULT: 350 passed, 4 failed
```

**Control M2 — reviewer-applied "treat `unavailable` as one item"** (scratch export, one line inserted before the
helper's shape check):

```
+  case "$line" in *unavailable*) line="proc-registry: summary — 1 entries: 0 running, 0 overdue, 1 orphaned, 0 finished" ;; esac
```

```
FAIL: (bp4) not-a-dir: rc=0 {
FAIL: (bp4) startup unreadable: rc=0 **Background processes:** 1 item(s) need attention (0 overdue, 1 orphaned, 0 unregistered) — …
FAIL: (bp4) resume unreadable: rc=0 **Background processes:** 1 item(s) need attention (0 overdue, 1 orphaned, 0 unregistered) — …
RESULT: 351 passed, 3 failed
```

The suite also carries both controls in-suite as (bp6) M1 and M2, and both are `ok` in the baseline.

## 6. Honest limits

- **Linux is exercised only by CI fixtures.** Every capture here is macOS `ps` and `lsof`. The procps
  `ps -A -ww` columns `summary` reads, the environment-showing snapshot form ci-local picks by feature probe, and
  Linux `lsof` are exercised only by the self-tests in the green ubuntu Actions run cited in section 1, never by
  a real Linux `ci-local.sh` pool.
- **The full run in section 1 is a FAILED run** on an overloaded machine. It proves the gate arms, attributes and
  reports in a real pool. It does not prove a green full run on this branch. The fresh `--affected` run also FAILED, so neither run
  proves the leak-gate PASS path. Only the fixture leg (LK1) shows the gate passing a run end to end.
- **The live attention line in section 2 is a false positive** of the `--scan` heuristic, from a wave of the
  pre-registry 17.14.1 plugin. On this branch the lane wrappers and sessions register, and the lane sampler now
  registers too. Any child of a registered process is excluded (section 2). A wanted plugin process that does
  neither is still counted.
- **Controls applied by hand:** only the brief's non-reviewer pin mutations (Control A, M1) and M2. The other
  reviewer-applied rows are covered only by the in-suite controls quoted above, or by none.
