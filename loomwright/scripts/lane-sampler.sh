#!/usr/bin/env bash
# lane-sampler.sh — fleet-health sampler for an `/automate --parallel N` wave: every interval it
# appends ONE line to the wave's fleet log with CI-slot holders/waiters, load, swap, free memory,
# per-lane RSS attributed by working directory, and the share of RSS and CPU that is NOT from a
# lane; it runs the memory guard (the trip file the launch guard reads) and notifies the owner once
# per crossing. Started by the coordinator as its own child when a wave starts; it exits by itself
# when that coordinator dies. Port of the S2 operator prototype, with Linux readers added.
#
# usage: lane-sampler.sh --parent-run-id <id> --parent-pid <pid> [--root <primary>]
#                        [--interval S] [--max-samples N] [--fleet-log <path>]
#          the loop (sampler_loop). ALWAYS exits 0 once running (observation emitter, fail-SAFE);
#          exit 2 only on a usage error. Stops when --parent-pid is gone (pid dead, or its start
#          time no longer matches the one read at startup — a recycled pid is not the parent).
#        lane-sampler.sh --once --parent-run-id <id> [--root <primary>]
#          print one sample line (sampler_line) on stdout; no append, no guard, no notification.
#        lane-sampler.sh --help   this header
#
# FILES            (all under <root>/.supervisor/automate/, <id> = the parent run id)
#                  <id>.lanes            INPUT, the coordinator's lane table (TSV: lane, path, item,
#                                        run_id, pid, pid start time, session_id, state,
#                                        last_launch_utc, blocked_reason). Lanes come from here only;
#                                        a blank line, a `#` line or a `lane` header row is skipped.
#                  <id>.fleet.log        OUTPUT, one sample line per interval (--fleet-log overrides).
#                                        Every line is a sample — start/stop notes go to stderr, so
#                                        "the last line" is always the latest reading.
#                  <id>.memory-pressure  OUTPUT, the memory-guard trip file: line 1 `tripped_utc: <ts>`,
#                                        line 2 `sample: <the triggering sample line>`. Written when
#                                        the guard trips, removed when it clears. Its presence is
#                                        what holds `automate-lanes.sh lane-launch` and every lane
#                                        resume. A sampler that starts while the file exists adopts
#                                        it (tripped) and clears it by the same rule.
# LINE             `<UTC ts> key=value …`, space separated; a value that cannot be read is `unknown`:
#                  holders waiters        live CI-slot holders / waiters (`ci-slot.sh status`)
#                  load1 load_state       from machine-load.sh --json (load_state = load1 against its
#                                         busy_at / overloaded_at: ok | busy | overloaded)
#                  mem_pressure           machine-load.sh's memory verdict
#                  swap_used_mb free_mb   macOS `sysctl -n vm.swapusage` + `vm_stat` Pages free (page
#                                         size read from vm_stat's own header); Linux /proc/meminfo
#                                         SwapTotal - SwapFree and MemAvailable
#                  keep_awake             held | not_held (macOS: a `caffeinate` process) | na
#                  rss_mb.<lane> procs.<lane>   per lane, summed RSS and count of every process whose
#                                         cwd is the lane path or below it (match by cwd, NOT argv —
#                                         `claude -p`'s argv carries no lane path). cwd: macOS
#                                         `lsof -a -d cwd -Fpn`, Linux `/proc/<pid>/cwd`.
#                  lane_rss_mb nonlane_rss_mb nonlane_rss_pct   all lanes vs everything else
#                  nonlane_load_pct       share of summed `ps` %CPU from processes outside every lane
#                  memory_guard           ok | pressured:<streak> | tripped
# MEMORY GUARD     a sample is PRESSURED when free_mb < LOOMWRIGHT_LANE_MEM_FREE_MB (default 512)
#                  AND swap_used_mb grew since the previous sample. LOOMWRIGHT_LANE_MEM_SAMPLES
#                  (default 3) consecutive pressured samples trip the guard (trip file written, owner
#                  notified once); the same number of consecutive non-pressured samples clear it (file
#                  removed). A sample with free or swap unreadable is neutral: it resets the pressured
#                  streak and does not count toward clearing. Never kills anything — the launch guard
#                  only stops STARTING.
# CROSSINGS        each notifies ONCE per crossing (notify-desktop.sh + send-webhook.sh, both
#                  fail-safe; gate types lane_load_busy, lane_load_overloaded, lane_memory_pressure,
#                  lane_keep_awake_lost): load_state rising into busy (from ok) or into overloaded
#                  (from ok or busy); the level is latched, so falling back from overloaded to busy
#                  and rising again does not re-notify — only a return to ok re-arms both (no flapping
#                  at a threshold), and an unreadable load keeps the previous level; the memory guard
#                  tripping;
#                  keep-awake going from held to not held (never at start: keep-awake is optional).
# SEAMS            (tests) LOOMWRIGHT_LANE_SAMPLER_OS=darwin|linux (default uname -s);
#                  LOOMWRIGHT_LANE_SAMPLER_{SYSCTL,VM_STAT,LSOF,PS,PGREP} name the commands;
#                  LOOMWRIGHT_LANE_SAMPLER_PROC names the /proc dir; LOOMWRIGHT_MACHINE_LOAD_CMD the
#                  load reader (as ci-slot.sh); LOOMWRIGHT_LANE_SAMPLER_CI_SLOT the slot helper;
#                  LOOMWRIGHT_LANE_SAMPLER_NOTIFIER_DIR the dir holding the two notifiers;
#                  LOOMWRIGHT_LANE_KEEPAWAKE_PROC the keep-awake process name (empty ⇒ na).
#                  LOOMWRIGHT_LANE_SAMPLER_INTERVAL is the default --interval (10).
#
# Honest limits: (1) load average is not per process, so the non-lane LOAD share is a proxy — the
# share of `ps` %CPU (a decaying average on macOS, a lifetime average on Linux procps). (2) a
# process that changed directory out of its lane is not attributed to it. (3) macOS "Pages free"
# is low on a healthy Mac, which is why the guard also needs swap growth. (4) `lsof` cannot see the
# cwd of another user's processes without privileges; those count as non-lane.
# Self-test: loomwright/scripts/test-lane-sampler.sh. Portability: bash 3.2 safe, BSD + GNU userland.
set -uo pipefail
export LC_ALL=C   # this process's own number parsing/printing (comma-decimal locales), as machine-load.sh

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

is_uint() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac; return 0; }
utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }
note() { echo "lane-sampler: $*" >&2; }
usage_die() { echo "lane-sampler: $* (try --help)" >&2; exit 2; }
# fld KEY LINE — the value of KEY=… in a sample line (empty when absent).
fld() { printf '%s\n' "$2" | awk -v k="$1=" '{ for (i = 1; i <= NF; i++) if (index($i, k) == 1) { print substr($i, length(k) + 1); exit } }'; }

OS="${LOOMWRIGHT_LANE_SAMPLER_OS:-}"
if [ -z "$OS" ]; then case "$(uname -s 2>/dev/null)" in Darwin) OS=darwin ;; Linux) OS=linux ;; *) OS=other ;; esac; fi
SYSCTL="${LOOMWRIGHT_LANE_SAMPLER_SYSCTL:-sysctl}"
VM_STAT="${LOOMWRIGHT_LANE_SAMPLER_VM_STAT:-vm_stat}"
LSOF="${LOOMWRIGHT_LANE_SAMPLER_LSOF:-lsof}"
PS="${LOOMWRIGHT_LANE_SAMPLER_PS:-ps}"
PGREP="${LOOMWRIGHT_LANE_SAMPLER_PGREP:-pgrep}"
PROC="${LOOMWRIGHT_LANE_SAMPLER_PROC:-/proc}"
LOAD_CMD="${LOOMWRIGHT_MACHINE_LOAD_CMD:-$HERE/machine-load.sh}"
CI_SLOT="${LOOMWRIGHT_LANE_SAMPLER_CI_SLOT:-$HERE/ci-slot.sh}"
NOTIFIER_DIR="${LOOMWRIGHT_LANE_SAMPLER_NOTIFIER_DIR:-$HERE}"
if [ "${LOOMWRIGHT_LANE_KEEPAWAKE_PROC+set}" = set ]; then KEEPAWAKE="$LOOMWRIGHT_LANE_KEEPAWAKE_PROC"
elif [ "$OS" = darwin ]; then KEEPAWAKE=caffeinate; else KEEPAWAKE=""; fi
MEM_FREE_MB="${LOOMWRIGHT_LANE_MEM_FREE_MB:-512}"; is_uint "$MEM_FREE_MB" || MEM_FREE_MB=512
MEM_SAMPLES="${LOOMWRIGHT_LANE_MEM_SAMPLES:-3}"; is_uint "$MEM_SAMPLES" && [ "$MEM_SAMPLES" -gt 0 ] || MEM_SAMPLES=3

# ---- readers (each prints a value or `unknown`; never fails) -------------------------------------

read_slots() {   # "<holders> <waiters>"
  local st
  st="$(cd "$ROOT" 2>/dev/null && bash "$CI_SLOT" status 2>/dev/null)"
  if [ -z "$st" ]; then echo "unknown unknown"; return 0; fi
  printf '%s\n' "$st" | awk '/^holder:/ { h++ } /^waiter:/ { w++ } END { printf "%d %d\n", h, w }'
}

read_load() {    # "<load1> <load_state> <mem_pressure>"
  local j l b o m
  j="$(bash "$LOAD_CMD" --json 2>/dev/null)"
  l="$(printf '%s' "$j" | sed -n 's/.*"load1":\([0-9.]*\)[,}].*/\1/p')"
  b="$(printf '%s' "$j" | sed -n 's/.*"busy_at":\([0-9.]*\)[,}].*/\1/p')"
  o="$(printf '%s' "$j" | sed -n 's/.*"overloaded_at":\([0-9.]*\)[,}].*/\1/p')"
  m="$(printf '%s' "$j" | sed -n 's/.*"mem_pressure":"\([a-z]*\)".*/\1/p')"
  local s=unknown
  if [ -n "$l" ] && [ -n "$b" ] && [ -n "$o" ]; then
    s="$(awk -v l="$l" -v b="$b" -v o="$o" 'BEGIN { print (l >= o) ? "overloaded" : (l >= b) ? "busy" : "ok" }')"
  fi
  echo "${l:-unknown} $s ${m:-unknown}"
}

read_mem() {     # "<swap_used_mb> <free_mb>"
  local sw="" fr=""
  case "$OS" in
    darwin)
      # `total = 3072.00M  used = 2237.56M  free = 834.44M  (encrypted)` — M or G suffix.
      sw="$("$SYSCTL" -n vm.swapusage 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i == "used" && $(i+1) == "=") {
              v = $(i+2); u = substr(v, length(v)); n = v + 0
              if (u == "G") n *= 1024; else if (u == "K") n /= 1024
              printf "%.0f\n", n; exit } }')"
      fr="$("$VM_STAT" 2>/dev/null | awk '/page size of/ { for (i = 1; i <= NF; i++) if ($i == "of") ps = $(i+1) + 0 }
              /^Pages free:/ { gsub(/\./, "", $3); f = $3 + 0; seen = 1 }
              END { if (seen && ps > 0) printf "%.0f\n", f * ps / 1048576 }')" ;;
    linux)
      sw="$(awk '/^SwapTotal:/ { t = $2; a++ } /^SwapFree:/ { f = $2; a++ } END { if (a == 2) printf "%.0f\n", (t - f) / 1024 }' "$PROC/meminfo" 2>/dev/null)"
      fr="$(awk '/^MemAvailable:/ { printf "%.0f\n", $2 / 1024; exit }' "$PROC/meminfo" 2>/dev/null)" ;;
  esac
  is_uint "$sw" || sw=unknown
  is_uint "$fr" || fr=unknown
  echo "$sw $fr"
}

read_keepawake() {
  [ -n "$KEEPAWAKE" ] || { echo na; return 0; }
  if "$PGREP" -x "$KEEPAWAKE" >/dev/null 2>&1; then echo held; else echo not_held; fi
}

# cwd_map OUT — "<pid>\t<cwd>" for every process whose cwd is readable.
cwd_map() {
  local out="$1" d c
  : > "$out"
  case "$OS" in
    darwin)
      "$LSOF" -a -d cwd -Fpn 2>/dev/null | awk '/^p/ { p = substr($0, 2) } /^n/ { if (p != "") print p "\t" substr($0, 2) }' > "$out" ;;
    linux)
      for d in "$PROC"/[0-9]*; do
        [ -L "$d/cwd" ] || continue
        c="$(readlink "$d/cwd" 2>/dev/null)" || continue
        [ -n "$c" ] && printf '%s\t%s\n' "${d##*/}" "$c" >> "$out"
      done ;;
  esac
  return 0
}

# lane_list OUT — "<lane>\t<canonical path>" from the lane table (lane names sanitised for the line).
lane_list() {
  local out="$1" lane path rest p
  : > "$out"
  [ -f "$LANES" ] || return 0
  while IFS="$(printf '\t')" read -r lane path rest || [ -n "${lane:-}" ]; do
    case "$lane" in ''|'#'*|lane) continue ;; esac
    [ -n "${path:-}" ] || continue
    lane="$(printf '%s' "$lane" | tr -c 'A-Za-z0-9_.-' '_')"
    p="$(cd "$path" 2>/dev/null && pwd -P)" || p=""
    [ -n "$p" ] || p="${path%/}"
    printf '%s\t%s\n' "$lane" "$p" >> "$out"
  done < "$LANES"
  return 0
}

# sampler_line — one sample line on stdout (reads only; temp files under $TMPD).
sampler_line() {
  local slots load mem ka
  slots="$(read_slots)"; load="$(read_load)"; mem="$(read_mem)"; ka="$(read_keepawake)"
  lane_list "$TMPD/lanes"
  cwd_map "$TMPD/cwd"
  "$PS" -A -o pid= -o rss= -o pcpu= 2>/dev/null | awk '$1 ~ /^[0-9]+$/ { print $1 "\t" $2 "\t" $3 }' > "$TMPD/ps"
  local procs
  # FILENAME, not an FNR counter: an empty lane table or cwd map must not shift the files.
  procs="$(awk -F'\t' -v lf="$TMPD/lanes" -v cf="$TMPD/cwd" '
    FILENAME == lf { n++; name[n] = $1; path[n] = $2; next }
    FILENAME == cf { cwd[$1] = $2; next }
    { rows++; rss = $2 + 0; cpu = $3 + 0; trss += rss; tcpu += cpu; c = ($1 in cwd) ? cwd[$1] : ""
             if (c == "") next
             for (i = 1; i <= n; i++) if (c == path[i] || index(c, path[i] "/") == 1) {
               lr[i] += rss; lp[i]++; lrss += rss; lcpu += cpu; break } }
    END {
      out = ""
      for (i = 1; i <= n; i++) out = out sprintf(" rss_mb.%s=%s procs.%s=%s", name[i], rows ? sprintf("%.0f", lr[i] / 1024) : "unknown", name[i], rows ? lp[i] + 0 : "unknown")
      if (rows) {
        out = out sprintf(" lane_rss_mb=%.0f nonlane_rss_mb=%.0f", lrss / 1024, (trss - lrss) / 1024)
        out = out (trss > 0 ? sprintf(" nonlane_rss_pct=%.1f", 100 * (trss - lrss) / trss) : " nonlane_rss_pct=unknown")
        out = out (tcpu > 0 ? sprintf(" nonlane_load_pct=%.1f", 100 * (tcpu - lcpu) / tcpu) : " nonlane_load_pct=unknown")
      } else out = out " lane_rss_mb=unknown nonlane_rss_mb=unknown nonlane_rss_pct=unknown nonlane_load_pct=unknown"
      print out
    }' "$TMPD/lanes" "$TMPD/cwd" "$TMPD/ps" 2>/dev/null)"
  set -- $slots; local h="$1" w="$2"
  set -- $load; local l1="$1" ls="$2" mp="$3"
  set -- $mem; local sw="$1" fr="$2"
  printf '%s holders=%s waiters=%s load1=%s load_state=%s mem_pressure=%s swap_used_mb=%s free_mb=%s keep_awake=%s%s\n' \
    "$(utc)" "$h" "$w" "$l1" "$ls" "$mp" "$sw" "$fr" "$ka" "$procs"
}

# ---- notifications, guard, loop ------------------------------------------------------------------

notify() {   # notify <gate_type> <message> — desktop + webhook, both fail-safe; never fails.
  local gt="$1" msg="$2" payload=""
  if command -v jq >/dev/null 2>&1; then
    payload="$(jq -cn --arg t "$gt" --arg m "$msg" '{hook_event_name:"Notification",notification_type:$t,message:$m}' 2>/dev/null)"
  fi
  [ -n "$payload" ] && [ -f "$NOTIFIER_DIR/notify-desktop.sh" ] &&
    printf '%s' "$payload" | bash "$NOTIFIER_DIR/notify-desktop.sh" >/dev/null 2>&1 </dev/null
  [ -f "$NOTIFIER_DIR/send-webhook.sh" ] &&
    bash "$NOTIFIER_DIR/send-webhook.sh" --event-type gate --gate-type "$gt" --context "$msg" >/dev/null 2>&1 </dev/null
  return 0
}

# parent_alive — the parent pid lives AND still has the start time read at startup.
parent_alive() {
  kill -0 "$PARENT_PID" 2>/dev/null || return 1
  [ -z "$PARENT_START" ] && return 0
  [ "$("$PS" -o lstart= -p "$PARENT_PID" 2>/dev/null)" = "$PARENT_START" ]
}

write_trip() {   # write_trip <sample line> — atomic, same dir.
  local t="$TRIP.tmp.$$"
  mkdir -p "$(dirname "$TRIP")" 2>/dev/null
  { printf 'tripped_utc: %s\n' "$(utc)"; printf 'sample: %s\n' "$1"; } > "$t" 2>/dev/null && mv -f "$t" "$TRIP" 2>/dev/null
  rm -f "$t" 2>/dev/null
  return 0
}

sampler_loop() {
  local n=0 line sw fr ls ka tripped=0 pstreak=0 cstreak=0 prev_sw="" load_level=0 prev_ka="" guard nl
  [ -f "$TRIP" ] && tripped=1
  mkdir -p "$(dirname "$FLEET")" 2>/dev/null
  note "start $(utc) pid=$$ parent=$PARENT_PID log=$FLEET"
  while parent_alive; do
    line="$(sampler_line)"
    sw="$(fld swap_used_mb "$line")"; fr="$(fld free_mb "$line")"
    ls="$(fld load_state "$line")"; ka="$(fld keep_awake "$line")"
    # memory guard
    if is_uint "$sw" && is_uint "$fr"; then
      if [ "$fr" -lt "$MEM_FREE_MB" ] && is_uint "$prev_sw" && [ "$sw" -gt "$prev_sw" ]; then
        pstreak=$((pstreak + 1)); cstreak=0
      else pstreak=0; cstreak=$((cstreak + 1)); fi
      prev_sw="$sw"
    else pstreak=0; prev_sw=""; fi
    if [ "$tripped" -eq 0 ] && [ "$pstreak" -ge "$MEM_SAMPLES" ]; then
      tripped=1; cstreak=0; guard=tripped
    elif [ "$tripped" -eq 1 ] && [ "$cstreak" -ge "$MEM_SAMPLES" ]; then
      tripped=0; rm -f "$TRIP" 2>/dev/null; note "memory guard cleared $(utc)"
      guard=ok
    elif [ "$tripped" -eq 1 ]; then guard=tripped
    elif [ "$pstreak" -gt 0 ]; then guard="pressured:$pstreak"
    else guard=ok; fi
    line="$line memory_guard=$guard"
    printf '%s\n' "$line" >> "$FLEET" 2>/dev/null
    if [ "$guard" = tripped ] && [ ! -f "$TRIP" ]; then
      write_trip "$line"
      notify lane_memory_pressure "lane wave $RUN_ID: memory guard tripped (free ${fr} MB, swap ${sw} MB growing) — no new lanes start until it clears; running lanes are left alone"
    fi
    # load crossings
    case "$ls" in
      overloaded) nl=2 ;; ok) nl=0 ;;
      busy) nl=1; [ "$load_level" -eq 2 ] && nl=2 ;;   # latched: overloaded re-arms only via ok
      *) nl="$load_level" ;;
    esac
    if [ "$nl" -eq 2 ] && [ "$load_level" -lt 2 ]; then
      notify lane_load_overloaded "lane wave $RUN_ID: machine load overloaded (load1 $(fld load1 "$line"), non-lane CPU share $(fld nonlane_load_pct "$line")%) — launches held"
    elif [ "$nl" -eq 1 ] && [ "$load_level" -eq 0 ]; then
      notify lane_load_busy "lane wave $RUN_ID: machine load busy (load1 $(fld load1 "$line"), non-lane CPU share $(fld nonlane_load_pct "$line")%) — launches staggered"
    fi
    load_level="$nl"
    # keep-awake lost
    if [ "$prev_ka" = held ] && [ "$ka" = not_held ]; then
      notify lane_keep_awake_lost "lane wave $RUN_ID: keep-awake ($KEEPAWAKE) is no longer held — the machine may sleep"
    fi
    case "$ka" in held|not_held) prev_ka="$ka" ;; esac
    n=$((n + 1))
    if [ "$MAX_SAMPLES" -gt 0 ] && [ "$n" -ge "$MAX_SAMPLES" ]; then note "stop $(utc) reason=max_samples"; return 0; fi
    local s=0
    while [ "$s" -lt "$INTERVAL" ]; do parent_alive || break; sleep 1; s=$((s + 1)); done
  done
  note "stop $(utc) reason=parent_gone"
  return 0
}

# ---- CLI -----------------------------------------------------------------------------------------

RUN_ID=""; PARENT_PID=""; ROOT=""; INTERVAL="${LOOMWRIGHT_LANE_SAMPLER_INTERVAL:-10}"; MAX_SAMPLES=0; FLEET=""; ONCE=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"; exit 0 ;;
    --parent-run-id) [ "$#" -ge 2 ] || usage_die "--parent-run-id needs a value"; RUN_ID="$2"; shift 2 ;;
    --parent-pid) [ "$#" -ge 2 ] || usage_die "--parent-pid needs a value"; PARENT_PID="$2"; shift 2 ;;
    --root) [ "$#" -ge 2 ] || usage_die "--root needs a value"; ROOT="$2"; shift 2 ;;
    --interval) [ "$#" -ge 2 ] || usage_die "--interval needs a value"; INTERVAL="$2"; shift 2 ;;
    --max-samples) [ "$#" -ge 2 ] || usage_die "--max-samples needs a value"; MAX_SAMPLES="$2"; shift 2 ;;
    --fleet-log) [ "$#" -ge 2 ] || usage_die "--fleet-log needs a value"; FLEET="$2"; shift 2 ;;
    --once) ONCE=1; shift ;;
    *) usage_die "unknown argument: $1" ;;
  esac
done
[ -n "$RUN_ID" ] || usage_die "--parent-run-id is required"
case "$RUN_ID" in */*|.*) usage_die "--parent-run-id must be a plain run id, got '$RUN_ID'" ;; esac
is_uint "$INTERVAL" || usage_die "--interval must be a whole number of seconds, got '$INTERVAL'"
is_uint "$MAX_SAMPLES" || usage_die "--max-samples must be a whole number, got '$MAX_SAMPLES'"
if [ "$ONCE" -eq 0 ]; then
  is_uint "$PARENT_PID" && [ "$PARENT_PID" -gt 0 ] || usage_die "--parent-pid is required (the coordinator pid)"
fi
[ -n "$ROOT" ] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
AD="$ROOT/.supervisor/automate"
LANES="$AD/$RUN_ID.lanes"
TRIP="$AD/$RUN_ID.memory-pressure"
[ -n "$FLEET" ] || FLEET="$AD/$RUN_ID.fleet.log"

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/lane-sampler.XXXXXX" 2>/dev/null)" || { note "cannot create a temp dir — not sampling"; exit 0; }
trap 'rm -rf "$TMPD"' EXIT
trap 'exit 0' TERM INT HUP

if [ "$ONCE" -eq 1 ]; then sampler_line; exit 0; fi
PARENT_START="$("$PS" -o lstart= -p "$PARENT_PID" 2>/dev/null)"
sampler_loop
exit 0
