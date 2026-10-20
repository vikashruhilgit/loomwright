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

# _lanes_resume_in_flight <stream_log> <inbox> <now_epoch> [any] — the answer-relaunch gap (wave 7, run
# automate-2026-10-15-163325: lane-wait reported L21 / L23 / L24 `stalled` seconds before each read running).
# lane-answer writes the answer file FIRST — so the question stops being pending — and only then spawns
# the resume, whose process lanes_proc_alive cannot see until its wrapper has exec'd (and `claude --help`
# probes the regime in between): in that window a lane with no live process, no pending question and no
# park read `stalled`, inviting the one allowed `--continue` to be spent on a lane already resuming.
# 0 (prints `<id> (written <at>)`) when the lane's last result line is still the `tool_deferred` exit on
# question <id>, answers/<id>.json exists — so no resumed session has written a result since — and that
# answer was written within LOOMWRIGHT_LANES_RESUME_GRACE_S (default 120) of <now>. With `any`, the age
# bound is dropped (the stalled reason names the answer). An unreadable time ⇒ 1: the lane reads stalled,
# never a hidden stall. A resume that died leaves the .died marker, classified before this. Callers:
# _lanes_lane_json (status-read.sh) and _lanes_quick_state (status.sh); _lanes_epoch is status-read.sh's.
_lanes_resume_in_flight() {
  local last id af at e g="${LOOMWRIGHT_LANES_RESUME_GRACE_S:-120}"
  case "$g" in ''|*[!0-9]*) g=120 ;; esac
  # the log's TAIL only (cheap enough for the Stop hook's _lanes_quick_state): with no live process and no
  # .died marker nothing has run since the deferred exit, so its result line is among the last lines
  last="$(tail -n 50 "$1" 2>/dev/null | grep '^{' | jq -c -R 'fromjson? | select(.type == "result")' 2>/dev/null | tail -1)"
  [ "$(jq -r '.stop_reason // empty' <<<"$last" 2>/dev/null)" = tool_deferred ] || return 1
  id="$(jq -r '.deferred_tool_use.id // empty' <<<"$last" 2>/dev/null)"
  case "$id" in ''|*[!A-Za-z0-9_-]*) return 1 ;; esac
  af="$2/answers/$id.json"; [ -f "$af" ] || return 1
  at="$(jq -r '.at // empty' "$af" 2>/dev/null)"
  if [ "${4:-}" != any ]; then
    e="$(_lanes_epoch "$at")" || return 1
    [ "$(($3 - e))" -le "$g" ] || return 1
  fi
  printf '%s (written %s)' "$id" "${at:-?}"
}

# _lanes_pending_questions <inbox> — THE pending-question reader: every recorded question id with no
# answer file, one per line. Every reader goes through it (_lanes_pending_question, lane-status's
# questions array — so lane-wait and the /lanes pane — `--inbox`, the lane-wait Stop hook). A question
# the lane abandoned and re-asked was moved to questions/superseded/ (_lanes_supersede_older), which
# the `questions/*.json` glob never matches.
_lanes_pending_questions() {
  local q id
  for q in "$1"/questions/*.json; do
    [ -f "$q" ] || continue
    id="$(basename "$q" .json)"
    [ -e "$1/answers/$id.json" ] || printf '%s\n' "$id"
  done
}

# _lanes_pending_question <inbox> — prints the first pending question id; returns 1 when there is none.
_lanes_pending_question() {
  local id; id="$(_lanes_pending_questions "$1" | head -1)"
  [ -n "$id" ] || return 1
  printf '%s' "$id"
}

# _lanes_supersede_older <lane_root> <new_id> — THE supersede rule, applied by relay-hook when it records
# a question: a lane runs ONE session and a deferred question ends its process, so a NEW question
# (another tool_use_id) from the lane means every older unanswered one was abandoned — the session
# ended a plain turn and re-asked (L8, 2026-10-16), or a bundled call was denied and re-asked. Each
# moves to questions/superseded/<id>.json (the record is kept, never deleted) with `superseded_by` and
# `superseded_at` added, and ONE lane `## Progress` line names them. A resume re-fires the SAME id after
# its answer, so a question never supersedes itself. Fail-SAFE: a failed move leaves the question
# pending, a failed annotation or Progress append is skipped, and nothing here blocks the hook's reply.
_lanes_supersede_older() {
  local root="$1" new="$2" inbox="$1/.supervisor/inbox" sd old ids="" run
  sd="$inbox/questions/superseded"
  while IFS= read -r old; do
    [ -n "$old" ] && [ "$old" != "$new" ] || continue
    mkdir -p "$sd" 2>/dev/null && mv -f "$inbox/questions/$old.json" "$sd/$old.json" 2>/dev/null || continue
    jq -c --arg by "$new" --arg at "$(now_utc)" '. + {superseded_by: $by, superseded_at: $at}' "$sd/$old.json" \
      > "$sd/$old.json.tmp.$$" 2>/dev/null && mv "$sd/$old.json.tmp.$$" "$sd/$old.json" || rm -f "$sd/$old.json.tmp.$$"
    ids="$ids${ids:+, }$old"
  done <<EOF
$(_lanes_pending_questions "$inbox")
EOF
  [ -n "$ids" ] || return 0
  run="$(jq -r '.run_id // empty' "$root/.supervisor/lane.json" 2>/dev/null)"
  case "$run" in ''|*/*|.*) return 0 ;; esac
  bash "$HELPERS" progress-append "$root/.supervisor/automate/$run.md" \
    "$(now_utc) question superseded: $ids by $new (the lane re-asked; record kept in .supervisor/inbox/questions/superseded/)" >/dev/null 2>&1 || true
  return 0
}

# _lanes_superseded_by <inbox> <id> — 0 when <id> was superseded (no live question file, a record under
# questions/superseded/); prints the newer id, or nothing when the record names none (a hand move).
_lanes_superseded_by() {
  [ -f "$1/questions/superseded/$2.json" ] && [ ! -f "$1/questions/$2.json" ] || return 1
  jq -r '.superseded_by // empty' "$1/questions/superseded/$2.json" 2>/dev/null
  return 0
}

# _lanes_superseded_msg <inbox> <id> — the refusal text for a superseded id, or returns 1.
_lanes_superseded_msg() {
  local by; by="$(_lanes_superseded_by "$1" "$2")" || return 1
  if [ -n "$by" ]; then printf '%s superseded by %s (the lane re-asked; answer %s)' "$2" "$by" "$by"
  else printf '%s superseded by a newer question (its record names none)' "$2"; fi
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

