echo "-- B. branches the golden segments do not reach"
# B1 — the --auto-merge MERGE chain in one run: gate-eval → drafts + pending record → SYNC → leftover ask → CHECK OFF → next PICK
inline_run gate-eval-merge "$(printf '%s\n' "call: --result '{\"drain_result\":\"READY\",\"termination_reason\":\"converged\",\"ready_sha\":\"eb0e123e1584184cca438b53ed5145da79825acc\"}'" \
  "expect: ask" "call: --result '{\"answers\":[\"Keep and continue\"]}'" "expect: done")"
if [ -z "$DRIVE_ERR" ] && in_order "$CASE_RF" "gate-eval: MERGE" "— kept automatically (summary below the tracking threshold, no question)" "- dismissed-drafts: 1 per-finding + 1 summary" \
     "closeout leftover kept: $CASE_RUN guard skipped — gh unavailable" "checked off .supervisor/requirements/automate-followups/39a-sweep-and-janitor.md — merged" \
   && grep -qxF -- '- pending_decisions: 1 | fix_now_reentered: false' "$CASE_RF" \
   && grep -qxF -- '- [x] .supervisor/requirements/automate-followups/39a-sweep-and-janitor.md' "$CASE_RF" \
   && printf '%s' "$LAST_OUT" | jq -e '.status == "running" and .remaining == 1' >/dev/null; then
  ok "B1: MERGE ⇒ drafts (the summary kept automatically, before the count line) + pending_decisions recorded ⇒ SYNC leftover kept ⇒ checked off ⇒ {do: done, status: running}"
else no "B1: MERGE chain wrong: $DRIVE_ERR"; tail -n 8 "$CASE_RF" | sed 's/^/    /'; fi
# B2 — AUT-WAIVE answered Keep parked ⇒ the escalated park (validation_unrun, the step as --check)
inline_run gate-validation-waive "$(printf '%s\n' "call: --result '{\"drain_result\":\"READY\",\"termination_reason\":\"converged\",\"ready_sha\":\"8f8a52d\"}'" \
  "expect: ask" "call: --result '{\"answers\":[\"Keep parked\"]}'" "expect: park")"
if [ -z "$DRIVE_ERR" ] && printf '%s' "$LAST_OUT" | jq -e '.escalation_cause == "validation_unrun"' >/dev/null \
   && grep -qF -- '- escalation_cause: validation_unrun | check: V3 Running system | run_id: null | attempt: null | sha: 8f8a52d' "$CASE_RF" \
   && grep -qF -- 'validation-gate: unrun — V3 Running system' "$CASE_RF" && ! grep -q 'validation waived' "$CASE_RF"; then
  ok "B2: AUT-WAIVE Keep parked ⇒ escalated park, escalation_cause validation_unrun, no waiver written"
else no "B2: Keep parked wrong: $DRIVE_ERR"; grep -E 'escalation_cause|validation' "$CASE_RF" | sed 's/^/    /'; fi
# B2' — AUT-WAIVE answered Waive with words validation-gate --waive refuses ⇒ the same escalated park, the
# refusal named on stderr, no waiver written and no write-only sidecar key left behind
inline_run gate-validation-waive "$(printf '%s\n' "call: --result '{\"drain_result\":\"READY\",\"termination_reason\":\"converged\",\"ready_sha\":\"8f8a52d\"}'" \
  "expect: ask" "call: --result '{\"answers\":[\"Waive this step\"],\"note\":\"ran it by hand | looked fine\"}'" "expect: park")"
if [ -z "$DRIVE_ERR" ] && printf '%s' "$LAST_OUT" | jq -e '.escalation_cause == "validation_unrun"' >/dev/null \
   && grep -q 'validation-gate --waive refused (treated as Keep parked)' "$CASE_DIR"/call*.err && ! grep -q 'validation waived' "$CASE_RF" \
   && ! grep -rq 'waive_refusal' "$CASE_ROOT/.supervisor"; then
  ok "B2': a refused waiver ⇒ escalated park validation_unrun, the refusal on stderr, no waiver line, no write-only sidecar key"
else no "B2': refused waiver wrong: $DRIVE_ERR $(grep -rl waive_refusal "$CASE_ROOT/.supervisor" 2>/dev/null | head -n 1)"; fi
# B2'' — the superseded drain's close-out reads the NEXT_STEP_CLOSEOUT_OUT seam (a partial removal ⇒ leftover)
inline_run drain-superseded-by-merge "$(printf '%s\n' "file: \"\$ROOT/closeout.out\" 'closeout: removed — worktree /tmp/wt; kept branch feature/x'" \
  "env: NEXT_STEP_FROM=drain-result NEXT_STEP_CLOSEOUT_OUT=\$ROOT/closeout.out" \
  "call: --session-id bec3aeba-75d5-447b-9d54-88f8a6d4593c --non-interactive --result '{\"no_terminal_block\":true}'" "expect: park")"
if [ -z "$DRIVE_ERR" ] && grep -qF 'closeout leftover kept' "$CASE_RF" && grep -qF 'kept branch feature/x' "$CASE_RF"; then
  ok "B2'': the superseded drain's close-out reads the closeout seam (its partial removal is a leftover)"
else no "B2'': superseded closeout seam not read: $DRIVE_ERR"; grep -E 'closeout|leftover' "$CASE_RF" | tail -n 3 | sed 's/^/    /'; fi
# B3 — a --result that answers nothing valid exits 2 and writes nothing; the ask stays pending
inline_run park-first-ready-park "$(printf '%s\n' "call: --result '{\"drain_result\":\"READY\",\"termination_reason\":\"converged\",\"ready_sha\":\"028cbed6b8e3588f93731d6b862f0bc334de1d96\"}'" "expect: ask")"
ask1="$LAST_OUT"; s0="$(snapshot)"; : > "$CASE_DIR/seams.none"
in_case "$DRIVER" "$CASE_DIR/seams.none" bash "$DRIVER" "$CASE_RF" --result '{"answers":["Merge it now"]}' > "$CASE_DIR/b3.out" 2> "$CASE_DIR/b3.err"; b3rc=$?
in_case "$DRIVER" "$CASE_DIR/seams.none" bash "$DRIVER" "$CASE_RF" --result 'not json' > /dev/null 2>&1; b3rc2=$?
s1="$(snapshot)"; again="$(in_case "$DRIVER" "$CASE_DIR/seams.none" bash "$DRIVER" "$CASE_RF" 2>/dev/null)"
if [ -z "$DRIVE_ERR" ] && [ "$b3rc" = 2 ] && [ "$b3rc2" = 2 ] && [ ! -s "$CASE_DIR/b3.out" ] && [ "$s0" = "$s1" ] && [ "$again" = "$ask1" ]; then
  ok "B3: a label that is not an option / a non-JSON --result ⇒ exit 2, nothing written, the ask re-prints"
else no "B3: invalid answer: rc $b3rc/$b3rc2, unchanged=$([ "$s0" = "$s1" ] && echo yes || echo no), $DRIVE_ERR $(head -n 2 "$CASE_DIR/b3.err" | tr '\n' ' ')"; fi
# B4 — a refused writer is surfaced (no instruction, non-zero exit), and the next call retries the step
new_scratch "$FIX/gate-validation-gate-unrun-escalated"
cp "$CASE_RF" "$CASE_DIR/rf.keep"; sed '1d' "$CASE_DIR/rf.keep" > "$CASE_RF"   # no `# Automate Run:` title ⇒ progress-append refuses
: > "$CASE_DIR/seams.none"
in_case "$DRIVER" "$CASE_DIR/seams.none" bash "$DRIVER" "$CASE_RF" --non-interactive \
  --result '{"drain_result":"READY","termination_reason":"converged","ready_sha":"06ce6f59617b3b515a1950dbeb8b13630b54525c"}' > "$CASE_DIR/b4.out" 2> "$CASE_DIR/b4.err"; b4rc=$?
cp "$CASE_DIR/rf.keep" "$CASE_RF"
retry="$(in_case "$DRIVER" "$CASE_DIR/seams.none" bash "$DRIVER" "$CASE_RF" --non-interactive 2>/dev/null)"
norm "$CASE_RF" > "$CASE_DIR/a.md"; norm "$FIX/gate-validation-gate-unrun-escalated/expected.md" > "$CASE_DIR/x.md"
if [ "$b4rc" -ne 0 ] && [ "$b4rc" -ne 2 ] && [ ! -s "$CASE_DIR/b4.out" ] && grep -q 'progress-append exited' "$CASE_DIR/b4.err" \
   && printf '%s' "$retry" | jq -e '.do == "park"' >/dev/null 2>&1 && cmp -s "$CASE_DIR/a.md" "$CASE_DIR/x.md"; then
  ok "B4: a refused progress-append ⇒ exit $b4rc, no instruction, stderr names it; the retry finishes the case byte-identically"
else no "B4: writer failure: rc $b4rc, out '$(cat "$CASE_DIR/b4.out")', retry '$retry'"; diff "$CASE_DIR/x.md" "$CASE_DIR/a.md" | sed 's/^/    /' | head -n 12; fi
# B5 — fix-now before the park (a lane: decide-then-park) ⇒ spawn ⇒ the re-drain report ⇒ re-park, fix-now never
# offered again: no fix-now is left, so nothing is asked after the re-drain. The re-dismissed draft is rewritten
# `undecided (fix-now unconfirmed)`; its `--auto` is refused (the ledger holds fix-now-unconfirmed), so it stays
# undecided (pending_decisions: 1) for the next PICK's AUT-PENDING fallback
inline_run dismissed-findings-decision-step "$(printf '%s\n' "call: --result '{\"drain_result\":\"READY\",\"termination_reason\":\"converged\",\"ready_sha\":\"0000000\"}'" \
  "expect: ask" "call: --result '{\"answers\":[\"Fix all listed on this PR\"]}'" "expect: spawn")"
spawn="$LAST_OUT"; b5err1="$DRIVE_ERR"
printf '%s\n' "call: --result '{\"drain_result\":\"READY\",\"termination_reason\":\"converged\",\"ready_sha\":\"1111111\"}'" "expect: park" > "$CASE_DIR/b5b.results"
: > "$WORK/asks.b5"; ASKS_SAVE="$ASKS"; ASKS="$WORK/asks.b5"
drive "$FIX/dismissed-findings-decision-step" "$DRIVER" "$CASE_DIR/b5b.results"; ASKS="$ASKS_SAVE"
if [ -z "$b5err1$DRIVE_ERR" ] && printf '%s' "$spawn" | jq -e '.what == "fix-now re-drain" and (.findings | length) == 1' >/dev/null \
   && grep -qF -- 'owner decisions (dismissed): 1 fix-now, 0 follow-up, 0 drop' "$CASE_RF" \
   && grep -qxF -- '- pending_decisions: 1 | fix_now_reentered: true' "$CASE_RF" \
   && grep -qxF -- '- **Decision:** undecided (fix-now unconfirmed)' "$CASE_ROOT"/.supervisor/requirements/proposed/*--dismissed-7de02129.md \
   && [ ! -s "$WORK/asks.b5" ]; then
  ok "B5: Fix all listed ⇒ {do: spawn} ⇒ re-drain report ⇒ nothing asked (no fix-now left; the fix-now-unconfirmed draft stays undecided) ⇒ re-park with fix_now_reentered: true"
else no "B5: fix-now re-pass wrong: $b5err1 $DRIVE_ERR asks: $(cut -f2- "$WORK/asks.b5" | head -c 200)"; tail -n 6 "$CASE_RF" | sed 's/^/    /'; fi
# B5b — a malformed re-drain report answering the spawn ⇒ exit 2, nothing written, the spawn re-prints
inline_run dismissed-findings-decision-step "$(printf '%s\n' "call: --result '{\"drain_result\":\"READY\",\"termination_reason\":\"converged\",\"ready_sha\":\"0000000\"}'" \
  "expect: ask" "call: --result '{\"answers\":[\"Fix all listed on this PR\"]}'" "expect: spawn")"
spawn="$LAST_OUT"; s0="$(snapshot)"; : > "$CASE_DIR/seams.none"
b5o="$(in_case "$DRIVER" "$CASE_DIR/seams.none" bash "$DRIVER" "$CASE_RF" --result '{"drain_result":"died"}' 2>/dev/null)"; b5rc=$?
again="$(in_case "$DRIVER" "$CASE_DIR/seams.none" bash "$DRIVER" "$CASE_RF" 2>/dev/null)"
if [ -z "$DRIVE_ERR" ] && [ "$b5rc" = 2 ] && [ -z "$b5o" ] && [ "$s0" = "$(snapshot)" ] && [ -n "$spawn" ] && [ "$again" = "$spawn" ]; then
  ok "B5b: a re-drain report with drain_result 'died' ⇒ exit 2, nothing written, the spawn re-prints"
else no "B5b: malformed re-drain report: rc $b5rc, out '$b5o', $DRIVE_ERR"; fi
# B6 — a malformed drain report (drain_result not READY|ESCALATED, a non-count items_processed, an unknown
# escalation_cause, a non-hex sha, a multi-line progress_note) ⇒ exit 2, nothing printed, nothing written
LEG_MSG=""
if leg_badreport "$DRIVER"; then ok "B6: $(grep -c . <<<"$BAD_REPORTS") malformed drain reports ⇒ exit 2, nothing printed, .supervisor/ byte-unchanged"
else no "B6: $LEG_MSG"; fi
# B7 — a different drain report after the terminal park (status no longer running) ⇒ exit 2, nothing written
LEG_MSG=""
if leg_reentry "$DRIVER"; then ok "B7: a different drain report after the escalated park ⇒ exit 2, nothing written, the park re-prints"
else no "B7: $LEG_MSG"; fi
# B8 — park-first order on the driver itself: watcher armed < run lock released < park-ask-gate
LEG_MSG=""
RECD="$WORK/rec-real"; mkdir -p "$RECD"
for e in "$HERE"/*; do [ "$e" = "$DRIVER" ] || ln -s "$e" "$RECD/$(basename "$e")"; done
cp "$DRIVER" "$RECD/automate-next-step.sh"; rec_helpers "$RECD/automate-next-step.sh"
if leg_order "$RECD/automate-next-step.sh"; then ok "B8: park-first READY park — watcher armed, then lock released, then park-ask-gate"
else no "B8: $LEG_MSG"; fi
# B9 — the sidecar's pending state is bound to ## Current's item + PR
LEG_MSG=""
if leg_binding "$DRIVER"; then ok "B9: A's pending ask never answers for B (exit 2, nothing written); B's report starts B's own tail at gate"
else no "B9: $LEG_MSG"; fi
# B10 — a count `[` cannot compare (20 digits, held in the sidecar) at terminate ⇒ the limit_reached park, never running
LEG_MSG=""
if leg_bigcount "$DRIVER"; then ok "B10: a 20-digit items_processed at terminate ⇒ limit_reached park (fail CLOSED)"
else no "B10: $LEG_MSG"; fi
# B11 — --non-interactive given on the first call only: the no-result retry of the failed step stays non-interactive
LEG_MSG=""
if leg_nonint_persist "$DRIVER"; then ok "B11: --non-interactive persists for the tail — the flagless retry parks (validation_unrun), never asks"
else no "B11: $LEG_MSG"; fi
# B12/B13 — dismissed-pending's documented `unknown` (another item's draft with no Decision line) is recorded,
# never a refusal: the escalated park completes, and the MERGE path goes on to SYNC
LEG_MSG=""
if leg_unknown_park "$DRIVER"; then ok "B12: a malformed draft (unknown) at an escalated park ⇒ pending_decisions: unknown, park line, watcher, notify, lock released"
else no "B12: $LEG_MSG"; fi
LEG_MSG=""
if leg_unknown_merge "$DRIVER"; then ok "B13: a malformed draft (unknown) after a MERGE ⇒ pending_decisions: unknown, SYNC reached"
else no "B13: $LEG_MSG"; fi
# B14 — a replayed drain report never stands in for a new one: the first report after a spawn re-prints the
# spawn (a new re-drain report proceeds); item A's report while B runs, or a foreign `pr`, ⇒ exit 2
LEG_MSG=""
if leg_spawn_replay "$DRIVER"; then ok "B14a: the first drain report re-sent after a spawn ⇒ the spawn re-prints, nothing written; a new re-drain report proceeds"
else no "B14a: $LEG_MSG"; fi
LEG_MSG=""
if leg_cross_replay "$DRIVER"; then ok "B14b: A's drain report while B runs / a foreign pr ⇒ exit 2, nothing written; B's own report (pr bound) starts B's tail"
else no "B14b: $LEG_MSG"; fi
# B15 — the done exit's registry line: ONE, directly before the sweep line; a silent summary ⇒ the skipped form
LEG_MSG=""
if leg_registry_line "$DRIVER"; then ok "B15: done exit ⇒ ONE '<ts> process registry: <summary>' line directly before the sweep line; a silent proc-registry.sh summary ⇒ 'proc-registry: summary — skipped: no output'"
else no "B15: $LEG_MSG"; fi
