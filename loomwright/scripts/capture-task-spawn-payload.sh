#!/usr/bin/env bash
# capture-task-spawn-payload.sh — OUT-OF-SESSION hook-payload probe harness.
#
# INVARIANT: ALWAYS exits 0. This is a fail-SAFE probe/diagnostic, never a gate
# (CLAUDE.md §"Failure-Mode Invariants" — runtime side-effect emitters and
# diagnostics fail SAFE and always exit 0). `set -u` with NO `set -e`,
# `trap 'exit 0' EXIT`, same discipline as emit-progress-event.sh.
#
# WHY THIS EXISTS
# ----------------
# This repo's history is explicit that a hook payload's shape is verified
# empirically or not at all: emit-progress-event.sh's header records that the
# real SubagentStop payload carries `last_assistant_message` +
# `agent_transcript_path` and NO `result_block`, contrary to what was assumed
# at design time. Before wiring anything to `PreToolUse[Task]` we therefore
# have to OBSERVE the payload, not read about it.
#
# TWO CONSTRAINTS MAKE AN IN-SESSION PROBE IMPOSSIBLE (brief R1 / R3):
#   R1  A `loomwright:worker` subagent cannot spawn Task subagents
#       (spawn-depth), so it can never produce a `PreToolUse[Task]` event in
#       its own session.
#   R3  Hooks are read at SESSION START, so editing `.claude/settings.local.json`
#       mid-session is not a reliable way to arm a capture hook. Concluding
#       "the hook does not fire" from a hook that silently never armed would be
#       a FALSE negative — worse than either real outcome.
# Both are sidestepped by capturing from a FRESH out-of-session run:
#   claude -p --settings <capture-settings.json> "<prompt that spawns subagents>"
# `--settings <file-or-json>` is a verified real flag on the installed CLI
# (2.1.237). `-p` is required — a plain `claude` is interactive-by-default and
# can hang detached on a permission prompt (see this repo's dispatch-pr-review.sh,
# which uses `-p` for the same reason). NO permission-bypass flags are used.
#
# MODES
# -----
#   probe (default)  Generate the capture settings + agent definitions, run one
#                    headless `claude -p` session that spawns two DIFFERENT
#                    agent types, and leave every raw captured payload in
#                    --out-dir. Prints a short PROBE_RESULT summary.
#   --sink DIR LABEL Internal HOOK mode. Reads raw stdin and writes it verbatim
#                    to a fresh `DIR/LABEL-<n>.json`. One file per event, so no
#                    delimiter parsing is ever needed and a concurrent hook
#                    cannot interleave into another's capture. This is the mode
#                    the generated settings file invokes.
#
# PORTABILITY: no `timeout(1)` (absent on stock macOS), no `stat -f` (BSD-only;
# succeeds with GARBAGE under GNU). The watchdog polls `kill -0` against a
# deadline computed from `date +%s`, which is portable across BSD/GNU.
#
# Usage:
#   bash capture-task-spawn-payload.sh [--out-dir DIR] [--model M] [--timeout S]
#   bash capture-task-spawn-payload.sh --sink DIR LABEL     # hook mode

set -u
# Intentionally NO `set -e` — every failure mode must absorb to exit 0.

trap 'exit 0' EXIT

# ---- Hook (sink) mode --------------------------------------------------------
# Kept FIRST and dependency-free so the hook path cannot be broken by anything
# the probe path needs.
if [ "${1:-}" = "--sink" ]; then
  sink_dir="${2:-}"
  sink_label="${3:-event}"
  [ -n "$sink_dir" ] || exit 0
  mkdir -p "$sink_dir" 2>/dev/null || exit 0
  # Distinct filename per event. mktemp keeps two concurrent hooks from
  # clobbering each other; the label keeps the hook event readable.
  out="$(mktemp "$sink_dir/${sink_label}-XXXXXX" 2>/dev/null || true)"
  [ -n "$out" ] || exit 0
  cat > "$out" 2>/dev/null || true
  exit 0
fi

# ---- Probe mode --------------------------------------------------------------
OUT_DIR=""
MODEL="sonnet"
TIMEOUT_SECS=300

while [ "$#" -gt 0 ]; do
  case "${1:-}" in
    --out-dir) OUT_DIR="${2:-}"; shift 2 || exit 0 ;;
    --model)   MODEL="${2:-}"; shift 2 || exit 0 ;;
    --timeout) TIMEOUT_SECS="${2:-}"; shift 2 || exit 0 ;;
    *) shift ;;
  esac
done

case "$TIMEOUT_SECS" in
  ''|*[!0-9]*) TIMEOUT_SECS=300 ;;
esac

if [ -z "$OUT_DIR" ]; then
  OUT_DIR="$(mktemp -d 2>/dev/null || true)"
fi
[ -n "$OUT_DIR" ] || exit 0
mkdir -p "$OUT_DIR" 2>/dev/null || exit 0

if ! command -v claude >/dev/null 2>&1; then
  printf 'PROBE_RESULT: BLOCKED — `claude` not on PATH\n'
  exit 0
fi

SELF="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/$(basename "${BASH_SOURCE[0]:-$0}")"
[ -f "$SELF" ] || exit 0

CAP_DIR="$OUT_DIR/captures"
mkdir -p "$CAP_DIR" 2>/dev/null || exit 0

SETTINGS="$OUT_DIR/capture-settings.json"
AGENTS="$OUT_DIR/capture-agents.json"
RUN_LOG="$OUT_DIR/run.log"

# Capture hook wiring. `PreToolUse` matcher `Task` is the thing under test;
# `SubagentStop` matcher `.*` is captured in the SAME run so the spawn->stop
# join can be measured on two real events rather than asserted.
python3 - "$SETTINGS" "$SELF" "$CAP_DIR" <<'PY' 2>/dev/null || exit 0
import json, sys
settings_path, self_path, cap_dir = sys.argv[1], sys.argv[2], sys.argv[3]

def cmd(label):
    return "bash %s --sink %s %s || true" % (
        json.dumps(self_path), json.dumps(cap_dir), label)

settings = {
    "hooks": {
        "PreToolUse": [
            {"matcher": "Task",
             "hooks": [{"type": "command", "command": cmd("pretooluse-task")}]}
        ],
        "PostToolUse": [
            {"matcher": "Task",
             "hooks": [{"type": "command", "command": cmd("posttooluse-task")}]}
        ],
        "SubagentStop": [
            {"matcher": ".*",
             "hooks": [{"type": "command", "command": cmd("subagentstop")}]}
        ],
    }
}
with open(settings_path, "w") as fh:
    json.dump(settings, fh, indent=2)
PY

# Two DIFFERENT agent types, defined inline so the probe does not depend on
# which plugins happen to be installed in the capture session.
python3 - "$AGENTS" <<'PY' 2>/dev/null || exit 0
import json, sys
agents = {
    "probe-alpha": {
        "description": "Probe agent alpha. Use for the spawn-payload probe.",
        "prompt": "You are a probe agent. Reply with exactly: ALPHA-DONE",
        "tools": ["Read"],
    },
    "probe-beta": {
        "description": "Probe agent beta. Use for the spawn-payload probe.",
        "prompt": "You are a probe agent. Reply with exactly: BETA-DONE",
        "tools": ["Read"],
    },
}
with open(sys.argv[1], "w") as fh:
    json.dump(agents, fh, indent=2)
PY

[ -s "$SETTINGS" ] && [ -s "$AGENTS" ] || { printf 'PROBE_RESULT: BLOCKED — could not write settings/agents JSON\n'; exit 0; }

PROMPT='Use the Task tool twice, one after the other. First spawn the probe-alpha subagent with the prompt "say your done word". Then spawn the probe-beta subagent with the prompt "say your done word". Do not use any other tool. Then reply with the two done words.'

printf 'command: claude -p --settings %s --agents <file:%s> --model %s --max-turns 12 "<prompt>"\n' \
  "$SETTINGS" "$AGENTS" "$MODEL" > "$OUT_DIR/command.txt"

# --- Run headless, with a portable watchdog (no `timeout` on stock macOS) -----
claude -p \
  --settings "$SETTINGS" \
  --agents "$(cat "$AGENTS")" \
  --model "$MODEL" \
  --max-turns 12 \
  "$PROMPT" >"$RUN_LOG" 2>&1 &
child=$!

deadline=$(( $(date +%s 2>/dev/null || echo 0) + TIMEOUT_SECS ))
timed_out=0
while kill -0 "$child" 2>/dev/null; do
  now="$(date +%s 2>/dev/null || echo 0)"
  if [ "$now" -ge "$deadline" ] 2>/dev/null; then
    kill "$child" 2>/dev/null || true
    timed_out=1
    break
  fi
  sleep 2
done
wait "$child" 2>/dev/null
rc=$?

# --- Report -------------------------------------------------------------------
pre_n=0; stop_n=0; post_n=0
for f in "$CAP_DIR"/pretooluse-task-*; do [ -f "$f" ] && pre_n=$(( pre_n + 1 )); done
for f in "$CAP_DIR"/posttooluse-task-*; do [ -f "$f" ] && post_n=$(( post_n + 1 )); done
for f in "$CAP_DIR"/subagentstop-*; do [ -f "$f" ] && stop_n=$(( stop_n + 1 )); done

{
  printf 'out_dir: %s\n' "$OUT_DIR"
  printf 'exit_code: %s\n' "$rc"
  printf 'timed_out: %s\n' "$timed_out"
  printf 'pretooluse_task_captures: %s\n' "$pre_n"
  printf 'posttooluse_task_captures: %s\n' "$post_n"
  printf 'subagentstop_captures: %s\n' "$stop_n"
} | tee "$OUT_DIR/probe-summary.txt"

if [ "$pre_n" -gt 0 ]; then
  printf 'PROBE_RESULT: FIRED — %s PreToolUse[Task] payload(s) captured in %s\n' "$pre_n" "$CAP_DIR"
elif [ "$timed_out" = "1" ]; then
  printf 'PROBE_RESULT: BLOCKED — capture session timed out after %ss (see %s)\n' "$TIMEOUT_SECS" "$RUN_LOG"
elif [ "$rc" != "0" ]; then
  printf 'PROBE_RESULT: BLOCKED — capture session exited %s (see %s)\n' "$rc" "$RUN_LOG"
else
  printf 'PROBE_RESULT: NO-FIRE — session completed exit 0 but no PreToolUse[Task] payload was captured\n'
fi

exit 0
