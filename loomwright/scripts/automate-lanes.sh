#!/usr/bin/env bash
# automate-lanes.sh — lane lifecycle for `/automate --parallel N` (parallel-automate/05).
#
# A LANE is a local clone of the primary checkout at `<primary>-lanes/<parent_run_id>/L<n>/` that runs
# the ordinary per-item `/automate` loop for ONE item, headless (`claude -p`), with a question channel
# (lane shape A + relay). One coordinator in the primary creates, launches and removes lanes through
# this script. Without `--parallel` nothing here is ever called. `--parallel 1` is SINGLE-LANE MODE
# (twin-remediation/08b): each Queue item runs in ONE fresh lane (a new lane number every time) that
# parks `awaiting_merge` like a sequential item — no wave, no wave PR (skills/automate-loop/lanes.md
# "Single-lane mode").
#
# Usage (standalone: `bash automate-lanes.sh <subcmd> ...`):
#   lane-create <parent_runfile> <item> <n> [--parallel N] [--max-tokens T]
#        clone + origin-before-fetch + meta pull + carried configs + lane.json + one-line backlog + relay hooks.
#        An explicit `--parallel 1` (single-lane mode) writes `"single_lane": true` into lane.json, takes
#        n in 1..99 and refuses a number already in the lane table (`refused — lane L<n> already used in
#        this run`), and makes --max-tokens T a WHOLE-RUN ceiling: SPENT = every table lane's ledger TOTAL
#        (a removed lane's from its parent `fleet closeout: <lane> tokens TOTAL=<n>` line) ⇒ refused
#        `token_ceiling total=<SPENT> max=<T>` / `token_ceiling ledger_unreadable`, else max_tokens = T − SPENT
#   lane-launch <lane_dir> --owner-command '<cmd the owner typed>' [--resume-run <run_id> | --continue]
#        [--without-gate-optout]
#        detached headless launch (or resume by run id — in the lane's LAST session, a fresh one only
#        when that cannot be resumed — / fixed decision-free continue message); see "Gate opt-out carry"
#   lane-launch <lane_dir> --host-denied '<reason>'      record a host-refused spawn as blocked_launch
#   relay-hook                                           PreToolUse / PermissionRequest hook (stdin: hook JSON)
#   lane-answer <lane_dir> <tool_use_id> --owner-command '<cmd>' [--via <client>] [--without-gate-optout]
#        stdin: {"answers":{"0":"<label>"},"note":"<optional free text>"}; validates, records, resumes
#        (HELD, or BLOCKED on a missing gate opt-out ⇒ the validated answer is kept coordinator-side,
#        the lane reads answer_pending)
#   lane-answer <lane_dir> --deliver-pending --owner-command '<cmd>' [--without-gate-optout]
#        deliver a kept answer (the poll)
#   lane-remove <lane_dir> [--stop] [--abandon]          guarded removal (salvages first); --abandon on a
#        `gone` lane stamps ABANDONED and pushes the lane's metadata through trail-pr's evidence gate;
#        an unpushed-metadata refusal names the paths (`meta-sync.sh status --paths`); on a single-lane
#        parent (`## Run Config` `- parallel: 1`) it first appends `fleet closeout: <lane> tokens TOTAL=<n>`
#        to the parent `## Progress` unless that lane already has one
#   lane-convert-ready <lane_dir>                        wave end: ready_for_release → awaiting_merge, then
#        push the lane's metadata (non-claim files by exact list + trail-pr's evidence-gated list); a
#        re-run once the PR merged first runs `closeout … --no-trail` inside the lane (the done stamp),
#        then, branch mode only, `finalize-empty` on the lane's run file (`## Status: done`)
#   fleet-closeout <parent_runfile>                      wave close, stepwise + idempotent (re-run on every
#        coordinator --resume): meta pull · per-lane backstop (lane-convert-ready on a merged lane) ·
#        parent Queue check-off · primary sync · lane-remove · lanes dir, leaks, main health, then — Queue
#        empty — the parent finalize (`## Status: done`, wave line cleared, trail-pr --reason done) and the
#        lock release; a single-lane parent also gets `fleet closeout: <lane> tokens TOTAL=<n>` per lane,
#        written BEFORE that lane's lane-remove
#   wave-plan <parent_runfile> [--wave-branch <name>]    READ-ONLY: prints the operator's wave-branch
#        integration commands (one `git merge --no-ff <head sha>` per lane) and the conflict rules;
#        the preview / manual fallback of automate-wave.sh `wave-build`, which runs those same steps
#   lane-info [--root <dir>]                             print .supervisor/lane.json (exit 1 when absent)
#   init-check --parallel N [--auto-merge]               INIT refusals: `ok` | `refuse: <reason>` (exit 1):
#        parallel_out_of_range · auto_merge_with_parallel (any N) · N = 1 only: single_lane_requires_branch_mode
#        (setup-memory.sh mode, --root = this checkout's top level, must print `on <branch>`)
#   lane-park [--root <dir>]                             READ-ONLY: the READY park a run writes here, one line,
#        exit 0: `awaiting_merge` (no lane.json — not a lane — or `"single_lane": true`) | `ready_for_release`
#        (any other lane.json, an unreadable one included: the park that arms no watcher)
#   lane-drain-check <lane_dir>                          READ-ONLY drain guard at a lane's park, one line, exit 0:
#        `drain-guard: ok — …` | `drain-guard: violation — <reason>` (a dispatch marker for the lane's PR,
#        0 or ≥ 2 owned drains / ≥ 2 fix-now re-drains after the LAST `picked`, a config backup) |
#        `drain-guard: unknown — <reason>` (fail SAFE)
#   pick-guard <automate_dir>                            PICK guard: `ok` | `refuse: live_lane <run_id> <lane>`
#   branch-check <lane_dir> <branch>                     remote branch-name check: prints the name to use
#   lane-status [<parent_runfile>] [--json] [--watch] [--refresh-readiness] [--keep-awake]
#        one line per lane: state, item, PR, progress, last 3 actions, question, CI slot, readiness,
#        and its policy-answer digest (`policy: none answered` when no lane has one)
#   lane-status [<parent_runfile>] --inbox               every lane's pending HUMAN questions, one list,
#        oldest asked_at first (a policy-answered question has an answer file, so it is not listed)
#   lane-status [<parent_runfile>] --leaks [--snapshot]  Validation 5 leak check vs the wave-start snapshot
#   lane-status [<parent_runfile>] --resources | --tokens  latest fleet.log line + peak | per-lane + parent tokens
#   lane-feed <lane_dir|L<n>> [--follow]                 readable narration of the lane's stream log
#   lane-readiness <lane_dir|L<n>>                       write <run_id>.merge-readiness.md (advisory, never merges)
#   validation-gate <runfile> <item> <pr_url> [--waive <n> --words <text>]   READY-park gate (lane AND
#        sequential): `none` | `ok` | `waived` | `unrun — V<n> <title>: <evidence>` (fail CLOSED, exit 0);
#        --waive records an interactive owner's waiver as one ## Progress line (refusal exit 1)
#   lane-park-notify <runfile>                           the ready_for_release park's ONE notify step: desktop +
#        `automate_ready_for_release` webhook (fail-SAFE) + one ## Progress line naming each channel's real outcome
#   lane-wait <parent_runfile> [--interval S] [--timeout S]   the coordinator's lane watcher: blocks,
#        token-free, until a lane needs the owner (a new pending question, or a lane entering any state
#        that is neither live nor coordinator-driven — a park / failure state, an unknown one included),
#        prints one `lane-wait: …` line per event and exits 0 — run it as a BACKGROUND
#        command so its exit wakes the coordinator session to relay; read-only except its seen ledger
#        and its liveness marker (the Stop hook guard-lane-wait-armed.sh reads the marker)
#
# Files (all paths derived; nothing hard-coded):
#   <lane>/.supervisor/lane.json        D2 marker — the ONE marker lane-create writes (plus the copied
#                                       configs, the intake `lane-backlog.md`, and the relay-hook entries
#                                       merged into `<lane>/.claude/settings.local.json`). After launch the
#                                       coordinator never writes into the lane again, EXCEPT (1) the answer
#                                       file of the inbox protocol (`lane-answer`, below), (2) the
#                                       wave-end `lane-convert-ready` run-file conversion and its metadata
#                                       push (trail-pr's failure marker / Progress line included) — on a
#                                       merged lane's re-run also `closeout --no-trail`'s requirement
#                                       stamp, check-off and `## Current` reconcile, and (branch mode)
#                                       finalize-empty's `## Status: done` + its Progress lines — and
#                                       (3) `lane-remove --abandon` on a `gone` lane: the ABANDONED stamp,
#                                       the done/ → failed/ brief move and the same push, just before the
#                                       lane is salvaged and deleted.
#                                       lane.json carries `policy`: lane-policy.sh `resolve`'s object, run in
#                                       the PRIMARY at lane-create (the rules stamp is per clone), or null;
#                                       and `"single_lane": true` (appended last) ONLY from an explicit
#                                       `--parallel 1` — absent otherwise, never inferred from `parallel`.
#   <lane>/.supervisor/inbox/questions/<tool_use_id>.json   written by relay-hook (the lane's own hook)
#   <lane>/.supervisor/inbox/questions/superseded/<tool_use_id>.json   an abandoned question, moved there by
#                                       relay-hook when the lane asks a newer one (+ `superseded_by`,
#                                       `superseded_at`); kept as the record, never pending, never answerable
#   <lane>/.supervisor/inbox/answers/<tool_use_id>.json     written by lane-answer (`source: "human"`), or by
#                                       relay-hook ITSELF — the lane's own hook, not the coordinator — for a
#                                       policy answer (`source: "policy"`, `policy_sha`, `gate`, `via: "policy"`)
#   <primary>/.supervisor/automate/<parent_run_id>.lanes    D6 lane table (TSV, untracked): lane, path, item,
#                                       run_id, pid, pid_start (`ps -o lstart=`), session_id (stream-json
#                                       `system/init`), state, last_launch_utc, blocked_reason. `-` = empty.
#   <primary>-lanes/<parent_run_id>/L<n>.stream.log         the lane's stream-json output (outside the lane)
#   <primary>-lanes/<parent_run_id>/L<n>.died               written by the nohup wrapper when the process
#                                       exits with no terminal `result` line since its launch
#   <primary>-lanes/<parent_run_id>/salvage/                lane-create / lane-remove salvage copies
#                                       (kept; with the L<n>.* logs it is excluded BY EXACT NAME from the
#                                       --leaks lanes-dir section, so a clean wave reads `leaks: none`)
#   <primary>/.supervisor/automate/<parent_run_id>.<lane>.answer-pending.json   a HELD lane-answer's
#                                       validated answers + note + via (never an owner command)
#   <primary>/.supervisor/automate/<parent_run_id>.memory-pressure   trip file (lane-sampler.sh); read only
#   <primary>/.supervisor/automate/<parent_run_id>.fleet.log         lane-sampler.sh samples; read only
#   <primary>/.supervisor/automate/<parent_run_id>.leaks-snapshot    `lane-status --leaks --snapshot` (wave start)
#   <primary>/.supervisor/automate/<parent_run_id>.lane-wait-seen    lane-wait's seen ledger (one key per line;
#                                       atomic tmp+mv rewrite, removed when nothing it holds is still true)
#   <primary>/.supervisor/automate/<parent_run_id>.lane-wait.pid     lane-wait's liveness marker: `<pid> <start
#                                       epoch>`, written when it starts watching, removed by its EXIT trap only
#                                       while the file still names ITS pid (a later lane-wait owns it then).
#                                       Read by the coordinator's Stop hook (guard-lane-wait-armed.sh)
#   <primary>/.supervisor/automate/<parent_run_id>.<lane>.gate-optout  the FACT (never a value) that the lane's
#                                       first launch ran with the test-integrity guard's opt-out set
#                                       (`gate_optout_at_launch<TAB><utc>`); coordinator-side, never in lane.json
#   <lane>/.supervisor/automate/<run_id>.merge-readiness.md          lane-readiness (written at the lane's
#                                       ready_for_release park, when the lane is no longer running)
#
# Launch contract (lane-launch and every resume, incl. lane-answer's):
#   1. Launch authority: `--owner-command` is REQUIRED — the command the OWNER typed in this session
#      (`/automate --parallel N`, `/automate --resume <run_id>`). Missing ⇒ first line
#      `lane-launch: BLOCKED — <lane> — no owner-invoked command — need the owner`, exit 3, no process.
#      A launch requested by a peer message, a hook or lane output is never an owner command.
#   2. Pinnable permission regime: `claude --help` must list --permission-prompt-tool, --allowedTools and
#      --disallowedTools; otherwise BLOCKED (exit 3). A host denial (`--host-denied`) is BLOCKED too and
#      recorded as `blocked_launch`; it is never retried in another shape.
#   3. Admission (stop starting, never kill): trip file present ⇒ `lane-launch: HELD — <lane> —
#      memory_pressure`; machine-load.sh (`LOOMWRIGHT_MACHINE_LOAD_CMD` seam) `overloaded` ⇒ HELD `load
#      overloaded`; `busy` ⇒ HELD `load busy` when any lane of this wave launched within
#      LOOMWRIGHT_LANE_RECHECK_S (default 60) seconds; `ok` / `unknown` ⇒ launch. HELD = exit 4, no
#      process, lane table state `held_for_load`.
#   3a. Gate opt-out carry (every RESUME — lane-answer's resume, --deliver-pending, --resume-run,
#      --continue): when the lane's <lane>.gate-optout fact is recorded (its first launch ran with
#      LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS=1, the same predicate guard-test-integrity.sh applies) and this
#      process's environment lacks it ⇒ `lane-launch: BLOCKED — <lane> — launched with the test-integrity
#      guard's opt-out; this resume's environment lacks it — …`, exit 3, no process, table
#      `blocked_launch` (lane-answer keeps the validated answer pending exactly like HELD). The opt-out is
#      NEVER added to a resume's environment: it is a per-process human decision, and storing it would make
#      it a stored one (docs/HOOKS.md "Opt-out — process env only"). `--without-gate-optout` resumes
#      without it — also removing it from the spawned environment — and clears the recorded fact once the
#      gate passes. A recorded fact only ever REFUSES, so a process that forges or deletes the sidecar can
#      at most block a resume or drop the opt-out; it can never grant it.
#   4. Spawn: `claude -p` with the lane allowlist / disallow list below, `--plugin-dir` pinned to the
#      coordinator's plugin root (LOOMWRIGHT_ROOT), `--append-system-prompt` = the fixed headless-lane text, env
#      CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 with CLAUDE_PID / CLAUDECODE / LOOMWRIGHT_HOLDER_PID unset. Prompt:
#      `/loomwright:automate --backlog <lane>/.supervisor/lane-backlog.md` or
#      `/loomwright:automate --resume <run_id>` (the lane's own run id only — never a bare --resume).
#
# Liveness: ONE helper, `lanes_proc_alive <pid> <pid_start> <lane_dir>` — the pid is alive, its
# `ps -o lstart=` equals the recorded start time, and `ps -ww -o command=` shows this script's
# `_lane-run <lane_dir>` wrapper. A recycled pid is never alive. lane-remove and pick-guard use it.
#
# Inbox protocol: relay-hook records the question (`asked_at` UTC) and returns `defer`; the lane exits
# `stop_reason: tool_deferred`. lane-answer accepts exactly the question's own option labels
# (multiSelect: comma-joined, each validated; one unknown label refuses the whole answer); a note alone
# is refused. The note IS delivered: on resume relay-hook returns `allow` with `updatedInput.answers`
# and `updatedInput.annotations` = {<question>: {notes: <note>}} for every answered question.
# A PermissionRequest[AskUserQuestion] (a question bundled with other calls) is denied with a re-ask.
# Superseded questions: when relay-hook records a NEW question id, every older question of the lane with
# no answer file was abandoned (a deferred question ends the process, so a new id means the session moved
# on) and moves to questions/superseded/ with one lane `## Progress` line (_lanes_supersede_older).
# Pending = _lanes_pending_questions, the one reader; lane-answer refuses a superseded id by name.
# Policy answers (parallel-automate/21 B6): before deferring, relay-hook asks `lane-policy.sh decide`
# (an EXACT catalog lookup, never a model judgement) against lane.json's carried `policy`. Only a full
# answer — every question of the call a catalogued `allowed` gate with a policy label — is applied: it
# is validated by _lanes_validate_answers like an owner answer, recorded as the answer file above, one
# `policy answer: <code> → <label> (policy_sha <12>)` lane `## Progress` line is appended (fail-SAFE),
# and the hook returns the answered branch's `allow` + `updatedInput` (no defer, no resume). `policy`
# null, `human`, or any error ⇒ exactly today's question file + defer.
#
# Failure posture: correctness gates (lane-remove refusals, pick-guard, init-check, launch authority,
# origin-before-fetch, remote branch-name hit, validation-gate — anything unreadable reads `unrun`) fail
# CLOSED; relay-hook outside a lane emits `{}`.
# Every meta-sync call passes `--branch` explicitly (the mode line's branch).
#
# Observation (lane-status, lane-feed, lane-readiness) fails SAFE: an absent or unreadable source reads
# `unknown` and the command exits 0 — EXCEPT `lane-status --leaks --snapshot`, which exits 1 naming why
# when it wrote no snapshot. With no lane table yet (§14 step 5 precedes step 6), `--leaks` derives the
# parent run id and the primary from <parent_runfile>. lane-status state, first match wins:
# removed/abandoned, answer_pending, blocked_launch, held_for_load (awaiting_input instead while the
# lane holds an unanswered question and no process runs), created, missing, running
# (lanes_proc_alive), awaiting_input, the run
# file's park (merged / gone after reconcile-item), lost_to_reset (boot later than the last launch),
# died (.died marker), stalled (process gone, not parked, no question). Keep-awake is SUGGESTED on macOS
# (`caffeinate -i -w <coordinator pid>`); only `lane-status --keep-awake` starts it.
#
# Test seams: LOOMWRIGHT_LANES_META_SYNC (meta-sync.sh path), LOOMWRIGHT_LANES_SETUP_MEMORY
# (setup-memory.sh path), LOOMWRIGHT_LANES_HELPERS (automate-helpers.sh path),
# LOOMWRIGHT_LANES_INIT_WAIT_S (default 15: wait for the session id), LOOMWRIGHT_LANES_STOP_GRACE_S
# (default 60: TERM→KILL grace for --stop), LOOMWRIGHT_MACHINE_LOAD_CMD, LOOMWRIGHT_LANE_RECHECK_S,
# LOOMWRIGHT_GH_BIN, LOOMWRIGHT_LANES_CI_SLOT, LOOMWRIGHT_LANES_PGREP, LOOMWRIGHT_LANES_PS (the --leaks
# claude-p process table), LOOMWRIGHT_LANES_LSOF / LOOMWRIGHT_LANES_PROC (its working-directory readers),
# LOOMWRIGHT_LANES_CAFFEINATE,
# LOOMWRIGHT_LANES_UNAME, LOOMWRIGHT_LANES_COORDINATOR_PID, LOOMWRIGHT_LANES_BOOT_EPOCH,
# LOOMWRIGHT_LANES_TOKEN_LEDGER, LOOMWRIGHT_LANES_WATCH_ITERATIONS, LOOMWRIGHT_LANES_WATCH_INTERVAL_S,
# LOOMWRIGHT_LANES_LOCK_WAIT_S (default 30: the bound on waiting for a live lock holder),
# LOOMWRIGHT_LANES_TRAIL (default: the helpers path — whose `trail-pr` runs the lane's gated push),
# LOOMWRIGHT_LANES_NOTIFY_DESKTOP / LOOMWRIGHT_LANES_SEND_WEBHOOK (lane-park-notify's two notifiers),
# LOOMWRIGHT_LANES_POLICY (lane-policy.sh path), LOOMWRIGHT_LANES_RUN_LOCK (run-lock.sh path, fleet-closeout).
#
# Modules (sourced in this order from automate-lanes.d/):
# - common.sh: now_utc … _lanes_merge_hooks — shared helpers, the D6 lane-table lock (_lt_*), _lane_ctx,
#    lanes_proc_alive (the ONE liveness helper), salvage, the relay-hook merge (`_merge-hooks`)
# - create.sh: lanes_create (`lane-create`)
# - launch.sh: _lanes_regime_ok … _lanes_last_result — the launch contract: regime, admission, the
#    launch lock, gate opt-out carry, spawn, the `_lane-run` wrapper, lanes_launch (`lane-launch`)
# - relay.sh: _lanes_hook_root … _lanes_deliver_pending — lanes_relay_hook (`relay-hook`), policy answers,
#    answer validation, lanes_answer (`lane-answer`, `--deliver-pending`)
# - remove.sh: _lanes_stop_pid … lanes_convert_ready — lanes_remove (`lane-remove`, its refusals,
#    `--abandon`'s metadata push), lanes_convert_ready (`lane-convert-ready`)
# - notify-guards.sh: _lanes_click_action … lanes_branch_check — lanes_park_notify (`lane-park-notify`),
#    lanes_info (`lane-info`), lanes_init_check (`init-check`), lanes_pick_guard (`pick-guard`),
#    lanes_branch_check (`branch-check`)
# - status-read.sh: _lanes_dash … _lanes_tokens_record — the OBSERVATION readers lane-status builds on:
#    run-file fields, questions, inbox, keep-awake, the lane resolver, timeline, the status document and
#    its plain render, resources, tokens
# - park-leaks.sh: lanes_park … lanes_leaks — lanes_park (`lane-park`), lanes_drain_check
#    (`lane-drain-check`), the `lane-status --leaks` sections
# - status.sh: lanes_status … lanes_feed — lanes_status (`lane-status`, `--watch`), lanes_wait
#    (`lane-wait`, _lanes_quick_state), lanes_feed (`lane-feed`)
# - readiness.sh: _lanes_rd_section … lanes_validation_gate — the shared Validation reader,
#    lanes_readiness (`lane-readiness`), lanes_validation_gate (`validation-gate`)
# - wave.sh: _lanes_base_of … lanes_wave_plan — WAVE CLOSE: lanes_fleet_closeout (`fleet-closeout`),
#    _lanes_wave_resolve (automate-wave.sh sources this file for it), lanes_wave_plan (`wave-plan`)
# Every module is sourced by name at the position its code held when this was one file (the loader
# below); the header, the config block, die, _lanes_usage, lanes_main and the direct-run guard stay
# here. A "see the header in automate-lanes.sh" pointer to a function lands on its module above.
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
HERE="$(dirname "$SELF")"
# The install root comes from the vendor-neutral resolver (docs/CORE_CONTRACT.md "Root resolution"),
# sourced in a SUBSHELL so this script adds nothing to the environment of the lanes it spawns.
# A missing resolver keeps the old location-derived fallback (this script's parent dir).
PLUGIN_ROOT="$( . "$HERE/resolve-loomwright-root.sh" 2>/dev/null && printf '%s' "$LOOMWRIGHT_ROOT" )" || PLUGIN_ROOT=""
[ -n "$PLUGIN_ROOT" ] || PLUGIN_ROOT="$(cd "$HERE/.." && pwd)"
META_SYNC="${LOOMWRIGHT_LANES_META_SYNC:-$HERE/meta-sync.sh}"
SETUP_MEMORY="${LOOMWRIGHT_LANES_SETUP_MEMORY:-$HERE/setup-memory.sh}"
HELPERS="${LOOMWRIGHT_LANES_HELPERS:-$HERE/automate-helpers.sh}"
TRAIL="${LOOMWRIGHT_LANES_TRAIL:-$HELPERS}"   # whose `trail-pr` runs the lane's evidence-gated push (F11)
POLICY="${LOOMWRIGHT_LANES_POLICY:-$HERE/lane-policy.sh}"      # resolve (lane-create) / decide (relay-hook)
RUN_LOCK="${LOOMWRIGHT_LANES_RUN_LOCK:-$HERE/run-lock.sh}"     # fleet-closeout's wave-lock release

# The lane allowlist (the minimum S1 found sufficient) and the DISALLOW list. These two are the only
# lines in this file that may name the merge / admin tokens (Validation 3 greps for them). The list
# also denies the GitHub merge endpoints reachable through `gh api` (the REST pulls/<n>/merge PUT and
# the GraphQL merge / auto-merge mutations); `gh api graphql` itself stays allowed because a lane's
# own drain reads review threads through it. Honest limit: a deny list is a TRIPWIRE, not a sandbox —
# any other route to the merge API (e.g. a raw HTTP client carrying a token) is not covered. The
# merge invariant's real backstop is that a lane only ever parks (`ready_for_release` in an N > 1 lane,
# `awaiting_merge` in a single lane — `lane-park`) and no lane runs the automate-loop §10 merge gate
# (`--auto-merge` is refused with any N).
LANE_ALLOWED_TOOLS="Bash,Read,Edit,Write,Glob,Grep,Task,Agent,AskUserQuestion"
LANE_DISALLOWED_FIXED="Bash(gh pr merge:*),Bash(gh pr merge *),Bash(*--admin*),Bash(gh api *pulls/*/merge*),Bash(gh api *mergePullRequest*),Bash(gh api *enablePullRequestAutoMerge*),Bash(git push --force:*),Bash(git push -f:*),Bash(git push --force-with-lease:*),Bash(git push *--force*)"
LANE_SYS="You are running as a HEADLESS lane (claude -p). Ending your turn ENDS this process and stops any background task. Never end your turn to wait for background work (CI, checks, subagents, long commands): wait in the FOREGROUND with a blocking Bash call or a Monitor you wait on. End your turn only when the item is parked, or when you must ask the owner via AskUserQuestion."
LANE_CONTINUE_MSG="continue where you left off; wait in the foreground"
LT_HEADER="$(printf '#lane\tpath\titem\trun_id\tpid\tpid_start\tsession_id\tstate\tlast_launch_utc\tblocked_reason')"

die() { echo "automate-lanes: $*" >&2; exit 1; }
# >>> module loader (_lanes_source / _lanes_bundle) — entry-point only, belongs to no module
# The lane code lives in automate-lanes.d/<name>.sh (automate-speed/19, move-only). Each module is
# sourced by ONE `_lanes_source <name> || …` line between `# >>> automate-lanes.d/<name>.sh` and
# `# <<< automate-lanes.d/<name>.sh` markers, at the position its text held when this was a single
# file, so `_lanes_bundle` (this script with each such line replaced by the module's text) reproduces
# that file's line order. Listed by name, never globbed: a stray file in automate-lanes.d/ is never
# sourced. The directory is resolved from THIS file's `${BASH_SOURCE[0]}`, never `$0` — automate-wave.sh
# and guard-lane-wait-armed.sh source this file, and `$0` is then the caller. `SELF` stays this entry
# point, so every `bash "$SELF" …` re-invocation and _lanes_usage's header read are unchanged.
# A missing or unreadable module fails CLOSED with `automate-lanes: missing module file:
# automate-lanes.d/<name>.sh` on stderr: run directly ⇒ exit 1; SOURCED ⇒ the source itself returns 1
# (never an exit), so a sourcing caller's own fallback runs.
_lanes_source() {
  local _lanes_f
  _lanes_f="$(dirname "${BASH_SOURCE[0]}")/automate-lanes.d/$1.sh"
  { [ -f "$_lanes_f" ] && [ -r "$_lanes_f" ]; } \
    || { echo "automate-lanes: missing module file: automate-lanes.d/$1.sh" >&2; return 1; }
  . "$_lanes_f"
}
# _lanes_bundle [<entry>] — print <entry> (default: this script) with every `_lanes_source <name> || …`
# line replaced by automate-lanes.d/<name>.sh read from beside it: ONE self-contained file (a test
# evals this one function and builds its mutants from the output). A missing, unreadable or empty
# module prints one stderr line naming it and returns 1.
_lanes_bundle() {
  local _lanes_e="${1:-$SELF}"
  LANES_MOD_DIR="$(dirname "$_lanes_e")/automate-lanes.d" awk '
    /^_lanes_source [a-z][a-z-]* \|\| \{ return 1 2>\/dev\/null \|\| exit 1; \}$/ {
      f = ENVIRON["LANES_MOD_DIR"] "/" $2 ".sh"; n = 0
      while ((r = (getline l < f)) > 0) { print l; n++ }
      close(f)
      if (r < 0 || n == 0) { print "automate-lanes: missing module file: automate-lanes.d/" $2 ".sh" > "/dev/stderr"; exit 1 }
      next
    }
    { print }
  ' "$_lanes_e"
}
# <<< module loader
# >>> automate-lanes.d/common.sh
_lanes_source common || { return 1 2>/dev/null || exit 1; }
# <<< automate-lanes.d/common.sh
# >>> automate-lanes.d/create.sh
_lanes_source create || { return 1 2>/dev/null || exit 1; }
# <<< automate-lanes.d/create.sh
# >>> automate-lanes.d/launch.sh
_lanes_source launch || { return 1 2>/dev/null || exit 1; }
# <<< automate-lanes.d/launch.sh
# >>> automate-lanes.d/relay.sh
_lanes_source relay || { return 1 2>/dev/null || exit 1; }
# <<< automate-lanes.d/relay.sh
# >>> automate-lanes.d/remove.sh
_lanes_source remove || { return 1 2>/dev/null || exit 1; }
# <<< automate-lanes.d/remove.sh
# >>> automate-lanes.d/notify-guards.sh
_lanes_source notify-guards || { return 1 2>/dev/null || exit 1; }
# <<< automate-lanes.d/notify-guards.sh
# >>> automate-lanes.d/status-read.sh
_lanes_source status-read || { return 1 2>/dev/null || exit 1; }
# <<< automate-lanes.d/status-read.sh
# >>> automate-lanes.d/park-leaks.sh
_lanes_source park-leaks || { return 1 2>/dev/null || exit 1; }
# <<< automate-lanes.d/park-leaks.sh
# >>> automate-lanes.d/status.sh
_lanes_source status || { return 1 2>/dev/null || exit 1; }
# <<< automate-lanes.d/status.sh
# >>> automate-lanes.d/readiness.sh
_lanes_source readiness || { return 1 2>/dev/null || exit 1; }
# <<< automate-lanes.d/readiness.sh
# >>> automate-lanes.d/wave.sh
_lanes_source wave || { return 1 2>/dev/null || exit 1; }
# <<< automate-lanes.d/wave.sh
_lanes_usage() { awk '/^# Usage \(standalone/ { on = 1 } on && /^#$/ { exit } on' "$SELF"; }

lanes_main() {
  local sub="${1:-}"; shift 2>/dev/null || true
  case "$sub" in
    lane-create) lanes_create "$@" ;;
    lane-launch) lanes_launch "$@" ;;
    relay-hook) lanes_relay_hook "$@" ;;
    lane-answer) lanes_answer "$@" ;;
    lane-remove) lanes_remove "$@" ;;
    lane-convert-ready) lanes_convert_ready "$@" ;;
    lane-info) lanes_info "$@" ;;
    lane-park) lanes_park "$@" ;;
    lane-drain-check) lanes_drain_check "$@" ;;
    init-check) lanes_init_check "$@" ;;
    pick-guard) lanes_pick_guard "$@" ;;
    branch-check) lanes_branch_check "$@" ;;
    lane-status) lanes_status "$@" ;;
    lane-feed) lanes_feed "$@" ;;
    lane-readiness) lanes_readiness "$@" ;;
    validation-gate) lanes_validation_gate "$@" ;;
    lane-park-notify) lanes_park_notify "$@" ;;
    lane-wait) lanes_wait "$@" ;;
    fleet-closeout) lanes_fleet_closeout "$@" ;;
    wave-plan) lanes_wave_plan "$@" ;;
    _lane-run) lanes_run_wrapper "$@" ;;
    _merge-hooks) _lanes_merge_hooks "$@" ;;
    -h|--help|help) _lanes_usage ;;
    *) _lanes_usage >&2; return 2 ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then lanes_main "$@"; exit $?; fi
