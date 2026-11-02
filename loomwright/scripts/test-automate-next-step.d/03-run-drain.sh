echo "-- R. RUN and DRAIN (automate-speed/07)"
LEG_MSG=""
if leg_run_order "$DRIVER"; then ok "R1 (AC5): suppressed before the /autonomous spawn; restored byte-for-byte (backup deleted, original read backup-first) before the owned-drain spawn"
else no "R1 (AC5): $LEG_MSG"; fi
LEG_MSG=""
if leg_drain_once "$DRIVER"; then ok "R2 (AC2): another owned-drain spawn for the pass ⇒ exit 2 drain_already_owned, nothing written (pending, after the report, sidecar gone)"
else no "R2 (AC2): $LEG_MSG"; fi
LEG_MSG=""
if leg_config_malformed "$DRIVER"; then ok "R3 (AC3): malformed config.json ⇒ exit 2 config_malformed before the spawn; config.json byte-unchanged, no backup, no line"
else no "R3 (AC3): $LEG_MSG"; fi
LEG_MSG=""
if leg_superseded "$DRIVER"; then ok "R4 (AC4): superseded_by_merge ⇒ byte-identical, no review-heal sidecar, no ledger line, awaiting_go park; an OPEN PR ⇒ nothing written"
else no "R4 (AC4): $LEG_MSG"; fi
LEG_MSG=""
if leg_bad_run_reports "$DRIVER"; then ok "R5: $(grep -c . <<<"$BAD_RUN") malformed RUN reports ⇒ exit 2, nothing written; a no-PR report ⇒ the pinned no-PR line, done/stopped, lock released"
else no "R5: $LEG_MSG"; fi
LEG_MSG=""
if leg_nested_run_reports "$DRIVER"; then ok "R5b (#616): $(grep -c . <<<"$NESTED_RUN") RUN reports with a nested object off its schema shape ⇒ exit 2 naming the key, nothing written; the GROUND_TRUTH_NESTED shape ⇒ accepted"
else no "R5b (#616): $LEG_MSG"; fi
LEG_MSG=""
if leg_bad_drain_reports "$DRIVER"; then ok "R6: $(grep -c . <<<"$BAD_DRAIN") malformed DRAIN reports (and a bare drain report) at the owned-drain spawn ⇒ exit 2, nothing written"
else no "R6: $LEG_MSG"; fi
LEG_MSG=""
if leg_run_idem "$DRIVER"; then ok "R7: the /autonomous and owned-drain spawns re-print, write nothing; the RUN report re-sent at the drain spawn / the no-PR done ⇒ re-print; a different one, or after the DRAIN report ⇒ exit 2; --start run at the drain spawn ⇒ exit 2"
else no "R7: $LEG_MSG"; fi
LEG_MSG=""
if leg_rate_hint "$DRIVER"; then ok "R8: unknown + a 429 STOP_FAILURE hint ⇒ rate_limit park with a separate reason_hint line; a row older than picked ⇒ no park"
else no "R8: $LEG_MSG"; fi
LEG_MSG=""
if leg_drain_replay "$DRIVER"; then ok "R9: the first DRAIN report re-sent at its tail's ask ⇒ the ask re-prints; re-sent at the fix-now spawn ⇒ the spawn re-prints, nothing written; the re-drain's own report proceeds"
else no "R9: $LEG_MSG"; fi
LEG_MSG=""
if leg_reserved_notes "$DRIVER"; then ok "R10: $(grep -c . <<<"$RESERVED_NOTES") reserved-prefix notes (progress_notes[] / progress_note) at the gate entry and the owned-drain spawn ⇒ exit 2 reserved_prefix, nothing written; mid-line ⇒ a note; still ONE owned drain"
else no "R10: $LEG_MSG"; fi
LEG_MSG=""
LEG_MSG=""
if leg_reader_prefixes "$DRIVER"; then ok "R12: all $RP_N ^-anchored ## Progress prefixes of the readers (phase-timing / read-token-ledger / /lanes cls / runfile / readiness / park-leaks) are reserved or a named exception; the doc names every reserved prefix"
else no "R12: $LEG_MSG"; fi
LEG_MSG=""
if leg_session_id "$DRIVER"; then ok "R11: --start run without / with a malformed --session-id ⇒ exit 2, nothing written; the loop's log parks rate_limit; no session id / no log at the check ⇒ ONE pinned skipped line"
else no "R11: $LEG_MSG"; fi
