echo "-- P. PICK / RECONCILE / resume (automate-speed/08)"
LEG_MSG=""
if leg_open_pr_park "$DRIVER"; then ok "P1 (AC2): an OPEN in-flight PR (awaiting_merge, escalated) / this run's open trail PR ⇒ --start pick parks, releases its lock, no picked line, no new ## Current item"
else no "P1: $LEG_MSG"; fi
LEG_MSG=""
if leg_reconcile_leftover "$DRIVER"; then ok "P2 (AC3): RECONCILE's closeout leftovers ⇒ AUT-LEFTOVER (4 a call, catalog labels, header \"AUT-LEFTOVER\"); cant_ask / --non-interactive ⇒ closeout_leftover park, one line per leftover, no trail-pr, no PICK"
else no "P2: $LEG_MSG"; fi
LEG_MSG=""
if leg_resume_entry "$DRIVER"; then ok "P3 (AC4): one run, no --run, can't ask ⇒ resume_requires_flag_non_interactive stop, nothing written; AUT-RESUME asked + re-printed (auto_answer \"Continue\"; null under auto_gates: off, two runs, a rebuilt ## Current); cant_ask / Start new write nothing; continue restores a stranded config backup"
else no "P3: $LEG_MSG"; fi
LEG_MSG=""
if m="$(build_mutant co - '-append:# co-helpers')" && leg_start_closeout_others "$m"; then ok "P4 (AC3): closeout-others at start — a run_lock_held row is recorded, never a leftover; a leftover row ⇒ the closeout_leftover park before the PICK lock"
else no "P4: ${LEG_MSG:-driver copy not built}"; fi
LEG_MSG=""
if leg_pick_order "$DRIVER"; then ok "P5: PICK's pair — current-set BEFORE the picked line (a never-set ## Current: both written, exit 0)"
else no "P5: $LEG_MSG"; fi
LEG_MSG=""
if leg_brief_repair "$DRIVER"; then ok "P6: brief-repair-merged through RECONCILE's closeout — the repairing brief-repair line passed through, the brief moved"
else no "P6: $LEG_MSG"; fi
LEG_MSG=""
if m="$(build_mutant cls - '-append:# cls-helpers')" && cls_helpers "$m" && leg_leftover_retry "$m"; then ok "P7: a crashed / silent closeout-classify on the Clean up now retry stays a leftover (re-ask, then the closeout_leftover park naming it); a silent one at RECONCILE is one leftover — never a PICK"
else no "P7: ${LEG_MSG:-driver copy not built}"; fi
LEG_MSG=""
if leg_coordinator "$DRIVER"; then ok "P8: a --parallel coordinator run (parallel: 2 / single-lane 1; also parallel:2 / a trailing comment / an extra space before parallel:) ⇒ --resume --run, Continue and --start pick print done/stopped coordinator_run, a bare start asks AUT-RESUME / stops resume_requires_flag_non_interactive, nothing written, no run lock"
else no "P8: $LEG_MSG"; fi
LEG_MSG=""
if leg_watch_note "$DRIVER"; then ok "P9: a live merge watcher of the in-flight open PR ⇒ ONE merge-watch noted line at the open-PR park (not repeated); a dead one ⇒ none"
else no "P9: $LEG_MSG"; fi
LEG_MSG=""
if leg_stops "$DRIVER"; then ok "P10: run_done (--start pick on a done run) / pick_already_started (a pending /autonomous spawn) / run_not_incomplete (--resume --run naming no run) ⇒ exit 2, the exact refusal line, nothing printed, .supervisor/ byte-unchanged, no run lock"
else no "P10: $LEG_MSG"; fi
LEG_MSG=""
if leg_resume_done "$DRIVER"; then ok "P16: --resume --run on a run that reads done (stamped by this call's --finalize, or earlier) ⇒ exit 0 done/done with run_file + closeout_others, no refusal, no PICK, no lock, no sidecar; a result sidecar named as the id ⇒ run_not_incomplete"
else no "P16: $LEG_MSG"; fi
LEG_MSG=""
if m="$(build_mutant rd-done 'if bash "$H" is-run-file "$NS_NAMED" 2>/dev/null' 'if false')" && ! leg_resume_done "$m"; then ok "P16 pin: the done branch removed ⇒ the P16 leg turns red"
else no "P16 pin: ${LEG_MSG:-mutant survived}"; fi
LEG_MSG=""
if m="$(build_mutant rd-title 'if bash "$H" is-run-file "$NS_NAMED" 2>/dev/null' 'if [ -f "$NS_NAMED" ]')" && ! leg_resume_done "$m"; then ok "P16 pin: the run-file shape check removed ⇒ the P16 leg turns red (a sidecar reads as a done run)"
else no "P16 pin (title): ${LEG_MSG:-mutant survived}"; fi
LEG_MSG=""
if leg_meta_push "$DRIVER"; then ok "P11: a non-empty meta-push-failed answer ⇒ ONE meta-push-failed: ## Progress line + the stderr report, the PICK proceeds (next: pending); no marker ⇒ nothing written"
else no "P11: $LEG_MSG"; fi
LEG_MSG=""
if leg_watch_registry "$DRIVER"; then ok "P12 (af/39e AC10/AC11/AC16): the default ns_watch launch ⇒ the watcher registers ONE merge-watch entry for its own (marker) pid with its cap, run file and stop hint; an unwritable registry changes neither the driver's exit/output nor the watcher log"
else no "P12: $LEG_MSG"; fi
LEG_MSG=""
if leg_pick_summary_autokeep "$DRIVER"; then ok "P15 (AC6/AC8a): a run's pre-auto-keep undecided summary draft ⇒ the PICK pending step records it follow-up with no question (one kept-automatically line, ledger row; not on a replay), interactive (nothing asked: the per-finding draft is followed up automatically too) and --non-interactive; a read-only ledger ⇒ it stays undecided and AUT-SUMMARY (Keep summary / Drop summary) is the fallback ask, at PICK and at the decision step"
else no "P15: $LEG_MSG"; fi
LEG_MSG=""
if m="$(build_mutant pk-autokeep 'ns_call_writer_helper dismissed-decide "$RF" "$apath" follow-up --auto' 'true')" && ! leg_pick_summary_autokeep "$m"; then ok "P15 pin: the PICK auto-keep call deleted ⇒ the P15 leg turns red"
else no "P15 pin: the mutant was not built or did not discriminate"; fi
LEG_MSG=""
if leg_resume_auto_risk "$DRIVER"; then ok "P13 (D8): the AUT-RESUME auto_answer's risk read — an open PR's docs-only diff ⇒ \"Continue\" naming it; an agents/ diff, an unreadable PR or one without a head sha ⇒ null high_risk; no PR ⇒ \"Continue\", no risk read; the driver writes no auto-* record"
else no "P13: $LEG_MSG"; fi
# leg_followup_nudge <driver> — dismissed-followups/01 AC6: the interactive PICK `pending` step relays
# followup-nudge's one line on stderr ONCE (a replayed step does not repeat it), never an ask or a park,
# the run file untouched and NEXT unchanged (reconcile: nothing of this run is undecided); --non-interactive
# and a draft younger than the threshold emit nothing. The draft is real-shape (`## Status: proposed` first)
# with a fixed mtime (python's os.utime), so its age is pinned through LOOMWRIGHT_FOLLOWUP_NOW.
leg_followup_nudge() {
  local drv="$1" mt=1767225600 p d line want
  line='automate: 1 follow-up drafts, oldest 20d — /backlog --state follow_up, then followup-bundle'
  want="next-step: $line (reported — not a block)"
  fn_case() { # <now days> — a fresh scratch with one follow-up draft and the pending-only seams
    new_scratch "$FIX/pick-current-set-then-picked" || return 1
    p="$CASE_ROOT/.supervisor/requirements/proposed"; d="$p/automate-2026-01-01-000000--01-fn--dismissed-0123abcd.md"
    mkdir -p "$p" && printf '# Dismissed finding\n\n## Status: proposed\n\n- **Decision:** follow-up\n- **Run:** automate-2026-01-01-000000\n- **PR:** https://example.invalid/pull/1\n' > "$d" \
      && python3 -c 'import os, sys; os.utime(sys.argv[1], (int(sys.argv[2]), int(sys.argv[2])))' "$d" "$mt" || return 1
    printf 'NEXT_STEP_FROM=pending\nNEXT_STEP_UNTIL=pending\nLOOMWRIGHT_FOLLOWUP_NOW=%s\nLOOMWRIGHT_FOLLOWUP_NUDGE_DAYS=14\n' "$((mt + $1 * 86400))" > "$CASE_DIR/seams.fu"
    cp "$CASE_RF" "$CASE_DIR/before.md"
  }
  fn_next() { jq -r '.next // empty' "$CASE_ROOT/.supervisor/automate/$CASE_RUN.next-step.json" 2>/dev/null; }
  fn_case 20 || { LEG_MSG="scratch"; return 1; }
  p_seamed "$CASE_DIR/seams.fu" "$drv" --session-id "$P_SID"
  [ "$NC_RC" = 0 ] && [ "$(grep -cxF -- "$want" <<<"$NC_ERR")" = 1 ] && [ -z "$NC_OUT" ] && [ "$(fn_next)" = reconcile ] \
    && cmp -s "$CASE_DIR/before.md" "$CASE_RF" \
    || { LEG_MSG="interactive: exit $NC_RC, stdout '${NC_OUT:0:80}', next=$(fn_next), stderr '${NC_ERR:0:240}'"; return 1; }
  # a replay of the same PICK step (the sidecar keeps the once-key) does not repeat the line
  printf 'NEXT_STEP_FROM=pending\nNEXT_STEP_UNTIL=pending\nLOOMWRIGHT_FOLLOWUP_NOW=%s\nLOOMWRIGHT_FOLLOWUP_NUDGE_DAYS=14\n' "$((mt + 20 * 86400))" > "$CASE_DIR/seams.fu"
  p_seamed "$CASE_DIR/seams.fu" "$drv" --session-id "$P_SID"
  [ "$NC_RC" = 0 ] && ! grep -qF -- "$line" <<<"$NC_ERR" || { LEG_MSG="replay: exit $NC_RC, the line was repeated: '${NC_ERR:0:240}'"; return 1; }
  fn_case 20 || { LEG_MSG="scratch (non-interactive)"; return 1; }
  p_seamed "$CASE_DIR/seams.fu" "$drv" --session-id "$P_SID" --non-interactive
  [ "$NC_RC" = 0 ] && ! grep -qF -- "follow-up drafts" <<<"$NC_ERR" && [ "$(fn_next)" = reconcile ] \
    || { LEG_MSG="--non-interactive: exit $NC_RC, next=$(fn_next), stderr '${NC_ERR:0:240}'"; return 1; }
  fn_case 10 || { LEG_MSG="scratch (younger)"; return 1; }
  p_seamed "$CASE_DIR/seams.fu" "$drv" --session-id "$P_SID"
  [ "$NC_RC" = 0 ] && ! grep -qF -- "follow-up drafts" <<<"$NC_ERR" && [ "$(fn_next)" = reconcile ] \
    || { LEG_MSG="younger than the threshold: exit $NC_RC, next=$(fn_next), stderr '${NC_ERR:0:240}'"; return 1; }
  return 0
}
LEG_MSG=""
if leg_followup_nudge "$DRIVER"; then ok "P14 (dismissed-followups/01 AC6): interactive PICK relays followup-nudge's line once on stderr (not on a replay), never an ask or a park, run file untouched, next: reconcile; --non-interactive / a draft younger than 14d ⇒ nothing"
else no "P14: $LEG_MSG"; fi
LEG_MSG=""
if m="$(build_mutant fu-nudge 'local fl; fl="$(bash "$H" followup-nudge --root "$ROOT" 2>/dev/null | head -n 1)"' 'local fl=""')" && ! leg_followup_nudge "$m"; then ok "P14 pin: the followup-nudge call deleted from the pending step ⇒ the P14 leg turns red"
else no "P14 pin: the mutant was not built or did not discriminate"; fi
# leg_resume_live_lock <driver> — a second session's --resume never resets a LIVE run's sidecar (observed
# 2026-11-08, run automate-2026-11-08-175120): session A holds the run's PICK lock (the real run-lock.sh, its
# holder pid this test's own, so alive) with its /autonomous spawn pending; session B's --resume — bare,
# --non-interactive and --run <id> — exits 2 with the `run_lock_held owner=automate:<run> pid=<p> — …` refusal,
# prints nothing, and leaves A's sidecar byte-unchanged (all of .supervisor/ too); A's RUN report is then still
# accepted (before the fix it was refused: "resume: answer must be Continue, Start new or Archive"). A's own
# session re-entering --resume is not refused (acquire's own re-entrancy rule)
leg_resume_live_lock() {
  local drv="$1" ad sc sf hold s0
  new_scratch "$FIX/resume-glob-finalize" || { LEG_MSG="scratch"; return 1; }
  ad="$CASE_ROOT/.supervisor/automate"; sc="$ad/$P_RUN.next-step.json"; sf="$CASE_DIR/seams.live"
  awk '/^## Status: /{ print "## Status: running"; next }
       /^- item: /{ print "- item: .supervisor/requirements/automate-followups/39a-sweep-and-janitor.md | status: running | pr: null | branch: null"; next }
       /^- pause_reason: /{ print "- pause_reason: null"; next } { print }' "$CASE_RF" > "$CASE_RF.t" && mv "$CASE_RF.t" "$CASE_RF"
  printf 'LOOMWRIGHT_HOLDER_PID=%s\n' "$$" > "$sf"
  hold="$(NS_REAL_LOCK=1 in_case "$drv" "$sf" bash "$HERE/run-lock.sh" acquire --owner "automate:$P_RUN" --session-id sess-live-a 2>&1)" \
    || { LEG_MSG="session A's PICK lock not taken: $hold"; return 1; }
  NS_REAL_LOCK=1 p_seamed "$sf" "$drv" --start run --non-interactive --session-id sess-live-a
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "spawn" and .what == "/autonomous run"' >/dev/null 2>&1 && [ -s "$sc" ] \
    || { LEG_MSG="session A: no pending /autonomous spawn: exit $NC_RC '${NC_OUT:0:160}' ${NC_ERR:0:160}"; return 1; }
  cp "$sc" "$CASE_DIR/sidecar.a"; s0="$(snapshot)"
  for b in "" "--non-interactive" "--run $P_RUN"; do
    # shellcheck disable=SC2086
    NC_OUT="$(NS_REAL_LOCK=1 in_case "$drv" "$sf" bash "$drv" --resume "$ad" $b --session-id sess-live-b 2>"$CASE_DIR/nc.err")"; NC_RC=$?
    NC_ERR="$(cat "$CASE_DIR/nc.err")"
    [ "$NC_RC" = 2 ] && [ -z "$NC_OUT" ] && grep -qF "next-step: run_lock_held owner=automate:$P_RUN pid=$$ — run $P_RUN is live in another session" <<<"$NC_ERR" \
      && cmp -s "$CASE_DIR/sidecar.a" "$sc" && [ "$s0" = "$(snapshot)" ] \
      || { LEG_MSG="session B --resume ${b:-(bare)}: exit $NC_RC '${NC_OUT:0:160}' '${NC_ERR:0:200}', A's sidecar $(cmp -s "$CASE_DIR/sidecar.a" "$sc" && echo unchanged || echo CLOBBERED)"; return 1; }
  done
  NS_REAL_LOCK=1 p_seamed "$sf" "$drv" --result "$R_NOPR"
  [ "$NC_RC" = 0 ] && ! grep -qF 'resume: answer must be' <<<"$NC_ERR" \
    || { LEG_MSG="session A's RUN report refused after B's --resume: exit $NC_RC ${NC_ERR:0:200}"; return 1; }
  hold="$(NS_REAL_LOCK=1 in_case "$drv" "$sf" bash "$HERE/run-lock.sh" acquire --owner "automate:$P_RUN" --session-id sess-live-a 2>&1)" \
    || { LEG_MSG="session A's lock not re-taken: $hold"; return 1; }
  NC_OUT="$(NS_REAL_LOCK=1 in_case "$drv" "$sf" bash "$drv" --resume "$ad" --session-id sess-live-a 2>"$CASE_DIR/nc.err")"; NC_RC=$?
  [ "$NC_RC" = 0 ] && ! grep -qF run_lock_held "$CASE_DIR/nc.err" \
    || { LEG_MSG="session A's own --resume refused: exit $NC_RC $(head -c 200 "$CASE_DIR/nc.err")"; return 1; }
  return 0
}
LEG_MSG=""
if leg_resume_live_lock "$DRIVER"; then ok "P17: a second session's --resume (bare / --non-interactive / --run) on a run whose PICK lock a running coordinator holds ⇒ exit 2 run_lock_held owner=automate:<run> pid=<p>, nothing printed, the live sidecar and .supervisor/ byte-unchanged; the coordinator's RUN report is still accepted; its own --resume is not refused"
else no "P17: $LEG_MSG"; fi
LEG_MSG=""
if m="$(build_mutant live-lock 'ns_lk="$(bash "$HERE/run-lock.sh" probe --session-id "$SID" </dev/null 2>/dev/null | head -n 1)"' 'ns_lk=run_lock_clear')" && ! leg_resume_live_lock "$m"; then ok "P17 pin: the live-lock probe removed from the --resume entry ⇒ the P17 leg turns red (B clobbers A's sidecar)"
else no "P17 pin: ${LEG_MSG:-the mutant was not built or did not discriminate}"; fi
# reconcile-status UNVERIFIED — a throttled merged-PR read reaches `## Progress`, so a resume with no
# `would stamp` lines cannot pass for a clean scan; the pass still moves on (it is advisory)
new_scratch "$FIX/resume-reconcile-status"
printf '1\tpr list *\t\n' > "$CASE_GH"
printf 'NEXT_STEP_FROM=reconcile-status\nNEXT_STEP_UNTIL=reconcile-status\n' > "$CASE_DIR/seams.rs"
in_case "$DRIVER" "$CASE_DIR/seams.rs" bash "$DRIVER" "$CASE_RF" --session-id auto-2026-10-15-040641 > "$CASE_DIR/rs.out" 2> "$CASE_DIR/rs.err"; rsrc=$?
if [ "$rsrc" = 0 ] && grep -qF -- '- reconcile-status: UNVERIFIED merged-pr-list: gh pr list failed; no merged PR was checked' "$CASE_RF" && ! grep -qF 'reconcile-status: would stamp' "$CASE_RF"; then
  ok "reconcile-status: a failed merged-PR read ⇒ an UNVERIFIED progress line and no would-stamp line, the step still completes"
else no "reconcile-status unverified line wrong: rc $rsrc, $(head -n 2 "$CASE_DIR/rs.err" | tr '\n' ' '), $(grep -n 'reconcile-status' "$CASE_RF" | tr '\n' ' ')"; fi
# A later resume of the same item reports its own rows: the once-keys guard a retry of a failed step, and
# must not outlive the step, or a different failure holding the same row position is silently dropped
printf '0\tpr list *\t<html>502</html>\n' > "$CASE_GH"
printf 'NEXT_STEP_FROM=reconcile-status\nNEXT_STEP_UNTIL=reconcile-status\n' > "$CASE_DIR/seams.rs"
in_case "$DRIVER" "$CASE_DIR/seams.rs" bash "$DRIVER" "$CASE_RF" --session-id auto-2026-10-15-040641 > "$CASE_DIR/rs2.out" 2> "$CASE_DIR/rs2.err"; rsrc=$?
if [ "$rsrc" = 0 ] && grep -qF -- '- reconcile-status: UNVERIFIED merged-pr-list: gh pr list answered unreadable JSON; no merged PR was checked' "$CASE_RF"; then
  ok "reconcile-status: a second pass reports its own different failure, not skipped by the first pass's once-key"
else no "reconcile-status second pass dropped its row: rc $rsrc, $(grep -n 'reconcile-status' "$CASE_RF" | tr '\n' ' ')"; fi

