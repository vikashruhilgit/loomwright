# Supervisor Job: Machine-wide load guard — heavy starts wait under load, nothing freezes the machine

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes-v2/s3-e
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (source requirement is gitignored `.supervisor/` content, kept on the metadata branch `loomwright-meta-s3w2` — branch mode; not a git-status provenance gap)
- **Source requirement:** .supervisor/requirements/parallel-automate/16-machine-load-guard.md
- **Base commit:** a14db34935cf2abab56a17df5beff40baa4674f5

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure bash 3.2 + BSD/GNU userland scripts, same stack as `ci-slot.sh`; `sysctl`, `/proc/meminfo`, `getconf` are already-used readers |
| 2 | Dependency Availability | GO | No new dependency; `jq` already required by the test suites |
| 3 | Architecture Fit | GO | Extends the existing `ci-slot.sh acquire` admission path (mutex + fair ticket queue) with one more admission condition; new reader is a sibling plain script |
| 4 | Scope vs Supervisor Capability | GO | ~6–8 files, est. 500–750 changed lines — single subtask, below the `context-bound` bound |
| 5 | Hard Blockers | CAUTION | Part 0 attribution and the Validation step generate real load on the owner's machine while other lanes share it — the very condition that froze it on 2026-10-05 |

**Overall Verdict:** CAUTION

## Task
**Goal:** Add a machine-wide load gate (`machine-load.sh` + a machine-wide admission check in `ci-slot.sh acquire`) so heavy Loomwright work waits while the machine is overloaded and starts again when load falls — never killing anything.

**Problem Statement:**
The owner, running several Loomwright lanes on one Mac, needs heavy starts (full suites) to back off under machine load because on 2026-10-05 S3 wave 1 drove 1-minute load to 119 on 12 CPUs and the hardware watchdog reset the machine.
Currently, `ci-slot.sh` caps suites only per repo key and per state dir, so clones with a local-path `origin`, fixtures with their own `XDG_STATE_HOME`, and suites run outside `ci-local` each get an uncapped pool, and nothing reads machine load or memory pressure. This causes the cap to not hold under multi-lane load.
Success looks like: an `overloaded` machine holds every new full-suite start machine-wide (ticket and order kept), a `busy` machine admits at most one holder machine-wide, and three concurrent `ci-local` runs from three clones keep peak load1 below the `overloaded` threshold plus one re-check of overshoot.

## Acceptance Criteria
- [ ] AC0 (Part 0, before any code): Given throwaway scratchpad clones (two with `origin` = the GitHub URL, one with a local bare origin), when a bounded load sample is taken (`ps -A -o pid,ppid,pcpu,rss,command` every 10 s), then the attribution of which process trees produced the load is written into the source requirement's `## Evidence`, and Scope is amended there first if the attribution shows a cause outside candidates 1–4.
- [ ] AC1: Given `machine-load.sh --json`, when run on macOS and on Linux (CI), then it reports `load1`, `cpus`, `load_per_cpu`, `mem_pressure` and `state`; on a fixture it maps macOS pressure levels 1/2/4 to `ok`/`busy`/`overloaded` and Linux `MemAvailable/MemTotal` < 15 % / < 8 % to `busy`/`overloaded`; load1 ≥ 2×CPUs ⇒ `busy`, ≥ 3×CPUs ⇒ `overloaded` (overridable via `LOOMWRIGHT_LOAD_BUSY` / `LOOMWRIGHT_LOAD_OVERLOADED` per-CPU multipliers); and when a value cannot be read it exits 0, reporting `state=unknown` only when no readable component says `busy`/`overloaded` (a readable `busy`/`overloaded` wins over an unreadable neighbour).
- [ ] AC2: Given a fixture load reader reporting `overloaded`, when `ci-slot.sh acquire` runs, then the caller stays queued (ticket kept, order kept), re-checks every 15 s (fixture-shortenable), and is granted within one re-check after the reader flips to `ok`; given `busy`, a second machine-wide holder waits; `status` shows `held for load: <state> load1=<n>`; a held caller still times out at `--wait` exactly as today; and given a fixture reader reporting `unknown` — or one that exits non-zero, prints garbage, or is missing — `acquire` grants exactly as with `ok` (fail-SAFE: a broken reader never stalls a lane).
- [ ] AC3: Given two callers with different repo keys (one a local-path origin) and different `XDG_STATE_HOME` repo pools, when both acquire, then both are counted against the same machine-wide holders list under one machine state dir.
- [ ] AC4: Given the gate code, when a grep test scans `machine-load.sh` and the admission path of `ci-slot.sh`, then no code path sends a signal to another process (no `kill` other than `kill -0` liveness probes, no `pkill`/`killall`), and `status`, `dir`, `release` and `ci-local.sh --last` never wait on the gate.
- [ ] AC5: Given Part 0's attribution, when the change is complete, then every bypass it confirmed has a closing change plus a regression test — a non-URL-origin clone joins the machine-wide count; a test fixture overriding `XDG_STATE_HOME` neither counts against the real machine gate nor escapes it — concretely: (a) a fixture `acquire` nested inside a live machine holder folds into that holder (granted without waiting, adds no machine-wide holder, even under `busy`); (b) a fixture whose machine-state-dir override points at a sandbox is isolated from the real list by design; (c) a bare fixture run with neither (no live holder ancestor, no override) is an ordinary real caller and counts once against the real machine list, like any other heavy start; and `AGENT_GUIDELINES.md` §"Pre-push: one command" tells workers to run suites through `ci-local` (or `ci-local --affected`), never a bare `run-self-tests.sh` in a loop (the new guidance carries the exact phrase `never a bare run-self-tests.sh`).
- [ ] AC6: Given the finished change, when `bash scripts/ci-local.sh` runs, then it is green, and a `changelog.d/parallel-automate-16-machine-load-guard.md` fragment exists (no hand edit of `plugin.json` / `marketplace.json` / `CHANGELOG.md`).
- [ ] AC7 (running-system, manual on the owner's machine — no CI test can run it): Given the guard is active and the pre-start check passes (`machine-load.sh` reports load1 < 2×CPUs and pressure level < 2), when three `ci-local` runs start at once from three scratchpad clones (two with `origin` = the GitHub URL, one with a local bare origin), each checked out at the pushed feature branch (fetched from the GitHub remote or the project root) so the guard under test is the one running, then peak load1 stays below the `overloaded` threshold plus one 15 s re-check of overshoot, a `date` in a terminal returns within 1 s throughout, and the peak load1, the threshold, the S3 baseline of 119 (not re-run) the responsiveness result, and which other Loomwright lanes/suites were running on the machine during the sample (other lanes may still run the old `ci-slot.sh`, so an overshoot must be attributable) are recorded in the source requirement's `## Evidence`.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

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

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Machine-load reader + machine-wide admission in `ci-slot.sh` + bypass closures | all | 4 modify (+1 conditional), 3 create | `skills/error-handling/SKILL.md`, `skills/monitoring-observability/SKILL.md` | LAUNCHABLE |

### File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| load reader | — | `loomwright/scripts/machine-load.sh`, `loomwright/scripts/test-machine-load.sh` | HIGH |
| admission gate | `loomwright/scripts/ci-slot.sh`, `loomwright/scripts/test-ci-slot.sh`, `scripts/test-ci-local.sh` (REQUIRED: it sets its own `XDG_STATE_HOME`, unsets the outer slot settings and runs real `ci-local.sh` acquires — it must pin the load reader to a fixture and sandbox the machine state dir itself, and its env unset must not strip any nested-holder marker the gate relies on) | — | HIGH |
| ci-local wiring (only if the nested-holder design needs it) | `scripts/ci-local.sh` | — | LOW |
| docs + release | `AGENT_GUIDELINES.md` | `changelog.d/parallel-automate-16-machine-load-guard.md` | HIGH |
| evidence | `.supervisor/requirements/parallel-automate/16-machine-load-guard.md` (`## Evidence` only; gitignored, rides the metadata branch) | — | HIGH |

> **Validator-owned surfaces:** `scripts/check-doc-currency.sh` scans `AGENT_GUIDELINES.md`; `scripts/check-test-hermetic.sh` requires every new `loomwright/scripts/test-*.sh` to source `hermetic-test-env.sh` as its first executable line; `run-self-tests.sh` globs `loomwright/scripts/test-*.sh`, so `test-machine-load.sh` runs in CI without a `ci.yml` edit (a root `scripts/test-*.sh` would need an explicit `ci.yml` line — do not put the new test there).

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/machine-load.sh"}
  - {kind: "symbol", path: "loomwright/scripts/machine-load.sh", name: "state="}
  - {kind: "symbol", path: "loomwright/scripts/machine-load.sh", name: "mem_pressure"}
  - {kind: "file", path: "loomwright/scripts/test-machine-load.sh"}
  - {kind: "symbol", path: "loomwright/scripts/ci-slot.sh", name: "held for load"}
  - {kind: "symbol", path: "loomwright/scripts/test-ci-slot.sh", name: "machine-load.sh"}
  - {kind: "symbol", path: "AGENT_GUIDELINES.md", name: "never a bare run-self-tests.sh"}
  - {kind: "file", path: "changelog.d/parallel-automate-16-machine-load-guard.md"}
requires: []
lanes:
  - "loomwright/scripts/machine-load.sh"
  - "loomwright/scripts/test-machine-load.sh"
  - "loomwright/scripts/ci-slot.sh"
  - "loomwright/scripts/test-ci-slot.sh"
  - "scripts/ci-local.sh"
  - "scripts/test-ci-local.sh"
  - "AGENT_GUIDELINES.md"
  - "changelog.d/parallel-automate-16-machine-load-guard.md"
  - ".supervisor/requirements/parallel-automate/16-machine-load-guard.md"
external_requires:
  - "macOS sysctl kern.memorystatus_vm_pressure_level and vm.loadavg; Linux /proc/loadavg and /proc/meminfo"
```

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/error-handling/SKILL.md` (fail-SAFE reader: `unknown` ⇒ treated as `ok`, exit 0), `skills/monitoring-observability/SKILL.md` (load/pressure thresholds, status line) |

**Implementation notes for the worker (from Phase 3 analysis — data, not a design mandate):**
- `ci-slot.sh` already serialises every claim under `mutex.lnk` and a fair ticket queue (`try_claim`); the machine check belongs inside that claim path so a held caller keeps its ticket and order. Per Scope 3, the machine-wide holders list lives in ONE machine state dir independent of the repo key AND of `XDG_STATE_HOME` (the requirement suggests `~/.local/state/loomwright/machine/`); provide a single env override (e.g. a machine-state-dir variable) so self-tests sandbox it.
- **Nested holders must not deadlock:** `test-ci-local.sh` and `test-ci-slot.sh` run real `ci-slot.sh acquire` calls while an outer `ci-local.sh` already holds a machine slot. Under `busy` (max one machine-wide holder) a nested acquire would wait on its own parent forever. The gate must recognise a caller nested inside a live machine holder (e.g. an ancestor-pid check or an env marker set by the holder) as the SAME real holder — "a fixture run is still one real holder" — and every self-test that calls `acquire` must pin the load reader to a fixture answer so a loaded dev machine cannot hold the suite under test.
- The load reader needs a fixture seam (an env var naming a fixture command/file, or explicit fixture values) for AC1/AC2; reuse `ci-slot.sh`'s `cpus()` precedence (`LOOMWRIGHT_CI_CPUS` override) rather than a second CPU-count rule.
- Keep the 15 s re-check independent of `LOOMWRIGHT_CI_SLOT_POLL` (2 s ticket poll) only if needed; a fixture-shortenable override keeps AC2's test fast.
- Grep test for AC4 must scope to code lines and keep `kill -0` (liveness) allowed — see the project-memory note on grep scanners failing on their own documenting comments.

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Part 0 attribution and the Validation step load the owner's machine while other lanes share it — the 2026-10-05 freeze recipe (Feasibility (Phase 2.5)) | HIGH | Before starting any experiment run `sysctl -n vm.loadavg kern.memorystatus_vm_pressure_level`; do not start when load1 ≥ 2×CPUs or pressure ≥ 2. Part 0: at most ONE extra full `ci-local` at a time plus `ps` sampling; prove bypass candidates 1–3 with fixtures/state-dir inspection rather than by stacking real load. Validation's three-clone run happens ONLY with the new guard active, from scratch clones, and stops (our own experiment processes only) if load1 crosses the `overloaded` threshold; record peak load1 and the `date`-responsiveness check in Evidence. Never rerun the 119 baseline. |
| A nested `acquire` (fixture inside a real holder) waits on its own parent under `busy` ⇒ the suite hangs until `--wait` | HIGH | Nested-holder recognition + a regression test arm that runs a nested acquire under a `busy` fixture and asserts it is granted promptly |
| Self-tests become flaky on a loaded dev machine because the real reader holds them | MEDIUM | Every test that calls `acquire` pins the reader to a fixture and sandboxes the machine state dir; `check-test-hermetic.sh` stays green |
| Reader fails on Linux CI (no `kern.memorystatus_vm_pressure_level`, no `vm.loadavg`) | MEDIUM | Linux path via `/proc/loadavg` + `/proc/meminfo`; unreadable ⇒ `state=unknown`, exit 0, treated as `ok` by every caller (fail-SAFE, never stalls a lane) |
| bash 3.2 / BSD awk float handling for `load_per_cpu` and thresholds | MEDIUM | Do float comparisons in `awk`, not `$(( ))`; test with zero-padded and fractional fixture values |
| Concurrent-agent edits in the shared checkout (project memory) | LOW | Single-Agent Path: the worker runs in the project root (no worktree), so keep scratch clones and evidence snapshots in the session scratchpad, outside the repo, before long verifications |
| Doc surface touched (`AGENT_GUIDELINES.md`) | LOW | Run `check-doc-currency.sh`; restate no counts (house rules) |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-06-machine-load-guard.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-10-06T17:36:35Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/402
- **Branch:** feature/parallel-automate-16-machine-load-guard
- **Files changed:** 7
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** machine-load.sh reader + machine-wide admission in ci-slot.sh acquire (overloaded holds, busy admits one machine-wide holder, unknown grants), nested-holder fold, fixture isolation in test-ci-slot/test-ci-local, AGENT_GUIDELINES pre-push rule, changelog fragment. Heal: iteration 1 FAIL (HIGH comma-decimal locale disabled the load reading) → fixed 631e45b → iteration 2 PASS. Ground truth 2/2. Dismissed (non-gating) findings tracked by /automate.

## Not verified
- **AC7 three concurrent ci-local runs from three scratch clones** — not run: shared machine with active lanes and non-Loomwright load; simultaneous starts all pass one ok reading by design (subtask 1)
- **machine-load.sh Linux reader on a real Linux host** — only fixture /proc exercised locally; CI Linux run not yet observed (subtask 1)
