#!/usr/bin/env bash
# machine-load.sh — one reader of how loaded THIS machine is: load average per CPU + the OS's own
# memory-pressure judgment, folded into one state that heavy starts (ci-slot.sh acquire) consult.
#
# usage: machine-load.sh [--json]
#          plain: five `key=value` lines — load1, cpus, load_per_cpu, mem_pressure, state (plus
#          mem_source, the raw memory reading). --json: one object with the same keys; a value that
#          could not be read is `null` (state is then a string as always). ALWAYS exit 0 on a
#          reading, even an unreadable one; exit 2 only on a usage error.
#        machine-load.sh --help   this header
#
# STATE            ok | busy | overloaded | unknown — the worst of the load verdict and the memory
#                  verdict. A component that cannot be read is `unknown`; the state is `unknown` when
#                  nothing readable says busy/overloaded (a readable "overloaded" is never hidden
#                  behind an unreadable neighbour). Every caller treats `unknown` as `ok` (fail-SAFE:
#                  a broken reader never stalls a lane).
# LOAD             per CPU, not absolute: load1 >= BUSY x CPUs ⇒ busy, load1 >= OVERLOADED x CPUs ⇒
#                  overloaded. Defaults 2 and 3 (24 / 36 on 12 CPUs); LOOMWRIGHT_LOAD_BUSY /
#                  LOOMWRIGHT_LOAD_OVERLOADED override them (per-CPU multipliers, decimals allowed; a
#                  malformed value falls back to the default with a warning on stderr).
#                  load1: macOS `sysctl -n vm.loadavg`, Linux /proc/loadavg.
# MEMORY           the OS's own judgment, not percent free (macOS "free" is misleading under
#                  compression and swap). macOS `sysctl -n kern.memorystatus_vm_pressure_level`:
#                  1 ⇒ ok, 2 (warn) ⇒ busy, 4 (critical) ⇒ overloaded (3 ⇒ busy, >4 ⇒ overloaded,
#                  anything else ⇒ unknown). Linux: MemAvailable / MemTotal < 15 % ⇒ busy, < 8 % ⇒
#                  overloaded (from /proc/meminfo).
# CPUS             the same precedence as ci-slot.sh `cpus()`: LOOMWRIGHT_CI_CPUS, then getconf
#                  _NPROCESSORS_ONLN, then sysctl -n hw.ncpu, else 4 — ci-slot.sh also passes its own
#                  count in, so the gate and the slot share never disagree.
# FIXTURE SEAMS    (tests only) LOOMWRIGHT_MACHINE_LOAD_OS=darwin|linux picks the reader (default:
#                  uname -s); LOOMWRIGHT_MACHINE_LOAD_SYSCTL names the sysctl command (default
#                  sysctl); LOOMWRIGHT_MACHINE_LOAD_PROC names the /proc dir (default /proc).
#
# Never signals or waits on any process; reads only. Honest limits: (1) load1 is a 1-minute average
# and lags a burst — work already running keeps climbing after the gate holds new starts, which is why
# `overloaded` sits well below the 2026-10-05 freeze (load1 119 on 12 CPUs). (2) other OSes (BSDs
# without vm.loadavg, Windows) read as `unknown`.
# Self-test: loomwright/scripts/test-machine-load.sh. Portability: bash 3.2 safe, BSD + GNU userland.
set -uo pipefail

is_uint() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac; return 0; }
is_num()  { local re='^[0-9]+(\.[0-9]+)?$'; [[ "${1:-}" =~ $re ]]; }   # no pipe: pipefail + grep -q

cpus() {
  local c="${LOOMWRIGHT_CI_CPUS:-}"
  is_uint "$c" && [ "$c" -gt 0 ] || c="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
  is_uint "$c" && [ "$c" -gt 0 ] || c="$(sysctl -n hw.ncpu 2>/dev/null || true)"
  is_uint "$c" && [ "$c" -gt 0 ] || c=4
  echo "$((10#$c))"
}

mult() {   # mult VALUE DEFAULT NAME — a validated per-CPU multiplier
  if [ -z "${1:-}" ]; then echo "$2"
  elif is_num "$1" && awk -v v="$1" 'BEGIN { exit !(v > 0) }'; then echo "$1"
  else echo "machine-load: $3 must be a positive number, got '$1' — using $2" >&2; echo "$2"; fi
}

case "${1:-}" in
  -h|--help) awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"; exit 0 ;;
  --json) JSON=1; [ "$#" -le 1 ] || { echo "machine-load: unexpected argument: $2" >&2; exit 2; } ;;
  '') JSON=0 ;;
  *) echo "machine-load: unknown argument: $1 (try --help)" >&2; exit 2 ;;
esac

SYSCTL="${LOOMWRIGHT_MACHINE_LOAD_SYSCTL:-sysctl}"
PROC="${LOOMWRIGHT_MACHINE_LOAD_PROC:-/proc}"
OS="${LOOMWRIGHT_MACHINE_LOAD_OS:-}"
if [ -z "$OS" ]; then case "$(uname -s 2>/dev/null)" in Darwin) OS=darwin ;; Linux) OS=linux ;; *) OS=other ;; esac; fi
BUSY="$(mult "${LOOMWRIGHT_LOAD_BUSY:-}" 2 LOOMWRIGHT_LOAD_BUSY)"
OVER="$(mult "${LOOMWRIGHT_LOAD_OVERLOADED:-}" 3 LOOMWRIGHT_LOAD_OVERLOADED)"
CPUS="$(cpus)"

load1=""; mem_state=unknown; mem_source=none
case "$OS" in
  darwin)
    # `{ 6.78 4.51 3.76 }` — the first number after the brace.
    load1="$("$SYSCTL" -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{ print $1; exit }')"
    lvl="$("$SYSCTL" -n kern.memorystatus_vm_pressure_level 2>/dev/null | tr -d '[:space:]')"
    if is_uint "$lvl"; then
      mem_source="macos-pressure-level:$((10#$lvl))"
      case "$((10#$lvl))" in 1) mem_state=ok ;; 2|3) mem_state=busy ;; 0) mem_state=unknown ;; *) mem_state=overloaded ;; esac
    fi ;;
  linux)
    load1="$(awk '{ print $1; exit }' "$PROC/loadavg" 2>/dev/null)"
    pct="$(awk '/^MemTotal:/ { t = $2 } /^MemAvailable:/ { a = $2; seen = 1 }
                END { if (seen && t > 0) printf "%.1f", 100 * a / t }' "$PROC/meminfo" 2>/dev/null)"
    if is_num "$pct"; then
      mem_source="linux-memavailable-pct:$pct"
      mem_state="$(awk -v p="$pct" 'BEGIN { print (p < 8) ? "overloaded" : (p < 15) ? "busy" : "ok" }')"
    fi ;;
esac

is_num "$load1" || load1=""
if [ -n "$load1" ]; then
  # Float compares in awk, never $(( )) (bash 3.2 has no floats; "07.50" is not octal here).
  load_per_cpu="$(awk -v l="$load1" -v c="$CPUS" 'BEGIN { printf "%.2f", l / c }')"
  load_state="$(awk -v l="$load1" -v c="$CPUS" -v b="$BUSY" -v o="$OVER" \
    'BEGIN { print (l >= o * c) ? "overloaded" : (l >= b * c) ? "busy" : "ok" }')"
  load1="$(awk -v l="$load1" 'BEGIN { printf "%.2f", l }')"
else load_per_cpu=""; load_state=unknown; fi

rank() { case "$1" in ok) echo 1 ;; busy) echo 2 ;; overloaded) echo 3 ;; *) echo 0 ;; esac; }
state=unknown; best=0
for s in "$load_state" "$mem_state"; do r="$(rank "$s")"; [ "$r" -gt "$best" ] && { best="$r"; state="$s"; }; done
# A readable "ok" next to an unreadable component is not a full reading: report unknown.
if [ "$state" = ok ] && { [ "$load_state" = unknown ] || [ "$mem_state" = unknown ]; }; then state=unknown; fi

if [ "$JSON" -eq 1 ]; then
  printf '{"load1":%s,"cpus":%s,"load_per_cpu":%s,"mem_pressure":"%s","mem_source":"%s","state":"%s","busy_at":%s,"overloaded_at":%s}\n' \
    "${load1:-null}" "$CPUS" "${load_per_cpu:-null}" "$mem_state" "$mem_source" "$state" \
    "$(awk -v b="$BUSY" -v c="$CPUS" 'BEGIN { printf "%g", b * c }')" \
    "$(awk -v o="$OVER" -v c="$CPUS" 'BEGIN { printf "%g", o * c }')"
else
  echo "load1=${load1:-unknown}"
  echo "cpus=$CPUS"
  echo "load_per_cpu=${load_per_cpu:-unknown}"
  echo "mem_pressure=$mem_state"
  echo "mem_source=$mem_source"
  echo "state=$state"
fi
exit 0
