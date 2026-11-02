if [ "${NS_SKIP_MUTANTS:-}" != 1 ]; then
  echo "-- M. mutation controls (coordinator_model pins)"
  # M10* — the coordinator_model pins (automate-speed/10, the brief's Pin mutations): each mutant must turn
  # its CM leg red
  cm_other="$(for v in $CM_VALUES; do [ "$v" = "$CM_DEFAULT" ] || { echo "$v"; break; }; done)"
  cm_mut() { # <name> <leg> <what> <anchor> <replacement>
    local m
    if m="$(build_mutant "$1" "$4" "$5")"; then
      LEG_MSG=""
      if "leg_cm_$2" "$m"; then no "M$1: CM $2 stayed green with $3"
      else ok "M$1: $3 ⇒ CM $2 red ($LEG_MSG)"; fi
    else no "M$1: mutant not built"; fi
  }
  cm_mut 10a setting "the invalid-value fallback a pass-through" \
    'ns_cm_listed "$v" && { NS_CM_CONF="$v"; return 0; }' '{ NS_CM_CONF="$v"; return 0; }'
  cm_mut 10b threshold "the valve threshold 3 ⇒ 4" 'NS_CM_FAILS=3;' 'NS_CM_FAILS=4;'
  cm_mut 10c badledger "a malformed ledger resolving the configured model" \
    'coordinator_model_ledger_malformed — $f — coordinator_model resolves session (delete the ledger to clear)"; NS_CM=session' \
    'coordinator_model_ledger_malformed — $f — coordinator_model resolves session (delete the ledger to clear)"; NS_CM="$NS_CM_CONF"'
  cm_mut 10d persist "the escalated record looked for only in the last-20 tail" \
    'elif any($l[]; .escalated == true) then "escalated"' 'elif any(($l | .[-$w:])[]; .escalated == true) then "escalated"'
  cm_mut 10e replay "the replay check dropped before the ledger append" \
    '     && [ "$(ns_report_key "$RESULT")" = "$(st report_key)" ]; then' '     && false; then'
  cm_mut 10f every "coordinator_model deleted from ns_base()" \
    'pr: (if $p == "" or $p == "null" then null else $p end), coordinator_model: $cm}' 'pr: (if $p == "" or $p == "null" then null else $p end)}'
  cm_mut 10g resume "coordinator_model deleted from the resume start_new instruction" \
    'pr: null, coordinator_model: $cm, status: "stopped"' 'pr: null, status: "stopped"'
  cm_mut 10h setting "the absent key resolving $cm_other (not the shipped $CM_DEFAULT)" \
    "NS_CM_DEFAULT=$CM_DEFAULT" "NS_CM_DEFAULT=$cm_other"
  cm_mut 10i setting "every configured value resolving session" \
    'ns_cm_listed "$v" && { NS_CM_CONF="$v"; return 0; }' 'ns_cm_listed "$v" && { NS_CM_CONF=session; return 0; }'
  cm_mut 10j threshold "the valve threshold 3 ⇒ 2" 'NS_CM_FAILS=3;' 'NS_CM_FAILS=2;'
  cm_mut 10k delete "a missing ledger resolving session" \
    '[ -e "$1" ] || { echo 0; return 0; }' '[ -e "$1" ] || { echo escalated; return 0; }'
  cm_mut 10l refusal "the ledger append dropped from ns_die2's refusal" \
    'ns_die2() { ns_valve_report false "$*"; echo' 'ns_die2() { echo'
  cm_mut 10m refusal "the ledger append dropped from a first arm's exit-2 refusal" \
    '{ ns_valve_report false "$arm: the --result was refused (exit 2)"; exit 2; }' 'exit 2'
  cm_mut 10n replay "the valve armed on every call, not only a --result report" \
    '[ "$have_result" = 1 ] && [ -z "$START" ] && NS_VALVE_ARMED=1' 'NS_VALVE_ARMED=1'
  cm_mut 10o stalelock "the stale-lock break dropped" \
    '    ns_cm_stale "$lk" && ns_cm_break "$lk" && continue' '    :'
  cm_mut 10p stalelock "a live holder's lock read as stale" \
    'e="$(kill -0 "$p" 2>&1)" || case "$e" in *ermitted*) ;; *) return 0 ;; esac' 'return 0'
  cm_mut 10q refusal "the bad---root refusal left armed" \
    '{ NS_VALVE_ARMED=0; ns_die2 "--root is not a directory: $ROOT"; }' 'ns_die2 "--root is not a directory: $ROOT"'
fi
