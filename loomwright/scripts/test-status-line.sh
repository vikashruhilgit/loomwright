#!/usr/bin/env bash
# test-status-line.sh — STATIC, fixture-driven self-tests for status-line.sh.
#
# STATIC ONLY: no network, no Docker, no GitHub — it runs on the plugin's Ubuntu CI like every
# other test-*.sh (auto-registered by ci.yml's `loomwright/scripts/test-*.sh` glob).
#
# Exit 0 = all pass, 1 = any assertion failed, 2 = FIXTURE SETUP is broken.
#
# Covers (each = an acceptance criterion):
#   (a) THE ABSENT LIVE-ROLE FIELD (AC 1) — asserted BOTH ways: the rendered line carries no
#       such field, and the source names none of the record kinds a liveness proxy would have
#       to read. A comment claiming honesty is not evidence; this is the check that backs it
#   (b) the three degraded cases — missing state file, unparseable state file, empty session
#       log — each prints a line and exits 0
#   (c) the happy path renders phase, branch, N/M and an age
#   (d) AGE COMES FROM THE RECORD, NOT THE FILESYSTEM: a fixture whose `ts` is 3 days old
#       renders `3d ago` even though the file was written seconds ago — which a `stat`-based
#       implementation cannot do. An UNPARSEABLE `ts` omits the field rather than emptying it
#   (e) write containment: the script creates and modifies nothing, asserted by checksumming
#       the whole fixture tree before and after
#   (f) fail-safe: every branch exits 0, including an unknown flag and an unreadable state file
#
# NO `producer | grep -q` PIPELINES (SIGPIPE turns a match into rc=141 under pipefail). Every
# text assertion captures stdout into a variable and matches it with a here-string.

set -uo pipefail
export LC_ALL=C

script_dir="$(cd "$(dirname "$0")" && pwd)"
SL="$script_dir/status-line.sh"

pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; return 0; }
setup_fail() { printf '  SETUP BROKEN: %s\n' "$1" >&2; exit 2; }
has() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }

[ -f "$SL" ] || setup_fail "status-line.sh not found at $SL"

TMPROOT="$(mktemp -d)" || setup_fail "mktemp -d failed"
trap 'rm -rf "$TMPROOT"' EXIT

# run <root> [extra args...] -> stdout in $out, exit code in $rc
run() {
  local root="$1"; shift
  out="$(bash "$SL" --root "$root" "$@" </dev/null 2>&1)"; rc=$?
}

# mkstate <root> <phase> <branch> <session_id> <done> <total>
mkstate() {
  local root="$1" phase="$2" branch="$3" sid="$4" done="$5" total="$6" i
  mkdir -p "$root/.supervisor" || setup_fail "mkdir -p $root/.supervisor failed"
  {
    echo "# Supervisor State"
    echo
    echo "## Session"
    echo "- session_id: $sid"
    echo "- branch: $branch"
    echo "- status: running"
    echo "- phase: $phase"
    echo
    echo "## Subtasks"
    echo "| # | Title | Status | Review |"
    echo "|---|-------|--------|--------|"
    i=1
    while [ "$i" -le "$total" ]; do
      if [ "$i" -le "$done" ]; then
        echo "| $i | fixture subtask $i | COMPLETED (abc123$i) | PASS |"
      else
        echo "| $i | fixture subtask $i | PENDING | — |"
      fi
      i=$((i+1))
    done
    echo
    echo "## Parallelism"
    echo "- launchable: 1"
  } > "$root/.supervisor/state.md" || setup_fail "could not write $root/.supervisor/state.md"
}

# mklog <root> <session_id> <iso-ts>   (an empty ts writes an EMPTY log file)
mklog() {
  local root="$1" sid="$2" ts="$3"
  mkdir -p "$root/.supervisor/logs" || setup_fail "mkdir logs failed"
  if [ -z "$ts" ]; then
    : > "$root/.supervisor/logs/$sid.jsonl" || setup_fail "could not create empty log"
  else
    printf '{"event":"phase_start","session_id":"%s","ts":"%s"}\n' "$sid" "$ts" \
      > "$root/.supervisor/logs/$sid.jsonl" || setup_fail "could not write log"
  fi
}

# An ISO-8601 Z timestamp N days in the past, computed try-BSD-then-GNU exactly as the script
# under test parses one. If neither flavour can do the arithmetic the (d1) case is SKIPPED
# rather than asserted against a wrong value.
iso_days_ago() {
  local n="$1" out
  out="$(date -u -v-"${n}"d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
  [ -n "$out" ] || out="$(date -u -d "$n days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
  printf '%s' "$out"
}

echo "== (a) the absent live-role field (AC 1) =="

R="$TMPROOT/a"; mkstate "$R" "EXECUTE" "main" "sid-a" 2 4
mklog "$R" "sid-a" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
run "$R"
lower="$(printf '%s' "$out" | tr '[:upper:]' '[:lower:]')"
if ! has "$lower" "agent"; then
  ok "(a1) the rendered line contains no agent field at all"
else
  no "(a1) the rendered line contains no agent field at all" "$out"
fi

# The source must not READ any record kind a liveness proxy would need. These four tokens are
# exactly the fields such an inference would have to key on; none may appear in the script.
src="$(cat "$SL")"
offenders=""
for tok in "token_ledger" "agent_spawn" "agent_type" "agent_id"; do
  has "$src" "$tok" && offenders="$offenders $tok"
done
if [ -z "$offenders" ]; then
  ok "(a2) the source references none of token_ledger / agent_spawn / agent_type / agent_id — no liveness proxy is even reachable"
else
  no "(a2) the source references none of token_ledger / agent_spawn / agent_type / agent_id — no liveness proxy is even reachable" \
     "offenders:$offenders"
fi

# Control for (a2): the token set must be one that CAN appear in a session log, otherwise the
# assertion is vacuous — it would pass against tokens no implementation would ever write.
mklog "$R" "sid-a" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '{"event":"token_ledger","agent_id":"x","agent_type":"worker","ts":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  >> "$R/.supervisor/logs/sid-a.jsonl" || setup_fail "could not append the control record"
run "$R"
lower="$(printf '%s' "$out" | tr '[:upper:]' '[:lower:]')"
if ! has "$lower" "worker" && ! has "$lower" "agent"; then
  ok "(a3) control — a log line that DOES carry token_ledger/agent_type/agent_id changes nothing in the output"
else
  no "(a3) control — a log line that DOES carry token_ledger/agent_type/agent_id changes nothing in the output" "$out"
fi

echo "== (b) the three degraded cases =="

R="$TMPROOT/b1"; mkdir -p "$R" || setup_fail "mkdir b1"
run "$R"
if [ "$rc" -eq 0 ] && [ -n "$out" ] && has "$out" "Loomwright"; then
  ok "(b1) missing state.md — prints a degraded line and exits 0"
else
  no "(b1) missing state.md — prints a degraded line and exits 0" "rc=$rc out='$out'"
fi
if has "$out" "no run state"; then
  ok "(b1b) …and says so explicitly rather than printing a bare prefix"
else
  no "(b1b) …and says so explicitly rather than printing a bare prefix" "$out"
fi

R="$TMPROOT/b2"; mkdir -p "$R/.supervisor" || setup_fail "mkdir b2"
printf 'not a state file at all\n\x01\x02binary junk\nno colon-keyed lines here\n' \
  > "$R/.supervisor/state.md" || setup_fail "could not write the unparseable state fixture"
run "$R"
if [ "$rc" -eq 0 ] && [ -n "$out" ]; then
  ok "(b2) unparseable state.md — prints a degraded line and exits 0"
else
  no "(b2) unparseable state.md — prints a degraded line and exits 0" "rc=$rc out='$out'"
fi
# It must not print a bare prefix, and must not print an empty field. A doubled separator
# ("· ·") or a TRAILING separator is the shape a silently-emptied variable produces — the exact
# signature of `set -u` arithmetic on an unparsed value.
trailing_sep=0
case "$out" in *"·"|*"· ") trailing_sep=1 ;; esac
if [ "$out" != "Loomwright" ] && ! has "$out" "· ·" && [ "$trailing_sep" -eq 0 ]; then
  ok "(b2b) …with no bare prefix and no empty field artefact"
else
  no "(b2b) …with no bare prefix and no empty field artefact" "out='$out'"
fi

R="$TMPROOT/b3"; mkstate "$R" "PLAN" "main" "sid-b3" 0 3
mklog "$R" "sid-b3" ""
run "$R"
if [ "$rc" -eq 0 ] && has "$out" "PLAN" && ! has "$out" "ago"; then
  ok "(b3) empty session log — the age field is omitted, the rest still renders, exit 0"
else
  no "(b3) empty session log — the age field is omitted, the rest still renders, exit 0" "rc=$rc out='$out'"
fi

echo "== (c) the happy path =="

R="$TMPROOT/c"; mkstate "$R" "EXECUTE" "feature/demo" "sid-c" 3 4
mklog "$R" "sid-c" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
run "$R"
for want in "EXECUTE" "feature/demo" "3/4" "ago"; do
  if has "$out" "$want"; then ok "(c) the line carries '$want'"; else no "(c) the line carries '$want'" "$out"; fi
done
lines="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
if [ "$lines" = "1" ]; then
  ok "(c5) the output is exactly ONE line"
else
  no "(c5) the output is exactly ONE line" "lines=$lines out='$out'"
fi

echo "== (d) age is read from the record, never the filesystem =="

R="$TMPROOT/d"; mkstate "$R" "EXECUTE" "main" "sid-d" 1 2
old_ts="$(iso_days_ago 3)"
if [ -z "$old_ts" ]; then
  printf '  SKIP (d1) — neither date flavour could compute a 3-days-ago timestamp on this host\n'
else
  mklog "$R" "sid-d" "$old_ts"
  run "$R"
  # The log FILE was written milliseconds ago. A stat/mtime implementation would say "0s ago".
  if has "$out" "3d ago"; then
    ok "(d1) a 3-day-old ts renders '3d ago' although the file's mtime is seconds old — the record is the source, not stat"
  else
    no "(d1) a 3-day-old ts renders '3d ago' although the file's mtime is seconds old — the record is the source, not stat" \
       "ts=$old_ts out='$out'"
  fi
fi

R="$TMPROOT/d2"; mkstate "$R" "EXECUTE" "main" "sid-d2" 1 2
mklog "$R" "sid-d2" "not-a-timestamp-at-all"
run "$R"
if [ "$rc" -eq 0 ] && ! has "$out" "ago" && has "$out" "EXECUTE"; then
  ok "(d2) an unparseable ts OMITS the age field entirely and still exits 0"
else
  no "(d2) an unparseable ts OMITS the age field entirely and still exits 0" "rc=$rc out='$out'"
fi
if ! has "$out" "· ·" && ! has "$out" "  "; then
  ok "(d3) …and leaves no empty field behind (the set -u arithmetic-on-empty signature)"
else
  no "(d3) …and leaves no empty field behind (the set -u arithmetic-on-empty signature)" "out='$out'"
fi

# The script must never shell out to `stat` — the flavour trap this design avoids by
# construction. Comment lines are stripped first: the header EXPLAINS the trap (and so names
# `stat` on purpose), and matching prose would make this assertion fire on its own rationale.
# Matched as a WHOLE WORD, not a substring: `state.md`, `$STATE` and `state_field` all contain
# the letters `stat` and would make a substring match fire on every line of a script that never
# calls the command once.
stat_hits="$(grep -v '^[[:space:]]*#' "$SL" | grep -cE '(^|[^A-Za-z_])stat([^A-Za-z_]|$)' || true)"
case "$stat_hits" in ''|*[!0-9]*) stat_hits=0 ;; esac
# Control: the same matcher MUST fire on a line that really does call stat, otherwise a
# zero-hit result proves nothing about the matcher.
ctl="$(printf 'x=$(stat -f %%m "$f")\n' | grep -cE '(^|[^A-Za-z_])stat([^A-Za-z_]|$)' || true)"
[ "$ctl" = "1" ] || setup_fail "the (d4) stat matcher does not fire on a real 'stat -f' call (ctl=$ctl) — the assertion would be vacuous"
if [ "$stat_hits" -eq 0 ]; then
  ok "(d4) the source never invokes stat — the BSD/GNU succeeds-with-garbage trap is unreachable"
else
  no "(d4) the source never invokes stat — the BSD/GNU succeeds-with-garbage trap is unreachable"
fi

echo "== (e) write containment =="

R="$TMPROOT/e"; mkstate "$R" "REVIEW" "main" "sid-e" 2 2
mklog "$R" "sid-e" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
before="$(cd "$R" && find . -type f | sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(wc -c < "$f" | tr -d ' ')"; done)"
run "$R"; run "$R"
after="$(cd "$R" && find . -type f | sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(wc -c < "$f" | tr -d ' ')"; done)"
if [ "$before" = "$after" ]; then
  ok "(e) two runs create and modify nothing in the project tree"
else
  no "(e) two runs create and modify nothing in the project tree" "before/after differ"
fi

echo "== (f) fail-safe: every branch exits 0 =="

R="$TMPROOT/f"; mkstate "$R" "EXECUTE" "main" "sid-f" 1 1
mklog "$R" "sid-f" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
run "$R" --no-such-flag
if [ "$rc" -eq 0 ] && [ -n "$out" ]; then
  ok "(f1) an unknown flag is ignored and the line still renders (exit 0)"
else
  no "(f1) an unknown flag is ignored and the line still renders (exit 0)" "rc=$rc out='$out'"
fi

# An unreadable state file. Skipped under root, which bypasses mode bits entirely.
R="$TMPROOT/f2"; mkstate "$R" "EXECUTE" "main" "sid-f2" 1 1
if [ "$(id -u)" = "0" ]; then
  printf '  SKIP (f2) — running as root, which bypasses mode bits\n'
else
  chmod 000 "$R/.supervisor/state.md" || setup_fail "chmod 000 failed"
  run "$R"
  chmod 644 "$R/.supervisor/state.md" 2>/dev/null || true
  if [ "$rc" -eq 0 ] && [ -n "$out" ]; then
    ok "(f2) an unreadable state.md still prints a line and exits 0"
  else
    no "(f2) an unreadable state.md still prints a line and exits 0" "rc=$rc out='$out'"
  fi
fi

R="$TMPROOT/f3"; mkdir -p "$R" || setup_fail "mkdir f3"
out="$(printf '{"workspace":{"current_dir":"%s"}}' "$R" | bash "$SL" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [ -n "$out" ]; then
  ok "(f3) a JSON blob on stdin is accepted (current_dir honoured) and exits 0"
else
  no "(f3) a JSON blob on stdin is accepted (current_dir honoured) and exits 0" "rc=$rc out='$out'"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
