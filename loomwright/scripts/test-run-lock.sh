#!/usr/bin/env bash
# test-run-lock.sh — self-tests for scripts/run-lock.sh (single-run-per-repo
# lock). Isolated: every fixture lives under a fresh mktemp -d, the SUT is
# invoked as a subprocess (never sourced), and `--root` pins it there so the
# real repo's `.supervisor/` is never touched. Exit 0 = all pass.
#
# Covers:
#   1. acquire on a checkout with no lock -> succeeds, rc=0, lock dir + meta created.
#   2. a SECOND acquire (different owner) while held -> prints
#      `run_lock_held owner=<label> pid=<pid> age=<s>` and exits non-zero.
#   3. status reflects LOCKED with the holder's owner/pid/age.
#   4. status on an unlocked checkout -> UNLOCKED.
#   5. release by the SAME owner that holds it -> lock cleared.
#   6. release by a DIFFERENT owner/session-id -> idempotent no-op, lock still held.
#   7. release by matching --session-id (not --owner) -> lock cleared (the
#      close-stranded-run.sh seam).
#   8. release when nothing is locked -> idempotent no-op success, rc=0.
#   9. dead pid + age >= 1800s -> RECLAIMS (second acquire succeeds).
#  10. dead pid + age < 1800s -> REFUSES (does not reclaim early).
#  11. live pid (self) + old ts -> REFUSES (pid liveness wins over TTL).
#  12. --force-unlock breaks a live, non-reclaimable lock and prints what it broke.
#  13. acquire with no --owner -> non-zero exit (bad usage), never a silent success.
#  14. unknown subcommand -> non-zero exit.
#  --- Mutation control ---
#  15. mutating the RECLAIM guard (`[ "$pid_alive" -eq 0 ]`) to always treat the
#      pid as alive makes a genuinely-reclaimable stale lock (dead pid, old ts)
#      NEVER reclaim -- proving the pid-liveness check in test 9 is load-bearing.
#  --- Static prose seam (PR #253 review) ---
#  16. all THREE lock-acquire prose call sites (agents/supervisor.md,
#      skills/supervisor-config/SKILL.md, skills/autonomous-loop/SKILL.md) --
#      like /automate PICK's own acquire call in skills/automate-loop/SKILL.md --
#      pass `--session-id` on their `run-lock.sh acquire` invocation line, so the
#      lock's meta `session_id` field is actually populated for crash recovery
#      (`close-stranded-run.sh` releases by matching `session_id`, not `owner`).
#      A caller whose acquire line omits `--session-id` leaves that field empty
#      and its lock is un-reclaimable by that path -- this is a grep on the
#      committed prose, not an execution trace (markdown, not code; mirrors the
#      static PART 1 convention in test-rules-seams.sh).
#  --- Holder liveness + re-entrancy (automate-2026-09-26-115755 regression) ---
#  17. BASH-TOOL REPRODUCTION: acquire from an ephemeral shell that exits
#      (the Claude Code Bash tool's shell) under a live fake `claude`
#      ($CLAUDE_PID) -> meta pid is the fake claude, NOT the exited shell; with
#      the lock aged past the TTL, a second acquire with a DIFFERENT owner AND
#      DIFFERENT session is REFUSED; once the fake claude dies the same acquire
#      reclaims (dead + old). Mutation control: a copy recording the old `$$`
#      reclaims in the identical scenario -- proving 17 detects the incident.
#  18. no $CLAUDE_PID (or a dead one) -> meta pid is the invoking shell ($PPID).
#  19. same-session nested acquire (automate -> supervisor) is RE-ENTRANT:
#      rc=0, prints run_lock_reentrant, owner stays the OUTER label; the inner
#      `release --owner <inner>` is a no-op and only the outer release clears it.
#  20. under Claude Code (CLAUDECODE set) WITHOUT $CLAUDE_PID -> the first
#      non-shell ancestor (a long-lived perl standing in for `claude`) is
#      recorded with pid_source=ancestor, and a different session is refused
#      past the TTL -- the fix survives CLAUDE_PID (undocumented) disappearing.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/run-lock.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

fresh_root() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/.supervisor"
  printf '%s' "$d"
}

run_sut() {
  RUN_OUT="$(bash "$SUT" "$@" 2>&1)"
  RUN_RC=$?
}

lock_dir() { printf '%s/.supervisor/run.lock' "$1"; }
meta_file() { printf '%s/.supervisor/run.lock/meta' "$1"; }

set_meta_field() {
  # set_meta_field <root> <key> <value>
  local m; m="$(meta_file "$1")"
  awk -F'\t' -v k="$2" -v v="$3" 'BEGIN{OFS="\t"} $1==k{$2=v; found=1} {print} END{if(!found) print k, v}' "$m" > "${m}.tmp"
  mv -f "${m}.tmp" "$m"
}

echo "== 1. acquire on an unlocked checkout succeeds =="
D1="$(fresh_root)"
run_sut acquire --owner automate:run1 --root "$D1"
if [ "$RUN_RC" -eq 0 ] && [ -d "$(lock_dir "$D1")" ] && [ -f "$(meta_file "$D1")" ]; then
  ok "acquire succeeded, lock dir + meta present"
else
  no "acquire failed or did not create lock: rc=$RUN_RC out='$RUN_OUT'"
fi

echo "== 2. second acquire while held -> run_lock_held + non-zero exit =="
run_sut acquire --owner automate:run2 --root "$D1"
if [ "$RUN_RC" -ne 0 ] && grep -qE '^run_lock_held owner=automate:run1 pid=[0-9]+ age=[0-9]+$' < <(printf '%s' "$RUN_OUT"); then
  ok "second acquire refused: $RUN_OUT"
else
  no "second acquire should have printed run_lock_held + exit non-zero: rc=$RUN_RC out='$RUN_OUT'"
fi

echo "== 3. status reflects LOCKED =="
run_sut status --root "$D1"
if [ "$RUN_RC" -eq 0 ] && grep -qE '^LOCKED owner=automate:run1 pid=[0-9]+ age=[0-9]+$' < <(printf '%s' "$RUN_OUT"); then
  ok "status LOCKED: $RUN_OUT"
else
  no "status wrong: rc=$RUN_RC out='$RUN_OUT'"
fi

echo "== 4. status on a fresh unlocked checkout -> UNLOCKED =="
D4="$(fresh_root)"
run_sut status --root "$D4"
if [ "$RUN_RC" -eq 0 ] && [ "$RUN_OUT" = "UNLOCKED" ]; then
  ok "status UNLOCKED"
else
  no "status should be UNLOCKED: rc=$RUN_RC out='$RUN_OUT'"
fi

echo "== 5. release by the owning label clears the lock =="
run_sut release --owner automate:run1 --root "$D1"
run_sut status --root "$D1"
if [ "$RUN_OUT" = "UNLOCKED" ]; then
  ok "release by owner cleared the lock"
else
  no "release by owner did not clear: $RUN_OUT"
fi

echo "== 6. release by a different owner/session-id is an idempotent no-op =="
D6="$(fresh_root)"
run_sut acquire --owner automate:runA --session-id sessA --root "$D6"
run_sut release --owner automate:runB --session-id sessB --root "$D6"
run_sut status --root "$D6"
if grep -q '^LOCKED owner=automate:runA' < <(printf '%s' "$RUN_OUT"); then
  ok "release by non-owning owner/session left the lock intact: $RUN_OUT"
else
  no "release by non-owning owner/session should NOT have cleared the lock: $RUN_OUT"
fi

echo "== 7. release by matching --session-id clears the lock (close-stranded-run.sh seam) =="
run_sut release --session-id sessA --root "$D6"
run_sut status --root "$D6"
if [ "$RUN_OUT" = "UNLOCKED" ]; then
  ok "release by matching session-id cleared the lock"
else
  no "release by matching session-id did not clear: $RUN_OUT"
fi

echo "== 8. release when nothing is locked -> idempotent no-op, rc=0 =="
D8="$(fresh_root)"
run_sut release --owner whoever --root "$D8"
if [ "$RUN_RC" -eq 0 ]; then
  ok "release on unlocked checkout is a no-op success"
else
  no "release on unlocked checkout should be rc=0: rc=$RUN_RC out='$RUN_OUT'"
fi

echo "== 9. dead pid + age >= 1800s -> RECLAIMS =="
D9="$(fresh_root)"
run_sut acquire --owner automate:stale --root "$D9"
set_meta_field "$D9" pid 999999
set_meta_field "$D9" ts 1
run_sut acquire --owner automate:reclaimer --root "$D9"
if [ "$RUN_RC" -eq 0 ]; then
  run_sut status --root "$D9"
  if grep -q 'owner=automate:reclaimer' < <(printf '%s' "$RUN_OUT"); then
    ok "stale lock (dead pid, age >= TTL) reclaimed by new acquirer"
  else
    no "reclaim succeeded but owner not updated: $RUN_OUT"
  fi
else
  no "stale lock should have been reclaimed: rc=$RUN_RC out='$RUN_OUT'"
fi

echo "== 10. dead pid + age < 1800s -> REFUSES (no early reclaim) =="
D10="$(fresh_root)"
run_sut acquire --owner automate:young --root "$D10"
set_meta_field "$D10" pid 999999
NOW="$(date +%s)"
set_meta_field "$D10" ts "$((NOW - 10))"
run_sut acquire --owner automate:impatient --root "$D10"
if [ "$RUN_RC" -ne 0 ] && grep -q 'owner=automate:young' < <(printf '%s' "$RUN_OUT"); then
  ok "young stale lock correctly refused early reclaim: $RUN_OUT"
else
  no "young stale lock should have refused reclaim: rc=$RUN_RC out='$RUN_OUT'"
fi

echo "== 11. live pid (self) + old ts -> REFUSES (liveness wins over TTL) =="
D11="$(fresh_root)"
run_sut acquire --owner automate:live --root "$D11"
set_meta_field "$D11" pid "$$"
set_meta_field "$D11" ts 1
run_sut acquire --owner automate:other --root "$D11"
if [ "$RUN_RC" -ne 0 ] && grep -q 'owner=automate:live' < <(printf '%s' "$RUN_OUT"); then
  ok "live pid with old ts still refused (liveness gates TTL): $RUN_OUT"
else
  no "live pid should refuse regardless of age: rc=$RUN_RC out='$RUN_OUT'"
fi

echo "== 12. --force-unlock breaks a live lock and prints what it broke =="
D12="$(fresh_root)"
run_sut acquire --owner automate:victim --root "$D12"
run_sut acquire --owner automate:forcer --force-unlock --root "$D12"
if [ "$RUN_RC" -eq 0 ] && grep -q 'force-unlock: broke run_lock_held owner=automate:victim' < <(printf '%s' "$RUN_OUT"); then
  run_sut status --root "$D12"
  if grep -q 'owner=automate:forcer' < <(printf '%s' "$RUN_OUT"); then
    ok "force-unlock broke the old lock and acquired a new one"
  else
    no "force-unlock reported breaking the lock but new owner not recorded: $RUN_OUT"
  fi
else
  no "force-unlock should report what it broke: rc=$RUN_RC out='$RUN_OUT'"
fi

echo "== 13. acquire with no --owner -> non-zero exit =="
D13="$(fresh_root)"
run_sut acquire --root "$D13"
if [ "$RUN_RC" -ne 0 ]; then
  ok "acquire without --owner rejected"
else
  no "acquire without --owner should not succeed: $RUN_OUT"
fi

echo "== 14. unknown subcommand -> non-zero exit =="
run_sut frobnicate --root "$D13"
if [ "$RUN_RC" -ne 0 ]; then
  ok "unknown subcommand rejected"
else
  no "unknown subcommand should not succeed: $RUN_OUT"
fi

echo "== 15. MUTATION CONTROL: forcing pid_alive=1 always disables reclaim =="
MUTDIR="$(mktemp -d)"
MUT="$MUTDIR/run-lock.sh"
cp "$SUT" "$MUT"
sed -i.bak 's/pid_alive=0/pid_alive=1/' "$MUT"
if bash -n "$MUT" 2>/dev/null && ! diff -q "$MUT" "$SUT" >/dev/null 2>&1; then
  D15="$(fresh_root)"
  bash "$MUT" acquire --owner automate:stale --root "$D15" >/dev/null 2>&1
  set_meta_field "$D15" pid 999999
  set_meta_field "$D15" ts 1
  MUT_OUT="$(bash "$MUT" acquire --owner automate:reclaimer --root "$D15" 2>&1)"
  MUT_RC=$?
  if [ "$MUT_RC" -ne 0 ] && grep -q 'owner=automate:stale' < <(printf '%s' "$MUT_OUT"); then
    ok "mutation control: forcing pid_alive=1 blocks the genuinely-reclaimable stale lock from test 9 -- the liveness check is load-bearing"
  else
    no "mutation control REFUTED: mutant still reclaimed the stale lock -- pid_alive guard may not be load-bearing (mutant rc=$MUT_RC out='$MUT_OUT')"
  fi
else
  no "mutation control: could not build the mutant (sed did not apply or bash -n failed) -- control inconclusive"
fi
rm -rf "$MUTDIR"

echo "== 16. STATIC: prose lock-acquire call sites all pass --session-id =="
PLUGIN_ROOT="$(cd "$HERE/.." && pwd)"
check_acquire_has_session_id() {
  # check_acquire_has_session_id <label> <file> -- greps every line in <file>
  # containing the CONTIGUOUS phrase "run-lock.sh acquire --owner" (an actual
  # acquire-invocation shape, not merely a line that separately mentions both
  # "acquire" and "--owner" -- e.g. a `release --owner ...` line that also
  # name-drops "run-lock.sh acquire" in prose must NOT count), and asserts
  # EACH such line also contains "--session-id" (the crash-recovery-matching
  # flag). A file with no such line at all is a setup failure (the seam moved
  # or vanished), not a pass -- so this also asserts at least one line was found.
  local label="$1" file="$2" line hits=0 all_ok=1
  if [ ! -f "$file" ]; then
    no "$label: file not found: $file"
    return
  fi
  while IFS= read -r line; do
    hits=$((hits+1))
    case "$line" in
      *--session-id*) : ;;
      *) all_ok=0 ;;
    esac
  done < <(grep -F 'run-lock.sh acquire --owner' "$file")
  if [ "$hits" -eq 0 ]; then
    no "$label: no 'run-lock.sh acquire ... --owner' line found in $file -- seam moved or vanished"
  elif [ "$all_ok" -eq 1 ]; then
    ok "$label: all $hits acquire line(s) in $file carry --session-id"
  else
    no "$label: at least one acquire line in $file is missing --session-id"
  fi
}
check_acquire_has_session_id "Supervisor Phase 0 (agents/supervisor.md)" "$PLUGIN_ROOT/agents/supervisor.md"
check_acquire_has_session_id "supervisor-config SKILL step 0" "$PLUGIN_ROOT/skills/supervisor-config/SKILL.md"
check_acquire_has_session_id "autonomous-loop SKILL INIT" "$PLUGIN_ROOT/skills/autonomous-loop/SKILL.md"
check_acquire_has_session_id "automate-loop SKILL PICK (reference shape)" "$PLUGIN_ROOT/skills/automate-loop/SKILL.md"

echo "== 17. Bash-tool reproduction: ephemeral acquirer shell, live claude, different session -> REFUSED =="
# fake_claude — a long-lived stand-in for the session's `claude` process.
sleep 600 & FAKE_CLAUDE=$!
D17="$(fresh_root)"
# The acquirer runs in its own `bash -c` shell that exits right after, exactly
# like a Claude Code Bash-tool call.
CLAUDE_PID="$FAKE_CLAUDE" bash -c 'bash "$1" acquire --owner automate:run17 --session-id sess-auto --root "$2"' _ "$SUT" "$D17" >/dev/null 2>&1
rec_pid="$(awk -F'\t' '$1=="pid"{print $2}' "$(meta_file "$D17")")"
if [ "$rec_pid" = "$FAKE_CLAUDE" ]; then
  ok "meta pid is the live claude process ($rec_pid), not the exited acquirer shell"
else
  no "meta pid should be \$CLAUDE_PID=$FAKE_CLAUDE, got '$rec_pid'"
fi
set_meta_field "$D17" ts 1   # the incident: launch-pad ran past the 1800s TTL
S17_OUT="$(CLAUDE_PID="$FAKE_CLAUDE" bash -c 'bash "$1" acquire --owner supervisor:sess-other --session-id sess-other --root "$2"' _ "$SUT" "$D17" 2>&1)"
S17_RC=$?
if [ "$S17_RC" -ne 0 ] && grep -q '^run_lock_held owner=automate:run17 ' < <(printf '%s' "$S17_OUT"); then
  ok "different owner + different session refused while claude lives, even past the TTL: $S17_OUT"
else
  no "different-session acquire must be REFUSED (rc=$S17_RC out='$S17_OUT')"
fi
kill "$FAKE_CLAUDE" 2>/dev/null; wait "$FAKE_CLAUDE" 2>/dev/null
run_sut acquire --owner supervisor:sess-other --session-id sess-other --root "$D17"
run_sut status --root "$D17"
if grep -q 'owner=supervisor:sess-other' < <(printf '%s' "$RUN_OUT"); then
  ok "once claude is dead (and age >= TTL) the lock reclaims"
else
  no "dead claude + old lock should reclaim: $RUN_OUT"
fi
# Mutation control: restore the pre-fix `$$` pid recording in a copy.
MUT17DIR="$(mktemp -d)"; MUT17="$MUT17DIR/run-lock.sh"
cp "$SUT" "$MUT17"
sed -i.bak 's/"\$hp"/"$$"/' "$MUT17"
if bash -n "$MUT17" 2>/dev/null && ! diff -q "$MUT17" "$SUT" >/dev/null 2>&1 && grep -qF "'pid\t%s\n' \"\$\$\"" "$MUT17"; then
  sleep 600 & FAKE2=$!
  D17M="$(fresh_root)"
  CLAUDE_PID="$FAKE2" bash -c 'bash "$1" acquire --owner automate:run17 --session-id sess-auto --root "$2"' _ "$MUT17" "$D17M" >/dev/null 2>&1
  set_meta_field "$D17M" ts 1
  CLAUDE_PID="$FAKE2" bash -c 'bash "$1" acquire --owner supervisor:sess-other --session-id sess-other --root "$2"' _ "$MUT17" "$D17M" >/dev/null 2>&1
  M17_RC=$?
  kill "$FAKE2" 2>/dev/null; wait "$FAKE2" 2>/dev/null
  if [ "$M17_RC" -eq 0 ]; then
    ok "mutation control: the pre-fix \$\$ recording reclaims in the identical scenario -- test 17 detects the incident"
  else
    no "mutation control REFUTED: pre-fix mutant also refused (rc=$M17_RC) -- test 17 would not have caught the incident"
  fi
else
  no "mutation control: could not build the \$\$ mutant (sed did not apply) -- control inconclusive"
fi
rm -rf "$MUT17DIR"

echo "== 18. outside Claude Code, no / dead \$CLAUDE_PID -> meta pid is the invoking shell =="
for cp_val in "" 999999; do
  D18="$(fresh_root)"
  caller="$(env -u CLAUDECODE CLAUDE_PID="$cp_val" bash -c 'bash "$1" acquire --owner x:18 --root "$2" >/dev/null 2>&1; echo $$' _ "$SUT" "$D18")"
  rec_pid="$(awk -F'\t' '$1=="pid"{print $2}' "$(meta_file "$D18")")"
  if [ -n "$caller" ] && [ "$rec_pid" = "$caller" ]; then
    ok "CLAUDE_PID='${cp_val}' -> pid is the invoking shell ($rec_pid)"
  else
    no "CLAUDE_PID='${cp_val}' -> expected invoking shell pid '$caller', got '$rec_pid'"
  fi
done

echo "== 19. same-session nested acquire is re-entrant; outer owner kept; inner release is a no-op =="
D19="$(fresh_root)"
run_sut acquire --owner automate:run19 --session-id sess19 --root "$D19"
run_sut acquire --owner supervisor:sess19 --session-id sess19 --root "$D19"
if [ "$RUN_RC" -eq 0 ] && [ "$RUN_OUT" = "run_lock_reentrant owner=automate:run19 session_id=sess19" ]; then
  ok "nested acquire re-entered: $RUN_OUT"
else
  no "nested same-session acquire should re-enter: rc=$RUN_RC out='$RUN_OUT'"
fi
run_sut release --owner supervisor:sess19 --root "$D19"
run_sut status --root "$D19"
if grep -q '^LOCKED owner=automate:run19 ' < <(printf '%s' "$RUN_OUT"); then
  ok "inner release left the outer run's lock held: $RUN_OUT"
else
  no "inner release must not clear the outer lock: $RUN_OUT"
fi
run_sut release --owner automate:run19 --root "$D19"
run_sut status --root "$D19"
if [ "$RUN_OUT" = "UNLOCKED" ]; then
  ok "outer release cleared the lock"
else
  no "outer release should clear: $RUN_OUT"
fi

echo "== 20. under Claude Code WITHOUT \$CLAUDE_PID -> first non-shell ancestor (survives the env var being dropped) =="
# A long-lived NON-shell parent (perl, standing in for the claude binary)
# spawns an ephemeral shell that runs acquire and exits — the Bash-tool shape
# with CLAUDE_PID absent. The recorded pid must be perl, not the shell.
D20="$(fresh_root)"
SUT="$SUT" D20="$D20" env -u CLAUDE_PID CLAUDECODE=1 perl -e 'system("bash", "-c", q{bash "$SUT" acquire --owner automate:run20 --session-id sess20 --root "$D20"}); sleep 600' >/dev/null 2>&1 &
FAKE_PARENT=$!
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  [ -n "$(awk -F'\t' '$1=="pid_source"{print $2}' "$(meta_file "$D20")" 2>/dev/null)" ] && break
  sleep 0.25
done
rec_pid="$(awk -F'\t' '$1=="pid"{print $2}' "$(meta_file "$D20")" 2>/dev/null)"
rec_src="$(awk -F'\t' '$1=="pid_source"{print $2}' "$(meta_file "$D20")" 2>/dev/null)"
if [ "$rec_pid" = "$FAKE_PARENT" ] && [ "$rec_src" = "ancestor" ]; then
  ok "no CLAUDE_PID: recorded the long-lived non-shell ancestor ($rec_pid, pid_source=ancestor)"
else
  no "expected ancestor pid $FAKE_PARENT / pid_source=ancestor, got pid='$rec_pid' source='$rec_src'"
fi
set_meta_field "$D20" ts 1
S20_OUT="$(env -u CLAUDE_PID bash "$SUT" acquire --owner supervisor:other --session-id other --root "$D20" 2>&1)"
S20_RC=$?
if [ "$S20_RC" -ne 0 ] && grep -q '^run_lock_held owner=automate:run20 ' < <(printf '%s' "$S20_OUT"); then
  ok "different session refused while the ancestor lives, past the TTL: $S20_OUT"
else
  no "different-session acquire must be REFUSED (rc=$S20_RC out='$S20_OUT')"
fi
kill "$FAKE_PARENT" 2>/dev/null; wait "$FAKE_PARENT" 2>/dev/null

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
