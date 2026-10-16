#!/usr/bin/env bash
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/wait-lib.sh"   # bounded condition waits (iq02 T07)
# test-automate-lanes.sh — hermetic self-tests for automate-lanes.sh (parallel-automate/05, lane
# lifecycle). Fixture: a bare fake origin + a "primary" clone of it holding two items and a parent run
# file, all under one mktemp dir. `claude` is a PATH stub that records argv / env / stdin and prints
# stream-json; `gh` is a PATH stub that fails the test if called; meta-sync / setup-memory /
# automate-helpers / machine-load are stubbed through the script's seams. No network, no real claude.
#
# Groups: A create (AC1) · B leftover salvage · C meta pull failure · D hook merge · E init-check (AC12)
#   F launch authority / regime / host denial · G admission (AC10 launch-hold half) · H launch shape
#   I checksum + mutation control (AC16) · J relay hook (AC6) · K lane-answer (AC6) · L .died marker
#   M liveness + pick-guard (AC12) · N lane-remove refusals (AC3) + mutation controls (AC16)
#   O lane-info · P branch-check · Q lane-status classification (AC7) · R lane-status --json (AC8)
#   S keep-awake · T --watch + lane-feed · U merge-readiness (AC9) · V --leaks / --resources / --tokens
#     (V15-V20: the merge-watch section reads live watchers from their markers — a process that only NAMES
#     the script is no leak, + mutation control; a v1 snapshot section is not compared)
#   W drain-round-1 hardening: one-call token total (D8) + mutation control · trailing value flags
#     exit promptly · unpushed count unreadable refuses + mutation control · lock holder records
#     (dead holder reclaimed, live holder waited on, foreign lock never unlocked, holder-less lock
#     reclaimed) · two concurrent launches spawn once · multiSelect labels containing commas ·
#     lane-remove --stop refuses before stopping + mutation control
#   X relay hook from a linked worktree of the lane (git common dir; older git) + mutation control
#   Y lane-convert-ready: refusals, convert + single-path push, idempotent re-run, failed push, removal
#   Z Validation 4/5 fixes (parallel-automate/23): F5 readiness report · F9 leak check after removal ·
#     F1 snapshot before the lane table · F10 no absolute path / real state · F4 resume in the last
#     session · F2 HELD answer kept + delivered under an owner command · F11 gated wave-end push + ABANDONED
#   AA Validation 4/5 fixes B (parallel-automate/24): F6 lane-park-notify (truthful per-channel delivery)
#     · F8 real transcript usage ⇒ non-zero lane TOTAL + a ceiling-check PARK · F12 lane-feed --follow leaves
#     no pipeline behind on TERM / HUP / INT, and no process naming the suite dir outlives the suite
#   AB merged lane close-out (automate-followups/38): lane-convert-ready runs `closeout --no-trail` inside
#     the lane on its awaiting_merge re-run only (OPEN ⇒ nothing written; MERGED ⇒ stamp + check-off +
#     done/awaiting_go, pushed), a done/awaiting_go re-run retries only the pushes, leftover / no-pr / mode off
#   AC a lane whose run wrote an Orchestrator task plan: the wave-end exact list carries it (a done-headed
#     *-plan.md never), the re-run names the state it reads, lane-remove removes with no hand push + mutation
#     (parallel-automate/21 A1: in branch mode the merged re-run also finalizes, so AB3f/AB3g/AB4b read the
#     finalized state — `pause_reason: null`, `## Status: done`; the done/awaiting_go re-run is AE4c)
#   AD fleet operations Part B (parallel-automate/21): lane-create carries the resolved policy into lane.json
#     (null without one), relay-hook applies a policy answer (source policy) or defers exactly as before,
#     lane-status policy digest + --inbox
#   AE lane-convert-ready finalizes a closed-out lane in branch mode (A1); mode off skips finalize
#   AF fleet-closeout: stepwise, idempotent wave close (A2) — backstop, check-off, sync, removal, lanes dir,
#     leaks, main health, lock release; gone / meta-push-failed are the human's; a failed pull stops it;
#     AF3m-AF12 the Queue-empty parent finalize (done + wave line cleared + one trail-pr, skipped on a
#     re-run, never with an item left, FAILED write still releases the lock, mode off unstages) + mutation
#   AH lane-wait: the coordinator's lane watcher — events, seen ledger (prune / keep), timeout, idle,
#     usage, read-only toward lanes; AH15 its liveness marker (written, handed over to a second watcher,
#     removed only by its owner, absent on the idle paths); AH16 _lanes_quick_state (the Stop hook's
#     classifier) agrees with lane-status on every live / attention state of the fleet
#   AI gate opt-out carry (lane-guardrails part 3): the FACT recorded coordinator-side at first launch,
#     every resume path refused without it (exit 3, no spawn, nothing in the lane), lane-answer keeps the
#     validated answer pending, --without-gate-optout resumes without it and clears the fact, never added
#   AG wave-plan is READ-ONLY (A4: refs + tree byte-identical) + mutation control; the A3/A4 static guards
#     (no executable merge / push / gate-eval) + mutation control; A5 no sequential caller
#   AK a lane whose worker filed a proposed/ requirement draft (wave W4): the wave-end exact list carries
#     it (a done-headed proposed/ file never), the lane is removable with no hand push; lane-remove's
#     unpushed-metadata refusal — and so fleet-closeout's waiting line — names the paths + two mutations
#   AJ lane timeline: the seven steps from `## Progress` + Supervisor state (pick-guarded), boundaries,
#     current-step state per lane state, a park before the drain stays on the step reached (L5 Launch Pad
#     blocked, unpinned wordings, the pinned no-PR status_reason line) + mutation controls, the JSON fields
#     and the plain steps line; `waves` from the
#     parent run file's wave-build records (undated hand line, colon inside the parenthetical)
#   E7-E9 init-check single-lane mode: branch mode required for N = 1 (fail CLOSED), no mode read for N > 1
#   SL single-lane mode `--parallel 1` (twin-remediation/08b): lane.json single_lane (first leg) · lane-park seam ·
#     fresh lane numbers 1..99 · whole-run token ceiling · lane-remove / fleet-closeout `fleet closeout: <lane>
#     tokens TOTAL=<n>` line (before the removal) · lane-drain-check (dispatch marker by the dispatcher's own
#     PR_HASH block, owned drains after the LAST picked — timestamp optional, colon form tolerated — config
#     backup, unknown) · both tokens-line readers take an optional timestamp · current-set's single_lane
#     refusal · the merge watcher's documented launch line outlives its parent + a nohup mutation control
#   AL validation-gate (af36-remainder/01): the #402 replay (pa/16's bullet Validation + PR #402's body,
#     both fixtures under fixtures/validation-gate/) ⇒ unrun; evidenced ⇒ ok; no running-system step ⇒
#     none; unreadable PR body / item ⇒ unrun; "Not verified" heading ⇒ NOT-RUN; FAIL ⇒ unrun; the owner
#     waiver (counted only for its item, after the last `picked <item>`) + its refusals; a `|`-bearing title is a legal
#     `current-escalation --check`; ONE shared reader; AC9 mutation control (unconditional ok ⇒ AL1 red);
#     fence-aware PR-body + item scans, a "running system" title outranking the repro rule, and evidence
#     attributed to the step (not-run line, bold pseudo-heading, sibling bullet, next paragraph) — AL11–AL16;
#     a not-run statement on any non-fenced line, an anchored step's intro paragraph, and no title-keyed
#     evidence for a title two entries share — AL17–AL19, U13c; an anchored passage crossing a paragraph
#     break only via an intro line ending in `:`, the wider not-run vocabulary — AL20–AL20g; a waiver
#     bound to its item (named in the line, refused for any item but the last picked) — AL7h–AL7m;
#     `* ` / `+ ` / `N) ` entries parse like `- ` / `N. `, a section that exists but parses to no entry
#     reads `unrun` (never `none`) with its own mutation control, and the not-run vocabulary matches
#     whole phrases only ("not running hot" stays PASS) — AL22–AL22h
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/automate-lanes.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"
BG_PIDS=""
# ere <text> — <text> as a literal extended regex (pgrep / pkill -f take an ERE: an unescaped `+` in
# `tail -n +1` means "one or more spaces", so the literal never matched — parallel-automate/24 F12).
ere() { printf '%s' "$1" | sed 's/[][\.*^$+?(){}|]/\\&/g'; }
cleanup() {
  local p
  for p in $BG_PIDS $(pgrep -f "_lane-run $T" 2>/dev/null); do kill -TERM "$p" 2>/dev/null; done
  pkill -TERM -f "$(ere "$T")" 2>/dev/null   # safety net only — the AA-F12z leg is the assertion
  rm -rf "$T"
}
trap cleanup EXIT

PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$3] got [$2]"; fi; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing [$3] in [$(printf '%s' "$2" | head -c 600)]" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1" "unexpected [$3]" ;; *) ok "$1" ;; esac; }

export HOME="$T/home"; mkdir -p "$HOME"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_CONFIG_NOSYSTEM=1
unset CLAUDE_PLUGIN_ROOT LOOMWRIGHT_ROOT LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS   # the AI group sets the opt-out per command; a pre-set neutral root would beat the location-derived one

BIN="$T/bin"; mkdir -p "$BIN"
export STUB_LOG="$T/claude.log"; : > "$STUB_LOG"
cat > "$BIN/claude" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--help" ]; then
  if [ -n "${STUB_NO_REGIME:-}" ]; then echo "Usage: claude [options]"; else echo "--permission-prompt-tool --allowedTools --disallowedTools --plugin-dir"; fi
  exit 0
fi
{ printf 'ARGS'; for a in "$@"; do printf ' [%s]' "$a"; done; printf '\n'
  printf 'ENV CEIL=%s CC=%s PID=%s OPTOUT=%s\n' "${CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS-unset}" "${CLAUDECODE-unset}" "${CLAUDE_PID-unset}" "${LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS-unset}"
  printf 'HOLDERENV %s\n' "${LOOMWRIGHT_HOLDER_PID-unset}"
  printf 'STDIN %s\n' "$(cat)"; printf 'CWD %s\n' "$PWD"
  printf 'RESUMEPATH %s\n' "${LOOMWRIGHT_LANE_RESUME_PATH-unset}"; } >> "$STUB_LOG"
if [ -n "${STUB_RESUME_FAIL:-}" ]; then
  for a in "$@"; do [ "$a" = --resume ] && { echo "No conversation found with session ID" >&2; exit 1; }; done
fi
echo '{"type":"system","subtype":"init","session_id":"sess-123"}'
case "${STUB_MODE:-ok}" in
  sleep) trap 'kill $! 2>/dev/null; exit 143' TERM; sleep 60 & wait $! ;;
  defer) printf '%s\n' "$STUB_DEFER_LINE" ;;
  die) exit 1 ;;
  *) echo '{"type":"result","subtype":"success","stop_reason":"end_turn","session_id":"sess-123"}' ;;
esac
EOF
cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >> "${GH_CALLS:-/dev/null}"; exit 1
EOF
export GH_CALLS="$T/gh.calls"
cat > "$T/meta-sync.sh" <<'EOF'
#!/usr/bin/env bash
echo "meta-sync $*" >> "$META_LOG"
case "$1" in
  pull) [ -n "${STUB_META_FAIL:-}" ] && exit 1; exit 0 ;;
  status) echo "${STUB_META_STATUS:-in_sync}"; exit 0 ;;
esac
EOF
cat > "$T/setup-memory.sh" <<'EOF'
#!/usr/bin/env bash
echo "${STUB_MODE_LINE:-on test-meta}"
EOF
cat > "$T/helpers.sh" <<'EOF'
#!/usr/bin/env bash
echo "helpers $*" >> "$HELPERS_LOG"
EOF
cat > "$T/load.sh" <<'EOF'
#!/usr/bin/env bash
printf '{"load1":1,"cpus":8,"state":"%s"}\n' "${STUB_LOAD:-ok}"
EOF
chmod +x "$BIN/claude" "$BIN/gh" "$T"/*.sh
export PATH="$BIN:$PATH"
export META_LOG="$T/meta.log" HELPERS_LOG="$T/helpers.log"; : > "$META_LOG"; : > "$HELPERS_LOG"
export LOOMWRIGHT_LANES_META_SYNC="$T/meta-sync.sh" LOOMWRIGHT_LANES_SETUP_MEMORY="$T/setup-memory.sh"
export LOOMWRIGHT_LANES_HELPERS="$T/helpers.sh" LOOMWRIGHT_MACHINE_LOAD_CMD="$T/load.sh"
export LOOMWRIGHT_LANES_INIT_WAIT_S=5 LOOMWRIGHT_LANES_STOP_GRACE_S=2
# the wave-end evidence-gated trail (F11) runs through this seam; a no-op stub everywhere but Z-F11
cat > "$T/trail-stub.sh" <<'EOF'
#!/usr/bin/env bash
echo "trail $*" >> "$T_TRAIL_LOG"; echo "trail-pr: skipped — meta no_changes"
EOF
chmod +x "$T/trail-stub.sh"; export LOOMWRIGHT_LANES_TRAIL="$T/trail-stub.sh" T_TRAIL_LOG="$T/trail.log"

# ---- fixture ----------------------------------------------------------------------------------------
ORIGIN="$T/origin.git"; P="$T/work/primary"
git init -q --bare "$ORIGIN"; git --git-dir="$ORIGIN" symbolic-ref HEAD refs/heads/main
git init -q "$P"; git -C "$P" checkout -q -b main
printf '.supervisor/*\n.claude/settings.local.json\n' > "$P/.gitignore"
mkdir -p "$P/reqs"; echo "# a" > "$P/reqs/a.md"; echo "# b" > "$P/reqs/b.md"
git -C "$P" add -A; git -C "$P" commit -qm init
git -C "$P" remote add origin "$ORIGIN"; git -C "$P" push -q -u origin main 2>/dev/null
git -C "$P" branch primary-only
PARENT=automate-2026-10-07-120000
mkdir -p "$P/.supervisor/automate"
printf '# Automate Run: %s\n\n## Progress\n' "$PARENT" > "$P/.supervisor/automate/$PARENT.md"
printf '{"auto_review": true, "x": [1, 2]}\n' > "$P/.supervisor/config.json"
printf '{"desktop": false}\n' > "$P/.supervisor/notify-config.json"
RF="$P/.supervisor/automate/$PARENT.md"; TABLE="$P/.supervisor/automate/$PARENT.lanes"
LR="$T/work/primary-lanes/$PARENT"
run() { bash "$S" "$@" 2>&1; }
claude_calls() { grep -c '^ARGS' "$STUB_LOG" | tr -d ' '; }
tcol() { awk -F'\t' -v l="$1" -v c="$2" '$1 == l { print $c }' "$TABLE"; }
lane_sum() { (cd "$1" && find . -path ./.git -prune -o -type f -print | env LC_ALL=C sort | while IFS= read -r f; do cksum "$f"; done) | cksum; }
wait_gone() { local i=0; while pgrep -f "_lane-run $1 " >/dev/null 2>&1 && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done; }

# ---- A: create (AC1) --------------------------------------------------------------------------------
out="$(run lane-create "$RF" reqs/a.md 1 --parallel 2 --max-tokens 1000)"; rc=$?
check "A1 lane-create L1 exits 0" "$rc" 0
has "A1 names the lane path" "$out" "$LR/L1"
out="$(run lane-create "$RF" reqs/b.md 2 --parallel 2 --max-tokens 1000)"; check "A2 lane-create L2 exits 0" "$?" 0
L1="$LR/L1"; L2="$LR/L2"
check "A3 origin is the remote URL, not the primary" "$(git -C "$L1" remote get-url origin)" "$ORIGIN"
hasnt "A4 inherited primary-only ref pruned" "$(git -C "$L1" branch -r)" "primary-only"
check "A5 config.json byte-for-byte" "$(cmp -s "$P/.supervisor/config.json" "$L1/.supervisor/config.json" && echo same)" same
check "A6 notify-config.json byte-for-byte" "$(cmp -s "$P/.supervisor/notify-config.json" "$L2/.supervisor/notify-config.json" && echo same)" same
check "A7 lane.json shape" "$(jq -c '[.schema_version, .lane, .run_id, .parent_run_id, .primary, .parallel, .max_tokens, (.created | test("Z$"))]' "$L1/.supervisor/lane.json")" \
  "[1,\"L1\",\"$PARENT-L1\",\"$PARENT\",\"$P\",2,500,true]"
check "A8 L2 run id" "$(jq -r .run_id "$L2/.supervisor/lane.json")" "$PARENT-L2"
check "A9 one-line backlog naming the canonical path" "$(cat "$L1/.supervisor/lane-backlog.md")" "- [ ] reqs/a.md"
has "A10 meta pull passes --branch explicitly" "$(cat "$META_LOG")" "meta-sync pull --branch test-meta --root $L1"
check "A11 relay hooks installed (PreToolUse + PermissionRequest)" \
  "$(jq -r '[.hooks.PreToolUse[0].matcher, (.hooks.PreToolUse[0].hooks[0].command | test("automate-lanes.sh\" relay-hook$")), .hooks.PermissionRequest[0].matcher] | join(",")' "$L1/.claude/settings.local.json")" \
  "AskUserQuestion,true,AskUserQuestion"
check "A12 lane table rows" "$(awk -F'\t' '!/^#/ { print $1 ":" $4 ":" $8 }' "$TABLE" | tr '\n' ' ')" "L1:$PARENT-L1:created L2:$PARENT-L2:created "
has "A13 lane table records what does not carry" "$(cat "$TABLE")" "not carried into lanes"
check "A14 lane clean after create" "$(git -C "$L1" status --porcelain)" ""
check "A15 lane on the base branch" "$(git -C "$L1" rev-parse --abbrev-ref HEAD)" main
hasnt "A16 no gh call during create" "$(cat "$GH_CALLS" 2>/dev/null)" "gh"

# ---- B: leftover directory salvaged then refused ----------------------------------------------------
mkdir -p "$LR/L9/.supervisor"; echo keep > "$LR/L9/.supervisor/note.txt"
out="$(run lane-create "$RF" reqs/a.md 9)"; rc=$?
check "B1 leftover lane dir refused" "$rc" 1
has "B2 refusal names never reused" "$out" "never reused"
check "B3 leftover salvaged" "$(cat "$LR"/salvage/L9-leftover-*/supervisor/note.txt 2>/dev/null)" keep
check "B4 leftover untouched" "$(cat "$LR/L9/.supervisor/note.txt")" keep
rm -rf "$LR/L9"

# ---- C: meta pull failure aborts and removes the clone ----------------------------------------------
out="$(STUB_META_FAIL=1 run lane-create "$RF" reqs/a.md 8)"; rc=$?
check "C1 meta pull failure exits 1" "$rc" 1
has "C2 names the abort" "$out" "aborted L8"
check "C3 clone removed" "$([ -e "$LR/L8" ] && echo present || echo absent)" absent
out="$(STUB_MODE_LINE='unknown no line' run lane-create "$RF" reqs/a.md 8)"; check "C4 unknown metadata mode fails closed" "$?" 1

# ---- D: hook merge never replaces an existing hooks key ---------------------------------------------
SF="$T/settings.json"
printf '{"model":"x","hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"keep-me"}]}],"Stop":[{"hooks":[]}]}}\n' > "$SF"
bash "$S" _merge-hooks "$SF" 'bash "/p/scripts/automate-lanes.sh" relay-hook'
bash "$S" _merge-hooks "$SF" 'bash "/p/scripts/automate-lanes.sh" relay-hook'
check "D1 existing hooks kept, relay entry added once" \
  "$(jq -c '[.model, (.hooks.PreToolUse | length), .hooks.PreToolUse[0].hooks[0].command, (.hooks.Stop | length), (.hooks.PermissionRequest | length)]' "$SF")" \
  '["x",2,"keep-me",1,1]'

# ---- E: init-check (AC12) ---------------------------------------------------------------------------
check "E1 --parallel 2 --auto-merge refused" "$(run init-check --parallel 2 --auto-merge)" "refuse: auto_merge_with_parallel"
run init-check --parallel 2 --auto-merge >/dev/null; check "E2 refusal exits 1" "$?" 1
check "E3 --parallel 1 --auto-merge refused (a single lane never runs the merge gate)" "$(run init-check --parallel 1 --auto-merge)" "refuse: auto_merge_with_parallel"
check "E4 --parallel 11 out of range" "$(run init-check --parallel 11)" "refuse: parallel_out_of_range"
check "E5 --parallel 0 out of range" "$(run init-check --parallel 0)" "refuse: parallel_out_of_range"
check "E6 --parallel 10 ok" "$(run init-check --parallel 10)" ok
# E7-E9 single-lane mode (twin-remediation/08b): N = 1 needs branch mode ON (setup-memory.sh mode through the
# SETUP_MEMORY seam); anything but `on <branch>` refuses (fail CLOSED); N > 1 never reads the mode.
out="$(STUB_MODE_LINE=off run init-check --parallel 1)"; rc=$?
check "E7 --parallel 1 with branch mode off ⇒ refuse: single_lane_requires_branch_mode (exit 1)" "$rc:$out" "1:refuse: single_lane_requires_branch_mode"
check "E7b … mode unknown ⇒ refused" "$(STUB_MODE_LINE='unknown no line' run init-check --parallel 1)" "refuse: single_lane_requires_branch_mode"
printf '#!/usr/bin/env bash\necho "mode-read $*" >> "$E_MODE_LOG"; exit 1\n' > "$T/mode-fail.sh"; printf '#!/usr/bin/env bash\nexit 0\n' > "$T/mode-empty.sh"
chmod +x "$T/mode-fail.sh" "$T/mode-empty.sh"; export E_MODE_LOG="$T/mode-read.log"; : > "$E_MODE_LOG"
check "E7c … a failing reader / an empty answer ⇒ refused" \
  "$(LOOMWRIGHT_LANES_SETUP_MEMORY="$T/mode-fail.sh" run init-check --parallel 1):$(LOOMWRIGHT_LANES_SETUP_MEMORY="$T/mode-empty.sh" run init-check --parallel 1)" \
  "refuse: single_lane_requires_branch_mode:refuse: single_lane_requires_branch_mode"
check "E7d … the reader got --root = this checkout's top level" "$(head -1 "$E_MODE_LOG")" "mode-read --root $(git rev-parse --show-toplevel 2>/dev/null || pwd) mode"
out="$(run init-check --parallel 1)"; rc=$?
check "E8 --parallel 1 with branch mode on <branch> ⇒ ok" "$rc:$out" "0:ok"
: > "$E_MODE_LOG"
check "E9 N > 1 makes NO mode read: outputs byte-identical to base, the loud stub never called" \
  "$(for a in '--parallel 2' '--parallel 10' '--parallel 2 --auto-merge' '--parallel 11'; do
       # shellcheck disable=SC2086
       LOOMWRIGHT_LANES_SETUP_MEMORY="$T/mode-fail.sh" run init-check $a; done | tr '\n' '|'):$(wc -l < "$E_MODE_LOG" | tr -d ' ')" \
  "ok|ok|refuse: auto_merge_with_parallel|refuse: parallel_out_of_range|:0"

# ---- F: launch authority, regime, host denial (AC Scope 17) -----------------------------------------
SUM_L1_BEFORE="$(lane_sum "$L1")"
n0="$(claude_calls)"
out="$(run lane-launch "$L1")"; rc=$?
check "F1 no owner command ⇒ exit 3" "$rc" 3
check "F2 BLOCKED first line" "$(printf '%s\n' "$out" | head -1)" "lane-launch: BLOCKED — L1 — no owner-invoked command — need the owner"
check "F3 no process started" "$(claude_calls)" "$n0"
check "F4 table blocked_launch" "$(tcol L1 8)" blocked_launch
out="$(STUB_NO_REGIME=1 run lane-launch "$L1" --owner-command '/automate --parallel 2')"; rc=$?
check "F5 no pinnable regime ⇒ exit 3" "$rc" 3
has "F6 regime BLOCKED line" "$(printf '%s\n' "$out" | head -1)" "lane-launch: BLOCKED — L1 — CLI advertises no pinnable permission regime"
out="$(run lane-launch "$L2" --host-denied 'auto-mode denied: Create Unsafe Agents')"; rc=$?
check "F7 host denial ⇒ exit 3" "$rc" 3
check "F8 host denial first line" "$(printf '%s\n' "$out" | head -1)" "lane-launch: BLOCKED — L2 — auto-mode denied: Create Unsafe Agents — need the owner"
check "F9 host denial blocked_launch, L1 row untouched by it" "$(tcol L2 8):$(tcol L1 10)" "blocked_launch:no pinnable permission regime"
check "F10 no process after either refusal" "$(claude_calls)" "$n0"

# ---- G: admission (AC10, launch-hold half) ----------------------------------------------------------
OWN='/automate --parallel 2'
out="$(STUB_LOAD=overloaded run lane-launch "$L1" --owner-command "$OWN")"; rc=$?
check "G1 overloaded ⇒ HELD exit 4" "$rc" 4
check "G2 overloaded first line" "$(printf '%s\n' "$out" | head -1)" "lane-launch: HELD — L1 — load overloaded"
check "G3 held_for_load in table" "$(tcol L1 8)" held_for_load
touch "$P/.supervisor/automate/$PARENT.memory-pressure"
out="$(run lane-launch "$L1" --owner-command "$OWN")"; rc=$?
check "G4 memory trip ⇒ HELD memory_pressure" "$rc:$(printf '%s\n' "$out" | head -1)" "4:lane-launch: HELD — L1 — memory_pressure"
rm -f "$P/.supervisor/automate/$PARENT.memory-pressure"
check "G5 no process while held" "$(claude_calls)" "$n0"
out="$(LOOMWRIGHT_MACHINE_LOAD_CMD="$T/absent-load.sh" CLAUDECODE=1 CLAUDE_PID=4242 LOOMWRIGHT_HOLDER_PID=4242 run lane-launch "$L1" --owner-command "$OWN")"; rc=$?
check "G6 unknown load admits" "$rc" 0
has "G7 launched line with session id" "$out" "launched L1"
check "G8 one process started" "$(claude_calls)" "$((n0 + 1))"
out="$(STUB_LOAD=busy run lane-launch "$L2" --owner-command "$OWN")"; rc=$?
check "G9 busy + a launch within the recheck ⇒ HELD" "$rc:$(printf '%s\n' "$out" | head -1)" "4:lane-launch: HELD — L2 — load busy"
out="$(STUB_LOAD=busy LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L2" --owner-command "$OWN")"; rc=$?
check "G10 busy past the recheck ⇒ launches (one per interval)" "$rc" 0
wait_gone "$L1"; wait_gone "$L2"

# ---- H: launch shape ----------------------------------------------------------------------------------
first="$(grep '^ARGS' "$STUB_LOG" | sed -n "$((n0 + 1))p")"
for f in "[-p]" "[--input-format] [stream-json]" "[--output-format] [stream-json]" "[--permission-prompt-tool] [stdio]" \
         "[--permission-mode] [acceptEdits]" "[--allowedTools] [Bash,Read,Edit,Write,Glob,Grep,Task,Agent,AskUserQuestion]" \
         "[--plugin-dir] [$(cd "$HERE/.." && pwd)]" "[--append-system-prompt] [You are running as a HEADLESS lane"; do
  has "H1 flag $f" "$first" "$f"
done
has "H2 disallow carries the merge command" "$first" "Bash(gh pr merge:*)"
has "H3 disallow carries force push" "$first" "Bash(git push --force:*)"
has "H4 disallow carries a push to the base branch" "$first" "Bash(git push origin main:*)"
has "H4b disallow carries the REST merge endpoint via gh api" "$first" "Bash(gh api *pulls/*/merge*)"
has "H4c disallow carries the GraphQL merge mutation via gh api" "$first" "Bash(gh api *mergePullRequest*)"
has "H4d disallow carries the GraphQL auto-merge mutation via gh api" "$first" "Bash(gh api *enablePullRequestAutoMerge*)"
hasnt "H4e gh api graphql itself is not blanket-denied" "$first" "Bash(gh api graphql"
hasnt "H5 no non-interactive fallback flag" "$first" "non-interactive"
has "H6 env: ceiling 0, CLAUDECODE and CLAUDE_PID unset" "$(grep '^ENV' "$STUB_LOG" | sed -n "$((n0 + 1))p")" "CEIL=0 CC=unset PID=unset"
check "H6b env: the coordinator's LOOMWRIGHT_HOLDER_PID (set on the launch) is unset for the lane" "$(grep '^HOLDERENV' "$STUB_LOG" | sed -n "$((n0 + 1))p")" "HOLDERENV unset"
has "H7 prompt = namespaced backlog command" "$(grep '^STDIN' "$STUB_LOG" | sed -n "$((n0 + 1))p")" "/loomwright:automate --backlog $L1/.supervisor/lane-backlog.md"
check "H8 runs inside the lane" "$(grep '^CWD' "$STUB_LOG" | sed -n "$((n0 + 1))p")" "CWD $L1"
check "H9 session id from system/init recorded" "$(tcol L1 7)" sess-123
case "$(tcol L1 5)" in [0-9]*) ok "H10 pid recorded" ;; *) bad "H10 pid recorded" ;; esac
[ -n "$(tcol L1 6)" ] && [ "$(tcol L1 6)" != "-" ] && ok "H11 pid start time recorded" || bad "H11 pid start time recorded"
check "H12 stream log outside the lane" "$(grep -c 'sess-123' "$LR/L1.stream.log" | tr -d ' ')" 2
out="$(run lane-launch "$L1" --owner-command "$OWN" --resume-run "$PARENT-L2")"; check "H13 resume of another lane's run refused" "$?" 1
mkdir -p "$L1/.supervisor/automate"; printf '# Automate Run: %s-L1 — reqs/a.md\n' "$PARENT" > "$L1/.supervisor/automate/$PARENT-L1.md"
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L1" --owner-command "/automate --resume $PARENT" --resume-run "$PARENT-L1")"
has "H14 resume by run id" "$(grep '^STDIN' "$STUB_LOG" | tail -1)" "/loomwright:automate --resume $PARENT-L1"
wait_gone "$L1"
rm -f "$L1/.supervisor/automate/$PARENT-L1.md"
# H15 — the vendor-neutral root arm (twin-remediation/11): with the harness variable unset (the suite
# unsets it above), a pre-set LOOMWRIGHT_ROOT is the plugin dir the lane is pinned to. H1 covers the
# other side: nothing pre-set ⇒ the location-derived root.
out="$(LOOMWRIGHT_ROOT="$T/neutral-root" LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L1" --owner-command "$OWN")"
has "H15 pre-set LOOMWRIGHT_ROOT pins --plugin-dir" "$(grep '^ARGS' "$STUB_LOG" | tail -1)" "[--plugin-dir] [$T/neutral-root]"
wait_gone "$L1"

# ---- I: coordinator never writes into a launched lane (checksum) + mutation control ------------------
check "I1 lane checksum unchanged across launches" "$(lane_sum "$L1")" "$SUM_L1_BEFORE"
MUT="$T/mut"; mkdir -p "$MUT"
awk '{ print } /# >>> spawn/ { print "  touch \"$LN_DIR/.coordinator-write\"" }' "$S" > "$MUT/automate-lanes.sh"
LOOMWRIGHT_LANE_RECHECK_S=0 bash "$MUT/automate-lanes.sh" lane-launch "$L1" --owner-command "$OWN" >/dev/null 2>&1
wait_gone "$L1"
if [ "$(lane_sum "$L1")" != "$SUM_L1_BEFORE" ]; then ok "I2 mutation (coordinator write after launch) fails the checksum"; else bad "I2 mutation control did not trip"; fi
rm -f "$L1/.coordinator-write"

# ---- J: relay hook (AC6) ----------------------------------------------------------------------------
Q2='[{"question":"Which color?","header":"Color","multiSelect":false,"options":[{"label":"Red","description":"r"},{"label":"Blue","description":"b"}]},{"question":"Which extras?","header":"Extras","multiSelect":true,"options":[{"label":"A","description":"a"},{"label":"B","description":"b"},{"label":"C","description":"c"}]}]'
hook_in() { jq -n -c --arg ev "$1" --arg cwd "$2" --arg id "$3" --argjson q "${4:-$Q2}" '{hook_event_name: $ev, cwd: $cwd, tool_use_id: $id, tool_name: "AskUserQuestion", tool_input: {questions: $q}}'; }
out="$(hook_in PermissionRequest "$L2" toolu_q1 | bash "$S" relay-hook)"
check "J1 bundled call denied" "$(jq -r '.hookSpecificOutput.decision.behavior' <<<"$out")" deny
out="$(hook_in PreToolUse "$L2" toolu_q1 | bash "$S" relay-hook)"
check "J2 unanswered question ⇒ defer" "$(jq -r '.hookSpecificOutput.permissionDecision' <<<"$out")" defer
J2_DEFER="$out"   # the pre-policy defer, byte for byte (AD5–AD9b compare against it)
QF="$L2/.supervisor/inbox/questions/toolu_q1.json"
check "J3 question file with asked_at" "$(jq -r '[.id, (.asked_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T.*Z$")), (.questions | length)] | map(tostring) | join(",")' "$QF")" "toolu_q1,true,2"
check "J4 outside a lane ⇒ no decision" "$(hook_in PreToolUse "$T" toolu_q9 | bash "$S" relay-hook)" "{}"
check "J5 path-unsafe id ignored" "$(hook_in PreToolUse "$L2" '../x' | bash "$S" relay-hook)" "{}"

# ---- K: lane-answer (AC6) ---------------------------------------------------------------------------
export STUB_DEFER_LINE="$(jq -n -c --argjson q "$Q2" '{type: "result", subtype: "success", stop_reason: "tool_deferred", session_id: "sess-123", deferred_tool_use: {id: "toolu_q1", name: "AskUserQuestion", input: {questions: $q}}}')"
STUB_MODE=defer LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L2" --owner-command "$OWN" >/dev/null; wait_gone "$L2"
AF="$L2/.supervisor/inbox/answers/toolu_q1.json"
ans() { printf '%s' "$1" | LOOMWRIGHT_LANE_RECHECK_S=0 bash "$S" lane-answer "$L2" toolu_q1 "${@:2}" 2>&1; }
out="$(ans '{"answers":{"0":"Green","1":"A"}}' --owner-command "$OWN")"; rc=$?
check "K1 unknown label refused" "$rc" 1; has "K1b names the bad label" "$out" '"Green" is not one of its options'
out="$(ans '{"note":"just do whatever"}' --owner-command "$OWN")"; check "K2 free-text-only refused" "$?" 1
out="$(ans '{"answers":{"0":"Red","1":"A,Z"}}' --owner-command "$OWN")"; check "K3 one unknown multiSelect label refuses all" "$?" 1
out="$(ans '{"answers":{"0":"Red"}}' --owner-command "$OWN")"; check "K4 missing an answer refused" "$?" 1
out="$(ans '{"answers":{"0":"Red","1":"A,B"}}')"; rc=$?
check "K5 answer without owner command ⇒ BLOCKED exit 3" "$rc" 3
check "K6 nothing recorded when blocked" "$([ -e "$AF" ] && echo written || echo none)" none
n1="$(claude_calls)"
out="$(ans '{"answers":{"0":"Red","1":"A,B"},"note":"prefer the small diff"}' --owner-command "$OWN" --via test)"; rc=$?
check "K7 valid multiSelect answer accepted" "$rc" 0
has "K8 reports the note as delivered" "$out" "note recorded and delivered"
check "K9 answer file" "$(jq -c '[.answers["Which color?"], .answers["Which extras?"], .note, .source, .via]' "$AF")" '["Red","A,B","prefer the small diff","human","test"]'
check "K10 resumed once" "$(claude_calls)" "$((n1 + 1))"
lastargs="$(grep '^ARGS' "$STUB_LOG" | tail -1)"
has "K11 resume carries --resume <session>" "$lastargs" "[--resume] [sess-123]"
has "K12 resume keeps the permission host" "$lastargs" "[--permission-prompt-tool] [stdio]"
has "K13 resume keeps the headless-lane prompt" "$lastargs" "[--append-system-prompt]"
has "K14 resume env ceiling 0" "$(grep '^ENV' "$STUB_LOG" | tail -1)" "CEIL=0 CC=unset PID=unset"
wait_gone "$L2"
out="$(hook_in PreToolUse "$L2" toolu_q1 | bash "$S" relay-hook)"
check "K15 hook on retry ⇒ allow with answers" "$(jq -r '.hookSpecificOutput.permissionDecision + "|" + .hookSpecificOutput.updatedInput.answers["Which extras?"]' <<<"$out")" "allow|A,B"
check "K16 note delivered as annotations" "$(jq -r '.hookSpecificOutput.updatedInput.annotations["Which color?"].notes' <<<"$out")" "prefer the small diff"
out="$(ans '{"answers":{"0":"Blue","1":"C"}}' --owner-command "$OWN")"; check "K17 second answer refused" "$?" 1

# ---- L: .died marker ----------------------------------------------------------------------------------
check "L1 clean exit leaves no .died marker" "$([ -e "$LR/L1.died" ] && echo yes || echo no)" no
STUB_MODE=die LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L1" --owner-command "$OWN" >/dev/null; wait_gone "$L1"
has "L2 exit with no terminal result ⇒ .died" "$(cat "$LR/L1.died" 2>/dev/null)" "died_at"

# ---- M: liveness helper + pick-guard (AC12) ---------------------------------------------------------
AD="$P/.supervisor/automate"
check "M1 pick-guard ok with no live lane" "$(run pick-guard "$AD")" ok
STUB_MODE=sleep LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L1" --owner-command "$OWN" >/dev/null
check "M2 pick-guard refuses a live lane" "$(run pick-guard "$AD")" "refuse: live_lane $PARENT-L1 L1"
run pick-guard "$AD" >/dev/null; check "M3 refusal exits 1" "$?" 1
out="$(run lane-launch "$L1" --owner-command "$OWN")"; check "M4 relaunch of a running lane refused" "$?" 1
sleep 300 & SPID=$!; BG_PIDS="$BG_PIDS $SPID"
SST="$(ps -o lstart= -p "$SPID")"
( . "$S"; lanes_proc_alive "$SPID" "$SST" "$L1" ); check "M5 recycled pid (other command line) is not alive" "$?" 1
( . "$S"; lanes_proc_alive "$(tcol L1 5)" "Mon Jan  1 00:00:00 2001" "$L1" ); check "M6 start-time mismatch is not alive" "$?" 1
( . "$S"; lanes_proc_alive "$(tcol L1 5)" "$(tcol L1 6)" "$L1" ); check "M7 recorded lane process is alive" "$?" 0
out="$(run lane-remove "$L1")"; rc=$?
check "M8 lane-remove refuses a live claude -p" "$rc" 1; has "M8b names the process" "$out" "live claude -p process"
LP="$(tcol L1 5)"
out="$(run lane-remove "$L1" --stop)"; rc=$?
check "M9 --stop TERMs then removes" "$rc" 0; has "M9b reports the stop" "$out" "stopped claude -p (pid $LP)"
check "M10 process gone after --stop" "$(kill -0 "$LP" 2>/dev/null && echo alive || echo dead)" dead
check "M11 lane dir removed, state removed" "$([ -e "$L1" ] && echo present || echo absent):$(tcol L1 8)" "absent:removed"
check "M12 pick-guard ok after the lane stopped (lock-independent)" "$(run pick-guard "$AD")" ok
mkdir -p "$L2/.supervisor/inbox/questions"; echo '{}' > "$L2/.supervisor/inbox/questions/toolu_q2.json"
check "M13 pick-guard refuses a lane holding an unanswered question" "$(run pick-guard "$AD")" "refuse: live_lane $PARENT-L2 L2"

# ---- N: lane-remove refusals (AC3) + mutation controls (AC16) ---------------------------------------
out="$(run lane-remove "$L2")"; rc=$?
check "N1 awaiting_input refused" "$rc" 1; has "N1b names the question" "$out" "awaiting_input — unanswered question toolu_q2"
awk '/# >>> awaiting-input check/ { skip = 1 } !skip { print } /# <<< awaiting-input check/ { skip = 0 }' "$S" > "$MUT/automate-lanes.sh"
out="$(bash "$MUT/automate-lanes.sh" lane-remove "$L2" 2>&1)"
hasnt "N2 mutation (awaiting_input check deleted) no longer refuses" "$out" "awaiting_input"
rm -rf "$L2"
# live-process mutation on a fresh lane
run lane-create "$RF" reqs/a.md 3 >/dev/null; L3="$LR/L3"
STUB_MODE=sleep LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L3" --owner-command "$OWN" >/dev/null
L3P="$(tcol L3 5)"
awk '/# >>> live-process check/ { skip = 1 } !skip { print } /# <<< live-process check/ { skip = 0 }' "$S" > "$MUT/automate-lanes.sh"
out="$(bash "$MUT/automate-lanes.sh" lane-remove "$L3" 2>&1)"
hasnt "N3 mutation (live-process check deleted) no longer refuses" "$out" "live claude -p"
kill -TERM "$L3P" 2>/dev/null; wait_gone "$L3"
# the remaining refusals, on one lane, each condition set then cleared
run lane-create "$RF" reqs/b.md 4 >/dev/null; L4="$LR/L4"
echo dirty >> "$L4/reqs/b.md"
out="$(run lane-remove "$L4")"; check "N4 dirty tree refused" "$?:$(printf '%s' "$out" | grep -c 'dirty working tree' | tr -d ' ')" "1:1"
git -C "$L4" checkout -q -- reqs/b.md
touch "$L4/.supervisor/automate/$PARENT-L4.meta-push-failed"
out="$(run lane-remove "$L4")"; has "N5 meta-push failure marker refused" "$out" "meta-push failure marker"
rm -f "$L4/.supervisor/automate/$PARENT-L4.meta-push-failed"
out="$(STUB_META_STATUS='local_ahead 2' run lane-remove "$L4")"; has "N6 unpushed metadata refused" "$out" "metadata not pushed (local_ahead 2)"
has "N6b meta status passes --branch" "$(cat "$META_LOG")" "meta-sync status --branch test-meta --root $L4"
# N6c-N6f the `status --paths` naming cap (_lanes_status_named): at most five paths, then `+<k> more`;
# exactly five reads no `more`; a control with the cap removed lists all seven (N6c's line fails).
N6P7="$(printf 'local_ahead 7\n  a.md\n  b.md\n  c.md\n  d.md\n  e.md\n  f.md\n  g.md')"
out="$(STUB_META_STATUS="$N6P7" run lane-remove "$L4")"
check "N6c seven unpushed paths: five named, then +2 more" "$(printf '%s\n' "$out" | grep 'metadata not pushed' | sed 's/^.* — metadata/metadata/')" \
  "metadata not pushed (local_ahead 7) — paths: a.md, b.md, c.md, d.md, e.md, +2 more"
out="$(STUB_META_STATUS="$(printf 'local_ahead 5\n  a.md\n  b.md\n  c.md\n  d.md\n  e.md')" run lane-remove "$L4")"
check "N6d exactly five paths: all named, no +k more" "$(printf '%s\n' "$out" | grep 'metadata not pushed' | sed 's/^.* — metadata/metadata/')" \
  "metadata not pushed (local_ahead 5) — paths: a.md, b.md, c.md, d.md, e.md"
sed "s/sed 's\/^  \/\/' | head -5 /sed 's\/^  \/\/' /" "$S" > "$MUT/automate-lanes.sh"
check "N6e mutation removed the five-path cap" "$(grep -c "sed 's/^  //' | head -5 " "$MUT/automate-lanes.sh" | tr -d ' ')" 0
out="$(STUB_META_STATUS="$N6P7" bash "$MUT/automate-lanes.sh" lane-remove "$L4" 2>&1)"
has "N6f mutation: without the cap all seven are listed (N6c's expected line would fail)" "$out" "paths: a.md, b.md, c.md, d.md, e.md, f.md, g.md, +2 more"
git -C "$L4" checkout -q -b feature/x; echo y > "$L4/reqs/y.md"; git -C "$L4" add reqs/y.md; git -C "$L4" commit -qm y
out="$(run lane-remove "$L4")"; has "N7 unpushed commits refused" "$out" "branch feature/x has 1 commit(s) not on origin"
git -C "$L4" checkout -q main; git -C "$L4" branch -q -D feature/x
cat > "$T/automate-merge-watch.sh" <<'EOF'
#!/usr/bin/env bash
trap 'kill $! 2>/dev/null; exit 0' TERM; sleep 300 & wait $!
EOF
bash "$T/automate-merge-watch.sh" rf item https://github.com/o/r/pull/9 & WPID=$!; BG_PIDS="$BG_PIDS $WPID"
# Wait until the watcher's own command line is visible to ps (lane-remove's _lanes_live_watchers
# matches it) — a fixed sleep raced the exec under load (iq02 T07).
_n8_up() { case "$(ps -o command= -p "$WPID" 2>/dev/null)" in *automate-merge-watch*pull/9*) return 0 ;; esac; return 1; }
wait_for_cmd 15 _n8_up || bad "N8 setup: the merge-watch stub (pid $WPID) never showed its command line in ps" "within 15 s"
printf 'pid\t%s\npr_url\thttps://github.com/o/r/pull/9\nstarted\tx\n' "$WPID" > "$L4/.supervisor/automate/$PARENT-L4.merge-watch"
out="$(run lane-remove "$L4")"; has "N8 live merge watcher refused" "$out" "live merge watcher (pid $WPID"
printf 'pid\t%s\npr_url\thttps://github.com/o/r/pull/77\n' "$WPID" > "$L4/.supervisor/automate/$PARENT-L4.merge-watch"
awk -F'\t' -v OFS='\t' '$1 == "L4" { $8 = "gone" } { print }' "$TABLE" > "$TABLE.t" && mv "$TABLE.t" "$TABLE"
out="$(run lane-remove "$L4")"; rc=$?
hasnt "N9 watcher marker with another pr_url (recycled) is not a refusal" "$out" "merge watcher"
check "N10 gone without --abandon refused" "$rc:$(printf '%s' "$out" | grep -c 'gone' | tr -d ' ')" "1:1"
out="$(run lane-remove "$L4" --abandon)"; rc=$?
check "N11 --abandon removes" "$rc:$([ -e "$L4" ] && echo present || echo absent):$(tcol L4 8)" "0:absent:abandoned"
has "N12 --abandon logs one Progress line" "$(cat "$HELPERS_LOG")" "progress-append $RF lane abandoned: L4"
check "N13 salvage kept the lane's .supervisor" "$(ls -d "$LR"/salvage/L4-removed-*/supervisor 2>/dev/null | wc -l | tr -d ' ')" 1
check "N14 the merge watcher process was left alone" "$(kill -0 "$WPID" 2>/dev/null && echo alive || echo dead)" alive
# recycled claude pid: a live unrelated process recorded as the lane pid does not block removal
run lane-create "$RF" reqs/a.md 5 >/dev/null; L5="$LR/L5"
awk -F'\t' -v OFS='\t' -v p="$SPID" -v s="$(printf '%s' "$SST" | tr -s ' ' | sed 's/^ //')" '$1 == "L5" { $5 = p; $6 = s } { print }' "$TABLE" > "$TABLE.t" && mv "$TABLE.t" "$TABLE"
out="$(run lane-remove "$L5")"; check "N15 recycled pid is not a refusal (lane removed)" "$?:$([ -e "$L5" ] && echo present || echo absent)" "0:absent"

# ---- O: lane-info -----------------------------------------------------------------------------------
run lane-create "$RF" reqs/a.md 6 >/dev/null; L6="$LR/L6"
check "O1 lane-info in a lane prints lane.json" "$(run lane-info --root "$L6" | jq -r .run_id)" "$PARENT-L6"
check "O2 lane-info from cwd" "$(cd "$L6" && bash "$S" lane-info | jq -r .lane)" L6
run lane-info --root "$P" >/dev/null; check "O3 lane-info outside a lane exits 1" "$?" 1

# ---- P: branch-check (Scope 14 remote branch name) ----------------------------------------------------
check "P1 free name kept" "$(run branch-check "$L6" feature/new)" feature/new
git -C "$P" push -q origin main:refs/heads/feature/taken 2>/dev/null
check "P2 remote-only hit ⇒ suffixed" "$(run branch-check "$L6" feature/taken)" feature/taken-L6
git -C "$P" push -q origin main:refs/heads/feature/taken-L6 2>/dev/null
out="$(run branch-check "$L6" feature/taken)"; check "P3 both taken ⇒ refused" "$?:$out" "1:refuse: remote_branch_exists feature/taken"

# ---- Q: lane-status classification (AC7) ---------------------------------------------------------------
PARENT2=automate-2026-10-07-130000; RF2="$P/.supervisor/automate/$PARENT2.md"
TABLE2="$P/.supervisor/automate/$PARENT2.lanes"; LR2="$T/work/primary-lanes/$PARENT2"
printf '# Automate Run: %s\n\n## Progress\n' "$PARENT2" > "$RF2"
for n in 1 2 3 4 5 6 7; do run lane-create "$RF2" reqs/a.md "$n" --parallel 8 >/dev/null; done
t2set() { awk -F'\t' -v OFS='\t' -v l="$1" -v c="$2" -v v="$3" '$1 == l { $c = v } { print }' "$TABLE2" > "$TABLE2.t" && mv "$TABLE2.t" "$TABLE2"; }
cat > "$T/pgrep-stub" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *caffeinate*) [ -n "${STUB_CAFF_HELD:-}" ] && { echo 777; exit 0; }; exit 1 ;;
  *) exit 1 ;;
esac
EOF
cat > "$T/ci-stub.sh" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = status ] && [ -n "${STUB_CI_JSON:-}" ] && printf '%s\n' "$STUB_CI_JSON"; exit 0
EOF
cat > "$T/caff-stub" <<'EOF'
#!/usr/bin/env bash
echo "caffeinate $*" >> "$CAFF_LOG"
EOF
chmod +x "$T/pgrep-stub" "$T/ci-stub.sh" "$T/caff-stub"
export LOOMWRIGHT_LANES_PGREP="$T/pgrep-stub" LOOMWRIGHT_LANES_CI_SLOT="$T/ci-stub.sh"
export LOOMWRIGHT_LANES_CAFFEINATE="$T/caff-stub" CAFF_LOG="$T/caff.log" LOOMWRIGHT_LANES_BOOT_EPOCH=1000000000
export LOOMWRIGHT_LANES_UNAME=Darwin LOOMWRIGHT_LANES_COORDINATOR_PID=4242
# pmset stub: prints $PMSET_OUT's content (none by default), so the real Mac's power assertions — the
# Claude desktop app holds one while it works — never leak into keep_awake.
printf '%s\n' '#!/usr/bin/env bash' '[ "$*" = "-g assertions" ] && [ -s "${PMSET_OUT:-}" ] && cat "$PMSET_OUT"; exit 0' > "$T/pmset-stub"
chmod +x "$T/pmset-stub"; export LOOMWRIGHT_LANES_PMSET="$T/pmset-stub" PMSET_OUT="$T/pmset.out"
: > "$CAFF_LOG"; : > "$PMSET_OUT"
sj() { bash "$S" lane-status "$RF2" --json 2>/dev/null; }
lf() { jq -r --arg l "$1" ".lanes[] | select(.lane == \$l) | $2" <<<"$J"; }
STUB_MODE=sleep LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$LR2/L1" --owner-command "$OWN" >/dev/null
STUB_MODE=sleep LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$LR2/L2" --owner-command "$OWN" >/dev/null
t2set L3 8 launched; t2set L3 5 99999998; t2set L3 6 "Mon Jan  1 00:00:00 2001"; t2set L3 9 "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
run lane-launch "$LR2/L4" --host-denied 'auto-mode classifier denied the spawn' >/dev/null
STUB_LOAD=overloaded run lane-launch "$LR2/L5" --owner-command "$OWN" >/dev/null
J="$(sj)"; rc=$?
check "Q1 lane-status --json exits 0 and parses" "$rc:$(jq -r '.lanes | length' <<<"$J")" "0:7"
check "Q2 launched lane is running" "$(lf L1 .state)" running
check "Q3 process gone, not parked, no question ⇒ stalled" "$(lf L3 .state)" stalled
check "Q4 host-denied spawn ⇒ blocked_launch with the reason" "$(lf L4 '.state + "|" + .reason')" "blocked_launch|auto-mode classifier denied the spawn"
check "Q5 HELD launch ⇒ held_for_load" "$(lf L5 '.state + "|" + .held_for_load')" "held_for_load|load overloaded"
check "Q6 never-launched lane ⇒ created" "$(lf L7 .state)" created
J="$(LOOMWRIGHT_LANES_BOOT_EPOCH="$(( $(date -u +%s) + 60 ))" sj)"
check "Q7 boot later than the last launch ⇒ lost_to_reset" "$(lf L3 .state)" lost_to_reset
has "Q7b lost_to_reset names the resume by run id" "$(lf L3 .reason)" "--resume-run $PARENT2-L3"
L1P="$(awk -F'\t' '$1 == "L1" { print $5 }' "$TABLE2")"; L1C="$(pgrep -P "$L1P" 2>/dev/null | head -1)"
kill -TERM "$L1C" 2>/dev/null; wait_gone "$LR2/L1"
J="$(sj)"
check "Q8 killed lane (no terminal result) ⇒ died" "$(lf L1 .state)" died
check "Q9 the other lane is unchanged (running)" "$(lf L2 .state)" running
out="$(run lane-status "$RF2")"
has "Q10 plain view: one line per lane with state and item" "$out" "L4  blocked_launch (auto-mode classifier denied the spawn)  item=reqs/a.md"
has "Q10b plain view shows held for load" "$out" "held for load: load overloaded"
check "Q11 liveness is not redefined (one lanes_proc_alive)" "$(grep -c '^lanes_proc_alive()' "$S")" 1
out="$(run lane-status "$P/.supervisor/automate/none.md" --json)"; rc=$?
check "Q12 no lane table ⇒ empty lanes, exit 0" "$rc:$(jq -r '.lanes | length' <<<"$out")" "0:0"

# ---- R: lane-status --json fields (AC8: machine, asked_at / waiting_s, last_message, CI slot) -----------
L6="$LR2/L6"; t2set L6 8 launched; t2set L6 9 "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '{"id":"toolu_r1","asked_at":"2026-10-07T00:00:00Z","questions":[{"question":"Which path?","header":"Path","options":[{"label":"A","description":"the first"},{"description":"no label: dropped"}]},{"question":"Which checks?","multiSelect":true,"options":[{"label":"x, y"},{"label":"z"}]}]}\n' > "$L6/.supervisor/inbox/questions/toolu_r1.json"
LONG="$(printf 'x%.0s' $(seq 1 400))"
{ echo '{"type":"system","subtype":"init","session_id":"sess-r"}'
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"first words"}]}}\n'
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"line one\\nline two %s"}]}}\n' "$LONG"
  echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Task","input":{"subagent_type":"loomwright:worker","description":"implement subtask 1"}}]}}'
  echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"bash automate-helpers.sh current-set rf --pause ready_for_release"}}]}}'
  echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"AskUserQuestion","input":{"questions":[{"question":"Which path?"}]}}]}}'
  echo '{"type":"result","subtype":"success","stop_reason":"tool_deferred","deferred_tool_use":{"id":"toolu_r1"},"session_id":"sess-r"}'
} > "$LR2/L6.stream.log"
J="$(LOOMWRIGHT_MACHINE_LOAD_CMD="$T/absent-load.sh" sj)"; rc=$?
check "R1 machine-load absent ⇒ machine.state unknown, exit 0" "$rc:$(jq -r .machine.state <<<"$J")" "0:unknown"
check "R2 pending question ⇒ awaiting_input" "$(lf L6 .state)" awaiting_input
check "R3 asked_at echoed" "$(lf L6 '.questions[0].asked_at')" "2026-10-07T00:00:00Z"
W1="$(lf L6 '.questions[0].waiting_s')"
check "R4 waiting_s computed at read time" "$([ "$W1" -ge $(( $(date -u +%s) - $(jq -n '"2026-10-07T00:00:00Z" | fromdateiso8601') - 5 )) ] && echo yes)" yes
sleep 1; J="$(sj)"; W2="$(lf L6 '.questions[0].waiting_s')"
check "R5 waiting_s grows" "$([ "$W2" -gt "$W1" ] && echo yes)" yes
LM="$(lf L6 .last_message)"
check "R6 last_message is the last assistant text, trimmed to 300" "${#LM}:$(printf '%s' "$LM" | head -c 17)" "300:line one line two"
hasnt "R7 last_message is never a tool-use line" "$LM" "AskUserQuestion"
check "R8 last 3 actions" "$(lf L6 '.last_actions | length'):$(lf L6 '.last_actions[2]')" "3:AskUserQuestion"
check "R9 machine from machine-load.sh" "$(jq -r '.machine | "\(.state) \(.load1) \(.cpus) \(.keep_awake)"' <<<"$J")" "ok 1 8 not held"
J="$(STUB_CI_JSON="{\"holders\":[{\"checkout\":\"$T/elsewhere\"}],\"waiters\":[{\"checkout\":\"$T/other\",\"held\":null},{\"checkout\":\"$LR2/L2\",\"held\":\"machine busy\"}]}" sj)"
check "R10 CI-slot queue position" "$(lf L2 '.ci_slot.state + " " + (.ci_slot.position | tostring)')" "waiting 2"
check "R11 a running lane held by machine admission ⇒ held for load" "$(lf L2 .held_for_load)" "machine busy"
check "R12 no CI slot record ⇒ ci_slot none" "$(lf L6 .ci_slot.state)" none
# items (parallel-automate/14): every question of the call, in answer-key order, with exactly the labels
# lane-answer accepts — what a client draws its option buttons from without reading the lane's files.
check "R13 items: one per question, in order" "$(lf L6 '.questions[0].items | map(.question) | join("|")')" "Which path?|Which checks?"
check "R14 items carry header, multiSelect and descriptions" \
  "$(lf L6 '.questions[0].items | map("\(.header)/\(.multiSelect)/\(.options | map(.label + "=" + (.description // "-")) | join(","))") | join(" ; ")')" \
  "Path/false/A=the first ; null/true/x, y=-,z=-"
check "R15 question (first text) kept beside items" "$(lf L6 '.questions[0].question')" "Which path?"
check "R16 no ## Current branch ⇒ branch null" "$(lf L6 '.branch')" null

# ---- S: keep-awake (suggest, never silently start) --------------------------------------------------
out="$(run lane-status "$RF2")"
has "S1 macOS: one-line caffeinate suggestion with the coordinator pid" "$out" "caffeinate -i -w 4242"
has "S2 keep-awake: not held" "$out" "keep-awake: not held"
check "S3 no keep-awake process started without --keep-awake" "$(wc -l < "$CAFF_LOG" | tr -d ' ')" 0
hasnt "S4 other OS: no suggestion" "$(LOOMWRIGHT_LANES_UNAME=Linux run lane-status "$RF2")" "caffeinate -i -w"
out="$(STUB_CAFF_HELD=1 run lane-status "$RF2")"
check "S5 holder seen ⇒ held, no suggestion" "$(printf '%s' "$out" | grep -c 'keep-awake: held'):$(printf '%s' "$out" | grep -c 'suggestion')" "1:0"
out="$(run lane-status "$RF2" --keep-awake)"
# The stub is started in the background: wait for its write, never a fixed sleep (the S6 flake, iq02 T07).
wait_for_file_content "$CAFF_LOG" "caffeinate -i -w 4242" 15 \
  || bad "S6 wait: '$CAFF_LOG' never received 'caffeinate -i -w 4242'" "within 15 s"
has "S6 --keep-awake starts it, tied to the coordinator" "$(cat "$CAFF_LOG")" "caffeinate -i -w 4242"
# S6 controls: a stub that writes 0.5 s late still passes (the old 0.3 s sleep lost this race every
# time); a stub that never writes makes the wait FAIL, naming the condition.
printf '%s\n' '#!/usr/bin/env bash' 'sleep 0.5   # fixed-sleep-ok: the delayed-writer fixture itself' 'echo "caffeinate $*" >> "$CAFF_LOG"' > "$T/caff-slow"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$T/caff-mute"
chmod +x "$T/caff-slow" "$T/caff-mute"
: > "$CAFF_LOG"; LOOMWRIGHT_LANES_CAFFEINATE="$T/caff-slow" run lane-status "$RF2" --keep-awake >/dev/null
if wait_for_file_content "$CAFF_LOG" "caffeinate -i -w 4242" 15; then ok "S6c a 0.5 s-late keep-awake write is still seen"
else bad "S6c delayed stub" "the wait missed a write that arrived 0.5 s late"; fi
: > "$CAFF_LOG"; LOOMWRIGHT_LANES_CAFFEINATE="$T/caff-mute" run lane-status "$RF2" --keep-awake >/dev/null
werr="$(wait_for_file_content "$CAFF_LOG" "caffeinate -i -w 4242" 1 2>&1)"; wrc=$?
check "S6d a stub that never writes ⇒ the wait fails, naming the condition" "$wrc:$(case "$werr" in *"waiting for: 'caffeinate -i -w 4242' in $CAFF_LOG"*) echo named ;; esac)" "1:named"
has "S6b and says so" "$out" "keep-awake: started (opt-in --keep-awake)"
# S7-S11: keep-awake is read from macOS power assertions, not only a `caffeinate` process. The desktop
# app's "Keep computer awake while Claude works" hold is a NoIdleSleepAssertion owned by `Claude` — the
# machine IS held, but only while a Code session works (headless lanes are not Code sessions), so the
# caffeinate suggestion stays and --keep-awake still starts one.
pm_line() { printf '   pid %s(%s): [0x0006137400018c52] 01:11:43 %s named: "%s"  \n' "$@"; }
{ echo 'Listed by owning process:'; pm_line 39844 Claude NoIdleSleepAssertion Electron
  pm_line 341 powerd PreventUserIdleSystemSleep 'Powerd - Prevent sleep while display is on'; } > "$PMSET_OUT"
J="$(sj)"
check "S7 Claude app assertion ⇒ held, not lasting, one claude-app holder (powerd's own hold ignored)" \
  "$(jq -r '.machine | "\(.keep_awake)|\(.keep_awake_lasting)|\([.keep_awake_holders[] | .process + ":" + .kind] | join(","))"' <<<"$J")" \
  "held|false|Claude:claude-app"
out="$(run lane-status "$RF2")"
has "S8 plain view names the app hold and its limit" "$out" "keep-awake: held (Claude app — only while a Code session works)"
has "S8b the app hold alone keeps the caffeinate suggestion" "$out" "keep-awake suggestion (run it yourself, or lane-status --keep-awake): caffeinate -i -w 4242"
: > "$CAFF_LOG"; out="$(run lane-status "$RF2" --keep-awake)"
wait_for_file_content "$CAFF_LOG" "caffeinate -i -w 4242" 15 || bad "S9 wait" "no caffeinate start with only the app hold"
has "S9 --keep-awake still starts caffeinate when only the app holds" "$(cat "$CAFF_LOG")" "caffeinate -i -w 4242"
pm_line 777 caffeinate PreventUserIdleSystemSleep 'caffeinate command-line tool' >> "$PMSET_OUT"
J="$(sj)"; out="$(run lane-status "$RF2")"
check "S10 a caffeinate assertion ⇒ lasting, no suggestion" \
  "$(jq -r .machine.keep_awake_lasting <<<"$J"):$(printf '%s' "$out" | grep -c 'suggestion')" "true:0"
: > "$CAFF_LOG"; out="$(run lane-status "$RF2" --keep-awake)"
check "S10b --keep-awake with a caffeinate already holding starts none" "$(wc -l < "$CAFF_LOG" | tr -d ' '):$(printf '%s' "$out" | grep -c 'already held')" "0:1"
{ echo 'Listed by owning process:'; pm_line 639 sharingd PreventUserIdleSystemSleep Handoff; } > "$PMSET_OUT"
J="$(sj)"
check "S11 a transient daemon assertion is listed but never makes it held" \
  "$(jq -r '.machine | "\(.keep_awake)|\(.keep_awake_holders | length)|\(.keep_awake_holders[0].kind)"' <<<"$J")" "not held|1|other"
: > "$PMSET_OUT"; : > "$CAFF_LOG"

# ---- T: --watch, lane-feed ----------------------------------------------------------------------------
out="$(LOOMWRIGHT_LANES_WATCH_ITERATIONS=1 run lane-status "$RF2" --watch)"; rc=$?
check "T1 --watch one iteration exits 0" "$rc" 0
has "T1b frame header" "$out" "lane-status --watch"
has "T1c frame carries the fleet" "$out" "L6  awaiting_input"
out="$(LOOMWRIGHT_LANES_WATCH_ITERATIONS=2 LOOMWRIGHT_LANES_WATCH_INTERVAL_S=0 run lane-status "$RF2" --watch)"
check "T2 --watch refreshes" "$(printf '%s\n' "$out" | grep -c '^lane-status --watch')" 2

# ---- AH: lane-wait — the coordinator's lane watcher (a question no longer sits unseen) ---------------------
# Fleet at this point: L1 died · L2 running · L3 stalled · L4 blocked_launch · L5 held_for_load ·
# L6 awaiting_input (toolu_r1) · L7 created.
LWS="$P/.supervisor/automate/$PARENT2.lane-wait-seen"; rm -f "$LWS"
out="$(run lane-wait "$RF2" --interval 1 --timeout 5)"; rc=$?
check "AH1 a pending question ⇒ exits 0 at once" "$rc" 0
has "AH1b the question is named with lane, id and text" "$out" "lane-wait: question L6 toolu_r1 asked 2026-10-07T00:00:00Z — Which path?"
has "AH1c a died lane is an event" "$out" "lane-wait: state L1 died — pr -"
has "AH1d a stalled lane is an event" "$out" "lane-wait: state L3 stalled"
has "AH1e a blocked launch is an event" "$out" "lane-wait: state L4 blocked_launch"
hasnt "AH1f awaiting_input with its question is reported once, as the question" "$out" "state L6 awaiting_input"
hasnt "AH1g running / held / created lanes are not events" "$out" "state L2"
has "AH1h ends with the relay hint" "$(printf '%s\n' "$out" | tail -1)" "lane-wait: relay — show each question to the owner verbatim"
has "AH1i a mixed batch also carries the state act hint" "$out" "lane-wait: act — handle each state line"
check "AH2 the seen ledger records every printed key" "$(sort "$LWS" | tr '\n' ',')" "question L6 toolu_r1,state L1 died,state L3 stalled,state L4 blocked_launch,"
# AH16 the Stop hook's classifier (_lanes_quick_state: no gh, no ci-slot, no stream log) names the same
# state as lane-status for every live / attention state; the states past awaiting_input read `other`.
ah16_full="$(bash "$S" lane-status "$RF2" --json 2>/dev/null | jq -r '.lanes[] | "\(.lane) \(.state)"' \
  | awk '{ s = $2; if (s !~ /^(answer_pending|blocked_launch|held_for_load|created|missing|running|awaiting_input)$/) s = "other"; print $1, s }')"
ah16_quick="$( ( . "$S"; while IFS="$(printf '\t')" read -r l p _ _ pid st _ ts _; do
  case "$l" in L[0-9]|L[0-9][0-9]) ;; *) continue ;; esac
  printf '%s %s\n' "$l" "$(_lanes_quick_state "$p" "$pid" "$st" "$ts" "$P/.supervisor/automate/$PARENT2.$l.answer-pending.json")"
done < "$TABLE2" ) )"
check "AH16 fixture: the fleet spans live, attention and other states" \
  "$(printf '%s\n' "$ah16_full" | awk '{ print $2 }' | sort -u | tr '\n' ' ')" "awaiting_input blocked_launch created held_for_load other running "
check "AH16a _lanes_quick_state agrees with lane-status lane by lane" "$ah16_quick" "$ah16_full"
echo "state L2 died" >> "$LWS"
out="$(run lane-wait "$RF2" --interval 1 --timeout 1)"; rc=$?
check "AH3 nothing new ⇒ waits, then times out (exit 0)" "$rc:$out" "0:lane-wait: timeout after 1s — nothing new"
check "AH3b a state key no longer true is pruned (re-entry reports again); questions are kept" \
  "$(grep -c '^state L2 died$' "$LWS"):$(grep -c '^question L6 toolu_r1$' "$LWS")" "0:1"
printf '{"id":"toolu_r2","asked_at":"2026-10-07T00:05:00Z","questions":[{"question":"Second ask?","options":[{"label":"A"}]}]}\n' > "$L6/.supervisor/inbox/questions/toolu_r2.json"
out="$(run lane-wait "$RF2" --interval 1 --timeout 5)"
check "AH4 a new question only ⇒ exactly that one event + the hint" "$(printf '%s\n' "$out" | grep -c '^lane-wait: ')" 2
has "AH4b … and it is the new id" "$out" "lane-wait: question L6 toolu_r2 asked 2026-10-07T00:05:00Z — Second ask?"
hasnt "AH4c a question-only batch carries no state act hint" "$out" "lane-wait: act"
rm -f "$L6/.supervisor/inbox/questions/toolu_r2.json"
out="$(run lane-wait)"; rc=$?
check "AH5 no run file ⇒ usage, exit 2" "$rc" 2
out="$(run lane-wait "$RF2" --interval 0)"; rc=$?
check "AH5b a zero interval is refused (never a busy loop)" "$rc" 2
out="$(run lane-wait "$P/.supervisor/automate/none.md")"; rc=$?
check "AH6 no lane table ⇒ idle, exit 0" "$rc" 0
has "AH6b … and says idle" "$out" "lane-wait: idle — no lane table"
out="$(bash "$HERE/automate-helpers.sh" lane-wait "$P/.supervisor/automate/none.md" 2>&1)"; rc=$?
check "AH6c dispatched through automate-helpers.sh" "$rc:$out" "0:lane-wait: idle — no lane table for $P/.supervisor/automate/none.md (nothing to watch)"
check "AH7 --help lists lane-wait" "$(bash "$S" --help | grep -c '^#   lane-wait <parent_runfile>' | tr -d ' ')" 1
# AH8 idle: a fleet with no live lane and nothing new must exit, never poll parked lanes forever.
PARENT3=automate-2026-10-07-140000; RF3="$P/.supervisor/automate/$PARENT3.md"
printf '# Automate Run: %s\n\n## Progress\n' "$PARENT3" > "$RF3"
run lane-create "$RF3" reqs/a.md 1 --parallel 2 >/dev/null
# AH10 the ledger's ONLY key is a state no longer true (L1 is `created`: live, not an event). With nothing
# new and nothing kept, the poll must still prune it — else the re-entered state is never reported again.
LWS3="$P/.supervisor/automate/$PARENT3.lane-wait-seen"; echo "state L1 blocked_launch" > "$LWS3"
out="$(run lane-wait "$RF3" --interval 1 --timeout 1)"; rc=$?
check "AH10 a lone stale key, one live lane, nothing new ⇒ times out" "$rc:$out" "0:lane-wait: timeout after 1s — nothing new"
check "AH10b … and that lone stale state key is pruned (ledger removed)" "$([ -e "$LWS3" ] && cat "$LWS3" || echo absent)" absent
run lane-launch "$T/work/primary-lanes/$PARENT3/L1" --host-denied 'denied' >/dev/null
out="$(run lane-wait "$RF3" --interval 1 --timeout 5)"
has "AH8a first call reports the blocked lane (AH10c: the re-entered state reports again)" "$out" "lane-wait: state L1 blocked_launch"
# AH11 the hint follows the events: a state-only batch says act-on-the-lane, never the question relay.
has "AH11a a state-only batch ends with the act hint" "$(printf '%s\n' "$out" | tail -1)" "lane-wait: act — handle each state line per the automate-loop skill §14"
hasnt "AH11b … and carries no question relay hint" "$out" "lane-wait: relay"
out="$(run lane-wait "$RF3" --interval 1 --timeout 5)"; rc=$?
check "AH8b nothing live, nothing new ⇒ idle at once, exit 0" "$rc:$out" "0:lane-wait: idle — no lane is running; nothing changes until the owner acts"
# AH9 read-only toward lanes: a full lane-wait pass writes nothing but its own ledger.
before="$(find "$LR2" -type f -newer "$LWS" 2>/dev/null | wc -l | tr -d ' ')"
run lane-wait "$RF2" --interval 1 --timeout 1 >/dev/null
check "AH9 lane-wait writes nothing into any lane" "$(find "$LR2" -type f -newer "$LWS" 2>/dev/null | wc -l | tr -d ' ')" "$before"
# AH13 events are every state that is neither live nor quiet (a deny-list): `_lanes_parked` reports ANY
# run-file pause_reason as the lane's state, so a park the old allow-list never named (token_ceiling) must
# wake the coordinator, while a coordinator-driven park (awaiting_merge) must not. L1 (blocked_launch) was
# already reported above and stays in the ledger.
for n in 2 3; do run lane-create "$RF3" reqs/a.md "$n" --parallel 4 >/dev/null; done
TABLE3="$P/.supervisor/automate/$PARENT3.lanes"
t3set() { awk -F'\t' -v OFS='\t' -v l="$1" -v c="$2" -v v="$3" '$1 == l { $c = v } { print }' "$TABLE3" > "$TABLE3.t" && mv "$TABLE3.t" "$TABLE3"; }
ah_park() { # <lane> <status> <pause_reason> — a launched-then-exited lane whose run file is parked as given
  local d r; d="$(awk -F'\t' -v l="$1" '$1 == l { print $2 }' "$TABLE3")"; r="$(awk -F'\t' -v l="$1" '$1 == l { print $4 }' "$TABLE3")"
  t3set "$1" 8 launched; t3set "$1" 5 99999998; t3set "$1" 6 "Mon Jan  1 00:00:00 2001"; t3set "$1" 9 "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p "$d/.supervisor/automate"
  printf '# Automate Run: %s\n\n## Status: paused\n\n## Current\n- item: reqs/a.md | status: %s | pr: null | branch: f\n- pause_reason: %s\n\n## Progress\n' "$r" "$2" "$3" > "$d/.supervisor/automate/$r.md"
}
ah_park L2 running token_ceiling; ah_park L3 awaiting_merge awaiting_merge
J="$(bash "$S" lane-status "$RF3" --json 2>/dev/null)"
check "AH13 fixture: L2 reads token_ceiling, L3 awaiting_merge" "$(lf L2 .state):$(lf L3 .state)" "token_ceiling:awaiting_merge"
out="$(run lane-wait "$RF3" --interval 1 --timeout 5)"; rc=$?
check "AH13a an unlisted run-file park (token_ceiling) is an event, alone" "$rc:$(printf '%s\n' "$out" | grep '^lane-wait: state')" "0:lane-wait: state L2 token_ceiling — pr -"
hasnt "AH13b a coordinator-driven park (awaiting_merge) is not an event" "$out" "state L3"
has "AH13c … and the act hint names the owner's decision for any other state" "$out" "a run-file park such as token_ceiling — the owner decides"
out="$(run lane-wait "$RF3" --interval 1 --timeout 5)"; rc=$?
check "AH13d a parked-but-quiet fleet with every event reported ⇒ idle at once (no loop, no re-report)" "$rc:$out" "0:lane-wait: idle — no lane is running; nothing changes until the owner acts"
# AH14 a long question is clipped by _lanes_clip on a whitespace boundary and marked ` …` (never a raw cut).
L32="$(awk -F'\t' '$1 == "L2" { print $2 }' "$TABLE3")"; mkdir -p "$L32/.supervisor/inbox/questions"
ahq="$(for i in $(seq 1 40); do printf 'word%02d ' "$i"; done)"
jq -n -c --arg q "$ahq" '{id: "toolu_long", asked_at: "2026-10-07T00:09:00Z", questions: [{question: $q, options: [{label: "A"}]}]}' > "$L32/.supervisor/inbox/questions/toolu_long.json"
out="$(run lane-wait "$RF3" --interval 1 --timeout 5)"
check "AH14 the question text is clipped by _lanes_clip 160" "$(printf '%s\n' "$out" | grep '^lane-wait: question')" \
  "lane-wait: question L2 toolu_long asked 2026-10-07T00:09:00Z — $(for i in $(seq 1 22); do printf 'word%02d ' "$i"; done)…"
# AH12 static: every _LANES_WAIT_QUIET / _LANES_WAIT_LIVE token is a state lane-status can report — a literal
# `state=<tok>` assignment in _lanes_lane_json, a table state it passes through (`removed|abandoned) state="$ts"`),
# a run-file park status `_lanes_parked` passes through, or a SKILL §3 `pause_reason` enum value (any non-empty
# pause_reason becomes the state). A renamed state would otherwise drift the array silently (a quiet token that
# matches nothing stops silencing; a live token that matches nothing lets idle fire past a working lane).
# Mutation control: a fake token must be named.
ah_reportable="$( { grep -v '^_LANES_WAIT_' "$S" | grep -oE '(^|[^_a-zA-Z])state=[a-z_]+' | sed 's/.*state=//'
  grep -A3 '^_lanes_parked() {' "$S" | grep -F 'case "${1:-}" in' | sed -E 's/.* in ([a-z_|]+)\).*/\1/' | tr '|' '\n'
  grep -E '^[[:space:]]+[a-z_|]+\) state="\$ts"' "$S" | sed -E 's/^[[:space:]]+([a-z_|]+)\).*/\1/' | tr '|' '\n'
  grep -m1 '^- pause_reason: ' "$HERE/../skills/automate-loop/SKILL.md" | sed 's/^- pause_reason: //' | tr '|' '\n'; } | sort -u)"
ah_drift() { jq -r '.[]' <<<"$1" 2>/dev/null | while IFS= read -r tok; do grep -qxF -- "$tok" <<<"$ah_reportable" || printf '%s ' "$tok"; done; }
ah_quiet="$(sed -n "s/^_LANES_WAIT_QUIET='\(.*\)'\$/\1/p" "$S")"; ah_live="$(sed -n "s/^_LANES_WAIT_LIVE='\(.*\)'\$/\1/p" "$S")"
check "AH12 both arrays read, and the reportable set holds a parked, a derived, a table and an enum-only state" \
  "$(jq 'length > 0' <<<"$ah_quiet"):$(jq 'length > 0' <<<"$ah_live"):$(grep -cxE 'failed|running|removed|awaiting_go' <<<"$ah_reportable")" "true:true:4"
check "AH12a every _LANES_WAIT_QUIET token is a reportable state" "$(ah_drift "$ah_quiet")" ""
check "AH12b every _LANES_WAIT_LIVE token is a reportable state" "$(ah_drift "$ah_live")" ""
check "AH12c mutation: a fake token appended to a copy of the array is named" "$(ah_drift "$(jq -c '. + ["stalld"]' <<<"$ah_quiet")")" "stalld "
check "AH12d no token is both live and quiet (an event state would be silenced twice)" "$(jq -rn --argjson a "$ah_quiet" --argjson b "$ah_live" '$a - ($a - $b) | join(",")')" ""
# AH15 the liveness marker: written naming the watcher's pid; a second watcher takes it over; the first
# one's exit leaves it (it names the second); the owner's exit removes it; the idle paths write none.
LWM="$P/.supervisor/automate/$PARENT2.lane-wait.pid"; rm -f "$LWM"
ah15_wait() { local i=0; while [ "$(awk '{ print $1 }' "$LWM" 2>/dev/null)" != "$1" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done; }
bash "$S" lane-wait "$RF2" --interval 1 --timeout 60 >/dev/null 2>&1 & LWA=$!; BG_PIDS="$BG_PIDS $LWA"
ah15_wait "$LWA"
check "AH15a lane-wait writes <pid> <start epoch>" "$(awk '{ print ($1 == '"$LWA"') ":" ($2 ~ /^[0-9]+$/) }' "$LWM" 2>/dev/null)" "1:1"
bash "$S" lane-wait "$RF2" --interval 1 --timeout 60 >/dev/null 2>&1 & LWB=$!; BG_PIDS="$BG_PIDS $LWB"
ah15_wait "$LWB"
check "AH15b a second watcher takes the marker over" "$(awk '{ print $1 }' "$LWM" 2>/dev/null)" "$LWB"
kill -TERM "$LWA" 2>/dev/null; wait "$LWA" 2>/dev/null
check "AH15c the first watcher's exit leaves the marker it no longer owns" "$(awk '{ print $1 }' "$LWM" 2>/dev/null)" "$LWB"
kill -TERM "$LWB" 2>/dev/null; wait "$LWB" 2>/dev/null
check "AH15d the owner's exit (TERM) removes it" "$([ -e "$LWM" ] && echo present || echo absent)" absent
out="$(run lane-wait "$RF2" --interval 1 --timeout 1)"
check "AH15e a lane-wait that times out removes its marker" "$([ -e "$LWM" ] && echo present || echo absent)" absent
run lane-wait "$P/.supervisor/automate/none.md" >/dev/null
bash "$S" lane-wait "$TABLE2" --interval 1 --timeout 60 >/dev/null 2>&1 & LWC=$!; BG_PIDS="$BG_PIDS $LWC"
ah15_wait "$LWC"
check "AH15g given the .lanes table path, the marker still lands at <parent_run_id>.lane-wait.pid" "$(awk '{ print $1 }' "$LWM" 2>/dev/null)" "$LWC"
kill -TERM "$LWC" 2>/dev/null; wait "$LWC" 2>/dev/null
check "AH15f the no-lane-table idle path writes no marker" "$(ls "$P/.supervisor/automate/" | grep -c 'none.lane-wait.pid' | tr -d ' ')" 0
# Clean up the second wave: lane-feed L<n> (T7) resolves the NEWEST lane table in the primary.
rm -rf "$LWS" "$P/.supervisor/automate/$PARENT3".* "$T/work/primary-lanes/$PARENT3"
out="$(run lane-feed "$L6")"
has "T3 feed prints spawns" "$out" "[spawn] loomwright:worker: implement subtask 1"
has "T4 feed prints the park write" "$out" "[park] bash automate-helpers.sh current-set"
has "T5 feed prints the deferred park" "$out" "[park] deferred toolu_r1 — awaiting input"
has "T6 feed prints messages and asks" "$out" "[ask] Which path?"
has "T7 feed resolves L<n>" "$(cd "$P" && bash "$S" lane-feed L6 2>&1)" "[init] session sess-r"
bash "$S" lane-feed "$L6" --follow > "$T/follow.out" 2>&1 & FP=$!
sleep 1.5; kill "$FP" 2>/dev/null; wait "$FP" 2>/dev/null   # lane-feed kills its own pipeline (F12)
has "T8 --follow narrates" "$(cat "$T/follow.out")" "[spawn] loomwright:worker"
has "T9 died lane: feed reports it" "$(run lane-feed "$LR2/L1")" "[died]"

# ---- U: merge-readiness report (AC9) -------------------------------------------------------------------
L3="$LR2/L3"
cat > "$L3/reqs/a.md" <<'EOF'
# a
## Touches
- `reqs/a.md`
- `src/`
## Validation (must pass before merge)
1. **Baseline:** full loop on base and branch.
2. **Running system:** run it for real and paste the output.
3. **A failure this must catch:** the mutation control, shown failing.
## Notes
EOF
printf '# Automate Run: %s\n\n## Current\n- item: reqs/a.md | status: awaiting_merge | pr: https://github.com/o/r/pull/5 | branch: f\n- pause_reason: ready_for_release\n\n## Progress\n- 2026-10-07T01:00:00Z children-settled: settled\n' "$PARENT2-L3" > "$L3/.supervisor/automate/$PARENT2-L3.md"
mkdir -p "$L3/.supervisor/jobs/in-progress"
printf '# brief for reqs/a.md\n- carried LOW: name the flag in the help text\n' > "$L3/.supervisor/jobs/in-progress/b.md"
cat > "$T/gh-ready" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "pr view") jq -n --arg b "$(printf 'Validation 1 baseline\n```\npassed: 5 failed: 0\n```\nValidation 2: will run later\nValidation 3 mutation\n```\nFAIL - leg x\n```\n')" '{body: $b, headRefOid: "abc123"}' ;;
  "pr diff") printf 'reqs/a.md\nsrc/x.sh\nchangelog.d/x.md\ndocs/other.md\n' ;;
  "pr checks") echo '[{"name":"ci","bucket":"pass"}]' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$T/gh-ready"
out="$(LOOMWRIGHT_GH_BIN="$T/gh-ready" run lane-readiness "$L3")"; rc=$?
RD="$L3/.supervisor/automate/$PARENT2-L3.merge-readiness.md"
check "U1 lane-readiness exits 0 and writes the report" "$rc:$([ -f "$RD" ] && echo yes)" "0:yes"
has "U2 a Validation step with pasted output ⇒ PASS" "$(cat "$RD")" "V1 Baseline: PASS"
has "U3 a running-system step with no pasted output ⇒ NOT-RUN, never PASS" "$(cat "$RD")" "V2 Running system: NOT-RUN — mentioned in the PR body without pasted output"
has "U4 scope fence lists the file outside the brief" "$(cat "$RD")" "  - docs/other.md"
has "U4b scope fence FAIL" "$(cat "$RD")" "- scope-fence: FAIL"
has "U5 carried note listed, NOT-RUN without accounting" "$(cat "$RD")" "carried-notes: NOT-RUN — 1 carried note(s)"
has "U6 gates PASS (checks green on head, decisions, children settled)" "$(cat "$RD")" "- gates: PASS"
has "U7 headline repro evidenced" "$(cat "$RD")" "V3 A failure this must catch: PASS"
has "U8 score line" "$(cat "$RD")" "- score: 2/5 | summary: ready (2/5: running-system NOT-RUN, carried-notes NOT-RUN, scope-fence FAIL)"
J="$(sj)"
check "U9 lane-status --json exposes the readiness score" "$(lf L3 '.readiness.score')" "2/5"
check "U9b lane-status --json carries the branch from ## Current" "$(lf L3 '.branch')" f
check "U10 parked ready lane state" "$(lf L3 .state)" ready_for_release
cat > "$T/helpers-merged.sh" <<'EOF'
#!/usr/bin/env bash
[ "$1" = reconcile-item ] && echo merged
EOF
chmod +x "$T/helpers-merged.sh"
J="$(LOOMWRIGHT_LANES_HELPERS="$T/helpers-merged.sh" sj)"
check "U11 parked lane reconciled against gh (reconcile-item)" "$(lf L3 '.state + "|" + .pr_state')" "merged|merged"
out="$(LOOMWRIGHT_GH_BIN="$T/absent-gh" run lane-readiness "$L3")"
has "U12 gh unreadable ⇒ every Validation step NOT-RUN" "$(cat "$RD")" "V1 Baseline: NOT-RUN — PR body unreadable"
out="$(LOOMWRIGHT_GH_BIN="$T/gh-ready" run lane-status "$RF2" --refresh-readiness)"
has "U13 lane-status --refresh-readiness re-writes it" "$(cat "$RD")" "V1 Baseline: PASS"
has "U13b plain view shows the score" "$out" "readiness: ready (2/5:"
# A numbered `Validation 1 (tests):` line, a blank, an intro paragraph ending in ':' and then the fence
# still reads PASS (origin/main did; review iteration 2 — the paragraph boundary never drops it).
cat > "$T/gh-ready-intro" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "pr view") jq -n --arg b "$(printf 'Validation 1 (tests):\n\nRan the suite:\n```\npassed: 5 failed: 0\n```\n')" '{body: $b, headRefOid: "abc123"}' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$T/gh-ready-intro"
LOOMWRIGHT_GH_BIN="$T/gh-ready-intro" run lane-readiness "$L3" >/dev/null
has "U13c numbered entry: \`Validation 1 (tests):\` + blank + intro paragraph + fence ⇒ PASS" "$(cat "$RD")" "V1 Baseline: PASS — pasted output in the PR body"
LOOMWRIGHT_GH_BIN="$T/gh-ready" run lane-readiness "$L3" >/dev/null
# U14: the children-settled line is clipped, never mid-token. Wave W2's L2 line was cut at 160
# chars inside its PR URL (`…/loomwright/pull/460` → `…/loomwrig`), and meta-sync's forge_slug scrub
# then refused the lane's metadata push (a non-allowlisted slug), so lane-remove refused the lane.
RF3="$L3/.supervisor/automate/$PARENT2-L3.md"; cp "$RF3" "$T/L3-runfile.bak"
printf -- '- 2026-10-10T14:44:12Z supervisor: worker done (ci-local PASS 161/161; provides 2/2; children settled); FINALIZE → PR https://github.com/vikashruhilgit/loomwright/pull/460 (base main verified); Phase 4.5 next\n' >> "$RF3"
out="$(LOOMWRIGHT_GH_BIN="$T/gh-ready" run lane-readiness "$L3")"
cs="$(grep 'children-settled:' "$RD")"
check "U14 a clipped line never ends inside a token (no partial URL)" "$(printf '%s' "$cs" | grep -cE 'github\.com/[^ ]*[^ /0-9]$|loomwrig($|[^h])')" "0"
has "U14b a clipped line is marked" "$cs" " …"
# U15: --refresh-readiness also re-writes a lane already closed out (done / awaiting_go), so a report
# written before a fix can be repaired by the sanctioned path instead of by hand.
sed -e 's/status: awaiting_merge/status: done/' -e 's/^- pause_reason: ready_for_release$/- pause_reason: awaiting_go/' "$T/L3-runfile.bak" > "$RF3"
rm -f "$RD"
out="$(LOOMWRIGHT_GH_BIN="$T/gh-ready" run lane-status "$RF2" --refresh-readiness)"
check "U15 --refresh-readiness re-writes a done lane's report" "$([ -f "$RD" ] && echo yes)" "yes"
cp "$T/L3-runfile.bak" "$RF3"
out="$(LOOMWRIGHT_GH_BIN="$T/gh-ready" run lane-readiness "$L3")"

# ---- V: --leaks, --resources, --tokens -----------------------------------------------------------------
# V1-V6 read a fixed process table (ps stub: $PS_TABLE's content, the real ps when unset), so the
# lanes launched above — whose stub `claude` exits after 60s — cannot change between snapshot and check.
printf '%s\n' '#!/usr/bin/env bash' '[ -n "${PS_TABLE:-}" ] && { cat "$PS_TABLE"; exit 0; }; exec ps "$@"' > "$T/ps-stub"
chmod +x "$T/ps-stub"; export LOOMWRIGHT_LANES_PS="$T/ps-stub" PS_TABLE="$T/ps.table"
echo "    1     0 /sbin/launchd" > "$PS_TABLE"
out="$(run lane-status "$RF2" --leaks)"; has "V1 no snapshot ⇒ unknown, exit 0" "$out" "leaks: unknown — no snapshot"
out="$(run lane-status "$RF2" --leaks --snapshot)"; has "V2 snapshot written" "$out" "leaks: snapshot written"
check "V3 unchanged ⇒ leaks: none" "$(run lane-status "$RF2" --leaks | head -1 | cut -c1-11)" "leaks: none"
cp "$P/.supervisor/config.json" "$T/config.bak"
HL="claude -p"   # the headless command the claude-p section matches (one vendor reference for V4-V26)
echo " 4321     1 bash $S _lane-run $LR2/L1 log died in -- env $HL --resume x" >> "$PS_TABLE"; echo '{"auto_review": false}' > "$P/.supervisor/config.json"
git -C "$P" worktree add -q "$T/wt-leak" -b leak-wt 2>/dev/null
out="$(run lane-status "$RF2" --leaks)"
check "V4 leaks found names each section" "$(printf '%s\n' "$out" | head -1)" "leaks: found — worktrees, claude-p, config-checksum"
has "V5 the leaked process is listed" "$out" "  + 4321 bash $S _lane-run $LR2/L1 log died in -- env $HL --resume x"
has "V6 unchanged sections say same" "$out" "- merge-watch: same"
cp "$T/config.bak" "$P/.supervisor/config.json"; unset PS_TABLE; git -C "$P" worktree remove --force "$T/wt-leak" 2>/dev/null
# V15-V20 (wave-close fix 2) the merge-watch section lists LIVE watchers from their *.merge-watch markers
# (`## merge-watch v2`), never a process-name match: W3's `leaks: found — merge-watch` was a grep whose
# argv named scripts/automate-merge-watch.sh. A pgrep wrapper hands the merge-watch pattern to the REAL
# pgrep (so the v1 mutation sees the decoy) and everything else to the stub. Decoys are background
# `sleep 30`s renamed with `exec -a` (bash 3.2); each names the suite dir, is tracked in BG_PIDS and killed.
cat > "$T/pgrep-mw" <<EOF
#!/usr/bin/env bash
case "\$*" in *automate-merge-watch*) exec pgrep "\$@" ;; esac
exec "$T/pgrep-stub" "\$@"
EOF
chmod +x "$T/pgrep-mw"
mw_spawn() { # <argv0> — sets MWPID: a background sleep whose ps command line reads "<argv0> 30"
  bash -c 'exec -a "$0" sleep 30' "$1" </dev/null >/dev/null 2>&1 &
  MWPID=$!; BG_PIDS="$BG_PIDS $MWPID"; local i=0
  until case "$(ps -ww -o command= -p "$MWPID" 2>/dev/null)" in "$1"*) true ;; *) false ;; esac || [ "$i" -ge 50 ]; do sleep 0.1; i=$((i + 1)); done
}
mw_kill() { local q; for q in "$@"; do kill -TERM "$q" 2>/dev/null; wait "$q" 2>/dev/null; done; }
mwl() { LOOMWRIGHT_LANES_PGREP="$T/pgrep-mw" bash "${MW_S:-$S}" lane-status "$1" --leaks "${@:2}" 2>&1; }
PARENTMW=automate-2026-10-11-090000; RFMW="$P/.supervisor/automate/$PARENTMW.md"
PARENTMV=automate-2026-10-11-091000; RFMV="$P/.supervisor/automate/$PARENTMV.md"
printf '# Automate Run: %s\n\n## Progress\n' "$PARENTMW" > "$RFMW"; printf '# Automate Run: %s\n\n## Progress\n' "$PARENTMV" > "$RFMV"
mwl "$RFMW" --snapshot >/dev/null
check "V15 the snapshot's merge-watch section carries the v2 format tag (and no v1 header)" \
  "$(grep -cxF '## merge-watch v2' "$P/.supervisor/automate/$PARENTMW.leaks-snapshot" | tr -d ' '):$(grep -cxF '## merge-watch' "$P/.supervisor/automate/$PARENTMW.leaks-snapshot" | tr -d ' ')" "1:0"
# the v1 mutation: the section body back to the process-name match; its own snapshot, before the decoy
awk '/# >>> merge-watch body$/ { print "  \"${LOOMWRIGHT_LANES_PGREP:-pgrep}\" -lf automate-merge-watch 2>/dev/null"; next } { print }' "$S" > "$MUT/lanes-mw.sh"
if ! cmp -s "$S" "$MUT/lanes-mw.sh" && bash -n "$MUT/lanes-mw.sh"; then MW_S="$MUT/lanes-mw.sh" mwl "$RFMV" --snapshot >/dev/null; MWMUT=1; else MWMUT=0; fi
mw_spawn "grep $T/scripts/automate-merge-watch.sh"; MWD="$MWPID"
out="$(mwl "$RFMW")"
check "V16 a process whose argv only NAMES automate-merge-watch.sh is not a watcher ⇒ merge-watch: same" \
  "$(printf '%s\n' "$out" | head -1 | cut -c1-11):$(printf '%s\n' "$out" | grep -cxF -- '- merge-watch: same' | tr -d ' ')" "leaks: none:1"
if [ "$MWMUT" = 1 ]; then
  has "V16b mutation (the v1 pgrep line restored) trips V16: the decoy reads as a leak" "$(MW_S="$MUT/lanes-mw.sh" mwl "$RFMV")" "- merge-watch: changed"
else bad "V16b mutation control not built"; fi
mw_kill "$MWD"
# V17 a real marker + a live process running automate-merge-watch for that marker's PR ⇒ reported
MWU1="https://github.com/o/r/pull/777"; MWU2="https://github.com/o/r/pull/778"
mw_spawn "bash $T/scripts/automate-merge-watch.sh $RFMW reqs/a.md $MWU1"; MW1="$MWPID"
printf 'pid\t%s\npr_url\t%s\nstarted\t2026-10-11T09:00:00Z\n' "$MW1" "$MWU1" > "$P/.supervisor/automate/mwtest.merge-watch"
out="$(mwl "$RFMW")"
check "V17 a live watcher in the primary ⇒ found — merge-watch, listed as <pid> <pr_url>" \
  "$(printf '%s\n' "$out" | head -1):$(printf '%s\n' "$out" | grep -cxF -- "  + $MW1 $MWU1" | tr -d ' ')" "leaks: found — merge-watch:1"
# V18 … and a live watcher of a lane in this run's table
mkdir -p "$T/mwlane/.supervisor/automate"
printf 'L1\t%s\treqs/a.md\t%s-L1\t-\t-\t-\tcreated\t-\t-\n' "$T/mwlane" "$PARENTMW" > "$P/.supervisor/automate/$PARENTMW.lanes"
mw_spawn "bash $T/scripts/automate-merge-watch.sh $T/mwlane/x.md reqs/a.md $MWU2"; MW2="$MWPID"
printf 'pid\t%s\npr_url\t%s\n' "$MW2" "$MWU2" > "$T/mwlane/.supervisor/automate/$PARENTMW-L1.merge-watch"
out="$(mwl "$RFMW")"
check "V18 a live watcher in a lane of the table is listed too (sorted, one line each)" \
  "$(printf '%s\n' "$out" | grep -cxF -- "  + $MW1 $MWU1" | tr -d ' '):$(printf '%s\n' "$out" | grep -cxF -- "  + $MW2 $MWU2" | tr -d ' ')" "1:1"
mw_kill "$MW1" "$MW2"
out="$(mwl "$RFMW")"
check "V19 markers left behind by watchers that exited are not live ⇒ merge-watch: same" \
  "$(printf '%s\n' "$out" | grep -cxF -- '- merge-watch: same' | tr -d ' ')" 1
rm -f "$P/.supervisor/automate/mwtest.merge-watch" "$P/.supervisor/automate/$PARENTMW.lanes"; rm -rf "$T/mwlane"
# V20 a v1 snapshot (taken by the pre-fix code: `## merge-watch` + pgrep lines) is NOT compared — never a false found
SFMW="$P/.supervisor/automate/$PARENTMW.leaks-snapshot"
awk '$0 == "## merge-watch v2" { print "## merge-watch"; print "4242 grep scripts/automate-merge-watch.sh"; next } { print }' "$SFMW" > "$SFMW.t" && mv "$SFMW.t" "$SFMW"
out="$(mwl "$RFMW")"
check "V20 a v1 snapshot section ⇒ leaks: none, the first line naming the uncompared section" \
  "$(printf '%s\n' "$out" | head -1)" "leaks: none (vs snapshot $SFMW; merge-watch not compared — pre-v2 snapshot)"
has "V20b … and the body says why" "$out" "- merge-watch: not compared — the wave-start snapshot predates the marker-based watcher list (v1)"
rm -f "$MUT/lanes-mw.sh"
# V21-V26 the claude-p section lists only THIS run's processes (`## claude-p v2`), read from the real ps:
# closing wave 1 of automate-2026-10-15-163325 read `leaks: found — claude-p` from another repo's healthy
# wave (its `_lane-run <other>-lanes/<run>/L1|L2` wrappers and their headless children). Decoys are
# `sleep 30`s renamed with `exec -a`; a wrapper decoy forks its headless child (cwd /, so only the
# parent pid ties it) before it execs, so the child's ppid is the wrapper's pid. All named under $T.
cp_spawn() { # <cwd> <argv0> — sets CPPID: a lone decoy running in <cwd>
  ( cd "$1" && exec -a "$2" sleep 30 ) </dev/null >/dev/null 2>&1 &
  CPPID=$!; BG_PIDS="$BG_PIDS $CPPID"; cp_seen "$CPPID" "$2"
}
cp_pair() { # <lane_dir> — sets CPW (a `_lane-run <lane_dir>` wrapper decoy) and CPC (its headless child)
  bash -c '( cd / && exec -a "$3 --plugin-dir $2" sleep 30 ) & exec -a "bash $2/scripts/automate-lanes.sh _lane-run $1 $1.log $1.died /dev/null -- env $3 --plugin-dir $2" sleep 30' \
    _ "$1" "$T" "$HL" </dev/null >/dev/null 2>&1 &
  CPW=$!; BG_PIDS="$BG_PIDS $CPW"; cp_seen "$CPW" "bash $T/scripts/automate-lanes.sh _lane-run $1 "
  local i=0; CPC=""
  until [ -n "$CPC" ] || [ "$i" -ge 50 ]; do CPC="$(pgrep -P "$CPW" 2>/dev/null | head -1)"; [ -n "$CPC" ] || sleep 0.1; i=$((i + 1)); done
  BG_PIDS="$BG_PIDS $CPC"; cp_seen "$CPC" "$HL --plugin-dir $T"
}
cp_seen() { local i=0; until case "$(ps -ww -o command= -p "$1" 2>/dev/null)" in "$2"*) true ;; *) false ;; esac || [ "$i" -ge 50 ]; do sleep 0.1; i=$((i + 1)); done; }
cpl() { bash "${CP_S:-$S}" lane-status "$1" --leaks "${@:2}" 2>&1; }
PARENTCP=automate-2026-10-16-090000; RFCP="$P/.supervisor/automate/$PARENTCP.md"; SFCP="$P/.supervisor/automate/$PARENTCP.leaks-snapshot"
CPL1="$T/work/primary-lanes/$PARENTCP/L1"; CPF="$T/work/studio-lanes/automate-2026-10-15-153327"
mkdir -p "$CPL1" "$CPF/L1" "$CPF/L2"
printf '# Automate Run: %s\n\n## Progress\n' "$PARENTCP" > "$RFCP"
cpl "$RFCP" --snapshot >/dev/null
check "V21 the snapshot's claude-p section carries the v2 format tag (and no v1 header)" \
  "$(grep -cxF '## claude-p v2' "$SFCP" | tr -d ' '):$(grep -cxF '## claude-p' "$SFCP" | tr -d ' ')" "1:0"
# the v1 mutation: the section body back to the machine-wide match; its own run + snapshot, before the decoys
PARENTCV=automate-2026-10-16-091000; RFCV="$P/.supervisor/automate/$PARENTCV.md"
printf '# Automate Run: %s\n\n## Progress\n' "$PARENTCV" > "$RFCV"
awk -v hl="$HL" '/# >>> claude-p body$/ { print "  pgrep -lf '"'"'" hl "'"'"' 2>/dev/null"; next } { print }' "$S" > "$MUT/lanes-cp.sh"
if ! cmp -s "$S" "$MUT/lanes-cp.sh" && bash -n "$MUT/lanes-cp.sh"; then CP_S="$MUT/lanes-cp.sh" cpl "$RFCV" --snapshot >/dev/null; CPMUT=1; else CPMUT=0; fi
# V22 another repo's healthy wave: two wrappers + their children, and a headless session whose cwd is its lane
cp_pair "$CPF/L1"; FW1="$CPW"; FC1="$CPC"; cp_pair "$CPF/L2"; FW2="$CPW"; FC2="$CPC"
cp_spawn "$CPF/L1" "$HL --resume foreign"; FO="$CPPID"
out="$(cpl "$RFCP")"
check "V22 a foreign run's lane processes do not count ⇒ leaks: none, claude-p: same" \
  "$(printf '%s\n' "$out" | head -1 | cut -c1-11):$(printf '%s\n' "$out" | grep -cxF -- '- claude-p: same' | tr -d ' ')" "leaks: none:1"
if [ "$CPMUT" = 1 ]; then
  has "V22b mutation (the v1 machine-wide pgrep restored) trips V22: the foreign wave reads as a leak" "$(CP_S="$MUT/lanes-cp.sh" cpl "$RFCV")" "- claude-p: changed"
else bad "V22b mutation control not built"; fi
# V23 this run's leftover lane: its wrapper and (by parent pid alone — cwd /) its headless child
cp_pair "$CPL1"; OW="$CPW"; OC="$CPC"
out="$(cpl "$RFCP")"
check "V23 this run's leftover lane process still reads found — wrapper and child listed, foreign ones not" \
  "$(printf '%s\n' "$out" | head -1):$(printf '%s\n' "$out" | grep -c "^  + $OW bash $T/scripts/automate-lanes.sh _lane-run $CPL1 " | tr -d ' '):$(printf '%s\n' "$out" | grep -cxF -- "  + $OC $HL --plugin-dir $T 30" | tr -d ' '):$(printf '%s\n' "$out" | grep -cE "^  \+ ($FW1|$FC1|$FW2|$FC2|$FO) " | tr -d ' ')" \
  "leaks: found — claude-p:1:1:0"
mw_kill "$OW" "$OC"
# V24 a headless session of this run whose wrapper is gone, tied by its working directory (a lane of the table)
printf 'L1\t%s\treqs/a.md\t%s-L1\t-\t-\t-\tcreated\t-\t-\n' "$CPL1" "$PARENTCP" > "$P/.supervisor/automate/$PARENTCP.lanes"
cp_spawn "$CPL1" "$HL --resume orphan"; OO="$CPPID"
out="$(cpl "$RFCP")"
check "V24 an orphaned headless session in this run's lane (cwd) reads found, listed" \
  "$(printf '%s\n' "$out" | head -1):$(printf '%s\n' "$out" | grep -cxF -- "  + $OO $HL --resume orphan 30" | tr -d ' ')" "leaks: found — claude-p:1"
# V25 an unreadable process table reads unknown, never found (fail SAFE, exit 0)
out="$(LOOMWRIGHT_LANES_PS=false cpl "$RFCP")"; rc=$?
check "V25 ps unreadable ⇒ leaks: unknown naming the section, exit 0" \
  "$rc:$(printf '%s\n' "$out" | head -1)" "0:leaks: unknown — claude-p unreadable (vs snapshot $SFCP)"
has "V25b … and the body says why" "$out" "- claude-p: unknown — the process table is unreadable (ps)"
# V25c a headless session to attribute (V22's foreign orphan still runs) with no working-directory reader
out="$(LOOMWRIGHT_LANES_LSOF="$T/no-lsof" LOOMWRIGHT_LANES_PROC="$T/no-proc" cpl "$RFCP")"; rc=$?
check "V25c no cwd reader (lsof, /proc) ⇒ leaks: unknown, exit 0, the body naming why" \
  "$rc:$(printf '%s\n' "$out" | head -1):$(printf '%s\n' "$out" | grep -cxF -- "- claude-p: unknown — no reader for a process's working directory (lsof, /proc)" | tr -d ' ')" \
  "0:leaks: unknown — claude-p unreadable (vs snapshot $SFCP):1"
# V25e no lsof ⇒ the /proc fallback attributes by `<proc>/<pid>/cwd` (a fake tree: V24's orphan in this
# run's lane, V22's foreign orphan in its own lane) — the minimal-container path, not only lsof's
mkdir -p "$T/fakeproc/self" "$T/fakeproc/$OO" "$T/fakeproc/$FO"
ln -s "$CPL1" "$T/fakeproc/$OO/cwd"; ln -s "$CPF/L1" "$T/fakeproc/$FO/cwd"
out="$(LOOMWRIGHT_LANES_LSOF="$T/no-lsof" LOOMWRIGHT_LANES_PROC="$T/fakeproc" cpl "$RFCP")"
check "V25e lsof absent, /proc present ⇒ this run's orphan found by its /proc cwd, the foreign one not" \
  "$(printf '%s\n' "$out" | head -1):$(printf '%s\n' "$out" | grep -cxF -- "  + $OO $HL --resume orphan 30" | tr -d ' '):$(printf '%s\n' "$out" | grep -c "^  + $FO " | tr -d ' ')" \
  "leaks: found — claude-p:1:0"
rm -rf "$T/fakeproc"
# V25d the unknown sniff is claude-p's alone: a lanes-dir entry NAMED like the fail-SAFE line is a leak
: > "$T/work/primary-lanes/unknown — decoy"
out="$(cpl "$RFCP")"
check "V25d a <primary>-lanes entry named 'unknown — …' reads found — lanes-dir, never unknown" \
  "$(printf '%s\n' "$out" | head -1 | grep -c '^leaks: found — lanes-dir' | tr -d ' '):$(printf '%s\n' "$out" | grep -cxF -- '  + unknown — decoy' | tr -d ' ')" "1:1"
rm -f "$T/work/primary-lanes/unknown — decoy"
# V26 a snapshot written before v2 (`## claude-p` + machine-wide pgrep lines) is NOT compared — the
# orphan of V24 still runs, and still the first line is never a false found
awk -v hl="$HL" '$0 == "## claude-p v2" { print "## claude-p"; print "4242 " hl " --resume someone-else"; skip = 1; next } /^## / { skip = 0 } !skip' "$SFCP" > "$SFCP.t" && mv "$SFCP.t" "$SFCP"
out="$(cpl "$RFCP")"
check "V26 a v1 claude-p snapshot section ⇒ leaks: none, the first line naming the uncompared section" \
  "$(printf '%s\n' "$out" | head -1)" "leaks: none (vs snapshot $SFCP; claude-p not compared — pre-v2 snapshot)"
has "V26b … and the body says why" "$out" "- claude-p: not compared — the wave-start snapshot predates the run-scoped process list (v1 matched every such process on the machine)"
mw_kill "$OO" "$FW1" "$FC1" "$FW2" "$FC2" "$FO"
# V27 the tie test reads a wrapper's argv tail from its start: a lane path with a space is never cut at it
check "V27 a wrapper argv tail whose lane path holds a space ties to its run (root and table forms), not to a sibling run" \
  "$( . "$S"; t() { _lanes_path_tied "$@" && echo y || echo n; }
     printf '%s' "$(t "/w/my repo-lanes/r1/L1 /w/my repo-lanes/r1/L1.stream.log x" "/w/my repo-lanes/r1" "")"
     printf '%s' "$(t "/w/my repo-lanes/r1/L1 log x" "" "/w/my repo-lanes/r1/L1")"
     printf '%s' "$(t "/w/my repo-lanes/r10/L1 /w/my repo-lanes/r1/L1.stream.log x" "/w/my repo-lanes/r1" "/w/my repo-lanes/r1/L1")" )" "yyn"
rm -f "$MUT/lanes-cp.sh" "$P/.supervisor/automate/$PARENTCP.lanes" "$P/.supervisor/automate/$PARENTCP".* "$P/.supervisor/automate/$PARENTCV".*
rm -rf "$T/work/primary-lanes/$PARENTCP" "$T/work/studio-lanes"
out="$(run lane-status "$RF2" --resources)"; has "V7 no fleet.log ⇒ resources unknown" "$out" "resources: unknown"
printf '2026-10-07T10:00:00Z load1=5 load=ok L1_rss=100M L2_rss=300M nonlane_load=10%%\n2026-10-07T10:00:10Z load1=9 load=busy L1_rss=200M L2_rss=150M nonlane_load=20%%\n' > "$P/.supervisor/automate/$PARENT2.fleet.log"
out="$(run lane-status "$RF2" --resources)"
has "V8 latest line per lane" "$out" "L1: L1_rss=200M"
has "V9 wave peak" "$out" "peak: load1=9 L1_rss=200M L2_rss=300M nonlane_load=20%"
has "V10 machine part of the latest line" "$out" "machine: load1=9 load=busy nonlane_load=20%"
cat > "$T/ledger.sh" <<'EOF'
#!/usr/bin/env bash
# argument-aware like the real reader: every --root adds one root's sums into the one line
n=0; for a in "$@"; do [ "$a" = "--root" ] && n=$((n + 1)); done; [ "$n" -gt 0 ] || n=1
echo "INPUT=$((1 * n)) OUTPUT=$((2 * n)) CACHE_READ=0 CACHE_CREATE=0 TOTAL=$((3 * n)) EVENTS=$n"
EOF
out="$(LOOMWRIGHT_LANES_TOKEN_LEDGER="$T/ledger.sh" run lane-status "$RF2" --tokens)"
has "V11 per-lane tokens" "$out" "L1 INPUT=1 OUTPUT=2"
has "V12 parent tokens" "$out" "parent INPUT=1"
check "V13 total sums parent + lanes" "$(printf '%s\n' "$out" | sed -n 's/.* TOTAL=\([0-9]*\).*/\1/p' | tail -1)" 24
out="$(LOOMWRIGHT_LANES_TOKEN_LEDGER="$T/absent.sh" run lane-status "$RF2" --tokens)"; rc=$?
check "V14 ledger absent ⇒ unknown, exit 0" "$rc:$out" "0:tokens: unknown — read-token-ledger.sh absent"
for p in $(pgrep -f "_lane-run $LR2" 2>/dev/null); do kill -TERM "$p" 2>/dev/null; done

# ---- W: drain round 1 hardening -------------------------------------------------------------------------
# W1 (D8) the total is ONE read-token-ledger.sh call over every root: a parent that ran no session of its
# own (its root alone is unreadable) with readable lanes is NOT LEDGER_UNREADABLE. The stub models the
# real reader: roots add up, LEDGER_UNREADABLE=1 only when no root reads.
export LEDGER_CALLS="$T/ledger.calls"; : > "$LEDGER_CALLS"
cat > "$T/ledger-arg.sh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$LEDGER_CALLS"
n=0; prev=""
for a in "$@"; do { [ "$prev" = "--root" ] && [ "$a" != "$LEDGER_EMPTY_ROOT" ]; } && n=$((n + 1)); prev="$a"; done
if [ "$n" = 0 ]; then echo "INPUT=0 OUTPUT=0 CACHE_READ=0 CACHE_CREATE=0 TOTAL=0 EVENTS=0 LEDGER_UNREADABLE=1"
else echo "INPUT=$n OUTPUT=$((2 * n)) CACHE_READ=0 CACHE_CREATE=0 TOTAL=$((3 * n)) EVENTS=$n"; fi
EOF
tokens_arg() { LOOMWRIGHT_LANES_TOKEN_LEDGER="$T/ledger-arg.sh" LEDGER_EMPTY_ROOT="$P" bash "${1:-$S}" lane-status "$RF2" --tokens 2>&1; }
out="$(tokens_arg)"; TOT="$(printf '%s\n' "$out" | grep '^total (parent + lanes):')"
has "W1 the parent alone is unreadable (no session of its own)" "$(printf '%s\n' "$out" | grep '^parent ')" "LEDGER_UNREADABLE=1"
hasnt "W1b readable lanes ⇒ the total is not LEDGER_UNREADABLE" "$TOT" "LEDGER_UNREADABLE"
has "W1c the total adds the 7 readable lane roots" "$TOT" "TOTAL=21"
check "W1d the total is one call: --run-id <parent> with the primary + 7 lane roots" \
  "$(grep "^--run-id $PARENT2 " "$LEDGER_CALLS" | awk '{ n = 0; for (i = 1; i <= NF; i++) if ($i == "--root") n++; if (n > 1) print n }')" 8
cat > "$T/mut-total.line" <<'EOF'
  to="$(for r in "${roots[@]}"; do [ "$r" = --root ] || bash "$rtl" --run-id "$3" --root "$r" 2>/dev/null | head -1; done | awk '{ for (i = 1; i <= NF; i++) { k = $i; v = $i; sub(/=.*/, "", k); sub(/^[^=]*=/, "", v); if (k == "LEDGER_UNREADABLE") u = 1; else if (v ~ /^[0-9]+$/) { if (!(k in s)) o[++n] = k; s[k] += v } } } END { for (j = 1; j <= n; j++) printf "%s%s=%s", (j > 1 ? " " : ""), o[j], s[o[j]]; if (u) printf " LEDGER_UNREADABLE=1"; print "" }')"
EOF
awk -v f="$T/mut-total.line" '/# TOTAL-CALL$/ { while ((getline l < f) > 0) print l; next } { print }' "$S" > "$MUT/automate-lanes.sh"
if ! cmp -s "$S" "$MUT/automate-lanes.sh" && bash -n "$MUT/automate-lanes.sh"; then
  has "W1e mutation (independent per-root calls, ORed) trips W1b" "$(tokens_arg "$MUT/automate-lanes.sh" | grep '^total')" "LEDGER_UNREADABLE=1"
else bad "W1e mutation control not built"; fi

# W2 a value-taking flag given last exits promptly non-zero (never a `shift 2` loop), per subcommand family
bounded() { # bounded <secs> <args...> — run the script; 124 when still alive after <secs> (then killed)
  local s="$1" p i=0; shift
  bash "$S" "$@" > "$T/bounded.out" 2>&1 < /dev/null & p=$!
  while kill -0 "$p" 2>/dev/null && [ "$i" -lt $((s * 10)) ]; do sleep 0.1; i=$((i + 1)); done
  if kill -0 "$p" 2>/dev/null; then kill -KILL "$p" 2>/dev/null; wait "$p" 2>/dev/null; return 124; fi
  wait "$p"
}
prompt_nz() { case "$1" in 0) echo "rc=0" ;; 124) echo "still running after 5s" ;; *) echo prompt-nonzero ;; esac; }
for spec in "lane-create|$RF reqs/a.md 7 --parallel" "lane-create|$RF reqs/a.md 7 --max-tokens" \
            "lane-launch|$LR/L6 --owner-command" "lane-launch|$LR/L6 --host-denied" "lane-launch|$LR/L6 --resume-run" \
            "lane-answer|$LR/L6 toolu_x --owner-command" "lane-answer|$LR/L6 toolu_x --via"; do
  sub="${spec%%|*}"; args="${spec#*|}"; flag="${args##* }"
  # shellcheck disable=SC2086
  bounded 5 "$sub" $args; rc=$?
  check "W2 $sub trailing $flag exits promptly non-zero" "$(prompt_nz "$rc")" prompt-nonzero
  has "W2b $sub trailing $flag names the missing value" "$(cat "$T/bounded.out")" "$flag needs a value"
done
check "W2c lane-create left no lane behind" "$([ -e "$LR/L7" ] && echo present || echo absent)" absent
bounded 5 init-check --parallel; rc=$?
check "W2d init-check trailing --parallel keeps its refuse contract (exit 1, promptly)" "$rc:$(cat "$T/bounded.out")" "1:refuse: parallel_out_of_range"

# W3 lane-remove: an unreadable unpushed-commit count refuses (fail CLOSED), never reads as 0
run lane-create "$RF" reqs/a.md 7 >/dev/null; L7="$LR/L7"
REAL_GIT="$(command -v git)"; mkdir -p "$T/gitshim"
cat > "$T/gitshim/git" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
  if [ "\$a" = rev-list ]; then [ "\${GITSHIM_MODE:-fail}" = empty ] && exit 0; echo "fatal: shim" >&2; exit 128; fi
done
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$T/gitshim/git"
out="$(PATH="$T/gitshim:$PATH" run lane-remove "$L7")"; rc=$?
check "W3 failed rev-list count ⇒ refused" "$rc:$([ -d "$L7" ] && echo kept || echo removed)" "1:kept"
has "W3b names the unreadable count" "$out" "branch main: unpushed-commit count unreadable"
out="$(GITSHIM_MODE=empty PATH="$T/gitshim:$PATH" run lane-remove "$L7")"; rc=$?
check "W3c empty count ⇒ refused" "$rc:$([ -d "$L7" ] && echo kept || echo removed)" "1:kept"
grep -v '# UNPUSHED-UNREADABLE$' "$S" > "$MUT/automate-lanes.sh"
if ! cmp -s "$S" "$MUT/automate-lanes.sh" && bash -n "$MUT/automate-lanes.sh"; then
  PATH="$T/gitshim:$PATH" bash "$MUT/automate-lanes.sh" lane-remove "$L7" >/dev/null 2>&1
  check "W3d mutation (count guard deleted) fails OPEN — the lane is removed" "$([ -d "$L7" ] && echo kept || echo removed)" removed
else bad "W3d mutation control not built"; fi

# W4 lock holder records: a dead holder is reclaimed, a live one waited on (bounded) and never stolen,
# a foreign lock is never unlocked, a holder-less lock is reclaimed after its grace
lst() { env LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed 's/^ //; s/ $//'; }
sleep 0 & DPID=$!; wait "$DPID" 2>/dev/null
mkdir -p "$TABLE.lock"; printf '%s Mon Jan  1 00:00:00 2001\n' "$DPID" > "$TABLE.lock/holder"
bounded 10 lane-launch "$LR/L6" --host-denied 'w4 dead holder'; rc=$?
check "W4 dead holder's lock reclaimed promptly (the table write lands)" "$rc:$(tcol L6 10)" "3:w4 dead holder"
check "W4b no lock left behind" "$([ -e "$TABLE.lock" ] && echo present || echo absent)" absent
sleep 300 & HPID=$!; BG_PIDS="$BG_PIDS $HPID"
mkdir -p "$TABLE.lock"; printf '%s %s\n' "$HPID" "$(lst "$HPID")" > "$TABLE.lock/holder"
LOOMWRIGHT_LANES_LOCK_WAIT_S=2 bounded 10 lane-launch "$LR/L6" --host-denied 'w4 live holder'; rc=$?
check "W4c live holder: the waiter gives up at its bound (not still running)" "$([ "$rc" != 124 ] && echo bounded || echo hung)" bounded
check "W4d live holder's lock is never stolen" "$(tcol L6 10):$(sed -n 1p "$TABLE.lock/holder" | cut -d' ' -f1)" "w4 dead holder:$HPID"
has "W4e the waiter says the lock is busy" "$(cat "$T/bounded.out")" "lock busy"
( . "$S"; _lt_unlock "$TABLE" )
check "W4f _lt_unlock leaves another process's lock alone" "$(sed -n 1p "$TABLE.lock/holder" 2>/dev/null | cut -d' ' -f1)" "$HPID"
bash "$S" lane-launch "$LR/L6" --host-denied 'w4 after holder died' > /dev/null 2>&1 & WPID=$!
sleep 1
check "W4g a live holder is waited on" "$(kill -0 "$WPID" 2>/dev/null && echo waiting || echo done):$(tcol L6 10)" "waiting:w4 dead holder"
kill "$HPID" 2>/dev/null; wait "$HPID" 2>/dev/null
i=0; while kill -0 "$WPID" 2>/dev/null && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
check "W4h once the holder dies the waiter reclaims and writes" "$(kill -0 "$WPID" 2>/dev/null && echo hung || echo done):$(tcol L6 10)" "done:w4 after holder died"
mkdir -p "$TABLE.lock"
bounded 15 lane-launch "$LR/L6" --host-denied 'w4 holder-less'; rc=$?
check "W4i a holder-less lock (creator died before recording) is reclaimed after its grace" "$rc:$(tcol L6 10)" "3:w4 holder-less"
rm -rf "$TABLE.lock" "$TABLE.lock.reclaim"

# W5 two overlapping launches of one lane spawn exactly once (launch lock spans check → pid write)
run lane-create "$RF" reqs/b.md 8 >/dev/null; L8="$LR/L8"
n5="$(claude_calls)"
STUB_MODE=sleep LOOMWRIGHT_LANE_RECHECK_S=0 bash "$S" lane-launch "$L8" --owner-command "$OWN" > "$T/w5a.out" 2>&1 & A5=$!
STUB_MODE=sleep LOOMWRIGHT_LANE_RECHECK_S=0 bash "$S" lane-launch "$L8" --owner-command "$OWN" > "$T/w5b.out" 2>&1 & B5=$!
wait "$A5"; ra=$?; wait "$B5"; rb=$?
check "W5 two concurrent launches ⇒ exactly one spawn" "$(( $(claude_calls) - n5 ))" 1
check "W5b one launched, one refused" "$(printf '%s\n%s\n' "$ra" "$rb" | env LC_ALL=C sort | tr '\n' ' ')" "0 1 "
has "W5c the second sees the lane running" "$(cat "$T/w5a.out" "$T/w5b.out")" "already running"
check "W5d no launch lock left behind" "$(ls -d "$TABLE".L8.launch.lock 2>/dev/null | wc -l | tr -d ' ')" 0
for p in $(pgrep -f "_lane-run $L8" 2>/dev/null); do kill -TERM "$p" 2>/dev/null; done; wait_gone "$L8"

# W6 multiSelect labels that contain commas
run lane-create "$RF" reqs/b.md 9 >/dev/null; L9="$LR/L9"
Q7='[{"question":"Which shades?","header":"Shades","multiSelect":true,"options":[{"label":"Red, dark","description":"r"},{"label":"Blue","description":"b"},{"label":"Green","description":"g"}]},{"question":"Which parts?","header":"Parts","multiSelect":true,"options":[{"label":"A","description":"a"},{"label":"B","description":"b"},{"label":"A, B","description":"ab"},{"label":"C","description":"c"}]}]'
jq -n -c --argjson q "$Q7" '{id: "toolu_w6", asked_at: "2026-10-07T00:00:00Z", questions: $q}' > "$L9/.supervisor/inbox/questions/toolu_w6.json"
jq -n -c --argjson q "$Q7" '{type: "result", subtype: "success", stop_reason: "tool_deferred", session_id: "sess-w6", deferred_tool_use: {id: "toolu_w6", name: "AskUserQuestion", input: {questions: $q}}}' >> "$LR/L9.stream.log"
ans6() { printf '%s' "$1" | LOOMWRIGHT_LANE_RECHECK_S=0 bash "$S" lane-answer "$L9" toolu_w6 --owner-command "$OWN" 2>&1; }
out="$(ans6 '{"answers":{"0":"Red, dark","1":"A, B,C"}}')"; rc=$?
check "W6 an answer that splits into known labels two ways is refused" "$rc" 1
has "W6b the refusal says ambiguous" "$out" '"A, B,C" is ambiguous'
out="$(ans6 '{"answers":{"0":"Red, dark, Purple","1":"C"}}')"; rc=$?
check "W6c one unknown label still refuses the whole answer" "$rc:$(printf '%s' "$out" | grep -c '"Red, dark, Purple" is not one of its options' | tr -d ' ')" "1:1"
out="$(ans6 '{"answers":{"0":"Red","1":"C"}}')"; check "W6d half of a comma label is not a label" "$?" 1
check "W6e nothing recorded by the refusals" "$([ -e "$L9/.supervisor/inbox/answers/toolu_w6.json" ] && echo written || echo none)" none
out="$(ans6 '{"answers":{"0":"Red, dark, Blue","1":"A, B"}}')"; rc=$?
check "W6f a comma label plus another label, and a whole-answer label, are accepted" "$rc" 0
check "W6g recorded labels" "$(jq -c '[.answers["Which shades?"], .answers["Which parts?"]]' "$L9/.supervisor/inbox/answers/toolu_w6.json" 2>/dev/null)" '["Red, dark,Blue","A, B"]'
wait_gone "$L9"

# W7 lane-remove --stop runs every non-liveness refusal BEFORE stopping anything: a live lane with a
# dirty tree is refused for the dirty tree and its process is left running (never stopped-but-refused)
run lane-create "$RF" reqs/a.md 10 >/dev/null; L10="$LR/L10"
STUB_MODE=sleep LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L10" --owner-command "$OWN" >/dev/null
L10P="$(tcol L10 5)"; L10S="$(tcol L10 6)"
echo dirty >> "$L10/reqs/a.md"
out="$(run lane-remove "$L10" --stop)"; rc=$?
check "W7 --stop on a dirty live lane ⇒ refused, lane kept" "$rc:$([ -d "$L10" ] && echo kept || echo removed)" "1:kept"
has "W7b refused with the dirty-tree reason" "$out" "refused — L10 — dirty working tree"
hasnt "W7c nothing was stopped" "$out" "lane-remove: stopped"
( . "$S"; lanes_proc_alive "$L10P" "$L10S" "$L10" ); check "W7d the lane process is still alive" "$?" 0
grep -v '# REFUSE-BEFORE-STOP$' "$S" > "$MUT/automate-lanes.sh"
if ! cmp -s "$S" "$MUT/automate-lanes.sh" && bash -n "$MUT/automate-lanes.sh"; then
  out="$(bash "$MUT/automate-lanes.sh" lane-remove "$L10" --stop 2>&1)"
  has "W7e mutation (pre-stop refusal pass deleted) stops the process first" "$out" "lane-remove: stopped"
  has "W7f … and is then refused anyway (the old stopped-but-refused order)" "$out" "dirty working tree"
  check "W7g … leaving the lane process dead" "$(kill -0 "$L10P" 2>/dev/null && echo alive || echo dead)" dead
else bad "W7e mutation control not built"; fi
wait_gone "$L10"
git -C "$L10" checkout -q -- reqs/a.md
out="$(run lane-remove "$L10" --stop)"; check "W7h once clean, the stopped lane is removed" "$?:$([ -d "$L10" ] && echo kept || echo removed)" "0:removed"

# ---- X: relay hook from a linked worktree of the lane (owner fix-now FN1) -----------------------------
# A worker's worktree sits OUTSIDE the lane dir (../{repo}-{task_id}-{slug}) and holds no lane.json; the
# hook resolves the lane through the git common dir, so the question still lands in the LANE's inbox.
run lane-create "$RF" reqs/a.md 1 >/dev/null; L1="$LR/L1"
xhook() { hook_in PreToolUse "$1" "$2" | bash "${3:-$S}" relay-hook; }   # <cwd> <tool_use_id> [<script>]
hso() { jq -r -c ".hookSpecificOutput$1" <<<"$2" 2>/dev/null; }   # <field path> <hook output> — a field of the hook response
xdec() { hso .permissionDecision "$1"; }
WT="$LR/L1-42-slug"
git -C "$L1" worktree add -q -b feature/42-slug "$WT" 2>/dev/null
out="$(xhook "$WT" toolu_x1)"
check "X1 question asked from a linked worktree of the lane ⇒ defer" "$(xdec "$out")" defer
check "X2 … recorded in the LANE's inbox" "$(jq -r .id "$L1/.supervisor/inbox/questions/toolu_x1.json" 2>/dev/null)" toolu_x1
check "X3 … nothing written under the worktree" "$([ -e "$WT/.supervisor" ] && echo written || echo none)" none
out="$(xhook "$WT/reqs" toolu_x2)"
check "X4 a subdirectory of the worktree resolves to the lane too" \
  "$(xdec "$out"):$([ -s "$L1/.supervisor/inbox/questions/toolu_x2.json" ] && echo lane || echo missing)" "defer:lane"
# git < 2.31 has no --path-format: the shim echoes the flag back (as an older rev-parse does) ahead of
# the plain answer, so the hook must fall back to the toplevel-relative resolution
REAL_GIT="$(command -v git)"; mkdir -p "$T/oldgit"
cat > "$T/oldgit/git" <<EOF
#!/usr/bin/env bash
a=(); f=0
for x in "\$@"; do if [ "\$x" = --path-format=absolute ]; then f=1; else a+=("\$x"); fi; done
[ "\$f" = 1 ] && echo --path-format=absolute
exec "$REAL_GIT" "\${a[@]}"
EOF
chmod +x "$T/oldgit/git"
out="$(PATH="$T/oldgit:$PATH" xhook "$WT" toolu_x3)"
check "X5 older git (no --path-format): worktree question still reaches the lane inbox" \
  "$(xdec "$out"):$([ -s "$L1/.supervisor/inbox/questions/toolu_x3.json" ] && echo lane || echo missing)" "defer:lane"
out="$(PATH="$T/oldgit:$PATH" xhook "$L1/reqs" toolu_x4)"
check "X6 older git: a question from a lane subdirectory still reaches the lane inbox" \
  "$(xdec "$out"):$([ -s "$L1/.supervisor/inbox/questions/toolu_x4.json" ] && echo lane || echo missing)" "defer:lane"
PWT="$T/work/primary-42-slug"
git -C "$P" worktree add -q -b feature/p42 "$PWT" 2>/dev/null
check "X7 a linked worktree of a NON-lane checkout ⇒ no decision" "$(xhook "$PWT" toolu_x5)" "{}"
check "X7b … and nothing recorded anywhere" "$(ls "$PWT/.supervisor" "$P/.supervisor/inbox" 2>/dev/null | wc -l | tr -d ' ')" 0
git -C "$P" worktree remove --force "$PWT" 2>/dev/null; git -C "$P" branch -q -D feature/p42 2>/dev/null
check "X8 path-unsafe id from the worktree still ignored" "$(xhook "$WT" '../x')" "{}"
awk '/# HOOK-ROOT$/ { print "  root=\"$(git -C \"$cwd\" rev-parse --show-toplevel 2>/dev/null)\"; [ -n \"$root\" ] || root=\"$cwd\""; next } { print }' "$S" > "$MUT/automate-lanes.sh"
if ! cmp -s "$S" "$MUT/automate-lanes.sh" && bash -n "$MUT/automate-lanes.sh"; then
  check "X9 mutation (old show-toplevel resolution) ⇒ the worktree question escapes ({})" "$(xhook "$WT" toolu_x9 "$MUT/automate-lanes.sh")" "{}"
  check "X9b … and the lane inbox never sees it" "$([ -e "$L1/.supervisor/inbox/questions/toolu_x9.json" ] && echo recorded || echo none)" none
else bad "X9 mutation control not built"; fi
git -C "$L1" worktree remove --force "$WT" 2>/dev/null; git -C "$L1" branch -q -D feature/42-slug 2>/dev/null

# ---- Y: lane-convert-ready — wave-end conversion pushes the lane run file (owner fix-now FN2) ----------
# The meta-sync stub models the real status: `synced` iff the lane's run files still hash to what the
# last push recorded, else `local_ahead 1`. current-set is the REAL automate-helpers.sh.
cat > "$T/meta-conv.sh" <<'EOF'
#!/usr/bin/env bash
echo "meta-sync $*" >> "$META_LOG"
root=""; pf=""; prev=""
for a in "$@"; do case "$prev" in --root) root="$a" ;; --paths-from) pf="$a" ;; esac; prev="$a"; done
sum() { cat "$root"/.supervisor/automate/*.md 2>/dev/null | cksum; }
case "$1" in
  push)
    echo "paths: $(tr '\n' ' ' < "$pf" 2>/dev/null)" >> "$META_LOG"
    [ -n "${STUB_PUSH_FAIL:-}" ] && { echo "meta_sync: push_failed — rejected 5 times; nothing forced, meta-base untouched" >&2; exit 1; }
    sum > "$root.pushed-sum"; echo "meta_sync: pushed abc123 (1 path(s))"; exit 0 ;;
  status) if [ "$(sum)" = "$(cat "$root.pushed-sum" 2>/dev/null)" ]; then echo "synced abc123 on test-meta"; else echo "local_ahead 1"; fi; exit 0 ;;
  pull) exit 0 ;;
esac
EOF
chmod +x "$T/meta-conv.sh"
conv_rf() { # <lane_dir> <status> <pause_reason> — a lane run file parked as given, recorded as pushed
  local id; id="$(jq -r .run_id "$1/.supervisor/lane.json")"
  printf '# Automate Run: %s\n\n## Status: paused\n\n## Source\n- backlog: lane\n\n## Run Config\n- limit: 1\n\n## Queue\n- [ ] reqs/b.md\n\n## Current\n- item: reqs/b.md | status: %s | pr: https://github.com/o/r/pull/12 | branch: feature/b\n- pause_reason: %s\n\n## Progress\n- 2026-10-08T00:00:00Z drain READY → %s\n' \
    "$id" "$2" "$3" "$2" > "$1/.supervisor/automate/$id.md"
  cat "$1"/.supervisor/automate/*.md | cksum > "$1.pushed-sum"
}
conv() { LOOMWRIGHT_LANES_META_SYNC="$T/meta-conv.sh" LOOMWRIGHT_LANES_HELPERS="$HERE/automate-helpers.sh" bash "$S" lane-convert-ready "$@" 2>&1; }
rmv() { LOOMWRIGHT_LANES_META_SYNC="$T/meta-conv.sh" bash "$S" lane-remove "$@" 2>&1; }
cur_line() { awk '/^## Current/ { c = 1; next } /^## / { c = 0 } c && /^- (item|pause_reason):/' "$1" | tr '\n' '|'; }
run lane-create "$RF" reqs/b.md 4 >/dev/null; L4="$LR/L4"; RF12="$L4/.supervisor/automate/$PARENT-L4.md"
conv_rf "$L4" escalated escalated; SUM12="$(cksum < "$RF12")"; : > "$META_LOG"
out="$(conv "$L4")"; rc=$?
check "Y1 a run file not reading ready_for_release is refused (exit 1)" "$rc" 1
has "Y1b … naming what it reads" "$out" "refused — L4 — run file reads status escalated / pause_reason escalated, not ready_for_release"
check "Y1c … nothing written, nothing pushed" "$(cksum < "$RF12"):$(grep -c ' push ' "$META_LOG" | tr -d ' ')" "$SUM12:0"
conv_rf "$L4" ready_for_release ready_for_release; SUM12="$(cksum < "$RF12")"
STUB_MODE=sleep LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L4" --owner-command "$OWN" >/dev/null
L4P="$(tcol L4 5)"
out="$(conv "$L4")"; rc=$?
check "Y2 a live lane is refused (exit 1)" "$rc" 1
has "Y2b … naming the process" "$out" "refused — L4 — live lane process (pid $L4P)"
check "Y2c … nothing written, nothing pushed" "$(cksum < "$RF12"):$(grep -c ' push ' "$META_LOG" | tr -d ' ')" "$SUM12:0"
kill -TERM "$L4P" 2>/dev/null; wait_gone "$L4"
out="$(conv "$L4")"; rc=$?
check "Y3 a stopped ready_for_release lane converts (exit 0)" "$rc" 0
has "Y3b … and reports the push" "$out" "converted L4 to awaiting_merge; metadata pushed to test-meta"
check "Y3c ## Current now awaiting_merge (item, PR and branch kept)" "$(cur_line "$RF12")" \
  "- item: reqs/b.md | status: awaiting_merge | pr: https://github.com/o/r/pull/12 | branch: feature/b|- pause_reason: awaiting_merge|"
has "Y3d push passes the lane's metadata branch explicitly and its root" "$(grep ' push ' "$META_LOG")" "meta-sync push --branch test-meta --root $L4 --paths-from "
check "Y3e … and pushes exactly the lane run file" "$(grep '^paths:' "$META_LOG")" "paths: .supervisor/automate/$PARENT-L4.md "
has "Y3f ## Progress kept" "$(cat "$RF12")" "drain READY → ready_for_release"
SUM12="$(cksum < "$RF12")"
out="$(conv "$L4")"; rc=$?
check "Y4 a re-run is idempotent (exit 0, run file byte-unchanged)" "$rc:$(cksum < "$RF12")" "0:$SUM12"
has "Y4b … saying it only retries the push" "$out" "already reads awaiting_merge — retrying the metadata push"
check "Y4c no launch lock left behind" "$(ls -d "$TABLE".L4.launch.lock 2>/dev/null | wc -l | tr -d ' ')" 0
out="$(rmv "$L4")"; rc=$?
check "Y5 afterwards lane-remove's metadata check passes and the lane is removed" "$rc:$([ -d "$L4" ] && echo kept || echo removed)" "0:removed"
# a failed push: loud, exit 2, the lane never looks converted-and-pushed (lane-remove refuses), re-run heals
run lane-create "$RF" reqs/b.md 5 >/dev/null; L5="$LR/L5"; RF13="$L5/.supervisor/automate/$PARENT-L5.md"
conv_rf "$L5" ready_for_release ready_for_release
out="$(STUB_PUSH_FAIL=1 conv "$L5")"; rc=$?
check "Y6 a failed push exits 2" "$rc" 2
has "Y6b … with a FAILED line naming the lane and the retry" "$out" "lane-convert-ready: FAILED — L5 — converted to awaiting_merge, but the metadata push to test-meta failed (meta-sync exit 1); NOT pushed"
has "Y6c … relaying meta-sync's own reason" "$out" "meta_sync: push_failed"
has "Y6d … and naming the re-run" "$out" "re-run lane-convert-ready $L5"
check "Y6e no launch lock left behind" "$(ls -d "$TABLE".L5.launch.lock 2>/dev/null | wc -l | tr -d ' ')" 0
out="$(rmv "$L5")"; rc=$?
check "Y7 after a failed push lane-remove refuses (metadata not pushed)" "$rc:$(printf '%s' "$out" | grep -c 'metadata not pushed (local_ahead 1)' | tr -d ' ')" "1:1"
out="$(conv "$L5")"; rc=$?
check "Y8 the re-run pushes (exit 0)" "$rc:$(printf '%s' "$out" | grep -c 'metadata pushed to test-meta' | tr -d ' ')" "0:1"
out="$(rmv "$L5")"; rc=$?
check "Y8b … and lane-remove then passes" "$rc:$([ -d "$L5" ] && echo kept || echo removed)" "0:removed"
# metadata mode: unknown refuses before any write; off converts with nothing to push
run lane-create "$RF" reqs/b.md 10 >/dev/null; L10="$LR/L10"; RF14="$L10/.supervisor/automate/$PARENT-L10.md"
conv_rf "$L10" ready_for_release ready_for_release; SUM14="$(cksum < "$RF14")"; : > "$META_LOG"
out="$(STUB_MODE_LINE='unknown no mode line' conv "$L10")"; rc=$?
check "Y9 metadata mode unknown ⇒ refused before any write" "$rc:$(cksum < "$RF14"):$(printf '%s' "$out" | grep -c 'metadata mode unknown' | tr -d ' ')" "1:$SUM14:1"
out="$(STUB_MODE_LINE=off conv "$L10")"; rc=$?
check "Y10 mode off ⇒ converted, nothing to push" "$rc:$(grep -c ' push ' "$META_LOG" | tr -d ' ')" "0:0"
has "Y10b … reported as such" "$out" "converted L10 to awaiting_merge (metadata mode off — no metadata branch to push)"
out="$(conv "$LR/nope")"; check "Y11 not a lane ⇒ exit 1" "$?" 1
out="$(bash "$HERE/automate-helpers.sh" lane-convert-ready 2>&1)"; rc=$?
check "Y12 automate-helpers.sh dispatches lane-convert-ready (no lane ⇒ not-a-lane refusal)" "$rc:$(printf '%s' "$out" | grep -c 'lane-convert-ready: not a lane' | tr -d ' ')" "1:1"

# ---- Z: Validation 4/5 fixes (parallel-automate/23) ---------------------------------------------------
# Each leg fails against the pre-fix lane code at 91adff5 (identical to #426's head 8226dfe) and passes here.
# Z-F5 lane-readiness writes its report when the Validation names no repro (empty erows / vrows)
run lane-create "$RF" reqs/a.md 2 >/dev/null; LZ5="$LR/L2"; RDZ="$LZ5/.supervisor/automate/$PARENT-L2.merge-readiness.md"
out="$(LOOMWRIGHT_GH_BIN="$T/absent-gh" run lane-readiness "$LZ5")"; rc=$?
check "Z-F5a no named repro (empty erows) ⇒ the report IS written" "$rc:$([ -f "$RDZ" ] && echo written || echo missing)" "0:written"
has "Z-F5b … with the headline-repro n/a line" "$(cat "$RDZ" 2>/dev/null)" "headline-repro: PASS — n/a (the Validation names no repro)"
hasnt "Z-F5c … and never says unwritable" "$out" "report not written"
check "Z-F5d no stray temp file left" "$(ls "$LZ5/.supervisor/automate/" | grep -c '\.tmp\.' | tr -d ' ')" 0
chmod 555 "$LZ5/.supervisor/automate"
out="$(LOOMWRIGHT_GH_BIN="$T/absent-gh" run lane-readiness "$LZ5")"; rc=$?
chmod 755 "$LZ5/.supervisor/automate"
check "Z-F5e a genuine write failure still says unwritable (exit 0, observation)" "$rc:$(printf '%s' "$out" | grep -c 'report not written (unwritable)' | tr -d ' ')" "0:1"
check "Z-F5f … leaving no temp file" "$(ls "$LZ5/.supervisor/automate/" | grep -c '\.tmp\.' | tr -d ' ')" 0

# Z-F9 a clean wave whose lanes were all removed reads `leaks: none`; salvage + stream logs are kept.
# The wave-start snapshot is taken through lanes_leaks directly (same signature before and after the
# fix) so this leg isolates F9 from F1.
PARENT4=automate-2026-10-08-090000; RF4="$P/.supervisor/automate/$PARENT4.md"; LR4="$T/work/primary-lanes/$PARENT4"
printf '# Automate Run: %s\n\n## Progress\n' "$PARENT4" > "$RF4"
( . "$S"; lanes_leaks "$P" "$PARENT4" 1 ) >/dev/null
run lane-create "$RF4" reqs/a.md 1 --parallel 2 >/dev/null; run lane-create "$RF4" reqs/b.md 2 --parallel 2 >/dev/null
LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$LR4/L1" --owner-command "$OWN" >/dev/null; wait_gone "$LR4/L1"
LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$LR4/L2" --owner-command "$OWN" >/dev/null; wait_gone "$LR4/L2"
out="$(run lane-remove "$LR4/L1")$(run lane-remove "$LR4/L2")"
check "Z-F9a both lanes removed" "$([ -e "$LR4/L1" ] || [ -e "$LR4/L2" ] && echo present || echo absent)" absent
out="$(run lane-status "$RF4" --leaks)"
check "Z-F9b after a clean wave lane-status --leaks reads none" "$(printf '%s\n' "$out" | head -1 | cut -c1-11)" "leaks: none"
hasnt "Z-F9c … and lanes-dir is not changed" "$out" "lanes-dir: changed"
check "Z-F9d salvage kept at <primary>-lanes/<run_id>/salvage/" "$(ls -d "$LR4"/salvage/L1-removed-* "$LR4"/salvage/L2-removed-* 2>/dev/null | wc -l | tr -d ' ')" 2
check "Z-F9e stream logs kept at <primary>-lanes/<run_id>/L<n>.stream.log" "$([ -s "$LR4/L1.stream.log" ] && [ -s "$LR4/L2.stream.log" ] && echo kept)" kept
mkdir -p "$LR4/L3"; : > "$LR4/stray.txt"
out="$(run lane-status "$RF4" --leaks)"
has "Z-F9f a lane directory left behind is still a leak" "$out" "  + $PARENT4/L3"
has "Z-F9g … and so is any other file in the run directory (exact names only)" "$out" "  + $PARENT4/stray.txt"
rm -rf "$LR4/L3" "$LR4/stray.txt"

# Z-F1 §14 step 5 (snapshot) runs BEFORE step 6 (first lane-create): no <run_id>.lanes table yet
PARENT3=automate-2026-10-08-080000; RF3="$P/.supervisor/automate/$PARENT3.md"
SF3="$P/.supervisor/automate/$PARENT3.leaks-snapshot"
printf '# Automate Run: %s\n\n## Progress\n' "$PARENT3" > "$RF3"
check "Z-F1a fixture: no lane table yet" "$([ -e "$P/.supervisor/automate/$PARENT3.lanes" ] && echo table || echo none)" none
out="$(run lane-status "$RF3" --leaks --snapshot)"; rc=$?
check "Z-F1b snapshot with no lane table is written (exit 0)" "$rc:$([ -s "$SF3" ] && echo written || echo missing)" "0:written"
has "Z-F1c … and says so (never a silent 'no lanes')" "$out" "leaks: snapshot written — $SF3"
hasnt "Z-F1d … no 'no lanes' line" "$out" "no lanes"
run lane-create "$RF3" reqs/a.md 1 >/dev/null
check "Z-F1e the snapshot is the baseline the end-of-wave check reads" "$(run lane-status "$RF3" --leaks | head -1 | cut -c1-6)" "leaks:"
rm -f "$SF3"; chmod 555 "$P/.supervisor/automate"
out="$(run lane-status "$RF3" --leaks --snapshot)"; rc=$?
chmod 755 "$P/.supervisor/automate"
check "Z-F1f an unwritable snapshot exits non-zero (the one fail-SAFE exception)" "$([ "$rc" != 0 ] && echo nonzero || echo zero)" nonzero
has "Z-F1g … naming why" "$out" "leaks: snapshot not written (unwritable)"
rm -rf "$T/work/primary-lanes/$PARENT3/L1"; rm -f "$P/.supervisor/automate/$PARENT3.lanes"
chmod 555 "$P/.supervisor/automate"
out="$(run lane-status "$RF3" --leaks --snapshot)"; rc=$?
chmod 755 "$P/.supervisor/automate"
check "Z-F1h … with no lane table too" "$([ "$rc" != 0 ] && echo nonzero || echo zero):$(printf '%s' "$out" | grep -c 'snapshot not written' | tr -d ' ')" "nonzero:1"
out="$(run lane-status "$P/.supervisor/automate/absent-run.md" --leaks --snapshot)"; rc=$?
check "Z-F1i a parent run file that does not exist ⇒ non-zero, named" "$([ "$rc" != 0 ] && echo nonzero || echo zero):$(printf '%s' "$out" | grep -c 'parent run file not found' | tr -d ' ')" "nonzero:1"

# Z-F10 lane-remove --abandon writes no absolute path into the parent run file, and reports the lane's
# REAL state (lane-status's reader: a parked lane whose PR closed unmerged reads `gone`). progress-append
# is the real helper; HOME is set to the fixture root so every absolute fixture path is a $HOME path.
PARENT5=automate-2026-10-08-100000; RF5="$P/.supervisor/automate/$PARENT5.md"; LR5="$T/work/primary-lanes/$PARENT5"
printf '# Automate Run: %s\n\n## Progress\n' "$PARENT5" > "$RF5"
cat > "$T/helpers-gone.sh" <<'EOF'
#!/usr/bin/env bash
case "$1" in reconcile-item) echo gone ;; *) exec bash "$REAL_HELPERS" "$@" ;; esac
EOF
chmod +x "$T/helpers-gone.sh"; export REAL_HELPERS="$HERE/automate-helpers.sh"
run lane-create "$RF5" reqs/a.md 1 >/dev/null; L51="$LR5/L1"
LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L51" --owner-command "$OWN" >/dev/null; wait_gone "$L51"
printf '# Automate Run: %s-L1\n\n## Current\n- item: reqs/a.md | status: awaiting_merge | pr: https://github.com/o/r/pull/51 | branch: f\n- pause_reason: awaiting_merge\n\n## Progress\n' "$PARENT5" > "$L51/.supervisor/automate/$PARENT5-L1.md"
check "Z-F10a fixture: lane-status reads the lane gone" \
  "$(LOOMWRIGHT_LANES_HELPERS="$T/helpers-gone.sh" bash "$S" lane-status "$RF5" --json 2>/dev/null | jq -r '.lanes[] | select(.lane == "L1") | .state')" gone
out="$(HOME="$T" LOOMWRIGHT_LANES_HELPERS="$T/helpers-gone.sh" run lane-remove "$L51" --abandon)"; rc=$?
check "Z-F10b lane-remove --abandon removes the gone lane" "$rc:$([ -d "$L51" ] && echo kept || echo removed)" "0:removed"
ABL="$(grep 'lane abandoned: L1' "$RF5")"
has "Z-F10c the abandoned line reports the real state (gone, not the table's launched)" "$ABL" "— state gone;"
has "Z-F10d … and names the salvage in the <primary>-lanes/… form" "$ABL" "salvage kept at <primary>-lanes/$PARENT5/salvage/L1-removed-"
check "Z-F10e no line in the parent run file contains \$HOME" "$(grep -cF "$T" "$RF5" | tr -d ' ')" 0
check "Z-F10f no token in the parent run file starts with /" "$(grep -cE '(^|[[:space:]])/' "$RF5" | tr -d ' ')" 0

# Z-F4 a lane that died after its PICK resumes in its LAST session (its run.lock is session-id
# re-entrant), never a fresh one that waits out the dead session's lock; fresh only as the fallback
run lane-create "$RF5" reqs/b.md 2 >/dev/null; L52="$LR5/L2"
STUB_MODE=die LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L52" --owner-command "$OWN" >/dev/null; wait_gone "$L52"
printf '# Automate Run: %s-L2\n\n## Progress\n- picked reqs/b.md\n' "$PARENT5" > "$L52/.supervisor/automate/$PARENT5-L2.md"
check "Z-F4a fixture: the lane reads died with a recorded session" \
  "$(bash "$S" lane-status "$RF5" --json 2>/dev/null | jq -r '.lanes[] | select(.lane == "L2") | .state + " " + .session_id')" "died sess-123"
SUM52="$(lane_sum "$L52")"; n4="$(claude_calls)"
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L52" --owner-command "/automate --resume $PARENT5" --resume-run "$PARENT5-L2")"; rc=$?
wait_gone "$L52"
check "Z-F4b --resume-run launches once (exit 0)" "$rc:$(( $(claude_calls) - n4 ))" "0:1"
has "Z-F4c … resuming the lane's last session (the run lock's re-entrant path)" "$(grep '^ARGS' "$STUB_LOG" | tail -1)" "[--resume] [sess-123]"
has "Z-F4d … with the lane's own resume command" "$(grep '^STDIN' "$STUB_LOG" | tail -1)" "/loomwright:automate --resume $PARENT5-L2"
check "Z-F4e … telling the lane which path it is on (it records it in ## Progress itself)" "$(grep '^RESUMEPATH' "$STUB_LOG" | tail -1)" "RESUMEPATH session sess-123"
check "Z-F4f the coordinator wrote nothing into the lane (run file, lock)" "$(lane_sum "$L52")" "$SUM52"
n4="$(claude_calls)"
out="$(STUB_RESUME_FAIL=1 LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L52" --owner-command "/automate --resume $PARENT5" --resume-run "$PARENT5-L2")"; rc=$?
wait_gone "$L52"
check "Z-F4g an unresumable session falls back to ONE fresh session (two spawns)" "$rc:$(( $(claude_calls) - n4 ))" "0:2"
has "Z-F4h … saying so" "$out" "could not be resumed"
hasnt "Z-F4i … the fallback carries no --resume" "$(grep '^ARGS' "$STUB_LOG" | tail -1)" "[--resume]"
check "Z-F4j … and tells the lane it is on the fresh path" "$(grep '^RESUMEPATH' "$STUB_LOG" | tail -1)" "RESUMEPATH fresh session (last session sess-123 not resumable)"
has "Z-F4k a normal launch carries an empty resume path" "$(grep '^RESUMEPATH' "$STUB_LOG" | head -1)" "RESUMEPATH "

# Z-F2 a HELD answer is kept coordinator-side (validated answers + note + via, never an owner command),
# shown as answer_pending, and delivered ONLY by the delivery form under a current-session owner command
zq() { # <lane_dir> <tool_use_id> <session> — a recorded question the lane parked on (deferred)
  jq -n -c --argjson q "$Q2" --arg id "$2" '{id: $id, asked_at: "2026-10-08T00:00:00Z", questions: $q}' > "$1/.supervisor/inbox/questions/$2.json"
  jq -n -c --argjson q "$Q2" --arg id "$2" --arg s "$3" '{type: "result", subtype: "success", stop_reason: "tool_deferred", session_id: $s, deferred_tool_use: {id: $id, input: {questions: $q}}}' >> "$(dirname "$1")/$(basename "$1").stream.log"
}
t5set() { awk -F'\t' -v OFS='\t' -v l="$1" -v c="$2" -v v="$3" '$1 == l { $c = v } { print }' "$P/.supervisor/automate/$PARENT5.lanes" > "$T/t5" && mv "$T/t5" "$P/.supervisor/automate/$PARENT5.lanes"; }
run lane-create "$RF5" reqs/a.md 3 >/dev/null; L53="$LR5/L3"; zq "$L53" toolu_z2 sess-z2
t5set L3 8 launched; t5set L3 9 "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
PF53="$P/.supervisor/automate/$PARENT5.L3.answer-pending.json"; AF53="$L53/.supervisor/inbox/answers/toolu_z2.json"
z2() { printf '%s' "$1" | bash "$S" lane-answer "$L53" toolu_z2 "${@:2}" 2>&1; }
n2="$(claude_calls)"
out="$(STUB_LOAD=busy z2 '{"answers":{"0":"Red","1":"A,B"},"note":"small diff"}' --owner-command "$OWN" --via test)"; rc=$?
check "Z-F2a load busy ⇒ HELD (exit 4)" "$rc:$(printf '%s\n' "$out" | head -1)" "4:lane-launch: HELD — L3 — load busy"
check "Z-F2b the validated answer is KEPT coordinator-side (answers, note, via)" \
  "$(jq -c '[.tool_use_id, .answers["0"], .answers["1"], .note, .via]' "$PF53" 2>/dev/null)" '["toolu_z2","Red","A,B","small diff","test"]'
check "Z-F2c … and the pending file holds no owner command" "$(grep -cF "$OWN" "$PF53" 2>/dev/null | tr -d ' '):$(jq -r 'keys | map(select(test("owner"))) | length' "$PF53" 2>/dev/null)" "0:0"
check "Z-F2d nothing written into the lane, nothing spawned" "$([ -e "$AF53" ] && echo written || echo none):$(( $(claude_calls) - n2 ))" "none:0"
J="$(bash "$S" lane-status "$RF5" --json 2>/dev/null)"
check "Z-F2e lane-status shows the lane as answer_pending" "$(jq -r '.lanes[] | select(.lane == "L3") | .state' <<<"$J")" answer_pending
out="$(run lane-status "$RF5")"
has "Z-F2f … plain view names the delivery form" "$out" "L3  answer_pending"
check "Z-F2g lane-status (observation) delivered nothing, spawned nothing" "$([ -e "$AF53" ] && echo written || echo none):$(( $(claude_calls) - n2 ))" "none:0"
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 run lane-answer "$L53" --deliver-pending)"; rc=$?
check "Z-F2h a pending file with NO current-session owner command is NOT delivered (BLOCKED, exit 3)" "$rc:$(printf '%s\n' "$out" | head -1)" "3:lane-launch: BLOCKED — L3 — no owner-invoked command — need the owner"
check "Z-F2i … nothing written into the lane, nothing spawned, the answer still pending" \
  "$([ -e "$AF53" ] && echo written || echo none):$(( $(claude_calls) - n2 )):$([ -s "$PF53" ] && echo kept || echo gone)" "none:0:kept"
out="$(STUB_LOAD=busy run lane-answer "$L53" --deliver-pending --owner-command "/automate --resume $PARENT5")"; rc=$?
check "Z-F2j still busy at delivery ⇒ HELD again, pending kept" "$rc:$([ -s "$PF53" ] && echo kept || echo gone):$([ -e "$AF53" ] && echo written || echo none)" "4:kept:none"
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 run lane-answer "$L53" --deliver-pending --owner-command "/automate --resume $PARENT5")"; rc=$?
check "Z-F2k the delivery form under the poll's owner command delivers (exit 0)" "$rc:$(( $(claude_calls) - n2 ))" "0:1"
check "Z-F2l … the answer file carries the stored labels and note" "$(jq -c '[.answers["Which color?"], .answers["Which extras?"], .note]' "$AF53" 2>/dev/null)" '["Red","A,B","small diff"]'
check "Z-F2m … the pending file is gone" "$([ -e "$PF53" ] && echo kept || echo gone)" gone
has "Z-F2n … and resumes the deferred session" "$(grep '^ARGS' "$STUB_LOG" | tail -1)" "[--resume] [sess-z2]"
wait_gone "$L53"
# a planted pending file (any process that can write the primary's .supervisor/automate/) is re-checked
run lane-create "$RF5" reqs/b.md 4 >/dev/null; L54="$LR5/L4"; zq "$L54" toolu_z3 sess-z3
PF54="$P/.supervisor/automate/$PARENT5.L4.answer-pending.json"; n2="$(claude_calls)"
printf '{"lane":"L4","tool_use_id":"toolu_z3","answers":{"0":"Purple","1":"A"},"note":null,"via":"x"}\n' > "$PF54"
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 run lane-answer "$L54" --deliver-pending --owner-command "$OWN")"; rc=$?
check "Z-F2o a stored answer that is not one of the question's labels is refused" "$rc:$(printf '%s' "$out" | grep -c 'no longer matches' | tr -d ' ')" "1:1"
check "Z-F2p … nothing written into the lane, nothing spawned, the stale file discarded" \
  "$([ -e "$L54/.supervisor/inbox/answers/toolu_z3.json" ] && echo written || echo none):$(( $(claude_calls) - n2 )):$([ -e "$PF54" ] && echo kept || echo gone)" "none:0:gone"
printf '{"lane":"L4","tool_use_id":"toolu_zz","answers":{"0":"Red","1":"A"},"note":null,"via":"x"}\n' > "$PF54"
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 run lane-answer "$L54" --deliver-pending --owner-command "$OWN")"; rc=$?
check "Z-F2q a stored answer for a tool_use_id the lane is not deferred on is refused" "$rc:$([ -e "$L54/.supervisor/inbox/answers/toolu_zz.json" ] && echo written || echo none):$(( $(claude_calls) - n2 ))" "1:none:0"
# Z-F2r..w (fix-now F-1/F-4) a HELD answer sets the table's state column to held_for_load; after its
# pending file is DISCARDED the lane's question is unanswered again, so lane-status must read
# awaiting_input (the question relayed), never held_for_load (which hides it and invites a fresh launch).
t5set L4 8 launched; t5set L4 9 "$(date -u +%Y-%m-%dT%H:%M:%SZ)"; n2="$(claude_calls)"
z4() { printf '%s' "$1" | bash "$S" lane-answer "$L54" toolu_z3 "${@:2}" 2>&1; }
out="$(STUB_LOAD=busy z4 '{"answers":{"0":"Red","1":"A"}}' --owner-command "$OWN" --via 'a b;c')"; rc=$?
check "Z-F2r fixture: HELD keeps the answer; a via that is not a short client token is stored as cli" "$rc:$(jq -r '.via' "$PF54" 2>/dev/null)" "4:cli"
out="$(STUB_LOAD=busy z4 '{"answers":{"0":"Blue","1":"B"}}' --owner-command "$OWN")"; rc=$?
check "Z-F2s a second HELD answer for the same question replaces the kept one (last write wins)" "$rc:$(jq -c '[.answers["0"], .answers["1"]]' "$PF54" 2>/dev/null)" '4:["Blue","B"]'
check "Z-F2t fixture: the table's state column reads held_for_load" "$(awk -F'\t' '$1 == "L4" { print $8 }' "$P/.supervisor/automate/$PARENT5.lanes")" held_for_load
jq -c '.answers["0"] = "Purple"' "$PF54" > "$PF54.t" && mv "$PF54.t" "$PF54"
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 run lane-answer "$L54" --deliver-pending --owner-command "$OWN")"; rc=$?
check "Z-F2u fixture: the stale pending answer is discarded" "$rc:$([ -e "$PF54" ] && echo kept || echo gone):$(( $(claude_calls) - n2 ))" "1:gone:0"
J="$(bash "$S" lane-status "$RF5" --json 2>/dev/null)"
check "Z-F2v after the discard lane-status reads awaiting_input (the question shows again), not held_for_load" \
  "$(jq -r '.lanes[] | select(.lane == "L4") | .state + " " + (.questions | map(.id) | join(","))' <<<"$J")" "awaiting_input toolu_z3"
has "Z-F2w … the reason still names the last launch's hold" "$(jq -r '.lanes[] | select(.lane == "L4") | .reason' <<<"$J")" "last launch held for load: load busy"

# Z-F11 wave end with an UNMERGED done stamp: convert → PR closed unmerged → lane-remove --abandon.
# The lane is removable with no hand step, and the metadata branch (a fake remote the meta-sync stub
# keeps) never receives a done claim or a jobs/done/ brief for the unmerged work. trail-pr and its
# evidence gate are the REAL scripts (a copy whose setup-memory.sh reads branch mode on).
SC="$T/scripts-copy"; cp -R "$HERE" "$SC"
printf '#!/usr/bin/env bash\necho "on test-meta"\n' > "$SC/setup-memory.sh"
export REMOTE11="$T/remote11"; mkdir -p "$REMOTE11"
cat > "$T/meta-f11.sh" <<'EOF'
#!/usr/bin/env bash
echo "meta-sync $*" >> "$META_LOG"
root=""; pf=""; prev=""
for a in "$@"; do case "$prev" in --root) root="$a" ;; --paths-from) pf="$a" ;; esac; prev="$a"; done
managed() { (cd "$root" && find .supervisor/requirements .supervisor/jobs/done .supervisor/jobs/failed .supervisor/automate .supervisor/postmortem \
  -type f \( -name '*.md' -o -name '*.dismissed-decisions' -o -name results.jsonl \) 2>/dev/null | env LC_ALL=C sort); }
case "$1" in
  push) while IFS= read -r p; do [ -n "$p" ] || continue
          if [ -f "$root/$p" ]; then mkdir -p "$REMOTE11/$(dirname "$p")"; cp "$root/$p" "$REMOTE11/$p"; else rm -f "$REMOTE11/$p"; fi
        done < "$pf"; echo "meta_sync: pushed abc"; exit 0 ;;
  status) n=0; ps=""; for p in $(managed); do cmp -s "$root/$p" "$REMOTE11/$p" || { n=$((n + 1)); ps="$ps  $p
"; }; done
          if [ "$n" = 0 ]; then echo "synced abc on test-meta"; else echo "local_ahead $n"; case " $* " in *" --paths "*) printf '%s' "$ps" ;; esac; fi; exit 0 ;;
  pull) exit 0 ;;
esac
EOF
cat > "$T/gh-f11" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >> "$T_GH11"
case "$1 $2" in "pr view") printf '{"state":"%s","mergedAt":null}\n' "${STUB_PR_STATE:-OPEN}" ;; *) exit 1 ;; esac
EOF
chmod +x "$T/meta-f11.sh" "$T/gh-f11"; export T_GH11="$T/gh-f11.calls"
f11() { LOOMWRIGHT_LANES_META_SYNC="$T/meta-f11.sh" LOOMWRIGHT_LANES_HELPERS="$SC/automate-helpers.sh" LOOMWRIGHT_LANES_TRAIL="$SC/automate-helpers.sh" \
  LOOMWRIGHT_GH_BIN="$T/gh-f11" bash "$S" "$@" 2>&1; }
run lane-create "$RF5" reqs/a.md 5 >/dev/null; L55="$LR5/L5"; R11=".supervisor/requirements/t/x.md"; PR11="https://github.com/o/r/pull/55"
LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L55" --owner-command "$OWN" >/dev/null; wait_gone "$L55"
mkdir -p "$L55/.supervisor/requirements/t" "$L55/.supervisor/jobs/done"
printf '# x\n\n## Status: pending\n\n## Status: done\n<!-- loomwright:requirement-closeout -->\n- **PR:** %s\n' "$PR11" > "$L55/$R11"
printf '# brief\n- **Source requirement:** %s\n\n## Outcome\n- **PR:** %s\n' "$R11" "$PR11" > "$L55/.supervisor/jobs/done/2026-10-08-x.md"
printf '# Automate Run: %s-L5\n\n## Status: paused\n\n## Queue\n- [ ] %s\n\n## Current\n- item: %s | status: ready_for_release | pr: %s | branch: f\n- pause_reason: ready_for_release\n\n## Progress\n- drain READY\n' \
  "$PARENT5" "$R11" "$R11" "$PR11" > "$L55/.supervisor/automate/$PARENT5-L5.md"
printf '# Merge readiness\n- score: 3/5\n' > "$L55/.supervisor/automate/$PARENT5-L5.merge-readiness.md"
out="$(STUB_PR_STATE=OPEN f11 lane-convert-ready "$L55")"; rc=$?
check "Z-F11a wave-end conversion with the PR still open exits 0" "$rc" 0
has "Z-F11b … the gated trail names the unmerged done stamp as excluded" "$out" "excluded $R11 — pr not merged"
check "Z-F11c … and nothing on the metadata branch carries it or a done/ brief" \
  "$([ -e "$REMOTE11/$R11" ] && echo req || echo noreq):$(ls "$REMOTE11/.supervisor/jobs/done" 2>/dev/null | wc -l | tr -d ' ')" "noreq:0"
check "Z-F11d … the run file and the readiness report were pushed" \
  "$([ -f "$REMOTE11/.supervisor/automate/$PARENT5-L5.md" ] && [ -f "$REMOTE11/.supervisor/automate/$PARENT5-L5.merge-readiness.md" ] && echo pushed)" pushed
out="$(STUB_PR_STATE=OPEN f11 lane-remove "$L55")"
has "Z-F11e an open PR's lane still refuses removal (its done stamp is unpushed by design)" "$out" "metadata not pushed"
out="$(STUB_PR_STATE=CLOSED f11 lane-remove "$L55" --abandon)"; rc=$?
check "Z-F11f PR closed unmerged ⇒ lane-remove --abandon removes the lane with no hand step" "$rc:$([ -d "$L55" ] && echo kept || echo removed)" "0:removed"
EMD="$(printf '\342\200\224')"
check "Z-F11g the metadata branch holds the reconcile-status ABANDONED stamp shape" \
  "$(grep -c "^## Status: done_with_escalation $EMD ABANDONED (- \[x\] $R11  # abandoned: " "$REMOTE11/$R11" 2>/dev/null | tr -d ' ')" 1
check "Z-F11h … and no other done heading (no done claim for the unmerged PR)" \
  "$(grep -E '^## Status:[[:space:]]*done' "$REMOTE11/$R11" 2>/dev/null | grep -vc "ABANDONED (- \[x\] " | tr -d ' ')" 0
check "Z-F11i … no jobs/done/ brief; the brief rides under jobs/failed/" \
  "$(ls "$REMOTE11/.supervisor/jobs/done" 2>/dev/null | wc -l | tr -d ' '):$(ls "$REMOTE11/.supervisor/jobs/failed" 2>/dev/null | tr '\n' ' ')" "0:2026-10-08-x.md "
has "Z-F11j the parent run file records the abandon with the real state" "$(cat "$RF5")" "lane abandoned: L5 ($PARENT5-L5) — state gone;"

# ---- AA: Validation 4/5 fixes B (parallel-automate/24) ------------------------------------------------
# Each leg fails against the pre-fix code at 9a65ecb and passes here.
# AA-F12 lane-feed --follow: signalling the lane-feed process ALONE leaves no tail | grep | jq behind.
AA_TAIL="tail -n \\+1 -f $(ere "$LR2/L6.stream.log")"
aa_feed() { # <signal> — prints "<seen|unseen> <none|survivor>"; kills any survivor afterwards
  local sig="$1" fp i=0 seen=unseen
  # An async child starts with SIGINT ignored, and a suite launched under `nohup` (a detached
  # ci-local / harness run) passes SIGHUP down ignored too — and bash cannot trap a signal that was
  # ignored on entry, so HUP then never reached lane-feed's trap and AA-F12b read "survivor" 50/50
  # (iq02 T07). Reset BOTH to default before exec, as a terminal would deliver them.
  python3 -c 'import os, signal, sys; signal.signal(signal.SIGINT, signal.SIG_DFL); signal.signal(signal.SIGHUP, signal.SIG_DFL); os.execvp(sys.argv[1], sys.argv[1:])' \
    bash "$S" lane-feed "$L6" --follow > "$T/aa-follow.$sig" 2>&1 & fp=$!
  # Clock-bounded (wait-lib), not count-bounded: AA-F12b went red under a loaded pool (iq02 T07).
  wait_for_cmd 15 pgrep -f "$AA_TAIL" 2>/dev/null && seen=seen
  sleep 0.3; kill -"$sig" "$fp" 2>/dev/null   # fixed-sleep-ok: settle — the pipeline's traps installed before the signal (too short ⇒ a different, earlier-kill path is tested)
  wait_for_pid_gone "$fp" 10 2>/dev/null
  kill -KILL "$fp" 2>/dev/null; wait "$fp" 2>/dev/null   # bounded: a lane-feed that ignores the signal never hangs the suite
  _aa_no_tail() { ! pgrep -f "$AA_TAIL" >/dev/null 2>&1; }
  wait_for_cmd 10 _aa_no_tail 2>/dev/null
  if pgrep -f "$AA_TAIL" >/dev/null 2>&1; then echo "$seen survivor"; pkill -TERM -f "$AA_TAIL" 2>/dev/null; else echo "$seen none"; fi
}
check "AA-F12a TERM to lane-feed --follow alone ⇒ its tail pipeline is gone (and the escaped pattern did see it)" "$(aa_feed TERM)" "seen none"
check "AA-F12b HUP ⇒ the same" "$(aa_feed HUP)" "seen none"
check "AA-F12c INT ⇒ the same" "$(aa_feed INT)" "seen none"
has "AA-F12d the follow still narrates" "$(cat "$T/aa-follow.TERM")" "[spawn] loomwright:worker"
check "AA-F12e the unescaped pattern T8 used never matched a live tail (the root cause, not the path)" \
  "$(bash "$S" lane-feed "$L6" --follow >/dev/null 2>&1 & fp=$!
     # first prove the tail IS up (the escaped pattern sees it), so `unmatched` cannot pass on a slow start
     if wait_for_cmd 15 pgrep -f "$AA_TAIL" 2>/dev/null; then
       pgrep -f "tail -n +1 -f $LR2/L6.stream.log" >/dev/null 2>&1 && echo matched || echo unmatched
     else echo "tail-never-up"; fi
     kill "$fp" 2>/dev/null; wait "$fp" 2>/dev/null; pkill -TERM -f "$AA_TAIL" 2>/dev/null)" unmatched

# AA fixture: one lane (L1) of a fresh parent run, its run file at the ready_for_release park.
PARENT6=automate-2026-10-08-110000; RF6="$P/.supervisor/automate/$PARENT6.md"; LR6="$T/work/primary-lanes/$PARENT6"
printf '# Automate Run: %s\n\n## Progress\n' "$PARENT6" > "$RF6"
run lane-create "$RF6" reqs/a.md 1 --parallel 2 --max-tokens 200 >/dev/null; L61="$LR6/L1"; LRF6="$L61/.supervisor/automate/$PARENT6-L1.md"
PR6="https://github.com/o/r/pull/66"
printf '# Automate Run: %s-L1\n\n## Status: paused\n\n## Queue\n- [ ] reqs/a.md\n\n## Current\n- item: reqs/a.md | status: ready_for_release | pr: %s | branch: f\n- pause_reason: ready_for_release\n\n## Progress\n- 2026-10-08T11:00:00Z session_id sess-aa (reqs/a.md)\n' \
  "$PARENT6" "$PR6" > "$LRF6"
# AA-F8 a lane whose log holds a real (transcript-usage) ledger line reads a non-zero TOTAL, and its share parks.
mkdir -p "$T/subagents"; AAT="$T/subagents/agent-aa1.jsonl"   # the agent's OWN transcript name — the emitter sums only agent-<agent_id>.jsonl
{ for o in 8 8; do printf '{"type":"assistant","message":{"id":"msg_A","stop_reason":null,"usage":{"input_tokens":10,"output_tokens":%s,"cache_read_input_tokens":100,"cache_creation_input_tokens":50,"cache_creation":{"ephemeral_5m_input_tokens":50}}}}\n' "$o"; done
  echo '{"type":"assistant","message":{"id":"msg_A","stop_reason":"end_turn","usage":{"input_tokens":10,"output_tokens":263,"cache_read_input_tokens":100,"cache_creation_input_tokens":50}}}'
  echo '{"type":"assistant","message":{"id":"msg_B","stop_reason":null,"usage":{"input_tokens":7,"output_tokens":40,"cache_read_input_tokens":200,"cache_creation_input_tokens":0}}}'
} > "$AAT"
jq -n --arg a "$AAT" '{session_id: "sess-aa", agent_id: "aa1", agent_transcript_path: $a}' \
  | (cd "$L61" && env -u LOOMWRIGHT_ORIENTATION_SOURCE -u LOOMWRIGHT_SHARED_PREFIX -u LOOMWRIGHT_ADVISORY_TOTAL_BYTES bash "$HERE/emit-token-ledger.sh")
check "AA-F8a the real emitter wrote a transcript-usage line into the lane's log" \
  "$(jq -r '"\(.usage_source) \(.output_tokens)"' "$L61/.supervisor/logs/sess-aa.jsonl" 2>/dev/null)" "transcript 303"
out="$(run lane-status "$RF6" --tokens)"
check "AA-F8b lane-status --tokens: the lane's TOTAL is non-zero (the real reader)" \
  "$(printf '%s\n' "$out" | awk '$1 == "L1"' | grep -oE 'TOTAL=[0-9]+')" "TOTAL=670"
check "AA-F8c ceiling-check on the lane run file with a share below that total ⇒ PARK" \
  "$(cd "$L61" && bash "$HERE/automate-helpers.sh" ceiling-check "$LRF6" 100)" "PARK: token_ceiling total=670 max=100"


# AA-F6 lane-park-notify: desktop + automate_ready_for_release webhook, one truthful ## Progress line.
cat > "$T/aa-nd.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$(cat)" >> "$AA_ND_LOG"
[ -n "${STUB_ND_AUDIT:-}" ] && { mkdir -p .supervisor/logs; echo "2026-10-08T11:00:00Z notify group=loomwright-x tool_use_id=-" >> .supervisor/logs/notifications.log; }
exit 0
EOF
cat > "$T/aa-sw.sh" <<'EOF'
#!/usr/bin/env bash
echo "dry=${LOOMWRIGHT_WEBHOOK_DRY_RUN:-} $*" >> "$AA_SW_LOG"
case "${STUB_SW:-none}" in
  ignored) echo "repo_webhook_ignored slug=o/r" >&2 ;;
  configured) [ -n "${LOOMWRIGHT_WEBHOOK_DRY_RUN:-}" ] && echo '{"event_type":"gate"}' ;;
esac
exit 0
EOF
chmod +x "$T/aa-nd.sh" "$T/aa-sw.sh"; export AA_ND_LOG="$T/aa-nd.log" AA_SW_LOG="$T/aa-sw.log"
# `desktop: sent` also needs the platform notifier notify-desktop.sh dispatches to, so the host's own
# PATH must not decide these legs: pn pins the OS (AA_UNAME, default Darwin) and prepends a stub
# osascript + notify-send (never executed — only probed with `command -v`). AA_PATH replaces the
# whole PATH for the no-notifier leg (AA-F6m); AA_ND swaps the notifier stub (AA-F6r/s).
mkdir -p "$T/aa-bin"; printf '#!/usr/bin/env bash\nexit 0\n' > "$T/aa-bin/osascript"; cp "$T/aa-bin/osascript" "$T/aa-bin/notify-send"
chmod +x "$T/aa-bin/osascript" "$T/aa-bin/notify-send"
pn() { : > "$AA_ND_LOG"; : > "$AA_SW_LOG"; PATH="${AA_PATH:-$T/aa-bin:$PATH}" LOOMWRIGHT_LANES_UNAME="${AA_UNAME:-Darwin}" \
  LOOMWRIGHT_LANES_HELPERS="$HERE/automate-helpers.sh" LOOMWRIGHT_LANES_NOTIFY_DESKTOP="${AA_ND:-$T/aa-nd.sh}" \
  LOOMWRIGHT_LANES_SEND_WEBHOOK="$T/aa-sw.sh" bash "$S" lane-park-notify "$@" 2>&1; }
pcount() { grep -c 'lane park notify: ready_for_release' "$LRF6" | tr -d ' '; }
out="$(STUB_SW=ignored STUB_ND_AUDIT=1 LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 pn "$LRF6")"; rc=$?
check "AA-F6a webhook ignored ⇒ exit 0, ONE ## Progress line" "$rc:$(pcount)" "0:1"
has "AA-F6b … the line names the delivered desktop channel" "$(grep 'lane park notify' "$LRF6")" "desktop: sent;"
has "AA-F6c … and says the webhook was ignored, with the reason" "$(grep 'lane park notify' "$LRF6")" "webhook: ignored (repo_webhook_ignored slug=o/r — no user-scope egress grant)"
check "AA-F6d the desktop payload: automate_ready_for_release, the do-not-merge message" \
  "$(jq -r '"\(.hook_event_name) \(.notification_type) \(.message | test("^https://github.com/o/r/pull/66 READY — do not merge yet — wave open"))"' "$AA_ND_LOG")" \
  "Notification automate_ready_for_release true"
check "AA-F6e an ignored webhook is only probed (dry run), never posted" "$(grep -c '^dry= ' "$AA_SW_LOG" | tr -d ' ')" 0
has "AA-F6f … with gate type automate_ready_for_release" "$(cat "$AA_SW_LOG")" "--gate-type automate_ready_for_release --context https://github.com/o/r/pull/66 READY — do not merge yet — wave open"
out="$(STUB_SW=configured STUB_ND_AUDIT=1 LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 LOOMWRIGHT_NOTIFY_DEBOUNCE=0 pn "$LRF6")"
has "AA-F6g webhook configured ⇒ posted once, reported as attempted (never 'sent': its HTTP result is unreported)" \
  "$(grep -c '^dry= --event-type gate --gate-type automate_ready_for_release' "$AA_SW_LOG" | tr -d ' '):$out" "1:lane-park-notify: lane park notify: ready_for_release ($PARENT6-L1) — desktop: sent; webhook: attempted"
out="$(STUB_SW=none LOOMWRIGHT_DESKTOP_NOTIFICATIONS=0 pn "$LRF6")"
check "AA-F6h desktop opted out ⇒ disabled, the notifier not run; no webhook ⇒ not configured" \
  "$(wc -l < "$AA_ND_LOG" | tr -d ' '):${out#*— }" "0:desktop: disabled (LOOMWRIGHT_DESKTOP_NOTIFICATIONS=0); webhook: not configured"
out="$(STUB_SW=none LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 pn "$LRF6")"
has "AA-F6i the notifier wrote no audit line ⇒ suppressed, never sent" "$out" "desktop: suppressed (no audit line"
check "AA-F6j one ## Progress line per run (four runs, four lines)" "$(pcount)" 4
# AA-F6m..p `sent` is claimed only when a platform notifier exists: notify-desktop.sh writes its audit
# line on EVERY host before its platform dispatch, so the audit line alone proves no banner.
# The no-notifier PATH is a symlink farm of the host's PATH minus the three notifiers it can dispatch to.
mkdir -p "$T/aa-nonotify-bin"
_aa_ifs="$IFS"; IFS=:
for _aa_d in $PATH; do
  [ -d "$_aa_d" ] || continue
  for _aa_f in "$_aa_d"/*; do
    _aa_n="${_aa_f##*/}"
    case "$_aa_n" in osascript|terminal-notifier|notify-send) continue ;; esac
    [ -x "$_aa_f" ] && [ ! -e "$T/aa-nonotify-bin/$_aa_n" ] && ln -s "$_aa_f" "$T/aa-nonotify-bin/$_aa_n" 2>/dev/null
  done
done
IFS="$_aa_ifs"
out="$(AA_PATH="$T/aa-nonotify-bin" STUB_SW=none STUB_ND_AUDIT=1 LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 pn "$LRF6")"; rc=$?
check "AA-F6m audit line written but no OS notifier on PATH (Darwin) ⇒ failed, never sent; exit 0" \
  "$rc:${out#*— }" "0:desktop: failed (no OS notifier on PATH); webhook: not configured"
has "AA-F6n … and the ## Progress line says the same" "$(grep 'lane park notify' "$LRF6" | tail -1)" "desktop: failed (no OS notifier on PATH);"
out="$(AA_PATH="$T/aa-nonotify-bin" AA_UNAME=Linux STUB_SW=none STUB_ND_AUDIT=1 LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 pn "$LRF6")"
has "AA-F6o Linux without notify-send ⇒ failed (no OS notifier on PATH)" "$out" "desktop: failed (no OS notifier on PATH);"
out="$(AA_UNAME=Linux STUB_SW=none STUB_ND_AUDIT=1 LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 DISPLAY= WAYLAND_DISPLAY= pn "$LRF6")"
has "AA-F6p Linux notify-send present but no display ⇒ failed (no display for notify-send) — notify-desktop.sh skips it there" \
  "$out" "desktop: failed (no display for notify-send);"
out="$(AA_UNAME=Linux STUB_SW=none STUB_ND_AUDIT=1 LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 DISPLAY=:0 pn "$LRF6")"
has "AA-F6q Linux notify-send + DISPLAY ⇒ sent" "$out" "desktop: sent;"
# AA-F6r..t Darwin with terminal-notifier but NO osascript: notify-desktop.sh uses terminal-notifier only
# when its click action is not `none` (resolved by the notify-click-target.sh beside it), else falls
# through to the osascript branch — so terminal-notifier alone counts only with a click action.
mkdir -p "$T/aa-tn-bin" "$T/aa-ndc"; cp "$T/aa-bin/osascript" "$T/aa-tn-bin/terminal-notifier"
cp "$T/aa-nd.sh" "$T/aa-ndc/notify-desktop.sh"; ln -s "$HERE/notify-click-target.sh" "$T/aa-ndc/notify-click-target.sh"
chmod +x "$T/aa-tn-bin/terminal-notifier" "$T/aa-ndc/notify-desktop.sh"
out="$(AA_PATH="$T/aa-tn-bin:$T/aa-nonotify-bin" AA_ND="$T/aa-ndc/notify-desktop.sh" LOOMWRIGHT_NOTIFY_CLICK=off \
  STUB_SW=none STUB_ND_AUDIT=1 LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 pn "$LRF6")"
has "AA-F6r Darwin terminal-notifier only, click action none (LOOMWRIGHT_NOTIFY_CLICK=off) ⇒ failed (no OS notifier on PATH), never sent" \
  "$out" "desktop: failed (no OS notifier on PATH);"
out="$(AA_PATH="$T/aa-tn-bin:$T/aa-nonotify-bin" AA_ND="$T/aa-ndc/notify-desktop.sh" LOOMWRIGHT_NOTIFY_CLICK=activate \
  STUB_SW=none STUB_ND_AUDIT=1 LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 pn "$LRF6")"
has "AA-F6s Darwin terminal-notifier only, click action set (activate) ⇒ sent" "$out" "desktop: sent;"
out="$(AA_PATH="$T/aa-tn-bin:$T/aa-nonotify-bin" LOOMWRIGHT_NOTIFY_CLICK=activate \
  STUB_SW=none STUB_ND_AUDIT=1 LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 pn "$LRF6")"
has "AA-F6t Darwin terminal-notifier only, no notify-click-target.sh beside the notifier (action none) ⇒ failed" \
  "$out" "desktop: failed (no OS notifier on PATH);"
out="$(LOOMWRIGHT_LANES_NOTIFY_DESKTOP="$T/aa-nd.sh" LOOMWRIGHT_LANES_SEND_WEBHOOK="$T/aa-sw.sh" LOOMWRIGHT_DESKTOP_NOTIFICATIONS=0 \
  bash "$HERE/automate-helpers.sh" lane-park-notify "$LRF6" 2>&1)"; rc=$?
check "AA-F6k dispatched through automate-helpers.sh" "$rc:$(printf '%s' "$out" | grep -c '^lane-park-notify: lane park notify:' | tr -d ' ')" "0:1"
sed 's/status: ready_for_release/status: awaiting_merge/; s/pause_reason: ready_for_release/pause_reason: awaiting_merge/' "$LRF6" > "$T/aa-notpark.md"
mkdir -p "$L61/.supervisor/automate"; cp "$T/aa-notpark.md" "$L61/.supervisor/automate/aa-notpark.md"
out="$(STUB_SW=configured LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 pn "$L61/.supervisor/automate/aa-notpark.md")"; rc=$?
check "AA-F6l not at the ready_for_release park ⇒ skipped: exit 0, nothing sent, no line written" \
  "$rc:$(wc -l < "$AA_ND_LOG" | tr -d ' '):$(wc -l < "$AA_SW_LOG" | tr -d ' '):$(cmp -s "$T/aa-notpark.md" "$L61/.supervisor/automate/aa-notpark.md" && echo unchanged)" "0:0:0:unchanged"

# ---- AB: a merged lane is closed out by lane-convert-ready's re-run (automate-followups/38) ----------
# lane-convert-ready on `ready_for_release` converts with NO closeout; its `awaiting_merge` re-run runs
# `closeout <run file> <item> <## Current pr> --no-trail` inside the lane, under the launch lock and
# BEFORE the pushes (evidence-gated: an OPEN PR ⇒ nothing written); a MERGED re-run stamps the
# requirement, checks the item off, reconciles ## Current to done / awaiting_go and the wave-end push
# carries all of it; a re-run after that (`done` / `awaiting_go`) retries only the pushes. The scripts
# are the REAL copy $SC (branch mode on, Z-F11); a spy dispatcher in front of it records every call.
cat > "$T/ab-gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >> "$T_ABGH"
st="${STUB_PR_STATE:-OPEN}"; ma=null; [ "$st" = MERGED ] && ma='"2026-10-10T00:00:00Z"'
case "$1 $2" in
  "auth status") exit 0 ;;
  "pr view") printf '{"state":"%s","mergedAt":%s,"headRefName":"feature/ab","headRefOid":"1111111111111111111111111111111111111111"}\n' "$st" "$ma" ;;
  *) exit 1 ;;
esac
EOF
cat > "$T/ab-spy.sh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "\$T_ABSPY"
[ "\$1" = closeout ] && echo "CC=\${CLAUDECODE-unset} PID=\${CLAUDE_PID-unset}" >> "\$T_ABENV"
[ "\$1" = closeout ] && echo "closeout HOLDER=\${LOOMWRIGHT_HOLDER_PID-unset} SELF=\$\$" >> "\$T_ABHOLD"
exec bash "$SC/automate-helpers.sh" "\$@"
EOF
chmod +x "$T/ab-gh" "$T/ab-spy.sh"; export T_ABGH="$T/ab-gh.calls" T_ABSPY="$T/ab-spy.log" T_ABENV="$T/ab-spy.env"; mkdir -p "$T/remote-ab"
# The finalize-empty half of the holder pin (AC 9): a helpers shim that records LOOMWRIGHT_HOLDER_PID and
# its own pid for finalize-empty, then execs the real helper; setup-memory.sh beside it forwards (the
# lane reads finalize-empty's mode through `dirname "$HELPERS"`). Used only where AB_HELPERS names it.
export T_ABHOLD="$T/ab-spy.holder"; mkdir -p "$T/abh"
cat > "$T/abh/automate-helpers.sh" <<EOF
#!/usr/bin/env bash
[ "\$1" = finalize-empty ] && echo "finalize-empty HOLDER=\${LOOMWRIGHT_HOLDER_PID-unset} SELF=\$\$" >> "\$T_ABHOLD"
exec bash "$SC/automate-helpers.sh" "\$@"
EOF
printf '#!/usr/bin/env bash\nexec bash "%s/setup-memory.sh" "$@"\n' "$SC" > "$T/abh/setup-memory.sh"
chmod +x "$T/abh/automate-helpers.sh" "$T/abh/setup-memory.sh"
# holder_pinned <label> — every recorded HOLDER is numeric and equals that process's own SELF pid.
holder_pinned() { awk -v l="$1" '$1 == l { n++; h = $2; s = $3; sub(/^HOLDER=/, "", h); sub(/^SELF=/, "", s); if (h !~ /^[0-9]+$/ || h != s) bad++ }
  END { print ((n > 0 && !bad) ? "pinned" : "unpinned(" n + 0 "," bad + 0 ")") }' "$T_ABHOLD" 2>/dev/null; }
ab() { REMOTE11="$T/remote-ab" LOOMWRIGHT_LANES_META_SYNC="$T/meta-f11.sh" LOOMWRIGHT_LANES_HELPERS="${AB_HELPERS:-$SC/automate-helpers.sh}" \
  LOOMWRIGHT_LANES_TRAIL="$T/ab-spy.sh" LOOMWRIGHT_GH_BIN="$T/ab-gh" bash "$S" "$@" 2>&1; }
# ab_lane <n> <item> <pr> — a launched-then-exited lane holding <item> pending (its af/37-shaped prose
# quotes the sentinel inline) and a jobs/done/ brief pointing at it.
ab_lane() {
  run lane-create "$RF5" reqs/a.md "$1" >/dev/null; ABL="$LR5/L$1"; ABRF="$ABL/.supervisor/automate/$PARENT5-L$1.md"
  LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$ABL" --owner-command "$OWN" >/dev/null; wait_gone "$ABL"
  mkdir -p "$ABL/$(dirname "$2")" "$ABL/.supervisor/jobs/done"
  printf '# ab\n\n## Status: pending\n\n## Problem\nThe old guard matched `<!-- loomwright:requirement-closeout -->` quoted in prose.\n' > "$ABL/$2"
  printf '# brief\n- **Source requirement:** %s\n\n## Outcome\n- **PR:** %s\n' "$2" "$3" > "$ABL/.supervisor/jobs/done/2026-10-10-L$1.md"
}
ab_rf() { # <runfile> <lane n> <item> <pr> <status> <pause_reason>
  printf '# Automate Run: %s-L%s\n\n## Status: paused\n\n## Source\n- backlog: lane\n\n## Run Config\n- limit: 1\n\n## Queue\n- [ ] %s\n\n## Current\n- item: %s | status: %s | pr: %s | branch: feature/ab\n- pause_reason: %s\n\n## Progress\n- 2026-10-10T00:00:00Z drain READY\n' \
    "$PARENT5" "$2" "$3" "$3" "$5" "$4" "$6" > "$1"
}
RAB=".supervisor/requirements/t/ab.md"; PRAB="https://github.com/o/r/pull/57"
ab_lane 7 "$RAB" "$PRAB"; L57="$ABL"; RFAB="$ABRF"
ab_rf "$RFAB" 7 "$RAB" "$PRAB" ready_for_release ready_for_release
: > "$T_ABSPY"; QAB="$(cksum < "$L57/$RAB")"
out="$(STUB_PR_STATE=OPEN ab lane-convert-ready "$L57")"; rc=$?
check "AB1 ready_for_release converts (exit 0) to awaiting_merge" "$rc:$(cur_line "$RFAB")" \
  "0:- item: $RAB | status: awaiting_merge | pr: $PRAB | branch: feature/ab|- pause_reason: awaiting_merge|"
check "AB1b … with NO closeout call (spy) and no done stamp" "$(grep -c '^closeout ' "$T_ABSPY" | tr -d ' '):$(cksum < "$L57/$RAB")" "0:$QAB"
SAB="$(cksum < "$RFAB")"; : > "$T_ABENV"
out="$(CLAUDECODE=1 CLAUDE_PID=$$ STUB_PR_STATE=OPEN ab lane-convert-ready "$L57")"; rc=$?
check "AB2 awaiting_merge re-run, PR still OPEN: exit 0, closeout called once with --no-trail inside the lane" \
  "$rc:$(grep -cxF "closeout $RFAB $RAB $PRAB --no-trail" "$T_ABSPY" | tr -d ' ')" "0:1"
has "AB2b … its evidence gate line echoed indented" "$out" "  closeout: skipped — pr not merged (awaiting_merge)"
check "AB2c … nothing written (requirement + run file byte-unchanged)" "$(cksum < "$L57/$RAB"):$(cksum < "$RFAB")" "$QAB:$SAB"
has "AB2d … the push still names the unmerged exclusion" "$out" "/2026-10-10-L7.md — pr not merged"
has "AB2e … and the last line names the gate leftover" "$(printf '%s\n' "$out" | tail -n1)" "; closeout leftover: gate — skipped — pr not merged (awaiting_merge)"
# AB2f the lane closeout is a FRESH run-lock acquire (no --session-id), so it runs with the host identity
# unset, as the merge watcher does — else a crashed closeout's lock would name the coordinator as holder.
check "AB2f … and that closeout ran with the host identity vars unset (coordinator had them set)" "$(cat "$T_ABENV")" "CC=unset PID=unset"
check "AB2g … and its LOOMWRIGHT_HOLDER_PID is the closeout process's own pid (the run-lock holder pin)" "$(holder_pinned closeout)" pinned
: > "$T_ABHOLD"
out="$(AB_HELPERS="$T/abh/automate-helpers.sh" STUB_PR_STATE=MERGED ab lane-convert-ready "$L57")"; rc=$?
printf '%s\n' "$out" | sed 's/^/       | /'
check "AB3 merged re-run exits 0 and its last line reads closeout complete" "$rc:$(printf '%s\n' "$out" | tail -n1 | grep -c '; closeout complete$' | tr -d ' ')" "0:1"
has "AB3b … closeout stamped the lane's requirement (a quoted sentinel is not a stamp)" "$out" "  closeout: stamped — $RAB"
has "AB3c … ran with --no-trail" "$out" "  trail-pr: skipped — --no-trail"
hasnt "AB3d … and the wave-end push no longer excludes the requirement" "$out" "excluded $RAB — pr not merged"
check "AB3e the lane requirement carries ONE sentinel-led ## Status: done" \
  "$(grep -A1 -xF '<!-- loomwright:requirement-closeout -->' "$L57/$RAB" | tr '\n' '|'):$(grep -cE '^## Status:[[:space:]]*done' "$L57/$RAB" | tr -d ' ')" \
  "<!-- loomwright:requirement-closeout -->|## Status: done|:1"
# AB3f/AB3g/AB4b — parallel-automate/21 A1: the merged re-run now also runs finalize-empty (branch mode),
# which writes `## Status: done` and `pause_reason: null`; before A1 the lane stayed done / awaiting_go.
check "AB3f the lane run file reads - [x] <item> and ## Current done (no current-set after closeout; A1 finalize ⇒ pause_reason null)" \
  "$(grep -cxF -- "- [x] $RAB" "$RFAB" | tr -d ' '):$(cur_line "$RFAB")" "1:- item: $RAB | status: done | pr: $PRAB | branch: feature/ab|- pause_reason: null|"
check "AB3g the PUSHED run file carries both" \
  "$(grep -cxF -- "- [x] $RAB" "$T/remote-ab/.supervisor/automate/$PARENT5-L7.md" 2>/dev/null | tr -d ' '):$(cur_line "$T/remote-ab/.supervisor/automate/$PARENT5-L7.md" 2>/dev/null)" \
  "1:- item: $RAB | status: done | pr: $PRAB | branch: feature/ab|- pause_reason: null|"
check "AB3h the PUSHED requirement carries the done stamp" "$(grep -cE '^## Status:[[:space:]]*done' "$T/remote-ab/$RAB" 2>/dev/null | tr -d ' ')" 1
check "AB3k the merged re-run's closeout AND its NAME=VALUE-led finalize-empty each ran with LOOMWRIGHT_HOLDER_PID = their own pid" \
  "$(holder_pinned closeout):$(holder_pinned finalize-empty)" "pinned:pinned"
ab_co="$(grep -n '^closeout ' "$T_ABSPY" | tail -n1 | cut -d: -f1)"; ab_tp="$(grep -n '^trail-pr ' "$T_ABSPY" | tail -n1 | cut -d: -f1)"
check "AB3i closeout ran BEFORE the wave-end trail push (spy order)" "$([ -n "$ab_co" ] && [ -n "$ab_tp" ] && [ "$ab_co" -lt "$ab_tp" ] && echo before)" before
check "AB3j no launch lock left behind" "$(ls -d "$P/.supervisor/automate/$PARENT5.lanes".L7.launch.lock 2>/dev/null | wc -l | tr -d ' ')" 0
SAB="$(cksum < "$RFAB")"; nco="$(grep -c '^closeout ' "$T_ABSPY" | tr -d ' ')"; : > "$META_LOG"
out="$(STUB_PR_STATE=MERGED ab lane-convert-ready "$L57")"; rc=$?
check "AB4 a re-run on a closed-out (A1: finalized) lane is NOT refused (exit 0)" "$rc" 0
has "AB4b … it names that state and retries only the pushes" "$out" "already closed out and finalized (## Status: done) — retrying the metadata push only"
check "AB4c … no second closeout, no current-set (run file byte-unchanged), the pushes ran" \
  "$(grep -c '^closeout ' "$T_ABSPY" | tr -d ' '):$(cksum < "$RFAB"):$(grep -c ' push ' "$META_LOG" | tr -d ' ')" "$nco:$SAB:2"
out="$(ab lane-status "$RF5")"; rc=$?
check "AB5 lane-status reads the closed-out lane without error" "$rc:$(printf '%s\n' "$out" | grep -c 'L7' | tr -d ' ' | sed 's/^[1-9][0-9]*$/seen/')" "0:seen"
out="$(ab lane-park-notify "$RFAB")"; rc=$?
check "AB5b lane-park-notify keeps skipping a non-ready_for_release file" "$rc:$(printf '%s' "$out" | grep -c '^lane-park-notify: skipped — ' | tr -d ' ')" "0:1"
out="$(ab lane-remove "$L57")"; rc=$?
check "AB5c lane-remove passes after the closed-out lane's push and removes it" "$rc:$([ -d "$L57" ] && echo kept || echo removed)" "0:removed"
# AB6 a closeout leftover inside the lane (its sync refused: the lane clone is on another branch) is
# echoed and named in the last line, and never changes the exit code; the stamp still lands.
RAB8=".supervisor/requirements/t/ab8.md"; PRAB8="https://github.com/o/r/pull/58"
ab_lane 8 "$RAB8" "$PRAB8"; L58="$ABL"; RFAB8="$ABRF"
git -C "$L58" checkout -q -b scratch
ab_rf "$RFAB8" 8 "$RAB8" "$PRAB8" awaiting_merge awaiting_merge
out="$(STUB_PR_STATE=MERGED ab lane-convert-ready "$L58")"; rc=$?
check "AB6 a closeout sync leftover in the lane keeps exit 0" "$rc" 0
has "AB6b … the sync skip is echoed indented" "$out" "  closeout: skipped — primary checkout is on scratch (neither main nor the PR head)"
has "AB6c … and named in the last line" "$(printf '%s\n' "$out" | tail -n1)" "; closeout leftover: sync — skipped — primary checkout is on scratch (neither main nor the PR head)"
check "AB6d … the requirement is still stamped" "$(grep -cE '^## Status:[[:space:]]*done' "$L58/$RAB8" | tr -d ' ')" 1

# AB7 an awaiting_merge re-run whose ## Current carries no pr: closeout is not run, and the last line says so.
RAB9=".supervisor/requirements/t/ab9.md"
ab_lane 9 "$RAB9" "-"; L59="$ABL"; RFAB9="$ABRF"
ab_rf "$RFAB9" 9 "$RAB9" null awaiting_merge awaiting_merge
nco="$(grep -c '^closeout ' "$T_ABSPY" | tr -d ' ')"
out="$(STUB_PR_STATE=MERGED ab lane-convert-ready "$L59")"; rc=$?
check "AB7 no ## Current pr ⇒ exit 0, no closeout call" "$rc:$(grep -c '^closeout ' "$T_ABSPY" | tr -d ' ')" "0:$nco"
has "AB7b … and the last line says closeout was not run" "$(printf '%s\n' "$out" | tail -n1)" "; closeout not run (## Current has no pr)"
# AB8 metadata mode off: the merged re-run still closes the lane out; the mode-off line gains only the summary.
RAB10=".supervisor/requirements/t/ab10.md"; PRAB10="https://github.com/o/r/pull/60"
ab_lane 10 "$RAB10" "$PRAB10"; L510="$ABL"; RFAB10="$ABRF"
ab_rf "$RFAB10" 10 "$RAB10" "$PRAB10" awaiting_merge awaiting_merge
out="$(STUB_MODE_LINE=off STUB_PR_STATE=MERGED ab lane-convert-ready "$L510")"; rc=$?
check "AB8 mode off: the merged re-run exits 0 with the mode-off line (naming the state it reads) + the closeout summary" "$rc:$(printf '%s\n' "$out" | tail -n1)" \
  "0:lane-convert-ready: L10 reads done / awaiting_go (a re-run converts nothing) (metadata mode off — no metadata branch to push); closeout complete"
check "AB8b … and the lane requirement is stamped" "$(grep -cE '^## Status:[[:space:]]*done' "$L510/$RAB10" | tr -d ' ')" 1

# ---- AC: a lane whose run wrote an Orchestrator task plan is removable with no hand push -------------
# Operator-run 2026-10-10 Phase 0.2: the plan (`.supervisor/requirements/<slug>-plan.md`, a meta-managed
# path) rode neither wave-end push, so after a "closeout complete" re-run lane-remove still refused
# `metadata not pushed (local_ahead 1)` until a hand meta-sync push. Same real scripts as AB; the stub's
# status counts EVERY managed file that differs from its fake remote, as the real status does.
ac() { REMOTE11="$T/remote-ac" LOOMWRIGHT_LANES_META_SYNC="$T/meta-f11.sh" LOOMWRIGHT_LANES_HELPERS="$SC/automate-helpers.sh" \
  LOOMWRIGHT_LANES_TRAIL="$T/ab-spy.sh" LOOMWRIGHT_GH_BIN="$T/ab-gh" bash "${AC_S:-$S}" "$@" 2>&1; }
PARENT6=automate-2026-10-10-090000; RF6="$P/.supervisor/automate/$PARENT6.md"; LR6="$T/work/primary-lanes/$PARENT6"
printf '# Automate Run: %s\n\n## Progress\n' "$PARENT6" > "$RF6"
ac_lane() { # <n> <pr> — an AB-shaped lane (own parent) at ready_for_release whose run also wrote a task plan
  local rq=".supervisor/requirements/t/ac$1.md"
  run lane-create "$RF6" reqs/a.md "$1" >/dev/null; ABL="$LR6/L$1"; ABRF="$ABL/.supervisor/automate/$PARENT6-L$1.md"
  LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$ABL" --owner-command "$OWN" >/dev/null; wait_gone "$ABL"
  mkdir -p "$ABL/.supervisor/requirements/t" "$ABL/.supervisor/jobs/done"
  printf '# ac\n\n## Status: pending\n' > "$ABL/$rq"
  printf '# brief\n- **Source requirement:** %s\n\n## Outcome\n- **PR:** %s\n' "$rq" "$2" > "$ABL/.supervisor/jobs/done/2026-10-10-ac$1.md"
  printf '# Automate Run: %s-L%s\n\n## Status: paused\n\n## Source\n- backlog: lane\n\n## Run Config\n- limit: 1\n\n## Queue\n- [ ] %s\n\n## Current\n- item: %s | status: ready_for_release | pr: %s | branch: feature/ac\n- pause_reason: ready_for_release\n\n## Progress\n- 2026-10-10T00:00:00Z drain READY\n' \
    "$PARENT6" "$1" "$rq" "$rq" "$2" > "$ABRF"
  printf '# Task Plan: ac%s\n\n## EPIC ac%s\n- [x] **ac%s-1** do it\n' "$1" "$1" "$1" > "$ABL/.supervisor/requirements/ac$1-plan.md"
}
mkdir -p "$T/remote-ac"; PAC="https://github.com/o/r/pull/61"; PLAC=".supervisor/requirements/ac1-plan.md"
ac_lane 1 "$PAC"; L511="$ABL"
printf '# claim\n\n## Status: done\n- **PR:** %s\n' "$PAC" > "$L511/.supervisor/requirements/claimed-plan.md"
out="$(STUB_PR_STATE=OPEN ac lane-convert-ready "$L511")"; rc=$?
check "AC1 wave-end conversion (PR open) exits 0 and pushes the task plan with the non-claim files" \
  "$rc:$(cmp -s "$L511/$PLAC" "$T/remote-ac/$PLAC" && echo pushed)" "0:pushed"
check "AC1b … a *-plan.md carrying a done heading is a claim: never on the exact list" \
  "$([ -e "$T/remote-ac/.supervisor/requirements/claimed-plan.md" ] && echo pushed || echo kept-local)" kept-local
rm -f "$L511/.supervisor/requirements/claimed-plan.md"
out="$(STUB_PR_STATE=MERGED ac lane-convert-ready "$L511")"; rc=$?
check "AC2 the merged re-run closes out (exit 0, closeout complete)" "$rc:$(printf '%s\n' "$out" | tail -n1 | grep -c '; closeout complete$' | tr -d ' ')" "0:1"
has "AC2b … and its last line names the state the lane now reads, not a conversion" "$(printf '%s\n' "$out" | tail -n1)" \
  "lane-convert-ready: L1 reads done / awaiting_go (a re-run converts nothing); metadata pushed to test-meta"
hasnt "AC2c … never 'converted … to awaiting_merge' on a re-run" "$(printf '%s\n' "$out" | tail -n1)" "converted L1 to awaiting_merge"
out="$(ac lane-remove "$L511")"; rc=$?
check "AC3 lane-remove then removes the lane — no hand meta-sync push" "$rc:$([ -d "$L511" ] && echo kept || echo removed)" "0:removed"
has "AC3b … reading lane-remove: removed" "$out" "lane-remove: removed L1 "
# AC4 mutation control: the same lane lifecycle with the task-plan line dropped from the exact list
# reproduces the incident — closeout complete, then lane-remove refuses on the one unpushed plan.
sed 's|"\$LN_DIR"/.supervisor/requirements/\*-plan.md ||' "$S" > "$MUT/automate-lanes.sh"
check "AC4a mutation removed the task-plan glob from the non-claim list" "$(grep -c 'requirements/\*-plan.md' "$MUT/automate-lanes.sh" | tr -d ' ')" 0
ac_lane 2 "https://github.com/o/r/pull/62"; L512="$ABL"
AC_S="$MUT/automate-lanes.sh" STUB_PR_STATE=OPEN ac lane-convert-ready "$L512" >/dev/null
out="$(AC_S="$MUT/automate-lanes.sh" STUB_PR_STATE=MERGED ac lane-convert-ready "$L512")"
has "AC4b mutation: the merged re-run still reads closeout complete" "$(printf '%s\n' "$out" | tail -n1)" "; closeout complete"
out="$(AC_S="$MUT/automate-lanes.sh" ac lane-remove "$L512")"; rc=$?
check "AC4c mutation: lane-remove refuses on the unpushed plan (the 2026-10-10 incident)" \
  "$rc:$(printf '%s' "$out" | grep -c 'metadata not pushed (local_ahead 1)' | tr -d ' ')" "1:1"

# ---- AK: a lane whose worker filed a proposed/ requirement is removable; an unpushed path is NAMED ----
# Wave W4 (run automate-2026-10-11-182243): L2's worker filed its out-of-scope follow-up as
# `.supervisor/requirements/proposed/twin-remediation-11-…md` (## Status: proposed). It rode neither
# wave-end push (the exact list had no proposed/ entry; trail-pr carries only this run's dismissed
# drafts), so fleet-closeout printed `waiting — L2 metadata not pushed (local_ahead 1)` forever and the
# coordinator found the file by a hand list-managed diff. Same real scripts and fake remote as AC.
AKD=".supervisor/requirements/proposed/twin-remediation-11-loomwright-root-migration.md"
AKC=".supervisor/requirements/proposed/ak-claimed.md"
ak_files() { # <lane dir> — the filed draft (its body names the lane: the fake remote is shared, so two
  # lanes' identical drafts would read as already pushed), plus a done-headed one (a claim: never listed)
  printf '# twin-remediation/11 — LOOMWRIGHT_ROOT migration\n\n## Status: proposed\n\n## Problem\nfiled by the %s worker\n' "${1##*/}" > "$1/$AKD"
  printf '# claim\n\n## Status: done\n- **PR:** %s\n' "$PAC" > "$1/$AKC"
}
mkdir -p "$T/remote-ac/.supervisor/requirements/proposed"; : > "$T/remote-ac/.supervisor/requirements/proposed/pulled.md"
ac_lane 3 "https://github.com/o/r/pull/63"; L513="$ABL"; mkdir -p "$L513/.supervisor/requirements/proposed"; ak_files "$L513"
: > "$L513/.supervisor/requirements/proposed/pulled.md"   # a draft the lane only pulled (same bytes as the branch): never unpushed
out="$(STUB_PR_STATE=OPEN ac lane-convert-ready "$L513")"; rc=$?
check "AK1 wave-end conversion (PR open) exits 0 and pushes the worker-filed proposed/ draft" \
  "$rc:$(cmp -s "$L513/$AKD" "$T/remote-ac/$AKD" && echo pushed)" "0:pushed"
check "AK1b … a done-headed proposed/ file is a claim: never on the exact list" \
  "$([ -e "$T/remote-ac/$AKC" ] && echo pushed || echo kept-local)" kept-local
out="$(STUB_PR_STATE=MERGED ac lane-convert-ready "$L513")"; rc=$?
check "AK2 the merged re-run closes out (exit 0, closeout complete)" "$rc:$(printf '%s\n' "$out" | tail -n1 | grep -c '; closeout complete$' | tr -d ' ')" "0:1"
out="$(ac lane-remove "$L513")"; rc=$?
check "AK3 lane-remove refuses on the one unpushed (claim) file and NAMES it" \
  "$rc:$(printf '%s\n' "$out" | grep -cxF "lane-remove: refused — L3 — metadata not pushed (local_ahead 1) — paths: $AKC" | tr -d ' ')" "1:1"
out="$(ac fleet-closeout "$RF6")"
has "AK3b … and fleet-closeout's waiting line names the path (no hand list-managed diff)" "$out" \
  "fleet-closeout: waiting — L3 metadata not pushed (local_ahead 1) — paths: $AKC"
rm -f "$L513/$AKC"
out="$(ac lane-remove "$L513")"; rc=$?
check "AK4 with the claim gone lane-remove removes the lane — the filed draft needed no hand push" "$rc:$([ -d "$L513" ] && echo kept || echo removed)" "0:removed"
# AK5 mutation control: the proposed/ glob dropped from the non-claim list reproduces wave W4 — the
# filed draft never reaches the branch and lane-remove refuses on it (still named).
sed 's| "\$LN_DIR"/.supervisor/requirements/proposed/\*.md||' "$S" > "$MUT/automate-lanes.sh"
check "AK5a mutation removed the proposed/ glob" "$(grep -c 'requirements/proposed/\*.md; do$' "$MUT/automate-lanes.sh" | tr -d ' ')" 0
ac_lane 4 "https://github.com/o/r/pull/64"; L514="$ABL"; mkdir -p "$L514/.supervisor/requirements/proposed"; ak_files "$L514"; rm -f "$L514/$AKC"
AC_S="$MUT/automate-lanes.sh" STUB_PR_STATE=OPEN ac lane-convert-ready "$L514" >/dev/null
AC_S="$MUT/automate-lanes.sh" STUB_PR_STATE=MERGED ac lane-convert-ready "$L514" >/dev/null
out="$(AC_S="$MUT/automate-lanes.sh" ac lane-remove "$L514")"; rc=$?
check "AK5b mutation: lane-remove refuses on the unpushed filed draft (the wave W4 incident)" \
  "$rc:$(printf '%s\n' "$out" | grep -cF "metadata not pushed (local_ahead 1) — paths: $AKD" | tr -d ' ')" "1:1"
# AK6 mutation control: without `--paths` on lane-remove's status read the refusal names nothing (the
# pre-fix line) — so AK3 / AK3b are what pin the naming.
sed 's|--root "\$LN_DIR" --paths 2>|--root "$LN_DIR" 2>|' "$S" > "$MUT/automate-lanes.sh"
check "AK6a mutation dropped --paths from the status read" "$(grep -cF -- '--root "$LN_DIR" --paths 2>' "$MUT/automate-lanes.sh" | tr -d ' ')" 0
out="$(AC_S="$MUT/automate-lanes.sh" ac lane-remove "$L514")"; rc=$?
check "AK6b mutation: the refusal reads the bare pre-fix line, no path named" \
  "$rc:$(printf '%s\n' "$out" | grep -c 'metadata not pushed (local_ahead 1)$' | tr -d ' ')" "1:1"

# ---- AD: policy carry (B5), relay-hook policy apply (B6), no policy ⇒ unchanged (B10), digest + inbox (B7)
# lane-policy.sh is the REAL script (Subtask 1); the policies are a wave-policy file and a project policy
# file written in this suite's own temp primary. HELPERS is the logging stub (progress-append recorded).
PARENT8=automate-2026-10-10-100000; RF8="$P/.supervisor/automate/$PARENT8.md"; LR8="$T/work/primary-lanes/$PARENT8"
printf '# Automate Run: %s\n\n## Progress\n' "$PARENT8" > "$RF8"
out="$(run lane-create "$RF8" reqs/a.md 1)"; L81="$LR8/L1"
check "AD1 no project / wave policy ⇒ lane.json carries \"policy\": null (B10)" \
  "$(jq -c '[has("policy"), .policy]' "$L81/.supervisor/lane.json")" "[true,null]"
has "AD1b … and lane-create says policy=none" "$out" "policy=none"
printf '{"schema_version":1,"run_id":"%s","answers":{"AUT-QUEUE":"Process","AUT-RESUME":"Continue"},"set_at":"2026-10-10T00:00:00Z"}\n' \
  "$PARENT8" > "$P/.supervisor/automate/$PARENT8.wave-policy.json"
out="$(run lane-create "$RF8" reqs/b.md 2)"; L82="$LR8/L2"; SHA82="$(jq -r '.policy.policy_sha // empty' "$L82/.supervisor/lane.json")"
check "AD2 the owner's wave policy is carried into lane.json (answers, a sha256, its source)" \
  "$(jq -c '[.policy.answers, (.policy.policy_sha | test("^[0-9a-f]{64}$")), [.policy.sources[].kind]]' "$L82/.supervisor/lane.json")" \
  '[{"AUT-QUEUE":"Process","AUT-RESUME":"Continue"},true,["wave"]]'
check "AD2b … lane.json's other keys keep their meaning" \
  "$(jq -c '[.schema_version, .lane, .run_id, .parent_run_id, .primary, .parallel, .max_tokens]' "$L82/.supervisor/lane.json")" \
  "[1,\"L2\",\"$PARENT8-L2\",\"$PARENT8\",\"$P\",2,null]"
has "AD2c … lane-create names the carried policy" "$out" "policy=${SHA82:0:12}:2"
mkdir -p "$P/.agent"; printf '{"schema_version":1,"answers":{"AUT-QUEUE":"Stop"}}\n' > "$P/.agent/lane-policy.json"
out="$(run lane-create "$RF8" reqs/a.md 3)"
has "AD3 an unstamped project policy is reported on lane-create's stderr (never applied)" "$out" "lane-policy: project policy ignored — "
check "AD3b … the lane carries the wave policy only (Process, not the project's Stop)" \
  "$(jq -c '[.policy.answers["AUT-QUEUE"], [.policy.sources[].kind]]' "$LR8/L3/.supervisor/lane.json")" '["Process",["wave"]]'
rm -rf "$P/.agent"
QQ='[{"question":"Process the queue?","header":"AUT-QUEUE","multiSelect":false,"options":[{"label":"Process (Recommended)","description":"p"},{"label":"Stop","description":"s"}]}]'
QR='[{"question":"Resume the run?","header":"AUT-RESUME","multiSelect":false,"options":[{"label":"Continue","description":"c"},{"label":"Start new","description":"n"},{"label":"Archive","description":"a"}]}]'
QH='[{"question":"Clean up the leftover?","header":"AUT-LEFTOVER","multiSelect":false,"options":[{"label":"Clean up now","description":"c"},{"label":"Keep and continue","description":"k"},{"label":"Stop","description":"s"}]}]'
QM="$(jq -c -n --argjson a "$QQ" --argjson b "$Q2" '$a + [$b[0]]')"
DEFER="$J2_DEFER"
check "AD0 the defer reference (J2's output) is exactly one PreToolUse defer object" \
  "$(xdec "$DEFER"):$(jq -c '[length, (.[] | [.hookEventName, .permissionDecision, length])]' <<<"$DEFER")" 'defer:[1,["PreToolUse","defer",2]]'
qhook() { hook_in PreToolUse "$1" "$2" "$3"; }
ad_ans() { [ -e "$1/.supervisor/inbox/answers/$2.json" ] && echo answered || echo none; }
: > "$HELPERS_LOG"
out="$(qhook "$L82" toolu_p1 "$QQ" | bash "$S" relay-hook)"
check "AD4 an allowed coded gate with a carried policy answer ⇒ allow (no defer, no resume)" "$(xdec "$out")" allow
check "AD4b … updatedInput.answers carries the question's OWN label (marker kept)" \
  "$(hso .updatedInput.answers "$out")" '{"Process the queue?":"Process (Recommended)"}'
check "AD4c answer file: source policy, via policy, gate, the carried policy_sha, no note" \
  "$(jq -c --arg sha "$SHA82" '[.source, .via, .gate, (.policy_sha == $sha), .note, (.at | test("Z$")), .answers["Process the queue?"]]' "$L82/.supervisor/inbox/answers/toolu_p1.json")" \
  '["policy","policy","AUT-QUEUE",true,null,true,"Process (Recommended)"]'
check "AD4d … the question file is recorded as today" "$(jq -r '[.id, (.questions | length)] | map(tostring) | join(",")' "$L82/.supervisor/inbox/questions/toolu_p1.json")" "toolu_p1,1"
has "AD4e one lane ## Progress line through progress-append" "$(cat "$HELPERS_LOG")" \
  "progress-append $L82/.supervisor/automate/$PARENT8-L2.md policy answer: AUT-QUEUE → Process (Recommended) (policy_sha ${SHA82:0:12})"
has "AD4f … and the allow reason names the policy, not the owner" "$(hso .permissionDecisionReason "$out")" "answered by the stamped lane policy (gate AUT-QUEUE"
out="$(qhook "$L82" toolu_p2 "$Q2" | bash "$S" relay-hook)"
check "AD5 a question with no catalog code ⇒ exactly today's defer, no answer file" "$out:$(ad_ans "$L82" toolu_p2)" "$DEFER:none"
out="$(qhook "$L82" toolu_p3 "$QM" | bash "$S" relay-hook)"
check "AD6 a multi-question call with one human question ⇒ defer (never a partial answer)" "$out:$(ad_ans "$L82" toolu_p3)" "$DEFER:none"
out="$(qhook "$L82" toolu_p4 "$QH" | bash "$S" relay-hook)"
check "AD7 a human-only gate ⇒ defer" "$out:$(ad_ans "$L82" toolu_p4)" "$DEFER:none"
out="$(qhook "$L81" toolu_p5 "$QQ" | bash "$S" relay-hook)"
check "AD8 the same allowed gate in a lane carrying \"policy\": null ⇒ defer (B10)" "$out:$(ad_ans "$L81" toolu_p5)" "$DEFER:none"
cp "$L82/.supervisor/lane.json" "$T/ad-lane.json"
jq -c '.policy.answers["AUT-QUEUE"] = "Stop"' "$T/ad-lane.json" > "$L82/.supervisor/lane.json"
out="$(qhook "$L82" toolu_p6 "$QQ" | bash "$S" relay-hook)"
check "AD9 a carried policy edited inside the lane (sha no longer matches) ⇒ defer" "$out:$(ad_ans "$L82" toolu_p6)" "$DEFER:none"
cp "$T/ad-lane.json" "$L82/.supervisor/lane.json"
check "AD9b a lane with no lane.json policy key at all reads like null (pre-21 lane) ⇒ defer" \
  "$(jq -c 'del(.policy)' "$T/ad-lane.json" > "$L82/.supervisor/lane.json"; qhook "$L82" toolu_p7 "$QQ" | bash "$S" relay-hook):$(ad_ans "$L82" toolu_p7)" "$DEFER:none"
cp "$T/ad-lane.json" "$L82/.supervisor/lane.json"
out="$(qhook "$L82" toolu_p8 "$QR" | bash "$S" relay-hook)"
check "AD10 a second allowed gate is answered too" "$(hso '.updatedInput.answers["Resume the run?"]' "$out")" Continue
jq -c '.at = "2026-10-10T01:00:00Z"' "$L82/.supervisor/inbox/answers/toolu_p1.json" > "$T/ad.a" && mv "$T/ad.a" "$L82/.supervisor/inbox/answers/toolu_p1.json"
jq -c '.at = "2026-10-10T02:00:00Z"' "$L82/.supervisor/inbox/answers/toolu_p8.json" > "$T/ad.a" && mv "$T/ad.a" "$L82/.supervisor/inbox/answers/toolu_p8.json"
out="$(run lane-status "$RF8")"
has "AD11 lane-status: one policy digest line for the lane with policy answers (B7)" "$out" \
  "    policy: 2 answered by policy since 2026-10-10T01:00:00Z — last AUT-RESUME → Continue 2026-10-10T02:00:00Z"
hasnt "AD11b … and no 'none answered' header while a lane has one" "$out" "policy: none answered"
check "AD11c --json carries the digest" "$(run lane-status "$RF8" --json | jq -c '.lanes[] | select(.lane == "L2") | .policy | [.answered, .first_at, .last_gate, .last_label]')" \
  '[2,"2026-10-10T01:00:00Z","AUT-RESUME","Continue"]'
check "AD11d no lane with a policy answer ⇒ the header line 'policy: none answered'" "$(run lane-status "$RF" | sed -n 2p)" "policy: none answered"
i=0; for f in "$L82"/.supervisor/inbox/questions/*.json "$L81"/.supervisor/inbox/questions/*.json; do
  i=$((i + 1)); case "$f" in */toolu_p5.json) at="2026-10-10T00:00:01Z" ;; *) at="2026-10-10T00:00:1${i}Z" ;; esac
  jq -c --arg at "$at" '.asked_at = $at' "$f" > "$T/ad.q" && mv "$T/ad.q" "$f"
done
out="$(run lane-status "$RF8" --inbox)"
check "AD12 --inbox: ONE list of pending human questions, oldest asked_at first" "$(printf '%s\n' "$out" | sed -n '1,3p')" \
  "lane-status: inbox — 6 pending human question call(s), oldest first
2026-10-10T00:00:01Z L1 toolu_p5 AUT-QUEUE — Process the queue?
    options: Process (Recommended) | Stop"
hasnt "AD12b … a policy-answered question is not in the inbox" "$out" "toolu_p1"
hasnt "AD12c … nor the second one" "$out" "toolu_p8"
has "AD12d … a multi-question call lists each question" "$out" "L2 toolu_p3 Color — Which color?"
check "AD12e … every pending call appears, in asked_at order" "$(printf '%s\n' "$out" | awk '/^2026/ { print $3 }' | uniq | tr '\n' ' ')" \
  "toolu_p5 toolu_p2 toolu_p3 toolu_p4 toolu_p6 toolu_p7 "
check "AD12f a lane-status --inbox with no lane table is fail-SAFE (exit 0)" "$(run lane-status "$T/none.md" --inbox >/dev/null; echo $?)" 0

# ---- AE: lane-convert-ready finalizes a closed-out lane (A1) -----------------------------------------
# The AB scripts (real closeout / finalize-empty / trail-pr, branch mode on in $SC) on lanes of a fresh
# parent. Mode on ⇒ ONE `finalize —` line, before the last, and `## Status: done` is pushed; a re-run is a
# no-op finalize; mode off ⇒ `finalize skipped — metadata mode off` and the lane stays paused.
PARENT9=automate-2026-10-10-110000; RF9="$P/.supervisor/automate/$PARENT9.md"; LR9="$T/work/primary-lanes/$PARENT9"
printf '# Automate Run: %s\n\n## Progress\n' "$PARENT9" > "$RF9"; mkdir -p "$T/remote-ae"
ae() { REMOTE11="$T/remote-ae" LOOMWRIGHT_LANES_META_SYNC="$T/meta-f11.sh" LOOMWRIGHT_LANES_HELPERS="$SC/automate-helpers.sh" \
  LOOMWRIGHT_LANES_TRAIL="$T/ab-spy.sh" LOOMWRIGHT_GH_BIN="$T/ab-gh" bash "$S" "$@" 2>&1; }
ae_lane() { # <parent_rf> <lanes_root> <n> <req> <pr> <status> [<item>] — a launched-then-exited lane at <status>
  local id="$(basename "$1" .md)-L$3"
  run lane-create "$1" "${7:-reqs/a.md}" "$3" >/dev/null; ABL="$2/L$3"; ABRF="$ABL/.supervisor/automate/$id.md"
  LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$ABL" --owner-command "$OWN" >/dev/null; wait_gone "$ABL"
  mkdir -p "$ABL/$(dirname "$4")" "$ABL/.supervisor/jobs/done"
  printf '# req\n\n## Status: pending\n' > "$ABL/$4"
  printf '# brief\n- **Source requirement:** %s\n\n## Outcome\n- **PR:** %s\n' "$4" "$5" > "$ABL/.supervisor/jobs/done/2026-10-10-$id.md"
  printf '# Automate Run: %s\n\n## Status: paused\n\n## Source\n- backlog: lane\n\n## Run Config\n- limit: 1\n\n## Queue\n- [ ] %s\n\n## Current\n- item: %s | status: %s | pr: %s | branch: feature/ae\n- pause_reason: %s\n\n## Progress\n- 2026-10-10T00:00:00Z drain READY\n' \
    "$id" "$4" "$4" "$6" "$5" "$6" > "$ABRF"
}
ae_lane "$RF9" "$LR9" 1 ".supervisor/requirements/t/ae1.md" "https://github.com/o/r/pull/91" awaiting_merge; L91="$ABL"; RF91="$ABRF"
out="$(STUB_PR_STATE=MERGED ae lane-convert-ready "$L91")"; rc=$?
check "AE1 merged re-run, branch mode on: exit 0 and ONE finalize line" "$rc:$(printf '%s\n' "$out" | grep -c '^lane-convert-ready: finalize' | tr -d ' ')" "0:1"
has "AE1b … it carries finalize-empty's own line" "$out" "lane-convert-ready: finalize — finalize-empty: finalized $RF91"
check "AE1c … printed BEFORE the last line, which still names closeout's state and the summary" \
  "$(printf '%s\n' "$out" | tail -n2 | head -1 | grep -c '^lane-convert-ready: finalize — ' | tr -d ' '):$(printf '%s\n' "$out" | tail -n1 | grep -c 'reads done / awaiting_go (a re-run converts nothing); metadata pushed to test-meta — .*; closeout complete$' | tr -d ' ')" \
  "1:1"
check "AE1d the lane run file reads ## Status: done (and an auto-finalized Progress line)" \
  "$(grep -c '^## Status: done' "$RF91" | tr -d ' '):$(grep -c 'auto-finalized: queue empty after closeout' "$RF91" | tr -d ' ')" "1:1"
check "AE1e … and the PUSHED run file is byte-identical to it (finalize ran before the pushes)" \
  "$(cmp -s "$RF91" "$T/remote-ae/.supervisor/automate/$PARENT9-L1.md" && echo same)" same
SAE="$(cksum < "$RF91")"
out="$(STUB_PR_STATE=MERGED ae lane-convert-ready "$L91")"; rc=$?
check "AE2 a re-run on the finalized lane: exit 0, finalize is a no-op, run file byte-unchanged" \
  "$rc:$(printf '%s\n' "$out" | grep -c '^lane-convert-ready: finalize — finalize-empty: skipped — not paused$' | tr -d ' '):$(cksum < "$RF91")" "0:1:$SAE"
out="$(ae lane-remove "$L91")"; rc=$?
check "AE3 the finalized lane is removable (its metadata is in sync)" "$rc:$([ -d "$L91" ] && echo kept || echo removed)" "0:removed"
ae_lane "$RF9" "$LR9" 2 ".supervisor/requirements/t/ae2.md" "https://github.com/o/r/pull/92" awaiting_merge; L92="$ABL"; RF92="$ABRF"
out="$(STUB_MODE_LINE=off STUB_PR_STATE=MERGED ae lane-convert-ready "$L92")"; rc=$?
check "AE4 mode off: the merged re-run says finalize skipped (it would open a trail PR)" \
  "$rc:$(printf '%s\n' "$out" | grep -cxF 'lane-convert-ready: finalize skipped — metadata mode off' | tr -d ' ')" "0:1"
check "AE4b … and the lane stays ## Status: paused at done / awaiting_go" "$(grep -c '^## Status: paused' "$RF92" | tr -d ' '):$(cur_line "$RF92" | sed 's/.*|- //')" "1:pause_reason: awaiting_go|"
out="$(STUB_MODE_LINE=off STUB_PR_STATE=MERGED ae lane-convert-ready "$L92")"; rc=$?
has "AE4c a mode-off re-run on done / awaiting_go names that state (the pre-A1 path, still reachable)" "$out" \
  "already closed out (## Current done / awaiting_go) — retrying the metadata push only"
check "AE4d … and skips finalize again" "$rc:$(printf '%s\n' "$out" | grep -c 'finalize skipped — metadata mode off' | tr -d ' ')" "0:1"
check "AE5 a ## Current done / null lane whose ## Status is NOT done is refused (exit 1, nothing written)" \
  "$(sed -i.bak 's/^- pause_reason: awaiting_go$/- pause_reason: null/' "$RF92"; S0="$(cksum < "$RF92")"; ae lane-convert-ready "$L92" >/dev/null; echo "$?:$([ "$(cksum < "$RF92")" = "$S0" ] && echo same)")" "1:same"
rm -f "$RF92.bak"

# ---- AF: fleet-closeout — the stepwise, idempotent wave close (A2) -----------------------------------
# Two lanes; the owner merges L1's PR, then L2's. Real helpers / closeout / finalize / run-lock; gh is a
# stub keyed per PR (AF_MERGED / AF_CLOSED / AF_NOHEAD) that also answers the `ci` check-runs read.
cat > "$T/af-gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >> "$T_AFGH"
case "$1" in
  auth) exit 0 ;;
  pr) if [ "$2" = list ]; then   # the dry sweep's read: `pr list --state all --head <B> --json …`
        if [ -n "${AF_SWEPT_OID:-}" ] && [ "$6" = feature/af-swept ]; then
          printf '[{"number":7,"state":"MERGED","headRefOid":"%s","mergedAt":"2026-10-10T00:00:00Z"}]\n' "$AF_SWEPT_OID"
        else echo '[]'; fi
        exit 0
      fi
      [ "$2" = view ] || exit 1
      st=OPEN; case " ${AF_MERGED:-} " in *" $3 "*) st=MERGED ;; esac; case " ${AF_CLOSED:-} " in *" $3 "*) st=CLOSED ;; esac
      ma=null; [ "$st" = MERGED ] && ma='"2026-10-10T00:00:00Z"'
      n="${3##*/}"; oid="$(printf '%040d' "$n")"; case " ${AF_NOHEAD:-} " in *" $3 "*) oid="" ;; esac
      printf '{"state":"%s","mergedAt":%s,"headRefName":"feature/af%s","headRefOid":"%s"}\n' "$st" "$ma" "$n" "$oid" ;;
  api) case "$2" in
         */check-runs*) printf '{"check_runs":[{"name":"ci","conclusion":"%s","started_at":"2026-10-10T00:00:00Z"}]}\n' "${AF_CI:-success}" ;;
         *) exit 1 ;;
       esac ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$T/af-gh"; export T_AFGH="$T/af-gh.calls"; mkdir -p "$T/remote-af"
af() { REMOTE11="$T/remote-af" LOOMWRIGHT_LANES_META_SYNC="$T/meta-f11.sh" LOOMWRIGHT_LANES_HELPERS="$SC/automate-helpers.sh" \
  LOOMWRIGHT_LANES_TRAIL="$T/ab-spy.sh" LOOMWRIGHT_GH_BIN="$T/af-gh" bash "$S" "$@" 2>&1; }
PARENT10=automate-2026-10-10-120000; RF10="$P/.supervisor/automate/$PARENT10.md"; LR10="$T/work/primary-lanes/$PARENT10"
printf '# Automate Run: %s\n\n## Status: running\n\n## Run Config\n- parallel: 2\n\n## Queue\n- [ ] reqs/a.md\n- [ ] reqs/b.md\n\n## Current\n- item: null | status: null\n- wave: 1 | items: reqs/a.md, reqs/b.md\n\n## Progress\n' "$PARENT10" > "$RF10"
af lane-status "$RF10" --leaks --snapshot >/dev/null
bash "$HERE/run-lock.sh" acquire --owner "automate-lanes:$PARENT10" --root "$P" >/dev/null 2>&1
PR101="https://github.com/o/r/pull/101"; PR102="https://github.com/o/r/pull/102"
ae_lane "$RF10" "$LR10" 1 ".supervisor/requirements/t/af1.md" "$PR101" awaiting_merge; L101="$ABL"; RF101="$ABRF"
ae_lane "$RF10" "$LR10" 2 ".supervisor/requirements/t/af2.md" "$PR102" awaiting_merge reqs/b.md; L102="$ABL"
# a new commit on origin/main, so the primary sync has something to pull
git clone -q "$ORIGIN" "$T/af-other" 2>/dev/null; echo c > "$T/af-other/c.txt"; git -C "$T/af-other" add c.txt
git -C "$T/af-other" commit -qm c; git -C "$T/af-other" push -q origin main 2>/dev/null
out="$(AF_MERGED="$PR101" af fleet-closeout "$RF10")"; rc=$?
printf '%s\n' "$out" | sed 's/^/       | /'
check "AF1 first call (L1 merged, L2 open): exit 0" "$rc" 0
check "AF1b … step 1 pulled the metadata branch first" "$(printf '%s\n' "$out" | head -1)" "fleet-closeout: pull — pulled test-meta"
has "AF1c … L1 backstop: lane-convert-ready closed it out and finalized it" "$out" "fleet-closeout: backstop — L1 lane-convert-ready (exit 0) — lane-convert-ready: finalize — finalize-empty: finalized"
has "AF1d … L2 waits for its merge" "$out" "fleet-closeout: waiting — L2 awaiting_merge"
has "AF1e … L1 checked off in the parent Queue" "$out" "fleet-closeout: check-off — L1 reqs/a.md"
check "AF1f parent Queue: reqs/a.md checked, reqs/b.md not" "$(grep -c '^- \[x\] reqs/a.md$' "$RF10" | tr -d ' '):$(grep -c '^- \[ \] reqs/b.md$' "$RF10" | tr -d ' ')" "1:1"
check "AF1g one parent Progress line for it, naming the PR" "$(grep -cxF -- "- fleet closeout: L1 reqs/a.md done (PR $PR101)" "$RF10" | tr -d ' ')" 1
has "AF1h step 4 pulled the primary onto origin/main" "$out" "fleet-closeout: sync — pulled main"
check "AF1i … the primary now has the new commit" "$(git -C "$P" rev-parse HEAD)" "$(git -C "$T/af-other" rev-parse HEAD)"
has "AF1j step 5 removed L1" "$out" "fleet-closeout: remove — L1 removed"
check "AF1k … L1 gone, L2 still there" "$([ -d "$L101" ] && echo kept || echo removed):$([ -d "$L102" ] && echo kept || echo removed)" "removed:kept"
check "AF1l step 6 waits on L2 (last line), lock still held" \
  "$(printf '%s\n' "$out" | tail -n1):$(bash "$HERE/run-lock.sh" status --root "$P" | cut -c1-6)" \
  "fleet-closeout: waiting — lane(s) not removed yet: L2 (re-run fleet-closeout on the next --resume):LOCKED"
hasnt "AF1m … no wave-end step ran" "$out" "lanes-dir"
SRF10="$(cksum < "$RF10")"
out="$(AF_MERGED="$PR101" af fleet-closeout "$RF10")"; rc=$?
check "AF2 a re-run with nothing new is idempotent (exit 0, parent run file byte-unchanged)" "$rc:$(cksum < "$RF10")" "0:$SRF10"
has "AF2b … it reads L1 removed" "$out" "fleet-closeout: lane — L1 removed"
has "AF2c … and the primary already synced" "$out" "fleet-closeout: sync — skipped — already synced (main at origin/main)"
# AF2d a closed-out lane whose removal is refused waits (never --stop, never an in-session wait)
echo junk > "$L102/junk.txt"
out="$(AF_MERGED="$PR101 $PR102" af fleet-closeout "$RF10")"; rc=$?
check "AF2d the owner merged L2 but its lane is dirty: closed out + checked off, removal waits (exit 0)" \
  "$rc:$(printf '%s\n' "$out" | grep -cxF 'fleet-closeout: waiting — L2 dirty working tree' | tr -d ' '):$([ -d "$L102" ] && echo kept)" "0:1:kept"
check "AF2e … and the wave end waits on it" "$(printf '%s\n' "$out" | tail -n1)" \
  "fleet-closeout: waiting — lane(s) not removed yet: L2 (re-run fleet-closeout on the next --resume)"
rm -f "$L102/junk.txt"
# a local branch in the primary whose newest PR merged at its tip — the dry sweep's would-remove candidate
git -C "$P" branch feature/af-swept 2>/dev/null; AFSW_OID="$(git -C "$P" rev-parse feature/af-swept)"
out="$(AF_SWEPT_OID="$AFSW_OID" AF_MERGED="$PR101 $PR102" AF_CI=failure af fleet-closeout "$RF10")"; rc=$?
printf '%s\n' "$out" | sed 's/^/       | /'
check "AF3 the next call removes it: exit 0" "$rc" 0
has "AF3b … L2 closed out, checked off and removed" "$out" "fleet-closeout: remove — L2 removed"
check "AF3c parent Queue fully checked off" "$(grep -c '^- \[ \] ' "$RF10" | tr -d ' ')" 0
has "AF3d the lanes dir is kept, naming its contents (salvage + logs kept by design)" "$out" "fleet-closeout: lanes-dir — kept $LR10 — contents: "
has "AF3e … salvage among them" "$(printf '%s\n' "$out" | grep 'lanes-dir — kept')" "salvage"
has "AF3f leaks vs the wave-start snapshot: none" "$out" "fleet-closeout: leaks — leaks: none (vs snapshot <primary>/.supervisor/automate/$PARENT10.leaks-snapshot)"
check "AF3g … its first line is in the parent Progress, with no absolute path" \
  "$(grep -c '^- fleet closeout leaks: leaks: none' "$RF10" | tr -d ' '):$(grep -c "$P" "$RF10" | tr -d ' ')" "1:0"
has "AF3h the wave end runs a DRY sweep of the primary: its summary line is printed" "$out" "fleet-closeout: sweep — sweep: summary — dry run: 1 would-remove, "
check "AF3h2 … appended once to the parent Progress, and the dry run removed nothing" \
  "$(grep -c '^- fleet closeout sweep (dry run): sweep: summary — dry run: 1 would-remove, ' "$RF10" | tr -d ' '):$(git -C "$P" rev-parse -q --verify refs/heads/feature/af-swept)" "1:$AFSW_OID"
MSHA="$(git -C "$P" rev-parse origin/main)"
has "AF3i main health: a red ci check on origin/main HEAD pauses the wave (printed)" "$out" "fleet-closeout: wave_paused: main_red after $MSHA"
check "AF3j … and appended once to the parent Progress (no revert, no block)" "$(grep -cxF -- "- wave_paused: main_red after $MSHA" "$RF10" | tr -d ' ')" 1
check "AF3k the Queue is empty ⇒ the wave lock is released (last line)" \
  "$(printf '%s\n' "$out" | tail -n1):$(bash "$HERE/run-lock.sh" status --root "$P")" "fleet-closeout: wave closed — lock released:UNLOCKED"
check "AF3l the gh calls were reads only (pr view / the sweep's pr list / the check-runs api)" "$(grep -vE '^gh (pr view|pr list --state all --head [^ ]+ --json number,state,headRefOid,mergedAt$|api repos/\{owner\}/\{repo\}/commits/[0-9a-f]+/check-runs\?check_name=ci|auth status)' "$T_AFGH" | wc -l | tr -d ' ')" 0
# AF3m-r the Queue emptied ⇒ the PARENT is finalized as §6 "Termination" ends a sequential run (W3 left
# it `## Status: running` with its wave line, and the coordinator hand-wrote done + its trail)
check "AF3m the parent run file reads ## Status: done (no running left)" \
  "$(grep -c '^## Status: done$' "$RF10" | tr -d ' '):$(grep -c '^## Status: running' "$RF10" | tr -d ' ')" "1:0"
check "AF3n … ## Current carries pause_reason: null and no wave line" \
  "$(awk '/^## Current/ { c = 1; next } /^## / { c = 0 } c' "$RF10" | grep -cxF -- '- pause_reason: null' | tr -d ' '):$(grep -c '^- wave:' "$RF10" | tr -d ' ')" "1:0"
check "AF3o … ONE finalize Progress line" "$(grep -cE '^- [0-9TZ:-]+ wave closed — Queue empty, run finalized$' "$RF10" | tr -d ' ')" 1
check "AF3p … trail-pr --reason done ran ONCE on the parent (through the trail seam), its line printed and appended" \
  "$(grep -cxF -- "trail-pr $RF10 --reason done" "$T_ABSPY" | tr -d ' '):$(printf '%s\n' "$out" | grep -cxF 'fleet-closeout: finalize — trail-pr: meta-pushed test-meta' | tr -d ' '):$(grep -cE '^- [0-9TZ:-]+ trail-pr: meta-pushed test-meta$' "$RF10" | tr -d ' ')" "1:1:1"
check "AF3q … the finalize ran BEFORE the release (under the wave lock), and branch mode on ⇒ no trail-unstage" \
  "$(printf '%s\n' "$out" | tail -n3 | head -1):$(grep -c "^trail-unstage $RF10" "$T_ABSPY" | tr -d ' ')" \
  "fleet-closeout: finalize — finalized (## Status: done, pause_reason: null, wave line cleared):0"
check "AF3r … the pushed parent run file carries ## Status: done (the trail ran after the write)" \
  "$(grep -c '^## Status: done$' "$T/remote-af/.supervisor/automate/$PARENT10.md" 2>/dev/null | tr -d ' ')" 1
SRF10="$(cksum < "$RF10")"
out="$(AF_MERGED="$PR101 $PR102" AF_CI=failure af fleet-closeout "$RF10")"; rc=$?
check "AF4 a re-run after the close: exit 0, the parent run file byte-unchanged (no duplicate lines)" "$rc:$(cksum < "$RF10")" "0:$SRF10"
check "AF4b … still ends wave closed (release is idempotent)" "$(printf '%s\n' "$out" | tail -n1)" "fleet-closeout: wave closed — lock released"
check "AF4d … the finalize is skipped (already done) and no second trail-pr runs" \
  "$(printf '%s\n' "$out" | grep -cxF 'fleet-closeout: finalize — skipped (already done)' | tr -d ' '):$(grep -cxF -- "trail-pr $RF10 --reason done" "$T_ABSPY" | tr -d ' ')" "1:1"
SRF10="$(cksum < "$RF10")"
out="$(LOOMWRIGHT_LANES_SWEEP="$T/no-such-sweep.sh" AF_MERGED="$PR101 $PR102" af fleet-closeout "$RF10")"; rc=$?
check "AF4f a failed sweep is reported, never an exit change, and its line is not appended twice" \
  "$rc:$(printf '%s\n' "$out" | grep -cxF 'fleet-closeout: sweep — sweep: summary — skipped: no summary line (sweep failed or printed nothing)' | tr -d ' '):$(cksum < "$RF10")" "0:1:$SRF10"
# AF4c the next wave's item is still unchecked ⇒ the lock is kept (the next wave runs under it)
printf '%s\n' "- [ ] reqs/next.md" > "$T/af.q"; awk -v f="$T/af.q" '{ print } /^## Queue$/ { while ((getline l < f) > 0) print l }' "$RF10" > "$T/af.rf" && mv "$T/af.rf" "$RF10"
bash "$HERE/run-lock.sh" acquire --owner "automate-lanes:$PARENT10" --root "$P" >/dev/null 2>&1
out="$(AF_MERGED="$PR101 $PR102" af fleet-closeout "$RF10")"
check "AF4c a Queue item left for the next wave keeps the wave lock" \
  "$(printf '%s\n' "$out" | tail -n1):$(bash "$HERE/run-lock.sh" status --root "$P" | cut -c1-6)" \
  "fleet-closeout: lock kept — 1 Queue item(s) remain unchecked (the next wave runs under it):LOCKED"
hasnt "AF4e … and no finalize runs while a Queue item remains" "$out" "finalize"
bash "$HERE/run-lock.sh" release --owner "automate-lanes:$PARENT10" --root "$P" >/dev/null 2>&1
# human cases + the pull failure, on a fresh one-lane parent
PARENT11=automate-2026-10-10-130000; RF11="$P/.supervisor/automate/$PARENT11.md"; LR11="$T/work/primary-lanes/$PARENT11"
printf '# Automate Run: %s\n\n## Queue\n- [ ] reqs/a.md\n\n## Progress\n' "$PARENT11" > "$RF11"
PR111="https://github.com/o/r/pull/111"
ae_lane "$RF11" "$LR11" 1 ".supervisor/requirements/t/af11.md" "$PR111" awaiting_merge; L111="$ABL"
out="$(AF_CLOSED="$PR111" af fleet-closeout "$RF11")"; rc=$?
has "AF5 a gone lane (PR closed unmerged) is the human's: never auto-abandoned" "$out" "fleet-closeout: human — L1 gone (PR closed unmerged): lane-remove $L111 --abandon"
check "AF5b … the lane is kept and its run file untouched" "$rc:$([ -d "$L111" ] && echo kept):$(grep -c '^## Status: paused' "$L111/.supervisor/automate/$PARENT11-L1.md" | tr -d ' ')" "0:kept:1"
echo "push_failed — rejected 5 times" > "$L111/.supervisor/automate/$PARENT11-L1.meta-push-failed"
out="$(AF_MERGED="$PR111" af fleet-closeout "$RF11")"
has "AF6 a meta-push-failed marker is the human's (no backstop runs)" "$out" "fleet-closeout: human — L1 meta-push-failed: push_failed — rejected 5 times"
hasnt "AF6b … no backstop" "$out" "backstop"
rm -f "$L111/.supervisor/automate/$PARENT11-L1.meta-push-failed"
S11="$(cksum < "$RF11")"
out="$(STUB_META_FAIL=1 AF_MERGED="$PR111" REMOTE11="$T/remote-af" LOOMWRIGHT_LANES_META_SYNC="$T/meta-sync.sh" LOOMWRIGHT_LANES_HELPERS="$SC/automate-helpers.sh" \
  LOOMWRIGHT_LANES_TRAIL="$T/ab-spy.sh" LOOMWRIGHT_GH_BIN="$T/af-gh" bash "$S" fleet-closeout "$RF11" 2>&1)"; rc=$?
check "AF7 a failed metadata pull: exit 2, ONE line, nothing else runs" "$rc:$(printf '%s\n' "$out" | wc -l | tr -d ' '):$out" \
  "2:1:fleet-closeout: pull FAILED — (meta-sync exit 1)"
check "AF7b … the parent run file and the lane are untouched" "$(cksum < "$RF11"):$([ -d "$L111" ] && echo kept)" "$S11:kept"
out="$(af fleet-closeout "$T/nowhere/x.md")"; rc=$?
check "AF8 a bad parent run file is refused (exit 1)" "$rc:$(printf '%s' "$out" | grep -c '^fleet-closeout: refused — ' | tr -d ' ')" "1:1"
printf '# Automate Run: automate-2026-10-10-140000\n\n## Progress\n' > "$P/.supervisor/automate/automate-2026-10-10-140000.md"
check "AF9 no lane table ⇒ one skipped line, exit 0" "$(af fleet-closeout "$P/.supervisor/automate/automate-2026-10-10-140000.md"; echo "rc=$?")" \
  "fleet-closeout: skipped — no lane table (automate-2026-10-10-140000.lanes): no lane to close out
rc=0"

# AF10-AF13 the parent finalize's edges, on a parent whose only lane is already removed (the table row
# reads `removed`), so a call goes straight to the wave end. A helpers wrapper in front of the real copy
# can refuse runfile-write (FC_REFUSE); mode off runs through the no-op trail stub (records its calls).
cat > "$T/fc-helpers.sh" <<EOF
#!/usr/bin/env bash
if [ "\$1" = runfile-write ] && [ -n "\${FC_REFUSE:-}" ]; then echo "runfile-write: refused — forced by the test [runfile_write_refused]" >&2; exit 1; fi
exec bash "$SC/automate-helpers.sh" "\$@"
EOF
chmod +x "$T/fc-helpers.sh"
fc_parent() { # <parent_id> — a running parent with an empty Queue, a wave line and one removed lane
  FCRF="$P/.supervisor/automate/$1.md"
  printf '# Automate Run: %s\n\n## Status: running\n\n## Run Config\n- parallel: 2\n\n## Queue\n- [x] reqs/a.md\n\n## Current\n- item: null | status: null\n- wave: 1 | items: reqs/a.md\n\n## Progress\n' "$1" > "$FCRF"
  printf 'L1\t%s\treqs/a.md\t%s-L1\t-\t-\t-\tremoved\t-\t-\n' "$T/work/primary-lanes/$1/L1" "$1" > "$P/.supervisor/automate/$1.lanes"
  bash "$HERE/run-lock.sh" acquire --owner "automate-lanes:$1" --root "$P" >/dev/null 2>&1
}
fc() { REMOTE11="$T/remote-af" LOOMWRIGHT_LANES_META_SYNC="$T/meta-f11.sh" LOOMWRIGHT_LANES_HELPERS="$T/fc-helpers.sh" \
  LOOMWRIGHT_LANES_TRAIL="${FC_TRAIL:-$T/ab-spy.sh}" LOOMWRIGHT_GH_BIN="$T/af-gh" bash "${FC_S:-$S}" "$@" 2>&1; }
lockst() { bash "$HERE/run-lock.sh" status --root "$P" | cut -c1-6; }
fc_parent automate-2026-10-11-100000; RF13="$FCRF"
out="$(FC_REFUSE=1 fc fleet-closeout "$RF13")"; rc=$?
check "AF10 a refused runfile-write ⇒ finalize FAILED naming why, exit unchanged (0)" \
  "$rc:$(printf '%s\n' "$out" | grep -c '^fleet-closeout: finalize FAILED — runfile-write: refused — forced by the test' | tr -d ' ')" "0:1"
check "AF10b … the finalize wrote nothing (still running, wave line kept, no finalize line; no stray staging file) and no trail-pr ran" \
  "$(grep -c '^## Status: running$' "$RF13" | tr -d ' '):$(grep -c '^- wave: 1' "$RF13" | tr -d ' '):$(grep -c 'run finalized' "$RF13" | tr -d ' '):$(ls "$P/.supervisor/automate/" | grep -c 'automate-2026-10-11-100000\.md\.' | tr -d ' '):$(grep -c "^trail-pr $RF13" "$T_ABSPY" | tr -d ' ')" "1:1:0:0:0"
check "AF10c … and the wave lock is STILL released (never stranded)" \
  "$(printf '%s\n' "$out" | tail -n1):$(lockst)" "fleet-closeout: wave closed — lock released:UNLOCK"
out="$(fc fleet-closeout "$RF13")"; rc=$?
check "AF10d the next call (lock already free: taken for the write) finalizes it: done, wave line gone, lock released" \
  "$rc:$(grep -c '^## Status: done$' "$RF13" | tr -d ' '):$(grep -c '^- wave:' "$RF13" | tr -d ' '):$(lockst)" "0:1:0:UNLOCK"
fc_parent automate-2026-10-11-110000; RF14="$FCRF"; : > "$T_TRAIL_LOG"
out="$(STUB_MODE_LINE=off FC_TRAIL="$T/trail-stub.sh" fc fleet-closeout "$RF14")"; rc=$?
check "AF11 branch mode OFF: finalized, trail-pr --reason done then trail-unstage, in that order" \
  "$rc:$(grep -c '^## Status: done$' "$RF14" | tr -d ' '):$(cat "$T_TRAIL_LOG" | tr '\n' '|')" \
  "0:1:trail trail-pr $RF14 --reason done|trail trail-unstage $RF14|"
has "AF11b … each printed as a finalize line" "$out" "fleet-closeout: finalize — trail-pr: skipped — meta no_changes"
# AF14 a TWO-wave run: each wave end prints its own dry sweep, but the parent Progress records the
# sweep ONLY at the parent finalize — so the one line at `## Status: done` is the FINAL wave's summary,
# never a frozen wave-1 snapshot (af/39a review). A stub sweep prints a per-call summary.
cat > "$T/sw-stub.sh" <<'EOF'
#!/usr/bin/env bash
echo "sweep: summary — dry run: ${SW_STUB_N:-0} would-remove, 0 kept (0 worktree(s), ${SW_STUB_N:-0} branch(es) examined)"
EOF
chmod +x "$T/sw-stub.sh"
fc_parent automate-2026-10-11-140000; RF17="$FCRF"
printf '%s\n' "- [ ] reqs/b.md" > "$T/af.q"; awk -v f="$T/af.q" '{ print } /^## Queue$/ { while ((getline l < f) > 0) print l }' "$RF17" > "$T/af.rf" && mv "$T/af.rf" "$RF17"
out="$(SW_STUB_N=1 LOOMWRIGHT_LANES_SWEEP="$T/sw-stub.sh" fc fleet-closeout "$RF17")"
check "AF14 wave 1 (a Queue item remains): its sweep is printed, NOT recorded, and the lock is kept" \
  "$(printf '%s\n' "$out" | grep -cxF 'fleet-closeout: sweep — sweep: summary — dry run: 1 would-remove, 0 kept (0 worktree(s), 1 branch(es) examined)' | tr -d ' '):$(grep -c '^- fleet closeout sweep (dry run): ' "$RF17" | tr -d ' '):$(lockst)" "1:0:LOCKED"
sed 's/^- \[ \] reqs\/b.md$/- [x] reqs\/b.md/' "$RF17" > "$T/af.rf" && mv "$T/af.rf" "$RF17"
out="$(SW_STUB_N=2 LOOMWRIGHT_LANES_SWEEP="$T/sw-stub.sh" fc fleet-closeout "$RF17")"
check "AF14b wave 2 finalizes: exactly ONE recorded sweep line, and it is the final wave's summary" \
  "$(grep -c '^## Status: done$' "$RF17" | tr -d ' '):$(grep -c '^- fleet closeout sweep (dry run): ' "$RF17" | tr -d ' '):$(grep -cxF -- '- fleet closeout sweep (dry run): sweep: summary — dry run: 2 would-remove, 0 kept (0 worktree(s), 2 branch(es) examined)' "$RF17" | tr -d ' ')" "1:1:1"
af14_fin="$(grep -n 'wave closed — Queue empty, run finalized$' "$RF17" | head -n1 | cut -d: -f1)"
af14_sw="$(grep -n '^- fleet closeout sweep (dry run): ' "$RF17" | head -n1 | cut -d: -f1)"
check "AF14c … recorded by the finalize, after its finalized line, as the run file's last line" \
  "$([ -n "$af14_fin" ] && [ -n "$af14_sw" ] && [ "$af14_sw" -gt "$af14_fin" ] && echo after):$(tail -n1 "$RF17" | cut -c1-34)" \
  "after:- fleet closeout sweep (dry run): "
out="$(SW_STUB_N=3 LOOMWRIGHT_LANES_SWEEP="$T/sw-stub.sh" fc fleet-closeout "$RF17")"
check "AF14d a re-run on the done parent records no second sweep line" "$(grep -c '^- fleet closeout sweep (dry run): ' "$RF17" | tr -d ' ')" "1"
# AF13 the run lock held by ANOTHER owner ⇒ nothing written under it, and it is never stolen
fc_parent automate-2026-10-11-130000; RF16="$FCRF"
bash "$HERE/run-lock.sh" release --owner "automate-lanes:automate-2026-10-11-130000" --root "$P" >/dev/null 2>&1
bash "$HERE/run-lock.sh" acquire --owner "automate-pick:someone-else" --root "$P" >/dev/null 2>&1
out="$(fc fleet-closeout "$RF16")"; rc=$?
check "AF13 a foreign run lock ⇒ finalize FAILED naming its holder, parent still running, the lock still theirs" \
  "$rc:$(printf '%s\n' "$out" | grep -cxF 'fleet-closeout: finalize FAILED — the run lock is held by automate-pick:someone-else, not automate-lanes:automate-2026-10-11-130000 (nothing written)' | tr -d ' '):$(grep -c '^## Status: running$' "$RF16" | tr -d ' '):$(bash "$HERE/run-lock.sh" status --root "$P" | cut -d' ' -f1-2)" \
  "0:1:1:LOCKED owner=automate-pick:someone-else"
bash "$HERE/run-lock.sh" release --owner "automate-pick:someone-else" --root "$P" >/dev/null 2>&1
# AF12 mutation control: with the finalize call deleted, the Queue-empty close leaves the parent running
mkdir -p "$MUT"; FCM="$SC/automate-lanes-nofinalize.sh"
awk '!/^  _lanes_fc_finalize "\$rf" "\$primary" "\$mb" "\$sw"$/' "$S" > "$FCM"
fc_parent automate-2026-10-11-120000; RF15="$FCRF"
if ! cmp -s "$S" "$FCM" && bash -n "$FCM"; then
  out="$(FC_S="$FCM" fc fleet-closeout "$RF15")"
  check "AF12 mutation (finalize call deleted) fails the done assertion — the parent stays running" \
    "$(grep -c '^## Status: done$' "$RF15" | tr -d ' '):$(grep -c '^## Status: running$' "$RF15" | tr -d ' '):$(printf '%s\n' "$out" | tail -n1)" \
    "0:1:fleet-closeout: wave closed — lock released"
else bad "AF12 mutation control not built"; fi
rm -f "$FCM"

# ---- SL: single-lane mode `--parallel 1` (twin-remediation/08b) ---------------------------------------
# lane.json marker (FIRST leg: the requirement's mutation control) · lane-park seam · fresh lane numbers
# (1..99, never reused) · whole-run token ceiling · lane-remove / fleet-closeout tokens line · drain guard
# (lane-drain-check) · current-set's single_lane refusal · the merge watcher outlives its launcher (AC 8).
cat > "$T/sl-ledger.sh" <<'EOF'
#!/usr/bin/env bash
root=""; prev=""; for a in "$@"; do [ "$prev" = --root ] && root="$a"; prev="$a"; done
f="$root/.supervisor/sl-tokens"
if [ -f "$f" ]; then echo "INPUT=0 OUTPUT=0 CACHE_READ=0 CACHE_CREATE=0 TOTAL=$(cat "$f") EVENTS=1"
else echo "INPUT=0 OUTPUT=0 CACHE_READ=0 CACHE_CREATE=0 TOTAL=0 EVENTS=0 LEDGER_UNREADABLE=1"; fi
EOF
chmod +x "$T/sl-ledger.sh"
sl() { LOOMWRIGHT_LANES_TOKEN_LEDGER="$T/sl-ledger.sh" LOOMWRIGHT_LANES_HELPERS="$SC/automate-helpers.sh" bash "$S" "$@" 2>&1; }
sl_parent() { # <parent_id> <N> — a running parent run file with `- parallel: <N>` and the two items queued
  printf '# Automate Run: %s\n\n## Status: running\n\n## Run Config\n- parallel: %s\n\n## Queue\n- [ ] reqs/a.md\n- [ ] reqs/b.md\n\n## Current\n- item: null | status: null\n- pause_reason: null\n\n## Progress\n- 2026-10-14T00:00:00Z run created\n' "$1" "$2" > "$P/.supervisor/automate/$1.md"
}
PARS=automate-2026-10-14-120000; RFS="$P/.supervisor/automate/$PARS.md"; LRS="$T/work/primary-lanes/$PARS"; TBS="$P/.supervisor/automate/$PARS.lanes"
PARN=automate-2026-10-14-130000; RFN="$P/.supervisor/automate/$PARN.md"; LRN="$T/work/primary-lanes/$PARN"
sl_parent "$PARS" 1; sl_parent "$PARN" 2
SL_KEYS='["schema_version","lane","run_id","parent_run_id","primary","parallel","max_tokens","created","policy"]'
# SL1 (FIRST LEG — the requirement's mutation control): an explicit --parallel 1 writes single_lane: true
out="$(sl lane-create "$RFS" reqs/a.md 1 --parallel 1)"; rc=$?
check "SL1 lane-create --parallel 1 ⇒ exit 0 and lane.json carries single_lane: true" "$rc:$(jq -c '.single_lane' "$LRS/L1/.supervisor/lane.json")" "0:true"
check "SL1b … appended LAST — every other key in today's order" "$(jq -c 'keys_unsorted' "$LRS/L1/.supervisor/lane.json")" \
  "${SL_KEYS%]},\"single_lane\"]"
check "SL1c lane-park --root <single lane> ⇒ awaiting_merge (exit 0)" "$(sl lane-park --root "$LRS/L1"; echo "rc=$?")" "awaiting_merge
rc=0"
# SL2 no --parallel (par defaults to n, here 1) and --parallel 2 ⇒ NO key; lane-park ⇒ ready_for_release
sl lane-create "$RFN" reqs/a.md 1 >/dev/null; sl lane-create "$RFN" reqs/b.md 2 --parallel 2 >/dev/null
check "SL2 lane-create without --parallel (n = 1 ⇒ parallel 1) ⇒ no single_lane key, today's keys and order" \
  "$(jq -c 'keys_unsorted' "$LRN/L1/.supervisor/lane.json"):$(jq -c '.parallel' "$LRN/L1/.supervisor/lane.json")" "$SL_KEYS:1"
check "SL2b lane-create --parallel 2 ⇒ no single_lane key" "$(jq -c 'has("single_lane")' "$LRN/L2/.supervisor/lane.json")" false
check "SL2c lane-park on both ⇒ ready_for_release" "$(sl lane-park --root "$LRN/L1"):$(sl lane-park --root "$LRN/L2")" "ready_for_release:ready_for_release"
# SL3 lane-park edge cases: no lane.json (not a lane) ⇒ the sequential park; unreadable / not an object /
# single_lane false ⇒ ready_for_release (the park that arms no watcher)
mkdir -p "$T/park/none" "$T/park/bad/.supervisor" "$T/park/arr/.supervisor" "$T/park/false/.supervisor" "$T/park/empty/.supervisor"
printf '{"lane": "L1", ' > "$T/park/bad/.supervisor/lane.json"; printf '[{"single_lane": true}]\n' > "$T/park/arr/.supervisor/lane.json"
printf '{"schema_version": 1, "single_lane": false}\n' > "$T/park/false/.supervisor/lane.json"; : > "$T/park/empty/.supervisor/lane.json"
check "SL3 lane-park with NO lane.json (not a lane) ⇒ awaiting_merge" "$(sl lane-park --root "$T/park/none")" awaiting_merge
check "SL3b lane-park on a malformed lane.json ⇒ ready_for_release" "$(sl lane-park --root "$T/park/bad")" ready_for_release
check "SL3c … a JSON array, single_lane false, an empty file ⇒ ready_for_release" \
  "$(sl lane-park --root "$T/park/arr"):$(sl lane-park --root "$T/park/false"):$(sl lane-park --root "$T/park/empty")" "ready_for_release:ready_for_release:ready_for_release"
check "SL3d lane-park defaults to the current checkout's top level" "$(cd "$LRS/L1" && bash "$S" lane-park)" awaiting_merge
# SL4 fresh lane numbers: a number already in the table is refused, nothing created
SL_TB0="$(cksum < "$TBS")"
out="$(bash "$S" lane-create "$RFS" reqs/b.md 1 --parallel 1 2>&1 >/dev/null)"; rc=$?
check "SL4 L1 reused under --parallel 1 ⇒ refused on stderr, exit 1" "$rc:$out" \
  "1:lane-create: refused — lane L1 already used in this run (single-lane takes a fresh number)"
check "SL4b … nothing created (table byte-unchanged, no salvage, L1 untouched)" \
  "$(cksum < "$TBS"):$([ -e "$LRS/salvage" ] && echo salvage || echo none):$(cat "$LRS/L1/.supervisor/lane-backlog.md")" "$SL_TB0:none:- [ ] reqs/a.md"
# SL5 lane numbers 1..99 under --parallel 1 only
out="$(sl lane-create "$RFS" reqs/b.md 11 --parallel 1)"; rc=$?
check "SL5 lane number 11 accepted under --parallel 1" "$rc:$([ -d "$LRS/L11" ] && echo created):$(jq -r .run_id "$LRS/L11/.supervisor/lane.json")" "0:created:$PARS-L11"
out="$(sl lane-create "$RFN" reqs/b.md 11)"; rc=$?
check "SL5b … still refused without it (1..10)" "$rc:$([ -e "$LRN/L11" ] && echo created || echo none)" "1:none"
has "SL5c … naming the bound" "$out" "lane number must be 1..10 (got '11')"
out="$(sl lane-create "$RFS" reqs/b.md 100 --parallel 1)"; check "SL5d 100 refused even under --parallel 1" "$?" 1
# SL6 whole-run token ceiling: SPENT = live lanes' ledger TOTAL + removed lanes' parent tokens lines
echo 300 > "$LRS/L1/.supervisor/sl-tokens"; echo 200 > "$LRS/L11/.supervisor/sl-tokens"
printf 'L5\t%s\treqs/z.md\t%s-L5\t-\t-\t-\tremoved\t-\t-\n' "$LRS/L5" "$PARS" >> "$TBS"   # a removed lane, directory gone
out="$(sl lane-create "$RFS" reqs/b.md 12 --parallel 1 --max-tokens 1000)"; rc=$?
check "SL6 a gone lane with no tokens line ⇒ refused token_ceiling ledger_unreadable, nothing created" \
  "$rc:$(printf '%s\n' "$out" | tail -n1):$([ -e "$LRS/L12" ] && echo created || echo none)" "1:lane-create: refused — token_ceiling ledger_unreadable:none"
bash "$SC/automate-helpers.sh" progress-append "$RFS" "fleet closeout: L5 tokens TOTAL=100" >/dev/null 2>&1
out="$(sl lane-create "$RFS" reqs/b.md 12 --parallel 1 --max-tokens 600)"; rc=$?
check "SL6b SPENT (300 + 200 + gone 100) ≥ T ⇒ refused token_ceiling total=600 max=600, nothing created" \
  "$rc:$(printf '%s\n' "$out" | tail -n1):$([ -e "$LRS/L12" ] && echo created || echo none)" "1:lane-create: refused — token_ceiling total=600 max=600:none"
out="$(sl lane-create "$RFS" reqs/b.md 12 --parallel 1 --max-tokens 1000)"; rc=$?
check "SL6c SPENT < T ⇒ lane.json max_tokens = T − SPENT (1000 − 600), not T / parallel" "$rc:$(jq -c .max_tokens "$LRS/L12/.supervisor/lane.json")" "0:400"
echo 50 > "$LRS/L12/.supervisor/sl-tokens"; rm -f "$LRS/L11/.supervisor/sl-tokens"
out="$(sl lane-create "$RFS" reqs/b.md 13 --parallel 1 --max-tokens 5000)"; rc=$?
check "SL6d a live lane whose reader says LEDGER_UNREADABLE ⇒ refused token_ceiling ledger_unreadable" \
  "$rc:$(printf '%s\n' "$out" | tail -n1)" "1:lane-create: refused — token_ceiling ledger_unreadable"
echo 200 > "$LRS/L11/.supervisor/sl-tokens"
# SL7 lane-remove (plain AND --abandon) on a single-lane parent writes the tokens line before deleting
out="$(sl lane-remove "$LRS/L12")"; rc=$?
check "SL7 plain lane-remove on a single-lane parent: removed, ONE tokens line with the lane's TOTAL" \
  "$rc:$([ -d "$LRS/L12" ] && echo kept || echo removed):$(grep -cxF -- '- fleet closeout: L12 tokens TOTAL=50' "$RFS" | tr -d ' ')" "0:removed:1"
out="$(sl lane-remove "$LRS/L11" --abandon)"; rc=$?
check "SL7b lane-remove --abandon: removed, tokens line written before the abandon line" \
  "$rc:$([ -d "$LRS/L11" ] && echo kept || echo removed):$(awk '/^- fleet closeout: L11 tokens TOTAL=200$/ { t = NR } /^- lane abandoned: L11 / { a = NR } END { print (t && a && t < a) }' "$RFS")" "0:removed:1"
out="$(sl lane-create "$RFS" reqs/b.md 13 --parallel 1 --max-tokens 1000)"; rc=$?
check "SL7c … so the next lane-create still reads SPENT (300 + 100 + 50 + 200 = 650 ⇒ max_tokens 350)" "$rc:$(jq -c .max_tokens "$LRS/L13/.supervisor/lane.json" 2>/dev/null)" "0:350"
bash "$SC/automate-helpers.sh" progress-append "$RFS" "fleet closeout: L13 tokens TOTAL=7" >/dev/null 2>&1
out="$(sl lane-remove "$LRS/L13")"
check "SL7d a lane that already has its tokens line gets no second one" "$(grep -c '^- fleet closeout: L13 tokens TOTAL=' "$RFS" | tr -d ' ')" 1
out="$(sl lane-remove "$LRN/L2")"; rc=$?
check "SL7e lane-remove on an N>1 parent's lane writes NO tokens line" "$rc:$(grep -c 'tokens TOTAL=' "$RFN" | tr -d ' ')" "0:0"
# SL7f/g the tokens line is read after one OPTIONAL timestamp token (the run file's own convention), by
# both readers: the whole-run SPENT sum and lane-remove's "already has its line" skip
printf 'L7\t%s\treqs/y.md\t%s-L7\t-\t-\t-\tremoved\t-\t-\n' "$LRS/L7" "$PARS" >> "$TBS"   # a gone lane, timestamped line
bash "$SC/automate-helpers.sh" progress-append "$RFS" "t9 fleet closeout: L7 tokens TOTAL=1000" >/dev/null 2>&1
out="$(sl lane-create "$RFS" reqs/b.md 14 --parallel 1 --max-tokens 2000)"; rc=$?
check "SL7f a timestamped tokens line counts toward SPENT (300+100+50+200+7+1000 = 1657 ⇒ max_tokens 343)" \
  "$rc:$(jq -c .max_tokens "$LRS/L14/.supervisor/lane.json" 2>/dev/null)" "0:343"
bash "$SC/automate-helpers.sh" progress-append "$RFS" "t9 fleet closeout: L14 tokens TOTAL=3" >/dev/null 2>&1
out="$(sl lane-remove "$LRS/L14")"; rc=$?
check "SL7g a lane whose tokens line is timestamped gets no second one" "$rc:$(grep -c 'fleet closeout: L14 tokens TOTAL=' "$RFS" | tr -d ' ')" "0:1"
# SL8 lane-drain-check: markers, not prose — dispatch marker / owned-drain count after the LAST picked / config backup
SLD="$LRS/L1"; SLDR="$SLD/.supervisor/automate/$PARS-L1.md"; SLPR="https://github.com/o/r/pull/881"
sl_drf() { # <progress lines…> — the lane run file at its park with these ## Progress lines
  { printf '# Automate Run: %s-L1 — reqs/a.md\n\n## Status: paused\n\n## Queue\n- [ ] reqs/a.md\n\n## Current\n- item: reqs/a.md | status: awaiting_merge | pr: %s | branch: feature/sl\n- pause_reason: awaiting_merge\n\n## Progress\n' "$PARS" "$SLPR"
    for l in "$@"; do printf -- '- %s\n' "$l"; done; } > "$SLDR"
}
sl_drf "t0 picked reqs/z.md" "t1 owned drain started — /review-pr x --until-mergeable @ aaa" "t2 picked reqs/a.md" "t3 owned drain started — /review-pr y --until-mergeable @ bbb" "t4 drain READY"
check "SL8 one owned drain after the LAST picked (an earlier item's drain before it) ⇒ ok" "$(sl lane-drain-check "$SLD")" \
  "drain-guard: ok — 1 owned drain(s), no dispatch marker, no config backup"
sl_drf "t2 picked reqs/a.md" "t3 owned drain started — a @ b" "t4 owned drain started — a @ c"
check "SL8b two plain owned drains after the last picked ⇒ violation" "$(sl lane-drain-check "$SLD")" \
  "drain-guard: violation — 2 owned drain(s) after the last picked line (exactly 1 expected)"
sl_drf "t2 picked reqs/a.md" "t3 owned drain started — a @ b" "t4 owned drain started (fix-now re-drain) — a @ c"
check "SL8c one plain + one fix-now re-drain ⇒ ok (the forms are counted apart)" "$(sl lane-drain-check "$SLD")" \
  "drain-guard: ok — 2 owned drain(s), no dispatch marker, no config backup"
sl_drf "t2 picked reqs/a.md" "t3 owned drain started — a @ b" "t4 owned drain started (fix-now re-drain) — a @ c" "t5 owned drain started (fix-now re-drain) — a @ d"
has "SL8d two fix-now re-drains ⇒ violation" "$(sl lane-drain-check "$SLD")" "drain-guard: violation — 2 fix-now re-drains after the last picked line (at most 1)"
sl_drf "t2 picked reqs/a.md" "t4 drain READY"
has "SL8e no owned drain after the last picked ⇒ violation" "$(sl lane-drain-check "$SLD")" "drain-guard: violation — 0 owned drain(s) after the last picked line"
# SL8k-n the drain-start line is matched after one OPTIONAL timestamp token, colon form tolerated
sl_drf "t2 picked reqs/a.md" "t3 owned drain started: /review-pr x --until-mergeable @ b"
check "SL8k a colon-form drain start (legacy run files) ⇒ ok, 1 drain" "$(sl lane-drain-check "$SLD")" \
  "drain-guard: ok — 1 owned drain(s), no dispatch marker, no config backup"
sl_drf "picked reqs/a.md" "owned drain started — a @ b" "drain READY"
check "SL8l an untimestamped drain start is counted ⇒ ok, 1 drain" "$(sl lane-drain-check "$SLD")" \
  "drain-guard: ok — 1 owned drain(s), no dispatch marker, no config backup"
sl_drf "t2 picked reqs/a.md" "owned drain started — a @ b" "t4 owned drain started — a @ c"
check "SL8m one untimestamped + one timestamped plain drain ⇒ violation, 2 drains" "$(sl lane-drain-check "$SLD")" \
  "drain-guard: violation — 2 owned drain(s) after the last picked line (exactly 1 expected)"
sl_drf "t2 picked reqs/a.md" "t3 owned drain started: a @ b" "owned drain started (fix-now re-drain) — a @ c" "t5 owned drain started (fix-now re-drain) — a @ d"
check "SL8n fix-now re-drains still counted apart, timestamp optional (1 plain ok, 2 fix-now ⇒ violation)" "$(sl lane-drain-check "$SLD")" \
  "drain-guard: violation — 2 fix-now re-drains after the last picked line (at most 1)"
sl_drf "t2 picked reqs/a.md" "t3 owned drain started — a @ b"
# the marker is named by the DISPATCHER's own PR_HASH block (dispatch-pr-review.sh), run on the lane's PR URL
SL_HASHBLK="$(awk '/^PR_HASH=""$/ { on = 1 } on && /^MARKER=/ { exit } on' "$HERE/dispatch-pr-review.sh")"
SL_HASH="$(PR_URL="$SLPR" bash -c "$SL_HASHBLK"'
printf "%s" "$PR_HASH"')"
mkdir -p "$SLD/.supervisor/review-dispatch"; : > "$SLD/.supervisor/review-dispatch/$SL_HASH"
check "SL8f the dispatcher's marker for the lane PR (hash from dispatch-pr-review.sh's own block) ⇒ violation" \
  "$([ -n "$SL_HASHBLK" ] && echo blk):$(sl lane-drain-check "$SLD")" \
  "blk:drain-guard: violation — review-dispatch marker for $SLPR (a detached default drain was dispatched)"
rm -f "$SLD/.supervisor/review-dispatch/$SL_HASH"; : > "$SLD/.supervisor/review-dispatch/0123456789abcdef0123456789abcdef01234567"
: > "$SLD/.supervisor/automate/$PARS-L1.config-backup.json"
check "SL8g a config backup ⇒ violation (another PR's dispatch file is not this lane's marker)" "$(sl lane-drain-check "$SLD")" \
  "drain-guard: violation — config backup $PARS-L1.config-backup.json present (auto_review never restored)"
rm -f "$SLD/.supervisor/automate/$PARS-L1.config-backup.json"; rm -rf "$SLD/.supervisor/review-dispatch"
rm -f "$SLDR"
out="$(sl lane-drain-check "$SLD")"; rc=$?
check "SL8h an unreadable (absent) lane run file ⇒ unknown, exit 0 (fail SAFE, never ok)" "$rc:$out" "0:drain-guard: unknown — lane run file unreadable ($PARS-L1.md)"
check "SL8i not a lane ⇒ unknown" "$(sl lane-drain-check "$T/park/none")" "drain-guard: unknown — not a lane: $T/park/none"
sl_drf "t3 owned drain started — a @ b"
has "SL8j no picked line ⇒ unknown" "$(sl lane-drain-check "$SLD")" "drain-guard: unknown — no picked line"
rm -f "$SLDR"
# SL9 current-set refuses the ready_for_release park in a single_lane checkout (file byte-unchanged)
sl_crf() { printf '# Automate Run: %s\n\n## Status: running\n\n## Queue\n- [ ] reqs/a.md\n\n## Current\n- item: reqs/a.md | status: running | pr: null | branch: null\n- pause_reason: null\n\n## Progress\n- t0 picked reqs/a.md\n' "$2" > "$1"; }
SLC="$SLD/.supervisor/automate/$PARS-L1.md"; sl_crf "$SLC" "$PARS-L1"; SLC0="$(cksum < "$SLC")"
out="$(bash "$SC/automate-helpers.sh" current-set "$SLC" --item reqs/a.md --status ready_for_release --pr "$SLPR" 2>&1 >/dev/null)"; rc=$?
check "SL9 current-set --status ready_for_release in a single_lane lane ⇒ exit 1, file byte-unchanged, ONE stderr line naming single_lane" \
  "$rc:$(cksum < "$SLC"):$(printf '%s\n' "$out" | grep -c . | tr -d ' '):$(printf '%s' "$out" | grep -c 'single_lane' | tr -d ' ')" "1:$SLC0:1:1"
bash "$SC/automate-helpers.sh" current-set "$SLC" --pause-reason ready_for_release >/dev/null 2>&1; rc=$?
check "SL9b … --pause-reason ready_for_release (run-level form) refused too" "$rc:$(cksum < "$SLC")" "1:$SLC0"
out="$(bash "$SC/automate-helpers.sh" current-set "$SLC" --item reqs/a.md --status awaiting_merge --pr "$SLPR" --pause-reason awaiting_merge 2>&1)"; rc=$?
check "SL9c … the awaiting_merge park is written" "$rc:$out:$(grep -c "^- item: reqs/a.md | status: awaiting_merge | pr: $SLPR" "$SLC" | tr -d ' ')" "0:current-set: written:1"
SLN="$LRN/L1/.supervisor/automate/$PARN-L1.md"; sl_crf "$SLN" "$PARN-L1"
out="$(bash "$SC/automate-helpers.sh" current-set "$SLN" --item reqs/a.md --status ready_for_release --pause-reason ready_for_release 2>&1)"; rc=$?
check "SL9d an N>1 lane (no single_lane key) still writes ready_for_release" "$rc:$out" "0:current-set: written"
rm -f "$SLC" "$SLN"
# SL10 fleet-closeout on a `- parallel: 1` parent writes `fleet closeout: <lane> tokens TOTAL=<n>` BEFORE lane-remove
PARF=automate-2026-10-14-140000; RFF="$P/.supervisor/automate/$PARF.md"; LRF="$T/work/primary-lanes/$PARF"; sl_parent "$PARF" 1
PRF1="https://github.com/o/r/pull/141"
sl_lane() { # <parent_rf> <lanes_root> <n> <req> <pr> <status> — ae_lane, created as a SINGLE lane
  local id="$(basename "$1" .md)-L$3"
  run lane-create "$1" reqs/a.md "$3" --parallel 1 >/dev/null; ABL="$2/L$3"; ABRF="$ABL/.supervisor/automate/$id.md"
  LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$ABL" --owner-command '/automate --parallel 1' >/dev/null; wait_gone "$ABL"
  mkdir -p "$ABL/$(dirname "$4")" "$ABL/.supervisor/jobs/done"
  printf '# req\n\n## Status: pending\n' > "$ABL/$4"
  printf '# brief\n- **Source requirement:** %s\n\n## Outcome\n- **PR:** %s\n' "$4" "$5" > "$ABL/.supervisor/jobs/done/2026-10-14-$id.md"
  printf '# Automate Run: %s\n\n## Status: paused\n\n## Source\n- backlog: lane\n\n## Run Config\n- limit: 1\n\n## Queue\n- [ ] %s\n\n## Current\n- item: %s | status: %s | pr: %s | branch: feature/sl\n- pause_reason: %s\n\n## Progress\n- 2026-10-14T00:00:00Z drain READY\n' \
    "$id" "$4" "$4" "$6" "$5" "$6" > "$ABRF"
}
sl_lane "$RFF" "$LRF" 1 ".supervisor/requirements/t/sl1.md" "$PRF1" awaiting_merge; LF1="$ABL"
echo 4242 > "$LF1/.supervisor/sl-tokens"
out="$(AF_MERGED="$PRF1" LOOMWRIGHT_LANES_TOKEN_LEDGER="$T/sl-ledger.sh" af fleet-closeout "$RFF")"; rc=$?
printf '%s\n' "$out" | sed 's/^/       | /'
check "SL10 single-lane parent: the merged lane is closed out, checked off and removed (exit 0)" \
  "$rc:$([ -d "$LF1" ] && echo kept || echo removed):$(grep -c '^- \[x\] reqs/a.md$' "$RFF" | tr -d ' ')" "0:removed:1"
check "SL10b … the tokens line printed BEFORE the lane-remove line" \
  "$(printf '%s\n' "$out" | awk '$0 == "fleet-closeout: tokens — L1 TOTAL=4242" { t = NR } $0 ~ /^fleet-closeout: remove — L1 removed/ { r = NR } END { print (t && r && t < r) }')" 1
check "SL10c … and ONE parent ## Progress line carrying the lane's real TOTAL (read while its directory existed)" \
  "$(grep -cxF -- '- fleet closeout: L1 tokens TOTAL=4242' "$RFF" | tr -d ' ')" 1
check "SL10d … the next item stays queued under the kept lock" "$(printf '%s\n' "$out" | tail -n1)" \
  "fleet-closeout: lock kept — 1 Queue item(s) remain unchecked (the next wave runs under it)"
check "SL10e fleet-closeout on the N>1 parent (AF above) wrote NO tokens line" "$(grep -c 'tokens TOTAL=' "$RF10" | tr -d ' ')" 0
# SL11 the merge watcher outlives the process that launched it (AC 8, owner decision 2). The launch line
# is READ from automate-merge-watch.sh's header (its documented source), never typed here; the leg runs it
# from a short-lived `bash -c` parent against a stub gh that reports OPEN, waits for that parent to exit,
# then delivers the hang-up a host's exit sends, and asserts the marker pid is alive and is the watcher.
cat > "$T/ws-gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in "pr view") [ -z "${WS_GH_LOG:-}" ] || echo poll >> "$WS_GH_LOG"
  echo '{"state":"OPEN","headRefOid":"abc","statusCheckRollup":[]}' ;; *) exit 1 ;; esac
EOF
chmod +x "$T/ws-gh"
ws_calls() { # <gh call log> — how many `gh pr view` polls the watcher has made (0 before the first)
  if [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi
}
_ws_settled() { # <pid> <gh call log> <n> — the watcher is gone, or it has made <n> polls
  ! kill -0 "$1" 2>/dev/null || [ "$(ws_calls "$2")" -ge "$3" ]
}
ws_line() { # <merge-watch file> — the documented launch line (header + its continuation), placeholders kept
  awk 'index($0, "#   env -u CLAUDE_PID -u CLAUDECODE ") == 1 && / automate-merge-watch\.sh \\$/ {
         l = $0; sub(/^#   /, "", l); sub(/ \\$/, "", l); getline n; sub(/^#[ ]+/, "", n); print l " " n; exit }' "$1"
}
ws_sub() { # <text> <from> <to> — literal replace-all (values via ENVIRON, never awk -v)
  WS_T="$1" WS_F="$2" WS_R="$3" awk 'BEGIN { t = ENVIRON["WS_T"]; f = ENVIRON["WS_F"]; r = ENVIRON["WS_R"]; o = ""
    while ((i = index(t, f)) > 0) { o = o substr(t, 1, i - 1) r; t = substr(t, i + length(f)) } print o t }'
}
ws_leg() { # <merge-watch file the line is read from> <tag> — prints `alive` | `dead` | `parent-blocked` | `no-line` | `no-marker` | `unsettled`
  local src="$1" tag="$2" d rf cmd p i wp gl c0
  cmd="$(ws_line "$src")"; [ -n "$cmd" ] || { echo no-line; return 0; }
  d="$T/ws-$tag"; mkdir -p "$d/.supervisor/automate"; rf="$d/.supervisor/automate/ws-$tag.md"
  printf '# Automate Run: ws-%s\n\n## Current\n- item: reqs/a.md | status: awaiting_merge | pr: %s\n\n## Progress\n' "$tag" "$SLPR" > "$rf"
  cmd="$(ws_sub "$cmd" '"<runfile dir>/<run_id>.merge-watch.log"' "'$d/.supervisor/automate/ws-$tag.merge-watch.log'")"
  cmd="$(ws_sub "$cmd" '<runfile> <item> <pr_url>' "'$rf' reqs/a.md '$SLPR'")"
  cmd="$(ws_sub "$cmd" ' automate-merge-watch.sh ' " '$HERE/automate-merge-watch.sh' ")"
  gl="$d/gh-calls"
  LOOMWRIGHT_GH_BIN="$T/ws-gh" WS_GH_LOG="$gl" LOOMWRIGHT_MERGE_WATCH_INTERVAL=1 bash -c "$cmd" </dev/null >/dev/null 2>&1 & p=$!
  i=0; while kill -0 "$p" 2>/dev/null && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  if kill -0 "$p" 2>/dev/null; then pkill -TERM -P "$p" 2>/dev/null; kill -TERM "$p" 2>/dev/null; wait "$p" 2>/dev/null; echo parent-blocked; return 0; fi
  wait "$p" 2>/dev/null
  i=0; while [ ! -s "$d/.supervisor/automate/ws-$tag.merge-watch" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  wp="$(awk -F'\t' '$1 == "pid" { print $2 }' "$d/.supervisor/automate/ws-$tag.merge-watch" 2>/dev/null)"
  [ -n "$wp" ] || { echo no-marker; return 0; }
  kill -HUP "$wp" 2>/dev/null   # the hang-up a host's exit delivers to what it started
  # Wait on a CONDITION, never a fixed time: the watcher dies (the hang-up took) or makes two more polls
  # counted AFTER the kill — a command boundary and a full interruptible nap lie between them, where its
  # `trap 'exit 0' HUP` would already have run — so `alive` below cannot pass before the signal acted.
  # A deadline miss with the watcher alive but not polling is `unsettled`, red for both SL11b and SL11c.
  c0="$(ws_calls "$gl")"
  if ! wait_for_cmd 20 _ws_settled "$wp" "$gl" "$((c0 + 2))" 2>/dev/null; then
    echo unsettled
  elif kill -0 "$wp" 2>/dev/null && case "$(ps -ww -p "$wp" -o command= 2>/dev/null)" in *automate-merge-watch.sh*" $SLPR"*) true ;; *) false ;; esac; then
    echo alive
  else echo dead; fi
  kill -TERM "$wp" 2>/dev/null   # stop it (its trap removes the marker) — nothing may leak into the piped suite
  i=0; while kill -0 "$wp" 2>/dev/null && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  kill -KILL "$wp" 2>/dev/null; return 0
}
check "SL11 the documented launch line is found in the automate-merge-watch.sh header" \
  "$(ws_line "$HERE/automate-merge-watch.sh" | grep -c '^env -u CLAUDE_PID -u CLAUDECODE nohup bash automate-merge-watch.sh <runfile> <item> <pr_url> </dev/null >"<runfile dir>/<run_id>.merge-watch.log" 2>&1 &$' | tr -d ' ')" 1
check "SL11b a watcher launched with that line outlives its parent and the hang-up (marker pid alive, ps shows the watcher + pr_url)" \
  "$(ws_leg "$HERE/automate-merge-watch.sh" real)" alive
# mutation control: the same leg on a header whose launch line lost `nohup` must report the watcher dead
sed 's/^#   env -u CLAUDE_PID -u CLAUDECODE nohup bash automate-merge-watch.sh \\$/#   env -u CLAUDE_PID -u CLAUDECODE bash automate-merge-watch.sh \\/' "$HERE/automate-merge-watch.sh" > "$T/ws-nonohup.sh"
if cmp -s "$HERE/automate-merge-watch.sh" "$T/ws-nonohup.sh"; then bad "SL11c mutant (nohup removed) not built"
else check "SL11c mutation control: the line without nohup ⇒ the watcher dies with the hang-up (SL11b would be red)" "$(ws_leg "$T/ws-nonohup.sh" nonohup)" dead; fi

# ---- AG: wave-plan is READ-ONLY (A4) + the no-new-merge-path guards (A3) + mutation control ----------
PARENT12=automate-2026-10-10-150000; RF12P="$P/.supervisor/automate/$PARENT12.md"; LR12="$T/work/primary-lanes/$PARENT12"
printf '# Automate Run: %s\n\n## Queue\n- [ ] reqs/a.md\n- [ ] reqs/b.md\n\n## Current\n- item: null | status: null\n- wave: 2 | items: reqs/b.md, reqs/a.md\n\n## Progress\n' "$PARENT12" > "$RF12P"
PR121="https://github.com/o/r/pull/121"; PR122="https://github.com/o/r/pull/122"
ae_lane "$RF12P" "$LR12" 1 ".supervisor/requirements/t/ag1.md" "$PR121" ready_for_release; L121="$ABL"
run lane-create "$RF12P" reqs/b.md 2 >/dev/null; L122="$LR12/L2"
printf '# Automate Run: %s-L2\n\n## Status: paused\n\n## Queue\n- [ ] reqs/b.md\n\n## Current\n- item: reqs/b.md | status: ready_for_release | pr: %s | branch: feature/b\n- pause_reason: ready_for_release\n\n## Progress\n' \
  "$PARENT12" "$PR122" > "$L122/.supervisor/automate/$PARENT12-L2.md"
ag_state() { # every ref + the working tree (status + content checksums) of the primary and both lanes
  local d; for d in "$P" "$L121" "$L122"; do git -C "$d" for-each-ref; git -C "$d" status --porcelain --untracked-files=all; lane_sum "$d"; done 2>&1 | cksum
}
: > "$T_AFGH"; AG0="$(ag_state)"
out="$(AF_NOHEAD="$PR121" af wave-plan "$RF12P")"; rc=$?
SHA122="$(printf '%040d' 122)"
check "AG1 wave-plan prints the operator's commands in planner order (exit 0)" "$rc
$out" "0
# wave-plan: $PARENT12 wave 2 (from ## Current) — READ-ONLY: nothing below was run; the operator runs it
git fetch origin
git checkout -b wave/$PARENT12-w2 origin/main
git merge --no-ff $SHA122 -m \"Merge lane L2 (reqs/b.md) PR #122\"
# L1: head unreadable — resolve before integrating
bash scripts/ci-local.sh
# run this project's release step
git push -u origin wave/$PARENT12-w2
gh pr create --base main --head wave/$PARENT12-w2
# Conflict rules (Part S):
#   - a marker-only conflict is resolved in the merge commit itself
#   - anything larger stops the integration: hand it to the owner
#   - never rewrite or push a lane branch
#   - a lane broken on the wave branch is fixed on its own PR, and its new head is re-merged"
check "AG2 GUARD: every ref and the working tree of the primary and the lanes are byte-identical after it" "$(ag_state)" "$AG0"
check "AG2b … and its only gh calls were pr view reads" "$(grep -vc '^gh pr view ' "$T_AFGH" | tr -d ' ')" 0
mkdir -p "$P/scripts"; printf '#!/usr/bin/env bash\n' > "$P/scripts/bump-version.sh"
out="$(af wave-plan "$RF12P" --wave-branch release/w2)"
has "AG3 a repo with scripts/bump-version.sh gets it as the release step" "$out" "
bash scripts/bump-version.sh
"
has "AG3b --wave-branch names the branch" "$out" "git checkout -b release/w2 origin/main"
has "AG3c … both lanes merged by their exact head sha" "$out" "git merge --no-ff $(printf '%040d' 121) -m \"Merge lane L1 (reqs/a.md) PR #121\""
rm -rf "$P/scripts"
out="$(af wave-plan "$RF11")"
check "AG3d no ## Current wave line ⇒ the lane table order, wave 1" "$(printf '%s\n' "$out" | sed -n '1p;3,4p')" \
  "# wave-plan: $PARENT11 wave 1 (no ## Current wave items — lane table order) — READ-ONLY: nothing below was run; the operator runs it
git checkout -b wave/$PARENT11-w1 origin/main
git merge --no-ff $(printf '%040d' 111) -m \"Merge lane L1 (reqs/a.md) PR #111\""
sed 's/^- wave: 2 | items: reqs\/b.md, reqs\/a.md$/- wave: 3 | items: reqs\/zzz.md/' "$RF12P" > "$T/ag.rf"; cp "$RF12P" "$T/ag.rf.keep"; mv "$T/ag.rf" "$RF12P"
check "AG3e a wave item with no lane is named and skipped" "$(af wave-plan "$RF12P" | sed -n 4p)" "# reqs/zzz.md: no lane in $PARENT12.lanes — skipped"
mv "$T/ag.rf.keep" "$RF12P"
out="$(af wave-plan "$RF12P" --wave-branch 'bad..name')"; rc=$?
check "AG4 an invalid wave branch name is refused (exit 1)" "$rc:$(printf '%s' "$out" | grep -c "^wave-plan: refused — 'bad..name' is not a valid branch name" | tr -d ' ')" "1:1"
check "AG4b helpers dispatches wave-plan and fleet-closeout to automate-lanes.sh" \
  "$(bash "$HERE/automate-helpers.sh" wave-plan 2>&1 | grep -c '^wave-plan: refused — ' | tr -d ' '):$(bash "$HERE/automate-helpers.sh" fleet-closeout 2>&1 | grep -cxF 'automate-lanes: usage: fleet-closeout <parent_runfile>' | tr -d ' ')" \
  "1:1"
# AG5 mutation control: a wave-plan that writes ONE ref (the wave branch) must fail the AG2 guard.
sed 's|^  echo "git checkout -b \$wb origin/\$base"$|&; git -C "$primary" branch "$wb" "refs/remotes/origin/$base" >/dev/null 2>\&1|' "$S" > "$MUT/automate-lanes.sh"
if [ -s "$MUT/automate-lanes.sh" ] && ! cmp -s "$S" "$MUT/automate-lanes.sh" && bash -n "$MUT/automate-lanes.sh"; then ok "AG5a mutant valid (non-empty, differs, bash -n)"; else bad "AG5a mutant invalid"; fi
AF_NOHEAD="$PR121" REMOTE11="$T/remote-af" LOOMWRIGHT_GH_BIN="$T/af-gh" bash "$MUT/automate-lanes.sh" wave-plan "$RF12P" >/dev/null 2>&1
if [ "$(ag_state)" != "$AG0" ]; then ok "AG5b mutation (wave-plan writes a ref) fails the read-only guard"; else bad "AG5b mutation control did not trip"; fi
git -C "$P" branch -D "wave/$PARENT12-w2" >/dev/null 2>&1
check "AG5c … the mutant's ref removed again" "$(ag_state)" "$AG0"
# AG6 A3/A4 static guards: no executable merge / push / gate-eval in automate-lanes.sh — the only hits
# are comments, the deny-list lines that NAME the tokens, and wave-plan's printed strings.
ag_exec_hits() { grep -nE 'gh pr merge|gate-eval|git( -C [^ ]+)? (merge|push)( |$)' "$1" \
  | grep -vE '^[0-9]+:[[:space:]]*#' | grep -vE 'LANE_DISALLOWED_FIXED=|disallow="|echo "git |printf .git merge'; }
check "AG6 automate-lanes.sh has no executable gh pr merge / gate-eval / git merge / git push" "$(ag_exec_hits "$S")" ""
awk '{ print } /^lanes_wave_plan\(\) \{$/ { print "  git -C \"$LP_PRIMARY\" push origin HEAD >/dev/null 2>&1" }' "$S" > "$MUT/automate-lanes.sh"
if [ -s "$MUT/automate-lanes.sh" ] && ! cmp -s "$S" "$MUT/automate-lanes.sh" && bash -n "$MUT/automate-lanes.sh"; then ok "AG6a mutant valid (non-empty, differs, bash -n)"; else bad "AG6a mutant invalid"; fi
check "AG6b mutation (an executable git push) is caught by the static guard" "$(ag_exec_hits "$MUT/automate-lanes.sh" | wc -l | tr -d ' ')" 1
check "AG7 A5: no sequential-loop script calls fleet-closeout or wave-plan (only the helpers dispatch arm)" \
  "$(grep -lE 'fleet-closeout|wave-plan' "$HERE"/automate-helpers.d/*.sh "$HERE/automate-trail.sh" "$HERE/automate-dismissed.sh" 2>/dev/null | wc -l | tr -d ' '):$(grep -cE '^ +fleet-closeout\|wave-plan\) exec bash "\$\(dirname "\$0"\)/automate-lanes.sh"' "$HERE/automate-helpers.sh" | tr -d ' ')" "0:1"

# ---- AI: gate opt-out carry (lane-guardrails part 3) ---------------------------------------------------
# A lane launched WITH the test-integrity guard's opt-out inherits it; a resume run from an environment
# that lacks it would silently have the guard block the lane. The FACT is recorded coordinator-side at
# first launch; every resume path refuses (exit 3, no spawn, nothing in the lane) until the owner re-runs
# with it set or passes --without-gate-optout. The opt-out is never ADDED to a resume's environment.
PARENT6=automate-2026-10-11-100000; RF6="$P/.supervisor/automate/$PARENT6.md"; LR6="$T/work/primary-lanes/$PARENT6"
printf '# Automate Run: %s\n\n## Progress\n' "$PARENT6" > "$RF6"
for n in 1 2 3; do run lane-create "$RF6" reqs/a.md "$n" --parallel 3 >/dev/null; done
L61="$LR6/L1"; L62="$LR6/L2"; L63="$LR6/L3"; TABLE6="$P/.supervisor/automate/$PARENT6.lanes"
OF61="$P/.supervisor/automate/$PARENT6.L1.gate-optout"; OF63="$P/.supervisor/automate/$PARENT6.L3.gate-optout"
OPT_ON="LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS=1"
lenv() { grep '^ENV' "$STUB_LOG" | tail -1 | sed 's/.* OPTOUT=//'; }
LJ61="$(cat "$L61/.supervisor/lane.json")"
n6="$(claude_calls)"
out="$(env "$OPT_ON" LOOMWRIGHT_LANE_RECHECK_S=0 bash "$S" lane-launch "$L61" --owner-command "$OWN" 2>&1)"; rc=$?
wait_gone "$L61"
check "AI1 first launch with the opt-out set launches (and the lane inherits it)" "$rc:$(( $(claude_calls) - n6 )):$(lenv)" "0:1:1"
check "AI1b the FACT is recorded coordinator-side (no value)" "$(cut -f1 "$OF61" 2>/dev/null):$(grep -c 'LOOMWRIGHT\|=1' "$OF61" 2>/dev/null | tr -d ' ')" "gate_optout_at_launch:0"
check "AI1c … never in the lane: lane.json byte-identical, no opt-out file under the lane" \
  "$([ "$(cat "$L61/.supervisor/lane.json")" = "$LJ61" ] && echo same):$(find "$L61" -name '*optout*' | wc -l | tr -d ' ')" "same:0"
mkdir -p "$L61/.supervisor/automate"; printf '# Automate Run: %s-L1 — reqs/a.md\n' "$PARENT6" > "$L61/.supervisor/automate/$PARENT6-L1.md"
ai_blocked="lane-launch: BLOCKED — L1 — launched with the test-integrity guard's opt-out; this resume's environment lacks it — re-run the same command with it set, or add --without-gate-optout to resume without it — need the owner"
n6="$(claude_calls)"
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L61" --owner-command "/automate --resume $PARENT6" --continue)"; rc=$?
check "AI2 --continue without the opt-out ⇒ BLOCKED exit 3, the exact line, no spawn" "$rc:$(printf '%s\n' "$out" | head -1):$(( $(claude_calls) - n6 ))" "3:$ai_blocked:0"
check "AI2b … the table reads blocked_launch with the reason; the fact is kept" \
  "$(awk -F'\t' '$1 == "L1" { print $8 "|" $10 }' "$TABLE6"):$([ -e "$OF61" ] && echo kept)" \
  "blocked_launch|launched with the test-integrity guard's opt-out; this resume's environment lacks it:kept"
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L61" --owner-command "/automate --resume $PARENT6" --resume-run "$PARENT6-L1")"; rc=$?
check "AI3 --resume-run without the opt-out ⇒ BLOCKED exit 3, no spawn" "$rc:$(( $(claude_calls) - n6 ))" "3:0"
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS=true run lane-launch "$L61" --owner-command "/automate --resume $PARENT6" --continue)"; rc=$?
check "AI3b a value other than 1 is the guard's 'unset' too ⇒ BLOCKED" "$rc:$(( $(claude_calls) - n6 ))" "3:0"
out="$(env "$OPT_ON" LOOMWRIGHT_LANE_RECHECK_S=0 bash "$S" lane-launch "$L61" --owner-command "/automate --resume $PARENT6" --continue 2>&1)"; rc=$?
wait_gone "$L61"
check "AI4 the same resume WITH the opt-out set ⇒ resumes, the lane runs with it (inherited)" "$rc:$(( $(claude_calls) - n6 )):$(lenv)" "0:1:1"
check "AI4b … and the fact stays recorded" "$([ -e "$OF61" ] && echo kept || echo gone)" kept
n6="$(claude_calls)"
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L61" --owner-command "/automate --resume $PARENT6" --continue --without-gate-optout)"; rc=$?
wait_gone "$L61"
check "AI5 --without-gate-optout resumes without it (never added)" "$rc:$(( $(claude_calls) - n6 )):$(lenv)" "0:1:unset"
check "AI5b … and clears the recorded fact" "$([ -e "$OF61" ] && echo kept || echo gone)" gone
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L61" --owner-command "/automate --resume $PARENT6" --continue)"; rc=$?
wait_gone "$L61"
check "AI6 fact cleared ⇒ a resume without the opt-out is unchanged (launches)" "$rc:$(( $(claude_calls) - n6 ))" "0:2"
# AI7 --without-gate-optout given while the environment HAS it: dropped from the spawn, nothing recorded.
n6="$(claude_calls)"
out="$(env "$OPT_ON" LOOMWRIGHT_LANE_RECHECK_S=0 bash "$S" lane-launch "$L62" --owner-command "$OWN" --without-gate-optout 2>&1)"; rc=$?
wait_gone "$L62"
check "AI7 a first launch with --without-gate-optout drops it from the lane's env and records nothing" \
  "$rc:$(lenv):$([ -e "$P/.supervisor/automate/$PARENT6.L2.gate-optout" ] && echo recorded || echo none)" "0:unset:none"
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L62" --owner-command "/automate --resume $PARENT6" --continue)"; rc=$?
wait_gone "$L62"
check "AI7b recorded = unset ⇒ resumes exactly as before" "$rc" 0
# AI8 lane-answer: the refusal keeps the owner's validated answer pending (never lost), like HELD.
out="$(env "$OPT_ON" LOOMWRIGHT_LANE_RECHECK_S=0 bash "$S" lane-launch "$L63" --owner-command "$OWN" 2>&1)"; wait_gone "$L63"
zq "$L63" toolu_ai1 sess-ai1
PF63="$P/.supervisor/automate/$PARENT6.L3.answer-pending.json"; AF63="$L63/.supervisor/inbox/answers/toolu_ai1.json"
n6="$(claude_calls)"
out="$(printf '%s' '{"answers":{"0":"Red","1":"A,B"},"note":"keep it small"}' | LOOMWRIGHT_LANE_RECHECK_S=0 bash "$S" lane-answer "$L63" toolu_ai1 --owner-command "$OWN" --via test 2>&1)"; rc=$?
check "AI8 lane-answer without the opt-out ⇒ BLOCKED exit 3, no spawn, nothing written into the lane" \
  "$rc:$(printf '%s\n' "$out" | head -1):$(( $(claude_calls) - n6 )):$([ -e "$AF63" ] && echo written || echo none)" \
  "3:${ai_blocked/— L1 —/— L3 —}:0:none"
check "AI8b … the validated answer is KEPT pending (answers, note, via)" \
  "$(jq -c '[.tool_use_id, .answers["0"], .answers["1"], .note, .via]' "$PF63" 2>/dev/null)" '["toolu_ai1","Red","A,B","keep it small","test"]'
has "AI8c … and the line says how to deliver it" "$out" "deliver it with the opt-out set, or with --without-gate-optout"
check "AI8d lane-status shows the lane as answer_pending" "$(bash "$S" lane-status "$RF6" --json 2>/dev/null | jq -r '.lanes[] | select(.lane == "L3") | .state')" answer_pending
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 run lane-answer "$L63" --deliver-pending --owner-command "/automate --resume $PARENT6")"; rc=$?
check "AI9 --deliver-pending without the opt-out ⇒ BLOCKED, the answer still pending, nothing in the lane" \
  "$rc:$([ -s "$PF63" ] && echo kept || echo gone):$([ -e "$AF63" ] && echo written || echo none):$(( $(claude_calls) - n6 ))" "3:kept:none:0"
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 run lane-answer "$L63" --deliver-pending --owner-command "/automate --resume $PARENT6" --without-gate-optout)"; rc=$?
wait_gone "$L63"
check "AI9b --deliver-pending --without-gate-optout delivers: answer file written, pending gone, fact cleared, env unset" \
  "$rc:$(jq -c '[.answers["Which color?"], .note]' "$AF63" 2>/dev/null):$([ -e "$PF63" ] && echo kept || echo gone):$([ -e "$OF63" ] && echo kept || echo gone):$(lenv)" \
  '0:["Red","keep it small"]:gone:gone:unset'
check "AI9c … one spawn, resuming the deferred session" "$(( $(claude_calls) - n6 )):$(grep '^ARGS' "$STUB_LOG" | tail -1 | grep -c '\[--resume\] \[sess-ai1\]' | tr -d ' ')" "1:1"
check "AI10 the opt-out's name never reaches a lane file (lane.json, inbox, settings)" \
  "$(grep -rl 'ALLOW_GATE_CONFIG_EDITS\|gate-optout\|gate_optout' "$L61/.supervisor" "$L63/.supervisor" "$L61/.claude" 2>/dev/null | wc -l | tr -d ' ')" 0

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
sed 's/if test("^parked ") then \["park"\]/if test("^parked ") then ["merge"]/' "$S" > "$MUT/lanes-aj4b.sh"
if ! cmp -s "$S" "$MUT/lanes-aj4b.sh" && bash -n "$MUT/lanes-aj4b.sh"; then
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
  "$(aj4d '— no PR: `user_aborted_at_no_go` (why)'),$(aj4d '— no PR: "supervisor_checkpoint" (why)'),$(aj4d '— no PR: unknown (Launch Pad blocked)'),$(aj4d '— no PR: unknown (no reason given)'),$(aj4d '— no PR: blocked by Launch Pad')" \
  "plan,build,plan,build,plan"
has "AJ4e5 per-item-loop.md step 2 pins the no-PR line" "$(cat "$HERE/../skills/automate-loop/per-item-loop.md")" \
  '`<ts> ran /autonomous — no PR: <status_reason> (<one-line why>)`'
sed 's/"concurrent_session_detected", //' "$S" > "$MUT/lanes-aj4e.sh"
if ! cmp -s "$S" "$MUT/lanes-aj4e.sh" && bash -n "$MUT/lanes-aj4e.sh"; then
  out="$(ajp '- 2026-10-11T08:01:00Z picked a.md' '- 2026-10-11T08:20:00Z ran /autonomous — no PR: concurrent_session_detected (two briefs)' '- 2026-10-11T08:20:05Z parked escalated (no PR)'
         ( . "$MUT/lanes-aj4e.sh"; _lanes_timeline "$AJRF" "$AJ/lane/.supervisor" "$(jq -n '"2026-10-11T10:00:00Z" | fromdateiso8601')" escalated - ) | jq -r .current)"
  check "AJ4f mutation (a Plan-stage token dropped from planstop) reads Build — the case AJ4e2 catches" "$out" build
else bad "AJ4f mutation did not apply (planstop moved)"; fi
rm -f "$MUT/lanes-aj4e.sh"
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
rm -f "$AJSM"
check "AJ9 a question ⇒ the current step waits on the owner" "$(ajt awaiting_input | jq -r '.steps[1].state')" waiting
rm -f "$AJRF"
check "AJ10 no run file ⇒ Pick current, held, started from last_launch_utc" \
  "$(ajt created 2026-10-11T07:59:00Z | jq -r '"\(.current)|\(.steps[0].state)|\(.started_at)|\([.steps[1:][].state] | unique | join(","))"')" \
  "pick|held|2026-10-11T07:59:00Z|pending"
J="$(sj)"
check "AJ11 lane-status --json carries timeline, started_at and run_started_at" \
  "$(jq -r '"\(has("run_started_at"))|\(.lanes | map(.timeline | type) | unique | join(","))|\(.lanes | map(has("started_at")) | all)"' <<<"$J")" "true|object|true"
has "AJ12 the plain view draws the steps line" "$(run lane-status "$RF2")" "    steps: [Pick"
check "AJ13 no wave built yet ⇒ waves is an empty list" "$(jq -c '.waves' <<<"$J")" "[]"
cp "$RF2" "$RF2.aj13"
printf '%s\n' '- wave built: wave/w3 — PR https://github.com/o/r/pull/474 (lanes: L1 PR #470; ci pass)' \
  '- 2026-10-13T00:15:43Z wave built (by hand; owner: push it): wave/p-w4 — PR https://github.com/o/r/pull/506 (lanes: L1 PR #502)' \
  '- 2026-10-13T00:20:00Z wave PR #506 ci re-run PASS' >> "$RF2"
check "AJ14 waves: every wave-build record, oldest first — an undated hand line and a parenthesised colon included" \
  "$(sj | jq -r '[.waves[] | "\(.wave)|\(.branch)|\(.pr)|\(.built_at)"] | join(" ")')" \
  "3|wave/w3|https://github.com/o/r/pull/474|null 4|wave/p-w4|https://github.com/o/r/pull/506|2026-10-13T00:15:43Z"
has "AJ15 the plain view names the wave PR" "$(run lane-status "$RF2")" "wave 4 PR: https://github.com/o/r/pull/506  branch=wave/p-w4"
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
sed '/^  if \[ -n "\$ev" \]; then echo "\$G unrun — \$item: \$ev"; return 0; fi$/d' "$S" > "$T/vgmut2/automate-lanes.sh"
if [ ! -s "$T/vgmut2/automate-lanes.sh" ] || cmp -s "$S" "$T/vgmut2/automate-lanes.sh" || ! bash -n "$T/vgmut2/automate-lanes.sh"; then
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
vg_fn() { awk -v f="$1() {" '$0 == f { on = 1 } on { print } on && /^}$/ { exit }' "$S"; }
check "AL9 AC7 lane-readiness + validation-gate read Validation only through _lanes_validation_rows" \
  "$(vg_fn lanes_readiness | grep -c '_lanes_validation_rows'):$(vg_fn lanes_validation_gate | grep -c '_lanes_validation_rows' | awk '{ print ($1 >= 2) }'):$(vg_fn lanes_readiness | grep -c 'Validation/'):$(vg_fn lanes_validation_gate | grep -c 'Validation/'):$(grep -c 'on = (\$0 ~ /^## Validation/)' "$S")" "1:1:0:0:1"
# AC9 mutation control: the gate's verdict replaced with an unconditional `ok` must turn AL1 red.
mkdir -p "$T/vgmut"; cp "$HERE"/resolve-loomwright-root.sh "$T/vgmut/" 2>/dev/null
sed 's/^    echo "\$G unrun — V\$n \$title: \$ev"; return 0$/    echo "$G ok — $k running-system step(s) evidenced"; return 0/' "$S" > "$T/vgmut/automate-lanes.sh"
if [ ! -s "$T/vgmut/automate-lanes.sh" ] || cmp -s "$S" "$T/vgmut/automate-lanes.sh" || ! bash -n "$T/vgmut/automate-lanes.sh"; then
  bad "AL10 AC9 mutant not built (empty, sed matched nothing, or bash -n failed)"
else
  out="$(VG_S="$T/vgmut/automate-lanes.sh" vg "$VGRF" reqs/pa16.md "$VGPR")"
  if [ "$out" != "$AL1_WANT" ]; then ok "AL10 AC9 mutation control: an unconditional ok verdict turns AL1 red (mutant prints: $out)"
  else bad "AL10 AC9 mutant still printed the AL1 verdict — AL1 is vacuous"; fi
fi

hasnt "Z1 gh never called" "$(cat "$GH_CALLS" 2>/dev/null)" "gh"
# AA-F12z (final leg): nothing this suite started may outlive it — no process whose command line names
# the suite dir $T (pgrep -f on the ERE-escaped path), after the same stop the EXIT trap performs.
for p in $BG_PIDS $(pgrep -f "_lane-run $T" 2>/dev/null); do kill -TERM "$p" 2>/dev/null; done
i=0; while pgrep -f "$(ere "$T")" >/dev/null 2>&1 && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
AA_LEFT="$(for p in $(pgrep -f "$(ere "$T")" 2>/dev/null); do ps -o pid= -o command= -p "$p" 2>/dev/null; done)"
check "AA-F12z no process naming the suite dir survives the suite" "${AA_LEFT:-none}" none
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
