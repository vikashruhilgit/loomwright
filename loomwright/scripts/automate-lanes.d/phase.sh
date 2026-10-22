# ==================================================================================================
# Phase sessions (automate-speed/09, fresh session per phase). By default `/automate` runs each phase of
# a Queue item — `launch-pad` (the brief), `supervisor` (implement + Phase 4.5), `drain` (the owned
# `/review-pr --until-mergeable`) — as its OWN headless session in the run's checkout. The
# session reads its inputs from disk and writes its result block to a sidecar; a question it asks reaches
# the coordinator through the relay hook (defer + resume), exactly like a lane's.
#
#   phase-check                  READ-ONLY, one line, exit 0: `phase-check: ok` | `phase-check: unavailable
#                                — <reason>` (jq missing; no claude on PATH; no pinnable permission regime).
#                                Fail CLOSED: anything it cannot read is `unavailable`.
#   phase-launch <runfile> <phase> --owner-command '<cmd>' --coordinator-session <sid> -- <phase prompt>
#                                detached launch. Launch authority as lane-launch: no owner command ⇒
#                                `phase-launch: BLOCKED — <phase> — no owner command — need the owner`, exit 3,
#                                no process; no pinnable regime ⇒ BLOCKED exit 3; already running ⇒ refused
#                                exit 1. No admission hold: a phase session replaces inline work, it adds none.
#   phase-wait <runfile> <phase> [--timeout S]   blocks at most S seconds (default 540, below the Bash tool's
#                                600 s cap) and prints ONE line: `phase-wait: done — session <sid> result
#                                <sidecar>` (exit 0: the process exited with a `"type":"result"` line) |
#                                `phase-wait: running — session <sid>` (exit 3: call again) | `phase-wait:
#                                question — <tool_use_id> <question file>` (exit 5: deferred on the ask-user tool)
#                                | `phase-wait: died — <reason>` (exit 6: `.died` marker, no result line, a
#                                deferral with no recorded question, or no result sidecar — a fresh launch
#                                removes the previous one, so a stale sidecar never reads as this one's). A died
#                                phase is not "nothing happened": the driver still runs its fallbacks on the
#                                died report (the Launch Pad pending-brief diff; the Supervisor open-PR check)
#   phase-answer <runfile> <phase> <tool_use_id> --owner-command '<cmd>'   (stdin {"answers":{…},"note":"…"})
#                                validates exactly as lane-answer (the question's own labels only; a note alone
#                                refused), writes the answer file, resumes the SAME session with `--resume`,
#                                returns; the caller goes back to phase-wait. No owner command ⇒ BLOCKED exit 3,
#                                nothing written.
#
# Phase dir (<phase> ∈ launch-pad | supervisor | drain): <checkout>/.supervisor/automate/<run_id>.phase/<phase>/
#   stream.log  stdin.json  .died  session  pid (<pid>\t<lstart>)  offset (stream.log size at the last spawn)
#   coordinator (the coordinator's session id, re-used by the resume)  inbox/questions/  inbox/answers/
# Sidecars (named here, written by the phase session itself, validated by the driver): <run_id>.launch-pad-
# result.md · <run_id>.supervisor-result.md · <run_id>.review-heal-result.md, beside the run file.
#
# Spawn: the lane's own nohup `_lane-run` wrapper and flag list (_lanes_claude_flags: LANE_ALLOWED_TOOLS,
# LANE_DISALLOWED_FIXED + the base-branch pushes, LANE_SYS), cwd = the run's checkout, plus `--settings`
# carrying ONLY the relay hook (PreToolUse + PermissionRequest on the ask-user tool → `automate-lanes.sh
# relay-hook`) — nothing is written into the checkout's settings files. Env: the lane spawn's (background-wait
# ceiling 0; the host's runtime-identity vars and LOOMWRIGHT_HOLDER_PID unset), plus LOOMWRIGHT_PHASE_DIR=
# <phase dir> (relay-hook routes the question there) and LOOMWRIGHT_RUN_LOCK_SESSION_ID=<coordinator sid>
# (run-lock.sh acquire re-enters the coordinator's lock instead of parking run_lock_held; release never matches on it). A lane spawn strips both.

# _lanes_phase_ctx <runfile> <phase> <subcmd> — sets PH_* or dies (exit 1) naming why.
_lanes_phase_ctx() {
  local rf="${1:-}" ph="${2:-}" sub="$3" d
  [ -n "$rf" ] && [ -n "$ph" ] || die "$sub: usage: $sub <runfile> <phase> … (phase: launch-pad | supervisor | drain)"
  case "$ph" in launch-pad|supervisor|drain) ;; *) die "$sub: unknown phase '$ph' (launch-pad | supervisor | drain)" ;; esac
  [ -f "$rf" ] || die "$sub: no run file: $rf"
  d="$(cd "$(dirname "$rf")" 2>/dev/null && pwd -P)" || die "$sub: cannot read the run file's directory: $rf"
  case "$d" in */.supervisor/automate) ;; *) die "$sub: not a run file under .supervisor/automate/: $rf" ;; esac
  PH_RUN="$(basename "$rf" .md)"
  case "$PH_RUN" in ''|.*|*[!A-Za-z0-9_.-]*) die "$sub: unsafe run id in $rf" ;; esac
  [ "$(basename "$rf")" = "$PH_RUN.md" ] || die "$sub: not a .md run file: $rf"
  PH_SUB="$sub"; PH_PHASE="$ph"; PH_AUTO="$d"; PH_CO="$(dirname "$(dirname "$d")")"
  PH_DIR="$d/$PH_RUN.phase/$ph"; PH_LOG="$PH_DIR/stream.log"; PH_DIED="$PH_DIR/.died"
  case "$ph" in
    launch-pad) PH_SIDECAR="$d/$PH_RUN.launch-pad-result.md" ;;
    supervisor) PH_SIDECAR="$d/$PH_RUN.supervisor-result.md" ;;
    drain) PH_SIDECAR="$d/$PH_RUN.review-heal-result.md" ;;
  esac
}

# _lanes_phase_alive — 0 only for a VERIFIED live phase wrapper: the recorded pid lives, its `ps -o lstart=`
# equals the recorded start, and its command line is this script's `_lane-run <checkout> <phase stream.log>`
# (the log path tells one phase from another and from the checkout's own lane process).
_lanes_phase_alive() {
  local pid="" st="" cur cmd
  [ -f "$PH_DIR/pid" ] || return 1
  IFS="$(printf '\t')" read -r pid st < "$PH_DIR/pid"
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  command -v ps >/dev/null 2>&1 || return 0   # cannot verify ⇒ treat as alive (callers are gates)
  cur="$(ps -o lstart= -p "$pid" 2>/dev/null | _trim_ws)"
  [ -n "$cur" ] || return 1
  [ "$cur" = "$(printf '%s' "$st" | _trim_ws)" ] || return 1
  cmd="$(ps -ww -o command= -p "$pid" 2>/dev/null)"
  case "$cmd" in *"automate-lanes.sh _lane-run $PH_CO $PH_LOG "*) return 0 ;; esac
  return 1
}

# _lanes_phase_last_result — the last `"type":"result"` line written since the last spawn's offset.
_lanes_phase_last_result() {
  local off; off="$(cat "$PH_DIR/offset" 2>/dev/null)"; case "$off" in ''|*[!0-9]*) off=0 ;; esac
  tail -c +"$((off + 1))" "$PH_LOG" 2>/dev/null | grep '^{' | jq -c -R 'fromjson? | select(.type == "result")' 2>/dev/null | tail -1
}

_lanes_phase_sid() { sed -n 1p "$PH_DIR/session" 2>/dev/null; }

# _lanes_phase_spawn <prompt|''> <session_id|''> <verb> <label> <coordinator sid> — the detached launch
# (caller holds the phase launch lock and passed every gate).
_lanes_phase_spawn() {
  local prompt="$1" sid="$2" verb="$3" label="$4" csid="$5" settings in pid st off i s
  settings="$(jq -n -c --arg h "bash \"$SELF\" relay-hook" \
    '[{matcher: "AskUserQuestion", hooks: [{type: "command", command: $h}]}] as $r | {hooks: {PreToolUse: $r, PermissionRequest: $r}}')" || return 1
  _lanes_claude_flags "$PH_CO"
  local -a flags=("${LN_FLAGS[@]}" --settings "$settings")
  [ -n "$sid" ] && flags+=(--resume "$sid")
  local -a envu=(-u CLAUDECODE -u CLAUDE_PID -u LOOMWRIGHT_HOLDER_PID)   # a coordinator's holder pin never reaches a phase session
  in=/dev/null
  if [ -n "$prompt" ]; then
    in="$PH_DIR/stdin.json"
    jq -n -c --arg c "$prompt" '{type: "user", message: {role: "user", content: $c}}' > "$in" || return 1
  fi
  touch "$PH_LOG" || return 1; rm -f "$PH_DIED"
  off="$(wc -c < "$PH_LOG" | tr -d ' ')"
  printf '%s\n' "$off" > "$PH_DIR/offset" || return 1
  # >>> phase spawn (the only process start of this module)
  nohup bash "$SELF" _lane-run "$PH_CO" "$PH_LOG" "$PH_DIED" "$in" -- \
    env "${envu[@]}" CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 \
    LOOMWRIGHT_PHASE_DIR="$PH_DIR" LOOMWRIGHT_RUN_LOCK_SESSION_ID="$csid" claude "${flags[@]}" >> "$PH_LOG" 2>&1 &
  pid=$!
  # <<< phase spawn
  st="$(ps -o lstart= -p "$pid" 2>/dev/null | _trim_ws)"
  printf '%s\t%s\n' "$pid" "$st" > "$PH_DIR/pid"
  # the launch lock is released only once a second caller's liveness check would see this process
  i=0
  while [ "$i" -lt 25 ] && kill -0 "$pid" 2>/dev/null && ! _lanes_phase_alive; do sleep 0.1; i=$((i + 1)); done
  # process registry (af/39e): fail-safe, fully redirected, never invokes claude (the 6h phase cap is proc-registry.sh's)
  _lanes_past_nohup "$pid"
  bash "$HERE/proc-registry.sh" register --pid "$pid" --kind phase --purpose "phase session $PH_PHASE of run $PH_RUN ($verb)" --runfile "$PH_AUTO/$PH_RUN.md" --run-id "$PH_RUN" --repo "$PH_CO" --expect "_lane-run $PH_CO $PH_LOG " --stop-hint "kill -TERM $pid (the _lane-run wrapper TERMs the phase's headless session)" </dev/null >/dev/null 2>&1 || true
  s="$(_lanes_await_init "$PH_LOG" "$off" "$pid")"
  [ -n "$s" ] && printf '%s\n' "$s" > "$PH_DIR/session"
  [ -n "$s" ] || s="$(_lanes_phase_sid)"
  echo "$PH_SUB: $verb $PH_PHASE (pid $pid, session ${s:-unknown}) $label — wait with phase-wait"
}

# ==================================================================================================
# phase-check — READ-ONLY; always exit 0.
lanes_phase_check() {
  [ "$#" -eq 0 ] || die "phase-check: takes no arguments"
  command -v jq >/dev/null 2>&1 || { echo "phase-check: unavailable — jq missing"; return 0; }
  command -v claude >/dev/null 2>&1 || { echo "phase-check: unavailable — no claude on PATH"; return 0; }
  _lanes_regime_ok || { echo "phase-check: unavailable — CLI advertises no pinnable permission regime (--permission-prompt-tool, --allowedTools, --disallowedTools)"; return 0; }
  echo "phase-check: ok"
}

# phase-launch <runfile> <phase> --owner-command '<cmd>' --coordinator-session <sid> -- <phase prompt>
lanes_phase_launch() {
  local rf="" ph="" owner="" csid="" prompt="" rc
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --owner-command) _lanes_need "$#" phase-launch "$1"; owner="$2"; shift 2 ;;
      --coordinator-session) _lanes_need "$#" phase-launch "$1"; csid="$2"; shift 2 ;;
      --) shift; prompt="$*"; break ;;
      *) if [ -z "$rf" ]; then rf="$1"; elif [ -z "$ph" ]; then ph="$1"; else die "phase-launch: unexpected argument '$1'"; fi; shift ;;
    esac
  done
  _lanes_phase_ctx "$rf" "$ph" phase-launch
  if [ -z "$owner" ]; then echo "phase-launch: BLOCKED — $PH_PHASE — no owner command — need the owner"; return 3; fi
  case "$csid" in ''|*[!A-Za-z0-9_-]*) die "phase-launch: --coordinator-session needs the coordinator's session id ([A-Za-z0-9_-]+)" ;; esac
  [ -n "$prompt" ] || die "phase-launch: no phase prompt (pass it after --)"
  mkdir -p "$PH_DIR/inbox/questions" "$PH_DIR/inbox/answers" 2>/dev/null || die "phase-launch: cannot create $PH_DIR"
  _lt_lock "$PH_DIR/launch" || { echo "phase-launch: refused — $PH_PHASE — launch lock busy (another launch of this phase is in flight)"; return 1; }
  if _lanes_phase_alive; then
    _lt_unlock "$PH_DIR/launch"
    echo "phase-launch: refused — $PH_PHASE — already running (pid $(cut -f1 "$PH_DIR/pid" 2>/dev/null))"; return 1
  fi
  if ! _lanes_regime_ok; then
    _lt_unlock "$PH_DIR/launch"
    echo "phase-launch: BLOCKED — $PH_PHASE — CLI advertises no pinnable permission regime — need the owner"; return 3
  fi
  rm -f "$PH_DIR/session"
  if ! { printf '%s\n' "$csid" > "$PH_DIR/coordinator.tmp.$$" && mv "$PH_DIR/coordinator.tmp.$$" "$PH_DIR/coordinator"; }; then
    rm -f "$PH_DIR/coordinator.tmp.$$"; _lt_unlock "$PH_DIR/launch"; die "phase-launch: cannot record the coordinator session ($PH_DIR/coordinator)"
  fi
  # the sidecar beside the run file is per run, not per item: a previous item's copy left there would read as
  # THIS launch's result, so a fresh launch clears it (a resume after phase-answer keeps what the session wrote)
  rm -f "$PH_SIDECAR"
  _lanes_phase_spawn "$prompt" "" launched "(launch)" "$csid"; rc=$?
  _lt_unlock "$PH_DIR/launch"
  return "$rc"
}

# phase-wait <runfile> <phase> [--timeout S]
lanes_phase_wait() {
  local rf="" ph="" to=540 i=0 last id qf sid
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --timeout) _lanes_need "$#" phase-wait "$1"; to="$2"; shift 2 ;;
      *) if [ -z "$rf" ]; then rf="$1"; elif [ -z "$ph" ]; then ph="$1"; else die "phase-wait: unexpected argument '$1'"; fi; shift ;;
    esac
  done
  case "$to" in ''|*[!0-9]*) die "phase-wait: --timeout needs whole seconds" ;; esac
  _lanes_phase_ctx "$rf" "$ph" phase-wait
  [ -f "$PH_DIR/pid" ] || { echo "phase-wait: died — $PH_PHASE was never launched (no $PH_DIR/pid)"; return 6; }
  while _lanes_phase_alive; do
    if [ "$i" -ge $((to * 5)) ]; then echo "phase-wait: running — session $(_lanes_phase_sid | grep . || echo unknown)"; return 3; fi
    sleep 0.2; i=$((i + 1))
  done
  if [ -e "$PH_DIED" ]; then
    echo "phase-wait: died — the session exited with no result line ($(tr '\t\n' '  ' < "$PH_DIED" | sed 's/ *$//'))"; return 6
  fi
  last="$(_lanes_phase_last_result)"
  [ -n "$last" ] || { echo "phase-wait: died — no result line since the last launch"; return 6; }
  sid="$(jq -r '.session_id // empty' <<<"$last" 2>/dev/null)"; [ -n "$sid" ] || sid="$(_lanes_phase_sid)"
  if [ "$(jq -r '.stop_reason // empty' <<<"$last" 2>/dev/null)" = "tool_deferred" ]; then
    id="$(jq -r '.deferred_tool_use.id // empty' <<<"$last" 2>/dev/null)"
    case "$id" in ''|*[!A-Za-z0-9_-]*) echo "phase-wait: died — deferred on an unreadable tool_use id"; return 6 ;; esac
    qf="$PH_DIR/inbox/questions/$id.json"
    [ -s "$qf" ] || { echo "phase-wait: died — deferred on $id with no recorded question (the relay hook did not record it)"; return 6; }
    [ -e "$PH_DIR/inbox/answers/$id.json" ] && { echo "phase-wait: died — $id answered but the session was not resumed"; return 6; }
    echo "phase-wait: question — $id $qf"; return 5
  fi
  # no sidecar ⇒ died (never `done`: the file a done line names must be THIS session's). The driver's died-report
  # path keeps the downstream fallbacks — a saved brief or an opened PR is still found there
  [ -s "$PH_SIDECAR" ] || { echo "phase-wait: died — the session ended without writing its result sidecar ($PH_SIDECAR)"; return 6; }
  echo "phase-wait: done — session ${sid:-unknown} result $PH_SIDECAR"
}

# phase-answer <runfile> <phase> <tool_use_id> --owner-command '<cmd>'   (stdin: answers JSON)
lanes_phase_answer() {
  local rf="" ph="" id="" owner="" qf af last in out sid csid note rc
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --owner-command) _lanes_need "$#" phase-answer "$1"; owner="$2"; shift 2 ;;
      *) if [ -z "$rf" ]; then rf="$1"; elif [ -z "$ph" ]; then ph="$1"; elif [ -z "$id" ]; then id="$1"; else die "phase-answer: unexpected argument '$1'"; fi; shift ;;
    esac
  done
  _lanes_phase_ctx "$rf" "$ph" phase-answer
  case "$id" in ''|*[!A-Za-z0-9_-]*) die "phase-answer: bad tool_use_id '$id'" ;; esac
  qf="$PH_DIR/inbox/questions/$id.json"; af="$PH_DIR/inbox/answers/$id.json"
  [ -s "$qf" ] || die "phase-answer: refused — no recorded question $id"
  [ -e "$af" ] && die "phase-answer: refused — $id already answered"
  _lanes_phase_alive && die "phase-answer: refused — $PH_PHASE is still running"
  last="$(_lanes_phase_last_result)"
  [ "$(jq -r '.stop_reason // empty' <<<"$last" 2>/dev/null)" = "tool_deferred" ] || die "phase-answer: refused — $PH_PHASE did not park on a question"
  [ "$(jq -r '.deferred_tool_use.id // empty' <<<"$last" 2>/dev/null)" = "$id" ] || die "phase-answer: refused — $PH_PHASE is parked on another question"
  in="$(cat)"
  jq -e 'type == "object"' >/dev/null 2>&1 <<<"$in" || die "phase-answer: refused — answers are not a JSON object"
  out="$(_lanes_validate_answers "$qf" "$in")" || die "phase-answer: refused — $(sed -E 's/^jq: error \(at [^)]*\): //' <<<"$out")"
  sid="$(jq -r '.session_id // empty' <<<"$last")"; [ -n "$sid" ] || sid="$(_lanes_phase_sid)"
  [ -n "$sid" ] || die "phase-answer: refused — no session id to resume"
  csid="$(sed -n 1p "$PH_DIR/coordinator" 2>/dev/null)"
  case "$csid" in ''|*[!A-Za-z0-9_-]*) die "phase-answer: refused — no recorded coordinator session ($PH_DIR/coordinator)" ;; esac
  note="$(jq -r '.note // ""' <<<"$in")"
  if [ -z "$owner" ]; then echo "phase-answer: BLOCKED — $PH_PHASE — no owner command — need the owner"; return 3; fi
  # authority + regime BEFORE the answer is written, under the launch lock, so an overlapping answer sees it.
  _lt_lock "$PH_DIR/launch" || die "phase-answer: refused — $PH_PHASE — launch lock busy (another launch of this phase is in flight)"
  if [ -e "$af" ]; then _lt_unlock "$PH_DIR/launch"; die "phase-answer: refused — $id already answered"; fi
  if _lanes_phase_alive; then _lt_unlock "$PH_DIR/launch"; die "phase-answer: refused — $PH_PHASE is still running"; fi
  if ! _lanes_regime_ok; then
    _lt_unlock "$PH_DIR/launch"
    echo "phase-answer: BLOCKED — $PH_PHASE — CLI advertises no pinnable permission regime — need the owner"; return 3
  fi
  _lanes_answer_file_write "$af" "$out" "$note" "phase-answer" \
    || { _lt_unlock "$PH_DIR/launch"; die "phase-answer: cannot write the answer file"; }
  [ -n "$note" ] && echo "phase-answer: note recorded and delivered to the session as an annotation (never the decision)"
  _lanes_phase_spawn "" "$sid" resumed "(after answer $id)" "$csid"; rc=$?
  _lt_unlock "$PH_DIR/launch"
  return "$rc"
}
