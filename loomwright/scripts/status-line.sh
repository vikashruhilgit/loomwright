#!/usr/bin/env bash
# status-line.sh — render ONE line describing what a Loomwright run is doing, for the host
# tool's status-line surface. Read-only, fail-safe, and it ALWAYS exits 0.
#
# WHY: the only way to know a run's phase was to open `.supervisor/state.md` by hand, which is
# exactly the thing a user will not do while a long run is in flight. This prints the four facts
# that answer "what is it doing and is it moving" and nothing else.
#
# OUTPUT (fields are omitted, never guessed, when their source is absent):
#   Loomwright · EXECUTE · feature/status-line · 3/4 · 2m ago
#     phase     — `- phase:` from state.md
#     branch    — `- branch:` from state.md, falling back to a read-only `git rev-parse`
#     N/M       — finished subtask rows / total rows in state.md's `## Subtasks` table
#                 (both table shapes that exist on disk are read — see "subtask progress" below)
#     age       — how long ago the newest session-log line was written
#   With no state file at all: `Loomwright · no run state`
#
# WHAT IS DELIBERATELY ABSENT — a live-role field.
#   There is no "currently running role" field here, and no code path infers liveness from the
#   recency of any log record. The emitter that would make such a field honest was investigated
#   and closed NO-GO, so no spawn event exists in any log; a field derived from record recency
#   would be a GUESS wearing the costume of a measurement — a log line proves something was
#   written, never that anything is running now. Omitted rather than guessed, per the repo's own
#   absent-evidence rule. test-status-line.sh asserts the absence mechanically (both in the
#   rendered output and as a source grep) so this comment cannot rot into a claim the code does
#   not back.
#
# TIME IS READ FROM THE RECORD, NEVER FROM THE FILESYSTEM.
#   The age field comes from the log line's own `ts` field. `stat -f %m` is BSD and SUCCEEDS
#   WITH GARBAGE on GNU/Linux, and `set -u` arithmetic on a non-numeric silently empties the
#   field — so this script calls `stat` nowhere at all. The ISO timestamp is parsed try-BSD-
#   then-GNU, both guarded, and the result is VALIDATED NUMERIC before any arithmetic. If
#   neither `date` flavour parses it, the age field is omitted entirely.
#   (The one mtime use is `ls -t` when picking a fallback log — `ls` does the comparison itself,
#   so no timestamp is ever parsed out of the filesystem.)
#
# NO HARD DEPENDENCIES. No `jq`, no `git` requirement (git is used only when available, and only
# read-only), no network. Every branch ends at exit 0: a status line that errors is worse than a
# status line that says less.
#
# USAGE
#   bash status-line.sh [--root <project-dir>]
#   The host passes a JSON blob on stdin; when it carries `workspace.current_dir` that value is
#   used as the project root. `--root` wins over stdin, and stdin over $PWD.
#
# Portability: bash 3.2 / BSD userland safe. No GNU-only flags, no associative arrays, no
# `${var//…}` pattern substitution, no `timeout`.

set -uo pipefail

ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) shift; ROOT="${1:-}" ;;
    *) : ;;  # fail-safe: an unknown flag is ignored, never fatal
  esac
  shift
done

# The host hands the status-line command a JSON object on stdin. Read it non-blockingly and
# only when stdin is not a terminal; a missing/short/blank read is normal and must not stall.
if [ -z "$ROOT" ] && [ ! -t 0 ]; then
  stdin_blob=""
  IFS= read -r -d '' -t 1 stdin_blob 2>/dev/null || true
  if [ -n "$stdin_blob" ]; then
    cand="$(printf '%s' "$stdin_blob" | grep -o '"current_dir"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"//; s/"$//')"
    [ -n "$cand" ] && [ -d "$cand" ] && ROOT="$cand"
  fi
fi
[ -n "$ROOT" ] || ROOT="$PWD"

STATE="$ROOT/.supervisor/state.md"
LOGDIR="$ROOT/.supervisor/logs"

# state_field <key> — the value of a `- <key>: <value>` line in state.md, or the empty string.
state_field() {
  [ -f "$STATE" ] || return 0
  awk -v k="$1" '
    $0 ~ ("^- " k ":") { sub(/^- [^:]*:[[:space:]]*/, ""); print; exit }
  ' "$STATE" 2>/dev/null
}

PHASE="$(state_field phase)"
BRANCH="$(state_field branch)"
STATUS="$(state_field status)"

# Branch fallback: read-only git, only when it is available and this is a work tree.
if [ -z "$BRANCH" ] && command -v git >/dev/null 2>&1; then
  BRANCH="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  [ "$BRANCH" = "HEAD" ] && BRANCH=""
fi

# ---- subtask progress -------------------------------------------------------
# Rows of the `## Subtasks` table only.
#
# TWO TABLE SHAPES EXIST ON DISK, and this reader tolerates BOTH.
#   Shape A — `| # | Title | Status | Review |`, bare-integer ids, statuses like
#             `COMPLETED (36c39de)`. This is the live `.supervisor/state.md` and 10 of the 17
#             files in `.supervisor/history/`.
#   Shape B — `| ID | Title | Status | Worker | Worktree | Review | Attempts |`, ids like `ST1`,
#             `subtask_1` or `BD-1.2`, lowercase `pending/in_progress/completed/failed`. This is
#             the other 7 history files, and what skills/state-management/SKILL.md documents.
# WHICH SHAPE IS AUTHORITATIVE IS AN UNRESOLVED OWNER DECISION that predates this script, and it
# is NOT settled here: this is a read-only consumer being made tolerant of both, not a vote. The
# earlier matcher required a leading NUMERIC cell, so it matched zero rows of Shape B and the
# field simply vanished — fail-safe, but a coverage gap.
#
# COLUMN CONTRACT (shared with reconcile-resume-state.sh): ID is data column 1 and Status is data
# column 3 — `c[2]` and `c[4]` after splitting on `|` — which holds for the 7-column schema, the
# 4-column form, and the abbreviated 3-column form alike. Status is matched as a COLUMN, never as
# a substring of the whole line: `$0 ~ /COMPLETED/` counted a subtask merely TITLED
# "Delete the COMPLETED marker handling" as finished. If that schema ever reorders, fix these
# indices — a mis-read Status is silent in both directions.
#
# NON-SUBTASK ROWS are dropped by the id cell: the `|---|---|` separator (a cell of only dashes
# and colons) and the header (`#` / `ID`). Everything else with a non-empty id AND a Status
# column counts, whatever its shape.
#
# A ROW WITH NO STATUS COLUMN IS NOT COUNTED AT ALL. Substituting an empty status and still
# incrementing the total renders `0/N` for a table this reader does not understand — a WRONG
# NUMBER, on a surface whose whole contract is that a field it cannot resolve is OMITTED rather
# than guessed. That is the same failure mode as the bare-literal `COMPLETED` test this widening
# replaced, merely relocated to a different input, so it is refused the same way: too few columns
# for a Status to exist means the row is skipped, the table degrades to 0 rows, and the field
# disappears from the line.
#
# DONE = SUCCESS-SHAPED TERMINAL STATUSES ONLY, a deliberate and tested divergence from the
# sibling's vocabulary. reconcile-resume-state.sh's `is_terminal_status` also treats
# FAILED/SKIPPED/ABANDONED as terminal, which is correct for its question ("is anything left to
# re-run?"). It is wrong for this one: `N/M` reads as progress toward a finished result, and
# rendering a failed subtask as done would present failure as success on a one-line surface that
# carries no other per-subtask signal. Those three count toward M and never toward N.
# Matching is case-insensitive and uses the status' FIRST WORD, so Shape B's `completed`,
# `DONE (review PASS)`, `COMPLETED (36c39de)` and `COMPLETED WITH ESCALATION` all count.
DONE=0
TOTAL=0
if [ -f "$STATE" ]; then
  counts="$(awk '
    /^## Subtasks/       { in_tbl=1; next }
    in_tbl && /^## /     { in_tbl=0 }
    in_tbl && /^[[:space:]]*\|/ {
      n = split($0, c, "[|]")
      # `| a | b |` splits into 4 fields — the empty strings outside the outer pipes count — so
      # `n < 5` means "no third data column", i.e. no Status cell to read. Omit, never guess.
      if (n < 5) next
      id = c[2]; gsub(/^[ \t]+|[ \t]+$/, "", id)
      st = c[4]; gsub(/^[ \t]+|[ \t]+$/, "", st)
      sub(/[ \t].*$/, "", st)          # first word: "COMPLETED (36c39de)" -> "COMPLETED"
      uid = toupper(id); ust = toupper(st)
      ok_id = (id != "" && id !~ /^[-:]+$/ && uid != "#" && uid != "ID")
      if (!ok_id) next
      total++
      is_done = (ust == "DONE" || ust == "DONE:" || ust == "COMPLETE" || ust == "COMPLETED" || ust == "MERGED")
      if (is_done) done++
    }
    END { printf "%d %d\n", done+0, total+0 }
  ' "$STATE" 2>/dev/null)"
  set -- $counts
  case "${1:-}" in ''|*[!0-9]*) : ;; *) DONE="$1" ;; esac
  case "${2:-}" in ''|*[!0-9]*) : ;; *) TOTAL="$2" ;; esac
fi

# ---- age of the newest logged event ----------------------------------------
# Source order: the log named by state.md's session_id (deterministic), else the newest .jsonl
# by `ls -t` (ls compares mtimes itself — no timestamp is parsed out of the filesystem).
LOGFILE=""
SID="$(state_field session_id)"
if [ -n "$SID" ] && [ -f "$LOGDIR/$SID.jsonl" ]; then
  LOGFILE="$LOGDIR/$SID.jsonl"
elif [ -d "$LOGDIR" ]; then
  LOGFILE="$(ls -t "$LOGDIR"/*.jsonl 2>/dev/null | head -1 || true)"
fi

# iso_to_epoch <ISO-8601-Z> — try BSD `date -j -f`, then GNU `date -d`. Echoes nothing when
# neither parses, so the caller's numeric validation is the single decision point.
iso_to_epoch() {
  local ts="$1" out
  out="$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null || true)"
  if [ -z "$out" ]; then
    out="$(date -u -d "$ts" +%s 2>/dev/null || true)"
  fi
  case "$out" in
    ''|*[!0-9]*) return 0 ;;   # not numeric -> emit nothing
    *) printf '%s' "$out" ;;
  esac
}

AGE=""
if [ -n "$LOGFILE" ] && [ -s "$LOGFILE" ]; then
  last_ts="$(grep -o '"ts"[[:space:]]*:[[:space:]]*"[^"]*"' "$LOGFILE" 2>/dev/null | tail -1 | sed 's/.*:[[:space:]]*"//; s/"$//')"
  if [ -n "$last_ts" ]; then
    then_epoch="$(iso_to_epoch "$last_ts")"
    now_epoch="$(date -u +%s 2>/dev/null || true)"
    case "${now_epoch:-x}" in ''|*[!0-9]*) now_epoch="" ;; esac
    # Both operands are validated numeric BEFORE the arithmetic runs; an unparseable
    # timestamp omits the field rather than emptying it into a `$(( ))`.
    if [ -n "$then_epoch" ] && [ -n "$now_epoch" ]; then
      delta=$(( now_epoch - then_epoch ))
      # A `ts` in the FUTURE (clock skew, a hand-edited record, a log written on another host)
      # cannot be aged honestly. Clamping the delta to 0 renders "0s ago", which PRESENTS a
      # record from the future as if it had just happened — a guess dressed as a reading, in a
      # script that otherwise omits every field it cannot resolve. So the field is OMITTED,
      # exactly as an unparseable `ts` is: the rest of the line still renders.
      if   [ "$delta" -lt 0 ];     then AGE=""
      elif [ "$delta" -lt 60 ];    then AGE="${delta}s ago"
      elif [ "$delta" -lt 3600 ];  then AGE="$(( delta / 60 ))m ago"
      elif [ "$delta" -lt 86400 ]; then AGE="$(( delta / 3600 ))h ago"
      else                              AGE="$(( delta / 86400 ))d ago"
      fi
    fi
  fi
fi

# ---- render -----------------------------------------------------------------
SEP=" · "
line="Loomwright"
add() { [ -n "${1:-}" ] && line="$line$SEP$1"; return 0; }

if [ ! -f "$STATE" ]; then
  # Degraded case 1: no state file. Say so plainly rather than printing a bare prefix.
  add "no run state"
else
  add "$PHASE"
  # A run that ended is worth distinguishing from one still in flight, but only when the
  # phase itself did not already say it.
  case "$STATUS" in
    ""|running) : ;;
    *) add "$STATUS" ;;
  esac
fi
add "$BRANCH"
[ "$TOTAL" -gt 0 ] && add "$DONE/$TOTAL"
add "$AGE"

# Degraded case 2: the state file exists but nothing in it parsed (unreadable/unexpected shape)
# and no other field resolved. Never print a bare prefix.
[ "$line" = "Loomwright" ] && line="Loomwright · no run state"

printf '%s\n' "$line"
exit 0
