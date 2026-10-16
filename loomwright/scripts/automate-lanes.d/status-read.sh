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
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    q="$1/questions/$id.json"
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
  done <<EOF
$(_lanes_pending_questions "$1")
EOF
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
    while IFS= read -r id; do
      [ -n "$id" ] || continue
      q="$path/.supervisor/inbox/questions/$id.json"
      rows="$rows$(jq -c --arg l "$lane" --arg id "$id" '{at: ((.asked_at // "unknown") | tostring), lane: $l, id: $id,
          qs: (if (.questions | type) == "array" then .questions else [] end)}' "$q" 2>/dev/null \
        || jq -n -c --arg l "$lane" --arg id "$id" '{at: "unknown", lane: $l, id: $id, qs: []}')
"
    done <<EOF
$(_lanes_pending_questions "$path/.supervisor/inbox")
EOF
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

# _lanes_timeline <runfile> <supervisor_dir> <now_epoch> <state> <last_launch_utc> [<lane session id>] — the lane's step timeline:
# {started_at, current, label, steps: [{id, name, state, started_at, ended_at, duration_s, lines}],
#  phase, phase_status, phases: [{phase, at}]} — the last three the lane's Supervisor's (null / []). The seven steps are the per-item loop as
# a lane records it: pick · plan (Launch Pad) · build (Supervisor up to the PR) · heal (Phase 4.5) ·
# drain (the owned /review-pr --until-mergeable) · decide (dismissed findings) · merge (park → merge →
# close-out). Evidence: the run file's timestamped `## Progress` lines, plus the lane's Supervisor
# `<supervisor_dir>/state.md` (the lane's `.supervisor/`, or its salvage copy once removed; `## Session` phase/status, `## Decisions Log` phase timestamps) only when that
# state was created at or after the pick — a previous item's Supervisor state never shows. A step is
# reached at its first evidence; the current step is the furthest one reached, its state taken from the
# lane state (`active`, `waiting` on the owner, `held`, `trouble`; every step `done` once merged/done).
# A step passed without a line of its own reads `done` with null times: the run never said when it ran.
# The Supervisor's own phase evidence: `## Session` `phase:` is projected by build-state.sh from two
# session-log events only (EXECUTE / LOOP), so it reads EXECUTE through FINALIZE and Phase 4.5. Two more
# sources carry the real phase: (1) the canonical Decisions Log TABLE rows (`| # | Phase | Decision |
# Rationale |`, state-management SKILL.md) — undated, so reach-only: SELF_HEAL/LOOP reach Heal, any other
# phase Build — trusted under the same predicate as `phase`; (2) the first `pr_created` event (written by
# hook-dispatch-on-pr-create.sh into `<supervisor_dir>/logs/<## Session session_id>.jsonl`) at or after
# the pick, a TIMED Heal start: FINALIZE opens the PR and Phase 4.5 is always entered right after it
# (agents/supervisor.md §"Phase 4.5"), and Build is "Supervisor up to the PR" by its own definition.
# Whose state it is: `## Checkpoint` `created:` (the dated trust) is in almost no real state file — the
# canonical template writes an agent-filled `last_checkpoint:` (a bare date, "(time not captured)", a fake
# midnight), so no Checkpoint time is trusted beyond `created:`. Identity is: a lane runs ONE item in one
# session (lane-create writes a one-line backlog), so a state whose `## Session` `session_id` is the lane's
# own session (the lane table's, from its stream `system/init`) is this item's. Such a state is trusted like
# a running one — phase, status, Decisions Log table rows, the Build label — whether or not the lane still
# runs, and still without a time: a lane that stopped mid-EXECUTE keeps its phase.
# Boundaries: the `picked` line ends Pick and starts Plan; a Launch Pad "brief saved" line ends Plan and starts Build (/autonomous hands the brief to
# the Supervisor at once); a `ran /autonomous` line carrying the heal verdict reaches Heal too. The pinned no-PR
# line (`ran /autonomous — no PR: <status_reason> (…)`, per-item-loop.md step 2) reaches only Plan when its
# status_reason token (snake_case, a backtick/quote/paren around it tolerated) is one of `planstop` (the Supervisor
# never started), else Build; `unknown` or any other free-text line with no
# PR URL that names Launch Pad and neither the Supervisor nor a saved brief reaches only Plan too.
# A `parked …` line is the Merge gate's only once the lane reached Drain; a park before that (Launch Pad
# blocked, an escalated build) reaches no step of its own — it joins the furthest step reached, which the
# lane state then colors, and every later step stays `pending`.
# Fail-SAFE: anything unreadable ⇒ `null`.
_lanes_timeline() {
  local rf="$1" sm="$2/state.md" now="$3" state="$4" llu="$5" lsid="${6:-}" out sid
  # Validated, never trusted by exit code: under `pipefail` an absent state.md fails the pipeline even
  # when jq printed a good object, and an `|| printf null` there would emit two JSON texts.
  out="$({
    [ -f "$rf" ] && awk '/^## / { sec = $0; next }
      sec == "## Progress" && /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z / {
        x = substr($0, 24); gsub(/\t/, " ", x); printf "P\t%s\t%s\n", substr($0, 3, 20), x }' "$rf" 2>/dev/null
    [ -f "$sm" ] && awk 'function val(s) { sub(/^- [a-z_]*: */, "", s); gsub(/\t/, " ", s); return s }
      /^## / { sec = $0; next }
      sec == "## Session" && /^- (phase|status|session_id):/ { k = $2; sub(/:$/, "", k); printf "S\t%s\t%s\n", k, val($0) }
      sec == "## Checkpoint" && /^- (created|last_updated):/ { k = $2; sub(/:$/, "", k); printf "S\t%s\t%s\n", k, val($0) }
      sec == "## Decisions Log" && /^- phase: / && /timestamp: / {
        ph = $0; sub(/^- phase: */, "", ph); sub(/[, ].*/, "", ph)
        ts = $0; sub(/.*timestamp: */, "", ts); sub(/[ ,].*/, "", ts)
        d = $0; sub(/^.*decision: */, "", d); sub(/, (rationale|timestamp):.*/, "", d); gsub(/\t/, " ", d)
        printf "D\t%s\t%s\t%s\n", ph, ts, d }
      sec == "## Decisions Log" && /^\| *[0-9]+ *\| *[A-Z][A-Z0-9_]* *\|/ {
        n = split($0, f, "|"); ph = f[3]; gsub(/^ +| +$/, "", ph); d = f[4]; gsub(/^ +| +$/, "", d); gsub(/\t/, " ", d)
        printf "T\t%s\t%s\n", ph, d }' "$sm" 2>/dev/null
    sid="$([ -f "$sm" ] && sed -nE 's/^- session_id:[[:space:]]*//p' "$sm" 2>/dev/null | head -1 | tr -cd 'A-Za-z0-9_-')"
    [ -n "$sid" ] && [ -f "$2/logs/$sid.jsonl" ] && jq -R -r 'fromjson? | select(.event? == "pr_created")
      | "E\tpr_created\t\(.ts // "")\t\(.url // "" | gsub("[\t\n]"; " "))"' "$2/logs/$sid.jsonl" 2>/dev/null
    true
  } | jq -R -s -c --arg state "$state" --arg llu "$(_lanes_dash "$llu")" --arg lsid "$(_lanes_dash "$lsid")" --argjson now "$now" '
    def ep: (try fromdateiso8601 catch null);
    def clip(n): if length > n then .[0:n - 1] + "…" else . end;
    def ids: ["pick", "plan", "build", "heal", "drain", "decide", "merge"];
    def names: ["Pick", "Plan", "Build", "Heal", "Drain", "Decide", "Merge"];
    def ord: . as $id | ids | index($id);
    # AUTONOMOUS_RUN status_reasons that stop /autonomous before the Supervisor starts (INIT, Launch Pad, brief checks).
    def planstop: ["launch_pad_blocked", "user_aborted_at_launch_pad", "launch_pad_cant_ask_non_interactive",
      "user_discarded_at_phase_6", "user_aborted_at_no_go", "user_aborted_at_plan_review_fail", "rubric_dropped_from_brief",
      "concurrent_session_detected", "non_interactive_without_fallback", "invalid_max_iterations", "conflicting_mode_flags",
      "run_lock_held"];
    # The token of the pinned no-PR line (per-item-loop.md step 2), tolerating one backtick / quote / paren around it.
    def noprtok: (capture("no PR: [`\"(]?(?<r>[a-z]+_[a-z0-9_]+)") | .r) // null;
    def cls:
      if test("^parked ") then ["park"]
      elif test("^(closeout |auto-finalized|trail-pr|lane park notify|converted |merged)") then ["merge"]
      elif test("^(dismissed|owner decisions)") then ["decide"]
      elif test("owned drain started|^drain |re-drain") then ["drain"]
      elif test("^/autonomous done") then ["heal"]
      elif test("^ran /autonomous") then (if noprtok != null then (if (noprtok | IN(planstop[])) then ["plan"] else ["build"] end)
                                         elif test("heal (PASS|FAIL|ESCALATED)") then ["build", "heal"]
                                         elif (test("PR https?://") | not) and test("launch[ _-]?pad"; "i")
                                              and (test("supervisor|brief saved"; "i") | not) then ["plan"] else ["build"] end)
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
    | ($lsid != "" and ($s.session_id // "") == $lsid) as $own
    | (($live or $own) and ($s.phase // "") != "") as $ph
    | ([$p[] | . as $x | ($x.text | cls)[] | {step: ., ts: $x.ts, e: $x.e, text: $x.text}]
       + (if $sup then
            [{step: "build", ts: $s.created, e: $se, text: "Supervisor started"}]
            + [$rows[] | select(.[0] == "D") | {step: (.[1] | sstep), ts: .[2], e: (.[2] | ep),
                 text: ("Supervisor " + .[1] + ": " + (.[3] // ""))} | select(.e != null)]
            + [$rows[] | select(.[0] == "T") | {step: (.[1] | sstep), ts: null, e: null,
                 text: ("Supervisor " + .[1] + ": " + (.[2] // ""))}]
            + (if ($s.phase // "") | sstep == "heal" then
                 [{step: "heal", ts: ($s.last_updated // $s.created), e: ((($s.last_updated // "") | ep) // $se),
                   text: ("Supervisor " + $s.phase + " (" + ($s.status // "?") + ")")}] else [] end)
          elif $live or $own then
            [$rows[] | select(.[0] == "T") | {step: (.[1] | sstep), ts: null, e: null,
               text: ("Supervisor " + .[1] + ": " + (.[2] // ""))}]
          else [] end)
       + (if $pick == null then [] else
            [$rows[] | select(.[0] == "E" and .[1] == "pr_created") | {ts: .[2], e: (.[2] | ep), url: (.[3] // "")}
               | select(.e != null and .e >= $pick.e)] | sort_by(.e) | .[0:1]
            | map({step: "heal", ts, e, text: ("Supervisor opened the PR" + (if .url == "" then "" else " " + .url end) + " — Phase 4.5")})
          end)) as $ev0
    | ([($ev0[] | select(.step != "park") | .step), (if $ph then ($s.phase | sstep) else empty end) | ord] | max // 0) as $reach
    | [$ev0[] | if .step == "park" then .step = (if $reach >= ("drain" | ord) then "merge" else ids[$reach] end) else . end] as $ev
    | ([($ev[] | .step), (if $ph then ($s.phase | sstep) else empty end) | ord] | max // 0) as $far
    | (if ($state | test("^(merged|done)$")) then 7 else $far end) as $cur
    | (if $state == "running" then "active"
       elif ($state | test("^(awaiting_input|answer_pending|ready_for_release|awaiting_merge)$")) then "waiting"
       elif ($state | test("^(held_for_load|created|removed)$")) then "held"
       elif ($state | test("^(stalled|died|lost_to_reset|missing|blocked_launch|gone|escalated|failed|rate_limit|drain_died|abandoned)$")) then "trouble"
       else "active" end) as $cs
    | [range(0; 7) as $i
        | ([$ev[] | select(.step == ids[$i])] | sort_by(.e // 9e15)) as $mine
        | {i: $i, first: ($mine | first), last: ($mine | last), lines: [$mine[] | .text | clip(140)][-4:],
           state: (if $i < $cur then "done" elif $i == $cur then $cs else "pending" end)}] as $st
    | [$st[] | . as $x
        | ([$st[($x.i + 1):][] | select(.first != null and .i <= $cur) | .first.e] | min) as $next
        | (if $x.state == "pending" or ($x.i == $cur) then null else ($next // $x.last.e) end) as $end
        # A step whose first dated line comes after it ended (a retrospective line, e.g. `ran /autonomous`
        # written once /autonomous returned, past the PR that started Heal) has no known start: null.
        | ($x.first.e // null) as $b0
        | (if $b0 != null and $end != null and $b0 > $end then null else $b0 end) as $b
        | {id: ids[$x.i], name: names[$x.i], state: $x.state, started_at: (if $b == null then null else $x.first.ts end),
           ended_at: (if $end == null then null else ($end | todateiso8601) end),
           duration_s: (if $b == null then null elif $end != null then ($end - $b)
                        elif $x.i == $cur then ([$now - $b, 0] | max) else null end),
           lines: $x.lines}] as $steps
    | ([$steps[] | select(.state != "done" and .state != "pending")] | first) as $c
    | ([$ev[] | select(.step == "drain") | .text | capture("drain round (?<n>[0-9]+)") | .n] | last) as $round
    | {started_at: (($p | first | .ts) // (if $llu == "" then null else $llu end)),
       current: ($c.id // null),
       label: (if $c == null then (if $cur >= 7 then "Done" else null end)
               elif $c.id == "build" and ($sup or $live or $own) and ($s.phase // "") != "" then "Build · " + $s.phase
               elif $c.id == "drain" and $round != null then "Drain · round " + $round
               else $c.name end),
       steps: $steps,
       phase: (if $sup or $live or $own then ($s.phase // null) else null end),
       phase_status: (if $sup or $live or $own then ($s.status // null) else null end),
       phases: (if $sup then [$rows[] | select(.[0] == "D") | {phase: .[1], at: .[2]}] | group_by(.phase) | map(min_by(.at)) | sort_by(.at)
                else [] end)}' 2>/dev/null)"
  if jq -e 'type == "object"' >/dev/null 2>&1 <<<"$out"; then printf '%s' "$out"; else printf 'null'; fi
}

# _lanes_salvaged_sup <lanes_root> <lane> — the newest copy lane-remove kept of <lane>'s clone (its
# `salvage/<lane>-removed-<UTC stamp>-<pid>/` dir, the clone's `.supervisor/` saved as `supervisor/`), or nothing.
# The stamp sorts by time, so the glob's last match is the newest; `L1-` never matches L10's copies.
_lanes_salvaged_sup() {
  local d best=""
  for d in "$1/salvage/$2-removed-"*; do [ -d "$d/supervisor" ] && best="$d"; done
  printf '%s' "$best"
}

# _lanes_salvage_time <salvage_dir> — the UTC time in its name (`…-20261015T022615Z-<pid>`) as ISO 8601, or nothing.
_lanes_salvage_time() {
  printf '%s' "${1##*/}" | sed -n 's/.*-\([0-9][0-9][0-9][0-9]\)\([0-9][0-9]\)\([0-9][0-9]\)T\([0-9][0-9]\)\([0-9][0-9]\)\([0-9][0-9]\)Z-[0-9]*$/\1-\2-\3T\4:\5:\6Z/p'
}

# _lanes_last_dated <runfile> — the time of its last dated `## Progress` line, or nothing.
_lanes_last_dated() {
  [ -f "${1:-}" ] || return 0
  awk '/^## / { sec = $0; next }
    sec == "## Progress" && /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z / { t = substr($0, 3, 20) }
    END { if (t != "") print t }' "$1" 2>/dev/null
}

# _lanes_lane_json <10 lane-table columns> <now_epoch> <ci_json> [<answer-pending file>] [<closeout PR>] — one lane's
# status object. A removed/abandoned lane's clone is gone, so its run file, Supervisor state and readiness are
# read from the copy lane-remove salvaged (_lanes_salvaged_sup) — never its inbox: a salvaged question is not
# one the lane still holds. `outcome` says how a removed lane ended: `done` (its run file reads `## Status:
# done`, or the parent recorded `fleet closeout: <lane> … done (PR <closeout PR>)`), else `removed`;
# `abandoned`; null for a lane still in the table's live states. `ended_at` is when a lane that no longer works
# stopped (parked, merged, removed, stopped): its run file's last dated `## Progress` line, else the salvage
# time; null while it runs, waits on a question, or has not launched — the pane's elapsed clock stops there.
# Classification order (first match wins): removed/abandoned · answer_pending (a HELD answer kept
# coordinator-side for a question the lane still holds, the process not running — shown, never delivered here) · blocked_launch · held_for_load (a lane holding an unanswered question,
# no process running, reads awaiting_input instead) · created · missing · running
# (lanes_proc_alive) · awaiting_input · parked (merged / gone after reconcile) · lost_to_reset (boot
# later than the last launch) · died (.died marker) · stalled.
_lanes_lane_json() {
  local lane="$1" path="$2" item="$3" run="$4" pid="$5" st="$6" sid="$7" ts="$8" llu="$9" why="${10}" now="${11}" ci="${12}" apf="${13:-}"
  local fcpr="${14:-}" sup sv="" oc="" ended="" tst
  local root log died rf status pause pr lp pd state reason="" held="" qs nq pk prs="" le be rdf rds="" rdsum="" lm la cij
  root="$(dirname "$path")"; log="$root/$lane.stream.log"; died="$root/$lane.died"
  sup="$path/.supervisor"
  case "$ts" in
    removed|abandoned) [ -d "$sup" ] || { sv="$(_lanes_salvaged_sup "$root" "$lane")"; [ -z "$sv" ] || sup="$sv/supervisor"; } ;;
  esac
  rf="$sup/automate/$run.md"
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
  case "$state" in
    removed)
      if [ "$status" = done ] || _lanes_rf_done "$rf" || [ -n "$fcpr" ]; then oc=done; else oc=removed; fi
      case "$(_lanes_dash "$pr")" in '') case "$fcpr" in https://*) pr="$fcpr" ;; esac ;; esac ;;
    abandoned) oc=abandoned ;;
  esac
  case "$state" in
    running|awaiting_input|answer_pending|created|held_for_load|blocked_launch|missing) ;;
    *) ended="$(_lanes_last_dated "$rf")"; [ -n "$ended" ] || [ -z "$sv" ] || ended="$(_lanes_salvage_time "$sv")" ;;
  esac
  rdf="$sup/automate/$run.merge-readiness.md"
  if [ -f "$rdf" ]; then
    rds="$(sed -n 's/^- score: \([0-9]*\/[0-9]*\).*/\1/p' "$rdf" | head -1)"
    rdsum="$(sed -n 's/^- score: .* | summary: //p' "$rdf" | head -1)"
  fi
  lm="$(_lanes_last_message "$log")"; la="$(_lanes_last_actions "$log")"
  local pdg tl; pdg="$(_lanes_policy_digest "$path/.supervisor/inbox")"
  jq -e 'type == "object" or . == null' >/dev/null 2>&1 <<<"$pdg" || pdg=null
  # A lane closed out as done draws every step done, like a merged one; removed without it, the step it stopped at.
  tst="$state"; [ "$oc" = done ] && tst=done
  tl="$(_lanes_timeline "$rf" "$sup" "$now" "$tst" "$llu" "$sid")"
  jq -e 'type == "object" or . == null' >/dev/null 2>&1 <<<"$tl" || tl=null
  jq -n -c --arg lane "$lane" --arg path "$path" --arg item "$(_lanes_dash "$item")" --arg run "$run" --argjson pdg "$pdg" --argjson tl "$tl" \
    --arg state "$state" --arg reason "$reason" --arg pid "$(_lanes_dash "$pid")" --arg sid "$(_lanes_dash "$sid")" \
    --arg llu "$(_lanes_dash "$llu")" --arg status "$(_lanes_dash "$status")" --arg pause "$(_lanes_dash "$pause")" \
    --arg pr "$(_lanes_dash "$pr")" --arg prs "$prs" --arg lp "$(_lanes_dash "$lp")" --arg lm "$lm" --arg la "$la" \
    --argjson qs "$qs" --argjson ci "$cij" --arg held "$held" --arg rdf "$rdf" --arg rds "$rds" --arg rdsum "$rdsum" \
    --arg br "$(_lanes_runfile_branch "$rf")" --arg oc "$oc" --arg ended "$ended" \
    'def n: if . == "" then null else . end;
     {lane: $lane, path: $path, item: $item, run_id: $run, state: $state, reason: $reason, pid: ($pid | n),
      session_id: ($sid | n), last_launch_utc: ($llu | n), run_status: ($status | n), pause_reason: ($pause | n),
      pr: ($pr | n), pr_state: ($prs | n), branch: ($br | n), last_progress: $lp, last_actions: ($la | split("\n") | map(select(. != ""))),
      last_message: $lm, questions: $qs, ci_slot: $ci, held_for_load: ($held | n),
      readiness: (if $rds == "" then null else {score: $rds, summary: $rdsum, file: $rdf} end), policy: $pdg,
      started_at: ($tl.started_at // ($llu | n)), ended_at: ($ended | n), outcome: ($oc | n), timeline: $tl}'
}

# _lanes_status_doc <table> <parent> <primary> — the full lane-status JSON document.
_lanes_status_doc() {
  local table="$1" parent="$2" primary="$3" now ci m hint lanes="" row tab prf fc
  tab="$(printf '\t')"; now="$(date -u +%s)"; ci="$(_lanes_ci_json)"; m="$(_lanes_machine_json)"; hint="$(_lanes_keep_awake_hint)"
  prf="$primary/.supervisor/automate/$parent.md"
  # fc: `<lane>\t<PR>` per `fleet closeout: <lane> <item> done (PR <url|none recorded>)` line — the parent's
  # own record that a lane closed out, read when its salvaged run file is gone too.
  fc="$(awk '/^## / { sec = $0; next }
    sec == "## Progress" && /fleet closeout: L[0-9]+ .* done \(PR / {
      x = $0; sub(/.*fleet closeout: /, "", x); l = x; sub(/ .*/, "", l)
      p = x; sub(/.* done \(PR /, "", p); sub(/\)[[:space:]]*$/, "", p); printf "%s\t%s\n", l, p }' "$prf" 2>/dev/null)"
  local lane path item run pid st sid ts llu why
  while IFS="$tab" read -r lane path item run pid st sid ts llu why; do
    case "$lane" in L[0-9]|L[0-9][0-9]) ;; *) continue ;; esac
    row="$(_lanes_lane_json "$lane" "$path" "$item" "$run" "$pid" "$st" "$sid" "$ts" "$llu" "${why:--}" "$now" "$ci" \
      "$primary/.supervisor/automate/$parent.$lane.answer-pending.json" \
      "$(printf '%s\n' "$fc" | awk -F'\t' -v l="$lane" '$1 == l { p = $2 } END { print p }')")" || continue
    lanes="$lanes$row
"
  done < "$table"
  local rs; rs="$(awk '/^## / { sec = $0; next } sec == "## Progress" && /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9:]*Z / { print substr($0, 3, 20); exit }' \
    "$primary/.supervisor/automate/$parent.md" 2>/dev/null)"
  # waves: every wave PR this run opened, oldest first, read from wave-build's `## Progress` record
  # (`<ts> wave built: <branch> — PR <url> (lanes: L1 PR #n, …; …)`; a hand-built wave writes the same line,
  # its timestamp sometimes left out). No gh call: lane-status is polled, so the PR's own state is not read
  # here — a wave's `state` is `merged` once every lane it names is merged or closed out as done (a lane PR
  # reads merged only once the wave PR landed it), `open` otherwise, null when the line names no lanes.
  # next_wave: the lanes no built wave names yet and still in the table's live states — the wave being
  # worked now — numbered one past the last built wave; null in single-lane mode (`- parallel: 1`).
  local wv; wv="$(awk '/^## / { sec = $0; next } sec == "## Progress" && /^- .*wave built/' "$primary/.supervisor/automate/$parent.md" 2>/dev/null \
    | jq -R -s -c '[split("\n")[]
        | . as $line
        | capture("^- (?:(?<built_at>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z) )?wave built.*?: (?<branch>[^ ]+) — PR (?<pr>https://[^ ]+)")
        | .pr |= sub("[),.;]+$"; "")
        | . + {lanes: ((($line | capture("\\(lanes: (?<ls>[^;)]*)").ls) // "") | [scan("L[0-9]+")])}
        | . + {wave: ((.branch | capture("w(?<k>[0-9]+)$").k | tonumber)? // null)}]' 2>/dev/null)"
  [ -n "$wv" ] || wv='[]'
  # utc_offset_s: the machine's local offset, so a client in a sandbox with no time zone can show local
  # clock times ("started 18:22"); `date +%z` is POSIX on BSD and GNU alike.
  local tz; tz="$(date +%z 2>/dev/null)"
  case "$tz" in [+-][0-9][0-9][0-9][0-9]) tz="$(( (10#${tz:1:2} * 3600 + 10#${tz:3:2} * 60) * (${tz:0:1}1) ))" ;; *) tz=null ;; esac
  printf '%s' "$lanes" | jq -s -c --arg parent "$parent" --arg primary "$primary" --arg at "$(now_utc)" --argjson m "$m" --arg rs "$rs" --argjson tz "$tz" --argjson wv "$wv" \
    --arg hint "$hint" --arg mp "$([ -e "$primary/.supervisor/automate/$parent.memory-pressure" ] && echo true || echo false)" \
    --arg single "$(_lanes_single_parent "$prf" && echo true || echo false)" \
    '. as $L
     | def landed: .state == "merged" or .state == "done" or .outcome == "done";
     ([$wv[].lanes[]]) as $built
     | ([$L[] | select(.lane as $x | ($built | index($x)) == null) | select(.state != "removed" and .state != "abandoned")]) as $rest
     | {schema_version: 1, parent_run_id: $parent, primary: $primary, generated_at: $at,
      run_started_at: (if $rs != "" then $rs else ([.[].started_at | select(. != null)] | min) end), utc_offset_s: $tz,
      waves: [$wv[] | . as $w | [$L[] | select(.lane as $x | ($w.lanes | index($x)) != null)] as $mine
        | $w + {state: (if ($w.lanes | length) == 0 then null
                        elif ($mine | length) == ($w.lanes | length) and all($mine[]; landed) then "merged" else "open" end)}],
      next_wave: (if $single == "true" or ($rest | length) == 0 then null
                  else {wave: ((([$wv[].wave | numbers] | max) // 0) + 1), lanes: [$rest[].lane]} end),
      machine: $m,
      memory_pressure: ($mp == "true"), keep_awake_suggestion: (if $hint == "" then null else $hint end), lanes: .}'
}

_lanes_render() { # <status JSON> — the plain view
  jq -r '"lane-status: \(.parent_run_id) — \(.lanes | length) lane(s) — \(.generated_at)\(if .run_started_at != null then " — started \(.run_started_at)" else "" end)",
    ((.waves // [])[] | "wave\(if .wave != null then " " + (.wave | tostring) else "" end) PR: \(.pr)  branch=\(.branch)\(if .built_at != null then "  built " + .built_at else "" end)\(if .state != null then "  " + .state else "" end)\(if (.lanes // []) != [] then "  lanes " + (.lanes | join(",")) else "" end)"),
    (if all(.lanes[]; .policy == null) then "policy: none answered" else empty end),
    (if .next_wave != null then "wave \(.next_wave.wave) (not built yet): lanes \(.next_wave.lanes | join(","))" else empty end),
    (.lanes[] | "\(.lane)  \(.state)\(if .outcome != null and .outcome != .state then " — " + .outcome else "" end)\(if .reason != "" then " (" + .reason + ")" else "" end)  item=\(.item)  pr=\(.pr // "-")\(if .ended_at != null then "  ended=" + .ended_at else "" end)  path=\(.path)",
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
    else v="$(_lanes_tokens_line "$rf" "$lane")"; fi
    case "$v" in ''|*[!0-9]*) return 1 ;; esac
    sum=$((sum + 10#$v))
  done < "$table"
  echo "$sum"
}

# _lanes_tokens_line <parent_runfile> <lane> — the value of the LAST `## Progress` line `fleet closeout:
# <lane> tokens TOTAL=<v>`, matched after one OPTIONAL timestamp token (the `^([^ ]+ )?` convention of
# `picked`, _lanes_vg_has and progress-append's `current_not_set` guard). Prints <v>; exit 1 when no such
# line. The one reader of that line: _lanes_single_spent sums it, _lanes_tokens_record skips on it.
_lanes_tokens_line() {
  L="$2" awk 'BEGIN { p = "fleet closeout: " ENVIRON["L"] " tokens TOTAL=" }
    /^## / { inp = ($0 ~ /^## Progress/); next }
    !inp { next }
    { l = $0; if (sub(/^- /, "", l) == 0) next
      if (index(l, p) != 1) { sub(/^[^ ]+ /, "", l); if (index(l, p) != 1) next }
      v = substr(l, length(p) + 1); f = 1 }
    END { if (!f) exit 1; print v }' "$1" 2>/dev/null
}

# _lanes_tokens_record <parent_runfile> <lane> <lane path> <lane run_id> — single-lane parents only:
# append `fleet closeout: <lane> tokens TOTAL=<n|unknown>` to the parent `## Progress` unless that lane
# already has one. Called BEFORE the lane directory is deleted (fleet-closeout step 5, lane-remove), so
# the whole-run ceiling can still count a removed lane. Prints the line it wrote (nothing when skipped).
_lanes_tokens_record() {
  local rf="$1" lane="$2" t
  _lanes_tokens_line "$rf" "$lane" >/dev/null && return 0
  t="$(_lanes_lane_total "$4" "$3")"
  bash "$HELPERS" progress-append "$rf" "fleet closeout: $lane tokens TOTAL=$t" >/dev/null 2>&1 \
    || { echo "automate-lanes: WARNING — the tokens line for $lane could not be appended" >&2; return 1; }
  echo "$lane TOTAL=$t"
}

