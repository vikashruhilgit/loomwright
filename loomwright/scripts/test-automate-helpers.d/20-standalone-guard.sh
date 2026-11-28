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
# This part is scanned too, with only its marked control block blanked (line numbers kept); the block
# must be exactly the three printf lines, so nothing else can hide in it.
sg_self="$TAH_D/20-standalone-guard.sh"
sg_blk="$(awk '/^# >>> sg1-control /{ f = 1; next } /^# <<< sg1-control$/{ f = 0 } f' "$sg_self")"
sg_blk_ok=0
if [ "$(printf '%s\n' "$sg_blk" | wc -l | tr -d ' ')" = 3 ]; then
  case "$sg_blk" in "  printf '%s\n' '( cd \"\$P\" && git checkout -q -- README; rm -f stray.txt )' "*' > "$SGC"') sg_blk_ok=1 ;; esac
fi
[ "$sg_blk_ok" = 1 ] || no "SG1 the sg1-control block in 20-standalone-guard.sh is not exactly the three control printf lines"
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
