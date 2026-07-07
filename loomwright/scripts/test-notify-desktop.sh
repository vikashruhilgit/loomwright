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
BASE_TOOLS="bash cat date mkdir find tail grep sed head dirname uname"

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
