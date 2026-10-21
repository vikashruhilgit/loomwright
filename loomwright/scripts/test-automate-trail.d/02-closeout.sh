# =============================================================================
# Part B — closeout + merge watcher
# =============================================================================
PRURL="https://github.com/acme/widgets/pull/7"
RF_REL=".supervisor/automate/$RUN_ID.md"

# spy copy of the scripts dir: automate-helpers.sh is a logging shim that execs
# the real helper (renamed), and captures the run-lock meta while trail-pr runs;
# notify-desktop.sh / send-webhook.sh are counters. Everything else is real.
# Every scripts-dir copy here also takes automate-helpers.d/ — the dispatcher
# sources its helper families from beside itself (parallel-automate/11).
SPYD="$TOP/spyd"; mkdir -p "$SPYD"
cp "$HERE"/*.sh "$HERE"/*.py "$SPYD/"; cp -R "$HERE/automate-helpers.d" "$SPYD/"; cp -R "$HERE/automate-trail.d" "$SPYD/"; cp -R "$HERE/setup-memory.d" "$HERE/meta-sync.d" "$HERE/automate-lanes.d" "$SPYD/"
mv "$SPYD/automate-helpers.sh" "$SPYD/automate-helpers.real.sh"
cat > "$SPYD/automate-helpers.sh" <<'SHIM'
#!/usr/bin/env bash
echo "$*" >> "$SPYLOG"
if [ "${1:-}" = trail-pr ]; then cat .supervisor/run.lock/meta >> "$SPYLOG.meta" 2>/dev/null; echo "--" >> "$SPYLOG.meta"; fi
exec bash "$(dirname "$0")/automate-helpers.real.sh" "$@"
SHIM
printf '#!/usr/bin/env bash\ncat >/dev/null\necho notify >> "$SPYLOG.notify"\nexit 0\n' > "$SPYD/notify-desktop.sh"
printf '#!/usr/bin/env bash\necho "$*" >> "$SPYLOG.webhook"\nexit 0\n' > "$SPYD/send-webhook.sh"
export SPYLOG="$TOP/spy.log"
spy_reset() { rm -f "$SPYLOG" "$SPYLOG.meta" "$SPYLOG.notify" "$SPYLOG.webhook"; }
spy_count() { grep -c "$1" "$2" 2>/dev/null || true; }

# closeout_fixture <n> [oid-override]: new_fixture, then a merged-PR world —
# feature/x pushed and SQUASH-merged into origin/main (a new commit, not the
# branch tip), the primary back on main with the PR's branch in its own
# worktree, plus an unrelated branch+worktree, and the feature PR in the stub.
closeout_fixture() {
  new_fixture "$1"
  ( cd "$P"
    git checkout -q -- README; rm -f stray.txt
    git push -q origin feature/x 2>/dev/null
    git checkout -q main
    git worktree add -q "$FX/wt-pr" feature/x 2>/dev/null
    git worktree add -q -b other "$FX/wt-other" main 2>/dev/null
  )
  git clone -q "$FX/origin.git" "$FX/merger" 2>/dev/null
  ( cd "$FX/merger" && git checkout -q main && git merge -q --squash origin/feature/x >/dev/null 2>&1 && git commit -qm "feat (#7)" && git push -q origin main 2>/dev/null )
  OID="${2:-$(git -C "$P" rev-parse feature/x)}"
  jq -n --arg u "$PRURL" --arg o "$OID" '[{number:7,url:$u,state:"MERGED",headRefName:"feature/x",headRefOid:$o}]' > "$GH_STUB_DIR/prs.json"
}
run_closeout() { (cd "$P" && bash "$SPYD/automate-helpers.sh" closeout "$RF_REL" "$REQ" "$PRURL" "$@"); }

echo "== C. closeout =="
closeout_fixture 4
# iq02 T04: seed the item's session id + pick/park so closeout's item_timing has a record to write.
# An EARLIER item (20 min, its own session) precedes it: the record must be THIS item's segment
# (closeout passes --item), never the run's first pick/park (which read 1200 s, not 3600 s).
printf -- '- 2026-10-01T08:00:00Z picked earlier.md\n- 2026-10-01T08:10:00Z session_id sess-early (earlier.md)\n- 2026-10-01T08:20:00Z parked awaiting_merge\n' >> "$P/$RF_REL"
printf -- '- 2026-10-01T10:00:00Z picked %s\n- 2026-10-01T10:30:00Z session_id sess-it (%s)\n- 2026-10-01T11:00:00Z parked awaiting_merge\n' "$REQ" "$REQ" >> "$P/$RF_REL"
mkdir -p "$P/.supervisor/logs"
(cd "$P" && bash "$H" trail-pr "$RF_REL" --reason closeout >/dev/null)   # stages trail blobs in the primary index
spy_reset
out="$(run_closeout)"; rc=$?
printf '%s\n' "$out" | sed 's/^/    | /'
[ "$rc" -eq 0 ] && ok "closeout exits 0" || no "closeout rc=$rc"
[ ! -d "$FX/wt-pr" ] && ok "AC9: the PR's worktree is removed" || no "AC9: wt-pr still present"
git -C "$P" rev-parse -q --verify refs/heads/feature/x >/dev/null && no "AC9: feature/x still present" || ok "AC9: the PR's local branch is deleted (squash-merged; tip == headRefOid)"
[ -d "$FX/wt-other" ] && git -C "$P" rev-parse -q --verify refs/heads/other >/dev/null && ok "AC9: unrelated branch + worktree untouched" || no "AC9: unrelated branch/worktree touched"
case "$out" in *"closeout: synced — main at "*) ok "sync: primary fast-forwarded over the staged trail paths" ;; *) no "sync line missing" ;; esac
[ "$(git -C "$P" rev-parse HEAD)" = "$(git -C "$FX/origin.git" rev-parse main)" ] && ok "primary main == origin/main" || no "primary not at origin/main"
grep -qxF -- "- [x] $REQ" "$P/$RF_REL" && ok "AC12: run file reads - [x] <item>" || no "AC12: item not checked off"
grep -qF '# skipped: done' "$P/$RF_REL" && no "AC12: '# skipped: done' written" || ok "AC12: never '# skipped: done'"
grep -qE "^trail-pr $P/$RF_REL --reason closeout\$" "$SPYLOG" && ok "AC12: closeout invokes trail-pr via the dispatcher (spy)" || no "AC12: trail-pr not invoked: $(cat "$SPYLOG" 2>/dev/null | tr '\n' '|')"
grep -qF '<!-- loomwright:requirement-closeout -->' "$P/$REQ" && grep -qF -- "- **PR:** $PRURL" "$P/$REQ" && grep -qF -- '- **Brief:** .supervisor/jobs/done/' "$P/$REQ" && ok "stamp: PASS-shape footer with the done/ brief" || no "stamp missing"
grep -q '^owner	automate-closeout:'"$RUN_ID"'$' "$SPYLOG.meta" && ok "trail-pr ran under the closeout's run lock" || no "lock meta during trail-pr: $(cat "$SPYLOG.meta" 2>/dev/null | tr '\n' '|')"
[ ! -d "$P/.supervisor/run.lock" ] && ok "run lock released after closeout" || no "run lock leaked"
grep -qE '^- .* closeout https://github.com/acme/widgets/pull/7: closeout: checked' "$P/$RF_REL" && ok "## Progress carries the step lines" || no "Progress lines missing"
IT="$(jq -c 'select(.event=="item_timing")' "$P/.supervisor/logs/sess-it.jsonl" 2>/dev/null)"
[ "$(printf '%s' "$IT" | jq -r '"\(.pr_url) \(.item.pick_to_park.seconds) \(has("ts"))"' 2>/dev/null)" = "$PRURL 3600 true" ] && ok "T04: closeout appends ONE item_timing event (phase-timing.sh --run --item: this item's segment, not the earlier item's) to the item's session log" || no "T04: item_timing missing/wrong: $IT"
case "$out" in *item_timing*|*phase-timing*) no "T04: item_timing step printed output (closeout prints only closeout: lines)" ;; *) ok "T04: the item_timing append is silent" ;; esac
# A session-log line carries cc_session_id only as a real id (pr_created's convention). A `null`
# one was counted as a session by build-floor's recount (`has("cc_session_id")`) — 425 vs 426.
[ "$(printf '%s' "$IT" | jq -r 'if has("cc_session_id") then (.cc_session_id | type) else "absent" end' 2>/dev/null)" != "null" ] \
  && ok "T04: item_timing never writes a null cc_session_id into the session log" \
  || no "T04: item_timing wrote cc_session_id: null: $IT"

echo "== C. closeout idempotent (AC11) =="
before_rf="$(cksum < "$P/$RF_REL")"; before_req="$(cksum < "$P/$REQ")"
before_trail="$(git -C "$FX/origin.git" for-each-ref --format='%(objectname)' 'refs/heads/chore/*')"
creates_before="$(count_creates)"
out2="$(run_closeout)"; rc=$?
printf '%s\n' "$out2" | sed 's/^/    | /'
badl="$(printf '%s\n' "$out2" | grep -v 'skipped — ' || true)"
[ -z "$badl" ] && [ "$rc" -eq 0 ] && ok "AC11: second run is all skipped lines, exit 0" || no "AC11: non-skipped line(s): $badl"
[ "$before_rf" = "$(cksum < "$P/$RF_REL")" ] && [ "$before_req" = "$(cksum < "$P/$REQ")" ] && ok "AC11: run file + requirement unchanged" || no "AC11: second run mutated files"
[ "$before_trail" = "$(git -C "$FX/origin.git" for-each-ref --format='%(objectname)' 'refs/heads/chore/*')" ] && [ "$creates_before" = "$(count_creates)" ] && ok "AC11: no push, no PR create on the second run" || no "AC11: second run pushed/created"
it_count() { jq -c 'select(.event=="item_timing")' "$1" 2>/dev/null | wc -l | tr -d ' '; }
[ "$(it_count "$P/.supervisor/logs/sess-it.jsonl")" = 1 ] && ok "AC11: the session log holds exactly ONE item_timing after the second closeout (the append is idempotent)" || no "AC11: item_timing rows after the re-run: $(it_count "$P/.supervisor/logs/sess-it.jsonl")"
grep -q '^pr merge' "$GH_STUB_DIR/argv.log" && no "gh pr merge called" || ok "closeout never calls gh pr merge"
# Control: the same two closeouts through a gated copy WITHOUT the idempotence guard append a
# second item_timing — so the exactly-ONE assertion above is load-bearing (red on the pre-fix code).
MUTI="$TOP/mutd-itiming"; mkdir -p "$MUTI"; cp "$HERE"/*.sh "$HERE"/*.py "$MUTI/"; cp -R "$HERE/automate-helpers.d" "$MUTI/"; cp -R "$HERE/automate-trail.d" "$MUTI/"; cp -R "$HERE/setup-memory.d" "$HERE/meta-sync.d" "$MUTI/"
if [ "$(grep -c 'item_timing-idempotence guard' "$TB")" != 1 ]; then no "item_timing mutant anchor is not unique"
else
  grep -v 'item_timing-idempotence guard' "$TB" > "$MUTI/automate-trail.sh"
  if [ ! -s "$MUTI/automate-trail.sh" ] || cmp -s "$TB" "$MUTI/automate-trail.sh" || ! bash -n "$MUTI/automate-trail.sh"; then no "item_timing mutant not built"
  else
    closeout_fixture 112
    printf -- '- 2026-10-01T10:00:00Z picked %s\n- 2026-10-01T10:30:00Z session_id sess-it (%s)\n- 2026-10-01T11:00:00Z parked awaiting_merge\n' "$REQ" "$REQ" >> "$P/$RF_REL"
    mkdir -p "$P/.supervisor/logs"
    (cd "$P" && bash "$MUTI/automate-helpers.sh" closeout "$RF_REL" "$REQ" "$PRURL" >/dev/null 2>&1)
    (cd "$P" && bash "$MUTI/automate-helpers.sh" closeout "$RF_REL" "$REQ" "$PRURL" >/dev/null 2>&1)
    [ "$(it_count "$P/.supervisor/logs/sess-it.jsonl")" = 2 ] && ok "control: without the guard the re-run appends a second item_timing (the AC11 exactly-ONE assertion is load-bearing)" || no "control: unguarded re-run left $(it_count "$P/.supervisor/logs/sess-it.jsonl") item_timing row(s), expected 2 — the control does not exercise the guard"
  fi
fi

echo "== C. closeout idempotent AFTER its own trail PR merged (the sync moves; nothing else may) =="
# Run automate-2026-10-01-142337: the watcher's closeout opened trail PR #329,
# the owner merged it, and RECONCILE's re-run printed only skips plus
# `synced — main at <the #329 merge>`. The sync set `did`, so the six step lines
# were appended to ## Progress and trail-pr opened #330 carrying only them. The
# AC11 leg above never merges the trail PR between runs, so its sync skips and
# it stayed green. Control: the same world with `did=1` restored on the synced
# line turns every assertion red.
MUTS="$TOP/mutd-sync"; mkdir -p "$MUTS"; cp "$HERE"/*.sh "$HERE"/*.py "$MUTS/"; cp -R "$HERE/automate-helpers.d" "$MUTS/"; cp -R "$HERE/automate-trail.d" "$MUTS/"; cp -R "$HERE/setup-memory.d" "$HERE/meta-sync.d" "$MUTS/"
[ "$(grep -c '^    sy="closeout: synced — ' "$TB")" = 1 ] || no "sync mutant anchor is not unique"
awk 'index($0, "sy=\"closeout: synced — ")==5 { print $0 "; did=1"; next } { print }' "$TB" > "$MUTS/automate-trail.sh"
for v in fixed mutant; do
  if [ "$v" = fixed ]; then closeout_fixture 110; D="$SPYD"; else closeout_fixture 111; D="$MUTS"; fi
  if [ "$v" = mutant ] && { cmp -s "$TB" "$D/automate-trail.sh" || ! bash -n "$D/automate-trail.sh"; }; then no "sync mutant not built"; continue; fi
  out1="$(cd "$P" && bash "$D/automate-helpers.sh" closeout "$RF_REL" "$REQ" "$PRURL")"
  case "$out1" in *"trail-pr: opened "*) ;; *) no "[$v] first closeout opened no trail PR: $out1"; continue ;; esac
  # The owner squash-merges the trail PR; the stub now reports it MERGED.
  TM="$FX/tmerger"; git clone -q "$FX/origin.git" "$TM" 2>/dev/null
  ( cd "$TM" && git checkout -q main && git merge -q --squash "origin/chore/$RUN_ID-trail-1" >/dev/null && git commit -qm "squash trail" && git push -q origin main 2>/dev/null )
  jq --arg h "chore/$RUN_ID-trail-1" 'map(if .headRefName == $h then .state = "MERGED" else . end)' "$GH_STUB_DIR/prs.json" > "$GH_STUB_DIR/p.tmp" && mv "$GH_STUB_DIR/p.tmp" "$GH_STUB_DIR/prs.json"
  cp "$P/$RF_REL" "$FX/rf.before"; cp "$P/$REQ" "$FX/req.before"; creates_before="$(count_creates)"
  out2="$(cd "$P" && bash "$D/automate-helpers.sh" closeout "$RF_REL" "$REQ" "$PRURL" --session-id SESS-RECONCILE)"
  printf '%s\n' "$out2" | sed "s/^/    [$v] | /"
  trail2="$(printf '%s\n' "$out2" | tail -n1)"
  if [ "$v" = fixed ]; then
    case "$out2" in *"closeout: synced — main at "*) ok "re-run after the trail merge: the sync really moved main (the leg exercises the bug's trigger)" ;; *) no "re-run did not sync — the leg does not reproduce the incident: $out2" ;; esac
    badl="$(printf '%s\n' "$out2" | sed '$d' | grep -v 'skipped — ' | grep -v '^closeout: synced — ' || true)"
    [ -z "$badl" ] && ok "re-run: every item line is skipped (only the sync moved)" || no "re-run non-skip item line(s): $badl"
    cmp -s "$FX/rf.before" "$P/$RF_REL" && ok "re-run: run file byte-identical (no skip-only ## Progress lines)" || no "re-run mutated the run file: $(diff "$FX/rf.before" "$P/$RF_REL" | tr '\n' '|')"
    cmp -s "$FX/req.before" "$P/$REQ" && ok "re-run: requirement byte-identical" || no "re-run mutated the requirement"
    case "$trail2" in "trail-pr: skipped — trail already up to date"*) ok "re-run: trail reads skipped — trail already up to date" ;; *) no "re-run trail line: $trail2" ;; esac
    [ "$creates_before" = "$(count_creates)" ] && ok "re-run: no new trail PR opened" || no "re-run opened a trail PR (the #330 incident)"
  else
    if ! cmp -s "$FX/rf.before" "$P/$RF_REL" && case "$trail2" in "trail-pr: opened "*) true ;; *) false ;; esac && [ "$creates_before" != "$(count_creates)" ]; then
      ok "control: with did=1 on the synced line the re-run appends skip lines and opens a fresh trail PR (the incident; the assertions above are load-bearing)"
    else
      no "sync control did not reproduce the incident: $trail2"
    fi
  fi
done

echo "== C. closeout reconciles a MATCHING ## Current, never a different one =="
# loomwright-studio run automate-2026-09-30-211858: after the watcher's closeout
# the Queue read `- [x] …02…` while ## Current still said awaiting_merge — a
# self-contradictory run file whose next resume re-ran reconcile + closeout.
cur_block() { awk '/^## Current/{c=1} /^## Progress/{c=0} c' "$1"; }
# (i) matching item + PR, ## Status: paused ⇒ status done, pause_reason awaiting_go.
closeout_fixture 101
out="$(run_closeout)"
grep -qxF -- "- item: $REQ | status: done | pr: $PRURL | branch: feature/x" "$P/$RF_REL" \
  && grep -qxF -- "- pause_reason: awaiting_go" "$P/$RF_REL" \
  && ok "## Current (matching item+PR, paused): status done + pause_reason awaiting_go" || no "## Current not reconciled: $(cur_block "$P/$RF_REL" | tr '\n' '|')"
grep -qxF -- "## Status: paused" "$P/$RF_REL" && ok "## Status is never rewritten by closeout" || no "## Status changed: $(grep '^## Status' "$P/$RF_REL")"
grep -qE "^- .* closeout $PRURL: closeout: reconciled — ## Current " "$P/$RF_REL" && ok "## Progress records the ## Current reconcile" || no "no Progress line for the reconcile"
case "$out" in *"closeout: reconciled — ## Current $REQ status done, pause_reason awaiting_go"*) ok "closeout prints the reconciled line" ;; *) no "reconciled line missing: $out" ;; esac
# Control (red without the fix): closeout with step 7b deleted leaves the studio state.
MUTD="$TOP/mutd-current"; mkdir -p "$MUTD"; cp "$HERE"/*.sh "$HERE"/*.py "$MUTD/"; cp -R "$HERE/automate-helpers.d" "$MUTD/"; cp -R "$HERE/automate-trail.d" "$MUTD/"; cp -R "$HERE/setup-memory.d" "$HERE/meta-sync.d" "$MUTD/"
sed '/^  cu="\$(_co_current "\$rf_rel" "\$item" "\$pr_url")"$/d' "$TB" > "$MUTD/automate-trail.sh"
if ! cmp -s "$TB" "$MUTD/automate-trail.sh" && bash -n "$MUTD/automate-trail.sh"; then
  closeout_fixture 102
  (cd "$P" && bash "$MUTD/automate-helpers.sh" closeout "$RF_REL" "$REQ" "$PRURL" >/dev/null)
  grep -qxF -- "- [x] $REQ" "$P/$RF_REL" && grep -qxF -- "- pause_reason: awaiting_merge" "$P/$RF_REL" \
    && ok "control: without step 7b the item is checked off while ## Current still says awaiting_merge (the incident)" || no "control did not reproduce the incident: $(cur_block "$P/$RF_REL" | tr '\n' '|')"
else
  no "control mutant not built"
fi
# (iii) matching item + PR inside a LIVE loop (RECONCILE's closeout, ## Status:
#       running) ⇒ status done + pause_reason null (a running run is not paused).
closeout_fixture 105
(cd "$P" && sed -i.bak 's/^## Status: paused$/## Status: running/' "$RF_REL" && rm -f "$RF_REL.bak")
run_closeout >/dev/null
grep -qxF -- "- item: $REQ | status: done | pr: $PRURL | branch: feature/x" "$P/$RF_REL" \
  && grep -qxF -- "- pause_reason: null" "$P/$RF_REL" && grep -qxF -- "## Status: running" "$P/$RF_REL" \
  && ok "## Current (matching item+PR, running): status done + pause_reason null; ## Status stays running" || no "running-branch reconcile wrong: $(cur_block "$P/$RF_REL" | tr '\n' '|')"
# Control (red without the branch): want forced to awaiting_go regardless of status.
MUTW="$TOP/mutd-want"; mkdir -p "$MUTW"; cp "$HERE"/*.sh "$HERE"/*.py "$MUTW/"; cp -R "$HERE/automate-helpers.d" "$MUTW/"; cp -R "$HERE/automate-trail.d" "$MUTW/"; cp -R "$HERE/setup-memory.d" "$HERE/meta-sync.d" "$MUTW/"
sed 's/^  if \[ "\$run_status" = "paused" \]; then want="awaiting_go"; else want="null"; fi$/  want="awaiting_go"/' "$TB" > "$MUTW/automate-trail.sh"
if ! cmp -s "$TB" "$MUTW/automate-trail.sh" && bash -n "$MUTW/automate-trail.sh"; then
  closeout_fixture 106
  (cd "$P" && sed -i.bak 's/^## Status: paused$/## Status: running/' "$RF_REL" && rm -f "$RF_REL.bak")
  (cd "$P" && bash "$MUTW/automate-helpers.sh" closeout "$RF_REL" "$REQ" "$PRURL" >/dev/null)
  grep -qxF -- "- pause_reason: awaiting_go" "$P/$RF_REL" \
    && ok "control: without the status branch a running run is mis-written awaiting_go (the null assertion is load-bearing)" || no "want control did not discriminate: $(cur_block "$P/$RF_REL" | tr '\n' '|')"
else
  no "want mutant not built"
fi
# (ii) ## Current names a LATER item/PR (the watcher fired after the owner
#      resumed and picked 02-b) ⇒ ## Current byte-identical; the check-off still lands.
closeout_fixture 103
LATER=".supervisor/requirements/f/02-b.md"
( cd "$P"
  awk -v L="$LATER" '/^- item: /{print "- item: " L " | status: running | pr: https://github.com/acme/widgets/pull/8 | branch: feature/y"; next}
       /^- pause_reason:/{print "- pause_reason: null"; next} {print}' "$RF_REL" > "$RF_REL.tmp" && mv "$RF_REL.tmp" "$RF_REL"
  sed -i.bak 's/^## Status: paused$/## Status: running/' "$RF_REL" && rm -f "$RF_REL.bak" )
before_cur="$(cur_block "$P/$RF_REL")"
out="$(run_closeout)"
[ "$before_cur" = "$(cur_block "$P/$RF_REL")" ] && ok "## Current naming a different item/PR is left byte-identical" || no "## Current clobbered: $(cur_block "$P/$RF_REL" | tr '\n' '|')"
case "$out" in *"closeout: skipped — ## Current is $LATER (https://github.com/acme/widgets/pull/8), not this item/PR"*) ok "closeout names the non-matching ## Current it skipped" ;; *) no "non-matching skip line missing: $out" ;; esac
grep -qxF -- "- [x] $REQ" "$P/$RF_REL" && ok "the closed-out item is still checked off" || no "check-off lost"
# Control (red without the guard): the same world, closeout with the item/PR
# comparison neutered, overwrites the later item's ## Current.
MUTG="$TOP/mutd-guard"; mkdir -p "$MUTG"; cp "$HERE"/*.sh "$HERE"/*.py "$MUTG/"; cp -R "$HERE/automate-helpers.d" "$MUTG/"; cp -R "$HERE/automate-trail.d" "$MUTG/"; cp -R "$HERE/setup-memory.d" "$HERE/meta-sync.d" "$MUTG/"
sed 's/^  if \[ "\$cur_item" != "\$item" \] || \[ "\$cur_pr" != "\$pr" \]; then$/  if false; then/' "$TB" > "$MUTG/automate-trail.sh"
if ! cmp -s "$TB" "$MUTG/automate-trail.sh" && bash -n "$MUTG/automate-trail.sh"; then
  closeout_fixture 104
  ( cd "$P"
    awk -v L="$LATER" '/^- item: /{print "- item: " L " | status: running | pr: https://github.com/acme/widgets/pull/8 | branch: feature/y"; next}
         /^- pause_reason:/{print "- pause_reason: null"; next} {print}' "$RF_REL" > "$RF_REL.tmp" && mv "$RF_REL.tmp" "$RF_REL" )
  (cd "$P" && bash "$MUTG/automate-helpers.sh" closeout "$RF_REL" "$REQ" "$PRURL" >/dev/null)
  grep -qF -- "- item: $LATER | status: done" "$P/$RF_REL" \
    && ok "control: without the item/PR guard the later item's ## Current is clobbered to done" || no "guard control did not discriminate: $(cur_block "$P/$RF_REL" | tr '\n' '|')"
else
  no "guard mutant not built"
fi

echo "== C. closeout after a PICK un-stage (decision 4 kept) =="
# trail PR squash-merged, then trail-unstage (as PICK runs it), then the live
# run file gains bytes: closeout's sync must still fast-forward — it re-stages
# the recorded trail blobs that landed on origin/main right before its pull.
for variant in record no-record; do
  if [ "$variant" = record ]; then closeout_fixture 13; else closeout_fixture 14; fi
  (cd "$P" && bash "$H" trail-pr "$RF_REL" --reason closeout >/dev/null)
  TM="$FX/tmerger"; git clone -q "$FX/origin.git" "$TM" 2>/dev/null
  ( cd "$TM" && git checkout -q main && git merge -q --squash "origin/chore/$RUN_ID-trail-1" >/dev/null && git commit -qm "squash trail" && git push -q origin main 2>/dev/null )
  (cd "$P" && bash "$H" trail-unstage "$RF_REL" >/dev/null)
  echo "- t9 live progress after the un-stage" >> "$P/$RF_REL"
  [ "$variant" = no-record ] && rm -f "$P/.supervisor/automate/$RUN_ID.trail-staged"
  out="$(run_closeout)"
  if [ "$variant" = record ]; then
    [ -z "$(printf '%s' "$out" | grep 'git pull --ff-only refused')" ] && case "$out" in *"closeout: synced — main at "*) true ;; *) false ;; esac \
      && ok "after un-stage: closeout's sync fast-forwards over the merged trail" || no "after un-stage sync: $out"
    [ "$(git -C "$P" rev-parse HEAD)" = "$(git -C "$FX/origin.git" rev-parse main)" ] && ok "after un-stage: primary main == origin/main" || no "after un-stage: main not synced"
    grep -q 't9 live progress' "$P/$RF_REL" && grep -q 'other-run' "$P/.supervisor/postmortem/results.jsonl" && ok "after un-stage: live run-file bytes + other-run ledger lines survive" || no "after un-stage: local bytes lost"
  else
    case "$out" in *"closeout: skipped — git pull --ff-only refused"*) ok "control: without the record the same pull refuses (the re-stage is load-bearing)" ;; *) no "control did not refuse: $out" ;; esac
  fi
done

echo "== C. closeout: a self-staged trail path that is no longer a candidate =="
# park1 commits a good review-heal sidecar → PICK trail-unstage → the sidecar is
# rewritten and now FAILS sidecar-check → park2 pushes (sidecar excluded) but
# _stage_tip re-stages its tip blob (AM). That entry is this run's own trail
# (in the trail-staged record), so closeout's sync must not call it "outside";
# a genuinely foreign modification in the same world must still refuse.
SC=".supervisor/automate/$RUN_ID.review-heal-result.md"
for variant in own foreign; do
  if [ "$variant" = own ]; then closeout_fixture 15; else closeout_fixture 16; fi
  (cd "$P" && bash "$H" trail-pr "$RF_REL" --reason closeout >/dev/null)
  (cd "$P" && bash "$H" trail-unstage "$RF_REL" >/dev/null)
  echo "not a result block" > "$P/$SC"
  echo "- t5 parked again" >> "$P/$RF_REL"
  out="$(cd "$P" && bash "$H" trail-pr "$RF_REL" --reason done)"
  case "$out" in "trail-pr: pushed "*"excluded $SC"*) ok "[$variant] second park pushes with the sidecar excluded" ;; *) no "[$variant] second park: $out" ;; esac
  case "$(git -C "$P" status --porcelain --untracked-files=no -- "$SC")" in "AM $SC") ok "[$variant] sidecar is self-staged (AM) from the trail tip" ;; *) no "[$variant] sidecar status: $(git -C "$P" status --porcelain -- "$SC")" ;; esac
  [ "$variant" = foreign ] && ( cd "$P" && echo "foreign edit" > README )
  out="$(run_closeout)"
  if [ "$variant" = own ]; then
    case "$out" in *"outside the trail paths"*) no "own: self-staged sidecar counted as outside: $out" ;; *"closeout: synced — main at "*) ok "own: closeout syncs over its own self-staged non-candidate sidecar" ;; *) no "own: sync line: $out" ;; esac
    [ "$(git -C "$P" rev-parse HEAD)" = "$(git -C "$FX/origin.git" rev-parse main)" ] && ok "own: primary main == origin/main" || no "own: main not synced"
  else
    case "$out" in *"closeout: skipped — uncommitted changes outside the trail paths (README)"*) ok "foreign: a foreign modification still refuses, and only it is named" ;; *) no "foreign: $out" ;; esac
  fi
done

echo "== C. closeout guards (AC10, AC11) =="
closeout_fixture 5 "0000000000000000000000000000000000000000"
( cd "$P" && echo "edited readme" > README )
out="$(run_closeout)"
case "$out" in *"closeout: skipped — local tip "*" != merged head 000000000000 (feature/x kept)"*) ok "AC10: tip != headRefOid ⇒ branch kept + skipped" ;; *) no "AC10 tip: $out" ;; esac
git -C "$P" rev-parse -q --verify refs/heads/feature/x >/dev/null && ok "AC10: feature/x still present" || no "AC10: branch deleted despite tip mismatch"
case "$out" in *"closeout: skipped — uncommitted changes outside the trail paths (README)"*) ok "AC10: primary dirty outside trail paths ⇒ sync skipped" ;; *) no "AC10 dirty sync: $out" ;; esac

closeout_fixture 6
echo scratch > "$FX/wt-pr/wip.txt"
out="$(run_closeout)"
salv="$(ls -d "$P"/.supervisor/salvage/wt-pr-* 2>/dev/null | head -n1)"
[ -n "$salv" ] && [ -f "$salv/untracked/wip.txt" ] && ok "AC10: dirty worktree salvaged ($salv)" || no "AC10: no salvage dir"
[ -d "$FX/wt-pr" ] && ok "AC10: still-dirty worktree kept (decision 6 step 3: remove only when clean after salvage)" || no "AC10: dirty worktree removed"
case "$out" in *"closeout: skipped — kept worktree $FX/wt-pr still dirty after salvage"*) ok "AC10: kept line names the salvage" ;; *) no "AC10 kept line: $out" ;; esac
git -C "$P" rev-parse -q --verify refs/heads/feature/x >/dev/null && ok "branch in a kept worktree is not deleted" || no "branch deleted under a kept worktree"

closeout_fixture 7
jq '.[0].state = "OPEN"' "$GH_STUB_DIR/prs.json" > "$GH_STUB_DIR/p.tmp" && mv "$GH_STUB_DIR/p.tmp" "$GH_STUB_DIR/prs.json"
out="$(run_closeout)"
[ "$out" = "closeout: skipped — pr not merged (awaiting_merge)" ] && ok "AC10: OPEN ⇒ one skipped line" || no "AC10 OPEN: $out"
[ -d "$FX/wt-pr" ] && git -C "$P" rev-parse -q --verify refs/heads/feature/x >/dev/null && grep -qxF -- "- [ ] $REQ" "$P/$RF_REL" && ok "AC10: OPEN ⇒ nothing removed or checked off" || no "AC10: OPEN mutated state"
out="$(cd "$P" && LOOMWRIGHT_GH_BIN="$TOP/no-such-gh" bash "$H" closeout "$RF_REL" "$REQ" "$PRURL")"; rc=$?
[ "$out" = "closeout: skipped — gh unavailable" ] && [ "$rc" -eq 0 ] && ok "AC11: gh absent ⇒ skipped, exit 0" || no "gh absent: $out rc=$rc"
out="$(cd "$P" && bash "$H" closeout ".supervisor/automate/nope.md" "$REQ" "$PRURL")"; rc=$?
[ "$out" = "closeout: skipped — run file not found" ] && [ "$rc" -eq 0 ] && ok "missing run file ⇒ skipped, exit 0" || no "missing run file: $out rc=$rc"

echo "== C. closeout 3a: a head-branch worktree at another tip is kept (M1) =="
# `git worktree remove` (no --force) deletes GITIGNORED content, which
# worktree-salvage.sh skips by design; a same-named branch reused for other work
# (worktree HEAD != headRefOid) must be kept with its gitignored .env intact.
for variant in moved match; do
  if [ "$variant" = moved ]; then closeout_fixture 31; else closeout_fixture 32; fi
  mkdir -p "$P/.git/info"; echo ".env" >> "$P/.git/info/exclude"
  echo "SECRET=1" > "$FX/wt-pr/.env"
  git -C "$FX/wt-pr" check-ignore -q .env && ok "[$variant] setup: .env is gitignored in the PR worktree" || no "[$variant] .env not ignored"
  [ "$variant" = moved ] && ( cd "$FX/wt-pr" && echo more > more.txt && git add more.txt && git commit -qm "other work, same branch name" )
  out="$(run_closeout)"
  if [ "$variant" = moved ]; then
    [ -d "$FX/wt-pr" ] && [ "$(cat "$FX/wt-pr/.env" 2>/dev/null)" = "SECRET=1" ] && ok "moved: worktree at another tip kept, gitignored .env intact" || no "moved: worktree/.env lost"
    case "$out" in *"closeout: skipped — kept worktree $FX/wt-pr (tip "*" != merged head "*) ok "moved: the kept line names the tip mismatch" ;; *) no "moved: kept line: $out" ;; esac
    git -C "$P" rev-parse -q --verify refs/heads/feature/x >/dev/null && ok "moved: branch at another tip kept" || no "moved: branch deleted"
  else
    [ ! -d "$FX/wt-pr" ] && ok "match: worktree at the merged head is removed" || no "match: worktree kept: $out"
  fi
done

echo "== C. closeout: a refused pull restores the re-staged index entries (L6) =="
# After a PICK un-stage over a merged trail PR, closeout re-stages the landed
# blobs right before its pull; when that pull refuses (a local commit diverges
# main), the index must go back to its prior state. trail-pr is stubbed out so
# its own checkout-contract staging does not mask the assertion; a mutant
# without the restore call is the control.
L6D="$TOP/l6d"; mkdir -p "$L6D"; cp "$SPYD"/*.sh "$SPYD"/*.py "$L6D/"; cp -R "$SPYD/automate-helpers.d" "$L6D/"; cp -R "$SPYD/automate-trail.d" "$L6D/"; cp -R "$SPYD/setup-memory.d" "$SPYD/meta-sync.d" "$L6D/"
cat > "$L6D/automate-helpers.sh" <<'SHIM'
#!/usr/bin/env bash
if [ "${1:-}" = trail-pr ]; then echo "trail-pr: skipped — stubbed"; exit 0; fi
exec bash "$(dirname "$0")/automate-helpers.real.sh" "$@"
SHIM
L6M="$TOP/l6m"; mkdir -p "$L6M"; cp "$L6D"/*.sh "$L6D"/*.py "$L6M/"; cp -R "$L6D/automate-helpers.d" "$L6M/"; cp -R "$L6D/automate-trail.d" "$L6M/"
sed 's/^\([[:space:]]*\)_restore_prior$/\1:/' "$TB" > "$L6M/automate-trail.sh"
for variant in fixed mutant; do
  if [ "$variant" = fixed ]; then closeout_fixture 33; D="$L6D"; else closeout_fixture 34; D="$L6M"; fi
  (cd "$P" && bash "$H" trail-pr "$RF_REL" --reason closeout >/dev/null)
  TM="$FX/tmerger"; git clone -q "$FX/origin.git" "$TM" 2>/dev/null
  ( cd "$TM" && git checkout -q main && git merge -q --squash "origin/chore/$RUN_ID-trail-1" >/dev/null && git commit -qm "squash trail" && git push -q origin main 2>/dev/null )
  (cd "$P" && bash "$H" trail-unstage "$RF_REL" >/dev/null)
  git -C "$P" commit -q --allow-empty -m "local diverging commit"
  pre_idx="$(git -C "$P" ls-files -s | env LC_ALL=C sort)"
  out="$(cd "$P" && bash "$D/automate-helpers.sh" closeout "$RF_REL" "$REQ" "$PRURL")"
  case "$out" in *"closeout: skipped — git pull --ff-only refused"*) ok "[$variant] diverged main ⇒ the pull refuses" ;; *) no "[$variant] pull did not refuse: $out" ;; esac
  post_idx="$(git -C "$P" ls-files -s | env LC_ALL=C sort)"
  if [ "$variant" = fixed ]; then
    [ "$pre_idx" = "$post_idx" ] && [ -z "$(git -C "$P" diff --cached --name-only)" ] && ok "fixed: index restored to its pre-closeout state (nothing staged)" || no "fixed: index changed: $(git -C "$P" diff --cached --name-only | tr '\n' ' ')"
  else
    [ "$pre_idx" != "$post_idx" ] && ok "mutation control: without _restore_prior the re-staged entries stay staged" || no "mutant left the index unchanged — the restore assertion is vacuous"
  fi
done

echo "== T. Queue candidates are requirement files only (L5) =="
new_fixture 35
( cd "$P" && mkdir -p src && echo "v1" > src/app.py && git add src/app.py && git commit -qm app && echo "local WIP" >> src/app.py )
awk '{print} /^## Queue$/{print "- [ ] src/app.py"}' "$P/$RF_REL0" > "$TOP/rf35" && mv "$TOP/rf35" "$P/$RF_REL0"
grep -qxF -- '- [ ] src/app.py' "$P/$RF_REL0" && ok "setup: a Queue item names a tracked source file" || no "setup: Queue edit failed"
(cd "$P" && bash "$H" trail-pr "$RF_REL0" --reason closeout >/dev/null)
names="$(git -C "$FX/origin.git" show --name-only --format= "refs/heads/chore/$RUN_ID-trail-1" 2>/dev/null)"
case "$names" in *src/app.py*) no "L5: source file's local WIP committed into the trail: $names" ;; *"$REQ"*) ok "L5: source-file Queue item not committed; requirement still is" ;; *) no "L5: trail names: $names" ;; esac

