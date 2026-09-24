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

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
