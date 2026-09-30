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
#            --session-id: it takes the run lock as `automate-closeout:<run_id>`;
#            while closeout reports `skipped — run lock held` it is retried on a
#            later poll, within the lifetime cap), then ONE notify
#            (notify-desktop.sh + send-webhook.sh, both fail-safe), exit.
#   CLOSED ⇒ one `gone` ## Progress line + notify, exit — no cleanup (§4's
#            `gone` rules stand).
#   Lifetime cap LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS (default 259200 = 72h) ⇒
#            one ## Progress line, exit.
# It never merges anything, never picks/RUNs a Queue item, never invokes
# `/autonomous`.
#
# SINGLE INSTANCE: marker `<runfile dir>/<run_id>.merge-watch` (TSV
# pid/pr_url/started; gitignored under `.supervisor/automate/*` because it is
# not `*.md`). A live pid ⇒ a second launch prints `merge-watch: already
# running pid=<p>` and exits 0; a dead pid ⇒ reclaimed. The marker is removed
# on every exit of the owning watcher (EXIT trap; TERM/INT/HUP exit through it).
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

# ---- single instance --------------------------------------------------------
if [ -f "$MARKER" ]; then
  opid="$(awk -F'\t' '$1=="pid"{print $2; exit}' "$MARKER" 2>/dev/null)"
  case "$opid" in ''|*[!0-9]*) opid="" ;; esac
  if [ -n "$opid" ] && kill -0 "$opid" 2>/dev/null; then
    echo "merge-watch: already running pid=$opid"; exit 0
  fi
  rm -f "$MARKER" 2>/dev/null   # dead pid ⇒ reclaim
fi
if ! ( set -C; printf 'pid\t%s\npr_url\t%s\nstarted\t%s\n' "$$" "$pr_url" "$(iso)" > "$MARKER" ) 2>/dev/null; then
  opid="$(awk -F'\t' '$1=="pid"{print $2; exit}' "$MARKER" 2>/dev/null)"
  echo "merge-watch: already running pid=${opid:-unknown}"; exit 0
fi

cleanup() {
  local cur
  cur="$(awk -F'\t' '$1=="pid"{print $2; exit}' "$MARKER" 2>/dev/null)"
  [ "$cur" = "$$" ] && rm -f "$MARKER" 2>/dev/null
  return 0
}
trap cleanup EXIT
trap 'exit 0' TERM INT HUP

progress() { bash "$HERE/automate-helpers.sh" progress-append "$rf_abs" "$(iso) merge-watch: $1" >/dev/null 2>&1; return 0; }
notify() {
  local msg="$1" payload
  payload="$("$JQ" -cn --arg m "$msg" '{hook_event_name:"Notification",notification_type:"automate_merge_watch",message:$m}' 2>/dev/null)"
  [ -n "$payload" ] && printf '%s' "$payload" | bash "$HERE/notify-desktop.sh" >/dev/null 2>&1 </dev/null
  bash "$HERE/send-webhook.sh" --event-type gate --gate-type automate_merge_watch --context "$msg" >/dev/null 2>&1 </dev/null
  return 0
}

echo "merge-watch: started pid=$$ pr=$pr_url interval=${interval}s cap=${max}s"
start="$(now)"
wait_s="$interval"
while :; do
  if [ $(( $(now) - start )) -ge "$max" ]; then
    progress "lifetime cap (${max}s) reached watching $pr_url — stopped; run /automate --resume after the merge"
    echo "merge-watch: lifetime cap reached"; exit 0
  fi
  view="$("$GH" pr view "$pr_url" --json state 2>/dev/null)"; rc=$?
  state="$(printf '%s' "$view" | "$JQ" -r '.state // empty' 2>/dev/null)"
  if [ "$rc" -ne 0 ] || [ -z "$state" ]; then
    wait_s=$(( wait_s * 2 )); [ "$wait_s" -ge 1 ] || wait_s=1
    [ "$wait_s" -le "$BACKOFF_CAP" ] || wait_s="$BACKOFF_CAP"
    echo "merge-watch: gh pr view failed — next poll in ${wait_s}s"
    sleep "$wait_s"; continue
  fi
  wait_s="$interval"
  case "$state" in
    MERGED)
      out="$(bash "$HERE/automate-helpers.sh" closeout "$rf_abs" "$item" "$pr_url" 2>/dev/null)"
      printf '%s\n' "$out"
      case "$out" in
        *"skipped — run lock held"*) sleep "$interval"; continue ;;
      esac
      notify "$pr_url merged — /automate closeout ran for $item (run $run_id); the next item waits for your go"
      echo "merge-watch: closeout done"; exit 0 ;;
    CLOSED)
      progress "$item gone — $pr_url closed unmerged (no cleanup; §4 gone rules)"
      notify "$pr_url closed unmerged — /automate item $item is gone (run $run_id)"
      echo "merge-watch: pr closed unmerged"; exit 0 ;;
    *) sleep "$interval" ;;
  esac
done
