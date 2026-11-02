echo "-- F. fresh phase sessions (automate-speed/09): the default, without --inline-phases"
LEG_MSG=""
if leg_fresh_walk "$DRIVER"; then ok "F1 (AC1): PICK (phase-check ok) → three fresh spawns — launch-pad, supervisor, drain, in that order — each a runnable phase-launch line (BLOCKED, exit 3, without an owner command); ONE session_id <sid> (<item>) phase=<phase> line per phase, three distinct ids (the Supervisor one from state.md), plus ONE session_id coord-1 (<item>) phase=driver line for the coordinator itself (the --inline-phases goldens write none)"
else no "F1: $LEG_MSG"; fi
LEG_MSG=""
if leg_fresh_unavailable "$DRIVER"; then ok "F2 (AC3): phase-check unavailable (no --permission-prompt-tool) / a session id phase-launch cannot carry ⇒ the phase_relay_unavailable park at phase-guard: no picked line, no current-set, no spawn, no RECONCILE, the run lock released"
else no "F2: $LEG_MSG"; fi
LEG_MSG=""
if leg_fresh_plan_mapping "$DRIVER"; then ok "F3 (AC7): LAUNCH_PAD_RESULT discarded / blocked / aborted / *_non_interactive / malformed / rubric dropped / a died phase ⇒ the no-PR line with /autonomous PLAN step 4's status_reason, no Supervisor spawn, no suppress; saved (and a malformed block or a died phase + ONE new brief) ⇒ the Supervisor phase spawn; a died phase + two new briefs ⇒ concurrent_session_detected"
else no "F3: $LEG_MSG"; fi
if leg_fresh_state_stale "$DRIVER"; then ok "F3b (review fixes): a stale .supervisor/state.md (older than the Supervisor phase spawn) + phase_died ⇒ the REPORTED session id on the phase=supervisor line (none reported ⇒ no line); a state.md naming the coordinator is not the phase's; an open PR on a FRESH state.md's branch is named on the no-PR line, a stale one's never — nor one the run file already records (exact URL, never a prefix), nor on a gh failure; GNU and BSD stat both read the mtime, garbage fails closed"
else no "F3b: $LEG_MSG"; fi
if leg_fresh_owner_session "$DRIVER"; then ok "F3c (review fixes): a re-printed fresh launch line is rebuilt from the re-printing session's identity — coord-1's re-print byte for byte; coord-2's re-print, the bare re-print after it and the bare --result's Supervisor spawn carry --coordinator-session coord-2 and no owner command (or coord-2's own when it gave one); coord-1 and coord-2 each get ONE phase=driver line, the re-prints none"
else no "F3c: $LEG_MSG"; fi
if leg_fresh_checkpoint "$DRIVER"; then ok "F4 (wave 7, L23): a re-pick (--start pick) / --start run of an item whose last RUN checkpointed, its brief still in .supervisor/jobs/in-progress/ ⇒ the Supervisor phase spawn /loomwright:supervisor --continue task: <id> (the line's id, else the brief saved before it), no Launch Pad spawn; no in-progress brief ⇒ the Launch Pad spawn; a newer saved brief after the checkpoint ⇒ that brief"
else no "F4: $LEG_MSG"; fi
if leg_inline_checkpoint "$DRIVER"; then ok "F4i (--inline-phases): an inline checkpoint RUN report (supervisor_checkpoint, its SUPERVISOR_RESULT's task_id) writes the no-PR line with --continue task: <id>; the re-pick / --start run with the brief in .supervisor/jobs/in-progress/ ⇒ the inline /loomwright:supervisor --continue task: <id> spawn (--non-interactive / --cheap / --max-tokens forwarded, --notify dropped), then asking for the SUPERVISOR_RESULT; no in-progress brief ⇒ the /autonomous spawn"
else no "F4i: $LEG_MSG"; fi
if leg_lane_cheap "$DRIVER"; then ok "F4j (lanes): inside a lane, lane.json \"cheap\": true puts --cheap on the RUN spawn with no --cheap given; a lane.json without it, or no lane.json (a sequential run), gets none"
else no "F4j (lanes): lane.json cheap ⇒ --cheap on the RUN spawn — $LEG_MSG"; fi
