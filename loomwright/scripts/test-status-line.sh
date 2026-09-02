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
#       implementation cannot do. An UNPARSEABLE `ts` omits the field rather than emptying it,
#       and so does a ts in the FUTURE: clamping a negative delta to 0 rendered `0s ago`,
#       presenting a record from the future as if it had just happened
#   (e) write containment: the script creates and modifies nothing, asserted by checksumming
#       the whole fixture tree before and after
#   (f) fail-safe: every branch exits 0, including an unknown flag and an unreadable state file
#   (g) BOTH `## Subtasks` TABLE SHAPES are counted. Shape A (`| # | Title | Status | Review |`,
#       numeric ids, `COMPLETED (sha)`) is the live state.md; Shape B (the 7-column schema in
#       state-management/SKILL.md, ids like ST1 / subtask_1 / BD-1.2, lowercase `completed`) is
#       7 of the 17 files in .supervisor/history/. mkstate() only ever manufactured Shape A,
#       which is exactly why the suite never saw that Shape B matched ZERO rows. Includes the
#       separator-row trap (N rows must report N, never N+1), the status-is-a-COLUMN trap (a
#       subtask *titled* "Delete the COMPLETED marker handling" is not finished), the deliberate
#       FAILED/SKIPPED/ABANDONED-are-not-done choice, and TWO MUTATION CONTROLS that revert each
#       half of the widening and prove the Shape B fixture goes red without it
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

# The mirror of iso_days_ago, for a timestamp in the FUTURE. Same try-BSD-then-GNU shape;
# an empty result SKIPS the case rather than asserting against a wrong value.
iso_days_ahead() {
  local n="$1" out
  out="$(date -u -v+"${n}"d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
  [ -n "$out" ] || out="$(date -u -d "$n days" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
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

# A ts in the FUTURE. Clock skew, a hand-edited record, or a log written on another host all
# produce one, and the old `[ "$delta" -lt 0 ] && delta=0` rendered it as "0s ago" — a record
# from the future presented as "just now". The field must be OMITTED, like an unparseable ts.
R="$TMPROOT/d5"; mkstate "$R" "EXECUTE" "main" "sid-d5" 1 2
future_ts="$(iso_days_ahead 2)"
if [ -z "$future_ts" ]; then
  printf '  SKIP (d5) — neither date flavour could compute a 2-days-ahead timestamp on this host\n'
else
  mklog "$R" "sid-d5" "$future_ts"
  run "$R"
  if [ "$rc" -eq 0 ] && ! has "$out" "ago" && has "$out" "EXECUTE"; then
    ok "(d5) a ts in the FUTURE omits the age field rather than rendering '0s ago', and still exits 0"
  else
    no "(d5) a ts in the FUTURE omits the age field rather than rendering '0s ago', and still exits 0" \
       "ts=$future_ts rc=$rc out='$out'"
  fi
  # The specific wrong output the clamp produced, named so a regression is unambiguous.
  if ! has "$out" "0s ago"; then
    ok "(d6) …and specifically never prints '0s ago' for it"
  else
    no "(d6) …and specifically never prints '0s ago' for it" "out='$out'"
  fi
  if ! has "$out" "· ·" && ! has "$out" "  "; then
    ok "(d7) …and leaves no empty field behind where the age would have been"
  else
    no "(d7) …and leaves no empty field behind where the age would have been" "out='$out'"
  fi
  # Control: the same fixture with a PAST ts of the same magnitude DOES render an age, so (d5)
  # is measuring the sign of the delta and not some unrelated reason the field went missing.
  past_ts="$(iso_days_ago 2)"
  if [ -n "$past_ts" ]; then
    mklog "$R" "sid-d5" "$past_ts"
    run "$R"
    if has "$out" "2d ago"; then
      ok "(d8) control — the same fixture with a 2-day-PAST ts still renders '2d ago', so (d5) is not vacuous"
    else
      no "(d8) control — the same fixture with a 2-day-PAST ts still renders '2d ago', so (d5) is not vacuous" \
         "ts=$past_ts out='$out'"
    fi
  else
    printf '  SKIP (d8) — neither date flavour could compute a 2-days-ago timestamp on this host\n'
  fi
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

echo "== (g) both Subtasks table shapes are counted =="

# mkstate7 <root> <phase> <branch> <session_id> — a SHAPE B fixture: the 7-column schema from
# skills/state-management/SKILL.md, non-numeric ids, and the lowercase / annotated statuses that
# really occur in .supervisor/history/. Written out literally rather than generated from a
# template, so the fixture IS the shape on disk rather than a paraphrase of it. mkstate() above
# is left untouched and still manufactures Shape A — the point is that both must work.
mkstate7() {
  local root="$1" phase="$2" branch="$3" sid="$4"
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
    echo "| ID | Title | Status | Worker | Worktree | Review | Attempts |"
    echo "|----|-------|--------|--------|----------|--------|----------|"
    echo "| ST1 | lowercase completed, as history files write it | completed | task | -- | PASS | 1/3 |"
    echo "| subtask_2 | an annotated terminal status | DONE (review PASS) | task | -- | PASS | 1/3 |"
    echo "| BD-1.2 | a dotted id, still running | in_progress | task | -- | -- | 0/3 |"
    echo "| ST4 | Delete the COMPLETED marker handling | pending | -- | -- | -- | 0/3 |"
    echo
    echo "## Parallelism"
    echo "- launchable: 1"
  } > "$root/.supervisor/state.md" || setup_fail "could not write the Shape B state fixture"
}

RB="$TMPROOT/g"; mkstate7 "$RB" "EXECUTE" "feature/shape-b" "sid-g"
# FIXTURE CONTROLS. Each of (g2)/(g3) asserts that something is NOT counted; if the thing it
# names were missing from the fixture, the assertion would pass while proving nothing.
sep_rows="$(grep -c '^|----' "$RB/.supervisor/state.md" || true)"
case "$sep_rows" in ''|*[!0-9]*) sep_rows=0 ;; esac
[ "$sep_rows" -eq 1 ] || setup_fail "the Shape B fixture has $sep_rows separator rows, not 1 — (g2) would be vacuous"
has "$(cat "$RB/.supervisor/state.md")" "Delete the COMPLETED marker handling" \
  || setup_fail "the Shape B fixture lost its COMPLETED-in-the-title row — (g3) would be vacuous"

run "$RB"
if [ "$rc" -eq 0 ] && has "$out" "2/4"; then
  ok "(g1) Shape B (7-column, ids ST1/subtask_2/BD-1.2, lowercase 'completed' + 'DONE (review PASS)') counts 2/4"
else
  no "(g1) Shape B (7-column, ids ST1/subtask_2/BD-1.2, lowercase 'completed' + 'DONE (review PASS)') counts 2/4" \
     "rc=$rc out='$out'"
fi
# The classic trap: `|----|-------|...` is a table row too. A widened id matcher that forgets it
# reports N+1 subtasks — silently, and in the direction that makes a finished run look unfinished.
if ! has "$out" "/5"; then
  ok "(g2) the |----| separator row is NOT counted — 4 subtask rows report a total of 4, never 5"
else
  no "(g2) the |----| separator row is NOT counted — 4 subtask rows report a total of 4, never 5" "$out"
fi
# Status is matched as a COLUMN. The old `$0 ~ /COMPLETED/` matched the whole line, so a subtask
# whose TITLE contains the word counted as finished — here that would render 3/4.
if ! has "$out" "3/4"; then
  ok "(g3) a subtask TITLED 'Delete the COMPLETED marker handling' with status 'pending' is not counted as done"
else
  no "(g3) a subtask TITLED 'Delete the COMPLETED marker handling' with status 'pending' is not counted as done" "$out"
fi

# FAILED / SKIPPED / ABANDONED are terminal for reconcile-resume-state.sh's question, and
# deliberately NOT done for this one — see the long comment in status-line.sh. Asserted either
# way: they must appear in the total and must not appear in the done count.
RB2="$TMPROOT/g2"; mkdir -p "$RB2/.supervisor" || setup_fail "mkdir g2"
{
  echo "## Session"; echo "- phase: EXECUTE"; echo "- branch: main"; echo
  echo "## Subtasks"
  echo "| ID | Title | Status | Worker | Worktree | Review | Attempts |"
  echo "|----|-------|--------|--------|----------|--------|----------|"
  echo "| ST1 | ok | completed | task | -- | PASS | 1/3 |"
  echo "| ST2 | broke | failed | task | -- | -- | 3/3 |"
  echo "| ST3 | not needed | skipped | -- | -- | -- | 0/3 |"
  echo "| ST4 | dropped | abandoned | -- | -- | -- | 0/3 |"
  echo "| ST5 | landed | MERGED | task | -- | PASS | 1/3 |"
} > "$RB2/.supervisor/state.md" || setup_fail "could not write the terminal-status fixture"
run "$RB2"
if has "$out" "2/5"; then
  ok "(g4) FAILED/SKIPPED/ABANDONED count toward the TOTAL but never toward DONE (2/5, not 5/5 and not 2/2)"
else
  no "(g4) FAILED/SKIPPED/ABANDONED count toward the TOTAL but never toward DONE (2/5, not 5/5 and not 2/2)" "$out"
fi

# The annotated forms reconcile-resume-state.sh documents, matched on the status' first word.
RB3="$TMPROOT/g3"; mkdir -p "$RB3/.supervisor" || setup_fail "mkdir g3"
{
  echo "## Session"; echo "- phase: EXECUTE"; echo "- branch: main"; echo
  echo "## Subtasks"
  echo "| ID | Title | Status | Worker | Worktree | Review | Attempts |"
  echo "|----|-------|--------|--------|----------|--------|----------|"
  echo "| ST1 | escalated but finished | COMPLETED WITH ESCALATION | task | -- | PASS | 1/3 |"
  echo "| ST2 | colon form | DONE: merged to main | task | -- | PASS | 1/3 |"
  echo "| ST3 | bare complete | COMPLETE | task | -- | PASS | 1/3 |"
  echo "| ST4 | waiting | pending | -- | -- | -- | 0/3 |"
} > "$RB3/.supervisor/state.md" || setup_fail "could not write the annotated-status fixture"
run "$RB3"
if has "$out" "3/4"; then
  ok "(g5) the annotated terminal forms COMPLETED WITH ESCALATION / DONE: / COMPLETE all count (3/4)"
else
  no "(g5) the annotated terminal forms COMPLETED WITH ESCALATION / DONE: / COMPLETE all count (3/4)" "$out"
fi

# Non-regression: the widening must not cost Shape A, which is what the live state.md is.
RA="$TMPROOT/ga"; mkstate "$RA" "EXECUTE" "main" "sid-ga" 3 4
run "$RA"
if has "$out" "3/4"; then
  ok "(g6) Shape A (4-column, numeric ids, 'COMPLETED (abc1233)') still counts 3/4 — no regression"
else
  no "(g6) Shape A (4-column, numeric ids, 'COMPLETED (abc1233)') still counts 3/4 — no regression" "$out"
fi

echo "== (g7/g8) MUTATION CONTROLS: revert each half of the widening, Shape B goes red =="
# Both mutants are COPIES in $TMPROOT; status-line.sh on disk is never edited. Each is gated on
# being non-empty, differing from the original, landing EXACTLY the intended one-line change, and
# still parsing — a mutant that is empty or unparseable proves nothing, and a control never
# observed failing is not evidence. Each also has to still RENDER against Shape A, so "the field
# vanished" cannot be explained by the mutant simply having crashed.
runmut() { mout="$(bash "$1" --root "$2" </dev/null 2>&1)"; mrc=$?; }
mutant_ok() {  # <file> <label> <orig-count-in-SL> <stub-count-in-mutant>
  local f="$1" label="$2" o="$3" s="$4"
  if [ ! -s "$f" ];              then no "$label — mutant is EMPTY (vacuous control)"; return 1; fi
  if cmp -s "$SL" "$f";          then no "$label — mutant is identical to the original (vacuous control)"; return 1; fi
  if [ "$o" -ne 1 ] || [ "$s" -ne 1 ]; then
    no "$label — the mutation did not land as intended (orig=$o stub=$s)"; return 1; fi
  if ! bash -n "$f" 2>/dev/null; then no "$label — mutant does not parse (vacuous control)"; return 1; fi
  return 0
}

# (g7) revert the ID widening: require a bare-integer id again, exactly as before this change.
M1="$TMPROOT/mut-narrow-id.sh"
o1="$(grep -c '^[[:space:]]*ok_id = (id != ""' "$SL" || true)"; case "$o1" in ''|*[!0-9]*) o1=0 ;; esac
sed -e 's%^\([[:space:]]*\)ok_id = .*%\1ok_id = (id ~ /^[0-9]+$/)%' "$SL" > "$M1"
s1="$(grep -c '^[[:space:]]*ok_id = (id ~ /\^\[0-9\]+\$/)$' "$M1" || true)"; case "$s1" in ''|*[!0-9]*) s1=0 ;; esac
if mutant_ok "$M1" "(g7) id-narrowing mutant" "$o1" "$s1"; then
  ok "(g7) the id-narrowing mutant is NON-VACUOUS: non-empty, differs from the original, parses, 1 widened guard replaced by 1 numeric-only guard"
  runmut "$M1" "$RA"
  if [ "$mrc" -eq 0 ] && has "$mout" "3/4"; then
    ok "(g7) …and it still renders Shape A (3/4), so it runs — a missing field below is behavioural"
    runmut "$M1" "$RB"
    if ! has "$mout" "2/4"; then
      ok "(g7) CONFIRMED: with the id widening reverted, the Shape B fixture loses its N/M field entirely — (g1) is load-bearing"
    else
      no "(g7) REFUTED: the narrowed mutant still counted Shape B — (g1) passes for some other reason and is vacuous" "$mout"
    fi
  else
    no "(g7) INCONCLUSIVE: the mutant did not render Shape A either (rc=$mrc) — it discriminated nothing" "$mout"
  fi
fi

# (g8) revert the DONE widening: exact-case COMPLETED only, as the bare literal did.
M2="$TMPROOT/mut-narrow-done.sh"
o2="$(grep -c '^[[:space:]]*is_done = (ust == "DONE"' "$SL" || true)"; case "$o2" in ''|*[!0-9]*) o2=0 ;; esac
sed -e 's%^\([[:space:]]*\)is_done = .*%\1is_done = (st == "COMPLETED")%' "$SL" > "$M2"
s2="$(grep -c '^[[:space:]]*is_done = (st == "COMPLETED")$' "$M2" || true)"; case "$s2" in ''|*[!0-9]*) s2=0 ;; esac
if mutant_ok "$M2" "(g8) done-narrowing mutant" "$o2" "$s2"; then
  ok "(g8) the done-narrowing mutant is NON-VACUOUS: non-empty, differs from the original, parses, 1 terminal-set match replaced by 1 exact-case COMPLETED match"
  runmut "$M2" "$RA"
  if [ "$mrc" -eq 0 ] && has "$mout" "3/4"; then
    ok "(g8) …and it still renders Shape A (3/4), so the two halves of the fix are independent"
    runmut "$M2" "$RB"
    if has "$mout" "0/4" && ! has "$mout" "2/4"; then
      ok "(g8) CONFIRMED: with the terminal-status set reverted, Shape B's lowercase 'completed' and 'DONE (review PASS)' count as 0/4 — the case-insensitive vocabulary is load-bearing"
    else
      no "(g8) REFUTED: the narrowed mutant still counted Shape B's done rows — (g1)'s numerator is vacuous" "$mout"
    fi
  else
    no "(g8) INCONCLUSIVE: the mutant did not render Shape A either (rc=$mrc) — it discriminated nothing" "$mout"
  fi
fi
rm -f "$M1" "$M2" 2>/dev/null   # a mutated reader must never outlive its own control

# The original on disk was never touched by either control.
run "$RB"
if has "$out" "2/4"; then
  ok "(g9) control — the real status-line.sh still counts the Shape B fixture 2/4 after both mutations"
else
  no "(g9) control — the real status-line.sh still counts the Shape B fixture 2/4 after both mutations" "$out"
fi

echo "== (g10) a row with NO Status column is not counted at all =="

# The widening reads Status as data column 3. A table with only two data columns has none, and
# substituting an empty status while still incrementing the total renders `0/N` — a WRONG NUMBER
# for a shape this reader does not understand, on a surface contracted to OMIT what it cannot
# resolve. Same failure class as the bare-literal `COMPLETED` test, relocated to a different input.
R="$TMPROOT/g10"; mkdir -p "$R/.supervisor" || setup_fail "mkdir g10"
{
  echo "## Session"; echo "- phase: EXECUTE"; echo "- branch: main"; echo
  echo "## Subtasks"
  echo "| ID | Title |"
  echo "|----|-------|"
  echo "| subtask_1 | a two-column table has no Status column |"
  echo "| subtask_2 | so neither row may be scored |"
} > "$R/.supervisor/state.md" || setup_fail "could not write the g10 fixture"
run "$R"
if [ "$rc" -eq 0 ] && has "$out" "EXECUTE" && ! has "$out" "0/2" && ! has "$out" "/2"; then
  ok "(g10) a 2-column table is unreadable — the N/M field is OMITTED, the rest of the line still renders, exit 0"
else
  no "(g10) a 2-column table is unreadable — the N/M field is OMITTED, the rest of the line still renders, exit 0" "rc=$rc out='$out'"
fi

# Control: the SAME two rows with a Status column present DO get counted. Without this, (g10)
# would also pass against an implementation that had simply stopped counting anything.
R="$TMPROOT/g10c"; mkdir -p "$R/.supervisor" || setup_fail "mkdir g10c"
{
  echo "## Session"; echo "- phase: EXECUTE"; echo "- branch: main"; echo
  echo "## Subtasks"
  echo "| ID | Title | Status |"
  echo "|----|-------|--------|"
  echo "| subtask_1 | now there is a status column | completed |"
  echo "| subtask_2 | and this one is not done | pending |"
} > "$R/.supervisor/state.md" || setup_fail "could not write the g10c fixture"
run "$R"
if has "$out" "1/2"; then
  ok "(g10c) control — the same rows WITH a Status column render 1/2, so (g10) is not vacuous"
else
  no "(g10c) control — the same rows WITH a Status column render 1/2, so (g10) is not vacuous" "$out"
fi

# Mutation control for (g10): reinstate the empty-status substitution and the wrong number returns.
# A FAITHFUL revert to the pre-fix code, not merely a line swap: the guard is deleted AND
# `st = c[4]` goes back to the `(n >= 5 ? c[4] : "")` substitution, so the mutant carries exactly
# ONE `st` assignment. An earlier version replaced only the guard line and left the unconditional
# `st = c[4]` below it, which overwrote the reinstated ternary — the mutant still flipped
# behaviour, because DELETING THE GUARD is what does that, but its label claimed to reinstate a
# substitution that was never the operative line. A control that discriminates for a different
# reason than it states is the same class of defect this suite exists to catch. (Review of #173.)
M3="$TMPROOT/mut-empty-status.sh"
g_orig="$(grep -c '^[[:space:]]*if (n < 5) next$' "$SL" || true)"; case "$g_orig" in ''|*[!0-9]*) g_orig=0 ;; esac
a_orig="$(grep -c '^[[:space:]]*st = c\[4\]; gsub' "$SL" || true)"; case "$a_orig" in ''|*[!0-9]*) a_orig=0 ;; esac
o3=0; [ "$g_orig" -eq 1 ] && [ "$a_orig" -eq 1 ] && o3=1
sed -e 's%^\([[:space:]]*\)if (n < 5) next$%\1# guard deleted by the mutant%' \
    -e 's%^\([[:space:]]*\)st = c\[4\]; gsub%\1st = (n >= 5 ? c[4] : ""); gsub%' "$SL" > "$M3"
g_stub="$(grep -c '^[[:space:]]*if (n < 5) next$' "$M3" || true)"; case "$g_stub" in ''|*[!0-9]*) g_stub=0 ;; esac
t_stub="$(grep -c '^[[:space:]]*st = (n >= 5 ? c\[4\] : ""); gsub' "$M3" || true)"; case "$t_stub" in ''|*[!0-9]*) t_stub=0 ;; esac
n_stub="$(grep -c '^[[:space:]]*st = ' "$M3" || true)"; case "$n_stub" in ''|*[!0-9]*) n_stub=0 ;; esac
# guard gone, ternary present, and it is the ONLY st assignment — nothing overwrites it.
s3=0; [ "$g_stub" -eq 0 ] && [ "$t_stub" -eq 1 ] && [ "$n_stub" -eq 1 ] && s3=1
if mutant_ok "$M3" "(g10) empty-status mutant" "$o3" "$s3"; then
  ok "(g10) the empty-status mutant is NON-VACUOUS: non-empty, differs from the original, parses, guard deleted and the empty-status substitution restored as the SOLE st assignment"
  runmut "$M3" "$RA"
  if [ "$mrc" -eq 0 ] && has "$mout" "3/4"; then
    ok "(g10) …and it still renders Shape A (3/4), so it runs — a wrong number below is behavioural"
    runmut "$M3" "$TMPROOT/g10"
    if has "$mout" "0/2"; then
      ok "(g10) CONFIRMED: with the substitution reinstated the 2-column table renders the WRONG NUMBER 0/2 — the guard is load-bearing"
    else
      no "(g10) REFUTED: the mutant did not produce 0/2 — (g10) passes for some other reason and is vacuous" "$mout"
    fi
  else
    no "(g10) INCONCLUSIVE: the mutant did not render Shape A either (rc=$mrc) — it discriminated nothing" "$mout"
  fi
fi

echo "== (h) the DONE vocabulary is pinned to reconcile-resume-state.sh, not copied =="

# The DONE set here is deliberately a SUBSET of reconcile's is_terminal_status() — FAILED /
# SKIPPED / ABANDONED are terminal for "is anything left to re-run" but must never score as
# progress. That divergence is only safe while it stays a *declared partition* of one vocabulary.
# Copied by hand it silently rots: a keyword added to reconcile would go unclassified here and
# land in the not-done branch with nothing failing. So the set is extracted from reconcile AT TEST
# TIME and every member is required to be classified by status-line, one way or the other.
RECON="$script_dir/reconcile-resume-state.sh"
if [ ! -f "$RECON" ]; then
  printf '  SKIP (h) — reconcile-resume-state.sh not found at %s\n' "$RECON"
else
  recon_raw="$(sed -n '/^is_terminal_status()/,/^}/p' "$RECON" | grep -F ') return 0 ;;' | head -1 \
               | sed 's/).*//; s/^[[:space:]]*//')"
  [ -n "$recon_raw" ] || setup_fail "could not extract is_terminal_status()'s keyword arm from $RECON — the (h) assertions would be vacuous"
  recon_set="$(printf '%s' "$recon_raw" | tr '|' '\n' | sed '/^$/d' | sort -u)"
  recon_n="$(printf '%s\n' "$recon_set" | grep -c . || true)"; case "$recon_n" in ''|*[!0-9]*) recon_n=0 ;; esac
  # A one-element extraction would make the coverage test pass trivially; reconcile's arm has many.
  [ "$recon_n" -ge 4 ] || setup_fail "extracted only $recon_n keyword(s) from $RECON — extraction is broken"

  # status-line's own DONE set, read out of the `is_done` line it actually evaluates — not out of
  # a comment, so this cannot drift from the code underneath it.
  sl_done="$(grep -F 'is_done = (ust == ' "$SL" | head -1 | grep -o '"[A-Z:]*"' | tr -d '"' | sed '/^$/d' | sort -u)"
  sl_n="$(printf '%s\n' "$sl_done" | grep -c . || true)"; case "$sl_n" in ''|*[!0-9]*) sl_n=0 ;; esac
  [ "$sl_n" -ge 2 ] || setup_fail "extracted only $sl_n keyword(s) from status-line.sh's is_done line — the (h) assertions would be vacuous"

  # (h1) status-line's DONE set must be drawn ENTIRELY from reconcile's vocabulary — no keyword
  # invented here that reconcile has never heard of.
  extra="$(comm -23 <(printf '%s\n' "$sl_done") <(printf '%s\n' "$recon_set") | tr '\n' ' ')"
  if [ -z "$(printf '%s' "$extra" | tr -d ' ')" ]; then
    ok "(h1) every DONE keyword status-line scores is drawn from reconcile's is_terminal_status() — one vocabulary, not two"
  else
    no "(h1) every DONE keyword status-line scores is drawn from reconcile's is_terminal_status() — one vocabulary, not two" \
       "invented here, unknown to reconcile: $extra"
  fi

  # (h2) THE DRIFT GATE. Every keyword reconcile knows must be CLASSIFIED here — either scored as
  # done, or named in the not-done exclusion comment as a deliberate exclusion. A keyword added to
  # reconcile that matches neither is an unreviewed silent default, and this fails.
  unclassified=""
  for kw in $recon_set; do
    if printf '%s\n' "$sl_done" | grep -Fqx "$kw"; then continue; fi
    grep -Fq "$kw" "$SL" && continue
    unclassified="$unclassified $kw"
  done
  if [ -z "$unclassified" ]; then
    ok "(h2) every keyword reconcile treats as terminal is classified here — scored as done, or named as a deliberate exclusion"
  else
    no "(h2) every keyword reconcile treats as terminal is classified here — scored as done, or named as a deliberate exclusion" \
       "reconcile grew keyword(s) status-line neither scores nor excludes:$unclassified"
  fi

  # (h3) The exclusion is not merely documented — it is rendered and checked. A subtask that
  # FAILED must never inflate N/M into looking like success.
  h_bad=""
  for kw in $(comm -13 <(printf '%s\n' "$sl_done") <(printf '%s\n' "$recon_set")); do
    R="$TMPROOT/h-$(printf '%s' "$kw" | tr -c 'A-Za-z0-9' '_')"; mkdir -p "$R/.supervisor" || setup_fail "mkdir h"
    {
      echo "## Session"; echo "- phase: EXECUTE"; echo "- branch: main"; echo
      echo "## Subtasks"
      echo "| ID | Title | Status | Worker | Worktree | Review | Attempts |"
      echo "|----|-------|--------|--------|----------|--------|----------|"
      echo "| subtask_1 | a subtask in a terminal-but-not-successful state | $kw | -- | -- | -- | 1/3 |"
    } > "$R/.supervisor/state.md" || setup_fail "could not write the (h3) fixture for $kw"
    run "$R"
    has "$out" "0/1" || h_bad="$h_bad $kw(expected 0/1, got '$out')"
  done
  if [ -z "$h_bad" ]; then
    ok "(h3) every terminal-but-not-successful keyword renders 0/1 — a failed subtask never inflates N/M"
  else
    no "(h3) every terminal-but-not-successful keyword renders 0/1 — a failed subtask never inflates N/M" "$h_bad"
  fi
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
