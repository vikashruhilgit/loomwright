if [ "${NS_SKIP_MUTANTS:-}" != 1 ]; then
  echo "-- M. mutation controls (PICK / resume and fresh phases)"
  # M8a (Validation 2 of automate-speed/08) — the open-PR park skipped: PICK falls through to current-set + picked ⇒ P1 red
  if m="$(build_mutant 8a '  ns_open_pr_park   # §8: an open PR blocks PICK' '  ns_after_reconcile; return 0   # M8a')"; then
    LEG_MSG=""
    if leg_open_pr_park "$m"; then no "M8a: the open-PR leg stayed green with the open-PR park skipped"
    else ok "M8a: open-PR park skipped (current-set + picked reached) ⇒ P1 red ($LEG_MSG)"; fi
  else no "M8a: mutant not built"; fi
  # M8b — the trail-gate park skipped (an open trail PR no longer parks) ⇒ P1 red
  if m="$(build_mutant 8b 'ns_run_park trail-gate trail_pr_open "" 1' 'NEXT=trail-unstage; return 0; ns_run_park trail-gate trail_pr_open "" 1')"; then
    LEG_MSG=""
    if leg_open_pr_park "$m"; then no "M8b: the open-PR leg stayed green with the trail-gate park skipped"
    else ok "M8b: trail-gate park skipped ⇒ P1 red ($LEG_MSG)"; fi
  else no "M8b: mutant not built"; fi
  # M8c — any closeout-classify answer read as complete ⇒ P2 red
  if m="$(build_mutant 8c 'ns_classify_complete() { [ "$1" = complete ]; }' 'ns_classify_complete() { return 0; }')"; then
    LEG_MSG=""
    if leg_reconcile_leftover "$m"; then no "M8c: the leftover leg stayed green with every answer read as complete"
    else ok "M8c: every closeout-classify answer read as complete ⇒ P2 red ($LEG_MSG)"; fi
  else no "M8c: mutant not built"; fi
  # M8d — the can't-ask resume auto-picks Continue ⇒ P3 red
  if m="$(build_mutant 8d '  ns_resume_stop   # one run, no --run, can not ask: fail closed, never auto-continued' '  NEXT=rebuild; return 0   # M8d')"; then
    LEG_MSG=""
    if leg_resume_entry "$m"; then no "M8d: the resume leg stayed green with Continue auto-picked"
    else ok "M8d: Continue auto-picked when the run cannot ask ⇒ P3 red ($LEG_MSG)"; fi
  else no "M8d: mutant not built"; fi
  # M8e — the picked line written BEFORE current-set (exit 3 current_not_set must surface) ⇒ P5 red
  if m="$(build_mutant 8e 'ns_once once_pk_current ns_call_writer current-set' 'ns_once once_pk_line ns_progress "$(ns_ts) picked $it" || return 1; ns_once once_pk_current ns_call_writer current-set')"; then
    LEG_MSG=""
    if leg_pick_order "$m"; then no "M8e: the PICK-order leg stayed green with the writes swapped"
    else ok "M8e: picked before current-set ⇒ P5 red ($LEG_MSG)"; fi
  else no "M8e: mutant not built"; fi
  # M8f — the Clean up now retry's classify guard dropped (a crashed classify reads as cleaned) ⇒ P7 red
  if m="$(build_mutant 8f 'cls="$(ns_classify_or_leftover "$crc" "$cls" "$r" "$it" "$p")"' ':')"; then
    cls_helpers "$m"; LEG_MSG=""
    if leg_leftover_retry "$m"; then no "M8f: the leftover-retry leg stayed green with the classify guard dropped"
    else ok "M8f: retry classify guard dropped ⇒ P7 red ($LEG_MSG)"; fi
  else no "M8f: mutant not built"; fi
  # M8g — the coordinator-run detection dropped (a --parallel run is picked in the primary) ⇒ P8 red
  if m="$(build_mutant 8g 'ns_parallel() { ns_section' 'ns_parallel() { return 0; ns_section')"; then
    LEG_MSG=""
    if leg_coordinator "$m"; then no "M8g: the coordinator leg stayed green with the parallel line ignored"
    else ok "M8g: coordinator detection dropped ⇒ P8 red ($LEG_MSG)"; fi
  else no "M8g: mutant not built"; fi
  # M8h — the live merge-watcher note dropped at the open-PR park ⇒ P9 red
  if m="$(build_mutant 8h '  ns_watch_note || return 1' '  :')"; then
    LEG_MSG=""
    if leg_watch_note "$m"; then no "M8h: the watch-note leg stayed green with the note dropped"
    else ok "M8h: merge-watch note dropped ⇒ P9 red ($LEG_MSG)"; fi
  else no "M8h: mutant not built"; fi
  # M8i — the run_done refusal dropped (a done run is picked: the PICK lock is acquired) ⇒ P10 red
  if m="$(build_mutant 8i '[ "$(ns_run_status)" != done ] || { ns_err "run_done' 'true || { ns_err "run_done')"; then
    LEG_MSG=""
    if leg_stops "$m"; then no "M8i: the stop leg stayed green with the run_done refusal dropped"
    else ok "M8i: run_done refusal dropped ⇒ P10 red ($LEG_MSG)"; fi
  else no "M8i: mutant not built"; fi
  # M8j — the meta-push-failed report's ## Progress line dropped (only the stderr report left) ⇒ P11 red
  if m="$(build_mutant 8j 'ns_once once_pk_meta ns_progress "$(ns_ts) meta-push-failed: $l" || return 1' ':')"; then
    LEG_MSG=""
    if leg_meta_push "$m"; then no "M8j: the meta-push leg stayed green with the report line dropped"
    else ok "M8j: meta-push-failed report line dropped ⇒ P11 red ($LEG_MSG)"; fi
  else no "M8j: mutant not built"; fi
  # M8k — automate-merge-watch.sh's one registration call line deleted ⇒ P12 red (af/39e AC16)
  if m="$(mw_mutant 8k)"; then
    LEG_MSG=""
    if leg_watch_registry "$m"; then no "M8k: the watcher-registry leg stayed green with the registration line deleted"
    else ok "M8k: merge-watch registration line deleted ⇒ P12 red ($LEG_MSG)"; fi
  else no "M8k: mutant not built"; fi
  # M9a — the phase-check answer test flipped (an `unavailable` answer proceeds to PICK) ⇒ F2 red
  if m="$(build_mutant 9a '  if [ "$l" = "phase-check: ok" ]; then' '  if [ "$l" != "phase-check: ok" ]; then')"; then
    LEG_MSG=""
    if leg_fresh_unavailable "$m"; then no "M9a: F2 stayed green with an unavailable phase-check proceeding"
    else ok "M9a: phase-check unavailable proceeds ⇒ F2 red ($LEG_MSG)"; fi
  else no "M9a: mutant not built"; fi
  # M9b — --inline-phases parsed as off (every call runs fresh phases) ⇒ R1 (an inline-parity leg) red
  if m="$(build_mutant 9b '    --inline-phases) INLINE=1; shift ;;' '    --inline-phases) INLINE=0; shift ;;')"; then
    LEG_MSG=""
    if leg_run_order "$m"; then no "M9b: R1 stayed green with --inline-phases ignored"
    else ok "M9b: --inline-phases ignored ⇒ R1 red ($LEG_MSG)"; fi
  else no "M9b: mutant not built"; fi
  # M9c — the Supervisor phase spawn marked "session":"inline" ⇒ F1 red
  if m="$(build_mutant 9c '{what: "/autonomous run", session: "fresh"' '{what: "/autonomous run", session: "inline"')"; then
    LEG_MSG=""
    if leg_fresh_walk "$m"; then no "M9c: F1 stayed green with the Supervisor spawn not fresh"
    else ok "M9c: the Supervisor spawn not fresh ⇒ F1 red ($LEG_MSG)"; fi
  else no "M9c: mutant not built"; fi
  # M9d — a discarded LAUNCH_PAD_RESULT taken down the saved branch ⇒ F3 red
  if m="$(build_mutant 9d '        saved) if [ -n "$path" ]' '        saved|discarded) if [ -n "$path" ]')"; then
    LEG_MSG=""
    if leg_fresh_plan_mapping "$m"; then no "M9d: F3 stayed green with discarded mapped to saved"
    else ok "M9d: discarded mapped to the saved branch ⇒ F3 red ($LEG_MSG)"; fi
  else no "M9d: mutant not built"; fi
  # M9e — the re-pick ignores the checkpoint (PICK always plans first under fresh phases) ⇒ F4 red
  if m="$(build_mutant 9e '  if ns_fresh && [ -z "$(ns_checkpoint_task)" ]; then NEXT=plan;' '  if ns_fresh; then NEXT=plan;')"; then
    LEG_MSG=""
    if leg_fresh_checkpoint "$m"; then no "M9e: F4 stayed green with the re-pick planning a checkpointed item afresh"
    else ok "M9e: a checkpointed item re-picked into a fresh Launch Pad ⇒ F4 red ($LEG_MSG)"; fi
  else no "M9e: mutant not built"; fi
  # M9f — the in-progress brief check dropped (a checkpoint line alone resumes) ⇒ F4 red
  if m="$(build_mutant 9f '  [ -f "$ROOT/.supervisor/jobs/in-progress/$t.md" ] || return 0' '  :')"; then
    LEG_MSG=""
    if leg_fresh_checkpoint "$m"; then no "M9f: F4 stayed green with the in-progress brief check dropped"
    else ok "M9f: the in-progress brief check dropped ⇒ F4 red ($LEG_MSG)"; fi
  else no "M9f: mutant not built"; fi
  # M9g — the inline resume spawns the pre-fix /autonomous (a fresh Launch Pad) ⇒ F4i red
  if m="$(build_mutant 9g '    inv="/loomwright:supervisor --continue task: $cont"' '    inv="/autonomous --single-iteration --requirement $ITEM"')"; then
    LEG_MSG=""
    if leg_inline_checkpoint "$m"; then no "M9g: F4i stayed green with the inline resume re-running /autonomous"
    else ok "M9g: the inline resume re-runs /autonomous ⇒ F4i red ($LEG_MSG)"; fi
  else no "M9g: mutant not built"; fi
  # M9h — the no-PR line no longer takes the task from the SUPERVISOR_RESULT's task_id ⇒ F4i red
  if m="$(build_mutant 9h '*) why="$why; resume with /supervisor --continue task: $tid" ;;' '*) ;;')"; then
    LEG_MSG=""
    if leg_inline_checkpoint "$m"; then no "M9h: F4i stayed green with the task_id hint dropped"
    else ok "M9h: the task_id hint dropped ⇒ F4i red ($LEG_MSG)"; fi
  else no "M9h: mutant not built"; fi
  # M9i — the checkpoint read keys on `checkpoint` only (inline's `supervisor_checkpoint` line ignored) ⇒ F4i red
  if m="$(build_mutant 9i 'index(last, "ran /autonomous — no PR: supervisor_checkpoint (") != 1)) exit' '1)) exit')"; then
    LEG_MSG=""
    if leg_inline_checkpoint "$m"; then no "M9i: F4i stayed green with the supervisor_checkpoint line ignored"
    else ok "M9i: the supervisor_checkpoint line ignored ⇒ F4i red ($LEG_MSG)"; fi
  else no "M9i: mutant not built"; fi
fi
