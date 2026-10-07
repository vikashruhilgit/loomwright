# 16 — Machine guard: lanes may slow the machine down, never freeze it

## Status: pending

## Depends on
none

## Touches
loomwright/scripts/ci-slot.sh
loomwright/scripts/test-ci-slot.sh
loomwright/scripts/machine-load.sh
loomwright/scripts/test-machine-load.sh
AGENT_GUIDELINES.md
changelog.d/parallel-automate-16-machine-load-guard.md

## Problem
On 2026-10-05, S3 wave 1 (4 lanes, the S2 harness `s1h.sh`, plugin 15.122.0) froze the owner's Mac (12 CPUs,
24 GB) and the hardware watchdog reset it:
- 13:17Z: 1-minute load average **119** (15-min 37), three lanes in `ci-local` at once, plus all four lanes'
  workers, a VM and Chrome.
- ~13:29Z: every lane's last log write. 13:40Z: reboot. Panic report `panic-base+socd-2026-10-05-191808.panic`:
  "SOCD report detected: (iBoot panic)"; reset counter: `Boot faults: wdog,reset_in_1 timeout,...` — a watchdog
  reset of a hung machine, not a sleep or a clean shutdown. The report has no stackshot, so load as the cause is the
  most likely reading, not a proven one.
- All four lanes died. Nothing was lost (work committed or on PR #391), but recovery was by hand: the operator found
  the reset, picked each lane's run id and resumed them with `s1h.sh launch <lane> --resume-run <id>`.
- `caffeinate -i` was running; it only prevents idle sleep and cannot help here.

**The cap that exists did not hold.** Item 08's shared CI slots should bound the suite: on 12 CPUs it allows
`floor(12/6) = 2` slots of `floor(12/2) = 6` jobs, about 12 runnable test jobs. Load reached ~10× the CPU count, so
most of it came from work the slots do not see. Candidates from `ci-slot.sh`'s own header and the lane logs (to verify
first; see Verified premises):
1. **Clones whose `origin` is a local path key a separate pool** (`ci-slot.sh` §ORIGIN ASSUMPTION). s3-a ran a
   "running-system check in a scratch clone with local bare origin"; any `ci-local` there had its own 2 slots.
2. **Test fixtures with their own state dir.** `test-ci-local.sh` / `test-ci-slot.sh` runs inside a lane (s3-d's item
   is `ci-local` itself) use their own `XDG_STATE_HOME`, so each is a separate, uncapped pool.
3. **Suites run outside `ci-local`:** workers running `test-*.sh` or `run-self-tests.sh` directly, and a
   caller-set `SELF_TEST_JOBS` that overrides the slot share.
4. **Agents themselves:** 4 lane sessions, each with live worker and reviewer subagents.

Item 05 Scope 16 plans a memory guard, but only for free memory and swap. It lives in the coordinator (wave 3+ of S3),
and it only stops new launches. Nothing today looks at load, nothing is machine-wide, and the S2 harness that runs
S3's waves before item 05 has no guard at all.

## Goal
On one machine, everything Loomwright starts that is heavy (a full suite, a lane launch) asks one **machine-wide**
gate first. The gate holds new heavy work while the machine is overloaded and lets it go when the load falls. It never
kills anything. Lanes get slower under load; the machine stays responsive.

## Scope
1. **Attribute first (Part 0, before any code).** Reproduce a 3-lane-like load in throwaway clones (scratchpad,
   `origin` = the GitHub URL, plus one with a local bare origin) and record which process trees produce the load
   (sample `ps -A -o pid,ppid,pcpu,rss,command` every 10 s). Write the attribution into this file's Evidence. If it
   shows a cause outside candidates 1–4, amend Scope before continuing.
2. **`machine-load.sh` — one reader, two answers.** `machine-load.sh [--json]` prints `load1`, `cpus`,
   `load_per_cpu`, `mem_pressure` and `state=ok|busy|overloaded`. Defaults (operator suggestion 2026-10-05, owner to
   confirm; tune from Part 0 and Validation):
   - **Load, per CPU, not absolute:** `busy` at load1 ≥ **2×CPUs**, `overloaded` at load1 ≥ **3×CPUs** (24 / 36 on the
     owner's 12 CPUs). Why: item 08 measured 27 with two clones as slow but stable; S3 froze at 119. The gate holds only
     new starts, and work already running keeps climbing while a 1-minute average lags (S3: 15-min 37 vs 1-min 119), so
     `overloaded` sits well below the freeze, not at half of it.
   - **Memory, the OS's own judgment, not percent free:** macOS `sysctl kern.memorystatus_vm_pressure_level` — 2
     (warn) ⇒ `busy`, 4 (critical) ⇒ `overloaded`. Why: macOS "free" memory is misleading under compression and swap
     (S2 ran stably with ~100 MB free). Linux fallback: `MemAvailable`/`MemTotal` < 15 % ⇒ `busy`, < 8 % ⇒
     `overloaded`.
   `LOOMWRIGHT_LOAD_BUSY` / `LOOMWRIGHT_LOAD_OVERLOADED` (per-CPU multipliers) override. bash 3.2 / BSD and GNU safe.
   Fail-SAFE: an unreadable value reports `state=unknown` and exit 0, and every caller treats `unknown` as `ok`, so a
   broken reader never stalls a lane.
3. **Machine-wide admission in `ci-slot.sh acquire`.** Before granting any slot, under the existing mutex, read
   `machine-load.sh`. While `overloaded`, the caller stays queued (keeps its ticket and fair order) and re-checks every
   15 s; while `busy`, grant at most one slot machine-wide. The check is **machine-wide, across all repo keys and state
   dirs** (one `~/.local/state/loomwright/machine/` holders list), so candidates 1 and 2 above share it. `status` shows
   `held for load: <state> load1=<n>`. A held caller still times out at `--wait` exactly as today.
4. **Close the bypasses that Part 0 confirms**, each with a regression test:
   - a `ci-local` in a clone with a non-URL origin joins the machine-wide count (it may keep its own repo pool);
   - test fixtures that override `XDG_STATE_HOME` do not count against the real machine gate and do not escape it
     (a fixture run is still one real holder);
   - `AGENT_GUIDELINES.md`: workers run suites through `ci-local` (or `ci-local --affected`, item 09), never a bare
     `run-self-tests.sh` in a loop.
4b. **(Amended 2026-10-06 from Part 0.)** A cause outside candidates 1–4 was confirmed: **non-Loomwright work on
   the same machine** (another project's `nest build` / `jest` workers, browser) and the macOS security daemons that
   exec churn wakes (`syspolicyd`, `trustd`, `tccd`). The gate cannot hold work it does not start, so it must read
   machine-wide load and pressure (Scope 2), never only its own holder count. No extra closure: recorded as a limit
   (Loomwright backs off; it cannot stop the rest).
5. **Never kill, never block reads.** The gate holds only new heavy starts. It never signals a running process, and
   `status`, `--last` and read-only commands never wait on it.

## Non-goals
Lane launch gating and crash/reset recovery: they belong to the coordinator (item 05 Scope 16, amended 2026-10-05).
Per-agent CPU limits (`nice`, cgroups), killing or pausing running work, other machines.

## Acceptance criteria
- AC1: `machine-load.sh --json` reports its five fields on macOS and on Linux (CI), maps pressure levels 1/2/4 to
  ok/busy/overloaded on a fixture, and exits 0 when a value cannot be read, reporting `state=unknown` only when no
  readable component says busy/overloaded (a readable busy/overloaded wins over an unreadable neighbour).
- AC2: with a fixture load reader reporting `overloaded`, `ci-slot.sh acquire` holds the caller (ticket kept, order
  kept) and grants it within one re-check after the reader flips to `ok`. With `busy`, a second machine-wide holder
  waits.
- AC3: two callers with different repo keys (one a local-path origin) are counted against the same machine-wide
  limit.
- AC4: no code path in the gate sends a signal to another process (grep test).
- AC5: Part 0's attribution is in Evidence, and every bypass it confirmed has a closing change and a test.

## Validation (must pass before merge)
- `bash scripts/ci-local.sh` green.
- **Running system:** in a scratch area, start three `ci-local` runs from three clones (two GitHub-origin, one
  local-bare-origin) at once on the owner's machine. Record peak load1 with the guard and the S3 baseline of 119 (no
  rerun of the baseline: that froze the machine). Pass: peak load1 stays below the `overloaded` threshold plus one
  re-check interval of overshoot, and the machine stays responsive (a `date` in a terminal returns within 1 s
  throughout).

## Verified premises (re-check before starting)
- `ci-slot.sh` default: `max(1, floor(CPUs/6))` slots, job share `max(2, floor(CPUs/N))`; repo-keyed state dir; a
  local-path origin keys separately (§ORIGIN ASSUMPTION) — read 2026-10-05 at `3217da0`.
- `kern.memorystatus_vm_pressure_level` returns 1 (normal) on this Mac at 2026-10-05T16:30Z, idle (load1 3.4,
  `kern.memorystatus_level` 53, swap used 1.1 GB of 2 GB).
- The owner's machine: `hw.ncpu` 12, `hw.memsize` 24 GB.

## Evidence
- S3 wave 1 crash, 2026-10-05: see `operator-run/S3-stabilization-wave-spike.md` §"Wave 1 log"; panic and reset
  reports under `/Library/Logs/DiagnosticReports/` (`panic-base+socd-2026-10-05-191808.panic`,
  `ResetCounter-2026-10-05-191809.diag`).
- Item 08's own evidence: two clones with a per-checkout lock pushed load to 27 (one: 10).
- **Part 0 attribution (2026-10-06, 16:04–16:14Z, base `a14db34`, before any gate code).** Setup in the session
  scratchpad: clones `g1`, `g2` (`origin` = the GitHub URL) and `l1` (cloned from a local bare `bare.git`). Pre-start
  check: load1 3.3, pressure level 1 (an earlier check read level 2, and I waited). ONE `ci-local --force` in `g1`
  (slot 1 of 2, 6 jobs), `ps -A -o pid,ppid,pcpu,rss,command` every 10 s, and a self-stop at load1 ≥ 36.
  - Load trace (load1, every 10 s): 2.9 → 9.6 by +150 s, 21.8 by +170 s, then 22–35 with pressure 1↔2. It hit
    **36.3 at +400 s** and the watchdog TERMed my run (rc 143). One minute later load1 was **67.9**, 15-min 16.8.
  - The same window also held: three other headless lanes (`claude -p --resume …`), lane **s3-g** running its own plain
    `ci-local` (the shared pool's second slot: two suites ran at once on one repo key, which the pool allows), and
    non-Loomwright work: a Tray/hub `nest build` (178 % CPU in one sample), then a Tray/hub `jest` run with 11
    `jest-worker`s. That jest run kept load1 at 64–68 **after all my processes were gone**.
  - Per-tree CPU (pcpu summed by nearest ancestor: `ci-local`, `claude`, other): my ci-local tree 20–90 %, the
    s3-g ci-local 20–90 %, claude sessions 50–330 %, "other" (system daemons, the Tray/hub build, browser) 90–380 %.
    The total sampled pcpu was 160–680 %, i.e. 1.6–6.8 CPUs, while load1 sat at 22–36. **Most of the load is not
    visible as steady CPU in a 10 s snapshot.** It is short-lived process churn (each self-test forks thousands of
    `bash`/`sed`/`awk`/`git`) plus I/O wait, and the security daemons that churn wakes (`syspolicyd` 13–46 %,
    `trustd` up to 31 %, `tccd` up to 38 %). That is why the gate reads load1 and pressure, not a process count.
  - Leftover finding: a TERM to `ci-local` (its direct children) left `run-self-tests` worker grandchildren running
    (3 orphaned test shells, which I stopped by hand). Noted for item 09 / `ci-local`; out of scope here (the gate
    never signals).
  - **Candidate 1 confirmed** (state-dir inspection): `ci-slot.sh dir` gives `g1` = `g2` = pool `dd8a9612…`, and
    `l1` (local bare origin) its own pool `e181ca8d…`. A third pool `ad034503…` (created 2026-10-04) already exists
    on this machine from an earlier local-origin checkout. Each such pool had its own 2 slots.
  - **Candidate 2 confirmed** (inspection): `test-ci-slot.sh` and `test-ci-local.sh` both export
    `XDG_STATE_HOME=$tmp/state`, and `ci-slot.sh dir` under an `XDG_STATE_HOME` override resolves to a different
    pool. Their fixture suites are light (stub gates), so this bypass is about counting, not load.
  - **Candidate 3 confirmed** (inspection): `run-self-tests.sh` has no reference to `ci-slot.sh`. A bare runner takes
    no slot, and a caller-set `SELF_TEST_JOBS` is passed through `ci-local` unchanged.
  - **Candidate 4 confirmed** (samples): claude lane sessions were a steady 0.5–3.3 CPUs.
  - **New cause outside 1–4:** non-Loomwright work plus the exec-churn security daemons. Scope amended (4b).

- **Validation, 2026-10-06 (guard active, commit `4b7eade`).** `bash scripts/ci-local.sh` PASS after 674 s (CI slot 2
  of 2: another lane held slot 1). Sampled load1 peaked at 24.6 (pre-start 8.4, pressure 1). Two earlier full runs
  were not green, and neither was a gate deadlock: run 1 had its runner TERMed from outside (`Terminated: 15`, no
  test FAIL banner). Run 2 found a real regression, now fixed: the nested-holder ancestry walk cost one `ps` per
  level before the first poll, which on a loaded pool took longer than `test-ci-local` (L)'s
  `CI_LOCAL_LOCK_WAIT=1`, so the waiter gave up before its first progress line. Fix: one `ps` per walk, run only
  when a machine holder exists, and the first waiting line printed before any give-up. Run 2's apparent "stall"
  was its long tail (`test-automate-trail.sh` 367 s, `test-meta-sync.sh` 266 s, alone at low load). No nested
  acquire waited and no self-test read the real reader (all acquiring suites pin a fixture reader and sandbox
  `LOOMWRIGHT_MACHINE_STATE_DIR`). A third run was cut by my own 600 s tool limit.
- **AC7 not run (deliberately).** Threshold: overloaded = 36 on 12 CPUs, plus one 15 s re-check. S3 baseline 119
  (not re-run). Other lanes were active all session: three headless lanes, s3-g's own `ci-local`, and a Tray/hub
  `jest` run that alone held load1 at 64–82 earlier. One guarded `ci-local` beside them already sampled 24.6, and
  the unguarded Part 0 run passed 36. Design note for the owner: the gate decides at START. Three runs started in
  the same instant all read the same `ok` reading and are all admitted (1-minute load lags), so AC7's simultaneous
  start would mostly measure that lag, not the gate. A staggered start, or a machine-wide cap even when `ok`, would
  close it. Proposed as a follow-up, not done here. AC7 stays open for a run on a quiet machine.
- 2026-10-07, owner fix-now: AC1's unknown clause reworded to the implemented rule (`state=unknown` only when no
  readable component says busy/overloaded; a readable busy/overloaded wins over an unreadable neighbour). The safer
  behaviour stays; only the wording changed, after the Phase 4.5 reviewer flagged the conflict.

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-06T17:36:35Z
- **Brief:** .supervisor/jobs/done/2026-10-06-machine-load-guard.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/402
