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
  cp "$GWD/rules-gate-verdict.sh" "$MUT/rules-gate-verdict.sh"
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
  cp "$GWD/rules-gate-verdict.sh" "$CTRL/rules-gate-verdict.sh"
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

