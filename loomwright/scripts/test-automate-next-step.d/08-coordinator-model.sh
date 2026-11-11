echo "-- CM. coordinator_model setting + escalate-on-failure valve (automate-speed/10)"
for cm_leg in setting every resume threshold persist badledger delete refusal stalelock replay; do
  LEG_MSG=""
  case "$cm_leg" in
    setting) d_="absent ⇒ the default ($CM_DEFAULT); each listed value ⇒ itself; invalid ⇒ session + ONE coordinator_model_invalid line, exit 0" ;;
    every) d_="every spawn / ask / park / done instruction carries a listed coordinator_model" ;;
    resume) d_="the --resume no-incomplete-run start_new carries it, from the automate dir's checkout (not --root)" ;;
    threshold) d_="2 FAILs/20 ⇒ no escalation; FAILs outside the window do not count; 3/20 ⇒ ONE escalated record, then session" ;;
    persist) d_="an escalated record + 25 later ok lines ⇒ still session" ;;
    badledger) d_="a malformed / capped ledger ⇒ session + a named line; nothing appended over the cap" ;;
    delete) d_="the owner deletes the ledger ⇒ the configured value resolves again" ;;
    refusal) d_="a refusal appends exactly ONE ok:false line, nothing else under .supervisor/ changes; usage errors (a bad --root included) append nothing" ;;
    stalelock) d_="a dead-pid / aged ledger lock is broken (the 3rd FAIL still escalates, no lock left); a live holder's lock is never broken" ;;
    replay) d_="a byte-identical replayed report, a no-result re-print and a no-result --start pick append nothing" ;;
  esac
  if "leg_cm_$cm_leg" "$DRIVER"; then ok "CM $cm_leg: $d_"; else no "CM $cm_leg: $LEG_MSG"; fi
done

# the invalid-value message names exactly NS_CM_VALUES (derived from it, never a hand copy)
cm_join="$(sed -n "/^NS_CM_VALUES='/,/'\$/p" "$DRIVER" | sed "s/^NS_CM_VALUES='//; s/'\$//" | awk 'NR > 1 { printf " | " } { printf "%s", $0 }')"
cm_run "$DRIVER" escalated-park '{"coordinator_model":"gpt-9"}' - "$ESC_CALL"$'\nexpect: park'
if [ -n "$cm_join" ] && cm_last_err | grep -qF "is not $cm_join — coordinator_model resolves session" \
   && grep 'coordinator_model_invalid — .* is not ' "$DRIVER" | grep -q 'NS_CM_VALUES'; then
  ok "CM message: coordinator_model_invalid lists NS_CM_VALUES ($cm_join), built from it"
else no "CM message: '$(cm_last_err | grep coordinator_model_invalid | head -n 1)' vs NS_CM_VALUES '$cm_join'"; fi

echo "-- E. the coordinator-model eval suite, model-free (automate-speed/10)"
# its reference coordinator must score every A/B case PASS and the mutation control FAIL, and its graders
# must notice a wrong question / a skipped instruction / a hand edit — so a red case under a model is the model
ESELF="$REPO/loomwright/evals/coordinator-model/lib/selftest.sh"
if [ -f "$ESELF" ]; then
  eout="$(HOME="$WORK/eself-home" bash "$ESELF" 2>&1)"; erc=$?
  etally="$(printf '%s\n' "$eout" | tail -n 1)"
  if [ "$erc" -eq 0 ]; then ok "E: lib/selftest.sh — $etally"
  else no "E: lib/selftest.sh — $etally"; printf '%s\n' "$eout" | grep '^FAIL' | sed 's/^/    /'; fi
else no "E: $ESELF missing"; fi
