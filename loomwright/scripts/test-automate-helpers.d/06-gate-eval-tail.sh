# --- Condition 5 with NO required context (a 404, GitHub's paid-plan 403, or reviews-only
# protection): never vacuously green — the gate reads the whole statusCheckRollup. A failing,
# pending or in-progress check parks checks_not_green; all success / neutral / skipped, or an
# empty rollup, holds. ---
e6_rollup() { printf '{"headRefOid":"%s","baseRefName":"main","statusCheckRollup":%s}\n' "$E_PR_HEAD" "$1" > "$GH_STUB_DIR/pr-view.json"; }
E6_RED='[{"__typename":"CheckRun","name":"ci","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"CheckRun","name":"claude-review","status":"COMPLETED","conclusion":"FAILURE"}]'
printf '%s\n' "$E_PAID_403" > "$GH_STUB_DIR/protection-error"; e6_rollup "$E6_RED"
gate "$(pass_ctx | jq '.trust_unprotected=true')"
if [ "$RUN_OUT" = "PARK: checks_not_green" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: paid-plan 403 (no required list) + --trust-unprotected + one FAILURE in the rollup ⇒ PARK: checks_not_green, no merge"
else
  no "gate paid-plan-403 empty-required + failing check FAILED OPEN (out='$RUN_OUT' merges=$(merges))"
fi
reset_live
touch "$GH_STUB_DIR/protection-404"; e6_rollup "$E6_RED"
gate "$(pass_ctx | jq '.trust_unprotected=true')"
if [ "$RUN_OUT" = "PARK: checks_not_green" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: 404 (no required list) + --trust-unprotected + one FAILURE in the rollup ⇒ PARK: checks_not_green, no merge"
else
  no "gate 404 empty-required + failing check FAILED OPEN (out='$RUN_OUT' merges=$(merges))"
fi
reset_live
for E6_PEND in '[{"__typename":"CheckRun","name":"ci","status":"IN_PROGRESS","conclusion":""}]' \
               '[{"__typename":"StatusContext","context":"ci/legacy","state":"PENDING"}]'; do
  printf '%s\n' "$E_PAID_403" > "$GH_STUB_DIR/protection-error"; e6_rollup "$E6_PEND"
  gate "$(pass_ctx | jq '.trust_unprotected=true')"
  if [ "$RUN_OUT" = "PARK: checks_not_green" ] && [ "$(merges)" -eq 0 ]; then
    ok "gate fail-closed: no required list + a check not finished ($E6_PEND) ⇒ PARK: checks_not_green, no merge"
  else
    no "gate empty-required + unfinished check FAILED OPEN ($E6_PEND; out='$RUN_OUT' merges=$(merges))"
  fi
  reset_live
done
printf '%s\n' "$E_PAID_403" > "$GH_STUB_DIR/protection-error"
e6_rollup '[{"__typename":"CheckRun","name":"ci","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"CheckRun","name":"lint","status":"COMPLETED","conclusion":"NEUTRAL"},{"__typename":"CheckRun","name":"deploy","status":"COMPLETED","conclusion":"SKIPPED"},{"__typename":"StatusContext","context":"ci/legacy","state":"SUCCESS"}]'
gate "$(pass_ctx | jq '.trust_unprotected=true')"
if [ "$RUN_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ]; then
  ok "gate: no required list + every rollup check SUCCESS / NEUTRAL / SKIPPED ⇒ condition 5 holds ⇒ MERGE"
else
  no "gate empty-required all-green rollup wrong (out='$RUN_OUT' merges=$(merges))"
fi
reset_live
printf '%s\n' "$E_PAID_403" > "$GH_STUB_DIR/protection-error"; e6_rollup '[]'
gate "$(pass_ctx | jq '.trust_unprotected=true')"
if [ "$RUN_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ]; then
  ok "gate: no required list + an empty rollup (statusCheckRollup: []) ⇒ condition 5 holds ⇒ MERGE"
else
  no "gate empty-required empty rollup wrong (out='$RUN_OUT' merges=$(merges))"
fi
reset_live
printf '{"required_pull_request_reviews":{"required_approving_review_count":1}}\n' > "$GH_STUB_DIR/protection.json"; e6_rollup "$E6_RED"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: checks_not_green" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: reviews-only protection (no required status checks) + one FAILURE in the rollup ⇒ PARK: checks_not_green, no merge"
else
  no "gate reviews-only + failing check FAILED OPEN (out='$RUN_OUT' merges=$(merges))"
fi
reset_live

# --- TOCTOU: a push lands AFTER every condition read the head but BEFORE the
# merge. The stub, like GitHub, refuses a --match-head-commit that no longer
# matches and merges a flag-less call regardless — so a gate that drops the SHA
# pin MERGEs unchecked code here and this case goes red. ---
printf '%040d\n' 0 > "$GH_STUB_DIR/merge-time-head"   # a pushed commit ≠ $E_PR_HEAD
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: merge_command_failed" ] \
   && ! grep -q MERGE_CALLED "$GH_STUB_DIR/merge.log" \
   && grep -q MERGE_REFUSED "$GH_STUB_DIR/merge.log"; then
  ok "gate fail-closed: head moved between the checks and the merge ⇒ GitHub refuses the SHA-pinned merge ⇒ PARK: merge_command_failed, nothing merged"
else
  no "gate head-moved-at-merge FAILED OPEN (out='$RUN_OUT' merges=$(merges) log='$(cat "$GH_STUB_DIR/merge.log" 2>/dev/null)')"
fi
rm -f "$GH_STUB_DIR/merge-time-head"

# --- merge command itself fails ---
touch "$GH_STUB_DIR/merge-fail"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: merge_command_failed" ]; then
  ok "gate fail-closed: gh pr merge fails ⇒ PARK: merge_command_failed (no successful merge)"
else
  no "gate merge-command-failed wrong (out='$RUN_OUT' merges=$(merges))"
fi
rm -f "$GH_STUB_DIR/merge-fail"
reset_live

# --- BLOCKING mutation control (AC — "Mutation control … proves condition 6 is
# load-bearing, not asserted"). Comment out the classify-risk.sh invocation
# inside a COPY of gate_eval (mirrors the pre-existing cond-6-deletion mutant
# pattern) — the all-green case must NOT merge: with the call never made,
# risk_json stays empty ⇒ hr="__MISSING__" ⇒ PARK: high_risk_diff. This proves
# the all-green MERGE case genuinely depends on the classify-risk.sh call
# happening, not on any value the ctx happened to carry (it can't — cond 6 has
# no ctx input at all any more). ---
MUT="$(mktemp -d)"
sed 's/^\(  if \[ -r "\$risk_bin" \]; then\)$/  if false \&\& [ -r "$risk_bin" ]; then/' "$GWD/automate-helpers.sh" > "$MUT/automate-helpers.sh"
if [ -s "$MUT/automate-helpers.sh" ] && ! cmp -s "$GWD/automate-helpers.sh" "$MUT/automate-helpers.sh" && bash -n "$MUT/automate-helpers.sh" 2>/dev/null \
   && grep -q 'if false && \[ -r "\$risk_bin" \]; then' "$MUT/automate-helpers.sh"; then
  cp "$GWD/classify-risk.sh" "$MUT/classify-risk.sh"
  cp "$GWD/rules-gate-verdict.sh" "$GWD/resolve-base-branch.sh" "$MUT/"
  # Instrument the stub classify-risk.sh to prove (positively) whether it was called.
  printf '#!/usr/bin/env bash\necho called >> "%s/classify-risk-called.log"\necho '"'"'{"high_risk": false, "reasons": [], "source": "classify-risk.sh"}'"'"'\n' "$WD" > "$MUT/classify-risk.sh"
  chmod +x "$MUT/classify-risk.sh"
  rm -f "$WD/classify-risk-called.log"
  rm -f "$GH_STUB_DIR/merge.log"
  printf '%s' "$(pass_ctx)" > "$WD/ctx.json"
  MUT_OUT="$( env PATH="$BIN:$PATH" GH_STUB_DIR="$GH_STUB_DIR" HOME="$WD/nohome" bash "$MUT/automate-helpers.sh" gate-eval "$PR" "$WD/ctx.json" --root "${E_GATE_ROOT:-$E_ROOT}" 2>/dev/null )"
  if [ "$MUT_OUT" != "MERGE" ] && [ "$(merges)" -eq 0 ] && [ ! -f "$WD/classify-risk-called.log" ]; then
    ok "gate (mutant) classify-risk.sh invocation commented out ⇒ the all-green case does NOT merge, and the stub log proves classify-risk.sh was never called — condition 6 is genuinely load-bearing on the call happening"
  else
    no "gate cond-6 mutation control FAILED to discriminate (mutant out='$MUT_OUT' merges=$(merges) called_log=$([ -f "$WD/classify-risk-called.log" ] && echo yes || echo no)) — the all-green MERGE case must depend on the classify-risk.sh call, not survive its removal"
  fi
  # Positive control: the REAL (non-mutant) harness, given the SAME instrumented
  # classify-risk.sh, DOES call it (the log proves it) and DOES merge — showing
  # the mutant's failure above is caused by the DELETED invocation, not by the
  # instrumentation itself (the harness under test differs by exactly one line).
  CTRL="$(mktemp -d)"
  cp "$GWD/automate-helpers.sh" "$CTRL/automate-helpers.sh"
  cp "$MUT/classify-risk.sh" "$CTRL/classify-risk.sh"
  cp "$GWD/rules-gate-verdict.sh" "$GWD/resolve-base-branch.sh" "$CTRL/"
  rm -f "$WD/classify-risk-called.log" "$GH_STUB_DIR/merge.log"
  printf '%s' "$(pass_ctx)" > "$WD/ctx.json"
  CTRL_OUT="$( env PATH="$BIN:$PATH" GH_STUB_DIR="$GH_STUB_DIR" HOME="$WD/nohome" bash "$CTRL/automate-helpers.sh" gate-eval "$PR" "$WD/ctx.json" --root "${E_GATE_ROOT:-$E_ROOT}" 2>/dev/null )"
  if [ "$CTRL_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ] && [ -f "$WD/classify-risk-called.log" ]; then
    ok "gate (positive control) the SAME instrumented classify-risk.sh, on the UN-mutated gate, IS called and DOES merge — the mutant's non-merge above is caused by the deleted invocation, not the instrumentation"
  else
    no "gate cond-6 mutation control's positive control failed (out='$CTRL_OUT' merges=$(merges) called_log=$([ -f "$WD/classify-risk-called.log" ] && echo yes || echo no)) — cannot trust the mutation result without this"
  fi
  rm -rf "$CTRL"
else
  no "gate cond-6 mutation control not gated (mutant empty, identical to original, bash -n failed, or the invocation guard was not injected)"
fi
rm -rf "$MUT"

