# ---- AJ: lane timeline (the step rail the /lanes pane draws) ----------------------------------------------
# _lanes_timeline over fixture run files / Supervisor state: 7 steps from `## Progress` lines, the
# Supervisor phase only when its state was created at/after the pick, the current step colored by state.
AJ="$T/aj"; mkdir -p "$AJ/lane/.supervisor"; AJRF="$AJ/run.md"; AJSM="$AJ/lane/.supervisor/state.md"
ajt() { ( . "$S"; _lanes_timeline "$AJRF" "$AJ/lane/.supervisor" "${3:-$(jq -n '"2026-10-11T10:00:00Z" | fromdateiso8601')}" "$1" "${2:--}" ); }
ajp() { printf '# Automate Run: x\n\n## Current\n- item: a.md | status: running\n\n## Progress\n' > "$AJRF"; printf '%s\n' "$@" >> "$AJRF"; }
ajp '- 2026-10-11T03:19:01Z run started (lane L1 of p)' '- trail-gate: clear — an undated line is skipped' \
  '- 2026-10-11T03:19:14Z picked a.md' '- 2026-10-11T03:55:09Z launch-pad: Plan Review attempt 1/3 FAIL' \
  '- 2026-10-11T04:13:15Z launch-pad: brief saved .supervisor/jobs/pending/x.md' \
  '- 2026-10-11T06:11:10Z ran /autonomous → PR https://x/pull/1 (FINALIZE; Phase 4.5 next)' \
  '- 2026-10-11T06:32:20Z /autonomous done: SUPERVISOR_RESULT completed, heal PASS' \
  '- 2026-10-11T06:32:42Z owned drain started — /review-pr https://x/pull/1' \
  '- 2026-10-11T06:36:53Z drain round 1: 1 validated bot finding fixed' '- 2026-10-11T06:48:15Z drain round 2: fixed' \
  '- 2026-10-11T07:05:55Z drain READY → converged' '- 2026-10-11T07:10:18Z dismissed: drop d1.md' \
  '- 2026-10-11T07:24:02Z parked ready_for_release — PR https://x/pull/1 READY' '- 2026-10-11T09:40:56Z auto-finalized: queue empty after closeout'
out="$(ajt merged)"
check "AJ1 merged ⇒ every step done, label Done, no current" \
  "$(jq -r '"\([.steps[].state] | unique | join(","))|\(.label)|\(.current)|\(.steps | length)"' <<<"$out")" "done|Done|null|7"
check "AJ2 boundaries: picked starts Plan, brief saved starts Build, durations from the lines" \
  "$(jq -r '[.steps[] | "\(.id)=\(.started_at | .[11:19])/\(.duration_s)"] | join(" ")' <<<"$out")" \
  "pick=03:19:01/13 plan=03:19:14/3241 build=04:13:15/8345 heal=06:32:20/22 drain=06:32:42/2256 decide=07:10:18/824 merge=07:24:02/8214"
check "AJ3 the run starts at its first dated line; a step keeps its last 4 lines" \
  "$(jq -r '"\(.started_at)|\(.steps[4].lines | length)|\(.steps[4].lines[0] | .[0:13])"' <<<"$out")" "2026-10-11T03:19:01Z|4|owned drain s"
out="$(ajt ready_for_release)"
check "AJ4 parked ⇒ Merge is current and waiting on the owner" "$(jq -r '"\(.current)|\(.steps[6].state)|\(.steps[5].state)"' <<<"$out")" "merge|waiting|done"
# AJ4b: a park BEFORE the drain is no Merge evidence (run automate-2026-10-15-163325 L5, 2026-10-16: Launch
# Pad blocked, the lane read "Merge · escalated, step 7 of 7" with Pick..Decide green). It stays on Plan.
ajp '- 2026-10-11T08:00:00Z run created (lane L5 of p)' '- 2026-10-11T08:01:00Z picked a.md' \
  '- 2026-10-11T08:20:00Z ran /autonomous --single-iteration — no PR: Launch Pad blocked (Plan Review FAIL 3/3; owner chose Refine offline)' \
  '- 2026-10-11T08:20:05Z parked escalated (no PR) — Launch Pad blocked; revised brief draft kept'
out="$(ajt escalated)"
AJ4B_GOT='"\(.current)|\(.label)|\(.steps[0].state)|\(.steps[1].state)|\([.steps[2:][].state] | unique | join(","))|\(.steps[1].lines[-1] | .[0:16])"'
check "AJ4b a park before the drain stays on the step reached: Plan trouble, Build..Merge pending" \
  "$(jq -r "$AJ4B_GOT" <<<"$out")" "plan|Plan|done|trouble|pending|parked escalated"
sed 's/if test("^parked ") then \["park"\]/if test("^parked ") then ["merge"]/' "$SB" > "$MUT/lanes-aj4b.sh"
if ! cmp -s "$SB" "$MUT/lanes-aj4b.sh" && bash -n "$MUT/lanes-aj4b.sh"; then
  out="$( ( . "$MUT/lanes-aj4b.sh"; _lanes_timeline "$AJRF" "$AJ/lane/.supervisor" "$(jq -n '"2026-10-11T10:00:00Z" | fromdateiso8601')" escalated - ) )"
  check "AJ4c mutation (every park is Merge again) trips AJ4b: Merge current, Pick..Decide done" \
    "$(jq -r "$AJ4B_GOT" <<<"$out")" "merge|Merge|done|done|done,trouble|ran /autonomous "
else bad "AJ4c mutation did not apply (the park classification moved)"; fi
rm -f "$MUT/lanes-aj4b.sh"
# AJ4d: the no-PR RUN line's wording is not pinned — other Launch Pad phrasings reach Plan too; one that names
# the Supervisor (it started) or carries a PR URL still reaches Build.
aj4d() { ajp '- 2026-10-11T08:01:00Z picked a.md' "- 2026-10-11T08:20:00Z ran /autonomous $1" '- 2026-10-11T08:20:05Z parked escalated (no PR)'; ajt escalated | jq -r .current; }
check "AJ4d unpinned Launch Pad wordings reach Plan; Supervisor / a PR URL reach Build" \
  "$(aj4d '— blocked: Launch Pad NO-GO (no PR)'),$(aj4d '(aborted, status_reason launch_pad_blocked)'),$(aj4d '— no PR: Supervisor failed after Launch Pad'),$(aj4d '→ PR https://x/pull/9 (Launch Pad brief reused)')" \
  "plan,plan,build,build"
# AJ4e: the PINNED no-PR line (per-item-loop.md step 2) — its status_reason token decides Plan vs Build. The
# Plan-stage set is written out HERE (never read back from the code), and every other value of the closed
# AUTONOMOUS_RUN enum must read Build, so a new enum value has to be placed on purpose + mutation control.
AJ4E_PLAN="launch_pad_blocked user_aborted_at_launch_pad launch_pad_cant_ask_non_interactive user_discarded_at_phase_6
  user_aborted_at_no_go user_aborted_at_plan_review_fail rubric_dropped_from_brief concurrent_session_detected
  non_interactive_without_fallback invalid_max_iterations conflicting_mode_flags run_lock_held"
AJ4E_ENUM="$(grep -m1 '^- \*\*status_reason:\*\*' "$HERE/../skills/autonomous-loop/SKILL.md" | grep -o '"[a-z0-9_]*"' | tr -d '"')"
AJ4E_BUILD=""; for x in $AJ4E_ENUM; do case " $(echo $AJ4E_PLAN) " in *" $x "*) ;; *) AJ4E_BUILD="$AJ4E_BUILD $x" ;; esac; done
AJ4E_MISS=""; for x in $AJ4E_PLAN; do case " $(echo $AJ4E_ENUM) " in *" $x "*) ;; *) AJ4E_MISS="$AJ4E_MISS $x" ;; esac; done
aj4e() { local r=""; for x in "$@"; do r="$r$(aj4d "— no PR: $x (why)"),"; done; printf '%s' "${r%,}"; }
check "AJ4e every Plan-stage token is in the AUTONOMOUS_RUN enum, and the enum's other values number 13" \
  "${AJ4E_MISS:-none}|$(echo $AJ4E_BUILD | wc -w | tr -d ' ')" "none|13"
check "AJ4e2 every Plan-stage status_reason reaches Plan" "$(aj4e $AJ4E_PLAN | tr ',' '\n' | sort -u)" plan
check "AJ4e3 every other enum value reaches Build" "$(aj4e $AJ4E_BUILD | tr ',' '\n' | sort -u)" build
check "AJ4e4 a wrapped token still reads; unknown / free text fall back to the Launch Pad match" \
  "$(aj4d '— no PR: `user_aborted_at_no_go` (why)'),$(aj4d '— no PR: "supervisor_checkpoint" (why)'),$(aj4d '— no PR: (user_aborted_at_plan_review_fail) (why)'),$(aj4d '— no PR: unknown (Launch Pad blocked)'),$(aj4d '— no PR: unknown (no reason given)'),$(aj4d '— no PR: blocked by Launch Pad')" \
  "plan,build,plan,plan,build,plan"
has "AJ4e5 per-item-loop.md step 2 pins the no-PR line" "$(cat "$HERE/../skills/automate-loop/per-item-loop.md")" \
  '`<ts> ran /autonomous — no PR: <status_reason> (<one-line why>)`'
sed 's/"concurrent_session_detected", //' "$SB" > "$MUT/lanes-aj4e.sh"
if ! cmp -s "$SB" "$MUT/lanes-aj4e.sh" && bash -n "$MUT/lanes-aj4e.sh"; then
  out="$(ajp '- 2026-10-11T08:01:00Z picked a.md' '- 2026-10-11T08:20:00Z ran /autonomous — no PR: concurrent_session_detected (two briefs)' '- 2026-10-11T08:20:05Z parked escalated (no PR)'
         ( . "$MUT/lanes-aj4e.sh"; _lanes_timeline "$AJRF" "$AJ/lane/.supervisor" "$(jq -n '"2026-10-11T10:00:00Z" | fromdateiso8601')" escalated - ) | jq -r .current)"
  check "AJ4f mutation (a Plan-stage token dropped from planstop) reads Build — the case AJ4e2 catches" "$out" build
else bad "AJ4f mutation did not apply (planstop moved)"; fi
rm -f "$MUT/lanes-aj4e.sh"
# AJ2b: the driver's PINNED plan-end line `launch-pad saved <brief>` (per-item-loop.md step 2) starts Build. Run
# automate-2026-10-15-163325 L21–L25 (2026-10-21): the timeline matched only "brief saved", so every fresh-phase
# lane's Build read "no time recorded". progress-line-match.sh is the one matcher it shares with read-token-ledger.sh.
ajt0() { ( unset LOOMWRIGHT_LANES_PROGRESS_MATCH; . "$S"; _lanes_timeline "$AJRF" "$AJ/lane/.supervisor" "$(jq -n '"2026-10-11T10:00:00Z" | fromdateiso8601')" "$1" - ); }
aj2b() { ajp '- 2026-10-11T08:00:00Z run started' '- 2026-10-11T08:01:00Z picked a.md' "- 2026-10-11T08:20:00Z $1" \
    '- 2026-10-11T08:20:01Z auto_review suppressed (backup x.config-backup.json) — running the supervisor phase (fresh session)'
  "${2:-ajt}" running | jq -r '"\(.current)@\(.steps[2].started_at | .[11:19] // "null")"'; }
check "AJ2b every real plan-end spelling starts Build at its own time; other Launch Pad lines stay on Plan" \
  "$(aj2b 'launch-pad saved .supervisor/jobs/pending/x.md'),$(aj2b 'launch-pad: brief saved .supervisor/jobs/pending/x.md'),$(aj2b 'launch pad: brief saved x.md'),$(aj2b 'Launch Pad saved brief x.md'),$(aj2b 'launch-pad: Plan Review attempt 1/3 FAIL'),$(aj2b 'launch pad: Plan Review PASS 3/3; no brief saved yet')" \
  "build@08:20:00,build@08:20:00,build@08:20:00,build@08:20:00,plan@null,plan@null"
check "AJ2b2 the default matcher path (no override) resolves beside the entry point" "$(aj2b 'launch-pad saved x.md' ajt0)" "build@08:20:00"
check "AJ2b3 an unreadable matcher fails SAFE: the timeline still reads, the line is no Build start" \
  "$(LOOMWRIGHT_LANES_PROGRESS_MATCH="$T/no-such-matcher.sh" aj2b 'launch-pad saved x.md')" "plan@null"
sed 's/elif plan_end then \["plan", "build"\] elif/elif test("launch[ -]?pad"; "i") and test("brief saved"; "i") then ["plan", "build"] elif/' "$SB" > "$MUT/lanes-aj2b.sh"
if ! cmp -s "$SB" "$MUT/lanes-aj2b.sh" && bash -n "$MUT/lanes-aj2b.sh"; then
  aj2bm() { ( . "$MUT/lanes-aj2b.sh"; _lanes_timeline "$AJRF" "$AJ/lane/.supervisor" "$(jq -n '"2026-10-11T10:00:00Z" | fromdateiso8601')" "$1" - ); }
  check "AJ2b4 mutation (the old \"brief saved\" rule back) loses the pinned line's Build start — the case AJ2b catches" \
    "$(aj2b 'launch-pad saved x.md' aj2bm)" "plan@null"
else bad "AJ2b4 mutation did not apply (the plan-end classification moved)"; fi
rm -f "$MUT/lanes-aj2b.sh"
ajp '- 2026-10-11T08:00:00Z run started' '- 2026-10-11T08:01:00Z picked a.md' \
  '- 2026-10-11T08:30:00Z ran /autonomous → PR https://x/pull/2 (SUPERVISOR_RESULT completed; heal PASS iter 1)' \
  '- 2026-10-11T08:31:00Z owned drain started' '- 2026-10-11T08:40:00Z drain round 3: fixed'
out="$(ajt running)"
check "AJ5 drain round in the label; heal reached by the ran-/autonomous heal verdict; current duration runs to now" \
  "$(jq -r '"\(.label)|\(.steps[3].state)|\(.steps[4].state)|\(.steps[4].duration_s)"' <<<"$out")" "Drain · round 3|done|active|5340"
ajp '- 2026-10-11T08:00:00Z run started' '- 2026-10-11T08:01:00Z picked a.md'
printf '# State Log\n\n## Session\n- status: running\n- phase: EXECUTE\n\n## Decisions Log\n- phase: INIT, decision: guard_armed: ok, timestamp: 2026-10-11T08:02:00Z\n- phase: PRE_FLIGHT_SYNC, decision: preflight_clear, rationale: r, timestamp: 2026-10-11T08:03:00Z\n\n## Checkpoint\n- created: 2026-10-11T08:02:00Z\n- last_updated: 2026-10-11T08:03:00Z\n' > "$AJSM"
out="$(ajt running)"
check "AJ6 Supervisor state after the pick ⇒ Build current with its phase; Plan ends at the Supervisor start" \
  "$(jq -r '"\(.label)|\(.steps[1].duration_s)|\(.steps[2].started_at)|\(.phases | map(.phase) | join(","))"' <<<"$out")" \
  "Build · EXECUTE|60|2026-10-11T08:02:00Z|INIT,PRE_FLIGHT_SYNC"
sed -i.bak 's/created: 2026-10-11T08:02:00Z/created: 2026-10-11T07:00:00Z/; s/08:02:00Z\(.*\)INIT/07:00:00Z\1INIT/' "$AJSM"; sed -i.bak 's/timestamp: 2026-10-11T08:0[23]:00Z/timestamp: 2026-10-11T07:00:00Z/' "$AJSM"
out="$(ajt running)"
check "AJ7 a Supervisor state created BEFORE the pick (the previous item's) never shows" "$(jq -r '"\(.current)|\(.phase)|\(.phases | length)"' <<<"$out")" "plan|null|0"
printf '# State Log\n\n## Session\n- status: running\n- phase: FINALIZE\n' > "$AJSM"
check "AJ8 an undated running Supervisor state still names the phase (no time invented)" \
  "$(ajt running | jq -r '"\(.label)|\(.steps[2].started_at)"')" "Build · FINALIZE|null"
check "AJ8b … but only while the lane runs" "$(ajt stalled | jq -r '"\(.current)|\(.steps[1].state)"')" "plan|trouble"
check "AJ8c a lane removed unfinished stops (held), it did not fail; abandoned still reads trouble" \
  "$(ajt removed | jq -r '.steps[1].state')|$(ajt abandoned | jq -r '.steps[1].state')" "held|trouble"
# AJ8d–AJ8m: the real Supervisor phase (run automate-2026-10-15-163325, 2026-10-16: L8 and L9 sat in Phase 4.5
# with PRs #577 / #575 open while the timeline read "Build · EXECUTE" for hours). build-state.sh projects
# `phase:` from subtask_complete / session_end only, so it reads EXECUTE through FINALIZE and Phase 4.5, and the
# canonical Decisions Log is a TABLE with no timestamp (the `- phase: … timestamp:` bullets above are the only
# shape the timeline read). Fixtures below are the canonical shapes, copied from those lanes' state.md:
# `- last_checkpoint:` (no `created:`), so only the undated-live branch trusts the state.
AJSID=sess-aj8; AJLOG="$AJ/lane/.supervisor/logs/$AJSID.jsonl"; mkdir -p "$AJ/lane/.supervisor/logs"
aj_state() { # <table rows (| n | PHASE | decision | why |) …> — a canonical state.md, phase EXECUTE, status running
  { printf '# State Log\n\n## Session\n- session_id: %s\n- branch: feature/x\n- status: running\n- phase: EXECUTE\n\n## Decisions Log\n| # | Phase | Decision | Rationale |\n|---|-------|----------|-----------|\n' "$AJSID"
    printf '%s\n' "$@"; printf '\n## Checkpoint\n- last_checkpoint: 2026-10-11 (time not captured)\n- current_phase: INIT\n'; } > "$AJSM"; }
aj_log() { # <pr_created ts|-> — the session log: two subtask_complete + (optionally) the hook's pr_created
  { printf '{"event":"subtask_complete","ts":"2026-10-11T08:40:00Z","session_id":"%s"}\n' "$AJSID"
    printf '{"event":"agent_lifecycle","state":"working","ts":"2026-10-11T08:41:00Z"}\nnot json\n'
    [ "$1" = - ] || printf '{"event":"pr_created","ts":"%s","url":"https://x/pull/7","session_id":"%s"}\n' "$1" "$AJSID"; } > "$AJLOG"; }
ajp '- 2026-10-11T08:00:00Z run started' '- 2026-10-11T08:01:00Z picked a.md' '- 2026-10-11T08:20:00Z launch-pad: brief saved .supervisor/jobs/pending/x.md'
AJ8_GOT='"\(.current)|\(.label)|\(.steps[2].state)|\(.steps[2].ended_at)|\(.steps[3].state)|\(.steps[3].started_at)|\(.phase)"'
aj_state '| 1 | INIT | guard_armed: ok | none |' '| 2 | EXECUTE | subtasks merged | r |' \
  '| 3 | SELF_HEAL | brief_conformance: non-empty | 9 ACs |' '| 4 | SELF_HEAL | fix iteration 1 | review FAIL, fixed |'
aj_log 2026-10-11T09:00:00Z
check "AJ8d L9's shape (phase EXECUTE, SELF_HEAL table rows, PR opened) ⇒ Heal current from the PR's time, Build done; phase stays the recorded one" \
  "$(ajt running | jq -r "$AJ8_GOT")" "heal|Heal|done|2026-10-11T09:00:00Z|active|2026-10-11T09:00:00Z|EXECUTE"
has "AJ8d2 … Heal lists the PR line and the SELF_HEAL decisions" "$(ajt running | jq -r '.steps[3].lines | join(" / ")')" \
  "Supervisor opened the PR https://x/pull/7 — Phase 4.5 / Supervisor SELF_HEAL: brief_conformance: non-empty / Supervisor SELF_HEAL: fix iteration 1"
aj_state '| 1 | INIT | guard_armed: ok | none |' '| 2 | EXECUTE | subtask3 requeued | r |'
check "AJ8e L8's shape (no SELF_HEAL row yet, PR opened) ⇒ Heal by the PR alone" "$(ajt running | jq -r "$AJ8_GOT")" \
  "heal|Heal|done|2026-10-11T09:00:00Z|active|2026-10-11T09:00:00Z|EXECUTE"
aj_state '| 1 | INIT | guard_armed: ok | none |' '| 2 | SELF_HEAL | fix iteration 1 | r |'; aj_log -
check "AJ8f SELF_HEAL table rows alone (no PR event) ⇒ Heal reached, no time invented" \
  "$(ajt running | jq -r '"\(.current)|\(.steps[3].started_at)|\(.steps[2].state)"')" "heal|null|done"
check "AJ8g … table rows are trusted like phase: not once the lane stopped (Build from the saved brief, never Heal)" "$(ajt stalled | jq -r .current)" build
aj_state '| 1 | INIT | guard_armed: ok | none |' '| 2 | EXECUTE | r | r |'; aj_log 2026-10-11T07:30:00Z
check "AJ8h a pr_created before the pick (the previous item's session) never counts" "$(ajt running | jq -r '"\(.current)|\(.label)"')" "build|Build · EXECUTE"
aj_log 2026-10-11T09:00:00Z
check "AJ8i a dated PR event stands without the live predicate: a stalled lane past its PR is in trouble at Heal" \
  "$(ajt stalled | jq -r '"\(.current)|\(.steps[3].state)"')" "heal|trouble"
# AJ8j: the only dated Build line is retrospective (`ran /autonomous → PR`, written once /autonomous returned,
# after the PR that started Heal) ⇒ Build has no known start, never one later than its end.
ajp '- 2026-10-11T08:00:00Z run started' '- 2026-10-11T08:01:00Z picked a.md' \
  '- 2026-10-11T09:30:00Z ran /autonomous → PR https://x/pull/7 (SUPERVISOR_RESULT completed; heal PASS iter 1)' '- 2026-10-11T09:31:00Z owned drain started'
AJ8J_GOT='"\(.steps[2].started_at)|\(.steps[2].ended_at)|\(.steps[3].started_at)|\(.steps[3].ended_at)"'
check "AJ8j a retrospective Build line after the PR ⇒ Build started_at null, ended at the PR; Heal from the PR to the drain" \
  "$(ajt running | jq -r "$AJ8J_GOT")" "null|2026-10-11T09:00:00Z|2026-10-11T09:00:00Z|2026-10-11T09:31:00Z"
# Mutation controls: each evidence source removed turns its leg red.
ajp '- 2026-10-11T08:00:00Z run started' '- 2026-10-11T08:01:00Z picked a.md' '- 2026-10-11T08:20:00Z launch-pad: brief saved .supervisor/jobs/pending/x.md'
aj_state '| 1 | INIT | guard_armed: ok | none |' '| 2 | EXECUTE | subtask3 requeued | r |'; aj_log 2026-10-11T09:00:00Z
ajm() { ( . "$1"; _lanes_timeline "$AJRF" "$AJ/lane/.supervisor" "$(jq -n '"2026-10-11T10:00:00Z" | fromdateiso8601')" "${2:-running}" - ); }
sed 's/select(.event? == "pr_created")/select(.event? == "pr_created_off")/' "$SB" > "$MUT/lanes-aj8.sh"
if ! cmp -s "$SB" "$MUT/lanes-aj8.sh" && bash -n "$MUT/lanes-aj8.sh"; then
  check "AJ8k mutation (pr_created not read) turns AJ8e red: L8 reads Build · EXECUTE again" "$(ajm "$MUT/lanes-aj8.sh" | jq -r '"\(.current)|\(.label)"')" "build|Build · EXECUTE"
else bad "AJ8k mutation did not apply (the pr_created reader moved)"; fi
aj_state '| 1 | INIT | guard_armed: ok | none |' '| 2 | SELF_HEAL | fix iteration 1 | r |'; aj_log -
sed 's/printf "T\\t%s\\t%s\\n", ph, d }/}/' "$SB" > "$MUT/lanes-aj8.sh"
if ! cmp -s "$SB" "$MUT/lanes-aj8.sh" && bash -n "$MUT/lanes-aj8.sh"; then
  check "AJ8l mutation (table rows not read) turns AJ8f red: Build · EXECUTE" "$(ajm "$MUT/lanes-aj8.sh" | jq -r '"\(.current)|\(.label)"')" "build|Build · EXECUTE"
else bad "AJ8l mutation did not apply (the table-row reader moved)"; fi
ajp '- 2026-10-11T08:00:00Z run started' '- 2026-10-11T08:01:00Z picked a.md' \
  '- 2026-10-11T09:30:00Z ran /autonomous → PR https://x/pull/7 (SUPERVISOR_RESULT completed; heal PASS iter 1)' '- 2026-10-11T09:31:00Z owned drain started'
aj_state '| 1 | INIT | guard_armed: ok | none |'; aj_log 2026-10-11T09:00:00Z
sed 's/(if \$b0 != null and \$end != null and \$b0 > \$end then null else \$b0 end) as \$b/$b0 as $b/' "$SB" > "$MUT/lanes-aj8.sh"
if ! cmp -s "$SB" "$MUT/lanes-aj8.sh" && bash -n "$MUT/lanes-aj8.sh"; then
  check "AJ8m mutation (no retrospective-start guard) turns AJ8j red: Build starts after it ended" \
    "$(ajm "$MUT/lanes-aj8.sh" | jq -r "$AJ8J_GOT")" "2026-10-11T09:30:00Z|2026-10-11T09:00:00Z|2026-10-11T09:00:00Z|2026-10-11T09:31:00Z"
else bad "AJ8m mutation did not apply (the start guard moved)"; fi
rm -f "$MUT/lanes-aj8.sh"
# AJ8n–AJ8q: whose state it is. Real state files carry no `## Checkpoint created:` (1 of 23 lanes across 8 runs;
# the rest an agent-filled `last_checkpoint:` — a bare date, "(time not captured)", a fake midnight), so only
# the live branch trusted them and a stopped lane lost its Supervisor phase. A state whose `session_id` is the
# lane's own session (the 6th argument, the lane table's) is this item's: trusted like a running one, no time.
ajp '- 2026-10-11T08:00:00Z run started' '- 2026-10-11T08:01:00Z picked a.md'
aj_state '| 1 | INIT | guard_armed: ok | none |' '| 2 | EXECUTE | subtask 1 merged | r |'; aj_log -
ajo() { ( . "${3:-$S}"; _lanes_timeline "$AJRF" "$AJ/lane/.supervisor" "$(jq -n '"2026-10-11T10:00:00Z" | fromdateiso8601')" "$1" - "$2" ); }
AJ8N_GOT='"\(.current)|\(.label)|\(.steps[2].state)|\(.phase)|\(.phase_status)|\(.steps[2].started_at)"'
check "AJ8n a stopped lane whose state is its own session's keeps its phase: Build · EXECUTE in trouble, no time invented" \
  "$(ajo stalled "$AJSID" | jq -r "$AJ8N_GOT")" "build|Build · EXECUTE|trouble|EXECUTE|running|null"
check "AJ8o … another session's state (a previous item's, a hand copy) is still never shown" \
  "$(ajo stalled sess-other | jq -r '"\(.current)|\(.phase)"'),$(ajo stalled "" | jq -r '"\(.current)|\(.phase)"'),$(ajo stalled - | jq -r '"\(.current)|\(.phase)"')" \
  "plan|null,plan|null,plan|null"
aj_state '| 1 | INIT | guard_armed: ok | none |' '| 2 | SELF_HEAL | fix iteration 1 | r |'
check "AJ8p … its SELF_HEAL table rows reach Heal on a stopped lane (AJ8g's case, now with identity)" \
  "$(ajo died "$AJSID" | jq -r '"\(.current)|\(.steps[3].state)|\(.steps[3].lines[0])"')" "heal|trouble|Supervisor SELF_HEAL: fix iteration 1"
aj_state '| 1 | INIT | guard_armed: ok | none |' '| 2 | EXECUTE | subtask 1 merged | r |'
sed 's/(\$lsid != "" and (\$s.session_id \/\/ "") == \$lsid) as \$own/false as $own/' "$SB" > "$MUT/lanes-aj8n.sh"
if ! cmp -s "$SB" "$MUT/lanes-aj8n.sh" && bash -n "$MUT/lanes-aj8n.sh"; then
  check "AJ8q mutation (identity never trusted) turns AJ8n red: the stopped lane falls back to Plan, no phase" \
    "$(ajo stalled "$AJSID" "$MUT/lanes-aj8n.sh" | jq -r '"\(.current)|\(.phase)"')" "plan|null"
else bad "AJ8q mutation did not apply (the identity predicate moved)"; fi
rm -f "$MUT/lanes-aj8n.sh"
rm -f "$AJLOG"
ajp '- 2026-10-11T08:00:00Z run started' '- 2026-10-11T08:01:00Z picked a.md'   # AJ9 reads the AJ6 run file
rm -f "$AJSM"
check "AJ9 a question ⇒ the current step waits on the owner" "$(ajt awaiting_input | jq -r '.steps[1].state')" waiting
rm -f "$AJRF"
check "AJ10 no run file ⇒ Pick current, held, started from last_launch_utc" \
  "$(ajt created 2026-10-11T07:59:00Z | jq -r '"\(.current)|\(.steps[0].state)|\(.started_at)|\([.steps[1:][].state] | unique | join(","))"')" \
  "pick|held|2026-10-11T07:59:00Z|pending"
J="$(sj)"
check "AJ11 lane-status --json carries timeline, started_at and run_started_at" \
  "$(jq -r '"\(has("run_started_at"))|\(.lanes | map(.timeline | type) | unique | join(","))|\(.lanes | map(has("started_at")) | all)"' <<<"$J")" "true|object|true"
# AJ11b–AJ11c: lane-status hands _lanes_timeline the lane table's session id — a stopped lane of the fixture
# fleet with its own session's state keeps its phase through the real reader; another session's does not.
AJL="$(jq -r '[.lanes[] | select(.state != "running" and .state != "removed" and .state != "abandoned")][0].lane // empty' <<<"$J")"
AJLP="$(awk -F'\t' -v l="$AJL" '$1 == l { p = $2 } END { print p }' "$TABLE2")"; AJLS="$(awk -F'\t' -v l="$AJL" '$1 == l { s = $7 } END { print s }' "$TABLE2")"
if [ -n "$AJL" ] && [ -d "$AJLP/.supervisor" ] && [ -n "$AJLS" ] && [ "$AJLS" != - ]; then
  printf '# State Log\n\n## Session\n- session_id: %s\n- status: running\n- phase: EXECUTE\n\n## Checkpoint\n- last_checkpoint: 2026-10-11 (time not captured)\n' "$AJLS" > "$AJLP/.supervisor/state.md"
  check "AJ11b lane-status passes the lane's session id: stopped $AJL with its own state reads phase EXECUTE" \
    "$(sj | jq -r --arg l "$AJL" '.lanes[] | select(.lane == $l) | .timeline.phase')" EXECUTE
  sed -i.bak "s/^- session_id: .*/- session_id: sess-not-$AJL/" "$AJLP/.supervisor/state.md"
  check "AJ11c … and another session's state is not shown" "$(sj | jq -r --arg l "$AJL" '.lanes[] | select(.lane == $l) | .timeline.phase')" null
  rm -f "$AJLP/.supervisor/state.md" "$AJLP/.supervisor/state.md.bak"
else bad "AJ11b no stopped fixture lane with a session id to test (lane=[$AJL] sid=[$AJLS])"; fi
has "AJ12 the --verbose plain view draws the steps line" "$(run lane-status "$RF2" --verbose)" "    steps: [Pick"
check "AJ13 no wave built yet ⇒ waves is an empty list" "$(jq -c '.waves' <<<"$J")" "[]"
cp "$RF2" "$RF2.aj13"
printf '%s\n' '- wave built: wave/w3 — PR https://github.com/o/r/pull/474 (lanes: L1 PR #470; ci pass)' \
  '- 2026-10-13T00:15:43Z wave built (by hand; owner: push it): wave/p-w4 — PR https://github.com/o/r/pull/506 (lanes: L1 PR #502)' \
  '- 2026-10-13T00:20:00Z wave PR #506 ci re-run PASS' >> "$RF2"
check "AJ14 waves: every wave-build record, oldest first — an undated hand line and a parenthesised colon included" \
  "$(sj | jq -r '[.waves[] | "\(.wave)|\(.branch)|\(.pr)|\(.built_at)"] | join(" ")')" \
  "3|wave/w3|https://github.com/o/r/pull/474|null 4|wave/p-w4|https://github.com/o/r/pull/506|2026-10-13T00:15:43Z"
has "AJ15 the --verbose plain view names the wave PR" "$(run lane-status "$RF2" --verbose)" "wave 4 PR: https://github.com/o/r/pull/506  branch=wave/p-w4"
mv "$RF2.aj13" "$RF2"
# AJ16–AJ22: removed lanes and waves, from a hand-written lane table (no lane process, no gh). A removed lane's
# clone is gone; lane-status reads its run file from the salvage copy lane-remove kept, else the parent's
# `fleet closeout: <lane> … done (PR …)` line — so a lane that landed reads Done, not "Pick ✕".
AK="$T/ak"; AKP="$AK/primary"; AKL="$AK/primary-lanes/pk"; mkdir -p "$AKP/.supervisor/automate" "$AKL"
AKRF="$AKP/.supervisor/automate/pk.md"; AKT="$AKP/.supervisor/automate/pk.lanes"
printf '# Automate Run: pk\n\n## Run Config\n- parallel: 3\n\n## Progress\n%s\n%s\n%s\n' \
  '- 2026-10-14T16:00:00Z run started' \
  '- 2026-10-15T02:06:59Z wave built: wave/pk-w1 — PR https://github.com/o/r/pull/51 (lanes: L1 PR #48, L2 PR #50; ci pass; release skipped)' \
  '- fleet closeout: L2 reqs/b.md done (PR https://github.com/o/r/pull/50)' > "$AKRF"
aksv() { mkdir -p "$AKL/salvage/$1/supervisor/automate"; printf '%s\n' "${@:3}" > "$AKL/salvage/$1/supervisor/automate/$2.md"; }
aksv L1-removed-20261014T120000Z-1 pk-L1 '# Automate Run: pk-L1' '## Status: running' '' '## Current' '- item: reqs/a.md | status: running | pr: https://github.com/o/r/pull/1 | branch: old'
aksv L1-removed-20261015T022615Z-37742 pk-L1 '# Automate Run: pk-L1' '## Status: done' '' '## Current' \
  '- item: reqs/a.md | status: done | pr: https://github.com/o/r/pull/48 | branch: feature/a' '' '## Progress' \
  '- 2026-10-14T16:34:52Z run started' '- 2026-10-14T16:35:00Z picked reqs/a.md' '- 2026-10-15T02:25:19Z auto-finalized: queue empty after closeout'
aksv L10-removed-20261016T000000Z-9 pk-L1 '# Automate Run: pk-L1' '## Status: running' '' '## Current' '- item: reqs/z.md | status: running | pr: https://github.com/o/r/pull/999 | branch: wrong'
{ printf '#lane\tpath\titem\trun_id\tpid\tpid_start\tsession_id\tstate\tlast_launch_utc\tblocked_reason\n'
  printf '%s\n' "L1 reqs/a.md removed" "L2 reqs/b.md removed" "L3 reqs/c.md removed" "L4 reqs/d.md created" "L5 reqs/e.md abandoned" \
    | while read -r akn akit akst; do printf '%s\t%s\t%s\tpk-%s\t-\t-\t-\t%s\t2026-10-15T00:31:53Z\t-\n' "$akn" "$AKL/$akn" "$akit" "$akn" "$akst"; done
  } > "$AKT"
akd() { ( . "$S"; _lanes_status_doc "$AKT" pk "$AKP" ); }
akl() { jq -r --arg l "$1" ".lanes[] | select(.lane == \$l) | $2" <<<"$AKJ"; }
AKJ="$(akd)"
check "AJ16 removed + salvaged run file done ⇒ outcome done, PR/branch from the NEWEST own copy (never L10's), every step done, ended at its last dated line" \
  "$(akl L1 '"\(.state)|\(.outcome)|\(.pr)|\(.branch)|\(.ended_at)|\(.timeline.label)|\([.timeline.steps[].state] | unique | join(","))|\(.started_at)"')" \
  "removed|done|https://github.com/o/r/pull/48|feature/a|2026-10-15T02:25:19Z|Done|done|2026-10-14T16:34:52Z"
check "AJ17 removed, no salvage, the parent's fleet closeout line ⇒ outcome done, PR from that line, no end time invented" \
  "$(akl L2 '"\(.outcome)|\(.pr)|\(.ended_at)|\(.timeline.label)"')" "done|https://github.com/o/r/pull/50|null|Done"
check "AJ18 removed with neither ⇒ outcome removed, its step held (not trouble)" \
  "$(akl L3 '"\(.outcome)|\(.timeline.current)|\(.timeline.steps[0].state)"')" "removed|pick|held"
check "AJ19 abandoned ⇒ outcome abandoned; a lane not launched has no outcome and no end" \
  "$(akl L5 .outcome)|$(akl L4 '"\(.outcome)|\(.ended_at)"')" "abandoned|null|null"
check "AJ20 a wave whose every lane landed reads merged; the live lanes no wave carries are the next wave (removed/abandoned left out)" \
  "$(jq -r '"\([.waves[] | "\(.wave):\(.state):\(.lanes | join(","))"] | join(" "))|\(.next_wave.wave):\(.next_wave.lanes | join(","))"' <<<"$AKJ")" \
  "1:merged:L1,L2|2:L4"
sed -i.bak '/fleet closeout: L2/d' "$AKRF"
check "AJ21 one lane not landed yet ⇒ the wave reads open" "$(akd | jq -r '.waves[0].state')" open
sed -i.bak 's/^- parallel: 3$/- parallel: 1/' "$AKRF"
check "AJ22 single-lane mode ⇒ no next wave" "$(akd | jq -c '.next_wave')" null
sed -i.bak 's/^- parallel: 1$/- parallel: 3/' "$AKRF"
AKV="$( . "$S"; _lanes_render "$(akd)" )"
has "AJ23 the plain view names each wave's state and lanes" "$AKV" "branch=wave/pk-w1  built 2026-10-15T02:06:59Z  open  lanes L1,L2"
has "AJ23b … the wave not built yet" "$AKV" "wave 2 (not built yet): lanes L4"
has "AJ23c … and how a removed lane ended, and when" "$AKV" "L1  removed — done  item=reqs/a.md  pr=https://github.com/o/r/pull/48  ended=2026-10-15T02:25:19Z"

# ---- AL: validation-gate — the READY-park gate (af36-remainder/01) ------------------------------------------
# Fixtures only (never gh, never .supervisor/): pa16-item.md carries pa/16's `## Validation` section verbatim
# (`- ` bullets, a `**Running system:**` entry); pr-402-body.json is `gh pr view 402 --json body`, captured once.
VGF="$HERE/fixtures/validation-gate"; VG="$T/vg"; mkdir -p "$VG/.supervisor/automate" "$VG/reqs"
VGRF="$VG/.supervisor/automate/vg.md"; VGPR=https://github.com/vikashruhilgit/loomwright/pull/402
cp "$VGF/pa16-item.md" "$VG/reqs/pa16.md"
vg_rf() { printf '# Automate Run: vg\n## Status: running\n\n## Queue\n- [ ] reqs/pa16.md\n\n## Current\n- item: reqs/pa16.md | status: running | pr: %s | branch: f\n- pause_reason: null\n\n## Progress\n- 2026-10-12T09:00:00Z picked reqs/pa16.md\n' "$VGPR" > "$VGRF"; }
vg_rf
cat > "$T/vg-gh402" <<EOF
#!/usr/bin/env bash
[ "\$1 \$2" = "pr view" ] && { cat "$VGF/pr-402-body.json"; exit 0; }
exit 1
EOF
cat > "$T/vg-ghbody" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2" = "pr view" ] && { jq -n --rawfile b "$VG_BODY" '{body: $b}'; exit 0; }
exit 1
EOF
chmod +x "$T/vg-gh402" "$T/vg-ghbody"
vg() { LOOMWRIGHT_GH_BIN="${VG_GH:-$T/vg-gh402}" LOOMWRIGHT_LANES_HELPERS="$HERE/automate-helpers.sh" bash "${VG_S:-$S}" validation-gate "$@" 2>&1; }
vgb() { printf "$1" > "$T/vg.body"; VG_BODY="$T/vg.body" VG_GH="$T/vg-ghbody" vg "$VGRF" "${2:-reqs/pa16.md}" "$VGPR"; }
AL1_WANT="validation-gate: unrun — V2 Running system: no evidence in the PR body"
out="$(vg "$VGRF" reqs/pa16.md "$VGPR")"; rc=$?
check "AL1 AC1 #402 replay (pa/16 Validation + PR #402 body) ⇒ unrun naming the Running system step, exit 0" "$rc|$out" "0|$AL1_WANT"
check "AL1b the dispatcher delegates validation-gate (same verdict through automate-helpers.sh)" \
  "$(LOOMWRIGHT_GH_BIN="$T/vg-gh402" bash "$HERE/automate-helpers.sh" validation-gate "$VGRF" reqs/pa16.md "$VGPR" 2>&1)" "$AL1_WANT"
check "AL1c bullet-form Validation parsed: entries numbered 1..k, the Running system bullet classified" \
  "$( ( . "$S"; _lanes_validation_rows "$VG/reqs/pa16.md" /dev/null 0 ) | cut -f1,3 | tr '\t\n' ':,')" "1:other,2:running-system,"
check "AL1d a continuation line joins its bullet (the entry text, not only its first line, is read)" \
  "$(printf '# x\n## Validation\n- **Smoke:** a first line\n  that continues on the running system\n- **Other:** x\n' > "$T/vg-cont.md"; ( . "$S"; _lanes_validation_rows "$T/vg-cont.md" /dev/null 0 ) | cut -f1,3 | tr '\t\n' ':,')" \
  "1:running-system,2:other,"
out="$(vgb '## Test Plan\nValidation 2 — Running system: three clones at once\n```\npeak load1 31.2 (threshold 36)\n```\n')"
check "AL2 AC2 every running-system step pasted with fenced output ⇒ ok" "$out" "validation-gate: ok — 1 running-system step(s) evidenced"
out="$(vgb '## Not verified\n- **Running system:** three clones at once\n```\nnot run: machine shared\n```\n')"
check "AL3 a step whose evidence sits under a \"Not verified\" heading ⇒ NOT-RUN ⇒ unrun (fenced output there is no evidence)" \
  "$out" "validation-gate: unrun — V2 Running system: listed under a \"Not verified\" / \"Not run\" heading in the PR body"
out="$(vgb '## Evidence\n### Not run in this lane\nValidation 2 — running system\n```\nx\n```\n')"
has "AL3b … also under a nested \"Not run\" sub-heading" "$out" "unrun — V2 Running system: listed under"
out="$(vgb '## Test Plan\nValidation 2 — running system\n```\nFAIL - load1 63.6\n```\n')"
check "AL4 pasted output showing FAIL counts as not evidenced ⇒ unrun" "$out" "validation-gate: unrun — V2 Running system: pasted output shows FAIL"
# Review iteration 1: the PR-body scan is fence-aware, a "running system" title outranks the repro rule,
# and evidence is attributed to the step (not to every fence in its section).
out="$(vgb '## Not verified\n```\n# machine busy\n$ uptime\n```\n- **Running system:** three clones at once, skipped\n```\n$ date\n```\n')"
check "AL11 a \`#\` comment inside a fence is not a heading: the \"Not verified\" heading still governs ⇒ unrun" \
  "$out" "validation-gate: unrun — V2 Running system: listed under a \"Not verified\" / \"Not run\" heading in the PR body"
out="$(vgb '## Not verified\n```\n#!/usr/bin/env bash\n## step one\n```\nValidation 2 — running system\n```\npeak 31\n```\n')"
has "AL11b … nor a \`#!\` shebang or a \`## \` line inside a fence" "$out" "unrun — V2 Running system: listed under a \"Not verified\""
out="$(vgb '## Test Plan\n```\n# Validation 2 running system\n```\n')"
check "AL11c a match inside a fence never starts the step's evidence window" "$out" "validation-gate: unrun — V2 Running system: no evidence in the PR body"
printf '# r\n## Validation\n1. **Running system:** reproduce the freeze with three clones at once.\n2. **Repro:** must catch the mutation.\n' > "$VG/reqs/repro.md"
check "AL12 a Running system step whose first line says \"reproduce\" is still gated (title outranks the repro rule)" \
  "$(VG_GH="$T/vg-no-gh" vg "$VGRF" reqs/repro.md "$VGPR")" "validation-gate: unrun — V1 Running system: PR body unreadable ($VGPR)"
check "AL12b … and a repro-titled step keeps kind repro" \
  "$( ( . "$S"; _lanes_validation_rows "$VG/reqs/repro.md" /dev/null 0 ) | cut -f1,3 | tr '\t\n' ':,')" "1:running-system,2:repro,"
printf '# f\n## Validation\n1. **Smoke:** run it\n```\n## not a section\n- not an entry\n```\n2. **Running system:** three clones\n' > "$VG/reqs/fence.md"
check "AL12c item side: a fenced \`## \` / \`- \` line neither ends ## Validation nor starts an entry" \
  "$( ( . "$S"; _lanes_validation_rows "$VG/reqs/fence.md" /dev/null 0 ) | cut -f1,3 | tr '\t\n' ':,')" "1:other,2:running-system,"
out="$(vgb '## Test Plan\n- Running system (three clones): not run, machine shared.\n- unrelated bullet\n  ```\n  x\n  ```\n')"
check "AL13 (a) a matched line saying \"not run\" ⇒ NOT-RUN even with a fence later in the section" \
  "$out" "validation-gate: unrun — V2 Running system: marked not run / skipped / not verified in the PR body"
out="$(vgb '## Test Plan\n- Running system (three clones): deferred.\n- unrelated bullet\n  ```\n  x\n  ```\n')"
check "AL13b a bullet-started match ends at the next sibling bullet (its fence is not this step's evidence)" \
  "$out" "validation-gate: unrun — V2 Running system: mentioned in the PR body without pasted output"
out="$(vgb '## Test Plan\n**Not verified:**\n- Running system three clones\n```\nx\n```\n')"
check "AL14 (b) a whole-line bold **Not verified:** is a heading ⇒ unrun" \
  "$out" "validation-gate: unrun — V2 Running system: listed under a \"Not verified\" / \"Not run\" heading in the PR body"
out="$(vgb '## Summary\nFixes the running system freeze.\n\nExample:\n```\nx\n```\n')"
check "AL15 (c) a generic \"running system\" mention in the Summary does not borrow the next paragraph's fence ⇒ unrun" \
  "$out" "validation-gate: unrun — V2 Running system: mentioned in the PR body without pasted output"
out="$(vgb '## Test Plan\n### Validation 2 — running system\n\nRan three clones:\n\n```\n# load\npeak load1 31.2\n```\n')"
check "AL16 a heading-started step still owns its whole section (fence with a \`#\` line inside) ⇒ ok" "$out" "validation-gate: ok — 1 running-system step(s) evidenced"
# Review iteration 2: a not-run statement on ANY non-fenced line of the step's passage, an anchored step
# keeping its own intro paragraph, and no title-keyed evidence for a title two entries share.
out="$(vgb '## Test Plan\n- **Running system:** three clones\n  Not run: machine shared\n  ```\n  load1 82\n  ```\n')"
check "AL17 bullet form: \"Not run\" on the line AFTER the match, a fence following ⇒ unrun" \
  "$out" "validation-gate: unrun — V2 Running system: marked not run / skipped / not verified in the PR body"
out="$(vgb '## Test Plan\n### Validation 2 - running system\nNot run, machine shared.\n```\nload1 82\n```\n')"
check "AL17b heading form: \"Not run\" in the section body, a fence following ⇒ unrun" \
  "$out" "validation-gate: unrun — V2 Running system: marked not run / skipped / not verified in the PR body"
out="$(vgb '## Test Plan\nValidation 2 — running system: three clones\n```\n3 skipped, 0 not run, peak load1 31\n```\n')"
check "AL17c … but \"skipped\" / \"not run\" inside the pasted output is output, not the PR's statement ⇒ ok" \
  "$out" "validation-gate: ok — 1 running-system step(s) evidenced"
out="$(vgb '## Test Plan\nValidation 2 (running system): ran three clones at once.\n\nOutput:\n\n```\npeak load1 31\n```\n')"
check "AL18 AC2 an anchored step keeps its intro paragraph (\"Output:\") and the fence after it ⇒ ok" \
  "$out" "validation-gate: ok — 1 running-system step(s) evidenced"
out="$(vgb '## Test Plan\nValidation 1 — running system: no, the smoke run.\n```\nok\n```\n')"
check "AL18b a title mention on another step's anchored line is never borrowed ⇒ unrun" \
  "$out" "validation-gate: unrun — V2 Running system: no evidence in the PR body"
printf '# t\n## Validation\n- **Running system:** three clones at once.\n- **Running system:** a rerun on a quiet machine.\n' > "$VG/reqs/twin.md"
out="$(vgb '## Test Plan\n- **Running system:** three clones\n  ```\n  peak load1 31\n  ```\n## Not verified\n- the quiet-machine rerun: deferred\n' reqs/twin.md)"
check "AL19 two entries titled \"Running system\": one generic passage evidences neither (no title match) ⇒ unrun" \
  "$out" "validation-gate: unrun — V1 Running system: no evidence in the PR body"
out="$(vgb '## Test Plan\nValidation 1 — running system, three clones:\n```\npeak load1 31\n```\n## Not verified\n- the quiet-machine rerun: deferred\n' reqs/twin.md)"
check "AL19b … each needs its own \"validation <n>\": only V1 anchored ⇒ unrun naming V2" \
  "$out" "validation-gate: unrun — V2 Running system: no evidence in the PR body"
out="$(vgb '## Test Plan\nValidation 1 — three clones:\n```\npeak load1 31\n```\nValidation 2 — quiet machine:\n```\npeak load1 4\n```\n' reqs/twin.md)"
check "AL19c … both anchored with output ⇒ ok — 2 steps" "$out" "validation-gate: ok — 2 running-system step(s) evidenced"
# Review iteration 3: an anchored passage crosses a paragraph break only after an intro line ending in
# `:`, and the wider not-run vocabulary (outside fences only).
out="$(vgb '## Test Plan\nValidation 2 - running system: could not get to this, machine shared.\n\nUnit test output:\n```\nok\n```\n')"
check "AL20 repro A: \"could not get to this.\" + a later paragraph's fence ⇒ unrun (never ok)" \
  "$out" "validation-gate: unrun — V2 Running system: marked not run / skipped / not verified in the PR body"
out="$(vgb '## Test Plan\nValidation 2 - running system: not yet run; needs a quiet machine.\n\nCI is green on the branch.\n\nShellcheck output:\n```\nok\n```\n')"
check "AL20b repro B: \"not yet run\" + unrelated paragraphs + a fence ⇒ unrun" \
  "$out" "validation-gate: unrun — V2 Running system: marked not run / skipped / not verified in the PR body"
out="$(vgb '## Test Plan\nValidation 2 - running system: deferred; needs a quiet machine.\n\nCI is green on the branch.\n\nShellcheck output:\n```\nok\n```\n')"
check "AL20c the boundary alone (no not-run words): an unrelated paragraph after the step's sentence closes the passage ⇒ unrun" \
  "$out" "validation-gate: unrun — V2 Running system: mentioned in the PR body without pasted output"
out="$(vgb '## Test Plan\nValidation 2 (running system):\n\nRan three clones:\n\n```\npeak load1 31\n```\n')"
check "AL20d an intro chain ending in \":\" keeps the fence (U13c shape, running-system step) ⇒ ok" \
  "$out" "validation-gate: ok — 1 running-system step(s) evidenced"
out="$(vgb '## Test Plan\nValidation 2 - running system: deferred.\n\nWe ran the unit tests\ninstead.\n\nOutput:\n```\nok\n```\n')"
check "AL20g an intro paragraph is crossed into only at the passage's FIRST break ⇒ unrun" \
  "$out" "validation-gate: unrun — V2 Running system: mentioned in the PR body without pasted output"
vg_voc=""
for ph in "not yet run" "wasn't run" "was not run" "couldn't run" "could not run" "could not get to it" "not tested" "untested"; do
  out="$(vgb "## Test Plan\nValidation 2 - running system: $ph.\n\`\`\`\npeak load1 31\n\`\`\`\n")"
  [ "$out" = "validation-gate: unrun — V2 Running system: marked not run / skipped / not verified in the PR body" ] || vg_voc="$vg_voc [$ph: $out]"
done
check "AL20e the not-run vocabulary (not yet run / wasn't / was not / couldn't / could not run / could not get to / not tested / untested) ⇒ unrun even with a fence" "${vg_voc:-none}" none
out="$(vgb '## Test Plan\nValidation 2 - running system: three clones\n```\nuntested: 0, not tested: 0, peak load1 31\n```\n')"
check "AL20f … but those words inside the pasted output are output ⇒ ok" "$out" "validation-gate: ok — 1 running-system step(s) evidenced"
# Drain round 1: a numbered entry and a bullet in one section never share a number (bullets follow the
# section's largest N), and two numbered entries that DO share one are each NOT-RUN.
printf '# m\n## Validation (must pass before merge)\n1. **Baseline:** tests green.\n- **Running system:** start three clones and record peak load.\n' > "$VG/reqs/mixed.md"
check "AL21 mixed numbered + bulleted section: entries numbered 1, 2 (never two 1s)" \
  "$( ( . "$S"; _lanes_validation_rows "$VG/reqs/mixed.md" /dev/null 0 ) | cut -f1,3 | tr '\t\n' ':,')" "1:other,2:running-system,"
out="$(vgb '## Test Plan\nValidation 1: baseline\n```\nok 12 passed\n```\n' reqs/mixed.md)"
check "AL21b the drain repro: the Baseline's \"Validation 1\" never evidences the Running system bullet ⇒ unrun" \
  "$out" "validation-gate: unrun — V2 Running system: no evidence in the PR body"
out="$(vgb '## Test Plan\nValidation 1: baseline\n```\nok 12 passed\n```\nValidation 2: three clones\n```\npeak load1 31\n```\n' reqs/mixed.md)"
check "AL21c … the Running system bullet evidenced by its own \"Validation 2\" ⇒ ok" "$out" "validation-gate: ok — 1 running-system step(s) evidenced"
printf '# m\n## Validation\n- **Smoke:** x\n3. **Baseline:** tests green.\n- **Running system:** three clones.\n' > "$VG/reqs/mixed2.md"
check "AL21d a bullet BEFORE a numbered entry still takes a number above the section's largest N (4, 3, 5)" \
  "$( ( . "$S"; _lanes_validation_rows "$VG/reqs/mixed2.md" /dev/null 0 ) | cut -f1,3 | tr '\t\n' ':,')" "4:other,3:other,5:running-system,"
check "AL21e a purely bulleted section is unchanged (1..k)" \
  "$( ( . "$S"; _lanes_validation_rows "$VG/reqs/twin.md" /dev/null 0 ) | cut -f1,3 | tr '\t\n' ':,')" "1:running-system,2:running-system,"
printf '# d\n## Validation\n1. **Smoke:** x\n1. **Running system:** three clones.\n' > "$VG/reqs/dup.md"
out="$(vgb '## Test Plan\nValidation 1: three clones\n```\npeak load1 31\n```\n' reqs/dup.md)"
check "AL21f two numbered entries sharing a number: the anchor is ambiguous ⇒ unrun (never ok)" \
  "$out" "validation-gate: unrun — V1 Running system: entry number 1 is not unique in the item's ## Validation section (renumber the item)"
printf '# n\n## Validation (must pass before merge)\n1. **Baseline:** tests green.\n2. **Unchanged path:** a READY drain whose PR body pastes every running-system step parks as before.\n' > "$VG/reqs/norun.md"
printf '# n\n## Touches\n- `x`\n' > "$VG/reqs/noval.md"
check "AL5 AC5 no running-system entry (\"running-system\" hyphenated is not the phrase) ⇒ none" \
  "$(VG_GH="$T/vg-no-gh" vg "$VGRF" reqs/norun.md "$VGPR")" "validation-gate: none — no running-system step in reqs/norun.md"
check "AL5b AC5 no ## Validation section at all ⇒ none" "$(vg "$VGRF" reqs/noval.md "$VGPR")" "validation-gate: none — no running-system step in reqs/noval.md"
# AL22: the entry grammar reads every list style, and a section it cannot parse fails CLOSED (the
# proposed/validation-gate-parser-fail-open repro: `* ` / `1) ` items once read as zero entries ⇒ `none`).
printf '# s\n## Validation\n* **Smoke:** tests green.\n* **Running system:** start three clones.\n' > "$VG/reqs/star.md"
printf '# s\n## Validation\n+ **Smoke:** tests green.\n+ **Running system:** start three clones.\n' > "$VG/reqs/plus.md"
printf '# s\n## Validation\n1) **Smoke:** tests green.\n2) **Running system:** start three clones.\n' > "$VG/reqs/paren.md"
vg_ls=""
for st in star plus paren; do
  r="$( ( . "$S"; _lanes_validation_rows "$VG/reqs/$st.md" /dev/null 0 ) | cut -f1,3 | tr '\t\n' ':,')"
  [ "$r" = "1:other,2:running-system," ] || vg_ls="$vg_ls [$st rows: $r]"
  out="$(vgb '## Test Plan\nValidation 1: baseline\n```\nok 12 passed\n```\n' "reqs/$st.md")"
  [ "$out" = "validation-gate: unrun — V2 Running system: no evidence in the PR body" ] || vg_ls="$vg_ls [$st unevidenced: $out]"
  out="$(vgb '## Test Plan\nValidation 2: three clones\n```\npeak load1 31\n```\n' "reqs/$st.md")"
  [ "$out" = "validation-gate: ok — 1 running-system step(s) evidenced" ] || vg_ls="$vg_ls [$st evidenced: $out]"
done
check "AL22 \`* \` / \`+ \` / \`N) \` entries read as 1:other, 2:running-system; unevidenced ⇒ unrun, evidenced ⇒ ok" "${vg_ls:-none}" none
check "AL22b \`* \` / \`N) \` fallback titles drop their marker like \`- \` / \`N. \`" \
  "$(printf '# s\n## Validation\n* plain smoke step\n3) plain running system step\n' > "$T/vg-ft.md"; ( . "$S"; _lanes_validation_rows "$T/vg-ft.md" /dev/null 0 ) | cut -f1,2 | tr '\t\n' ':,')" \
  "4:plain smoke step,3:plain running system step,"
AL22C_WANT="validation-gate: unrun — reqs/prose.md: the ## Validation section has no parseable entry (an entry is a column-0 N. / N) / - / * / + list item)"
printf '# p\n## Validation (must pass before merge)\nStart the app on the running system and paste its output.\n\n## Touches\n- `x`\n' > "$VG/reqs/prose.md"
out="$(vg "$VGRF" reqs/prose.md "$VGPR")"; rc=$?
check "AL22c a ## Validation section that parses to no entry ⇒ unrun with the reason (never none), exit 0" "$rc|$out" "0|$AL22C_WANT"
printf '# e\n## Validation\n\n## Touches\n- `x`\n' > "$VG/reqs/empty.md"
check "AL22d an empty ## Validation section ⇒ unrun (fail CLOSED)" "$(vg "$VGRF" reqs/empty.md "$VGPR")" \
  "validation-gate: unrun — reqs/empty.md: the ## Validation section has no parseable entry (an entry is a column-0 N. / N) / - / * / + list item)"
out="$(vg "$VGRF" reqs/prose.md "$VGPR" --waive 0 --words "ok")"; rc=$?
check "AL22e the step-less unrun has nothing to waive (--waive 0 refused, exit 1)" "$rc|$out" "1|validation-gate: refused — V0 is not a running-system Validation entry of reqs/prose.md"
# Mutation control: the guard removed, the unparseable section must read `none` again — AL22c goes red.
mkdir -p "$T/vgmut2"; cp "$HERE"/resolve-loomwright-root.sh "$T/vgmut2/" 2>/dev/null
sed '/^  if \[ -n "\$ev" \]; then echo "\$G unrun — \$item: \$ev"; return 0; fi$/d' "$SB" > "$T/vgmut2/automate-lanes.sh"
if [ ! -s "$T/vgmut2/automate-lanes.sh" ] || cmp -s "$SB" "$T/vgmut2/automate-lanes.sh" || ! bash -n "$T/vgmut2/automate-lanes.sh"; then
  bad "AL22f guard mutant not built (empty, sed matched nothing, or bash -n failed)"
else
  out="$(VG_S="$T/vgmut2/automate-lanes.sh" vg "$VGRF" reqs/prose.md "$VGPR")"
  if [ "$out" != "$AL22C_WANT" ]; then ok "AL22f mutation control: the unparsed-section guard removed turns AL22c red (mutant prints: $out)"
  else bad "AL22f mutant still printed the AL22c verdict — AL22c is vacuous"; fi
fi
out="$(vgb '## Test Plan\nValidation 2 - running system: three clones; the machine was not running hot.\n```\npeak load1 31\n```\n')"
check "AL22g the not-run vocabulary is whole phrases: \"not running hot\" is not \"not run\" ⇒ ok" "$out" "validation-gate: ok — 1 running-system step(s) evidenced"
out="$(vgb '## Test Plan\nValidation 2 - running system: not run (needs a quiet machine).\n```\npeak load1 31\n```\n')"
check "AL22h … while \"not run\" as its own phrase still marks the step ⇒ unrun" \
  "$out" "validation-gate: unrun — V2 Running system: marked not run / skipped / not verified in the PR body"
out="$(VG_GH="$T/vg-no-gh" vg "$VGRF" reqs/pa16.md "$VGPR")"; rc=$?
check "AL6 AC6 gh unreadable ⇒ unrun (fail CLOSED, exit 0)" "$rc|$out" "0|validation-gate: unrun — V2 Running system: PR body unreadable ($VGPR)"
check "AL6b AC6 no PR url ⇒ unrun" "$(vg "$VGRF" reqs/pa16.md "")" "validation-gate: unrun — V2 Running system: PR body unreadable: no PR recorded"
out="$(vg "$VGRF" reqs/missing.md "$VGPR")"; rc=$?
check "AL6c AC6 unreadable item file ⇒ unrun (exit 0)" "$rc|$out" "0|validation-gate: unrun — item file unreadable: reqs/missing.md"
check "AL6d no arguments ⇒ unrun (usage), exit 0" "$(vg; echo "rc=$?")" "validation-gate: unrun — usage: validation-gate <runfile> <item> <pr_url> [--waive <n> --words <text>]
rc=0"
check "AL6e an extra positional argument ⇒ unrun (never ok), exit 0" "$(vg "$VGRF" reqs/pa16.md "$VGPR" extra; echo "rc=$?")" "validation-gate: unrun — unexpected argument 'extra'; usage: validation-gate <runfile> <item> <pr_url> [--waive <n> --words <text>]
rc=0"
check "AL6f an absolute item path is read as given (not re-rooted)" "$(vg "$VGRF" "$VG/reqs/pa16.md" "$VGPR")" "$AL1_WANT"
# AC3 — the owner waiver
out="$(vg "$VGRF" reqs/pa16.md "$VGPR" --waive 2 --words "run it at wave close on a quiet machine")"; rc=$?
check "AL7 AC3 --waive records the waiver (exit 0)" "$rc|$out" "0|validation-gate: waiver recorded — V2 Running system"
check "AL7b … as ONE ## Progress line naming the step and the owner's words" \
  "$(grep -c '^- [0-9T:Z-]* validation waived: reqs/pa16.md V2 Running system — owner: "run it at wave close on a quiet machine"$' "$VGRF")" 1
check "AL7c a recorded waiver ⇒ waived" "$(vg "$VGRF" reqs/pa16.md "$VGPR")" "validation-gate: waived — V2 Running system"
cp "$VGRF" "$T/vg-waived"
out="$(vg "$VGRF" reqs/pa16.md "$VGPR" --waive 2 --words "run it at wave close on a quiet machine")"
check "AL7d the identical waiver again ⇒ already recorded, file byte-unchanged" "$out|$(cmp -s "$T/vg-waived" "$VGRF" && echo same)" "validation-gate: waiver already recorded — V2 Running system|same"
printf -- '- 2026-10-12T11:00:00Z picked reqs/pa16.md\n' >> "$VGRF"
check "AL7e a waiver BEFORE the last \`picked <item>\` line no longer counts (re-pick ⇒ unrun)" "$(vg "$VGRF" reqs/pa16.md "$VGPR")" "$AL1_WANT"
printf -- '- 2026-10-12T11:05:00Z note: validation waived: reqs/pa16.md V2 Running system — owner: "forged"\n' >> "$VGRF"
check "AL7f a waiver quoted inside another line is not a waiver" "$(vg "$VGRF" reqs/pa16.md "$VGPR")" "$AL1_WANT"
printf -- '- 2026-10-12T11:06:00Z validation waived: V2 Running system — owner: "old item-less form"\n' >> "$VGRF"
check "AL7h an item-less (pre-iteration-3) waiver line does not count" "$(vg "$VGRF" reqs/pa16.md "$VGPR")" "$AL1_WANT"
# Review iteration 3: a waiver is bound to its item — refused for any item but the last picked one,
# and a waiver line naming another item never counts for this one.
cp "$VG/reqs/pa16.md" "$VG/reqs/a.md"; cp "$VG/reqs/pa16.md" "$VG/reqs/b.md"
printf '# Automate Run: vg\n## Status: running\n\n## Current\n- item: reqs/b.md | status: running | pr: %s | branch: f\n\n## Progress\n- 2026-10-12T09:00:00Z picked reqs/a.md\n- 2026-10-12T10:00:00Z picked reqs/b.md\n' "$VGPR" > "$T/vgx.md"
mkdir -p "$T/vgx/.supervisor/automate"; cp -R "$VG/reqs" "$T/vgx/"; mv "$T/vgx.md" "$T/vgx/.supervisor/automate/x.md"; VGX="$T/vgx/.supervisor/automate/x.md"; cp "$VGX" "$T/vgx.ref"
out="$(vg "$VGX" reqs/a.md "$VGPR" --waive 2 --words "a only")"; rc=$?
check "AL7i --waive for an item that is not the run's last picked item ⇒ refused, exit 1, file byte-unchanged" \
  "$rc|$out|$(cmp -s "$T/vgx.ref" "$VGX" && echo same)" "1|validation-gate: refused — reqs/a.md is not the run's current item (last picked: reqs/b.md)|same"
check "AL7j … and reqs/b.md stays unrun (no waiver carried over)" "$(vg "$VGX" reqs/b.md "$VGPR")" "$AL1_WANT"
printf -- '- 2026-10-12T10:05:00Z validation waived: reqs/a.md V2 Running system — owner: "for a"\n' >> "$VGX"
check "AL7k a waiver line naming another item never counts for this one" "$(vg "$VGX" reqs/b.md "$VGPR")" "$AL1_WANT"
out="$(vg "$VGX" ./reqs/b.md "$VGPR" --waive 2 --words "for b")"; rc=$?
check "AL7l --waive for the current item (leading ./ stripped) records it naming the item" \
  "$rc|$out|$(grep -c '^- [0-9T:Z-]* validation waived: reqs/b.md V2 Running system — owner: "for b"$' "$VGX")" "0|validation-gate: waiver recorded — V2 Running system|1"
check "AL7m … and counts for reqs/b.md" "$(vg "$VGX" reqs/b.md "$VGPR")" "validation-gate: waived — V2 Running system"
vg_rf; cp "$VGRF" "$T/vg-ref"; vg_bad=""
for wa in "--waive 2 --words ''" "--waive 2 --words 'a|b'" "--waive 1 --words 'ok'" "--waive 9 --words 'ok'" "--waive x --words 'ok'" "--waive 2" "--words 'ok'"; do
  eval "set -- $wa"; out="$(vg "$VGRF" reqs/pa16.md "$VGPR" "$@")"; rc=$?
  { [ "$rc" = 1 ] && cmp -s "$T/vg-ref" "$VGRF" && case "$out" in "validation-gate: refused — "*) true ;; *) false ;; esac; } || vg_bad="$vg_bad [$wa rc=$rc $out]"
done
out="$(vg "$VGRF" reqs/pa16.md "$VGPR" --waive 2 --words "$(printf 'a\nb')")"; rc=$?
{ [ "$rc" = 1 ] && cmp -s "$T/vg-ref" "$VGRF"; } || vg_bad="$vg_bad [newline rc=$rc]"
printf '# Automate Run: vg\n\n## Current\n- item: null\n\n## Progress\n- 2026-10-12T09:00:00Z run started\n' > "$T/vg-nopick.md"; cp "$T/vg-nopick.md" "$T/vg-nopick.ref"
mkdir -p "$T/vgnp/.supervisor/automate" "$T/vgnp/reqs"; cp "$VG/reqs/pa16.md" "$T/vgnp/reqs/"; mv "$T/vg-nopick.md" "$T/vgnp/.supervisor/automate/np.md"
out="$(vg "$T/vgnp/.supervisor/automate/np.md" reqs/pa16.md "$VGPR" --waive 2 --words ok)"; rc=$?
{ [ "$rc" = 1 ] && cmp -s "$T/vg-nopick.ref" "$T/vgnp/.supervisor/automate/np.md"; } || vg_bad="$vg_bad [no-picked rc=$rc $out]"
check "AL7g every waiver refusal (empty / | / newline words, a non-running-system or unknown <n>, no --words, --words alone, no picked line) exits 1, file byte-unchanged" "${vg_bad:-none}" none
# The title cleaner: a `|`-bearing fallback title becomes a legal `current-escalation --check` value.
printf '# p\n## Validation\n1. Running system check a|b on the real host\n' > "$VG/reqs/pipe.md"
out="$(VG_GH="$T/vg-no-gh" vg "$VGRF" reqs/pipe.md "$VGPR")"
check "AL8 a |-bearing fallback title is cleaned (| → /)" "$out" "validation-gate: unrun — V1 Running system check a/b on the real host: PR body unreadable ($VGPR)"
vchk="${out#validation-gate: unrun — }"; vchk="${vchk%%: *}"
cp "$VGRF" "$T/vg-esc.md"; sed -i.bak 's/^- item: reqs\/pa16.md | status: running/- item: reqs\/pa16.md | status: escalated/' "$T/vg-esc.md"
out="$(bash "$HERE/automate-helpers.sh" current-escalation "$T/vg-esc.md" --cause validation_unrun --check "$vchk" --sha 1e35336 2>&1)"; rc=$?
check "AL8b … and \`current-escalation --cause validation_unrun --check \"V<n> <title>\"\` accepts it" \
  "$rc|$out|$(grep -c "^- escalation_cause: validation_unrun | check: V1 Running system check a/b on the real host | run_id: null | attempt: null | sha: 1e35336$" "$T/vg-esc.md")" "0|current-escalation: written|1"
# AC7 — ONE shared reader: lane-readiness and validation-gate both call it; neither parses `## Validation`.
vg_fn() { awk -v f="$1() {" '$0 == f { on = 1 } on { print } on && /^}$/ { exit }' "$SB"; }
check "AL9 AC7 lane-readiness + validation-gate read Validation only through _lanes_validation_rows" \
  "$(vg_fn lanes_readiness | grep -c '_lanes_validation_rows'):$(vg_fn lanes_validation_gate | grep -c '_lanes_validation_rows' | awk '{ print ($1 >= 2) }'):$(vg_fn lanes_readiness | grep -c 'Validation/'):$(vg_fn lanes_validation_gate | grep -c 'Validation/'):$(grep -c 'on = (\$0 ~ /^## Validation/)' "$SB")" "1:1:0:0:1"
# AC9 mutation control: the gate's verdict replaced with an unconditional `ok` must turn AL1 red.
mkdir -p "$T/vgmut"; cp "$HERE"/resolve-loomwright-root.sh "$T/vgmut/" 2>/dev/null
sed 's/^    echo "\$G unrun — V\$n \$title: \$ev"; return 0$/    echo "$G ok — $k running-system step(s) evidenced"; return 0/' "$SB" > "$T/vgmut/automate-lanes.sh"
if [ ! -s "$T/vgmut/automate-lanes.sh" ] || cmp -s "$SB" "$T/vgmut/automate-lanes.sh" || ! bash -n "$T/vgmut/automate-lanes.sh"; then
  bad "AL10 AC9 mutant not built (empty, sed matched nothing, or bash -n failed)"
else
  out="$(VG_S="$T/vgmut/automate-lanes.sh" vg "$VGRF" reqs/pa16.md "$VGPR")"
  if [ "$out" != "$AL1_WANT" ]; then ok "AL10 AC9 mutation control: an unconditional ok verdict turns AL1 red (mutant prints: $out)"
  else bad "AL10 AC9 mutant still printed the AL1 verdict — AL1 is vacuous"; fi
fi

# ---- AM: superseded lane questions (L8 of run automate-2026-10-15-163325, 2026-10-16) ------------------
# The incident: the lane asked toolu_s1 (relay-hook recorded it and deferred), could not exit deferred,
# ended a PLAIN turn, and on `--continue` re-asked as toolu_s2, which the owner answered. toolu_s1 never
# got an answer file, so "question file with no answer file" kept it pending: --inbox and the pane showed
# it, lane-answer refused it ("parked on another question"), and the parked lane read awaiting_input
# (refusing lane-convert-ready / wave-build / lane-remove) until the coordinator moved it by hand.
# The rule: relay-hook recording a NEW id supersedes every older unanswered question of the lane.
PAM=automate-2026-10-16-040000; RFAM="$P/.supervisor/automate/$PAM.md"; LAM="$T/work/primary-lanes/$PAM"
printf '# Automate Run: %s\n\n## Progress\n' "$PAM" > "$RFAM"
for n in 1 2; do run lane-create "$RFAM" reqs/a.md "$n" --parallel 2 >/dev/null; done
QS1='[{"question":"Save the brief?","header":"Save","multiSelect":false,"options":[{"label":"Save and exit","description":"s"},{"label":"Revise","description":"r"}]}]'
am_defer() { jq -n -c --arg id "$1" --argjson q "$QS1" '{type: "result", subtype: "success", stop_reason: "tool_deferred", session_id: "sess-123", deferred_tool_use: {id: $id, name: "AskUserQuestion", input: {questions: $q}}}'; }
am_seq() { # <lane dir> <relay-hook script> — the L8 sequence up to the lane parking deferred on toolu_s2
  # (the relay hook runs with the REAL automate-helpers.sh, so its ## Progress line lands in the lane run file)
  local l="$1" hs="$2"
  printf '# Automate Run: %s\n\n## Current\n- item: reqs/a.md | status: awaiting_merge | pr: https://github.com/o/r/pull/7 | branch: f\n- pause_reason: ready_for_release\n\n## Progress\n' \
    "$PAM-${l##*/}" > "$l/.supervisor/automate/$PAM-${l##*/}.md"
  hook_in PreToolUse "$l" toolu_s1 "$QS1" | LOOMWRIGHT_LANES_HELPERS="$HERE/automate-helpers.sh" bash "$hs" relay-hook >/dev/null
  STUB_MODE=ok LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$l" --owner-command "$OWN" >/dev/null; wait_gone "$l"   # a plain turn end
  hook_in PreToolUse "$l" toolu_s2 "$QS1" | LOOMWRIGHT_LANES_HELPERS="$HERE/automate-helpers.sh" bash "$hs" relay-hook >/dev/null
  STUB_DEFER_LINE="$(am_defer toolu_s2)" STUB_MODE=defer LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$l" --owner-command "$OWN" --continue >/dev/null; wait_gone "$l"
}
am_pending() { ( . "$S"; _lanes_pending_questions "$1/.supervisor/inbox" | tr '\n' ' ' | sed 's/ $//' ); }
am_ans() { printf '{"answers":{"0":"Save and exit"}}' | LOOMWRIGHT_LANE_RECHECK_S=0 bash "$S" lane-answer "$1" "$2" --owner-command "$OWN" 2>&1; }
LA1="$LAM/L1"; am_seq "$LA1" "$S"
SUPF="$LA1/.supervisor/inbox/questions/superseded/toolu_s1.json"
check "AM1 the re-ask supersedes the abandoned question: only toolu_s2 is pending" "$(am_pending "$LA1")" toolu_s2
check "AM2 the record is kept (moved, never deleted) and names the newer id" \
  "$([ -e "$LA1/.supervisor/inbox/questions/toolu_s1.json" ] && echo live || echo moved):$(jq -r '[.id, .superseded_by, (.superseded_at | test("Z$")), (.questions | length)] | map(tostring) | join(",")' "$SUPF")" \
  "moved:toolu_s1,toolu_s2,true,1"
check "AM3 ONE lane ## Progress line names it" \
  "$(grep -c '^- [0-9TZ:-]* question superseded: toolu_s1 by toolu_s2 (the lane re-asked; record kept in .supervisor/inbox/questions/superseded/)$' "$LA1/.supervisor/automate/$PAM-L1.md" | tr -d ' ')" 1
out="$(am_ans "$LA1" toolu_s1)"; rc=$?
check "AM4 lane-answer on the superseded id refuses, naming the newer id" \
  "$rc:$out" "1:automate-lanes: lane-answer: refused — toolu_s1 superseded by toolu_s2 (the lane re-asked; answer toolu_s2)"
check "AM4b … and writes no answer file for it" "$([ -e "$LA1/.supervisor/inbox/answers/toolu_s1.json" ] && echo written || echo none)" none
jq -n -c --arg id toolu_s1 '{schema_version: 1, lane: "L1", tool_use_id: $id, answers: {"0": "Save and exit"}, note: null, via: "cli", held_at: "2026-10-16T03:50:00Z"}' \
  > "$P/.supervisor/automate/$PAM.L1.answer-pending.json"
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 bash "$S" lane-answer "$LA1" --deliver-pending --owner-command "$OWN" 2>&1)"; rc=$?
check "AM5 a HELD answer kept for the superseded id is discarded on delivery, naming the newer id" \
  "$rc:$out:$([ -e "$P/.supervisor/automate/$PAM.L1.answer-pending.json" ] && echo kept || echo discarded)" \
  "1:automate-lanes: lane-answer: refused — the pending answer for L1 no longer matches (toolu_s1 superseded by toolu_s2 (the lane re-asked; answer toolu_s2)); discarded — the question is shown again:discarded"
out="$(am_ans "$LA1" toolu_s2)"; rc=$?
check "AM6 the newer question is answered as usual" "$rc:$(jq -r '.answers["Save the brief?"]' "$LA1/.supervisor/inbox/answers/toolu_s2.json")" "0:Save and exit"
wait_gone "$LA1"
out="$(hook_in PreToolUse "$LA1" toolu_s2 "$QS1" | bash "$S" relay-hook)"
check "AM7 the resume re-fires the SAME id: allowed with its answer, nothing superseded" \
  "$(jq -r '.hookSpecificOutput.permissionDecision' <<<"$out"):$(ls "$LA1/.supervisor/inbox/questions/superseded" | tr '\n' ' ')" "allow:toolu_s1.json "
# AM7b the coordinator's hand fix on 2026-10-16 left a record with no superseded_by: still refused, by its own wording
jq -n -c --argjson q "$QS1" '{id: "toolu_h1", asked_at: "2026-10-16T03:40:00Z", questions: $q}' > "$LA1/.supervisor/inbox/questions/superseded/toolu_h1.json"
out="$(am_ans "$LA1" toolu_h1)"; rc=$?
check "AM7b a hand-moved record (no superseded_by) is refused as superseded, naming no id" \
  "$rc:$out" "1:automate-lanes: lane-answer: refused — toolu_h1 superseded by a newer question (its record names none)"
check "AM8 the two-question sequence leaves 0 pending" "$(am_pending "$LA1")" ""
JAM="$(bash "$S" lane-status "$RFAM" --json 2>/dev/null)"
check "AM9 lane-status reads the lane's real state (its park), not awaiting_input; no questions (the pane)" \
  "$(jq -r '.lanes[] | select(.lane == "L1") | "\(.state):\(.questions | length)"' <<<"$JAM")" "ready_for_release:0"
has "AM10 lane-status --inbox lists nothing" "$(run lane-status "$RFAM" --inbox)" "inbox — 0 pending human question call(s)"
hasnt "AM11 lane-remove no longer refuses awaiting_input" "$(run lane-remove "$LA1")" "awaiting_input"
# AM12 mutation control: relay-hook without the supersede step replays the incident on a fresh lane —
# toolu_s1 stays pending, so AM1/AM8 and AM9 would be red.
sed 's/ && _lanes_supersede_older "\$root" "\$id"$//' "$SB" > "$MUT/automate-lanes.sh"
if cmp -s "$SB" "$MUT/automate-lanes.sh" || ! bash -n "$MUT/automate-lanes.sh"; then
  bad "AM12 mutant not built (sed matched nothing, or bash -n failed)"
else
  LA2="$LAM/L2"; am_seq "$LA2" "$MUT/automate-lanes.sh"; am_ans "$LA2" toolu_s2 >/dev/null; wait_gone "$LA2"
  JAM="$(bash "$S" lane-status "$RFAM" --json 2>/dev/null)"
  check "AM12 mutation (supersede step removed): the abandoned question stays pending and the lane reads awaiting_input" \
    "$(am_pending "$LA2")|$(jq -r '.lanes[] | select(.lane == "L2") | .state' <<<"$JAM")" "toolu_s1|awaiting_input"
fi

hasnt "Z1 gh never called" "$(cat "$GH_CALLS" 2>/dev/null)" "gh"
# AA-F12z (final leg): nothing this suite started may outlive it — no process whose command line names
# the suite dir $T (pgrep -f on the ERE-escaped path), after the same stop the EXIT trap performs.
for p in $BG_PIDS $(pgrep -f "_lane-run $T" 2>/dev/null); do kill -TERM "$p" 2>/dev/null; done
i=0; while pgrep -f "$(ere "$T")" >/dev/null 2>&1 && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
AA_LEFT="$(for p in $(pgrep -f "$(ere "$T")" 2>/dev/null); do ps -o pid= -o command= -p "$p" 2>/dev/null; done)"
check "AA-F12z no process naming the suite dir survives the suite" "${AA_LEFT:-none}" none
