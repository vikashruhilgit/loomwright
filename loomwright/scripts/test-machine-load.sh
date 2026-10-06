#!/usr/bin/env bash
# test-machine-load.sh — offline self-test for machine-load.sh. Every reading but the host arm comes
# from fixtures: a stub sysctl (macOS path) or a fixture /proc dir (Linux path), so the result never
# depends on how loaded the machine running the suite is.
#
# Arms:
#   (F)  five fields, plain and --json, on both readers (darwin stub, linux fixture /proc)
#   (P)  macOS pressure level 1/2/4 ⇒ ok/busy/overloaded (3 ⇒ busy); level 0 / garbage ⇒ unknown
#        MUTATION CONTROL: map level 2 to ok ⇒ the busy check fails
#   (L)  load per CPU on 12 CPUs: 23.99 ok, 24 busy, 35.99 busy, 36 overloaded; zero-padded "07.50"
#        and fractional values read as decimals; LOOMWRIGHT_LOAD_BUSY / _OVERLOADED override (decimals
#        allowed); a malformed multiplier falls back to the default with a warning
#   (M)  Linux MemAvailable/MemTotal: 20 % ok, 14 % busy, 7 % overloaded
#   (U)  unreadable ⇒ state=unknown, exit 0: no sysctl at all, an empty /proc, a missing meminfo
#        next to an ok load; a readable "overloaded" is never hidden behind an unreadable neighbour
#   (H)  the host: real reader exits 0 with five fields and a state in the set (Linux on CI)
#   (X)  usage: an unknown argument exits 2; --help prints the de-commented header
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/machine-load.sh"
[ -f "$SUT" ] || { echo "test-machine-load: $SUT not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "test-machine-load: FATAL: jq required" >&2; exit 1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/machine-load-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
unset LOOMWRIGHT_LOAD_BUSY LOOMWRIGHT_LOAD_OVERLOADED LOOMWRIGHT_MACHINE_LOAD_OS \
      LOOMWRIGHT_MACHINE_LOAD_SYSCTL LOOMWRIGHT_MACHINE_LOAD_PROC
export LOOMWRIGHT_CI_CPUS=12

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
no() { fail=$((fail + 1)); echo "FAIL $1"; }

# Stub sysctl: answers from FX_LOADAVG / FX_LEVEL, fails (like a missing OID) when one is unset.
cat > "$tmp/sysctl" <<'EOF'
#!/bin/sh
case "$2" in
  vm.loadavg) [ -n "${FX_LOADAVG:-}" ] || exit 1; echo "{ $FX_LOADAVG 1.00 1.00 }" ;;
  kern.memorystatus_vm_pressure_level) [ -n "${FX_LEVEL:-}" ] || exit 1; echo "$FX_LEVEL" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$tmp/sysctl"
# mac SUT LOAD LEVEL [ARGS] — the darwin reader against the stub.
mac() { local s="$1" l="$2" v="$3"; shift 3
  FX_LOADAVG="$l" FX_LEVEL="$v" LOOMWRIGHT_MACHINE_LOAD_OS=darwin LOOMWRIGHT_MACHINE_LOAD_SYSCTL="$tmp/sysctl" bash "$s" "$@"; }
field() { sed -n "s/^$1=//p"; }
# lin LOAD AVAIL_KB [ARGS] — the linux reader against a fixture /proc (MemTotal 1000000 kB).
lin() { local l="$1" a="$2" p="$tmp/proc.$RANDOM"; shift 2; mkdir -p "$p"
  [ "$l" = - ] || echo "$l 1.00 1.00 1/100 4242" > "$p/loadavg"
  [ "$a" = - ] || printf 'MemTotal:        1000000 kB\nMemFree:           10000 kB\nMemAvailable:    %s kB\n' "$a" > "$p/meminfo"
  LOOMWRIGHT_MACHINE_LOAD_OS=linux LOOMWRIGHT_MACHINE_LOAD_PROC="$p" bash "$SUT" "$@"; }

# --- (F) -------------------------------------------------------------------------------------------
five='has("load1") and has("cpus") and has("load_per_cpu") and has("mem_pressure") and has("state")'
out="$(mac "$SUT" 6.00 1 --json)"
if jq -e "$five and .load1 == 6 and .cpus == 12 and .load_per_cpu == 0.5 and .mem_pressure == \"ok\" and .state == \"ok\"" <<<"$out" >/dev/null; then
  ok "(F) darwin --json: load1 6, cpus 12, load_per_cpu 0.5, mem_pressure ok, state ok"
else no "(F) darwin --json: $out"; fi
out="$(lin 3.00 500000 --json)"
if jq -e "$five and .load1 == 3 and .load_per_cpu == 0.25 and .mem_pressure == \"ok\" and .state == \"ok\"" <<<"$out" >/dev/null; then
  ok "(F) linux --json: the same five fields from /proc"
else no "(F) linux --json: $out"; fi
out="$(mac "$SUT" 6.00 1)"
if [ "$(printf '%s\n' "$out" | grep -cE '^(load1|cpus|load_per_cpu|mem_pressure|state)=')" = 5 ] \
   && [ "$(field state <<<"$out")" = ok ] && [ "$(field load1 <<<"$out")" = 6.00 ]; then
  ok "(F) plain: the five key=value lines"
else no "(F) plain: $out"; fi

# --- (P) -------------------------------------------------------------------------------------------
levels() {   # levels SUT — exit 0 iff 1/2/3/4 map to ok/busy/busy/overloaded at a low load
  local s="$1" v want got
  for v in 1:ok 2:busy 3:busy 4:overloaded; do
    want="${v#*:}"; got="$(mac "$s" 1.00 "${v%%:*}" | field state)"
    [ "$got" = "$want" ] || { PWHY="level ${v%%:*}: got $got, want $want"; return 1; }
  done
}
if levels "$SUT"; then ok "(P) pressure level 1/2/3/4 ⇒ ok/busy/busy/overloaded"; else no "(P) $PWHY"; fi
if [ "$(mac "$SUT" 1.00 0 | field state)" = unknown ] && [ "$(mac "$SUT" 1.00 high | field state)" = unknown ] \
   && [ "$(mac "$SUT" 1.00 high | field mem_pressure)" = unknown ]; then ok "(P) level 0 and a garbage level read as unknown"
else no "(P) level 0 / garbage not unknown"; fi
mut="$tmp/mut-level.sh"
sed 's/1) mem_state=ok ;; 2|3) mem_state=busy ;;/1|2) mem_state=ok ;; 3) mem_state=busy ;;/' "$SUT" > "$mut"
if [ -s "$mut" ] && ! cmp -s "$mut" "$SUT" && bash -n "$mut"; then
  if levels "$mut"; then no "(P) MUTATION CONTROL: level 2 ⇒ ok still passed — (P) proves nothing"
  else ok "(P) MUTATION CONTROL: mapping level 2 to ok fails (P) ($PWHY)"; fi
else no "(P) MUTATION CONTROL: mutant not built (empty, unchanged or invalid)"; fi

# --- (L) -------------------------------------------------------------------------------------------
lok=1
for v in 23.99:ok 24:busy 24.00:busy 35.99:busy 36:overloaded 119.40:overloaded 07.50:ok 0.5:ok; do
  got="$(mac "$SUT" "${v%%:*}" 1 | field state)"
  [ "$got" = "${v#*:}" ] || { lok=0; no "(L) load1 ${v%%:*} on 12 CPUs: got $got, want ${v#*:}"; }
done
[ "$lok" -eq 1 ] && ok "(L) 12 CPUs: busy at 24 (2x), overloaded at 36 (3x); 07.50 and 0.5 read as decimals"
if [ "$(mac "$SUT" 07.50 1 | field load1)" = 7.50 ]; then ok "(L) a zero-padded load1 is reported as 7.50"; else no "(L) zero-padded load1 misread"; fi
if [ "$(LOOMWRIGHT_LOAD_BUSY=1 mac "$SUT" 12 1 | field state)" = busy ] \
   && [ "$(LOOMWRIGHT_LOAD_BUSY=1 LOOMWRIGHT_LOAD_OVERLOADED=1.5 mac "$SUT" 18 1 | field state)" = overloaded ] \
   && [ "$(LOOMWRIGHT_LOAD_OVERLOADED=1.5 mac "$SUT" 17.99 1 | field state)" = ok ]; then
  ok "(L) LOOMWRIGHT_LOAD_BUSY=1 / _OVERLOADED=1.5 move the thresholds to 12 / 18"
else no "(L) multiplier overrides ignored"; fi
out="$(LOOMWRIGHT_LOAD_BUSY=abc mac "$SUT" 24 1 2>"$tmp/m.err")"
if [ "$(field state <<<"$out")" = busy ] && grep -q "LOOMWRIGHT_LOAD_BUSY must be a positive number, got 'abc'" "$tmp/m.err"; then
  ok "(L) a malformed multiplier falls back to the default, with a warning"
else no "(L) malformed multiplier: out=$out err=$(cat "$tmp/m.err")"; fi

# --- (M) -------------------------------------------------------------------------------------------
if [ "$(lin 1.00 200000 | field state)" = ok ] && [ "$(lin 1.00 140000 | field state)" = busy ] \
   && [ "$(lin 1.00 70000 | field state)" = overloaded ] && [ "$(lin 1.00 70000 | field mem_pressure)" = overloaded ]; then
  ok "(M) linux MemAvailable 20 % ok, 14 % busy, 7 % overloaded"
else no "(M) linux memory: 20%=$(lin 1.00 200000 | field state) 14%=$(lin 1.00 140000 | field state) 7%=$(lin 1.00 70000 | field state)"; fi

# --- (U) -------------------------------------------------------------------------------------------
out="$(LOOMWRIGHT_MACHINE_LOAD_OS=darwin LOOMWRIGHT_MACHINE_LOAD_SYSCTL="$tmp/no-such-sysctl" bash "$SUT" --json 2>/dev/null)"; rc=$?
if [ "$rc" = 0 ] && jq -e '.state == "unknown" and .load1 == null and .load_per_cpu == null and .mem_pressure == "unknown"' <<<"$out" >/dev/null; then
  ok "(U) no sysctl: state=unknown, nulls, exit 0"
else no "(U) no sysctl: rc=$rc out=$out"; fi
out="$(lin - - 2>/dev/null)"; rc=$?
if [ "$rc" = 0 ] && [ "$(field state <<<"$out")" = unknown ] && [ "$(field load1 <<<"$out")" = unknown ]; then ok "(U) empty /proc: state=unknown, exit 0"
else no "(U) empty /proc: rc=$rc out=$out"; fi
if [ "$(lin 1.00 - | field state)" = unknown ] && [ "$(mac "$SUT" "" 1 | field state)" = unknown ]; then
  ok "(U) one unreadable component next to an ok one ⇒ unknown, never a claimed ok"
else no "(U) partial read reported ok"; fi
if [ "$(lin - 70000 | field state)" = overloaded ] && [ "$(mac "$SUT" 40 "" | field state)" = overloaded ]; then
  ok "(U) a readable overloaded is not hidden behind an unreadable neighbour"
else no "(U) overloaded hidden: $(lin - 70000 | field state) / $(mac "$SUT" 40 "" | field state)"; fi

# --- (H) -------------------------------------------------------------------------------------------
unset LOOMWRIGHT_CI_CPUS
out="$(bash "$SUT" --json)"; rc=$?
if [ "$rc" = 0 ] && jq -e "$five and (.state | IN(\"ok\",\"busy\",\"overloaded\",\"unknown\")) and .cpus > 0" <<<"$out" >/dev/null; then
  ok "(H) host ($(uname -s)): exit 0, five fields, state $(jq -r .state <<<"$out")"
else no "(H) host: rc=$rc out=$out"; fi

# --- (X) -------------------------------------------------------------------------------------------
bash "$SUT" --bogus >/dev/null 2>&1; r1=$?
out="$(bash "$SUT" --help)"
if [ "$r1" = 2 ] && grep -q '^machine-load.sh — ' <<<"$out" && grep -q '^Self-test: loomwright/scripts/test-machine-load.sh' <<<"$out" \
   && ! grep -q 'set -uo' <<<"$out"; then ok "(X) unknown argument exits 2; --help prints the de-commented header"
else no "(X) usage: rc=$r1 help=$out"; fi

echo
echo "test-machine-load: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
