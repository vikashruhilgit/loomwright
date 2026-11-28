# =============================================================================
# SG. the parts refuse to run standalone; a fixture cd group stops on a failed cd (issue #994).
# Run alone (`bash <this file>`), this part re-runs the suite for itself and nothing else (see 01-config.sh).
if [ "${BASH_SOURCE[0]}" = "$0" ]; then exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test-automate-helpers.sh" 20-standalone-guard; fi
echo "== SG. parts refuse to run standalone; fixture cd groups stop on a failed cd =="
# A part run alone (`bash <part>`) has none of the runner's setup ($H, ok, no, the fixture roots), so a
# `( cd "$X" && a; rm … )` group ran on in the caller's checkout. Each part's first command is the guard
# that re-execs this runner for that one part; each cd group opens `cd "$X" || exit 1`. Every leg reads
# the runner's own $TAH_PARTS and $TAH_D — never a glob, never a second part list.
SG_T="$(mktemp -d)"; SG_T="$(cd "$SG_T" && pwd -P)"

# SG1 static — a ( / $( subshell opening with cd "…" then end of line, `;`, or `&&` with a `;` before
# the group's own `)` on that logical line (backslash-continued lines are joined first). The program and
# its planted control lines are test-automate-trail.sh's, byte-for-byte.
SG_SCAN='!cont && /^[ \t]*#/ { next }
{ if (cont) buf = buf $0; else { buf = $0; st = FNR }
  if (buf ~ /\\$/) { sub(/\\$/, "", buf); cont = 1; next }
  cont = 0; line = buf; n = length(line); i = 1
  while (i <= n && match(substr(line, i), /\([ \t]*cd "[^"]*"/)) {
    e = i + RSTART - 1 + RLENGTH; tl = substr(line, e); bad = 0
    if (tl ~ /^[ \t]*$/ || tl ~ /^[ \t]*;/) bad = 1
    else if (tl ~ /^[ \t]*&&/) {
      d = 1; q = 0
      for (j = e; j <= n; j++) { c = substr(line, j, 1)
        if (q) { if (c == "\047") q = 0; continue }
        if (c == "\047") q = 1
        else if (c == "#" && j > 1 && substr(line, j - 1, 1) ~ /[ \t]/) break
        else if (c == "(") d++
        else if (c == ")") { d--; if (d == 0) break }
        else if (c == ";" && d == 1) { bad = 1; break } } }
    if (bad) print F ":" st
    i = e } }'
SGC="$SG_T/sg-scan-control.sh"
# >>> sg1-control (this part's own scan blanks these three lines: they are the planted unsafe shapes)
  printf '%s\n' '( cd "$P" && git checkout -q -- README; rm -f stray.txt )' '  ( cd "$P"' 'x="$(cd "$P" && a >/dev/null; b)"' \
    '(cd "$P"; rm -f x)' '(cd "$P" && bash "$H" trail-pr x)   # a; b' '( cd "$P" || exit 1; rm -f x )' "(cd \"\$P\" && printf ';')" \
      '( cd "$P" \' '  ; rm -f x )' '( cd "$P" && git status \' '  && rm -f x )' '( cd "$P" && a \' '  ; rm -f x )' '(cd "$P"; rm -f y)' > "$SGC"
# <<< sg1-control
sg_ctl="$(awk -v F=control "$SG_SCAN" "$SGC" 2>&1)"
[ "$sg_ctl" = "$(printf 'control:1\ncontrol:2\ncontrol:3\ncontrol:4\ncontrol:8\ncontrol:12\ncontrol:14')" ] \
  && ok "SG1 control: the cd-group scan flags the seven unsafe shapes (two backslash-continued, reported at their first line) and none of the four safe ones" \
  || no "SG1 control: the cd-group scan read the planted lines as: $(printf '%s' "$sg_ctl" | tr '\n' ' ')"
# This part is scanned too, with only its marked control block blanked (line numbers kept). sg_pins
# compares that block, and the SG_SCAN program, line for line (leading whitespace stripped) with the
# same spans in test-automate-trail.sh, so the block is exactly the three control printf lines and
# nothing else can hide in it. Status: 0 both match, 1 the control block differs, 2 the program differs.
sg_trail="$TAH_D/../test-automate-trail.sh"
sg_span() {  # <file> <first-line prefix> <last-line suffix>: that span, leading whitespace stripped
  SGS_S="$2" SGS_E="$3" awk '{ sub(/^[ \t]+/, "") } !f && index($0, ENVIRON["SGS_S"]) == 1 { f = 1 }
    f { print; n = length($0); m = length(ENVIRON["SGS_E"]); if (n >= m && substr($0, n - m + 1) == ENVIRON["SGS_E"]) exit }' "$1"
}
sg_pins() {
  local ctl prog tc tp
  ctl="$(awk '/^# >>> sg1-control /{ f = 1; next } /^# <<< sg1-control$/{ f = 0 } f { sub(/^[ \t]+/, ""); print }' "$1")"
  tc="$(sg_span "$sg_trail" "printf '%s\n' '( cd \"\$P\" && git checkout -q -- README; rm -f stray.txt )'" ' > "$SGC"')"
  [ -n "$tc" ] && [ "$ctl" = "$tc" ] || return 1
  prog="$(sg_span "$1" "SG_SCAN='!cont && /^[ \t]*#/ { next }" "i = e } }'")"
  tp="$(sg_span "$sg_trail" "SG_SCAN='!cont && /^[ \t]*#/ { next }" "i = e } }'")"
  [ -n "$tp" ] && [ "$prog" = "$tp" ] || return 2
  return 0
}
sg_self="$TAH_D/20-standalone-guard.sh"
sg_pins "$sg_self"; sg_rc=$?
[ "$sg_rc" -eq 0 ] && ok "SG1 this part's sg1-control block and SG_SCAN program are test-automate-trail.sh's, line for line" \
  || no "SG1 20-standalone-guard.sh differs from test-automate-trail.sh: $( [ "$sg_rc" -eq 1 ] && echo 'the sg1-control block is not exactly its three control printf lines' || echo 'the SG_SCAN program')"
# The pin goes red on a copy (never this file) with a command hidden inside the first control line,
# with a fourth line added to the block, and with one character of the program changed.
# (The '' keeps this line's own text out of the cd-group scan; the copy reads `( cd "$SG_T/nope"; …`.)
sg_hide='>/dev/null; ( ''cd "$SG_T/nope"; : > "$SG_T/HIDDEN-RAN"; echo HIDDEN-RAN ); printf '"'%s\\n' "
SG_HIDE="$sg_hide" awk '/^# >>> sg1-control /{ f = 1; print; next } f && !d { i = index($0, "stray.txt )'"' "'")
  $0 = substr($0, 1, i + 12) ENVIRON["SG_HIDE"] substr($0, i + 13); d = 1 } { print }' "$sg_self" > "$SG_T/mut-hide.sh"
awk '/^# <<< sg1-control$/{ print "  : extra line" } { print }' "$sg_self" > "$SG_T/mut-extra.sh"
awk '!d && /^    i = e [}] [}]'"'"'$/{ sub(/i = e/, "i = e + 0"); d = 1 } { print }' "$sg_self" > "$SG_T/mut-prog.sh"
sg_m1=0; sg_m2=0; sg_m3=0
sg_pins "$SG_T/mut-hide.sh" || sg_m1=$?; sg_pins "$SG_T/mut-extra.sh" || sg_m2=$?; sg_pins "$SG_T/mut-prog.sh" || sg_m3=$?
# The hidden-command copy keeps the block's old shape (three lines, the first control argument first,
# `> "$SGC"` last), so a line-count and prefix/suffix check would pass it.
sg_mblk="$(awk '/^# >>> sg1-control /{ f = 1; next } /^# <<< sg1-control$/{ f = 0 } f' "$SG_T/mut-hide.sh")"
sg_mshape=0
case "$sg_mblk" in "  printf '%s\n' '( cd \"\$P\" && git checkout -q -- README; rm -f stray.txt )' >/dev/null; ( "*' > "$SGC"')
  [ "$(printf '%s\n' "$sg_mblk" | wc -l | tr -d ' ')" = 3 ] && sg_mshape=1 ;; esac
if [ "$sg_m1" -eq 1 ] && [ "$sg_m2" -eq 1 ] && [ "$sg_m3" -eq 2 ] && [ "$sg_mshape" = 1 ]; then
  ok "SG1 the pin fails a copy with a command hidden in a control line (block still three lines), an added block line, and an edited program"
else
  no "SG1 the pin missed a mutant copy: hidden-command=$sg_m1 extra-line=$sg_m2 program-edit=$sg_m3 (want 1 1 2), hidden copy keeps the old shape=$sg_mshape"
fi
sg_hits=""
for sg_p in $TAH_PARTS; do
  if [ "$sg_p" = 20-standalone-guard ]; then
    sg_hits="$sg_hits$(awk '/^# >>> sg1-control /{ f = 1; print ""; next } /^# <<< sg1-control$/{ f = 0 } { print (f ? "" : $0) }' "$sg_self" | awk -v F="test-automate-helpers.d/$sg_p.sh" "$SG_SCAN" 2>&1)
"
  else
    sg_hits="$sg_hits$(awk -v F="test-automate-helpers.d/$sg_p.sh" "$SG_SCAN" "$TAH_D/$sg_p.sh" 2>&1)
"
  fi
done
sg_hits="$(printf '%s' "$sg_hits" | grep -v '^$')"
[ -z "$sg_hits" ] && ok "SG1 no part opens a cd group that runs on after a failed cd (cd \"\$X\" || exit 1)" \
  || no "SG1 cd group(s) that run on after a failed cd: $(printf '%s' "$sg_hits" | tr '\n' ' ')"

# SG3 an empty or missing cd target stops the group: none of its later commands runs. The runner's cd
# refuses an empty operand (bash 3.2's builtin accepts it), so it must be the function here.
sg_m="$SG_T/sg-empty-cd.marker"; sg_x=""
( cd "$sg_x" || exit 1; : > "$sg_m" ) 2>/dev/null; sg_rc1=$?
( cd "$SG_T/sg-no-such-dir" || exit 1; : >> "$sg_m" ) 2>/dev/null; sg_rc2=$?
if [ "$sg_rc1" -eq 1 ] && [ "$sg_rc2" -eq 1 ] && [ ! -e "$sg_m" ]; then
  ok "SG3 ( cd \"\$X\" || exit 1; … ) runs nothing when \$X is empty or not a directory"
else
  no "SG3 a cd group ran on after a failed cd: empty rc=$sg_rc1, missing-dir rc=$sg_rc2, marker $( [ -e "$sg_m" ] && echo written || echo absent)"
fi
sg_ty="$(type -t cd)"
[ "$sg_ty" = function ] && ok "SG3 cd is the runner's empty-operand-refusing function (type -t cd = function)" \
  || no "SG3 cd is '$sg_ty', not the runner's function: an empty fixture path would cd nowhere on bash 3.2"

# SG2 the incident replayed — a copy of each part run on its own (cwd = a scratch checkout holding
# sentinel run files) beside a stub runner that logs its arguments. Never the real checkout or parts.
SGX="$SG_T/checkout"; mkdir -p "$SGX/.supervisor/automate"; git init -q "$SGX"
printf 'sentinel run\n' > "$SGX/.supervisor/automate/sentinel-run.md"
printf '{"sentinel":true}\n' > "$SGX/.supervisor/automate/sentinel.next-step.json"
SGS="$SG_T/s/scripts"; SG_LOG="$SG_T/stub-runner.log"; mkdir -p "$SGS/test-automate-helpers.d"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\nexit 0\n' "$SG_LOG" > "$SGS/test-automate-helpers.sh"
for sg_p in $TAH_PARTS; do cp "$TAH_D/$sg_p.sh" "$SGS/test-automate-helpers.d/$sg_p.sh"; done
for sg_p in $TAH_PARTS; do
  sg_c="$SGS/test-automate-helpers.d/$sg_p.sh"
  # The exact guard (AC1) must be the copy's first command, within its first 15 lines, BEFORE it is
  # run: an unguarded part run standalone is the incident itself, so it is reported red, never run.
  sg_guard='if [ "${BASH_SOURCE[0]}" = "$0" ]; then exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test-automate-helpers.sh" '"$sg_p"'; fi'
  if [ "$(awk 'NR > 15 { exit } /^[ \t]*(#|$)/ { next } { print; exit }' "$sg_c")" != "$sg_guard" ]; then
    no "SG2 $sg_p.sh: the standalone guard naming $sg_p is not its first command within its first 15 lines — not run standalone"
    continue
  fi
  rm -f "$SG_LOG"
  ( cd "$SGX" || exit 1; bash "$sg_c" </dev/null >/dev/null 2>&1 ); sg_rc=$?
  if [ "$sg_rc" -eq 0 ] && [ "$(cat "$SG_LOG" 2>/dev/null)" = "$sg_p" ] \
     && [ "$(cat "$SGX/.supervisor/automate/sentinel-run.md" 2>/dev/null)" = "sentinel run" ] \
     && [ "$(cat "$SGX/.supervisor/automate/sentinel.next-step.json" 2>/dev/null)" = '{"sentinel":true}' ]; then
    ok "SG2 $sg_p.sh run standalone re-execs test-automate-helpers.sh $sg_p (exit 0); the scratch sentinels are kept"
  else
    no "SG2 $sg_p.sh run standalone: rc=$sg_rc runner args='$(tr '\n' '|' < "$SG_LOG" 2>/dev/null)' sentinels: $(ls "$SGX/.supervisor/automate" 2>/dev/null | tr '\n' ' ')"
  fi
done
rm -rf "$SG_T"
