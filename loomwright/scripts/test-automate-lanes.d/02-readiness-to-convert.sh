declare -F tal_pgrep >/dev/null && [ -n "${T:-}" ] && [ -d "$T" ] || { echo "${BASH_SOURCE[0]##*/}: run via test-automate-lanes.sh, never standalone (its kills need the suite's \$T)" >&2; exit 2; }
# ---- U: merge-readiness report (AC9) -------------------------------------------------------------------
L3="$LR2/L3"
cat > "$L3/reqs/a.md" <<'EOF'
# a
## Touches
reqs/a.md
src/
## Validation (must pass before merge)
1. **Baseline:** full loop on base and branch.
2. **Running system:** run it for real and paste the output.
3. **A failure this must catch:** the mutation control, shown failing.
## Notes
EOF
printf '# Automate Run: %s\n\n## Current\n- item: reqs/a.md | status: awaiting_merge | pr: https://github.com/o/r/pull/5 | branch: f\n- pause_reason: ready_for_release\n\n## Progress\n- 2026-10-07T01:00:00Z children-settled: settled\n' "$PARENT2-L3" > "$L3/.supervisor/automate/$PARENT2-L3.md"
mkdir -p "$L3/.supervisor/jobs/in-progress"
printf '# brief for reqs/a.md\n- carried LOW: name the flag in the help text\n' > "$L3/.supervisor/jobs/in-progress/b.md"
cat > "$T/gh-ready" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "pr view") jq -n --arg b "$(printf 'Validation 1 baseline\n```\npassed: 5 failed: 0\n```\nValidation 2: will run later\nValidation 3 mutation\n```\nFAIL - leg x\n```\n')" '{body: $b, headRefOid: "abc123"}' ;;
  "pr diff") printf 'reqs/a.md\nsrc/x.sh\nchangelog.d/x.md\ndocs/other.md\n' ;;
  "pr checks") echo '[{"name":"ci","bucket":"pass"}]' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$T/gh-ready"
out="$(LOOMWRIGHT_GH_BIN="$T/gh-ready" run lane-readiness "$L3")"; rc=$?
RD="$L3/.supervisor/automate/$PARENT2-L3.merge-readiness.md"
check "U1 lane-readiness exits 0 and writes the report" "$rc:$([ -f "$RD" ] && echo yes)" "0:yes"
has "U2 a Validation step with pasted output ⇒ PASS" "$(cat "$RD")" "V1 Baseline: PASS"
has "U3 a running-system step with no pasted output ⇒ NOT-RUN, never PASS" "$(cat "$RD")" "V2 Running system: NOT-RUN — mentioned in the PR body without pasted output"
has "U4 scope fence lists the file outside the brief" "$(cat "$RD")" "  - docs/other.md"
has "U4b scope fence FAIL" "$(cat "$RD")" "- scope-fence: FAIL"
hasnt "U4c a bare-path Touches entry (the strict grammar) is declared: src/ covers src/x.sh" "$(cat "$RD")" "  - src/x.sh"
has "U5 carried note listed, NOT-RUN without accounting" "$(cat "$RD")" "carried-notes: NOT-RUN — 1 carried note(s)"
has "U6 gates PASS (checks green on head, decisions, children settled)" "$(cat "$RD")" "- gates: PASS"
has "U7 headline repro evidenced" "$(cat "$RD")" "V3 A failure this must catch: PASS"
has "U8 score line" "$(cat "$RD")" "- score: 2/5 | summary: ready (2/5: running-system NOT-RUN, carried-notes NOT-RUN, scope-fence FAIL)"
J="$(sj)"
check "U9 lane-status --json exposes the readiness score" "$(lf L3 '.readiness.score')" "2/5"
check "U9b lane-status --json carries the branch from ## Current" "$(lf L3 '.branch')" f
check "U10 parked ready lane state" "$(lf L3 .state)" ready_for_release
cat > "$T/helpers-merged.sh" <<'EOF'
#!/usr/bin/env bash
[ "$1" = reconcile-item ] && echo merged
EOF
chmod +x "$T/helpers-merged.sh"
J="$(LOOMWRIGHT_LANES_HELPERS="$T/helpers-merged.sh" sj)"
check "U11 parked lane reconciled against gh (reconcile-item)" "$(lf L3 '.state + "|" + .pr_state')" "merged|merged"
out="$(LOOMWRIGHT_GH_BIN="$T/absent-gh" run lane-readiness "$L3")"
has "U12 gh unreadable ⇒ every Validation step NOT-RUN" "$(cat "$RD")" "V1 Baseline: NOT-RUN — PR body unreadable"
out="$(LOOMWRIGHT_GH_BIN="$T/gh-ready" run lane-status "$RF2" --refresh-readiness --verbose)"
has "U13 lane-status --refresh-readiness re-writes it" "$(cat "$RD")" "V1 Baseline: PASS"
has "U13b --verbose plain view shows the score" "$out" "readiness: ready (2/5:"
# A numbered `Validation 1 (tests):` line, a blank, an intro paragraph ending in ':' and then the fence
# still reads PASS (origin/main did; review iteration 2 — the paragraph boundary never drops it).
cat > "$T/gh-ready-intro" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "pr view") jq -n --arg b "$(printf 'Validation 1 (tests):\n\nRan the suite:\n```\npassed: 5 failed: 0\n```\n')" '{body: $b, headRefOid: "abc123"}' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$T/gh-ready-intro"
LOOMWRIGHT_GH_BIN="$T/gh-ready-intro" run lane-readiness "$L3" >/dev/null
has "U13c numbered entry: \`Validation 1 (tests):\` + blank + intro paragraph + fence ⇒ PASS" "$(cat "$RD")" "V1 Baseline: PASS — pasted output in the PR body"
LOOMWRIGHT_GH_BIN="$T/gh-ready" run lane-readiness "$L3" >/dev/null
# U14: the children-settled line is clipped, never mid-token. Wave W2's L2 line was cut at 160
# chars inside its PR URL (`…/loomwright/pull/460` → `…/loomwrig`), and meta-sync's forge_slug scrub
# then refused the lane's metadata push (a non-allowlisted slug), so lane-remove refused the lane.
RF3="$L3/.supervisor/automate/$PARENT2-L3.md"; cp "$RF3" "$T/L3-runfile.bak"
printf -- '- 2026-10-10T14:44:12Z supervisor: worker done (ci-local PASS 161/161; provides 2/2; children settled); FINALIZE → PR https://github.com/vikashruhilgit/loomwright/pull/460 (base main verified); Phase 4.5 next\n' >> "$RF3"
out="$(LOOMWRIGHT_GH_BIN="$T/gh-ready" run lane-readiness "$L3")"
cs="$(grep 'children-settled:' "$RD")"
check "U14 a clipped line never ends inside a token (no partial URL)" "$(printf '%s' "$cs" | grep -cE 'github\.com/[^ ]*[^ /0-9]$|loomwrig($|[^h])')" "0"
has "U14b a clipped line is marked" "$cs" " …"
# U15: --refresh-readiness also re-writes a lane already closed out (done / awaiting_go), so a report
# written before a fix can be repaired by the sanctioned path instead of by hand.
sed -e 's/status: awaiting_merge/status: done/' -e 's/^- pause_reason: ready_for_release$/- pause_reason: awaiting_go/' "$T/L3-runfile.bak" > "$RF3"
rm -f "$RD"
out="$(LOOMWRIGHT_GH_BIN="$T/gh-ready" run lane-status "$RF2" --refresh-readiness)"
check "U15 --refresh-readiness re-writes a done lane's report" "$([ -f "$RD" ] && echo yes)" "yes"
cp "$T/L3-runfile.bak" "$RF3"
out="$(LOOMWRIGHT_GH_BIN="$T/gh-ready" run lane-readiness "$L3")"

# ---- V: --leaks, --resources, --tokens -----------------------------------------------------------------
# V1-V6 read a fixed process table (ps stub: $PS_TABLE's content, the real ps when unset), so the
# lanes launched above — whose stub `claude` exits after 60s — cannot change between snapshot and check.
printf '%s\n' '#!/usr/bin/env bash' '[ -n "${PS_TABLE:-}" ] && { cat "$PS_TABLE"; exit 0; }; exec ps "$@"' > "$T/ps-stub"
chmod +x "$T/ps-stub"; export LOOMWRIGHT_LANES_PS="$T/ps-stub" PS_TABLE="$T/ps.table"
echo "    1     0 /sbin/launchd" > "$PS_TABLE"
out="$(run lane-status "$RF2" --leaks)"; has "V1 no snapshot ⇒ unknown, exit 0" "$out" "leaks: unknown — no snapshot"
out="$(run lane-status "$RF2" --leaks --snapshot)"; has "V2 snapshot written" "$out" "leaks: snapshot written"
check "V3 unchanged ⇒ leaks: none" "$(run lane-status "$RF2" --leaks | head -1 | cut -c1-11)" "leaks: none"
cp "$P/.supervisor/config.json" "$T/config.bak"
HL="claude -p"   # the headless command the claude-p section matches (one vendor reference for V4-V26)
echo " 4321     1 bash $S _lane-run $LR2/L1 log died in -- env $HL --resume x" >> "$PS_TABLE"; echo '{"auto_review": false}' > "$P/.supervisor/config.json"
git -C "$P" worktree add -q "$T/wt-leak" -b leak-wt 2>/dev/null
out="$(run lane-status "$RF2" --leaks)"
check "V4 leaks found names each section" "$(printf '%s\n' "$out" | head -1)" "leaks: found — worktrees, claude-p, config-checksum"
has "V5 the leaked process is listed" "$out" "  + 4321 bash $S _lane-run $LR2/L1 log died in -- env $HL --resume x"
has "V6 unchanged sections say same" "$out" "- merge-watch: same"
cp "$T/config.bak" "$P/.supervisor/config.json"; unset PS_TABLE; git -C "$P" worktree remove --force "$T/wt-leak" 2>/dev/null
# V15-V20 (wave-close fix 2) the merge-watch section lists LIVE watchers from their *.merge-watch markers
# (`## merge-watch v2`), never a process-name match: W3's `leaks: found — merge-watch` was a grep whose
# argv named scripts/automate-merge-watch.sh. A pgrep wrapper hands the merge-watch pattern to the REAL
# pgrep (so the v1 mutation sees the decoy) and everything else to the stub. Decoys are background
# `sleep 30`s renamed with `exec -a` (bash 3.2); each names the suite dir, is tracked in BG_PIDS and killed.
cat > "$T/pgrep-mw" <<EOF
#!/usr/bin/env bash
case "\$*" in *automate-merge-watch*) exec pgrep "\$@" ;; esac
exec "$T/pgrep-stub" "\$@"
EOF
chmod +x "$T/pgrep-mw"
mw_spawn() { # <argv0> — sets MWPID: a background sleep whose ps command line reads "<argv0> 30"
  bash -c 'exec -a "$0" sleep 30' "$1" </dev/null >/dev/null 2>&1 &
  MWPID=$!; BG_PIDS="$BG_PIDS $MWPID"; local i=0
  until case "$(ps -ww -o command= -p "$MWPID" 2>/dev/null)" in "$1"*) true ;; *) false ;; esac || [ "$i" -ge 50 ]; do sleep 0.1; i=$((i + 1)); done
}
mw_kill() { local q; for q in "$@"; do kill -TERM "$q" 2>/dev/null; wait "$q" 2>/dev/null; done; }
mwl() { LOOMWRIGHT_LANES_PGREP="$T/pgrep-mw" bash "${MW_S:-$S}" lane-status "$1" --leaks "${@:2}" 2>&1; }
PARENTMW=automate-2026-10-11-090000; RFMW="$P/.supervisor/automate/$PARENTMW.md"
PARENTMV=automate-2026-10-11-091000; RFMV="$P/.supervisor/automate/$PARENTMV.md"
printf '# Automate Run: %s\n\n## Progress\n' "$PARENTMW" > "$RFMW"; printf '# Automate Run: %s\n\n## Progress\n' "$PARENTMV" > "$RFMV"
mwl "$RFMW" --snapshot >/dev/null
check "V15 the snapshot's merge-watch section carries the v2 format tag (and no v1 header)" \
  "$(grep -cxF '## merge-watch v2' "$P/.supervisor/automate/$PARENTMW.leaks-snapshot" | tr -d ' '):$(grep -cxF '## merge-watch' "$P/.supervisor/automate/$PARENTMW.leaks-snapshot" | tr -d ' ')" "1:0"
# the v1 mutation: the section body back to the process-name match; its own snapshot, before the decoy
awk '/# >>> merge-watch body$/ { print "  \"${LOOMWRIGHT_LANES_PGREP:-pgrep}\" -lf automate-merge-watch 2>/dev/null"; next } { print }' "$SB" > "$MUT/lanes-mw.sh"
if ! cmp -s "$SB" "$MUT/lanes-mw.sh" && bash -n "$MUT/lanes-mw.sh"; then MW_S="$MUT/lanes-mw.sh" mwl "$RFMV" --snapshot >/dev/null; MWMUT=1; else MWMUT=0; fi
mw_spawn "grep $T/scripts/automate-merge-watch.sh"; MWD="$MWPID"
out="$(mwl "$RFMW")"
check "V16 a process whose argv only NAMES automate-merge-watch.sh is not a watcher ⇒ merge-watch: same" \
  "$(printf '%s\n' "$out" | head -1 | cut -c1-11):$(printf '%s\n' "$out" | grep -cxF -- '- merge-watch: same' | tr -d ' ')" "leaks: none:1"
if [ "$MWMUT" = 1 ]; then
  has "V16b mutation (the v1 pgrep line restored) trips V16: the decoy reads as a leak" "$(MW_S="$MUT/lanes-mw.sh" mwl "$RFMV")" "- merge-watch: changed"
else bad "V16b mutation control not built"; fi
mw_kill "$MWD"
# V17 a real marker + a live process running automate-merge-watch for that marker's PR ⇒ reported
MWU1="https://github.com/o/r/pull/777"; MWU2="https://github.com/o/r/pull/778"
mw_spawn "bash $T/scripts/automate-merge-watch.sh $RFMW reqs/a.md $MWU1"; MW1="$MWPID"
printf 'pid\t%s\npr_url\t%s\nstarted\t2026-10-11T09:00:00Z\n' "$MW1" "$MWU1" > "$P/.supervisor/automate/mwtest.merge-watch"
out="$(mwl "$RFMW")"
check "V17 a live watcher in the primary ⇒ found — merge-watch, listed as <pid> <pr_url>" \
  "$(printf '%s\n' "$out" | head -1):$(printf '%s\n' "$out" | grep -cxF -- "  + $MW1 $MWU1" | tr -d ' ')" "leaks: found — merge-watch:1"
# V18 … and a live watcher of a lane in this run's table
mkdir -p "$T/mwlane/.supervisor/automate"
printf 'L1\t%s\treqs/a.md\t%s-L1\t-\t-\t-\tcreated\t-\t-\n' "$T/mwlane" "$PARENTMW" > "$P/.supervisor/automate/$PARENTMW.lanes"
mw_spawn "bash $T/scripts/automate-merge-watch.sh $T/mwlane/x.md reqs/a.md $MWU2"; MW2="$MWPID"
printf 'pid\t%s\npr_url\t%s\n' "$MW2" "$MWU2" > "$T/mwlane/.supervisor/automate/$PARENTMW-L1.merge-watch"
out="$(mwl "$RFMW")"
check "V18 a live watcher in a lane of the table is listed too (sorted, one line each)" \
  "$(printf '%s\n' "$out" | grep -cxF -- "  + $MW1 $MWU1" | tr -d ' '):$(printf '%s\n' "$out" | grep -cxF -- "  + $MW2 $MWU2" | tr -d ' ')" "1:1"
mw_kill "$MW1" "$MW2"
out="$(mwl "$RFMW")"
check "V19 markers left behind by watchers that exited are not live ⇒ merge-watch: same" \
  "$(printf '%s\n' "$out" | grep -cxF -- '- merge-watch: same' | tr -d ' ')" 1
rm -f "$P/.supervisor/automate/mwtest.merge-watch" "$P/.supervisor/automate/$PARENTMW.lanes"; rm -rf "$T/mwlane"
# V20 a v1 snapshot (taken by the pre-fix code: `## merge-watch` + pgrep lines) is NOT compared — never a false found
SFMW="$P/.supervisor/automate/$PARENTMW.leaks-snapshot"
awk '$0 == "## merge-watch v2" { print "## merge-watch"; print "4242 grep scripts/automate-merge-watch.sh"; next } { print }' "$SFMW" > "$SFMW.t" && mv "$SFMW.t" "$SFMW"
out="$(mwl "$RFMW")"
check "V20 a v1 snapshot section ⇒ leaks: none, the first line naming the uncompared section" \
  "$(printf '%s\n' "$out" | head -1)" "leaks: none (vs snapshot $SFMW; merge-watch not compared — pre-v2 snapshot)"
has "V20b … and the body says why" "$out" "- merge-watch: not compared — the wave-start snapshot predates the marker-based watcher list (v1)"
rm -f "$MUT/lanes-mw.sh"
# V21-V26 the claude-p section lists only THIS run's processes (`## claude-p v2`), read from the real ps:
# closing wave 1 of automate-2026-10-15-163325 read `leaks: found — claude-p` from another repo's healthy
# wave (its `_lane-run <other>-lanes/<run>/L1|L2` wrappers and their headless children). Decoys are
# `sleep 30`s renamed with `exec -a`; a wrapper decoy forks its headless child (cwd /, so only the
# parent pid ties it) before it execs, so the child's ppid is the wrapper's pid. All named under $T.
cp_spawn() { # <cwd> <argv0> — sets CPPID: a lone decoy running in <cwd>
  ( cd "$1" && exec -a "$2" sleep 30 ) </dev/null >/dev/null 2>&1 &
  CPPID=$!; BG_PIDS="$BG_PIDS $CPPID"; cp_seen "$CPPID" "$2"
}
cp_pair() { # <lane_dir> — sets CPW (a `_lane-run <lane_dir>` wrapper decoy) and CPC (its headless child)
  bash -c '( cd / && exec -a "$3 --plugin-dir $2" sleep 30 ) & exec -a "bash $2/scripts/automate-lanes.sh _lane-run $1 $1.log $1.died /dev/null -- env $3 --plugin-dir $2" sleep 30' \
    _ "$1" "$T" "$HL" </dev/null >/dev/null 2>&1 &
  CPW=$!; BG_PIDS="$BG_PIDS $CPW"; cp_seen "$CPW" "bash $T/scripts/automate-lanes.sh _lane-run $1 "
  local i=0; CPC=""
  until [ -n "$CPC" ] || [ "$i" -ge 50 ]; do CPC="$(pgrep -P "$CPW" 2>/dev/null | head -1)"; [ -n "$CPC" ] || sleep 0.1; i=$((i + 1)); done
  BG_PIDS="$BG_PIDS $CPC"; cp_seen "$CPC" "$HL --plugin-dir $T"
}
cp_seen() { local i=0; until case "$(ps -ww -o command= -p "$1" 2>/dev/null)" in "$2"*) true ;; *) false ;; esac || [ "$i" -ge 50 ]; do sleep 0.1; i=$((i + 1)); done; }
cpl() { bash "${CP_S:-$S}" lane-status "$1" --leaks "${@:2}" 2>&1; }
PARENTCP=automate-2026-10-16-090000; RFCP="$P/.supervisor/automate/$PARENTCP.md"; SFCP="$P/.supervisor/automate/$PARENTCP.leaks-snapshot"
CPL1="$T/work/primary-lanes/$PARENTCP/L1"; CPF="$T/work/studio-lanes/automate-2026-10-15-153327"
mkdir -p "$CPL1" "$CPF/L1" "$CPF/L2"
printf '# Automate Run: %s\n\n## Progress\n' "$PARENTCP" > "$RFCP"
cpl "$RFCP" --snapshot >/dev/null
check "V21 the snapshot's claude-p section carries the v2 format tag (and no v1 header)" \
  "$(grep -cxF '## claude-p v2' "$SFCP" | tr -d ' '):$(grep -cxF '## claude-p' "$SFCP" | tr -d ' ')" "1:0"
# the v1 mutation: the section body back to the machine-wide match; its own run + snapshot, before the decoys
PARENTCV=automate-2026-10-16-091000; RFCV="$P/.supervisor/automate/$PARENTCV.md"
printf '# Automate Run: %s\n\n## Progress\n' "$PARENTCV" > "$RFCV"
awk -v hl="$HL" '/# >>> claude-p body$/ { print "  pgrep -lf '"'"'" hl "'"'"' 2>/dev/null"; next } { print }' "$SB" > "$MUT/lanes-cp.sh"   # raw-pgrep-ok: the mutant only lists (-l)
if ! cmp -s "$SB" "$MUT/lanes-cp.sh" && bash -n "$MUT/lanes-cp.sh"; then CP_S="$MUT/lanes-cp.sh" cpl "$RFCV" --snapshot >/dev/null; CPMUT=1; else CPMUT=0; fi
# V22 another repo's healthy wave: two wrappers + their children, and a headless session whose cwd is its lane
cp_pair "$CPF/L1"; FW1="$CPW"; FC1="$CPC"; cp_pair "$CPF/L2"; FW2="$CPW"; FC2="$CPC"
cp_spawn "$CPF/L1" "$HL --resume foreign"; FO="$CPPID"
out="$(cpl "$RFCP")"
check "V22 a foreign run's lane processes do not count ⇒ leaks: none, claude-p: same" \
  "$(printf '%s\n' "$out" | head -1 | cut -c1-11):$(printf '%s\n' "$out" | grep -cxF -- '- claude-p: same' | tr -d ' ')" "leaks: none:1"
if [ "$CPMUT" = 1 ]; then
  has "V22b mutation (the v1 machine-wide pgrep restored) trips V22: the foreign wave reads as a leak" "$(CP_S="$MUT/lanes-cp.sh" cpl "$RFCV")" "- claude-p: changed"
else bad "V22b mutation control not built"; fi
# V23 this run's leftover lane: its wrapper and (by parent pid alone — cwd /) its headless child
cp_pair "$CPL1"; OW="$CPW"; OC="$CPC"
out="$(cpl "$RFCP")"
check "V23 this run's leftover lane process still reads found — wrapper and child listed, foreign ones not" \
  "$(printf '%s\n' "$out" | head -1):$(printf '%s\n' "$out" | grep -c "^  + $OW bash $T/scripts/automate-lanes.sh _lane-run $CPL1 " | tr -d ' '):$(printf '%s\n' "$out" | grep -cxF -- "  + $OC $HL --plugin-dir $T 30" | tr -d ' '):$(printf '%s\n' "$out" | grep -cE "^  \+ ($FW1|$FC1|$FW2|$FC2|$FO) " | tr -d ' ')" \
  "leaks: found — claude-p:1:1:0"
mw_kill "$OW" "$OC"
# V24 a headless session of this run whose wrapper is gone, tied by its working directory (a lane of the table)
printf 'L1\t%s\treqs/a.md\t%s-L1\t-\t-\t-\tcreated\t-\t-\n' "$CPL1" "$PARENTCP" > "$P/.supervisor/automate/$PARENTCP.lanes"
cp_spawn "$CPL1" "$HL --resume orphan"; OO="$CPPID"
out="$(cpl "$RFCP")"
check "V24 an orphaned headless session in this run's lane (cwd) reads found, listed" \
  "$(printf '%s\n' "$out" | head -1):$(printf '%s\n' "$out" | grep -cxF -- "  + $OO $HL --resume orphan 30" | tr -d ' ')" "leaks: found — claude-p:1"
# V25 an unreadable process table reads unknown, never found (fail SAFE, exit 0)
out="$(LOOMWRIGHT_LANES_PS=false cpl "$RFCP")"; rc=$?
check "V25 ps unreadable ⇒ leaks: unknown naming the section, exit 0" \
  "$rc:$(printf '%s\n' "$out" | head -1)" "0:leaks: unknown — claude-p unreadable (vs snapshot $SFCP)"
has "V25b … and the body says why" "$out" "- claude-p: unknown — the process table is unreadable (ps)"
# V25c a headless session to attribute (V22's foreign orphan still runs) with no working-directory reader
out="$(LOOMWRIGHT_LANES_LSOF="$T/no-lsof" LOOMWRIGHT_LANES_PROC="$T/no-proc" cpl "$RFCP")"; rc=$?
check "V25c no cwd reader (lsof, /proc) ⇒ leaks: unknown, exit 0, the body naming why" \
  "$rc:$(printf '%s\n' "$out" | head -1):$(printf '%s\n' "$out" | grep -cxF -- "- claude-p: unknown — no reader for a process's working directory (lsof, /proc)" | tr -d ' ')" \
  "0:leaks: unknown — claude-p unreadable (vs snapshot $SFCP):1"
# V25e no lsof ⇒ the /proc fallback attributes by `<proc>/<pid>/cwd` (a fake tree: V24's orphan in this
# run's lane, V22's foreign orphan in its own lane) — the minimal-container path, not only lsof's
mkdir -p "$T/fakeproc/self" "$T/fakeproc/$OO" "$T/fakeproc/$FO"
ln -s "$CPL1" "$T/fakeproc/$OO/cwd"; ln -s "$CPF/L1" "$T/fakeproc/$FO/cwd"
out="$(LOOMWRIGHT_LANES_LSOF="$T/no-lsof" LOOMWRIGHT_LANES_PROC="$T/fakeproc" cpl "$RFCP")"
check "V25e lsof absent, /proc present ⇒ this run's orphan found by its /proc cwd, the foreign one not" \
  "$(printf '%s\n' "$out" | head -1):$(printf '%s\n' "$out" | grep -cxF -- "  + $OO $HL --resume orphan 30" | tr -d ' '):$(printf '%s\n' "$out" | grep -c "^  + $FO " | tr -d ' ')" \
  "leaks: found — claude-p:1:0"
rm -rf "$T/fakeproc"
# V25d the unknown sniff is claude-p's alone: a lanes-dir entry NAMED like the fail-SAFE line is a leak
: > "$T/work/primary-lanes/unknown — decoy"
out="$(cpl "$RFCP")"
check "V25d a <primary>-lanes entry named 'unknown — …' reads found — lanes-dir, never unknown" \
  "$(printf '%s\n' "$out" | head -1 | grep -c '^leaks: found — lanes-dir' | tr -d ' '):$(printf '%s\n' "$out" | grep -cxF -- '  + unknown — decoy' | tr -d ' ')" "1:1"
rm -f "$T/work/primary-lanes/unknown — decoy"
# V26 a snapshot written before v2 (`## claude-p` + machine-wide pgrep lines) is NOT compared — the
# orphan of V24 still runs, and still the first line is never a false found
awk -v hl="$HL" '$0 == "## claude-p v2" { print "## claude-p"; print "4242 " hl " --resume someone-else"; skip = 1; next } /^## / { skip = 0 } !skip' "$SFCP" > "$SFCP.t" && mv "$SFCP.t" "$SFCP"
out="$(cpl "$RFCP")"
check "V26 a v1 claude-p snapshot section ⇒ leaks: none, the first line naming the uncompared section" \
  "$(printf '%s\n' "$out" | head -1)" "leaks: none (vs snapshot $SFCP; claude-p not compared — pre-v2 snapshot)"
has "V26b … and the body says why" "$out" "- claude-p: not compared — the wave-start snapshot predates the run-scoped process list (v1 matched every such process on the machine)"
mw_kill "$OO" "$FW1" "$FC1" "$FW2" "$FC2" "$FO"
# V27 the tie test reads a wrapper's argv tail from its start: a lane path with a space is never cut at it
check "V27 a wrapper argv tail whose lane path holds a space ties to its run (root and table forms), not to a sibling run" \
  "$( . "$S"; t() { _lanes_path_tied "$@" && echo y || echo n; }
     printf '%s' "$(t "/w/my repo-lanes/r1/L1 /w/my repo-lanes/r1/L1.stream.log x" "/w/my repo-lanes/r1" "")"
     printf '%s' "$(t "/w/my repo-lanes/r1/L1 log x" "" "/w/my repo-lanes/r1/L1")"
     printf '%s' "$(t "/w/my repo-lanes/r10/L1 /w/my repo-lanes/r1/L1.stream.log x" "/w/my repo-lanes/r1" "/w/my repo-lanes/r1/L1")" )" "yyn"
rm -f "$MUT/lanes-cp.sh" "$P/.supervisor/automate/$PARENTCP.lanes" "$P/.supervisor/automate/$PARENTCP".* "$P/.supervisor/automate/$PARENTCV".*
rm -rf "$T/work/primary-lanes/$PARENTCP" "$T/work/studio-lanes"
out="$(run lane-status "$RF2" --resources)"; has "V7 no fleet.log ⇒ resources unknown" "$out" "resources: unknown"
printf '2026-10-07T10:00:00Z load1=5 load=ok L1_rss=100M L2_rss=300M nonlane_load=10%%\n2026-10-07T10:00:10Z load1=9 load=busy L1_rss=200M L2_rss=150M nonlane_load=20%%\n' > "$P/.supervisor/automate/$PARENT2.fleet.log"
out="$(run lane-status "$RF2" --resources)"
has "V8 latest line per lane" "$out" "L1: L1_rss=200M"
has "V9 wave peak" "$out" "peak: load1=9 L1_rss=200M L2_rss=300M nonlane_load=20%"
has "V10 machine part of the latest line" "$out" "machine: load1=9 load=busy nonlane_load=20%"
cat > "$T/ledger.sh" <<'EOF'
#!/usr/bin/env bash
# argument-aware like the real reader: every --root adds one root's sums into the one line
n=0; for a in "$@"; do [ "$a" = "--root" ] && n=$((n + 1)); done; [ "$n" -gt 0 ] || n=1
echo "INPUT=$((1 * n)) OUTPUT=$((2 * n)) CACHE_READ=0 CACHE_CREATE=0 TOTAL=$((3 * n)) EVENTS=$n"
EOF
out="$(LOOMWRIGHT_LANES_TOKEN_LEDGER="$T/ledger.sh" run lane-status "$RF2" --tokens)"
has "V11 per-lane tokens" "$out" "L1 INPUT=1 OUTPUT=2"
has "V12 parent tokens" "$out" "parent INPUT=1"
check "V13 total sums parent + lanes" "$(printf '%s\n' "$out" | sed -n 's/.* TOTAL=\([0-9]*\).*/\1/p' | tail -1)" 24
out="$(LOOMWRIGHT_LANES_TOKEN_LEDGER="$T/absent.sh" run lane-status "$RF2" --tokens)"; rc=$?
check "V14 ledger absent ⇒ unknown, exit 0" "$rc:$out" "0:tokens: unknown — read-token-ledger.sh absent"
for p in $(tal_pgrep "$LR2" "_lane-run "); do kill -TERM "$p" 2>/dev/null; done

# ---- W: drain round 1 hardening -------------------------------------------------------------------------
# W1 (D8) the total is ONE read-token-ledger.sh call over every root: a parent that ran no session of its
# own (its root alone is unreadable) with readable lanes is NOT LEDGER_UNREADABLE. The stub models the
# real reader: roots add up, LEDGER_UNREADABLE=1 only when no root reads.
export LEDGER_CALLS="$T/ledger.calls"; : > "$LEDGER_CALLS"
cat > "$T/ledger-arg.sh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$LEDGER_CALLS"
n=0; prev=""
for a in "$@"; do { [ "$prev" = "--root" ] && [ "$a" != "$LEDGER_EMPTY_ROOT" ]; } && n=$((n + 1)); prev="$a"; done
if [ "$n" = 0 ]; then echo "INPUT=0 OUTPUT=0 CACHE_READ=0 CACHE_CREATE=0 TOTAL=0 EVENTS=0 LEDGER_UNREADABLE=1"
else echo "INPUT=$n OUTPUT=$((2 * n)) CACHE_READ=0 CACHE_CREATE=0 TOTAL=$((3 * n)) EVENTS=$n"; fi
EOF
tokens_arg() { LOOMWRIGHT_LANES_TOKEN_LEDGER="$T/ledger-arg.sh" LEDGER_EMPTY_ROOT="$P" bash "${1:-$S}" lane-status "$RF2" --tokens 2>&1; }
out="$(tokens_arg)"; TOT="$(printf '%s\n' "$out" | grep '^total (parent + lanes):')"
has "W1 the parent alone is unreadable (no session of its own)" "$(printf '%s\n' "$out" | grep '^parent ')" "LEDGER_UNREADABLE=1"
hasnt "W1b readable lanes ⇒ the total is not LEDGER_UNREADABLE" "$TOT" "LEDGER_UNREADABLE"
has "W1c the total adds the 7 readable lane roots" "$TOT" "TOTAL=21"
check "W1d the total is one call: --run-id <parent> with the primary + 7 lane roots" \
  "$(grep "^--run-id $PARENT2 " "$LEDGER_CALLS" | awk '{ n = 0; for (i = 1; i <= NF; i++) if ($i == "--root") n++; if (n > 1) print n }')" 8
cat > "$T/mut-total.line" <<'EOF'
  to="$(for r in "${roots[@]}"; do [ "$r" = --root ] || bash "$rtl" --run-id "$3" --root "$r" 2>/dev/null | head -1; done | awk '{ for (i = 1; i <= NF; i++) { k = $i; v = $i; sub(/=.*/, "", k); sub(/^[^=]*=/, "", v); if (k == "LEDGER_UNREADABLE") u = 1; else if (v ~ /^[0-9]+$/) { if (!(k in s)) o[++n] = k; s[k] += v } } } END { for (j = 1; j <= n; j++) printf "%s%s=%s", (j > 1 ? " " : ""), o[j], s[o[j]]; if (u) printf " LEDGER_UNREADABLE=1"; print "" }')"
EOF
awk -v f="$T/mut-total.line" '/# TOTAL-CALL$/ { while ((getline l < f) > 0) print l; next } { print }' "$SB" > "$MUT/automate-lanes.sh"
if ! cmp -s "$SB" "$MUT/automate-lanes.sh" && bash -n "$MUT/automate-lanes.sh"; then
  has "W1e mutation (independent per-root calls, ORed) trips W1b" "$(tokens_arg "$MUT/automate-lanes.sh" | grep '^total')" "LEDGER_UNREADABLE=1"
else bad "W1e mutation control not built"; fi

# W2 a value-taking flag given last exits promptly non-zero (never a `shift 2` loop), per subcommand family
bounded() { # bounded <secs> <args...> — run the script; 124 when still alive after <secs> (then killed)
  local s="$1" p i=0; shift
  bash "$S" "$@" > "$T/bounded.out" 2>&1 < /dev/null & p=$!
  while kill -0 "$p" 2>/dev/null && [ "$i" -lt $((s * 10)) ]; do sleep 0.1; i=$((i + 1)); done
  if kill -0 "$p" 2>/dev/null; then kill -KILL "$p" 2>/dev/null; wait "$p" 2>/dev/null; return 124; fi
  wait "$p"
}
prompt_nz() { case "$1" in 0) echo "rc=0" ;; 124) echo "still running after 5s" ;; *) echo prompt-nonzero ;; esac; }
for spec in "lane-create|$RF reqs/a.md 7 --parallel" "lane-create|$RF reqs/a.md 7 --max-tokens" \
            "lane-launch|$LR/L6 --owner-command" "lane-launch|$LR/L6 --host-denied" "lane-launch|$LR/L6 --resume-run" \
            "lane-answer|$LR/L6 toolu_x --owner-command" "lane-answer|$LR/L6 toolu_x --via"; do
  sub="${spec%%|*}"; args="${spec#*|}"; flag="${args##* }"
  # shellcheck disable=SC2086
  bounded 5 "$sub" $args; rc=$?
  check "W2 $sub trailing $flag exits promptly non-zero" "$(prompt_nz "$rc")" prompt-nonzero
  has "W2b $sub trailing $flag names the missing value" "$(cat "$T/bounded.out")" "$flag needs a value"
done
check "W2c lane-create left no lane behind" "$([ -e "$LR/L7" ] && echo present || echo absent)" absent
bounded 5 init-check --parallel; rc=$?
check "W2d init-check trailing --parallel keeps its refuse contract (exit 1, promptly)" "$rc:$(cat "$T/bounded.out")" "1:refuse: parallel_out_of_range"

# W3 lane-remove: an unreadable unpushed-commit count refuses (fail CLOSED), never reads as 0
run lane-create "$RF" reqs/a.md 7 >/dev/null; L7="$LR/L7"
REAL_GIT="$(command -v git)"; mkdir -p "$T/gitshim"
cat > "$T/gitshim/git" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
  if [ "\$a" = rev-list ]; then [ "\${GITSHIM_MODE:-fail}" = empty ] && exit 0; echo "fatal: shim" >&2; exit 128; fi
done
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$T/gitshim/git"
out="$(PATH="$T/gitshim:$PATH" run lane-remove "$L7")"; rc=$?
check "W3 failed rev-list count ⇒ refused" "$rc:$([ -d "$L7" ] && echo kept || echo removed)" "1:kept"
has "W3b names the unreadable count" "$out" "branch main: unpushed-commit count unreadable"
out="$(GITSHIM_MODE=empty PATH="$T/gitshim:$PATH" run lane-remove "$L7")"; rc=$?
check "W3c empty count ⇒ refused" "$rc:$([ -d "$L7" ] && echo kept || echo removed)" "1:kept"
grep -v '# UNPUSHED-UNREADABLE$' "$SB" > "$MUT/automate-lanes.sh"
if ! cmp -s "$SB" "$MUT/automate-lanes.sh" && bash -n "$MUT/automate-lanes.sh"; then
  PATH="$T/gitshim:$PATH" bash "$MUT/automate-lanes.sh" lane-remove "$L7" >/dev/null 2>&1
  check "W3d mutation (count guard deleted) fails OPEN — the lane is removed" "$([ -d "$L7" ] && echo kept || echo removed)" removed
else bad "W3d mutation control not built"; fi

# W4 lock holder records: a dead holder is reclaimed, a live one waited on (bounded) and never stolen,
# a foreign lock is never unlocked, a holder-less lock is reclaimed after its grace
lst() { env LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed 's/^ //; s/ $//'; }
sleep 0 & DPID=$!; wait "$DPID" 2>/dev/null
mkdir -p "$TABLE.lock"; printf '%s Mon Jan  1 00:00:00 2001\n' "$DPID" > "$TABLE.lock/holder"
bounded 10 lane-launch "$LR/L6" --host-denied 'w4 dead holder'; rc=$?
check "W4 dead holder's lock reclaimed promptly (the table write lands)" "$rc:$(tcol L6 10)" "3:w4 dead holder"
check "W4b no lock left behind" "$([ -e "$TABLE.lock" ] && echo present || echo absent)" absent
sleep 300 & HPID=$!; BG_PIDS="$BG_PIDS $HPID"
mkdir -p "$TABLE.lock"; printf '%s %s\n' "$HPID" "$(lst "$HPID")" > "$TABLE.lock/holder"
LOOMWRIGHT_LANES_LOCK_WAIT_S=2 bounded 10 lane-launch "$LR/L6" --host-denied 'w4 live holder'; rc=$?
check "W4c live holder: the waiter gives up at its bound (not still running)" "$([ "$rc" != 124 ] && echo bounded || echo hung)" bounded
check "W4d live holder's lock is never stolen" "$(tcol L6 10):$(sed -n 1p "$TABLE.lock/holder" | cut -d' ' -f1)" "w4 dead holder:$HPID"
has "W4e the waiter says the lock is busy" "$(cat "$T/bounded.out")" "lock busy"
( . "$S"; _lt_unlock "$TABLE" )
check "W4f _lt_unlock leaves another process's lock alone" "$(sed -n 1p "$TABLE.lock/holder" 2>/dev/null | cut -d' ' -f1)" "$HPID"
bash "$S" lane-launch "$LR/L6" --host-denied 'w4 after holder died' > /dev/null 2>&1 & WPID=$!
sleep 1
check "W4g a live holder is waited on" "$(kill -0 "$WPID" 2>/dev/null && echo waiting || echo done):$(tcol L6 10)" "waiting:w4 dead holder"
kill "$HPID" 2>/dev/null; wait "$HPID" 2>/dev/null
i=0; while kill -0 "$WPID" 2>/dev/null && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
check "W4h once the holder dies the waiter reclaims and writes" "$(kill -0 "$WPID" 2>/dev/null && echo hung || echo done):$(tcol L6 10)" "done:w4 after holder died"
mkdir -p "$TABLE.lock"
bounded 15 lane-launch "$LR/L6" --host-denied 'w4 holder-less'; rc=$?
check "W4i a holder-less lock (creator died before recording) is reclaimed after its grace" "$rc:$(tcol L6 10)" "3:w4 holder-less"
rm -rf "$TABLE.lock" "$TABLE.lock.reclaim"

# W5 two overlapping launches of one lane spawn exactly once (launch lock spans check → pid write)
run lane-create "$RF" reqs/b.md 8 >/dev/null; L8="$LR/L8"
n5="$(claude_calls)"
STUB_MODE=sleep LOOMWRIGHT_LANE_RECHECK_S=0 bash "$S" lane-launch "$L8" --owner-command "$OWN" > "$T/w5a.out" 2>&1 & A5=$!
STUB_MODE=sleep LOOMWRIGHT_LANE_RECHECK_S=0 bash "$S" lane-launch "$L8" --owner-command "$OWN" > "$T/w5b.out" 2>&1 & B5=$!
wait "$A5"; ra=$?; wait "$B5"; rb=$?
check "W5 two concurrent launches ⇒ exactly one spawn" "$(( $(claude_calls) - n5 ))" 1
check "W5b one launched, one refused" "$(printf '%s\n%s\n' "$ra" "$rb" | env LC_ALL=C sort | tr '\n' ' ')" "0 1 "
has "W5c the second sees the lane running" "$(cat "$T/w5a.out" "$T/w5b.out")" "already running"
check "W5d no launch lock left behind" "$(ls -d "$TABLE".L8.launch.lock 2>/dev/null | wc -l | tr -d ' ')" 0
for p in $(tal_pgrep "$L8" "_lane-run "); do kill -TERM "$p" 2>/dev/null; done; wait_gone "$L8"

# W6 multiSelect labels that contain commas
run lane-create "$RF" reqs/b.md 9 >/dev/null; L9="$LR/L9"
Q7='[{"question":"Which shades?","header":"Shades","multiSelect":true,"options":[{"label":"Red, dark","description":"r"},{"label":"Blue","description":"b"},{"label":"Green","description":"g"}]},{"question":"Which parts?","header":"Parts","multiSelect":true,"options":[{"label":"A","description":"a"},{"label":"B","description":"b"},{"label":"A, B","description":"ab"},{"label":"C","description":"c"}]}]'
jq -n -c --argjson q "$Q7" '{id: "toolu_w6", asked_at: "2026-10-07T00:00:00Z", questions: $q}' > "$L9/.supervisor/inbox/questions/toolu_w6.json"
jq -n -c --argjson q "$Q7" '{type: "result", subtype: "success", stop_reason: "tool_deferred", session_id: "sess-w6", deferred_tool_use: {id: "toolu_w6", name: "AskUserQuestion", input: {questions: $q}}}' >> "$LR/L9.stream.log"
ans6() { printf '%s' "$1" | LOOMWRIGHT_LANE_RECHECK_S=0 bash "$S" lane-answer "$L9" toolu_w6 --owner-command "$OWN" 2>&1; }
out="$(ans6 '{"answers":{"0":"Red, dark","1":"A, B,C"}}')"; rc=$?
check "W6 an answer that splits into known labels two ways is refused" "$rc" 1
has "W6b the refusal says ambiguous" "$out" '"A, B,C" is ambiguous'
out="$(ans6 '{"answers":{"0":"Red, dark, Purple","1":"C"}}')"; rc=$?
check "W6c one unknown label still refuses the whole answer" "$rc:$(printf '%s' "$out" | grep -c '"Red, dark, Purple" is not one of its options' | tr -d ' ')" "1:1"
out="$(ans6 '{"answers":{"0":"Red","1":"C"}}')"; check "W6d half of a comma label is not a label" "$?" 1
check "W6e nothing recorded by the refusals" "$([ -e "$L9/.supervisor/inbox/answers/toolu_w6.json" ] && echo written || echo none)" none
out="$(ans6 '{"answers":{"0":"Red, dark, Blue","1":"A, B"}}')"; rc=$?
check "W6f a comma label plus another label, and a whole-answer label, are accepted" "$rc" 0
check "W6g recorded labels" "$(jq -c '[.answers["Which shades?"], .answers["Which parts?"]]' "$L9/.supervisor/inbox/answers/toolu_w6.json" 2>/dev/null)" '["Red, dark,Blue","A, B"]'
wait_gone "$L9"

# W7 lane-remove --stop runs every non-liveness refusal BEFORE stopping anything: a live lane with a
# dirty tree is refused for the dirty tree and its process is left running (never stopped-but-refused)
run lane-create "$RF" reqs/a.md 10 >/dev/null; L10="$LR/L10"
STUB_MODE=sleep LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L10" --owner-command "$OWN" >/dev/null
L10P="$(tcol L10 5)"; L10S="$(tcol L10 6)"
echo dirty >> "$L10/reqs/a.md"
out="$(run lane-remove "$L10" --stop)"; rc=$?
check "W7 --stop on a dirty live lane ⇒ refused, lane kept" "$rc:$([ -d "$L10" ] && echo kept || echo removed)" "1:kept"
has "W7b refused with the dirty-tree reason" "$out" "refused — L10 — dirty working tree"
hasnt "W7c nothing was stopped" "$out" "lane-remove: stopped"
( . "$S"; lanes_proc_alive "$L10P" "$L10S" "$L10" ); check "W7d the lane process is still alive" "$?" 0
grep -v '# REFUSE-BEFORE-STOP$' "$SB" > "$MUT/automate-lanes.sh"
if ! cmp -s "$SB" "$MUT/automate-lanes.sh" && bash -n "$MUT/automate-lanes.sh"; then
  out="$(bash "$MUT/automate-lanes.sh" lane-remove "$L10" --stop 2>&1)"
  has "W7e mutation (pre-stop refusal pass deleted) stops the process first" "$out" "lane-remove: stopped"
  has "W7f … and is then refused anyway (the old stopped-but-refused order)" "$out" "dirty working tree"
  check "W7g … leaving the lane process dead" "$(kill -0 "$L10P" 2>/dev/null && echo alive || echo dead)" dead
else bad "W7e mutation control not built"; fi
wait_gone "$L10"
git -C "$L10" checkout -q -- reqs/a.md
out="$(run lane-remove "$L10" --stop)"; check "W7h once clean, the stopped lane is removed" "$?:$([ -d "$L10" ] && echo kept || echo removed)" "0:removed"

# ---- X: relay hook from a linked worktree of the lane (owner fix-now FN1) -----------------------------
# A worker's worktree sits OUTSIDE the lane dir (../{repo}-{task_id}-{slug}) and holds no lane.json; the
# hook resolves the lane through the git common dir, so the question still lands in the LANE's inbox.
run lane-create "$RF" reqs/a.md 11 --parallel 2 >/dev/null; L1="$LR/L11"
xhook() { hook_in PreToolUse "$1" "$2" | bash "${3:-$S}" relay-hook; }   # <cwd> <tool_use_id> [<script>]
hso() { jq -r -c ".hookSpecificOutput$1" <<<"$2" 2>/dev/null; }   # <field path> <hook output> — a field of the hook response
xdec() { hso .permissionDecision "$1"; }
WT="$LR/L1-42-slug"
git -C "$L1" worktree add -q -b feature/42-slug "$WT" 2>/dev/null
out="$(xhook "$WT" toolu_x1)"
check "X1 question asked from a linked worktree of the lane ⇒ defer" "$(xdec "$out")" defer
check "X2 … recorded in the LANE's inbox" "$(jq -r .id "$L1/.supervisor/inbox/questions/toolu_x1.json" 2>/dev/null)" toolu_x1
check "X3 … nothing written under the worktree" "$([ -e "$WT/.supervisor" ] && echo written || echo none)" none
out="$(xhook "$WT/reqs" toolu_x2)"
check "X4 a subdirectory of the worktree resolves to the lane too" \
  "$(xdec "$out"):$([ -s "$L1/.supervisor/inbox/questions/toolu_x2.json" ] && echo lane || echo missing)" "defer:lane"
# git < 2.31 has no --path-format: the shim echoes the flag back (as an older rev-parse does) ahead of
# the plain answer, so the hook must fall back to the toplevel-relative resolution
REAL_GIT="$(command -v git)"; mkdir -p "$T/oldgit"
cat > "$T/oldgit/git" <<EOF
#!/usr/bin/env bash
a=(); f=0
for x in "\$@"; do if [ "\$x" = --path-format=absolute ]; then f=1; else a+=("\$x"); fi; done
[ "\$f" = 1 ] && echo --path-format=absolute
exec "$REAL_GIT" "\${a[@]}"
EOF
chmod +x "$T/oldgit/git"
out="$(PATH="$T/oldgit:$PATH" xhook "$WT" toolu_x3)"
check "X5 older git (no --path-format): worktree question still reaches the lane inbox" \
  "$(xdec "$out"):$([ -s "$L1/.supervisor/inbox/questions/toolu_x3.json" ] && echo lane || echo missing)" "defer:lane"
out="$(PATH="$T/oldgit:$PATH" xhook "$L1/reqs" toolu_x4)"
check "X6 older git: a question from a lane subdirectory still reaches the lane inbox" \
  "$(xdec "$out"):$([ -s "$L1/.supervisor/inbox/questions/toolu_x4.json" ] && echo lane || echo missing)" "defer:lane"
PWT="$T/work/primary-42-slug"
git -C "$P" worktree add -q -b feature/p42 "$PWT" 2>/dev/null
check "X7 a linked worktree of a NON-lane checkout ⇒ no decision" "$(xhook "$PWT" toolu_x5)" "{}"
check "X7b … and nothing recorded anywhere" "$(ls "$PWT/.supervisor" "$P/.supervisor/inbox" 2>/dev/null | wc -l | tr -d ' ')" 0
git -C "$P" worktree remove --force "$PWT" 2>/dev/null; git -C "$P" branch -q -D feature/p42 2>/dev/null
check "X8 path-unsafe id from the worktree still ignored" "$(xhook "$WT" '../x')" "{}"
awk '/# HOOK-ROOT$/ { print "  root=\"$(git -C \"$cwd\" rev-parse --show-toplevel 2>/dev/null)\"; [ -n \"$root\" ] || root=\"$cwd\""; next } { print }' "$SB" > "$MUT/automate-lanes.sh"
if ! cmp -s "$SB" "$MUT/automate-lanes.sh" && bash -n "$MUT/automate-lanes.sh"; then
  check "X9 mutation (old show-toplevel resolution) ⇒ the worktree question escapes ({})" "$(xhook "$WT" toolu_x9 "$MUT/automate-lanes.sh")" "{}"
  check "X9b … and the lane inbox never sees it" "$([ -e "$L1/.supervisor/inbox/questions/toolu_x9.json" ] && echo recorded || echo none)" none
else bad "X9 mutation control not built"; fi
git -C "$L1" worktree remove --force "$WT" 2>/dev/null; git -C "$L1" branch -q -D feature/42-slug 2>/dev/null

# ---- Y: lane-convert-ready — wave-end conversion pushes the lane run file (owner fix-now FN2) ----------
# The meta-sync stub models the real status: `synced` iff the lane's run files still hash to what the
# last push recorded, else `local_ahead 1`. current-set is the REAL automate-helpers.sh.
cat > "$T/meta-conv.sh" <<'EOF'
#!/usr/bin/env bash
echo "meta-sync $*" >> "$META_LOG"
root=""; pf=""; prev=""
for a in "$@"; do case "$prev" in --root) root="$a" ;; --paths-from) pf="$a" ;; esac; prev="$a"; done
sum() { cat "$root"/.supervisor/automate/*.md 2>/dev/null | cksum; }
case "$1" in
  push)
    echo "paths: $(tr '\n' ' ' < "$pf" 2>/dev/null)" >> "$META_LOG"
    [ -n "${STUB_PUSH_FAIL:-}" ] && { echo "meta_sync: push_failed — rejected 5 times; nothing forced, meta-base untouched" >&2; exit 1; }
    sum > "$root.pushed-sum"; echo "meta_sync: pushed abc123 (1 path(s))"; exit 0 ;;
  status) if [ "$(sum)" = "$(cat "$root.pushed-sum" 2>/dev/null)" ]; then echo "synced abc123 on test-meta"; else echo "local_ahead 1"; fi; exit 0 ;;
  pull) exit 0 ;;
esac
EOF
chmod +x "$T/meta-conv.sh"
conv_rf() { # <lane_dir> <status> <pause_reason> — a lane run file parked as given, recorded as pushed
  local id; id="$(jq -r .run_id "$1/.supervisor/lane.json")"
  printf '# Automate Run: %s\n\n## Status: paused\n\n## Source\n- backlog: lane\n\n## Run Config\n- limit: 1\n\n## Queue\n- [ ] reqs/b.md\n\n## Current\n- item: reqs/b.md | status: %s | pr: https://github.com/o/r/pull/12 | branch: feature/b\n- pause_reason: %s\n\n## Progress\n- 2026-10-08T00:00:00Z drain READY → %s\n' \
    "$id" "$2" "$3" "$2" > "$1/.supervisor/automate/$id.md"
  cat "$1"/.supervisor/automate/*.md | cksum > "$1.pushed-sum"
}
conv() { LOOMWRIGHT_LANES_META_SYNC="$T/meta-conv.sh" LOOMWRIGHT_LANES_HELPERS="$HERE/automate-helpers.sh" bash "$S" lane-convert-ready "$@" 2>&1; }
rmv() { LOOMWRIGHT_LANES_META_SYNC="$T/meta-conv.sh" bash "$S" lane-remove "$@" 2>&1; }
cur_line() { awk '/^## Current/ { c = 1; next } /^## / { c = 0 } c && /^- (item|pause_reason):/' "$1" | tr '\n' '|'; }
run lane-create "$RF" reqs/b.md 14 --parallel 2 >/dev/null; L14="$LR/L14"; RF12="$L14/.supervisor/automate/$PARENT-L14.md"
conv_rf "$L14" escalated escalated; SUM12="$(cksum < "$RF12")"; : > "$META_LOG"
out="$(conv "$L14")"; rc=$?
check "Y1 a run file not reading ready_for_release is refused (exit 1)" "$rc" 1
has "Y1b … naming what it reads" "$out" "refused — L14 — run file reads status escalated / pause_reason escalated, not ready_for_release"
check "Y1c … nothing written, nothing pushed" "$(cksum < "$RF12"):$(grep -c ' push ' "$META_LOG" | tr -d ' ')" "$SUM12:0"
conv_rf "$L14" ready_for_release ready_for_release; SUM12="$(cksum < "$RF12")"
STUB_MODE=sleep LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L14" --owner-command "$OWN" >/dev/null
L4P="$(tcol L14 5)"
out="$(conv "$L14")"; rc=$?
check "Y2 a live lane is refused (exit 1)" "$rc" 1
has "Y2b … naming the process" "$out" "refused — L14 — live lane process (pid $L4P)"
check "Y2c … nothing written, nothing pushed" "$(cksum < "$RF12"):$(grep -c ' push ' "$META_LOG" | tr -d ' ')" "$SUM12:0"
kill -TERM "$L4P" 2>/dev/null; wait_gone "$L14"
out="$(conv "$L14")"; rc=$?
check "Y3 a stopped ready_for_release lane converts (exit 0)" "$rc" 0
has "Y3b … and reports the push" "$out" "converted L14 to awaiting_merge; metadata pushed to test-meta"
check "Y3c ## Current now awaiting_merge (item, PR and branch kept)" "$(cur_line "$RF12")" \
  "- item: reqs/b.md | status: awaiting_merge | pr: https://github.com/o/r/pull/12 | branch: feature/b|- pause_reason: awaiting_merge|"
has "Y3d push passes the lane's metadata branch explicitly and its root" "$(grep ' push ' "$META_LOG")" "meta-sync push --branch test-meta --root $L14 --paths-from "
check "Y3e … and pushes exactly the lane run file" "$(grep '^paths:' "$META_LOG")" "paths: .supervisor/automate/$PARENT-L14.md "
has "Y3f ## Progress kept" "$(cat "$RF12")" "drain READY → ready_for_release"
SUM12="$(cksum < "$RF12")"
out="$(conv "$L14")"; rc=$?
check "Y4 a re-run is idempotent (exit 0, run file byte-unchanged)" "$rc:$(cksum < "$RF12")" "0:$SUM12"
has "Y4b … saying it only retries the push" "$out" "already reads awaiting_merge — retrying the metadata push"
check "Y4c no launch lock left behind" "$(ls -d "$TABLE".L14.launch.lock 2>/dev/null | wc -l | tr -d ' ')" 0
out="$(rmv "$L14")"; rc=$?
check "Y5 afterwards lane-remove's metadata check passes and the lane is removed" "$rc:$([ -d "$L14" ] && echo kept || echo removed)" "0:removed"
# a failed push: loud, exit 2, the lane never looks converted-and-pushed (lane-remove refuses), re-run heals
run lane-create "$RF" reqs/b.md 15 --parallel 2 >/dev/null; L15="$LR/L15"; RF13="$L15/.supervisor/automate/$PARENT-L15.md"
conv_rf "$L15" ready_for_release ready_for_release
out="$(STUB_PUSH_FAIL=1 conv "$L15")"; rc=$?
check "Y6 a failed push exits 2" "$rc" 2
has "Y6b … with a FAILED line naming the lane and the retry" "$out" "lane-convert-ready: FAILED — L15 — converted to awaiting_merge, but the metadata push to test-meta failed (meta-sync exit 1); NOT pushed"
has "Y6c … relaying meta-sync's own reason" "$out" "meta_sync: push_failed"
has "Y6d … and naming the re-run" "$out" "re-run lane-convert-ready $L15"
check "Y6e no launch lock left behind" "$(ls -d "$TABLE".L15.launch.lock 2>/dev/null | wc -l | tr -d ' ')" 0
out="$(rmv "$L15")"; rc=$?
check "Y7 after a failed push lane-remove refuses (metadata not pushed)" "$rc:$(printf '%s' "$out" | grep -c 'metadata not pushed (local_ahead 1)' | tr -d ' ')" "1:1"
out="$(conv "$L15")"; rc=$?
check "Y8 the re-run pushes (exit 0)" "$rc:$(printf '%s' "$out" | grep -c 'metadata pushed to test-meta' | tr -d ' ')" "0:1"
out="$(rmv "$L15")"; rc=$?
check "Y8b … and lane-remove then passes" "$rc:$([ -d "$L15" ] && echo kept || echo removed)" "0:removed"
# metadata mode: unknown refuses before any write; off converts with nothing to push
run lane-create "$RF" reqs/b.md 20 --parallel 2 >/dev/null; L20="$LR/L20"; RF14="$L20/.supervisor/automate/$PARENT-L20.md"
conv_rf "$L20" ready_for_release ready_for_release; SUM14="$(cksum < "$RF14")"; : > "$META_LOG"
out="$(STUB_MODE_LINE='unknown no mode line' conv "$L20")"; rc=$?
check "Y9 metadata mode unknown ⇒ refused before any write" "$rc:$(cksum < "$RF14"):$(printf '%s' "$out" | grep -c 'metadata mode unknown' | tr -d ' ')" "1:$SUM14:1"
out="$(STUB_MODE_LINE=off conv "$L20")"; rc=$?
check "Y10 mode off ⇒ converted, nothing to push" "$rc:$(grep -c ' push ' "$META_LOG" | tr -d ' ')" "0:0"
has "Y10b … reported as such" "$out" "converted L20 to awaiting_merge (metadata mode off — no metadata branch to push)"
out="$(conv "$LR/nope")"; check "Y11 not a lane ⇒ exit 1" "$?" 1
out="$(bash "$HERE/automate-helpers.sh" lane-convert-ready 2>&1)"; rc=$?
check "Y12 automate-helpers.sh dispatches lane-convert-ready (no lane ⇒ not-a-lane refusal)" "$rc:$(printf '%s' "$out" | grep -c 'lane-convert-ready: not a lane' | tr -d ' ')" "1:1"

