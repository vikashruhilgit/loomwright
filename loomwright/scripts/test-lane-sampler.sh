#!/usr/bin/env bash
# test-lane-sampler.sh — offline self-test for lane-sampler.sh. Every reading comes from a stub
# named through the sampler's seams (lsof, ps, sysctl, vm_stat, pgrep, a fixture /proc, the load
# reader, the CI-slot helper, the two notifiers), so no result depends on the machine running it.
#
# Arms:
#   (A)  macOS attribution by cwd on a fixture process tree: per-lane RSS/procs, a process in a
#        lane SUBdirectory counts, lane L1 does not swallow lane L10 (path-prefix boundary), the
#        non-lane RSS and CPU shares; lane names come from the .lanes table (header/comment skipped)
#        MUTATION CONTROL: drop the trailing "/" from the prefix match ⇒ L10's process lands in L1
#   (B)  Linux readers: /proc/<pid>/cwd symlinks attribute by cwd; swap and free from meminfo
#   (C)  unreadable: ps, load reader, CI-slot helper, swap/free all failing ⇒ `unknown` fields, exit 0;
#        no .lanes table ⇒ a line with no per-lane fields
#   (S)  CI-slot holders/waiters counted from `ci-slot.sh status`; vm_stat's own page size is used
#   (G)  memory guard on a fixture series: trips after N pressured samples (trip file = UTC ts +
#        the triggering sample, one notification), clears after N calm samples (file removed); a
#        new sampler adopts an existing trip file and clears it; unreadable swap is neutral
#        MUTATION CONTROL: drop the swap-growth condition ⇒ low free alone trips (the leg fails)
#   (X)  crossings notify exactly once each: busy, overloaded (latched until ok), keep-awake lost
#        (never at start)
#   (P)  the loop stops when the parent dies, and when the parent pid's start time changes, and
#        when the parent is an unreaped zombie (ps stat Z — `kill -0` alone still succeeds)
#   (B2) Linux: a /proc cwd link reading "<lane path> (deleted)" (the lane root removed under a
#        live process) still attributes to that lane, not to non-lane
#   (L)  every fleet.log line is a sample line (no comment lines), at the default path
#   (U)  usage: missing --parent-run-id / --parent-pid, a run id with "/", bad --interval ⇒ exit 2;
#        --help prints the header
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/lane-sampler.sh"
[ -f "$SUT" ] || { echo "test-lane-sampler: $SUT not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "test-lane-sampler: FATAL: jq required" >&2; exit 1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/lane-sampler-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
unset LOOMWRIGHT_LANE_MEM_FREE_MB LOOMWRIGHT_LANE_MEM_SAMPLES LOOMWRIGHT_LANE_SAMPLER_INTERVAL \
      LOOMWRIGHT_LANE_KEEPAWAKE_PROC

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
no() { fail=$((fail + 1)); echo "FAIL $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$3', got '$2')"; fi; }
fld() { printf '%s\n' "$2" | awk -v k="$1=" '{ for (i = 1; i <= NF; i++) if (index($i, k) == 1) { print substr($i, length(k) + 1); exit } }'; }

FX="$tmp/fx"; ST="$tmp/stubs"; mkdir -p "$FX" "$ST"
# series NAME — prints the next line of $FX/NAME.series (the last line once exhausted).
cat > "$ST/series" <<'EOF'
#!/bin/sh
n=$(cat "$FX/$1.n" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$FX/$1.n"
t=$(wc -l < "$FX/$1.series"); [ "$n" -gt "$t" ] && n=$t
sed -n "${n}p" "$FX/$1.series"
EOF
cat > "$ST/ps" <<'EOF'
#!/bin/sh
case "$*" in *lstart=*) cat "$FX/lstart" 2>/dev/null; exit 0 ;; esac
case "$*" in *stat=*) cat "$FX/stat" 2>/dev/null; exit 0 ;; esac
[ -f "$FX/ps.fail" ] && exit 1
cat "$FX/ps"
EOF
cat > "$ST/lsof" <<'EOF'
#!/bin/sh
cat "$FX/lsof"
EOF
cat > "$ST/sysctl" <<'EOF'
#!/bin/sh
[ "$2" = vm.swapusage ] || exit 1
[ -f "$FX/swap.fail" ] && exit 1
if [ -f "$FX/swap.series" ]; then s=$("$ST/series" swap); else s=$(cat "$FX/swap"); fi
echo "total = 8192.00M  used = ${s}  free = 1.00M  (encrypted)"
EOF
cat > "$ST/vm_stat" <<'EOF'
#!/bin/sh
[ -f "$FX/free.fail" ] && exit 1
if [ -f "$FX/free.series" ]; then f=$("$ST/series" free); else f=$(cat "$FX/free"); fi
echo "Mach Virtual Memory Statistics: (page size of 4096 bytes)"
echo "Pages free:                               $((f * 256))."
echo "Pages active:                             1234."
EOF
cat > "$ST/pgrep" <<'EOF'
#!/bin/sh
[ -f "$FX/ka.series" ] || exit 1
[ "$("$ST/series" ka)" = 1 ]
EOF
cat > "$ST/load" <<'EOF'
#!/bin/sh
[ -f "$FX/load.fail" ] && exit 1
if [ -f "$FX/load.series" ]; then l=$("$ST/series" load); else l=$(cat "$FX/load" 2>/dev/null || echo 2.00); fi
echo "{\"load1\":$l,\"cpus\":12,\"load_per_cpu\":0.10,\"mem_pressure\":\"ok\",\"mem_source\":\"x\",\"state\":\"ok\",\"busy_at\":24,\"overloaded_at\":36}"
EOF
cat > "$ST/ci-slot.sh" <<'EOF'
[ -f "$FX/slot.fail" ] && exit 1
echo "dir: /x"
cat "$FX/slot" 2>/dev/null
exit 0
EOF
mkdir -p "$ST/notifiers"
cat > "$ST/notifiers/notify-desktop.sh" <<'EOF'
echo "desktop $(cat)" >> "$FX/notify.log"
EOF
cat > "$ST/notifiers/send-webhook.sh" <<'EOF'
echo "webhook $*" >> "$FX/notify.log"
EOF
chmod +x "$ST/series" "$ST/ps" "$ST/lsof" "$ST/sysctl" "$ST/vm_stat" "$ST/pgrep" "$ST/load"

export FX ST
export LOOMWRIGHT_LANE_SAMPLER_PS="$ST/ps" LOOMWRIGHT_LANE_SAMPLER_LSOF="$ST/lsof" \
       LOOMWRIGHT_LANE_SAMPLER_SYSCTL="$ST/sysctl" LOOMWRIGHT_LANE_SAMPLER_VM_STAT="$ST/vm_stat" \
       LOOMWRIGHT_LANE_SAMPLER_PGREP="$ST/pgrep" LOOMWRIGHT_MACHINE_LOAD_CMD="$ST/load" \
       LOOMWRIGHT_LANE_SAMPLER_CI_SLOT="$ST/ci-slot.sh" LOOMWRIGHT_LANE_SAMPLER_NOTIFIER_DIR="$ST/notifiers" \
       LOOMWRIGHT_LANE_SAMPLER_OS=darwin

ROOT="$tmp/primary"; AD="$ROOT/.supervisor/automate"; mkdir -p "$AD"
RID="automate-2026-10-07-000000"
reset_fx() { rm -rf "$FX"; mkdir -p "$FX"; echo "FIXED-START" > "$FX/lstart"; echo 2048.00M > "$FX/swap"; echo 4000 > "$FX/free"; : > "$FX/notify.log"
  rm -f "$AD/$RID".*; }
once() { bash "${SAMPLER:-$SUT}" --once --parent-run-id "$RID" --root "$ROOT"; }
loop() { bash "${SAMPLER:-$SUT}" --parent-run-id "$RID" --parent-pid "$$" --root "$ROOT" --interval 0 "$@" 2>/dev/null; }
notes() { grep -c "^webhook .*--gate-type $1 " "$FX/notify.log" 2>/dev/null || true; }

# ---- (A) macOS attribution by cwd -------------------------------------------------------------
reset_fx
L="/fx/lanes/r"
printf 'lane\tpath\titem\trun_id\n# a comment row\nL1\t%s/L1\tq/a.md\t%s-L1\nL10\t%s/L10\tq/b.md\t%s-L10\n' "$L" "$RID" "$L" "$RID" > "$AD/$RID.lanes"
# pid 101 at the L1 root, 102 in an L1 subdir, 103 in L10 (shares L1's prefix), 104 and 105 elsewhere.
printf 'p101\nfcwd\nn%s/L1\np102\nfcwd\nn%s/L1/loomwright/scripts\np103\nfcwd\nn%s/L10\np104\nfcwd\nn/opt/other/hub\np105\nfcwd\nn/\n' "$L" "$L" "$L" > "$FX/lsof"
printf '  101  102400  10.0\n  102  51200   5.0\n  103  204800  25.0\n  104  1024000 60.0\n  105  10240   0.0\n  106  2048    0.0\n' > "$FX/ps"
line="$(once)"; rc=$?
check "(A) exit 0" "$rc" 0
check "(A) L1 RSS = root + subdir process (150 MB)" "$(fld rss_mb.L1 "$line")" 150
check "(A) L1 procs = 2" "$(fld procs.L1 "$line")" 2
check "(A) L10 RSS not swallowed by L1 (200 MB)" "$(fld rss_mb.L10 "$line")" 200
check "(A) L10 procs = 1" "$(fld procs.L10 "$line")" 1
check "(A) lane_rss_mb" "$(fld lane_rss_mb "$line")" 350
check "(A) nonlane_rss_mb (incl. a process with no readable cwd)" "$(fld nonlane_rss_mb "$line")" 1012
check "(A) nonlane_rss_pct" "$(fld nonlane_rss_pct "$line")" 74.3
check "(A) nonlane_load_pct (CPU share outside lanes)" "$(fld nonlane_load_pct "$line")" 60.0
case "$line" in *rss_mb.lane=*|*"rss_mb.#"*) no "(A) header/comment rows skipped" ;; *) ok "(A) header/comment rows skipped" ;; esac
case "$line" in 20[0-9][0-9]-[0-1][0-9]-[0-3][0-9]T*Z\ holders=*) ok "(A) line starts with a UTC timestamp" ;; *) no "(A) line starts with a UTC timestamp: $line" ;; esac
# MUTATION CONTROL: prefix match without the trailing "/" lets L1 swallow L10's process.
MUT="$tmp/mutant-prefix.sh"
sed 's|index(c, path\[i\] "/") == 1|index(c, path[i]) == 1|' "$SUT" > "$MUT"
if cmp -s "$SUT" "$MUT"; then no "(A) mutation control applied (pattern not found)"
else
  mline="$(SAMPLER="$MUT" once)"
  if [ "$(fld rss_mb.L10 "$mline")" != 200 ]; then ok "(A) MUTATION CONTROL: prefix without '/' breaks the L10 check"
  else no "(A) MUTATION CONTROL: mutant still passed the L10 check"; fi
fi

# ---- (B) Linux readers ------------------------------------------------------------------------
reset_fx
# /proc/<pid>/cwd is always canonical on Linux, and the sampler canonicalises lane paths: point
# the fixture links at canonical paths (macOS TMPDIR sits behind the /var -> /private/var link).
P="$tmp/proc"; mkdir -p "$P" "$tmp/lin/L1/sub" "$tmp/lin/L2" "$tmp/lin/other"
lin="$(cd "$tmp/lin" && pwd -P)"
mkdir -p "$P/201" "$P/202" "$P/203" "$P/204"
ln -s "$lin/L1/sub" "$P/201/cwd"; ln -s "$lin/L2" "$P/202/cwd"; ln -s "$lin/other" "$P/203/cwd"   # 204: no cwd link
printf 'MemTotal:  16000000 kB\nMemFree:   100000 kB\nMemAvailable:  2048000 kB\nSwapTotal:  4194304 kB\nSwapFree:  3145728 kB\n' > "$P/meminfo"
printf '201 10240 1.0\n202 20480 1.0\n203 30720 2.0\n204 1024 0\n' > "$FX/ps"
printf 'L1\t%s\tq/a.md\nL2\t%s\tq/b.md\n' "$tmp/lin/L1" "$tmp/lin/L2" > "$AD/$RID.lanes"
line="$(LOOMWRIGHT_LANE_SAMPLER_OS=linux LOOMWRIGHT_LANE_SAMPLER_PROC="$P" once)"
check "(B) Linux L1 by /proc cwd (subdir)" "$(fld rss_mb.L1 "$line")" 10
check "(B) Linux L2 by /proc cwd" "$(fld rss_mb.L2 "$line")" 20
check "(B) Linux nonlane_rss_mb" "$(fld nonlane_rss_mb "$line")" 31
check "(B) Linux swap_used_mb = SwapTotal - SwapFree" "$(fld swap_used_mb "$line")" 1024
check "(B) Linux free_mb = MemAvailable" "$(fld free_mb "$line")" 2000
check "(B) keep_awake na off macOS" "$(fld keep_awake "$line")" na

# ---- (B2) Linux: a removed cwd ("<path> (deleted)") still attributes to its lane ---------------
reset_fx
P2="$tmp/proc2"; mkdir -p "$P2/301" "$P2/302"
# 301: the lane ROOT itself was removed (the suffix breaks both the exact and the "<path>/" match);
# 303: a removed subdirectory of L2; 302: a removed dir outside every lane.
mkdir -p "$P2/303"
ln -s "$lin/L1 (deleted)" "$P2/301/cwd"; ln -s "$lin/other (deleted)" "$P2/302/cwd"; ln -s "$lin/L2/gone (deleted)" "$P2/303/cwd"
printf '301 40960 1.0\n302 5120 1.0\n303 2048 1.0\n' > "$FX/ps"
printf 'L1\t%s\tq/a.md\nL2\t%s\tq/b.md\n' "$tmp/lin/L1" "$tmp/lin/L2" > "$AD/$RID.lanes"
line="$(LOOMWRIGHT_LANE_SAMPLER_OS=linux LOOMWRIGHT_LANE_SAMPLER_PROC="$P2" once)"
check "(B2) deleted lane-root cwd attributes to L1" "$(fld rss_mb.L1 "$line")" 40
check "(B2) deleted subdir cwd attributes to L2" "$(fld rss_mb.L2 "$line")" 2
check "(B2) deleted cwd outside every lane stays non-lane" "$(fld nonlane_rss_mb "$line")" 5

# ---- (C) unreadable ---------------------------------------------------------------------------
reset_fx
: > "$FX/ps.fail"; : > "$FX/load.fail"; : > "$FX/slot.fail"; : > "$FX/swap.fail"; : > "$FX/free.fail"
line="$(once)"; rc=$?
check "(C) exit 0 with everything unreadable" "$rc" 0
for k in holders waiters load1 load_state swap_used_mb free_mb lane_rss_mb nonlane_rss_pct nonlane_load_pct; do
  check "(C) $k unknown" "$(fld "$k" "$line")" unknown
done
case "$line" in *rss_mb.*) no "(C) no .lanes table ⇒ no per-lane fields" ;; *) ok "(C) no .lanes table ⇒ no per-lane fields" ;; esac

# ---- (S) CI-slot counts and vm_stat page size ---------------------------------------------------
reset_fx
printf 'holder: slot 1 pid 11 /a ci-local\nholder: slot 2 pid 12 /b ci-local\nwaiter: ticket 3 pid 13 /c ci-local\n' > "$FX/slot"
echo 300 > "$FX/free"; echo 1536.60M > "$FX/swap"; echo '' > "$FX/ps"
line="$(once)"
check "(S) holders" "$(fld holders "$line")" 2
check "(S) waiters" "$(fld waiters "$line")" 1
check "(S) free_mb from vm_stat's own page size" "$(fld free_mb "$line")" 300
check "(S) swap_used_mb from vm.swapusage" "$(fld swap_used_mb "$line")" 1537
echo 1.50G > "$FX/swap"
check "(S) swap in G converts to MB" "$(fld swap_used_mb "$(once)")" 1536

# ---- (G) memory guard ---------------------------------------------------------------------------
TRIP="$AD/$RID.memory-pressure"
reset_fx; : > "$FX/ps"; rm -f "$FX/free" "$FX/swap"
printf '100\n100\n100\n100\n' > "$FX/free.series"; printf '1000M\n1100M\n1200M\n1300M\n' > "$FX/swap.series"
loop --max-samples 3
check "(G) 3 samples: not yet tripped (first sample has no previous swap)" "$([ -f "$TRIP" ] && echo yes || echo no)" no
check "(G) streak shown as pressured:2" "$(fld memory_guard "$(tail -n 1 "$AD/$RID.fleet.log")")" pressured:2
reset_fx; : > "$FX/ps"; rm -f "$FX/free" "$FX/swap"
printf '100\n100\n100\n100\n100\n100\n100\n100\n' > "$FX/free.series"
printf '1000M\n1100M\n1200M\n1300M\n1400M\n1400M\n1400M\n1400M\n' > "$FX/swap.series"
loop --max-samples 5
check "(G) trips on the 4th sample (3 pressured)" "$([ -f "$TRIP" ] && echo yes || echo no)" yes
check "(G) trip file line 1 = UTC ts" "$(sed -n 1p "$TRIP" | grep -cE '^tripped_utc: 20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$')" 1
check "(G) trip file line 2 = the triggering sample" "$(sed -n 2p "$TRIP" | sed 's/^sample: //' | awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^swap_used_mb=/) print $i }')" swap_used_mb=1300
check "(G) one notification for one trip" "$(notes lane_memory_pressure)" 1
check "(G) 4th line says tripped" "$(fld memory_guard "$(sed -n 4p "$AD/$RID.fleet.log")")" tripped
# adoption: a new sampler sees the trip file; three calm samples clear it, no new notification.
: > "$FX/notify.log"
loop --max-samples 2
check "(G) adopted trip still held after 2 calm samples" "$([ -f "$TRIP" ] && echo yes || echo no)" yes
loop --max-samples 4
check "(G) cleared after 3 calm samples (file removed)" "$([ -f "$TRIP" ] && echo yes || echo no)" no
check "(G) the clear sample says ok" "$(fld memory_guard "$(tail -n 1 "$AD/$RID.fleet.log")")" ok
check "(G) adoption does not re-notify" "$(notes lane_memory_pressure)" 0
# unreadable swap is neutral: never trips, never counts as calm.
reset_fx; : > "$FX/ps"; : > "$FX/swap.fail"; echo 100 > "$FX/free"
loop --max-samples 5
check "(G) unreadable swap never trips" "$([ -f "$TRIP" ] && echo yes || echo no)" no
# low free alone (swap flat) does not trip; MUTATION CONTROL: drop the growth condition ⇒ it does.
reset_fx; : > "$FX/ps"; echo 100 > "$FX/free"; echo 1000M > "$FX/swap"
loop --max-samples 5
check "(G) low free with flat swap does not trip" "$([ -f "$TRIP" ] && echo yes || echo no)" no
MUT="$tmp/mutant-growth.sh"
sed 's/ && is_uint "\$prev_sw" && \[ "\$sw" -gt "\$prev_sw" \]//' "$SUT" > "$MUT"
if cmp -s "$SUT" "$MUT"; then no "(G) mutation control applied (pattern not found)"
else
  reset_fx; : > "$FX/ps"; echo 100 > "$FX/free"; echo 1000M > "$FX/swap"
  SAMPLER="$MUT" loop --max-samples 5
  if [ -f "$TRIP" ]; then ok "(G) MUTATION CONTROL: without the swap-growth condition the flat-swap leg fails"
  else no "(G) MUTATION CONTROL: mutant did not trip"; fi
fi

# ---- (X) crossings ----------------------------------------------------------------------------
reset_fx; : > "$FX/ps"
printf '2.0\n25.0\n26.0\n40.0\n30.0\n41.0\nnull\n10.0\n30.0\n' > "$FX/load.series"
printf '0\n1\n1\n0\n0\n1\n0\n0\n0\n' > "$FX/ka.series"
LOOMWRIGHT_LANE_KEEPAWAKE_PROC=caffeinate loop --max-samples 9
check "(X) busy crossing notified once per crossing (2 crossings)" "$(notes lane_load_busy)" 2
check "(X) overloaded notified once (latched until load returns to ok)" "$(notes lane_load_overloaded)" 1
check "(X) keep-awake lost notified per loss, never at start (2)" "$(notes lane_keep_awake_lost)" 2
check "(X) desktop banner fired for each webhook" "$(grep -c '^desktop ' "$FX/notify.log")" 5
check "(X) unreadable load line says unknown" "$(fld load_state "$(sed -n 7p "$AD/$RID.fleet.log")")" unknown

# ---- (P) stops with the parent ------------------------------------------------------------------
wait_gone() { local i=0; while kill -0 "$1" 2>/dev/null && [ "$i" -lt 50 ]; do sleep 0.2; i=$((i + 1)); done; ! kill -0 "$1" 2>/dev/null; }
reset_fx; : > "$FX/ps"
sleep 60 & PARENT=$!
bash "$SUT" --parent-run-id "$RID" --parent-pid "$PARENT" --root "$ROOT" --interval 1 2>/dev/null & SPID=$!
i=0; while [ ! -s "$AD/$RID.fleet.log" ] && [ "$i" -lt 50 ]; do sleep 0.2; i=$((i + 1)); done
check "(P) sampling while the parent lives" "$([ -s "$AD/$RID.fleet.log" ] && echo yes || echo no)" yes
kill "$PARENT" 2>/dev/null; wait "$PARENT" 2>/dev/null
if wait_gone "$SPID"; then ok "(P) sampler exits when the parent dies"; else no "(P) sampler outlived its parent"; kill "$SPID" 2>/dev/null; fi
wait "$SPID" 2>/dev/null; check "(P) exit 0 on parent death" "$?" 0
sleep 60 & PARENT=$!
bash "$SUT" --parent-run-id "$RID" --parent-pid "$PARENT" --root "$ROOT" --interval 1 2>/dev/null & SPID=$!
sleep 1; echo "OTHER-START" > "$FX/lstart"
if wait_gone "$SPID"; then ok "(P) a recycled parent pid (start time changed) stops the sampler"; else no "(P) sampler kept running on a recycled pid"; kill "$SPID" 2>/dev/null; fi
wait "$SPID" 2>/dev/null; kill "$PARENT" 2>/dev/null; wait "$PARENT" 2>/dev/null
sleep 60 & PARENT=$!
echo S > "$FX/stat"
bash "$SUT" --parent-run-id "$RID" --parent-pid "$PARENT" --root "$ROOT" --interval 1 2>/dev/null & SPID=$!
sleep 1
check "(P) a live (non-zombie) parent keeps the sampler running" "$(kill -0 "$SPID" 2>/dev/null && echo yes || echo no)" yes
echo Z > "$FX/stat"
if wait_gone "$SPID"; then ok "(P) a zombie parent (ps stat Z, kill -0 still succeeds) stops the sampler"; else no "(P) sampler kept running on a zombie parent"; kill "$SPID" 2>/dev/null; fi
wait "$SPID" 2>/dev/null; kill "$PARENT" 2>/dev/null; wait "$PARENT" 2>/dev/null; rm -f "$FX/stat"
dead=$PARENT
bash "$SUT" --parent-run-id "$RID" --parent-pid "$dead" --root "$ROOT" --interval 0 2>/dev/null; rc=$?
check "(P) a parent already gone ⇒ exit 0 at once" "$rc" 0

# ---- (L) fleet.log lines ------------------------------------------------------------------------
reset_fx; : > "$FX/ps"
loop --max-samples 3
check "(L) default path gets one line per sample" "$(wc -l < "$AD/$RID.fleet.log" | tr -d ' ')" 3
check "(L) no comment lines in fleet.log" "$(grep -c '^#' "$AD/$RID.fleet.log")" 0
loop --max-samples 1 --fleet-log "$tmp/custom.fleet.log"
check "(L) --fleet-log overrides the path" "$(wc -l < "$tmp/custom.fleet.log" | tr -d ' ')" 1

# ---- (U) usage ----------------------------------------------------------------------------------
bash "$SUT" --parent-pid 1 >/dev/null 2>&1; check "(U) missing --parent-run-id ⇒ 2" "$?" 2
bash "$SUT" --parent-run-id "$RID" --root "$ROOT" >/dev/null 2>&1; check "(U) loop without --parent-pid ⇒ 2" "$?" 2
bash "$SUT" --once --parent-run-id "a/b" >/dev/null 2>&1; check "(U) run id with '/' ⇒ 2" "$?" 2
bash "$SUT" --parent-run-id "$RID" --parent-pid 1 --interval x >/dev/null 2>&1; check "(U) bad --interval ⇒ 2" "$?" 2
bash "$SUT" --bogus >/dev/null 2>&1; check "(U) unknown argument ⇒ 2" "$?" 2
check "(U) --help prints the header" "$(bash "$SUT" --help | grep -c 'MEMORY GUARD')" 1

echo "test-lane-sampler: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
