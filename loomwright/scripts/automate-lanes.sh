#!/usr/bin/env bash
# automate-lanes.sh — lane lifecycle for `/automate --parallel N` (parallel-automate/05).
#
# A LANE is a local clone of the primary checkout at `<primary>-lanes/<parent_run_id>/L<n>/` that runs
# the ordinary per-item `/automate` loop for ONE item, headless (`claude -p`), with a question channel
# (lane shape A + relay). One coordinator in the primary creates, launches and removes lanes through
# this script. Without `--parallel`, or with N = 1, nothing here is ever called.
#
# Usage (standalone: `bash automate-lanes.sh <subcmd> ...`):
#   lane-create <parent_runfile> <item> <n> [--parallel N] [--max-tokens T]
#        clone + origin-before-fetch + meta pull + carried configs + lane.json + one-line backlog + relay hooks
#   lane-launch <lane_dir> --owner-command '<cmd the owner typed>' [--resume-run <run_id> | --continue]
#        detached headless launch (or resume by run id — in the lane's LAST session, a fresh one only
#        when that cannot be resumed — / fixed decision-free continue message)
#   lane-launch <lane_dir> --host-denied '<reason>'      record a host-refused spawn as blocked_launch
#   relay-hook                                           PreToolUse / PermissionRequest hook (stdin: hook JSON)
#   lane-answer <lane_dir> <tool_use_id> --owner-command '<cmd>' [--via <client>]
#        stdin: {"answers":{"0":"<label>"},"note":"<optional free text>"}; validates, records, resumes
#        (HELD ⇒ the validated answer is kept coordinator-side, the lane reads answer_pending)
#   lane-answer <lane_dir> --deliver-pending --owner-command '<cmd>'   deliver a kept answer (the poll)
#   lane-remove <lane_dir> [--stop] [--abandon]          guarded removal (salvages first); --abandon on a
#        `gone` lane stamps ABANDONED and pushes the lane's metadata through trail-pr's evidence gate
#   lane-convert-ready <lane_dir>                        wave end: ready_for_release → awaiting_merge, then
#        push the lane's metadata (non-claim files by exact list + trail-pr's evidence-gated list); a
#        re-run once the PR merged first runs `closeout … --no-trail` inside the lane (the done stamp),
#        then, branch mode only, `finalize-empty` on the lane's run file (`## Status: done`)
#   fleet-closeout <parent_runfile>                      wave close, stepwise + idempotent (re-run on every
#        coordinator --resume): meta pull · per-lane backstop (lane-convert-ready on a merged lane) ·
#        parent Queue check-off · primary sync · lane-remove · lanes dir, leaks, main health, lock release
#   wave-plan <parent_runfile> [--wave-branch <name>]    READ-ONLY: prints the operator's wave-branch
#        integration commands (one `git merge --no-ff <head sha>` per lane) and the conflict rules
#   lane-info [--root <dir>]                             print .supervisor/lane.json (exit 1 when absent)
#   init-check --parallel N [--auto-merge]               INIT refusals: `ok` | `refuse: <reason>` (exit 1)
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
#   lane-park-notify <runfile>                           the ready_for_release park's ONE notify step: desktop +
#        `automate_ready_for_release` webhook (fail-SAFE) + one ## Progress line naming each channel's real outcome
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
#                                       the PRIMARY at lane-create (the rules stamp is per clone), or null.
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
#   4. Spawn: `claude -p` with the lane allowlist / disallow list below, `--plugin-dir` pinned to the
#      coordinator's CLAUDE_PLUGIN_ROOT, `--append-system-prompt` = the fixed headless-lane text, env
#      CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 with CLAUDE_PID / CLAUDECODE unset. Prompt:
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
# origin-before-fetch, remote branch-name hit) fail CLOSED; relay-hook outside a lane emits `{}`.
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
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$HERE/.." && pwd)}"
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
  local runfile="" item="" n="" par="" maxt="" a
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --parallel) _lanes_need "$#" lane-create "$1"; par="$2"; shift 2 ;;
      --max-tokens) _lanes_need "$#" lane-create "$1"; maxt="$2"; shift 2 ;;
      *) if [ -z "$runfile" ]; then runfile="$1"; elif [ -z "$item" ]; then item="$1"; elif [ -z "$n" ]; then n="$1"
         else die "lane-create: unexpected argument '$1'"; fi; shift ;;
    esac
  done
  [ -n "$runfile" ] && [ -n "$item" ] && [ -n "$n" ] || die "usage: lane-create <parent_runfile> <item> <n> [--parallel N] [--max-tokens T]"
  case "$n" in [1-9]|10) ;; *) die "lane-create: lane number must be 1..10 (got '$n')" ;; esac
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
  local mt=null; [ -n "$maxt" ] && mt=$((10#$maxt / par))
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
    '{schema_version: 1, lane: $lane, run_id: $run, parent_run_id: $parent, primary: $primary,
      parallel: $parallel, max_tokens: $mt, created: $created, policy: $policy}' > "$C/.supervisor/lane.json" \
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

# _lanes_gate <owner_cmd> — authority, liveness, regime, admission. Prints the first line; returns the exit code.
_lanes_gate() {
  local owner="$1" why
  if [ -z "$owner" ]; then
    echo "lane-launch: BLOCKED — $LN_LANE — no owner-invoked command — need the owner"
    _lt_set "$LN_TABLE" "$LN_LANE" 8 blocked_launch 10 "no owner-invoked command"; return 3
  fi
  if lanes_proc_alive "$(_lt_get "$LN_TABLE" "$LN_LANE" 5)" "$(_lt_get "$LN_TABLE" "$LN_LANE" 6)" "$LN_DIR"; then
    echo "lane-launch: refused — $LN_LANE — already running (pid $(_lt_get "$LN_TABLE" "$LN_LANE" 5))"; return 1
  fi
  if ! _lanes_regime_ok; then
    echo "lane-launch: BLOCKED — $LN_LANE — CLI advertises no pinnable permission regime — need the owner"
    _lt_set "$LN_TABLE" "$LN_LANE" 8 blocked_launch 10 "no pinnable permission regime"; return 3
  fi
  if ! why="$(_lanes_admission)"; then
    echo "lane-launch: HELD — $LN_LANE — $why"
    _lt_set "$LN_TABLE" "$LN_LANE" 8 held_for_load 10 "$why"; return 4
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
  in=/dev/null
  if [ -n "$prompt" ]; then
    in="$LN_ROOT/$LN_LANE.stdin.json"
    jq -n -c --arg c "$prompt" '{type: "user", message: {role: "user", content: $c}}' > "$in" || return 1
  fi
  touch "$LN_LOG"; rm -f "$LN_DIED"
  off="$(wc -c < "$LN_LOG" | tr -d ' ')"
  # >>> spawn (the only process start; it writes nothing into the lane directory)
  nohup bash "$SELF" _lane-run "$LN_DIR" "$LN_LOG" "$LN_DIED" "$in" -- \
    env -u CLAUDECODE -u CLAUDE_PID CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 \
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
  local rc; _lanes_gate "$owner"; rc=$?
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
# reads that lane awaiting_input again — never held_for_load.
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
  _lanes_gate "$owner"; rc=$?
  if [ "$rc" = 4 ]; then
    # HELD (admission): keep the VALIDATED answer coordinator-side — never the owner command.
    pf="$(_lanes_pending_file)"; case "$via" in *[!A-Za-z0-9_.-]*) via=cli ;; esac
    if jq -n -c --arg lane "$LN_LANE" --arg id "$id" --argjson a "$(jq -c '.answers' <<<"$in")" --arg note "$note" \
        --arg via "$via" --arg at "$(now_utc)" \
        '{schema_version: 1, lane: $lane, tool_use_id: $id, answers: $a, note: (if $note == "" then null else $note end), via: $via, held_at: $at}' \
        > "$pf.tmp.$$" 2>/dev/null && mv "$pf.tmp.$$" "$pf"; then
      echo "lane-answer: answer kept pending ($(basename "$pf")) — $LN_LANE reads answer_pending; the next /automate --resume poll delivers it (lane-answer <lane_dir> --deliver-pending --owner-command '<cmd>')"
    else
      rm -f "$pf.tmp.$$"; echo "lane-answer: answer NOT kept — cannot write $(basename "$pf"); re-send it at the next poll"
    fi
    _lanes_launch_unlock; return 4
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
  _lanes_gate "$owner"; rc=$?
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
    ms="$(bash "$META_SYNC" status --branch "$mb" --root "$LN_DIR" 2>/dev/null)" || { _refuse "metadata status unreadable"; return 1; }
    case "$ms" in local_ahead*|conflict*|*local_ahead*|*conflict*) _refuse "metadata not pushed ($ms)"; return 1 ;; esac
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
# plus its Orchestrator task plans (_lanes_task_plans). None of them is a done claim. Prints
# meta-sync's reason and returns 1 on failure.
_lanes_meta_extras() {
  local mb="$1" msg="$2" list f out rc=0
  list="$(mktemp "${TMPDIR:-/tmp}/lane-meta.XXXXXX" 2>/dev/null)" || { echo "could not stage the push list"; return 1; }
  { for f in "$LN_RUN.md" "$LN_RUN.merge-readiness.md" "$LN_RUN.dismissed-decisions"; do
      if [ -f "$LN_DIR/.supervisor/automate/$f" ]; then printf '%s\n' ".supervisor/automate/$f"; fi
    done
    _lanes_task_plans
  } > "$list" || { rm -f "$list"; echo "could not stage the push list"; return 1; }
  out="$(bash "$META_SYNC" push --branch "$mb" --root "$LN_DIR" --paths-from "$list" --message "$msg" 2>&1)" || rc=$?
  rm -f "$list"
  if [ "$rc" != 0 ]; then
    printf 'meta-sync exit %s\n%s' "$rc" "$out"; return 1
  fi
  return 0
}

# _lanes_task_plans — prints the lane's Orchestrator task plans, one repo-relative path per line: every
# regular file `.supervisor/requirements/<slug>-plan.md` (top level only — the one path the Orchestrator's
# file-fallback mode writes, agents/orchestrator.md §"Persistence Mode"). It sits on a meta-managed path,
# so before this list carried it neither of the wave end's pushes did (trail-pr's candidates are the run
# file, its sidecars, its Queue requirements and their briefs) and lane-remove refused the lane forever
# on `local_ahead` (operator-run 2026-10-10 Phase 0.2). Excluded, left to trail-pr's evidence gate: a
# path the lane run file's `## Queue` / `## Current` names (that is the item's requirement), and any
# file carrying a `## Status: done…` heading (a done claim). A plan the lane only pulled is unchanged,
# so meta-sync pushes nothing for it; a lane clone has exactly one run, so no other run's plan is here.
_lanes_task_plans() {
  local f p items nl tab
  nl="$(printf '\nx')"; nl="${nl%x}"; tab="$(printf '\t')"
  items="$(awk '/^## / { sec = $0; next }
    sec == "## Queue" && /^- \[[ xX]\] / { v = $0; sub(/^- \[[ xX]\] /, "", v); sub(/[[:space:]]+#.*$/, "", v); sub(/[[:space:]]+$/, "", v); sub(/^\.\//, "", v); print v }
    sec == "## Current" && /^- item:/ { v = $0; sub(/^- item: */, "", v); sub(/ *\|.*/, "", v); sub(/^\.\//, "", v); print v }' \
    "$LN_DIR/.supervisor/automate/$LN_RUN.md" 2>/dev/null)"
  for f in "$LN_DIR"/.supervisor/requirements/*-plan.md; do
    [ -f "$f" ] && [ ! -L "$f" ] || continue
    p=".supervisor/requirements/${f##*/}"
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
# merge-readiness report, its dismissed-decisions ledger, its task plans) and (2) everything else through trail-pr's
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
# _lanes_no_host_identity [NAME=VALUE ...] <cmd> [args...] — runs <cmd> (through env, so leading
# NAME=VALUE pairs apply) with the host's two runtime-identity variables unset. For a fresh run-lock
# acquire with no --session-id (lane-convert-ready's closeout and finalize-empty): like the merge
# watcher, or a crashed call's lock names the coordinator as holder and stays unreclaimable while it
# lives (automate-loop SKILL, "Why … are unset").
_lanes_no_host_identity() { env -u CLAUDE_PID -u CLAUDECODE "$@"; }
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
      if grep -qE '^## Status:[[:space:]]*done([^A-Za-z0-9_]|$)' "$rf" 2>/dev/null; then
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
        # A fresh run-lock acquire (no --session-id): host identity unset (_lanes_no_host_identity).
        co="$(cd "$LN_DIR" && _lanes_no_host_identity bash "$TRAIL" closeout "$rf" "$item" "$pr" --no-trail 2>/dev/null)"
        printf '%s\n' "$co" | sed '/^$/d; s/^/  /'
        cv="$(printf '%s\n' "$co" | bash "$HELPERS" closeout-classify --run "$LN_RUN" --item "${item#./}" --pr "$pr" 2>/dev/null)"
        if [ "$cv" = complete ]; then cs="; closeout complete"
        elif [ -z "$cv" ]; then cs="; closeout leftover: classify — closeout-classify printed nothing"
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
        # finalize-empty's run-lock acquire takes no --session-id either: same unset as closeout above.
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
  if [ "$n" -gt 1 ] && [ "$am" = 1 ]; then echo "refuse: auto_merge_with_parallel"; return 1; fi
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
    nx="$(jq -c --slurpfile Q "$q" --arg id "$id" --arg at "$at" --argjson w "$w" \
      '. + [{id: $id, asked_at: (if $at == "" then null else $at end), waiting_s: $w,
             question: (($Q[0].questions // [])[0].question // null)}]' <<<"$out" 2>/dev/null)" \
      || nx="$(jq -c --arg id "$id" '. + [{id: $id, asked_at: null, waiting_s: null, question: null}]' <<<"$out")"
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

_lanes_keep_awake_state() {
  if "${LOOMWRIGHT_LANES_PGREP:-pgrep}" -x caffeinate >/dev/null 2>&1; then printf 'held'; else printf 'not held'; fi
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
  [ "$(_lanes_keep_awake_state)" = held ] && { echo "keep-awake: already held"; return 0; }
  cp="$(_lanes_coordinator_pid)"
  nohup "$cf" -i -w "$cp" >/dev/null 2>&1 &
  hp=$!
  echo "keep-awake: started (opt-in --keep-awake) — $cf -i -w $cp (pid $hp); it ends with the coordinator"
}

# _lanes_machine_json — {state, load1, cpus, mem_pressure, keep_awake}; `unknown` when the reader is
# absent or unreadable (never an error).
_lanes_machine_json() {
  local cmd="${LOOMWRIGHT_MACHINE_LOAD_CMD:-$HERE/machine-load.sh}" j="" ka
  ka="$(_lanes_keep_awake_state)"
  [ -f "$cmd" ] && j="$(bash "$cmd" --json 2>/dev/null | jq -c 'select(type == "object")' 2>/dev/null | head -1)"
  [ -n "$j" ] || j='{}'
  jq -c --arg ka "$ka" '{state: ((.state // "unknown") | tostring), load1: (.load1 // "unknown"),
    cpus: (.cpus // "unknown"), mem_pressure: (.mem_pressure // "unknown"), keep_awake: $ka}' <<<"$j" 2>/dev/null \
    || printf '{"state":"unknown","load1":"unknown","cpus":"unknown","mem_pressure":"unknown","keep_awake":"%s"}' "$ka"
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
  local pdg; pdg="$(_lanes_policy_digest "$path/.supervisor/inbox")"
  jq -e 'type == "object" or . == null' >/dev/null 2>&1 <<<"$pdg" || pdg=null
  jq -n -c --arg lane "$lane" --arg path "$path" --arg item "$(_lanes_dash "$item")" --arg run "$run" --argjson pdg "$pdg" \
    --arg state "$state" --arg reason "$reason" --arg pid "$(_lanes_dash "$pid")" --arg sid "$(_lanes_dash "$sid")" \
    --arg llu "$(_lanes_dash "$llu")" --arg status "$(_lanes_dash "$status")" --arg pause "$(_lanes_dash "$pause")" \
    --arg pr "$(_lanes_dash "$pr")" --arg prs "$prs" --arg lp "$(_lanes_dash "$lp")" --arg lm "$lm" --arg la "$la" \
    --argjson qs "$qs" --argjson ci "$cij" --arg held "$held" --arg rdf "$rdf" --arg rds "$rds" --arg rdsum "$rdsum" \
    'def n: if . == "" then null else . end;
     {lane: $lane, path: $path, item: $item, run_id: $run, state: $state, reason: $reason, pid: ($pid | n),
      session_id: ($sid | n), last_launch_utc: ($llu | n), run_status: ($status | n), pause_reason: ($pause | n),
      pr: ($pr | n), pr_state: ($prs | n), last_progress: $lp, last_actions: ($la | split("\n") | map(select(. != ""))),
      last_message: $lm, questions: $qs, ci_slot: $ci, held_for_load: ($held | n),
      readiness: (if $rds == "" then null else {score: $rds, summary: $rdsum, file: $rdf} end), policy: $pdg}'
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
  printf '%s' "$lanes" | jq -s -c --arg parent "$parent" --arg primary "$primary" --arg at "$(now_utc)" --argjson m "$m" \
    --arg hint "$hint" --arg mp "$([ -e "$primary/.supervisor/automate/$parent.memory-pressure" ] && echo true || echo false)" \
    '{schema_version: 1, parent_run_id: $parent, primary: $primary, generated_at: $at, machine: $m,
      memory_pressure: ($mp == "true"), keep_awake_suggestion: (if $hint == "" then null else $hint end), lanes: .}'
}

_lanes_render() { # <status JSON> — the plain view
  jq -r '"lane-status: \(.parent_run_id) — \(.lanes | length) lane(s) — \(.generated_at)",
    (if all(.lanes[]; .policy == null) then "policy: none answered" else empty end),
    (.lanes[] | "\(.lane)  \(.state)\(if .reason != "" then " (" + .reason + ")" else "" end)  item=\(.item)  pr=\(.pr // "-")  path=\(.path)",
      (if .policy != null then "    policy: \(.policy.answered) answered by policy\(if .policy.answered > 1 and .policy.first_at != null then " since " + .policy.first_at else "" end) — last \(.policy.last_gate // "?") → \(.policy.last_label) \(.policy.last_at // "unknown")" else empty end),
      (if .last_progress != "" then "    progress: \(.last_progress)" else empty end),
      (if (.last_actions | length) > 0 then "    actions: \(.last_actions | join("; "))" else empty end),
      (.questions[] | "    question: \(.id) asked_at=\(.asked_at // "unknown") waiting_s=\(.waiting_s // "unknown") — \(.question // "")"),
      (if .ci_slot.state == "waiting" then "    ci-slot: waiting — position \(.ci_slot.position)"
       elif .ci_slot.state == "holding" then "    ci-slot: holding a slot" else empty end),
      (if .held_for_load != null then "    held for load: \(.held_for_load)" else empty end),
      (if .readiness != null then "    readiness: \(.readiness.summary)" else empty end),
      (if .last_message != "" then "    last: \(.last_message)" else empty end)),
    "machine: state=\(.machine.state) load1=\(.machine.load1) cpus=\(.machine.cpus) mem_pressure=\(.machine.mem_pressure)\(if .memory_pressure then " — memory_pressure: new launches held" else "" end)",
    "keep-awake: \(.machine.keep_awake)",
    (if .keep_awake_suggestion != null and .machine.keep_awake != "held"
     then "keep-awake suggestion (run it yourself): \(.keep_awake_suggestion) — a closed lid still sleeps" else empty end)' <<<"$1"
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

_lanes_leak_sections() { # <primary> <parent>
  local p="$1" pg="${LOOMWRIGHT_LANES_PGREP:-pgrep}"
  echo "## worktrees"; git -C "$p" worktree list --porcelain 2>/dev/null | awk '/^worktree /'
  echo "## lanes-dir"; _lanes_leak_lanes_dir "$p" "${2:-}"
  echo "## claude-p"; "$pg" -lf 'claude -p' 2>/dev/null
  echo "## merge-watch"; "$pg" -lf automate-merge-watch 2>/dev/null
  echo "## config-checksum"
  if [ -f "$p/.supervisor/config.json" ]; then cksum < "$p/.supervisor/config.json" | awk '{ print $1, $2 }'; else echo absent; fi
  echo "## git-status"; git -C "$p" status --porcelain 2>/dev/null | awk '!/\.leaks-snapshot$/'
  return 0
}

# lanes_leaks <primary> <parent> [snapshot 0|1] — `--snapshot` records the wave-start state; otherwise
# compares now against it. First line: `leaks: none` | `leaks: found — <sections>` | `leaks: unknown — …`.
lanes_leaks() {
  local p="$1" parent="$2" snap="${3:-0}" sf tmp sec found="" body="" d
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
    awk -v s="## $sec" '/^## / { on = ($0 == s); next } on' "$sf" | env LC_ALL=C sort > "$tmp/a"
    awk -v s="## $sec" '/^## / { on = ($0 == s); next } on' "$tmp/now" | env LC_ALL=C sort > "$tmp/b"
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
  if [ -z "$found" ]; then echo "leaks: none (vs snapshot $sf)"; else echo "leaks: found — $found"; fi
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
      case "$ts" in *ready_for_release*|*awaiting_merge*) lanes_readiness "$path" >/dev/null ;; esac
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
# Called by the lane at its ready_for_release park; re-written on demand (`lane-status --refresh-readiness`).
_lanes_rd_section() { # <n> <title> <body_file> — the PR body's lines for Validation entry n
  awk -v n="$1" -v t="$2" '
    BEGIN { t = tolower(t) }
    { l = tolower($0) }
    on && (l ~ /^#/ || (l ~ /validation[ #]*[0-9]/ && l !~ ("validation[ #]*" n "([^0-9]|$)"))) { on = 0 }
    !on && (l ~ ("validation[ #]*" n "([^0-9]|$)") || (t != "" && index(l, t) > 0)) { on = 1 }
    on { print }' "$3"
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
  # ---- a + e: Validation entries
  local vrows="" erows="" n title sec st ev rs=0 vworst=PASS eworst=PASS vlabel="" isrepro
  awk '/^## /{ on = ($0 ~ /^## Validation/); next } on && /^[0-9]+\. / {
         n = $0; sub(/\..*/, "", n); t = $0
         if (match(t, /\*\*[^*]+\*\*/)) t = substr(t, RSTART + 2, RLENGTH - 4); else { sub(/^[0-9]+\. */, "", t); t = substr(t, 1, 60) }
         sub(/:$/, "", t); full = $0; gsub(/\t/, " ", full); print n "\t" t "\t" full }' "$itemf" 2>/dev/null > "$tmp/val"
  while IFS="$(printf '\t')" read -r n title full; do
    [ -n "$n" ] || continue
    isrepro=0; case "$(printf '%s %s' "$title" "$full" | tr '[:upper:]' '[:lower:]')" in *mutation*|*"must catch"*|*repro*|*"must fail"*) isrepro=1 ;; esac
    if [ "$gh_ok" = 0 ]; then st=NOT-RUN; ev="PR body unreadable${pr:+ ($pr)}${pr:-: no PR recorded}"
    else
      sec="$(_lanes_rd_section "$n" "$title" "$tmp/body")"
      if [ -z "$sec" ]; then st=NOT-RUN; ev="no evidence in the PR body"
      elif ! grep -q '```' <<<"$sec"; then st=NOT-RUN; ev="mentioned in the PR body without pasted output"
      elif [ "$isrepro" = 0 ] && grep -qw 'FAIL' <<<"$sec"; then st=FAIL; ev="pasted output shows FAIL"
      else st=PASS; ev="pasted output in the PR body"; fi
    fi
    if [ "$isrepro" = 1 ]; then
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
    fworst=NOT-RUN; fline="scope-fence: NOT-RUN — gh pr diff unreadable${pr:+ ($pr)}${pr:-: no PR recorded}"
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
  - children-settled: PASS — $(grep -iE 'children[-_ ]settled' "$rf" | tail -1 | sed 's/^- //' | cut -c1-160)"
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
# WAVE CLOSE (parallel-automate/21 Part A). Owner decision 2026-10-10: the OPERATOR runs the wave-branch
# merges. Nothing here merges or pushes a lane branch: `wave-plan` only PRINTS the commands, and
# `fleet-closeout` closes a wave out AFTER the owner merged, through the existing sanctioned paths
# (lane-convert-ready, queue-checkoff, lane-remove, run-lock.sh release).

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
#   5. remove      `lane-remove <lane_dir>` per closed-out lane (no --stop: a live watcher or process
#                  refuses — `waiting — <lane> <refusal>`, re-checked on the next call).
#   6. wave end    only once EVERY lane reads removed/abandoned: `rmdir <primary>-lanes/<run_id>/` when
#                  empty, else `kept <dir> — contents: <names>`; `lane-status --leaks` (its first line
#                  appended as `fleet closeout leaks: <line>`, the primary's path written `<primary>`);
#                  `sweep: unavailable (automate-followups/22 not shipped)`; main health — the `ci` check of
#                  origin/<base> HEAD via gh: `failure` ⇒ `wave_paused: main_red after <sha>` appended and
#                  printed (no revert, no block); then, when the parent Queue has no `- [ ]` left,
#                  `run-lock.sh release --owner "automate-lanes:<run_id>"` ⇒ `wave closed — lock released`.
# Exit: 0 (done, or waiting — the lines say which) · 1 refused (bad parent run file) · 2 pull failed.
lanes_fleet_closeout() {
  local rf="${1:-}"
  [ -n "$rf" ] && [ "$#" -le 1 ] || die "usage: fleet-closeout <parent_runfile>"
  _lanes_parent_of "$rf" || { echo "fleet-closeout: refused — $LP_WHY"; return 1; }
  local parent="$LP_PARENT" primary="$LP_PRIMARY" table mb out rc tab doc closed="" n
  local lane path item run state lrf mk w pid st lpr detail
  tab="$(printf '\t')"
  rf="$primary/.supervisor/automate/$parent.md"; table="$primary/.supervisor/automate/$parent.lanes"
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
  if out="$(bash "$RUN_LOCK" release --owner "automate-lanes:$parent" --root "$primary" 2>&1 </dev/null)"; then
    _fc "wave closed — lock released"
  else
    _fc "lock release FAILED — $(printf '%s\n' "$out" | head -1)"
  fi
  return 0
}

# wave-plan <parent_runfile> [--wave-branch <name>] — Part S, READ-ONLY (owner decision 2026-10-10: the
# operator merges). Executes no git mutation, no push and no gh write: it reads the lane table, the
# parent `## Current` wave line (`- wave: <k> | items: …`; absent ⇒ the lane table order, wave 1), each
# lane's `## Current` pr and that PR's head sha (`gh pr view <pr> --json headRefOid` — a read), and
# PRINTS the operator's commands: fetch, `git checkout -b <wave branch, default wave/<run_id>-w<k>>
# origin/<base>`, one `git merge --no-ff <exact head sha> -m "Merge lane <L> (<item>) PR #<n>"` per lane
# in planner order (an unreadable sha ⇒ `# <lane>: head unreadable — resolve before integrating`, that
# lane skipped), `bash scripts/ci-local.sh`, the release step (`bash scripts/bump-version.sh` only when
# the repo has it, else `# run this project's release step`), the push and `gh pr create`, then the
# conflict rules. Exit 0 printed · 1 refused (bad parent run file, no lane table, bad branch name).
lanes_wave_plan() {
  local rf="" wb=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --wave-branch) _lanes_need "$#" wave-plan "$1"; wb="$2"; shift 2 ;;
      -*) echo "wave-plan: refused — unknown flag '$1'"; return 1 ;;
      *) [ -z "$rf" ] || { echo "wave-plan: refused — unexpected argument '$1'"; return 1; }; rf="$1"; shift ;;
    esac
  done
  _lanes_parent_of "$rf" || { echo "wave-plan: refused — $LP_WHY"; return 1; }
  local parent="$LP_PARENT" primary="$LP_PRIMARY" table base wl k items tab lane path item run pr num sha v msg rows=""
  tab="$(printf '\t')"
  rf="$primary/.supervisor/automate/$parent.md"; table="$primary/.supervisor/automate/$parent.lanes"
  [ -f "$table" ] || { echo "wave-plan: refused — no lane table ($parent.lanes)"; return 1; }
  base="$(_lanes_base_of "$primary")"
  wl="$(awk '/^## / { sec = $0; next } sec == "## Current" && /^- wave: / { print; exit }' "$rf" 2>/dev/null)"
  k="$(printf '%s' "$wl" | sed -n 's/^- wave: *\([0-9][0-9]*\) *|.*/\1/p; s/^- wave: *\([0-9][0-9]*\) *$/\1/p' | head -1)"
  items="$(printf '%s' "$wl" | sed -n 's/^- wave: [^|]*| *items: *//p' \
    | awk '{ n = split($0, a, /, */); for (i = 1; i <= n; i++) { sub(/ +$/, "", a[i]); if (a[i] != "") print a[i] } }')"
  [ -n "$k" ] || k=1
  [ -n "$wb" ] || wb="wave/$parent-w$k"
  git check-ref-format --branch "$wb" >/dev/null 2>&1 || { echo "wave-plan: refused — '$wb' is not a valid branch name"; return 1; }
  if [ -n "$items" ]; then
    while IFS= read -r item; do
      [ -n "$item" ] || continue
      v="$(awk -F'\t' -v i="$item" '$1 ~ /^L[0-9][0-9]?$/ && $3 == i { r = $1 "\t" $2 "\t" $3 "\t" $4 } END { if (r != "") print r }' "$table")"
      if [ -n "$v" ]; then rows="$rows$v
"; else rows="$rows-$tab-$tab$item$tab-
"; fi
    done <<<"$items"
  else
    rows="$(awk -F'\t' '$1 ~ /^L[0-9][0-9]?$/ { print $1 "\t" $2 "\t" $3 "\t" $4 }' "$table")"
  fi
  local src="from ## Current"; [ -n "$items" ] || src="no ## Current wave items — lane table order"
  echo "# wave-plan: $parent wave $k ($src) — READ-ONLY: nothing below was run; the operator runs it"
  echo "git fetch origin"
  echo "git checkout -b $wb origin/$base"
  while IFS="$tab" read -r lane path item run; do
    [ -n "$lane$item" ] || continue
    if [ "$lane" = - ]; then echo "# $item: no lane in $parent.lanes — skipped"; continue; fi
    pr="$(_lanes_dash "$(_lanes_runfile_fields "$path/.supervisor/automate/$run.md" | cut -f3)")"
    num="${pr##*/}"
    case "$num" in ''|*[!0-9]*) echo "# $lane: no PR recorded in its run file — resolve before integrating"; continue ;; esac
    sha="$("$LANES_GH" pr view "$pr" --json headRefOid 2>/dev/null </dev/null | jq -r '.headRefOid // empty' 2>/dev/null)"
    case "$sha" in [0-9a-f]*) ;; *) sha="" ;; esac
    if [ "${#sha}" != 40 ] || [ -n "$(printf '%s' "$sha" | tr -d '0-9a-f')" ]; then
      echo "# $lane: head unreadable — resolve before integrating"; continue
    fi
    msg="$(printf 'Merge lane %s (%s) PR #%s' "$lane" "$item" "$num" | sed 's/[\\"$`]/\\&/g')"
    printf 'git merge --no-ff %s -m "%s"\n' "$sha" "$msg"
  done <<EOF
$rows
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

_lanes_usage() { awk 'NR >= 9 && /^#$/ { exit } NR >= 9' "$SELF"; }

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
    init-check) lanes_init_check "$@" ;;
    pick-guard) lanes_pick_guard "$@" ;;
    branch-check) lanes_branch_check "$@" ;;
    lane-status) lanes_status "$@" ;;
    lane-feed) lanes_feed "$@" ;;
    lane-readiness) lanes_readiness "$@" ;;
    lane-park-notify) lanes_park_notify "$@" ;;
    fleet-closeout) lanes_fleet_closeout "$@" ;;
    wave-plan) lanes_wave_plan "$@" ;;
    _lane-run) lanes_run_wrapper "$@" ;;
    _merge-hooks) _lanes_merge_hooks "$@" ;;
    -h|--help|help) _lanes_usage ;;
    *) _lanes_usage >&2; return 2 ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then lanes_main "$@"; exit $?; fi
