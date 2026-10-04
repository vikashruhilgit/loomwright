# Supervisor Job: Shared CI slots — every checkout of one repo on a machine shares N CI slots, one fair queue and one pass cache

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes-v2/w1-08
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/parallel-automate/08-shared-ci-slots.md
- **Base commit:** 95e86013e2f6511f37540de499d7b95816b71303

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure bash 3.2 + BSD userland, same as the existing `scripts/ci-local.sh` lock it replaces |
| 2 | Dependency Availability | GO | Needs only `mkdir`, `kill -0`, `git`, `shasum`/`cksum`, `sysctl`/`getconf` — all present; no `flock` (macOS has none) |
| 3 | Architecture Fit | GO | Generic helper under `loomwright/scripts/` (plugin code), consumed by the repo-root `scripts/ci-local.sh`; files+pids only, no daemon |
| 4 | Scope vs Supervisor Capability | GO | 7 files, est. ~700 changed lines — below the `context-bound` threshold; single subtask |
| 5 | Hard Blockers | GO | None |

**Overall Verdict:** GO

## Task
**Goal:** Add a generic, shipped slot helper `loomwright/scripts/ci-slot.sh` and make `scripts/ci-local.sh` use it, so every checkout of the same repository on one machine (primary, linked worktrees, lane clones) shares ONE pool of N CI slots, ONE fair waiting queue and ONE pass cache, keyed by repository identity instead of git dir.

**Problem Statement:**
The operator running parallel lanes needs 5–10 lane clones of this repo to run the full local suite without oversubscribing the machine N times.
Currently `scripts/ci-local.sh` keeps its "ONE RUN AT A TIME" lock and its PASS cache in `git rev-parse --git-common-dir`/loomwright-ci-local/. A lane is a separate local CLONE (decision P4 in `.supervisor/requirements/parallel-automate/00-overview.md`), so each lane has its own git dir, its own lock and its own cache; every run takes `SELF_TEST_JOBS` = every CPU. Measured (S1 v2, two lanes on a 12-core Mac): a run alone 190–380 s, both at once 490–820 s; load average 27 vs 10.
Success looks like: at most N suites run at once across all checkouts of the repo, the rest wait in ticket order and print their position, each run uses `max(2, floor(CPUs/N))` jobs, and a tree that passed in any checkout returns `PASS (cached)` in every other.

### Design (from the source requirement — the worker implements this exactly)
1. **`loomwright/scripts/ci-slot.sh`** (plugin code — no repo-local or vendor-specific paths):
   - Subcommands: `acquire <name> --pid <holder-pid> [--slots N] [--wait S]` → on success prints ONLY `slot=<k> jobs=<j>` on stdout; `release --pid <holder-pid>` (or `--slot <k>`) frees only that holder's slot (and that pid's ticket, if still queued); `status [--json]` → holders (pid, checkout path, lane/name, started) and waiters in queue order; `dir` → prints the repo-keyed state dir (read-only, creates nothing beyond `mkdir -p`) so `ci-local.sh` never re-derives the key. A `--help` that prints the header comment block, like `ci-local.sh`.
   - **Holder identity (load-bearing):** the pid recorded in a slot (and in a ticket) is the `--pid` the caller passes — `ci-local.sh` passes its own `$$`, the long-lived run. Never the helper's own pid or `$PPID`: `acquire` exits right after printing, and is typically called inside `$(...)`, so its own pid is dead at once — every later caller would take the slot over and the limit would silently vanish. `--pid` is required for `acquire`; refuse (exit 2) without it.
   - **stdout vs. stderr:** progress/wait lines and diagnostics go to STDERR; stdout carries only the machine-readable result, so `$(ci-slot.sh acquire …)` parses cleanly.
   - **Origin assumption (state honestly in the header of both scripts):** sharing assumes every checkout's `origin` is the same remote URL (lane-create in item 05 guarantees this); a clone whose `origin` is a local filesystem path keys separately and does not share.
   - **Shared location keyed by repository identity:** `${XDG_STATE_HOME:-$HOME/.local/state}/loomwright/ci-slots/<repo-key>/`. `<repo-key>` = a hash of the NORMALISED `origin` URL (strip a trailing `.git` and `/`, reduce `git@host:owner/repo`, `ssh://`, `https://` forms to one canonical string — follow the normalisation `loomwright/scripts/resolve-egress-config.sh` already does for its repo slug, and use the whole normalised URL including host, not only `owner/repo`, so two hosts never collide). No `origin` ⇒ fall back to a hash of the absolute git-common-dir path (today's per-repo behaviour).
   - **N slots:** default `max(1, floor(CPUs / 6))`; override `LOOMWRIGHT_CI_SLOTS` (or `--slots`). CPU count via `getconf _NPROCESSORS_ONLN`, else `sysctl -n hw.ncpu`, else 4. Each slot is an atomic `mkdir` lock dir holding its pid (and checkout path, name, start time). A slot whose holder pid is dead (`kill -0` fails) is taken over — today's rule.
   - **Fair queue:** a waiter takes a ticket from an atomic counter (guarded by a short `mkdir` mutex — no `flock`); a free slot goes only to the LOWEST LIVE ticket, so no run starves. A waiter whose pid is dead has its ticket skipped (and cleaned). A waiter that gives up after `--wait S` removes its own ticket and exits non-zero.
   - **`release` is idempotent:** it exits 0 when the pid holds no slot and no ticket (so `ci-local.sh`'s EXIT trap is safe on `--list`, a cached PASS, or a failed/timed-out acquire — keep a `have_lock`-style guard anyway and call it `|| true` in the trap).
   - **Canonical origin form (for `<repo-key>`):** lowercase host + `/` + path, with scp-style `git@host:owner/repo` mapped to `host/owner/repo`, scheme/user/port stripped, trailing `.git` and `/` removed; the key is a hash of that string. Equality ACROSS URL forms (e.g. one clone on ssh, another on https) is best-effort and NOT an acceptance criterion — lanes share one origin URL by construction (item 05).
   - **Stale mutex:** the counter mutex dir records its holder pid; a mutex whose pid is dead (or that is older than a short bound, e.g. 30 s, when the pid file is missing) is taken over, so a process SIGKILLed between `mkdir` and `rmdir` can never block every checkout until `--wait` expires.
   - **Job share:** `jobs = max(2, floor(CPUs / N))`.
   - bash 3.2 / BSD userland safe; no `flock`, no GNU-only flags, no `timeout`; `stat`/`date` used portably (see CLAUDE.md global notes).
2. **`scripts/ci-local.sh`:** it gets the shared state dir from `ci-slot.sh dir` (needed BEFORE locking, because the PASS-cache check and `--list` run before the lock); the `mkdir "$lockdir"` lock loop becomes `ci-slot.sh acquire ci-local --pid $$ --wait "$CI_LOCAL_LOCK_WAIT"`, and the EXIT trap runs `ci-slot.sh release --pid $$`; `SELF_TEST_JOBS` is set from the printed job share unless the caller set `SELF_TEST_JOBS` explicitly (explicit wins); release in the EXIT trap. The PASS-cache stamps move to the same shared repo-keyed directory (e.g. `<state>/ci-slots/<repo-key>/pass/`) so a tree that passed in any checkout is cached for all. Unchanged: the content key, a waiter re-checking the PASS cache right after it gets a slot (so a holder that just verified the same tree short-circuits it), the tree-moved-mid-run rule ("NOT cached"), "only passes are cached", a failure removing the stamp, `--force`, `--list`, `--help`. `CI_LOCAL_LOCK_WAIT` keeps its meaning (passed as `--wait`). `git-common-dir` remains ONLY as the no-origin fallback. The header comment blocks "PASS CACHE" and "ONE RUN AT A TIME" are rewritten to describe the shared slots.
3. **Visible waiting:** while waiting, one line every 30 s: `waiting for a CI slot — position <p>, holders: <name> (<age>), …` (the 30 s period may be overridable by an env var for tests).
4. **`AGENT_GUIDELINES.md` §"Pre-push: one command"** gains one sentence: concurrent sessions and lane clones share slots automatically; never raise `LOOMWRIGHT_CI_SLOTS` to "go faster". Adjust the existing "Only one full run happens at a time per repo" sentence so it is not contradicted.
4a. **`CLAUDE.md` §"Pre-push test run?"** — the phrase "lets only one run go at a time" becomes false; replace it minimally (e.g. "shares a few CI slots and one pass cache across every checkout of the repo"), keeping the `AGENT_GUIDELINES.md` §"Pre-push: one command" pointer as it is. No other CLAUDE.md change.
5. **Changelog fragment** `changelog.d/parallel-automate-08-shared-ci-slots.md` (format: `changelog.d/README.md`). Do NOT bump versions or hand-edit `CHANGELOG.md` / manifests.

**Non-goals:** no change to WHAT runs (item 09) or to the remote `ci` job; no daemon or server process — files and pids only.

## Acceptance Criteria
- [ ] Given two checkouts of one repository with the same `origin` (a clone and a linked worktree, or two clones), when each runs `ci-slot.sh acquire`, then both use the same `<state>/ci-slots/<repo-key>/` directory and compete for the same slot set.
- [ ] Given two repositories with different `origin` URLs, when each acquires, then they use different `<repo-key>` directories and never share slots or cache stamps.
- [ ] Given a repository with no `origin`, when it acquires, then the key is derived from its git-common-dir path (today's per-repo behaviour).
- [ ] Given N=2 and three concurrent acquirers, when all three call `acquire`, then exactly 2 hold slots, the third waits, and on a release the third gets a slot in ticket order (lowest live ticket first).
- [ ] Given a slot whose holder pid is dead, when another caller acquires, then the slot is taken over.
- [ ] Given a waiter whose pid died while queued, when a slot frees, then its ticket is skipped and the next live ticket gets the slot.
- [ ] Given CPU counts and N in {1, 2, 4}, when the job share is computed, then it equals `max(2, floor(CPUs / N))`; and the default N equals `max(1, floor(CPUs / 6))` unless `LOOMWRIGHT_CI_SLOTS` overrides it.
- [ ] Given a caller that sets `SELF_TEST_JOBS` explicitly, when `ci-local.sh` runs, then that value is passed through unchanged; otherwise the slot's job share is used.
- [ ] Given a tree that passed `ci-local.sh` in one clone, when another clone of the same origin runs `ci-local.sh` on an identical tree, then it prints `PASS (cached)` and runs nothing.
- [ ] Given a run waiting for a slot, when it waits, then it prints `waiting for a CI slot — position <p>, holders: …` periodically, and `ci-slot.sh status --json` lists holders (pid, checkout path, name, started) and waiters in queue order.
- [ ] Given the change, when `grep -n 'git-common-dir' scripts/ci-local.sh` runs, then it appears only as the no-origin fallback; the per-clone `loomwright-ci-local/lock` no longer exists.
- [ ] Given a holder whose `acquire` call has already exited but whose `--pid` process is still alive, when another caller acquires with all slots held, then that slot is NOT taken over (the holder pid is the caller's, not the helper's).
- [ ] Given a pre-planted counter mutex dir whose recorded pid is dead, when `acquire` runs, then it takes the mutex over and does not block.
- [ ] Given a waiter with `--wait 1` and every slot held by live pids, when the wait expires, then `acquire` exits non-zero, its ticket is gone, and `status --json` no longer lists it.
- [ ] Given `acquire` is waiting, when its stdout is captured, then stdout holds only `slot=<k> jobs=<j>` and every progress line went to stderr.
- [ ] Given a single checkout with no other session, when `ci-local.sh` runs, then it behaves as today apart from the lock line and the job share (the full CPU count only when N=1); every existing `test-ci-local.sh` arm still passes, updated where the lock/cache location moved and where the fixture must carry `ci-slot.sh` and a sandboxed `XDG_STATE_HOME`.
- [ ] Given `ci-local.sh --list`, or a run that exits early on `PASS (cached)`, when the EXIT trap runs, then the exit status is still 0 (`release` with nothing held is a no-op exit 0).
- [ ] Given a waiter queued behind a holder that stamps the same tree, when the waiter gets the slot, then it prints `PASS (cached)` and runs nothing.
- [ ] Given the change, when `grep -n 'at a time' CLAUDE.md` runs, then §"Pre-push test run?" no longer claims only one run at a time.
- [ ] Given the full suite, when `bash scripts/ci-local.sh` runs on the branch, then it is green.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Shared CI slot helper + ci-local.sh wiring + tests + guideline + changelog fragment | all | 4 modify, 3 create | `skills/unit-testing/SKILL.md`, `skills/ci-cd/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/ci-slot.sh"}
  - {kind: "file", path: "loomwright/scripts/test-ci-slot.sh"}
  - {kind: "file", path: "changelog.d/parallel-automate-08-shared-ci-slots.md"}
  - {kind: "symbol", path: "scripts/ci-local.sh", name: "ci-slot.sh"}
  - {kind: "symbol", path: "AGENT_GUIDELINES.md", name: "LOOMWRIGHT_CI_SLOTS"}
requires: []
lanes:
  - "loomwright/scripts/ci-slot.sh"
  - "loomwright/scripts/test-ci-slot.sh"
  - "scripts/ci-local.sh"
  - "scripts/test-ci-local.sh"
  - "AGENT_GUIDELINES.md"
  - "CLAUDE.md"
  - "changelog.d/parallel-automate-08-shared-ci-slots.md"
external_requires:
  - "bash 3.2 + BSD userland (macOS); no flock binary"
```

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md`, `skills/ci-cd/SKILL.md` |

## House Rules

> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- Wording that carries a contract — a heading a gate greps for, a sentence that states a guarantee — is treated as an interface: renaming it is a change to that interface and its consumers move with it.
  - id: documentation-wording-that-carries-a-contract-a-heading-a-gate-greps-for-a-sentence-that-states-a-guarantee-is-treated-as-an-interface-renaming-it-is-a-change-to-that-interface-and-its-consumers-move-with-it
  - enforcement: advisory
  - category: documentation
  - check (data only, NOT executed by this reader): (none)
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

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Tests write to the developer's real `~/.local/state/loomwright/ci-slots/` and collide with live lane runs | HIGH | Every test (`test-ci-slot.sh`, `test-ci-local.sh`) sets `XDG_STATE_HOME` to a `mktemp -d` sandbox before any call; assert the real state dir is untouched |
| Race in ticket counter / slot handoff (two waiters both see themselves as lowest, or a slot freed between check and mkdir) | HIGH | Ticket increment under a `mkdir` mutex; slot claim is the atomic `mkdir` itself; a waiter claims only when its ticket is the lowest LIVE ticket, re-checked after every failed claim. Fairness test with N=2 and 3 acquirers asserts order; mutation control: remove ticket ordering ⇒ the fairness test must fail |
| Slot recorded under the helper's own short-lived pid ⇒ every holder looks dead, the limit silently vanishes | HIGH | `acquire --pid` is required and ci-local passes `$$`; test with a long-lived holder process whose `acquire` call has already exited |
| Stale counter mutex left by a SIGKILLed process blocks every checkout until `--wait` expires | MEDIUM | Mutex records its pid; dead-pid (or age-bounded) takeover; test with a pre-planted dead-pid mutex |
| Solo runs on machines with ≥12 CPUs get half the jobs by default (N=2 ⇒ 6 jobs on this Mac) | LOW | Documented in the AC and the guideline sentence; `SELF_TEST_JOBS` or `LOOMWRIGHT_CI_SLOTS=1` restores the old behaviour |
| A clone whose `origin` is a local path keys separately and silently stops sharing | LOW | Stated in both script headers; lane-create (item 05) sets origin to the remote URL |
| pid-reuse makes a dead holder look alive (`kill -0` on a recycled pid) | MEDIUM | Same posture as today's lock; record start time in the slot dir and state the limit in the header honestly |
| Keying by git dir silently regresses (two checkouts no longer share) | MEDIUM | Two-checkout (clone + worktree) test; mutation control: key by git-common-dir ⇒ that test must fail |
| `check-test-hermetic.sh` fails the new test | MEDIUM | `test-ci-slot.sh` sources `loomwright/scripts/hermetic-test-env.sh` as its first executable line (AGENT_GUIDELINES §"Egress-hermetic self-tests") |
| `check-vendor-coupling.sh` breach — `loomwright/scripts/` is a CORE path | MEDIUM | Do not write any manifest vendor token (`CLAUDE_PLUGIN_ROOT`, `CLAUDE_CODE_`, `claude -p`, `.claude/`) into `ci-slot.sh` / `test-ci-slot.sh` |
| Prior churn on `AGENT_GUIDELINES.md` (16 postmortem entries: drain_churn, convention_mismatch, self_heal_miss) — source: Prior churn (postmortem ledger) | MEDIUM | Keep the guideline edit to one sentence plus the minimal adjustment of the contradicting "one full run at a time per repo" sentence; re-read the whole §"Pre-push: one command" after editing |
| Timing-sensitive concurrency tests flake under the loaded pool | MEDIUM | Poll with bounded waits rather than fixed sleeps; mark `test-ci-slot.sh` `# run-self-tests: serial` if it spawns concurrent acquirers; use a short wait-print period override in tests |
| Item 09 (ci-local fewer full runs) also edits `scripts/ci-local.sh` in another lane | LOW | Keep the diff confined to the lock/cache/jobs blocks; no change to WHAT runs |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-04-shared-ci-slots.md
```

## Plan Review: PASS (attempt 3/3)
Open LOW notes (follow-ups, not blocking): (1) the three-clone running-system check and baseline counts from the requirement's Validation list are not an AC, so they are a human pre-merge step; (2) holder display label source is unspecified (every ci-local holder is named ci-local); (3) the SELF_TEST_JOBS / LOOMWRIGHT_CI_SLOTS=1 escape should be documented in the ci-local.sh header.

## Outcome
- **Status:** completed
- **Completed:** 2026-10-04T11:51:32Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/375
- **Branch:** feature/parallel-automate-08-shared-ci-slots
- **Files changed:** 7
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Added repo-keyed loomwright/scripts/ci-slot.sh (N shared slots, fair lowest-live-ticket queue, caller --pid holders, stale slot/mutex takeover, idempotent release, status --json, dir) and wired scripts/ci-local.sh to it with a shared pass cache and slot job share. Phase 4.5 iteration 1 FAIL (HIGH: queued run deferred TERM/INT for its whole wait budget) fixed in 297e9e4 with backgrounded acquire + wait; iteration 2 PASS. Ground truth 2/2 (doc-currency-green, version-consistent). 5 below-floor findings dismissed (2 MEDIUM, 1 LOW, 2 nit) — see PR #375 marker comment.

## Not verified
- **three-clone running-system check on real lane clones** — needs multiple real lane clones running ci-local.sh concurrently; the brief lists it as a human pre-merge step (subtask 1)
