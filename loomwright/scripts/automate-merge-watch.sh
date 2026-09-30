#!/usr/bin/env bash
# automate-merge-watch.sh — the `/automate` merge watcher. PROTOCOL AUTHORITY:
# `skills/automate-loop/SKILL.md` §6 "Post-merge close-out" (armed at §9's
# safe-mode `awaiting_merge` park, after trail-pr and before the lock release).
#
# Usage: automate-merge-watch.sh <runfile> <item> <pr_url>
#
# Pure bash, no Claude session, no tokens. The launcher detaches it:
#   env -u CLAUDE_PID -u CLAUDECODE nohup bash automate-merge-watch.sh \
#     <runfile> <item> <pr_url> </dev/null >"<runfile dir>/<run_id>.merge-watch.log" 2>&1 &
# (NOT setsid — absent on stock macOS). Polls `gh pr view <pr_url> --json
# state` every LOOMWRIGHT_MERGE_WATCH_INTERVAL seconds (default 60), doubling
# the wait on a gh error up to 900s and resetting on success.
#   MERGED ⇒ `automate-helpers.sh closeout <runfile> <item> <pr_url>` (NO
#            --session-id: it takes the run lock as `automate-closeout:<run_id>`).
#            Its output is classified, never assumed a success:
#              - TRANSIENT (`skipped — run lock held`, `skipped — gh
#                unavailable`, `skipped — pr not merged (…)` — the forge
#                contradicting this watcher's own MERGED read — or no output):
#                retried on a later poll with the gh-error backoff, within the
#                lifetime cap;
#              - any OTHER lone `closeout: skipped — …` guard line: terminal —
#                one ## Progress line + a notify naming it, exit;
#              - otherwise (closeout got past its guards): ONE success notify
#                (notify-desktop.sh + send-webhook.sh, both fail-safe), exit.
#   CLOSED ⇒ one `gone` ## Progress line + notify, exit — no cleanup (§4's
#            `gone` rules stand).
#   Lifetime cap LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS (default 259200 = 72h) ⇒
#            one ## Progress line, exit. When the watcher HAS read MERGED but
#            closeout kept returning a transient skip until the cap, the line
#            and a failure-style notify both say so and name the last skip
#            reason (never "resume after the merge" — the merge was observed).
# It never merges anything, never picks/RUNs a Queue item, never invokes
# `/autonomous`.
#
# SINGLE INSTANCE PER RUN: marker `<runfile dir>/<run_id>.merge-watch` (TSV
# pid/pr_url/started; gitignored under `.supervisor/automate/*` because it is
# not `*.md`). A live marker pid is trusted only after `ps -ww -p <pid> -o
# command=` shows an automate-merge-watch.sh process carrying the marker's
# pr_url (a recycled pid is never signalled — it is reclaimed as stale):
#   - same pr_url ⇒ `merge-watch: already running pid=<p>`, exit 0;
#   - a DIFFERENT pr_url (the run parked a later item) ⇒ the old watcher is
#     replaced: TERM (its trap removes its marker; sleeps are interruptible
#     `sleep & wait`), KILL only if it is still alive after 60s (e.g. mid-
#     closeout — the closeout child itself runs on), one `## Progress` line
#     naming the PR that is no longer watched, then this watcher starts;
#   - `ps` unavailable ⇒ cannot verify ⇒ `already running … (cannot verify)`.
# A dead pid ⇒ reclaimed. The marker is removed on every exit of the owning
# watcher (EXIT trap; TERM/INT/HUP exit through it), and a launch only ever
# removes the marker it inspected.
#
# CLAUDE_PID / CLAUDECODE are unset HERE as well as by the launcher: with them
# set, run-lock.sh would record the launching Claude session as the lock
# holder, and a closeout that died without its trap would leave a lock nobody
# can reclaim while that session lives. Unset, run-lock.sh records
# `pid_source ppid` — the closeout process — reclaimable after it dies
# (dead pid + the 1800s TTL).
#
# Always exits 0. bash 3.2 / BSD-userland safe (no `timeout`; `sleep` only).
# Seams: LOOMWRIGHT_GH_BIN, LOOMWRIGHT_JQ_BIN (same as automate-helpers.sh).

set -uo pipefail
unset CLAUDE_PID CLAUDECODE

GH="${LOOMWRIGHT_GH_BIN:-gh}"
JQ="${LOOMWRIGHT_JQ_BIN:-jq}"
HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"

runfile="${1:-}"; item="${2:-}"; pr_url="${3:-}"
if [ -z "$runfile" ] || [ -z "$item" ] || [ -z "$pr_url" ]; then
  echo "merge-watch: skipped — usage: automate-merge-watch.sh <runfile> <item> <pr_url>"; exit 0
fi
if [ ! -f "$runfile" ]; then echo "merge-watch: skipped — run file not found"; exit 0; fi
rf_dir="$(cd "$(dirname "$runfile")" 2>/dev/null && pwd -P)" || { echo "merge-watch: skipped — run file not found"; exit 0; }
rf_abs="$rf_dir/$(basename "$runfile")"
run_id="$(basename "$runfile" .md)"
MARKER="$rf_dir/$run_id.merge-watch"
root="$(git -C "$rf_dir" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$root" ] && cd "$root" 2>/dev/null

interval="${LOOMWRIGHT_MERGE_WATCH_INTERVAL:-60}"
case "$interval" in ''|*[!0-9]*) interval=60 ;; esac
max="${LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS:-259200}"
case "$max" in ''|*[!0-9]*) max=259200 ;; esac
BACKOFF_CAP=900

now() { date +%s; }
iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

progress() { bash "$HERE/automate-helpers.sh" progress-append "$rf_abs" "$(iso) merge-watch: $1" >/dev/null 2>&1; return 0; }
notify() {
  local msg="$1" payload
  payload="$("$JQ" -cn --arg m "$msg" '{hook_event_name:"Notification",notification_type:"automate_merge_watch",message:$m}' 2>/dev/null)"
  [ -n "$payload" ] && printf '%s' "$payload" | bash "$HERE/notify-desktop.sh" >/dev/null 2>&1 </dev/null
  bash "$HERE/send-webhook.sh" --event-type gate --gate-type automate_merge_watch --context "$msg" >/dev/null 2>&1 </dev/null
  return 0
}
marker_field() { awk -F'\t' -v k="$1" '$1==k{print $2; exit}' "$MARKER" 2>/dev/null; }

# is_our_watcher <pid> <pr_url> — 0: <pid> is an automate-merge-watch.sh process
# watching <pr_url>; 1: it is not (a recycled pid, or already gone); 2: cannot
# tell (no `ps`). Only a 0 is ever signalled.
is_our_watcher() {
  local cmd
  [ -n "$2" ] || return 1
  command -v ps >/dev/null 2>&1 || return 2
  cmd="$(ps -ww -p "$1" -o command= 2>/dev/null)"
  case "$cmd" in *automate-merge-watch.sh*) ;; *) return 1 ;; esac
  case "$cmd" in *" $2"|*" $2 "*) return 0 ;; esac
  return 1
}

# ---- single instance (per run: one marker, one watched PR) -----------------
replaced=""
if [ -f "$MARKER" ]; then
  opid="$(marker_field pid)"; opr="$(marker_field pr_url)"
  case "$opid" in ''|*[!0-9]*) opid="" ;; esac
  if [ -n "$opid" ] && [ "$opid" != "$$" ] && kill -0 "$opid" 2>/dev/null; then
    is_our_watcher "$opid" "$opr"; v=$?
    if [ "$v" -eq 2 ]; then
      echo "merge-watch: already running pid=$opid (cannot verify it: ps unavailable)"; exit 0
    elif [ "$v" -eq 0 ] && [ "$opr" = "$pr_url" ]; then
      echo "merge-watch: already running pid=$opid"; exit 0
    elif [ "$v" -eq 0 ]; then
      # Our watcher, but for ANOTHER PR of this run: the run has moved on, so
      # replace it (TERM — its trap removes its marker; KILL only if it has not
      # exited within 60s, e.g. mid-closeout).
      kill -TERM "$opid" 2>/dev/null
      i=0; while kill -0 "$opid" 2>/dev/null && [ "$i" -lt 300 ]; do sleep 0.2; i=$((i + 1)); done
      if kill -0 "$opid" 2>/dev/null && is_our_watcher "$opid" "$opr"; then
        kill -KILL "$opid" 2>/dev/null; sleep 0.2
      fi
      if kill -0 "$opid" 2>/dev/null && is_our_watcher "$opid" "$opr"; then
        echo "merge-watch: skipped — could not stop watcher pid=$opid for $opr"; exit 0
      fi
      replaced="$opid"
    fi
    # v == 1: a live pid that is not our watcher (recycled) — stale, reclaimed.
  fi
  # reclaim only the marker we inspected (never one a concurrent launch wrote)
  [ "$(marker_field pid)" = "$opid" ] && rm -f "$MARKER" 2>/dev/null
fi
if ! ( set -C; printf 'pid\t%s\npr_url\t%s\nstarted\t%s\n' "$$" "$pr_url" "$(iso)" > "$MARKER" ) 2>/dev/null; then
  echo "merge-watch: already running pid=$(marker_field pid)"; exit 0
fi

SLEEP_PID=""
cleanup() {
  [ -n "$SLEEP_PID" ] && kill "$SLEEP_PID" 2>/dev/null
  [ "$(marker_field pid)" = "$$" ] && rm -f "$MARKER" 2>/dev/null
  return 0
}
trap cleanup EXIT
trap 'exit 0' TERM INT HUP
# nap <s> — an interruptible sleep: `wait` returns at once on a trapped TERM, so
# a replacing launch never waits out a 60s/900s foreground `sleep`.
nap() { sleep "$1" & SLEEP_PID=$!; wait "$SLEEP_PID" 2>/dev/null; SLEEP_PID=""; return 0; }

if [ -n "$replaced" ]; then
  progress "replaced watcher pid=$replaced for $opr (now watching $pr_url); $opr is no longer watched — run /automate --resume after it merges"
  echo "merge-watch: replaced pid=$replaced watching $opr"
fi

echo "merge-watch: started pid=$$ pr=$pr_url interval=${interval}s cap=${max}s"
start="$(now)"
wait_s="$interval"
co_wait="$interval"
merged_seen=0   # this watcher has read MERGED at least once
last_skip=""    # the last transient closeout skip reason (why it retried)
while :; do
  if [ $(( $(now) - start )) -ge "$max" ]; then
    if [ "$merged_seen" -eq 1 ]; then
      # The merge WAS observed; closeout never got past a transient skip.
      progress "lifetime cap (${max}s) reached — $pr_url is MERGED but closeout never ran (last skip: ${last_skip:-unknown}); run /automate --resume to close it out"
      notify "$pr_url merged but /automate closeout could not run for $item (run $run_id): lifetime cap reached, last skip: ${last_skip:-unknown}"
      echo "merge-watch: lifetime cap reached (merged; closeout never ran — ${last_skip:-unknown})"; exit 0
    fi
    progress "lifetime cap (${max}s) reached watching $pr_url — stopped; run /automate --resume after the merge"
    echo "merge-watch: lifetime cap reached"; exit 0
  fi
  view="$("$GH" pr view "$pr_url" --json state 2>/dev/null)"; rc=$?
  state="$(printf '%s' "$view" | "$JQ" -r '.state // empty' 2>/dev/null)"
  if [ "$rc" -ne 0 ] || [ -z "$state" ]; then
    wait_s=$(( wait_s * 2 )); [ "$wait_s" -ge 1 ] || wait_s=1
    [ "$wait_s" -le "$BACKOFF_CAP" ] || wait_s="$BACKOFF_CAP"
    echo "merge-watch: gh pr view failed — next poll in ${wait_s}s"
    nap "$wait_s"; continue
  fi
  wait_s="$interval"
  case "$state" in
    MERGED)
      merged_seen=1
      out="$(bash "$HERE/automate-helpers.sh" closeout "$rf_abs" "$item" "$pr_url" 2>/dev/null)"
      [ -n "$out" ] && printf '%s\n' "$out"
      guard=""
      # A lone `closeout: skipped — …` line is a guard that stopped closeout
      # before any step ran; the lock-held skip follows the brief-repair line.
      if [ -n "$out" ] && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = "1" ]; then
        case "$out" in "closeout: skipped — "*) guard="${out#closeout: skipped — }" ;; esac
      fi
      why=""
      case "$out" in
        "") why="no output" ;;
        *"closeout: skipped — run lock held"*) why="run lock held" ;;
      esac
      case "$guard" in "gh unavailable"|"pr not merged"*) why="$guard" ;; esac
      if [ -n "$why" ]; then
        last_skip="$why"
        # own backoff (the poll's wait_s resets on every successful gh read)
        co_wait=$(( co_wait * 2 )); [ "$co_wait" -ge 1 ] || co_wait=1
        [ "$co_wait" -le "$BACKOFF_CAP" ] || co_wait="$BACKOFF_CAP"
        echo "merge-watch: closeout did not run ($why) — retry in ${co_wait}s"
        nap "$co_wait"; continue
      fi
      if [ -n "$guard" ]; then
        progress "closeout for $pr_url could not run — skipped: $guard; run /automate --resume"
        notify "$pr_url merged but /automate closeout could not run for $item (run $run_id): $guard"
        echo "merge-watch: closeout skipped — $guard"; exit 0
      fi
      notify "$pr_url merged — /automate closeout ran for $item (run $run_id); the next item waits for your go"
      echo "merge-watch: closeout done"; exit 0 ;;
    CLOSED)
      progress "$item gone — $pr_url closed unmerged (no cleanup; §4 gone rules)"
      notify "$pr_url closed unmerged — /automate item $item is gone (run $run_id)"
      echo "merge-watch: pr closed unmerged"; exit 0 ;;
    *) nap "$interval" ;;
  esac
done
