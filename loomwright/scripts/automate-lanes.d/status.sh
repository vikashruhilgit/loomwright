# ==================================================================================================
# lane-status [<parent_runfile>] [--json] [--watch] [--leaks [--snapshot]] [--resources] [--tokens]
#             [--refresh-readiness] [--keep-awake] [--inbox] [--verbose]
# The plain view (no mode flag) is terse: the header line plus each lane's first line
# (_lanes_render_terse); `--verbose` prints the full _lanes_render view, which `--watch` always shows.
# Mode flags (--json, --inbox, --leaks, --resources, --tokens) ignore --verbose.
lanes_status() {
  local rf="" json=0 watch=0 leaks=0 snap=0 res=0 tok=0 ka=0 refresh=0 inbox=0 verbose=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --inbox) inbox=1 ;;
      --json) json=1 ;; --watch) watch=1 ;; --leaks) leaks=1 ;; --snapshot) leaks=1; snap=1 ;;
      --resources) res=1 ;; --tokens) tok=1 ;; --keep-awake) ka=1 ;; --refresh-readiness) refresh=1 ;;
      --verbose) verbose=1 ;;
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
  if [ "$json" = 1 ]; then printf '%s\n' "$doc"; elif [ "$verbose" = 1 ]; then _lanes_render "$doc"; else _lanes_render_terse "$doc"; fi
  return 0
}

# _lanes_watch [<parent_runfile>] — the full plain view (`--verbose`) every LOOMWRIGHT_LANES_WATCH_INTERVAL_S (default 15)
# seconds; LOOMWRIGHT_LANES_WATCH_ITERATIONS (default 0 = until interrupted) is the test seam.
_lanes_watch() {
  local n="${LOOMWRIGHT_LANES_WATCH_ITERATIONS:-0}" iv="${LOOMWRIGHT_LANES_WATCH_INTERVAL_S:-15}" i=0
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  case "$iv" in ''|*[!0-9]*) iv=15 ;; esac
  while :; do
    [ -t 1 ] && printf '\033[H\033[2J'
    echo "lane-status --watch — $(now_utc) — every ${iv}s (interrupt to stop)"
    if [ -n "${1:-}" ]; then lanes_status "$1" --verbose; else lanes_status --verbose; fi
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
# split needs and with NO gh or ci-slot read and no full stream-log read (the coordinator's Stop hook runs
# it at every turn end): answer_pending · blocked_launch · held_for_load · created · missing · running ·
# awaiting_input · running again in the answer-relaunch gap (_lanes_resume_in_flight, a log-tail read) · `other` (removed / abandoned and every state past awaiting_input: a park, died,
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
       elif [ ! -e "$path.died" ] && _lanes_resume_in_flight "$path.stream.log" "$path/.supervisor/inbox" "$(date -u +%s)" >/dev/null; then
         printf 'running'   # the answer-relaunch gap, as _lanes_lane_json reads it (a stream-log tail only)
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

