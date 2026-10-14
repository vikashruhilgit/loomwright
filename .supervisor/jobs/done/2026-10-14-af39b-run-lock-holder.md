# Supervisor Job: The run lock records a live holder under any harness, and says so when it cannot

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** dirty (1 untracked file: `AI-Radar-All.md`, unrelated), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 (after the owner's 2026-10-14 split — see Feasibility check 5) | **Warnings:** 2 (orphaned worktrees of merged PRs; unrelated untracked file)
- **Source requirement:** .supervisor/requirements/automate-followups/39b-run-lock-and-guard-arm.md
- **Base commit:** adce64f9ce7922984db0a2fb326b115504b46c1b

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 + BSD/GNU `ps`, the same as `run-lock.sh` today; `ps -o lstart=` exists on macOS and procps Linux |
| 2 | Dependency Availability | GO | No new tool. `perl` (already used by `test-run-lock.sh` test 20) stands in for a long-lived non-shell parent; a PATH-stub `ps` (test 21's idiom) fakes session hosts and wrappers |
| 3 | Architecture Fit | GO | One script's holder resolution and reclaim test change; meta stays TSV `key<TAB>value`; every stdout line a consumer parses stays byte-identical |
| 4 | Scope vs Supervisor Capability | CAUTION | ~13 files. Dropping the `CLAUDECODE` gate silently changes two callers that rely on it (the merge watcher, lane close-out), and a test pins the old behaviour; both sit outside the requirement's `## Touches` (see Risk Assessment) |
| 5 | Hard Blockers | CAUTION (was NO-GO) | The requirement's Scope 3 edits `scripts/guard-arm.sh`, which the armed test-integrity guard denies to this run (verified 2026-10-14 on the installed v17.2.0 guard: an Edit payload for `loomwright/scripts/guard-arm.sh` in an armed session → rc 2; `run-lock.sh` → rc 0). **Owner decision (2026-10-14, AskUserQuestion):** split — Scopes 3–4 and owner decision 3 moved to `.supervisor/requirements/automate-followups/39c-guard-arm-trace.md`. This brief carries Scopes 1, 2, 5 (run-lock tests) and 6 (docs) only, with owner decisions 1–2 |

**Overall Verdict:** CAUTION

## Task
**Goal:** Make `run-lock.sh` resolve its liveness holder under any harness — a vendor-neutral `LOOMWRIGHT_HOLDER_PID` first, `CLAUDE_PID` second, an ancestor walk that no longer needs `CLAUDECODE` third, `$PPID` last — fingerprint the holder by its start time so a reused pid reads dead, and print one `run_lock_degraded` line whenever the lock falls back to the bare TTL.

**Problem Statement:**
The owner needs the run lock to keep a second run out for as long as the first one actually lives, under Claude Code, a CI job, a terminal or any other harness.
Currently, outside Claude Code the lock records the invoking shell (`pid_source ppid`), which exits right after `acquire`, so any run longer than 30 minutes can be double-entered (exercised 2026-09-30), and nothing says so at acquire time; a reused pid also reads "alive".
Success looks like: a live non-shell holder is recorded whenever one exists, a named holder can be pinned explicitly, a crashed run under `tmux`/`sshd` stays TTL-reclaimable, a reused pid reads dead, and the degraded case is visible in one stderr line — with every exit code and every parsed stdout line unchanged.

## Acceptance Criteria
- [ ] 1. Given `LOOMWRIGHT_HOLDER_PID=<live pid>` (with or without `CLAUDE_PID` set), when `run-lock.sh acquire` writes meta, then meta records `pid <that pid>` and `pid_source holder_env`; given a dead or non-numeric `LOOMWRIGHT_HOLDER_PID`, then it is ignored and resolution falls through to `CLAUDE_PID` / the walk / `$PPID`.
- [ ] 2. Given `LOOMWRIGHT_HOLDER_PID` unset and a live numeric `CLAUDE_PID`, when acquire writes meta, then `pid_source claude_pid` exactly as today.
- [ ] 3. Given `env -u CLAUDE_PID -u CLAUDECODE` and a live non-shell parent (a `perl` that stays alive) above only shells, when acquire runs, then meta records that parent with `pid_source ancestor` and `kill -0 <pid>` succeeds. `test-run-lock.sh` test 18 is FLIPPED to this (it asserted the old `CLAUDECODE`-gated behaviour) — flipped, not deleted.
- [ ] 4. Given a wrapper (`env`, `timeout`, `xargs`, `sudo`) between the shells and a live non-shell ancestor, when the walk runs, then the wrapper is skipped like a shell and the non-shell beyond it is recorded (`ancestor`); each wrapper name is added with its own test.
- [ ] 5. Given a session host (`tmux`, `screen`, `sshd`, `login`, `Terminal`, `iTerm2`) above only shells/wrappers, when the walk reaches it, then the walk stops: meta records `pid_source ppid` (the invoking shell) and the degraded line prints — the host is NEVER recorded; each host name is added with its own test.
- [ ] 6. Given a recorded `pid_source ppid`, when `acquire` succeeds (fresh, reclaim or re-entrant refresh), then stderr carries exactly one line `run_lock_degraded: pid_source=ppid ttl_only=1800s`, and the exit code and stdout are byte-identical to today's (`''` / `run_lock_reentrant owner=<o> session_id=<id>`); given a held lock whose meta reads `pid_source ppid`, when `status` runs, then stdout is today's `LOCKED owner=<o> pid=<p> age=<s>` byte-for-byte and the same degraded line goes to stderr. No other `pid_source` prints it.
- [ ] 7. Given any acquire that writes meta, when `LC_ALL=C ps -o lstart= -p <holder pid>` yields a non-empty value, then meta gains `pid_start<TAB><that value, surrounding whitespace trimmed>`; when it yields nothing, the `pid_start` key is omitted.
- [ ] 8. Given a held lock whose recorded pid is alive (`kill -0` succeeds), when another session acquires, then: `pid_start` present and different from the pid's current `lstart` ⇒ the holder reads DEAD (reclaimed once age ≥ 1800 s, refused while younger); `pid_start` present and equal ⇒ held (refused at any age); no `pid_start` key ⇒ today's `kill -0`-only rule. TTL, `--force-unlock`, and "BOTH dead AND age ≥ 1800 s" are unchanged.
- [ ] 9. Given the merge watcher (`automate-merge-watch.sh`) or a lane close-out (`automate-lanes.sh` `_lanes_no_host_identity`) running a `closeout` / `finalize-empty` UNDER a live long-lived non-shell ancestor, when that close-out acquires the run lock, then meta records the close-out process itself (`pid_source holder_env`, the pid dead once that close-out exits) — never the ancestor and never the launching Claude session. `test-automate-trail.sh` W/AC14 is FLIPPED from `pid_source ppid` to this (flipped, not deleted) and run under such an ancestor so the old mechanism would fail it; the W-block header comment (`W. merge watcher — OPEN → MERGED ⇒ one closeout + one notify (pid_source`) is updated with it. Every prose surface that explains the old mechanism is rewritten to the `holder_env` one, pointing to `docs/ARCHITECTURE_CONTRACTS.md` §"Run lock": the `automate-merge-watch.sh` comment block, the `automate-lanes.sh` `_lanes_no_host_identity` header, and the `skills/automate-loop/per-item-loop.md` watcher bullet `Why \`CLAUDE_PID\`/\`CLAUDECODE\` are unset` (whose "Unset, the lock meta records `pid_source ppid` — the closeout process" becomes false). Checked by `grep -rn "the closeout process" loomwright/` returning no line that claims `pid_source ppid`. For the lanes half, `test-automate-lanes.sh`'s closeout spy (the `ab-spy.sh` heredoc that already records `CC=\${CLAUDECODE-unset} PID=\${CLAUDE_PID-unset}`) also records `LOOMWRIGHT_HOLDER_PID` and its own `$$`, and the test asserts the two are equal — for the closeout call AND for the `NAME=VALUE`-led finalize-empty call — so deleting the pin from `_lanes_no_host_identity` turns it red.
- [ ] 10. Given a lane launch, when `automate-lanes.sh lane-launch` starts the lane's `claude`, then `LOOMWRIGHT_HOLDER_PID` is unset for it alongside `CLAUDECODE` / `CLAUDE_PID` — a coordinator's holder pin never leaks into a lane's own locks.
- [ ] 11. Given the three acquire callers' prose (automate PICK in `skills/automate-loop/per-item-loop.md` §6 step 1; Supervisor Phase 0 INIT in `agents/supervisor.md` + `skills/supervisor-config/SKILL.md` step 0; `/autonomous` INIT in `skills/autonomous-loop/SKILL.md`) AND their inline command mirrors (`commands/supervisor.md`, `commands/autonomous.md` and `commands/automate.md` — each one's `--max-tokens N` parameter row, which names the run-lock acquire and, for the first two, the `run_lock_reentrant` "NOT a park"/"NOT an abort" line), when a reader follows them, then each says a `run_lock_degraded` stderr line is surfaced (noted once) and is NOT a park — no new gate; `test-run-lock.sh` test 16 (every acquire line passes `--session-id`) still passes.
- [ ] 12. Given a meta written by the new code, when a committed `test-run-lock.sh` leg inspects it, then the original five keys (`pid`, `owner`, `session_id`, `ts`, `pid_source`) keep their names and their order, `pid_start` comes AFTER them, and the base reader's exact lookup (`awk -F'\t' -v k="$key" '$1==k{print $2; exit}'`, copied verbatim into the test as the frozen base `meta_get`) returns, for each of the five keys, exactly what the new `meta_get` returns. No committed test reads git history (CI's suite checkout is depth 1). Separately, as Validation 3 evidence only, the worker runs the real base script once (`git show adce64f:loomwright/scripts/run-lock.sh > <scratch>/old.sh`, then `status` and a dead-pid/old-ts reclaim against a new-code meta) and records the fenced output in `docs/evidence/af39b-run-lock-holder.md`.
- [ ] 13. Given mutation controls (each gated on: mutant non-empty, differs from `run-lock.sh`, `bash -n` clean), when the `CLAUDECODE` gate is re-added around the walk, then AC 3's test goes red; when the `pid_start` comparison is dropped, then AC 8's reuse test goes red.
- [ ] 14. Given the requirement's Validation 2, when the worker runs (a) one real `run-lock.sh acquire --root <scratch>` whose parent chain holds no live non-shell process — produced from inside Claude Code by an orphaned double-fork: `env -u CLAUDE_PID -u CLAUDECODE -u LOOMWRIGHT_HOLDER_PID bash -c '( sleep 2; bash <run-lock.sh> acquire --owner v2:plain --root <scratch> 2><scratch>/err; cp <scratch>/.supervisor/run.lock/meta <scratch>/meta.plain ) & exit 0'`, then waiting for `meta.plain` (the outer shell exits first, so the inner shell is reparented to pid 1 and the walk ends there ⇒ `ppid`) — and (b) one with `LOOMWRIGHT_HOLDER_PID=$$` from a long-lived shell, then the captured meta files and `err` (the degraded line) are written fenced to `docs/evidence/af39b-run-lock-holder.md`, together with the method used (the double-fork, or an owner-run Terminal.app acquire if the reparent target on that machine is not pid 1). Brief conformance is judged on that evidence file. The PR body copy the `/automate` validation gate reads (a `validation 2` line plus the same fenced block) is not produced by FINALIZE's fixed PR-body template and not by the worker: the operator adds it to the PR body (or waives the step at the gate's `AUT-WAIVE` ask).

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

## Cited-line premise check

| ref | resolves | premise | deciding line | as of |
|-----|----------|---------|----------------|-------|
| `scripts/run-lock.sh:173-193` | yes (`loomwright/scripts/run-lock.sh`) | HOLDS | `holder_pid() {` … `if [ -n "${CLAUDECODE:-}" ]; then` | tip 21 minutes ago, fetched <1h |
| `scripts/run-lock.sh:36-38` | yes | HOLDS | `3. \`ppid\` — otherwise the invoking shell (an interactive terminal, a CI` | tip 21 minutes ago, fetched <1h |
| `scripts/run-lock.sh:240-250` | yes | HOLDS (moved to 254) | `pid_alive=0` … `if [ "$pid_alive" -eq 0 ] && [ "$age" -ge "$LOCK_TTL_SECONDS" ]` | tip 21 minutes ago, fetched <1h |

## Touched-file invariants

> Grounded at base `adce64f9ce7922984db0a2fb326b115504b46c1b`. The worker re-checks every entry for the files in its lanes before hand-back.

- **`loomwright/scripts/run-lock.sh`** — keep: `set -u` only (no `set -e`); `LOCK_TTL_SECONDS=1800`; the exit-code contract (acquire `exit 0` / `exit 1`, release and status always `exit 0`); every stdout line byte-identical — `run_lock_held owner=${o} pid=${p} age=${a}` (parsed by `automate-trail.sh`'s closeout refusal reader: `sed -n 's/.*run_lock_held owner=\([^ ]*\).*/\1/p'` and the `pid=\([0-9][0-9]*\)` capture), `run_lock_reentrant owner=${lk_owner} session_id=${SESSION_ID}`, `LOCKED owner=…` (matched by `automate-lanes.sh` fleet-closeout as `"LOCKED owner=$lk_own "*`), `UNLOCKED` (compared by `migrate-branch-mode.sh` as `[ "$lk" = "UNLOCKED" ]`) — the degraded line goes to STDERR only; the meta format `printf 'pid\t%s\n'` TSV, read by `meta_get` and by `session-resume.sh`'s `awk -F'\t' '$1=="pid"{print $2; exit}'` (a new `pid_start` key must not reorder or rename the existing five); reclaim needs BOTH `"$pid_alive" -eq 0` AND `"$age" -ge "$LOCK_TTL_SECONDS"`; never record `$$`; the walk stays bounded (`while [ "$n" -lt 8 ]`) and never records pid 1 (`[ "$p" -gt 1 ]`); bash 3.2 / BSD userland (no `timeout`, no GNU-only `ps` flag; `lstart` read with `LC_ALL=C` so its text does not change with locale). reuse: the `is_shell_comm` basename-and-`-`-strip idiom (`c="${1##*/}"`, `c="${c#-}"`) for the two new name lists; the `case "${CLAUDE_PID:-}" in ''|*[!0-9]*)` numeric guard + `kill -0` shape for `LOOMWRIGHT_HOLDER_PID`. pinned by: `loomwright/scripts/test-run-lock.sh` tests 1–21 — test 18 flips per AC 3; test 11 (`live pid (self) + old ts -> REFUSES`) is RE-SCOPED, not deleted: it runs `run_sut acquire` and then `set_meta_field pid "$$"`, so the meta's new `pid_start` belongs to whatever holder the walk recorded, not to `$$`, and the lock would read dead and be reclaimed. Test 11 must drop the `pid_start` line after `set_meta_field pid` (making it AC 8's "no `pid_start` ⇒ `kill -0`-only" leg); AC 8's "equal ⇒ held" leg sets `pid_start` to `$$`'s own current lstart. Tests 17/20/21 keep passing.
- **`loomwright/scripts/test-run-lock.sh`** — keep: the hermetic first executable line (`hermetic-test-env.sh`, enforced by `scripts/check-test-hermetic.sh`); the `ok`/`no` counters and final `RESULT:` line; test 16's static prose grep (`--session-id` on every acquire line); the mutation-control shape of test 17 (`bash -n "$MUT17"` … `! diff -q "$MUT17" "$SUT"` … `grep -qF` the mutated text) — a mutant that did not apply is reported inconclusive, never a pass; test 21's PATH-stub `ps` idiom (`printf '#!/bin/sh\nexit 1\n' > "$STUB21/ps"`). Every new leg kills the long-lived processes it starts (`kill "$FAKE_PARENT"` … `wait`), so no leaked child holds the runner's stdout.
- **`loomwright/scripts/automate-merge-watch.sh`** — keep: `unset CLAUDE_PID CLAUDECODE`; always exit 0; `set -uo pipefail`; bash 3.2; the single-instance marker logic. Its comment block "CLAUDE_PID / CLAUDECODE are unset HERE as well as by the launcher … Unset, run-lock.sh records `pid_source ppid` — the closeout process" becomes FALSE once the walk is unconditional — rewrite it to the new mechanism (AC 9). pinned by: `loomwright/scripts/test-automate-trail.sh` W `AC14: watcher-driven closeout records pid_source ppid (CLAUDECODE unset by the watcher)` (flip per AC 9) and `AC13` (one closeout, one notify — unchanged).
- **`loomwright/scripts/automate-lanes.sh`** — keep: `_lanes_no_host_identity` still unsets `CLAUDE_PID` and `CLAUDECODE` and still accepts its documented `[NAME=VALUE ...] <cmd> [args...]` form (the finalize-empty caller passes `LOOMWRIGHT_META_SYNC_BIN="$META_SYNC"` first) (pinned by `loomwright/scripts/test-automate-lanes.sh` `CC=\${CLAUDECODE-unset} PID=\${CLAUDE_PID-unset}` on the closeout leg and `H6 env: ceiling 0, CLAUDECODE and CLAUDE_PID unset` on lane-launch); its two callers (lane-convert-ready's closeout, its finalize-empty) keep `2>/dev/null` and their `closeout-classify` read; lane-launch's `local -a envu=(-u CLAUDECODE -u CLAUDE_PID)` gains `-u LOOMWRIGHT_HOLDER_PID` (AC 10). The helper's comment "host identity unset" must say what it now guarantees.
- **`loomwright/scripts/test-automate-trail.sh`, `loomwright/scripts/test-automate-lanes.sh`** — keep the hermetic first line, the spy (`cat .supervisor/run.lock/meta >> "$SPYLOG.meta"` on `trail-pr`), and every other assertion in the W and convert-ready blocks byte-unchanged.
- **Caller prose** (`loomwright/agents/supervisor.md` Phase 0 `Run-lock acquired` bullet, `loomwright/skills/supervisor-config/SKILL.md` step 0, `loomwright/skills/autonomous-loop/SKILL.md` INIT `--max-tokens` paragraph, `loomwright/skills/automate-loop/per-item-loop.md` §6 step 1 `PICK-time run-lock acquire` and the `Why CLAUDE_PID/CLAUDECODE are unset` watcher bullet) — keep every `run-lock.sh acquire … --session-id` line intact (test 16) and the `run_lock_reentrant` "NOT a park" sentence; add the degraded line as one short clause; the watcher bullet is REWRITTEN to the `holder_env` mechanism (AC 9), not merely extended; both point to `docs/ARCHITECTURE_CONTRACTS.md` §"Run lock" rather than restating the resolution order (advisory restated-list rule). `agents/supervisor.md` has a declared budget in `loomwright/docs/prompt-token-budgets.json` (headroom ≈ 2.6k proxy tokens at base) — `scripts/check-token-budget.sh` must stay green.

## Closed enumerations touched

> Sibling grep at base `adce64f`: `grep -rn "claude_pid" loomwright/ scripts/` → hits only in `loomwright/scripts/run-lock.sh` (header + `holder_pid`) and `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Run lock" (the one `pid_source` list outside the script).

- **`pid_source holder_env`** (siblings: `claude_pid`, `ancestor`, `ppid`) — must be named in:
  - `loomwright/scripts/run-lock.sh` — the header `Resolution order (recorded as \`pid_source\`)` list (now four entries) and `holder_pid()`.
  - `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Run lock" — the resolution sentence `resolved in order and recorded as \`pid_source\`` — rewrite to the four-step order (the `ancestor` entry loses "under Claude Code (`CLAUDECODE` set)").
  - The meta-key list in both places (`pid, owner, session_id, ts, pid_source`) gains `pid_start`.
- **Walk skip lists** — two new closed lists owned by `run-lock.sh` (wrappers: `env timeout xargs sudo`; session hosts: `tmux screen sshd login Terminal iTerm2`). Docs point to the script; they never restate the names.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| test 18 (flipped) — no Claude env, live `perl` parent ⇒ `ancestor` | re-wrap the walk in `if [ -n "${CLAUDECODE:-}" ]; then … fi` ⇒ `ppid` recorded, test red (AC 13's control) |
| `holder_env` leg — live `LOOMWRIGHT_HOLDER_PID` | delete the `LOOMWRIGHT_HOLDER_PID` branch of `holder_pid()` ⇒ `claude_pid`/`ancestor` recorded, test red |
| `holder_env` dead/non-numeric leg | drop the `kill -0` on `LOOMWRIGHT_HOLDER_PID` ⇒ the dead pid is recorded, test red |
| wrapper legs (`env`/`timeout`/`xargs`/`sudo`) | remove that name from the wrapper list ⇒ the wrapper's pid is recorded as `ancestor`, test red |
| session-host legs (`tmux`/`screen`/`sshd`/`login`/`Terminal`/`iTerm2`) | remove that name from the host list ⇒ the host is recorded as `ancestor`, test red |
| degraded acquire line | delete the stderr `run_lock_degraded` print in acquire ⇒ test red |
| degraded `status` line | delete it from `cmd_status` ⇒ test red; print it on STDOUT instead ⇒ the "stdout byte-identical" assertion red |
| `pid_start` recorded | delete the `printf 'pid_start\t%s\n'` line ⇒ test red |
| pid reuse ⇒ reclaimable (AC 8) | drop the `pid_start` comparison from the liveness test ⇒ reused pid reads alive, refused, test red (AC 13's control) |
| no-`pid_start` meta keeps `kill -0`-only | treat a missing `pid_start` as dead ⇒ live-self/old-ts lock reclaimed, test red |
| compatibility leg (AC 12) | rename an existing meta key (e.g. write `pid_src`) or write `pid_start` before `pid` ⇒ the frozen base `meta_get` / key-order assertion differs, test red |
| test 11 (re-scoped) — no-`pid_start` meta, live self, old ts ⇒ refused | remove the `kill -0` half of the liveness test (keep only the `pid_start` compare) ⇒ test red |
| AC14 (flipped) — watcher close-out holder | delete the watcher's holder pin ⇒ under the fixture's live non-shell ancestor the meta reads `ancestor`, test red |
| lanes close-out holder (AC 9) | delete the pin from `_lanes_no_host_identity` ⇒ test red |
| lane-launch env (AC 10) | drop `-u LOOMWRIGHT_HOLDER_PID` from `envu` ⇒ the stub's `ENV` line shows it set, test red |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | run-lock holder resolution + start-time fingerprint + degraded line, its two close-out callers, docs | all | 12 modify, 2 create | `skills/unit-testing/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/scripts/run-lock.sh", name: "LOOMWRIGHT_HOLDER_PID"}
  - {kind: "symbol", path: "loomwright/scripts/run-lock.sh", name: "holder_env"}
  - {kind: "symbol", path: "loomwright/scripts/run-lock.sh", name: "pid_start"}
  - {kind: "symbol", path: "loomwright/scripts/run-lock.sh", name: "run_lock_degraded"}
  - {kind: "symbol", path: "loomwright/scripts/test-run-lock.sh", name: "holder_env"}
  - {kind: "symbol", path: "loomwright/scripts/test-run-lock.sh", name: "pid_start"}
  - {kind: "symbol", path: "loomwright/scripts/automate-merge-watch.sh", name: "LOOMWRIGHT_HOLDER_PID"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "LOOMWRIGHT_HOLDER_PID"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-trail.sh", name: "holder_env"}
  - {kind: "symbol", path: "loomwright/docs/ARCHITECTURE_CONTRACTS.md", name: "holder_env"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/per-item-loop.md", name: "run_lock_degraded"}
  - {kind: "symbol", path: "loomwright/agents/supervisor.md", name: "run_lock_degraded"}
  - {kind: "symbol", path: "loomwright/skills/supervisor-config/SKILL.md", name: "run_lock_degraded"}
  - {kind: "symbol", path: "loomwright/skills/autonomous-loop/SKILL.md", name: "run_lock_degraded"}
  - {kind: "symbol", path: "loomwright/commands/supervisor.md", name: "run_lock_degraded"}
  - {kind: "symbol", path: "loomwright/commands/autonomous.md", name: "run_lock_degraded"}
  - {kind: "symbol", path: "loomwright/commands/automate.md", name: "run_lock_degraded"}
  - {kind: "file", path: "changelog.d/af39b-run-lock-holder.md"}
  - {kind: "file", path: "docs/evidence/af39b-run-lock-holder.md"}
requires: []
lanes:
  - "loomwright/scripts/run-lock.sh"
  - "loomwright/scripts/test-run-lock.sh"
  - "loomwright/scripts/automate-merge-watch.sh"
  - "loomwright/scripts/automate-lanes.sh"
  - "loomwright/scripts/test-automate-trail.sh"
  - "loomwright/scripts/test-automate-lanes.sh"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/agents/supervisor.md"
  - "loomwright/skills/supervisor-config/SKILL.md"
  - "loomwright/skills/autonomous-loop/SKILL.md"
  - "loomwright/skills/automate-loop/per-item-loop.md"
  - "loomwright/commands/supervisor.md"
  - "loomwright/commands/autonomous.md"
  - "loomwright/commands/automate.md"
  - "changelog.d/af39b-run-lock-holder.md"
  - "docs/evidence/af39b-run-lock-holder.md"
external_requires:
  - "ps with -o comm=, -o ppid= and -o lstart= (BSD/macOS and procps Linux)"
  - "perl (long-lived non-shell parent in tests; already used by test-run-lock.sh test 20)"
```

### Design notes for the worker (decided here; do not re-open)
- **`holder_pid()` order (owner decision 1):** (1) `LOOMWRIGHT_HOLDER_PID` — numeric and `kill -0` alive ⇒ `holder_env`; (2) `CLAUDE_PID`, same test ⇒ `claude_pid`; (3) the walk from `$PPID`, unconditional: a shell or a WRAPPER (`env timeout xargs sudo`) ⇒ step to its parent; a SESSION HOST (`tmux screen sshd login Terminal iTerm2`) ⇒ stop the walk (go to step 4 — the host is never recorded); any other comm with pid > 1 ⇒ `ancestor`; pid 1, an empty `ps`, or 8 steps ⇒ step 4; (4) `$PPID` ⇒ `ppid`. Names are matched after the existing basename + leading-`-` strip.
- **Start-time fingerprint (owner decision 2):** `pid_start` = `LC_ALL=C ps -o lstart= -p <pid>` with surrounding whitespace trimmed, written by `write_meta` (all three writers — fresh, reclaim, re-entrant refresh) only when non-empty. Liveness at reclaim: `kill -0` succeeds AND (no `pid_start` key OR the pid's current trimmed `lstart` equals it). Honest limit, stated in the header: a live pid whose `lstart` cannot be read now, while meta holds a `pid_start`, compares unequal and so reads dead — the owner's "alive only when equal" rule; reclaim still also needs age ≥ 1800 s.
- **Degraded line:** `acquire` prints it to stderr after any successful meta write whose source is `ppid`; `status` prints it to stderr when the held lock's meta reads `pid_source ppid`. Stdout is never touched.
- **The two close-out callers (AC 9) — why and how.** Today the merge watcher (`unset CLAUDE_PID CLAUDECODE`) and lane close-out (`_lanes_no_host_identity`) make closeout's lock record the close-out process ONLY because the walk is gated on `CLAUDECODE`. Ungated, a close-out started under a live non-shell ancestor (an un-detached watcher, the lane coordinator's own `claude`) would record that ancestor, so a close-out that crashed without its trap would leave a lock nobody can reclaim while the ancestor lives — the exact failure the watcher's comment says it prevents. Pin the holder to the close-out process: run the close-out as `bash -c 'LOOMWRIGHT_HOLDER_PID=$$; export LOOMWRIGHT_HOLDER_PID; exec env "$@"' _ <the existing command…>` — `exec env "$@"` (not `exec "$@"`) so leading `NAME=VALUE` pairs still apply, and both `exec` and `env`'s own exec keep the pid, so `$$` IS the close-out process — still under the `CLAUDE_PID`/`CLAUDECODE` unset. In the watcher this wraps its `closeout` call; in `automate-lanes.sh` it goes inside `_lanes_no_host_identity` (`env -u CLAUDE_PID -u CLAUDECODE bash -c '…; exec env "$@"' _ "$@"`), so both of its callers — including the `NAME=VALUE`-led finalize-empty call — inherit it. The AC14 test runs the watcher under a fixture `perl` parent that stays alive (test 20's shape) and asserts `pid_source holder_env` with a pid that is dead after the watcher exits.
- **Tests that fake a process tree:** use a PATH-stub `ps` (test 21's idiom) that answers `comm=` / `ppid=` / `lstart=` from a small table keyed by pid, so host and wrapper legs are deterministic on macOS and Linux; use a real long-lived `perl` only where a live pid is needed (AC 3, AC 9). The pid-reuse leg writes meta by hand (`set_meta_field`): `pid` = a live pid the test owns, `pid_start` = a deliberately different string, `ts` = old.
- **Vendor ratchet:** `run-lock.sh` loses its `CLAUDECODE` reference in code (count may fall); `test-run-lock.sh`'s mutation control re-adds the literal, so raise that path's allowance in `loomwright/docs/vendor-coupling-manifest.json` with a reason (`mutation control re-adds the CLAUDECODE gate`). `LOOMWRIGHT_HOLDER_PID` is not a vendor token. Run `scripts/check-vendor-coupling.sh` after `git add`.

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Scope beyond the requirement's `## Touches`: the ungated walk changes the merge watcher's and lane close-out's holder, and `test-automate-trail.sh` AC14 pins the old `pid_source ppid` (Feasibility (Phase 2.5)) | HIGH | AC 9 pins the close-out process explicitly (`holder_env`); `automate-merge-watch.sh`, `automate-lanes.sh`, `test-automate-trail.sh`, `test-automate-lanes.sh` added to lanes; AC14 flipped, run under a live non-shell ancestor so the old mechanism fails it |
| The requirement's guard half cannot run in an armed session (Feasibility (Phase 2.5), check 5) | MEDIUM | Owner split 2026-10-14: Scopes 3–4 live in `39c-guard-arm-trace.md` (not enqueued); this brief touches no guard-protected file (`guard-arm.sh`, `guard-test-integrity.sh`, `hooks.json`, `host-mode.sh` are NOT in lanes) |
| A walk that records the wrong process: a long-lived non-shell that is not the run (CI's runner agent, an IDE) | MEDIUM | That is the owner's decision 1 (record it; hosts excepted). `LOOMWRIGHT_HOLDER_PID` lets any harness name the right process; the header states the limit |
| Consumers of `run-lock.sh` output break on a format change | MEDIUM | Degraded line on stderr only; AC 6 asserts stdout byte-identical; consumers named in Touched-file invariants (closeout refusal reader, fleet-closeout, migrate-branch-mode, session-resume) |
| Test legs leak long-lived `perl`/stub processes and hang the piped suite (the leaked-child lesson) | MEDIUM | Every leg kills and `wait`s what it started; worker runs the changed tests piped through `tail` once to prove no hang |
| `ps -o lstart=` output differs across locales/platforms | LOW | `LC_ALL=C`, trimmed; compared only against the value the same machine wrote |

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-14-af39b-run-lock-holder.md
```

## Plan Review
- **Reviewer decision:** PASS (attempt 3/3) | **Attempts:** 3/3
- **Attempt 1:** FAIL — 2 HIGH (AC 12 read git history in a depth-1 CI checkout; AC 14's plain-terminal recipe cannot yield `ppid` once the walk is ungated), 1 MEDIUM (test 11 breaks under `pid_start`), 3 LOW — all fixed.
- **Attempt 2:** PASS — 1 MEDIUM (stale per-item-loop.md watcher prose not required to be rewritten), 1 LOW (PR-body validation line owner) — both fixed.
- **Attempt 3:** PASS — 1 MEDIUM (command mirrors not in lanes), 3 LOW (lanes pin row had no backing assertion; wrong sibling-grep hit; changelog slug named the split-off guard half).

| # | Severity | Section | Description | Resolution |
|---|----------|---------|-------------|------------|
| 1 | MEDIUM | AC 11 / lanes | commands/supervisor.md, autonomous.md, automate.md mirrors omitted | fixed (owner override — post-PASS edit, not re-reviewed: cap exhausted) |
| 2 | LOW | AC 9 / Pin mutations | lanes close-out pin had no assertion | fixed (owner override, not re-reviewed) |
| 3 | LOW | Closed enumerations | sibling grep listed test-run-lock.sh | fixed (owner override, not re-reviewed) |
| 4 | LOW | Subtask Contracts | changelog slug `af39b-run-lock-and-guard-arm` | fixed → `af39b-run-lock-holder` (owner override, not re-reviewed) |

**Owner decision (2026-10-14, Phase 6):** "Apply 4 fixes, then save" — the four post-PASS edits above were applied without a fourth review; Phase 4.5 is the next lens on them.

## Outcome
- **Status:** completed
- **Completed:** 2026-10-14T11:01:07Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/542
- **Branch:** feature/af39b-run-lock-holder
- **Files changed:** 21
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** armed (guard_armed: ok at INIT)
- **Summary:** run-lock.sh records a live holder under any harness (LOOMWRIGHT_HOLDER_PID > CLAUDE_PID > ungated walk skipping shells/wrappers, stopping at session hosts > PPID), fingerprints it by a TZ/locale-pinned start time (single holder_alive rule, read-only `liveness [--pid]` subcommand read by session-resume.sh and the closeout refusal), prints run_lock_degraded on stderr only; merge watcher + lane close-out pin the holder to the close-out process. Phase 4.5: 3 reviews (FAIL → FAIL → PASS), 2 fix rounds (4cf6a58 TZ/locale pin + one liveness rule; 35b8303 closeout refusal reads liveness --pid); risk_classification high_risk true (advisory); ground_truth 2/2; contract_conformance pass (1 evaluated); rules gate none; 5 LOW findings dismissed below the MEDIUM floor; pin-mutation gate 15 unverified (prose rows — held by hand by the reviewer for the CLAUDECODE gate, pid_start compare, lanes pin and watcher pin).

## Not verified
- **Linux CI: procps `ps -o lstart=` output and GNU comm names for env/timeout/xargs/sudo** — no local Linux runtime; GitHub CI runs the suite (subtask 1)
- **A real tmux/screen/sshd/login/Terminal/iTerm2 process tree** — host and wrapper legs use a PATH-stub ps over a pid table (subtask 1)
- **The /automate PR-body validation 2 line** — operator-owned per AC 14; the main thread pasted the evidence block into the PR body at FINALIZE (subtask 1)
