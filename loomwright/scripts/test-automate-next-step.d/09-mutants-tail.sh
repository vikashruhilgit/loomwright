if [ "${NS_SKIP_MUTANTS:-}" != 1 ]; then
  echo "-- M. mutation controls"
  # M2a — gate-eval replaced by a direct awaiting_merge park
  if m="$(build_mutant 2a 'gl="$(bash "$H" gate-eval "$PR" "$CTXF" --root "$ROOT" 2>"$errf")"; rc=$?' 'gl="PARK: skipped"; rc=0')"; then
    if golden_case gate-eval-merge "$m"; then no "M2a: gate-eval-merge stayed green with gate-eval skipped"
    else ok "M2a: gate-eval skipped (direct park) ⇒ gate-eval-merge red ($GC_MSG)"; fi
  else no "M2a: mutant not built"; fi
  # M2b — an unguarded merge-command line appended (the literal assembled from pieces here)
  if m="$(build_mutant 2b - "-append:$(printf '%s %s "$PR"' "$MC_PIECE_A" "$MC_PIECE_B")")"; then
    if leg_surface "$m"; then no "M2b: the surface leg stayed green with an unguarded merge line"
    else ok "M2b: an unguarded merge-command line ⇒ surface leg red"; fi
  else no "M2b: mutant not built"; fi
  # MI — the no-result path re-runs the last step instead of re-printing
  if m="$(build_mutant I "then ns_reprint; fi" 'then NS_STATE="$(printf '"'"'%s'"'"' "$NS_STATE" | "$JQ" -c '"'"'.failed = .last_arm'"'"')"; fi')"; then
    if leg_idem escalated-park "$m"; then no "MI: idempotency stayed green with the re-print replaced"
    else ok "MI: re-run instead of re-print ⇒ idempotency red ($LEG_MSG)"; fi
  else no "MI: mutant not built"; fi
  # MG (#616) — the write-time nested-object refusal dropped ⇒ R5b red
  if m="$(build_mutant G616 'v="$(ns_nested_error "$t")"' 'v=""')"; then
    if leg_nested_run_reports "$m"; then no "MG: R5b stayed green with the nested-object refusal dropped"
    else ok "MG: nested-object refusal dropped ⇒ R5b red ($LEG_MSG)"; fi
  else no "MG: mutant not built"; fi
  # MQ — the --non-interactive check dropped before an ask
  if m="$(build_mutant Q 'ns_interactive() { [ "$NONINT" != 1 ]; }' 'ns_interactive() { return 0; }')"; then
    if leg_cantask "$m"; then no "MQ: can't-ask stayed green with the --non-interactive check dropped"
    else ok "MQ: --non-interactive check dropped ⇒ can't-ask red ($LEG_MSG)"; fi
  else no "MQ: mutant not built"; fi
  # MC — a gate-owned key added to the ctx
  if m="$(build_mutant C 'supervisor_result_path: $sp}' 'supervisor_result_path: $sp, high_risk: false}')"; then
    if leg_ctx "$m"; then no "MC: ctx leg stayed green with high_risk in the ctx"
    else ok "MC: \"high_risk\": false in the ctx ⇒ ctx leg red ($LEG_MSG)"; fi
  else no "MC: mutant not built"; fi
  # MV* — each drain-report guard dropped ⇒ the malformed-report leg (B6) red
  mv_leg() { # <name> <anchor> <replacement>
    local m
    if m="$(build_mutant "$1" "$2" "$3")"; then
      LEG_MSG=""
      if leg_badreport "$m"; then no "M$1: the malformed-report leg stayed green with the guard dropped"
      else ok "M$1: guard dropped ⇒ malformed-report leg red ($LEG_MSG)"; fi
    else no "M$1: mutant not built"; fi
  }
  mv_leg Vdr 'ns_field_ok drain_result "$dr" ||' 'true ||'
  mv_leg Vip 'escalation_attempt|items_processed) ns_count_ok "$2" ;;' 'escalation_attempt|items_processed) true ;;'
  mv_leg Vbig 'ns_count_ok() { [[ "$1" =~ ^[0-9]{1,9}$ ]]; }' 'ns_count_ok() { [[ "$1" =~ ^[0-9]+$ ]]; }'
  mv_leg Vec 'check_pending|check_red_unrelated|check_red|findings|validation_unrun|other) return 0 ;; *) return 1 ;; esac ;;' '*) return 0 ;; esac ;;'
  mv_leg Vsha 'ready_sha|escalation_sha) [[' 'ready_sha|escalation_sha) true || [['
  mv_leg Vnote 'progress_note) case "$2" in' 'progress_note) case "x" in'
  # MQp — both post-park --non-interactive guards of the decide step dropped (the first-entry park and
  # the batch emitter; either alone keeps the ask away) ⇒ Q (c) red
  if m="$(build_mutant2 Qp 'if ! ns_interactive; then ns_emit_park decide' 'if false; then ns_emit_park decide' \
       'ns_interactive || return 1   # --non-interactive' 'true || return 1   # --non-interactive')"; then
    LEG_MSG=""
    if leg_cantask "$m"; then no "MQp: can't-ask stayed green with the post-park guards dropped"
    else ok "MQp: post-park --non-interactive guards dropped ⇒ can't-ask red ($LEG_MSG)"; fi
  else no "MQp: mutant not built"; fi
  # MR — the running-status re-entry guard dropped ⇒ B7 red
  if m="$(build_mutant R '[ "$STATUS" = running ] ||' 'true ||')"; then
    LEG_MSG=""
    if leg_reentry "$m"; then no "MR: the re-entry leg stayed green with the running-status guard dropped"
    else ok "MR: running-status guard dropped ⇒ re-entry leg red ($LEG_MSG)"; fi
  else no "MR: mutant not built"; fi
  # MB — the item/PR binding of the sidecar dropped ⇒ B9 red
  if m="$(build_mutant B 'if [ -z "${NEXT_STEP_FROM:-}" ] && ! ns_bound; then' 'if false; then')"; then
    LEG_MSG=""
    if leg_binding "$m"; then no "MB: the binding leg stayed green with the item/PR binding dropped"
    else ok "MB: item/PR binding dropped ⇒ binding leg red ($LEG_MSG)"; fi
  else no "MB: mutant not built"; fi
  # MT — terminate's fail-CLOSED comparison reverted to a bare -ge (an erroring test reads as under) ⇒ B10 red
  if m="$(build_mutant T 'if ! ns_count_ok "$p" || ! [ "$p" -lt "$lim" ] 2>/dev/null; then' 'if [ "$p" -ge "$lim" ] 2>/dev/null; then')"; then
    LEG_MSG=""
    if leg_bigcount "$m"; then no "MT: the big-count leg stayed green with the bare -ge"
    else ok "MT: bare -ge at terminate ⇒ big-count leg red ($LEG_MSG)"; fi
  else no "MT: mutant not built"; fi
  # MN — the persisted --non-interactive no longer read back ⇒ B11 red
  if m="$(build_mutant N 'elif [ "$(st flag_non_interactive)" = true ]; then NONINT=1; fi' 'fi')"; then
    LEG_MSG=""
    if leg_nonint_persist "$m"; then no "MN: the persistence leg stayed green with the flag not read back"
    else ok "MN: persisted --non-interactive not read back ⇒ persistence leg red ($LEG_MSG)"; fi
  else no "MN: mutant not built"; fi
  # MPu — ns_pending_write refuses dismissed-pending's documented `unknown` again ⇒ B12 and B13 red
  if m="$(build_mutant Pu 'ns_count_ok "$1" || [ "$1" = unknown ] ||' 'ns_count_ok "$1" ||')"; then
    LEG_MSG=""; r12=green; r13=green
    leg_unknown_park "$m" || r12=red
    leg_unknown_merge "$m" || r13=red
    if [ "$r12" = red ] && [ "$r13" = red ]; then ok "MPu: unknown refused ⇒ B12 and B13 red"
    else no "MPu: unknown refused ⇒ B12 $r12, B13 $r13"; fi
  else no "MPu: mutant not built"; fi
  # MRs — the spawn branch's replay check dropped ⇒ B14a red
  if m="$(build_mutant Rs 'if ns_same_report "$RESULT" "$(st report_key)"; then' 'if false; then')"; then
    LEG_MSG=""
    if leg_spawn_replay "$m"; then no "MRs: the spawn-replay leg stayed green with the replay check dropped"
    else ok "MRs: spawn replay check dropped ⇒ B14a red ($LEG_MSG)"; fi
  else no "MRs: mutant not built"; fi
  # MRx — the fresh-tail stale-report check dropped ⇒ B14b red
  if m="$(build_mutant Rx '  ns_stale_report "$RESULT" && ns_die2 "--result is the drain report of a tail already left behind (another item / PR; ' '  false && ns_die2 "--result is the drain report of a tail already left behind (another item / PR; ')"; then
    LEG_MSG=""
    if leg_cross_replay "$m"; then no "MRx: the cross-item replay leg stayed green with the stale check dropped"
    else ok "MRx: stale-report check dropped ⇒ B14b red ($LEG_MSG)"; fi
  else no "MRx: mutant not built"; fi
  # M7a (Validation 2a) — the config restore moved from the RUN-result step to the drain-result step ⇒ R1 red
  # (config.json still suppressed when the owned-drain spawn prints) and run-config-suppress-restore red
  if m="$(build_mutant2 7a 'ns_once once_rr_restore ns_config_restore || return 1   # the RUN-result restore: before the drain spawn' \
       ':   # restore moved to DRAIN' \
       '  ns_once once_dr_start ns_drain_start_line "$kind" "$pr" || return 1' \
       '  ns_once once_rr_restore ns_config_restore || return 1; ns_once once_dr_start ns_drain_start_line "$kind" "$pr" || return 1')"; then
    LEG_MSG=""; if golden_case run-config-suppress-restore "$m"; then m7a_gold=green; else m7a_gold=red; fi
    if leg_run_order "$m"; then no "M7a: the restore-order leg stayed green with the restore at DRAIN (parity $m7a_gold)"
    else ok "M7a: restore moved to drain-result ⇒ R1 red ($LEG_MSG); run-config-suppress-restore parity $m7a_gold"; fi
  else no "M7a: mutant not built"; fi
  # M7b (Validation 2b) — the second-drain refusal removed ⇒ R2 red
  if m="$(build_mutant 7b 'if ns_drain_owned; then' 'if false; then')"; then
    LEG_MSG=""
    if leg_drain_once "$m"; then no "M7b: the second-drain leg stayed green with the refusal removed"
    else ok "M7b: second-drain refusal removed ⇒ R2 red ($LEG_MSG)"; fi
  else no "M7b: mutant not built"; fi
  # M7c — config-suppress's non-zero exit ignored (the /autonomous spawn printed anyway) ⇒ R3 red
  if m="$(build_mutant 7c 'e="$(bash "$H" config-suppress "$CFG_PATH" "$BAK_PATH" 2>&1 >/dev/null)"; rc=$?' 'e="$(bash "$H" config-suppress "$CFG_PATH" "$BAK_PATH" 2>&1 >/dev/null)"; rc=0')"; then
    LEG_MSG=""
    if leg_config_malformed "$m"; then no "M7c: the malformed-config leg stayed green with the abort ignored"
    else ok "M7c: config-suppress exit ignored ⇒ R3 red ($LEG_MSG)"; fi
  else no "M7c: mutant not built"; fi
  # M7d — the review-heal sidecar written on the superseded path ⇒ R4 red
  if m="$(build_mutant 7d '  # NO review-heal sidecar, NO learning-emit, NO GATE / decision step: close the item out as RECONCILE does' \
       '  ns_write_text drain_text "$AD/$RUN_ID.review-heal-result.md"')"; then
    LEG_MSG=""
    if leg_superseded "$m"; then no "M7d: the superseded leg stayed green with a review-heal sidecar written"
    else ok "M7d: sidecar written on the superseded path ⇒ R4 red ($LEG_MSG)"; fi
  else no "M7d: mutant not built"; fi
  # M7e — progress-append's exit swallowed on the drain start line ⇒ drain-pinned-start-line-current-not-set red
  if m="$(build_mutant 7e 'ns_progress "$ts owned drain started$tag — /review-pr $2 --until-mergeable --no-auto-postmortem @ $h"' \
       'ns_progress "$ts owned drain started$tag — /review-pr $2 --until-mergeable --no-auto-postmortem @ $h" || true')"; then
    if golden_case drain-pinned-start-line-current-not-set "$m"; then no "M7e: the current_not_set case stayed green with the exit swallowed"
    else ok "M7e: start-line exit swallowed ⇒ drain-pinned-start-line-current-not-set red (${GC_MSG:0:160})"; fi
  else no "M7e: mutant not built"; fi
  # M7f — the reserved-prefix check of the free-text notes removed ⇒ R10 red
  if m="$(build_mutant 7f 'case "$t" in "$p"*) printf '"'"'%s'"'"' "$p"; return 0 ;; esac' ':')"; then
    LEG_MSG=""
    if leg_reserved_notes "$m"; then no "M7f: the reserved-prefix leg stayed green with the check removed"
    else ok "M7f: reserved-prefix check removed ⇒ R10 red ($LEG_MSG)"; fi
  else no "M7f: mutant not built"; fi
  # M7i — a reader prefix dropped from NS_RESERVED_PREFIXES (`parked`) ⇒ R12 red and R10 red (the forged park note)
  if m="$(build_mutant 7i - '-append:# M7i')" && awk '$0 != "parked"' "$m" > "$m.t" && mv "$m.t" "$m" \
     && [ -s "$m" ] && ! grep -qx parked "$m" && bash -n "$m"; then
    LEG_MSG=""; if leg_reserved_notes "$m"; then m7i_r10=green; else m7i_r10=red; fi
    LEG_MSG=""
    if leg_reader_prefixes "$m"; then no "M7i: the reader-prefix leg stayed green with 'parked' unreserved (R10 $m7i_r10)"
    elif [ "$m7i_r10" = red ]; then ok "M7i: 'parked' unreserved ⇒ R12 red ($LEG_MSG) and R10 red"
    else no "M7i: 'parked' unreserved ⇒ R12 red but R10 stayed green"; fi
  else no "M7i: mutant not built"; fi
  # M7j — the case fold dropped (a reader lower-cases before it matches: `Finalize:` / `PARKED`) ⇒ R10 red
  if m="$(build_mutant 7j 'ns_lc() { printf '"'"'%s'"'"' "$1" | tr '"'"'[:upper:]'"'"' '"'"'[:lower:]'"'"'; }' 'ns_lc() { printf '"'"'%s'"'"' "$1"; }')"; then
    LEG_MSG=""
    if leg_reserved_notes "$m"; then no "M7j: the reserved-prefix leg stayed green with the case fold dropped"
    else ok "M7j: case fold dropped ⇒ R10 red ($LEG_MSG)"; fi
  else no "M7j: mutant not built"; fi
  # M7k — the RUN report replay dropped (a byte-identical re-send is refused again) ⇒ R7 red
  if m="$(build_mutant 7k 'elif ns_run_replay "$RESULT"; then' 'elif false; then')"; then
    LEG_MSG=""
    if leg_run_idem "$m"; then no "M7k: the RUN-idempotency leg stayed green with the RUN replay dropped"
    else ok "M7k: RUN replay dropped ⇒ R7 red ($LEG_MSG)"; fi
  else no "M7k: mutant not built"; fi
  # M7l — the DRAIN replay at an open ask dropped (the report read as the ask's answer) ⇒ R9 red
  if m="$(build_mutant 7l 'elif [ "$pending_do" = ask ] && ns_is_drain_report "$RESULT" && [ "$(ns_report_hash "$RESULT")" = "$(st drain_report_hash)" ]; then' 'elif false; then')"; then
    LEG_MSG=""
    if leg_drain_replay "$m"; then no "M7l: the drain-replay leg stayed green with the ask replay dropped"
    else ok "M7l: DRAIN replay at the ask dropped ⇒ R9 red ($LEG_MSG)"; fi
  else no "M7l: mutant not built"; fi
  # M7g — both --start run session-id refusals removed (RUN starts with no id) ⇒ R11 red
  if m="$(build_mutant2 7g '[ -n "$SID" ] || { ns_err "session_id_missing' 'true || { ns_err "session_id_missing' \
       'ns_sid_ok "$SID" || { ns_err "session_id_malformed' 'true || { ns_err "session_id_malformed')"; then
    LEG_MSG=""
    if leg_session_id "$m"; then no "M7g: the session-id leg stayed green with the refusal removed"
    else ok "M7g: session-id refusal removed ⇒ R11 red ($LEG_MSG)"; fi
  else no "M7g: mutant not built"; fi
  # M7h — the rate-limit check's pinned skipped line removed (a skipped check reads clean again) ⇒ R11 red
  if m="$(build_mutant 7h 'if [ -n "$skip" ]; then ns_once once_rl_skip' 'if false; then ns_once once_rl_skip')"; then
    LEG_MSG=""
    if leg_session_id "$m"; then no "M7h: the session-id leg stayed green with the skipped line removed"
    else ok "M7h: pinned skipped line removed ⇒ R11 red ($LEG_MSG)"; fi
  else no "M7h: mutant not built"; fi
  # MO — ns_park reordered: the merge watcher armed only AFTER the post-park decide step (the run file is
  # byte-identical, so only the order leg can see it) ⇒ B8 red
  if m="$(build_mutant2 O '*) ns_watch; ns_notify awaiting_merge' '*) ns_notify awaiting_merge' \
       'if [ "$(st order)" = park-first ]; then NEXT=decide; return 0; fi' 'if [ "$(st order)" = park-first ]; then ns_decide; ns_watch; return 0; fi')"; then
    rec_helpers "$m"; LEG_MSG=""
    if golden_case park-first-ready-park "$m"; then mo_gold=green; else mo_gold=red; fi
    if leg_order "$m"; then no "MO: the order leg stayed green with the watcher armed after park-ask-gate"
    else ok "MO: watcher armed after the decide step ⇒ order leg red (golden run file $mo_gold: $LEG_MSG)"; fi
  else no "MO: mutant not built"; fi
fi
