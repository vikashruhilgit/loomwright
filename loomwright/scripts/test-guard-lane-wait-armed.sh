#!/usr/bin/env bash
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
# test-guard-lane-wait-armed.sh — hermetic self-tests for guard-lane-wait-armed.sh, the Stop hook that
# sends the `/automate --parallel` coordinator back to arm `lane-wait` when it ends a turn with a live
# wave and no watcher (lane-guardrails part 1).
#
# Fixture: a bare fake origin + a "primary" clone + a parent run file; real lanes made by
# automate-lanes.sh `lane-create` (meta-sync / setup-memory / helpers / machine-load stubbed through its
# seams), a `claude` PATH stub that sleeps (a RUNNING lane is a real `_lane-run` process), and the
# coordinator's run lock taken with the real run-lock.sh. No network, no real claude, no gh.
#
# Groups: A allow cases (no lock · another session's lock · agent_type · a continued turn · a lock that
#   is not a lane coordinator's · all lanes quiet · parent done · live marker · background lane-wait ·
#   a reported question) · B block cases (coordinator + live lane + no marker · dead-pid marker ·
#   pid-reuse marker · running lane · unreported question · cwd a subdirectory) · C fail-safe (malformed /
#   empty / non-object payload, missing automate-lanes.sh) · D runtime bound · E mutation control (the
#   session-id match is load-bearing) · F every output is exactly one JSON object, exit 0.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
H="$HERE/guard-lane-wait-armed.sh"
S="$HERE/automate-lanes.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"
BG_PIDS=""
cleanup() {
  local p
  for p in $BG_PIDS $(pgrep -f "_lane-run $T" 2>/dev/null); do kill -TERM "$p" 2>/dev/null; done
  rm -rf "$T"
}
trap cleanup EXIT

PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$3] got [$2]"; fi; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing [$3] in [$(printf '%s' "$2" | head -c 600)]" ;; esac; }

export HOME="$T/home"; mkdir -p "$HOME"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_CONFIG_NOSYSTEM=1
unset CLAUDE_PLUGIN_ROOT CLAUDE_PROJECT_DIR LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS

BIN="$T/bin"; mkdir -p "$BIN"
cat > "$BIN/claude" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--help" ]; then echo "--permission-prompt-tool --allowedTools --disallowedTools --plugin-dir"; exit 0; fi
cat >/dev/null
echo '{"type":"system","subtype":"init","session_id":"sess-g1"}'
trap 'kill $! 2>/dev/null; exit 143' TERM; sleep 60 & wait $!
EOF
cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >> "$GH_CALLS"; exit 1
EOF
export GH_CALLS="$T/gh.calls"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/meta-sync.sh"
printf '#!/usr/bin/env bash\necho "off"\n' > "$T/setup-memory.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/helpers.sh"
printf '#!/usr/bin/env bash\necho %s\n' "'{\"state\":\"ok\"}'" > "$T/load.sh"
printf '#!/usr/bin/env bash\necho "{}"\n' > "$T/policy.sh"
chmod +x "$BIN/claude" "$BIN/gh" "$T"/*.sh
export PATH="$BIN:$PATH"
export LOOMWRIGHT_LANES_META_SYNC="$T/meta-sync.sh" LOOMWRIGHT_LANES_SETUP_MEMORY="$T/setup-memory.sh"
export LOOMWRIGHT_LANES_HELPERS="$T/helpers.sh" LOOMWRIGHT_MACHINE_LOAD_CMD="$T/load.sh" LOOMWRIGHT_LANES_POLICY="$T/policy.sh"
export LOOMWRIGHT_LANES_INIT_WAIT_S=3 LOOMWRIGHT_LANE_RECHECK_S=0

# ---- fixture ----------------------------------------------------------------------------------------
ORIGIN="$T/origin.git"; P="$T/work/primary"
git init -q --bare "$ORIGIN"; git --git-dir="$ORIGIN" symbolic-ref HEAD refs/heads/main
git init -q "$P"; git -C "$P" checkout -q -b main
printf '.supervisor/*\n.claude/settings.local.json\n' > "$P/.gitignore"
mkdir -p "$P/reqs" "$P/sub/dir"; echo "# a" > "$P/reqs/a.md"; echo "# b" > "$P/reqs/b.md"; echo x > "$P/sub/dir/f"
git -C "$P" add -A; git -C "$P" commit -qm init
git -C "$P" remote add origin "$ORIGIN"; git -C "$P" push -q -u origin main 2>/dev/null
PARENT=automate-2026-10-11-090000
AD="$P/.supervisor/automate"; mkdir -p "$AD"
RF="$AD/$PARENT.md"; TABLE="$AD/$PARENT.lanes"; MARK="$AD/$PARENT.lane-wait.pid"; SEEN="$AD/$PARENT.lane-wait-seen"
printf '# Automate Run: %s\n\n## Status: running\n\n## Progress\n' "$PARENT" > "$RF"
for n in 1 2; do bash "$S" lane-create "$RF" reqs/a.md "$n" --parallel 2 >/dev/null 2>&1; done
L1="$T/work/primary-lanes/$PARENT/L1"; L2="$T/work/primary-lanes/$PARENT/L2"
check "fixture: two created lanes" "$(awk -F'\t' '!/^#/ { print $1 ":" $8 }' "$TABLE" | tr '\n' ' ')" "L1:created L2:created "
COORD=sess-coordinator-1
bash "$HERE/run-lock.sh" acquire --owner "automate-lanes:$PARENT" --session-id "$COORD" --root "$P" >/dev/null 2>&1
check "fixture: the coordinator holds the run lock" "$(awk -F'\t' '$1 == "owner" { print $2 }' "$P/.supervisor/run.lock/meta")" "automate-lanes:$PARENT"

# pl <session_id> [<jq filter applied to the payload>] — a main-thread Stop payload from the primary.
pl() { jq -n -c --arg s "$1" --arg cwd "${PL_CWD:-$P}" '{session_id: $s, transcript_path: "/x", cwd: $cwd,
  hook_event_name: "Stop", stop_hook_active: false, last_assistant_message: "done", background_tasks: [], session_crons: []}' \
  | jq -c "${2:-.}"; }
# hook <payload> [<hook script>] — sets OUT and RC.
hook() { OUT="$(printf '%s' "$1" | bash "${2:-$H}" 2>"$T/hook.err")"; RC=$?; }
dec() { jq -r '.decision // "allow"' <<<"$OUT" 2>/dev/null || echo unparseable; }
one_obj() { [ "$RC" = 0 ] && [ "$(jq -s 'length' <<<"$OUT" 2>/dev/null)" = 1 ] && [ "$(jq -r 'type' <<<"$OUT" 2>/dev/null)" = object ]; }
F_SHAPE=0
shape() { one_obj || { F_SHAPE=$((F_SHAPE + 1)); bad "F shape after: $1" "rc=$RC out=[$OUT] err=[$(cat "$T/hook.err")]"; }; }
tset() { awk -F'\t' -v OFS='\t' -v l="$1" -v c="$2" -v v="$3" '$1 == l { $c = v } { print }' "$TABLE" > "$TABLE.t" && mv "$TABLE.t" "$TABLE"; }

# ---- B: block cases -----------------------------------------------------------------------------------
hook "$(pl "$COORD")"; shape B1
check "B1 coordinator session + live (created) lanes + no marker ⇒ block" "$(dec)" block
R="$(jq -r .reason <<<"$OUT")"
has "B1b the reason names the run and the live lane states" "$R" "($PARENT: L1 created, L2 created)"
has "B1c the reason says no watcher is running" "$R" "no lane-wait watcher is running"
has "B1d the reason gives the exact background command (this checkout's automate-lanes.sh)" "$R" "Arm it as a BACKGROUND command: bash $S lane-wait $RF (SKILL §14 step 8), then end the turn."
PL_CWD="$P/sub/dir" hook "$(PL_CWD="$P/sub/dir" pl "$COORD")"; shape B6
check "B6 a cwd inside the checkout resolves to its toplevel ⇒ block" "$(dec)" block

sleep 0 & DEADPID=$!; wait "$DEADPID" 2>/dev/null
printf '%s %s\n' "$DEADPID" "$(date +%s)" > "$MARK"
hook "$(pl "$COORD")"; shape B2
check "B2 a marker whose pid is dead ⇒ block" "$(dec)" block
sleep 30 & REUSE=$!; BG_PIDS="$BG_PIDS $REUSE"
printf '%s %s\n' "$REUSE" "$(date +%s)" > "$MARK"
hook "$(pl "$COORD")"; shape B3
check "B3 a marker whose pid is alive but not a lane-wait (pid reuse) ⇒ block" "$(dec)" block
kill "$REUSE" 2>/dev/null; rm -f "$MARK"

# ---- A: allow cases ---------------------------------------------------------------------------------
hook "$(pl sess-someone-else)"; shape A2
check "A2 another session (not the lock's) ⇒ allow" "$OUT" "{}"
hook "$(pl "$COORD" '. + {agent_type: "loomwright:loomwright:worker"}')"; shape A3
check "A3 a payload with a top-level agent_type ⇒ allow" "$OUT" "{}"
hook "$(pl "$COORD" '.stop_hook_active = true')"; shape A4
check "A4 a turn already continued by a Stop block ⇒ allow (never loops)" "$OUT" "{}"
NL_DIR="$T/work/nolock"; mkdir -p "$NL_DIR"
PL_CWD="$NL_DIR" hook "$(PL_CWD="$NL_DIR" pl "$COORD")"; shape A1
check "A1 no run lock in the checkout ⇒ allow" "$OUT" "{}"
hook "$(pl "$COORD" '.background_tasks = [{id: "b1", type: "bash", status: "running", description: "bash automate-lanes.sh lane-wait x.md"}]')"; shape A9
check "A9 a running background task naming lane-wait ⇒ allow (marker not written yet)" "$OUT" "{}"
hook "$(pl "$COORD" '.background_tasks = [{id: "b1", type: "bash", status: "completed", description: "lane-wait"}]')"; shape A9b
check "A9b … a COMPLETED one does not count ⇒ block" "$(dec)" block

# A8 + marker lifecycle: a real lane-wait is a live watcher; its exit removes its marker.
bash "$S" lane-wait "$RF" --interval 1 --timeout 60 > "$T/lw.out" 2>&1 &
LW=$!; BG_PIDS="$BG_PIDS $LW"
i=0; while [ ! -s "$MARK" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
check "A8a lane-wait writes its marker naming its own pid" "$(awk '{ print $1 }' "$MARK" 2>/dev/null)" "$LW"
hook "$(pl "$COORD")"; shape A8
check "A8 a live lane-wait marker ⇒ allow" "$OUT" "{}"
kill -TERM "$LW" 2>/dev/null; wait "$LW" 2>/dev/null
check "A8c lane-wait's exit removed the marker" "$([ -e "$MARK" ] && echo present || echo absent)" absent
hook "$(pl "$COORD")"; shape A8d
check "A8d … so the next turn end blocks again" "$(dec)" block

cp "$RF" "$T/rf.bak"; printf '# Automate Run: %s\n\n## Status: done\n' "$PARENT" > "$RF"
hook "$(pl "$COORD")"; shape A7
check "A7 the parent run file reads ## Status: done ⇒ allow" "$OUT" "{}"
cp "$T/rf.bak" "$RF"

cp "$TABLE" "$T/table.bak"; tset L1 8 removed; tset L2 8 abandoned
hook "$(pl "$COORD")"; shape A6
check "A6 every lane quiet (removed / abandoned) ⇒ allow" "$OUT" "{}"
cp "$T/table.bak" "$TABLE"

cp "$P/.supervisor/run.lock/meta" "$T/meta.bak"
awk -F'\t' -v OFS='\t' '$1 == "owner" { $2 = "automate:'"$PARENT"'" } { print }' "$T/meta.bak" > "$P/.supervisor/run.lock/meta"
hook "$(pl "$COORD")"; shape A5
check "A5 a run lock held by a sequential /automate (not automate-lanes:) ⇒ allow" "$OUT" "{}"
cp "$T/meta.bak" "$P/.supervisor/run.lock/meta"

# ---- B4/B5 + A10: a RUNNING lane, and a lane holding a question ---------------------------------------
bash "$S" lane-launch "$L1" --owner-command '/automate --parallel 2' >/dev/null 2>&1
check "fixture: L1 launched and running" "$(bash "$S" lane-status "$RF" --json 2>/dev/null | jq -r '.lanes[] | select(.lane == "L1") | .state')" running
tset L2 8 launched; tset L2 9 "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq -n -c '{id: "toolu_g1", asked_at: "2026-10-11T09:00:00Z", questions: [{question: "Which way?", header: "Way", options: [{label: "A"}, {label: "B"}]}]}' \
  > "$L2/.supervisor/inbox/questions/toolu_g1.json"
hook "$(pl "$COORD")"; shape B4
check "B4 a running lane + no marker ⇒ block" "$(dec)" block
R="$(jq -r .reason <<<"$OUT")"
has "B4b the running lane is named" "$R" "L1 running"
has "B5 an unreported question is named and must be relayed first" "$R" "A lane question is pending and unrelayed (L2 toolu_g1) — relay it to the owner first (bash $S lane-status $RF --inbox)."
has "B5b … its lane is listed by its state" "$R" "L2 awaiting_input"

# D: runtime bound on the live fixture (block path: the slowest, with its 0.1 s marker re-read).
ms() { perl -MTime::HiRes=time -e 'printf "%d\n", time() * 1000' 2>/dev/null; }
if [ -n "$(ms)" ]; then
  best=999999; for k in 1 2 3; do
    t0="$(ms)"; printf '%s' "$(pl "$COORD")" | bash "$H" >/dev/null 2>&1; t1="$(ms)"
    [ $((t1 - t0)) -lt "$best" ] && best=$((t1 - t0))
  done
  bestA=999999; for k in 1 2 3; do
    t0="$(ms)"; printf '%s' "$(pl sess-other)" | bash "$H" >/dev/null 2>&1; t1="$(ms)"
    [ $((t1 - t0)) -lt "$bestA" ] && bestA=$((t1 - t0))
  done
  echo "#    runtime: block path (running lane + question) best of 3 = ${best} ms; allow path (another session) = ${bestA} ms"
  [ "$best" -lt 1500 ] && ok "D1 block path finishes well inside a turn end (< 1500 ms; measured ${best} ms)" || bad "D1 block path too slow" "${best} ms"
  [ "$bestA" -lt 500 ] && ok "D2 the allow path of a non-coordinator session is cheap (< 500 ms; measured ${bestA} ms)" || bad "D2 allow path too slow" "${bestA} ms"
else
  ok "D1/D2 SKIP — no perl Time::HiRes for a millisecond clock"
fi

# A10: once lane-wait reported the question (seen ledger), it is the coordinator's to relay — no re-block
# on it alone (a re-armed watcher would exit idle at once and ping-pong). L1 stops running ⇒ nothing live.
printf 'question L2 toolu_g1\n' > "$SEEN"
L1PID="$(awk -F'\t' '$1 == "L1" { print $5 }' "$TABLE")"
for c in $(pgrep -P "$L1PID" 2>/dev/null); do kill -TERM "$c" 2>/dev/null; done
i=0; while kill -0 "$L1PID" 2>/dev/null && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
hook "$(pl "$COORD")"; shape A10
check "A10 no live lane and only a REPORTED question ⇒ allow" "$OUT" "{}"
jq -c '.id = "toolu_g2"' "$L2/.supervisor/inbox/questions/toolu_g1.json" > "$L2/.supervisor/inbox/questions/toolu_g2.json"
hook "$(pl "$COORD")"; shape A10c
check "A10c a SECOND question on the same lane, not yet reported ⇒ block" "$(dec)" block
has "A10d … naming only the unreported one" "$(jq -r .reason <<<"$OUT")" "unrelayed (L2 toolu_g2)"
rm -f "$L2/.supervisor/inbox/questions/toolu_g2.json"
rm -f "$SEEN"
hook "$(pl "$COORD")"; shape A10b
check "A10b the same question NOT yet reported ⇒ block" "$(dec)" block

# ---- C: fail-safe ------------------------------------------------------------------------------------
hook '{{{ not json'; shape C1; check "C1 malformed payload ⇒ {}" "$OUT" "{}"
hook ''; shape C2; check "C2 empty payload ⇒ {}" "$OUT" "{}"
hook '[1,2]'; shape C3; check "C3 a non-object payload ⇒ {}" "$OUT" "{}"
hook "$(pl "")"; shape C4; check "C4 no session_id ⇒ {}" "$OUT" "{}"
# C7 an EMPTY field never shifts the next one (fields are 0x1f-joined, not tab-joined: IFS whitespace
# would merge them): no cwd in the payload ⇒ CLAUDE_PROJECT_DIR is the checkout, and the block holds.
OUT="$(pl "$COORD" '.cwd = ""' | CLAUDE_PROJECT_DIR="$P" bash "$H" 2>"$T/hook.err")"; RC=$?; shape C7
check "C7 an empty cwd falls back to CLAUDE_PROJECT_DIR (no field shift) ⇒ block" "$(dec)" block
LONE="$T/lone"; mkdir -p "$LONE"; cp "$H" "$LONE/"
hook "$(pl "$COORD")" "$LONE/guard-lane-wait-armed.sh"; shape C5
check "C5 automate-lanes.sh not beside the hook ⇒ {} (fail SAFE)" "$OUT" "{}"
chmod 000 "$TABLE"
if [ -r "$TABLE" ]; then ok "C6 SKIP — running as a user that ignores mode bits"; else
  hook "$(pl "$COORD")"; shape C6; check "C6 an unreadable lane table ⇒ {}" "$OUT" "{}"; fi
chmod 644 "$TABLE"

# ---- E: mutation control — the session-id match is load-bearing ----------------------------------------
MUT="$T/mut"; mkdir -p "$MUT"; cp "$S" "$MUT/"
grep -v '\[ "\$LOCK_SID" = "\$SID" \] || allow' "$H" > "$MUT/guard-lane-wait-armed.sh"
if ! cmp -s "$H" "$MUT/guard-lane-wait-armed.sh" && bash -n "$MUT/guard-lane-wait-armed.sh"; then ok "E0 mutant valid (differs, bash -n)"; else bad "E0 mutant invalid"; fi
hook "$(pl sess-someone-else)"; check "E1 the real hook allows another session" "$OUT" "{}"
hook "$(pl sess-someone-else)" "$MUT/guard-lane-wait-armed.sh"
check "E2 mutation (session-id check removed) blocks another session — the check is load-bearing" "$(dec)" block

check "F every hook run printed exactly one JSON object and exited 0" "$F_SHAPE" 0
check "Z gh never called" "$(cat "$GH_CALLS" 2>/dev/null)" ""
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
