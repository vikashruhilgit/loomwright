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
# _lanes_claude_flags <checkout> — sets the LN_FLAGS array: THE headless-session flag list (stream-json
# in/out, the pinned permission regime, the allowlist, the deny list with the checkout's own base-branch
# pushes added, the plugin root, LANE_SYS). One list for a lane (_lanes_spawn) and a phase session
# (phase.sh _lanes_phase_spawn), so the merge / force-push tripwire can never differ between the two.
# The base comes from the ONE resolver, resolve-base-branch.sh (via wave.sh _lanes_base_of), run in
# <checkout>. Unresolved/invalid ⇒
# fail CLOSED: LN_FLAGS emptied, the status token on stderr, return 1 — a session is never started
# without its base-branch push tripwire (both callers return 1 before spawning anything).
_lanes_claude_flags() {
  local base disallow
  LN_FLAGS=()
  if ! base="$(_lanes_base_of "$1" 2>&1)"; then
    printf '%s\n' "$base" >&2; return 1
  fi
  disallow="$LANE_DISALLOWED_FIXED,Bash(git push origin $base:*),Bash(git push origin HEAD:$base:*),Bash(git push origin HEAD:refs/heads/$base:*),Bash(git push -u origin $base:*)"
  LN_FLAGS=(-p --input-format stream-json --output-format stream-json --verbose
    --permission-prompt-tool stdio --permission-mode acceptEdits
    --allowedTools "$LANE_ALLOWED_TOOLS" --disallowedTools "$disallow"
    --plugin-dir "$PLUGIN_ROOT" --append-system-prompt "$LANE_SYS")
}
# _lanes_await_init <stream_log> <byte offset> <pid> — prints the `system/init` session id written to the
# log after <offset>, waiting up to LOOMWRIGHT_LANES_INIT_WAIT_S (default 15) seconds while <pid> lives;
# prints nothing when none appeared.
_lanes_await_init() {
  local log="$1" off="$2" pid="$3" w i=0 s=""
  w="${LOOMWRIGHT_LANES_INIT_WAIT_S:-15}"; case "$w" in ''|*[!0-9]*) w=15 ;; esac
  while [ "$i" -lt $((w * 5)) ]; do
    s="$(tail -c +"$((off + 1))" "$log" 2>/dev/null | grep '^{' | jq -r -R 'fromjson? | select(.type == "system" and .subtype == "init") | .session_id // empty' 2>/dev/null | head -1)"
    [ -n "$s" ] && break
    kill -0 "$pid" 2>/dev/null || { sleep 0.2; s="$(tail -c +"$((off + 1))" "$log" 2>/dev/null | grep '^{' | jq -r -R 'fromjson? | select(.type == "system" and .subtype == "init") | .session_id // empty' 2>/dev/null | head -1)"; break; }
    sleep 0.2; i=$((i + 1))
  done
  printf '%s' "$s"
}
# _lanes_register <register args...> — the ONE proc-registry.sh call line of this file, shared by the lane wrapper
# (_lanes_spawn) and the session registration of the _lane-run wrapper (lane and phase): the user-scope registry
# only, never a write into the lane directory; fail-safe and fully redirected, so it can never change a launch. No
# cap and no grace here: both are the tables of proc-registry.sh, keyed by --kind (a wrapper entry, registered
# without --owner-pid, takes its WRAPPER grace).
_lanes_register() {
  bash "$HERE/proc-registry.sh" register "$@" </dev/null >/dev/null 2>&1
  return 0
}
_lanes_spawn() {
  local prompt="$1" sid="$2" label="$3" in pid st off i s=""
  _lanes_claude_flags "$LN_DIR" || { echo "lane-launch: refused — $LN_LANE — base branch unresolved (status on stderr)"; return 1; }
  local -a flags=("${LN_FLAGS[@]}")
  [ -n "$sid" ] && flags+=(--resume "$sid")
  local -a envu=(-u CLAUDECODE -u CLAUDE_PID -u LOOMWRIGHT_HOLDER_PID)   # a coordinator's holder pin never reaches a lane
  # … nor a phase session's routing (phase.sh): a lane never inherits the coordinator's run-lock session
  # (its own PICK must take its own lock) or a phase dir (its questions belong in the lane inbox).
  envu+=(-u LOOMWRIGHT_RUN_LOCK_SESSION_ID -u LOOMWRIGHT_PHASE_DIR)
  [ "$LN_STRIP_OPTOUT" = 1 ] && envu+=(-u LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS)   # --without-gate-optout
  in=/dev/null
  if [ -n "$prompt" ]; then
    in="$LN_ROOT/$LN_LANE.stdin.json"
    jq -n -c --arg c "$prompt" '{type: "user", message: {role: "user", content: $c}}' > "$in" || return 1
  fi
  touch "$LN_LOG"; rm -f "$LN_DIED"
  off="$(wc -c < "$LN_LOG" | tr -d ' ')"
  # >>> spawn (the only process start; it writes nothing into the lane directory)
  LOOMWRIGHT_LANE_RUN_KIND=lane nohup bash "$SELF" _lane-run "$LN_DIR" "$LN_LOG" "$LN_DIED" "$in" -- \
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
  # process registry (af/39e), through _lanes_register; its --expect waits past nohup's exec itself. The _lane-run
  # wrapper is a WRAPPER KIND (proc-registry.sh header): this entry is the wrapper's, the wrapper registers its
  # session itself (LOOMWRIGHT_LANE_RUN_KIND above)
  _lanes_register --pid "$pid" --kind lane --purpose "_lane-run wrapper of lane $LN_LANE of $LN_PARENT $label" --lane "$LN_DIR" --run-id "$LN_RUN" --expect "_lane-run $LN_DIR " --stop-hint "kill -TERM $pid (the _lane-run wrapper TERMs its headless session)"
  s="$(_lanes_await_init "$LN_LOG" "$off" "$pid")"
  [ -n "$s" ] && _lt_set "$LN_TABLE" "$LN_LANE" 7 "$s"
  LN_SPAWN_SID="$s"
  echo "lane-launch: launched $LN_LANE (pid $pid, session ${s:-unknown}) $label"
}

# _lanes_run_prog <cmd...> — the basename of the program <cmd> finally execs, past a leading
# `env [-u NAME]... [NAME=VALUE]...` (the session registration's --expect substring).
_lanes_run_prog() {
  [ "${1:-}" = env ] || { printf '%s' "${1##*/}"; return 0; }
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in -u) shift; [ "$#" -gt 0 ] && shift ;; -*|*=*) shift ;; *) printf '%s' "${1##*/}"; return 0 ;; esac
  done
}
# _lane-run <lane_dir> <log> <died> <stdin> -- <cmd...> — the nohup wrapper (its argv carries the lane dir).
# LOOMWRIGHT_LANE_RUN_KIND (lane | phase, set by the launcher, never passed on to the session): the wrapper
# registers its background session in proc-registry.sh under that kind, owner = this wrapper (WRAPPER KINDS).
lanes_run_wrapper() {
  local dir="$1" log="$2" died="$3" in="$4" off cp n rc=0 kind="${LOOMWRIGHT_LANE_RUN_KIND:-}"; shift 4; [ "${1:-}" = "--" ] && shift
  unset LOOMWRIGHT_LANE_RUN_KIND
  off="$(wc -c < "$log" 2>/dev/null | tr -d ' ')"; off="${off:-0}"
  cd "$dir" || exit 1
  "$@" < "$in" &
  cp=$!
  trap 'kill -TERM "$cp" 2>/dev/null' TERM INT HUP
  # the session's own registry entry (_lanes_register), backgrounded so its bounded --expect wait never delays the
  # wait below; a lane's session is tied to the lane dir, a phase's to its checkout
  local -a ra=()
  case "$kind" in
    lane)  ra=(--lane "$dir" --purpose "headless session of the _lane-run wrapper $$ (lane $dir)") ;;
    phase) ra=(--repo "$dir" --purpose "headless phase session of the _lane-run wrapper $$ ($log)") ;;
  esac
  if [ "${#ra[@]}" -gt 0 ]; then
    _lanes_register --pid "$cp" --kind "$kind" --owner-pid "$$" "${ra[@]}" --expect "$(_lanes_run_prog "$@")" --stop-hint "kill -TERM $$ (its _lane-run wrapper passes the TERM on)" &
  fi
  wait "$cp"; rc=$?
  while kill -0 "$cp" 2>/dev/null; do wait "$cp"; rc=$?; done
  # a COUNT, never a pipeline's exit status: under this script's `pipefail`, `tail | grep -q` exits 141 whenever
  # grep's first-match exit SIGPIPEs tail mid-stream (a result line followed by more output than a pipe holds),
  # which read as "no result line" — a false `.died` on a session that finished (wave 7, lane L22). `grep -c`
  # reads to EOF, so tail is never cut off, and the decision reads the number, not the pipe
  n="$(tail -c +"$((off + 1))" "$log" 2>/dev/null | grep -c '"type": *"result"')"
  case "$n" in ''|*[!0-9]*|0) printf 'died_at\t%s\nexit\t%s\n' "$(now_utc)" "$rc" > "$died" ;; esac
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

# _lanes_cheap_flag — ` --cheap` when the lane's lane.json carries `"cheap": true` (lane-create --cheap), else
# nothing: the flag every `/loomwright:automate` command this file sends a lane (launch and both --resume-run
# forms) carries, read from the lane's own record so a resume never depends on the coordinator re-passing it.
# The continue and answer-resume spawns send no new command (the session's own carries it) — and the in-lane
# driver reads the same record (automate-next-step.sh), whatever command its session received.
_lanes_cheap_flag() {
  jq -e '.cheap == true' "$LN_DIR/.supervisor/lane.json" >/dev/null 2>&1 && printf ' --cheap'
  return 0
}

# _lanes_launch_go <resume_run|''> <continue 0|1> — the launch proper (caller holds the launch lock).
_lanes_launch_go() {
  local resume_run="$1" cont="$2" ch
  ch="$(_lanes_cheap_flag)"
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
      _lanes_spawn "/loomwright:automate --resume $LN_RUN$ch" "$rsid" "(resume $LN_RUN in its last session $rsid)" || return 1
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
    _lanes_spawn "/loomwright:automate --resume $LN_RUN$ch" "" "(resume $LN_RUN in a fresh session)"
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
    _lanes_spawn "/loomwright:automate --backlog $LN_DIR/.supervisor/lane-backlog.md$ch" "" "(launch)"
  fi
}

# _lanes_session_id — the lane table's session id, else the newest `system/init` in the stream log.
_lanes_session_id() {
  local s; s="$(_lt_get "$LN_TABLE" "$LN_LANE" 7)"
  [ -n "$s" ] || s="$(grep '^{' "$LN_LOG" 2>/dev/null | jq -r -R 'fromjson? | select(.type == "system" and .subtype == "init") | .session_id // empty' 2>/dev/null | tail -1)"
  printf '%s' "$s"
}

_lanes_last_result() { grep '^{' "$1" 2>/dev/null | jq -c -R 'fromjson? | select(.type == "result")' 2>/dev/null | tail -1; }

