echo "-- V7. running system (Validation 3 of automate-speed/07): PICK → RUN → DRAIN → the tail, one item"
V7="$WORK/v7"; mkdir -p "$V7/fx"
V7_PR=https://github.com/example/scratch/pull/9
cat > "$V7/fx/input.md" <<'EOF'
# Automate Run: v7 scratch backlog
## Status: running
## Source
- backlog .supervisor/requirements/v7/_BACKLOG.md
## Run Config
- mode: safe | limit: 5 | trust_unprotected: false
- auto_review_original: absent | config_backup: automate-2026-10-17-000000.config-backup.json
## Queue
- [ ] .supervisor/requirements/v7/01-scratch-item.md
- [ ] .supervisor/requirements/v7/02-next-item.md
## Current
- item: .supervisor/requirements/v7/01-scratch-item.md | status: running | pr: null | branch: null
- pause_reason: null
## Progress
- 2026-10-17T09:00:00Z picked .supervisor/requirements/v7/01-scratch-item.md
EOF
printf 'run: automate-2026-10-17-000000\nscratch: Validation 3 of automate-speed/07\n' > "$V7/fx/source"
mkdir -p "$V7/fx/tree/dot-supervisor/requirements/v7"
printf '# Scratch item\n\n## Status: pending\n\n## Task\nA one-line doc change.\n' > "$V7/fx/tree/dot-supervisor/requirements/v7/01-scratch-item.md"
printf '0\tpr view %s --json headRefOid\t{"headRefOid":"2222222222222222222222222222222222222222"}\n0\tpr view %s --json files,additions,deletions,changedFiles\t{"files":[{"path":"README.md"}],"additions":1,"deletions":0,"changedFiles":1}\n0\tpr view %s --json state\t{"state":"OPEN"}\n' "$V7_PR" "$V7_PR" "$V7_PR" > "$V7/fx/gh.stub"
V7_SUP="$(printf 'SUPERVISOR_RESULT:\n  schema_version: 1\n  task_id: v7\n  status: completed\n  pr_url: %s\n  branch: feature/v7-scratch\n  subtasks_completed: 1\n  subtasks_failed: 0\n  heal_loop_ran: true\n  heal_iterations: 1\n  heal_decision: PASS\n  heal_fixable_issues_fixed: 0\n  heal_remaining_issues: 0\n  summary: "one-line doc change"\n' "$V7_PR")"
V7_RH="$(printf 'REVIEW_HEAL_RESULT:\n  schema_version: 2\n  decision: READY\n  iterations: 1\n  issues_fixed: 0\n  remaining_issues: 0\n  pr_url: "%s"\n  notified: true\n  rounds: 1\n  fix_cycles: 0\n  repeat_check_failure: false\n  unresolved_bot_feedback: false\n  termination_reason: converged\n' "$V7_PR")"
if new_scratch "$V7/fx"; then
  hold="$(NS_REAL_LOCK=1 in_case "$DRIVER" /dev/null bash -c 'LOOMWRIGHT_HOLDER_PID='"$$"' bash "'"$HERE"'/run-lock.sh" acquire --owner "automate:'"$CASE_RUN"'" 2>&1')"; hrc=$?
  o1="$(NS_REAL_LOCK=1 in_case "$DRIVER" /dev/null bash "$DRIVER" "$CASE_RF" --start run --non-interactive --session-id v7-loop 2>"$V7/e1")"; r1=$?
  c1="$([ -f "$CASE_ROOT/.supervisor/config.json" ] && jq -c . "$CASE_ROOT/.supervisor/config.json")"
  o2="$(NS_REAL_LOCK=1 in_case "$DRIVER" /dev/null bash "$DRIVER" "$CASE_RF" \
    --result "$(jq -cn --arg t "$V7_SUP" '{supervisor_result: $t, session_id: "auto-2026-10-17-090001", run_note: "SUPERVISOR_RESULT completed: heal PASS, 1 review"}')" 2>"$V7/e2")"; r2=$?
  c2="$([ -f "$CASE_ROOT/.supervisor/config.json" ] && echo present || echo absent)"
  o3="$(NS_REAL_LOCK=1 in_case "$DRIVER" /dev/null bash "$DRIVER" "$CASE_RF" \
    --result "$(jq -cn --arg t "$V7_RH" '{review_heal_result: $t, ready_sha: "2222222222222222222222222222222222222222", progress_notes: ["drain round 1: 0 validated findings; ci green on 2222222"], drain_note: "converged, 1 round, 0 fix cycles; ci green on 2222222"}')" 2>"$V7/e3")"; r3=$?
  st_after="$(NS_REAL_LOCK=1 in_case "$DRIVER" /dev/null bash "$HERE/run-lock.sh" status 2>&1)"
  echo "V3-07> acquire (PICK's lock, real run-lock.sh): exit $hrc"
  echo "V3-07> call 1 --start run: exit $r1, $(printf '%s' "$o1" | jq -c '{do, step, what, invocation}' 2>/dev/null); config.json at the spawn: $c1"
  echo "V3-07> call 2 RUN report: exit $r2, $(printf '%s' "$o2" | jq -c '{do, step, what, invocation, head_sha}' 2>/dev/null); config.json at the drain spawn: $c2"
  echo "V3-07> call 3 DRAIN report: exit $r3, $(printf '%s' "$o3" | jq -c '{do, step, pause_reason, message}' 2>/dev/null)"
  echo "V3-07> ## Progress, auto_review suppressed .. drain READY:"
  sed -n '/auto_review suppressed/,/ drain READY /p' "$CASE_RF" | sed 's/^/V3-07>   /'
  echo "V3-07> ## Progress after it:"; sed -n '/ drain READY /,$p' "$CASE_RF" | sed '1d; s/^/V3-07>   /'
  echo "V3-07> run-lock.sh status after: $st_after"
  if [ "$hrc$r1$r2$r3" = 0000 ] && [ "$c1" = '{"auto_review":false}' ] && [ "$c2" = absent ] \
     && printf '%s' "$o1" | jq -e '.what == "/autonomous run" and .invocation == "/autonomous --single-iteration --requirement .supervisor/requirements/v7/01-scratch-item.md --non-interactive-fallback"' >/dev/null 2>&1 \
     && printf '%s' "$o2" | jq -e --arg p "$V7_PR" '.what == "owned drain" and .invocation == ("/review-pr " + $p + " --until-mergeable --no-auto-postmortem") and .head_sha == "2222222222222222222222222222222222222222"' >/dev/null 2>&1 \
     && printf '%s' "$o3" | jq -e '.do == "park" and .pause_reason == "awaiting_merge"' >/dev/null 2>&1 \
     && in_order "$CASE_RF" "auto_review suppressed (backup automate-2026-10-17-000000.config-backup.json)" "auto_review restored (config-restore: original absent)" \
          "session_id auto-2026-10-17-090001" "ran /autonomous → PR $V7_PR (SUPERVISOR_RESULT completed" \
          "owned drain started — /review-pr $V7_PR --until-mergeable --no-auto-postmortem @ 2222222222222222222222222222222222222222" \
          "drain round 1: 0 validated findings" "drain READY (converged, 1 round, 0 fix cycles" "validation-gate: none" "parked awaiting_merge $V7_PR" \
     && grep -qE -- '^- owned_drain_started: [0-9]{4}-[0-9TZ:-]+ \| owned_drain_result: READY \| suppressed_default_dispatch: true$' "$CASE_RF" \
     && grep -qF -- "- item: .supervisor/requirements/v7/01-scratch-item.md | status: awaiting_merge | pr: $V7_PR | branch: feature/v7-scratch" "$CASE_RF" \
     && [ -s "$CASE_ROOT/.supervisor/automate/$CASE_RUN.review-heal-result.md" ] && [ -s "$CASE_ROOT/.supervisor/automate/$CASE_RUN.supervisor-result.md" ] \
     && grep -q '"source":"automate_drain"' "$CASE_ROOT/.supervisor/postmortem/results.jsonl" \
     && ! grep -q "automate:$CASE_RUN" <<<"$st_after"; then
    ok "V7: PICK → RUN (suppress, /autonomous spawn, restore) → DRAIN (owned-drain spawn, pinned lines, sidecars, learning line) → awaiting_merge park; the real run lock released"
  else
    no "V7: drive wrong (acquire $hrc, calls $r1/$r2/$r3: $(cat "$V7/e1" "$V7/e2" "$V7/e3" | head -n 4 | tr '\n' ' '))"
  fi
else
  no "V7: scratch repo not built"
fi

echo "-- V8. running system (Validation 3 of automate-speed/08): a run parked awaiting_merge whose PR merged, through the resume entry"
if new_scratch "$FIX/reconcile-closeout-merged"; then
  o8="$(NS_REAL_LOCK=1 in_case "$DRIVER" /dev/null bash "$DRIVER" --resume "$CASE_ROOT/.supervisor/automate" --run "$CASE_RUN" \
    --non-interactive --session-id auto-2026-10-17-080000 2>"$WORK/v8.err")"; r8=$?
  st8="$(NS_REAL_LOCK=1 in_case "$DRIVER" /dev/null bash "$HERE/run-lock.sh" status 2>&1)"
  echo "V3-08> --resume <automate_dir> --run $CASE_RUN --non-interactive (gh stub: PR #555 MERGED): exit $r8, $(printf '%s' "$o8" | jq -c '{do, step, what, invocation}' 2>/dev/null)"
  echo "V3-08> ## Progress, the closeout lines through the next picked line:"
  sed -n '/ closeout https:\/\/github.com\/vikashruhilgit\/loomwright\/pull\/555: /,/ picked /p' "$CASE_RF" | sed 's/^/V3-08>   /'
  echo "V3-08> ## Status / ## Current after it:"; grep -E '^## Status: |^- item: |^- pause_reason: ' "$CASE_RF" | sed 's/^/V3-08>   /'
  echo "V3-08> run-lock.sh status (PICK holds it through RUN): $(printf '%s' "$st8" | head -n 1)"
  if [ "$r8" = 0 ] && printf '%s' "$o8" | jq -e '.do == "spawn" and .what == "/autonomous run" and .invocation == "/autonomous --single-iteration --requirement .supervisor/requirements/parallel-automate/18-backlog-board-and-right-size.md --non-interactive-fallback"' >/dev/null 2>&1 \
     && in_order "$CASE_RF" "closeout https://github.com/vikashruhilgit/loomwright/pull/555: closeout: reconciled" "trail-unstage: unstaged" \
          "picked .supervisor/requirements/parallel-automate/18-backlog-board-and-right-size.md" \
     && [ "$(grep -c '^- trail-gate: clear' "$CASE_RF")" = 2 ] && grep -q ' auto_review suppressed (backup ' < <(tail -n 1 "$CASE_RF") \
     && grep -qx '## Status: running' "$CASE_RF" \
     && grep -qxF -- '- [x] .supervisor/requirements/automate-followups/39a-sweep-and-janitor.md' "$CASE_RF" \
     && grep -qF -- '- item: .supervisor/requirements/parallel-automate/18-backlog-board-and-right-size.md | status: running | pr: null | branch: null' "$CASE_RF" \
     && grep -q "automate:$CASE_RUN" <<<"$st8"; then
    ok "V8: resume → PICK (real run lock) → RECONCILE closeout of the merged PR → trail gate / un-stage → current-set + picked → the /autonomous spawn"
  else
    no "V8: drive wrong (exit $r8: $(head -n 3 "$WORK/v8.err" | tr '\n' ' '))"
  fi
else
  no "V8: scratch repo not built"
fi
