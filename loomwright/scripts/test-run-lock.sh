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
#  18. FLIPPED (af39b): no $CLAUDE_PID / CLAUDECODE / LOOMWRIGHT_HOLDER_PID and a
#      live non-shell parent (perl) above only shells -> the walk (no longer
#      gated on CLAUDECODE) records that parent, pid_source=ancestor, alive.
#  19. same-session nested acquire (automate -> supervisor) is RE-ENTRANT:
#      rc=0, prints run_lock_reentrant, owner stays the OUTER label; the inner
#      `release --owner <inner>` is a no-op and only the outer release clears it.
#  20. with CLAUDECODE set (irrelevant since af39b) WITHOUT $CLAUDE_PID -> the first
#      non-shell ancestor (a long-lived perl standing in for `claude`) is
#      recorded with pid_source=ancestor, and a different session is refused
#      past the TTL -- the fix survives CLAUDE_PID (undocumented) disappearing.
#  21. under Claude Code with BOTH tiers failing (no CLAUDE_PID, a `ps` that
#      yields nothing -- e.g. a minimal image) -> falls through to the invoking
#      shell and records pid_source=ppid, the visible "degraded to TTL" marker.
#  --- Holder under any harness + start-time fingerprint (af39b) ---
#  22. LOOMWRIGHT_HOLDER_PID live -> pid_source holder_env (with or without
#      CLAUDE_PID); dead / non-numeric -> ignored, falls through.
#  23. LOOMWRIGHT_HOLDER_PID unset + live CLAUDE_PID -> claude_pid; that variable
#      at 0, a leading zero or 1 (or dead / non-numeric) is never recorded.
#  24. a WRAPPER (env/timeout/xargs/sudo) between the shells and a non-shell
#      is skipped like a shell (PATH-stub `ps` answering from a pid table).
#  25. a SESSION HOST (tmux/screen/sshd/login/Terminal/iTerm2) stops the walk:
#      pid_source ppid + the degraded line; the host is never recorded.
#  26. the `run_lock_degraded` STDERR line on fresh / reclaim / re-entrant
#      acquire and on status of a ppid lock; stdout + rc byte-identical; no
#      other pid_source prints it.
#  27. pid_start = trimmed `env TZ=UTC0 LC_ALL=C ps -o lstart=` of the
#      holder; omitted when ps yields nothing.
#  28. pid reuse: live pid + different pid_start reads DEAD (reclaimed when
#      old, refused when young); equal pid_start reads held (test 11 is the
#      no-pid_start leg).
#  29. compatibility: the five original keys keep names + order, pid_start
#      after them; a FROZEN copy of the base meta_get agrees with the new one.
#  30. mutation controls: re-adding the CLAUDECODE gate turns 18 red;
#      dropping the pid_start compare turns 28's reuse leg red.
#  31. pid_start is TZ-independent: written under TZ=UTC, compared under
#      TZ=Asia/Kolkata -> a live holder past the TTL is still held (refused);
#      mutation control: dropping the TZ pin reclaims it.
#  32. `liveness` prints the same verdict acquire's reclaim reads: unknown
#      (no lock), alive, dead (dead pid), dead (reused pid); stdout of
#      status/acquire unchanged.
#  33. `liveness --pid <p>` binds the verdict to the holder a caller saw:
#      the same live pid -> alive; a different recorded pid (the lock changed
#      hands, even to a LIVE holder) -> dead; no lock -> unknown; a
#      non-numeric --pid -> usage error (exit 1).
#  34. a `$PPID` of 1 (the SUT orphaned to init by a double fork before bash
#      read its parent) is never recorded: pid empty, no pid_start, pid_source
#      ppid + the degraded line, liveness unknown, status `pid=`; reclaimable
#      once aged, refused while young. Mutation control: the pre-fix
#      `echo "$PPID ppid"` records 1, and where `kill -0 1` succeeds (root)
#      the aged lock is never reclaimed. SKIPs where a subreaper adopts orphans.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/run-lock.sh"
# An ambient holder pin (a close-out's own, an operator's) must not decide any leg.
unset LOOMWRIGHT_HOLDER_PID

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

fresh_root() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/.supervisor"
  printf '%s' "$d"
}

# STDOUT only in RUN_OUT (the parsed surface); STDERR (the run_lock_degraded
# line) in RUN_ERR — so a ppid-recording environment (a tmux pane) cannot
# change any stdout assertion.
RUN_ERR_FILE="$(mktemp)"
run_sut() {
  RUN_OUT="$(bash "$SUT" "$@" 2>"$RUN_ERR_FILE")"
  RUN_RC=$?
  RUN_ERR="$(cat "$RUN_ERR_FILE")"
}

lock_dir() { printf '%s/.supervisor/run.lock' "$1"; }
meta_file() { printf '%s/.supervisor/run.lock/meta' "$1"; }

set_meta_field() {
  # set_meta_field <root> <key> <value>
  local m; m="$(meta_file "$1")"
  awk -F'\t' -v k="$2" -v v="$3" 'BEGIN{OFS="\t"} $1==k{$2=v; found=1} {print} END{if(!found) print k, v}' "$m" > "${m}.tmp"
  mv -f "${m}.tmp" "$m"
}
del_meta_field() {
  # del_meta_field <root> <key>
  local m; m="$(meta_file "$1")"
  awk -F'\t' -v k="$2" '$1!=k' "$m" > "${m}.tmp"
  mv -f "${m}.tmp" "$m"
}
meta_val() { awk -F'\t' -v k="$2" '$1==k{print $2; exit}' "$(meta_file "$1")" 2>/dev/null; }
trim_ws() { sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }

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

echo "== 11. live pid (self) + old ts + NO pid_start -> REFUSES (kill -0-only rule) =="
D11="$(fresh_root)"
run_sut acquire --owner automate:live --root "$D11"
set_meta_field "$D11" pid "$$"
# The recorded pid_start belongs to whatever holder acquire resolved, not to
# $$ — drop it: this is AC 8's "no pid_start => kill -0 only" leg.
del_meta_field "$D11" pid_start
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
# The automate-loop skill is a split index (parallel-automate/22): check its documented-order assembly
# (index segments + split files) — a failed assembly leaves no file, which the helper reports as a FAIL.
AL_D="$(mktemp -d)"
bash "$HERE/fixtures/automate-loop-split/assemble.sh" "$PLUGIN_ROOT/skills/automate-loop/SKILL.md" "$AL_D/SKILL.md"
check_acquire_has_session_id "automate-loop SKILL PICK (reference shape)" "$AL_D/SKILL.md"
rm -rf "$AL_D"

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

echo "== 18. FLIPPED: no Claude env, live non-shell parent above only shells -> ancestor (ungated walk) =="
# ancestor_leg <sut> <root> — a long-lived perl (any non-shell harness) runs an
# ephemeral shell that runs acquire and exits, with CLAUDE_PID, CLAUDECODE and
# LOOMWRIGHT_HOLDER_PID all unset. Prints `<recorded pid> <pid_source> <perl
# pid> <alive 0|1>`; kills and reaps the perl before returning.
ancestor_leg() {
  local sut="$1" root="$2" fp i rp rs alive=0
  SUT_L="$sut" ROOT_L="$root" env -u CLAUDE_PID -u CLAUDECODE -u LOOMWRIGHT_HOLDER_PID \
    perl -e 'system("bash", "-c", q{bash "$SUT_L" acquire --owner x:18 --root "$ROOT_L"}); sleep 600' >/dev/null 2>&1 &
  fp=$!
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    [ -n "$(meta_val "$root" pid_source)" ] && break
    sleep 0.25
  done
  rp="$(meta_val "$root" pid)"; rs="$(meta_val "$root" pid_source)"
  [ -n "$rp" ] && kill -0 "$rp" 2>/dev/null && alive=1
  kill "$fp" 2>/dev/null; wait "$fp" 2>/dev/null
  echo "$rp $rs $fp $alive"
}
D18="$(fresh_root)"
read -r rec_pid rec_src fake_parent rec_alive <<EOF18
$(ancestor_leg "$SUT" "$D18")
EOF18
if [ "$rec_pid" = "$fake_parent" ] && [ "$rec_src" = "ancestor" ] && [ "$rec_alive" = 1 ]; then
  ok "no CLAUDE_PID/CLAUDECODE: recorded the live non-shell parent ($rec_pid, pid_source=ancestor, kill -0 ok)"
else
  no "expected ancestor pid $fake_parent / ancestor / alive, got pid='$rec_pid' source='$rec_src' alive='$rec_alive'"
fi

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

echo "== 21. under Claude Code, ancestor walk fails -> pid_source=ppid (degraded, visible) =="
STUB21="$(mktemp -d)"
printf '#!/bin/sh\nexit 1\n' > "$STUB21/ps"; chmod +x "$STUB21/ps"
D21="$(fresh_root)"
caller="$(env -u CLAUDE_PID CLAUDECODE=1 PATH="$STUB21:$PATH" bash -c 'bash "$1" acquire --owner x:21 --root "$2" >/dev/null 2>&1; echo $$' _ "$SUT" "$D21")"
rec_pid="$(awk -F'\t' '$1=="pid"{print $2}' "$(meta_file "$D21")")"
rec_src="$(awk -F'\t' '$1=="pid_source"{print $2}' "$(meta_file "$D21")")"
if [ -n "$caller" ] && [ "$rec_pid" = "$caller" ] && [ "$rec_src" = "ppid" ]; then
  ok "ancestor walk failed under CLAUDECODE -> invoking shell ($rec_pid), pid_source=ppid"
else
  no "expected pid=$caller pid_source=ppid, got pid='$rec_pid' source='$rec_src'"
fi
rm -rf "$STUB21"

# ---- af39b helpers ----------------------------------------------------------
DEGRADED_LINE="run_lock_degraded: pid_source=ppid ttl_only=1800s"
# run_env <env-arg>... -- <sut args>... — run the SUT under `env <env-args>`
# (at least one env arg), STDOUT in RUN_OUT, STDERR in RUN_ERR.
run_env() {
  local -a e=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do e+=("$1"); shift; done
  shift
  RUN_OUT="$(env "${e[@]}" bash "$SUT" "$@" 2>"$RUN_ERR_FILE")"
  RUN_RC=$?
  RUN_ERR="$(cat "$RUN_ERR_FILE")"
}
# A PATH-stub `ps` that answers `-o comm= | ppid= | lstart= -p <pid>` from a
# TSV table ($PS_TABLE: pid<TAB>comm<TAB>ppid<TAB>lstart) — a deterministic
# fake process tree on macOS and Linux (test 21's PATH-stub idiom).
PSSTUB="$(mktemp -d)"
cat > "$PSSTUB/ps" <<'PSEOF'
#!/bin/sh
f=""; p=""
while [ $# -gt 0 ]; do
  case "$1" in -o) f="$2"; shift 2 ;; -p) p="$2"; shift 2 ;; *) shift ;; esac
done
awk -F'\t' -v p="$p" -v f="$f" '$1==p { if (f=="comm=") print $2; else if (f=="ppid=") print $3; else if (f=="lstart=") print $4; found=1; exit } END { exit (found ? 0 : 1) }' "$PS_TABLE"
PSEOF
chmod +x "$PSSTUB/ps"
# tree_acquire <root> <table> <row>... — each <row> is `comm<TAB>ppid<TAB>lstart`
# for fake pids 90001, 90002, … in order; the invoking shell's row (its parent
# = 90001) is added at run time. Acquires with no holder env through the stub
# `ps`; sets TREE_CALLER (the invoking shell's pid), RUN_ERR (stderr).
tree_acquire() {
  local root="$1" tbl="$2" i=90001 row; shift 2
  : > "$tbl"
  for row in "$@"; do printf '%s\t%s\n' "$i" "$row" >> "$tbl"; i=$((i+1)); done
  TREE_CALLER="$(env -u CLAUDE_PID -u LOOMWRIGHT_HOLDER_PID PS_TABLE="$tbl" PATH="$PSSTUB:$PATH" \
    bash -c 'printf "%s\tbash\t90001\tShellStart\n" "$$" >> "$3"; bash "$1" acquire --owner x:tree --root "$2" >/dev/null 2>"$4"; echo $$' \
    _ "$SUT" "$root" "$tbl" "$RUN_ERR_FILE")"
  RUN_ERR="$(cat "$RUN_ERR_FILE")"
}
TAB="$(printf '\t')"

echo "== 22. LOOMWRIGHT_HOLDER_PID live -> holder_env; dead / non-numeric -> ignored =="
sleep 600 & HOLD22=$!
sleep 600 & CL22=$!
D22="$(fresh_root)"
run_env -u CLAUDE_PID LOOMWRIGHT_HOLDER_PID="$HOLD22" -- acquire --owner x:22 --root "$D22"
if [ "$RUN_RC" -eq 0 ] && [ "$(meta_val "$D22" pid)" = "$HOLD22" ] && [ "$(meta_val "$D22" pid_source)" = holder_env ]; then
  ok "live LOOMWRIGHT_HOLDER_PID, no CLAUDE_PID -> pid $HOLD22, pid_source holder_env"
else
  no "expected pid $HOLD22 holder_env, got '$(meta_val "$D22" pid)' '$(meta_val "$D22" pid_source)' rc=$RUN_RC"
fi
D22b="$(fresh_root)"
run_env LOOMWRIGHT_HOLDER_PID="$HOLD22" CLAUDE_PID="$CL22" -- acquire --owner x:22 --root "$D22b"
if [ "$(meta_val "$D22b" pid)" = "$HOLD22" ] && [ "$(meta_val "$D22b" pid_source)" = holder_env ]; then
  ok "live LOOMWRIGHT_HOLDER_PID beats a live CLAUDE_PID -> holder_env"
else
  no "LOOMWRIGHT_HOLDER_PID must win over CLAUDE_PID: got '$(meta_val "$D22b" pid)' '$(meta_val "$D22b" pid_source)'"
fi
# 0 always "lives" (kill -0 0 = own process group) and 1 is init: never a holder.
for bad in 999999 abc 12x 0 007 1; do
  D22c="$(fresh_root)"
  run_env LOOMWRIGHT_HOLDER_PID="$bad" CLAUDE_PID="$CL22" -- acquire --owner x:22 --root "$D22c"
  if [ "$(meta_val "$D22c" pid)" = "$CL22" ] && [ "$(meta_val "$D22c" pid_source)" = claude_pid ]; then
    ok "LOOMWRIGHT_HOLDER_PID='$bad' ignored -> falls through to CLAUDE_PID (claude_pid)"
  else
    no "LOOMWRIGHT_HOLDER_PID='$bad' should fall through to claude_pid, got '$(meta_val "$D22c" pid)' '$(meta_val "$D22c" pid_source)'"
  fi
done
D22d="$(fresh_root)"
run_env -u CLAUDE_PID LOOMWRIGHT_HOLDER_PID=999999 -- acquire --owner x:22 --root "$D22d"
if [ "$(meta_val "$D22d" pid)" != 999999 ] && [ "$(meta_val "$D22d" pid_source)" != holder_env ]; then
  ok "dead LOOMWRIGHT_HOLDER_PID, no CLAUDE_PID -> falls through to the walk / ppid ($(meta_val "$D22d" pid_source))"
else
  no "a dead LOOMWRIGHT_HOLDER_PID must never be recorded: got '$(meta_val "$D22d" pid)' '$(meta_val "$D22d" pid_source)'"
fi

echo "== 23. LOOMWRIGHT_HOLDER_PID unset + live CLAUDE_PID -> claude_pid =="
D23="$(fresh_root)"
run_env -u LOOMWRIGHT_HOLDER_PID CLAUDE_PID="$CL22" -- acquire --owner x:23 --root "$D23"
if [ "$(meta_val "$D23" pid)" = "$CL22" ] && [ "$(meta_val "$D23" pid_source)" = claude_pid ]; then
  ok "no holder pin, live CLAUDE_PID -> pid $CL22, pid_source claude_pid"
else
  no "expected claude_pid $CL22, got '$(meta_val "$D23" pid)' '$(meta_val "$D23" pid_source)'"
fi
# 0 always "lives" (kill -0 0) and 1 is init: the same rule as the holder pin.
for bad in 0 007 1 999999 abc; do
  D23b="$(fresh_root)"
  run_env -u LOOMWRIGHT_HOLDER_PID CLAUDE_PID="$bad" -- acquire --owner x:23 --root "$D23b"
  if [ "$RUN_RC" -eq 0 ] && [ "$(meta_val "$D23b" pid)" != "$bad" ] && [ "$(meta_val "$D23b" pid_source)" != claude_pid ]; then
    ok "harness pid var='$bad' ignored -> falls through to the walk / ppid ($(meta_val "$D23b" pid_source))"
  else
    no "harness pid var='$bad' must never be recorded: got '$(meta_val "$D23b" pid)' '$(meta_val "$D23b" pid_source)' rc=$RUN_RC"
  fi
done
kill "$HOLD22" "$CL22" 2>/dev/null; wait "$HOLD22" "$CL22" 2>/dev/null

echo "== 24. a wrapper between the shells and a non-shell ancestor is skipped =="
TBL="$(mktemp)"
for w in env /usr/bin/env timeout xargs sudo; do
  D24="$(fresh_root)"
  tree_acquire "$D24" "$TBL" "${w}${TAB}90002${TAB}WrapStart" "perl${TAB}1${TAB}Mon Jan  5 10:00:00 2026"
  if [ "$(meta_val "$D24" pid)" = 90002 ] && [ "$(meta_val "$D24" pid_source)" = ancestor ] && [ -z "$RUN_ERR" ]; then
    ok "wrapper '$w' skipped like a shell -> the non-shell beyond it (90002) recorded as ancestor"
  else
    no "wrapper '$w': expected 90002 ancestor, got '$(meta_val "$D24" pid)' '$(meta_val "$D24" pid_source)' err='$RUN_ERR'"
  fi
done

echo "== 25. a session host stops the walk -> ppid + degraded line; the host is never recorded =="
for h in tmux screen sshd -login /usr/bin/login /System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal /Applications/iTerm.app/Contents/MacOS/iTerm2; do
  D25="$(fresh_root)"
  tree_acquire "$D25" "$TBL" "${h}${TAB}90002${TAB}HostStart" "perl${TAB}1${TAB}PerlStart"
  rp="$(meta_val "$D25" pid)"
  if [ -n "$TREE_CALLER" ] && [ "$rp" = "$TREE_CALLER" ] && [ "$(meta_val "$D25" pid_source)" = ppid ] && [ "$RUN_ERR" = "$DEGRADED_LINE" ]; then
    ok "session host '${h##*/}' stops the walk -> invoking shell ($rp), pid_source ppid, degraded line on stderr"
  else
    no "session host '$h': expected pid $TREE_CALLER ppid + degraded line, got '$rp' '$(meta_val "$D25" pid_source)' err='$RUN_ERR'"
  fi
done
D25b="$(fresh_root)"
tree_acquire "$D25b" "$TBL" "xargs${TAB}90002${TAB}X" "tmux${TAB}90003${TAB}T" "perl${TAB}1${TAB}P"
if [ "$(meta_val "$D25b" pid_source)" = ppid ] && [ "$(meta_val "$D25b" pid)" = "$TREE_CALLER" ]; then
  ok "a host above shells AND a wrapper still stops the walk -> ppid (neither 90002 nor 90003 recorded)"
else
  no "wrapper-then-host: expected ppid $TREE_CALLER, got '$(meta_val "$D25b" pid)' '$(meta_val "$D25b" pid_source)'"
fi

echo "== 26. run_lock_degraded on stderr only, for pid_source ppid only =="
STUB26="$(mktemp -d)"
printf '#!/bin/sh\nexit 1\n' > "$STUB26/ps"; chmod +x "$STUB26/ps"
D26="$(fresh_root)"
run_env -u CLAUDE_PID -u LOOMWRIGHT_HOLDER_PID PATH="$STUB26:$PATH" -- acquire --owner x:26 --session-id s26 --root "$D26"
if [ "$RUN_RC" -eq 0 ] && [ -z "$RUN_OUT" ] && [ "$RUN_ERR" = "$DEGRADED_LINE" ] && [ "$(meta_val "$D26" pid_source)" = ppid ]; then
  ok "fresh ppid acquire: rc 0, stdout empty, stderr exactly the degraded line"
else
  no "fresh ppid acquire: rc=$RUN_RC out='$RUN_OUT' err='$RUN_ERR'"
fi
run_env -u CLAUDE_PID -u LOOMWRIGHT_HOLDER_PID PATH="$STUB26:$PATH" -- acquire --owner x:26-inner --session-id s26 --root "$D26"
if [ "$RUN_RC" -eq 0 ] && [ "$RUN_OUT" = "run_lock_reentrant owner=x:26 session_id=s26" ] && [ "$RUN_ERR" = "$DEGRADED_LINE" ]; then
  ok "re-entrant ppid refresh: stdout is today's run_lock_reentrant line, stderr the degraded line"
else
  no "re-entrant ppid refresh: rc=$RUN_RC out='$RUN_OUT' err='$RUN_ERR'"
fi
p26="$(meta_val "$D26" pid)"
run_env -u CLAUDE_PID -- status --root "$D26"
case "$RUN_OUT" in "LOCKED owner=x:26 pid=$p26 age="[0-9]*) st_shape=1 ;; *) st_shape=0 ;; esac
if [ "$RUN_RC" -eq 0 ] && [ "$st_shape" = 1 ] && [ "$(printf '%s\n' "$RUN_OUT" | wc -l | tr -d ' ')" = 1 ] \
   && [ -z "$(printf '%s' "$RUN_OUT" | tr -d 'A-Za-z0-9=:_ -')" ] && [ "$RUN_ERR" = "$DEGRADED_LINE" ]; then
  ok "status of a ppid lock: stdout one LOCKED line byte-for-byte, the degraded line on stderr"
else
  no "status of a ppid lock: rc=$RUN_RC out='$RUN_OUT' err='$RUN_ERR'"
fi
set_meta_field "$D26" pid 999999; set_meta_field "$D26" ts 1
run_env -u CLAUDE_PID -u LOOMWRIGHT_HOLDER_PID PATH="$STUB26:$PATH" -- acquire --owner x:26r --root "$D26"
if [ "$RUN_RC" -eq 0 ] && [ -z "$RUN_OUT" ] && [ "$RUN_ERR" = "$DEGRADED_LINE" ] && [ "$(meta_val "$D26" owner)" = x:26r ]; then
  ok "reclaim with a ppid holder: rc 0, stdout empty, stderr the degraded line"
else
  no "reclaim ppid: rc=$RUN_RC out='$RUN_OUT' err='$RUN_ERR'"
fi
sleep 600 & L26=$!
D26n="$(fresh_root)"
run_env -u LOOMWRIGHT_HOLDER_PID CLAUDE_PID="$L26" -- acquire --owner x:26n --root "$D26n"
e1="$RUN_ERR"
run_env -u LOOMWRIGHT_HOLDER_PID CLAUDE_PID="$L26" -- status --root "$D26n"
e2="$RUN_ERR"
D26h="$(fresh_root)"
run_env LOOMWRIGHT_HOLDER_PID="$L26" -- acquire --owner x:26h --root "$D26h"
e3="$RUN_ERR"
D26a="$(fresh_root)"
tree_acquire "$D26a" "$TBL" "perl${TAB}1${TAB}P"
e4="$RUN_ERR"
if [ -z "$e1$e2$e3$e4" ] && [ "$(meta_val "$D26a" pid_source)" = ancestor ]; then
  ok "claude_pid / holder_env / ancestor acquires and status print no degraded line"
else
  no "a non-ppid source printed stderr: claude_pid='$e1' status='$e2' holder_env='$e3' ancestor='$e4'"
fi
kill "$L26" 2>/dev/null; wait "$L26" 2>/dev/null
rm -rf "$STUB26"

echo "== 27. pid_start = the holder's trimmed lstart; omitted when ps yields nothing =="
sleep 600 & L27=$!
D27="$(fresh_root)"
run_env -u LOOMWRIGHT_HOLDER_PID CLAUDE_PID="$L27" -- acquire --owner x:27 --root "$D27"
want27="$(env TZ=UTC0 LC_ALL=C ps -o lstart= -p "$L27" | trim_ws)"
if [ -n "$want27" ] && [ "$(meta_val "$D27" pid_start)" = "$want27" ]; then
  ok "pid_start recorded = the holder's trimmed lstart ('$want27')"
else
  no "pid_start: expected '$want27', got '$(meta_val "$D27" pid_start)'"
fi
kill "$L27" 2>/dev/null; wait "$L27" 2>/dev/null
D27b="$(fresh_root)"
tree_acquire "$D27b" "$TBL" "perl${TAB}1${TAB}   Tue Oct 14 09:15:31 2026   "
if [ "$(meta_val "$D27b" pid_start)" = "Tue Oct 14 09:15:31 2026" ]; then
  ok "surrounding whitespace in lstart is trimmed"
else
  no "pid_start not trimmed: '$(meta_val "$D27b" pid_start)'"
fi
D27c="$(fresh_root)"
STUB27="$(mktemp -d)"; printf '#!/bin/sh\nexit 1\n' > "$STUB27/ps"; chmod +x "$STUB27/ps"
run_env -u CLAUDE_PID -u LOOMWRIGHT_HOLDER_PID PATH="$STUB27:$PATH" -- acquire --owner x:27c --root "$D27c"
if [ -f "$(meta_file "$D27c")" ] && ! grep -q '^pid_start' "$(meta_file "$D27c")"; then
  ok "ps yields no lstart -> the pid_start key is omitted"
else
  no "pid_start should be absent when ps yields nothing: $(tr '\n' '|' < "$(meta_file "$D27c")")"
fi
rm -rf "$STUB27"

echo "== 28. pid reuse: live pid + different pid_start reads DEAD; equal reads held =="
# reuse_leg <sut> <root> <ts> — a live pid this test owns with a deliberately
# different pid_start; prints the second acquire's rc.
reuse_leg() {
  local sut="$1" root="$2" ts="$3" lp rc
  sleep 600 & lp=$!
  bash "$sut" acquire --owner x:28-held --root "$root" >/dev/null 2>&1
  set_meta_field "$root" pid "$lp"
  set_meta_field "$root" pid_start "Thu Jan  1 00:00:00 1970"
  set_meta_field "$root" ts "$ts"
  bash "$sut" acquire --owner x:28-new --root "$root" >/dev/null 2>&1; rc=$?
  kill "$lp" 2>/dev/null; wait "$lp" 2>/dev/null
  echo "$rc"
}
D28="$(fresh_root)"
r28="$(reuse_leg "$SUT" "$D28" 1)"
if [ "$r28" = 0 ] && [ "$(meta_val "$D28" owner)" = x:28-new ]; then
  ok "live pid with a mismatched pid_start, age >= TTL -> reads dead, reclaimed"
else
  no "reused pid should be reclaimed: rc=$r28 owner='$(meta_val "$D28" owner)'"
fi
D28y="$(fresh_root)"
r28y="$(reuse_leg "$SUT" "$D28y" "$(( $(date +%s) - 10 ))")"
if [ "$r28y" != 0 ] && [ "$(meta_val "$D28y" owner)" = x:28-held ]; then
  ok "mismatched pid_start but a young lock -> still refused (TTL unchanged)"
else
  no "young reused-pid lock must refuse: rc=$r28y owner='$(meta_val "$D28y" owner)'"
fi
D28e="$(fresh_root)"
run_sut acquire --owner x:28-eq --root "$D28e"
set_meta_field "$D28e" pid "$$"
set_meta_field "$D28e" pid_start "$(env TZ=UTC0 LC_ALL=C ps -o lstart= -p "$$" | trim_ws)"
set_meta_field "$D28e" ts 1
run_sut acquire --owner x:28-other --root "$D28e"
if [ "$RUN_RC" -ne 0 ] && grep -q '^run_lock_held owner=x:28-eq ' < <(printf '%s' "$RUN_OUT"); then
  ok "live pid with an EQUAL pid_start, age >= TTL -> held (refused)"
else
  no "equal pid_start must read held: rc=$RUN_RC out='$RUN_OUT'"
fi

echo "== 29. compatibility: key names + order; frozen base meta_get agrees with the new one =="
sleep 600 & L29=$!
D29="$(fresh_root)"
run_env -u LOOMWRIGHT_HOLDER_PID CLAUDE_PID="$L29" -- acquire --owner x:29 --session-id s29 --root "$D29"
kill "$L29" 2>/dev/null; wait "$L29" 2>/dev/null
keys29="$(awk -F'\t' '{printf "%s ", $1}' "$(meta_file "$D29")")"
if [ "$keys29" = "pid owner session_id ts pid_source pid_start " ]; then
  ok "meta keys in order: $keys29"
else
  no "meta key order changed: '$keys29'"
fi
# FROZEN copy of the base (adce64f) run-lock.sh meta_get lookup — never edit it
# to follow the script: it is the reader an older checkout still runs.
base_meta_get() {
  local key="$1"
  awk -F'\t' -v k="$key" '$1==k{print $2; exit}' "$LOCK_META" 2>/dev/null
}
NEW_MG="$(awk '/^meta_get\(\) \{/{s=1} s{print} s&&/^}/{exit}' "$SUT")"
LOCK_META="$(meta_file "$D29")"
if [ -n "$NEW_MG" ] && eval "$NEW_MG" 2>/dev/null; then
  agree=1
  for k in pid owner session_id ts pid_source; do
    bv="$(base_meta_get "$k")"; nv="$(meta_get "$k")"
    { [ -n "$bv" ] && [ "$bv" = "$nv" ]; } || { agree=0; no "key '$k': base meta_get '$bv' vs new meta_get '$nv'"; }
  done
  [ "$agree" = 1 ] && ok "the frozen base meta_get returns exactly the new meta_get's value for all five original keys"
else
  no "could not extract the new meta_get from $SUT"
fi
unset LOCK_META

echo "== 30. MUTATION CONTROLS: the CLAUDECODE gate re-added; the pid_start compare dropped =="
MUT30DIR="$(mktemp -d)"
MUT30A="$MUT30DIR/gate.sh"
sed -e 's/^  local p="\$PPID" c n=0$/  if [ -n "${CLAUDECODE:-}" ]; then local p="$PPID" c n=0/' \
    -e 's/^  done   # end of the ancestor walk$/  done; fi/' "$SUT" > "$MUT30A"
if [ -s "$MUT30A" ] && ! diff -q "$MUT30A" "$SUT" >/dev/null 2>&1 && bash -n "$MUT30A" 2>/dev/null \
   && grep -qF 'if [ -n "${CLAUDECODE:-}" ]; then local p=' "$MUT30A" && grep -qF '  done; fi' "$MUT30A"; then
  D30="$(fresh_root)"
  read -r m_pid m_src m_fp m_alive <<EOF30
$(ancestor_leg "$MUT30A" "$D30")
EOF30
  if [ "$m_src" != ancestor ]; then
    ok "mutation control: with the CLAUDECODE gate re-added, test 18's scenario records '$m_src' -- test 18 is load-bearing"
  else
    no "mutation control REFUTED: the gated mutant still recorded ancestor -- test 18 cannot see the gate"
  fi
else
  no "mutation control: could not build the CLAUDECODE-gate mutant -- control inconclusive"
fi
MUT30B="$MUT30DIR/nostart.sh"
sed -e 's/^    return 1   # pid_start mismatch: the pid was reused$/    :   # mutant: pid_start compare dropped/' "$SUT" > "$MUT30B"
if [ -s "$MUT30B" ] && ! diff -q "$MUT30B" "$SUT" >/dev/null 2>&1 && bash -n "$MUT30B" 2>/dev/null \
   && grep -qF 'mutant: pid_start compare dropped' "$MUT30B"; then
  D30b="$(fresh_root)"
  rm30="$(reuse_leg "$MUT30B" "$D30b" 1)"
  if [ "$rm30" != 0 ]; then
    ok "mutation control: without the pid_start compare a reused pid reads alive and is refused -- test 28 is load-bearing"
  else
    no "mutation control REFUTED: the no-compare mutant still reclaimed the reused pid"
  fi
else
  no "mutation control: could not build the no-pid_start-compare mutant -- control inconclusive"
fi
rm -rf "$MUT30DIR"

echo "== 31. pid_start is TZ-independent: written under one TZ, compared under another -> held =="
# tz_leg <sut> — acquire under TZ=UTC with a live holder pinned, age the lock past
# the TTL, then a different owner acquires under TZ=Asia/Kolkata; prints that rc.
tz_leg() {
  local sut="$1" root lp rc
  root="$(fresh_root)"
  sleep 600 & lp=$!
  env TZ=UTC LOOMWRIGHT_HOLDER_PID="$lp" bash "$sut" acquire --owner x:31-held --root "$root" >/dev/null 2>&1
  set_meta_field "$root" ts 1
  env -u LOOMWRIGHT_HOLDER_PID TZ=Asia/Kolkata bash "$sut" acquire --owner x:31-new --root "$root" >/dev/null 2>&1; rc=$?
  kill "$lp" 2>/dev/null; wait "$lp" 2>/dev/null
  echo "$rc $(meta_val "$root" owner) $(meta_val "$root" pid_source)"
}
read -r r31 o31 s31 <<EOF31
$(tz_leg "$SUT")
EOF31
if [ "$r31" != 0 ] && [ "$o31" = x:31-held ] && [ "$s31" = holder_env ]; then
  ok "live holder written under TZ=UTC is still held when compared under TZ=Asia/Kolkata"
else
  no "cross-TZ compare must read held: rc=$r31 owner='$o31' pid_source='$s31'"
fi
MUT31DIR="$(mktemp -d)"; MUT31="$MUT31DIR/notz.sh"
sed -e 's/^  env TZ=UTC0 LC_ALL=C ps -o lstart= -p "\$1"/  env LC_ALL=C ps -o lstart= -p "$1"/' "$SUT" > "$MUT31"
if [ -s "$MUT31" ] && ! diff -q "$MUT31" "$SUT" >/dev/null 2>&1 && bash -n "$MUT31" 2>/dev/null \
   && [ "$(env TZ=UTC LC_ALL=C ps -o lstart= -p "$$")" != "$(env TZ=Asia/Kolkata LC_ALL=C ps -o lstart= -p "$$")" ]; then
  read -r rm31 _ _ <<EOF31M
$(tz_leg "$MUT31")
EOF31M
  if [ "$rm31" = 0 ]; then
    ok "mutation control: without the TZ pin the same live holder is reclaimed -- test 31 is load-bearing"
  else
    no "mutation control REFUTED: the TZ-unpinned mutant still refused (rc=$rm31)"
  fi
else
  no "mutation control: could not build the TZ-unpinned mutant (or ps ignores TZ here) -- control inconclusive"
fi
rm -rf "$MUT31DIR"

echo "== 32. liveness prints the verdict acquire's reclaim reads =="
D32="$(fresh_root)"
v32u="$(bash "$SUT" liveness --root "$D32" 2>/dev/null)"; rc32u=$?
sleep 600 & L32=$!
env LOOMWRIGHT_HOLDER_PID="$L32" bash "$SUT" acquire --owner x:32 --root "$D32" >/dev/null 2>&1
v32a="$(bash "$SUT" liveness --root "$D32" 2>/dev/null)"
set_meta_field "$D32" pid_start "Thu Jan  1 00:00:00 1970"
v32r="$(bash "$SUT" liveness --root "$D32" 2>/dev/null)"
kill "$L32" 2>/dev/null; wait "$L32" 2>/dev/null
set_meta_field "$D32" pid 999999
v32d="$(bash "$SUT" liveness --root "$D32" 2>/dev/null)"; rc32d=$?
if [ "$v32u" = unknown ] && [ "$rc32u" = 0 ] && [ "$v32a" = alive ] && [ "$v32r" = dead ] \
   && [ "$v32d" = dead ] && [ "$rc32d" = 0 ]; then
  ok "liveness: unknown (no lock) / alive / dead (reused pid) / dead (dead pid), exit 0"
else
  no "liveness verdicts: none='$v32u'($rc32u) live='$v32a' reused='$v32r' dead='$v32d'($rc32d)"
fi
st32="$(bash "$SUT" status --root "$D32" 2>/dev/null)"
case "$st32" in "LOCKED owner=x:32 pid=999999 age="*) ok "status stdout shape unchanged: '$st32'" ;;
  *) no "status stdout changed: '$st32'" ;; esac

echo "== 33. liveness --pid binds the verdict to the refused holder =="
D33="$(fresh_root)"
v33u="$(bash "$SUT" liveness --pid 4242 --root "$D33" 2>/dev/null)"
sleep 600 & L33=$!
env LOOMWRIGHT_HOLDER_PID="$L33" bash "$SUT" acquire --owner x:33 --root "$D33" >/dev/null 2>&1
v33s="$(bash "$SUT" liveness --pid "$L33" --root "$D33" 2>/dev/null)"
v33o="$(bash "$SUT" liveness --pid "$$" --root "$D33" 2>/dev/null)"
v33n="$(bash "$SUT" liveness --root "$D33" 2>/dev/null)"
bash "$SUT" liveness --pid x1 --root "$D33" >/dev/null 2>&1; rc33b=$?
kill "$L33" 2>/dev/null; wait "$L33" 2>/dev/null
if [ "$v33u" = unknown ] && [ "$v33s" = alive ] && [ "$v33o" = dead ] && [ "$v33n" = alive ] && [ "$rc33b" = 1 ]; then
  ok "liveness --pid: unknown (no lock) / alive (same live pid) / dead (lock names another LIVE pid) / unbound still alive / bad --pid exit 1"
else
  no "liveness --pid: none='$v33u' same='$v33s' other='$v33o' unbound='$v33n' bad_rc=$rc33b"
fi

echo "== 34. a \$PPID of 1 (orphaned to init) is never recorded; the lock stays TTL-reclaimable =="
# orphan_acquire <sut> <root> <ppid-file> — the outer shell exits at once, so
# the backgrounded subshell is reparented to init; it then (after a pause)
# records its own $PPID and EXECs the SUT, which therefore starts with that
# same parent. A `ps` stub that yields nothing keeps the walk out of it, as on
# a minimal image. Waits up to ~10s for the meta.
STUB34="$(mktemp -d)"
printf '#!/bin/sh\nexit 1\n' > "$STUB34/ps"; chmod +x "$STUB34/ps"
orphan_acquire() {
  local sut="$1" root="$2" pf="$3" i=0
  env -u CLAUDE_PID -u LOOMWRIGHT_HOLDER_PID PATH="$STUB34:$PATH" \
    bash -c '( sleep 1; exec bash -c '"'"'echo "$PPID" > "$3"; exec bash "$1" acquire --owner x:34 --root "$2"'"'"' _ "$1" "$2" "$3" ) >/dev/null 2>"$4" & exit 0' \
    _ "$sut" "$root" "$pf" "$root.err" >/dev/null 2>&1
  while [ "$i" -lt 100 ] && ! grep -q '^pid_source' "$(meta_file "$root")" 2>/dev/null; do sleep 0.1; i=$((i+1)); done
}
D34="$(fresh_root)"
orphan_acquire "$SUT" "$D34" "$D34.ppid"
o34="$(cat "$D34.ppid" 2>/dev/null)"
if [ "$o34" != 1 ]; then
  # A subreaper (systemd --user, a container's init shim) adopted the orphan
  # instead of pid 1 — this host cannot produce the scenario.
  ok "SKIP: orphan reparented to pid '${o34:-?}', not 1 (a subreaper) -- leg not reproducible here"
else
  st34="$(bash "$SUT" status --root "$D34" 2>"$RUN_ERR_FILE")"; st34e="$(cat "$RUN_ERR_FILE")"
  lv34="$(bash "$SUT" liveness --root "$D34" 2>/dev/null)"
  if grep -q $'^pid\t$' "$(meta_file "$D34")" && [ -z "$(meta_val "$D34" pid_start)" ] \
     && [ "$(meta_val "$D34" pid_source)" = ppid ] && [ "$(cat "$D34.err")" = "$DEGRADED_LINE" ] \
     && [ "$lv34" = unknown ] && [ "$st34e" = "$DEGRADED_LINE" ]; then
    case "$st34" in "LOCKED owner=x:34 pid= age="*) ok "\$PPID=1 -> empty pid, no pid_start, ppid + degraded line, liveness unknown, status '$st34'" ;;
      *) no "status stdout for an empty pid: '$st34'" ;; esac
  else
    no "\$PPID=1: meta='$(tr '\t\n' '=;' < "$(meta_file "$D34")")' err='$(cat "$D34.err")' liveness='$lv34' status_err='$st34e'"
  fi
  run_sut acquire --owner x:34b --root "$D34"
  if [ "$RUN_RC" -eq 1 ]; then ok "young empty-pid lock refused (dead holder alone never reclaims)"; else no "young empty-pid lock must refuse, rc=$RUN_RC"; fi
  set_meta_field "$D34" ts "$(( $(date +%s) - 4000 ))"
  run_sut acquire --owner x:34b --root "$D34"
  if [ "$RUN_RC" -eq 0 ] && [ "$(meta_val "$D34" owner)" = x:34b ]; then
    ok "aged empty-pid lock reclaimed by a different owner"
  else
    no "aged empty-pid lock must reclaim: rc=$RUN_RC owner='$(meta_val "$D34" owner)'"
  fi
  # Mutation control: the pre-fix fallback records init. Whether that lock is
  # then unreclaimable depends on `kill -0 1`: it succeeds as root (a CI
  # container) and fails EPERM for an ordinary user — so the never-reclaimed
  # half is asserted only where `kill -0 1` succeeds.
  MUT34="$(mktemp -d)/run-lock.sh"
  sed 's/^  if is_holder_pid "\$PPID"; then echo "\$PPID ppid"; else echo "- ppid"; fi$/  echo "$PPID ppid"/' "$SUT" > "$MUT34"
  D34m="$(fresh_root)"
  if grep -q '^  echo "\$PPID ppid"$' "$MUT34"; then
    orphan_acquire "$MUT34" "$D34m" "$D34m.ppid"
    p34m="$(meta_val "$D34m" pid)"
    set_meta_field "$D34m" ts "$(( $(date +%s) - 4000 ))"
    bash "$MUT34" acquire --owner x:34b --root "$D34m" >/dev/null 2>&1; rc34m=$?
    if kill -0 1 2>/dev/null; then want34m=1; else want34m=0; fi
    if [ "$p34m" = 1 ] && [ "$rc34m" -eq "$want34m" ]; then
      ok "mutation control: the pre-fix fallback records pid 1 (aged-acquire rc=$rc34m; kill -0 1 here: $([ "$want34m" = 1 ] && echo succeeds || echo EPERM))"
    else
      no "mutation control did not reproduce: pid='$p34m' rc=$rc34m want_rc=$want34m"
    fi
  else
    no "mutation control: could not locate the ppid fallback line in run-lock.sh"
  fi
  rm -rf "$(dirname "$MUT34")"
fi
rm -rf "$STUB34"
rm -f "$D34.ppid" "$D34.err" "${D34m:-}.ppid" "${D34m:-}.err"
rm -rf "$PSSTUB" "$TBL" "$RUN_ERR_FILE"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
