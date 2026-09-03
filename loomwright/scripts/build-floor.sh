#!/usr/bin/env bash
# build-floor.sh - deterministic, READ-ONLY projector of the scattered .supervisor/ and
# .agent/ surfaces into ONE versioned artefact: .supervisor/floor/floor.json.
#
# WHY: the state a view needs is already on disk, but spread across FOURTEEN projected
# surfaces in five formats (markdown tables, YAML frontmatter, folder membership, JSONL,
# JSON). Counting basis for the fourteen: one key under `surfaces` in floor.json, which is
# not the same as the number of directories read - the four jobs/ lifecycle folders are four
# surfaces, while logs/*.jsonl yields two (`logs` counts files, `sessions` reads their
# contents). If every view parses those inputs itself, every view re-implements the same
# parsers and drifts independently. Exactly one thing should read them. That is this script;
# floor.json is the contract.
#
# DISCIPLINE (mirrors build-insights.sh / build-handoff.sh, the two sibling projectors):
#   * set -uo pipefail with NO set -e.
#   * a `command -v jq` guard that SKIPS rather than fails.
#   * exit 0 ALWAYS - a projector must never break its caller.
#   * READ-ONLY on every input. The only path written is .supervisor/floor/floor.json.
#     No temp files, no lock files, no redirects outside that one directory.
#
# EVIDENCE-ONLY DERIVATION: a projector that guesses is the same lie in a new place. Every
# number carries the glob or predicate that produced it (`basis`), and evidence we do not
# have is OMITTED rather than defaulted. A consumer must be able to render "unknown"; it
# must never be handed a fabricated zero. Concretely: when a surface cannot be counted the
# `count` key is ABSENT (not 0) and `reason` names why, and an input we could not fully
# parse reports status `unverified` - never `counted`.
#
# COUNTING BASIS: `.supervisor/logs/` holds 99 directory entries but only 65 `*.jsonl`
# session logs - the rest are plain `.log` dispatch transcripts. Both readings are
# defensible and they differ by 34, so a bare number is already ambiguous. Every count in
# floor.json therefore states its own basis inline.
#
# SESSION SEGMENTATION is by the `cc_session_id` FIELD, never by filename. A log file is
# named for a `state.md` `status:` that can read `running` for weeks, so one file routinely
# spans many real sessions across many branches; `cc_session_id` is already additive on
# every event and segments cleanly with no emitter change.
#
# DETERMINISM: the script reads the wall clock EXACTLY ONCE (the sole `date` invocation
# below, overridable via FLOOR_SOURCE_DATE_EPOCH for reproducible builds and tests). Every
# enumeration is LC_ALL=C sorted and the output is emitted with `jq -S`, so two runs over an
# unchanged tree differ only in `generated_at_epoch`. Timestamps elsewhere in the artefact
# are file mtimes - properties of the inputs, not of the run.
#
# Usage:  build-floor.sh
#   env FLOOR_SOURCE_DATE_EPOCH=<unix seconds>  pin the generation stamp (reproducible runs)
# Exit:   0 always. Prints the output path.

set -uo pipefail

# Resolved BEFORE the `cd` below, and that order is load-bearing: `$0` is frequently a
# RELATIVE path (`bash loomwright/scripts/build-floor.sh`), and resolving it after changing
# directory would silently point at whatever `../agents` means from the new cwd. This is the
# plugin's own install directory, never a repo-relative path - it is the one input that lives
# beside the script rather than beside the project.
SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
PLUGIN_ROOT=""
[ -n "$SELF_DIR" ] && PLUGIN_ROOT="$(cd "$SELF_DIR/.." 2>/dev/null && pwd)"

GITROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$GITROOT" 2>/dev/null || true

command -v jq >/dev/null 2>&1 || {
  echo "build-floor: jq required - skipping, no floor.json written" >&2
  exit 0
}

OUT_DIR=".supervisor/floor"
OUT="$OUT_DIR/floor.json"
SCHEMA_VERSION=1

shopt -s nullglob

# ---------------------------------------------------------------------------
# Clock: THE single wall-clock read in this script. Everything else is derived
# from file mtimes (properties of the inputs) so re-runs stay byte-identical.
# FLOOR_SOURCE_DATE_EPOCH (SOURCE_DATE_EPOCH-style seam) pins it. Non-numeric or
# unreadable => null, never a plausible default.
# ---------------------------------------------------------------------------
now_epoch="${FLOOR_SOURCE_DATE_EPOCH:-}"
case "$now_epoch" in
  ''|*[!0-9]*) now_epoch="$(date -u +%s 2>/dev/null)" ;;
esac
case "$now_epoch" in
  ''|*[!0-9]*) now_epoch="" ;;
esac

repo_head="$(git rev-parse --short HEAD 2>/dev/null || true)"
case "$repo_head" in *[!0-9a-f]*) repo_head="" ;; esac

# ---------------------------------------------------------------------------
# Portable mtime -> epoch seconds. Copied in SHAPE from build-handoff.sh's
# mtime_epoch(): GNU `stat -c %Y` FIRST, BSD/macOS `stat -f %m` second. The order
# is load-bearing - on GNU coreutils `-f` means "filesystem status" and succeeds
# printing a MOUNT POINT, so a BSD-first probe returns a non-numeric string on
# Linux and the caller does arithmetic on garbage. This repo shipped exactly that
# bug once (macOS green, Linux CI red).
#
# NOT copied: build-handoff.sh's CALL SITES, which do `e="${e:-0}"`. Defaulting an
# unverifiable mtime to 0 (the Unix epoch) is precisely the plausible default this
# projector exists to refuse. Empty here means OMIT the field upstream.
# ---------------------------------------------------------------------------
mtime_epoch() {
  local f="$1" e=""
  e="$(stat -c %Y "$f" 2>/dev/null || true)"
  [ -n "$e" ] || e="$(stat -f %m "$f" 2>/dev/null || true)"
  case "$e" in
    ''|*[!0-9]*) e="" ;;
  esac
  printf '%s' "$e"
}

SURF=""
NOTES=""

add_note() { NOTES="${NOTES}$1
"; }

# surface_obj <key> <source> <basis> <status> <count> <reason> <mtime> <detail_json>
# The assembly, in ONE place, so add_surface below can call it twice - with the caller's
# detail and, if that produced nothing, without it. An empty count / reason / mtime / detail
# OMITS that key entirely.
surface_obj() {
  jq -cn \
      --arg k "$1" --arg source "$2" --arg basis "$3" --arg status "$4" \
      --arg count "$5" --arg reason "$6" --arg mt "$7" --arg detail "$8" '
    {k: $k,
     v: ({source: $source, basis: $basis, status: $status}
         + (if $count  == "" then {} else {count:       ($count | tonumber)} end)
         + (if $reason == "" then {} else {reason:      $reason}             end)
         + (if $mt     == "" then {} else {mtime_epoch: ($mt    | tonumber)} end)
         + (if $detail == "" then {} else {detail:      ($detail | fromjson)} end))}
  ' 2>/dev/null
}

# add_surface <key> <source> <basis> <status> [count] [reason] [mtime] [detail_json]
# An empty count / reason / mtime / detail OMITS that key entirely.
#
# A `detail` that will not parse costs the caller its detail and NOTHING ELSE. Before the
# retry below this function returned silently on that path, which deleted the entire surface -
# source, basis, status and the proven count with it - over one bad OPTIONAL field, and said
# so nowhere: the key was simply missing from `surfaces`, indistinguishable from a surface
# that was never attempted. A projector that refuses to fabricate evidence has to equally
# refuse to discard evidence it already holds; the note names the key and the reason.
add_surface() {
  local k="$1" src="$2" basis="$3" status="$4"
  local count="${5:-}" reason="${6:-}" mt="${7:-}" detail="${8:-}"
  local obj
  obj="$(surface_obj "$k" "$src" "$basis" "$status" "$count" "$reason" "$mt" "$detail")"
  if [ -z "$obj" ] && [ -n "$detail" ]; then
    add_note "$k detail dropped: the detail payload for $k is not valid JSON - the surface is emitted without it"
    obj="$(surface_obj "$k" "$src" "$basis" "$status" "$count" "$reason" "$mt" "")"
  fi
  [ -n "$obj" ] || return 0
  SURF="${SURF}${obj}
"
}

# count_glob <key> <dir> <basis> <files...>
# Shared path for the "how many files match this glob" surfaces. An absent parent
# directory is `absent` with a named reason and NO count.
count_glob() {
  local k="$1" dir="$2" basis="$3"; shift 3
  local n=$#
  if [ ! -d "$dir" ]; then
    add_note "$k omitted: input directory $dir is not present"
    add_surface "$k" "$dir" "$basis" "absent" "" "input directory $dir is not present"
    return 0
  fi
  if [ ! -r "$dir" ]; then
    add_note "$k unverified: input directory $dir is not readable"
    add_surface "$k" "$dir" "$basis" "unverified" "" "input directory $dir is not readable"
    return 0
  fi
  add_surface "$k" "$dir" "$basis" "counted" "$n" "" "$(mtime_epoch "$dir")"
}

# ---------------------------------------------------------------------------
# 1) .supervisor/state.md - phase / branch / subtask table
# ---------------------------------------------------------------------------
STATE=".supervisor/state.md"
state_basis="rows matching a leading numeric cell inside the ## Subtasks table of $STATE"
if [ ! -f "$STATE" ]; then
  add_note "state omitted: $STATE is not present"
  add_surface "state" "$STATE" "$state_basis" "absent" "" "$STATE is not present"
elif [ ! -r "$STATE" ]; then
  add_note "state unverified: $STATE is not readable"
  add_surface "state" "$STATE" "$state_basis" "unverified" "" "$STATE is not readable"
else
  # ONE awk pass emits the rows; the count is their number. Two passes (one counting, one
  # listing) could disagree about what a row IS, and the artefact would then carry a count and
  # a list that contradict each other with no way to tell which was right.
  st_table="$(awk '
    /^## Subtasks/ {f=1; next}
    f && /^## /    {exit}
    f && /^\|[[:space:]]*[0-9]+[[:space:]]*\|/ {
      n = split($0, c, "|")
      id = c[2]; title = (n >= 3 ? c[3] : ""); status = (n >= 4 ? c[4] : "")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", title)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", status)
      printf "%s\t%s\t%s\n", id, title, status
    }
  ' "$STATE" 2>/dev/null)"
  st_rows="$(printf '%s\n' "$st_table" | awk 'NF{n++} END{print n+0}')"
  case "$st_rows" in ''|*[!0-9]*) st_rows="" ;; esac

  # A cell the table does not have is OMITTED from its row, not filled in: a subtask table
  # with no Status column says nothing about status, and `PENDING` there would be this
  # projector inventing the very thing it exists to stop inventing.
  subtasks_rows="$(printf '%s' "$st_table" | jq -R -s -c '
    split("\n") | map(select(length > 0)) | map(split("\t"))
    | map({}
        + (if (.[0] // "") == "" then {} else {id:     .[0]} end)
        + (if (.[1] // "") == "" then {} else {title:  .[1]} end)
        + (if (.[2] // "") == "" then {} else {status: .[2]} end))
  ' 2>/dev/null)"
  case "$subtasks_rows" in ''|'[]') subtasks_rows="null" ;; esac
  st_field() {
    awk -v key="$1" '
      /^## Session/ {f=1; next}
      f && /^## /   {exit}
      f {
        pat = "^- " key ":[[:space:]]*"
        if ($0 ~ pat) { sub(pat, "", $0); print $0; exit }
      }
    ' "$STATE" 2>/dev/null | head -1
  }
  st_detail="$(jq -cn \
      --arg phase "$(st_field phase)" --arg branch "$(st_field branch)" \
      --arg status "$(st_field status)" --arg sid "$(st_field session_id)" \
      --argjson subtasks "$subtasks_rows" '
    {} + (if $phase  == "" then {} else {phase:      $phase}  end)
       + (if $branch == "" then {} else {branch:     $branch} end)
       + (if $status == "" then {} else {run_status: $status} end)
       + (if $sid    == "" then {} else {session_id: $sid}    end)
       + (if $subtasks == null then {} else {subtasks: $subtasks} end)
  ' 2>/dev/null)"
  [ "$st_detail" = "{}" ] && st_detail=""
  if [ -z "$st_rows" ]; then
    add_note "state count omitted: could not parse the ## Subtasks table in $STATE"
    add_surface "state" "$STATE" "$state_basis" "unverified" "" \
      "could not parse the ## Subtasks table" "$(mtime_epoch "$STATE")" "$st_detail"
  else
    add_surface "state" "$STATE" "$state_basis" "counted" "$st_rows" "" \
      "$(mtime_epoch "$STATE")" "$st_detail"
  fi
fi

# ---------------------------------------------------------------------------
# 2) .supervisor/jobs/{pending,in-progress,done,failed}/ - the brief pipeline
# ---------------------------------------------------------------------------
for lc in pending in-progress done failed; do
  key="jobs_$(printf '%s' "$lc" | tr '-' '_')"
  count_glob "$key" ".supervisor/jobs/$lc" \
    "files matching .supervisor/jobs/$lc/*.md" .supervisor/jobs/"$lc"/*.md
done

# ---------------------------------------------------------------------------
# 3) .supervisor/automate/ - engine run files
# ---------------------------------------------------------------------------
count_glob "automate_runs" ".supervisor/automate" \
  "files matching .supervisor/automate/*.md, which excludes the sibling *.config-backup.json transients" \
  .supervisor/automate/*.md

# ---------------------------------------------------------------------------
# 4) .supervisor/logs/*.jsonl - the event stream (the counting-basis case in point)
# ---------------------------------------------------------------------------
LOGS_DIR=".supervisor/logs"
logs_basis="files matching .supervisor/logs/*.jsonl, an extension glob; the same directory also holds plain .log dispatch transcripts which are deliberately NOT counted here"
logfiles=("$LOGS_DIR"/*.jsonl)
# `${arr[@]+"${arr[@]}"}`, not a bare `"${arr[@]}"`: under `set -u` macOS bash 3.2 treats an
# EMPTY array expansion as an unbound variable and aborts the script with status 1. That is
# not a corner case here - it is every fresh clone, every git worktree and every user who has
# not run the plugin yet, i.e. exactly the trees where `*.jsonl` matches nothing. It would
# have broken this script's headline exit-0-always invariant while staying INVISIBLE on Linux
# CI (bash 4+ expands an empty array happily) - the exact inverse of the stat-flavour trap.
count_glob "logs" "$LOGS_DIR" "$logs_basis" ${logfiles[@]+"${logfiles[@]}"}

# ---------------------------------------------------------------------------
# 5) sessions - distinct cc_session_id across every *.jsonl, NEVER by filename
# ---------------------------------------------------------------------------
sess_basis="distinct non-empty cc_session_id values across every line of .supervisor/logs/*.jsonl, grouped by that FIELD and never by filename, so one file may contribute many sessions and one session may span many files"
# READABILITY FIRST, decided BEFORE the branch chain below. `cat ... 2>/dev/null` swallows a
# read failure, so an unreadable log (or a directory that merely happens to be named `*.jsonl`)
# was silently DROPPED and this surface reported `counted` with an UNDERCOUNT plus
# `lines_malformed: 0` - actively asserting cleanliness about bytes it never saw, which is
# worse than reporting nothing at all. state.md (`! -r`), postmortem (`! -r`) and count_glob
# (`! -r`) all guard this; the bulk reader here was the one that did not. Harmless to run when
# the directory is absent: the array is empty and the loop body never executes.
log_unreadable=""
for lf in ${logfiles[@]+"${logfiles[@]}"}; do
  if [ ! -f "$lf" ]; then log_unreadable="$lf is not a regular file"; break; fi
  if [ ! -r "$lf" ]; then log_unreadable="$lf is not readable";       break; fi
done

if [ ! -d "$LOGS_DIR" ]; then
  add_note "sessions omitted: input directory $LOGS_DIR is not present"
  add_surface "sessions" "$LOGS_DIR" "$sess_basis" "absent" "" \
    "input directory $LOGS_DIR is not present"
elif [ ${#logfiles[@]} -eq 0 ]; then
  add_note "sessions omitted: no files match $LOGS_DIR/*.jsonl"
  add_surface "sessions" "$LOGS_DIR" "$sess_basis" "absent" "" \
    "no files match $LOGS_DIR/*.jsonl"
elif [ -n "$log_unreadable" ]; then
  add_note "sessions unverified: $log_unreadable"
  add_surface "sessions" "$LOGS_DIR" "$sess_basis" "unverified" "" "$log_unreadable"
else
  # Classify every raw line exactly once: blank / malformed / carries an id / lacks one.
  # `try ... catch` keeps a malformed line VISIBLE instead of silently dropping it.
  #
  # `awk 1 "$f"` per file, NOT one bulk `cat`: a file whose last record has no trailing newline
  # is spliced by `cat` onto the first record of the NEXT file, destroying TWO valid records
  # and reporting the splice as a malformed line - the reader blaming its inputs for its own
  # defect. `awk 1` is the terse "print every line", which terminates each file's final line.
  classified="$(for lf in ${logfiles[@]+"${logfiles[@]}"}; do awk 1 "$lf" 2>/dev/null; done | jq -R -r '
    if ((. | gsub("\\s"; "")) == "") then "blank"
    else
      (try (fromjson) catch null) as $o
      | if ($o | type) != "object" then "malformed"
        elif ($o | has("cc_session_id"))
             and (($o.cc_session_id | type) == "string")
             and (($o.cc_session_id | length) > 0)
          then "id\t" + $o.cc_session_id + "\t" +
               ({sid: $o.cc_session_id, ts: $o.ts, agent_id: $o.agent_id,
                 agent_type: $o.agent_type, branch: $o.branch}
                | with_entries(select(.value != null and .value != "")) | tojson)
        else "noid" end
    end
  ' 2>/dev/null)"

  sess_total="$(printf '%s\n' "$classified"   | awk 'NF{n++} END{print n+0}')"
  sess_blank="$(printf '%s\n' "$classified"   | awk '$0=="blank"{n++} END{print n+0}')"
  sess_bad="$(printf '%s\n' "$classified"     | awk '$0=="malformed"{n++} END{print n+0}')"
  sess_noid="$(printf '%s\n' "$classified"    | awk '$0=="noid"{n++} END{print n+0}')"
  sess_withid="$(printf '%s\n' "$classified"  | awk '/^id\t/{n++} END{print n+0}')"
  sess_distinct="$(printf '%s\n' "$classified" \
    | awk -F'\t' '/^id\t/{print $2}' | LC_ALL=C sort -u | awk 'NF{n++} END{print n+0}')"

  sess_lines=$((sess_total - sess_blank))

  # -------------------------------------------------------------------------
  # The NEWEST-SESSION view. Built from the SAME classified lines the counts came from - the
  # third field each id line already carries - so the log files are read exactly once. A
  # second `cat` over .supervisor/logs/*.jsonl would re-read megabytes to answer a question
  # the first pass already had the evidence for, and the two readings could disagree.
  #
  # The session is picked by the newest `ts` ON A RECORD, never by file order or filename:
  # a log file is named for a `state.md` status that can read `running` for weeks, so the
  # last file is not the latest session and the last line is not the latest event. When no
  # record carries a `ts` at all the view is OMITTED with a note - the ordering the shell's
  # glob happens to produce is not evidence of recency.
  #
  # `events` counts every line the agent appears on, including one with no `ts`; `first_ts`
  # and `last_ts` span only the lines that carried one, and are omitted when none did.
  # `agent_type` and `branch` are additive fields present on only some events, so they are
  # taken from ANY line of that agent and omitted when no line carried them.
  sess_current="$(printf '%s\n' "$classified" | awk -F'\t' '/^id\t/{print $3}' | jq -s -c '
    map(select(type == "object")) as $all
    | ($all | map(select(has("ts"))) | sort_by(.ts | tostring) | last) as $newest
    | if $newest == null then null
      else
        ($newest.sid) as $s
        | ($all | map(select(.sid == $s))) as $cur
        | ($cur | map(select(has("agent_id")))) as $ev
        | {cc_session_id: $s, last_event_ts: $newest.ts}
          + (if ($ev | length) == 0 then {}
             else {agents: ($ev | group_by(.agent_id) | map(
                     (map(select(has("ts")) | .ts)) as $tss
                     | {agent_id: .[0].agent_id, events: length}
                       + (if ($tss | length) == 0 then {}
                          else {first_ts: ($tss | min), last_ts: ($tss | max)} end)
                       + ((map(select(has("agent_type")) | .agent_type) | first) as $t
                          | if $t == null then {} else {agent_type: $t} end)
                       + ((map(select(has("branch")) | .branch) | first) as $b
                          | if $b == null then {} else {branch: $b} end)
                   ) | sort_by(.agent_id))}
             end)
      end' 2>/dev/null)"
  case "$sess_current" in ''|'null') sess_current="null" ;; esac
  if [ "$sess_current" = "null" ]; then
    add_note "sessions current omitted: no line under $LOGS_DIR/*.jsonl carries a ts, so the newest session cannot be identified from the events themselves (file order is not evidence of recency)"
  fi

  sess_detail="$(jq -cn \
      --argjson lines "$sess_lines" --argjson blank "$sess_blank" \
      --argjson malformed "$sess_bad" --argjson without "$sess_noid" \
      --argjson with "$sess_withid" --argjson current "$sess_current" '
    {lines_scanned: $lines, lines_blank_skipped: $blank, lines_malformed: $malformed,
     lines_with_session_id: $with, lines_without_session_id: $without}
    + (if $current == null then {} else {current: $current} end)' 2>/dev/null)"

  if [ "$sess_bad" -gt 0 ]; then
    # A line we cannot parse may carry an id we cannot see, so the distinct count is
    # not provable. Report unverified and OMIT the count - never "clean".
    add_note "sessions count omitted: $sess_bad unparseable line(s) under $LOGS_DIR/*.jsonl mean the distinct session count cannot be proven"
    add_surface "sessions" "$LOGS_DIR" "$sess_basis" "unverified" "" \
      "$sess_bad unparseable line(s) - a line that will not parse may carry a session id that cannot be seen" \
      "" "$sess_detail"
  elif [ "$sess_withid" -eq 0 ]; then
    add_note "sessions omitted: no line under $LOGS_DIR/*.jsonl carries a cc_session_id"
    add_surface "sessions" "$LOGS_DIR" "$sess_basis" "absent" "" \
      "no line carries a cc_session_id" "" "$sess_detail"
  else
    add_surface "sessions" "$LOGS_DIR" "$sess_basis" "counted" "$sess_distinct" "" \
      "" "$sess_detail"
  fi
fi

# ---------------------------------------------------------------------------
# 6) .supervisor/insights/runs/ - one note per summarized run
# ---------------------------------------------------------------------------
count_glob "insights_runs" ".supervisor/insights/runs" \
  "files matching .supervisor/insights/runs/*.md, one note per summarized run" \
  .supervisor/insights/runs/*.md

# ---------------------------------------------------------------------------
# 7) .supervisor/postmortem/results.jsonl - the review-churn ledger
# ---------------------------------------------------------------------------
PM=".supervisor/postmortem/results.jsonl"
pm_basis="non-blank lines in $PM that parse as a JSON object, one record per line"
if [ ! -f "$PM" ]; then
  add_note "postmortem omitted: $PM is not present"
  add_surface "postmortem" "$PM" "$pm_basis" "absent" "" "$PM is not present"
elif [ ! -r "$PM" ]; then
  add_note "postmortem unverified: $PM is not readable"
  add_surface "postmortem" "$PM" "$pm_basis" "unverified" "" "$PM is not readable"
else
  pm_class="$(jq -R -r '
    if ((. | gsub("\\s"; "")) == "") then "blank"
    else ((try (fromjson) catch null) as $o
          | if ($o | type) == "object" then "ok" else "malformed" end)
    end' "$PM" 2>/dev/null)"
  pm_ok="$(printf '%s\n'  "$pm_class" | awk '$0=="ok"{n++} END{print n+0}')"
  pm_bad="$(printf '%s\n' "$pm_class" | awk '$0=="malformed"{n++} END{print n+0}')"
  if [ "$pm_bad" -gt 0 ]; then
    add_note "postmortem count omitted: $pm_bad malformed line(s) in $PM"
    add_surface "postmortem" "$PM" "$pm_basis" "unverified" "" \
      "$pm_bad line(s) do not parse as a JSON object" "$(mtime_epoch "$PM")"
  else
    add_surface "postmortem" "$PM" "$pm_basis" "counted" "$pm_ok" "" "$(mtime_epoch "$PM")"
  fi
fi

# ---------------------------------------------------------------------------
# 8+9) JSON-document surfaces: drain rounds and the committed rules store.
# A malformed document makes the whole surface unverified, with the file named.
# ---------------------------------------------------------------------------
count_json_docs() {
  local k="$1" dir="$2" basis="$3"; shift 3
  local n=$#
  if [ ! -d "$dir" ]; then
    add_note "$k omitted: input directory $dir is not present"
    add_surface "$k" "$dir" "$basis" "absent" "" "input directory $dir is not present"
    return 0
  fi
  # BEFORE the n -eq 0 arm, and that order is the whole point: under `nullglob` an UNREADABLE
  # directory expands to zero arguments exactly like an empty one, so without this guard the
  # unreadable case falls through to "counted 0" and ships a proven-looking zero carrying an
  # `mtime_epoch` that implies a reading which never happened. Mirrors count_glob's guard.
  if [ ! -r "$dir" ]; then
    add_note "$k unverified: input directory $dir is not readable"
    add_surface "$k" "$dir" "$basis" "unverified" "" "input directory $dir is not readable"
    return 0
  fi
  if [ "$n" -eq 0 ]; then
    add_surface "$k" "$dir" "$basis" "counted" "0" "" "$(mtime_epoch "$dir")"
    return 0
  fi
  # `jq empty` — NOT `jq -e .`: with -e the exit status is taken from the last OUTPUT
  # value, so a perfectly valid document whose value is `null`, `false` or `0` exits 1 and
  # would be misreported as malformed. `empty` produces no output and fails only on a real
  # parse error. Bulk call first (one process for the whole surface, the fast path); only on
  # failure do we pay a per-file pass, because jq's bulk parse error does not name the file
  # and "the reason is named" requires naming the offender.
  local rc offender=""
  { jq empty "$@" >/dev/null; } 2>/dev/null
  rc=$?
  if [ "$rc" -ne 0 ]; then
    local f err
    for f in "$@"; do
      err="$( { jq empty "$f" >/dev/null; } 2>&1 )"
      if [ $? -ne 0 ]; then
        offender="$f - $(printf '%s\n' "$err" | head -1 | cut -c1-160)"
        break
      fi
    done
    [ -n "$offender" ] || offender="a document under $dir would not parse"
    add_note "$k count omitted: $offender"
    add_surface "$k" "$dir" "$basis" "unverified" "" \
      "at least one document does not parse as JSON: $offender" "$(mtime_epoch "$dir")"
    return 0
  fi
  add_surface "$k" "$dir" "$basis" "counted" "$n" "" "$(mtime_epoch "$dir")"
}

count_json_docs "drain_rounds" ".supervisor/drain-rounds" \
  "files matching .supervisor/drain-rounds/*.json, each parsed as a JSON document" \
  .supervisor/drain-rounds/*.json

count_glob "worker_summaries" ".supervisor/worker-summaries" \
  "files matching .supervisor/worker-summaries/*.md" \
  .supervisor/worker-summaries/*.md

count_json_docs "rules" ".agent/rules" \
  "files matching .agent/rules/*.json, each parsed as a JSON document; the sibling README.md is not counted" \
  .agent/rules/*.json

# ---------------------------------------------------------------------------
# 10) the agent roster - <plugin>/agents/*.md YAML frontmatter.
#
# The ONE input that is not repo-relative. Every other surface lives under the project being
# projected; this one lives beside the script, because the roster is a property of the
# INSTALLED PLUGIN and is identical for every project it runs in. FLOOR_AGENTS_DIR overrides
# it, which is what keeps the test suite hermetic: without an override the script would
# resolve its own install directory and report the real agent count against a fixture tree
# that has no agents at all.
#
# Only the FIRST frontmatter block is read (the awk stops at the closing `---`), so a `name:`
# or `color:` in the prose body can never be mistaken for one - the gen-color-legend.sh
# convention. Every field is OMITTED when the frontmatter does not state it, `read_only`
# included: "this file lists no disallowedTools" is a fact about the file, and `false` there
# would be a derivation from silence.
# ---------------------------------------------------------------------------
AGENTS_DIR="${FLOOR_AGENTS_DIR:-}"
if [ -z "$AGENTS_DIR" ] && [ -n "$PLUGIN_ROOT" ]; then AGENTS_DIR="$PLUGIN_ROOT/agents"; fi
agents_basis="files matching <plugin>/agents/*.md, one per agent role, with name / color / model / maxTurns / disallowedTools read from the YAML frontmatter between the first two --- lines; the directory is the plugin's own install path resolved from \$0 (overridable via FLOOR_AGENTS_DIR), NOT a repo-relative one"

# read_only is TRUE only when disallowedTools lists both Write and Edit as WHOLE TOKENS. A
# substring test matches `NotebookEdit` and would report an agent that can still edit files as
# read-only - the split on non-identifier characters is what makes the claim honest.
agent_row() {
  awk '
    NR==1 && $0 ~ /^---[[:space:]]*$/ { fm=1; next }
    fm && $0 ~ /^---[[:space:]]*$/    { exit }
    fm {
      if (match($0, /^[A-Za-z_]+:/)) {
        k = substr($0, 1, RLENGTH-1)
        v = substr($0, RLENGTH+1)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        gsub(/^"|"$/, "", v)
        if      (k == "name")            name  = v
        else if (k == "color")           color = v
        else if (k == "model")           model = v
        else if (k == "maxTurns")        turns = v
        else if (k == "disallowedTools") { dis = v; hasdis = 1 }
      }
    }
    END {
      ro = ""
      if (hasdis) {
        n = split(dis, t, /[^A-Za-z0-9_]+/)
        for (i = 1; i <= n; i++) { if (t[i] == "Write") w = 1; if (t[i] == "Edit") e = 1 }
        ro = (w && e) ? "true" : "false"
      }
      sub(/^loomwright:/, "", name)
      printf "%s\t%s\t%s\t%s\t%s\n", name, color, model, turns, ro
    }
  ' "$1" 2>/dev/null
}

agentfiles=()
[ -n "$AGENTS_DIR" ] && agentfiles=("$AGENTS_DIR"/*.md)
if [ -z "$AGENTS_DIR" ]; then
  add_note "agents omitted: the plugin agents directory could not be resolved from \$0 and FLOOR_AGENTS_DIR is unset"
  add_surface "agents" "unresolved" "$agents_basis" "absent" "" \
    "the plugin agents directory could not be resolved from \$0 and FLOOR_AGENTS_DIR is unset"
elif [ ! -d "$AGENTS_DIR" ]; then
  add_note "agents omitted: input directory $AGENTS_DIR is not present"
  add_surface "agents" "$AGENTS_DIR" "$agents_basis" "absent" "" \
    "input directory $AGENTS_DIR is not present"
elif [ ! -r "$AGENTS_DIR" ]; then
  add_note "agents unverified: input directory $AGENTS_DIR is not readable"
  add_surface "agents" "$AGENTS_DIR" "$agents_basis" "unverified" "" \
    "input directory $AGENTS_DIR is not readable"
else
  # Readability of every MEMBER, decided before any parsing: awk on an unreadable file prints
  # nothing and exits fine, so the roster would silently lose a row while the count - taken
  # from glob membership - still claimed it. Same guard, same reason, as the logs reader.
  agent_unreadable=""
  for af in ${agentfiles[@]+"${agentfiles[@]}"}; do
    if [ ! -f "$af" ]; then agent_unreadable="$af is not a regular file"; break; fi
    if [ ! -r "$af" ]; then agent_unreadable="$af is not readable";       break; fi
  done
  if [ -n "$agent_unreadable" ]; then
    add_note "agents unverified: $agent_unreadable"
    add_surface "agents" "$AGENTS_DIR" "$agents_basis" "unverified" "" "$agent_unreadable"
  else
    agent_tsv=""
    for af in ${agentfiles[@]+"${agentfiles[@]}"}; do
      agent_tsv="${agent_tsv}$(agent_row "$af")
"
    done
    agents_roster="$(printf '%s' "$agent_tsv" | LC_ALL=C sort | jq -R -s -c '
      split("\n") | map(select(length > 0)) | map(split("\t"))
      | map({}
          + (if (.[0] // "") == "" then {} else {name:  .[0]} end)
          + (if (.[1] // "") == "" then {} else {color: .[1]} end)
          + (if (.[2] // "") == "" then {} else {model: .[2]} end)
          + (if ((.[3] // "") | test("^[0-9]+$")) then {max_turns: (.[3] | tonumber)} else {} end)
          + (if   (.[4] // "") == "true"  then {read_only: true}
             elif (.[4] // "") == "false" then {read_only: false}
             else {} end))
    ' 2>/dev/null)"
    agents_detail=""
    case "$agents_roster" in
      ''|'[]') : ;;
      *) agents_detail="$(jq -cn --argjson roster "$agents_roster" '{roster: $roster}' 2>/dev/null)" ;;
    esac
    add_surface "agents" "$AGENTS_DIR" "$agents_basis" "counted" "${#agentfiles[@]}" "" \
      "$(mtime_epoch "$AGENTS_DIR")" "$agents_detail"
  fi
fi

# ---------------------------------------------------------------------------
# Assemble. jq -S sorts every key, so the byte layout is a function of the data
# alone. LC_ALL=C keeps that ordering locale-independent.
# ---------------------------------------------------------------------------
mkdir -p "$OUT_DIR" 2>/dev/null || {
  echo "build-floor: cannot create $OUT_DIR - skipping" >&2
  exit 0
}

notes_json="$(printf '%s' "$NOTES" | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null)"
# The fallback is deliberately NOT an empty array. Empty is a positive claim - "nothing was
# omitted" - and it would be made at exactly the moment that is unknown, because reaching here
# means the assembly itself failed. Emit a literal one-element array (no jq needed, since jq is
# what just failed) that says so; a consumer rendering notes[] then shows the doubt rather than
# a false all-clear. Written without spelling the empty-array literal, so that the source-level
# check in test-build-floor.sh cannot be satisfied - or tripped - by this comment.
[ -n "$notes_json" ] || notes_json='["notes unavailable: the notes list could not be assembled, so an empty notes array here would NOT mean nothing was omitted"]'

out_json="$(printf '%s' "$SURF" | LC_ALL=C jq -S --indent 2 -s \
    --argjson sv "$SCHEMA_VERSION" --arg ge "$now_epoch" \
    --arg gen "build-floor.sh" --arg head "$repo_head" --argjson notes "$notes_json" '
  {schema_version: $sv,
   generated_at_epoch: (if $ge == "" then null else ($ge | tonumber) end),
   generator: $gen,
   surfaces: (map({key: .k, value: .v}) | from_entries),
   notes: $notes}
  + (if $head == "" then {} else {repo_head: $head} end)
' 2>/dev/null)"

if [ -z "$out_json" ]; then
  echo "build-floor: could not assemble the projection - skipping, no floor.json written" >&2
  exit 0
fi

# Brace-grouped, because the command-level `2>/dev/null` is applied by the SHELL to `printf`'s
# own stderr and is therefore too late: bash opens the redirect first and prints its own
# `line NNN: ...: Permission denied` diagnostic before printf is ever executed. The group's
# redirection covers the failing redirect itself, so an unwritable output path yields only this
# script's own one-line message and the fail-safe exit 0.
{ printf '%s\n' "$out_json" > "$OUT"; } 2>/dev/null || {
  echo "build-floor: cannot write $OUT - skipping" >&2
  exit 0
}

echo "$OUT"
exit 0
