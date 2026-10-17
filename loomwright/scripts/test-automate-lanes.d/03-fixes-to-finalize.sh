# ---- Z: Validation 4/5 fixes (parallel-automate/23) ---------------------------------------------------
# Each leg fails against the pre-fix lane code at 91adff5 (identical to #426's head 8226dfe) and passes here.
# Z-F5 lane-readiness writes its report when the Validation names no repro (empty erows / vrows)
run lane-create "$RF" reqs/a.md 2 >/dev/null; LZ5="$LR/L2"; RDZ="$LZ5/.supervisor/automate/$PARENT-L2.merge-readiness.md"
out="$(LOOMWRIGHT_GH_BIN="$T/absent-gh" run lane-readiness "$LZ5")"; rc=$?
check "Z-F5a no named repro (empty erows) ⇒ the report IS written" "$rc:$([ -f "$RDZ" ] && echo written || echo missing)" "0:written"
has "Z-F5b … with the headline-repro n/a line" "$(cat "$RDZ" 2>/dev/null)" "headline-repro: PASS — n/a (the Validation names no repro)"
hasnt "Z-F5c … and never says unwritable" "$out" "report not written"
check "Z-F5d no stray temp file left" "$(ls "$LZ5/.supervisor/automate/" | grep -c '\.tmp\.' | tr -d ' ')" 0
chmod 555 "$LZ5/.supervisor/automate"
out="$(LOOMWRIGHT_GH_BIN="$T/absent-gh" run lane-readiness "$LZ5")"; rc=$?
chmod 755 "$LZ5/.supervisor/automate"
check "Z-F5e a genuine write failure still says unwritable (exit 0, observation)" "$rc:$(printf '%s' "$out" | grep -c 'report not written (unwritable)' | tr -d ' ')" "0:1"
check "Z-F5f … leaving no temp file" "$(ls "$LZ5/.supervisor/automate/" | grep -c '\.tmp\.' | tr -d ' ')" 0

# Z-F9 a clean wave whose lanes were all removed reads `leaks: none`; salvage + stream logs are kept.
# The wave-start snapshot is taken through lanes_leaks directly (same signature before and after the
# fix) so this leg isolates F9 from F1.
PARENT4=automate-2026-10-08-090000; RF4="$P/.supervisor/automate/$PARENT4.md"; LR4="$T/work/primary-lanes/$PARENT4"
printf '# Automate Run: %s\n\n## Progress\n' "$PARENT4" > "$RF4"
( . "$S"; lanes_leaks "$P" "$PARENT4" 1 ) >/dev/null
run lane-create "$RF4" reqs/a.md 1 --parallel 2 >/dev/null; run lane-create "$RF4" reqs/b.md 2 --parallel 2 >/dev/null
LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$LR4/L1" --owner-command "$OWN" >/dev/null; wait_gone "$LR4/L1"
LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$LR4/L2" --owner-command "$OWN" >/dev/null; wait_gone "$LR4/L2"
out="$(run lane-remove "$LR4/L1")$(run lane-remove "$LR4/L2")"
check "Z-F9a both lanes removed" "$([ -e "$LR4/L1" ] || [ -e "$LR4/L2" ] && echo present || echo absent)" absent
out="$(run lane-status "$RF4" --leaks)"
check "Z-F9b after a clean wave lane-status --leaks reads none" "$(printf '%s\n' "$out" | head -1 | cut -c1-11)" "leaks: none"
hasnt "Z-F9c … and lanes-dir is not changed" "$out" "lanes-dir: changed"
check "Z-F9d salvage kept at <primary>-lanes/<run_id>/salvage/" "$(ls -d "$LR4"/salvage/L1-removed-* "$LR4"/salvage/L2-removed-* 2>/dev/null | wc -l | tr -d ' ')" 2
check "Z-F9e stream logs kept at <primary>-lanes/<run_id>/L<n>.stream.log" "$([ -s "$LR4/L1.stream.log" ] && [ -s "$LR4/L2.stream.log" ] && echo kept)" kept
mkdir -p "$LR4/L3"; : > "$LR4/stray.txt"
out="$(run lane-status "$RF4" --leaks)"
has "Z-F9f a lane directory left behind is still a leak" "$out" "  + $PARENT4/L3"
has "Z-F9g … and so is any other file in the run directory (exact names only)" "$out" "  + $PARENT4/stray.txt"
rm -rf "$LR4/L3" "$LR4/stray.txt"

# Z-F1 §14 step 5 (snapshot) runs BEFORE step 6 (first lane-create): no <run_id>.lanes table yet
PARENT3=automate-2026-10-08-080000; RF3="$P/.supervisor/automate/$PARENT3.md"
SF3="$P/.supervisor/automate/$PARENT3.leaks-snapshot"
printf '# Automate Run: %s\n\n## Progress\n' "$PARENT3" > "$RF3"
check "Z-F1a fixture: no lane table yet" "$([ -e "$P/.supervisor/automate/$PARENT3.lanes" ] && echo table || echo none)" none
out="$(run lane-status "$RF3" --leaks --snapshot)"; rc=$?
check "Z-F1b snapshot with no lane table is written (exit 0)" "$rc:$([ -s "$SF3" ] && echo written || echo missing)" "0:written"
has "Z-F1c … and says so (never a silent 'no lanes')" "$out" "leaks: snapshot written — $SF3"
hasnt "Z-F1d … no 'no lanes' line" "$out" "no lanes"
run lane-create "$RF3" reqs/a.md 1 >/dev/null
check "Z-F1e the snapshot is the baseline the end-of-wave check reads" "$(run lane-status "$RF3" --leaks | head -1 | cut -c1-6)" "leaks:"
rm -f "$SF3"; chmod 555 "$P/.supervisor/automate"
out="$(run lane-status "$RF3" --leaks --snapshot)"; rc=$?
chmod 755 "$P/.supervisor/automate"
check "Z-F1f an unwritable snapshot exits non-zero (the one fail-SAFE exception)" "$([ "$rc" != 0 ] && echo nonzero || echo zero)" nonzero
has "Z-F1g … naming why" "$out" "leaks: snapshot not written (unwritable)"
rm -rf "$T/work/primary-lanes/$PARENT3/L1"; rm -f "$P/.supervisor/automate/$PARENT3.lanes"
chmod 555 "$P/.supervisor/automate"
out="$(run lane-status "$RF3" --leaks --snapshot)"; rc=$?
chmod 755 "$P/.supervisor/automate"
check "Z-F1h … with no lane table too" "$([ "$rc" != 0 ] && echo nonzero || echo zero):$(printf '%s' "$out" | grep -c 'snapshot not written' | tr -d ' ')" "nonzero:1"
out="$(run lane-status "$P/.supervisor/automate/absent-run.md" --leaks --snapshot)"; rc=$?
check "Z-F1i a parent run file that does not exist ⇒ non-zero, named" "$([ "$rc" != 0 ] && echo nonzero || echo zero):$(printf '%s' "$out" | grep -c 'parent run file not found' | tr -d ' ')" "nonzero:1"

# Z-F10 lane-remove --abandon writes no absolute path into the parent run file, and reports the lane's
# REAL state (lane-status's reader: a parked lane whose PR closed unmerged reads `gone`). progress-append
# is the real helper; HOME is set to the fixture root so every absolute fixture path is a $HOME path.
PARENT5=automate-2026-10-08-100000; RF5="$P/.supervisor/automate/$PARENT5.md"; LR5="$T/work/primary-lanes/$PARENT5"
printf '# Automate Run: %s\n\n## Progress\n' "$PARENT5" > "$RF5"
cat > "$T/helpers-gone.sh" <<'EOF'
#!/usr/bin/env bash
case "$1" in reconcile-item) echo gone ;; *) exec bash "$REAL_HELPERS" "$@" ;; esac
EOF
chmod +x "$T/helpers-gone.sh"; export REAL_HELPERS="$HERE/automate-helpers.sh"
run lane-create "$RF5" reqs/a.md 1 >/dev/null; L51="$LR5/L1"
LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L51" --owner-command "$OWN" >/dev/null; wait_gone "$L51"
printf '# Automate Run: %s-L1\n\n## Current\n- item: reqs/a.md | status: awaiting_merge | pr: https://github.com/o/r/pull/51 | branch: f\n- pause_reason: awaiting_merge\n\n## Progress\n' "$PARENT5" > "$L51/.supervisor/automate/$PARENT5-L1.md"
check "Z-F10a fixture: lane-status reads the lane gone" \
  "$(LOOMWRIGHT_LANES_HELPERS="$T/helpers-gone.sh" bash "$S" lane-status "$RF5" --json 2>/dev/null | jq -r '.lanes[] | select(.lane == "L1") | .state')" gone
out="$(HOME="$T" LOOMWRIGHT_LANES_HELPERS="$T/helpers-gone.sh" run lane-remove "$L51" --abandon)"; rc=$?
check "Z-F10b lane-remove --abandon removes the gone lane" "$rc:$([ -d "$L51" ] && echo kept || echo removed)" "0:removed"
ABL="$(grep 'lane abandoned: L1' "$RF5")"
has "Z-F10c the abandoned line reports the real state (gone, not the table's launched)" "$ABL" "— state gone;"
has "Z-F10d … and names the salvage in the <primary>-lanes/… form" "$ABL" "salvage kept at <primary>-lanes/$PARENT5/salvage/L1-removed-"
check "Z-F10e no line in the parent run file contains \$HOME" "$(grep -cF "$T" "$RF5" | tr -d ' ')" 0
check "Z-F10f no token in the parent run file starts with /" "$(grep -cE '(^|[[:space:]])/' "$RF5" | tr -d ' ')" 0

# Z-F4 a lane that died after its PICK resumes in its LAST session (its run.lock is session-id
# re-entrant), never a fresh one that waits out the dead session's lock; fresh only as the fallback
run lane-create "$RF5" reqs/b.md 2 >/dev/null; L52="$LR5/L2"
STUB_MODE=die LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L52" --owner-command "$OWN" >/dev/null; wait_gone "$L52"
printf '# Automate Run: %s-L2\n\n## Progress\n- picked reqs/b.md\n' "$PARENT5" > "$L52/.supervisor/automate/$PARENT5-L2.md"
check "Z-F4a fixture: the lane reads died with a recorded session" \
  "$(bash "$S" lane-status "$RF5" --json 2>/dev/null | jq -r '.lanes[] | select(.lane == "L2") | .state + " " + .session_id')" "died sess-123"
SUM52="$(lane_sum "$L52")"; n4="$(claude_calls)"
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L52" --owner-command "/automate --resume $PARENT5" --resume-run "$PARENT5-L2")"; rc=$?
wait_gone "$L52"
check "Z-F4b --resume-run launches once (exit 0)" "$rc:$(( $(claude_calls) - n4 ))" "0:1"
has "Z-F4c … resuming the lane's last session (the run lock's re-entrant path)" "$(grep '^ARGS' "$STUB_LOG" | tail -1)" "[--resume] [sess-123]"
has "Z-F4d … with the lane's own resume command" "$(grep '^STDIN' "$STUB_LOG" | tail -1)" "/loomwright:automate --resume $PARENT5-L2"
check "Z-F4e … telling the lane which path it is on (it records it in ## Progress itself)" "$(grep '^RESUMEPATH' "$STUB_LOG" | tail -1)" "RESUMEPATH session sess-123"
check "Z-F4f the coordinator wrote nothing into the lane (run file, lock)" "$(lane_sum "$L52")" "$SUM52"
n4="$(claude_calls)"
out="$(STUB_RESUME_FAIL=1 LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L52" --owner-command "/automate --resume $PARENT5" --resume-run "$PARENT5-L2")"; rc=$?
wait_gone "$L52"
check "Z-F4g an unresumable session falls back to ONE fresh session (two spawns)" "$rc:$(( $(claude_calls) - n4 ))" "0:2"
has "Z-F4h … saying so" "$out" "could not be resumed"
hasnt "Z-F4i … the fallback carries no --resume" "$(grep '^ARGS' "$STUB_LOG" | tail -1)" "[--resume]"
check "Z-F4j … and tells the lane it is on the fresh path" "$(grep '^RESUMEPATH' "$STUB_LOG" | tail -1)" "RESUMEPATH fresh session (last session sess-123 not resumable)"
has "Z-F4k a normal launch carries an empty resume path" "$(grep '^RESUMEPATH' "$STUB_LOG" | head -1)" "RESUMEPATH "

# Z-F2 a HELD answer is kept coordinator-side (validated answers + note + via, never an owner command),
# shown as answer_pending, and delivered ONLY by the delivery form under a current-session owner command
zq() { # <lane_dir> <tool_use_id> <session> — a recorded question the lane parked on (deferred)
  jq -n -c --argjson q "$Q2" --arg id "$2" '{id: $id, asked_at: "2026-10-08T00:00:00Z", questions: $q}' > "$1/.supervisor/inbox/questions/$2.json"
  jq -n -c --argjson q "$Q2" --arg id "$2" --arg s "$3" '{type: "result", subtype: "success", stop_reason: "tool_deferred", session_id: $s, deferred_tool_use: {id: $id, input: {questions: $q}}}' >> "$(dirname "$1")/$(basename "$1").stream.log"
}
t5set() { awk -F'\t' -v OFS='\t' -v l="$1" -v c="$2" -v v="$3" '$1 == l { $c = v } { print }' "$P/.supervisor/automate/$PARENT5.lanes" > "$T/t5" && mv "$T/t5" "$P/.supervisor/automate/$PARENT5.lanes"; }
run lane-create "$RF5" reqs/a.md 3 >/dev/null; L53="$LR5/L3"; zq "$L53" toolu_z2 sess-z2
t5set L3 8 launched; t5set L3 9 "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
PF53="$P/.supervisor/automate/$PARENT5.L3.answer-pending.json"; AF53="$L53/.supervisor/inbox/answers/toolu_z2.json"
z2() { printf '%s' "$1" | bash "$S" lane-answer "$L53" toolu_z2 "${@:2}" 2>&1; }
n2="$(claude_calls)"
out="$(STUB_LOAD=busy z2 '{"answers":{"0":"Red","1":"A,B"},"note":"small diff"}' --owner-command "$OWN" --via test)"; rc=$?
check "Z-F2a load busy ⇒ HELD (exit 4)" "$rc:$(printf '%s\n' "$out" | head -1)" "4:lane-launch: HELD — L3 — load busy"
check "Z-F2b the validated answer is KEPT coordinator-side (answers, note, via)" \
  "$(jq -c '[.tool_use_id, .answers["0"], .answers["1"], .note, .via]' "$PF53" 2>/dev/null)" '["toolu_z2","Red","A,B","small diff","test"]'
check "Z-F2c … and the pending file holds no owner command" "$(grep -cF "$OWN" "$PF53" 2>/dev/null | tr -d ' '):$(jq -r 'keys | map(select(test("owner"))) | length' "$PF53" 2>/dev/null)" "0:0"
check "Z-F2d nothing written into the lane, nothing spawned" "$([ -e "$AF53" ] && echo written || echo none):$(( $(claude_calls) - n2 ))" "none:0"
J="$(bash "$S" lane-status "$RF5" --json 2>/dev/null)"
check "Z-F2e lane-status shows the lane as answer_pending" "$(jq -r '.lanes[] | select(.lane == "L3") | .state' <<<"$J")" answer_pending
out="$(run lane-status "$RF5")"
has "Z-F2f … plain view names the delivery form" "$out" "L3  answer_pending"
check "Z-F2g lane-status (observation) delivered nothing, spawned nothing" "$([ -e "$AF53" ] && echo written || echo none):$(( $(claude_calls) - n2 ))" "none:0"
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 run lane-answer "$L53" --deliver-pending)"; rc=$?
check "Z-F2h a pending file with NO current-session owner command is NOT delivered (BLOCKED, exit 3)" "$rc:$(printf '%s\n' "$out" | head -1)" "3:lane-launch: BLOCKED — L3 — no owner-invoked command — need the owner"
check "Z-F2i … nothing written into the lane, nothing spawned, the answer still pending" \
  "$([ -e "$AF53" ] && echo written || echo none):$(( $(claude_calls) - n2 )):$([ -s "$PF53" ] && echo kept || echo gone)" "none:0:kept"
out="$(STUB_LOAD=busy run lane-answer "$L53" --deliver-pending --owner-command "/automate --resume $PARENT5")"; rc=$?
check "Z-F2j still busy at delivery ⇒ HELD again, pending kept" "$rc:$([ -s "$PF53" ] && echo kept || echo gone):$([ -e "$AF53" ] && echo written || echo none)" "4:kept:none"
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 run lane-answer "$L53" --deliver-pending --owner-command "/automate --resume $PARENT5")"; rc=$?
check "Z-F2k the delivery form under the poll's owner command delivers (exit 0)" "$rc:$(( $(claude_calls) - n2 ))" "0:1"
check "Z-F2l … the answer file carries the stored labels and note" "$(jq -c '[.answers["Which color?"], .answers["Which extras?"], .note]' "$AF53" 2>/dev/null)" '["Red","A,B","small diff"]'
check "Z-F2m … the pending file is gone" "$([ -e "$PF53" ] && echo kept || echo gone)" gone
has "Z-F2n … and resumes the deferred session" "$(grep '^ARGS' "$STUB_LOG" | tail -1)" "[--resume] [sess-z2]"
wait_gone "$L53"
# a planted pending file (any process that can write the primary's .supervisor/automate/) is re-checked
run lane-create "$RF5" reqs/b.md 4 >/dev/null; L54="$LR5/L4"; zq "$L54" toolu_z3 sess-z3
PF54="$P/.supervisor/automate/$PARENT5.L4.answer-pending.json"; n2="$(claude_calls)"
printf '{"lane":"L4","tool_use_id":"toolu_z3","answers":{"0":"Purple","1":"A"},"note":null,"via":"x"}\n' > "$PF54"
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 run lane-answer "$L54" --deliver-pending --owner-command "$OWN")"; rc=$?
check "Z-F2o a stored answer that is not one of the question's labels is refused" "$rc:$(printf '%s' "$out" | grep -c 'no longer matches' | tr -d ' ')" "1:1"
check "Z-F2p … nothing written into the lane, nothing spawned, the stale file discarded" \
  "$([ -e "$L54/.supervisor/inbox/answers/toolu_z3.json" ] && echo written || echo none):$(( $(claude_calls) - n2 )):$([ -e "$PF54" ] && echo kept || echo gone)" "none:0:gone"
printf '{"lane":"L4","tool_use_id":"toolu_zz","answers":{"0":"Red","1":"A"},"note":null,"via":"x"}\n' > "$PF54"
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 run lane-answer "$L54" --deliver-pending --owner-command "$OWN")"; rc=$?
check "Z-F2q a stored answer for a tool_use_id the lane is not deferred on is refused" "$rc:$([ -e "$L54/.supervisor/inbox/answers/toolu_zz.json" ] && echo written || echo none):$(( $(claude_calls) - n2 ))" "1:none:0"
# Z-F2r..w (fix-now F-1/F-4) a HELD answer sets the table's state column to held_for_load; after its
# pending file is DISCARDED the lane's question is unanswered again, so lane-status must read
# awaiting_input (the question relayed), never held_for_load (which hides it and invites a fresh launch).
t5set L4 8 launched; t5set L4 9 "$(date -u +%Y-%m-%dT%H:%M:%SZ)"; n2="$(claude_calls)"
z4() { printf '%s' "$1" | bash "$S" lane-answer "$L54" toolu_z3 "${@:2}" 2>&1; }
out="$(STUB_LOAD=busy z4 '{"answers":{"0":"Red","1":"A"}}' --owner-command "$OWN" --via 'a b;c')"; rc=$?
check "Z-F2r fixture: HELD keeps the answer; a via that is not a short client token is stored as cli" "$rc:$(jq -r '.via' "$PF54" 2>/dev/null)" "4:cli"
out="$(STUB_LOAD=busy z4 '{"answers":{"0":"Blue","1":"B"}}' --owner-command "$OWN")"; rc=$?
check "Z-F2s a second HELD answer for the same question replaces the kept one (last write wins)" "$rc:$(jq -c '[.answers["0"], .answers["1"]]' "$PF54" 2>/dev/null)" '4:["Blue","B"]'
check "Z-F2t fixture: the table's state column reads held_for_load" "$(awk -F'\t' '$1 == "L4" { print $8 }' "$P/.supervisor/automate/$PARENT5.lanes")" held_for_load
jq -c '.answers["0"] = "Purple"' "$PF54" > "$PF54.t" && mv "$PF54.t" "$PF54"
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 run lane-answer "$L54" --deliver-pending --owner-command "$OWN")"; rc=$?
check "Z-F2u fixture: the stale pending answer is discarded" "$rc:$([ -e "$PF54" ] && echo kept || echo gone):$(( $(claude_calls) - n2 ))" "1:gone:0"
J="$(bash "$S" lane-status "$RF5" --json 2>/dev/null)"
check "Z-F2v after the discard lane-status reads awaiting_input (the question shows again), not held_for_load" \
  "$(jq -r '.lanes[] | select(.lane == "L4") | .state + " " + (.questions | map(.id) | join(","))' <<<"$J")" "awaiting_input toolu_z3"
has "Z-F2w … the reason still names the last launch's hold" "$(jq -r '.lanes[] | select(.lane == "L4") | .reason' <<<"$J")" "last launch held for load: load busy"

# Z-F11 wave end with an UNMERGED done stamp: convert → PR closed unmerged → lane-remove --abandon.
# The lane is removable with no hand step, and the metadata branch (a fake remote the meta-sync stub
# keeps) never receives a done claim or a jobs/done/ brief for the unmerged work. trail-pr and its
# evidence gate are the REAL scripts (a copy whose setup-memory.sh reads branch mode on).
SC="$T/scripts-copy"; cp -R "$HERE" "$SC"
printf '#!/usr/bin/env bash\necho "on test-meta"\n' > "$SC/setup-memory.sh"
export REMOTE11="$T/remote11"; mkdir -p "$REMOTE11"
cat > "$T/meta-f11.sh" <<'EOF'
#!/usr/bin/env bash
echo "meta-sync $*" >> "$META_LOG"
root=""; pf=""; prev=""
for a in "$@"; do case "$prev" in --root) root="$a" ;; --paths-from) pf="$a" ;; esac; prev="$a"; done
managed() { (cd "$root" && find .supervisor/requirements .supervisor/jobs/done .supervisor/jobs/failed .supervisor/automate .supervisor/postmortem \
  -type f \( -name '*.md' -o -name '*.dismissed-decisions' -o -name results.jsonl \) 2>/dev/null | env LC_ALL=C sort); }
case "$1" in
  push) echo "f11-paths: $(tr '\n' ' ' < "$pf")" >> "$META_LOG"
        while IFS= read -r p; do [ -n "$p" ] || continue
          if [ -f "$root/$p" ]; then mkdir -p "$REMOTE11/$(dirname "$p")"; cp "$root/$p" "$REMOTE11/$p"; else rm -f "$REMOTE11/$p"; fi
        done < "$pf"; echo "meta_sync: pushed abc"; exit 0 ;;
  status) n=0; ps=""; for p in $(managed); do cmp -s "$root/$p" "$REMOTE11/$p" || { n=$((n + 1)); ps="$ps  $p
"; }; done
          if [ "$n" = 0 ]; then echo "synced abc on test-meta"; else echo "local_ahead $n"; case " $* " in *" --paths "*) printf '%s' "$ps" ;; esac; fi; exit 0 ;;
  pull) exit 0 ;;
esac
EOF
cat > "$T/gh-f11" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >> "$T_GH11"
case "$1 $2" in "pr view") printf '{"state":"%s","mergedAt":null}\n' "${STUB_PR_STATE:-OPEN}" ;; *) exit 1 ;; esac
EOF
chmod +x "$T/meta-f11.sh" "$T/gh-f11"; export T_GH11="$T/gh-f11.calls"
f11() { LOOMWRIGHT_LANES_META_SYNC="$T/meta-f11.sh" LOOMWRIGHT_LANES_HELPERS="$SC/automate-helpers.sh" LOOMWRIGHT_LANES_TRAIL="$SC/automate-helpers.sh" \
  LOOMWRIGHT_GH_BIN="$T/gh-f11" bash "$S" "$@" 2>&1; }
run lane-create "$RF5" reqs/a.md 5 >/dev/null; L55="$LR5/L5"; R11=".supervisor/requirements/t/x.md"; PR11="https://github.com/o/r/pull/55"
LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L55" --owner-command "$OWN" >/dev/null; wait_gone "$L55"
mkdir -p "$L55/.supervisor/requirements/t" "$L55/.supervisor/jobs/done"
printf '# x\n\n## Status: pending\n\n## Status: done\n<!-- loomwright:requirement-closeout -->\n- **PR:** %s\n' "$PR11" > "$L55/$R11"
printf '# brief\n- **Source requirement:** %s\n\n## Outcome\n- **PR:** %s\n' "$R11" "$PR11" > "$L55/.supervisor/jobs/done/2026-10-08-x.md"
printf '# Automate Run: %s-L5\n\n## Status: paused\n\n## Queue\n- [ ] %s\n\n## Current\n- item: %s | status: ready_for_release | pr: %s | branch: f\n- pause_reason: ready_for_release\n\n## Progress\n- drain READY\n' \
  "$PARENT5" "$R11" "$R11" "$PR11" > "$L55/.supervisor/automate/$PARENT5-L5.md"
printf '# Merge readiness\n- score: 3/5\n' > "$L55/.supervisor/automate/$PARENT5-L5.merge-readiness.md"
out="$(STUB_PR_STATE=OPEN f11 lane-convert-ready "$L55")"; rc=$?
check "Z-F11a wave-end conversion with the PR still open exits 0" "$rc" 0
has "Z-F11b … the gated trail names the unmerged done stamp as excluded" "$out" "excluded $R11 — pr not merged"
check "Z-F11c … and nothing on the metadata branch carries it or a done/ brief" \
  "$([ -e "$REMOTE11/$R11" ] && echo req || echo noreq):$(ls "$REMOTE11/.supervisor/jobs/done" 2>/dev/null | wc -l | tr -d ' ')" "noreq:0"
check "Z-F11d … the run file and the readiness report were pushed" \
  "$([ -f "$REMOTE11/.supervisor/automate/$PARENT5-L5.md" ] && [ -f "$REMOTE11/.supervisor/automate/$PARENT5-L5.merge-readiness.md" ] && echo pushed)" pushed
out="$(STUB_PR_STATE=OPEN f11 lane-remove "$L55")"
has "Z-F11e an open PR's lane still refuses removal (its done stamp is unpushed by design)" "$out" "metadata not pushed"
out="$(STUB_PR_STATE=CLOSED f11 lane-remove "$L55" --abandon)"; rc=$?
check "Z-F11f PR closed unmerged ⇒ lane-remove --abandon removes the lane with no hand step" "$rc:$([ -d "$L55" ] && echo kept || echo removed)" "0:removed"
EMD="$(printf '\342\200\224')"
check "Z-F11g the metadata branch holds the reconcile-status ABANDONED stamp shape" \
  "$(grep -c "^## Status: done_with_escalation $EMD ABANDONED (- \[x\] $R11  # abandoned: " "$REMOTE11/$R11" 2>/dev/null | tr -d ' ')" 1
check "Z-F11h … and no other done heading (no done claim for the unmerged PR)" \
  "$(grep -E '^## Status:[[:space:]]*done' "$REMOTE11/$R11" 2>/dev/null | grep -vc "ABANDONED (- \[x\] " | tr -d ' ')" 0
check "Z-F11i … no jobs/done/ brief; the brief rides under jobs/failed/" \
  "$(ls "$REMOTE11/.supervisor/jobs/done" 2>/dev/null | wc -l | tr -d ' '):$(ls "$REMOTE11/.supervisor/jobs/failed" 2>/dev/null | tr '\n' ' ')" "0:2026-10-08-x.md "
has "Z-F11j the parent run file records the abandon with the real state" "$(cat "$RF5")" "lane abandoned: L5 ($PARENT5-L5) — state gone;"

# ---- AA: Validation 4/5 fixes B (parallel-automate/24) ------------------------------------------------
# Each leg fails against the pre-fix code at 9a65ecb and passes here.
# AA-F12 lane-feed --follow: signalling the lane-feed process ALONE leaves no tail | grep | jq behind.
AA_TAIL="tail -n \\+1 -f $(ere "$LR2/L6.stream.log")"
aa_feed() { # <signal> — prints "<seen|unseen> <none|survivor>"; kills any survivor afterwards
  local sig="$1" fp i=0 seen=unseen
  # An async child starts with SIGINT ignored, and a suite launched under `nohup` (a detached
  # ci-local / harness run) passes SIGHUP down ignored too — and bash cannot trap a signal that was
  # ignored on entry, so HUP then never reached lane-feed's trap and AA-F12b read "survivor" 50/50
  # (iq02 T07). Reset BOTH to default before exec, as a terminal would deliver them.
  python3 -c 'import os, signal, sys; signal.signal(signal.SIGINT, signal.SIG_DFL); signal.signal(signal.SIGHUP, signal.SIG_DFL); os.execvp(sys.argv[1], sys.argv[1:])' \
    bash "$S" lane-feed "$L6" --follow > "$T/aa-follow.$sig" 2>&1 & fp=$!
  # Clock-bounded (wait-lib), not count-bounded: AA-F12b went red under a loaded pool (iq02 T07).
  wait_for_cmd 15 pgrep -f "$AA_TAIL" 2>/dev/null && seen=seen
  sleep 0.3; kill -"$sig" "$fp" 2>/dev/null   # fixed-sleep-ok: settle — the pipeline's traps installed before the signal (too short ⇒ a different, earlier-kill path is tested)
  wait_for_pid_gone "$fp" 10 2>/dev/null
  kill -KILL "$fp" 2>/dev/null; wait "$fp" 2>/dev/null   # bounded: a lane-feed that ignores the signal never hangs the suite
  _aa_no_tail() { ! pgrep -f "$AA_TAIL" >/dev/null 2>&1; }
  wait_for_cmd 10 _aa_no_tail 2>/dev/null
  if pgrep -f "$AA_TAIL" >/dev/null 2>&1; then echo "$seen survivor"; pkill -TERM -f "$AA_TAIL" 2>/dev/null; else echo "$seen none"; fi
}
check "AA-F12a TERM to lane-feed --follow alone ⇒ its tail pipeline is gone (and the escaped pattern did see it)" "$(aa_feed TERM)" "seen none"
check "AA-F12b HUP ⇒ the same" "$(aa_feed HUP)" "seen none"
check "AA-F12c INT ⇒ the same" "$(aa_feed INT)" "seen none"
has "AA-F12d the follow still narrates" "$(cat "$T/aa-follow.TERM")" "[spawn] loomwright:worker"
check "AA-F12e the unescaped pattern T8 used never matched a live tail (the root cause, not the path)" \
  "$(bash "$S" lane-feed "$L6" --follow >/dev/null 2>&1 & fp=$!
     # first prove the tail IS up (the escaped pattern sees it), so `unmatched` cannot pass on a slow start
     if wait_for_cmd 15 pgrep -f "$AA_TAIL" 2>/dev/null; then
       pgrep -f "tail -n +1 -f $LR2/L6.stream.log" >/dev/null 2>&1 && echo matched || echo unmatched
     else echo "tail-never-up"; fi
     kill "$fp" 2>/dev/null; wait "$fp" 2>/dev/null; pkill -TERM -f "$AA_TAIL" 2>/dev/null)" unmatched

# AA fixture: one lane (L1) of a fresh parent run, its run file at the ready_for_release park.
PARENT6=automate-2026-10-08-110000; RF6="$P/.supervisor/automate/$PARENT6.md"; LR6="$T/work/primary-lanes/$PARENT6"
printf '# Automate Run: %s\n\n## Progress\n' "$PARENT6" > "$RF6"
run lane-create "$RF6" reqs/a.md 1 --parallel 2 --max-tokens 200 >/dev/null; L61="$LR6/L1"; LRF6="$L61/.supervisor/automate/$PARENT6-L1.md"
PR6="https://github.com/o/r/pull/66"
printf '# Automate Run: %s-L1\n\n## Status: paused\n\n## Queue\n- [ ] reqs/a.md\n\n## Current\n- item: reqs/a.md | status: ready_for_release | pr: %s | branch: f\n- pause_reason: ready_for_release\n\n## Progress\n- 2026-10-08T11:00:00Z session_id sess-aa (reqs/a.md)\n' \
  "$PARENT6" "$PR6" > "$LRF6"
# AA-F8 a lane whose log holds a real (transcript-usage) ledger line reads a non-zero TOTAL, and its share parks.
mkdir -p "$T/subagents"; AAT="$T/subagents/agent-aa1.jsonl"   # the agent's OWN transcript name — the emitter sums only agent-<agent_id>.jsonl
{ for o in 8 8; do printf '{"type":"assistant","message":{"id":"msg_A","stop_reason":null,"usage":{"input_tokens":10,"output_tokens":%s,"cache_read_input_tokens":100,"cache_creation_input_tokens":50,"cache_creation":{"ephemeral_5m_input_tokens":50}}}}\n' "$o"; done
  echo '{"type":"assistant","message":{"id":"msg_A","stop_reason":"end_turn","usage":{"input_tokens":10,"output_tokens":263,"cache_read_input_tokens":100,"cache_creation_input_tokens":50}}}'
  echo '{"type":"assistant","message":{"id":"msg_B","stop_reason":null,"usage":{"input_tokens":7,"output_tokens":40,"cache_read_input_tokens":200,"cache_creation_input_tokens":0}}}'
} > "$AAT"
jq -n --arg a "$AAT" '{session_id: "sess-aa", agent_id: "aa1", agent_transcript_path: $a}' \
  | (cd "$L61" && env -u LOOMWRIGHT_ORIENTATION_SOURCE -u LOOMWRIGHT_SHARED_PREFIX -u LOOMWRIGHT_ADVISORY_TOTAL_BYTES bash "$HERE/emit-token-ledger.sh")
check "AA-F8a the real emitter wrote a transcript-usage line into the lane's log" \
  "$(jq -r '"\(.usage_source) \(.output_tokens)"' "$L61/.supervisor/logs/sess-aa.jsonl" 2>/dev/null)" "transcript 303"
out="$(run lane-status "$RF6" --tokens)"
check "AA-F8b lane-status --tokens: the lane's TOTAL is non-zero (the real reader)" \
  "$(printf '%s\n' "$out" | awk '$1 == "L1"' | grep -oE 'TOTAL=[0-9]+')" "TOTAL=670"
check "AA-F8c ceiling-check on the lane run file with a share below that total ⇒ PARK" \
  "$(cd "$L61" && bash "$HERE/automate-helpers.sh" ceiling-check "$LRF6" 100)" "PARK: token_ceiling total=670 max=100"


# AA-F6 lane-park-notify: desktop + automate_ready_for_release webhook, one truthful ## Progress line.
cat > "$T/aa-nd.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$(cat)" >> "$AA_ND_LOG"
[ -n "${STUB_ND_AUDIT:-}" ] && { mkdir -p .supervisor/logs; echo "2026-10-08T11:00:00Z notify group=loomwright-x tool_use_id=-" >> .supervisor/logs/notifications.log; }
exit 0
EOF
cat > "$T/aa-sw.sh" <<'EOF'
#!/usr/bin/env bash
echo "dry=${LOOMWRIGHT_WEBHOOK_DRY_RUN:-} $*" >> "$AA_SW_LOG"
case "${STUB_SW:-none}" in
  ignored) echo "repo_webhook_ignored slug=o/r" >&2 ;;
  configured) [ -n "${LOOMWRIGHT_WEBHOOK_DRY_RUN:-}" ] && echo '{"event_type":"gate"}' ;;
esac
exit 0
EOF
chmod +x "$T/aa-nd.sh" "$T/aa-sw.sh"; export AA_ND_LOG="$T/aa-nd.log" AA_SW_LOG="$T/aa-sw.log"
# `desktop: sent` also needs the platform notifier notify-desktop.sh dispatches to, so the host's own
# PATH must not decide these legs: pn pins the OS (AA_UNAME, default Darwin) and prepends a stub
# osascript + notify-send (never executed — only probed with `command -v`). AA_PATH replaces the
# whole PATH for the no-notifier leg (AA-F6m); AA_ND swaps the notifier stub (AA-F6r/s).
mkdir -p "$T/aa-bin"; printf '#!/usr/bin/env bash\nexit 0\n' > "$T/aa-bin/osascript"; cp "$T/aa-bin/osascript" "$T/aa-bin/notify-send"
chmod +x "$T/aa-bin/osascript" "$T/aa-bin/notify-send"
pn() { : > "$AA_ND_LOG"; : > "$AA_SW_LOG"; PATH="${AA_PATH:-$T/aa-bin:$PATH}" LOOMWRIGHT_LANES_UNAME="${AA_UNAME:-Darwin}" \
  LOOMWRIGHT_LANES_HELPERS="$HERE/automate-helpers.sh" LOOMWRIGHT_LANES_NOTIFY_DESKTOP="${AA_ND:-$T/aa-nd.sh}" \
  LOOMWRIGHT_LANES_SEND_WEBHOOK="$T/aa-sw.sh" bash "$S" lane-park-notify "$@" 2>&1; }
pcount() { grep -c 'lane park notify: ready_for_release' "$LRF6" | tr -d ' '; }
out="$(STUB_SW=ignored STUB_ND_AUDIT=1 LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 pn "$LRF6")"; rc=$?
check "AA-F6a webhook ignored ⇒ exit 0, ONE ## Progress line" "$rc:$(pcount)" "0:1"
has "AA-F6b … the line names the delivered desktop channel" "$(grep 'lane park notify' "$LRF6")" "desktop: sent;"
has "AA-F6c … and says the webhook was ignored, with the reason" "$(grep 'lane park notify' "$LRF6")" "webhook: ignored (repo_webhook_ignored slug=o/r — no user-scope egress grant)"
check "AA-F6d the desktop payload: automate_ready_for_release, the do-not-merge message" \
  "$(jq -r '"\(.hook_event_name) \(.notification_type) \(.message | test("^https://github.com/o/r/pull/66 READY — do not merge yet — wave open"))"' "$AA_ND_LOG")" \
  "Notification automate_ready_for_release true"
check "AA-F6e an ignored webhook is only probed (dry run), never posted" "$(grep -c '^dry= ' "$AA_SW_LOG" | tr -d ' ')" 0
has "AA-F6f … with gate type automate_ready_for_release" "$(cat "$AA_SW_LOG")" "--gate-type automate_ready_for_release --context https://github.com/o/r/pull/66 READY — do not merge yet — wave open"
out="$(STUB_SW=configured STUB_ND_AUDIT=1 LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 LOOMWRIGHT_NOTIFY_DEBOUNCE=0 pn "$LRF6")"
has "AA-F6g webhook configured ⇒ posted once, reported as attempted (never 'sent': its HTTP result is unreported)" \
  "$(grep -c '^dry= --event-type gate --gate-type automate_ready_for_release' "$AA_SW_LOG" | tr -d ' '):$out" "1:lane-park-notify: lane park notify: ready_for_release ($PARENT6-L1) — desktop: sent; webhook: attempted"
out="$(STUB_SW=none LOOMWRIGHT_DESKTOP_NOTIFICATIONS=0 pn "$LRF6")"
check "AA-F6h desktop opted out ⇒ disabled, the notifier not run; no webhook ⇒ not configured" \
  "$(wc -l < "$AA_ND_LOG" | tr -d ' '):${out#*— }" "0:desktop: disabled (LOOMWRIGHT_DESKTOP_NOTIFICATIONS=0); webhook: not configured"
out="$(STUB_SW=none LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 pn "$LRF6")"
has "AA-F6i the notifier wrote no audit line ⇒ suppressed, never sent" "$out" "desktop: suppressed (no audit line"
check "AA-F6j one ## Progress line per run (four runs, four lines)" "$(pcount)" 4
# AA-F6m..p `sent` is claimed only when a platform notifier exists: notify-desktop.sh writes its audit
# line on EVERY host before its platform dispatch, so the audit line alone proves no banner.
# The no-notifier PATH is a symlink farm of the host's PATH minus the three notifiers it can dispatch to.
mkdir -p "$T/aa-nonotify-bin"
_aa_ifs="$IFS"; IFS=:
for _aa_d in $PATH; do
  [ -d "$_aa_d" ] || continue
  for _aa_f in "$_aa_d"/*; do
    _aa_n="${_aa_f##*/}"
    case "$_aa_n" in osascript|terminal-notifier|notify-send) continue ;; esac
    [ -x "$_aa_f" ] && [ ! -e "$T/aa-nonotify-bin/$_aa_n" ] && ln -s "$_aa_f" "$T/aa-nonotify-bin/$_aa_n" 2>/dev/null
  done
done
IFS="$_aa_ifs"
out="$(AA_PATH="$T/aa-nonotify-bin" STUB_SW=none STUB_ND_AUDIT=1 LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 pn "$LRF6")"; rc=$?
check "AA-F6m audit line written but no OS notifier on PATH (Darwin) ⇒ failed, never sent; exit 0" \
  "$rc:${out#*— }" "0:desktop: failed (no OS notifier on PATH); webhook: not configured"
has "AA-F6n … and the ## Progress line says the same" "$(grep 'lane park notify' "$LRF6" | tail -1)" "desktop: failed (no OS notifier on PATH);"
out="$(AA_PATH="$T/aa-nonotify-bin" AA_UNAME=Linux STUB_SW=none STUB_ND_AUDIT=1 LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 pn "$LRF6")"
has "AA-F6o Linux without notify-send ⇒ failed (no OS notifier on PATH)" "$out" "desktop: failed (no OS notifier on PATH);"
out="$(AA_UNAME=Linux STUB_SW=none STUB_ND_AUDIT=1 LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 DISPLAY= WAYLAND_DISPLAY= pn "$LRF6")"
has "AA-F6p Linux notify-send present but no display ⇒ failed (no display for notify-send) — notify-desktop.sh skips it there" \
  "$out" "desktop: failed (no display for notify-send);"
out="$(AA_UNAME=Linux STUB_SW=none STUB_ND_AUDIT=1 LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 DISPLAY=:0 pn "$LRF6")"
has "AA-F6q Linux notify-send + DISPLAY ⇒ sent" "$out" "desktop: sent;"
# AA-F6r..t Darwin with terminal-notifier but NO osascript: notify-desktop.sh uses terminal-notifier only
# when its click action is not `none` (resolved by the notify-click-target.sh beside it), else falls
# through to the osascript branch — so terminal-notifier alone counts only with a click action.
mkdir -p "$T/aa-tn-bin" "$T/aa-ndc"; cp "$T/aa-bin/osascript" "$T/aa-tn-bin/terminal-notifier"
cp "$T/aa-nd.sh" "$T/aa-ndc/notify-desktop.sh"; ln -s "$HERE/notify-click-target.sh" "$T/aa-ndc/notify-click-target.sh"
chmod +x "$T/aa-tn-bin/terminal-notifier" "$T/aa-ndc/notify-desktop.sh"
out="$(AA_PATH="$T/aa-tn-bin:$T/aa-nonotify-bin" AA_ND="$T/aa-ndc/notify-desktop.sh" LOOMWRIGHT_NOTIFY_CLICK=off \
  STUB_SW=none STUB_ND_AUDIT=1 LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 pn "$LRF6")"
has "AA-F6r Darwin terminal-notifier only, click action none (LOOMWRIGHT_NOTIFY_CLICK=off) ⇒ failed (no OS notifier on PATH), never sent" \
  "$out" "desktop: failed (no OS notifier on PATH);"
out="$(AA_PATH="$T/aa-tn-bin:$T/aa-nonotify-bin" AA_ND="$T/aa-ndc/notify-desktop.sh" LOOMWRIGHT_NOTIFY_CLICK=activate \
  STUB_SW=none STUB_ND_AUDIT=1 LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 pn "$LRF6")"
has "AA-F6s Darwin terminal-notifier only, click action set (activate) ⇒ sent" "$out" "desktop: sent;"
out="$(AA_PATH="$T/aa-tn-bin:$T/aa-nonotify-bin" LOOMWRIGHT_NOTIFY_CLICK=activate \
  STUB_SW=none STUB_ND_AUDIT=1 LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 pn "$LRF6")"
has "AA-F6t Darwin terminal-notifier only, no notify-click-target.sh beside the notifier (action none) ⇒ failed" \
  "$out" "desktop: failed (no OS notifier on PATH);"
out="$(LOOMWRIGHT_LANES_NOTIFY_DESKTOP="$T/aa-nd.sh" LOOMWRIGHT_LANES_SEND_WEBHOOK="$T/aa-sw.sh" LOOMWRIGHT_DESKTOP_NOTIFICATIONS=0 \
  bash "$HERE/automate-helpers.sh" lane-park-notify "$LRF6" 2>&1)"; rc=$?
check "AA-F6k dispatched through automate-helpers.sh" "$rc:$(printf '%s' "$out" | grep -c '^lane-park-notify: lane park notify:' | tr -d ' ')" "0:1"
sed 's/status: ready_for_release/status: awaiting_merge/; s/pause_reason: ready_for_release/pause_reason: awaiting_merge/' "$LRF6" > "$T/aa-notpark.md"
mkdir -p "$L61/.supervisor/automate"; cp "$T/aa-notpark.md" "$L61/.supervisor/automate/aa-notpark.md"
out="$(STUB_SW=configured LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 pn "$L61/.supervisor/automate/aa-notpark.md")"; rc=$?
check "AA-F6l not at the ready_for_release park ⇒ skipped: exit 0, nothing sent, no line written" \
  "$rc:$(wc -l < "$AA_ND_LOG" | tr -d ' '):$(wc -l < "$AA_SW_LOG" | tr -d ' '):$(cmp -s "$T/aa-notpark.md" "$L61/.supervisor/automate/aa-notpark.md" && echo unchanged)" "0:0:0:unchanged"

# ---- AB: a merged lane is closed out by lane-convert-ready's re-run (automate-followups/38) ----------
# lane-convert-ready on `ready_for_release` converts with NO closeout; its `awaiting_merge` re-run runs
# `closeout <run file> <item> <## Current pr> --no-trail` inside the lane, under the launch lock and
# BEFORE the pushes (evidence-gated: an OPEN PR ⇒ nothing written); a MERGED re-run stamps the
# requirement, checks the item off, reconciles ## Current to done / awaiting_go and the wave-end push
# carries all of it; a re-run after that (`done` / `awaiting_go`) retries only the pushes. The scripts
# are the REAL copy $SC (branch mode on, Z-F11); a spy dispatcher in front of it records every call.
cat > "$T/ab-gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >> "$T_ABGH"
st="${STUB_PR_STATE:-OPEN}"; ma=null; [ "$st" = MERGED ] && ma='"2026-10-10T00:00:00Z"'
case "$1 $2" in
  "auth status") exit 0 ;;
  "pr view") printf '{"state":"%s","mergedAt":%s,"headRefName":"feature/ab","headRefOid":"1111111111111111111111111111111111111111"}\n' "$st" "$ma" ;;
  *) exit 1 ;;
esac
EOF
cat > "$T/ab-spy.sh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "\$T_ABSPY"
[ "\$1" = closeout ] && echo "CC=\${CLAUDECODE-unset} PID=\${CLAUDE_PID-unset}" >> "\$T_ABENV"
[ "\$1" = closeout ] && echo "closeout HOLDER=\${LOOMWRIGHT_HOLDER_PID-unset} SELF=\$\$" >> "\$T_ABHOLD"
exec bash "$SC/automate-helpers.sh" "\$@"
EOF
chmod +x "$T/ab-gh" "$T/ab-spy.sh"; export T_ABGH="$T/ab-gh.calls" T_ABSPY="$T/ab-spy.log" T_ABENV="$T/ab-spy.env"; mkdir -p "$T/remote-ab"
# The finalize-empty half of the holder pin (AC 9): a helpers shim that records LOOMWRIGHT_HOLDER_PID and
# its own pid for finalize-empty, then execs the real helper; setup-memory.sh beside it forwards (the
# lane reads finalize-empty's mode through `dirname "$HELPERS"`). Used only where AB_HELPERS names it.
export T_ABHOLD="$T/ab-spy.holder"; mkdir -p "$T/abh"
cat > "$T/abh/automate-helpers.sh" <<EOF
#!/usr/bin/env bash
[ "\$1" = finalize-empty ] && echo "finalize-empty HOLDER=\${LOOMWRIGHT_HOLDER_PID-unset} SELF=\$\$" >> "\$T_ABHOLD"
exec bash "$SC/automate-helpers.sh" "\$@"
EOF
printf '#!/usr/bin/env bash\nexec bash "%s/setup-memory.sh" "$@"\n' "$SC" > "$T/abh/setup-memory.sh"
chmod +x "$T/abh/automate-helpers.sh" "$T/abh/setup-memory.sh"
# holder_pinned <label> — every recorded HOLDER is numeric and equals that process's own SELF pid.
holder_pinned() { awk -v l="$1" '$1 == l { n++; h = $2; s = $3; sub(/^HOLDER=/, "", h); sub(/^SELF=/, "", s); if (h !~ /^[0-9]+$/ || h != s) bad++ }
  END { print ((n > 0 && !bad) ? "pinned" : "unpinned(" n + 0 "," bad + 0 ")") }' "$T_ABHOLD" 2>/dev/null; }
ab() { REMOTE11="$T/remote-ab" LOOMWRIGHT_LANES_META_SYNC="$T/meta-f11.sh" LOOMWRIGHT_LANES_HELPERS="${AB_HELPERS:-$SC/automate-helpers.sh}" \
  LOOMWRIGHT_LANES_TRAIL="$T/ab-spy.sh" LOOMWRIGHT_GH_BIN="$T/ab-gh" bash "$S" "$@" 2>&1; }
# ab_lane <n> <item> <pr> — a launched-then-exited lane holding <item> pending (its af/37-shaped prose
# quotes the sentinel inline) and a jobs/done/ brief pointing at it.
ab_lane() {
  run lane-create "$RF5" reqs/a.md "$1" >/dev/null; ABL="$LR5/L$1"; ABRF="$ABL/.supervisor/automate/$PARENT5-L$1.md"
  LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$ABL" --owner-command "$OWN" >/dev/null; wait_gone "$ABL"
  mkdir -p "$ABL/$(dirname "$2")" "$ABL/.supervisor/jobs/done"
  printf '# ab\n\n## Status: pending\n\n## Problem\nThe old guard matched `<!-- loomwright:requirement-closeout -->` quoted in prose.\n' > "$ABL/$2"
  printf '# brief\n- **Source requirement:** %s\n\n## Outcome\n- **PR:** %s\n' "$2" "$3" > "$ABL/.supervisor/jobs/done/2026-10-10-L$1.md"
}
ab_rf() { # <runfile> <lane n> <item> <pr> <status> <pause_reason>
  printf '# Automate Run: %s-L%s\n\n## Status: paused\n\n## Source\n- backlog: lane\n\n## Run Config\n- limit: 1\n\n## Queue\n- [ ] %s\n\n## Current\n- item: %s | status: %s | pr: %s | branch: feature/ab\n- pause_reason: %s\n\n## Progress\n- 2026-10-10T00:00:00Z drain READY\n' \
    "$PARENT5" "$2" "$3" "$3" "$5" "$4" "$6" > "$1"
}
RAB=".supervisor/requirements/t/ab.md"; PRAB="https://github.com/o/r/pull/57"
ab_lane 7 "$RAB" "$PRAB"; L57="$ABL"; RFAB="$ABRF"
ab_rf "$RFAB" 7 "$RAB" "$PRAB" ready_for_release ready_for_release
: > "$T_ABSPY"; QAB="$(cksum < "$L57/$RAB")"
out="$(STUB_PR_STATE=OPEN ab lane-convert-ready "$L57")"; rc=$?
check "AB1 ready_for_release converts (exit 0) to awaiting_merge" "$rc:$(cur_line "$RFAB")" \
  "0:- item: $RAB | status: awaiting_merge | pr: $PRAB | branch: feature/ab|- pause_reason: awaiting_merge|"
check "AB1b … with NO closeout call (spy) and no done stamp" "$(grep -c '^closeout ' "$T_ABSPY" | tr -d ' '):$(cksum < "$L57/$RAB")" "0:$QAB"
SAB="$(cksum < "$RFAB")"; : > "$T_ABENV"
out="$(CLAUDECODE=1 CLAUDE_PID=$$ STUB_PR_STATE=OPEN ab lane-convert-ready "$L57")"; rc=$?
check "AB2 awaiting_merge re-run, PR still OPEN: exit 0, closeout called once with --no-trail inside the lane" \
  "$rc:$(grep -cxF "closeout $RFAB $RAB $PRAB --no-trail" "$T_ABSPY" | tr -d ' ')" "0:1"
has "AB2b … its evidence gate line echoed indented" "$out" "  closeout: skipped — pr not merged (awaiting_merge)"
check "AB2c … nothing written (requirement + run file byte-unchanged)" "$(cksum < "$L57/$RAB"):$(cksum < "$RFAB")" "$QAB:$SAB"
has "AB2d … the push still names the unmerged exclusion" "$out" "/2026-10-10-L7.md — pr not merged"
has "AB2e … and the last line names the gate leftover" "$(printf '%s\n' "$out" | tail -n1)" "; closeout leftover: gate — skipped — pr not merged (awaiting_merge)"
# AB2f the lane closeout is a FRESH run-lock acquire (no --session-id), so it runs with the host identity
# unset, as the merge watcher does — else a crashed closeout's lock would name the coordinator as holder.
check "AB2f … and that closeout ran with the host identity vars unset (coordinator had them set)" "$(cat "$T_ABENV")" "CC=unset PID=unset"
check "AB2g … and its LOOMWRIGHT_HOLDER_PID is the closeout process's own pid (the run-lock holder pin)" "$(holder_pinned closeout)" pinned
: > "$T_ABHOLD"
out="$(AB_HELPERS="$T/abh/automate-helpers.sh" STUB_PR_STATE=MERGED ab lane-convert-ready "$L57")"; rc=$?
printf '%s\n' "$out" | sed 's/^/       | /'
check "AB3 merged re-run exits 0 and its last line reads closeout complete" "$rc:$(printf '%s\n' "$out" | tail -n1 | grep -c '; closeout complete$' | tr -d ' ')" "0:1"
has "AB3b … closeout stamped the lane's requirement (a quoted sentinel is not a stamp)" "$out" "  closeout: stamped — $RAB"
has "AB3c … ran with --no-trail" "$out" "  trail-pr: skipped — --no-trail"
hasnt "AB3d … and the wave-end push no longer excludes the requirement" "$out" "excluded $RAB — pr not merged"
check "AB3e the lane requirement carries ONE sentinel-led ## Status: done" \
  "$(grep -A1 -xF '<!-- loomwright:requirement-closeout -->' "$L57/$RAB" | tr '\n' '|'):$(grep -cE '^## Status:[[:space:]]*done' "$L57/$RAB" | tr -d ' ')" \
  "<!-- loomwright:requirement-closeout -->|## Status: done|:1"
# AB3f/AB3g/AB4b — parallel-automate/21 A1: the merged re-run now also runs finalize-empty (branch mode),
# which writes `## Status: done` and `pause_reason: null`; before A1 the lane stayed done / awaiting_go.
check "AB3f the lane run file reads - [x] <item> and ## Current done (no current-set after closeout; A1 finalize ⇒ pause_reason null)" \
  "$(grep -cxF -- "- [x] $RAB" "$RFAB" | tr -d ' '):$(cur_line "$RFAB")" "1:- item: $RAB | status: done | pr: $PRAB | branch: feature/ab|- pause_reason: null|"
check "AB3g the PUSHED run file carries both" \
  "$(grep -cxF -- "- [x] $RAB" "$T/remote-ab/.supervisor/automate/$PARENT5-L7.md" 2>/dev/null | tr -d ' '):$(cur_line "$T/remote-ab/.supervisor/automate/$PARENT5-L7.md" 2>/dev/null)" \
  "1:- item: $RAB | status: done | pr: $PRAB | branch: feature/ab|- pause_reason: null|"
check "AB3h the PUSHED requirement carries the done stamp" "$(grep -cE '^## Status:[[:space:]]*done' "$T/remote-ab/$RAB" 2>/dev/null | tr -d ' ')" 1
check "AB3k the merged re-run's closeout AND its NAME=VALUE-led finalize-empty each ran with LOOMWRIGHT_HOLDER_PID = their own pid" \
  "$(holder_pinned closeout):$(holder_pinned finalize-empty)" "pinned:pinned"
ab_co="$(grep -n '^closeout ' "$T_ABSPY" | tail -n1 | cut -d: -f1)"; ab_tp="$(grep -n '^trail-pr ' "$T_ABSPY" | tail -n1 | cut -d: -f1)"
check "AB3i closeout ran BEFORE the wave-end trail push (spy order)" "$([ -n "$ab_co" ] && [ -n "$ab_tp" ] && [ "$ab_co" -lt "$ab_tp" ] && echo before)" before
check "AB3j no launch lock left behind" "$(ls -d "$P/.supervisor/automate/$PARENT5.lanes".L7.launch.lock 2>/dev/null | wc -l | tr -d ' ')" 0
SAB="$(cksum < "$RFAB")"; nco="$(grep -c '^closeout ' "$T_ABSPY" | tr -d ' ')"; : > "$META_LOG"
out="$(STUB_PR_STATE=MERGED ab lane-convert-ready "$L57")"; rc=$?
check "AB4 a re-run on a closed-out (A1: finalized) lane is NOT refused (exit 0)" "$rc" 0
has "AB4b … it names that state and retries only the pushes" "$out" "already closed out and finalized (## Status: done) — retrying the metadata push only"
check "AB4c … no second closeout, no current-set (run file byte-unchanged), the pushes ran" \
  "$(grep -c '^closeout ' "$T_ABSPY" | tr -d ' '):$(cksum < "$RFAB"):$(grep -c ' push ' "$META_LOG" | tr -d ' ')" "$nco:$SAB:2"
out="$(ab lane-status "$RF5")"; rc=$?
check "AB5 lane-status reads the closed-out lane without error" "$rc:$(printf '%s\n' "$out" | grep -c 'L7' | tr -d ' ' | sed 's/^[1-9][0-9]*$/seen/')" "0:seen"
out="$(ab lane-park-notify "$RFAB")"; rc=$?
check "AB5b lane-park-notify keeps skipping a non-ready_for_release file" "$rc:$(printf '%s' "$out" | grep -c '^lane-park-notify: skipped — ' | tr -d ' ')" "0:1"
out="$(ab lane-remove "$L57")"; rc=$?
check "AB5c lane-remove passes after the closed-out lane's push and removes it" "$rc:$([ -d "$L57" ] && echo kept || echo removed)" "0:removed"
# AB6 a closeout leftover inside the lane (its sync refused: the lane clone is on another branch) is
# echoed and named in the last line, and never changes the exit code; the stamp still lands.
RAB8=".supervisor/requirements/t/ab8.md"; PRAB8="https://github.com/o/r/pull/58"
ab_lane 8 "$RAB8" "$PRAB8"; L58="$ABL"; RFAB8="$ABRF"
git -C "$L58" checkout -q -b scratch
ab_rf "$RFAB8" 8 "$RAB8" "$PRAB8" awaiting_merge awaiting_merge
out="$(STUB_PR_STATE=MERGED ab lane-convert-ready "$L58")"; rc=$?
check "AB6 a closeout sync leftover in the lane keeps exit 0" "$rc" 0
has "AB6b … the sync skip is echoed indented" "$out" "  closeout: skipped — primary checkout is on scratch (neither main nor the PR head)"
has "AB6c … and named in the last line" "$(printf '%s\n' "$out" | tail -n1)" "; closeout leftover: sync — skipped — primary checkout is on scratch (neither main nor the PR head)"
check "AB6d … the requirement is still stamped" "$(grep -cE '^## Status:[[:space:]]*done' "$L58/$RAB8" | tr -d ' ')" 1

# AB7 an awaiting_merge re-run whose ## Current carries no pr: closeout is not run, and the last line says so.
RAB9=".supervisor/requirements/t/ab9.md"
ab_lane 9 "$RAB9" "-"; L59="$ABL"; RFAB9="$ABRF"
ab_rf "$RFAB9" 9 "$RAB9" null awaiting_merge awaiting_merge
nco="$(grep -c '^closeout ' "$T_ABSPY" | tr -d ' ')"
out="$(STUB_PR_STATE=MERGED ab lane-convert-ready "$L59")"; rc=$?
check "AB7 no ## Current pr ⇒ exit 0, no closeout call" "$rc:$(grep -c '^closeout ' "$T_ABSPY" | tr -d ' ')" "0:$nco"
has "AB7b … and the last line says closeout was not run" "$(printf '%s\n' "$out" | tail -n1)" "; closeout not run (## Current has no pr)"
# AB8 metadata mode off: the merged re-run still closes the lane out; the mode-off line gains only the summary.
RAB10=".supervisor/requirements/t/ab10.md"; PRAB10="https://github.com/o/r/pull/60"
ab_lane 10 "$RAB10" "$PRAB10"; L510="$ABL"; RFAB10="$ABRF"
ab_rf "$RFAB10" 10 "$RAB10" "$PRAB10" awaiting_merge awaiting_merge
out="$(STUB_MODE_LINE=off STUB_PR_STATE=MERGED ab lane-convert-ready "$L510")"; rc=$?
check "AB8 mode off: the merged re-run exits 0 with the mode-off line (naming the state it reads) + the closeout summary" "$rc:$(printf '%s\n' "$out" | tail -n1)" \
  "0:lane-convert-ready: L10 reads done / awaiting_go (a re-run converts nothing) (metadata mode off — no metadata branch to push); closeout complete"
check "AB8b … and the lane requirement is stamped" "$(grep -cE '^## Status:[[:space:]]*done' "$L510/$RAB10" | tr -d ' ')" 1

# ---- AC: a lane whose run wrote an Orchestrator task plan is removable with no hand push -------------
# Operator-run 2026-10-10 Phase 0.2: the plan (`.supervisor/requirements/<slug>-plan.md`, a meta-managed
# path) rode neither wave-end push, so after a "closeout complete" re-run lane-remove still refused
# `metadata not pushed (local_ahead 1)` until a hand meta-sync push. Same real scripts as AB; the stub's
# status counts EVERY managed file that differs from its fake remote, as the real status does.
ac() { REMOTE11="$T/remote-ac" LOOMWRIGHT_LANES_META_SYNC="$T/meta-f11.sh" LOOMWRIGHT_LANES_HELPERS="$SC/automate-helpers.sh" \
  LOOMWRIGHT_LANES_TRAIL="$T/ab-spy.sh" LOOMWRIGHT_GH_BIN="$T/ab-gh" bash "${AC_S:-$S}" "$@" 2>&1; }
PARENT6=automate-2026-10-10-090000; RF6="$P/.supervisor/automate/$PARENT6.md"; LR6="$T/work/primary-lanes/$PARENT6"
printf '# Automate Run: %s\n\n## Progress\n' "$PARENT6" > "$RF6"
ac_lane() { # <n> <pr> — an AB-shaped lane (own parent) at ready_for_release whose run also wrote a task plan
  local rq=".supervisor/requirements/t/ac$1.md"
  run lane-create "$RF6" reqs/a.md "$1" >/dev/null; ABL="$LR6/L$1"; ABRF="$ABL/.supervisor/automate/$PARENT6-L$1.md"
  LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$ABL" --owner-command "$OWN" >/dev/null; wait_gone "$ABL"
  mkdir -p "$ABL/.supervisor/requirements/t" "$ABL/.supervisor/jobs/done"
  printf '# ac\n\n## Status: pending\n' > "$ABL/$rq"
  printf '# brief\n- **Source requirement:** %s\n\n## Outcome\n- **PR:** %s\n' "$rq" "$2" > "$ABL/.supervisor/jobs/done/2026-10-10-ac$1.md"
  printf '# Automate Run: %s-L%s\n\n## Status: paused\n\n## Source\n- backlog: lane\n\n## Run Config\n- limit: 1\n\n## Queue\n- [ ] %s\n\n## Current\n- item: %s | status: ready_for_release | pr: %s | branch: feature/ac\n- pause_reason: ready_for_release\n\n## Progress\n- 2026-10-10T00:00:00Z drain READY\n' \
    "$PARENT6" "$1" "$rq" "$rq" "$2" > "$ABRF"
  printf '# Task Plan: ac%s\n\n## EPIC ac%s\n- [x] **ac%s-1** do it\n' "$1" "$1" "$1" > "$ABL/.supervisor/requirements/ac$1-plan.md"
}
mkdir -p "$T/remote-ac"; PAC="https://github.com/o/r/pull/61"; PLAC=".supervisor/requirements/ac1-plan.md"
ac_lane 1 "$PAC"; L511="$ABL"
printf '# claim\n\n## Status: done\n- **PR:** %s\n' "$PAC" > "$L511/.supervisor/requirements/claimed-plan.md"
out="$(STUB_PR_STATE=OPEN ac lane-convert-ready "$L511")"; rc=$?
check "AC1 wave-end conversion (PR open) exits 0 and pushes the task plan with the non-claim files" \
  "$rc:$(cmp -s "$L511/$PLAC" "$T/remote-ac/$PLAC" && echo pushed)" "0:pushed"
check "AC1b … a *-plan.md carrying a done heading is a claim: never on the exact list" \
  "$([ -e "$T/remote-ac/.supervisor/requirements/claimed-plan.md" ] && echo pushed || echo kept-local)" kept-local
rm -f "$L511/.supervisor/requirements/claimed-plan.md"
out="$(STUB_PR_STATE=MERGED ac lane-convert-ready "$L511")"; rc=$?
check "AC2 the merged re-run closes out (exit 0, closeout complete)" "$rc:$(printf '%s\n' "$out" | tail -n1 | grep -c '; closeout complete$' | tr -d ' ')" "0:1"
has "AC2b … and its last line names the state the lane now reads, not a conversion" "$(printf '%s\n' "$out" | tail -n1)" \
  "lane-convert-ready: L1 reads done / awaiting_go (a re-run converts nothing); metadata pushed to test-meta"
hasnt "AC2c … never 'converted … to awaiting_merge' on a re-run" "$(printf '%s\n' "$out" | tail -n1)" "converted L1 to awaiting_merge"
out="$(ac lane-remove "$L511")"; rc=$?
check "AC3 lane-remove then removes the lane — no hand meta-sync push" "$rc:$([ -d "$L511" ] && echo kept || echo removed)" "0:removed"
has "AC3b … reading lane-remove: removed" "$out" "lane-remove: removed L1 "
# AC4 mutation control: the same lane lifecycle with the task-plan line dropped from the exact list
# reproduces the incident — closeout complete, then lane-remove refuses on the one unpushed plan.
sed 's|"\$LN_DIR"/.supervisor/requirements/\*-plan.md ||' "$SB" > "$MUT/automate-lanes.sh"
check "AC4a mutation removed the task-plan glob from the non-claim list" "$(grep -c 'requirements/\*-plan.md' "$MUT/automate-lanes.sh" | tr -d ' ')" 0
ac_lane 2 "https://github.com/o/r/pull/62"; L512="$ABL"
AC_S="$MUT/automate-lanes.sh" STUB_PR_STATE=OPEN ac lane-convert-ready "$L512" >/dev/null
out="$(AC_S="$MUT/automate-lanes.sh" STUB_PR_STATE=MERGED ac lane-convert-ready "$L512")"
has "AC4b mutation: the merged re-run still reads closeout complete" "$(printf '%s\n' "$out" | tail -n1)" "; closeout complete"
out="$(AC_S="$MUT/automate-lanes.sh" ac lane-remove "$L512")"; rc=$?
check "AC4c mutation: lane-remove refuses on the unpushed plan (the 2026-10-10 incident)" \
  "$rc:$(printf '%s' "$out" | grep -c 'metadata not pushed (local_ahead 1)' | tr -d ' ')" "1:1"

# ---- AK: a lane whose worker filed a proposed/ requirement is removable; an unpushed path is NAMED ----
# Wave W4 (run automate-2026-10-11-182243): L2's worker filed its out-of-scope follow-up as
# `.supervisor/requirements/proposed/twin-remediation-11-…md` (## Status: proposed). It rode neither
# wave-end push (the exact list had no proposed/ entry; trail-pr carries only this run's dismissed
# drafts), so fleet-closeout printed `waiting — L2 metadata not pushed (local_ahead 1)` forever and the
# coordinator found the file by a hand list-managed diff. Same real scripts and fake remote as AC.
AKD=".supervisor/requirements/proposed/twin-remediation-11-loomwright-root-migration.md"
AKC=".supervisor/requirements/proposed/ak-claimed.md"
ak_files() { # <lane dir> — the filed draft (its body names the lane: the fake remote is shared, so two
  # lanes' identical drafts would read as already pushed), plus a done-headed one (a claim: never listed)
  printf '# twin-remediation/11 — LOOMWRIGHT_ROOT migration\n\n## Status: proposed\n\n## Problem\nfiled by the %s worker\n' "${1##*/}" > "$1/$AKD"
  printf '# claim\n\n## Status: done\n- **PR:** %s\n' "$PAC" > "$1/$AKC"
}
mkdir -p "$T/remote-ac/.supervisor/requirements/proposed"; : > "$T/remote-ac/.supervisor/requirements/proposed/pulled.md"
ac_lane 3 "https://github.com/o/r/pull/63"; L513="$ABL"; mkdir -p "$L513/.supervisor/requirements/proposed"; ak_files "$L513"
: > "$L513/.supervisor/requirements/proposed/pulled.md"   # a draft the lane only pulled (same bytes as the branch): never unpushed
out="$(STUB_PR_STATE=OPEN ac lane-convert-ready "$L513")"; rc=$?
check "AK1 wave-end conversion (PR open) exits 0 and pushes the worker-filed proposed/ draft" \
  "$rc:$(cmp -s "$L513/$AKD" "$T/remote-ac/$AKD" && echo pushed)" "0:pushed"
check "AK1b … a done-headed proposed/ file is a claim: never on the exact list" \
  "$([ -e "$T/remote-ac/$AKC" ] && echo pushed || echo kept-local)" kept-local
out="$(STUB_PR_STATE=MERGED ac lane-convert-ready "$L513")"; rc=$?
check "AK2 the merged re-run closes out (exit 0, closeout complete)" "$rc:$(printf '%s\n' "$out" | tail -n1 | grep -c '; closeout complete$' | tr -d ' ')" "0:1"
out="$(ac lane-remove "$L513")"; rc=$?
check "AK3 lane-remove refuses on the one unpushed (claim) file and NAMES it" \
  "$rc:$(printf '%s\n' "$out" | grep -cxF "lane-remove: refused — L3 — metadata not pushed (local_ahead 1) — paths: $AKC" | tr -d ' ')" "1:1"
out="$(ac fleet-closeout "$RF6")"
has "AK3b … and fleet-closeout's waiting line names the path (no hand list-managed diff)" "$out" \
  "fleet-closeout: waiting — L3 metadata not pushed (local_ahead 1) — paths: $AKC"
rm -f "$L513/$AKC"
out="$(ac lane-remove "$L513")"; rc=$?
check "AK4 with the claim gone lane-remove removes the lane — the filed draft needed no hand push" "$rc:$([ -d "$L513" ] && echo kept || echo removed)" "0:removed"
# AK5 mutation control: the proposed/ glob dropped from the non-claim list reproduces wave W4 — the
# filed draft never reaches the branch and lane-remove refuses on it (still named).
sed 's| "\$LN_DIR"/.supervisor/requirements/proposed/\*.md||' "$SB" > "$MUT/automate-lanes.sh"
check "AK5a mutation removed the proposed/ glob" "$(grep -c 'requirements/proposed/\*.md; do$' "$MUT/automate-lanes.sh" | tr -d ' ')" 0
ac_lane 4 "https://github.com/o/r/pull/64"; L514="$ABL"; mkdir -p "$L514/.supervisor/requirements/proposed"; ak_files "$L514"; rm -f "$L514/$AKC"
AC_S="$MUT/automate-lanes.sh" STUB_PR_STATE=OPEN ac lane-convert-ready "$L514" >/dev/null
AC_S="$MUT/automate-lanes.sh" STUB_PR_STATE=MERGED ac lane-convert-ready "$L514" >/dev/null
out="$(AC_S="$MUT/automate-lanes.sh" ac lane-remove "$L514")"; rc=$?
check "AK5b mutation: lane-remove refuses on the unpushed filed draft (the wave W4 incident)" \
  "$rc:$(printf '%s\n' "$out" | grep -cF "metadata not pushed (local_ahead 1) — paths: $AKD" | tr -d ' ')" "1:1"
# AK6 mutation control: without `--paths` on lane-remove's status read the refusal names nothing (the
# pre-fix line) — so AK3 / AK3b are what pin the naming.
sed 's|--root "\$LN_DIR" --paths 2>|--root "$LN_DIR" 2>|' "$SB" > "$MUT/automate-lanes.sh"
check "AK6a mutation dropped --paths from the status read" "$(grep -cF -- '--root "$LN_DIR" --paths 2>' "$MUT/automate-lanes.sh" | tr -d ' ')" 0
out="$(AC_S="$MUT/automate-lanes.sh" ac lane-remove "$L514")"; rc=$?
check "AK6b mutation: the refusal reads the bare pre-fix line, no path named" \
  "$rc:$(printf '%s\n' "$out" | grep -c 'metadata not pushed (local_ahead 1)$' | tr -d ' ')" "1:1"

# ---- AN: a lane whose Launch Pad kept a revised brief draft is removable with no hand push ------------
# Run automate-2026-10-15-163325 (L5, L9): the lane's Launch Pad kept `.supervisor/automate/<run_id>.brief-draft.md`
# (Plan Review FAIL×3 → "Refine offline"). A managed path on neither wave-end push — not the exact list,
# not a trail-pr candidate — so fleet-closeout waited on `local_ahead 1 — paths: …brief-draft.md` until
# the owner approved a hand `meta-sync push --paths-from`. Same real scripts and fake remote as AC / AK.
ac_lane 5 "https://github.com/o/r/pull/65"; L515="$ABL"
AND=".supervisor/automate/$PARENT6-L5.brief-draft.md"; ANF=".supervisor/automate/$PARENT6-L9.brief-draft.md"
printf '# Brief draft (revised after Plan Review FAIL 3/3)\n\nkept by %s\n' L5 > "$L515/$AND"
printf '# another run'"'"'s draft\n' > "$L515/$ANF"   # not this lane's run id: never on the list
: > "$META_LOG"
out="$(STUB_PR_STATE=OPEN ac lane-convert-ready "$L515")"; rc=$?
check "AN1 wave-end conversion (PR open) exits 0 and pushes the lane's brief draft" \
  "$rc:$(cmp -s "$L515/$AND" "$T/remote-ac/$AND" && echo pushed)" "0:pushed"
has "AN1b … the exact non-claim push list names the draft" "$(grep '^f11-paths:' "$META_LOG" | head -1)" " $AND "
check "AN1c … another run id's brief draft is never on the list" \
  "$([ -e "$T/remote-ac/$ANF" ] && echo pushed || echo kept-local):$(grep -c "$ANF" "$META_LOG" | tr -d ' ')" "kept-local:0"
rm -f "$L515/$ANF"
out="$(STUB_PR_STATE=MERGED ac lane-convert-ready "$L515")"; rc=$?
check "AN2 the merged re-run closes out (exit 0, closeout complete)" "$rc:$(printf '%s\n' "$out" | tail -n1 | grep -c '; closeout complete$' | tr -d ' ')" "0:1"
out="$(ac lane-remove "$L515")"; rc=$?
check "AN3 lane-remove then removes the lane — the brief draft needed no hand push" "$rc:$([ -d "$L515" ] && echo kept || echo removed)" "0:removed"
# AN4 mutation control: the brief-draft entry dropped from the exact list reproduces the incident —
# closeout complete, then lane-remove refuses and names the one unpushed draft.
sed 's| "\$LN_RUN.brief-draft.md"; do$|; do|' "$SB" > "$MUT/automate-lanes.sh"
check "AN4a mutation removed the brief-draft entry" "$(grep -c 'LN_RUN.brief-draft.md"; do$' "$MUT/automate-lanes.sh" | tr -d ' ')" 0
ac_lane 6 "https://github.com/o/r/pull/66"; L516="$ABL"
printf '# Brief draft (revised after Plan Review FAIL 3/3)\n\nkept by %s\n' L6 > "$L516/.supervisor/automate/$PARENT6-L6.brief-draft.md"
AC_S="$MUT/automate-lanes.sh" STUB_PR_STATE=OPEN ac lane-convert-ready "$L516" >/dev/null
AC_S="$MUT/automate-lanes.sh" STUB_PR_STATE=MERGED ac lane-convert-ready "$L516" >/dev/null
out="$(AC_S="$MUT/automate-lanes.sh" ac lane-remove "$L516")"; rc=$?
check "AN4b mutation: lane-remove refuses on the unpushed brief draft (the L5 / L9 incident)" \
  "$rc:$(printf '%s\n' "$out" | grep -cF "metadata not pushed (local_ahead 1) — paths: .supervisor/automate/$PARENT6-L6.brief-draft.md" | tr -d ' ')" "1:1"

# ---- AD: policy carry (B5), relay-hook policy apply (B6), no policy ⇒ unchanged (B10), digest + inbox (B7)
# lane-policy.sh is the REAL script (Subtask 1); the policies are a wave-policy file and a project policy
# file written in this suite's own temp primary. HELPERS is the logging stub (progress-append recorded).
PARENT8=automate-2026-10-10-100000; RF8="$P/.supervisor/automate/$PARENT8.md"; LR8="$T/work/primary-lanes/$PARENT8"
printf '# Automate Run: %s\n\n## Progress\n' "$PARENT8" > "$RF8"
out="$(run lane-create "$RF8" reqs/a.md 1)"; L81="$LR8/L1"
check "AD1 no project / wave policy ⇒ lane.json carries \"policy\": null (B10)" \
  "$(jq -c '[has("policy"), .policy]' "$L81/.supervisor/lane.json")" "[true,null]"
has "AD1b … and lane-create says policy=none" "$out" "policy=none"
printf '{"schema_version":1,"run_id":"%s","answers":{"AUT-QUEUE":"Process","AUT-RESUME":"Continue"},"set_at":"2026-10-10T00:00:00Z"}\n' \
  "$PARENT8" > "$P/.supervisor/automate/$PARENT8.wave-policy.json"
out="$(run lane-create "$RF8" reqs/b.md 2)"; L82="$LR8/L2"; SHA82="$(jq -r '.policy.policy_sha // empty' "$L82/.supervisor/lane.json")"
check "AD2 the owner's wave policy is carried into lane.json (answers, a sha256, its source)" \
  "$(jq -c '[.policy.answers, (.policy.policy_sha | test("^[0-9a-f]{64}$")), [.policy.sources[].kind]]' "$L82/.supervisor/lane.json")" \
  '[{"AUT-QUEUE":"Process","AUT-RESUME":"Continue"},true,["wave"]]'
check "AD2b … lane.json's other keys keep their meaning" \
  "$(jq -c '[.schema_version, .lane, .run_id, .parent_run_id, .primary, .parallel, .max_tokens]' "$L82/.supervisor/lane.json")" \
  "[1,\"L2\",\"$PARENT8-L2\",\"$PARENT8\",\"$P\",2,null]"
has "AD2c … lane-create names the carried policy" "$out" "policy=${SHA82:0:12}:2"
mkdir -p "$P/.agent"; printf '{"schema_version":1,"answers":{"AUT-QUEUE":"Stop"}}\n' > "$P/.agent/lane-policy.json"
out="$(run lane-create "$RF8" reqs/a.md 3)"
has "AD3 an unstamped project policy is reported on lane-create's stderr (never applied)" "$out" "lane-policy: project policy ignored — "
check "AD3b … the lane carries the wave policy only (Process, not the project's Stop)" \
  "$(jq -c '[.policy.answers["AUT-QUEUE"], [.policy.sources[].kind]]' "$LR8/L3/.supervisor/lane.json")" '["Process",["wave"]]'
rm -rf "$P/.agent"
QQ='[{"question":"Process the queue?","header":"AUT-QUEUE","multiSelect":false,"options":[{"label":"Process (Recommended)","description":"p"},{"label":"Stop","description":"s"}]}]'
QR='[{"question":"Resume the run?","header":"AUT-RESUME","multiSelect":false,"options":[{"label":"Continue","description":"c"},{"label":"Start new","description":"n"},{"label":"Archive","description":"a"}]}]'
QH='[{"question":"Clean up the leftover?","header":"AUT-LEFTOVER","multiSelect":false,"options":[{"label":"Clean up now","description":"c"},{"label":"Keep and continue","description":"k"},{"label":"Stop","description":"s"}]}]'
QM="$(jq -c -n --argjson a "$QQ" --argjson b "$Q2" '$a + [$b[0]]')"
DEFER="$J2_DEFER"
check "AD0 the defer reference (J2's output) is exactly one PreToolUse defer object" \
  "$(xdec "$DEFER"):$(jq -c '[length, (.[] | [.hookEventName, .permissionDecision, length])]' <<<"$DEFER")" 'defer:[1,["PreToolUse","defer",2]]'
qhook() { hook_in PreToolUse "$1" "$2" "$3"; }
ad_ans() { [ -e "$1/.supervisor/inbox/answers/$2.json" ] && echo answered || echo none; }
: > "$HELPERS_LOG"
out="$(qhook "$L82" toolu_p1 "$QQ" | bash "$S" relay-hook)"
check "AD4 an allowed coded gate with a carried policy answer ⇒ allow (no defer, no resume)" "$(xdec "$out")" allow
check "AD4b … updatedInput.answers carries the question's OWN label (marker kept)" \
  "$(hso .updatedInput.answers "$out")" '{"Process the queue?":"Process (Recommended)"}'
check "AD4c answer file: source policy, via policy, gate, the carried policy_sha, no note" \
  "$(jq -c --arg sha "$SHA82" '[.source, .via, .gate, (.policy_sha == $sha), .note, (.at | test("Z$")), .answers["Process the queue?"]]' "$L82/.supervisor/inbox/answers/toolu_p1.json")" \
  '["policy","policy","AUT-QUEUE",true,null,true,"Process (Recommended)"]'
check "AD4d … the question file is recorded as today" "$(jq -r '[.id, (.questions | length)] | map(tostring) | join(",")' "$L82/.supervisor/inbox/questions/toolu_p1.json")" "toolu_p1,1"
has "AD4e one lane ## Progress line through progress-append" "$(cat "$HELPERS_LOG")" \
  "progress-append $L82/.supervisor/automate/$PARENT8-L2.md policy answer: AUT-QUEUE → Process (Recommended) (policy_sha ${SHA82:0:12})"
has "AD4f … and the allow reason names the policy, not the owner" "$(hso .permissionDecisionReason "$out")" "answered by the stamped lane policy (gate AUT-QUEUE"
out="$(qhook "$L82" toolu_p2 "$Q2" | bash "$S" relay-hook)"
check "AD5 a question with no catalog code ⇒ exactly today's defer, no answer file" "$out:$(ad_ans "$L82" toolu_p2)" "$DEFER:none"
out="$(qhook "$L82" toolu_p3 "$QM" | bash "$S" relay-hook)"
check "AD6 a multi-question call with one human question ⇒ defer (never a partial answer)" "$out:$(ad_ans "$L82" toolu_p3)" "$DEFER:none"
out="$(qhook "$L82" toolu_p4 "$QH" | bash "$S" relay-hook)"
check "AD7 a human-only gate ⇒ defer" "$out:$(ad_ans "$L82" toolu_p4)" "$DEFER:none"
out="$(qhook "$L81" toolu_p5 "$QQ" | bash "$S" relay-hook)"
check "AD8 the same allowed gate in a lane carrying \"policy\": null ⇒ defer (B10)" "$out:$(ad_ans "$L81" toolu_p5)" "$DEFER:none"
cp "$L82/.supervisor/lane.json" "$T/ad-lane.json"
jq -c '.policy.answers["AUT-QUEUE"] = "Stop"' "$T/ad-lane.json" > "$L82/.supervisor/lane.json"
out="$(qhook "$L82" toolu_p6 "$QQ" | bash "$S" relay-hook)"
check "AD9 a carried policy edited inside the lane (sha no longer matches) ⇒ defer" "$out:$(ad_ans "$L82" toolu_p6)" "$DEFER:none"
cp "$T/ad-lane.json" "$L82/.supervisor/lane.json"
check "AD9b a lane with no lane.json policy key at all reads like null (pre-21 lane) ⇒ defer" \
  "$(jq -c 'del(.policy)' "$T/ad-lane.json" > "$L82/.supervisor/lane.json"; qhook "$L82" toolu_p7 "$QQ" | bash "$S" relay-hook):$(ad_ans "$L82" toolu_p7)" "$DEFER:none"
cp "$T/ad-lane.json" "$L82/.supervisor/lane.json"
out="$(qhook "$L82" toolu_p8 "$QR" | bash "$S" relay-hook)"
check "AD10 a second allowed gate is answered too" "$(hso '.updatedInput.answers["Resume the run?"]' "$out")" Continue
jq -c '.at = "2026-10-10T01:00:00Z"' "$L82/.supervisor/inbox/answers/toolu_p1.json" > "$T/ad.a" && mv "$T/ad.a" "$L82/.supervisor/inbox/answers/toolu_p1.json"
jq -c '.at = "2026-10-10T02:00:00Z"' "$L82/.supervisor/inbox/answers/toolu_p8.json" > "$T/ad.a" && mv "$T/ad.a" "$L82/.supervisor/inbox/answers/toolu_p8.json"
out="$(run lane-status "$RF8")"
has "AD11 lane-status: one policy digest line for the lane with policy answers (B7)" "$out" \
  "    policy: 2 answered by policy since 2026-10-10T01:00:00Z — last AUT-RESUME → Continue 2026-10-10T02:00:00Z"
hasnt "AD11b … and no 'none answered' header while a lane has one" "$out" "policy: none answered"
check "AD11c --json carries the digest" "$(run lane-status "$RF8" --json | jq -c '.lanes[] | select(.lane == "L2") | .policy | [.answered, .first_at, .last_gate, .last_label]')" \
  '[2,"2026-10-10T01:00:00Z","AUT-RESUME","Continue"]'
check "AD11d no lane with a policy answer ⇒ the header line 'policy: none answered'" "$(run lane-status "$RF" | sed -n 2p)" "policy: none answered"
# A lane holds ONE pending call: L2 asked p2–p7 unanswered, then p8, and each newly recorded question
# superseded the one before it (a policy-answered p8 is still a newer question). The multi-question call is L3's own.
check "AD12g L2's unanswered p2–p7 were each superseded by the next question it asked (records kept)" \
  "$(jq -r '"\(.id)>\(.superseded_by)"' "$L82"/.supervisor/inbox/questions/superseded/*.json | tr '\n' ' ')" \
  "toolu_p2>toolu_p3 toolu_p3>toolu_p4 toolu_p4>toolu_p6 toolu_p6>toolu_p7 toolu_p7>toolu_p8 "
check "AD12h … one lane ## Progress line per supersede" "$(grep -c "^helpers progress-append $L82/.supervisor/automate/$PARENT8-L2.md [0-9TZ:-]* question superseded: toolu_p[0-9] by toolu_p[0-9] " "$HELPERS_LOG" | tr -d ' ')" 5
out="$(qhook "$LR8/L3" toolu_p9 "$QM" | bash "$S" relay-hook)"
check "AD12i a multi-question call with one human question in L3 ⇒ defer" "$out:$(ad_ans "$LR8/L3" toolu_p9)" "$DEFER:none"
i=0; for f in "$L82"/.supervisor/inbox/questions/*.json "$L81"/.supervisor/inbox/questions/*.json "$LR8/L3"/.supervisor/inbox/questions/*.json; do
  i=$((i + 1)); case "$f" in */toolu_p5.json) at="2026-10-10T00:00:01Z" ;; *) at="2026-10-10T00:00:1${i}Z" ;; esac
  jq -c --arg at "$at" '.asked_at = $at' "$f" > "$T/ad.q" && mv "$T/ad.q" "$f"
done
out="$(run lane-status "$RF8" --inbox)"
check "AD12 --inbox: ONE list of pending human questions, oldest asked_at first" "$(printf '%s\n' "$out" | sed -n '1,3p')" \
  "lane-status: inbox — 2 pending human question call(s), oldest first
2026-10-10T00:00:01Z L1 toolu_p5 AUT-QUEUE — Process the queue?
    options: Process (Recommended) | Stop"
hasnt "AD12b … a policy-answered question is not in the inbox" "$out" "toolu_p1"
hasnt "AD12c … nor the second one" "$out" "toolu_p8"
has "AD12d … a multi-question call lists each question" "$out" "L3 toolu_p9 Color — Which color?"
check "AD12e … every pending call appears, in asked_at order" "$(printf '%s\n' "$out" | awk '/^2026/ { print $3 }' | uniq | tr '\n' ' ')" \
  "toolu_p5 toolu_p9 "
check "AD12f a lane-status --inbox with no lane table is fail-SAFE (exit 0)" "$(run lane-status "$T/none.md" --inbox >/dev/null; echo $?)" 0

# ---- AE: lane-convert-ready finalizes a closed-out lane (A1) -----------------------------------------
# The AB scripts (real closeout / finalize-empty / trail-pr, branch mode on in $SC) on lanes of a fresh
# parent. Mode on ⇒ ONE `finalize —` line, before the last, and `## Status: done` is pushed; a re-run is a
# no-op finalize; mode off ⇒ `finalize skipped — metadata mode off` and the lane stays paused.
PARENT9=automate-2026-10-10-110000; RF9="$P/.supervisor/automate/$PARENT9.md"; LR9="$T/work/primary-lanes/$PARENT9"
printf '# Automate Run: %s\n\n## Progress\n' "$PARENT9" > "$RF9"; mkdir -p "$T/remote-ae"
ae() { REMOTE11="$T/remote-ae" LOOMWRIGHT_LANES_META_SYNC="$T/meta-f11.sh" LOOMWRIGHT_LANES_HELPERS="$SC/automate-helpers.sh" \
  LOOMWRIGHT_LANES_TRAIL="$T/ab-spy.sh" LOOMWRIGHT_GH_BIN="$T/ab-gh" bash "$S" "$@" 2>&1; }
ae_lane() { # <parent_rf> <lanes_root> <n> <req> <pr> <status> [<item>] — a launched-then-exited lane at <status>
  local id="$(basename "$1" .md)-L$3"
  run lane-create "$1" "${7:-reqs/a.md}" "$3" >/dev/null; ABL="$2/L$3"; ABRF="$ABL/.supervisor/automate/$id.md"
  LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$ABL" --owner-command "$OWN" >/dev/null; wait_gone "$ABL"
  mkdir -p "$ABL/$(dirname "$4")" "$ABL/.supervisor/jobs/done"
  printf '# req\n\n## Status: pending\n' > "$ABL/$4"
  printf '# brief\n- **Source requirement:** %s\n\n## Outcome\n- **PR:** %s\n' "$4" "$5" > "$ABL/.supervisor/jobs/done/2026-10-10-$id.md"
  printf '# Automate Run: %s\n\n## Status: paused\n\n## Source\n- backlog: lane\n\n## Run Config\n- limit: 1\n\n## Queue\n- [ ] %s\n\n## Current\n- item: %s | status: %s | pr: %s | branch: feature/ae\n- pause_reason: %s\n\n## Progress\n- 2026-10-10T00:00:00Z drain READY\n' \
    "$id" "$4" "$4" "$6" "$5" "$6" > "$ABRF"
}
ae_lane "$RF9" "$LR9" 1 ".supervisor/requirements/t/ae1.md" "https://github.com/o/r/pull/91" awaiting_merge; L91="$ABL"; RF91="$ABRF"
out="$(STUB_PR_STATE=MERGED ae lane-convert-ready "$L91")"; rc=$?
check "AE1 merged re-run, branch mode on: exit 0 and ONE finalize line" "$rc:$(printf '%s\n' "$out" | grep -c '^lane-convert-ready: finalize' | tr -d ' ')" "0:1"
has "AE1b … it carries finalize-empty's own line" "$out" "lane-convert-ready: finalize — finalize-empty: finalized $RF91"
check "AE1c … printed BEFORE the last line, which still names closeout's state and the summary" \
  "$(printf '%s\n' "$out" | tail -n2 | head -1 | grep -c '^lane-convert-ready: finalize — ' | tr -d ' '):$(printf '%s\n' "$out" | tail -n1 | grep -c 'reads done / awaiting_go (a re-run converts nothing); metadata pushed to test-meta — .*; closeout complete$' | tr -d ' ')" \
  "1:1"
check "AE1d the lane run file reads ## Status: done (and an auto-finalized Progress line)" \
  "$(grep -c '^## Status: done' "$RF91" | tr -d ' '):$(grep -c 'auto-finalized: queue empty after closeout' "$RF91" | tr -d ' ')" "1:1"
check "AE1e … and the PUSHED run file is byte-identical to it (finalize ran before the pushes)" \
  "$(cmp -s "$RF91" "$T/remote-ae/.supervisor/automate/$PARENT9-L1.md" && echo same)" same
SAE="$(cksum < "$RF91")"
out="$(STUB_PR_STATE=MERGED ae lane-convert-ready "$L91")"; rc=$?
check "AE2 a re-run on the finalized lane: exit 0, finalize is a no-op, run file byte-unchanged" \
  "$rc:$(printf '%s\n' "$out" | grep -c '^lane-convert-ready: finalize — finalize-empty: skipped — not paused$' | tr -d ' '):$(cksum < "$RF91")" "0:1:$SAE"
out="$(ae lane-remove "$L91")"; rc=$?
check "AE3 the finalized lane is removable (its metadata is in sync)" "$rc:$([ -d "$L91" ] && echo kept || echo removed)" "0:removed"
ae_lane "$RF9" "$LR9" 2 ".supervisor/requirements/t/ae2.md" "https://github.com/o/r/pull/92" awaiting_merge; L92="$ABL"; RF92="$ABRF"
out="$(STUB_MODE_LINE=off STUB_PR_STATE=MERGED ae lane-convert-ready "$L92")"; rc=$?
check "AE4 mode off: the merged re-run says finalize skipped (it would open a trail PR)" \
  "$rc:$(printf '%s\n' "$out" | grep -cxF 'lane-convert-ready: finalize skipped — metadata mode off' | tr -d ' ')" "0:1"
check "AE4b … and the lane stays ## Status: paused at done / awaiting_go" "$(grep -c '^## Status: paused' "$RF92" | tr -d ' '):$(cur_line "$RF92" | sed 's/.*|- //')" "1:pause_reason: awaiting_go|"
out="$(STUB_MODE_LINE=off STUB_PR_STATE=MERGED ae lane-convert-ready "$L92")"; rc=$?
has "AE4c a mode-off re-run on done / awaiting_go names that state (the pre-A1 path, still reachable)" "$out" \
  "already closed out (## Current done / awaiting_go) — retrying the metadata push only"
check "AE4d … and skips finalize again" "$rc:$(printf '%s\n' "$out" | grep -c 'finalize skipped — metadata mode off' | tr -d ' ')" "0:1"
check "AE5 a ## Current done / null lane whose ## Status is NOT done is refused (exit 1, nothing written)" \
  "$(sed -i.bak 's/^- pause_reason: awaiting_go$/- pause_reason: null/' "$RF92"; S0="$(cksum < "$RF92")"; ae lane-convert-ready "$L92" >/dev/null; echo "$?:$([ "$(cksum < "$RF92")" = "$S0" ] && echo same)")" "1:same"
rm -f "$RF92.bak"

