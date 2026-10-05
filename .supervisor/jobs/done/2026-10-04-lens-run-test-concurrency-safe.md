# Supervisor Job: test-lens-run.sh case H is safe when two suites run at once

## Environment
- **Project:** repo root of this checkout (lane w2-30)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main @ d3ee8f2 (== origin/main)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1
- **Source requirement:** .supervisor/requirements/automate-followups/30-lens-run-test-concurrency-safe.md

> **Warning (1):** sibling lanes (other clones of this repo) may run `ci-local.sh` concurrently on this
> machine — that is the very condition this item fixes. Never `cd` outside this checkout; never bare `git stash`.

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure bash 3.2 test edit; same TMP-dir-plus-trap convention the suite already uses. |
| 2 | Dependency Availability | GO | `jq`, `perl`/`python3` (lens-run's setpgrp launcher), `pgrep`, `ps` all present on macOS. |
| 3 | Architecture Fit | GO | Test-only change; `lens-run.sh` (the code under test) is NOT modified. |
| 4 | Scope vs Supervisor Capability | GO | One test file + one changelog fragment — single subtask. |
| 5 | Hard Blockers | CAUTION | Scope item 3 asks to "wait for the stub's pid file before starting the clock", but the timeout clock is `lens-run.sh`'s own watchdog (started at CLI launch) — the test cannot defer it without a production change outside `## Touches`. Resolved in-test (see Design decision D3). |

**Overall Verdict:** GO (1 CAUTION carried into Risk Assessment)

## Task
**Goal:** Make `loomwright/scripts/adapters/providers/test-lens-run.sh` case H ("hung CLI times out, process group killed, no leftover children") prove the same three things independently of any other suite running on the machine and of CPU load.

**Problem Statement:**
Two concurrent `ci-local.sh --force` runs (the designed normal since `parallel-automate/08`, PR #375 — default 2 CI slots) both failed case H while a solo run passed: c1 `FAIL: H no leftover stub CLI processes (expected [0] got [1])`; c2 `FAIL: H CLI never wrote its pid …` + `… never wrote a child pid`.
Causes (read from the test, pre-existing since `4865f06`):
1. **Machine-wide check on a fixed name** — `STUB_CLI_NAME="loomwright-test-stub-cli"` is identical in every run, and the leftover assertion is `pgrep -f "$STUB_CLI_NAME"` over the whole machine, so another suite's live stub reads as this suite's leftover.
2. **1-second timeout under load** — `LOOMWRIGHT_LENS_CLI_TIMEOUT=1`: on a loaded machine the stub may not even exec (write its pid) inside one second, so the process-group proof has nothing to prove.
3. **(found in analysis) A shared provider-table file in the source tree** — the suite writes `$HERE/provider-teststub.sh` (fixed name, inside the plugin dir) and deletes it in its EXIT trap; two concurrent runs in the SAME checkout race on it (one run's cleanup deletes the other's provider entry). Different clones do not share it, but the fix is the same shape as cause 1.

## Design decisions (binding on the worker)
- **D1 — per-run identity.** Derive the stub CLI name AND the provider-table name from a per-run token `RUN_TAG="$$"` (digits only; a per-instance suffix such as `-kb` for case K's second instance is fine). Do NOT use the basename of `$TMP` — macOS `mktemp -d` yields `tmp.XXXXXXXX`, whose `.` fails `lens-run.sh`'s provider-name allowlist `[a-zA-Z0-9_-]` and returns `provider_unavailable`: `STUB_CLI_NAME="loomwright-test-stub-cli-$RUN_TAG"`, provider name `teststub$RUN_TAG` (or `teststub-$RUN_TAG`), provider file `$HERE/provider-<that name>.sh`. The generated provider file's `PROVIDER_CLI_NAME` must use the per-run stub name (the heredoc is currently quoted `<<'PROVIDER'` — the worker must interpolate the name safely). Every assertion that echoes the provider name (case A's `.provider` check, `run_lens`) uses the variable, never the literal `teststub`.
- **D2 — scoped leftover check.** Replace `pgrep -f "$STUB_CLI_NAME"` with checks over ONLY the processes case H started: `kill -0` on the recorded leader and child pids, plus the leader's process group (`pgrep -g <pgid>` where the pgid was recorded by the stub, or `ps -o pgid=` read while alive) reporting nothing. **Guard the group check:** before `pgrep -g`, assert the recorded pgid is non-empty, equals the recorded leader pid (the perl/python `setpgrp` launch), and differs from the test's own pgid — otherwise fail that sub-check with a clear message (without `setpgrp`, `lens-run.sh`'s fallback launcher leaves the stub in the test's own group, and `pgrep -g` would list the test itself). No machine-wide name match remains anywhere in the file.
- **D3 — load tolerance without touching `lens-run.sh`.** The watchdog clock belongs to `lens-run.sh` and starts at CLI launch, so the test cannot start it later. Instead: (a) the stub writes its own pid (and pgid) as its FIRST action, before backgrounding the child; (b) raise case H's `LOOMWRIGHT_LENS_CLI_TIMEOUT` from 1 to a value that leaves ample exec headroom under load (5 s recommended); (c) keep the "finished well inside the hung sleep" bound (elapsed < 20 s vs the stub's `sleep 120`), which still proves the timeout fired rather than the CLI exiting; (d) after `lens-run.sh` returns, the bounded wait (up to 10 s) is applied to the *kill* check — poll `kill -0` on leader/child until gone or the bound expires — so a slow-to-reap process is not a false leftover. Document in the case-H comment why the clock is not deferred (it is `lens-run.sh`'s watchdog, forked right after the CLI subshell), and state both honest limits there: (1) a `sleep` shim on the PATH the test passes could defer the watchdog test-side, but it would alter the timing of the code under test, so it is deliberately not used; (2) an exec stall longer than the raised timeout still fails `never wrote its pid` — the raise shrinks the flake window, it does not abolish it, and the 10 s bound now applies to the post-return kill poll, not to the pid-file wait the requirement described. `lens-run.sh` MUST NOT be edited.
- **D4 — concurrency regression leg (overlap held by a release file, not by timeouts).** Add a new case `K` with two overlapping `lens-run.sh` instances:
  - **Instance B (the live neighbour)** starts first, in the background, with its own per-run stub name (`RUN_TAG` + suffix), own temp dir and own provider entry. B's stub writes its pid, then **waits for a release file in B's own temp dir** (poll, bounded ≈60 s), then exits 0. B runs with a long timeout (≈90 s) as a backstop only, so B's lifetime does not depend on A's wall time — A's sandbox setup/teardown runs off A's clock and is unbounded under load.
  - The test waits (bounded, ≤10 s) for B's pid file; then runs **instance A** (the case-H hung CLI, D3's timeout) to completion and runs A's scoped leftover checks while B is held alive — assert `kill -0` on B's leader succeeds at that moment, with a failure message naming the cause (`overlap not established — B exited before A's check`) rather than a generic fail.
  - Then the test writes B's release file, waits for B's `lens-run.sh` (bounded), and asserts B: rc 0, notes do NOT say `timed out` (it was released, not killed), and B's leader is gone. A must end `lens_unparseable`/timed-out with nothing left behind (D2's scoped checks).
- **D4 mutation (replaces the requirement's Validation 4 wording — recorded deviation).** Once D2 lands, nothing in `lens-run.sh` or the allowed assertions depends on the stub's NAME (`lens-run.sh` resolves the CLI with `command -v` on the per-call PATH and kills by recorded pgid / `pgrep -P`), so reverting D1 *alone* is unobservable — say so in the PR body. The mutation that must turn `K` red is reverting D1 **and** D2 together: fixed shared stub name `loomwright-test-stub-cli` for both instances + the old machine-wide `pgrep -f "$STUB_CLI_NAME"` leftover check — A's check then sees B's live stub. Record that hunk and the failing assertion verbatim.
- **D5 — restated copies move in the same change.** Update the file's header `Covers:` list (add `K`; case H's new timeout), the case-H section/assertion labels that state `LOOMWRIGHT_LENS_CLI_TIMEOUT=1` / `bound ~1s+kill`, and every comment that names the fixed `provider-teststub.sh` (header + provider heredoc comment) so the AC-5 grep is clean.

## Acceptance Criteria
- [ ] Given two clones of the repo running `bash scripts/ci-local.sh --force` at the same time, when both suites reach `test-lens-run.sh`, then case H passes in both — three consecutive concurrent runs, logs pasted in the PR body. Recipe (no `cd` out of this checkout needed): `git clone` this checkout's feature branch into a scratch dir under `$TMPDIR`, then start `bash <abs-this-checkout>/scripts/ci-local.sh --force` and `bash <abs-scratch-clone>/scripts/ci-local.sh --force` together (`ci-local.sh` resolves its repo from its own path), three times.
- [ ] Given the change, when `test-lens-run.sh` runs solo, then every case (A–J plus the new leg) passes and the `RESULT:` line is pasted for base and branch (passed/total and any SKIP count).
- [ ] Given the timeout kill removed from the code path (mutation: e.g. a stub that is not killed / `LOOMWRIGHT_LENS_CLI_TIMEOUT` effectively disabled in a scratch copy), when case H runs, then it FAILS; and given the child left alive (mutation: stub child escapes the process group, e.g. `setsid`/`perl setpgrp` on the child), then the leftover assertion FAILS — both recorded verbatim (hunk + failing assertion text) in `WORKER_RESULT` and the PR body.
- [ ] Given D1 and D2 reverted together (fixed shared stub name + the old machine-wide `pgrep -f "$STUB_CLI_NAME"` leftover check), when case K runs, then it FAILS — hunk and failing assertion recorded verbatim; and the PR body states that reverting the stub name alone is unobservable once D2 lands (D4 mutation).
- [ ] Given the whole file, when grepped, then no `pgrep -f`/`pkill -f`/`ps … | grep` machine-wide name match remains, and no literal fixed `provider-teststub.sh` path remains.
- [ ] Given the other self-tests (`loomwright/scripts/**/test-*.sh`, `scripts/test-*.sh`), when grepped for the same shape (machine-wide `pgrep -f`/`pkill -f`/`ps | grep` on a fixed name, fixed-name files written into the source tree), then each hit is fixed in this PR or listed in the PR body with why it is safe (analysis found none executing besides case H; `test-verify-seam.sh`'s `"pkill -f myapp"` is fixture JSON data, not executed; `test-lens-compare.sh` writes fixed `$HERE/provider-teststubx.sh`/`teststuby.sh` — same-checkout race shape as cause 3: fix it the same way or list it).
- [ ] Given the change, when `bash scripts/ci-local.sh` runs, then it is green (includes `check-doc-currency.sh` and `test-citation-drift.sh`).
- [ ] A `changelog.d/automate-followups-30-lens-run-test-concurrency-safe.md` fragment exists in the `<!-- bump: patch -->` format; no version file is hand-edited.

## Outcomes Rubric
- `test-lens-run.sh` contains no `pgrep -f`/`pkill -f`/`ps … | grep` name match; case H's leftover assertions use `kill -0` on the recorded leader/child pids and a process-group query on the recorded pgid.
- `STUB_CLI_NAME` and the provider-table name/file in `test-lens-run.sh` are derived from `RUN_TAG`; no literal `provider-teststub.sh` path remains.
- Case H keeps an elapsed-time bound well under the stub's hung sleep and keeps the `never wrote its pid` / `never wrote a child pid` failure arms.
- A case-K block starts a background `lens-run.sh` instance, waits for its stub pid, runs a second instance to completion, and asserts the first instance's stub is alive (`kill -0`) during the second's leftover checks.
- The diff does not modify `loomwright/scripts/adapters/providers/lens-run.sh`.
- `changelog.d/automate-followups-30-lens-run-test-concurrency-safe.md` exists with a `<!-- bump: patch -->` header.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Make test-lens-run.sh case H concurrency- and load-safe (+ concurrency leg, sibling sweep, changelog) | ALL | 1–2 modify, 1 create | `unit-testing`, `quality-checklist` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1 — the whole change (LAUNCHABLE; no siblings)
provides:
  - {kind: "file",   path: "changelog.d/automate-followups-30-lens-run-test-concurrency-safe.md"}
  - {kind: "symbol", path: "loomwright/scripts/adapters/providers/test-lens-run.sh", name: "RUN_TAG"}
requires: []
lanes:
  - "loomwright/scripts/adapters/providers/test-lens-run.sh"
  - "loomwright/scripts/adapters/providers/test-lens-compare.sh"
  - "changelog.d/automate-followups-30-lens-run-test-concurrency-safe.md"
external_requires: []
```

**Exact-name mandate:** `RUN_TAG` is the literal per-run token variable in `test-lens-run.sh`. `test-lens-compare.sh` is in `lanes` ONLY for the sibling-sweep fix (AC 6) — it is NOT in the requirement's `## Touches`, so if the worker changes it the PR body must say so; leave it untouched if the worker lists it instead of fixing it.

## Parallelism Analysis

### Dependency Graph
Single subtask — no graph.

### File Overlap Matrix
Not applicable (one subtask).

### Batch Plan
One batch, one worker.

## Skill References

| Skill | Why |
|---|---|
| `skills/unit-testing/SKILL.md` | Assertion structure, non-vacuous tests |
| `skills/quality-checklist/SKILL.md` | Pre/post-implementation gates |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Scope item 3's "start the clock after the pid file" is impossible test-side (Feasibility CAUTION 5) | MEDIUM | D3: stub writes pid first, timeout raised to ~5 s, bounded post-return kill poll; deviation documented in the case-H comment and PR body. `lens-run.sh` untouched |
| Scoped check passes vacuously (e.g. pids never recorded ⇒ `kill -0 ""` reads as "gone") | HIGH | Keep the existing `no "… never wrote its pid"` arms; mutation controls in AC 3/4 prove the assertions bite |
| Per-run provider name breaks case A's `.provider` echo assertion or `lens-run.sh`'s name allowlist | MEDIUM | D1: tag restricted to `[a-zA-Z0-9_-]`; every name assertion uses the variable |
| Concurrency leg itself flakes under load (B's watchdog racing A's whole run) | MEDIUM | D4: B is held by a release file the test writes after A's checks, with a ≈90 s backstop timeout — B's lifetime is independent of A's setup/teardown time; bounded waits everywhere; each instance in its own temp dir; overlap-not-established gets its own named failure |
| Quoted heredoc interpolation of the per-run name done unsafely | LOW | Tag is digits/`[a-zA-Z0-9_-]` only; write the one variable line outside the quoted heredoc |
| A new bare `file.ext:N` citation fails `test-citation-drift.sh` | LOW | Use descriptive anchors or `[pins: …]` |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-04-lens-run-test-concurrency-safe.md
```

## Plan Review
- **Decision:** PASS (attempt 3 of 3; attempts 1–2 FAIL, fixed in-brief)
- **Non-blocking notes for the worker (apply them — same flake class this item removes):**
  - MEDIUM — D4: raise the wait for B's pid file from 10 s to the same ~60 s bound as B's release poll (B's sandbox setup runs before its stub starts and is unbounded under load); give that miss its own failure message (`B never started its stub within the bound`).
  - LOW — D4: have B's stub print `{"issues":[]}` before exiting 0 and assert B's `lens_status` is `ok` (proves B ran and was released, not killed); keep the `not timed out` check as a second assertion.
  - LOW — D1/D4: the EXIT trap must remove every per-run provider file, write B's release file and kill B's background job if K is interrupted; note in the PR body that a SIGKILLed run can leave an untracked `provider-teststub<pid>.sh` (a `.gitignore` entry would be outside `## Touches`).

---

## Outcome
- **Status:** completed
- **Completed:** 2026-10-04T16:52:25Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/379
- **Branch:** feature/automate-followups-30-lens-run-test-concurrency-safe
- **Files changed:** 3
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Rubric score:** 6/6
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Children check:** unsettled a086cf547efc062bf (first worker stopped at its 40-turn limit; owner chose proceed — superseded by continuation worker a2b1a0ab5726f36d7)
- **Summary:** case H scoped to this run's recorded pids/pgid; per-run RUN_TAG stub/provider names (also test-lens-compare.sh); timeout 1s→5s + 10s kill poll (clock not deferred — lens-run.sh owns it); new case K holds a released neighbour alive; base 49/49 → branch 60/60; M1–M3 valid mutants red; 6/6 concurrent two-clone runs green on case H; PR CI (Linux) green.

## Not verified
- **per-assertion H/K lines inside the concurrent ci-local runs** — ci-local prints only PASS <s> <file>; per-assertion lines observed in solo runs only (subtask 1)
