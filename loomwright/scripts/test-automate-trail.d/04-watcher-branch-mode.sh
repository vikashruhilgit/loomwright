# =============================================================================
echo "== W. merge watcher =="
WATCH="$SPYD/automate-merge-watch.sh"
cp "$HERE/automate-merge-watch.sh" "$WATCH"
bash -n "$HERE/automate-merge-watch.sh" && ok "bash -n automate-merge-watch.sh" || no "bash -n watcher failed"
MARK=".supervisor/automate/$RUN_ID.merge-watch"

closeout_fixture 9
spy_reset
printf 'OPEN\nOPEN\nMERGED\n' > "$GH_STUB_DIR/state-seq"
jq '.[0].state = "OPEN"' "$GH_STUB_DIR/prs.json" > "$GH_STUB_DIR/p.tmp" && mv "$GH_STUB_DIR/p.tmp" "$GH_STUB_DIR/prs.json"
# AC14 runs the watcher under a LIVE long-lived non-shell ancestor (a perl standing in for an
# un-detached launcher's `claude`, with CLAUDE_PID naming it and CLAUDECODE set): without the
# watcher's holder pin, run-lock.sh's ungated ancestor walk would record that perl.
rm -f "$TOP/w14.out" "$TOP/w14.rc" "$TOP/w14.perl"
( cd "$P" || exit 1
  CLAUDECODE=1 LOOMWRIGHT_MERGE_WATCH_INTERVAL=0 LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=60 W14_OUT="$TOP/w14.out" W14_RC="$TOP/w14.rc" \
    perl -e '$ENV{CLAUDE_PID} = $$; my $r = system(@ARGV) >> 8; open(my $f, ">", $ENV{W14_RC}); print $f "$r\n"; close $f; sleep 600' \
    bash -c 'bash "$@" </dev/null >"$W14_OUT" 2>&1' _ "$WATCH" "$RF_REL" "$REQ" "$PRURL" </dev/null >/dev/null 2>&1 &
  echo "$!" > "$TOP/w14.perl" )
i=0; while [ ! -s "$TOP/w14.rc" ] && [ "$i" -lt 600 ]; do sleep 0.1; i=$((i+1)); done
wout="$(cat "$TOP/w14.out" 2>/dev/null)"; rc="$(cat "$TOP/w14.rc" 2>/dev/null)"; rc="${rc:-99}"
w14_perl="$(cat "$TOP/w14.perl" 2>/dev/null)"
w14_perl_alive=0; [ -n "$w14_perl" ] && kill -0 "$w14_perl" 2>/dev/null && w14_perl_alive=1
[ "$rc" -eq 0 ] && ok "watcher exits 0" || no "watcher rc=$rc"
[ "$(spy_count '^closeout ' "$SPYLOG")" = "1" ] && ok "AC13: OPEN → MERGED ⇒ exactly one closeout" || no "AC13: closeout count $(spy_count '^closeout ' "$SPYLOG")"
[ "$(spy_count notify "$SPYLOG.notify")" = "1" ] && [ "$(spy_count 'automate_merge_watch' "$SPYLOG.webhook")" = "1" ] && ok "AC13: exactly one notify (desktop + webhook)" || no "AC13: notify count"
[ ! -d "$FX/wt-pr" ] && grep -qxF -- "- [x] $REQ" "$P/$RF_REL" && ok "watcher-driven closeout cleaned up + checked off" || no "watcher closeout: $wout"
w14_hp="$(awk -F'\t' '$1=="pid"{print $2; exit}' "$SPYLOG.meta" 2>/dev/null)"
grep -q '^pid_source	holder_env$' "$SPYLOG.meta" && [ "$w14_perl_alive" = 1 ] && [ -n "$w14_hp" ] && [ "$w14_hp" != "$w14_perl" ] && ! kill -0 "$w14_hp" 2>/dev/null \
  && ok "AC14: watcher-driven closeout records pid_source holder_env — the closeout process (dead once it exits), not the live ancestor $w14_perl" \
  || no "pid_source (ancestor perl=$w14_perl alive=$w14_perl_alive): $(cat "$SPYLOG.meta" 2>/dev/null | tr '\n' '|')"
[ -n "$w14_perl" ] && kill "$w14_perl" 2>/dev/null
[ ! -e "$P/$MARK" ] && ok "AC13: marker gone after MERGED exit" || no "marker left after MERGED"

closeout_fixture 10
spy_reset
jq '.[0].state = "CLOSED"' "$GH_STUB_DIR/prs.json" > "$GH_STUB_DIR/p.tmp" && mv "$GH_STUB_DIR/p.tmp" "$GH_STUB_DIR/prs.json"
(cd "$P" && LOOMWRIGHT_MERGE_WATCH_INTERVAL=0 bash "$WATCH" "$RF_REL" "$REQ" "$PRURL" </dev/null >/dev/null 2>&1)
[ "$(spy_count '^closeout ' "$SPYLOG")" = "0" ] && [ -d "$FX/wt-pr" ] && git -C "$P" rev-parse -q --verify refs/heads/feature/x >/dev/null && ok "AC13: CLOSED ⇒ no closeout, no cleanup" || no "AC13: CLOSED cleaned up"
grep -qE "^- .* merge-watch: $REQ gone — $PRURL closed unmerged" "$P/$RF_REL" && ok "AC13: CLOSED ⇒ a gone Progress line" || no "AC13: gone line missing"
[ "$(spy_count notify "$SPYLOG.notify")" = "1" ] && [ ! -e "$P/$MARK" ] && ok "AC13: CLOSED ⇒ one notify, marker gone" || no "AC13: CLOSED notify/marker"

closeout_fixture 11
jq '.[0].state = "OPEN"' "$GH_STUB_DIR/prs.json" > "$GH_STUB_DIR/p.tmp" && mv "$GH_STUB_DIR/p.tmp" "$GH_STUB_DIR/prs.json"
t0="$(date +%s)"
(cd "$P" && LOOMWRIGHT_MERGE_WATCH_INTERVAL=1 LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=2 bash "$WATCH" "$RF_REL" "$REQ" "$PRURL" </dev/null >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ $(( $(date +%s) - t0 )) -lt 20 ] && ok "AC13: lifetime cap ⇒ clean exit" || no "AC13: cap exit rc=$rc"
grep -qE "^- .* merge-watch: lifetime cap \(2s\) reached watching $PRURL" "$P/$RF_REL" && ok "AC13: cap ⇒ a Progress line" || no "AC13: cap Progress line missing"
[ ! -e "$P/$MARK" ] && [ -d "$FX/wt-pr" ] && ok "AC13: cap ⇒ marker gone, nothing cleaned" || no "AC13: cap marker/cleanup"

# single instance: a live watcher blocks a second launch; a dead pid is reclaimed
( cd "$P" && LOOMWRIGHT_MERGE_WATCH_INTERVAL=1 LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=60 nohup bash "$WATCH" "$RF_REL" "$REQ" "$PRURL" </dev/null >"$TOP/w1.log" 2>&1 & )
i=0; while [ ! -s "$P/$MARK" ] && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i+1)); done
wpid="$(awk -F'\t' '$1=="pid"{print $2}' "$P/$MARK" 2>/dev/null)"
out="$(cd "$P" && bash "$WATCH" "$RF_REL" "$REQ" "$PRURL" </dev/null 2>&1)"
[ -n "$wpid" ] && [ "$out" = "merge-watch: already running pid=$wpid" ] && ok "AC13: second launch ⇒ already running, no second poller" || no "AC13 second launch: '$out' (pid=$wpid)"
[ "$(awk -F'\t' '$1=="pid"{print $2}' "$P/$MARK" 2>/dev/null)" = "$wpid" ] && ok "marker still names the first watcher" || no "marker overwritten"
[ -n "$wpid" ] && kill "$wpid" 2>/dev/null
i=0; while [ -e "$P/$MARK" ] && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i+1)); done
[ ! -e "$P/$MARK" ] && ok "AC13: marker gone after the watcher is terminated" || no "marker left after TERM"
( sleep 0 & echo $! > "$TOP/deadpid" )   # fixed-sleep-ok: `sleep 0` is the short-lived process whose pid goes dead, not a wait
# Wait until that pid IS dead before writing the marker — a fixed `sleep 0.2` assumed it (iq02 T07).
wait_for_pid_gone "$(cat "$TOP/deadpid")" 10 || no "dead-pid fixture: pid $(cat "$TOP/deadpid") never exited within 10 s"
printf 'pid\t%s\npr_url\t%s\nstarted\tx\n' "$(cat "$TOP/deadpid")" "$PRURL" > "$P/$MARK"
out="$(cd "$P" && LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=0 bash "$WATCH" "$RF_REL" "$REQ" "$PRURL" </dev/null 2>&1)"
case "$out" in *"merge-watch: started pid="*) ok "dead-pid marker is reclaimed" ;; *) no "dead-pid reclaim: $out" ;; esac

# M2: the marker is per RUN; a launch for ANOTHER PR of the same run replaces
# the live watcher (verified as ours by ps), a same-PR launch does not (above).
PRURL2="https://github.com/acme/widgets/pull/8"
REQ2=".supervisor/requirements/f/02-b.md"
closeout_fixture 38
spy_reset
jq --arg u "$PRURL2" '.[0].state = "OPEN" | . + [{number:8,url:$u,state:"OPEN",headRefName:"feature/y",headRefOid:"0"}]' "$GH_STUB_DIR/prs.json" > "$GH_STUB_DIR/p.tmp" && mv "$GH_STUB_DIR/p.tmp" "$GH_STUB_DIR/prs.json"
( cd "$P" && LOOMWRIGHT_MERGE_WATCH_INTERVAL=30 LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=600 nohup bash "$WATCH" "$RF_REL" "$REQ" "$PRURL" </dev/null >"$TOP/wa.log" 2>&1 & )
i=0; while [ ! -s "$P/$MARK" ] && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i+1)); done
apid="$(awk -F'\t' '$1=="pid"{print $2}' "$P/$MARK" 2>/dev/null)"
sleep 0.5   # fixed-sleep-ok: settle — A is now inside its 30s interval nap (too short ⇒ B replaces A before its nap, a different path)
t0="$(date +%s)"
( cd "$P" && LOOMWRIGHT_MERGE_WATCH_INTERVAL=30 LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=600 nohup bash "$WATCH" "$RF_REL" "$REQ2" "$PRURL2" </dev/null >"$TOP/wb.log" 2>&1 & )
i=0; while [ "$(awk -F'\t' '$1=="pr_url"{print $2}' "$P/$MARK" 2>/dev/null)" != "$PRURL2" ] && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i+1)); done
bpid="$(awk -F'\t' '$1=="pid"{print $2}' "$P/$MARK" 2>/dev/null)"
t1="$(date +%s)"
# The replacing watcher writes its marker BEFORE its `replaced` Progress + log
# lines, so wait (bounded) for those instead of reading them at the flip.
i=0; while ! grep -qF "merge-watch: replaced pid=$apid" "$TOP/wb.log" 2>/dev/null && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i+1)); done
[ -n "$apid" ] && ! kill -0 "$apid" 2>/dev/null && [ $(( t1 - t0 )) -lt 15 ] && ok "M2: launch for another PR terminates the old watcher promptly (interruptible nap)" || no "M2: old watcher pid=$apid still alive / slow"
[ -n "$bpid" ] && [ "$bpid" != "$apid" ] && kill -0 "$bpid" 2>/dev/null && ok "M2: the marker now names the new watcher for $PRURL2" || no "M2: marker: $(cat "$P/$MARK" 2>/dev/null | tr '\n' '|')"
grep -qF "merge-watch: replaced pid=$apid watching $PRURL" "$TOP/wb.log" && ok "M2: the new watcher says whom it replaced" || no "M2: wb.log: $(cat "$TOP/wb.log")"
grep -qE "^- .* merge-watch: replaced watcher pid=$apid for $PRURL \(now watching $PRURL2\)" "$P/$RF_REL" && ok "M2: a Progress line names the PR that is no longer watched" || no "M2: replace Progress line missing"
[ ! -s "$SPYLOG.notify" ] && [ ! -s "$SPYLOG.webhook" ] && ok "M2: the replaced watcher sent no notify" || no "M2: notify sent on replace"
[ -n "$bpid" ] && kill "$bpid" 2>/dev/null
i=0; while [ -e "$P/$MARK" ] && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i+1)); done
[ ! -e "$P/$MARK" ] && ok "M2: marker gone after the new watcher exits" || no "M2: marker left"

# stale-pid safety: a LIVE pid that is not our watcher is never signalled — the
# marker is reclaimed as stale, for the same PR and for another PR.
for spr in "$PRURL" "$PRURL2"; do
  sleep 30 </dev/null >/dev/null 2>&1 &
  foreign=$!
  printf 'pid\t%s\npr_url\t%s\nstarted\tx\n' "$foreign" "$PRURL" > "$P/$MARK"
  out="$(cd "$P" && LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=0 bash "$WATCH" "$RF_REL" "$REQ" "$spr" </dev/null 2>&1)"
  case "$out" in *"replaced"*) no "stale pid ($spr): treated as our watcher: $out" ;; *"merge-watch: started pid="*) ok "stale live pid, launch for $spr: reclaimed, not replaced" ;; *) no "stale pid ($spr): $out" ;; esac
  kill -0 "$foreign" 2>/dev/null && ok "stale live pid ($spr): the foreign process was not signalled" || no "stale pid ($spr): foreign process killed"
  kill "$foreign" 2>/dev/null; wait "$foreign" 2>/dev/null
done

# M3: MERGED seen, but closeout returns a transient skip until the lifetime cap
# ⇒ a failure-style notify + a Progress line naming the merge and the reason.
closeout_fixture 39
spy_reset
TC="$TOP/tcap"; mkdir -p "$TC"
cp "$WATCH" "$SPYD/notify-desktop.sh" "$SPYD/send-webhook.sh" "$TC/"
cat > "$TC/automate-helpers.sh" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$SPYLOG"
case "${1:-}" in
  closeout) echo "closeout: skipped — gh unavailable" ;;
  *) exec bash "$SPYD_REAL/automate-helpers.real.sh" "$@" ;;
esac
FAKE
# MAX=5, not 2: the watcher's clock is `date +%s` (whole seconds), so a start at
# x.9s plus the 1s retry nap can already read "2s elapsed" and hit a 2s cap
# before the retry — the 1-in-N 3.2 flake. 5s leaves room for >=2 closeouts.
wout="$(cd "$P" && SPYD_REAL="$SPYD" LOOMWRIGHT_MERGE_WATCH_INTERVAL=0 LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=5 bash "$TC/automate-merge-watch.sh" "$RF_REL" "$REQ" "$PRURL" </dev/null 2>&1)"
case "$wout" in *"merge-watch: lifetime cap reached (merged; closeout never ran — gh unavailable)"*) ok "M3: cap after MERGED names the merge + last skip" ;; *) no "M3: $wout" ;; esac
grep -qE "^- .* merge-watch: lifetime cap \(5s\) reached — $PRURL is MERGED but closeout never ran \(last skip: gh unavailable\)" "$P/$RF_REL" && ok "M3: Progress line says MERGED + the reason" || no "M3: Progress line missing"
grep -q 'after the merge' "$P/$RF_REL" && no "M3: Progress still says 'after the merge'" || ok "M3: never tells the owner to resume 'after the merge'"
[ "$(spy_count notify "$SPYLOG.notify")" = "1" ] && grep -q 'could not run.*lifetime cap reached, last skip: gh unavailable' "$SPYLOG.webhook" && ok "M3: one failure-style notify naming the reason" || no "M3 notify: $(cat "$SPYLOG.webhook" 2>/dev/null)"
[ "$(spy_count '^closeout ' "$SPYLOG")" -ge 2 ] && ok "M3: closeout was retried before the cap" || no "M3: closeout calls $(spy_count '^closeout ' "$SPYLOG")"

w_code="$(grep -vE '^[[:space:]]*#' "$HERE/automate-merge-watch.sh")"
bad="$(grep -nE 'pr merge|/autonomous|(^|[^a-z-])timeout |setsid|sed -i|stat -c|date -d' <<<"$w_code" || true)"
[ -z "$bad" ] && ok "watcher: no merge, no /autonomous, no timeout/setsid/GNU-only forms" || no "watcher forms: $bad"

# transient gh failure inside closeout: fails once, then succeeds ⇒ exactly one
# successful closeout + one notify (never a success notify for the guard skip)
closeout_fixture 36   # fresh id: 15/16 are the C legs above (a reused dir fails its clone)
spy_reset
touch "$GH_STUB_DIR/auth-fail-once"
wout="$(cd "$P" && LOOMWRIGHT_MERGE_WATCH_INTERVAL=0 LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=60 bash "$WATCH" "$RF_REL" "$REQ" "$PRURL" </dev/null 2>&1)"
case "$wout" in *"closeout: skipped — gh unavailable"*"merge-watch: closeout did not run (gh unavailable) — retry in "*"merge-watch: closeout done"*) ok "W: gh unavailable ⇒ retried, then closeout done" ;; *) no "W transient: $wout" ;; esac
[ "$(spy_count '^closeout ' "$SPYLOG")" = "2" ] && ok "W: two closeout calls (one guard skip + one real)" || no "W: closeout calls $(spy_count '^closeout ' "$SPYLOG")"
[ "$(printf '%s\n' "$wout" | grep -c '^closeout: checked — ')" = "1" ] && grep -qxF -- "- [x] $REQ" "$P/$RF_REL" && ok "W: exactly one successful closeout (checked off once)" || no "W: successful closeout count"
[ "$(spy_count notify "$SPYLOG.notify")" = "1" ] && [ "$(spy_count 'automate_merge_watch' "$SPYLOG.webhook")" = "1" ] && ok "W: exactly one notify" || no "W: notify count $(spy_count notify "$SPYLOG.notify")"

# terminal guard skip: one Progress line + a failure notify, never the success notify
closeout_fixture 37
spy_reset
TG="$TOP/tguard"; mkdir -p "$TG"
cp "$WATCH" "$SPYD/notify-desktop.sh" "$SPYD/send-webhook.sh" "$TG/"
cat > "$TG/automate-helpers.sh" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$SPYLOG"
case "${1:-}" in
  closeout) echo "closeout: skipped — not a git checkout" ;;
  *) exec bash "$SPYD_REAL/automate-helpers.real.sh" "$@" ;;
esac
FAKE
wout="$(cd "$P" && SPYD_REAL="$SPYD" LOOMWRIGHT_MERGE_WATCH_INTERVAL=0 LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=60 bash "$TG/automate-merge-watch.sh" "$RF_REL" "$REQ" "$PRURL" </dev/null 2>&1)"
[ "$(spy_count '^closeout ' "$SPYLOG")" = "1" ] && case "$wout" in *"merge-watch: closeout skipped — not a git checkout"*) true ;; *) false ;; esac && ok "W: terminal guard ⇒ one closeout call, exit" || no "W terminal: $wout"
grep -qE "^- .* merge-watch: closeout for $PRURL could not run — skipped: not a git checkout" "$P/$RF_REL" && ok "W: terminal guard ⇒ a Progress line naming it" || no "W terminal Progress line missing"
[ "$(spy_count notify "$SPYLOG.notify")" = "1" ] && grep -q 'could not run' "$SPYLOG.webhook" && ! grep -q 'closeout ran' "$SPYLOG.webhook" && ok "W: terminal guard ⇒ failure notify, never the success notify" || no "W terminal notify: $(cat "$SPYLOG.webhook" 2>/dev/null)"

echo "== WE. escalated park: watcher armed + settle re-check (automate-followups/31) =="
# Every leg runs the watcher against an `escalated` park whose ## Current carries
# the `- escalation_cause:` line Subtask 1's `current-escalation` writes.
ESHA="1e35336aaaabbbbccccddddeeeeffff000011112"
we_park() { # <cause> [current-escalation flags…] — turn the fixture's park into an escalated one
  local c="$1"; shift
  (cd "$P" && bash "$H" current-set "$RF_REL" --item "$REQ" --status escalated --pr "$PRURL" --branch feature/x --pause-reason escalated >/dev/null \
    && bash "$H" current-escalation "$RF_REL" --cause "$c" "$@" >/dev/null)
}
# we_open: the PR is OPEN at head $ESHA with an empty rollup (review iteration 1: the
# watcher reports only when the recorded sha IS the PR's current headRefOid and every
# OTHER rollup check is settled green — both read from the poll's own `gh pr view`).
we_open() { jq --arg h "$ESHA" '.[0].state = "OPEN" | .[0].headRefOid = $h | .[0].statusCheckRollup = []' "$GH_STUB_DIR/prs.json" > "$GH_STUB_DIR/p.tmp" && mv "$GH_STUB_DIR/p.tmp" "$GH_STUB_DIR/prs.json"; }
we_watch() { (cd "$P" && LOOMWRIGHT_MERGE_WATCH_INTERVAL=0 LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=60 bash "$WATCH" "$RF_REL" "$REQ" "$PRURL" </dev/null 2>&1); }
we_n() { grep -c -- "$1" "$P/$RF_REL" 2>/dev/null || true; }
we_calls() { grep -cE '^(run view|api )' "$GH_STUB_DIR/argv.log" 2>/dev/null || true; }
rj() { jq -cn --argjson a "$1" --arg s "$2" --arg c "$3" --arg h "${4:-$ESHA}" '{attempt:$a,status:$s,conclusion:$c,headSha:$h}'; }

# (E1, AC8 + AC12) escalated park, cause check_red ⇒ armed, merge closes it out,
# no check polling at all.
closeout_fixture 401; spy_reset; we_open
we_park check_red --check ci --run-id 555 --attempt 1 --sha "$ESHA"
grep -qE '^- escalation_cause: check_red \| check: ci' "$P/$RF_REL" && ok "(E1) fixture: ## Current carries the current-escalation line" || no "(E1) fixture line: $(cur_block "$P/$RF_REL" | tr '\n' '|')"
printf 'OPEN\nOPEN\nMERGED\n' > "$GH_STUB_DIR/state-seq"; rj 2 completed success > "$GH_STUB_DIR/run-seq"
wout="$(we_watch)"
[ "$(spy_count '^closeout ' "$SPYLOG")" = "1" ] && grep -qxF -- "- [x] $REQ" "$P/$RF_REL" && ok "(E1) AC8: an escalated park's watcher closes the item out on merge (one closeout)" || no "(E1) closeout: $wout"
[ "$(we_calls)" = "0" ] && [ "$(we_n 'merge-watch: now mergeable:')" = "0" ] && [ "$(spy_count automate_escalation_recheck "$SPYLOG.webhook")" = "0" ] && ok "(E1) AC12: check_red ⇒ no check polling, no re-check report" || no "(E1) check_red polled: calls=$(we_calls)"
[ "$(spy_count notify "$SPYLOG.notify")" = "1" ] && [ "$(spy_count automate_merge_watch "$SPYLOG.webhook")" = "1" ] && ok "(E1) one merge notify, as for awaiting_merge" || no "(E1) notify count"

# (E2, AC12) findings / other / a re-checkable cause naming ANOTHER PR ⇒ no polling.
closeout_fixture 402
for wc in findings other foreign; do
  spy_reset; we_open; : > "$GH_STUB_DIR/argv.log"
  if [ "$wc" = foreign ]; then
    we_park check_pending --check ci --run-id 555 --attempt 1 --sha "$ESHA"
    (cd "$P" && bash "$H" current-set "$RF_REL" --item "$REQ" --status escalated --pr "https://github.com/acme/widgets/pull/70" --branch feature/x --pause-reason escalated >/dev/null)
  else we_park "$wc"; fi
  printf 'OPEN\nOPEN\nCLOSED\n' > "$GH_STUB_DIR/state-seq"; rj 1 completed success > "$GH_STUB_DIR/run-seq"
  we_watch >/dev/null
  [ "$(we_calls)" = "0" ] && [ "$(spy_count automate_escalation_recheck "$SPYLOG.webhook")" = "0" ] && ok "(E2) AC12: $wc ⇒ no check polling" || no "(E2) $wc polled: $(we_calls)"
done

# (E2b, af36-remainder/01 AC8) validation_unrun is an engine-side park cause (an unrun
# running-system Validation step), never a check: even with a run id whose run is green on
# the PR head — the exact shape E3 reports — the watcher never polls and never writes
# `now mergeable`; a merge still closes the item out.
closeout_fixture 420; spy_reset; we_open; : > "$GH_STUB_DIR/argv.log"
we_park validation_unrun --check "V2 Running system" --run-id 555 --attempt 1 --sha "$ESHA"
grep -qE '^- escalation_cause: validation_unrun \| check: V2 Running system' "$P/$RF_REL" && ok "(E2b) fixture: ## Current carries the validation_unrun line" || no "(E2b) fixture line: $(cur_block "$P/$RF_REL" | tr '\n' '|')"
printf 'OPEN\nOPEN\nOPEN\nOPEN\nMERGED\n' > "$GH_STUB_DIR/state-seq"; { rj 1 completed success; rj 1 completed success; } > "$GH_STUB_DIR/run-seq"
we_watch >/dev/null
[ "$(we_calls)" = "0" ] && [ "$(we_n 'merge-watch: now mergeable:')" = "0" ] && [ "$(spy_count automate_escalation_recheck "$SPYLOG.webhook")" = "0" ] && ok "(E2b) validation_unrun ⇒ no check polling, never 'now mergeable', no recheck notify" || no "(E2b) validation_unrun re-checked: calls=$(we_calls) $(grep 'mergeable' "$P/$RF_REL")"
[ "$(spy_count '^closeout ' "$SPYLOG")" = "1" ] && ok "(E2b) the merge still closes a validation_unrun park out (one closeout)" || no "(E2b) closeouts=$(spy_count '^closeout ' "$SPYLOG")"

# (E3, AC10) check_pending → completes green ⇒ exactly one now-mergeable line +
# one recheck notify, then keeps watching and closes out on the merge.
closeout_fixture 403; spy_reset; we_open
we_park check_pending --check claude-review --run-id 555 --attempt 1 --sha "$ESHA"
printf 'OPEN\nOPEN\nOPEN\nOPEN\nMERGED\n' > "$GH_STUB_DIR/state-seq"
{ rj 1 in_progress ""; rj 1 completed success; } > "$GH_STUB_DIR/run-seq"
wout="$(we_watch)"
[ "$(we_n "merge-watch: now mergeable: claude-review green on $ESHA")" = "1" ] && ok "(E3) AC10: exactly one 'now mergeable: claude-review green on <sha>' Progress line" || no "(E3) now-mergeable lines: $(we_n 'now mergeable')"
[ "$(spy_count automate_escalation_recheck "$SPYLOG.webhook")" = "1" ] && [ "$(spy_count automate_merge_watch "$SPYLOG.webhook")" = "1" ] && [ "$(spy_count notify "$SPYLOG.notify")" = "2" ] && ok "(E3) AC10: one automate_escalation_recheck notify (distinct type) + the one merge notify" || no "(E3) webhook: $(cat "$SPYLOG.webhook" 2>/dev/null | tr '\n' '|')"
[ "$(we_calls)" = "2" ] && [ "$(spy_count '^closeout ' "$SPYLOG")" = "1" ] && ok "(E3) latched after the report (2 run-view polls), then the merge closed it out" || no "(E3) calls=$(we_calls) closeouts=$(spy_count '^closeout ' "$SPYLOG")"
grep -q '^run view 555 --json attempt,status,conclusion,headSha$' "$GH_STUB_DIR/argv.log" && ! grep -q '^run rerun\|^pr merge' "$GH_STUB_DIR/argv.log" && ok "(E3) polls via gh run view <run_id>; no rerun, no merge call" || no "(E3) argv: $(tr '\n' '|' < "$GH_STUB_DIR/argv.log")"

# (E4, AC10) check_pending → completes non-green ⇒ one still-failing line carrying
# the rerun command; a restarted watcher does not report it again.
closeout_fixture 404; spy_reset; we_open
we_park check_pending --check claude-review --run-id 555 --attempt 1 --sha "$ESHA"
printf 'OPEN\nOPEN\nOPEN\nCLOSED\n' > "$GH_STUB_DIR/state-seq"; rj 1 completed failure > "$GH_STUB_DIR/run-seq"
we_watch >/dev/null
[ "$(we_n 'merge-watch: still failing: claude-review failure — rerun: gh run rerun 555 --failed')" = "1" ] && [ "$(spy_count automate_escalation_recheck "$SPYLOG.webhook")" = "1" ] && ok "(E4) AC10: one 'still failing … — rerun: gh run rerun 555 --failed' line + one recheck notify" || no "(E4) still-failing: $(grep 'still failing' "$P/$RF_REL")"
spy_reset; printf 'OPEN\nCLOSED\n' > "$GH_STUB_DIR/state-seq"
we_watch >/dev/null
[ "$(we_n 'merge-watch: still failing:')" = "1" ] && [ "$(spy_count automate_escalation_recheck "$SPYLOG.webhook")" = "0" ] && ok "(E4) a restarted watcher finds the report in ## Progress and stays silent" || no "(E4) restart re-reported"

# (E5, AC11) check_red_unrelated: the recorded red attempt never reports; a NEWER
# attempt (a human rerun) green ⇒ one now-mergeable; non-green ⇒ one still-failing.
for wv in green red; do
  if [ "$wv" = green ]; then closeout_fixture 405; fin=success; else closeout_fixture 406; fin=failure; fi
  spy_reset; we_open
  we_park check_red_unrelated --check ci --run-id 777 --attempt 1 --sha "$ESHA"
  printf 'OPEN\nOPEN\nOPEN\nOPEN\nOPEN\nOPEN\nOPEN\nCLOSED\n' > "$GH_STUB_DIR/state-seq"
  { rj 1 completed failure; rj 1 completed failure; rj 1 completed failure; rj 2 in_progress ""; rj 2 completed "$fin"; } > "$GH_STUB_DIR/run-seq"
  we_watch >/dev/null
  if [ "$wv" = green ]; then
    [ "$(we_n "merge-watch: now mergeable: ci green on $ESHA")" = "1" ] && [ "$(we_n 'merge-watch: still failing:')" = "0" ] && ok "(E5) AC11: red attempt 1 silent; attempt 2 green ⇒ one now-mergeable" || no "(E5) green: $(grep -E 'mergeable|failing' "$P/$RF_REL" | tr '\n' '|')"
    [ "$(we_calls)" = "5" ] && ok "(E5) reported on the 5th poll (the first completed attempt 2), then latched" || no "(E5) calls=$(we_calls)"
  else
    [ "$(we_n 'merge-watch: still failing: ci failure — rerun: gh run rerun 777 --failed')" = "1" ] && [ "$(we_n 'merge-watch: now mergeable:')" = "0" ] && [ "$(spy_count automate_escalation_recheck "$SPYLOG.webhook")" = "1" ] && ok "(E5) AC11: attempt 2 red ⇒ one still-failing line with the rerun command" || no "(E5) red: $(grep -E 'mergeable|failing' "$P/$RF_REL" | tr '\n' '|')"
  fi
done

# (E6) no run id recorded ⇒ the check-runs API by name, on the recorded sha.
closeout_fixture 407; spy_reset; we_open
we_park check_pending --check claude-review --sha "$ESHA"
printf 'OPEN\nOPEN\nCLOSED\n' > "$GH_STUB_DIR/state-seq"
jq -cn '{check_runs:[{name:"ci",status:"completed",conclusion:"success",started_at:"t1"},{name:"claude-review",status:"completed",conclusion:"success",started_at:"t2",details_url:"https://github.com/acme/widgets/actions/runs/999/job/1"}]}' > "$GH_STUB_DIR/api-seq"
we_watch >/dev/null
grep -q "^api repos/acme/widgets/commits/$ESHA/check-runs" "$GH_STUB_DIR/argv.log" && [ "$(we_n "merge-watch: now mergeable: claude-review green on $ESHA")" = "1" ] && ok "(E6) no run id ⇒ gh api commits/<sha>/check-runs by name ⇒ one now-mergeable" || no "(E6) argv: $(tr '\n' '|' < "$GH_STUB_DIR/argv.log")"

# (E6b, V5) a spaced (matrix) check name recorded whole — what escalation-cause writes since it
# reads the snapshot through wait-for-checks-line.sh — is found by name on the no-run-id path
# ⇒ one now-mergeable. Control: the word-split name the old parser recorded (`test`) matches no
# check run ⇒ never reported (the silent loss V5 describes).
for wn in "test (18.x)" "test"; do
  closeout_fixture 408; spy_reset; we_open; : > "$GH_STUB_DIR/argv.log"
  we_park check_pending --check "$wn" --sha "$ESHA"
  printf 'OPEN\nOPEN\nCLOSED\n' > "$GH_STUB_DIR/state-seq"
  jq -cn '{check_runs:[{name:"lint",status:"completed",conclusion:"success",started_at:"t1"},{name:"test (18.x)",status:"completed",conclusion:"success",started_at:"t2",details_url:"https://github.com/acme/widgets/actions/runs/998/job/1"}]}' > "$GH_STUB_DIR/api-seq"
  we_watch >/dev/null
  if [ "$wn" = "test (18.x)" ]; then
    [ "$(we_n "merge-watch: now mergeable: test (18.x) green on $ESHA")" = "1" ] && ok "(E6b) V5: spaced check name 'test (18.x)', no run id ⇒ found by name ⇒ one now-mergeable" || no "(E6b) spaced name not reported: $(grep -E 'mergeable|failing|escalation_cause' "$P/$RF_REL" | tr '\n' '|')"
  else
    [ "$(we_n 'merge-watch: now mergeable:')" = "0" ] && ok "(E6b) V5 control: the word-split name 'test' matches no check run ⇒ never reported" || no "(E6b) control: truncated name reported"
  fi
done

# (E7, AC9) park → fix-now re-drain → re-park of the SAME PR: both parks run the
# documented launch line (`nohup bash <watcher> <runfile> <item> <pr_url> </dev/null >log &`;
# its env-unset prefix is omitted — the watcher unsets those vars itself, first line).
# dbl_arm <watcher> → DA1/DA2/DA3 = the three assertions.
dbl_arm() {
  local w="$1" i lg1 lg2
  lg1="$TOP/da1-$2.log"; lg2="$TOP/da2-$2.log"
  ( cd "$P" && LOOMWRIGHT_MERGE_WATCH_INTERVAL=1 LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=60 nohup bash "$w" "$RF_REL" "$REQ" "$PRURL" </dev/null >"$lg1" 2>&1 & )
  i=0; while [ ! -s "$P/$MARK" ] && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i+1)); done
  DPID="$(awk -F'\t' '$1=="pid"{print $2}' "$P/$MARK" 2>/dev/null)"
  # The second launcher's own pid is kept, and its EXIT is awaited before its log is read — it exits right
  # after `already running`. This replaced a fixed `sleep 0.3` quiet period (iq02 T07). Bounded: a
  # mutant whose second launch keeps running as a watcher is read after 5 s, its log then is not the
  # one-line `already running`, so DA1 still goes red.
  ( cd "$P" && LOOMWRIGHT_MERGE_WATCH_INTERVAL=1 LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=60 nohup bash "$w" "$RF_REL" "$REQ" "$PRURL" </dev/null >"$lg2" 2>&1 ) &
  DA_L2=$!
  i=0; while ! grep -qE 'already running|started|replaced' "$lg2" 2>/dev/null && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i+1)); done
  wait_for_pid_gone "$DA_L2" 5 2>/dev/null || :
  disown "$DA_L2" 2>/dev/null || :
  DA1=1; DA2=1; DA3=1
  [ -n "$DPID" ] && [ "$(cat "$lg2")" = "merge-watch: already running pid=$DPID" ] || DA1=0
  [ -n "$DPID" ] && kill -0 "$DPID" 2>/dev/null || DA2=0
  [ -n "$DPID" ] && [ "$(awk -F'\t' '$1=="pid"{print $2}' "$P/$MARK" 2>/dev/null)" = "$DPID" ] || DA3=0
}
closeout_fixture 408; spy_reset; we_open
we_park check_red --check ci --run-id 555 --attempt 1 --sha "$ESHA"
dbl_arm "$WATCH" fixed
[ "$DA1" = 1 ] && ok "(E7) AC9 (1): the second launch prints 'merge-watch: already running pid=<first pid>'" || no "(E7) second launch: $(cat "$TOP/da2-fixed.log")"
[ "$DA2" = 1 ] && ok "(E7) AC9 (2): the first watcher is still alive after the second launch" || no "(E7) first watcher pid=$DPID gone"
[ "$DA3" = 1 ] && ok "(E7) AC9 (3): the marker's pid field is unchanged" || no "(E7) marker: $(tr '\n' '|' < "$P/$MARK" 2>/dev/null)"
jq '.[0].state = "MERGED"' "$GH_STUB_DIR/prs.json" > "$GH_STUB_DIR/p.tmp" && mv "$GH_STUB_DIR/p.tmp" "$GH_STUB_DIR/prs.json"
i=0; while [ -e "$P/$MARK" ] && [ "$i" -lt 400 ]; do sleep 0.1; i=$((i+1)); done
[ ! -e "$P/$MARK" ] && [ "$(spy_count '^closeout ' "$SPYLOG")" = "1" ] && [ "$(spy_count automate_merge_watch "$SPYLOG.webhook")" = "1" ] && grep -qxF -- "- [x] $REQ" "$P/$RF_REL" && ok "(E7) AC9: the merge then yields exactly one closeout + one merge notify" || no "(E7) closeouts=$(spy_count '^closeout ' "$SPYLOG") marker=$([ -e "$P/$MARK" ] && echo left)"
[ -n "$DPID" ] && kill "$DPID" 2>/dev/null
# mutation control: delete EXACTLY the same-pr_url `already running` branch.
MUT9="$TOP/mut9"; mkdir -p "$MUT9"; cp -R "$SPYD"/* "$MUT9/"
awk 'skip { skip = 0; next } /elif \[ "\$v" -eq 0 \] && \[ "\$opr" = "\$pr_url" \]; then/ { skip = 1; next } { print }' "$WATCH" > "$MUT9/automate-merge-watch.sh"
if [ -s "$MUT9/automate-merge-watch.sh" ] && ! cmp -s "$WATCH" "$MUT9/automate-merge-watch.sh" && bash -n "$MUT9/automate-merge-watch.sh" \
   && [ "$(( $(wc -l < "$WATCH") - $(wc -l < "$MUT9/automate-merge-watch.sh") ))" = "2" ]; then
  ok "(E7) AC9 mutant is valid (non-empty, differs by exactly the 2-line branch, bash -n clean)"
  closeout_fixture 409; spy_reset; we_open
  we_park check_red --check ci --run-id 555 --attempt 1 --sha "$ESHA"
  dbl_arm "$MUT9/automate-merge-watch.sh" mut
  [ "$DA1$DA2$DA3" != 111 ] && ok "(E7) AC9 mutant (same-pr_url branch deleted) is detected: (1)(2)(3)=$DA1$DA2$DA3" || no "(E7) AC9 mutant survived the double-arm assertions"
  for kp in "$DPID" "$(awk -F'\t' '$1=="pid"{print $2}' "$P/$MARK" 2>/dev/null)"; do [ -n "$kp" ] && kill "$kp" 2>/dev/null; done
  i=0; while [ -e "$P/$MARK" ] && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i+1)); done
else no "(E7) AC9 mutant invalid (empty / identical / bash -n / not exactly 2 lines)"; fi

# (E8, AC13 watcher half) no executed `gh run rerun` / `gh pr merge` / `git push`
# / approval in the watcher (or the classifier); comment and string mentions excluded.
we_exec_re='(^|[;&|({]|then|do|else|&&|\|\|)[[:space:]]*("?\$\{?GH\}?"?|gh)[[:space:]]+(run[[:space:]]+rerun|pr[[:space:]]+merge|pr[[:space:]]+review)|(^|[;&|({]|then|do|else)[[:space:]]*git[[:space:]]+push'
for wf in "$HERE/automate-merge-watch.sh" "$HERE/automate-helpers.d/escalation.sh"; do
  bad="$(grep -vE '^[[:space:]]*#' "$wf" | grep -nE "$we_exec_re" || true)"
  [ -z "$bad" ] && ok "(E8) AC13: $(basename "$wf") executes no gh run rerun / gh pr merge / git push / approval" || no "(E8) $(basename "$wf"): $bad"
done
[ "$(printf '%s\n' '  "$GH" run rerun "$rid" --failed' 'gh pr merge --squash "$u"' '  then git push origin x' | grep -cE "$we_exec_re")" = 3 ] && ok "(E8) the scan's positive control matches executed forms" || no "(E8) scan regex vacuous"
grep -qF 'rerun: gh run rerun' "$HERE/automate-merge-watch.sh" && ok "(E8) the rerun command is printed for the owner (string), never run" || no "(E8) rerun string missing"

# (E9, review iteration 1 — stale per-item state) a recorded sha that is NOT the PR's
# current headRefOid (a later push, or a line left over from an earlier item) ⇒ no
# check polling, no report.
closeout_fixture 410; spy_reset; we_open; : > "$GH_STUB_DIR/argv.log"
we_park check_pending --check claude-review --run-id 555 --attempt 1 --sha aaaaaaa
printf 'OPEN\nOPEN\nCLOSED\n' > "$GH_STUB_DIR/state-seq"; rj 1 completed success aaaaaaa > "$GH_STUB_DIR/run-seq"
we_watch >/dev/null
[ "$(we_calls)" = "0" ] && [ "$(we_n 'merge-watch: now mergeable:')" = "0" ] && [ "$(spy_count automate_escalation_recheck "$SPYLOG.webhook")" = "0" ] && ok "(E9) recorded sha != PR head ⇒ no polling, no 'now mergeable', no recheck notify" || no "(E9) stale sha reported: calls=$(we_calls) $(grep 'mergeable' "$P/$RF_REL")"
grep -q -- '--json state,headRefOid,statusCheckRollup' "$GH_STUB_DIR/argv.log" && [ "$(grep -c '^pr view ' "$GH_STUB_DIR/argv.log")" = "3" ] && ok "(E9) head + rollup come from the poll's own gh pr view (3 polls = 3 calls, no extra one)" || no "(E9) argv: $(tr '\n' '|' < "$GH_STUB_DIR/argv.log")"
# mutation control: delete EXACTLY the head-mismatch latch ⇒ the stale line reports.
MUT10="$TOP/mut10"; mkdir -p "$MUT10"; cp -R "$SPYD"/* "$MUT10/"
grep -vxF '  case "$head" in "$sha"*) ;; *) case "$sha" in "$head"*) ;; *) recheck_done=1; return 0 ;; esac ;; esac' "$WATCH" > "$MUT10/automate-merge-watch.sh"
if [ -s "$MUT10/automate-merge-watch.sh" ] && ! cmp -s "$WATCH" "$MUT10/automate-merge-watch.sh" && bash -n "$MUT10/automate-merge-watch.sh" \
   && [ "$(( $(wc -l < "$WATCH") - $(wc -l < "$MUT10/automate-merge-watch.sh") ))" = "1" ]; then
  closeout_fixture 413; spy_reset; we_open
  we_park check_pending --check claude-review --run-id 555 --attempt 1 --sha aaaaaaa
  printf 'OPEN\nOPEN\nCLOSED\n' > "$GH_STUB_DIR/state-seq"; rj 1 completed success aaaaaaa > "$GH_STUB_DIR/run-seq"
  (cd "$P" && LOOMWRIGHT_MERGE_WATCH_INTERVAL=0 LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=60 bash "$MUT10/automate-merge-watch.sh" "$RF_REL" "$REQ" "$PRURL" </dev/null >/dev/null 2>&1)
  [ "$(we_n 'merge-watch: now mergeable: claude-review green on aaaaaaa')" = "1" ] && ok "(E9) mutant (head check deleted) reports the stale sha — the latch is load-bearing" || no "(E9) mutant did not discriminate"
else no "(E9) head-check mutant invalid (empty / identical / bash -n / not exactly 1 line)"; fi
# (E9b) the escalated item's merge: closeout's `current-set --status done` clears the
# line; a second closeout leaves the run file byte-identical.
closeout_fixture 411; spy_reset; we_open
we_park check_pending --check claude-review --run-id 555 --attempt 1 --sha "$ESHA"
jq '.[0].state = "MERGED"' "$GH_STUB_DIR/prs.json" > "$GH_STUB_DIR/p.tmp" && mv "$GH_STUB_DIR/p.tmp" "$GH_STUB_DIR/prs.json"
run_closeout >/dev/null
if ! grep -q '^- escalation_cause:' "$P/$RF_REL" && grep -q 'status: done' < <(cur_block "$P/$RF_REL"); then ok "(E9b) closeout clears the escalated item's escalation_cause line"; else no "(E9b) line survived closeout: $(cur_block "$P/$RF_REL" | tr '\n' '|')"; fi
we_ck="$(cksum < "$P/$RF_REL")"; run_closeout >/dev/null
[ "$(cksum < "$P/$RF_REL")" = "$we_ck" ] && ok "(E9b) a second closeout leaves the run file byte-identical" || no "(E9b) second closeout changed the run file"

# (E10, review iteration 1 — verdict before a more-severe signal) the recorded check
# completes green but ANOTHER rollup check is still pending / red / the rollup is
# unreadable ⇒ no 'now mergeable'; control: only the recorded check itself in the rollup ⇒ reported.
for wo in pending red unreadable self; do
  closeout_fixture 412; spy_reset; we_open
  case "$wo" in
    pending) rl='[{"name":"ci","status":"IN_PROGRESS","conclusion":""}]' ;;
    red) rl='[{"name":"ci","status":"COMPLETED","conclusion":"FAILURE"},{"context":"lint","state":"SUCCESS"}]' ;;
    unreadable) rl='null' ;;
    self) rl='[{"name":"claude-review","status":"IN_PROGRESS","conclusion":""},{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS"},{"context":"lint","state":"SUCCESS"}]' ;;
  esac
  jq --argjson r "$rl" '.[0].statusCheckRollup = $r' "$GH_STUB_DIR/prs.json" > "$GH_STUB_DIR/p.tmp" && mv "$GH_STUB_DIR/p.tmp" "$GH_STUB_DIR/prs.json"
  we_park check_pending --check claude-review --run-id 555 --attempt 1 --sha "$ESHA"
  printf 'OPEN\nOPEN\nOPEN\nCLOSED\n' > "$GH_STUB_DIR/state-seq"; rj 1 completed success > "$GH_STUB_DIR/run-seq"
  we_watch >/dev/null
  if [ "$wo" = self ]; then
    [ "$(we_n "merge-watch: now mergeable: claude-review green on $ESHA")" = "1" ] && ok "(E10) control: other rollup checks settled green (recorded check excluded by name) ⇒ one now-mergeable" || no "(E10) control did not report: $(grep -E 'mergeable|failing' "$P/$RF_REL" | tr '\n' '|')"
  else
    [ "$(we_n 'merge-watch: now mergeable:')" = "0" ] && [ "$(spy_count automate_escalation_recheck "$SPYLOG.webhook")" = "0" ] && ok "(E10) recorded check green but another check $wo ⇒ no 'now mergeable'" || no "(E10) $wo reported now mergeable"
  fi
done

# (E11, review iteration 1 — fail-open on incomplete evidence) a run view with no
# headSha is no evidence the run is for the recorded sha ⇒ no report.
closeout_fixture 414; spy_reset; we_open
we_park check_pending --check claude-review --run-id 555 --attempt 1 --sha "$ESHA"
printf 'OPEN\nOPEN\nCLOSED\n' > "$GH_STUB_DIR/state-seq"; jq -cn '{attempt:1,status:"completed",conclusion:"success"}' > "$GH_STUB_DIR/run-seq"
we_watch >/dev/null
[ "$(we_n 'merge-watch: now mergeable:')" = "0" ] && [ "$(spy_count automate_escalation_recheck "$SPYLOG.webhook")" = "0" ] && ok "(E11) a run view without headSha ⇒ no 'now mergeable'" || no "(E11) headSha-less run reported"

# (E12, review iteration 2 — permanent latch on an absent/stale line) the brief's AC9
# flow end to end: park (check_red line) arms the watcher → PICK's `running` drops the
# line → the re-park writes a FRESH check_pending line and its launch prints `already
# running` ⇒ the KEPT watcher still reports exactly once (the latch is keyed on the
# line's content, never permanent). we_pr <n> — `pr view` calls so far.
we_pr() { grep -c '^pr view ' "$GH_STUB_DIR/argv.log" 2>/dev/null || true; }
we_until_polls() { local n0 i=0; n0="$(we_pr)"; while [ "$(we_pr)" -lt $((n0 + $1)) ] && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i+1)); done; }
# repark_flow <watcher> <fixture_n> <tag> → RP_ALREADY (second launch line ok), RP_N (now-mergeable lines), RP_R (recheck notifies)
repark_flow() {
  local w="$1" i pid lg2="$TOP/rp2-$3.log"
  closeout_fixture "$2"; spy_reset; we_open; : > "$GH_STUB_DIR/argv.log"; rm -f "$GH_STUB_DIR/state-seq" "$GH_STUB_DIR/run-seq"
  we_park check_red --check ci --run-id 555 --attempt 1 --sha "$ESHA"
  rj 1 completed success > "$GH_STUB_DIR/run-seq"
  ( cd "$P" && LOOMWRIGHT_MERGE_WATCH_INTERVAL=1 LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=120 nohup bash "$w" "$RF_REL" "$REQ" "$PRURL" </dev/null >"$TOP/rp1-$3.log" 2>&1 & )
  i=0; while [ ! -s "$P/$MARK" ] && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i+1)); done
  pid="$(awk -F'\t' '$1=="pid"{print $2}' "$P/$MARK" 2>/dev/null)"
  we_until_polls 2
  (cd "$P" && bash "$H" current-set "$RF_REL" --item "$REQ" --status running >/dev/null)   # PICK drops the line
  we_until_polls 2
  we_park check_pending --check claude-review --run-id 555 --attempt 1 --sha "$ESHA"
  ( cd "$P" && LOOMWRIGHT_MERGE_WATCH_INTERVAL=1 LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=120 nohup bash "$w" "$RF_REL" "$REQ" "$PRURL" </dev/null >"$lg2" 2>&1 & )
  i=0; while ! grep -qE 'already running|started|replaced' "$lg2" 2>/dev/null && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i+1)); done
  RP_ALREADY=0; [ -n "$pid" ] && [ "$(cat "$lg2")" = "merge-watch: already running pid=$pid" ] && RP_ALREADY=1
  i=0; while [ "$(we_n 'merge-watch: now mergeable:')" = 0 ] && [ "$i" -lt 6 ]; do we_until_polls 1; i=$((i+1)); done
  we_until_polls 3   # further polls after any report must stay silent
  RP_N="$(we_n "merge-watch: now mergeable: claude-review green on $ESHA")"
  RP_R="$(spy_count automate_escalation_recheck "$SPYLOG.webhook")"
  jq '.[0].state = "MERGED"' "$GH_STUB_DIR/prs.json" > "$GH_STUB_DIR/p.tmp" && mv "$GH_STUB_DIR/p.tmp" "$GH_STUB_DIR/prs.json"
  i=0; while [ -e "$P/$MARK" ] && [ "$i" -lt 400 ]; do sleep 0.1; i=$((i+1)); done
  [ -n "$pid" ] && kill "$pid" 2>/dev/null
  return 0
}
repark_flow "$WATCH" 415 fixed
[ "$RP_ALREADY" = 1 ] && ok "(E12) AC9: the re-park's launch prints 'already running pid=<kept watcher>'" || no "(E12) second launch: $(cat "$TOP/rp2-fixed.log")"
[ "$RP_N" = 1 ] && [ "$RP_R" = 1 ] && ok "(E12) AC10 after a re-park: the kept watcher reads the fresh check_pending line ⇒ exactly one now-mergeable + one recheck notify" || no "(E12) kept watcher: now-mergeable=$RP_N notifies=$RP_R"
# mutation control: delete EXACTLY the content-change reset ⇒ the latch is permanent again.
MUT12="$TOP/mut12"; mkdir -p "$MUT12"; cp -R "$SPYD"/* "$MUT12/"
grep -vxF '       [ "$esc_now" = "$esc_seen" ] || { esc_seen="$esc_now"; recheck_done=0; }' "$WATCH" > "$MUT12/automate-merge-watch.sh"
if [ -s "$MUT12/automate-merge-watch.sh" ] && ! cmp -s "$WATCH" "$MUT12/automate-merge-watch.sh" && bash -n "$MUT12/automate-merge-watch.sh" \
   && [ "$(( $(wc -l < "$WATCH") - $(wc -l < "$MUT12/automate-merge-watch.sh") ))" = "1" ]; then
  repark_flow "$MUT12/automate-merge-watch.sh" 416 mut
  [ "$RP_N" = 0 ] && ok "(E12) mutant (permanent latch restored) misses the re-park's fresh line — the reset is load-bearing" || no "(E12) mutant did not discriminate: now-mergeable=$RP_N"
else no "(E12) permanent-latch mutant invalid (empty / identical / bash -n / not exactly 1 line)"; fi

# (E13) the content-keyed latch never re-reports one line: a restarted watcher over the
# SAME check_pending line finds its now-mergeable report in ## Progress and stays silent.
closeout_fixture 417; spy_reset; we_open; rm -f "$GH_STUB_DIR/run-seq"
we_park check_pending --check claude-review --run-id 555 --attempt 1 --sha "$ESHA"
printf 'OPEN\nOPEN\nOPEN\nCLOSED\n' > "$GH_STUB_DIR/state-seq"; rj 1 completed success > "$GH_STUB_DIR/run-seq"
we_watch >/dev/null
spy_reset; printf 'OPEN\nOPEN\nCLOSED\n' > "$GH_STUB_DIR/state-seq"
we_watch >/dev/null
[ "$(we_n "merge-watch: now mergeable: claude-review green on $ESHA")" = "1" ] && [ "$(spy_count automate_escalation_recheck "$SPYLOG.webhook")" = "0" ] && ok "(E13) one line, two watchers (restart) ⇒ still exactly one now-mergeable report" || no "(E13) restart re-reported: $(we_n 'now mergeable')"

# (E14, review iteration 3 — restart latch keyed on text that does not identify the
# event) check_red_unrelated park (ci, run 777, attempt 1) → attempt 2 fails ⇒ one
# still-failing line → re-park (running → escalated) recording attempt 2 → attempt 3
# fails ⇒ a SECOND still-failing line. The restart latch is the gitignored
# `<run_id>.merge-watch-reported` sidecar (item + PR + line content), never a search
# of the whole run file. e14_flow <watcher> <fixture_n> → E14_A (lines after the
# first watcher), E14_B (after the re-parked one), E14_R (its recheck notifies).
E14_SC=".supervisor/automate/$RUN_ID.merge-watch-reported"
E14_FAIL='merge-watch: still failing: ci failure — rerun: gh run rerun 777 --failed'
e14_run() { (cd "$P" && LOOMWRIGHT_MERGE_WATCH_INTERVAL=0 LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=60 bash "$1" "$RF_REL" "$REQ" "$PRURL" </dev/null >/dev/null 2>&1); }
e14_flow() {
  closeout_fixture "$2"; spy_reset; we_open; rm -f "$GH_STUB_DIR/run-seq"
  we_park check_red_unrelated --check ci --run-id 777 --attempt 1 --sha "$ESHA"
  printf 'OPEN\nOPEN\nOPEN\nCLOSED\n' > "$GH_STUB_DIR/state-seq"; rj 2 completed failure > "$GH_STUB_DIR/run-seq"
  e14_run "$1"; E14_A="$(we_n "$E14_FAIL")"
  (cd "$P" && bash "$H" current-set "$RF_REL" --item "$REQ" --status running >/dev/null)
  we_park check_red_unrelated --check ci --run-id 777 --attempt 2 --sha "$ESHA"
  spy_reset; printf 'OPEN\nOPEN\nOPEN\nCLOSED\n' > "$GH_STUB_DIR/state-seq"; rj 3 completed failure > "$GH_STUB_DIR/run-seq"
  e14_run "$1"; E14_B="$(we_n "$E14_FAIL")"; E14_R="$(spy_count automate_escalation_recheck "$SPYLOG.webhook")"
  return 0
}
e14_flow "$WATCH" 418
[ "$E14_A" = 1 ] && [ "$E14_B" = 2 ] && [ "$E14_R" = 1 ] && [ "$(we_n "$E14_FAIL (attempt 3)")" = 1 ] && ok "(E14) AC11 after a re-park: attempt 3 red ⇒ a second still-failing line naming its attempt + one recheck notify" || no "(E14) lines=$E14_A/$E14_B notifies=$E14_R: $(grep 'still failing' "$P/$RF_REL" | tr '\n' '|')"
git -C "$P" check-ignore -q "$E14_SC" && ok "(E14) the reported-line sidecar is gitignored (not *.md ⇒ never in a trail)" || no "(E14) sidecar not gitignored"
spy_reset; printf 'OPEN\nOPEN\nCLOSED\n' > "$GH_STUB_DIR/state-seq"
e14_run "$WATCH"
[ "$(we_n "$E14_FAIL")" = 2 ] && [ "$(spy_count automate_escalation_recheck "$SPYLOG.webhook")" = 0 ] && ok "(E14) the same line across a restart ⇒ no repeat (sidecar)" || no "(E14) restart re-reported: $(we_n "$E14_FAIL")"
printf 'other-item\t%s\t%s\n' "$PRURL" "$(cut -f3- "$P/$E14_SC")" > "$P/$E14_SC"
spy_reset; printf 'OPEN\nOPEN\nCLOSED\n' > "$GH_STUB_DIR/state-seq"
e14_run "$WATCH"
[ "$(we_n "$E14_FAIL")" = 3 ] && [ "$(spy_count automate_escalation_recheck "$SPYLOG.webhook")" = 1 ] && ok "(E14) another item's sidecar entry never silences this item's line" || no "(E14) foreign sidecar suppressed: $(we_n "$E14_FAIL")"
# mutation control: replace EXACTLY the sidecar comparison with the old whole-run-file search.
MUT14="$TOP/mut14"; mkdir -p "$MUT14"; cp -R "$SPYD"/* "$MUT14/"
cat > "$TOP/mut14.line" <<'ML'
  awk -v b="merge-watch: still failing: $chk " -v r="gh run rerun ${rid:-<run_id>} --failed" 'index($0, b) && index($0, r) { f = 1 } END { exit !f }' "$rf_abs" 2>/dev/null && return 0
ML
E14_T='  [ "$(cat "$REPORTED" 2>/dev/null)" = "$key" ] && return 0'
T="$E14_T" awk 'NR == FNR { r = $0; next } $0 == ENVIRON["T"] { print r; next } { print }' "$TOP/mut14.line" "$WATCH" > "$MUT14/automate-merge-watch.sh"
if [ -s "$MUT14/automate-merge-watch.sh" ] && ! cmp -s "$WATCH" "$MUT14/automate-merge-watch.sh" && bash -n "$MUT14/automate-merge-watch.sh" \
   && [ "$(grep -cxF "$E14_T" "$WATCH")" = 1 ] && [ "$(grep -cxF "$E14_T" "$MUT14/automate-merge-watch.sh")" = 0 ] \
   && [ "$(wc -l < "$WATCH")" = "$(wc -l < "$MUT14/automate-merge-watch.sh")" ]; then
  e14_flow "$MUT14/automate-merge-watch.sh" 419
  [ "$E14_A" = 1 ] && [ "$E14_B" = 1 ] && ok "(E14) mutant (whole-run-file search restored) swallows attempt 3's report — the line-keyed sidecar is load-bearing" || no "(E14) mutant did not discriminate: lines=$E14_A/$E14_B"
else no "(E14) whole-file-search mutant invalid (empty / identical / bash -n / not a 1-for-1 line swap)"; fi

echo "== K. SKILL wiring (Part B) =="
grep -qF 'automate-merge-watch.sh' "$SKILL" && ok "SKILL names automate-merge-watch.sh" || no "SKILL lacks the watcher"
step1="$(grep -m1 -E '^1\. \*\*RECONCILE' "$SKILL")"
a="${step1%%closeout*}"; b="${step1%%PICK*}"
if [ -n "$step1" ] && [ "$a" != "$step1" ] && grep -qF -- '--session-id' <<<"$step1" && [ "${#a}" -lt "${#b}" ]; then ok "AC14: §6 step 1 runs closeout --session-id before PICK"; else no "AC14: §6 step 1 closeout wiring"; fi
hits="$(grep -nE 're-checks the PR each tick|resumes once|resume[sd]? on merge' "$SKILL" "$CMD_ALL" "$HERE/../docs/RESULT_SCHEMAS.md" "$HERE"/../docs/result-schemas/*.md "$HERE"/../docs/result-schemas/automate-run/*.md || true)"
[ -z "$hits" ] && ok "AC14: decision-9 grep has no per-tick/auto-resume claim" || no "decision-9 hits: $hits"
grep -qF '/loop` re-invokes `/automate` each tick' "$SKILL" && ok "§12's accurate /loop tick sentence kept" || no "§12 /loop sentence changed"
grep -qF 'closeout' "$HERE/../commands/automate.md" && grep -qF 'trail-pr' "$HERE/../commands/automate.md" && ok "commands/automate.md mirrors the surface" || no "commands/automate.md surface missing"

echo "== BM. branch mode: trail-pr pushes to the metadata branch (no PR), evidence-gated, loud on failure =="
# skills/automate-loop/SKILL.md §"Branch mode". Hermetic: the fixture's LOCAL bare origin, never
# GitHub; the gh stub records every call and these cases FAIL if `pr create` is ever invoked.
# The committed sidecar fixtures cite vikashruhilgit/loomwright; the stub PRs cite acme/widgets.
export LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="acme/widgets,vikashruhilgit/loomwright"
BM_MEM="$HERE/setup-memory.sh"; BM_MS="$HERE/meta-sync.sh"; BMB="loomwright-meta"
# bm_switch: run history IGNORED (the post-migration shape, so a kept check-ignore drop would push
# nothing), the branch-mode block, an allowlisted ledger, and an initialised metadata branch.
bm_switch() {
  ( cd "$P"
    printf '.supervisor/\n' > .gitignore
    bash "$BM_MEM" --root "$P" apply --branch-mode "$BMB" >/dev/null 2>&1; rm -f .gitignore.backup.*
    printf '{"repo":"acme/widgets","automate_key":"%s\\u001fx","source":"automate_drain"}\n' "$RUN_ID" > .supervisor/postmortem/results.jsonl
    bash "$BM_MS" init --root "$P" --branch "$BMB" >/dev/null 2>&1 )
}
bm_tree() { git --git-dir="$FX/origin.git" ls-tree -r --name-only "refs/heads/$BMB" 2>/dev/null; }
bm_show() { git --git-dir="$FX/origin.git" show "refs/heads/$BMB:$1" 2>/dev/null; }
bm_trail() { (cd "$P" && bash "${BM_HELPER:-$H}" trail-pr "$RF_REL0" --reason "${1:-done}"); }

# (bm-a) merged item ⇒ meta-pushed, NO PR, no trail worktree; the branch holds the stamp + run file.
new_fixture 80; bm_switch
[ "$(bash "$BM_MEM" --root "$P" mode)" = "on $BMB" ] && ok "(bm-a) fixture is in branch mode" || no "(bm-a) fixture mode: $(bash "$BM_MEM" --root "$P" mode)"
git -C "$P" check-ignore -q -- "$RF_REL0" && ok "(bm-a) the run file is gitignored (a kept check-ignore drop would push nothing)" || no "(bm-a) run file not ignored in the fixture"
stamp_req "$REQ" done "$PRL"; set_pr "$PRURL" MERGED
wt_before="$(git -C "$P" worktree list | wc -l | tr -d ' ')"
out="$(bm_trail done)"; rc=$?
[ "$rc" -eq 0 ] && case "$out" in "trail-pr: meta-pushed $BMB"*) true ;; *) false ;; esac && ok "(bm-a) mode on ⇒ '$out', exit 0" || no "(bm-a) trail-pr: '$out' rc=$rc"
[ "$(count_creates)" = 0 ] && ok "(bm-a) gh pr create NEVER invoked in branch mode" || no "(bm-a) gh pr create was invoked: $(grep '^pr create' "$GH_STUB_DIR/argv.log")"
[ "$(git -C "$P" worktree list | wc -l | tr -d ' ')" = "$wt_before" ] && ok "(bm-a) no trail worktree created" || no "(bm-a) a worktree was added"
names="$(bm_tree)"
grep -qxF -- "$RF_REL0" <<<"$names" && ok "(bm-a) the branch holds the run file" || no "(bm-a) branch tree: $names"
grep -q '^## Status: done' < <(bm_show "$REQ") && ok "(bm-a) the branch holds the MERGED item's done stamp" || no "(bm-a) stamp not on the branch"
[ -z "$(git -C "$P" ls-remote --heads origin "chore/$RUN_ID-trail-*")" ] && ok "(bm-a) no chore/<run>-trail-* branch pushed" || no "(bm-a) a trail branch was pushed"
[ ! -f "$P/.supervisor/automate/$RUN_ID.trail-staged" ] && ok "(bm-a) no .trail-staged record written" || no "(bm-a) .trail-staged written"

# (bm-b) UNMERGED item ⇒ excluded and named; its done stamp is NOT on the branch.
bm_unmerged() {  # <helper> → sets BM_OUT; 0 when the unmerged stamp stayed off the branch
  new_fixture "$1"; bm_switch; stamp_req "$REQ" done "$PRL"; set_pr "$PRURL" OPEN
  BM_OUT="$(BM_HELPER="$2" bm_trail done)"
  ! grep -q '^## Status: done' < <(bm_show "$REQ")
}
if bm_unmerged 81 "$H"; then ok "(bm-b) unmerged item's done stamp is NOT on the branch"; else no "(bm-b) unmerged stamp reached the branch"; fi
case "$BM_OUT" in "trail-pr: meta-pushed $BMB"*"; excluded $REQ — pr not merged"*) ok "(bm-b) '$BM_OUT'" ;; *) no "(bm-b) output: '$BM_OUT'" ;; esac
# Mutation control (ii): a patched copy that bypasses _evidence_gate on the mode-on push list MUST
# turn (bm-b) red.
MUTD="$TOP/bm-mut"; mkdir -p "$MUTD"; cp "$HERE"/*.sh "$HERE"/*.py "$MUTD/" 2>/dev/null; cp -R "$HERE/automate-helpers.d" "$MUTD/"; cp -R "$HERE/automate-trail.d" "$MUTD/"
awk 'skip && /^  _evidence_gate$/ { skip = 0; next } { skip = 0 } /^  TRAIL_SKIP_IGNORE_DROP=0$/ { skip = 1 } { print }' "$TB" > "$MUTD/automate-trail.sh"
if cmp -s "$TB" "$MUTD/automate-trail.sh"; then no "(bm-b) mutation control (ii): the patch changed nothing — control inconclusive"
elif bm_unmerged 82 "$MUTD/automate-helpers.sh"; then no "(bm-b) mutation control (ii) REFUTED: bypassing _evidence_gate still kept the stamp off the branch"
else ok "(bm-b) mutation control (ii): bypassing _evidence_gate puts the unmerged stamp on the branch — the assertion is load-bearing"; fi

# (bm-c) a dropped dismissed draft becomes a real deletion on the branch.
new_fixture 83; bm_switch; set_pr "$PRURL" OPEN
DRN="$RUN_ID--01-a--dismissed-1.md"; DRP=".supervisor/requirements/proposed/$DRN"
mkdir -p "$P/.supervisor/requirements/proposed"; printf '# draft\n## Status: proposed\n' > "$P/$DRP"
bm_trail done >/dev/null
grep -qxF -- "$DRP" < <(bm_tree) && ok "(bm-c) precondition: the undecided draft rode a push" || no "(bm-c) precondition: draft not on the branch"
rm -f "$P/$DRP"; printf '%s\tdrop\n' "$DRN" > "$P/.supervisor/automate/$RUN_ID.dismissed-decisions"
out="$(bm_trail done)"
grep -qxF -- "$DRP" < <(bm_tree) && no "(bm-c) the dropped draft is still on the branch ($out)" || ok "(bm-c) the dropped draft is DELETED on the branch ($out)"

# (bm-d) a push meta-sync refuses (scrub hit) is LOUD: exit 0, Progress line, notify, marker; the
# next successful push removes the marker.
new_fixture 84; bm_switch; set_pr "$PRURL" OPEN
printf -- '- t1 see /Users/someone/notes.txt\n' >> "$P/$RF_REL0"
spy_reset; : > "$SPYLOG"
out="$(cd "$P" && bash "$SPYD/automate-helpers.sh" trail-pr "$RF_REL0" --reason done)"; rc=$?
case "$out" in "trail-pr: meta-push FAILED — scrub "*) ok "(bm-d) scrub hit ⇒ '$out'" ;; *) no "(bm-d) scrub hit output: '$out'" ;; esac
[ "$rc" -eq 0 ] && ok "(bm-d) trail-pr exits 0 on a refused push" || no "(bm-d) rc=$rc"
grep -q '^- .*meta-push FAILED: scrub ' "$P/$RF_REL0" || grep -q 'meta-push FAILED: scrub ' "$P/$RF_REL0"; [ $? -eq 0 ] && ok "(bm-d) the 'meta-push FAILED:' line is in ## Progress" || no "(bm-d) no Progress line"
MK="$P/.supervisor/automate/$RUN_ID.meta-push-failed"
[ -f "$MK" ] && ok "(bm-d) the .meta-push-failed marker is written" || no "(bm-d) marker missing"
grep -q 'meta_sync: scrub ' "$MK" 2>/dev/null && ok "(bm-d) the marker carries the full scrub list" || no "(bm-d) marker lacks the scrub list"
[ "$(spy_count notify "$SPYLOG.notify")" -ge 1 ] && [ "$(spy_count automate_meta_push "$SPYLOG.webhook")" -ge 1 ] && ok "(bm-d) notify-desktop + send-webhook fired" || no "(bm-d) notify pair did not fire"
mp="$(bash "$H" meta-push-failed "$P/$RF_REL0")"
case "$mp" in *"scrub "*) ok "(bm-d) meta-push-failed prints the marker ($mp)" ;; *) no "(bm-d) meta-push-failed: '$mp'" ;; esac
[ "$(count_creates)" = 0 ] && ok "(bm-d) no gh pr create on the failure path" || no "(bm-d) pr create invoked"
grep -v '/Users/someone/' "$P/$RF_REL0" > "$P/rf.tmp" && mv "$P/rf.tmp" "$P/$RF_REL0"
out="$(bm_trail done)"
case "$out" in "trail-pr: meta-pushed $BMB"*) ok "(bm-d) the next push succeeds ($out)" ;; *) no "(bm-d) retry: '$out'" ;; esac
[ ! -f "$MK" ] && [ -z "$(bash "$H" meta-push-failed "$P/$RF_REL0")" ] && ok "(bm-d) a successful push removes the marker" || no "(bm-d) marker survived a successful push"

# (bm-e) mode unknown ⇒ loud failure, nothing pushed.
new_fixture 85; bm_switch
awk '{print} index($0, "# loomwright-meta-branch: ") == 1 {print "# loomwright-meta-branch: other"}' "$P/.gitignore" > "$P/g" && mv "$P/g" "$P/.gitignore"
out="$(bm_trail done)"
case "$out" in "trail-pr: meta-push FAILED — mode unknown "*) ok "(bm-e) mode unknown ⇒ '$out'" ;; *) no "(bm-e) mode unknown: '$out'" ;; esac
[ -f "$P/.supervisor/automate/$RUN_ID.meta-push-failed" ] && ok "(bm-e) mode unknown writes the marker" || no "(bm-e) no marker"

# (bm-f) trail-unstage in branch mode ⇒ skipped, index untouched.
new_fixture 86; bm_switch
(cd "$P" && git add -f "$RF_REL0" >/dev/null 2>&1)
idx_before="$(git -C "$P" diff --cached --name-only)"
out="$(cd "$P" && bash "$H" trail-unstage "$RF_REL0")"
[ "$out" = "trail-unstage: skipped — branch mode" ] && ok "(bm-f) '$out'" || no "(bm-f) trail-unstage: '$out'"
[ "$(git -C "$P" diff --cached --name-only)" = "$idx_before" ] && ok "(bm-f) the index is untouched" || no "(bm-f) index changed"

# (bm-g) closeout on a merged item in branch mode: no PR, the branch holds the run file + stamp.
closeout_fixture 87
( cd "$P" && git pull -q --ff-only origin main >/dev/null 2>&1 )
bm_switch
( cd "$P" && git add .gitignore && git commit -qm "branch mode" && git push -q origin main ) >/dev/null 2>&1
: > "$GH_STUB_DIR/argv.log"
out="$(cd "$P" && bash "$H" closeout "$RF_REL" "$REQ" "$PRURL")"
grep -q 'meta-pushed' <<<"$out" && ok "(bm-g) closeout's trail step meta-pushed" || no "(bm-g) closeout output: $out"
[ "$(count_creates)" = 0 ] && ok "(bm-g) closeout opened NO PR in branch mode" || no "(bm-g) pr create invoked by closeout"
grep -qxF -- "$RF_REL" < <(bm_tree) && ok "(bm-g) the branch holds the run file after closeout" || no "(bm-g) branch tree: $(bm_tree | tr '\n' ' ')"
grep -q '^## Status: done' < <(bm_show "$REQ") && ok "(bm-g) the branch holds the closed-out item's stamp" || no "(bm-g) closed-out stamp not on the branch"

# A1: the SKILL's "No park calls it" list carries meta_unreachable (it runs before the PICK lock).
case "$nopark" in *meta_unreachable*) ok "(bm) the no-park list names meta_unreachable" ;; *) no "(bm) meta_unreachable missing from the 'No park calls it' list" ;; esac

# (bm-h) a repo that NEVER opted in keeps the mode-off PR path even when its .gitignore is one the
# setup-memory WRITER refuses (read-only / conflict-marked): the mode reader decides `off` from
# content, so trail-pr must open its PR exactly as today — never route to a FAILED meta-push.
new_fixture 88; chmod 444 "$P/.gitignore"
out="$(bm_trail done)"; rc=$?
chmod 644 "$P/.gitignore"
case "$out" in "trail-pr: opened https://github.com/acme/widgets/pull/"*) [ "$rc" -eq 0 ] && ok "(bm-h) never opted in + read-only .gitignore ⇒ PR path ($out)" || no "(bm-h) read-only rc=$rc" ;; *) no "(bm-h) read-only, never opted in ⇒ '$out'" ;; esac
[ "$(count_creates)" = 1 ] && ok "(bm-h) read-only: exactly one gh pr create (mode-off path)" || no "(bm-h) read-only: pr create count $(count_creates)"
[ ! -f "$P/.supervisor/automate/$RUN_ID.meta-push-failed" ] && ok "(bm-h) read-only: no .meta-push-failed marker" || no "(bm-h) read-only: marker written"
grep -q 'meta-push FAILED' "$P/$RF_REL0" && no "(bm-h) read-only: a meta-push FAILED Progress line was appended" || ok "(bm-h) read-only: no meta-push FAILED Progress line"
new_fixture 89; printf '<<<<<<< HEAD\nzz-a/\n=======\nzz-b/\n>>>>>>> other\n' >> "$P/.gitignore"
out="$(bm_trail done)"
case "$out" in "trail-pr: opened https://github.com/acme/widgets/pull/"*) ok "(bm-h) never opted in + conflict-marked .gitignore ⇒ PR path ($out)" ;; *) no "(bm-h) conflict-marked, never opted in ⇒ '$out'" ;; esac
[ ! -f "$P/.supervisor/automate/$RUN_ID.meta-push-failed" ] && ok "(bm-h) conflict-marked: no .meta-push-failed marker" || no "(bm-h) conflict-marked: marker written"

# (bm-i) review iteration 3 — _branch_mode is FAIL-CLOSED on the answer's SHAPE. Only `off` and
# `on <non-empty>` pass through; an `on ` (empty-branch) answer is `unknown`, so trail-pr fails LOUD
# without ever invoking meta-sync; and a stripped copy (no sibling reader) treats near-miss mode text
# (no space after the colon) as `unknown`, never `off` (which would open a PR in a branch-mode repo).
BMI="$TOP/bm-i"; mkdir -p "$BMI/stub" "$BMI/strip"
cp "$HERE"/*.sh "$HERE"/*.py "$BMI/stub/" 2>/dev/null; cp -R "$HERE/automate-helpers.d" "$BMI/stub/"; cp -R "$HERE/automate-trail.d" "$BMI/stub/"; cp "$HERE"/*.sh "$HERE"/*.py "$BMI/strip/" 2>/dev/null; cp -R "$HERE/automate-helpers.d" "$BMI/strip/"; cp -R "$HERE/automate-trail.d" "$BMI/strip/"
printf '#!/bin/bash\necho "on "\n' > "$BMI/stub/setup-memory.sh"
rm -f "$BMI/strip/setup-memory.sh"
printf '#!/bin/bash\necho invoked >> "%s/ms.log"\nexit 0\n' "$BMI" > "$BMI/spy-ms.sh"
bmi_trail() { (cd "$P" && LOOMWRIGHT_META_SYNC_BIN="$BMI/spy-ms.sh" bash "$1/automate-helpers.sh" trail-pr "$RF_REL0" --reason done); }
new_fixture 90; bm_switch; rm -f "$BMI/ms.log"
out="$(bmi_trail "$BMI/stub")"
[ "$out" = "trail-pr: meta-push FAILED — mode unknown setup-memory.sh mode printed 'on '" ] && ok "(bm-i) an 'on ' (empty-branch) reader answer ⇒ '$out'" || no "(bm-i) 'on ' answer ⇒ '$out'"
[ ! -e "$BMI/ms.log" ] && ok "(bm-i) meta-sync was NEVER invoked on the empty-branch answer" || no "(bm-i) meta-sync invoked with an empty branch"
[ "$(count_creates)" = 0 ] && ok "(bm-i) no gh pr create on the empty-branch answer" || no "(bm-i) pr create invoked"
# Mutation control: the pre-fix _branch_mode (no shape check) passes `on ` through and runs meta-sync.
awk '/^  case "\$m" in$/ && !done { skip = 4; done = 1 } skip > 0 { skip--; next } { print }' "$TB" > "$BMI/stub/at.mut" && mv "$BMI/stub/at.mut" "$BMI/stub/automate-trail.sh"
if cmp -s "$TB" "$BMI/stub/automate-trail.sh"; then no "(bm-i) mutation control: the patch changed nothing — inconclusive"
else
  new_fixture 91; bm_switch; rm -f "$BMI/ms.log"; bmi_trail "$BMI/stub" >/dev/null
  [ -e "$BMI/ms.log" ] && ok "(bm-i) mutation control: without the shape check meta-sync IS invoked on 'on ' — the assertion is load-bearing" || no "(bm-i) mutation control REFUTED: meta-sync still not invoked"
fi
# Stripped copy + a no-space near-miss inside the block ⇒ unknown (loud), not the mode-off PR path.
new_fixture 92; bm_switch
sed 's/^# loomwright-meta-branch: /# loomwright-meta-branch:/' "$P/.gitignore" > "$P/g" && mv "$P/g" "$P/.gitignore"
: > "$GH_STUB_DIR/argv.log"
out="$(bmi_trail "$BMI/strip")"
[ "$out" = "trail-pr: meta-push FAILED — mode unknown setup-memory.sh is missing beside automate-trail.sh" ] && ok "(bm-i) stripped copy + no-space near-miss ⇒ '$out'" || no "(bm-i) stripped copy + near-miss ⇒ '$out'"
[ "$(count_creates)" = 0 ] && ok "(bm-i) stripped copy + near-miss: no gh pr create" || no "(bm-i) stripped copy + near-miss opened a PR"
sed "s/grep -qF 'loomwright-meta-branch' /grep -q '^# loomwright-meta-branch: ' /" "$TB" > "$BMI/strip/at.mut"
if cmp -s "$TB" "$BMI/strip/at.mut"; then no "(bm-i) fallback mutation control: the patch changed nothing — inconclusive"
else
  mv "$BMI/strip/at.mut" "$BMI/strip/automate-trail.sh"
  out="$(bmi_trail "$BMI/strip")"
  case "$out" in *"mode unknown"*) no "(bm-i) fallback mutation control REFUTED: the prefix-only grep still reads unknown ($out)" ;; *) ok "(bm-i) fallback mutation control: the prefix-only grep reads the near-miss as off ($out) — the assertion is load-bearing" ;; esac
fi
unset LOOMWRIGHT_MEMORY_REPO_ALLOWLIST

