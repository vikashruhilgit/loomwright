#!/usr/bin/env bash
# test-notify-desktop.sh — deterministic, sandboxed self-tests for notify-desktop.sh.
#
# Harness style mirrors test-webhook.sh / test-notify-click-target.sh (pass/fail
# helpers, RESULT summary line, exit 0 all-pass / 1 any-fail). Not counted by
# the doc-currency gate.
#
# Core assertion: notify-desktop.sh is a fail-safe emitter — it must exit 0 on
# EVERY path (missing jq, missing notifiers, malformed payload, unknown event,
# opt-out, scope-gate suppression, headless Linux, ...). Every case below
# asserts RC=0 in addition to its behavioral assertion.
#
# Sandboxing: the SUT is always run with PATH pointing at a temp bin dir that
# contains ONLY symlinks to the coreutils the script legitimately needs plus
# tiny stub scripts for the notifier / timeout binaries under test. The stubs
# record their invocation (name + args) to a per-test marker directory instead
# of touching the OS notification service — so NO real notification can ever
# fire, and absence/presence of a marker file is the observable behavior.
#
# Platform guard: dispatch-branch tests are host-guarded via `uname -s` —
# Darwin-branch tests run only on macOS, Linux-branch tests only on Linux; the
# other set is SKIPped green. Early-exit tests (opt-out, empty stdin, no jq,
# unknown event, scope gate, debounce) run on any host.
#
# bash-3.2 + Linux CI safe: no mapfile, no `stat`, numerics validated before
# arithmetic, no reliance on `timeout` existing on the host (the timeout /
# gtimeout binaries the SUT probes for are OUR stubs).
#
# EXIT: 0 on full pass, 1 on any failure.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/notify-desktop.sh"
BASH_BIN="$(command -v bash)"
HOST_OS="$(uname -s 2>/dev/null || echo unknown)"

if [ ! -f "$SUT" ]; then
  echo "FATAL  notify-desktop.sh not found: $SUT" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "FATAL  jq required to run these self-tests" >&2
  exit 1
fi

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
declare -a FAIL_LINES=()

pass() { echo "PASS  $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL  $1"; FAIL_LINES+=("FAIL  $1"); FAIL_COUNT=$((FAIL_COUNT + 1)); }
skip() { echo "SKIP  $1"; SKIP_COUNT=$((SKIP_COUNT + 1)); }

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then pass "$label"; else fail "$label  expected='$expected' actual='$actual'"; fi
}
assert_file_absent() {
  local label="$1" f="$2"
  if [ ! -e "$f" ]; then pass "$label"; else fail "$label  unexpected file: $f ($(cat "$f" 2>/dev/null | tr '\n' '|'))"; fi
}
assert_file_present() {
  local label="$1" f="$2"
  if [ -e "$f" ]; then pass "$label"; else fail "$label  expected file missing: $f"; fi
}
assert_file_match() {
  local label="$1" needle="$2" f="$3"
  if [ -e "$f" ] && grep -qF -- "$needle" "$f" 2>/dev/null; then
    pass "$label"
  else
    fail "$label  needle='$needle' not in $f ($(cat "$f" 2>/dev/null | tr '\n' '|'))"
  fi
}

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT INT TERM

# ---- Sandbox construction ----------------------------------------------------
# Base tools = every external binary notify-desktop.sh (and the pure
# notify-click-target.sh helper it shells out to) legitimately uses on its
# non-notifier paths. Notifiers (terminal-notifier / osascript / notify-send)
# and timeout / gtimeout are NEVER linked — only stubbed per-sandbox.
# tr/cksum/mv/rm serve the per-session group key and the bounded replay
# ledger — without them the SUT would silently skip both and the G*/R* cases
# below would pass vacuously.
BASE_TOOLS="bash cat date mkdir find tail grep sed head dirname uname tr cksum mv rm"

# build_sandbox <name> — creates $TMP_ROOT/<name>/ with base tools + jq linked.
# Echoes the sandbox bin dir path.
build_sandbox() {
  local dir="$TMP_ROOT/$1" t p
  mkdir -p "$dir"
  for t in $BASE_TOOLS jq; do
    p="$(command -v "$t" 2>/dev/null || true)"
    [ -n "$p" ] && ln -s "$p" "$dir/$t" 2>/dev/null
  done
  printf '%s' "$dir"
}

# add_stub <bindir> <name> — recording stub: appends "$*" to
# $LOOM_TEST_MARKER_DIR/<name>.invoked and exits 0. Never notifies.
add_stub() {
  local bindir="$1" name="$2"
  cat > "$bindir/$name" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "\${LOOM_TEST_MARKER_DIR:?}/$name.invoked"
exit 0
STUB
  chmod +x "$bindir/$name"
}

# add_timeout_stub <bindir> <name> — records invocation, then drops the
# duration arg and execs the wrapped command (so the notifier stub downstream
# still runs, mirroring real timeout semantics without any waiting).
add_timeout_stub() {
  local bindir="$1" name="$2"
  cat > "$bindir/$name" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "\${LOOM_TEST_MARKER_DIR:?}/$name.invoked"
shift
exec "\$@"
STUB
  chmod +x "$bindir/$name"
}

# ---- Sandboxes ----------------------------------------------------------------
SB_BARE="$(build_sandbox sb-bare)"                    # jq present, NO notifiers, NO timeout
SB_NOJQ="$(build_sandbox sb-nojq)"                    # jq REMOVED, notifier stubs present
rm -f "$SB_NOJQ/jq"
add_stub "$SB_NOJQ" osascript
add_stub "$SB_NOJQ" notify-send

SB_ALLSTUB="$(build_sandbox sb-allstub)"              # both notifier stubs (early-exit proofs)
add_stub "$SB_ALLSTUB" osascript
add_stub "$SB_ALLSTUB" notify-send

SB_OSA="$(build_sandbox sb-osa)"                      # Darwin: osascript only, no timeout
add_stub "$SB_OSA" osascript

SB_OSA_T="$(build_sandbox sb-osa-t)"                  # Darwin: osascript + timeout + gtimeout
add_stub "$SB_OSA_T" osascript
add_timeout_stub "$SB_OSA_T" timeout
add_timeout_stub "$SB_OSA_T" gtimeout

SB_OSA_GT="$(build_sandbox sb-osa-gt)"                # Darwin: osascript + gtimeout only
add_stub "$SB_OSA_GT" osascript
add_timeout_stub "$SB_OSA_GT" gtimeout

SB_TN="$(build_sandbox sb-tn)"                        # Darwin: terminal-notifier + osascript
add_stub "$SB_TN" terminal-notifier
add_stub "$SB_TN" osascript

SB_NS="$(build_sandbox sb-ns)"                        # Linux: notify-send only, no timeout
add_stub "$SB_NS" notify-send

SB_NS_T="$(build_sandbox sb-ns-t)"                    # Linux: notify-send + timeout + gtimeout
add_stub "$SB_NS_T" notify-send
add_timeout_stub "$SB_NS_T" timeout
add_timeout_stub "$SB_NS_T" gtimeout

SB_NS_GT="$(build_sandbox sb-ns-gt)"                  # Linux: notify-send + gtimeout only
add_stub "$SB_NS_GT" notify-send
add_timeout_stub "$SB_NS_GT" gtimeout

# ---- Payloads -----------------------------------------------------------------
P_NOTIFICATION='{"hook_event_name":"Notification","notification_type":"idle_prompt","message":"Claude is waiting on you now"}'
P_ASK='{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Proceed with the plan?"}]}}'
P_OTHER_TOOL='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}'
P_UNKNOWN='{"hook_event_name":"PostToolUse","tool_name":"Bash"}'
P_MALFORMED='{{{ not json at all'

# ---- Runner --------------------------------------------------------------------
# run_sut <bindir> <payload> [VAR=val ...]
#   Fresh working dir + fresh marker dir per call. Safe env defaults (debounce
#   off, click off, scope all, notifications on, headless-neutral DISPLAY);
#   trailing VAR=val args override the defaults (env: later wins).
#   Sets: RC, WD, MARKER, ERRFILE.
CASE_N=0
run_sut() {
  local bindir="$1" payload="$2"
  shift 2
  CASE_N=$((CASE_N + 1))
  WD="$TMP_ROOT/wd-$CASE_N"
  MARKER="$TMP_ROOT/markers-$CASE_N"
  ERRFILE="$TMP_ROOT/err-$CASE_N"
  mkdir -p "$WD" "$MARKER"
  RC=0
  ( cd "$WD" && printf '%s' "$payload" | env \
      PATH="$bindir" \
      LOOM_TEST_MARKER_DIR="$MARKER" \
      LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 \
      LOOMWRIGHT_NOTIFY_DEBOUNCE=0 \
      LOOMWRIGHT_NOTIFY_CLICK=off \
      LOOMWRIGHT_NOTIFY_SCOPE=all \
      DISPLAY= WAYLAND_DISPLAY= \
      CLAUDE_CODE_SESSION_ID= \
      CLAUDE_CODE_ENTRYPOINT= \
      "$@" "$BASH_BIN" "$SUT" ) >/dev/null 2>"$ERRFILE" || RC=$?
}

# rerun_sut_same_wd <bindir> <payload> [VAR=val ...] — like run_sut but reuses
# the CURRENT $WD and $MARKER (for the debounce coalescing case).
rerun_sut_same_wd() {
  local bindir="$1" payload="$2"
  shift 2
  RC=0
  ( cd "$WD" && printf '%s' "$payload" | env \
      PATH="$bindir" \
      LOOM_TEST_MARKER_DIR="$MARKER" \
      LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 \
      LOOMWRIGHT_NOTIFY_DEBOUNCE=0 \
      LOOMWRIGHT_NOTIFY_CLICK=off \
      LOOMWRIGHT_NOTIFY_SCOPE=all \
      DISPLAY= WAYLAND_DISPLAY= \
      CLAUDE_CODE_SESSION_ID= \
      CLAUDE_CODE_ENTRYPOINT= \
      "$@" "$BASH_BIN" "$SUT" ) >/dev/null 2>>"$ERRFILE" || RC=$?
}

# wait_for_file <path> — poll up to ~5s for a detached (fire_detached) stub to
# land its marker. Returns 0 if it appears.
wait_for_file() {
  local f="$1" i=0
  while [ "$i" -lt 50 ]; do
    [ -e "$f" ] && return 0
    sleep 0.1
    i=$((i + 1))
  done
  [ -e "$f" ]
}

# marker_lines <path> — line count (0 if absent); grep -c gives a clean number
# on both BSD and GNU (unlike wc -l's padded output).
marker_lines() {
  grep -c '' "$1" 2>/dev/null || echo 0
}

echo "==== Early-exit paths (platform-agnostic; run on any host) ===="

# Case A1: opt-out gate — LOOMWRIGHT_DESKTOP_NOTIFICATIONS=0 is a silent no-op
# even with notifier stubs on PATH.
run_sut "$SB_ALLSTUB" "$P_NOTIFICATION" LOOMWRIGHT_DESKTOP_NOTIFICATIONS=0
assert_eq          "A1 opt-out exit 0" "0" "$RC"
assert_file_absent "A1 opt-out: no notifier invoked (osascript)" "$MARKER/osascript.invoked"
assert_file_absent "A1 opt-out: no notifier invoked (notify-send)" "$MARKER/notify-send.invoked"

# Case A2: empty stdin → silent exit 0.
run_sut "$SB_ALLSTUB" ""
assert_eq          "A2 empty stdin exit 0" "0" "$RC"
assert_file_absent "A2 empty stdin: no notifier invoked" "$MARKER/osascript.invoked"

# Case A3: jq absent from PATH → graceful skip (stderr note), exit 0, no dispatch.
run_sut "$SB_NOJQ" "$P_NOTIFICATION"
assert_eq          "A3 no-jq exit 0" "0" "$RC"
assert_file_match  "A3 no-jq: skip note on stderr" "jq not on PATH" "$ERRFILE"
assert_file_absent "A3 no-jq: no notifier invoked" "$MARKER/osascript.invoked"

# Case A4: unknown hook event → silent exit 0.
run_sut "$SB_ALLSTUB" "$P_UNKNOWN"
assert_eq          "A4 unknown event exit 0" "0" "$RC"
assert_file_absent "A4 unknown event: no notifier invoked" "$MARKER/osascript.invoked"

# Case A5: malformed JSON payload → jq parse fails → treated as unknown → exit 0.
run_sut "$SB_ALLSTUB" "$P_MALFORMED"
assert_eq          "A5 malformed payload exit 0" "0" "$RC"
assert_file_absent "A5 malformed payload: no notifier invoked" "$MARKER/osascript.invoked"

# Case A6: PreToolUse for a tool other than AskUserQuestion → noise-filtered.
run_sut "$SB_ALLSTUB" "$P_OTHER_TOOL"
assert_eq          "A6 non-AskUserQuestion PreToolUse exit 0" "0" "$RC"
assert_file_absent "A6 non-AskUserQuestion: no notifier invoked" "$MARKER/osascript.invoked"

# Case A7: scope gate — default plugin scope + bare cwd (no .supervisor markers,
# no transcript) suppresses an AskUserQuestion notification.
run_sut "$SB_ALLSTUB" "$P_ASK" LOOMWRIGHT_NOTIFY_SCOPE=plugin
assert_eq          "A7 scope-gated AskUserQuestion exit 0" "0" "$RC"
assert_file_absent "A7 scope gate: no notifier invoked (osascript)" "$MARKER/osascript.invoked"
assert_file_absent "A7 scope gate: no notifier invoked (notify-send)" "$MARKER/notify-send.invoked"

echo ""
echo "==== Darwin dispatch branch (host-guarded) ===="
if [ "$HOST_OS" = "Darwin" ]; then
  # Case D1: notifiers ABSENT (no terminal-notifier, no osascript) → graceful
  # no-op: exit 0, no crash, nothing invoked. THE macOS no-notifier contract.
  run_sut "$SB_BARE" "$P_NOTIFICATION"
  assert_eq "D1 macOS no notifiers → graceful no-op exit 0" "0" "$RC"

  # Case D2: osascript fallback path (no terminal-notifier, no timeout binary
  # of any flavor → run_bounded runs the notifier DIRECTLY, still exit 0).
  run_sut "$SB_OSA" "$P_NOTIFICATION"
  assert_eq         "D2 osascript path exit 0" "0" "$RC"
  assert_file_match "D2 osascript invoked with notification body" "Claude is waiting on you now" "$MARKER/osascript.invoked"
  assert_file_match "D2 osascript invoked with title" "Claude is waiting on you" "$MARKER/osascript.invoked"

  # Case D3: timeout selection — BOTH timeout and gtimeout available →
  # `timeout` must win; gtimeout must NOT be invoked.
  run_sut "$SB_OSA_T" "$P_NOTIFICATION"
  assert_eq           "D3 both-timeouts exit 0" "0" "$RC"
  assert_file_present "D3 timeout selected when both available" "$MARKER/timeout.invoked"
  assert_file_absent  "D3 gtimeout NOT selected when timeout available" "$MARKER/gtimeout.invoked"
  assert_file_match   "D3 timeout wraps with 3s ceiling" "3 osascript" "$MARKER/timeout.invoked"
  assert_file_present "D3 notifier still runs through the timeout wrapper" "$MARKER/osascript.invoked"

  # Case D4: timeout selection — only gtimeout available → gtimeout chosen.
  run_sut "$SB_OSA_GT" "$P_NOTIFICATION"
  assert_eq           "D4 gtimeout-only exit 0" "0" "$RC"
  assert_file_present "D4 gtimeout selected as fallback" "$MARKER/gtimeout.invoked"
  assert_file_match   "D4 gtimeout wraps with 3s ceiling" "3 osascript" "$MARKER/gtimeout.invoked"

  # Case D5: terminal-notifier clickable path (click=activate). fire_detached
  # backgrounds the notifier, so poll for the marker instead of asserting
  # immediately (detached side effect — never assert before it lands).
  run_sut "$SB_TN" "$P_ASK" LOOMWRIGHT_NOTIFY_CLICK=activate
  assert_eq "D5 terminal-notifier path exit 0" "0" "$RC"
  if wait_for_file "$MARKER/terminal-notifier.invoked"; then
    pass "D5 terminal-notifier invoked (detached)"
    assert_file_match "D5 clickable banner uses -activate + Claude bundle id" "-activate com.anthropic.claudefordesktop" "$MARKER/terminal-notifier.invoked"
    assert_file_match "D5 banner carries the question text" "Proceed with the plan?" "$MARKER/terminal-notifier.invoked"
  else
    fail "D5 terminal-notifier invoked (detached)  marker never appeared"
  fi
  assert_file_absent "D5 osascript fallback NOT used when terminal-notifier handles it" "$MARKER/osascript.invoked"

  # Case D6: terminal-notifier present but click=off → CLICK_ACTION=none →
  # falls back to osascript; terminal-notifier must NOT be invoked.
  run_sut "$SB_TN" "$P_NOTIFICATION" LOOMWRIGHT_NOTIFY_CLICK=off
  assert_eq          "D6 click-off exit 0" "0" "$RC"
  assert_file_absent "D6 click-off: terminal-notifier not used" "$MARKER/terminal-notifier.invoked"
  assert_file_present "D6 click-off: osascript fallback used" "$MARKER/osascript.invoked"

  # Case D7: debounce coalescing — with a 60s window, a second fire in the same
  # working dir within the window is suppressed (single marker line).
  run_sut "$SB_OSA" "$P_NOTIFICATION" LOOMWRIGHT_NOTIFY_DEBOUNCE=60
  RC1="$RC"
  rerun_sut_same_wd "$SB_OSA" "$P_NOTIFICATION" LOOMWRIGHT_NOTIFY_DEBOUNCE=60
  assert_eq "D7 debounce first fire exit 0" "0" "$RC1"
  assert_eq "D7 debounce second fire exit 0" "0" "$RC"
  assert_eq "D7 second fire within window suppressed (1 invocation)" "1" "$(marker_lines "$MARKER/osascript.invoked")"
else
  skip "Darwin dispatch cases D1-D7 (host is $HOST_OS)"
fi

echo ""
echo "==== Linux dispatch branch (host-guarded) ===="
if [ "$HOST_OS" = "Linux" ]; then
  # Case L1: notify-send ABSENT → graceful no-op: exit 0, no crash.
  run_sut "$SB_BARE" "$P_NOTIFICATION"
  assert_eq "L1 Linux no notify-send → graceful no-op exit 0" "0" "$RC"

  # Case L2: notify-send present but HEADLESS (no DISPLAY/WAYLAND_DISPLAY) →
  # channel-detect skips cleanly; notify-send must NOT be invoked.
  run_sut "$SB_NS" "$P_NOTIFICATION"
  assert_eq          "L2 headless exit 0" "0" "$RC"
  assert_file_absent "L2 headless: notify-send not invoked" "$MARKER/notify-send.invoked"

  # Case L3: notify-send + display server present → dispatched (no timeout
  # binary of any flavor → run directly, still exit 0).
  run_sut "$SB_NS" "$P_NOTIFICATION" DISPLAY=:0
  assert_eq         "L3 notify-send path exit 0" "0" "$RC"
  assert_file_match "L3 notify-send invoked with body" "Claude is waiting on you now" "$MARKER/notify-send.invoked"
  assert_file_match "L3 notify-send app name" "Claude Code" "$MARKER/notify-send.invoked"

  # Case L4: timeout selection — BOTH available → `timeout` wins.
  run_sut "$SB_NS_T" "$P_NOTIFICATION" DISPLAY=:0
  assert_eq           "L4 both-timeouts exit 0" "0" "$RC"
  assert_file_present "L4 timeout selected when both available" "$MARKER/timeout.invoked"
  assert_file_absent  "L4 gtimeout NOT selected when timeout available" "$MARKER/gtimeout.invoked"
  assert_file_match   "L4 timeout wraps with 3s ceiling" "3 notify-send" "$MARKER/timeout.invoked"
  assert_file_present "L4 notifier still runs through the timeout wrapper" "$MARKER/notify-send.invoked"

  # Case L5: timeout selection — only gtimeout available → gtimeout chosen.
  run_sut "$SB_NS_GT" "$P_NOTIFICATION" DISPLAY=:0
  assert_eq           "L5 gtimeout-only exit 0" "0" "$RC"
  assert_file_present "L5 gtimeout selected as fallback" "$MARKER/gtimeout.invoked"
  assert_file_match   "L5 gtimeout wraps with 3s ceiling" "3 notify-send" "$MARKER/gtimeout.invoked"

  # Case L6: debounce coalescing on the Linux branch.
  run_sut "$SB_NS" "$P_NOTIFICATION" DISPLAY=:0 LOOMWRIGHT_NOTIFY_DEBOUNCE=60
  RC1="$RC"
  rerun_sut_same_wd "$SB_NS" "$P_NOTIFICATION" DISPLAY=:0 LOOMWRIGHT_NOTIFY_DEBOUNCE=60
  assert_eq "L6 debounce first fire exit 0" "0" "$RC1"
  assert_eq "L6 debounce second fire exit 0" "0" "$RC"
  assert_eq "L6 second fire within window suppressed (1 invocation)" "1" "$(marker_lines "$MARKER/notify-send.invoked")"
else
  skip "Linux dispatch cases L1-L6 (host is $HOST_OS)"
fi

# ---- Per-session group + per-tool_use_id replay de-duplication ---------------
# Host-independent assertions read the audit lines the SUT appends to
# $WD/.supervisor/logs/notifications.log before dispatch:
#   "<ts> notify group=<TN_GROUP> tool_use_id=<id|->" and
#   "<ts> skip replay tool_use_id=<id>".
# SB_BARE has no notifier on any host, so these cases never dispatch; the
# Darwin-only sub-assertions use the SB_TN / SB_OSA recording stubs.

# count_in <fixed-string> <file> — matching line count (0 if absent). grep -c
# prints "0" AND exits 1 on no match, so default the captured value instead of
# `|| echo 0` (which would yield "0\n0").
count_in() {
  local n
  n="$(grep -cF -- "$1" "$2" 2>/dev/null)"
  printf '%s' "${n:-0}"
}
# logged_group <file> — the group named by the LAST notify audit line.
logged_group() {
  grep -F ' notify group=' "$1" 2>/dev/null | tail -1 | sed -n 's/.* notify group=\([^ ]*\) .*/\1/p'
}
# ask_payload <session_id|""> <tool_use_id|""> — AskUserQuestion payload;
# an empty argument omits that key entirely.
ask_payload() {
  jq -nc --arg s "$1" --arg t "$2" \
    '{hook_event_name:"PreToolUse", tool_name:"AskUserQuestion",
      tool_input:{questions:[{question:"Proceed with the plan?"}]}}
     + (if $s == "" then {} else {session_id:$s} end)
     + (if $t == "" then {} else {tool_use_id:$t} end)'
}
# expected_path_group <dir> — what the SUT's cksum fallback must produce.
expected_path_group() {
  local out
  out="$(printf '%s' "$(cd "$1" && pwd -P)" | cksum)"
  printf 'loomwright-p%s' "${out%% *}"
}

echo ""
echo "==== Per-session notification group (audit line: any host) ===="

# Case G1: two different sessions → two different groups, each
# loomwright-<first 8 SANITISED chars>. Session A's raw id carries a '.' that
# sanitisation must drop ("ab.cd-ef_gh…" → "abcd-ef_").
P_G_A1="$(ask_payload "ab.cd-ef_gh-1111" "toolu_g1")"
P_G_B="$(ask_payload "zz99yy88-2222" "toolu_g2")"
P_G_A2="$(ask_payload "ab.cd-ef_gh-1111" "toolu_g3")"
run_sut "$SB_BARE" "$P_G_A1"
assert_eq "G1 session A exit 0" "0" "$RC"
G1_A="$(logged_group "$WD/.supervisor/logs/notifications.log")"
run_sut "$SB_BARE" "$P_G_B"
G1_B="$(logged_group "$WD/.supervisor/logs/notifications.log")"
run_sut "$SB_BARE" "$P_G_A2"
G1_A2="$(logged_group "$WD/.supervisor/logs/notifications.log")"
assert_eq "G1 session A group = loomwright-<first 8 sanitised chars>" "loomwright-abcd-ef_" "$G1_A"
assert_eq "G1 session B group = loomwright-<first 8 sanitised chars>" "loomwright-zz99yy88" "$G1_B"
if [ -n "$G1_A" ] && [ "$G1_A" != "$G1_B" ]; then
  pass "G1 two sessions land in two different groups"
else
  fail "G1 two sessions land in two different groups  A='$G1_A' B='$G1_B'"
fi
assert_eq "G1 a later payload from session A reuses A's group" "$G1_A" "$G1_A2"

# Case G2: CLAUDE_CODE_SESSION_ID is the fallback when the payload has none.
run_sut "$SB_BARE" "$(ask_payload "" "toolu_g4")" CLAUDE_CODE_SESSION_ID=envsess1-xyz
assert_eq "G2 env session id fallback group" "loomwright-envsess1" "$(logged_group "$WD/.supervisor/logs/notifications.log")"

# Case G3: no session id anywhere → loomwright-p<cksum of the checkout path>;
# two dirs differ, and re-running from the same dir is stable.
run_sut "$SB_BARE" "$(ask_payload "" "toolu_g5")"
G3_WD1="$WD"
G3_1="$(logged_group "$WD/.supervisor/logs/notifications.log")"
run_sut "$SB_BARE" "$(ask_payload "" "toolu_g6")"
G3_2="$(logged_group "$WD/.supervisor/logs/notifications.log")"
assert_eq "G3 dir 1 group = loomwright-p<cksum of path>" "$(expected_path_group "$G3_WD1")" "$G3_1"
assert_eq "G3 dir 2 group = loomwright-p<cksum of path>" "$(expected_path_group "$WD")" "$G3_2"
if [ -n "$G3_1" ] && [ "$G3_1" != "$G3_2" ]; then
  pass "G3 two checkout dirs → two different path-hash groups"
else
  fail "G3 two checkout dirs → two different path-hash groups  1='$G3_1' 2='$G3_2'"
fi
WD="$G3_WD1"
rerun_sut_same_wd "$SB_BARE" "$(ask_payload "" "toolu_g7")"
assert_eq "G3 re-run from the same dir → same group" "$G3_1" "$(logged_group "$WD/.supervisor/logs/notifications.log")"

if [ "$HOST_OS" = "Darwin" ]; then
  # Case G4: the terminal-notifier invocation itself carries the per-session
  # -group (detached → poll for the marker).
  run_sut "$SB_TN" "$P_G_A1" LOOMWRIGHT_NOTIFY_CLICK=activate
  G4_A_MARK="$MARKER/terminal-notifier.invoked"
  run_sut "$SB_TN" "$P_G_B" LOOMWRIGHT_NOTIFY_CLICK=activate
  G4_B_MARK="$MARKER/terminal-notifier.invoked"
  if wait_for_file "$G4_A_MARK" && wait_for_file "$G4_B_MARK"; then
    assert_file_match "G4 session A banner uses -group loomwright-abcd-ef_" "-group loomwright-abcd-ef_ " "$G4_A_MARK"
    assert_file_match "G4 session B banner uses -group loomwright-zz99yy88" "-group loomwright-zz99yy88 " "$G4_B_MARK"
  else
    fail "G4 terminal-notifier invoked for both sessions  marker never appeared"
  fi
else
  skip "G4 terminal-notifier -group stub assertion (host is $HOST_OS)"
fi

echo ""
echo "==== Replay de-duplication per tool_use_id ===="

# Case R1: the same ask (same tool_use_id) fed twice, debounce off → exactly
# one notify line + one skip-replay line; the ledger holds the id once.
P_R1="$(ask_payload "s2dtest-r1" "toolu_replay_1")"
run_sut "$SB_BARE" "$P_R1"
RC1="$RC"
rerun_sut_same_wd "$SB_BARE" "$P_R1"
R1_LOG="$WD/.supervisor/logs/notifications.log"
assert_eq "R1 first fire exit 0" "0" "$RC1"
assert_eq "R1 replay exit 0" "0" "$RC"
assert_eq "R1 same tool_use_id twice → exactly 1 notify line" "1" "$(count_in ' notify group=' "$R1_LOG")"
assert_eq "R1 same tool_use_id twice → exactly 1 skip replay line" "1" "$(count_in ' skip replay tool_use_id=toolu_replay_1' "$R1_LOG")"
assert_eq "R1 ledger holds the id once" "1" "$(count_in 'toolu_replay_1' "$WD/.supervisor/logs/.notified-ids")"

# Case R2: two different tool_use_ids → two notify lines, no skip.
run_sut "$SB_BARE" "$(ask_payload "s2dtest-r2" "toolu_r2_a")"
rerun_sut_same_wd "$SB_BARE" "$(ask_payload "s2dtest-r2" "toolu_r2_b")"
assert_eq "R2 two different tool_use_ids → 2 notify lines" "2" "$(count_in ' notify group=' "$WD/.supervisor/logs/notifications.log")"
assert_eq "R2 two different tool_use_ids → 0 skip lines" "0" "$(count_in 'skip replay' "$WD/.supervisor/logs/notifications.log")"

# Case R3: no tool_use_id → every call fires; nothing is recorded.
P_R3="$(ask_payload "s2dtest-r3" "")"
run_sut "$SB_BARE" "$P_R3"
rerun_sut_same_wd "$SB_BARE" "$P_R3"
rerun_sut_same_wd "$SB_BARE" "$P_R3"
assert_eq "R3 no tool_use_id → all 3 calls notify" "3" "$(count_in ' notify group=' "$WD/.supervisor/logs/notifications.log")"
assert_eq "R3 no tool_use_id → audit line says tool_use_id=-" "3" "$(count_in 'tool_use_id=-' "$WD/.supervisor/logs/notifications.log")"
assert_file_absent "R3 no tool_use_id → no ledger written" "$WD/.supervisor/logs/.notified-ids"

# Case R4: Notification events are never de-duplicated.
run_sut "$SB_BARE" "$P_NOTIFICATION"
rerun_sut_same_wd "$SB_BARE" "$P_NOTIFICATION"
assert_eq "R4 Notification event twice → 2 notify lines" "2" "$(count_in ' notify group=' "$WD/.supervisor/logs/notifications.log")"

# Case R5: an ask whose banner the DEBOUNCE suppressed is still recorded at
# first sight, so its replay is a skip — never a late banner.
run_sut "$SB_BARE" "$(ask_payload "s2dtest-r5" "toolu_r5_a")" LOOMWRIGHT_NOTIFY_DEBOUNCE=60
rerun_sut_same_wd "$SB_BARE" "$(ask_payload "s2dtest-r5" "toolu_r5_b")" LOOMWRIGHT_NOTIFY_DEBOUNCE=60
R5_LOG="$WD/.supervisor/logs/notifications.log"
assert_eq "R5 precondition: 2nd ask debounced (1 notify line so far)" "1" "$(count_in ' notify group=' "$R5_LOG")"
rerun_sut_same_wd "$SB_BARE" "$(ask_payload "s2dtest-r5" "toolu_r5_b")" LOOMWRIGHT_NOTIFY_DEBOUNCE=0
assert_eq "R5 replay of a debounced ask → skip replay" "1" "$(count_in 'skip replay tool_use_id=toolu_r5_b' "$R5_LOG")"
assert_eq "R5 replay of a debounced ask → still only 1 notify line" "1" "$(count_in ' notify group=' "$R5_LOG")"

# Case R6: the ledger is bounded to the newest 200 ids — seed 200, add one,
# the oldest rolls off, and a re-ask of it notifies again.
R6_WD="$TMP_ROOT/wd-$((CASE_N + 1))"
mkdir -p "$R6_WD/.supervisor/logs"
i=0
while [ "$i" -lt 200 ]; do
  printf 'toolu_old_%s\n' "$i" >> "$R6_WD/.supervisor/logs/.notified-ids"
  i=$((i + 1))
done
run_sut "$SB_BARE" "$(ask_payload "s2dtest-r6" "toolu_new_201")"
assert_eq "R6 runner reused the seeded dir" "$R6_WD" "$WD"
R6_IDS="$WD/.supervisor/logs/.notified-ids"
assert_eq "R6 ledger holds at most 200 ids" "200" "$(marker_lines "$R6_IDS")"
assert_eq "R6 newest id is recorded" "1" "$(count_in 'toolu_new_201' "$R6_IDS")"
R6_OLD0="$(grep -cxF 'toolu_old_0' "$R6_IDS" 2>/dev/null)"
assert_eq "R6 oldest id rolled off" "0" "${R6_OLD0:-0}"
R6_OLD1="$(grep -cxF 'toolu_old_1' "$R6_IDS" 2>/dev/null)"
assert_eq "R6 second-oldest id kept" "1" "${R6_OLD1:-0}"
assert_file_absent "R6 trim temp file cleaned up" "$(ls "$WD/.supervisor/logs/".notified-ids.tmp.* 2>/dev/null | head -1)"
rerun_sut_same_wd "$SB_BARE" "$(ask_payload "s2dtest-r6" "toolu_old_0")"
assert_eq "R6 re-ask of the rolled-off id notifies again" "1" "$(count_in 'tool_use_id=toolu_old_0' "$WD/.supervisor/logs/notifications.log")"
assert_eq "R6 re-ask of the rolled-off id is not a skip" "0" "$(count_in 'skip replay' "$WD/.supervisor/logs/notifications.log")"

if [ "$HOST_OS" = "Darwin" ]; then
  # Case R7: the stub itself fires once for a replayed id (osascript path is
  # synchronous — no polling), twice for two ids.
  run_sut "$SB_OSA" "$P_R1"
  rerun_sut_same_wd "$SB_OSA" "$P_R1"
  assert_eq "R7 Darwin stub: same tool_use_id twice → 1 notifier invocation" "1" "$(marker_lines "$MARKER/osascript.invoked")"
  run_sut "$SB_OSA" "$(ask_payload "s2dtest-r7" "toolu_r7_a")"
  rerun_sut_same_wd "$SB_OSA" "$(ask_payload "s2dtest-r7" "toolu_r7_b")"
  assert_eq "R7 Darwin stub: two tool_use_ids → 2 notifier invocations" "2" "$(marker_lines "$MARKER/osascript.invoked")"
else
  skip "R7 Darwin stub replay count (host is $HOST_OS)"
fi

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo "=========================================="
echo "RESULT  total=$TOTAL  passed=$PASS_COUNT  failed=$FAIL_COUNT  skipped=$SKIP_COUNT"
echo "=========================================="
if [ "$FAIL_COUNT" -gt 0 ]; then
  printf '  %s\n' "${FAIL_LINES[@]}"
  exit 1
fi
exit 0
