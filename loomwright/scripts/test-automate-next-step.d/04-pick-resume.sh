echo "-- P. PICK / RECONCILE / resume (automate-speed/08)"
LEG_MSG=""
if leg_open_pr_park "$DRIVER"; then ok "P1 (AC2): an OPEN in-flight PR (awaiting_merge, escalated) / this run's open trail PR ⇒ --start pick parks, releases its lock, no picked line, no new ## Current item"
else no "P1: $LEG_MSG"; fi
LEG_MSG=""
if leg_reconcile_leftover "$DRIVER"; then ok "P2 (AC3): RECONCILE's closeout leftovers ⇒ AUT-LEFTOVER (4 a call, catalog labels, header \"AUT-LEFTOVER\"); cant_ask / --non-interactive ⇒ closeout_leftover park, one line per leftover, no trail-pr, no PICK"
else no "P2: $LEG_MSG"; fi
LEG_MSG=""
if leg_resume_entry "$DRIVER"; then ok "P3 (AC4): one run, no --run, can't ask ⇒ resume_requires_flag_non_interactive stop, nothing written; AUT-RESUME asked + re-printed; cant_ask / Start new write nothing; continue restores a stranded config backup"
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
