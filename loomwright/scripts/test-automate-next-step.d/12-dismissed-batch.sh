# test-automate-next-step.d/12-dismissed-batch.sh — part of test-automate-next-step.sh (TNS_PARTS / TNS_GROUPS /
# its `pg_want 12-dismissed-batch` line): the dismissed-findings decision step's silent follow-up, its ONE batched
# AUT-DISMISS ask, the PICK-time automatic follow-up and the park report (skills/automate-loop/per-item-loop.md
# §"Dismissed-findings decision step (before the park)"). Sourced by the runner (its setup, helpers and counters);
# run directly — e.g. by run-pin-mutations.sh — it re-enters the runner for this part alone.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  exec "${BASH:-bash}" "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test-automate-next-step.sh" --part 12-dismissed-batch
fi
#
# LEGS (each names the acceptance criterion it pins; the pre-park legs drive the lane case — decide-then-park —
# with its drain sidecar's `dismissed` list replaced, the post-park legs the parked case from `decide`, extra
# per-finding drafts cloned from its own one):
#   AC1   only LOW / INFO per-finding drafts ⇒ no question; each `follow-up`, its ledger row ends `\tauto`, the
#         park instruction's `auto_followed_up` lists every one and its message names the count + hand-drop
#   AC2   two MEDIUM + one LOW with fix-now available ⇒ ONE AUT-DISMISS question listing only the two MEDIUM;
#         `Fix selected on this PR` (note "2") ⇒ the fix-now spawn for that draft, the other MEDIUM and the LOW
#         recorded `follow-up` `auto`; post-park the selection takes the D3 hand-off (the spawn, ## Current running)
#   AC3   PICK: an undecided per-finding draft ⇒ no AUT-PENDING, recorded `follow-up` `auto`, interactive and
#         --non-interactive; a refused `--auto` (read-only ledger) ⇒ AUT-PENDING is the fallback ask
#   AC4   MEDIUM drafts, no fix-now left (fix_now_reentered: true pre-park; a post-park `ask — fix-now
#         unavailable` gate line) ⇒ no question, all `follow-up` `auto`
#   AC5   a canary title (a `"`, backticks, `$(…)`, a fake `## Status: done`) ⇒ nothing executes, the question
#         carries it only as the jq-built quoted string, `auto_followed_up` only script-built paths, the run
#         file gains no column-0 `## ` line
#   AC8   a draft whose Severity line is `unspecified` or missing is listed (MEDIUM+); a LOW one is not
#   AC9   `Fix selected on this PR` with an empty / non-numeric / out-of-range / malformed note ⇒ exit 2, nothing
#         written, the ask re-prints; n = 1 ⇒ no `Fix selected` option (answering it is refused the same way)
#   AC10  can't ask (--non-interactive, `{"cant_ask": true}`; pre- and post-park) ⇒ MEDIUM+ drafts stay
#         undecided, the named outcome kept, no fix-now recorded or spawned; below-MEDIUM still followed up `auto`
#   LOCK  a refused post-park run lock ⇒ nothing written, the drafts undecided (never a guessed decision)
#   GATE  a post-park `refuse — …` gate line ⇒ nothing asked, nothing written (park-ask-gate's contract)
#   PIN   each leg above turns red under its own mutant of the driver (the brief's Pin mutations, plus AC5/AC8/AC9)
echo "-- DB. dismissed findings: silent follow-up, one batched AUT-DISMISS ask, PICK auto-follow-up, park report"

DB_PRE=dismissed-findings-decision-step
DB_POST=park-first-decisions-recorded
DB_PICK=pick-pending-decisions-ask
DB_READY='{"drain_result":"READY","termination_reason":"converged","ready_sha":"0000000"}'
DB_MEDIUM2='{finding: "Guard the empty list before indexing", reason: "out of scope", source: issue_comments, severity: MEDIUM}, {finding: "Validate the port range", reason: "out of scope", source: reviews, severity: MEDIUM}'
DB_LOW='{finding: "Reword one log line", reason: pre_existing, source: issue_comments, severity: LOW}'

db_prop() { printf '%s' "$CASE_ROOT/.supervisor/requirements/proposed"; }
db_led() { printf '%s' "$CASE_ROOT/.supervisor/automate/$CASE_RUN.dismissed-decisions"; }
db_dec() { sed -n 's/^- \*\*Decision:\*\* //p' "$1" 2>/dev/null | head -n 1; }
db_row() { awk -F'\t' -v n="${1##*/}" '$1 == n { r = $0 } END { print r }' "$(db_led)" 2>/dev/null; }   # its last ledger row
db_auto() { [ "$(db_dec "$1")" = follow-up ] && case "$(db_row "$1")" in *"${TAB}follow-up${TAB}"*"${TAB}auto") true ;; *) false ;; esac; }
db_undecided() { [ "$(db_dec "$1")" = undecided ] && [ -z "$(db_row "$1")" ]; }
db_jq() { printf '%s' "$DB_OUT" | jq "$@" 2>/dev/null; }
db_findings() { # this run's per-finding drafts on disk, one path a line
  local f; for f in "$(db_prop)/$CASE_RUN"--*--dismissed-*.md; do
    case "$f" in *--dismissed-summary*) ;; *) [ -f "$f" ] && printf '%s\n' "$f" ;; esac
  done
}
db_sev_of() { sed -n 's/^- \*\*Severity:\*\* //p' "$1" | head -n 1; }
# db_call <driver> <seams> <args…> — one driver call (run file first); sets DB_OUT DB_RC DB_ERR, asks to $DB_ASKS
db_call() {
  local drv="$1" s="$2"; shift 2
  DB_OUT="$(in_case "$drv" "$s" bash "$drv" "$CASE_RF" "$@" 2>"$CASE_DIR/db.err")"; DB_RC=$?
  DB_ERR="$(cat "$CASE_DIR/db.err")"
  printf '%s' "$DB_OUT" | grep '"do":"ask"' >> "$DB_ASKS"
  return 0
}
db_fail() { LEG_MSG="$1 — exit $DB_RC, printed '${DB_OUT:0:220}' ${DB_ERR:0:220}"; return 1; }
# db_pre <dismissed entries> — the lane case (decide-then-park), its drain sidecar's dismissed list replaced
db_pre() {
  new_scratch "$FIX/$DB_PRE" || return 1
  local sc="$CASE_ROOT/.supervisor/automate/$CASE_RUN.review-heal-result.md"
  DB_L="[$1]" awk 'BEGIN { l = ENVIRON["DB_L"] } /^- dismissed: / { print "- dismissed: " l; next } { print }' "$sc" > "$sc.t" && mv "$sc.t" "$sc" || return 1
  : > "$CASE_DIR/seams.none"; DB_ASKS="$CASE_DIR/asks"; : > "$DB_ASKS"
}
# db_post — the case parked awaiting_merge, its gate line recorded (`ask — fix-now allowed …`), one undecided
# per-finding draft (Severity: unspecified); calls start at `decide` (seams.from)
db_post() {
  new_scratch "$FIX/$DB_POST" || return 1
  DB_D0="$(db_prop)/$CASE_RUN--39a-sweep-and-janitor-1c7166--dismissed-d90c587e.md"
  printf 'NEXT_STEP_FROM=decide\n' > "$CASE_DIR/seams.from"; : > "$CASE_DIR/seams.none"
  DB_ASKS="$CASE_DIR/asks"; : > "$DB_ASKS"
}
# db_clone <h8> <severity|-> <title> — another per-finding draft of the parked item (its own one re-titled, its
# Severity line replaced — `-` deletes it); prints the path
db_clone() {
  local f="$(db_prop)/$CASE_RUN--39a-sweep-and-janitor-1c7166--dismissed-$1.md"
  DB_S="$2" DB_T="$3" awk 'BEGIN { s = ENVIRON["DB_S"]; t = ENVIRON["DB_T"] }
    NR == 1 { print "# Dismissed finding: " t; next }
    /^- \*\*Severity:\*\* / { if (s != "-") print "- **Severity:** " s; next } { print }' "$DB_D0" > "$f"
  printf '%s' "$f"
}
# db_gate <text> — the recorded post-park gate line's text after its timestamp, replaced
db_gate() {
  DB_G="$1" awk 'BEGIN { g = ENVIRON["DB_G"] } /^- [^ ]+ dismissed decisions asked after the park — / { sub(/ dismissed decisions .*/, ""); print $0 " " g; next } { print }' \
    "$CASE_RF" > "$CASE_RF.t" && mv "$CASE_RF.t" "$CASE_RF"
}
db_listed() { db_jq -r '.questions[0].drafts[]?' | sed 's|.*/||' | env LC_ALL=C sort | tr '\n' ' '; }
db_names() { local p; for p in "$@"; do printf '%s\n' "${p##*/}"; done | env LC_ALL=C sort | tr '\n' ' '; }

# AC1 — only below-MEDIUM drafts ⇒ no question, every one `follow-up` `auto`, all in the park report
db_ac1() {
  local drv="$1" d n=0 o2
  db_pre "$DB_LOW, {finding: \"Tidy the comment wording\", reason: pre_existing, source: reviews, severity: INFO}" || { LEG_MSG="scratch"; return 1; }
  db_call "$drv" "$CASE_DIR/seams.none" --result "$DB_READY"
  [ "$DB_RC" = 0 ] && [ "$(db_jq -r .do)" = park ] && [ ! -s "$DB_ASKS" ] || { db_fail "LOW/INFO only: want the park, no ask"; return 1; }
  while IFS= read -r d; do
    n=$((n + 1))
    db_auto "$d" || { LEG_MSG="${d##*/}: Decision '$(db_dec "$d")', ledger row '$(db_row "$d")' (want follow-up, \\tauto)"; return 1; }
    db_jq -e --arg p ".supervisor/requirements/proposed/${d##*/}" 'any(.auto_followed_up[]?; . == $p)' >/dev/null \
      || { LEG_MSG="auto_followed_up $(db_jq -c .auto_followed_up) lacks ${d##*/}"; return 1; }
  done <<EOF
$(db_findings)
EOF
  [ "$n" = 2 ] && [ "$(db_jq '.auto_followed_up | length')" = 2 ] || { LEG_MSG="$n draft(s), auto_followed_up $(db_jq -c .auto_followed_up) (want 2 and 2)"; return 1; }
  db_jq -e '.message | (contains("2 dismissed draft(s) followed up automatically (no question)") and contains("automate-helpers.sh dismissed-decide ") and endswith(" <draft> drop"))' >/dev/null \
    || { LEG_MSG="park message '$(db_jq -r .message)' does not name the count and the hand-drop command"; return 1; }
  ! grep -q 'owner decisions (dismissed)' "$CASE_RF" || { LEG_MSG="an owner-decisions batch line was written with nothing asked"; return 1; }
  o2="$(in_case "$drv" "$CASE_DIR/seams.none" bash "$drv" "$CASE_RF" 2>/dev/null)"
  [ "$o2" = "$DB_OUT" ] || { LEG_MSG="the no-result call did not re-print the park"; return 1; }
  return 0
}

# AC2 — the ONE batched ask lists only the MEDIUM+ drafts; a selection takes the fix-now path, the rest `auto`
db_ac2() {
  local drv="$1" d low="" med="" sel unsel f
  db_pre "$DB_MEDIUM2, $DB_LOW" || { LEG_MSG="scratch"; return 1; }
  db_call "$drv" "$CASE_DIR/seams.none" --result "$DB_READY"
  [ "$DB_RC" = 0 ] && [ "$(db_jq -r .do)" = ask ] || { db_fail "two MEDIUM + one LOW: want the ask"; return 1; }
  while IFS= read -r d; do
    if [ "$(db_sev_of "$d")" = LOW ]; then low="$d"; else med="$med$d$TAB"; fi
  done <<EOF
$(db_findings)
EOF
  [ -n "$low" ] && db_auto "$low" || { LEG_MSG="the LOW draft: Decision '$(db_dec "$low")', row '$(db_row "$low")' (want follow-up, auto, before the ask)"; return 1; }
  [ "$(grep -c . "$DB_ASKS")" = 1 ] && [ "$(db_jq -r .gate)" = AUT-DISMISS ] && [ "$(db_jq '.questions | length')" = 1 ] \
    && [ "$(db_jq -r '.questions[0].header')" = AUT-DISMISS ] \
    && [ "$(db_jq -c '.questions[0].options')" = '["Fix none (follow-up all)","Fix all listed on this PR","Fix selected on this PR"]' ] \
    || { LEG_MSG="want ONE AUT-DISMISS question with the three catalog labels, got $(db_jq -c '[.gate, (.questions | length), .questions[0].options]')"; return 1; }
  # shellcheck disable=SC2086
  [ "$(db_listed)" = "$(IFS="$TAB"; db_names $med)" ] || { LEG_MSG="listed '$(db_listed)', want only the MEDIUM drafts '$(IFS="$TAB"; db_names $med)'"; return 1; }
  sel="$(db_jq -r '.questions[0].drafts[1]')"; unsel="$(db_jq -r '.questions[0].drafts[0]')"
  db_jq -e --arg a "1. \"$(head -n 1 "$unsel" | sed 's/^# //')\" — draft ${unsel##*/}" --arg b "2. \"$(head -n 1 "$sel" | sed 's/^# //')\" — draft ${sel##*/}" \
    '.questions[0].question | contains($a) and contains($b)' >/dev/null || { LEG_MSG="the question does not number the listed drafts: $(db_jq -r '.questions[0].question')"; return 1; }
  db_call "$drv" "$CASE_DIR/seams.none" --result '{"answers":["Fix selected on this PR"],"note":"2"}'
  [ "$DB_RC" = 0 ] && db_jq -e --arg n "${sel##*/}" '.do == "spawn" and .what == "fix-now re-drain" and (.findings | length) == 1 and .findings[0].draft == $n' >/dev/null \
    || { db_fail "Fix selected 2: want the fix-now spawn for ${sel##*/}"; return 1; }
  [ ! -e "$sel" ] && [ "$(db_row "$sel" | cut -f2)" = fix-now ] && db_auto "$unsel" && db_auto "$low" \
    && grep -qF -- 'owner decisions (dismissed): 1 fix-now, 1 follow-up, 0 drop' "$CASE_RF" \
    || { LEG_MSG="selected row '$(db_row "$sel")'; unselected '$(db_dec "$unsel")' '$(db_row "$unsel")'; LOW '$(db_row "$low")'"; return 1; }
  # post-park: the same selection takes the D3 hand-off — both park-ask-gate reads OPEN, the item set running
  db_post || { LEG_MSG="scratch (post)"; return 1; }
  f="$(db_clone 11111111 HIGH "Close the second race")"
  db_call "$drv" "$CASE_DIR/seams.from"
  [ "$DB_RC" = 0 ] && [ "$(db_jq -r .gate)" = AUT-DISMISS ] && [ "$(db_listed)" = "$(db_names "$f" "$DB_D0")" ] || { db_fail "post-park: want the ask listing both"; return 1; }
  sel="$(db_jq -r '.questions[0].drafts[0]')"; unsel="$(db_jq -r '.questions[0].drafts[1]')"
  db_call "$drv" "$CASE_DIR/seams.none" --result '{"answers":["Fix selected on this PR"],"note":" 1 "}'
  [ "$DB_RC" = 0 ] && db_jq -e --arg n "${sel##*/}" '.do == "spawn" and .what == "fix-now re-drain" and .findings[0].draft == $n' >/dev/null \
    && grep -qF -- "status: running" <(grep '^- item: ' "$CASE_RF") && [ "$(db_row "$sel" | cut -f2)" = fix-now ] && db_auto "$unsel" \
    || { db_fail "post-park Fix selected 1: want the D3 hand-off spawn, ## Current running, the other draft auto"; return 1; }
  return 0
}

# AC3 — PICK: every undecided per-finding draft is followed up `auto`, nothing asked; AUT-PENDING only as the fallback
db_ac3() {
  local drv="$1" nonint d
  for nonint in "" --non-interactive; do
    new_scratch "$FIX/$DB_PICK" || { LEG_MSG="scratch"; return 1; }
    printf 'NEXT_STEP_FROM=pending\nNEXT_STEP_UNTIL=pending\n' > "$CASE_DIR/seams.p"; DB_ASKS="$CASE_DIR/asks"; : > "$DB_ASKS"
    db_call "$drv" "$CASE_DIR/seams.p" --session-id auto-2026-10-15-040641 $nonint
    d="$(db_findings | head -n 1)"
    [ "$DB_RC" = 0 ] && [ -z "$DB_OUT" ] && [ ! -s "$DB_ASKS" ] && [ -n "$d" ] && db_auto "$d" \
      || { db_fail "PICK ${nonint:-interactive}: ${d##*/} Decision '$(db_dec "$d")' row '$(db_row "$d")' (want follow-up auto, no AUT-PENDING)"; return 1; }
  done
  # the fallback: a read-only ledger refuses every --auto ⇒ the per-finding draft is asked under AUT-PENDING
  new_scratch "$FIX/$DB_PICK" || { LEG_MSG="scratch (fallback)"; return 1; }
  printf 'NEXT_STEP_FROM=pending\nNEXT_STEP_UNTIL=pending\n' > "$CASE_DIR/seams.p"; DB_ASKS="$CASE_DIR/asks"; : > "$DB_ASKS"
  : > "$(db_led)"; chmod 444 "$(db_led)"
  db_call "$drv" "$CASE_DIR/seams.p" --session-id auto-2026-10-15-040641
  chmod 644 "$(db_led)"
  d="$(db_findings | head -n 1)"
  [ "$DB_RC" = 0 ] && db_jq -e --arg p "$d" '.gate == "AUT-PENDING" and .questions[0].options == ["Follow-up (keep draft)","Drop"] and .questions[0].draft == $p' >/dev/null \
    && [ "$(db_dec "$d")" = undecided ] || { db_fail "refused --auto at PICK: want the AUT-PENDING fallback ask for ${d##*/}"; return 1; }
  return 0
}

# AC4 — MEDIUM drafts with no fix-now left ⇒ no question, all `follow-up` `auto`
db_ac4() {
  local drv="$1" d n=0
  db_pre "$DB_MEDIUM2" || { LEG_MSG="scratch"; return 1; }
  awk '{ print } index($0, "- owned_drain_started:") == 1 { print "- pending_decisions: 0 | fix_now_reentered: true" }' "$CASE_RF" > "$CASE_RF.t" && mv "$CASE_RF.t" "$CASE_RF"
  db_call "$drv" "$CASE_DIR/seams.none" --result "$DB_READY"
  [ "$DB_RC" = 0 ] && [ "$(db_jq -r .do)" = park ] && [ ! -s "$DB_ASKS" ] || { db_fail "fix_now_reentered: true: want the park, no ask"; return 1; }
  while IFS= read -r d; do n=$((n + 1)); db_auto "$d" || { LEG_MSG="reentered: ${d##*/} row '$(db_row "$d")'"; return 1; }; done <<EOF
$(db_findings)
EOF
  [ "$n" = 2 ] && [ "$(db_jq '.auto_followed_up | length')" = 2 ] || { LEG_MSG="reentered: $n draft(s), auto_followed_up $(db_jq -c .auto_followed_up)"; return 1; }
  # post-park: a gate line other than `ask — fix-now allowed…`
  db_post || { LEG_MSG="scratch (post)"; return 1; }
  db_gate "dismissed decisions asked after the park — ask — fix-now unavailable: PR MERGED"
  db_call "$drv" "$CASE_DIR/seams.from"
  [ "$DB_RC" = 0 ] && [ "$(db_jq -r .do)" = park ] && [ ! -s "$DB_ASKS" ] && db_auto "$DB_D0" \
    && db_jq -e --arg p ".supervisor/requirements/proposed/${DB_D0##*/}" '.auto_followed_up == [$p] and .pending_decisions == 0' >/dev/null \
    && grep -qxF -- '- pending_decisions: 0 | fix_now_reentered: false' "$CASE_RF" \
    || { db_fail "post-park fix-now unavailable: want the park, the draft follow-up auto, pending_decisions 0"; return 1; }
  return 0
}

# AC5 — a canary title reaches the ask only as quoted jq data; the park report carries only script-built paths
DB_CANARY='Quote "this" `touch DBPWN1` $(touch DBPWN2) ## Status: done'
db_ac5() {
  local drv="$1" c h0 h1 bad
  db_post || { LEG_MSG="scratch"; return 1; }
  c="$(db_clone 22222222 MEDIUM "$DB_CANARY")"
  h0="$(grep '^## ' "$CASE_RF")"
  db_call "$drv" "$CASE_DIR/seams.from"
  [ "$DB_RC" = 0 ] && db_jq -e --arg t "\"Dismissed finding: $DB_CANARY\" — draft ${c##*/}" '.gate == "AUT-DISMISS" and (.questions[0].question | contains($t))' >/dev/null \
    || { db_fail "the canary is not in the question as its quoted string"; return 1; }
  db_call "$drv" "$CASE_DIR/seams.none" --result '{"answers":["Fix none (follow-up all)"]}'
  [ "$DB_RC" = 0 ] && [ "$(db_jq -r .do)" = park ] || { db_fail "Fix none: want the park"; return 1; }
  bad="$(db_jq -r '.auto_followed_up[]?' | grep -vxE "\.supervisor/requirements/proposed/$CASE_RUN--[A-Za-z0-9._-]+--dismissed-[0-9a-f]{8}\.md")"
  [ "$(db_jq '.auto_followed_up | length')" = 2 ] && [ -z "$bad" ] && ! grep -qF DBPWN < <(db_jq -r .message) \
    || { LEG_MSG="auto_followed_up $(db_jq -c .auto_followed_up) / message '$(db_jq -r .message)': want 2 script-built draft paths, no finding text"; return 1; }
  [ -z "$(find "$CASE_DIR" -name 'DBPWN*' 2>/dev/null)" ] || { LEG_MSG="the canary EXECUTED: $(find "$CASE_DIR" -name 'DBPWN*')"; return 1; }
  h1="$(grep '^## ' "$CASE_RF")"
  [ "$h0" = "$h1" ] || { LEG_MSG="the run file's column-0 headings changed: $(diff <(printf '%s\n' "$h0") <(printf '%s\n' "$h1") | tr '\n' ' ')"; return 1; }
  return 0
}

# AC8 — Severity `unspecified` or missing ⇒ listed (MEDIUM+); LOW ⇒ not listed
db_ac8() {
  local drv="$1" miss low
  db_post || { LEG_MSG="scratch"; return 1; }
  miss="$(db_clone 33333333 - "No severity line at all")"; low="$(db_clone 44444444 LOW "A LOW one")"
  db_call "$drv" "$CASE_DIR/seams.from"
  [ "$DB_RC" = 0 ] && [ "$(db_listed)" = "$(db_names "$miss" "$DB_D0")" ] && db_auto "$low" \
    || { db_fail "want listed '$(db_names "$miss" "$DB_D0")' (unspecified + missing), got '$(db_listed)'; LOW row '$(db_row "$low")'"; return 1; }
  return 0
}

# AC9 — an invalid `Fix selected` note is refused like an invalid label: exit 2, nothing written; n = 1 has no option
db_ac9() {
  local drv="$1" ask s0 note o rc
  db_post || { LEG_MSG="scratch"; return 1; }
  db_clone 55555555 MEDIUM "A second MEDIUM finding" >/dev/null
  db_call "$drv" "$CASE_DIR/seams.from"; ask="$DB_OUT"
  [ "$DB_RC" = 0 ] && [ "$(db_jq '.questions[0].drafts | length')" = 2 ] || { db_fail "setup: want the ask listing 2"; return 1; }
  s0="$(snapshot)"
  for note in '' 'abc' '0' '3' '1;2' '2 x' '-1' '1.5' $'1\n2'; do
    o="$(in_case "$drv" "$CASE_DIR/seams.none" bash "$drv" "$CASE_RF" --result "$(jq -cn --arg n "$note" '{answers: ["Fix selected on this PR"], note: $n}')" 2>/dev/null)"; rc=$?
    [ "$rc" = 2 ] && [ -z "$o" ] && [ "$s0" = "$(snapshot)" ] || { LEG_MSG="note '$note' ⇒ exit $rc '${o:0:80}', .supervisor/ $([ "$s0" = "$(snapshot)" ] && echo unchanged || echo CHANGED)"; return 1; }
  done
  o="$(in_case "$drv" "$CASE_DIR/seams.none" bash "$drv" "$CASE_RF" --result '{"answers":["Fix selected on this PR"]}' 2>/dev/null)"; rc=$?
  [ "$rc" = 2 ] && [ "$s0" = "$(snapshot)" ] || { LEG_MSG="no note ⇒ exit $rc"; return 1; }
  o="$(in_case "$drv" "$CASE_DIR/seams.none" bash "$drv" "$CASE_RF" 2>/dev/null)"
  [ "$o" = "$ask" ] || { LEG_MSG="after the refusals the ask does not re-print"; return 1; }
  # n = 1: two options only; `Fix selected on this PR` is not one of them
  db_post || { LEG_MSG="scratch (n=1)"; return 1; }
  db_call "$drv" "$CASE_DIR/seams.from"
  [ "$(db_jq -c '.questions[0].options')" = '["Fix none (follow-up all)","Fix all listed on this PR"]' ] || { db_fail "n = 1: want the two-label core"; return 1; }
  s0="$(snapshot)"
  o="$(in_case "$drv" "$CASE_DIR/seams.none" bash "$drv" "$CASE_RF" --result '{"answers":["Fix selected on this PR"],"note":"1"}' 2>/dev/null)"; rc=$?
  [ "$rc" = 2 ] && [ -z "$o" ] && [ "$s0" = "$(snapshot)" ] || { LEG_MSG="n = 1, Fix selected ⇒ exit $rc '${o:0:80}'"; return 1; }
  return 0
}

# AC10 — can't ask: MEDIUM+ drafts with fix-now available stay undecided, the named outcome kept, never a fix-now;
# below-MEDIUM still followed up `auto`
db_nofixnow() { ! grep -q "${TAB}fix-now" "$(db_led)" 2>/dev/null && ! grep -q 'owner decisions (dismissed)' "$CASE_RF"; }
db_ac10() {
  local drv="$1" d low med
  db_lowmed() { low=""; med=""; while IFS= read -r d; do if [ "$(db_sev_of "$d")" = LOW ]; then low="$d"; else med="$d"; fi; done <<EOF
$(db_findings)
EOF
  }
  # (a) pre-park --non-interactive
  db_pre "$DB_LOW, {finding: \"Guard the empty list before indexing\", reason: \"out of scope\", source: issue_comments, severity: MEDIUM}" || { LEG_MSG="scratch (a)"; return 1; }
  db_call "$drv" "$CASE_DIR/seams.none" --non-interactive --result "$DB_READY"; db_lowmed
  [ "$DB_RC" = 0 ] && [ "$(db_jq -r .do)" = park ] && [ ! -s "$DB_ASKS" ] && db_undecided "$med" && db_auto "$low" && db_nofixnow \
    && grep -qxF -- '- pending_decisions: 1 | fix_now_reentered: false' "$CASE_RF" \
    || { db_fail "(a) --non-interactive: MEDIUM '$(db_dec "$med")' '$(db_row "$med")', LOW '$(db_row "$low")'"; return 1; }
  # (b) pre-park cant_ask
  db_pre "$DB_LOW, {finding: \"Guard the empty list before indexing\", reason: \"out of scope\", source: issue_comments, severity: MEDIUM}" || { LEG_MSG="scratch (b)"; return 1; }
  db_call "$drv" "$CASE_DIR/seams.none" --result "$DB_READY"; db_lowmed
  [ "$(db_jq -r .do)" = ask ] && db_jq -e '.cant_ask | startswith("pending_decisions recorded — ")' >/dev/null || { db_fail "(b) want the ask"; return 1; }
  db_call "$drv" "$CASE_DIR/seams.none" --result '{"cant_ask":true}'
  [ "$DB_RC" = 0 ] && [ "$(db_jq -r .do)" = park ] && db_undecided "$med" && db_auto "$low" && db_nofixnow \
    && grep -qxF -- '- pending_decisions: 1 | fix_now_reentered: false' "$CASE_RF" \
    || { db_fail "(b) cant_ask: MEDIUM '$(db_dec "$med")' '$(db_row "$med")', LOW '$(db_row "$low")'"; return 1; }
  # (c) post-park cant_ask
  db_post || { LEG_MSG="scratch (c)"; return 1; }
  low="$(db_clone 66666666 LOW "A LOW one")"
  db_call "$drv" "$CASE_DIR/seams.from"
  [ "$(db_jq -r .do)" = ask ] || { db_fail "(c) want the ask"; return 1; }
  db_call "$drv" "$CASE_DIR/seams.none" --result '{"cant_ask":true}'
  [ "$DB_RC" = 0 ] && db_jq -e '.do == "park" and (.message | startswith("park written; decisions not asked (cant_ask)"))' >/dev/null \
    && db_undecided "$DB_D0" && db_auto "$low" && db_nofixnow || { db_fail "(c) post-park cant_ask"; return 1; }
  # (d) post-park --non-interactive: no gate read, no ask; the LOW one still followed up
  db_post || { LEG_MSG="scratch (d)"; return 1; }
  low="$(db_clone 66666666 LOW "A LOW one")"
  db_call "$drv" "$CASE_DIR/seams.from" --non-interactive
  [ "$DB_RC" = 0 ] && db_jq -e '.do == "park" and (.message | startswith("park written; decisions not asked (--non-interactive)"))' >/dev/null \
    && [ ! -s "$DB_ASKS" ] && db_undecided "$DB_D0" && db_auto "$low" && db_nofixnow || { db_fail "(d) post-park --non-interactive"; return 1; }
  return 0
}

# LOCK — a refused post-park run lock ⇒ nothing written, the drafts undecided
db_lock() {
  local drv="$1" low
  db_post || { LEG_MSG="scratch"; return 1; }
  low="$(db_clone 77777777 LOW "A LOW one")"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$CASE_BIN/nolock"; chmod +x "$CASE_BIN/nolock"
  printf 'NEXT_STEP_FROM=decide\nNEXT_STEP_LOCK_CMD=%s\n' "$CASE_BIN/nolock" > "$CASE_DIR/seams.nolock"
  db_call "$drv" "$CASE_DIR/seams.nolock"
  [ "$DB_RC" = 0 ] && db_jq -e '.do == "park" and (.message | contains("decisions not recorded (run lock held)"))' >/dev/null \
    && db_undecided "$low" && db_undecided "$DB_D0" && cmp -s "$FIX/$DB_POST/input.md" "$CASE_RF" \
    || { db_fail "lock refused: want the park, nothing written (LOW '$(db_dec "$low")' '$(db_row "$low")')"; return 1; }
  return 0
}

# GATE — a post-park `refuse — …` gate line ⇒ nothing asked, nothing written
db_refuse() {
  local drv="$1" low
  db_post || { LEG_MSG="scratch"; return 1; }
  db_gate "dismissed decisions not asked — refuse — no merge-watch marker for this PR"
  cp "$CASE_RF" "$CASE_DIR/rf.before"
  low="$(db_clone 88888888 LOW "A LOW one")"
  db_call "$drv" "$CASE_DIR/seams.from"
  [ "$DB_RC" = 0 ] && db_jq -e '.do == "park" and (.message | startswith("park written; decisions not asked (refuse — "))' >/dev/null \
    && [ ! -s "$DB_ASKS" ] && db_undecided "$low" && db_undecided "$DB_D0" && cmp -s "$CASE_DIR/rf.before" "$CASE_RF" \
    || { db_fail "refuse gate line: want the park, nothing written"; return 1; }
  return 0
}

for db_leg in "AC1:db_ac1:only LOW / INFO per-finding drafts ⇒ no question, each follow-up with the auto ledger column, all listed in the park's auto_followed_up + its message names the count and the hand-drop command" \
  "AC2:db_ac2:two MEDIUM + one LOW, fix-now available ⇒ ONE AUT-DISMISS question listing only the two MEDIUM (numbered, three labels); Fix selected (note 2) ⇒ that draft's fix-now spawn, the other MEDIUM and the LOW follow-up auto; post-park the D3 hand-off" \
  "AC3:db_ac3:PICK ⇒ no AUT-PENDING, the per-finding draft follow-up auto (interactive and --non-interactive); a refused --auto ⇒ AUT-PENDING is the fallback ask" \
  "AC4:db_ac4:MEDIUM drafts with no fix-now left (fix_now_reentered: true pre-park; a post-park ask — fix-now unavailable line) ⇒ no question, all follow-up auto" \
  "AC5:db_ac5:a canary title (quote, backticks, \$(…), fake ## Status) ⇒ nothing executes, the question quotes it as jq data, auto_followed_up holds only script-built paths, no new column-0 heading" \
  "AC8:db_ac8:Severity unspecified / missing ⇒ listed (MEDIUM+), LOW ⇒ not listed" \
  "AC9:db_ac9:Fix selected with an empty / non-numeric / out-of-range / malformed note (or none) ⇒ exit 2, nothing written, the ask re-prints; n = 1 offers no Fix selected (answering it ⇒ exit 2)" \
  "AC10:db_ac10:can't ask (--non-interactive / cant_ask, pre- and post-park) ⇒ MEDIUM+ undecided, the named outcome kept, no fix-now; below-MEDIUM still follow-up auto" \
  "LOCK:db_lock:a refused post-park run lock ⇒ nothing written, every draft undecided" \
  "GATE:db_refuse:a post-park refuse — gate line ⇒ nothing asked, nothing written"; do
  LEG_MSG=""; db_id="${db_leg%%:*}"; db_rest="${db_leg#*:}"; db_fn="${db_rest%%:*}"; db_what="${db_rest#*:}"
  if "$db_fn" "$DRIVER"; then ok "DB $db_id: $db_what"; else no "DB $db_id: $LEG_MSG"; fi
done

# PIN — each leg turns red under its own mutant (the brief's Pin mutations rows for this part, plus AC5/AC8/AC9)
if [ "${NS_SKIP_MUTANTS:-}" != 1 ]; then
  db_pin() { # <name> <leg fn> <anchor> <replacement> <what>
    local m
    LEG_MSG=""
    if m="$(build_mutant "db$1" "$3" "$4")"; then
      if "$2" "$m"; then no "DB pin $1: the leg stayed green with $5"
      else ok "DB pin $1: $5 ⇒ the leg turns red (${LEG_MSG:0:120})"; fi
    else no "DB pin $1: mutant not built ($5)"; fi
  }
  db_pin AC4 db_ac4 'st_set fixnow_offer true || st_set fixnow_offer false' 'st_set fixnow_offer true || st_set fixnow_offer true' \
    'fix-now always available'
  db_pin AC1 db_ac1 'case "$(ns_lc "$s")" in low|info) return 0 ;; *) return 1 ;; esac' 'case "$(ns_lc "$s")" in *) return 1 ;; esac' \
    'every severity classed MEDIUM+'
  db_pin AC2 db_ac2 'if [ "$kind" = finding ] && { [ "$(st fixnow_offer)" != true ] || ns_below_medium "$path"; }; then continue; fi' 'if false; then continue; fi' \
    'the ask built from every undecided per-finding draft'
  db_pin AC3 db_ac3 '    [ -n "$apath" ] || continue' '    [ "$akind" = summary ] && [ -n "$apath" ] || continue' \
    'the PICK auto-follow-up restricted to summary drafts'
  db_pin AC10 db_ac10 '      st_del queue; st_del batch; st_del answers' \
    '      st_setj answers "$(st batch | "$JQ" -c '"'"'map({draft: .path, name: .name, title: .title, decision: "fix-now"})'"'"')"; ns_decide_complete "$post"; return' \
    'a cant_ask answer recording every listed draft fix-now'
  db_pin AC5 db_ac5 '"$JQ" -cn --arg k "$kind" --arg p "$path" --arg n "${path##*/}" --arg t "$t" '"'"'{kind: $k, path: $p, name: $n, title: $t}'"'" \
    '"$JQ" -cn --arg k "$kind" --arg p "$path" --arg n "${path##*/}" "{kind: \$k, path: \$p, name: \$n, title: \"$t\"}"' \
    'the title spliced into the jq program instead of --arg'
  db_pin AC8 db_ac8 'low|info) return 0' 'low|info|unspecified) return 0' 'unspecified classed below MEDIUM'
  db_pin AC9 db_ac9 '[ "$w" -ge 1 ] && [ "$w" -le "$n" ] || return 1' 'true || return 1' 'the 1..n note range check skipped'
fi
