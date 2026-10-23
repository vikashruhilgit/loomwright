#!/usr/bin/env bash
# test-proc-registry.sh — self-tests for loomwright/scripts/proc-registry.sh (register / list / reap).
# Isolated: every leg uses its own LOOMWRIGHT_PROC_REGISTRY_DIR under one mktemp -d, the SUT runs as a
# subprocess, and every fixture process is a background child of this shell, killed by the leg (and
# by the EXIT trap). The hermetic legs fake HOME and assert nothing lands under it.
#
#   AC1  register writes ONE <id>.json with every key (absent optionals null), built with jq --arg
#        (a purpose full of quotes / `$( )` survives verbatim and runs nothing); relative paths made
#        absolute; registering the same process twice keeps one entry; the same pid with a different
#        start time (a PATH-stub `ps`) is a NEW entry and the old file is byte-identical.
#   AC2  --expect waits for a not-yet-exec'd command line (the entry then classifies running), also past
#        a `nohup` / `env` launcher stage whose line already carries the substring; a
#        never-matching --expect still writes, prints one stderr line, and is bounded (< 6 s).
#   AC3  fail-safe: unwritable dir, jq missing, dead pid, merge-watch without --max-lifetime, bad
#        arguments — exit 0, exactly one `register failed — <reason>` stderr line, nothing written.
#   AC4  list classifies running / overdue / orphaned (repo missing, ## Status: done, lane missing,
#        owner dead, owner recycled) / finished (pid gone, lstart differs, hash differs); overdue wins
#        over orphaned; exit 0; the registry is unchanged by list.
#   AC5  reap without --apply: every class present, no signal, registry checksum unchanged.
#   AC6  reap --apply: overdue + orphaned stopped and removed, finished pruned, running untouched, one
#        reap.log line per processed entry; a TERM-ignoring process is KILLed; for a wrapper kind the
#        wrapper's TERM-ignoring child is KILLed too (a non-wrapper kind's child is not); a process that execs a
#        different command during the grace is NOT KILLed (the re-check); named ids only; an unknown id
#        is skipped; a malformed id is a usage error; reap.log keeps its last 1000 lines.
#   AC7  a recycled pid (alive, different command line) is finished and survives reap --apply.
#   AC8  HERMETIC_TEST_ENV=1 redirects to $HERMETIC_SHIM_DIR/procs (nothing under a fake HOME); an empty
#        or missing HERMETIC_SHIM_DIR is unavailable (register fails safe, list/reap empty, no write
#        anywhere); outside hermetic mode the default is $HOME's user-scope registry.
#   AC9  the header names the contract; its caps table equals the code's (per-kind registration), the
#        LOOMWRIGHT_PROC_MAX_S_<KIND> overrides and --max-lifetime precedence work; exit codes.
#   MUTATION CONTROLS (each mutant gated per lesson fa32a308: non-empty, byte-differs, parses, and a
#   line-delete removes exactly one line), each must turn its leg red: the cmd-hash comparison
#   deleted (AC7), the --apply gate deleted (AC5), the ## Status read deleted (AC4), the age compare
#   flipped (AC4), the hermetic branch deleted (AC8), the HERMETIC_SHIM_DIR check deleted (AC8), the id
#   from the pid alone (AC1), register's failure path exiting 1 (AC3), the re-check before KILL
#   deleted (AC6), the reap filter widened to running (AC6), the wrapper-kind child KILL deleted (AC6),
#   the --expect launcher-stage check deleted (AC2).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUT_REAL="$HERE/proc-registry.sh"
S="$SUT_REAL"
. "$HERE/wait-lib.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass + 1)); }
no() { echo "  FAIL: $1"; fail=$((fail + 1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/test-proc-registry.XXXXXX")"
export LOOMWRIGHT_PROC_REGISTRY_DIR="$WORK/default-registry"   # nothing ever falls through to a real home
# Fixtures are disowned (no "Killed: 9" job notices when reap stops one) and tracked in $FIXDIR as
# <pid> -> its lstart at spawn; cleanup kills a fixture only while that lstart still matches, so it
# never signals a pid the OS has since reused — the rule the SUT itself keeps.
FIXDIR="$WORK/fixtures"; mkdir -p "$FIXDIR"
fix_kill() {   # fix_kill <pid> — kill -9 a tracked fixture if it is still the process we spawned
  local want cur
  want="$(cat "$FIXDIR/$1" 2>/dev/null)"; rm -f "$FIXDIR/$1"
  cur="$(env TZ=UTC0 LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null)"
  [ -n "$want" ] && [ "$cur" = "$want" ] && kill -9 "$1" 2>/dev/null
  return 0
}
cleanup() {
  local f
  for f in "$FIXDIR"/*; do [ -f "$f" ] && fix_kill "${f##*/}"; done
  chmod -R u+w "$WORK" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

# --- leg harness: real mode prints ok/FAIL; mutant mode (QUIET=1) only records LEG_FAIL ---------------
QUIET=0; LEG_FAIL=0; LEG_PIDS=""
check() {   # check <label> <command…>
  local label="$1"; shift
  if "$@"; then
    [ "$QUIET" = 1 ] || ok "$label"
  else
    LEG_FAIL=1
    [ "$QUIET" = 1 ] || no "$label"
  fi
}
spawn() {
  "$@" </dev/null >/dev/null 2>&1 &
  SP=$!; disown "$SP" 2>/dev/null
  env TZ=UTC0 LC_ALL=C ps -o lstart= -p "$SP" > "$FIXDIR/$SP" 2>/dev/null
  LEG_PIDS="$LEG_PIDS $SP"
}
# sleeper — the plain long-lived fixture process (sets SP); spawn backgrounds it, nothing waits on it
sleeper() { spawn sleep 3001; }   # fixed-sleep-ok: a background FIXTURE process to register, not a wait
leg_end() {
  local p
  for p in $LEG_PIDS; do fix_kill "$p"; done
  LEG_PIDS=""
}
no_lstart() { [ -z "$(ps -o lstart= -p "$1" 2>/dev/null)" ]; }
# kill_gone <pid> — stop a fixture and wait until it is reaped (a zombie still reports an lstart)
kill_gone() { fix_kill "$1"; WAIT_LIB_WHAT="pid $1 to be reaped" wait_for_cmd 5 no_lstart "$1"; }
new_reg() { R="$(mktemp -d "$WORK/reg.XXXXXX")"; export LOOMWRIGHT_PROC_REGISTRY_DIR="$R"; }
reg() { bash "$S" register "$@"; }
alive() {
  local s
  s="$(ps -o stat= -p "$1" 2>/dev/null | tr -d '[:space:]')"
  [ -n "$s" ] || return 1
  case "$s" in Z*) return 1 ;; esac
  return 0
}
gone() { ! alive "$1"; }
njson() { local n=0 f; for f in "$R"/*.json; do [ -f "$f" ] && n=$((n + 1)); done; printf '%s' "$n"; }
efile() {
  local f
  for f in "$R"/*.json; do
    [ -f "$f" ] && [ "$(jq -r .pid "$f" 2>/dev/null)" = "$1" ] && { printf '%s' "$f"; return 0; }
  done
  return 1
}
eid() { local f; f="$(efile "$1")" || return 1; basename "$f" .json; }
efield() { jq -r ".$2" "$(efile "$1")" 2>/dev/null; }
forge() { local f; f="$(efile "$1")" && jq --arg v "$3" ".$2 = \$v" "$f" > "$WORK/forge.tmp" && mv "$WORK/forge.tmp" "$f"; }
class_of() { bash "$S" list 2>/dev/null | awk -F'\t' -v p="$1" '$3 == p { print $5; exit }'; }
is_class() { [ "$(class_of "$1")" = "$2" ]; }
dirsum() { (cd "$R" && find . -type f | env LC_ALL=C sort | while IFS= read -r f; do printf '%s ' "$f"; cksum < "$f"; done); }
eq() { [ "$1" = "$2" ]; }
cmd_is() { [ "$(ps -ww -o command= -p "$1" 2>/dev/null | sed -e 's/^ *//' -e 's/ *$//')" = "$2" ]; }
# ready_fixture <script> — spawn `bash -c <script> _ <readyfile>` and wait until the script has run
# far enough to touch "$1" (its traps installed), so no signal can land before the trap does
ready_fixture() {
  local rf="$WORK/ready.$RANDOM.$RANDOM"
  spawn bash -c "$1" _ "$rf"
  WAIT_LIB_WHAT="fixture $SP to install its trap" wait_for_cmd 5 test -f "$rf"
}
has() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }
lines() { awk 'END { print NR }' "$1"; }
one_fail_line() {   # one_fail_line <stderr file> <reason substring>
  [ "$(lines "$1")" = 1 ] && grep -q '^proc-registry: register failed — ' "$1" && grep -qF -- "$2" "$1"
}
# the shared overdue fixture: registered with a 1 s cap, overdue once its age passes 1 s
reg_overdue() { reg --pid "$1" --kind lane --purpose overdue --max-lifetime 1 "${@:2}"; }
wait_overdue() { WAIT_LIB_WHAT="pid $1 to read overdue" wait_for_cmd 10 is_class "$1" overdue; }

ERR="$WORK/stderr"

# ==== AC1 — keys, jq-built JSON, one entry per process, a new entry per start time ==================
leg_keys() {
  local p f keys out cwd
  new_reg
  sleeper; p=$SP
  out="$(env -u CLAUDE_CODE_SESSION_ID bash "$S" register --pid "$p" --kind lane --purpose 'say "hi" $(touch '"$WORK"'/pwned) `x` \ end' 2>"$ERR")"
  check "AC1 register exits 0 and prints nothing" eq "$?|$out|$(cat "$ERR")" "0||"
  check "AC1 exactly one entry file" eq "$(njson)" 1
  f="$(efile "$p")"
  keys="$(jq -r 'keys | join(",")' "$f")"
  check "AC1 every key present" eq "$keys" "cmd_hash,grace_s,kind,lane,max_lifetime_s,owner_pid,owner_start,pid,pid_start,purpose,registered_at,repo,run_id,runfile,session_id,stop_hint"
  check "AC1 absent optionals are JSON null" eq "$(jq -c '[.repo, .run_id, .runfile, .lane, .owner_pid, .owner_start, .session_id, .stop_hint]' "$f")" "[null,null,null,null,null,null,null,null]"
  check "AC1 pid_start is the C-locale UTC lstart" eq "$(jq -r .pid_start "$f")" "$(env TZ=UTC0 LC_ALL=C ps -o lstart= -p "$p" | sed -e 's/^ *//' -e 's/ *$//')"
  check "AC1 cmd_hash is <algo>:<hash>" has "$(jq -r .cmd_hash "$f" | sed -E 's/^(sha1|cksum):[0-9a-f]+$/SHAPE_OK/')" SHAPE_OK
  check "AC1 kind / table cap / default grace" eq "$(jq -c '[.kind, .max_lifetime_s, .grace_s]' "$f")" '["lane",86400,10]'
  check "AC1 purpose is stored verbatim (jq --arg, never templated)" eq "$(jq -r .purpose "$f")" 'say "hi" $(touch '"$WORK"'/pwned) `x` \ end'
  check "AC1 the purpose ran nothing" eq "$([ -e "$WORK/pwned" ] && echo ran || echo clean)" clean
  check "AC1 the id is <pid>-<hash>" has "$(basename "$f" .json | sed -E "s/^$p-[A-Za-z0-9]+\$/ID_OK/")" ID_OK
  # every optional, with relative paths made absolute against the caller's cwd
  mkdir -p "$WORK/cwd/rel/repo" "$WORK/cwd/rel/lane"; : > "$WORK/cwd/rel/run.md"
  cwd="$(cd "$WORK/cwd" && pwd)"   # $PWD's normalized form (a TMPDIR ending in / leaves a // in $WORK)
  sleeper; local q=$SP owner
  sleeper; owner=$SP
  (cd "$cwd" && bash "$S" register --pid "$q" --kind drain --purpose all --repo rel/repo --run-id run-1 \
     --runfile rel/run.md --lane rel/lane --owner-pid "$owner" --max-lifetime 50 --grace 3 \
     --stop-hint "TERM the pid" --session-id sess-1) 2>"$ERR"
  f="$(efile "$q")"
  check "AC1 optionals stored (relative paths absolutized)" eq "$(jq -c '[.repo, .run_id, .runfile, .lane, .owner_pid, .max_lifetime_s, .grace_s, .stop_hint, .session_id]' "$f")" \
    "[\"$cwd/rel/repo\",\"run-1\",\"$cwd/rel/run.md\",\"$cwd/rel/lane\",$owner,50,3,\"TERM the pid\",\"sess-1\"]"
  check "AC1 owner_start is the owner's lstart" eq "$(jq -r .owner_start "$f")" "$(env TZ=UTC0 LC_ALL=C ps -o lstart= -p "$owner" | sed -e 's/^ *//' -e 's/ *$//')"
  leg_end
}

# psbin: a PATH-stub `ps` that reports $FAKE_LSTART for `lstart=` (a pid reused by a later process)
PSBIN="$WORK/psbin"; mkdir -p "$PSBIN"
printf '#!/bin/sh\ncase " $* " in *" lstart= "*) if [ -n "${FAKE_LSTART:-}" ]; then echo "$FAKE_LSTART"; exit 0; fi ;; esac\nexec %s "$@"\n' "$(command -v ps)" > "$PSBIN/ps"
chmod +x "$PSBIN/ps"

leg_id() {
  local p f1 s1
  new_reg
  sleeper; p=$SP
  reg --pid "$p" --kind lane --purpose first 2>/dev/null
  reg --pid "$p" --kind lane --purpose second 2>/dev/null
  check "AC1 registering the same live process twice keeps ONE entry" eq "$(njson)" 1
  check "AC1 the re-register rewrote that entry" eq "$(efield "$p" purpose)" second
  f1="$(efile "$p")"; s1="$(cksum < "$f1")"
  PATH="$PSBIN:$PATH" FAKE_LSTART="Mon Jan  1 00:00:00 2001" bash "$S" register --pid "$p" --kind lane --purpose reused 2>/dev/null
  check "AC1 the same pid with a different start time is a NEW entry" eq "$(njson)" 2
  check "AC1 the old entry is never overwritten" eq "$(cksum < "$f1" 2>/dev/null)" "$s1"
  leg_end
}

# ==== AC2 — --expect ===================================================================================
leg_expect() {
  local p t0 el a
  new_reg
  # the pre-exec command line (`bash -c … exec "$0" 3002 sleep`) does NOT contain `sleep 3002`; the
  # exec'd one is exactly `sleep 3002` — a real not-yet-exec'd window, like a nohup before its exec
  spawn bash -c 'sleep 1.5; exec "$0" 3002' sleep; p=$SP
  reg --pid "$p" --kind postmortem --purpose expect --expect 'sleep 3002' 2>"$ERR"
  check "AC2 --expect that appears: no stderr" eq "$(cat "$ERR")" ""
  check "AC2 --expect hashed the exec'd command line (classifies running)" is_class "$p" running
  # control: the same race without --expect hashes the pre-exec line and reads finished after the exec
  spawn bash -c 'sleep 1.5; exec "$0" 3005' sleep; p=$SP
  reg --pid "$p" --kind postmortem --purpose no-expect 2>/dev/null
  WAIT_LIB_WHAT="pid $p to exec sleep 3005" wait_for_cmd 10 cmd_is "$p" 'sleep 3005'
  check "AC2 (control) without --expect the pre-exec hash reads finished" is_class "$p" finished
  # a launcher stage whose line ALREADY contains the substring (`nohup …` / `/usr/bin/env …`, argv[0] set by
  # `exec -a`): --expect alone would match it at once; register waits until the line has exec'd past it
  for a in nohup /usr/bin/env; do
    spawn bash -c 'exec -a "$0" bash -c "sleep 1.5; exec sleep 3004"' "$a"; p=$SP
    WAIT_LIB_WHAT="pid $p to show its $a stage" wait_for_cmd 5 eval 'has "$(ps -ww -o command= -p "$p" 2>/dev/null)" "$a -c"'
    reg --pid "$p" --kind postmortem --purpose "launcher $a" --expect 'sleep 3004' 2>"$ERR"
    WAIT_LIB_WHAT="pid $p to exec sleep 3004" wait_for_cmd 10 cmd_is "$p" 'sleep 3004'
    check "AC2 --expect waits past a '$a' launcher stage that already carries the substring" eval '[ -z "$(cat "$ERR")" ] && is_class "$p" running'
    fix_kill "$p"; rm -f "$(efile "$p")"
  done
  sleeper; p=$SP
  t0="$(date +%s)"
  reg --pid "$p" --kind postmortem --purpose never --expect 'no-such-substring-xyz' 2>"$ERR"
  el=$(( $(date +%s) - t0 ))
  check "AC2 a never-matching --expect still writes the entry" eq "$(njson)" 3
  check "AC2 ... and prints exactly one 'never matched' line" eq "$(lines "$ERR")|$(cat "$ERR")" "1|proc-registry: register — command line never matched --expect"
  check "AC2 ... and the wait is bounded (2..6 s, got ${el}s)" eval '[ "$el" -ge 2 ] && [ "$el" -le 6 ]'
  leg_end
}

# ==== AC3 — fail-safe ==================================================================================
leg_failsafe() {
  local p rc nojq t r
  new_reg
  sleeper; p=$SP
  if [ "$(id -u)" != 0 ]; then
    chmod 555 "$R"
    reg --pid "$p" --kind lane --purpose x 2>"$ERR"; rc=$?
    check "AC3 unwritable dir: exit 0, one 'register failed' line, nothing written" eval '[ "$rc" = 0 ] && one_fail_line "$ERR" "$R" && [ "$(njson)" = 0 ]'
    chmod 755 "$R"
  else
    [ "$QUIET" = 1 ] || echo "  skip: AC3 unwritable dir (running as root)"
  fi
  nojq="$WORK/nojq"; mkdir -p "$nojq"
  for t in ps env sed cut awk date mkdir mktemp mv rm tr sort basename shasum sha1sum cksum tail sleep cat; do
    r="$(command -v "$t" 2>/dev/null)" && [ ! -e "$nojq/$t" ] && ln -s "$r" "$nojq/$t"
  done
  PATH="$nojq" "$BASH" "$S" register --pid "$p" --kind lane --purpose x 2>"$ERR"; rc=$?
  check "AC3 jq missing: exit 0, one 'register failed — jq not found' line" eval '[ "$rc" = 0 ] && one_fail_line "$ERR" "jq not found" && [ "$(njson)" = 0 ]'
  sleeper; local dead=$SP
  kill_gone "$dead"
  reg --pid "$dead" --kind lane --purpose x 2>"$ERR"; rc=$?
  check "AC3 dead pid: exit 0, one 'is not running' line" eval '[ "$rc" = 0 ] && one_fail_line "$ERR" "is not running" && [ "$(njson)" = 0 ]'
  reg --pid "$p" --kind merge-watch --purpose x 2>"$ERR"; rc=$?
  check "AC3 merge-watch without --max-lifetime fails safe" eval '[ "$rc" = 0 ] && one_fail_line "$ERR" "requires --max-lifetime" && [ "$(njson)" = 0 ]'
  LOOMWRIGHT_PROC_MAX_S_MERGE_WATCH=99 bash "$S" register --pid "$p" --kind merge-watch --purpose x 2>"$ERR"; rc=$?
  check "AC3 merge-watch has no env-override default either" eval '[ "$rc" = 0 ] && one_fail_line "$ERR" "requires --max-lifetime"'
  reg --kind lane --purpose x 2>"$ERR"; rc=$?
  check "AC3 missing --pid fails safe" eval '[ "$rc" = 0 ] && one_fail_line "$ERR" "missing --pid"'
  reg --pid "$p" --kind bogus --purpose x 2>"$ERR"; rc=$?
  check "AC3 unknown --kind fails safe" eval '[ "$rc" = 0 ] && one_fail_line "$ERR" "unknown --kind"'
  reg --pid "$p" --kind lane --purpose x --bogus 1 2>"$ERR"; rc=$?
  check "AC3 unknown option fails safe" eval '[ "$rc" = 0 ] && one_fail_line "$ERR" "unknown option"'
  reg --pid "$p" --kind lane --purpose x --grace 2>"$ERR"; rc=$?
  check "AC3 an option missing its value fails safe" eval '[ "$rc" = 0 ] && one_fail_line "$ERR" "missing value for --grace"'
  reg --pid "$p" --kind merge-watch --purpose x --max-lifetime 7200 2>"$ERR"; rc=$?
  check "AC3 (control) merge-watch WITH --max-lifetime registers" eval '[ "$rc" = 0 ] && [ ! -s "$ERR" ] && [ "$(efield "$p" max_lifetime_s)" = 7200 ]'
  leg_end
}

# ==== AC4 — classes ====================================================================================
leg_status_done() {
  local p q rf rf2
  new_reg
  rf="$WORK/run-done.md"; printf '# run\n## Status: done\n' > "$rf"
  rf2="$WORK/run-live.md"; printf '# run\n## Status: running\n' > "$rf2"
  sleeper; p=$SP; sleeper; q=$SP
  reg --pid "$p" --kind phase --purpose done --runfile "$rf" 2>/dev/null
  reg --pid "$q" --kind phase --purpose live --runfile "$rf2" 2>/dev/null
  check "AC4 orphaned: the run file's ## Status: is done" is_class "$p" orphaned
  check "AC4 (control) ## Status: running stays running" is_class "$q" running
  leg_end
}

leg_overdue_vs_running() {
  local p q
  new_reg
  sleeper; p=$SP; sleeper; q=$SP
  reg_overdue "$p" 2>/dev/null
  reg --pid "$q" --kind lane --purpose young --max-lifetime 3600 2>/dev/null
  check "AC4 running: a young process under its cap" is_class "$q" running
  wait_overdue "$p" 2>/dev/null
  check "AC4 overdue: running and older than max_lifetime_s" is_class "$p" overdue
  leg_end
}

leg_classes() {
  local p repo lane owner own2 out before rows
  new_reg
  sleeper; local p_repo=$SP; repo="$WORK/repo-gone"; mkdir -p "$repo"
  reg --pid "$p_repo" --kind drain --purpose r --repo "$repo" 2>/dev/null; rmdir "$repo"
  sleeper; local p_lane=$SP; lane="$WORK/lane-gone"; mkdir -p "$lane"
  reg --pid "$p_lane" --kind lane --purpose l --lane "$lane" 2>/dev/null; rmdir "$lane"
  sleeper; owner=$SP; sleeper; local p_own=$SP
  reg --pid "$p_own" --kind phase --purpose o --owner-pid "$owner" 2>/dev/null
  kill_gone "$owner"
  sleeper; own2=$SP; sleeper; local p_rec=$SP
  reg --pid "$p_rec" --kind phase --purpose o2 --owner-pid "$own2" 2>/dev/null
  forge "$p_rec" owner_start "Mon Jan  1 00:00:00 2001"
  sleeper; local p_ok=$SP; sleeper; local own3=$SP
  reg --pid "$p_ok" --kind phase --purpose ok --owner-pid "$own3" --repo "$WORK" --lane "$WORK" 2>/dev/null
  sleeper; local p_gone=$SP
  reg --pid "$p_gone" --kind lane --purpose g 2>/dev/null
  kill_gone "$p_gone"
  sleeper; local p_ls=$SP
  reg --pid "$p_ls" --kind lane --purpose ls 2>/dev/null; forge "$p_ls" pid_start "Mon Jan  1 00:00:00 2001"
  sleeper; local p_hash=$SP
  reg --pid "$p_hash" --kind lane --purpose h 2>/dev/null; forge "$p_hash" cmd_hash "sha1:0000"
  sleeper; local p_both=$SP; repo="$WORK/repo-gone2"; mkdir -p "$repo"
  reg_overdue "$p_both" --repo "$repo" 2>/dev/null; rmdir "$repo"
  wait_overdue "$p_both" 2>/dev/null
  before="$(dirsum)"
  out="$(bash "$S" list)"; local rc=$?
  check "AC4 list exits 0 and changes nothing" eval '[ "$rc" = 0 ] && [ "$(dirsum)" = "$before" ]'
  check "AC4 orphaned: repo dir missing" is_class "$p_repo" orphaned
  check "AC4 orphaned: lane dir missing" is_class "$p_lane" orphaned
  check "AC4 orphaned: owner pid dead" is_class "$p_own" orphaned
  check "AC4 orphaned: owner pid recycled (owner_start differs)" is_class "$p_rec" orphaned
  check "AC4 running: owner alive, repo + lane present" is_class "$p_ok" running
  check "AC4 finished: pid gone" is_class "$p_gone" finished
  check "AC4 finished: lstart differs" is_class "$p_ls" finished
  check "AC4 finished: command-line hash differs" is_class "$p_hash" finished
  check "AC4 overdue AND orphaned prints overdue" is_class "$p_both" overdue
  check "AC4 ... and its evidence names the orphan too" has "$(awk -F'\t' -v p="$p_both" '$3 == p' <<<"$out")" "also orphaned: repo dir missing"
  rows="$(awk -F'\t' '!/^#/ && NF != 6 { bad++ } END { print bad + 0 }' <<<"$out")"
  check "AC4 every row is id/kind/pid/age/class/evidence" eq "$rows" 0
  check "AC4 one row per entry" eq "$(grep -vc '^#' <<<"$out")" "$(njson)"
  leg_end
  new_reg
  check "AC4 an empty registry lists (no entries)" has "$(bash "$S" list)" "(no entries)"
}

# fixture set with one entry per class, for AC5/AC6 (sets C_RUN C_OVER C_ORPH C_FIN)
classes_fixture() {
  local repo="$WORK/repo-$RANDOM"
  new_reg
  sleeper; C_RUN=$SP; reg --pid "$C_RUN" --kind lane --purpose run --max-lifetime 3600 2>/dev/null
  sleeper; C_OVER=$SP; reg_overdue "$C_OVER" 2>/dev/null
  mkdir -p "$repo"
  sleeper; C_ORPH=$SP; reg --pid "$C_ORPH" --kind drain --purpose orph --repo "$repo" 2>/dev/null
  rmdir "$repo"
  sleeper; C_FIN=$SP; reg --pid "$C_FIN" --kind lane --purpose fin 2>/dev/null
  kill_gone "$C_FIN"
  wait_overdue "$C_OVER" 2>/dev/null
}

# ==== AC5 — dry run ====================================================================================
leg_dryrun() {
  local before out rc
  classes_fixture
  before="$(dirsum)"
  out="$(bash "$S" reap 2>/dev/null)"; rc=$?
  check "AC5 dry run exits 0" eq "$rc" 0
  check "AC5 dry run: registry checksum unchanged (no file written or removed)" eq "$(dirsum)" "$before"
  check "AC5 dry run: no signal sent (overdue, orphaned, running all alive)" eval 'alive "$C_OVER" && alive "$C_ORPH" && alive "$C_RUN"'
  check "AC5 dry run prints the action per entry" eval 'has "$out" "would stop $(eid "$C_OVER")" && has "$out" "would stop $(eid "$C_ORPH")" && has "$out" "would prune $(eid "$C_FIN")" && has "$out" "keep $(eid "$C_RUN")"'
  leg_end
}

# ==== AC6 — reap --apply ===============================================================================
leg_apply_classes() {
  local out
  classes_fixture
  local id_run id_over id_orph id_fin
  id_run="$(eid "$C_RUN")"; id_over="$(eid "$C_OVER")"; id_orph="$(eid "$C_ORPH")"; id_fin="$(eid "$C_FIN")"
  out="$(bash "$S" reap --apply 2>/dev/null)"
  WAIT_LIB_WHAT="overdue + orphaned fixtures to die" wait_for_cmd 10 eval 'gone "$C_OVER" && gone "$C_ORPH"'
  check "AC6 overdue and orphaned processes are stopped" eval 'gone "$C_OVER" && gone "$C_ORPH"'
  check "AC6 running is never touched (alive, entry kept)" eval 'alive "$C_RUN" && [ -f "$R/$id_run.json" ]'
  check "AC6 stopped and finished entries are removed" eval '[ ! -e "$R/$id_over.json" ] && [ ! -e "$R/$id_orph.json" ] && [ ! -e "$R/$id_fin.json" ]'
  check "AC6 reap.log: one line per processed entry (3)" eq "$(lines "$R/reap.log" 2>/dev/null)" 3
  check "AC6 reap.log names each processed id, never the running one" eval 'grep -qF "$id_over" "$R/reap.log" && grep -qF "$id_orph" "$R/reap.log" && grep -qF "$id_fin" "$R/reap.log" && ! grep -qF "$id_run" "$R/reap.log"'
  leg_end
}

leg_recheck_kill() {
  local p repo="$WORK/repo-rk-$RANDOM"
  new_reg
  mkdir -p "$repo"
  # ignores TERM by exec'ing a DIFFERENT command: same pid + lstart, new command line
  ready_fixture 'trap "exec sleep 3003" TERM; : > "$1"; while :; do sleep 0.1; done'; p=$SP
  reg --pid "$p" --kind drain --purpose rk --repo "$repo" --grace 1 2>/dev/null; rmdir "$repo"
  bash "$S" reap --apply >/dev/null 2>&1
  check "AC6 a process that no longer matches after TERM is NOT KILLed (re-check before KILL)" alive "$p"
  check "AC6 ... and its entry is removed (it is no longer the registered process)" eq "$(njson)" 0
  leg_end
}

# child_of <pid> — the first live direct child of <pid> (empty when none)
child_of() { ps -A -o pid= -o ppid= -o stat= 2>/dev/null | awk -v p="$1" '$2 == p && $3 !~ /^Z/ { print $1; exit }'; }
# WRAPPER KINDS: a wrapper of the contract's shape (TERM passed on to a background child, waits while it
# lives) whose child IGNORES TERM — so only reap's KILL leg can end it, and a wrapper cannot pass a KILL on
WRAP_FIXTURE='bash -c "trap \"\" TERM; while :; do sleep 0.1; done" & c=$!; trap "kill -TERM $c 2>/dev/null" TERM; : > "$1"; while kill -0 "$c" 2>/dev/null; do wait "$c"; done'
leg_wrapper_kill() {
  local p c out
  new_reg
  ready_fixture "$WRAP_FIXTURE"; p=$SP
  WAIT_LIB_WHAT="wrapper $p to start its child" wait_for_cmd 5 eval '[ -n "$(child_of "$p")" ]'
  c="$(child_of "$p")"; [ -n "$c" ] && { env TZ=UTC0 LC_ALL=C ps -o lstart= -p "$c" > "$FIXDIR/$c" 2>/dev/null; LEG_PIDS="$LEG_PIDS $c"; }
  reg --pid "$p" --kind lane --purpose wrapper --max-lifetime 1 --grace 1 2>/dev/null
  wait_overdue "$p"
  out="$(bash "$S" reap --apply 2>/dev/null)"
  WAIT_LIB_WHAT="wrapper $p and child $c to be gone" wait_for_cmd 10 eval 'gone "$p" && gone "$c"'
  check "AC6 wrapper kind: reap KILLs the wrapper's TERM-ignoring child (never orphaned)" eval '[ -n "$c" ] && gone "$c"'
  check "AC6 ... the wrapper then exits by itself and the entry is removed" eval 'gone "$p" && [ "$(njson)" = 0 ] && has "$out" "KILLed 1 child process(es) of the wrapper"'
  # control: the same shape registered as a NON-wrapper kind — reap KILLs the pid alone, the child survives
  ready_fixture "$WRAP_FIXTURE"; p=$SP
  WAIT_LIB_WHAT="wrapper $p to start its child" wait_for_cmd 5 eval '[ -n "$(child_of "$p")" ]'
  c="$(child_of "$p")"; [ -n "$c" ] && { env TZ=UTC0 LC_ALL=C ps -o lstart= -p "$c" > "$FIXDIR/$c" 2>/dev/null; LEG_PIDS="$LEG_PIDS $c"; }
  reg --pid "$p" --kind postmortem --purpose plain --max-lifetime 1 --grace 1 2>/dev/null
  wait_overdue "$p"
  bash "$S" reap --apply >/dev/null 2>&1
  WAIT_LIB_WHAT="pid $p to be gone" wait_for_cmd 10 gone "$p"
  check "AC6 (control) a non-wrapper kind's child is not signalled by reap" eval '[ -n "$c" ] && alive "$c"'
  leg_end
}

leg_apply_more() {
  local p a b ida idb repo="$WORK/repo-am-$RANDOM" rc out i
  new_reg
  mkdir -p "$repo"
  ready_fixture 'trap "" TERM; : > "$1"; while :; do sleep 0.1; done'; p=$SP
  reg --pid "$p" --kind drain --purpose stubborn --repo "$repo" --grace 1 2>/dev/null
  sleeper; a=$SP; reg --pid "$a" --kind drain --purpose a --repo "$repo" 2>/dev/null
  sleeper; b=$SP; reg --pid "$b" --kind drain --purpose b --repo "$repo" 2>/dev/null
  rmdir "$repo"
  ida="$(eid "$a")"; idb="$(eid "$b")"
  out="$(bash "$S" reap --apply "$ida" "$(eid "$p")" 2>/dev/null)"
  WAIT_LIB_WHAT="named ids to die" wait_for_cmd 10 eval 'gone "$a" && gone "$p"'
  check "AC6 a TERM-ignoring process is KILLed after its grace" eval 'gone "$p" && has "$out" "TERM+KILL"'
  check "AC6 reap <id>: only the named ids are touched" eval 'gone "$a" && alive "$b" && [ -f "$R/$idb.json" ]'
  out="$(bash "$S" reap --apply 99999-nosuchid 2>"$ERR")"; rc=$?
  check "AC6 an id not in the registry is reported and skipped (exit 0)" eval '[ "$rc" = 0 ] && grep -qF "no entry 99999-nosuchid" "$ERR" && alive "$b"'
  bash "$S" reap --apply ../etc/passwd >/dev/null 2>&1; rc=$?
  check "AC6 a malformed id is a usage error (non-zero)" eval '[ "$rc" != 0 ] && alive "$b"'
  bash "$S" reap --bogus >/dev/null 2>&1; rc=$?
  check "AC6 an unknown reap option is a usage error" eval '[ "$rc" != 0 ]'
  i=0; : > "$R/reap.log"; while [ "$i" -lt 1005 ]; do echo "old line $i"; i=$((i + 1)); done >> "$R/reap.log"
  bash "$S" reap --apply "$idb" >/dev/null 2>&1
  check "AC6 reap.log keeps its last 1000 lines" eval '[ "$(lines "$R/reap.log")" = 1000 ] && has "$(tail -n 1 "$R/reap.log")" "$idb" && ! grep -qx "old line 5" "$R/reap.log" && grep -qx "old line 6" "$R/reap.log"'
  leg_end
}

# ==== AC7 — recycled pid ===============================================================================
leg_recycled() {
  local p repo="$WORK/repo-rc-$RANDOM" out
  new_reg
  mkdir -p "$repo"
  ready_fixture 'trap "exec sleep 3004" USR1; : > "$1"; while :; do sleep 0.1; done'; p=$SP
  # repo removed too: if the hash were ignored the entry would read orphaned and reap would kill it
  reg --pid "$p" --kind drain --purpose recycled --repo "$repo" 2>/dev/null; rmdir "$repo"
  kill -USR1 "$p"
  WAIT_LIB_WHAT="pid $p to run a different command line" wait_for_cmd 5 cmd_is "$p" 'sleep 3004'
  check "AC7 a live pid running a different command line lists finished" is_class "$p" finished
  out="$(bash "$S" reap --apply 2>/dev/null)"
  check "AC7 reap --apply leaves the recycled pid alive" alive "$p"
  check "AC7 ... and only prunes its entry" eval '[ "$(njson)" = 0 ] && has "$out" "pruned (no signal)"'
  leg_end
}

# ==== AC8 — hermetic redirect ==========================================================================
leg_hermetic() {
  local p fh sh out
  fh="$(mktemp -d "$WORK/home.XXXXXX")"; sh="$(mktemp -d "$WORK/shim.XXXXXX")"
  sleeper; p=$SP
  (unset LOOMWRIGHT_PROC_REGISTRY_DIR; export HOME="$fh" HERMETIC_TEST_ENV=1 HERMETIC_SHIM_DIR="$sh"
   bash "$S" register --pid "$p" --kind lane --purpose herm) 2>"$ERR"
  check "AC8 HERMETIC_TEST_ENV=1: the entry lands in \$HERMETIC_SHIM_DIR/procs" eval 'ls "$sh/procs/"*.json >/dev/null 2>&1 && [ ! -s "$ERR" ]'
  check "AC8 ... and nothing lands under the (fake) HOME" eq "$(find "$fh" -mindepth 1 | wc -l | tr -d ' ')" 0
  out="$(unset LOOMWRIGHT_PROC_REGISTRY_DIR; export HOME="$fh" HERMETIC_TEST_ENV=1 HERMETIC_SHIM_DIR="$sh"; bash "$S" list)"
  check "AC8 list reads the hermetic registry" has "$out" "$(printf '\t%s\t' "$p")"
  leg_end
}

leg_hermetic_empty() {
  local p fh gone_dir out rc procs_before
  fh="$(mktemp -d "$WORK/home.XXXXXX")"; gone_dir="$WORK/shim-gone-$RANDOM"
  procs_before="$([ -e /procs ] && echo present || echo absent)"
  sleeper; p=$SP
  (unset LOOMWRIGHT_PROC_REGISTRY_DIR; export HOME="$fh" HERMETIC_TEST_ENV=1 HERMETIC_SHIM_DIR=""
   bash "$S" register --pid "$p" --kind lane --purpose herm) 2>"$ERR"; rc=$?
  check "AC8 empty HERMETIC_SHIM_DIR: register fails safe ('hermetic registry dir unavailable')" eval '[ "$rc" = 0 ] && one_fail_line "$ERR" "hermetic registry dir unavailable"'
  check "AC8 ... no write under HOME and never /procs" eval '[ "$(find "$fh" -mindepth 1 | wc -l | tr -d " ")" = 0 ] && [ "$([ -e /procs ] && echo present || echo absent)" = "$procs_before" ]'
  (unset LOOMWRIGHT_PROC_REGISTRY_DIR; export HOME="$fh" HERMETIC_TEST_ENV=1 HERMETIC_SHIM_DIR="$gone_dir"
   bash "$S" register --pid "$p" --kind lane --purpose herm) 2>"$ERR"; rc=$?
  check "AC8 HERMETIC_SHIM_DIR not a directory: fails safe, creates nothing" eval '[ "$rc" = 0 ] && one_fail_line "$ERR" "hermetic registry dir unavailable" && [ ! -e "$gone_dir" ] && [ "$(find "$fh" -mindepth 1 | wc -l | tr -d " ")" = 0 ]'
  out="$(unset LOOMWRIGHT_PROC_REGISTRY_DIR; export HOME="$fh" HERMETIC_TEST_ENV=1 HERMETIC_SHIM_DIR=""; bash "$S" list; echo "rc=$?"; bash "$S" reap --apply; echo "rc=$?")"
  check "AC8 ... list and reap report an empty registry (exit 0)" eq "$(grep -c '(no entries)' <<<"$out")|$(grep -c '^rc=0$' <<<"$out")" "2|2"
  leg_end
}

leg_default_location() {
  local p fh
  fh="$(mktemp -d "$WORK/home.XXXXXX")"
  sleeper; p=$SP
  (unset LOOMWRIGHT_PROC_REGISTRY_DIR HERMETIC_TEST_ENV; export HOME="$fh"
   bash "$S" register --pid "$p" --kind lane --purpose home) 2>/dev/null
  check "AC8 (control) outside hermetic mode the registry is \$HOME/.claude/loomwright/procs" eval 'ls "$fh/.claude/loomwright/procs/"*.json >/dev/null 2>&1'
  (unset LOOMWRIGHT_PROC_REGISTRY_DIR HERMETIC_TEST_ENV; export HOME=""
   bash "$S" register --pid "$p" --kind lane --purpose nohome) 2>"$ERR"
  check "AC8 an empty HOME is unavailable (never a root-level path)" one_fail_line "$ERR" "HOME is empty"
  leg_end
}

# ==== AC9 — header contract, caps, overrides, exit codes ===============================================
leg_header() {
  local hdr k p n rc
  hdr="$(awk '/^set -uo pipefail/ { exit } { print }' "$S")"
  for k in register list reap --apply --expect --max-lifetime --grace --stop-hint --owner-pid pid_start cmd_hash \
           owner_start max_lifetime_s grace_s registered_at session_id stop_hint run_id runfile \
           running overdue orphaned finished LOOMWRIGHT_PROC_REGISTRY_DIR HERMETIC_TEST_ENV HERMETIC_SHIM_DIR \
           LOOMWRIGHT_PROC_MAX_S_PHASE LOOMWRIGHT_PROC_MAX_S_LANE LOOMWRIGHT_PROC_MAX_S_DRAIN \
           LOOMWRIGHT_PROC_MAX_S_POSTMORTEM "NEVER SIGNAL BY PID ALONE" "EXIT CODES" "CLASSES" "CAPS" "precedence"; do
    has "$hdr" "$k" || { check "AC9 header names '$k'" false; }
  done
  check "AC9 header names every subcommand, key, class, cap override, location and exit code" true
  new_reg
  for k in phase lane drain postmortem; do
    sleeper; p=$SP
    reg --pid "$p" --kind "$k" --purpose cap 2>/dev/null
    n="$(efield "$p" max_lifetime_s)"
    check "AC9 the header's caps row for $k equals the code's default ($n)" eval 'grep -Eq "^#   $k +$n " <<<"$hdr"'
  done
  sleeper; p=$SP
  LOOMWRIGHT_PROC_MAX_S_DRAIN=77 bash "$S" register --pid "$p" --kind drain --purpose ov 2>/dev/null
  check "AC9 LOOMWRIGHT_PROC_MAX_S_DRAIN overrides the drain cap" eq "$(efield "$p" max_lifetime_s)" 77
  LOOMWRIGHT_PROC_MAX_S_DRAIN=abc bash "$S" register --pid "$p" --kind drain --purpose ov 2>/dev/null
  check "AC9 a non-numeric override is ignored (table default)" eq "$(efield "$p" max_lifetime_s)" 14400
  LOOMWRIGHT_PROC_MAX_S_DRAIN=77 bash "$S" register --pid "$p" --kind drain --purpose ov --max-lifetime 55 2>/dev/null
  check "AC9 --max-lifetime beats the env override" eq "$(efield "$p" max_lifetime_s)" 55
  bash "$S" >/dev/null 2>&1; rc=$?
  check "AC9 a missing subcommand is a usage error (non-zero)" eval '[ "$rc" != 0 ]'
  bash "$S" frobnicate >/dev/null 2>&1; rc=$?
  check "AC9 an unknown subcommand is a usage error (non-zero)" eval '[ "$rc" != 0 ]'
  bash "$S" list extra >/dev/null 2>&1; rc=$?
  check "AC9 list always exits 0" eq "$rc" 0
  bash "$S" help >/dev/null 2>&1; rc=$?
  check "AC9 help exits 0" eq "$rc" 0
  leg_end
}

# ==== run the legs against the real script =============================================================
echo "== proc-registry.sh =="
for leg in leg_keys leg_id leg_expect leg_failsafe leg_status_done leg_overdue_vs_running leg_classes \
           leg_dryrun leg_apply_classes leg_recheck_kill leg_wrapper_kill leg_apply_more leg_recycled leg_hermetic \
           leg_hermetic_empty leg_default_location leg_header; do
  LEG_FAIL=0; S="$SUT_REAL"; "$leg"
done

# ==== mutation controls ================================================================================
echo "== mutation controls =="
MUT=""
mk_mutant() {   # mk_mutant <name> del <fixed string> | sub <fixed a> <fixed b> | range <marker>
  local name="$1" mode="$2"
  MUT="$WORK/mutant-$name.sh"
  case "$mode" in
    del) awk -v m="$3" 'index($0, m) == 0' "$SUT_REAL" > "$MUT" ;;
    sub) awk -v a="$3" -v b="$4" '{ i = index($0, a); if (i) $0 = substr($0, 1, i - 1) b substr($0, i + length(a)); print }' "$SUT_REAL" > "$MUT" ;;
    range) awk -v m=">>> $3" -v e="<<< $3" 'index($0, m) { s = 1 } !s { print } index($0, e) { s = 0 }' "$SUT_REAL" > "$MUT" ;;
  esac
  MUT_MODE="$mode"
}
gate_mutant() {   # gate_mutant <label> — the lesson-fa32a308 gate
  local g=0
  [ -s "$MUT" ] || { no "$1 mutant is EMPTY"; g=1; }
  cmp -s "$MUT" "$SUT_REAL" && { no "$1 mutant is byte-identical — the mutation no-opped"; g=1; }
  bash -n "$MUT" 2>/dev/null || { no "$1 mutant does not parse"; g=1; }
  if [ "$MUT_MODE" = del ] && [ "$(( $(lines "$SUT_REAL") - $(lines "$MUT") ))" != 1 ]; then
    no "$1 mutant removed $(( $(lines "$SUT_REAL") - $(lines "$MUT") )) lines, not exactly one"; g=1
  fi
  return "$g"
}
run_mutant() {   # run_mutant <label> <leg>
  gate_mutant "$1" || return 0
  QUIET=1; LEG_FAIL=0; S="$MUT"
  "$2"
  QUIET=0; S="$SUT_REAL"
  if [ "$LEG_FAIL" = 1 ]; then ok "$1: the mutant turns $2 red"; else no "$1: the mutant PASSES $2 — the pin is not load-bearing"; fi
}

mk_mutant cmdhash del 'command line differs (pid recycled)'
run_mutant "AC7 cmd-hash comparison deleted" leg_recycled
mk_mutant apply del '_pr_dry_row; continue'
run_mutant "AC5 --apply gate deleted" leg_dryrun
mk_mutant status del 'st="$(awk '"'"'/^## Status:/'
run_mutant "AC4 ## Status read deleted" leg_status_done
mk_mutant age sub '"$E_AGE" -gt "$max"' '"$E_AGE" -lt "$max"'
run_mutant "AC4 age comparison flipped" leg_overdue_vs_running
mk_mutant hermetic range 'hermetic redirect'
run_mutant "AC8 HERMETIC_TEST_ENV branch deleted" leg_hermetic
mk_mutant shimcheck del 'PR_DIR_WHY="hermetic registry dir unavailable"'
run_mutant "AC8 HERMETIC_SHIM_DIR empty/not-a-dir check deleted" leg_hermetic_empty
mk_mutant idpid sub 'idh="$(_pr_hash "$pid $st"' 'idh="$(_pr_hash "$pid"'
run_mutant "AC1 id from the pid alone" leg_id
mk_mutant exit1 sub '"$PR_ME" "$1" >&2; }' '"$PR_ME" "$1" >&2; exit 1; }'
run_mutant "AC3 register failure path exits 1" leg_failsafe
mk_mutant recheck del '|| nokill="$PR_WHY"'
run_mutant "AC6 re-check before KILL deleted" leg_recheck_kill
mk_mutant kidkill del 'for k in $kids; do kill -KILL "$k"'
run_mutant "AC6 wrapper kind's child KILL deleted" leg_wrapper_kill
mk_mutant preexec sub '_pr_pre_exec "$cmd" || { matched=1; break; }' '{ matched=1; break; }'
run_mutant "AC2 --expect exec-past-launcher check deleted" leg_expect
mk_mutant widen sub 'overdue|orphaned) _pr_stop "$f" ;;' 'overdue|orphaned|running) _pr_stop "$f" ;;'
run_mutant "AC6 reap filter widened to running" leg_apply_classes

echo
echo "test-proc-registry.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
