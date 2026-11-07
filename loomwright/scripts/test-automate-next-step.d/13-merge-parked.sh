# test-automate-next-step.d/13-merge-parked.sh — part of test-automate-next-step.sh (TNS_PARTS / TNS_GROUPS / its
# `pg_want 13-merge-parked` line): `automate-next-step.sh --merge-parked` (merge ONE parked awaiting_merge item
# through the existing gate, then stop), the durable `- ready_sha:` READY record and `--resume --auto-merge`'s
# park message. Sourced by the runner (its setup, helpers and counters); run directly — e.g. by
# run-pin-mutations.sh — it re-enters the runner for this part alone.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  exec "${BASH:-bash}" "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test-automate-next-step.sh" --part 13-merge-parked
fi
#
# THE CASE: reconcile-closeout-merged's run (item 39a parked awaiting_merge after a READY drain, safe mode, two
# undecided dismissed drafts), its ## Current given a `- ready_sha:` line at the scratch checkout's HEAD. `gh`
# is the table stub plus a call log; `automate-helpers.sh` is a SPY beside the driver (every call passes through
# to the real one except two): `gate-eval` records its argv and a copy of the ctx and prints MP_GATE_OUT
# (default MERGE) — the real gate is unchanged and has its own suites; `closeout` records its argv and does what
# a clean real closeout does to the run file (queue-checkoff, ## Current done / awaiting_go), or prints one
# leftover (MP_CLOSEOUT_LEFTOVER). Honest limit: the real gate-eval and the real closeout are not run here.
# LEGS (each names the acceptance criterion it pins; PIN turns each red under the brief's Pin mutations rows):
#   AC1/AC2/AC4  MERGE ⇒ gate-eval once, closeout once WITH its trail (no --no-trail, --session-id), one check-off,
#         items remain ⇒ paused awaiting_go with the entry's own message, no picked line, no spawn, mode: safe
#   AC3   no items remain ⇒ the done termination (## Status: done, its trail-pr line)
#   AC5   --resume first (the sidecar wiped), then the entry: the ctx carries the recorded ready_sha, READY, tr
#   AC6/AC24  drain-result: a fix-now re-drain rewrites the line in place (its sha + tr); a READY report with no
#         ready_sha writes none; an item-form current-set that changes the item drops it (runfile.sh)
#   AC7–AC10, AC15  the guard parks (head moved, late feedback, behind_by, checkout off the head, no line), never
#         calling gate-eval; a comment 1 s before ready_at does not park
#   AC11  the run lock is held across gate-eval (a lock-less acquire — a merge watcher's closeout — is refused
#         then), one closeout, one check-off, the lock free and ## Current done afterwards
#   AC12  a park keeps awaiting_merge + one PARK line, releases the lock, arms a watcher only when none is live;
#         a gate PARK never reruns the decision step
#   AC13  undecided per-finding drafts stay undecided after MERGE     AC14  --resume --auto-merge on the parked open PR
#   AC16/AC17  refusals: exit 2, .supervisor/ byte-unchanged, no lock      AC18  MERGED / CLOSED at entry
#   LEFT  a closeout leftover kept ⇒ the entry's tail (awaiting_go)        HOST  LOOMWRIGHT_HOST_STATE_DIR untouched
#   UNREAD  the fail-CLOSED reads (PR head, feedback, compare) park; a held run lock refuses (exit 2, nothing written)
#   RACE  a merge watcher's closeout finishing while the lock is taken ⇒ released, refused by name, no gate, no closeout
echo "-- MP. --merge-parked: one parked item through the existing gate, the durable READY record"

MP_CASE=reconcile-closeout-merged
MP_ITEM=.supervisor/requirements/automate-followups/39a-sweep-and-janitor.md
MP_PR=https://github.com/vikashruhilgit/loomwright/pull/555
MP_API=repos/vikashruhilgit/loomwright
MP_SID=auto-2026-11-06-130000
MP_RA=2026-10-15T09:53:21Z
MP_MSG_GATE="merged through gate-eval by --merge-parked — the item is closed out; the next item waits for /automate --resume"

# mp_spy <driver> — a scripts/ dir: <driver> + the helper spy, every other entry a symlink; prints its driver path
mp_spy() {
  local d e; d="$(mktemp -d "$WORK/mp-spy.XXXXXX")" || return 1
  for e in "$HERE"/*; do case "${e##*/}" in automate-next-step.sh|automate-helpers.sh) ;; *) ln -s "$e" "$d/${e##*/}" ;; esac; done
  ln -s "$1" "$d/automate-next-step.sh"
  { printf '#!/usr/bin/env bash\nREAL_DIR=%q\n' "$HERE"; cat <<'SPY'
case "${1:-}" in
  gate-eval)
    printf 'helper gate-eval %s\n' "$*" >> "$NS_REC_LOG"
    [ -z "${MP_CTX_COPY:-}" ] || cp "$3" "$MP_CTX_COPY"
    if [ -n "${MP_LOCKPROBE:-}" ]; then
      bash "$REAL_DIR/run-lock.sh" acquire --owner merge-watch-probe >/dev/null 2>&1; rc=$?; echo "$rc" >> "$MP_LOCKPROBE"
      [ "$rc" != 0 ] || bash "$REAL_DIR/run-lock.sh" release --owner merge-watch-probe >/dev/null 2>&1
    fi
    printf '%s\n' "${MP_GATE_OUT:-MERGE}"; exit 0 ;;
  closeout)
    printf 'helper closeout %s\n' "$*" >> "$NS_REC_LOG"
    if [ -n "${MP_CLOSEOUT_LEFTOVER:-}" ]; then echo "closeout: bogus — left behind"; exit 0; fi
    bash "$REAL_DIR/automate-helpers.sh" queue-checkoff "$2" "$3" >/dev/null 2>&1
    bash "$REAL_DIR/automate-helpers.sh" current-set "$2" --item "$3" --status done --pause-reason awaiting_go >/dev/null 2>&1
    printf 'closeout: checked — - [x] %s\ncloseout: reconciled — ## Current %s status done, pause_reason awaiting_go\n' "$3" "$3"
    exit 0 ;;
esac
exec bash "$REAL_DIR/automate-helpers.sh" "$@"
SPY
  } > "$d/automate-helpers.sh" && printf '%s/automate-next-step.sh' "$d"
}
# mp_gh <live head> <state OPEN|MERGED|CLOSED> <issue comments json> <reviews json> <behind_by> — the gh table
mp_gh() {
  local ma=null; [ "$2" = MERGED ] && ma='"2026-10-15T10:49:00Z"'
  { printf '0\tpr view %s --json state,mergedAt\t{"state":"%s","mergedAt":%s}\n' "$MP_PR" "$2" "$ma"
    printf '0\tpr view %s --json headRefOid,headRefName,baseRefName\t{"headRefOid":"%s","headRefName":"feature/af39a-sweep","baseRefName":"main"}\n' "$MP_PR" "$1"
    printf '0\tapi %s/issues/555/comments --paginate\t%s\n0\tapi %s/pulls/555/reviews --paginate\t%s\n' "$MP_API" "$3" "$MP_API" "$4"
    printf '0\tapi %s/pulls/555/comments --paginate\t[]\n0\tapi %s/compare/main...*\t{"behind_by":%s}\n' "$MP_API" "$MP_API" "$5"
    printf '0\tauth status*\t\n0\tpr list --state open *\t[]\n0\tpr list *\t[]\n0\tpr create *\thttps://github.com/vikashruhilgit/loomwright/pull/560\n'
  } > "$CASE_GH"
}
# mp_new [ready line | -] — the scratch case; the default ready line names HEAD, `-` writes none
mp_new() {
  new_scratch "$FIX/$MP_CASE" || return 1
  MP_HEAD="$(git -C "$CASE_ROOT" rev-parse HEAD)"
  local rl="${1:-- ready_sha: $MP_HEAD | ready_at: $MP_RA | termination_reason: converged}"
  if [ "$rl" != - ]; then
    MP_L="$rl" awk 'BEGIN { l = ENVIRON["MP_L"] } { print } /^- pending_decisions: / && !d { print l; d = 1 }' "$CASE_RF" > "$CASE_RF.t" && mv "$CASE_RF.t" "$CASE_RF" || return 1
  fi
  { printf '#!/usr/bin/env bash\nprintf "gh %%s\\n" "$*" >> "$NS_REC_LOG"\n'; printf '%s' "$GH_STUB_BODY" | sed 1d; } > "$CASE_BIN/gh"; chmod +x "$CASE_BIN/gh"
  f_claude 1   # a --resume leg runs phase-check, which reads `claude --help`: never the machine's own claude (CI has none)
  mp_gh "$MP_HEAD" OPEN '[{"created_at":"2026-10-15T09:53:20Z"}]' '[]' 0
  MP_SEAMS="$CASE_DIR/seams.mp"
  printf 'MP_CTX_COPY=%s\nLOOMWRIGHT_PROC_REGISTRY_DIR=%s\n' "$CASE_DIR/ctx.json" "$CASE_ROOT/.procs" > "$MP_SEAMS"
}
mp_seam() { printf '%s\n' "$@" >> "$MP_SEAMS"; }
mp_call() { # <spy driver> [args…] — the entry; sets MP_OUT MP_RC MP_ERR
  local drv="$1"; shift
  MP_OUT="$(NS_FRESH=1 in_case "$drv" "$MP_SEAMS" bash "$drv" --merge-parked "$CASE_ROOT/.supervisor/automate" --run "$CASE_RUN" --session-id "$MP_SID" "$@" 2>"$CASE_DIR/mp.err")"; MP_RC=$?
  MP_ERR="$(cat "$CASE_DIR/mp.err")"
}
mp_fail() { LEG_MSG="$1 — exit $MP_RC, printed '${MP_OUT:0:240}' ${MP_ERR:0:240}"; return 1; }
mp_j() { printf '%s' "$MP_OUT" | jq -e "$@" >/dev/null 2>&1; }
mp_n() { grep -c -- "$1" "$CASE_DIR/rec.log" | tr -d ' '; }   # spy / gh / rec lines
mp_safe() { grep -qx -- '- mode: safe | limit: 5 | trust_unprotected: false' "$CASE_RF" && ! grep -q '"do":"spawn"' <<<"$MP_OUT"; }
mp_park() { # <reason> — the guard / gate park: exit 0, awaiting_merge kept, ONE PARK line, gate-eval never called
  mp_j --arg r "$1" '.do == "park" and .step == "merge-park" and .pause_reason == "awaiting_merge" and (.message | startswith("PARK: " + $r))' \
    && grep -q "^- item: $MP_ITEM | status: awaiting_merge " "$CASE_RF" && [ "$(grep -c " merge-parked $MP_PR — PARK: $1 " "$CASE_RF")" = 1 ] \
    && [ "$(mp_n '^helper gate-eval')" = 0 ] && mp_safe
}

mp_ac1() { # AC1 / AC2 / AC4
  local drv; drv="$(mp_spy "$1")" && mp_new || { LEG_MSG="scratch"; return 1; }
  cp "$CASE_RF" "$CASE_DIR/before.md"
  mp_call "$drv"
  [ "$MP_RC" = 0 ] && mp_j --arg m "$MP_MSG_GATE" '.do == "park" and .step == "awaiting-go" and .pause_reason == "awaiting_go" and .message == $m' || { mp_fail "MERGE: not the entry's awaiting_go stop"; return 1; }
  [ "$(mp_n '^helper gate-eval')" = 1 ] && [ "$(mp_n '^helper closeout ')" = 1 ] && grep -q "^helper closeout .* --session-id $MP_SID" "$CASE_DIR/rec.log" \
    && [ "$(mp_n '--no-trail')" = 0 ] || { mp_fail "gate-eval / closeout: $(grep '^helper' "$CASE_DIR/rec.log" | tr '\n' ';')"; return 1; }
  [ "$(grep -cxF -- "- [x] $MP_ITEM" "$CASE_RF")" = 1 ] && [ "$(grep -c " checked off $MP_ITEM — merged $MP_PR; remaining: 1" "$CASE_RF")" = 1 ] \
    && grep -q ' gate-eval: MERGE$' "$CASE_RF" && grep -qx '## Status: paused' "$CASE_RF" && grep -qx -- '- pause_reason: awaiting_go' "$CASE_RF" \
    || { mp_fail "the check-off / MERGE line / awaiting_go state"; return 1; }
  [ "$(grep -c ' picked ' "$CASE_RF")" = "$(grep -c ' picked ' "$CASE_DIR/before.md")" ] || { mp_fail "a picked line"; return 1; }
  mp_safe && [ "$(mp_n '^gh pr merge')" = 0 ] || { mp_fail "a spawn, a Run Config write or a gh pr merge outside gate-eval"; return 1; }
}
mp_ac3() {
  local drv; drv="$(mp_spy "$1")" && mp_new || { LEG_MSG="scratch"; return 1; }
  in_case "$drv" "$MP_SEAMS" bash "$H" queue-checkoff "$CASE_RF" .supervisor/requirements/parallel-automate/18-backlog-board-and-right-size.md >/dev/null 2>&1
  mp_call "$drv"
  [ "$MP_RC" = 0 ] && mp_j '.do == "done" and .step == "terminate" and .status == "done" and .remaining == 0' && grep -qx '## Status: done' "$CASE_RF" \
    && grep -qE '^- [0-9TZ:-]+ trail-pr: ' "$CASE_RF" && grep -q ' sweep (dry run): ' "$CASE_RF" || { mp_fail "no items remain: not the done termination with its trail"; return 1; }
}
mp_ac5() {
  local drv; drv="$(mp_spy "$1")" && mp_new || { LEG_MSG="scratch"; return 1; }
  NS_FRESH=1 in_case "$drv" "$MP_SEAMS" bash "$drv" --resume "$CASE_ROOT/.supervisor/automate" --run "$CASE_RUN" --session-id "$MP_SID" >"$CASE_DIR/res.out" 2>&1
  jq -e '.do == "park" and .step == "reconcile"' "$CASE_DIR/res.out" >/dev/null 2>&1 || { LEG_MSG="--resume did not park at reconcile: $(head -c 200 "$CASE_DIR/res.out")"; return 1; }
  mp_call "$drv"
  [ "$MP_RC" = 0 ] && jq -e --arg s "$MP_HEAD" '.ready_sha == $s and .drain_result == "READY" and .termination_reason == "converged"' "$CASE_DIR/ctx.json" >/dev/null 2>&1 \
    || { mp_fail "the ctx after --resume: $(cat "$CASE_DIR/ctx.json" 2>/dev/null)"; return 1; }
}
# mp_redrain <driver> <pre-existing ready line|-> <report extra json> — the fix-now re-drain through drain-result
mp_redrain() {
  local c="$FIX/dismissed-fix-now-re-drain" rep
  new_scratch "$c" || return 1
  if [ "$2" != - ]; then MP_L="$2" awk 'BEGIN { l = ENVIRON["MP_L"] } { print } /^- owned_drain_started: / && !d { print l; d = 1 }' "$CASE_RF" > "$CASE_RF.t" && mv "$CASE_RF.t" "$CASE_RF"; fi
  rep="$(jq -cn --argjson x "$3" '{review_heal_result: "REVIEW_HEAL_RESULT:\n  schema_version: 2\n  decision: READY\n  iterations: 1\n  rounds: 1\n  fix_cycles: 1\n  termination_reason: bound_hit\n  rules_gate: none", head_sha: "953c2d1bbf14"} + $x')"
  { grep '^sidecar: ' "$c/next-step.results"; printf 'sidecar: %s\n' "'{\"termination_reason\":\"converged\"}'"
    printf 'env: NEXT_STEP_FROM=fix-now\ncall:\nexpect: spawn\nenv: NEXT_STEP_FROM= NEXT_STEP_UNTIL=drain-result\ncall: --result %q\nexpect: none\n' "$rep"; } > "$CASE_DIR/rd.results"
  drive "$c" "$1" "$CASE_DIR/rd.results"
}
mp_ac6() {
  mp_redrain "$1" "- ready_sha: aaaaaaa | ready_at: $MP_RA | termination_reason: converged" '{"ready_sha":"953c2d1bbf14"}' || { LEG_MSG="scratch"; return 1; }
  [ -z "$DRIVE_ERR" ] && [ "$(grep -c '^- ready_sha: ' "$CASE_RF")" = 1 ] && grep -qE '^- ready_sha: 953c2d1bbf14 \| ready_at: [0-9TZ:-]+ \| termination_reason: bound_hit$' "$CASE_RF" \
    || { LEG_MSG="re-drain: $(grep '^- ready_sha' "$CASE_RF" | tr '\n' ';') ${DRIVE_ERR:0:200}"; return 1; }
}
mp_ac24() {
  local m="${2:-$HERE/automate-helpers.sh}"
  mp_redrain "$1" - '{}' || { LEG_MSG="scratch"; return 1; }
  [ -z "$DRIVE_ERR" ] && ! grep -q '^- ready_sha:' "$CASE_RF" || { LEG_MSG="a READY report without ready_sha wrote: $(grep '^- ready_sha' "$CASE_RF") ${DRIVE_ERR:0:160}"; return 1; }
  mp_new || { LEG_MSG="scratch"; return 1; }
  bash "$m" current-set "$CASE_RF" --item "$MP_ITEM" --status running >/dev/null 2>&1 && grep -q '^- ready_sha: ' "$CASE_RF" || { LEG_MSG="a same-item current-set dropped the line"; return 1; }
  bash "$m" current-set "$CASE_RF" --item .supervisor/requirements/parallel-automate/18-backlog-board-and-right-size.md --status running >/dev/null 2>&1 \
    && ! grep -q '^- ready_sha: ' "$CASE_RF" || { LEG_MSG="an item change kept the line"; return 1; }
}
mp_ac7() { # the checkout and the live head agree, so only the recorded ready_sha can differ
  local drv; drv="$(mp_spy "$1")" && mp_new "- ready_sha: 2222222222222222222222222222222222222222 | ready_at: $MP_RA | termination_reason: converged" || { LEG_MSG="scratch"; return 1; }
  mp_call "$drv"
  [ "$MP_RC" = 0 ] && mp_park head_sha_moved && mp_j '.message | contains("a person must decide")' || { mp_fail "head moved: not the head_sha_moved park"; return 1; }
}
mp_ac8() {
  local drv; drv="$(mp_spy "$1")" && mp_new || { LEG_MSG="scratch"; return 1; }
  mp_gh "$MP_HEAD" OPEN '[{"created_at":"2026-10-15T09:55:00Z"}]' '[]' 0
  mp_call "$drv"
  [ "$MP_RC" = 0 ] && mp_park ready_stale_feedback || { mp_fail "a comment after ready_at"; return 1; }
  mp_new && mp_gh "$MP_HEAD" OPEN '[]' '[{"submitted_at":"2026-10-15T10:00:00Z","state":"COMMENTED"}]' 0 || { LEG_MSG="scratch"; return 1; }
  mp_call "$drv"
  [ "$MP_RC" = 0 ] && mp_park ready_stale_feedback || { mp_fail "a review after ready_at"; return 1; }
}
mp_ac9() {
  local drv; drv="$(mp_spy "$1")" && mp_new || { LEG_MSG="scratch"; return 1; }
  mp_gh "$MP_HEAD" OPEN '[]' '[]' 2
  mp_call "$drv"
  [ "$MP_RC" = 0 ] && mp_park base_moved_since_ready || { mp_fail "behind_by 2"; return 1; }
}
mp_ac10() {
  local drv live=3333333333333333333333333333333333333333 st0; drv="$(mp_spy "$1")" && mp_new "- ready_sha: $live | ready_at: $MP_RA | termination_reason: converged" || { LEG_MSG="scratch"; return 1; }
  mp_gh "$live" OPEN '[]' '[]' 0
  st0="$(git -C "$CASE_ROOT" status --porcelain -uall | grep -v '^?? .supervisor/')"
  mp_call "$drv"
  [ "$MP_RC" = 0 ] && mp_park checkout_not_on_pr_head && mp_j '.message | contains("git checkout feature/af39a-sweep")' \
    && [ "$(git -C "$CASE_ROOT" rev-parse HEAD)" = "$MP_HEAD" ] && [ "$(git -C "$CASE_ROOT" status --porcelain -uall | grep -v '^?? .supervisor/')" = "$st0" ] \
    || { mp_fail "checkout off the PR head"; return 1; }
}
mp_ac15() {
  local drv; drv="$(mp_spy "$1")" && mp_new - || { LEG_MSG="scratch"; return 1; }
  mp_call "$drv"
  [ "$MP_RC" = 0 ] && mp_park ready_sha_missing && mp_j '.message | contains("never substituted")' || { mp_fail "no ready_sha line"; return 1; }
}
mp_ac11() {
  local drv; drv="$(mp_spy "$1")" && mp_new || { LEG_MSG="scratch"; return 1; }
  mp_seam "MP_LOCKPROBE=$CASE_DIR/probe"
  NS_REAL_LOCK=1 mp_call "$drv"
  [ "$MP_RC" = 0 ] && [ "$(cat "$CASE_DIR/probe" 2>/dev/null)" != 0 ] && [ -s "$CASE_DIR/probe" ] || { mp_fail "the run lock was not held across gate-eval (probe: $(cat "$CASE_DIR/probe" 2>/dev/null))"; return 1; }
  ( cd "$CASE_ROOT" && bash "$HERE/run-lock.sh" acquire --owner merge-watch-probe >/dev/null 2>&1 && bash "$HERE/run-lock.sh" release --owner merge-watch-probe >/dev/null 2>&1 ) \
    || { mp_fail "the run lock is still held after the entry"; return 1; }
  [ "$(mp_n '^helper closeout ')" = 1 ] && [ "$(grep -c " checked off $MP_ITEM " "$CASE_RF")" = 1 ] && grep -q "^- item: $MP_ITEM | status: done " "$CASE_RF" \
    || { mp_fail "not one closeout / one check-off / ## Current done for the watcher"; return 1; }
}
mp_ac12() {
  local drv wp; drv="$(mp_spy "$1")" && mp_new || { LEG_MSG="scratch"; return 1; }
  mp_gh "$MP_HEAD" OPEN '[]' '[]' 4
  mp_call "$drv"
  [ "$MP_RC" = 0 ] && mp_park base_moved_since_ready && grep -q "^lock acquire --owner automate:$CASE_RUN" "$CASE_DIR/rec.log" \
    && grep -q "^lock release --owner automate:$CASE_RUN" "$CASE_DIR/rec.log" && [ "$(mp_n '^watch ')" = 1 ] || { mp_fail "park: lock / one watcher: $(tr '\n' ';' < "$CASE_DIR/rec.log" | cut -c1-300)"; return 1; }
  mp_new && mp_gh "$MP_HEAD" OPEN '[]' '[]' 4 || { LEG_MSG="scratch"; return 1; }
  mkdir -p "$CASE_DIR/w"; printf 'while :; do sleep 1; done\n' > "$CASE_DIR/w/automate-merge-watch.sh"
  bash "$CASE_DIR/w/automate-merge-watch.sh" "$CASE_RF" item "$MP_PR" </dev/null >/dev/null 2>&1 & wp=$!
  WAIT_LIB_WHAT="the stand-in watcher" wait_for_cmd 5 bash -c "grep -q automate-merge-watch.sh < <(ps -ww -p $wp -o command=)"
  printf 'pid\t%s\npr_url\t%s\n' "$wp" "$MP_PR" > "$CASE_ROOT/.supervisor/automate/$CASE_RUN.merge-watch"
  mp_call "$drv"; kill "$wp" 2>/dev/null; wait "$wp" 2>/dev/null
  [ "$MP_RC" = 0 ] && mp_park base_moved_since_ready && [ "$(mp_n '^watch ')" = 0 ] || { mp_fail "a live watcher: a second one was armed"; return 1; }
  mp_new || { LEG_MSG="scratch"; return 1; }
  cp "$CASE_RF" "$CASE_DIR/before.md"; mp_seam "MP_GATE_OUT=PARK: checks_not_green"
  mp_call "$drv"
  [ "$MP_RC" = 0 ] && mp_j '.step == "merge-park" and (.message | startswith("PARK: checks_not_green"))' && grep -q " merge-parked $MP_PR — PARK: checks_not_green " "$CASE_RF" \
    && ! grep -q 'dismissed-drafts' < <(diff "$CASE_DIR/before.md" "$CASE_RF") && ! grep -q ' parked awaiting_merge ' < <(diff "$CASE_DIR/before.md" "$CASE_RF") \
    && grep -q "^lock release " "$CASE_DIR/rec.log" || { mp_fail "a gate PARK: the decision step ran or the lock was kept"; return 1; }
}
mp_ac13() {
  local drv f bad=""; drv="$(mp_spy "$1")" && mp_new || { LEG_MSG="scratch"; return 1; }
  mp_call "$drv"
  for f in "$CASE_ROOT/.supervisor/requirements/proposed/$CASE_RUN"--*dismissed-*.md; do
    # per-finding drafts only: dismissed-drafts itself records a below-MEDIUM summary `follow-up auto` on every path
    case "$f" in *--dismissed-summary*) continue ;; esac
    [ -f "$f" ] && [ "$(sed -n 's/^- \*\*Decision:\*\* //p' "$f" | head -n 1)" != undecided ] && bad="$bad ${f##*/}"
  done
  [ "$MP_RC" = 0 ] && [ -z "$bad" ] && grep -q '^- pending_decisions: ' "$CASE_RF" || { mp_fail "drafts decided after MERGE:$bad"; return 1; }
}
mp_ac14() {
  local drv; drv="$(mp_spy "$1")" && mp_new || { LEG_MSG="scratch"; return 1; }
  NS_FRESH=1 in_case "$drv" "$MP_SEAMS" bash "$drv" --resume "$CASE_ROOT/.supervisor/automate" --run "$CASE_RUN" --session-id "$MP_SID" --mode auto-merge >"$CASE_DIR/res.out" 2>/dev/null
  jq -e --arg r "$CASE_RUN" '.do == "park" and .step == "reconcile" and (.message | contains("--auto-merge was not applied") and contains("/automate --merge-parked " + $r))' "$CASE_DIR/res.out" >/dev/null 2>&1 \
    && ! jq -e 'has("flag_mode")' "$CASE_ROOT/.supervisor/automate/$CASE_RUN.next-step.json" >/dev/null 2>&1 \
    || { LEG_MSG="--resume --auto-merge: $(head -c 300 "$CASE_DIR/res.out"); sidecar flag_mode $(jq -r '.flag_mode // "absent"' "$CASE_ROOT/.supervisor/automate/$CASE_RUN.next-step.json" 2>/dev/null)"; return 1; }
  mp_new || { LEG_MSG="scratch"; return 1; }
  NS_FRESH=1 in_case "$drv" "$MP_SEAMS" bash "$drv" --resume "$CASE_ROOT/.supervisor/automate" --run "$CASE_RUN" --session-id "$MP_SID" >"$CASE_DIR/res.out" 2>/dev/null
  jq -e '.do == "park" and (.message | contains("--merge-parked") | not)' "$CASE_DIR/res.out" >/dev/null 2>&1 || { LEG_MSG="plain --resume: the message changed"; return 1; }
}
# mp_refused <what> <stderr needle> — exit 2, nothing on stdout, .supervisor/ byte-unchanged, no lock taken
mp_refused() {
  [ "$MP_RC" = 2 ] && [ -z "$MP_OUT" ] && grep -qF -- "$2" <<<"$MP_ERR" && [ "$(snapshot)" = "$MP_SNAP" ] && [ "$(mp_n '^lock ')" = 0 ] || { mp_fail "$1: not refused with nothing written"; return 1; }
}
mp_ac16() {
  local drv s; drv="$(mp_spy "$1")" || { LEG_MSG="spy"; return 1; }
  for s in escalated ready_for_release running done ESCALATED-drain; do
    mp_new || { LEG_MSG="scratch"; return 1; }
    case "$s" in
      ESCALATED-drain) sed -i.bak 's/| owned_drain_result: READY |/| owned_drain_result: ESCALATED |/' "$CASE_RF" && rm -f "$CASE_RF.bak"; s=awaiting_merge ;;
      *) bash "$H" current-set "$CASE_RF" --item "$MP_ITEM" --status "$s" >/dev/null 2>&1 || { LEG_MSG="seed $s"; return 1; } ;;
    esac
    MP_SNAP="$(snapshot)"; mp_call "$drv"; mp_refused "status $s" "merge_parked_not_awaiting_merge — ## Current reads status: $s" || return 1
  done
}
mp_race() { # the lock stub moves ## Current as it is acquired: the gap between the entry's first reads and its lock
  local drv; drv="$(mp_spy "$1")" && mp_new || { LEG_MSG="scratch"; return 1; }
  { printf '#!/usr/bin/env bash\nprintf "lock %%s\\n" "$1" >> "$NS_REC_LOG"\n'
    printf '[ "$1" != acquire ] || bash %q current-set "$RF" --item %q --status done --pause-reason awaiting_go >/dev/null 2>&1\nexit 0\n' "$H" "$MP_ITEM"
  } > "$CASE_BIN/racelock"; chmod +x "$CASE_BIN/racelock"; mp_seam "NEXT_STEP_LOCK_CMD=$CASE_BIN/racelock"
  mp_call "$drv"
  [ "$MP_RC" = 2 ] && [ -z "$MP_OUT" ] && grep -qF 'merge_parked_state_changed — ' <<<"$MP_ERR" && [ "$(mp_n '^helper gate-eval')" = 0 ] && [ "$(mp_n '^helper closeout')" = 0 ] && [ "$(mp_n '^lock release')" = 1 ] \
    || { mp_fail "a closeout in the lock gap: not released and refused with no gate and no closeout"; return 1; }
}
mp_ac17() {
  local drv; drv="$(mp_spy "$1")" && mp_new || { LEG_MSG="scratch"; return 1; }
  printf '{"lane":"L1","parallel":2}\n' > "$CASE_ROOT/.supervisor/lane.json"
  MP_SNAP="$(snapshot)"; mp_call "$drv"; mp_refused lane merge_parked_in_lane || return 1
  mp_new || { LEG_MSG="scratch"; return 1; }
  awk '{ print } /^- auto_review_original: / { print "- parallel: 2" }' "$CASE_RF" > "$CASE_RF.t" && mv "$CASE_RF.t" "$CASE_RF"
  MP_SNAP="$(snapshot)"; mp_call "$drv"; mp_refused "parallel parent" merge_parked_parallel_parent
}
mp_ac18() {
  local drv; drv="$(mp_spy "$1")" && mp_new || { LEG_MSG="scratch"; return 1; }
  mp_gh "$MP_HEAD" MERGED '[]' '[]' 0
  mp_call "$drv"
  [ "$MP_RC" = 0 ] && mp_j '.step == "awaiting-go" and (.message | startswith("PR already merged — closed out by --merge-parked"))' && [ "$(mp_n '^helper gate-eval')" = 0 ] \
    && [ "$(mp_n '^helper closeout ')" = 1 ] && [ "$(mp_n '--no-trail')" = 0 ] && [ "$(grep -c " checked off $MP_ITEM " "$CASE_RF")" = 1 ] && mp_safe \
    || { mp_fail "MERGED at entry: not closed out with no gate"; return 1; }
  mp_new && mp_gh "$MP_HEAD" CLOSED '[]' '[]' 0 || { LEG_MSG="scratch"; return 1; }
  mp_call "$drv"
  [ "$MP_RC" = 0 ] && mp_j '.do == "park" and .step == "merge-parked" and (.message | contains("reads gone"))' && grep -qxF -- "- [ ] $MP_ITEM" "$CASE_RF" \
    && ! grep -q ' checked off ' "$CASE_RF" && [ "$(mp_n '^helper ')" = 0 ] || { mp_fail "CLOSED at entry: checked off or closed out"; return 1; }
}
mp_left() {
  local drv; drv="$(mp_spy "$1")" && mp_new || { LEG_MSG="scratch"; return 1; }
  mp_seam MP_CLOSEOUT_LEFTOVER=1
  mp_call "$drv"
  [ "$MP_RC" = 0 ] && mp_j '.do == "ask" and .gate == "AUT-LEFTOVER"' || { mp_fail "leftover: not the AUT-LEFTOVER ask"; return 1; }
  MP_OUT="$(NS_FRESH=1 in_case "$drv" "$MP_SEAMS" bash "$drv" "$CASE_RF" --result '{"answers":["Keep and continue"]}' 2>"$CASE_DIR/mp.err")"; MP_RC=$?; MP_ERR="$(cat "$CASE_DIR/mp.err")"
  [ "$MP_RC" = 0 ] && mp_j --arg m "$MP_MSG_GATE" '.step == "awaiting-go" and .message == $m' || { mp_fail "leftover kept: not the entry's tail"; return 1; }
}
mp_host() {
  local drv h; drv="$(mp_spy "$1")" && mp_new || { LEG_MSG="scratch"; return 1; }
  h="$CASE_DIR/host-state"; mkdir -p "$h"; mp_seam "LOOMWRIGHT_HOST_STATE_DIR=$h"
  mp_call "$drv"
  [ "$MP_RC" = 0 ] && [ -z "$(ls -A "$h")" ] && grep -q ' gate-eval: MERGE$' "$CASE_RF" && [ -s "$CASE_ROOT/.supervisor/automate/$CASE_RUN.next-step.json" ] \
    || { mp_fail "host mode: wrote under LOOMWRIGHT_HOST_STATE_DIR ($(ls -A "$h" | tr '\n' ' ')) or not the automate dir"; return 1; }
}
mp_usage() {
  local drv; drv="$(mp_spy "$1")" && mp_new || { LEG_MSG="scratch"; return 1; }
  MP_SNAP="$(snapshot)"
  for a in "--resume $CASE_ROOT/.supervisor/automate" "--start pick" "--result {}"; do
    # shellcheck disable=SC2086
    mp_call "$drv" $a; [ "$MP_RC" = 2 ] && [ "$(snapshot)" = "$MP_SNAP" ] || { mp_fail "--merge-parked with $a"; return 1; }
  done
  ! grep -qE '(gh|GH")? pr merge' "$1" || { LEG_MSG="the driver names a pr merge"; return 1; }
}

# mp_row <gh pattern> <rc> <output> — one gh table row replaced (the rest of the table kept)
mp_row() { MP_P="$1" MP_C="$2" MP_O="$3" awk -F'\t' 'BEGIN { OFS = "\t" } $2 == ENVIRON["MP_P"] { $1 = ENVIRON["MP_C"]; $3 = ENVIRON["MP_O"] } { print }' "$CASE_GH" > "$CASE_GH.t" && mv "$CASE_GH.t" "$CASE_GH"; }
mp_unread() { # the fail-CLOSED branches: an unreadable PR head / feedback / base read parks; a late review comment parks; a held lock refuses
  local drv; drv="$(mp_spy "$1")" || { LEG_MSG="spy"; return 1; }
  mp_new && mp_row "pr view $MP_PR --json headRefOid,headRefName,baseRefName" 1 "" || { LEG_MSG="scratch"; return 1; }
  mp_call "$drv"; [ "$MP_RC" = 0 ] && mp_park pr_unreadable || { mp_fail "pr view unreadable"; return 1; }
  mp_new && mp_row "api $MP_API/pulls/555/comments --paginate" 1 "" || { LEG_MSG="scratch"; return 1; }
  mp_call "$drv"; [ "$MP_RC" = 0 ] && mp_park feedback_unreadable || { mp_fail "review comments unreadable"; return 1; }
  mp_new && mp_row "api $MP_API/pulls/555/comments --paginate" 0 '[{"created_at":"2026-10-15T11:00:00Z"}]' || { LEG_MSG="scratch"; return 1; }
  mp_call "$drv"; [ "$MP_RC" = 0 ] && mp_park ready_stale_feedback || { mp_fail "a review comment after ready_at"; return 1; }
  mp_new && mp_row "api $MP_API/compare/main...*" 0 '{"message":"Not Found"}' || { LEG_MSG="scratch"; return 1; }
  mp_call "$drv"; [ "$MP_RC" = 0 ] && mp_park base_unreadable || { mp_fail "compare unreadable"; return 1; }
  mp_new || { LEG_MSG="scratch"; return 1; }
  printf '#!/usr/bin/env bash\nexit 1\n' > "$CASE_BIN/nolock"; chmod +x "$CASE_BIN/nolock"; mp_seam "NEXT_STEP_LOCK_CMD=$CASE_BIN/nolock"
  MP_SNAP="$(snapshot)"; mp_call "$drv"
  [ "$MP_RC" = 2 ] && [ -z "$MP_OUT" ] && grep -qF 'run_lock_held — ' <<<"$MP_ERR" && [ "$(snapshot)" = "$MP_SNAP" ] && [ "$(mp_n '^helper ')" = 0 ] \
    || { mp_fail "a held run lock: not refused with nothing written"; return 1; }
}

for mp_leg in "AC1:mp_ac1:MERGE ⇒ gate-eval once, closeout once WITH its trail + --session-id, one check-off, items remain ⇒ awaiting_go (the entry's message), no pick, no spawn, mode: safe" \
  "AC3:mp_ac3:no items remain ⇒ the done termination, trail included" \
  "AC5:mp_ac5:--resume first, then the entry ⇒ the ctx carries the recorded ready_sha, READY and termination_reason" \
  "AC6:mp_ac6:a fix-now re-drain rewrites the ready line in place (its sha and termination_reason, one line)" \
  "AC24:mp_ac24:a READY report without ready_sha writes no line; an item change drops it, a same-item current-set keeps it" \
  "AC7:mp_ac7:the live head is not ready_sha ⇒ PARK: head_sha_moved, a person must decide, no gate-eval" \
  "AC8:mp_ac8:a comment / review after ready_at ⇒ ready_stale_feedback, no gate-eval (a comment 1 s before does not park — AC1)" \
  "AC9:mp_ac9:compare behind_by > 0 ⇒ base_moved_since_ready, no gate-eval" \
  "AC10:mp_ac10:the checkout is off the PR head ⇒ checkout_not_on_pr_head naming the branch, HEAD and the tree unchanged" \
  "AC15:mp_ac15:no recorded ready_sha ⇒ ready_sha_missing, the live head never substituted" \
  "AC11:mp_ac11:the run lock is held across gate-eval (a watcher's lock-less acquire refused), one closeout, one check-off, the lock free after" \
  "AC12:mp_ac12:a park keeps awaiting_merge + one PARK line, releases the lock, one watcher (none armed beside a live one); a gate PARK reruns no decision step" \
  "AC13:mp_ac13:undecided per-finding dismissed drafts stay undecided after MERGE (pending_decisions recorded)" \
  "AC14:mp_ac14:--resume --auto-merge on the parked open PR names --merge-parked, keeps no flag_mode; plain --resume unchanged" \
  "AC16:mp_ac16:## Current not awaiting_merge after READY ⇒ refused by status, nothing written" \
  "AC17:mp_ac17:a lane / a --parallel parent ⇒ refused by name, nothing written" \
  "AC18:mp_ac18:MERGED at entry ⇒ closeout with no gate; CLOSED ⇒ RECONCILE's report, never checked off" \
  "LEFT:mp_left:a closeout leftover kept ⇒ the entry's own tail (awaiting_go)" \
  "HOST:mp_host:LOOMWRIGHT_HOST_STATE_DIR set ⇒ nothing written under it; the run file and sidecar under the automate dir" \
  "UNREAD:mp_unread:an unreadable PR head / review-comment / compare read parks (fail CLOSED), a late review comment parks, a held run lock refuses with nothing written" \
  "RACE:mp_race:## Current moved while the run lock was taken ⇒ the lock released, merge_parked_state_changed, no gate, no second closeout" \
  "USAGE:mp_usage:--merge-parked with --resume / --start / --result ⇒ exit 2, nothing written; the driver names no pr merge"; do
  LEG_MSG=""; mp_id="${mp_leg%%:*}"; mp_rest="${mp_leg#*:}"; mp_fn="${mp_rest%%:*}"; mp_what="${mp_rest#*:}"
  if "$mp_fn" "$DRIVER"; then ok "MP $mp_id: $mp_what"; else no "MP $mp_id: $LEG_MSG"; fi
done

# PIN — each leg turns red under its own mutant (the brief's Pin mutations rows; every mutant gated on its anchor
# once, non-empty, differs, bash -n — build_mutant / mp_rf_mutant)
if [ "${NS_SKIP_MUTANTS:-}" != 1 ]; then
  mp_pin() { # <name> <leg fn> <anchor> <replacement> <what>
    local m; LEG_MSG=""
    if m="$(build_mutant "mp$1" "$3" "$4")"; then
      if "$2" "$m"; then no "MP pin $1: the leg stayed green with $5"
      else ok "MP pin $1: $5 ⇒ the leg turns red (${LEG_MSG:0:120})"; fi
    else no "MP pin $1: mutant not built ($5)"; fi
  }
  # mp_rf_mutant — a scripts/ dir whose automate-helpers.d/runfile.sh lacks the `- ready_sha:` drop line
  mp_rf_mutant() {
    local d="$WORK/mut-mp-rf" e l='    c && dready == 1 && /^- ready_sha:/ { next }' f="$HERE/automate-helpers.d/runfile.sh"
    rm -rf "$d"; mkdir -p "$d/automate-helpers.d"
    for e in "$HERE"/*; do [ "${e##*/}" = automate-helpers.d ] || ln -s "$e" "$d/${e##*/}"; done
    for e in "$HERE/automate-helpers.d"/*; do [ "${e##*/}" = runfile.sh ] || ln -s "$e" "$d/automate-helpers.d/${e##*/}"; done
    [ "$(grep -cxF -- "$l" "$f")" = 1 ] || { echo "drop line occurs $(grep -cxF -- "$l" "$f") time(s)" >&2; return 1; }
    grep -vxF -- "$l" "$f" > "$d/automate-helpers.d/runfile.sh"
    [ -s "$d/automate-helpers.d/runfile.sh" ] && ! cmp -s "$f" "$d/automate-helpers.d/runfile.sh" && bash -n "$d/automate-helpers.d/runfile.sh" || { echo "mutant gates failed" >&2; return 1; }
    printf '%s/automate-helpers.sh' "$d"
  }
  mp_pin AC5s mp_ac5 '  rs="$(ns_kv "$l" ready_sha)"' '  rs="$(st ready_sha)"' 'ready_sha read from the sidecar'
  mp_pin AC5t mp_ac5 '  tr="$(ns_kv "$l" termination_reason)"' '  tr="$(st termination_reason)"' 'termination_reason read from the sidecar'
  mp_pin AC20 mp_ac6 '    ns_once once_dr_ready ns_current_line "- ready_sha:"' '    : ns_once once_dr_ready ns_current_line "- ready_sha:"' 'the drain-result ready line not written'
  mp_pin AC6k mp_ac6 '  if [ "$dec" = READY ] && [ -n "$rs" ]; then' '  if [ "$dec" = READY ] && [ "$kind" != fixnow ] && [ -n "$rs" ]; then' 'the ready line skipped for a fix-now re-drain'
  mp_pin AC6t mp_ac6 '| termination_reason: $tr" "- owned_drain_started:|- pending_decisions:"' '| termination_reason: $(st termination_reason)" "- owned_drain_started:|- pending_decisions:"' "the first drain's termination_reason written"
  mp_pin AC24 mp_ac24 '  if [ "$dec" = READY ] && [ -n "$rs" ]; then' '  if [ "$dec" = READY ]; then' 'the ready line written with an empty ready_sha'
  mp_pin AC8 mp_ac8 '    [ "$rc" != 0 ] || { ns_mp_due ready_stale_feedback' '    true || { ns_mp_due ready_stale_feedback' 'the newer-than-ready_at check deleted'
  mp_pin AC9 mp_ac9 '[ "$ba" -gt 0 ]' '[ "$ba" -gt 999 ]' 'behind_by compared with 999'
  mp_pin AC10 mp_ac10 '  [ "$cur" = "$live" ] || {' '  true || {' 'the HEAD-vs-live-head check deleted'
  mp_pin AC15 mp_ac15 '  ns_sha_ok "$rs" && ns_iso_ok "$ra" && [ -n "$tr" ] || { ns_mp_due ready_sha_missing' \
    '  ns_sha_ok "$rs" || rs="$(ns_pr_head "$PR")"; ns_iso_ok "$ra" || ra="$(ns_ts)"; [ -n "$tr" ] || tr=converged; false && { ns_mp_due ready_sha_missing' 'a missing ready_sha replaced by the live head'
  mp_pin AC2 mp_ac1 '  ns_awaiting_go "$m"' '  ns_terminate' 'the MERGE tail routed to ns_terminate (running)'
  mp_pin AC2m mp_ac1 '  ns_awaiting_go "$m"' '  ns_awaiting_go' "the superseded-drain default awaiting_go message"
  mp_pin AC12 mp_ac12 '  ns_release   # the merge-park releases the run lock' '  :' 'the guard park keeps the run lock'
  mp_pin AC12g mp_ac12 'the item stays awaiting_merge"; NEXT=merge-park ;;' 'the item stays awaiting_merge"; NEXT=dismissed ;;' "a gate PARK routed to ns_gate_eval's decision step"
  mp_pin AC14 mp_ac14 '    st_del flag_mode' '    :' 'flag_mode kept on the parked-open-PR --resume --auto-merge'
  mp_pin AC17 mp_ac17 '  ns_lane && { ns_mp_refuse "merge_parked_in_lane' '  false && { ns_mp_refuse "merge_parked_in_lane' 'the lane refusal deleted'
  mp_pin AC1 mp_ac1 '"$PR" ${SID:+--session-id "$SID"} 2>/dev/null)"   # WITH its trail' '"$PR" --no-trail ${SID:+--session-id "$SID"} 2>/dev/null)"   # WITH its trail' "the closeout run --no-trail (sync's)"
  mp_pin AC3 mp_ac3 '  [ "$n" = 0 ] && { ns_terminate; return; }' '  [ "$n" = 0 ] && { ns_awaiting_go; return; }' 'no items remain routed to awaiting_go'
  mp_pin AC4 mp_ac7 '  [ "$live" = "$rs" ] || { ns_mp_due head_sha_moved' '  [ "$live" = "$rs" ] || { NEXT=drain; return 0; ns_mp_due head_sha_moved' 'the head-moved branch routed to the drain'
  mp_pin AC7 mp_ac7 '  [ "$live" = "$rs" ] || { ns_mp_due head_sha_moved' '  true || { ns_mp_due head_sha_moved' 'the live-head-vs-ready_sha comparison deleted'
  mp_pin AC11 mp_ac11 '  ns_lock acquire || { ns_mp_refuse "run_lock_held' '  true || { ns_mp_refuse "run_lock_held' 'the run-lock acquire before gate-eval deleted'
  mp_pin RACE mp_race '  [ "$ITEM|$STATUS|$PR|$odr" = "$pre" ] || {' '  true || {' 'the re-read after the lock deleted'
  mp_pin AC13 mp_ac13 '  ns_dismissed || return 1' '  ns_dismissed || return 1; while IFS="$TAB" read -r _k _p; do [ -n "$_p" ] && bash "$H" dismissed-decide "$RF" "$_p" follow-up --auto >/dev/null 2>&1; done < <(ns_undecided)' 'undecided drafts followed up --auto after MERGE'
  mp_pin AC16 mp_ac16 '  [ "$STATUS" = awaiting_merge ] && [ "$odr" = READY ] || {' '  true || {' 'the status refusal deleted'
  mp_pin AC18c mp_ac18 "    *) # closed unmerged or vanished: RECONCILE's report — a human resolves it; never checked off" '    *) NEXT=merge-finish; return 0 ;; zz-never)' 'a CLOSED PR sent to the check-off'
  mp_pin AC18t mp_ac18 '  NEXT=merge-finish' '  ns_after_reconcile' "the MERGED tail routed to ns_after_reconcile (trail-gate)"
  mp_pin AC18g mp_ac18 '    merged) st_set mp_how already; NEXT=merge-closeout ;;' '    merged) st_set mp_how already; NEXT=merge-gate ;;' 'a MERGED PR sent to gate-eval first'
  mp_pin LEFT mp_left 'st_set leftovers "$cls"; st_set after_leftover merge-finish; NEXT=leftover' 'st_set leftovers "$cls"; NEXT=leftover' 'after_leftover left unset (checkoff → terminate → running)'
  LEG_MSG=""
  if mp_rfm="$(mp_rf_mutant)"; then
    if mp_ac24 "$DRIVER" "$mp_rfm"; then no "MP pin AC24d: the leg stayed green with runfile.sh's - ready_sha: drop line deleted"
    else ok "MP pin AC24d: runfile.sh's - ready_sha: drop line deleted ⇒ the leg turns red (${LEG_MSG:0:120})"; fi
  else no "MP pin AC24d: runfile mutant not built"; fi
fi
