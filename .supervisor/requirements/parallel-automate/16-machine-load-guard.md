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
5. **Never kill, never block reads.** The gate holds only new heavy starts. It never signals a running process, and
   `status`, `--last` and read-only commands never wait on it.

## Non-goals
Lane launch gating and crash/reset recovery: they belong to the coordinator (item 05 Scope 16, amended 2026-10-05).
Per-agent CPU limits (`nice`, cgroups), killing or pausing running work, other machines.

## Acceptance criteria
- AC1: `machine-load.sh --json` reports its five fields on macOS and on Linux (CI), maps pressure levels 1/2/4 to
  ok/busy/overloaded on a fixture, and reports `state=unknown` with exit 0 when a value cannot be read.
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
