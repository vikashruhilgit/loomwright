echo "-- G. golden parity (AC1)"
missing=""
for c in $REQUIRED_CASES; do [ -f "$FIX/$c/next-step.results" ] || missing="$missing $c"; done
for d in "$FIX"/gate-eval-*-park; do [ -f "$d/next-step.results" ] || missing="$missing $(basename "$d")"; done
[ -z "$missing" ] && ok "every required TAIL case carries next-step.results" || no "next-step.results missing:$missing"
sel="${NS_CASES:-}"
if [ -z "$sel" ]; then
  for d in "$FIX"/*/next-step.results; do sel="$sel $(basename "$(dirname "$d")")"; done
fi
for c in $sel; do
  GC_MSG=""; GC_DIFF=""
  if golden_case "$c" "$DRIVER"; then ok "$c: run file matches expected.md"
  else no "$c: $GC_MSG"; [ -n "$GC_DIFF" ] && printf '%s\n' "$GC_DIFF" | sed 's/^/    /'; fi
done
[ -n "${NS_CASES:-}" ] && { echo "PASS: $pass FAIL: $fail"; [ "$fail" -eq 0 ]; exit $?; }

echo "-- I. idempotency (AC2)"
for c in escalated-park park-first-ready-park gate-validation-gate-unrun-escalated; do
  LEG_MSG=""
  if leg_idem "$c" "$DRIVER"; then ok "I $c: two no-result calls re-print the instruction, nothing written"
  else no "I $c: $LEG_MSG"; fi
done

# replay: the case's own first drain report sent again after its terminal park re-prints it, writes nothing
if golden_case escalated-park "$DRIVER"; then
  last="$LAST_OUT"; s0="$(snapshot)"
  grep -m1 '^call: ' "$FIX/escalated-park/next-step.results" > "$CASE_DIR/replay.results"
  drive "$FIX/escalated-park" "$DRIVER" "$CASE_DIR/replay.results"
  if [ -z "$DRIVE_ERR" ] && [ "$LAST_OUT" = "$last" ] && [ "$s0" = "$(snapshot)" ]; then
    ok "I replay: the same drain report after the terminal park re-prints it, nothing written"
  else no "I replay: a replayed drain report re-ran the tail ($DRIVE_ERR)"; fi
else no "I replay: escalated-park did not run: $GC_MSG"; fi

echo "-- Q. question gates (AC3)"
LEG_MSG=""
if leg_cantask "$DRIVER"; then ok "Q: --non-interactive never asks (validation_unrun park; pending_decisions: 2 recorded)"
else no "Q: $LEG_MSG"; fi
# one interactive leftover ask, so AUT-LEFTOVER's shape is checked too
new_scratch "$FIX/closeout-leftover-gate-non-interactive" \
  && printf '%s\n' 'env: NEXT_STEP_FROM=sync NEXT_STEP_CLOSEOUT_OUT=$ROOT/closeout.out' "call:" "expect: ask" > "$CASE_DIR/lo.results" \
  && drive "$FIX/closeout-leftover-gate-non-interactive" "$DRIVER" "$CASE_DIR/lo.results"
[ -z "$DRIVE_ERR" ] && ok "Q: an interactive close-out leftover asks (AUT-LEFTOVER)" || no "Q: leftover ask: $DRIVE_ERR"
n_ask="$(grep -c . "$ASKS" || true)"
bad="$(cut -f2- "$ASKS" | jq -c 'select((.question | type) != "string" or (.question | length) == 0
    or (.header | type) != "string" or (.options | type) != "array" or (.options | length) == 0
    or (.cant_ask | type) != "string" or (.cant_ask | length) == 0)' 2>&1)"
gates="$(cut -f2- "$ASKS" | jq -r '.gate' 2>/dev/null | env LC_ALL=C sort -u | tr '\n' ' ')"
if [ "$n_ask" -gt 0 ] && [ -z "$bad" ]; then ok "Q: all $n_ask ask(s) carry question, header, options, cant_ask (gates: $gates)"
else no "Q: $n_ask ask(s); malformed: ${bad:-none}"; fi
# Every ask — human-only gates included — names its gate in every header and offers exactly the catalog's
# labels (all of them, or a row's non-`?` core): wave 7 relayed AUT-WAIVE / AUT-DISMISS asks with header "".
CATJ="$(bash "$HERE/lane-policy.sh" catalog | jq -Rnc '[inputs | split("\t") | (.[2] | split("|")) as $l
  | {key: .[0], value: {all: ($l | map(sub("[?!]$"; "")) | sort), core: ($l | map(select(endswith("?") | not) | sub("!$"; "")) | sort)}}] | from_entries')"
drift="$(cut -f2- "$ASKS" | jq -c --argjson cat "$CATJ" '.gate as $g | select(.header != $g or any(.questions[]; .header != $g)
    or any(.questions[]; (.options | sort) as $o | ($cat[.header] // {}) as $r | $o != $r.all and $o != $r.core)) | .gate' 2>&1)"
gates_seen="$(cut -f2- "$ASKS" | jq -r '.gate' | env LC_ALL=C sort -u | tr '\n' ' ')"
case "$gates_seen" in *AUT-WAIVE*AUT-DISMISS*|*AUT-DISMISS*AUT-WAIVE*) gs_ok=1 ;; *) gs_ok=0 ;; esac
if [ -z "$drift" ] && [ "$gs_ok" = 1 ]; then ok "Q: every ask's header is its gate code and its options are the catalog's labels (gates: $gates_seen)"
else no "Q: header/label drift in [${drift:-none}] (gates seen: $gates_seen)"; fi
if cut -f2- "$ASKS" | jq -e 'select(.gate == "AUT-SUMMARY") | select(.header != "AUT-SUMMARY" or .options != ["Keep summary","Drop summary"])' >/dev/null 2>&1; then
  no "Q: an AUT-SUMMARY ask lacks its code or labels"
else ok "Q: AUT-SUMMARY asks carry header AUT-SUMMARY and exactly its two labels"; fi

echo "-- S. merge-surface invariant (AC4)"
LEG_MSG=""
if leg_surface "$DRIVER"; then ok "S: the positive-grep file list equals the base commit's (driver absent from it)"; else no "S: $LEG_MSG"; fi
grep -qF 'bash "$H" gate-eval "$PR" "$CTXF" --root "$ROOT"' "$DRIVER" && ok "S: the driver calls automate-helpers.sh gate-eval" \
  || no "S: the driver does not call automate-helpers.sh gate-eval"

echo "-- C. ctx shape (AC5)"
LEG_MSG=""
if leg_ctx "$DRIVER"; then ok "C: gate-eval-merge ctx carries exactly the six keys"; else no "C: $LEG_MSG"; fi

echo "-- V. running system (Validation 3)"
V3="$WORK/v3"; mkdir -p "$V3/fx"
cat > "$V3/fx/input.md" <<'EOF'
# Automate Run: v3 scratch backlog
## Status: running
## Source
- backlog .supervisor/requirements/v3/_BACKLOG.md
## Run Config
- mode: safe | limit: 5 | trust_unprotected: false
- auto_review_original: absent | config_backup: automate-2026-10-16-000000.config-backup.json
## Queue
- [ ] .supervisor/requirements/v3/01-scratch-item.md
- [ ] .supervisor/requirements/v3/02-next-item.md
## Current
- item: .supervisor/requirements/v3/01-scratch-item.md | status: running | pr: https://github.com/example/scratch/pull/7 | branch: feature/v3-scratch
- pause_reason: null
- owned_drain_started: 2026-10-16T10:00:00Z | owned_drain_result: READY | suppressed_default_dispatch: true
## Progress
- 2026-10-16T09:00:00Z picked .supervisor/requirements/v3/01-scratch-item.md
- 2026-10-16T09:40:00Z ran /autonomous → PR https://github.com/example/scratch/pull/7
- 2026-10-16T10:00:00Z owned drain started — /review-pr https://github.com/example/scratch/pull/7 --until-mergeable --no-auto-postmortem @ 1111111111111111111111111111111111111111
- 2026-10-16T10:20:00Z drain READY (converged, 1 round, 0 fix cycles)
EOF
printf 'run: automate-2026-10-16-000000\nscratch: Validation 3 of automate-speed/06\n' > "$V3/fx/source"
mkdir -p "$V3/fx/tree/dot-supervisor/requirements/v3"
printf '# Scratch item\n\n## Status: pending\n\n## Task\nA one-line doc change.\n' > "$V3/fx/tree/dot-supervisor/requirements/v3/01-scratch-item.md"
printf '0\tpr view https://github.com/example/scratch/pull/7 --json state\t{"state":"OPEN"}\n' > "$V3/fx/gh.stub"
if new_scratch "$V3/fx"; then
  hold="$(NS_REAL_LOCK=1 LOOMWRIGHT_HOLDER_PID=$$ in_case "$DRIVER" /dev/null bash -c 'LOOMWRIGHT_HOLDER_PID='"$$"' bash "'"$HERE"'/run-lock.sh" acquire --owner "automate:'"$CASE_RUN"'" 2>&1')"; hrc=$?
  out="$(NS_REAL_LOCK=1 in_case "$DRIVER" /dev/null bash "$DRIVER" "$CASE_RF" \
    --result '{"drain_result":"READY","termination_reason":"converged","ready_sha":"1111111111111111111111111111111111111111"}' 2>"$V3/err")"; vrc=$?
  st_after="$(NS_REAL_LOCK=1 in_case "$DRIVER" /dev/null bash "$HERE/run-lock.sh" status 2>&1)"
  echo "V3> acquire (PICK's lock, real run-lock.sh): exit $hrc"
  echo "V3> driver exit $vrc, instruction: $out"
  echo "V3> run-lock.sh status after: $st_after"
  echo "V3> ## Status / ## Current:"; grep -E '^## Status: |^- item: |^- pause_reason: |^- pending_decisions: ' "$CASE_RF" | sed 's/^/V3>   /'
  echo "V3> tail ## Progress:"; tail -n 5 "$CASE_RF" | sed 's/^/V3>   /'
  echo "V3> recorded side effects:"; sed 's/^/V3>   /' "$CASE_DIR/rec.log"
  if [ "$hrc" -eq 0 ] && [ "$vrc" -eq 0 ] && printf '%s' "$out" | jq -e '.do == "park" and .pause_reason == "awaiting_merge"' >/dev/null 2>&1 \
     && grep -qxF '## Status: paused' "$CASE_RF" \
     && grep -qF -- '- item: .supervisor/requirements/v3/01-scratch-item.md | status: awaiting_merge |' "$CASE_RF" \
     && grep -qE -- '^- [0-9TZ:-]+ parked awaiting_merge https://github.com/example/scratch/pull/7 — 0 dismissed decision\(s\) pending$' "$CASE_RF" \
     && grep -qxF "watch $CASE_RF .supervisor/requirements/v3/01-scratch-item.md https://github.com/example/scratch/pull/7" "$CASE_DIR/rec.log" \
     && ! grep -q "automate:$CASE_RUN" <<<"$st_after"; then
    ok "V: one item's tail from a READY drain report to the awaiting_merge park (watcher armed, the real run lock released)"
  else
    no "V: tail run wrong (acquire $hrc, driver $vrc: $(head -n 3 "$V3/err" | tr '\n' ' '))"
  fi
else
  no "V: scratch repo not built"
fi
