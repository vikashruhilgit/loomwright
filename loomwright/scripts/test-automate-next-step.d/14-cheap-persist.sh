# test-automate-next-step.d/14-cheap-persist.sh — part of test-automate-next-step.sh (TNS_PARTS / TNS_GROUPS / its
# `pg_want 14-cheap-persist` line): `/automate`'s cheap mode is the RUN's, not the call's. Outside a lane the record
# is `## Run Config`'s `- cheap: true` line (--cheap writes it, a bare call reads it, --no-cheap removes it); inside a
# lane `.supervisor/lane.json` `"cheap": true` alone decides; every Supervisor / `/autonomous` spawn and every drain
# spawn (owned drain inline and fresh, fix-now re-drain) carries `--cheap` while it is on. Sourced by the runner (its
# setup, helpers and counters); run directly — e.g. by run-pin-mutations.sh — it re-enters the runner for this part.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  exec "${BASH:-bash}" "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test-automate-next-step.sh" --part 14-cheap-persist
fi
#
# THE CASES: run-config-suppress-restore (an item running, no PR: --start run), drain-owned-drain-started (an item
# with its PR: --start drain) and dismissed-fix-now-re-drain (the fix-now hand-off), each with a `- cheap:` line
# put into ## Run Config (cp_inject) or a lane.json written, where the leg needs one.
# Honest limit: a `/automate --resume` is modelled by deleting the driver's sidecar (what every --resume does to
# it) before the next call; the resume entry's own start steps (closeout-others, the glob, AUT-RESUME) are 04's.
# LEGS (each names the acceptance criterion it pins; the brief's Pin mutations turn each red):
#   A1  --cheap writes ONE `- cheap: true` line, the last of ## Run Config; the spawn carries --cheap
#   A2  a `- cheap: true` run, the sidecar wiped, no --cheap given ⇒ the inline /autonomous spawn and the fresh
#       Supervisor phase spawn carry --cheap
#   A3  no --cheap, no line ⇒ no spawn carries --cheap, no cheap line written
#   A4  --no-cheap removes the line, ONE `cheap mode off (--no-cheap)` ## Progress line, the RUN spawn and the
#       owned drain after it carry no --cheap; the same run file, the sidecar wiped, a bare call ⇒ full cost
#   A5  a lane: lane.json without `cheap` + a command-line --cheap (the lane session's own command) ⇒ no spawn
#       carries --cheap and ## Run Config is untouched; a `- cheap: true` line there is not read either
#   A6  --cheap --no-cheap ⇒ cheap_flags_conflict, exit 2, .supervisor/ byte-unchanged (a run-file call and a
#       --resume call alike)
#   A7  `- cheap: yes` ⇒ off, exactly ONE stderr warning naming the value, stdout ONE JSON instruction
#   B1  cheap ⇒ the owned drain (inline and fresh) and the fix-now re-drain's drain_invocation end `--cheap`
#   B3  not cheap ⇒ those invocations are exactly today's `/review-pr <pr> --until-mergeable --no-auto-postmortem`
#   B5  a lane whose lane.json reads `"cheap": true` ⇒ its owned drain carries --cheap with no --cheap given
#   A1/A4 on a parking call (pick-time-token-ceiling-park): --no-cheap removes the line with ONE Progress line
#       though the call parks before any spawn, a second --no-cheap writes nothing; --cheap writes the line; a
#       call that only re-prints the pending park records its flag too
echo "-- CP. cheap mode persisted in ## Run Config, --no-cheap, lane.json authoritative in a lane, drain spawns"

CP_DRAIN_BASE="/review-pr https://github.com/vikashruhilgit/loomwright/pull/542 --until-mergeable --no-auto-postmortem"
cp_inject() { # <line> — <line> becomes the last line of the scratch run file's ## Run Config
  awk -v l="$1" '/^## / { if (c) print l; c = ($0 == "## Run Config") } { print } END { if (c) print l }' "$CASE_RF" > "$CASE_RF.t" \
    && mv "$CASE_RF.t" "$CASE_RF"
}
cp_cfg() { awk '/^## / { c = ($0 == "## Run Config"); next } c' "$CASE_RF"; }   # the scratch run file's ## Run Config lines
cp_call() { # <driver> <args…> — one --inline-phases driver call (in_case adds it; the real run-lock.sh); sets NC_OUT NC_RC NC_ERR
  local drv="$1"; shift
  NC_OUT="$(NS_REAL_LOCK=1 in_case "$drv" "$R_SEAMS" bash "$drv" "$CASE_RF" "$@" 2>"$CASE_DIR/nc.err")"; NC_RC=$?
  NC_ERR="$(cat "$CASE_DIR/nc.err")"
}
cp_inv() { printf '%s' "$NC_OUT" | jq -r '.invocation // .drain_invocation // empty' 2>/dev/null; }
cp_run_item() { sed -n 's/^- item: \([^ ]*\) .*/\1/p' "$CASE_RF" | head -n 1; }
CP_RUN_REPORT="$(sed -n "s/^call: --result '\(.*\)'\$/\1/p" "$FIX/run-config-suppress-restore/next-step.results" | head -n 1)"

# leg_cp_run <driver> — A1, A2, A3, A4, A6, A7 on the RUN spawn
leg_cp_run() {
  local drv="$1" it base s0 n lp ad
  # A1 — --cheap writes the line (once), the spawn carries --cheap
  new_scratch "$FIX/run-config-suppress-restore" || { LEG_MSG="scratch"; return 1; }
  it="$(cp_run_item)"; base="/autonomous --single-iteration --requirement $it"
  cp_call "$drv" --start run --session-id coord-1 --cheap
  [ "$NC_RC" = 0 ] && [ "$(cp_inv)" = "$base --cheap" ] || { LEG_MSG="A1 spawn ⇒ exit $NC_RC '$(cp_inv)' ${NC_ERR:0:200}"; return 1; }
  [ "$(cp_cfg | grep -c '^- cheap:')" = 1 ] && [ "$(cp_cfg | grep -v '^[[:space:]]*$' | tail -n 1)" = "- cheap: true" ] \
    || { LEG_MSG="A1 ## Run Config: $(cp_cfg | tr '\n' '|')"; return 1; }
  # A2 — the sidecar wiped (a --resume), no --cheap: read back from ## Run Config
  rm -f "$CASE_ROOT/.supervisor/automate/$CASE_RUN.next-step.json" "$CASE_ROOT/.supervisor/automate/$CASE_RUN.config-backup.json"
  rm -f "$CASE_ROOT/.supervisor/config.json"
  cp_call "$drv" --start run --session-id coord-2
  [ "$NC_RC" = 0 ] && [ "$(cp_inv)" = "$base --cheap" ] || { LEG_MSG="A2 bare resume ⇒ exit $NC_RC '$(cp_inv)' ${NC_ERR:0:200}"; return 1; }
  [ "$(cp_cfg | grep -c '^- cheap:')" = 1 ] || { LEG_MSG="A2 a second cheap line: $(cp_cfg | tr '\n' '|')"; return 1; }
  # A2 — the fresh Supervisor phase spawn (after a saved Launch Pad report) carries --cheap too
  new_scratch "$FIX/run-config-suppress-restore" || { LEG_MSG="scratch"; return 1; }
  cp_inject "- cheap: true"; f_claude 1; ad="$CASE_ROOT/.supervisor/automate"
  f_call "$drv" --start run --session-id coord-1
  [ "$NC_RC" = 0 ] && f_spawn_ok "$NC_OUT" plan launch-pad || { LEG_MSG="A2 fresh plan ⇒ exit $NC_RC '${NC_OUT:0:200}' ${NC_ERR:0:200}"; return 1; }
  mkdir -p "$CASE_ROOT/.supervisor/jobs/pending" && printf '# Brief\n' > "$CASE_ROOT/.supervisor/jobs/pending/h.md"
  lp="$(printf 'LAUNCH_PAD_RESULT:\n  schema_version: 1\n  status: saved\n  saved_brief_path: .supervisor/jobs/pending/h.md\n  summary: PASS\n')"
  printf '%s' "$lp" > "$ad/$CASE_RUN.launch-pad-result.md"
  f_call "$drv" --result "$(jq -cn --arg f "$ad/$CASE_RUN.launch-pad-result.md" '{launch_pad_result_file: $f, session_id: "lp-sess-1"}')"
  [ "$NC_RC" = 0 ] && f_spawn_ok "$NC_OUT" run supervisor && [ "$(cp_inv)" = "/loomwright:supervisor job: .supervisor/jobs/pending/h.md --cheap" ] \
    || { LEG_MSG="A2 fresh supervisor ⇒ exit $NC_RC '$(cp_inv)' ${NC_ERR:0:200}"; return 1; }
  # A3 — never cheap: no --cheap, no line
  new_scratch "$FIX/run-config-suppress-restore" || { LEG_MSG="scratch"; return 1; }
  cp_call "$drv" --start run --session-id coord-1
  [ "$NC_RC" = 0 ] && [ "$(cp_inv)" = "$base" ] && ! grep -q 'cheap' < <(cp_cfg) \
    || { LEG_MSG="A3 ⇒ exit $NC_RC '$(cp_inv)' cfg $(cp_cfg | tr '\n' '|')"; return 1; }
  # A4 — --no-cheap: the line goes, ONE Progress line, the RUN spawn and the owned drain after it are full cost
  new_scratch "$FIX/run-config-suppress-restore" || { LEG_MSG="scratch"; return 1; }
  cp_inject "- cheap: true"
  cp_call "$drv" --start run --session-id coord-1 --no-cheap
  [ "$NC_RC" = 0 ] && [ "$(cp_inv)" = "$base" ] || { LEG_MSG="A4 spawn ⇒ exit $NC_RC '$(cp_inv)' ${NC_ERR:0:200}"; return 1; }
  ! grep -q '^- cheap:' < <(cp_cfg) && [ "$(grep -cE '^- [0-9TZ:-]+ cheap mode off \(--no-cheap\)$' "$CASE_RF")" = 1 ] \
    || { LEG_MSG="A4 run file: cfg $(cp_cfg | tr '\n' '|') progress $(grep -c 'cheap mode off' "$CASE_RF")"; return 1; }
  cp_call "$drv" --session-id coord-1 --result "$CP_RUN_REPORT"
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.what == "owned drain"' >/dev/null 2>&1 \
    && [ "$(cp_inv)" = "/review-pr https://github.com/vikashruhilgit/loomwright/pull/542 --until-mergeable --no-auto-postmortem" ] \
    || { LEG_MSG="A4 later drain ⇒ exit $NC_RC '${NC_OUT:0:200}' ${NC_ERR:0:200}"; return 1; }
  [ "$(grep -c 'cheap mode off' "$CASE_RF")" = 1 ] || { LEG_MSG="A4 the Progress line repeated"; return 1; }
  # A4 — that run file in a fresh checkout, no sidecar (a following bare --resume): full cost
  cp "$CASE_RF" "$WORK/cp-a4.md"
  new_scratch "$FIX/run-config-suppress-restore" || { LEG_MSG="scratch"; return 1; }
  awk '/^## Current/ { c = 1 } c && /^- item: / { sub(/ pr: [^ ]* /, " pr: null ") } { print }' "$WORK/cp-a4.md" \
    | sed '/^## Current/,$ { /owned_drain_started/d; }' > "$CASE_RF"
  cp_call "$drv" --start run --session-id coord-3
  [ "$NC_RC" = 0 ] && [ "$(cp_inv)" = "$base" ] || { LEG_MSG="A4 bare resume after --no-cheap ⇒ exit $NC_RC '$(cp_inv)' ${NC_ERR:0:200}"; return 1; }
  # A6 — both switches: refused, nothing written (a run-file call, then a --resume call)
  new_scratch "$FIX/run-config-suppress-restore" || { LEG_MSG="scratch"; return 1; }
  cp_inject "- cheap: true"; printf '{"x":1}\n' > "$CASE_ROOT/.supervisor/automate/$CASE_RUN.next-step.json"; s0="$(snapshot)"
  cp_call "$drv" --start run --session-id coord-1 --cheap --no-cheap
  [ "$NC_RC" = 2 ] && [ -z "$NC_OUT" ] && grep -q 'cheap_flags_conflict' <<<"$NC_ERR" && [ "$(snapshot)" = "$s0" ] \
    || { LEG_MSG="A6 run file ⇒ exit $NC_RC '${NC_OUT:0:100}' ${NC_ERR:0:200}"; return 1; }
  NC_OUT="$(NS_REAL_LOCK=1 in_case "$drv" "$R_SEAMS" bash "$drv" --resume "$CASE_ROOT/.supervisor/automate" --run "$CASE_RUN" --no-cheap --session-id coord-1 --cheap 2>"$CASE_DIR/nc.err")"; NC_RC=$?
  [ "$NC_RC" = 2 ] && [ -z "$NC_OUT" ] && grep -q 'cheap_flags_conflict' "$CASE_DIR/nc.err" && [ "$(snapshot)" = "$s0" ] \
    || { LEG_MSG="A6 --resume ⇒ exit $NC_RC '${NC_OUT:0:100}' $(head -c 200 "$CASE_DIR/nc.err")"; return 1; }
  # A7 — an unrecognised value: off, one warning naming it, stdout one instruction
  new_scratch "$FIX/run-config-suppress-restore" || { LEG_MSG="scratch"; return 1; }
  cp_inject "- cheap: yes"
  cp_call "$drv" --start run --session-id coord-1
  n="$(printf '%s\n' "$NC_ERR" | grep -c "cheap_value_unrecognised: 'yes'")"
  [ "$NC_RC" = 0 ] && [ "$(cp_inv)" = "$base" ] && [ "$n" = 1 ] && [ "$(printf '%s\n' "$NC_OUT" | grep -c .)" = 1 ] \
    && printf '%s' "$NC_OUT" | jq -e '.do == "spawn"' >/dev/null 2>&1 \
    || { LEG_MSG="A7 ⇒ exit $NC_RC '$(cp_inv)' warnings $n ${NC_ERR:0:200}"; return 1; }
  return 0
}

# leg_cp_drain <driver> — B1, B3 on the owned drain (inline and fresh) and the fix-now re-drain
leg_cp_drain() {
  local drv="$1" c want
  for c in cheap plain; do
    want="$CP_DRAIN_BASE"; [ "$c" = cheap ] && want="$CP_DRAIN_BASE --cheap"
    new_scratch "$FIX/drain-owned-drain-started" || { LEG_MSG="scratch"; return 1; }
    [ "$c" = cheap ] && cp_inject "- cheap: true"
    cp_call "$drv" --start drain
    [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.what == "owned drain"' >/dev/null 2>&1 && [ "$(cp_inv)" = "$want" ] \
      || { LEG_MSG="$c inline drain ⇒ exit $NC_RC '$(cp_inv)' ${NC_ERR:0:200}"; return 1; }
    new_scratch "$FIX/drain-owned-drain-started" || { LEG_MSG="scratch"; return 1; }
    [ "$c" = cheap ] && cp_inject "- cheap: true"
    f_claude 1
    f_call "$drv" --start drain --session-id coord-1
    [ "$NC_RC" = 0 ] && f_spawn_ok "$NC_OUT" drain drain && [ "$(cp_inv)" = "$want" ] \
      && printf '%s' "$NC_OUT" | jq -e --arg p "$want — When the drain ends" '.prompt | startswith($p)' >/dev/null 2>&1 \
      || { LEG_MSG="$c fresh drain ⇒ exit $NC_RC '$(cp_inv)' prompt '$(printf '%s' "$NC_OUT" | jq -r .prompt | head -c 200)' ${NC_ERR:0:200}"; return 1; }
    new_scratch "$FIX/dismissed-fix-now-re-drain" || { LEG_MSG="scratch"; return 1; }
    [ "$c" = cheap ] && cp_inject "- cheap: true"
    grep -v '^call: --result\|^expect: none\|^env: NEXT_STEP_FROM= ' "$FIX/dismissed-fix-now-re-drain/next-step.results" > "$CASE_DIR/cp.results"
    drive "$FIX/dismissed-fix-now-re-drain" "$drv" "$CASE_DIR/cp.results"
    [ -z "$DRIVE_ERR" ] && printf '%s' "$LAST_OUT" | jq -e --arg i "${want/pull\/542/pull/555}" '.what == "fix-now re-drain" and .drain_invocation == $i' >/dev/null 2>&1 \
      || { LEG_MSG="$c fix-now ⇒ ${DRIVE_ERR:-} '$(printf '%s' "$LAST_OUT" | jq -r '.drain_invocation // .' 2>/dev/null | head -c 200)'"; return 1; }
  done
  return 0
}

# leg_cp_lane <driver> — A5 and B5: inside a lane lane.json alone decides
leg_cp_lane() {
  local drv="$1" it base cfg0
  # A5 — lane.json without cheap, the lane session's own command-line --cheap: ignored; ## Run Config untouched
  new_scratch "$FIX/run-config-suppress-restore" || { LEG_MSG="scratch"; return 1; }
  printf '{"schema_version":1,"lane":"L1"}\n' > "$CASE_ROOT/.supervisor/lane.json"
  it="$(cp_run_item)"; base="/autonomous --single-iteration --requirement $it"; cfg0="$(cp_cfg)"
  cp_call "$drv" --start run --session-id coord-1 --cheap
  [ "$NC_RC" = 0 ] && [ "$(cp_inv)" = "$base" ] && [ "$(cp_cfg)" = "$cfg0" ] \
    || { LEG_MSG="A5 lane run ⇒ exit $NC_RC '$(cp_inv)' cfg $(cp_cfg | tr '\n' '|') ${NC_ERR:0:200}"; return 1; }
  # … nor a `- cheap: true` line in the lane's own ## Run Config
  new_scratch "$FIX/drain-owned-drain-started" || { LEG_MSG="scratch"; return 1; }
  printf '{"schema_version":1,"lane":"L1"}\n' > "$CASE_ROOT/.supervisor/lane.json"; cp_inject "- cheap: true"
  cp_call "$drv" --start drain --cheap
  [ "$NC_RC" = 0 ] && [ "$(cp_inv)" = "$CP_DRAIN_BASE" ] || { LEG_MSG="A5 lane drain ⇒ exit $NC_RC '$(cp_inv)' ${NC_ERR:0:200}"; return 1; }
  # B5 — lane.json "cheap": true, no flag given: the drain carries --cheap
  new_scratch "$FIX/drain-owned-drain-started" || { LEG_MSG="scratch"; return 1; }
  printf '{"schema_version":1,"lane":"L1","cheap":true}\n' > "$CASE_ROOT/.supervisor/lane.json"; cfg0="$(cp_cfg)"
  cp_call "$drv" --start drain
  [ "$NC_RC" = 0 ] && [ "$(cp_inv)" = "$CP_DRAIN_BASE --cheap" ] && [ "$(cp_cfg)" = "$cfg0" ] \
    || { LEG_MSG="B5 lane drain ⇒ exit $NC_RC '$(cp_inv)' ${NC_ERR:0:200}"; return 1; }
  return 0
}

# leg_cp_park <driver> — the flag is written by the call that receives it, a parking call and a re-print included
leg_cp_park() {
  local drv="$1" c="$FIX/pick-time-token-ceiling-park" call="call: --start pick --session-id auto-2026-10-15-040641"
  cp_park_drive() { # <call line> <expect line> — one driven call on the scratch case
    printf '%s\n%s\n' "$1" "$2" > "$CASE_DIR/cp.results"; drive "$c" "$drv" "$CASE_DIR/cp.results"
  }
  cp_off_lines() { grep -cE '^- [0-9TZ:-]+ cheap mode off \(--no-cheap\)$' "$CASE_RF"; }
  # --no-cheap on a call that parks token_ceiling before any spawn: the line goes, ONE Progress line
  new_scratch "$c" || { LEG_MSG="scratch"; return 1; }
  cp_inject "- cheap: true"
  cp_park_drive "$call --no-cheap" "expect: park"
  [ -z "$DRIVE_ERR" ] && printf '%s' "$LAST_OUT" | jq -e '.do == "park" and .pause_reason == "token_ceiling"' >/dev/null 2>&1 \
    || { LEG_MSG="park --no-cheap ⇒ ${DRIVE_ERR:-} '${LAST_OUT:0:200}'"; return 1; }
  ! grep -q '^- cheap:' < <(cp_cfg) && [ "$(cp_off_lines)" = 1 ] \
    || { LEG_MSG="park --no-cheap run file: cfg $(cp_cfg | tr '\n' '|') progress $(cp_off_lines)"; return 1; }
  # a second --no-cheap (the line already gone): nothing more written
  cp_park_drive "$call --no-cheap" "expect: park"
  [ -z "$DRIVE_ERR" ] && [ "$(cp_off_lines)" = 1 ] || { LEG_MSG="second --no-cheap ⇒ ${DRIVE_ERR:-} progress $(cp_off_lines)"; return 1; }
  # --cheap on a parking call writes the line
  new_scratch "$c" || { LEG_MSG="scratch"; return 1; }
  cp_park_drive "$call --cheap" "expect: park"
  [ -z "$DRIVE_ERR" ] && [ "$(cp_cfg | grep -c '^- cheap: true$')" = 1 ] \
    || { LEG_MSG="park --cheap ⇒ ${DRIVE_ERR:-} cfg $(cp_cfg | tr '\n' '|')"; return 1; }
  # a call that only re-prints the pending park records --no-cheap too, and the same park re-prints
  cp_park_drive "call: --no-cheap" "expect: park"
  [ -z "$DRIVE_ERR" ] && printf '%s' "$LAST_OUT" | jq -e '.pause_reason == "token_ceiling"' >/dev/null 2>&1 \
    && ! grep -q '^- cheap:' < <(cp_cfg) && [ "$(cp_off_lines)" = 1 ] \
    || { LEG_MSG="re-print --no-cheap ⇒ ${DRIVE_ERR:-} '${LAST_OUT:0:120}' cfg $(cp_cfg | tr '\n' '|') progress $(cp_off_lines)"; return 1; }
  return 0
}

LEG_MSG=""
if leg_cp_run "$DRIVER"; then ok "CP-A (A1–A4, A6, A7): --cheap writes ONE '- cheap: true' line in ## Run Config and a bare call after a sidecar wipe still puts --cheap on the inline /autonomous and the fresh Supervisor spawn; no --cheap ⇒ none and no line; --no-cheap removes the line with ONE 'cheap mode off (--no-cheap)' Progress line and the RUN spawn, the drain after it and a later bare call are full cost; --cheap --no-cheap ⇒ cheap_flags_conflict exit 2, nothing written; '- cheap: yes' ⇒ off + ONE warning"
else no "CP-A: $LEG_MSG"; fi
LEG_MSG=""
if leg_cp_drain "$DRIVER"; then ok "CP-B (B1, B3): cheap ⇒ the inline and fresh owned drain and the fix-now re-drain's drain_invocation end --cheap; not cheap ⇒ exactly '/review-pr <pr> --until-mergeable --no-auto-postmortem'"
else no "CP-B: $LEG_MSG"; fi
LEG_MSG=""
if leg_cp_lane "$DRIVER"; then ok "CP-L (A5, B5): in a lane a command-line --cheap and a '- cheap: true' Run Config line are ignored when lane.json has no cheap key (Run Config untouched); lane.json \"cheap\": true ⇒ the owned drain carries --cheap"
else no "CP-L: $LEG_MSG"; fi
LEG_MSG=""
if leg_cp_park "$DRIVER"; then ok "CP-P (A1, A4 on a parking call): --start pick --no-cheap that parks token_ceiling removes '- cheap: true' with ONE 'cheap mode off (--no-cheap)' Progress line and a second --no-cheap writes nothing; --cheap on a parking call writes the line; a re-print call records --no-cheap too"
else no "CP-P: $LEG_MSG"; fi
