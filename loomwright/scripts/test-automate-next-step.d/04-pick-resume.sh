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
if leg_stops "$DRIVER"; then ok "P10: run_done (--start pick on a done run) / pick_already_started (a pending /autonomous spawn) / run_not_incomplete (--resume --run naming no incomplete run) ⇒ exit 2, the exact refusal line, nothing printed, .supervisor/ byte-unchanged, no run lock"
else no "P10: $LEG_MSG"; fi
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

