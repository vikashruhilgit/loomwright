# Supervisor Job: Lane coordinator — `/automate --parallel N` (parallel-automate/05)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/parallel-automate/05-lane-coordinator.md
- **Base commit:** 51dd5db058f0162c944791df42774b649f55d6bf

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure bash 3.2 / BSD-userland scripts + markdown prose, same stack as every `automate-*` helper. |
| 2 | Dependency Availability | GO | All `## Depends on` items carry done stamps and their code is on `main` (`plan-waves` in `automate-helpers.d/plan-waves.sh`, `ci-slot.sh`, `machine-load.sh`, branch-mode `trail-pr`, non-interactive gates). Prototype to port: the operator harness `s1h.sh` / `s2-sampler.sh` (outside the repo, described in Risk Assessment). |
| 3 | Architecture Fit | GO | New sibling script dispatched from `automate-helpers.sh` exactly like `automate-trail.sh` / `automate-dismissed.sh`; lanes are local clones, so every lane-local contract (run lock, `.auto_review` toggle, owned drain) holds unchanged. |
| 4 | Scope vs Supervisor Capability | CAUTION | 31 files, two new ~1–2k-line scripts — far over one worker's context; split `context-bound` into 6 subtasks with file-disjoint lanes. |
| 5 | Hard Blockers | GO | None. Validation 4 (a real `--parallel 2` run) needs the owner's go and two throwaway items — operator step after the PR, not a worker step. |

**Overall Verdict:** CAUTION

## Task
**Goal:** Ship `/automate --parallel N`: a lane coordinator that runs up to N independent Queue items at once, each in an isolated local clone ("lane"), tracked by one coordinator in the primary checkout — with no lane code path entered when the flag is absent or N = 1.

**Problem Statement:**
The owner needs independent Queue items to progress concurrently because one `/automate` run processes one item at a time (RUN took 1h14–4h37 per item) and nothing else starts until that item's PR merges. Currently parallel runs exist only as an operator harness (`s1h.sh`, `s2-sampler.sh`, ad-hoc monitors) that dies with the operator session and needs hand-relayed questions, hand closeout and hand hardware protection. This causes hours of serial waiting, and three S3 waves of manual operator work. Success looks like `/automate --parallel 2` on two disjoint items reaching two READY PRs, each lane's gates relayed to the owner, with the primary refusing a second run meanwhile and the machine guarded by admission, not by a human watching load.

**THE REQUIREMENT FILE IS THE AUTHORITATIVE SPEC.** Each subtask below names the requirement Scopes it implements; the worker MUST read those Scopes in full in `.supervisor/requirements/parallel-automate/05-lane-coordinator.md` (including every "Amended 2026-10-0x" block and §"Spike findings" — the exact `claude -p` flags that worked are there) before writing code. This brief adds the design decisions below; where it is silent, the requirement governs.

### Design decisions (binding for all subtasks)
- **D1 — Lane shape A + relay** (requirement §"Spike findings", Q7). No shape B.
- **D2 — Lane marker file `.supervisor/lane.json`** is the ONE file `lane-create` writes into a lane beyond the copied configs and the intake (the coordinator's single write, Design bullet 3). Shape: `{"schema_version":1,"lane":"L<n>","run_id":"<parent_run_id>-L<n>","parent_run_id":"<id>","primary":"<abs path of primary>","parallel":<N>,"max_tokens":<int|null>,"created":"<UTC ISO>"}`. `automate-lanes.sh lane-info [--root <dir>]` prints it (exit 1 when absent, never guesses). Every lane-aware seam keys on this file's presence: the engine uses its `run_id` as the lane's run id (no self-minted id), `closeout-others` skips, `resume-glob --finalize` finalizes only `run_id`'s own file, and the terminal park writes `ready_for_release`.
- **D3 — Lane run-file title** is `# Automate Run: <parent_run_id>-L<n> — <item path>`. `resume-glob` skips any run file whose title carries a `-L<digits>` run-id token, EXCEPT the run named by a present `.supervisor/lane.json` (a lane must still resume itself).
- **D4 — Relay hook is a subcommand, not a new file:** `automate-lanes.sh relay-hook` (reads the hook JSON on stdin, writes `<lane>/.supervisor/inbox/questions/<tool_use_id>.json` incl. `asked_at`, returns `defer`; on retry returns `allow` + `updatedInput.answers` and, when the answer carries a note, `updatedInput.annotations` so the note IS delivered — Scope 13 amendment option 1). `PermissionRequest[AskUserQuestion]` → deny for bundled calls. `lane-create` merges these two hook entries into the lane's `.claude/settings.local.json` with jq (never replacing an existing `hooks` key), the command pinned to `bash <coordinator CLAUDE_PLUGIN_ROOT>/scripts/automate-lanes.sh relay-hook`.
- **D5 — Launch authority (Scope 17):** `lane-launch` and every lane resume require `--owner-command '<the owner-invoked command text>'` (the coordinator passes the `/automate --parallel N` / `/automate --resume <id>` the OWNER typed in this session). Missing ⇒ first output line `lane-launch: BLOCKED — <lane> — no owner-invoked command — need the owner`, exit 3, no process. A host denial of the spawn ⇒ `blocked_launch` in the lane table + the same `BLOCKED` first line, never a retry in another shape.
- **D6 — Lane table** is the untracked sidecar `.supervisor/automate/<parent_run_id>.lanes` (TSV, non-`.md`): one row per lane — lane, path, item, run_id, pid, pid start time (`ps -o lstart=`), session_id (from the stream-json `system/init` event), state, last_launch_utc, blocked_reason.
- **D7 — INIT refusals and PICK guard are helper subcommands** (no script parses `/automate` flags today): `automate-lanes.sh init-check --parallel N [--auto-merge]` prints `refuse: auto_merge_with_parallel` (exit 1) for N>1 with `--auto-merge`, `refuse: parallel_out_of_range` for N<1 or N>10, else `ok`; `automate-lanes.sh pick-guard <automate_dir>` prints `refuse: live_lane <run_id> <lane>` (exit 1) when any `*.lanes` sidecar has a lane `lane-status` reconciles as live, else `ok`. The SKILL calls both; they are what the tests exercise.
- **D8 — Token split (Scope 8):** `lane-create` records `max_tokens = floor(N_total / lanes)` in `lane.json`; `read-token-ledger.sh` accepts `--root` repeated and sums across roots (one output line, same format), and `automate-lanes.sh lane-status --tokens` prints the per-lane and parent totals.
- **D9 — `.dismissed-decisions` joins the meta-sync managed set** (owner decision 2026-10-07, this run): `is_managed` accepts `.supervisor/automate/<name>.dismissed-decisions` (top level only, same canonical-path rules); the ledger is TSV of draft names (no home paths), scrub still applies.
- **D10 — Failure posture:** lane CORRECTNESS gates fail CLOSED (`lane-remove` refusals, `pick-guard`, `init-check`, launch authority, origin-before-fetch, remote branch-name hit ⇒ suffix or refuse, never force-push); OBSERVATION emitters fail SAFE and exit 0 (`lane-status` field readers incl. `machine.state: "unknown"`, `lane-sampler.sh`, notifications). Never kill a lane automatically (memory/load guards stop STARTING only).

## Acceptance Criteria
- [ ] AC1 — Given a two-item fixture queue with disjoint `Touches`, when `/automate --parallel 2` runs (hermetic test with `claude` stubbed), then two lanes are created at `<primary>-lanes/<run_id>/L1|L2/` with origin = the remote URL set before any fetch, configs carried byte-for-byte, `.supervisor/lane.json` per D2, run ids `<parent>-L1`/`-L2`, and `lane-status` lists both (Scopes 1, 2, 11). Requirement acceptance 1's end-to-end claim (two READY PRs, each lane run file with `owned_drain_result`, `suppressed_default_dispatch: true` and `ready_for_release`) is verified by Validation 4 (operator, real run) — the hermetic test covers creation, launch and the `ready_for_release` status write via `current-set` (AC4/Subtask 5).
- [ ] AC2 — Given no `--parallel` flag (or N = 1), when the existing helper suites run, then they pass with NO edit to an existing assertion (only added groups) and no lane directory, `.lanes` sidecar or `parallel:` line is created (Scope 11, Validation 2).
- [ ] AC3 — Given a live lane, when `lane-remove` runs, then it refuses (naming the reason) on: a live merge watcher, a live `claude -p` (pid + start-time + command-line check — a recycled pid is NOT a refusal), `awaiting_input`, unpushed metadata / the meta-push failure marker / unpushed commits, a dirty tree, and `gone` without `--abandon`; `--stop` TERMs then KILLs after 60 s; never `rm -rf` of a dirty lane (Scope 1).
- [ ] AC4 — Given a lane run file and the parent's primary, when `resume-glob` runs in the primary, then finished AND unfinished lane run files are never listed; inside a lane clone its own run IS listed and `--finalize` touches no other run (Scope 3, D3).
- [ ] AC5 — Given a two-lane fixture fleet with old unfinished run files on the metadata branch, when lanes start, then each old file is closed out exactly once (by the coordinator, in the primary), zero `closeout-others` lines appear in either lane, and no lane meta-push touches a path outside its own run (+ the shared ledger) (Scope 3 amendment).
- [ ] AC6 — Given a lane that asks, when the relay hook fires, then the question file appears, the lane exits `tool_deferred`, `lane-status` shows `awaiting_input` with `asked_at`/`waiting_s`; `lane-answer` accepts only the question's own labels (multiSelect: comma-joined, each validated, one unknown refuses all), refuses free-text-only, delivers the note, and resumes with `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0` and the same flags; a bundled call is denied (Scope 13 + amendment).
- [ ] AC7 — Given a lane whose process is gone, run file not parked, no pending question, when `lane-status` runs, then it shows `stalled`; after a reboot later than the last launch it shows `lost_to_reset`; a refused spawn shows `blocked_launch`; one lane dying leaves the other's status unchanged (`died`) (Scopes 14, 16, 17, acceptance 3).
- [ ] AC8 — Given `lane-status --json`, then it carries top-level `machine {state, load1, cpus, mem_pressure, keep_awake}` (`state: "unknown"`, exit 0, when `machine-load.sh` is absent), per-question `asked_at`/`waiting_s`, per-lane `last_message` (last assistant text, ≤300 chars, never a tool-use line), the merge-readiness score, CI-slot position, and `held for load` (Scopes 14, 15, 16, 17b).
- [ ] AC9 — Given a parked READY lane, then it writes `<run_id>.merge-readiness.md` with PASS/FAIL/NOT-RUN per check (Validation entries, carried Plan Review notes, scope fence `gh pr diff --name-only` ⊆ brief files + `changelog.d/`, gates, headline repro); a running-system step with no pasted output is NOT-RUN, never PASS (Scope 15).
- [ ] AC10 — Given `lane-sampler.sh` started by the coordinator, then every 10 s it appends one line to `<run_id>.fleet.log` with CI-slot holders/waiters, load1, swap, free memory, per-lane RSS attributed by CWD (not argv) and the non-lane share of load/RSS; it stops with the coordinator; the memory guard trips on a fixture series; each crossing (busy, overloaded, memory, keep-awake lost) notifies exactly once; while the trip file `.supervisor/automate/<parent_run_id>.memory-pressure` exists, `lane-launch` and every lane resume HOLD (`lane-launch: HELD — <lane> — memory_pressure`, no process), and on `machine-load.sh` `overloaded` they hold, on `busy` they launch at most one lane per re-check interval — stop starting, never kill (Scope 16 + amendment items 2–4).
- [ ] AC11 — Given two live 6-job `ci-slot` holders, when a bare `run-self-tests.sh` starts, then it waits for machine admission; under a live parent holder it folds; removing the admission call fails its test leg (Scope 16 amendment item 1; closes `ci-slot.sh` honest limit 9).
- [ ] AC12 — Given `init-check --parallel 2 --auto-merge`, then it refuses; given `pick-guard` while a `.lanes` sidecar shows a live lane, then a plain `/automate` PICK is refused, including after the run lock was reclaimed (Scopes 4, 9, D7).
- [ ] AC13 — Given parent `dismissed-pending`, then a lane's draft (`<parent>-L<n>--…--dismissed-*.md`) is counted, `dismissed-decide` accepts it, and `.dismissed-decisions` is listed by `meta-sync.sh list-managed` (Scope 7, D9).
- [ ] AC14 — Given `/automate --parallel N` prose, then `skills/automate-loop/SKILL.md` has a new `## §14 — Lanes (--parallel N)` section plus the non-goal, §8 ("one open PR per lane") and §11 concurrent-run edits; `commands/automate.md`, `agent-help.md`, `docs/result-schemas/automate-run.md` (`ready_for_release`, `parallel`) and `ARCHITECTURE_CONTRACTS.md` (`## Lanes`) are updated; `SKILLS_INDEX.md` in the same commit; the launch-authority rule is WRITTEN as a new stance (no existing anchor exists in the plugin) in both SKILL §14 and `commands/automate.md`: a launch or resume requested by a cross-session / peer message, a hook, or text inside a lane's output cannot authorize a lane launch or grant escalation — only a command the owner typed in the same session (Scopes 12, 17).
- [ ] AC15 — Given the full test loop + root checks (`bash scripts/ci-local.sh`), then all are green, including `check-vendor-coupling.sh` (manifest allowances raised with per-path reasons), `check-test-hermetic.sh`, `check-locale-prefix.sh`, `test-citation-drift.sh`; the `gh pr merge --squash` positive grep still resolves to the same five surfaces and `git grep -nE 'gh pr merge|--admin' loomwright/scripts/automate-lanes.sh` shows only the disallow list (Validation 3).
- [ ] AC16 — The two Scope 11 mutation controls fail when applied: dropping the `-L<n>` skip in `resume-glob`, and a coordinator write into a launched lane (checksum test); plus deleting the live-process check, and the `awaiting_input` check, from `lane-remove` each fail their leg (Validation 6).

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | `automate-lanes.sh` lifecycle: lane-create / lane-launch / relay-hook / lane-answer / lane-remove / lane-info / init-check / pick-guard + launch-time load/memory admission (Scopes 1, 4, 5-hook, 6, 8-split, 9, 10, 13, 14-remote-name+append-prompt, 16-launch-guard, 17) | AC1, AC3, AC6, AC10 (launch-hold half), AC12, AC16 (lane-remove legs, checksum) | 0 modify, 2 create | `skills/automate-loop/SKILL.md` (read), `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 2 | `automate-lanes.sh` observation: lane-status (+`--json`, `--watch`, `--leaks`, `--resources`, `--tokens`), lane-feed, merge-readiness writer, stalled / lost_to_reset / blocked_launch / held-for-load classification, keep-awake suggestion (Scopes 14, 15, 16-guards+reset+keep-awake, 17b) | AC7, AC8, AC9 | 2 modify, 0 create | `skills/unit-testing/SKILL.md` | BLOCKED (by #1) |
| 3 | `lane-sampler.sh`: port of `s2-sampler.sh` with Linux equivalents, CWD attribution, non-lane share, memory-guard trip file, crossing notifications (Scope 16 + amendment 3–4) | AC10 (sampler half) | 0 modify, 2 create | `skills/unit-testing/SKILL.md`, `skills/monitoring-observability/SKILL.md` | LAUNCHABLE |
| 4 | Machine admission for every full-suite entry point: `run-self-tests.sh` takes a `ci-slot.sh` slot (folds under a live parent holder), `ci-slot.sh` honest limit 9 closed (Scope 16 amendment 1–2) | AC11 | 4 modify, 0 create | `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 5 | Engine seams: dispatch arms + help lines + golden, `resume-glob` lane skip, `## Current` wave line + `ready_for_release`, `closeout-others`/`finalize` lane guards, dismissed lane scoping, multi-root token ledger, meta-sync managed `.dismissed-decisions` (Scopes 2, 3, 5-status, 7, 8, D2, D3, D8, D9) | AC2, AC4, AC5, AC13, AC16 (resume-glob leg) | 14 modify, 0 create | `skills/automate-loop/SKILL.md` (read), `skills/unit-testing/SKILL.md` | BLOCKED (by #1) |
| 6 | Docs + vendor-coupling manifest + changelog fragment (Scope 12, 17 prose; Scopes 2–17 described) | AC14, AC15 | 8 modify, 1 create | `skills/automate-loop/SKILL.md` | BLOCKED (by #1, #2, #3, #4, #5) |

### Subtask notes (what each worker must know beyond the requirement)

**Subtask 1.** New `loomwright/scripts/automate-lanes.sh` (bash 3.2, `set -uo pipefail`, `env LC_ALL=C` never a bare `LC_ALL=C cmd` prefix) + `test-automate-lanes.sh` (sources `hermetic-test-env.sh` as its FIRST executable line; `claude` and `gh` stubbed on PATH; fixture "primary" = a temp git repo with a bare fake origin). Functions (the gate greps these names): `lanes_create`, `lanes_launch`, `lanes_relay_hook`, `lanes_answer`, `lanes_remove`, `lanes_info`, `lanes_init_check`, `lanes_pick_guard`. Port, do not copy, the S1 harness behavior summarised in Risk Assessment row "Prototype port"; fix its known defects: pid liveness = pid + start time + `ps -ww -o command=` match (no bare `ps -p`); `.died` marker written by the nohup wrapper when the process exits with no terminal result line; session id captured from the stream-json `system/init` event at launch; `--plugin-dir "$CLAUDE_PLUGIN_ROOT"` pinned; refuse to launch when `claude --help` does not list `--permission-prompt-tool` / `--allowedTools` / `--disallowedTools` (pinnable permission regime); `--disallowedTools` carries `gh pr merge`, `--admin`, `git push --force`, and pushes to the base branch; `--append-system-prompt` carries the fixed headless-lane text (wait in the FOREGROUND; end the turn only when parked or asking); env `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0`, `CLAUDE_PID`/`CLAUDECODE` unset; prompt `/loomwright:automate --backlog <lane>/.supervisor/lane-backlog.md` (one line naming the item's CANONICAL path) or `/loomwright:automate --resume <run_id>`. Every meta-sync call passes `--branch` explicitly (Spike Q5 trap). Remote branch-name check: `git ls-remote --heads origin <name>` hit ⇒ suffix `-L<n>` or refuse; never force-push. Clone state at park = stay on the PR branch until closeout. A leftover lane directory is salvaged (`worktree-salvage.sh` style copy to `<primary>-lanes/<run_id>/salvage/`) then refused, never reused. Mutation-control legs required: coordinator write into a launched lane fails a checksum test; deleting the live-process check, or the `awaiting_input` check, from `lanes_remove` fails its leg. **Launch-time admission (Scope 16 load + memory guards — this subtask owns enforcement):** `lanes_launch` and the resume path (`lane-answer`'s resume, `--resume-run`) first read `machine-load.sh --json` (`LOOMWRIGHT_MACHINE_LOAD_CMD` seam, as `ci-slot.sh` uses) and the trip file `.supervisor/automate/<parent_run_id>.memory-pressure` (written by Subtask 3's sampler; tested here with a fixture file): `overloaded` or trip file present ⇒ first line `lane-launch: HELD — <lane> — <load overloaded|memory_pressure>`, exit 4, no process, lane table state `held_for_load`; `busy` ⇒ launch only if no lane of this wave launched within `LOOMWRIGHT_LANE_RECHECK_S` (default 60) per the lane table's `last_launch_utc`, else HELD the same way; `ok`/`unknown` ⇒ launch. Never kills a running lane. **Shared liveness helper:** lane liveness (pid + `ps -o lstart=` start time + `ps -ww -o command=` match against the lane-table row) is ONE function, `lanes_proc_alive`, used by `lanes_remove` AND `lanes_pick_guard` (pick-guard cannot call `lane-status`, which Subtask 2 adds later); Subtask 2's `lane-status` reuses it rather than redefining liveness. Test legs: overloaded holds, busy staggers, memory trip blocks a new launch, unknown admits. The dispatch arm in `automate-helpers.sh` is Subtask 5's — this subtask makes the script runnable standalone (`bash automate-lanes.sh <subcmd>`), with a `#   <subcmd> …` usage header.

**Subtask 2.** Adds to the SAME two files after Subtask 1 (file-conflict ordering). Functions: `lanes_status`, `lanes_feed`, `lanes_readiness`, `lanes_leaks`. The merge-readiness report (`lanes_readiness`) is written at a lane's `ready_for_release` park — that replaces the requirement's `awaiting_merge` trigger for lanes (D2/Scope 5) — and re-written on demand by `lane-status`; liveness comes from Subtask 1's `lanes_proc_alive`. `lane-status` reads lane run files + `gh` (reconcile like `reconcile-item`), the D6 lane table, inbox, stream log, `ci-slot.sh status --json`, `machine-load.sh --json`, `lane-sampler.sh`'s latest `fleet.log` line (absent ⇒ fields `unknown`, exit 0). `--leaks` = Validation 5's list (`git worktree list`, `ls <primary>-lanes/`, `pgrep -lf 'claude -p'`, `pgrep -lf automate-merge-watch`, config checksum, `git status --porcelain`) compared against a `--snapshot` taken at wave start. `--watch` refreshes every 15 s (test with a 1-iteration seam). Keep-awake: print the one-line suggestion `caffeinate -i -w <coordinator pid>` on macOS (nothing elsewhere) and show `keep-awake: held|not held` (`pgrep -x caffeinate`); `--keep-awake` opt-in starts it as the coordinator's child — never silently. No emoji in output.

**Subtask 3.** New `loomwright/scripts/lane-sampler.sh` + `test-lane-sampler.sh`. Function names: `sampler_line`, `sampler_loop`. Lane set read from the `.lanes` sidecar (never hard-coded names); CWD map via `lsof -a -d cwd -Fpn` on macOS, `/proc/<pid>/cwd` on Linux (test seams for both); load/memory via `machine-load.sh` (reuse, do not re-derive); temp data in `mktemp -d`, never the repo. Stops when its parent (coordinator pid, `--parent-pid`) dies. Memory guard: when free memory stays below `LOOMWRIGHT_LANE_MEM_FREE_MB` while swap grows for `LOOMWRIGHT_LANE_MEM_SAMPLES` consecutive samples (defaults stated in the header), it writes the trip file `.supervisor/automate/<parent_run_id>.memory-pressure` (UTC ts + the triggering sample) and removes it when the condition clears — the contract Subtask 1's launch guard reads. Notifications through the existing fail-safe `notify-desktop.sh` + `send-webhook.sh`, latched once per crossing.

**Subtask 4.** `run-self-tests.sh` acquires `ci-slot.sh acquire self-tests --pid $$` between job-count resolution and scheduling, releases in an EXIT trap, uses the returned `jobs` when `SELF_TEST_JOBS` is unset; under a live ancestor holder the call folds (existing `NESTED_IN` path) so `ci-local` is unchanged. Update `ci-slot.sh`'s honest-limit (9) text to the new truth (single test files run directly still bypass it — say so). Tests in `test-run-self-tests.sh` / `test-ci-slot.sh` with the mutation control.

**Subtask 5.** Small edits across 14 files; each has a co-located test group (added groups only — never edit an existing assertion; Validation 2 diffs `test-automate-helpers.sh`, `test-automate-trail.sh`, `test-dispatch-pr-review.sh`). `automate-helpers.sh`: exec arm(s) `    lane-create|lane-launch|…) exec bash "$(dirname "$0")/automate-lanes.sh" "$cmd" "$@" ;;` (4-space indent — the dispatch test's `exec_arms` regex), the `#   lane-…` help lines, the header carve-out paragraph; regenerate the golden with `bash loomwright/scripts/automate-helpers.sh --help > loomwright/scripts/fixtures/automate-helpers-help.golden`. `resume.sh`: D3 skip inside `_resume_glob_list` (not in `is_run_file`, which four other callers share) as function `_resume_lane_skip`; `--finalize` in a lane clone finalizes only `lane.json`'s run. `runfile.sh`: add `ready_for_release` to `CURRENT_STATUS_ENUM` and `CURRENT_PAUSE_ENUM`; a `- wave:` line in `## Current` written by a new `current_wave` writer modelled on `current_escalation`. `automate-trail.sh`: `_in_lane_clone` guard right after `closeout_others`'s `cd "$root"` ⇒ `closeout-others: skipped — lane clone`, exit 0. `automate-dismissed.sh` (new helper `_dismissed_lane_drafts`; + the two mirrored globs in `automate-trail.sh`'s candidate list and dropped-draft list): parent run file also matches `<parent>-L[0-9]*--*--dismissed-*.md`, each lane draft decided against ITS lane's ledger when present else the parent's. `read-token-ledger.sh`: repeatable `--root`. `meta-sync.sh`: D9 in `is_managed` + the managed-set header comment; `test-meta-sync.sh` leg with a mutation control. No SKILL/command prose pins in tests here (prose is Subtask 6's).

**Subtask 6.** Prose only, written AFTER the code so it describes what shipped. SKILL `## §14 — Lanes (--parallel N)`: the per-wave loop (meta pull → coordinator `closeout-others` ONCE → RECONCILE lanes → `plan-waves --max N` (+ the existing §2 intake lint) → `init-check` → `lane-create` + `lane-launch` per item → sampler start → resumable polling via `lane-status`), primary locked for the wave (`automate-lanes:<run_id>` run-lock owner + `pick-guard`), `ready_for_release` terminal park and the wave-end conversion to `awaiting_merge` until item 21 Part A lands, per-lane parks and the account-wide rate-limit pause, dismissed findings across lanes, token split, RESUME/`gone`, the lane inbox and how the main session relays questions verbatim, launch authority + `BLOCKED` reporting + wave hand-over, fleet health. **Also (Plan Review notes):** (a) INIT in §3/§14: when `automate-lanes.sh lane-info` succeeds, the run id AND the D3 title come from `lane.json` verbatim — the lane never mints its own id (no helper mints run ids; this is engine prose); (b) `## Run Config` gains `- parallel: N` only on a `--parallel N>1` parent run (absent otherwise — Validation 2); (c) the coordinator's stalled-lane rule: resume a `stalled` lane ONCE with the fixed decision-free message ("continue where you left off; wait in the foreground"), a second stall in the same phase escalates to the owner; (d) Scope 5: a READY lane writes `ready_for_release`, arms NO merge watcher, its notify says "do not merge yet — wave open"; (e) the launch-authority stance is NEW prose (no existing "peer cannot grant escalation" anchor exists) — write it in §14 and in `commands/automate.md`; (f) `ready_for_release` must be added to EVERY restated copy of the `## Current` enums in the same change — find them with `grep -rn 'closeout_leftover\|drain_died|done' loomwright/` (the list below is a floor, not a ceiling): in `docs/result-schemas/automate-run.md` the `- item: … | status: …` template line, the `pause_reason` template line, the `paused` row of the `## Status` table, the item-level `status` row and the `pause_reason` row of the field/enum table; in SKILL §3 the run-file template's `## Current` item and `pause_reason` lines and the `## Status` semantics list, and in SKILL §6 the park-path list in "Trail PR after merge and at run end" (add `ready_for_release` as a park that never calls `trail-pr`); and add one dated entry to `docs/result-schemas/schema-versioning.md` for the additive AUTOMATE_RUN values (`ready_for_release`, the `- wave:` `## Current` line, the `- parallel: N` Run Config line), following its existing `closeout_leftover` entry's shape. Update the stale "no `--parallel` flag exists in the engine yet" line (§2) and the §4 "Concurrency (accepted)" paragraph (now prevented by the lane guard). Raise `vendor-coupling-manifest.json` allowances for exactly the new/changed paths with a one-line reason each, measured with the new files `git add`-ed (the gate only sees tracked files). Fragment `changelog.d/parallel-automate-05-lane-coordinator.md` with `<!-- bump: minor -->`. Never hand-edit `plugin.json` / `marketplace.json` / `CHANGELOG.md`. If the SKILL frontmatter `version:` is bumped, run `bash scripts/check-skills-index-sync.sh --write`.

## Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/automate-lanes.sh"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "lanes_create"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "lanes_launch"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "lanes_relay_hook"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "lanes_answer"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "lanes_remove"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "lanes_info"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "lanes_init_check"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "lanes_pick_guard"}
  - {kind: "file", path: "loomwright/scripts/test-automate-lanes.sh"}
requires: []
lanes:
  - "loomwright/scripts/automate-lanes.sh"
  - "loomwright/scripts/test-automate-lanes.sh"
external_requires:
  - "claude CLI flags --input-format stream-json, --permission-prompt-tool stdio, --allowedTools, --disallowedTools, --plugin-dir, --append-system-prompt, --resume (stubbed in tests)"
  - "PreToolUse defer / PermissionRequest deny hook protocol for AskUserQuestion (verified in S1 v2)"

# Subtask 2
provides:
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "lanes_status"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "lanes_feed"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "lanes_readiness"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "lanes_leaks"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "lanes_create"}
  - {from: "1", kind: "file", path: "loomwright/scripts/test-automate-lanes.sh"}
lanes:
  - "loomwright/scripts/automate-lanes.sh"
  - "loomwright/scripts/test-automate-lanes.sh"
external_requires: []

# Subtask 3
provides:
  - {kind: "file", path: "loomwright/scripts/lane-sampler.sh"}
  - {kind: "symbol", path: "loomwright/scripts/lane-sampler.sh", name: "sampler_line"}
  - {kind: "symbol", path: "loomwright/scripts/lane-sampler.sh", name: "sampler_loop"}
  - {kind: "file", path: "loomwright/scripts/test-lane-sampler.sh"}
requires: []
lanes:
  - "loomwright/scripts/lane-sampler.sh"
  - "loomwright/scripts/test-lane-sampler.sh"
external_requires:
  - "lsof (macOS) or /proc (Linux) for per-process CWD"

# Subtask 4
provides:
  - {kind: "symbol", path: "loomwright/scripts/run-self-tests.sh", name: "ci-slot.sh"}
  - {kind: "symbol", path: "loomwright/scripts/test-run-self-tests.sh", name: "admission"}
requires: []
lanes:
  - "loomwright/scripts/run-self-tests.sh"
  - "loomwright/scripts/test-run-self-tests.sh"
  - "loomwright/scripts/ci-slot.sh"
  - "loomwright/scripts/test-ci-slot.sh"
external_requires: []

# Subtask 5
provides:
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "automate-lanes.sh"}
  - {kind: "symbol", path: "loomwright/scripts/fixtures/automate-helpers-help.golden", name: "lane-create"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.d/resume.sh", name: "_resume_lane_skip"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.d/runfile.sh", name: "ready_for_release"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.d/runfile.sh", name: "current_wave"}
  - {kind: "symbol", path: "loomwright/scripts/automate-trail.sh", name: "_in_lane_clone"}
  - {kind: "symbol", path: "loomwright/scripts/automate-dismissed.sh", name: "_dismissed_lane_drafts"}
  - {kind: "symbol", path: "loomwright/scripts/meta-sync.sh", name: "dismissed-decisions"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "lanes_info"}
lanes:
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/automate-helpers.d/resume.sh"
  - "loomwright/scripts/automate-helpers.d/runfile.sh"
  - "loomwright/scripts/fixtures/automate-helpers-help.golden"
  - "loomwright/scripts/test-automate-helpers.sh"
  - "loomwright/scripts/test-automate-helpers-dispatch.sh"
  - "loomwright/scripts/automate-trail.sh"
  - "loomwright/scripts/test-automate-trail.sh"
  - "loomwright/scripts/automate-dismissed.sh"
  - "loomwright/scripts/test-automate-dismissed.sh"
  - "loomwright/scripts/read-token-ledger.sh"
  - "loomwright/scripts/test-read-token-ledger.sh"
  - "loomwright/scripts/meta-sync.sh"
  - "loomwright/scripts/test-meta-sync.sh"
external_requires: []

# Subtask 6
provides:
  - {kind: "symbol", path: "loomwright/skills/automate-loop/SKILL.md", name: "## §14 — Lanes"}
  - {kind: "symbol", path: "loomwright/commands/automate.md", name: "--parallel"}
  - {kind: "symbol", path: "loomwright/commands/agent-help.md", name: "--parallel"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/automate-run.md", name: "ready_for_release"}
  - {kind: "symbol", path: "loomwright/docs/ARCHITECTURE_CONTRACTS.md", name: "## Lanes"}
  - {kind: "file", path: "changelog.d/parallel-automate-05-lane-coordinator.md"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "lanes_launch"}
  - {from: "2", kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "lanes_status"}
  - {from: "3", kind: "file", path: "loomwright/scripts/lane-sampler.sh"}
  - {from: "4", kind: "symbol", path: "loomwright/scripts/run-self-tests.sh", name: "ci-slot.sh"}
  - {from: "5", kind: "symbol", path: "loomwright/scripts/automate-helpers.d/runfile.sh", name: "ready_for_release"}
lanes:
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/skills/SKILLS_INDEX.md"
  - "loomwright/commands/automate.md"
  - "loomwright/commands/agent-help.md"
  - "loomwright/docs/result-schemas/automate-run.md"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/docs/result-schemas/schema-versioning.md"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "changelog.d/parallel-automate-05-lane-coordinator.md"
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2 ──→ Subtask 6
Subtask 1 ──→ Subtask 5 ──→ Subtask 6
Subtask 3 (independent) ──→ Subtask 6
Subtask 4 (independent) ──→ Subtask 6
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | `loomwright/scripts/automate-lanes.sh`, `loomwright/scripts/test-automate-lanes.sh` | YES (2 requires 1) |
| Subtask 1 | Subtask 3/4/5/6 | none | NO |
| Subtask 2 | Subtask 5 | none | NO |
| Subtask 3 | Subtask 4 | none | NO |
| Subtask 5 | Subtask 6 | none | NO |

### Batch Plan
- **Batch 1:** Subtask 1, Subtask 3, Subtask 4 (parallel — empty `requires`, disjoint lanes)
- **Batch 2:** Subtask 2, Subtask 5 (after Subtask 1; disjoint lanes)
- **Batch 3:** Subtask 6 (after all)
- **Recommended workers:** 3
- **Estimated batches:** 3

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/automate-loop/SKILL.md`, `skills/unit-testing/SKILL.md` |
| 2 | `skills/unit-testing/SKILL.md` |
| 3 | `skills/unit-testing/SKILL.md`, `skills/monitoring-observability/SKILL.md` |
| 4 | `skills/unit-testing/SKILL.md` |
| 5 | `skills/automate-loop/SKILL.md`, `skills/unit-testing/SKILL.md` |
| 6 | `skills/automate-loop/SKILL.md` |

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Scope size: 31 files, two new large scripts; one worker cannot hold it (Feasibility (Phase 2.5), check 4) | HIGH | `context-bound` split into 6 file-disjoint subtasks; each worker reads only its Scopes; Subtask 2 extends Subtask 1's files strictly after it. |
| Prototype port: the S1 harness (`s1h.sh`, outside the repo) has known defects — bare `ps -p` liveness (recycled pid reads alive), pid from a log, session id only from the last result line, `install_hooks` overwrites an existing `hooks` key, absolute hook path, hard-coded paths/branch/lane names, emoji, `perl -pi`, macOS-only `sysctl`/`vm_stat`/`lsof` in the sampler | HIGH | Subtask 1/2/3 notes list each fix; tests cover recycled pid, hook merge, Linux seams. Never copy hard-coded values; never write a home path into a committed file (meta-sync `home_path` scrub). |
| Vendor-coupling ratchet: new scripts carry `claude -p`, `CLAUDE_CODE_`, `CLAUDE_PID`, `AskUserQuestion`, `.claude/`, `CLAUDE_PLUGIN_ROOT` tokens; a new path's allowance is 0 | HIGH | Subtask 6 raises allowances with reasons, measured after `git add` of the new files (gate scans tracked files only). |
| Validation 4 (real `--parallel 2`) and Validation 2's real single-item run cannot run inside the Supervisor run | MEDIUM | Operator steps after the PR, owner's go, two THROWAWAY items only (never real queue items); the PR body lists them NOT-RUN until done. |
| Hardware: 3 parallel workers each running test files (S3 wave 1 froze at load1 119) | MEDIUM | Operator load monitor (alert ≥ 60) + `caffeinate -i` are live; workers run their own test file, the full loop only via `bash scripts/ci-local.sh` (ci-slot admission). |
| Lane run id and title (D2/D3) are new contracts other readers (`build-handoff.sh` title mirror, `plan-waves` `is_run_file`) see | MEDIUM | `is_run_file` stays unchanged (the skip lives in `_resume_glob_list` only); the title remains a valid `# Automate Run:` line. |
| Test-integrity guard (fail-CLOSED PreToolUse hook) refuses edits to existing assertions | MEDIUM | Add test groups only; Validation 2 depends on it anyway. |
| `meta-sync.sh` is security-sensitive (scrub, managed set, symlink containment) | MEDIUM | D9 is a one-pattern addition at top level of `.supervisor/automate/`, same canonical-path rejection; a test + mutation control; no other meta-sync change. |
| `skills/automate-loop/SKILL.md` is ~194 KB and has no token budget; §14 grows it further | LOW | Keep §14 a contract (pointers to `automate-lanes.sh --help`), not a restatement of script internals. |

## Configuration
- **Workers:** 3
- **Mode:** parallel
- **Estimated batches:** 3
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-07-pa05-lane-coordinator.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-10-07T20:29:57Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/426
- **Branch:** feature/pa05-lane-coordinator
- **Files changed:** 31
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** /automate --parallel N lane coordinator: automate-lanes.sh (lifecycle + observation), lane-sampler.sh, run-self-tests machine admission, engine seams (resume lane skip, ready_for_release/live_lane, lane guards, dismissed lane scope, multi-root ledger, managed .dismissed-decisions), SKILL §14 + docs. ci-local PASS on 72bd1c6; Phase 4.5 review 1 FAIL (AC12 pick-guard) fixed in a624d01, review 2 PASS; 6 MEDIUM/LOW dismissed for owner decision.

## Not verified
- **Real claude -p launch/resume (disallowedTools rule syntax, annotations note delivery)** — tests use a PATH stub (subtask 1)
- **Real meta-sync.sh / setup-memory.sh inside a lane clone** — stubbed via seams (subtask 1)
- **lane-status vs real ci-slot/machine-load/sampler fleet.log; lane-readiness vs real gh** — fixtures only (subtask 2)
- **lost_to_reset boot-time readers** — seam only, no real reboot (subtask 2)
- **lane-sampler.sh Linux readers** — fixture /proc only (subtask 3)
- **Bare run-self-tests.sh admission on Linux CI** — no CI run observed yet (subtask 4)
- **AC5 real-fleet lane meta-push path scope** — needs Validation 4 (subtask 5)
- **Engine following §14 end to end** — needs Validation 4 (subtask 6)
