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
# LOOMWRIGHT_GH_BIN, LOOMWRIGHT_LANES_CI_SLOT, LOOMWRIGHT_LANES_PGREP, LOOMWRIGHT_LANES_CAFFEINATE,
# LOOMWRIGHT_LANES_UNAME, LOOMWRIGHT_LANES_COORDINATOR_PID, LOOMWRIGHT_LANES_BOOT_EPOCH,
# LOOMWRIGHT_LANES_TOKEN_LEDGER, LOOMWRIGHT_LANES_WATCH_ITERATIONS, LOOMWRIGHT_LANES_WATCH_INTERVAL_S,
# LOOMWRIGHT_LANES_LOCK_WAIT_S (default 30: the bound on waiting for a live lock holder),
# LOOMWRIGHT_LANES_TRAIL (default: the helpers path — whose `trail-pr` runs the lane's gated push),
# LOOMWRIGHT_LANES_NOTIFY_DESKTOP / LOOMWRIGHT_LANES_SEND_WEBHOOK (lane-park-notify's two notifiers),
# LOOMWRIGHT_LANES_POLICY (lane-policy.sh path), LOOMWRIGHT_LANES_RUN_LOCK (run-lock.sh path, fleet-closeout).
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
# merge invariant's real backstop is that a lane parks at ready_for_release and only the
# coordinator's automate-loop §10 gate ever executes a merge.
LANE_ALLOWED_TOOLS="Bash,Read,Edit,Write,Glob,Grep,Task,Agent,AskUserQuestion"
LANE_DISALLOWED_FIXED="Bash(gh pr merge:*),Bash(gh pr merge *),Bash(*--admin*),Bash(gh api *pulls/*/merge*),Bash(gh api *mergePullRequest*),Bash(gh api *enablePullRequestAutoMerge*),Bash(git push --force:*),Bash(git push -f:*),Bash(git push --force-with-lease:*),Bash(git push *--force*)"
LANE_SYS="You are running as a HEADLESS lane (claude -p). Ending your turn ENDS this process and stops any background task. Never end your turn to wait for background work (CI, checks, subagents, long commands): wait in the FOREGROUND with a blocking Bash call or a Monitor you wait on. End your turn only when the item is parked, or when you must ask the owner via AskUserQuestion."
LANE_CONTINUE_MSG="continue where you left off; wait in the foreground"
LT_HEADER="$(printf '#lane\tpath\titem\trun_id\tpid\tpid_start\tsession_id\tstate\tlast_launch_utc\tblocked_reason')"

die() { echo "automate-lanes: $*" >&2; exit 1; }
now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }
_trim_ws() { tr -s ' ' | sed 's/^ //; s/ $//'; }
_clean() { local v="${1:-}"; [ -n "$v" ] || v="-"; printf '%s' "$v" | tr '\t\n' '  '; }

# _lanes_need <argc> <subcmd> <flag> — a value-taking flag given last dies instead of `shift 2` looping.
_lanes_need() { [ "$1" -ge 2 ] || die "$2: $3 needs a value"; }

# ---- lane table (D6) ----------------------------------------------------------------------------
# Locks are `mkdir <file>.lock` dirs whose `holder` file (written atomically right after the mkdir)
# names the holder: this script's pid and its `ps -o lstart=` (read in the C locale, so a waiter
# with another LC_TIME never misreads a live holder as recycled). A lock is reclaimed ONLY when that
# holder is dead (pid gone, or a recycled pid with another start time), or when it has carried no
# holder for ~5 s (its creator died between the mkdir and the holder write, which takes
# milliseconds). A live holder is waited on, bounded by LOOMWRIGHT_LANES_LOCK_WAIT_S (default 30):
# past it _lt_lock returns 1 and the caller fails rather than steal the lock. A reclaim happens under
# a second `<file>.lock.reclaim` dir and re-reads the holder there, so two waiters never both remove
# the same stale lock (the second one would otherwise remove the first one's fresh lock). _lt_unlock
# removes a lock only when this process holds it. One process never takes the same lock twice.
_LT_ME=""
_lt_me() { # this process's holder line: "<pid> <lstart>"
  [ -n "$_LT_ME" ] || _LT_ME="$$ $(env LC_ALL=C ps -o lstart= -p "$$" 2>/dev/null | _trim_ws)"
  printf '%s' "$_LT_ME"
}
_lt_holder() { sed -n 1p "$1/holder" 2>/dev/null; }
_lt_holder_dead() { # <holder line> — 0 only for a holder that is VERIFIED gone
  local p="${1%% *}" s="" cur
  case "$1" in *" "*) s="${1#* }" ;; esac
  case "$p" in ''|*[!0-9]*) return 1 ;; esac
  command -v ps >/dev/null 2>&1 || return 1   # cannot verify ⇒ never steal
  cur="$(env LC_ALL=C ps -o lstart= -p "$p" 2>/dev/null | _trim_ws)"
  [ -z "$cur" ] && return 0
  [ -n "$s" ] && [ "$cur" != "$s" ] && return 0
  return 1
}
_lt_reclaim() { # <lockdir> <holder line seen ('' = holder-less)> — remove it iff still that stale state
  local d="$1" g="$1.reclaim" i=0
  while ! mkdir "$g" 2>/dev/null; do
    i=$((i + 1)); [ "$i" -gt 50 ] && { rmdir "$g" 2>/dev/null; i=0; }   # a reclaim takes milliseconds
    sleep 0.1
  done
  if [ -d "$d" ] && [ "$(_lt_holder "$d")" = "$2" ]; then rm -rf "$d"; fi
  rmdir "$g" 2>/dev/null
  return 0
}
_lt_lock() {
  local d="$1.lock" w="${LOOMWRIGHT_LANES_LOCK_WAIT_S:-30}" i=0 orphan=0 h
  case "$w" in ''|*[!0-9]*) w=30 ;; esac
  while ! mkdir "$d" 2>/dev/null; do
    h="$(_lt_holder "$d")"
    if [ -n "$h" ]; then
      orphan=0
      if _lt_holder_dead "$h"; then _lt_reclaim "$d" "$h"; continue; fi
    elif [ -d "$d" ]; then
      orphan=$((orphan + 1))
      if [ "$orphan" -ge 50 ]; then _lt_reclaim "$d" ""; orphan=0; continue; fi
    fi
    i=$((i + 1)); [ "$i" -ge $((w * 10)) ] && return 1
    sleep 0.1
  done
  printf '%s\n' "$(_lt_me)" > "$d/holder.tmp.$$" && mv "$d/holder.tmp.$$" "$d/holder"
  return 0
}
_lt_unlock() {
  local d="$1.lock"
  [ "$(_lt_holder "$d")" = "$(_lt_me)" ] || return 0
  rm -f "$d/holder"; rmdir "$d" 2>/dev/null
  return 0
}

# _lt_set <table> <lane> <col> <val> [<col> <val> ...] — rewrite one row's columns (1-based).
_lt_set() {
  local f="$1" lane="$2" spec="" rc; shift 2
  [ -f "$f" ] || return 1
  _lt_lock "$f" || { echo "automate-lanes: lane table lock busy (live holder): $f.lock" >&2; return 1; }
  (
    while [ "$#" -ge 2 ]; do export "LT_C$1=$(_clean "$2")"; spec="$spec $1"; shift 2; done
    LT_SPEC="$spec" LT_LANE="$lane" awk -F'\t' -v OFS='\t' '
      BEGIN { n = split(ENVIRON["LT_SPEC"], s, " ") }
      $1 == ENVIRON["LT_LANE"] { for (i = 1; i <= n; i++) $(s[i]) = ENVIRON["LT_C" s[i]] }
      { print }' "$f" > "$f.tmp.$$" && mv "$f.tmp.$$" "$f"
  )
  rc=$?; _lt_unlock "$f"; return "$rc"
}

# _lt_get <table> <lane> <col> — one column ('' for `-` or no row).
_lt_get() {
  [ -f "$1" ] || return 0
  awk -F'\t' -v l="$2" -v c="$3" '$1 == l { v = $c } END { if (v != "-") printf "%s", v }' "$1"
}

# ---- lane context -------------------------------------------------------------------------------
# _lane_ctx <lane_dir> — sets LN_* from <lane_dir>/.supervisor/lane.json; returns 1 when not a lane.
_lane_ctx() {
  local d="${1:-}" j
  [ -n "$d" ] && [ -d "$d" ] || return 1
  LN_DIR="$(cd "$d" && pwd -P)"; j="$LN_DIR/.supervisor/lane.json"
  [ -s "$j" ] || return 1
  LN_LANE="$(jq -r '.lane // empty' "$j" 2>/dev/null)"
  LN_RUN="$(jq -r '.run_id // empty' "$j" 2>/dev/null)"
  LN_PARENT="$(jq -r '.parent_run_id // empty' "$j" 2>/dev/null)"
  LN_PRIMARY="$(jq -r '.primary // empty' "$j" 2>/dev/null)"
  case "$LN_LANE" in L[0-9]|L[0-9][0-9]) ;; *) return 1 ;; esac
  case "$LN_PARENT" in ''|*/*|.*) return 1 ;; esac
  [ "$LN_RUN" = "$LN_PARENT-$LN_LANE" ] || return 1
  [ -n "$LN_PRIMARY" ] || return 1
  LN_TABLE="$LN_PRIMARY/.supervisor/automate/$LN_PARENT.lanes"
  LN_ROOT="$(dirname "$LN_DIR")"
  LN_LOG="$LN_ROOT/$LN_LANE.stream.log"
  LN_DIED="$LN_ROOT/$LN_LANE.died"
  LN_INBOX="$LN_DIR/.supervisor/inbox"
  return 0
}

# ---- shared liveness helper (lane-remove, pick-guard; Subtask 2's lane-status reuses it) ------------
# lanes_proc_alive <pid> <pid_start> <lane_dir> — 0 only for a VERIFIED live lane process.
lanes_proc_alive() {
  local pid="${1:-}" st="${2:-}" dir="${3:-}" cur cmd
  case "$pid" in ''|-|*[!0-9]*) return 1 ;; esac
  command -v ps >/dev/null 2>&1 || return 0   # cannot verify ⇒ treat as alive (callers are gates)
  cur="$(ps -o lstart= -p "$pid" 2>/dev/null | _trim_ws)"
  [ -n "$cur" ] || return 1
  [ "$cur" = "$(printf '%s' "$st" | _trim_ws)" ] || return 1
  cmd="$(ps -ww -o command= -p "$pid" 2>/dev/null)"
  case "$cmd" in
    *"automate-lanes.sh _lane-run $dir "*|*"automate-lanes.sh _lane-run $dir") return 0 ;;
  esac
  return 1
}

# _lanes_clip <n> — stdin (one line) clipped to at most <n> characters on a whitespace boundary and
# marked ` …`; a line that fits is unchanged, and a line with no whitespace to cut at is kept whole.
# Never `cut -c` alone: a cut inside a PR URL leaves a partial `owner/repo` slug, which meta-sync's
# forge_slug scrub refuses (fail closed) — wave W2's L2 metadata push stopped on exactly that.
_lanes_clip() {
  local s c
  s="$(cat)"; c="$(printf '%s' "$s" | cut -c1-"$1")"
  [ "$c" = "$s" ] && { printf '%s' "$s"; return 0; }
  case "$c" in
    *[[:space:]]*) printf '%s …' "$(printf '%s' "$c" | sed -E 's/[[:space:]]+[^[:space:]]*$//')" ;;
    *) printf '%s' "$s" ;;
  esac
}

# _lanes_pending_question <inbox> — prints the first recorded question id with no answer file.
_lanes_pending_question() {
  local q id
  for q in "$1"/questions/*.json; do
    [ -f "$q" ] || continue
    id="$(basename "$q" .json)"
    [ -e "$1/answers/$id.json" ] || { printf '%s' "$id"; return 0; }
  done
  return 1
}

# ---- meta-sync (always with --branch) -----------------------------------------------------------
# _lanes_meta_branch <root> — prints the branch for `on <Y>`, prints nothing for `off`, returns 1 otherwise.
_lanes_meta_branch() {
  local m; m="$(bash "$SETUP_MEMORY" --root "$1" mode 2>/dev/null | head -1)"
  case "$m" in
    "on "?*) printf '%s' "${m#on }" ;;
    off) ;;
    *) return 1 ;;
  esac
}

# ---- salvage (copy, never move) -----------------------------------------------------------------
_lanes_salvage() { # <dir> <dest_parent> <label> — prints the destination
  local dir="$1" dest="$2/$3-$(date -u +%Y%m%dT%H%M%SZ)-$$" f
  mkdir -p "$dest" || return 1
  if [ -d "$dir/.git" ]; then
    git -C "$dir" rev-parse HEAD > "$dest/BASE_SHA" 2>/dev/null
    git -C "$dir" status --porcelain > "$dest/status.txt" 2>/dev/null
    git -C "$dir" diff HEAD > "$dest/tracked.patch" 2>/dev/null
    git -C "$dir" ls-files --others --exclude-standard 2>/dev/null | while IFS= read -r f; do
      [ -n "$f" ] || continue; mkdir -p "$dest/untracked/$(dirname "$f")"; cp -p "$dir/$f" "$dest/untracked/$f" 2>/dev/null
    done
  fi
  [ -d "$dir/.supervisor" ] && cp -R "$dir/.supervisor" "$dest/supervisor" 2>/dev/null
  printf '%s' "$dest"
}

# ---- relay hook settings merge (never replaces an existing `hooks` key) -------------------------
_lanes_merge_hooks() { # <settings_file> <hook_command>
  local f="$1" cmd="$2" base="{}" out
  mkdir -p "$(dirname "$f")" || return 1
  if [ -s "$f" ]; then base="$(cat "$f")"; jq -e 'type == "object"' >/dev/null 2>&1 <<<"$base" || return 1; fi
  out="$(jq --arg h "$cmd" '
    def add($ev): .hooks[$ev] = (((.hooks[$ev]) // [])
      | if any(.[]?; (.hooks // []) | any(.[]?; .command == $h)) then .
        else . + [{matcher: "AskUserQuestion", hooks: [{type: "command", command: $h}]}] end);
    .hooks = (.hooks // {}) | add("PreToolUse") | add("PermissionRequest")' <<<"$base")" || return 1
  printf '%s\n' "$out" > "$f.tmp.$$" && mv "$f.tmp.$$" "$f"
}

# ==================================================================================================
# lane-create <parent_runfile> <item> <n> [--parallel N] [--max-tokens T]
lanes_create() {
  local runfile="" item="" n="" par="" maxt="" a single=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --parallel) _lanes_need "$#" lane-create "$1"; par="$2"; shift 2; if [ "$par" = 1 ]; then single=1; else single=0; fi ;;
      --max-tokens) _lanes_need "$#" lane-create "$1"; maxt="$2"; shift 2 ;;
      *) if [ -z "$runfile" ]; then runfile="$1"; elif [ -z "$item" ]; then item="$1"; elif [ -z "$n" ]; then n="$1"
         else die "lane-create: unexpected argument '$1'"; fi; shift ;;
    esac
  done
  [ -n "$runfile" ] && [ -n "$item" ] && [ -n "$n" ] || die "usage: lane-create <parent_runfile> <item> <n> [--parallel N] [--max-tokens T]"
  # Single-lane mode (an EXPLICIT `--parallel 1` — never inferred from `par`, whose default is n) takes a
  # fresh lane number per item, so its bound is 1..99; every other caller keeps 1..10.
  if [ "$single" = 1 ]; then
    case "$n" in [1-9]|[1-9][0-9]) ;; *) die "lane-create: lane number must be 1..99 in single-lane mode (got '$n')" ;; esac
  else
    case "$n" in [1-9]|10) ;; *) die "lane-create: lane number must be 1..10 (got '$n')" ;; esac
  fi
  [ -n "$par" ] || par="$n"
  case "$par" in [1-9]|10) ;; *) die "lane-create: --parallel must be 1..10 (got '$par')" ;; esac
  case "$maxt" in ''|*[!0-9]*) [ -z "$maxt" ] || die "lane-create: --max-tokens must be a whole number" ;; esac
  case "$item" in /*|*..*) die "lane-create: item must be the canonical repo-relative path (got '$item')" ;; esac
  [ -f "$runfile" ] || die "lane-create: run file not found: $runfile"
  local rdir parent primary
  rdir="$(cd "$(dirname "$runfile")" && pwd -P)"; parent="$(basename "$runfile" .md)"
  case "$parent" in ''|*/*|.*|*-L[0-9]|*-L[0-9][0-9]) die "lane-create: bad parent run file name '$parent'" ;; esac
  [ "$(basename "$rdir")" = automate ] && [ "$(basename "$(dirname "$rdir")")" = .supervisor ] \
    || die "lane-create: run file must live in <primary>/.supervisor/automate/"
  primary="$(cd "$rdir/../.." && pwd -P)"
  [ "$(git -C "$primary" rev-parse --show-toplevel 2>/dev/null)" = "$primary" ] || die "lane-create: $primary is not a git checkout root"
  [ -f "$primary/$item" ] || die "lane-create: item not found in the primary: $item"
  local url; url="$(git -C "$primary" remote get-url origin 2>/dev/null)"
  [ -n "$url" ] || die "lane-create: refused — the primary has no origin remote"
  local lane="L$n" lroot="$primary-lanes/$parent" C run_id="$parent-L$n" table="$rdir/$parent.lanes"
  C="$lroot/$lane"
  local spent=""
  if [ "$single" = 1 ]; then
    # A single lane takes a FRESH number: one already in this run's table (live, removed or abandoned) is
    # refused — its run id, salvage and logs belong to an earlier item. Nothing is created.
    if [ -f "$table" ] && awk -F'\t' -v l="$lane" '$1 == l { f = 1 } END { exit !f }' "$table" 2>/dev/null; then
      echo "lane-create: refused — lane $lane already used in this run (single-lane takes a fresh number)" >&2
      return 1
    fi
    # Whole-run token ceiling (owner decision 3): T bounds the RUN, not each lane.
    if [ -n "$maxt" ]; then
      if ! spent="$(_lanes_single_spent "$table" "$runfile")"; then
        echo "lane-create: refused — token_ceiling ledger_unreadable" >&2; return 1
      fi
      if [ "$spent" -ge "$((10#$maxt))" ]; then
        echo "lane-create: refused — token_ceiling total=$spent max=$((10#$maxt))" >&2; return 1
      fi
    fi
  fi
  if [ -e "$C" ]; then
    local sv; sv="$(_lanes_salvage "$C" "$lroot/salvage" "$lane-leftover")"
    echo "lane-create: refused — leftover lane directory $C (salvaged to ${sv:-<salvage failed>}); never reused" >&2
    return 1
  fi
  mkdir -p "$lroot" || die "lane-create: cannot create $lroot"
  _abort() { rm -rf "$C"; echo "lane-create: aborted $lane — $1 (clone removed)" >&2; return 1; }
  git clone -q --local "$primary" "$C" 2>/dev/null || { _abort "clone failed"; return 1; }
  # origin = the primary's remote URL BEFORE any fetch; prune the refs the --local clone inherited.
  git -C "$C" remote set-url origin "$url" || { _abort "could not set origin"; return 1; }
  git -C "$C" fetch -q --prune origin 2>/dev/null || { _abort "fetch from origin failed"; return 1; }
  git -C "$C" for-each-ref --format='%(refname)' refs/remotes/origin | while IFS= read -r a; do
    git -C "$C" rev-parse -q --verify "$a" >/dev/null 2>&1 || git -C "$C" update-ref -d "$a" 2>/dev/null
  done
  git -C "$C" remote set-head origin -a >/dev/null 2>&1
  local base; base="$(git -C "$C" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"; base="${base#origin/}"
  [ -n "$base" ] || base=main
  git -C "$C" checkout -q -B "$base" "origin/$base" 2>/dev/null || { _abort "base branch origin/$base not found"; return 1; }
  # metadata pull (always --branch); non-zero ⇒ abort the lane.
  local mb
  if ! mb="$(_lanes_meta_branch "$C")"; then _abort "metadata mode unknown"; return 1; fi
  if [ -n "$mb" ]; then
    bash "$META_SYNC" pull --branch "$mb" --root "$C" >/dev/null 2>&1 || { _abort "meta-sync pull --branch $mb failed"; return 1; }
  fi
  [ -f "$C/$item" ] || { _abort "item $item absent in the lane after the metadata pull"; return 1; }
  mkdir -p "$C/.supervisor/automate" "$C/.supervisor/inbox/questions" "$C/.supervisor/inbox/answers" || { _abort "cannot create .supervisor"; return 1; }
  local cf
  for cf in config.json notify-config.json; do
    if [ -f "$primary/.supervisor/$cf" ]; then cp -p "$primary/.supervisor/$cf" "$C/.supervisor/$cf" || { _abort "cannot copy $cf"; return 1; }; fi
  done
  local mt=null
  if [ -n "$maxt" ]; then
    if [ "$single" = 1 ]; then mt=$((10#$maxt - spent)); else mt=$((10#$maxt / par)); fi
  fi
  # Policy carry (parallel-automate/21 B5): `lane-policy.sh resolve` runs HERE, in the primary — the rules
  # stamp is keyed per clone, so a lane can never verify the project policy itself. Its report lines
  # (`lane-policy: project policy ignored — …`, `lane-policy: dropped …`) reach this command's stderr
  # verbatim. Anything but a non-empty answers object with a policy_sha (no policy, a usage error, an
  # unreadable result) carries `"policy": null` — the lane then relays every question as before.
  local pol pj=null ps=none
  pol="$(bash "$POLICY" resolve "$runfile" --root "$primary" </dev/null)" || pol=""
  if jq -e 'type == "object" and (.policy_sha | type) == "string" and (.answers | type) == "object"
      and (.answers | length) > 0' >/dev/null 2>&1 <<<"$pol"; then
    pj="$(jq -c . <<<"$pol")"; ps="$(jq -r '"\(.policy_sha[0:12]):\(.answers | length)"' <<<"$pol")"
  fi
  jq -n --arg lane "$lane" --arg run "$run_id" --arg parent "$parent" --arg primary "$primary" \
    --argjson parallel "$par" --argjson mt "$mt" --arg created "$(now_utc)" --argjson policy "$pj" \
    --argjson single "$single" \
    '{schema_version: 1, lane: $lane, run_id: $run, parent_run_id: $parent, primary: $primary,
      parallel: $parallel, max_tokens: $mt, created: $created, policy: $policy}
      + (if $single == 1 then {single_lane: true} else {} end)' > "$C/.supervisor/lane.json" \
    || { _abort "cannot write lane.json"; return 1; }
  printf -- '- [ ] %s\n' "$item" > "$C/.supervisor/lane-backlog.md" || { _abort "cannot write the backlog"; return 1; }
  _lanes_merge_hooks "$C/.claude/settings.local.json" "bash \"$PLUGIN_ROOT/scripts/automate-lanes.sh\" relay-hook" \
    || { _abort "cannot merge the relay hooks"; return 1; }
  local porc; porc="$(git -C "$C" status --porcelain 2>/dev/null)"
  [ -z "$porc" ] || { _abort "lane is not clean after setup: $(printf '%s' "$porc" | head -3 | tr '\n' ' ')"; return 1; }
  _lt_lock "$table" || { _abort "lane table lock busy (live holder): $table.lock"; return 1; }
  if [ ! -s "$table" ]; then
    { printf '%s\n' "$LT_HEADER"
      printf '# not carried into lanes: .claude/settings.local.json (relay hooks only), the rules stamp, Claude auto-memory\n'; } > "$table"
  fi
  awk -F'\t' -v l="$lane" '$1 != l' "$table" > "$table.tmp.$$" && mv "$table.tmp.$$" "$table"
  printf '%s\t%s\t%s\t%s\t-\t-\t-\tcreated\t-\t-\n' "$lane" "$C" "$(_clean "$item")" "$run_id" >> "$table"
  _lt_unlock "$table"
  echo "lane-create: $lane $C run_id=$run_id item=$item meta=${mb:-off} policy=$ps"
}

# ==================================================================================================
# _lanes_regime_ok — the CLI advertises a pinnable permission regime.
_lanes_regime_ok() {
  local h; h="$(claude --help 2>&1)" || true
  case "$h" in *--permission-prompt-tool*) ;; *) return 1 ;; esac
  case "$h" in *--allowedTools*) ;; *) return 1 ;; esac
  case "$h" in *--disallowedTools*) ;; *) return 1 ;; esac
  return 0
}

# _lanes_admission — prints the HELD reason and returns 1 when the launch must hold.
_lanes_admission() {
  [ -e "$LN_PRIMARY/.supervisor/automate/$LN_PARENT.memory-pressure" ] && { printf 'memory_pressure'; return 1; }
  local cmd="${LOOMWRIGHT_MACHINE_LOAD_CMD:-$HERE/machine-load.sh}" st=unknown
  if [ -f "$cmd" ]; then st="$(bash "$cmd" --json 2>/dev/null | jq -r '.state // "unknown"' 2>/dev/null | head -1)"; fi
  case "$st" in
    overloaded) printf 'load overloaded'; return 1 ;;
    busy)
      local rs="${LOOMWRIGHT_LANE_RECHECK_S:-60}" now t e
      case "$rs" in ''|*[!0-9]*) rs=60 ;; esac
      now="$(date -u +%s)"
      for t in $(awk -F'\t' '!/^#/ && $9 != "-" { print $9 }' "$LN_TABLE" 2>/dev/null); do
        e="$(jq -n --arg t "$t" '$t | fromdateiso8601' 2>/dev/null)" || continue
        case "$e" in ''|*[!0-9]*) continue ;; esac
        if [ $((now - e)) -lt "$rs" ]; then printf 'load busy'; return 1; fi
      done ;;
  esac
  return 0
}

# Launch lock (one per lane: <table>.<lane>.launch.lock, the _lt_lock helper): held from _lanes_gate's
# "not already running" check until _lanes_spawn has recorded the new pid in the lane table and that
# pid reads alive (lanes_proc_alive), so two overlapping lane-launch / lane-answer calls for one lane
# never both spawn: the second waits, then sees the lane running and is refused. Never held across
# the session-id wait, and never taken twice by one process.
LN_LAUNCH_LOCKED=0
_lanes_launch_lock() { _lt_lock "$LN_TABLE.$LN_LANE.launch" || return 1; LN_LAUNCH_LOCKED=1; }   # LAUNCHLOCK
_lanes_launch_unlock() { [ "$LN_LAUNCH_LOCKED" = 1 ] || return 0; _lt_unlock "$LN_TABLE.$LN_LANE.launch"; LN_LAUNCH_LOCKED=0; }

# ---- gate opt-out carry (launch contract 3a) --------------------------------------------------------
# _lanes_optout_set — the test-integrity guard's opt-out is set in THIS process's environment: the SAME
# predicate guard-test-integrity.sh applies (`= "1"` exactly; any other value is unset).
_lanes_optout_set() { [ "${LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS:-}" = "1" ]; }
# _lanes_optout_file — the coordinator-side fact file (primary's automate dir; never the lane's lane.json).
_lanes_optout_file() { printf '%s' "$LN_PRIMARY/.supervisor/automate/$LN_PARENT.$LN_LANE.gate-optout"; }
# _lanes_optout_record — at a FIRST launch only: record the fact (no value) when the opt-out is set and
# not dropped by --without-gate-optout, else remove any earlier record. Returns 1 when the record cannot
# be written (the caller refuses the launch: an unrecorded opt-out would silently block a later resume).
_lanes_optout_record() {
  local f; f="$(_lanes_optout_file)"
  if _lanes_optout_set && [ "$LN_WITHOUT_OPTOUT" != 1 ]; then
    { printf 'gate_optout_at_launch\t%s\n' "$(now_utc)" > "$f.tmp.$$" && mv "$f.tmp.$$" "$f"; } 2>/dev/null \
      || { rm -f "$f.tmp.$$" 2>/dev/null; return 1; }
  else
    rm -f "$f" 2>/dev/null
  fi
  return 0
}
LN_WITHOUT_OPTOUT=0; LN_STRIP_OPTOUT=0; LN_GATE_OPTOUT_BLOCKED=0

# _lanes_gate <owner_cmd> [<resume 0|1>] — authority, liveness, the gate opt-out carry (resumes only),
# regime, admission. Prints the first line; returns the exit code. LN_GATE_OPTOUT_BLOCKED=1 marks the
# opt-out refusal (lane-answer keeps its validated answer pending on it, as on HELD).
_lanes_gate() {
  local owner="$1" resume="${2:-0}" why
  LN_GATE_OPTOUT_BLOCKED=0
  if [ -z "$owner" ]; then
    echo "lane-launch: BLOCKED — $LN_LANE — no owner-invoked command — need the owner"
    _lt_set "$LN_TABLE" "$LN_LANE" 8 blocked_launch 10 "no owner-invoked command"; return 3
  fi
  if lanes_proc_alive "$(_lt_get "$LN_TABLE" "$LN_LANE" 5)" "$(_lt_get "$LN_TABLE" "$LN_LANE" 6)" "$LN_DIR"; then
    echo "lane-launch: refused — $LN_LANE — already running (pid $(_lt_get "$LN_TABLE" "$LN_LANE" 5))"; return 1
  fi
  if [ "$resume" = 1 ] && [ -e "$(_lanes_optout_file)" ] && ! _lanes_optout_set && [ "$LN_WITHOUT_OPTOUT" != 1 ]; then
    echo "lane-launch: BLOCKED — $LN_LANE — launched with the test-integrity guard's opt-out; this resume's environment lacks it — re-run the same command with it set, or add --without-gate-optout to resume without it — need the owner"
    LN_GATE_OPTOUT_BLOCKED=1
    _lt_set "$LN_TABLE" "$LN_LANE" 8 blocked_launch 10 "launched with the test-integrity guard's opt-out; this resume's environment lacks it"; return 3
  fi
  if ! _lanes_regime_ok; then
    echo "lane-launch: BLOCKED — $LN_LANE — CLI advertises no pinnable permission regime — need the owner"
    _lt_set "$LN_TABLE" "$LN_LANE" 8 blocked_launch 10 "no pinnable permission regime"; return 3
  fi
  if ! why="$(_lanes_admission)"; then
    echo "lane-launch: HELD — $LN_LANE — $why"
    _lt_set "$LN_TABLE" "$LN_LANE" 8 held_for_load 10 "$why"; return 4
  fi
  # --without-gate-optout: the owner chose to run without it — drop it from the spawn's environment and,
  # on a resume, clear the recorded fact (only now: a refused or HELD call leaves the record unchanged).
  if [ "$LN_WITHOUT_OPTOUT" = 1 ]; then
    LN_STRIP_OPTOUT=1
    [ "$resume" = 1 ] && rm -f "$(_lanes_optout_file)" 2>/dev/null
  fi
  return 0
}

# _lanes_spawn <prompt|''> <session_id|''> <label> — the detached nohup wrapper around `claude -p`.
# Sets LN_SPAWN_PID and LN_SPAWN_SID (the `system/init` session id, '' when none appeared). The env
# carries LOOMWRIGHT_LANE_RESUME_PATH = LN_RESUME_PATH (set only by a `--resume-run` launch; empty
# otherwise) — how the lane's own engine learns which resume path it is on (§14 INIT).
LN_RESUME_PATH=""; LN_SPAWN_PID=""; LN_SPAWN_SID=""
_lanes_spawn() {
  local prompt="$1" sid="$2" label="$3" base disallow in pid st off i s=""
  base="$(git -C "$LN_DIR" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"; base="${base#origin/}"; [ -n "$base" ] || base=main
  disallow="$LANE_DISALLOWED_FIXED,Bash(git push origin $base:*),Bash(git push origin HEAD:$base:*),Bash(git push origin HEAD:refs/heads/$base:*),Bash(git push -u origin $base:*)"
  local -a flags=(-p --input-format stream-json --output-format stream-json --verbose
    --permission-prompt-tool stdio --permission-mode acceptEdits
    --allowedTools "$LANE_ALLOWED_TOOLS" --disallowedTools "$disallow"
    --plugin-dir "$PLUGIN_ROOT" --append-system-prompt "$LANE_SYS")
  [ -n "$sid" ] && flags+=(--resume "$sid")
  local -a envu=(-u CLAUDECODE -u CLAUDE_PID -u LOOMWRIGHT_HOLDER_PID)   # a coordinator's holder pin never reaches a lane
  [ "$LN_STRIP_OPTOUT" = 1 ] && envu+=(-u LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS)   # --without-gate-optout
  in=/dev/null
  if [ -n "$prompt" ]; then
    in="$LN_ROOT/$LN_LANE.stdin.json"
    jq -n -c --arg c "$prompt" '{type: "user", message: {role: "user", content: $c}}' > "$in" || return 1
  fi
  touch "$LN_LOG"; rm -f "$LN_DIED"
  off="$(wc -c < "$LN_LOG" | tr -d ' ')"
  # >>> spawn (the only process start; it writes nothing into the lane directory)
  nohup bash "$SELF" _lane-run "$LN_DIR" "$LN_LOG" "$LN_DIED" "$in" -- \
    env "${envu[@]}" CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 \
    LOOMWRIGHT_LANE_RESUME_PATH="${LN_RESUME_PATH:-}" claude "${flags[@]}" >> "$LN_LOG" 2>&1 &
  pid=$!; LN_SPAWN_PID="$pid"; LN_SPAWN_SID=""
  # <<< spawn
  st="$(ps -o lstart= -p "$pid" 2>/dev/null | _trim_ws)"
  _lt_set "$LN_TABLE" "$LN_LANE" 5 "$pid" 6 "$st" 8 launched 9 "$(now_utc)" 10 -
  # the launch lock is released only once a second caller's liveness check would see this process
  # (until nohup has exec'd the wrapper its command line is still this script's)
  i=0
  while [ "$i" -lt 25 ] && kill -0 "$pid" 2>/dev/null && ! lanes_proc_alive "$pid" "$st" "$LN_DIR"; do sleep 0.1; i=$((i + 1)); done
  _lanes_launch_unlock
  local w="${LOOMWRIGHT_LANES_INIT_WAIT_S:-15}"; case "$w" in ''|*[!0-9]*) w=15 ;; esac
  i=0
  while [ "$i" -lt $((w * 5)) ]; do
    s="$(tail -c +"$((off + 1))" "$LN_LOG" 2>/dev/null | grep '^{' | jq -r -R 'fromjson? | select(.type == "system" and .subtype == "init") | .session_id // empty' 2>/dev/null | head -1)"
    [ -n "$s" ] && break
    kill -0 "$pid" 2>/dev/null || { sleep 0.2; s="$(tail -c +"$((off + 1))" "$LN_LOG" 2>/dev/null | grep '^{' | jq -r -R 'fromjson? | select(.type == "system" and .subtype == "init") | .session_id // empty' 2>/dev/null | head -1)"; break; }
    sleep 0.2; i=$((i + 1))
  done
  [ -n "$s" ] && _lt_set "$LN_TABLE" "$LN_LANE" 7 "$s"
  LN_SPAWN_SID="$s"
  echo "lane-launch: launched $LN_LANE (pid $pid, session ${s:-unknown}) $label"
}

# _lane-run <lane_dir> <log> <died> <stdin> -- <cmd...> — the nohup wrapper (its argv carries the lane dir).
lanes_run_wrapper() {
  local dir="$1" log="$2" died="$3" in="$4" off cp rc=0; shift 4; [ "${1:-}" = "--" ] && shift
  off="$(wc -c < "$log" 2>/dev/null | tr -d ' ')"; off="${off:-0}"
  cd "$dir" || exit 1
  "$@" < "$in" &
  cp=$!
  trap 'kill -TERM "$cp" 2>/dev/null' TERM INT HUP
  wait "$cp"; rc=$?
  while kill -0 "$cp" 2>/dev/null; do wait "$cp"; rc=$?; done
  if ! tail -c +"$((off + 1))" "$log" 2>/dev/null | grep -q '"type": *"result"'; then
    printf 'died_at\t%s\nexit\t%s\n' "$(now_utc)" "$rc" > "$died"
  fi
  exit "$rc"
}

# ==================================================================================================
# lane-launch <lane_dir> --owner-command '<cmd>' [--resume-run <run_id> | --continue] | --host-denied '<reason>'
lanes_launch() {
  local dir="" owner="" resume_run="" cont=0 denied="" denied_set=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --owner-command) _lanes_need "$#" lane-launch "$1"; owner="$2"; shift 2 ;;
      --resume-run) _lanes_need "$#" lane-launch "$1"; resume_run="$2"; [ -n "$resume_run" ] || die "lane-launch: --resume-run needs a run id"; shift 2 ;;
      --continue) cont=1; shift ;;
      --without-gate-optout) LN_WITHOUT_OPTOUT=1; shift ;;
      --host-denied) _lanes_need "$#" lane-launch "$1"; denied="${2:-host denied the spawn}"; denied_set=1; shift 2 ;;
      *) [ -z "$dir" ] || die "lane-launch: unexpected argument '$1'"; dir="$1"; shift ;;
    esac
  done
  _lane_ctx "$dir" || die "lane-launch: not a lane (no valid .supervisor/lane.json): ${dir:-<none>}"
  if [ "$denied_set" = 1 ]; then
    echo "lane-launch: BLOCKED — $LN_LANE — $denied — need the owner"
    _lt_set "$LN_TABLE" "$LN_LANE" 8 blocked_launch 10 "$denied"; return 3
  fi
  _lanes_launch_lock || { echo "lane-launch: refused — $LN_LANE — launch lock busy (another launch of this lane is in flight)"; return 1; }
  local rc res=0; { [ -n "$resume_run" ] || [ "$cont" = 1 ]; } && res=1
  _lanes_gate "$owner" "$res"; rc=$?
  [ "$rc" = 0 ] && { _lanes_launch_go "$resume_run" "$cont"; rc=$?; }
  _lanes_launch_unlock
  return "$rc"
}

# _lanes_launch_go <resume_run|''> <continue 0|1> — the launch proper (caller holds the launch lock).
_lanes_launch_go() {
  local resume_run="$1" cont="$2"
  if [ -n "$resume_run" ]; then
    [ "$resume_run" = "$LN_RUN" ] || { echo "lane-launch: refused — $LN_LANE resumes only its own run ($LN_RUN), not '$resume_run'"; return 1; }
    [ -f "$LN_DIR/.supervisor/automate/$LN_RUN.md" ] || { echo "lane-launch: refused — no run file $LN_RUN.md in $LN_LANE"; return 1; }
    # F4: resume the lane's LAST session, so its own run.lock (session-id re-entrant) never stalls the
    # resume of a lane that died after its PICK took the lock. A fresh session is the fallback only
    # when no session is recorded, or the resume of it exited at once with no session (`claude
    # --resume` refused it). The coordinator never writes the lane's run file or lock: the lane's
    # engine records the path from LOOMWRIGHT_LANE_RESUME_PATH on entry.
    local rsid; rsid="$(_lanes_session_id)"
    if [ -n "$rsid" ]; then
      LN_RESUME_PATH="session $rsid"
      _lanes_spawn "/loomwright:automate --resume $LN_RUN" "$rsid" "(resume $LN_RUN in its last session $rsid)" || return 1
      if [ -n "$LN_SPAWN_SID" ] || kill -0 "$LN_SPAWN_PID" 2>/dev/null; then return 0; fi
      echo "lane-launch: $LN_LANE — session $rsid could not be resumed (exited with no session); falling back to a fresh session"
      _lanes_launch_lock || { echo "lane-launch: refused — $LN_LANE — launch lock busy (another launch of this lane is in flight)"; return 1; }
      if lanes_proc_alive "$(_lt_get "$LN_TABLE" "$LN_LANE" 5)" "$(_lt_get "$LN_TABLE" "$LN_LANE" 6)" "$LN_DIR"; then
        echo "lane-launch: refused — $LN_LANE — already running (pid $(_lt_get "$LN_TABLE" "$LN_LANE" 5))"; return 1
      fi
      LN_RESUME_PATH="fresh session (last session $rsid not resumable)"
    else
      LN_RESUME_PATH="fresh session (no recorded session)"
    fi
    _lanes_spawn "/loomwright:automate --resume $LN_RUN" "" "(resume $LN_RUN in a fresh session)"
  elif [ "$cont" = 1 ]; then
    local sid; sid="$(_lanes_session_id)"
    [ -n "$sid" ] || { echo "lane-launch: refused — $LN_LANE has no recorded session to continue"; return 1; }
    _lanes_spawn "$LANE_CONTINUE_MSG" "$sid" "(continue)"
  else
    [ -s "$LN_DIR/.supervisor/lane-backlog.md" ] || { echo "lane-launch: refused — $LN_LANE has no backlog (setup incomplete)"; return 1; }
    jq -e '[.hooks.PreToolUse[]?.hooks[]?.command] | any(test("automate-lanes.sh\" relay-hook"))' \
      "$LN_DIR/.claude/settings.local.json" >/dev/null 2>&1 \
      || { echo "lane-launch: refused — $LN_LANE has no relay hook (a lane never runs without its question channel)"; return 1; }
    _lanes_optout_record \
      || { echo "lane-launch: refused — $LN_LANE — cannot record the gate opt-out fact ($(_lanes_optout_file)); a resume could not detect it"; return 1; }
    _lanes_spawn "/loomwright:automate --backlog $LN_DIR/.supervisor/lane-backlog.md" "" "(launch)"
  fi
}

# _lanes_session_id — the lane table's session id, else the newest `system/init` in the stream log.
_lanes_session_id() {
  local s; s="$(_lt_get "$LN_TABLE" "$LN_LANE" 7)"
  [ -n "$s" ] || s="$(grep '^{' "$LN_LOG" 2>/dev/null | jq -r -R 'fromjson? | select(.type == "system" and .subtype == "init") | .session_id // empty' 2>/dev/null | tail -1)"
  printf '%s' "$s"
}

_lanes_last_result() { grep '^{' "$1" 2>/dev/null | jq -c -R 'fromjson? | select(.type == "result")' 2>/dev/null | tail -1; }

# _lanes_hook_root <cwd> — prints the lane checkout a hook's cwd belongs to; returns 1 when none.
# A question asked from a worker's linked worktree (../{repo}-{task_id}-{slug}: OUTSIDE the lane dir,
# no lane.json) must still reach the LANE's inbox, so the cwd's own toplevel is not enough: the lane is
# the MAIN checkout of the cwd's repository, the parent of its git common dir. `--path-format=absolute`
# needs git >= 2.31; an older git (no absolute answer) is asked again from the toplevel, where its
# relative answer resolves unambiguously. Candidates, first holding a non-empty lane.json wins: that
# main checkout, the cwd's toplevel, the cwd itself.
_lanes_hook_root() {
  local cwd="$1" top gcd main="" c nl
  nl="$(printf '\nx')"; nl="${nl%x}"
  top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"
  gcd="$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  case "$gcd" in *"$nl"*|"") gcd="" ;; /*) ;; *) gcd="" ;; esac
  if [ -z "$gcd" ] && [ -n "$top" ]; then
    gcd="$(git -C "$top" rev-parse --git-common-dir 2>/dev/null)"
    case "$gcd" in *"$nl"*|"") gcd="" ;; /*) ;; *) gcd="$(cd "$top" 2>/dev/null && cd "$gcd" 2>/dev/null && pwd -P)" ;; esac
  fi
  [ -n "$gcd" ] && [ "$(basename "$gcd")" = .git ] && main="$(dirname "$gcd")"
  for c in "$main" "$top" "$cwd"; do
    [ -n "$c" ] && [ -s "$c/.supervisor/lane.json" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

# ==================================================================================================
# relay-hook — PreToolUse[AskUserQuestion]: answer recorded ⇒ allow + updatedInput, else record + defer.
#              PermissionRequest[AskUserQuestion] (bundled call, defer ignored) ⇒ deny with a re-ask.
lanes_relay_hook() {
  local in ev cwd root id q a
  in="$(cat)"
  ev="$(jq -r '.hook_event_name // empty' <<<"$in" 2>/dev/null)"
  if [ "$ev" = "PermissionRequest" ]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"AskUserQuestion must be the ONLY tool call in its turn (the answer is relayed to the owner). Call AskUserQuestion again, alone, in a turn of its own."}}}'
    return 0
  fi
  [ "$ev" = "PreToolUse" ] || { echo '{}'; return 0; }
  cwd="$(jq -r '.cwd // empty' <<<"$in" 2>/dev/null)"; [ -n "$cwd" ] || cwd="${CLAUDE_PROJECT_DIR:-$PWD}"
  root="$(_lanes_hook_root "$cwd")" || { echo '{}'; return 0; }   # HOOK-ROOT
  [ -s "$root/.supervisor/lane.json" ] || { echo '{}'; return 0; }
  id="$(jq -r '.tool_use_id // empty' <<<"$in" 2>/dev/null)"
  case "$id" in ''|*[!A-Za-z0-9_-]*) echo '{}'; return 0 ;; esac
  q="$root/.supervisor/inbox/questions/$id.json"; a="$root/.supervisor/inbox/answers/$id.json"
  mkdir -p "$(dirname "$q")" "$(dirname "$a")" 2>/dev/null
  if [ ! -s "$a" ]; then
    jq -c --arg at "$(now_utc)" '{id: .tool_use_id, asked_at: $at, questions: .tool_input.questions}' <<<"$in" > "$q.tmp.$$" \
      && mv "$q.tmp.$$" "$q"
    # No policy answer (policy null, `human`, any error) ⇒ exactly the pre-policy defer.
    _lanes_policy_apply "$root" "$q" "$a" \
      || { echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"defer"}}'; return 0; }
  fi
  jq -c --slurpfile ans "$a" '
    ($ans[0].answers) as $A | ($ans[0].note) as $N
    | {hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow",
        permissionDecisionReason: (if $ans[0].source == "policy"
          then "answered by the stamped lane policy (gate \($ans[0].gate // "?"), policy_sha \(($ans[0].policy_sha // "?")[0:12])) via automate-lanes.sh relay-hook"
          else "answered by the owner via automate-lanes.sh lane-answer" end),
        updatedInput: ({questions: .tool_input.questions, answers: $A}
          + (if ($N // "") == "" then {} else {annotations: ($A | with_entries(.value = {notes: $N}))} end))}}' <<<"$in"
}

# _lanes_policy_apply <lane_root> <question_file> <answer_file> — B6: the lane's OWN hook applies a
# policy answer. Returns 1 (caller defers to the human, unchanged) unless lane.json carries a `policy`
# object, `lane-policy.sh decide` answers EVERY question of the call, that answer passes
# _lanes_validate_answers (the owner's own validator) and the answer file is written. The answer file
# mirrors lane-answer's shape with `source: "policy"`, `policy_sha`, `gate` (the call's catalog codes,
# comma-joined) and `via: "policy"`. The `## Progress` line is fail-SAFE: a failed append never blocks
# the answer (the answer file is the record the lane reads).
_lanes_policy_apply() {
  local root="$1" q="$2" af="$3" lj="$1/.supervisor/lane.json" dec ain out sha gate run line
  jq -e '(.policy | type) == "object"' "$lj" >/dev/null 2>&1 || return 1
  [ -s "$q" ] || return 1
  dec="$(bash "$POLICY" decide "$q" --policy-json "$lj" 2>/dev/null </dev/null)" || return 1
  jq -e 'type == "object" and length > 0' >/dev/null 2>&1 <<<"$dec" || return 1   # `human` ⇒ the owner
  ain="$(jq -c '{answers: .}' <<<"$dec" 2>/dev/null)" || return 1
  out="$(_lanes_validate_answers "$q" "$ain")" || return 1
  jq -e 'type == "object" and length > 0' >/dev/null 2>&1 <<<"$out" || return 1
  sha="$(jq -r '.policy.policy_sha // empty' "$lj" 2>/dev/null)"; [ -n "$sha" ] || return 1
  gate="$(jq -r '[.questions[]?.header // "?"] | join(",")' "$q" 2>/dev/null)" || return 1
  # source: "policy" — the policy writer's shape; lane-answer's human writer stays byte-identical.
  if ! { jq -n --argjson a "$out" --arg sha "$sha" --arg gate "$gate" --arg at "$(now_utc)" \
      '{answers: $a, note: null, source: "policy", policy_sha: $sha, gate: $gate, via: "policy", at: $at}' > "$af.tmp.$$" \
      && mv "$af.tmp.$$" "$af"; }; then
    rm -f "$af.tmp.$$"; return 1
  fi
  run="$(jq -r '.run_id // empty' "$lj" 2>/dev/null)"
  case "$run" in ''|*/*|.*) return 0 ;; esac
  line="policy answer: $(jq -r --argjson a "$out" '[.questions[] | "\(.header // "?") → \($a[.question] // "?")"] | join(", ")' "$q" 2>/dev/null) (policy_sha ${sha:0:12})"
  bash "$HELPERS" progress-append "$root/.supervisor/automate/$run.md" "$line" >/dev/null 2>&1 || true
  return 0
}

# ==================================================================================================
# lane-answer <lane_dir> <tool_use_id> --owner-command '<cmd>' [--via <client>]  (stdin: answers JSON)
# lane-answer <lane_dir> --deliver-pending --owner-command '<cmd>'
#
# A HELD answer is never lost (parallel-automate/23 F2): when admission holds the resume (exit 4), the
# VALIDATED answers, the note and `via` — never an owner command — are kept coordinator-side in
# <primary>/.supervisor/automate/<parent_run_id>.<lane>.answer-pending.json and nothing is written
# into the lane. lane-status only SHOWS that lane as `answer_pending`. Delivery is the second form,
# run by the coordinator's `/automate --resume <run_id>` poll with the command the owner typed in
# THAT session: it re-runs the full _lanes_gate (authority, liveness, regime, admission) and re-checks
# the stored answers against the recorded question's labels AND the lane's still-deferred tool_use_id
# (a mismatch refuses and discards the pending file). Honest limit: the re-check proves the stored
# answer is a VALID label for the question still pending — not that the owner chose it. That is the
# same trust level as the lane inbox's answer file relay-hook reads; the pending file is not
# owner-authenticated, which is why it can never carry, or stand in for, an owner command. One pending
# file per lane, last write wins: a second HELD lane-answer for the same question replaces the first
# (how the owner corrects a kept answer). A discard leaves the question unanswered, so lane-status
# reads that lane awaiting_input again — never held_for_load. A resume refused for a missing gate
# opt-out (launch contract 3a) keeps the validated answer pending the same way (exit 3, not 4).
_lanes_pending_file() { printf '%s' "$LN_PRIMARY/.supervisor/automate/$LN_PARENT.$LN_LANE.answer-pending.json"; }

# _lanes_validate_answers <question_file> <input JSON> — prints {<question>: "<label[,label…]>"} or
# fails with the refusal text: exactly the question's own option labels (multiSelect: comma-joined,
# every way of cutting the answer at its commas into known labels is tried — a label may itself
# contain a comma — exactly one cut ⇒ accepted; none ⇒ unknown label, refusing the whole answer;
# more than one ⇒ ambiguous).
_lanes_validate_answers() {
  jq -c --argjson in "$2" '
    def cuts($labels): if length == 0 then [[]] else
      [range(1; length + 1) as $k | (.[0:$k] | join(",") | sub("^ +"; "") | sub(" +$"; "")) as $h
        | select(any($labels[]; . == $h)) | (.[$k:] | cuts($labels))[] | [$h] + .] end;
    .questions as $qs | ($qs | length) as $n
    | if ($in.answers | type) != "object" then error("an answer is one of the question'"'"'s own option labels per question (a note alone is never the decision)") else . end
    | if ([$in.answers | keys[]] | map(tonumber? // -1) | sort) != [range(0; $n)] then error("need exactly one answer for each of the \($n) question(s)") else . end
    | reduce range(0; $n) as $i ({}; ($in.answers[($i | tostring)]) as $a
        | [$qs[$i].options[].label] as $labels
        | (if ($a | type) != "string" then []
           elif $qs[$i].multiSelect != true then [$a]
           elif any($labels[]; . == $a) then [$a]
           else ($a | split(",") | cuts($labels)) as $c
             | if ($c | length) > 1 then error("question \($i + 1): \"\($a)\" is ambiguous — its labels contain commas and it splits into known labels \($c | length) ways (\($c | map(map("\"" + . + "\"") | join(" + ")) | join(" | "))), so no one reading can be chosen") else ($c[0] // []) end
           end) as $parts
        | if ($parts | length) == 0 or any($parts[]; . as $p | ($labels | index($p)) == null)
          then error("question \($i + 1): \"\($a)\" is not one of its options\(if $qs[$i].multiSelect == true then " (multiSelect: comma-joined labels)" else "" end)")
          else . end
        | . + {($qs[$i].question): ($parts | join(","))})' "$1" 2>&1
}

# _lanes_answer_parked <tool_use_id> — 0 when the lane's last result parked on exactly that deferred
# question (prints it), else prints the refusal reason and returns 1.
_lanes_answer_parked() {
  local last; last="$(_lanes_last_result "$LN_LOG")"
  [ "$(jq -r '.stop_reason // empty' <<<"$last" 2>/dev/null)" = "tool_deferred" ] || { echo "$LN_LANE did not park on a question"; return 1; }
  [ "$(jq -r '.deferred_tool_use.id // empty' <<<"$last" 2>/dev/null)" = "$1" ] || { echo "$LN_LANE is parked on another question"; return 1; }
  printf '%s' "$last"
}

# _lanes_answer_write_resume <id> <validated> <note> <via> <sid> — caller holds the launch lock and
# passed _lanes_gate: writes the lane's answer file, drops any pending copy, resumes the session.
_lanes_answer_write_resume() {
  local id="$1" out="$2" note="$3" via="$4" sid="$5" af="$LN_INBOX/answers/$1.json" rc
  if ! { jq -n --argjson a "$out" --arg note "$note" --arg via "$via" --arg at "$(now_utc)" \
      '{answers: $a, note: (if $note == "" then null else $note end), source: "human", via: $via, at: $at}' > "$af.tmp.$$" \
      && mv "$af.tmp.$$" "$af"; }; then
    rm -f "$af.tmp.$$"; _lanes_launch_unlock; die "lane-answer: cannot write the answer file"
  fi
  rm -f "$(_lanes_pending_file)"
  [ -n "$note" ] && echo "lane-answer: note recorded and delivered to the lane as an annotation (never the decision)"
  _lanes_spawn "" "$sid" "(resume after answer $id via $via)"; rc=$?
  _lanes_launch_unlock
  return "$rc"
}

lanes_answer() {
  local dir="" id="" owner="" via=cli deliver=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --owner-command) _lanes_need "$#" lane-answer "$1"; owner="$2"; shift 2 ;;
      --via) _lanes_need "$#" lane-answer "$1"; via="${2:-cli}"; shift 2 ;;
      --deliver-pending) deliver=1; shift ;;
      --without-gate-optout) LN_WITHOUT_OPTOUT=1; shift ;;
      *) if [ -z "$dir" ]; then dir="$1"; elif [ -z "$id" ]; then id="$1"; else die "lane-answer: unexpected argument '$1'"; fi; shift ;;
    esac
  done
  _lane_ctx "$dir" || die "lane-answer: not a lane: ${dir:-<none>}"
  if [ "$deliver" = 1 ]; then
    [ -z "$id" ] || die "lane-answer: --deliver-pending takes no tool_use_id (it delivers the stored one)"
    _lanes_deliver_pending "$owner"; return $?
  fi
  case "$id" in ''|*[!A-Za-z0-9_-]*) die "lane-answer: bad tool_use_id '$id'" ;; esac
  local qf="$LN_INBOX/questions/$id.json" af="$LN_INBOX/answers/$id.json" last in out rc pf
  [ -s "$qf" ] || die "lane-answer: refused — no recorded question $id"
  [ -e "$af" ] && die "lane-answer: refused — $id already answered"
  last="$(_lanes_answer_parked "$id")" || die "lane-answer: refused — $last"
  in="$(cat)"
  jq -e 'type == "object"' >/dev/null 2>&1 <<<"$in" || die "lane-answer: refused — answers are not a JSON object"
  out="$(_lanes_validate_answers "$qf" "$in")" || die "lane-answer: refused — $(sed -E 's/^jq: error \(at [^)]*\): //' <<<"$out")"
  local sid; sid="$(jq -r '.session_id // empty' <<<"$last")"; [ -n "$sid" ] || sid="$(_lanes_session_id)"
  [ -n "$sid" ] || die "lane-answer: refused — no session id to resume"
  local note; note="$(jq -r '.note // ""' <<<"$in")"
  # authority + admission BEFORE the answer is written into the lane, so a refused resume leaves
  # nothing half-written there; under the launch lock, so an overlapping answer sees it answered.
  _lanes_launch_lock || die "lane-answer: refused — $LN_LANE — launch lock busy (another launch of this lane is in flight)"
  if [ -e "$af" ]; then _lanes_launch_unlock; die "lane-answer: refused — $id already answered"; fi
  _lanes_gate "$owner" 1; rc=$?
  if [ "$rc" = 4 ] || { [ "$rc" = 3 ] && [ "$LN_GATE_OPTOUT_BLOCKED" = 1 ]; }; then
    # HELD (admission) or BLOCKED on a missing gate opt-out: keep the VALIDATED answer coordinator-side
    # — never the owner command — so the owner's answer is not lost while the resume waits.
    pf="$(_lanes_pending_file)"; case "$via" in *[!A-Za-z0-9_.-]*) via=cli ;; esac
    if jq -n -c --arg lane "$LN_LANE" --arg id "$id" --argjson a "$(jq -c '.answers' <<<"$in")" --arg note "$note" \
        --arg via "$via" --arg at "$(now_utc)" \
        '{schema_version: 1, lane: $lane, tool_use_id: $id, answers: $a, note: (if $note == "" then null else $note end), via: $via, held_at: $at}' \
        > "$pf.tmp.$$" 2>/dev/null && mv "$pf.tmp.$$" "$pf"; then
      if [ "$rc" = 3 ]; then
        echo "lane-answer: answer kept pending ($(basename "$pf")) — $LN_LANE reads answer_pending; deliver it with the opt-out set, or with --without-gate-optout (lane-answer <lane_dir> --deliver-pending --owner-command '<cmd>' [--without-gate-optout])"
      else
        echo "lane-answer: answer kept pending ($(basename "$pf")) — $LN_LANE reads answer_pending; the next /automate --resume poll delivers it (lane-answer <lane_dir> --deliver-pending --owner-command '<cmd>')"
      fi
    else
      rm -f "$pf.tmp.$$"; echo "lane-answer: answer NOT kept — cannot write $(basename "$pf"); re-send it at the next poll"
    fi
    _lanes_launch_unlock; return "$rc"
  fi
  [ "$rc" = 0 ] || { _lanes_launch_unlock; return "$rc"; }
  _lanes_answer_write_resume "$id" "$out" "$note" "$via" "$sid"
}

# _lanes_deliver_pending <owner_cmd> — the delivery form (see lanes_answer). Nothing is written into
# the lane before every re-check and the full _lanes_gate pass.
_lanes_deliver_pending() {
  local owner="$1" pf id qf af last in out sid note via rc
  pf="$(_lanes_pending_file)"
  [ -s "$pf" ] || die "lane-answer: refused — no pending answer for $LN_LANE ($(basename "$pf"))"
  _discard() { rm -f "$pf"; die "lane-answer: refused — the pending answer for $LN_LANE no longer matches ($1); discarded — the question is shown again"; }
  id="$(jq -r '.tool_use_id // empty' "$pf" 2>/dev/null)"
  case "$id" in ''|*[!A-Za-z0-9_-]*) _discard "bad tool_use_id" ;; esac
  [ "$(jq -r '.lane // empty' "$pf" 2>/dev/null)" = "$LN_LANE" ] || _discard "recorded for another lane"
  qf="$LN_INBOX/questions/$id.json"; af="$LN_INBOX/answers/$id.json"
  [ -s "$qf" ] || _discard "no recorded question $id"
  [ -e "$af" ] && _discard "$id already answered"
  last="$(_lanes_answer_parked "$id")" || _discard "$last"
  in="$(jq -c '{answers: .answers, note: .note}' "$pf" 2>/dev/null)" || _discard "pending file unreadable"
  out="$(_lanes_validate_answers "$qf" "$in")" || _discard "$(sed -E 's/^jq: error \(at [^)]*\): //' <<<"$out")"
  note="$(jq -r '.note // ""' <<<"$in")"; via="$(jq -r '.via // "cli"' "$pf")"; case "$via" in ''|*[!A-Za-z0-9_.-]*) via=cli ;; esac
  sid="$(jq -r '.session_id // empty' <<<"$last")"; [ -n "$sid" ] || sid="$(_lanes_session_id)"
  [ -n "$sid" ] || die "lane-answer: refused — no session id to resume"
  _lanes_launch_lock || die "lane-answer: refused — $LN_LANE — launch lock busy (another launch of this lane is in flight)"
  if [ -e "$af" ]; then _lanes_launch_unlock; _discard "$id already answered"; fi
  _lanes_gate "$owner" 1; rc=$?
  if [ "$rc" != 0 ]; then
    _lanes_launch_unlock
    echo "lane-answer: pending answer kept for $LN_LANE — not delivered"
    return "$rc"
  fi
  _lanes_answer_write_resume "$id" "$out" "$note" "$via (delivered pending)" "$sid"
}

# ==================================================================================================
# lane-remove <lane_dir> [--stop] [--abandon]
_lanes_stop_pid() { # <pid> <label> — TERM, then KILL after the grace period
  local p="$1" g="${LOOMWRIGHT_LANES_STOP_GRACE_S:-60}" i=0
  case "$g" in ''|*[!0-9]*) g=60 ;; esac
  kill -TERM "$p" 2>/dev/null
  while kill -0 "$p" 2>/dev/null && [ "$i" -lt $((g * 5)) ]; do sleep 0.2; i=$((i + 1)); done
  kill -0 "$p" 2>/dev/null && kill -KILL "$p" 2>/dev/null
  echo "lane-remove: stopped $2 (pid $p)"
}

# _lanes_live_watchers <lane_dir> — prints "<pid>\t<pr_url>" for each live merge watcher of the lane
# (its marker's pid still runs automate-merge-watch for that marker's PR — a recycled pid is not live).
_lanes_live_watchers() {
  local m mp mu
  for m in "$1"/.supervisor/automate/*.merge-watch; do
    [ -f "$m" ] || continue
    mp="$(awk -F'\t' '$1 == "pid" { print $2 }' "$m")"; mu="$(awk -F'\t' '$1 == "pr_url" { print $2 }' "$m")"
    case "$mp" in ''|*[!0-9]*) continue ;; esac
    case "$(ps -ww -o command= -p "$mp" 2>/dev/null)" in
      *automate-merge-watch*"$mu"*) printf '%s\t%s\n' "$mp" "$mu" ;;
    esac
  done
}

# _lanes_status_named <meta-sync status --paths output> — `(<first line>)`, plus ` — paths: <p>, …` when
# indented path lines follow (at most five named, then `+<k> more`). A status with no path lines (an
# older meta-sync) reads exactly as before: `(<first line>)`.
_lanes_status_named() {
  local first n
  first="$(printf '%s\n' "$1" | head -1)"
  n="$(printf '%s\n' "$1" | sed 1d | grep -c '^  [^ ]')"
  [ "$n" -gt 0 ] || { printf '(%s)' "$first"; return 0; }
  printf '(%s) — paths: %s' "$first" "$(printf '%s\n' "$1" | sed 1d | grep '^  [^ ]' | sed 's/^  //' | head -5 \
    | awk -v k="$((n - 5))" '{ printf "%s%s", (NR > 1 ? ", " : ""), $0 } END { if (k > 0) printf ", +%d more", k }')"
}

# _lanes_remove_refusals — every lane-remove refusal that does not depend on process liveness. Runs
# in lanes_remove's dynamic scope (reads/sets its locals L, abandon, state, rf, q, b, u, mb, ms).
_lanes_remove_refusals() {
  rstate="$(_lanes_state_of "$L")"   # the lane's real state, from lane-status's own reader (F10)
  # >>> awaiting-input check
  rf="$LN_DIR/.supervisor/automate/$LN_RUN.md"
  if q="$(_lanes_pending_question "$LN_INBOX")"; then _refuse "awaiting_input — unanswered question $q"; return 1; fi
  if [ -f "$rf" ] && grep -q 'pause_reason: *awaiting_input' "$rf"; then _refuse "awaiting_input — run file is parked on a question"; return 1; fi
  if [ "$(jq -r '.stop_reason // empty' <<<"$(_lanes_last_result "$LN_LOG")" 2>/dev/null)" = "tool_deferred" ]; then
    q="$(jq -r '.deferred_tool_use.id // empty' <<<"$(_lanes_last_result "$LN_LOG")")"
    [ -e "$LN_INBOX/answers/$q.json" ] || { _refuse "awaiting_input — deferred tool call $q"; return 1; }
  fi
  # <<< awaiting-input check
  state="$(_lt_get "$LN_TABLE" "$L" 8)"
  if [ "$abandon" = 0 ]; then
    if [ "$state" = gone ] || { [ -f "$rf" ] && grep -qE '(status|pause_reason): *gone' "$rf"; }; then
      _refuse "gone (PR closed unmerged) — a human runs lane-remove --abandon"; return 1
    fi
  fi
  [ -z "$(git -C "$LN_DIR" status --porcelain 2>/dev/null)" ] || { _refuse "dirty working tree"; return 1; }
  if [ "$abandon" = 1 ] && [ "$ab_ok" = 1 ] && [ "$rstate" = gone ]; then   # F11
    if ! mb="$(_lanes_meta_branch "$LN_DIR")"; then _refuse "metadata mode unknown (cannot record the abandon)"; return 1; fi
    _lanes_abandon_meta || return 1
  fi
  [ -e "$LN_DIR/.supervisor/automate/$LN_RUN.meta-push-failed" ] && { _refuse "meta-push failure marker is set"; return 1; }
  if ! mb="$(_lanes_meta_branch "$LN_DIR")"; then _refuse "metadata mode unknown (cannot prove the metadata was pushed)"; return 1; fi
  if [ -n "$mb" ]; then
    # --paths: the refusal names what is unpushed, so fleet-closeout's `waiting — <lane> …` line says
    # which file to push (wave W4: a worker-filed proposed/ draft found only by a hand list-managed diff).
    ms="$(bash "$META_SYNC" status --branch "$mb" --root "$LN_DIR" --paths 2>/dev/null)" || { _refuse "metadata status unreadable"; return 1; }
    case "$(printf '%s\n' "$ms" | head -1)" in
      local_ahead*|conflict*|*local_ahead*|*conflict*) _refuse "metadata not pushed $(_lanes_status_named "$ms")"; return 1 ;;
    esac
  fi
  # >>> unpushed-commit check (fail CLOSED: an unreadable branch list or count refuses, never reads 0)
  local heads; heads="$(git -C "$LN_DIR" for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null)" \
    || { _refuse "local branch list unreadable"; return 1; }
  for b in $heads; do
    u="$(git -C "$LN_DIR" rev-list --count "$b" --not --remotes=origin 2>/dev/null)" || u=""
    case "$u" in ''|*[!0-9]*) _refuse "branch $b: unpushed-commit count unreadable"; return 1 ;; esac   # UNPUSHED-UNREADABLE
    [ "$u" -gt 0 ] && { _refuse "branch $b has $u commit(s) not on origin"; return 1; }
  done
  # <<< unpushed-commit check
  return 0
}

# Order: without --stop a live process refuses first (naming it). With --stop, EVERY non-liveness
# refusal runs BEFORE anything is stopped, so a lane that is unremovable for another reason is refused
# with its processes untouched (never left stopped-but-refused); only then are the live processes
# TERMed (KILL after the grace), liveness is re-evaluated, and the non-liveness refusals run once more
# (the stopped process may have changed the lane in between) before salvage and removal.
lanes_remove() {
  local dir="" stop=0 abandon=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --stop) stop=1; shift ;;
      --abandon) abandon=1; shift ;;
      *) [ -z "$dir" ] || die "lane-remove: unexpected argument '$1'"; dir="$1"; shift ;;
    esac
  done
  _lane_ctx "$dir" || die "lane-remove: not a lane: ${dir:-<none>}"
  local L="$LN_LANE" pid st mp mu q state rstate="" rf b u mb ms live_pid="" watchers="" ab_ok=0
  _refuse() { echo "lane-remove: refused — $L — $1"; return 1; }
  # >>> live-process check
  pid="$(_lt_get "$LN_TABLE" "$L" 5)"; st="$(_lt_get "$LN_TABLE" "$L" 6)"
  if lanes_proc_alive "$pid" "$st" "$LN_DIR"; then
    if [ "$stop" = 1 ]; then live_pid="$pid"; else _refuse "live claude -p process (pid $pid); use --stop"; return 1; fi
  fi
  # <<< live-process check
  watchers="$(_lanes_live_watchers "$LN_DIR")"
  if [ -n "$watchers" ] && [ "$stop" = 0 ]; then
    IFS="$(printf '\t')" read -r mp mu <<<"$watchers"   # the first live watcher
    _refuse "live merge watcher (pid $mp, $mu); use --stop"; return 1
  fi
  [ -z "$live_pid$watchers" ] && ab_ok=1   # the abandon record is written only once nothing runs
  _lanes_remove_refusals || return 1   # REFUSE-BEFORE-STOP
  if [ -n "$live_pid$watchers" ]; then
    [ -n "$live_pid" ] && _lanes_stop_pid "$live_pid" "claude -p"
    while IFS="$(printf '\t')" read -r mp mu; do
      [ -n "$mp" ] && _lanes_stop_pid "$mp" "merge watcher"
    done <<<"$watchers"
    if [ -n "$live_pid" ] && lanes_proc_alive "$pid" "$st" "$LN_DIR"; then
      _refuse "lane process (pid $pid) still alive after --stop"; return 1
    fi
    watchers="$(_lanes_live_watchers "$LN_DIR")"
    if [ -n "$watchers" ]; then
      IFS="$(printf '\t')" read -r mp mu <<<"$watchers"   # the first live watcher
      _refuse "merge watcher (pid $mp, $mu) still alive after --stop"; return 1
    fi
    ab_ok=1
    _lanes_remove_refusals || return 1
  fi
  local sv; sv="$(_lanes_salvage "$LN_DIR" "$LN_ROOT/salvage" "$L-removed")" || { _refuse "salvage failed"; return 1; }
  # Single-lane parent: the lane's token TOTAL survives its directory as one parent ## Progress line
  # (the whole-run ceiling's only record of a removed lane) — plain and --abandon alike, once per lane.
  local prf="$LN_PRIMARY/.supervisor/automate/$LN_PARENT.md"
  if _lanes_single_parent "$prf"; then _lanes_tokens_record "$prf" "$L" "$LN_DIR" "$LN_RUN" >/dev/null; fi
  rm -rf "$LN_DIR" || { echo "lane-remove: could not remove $LN_DIR" >&2; return 1; }
  _lt_set "$LN_TABLE" "$L" 8 "$([ "$abandon" = 1 ] && echo abandoned || echo removed)"
  if [ "$abandon" = 1 ]; then
    # A run-file line never carries an absolute path (the branch-mode trail push scrubs home paths and
    # would fail the parent's push — F10): the salvage is named in the `<primary>-lanes/…` form.
    bash "$HELPERS" progress-append "$LN_PRIMARY/.supervisor/automate/$LN_PARENT.md" \
      "lane abandoned: $L ($LN_RUN) — state ${rstate:-unknown}; salvage kept at <primary>-lanes/$LN_PARENT/salvage/${sv##*/}" >/dev/null 2>&1 || true
  fi
  echo "lane-remove: removed $L ($LN_DIR); salvage $sv"
}

# ==================================================================================================
# ---- the lane's metadata at the wave end (F11) --------------------------------------------------
# _lanes_meta_extras <branch> <message> — pushes the lane's own NON-claim metadata, exactly listed:
# its run file, `<run_id>.merge-readiness.md` and `<run_id>.dismissed-decisions` (each when present),
# plus its Orchestrator task plans and the requirement drafts it filed (_lanes_noclaim_files). None of
# them is a done claim. Prints meta-sync's reason and returns 1 on failure.
_lanes_meta_extras() {
  local mb="$1" msg="$2" list f out rc=0
  list="$(mktemp "${TMPDIR:-/tmp}/lane-meta.XXXXXX" 2>/dev/null)" || { echo "could not stage the push list"; return 1; }
  { for f in "$LN_RUN.md" "$LN_RUN.merge-readiness.md" "$LN_RUN.dismissed-decisions"; do
      if [ -f "$LN_DIR/.supervisor/automate/$f" ]; then printf '%s\n' ".supervisor/automate/$f"; fi
    done
    _lanes_noclaim_files
  } > "$list" || { rm -f "$list"; echo "could not stage the push list"; return 1; }
  out="$(bash "$META_SYNC" push --branch "$mb" --root "$LN_DIR" --paths-from "$list" --message "$msg" 2>&1)" || rc=$?
  rm -f "$list"
  if [ "$rc" != 0 ]; then
    printf 'meta-sync exit %s\n%s' "$rc" "$out"; return 1
  fi
  return 0
}

# _lanes_noclaim_files — prints the lane's other non-claim metadata, one repo-relative path per line:
#   - its Orchestrator task plans: every regular top-level `.supervisor/requirements/<slug>-plan.md` (the
#     one path the Orchestrator's file-fallback mode writes, agents/orchestrator.md §"Persistence Mode")
#     — before this list carried them, lane-remove refused forever on `local_ahead` (operator-run
#     2026-10-10 Phase 0.2);
#   - the requirement drafts it filed: every regular top-level `.supervisor/requirements/proposed/*.md`.
#     A worker whose requirement says to file an out-of-scope follow-up as its own item writes it there
#     (`## Status: proposed`); trail-pr's candidates carry only this run's dismissed drafts from that
#     folder, so before this list carried them the draft stayed local and fleet-closeout waited forever
#     on `local_ahead 1` (wave W4, run automate-2026-10-11-182243: twin-remediation-11, hand-pushed).
# Both sit on meta-managed paths no other wave-end push carries. Excluded, left to trail-pr's evidence
# gate: a path the lane run file's `## Queue` / `## Current` names (that is the item's requirement), and
# any file carrying a `## Status: done…` heading (a done claim). A file the lane only pulled is unchanged,
# so meta-sync pushes nothing for it; a lane clone has exactly one run, so nothing here is another run's.
_lanes_noclaim_files() {
  local f p items nl tab
  nl="$(printf '\nx')"; nl="${nl%x}"; tab="$(printf '\t')"
  items="$(awk '/^## / { sec = $0; next }
    sec == "## Queue" && /^- \[[ xX]\] / { v = $0; sub(/^- \[[ xX]\] /, "", v); sub(/[[:space:]]+#.*$/, "", v); sub(/[[:space:]]+$/, "", v); sub(/^\.\//, "", v); print v }
    sec == "## Current" && /^- item:/ { v = $0; sub(/^- item: */, "", v); sub(/ *\|.*/, "", v); sub(/^\.\//, "", v); print v }' \
    "$LN_DIR/.supervisor/automate/$LN_RUN.md" 2>/dev/null)"
  for f in "$LN_DIR"/.supervisor/requirements/*-plan.md "$LN_DIR"/.supervisor/requirements/proposed/*.md; do
    [ -f "$f" ] && [ ! -L "$f" ] || continue
    p="${f#"$LN_DIR"/}"
    case "$p" in *"$nl"*|*"$tab"*) continue ;; esac   # meta-sync refuses such names; never split a line
    grep -qxF -- "$p" <<<"$items" && continue
    grep -qE '^## Status:[[:space:]]*done' "$f" 2>/dev/null && continue
    printf '%s\n' "$p"
  done
  return 0
}

# _lanes_meta_trail <branch> <lane_runfile> <reason> — the rest of the lane's metadata (requirement,
# done/failed briefs, result sidecars, the postmortem ledger, its dismissed drafts) goes through
# `trail-pr`'s OWN evidence-gated candidate list, run on the lane's run file inside the lane: a done
# stamp or a `jobs/done/` brief rides only when its PR reads MERGED (`; excluded <path> — pr not
# merged` otherwise). Branch mode only. trail-pr reads the mode through its sibling setup-memory.sh;
# when that reader does not say `on <branch>` too, nothing runs (a PR-mode trail must never start
# from here). Prints trail-pr's line; returns 1 unless it reads meta-pushed / meta no_changes.
# Pass-through, not a new seam: META_SYNC is forwarded as trail-pr's LOOMWRIGHT_META_SYNC_BIN so the
# push uses the same meta-sync this script's other calls use — in a real run that is the sibling
# meta-sync.sh (trail-pr's own default); only the LOOMWRIGHT_LANES_META_SYNC test seam changes it.
_lanes_meta_trail() {
  local mb="$1" rf="$2" reason="$3" tm out
  tm="$(bash "$(dirname "$TRAIL")/setup-memory.sh" --root "$LN_DIR" mode 2>/dev/null | head -1)"
  [ "$tm" = "on $mb" ] || { echo "trail-pr's mode reader says '${tm:-nothing}', not 'on $mb' — trail not run"; return 1; }
  out="$(LOOMWRIGHT_META_SYNC_BIN="$META_SYNC" bash "$TRAIL" trail-pr "$rf" --reason "$reason" 2>/dev/null | tail -1)"
  printf '%s' "${out:-trail-pr printed nothing}"
  case "$out" in "trail-pr: meta-pushed "*|"trail-pr: skipped — meta no_changes"*) return 0 ;; esac
  return 1
}

# _lanes_abandon_meta — lane-remove --abandon on a lane lane-status reads `gone` (its PR closed
# unmerged), in lanes_remove's scope. The owner's abandon decision is recorded the way
# `reconcile-status --apply` records an `# abandoned:` Queue row: every done heading of the lane's
# requirement becomes `## Status: done_with_escalation — ABANDONED (- [x] <item>  # abandoned:
# <reason>)` (appended when it has none), and a `jobs/done/` brief pointing at that requirement moves
# to `jobs/failed/`. (Before automate-followups/37, Phase 4.5 stamped the requirement done before any
# merge; it no longer does, but an older requirement may still carry that stamp for the unmerged PR,
# and this is what rewrites it.) Then, in branch mode,
# the lane's metadata is pushed (_lanes_meta_extras + _lanes_meta_trail --reason abandoned), so the
# lane is removable with no hand step and nothing pushed claims the unmerged work done.
_lanes_abandon_meta() {
  local arf="$LN_DIR/.supervisor/automate/$LN_RUN.md" item req row em b ptr out
  item="$(_lanes_current_item "$arf")"; item="${item#./}"
  case "$item" in .supervisor/requirements/*.md) ;; *) item="" ;; esac
  case "$item" in *..*) item="" ;; esac
  if [ -n "$item" ] && [ -f "$LN_DIR/$item" ]; then
    req="$LN_DIR/$item"; em="$(printf '\342\200\224')"
    row="- [x] $item  # abandoned: PR closed unmerged $em lane-remove --abandon"
    if ! AB_HEAD="## Status: done_with_escalation $em ABANDONED ($row)" AB_PFX="## Status: done_with_escalation $em ABANDONED (- [x] " awk '
        /^## Status:[[:space:]]*done(_with_escalation)?([^A-Za-z0-9_]|$)/ && index($0, ENVIRON["AB_PFX"]) != 1 { print ENVIRON["AB_HEAD"]; n++; next }
        index($0, ENVIRON["AB_PFX"]) == 1 { n++ }
        { print }
        END { if (!n) { print ""; print ENVIRON["AB_HEAD"] } }' "$req" > "$req.tmp.$$" || ! mv "$req.tmp.$$" "$req"; then
      rm -f "$req.tmp.$$"; _refuse "could not write the ABANDONED stamp on $item"; return 1
    fi
    if [ -r "$HERE/brief-pointer.sh" ]; then
      # shellcheck source=/dev/null
      . "$HERE/brief-pointer.sh"
      for b in "$LN_DIR"/.supervisor/jobs/done/*.md; do
        [ -f "$b" ] || continue
        ptr="$(brief_requirement_pointer "$b" 2>/dev/null)" || continue
        [ "${ptr#./}" = "$item" ] || continue
        mkdir -p "$LN_DIR/.supervisor/jobs/failed" && mv "$b" "$LN_DIR/.supervisor/jobs/failed/" \
          || { _refuse "could not move $(basename "$b") to jobs/failed/"; return 1; }
      done
    fi
  fi
  [ -n "$mb" ] || return 0
  out="$(_lanes_meta_extras "$mb" "chore(supervisor): $LN_RUN abandoned (lane-remove --abandon)")" || { _refuse "metadata push failed ($(printf '%s\n' "$out" | head -1))"; return 1; }
  out="$(_lanes_meta_trail "$mb" "$arf" abandoned)" || { _refuse "evidence-gated trail push failed: $out"; return 1; }
  echo "lane-remove: $L abandoned — $out"
}

# lane-convert-ready <lane_dir> — the wave-end `ready_for_release` → `awaiting_merge` conversion: the
# coordinator's one run-file write into a launched lane, and it PUSHES the lane's metadata, so the
# primary's next meta pull reads awaiting_merge and lane-remove's metadata check (`meta-sync status`)
# can pass. Under the lane's launch lock (no launch or resume can start mid-conversion). Refusals (exit
# 1, nothing written): a live lane process (lanes_proc_alive), no run file, a `## Current` that reads
# none of the three accepted states below, or an unknown metadata mode. Order, after the refusals:
# `ready_for_release` (both fields) ⇒ current-set converts it to `awaiting_merge` (no closeout — the PR
# is not merged yet). Already `awaiting_merge` (a re-run after a failed push, or after the owner
# merged) ⇒ NO current-set; instead `closeout <the lane's run file> <item> <## Current pr> --no-trail`
# runs inside the lane (automate-followups/38) — the ONE writer of the requirement's done stamp, behind
# its own evidence gate (PR not MERGED ⇒ it writes nothing), which also checks the item off and
# reconciles `## Current` to `done` / `awaiting_go`; its lines are echoed indented, closeout-classify
# reads them and the last line names any leftover (a leftover never changes the exit code); no
# `pr:` in `## Current` ⇒ closeout is not run. Already closed out (`done` / `awaiting_go` — a re-run
# after the merged re-run's push failed) ⇒ neither runs again; a lane finalize-empty already finalized
# (`## Status: done`, ## Current `done` / `null`) is accepted the same way. Whenever ## Current then reads
# `done`, branch mode runs `finalize-empty` inside the lane before the pushes (A1, parallel-automate/21 —
# see the comment at its call). Each then runs the pushes, so a re-run is idempotent. Branch mode (`on <Y>`) then
# pushes (1) the lane's non-claim files by exact list (_lanes_meta_extras: the run file, its
# merge-readiness report, its dismissed-decisions ledger, its task plans, the requirement drafts it filed
# under proposed/) and (2) everything else through trail-pr's
# evidence-gated candidate list (_lanes_meta_trail, `--reason wave-end`): a done stamp or a jobs/done/
# brief whose PR is not MERGED is excluded and named, so while the PR is open the lane keeps reading
# `local_ahead` and lane-remove keeps refusing — after the owner merges, the re-run's closeout writes
# the stamp and its pushes carry it; if the PR closes unmerged, `lane-remove --abandon` records it
# (F11). Mode `off` has no metadata
# branch to push. A failed push ⇒ `lane-convert-ready: FAILED — …` and exit 2 (re-run to retry). The
# last line names the state the lane reads afterwards: `converted <lane> to awaiting_merge` on the
# conversion, `<lane> reads <status> / <pause_reason> (a re-run converts nothing)` on a re-run.
_lanes_current_item() { # <runfile> — the `## Current` item path, or nothing
  awk '/^## / { sec = $0; next }
    sec == "## Current" && /^- item:/ { v = $0; sub(/^- item: */, "", v); sub(/ *\|.*/, "", v); print v; exit }' "$1" 2>/dev/null
}
# _lanes_no_host_identity [NAME=VALUE ...] <cmd> [args...] — runs <cmd> (through `exec env`, so
# leading NAME=VALUE pairs apply) with the host's two runtime-identity variables unset AND
# LOOMWRIGHT_HOLDER_PID pinned to <cmd>'s own pid (`bash -c` sets it to `$$`, then `exec env` and
# env's own exec keep that pid, so `$$` IS <cmd>). Guarantee: a fresh run-lock acquire with no
# --session-id inside <cmd> (lane-convert-ready's closeout and finalize-empty) records <cmd> itself
# as holder (`pid_source holder_env`) — never the coordinator session and never a long-lived
# ancestor such as the coordinator's own `claude` (run-lock.sh's ancestor walk is ungated) — so a
# crashed call's lock is reclaimable once <cmd> is dead. Like the merge watcher (automate-loop
# SKILL, "Why … are unset"); resolution order: docs/ARCHITECTURE_CONTRACTS.md §"Run lock".
_lanes_no_host_identity() {
  env -u CLAUDE_PID -u CLAUDECODE \
    bash -c 'LOOMWRIGHT_HOLDER_PID=$$; export LOOMWRIGHT_HOLDER_PID; exec env "$@"' _ "$@"
}
lanes_convert_ready() {
  local dir="${1:-}"
  [ "$#" -le 1 ] || die "lane-convert-ready: unexpected argument '$2'"
  _lane_ctx "$dir" || die "lane-convert-ready: not a lane: ${dir:-<none>}"
  local L="$LN_LANE" rf pid st status pause pr item mb out rc list phase co cv cs="" did fdid
  rf="$LN_DIR/.supervisor/automate/$LN_RUN.md"
  _cr_refuse() { _lanes_launch_unlock; echo "lane-convert-ready: refused — $L — $1"; return 1; }
  _lanes_launch_lock || { echo "lane-convert-ready: refused — $L — launch lock busy (a launch or resume of this lane is in flight)"; return 1; }
  pid="$(_lt_get "$LN_TABLE" "$L" 5)"; st="$(_lt_get "$LN_TABLE" "$L" 6)"
  if lanes_proc_alive "$pid" "$st" "$LN_DIR"; then _cr_refuse "live lane process (pid $pid); convert only after it exits"; return 1; fi
  [ -f "$rf" ] || { _cr_refuse "no run file $LN_RUN.md"; return 1; }
  IFS="$(printf '\t')" read -r status pause pr _ <<<"$(_lanes_runfile_fields "$rf")"
  case "$status/$pause" in
    ready_for_release/ready_for_release) phase=convert ;;
    awaiting_merge/awaiting_merge) phase=closeout; echo "lane-convert-ready: $L already reads awaiting_merge — retrying the metadata push" ;;
    done/awaiting_go) phase=closed; echo "lane-convert-ready: $L already closed out (## Current done / awaiting_go) — retrying the metadata push only" ;;
    # A1: finalize-empty rewrote `## Status: done` + pause_reason null — a re-run after a failed push.
    done/null|done/-)
      if _lanes_rf_done "$rf"; then
        phase=closed; echo "lane-convert-ready: $L already closed out and finalized (## Status: done) — retrying the metadata push only"
      else _cr_refuse "run file reads status ${status:--} / pause_reason ${pause:--}, not ready_for_release"; return 1; fi ;;
    *) _cr_refuse "run file reads status ${status:--} / pause_reason ${pause:--}, not ready_for_release"; return 1 ;;
  esac
  item="$(_lanes_current_item "$rf")"
  case "$item" in ''|null|-) _cr_refuse "run file has no ## Current item"; return 1 ;; esac
  if ! mb="$(_lanes_meta_branch "$LN_DIR")"; then _cr_refuse "metadata mode unknown (the conversion could not be pushed)"; return 1; fi
  if [ "$phase" = convert ]; then
    out="$(bash "$HELPERS" current-set "$rf" --item "$item" --status awaiting_merge --pause-reason awaiting_merge 2>&1)" \
      || { _cr_refuse "current-set failed: $(printf '%s' "$out" | tr '\n' ' ')"; return 1; }
  fi
  # The merged re-run (automate-followups/38): closeout --no-trail inside the lane, under the launch lock,
  # BEFORE the pushes, never followed by current-set (that would revert closeout's ## Current reconcile).
  # Its own evidence gate decides — an unmerged PR prints `skipped — pr not merged` and writes nothing.
  if [ "$phase" = closeout ]; then
    case "$pr" in
      ''|-|null) cs="; closeout not run (## Current has no pr)" ;;
      *)
        # A fresh run-lock acquire (no --session-id): host identity unset, holder pinned to the
        # closeout process (_lanes_no_host_identity).
        co="$(cd "$LN_DIR" && _lanes_no_host_identity bash "$TRAIL" closeout "$rf" "$item" "$pr" --no-trail 2>/dev/null)"
        printf '%s\n' "$co" | sed '/^$/d; s/^/  /'
        cv="$(printf '%s\n' "$co" | bash "$HELPERS" closeout-classify --run "$LN_RUN" --item "${item#./}" --pr "$pr" 2>/dev/null)"
        if [ "$cv" = complete ]; then cs="; closeout complete"
        elif [ -z "$cv" ]; then cs="; closeout leftover: classify — closeout-classify printed nothing"
        elif ! grep -q '^leftover	' <<<"$cv" && grep -q '^run_lock_held	' <<<"$cv"; then
          # automate-followups/36 A1: a LIVE process holds the run lock — not a leftover; nothing ran.
          cs="; closeout deferred: $(printf '%s\n' "$cv" | awk -F'\t' '$1 == "run_lock_held" { printf "%s%s", (n++ ? ", " : ""), $6 }') — re-run lane-convert-ready once it is released"
        else cs="; closeout leftover: $(printf '%s\n' "$cv" | awk -F'\t' '$1 == "leftover" { printf "%s%s — %s", (n++ ? ", " : ""), $5, $6 }')"
        fi ;;
    esac
  fi
  # What the lane now reads — a re-run converts nothing, and its closeout may have reconciled ## Current
  # to done / awaiting_go, so it names the state it read back, never "converted … to awaiting_merge".
  if [ "$phase" = convert ]; then did="converted $L to awaiting_merge"; fdid="converted to awaiting_merge"
  else
    IFS="$(printf '\t')" read -r status pause _ <<<"$(_lanes_runfile_fields "$rf")"
    fdid="reads ${status:--} / ${pause:--} (a re-run converts nothing)"; did="$L $fdid"
  fi
  # A1 (parallel-automate/21): a re-run whose ## Current reads `done` (closeout's done / awaiting_go, or an
  # already-finalized lane) runs `finalize-empty <the lane's run file>` INSIDE the lane, under the launch
  # lock and BEFORE the pushes — so the pushes carry its `## Status: done` and the Progress lines it
  # appends after its own trail push. finalize-empty decides eligibility itself (already `## Status: done`
  # ⇒ `finalize-empty: skipped — not paused`). Its `trail-pr --reason done` runs through the evidence gate
  # with this script's meta-sync (LOOMWRIGHT_META_SYNC_BIN, as _lanes_meta_trail). Branch mode only: with
  # mode off — or when finalize's own mode reader does not say `on <mb>` too — finalize is NOT run (its
  # trail-pr would open a trail PR). One `lane-convert-ready: finalize …` line, printed before the last.
  # The last line keeps naming the state closeout left (`reads done / awaiting_go`) — the finalize line
  # above it names what finalize-empty did to it.
  local fin="" fe fm
  if [ "$phase" != convert ] && [ "$status" = done ]; then
    if [ -z "$mb" ]; then fin="lane-convert-ready: finalize skipped — metadata mode off"
    else
      fm="$(bash "$(dirname "$HELPERS")/setup-memory.sh" --root "$LN_DIR" mode 2>/dev/null | head -1)"
      if [ "$fm" != "on $mb" ]; then
        fin="lane-convert-ready: finalize skipped — finalize-empty's mode reader says '${fm:-nothing}', not 'on $mb'"
      else
        # finalize-empty's run-lock acquire takes no --session-id either: same unset + holder pin as closeout above.
        fe="$(cd "$LN_DIR" && _lanes_no_host_identity LOOMWRIGHT_META_SYNC_BIN="$META_SYNC" \
          bash "$HELPERS" finalize-empty "$rf" 2>/dev/null)"
        fe="$(printf '%s\n' "$fe" | sed '/^$/d' | awk '{ printf "%s%s", (NR > 1 ? "; " : ""), $0 }')"
        fin="lane-convert-ready: finalize — ${fe:-finalize-empty printed nothing}"
      fi
    fi
  fi
  if [ -z "$mb" ]; then
    _lanes_launch_unlock
    if [ -n "$fin" ]; then echo "$fin"; fi
    echo "lane-convert-ready: $did (metadata mode off — no metadata branch to push)$cs"
    return 0
  fi
  if [ -n "$fin" ]; then echo "$fin"; fi
  rc=0; out="$(_lanes_meta_extras "$mb" "chore(supervisor): $LN_RUN ready_for_release -> awaiting_merge (wave end)")" || rc=$?
  if [ "$rc" != 0 ]; then
    _lanes_launch_unlock
    echo "lane-convert-ready: FAILED — $L — $fdid, but the metadata push to $mb failed ($(printf '%s\n' "$out" | head -1)); NOT pushed (lane-remove refuses until it is) — re-run lane-convert-ready $LN_DIR$cs"
    printf '%s\n' "$out" | sed '1d; /^$/d; s/^/  /'
    return 2
  fi
  rc=0; out="$(_lanes_meta_trail "$mb" "$rf" wave-end)" || rc=$?
  _lanes_launch_unlock
  if [ "$rc" != 0 ]; then
    echo "lane-convert-ready: FAILED — $L — $fdid and its non-claim files pushed, but the evidence-gated trail push failed: $out — re-run lane-convert-ready $LN_DIR$cs"
    return 2
  fi
  echo "lane-convert-ready: $did; metadata pushed to $mb — $out$cs"
}

# _lanes_click_action <notify-desktop.sh path> <checkout root> — the click action notify-desktop.sh
# resolves for this call, derived its own way: LOOMWRIGHT_NOTIFY_CLICK (default activate), `off` or no
# readable notify-click-target.sh beside the notifier ⇒ `none`, else that resolver's ACTION= line, fed
# the same session-id / entrypoint env inputs (the park payload carries no session id, so the env wins).
# The notifier's dir is resolved from <root>, the cwd it runs in; an unresolvable dir reads `none`.
_lanes_click_action() {
  local nd="$1" root="$2" mode="${LOOMWRIGHT_NOTIFY_CLICK:-activate}" dir out act=""
  dir="$(cd "$root" 2>/dev/null && cd "$(dirname "$nd")" 2>/dev/null && pwd)" || dir=""
  if [ "$mode" != off ] && [ -n "$dir" ] && [ -r "$dir/notify-click-target.sh" ]; then
    out="$(bash "$dir/notify-click-target.sh" "$mode" "${CLAUDE_CODE_SESSION_ID:-}" "${CLAUDE_CODE_ENTRYPOINT:-}" 2>/dev/null)" || true
    act="$(printf '%s\n' "$out" | sed -n 's/^ACTION=//p' | head -1)" || act=""
  fi
  echo "${act:-none}"
}

# _lanes_os_notifier <notify-desktop.sh path> <checkout root> — prints NOTHING when the platform
# notifier notify-desktop.sh dispatches to is present, else the `failed (…)` reason. Mirrors that
# script's own dispatch conditions: Darwin uses terminal-notifier ONLY with a click action other than
# `none` (else it falls through to osascript), Linux needs notify-send plus a display; any other OS has
# no notifier there either. LOOMWRIGHT_LANES_UNAME is the existing uname seam of this file.
_lanes_os_notifier() {
  local nd="${1:-}" root="${2:-.}"
  case "${LOOMWRIGHT_LANES_UNAME:-$(uname -s 2>/dev/null)}" in
    Darwin)
      if command -v terminal-notifier >/dev/null 2>&1 && [ "$(_lanes_click_action "$nd" "$root")" != none ]; then :
      elif command -v osascript >/dev/null 2>&1; then :
      else echo "no OS notifier on PATH"; fi ;;
    Linux)
      if ! command -v notify-send >/dev/null 2>&1; then echo "no OS notifier on PATH"
      elif [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then echo "no display for notify-send"; fi ;;
    *) echo "no OS notifier on PATH" ;;
  esac
}

# ==================================================================================================
# lane-park-notify <runfile> — the ONE notify step of a lane's ready_for_release park (§14 "Terminal
# park"; parallel-automate/24 F6). Sends the desktop notification and the `automate_ready_for_release`
# webhook ("do not merge yet — wave open"), both fail-SAFE, then appends ONE `## Progress` line naming
# what each channel actually did. Both notifiers are silent on stdout, so delivery is read from their
# observable outcomes only — never assumed:
#   desktop  `sent` (notify-desktop.sh wrote its `notify group=` audit line to <root>/.supervisor/logs/
#            notifications.log AND the platform notifier it dispatches to is present — Darwin:
#            osascript, or terminal-notifier with a click action other than `none` (LOOMWRIGHT_NOTIFY_CLICK
#            not `off` and notify-click-target.sh beside it), on PATH; Linux: notify-send on PATH plus DISPLAY or
#            WAYLAND_DISPLAY — the OS banner itself is best-effort and not observable) · `disabled
#            (LOOMWRIGHT_DESKTOP_NOTIFICATIONS=0)` · `suppressed (no audit line …)` (debounce, or the
#            notifier skipped it) · `failed (<why>)` — incl. `failed (no OS notifier on PATH)` and
#            `failed (no display for notify-send)`, because notify-desktop.sh writes its audit line on
#            EVERY host BEFORE its platform dispatch, so the audit line alone cannot prove a banner
#   webhook  a LOOMWRIGHT_WEBHOOK_DRY_RUN=1 probe of send-webhook.sh first says whether a webhook URL
#            resolves (it prints the payload only then): none ⇒ `ignored (repo_webhook_ignored slug=…
#            — no user-scope egress grant)` or `not configured`; one ⇒ the real call, then `attempted
#            (POST sent; delivery not reported by send-webhook.sh)` — it never reports the HTTP result,
#            so never `sent` — or `failed (<its stderr line>)`; `dry-run …` when the caller already set
#            LOOMWRIGHT_WEBHOOK_DRY_RUN
# Not at the ready_for_release park ⇒ `lane-park-notify: skipped — …`, nothing sent, nothing written.
# Always exits 0 except a usage error. Seams: LOOMWRIGHT_LANES_NOTIFY_DESKTOP, LOOMWRIGHT_LANES_SEND_WEBHOOK.
lanes_park_notify() {
  local rf="${1:-}" nd="${LOOMWRIGHT_LANES_NOTIFY_DESKTOP:-$HERE/notify-desktop.sh}"
  local sw="${LOOMWRIGHT_LANES_SEND_WEBHOOK:-$HERE/send-webhook.sh}"
  local root run status pause pr item msg payload nlog before after desk web probe perr err line osn
  [ -n "$rf" ] && [ "$#" -le 1 ] || die "usage: lane-park-notify <runfile>"
  [ -f "$rf" ] || die "lane-park-notify: run file not found: $rf"
  root="$(cd "$(dirname "$rf")/../.." 2>/dev/null && pwd -P)" || die "lane-park-notify: cannot resolve the checkout of $rf"
  run="$(basename "$rf" .md)"
  IFS="$(printf '\t')" read -r status pause pr _ <<<"$(_lanes_runfile_fields "$rf")"
  if [ "$status/$pause" != "ready_for_release/ready_for_release" ]; then
    echo "lane-park-notify: skipped — $run — run file reads status ${status:--} / pause_reason ${pause:--}, not the ready_for_release park; nothing sent"
    return 0
  fi
  item="$(_lanes_current_item "$rf")"
  case "$pr" in ''|-|null) pr="(no PR recorded)" ;; esac
  msg="$pr READY — do not merge yet — wave open (/automate item ${item:--}, run $run)"
  # desktop — the merge watcher's notify_as payload shape, judged by the notifier's own audit line.
  nlog="$root/.supervisor/logs/notifications.log"
  if [ "${LOOMWRIGHT_DESKTOP_NOTIFICATIONS:-1}" = 0 ]; then desk="disabled (LOOMWRIGHT_DESKTOP_NOTIFICATIONS=0)"
  elif [ ! -f "$nd" ]; then desk="failed (notify-desktop.sh absent)"
  elif ! payload="$(jq -cn --arg t automate_ready_for_release --arg m "$msg" \
      '{hook_event_name:"Notification",notification_type:$t,message:$m}' 2>/dev/null)" || [ -z "$payload" ]; then
    desk="failed (payload not built — jq)"
  else
    before="$(grep -c ' notify group=' "$nlog" 2>/dev/null)"; before="${before:-0}"
    printf '%s' "$payload" | (cd "$root" && bash "$nd" >/dev/null 2>&1) || true
    after="$(grep -c ' notify group=' "$nlog" 2>/dev/null)"; after="${after:-0}"
    osn="$(_lanes_os_notifier "$nd" "$root")"
    if [ "$after" -gt "$before" ] 2>/dev/null; then
      if [ -z "$osn" ]; then desk="sent"; else desk="failed ($osn)"; fi
    else desk="suppressed (no audit line in .supervisor/logs/notifications.log — debounced or skipped by notify-desktop.sh)"; fi
  fi
  # webhook — probe first (dry run prints the payload only when a URL resolves), then the real call.
  if [ ! -f "$sw" ]; then web="failed (send-webhook.sh absent)"
  else
    perr="$root/.supervisor/logs/.lane-park-notify.$$.err"; mkdir -p "$root/.supervisor/logs" 2>/dev/null
    probe="$(cd "$root" && LOOMWRIGHT_WEBHOOK_DRY_RUN=1 bash "$sw" --event-type gate --gate-type automate_ready_for_release \
      --context "$msg" 2>"$perr" </dev/null)" || true
    err="$(grep -m1 -E '^(repo_webhook_ignored|send-webhook:)' "$perr" 2>/dev/null)"
    case "$probe" in
      "{"*)
        if [ -n "${LOOMWRIGHT_WEBHOOK_DRY_RUN:-}" ]; then web="dry-run (LOOMWRIGHT_WEBHOOK_DRY_RUN set — nothing posted)"
        else
          (cd "$root" && bash "$sw" --event-type gate --gate-type automate_ready_for_release --context "$msg" \
            >/dev/null 2>"$perr" </dev/null) || true
          err="$(grep -m1 '^send-webhook:' "$perr" 2>/dev/null)"
          if [ -n "$err" ]; then web="failed ($err)"; else web="attempted (POST sent; delivery not reported by send-webhook.sh)"; fi
        fi ;;
      *)
        case "$err" in
          repo_webhook_ignored*) web="ignored ($err — no user-scope egress grant)" ;;
          send-webhook:*) web="failed ($err)" ;;
          *) web="not configured" ;;
        esac ;;
    esac
    rm -f "$perr" 2>/dev/null
  fi
  line="lane park notify: ready_for_release ($run) — desktop: $desk; webhook: $web"
  bash "$HELPERS" progress-append "$rf" "$(now_utc) $line" >/dev/null 2>&1 \
    || echo "lane-park-notify: WARNING — the ## Progress line could not be appended to $rf" >&2
  echo "lane-park-notify: $line"
  return 0
}

# ==================================================================================================
# lane-info [--root <dir>]
lanes_info() {
  local root=""
  [ "${1:-}" = "--root" ] && { root="${2:-}"; [ -n "$root" ] || die "lane-info: --root needs a directory"; }
  [ -n "$root" ] || root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  local j="$root/.supervisor/lane.json"
  if [ -s "$j" ] && jq -e '.schema_version == 1 and (.run_id | type == "string")' "$j" >/dev/null 2>&1; then cat "$j"; return 0; fi
  echo "lane-info: not a lane (no valid .supervisor/lane.json under $root)" >&2
  return 1
}

# init-check --parallel N [--auto-merge]
lanes_init_check() {
  local n="" am=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --parallel) [ "$#" -ge 2 ] || { echo "refuse: parallel_out_of_range"; return 1; }; n="$2"; shift 2 ;;
      --auto-merge) am=1; shift ;;
      *) echo "refuse: unknown_argument $1"; return 1 ;;
    esac
  done
  case "$n" in ''|*[!0-9]*) echo "refuse: parallel_out_of_range"; return 1 ;; esac
  n=$((10#$n))
  if [ "$n" -lt 1 ] || [ "$n" -gt 10 ]; then echo "refuse: parallel_out_of_range"; return 1; fi
  # `--auto-merge` is refused with ANY lane (N = 1 included): a lane never runs the §10 merge gate.
  if [ "$am" = 1 ]; then echo "refuse: auto_merge_with_parallel"; return 1; fi
  # N = 1 (single-lane mode) only: branch mode must be ON — with it off a single lane's close-out would
  # open its own trail PR the parent never sees and fleet-closeout could never finalize the lane. Fail
  # CLOSED: anything but a first line `on <branch>` (off, unknown, empty, a failing reader) refuses.
  # N > 1 never reads the mode here.
  if [ "$n" = 1 ]; then
    local root m
    root="$(git rev-parse --show-toplevel 2>/dev/null)" || root=""
    m="$(bash "$SETUP_MEMORY" --root "${root:-$PWD}" mode 2>/dev/null </dev/null | head -1)"
    case "$m" in "on "?*) ;; *) echo "refuse: single_lane_requires_branch_mode"; return 1 ;; esac
  fi
  echo ok
}

# pick-guard <automate_dir> — a lane is live when its process is (lanes_proc_alive) or it holds an
# unanswered question (a deferred session is a lane mid-flight). The run lock alone is reclaimable.
lanes_pick_guard() {
  local d="${1:-}" t lane path run pid st
  [ -n "$d" ] && [ -d "$d" ] || { echo "refuse: automate_dir_missing ${d:-<none>}"; return 1; }
  for t in "$d"/*.lanes; do
    [ -f "$t" ] || continue
    while IFS="$(printf '\t')" read -r lane path _ run pid st _; do
      case "$lane" in L[0-9]*) ;; *) continue ;; esac
      if lanes_proc_alive "$pid" "$st" "$path" || { [ -d "$path/.supervisor/inbox" ] && _lanes_pending_question "$path/.supervisor/inbox" >/dev/null; }; then
        echo "refuse: live_lane $run $lane"; return 1
      fi
    done < "$t"
  done
  echo ok
}

# branch-check <lane_dir> <branch> — prints the branch name to use; a remote hit ⇒ `<branch>-L<n>`;
# both taken ⇒ `refuse: remote_branch_exists <branch>` (exit 1). Never a force push.
lanes_branch_check() {
  local dir="${1:-}" b="${2:-}" hit
  _lane_ctx "$dir" || die "branch-check: not a lane: ${dir:-<none>}"
  [ -n "$b" ] || die "branch-check: usage: branch-check <lane_dir> <branch>"
  hit="$(git -C "$LN_DIR" ls-remote --heads origin "$b" 2>/dev/null)" || { echo "refuse: remote_unreachable $b"; return 1; }
  [ -z "$hit" ] && { echo "$b"; return 0; }
  hit="$(git -C "$LN_DIR" ls-remote --heads origin "$b-$LN_LANE" 2>/dev/null)" || { echo "refuse: remote_unreachable $b"; return 1; }
  [ -z "$hit" ] && { echo "$b-$LN_LANE"; return 0; }
  echo "refuse: remote_branch_exists $b"; return 1
}

# ==================================================================================================
# OBSERVATION — lane-status, lane-feed, lane-readiness, lane-status --leaks. Every reader fails SAFE:
# an absent or unreadable source prints `unknown` and the command exits 0. Nothing here starts, stops
# or kills a lane; the only process it may start is the opt-in `--keep-awake` holder.
LANES_GH="${LOOMWRIGHT_GH_BIN:-gh}"

_lanes_dash() { case "${1:-}" in -|null) ;; *) printf '%s' "${1:-}" ;; esac; }

_lanes_epoch() { # <UTC ISO 8601> — epoch seconds; returns 1 when unparseable
  local e; e="$(jq -n --arg t "${1:-}" '$t | fromdateiso8601' 2>/dev/null)"
  case "$e" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$e"
}

_lanes_boot_epoch() { # machine boot time (epoch); returns 1 when unknown
  local b="${LOOMWRIGHT_LANES_BOOT_EPOCH:-}"
  if [ -z "$b" ]; then
    case "$(uname -s 2>/dev/null)" in
      Darwin) b="$(sysctl -n kern.boottime 2>/dev/null | sed -n 's/^{ *sec = \([0-9][0-9]*\).*/\1/p' | head -1)" ;;
      *) b="$(awk '$1 == "btime" { print $2 }' /proc/stat 2>/dev/null | head -1)" ;;
    esac
  fi
  case "$b" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$b"
}

# _lanes_runfile_fields <runfile> — status<TAB>pause_reason<TAB>pr<TAB>last_progress<TAB>pending_decisions
# (`-` for each value that is absent; the whole line is `-`s when the run file is absent).
_lanes_runfile_fields() {
  [ -f "${1:-}" ] || { printf -- '-\t-\t-\t-\t-'; return 0; }
  awk '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function d(s) { return (s == "" ? "-" : s) }
    /^## / { sec = $0; next }
    sec == "## Current" && /^- item:/ {
      n = split($0, a, / \| /)
      for (i = 1; i <= n; i++) { kv = a[i]; sub(/^- /, "", kv); k = kv; sub(/:.*/, "", k); v = kv; sub(/^[^:]*: */, "", v)
        if (k == "status") st = trim(v); else if (k == "pr") pr = trim(v) } }
    sec == "## Current" && /^- pause_reason:/ { v = $0; sub(/^- pause_reason: */, "", v); sub(/ \|.*/, "", v); pa = trim(v) }
    sec == "## Current" && /pending_decisions:/ { v = $0; sub(/.*pending_decisions: */, "", v); sub(/[ |].*/, "", v); pd = v }
    sec == "## Progress" && /^- / { lp = substr($0, 3); gsub(/\t/, " ", lp) }
    END { printf "%s\t%s\t%s\t%s\t%s", d(st), d(pa), d(pr), d(lp), d(pd) }' "$1" 2>/dev/null | tr -d '\r'
}

# _lanes_runfile_branch <runfile> — the `branch:` field of `## Current`'s `- item:` line, or nothing. Kept out
# of _lanes_runfile_fields: its callers read five tab fields, and a sixth would join the fifth.
_lanes_runfile_branch() {
  [ -f "${1:-}" ] || return 0
  awk '/^## / { sec = $0; next }
    sec == "## Current" && /^- item:/ {
      n = split($0, a, / \| /)
      for (i = 1; i <= n; i++) { kv = a[i]; k = kv; sub(/:.*/, "", k)
        if (k == "branch") { v = kv; sub(/^[^:]*: */, "", v); sub(/[ \t]+$/, "", v); b = v } } }
    END { if (b != "" && b != "-" && b != "null") printf "%s", b }' "$1" 2>/dev/null | tr -d '\r'
}

# _lanes_parked <status> <pause_reason> — prints the park reason; returns 1 when the run is not parked.
_lanes_parked() {
  case "${2:-}" in -|null|'') ;; *) printf '%s' "$2"; return 0 ;; esac
  case "${1:-}" in awaiting_merge|ready_for_release|escalated|failed|rate_limit|drain_died|done|gone) printf '%s' "$1"; return 0 ;; esac
  return 1
}

# _lanes_last_message <stream_log> — the most recent assistant TEXT (never a tool-use line), ≤300 chars.
_lanes_last_message() {
  grep '^{' "$1" 2>/dev/null | jq -r -R 'fromjson? | select(.type == "assistant")
    | [.message.content[]? | select(.type == "text") | .text] | join(" ")
    | gsub("[\\r\\n\\t]+"; " ") | gsub("^ +| +$"; "") | select(length > 0) | .[0:300]' 2>/dev/null | tail -1
}

# _lanes_last_actions <stream_log> — the last 3 tool calls, one per line.
_lanes_last_actions() {
  grep '^{' "$1" 2>/dev/null | jq -r -R 'fromjson? | select(.type == "assistant") | .message.content[]?
    | select(.type == "tool_use")
    | (.name + " " + ((.input.command // .input.description // .input.file_path // .input.pattern // "") | tostring
        | gsub("[\\r\\n\\t]+"; " ") | .[0:80])) | gsub(" +$"; "")' 2>/dev/null | tail -3
}

# _lanes_questions_json <inbox> <now_epoch> — JSON array of unanswered questions (asked_at, waiting_s).
_lanes_questions_json() {
  local q id at e w out="[]" nx
  for q in "$1"/questions/*.json; do
    [ -f "$q" ] || continue
    id="$(basename "$q" .json)"
    [ -e "$1/answers/$id.json" ] && continue
    at="$(jq -r '.asked_at // empty' "$q" 2>/dev/null)"
    w=null; if e="$(_lanes_epoch "$at")"; then w=$(( $2 - e )); fi
    # `items`: every question of the call, in order — its index is lane-answer's answer key — with its
    # option labels, so a client can offer exactly the labels lane-answer accepts without reading the
    # lane's question file itself (parallel-automate/14). `question` stays the first one's text.
    nx="$(jq -c --slurpfile Q "$q" --arg id "$id" --arg at "$at" --argjson w "$w" \
      'def arr: if type == "array" then . else [] end;
       . + [{id: $id, asked_at: (if $at == "" then null else $at end), waiting_s: $w,
             question: (($Q[0].questions // [])[0].question // null),
             items: (($Q[0].questions // []) | arr | map(select(type == "object") | {
               question: (.question // null), header: (.header // null), multiSelect: (.multiSelect == true),
               options: ((.options // []) | arr | map(select(type == "object" and .label != null)
                 | {label: (.label | tostring), description: (.description // null)}))}))}]' <<<"$out" 2>/dev/null)" \
      || nx="$(jq -c --arg id "$id" '. + [{id: $id, asked_at: null, waiting_s: null, question: null, items: []}]' <<<"$out")"
    out="$nx"
  done
  printf '%s' "$out"
}

# _lanes_policy_digest <inbox> — B7: the lane's policy answers (answer files with `source: "policy"`) as
# {answered, first_at, last_at, last_gate, last_label}, or `null` when it has none / none are readable.
_lanes_policy_digest() {
  set -- "$1"/answers/*.json
  [ -f "$1" ] || { printf 'null'; return 0; }
  jq -c -s '[.[] | select(type == "object" and .source == "policy")] | sort_by(.at // "")
    | if length == 0 then null
      else {answered: length, first_at: (.[0].at // null), last_at: (.[-1].at // null),
            last_gate: (.[-1].gate // null), last_label: ([(.[-1].answers // {})[] | tostring] | join(", "))} end' \
    "$@" 2>/dev/null || printf 'null'
}

# _lanes_inbox <table> — B7 `lane-status --inbox`: every lane's pending HUMAN questions (a question file
# with no answer file — a policy answer writes one, so it never shows) in ONE list, oldest asked_at
# first: `<asked_at> <lane> <tool_use_id> <header> — <question>` + an `options:` line per question.
_lanes_inbox() {
  local tab lane path q id rows=""
  tab="$(printf '\t')"
  while IFS="$tab" read -r lane path _; do
    case "$lane" in L[0-9]|L[0-9][0-9]) ;; *) continue ;; esac
    for q in "$path"/.supervisor/inbox/questions/*.json; do
      [ -f "$q" ] || continue
      id="$(basename "$q" .json)"
      [ -e "$path/.supervisor/inbox/answers/$id.json" ] && continue
      rows="$rows$(jq -c --arg l "$lane" --arg id "$id" '{at: ((.asked_at // "unknown") | tostring), lane: $l, id: $id,
          qs: (if (.questions | type) == "array" then .questions else [] end)}' "$q" 2>/dev/null \
        || jq -n -c --arg l "$lane" --arg id "$id" '{at: "unknown", lane: $l, id: $id, qs: []}')
"
    done
  done < "$1"
  printf '%s' "$rows" | jq -r -s 'sort_by(.at, .lane, .id)
    | "lane-status: inbox — \(length) pending human question call(s), oldest first",
      (.[] | . as $r
        | if ($r.qs | length) == 0 then "\($r.at) \($r.lane) \($r.id) - — (question unreadable)"
          else ($r.qs[] | "\($r.at) \($r.lane) \($r.id) \(.header // "-") — \(.question // "")",
            "    options: \([.options[]?.label // empty] | join(" | "))") end)' 2>/dev/null \
    || echo "lane-status: inbox — unknown (questions unreadable)"
  return 0
}

# _lanes_keep_awake_holders — JSON array of what keeps this machine from idle-sleeping right now, one
# {pid, process, assertion, name, kind} per holder. macOS: every idle-sleep-preventing power assertion
# `pmset -g assertions` lists (powerd's own display-on hold excluded), so the Claude desktop app's
# "Keep computer awake while Claude works" hold counts — it is a power assertion, not a `caffeinate`
# process, and a process-name check alone read it as "not held". kind: `caffeinate` (a holder that lasts
# as long as the process it waits on), `claude-app` (the desktop app: held only while a Code session
# works — headless lanes are not Code sessions, so it can drop mid-wave), `other`. A `caffeinate` that
# pgrep sees but pmset did not list (no pmset, other OSes) is added. Fail-SAFE: unreadable ⇒ `[]`.
_lanes_keep_awake_holders() {
  local pm="${LOOMWRIGHT_LANES_PMSET:-pmset}" rows="" cp
  if command -v "$pm" >/dev/null 2>&1 || [ -x "$pm" ]; then
    rows="$("$pm" -g assertions 2>/dev/null | sed -n 's/^[[:space:]]*pid \([0-9][0-9]*\)(\(.*\)): \[[^]]*\] *[0-9:]* *\([A-Za-z]*\) named: "\(.*\)".*$/\1	\2	\3	\4/p' \
      | awk -F'	' '$2 != "powerd" && $3 ~ /^(PreventUserIdleSystemSleep|NoIdleSleepAssertion|PreventSystemSleep|PreventUserIdleDisplaySleep|NoDisplaySleepAssertion)$/')"
  fi
  if ! awk -F'	' '$2 == "caffeinate" { f = 1 } END { exit !f }' <<<"$rows" \
    && cp="$("${LOOMWRIGHT_LANES_PGREP:-pgrep}" -x caffeinate 2>/dev/null | head -1)" && [ -n "$cp" ]; then
    rows="$(printf '%s%s%s\tcaffeinate\tPreventUserIdleSystemSleep\tcaffeinate' "$rows" "${rows:+$'\n'}" "$cp")"
  fi
  printf '%s' "$rows" | jq -R -s -c '[split("\n")[] | select(. != "") | split("\t")
    | {pid: (.[0] | tonumber? // null), process: .[1], assertion: .[2], name: (.[3] // ""),
       kind: (if .[1] == "caffeinate" then "caffeinate" elif (.[1] | test("^Claude( Helper)?$")) then "claude-app" else "other" end)}]' 2>/dev/null \
    || printf '[]'
}

# _lanes_keep_awake_state [<holders JSON>] — `held` when a caffeinate or the Claude app holds the machine
# awake now, else `not held`. `other` holders (macOS daemons such as sharingd / useractivityd take
# seconds-long assertions all day) are listed but never make it `held`.
_lanes_keep_awake_state() {
  local h="${1:-}"; [ -n "$h" ] || h="$(_lanes_keep_awake_holders)"
  if jq -e 'any(.[]; .kind != "other")' >/dev/null 2>&1 <<<"$h"; then printf 'held'; else printf 'not held'; fi
}

# _lanes_keep_awake_lasting [<holders JSON>] — exit 0 when a `caffeinate` holder exists: the one kind of
# hold that lasts the wave. The desktop app's hold alone does not (it follows Code-session activity).
_lanes_keep_awake_lasting() {
  local h="${1:-}"; [ -n "$h" ] || h="$(_lanes_keep_awake_holders)"
  jq -e 'any(.[]; .kind == "caffeinate")' >/dev/null 2>&1 <<<"$h"
}

# _lanes_coordinator_pid — LOOMWRIGHT_LANES_COORDINATOR_PID, else the nearest `claude` ancestor, else $PPID.
_lanes_coordinator_pid() {
  local p="${LOOMWRIGHT_LANES_COORDINATOR_PID:-}" i=0 c
  case "$p" in ''|*[!0-9]*) ;; *) printf '%s' "$p"; return 0 ;; esac
  p="$PPID"
  while [ "$i" -lt 12 ]; do
    case "$p" in ''|*[!0-9]*|0|1) break ;; esac
    c="$(ps -o comm= -p "$p" 2>/dev/null)"
    case "${c##*/}" in claude) printf '%s' "$p"; return 0 ;; esac
    p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"; i=$((i + 1))
  done
  printf '%s' "$PPID"
}

# _lanes_keep_awake_hint — the macOS suggestion (the owner runs it); nothing on other OSes.
_lanes_keep_awake_hint() {
  case "${LOOMWRIGHT_LANES_UNAME:-$(uname -s 2>/dev/null)}" in
    Darwin) printf 'caffeinate -i -w %s' "$(_lanes_coordinator_pid)" ;;
  esac
}

# _lanes_keep_awake_start — `--keep-awake` opt-in ONLY: starts the holder tied to the coordinator pid.
_lanes_keep_awake_start() {
  local cf="${LOOMWRIGHT_LANES_CAFFEINATE:-caffeinate}" cp hp
  case "${LOOMWRIGHT_LANES_UNAME:-$(uname -s 2>/dev/null)}" in
    Darwin) ;;
    *) echo "keep-awake: not started — no keep-awake holder known on this OS"; return 0 ;;
  esac
  # Only a lasting holder suppresses the start: the desktop app's while-working hold can drop mid-wave.
  _lanes_keep_awake_lasting && { echo "keep-awake: already held (caffeinate)"; return 0; }
  cp="$(_lanes_coordinator_pid)"
  nohup "$cf" -i -w "$cp" >/dev/null 2>&1 &
  hp=$!
  echo "keep-awake: started (opt-in --keep-awake) — $cf -i -w $cp (pid $hp); it ends with the coordinator"
}

# _lanes_machine_json — {state, load1, cpus, mem_pressure, keep_awake, keep_awake_lasting,
# keep_awake_holders}; `unknown` when the reader is absent or unreadable (never an error).
_lanes_machine_json() {
  local cmd="${LOOMWRIGHT_MACHINE_LOAD_CMD:-$HERE/machine-load.sh}" j="" ka h kl=false
  h="$(_lanes_keep_awake_holders)"; ka="$(_lanes_keep_awake_state "$h")"; _lanes_keep_awake_lasting "$h" && kl=true
  [ -f "$cmd" ] && j="$(bash "$cmd" --json 2>/dev/null | jq -c 'select(type == "object")' 2>/dev/null | head -1)"
  [ -n "$j" ] || j='{}'
  jq -c --arg ka "$ka" --argjson h "$h" --argjson kl "$kl" '{state: ((.state // "unknown") | tostring), load1: (.load1 // "unknown"),
    cpus: (.cpus // "unknown"), mem_pressure: (.mem_pressure // "unknown"), keep_awake: $ka,
    keep_awake_lasting: $kl, keep_awake_holders: $h}' <<<"$j" 2>/dev/null \
    || printf '{"state":"unknown","load1":"unknown","cpus":"unknown","mem_pressure":"unknown","keep_awake":"%s","keep_awake_lasting":%s,"keep_awake_holders":[]}' "$ka" "$kl"
}

_lanes_ci_json() { # `ci-slot.sh status --json`, or nothing
  local c="${LOOMWRIGHT_LANES_CI_SLOT:-$HERE/ci-slot.sh}"
  [ -f "$c" ] || return 0
  bash "$c" status --json 2>/dev/null | jq -c 'select(type == "object")' 2>/dev/null | head -1
}

# _lanes_table_for [<parent_runfile>|<table>] — the D6 lane table; returns 1 when none.
_lanes_table_for() {
  local rf="${1:-}" top t
  if [ -n "$rf" ]; then
    case "$rf" in *.lanes) t="$rf" ;; *) t="${rf%.md}.lanes" ;; esac
    [ -f "$t" ] && { printf '%s' "$t"; return 0; }
    return 1
  fi
  top="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  t="$(ls -t "$top"/.supervisor/automate/*.lanes 2>/dev/null | head -1)"
  [ -n "$t" ] && [ -f "$t" ] && { printf '%s' "$t"; return 0; }
  return 1
}

# _lanes_state_of <lane> — that lane's `state` exactly as lane-status reports it (_lanes_lane_json over
# its lane-table row, LN_TABLE); `unknown` when the row or the reader is unreadable.
_lanes_state_of() {
  local tab lane path item run pid st sid ts llu why s
  tab="$(printf '\t')"
  IFS="$tab" read -r lane path item run pid st sid ts llu why <<<"$(awk -F'\t' -v l="$1" '$1 == l' "$LN_TABLE" 2>/dev/null | tail -1)"
  [ -n "$lane" ] || { printf 'unknown'; return 0; }
  s="$(_lanes_lane_json "$lane" "$path" "$item" "$run" "$pid" "$st" "$sid" "$ts" "$llu" "${why:--}" "$(date -u +%s)" "" \
    "$LN_PRIMARY/.supervisor/automate/$LN_PARENT.$lane.answer-pending.json" 2>/dev/null | jq -r '.state // empty' 2>/dev/null)"
  printf '%s' "${s:-unknown}"
}

# _lanes_parent_of <parent_runfile> — sets LP_PARENT / LP_PRIMARY from a parent run file at
# <primary>/.supervisor/automate/<run_id>.md (no lane table needed); returns 1 with LP_WHY otherwise.
_lanes_parent_of() {
  local rf="${1:-}" d
  LP_PARENT=""; LP_PRIMARY=""; LP_WHY=""
  [ -n "$rf" ] || { LP_WHY="no lane table found and no <parent_runfile> given"; return 1; }
  case "$rf" in *.md) ;; *) LP_WHY="no lane table for $rf (pass the parent run file)"; return 1 ;; esac
  [ -f "$rf" ] || { LP_WHY="parent run file not found: $rf"; return 1; }
  d="$(cd "$(dirname "$rf")" 2>/dev/null && pwd -P)" || { LP_WHY="parent run file directory unreadable: $rf"; return 1; }
  [ "$(basename "$d")" = automate ] && [ "$(basename "$(dirname "$d")")" = .supervisor ] \
    || { LP_WHY="parent run file must live in <primary>/.supervisor/automate/: $rf"; return 1; }
  LP_PARENT="$(basename "$rf" .md)"
  case "$LP_PARENT" in ''|.*|*-L[0-9]|*-L[0-9][0-9]) LP_WHY="not a parent run file: $rf"; return 1 ;; esac
  LP_PRIMARY="$(cd "$d/../.." && pwd -P)" || { LP_WHY="primary unreadable for $rf"; return 1; }
  return 0
}

# _lanes_resolve <lane_dir|L<n>> — a lane directory (L<n> through the newest lane table).
_lanes_resolve() {
  case "${1:-}" in
    L[0-9]|L[0-9][0-9])
      local t; t="$(_lanes_table_for "")" || return 1
      awk -F'\t' -v l="$1" '$1 == l { p = $2 } END { if (p != "") print p }' "$t" ;;
    *) printf '%s' "${1:-}" ;;
  esac
}

# _lanes_timeline <runfile> <lane_path> <now_epoch> <state> <last_launch_utc> — the lane's step timeline:
# {started_at, current, label, steps: [{id, name, state, started_at, ended_at, duration_s, lines}],
#  phase, phase_status, phases: [{phase, at}]} — the last three the lane's Supervisor's (null / []). The seven steps are the per-item loop as
# a lane records it: pick · plan (Launch Pad) · build (Supervisor up to the PR) · heal (Phase 4.5) ·
# drain (the owned /review-pr --until-mergeable) · decide (dismissed findings) · merge (park → merge →
# close-out). Evidence: the run file's timestamped `## Progress` lines, plus the lane's Supervisor
# `.supervisor/state.md` (`## Session` phase/status, `## Decisions Log` phase timestamps) only when that
# state was created at or after the pick — a previous item's Supervisor state never shows. A step is
# reached at its first evidence; the current step is the furthest one reached, its state taken from the
# lane state (`active`, `waiting` on the owner, `held`, `trouble`; every step `done` once merged/done).
# A step passed without a line of its own reads `done` with null times: the run never said when it ran.
# Boundaries: the `picked` line ends Pick and starts Plan; a Launch Pad "brief saved" line ends Plan and starts Build (/autonomous hands the brief to
# the Supervisor at once); a `ran /autonomous` line carrying the heal verdict reaches Heal too.
# Fail-SAFE: anything unreadable ⇒ `null`.
_lanes_timeline() {
  local rf="$1" sm="$2/.supervisor/state.md" now="$3" state="$4" llu="$5" out
  # Validated, never trusted by exit code: under `pipefail` an absent state.md fails the pipeline even
  # when jq printed a good object, and an `|| printf null` there would emit two JSON texts.
  out="$({
    [ -f "$rf" ] && awk '/^## / { sec = $0; next }
      sec == "## Progress" && /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z / {
        x = substr($0, 24); gsub(/\t/, " ", x); printf "P\t%s\t%s\n", substr($0, 3, 20), x }' "$rf" 2>/dev/null
    [ -f "$sm" ] && awk 'function val(s) { sub(/^- [a-z_]*: */, "", s); gsub(/\t/, " ", s); return s }
      /^## / { sec = $0; next }
      sec == "## Session" && /^- (phase|status):/ { k = $2; sub(/:$/, "", k); printf "S\t%s\t%s\n", k, val($0) }
      sec == "## Checkpoint" && /^- (created|last_updated):/ { k = $2; sub(/:$/, "", k); printf "S\t%s\t%s\n", k, val($0) }
      sec == "## Decisions Log" && /^- phase: / && /timestamp: / {
        ph = $0; sub(/^- phase: */, "", ph); sub(/[, ].*/, "", ph)
        ts = $0; sub(/.*timestamp: */, "", ts); sub(/[ ,].*/, "", ts)
        d = $0; sub(/^.*decision: */, "", d); sub(/, (rationale|timestamp):.*/, "", d); gsub(/\t/, " ", d)
        printf "D\t%s\t%s\t%s\n", ph, ts, d }' "$sm" 2>/dev/null
    true
  } | jq -R -s -c --arg state "$state" --arg llu "$(_lanes_dash "$llu")" --argjson now "$now" '
    def ep: (try fromdateiso8601 catch null);
    def clip(n): if length > n then .[0:n - 1] + "…" else . end;
    def ids: ["pick", "plan", "build", "heal", "drain", "decide", "merge"];
    def names: ["Pick", "Plan", "Build", "Heal", "Drain", "Decide", "Merge"];
    def ord: . as $id | ids | index($id);
    def cls:
      if test("^(closeout |auto-finalized|trail-pr|parked |lane park notify|converted |merged)") then ["merge"]
      elif test("^(dismissed|owner decisions)") then ["decide"]
      elif test("owned drain started|^drain |re-drain") then ["drain"]
      elif test("^/autonomous done") then ["heal"]
      elif test("^ran /autonomous") then (if test("heal (PASS|FAIL|ESCALATED)") then ["build", "heal"] else ["build"] end)
      elif test("^supervisor:"; "i") then ["build"]
      elif test("launch[ -]?pad"; "i") then (if test("brief saved"; "i") then ["plan", "build"] else ["plan"] end)
      elif test("^picked ") then ["pick", "plan"]
      elif test("^(run started|run created|run-lock acquired|meta-entry|skipped AUT-QUEUE|trail-gate|trail-unstage)") then ["pick"]
      else [] end;
    def sstep: if . == "SELF_HEAL" or . == "LOOP" then "heal" else "build" end;
    [split("\n")[] | select(. != "") | split("\t")] as $rows
    | ([$rows[] | select(.[0] == "S") | {key: .[1], value: (.[2] // "")}] | from_entries) as $s
    | [$rows[] | select(.[0] == "P") | {ts: .[1], e: (.[1] | ep), text: (.[2] // "")} | select(.e != null)] as $p
    | ([$p[] | select(.text | test("^picked "))] | last) as $pick
    | (($s.created // "") | ep) as $se
    | ($se != null and ($pick == null or $se >= $pick.e)) as $sup
    | ($se == null and ($s.status // "") == "running" and $state == "running" and ($s.phase // "") != "") as $live
    | ([$p[] | . as $x | ($x.text | cls)[] | {step: ., ts: $x.ts, e: $x.e, text: $x.text}]
       + (if $sup then
            [{step: "build", ts: $s.created, e: $se, text: "Supervisor started"}]
            + [$rows[] | select(.[0] == "D") | {step: (.[1] | sstep), ts: .[2], e: (.[2] | ep),
                 text: ("Supervisor " + .[1] + ": " + (.[3] // ""))} | select(.e != null)]
            + (if ($s.phase // "") | sstep == "heal" then
                 [{step: "heal", ts: ($s.last_updated // $s.created), e: ((($s.last_updated // "") | ep) // $se),
                   text: ("Supervisor " + $s.phase + " (" + ($s.status // "?") + ")")}] else [] end)
          else [] end)) as $ev
    | ([($ev[] | .step), (if $live then ($s.phase | sstep) else empty end) | ord] | max // 0) as $far
    | (if ($state | test("^(merged|done)$")) then 7 else $far end) as $cur
    | (if $state == "running" then "active"
       elif ($state | test("^(awaiting_input|answer_pending|ready_for_release|awaiting_merge)$")) then "waiting"
       elif ($state | test("^(held_for_load|created)$")) then "held"
       elif ($state | test("^(stalled|died|lost_to_reset|missing|blocked_launch|gone|escalated|failed|rate_limit|drain_died|removed|abandoned)$")) then "trouble"
       else "active" end) as $cs
    | [range(0; 7) as $i
        | ([$ev[] | select(.step == ids[$i])] | sort_by(.e)) as $mine
        | {i: $i, first: ($mine | first), last: ($mine | last), lines: [$mine[] | .text | clip(140)][-4:],
           state: (if $i < $cur then "done" elif $i == $cur then $cs else "pending" end)}] as $st
    | [$st[] | . as $x
        | ([$st[($x.i + 1):][] | select(.first != null and .i <= $cur) | .first.e] | min) as $next
        | (if $x.state == "pending" or ($x.i == $cur) then null else ($next // $x.last.e) end) as $end
        | ($x.first.e // null) as $b
        | {id: ids[$x.i], name: names[$x.i], state: $x.state, started_at: ($x.first.ts // null),
           ended_at: (if $end == null then null else ($end | todateiso8601) end),
           duration_s: (if $b == null then null elif $end != null then ($end - $b)
                        elif $x.i == $cur then ([$now - $b, 0] | max) else null end),
           lines: $x.lines}] as $steps
    | ([$steps[] | select(.state != "done" and .state != "pending")] | first) as $c
    | ([$ev[] | select(.step == "drain") | .text | capture("drain round (?<n>[0-9]+)") | .n] | last) as $round
    | {started_at: (($p | first | .ts) // (if $llu == "" then null else $llu end)),
       current: ($c.id // null),
       label: (if $c == null then (if $cur >= 7 then "Done" else null end)
               elif $c.id == "build" and ($sup or $live) and ($s.phase // "") != "" then "Build · " + $s.phase
               elif $c.id == "drain" and $round != null then "Drain · round " + $round
               else $c.name end),
       steps: $steps,
       phase: (if $sup or $live then ($s.phase // null) else null end),
       phase_status: (if $sup or $live then ($s.status // null) else null end),
       phases: (if $sup then [$rows[] | select(.[0] == "D") | {phase: .[1], at: .[2]}] | group_by(.phase) | map(min_by(.at)) | sort_by(.at)
                else [] end)}' 2>/dev/null)"
  if jq -e 'type == "object"' >/dev/null 2>&1 <<<"$out"; then printf '%s' "$out"; else printf 'null'; fi
}

# _lanes_lane_json <10 lane-table columns> <now_epoch> <ci_json> [<answer-pending file>] — one lane's
# status object. Classification order (first match wins): removed/abandoned · answer_pending (a HELD
# answer kept coordinator-side for a question the lane still holds, the process not running — shown,
# never delivered here) · blocked_launch · held_for_load (a lane holding an unanswered question,
# no process running, reads awaiting_input instead) · created · missing · running
# (lanes_proc_alive) · awaiting_input · parked (merged / gone after reconcile) · lost_to_reset (boot
# later than the last launch) · died (.died marker) · stalled.
_lanes_lane_json() {
  local lane="$1" path="$2" item="$3" run="$4" pid="$5" st="$6" sid="$7" ts="$8" llu="$9" why="${10}" now="${11}" ci="${12}" apf="${13:-}"
  local root log died rf status pause pr lp pd state reason="" held="" qs nq pk prs="" le be rdf rds="" rdsum="" lm la cij
  root="$(dirname "$path")"; log="$root/$lane.stream.log"; died="$root/$lane.died"
  rf="$path/.supervisor/automate/$run.md"
  IFS="$(printf '\t')" read -r status pause pr lp pd <<<"$(_lanes_runfile_fields "$rf")"
  qs="$(_lanes_questions_json "$path/.supervisor/inbox" "$now")"; nq="$(jq 'length' <<<"$qs" 2>/dev/null)"; nq="${nq:-0}"
  cij='{"state":"unknown","position":null,"held":null}'
  if [ -n "$ci" ]; then
    cij="$(jq -c --arg d "$path" 'def m: ((.checkout // "") as $c | ($c == $d or ($c | startswith($d + "/"))));
      if ((.holders // []) | any(m)) then {state: "holding", position: null, held: null}
      else ([(.waiters // []) | to_entries[] | select(.value | m)] | first) as $w
        | if $w == null then {state: "none", position: null, held: null}
          else {state: "waiting", position: ($w.key + 1), held: $w.value.held} end end' <<<"$ci" 2>/dev/null)" \
      || cij='{"state":"unknown","position":null,"held":null}'
  fi
  local pend=""
  if [ -n "$apf" ] && [ -s "$apf" ] && [ "$nq" -gt 0 ]; then
    pend="$(jq -r '.tool_use_id // empty' "$apf" 2>/dev/null)"
    [ -n "$pend" ] && jq -e --arg id "$pend" 'any(.[]; .id == $id)' >/dev/null 2>&1 <<<"$qs" || pend=""
  fi
  case "$ts" in removed|abandoned) pend="" ;; esac
  [ -n "$pend" ] && lanes_proc_alive "$pid" "$st" "$path" && pend=""
  if [ -n "$pend" ]; then
    state=answer_pending
    reason="answer to $pend held $(jq -r '.held_at // "?"' "$apf" 2>/dev/null) (last launch state: $ts$(w="$(_lanes_dash "$why")"; [ -n "$w" ] && printf ' — %s' "$w")); the next /automate --resume poll delivers it: lane-answer $path --deliver-pending --owner-command '<cmd>'"
  else
  case "$ts" in
    removed|abandoned) state="$ts" ;;
    blocked_launch) state=blocked_launch; reason="$(_lanes_dash "$why")" ;;
    held_for_load)
      # The column records the last launch attempt; a HELD resume (or a discarded pending answer)
      # leaves the lane's question unanswered, and that question — not the hold — is what the
      # owner must see: a held_for_load label would hide it and invite a fresh-launch retry.
      if [ "$nq" -gt 0 ] && [ -d "$path" ] && ! lanes_proc_alive "$pid" "$st" "$path"; then
        state=awaiting_input; reason="question $(jq -r '.[0].id' <<<"$qs") (last launch held for load: $(_lanes_dash "$why"))"
      else
        state=held_for_load; reason="held for load: $(_lanes_dash "$why")"
      fi
      held="$(_lanes_dash "$why")" ;;
    created) state=created; reason="not launched" ;;
    *)
      if [ ! -d "$path" ]; then state=missing; reason="lane directory vanished"
      elif lanes_proc_alive "$pid" "$st" "$path"; then
        state=running
        held="$(jq -r '.held // empty' <<<"$cij" 2>/dev/null)"
        if [ "$(jq -r .state <<<"$cij")" = waiting ]; then reason="waiting for a CI slot — position $(jq -r .position <<<"$cij")"; fi
        [ -n "$held" ] && reason="${reason:+$reason; }held for load: $held"
      elif [ "$nq" -gt 0 ]; then state=awaiting_input; reason="question $(jq -r '.[0].id' <<<"$qs")"
      elif pk="$(_lanes_parked "$status" "$pause")"; then
        state="$pk"
        if [ -n "$(_lanes_dash "$pr")" ]; then
          case "$pk" in
            awaiting_merge|ready_for_release)
              prs="$(bash "$HELPERS" reconcile-item "$pr" "$pk" 2>/dev/null | head -1)"
              case "$prs" in merged) state=merged ;; gone) state=gone; reason="PR closed unmerged" ;; awaiting_merge) ;; *) prs="" ;; esac ;;
          esac
        fi
      elif be="$(_lanes_boot_epoch)" && le="$(_lanes_epoch "$(_lanes_dash "$llu")")" && [ "$be" -gt "$le" ]; then
        state=lost_to_reset; reason="machine booted after the last launch ($llu); resume with lane-launch --resume-run $run"
      elif [ -e "$died" ]; then
        state=died; reason="process exited with no terminal result ($(awk -F'\t' '$1 == "died_at" { print $2 }' "$died" 2>/dev/null))"
      else
        state=stalled; reason="process gone, run file not parked, no pending question — resume once with lane-launch --continue"
      fi ;;
  esac
  fi
  rdf="$path/.supervisor/automate/$run.merge-readiness.md"
  if [ -f "$rdf" ]; then
    rds="$(sed -n 's/^- score: \([0-9]*\/[0-9]*\).*/\1/p' "$rdf" | head -1)"
    rdsum="$(sed -n 's/^- score: .* | summary: //p' "$rdf" | head -1)"
  fi
  lm="$(_lanes_last_message "$log")"; la="$(_lanes_last_actions "$log")"
  local pdg tl; pdg="$(_lanes_policy_digest "$path/.supervisor/inbox")"
  jq -e 'type == "object" or . == null' >/dev/null 2>&1 <<<"$pdg" || pdg=null
  tl="$(_lanes_timeline "$rf" "$path" "$now" "$state" "$llu")"
  jq -e 'type == "object" or . == null' >/dev/null 2>&1 <<<"$tl" || tl=null
  jq -n -c --arg lane "$lane" --arg path "$path" --arg item "$(_lanes_dash "$item")" --arg run "$run" --argjson pdg "$pdg" --argjson tl "$tl" \
    --arg state "$state" --arg reason "$reason" --arg pid "$(_lanes_dash "$pid")" --arg sid "$(_lanes_dash "$sid")" \
    --arg llu "$(_lanes_dash "$llu")" --arg status "$(_lanes_dash "$status")" --arg pause "$(_lanes_dash "$pause")" \
    --arg pr "$(_lanes_dash "$pr")" --arg prs "$prs" --arg lp "$(_lanes_dash "$lp")" --arg lm "$lm" --arg la "$la" \
    --argjson qs "$qs" --argjson ci "$cij" --arg held "$held" --arg rdf "$rdf" --arg rds "$rds" --arg rdsum "$rdsum" \
    --arg br "$(_lanes_runfile_branch "$rf")" \
    'def n: if . == "" then null else . end;
     {lane: $lane, path: $path, item: $item, run_id: $run, state: $state, reason: $reason, pid: ($pid | n),
      session_id: ($sid | n), last_launch_utc: ($llu | n), run_status: ($status | n), pause_reason: ($pause | n),
      pr: ($pr | n), pr_state: ($prs | n), branch: ($br | n), last_progress: $lp, last_actions: ($la | split("\n") | map(select(. != ""))),
      last_message: $lm, questions: $qs, ci_slot: $ci, held_for_load: ($held | n),
      readiness: (if $rds == "" then null else {score: $rds, summary: $rdsum, file: $rdf} end), policy: $pdg,
      started_at: ($tl.started_at // ($llu | n)), timeline: $tl}'
}

# _lanes_status_doc <table> <parent> <primary> — the full lane-status JSON document.
_lanes_status_doc() {
  local table="$1" parent="$2" primary="$3" now ci m hint lanes="" row tab
  tab="$(printf '\t')"; now="$(date -u +%s)"; ci="$(_lanes_ci_json)"; m="$(_lanes_machine_json)"; hint="$(_lanes_keep_awake_hint)"
  local lane path item run pid st sid ts llu why
  while IFS="$tab" read -r lane path item run pid st sid ts llu why; do
    case "$lane" in L[0-9]|L[0-9][0-9]) ;; *) continue ;; esac
    row="$(_lanes_lane_json "$lane" "$path" "$item" "$run" "$pid" "$st" "$sid" "$ts" "$llu" "${why:--}" "$now" "$ci" \
      "$primary/.supervisor/automate/$parent.$lane.answer-pending.json")" || continue
    lanes="$lanes$row
"
  done < "$table"
  local rs; rs="$(awk '/^## / { sec = $0; next } sec == "## Progress" && /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9:]*Z / { print substr($0, 3, 20); exit }' \
    "$primary/.supervisor/automate/$parent.md" 2>/dev/null)"
  # waves: every wave PR this run opened, oldest first, read from wave-build's `## Progress` record
  # (`<ts> wave built: <branch> — PR <url> (…)`; a hand-built wave writes the same line, its timestamp
  # sometimes left out). No gh call: lane-status is polled, so the PR's own state is not read here.
  local wv; wv="$(awk '/^## / { sec = $0; next } sec == "## Progress" && /^- .*wave built/' "$primary/.supervisor/automate/$parent.md" 2>/dev/null \
    | jq -R -s -c '[split("\n")[]
        | capture("^- (?:(?<built_at>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z) )?wave built.*?: (?<branch>[^ ]+) — PR (?<pr>https://[^ ]+)")
        | .pr |= sub("[),.;]+$"; "")
        | . + {wave: ((.branch | capture("w(?<k>[0-9]+)$").k | tonumber)? // null)}]' 2>/dev/null)"
  [ -n "$wv" ] || wv='[]'
  # utc_offset_s: the machine's local offset, so a client in a sandbox with no time zone can show local
  # clock times ("started 18:22"); `date +%z` is POSIX on BSD and GNU alike.
  local tz; tz="$(date +%z 2>/dev/null)"
  case "$tz" in [+-][0-9][0-9][0-9][0-9]) tz="$(( (10#${tz:1:2} * 3600 + 10#${tz:3:2} * 60) * (${tz:0:1}1) ))" ;; *) tz=null ;; esac
  printf '%s' "$lanes" | jq -s -c --arg parent "$parent" --arg primary "$primary" --arg at "$(now_utc)" --argjson m "$m" --arg rs "$rs" --argjson tz "$tz" --argjson wv "$wv" \
    --arg hint "$hint" --arg mp "$([ -e "$primary/.supervisor/automate/$parent.memory-pressure" ] && echo true || echo false)" \
    '{schema_version: 1, parent_run_id: $parent, primary: $primary, generated_at: $at,
      run_started_at: (if $rs != "" then $rs else ([.[].started_at | select(. != null)] | min) end), utc_offset_s: $tz, waves: $wv, machine: $m,
      memory_pressure: ($mp == "true"), keep_awake_suggestion: (if $hint == "" then null else $hint end), lanes: .}'
}

_lanes_render() { # <status JSON> — the plain view
  jq -r '"lane-status: \(.parent_run_id) — \(.lanes | length) lane(s) — \(.generated_at)\(if .run_started_at != null then " — started \(.run_started_at)" else "" end)",
    ((.waves // [])[] | "wave\(if .wave != null then " " + (.wave | tostring) else "" end) PR: \(.pr)  branch=\(.branch)\(if .built_at != null then "  built " + .built_at else "" end)"),
    (if all(.lanes[]; .policy == null) then "policy: none answered" else empty end),
    (.lanes[] | "\(.lane)  \(.state)\(if .reason != "" then " (" + .reason + ")" else "" end)  item=\(.item)  pr=\(.pr // "-")  path=\(.path)",
      (if .policy != null then "    policy: \(.policy.answered) answered by policy\(if .policy.answered > 1 and .policy.first_at != null then " since " + .policy.first_at else "" end) — last \(.policy.last_gate // "?") → \(.policy.last_label) \(.policy.last_at // "unknown")" else empty end),
      (if .timeline != null then "    steps: \([.timeline as $t | .timeline.steps[] | if .state == "done" then .name + " ✓" elif .state == "pending" then .name
          else "[\($t.label // .name)\(if .duration_s != null then " " + ((.duration_s / 60 | floor | tostring) + "m") else "" end) \(.state)]" end] | join(" · "))\(if .started_at != null then "  (started \(.started_at))" else "" end)" else empty end),
      (if .last_progress != "" then "    progress: \(.last_progress)" else empty end),
      (if (.last_actions | length) > 0 then "    actions: \(.last_actions | join("; "))" else empty end),
      (.questions[] | "    question: \(.id) asked_at=\(.asked_at // "unknown") waiting_s=\(.waiting_s // "unknown") — \(.question // "")"),
      (if .ci_slot.state == "waiting" then "    ci-slot: waiting — position \(.ci_slot.position)"
       elif .ci_slot.state == "holding" then "    ci-slot: holding a slot" else empty end),
      (if .held_for_load != null then "    held for load: \(.held_for_load)" else empty end),
      (if .readiness != null then "    readiness: \(.readiness.summary)" else empty end),
      (if .last_message != "" then "    last: \(.last_message)" else empty end)),
    "machine: state=\(.machine.state) load1=\(.machine.load1) cpus=\(.machine.cpus) mem_pressure=\(.machine.mem_pressure)\(if .memory_pressure then " — memory_pressure: new launches held" else "" end)",
    "keep-awake: \(.machine.keep_awake)\([(.machine.keep_awake_holders // [])[] | select(.kind != "other")
      | if .kind == "caffeinate" then "caffeinate pid \(.pid)" else "Claude app — only while a Code session works" end] | unique
      | if length > 0 then " (" + join("; ") + ")" else "" end)",
    (if .keep_awake_suggestion != null and (if .machine | has("keep_awake_lasting") then .machine.keep_awake_lasting else .machine.keep_awake == "held" end) != true
     then "keep-awake suggestion (run it yourself, or lane-status --keep-awake): \(.keep_awake_suggestion) — a closed lid still sleeps" else empty end)' <<<"$1"
}

# _lanes_resources <primary> <parent> — the latest fleet.log line per lane plus the wave's peak.
_lanes_resources() {
  local f="$1/.supervisor/automate/$2.fleet.log" last
  [ -s "$f" ] || { echo "resources: unknown — no fleet.log ($f)"; return 0; }
  last="$(tail -1 "$f")"
  printf '%s\n' "$last" | awk '{
      printf "resources: latest %s\n", $1; m = ""
      for (i = 2; i <= NF; i++) { k = $i; sub(/=.*/, "", k)
        if (k ~ /(^|[_.])L[0-9]+([_.]|$)/) { match(k, /L[0-9]+/); l = substr(k, RSTART, RLENGTH)
          if (!(l in seen)) { seen[l] = 1; order[++n] = l }; lines[l] = lines[l] " " $i }
        else m = m " " $i }
      printf "machine:%s\n", (m == "" ? " unknown" : m)
      for (j = 1; j <= n; j++) printf "%s:%s\n", order[j], lines[order[j]] }'
  awk '{ for (i = 2; i <= NF; i++) { k = $i; v = $i; sub(/=.*/, "", k); sub(/^[^=]*=/, "", v)
          if (v ~ /^[0-9]+(\.[0-9]+)?/ && (!(k in pk) || v + 0 > pk[k] + 0)) { if (!(k in pk)) ord[++n] = k; pk[k] = v } } }
       END { printf "peak:"; for (j = 1; j <= n; j++) printf " %s=%s", ord[j], pk[ord[j]]; print "" }' "$f"
}

# _lanes_tokens <table> <primary> <parent> — per-lane and parent token totals (read-token-ledger.sh).
# The per-lane and parent lines are one call each; the total is ONE call over every root (D8:
# `--run-id <parent> --root <primary> --root <lane1> …`), so the reader adds the roots itself and
# says LEDGER_UNREADABLE=1 only when NO root yields a readable ledger — never because one root (a
# parent that ran no session of its own) had nothing.
_lanes_tokens() {
  local rtl="${LOOMWRIGHT_LANES_TOKEN_LEDGER:-$HERE/read-token-ledger.sh}" tab lane path run out po to
  [ -f "$rtl" ] || { echo "tokens: unknown — read-token-ledger.sh absent"; return 0; }
  local -a roots=(--root "$2")
  tab="$(printf '\t')"
  while IFS="$tab" read -r lane path _ run _; do
    case "$lane" in L[0-9]|L[0-9][0-9]) ;; *) continue ;; esac
    if [ -d "$path" ]; then
      out="$(bash "$rtl" --run-id "$run" --root "$path" 2>/dev/null | head -1)"; roots+=(--root "$path")
    else out=""; fi
    echo "$lane ${out:-unknown}"
  done < "$1"
  po="$(bash "$rtl" --run-id "$3" --root "$2" 2>/dev/null | head -1)"
  echo "parent ${po:-unknown}"
  to="$(bash "$rtl" --run-id "$3" "${roots[@]}" 2>/dev/null | head -1)"   # TOTAL-CALL
  echo "total (parent + lanes): ${to:-unknown}"
}

# ---- single-lane mode (twin-remediation/08b) ----------------------------------------------------------
# _lanes_single_parent <parent_runfile> — 0 when its `## Run Config` carries `- parallel: 1` (the
# coordinator-routing marker of single-lane mode); 1 otherwise (N > 1, no line, unreadable).
_lanes_single_parent() {
  awk '/^## / { c = ($0 ~ /^## Run Config[[:space:]]*$/); next }
       c && /^- parallel:[[:space:]]*1[[:space:]]*$/ { f = 1 } END { exit !f }' "${1:-/dev/null}" 2>/dev/null
}

# _lanes_lane_total <lane run_id> <lane path> — the lane's read-token-ledger.sh TOTAL (the same
# `--run-id <run> --root <path>` call _lanes_tokens makes per lane), or `unknown` when the reader is
# absent, prints no TOTAL, or says LEDGER_UNREADABLE=1.
_lanes_lane_total() {
  local rtl="${LOOMWRIGHT_LANES_TOKEN_LEDGER:-$HERE/read-token-ledger.sh}" out t
  [ -f "$rtl" ] && [ -d "${2:-}" ] || { echo unknown; return 0; }
  out="$(bash "$rtl" --run-id "$1" --root "$2" 2>/dev/null </dev/null | head -1)"
  case " $out " in *" LEDGER_UNREADABLE=1 "*) echo unknown; return 0 ;; esac
  t="$(printf '%s\n' "$out" | tr ' ' '\n' | sed -n 's/^TOTAL=\([0-9][0-9]*\)$/\1/p' | head -1)"
  echo "${t:-unknown}"
}

# _lanes_single_spent <lane table> <parent_runfile> — SPENT of a single-lane run: the sum over every table
# lane of its ledger TOTAL (directory present) or of its parent `## Progress` line `fleet closeout: <lane>
# tokens TOTAL=<n>` (directory gone — the line fleet-closeout / lane-remove write before deleting it; the
# LAST such line counts). Prints the sum; returns 1 (fail CLOSED ⇒ `token_ceiling ledger_unreadable`) when
# any lane's TOTAL is unknown — a live lane whose reader cannot answer, or a gone lane with no line (or
# `TOTAL=unknown`). No table yet ⇒ 0. Honest limit: like every ledger read it never counts the
# coordinator's own main-thread tokens or CI spend.
_lanes_single_spent() {
  local table="$1" rf="$2" tab lane path run v sum=0
  [ -f "$table" ] || { echo 0; return 0; }
  tab="$(printf '\t')"
  while IFS="$tab" read -r lane path _ run _; do
    case "$lane" in L[0-9]|L[0-9][0-9]) ;; *) continue ;; esac
    if [ -d "$path" ]; then v="$(_lanes_lane_total "$run" "$path")"
    else
      v="$(L="$lane" awk 'BEGIN { p = "- fleet closeout: " ENVIRON["L"] " tokens TOTAL=" }
             /^## / { inp = ($0 ~ /^## Progress/); next }
             inp && index($0, p) == 1 { v = substr($0, length(p) + 1) } END { print v }' "$rf" 2>/dev/null)"
    fi
    case "$v" in ''|*[!0-9]*) return 1 ;; esac
    sum=$((sum + 10#$v))
  done < "$table"
  echo "$sum"
}

# _lanes_tokens_record <parent_runfile> <lane> <lane path> <lane run_id> — single-lane parents only:
# append `fleet closeout: <lane> tokens TOTAL=<n|unknown>` to the parent `## Progress` unless that lane
# already has one. Called BEFORE the lane directory is deleted (fleet-closeout step 5, lane-remove), so
# the whole-run ceiling can still count a removed lane. Prints the line it wrote (nothing when skipped).
_lanes_tokens_record() {
  local rf="$1" lane="$2" t
  grep -q "^- fleet closeout: $lane tokens TOTAL=" "$rf" 2>/dev/null && return 0
  t="$(_lanes_lane_total "$4" "$3")"
  bash "$HELPERS" progress-append "$rf" "fleet closeout: $lane tokens TOTAL=$t" >/dev/null 2>&1 \
    || { echo "automate-lanes: WARNING — the tokens line for $lane could not be appended" >&2; return 1; }
  echo "$lane TOTAL=$t"
}

# lane-park [--root <dir>] — READ-ONLY: the READY park a run in <root> writes. Exactly one line, exit 0:
# `awaiting_merge` when <root>/.supervisor/lane.json is absent (not a lane — the sequential park) or
# carries `"single_lane": true`; `ready_for_release` when lane.json is present without it, or is
# unreadable / not a JSON object (fail toward the park that arms no watcher and waits for the
# coordinator). <root> defaults to the current checkout's top level (lane-info's default).
lanes_park() {
  local root=""
  if [ "${1:-}" = "--root" ]; then root="${2:-}"; [ -n "$root" ] || die "lane-park: --root needs a directory"; fi
  [ -n "$root" ] || root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  local j="$root/.supervisor/lane.json"
  if [ ! -e "$j" ]; then echo awaiting_merge; return 0; fi
  if jq -e 'type == "object" and .single_lane == true' "$j" >/dev/null 2>&1; then echo awaiting_merge
  else echo ready_for_release; fi
  return 0
}

# _lanes_pr_hash <pr_url> — the review-dispatch marker name. The SAME derivation as dispatch-pr-review.sh's
# PR_HASH (shasum → sha1sum → cksum → sanitized URL; drain-rounds.sh mirrors it too), pinned against the
# dispatcher's own block by test-automate-lanes.sh, so the marker it names is the dispatcher's.
_lanes_pr_hash() {
  local u="$1" h=""
  if command -v shasum >/dev/null 2>&1; then h="$(printf '%s' "$u" | shasum 2>/dev/null | cut -d' ' -f1 || true)"
  elif command -v sha1sum >/dev/null 2>&1; then h="$(printf '%s' "$u" | sha1sum 2>/dev/null | cut -d' ' -f1 || true)"
  elif command -v cksum >/dev/null 2>&1; then h="$(printf '%s' "$u" | cksum 2>/dev/null | cut -d' ' -f1 || true)"; fi
  [ -n "$h" ] || h="$(printf '%s' "$u" | tr -c 'A-Za-z0-9' '-')"
  printf '%s' "$h"
}

# lane-drain-check <lane_dir> — READ-ONLY drain guard (single-ownership, CLAUDE.md "/automate
# single-drain ownership"), run by the coordinator at the lane's park. One line, exit 0:
#   `drain-guard: violation — <reason>[; <reason>…]` when (a) <lane>/.supervisor/review-dispatch/ holds the
#     marker named by _lanes_pr_hash of the lane `## Current` `pr:` URL (a detached default dispatch
#     fired), (b) after the LAST `picked` line of the lane run file's `## Progress` there are 0 or ≥ 2
#     lines starting (after one timestamp token) `owned drain started — `, or ≥ 2 starting `owned drain
#     started (fix-now re-drain) — `, or (c) <lane>/.supervisor/automate/<run_id>.config-backup.json exists
#     (the auto_review toggle was never restored);
#   `drain-guard: ok — <n> owned drain(s), no dispatch marker, no config backup` otherwise;
#   `drain-guard: unknown — <reason>` when the lane, its run file, its PR or its `picked` line cannot be
#     read (observation fails SAFE — never `ok` on what it could not read).
lanes_drain_check() {
  local dir="${1:-}" G="drain-guard:" rf pr after plain fix why=""
  _lane_ctx "$dir" || { echo "$G unknown — not a lane: ${dir:-<none>}"; return 0; }
  rf="$LN_DIR/.supervisor/automate/$LN_RUN.md"
  [ -f "$rf" ] && [ -r "$rf" ] || { echo "$G unknown — lane run file unreadable ($LN_RUN.md)"; return 0; }
  grep -q '^## Progress' "$rf" 2>/dev/null || { echo "$G unknown — lane run file has no ## Progress ($LN_RUN.md)"; return 0; }
  pr="$(_lanes_dash "$(_lanes_runfile_fields "$rf" | cut -f3)")"
  case "$pr" in ''|null) echo "$G unknown — no PR in the lane ## Current ($LN_RUN.md)"; return 0 ;; esac
  after="$(awk '
    /^## / { inp = ($0 ~ /^## Progress/); next }
    !inp { next }
    { n++; line[n] = $0; l = $0; sub(/^- /, "", l); if (l ~ /^([^ ]+ )?picked /) last = n }
    END { if (!last) exit 1; for (i = last + 1; i <= n; i++) print line[i] }' "$rf" 2>/dev/null)" \
    || { echo "$G unknown — no picked line in the lane ## Progress ($LN_RUN.md)"; return 0; }
  plain="$(printf '%s\n' "$after" | awk '{ l = $0; if (sub(/^- /, "", l) == 0) next; sub(/^[^ ]+ /, "", l)
    if (index(l, "owned drain started — ") == 1) c++ } END { print c + 0 }')"
  fix="$(printf '%s\n' "$after" | awk '{ l = $0; if (sub(/^- /, "", l) == 0) next; sub(/^[^ ]+ /, "", l)
    if (index(l, "owned drain started (fix-now re-drain) — ") == 1) c++ } END { print c + 0 }')"
  [ -e "$LN_DIR/.supervisor/review-dispatch/$(_lanes_pr_hash "$pr")" ] \
    && why="${why:+$why; }review-dispatch marker for $pr (a detached default drain was dispatched)"
  [ "$plain" = 1 ] || why="${why:+$why; }$plain owned drain(s) after the last picked line (exactly 1 expected)"
  [ "$fix" -lt 2 ] || why="${why:+$why; }$fix fix-now re-drains after the last picked line (at most 1)"
  [ -e "$LN_DIR/.supervisor/automate/$LN_RUN.config-backup.json" ] \
    && why="${why:+$why; }config backup $LN_RUN.config-backup.json present (auto_review never restored)"
  if [ -n "$why" ]; then echo "$G violation — $why"
  else echo "$G ok — $((plain + fix)) owned drain(s), no dispatch marker, no config backup"; fi
  return 0
}

# ---- leak check (Validation 5) ----------------------------------------------------------------------
# _lanes_leak_lanes_dir <primary> <parent> — the `## lanes-dir` section: one line per entry of
# <primary>-lanes/, except that THIS run's own directory is listed by its contents minus the run's
# kept artifacts, matched by EXACT name (never a glob): `salvage` (lane-create / lane-remove salvage)
# and, for every lane in this run's table, `L<n>.stream.log`, `L<n>.stdin.json`, `L<n>.died`. A lane
# directory still present (`<parent>/L<n>`) or any other file there is listed, so it reads as a leak.
# After a clean wave this run's directory contributes nothing — the same as at wave start, when it
# does not exist yet, and the same once item 21 removes it (parallel-automate/23 F9).
_lanes_leak_lanes_dir() {
  local p="$1" parent="${2:-}" e f keep="salvage" l nl
  nl="$(printf '\nx')"; nl="${nl%x}"
  [ -d "$p-lanes" ] || return 0
  if [ -n "$parent" ] && [ -f "$p/.supervisor/automate/$parent.lanes" ]; then
    for l in $(awk -F'\t' '$1 ~ /^L[0-9][0-9]?$/ { print $1 }' "$p/.supervisor/automate/$parent.lanes"); do
      keep="$keep$nl$l.stream.log$nl$l.stdin.json$nl$l.died"
    done
  fi
  ls -1 "$p-lanes" 2>/dev/null | while IFS= read -r e; do
    if [ -n "$parent" ] && [ "$e" = "$parent" ] && [ -d "$p-lanes/$e" ]; then
      ls -1 "$p-lanes/$e" 2>/dev/null | while IFS= read -r f; do
        grep -qxF -- "$f" <<<"$keep" || printf '%s/%s\n' "$e" "$f"
      done
    else
      printf '%s\n' "$e"
    fi
  done
}

# _lanes_leak_watchers <primary> <parent> — the `## merge-watch v2` section body: one `<pid> <pr_url>`
# line per LIVE merge watcher, sorted, read from the `*.merge-watch` markers through _lanes_live_watchers
# (the marker's pid still runs automate-merge-watch for that marker's PR) — for the primary's
# `.supervisor/automate/` and for every lane path in this run's lane table (a removed lane's directory
# has no markers left). Never a process-table pattern match: `pgrep -lf automate-merge-watch` (v1) also
# matched any process whose argv merely NAMED the script — a `grep … scripts/automate-merge-watch.sh`
# in the coordinator read as `leaks: found — merge-watch` with no watcher running (wave W3, 2026-10-11).
# Honest limit: a watcher with no marker (or whose marker was deleted) is not listed; every watcher this
# plugin starts writes one (automate-merge-watch.sh), and lane-remove reads the same markers.
_lanes_leak_watchers() {
  local p="$1" parent="${2:-}" tbl l
  {
    _lanes_live_watchers "$p"
    tbl="$p/.supervisor/automate/$parent.lanes"
    if [ -n "$parent" ] && [ -f "$tbl" ]; then
      awk -F'\t' '$1 ~ /^L[0-9][0-9]?$/ && $2 != "" && $2 != "-" { print $2 }' "$tbl" | while IFS= read -r l; do
        [ -d "$l" ] && _lanes_live_watchers "$l"
      done
    fi
  } | tr '\t' ' ' | env LC_ALL=C sort -u
  return 0
}

_lanes_leak_sections() { # <primary> <parent>
  local p="$1" pg="${LOOMWRIGHT_LANES_PGREP:-pgrep}"
  echo "## worktrees"; git -C "$p" worktree list --porcelain 2>/dev/null | awk '/^worktree /'
  echo "## lanes-dir"; _lanes_leak_lanes_dir "$p" "${2:-}"
  echo "## claude-p"; "$pg" -lf 'claude -p' 2>/dev/null
  # The format tag IS the header: lanes_leaks compares this section only against a snapshot section
  # written in the same format (a v1 `## merge-watch` snapshot section is read as not compared).
  echo "## merge-watch v2"
  _lanes_leak_watchers "$p" "${2:-}"   # >>> merge-watch body
  echo "## config-checksum"
  if [ -f "$p/.supervisor/config.json" ]; then cksum < "$p/.supervisor/config.json" | awk '{ print $1, $2 }'; else echo absent; fi
  echo "## git-status"; git -C "$p" status --porcelain 2>/dev/null | awk '!/\.leaks-snapshot$/'
  return 0
}

# lanes_leaks <primary> <parent> [snapshot 0|1] — `--snapshot` records the wave-start state; otherwise
# compares now against it. First line: `leaks: none` | `leaks: found — <sections>` | `leaks: unknown — …`.
lanes_leaks() {
  local p="$1" parent="$2" snap="${3:-0}" sf tmp sec found="" body="" d hd nc=""
  sf="$p/.supervisor/automate/$parent.leaks-snapshot"
  if [ "$snap" = 1 ]; then
    # The ONE exception to observation's exit 0: a snapshot request that wrote nothing exits 1 naming
    # why, because the end-of-wave check against a missing baseline can never read `none`.
    if { echo "# leaks snapshot $(now_utc)"; _lanes_leak_sections "$p" "$parent"; } > "$sf.tmp.$$" 2>/dev/null && mv "$sf.tmp.$$" "$sf"; then
      echo "leaks: snapshot written — $sf"
    else rm -f "$sf.tmp.$$"; echo "leaks: snapshot not written (unwritable) — $sf"; return 1; fi
    return 0
  fi
  if [ ! -f "$sf" ]; then
    echo "leaks: unknown — no snapshot (take one at wave start: lane-status --leaks --snapshot)"
    _lanes_leak_sections "$p" "$parent" | sed 's/^/  /'; return 0
  fi
  tmp="$(mktemp -d 2>/dev/null)" || { echo "leaks: unknown — no temp dir"; return 0; }
  _lanes_leak_sections "$p" "$parent" > "$tmp/now"
  for sec in worktrees lanes-dir claude-p merge-watch config-checksum git-status; do
    hd="## $sec"
    if [ "$sec" = merge-watch ]; then
      hd="## merge-watch v2"
      # A snapshot taken before the marker-based list (its section is the v1 `## merge-watch` pgrep
      # output, or absent) is NOT compared: two formats never diff into a false `found`.
      if ! grep -qxF -- "$hd" "$sf"; then
        nc="merge-watch not compared — pre-v2 snapshot"
        body="$body- merge-watch: not compared — the wave-start snapshot predates the marker-based watcher list (v1)
"
        continue
      fi
    fi
    awk -v s="$hd" '/^## / { on = ($0 == s); next } on' "$sf" | env LC_ALL=C sort > "$tmp/a"
    awk -v s="$hd" '/^## / { on = ($0 == s); next } on' "$tmp/now" | env LC_ALL=C sort > "$tmp/b"
    if cmp -s "$tmp/a" "$tmp/b"; then body="$body- $sec: same
"
    else
      found="$found${found:+, }$sec"
      d="$(env LC_ALL=C comm -13 "$tmp/a" "$tmp/b" | sed 's/^/  + /'; env LC_ALL=C comm -23 "$tmp/a" "$tmp/b" | sed 's/^/  - /')"
      body="$body- $sec: changed
$d
"
    fi
  done
  rm -rf "$tmp"
  if [ -z "$found" ]; then echo "leaks: none (vs snapshot $sf${nc:+; $nc})"; else echo "leaks: found — $found${nc:+ ($nc)}"; fi
  printf '%s' "$body"
  return 0
}

# ==================================================================================================
# lane-status [<parent_runfile>] [--json] [--watch] [--leaks [--snapshot]] [--resources] [--tokens]
#             [--refresh-readiness] [--keep-awake] [--inbox]
lanes_status() {
  local rf="" json=0 watch=0 leaks=0 snap=0 res=0 tok=0 ka=0 refresh=0 inbox=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --inbox) inbox=1 ;;
      --json) json=1 ;; --watch) watch=1 ;; --leaks) leaks=1 ;; --snapshot) leaks=1; snap=1 ;;
      --resources) res=1 ;; --tokens) tok=1 ;; --keep-awake) ka=1 ;; --refresh-readiness) refresh=1 ;;
      -*) echo "lane-status: unknown flag '$1'" >&2; return 2 ;;
      *) [ -z "$rf" ] || { echo "lane-status: unexpected argument '$1'" >&2; return 2; }; rf="$1" ;;
    esac
    shift
  done
  if [ "$watch" = 1 ]; then _lanes_watch "$rf"; return 0; fi
  local table parent primary doc tab lane path ts
  if ! table="$(_lanes_table_for "$rf")"; then
    if [ "$leaks" = 1 ]; then
      # §14 step 5 takes the wave-start snapshot BEFORE step 6's first lane-create, so no lane table
      # exists yet: the parent run id and the primary come from <parent_runfile> itself (F1).
      if ! _lanes_parent_of "$rf"; then
        if [ "$snap" = 1 ]; then echo "leaks: snapshot not written — $LP_WHY"; return 1; fi
        echo "leaks: unknown — $LP_WHY"; return 0
      fi
      lanes_leaks "$LP_PRIMARY" "$LP_PARENT" "$snap"; return $?
    fi
    if [ "$json" = 1 ]; then
      jq -n -c --argjson m "$(_lanes_machine_json)" '{schema_version: 1, parent_run_id: null, machine: $m, lanes: []}'
    else echo "lane-status: no lane table (${rf:-none found}) — no lanes"; fi
    return 0
  fi
  parent="$(basename "$table" .lanes)"; primary="$(cd "$(dirname "$table")/../.." && pwd -P)"
  [ "$leaks" = 1 ] && { lanes_leaks "$primary" "$parent" "$snap"; return $?; }
  [ "$res" = 1 ] && { _lanes_resources "$primary" "$parent"; return 0; }
  [ "$tok" = 1 ] && { _lanes_tokens "$table" "$primary" "$parent"; return 0; }
  [ "$inbox" = 1 ] && { _lanes_inbox "$table"; return 0; }
  [ "$ka" = 1 ] && _lanes_keep_awake_start
  if [ "$refresh" = 1 ]; then
    tab="$(printf '\t')"
    while IFS="$tab" read -r lane path _; do
      case "$lane" in L[0-9]|L[0-9][0-9]) ;; *) continue ;; esac
      [ -d "$path" ] && _lane_ctx "$path" || continue
      ts="$(_lanes_runfile_fields "$path/.supervisor/automate/$LN_RUN.md" | cut -f1-2)"
      case "$ts" in *ready_for_release*|*awaiting_merge*|done*) lanes_readiness "$path" >/dev/null ;; esac
    done < "$table"
  fi
  doc="$(_lanes_status_doc "$table" "$parent" "$primary")"
  if [ -z "$doc" ]; then echo "lane-status: unknown — status unreadable"; return 0; fi
  if [ "$json" = 1 ]; then printf '%s\n' "$doc"; else _lanes_render "$doc"; fi
  return 0
}

# _lanes_watch [<parent_runfile>] — the plain view every LOOMWRIGHT_LANES_WATCH_INTERVAL_S (default 15)
# seconds; LOOMWRIGHT_LANES_WATCH_ITERATIONS (default 0 = until interrupted) is the test seam.
_lanes_watch() {
  local n="${LOOMWRIGHT_LANES_WATCH_ITERATIONS:-0}" iv="${LOOMWRIGHT_LANES_WATCH_INTERVAL_S:-15}" i=0
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  case "$iv" in ''|*[!0-9]*) iv=15 ;; esac
  while :; do
    [ -t 1 ] && printf '\033[H\033[2J'
    echo "lane-status --watch — $(now_utc) — every ${iv}s (interrupt to stop)"
    if [ -n "${1:-}" ]; then lanes_status "$1"; else lanes_status; fi
    i=$((i + 1)); [ "$n" -gt 0 ] && [ "$i" -ge "$n" ] && return 0
    sleep "$iv"
  done
}

# _lanes_wait_print — stdin "<key>\t<line>" rows ⇒ `lane-wait: <line>`; a question row's text (after its
# first ` — `; the `question <lane> <id> asked <at>` prefix never holds one) is clipped with _lanes_clip 160.
_lanes_wait_print() {
  local key body
  while IFS="$(printf '\t')" read -r key body; do
    [ -n "$key" ] || continue
    case "$key" in
      question\ *) body="${body%% — *} — $(printf '%s' "${body#* — }" | _lanes_clip 160)" ;;
    esac
    printf 'lane-wait: %s\n' "$body"
  done
}

# lane-wait <parent_runfile> [--interval S] [--timeout S] — the coordinator's lane watcher (§14 "The
# per-wave loop" step 8). A lane that needs the owner records it and goes quiet (relay-hook defers and the
# lane exits; a park is a run-file line): nothing else tells the coordinator session, so a question sat
# unseen until the owner happened to look (W3, 2026-10-11 — two lanes waited 22–24 min). This blocks,
# token-free (a `sleep` loop over `lane-status --json`), until an ATTENTION event appears that its seen
# ledger has not reported, prints it and exits 0 — the coordinator runs it as a BACKGROUND command, so the
# host re-invokes the coordinator when it exits, and re-arms it after relaying. Events, one line each:
#   lane-wait: question <lane> <tool_use_id> asked <asked_at> — <question, clipped by _lanes_clip 160>
#   lane-wait: state <lane> <state> — pr <url|->   (state ∉ _LANES_WAIT_LIVE and ∉ _LANES_WAIT_QUIET)
# A state is an event unless it is LIVE (the lane is working) or QUIET (a state the coordinator itself
# drives and needs no wake-up for: awaiting_merge, awaiting_go, done, removed, abandoned). This is a
# deny-list on purpose: `_lanes_parked` reports ANY non-empty run-file `pause_reason` as the lane's state
# (token_ceiling, run_lock_held, trail_pr_open, closeout_leftover, …) and an attention ALLOW-list kept
# missing them (round 3 found `failed`) — a lane in a missed state was invisible and `idle` fired past
# it. A new or unknown state (incl. a fail-safe `unknown`) now fails TOWARD notifying, once per entry.
# then one hint line per event kind present: state events ⇒ `lane-wait: act — …` (handle the lane per
# SKILL §14 "Lane states", then re-arm); questions ⇒ `lane-wait: relay — …` (last when both). No live
# lane left (none created / running / held / answer_pending) and nothing new ⇒ `lane-wait: idle — no
# lane is running; nothing changes until the owner acts`, exit 0 (never a forever-poll of parked lanes). `--timeout S` (default 0 = none) ⇒
# `lane-wait: timeout after <S>s — nothing new`, exit 0. Unreadable status ⇒ retried next interval.
# Seen ledger: `<automate dir>/<parent_run_id>.lane-wait-seen`, one key per line — a question key is kept
# for good (tool_use_ids never repeat), a state key only while that lane is still in that state, so a
# lane that stalls, is resumed and stalls again is reported again. Keys are recorded when PRINTED: a
# coordinator that dies after the exit and before relaying does not see them again from lane-wait (its
# next `--resume` runs `lane-status --inbox`, which lists every pending question regardless).
# Liveness marker: once it has a lane table to watch, lane-wait writes `<automate dir>/<parent_run_id>.
# lane-wait.pid` = `<its pid> <start epoch>` (tmp+mv) and an EXIT trap (TERM / INT / HUP exit through it)
# removes it ONLY while the file still names ITS pid — a second lane-wait armed meanwhile owns the file
# and keeps it. The coordinator's Stop hook (guard-lane-wait-armed.sh) reads it: a coordinator turn that
# ends with a live wave and no live watcher is sent back to arm one. A stale marker (pid gone, or reused
# by a process that is not a lane-wait) reads as no watcher.
# Never answers, launches, resumes or writes into a lane. Exits 0 except a usage error (2).
_LANES_WAIT_QUIET='["awaiting_merge","awaiting_go","done","removed","abandoned"]'
_LANES_WAIT_LIVE='["created","running","held_for_load","answer_pending"]'
_LANES_WAIT_MARK=""
# _lanes_wait_unmark — remove lane-wait's liveness marker iff it still names this process.
_lanes_wait_unmark() {
  [ -n "$_LANES_WAIT_MARK" ] || return 0
  [ "$(awk 'NR == 1 { print $1 }' "$_LANES_WAIT_MARK" 2>/dev/null)" = "$$" ] && rm -f "$_LANES_WAIT_MARK" 2>/dev/null
  _LANES_WAIT_MARK=""
  return 0
}

# _lanes_quick_state <path> <pid> <pid_start> <table_state> <answer-pending file> — a lane's state as
# _lanes_lane_json classifies it, in its first-match order, but only as far as the live / attention
# split needs and with NO gh, ci-slot or stream-log read (the coordinator's Stop hook runs it at every
# turn end): answer_pending · blocked_launch · held_for_load · created · missing · running ·
# awaiting_input · `other` (removed / abandoned and every state past awaiting_input: a park, died,
# lost_to_reset, stalled — none of them live, none an unanswered question). Membership in
# _LANES_WAIT_LIVE stays the caller's: this never restates that set.
_lanes_quick_state() {
  local path="$1" pid="$2" st="$3" ts="$4" apf="${5:-}" pend="" alive=0 nq=0
  case "$ts" in removed|abandoned) printf 'other'; return 0 ;; esac
  lanes_proc_alive "$pid" "$st" "$path" && alive=1
  [ -d "$path/.supervisor/inbox" ] && _lanes_pending_question "$path/.supervisor/inbox" >/dev/null && nq=1
  if [ "$alive" = 0 ] && [ "$nq" = 1 ] && [ -n "$apf" ] && [ -s "$apf" ]; then
    pend="$(jq -r '.tool_use_id // empty' "$apf" 2>/dev/null)"
    case "$pend" in ''|*[!A-Za-z0-9_-]*) pend="" ;; esac
    if [ -n "$pend" ] && { [ ! -f "$path/.supervisor/inbox/questions/$pend.json" ] || [ -e "$path/.supervisor/inbox/answers/$pend.json" ]; }; then pend=""; fi
  fi
  [ -n "$pend" ] && { printf 'answer_pending'; return 0; }
  case "$ts" in
    blocked_launch) printf 'blocked_launch' ;;
    held_for_load) if [ "$nq" = 1 ] && [ -d "$path" ] && [ "$alive" = 0 ]; then printf 'awaiting_input'; else printf 'held_for_load'; fi ;;
    created) printf 'created' ;;
    *) if [ ! -d "$path" ]; then printf 'missing'
       elif [ "$alive" = 1 ]; then printf 'running'
       elif [ "$nq" = 1 ]; then printf 'awaiting_input'
       else printf 'other'; fi ;;
  esac
}
lanes_wait() {
  local rf="" iv="${LOOMWRIGHT_LANES_WAIT_INTERVAL_S:-15}" to=0 start doc parent ledger cur keep new live
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --interval) iv="${2:-}"; shift ;;
      --timeout) to="${2:-}"; shift ;;
      -*) echo "lane-wait: unknown flag '$1'" >&2; return 2 ;;
      *) [ -z "$rf" ] || { echo "lane-wait: unexpected argument '$1'" >&2; return 2; }; rf="$1" ;;
    esac
    shift
  done
  [ -n "$rf" ] || { echo "usage: lane-wait <parent_runfile> [--interval S] [--timeout S]" >&2; return 2; }
  case "$iv" in ''|*[!0-9]*|0) echo "lane-wait: --interval must be a positive integer" >&2; return 2 ;; esac
  case "$to" in ''|*[!0-9]*) echo "lane-wait: --timeout must be a non-negative integer" >&2; return 2 ;; esac
  _lanes_table_for "$rf" >/dev/null 2>&1 || { echo "lane-wait: idle — no lane table for ${rf} (nothing to watch)"; return 0; }
  start="$(date +%s)"
  _LANES_WAIT_MARK="$(basename "$rf")"; _LANES_WAIT_MARK="${_LANES_WAIT_MARK%.md}"
  _LANES_WAIT_MARK="$(dirname "$rf")/${_LANES_WAIT_MARK%.lanes}.lane-wait.pid"
  { printf '%s %s\n' "$$" "$start" > "$_LANES_WAIT_MARK.tmp.$$" && mv "$_LANES_WAIT_MARK.tmp.$$" "$_LANES_WAIT_MARK"; } 2>/dev/null \
    || rm -f "$_LANES_WAIT_MARK.tmp.$$" 2>/dev/null
  trap '_lanes_wait_unmark' EXIT
  trap '_lanes_wait_unmark; exit 143' TERM
  trap '_lanes_wait_unmark; exit 130' INT
  trap '_lanes_wait_unmark; exit 129' HUP
  while :; do
    doc="$(lanes_status "$rf" --json 2>/dev/null)"
    parent="$(jq -r '.parent_run_id // empty' <<<"$doc" 2>/dev/null)"
    if [ -n "$parent" ]; then
      ledger="$(dirname "$rf")/$parent.lane-wait-seen"
      # Current attention events: "<key>\t<line>"; the key is what the ledger dedupes on.
      # The `awaiting_input` guard below drops that state line when its questions already
      # report it; its question-less branch is belt-and-suspenders — today _lanes_lane_json
      # sets state=awaiting_input only when a question exists, so that branch is unreachable,
      # but it keeps a question-less awaiting_input reported if that invariant ever changes.
      # The question text is emitted whole (one line) and clipped by _lanes_clip when PRINTED.
      cur="$(jq -r --argjson live "$_LANES_WAIT_LIVE" --argjson quiet "$_LANES_WAIT_QUIET" '
        .lanes[]? as $l
        | ( ($l.questions // [])[]
            | "question \($l.lane) \(.id)\tquestion \($l.lane) \(.id) asked \(.asked_at // "unknown") — \((.question // "") | gsub("[\\r\\n\\t]+"; " "))" ),
          ( select(($live | index($l.state)) == null and ($quiet | index($l.state)) == null)
            | select($l.state != "awaiting_input" or (($l.questions // []) | length) == 0)
            | "state \($l.lane) \($l.state)\tstate \($l.lane) \($l.state) — pr \($l.pr // "-")" )' <<<"$doc" 2>/dev/null)"
      # Ledger pruned to what is still true: every question key, and state keys still current.
      keep="$( { [ -f "$ledger" ] && cat "$ledger"; } 2>/dev/null | while IFS= read -r k; do
        case "$k" in
          question\ *) printf '%s\n' "$k" ;;
          state\ *) grep -qxF -- "$k" <<<"$(cut -f1 <<<"$cur")" && printf '%s\n' "$k" ;;
        esac
      done)"
      new="$(printf '%s\n' "$cur" | while IFS= read -r ln; do
        [ -n "$ln" ] || continue
        grep -qxF -- "$(cut -f1 <<<"$ln")" <<<"$keep" || printf '%s\n' "$ln"
      done)"
      if [ -n "$new" ]; then
        { [ -n "$keep" ] && printf '%s\n' "$keep"; printf '%s\n' "$new" | cut -f1; } > "$ledger.tmp.$$" 2>/dev/null \
          && mv "$ledger.tmp.$$" "$ledger" 2>/dev/null || rm -f "$ledger.tmp.$$" 2>/dev/null
        printf '%s\n' "$new" | _lanes_wait_print
        grep -q '^state ' <<<"$new" \
          && echo "lane-wait: act — handle each state line per the automate-loop skill §14 \"Lane states and what the coordinator does\" (report it to the owner; resume a stalled lane once; ready_for_release ⇒ wave-end handling; any other state — died / lost_to_reset / escalated / failed / gone or a run-file park such as token_ceiling — the owner decides), then re-arm lane-wait"
        grep -q '^question ' <<<"$new" \
          && echo "lane-wait: relay — show each question to the owner verbatim (lane-status $rf --inbox), deliver only the owner's answer with lane-answer, then re-arm lane-wait"
        return 0
      fi
      # Nothing new: the ledger is rewritten to exactly `keep` — removed when keep is empty, so a lone
      # stale state key (L1 stalled → running) is pruned too and the re-entered state reports again.
      if [ -f "$ledger" ]; then
        if [ -n "$keep" ]; then
          { printf '%s\n' "$keep" > "$ledger.tmp.$$" 2>/dev/null && mv "$ledger.tmp.$$" "$ledger" 2>/dev/null; } || rm -f "$ledger.tmp.$$" 2>/dev/null
        else
          rm -f "$ledger" 2>/dev/null
        fi
      fi
      live="$(jq -r --argjson live "$_LANES_WAIT_LIVE" '[.lanes[]? | .state as $s | select($live | index($s))] | length' <<<"$doc" 2>/dev/null)"
      if [ "${live:-1}" = 0 ]; then
        echo "lane-wait: idle — no lane is running; nothing changes until the owner acts"
        return 0
      fi
    fi
    if [ "$to" -gt 0 ] && [ "$(( $(date +%s) - start ))" -ge "$to" ]; then
      echo "lane-wait: timeout after ${to}s — nothing new"
      return 0
    fi
    sleep "$iv"
  done
}

# ==================================================================================================
# lane-feed <lane_dir|L<n>> [--follow] — a readable narration of the lane's stream log.
_LANES_FEED_JQ='fromjson? |
  if .type == "system" and .subtype == "init" then "[init] session \(.session_id // "?")"
  elif .type == "assistant" then (.message.content[]? |
    if .type == "text" then ((.text // "") | gsub("[\\r\\n\\t]+"; " ") | gsub("^ +| +$"; "")) as $t
      | select($t != "") | "[say] \($t[0:200])"
    elif .type == "tool_use" then
      if (.name == "Task" or .name == "Agent") then "[spawn] \(.input.subagent_type // "agent"): \((.input.description // "") | tostring | .[0:120])"
      elif .name == "AskUserQuestion" then "[ask] \(((.input.questions // [])[0].question // "") | tostring | .[0:160])"
      elif .name == "Bash" and ((.input.command // "") | test("current-set")) and ((.input.command // "") | test("ready_for_release|awaiting_merge|escalated"))
        then "[park] \((.input.command // "") | gsub("[\\r\\n\\t]+"; " ") | .[0:160])"
      else "[tool] \(.name) \((.input.command // .input.description // .input.file_path // .input.pattern // "") | tostring | gsub("[\\r\\n\\t]+"; " ") | .[0:120])" end
    else empty end)
  elif .type == "result" then
    if .stop_reason == "tool_deferred" then "[park] deferred \(.deferred_tool_use.id // "?") — awaiting input"
    else "[end] \(.subtype // "?") stop_reason=\(.stop_reason // "?")" end
  else empty end'

lanes_feed() {
  local target="" follow=0 dir
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --follow) follow=1 ;;
      *) [ -z "$target" ] || die "lane-feed: unexpected argument '$1'"; target="$1" ;;
    esac
    shift
  done
  dir="$(_lanes_resolve "$target")"
  _lane_ctx "$dir" || die "lane-feed: not a lane: ${target:-<none>}"
  if [ ! -f "$LN_LOG" ] && [ "$follow" = 0 ]; then echo "lane-feed: $LN_LANE — no stream log yet ($LN_LOG)"; return 0; fi
  echo "lane-feed: $LN_LANE ($LN_RUN) — $LN_LOG"
  if [ "$follow" = 1 ]; then
    touch "$LN_LOG" 2>/dev/null
    # The pipeline never ends by itself (`tail -f`), so it runs in the BACKGROUND and this process
    # blocks on `wait`: bash defers a trapped signal until a FOREGROUND command returns, but a trapped
    # signal interrupts `wait`. On TERM / INT / HUP the trap kills the pipeline it started — `jobs -p`
    # names its first process (tail), `$!` its last (jq); grep then reads EOF — and exits, so killing
    # the lane-feed process alone leaves nothing behind (parallel-automate/24 F12). Async children of a
    # non-interactive bash start with SIGINT ignored, hence TERM to them whatever signal arrived here.
    _LANES_FEED_PIDS=""
    trap 'kill -TERM $(jobs -p) $_LANES_FEED_PIDS 2>/dev/null; exit 0' TERM INT HUP
    tail -n +1 -f "$LN_LOG" | grep --line-buffered '^{' | jq --unbuffered -r -R "$_LANES_FEED_JQ" 2>/dev/null &
    _LANES_FEED_PIDS="$(jobs -p) $!"
    wait
    trap - TERM INT HUP
    return 0
  fi
  grep '^{' "$LN_LOG" 2>/dev/null | jq -r -R "$_LANES_FEED_JQ" 2>/dev/null
  [ -f "$LN_DIED" ] && echo "[died] $(awk -F'\t' '$1 == "died_at" { print $2 }' "$LN_DIED" 2>/dev/null) — no terminal result"
  return 0
}

# ==================================================================================================
# lane-readiness <lane_dir|L<n>> — writes <lane>/.supervisor/automate/<run_id>.merge-readiness.md
# (advisory, never a merge executor). Five checks, each PASS / FAIL / NOT-RUN with its evidence:
#   validation     each `## Validation` entry of the item: PASS only with pasted output (a fenced block)
#                  in the PR body's matching section; mentioned without output, or absent ⇒ NOT-RUN
#   carried-notes  the brief's carried MEDIUM/LOW Plan Review notes, accounted for in the PR body
#   scope-fence    `gh pr diff --name-only` ⊆ the item's `## Touches` / the brief's lanes + changelog.d/
#   gates          required checks on the current head, dismissed-finding decisions, children-settled
#   headline-repro the Validation entry naming a mutation / repro (PASS n/a when none is named)
# Called by the lane at its ready_for_release park; re-written on demand (`lane-status --refresh-readiness`,
# which also covers a lane already closed out — `done` — so a report written before a fix is repairable).
# _lanes_rd_section <n> <title> <body_file> [nv] [<others>] [<tm>] — the PR body's lines for Validation
# entry n. With the 4th argument `nv` it prints instead ONE line: `NV` when any matched block starts
# under a PR-body heading (at any enclosing level) containing "not verified" or "not run"; else `NL`
# when such a heading says "skipped", or ANY non-fenced line of a matched block (its first line, a
# continuation, a heading-started section's body) says "not run" / "skipped" / "not verified" (or
# "not yet run", "wasn't run", "couldn't run", "could not get to", "not tested", "untested" — "was
# not run" / "could not run" are already "not run"; any such heading text is a "not run" heading) — each
# as a whole phrase, never inside a longer word ("not running hot" is not "not run"); else nothing —
# the same match, so the not-run tests can never drift from the evidence test. Fenced lines never raise
# NL (pasted output that says "skipped" is output, not the PR's statement). <others> is the item's
# entry titles, newline-separated; <tm> 0 disables the title match (a title another entry's title
# contains is not unique — that entry needs its own "validation <n>"). Titles are read through
# ENVIRON (awk -v would rewrite a backslash). Fence-aware: a line inside a ``` / ~~~ block (shell
# comments, `#!`, root prompts, pasted output) is never a heading, never starts a match, never ends one.
#   heading      `#`..`######` + a space, or a whole-line bold `**…**` naming "not verified" / "not run"
#                / "skipped" (a pseudo-heading below every `#` level)
#   match start  a line naming "validation <n>" (an anchored match), or containing the entry's title
#                (a title match, only when <tm> is not 0 and the line names no "validation <m>" —
#                another step's anchored line is never borrowed by a title)
#   match end    any heading; a line naming another "validation <m>"; for a match that started on a
#                list item, the next list item at the same or a shallower indent; for any non-heading
#                start, an unindented non-fence paragraph after a blank line that is a list item or
#                names another entry's title — and, for a title match, ANY such paragraph (a generic
#                mention never borrows the next paragraph's fence). An anchored match crosses such a
#                paragraph break ONLY when the last non-blank, non-fenced line before it ends in `:`
#                (an intro line: "Validation 1 (tests):" / blank / "Ran the suite:" / blank / fence
#                stays one passage) or, at its FIRST break only, when the new paragraph's line itself
#                ends in `:` (the step's sentence, then "Output:", then the fence); otherwise it closes,
#                so "… needs a quiet machine." / "CI is green." / "Shellcheck output:" + fence never
#                borrows that fence. The shape "<step sentence>." / "<x> output:" + fence is the same
#                for a run step and an unrun one — only the not-run vocabulary tells them apart. An
#                indented line never closes a match by this paragraph rule
_lanes_rd_section() {
  _RD_T="$2" _RD_O="${5:-}" awk -v n="$1" -v mode="${4:-}" -v tm="${6:-1}" '
    BEGIN { t = tolower(ENVIRON["_RD_T"]); vn = "validation[ #]*" n "([^0-9]|$)"; no = split(tolower(ENVIRON["_RD_O"]), ot, "\n") }
    function ind(s) { match(s, /^[ \t]*/); return RLENGTH }
    function ph(s, p,  st, i, j) { st = 1   # p in s as a whole phrase: no letter/digit on either side
      while ((i = index(substr(s, st), p)) > 0) { j = st + i - 1
        if ((j == 1 || substr(s, j - 1, 1) !~ /[a-z0-9]/) && substr(s, j + length(p), 1) !~ /[a-z0-9]/) return 1
        st = j + 1 }
      return 0 }
    function nrv(s) { return ph(s, "not verified") || ph(s, "not run") || ph(s, "not yet run") ||
      ph(s, "wasn\047t run") || ph(s, "wasn\342\200\231t run") || ph(s, "couldn\047t run") ||
      ph(s, "couldn\342\200\231t run") || ph(s, "could not get to") || ph(s, "not tested") || ph(s, "untested") }
    function nrl(s) { return nrv(s) || ph(s, "skipped") }
    function oth(s,  i) { for (i = 1; i <= no; i++) if (ot[i] != "" && !index(t, ot[i]) && index(s, ot[i])) return 1; return 0 }
    { l = tolower($0); wasin = inf; fl = 0; hd = 0 }
    l ~ /^[ \t]*(```|~~~)/ {
      fl = 1; x = l; sub(/^[ \t]*/, "", x); c = substr(x, 1, 3)
      if (!inf) { inf = 1; fc = c } else if (c == fc) inf = 0
    }
    !wasin && !fl && l ~ /^#+[ \t]/ && match(l, /[^#]/) - 1 <= 6 { lv = RSTART - 1; hd = 1 }
    !wasin && !fl && !hd && l ~ /^[ \t]*\*\*.*\*\*[ \t]*:?[ \t]*$/ && nrl(l) { lv = 7; hd = 1 }
    hd { h[lv] = l; for (k = lv + 1; k <= 7; k++) delete h[k]; top = lv }
    { li = (l ~ /^[ \t]*([-*+]|[0-9]+[.)])[ \t]/) }
    on && !wasin && !fl && (hd || (l ~ /validation[ #]*[0-9]/ && l !~ vn) ||
        (sk == "b" && li && ind(l) <= si) ||
        (sk != "h" && blank && l !~ /^[ \t]/ && l !~ /^[ \t]*$/ &&
         (!sw || li || oth(l) || (lnb !~ /:$/ && (pb || l !~ /:[ \t\r]*$/))))) { on = 0 }
    on && !wasin && !fl && sk != "h" && blank && l !~ /^[ \t]/ && l !~ /^[ \t]*$/ { pb = 1 }
    !on && !wasin && !fl && (l ~ vn || (tm != 0 && t != "" && index(l, t) > 0 && l !~ /validation[ #]*[0-9]/)) {
      on = 1; si = ind(l); sw = (l ~ vn); pb = 0
      sk = hd ? "h" : (li ? "b" : "p")
      for (k = 1; k <= top; k++) if (k in h) { if (nrv(h[k])) nv = 1; else if (ph(h[k], "skipped")) nl = 1 }
    }
    on && !wasin && !fl && nrl(l) { nl = 1 }
    on && mode != "nv" { print }
    { blank = (!wasin && !fl && l ~ /^[ \t]*$/); if (!wasin && !fl && !blank) { lnb = l; sub(/[ \t\r]+$/, "", lnb) } }
    END { if (mode == "nv") { if (nv) print "NV"; else if (nl) print "NL" } }' "$3"
}

# _lanes_validation_rows <item_file> <body_file> <gh_ok> [<pr>] — THE Validation reader, shared by
# lane-readiness and validation-gate (af36-remainder/01: no second parser). One TSV row per entry of
# the item's `## Validation` section:  n<TAB>title<TAB>kind<TAB>status<TAB>evidence
#   entries   a column-0 numbered line (`N. ` or `N) `) OR a column-0 `- ` / `* ` / `+ ` bullet; an indented line, or an unindented one right after it (no blank line between),
#             continues the entry; a blank line followed by unindented text ends it. Fence-aware: a
#             ``` / ~~~ block's lines never start an entry or end the section (they join the open entry)
#   number    a numbered entry keeps its own N; the section's bullets are numbered M+1..M+k in order,
#             M = the LARGEST N of any numbered entry anywhere in the section (0 when none) — so a
#             purely bulleted section reads 1..k, a purely numbered one reads as written, and a bullet
#             can never share a number with a numbered entry (af36-remainder/01 drain round 1: `1.` +
#             `- **Running system:**` once read as two entries numbered 1, and the Baseline's
#             "Validation 1" evidenced the Running system step). Two numbered entries that still share
#             a number (`1.` / `1.` as written) are each NOT-RUN — an anchored "validation <n>" is
#             ambiguous there, and ambiguity never reads as evidence (fail CLOSED)
#   title     the entry's first line: its first `**…**` span, else its first 60 chars; trailing `:`
#             stripped; every `|` → `/` and tab runs → one space, so `V<n> <title>` is always a legal
#             `current-escalation --check` value; `(untitled)` when empty
#   kind      running-system — the TITLE contains "running system" (checked first: a gated step is
#             never shadowed by a "reproduce" in its first line) · repro — the FIRST line names a
#             mutation / repro ("mutation", "must catch", "repro", "must fail"; today's rule) ·
#             running-system — the joined entry text contains "running system" · other (case-insensitive)
#   status    gh_ok 0 ⇒ NOT-RUN (PR body unreadable). Else the PR body's matching lines
#             (_lanes_rd_section): none ⇒ NOT-RUN; under a "not verified" / "not run" heading, or any
#             non-fenced matched line saying "not run" / "skipped" / "not verified" (or another phrase of
#             _lanes_rd_section's not-run set) ⇒ NOT-RUN; no fence
#             line ⇒ NOT-RUN; a non-repro entry whose output shows the word FAIL ⇒ FAIL; else PASS
#   unique    an entry whose title (case-insensitive) equals or is contained in another entry's title
#             gets NO title match — e.g. two `- **Running system:**` bullets — so one passage can never
#             evidence two steps: each needs its own "validation <n>" in the PR body, else NOT-RUN
#   unparsed  a `## Validation` section that EXISTS but yields no entry (prose only, or an unsupported
#             list style) prints ONE row instead: 0<TAB>(no parseable entry)<TAB>unparsed<TAB>NOT-RUN<TAB>
#             <reason> — fail CLOSED, so an unreadable section never reads as "no running-system step"
# An unreadable item file, or one with no `## Validation` section, prints nothing (callers that must
# fail CLOSED check readability themselves).
_lanes_validation_rows() {
  local itemf="$1" body="$2" gh_ok="$3" pr="${4:-}" n title kind tm st ev sec nvs ents titles
  ents="$(awk '
    function flush() {
      if (!cur) return
      t = first
      if (match(t, /\*\*[^*]+\*\*/)) t = substr(t, RSTART + 2, RLENGTH - 4)
      else { sub(/^([0-9]+[.)]|[-*+]) */, "", t); t = substr(t, 1, 60) }
      sub(/:$/, "", t); gsub(/\|/, "/", t); gsub(/[ \t]*\t[ \t]*/, " ", t)
      if (t == "") t = "(untitled)"
      lf = tolower(first); lt = tolower(t); lj = tolower(full)
      if (index(lt, "running system")) k = "running-system"
      else if (lf ~ /mutation|must catch|repro|must fail/) k = "repro"
      else if (index(lj, "running system")) k = "running-system"
      else k = "other"
      print num "\t" t "\t" k
      cur = 0; ne++
    }
    { wasin = inf; fl = ($0 ~ /^[ \t]*(```|~~~)/) }
    fl { x = $0; sub(/^[ \t]*/, "", x); c = substr(x, 1, 3); if (!inf) { inf = 1; fc = c } else if (c == fc) inf = 0 }
    fl || wasin { if (on && cur) { x = $0; gsub(/\t/, " ", x); sub(/^ +/, "", x); full = full " " x }; blank = 0; next }
    /^## / { flush(); on = ($0 ~ /^## Validation/); if (on) sec = 1; blank = 0; next }
    !on { next }
    /^[0-9]+[.)] / { flush(); num = $0; sub(/[.)].*/, "", num); cur = 1; blank = 0
                   first = $0; gsub(/\t/, " ", first); full = first; next }
    /^[-*+] / { flush(); num = "b"; cur = 1; blank = 0
            first = $0; gsub(/\t/, " ", first); full = first; next }
    /^[ \t]*$/ { blank = 1; next }
    cur && ($0 ~ /^[ \t]/ || !blank) { x = $0; gsub(/\t/, " ", x); sub(/^ +/, "", x); full = full " " x; blank = 0; next }
    { flush(); blank = 0 }
    END { flush(); if (sec && !ne) print "U" }' "$itemf" 2>/dev/null |
    awk -F'\t' -v OFS='\t' '$0 == "U" { print; next } { r[NR] = $0; if ($1 != "b" && $1 + 0 > m) m = $1 + 0 }
      END { for (i = 1; i <= NR; i++) { if (!(i in r)) continue; $0 = r[i]; if ($1 == "b") $1 = ++m; print } }')"
  [ -n "$ents" ] || return 0
  # Fail CLOSED: a section that exists but yields no entry is never "no step" — one row, kind unparsed.
  if [ "$ents" = U ]; then
    printf '0\t(no parseable entry)\tunparsed\tNOT-RUN\t%s\n' "the ## Validation section has no parseable entry (an entry is a column-0 N. / N) / - / * / + list item)"
    return 0
  fi
  titles="$(cut -f2 <<<"$ents")"
  # 4th column tm: 0 when this title equals / is contained in another entry's title (no title match).
  # 5th column du: 1 when another entry carries the same number (numbered `1.` / `1.` as written).
  awk -F'\t' '{ r[NR] = $0; lt[NR] = tolower($2); nn[NR] = $1 + 0; c[$1 + 0]++ }
    END { for (i = 1; i <= NR; i++) { tm = 1; for (j = 1; j <= NR; j++) if (j != i && index(lt[j], lt[i])) tm = 0; print r[i] "\t" tm "\t" (c[nn[i]] > 1) } }' <<<"$ents" |
  while IFS="$(printf '\t')" read -r n title kind tm du; do
    [ -n "$n" ] || continue
    # (`${pr:-…}` expands to $pr itself when set — the old one-expression form printed the URL twice)
    if [ "$gh_ok" = 0 ]; then st=NOT-RUN; if [ -n "$pr" ]; then ev="PR body unreadable ($pr)"; else ev="PR body unreadable: no PR recorded"; fi
    elif [ "$du" = 1 ]; then st=NOT-RUN; ev="entry number $n is not unique in the item's ## Validation section (renumber the item)"
    else
      sec="$(_lanes_rd_section "$n" "$title" "$body" "" "$titles" "$tm")"
      if [ -z "$sec" ]; then st=NOT-RUN; ev="no evidence in the PR body"
      elif nvs="$(_lanes_rd_section "$n" "$title" "$body" nv "$titles" "$tm")" && [ "$nvs" = NV ]; then st=NOT-RUN; ev="listed under a \"Not verified\" / \"Not run\" heading in the PR body"
      elif [ -n "$nvs" ]; then st=NOT-RUN; ev="marked not run / skipped / not verified in the PR body"
      elif ! grep -qE '^[[:space:]]*(```|~~~)' <<<"$sec"; then st=NOT-RUN; ev="mentioned in the PR body without pasted output"
      elif [ "$kind" != repro ] && grep -qw 'FAIL' <<<"$sec"; then st=FAIL; ev="pasted output shows FAIL"
      else st=PASS; ev="pasted output in the PR body"; fi
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$n" "$title" "$kind" "$st" "$ev"
  done
}

lanes_readiness() {
  local target="${1:-}" dir
  dir="$(_lanes_resolve "$target")"
  _lane_ctx "$dir" || die "lane-readiness: not a lane: ${target:-<none>}"
  local rf="$LN_DIR/.supervisor/automate/$LN_RUN.md" out="$LN_DIR/.supervisor/automate/$LN_RUN.merge-readiness.md"
  local status pause pr lp pd item itemf tmp view="" head=unknown gh_ok=0 brief=""
  IFS="$(printf '\t')" read -r status pause pr lp pd <<<"$(_lanes_runfile_fields "$rf")"
  pr="$(_lanes_dash "$pr")"; pd="$(_lanes_dash "$pd")"
  item="$(sed -n 's/^- \[.\] //p' "$LN_DIR/.supervisor/lane-backlog.md" 2>/dev/null | head -1)"
  itemf="$LN_DIR/$item"
  tmp="$(mktemp -d 2>/dev/null)" || die "lane-readiness: no temp dir"
  : > "$tmp/body"; : > "$tmp/files"
  if [ -n "$pr" ] && view="$("$LANES_GH" pr view "$pr" --json body,headRefOid 2>/dev/null)" && jq -e 'type == "object"' >/dev/null 2>&1 <<<"$view"; then
    gh_ok=1; jq -r '.body // ""' <<<"$view" > "$tmp/body"; head="$(jq -r '.headRefOid // "unknown"' <<<"$view")"
  fi
  # ---- a + e: Validation entries (the shared reader — validation-gate reads the same rows)
  local vrows="" erows="" n title kind st ev vworst=PASS eworst=PASS vlabel=""
  _lanes_validation_rows "$itemf" "$tmp/body" "$gh_ok" "$pr" > "$tmp/val"
  while IFS="$(printf '\t')" read -r n title kind st ev; do
    [ -n "$n" ] || continue
    if [ "$kind" = repro ]; then
      erows="$erows  - V$n $title: $st — $ev
"
      case "$st" in FAIL) eworst=FAIL ;; NOT-RUN) [ "$eworst" = FAIL ] || eworst=NOT-RUN ;; esac
    else
      vrows="$vrows  - V$n $title: $st — $ev
"
      case "$st" in
        FAIL) vworst=FAIL ;;
        NOT-RUN) [ "$vworst" = FAIL ] || vworst=NOT-RUN ;;
      esac
      if [ "$st" != PASS ]; then
        case "$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]')" in
          *"running system"*) case "$vlabel" in ''|running-system) vlabel=running-system ;; *) vlabel=validation ;; esac ;;
          *) vlabel=validation ;;
        esac
      fi
    fi
  done < "$tmp/val"
  local vline eline
  if [ ! -s "$tmp/val" ]; then vworst=NOT-RUN; vlabel=validation; vline="validation: NOT-RUN — no ## Validation section in $item"
  else vline="validation: $vworst — $(printf '%s' "$vrows" | grep -c ' PASS ' | tr -d ' ') of $(printf '%s' "$vrows" | grep -c '^  - ' | tr -d ' ') entr(ies) evidenced"; fi
  if [ -z "$erows" ]; then eworst=PASS; eline="headline-repro: PASS — n/a (the Validation names no repro)"
  else eline="headline-repro: $eworst — the Validation's named repro"; fi
  # ---- b: carried Plan Review notes
  local cline crows="" nc
  local bl; bl="$(grep -l -F "$item" "$LN_DIR"/.supervisor/jobs/*/*.md 2>/dev/null)"
  [ -n "$item" ] && [ -n "$bl" ] && brief="$(printf '%s\n' "$bl" | while IFS= read -r f; do ls -t "$f"; done 2>/dev/null | head -1)"
  local cworst
  if [ -z "$item" ] || [ -z "$brief" ]; then cworst=NOT-RUN; cline="carried-notes: NOT-RUN — no brief naming $item found in the lane"
  else
    grep -iE 'carried' "$brief" | grep -E 'MEDIUM|LOW' | sed 's/^[[:space:]-]*//' > "$tmp/carried"
    nc="$(wc -l < "$tmp/carried" | tr -d ' ')"
    if [ "$nc" = 0 ]; then cworst=PASS; cline="carried-notes: PASS — none carried ($(basename "$brief"))"
    elif grep -qi 'carried' "$tmp/body"; then cworst=PASS; cline="carried-notes: PASS — $nc carried note(s), accounted for in the PR body"
    else cworst=NOT-RUN; cline="carried-notes: NOT-RUN — $nc carried note(s), no accounting in the PR body"; fi
    crows="$(sed 's/^/  - /' "$tmp/carried")"
  fi
  # ---- c: scope fence
  local fline frows="" fworst f dcl outside=""
  {
    awk '/^## /{ on = ($0 ~ /^## Touches/); next } on' "$itemf" 2>/dev/null | grep -o '`[^`]*`' | tr -d '`'
    [ -n "$brief" ] && sed -n 's/.*path: *"\([^"]*\)".*/\1/p; s/^ *- *"\([^"]*\)" *$/\1/p' "$brief"
  } 2>/dev/null | sed 's#^\./##' | awk 'index($0, "/") || index($0, ".")' | env LC_ALL=C sort -u > "$tmp/declared"
  if [ -z "$pr" ] || ! "$LANES_GH" pr diff "$pr" --name-only > "$tmp/files" 2>/dev/null; then
    fworst=NOT-RUN; if [ -n "$pr" ]; then fline="scope-fence: NOT-RUN — gh pr diff unreadable ($pr)"; else fline="scope-fence: NOT-RUN — gh pr diff unreadable: no PR recorded"; fi
  else
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      case "$f" in changelog.d/*) continue ;; esac
      local okf=0
      while IFS= read -r dcl; do
        [ -n "$dcl" ] || continue
        case "$f" in "$dcl"|*/"$dcl") okf=1; break ;; esac
        case "$dcl" in */) case "$f" in "$dcl"*) okf=1; break ;; esac ;; esac
        case "$dcl" in *'*'*) case "$f" in $dcl) okf=1; break ;; esac ;; esac
      done < "$tmp/declared"
      [ "$okf" = 1 ] || outside="$outside$f
"
    done < "$tmp/files"
    if [ -z "$outside" ]; then fworst=PASS; fline="scope-fence: PASS — $(grep -c . "$tmp/files" | tr -d ' ') file(s) within the declared files + changelog.d/"
    else fworst=FAIL; fline="scope-fence: FAIL — file(s) outside the declared files + changelog.d/"; frows="$(printf '%s' "$outside" | sed '/^$/d; s/^/  - /')"; fi
  fi
  # ---- d: gates
  local gline grows="" gworst=PASS cj cs
  if [ -z "$pr" ]; then gworst=NOT-RUN; grows="  - required checks: NOT-RUN — no PR recorded"
  else
    cj="$("$LANES_GH" pr checks "$pr" --required --json name,bucket 2>/dev/null)" || true
    if ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$cj"; then gworst=NOT-RUN; grows="  - required checks: NOT-RUN — unreadable"
    else
      cs="$(jq -r --arg h "$head" 'if length == 0 then "NOT-RUN — no required checks reported"
        elif any(.[]; .bucket == "fail" or .bucket == "cancel") then "FAIL — " + ([.[] | select(.bucket == "fail" or .bucket == "cancel") | .name] | join(", "))
        elif all(.[]; .bucket == "pass" or .bucket == "skipping") then "PASS — \(length) required check(s) green on \($h)"
        else "NOT-RUN — pending: " + ([.[] | select(.bucket != "pass" and .bucket != "skipping") | .name] | join(", ")) end' <<<"$cj")"
      grows="  - required checks: $cs"
      case "$cs" in FAIL*) gworst=FAIL ;; NOT-RUN*) gworst=NOT-RUN ;; esac
    fi
  fi
  case "$pd" in
    ''|0) grows="$grows
  - dismissed findings: PASS — none pending an owner decision" ;;
    *[!0-9]*) grows="$grows
  - dismissed findings: NOT-RUN — pending_decisions unreadable ($pd)"; [ "$gworst" = FAIL ] || gworst=NOT-RUN ;;
    *) grows="$grows
  - dismissed findings: FAIL — $pd without an owner decision"; gworst=FAIL ;;
  esac
  if grep -qiE 'children[-_ ]settled' "$rf" 2>/dev/null; then
    grows="$grows
  - children-settled: PASS — $(grep -iE 'children[-_ ]settled' "$rf" | tail -1 | sed 's/^- //' | _lanes_clip 160)"
  else
    grows="$grows
  - children-settled: NOT-RUN — not recorded in the run file"; [ "$gworst" = FAIL ] || gworst=NOT-RUN
  fi
  gline="gates: $gworst"
  # ---- score
  local pass=0 total=5 bad="" w lbl
  for w in "validation:$vworst" "carried-notes:$cworst" "scope-fence:$fworst" "gates:$gworst" "headline-repro:$eworst"; do
    lbl="${w%%:*}"; st="${w#*:}"
    if [ "$st" = PASS ]; then pass=$((pass + 1)); else
      [ "$lbl" = validation ] && lbl="${vlabel:-validation}"
      bad="$bad${bad:+, }$lbl $st"
    fi
  done
  local summary="ready ($pass/$total)"; [ -n "$bad" ] && summary="ready ($pass/$total: $bad)"
  # The group's status is its LAST command's, so every optional row is an `if` (never `[ -n … ] &&`,
  # which exits 1 on an empty row and read as a write failure — parallel-automate/23 F5). A non-zero
  # status here now means a real write failure (the redirect, or a printf into a full disk).
  if {
    echo "# Merge readiness: $LN_RUN"
    echo
    echo "- item: ${item:-unknown} | pr: ${pr:-none} | head: $head | written: $(now_utc)"
    echo "- score: $pass/$total | summary: $summary"
    echo "- advisory only: this report never merges; the owner merges by hand."
    echo
    echo "## Checks"
    echo "- $vline"; if [ -n "$vrows" ]; then printf '%s' "$vrows"; fi
    echo "- $cline"; if [ -n "$crows" ]; then printf '%s\n' "$crows"; fi
    echo "- $fline"; if [ -n "$frows" ]; then printf '%s\n' "$frows"; fi
    echo "- $gline"; printf '%s\n' "$grows"
    echo "- $eline"; if [ -n "$erows" ]; then printf '%s' "$erows"; fi
  } > "$out.tmp.$$" 2>/dev/null && mv "$out.tmp.$$" "$out"; then :
  else rm -f "$out.tmp.$$"; rm -rf "$tmp"; echo "lane-readiness: $LN_LANE — report not written (unwritable): $out"; return 0; fi
  rm -rf "$tmp"
  echo "lane-readiness: $LN_LANE ($LN_RUN) — $summary — $out"
  return 0
}

# ==================================================================================================
# validation-gate <runfile> <item> <pr_url> [--waive <n> --words <text>] (af36-remainder/01) — the
# READY-park correctness gate: every "Running system" step of the item's `## Validation` section must
# have pasted evidence in the PR body (the shared reader, _lanes_validation_rows). Takes the run file and
# the item explicitly (never _lane_ctx), so a lane and a sequential run call it the same way. A relative
# <item> resolves against the checkout owning <runfile> (<root>/.supervisor/automate/<run>.md), else $PWD.
# Read-only form — fails CLOSED, prints EXACTLY one line, always exits 0 (stdout IS the verdict):
#   validation-gate: none — no running-system step in <item>
#   validation-gate: ok — <k> running-system step(s) evidenced
#   validation-gate: waived — V<n> <title>[; V<m> <title>…]   every non-PASS running-system step waived
#   validation-gate: unrun — V<n> <title>: <evidence>          the first non-PASS, un-waived one (FAIL too)
#   validation-gate: unrun — <reason>                           unreadable item file, usage error
#   validation-gate: unrun — <item>: the ## Validation section has no parseable entry (…)   (step-less)
# A readable item with no running-system step is `none` without reading the PR — but a `## Validation`
# section the reader parses to zero entries is `unrun`, never `none`; an unreadable PR body
# makes every step NOT-RUN, so any running-system step reads `unrun`. Callers treat anything but
# none / ok / waived as unrun.
# Waiver form (--waive <n> --words <text>) — called by the engine ONLY with an interactive owner's
# answer, never on a can't-ask path — appends ONE `## Progress` line through progress-append:
#   <utc> validation waived: <item> V<n> <title> — owner: "<text>"
# (<item> with any leading `./` stripped). A waiver counts only for the item it names, and only AFTER
# the run file's LAST `picked <item>` line (a re-pick needs a new waiver). Refusals print
# `validation-gate: refused — <reason>` and exit 1 with nothing written: empty words, a `|` or newline
# in them, <n> not a running-system entry, an unreadable item file, no `picked <item>` line in the run
# file, or <item> not the item of the run file's LAST `picked` line (a waiver is only ever for the item
# being parked now). An identical waiver already counted ⇒ `waiver already recorded`, nothing written.
_lanes_vg_itemf() { # <runfile> <item> — the item file's path
  local rf="$1" it="$2" d
  case "$it" in /*) printf '%s' "$it"; return 0 ;; esac
  d="$(cd "$(dirname "$rf")" 2>/dev/null && pwd -P)"
  case "$d" in */.supervisor/automate) printf '%s/%s' "${d%/.supervisor/automate}" "${it#./}" ;; *) printf '%s/%s' "$PWD" "${it#./}" ;; esac
}

_lanes_vg_after_pick() { # <runfile> <item> — the ## Progress lines after the LAST `picked <item>`; exit 1 when none
  VG_ITEM="${2#./}" awk '
    BEGIN { it = ENVIRON["VG_ITEM"] }
    /^## / { inp = ($0 ~ /^## Progress/); next }
    !inp { next }
    { n++; line[n] = $0; l = $0; sub(/^- /, "", l)
      if (l ~ /^([^ ]+ )?picked /) {
        x = l; sub(/^([^ ]+ )?picked /, "", x); split(x, a, " "); x = a[1]
        sub(/[;,]+$/, "", x); sub(/^\.\//, "", x)
        if (x == it) last = n
      } }
    END { if (!last) exit 1; for (i = last + 1; i <= n; i++) print line[i] }' "$1" 2>/dev/null
}

_lanes_vg_last_pick() { # <runfile> — the item of the LAST `picked` line in ## Progress (`./` stripped); exit 1 when none
  awk '
    /^## / { inp = ($0 ~ /^## Progress/); next }
    !inp { next }
    { l = $0; sub(/^- /, "", l)
      if (l ~ /^([^ ]+ )?picked /) {
        x = l; sub(/^([^ ]+ )?picked /, "", x); split(x, a, " "); x = a[1]
        sub(/[;,]+$/, "", x); sub(/^\.\//, "", x); last = x; f = 1
      } }
    END { if (!f || last == "") exit 1; print last }' "$1" 2>/dev/null
}

_lanes_vg_has() { # <lines> <prefix> [exact] — 0 when a `- [<one token> ]<prefix>…` line is there (exact: the whole rest)
  VG_P="$2" VG_X="${3:-}" awk '
    BEGIN { p = ENVIRON["VG_P"]; x = ENVIRON["VG_X"] }
    function hit(s) { return x == "exact" ? (s == p) : (index(s, p) == 1) }
    { l = $0; if (sub(/^- /, "", l) == 0) next
      if (hit(l)) { f = 1; exit }
      sub(/^[^ ]+ /, "", l); if (hit(l)) { f = 1; exit } }
    END { exit !f }' <<<"$1"
}

lanes_validation_gate() {
  local G="validation-gate:" rf="" item="" pr="" wn="" words="" waive=0 hw=0 pos=0
  local usage="usage: validation-gate <runfile> <item> <pr_url> [--waive <n> --words <text>]"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --waive) waive=1; [ "$#" -ge 2 ] || { echo "$G refused — --waive needs a value"; return 1; }; wn="$2"; shift 2 ;;
      --words) hw=1; [ "$#" -ge 2 ] || { echo "$G refused — --words needs a value"; return 1; }; words="$2"; shift 2 ;;
      *) pos=$((pos + 1))
         case "$pos" in 1) rf="$1" ;; 2) item="$1" ;; 3) pr="$1" ;; *) echo "$G unrun — unexpected argument '$1'; $usage"; return 0 ;; esac
         shift ;;
    esac
  done
  if [ "$hw" = 1 ] && [ "$waive" = 0 ]; then echo "$G refused — --words needs --waive <n>"; return 1; fi
  local itemf tab rows n title kind st ev
  tab="$(printf '\t')"
  if [ "$waive" = 1 ]; then
    [ -n "$rf" ] && [ -n "$item" ] || { echo "$G refused — $usage"; return 1; }
    [ "$hw" = 1 ] && [ -n "$words" ] || { echo "$G refused — --waive needs non-empty --words (the owner's own words)"; return 1; }
    case "$words" in *"|"*|*"
"*) echo "$G refused — the owner's words contain '|' or a newline"; return 1 ;; esac
    case "$wn" in ''|*[!0-9]*) echo "$G refused — --waive '$wn' is not an entry number"; return 1 ;; esac
    itemf="$(_lanes_vg_itemf "$rf" "$item")"
    [ -f "$itemf" ] && [ -r "$itemf" ] || { echo "$G refused — item file unreadable: $item"; return 1; }
    title="$(_lanes_validation_rows "$itemf" /dev/null 0 | awk -F'\t' -v n="$wn" '$1 == n && $3 == "running-system" { print $2; exit }')"
    [ -n "$title" ] || { echo "$G refused — V$wn is not a running-system Validation entry of $item"; return 1; }
    local after lastp
    if ! after="$(_lanes_vg_after_pick "$rf" "$item")"; then echo "$G refused — no \`picked $item\` line in $rf (a waiver would never count)"; return 1; fi
    lastp="$(_lanes_vg_last_pick "$rf")" || lastp=""
    if [ "$lastp" != "${item#./}" ]; then echo "$G refused — $item is not the run's current item (last picked: ${lastp:-none})"; return 1; fi
    if _lanes_vg_has "$after" "validation waived: ${item#./} V$wn $title — owner: \"$words\"" exact; then
      echo "$G waiver already recorded — V$wn $title"; return 0
    fi
    bash "$HELPERS" progress-append "$rf" "$(now_utc) validation waived: ${item#./} V$wn $title — owner: \"$words\"" >/dev/null 2>&1 \
      || { echo "$G refused — progress-append failed on $rf"; return 1; }
    echo "$G waiver recorded — V$wn $title"
    return 0
  fi
  [ -n "$rf" ] && [ -n "$item" ] || { echo "$G unrun — $usage"; return 0; }
  itemf="$(_lanes_vg_itemf "$rf" "$item")"
  if [ ! -f "$itemf" ] || [ ! -r "$itemf" ]; then echo "$G unrun — item file unreadable: $item"; return 0; fi
  rows="$(_lanes_validation_rows "$itemf" /dev/null 0)"
  # Fail CLOSED: a section the reader cannot parse is unrun (step-less, nothing to waive), never `none`.
  ev="$(awk -F'\t' '$3 == "unparsed" { print $5; exit }' <<<"$rows")"
  if [ -n "$ev" ]; then echo "$G unrun — $item: $ev"; return 0; fi
  if ! awk -F'\t' '$3 == "running-system" { f = 1 } END { exit !f }' <<<"$rows"; then
    echo "$G none — no running-system step in $item"; return 0
  fi
  local tmp view gh_ok=0 k=0 waived="" after=""
  tmp="$(mktemp -d 2>/dev/null)" || { echo "$G unrun — no temp dir"; return 0; }
  : > "$tmp/body"
  if [ -n "$pr" ] && view="$("$LANES_GH" pr view "$pr" --json body 2>/dev/null)" && jq -e 'type == "object" and (.body | type == "string")' >/dev/null 2>&1 <<<"$view"; then
    gh_ok=1; jq -r '.body' <<<"$view" > "$tmp/body"
  fi
  rows="$(_lanes_validation_rows "$itemf" "$tmp/body" "$gh_ok" "$pr")"
  after="$(_lanes_vg_after_pick "$rf" "$item")" || after=""
  rm -rf "$tmp"
  while IFS="$tab" read -r n title kind st ev; do
    [ "$kind" = running-system ] || continue
    k=$((k + 1))
    [ "$st" = PASS ] && continue
    if [ -n "$after" ] && _lanes_vg_has "$after" "validation waived: ${item#./} V$n $title — owner: \""; then
      waived="$waived${waived:+; }V$n $title"; continue
    fi
    echo "$G unrun — V$n $title: $ev"; return 0
  done <<EOF
$rows
EOF
  # Fail CLOSED: the pre-check saw a running-system step, so zero rows here is a reader failure, never `ok`.
  if [ "$k" = 0 ]; then echo "$G unrun — the Validation reader returned no running-system row for $item"; return 0; fi
  if [ -n "$waived" ]; then echo "$G waived — $waived"; return 0; fi
  echo "$G ok — $k running-system step(s) evidenced"
  return 0
}

# ==================================================================================================
# WAVE CLOSE (parallel-automate/21 Part A). Nothing in THIS file merges or pushes anything:
# `wave-plan` only PRINTS the integration commands, and `fleet-closeout` closes a wave out AFTER the
# owner merged the wave PR, through the existing sanctioned paths (lane-convert-ready, queue-checkoff,
# lane-remove, run-lock.sh release). The ONE writer of a wave branch is the sibling automate-wave.sh
# (`wave-build`, owner decision 2026-10-11): it sources this file for _lanes_wave_resolve, so it builds
# exactly the plan `wave-plan` prints, pushes only the wave branch and opens the wave PR; merging that
# PR stays the owner's.

# _lanes_base_of <checkout> — the base branch (origin/HEAD's name; `main` when unset).
_lanes_base_of() {
  local b; b="$(git -C "$1" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"; b="${b#origin/}"
  printf '%s' "${b:-main}"
}

# _lanes_rf_done <runfile> — 0 when the run file's `## Status:` line reads done.
_lanes_rf_done() { grep -qE '^## Status:[[:space:]]*done([^A-Za-z0-9_]|$)' "${1:-/dev/null}" 2>/dev/null; }

# _lanes_sync_primary <primary> — `git pull --ff-only` of the primary on its base branch; prints
# `pulled <base>` or `skipped — <reason>`. The refusal set mirrors automate-trail.sh's `_sync_primary`
# (closeout's step-4 sync): detached HEAD, another branch, tracked modifications, a failed fetch,
# already synced, a refused pull — never a reset, a stash, a checkout or a commit.
_lanes_sync_primary() {
  local p="$1" base cur st
  base="$(_lanes_base_of "$p")"
  cur="$(git -C "$p" symbolic-ref -q --short HEAD 2>/dev/null)"
  if [ -z "$cur" ]; then echo "skipped — primary checkout is on a detached HEAD"; return 0; fi
  if [ "$cur" != "$base" ]; then echo "skipped — primary checkout is on $cur, not $base"; return 0; fi
  if ! st="$(git -C "$p" status --porcelain --untracked-files=no 2>/dev/null)"; then echo "skipped — git status unreadable"; return 0; fi
  if [ -n "$st" ]; then echo "skipped — uncommitted tracked changes ($(printf '%s\n' "$st" | cut -c4- | head -3 | paste -sd ',' - | sed 's/,/, /g'))"; return 0; fi
  if ! git -C "$p" fetch -q origin >/dev/null 2>&1; then echo "skipped — git fetch failed"; return 0; fi
  if [ "$(git -C "$p" rev-parse -q --verify HEAD 2>/dev/null)" = "$(git -C "$p" rev-parse -q --verify "refs/remotes/origin/$base" 2>/dev/null)" ]; then
    echo "skipped — already synced ($base at origin/$base)"; return 0
  fi
  if ! git -C "$p" pull -q --ff-only origin "$base" >/dev/null 2>&1; then echo "skipped — git pull --ff-only refused (no reset attempted)"; return 0; fi
  echo "pulled $base"
}

# _lanes_append_once <runfile> <line> — progress-append unless that exact `- <line>` is already there
# (fleet-closeout re-runs on every --resume; its wave-level lines are recorded once). Fail-SAFE.
_lanes_append_once() {
  grep -qxF -- "- $2" "$1" 2>/dev/null && return 0
  bash "$HELPERS" progress-append "$1" "$2" >/dev/null 2>&1 || return 1
}

# _lanes_fc_finalize <parent_runfile> <primary> <meta branch, empty = mode off> — fleet-closeout's last
# write, run only once the parent `## Queue` has no `- [ ]` left and only while the wave lock is still
# held (the caller releases it right after, whatever this printed). It finalizes the parent exactly as
# the sequential loop's §6 "Termination" does, through the existing helpers (never a hand write):
# ONE validated `runfile-write` of a staged copy on which `current-wave --wave null` cleared the
# `- wave:` line, the first `## Status:` line became `## Status: done` and `current-set --pause-reason
# null` authored `pause_reason: null` (finalize-empty's staging — a failure at any step leaves the run
# file byte-unchanged); then `<ts> wave closed — Queue empty, run finalized`; then `trail-pr <rf>
# --reason done` (through the TRAIL seam, with this script's meta-sync, in the primary) printed and
# appended like finalize-empty's; then, branch mode OFF only, `trail-unstage <rf>`. Lines:
# `fleet-closeout: finalize — <outcome>` (one per step) | `fleet-closeout: finalize — skipped (already
# done)` (nothing written: a re-run never repeats the trail) | `fleet-closeout: finalize FAILED —
# <reason>` (nothing written — a refused write, or the run lock held by an owner other than
# `automate-lanes:<run_id>`; a FREE lock is taken first, so the write is always under it). Returns 0.
_lanes_fc_finalize() {
  local rf="$1" primary="$2" mb="$3" tmp out ts l F="fleet-closeout: finalize FAILED —"
  if _lanes_rf_done "$rf"; then echo "fleet-closeout: finalize — skipped (already done)"; return 0; fi
  if grep -q '^- \[ \] ' "$rf" 2>/dev/null; then echo "fleet-closeout: finalize — skipped (Queue items remain)"; return 0; fi
  grep -q '^## Status:' "$rf" 2>/dev/null || { echo "$F the parent run file has no ## Status: line"; return 0; }
  # The write happens under the wave lock: held by this wave ⇒ go; free (a FAILED finalize's call already
  # released it) ⇒ take it, the caller's release drops it; held by anyone else ⇒ nothing written.
  local lk_st lk_own="automate-lanes:${rf##*/}"; lk_own="${lk_own%.md}"
  lk_st="$(bash "$RUN_LOCK" status --root "$primary" 2>/dev/null </dev/null | head -1)"
  case "$lk_st" in
    "LOCKED owner=$lk_own "*) ;;
    UNLOCKED)
      out="$(bash "$RUN_LOCK" acquire --owner "$lk_own" --root "$primary" 2>&1 </dev/null)" \
        || { echo "$F the wave lock could not be taken — $(printf '%s\n' "$out" | head -1) (nothing written)"; return 0; } ;;
    LOCKED*) l="${lk_st#LOCKED owner=}"; echo "$F the run lock is held by ${l%% *}, not $lk_own (nothing written)"; return 0 ;;
    *) echo "$F run lock status unreadable (nothing written)"; return 0 ;;
  esac
  tmp="$(mktemp "$rf.fc.XXXXXX" 2>/dev/null)" || { echo "$F cannot stage the rewrite"; return 0; }
  if ! awk '!st && /^## Status:/ { print "## Status: done"; st = 1; next } { print }' "$rf" > "$tmp" 2>/dev/null; then
    rm -f "$tmp"; echo "$F cannot stage the rewrite"; return 0
  fi
  if ! out="$(bash "$HELPERS" current-wave "$tmp" --wave null 2>&1 </dev/null)" \
     || ! out="$(bash "$HELPERS" current-set "$tmp" --pause-reason null 2>&1 </dev/null)" \
     || ! out="$(bash "$HELPERS" runfile-write "$rf" < "$tmp" 2>&1)"; then
    rm -f "$tmp" "$tmp".*
    echo "$F $(printf '%s\n' "$out" | sed '/^$/d' | head -1 | cut -c1-200) (the run file is unchanged)"; return 0
  fi
  rm -f "$tmp"
  ts="$(now_utc)"
  bash "$HELPERS" progress-append "$rf" "$ts wave closed — Queue empty, run finalized" >/dev/null 2>&1 \
    || echo "fleet-closeout: WARNING — the finalize ## Progress line could not be appended" >&2
  echo "fleet-closeout: finalize — finalized (## Status: done, pause_reason: null, wave line cleared)"
  l="$(cd "$primary" && LOOMWRIGHT_META_SYNC_BIN="$META_SYNC" bash "$TRAIL" trail-pr "$rf" --reason done 2>/dev/null </dev/null | tail -n1)"
  l="${l:-trail-pr: skipped — no output}"
  echo "fleet-closeout: finalize — $l"
  bash "$HELPERS" progress-append "$rf" "$ts $l" >/dev/null 2>&1
  if [ -z "$mb" ]; then
    l="$(cd "$primary" && bash "$TRAIL" trail-unstage "$rf" 2>/dev/null </dev/null | tail -n1)"
    echo "fleet-closeout: finalize — ${l:-trail-unstage: skipped — no output}"
  fi
  return 0
}

# fleet-closeout <parent_runfile> — the wave close, run in the coordinator's PRIMARY checkout on every
# `/automate --resume` (stepwise, idempotent: each call does every step it can; nothing waits in-session).
# One `fleet-closeout: <step> — <detail>` line per lane and per step, in order:
#   1. pull        branch mode: `meta-sync.sh pull --branch <mode branch>`; failure (or mode unknown) ⇒
#                  `fleet-closeout: pull FAILED — <reason>`, exit 2, nothing else runs. Mode off: skipped.
#   2. per lane    (lane-status): already `## Status: done` ⇒ closed out. A `.meta-push-failed` marker ⇒
#                  `human — <lane> meta-push-failed: <reason>`. `merged` (or closeout's `awaiting_go`)
#                  with no live lane process and no live merge watcher ⇒ BACKSTOP: `lane-convert-ready
#                  <lane_dir>` — the existing sanctioned coordinator→lane closeout path (closeout
#                  --no-trail + A1 finalize + pushes), run again once when that call only converted a
#                  ready_for_release lane. `gone` ⇒ `human — <lane> gone (PR closed unmerged): lane-remove
#                  <lane_dir> --abandon` (never auto-abandoned). Anything else ⇒ `waiting — <lane> <state>`.
#   3. check-off   each closed-out lane whose item is still `- [ ]` in the parent `## Queue`:
#                  `queue-checkoff <parent_runfile> <item>` + `fleet closeout: <lane> <item> done (PR <url>)`.
#   4. sync        `git pull --ff-only` of the primary (_lanes_sync_primary's refusals are `skipped — …`).
#   5. remove      single-lane parent (`## Run Config` `- parallel: 1`) only, first: `fleet closeout: <lane>
#                  tokens TOTAL=<n|unknown>` appended once per lane (`fleet-closeout: tokens — <lane> TOTAL=<n>`);
#                  then `lane-remove <lane_dir>` per closed-out lane (no --stop: a live watcher or process
#                  refuses — `waiting — <lane> <refusal>`, re-checked on the next call). An unpushed-
#                  metadata refusal names its paths (`… (local_ahead <n>) — paths: <p>, …`).
#   6. wave end    only once EVERY lane reads removed/abandoned: `rmdir <primary>-lanes/<run_id>/` when
#                  empty, else `kept <dir> — contents: <names>`; `lane-status --leaks` (its first line
#                  appended as `fleet closeout leaks: <line>`, the primary's path written `<primary>`);
#                  `sweep: unavailable (automate-followups/22 not shipped)`; main health — the `ci` check of
#                  origin/<base> HEAD via gh: `failure` ⇒ `wave_paused: main_red after <sha>` appended and
#                  printed (no revert, no block); then, when the parent Queue has no `- [ ]` left,
#                  the parent FINALIZE under the still-held wave lock (_lanes_fc_finalize: `current-wave
#                  --wave null` + `## Status: done` + `pause_reason: null` in ONE validated runfile-write,
#                  `<ts> wave closed — Queue empty, run finalized`, `trail-pr --reason done`, branch mode
#                  off `trail-unstage`; `finalize — skipped (already done)` on a re-run, nothing written;
#                  `finalize FAILED — <reason>`, nothing written, exit unchanged), then — on every finalize
#                  outcome — `run-lock.sh release --owner "automate-lanes:<run_id>"` ⇒ `wave closed — lock
#                  released`. A Queue item left (the next wave) ⇒ no finalize, `lock kept — …`.
# Exit: 0 (done, or waiting — the lines say which) · 1 refused (bad parent run file) · 2 pull failed.
lanes_fleet_closeout() {
  local rf="${1:-}"
  [ -n "$rf" ] && [ "$#" -le 1 ] || die "usage: fleet-closeout <parent_runfile>"
  _lanes_parent_of "$rf" || { echo "fleet-closeout: refused — $LP_WHY"; return 1; }
  local parent="$LP_PARENT" primary="$LP_PRIMARY" table mb out rc tab doc closed="" n
  local lane path item run state lrf mk w pid st lpr detail single=0 tk
  tab="$(printf '\t')"
  rf="$primary/.supervisor/automate/$parent.md"; table="$primary/.supervisor/automate/$parent.lanes"
  _lanes_single_parent "$rf" && single=1   # `- parallel: 1` ⇒ the per-lane tokens line (step 5)
  _fc() { echo "fleet-closeout: $*"; }
  [ -f "$table" ] || { _fc "skipped — no lane table ($parent.lanes): no lane to close out"; return 0; }
  # 1. pull
  if ! mb="$(_lanes_meta_branch "$primary")"; then _fc "pull FAILED — metadata mode unknown"; return 2; fi
  if [ -n "$mb" ]; then
    out="$(bash "$META_SYNC" pull --branch "$mb" --root "$primary" 2>&1 </dev/null)"; rc=$?
    if [ "$rc" != 0 ]; then
      _fc "pull FAILED — $(printf '%s\n' "$out" | sed '/^$/d' | head -1 | cut -c1-200)${out:+ }(meta-sync exit $rc)"; return 2
    fi
    _fc "pull — pulled $mb"
  else _fc "pull — skipped (metadata mode off)"; fi
  # 2. per lane
  doc="$(_lanes_status_doc "$table" "$parent" "$primary")"
  while IFS="$tab" read -r lane path item run state; do
    [ -n "$lane" ] || continue
    lrf="$path/.supervisor/automate/$run.md"; mk="$path/.supervisor/automate/$run.meta-push-failed"
    case "$state" in removed|abandoned) _fc "lane — $lane $state"; continue ;; esac
    if [ -f "$mk" ]; then _fc "human — $lane meta-push-failed: $(head -1 "$mk" 2>/dev/null | cut -c1-200)"; continue; fi
    if _lanes_rf_done "$lrf"; then
      _fc "lane — $lane closed out (## Status: done)"; closed="$closed$lane$tab$path$tab$item$tab$run
"; continue
    fi
    case "$state" in
      merged|awaiting_go|done)
        pid="$(_lt_get "$table" "$lane" 5)"; st="$(_lt_get "$table" "$lane" 6)"
        if lanes_proc_alive "$pid" "$st" "$path"; then _fc "waiting — $lane live lane process (pid $pid)"; continue; fi
        w="$(_lanes_live_watchers "$path" | head -1)"
        if [ -n "$w" ]; then _fc "waiting — $lane live merge watcher (pid ${w%%"$tab"*})"; continue; fi
        out="$(bash "$SELF" lane-convert-ready "$path" 2>&1 </dev/null)"; rc=$?
        case "$(printf '%s\n' "$out" | tail -1)" in
          "lane-convert-ready: converted $lane to awaiting_merge"*)   # a ready_for_release lane: the merged re-run follows
            out="$(bash "$SELF" lane-convert-ready "$path" 2>&1 </dev/null)"; rc=$? ;;
        esac
        detail="$(printf '%s\n' "$out" | grep -E '^lane-convert-ready: (finalize|refused|FAILED)' | head -1)"
        [ -n "$detail" ] || detail="$(printf '%s\n' "$out" | grep '^lane-convert-ready: ' | tail -1)"
        if _lanes_rf_done "$lrf"; then
          _fc "backstop — $lane lane-convert-ready (exit $rc) — ${detail:-no output}; now ## Status: done"
          closed="$closed$lane$tab$path$tab$item$tab$run
"
        else
          case "$detail" in
            *"finalize skipped"*) _fc "human — $lane not finalized (exit $rc): $detail" ;;
            *) _fc "waiting — $lane backstop lane-convert-ready (exit $rc) — ${detail:-no output}" ;;
          esac
        fi ;;
      gone) _fc "human — $lane gone (PR closed unmerged): lane-remove $path --abandon" ;;
      *) _fc "waiting — $lane $state" ;;
    esac
  done <<EOF
$(jq -r '.lanes[] | [.lane, .path, .item, .run_id, .state] | @tsv' <<<"$doc" 2>/dev/null)
EOF
  # 3. parent check-off
  while IFS="$tab" read -r lane path item run; do
    [ -n "$lane" ] || continue
    if ! grep -qxF -- "- [ ] $item" "$rf" 2>/dev/null; then _fc "check-off — $lane $item already checked off"; continue; fi
    lpr="$(_lanes_dash "$(_lanes_runfile_fields "$path/.supervisor/automate/$run.md" | cut -f3)")"
    if out="$(bash "$HELPERS" queue-checkoff "$rf" "$item" 2>&1 </dev/null)" && ! grep -qxF -- "- [ ] $item" "$rf" 2>/dev/null; then
      bash "$HELPERS" progress-append "$rf" "fleet closeout: $lane $item done (PR ${lpr:-none recorded})" >/dev/null 2>&1 \
        || echo "fleet-closeout: WARNING — the ## Progress line for $lane could not be appended" >&2
      _fc "check-off — $lane $item"
    else
      _fc "check-off FAILED — $lane $item: $(printf '%s\n' "$out" | head -1)"
    fi
  done <<EOF
$closed
EOF
  # 4. primary sync
  _fc "sync — $(_lanes_sync_primary "$primary")"
  # 5. lane removal (closed-out lanes only; a refusal waits for the next call — never --stop, never a wait)
  while IFS="$tab" read -r lane path item run; do
    [ -n "$lane" ] || continue
    if [ "$single" = 1 ]; then   # BEFORE the removal: the TOTAL is read from the lane directory
      tk="$(_lanes_tokens_record "$rf" "$lane" "$path" "$run")"; [ -z "$tk" ] || _fc "tokens — $tk"
    fi
    out="$(bash "$SELF" lane-remove "$path" 2>&1 </dev/null)"; rc=$?
    if [ "$rc" = 0 ]; then _fc "remove — $lane removed (salvage kept under <primary>-lanes/$parent/salvage/)"
    else
      detail="$(printf '%s\n' "$out" | sed -n "s/^lane-remove: refused — $lane — //p" | head -1)"
      _fc "waiting — $lane ${detail:-$(printf '%s\n' "$out" | head -1)}"
    fi
  done <<EOF
$closed
EOF
  # 6. wave end — only once every lane of the table is removed / abandoned
  local left; left="$(awk -F'\t' '$1 ~ /^L[0-9][0-9]?$/ && $8 != "removed" && $8 != "abandoned" { printf "%s%s", (n++ ? ", " : ""), $1 }' "$table")"
  if [ -n "$left" ]; then _fc "waiting — lane(s) not removed yet: $left (re-run fleet-closeout on the next --resume)"; return 0; fi
  local ld="$primary-lanes/$parent" lk base sha cj concl line
  if [ ! -d "$ld" ]; then _fc "lanes-dir — already gone"
  elif rmdir "$ld" 2>/dev/null; then _fc "lanes-dir — removed (empty) $ld"
  else _fc "lanes-dir — kept $ld — contents: $(ls -1A "$ld" 2>/dev/null | paste -sd ',' - | sed 's/,/, /g')"; fi
  lk="$(bash "$SELF" lane-status "$rf" --leaks 2>/dev/null </dev/null | head -1)"
  lk="${lk:-leaks: unknown — lane-status --leaks printed nothing}"
  case "$lk" in *"$primary"*) lk="$(printf '%s' "$lk" | awk -v p="$primary" '{ while ((i = index($0, p)) > 0) $0 = substr($0, 1, i - 1) "<primary>" substr($0, i + length(p)); print }')" ;; esac
  _lanes_append_once "$rf" "fleet closeout leaks: $lk" || echo "fleet-closeout: WARNING — the leaks line could not be appended" >&2
  _fc "leaks — $lk"
  _fc "sweep: unavailable (automate-followups/22 not shipped)"
  base="$(_lanes_base_of "$primary")"
  sha="$(git -C "$primary" rev-parse -q --verify "refs/remotes/origin/$base" 2>/dev/null)"
  if [ -z "$sha" ]; then _fc "main health — unknown (origin/$base unreadable)"
  else
    cj="$(cd "$primary" && "$LANES_GH" api "repos/{owner}/{repo}/commits/$sha/check-runs?check_name=ci" 2>/dev/null </dev/null)" || cj=""
    concl="$(jq -r '[.check_runs[]? | select(.name == "ci")] | sort_by(.started_at // "") | last
      | if . == null then "none" else (.conclusion // "pending") end' <<<"$cj" 2>/dev/null)"
    case "$concl" in
      failure)
        line="wave_paused: main_red after $sha"
        _lanes_append_once "$rf" "$line" || echo "fleet-closeout: WARNING — the main_red line could not be appended" >&2
        _fc "$line" ;;
      "") _fc "main health — unknown (ci check of origin/$base ${sha:0:12} unreadable)" ;;
      *) _fc "main health — ci $concl on origin/$base ${sha:0:12}" ;;
    esac
  fi
  n="$(grep -c '^- \[ \] ' "$rf" 2>/dev/null)"; n="${n:-0}"
  if [ "$n" != 0 ]; then _fc "lock kept — $n Queue item(s) remain unchecked (the next wave runs under it)"; return 0; fi
  # The Queue is empty: finalize the parent UNDER the wave lock, then release it on EVERY outcome —
  # a refused finalize prints its FAILED line and never strands the lock.
  _lanes_fc_finalize "$rf" "$primary" "$mb"
  if out="$(bash "$RUN_LOCK" release --owner "automate-lanes:$parent" --root "$primary" 2>&1 </dev/null)"; then
    _fc "wave closed — lock released"
  else
    _fc "lock release FAILED — $(printf '%s\n' "$out" | head -1)"
  fi
  return 0
}

# _lanes_wave_resolve <parent_runfile> [<wave branch>] — the ONE wave resolver. `wave-plan` (below) and
# automate-wave.sh's `wave-build` (which sources this file) both read the wave through it, so the
# printed plan and the executed build can never disagree on the lanes, their order, the head shas, the
# base or the branch name. READ-ONLY: it reads the lane table, the parent `## Current` wave line
# (`- wave: <k> | items: …`; absent ⇒ the lane table order, wave 1), each lane's `## Current` pr and
# that PR's head + state (ONE `gh pr view <pr> --json headRefOid,state` read per lane). Sets WV_PARENT,
# WV_PRIMARY, WV_RF, WV_TABLE, WV_BASE, WV_K, WV_WB (default `wave/<run_id>-w<k>`), WV_SRC and WV_ROWS —
# one TSV row per wave entry, in planner order: <kind> <lane> <path> <item> <run_id> <pr> <num> <sha>
# <pr_state>, every empty field `-`. kind: `ok` · `nolane` (a wave item with no lane-table row) · `nopr`
# (no numeric PR in the lane's run file) · `nohead` (the head sha unreadable). Returns 1 with WV_WHY
# when it refuses (bad parent run file, no lane table, bad branch name).
_lanes_wave_resolve() {
  local rf="${1:-}" wb="${2:-}" wl items item v rows="" tab lane path run pr num j sha st
  WV_WHY=""; WV_ROWS=""; WV_SRC=""
  _lanes_parent_of "$rf" || { WV_WHY="$LP_WHY"; return 1; }
  WV_PARENT="$LP_PARENT"; WV_PRIMARY="$LP_PRIMARY"
  WV_RF="$WV_PRIMARY/.supervisor/automate/$WV_PARENT.md"; WV_TABLE="$WV_PRIMARY/.supervisor/automate/$WV_PARENT.lanes"
  tab="$(printf '\t')"
  [ -f "$WV_TABLE" ] || { WV_WHY="no lane table ($WV_PARENT.lanes)"; return 1; }
  WV_BASE="$(_lanes_base_of "$WV_PRIMARY")"
  wl="$(awk '/^## / { sec = $0; next } sec == "## Current" && /^- wave: / { print; exit }' "$WV_RF" 2>/dev/null)"
  WV_K="$(printf '%s' "$wl" | sed -n 's/^- wave: *\([0-9][0-9]*\) *|.*/\1/p; s/^- wave: *\([0-9][0-9]*\) *$/\1/p' | head -1)"
  items="$(printf '%s' "$wl" | sed -n 's/^- wave: [^|]*| *items: *//p' \
    | awk '{ n = split($0, a, /, */); for (i = 1; i <= n; i++) { sub(/ +$/, "", a[i]); if (a[i] != "") print a[i] } }')"
  [ -n "$WV_K" ] || WV_K=1
  [ -n "$wb" ] || wb="wave/$WV_PARENT-w$WV_K"
  git check-ref-format --branch "$wb" >/dev/null 2>&1 || { WV_WHY="'$wb' is not a valid branch name"; return 1; }
  WV_WB="$wb"
  if [ -n "$items" ]; then
    WV_SRC="from ## Current"
    while IFS= read -r item; do
      [ -n "$item" ] || continue
      v="$(awk -F'\t' -v i="$item" '$1 ~ /^L[0-9][0-9]?$/ && $3 == i { r = $1 "\t" $2 "\t" $3 "\t" $4 } END { if (r != "") print r }' "$WV_TABLE")"
      if [ -n "$v" ]; then rows="$rows$v
"; else rows="$rows-$tab-$tab$item$tab-
"; fi
    done <<<"$items"
  else
    WV_SRC="no ## Current wave items — lane table order"
    rows="$(awk -F'\t' '$1 ~ /^L[0-9][0-9]?$/ { print $1 "\t" $2 "\t" $3 "\t" $4 }' "$WV_TABLE")"
  fi
  while IFS="$tab" read -r lane path item run; do
    [ -n "$lane$item" ] || continue
    if [ "$lane" = - ]; then WV_ROWS="${WV_ROWS}nolane$tab-$tab-$tab$item$tab-$tab-$tab-$tab-$tab-
"; continue; fi
    pr="$(_lanes_dash "$(_lanes_runfile_fields "$path/.supervisor/automate/$run.md" | cut -f3)")"
    num="${pr##*/}"
    case "$num" in ''|*[!0-9]*)
      WV_ROWS="${WV_ROWS}nopr$tab$lane$tab$path$tab$item$tab$run$tab${pr:--}$tab-$tab-$tab-
"; continue ;;
    esac
    j="$("$LANES_GH" pr view "$pr" --json headRefOid,state 2>/dev/null </dev/null)"
    sha="$(jq -r '.headRefOid // empty' <<<"$j" 2>/dev/null)"; st="$(jq -r '.state // empty' <<<"$j" 2>/dev/null)"
    case "$sha" in [0-9a-f]*) ;; *) sha="" ;; esac
    if [ "${#sha}" != 40 ] || [ -n "$(printf '%s' "$sha" | tr -d '0-9a-f')" ]; then
      WV_ROWS="${WV_ROWS}nohead$tab$lane$tab$path$tab$item$tab$run$tab$pr$tab$num$tab-$tab${st:--}
"; continue
    fi
    WV_ROWS="${WV_ROWS}ok$tab$lane$tab$path$tab$item$tab$run$tab$pr$tab$num$tab$sha$tab${st:--}
"
  done <<EOF
$rows
EOF
  return 0
}

# wave-plan <parent_runfile> [--wave-branch <name>] — Part S, READ-ONLY (owner decision 2026-10-10: the
# operator merges; since then `wave-build` in automate-wave.sh runs these same steps, and this stays the
# read-only preview and the manual fallback). Executes no git mutation, no push and no gh write: it
# resolves the wave with _lanes_wave_resolve (above — the lane table, the parent `## Current` wave line,
# each lane's `## Current` pr and that PR's head sha, a `gh pr view` read) and PRINTS the operator's
# commands: fetch, `git checkout -b <wave branch, default wave/<run_id>-w<k>> origin/<base>`, one
# `git merge --no-ff <exact head sha> -m "Merge lane <L> (<item>) PR #<n>"` per lane in planner order
# (an unreadable sha ⇒ `# <lane>: head unreadable — resolve before integrating`, that lane skipped),
# `bash scripts/ci-local.sh`, the release step (`bash scripts/bump-version.sh` only when the repo has
# it, else `# run this project's release step`), the push and `gh pr create`, then the conflict rules.
# Exit 0 printed · 1 refused (bad parent run file, no lane table, bad branch name).
lanes_wave_plan() {
  local rf="" wb=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --wave-branch) _lanes_need "$#" wave-plan "$1"; wb="$2"; shift 2 ;;
      -*) echo "wave-plan: refused — unknown flag '$1'"; return 1 ;;
      *) [ -z "$rf" ] || { echo "wave-plan: refused — unexpected argument '$1'"; return 1; }; rf="$1"; shift ;;
    esac
  done
  _lanes_wave_resolve "$rf" "$wb" || { echo "wave-plan: refused — $WV_WHY"; return 1; }
  local parent="$WV_PARENT" primary="$WV_PRIMARY" base="$WV_BASE" k="$WV_K" tab kind lane path item run pr num sha st msg
  wb="$WV_WB"; tab="$(printf '\t')"
  echo "# wave-plan: $parent wave $k ($WV_SRC) — READ-ONLY: nothing below was run; the operator runs it"
  echo "git fetch origin"
  echo "git checkout -b $wb origin/$base"
  while IFS="$tab" read -r kind lane path item run pr num sha st; do
    case "$kind" in
      nolane) echo "# $item: no lane in $parent.lanes — skipped" ;;
      nopr) echo "# $lane: no PR recorded in its run file — resolve before integrating" ;;
      nohead) echo "# $lane: head unreadable — resolve before integrating" ;;
      ok) msg="$(printf 'Merge lane %s (%s) PR #%s' "$lane" "$item" "$num" | sed 's/[\\"$`]/\\&/g')"
          printf 'git merge --no-ff %s -m "%s"\n' "$sha" "$msg" ;;
    esac
  done <<EOF
$WV_ROWS
EOF
  echo "bash scripts/ci-local.sh"
  if [ -f "$primary/scripts/bump-version.sh" ]; then echo "bash scripts/bump-version.sh"
  else echo "# run this project's release step"; fi
  echo "git push -u origin $wb"
  echo "gh pr create --base $base --head $wb"
  echo "# Conflict rules (Part S):"
  echo "#   - a marker-only conflict is resolved in the merge commit itself"
  echo "#   - anything larger stops the integration: hand it to the owner"
  echo "#   - never rewrite or push a lane branch"
  echo "#   - a lane broken on the wave branch is fixed on its own PR, and its new head is re-merged"
  return 0
}

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
