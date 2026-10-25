#!/usr/bin/env bash
# test-proc-registry.sh — self-tests for loomwright/scripts/proc-registry.sh (register / list / summary / reap).
# Isolated: every leg uses its own LOOMWRIGHT_PROC_REGISTRY_DIR under one mktemp -d, the SUT runs as a
# subprocess, and every fixture process is a background child of this shell, killed by the leg (and
# by the EXIT trap). The hermetic legs fake HOME and assert nothing lands under it.
#
#   AC1  register writes ONE <id>.json with every key (absent optionals null), built with jq --arg
#        (a purpose full of quotes / `$( )` survives verbatim and runs nothing); relative paths made
#        absolute; registering the same process twice keeps one entry; the same pid with a different
#        start time (a PATH-stub `ps`) is a NEW entry and the old file is byte-identical.
#   AC2  --expect waits for a not-yet-exec'd command line (the entry then classifies running), also past
#        a `nohup` / `env` launcher stage whose line already carries the substring, and past a forked
#        child that still shows its --owner-pid's line; a never-matching --expect still writes, prints
#        one stderr line, and is bounded (< 6 s).
#   AC3  fail-safe: unwritable dir, jq missing, dead pid, merge-watch without --max-lifetime, bad
#        arguments — exit 0, exactly one `register failed — <reason>` stderr line, nothing written.
#   AC4  list classifies running / overdue / orphaned (repo missing, ## Status: done, lane missing,
#        owner dead, owner recycled) / finished (pid gone, lstart differs, hash differs); overdue wins
#        over orphaned; exit 0; the registry is unchanged by list.
#   AC5  reap without --apply: every class present, no signal, registry checksum unchanged.
#   AC6  reap --apply: overdue + orphaned stopped and removed, finished pruned, running untouched, one
#        reap.log line per processed entry; a TERM-ignoring process is KILLed; a wrapper's TERM-ignoring
#        session is stopped through its OWN entry (orphaned once the same pass KILLed the wrapper; owned
#        entries are processed last), and an unregistered child of a registered wrapper is never
#        signalled; a process that execs a different command during the grace is NOT KILLed (the
#        re-check); named ids only; an unknown id is skipped; a malformed id is a usage error; reap.log
#        keeps its last 1000 lines.
#   AC7  a recycled pid (alive, different command line) is finished and survives reap --apply.
#   AC8  HERMETIC_TEST_ENV=1 redirects to $HERMETIC_SHIM_DIR/procs (nothing under a fake HOME); an empty
#        or missing HERMETIC_SHIM_DIR is unavailable (register fails safe, list/reap empty, no write
#        anywhere); outside hermetic mode the default is $HOME's user-scope registry.
#   AC9  the header names the contract; its caps table equals the code's (per-kind registration), the
#        LOOMWRIGHT_PROC_MAX_S_<KIND> overrides and --max-lifetime precedence work; its GRACE table equals
#        the code's (an owner-less wrapper-kind entry vs every other entry; --grace wins); exit codes.
#   AC10 summary prints exactly ONE `proc-registry: summary — <E> entries: …` line, exit 0, classifying
#        like list (one entry per class; a recycled pid — different command line or lstart — is
#        finished; the snapshot's lstart is read under the TZ pin, proven with a non-UTC TZ), with ONE
#        `ps` call (a PATH-stub counter: 3 or 4 entries ⇒ 1 call, 0 entries ⇒ 0 calls); empty / missing
#        registry ⇒ the zero line; unavailable (hermetic with no shim dir, an unreadable dir, a non-dir
#        path, a failing snapshot) ⇒ `proc-registry: summary — unavailable`, exit 0; a bad argument
#        exits 2; LOOMWRIGHT_PROC_PS_SNAPSHOT is read in place of ps.
#   AC11 summary --scan appends `; <u> unregistered` from the same snapshot fixture: checkout and
#        versioned-plugin-root look-alikes and a temp-dir python whose script is gone count; a
#        registered pid, a young one (LOOMWRIGHT_PROC_UNREG_MIN_S, default 3600), an existing or
#        non-temp script, `-m`, and non-plugin paths do not; the caller's ancestors are excluded but
#        their other children are not; the registry checksum is unchanged; under HERMETIC_TEST_ENV=1
#        without the snapshot seam the scan is skipped (0, no ps call) even with a live look-alike.
#   leg_list_scan  list --scan prints, after the registry rows (classified from the SAME snapshot), one
#        `unreg-<pid> unregistered <pid> <age>s unregistered <rule>; lstart=…; cmd_hash=…` row per
#        look-alike — exactly the fixture's 3 (checkout, versioned root, gone temp python; registered,
#        its descendant, young and non-plugin excluded), equal to summary --scan's <u> — and one
#        `# scan: 3 unregistered` line; registry unchanged; `list` without --scan prints no scan row or
#        line and never reads the snapshot; the hermetic skip and an unreadable snapshot print
#        `# scan: skipped|unavailable — …`; an extra argument is warned about and ignored.
#   leg_stop_unreg  stop-unregistered with a live list --scan row's lstart + hash: the dry run signals
#        and writes nothing; a live registry entry's pid (lstart + hash match) and a look-alike child of
#        a live entry are refused with ONE `not signalled: <reason>` line and stay alive; the hermetic
#        skip refuses; --apply stops the look-alike and appends one reap.log line per --apply call; a
#        gone pid is refused; bad arguments exit 2.
#   leg_stop_unreg_recycled  a look-alike that execs into a DIFFERENT command line that still
#        satisfies the predicate (list --scan still lists it) is not signalled — only the lstart/hash
#        re-check can refuse it.
#   leg_stop_unreg_nonlookalike  an unregistered pid whose lstart + hash match but that fails the scan
#        predicate (a plain sleep) is not signalled.
#   MUTATION CONTROLS (each mutant gated per lesson fa32a308: non-empty, byte-differs, parses, and a
#   line-delete removes exactly one line), each must turn its leg red: the cmd-hash comparison
#   deleted (AC7), the --apply gate deleted (AC5), the ## Status read deleted (AC4), the age compare
#   flipped (AC4), the hermetic branch deleted (AC8), the HERMETIC_SHIM_DIR check deleted (AC8), the id
#   from the pid alone (AC1), register's failure path exiting 1 (AC3), the re-check before KILL
#   deleted (AC6), the reap filter widened to running (AC6), a ppid KILL of the wrapper's children
#   re-added (AC6), the owned-entries-last ordering deleted (AC6), the --expect launcher-stage check
#   deleted (AC2), the --expect owner-line check deleted (AC2), the GRACE table's WRAPPER row deleted
#   (AC9); summary's snapshot lstart lookup replaced by a live ps per entry (AC10), the cmd-hash
#   comparison deleted against summary (AC10), the snapshot's TZ pin dropped (AC10), the unavailable
#   line silenced (AC10), the --scan age comparison made never-true (AC11), the registered-pid
#   exclusion deleted (AC11), summary touching a registry file (AC11), the ancestor walk deleted
#   (AC11), the gone-script check deleted (AC11), the hermetic scan skip deleted (AC11); list --scan's
#   own row print deleted (leg_list_scan), stop-unregistered's pre-TERM identity re-check deleted
#   (leg_stop_unreg_recycled), its live-entry refusal deleted (leg_stop_unreg), its scan-predicate
#   refusal deleted (leg_stop_unreg_nonlookalike).
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
  check "AC1 kind / table cap / table grace (an owner-less lane entry is a wrapper: the WRAPPER grace)" eq "$(jq -c '[.kind, .max_lifetime_s, .grace_s]' "$f")" '["lane",86400,120]'
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
  # a forked child that has not exec'd yet shows its parent's line, which (the -c text) already carries the
  # substring: with --owner-pid = that parent, register waits for the exec
  ready_fixture '( sleep 1.5; exec sleep 3006 ) & echo "$!" > "$1.c"; : > "$1"; wait'; local o=$SP
  p="$(cat "$WORK"/ready.*.c 2>/dev/null | head -1)"; rm -f "$WORK"/ready.*.c
  [ -n "$p" ] && { env TZ=UTC0 LC_ALL=C ps -o lstart= -p "$p" > "$FIXDIR/$p" 2>/dev/null; LEG_PIDS="$LEG_PIDS $p"; }
  reg --pid "$p" --kind lane --purpose forked --owner-pid "$o" --expect 'sleep 3006' 2>"$ERR"
  WAIT_LIB_WHAT="pid $p to exec sleep 3006" wait_for_cmd 10 cmd_is "$p" 'sleep 3006'
  check "AC2 --expect waits past a forked child still showing its --owner-pid's line" eval '[ -n "$p" ] && [ -z "$(cat "$ERR")" ] && is_class "$p" running'
  fix_kill "$p"; rm -f "$(efile "$p")"
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
# lives) whose child IGNORES TERM — so the wrapper outlives its TERM and is KILLed, and the child can only be
# reached through an entry of its own
WRAP_FIXTURE='bash -c "trap \"\" TERM; while :; do sleep 0.1; done" & c=$!; trap "kill -TERM $c 2>/dev/null" TERM; : > "$1"; while kill -0 "$c" 2>/dev/null; do wait "$c"; done'
# wrap_fixture — spawn WRAP_FIXTURE and track its child (sets WP, WC)
wrap_fixture() {
  ready_fixture "$WRAP_FIXTURE"; WP=$SP
  WAIT_LIB_WHAT="wrapper $WP to start its child" wait_for_cmd 5 eval '[ -n "$(child_of "$WP")" ]'
  WC="$(child_of "$WP")"; [ -n "$WC" ] && { env TZ=UTC0 LC_ALL=C ps -o lstart= -p "$WC" > "$FIXDIR/$WC" 2>/dev/null; LEG_PIDS="$LEG_PIDS $WC"; }
}
leg_session_entry() {
  local out idc
  new_reg
  wrap_fixture
  reg --pid "$WP" --kind lane --purpose wrapper --max-lifetime 1 --grace 1 2>/dev/null
  # the session's own entry: same kind, owner = the wrapper, NOT overdue — only orphaned can stop it
  reg --pid "$WC" --kind lane --purpose session --owner-pid "$WP" --max-lifetime 3600 --grace 1 --expect 'trap "" TERM' 2>/dev/null
  idc="$(eid "$WC")"
  wait_overdue "$WP"
  out="$(bash "$S" reap --apply 2>/dev/null)"
  WAIT_LIB_WHAT="wrapper $WP and session $WC to be gone" wait_for_cmd 10 eval 'gone "$WP" && gone "$WC"'
  check "AC6 a wrapper's TERM-ignoring session is stopped in the same pass, through its own entry (orphaned)" \
    eval '[ -n "$WC" ] && gone "$WC" && gone "$WP" && has "$out" "orphaned $idc (lane, pid $WC): stopped (TERM+KILL)"'
  check "AC6 ... both entries removed" eq "$(njson)" 0
  leg_end
}
leg_no_ppid_signal() {
  new_reg
  wrap_fixture
  # only the wrapper is registered: its child is NOT in the registry and must never be signalled
  reg --pid "$WP" --kind lane --purpose wrapper --max-lifetime 1 --grace 1 2>/dev/null
  wait_overdue "$WP"
  bash "$S" reap --apply >/dev/null 2>&1
  WAIT_LIB_WHAT="wrapper $WP to be gone" wait_for_cmd 10 gone "$WP"
  check "AC6 reap never signals an unregistered child of a registered wrapper" eval '[ -n "$WC" ] && gone "$WP" && alive "$WC"'
  leg_end
}
# owned entries are processed after the rest, whatever their file order (ids renamed so the owned one sorts first)
leg_owned_last() {
  local out
  new_reg
  sleeper; local w=$SP; sleeper; local c=$SP
  reg --pid "$w" --kind lane --purpose plain 2>/dev/null
  reg --pid "$c" --kind lane --purpose owned --owner-pid "$w" 2>/dev/null
  mv "$(efile "$c")" "$R/1-owned.json"; mv "$(efile "$w")" "$R/9-plain.json"
  out="$(bash "$S" reap 2>/dev/null)"
  check "AC6 reap processes an entry with an owner_pid after the rest" eq "$(awk '/^keep / { printf "%s ", $2 }' <<<"$out")" "9-plain 1-owned "
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
           LOOMWRIGHT_PROC_MAX_S_POSTMORTEM "NEVER SIGNAL BY PID ALONE" "EXIT CODES" "CLASSES" "CAPS" "GRACE" "precedence" \
           "summary [--scan]" "proc-registry: summary — <E> entries: <r> running, <o> overdue, <a> orphaned, <f> finished" \
           "$U" "; <u> unregistered" LOOMWRIGHT_PROC_PS_SNAPSHOT LOOMWRIGHT_PROC_UNREG_MIN_S "HERMETIC SCAN SKIP" \
           "summary 0 (usage error 2)" "list [--scan]" "# scan: <u> unregistered" \
           "stop-unregistered --pid <p> --start <lstart> --hash <cmd_hash> [--apply]" "not signalled: <reason>" \
           "stop-unregistered 0, a refusal too (usage error 2)"; do
    has "$hdr" "$k" || { check "AC9 header names '$k'" false; }
  done
  check "AC9 header names every subcommand, key, class, cap override, location and exit code" true
  check "AC10 the usage text lists summary" has "$(bash "$S" help)" "proc-registry.sh summary [--scan]"
  check "leg_header the usage text lists list --scan and stop-unregistered" eval 'has "$(bash "$S" help)" "proc-registry.sh list [--scan]" && has "$(bash "$S" help)" "proc-registry.sh stop-unregistered --pid <p> --start <lstart> --hash <cmd_hash> [--apply]"'
  new_reg
  for k in phase lane drain postmortem; do
    sleeper; p=$SP
    reg --pid "$p" --kind "$k" --purpose cap 2>/dev/null
    n="$(efield "$p" max_lifetime_s)"
    check "AC9 the header's caps row for $k equals the code's default ($n)" eval 'grep -Eq "^#   $k +$n " <<<"$hdr"'
  done
  # the GRACE table: an owner-less wrapper-kind entry gets the header's WRAPPER row, every other entry (a session,
  # postmortem, merge-watch) the "every other" row; --grace always wins
  local gw go owner
  gw="$(sed -n 's/^#   WRAPPER  *\([0-9][0-9]*\) .*/\1/p' <<<"$hdr")"
  go="$(sed -n 's/^#   every other  *\([0-9][0-9]*\) .*/\1/p' <<<"$hdr")"
  sleeper; owner=$SP
  for k in phase lane drain; do
    sleeper; p=$SP
    reg --pid "$p" --kind "$k" --purpose grace 2>/dev/null
    check "AC9 the header's WRAPPER grace row ($gw) is the code's default for an owner-less $k entry" eq "$gw|$(efield "$p" grace_s)" "120|120"
    sleeper; p=$SP
    reg --pid "$p" --kind "$k" --purpose grace --owner-pid "$owner" 2>/dev/null
    check "AC9 the header's every-other grace row ($go) is the code's default for a $k session (owner set)" eq "$go|$(efield "$p" grace_s)" "10|10"
  done
  sleeper; p=$SP
  reg --pid "$p" --kind postmortem --purpose grace 2>/dev/null
  check "AC9 a postmortem entry takes the every-other grace" eq "$(efield "$p" grace_s)" "$go"
  sleeper; p=$SP
  reg --pid "$p" --kind merge-watch --purpose grace --max-lifetime 60 2>/dev/null
  check "AC9 a merge-watch entry takes the every-other grace" eq "$(efield "$p" grace_s)" "$go"
  sleeper; p=$SP
  reg --pid "$p" --kind drain --purpose grace --grace 4 2>/dev/null
  check "AC9 --grace beats the GRACE table" eq "$(efield "$p" grace_s)" 4
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

# ==== AC10 / AC11 — summary [--scan] ===================================================================
# CNTBIN: a PATH-stub `ps` that appends one line to $PS_COUNT per call, then runs the real ps
CNTBIN="$WORK/cntbin"; mkdir -p "$CNTBIN"
printf '#!/bin/sh\necho call >> "${PS_COUNT:?}"\nexec %s "$@"\n' "$(command -v ps)" > "$CNTBIN/ps"
chmod +x "$CNTBIN/ps"
PS_COUNT="$WORK/ps-count"
Z="proc-registry: summary — 0 entries: 0 running, 0 overdue, 0 orphaned, 0 finished"
U="proc-registry: summary — unavailable"
# summ [args] — summary through the counting stub, under a non-UTC TZ (XST5: no tzdata needed), with the
# optional seams SUM_SNAP (LOOMWRIGHT_PROC_PS_SNAPSHOT) and SUM_MIN (LOOMWRIGHT_PROC_UNREG_MIN_S); sets
# SUM (stdout), SUM_RC, SUM_PS (ps calls)
summ() {
  : > "$PS_COUNT"
  SUM="$(PATH="$CNTBIN:$PATH" PS_COUNT="$PS_COUNT" TZ=XST5 LOOMWRIGHT_PROC_PS_SNAPSHOT="${SUM_SNAP:-}" \
         LOOMWRIGHT_PROC_UNREG_MIN_S="${SUM_MIN:-}" bash "$S" summary "$@" 2>"$ERR")"; SUM_RC=$?
  SUM_PS="$(lines "$PS_COUNT")"
}
sline() { printf 'proc-registry: summary — %s entries: %s running, %s overdue, %s orphaned, %s finished' "$@"; }
list_counts() { bash "$S" list 2>/dev/null | awk -F'\t' '!/^#/ && NF == 6 { c[$5]++ } END { printf "%d %d %d %d", c["running"], c["overdue"], c["orphaned"], c["finished"] }'; }
trimmed() { sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }
etime_pos() { [ -n "$(ps -o etime= -p "$1" 2>/dev/null | tr -d ' :0-')" ]; }

leg_summary_classes() {
  local before
  SUM_SNAP=""; SUM_MIN=""
  classes_fixture
  before="$(dirsum)"
  summ
  check "AC10 summary: one line, one entry per class, exit 0" eq "$SUM_RC|$SUM" "0|$(sline 4 1 1 1 1)"
  check "AC10 ... from ONE ps call for 4 entries" eq "$SUM_PS" 1
  check "AC10 ... the same classes list prints" eq "$(list_counts)" "1 1 1 1"
  check "AC10 ... read-only: registry unchanged, nothing signalled" eval '[ "$(dirsum)" = "$before" ] && alive "$C_RUN" && alive "$C_OVER" && alive "$C_ORPH"'
  summ --scan
  check "AC11 --scan under HERMETIC_TEST_ENV=1 without the seam: classification runs, the scan is skipped" eq "$SUM_RC|$SUM|$SUM_PS" "0|$(sline 4 1 1 1 1); 0 unregistered|1"
  leg_end
}

leg_summary_recycled() {
  local p1 p2 p3
  SUM_SNAP=""; SUM_MIN=""
  new_reg
  sleeper; p1=$SP; reg --pid "$p1" --kind lane --purpose live --max-lifetime 3600 2>/dev/null
  ready_fixture 'trap "exec sleep 3009" USR1; : > "$1"; while :; do sleep 0.1; done'; p2=$SP
  reg --pid "$p2" --kind lane --purpose recycled-cmd --max-lifetime 3600 2>/dev/null
  kill -USR1 "$p2"
  WAIT_LIB_WHAT="pid $p2 to run a different command line" wait_for_cmd 5 cmd_is "$p2" 'sleep 3009'
  sleeper; p3=$SP; reg --pid "$p3" --kind lane --purpose recycled-lstart --max-lifetime 3600 2>/dev/null
  forge "$p3" pid_start "Mon Jan  1 00:00:00 2001"
  summ
  check "AC10 a recycled pid (command line or lstart differs) is finished; the live one running (non-UTC TZ)" eq "$SUM_RC|$SUM" "0|$(sline 3 1 0 0 2)"
  check "AC10 ... 3 entries cost ONE ps call" eq "$SUM_PS" 1
  check "AC10 ... and summary never signalled the recycled pid" alive "$p2"
  leg_end
}

leg_summary_zero() {
  local out rc p
  SUM_SNAP=""; SUM_MIN=""
  new_reg
  summ
  check "AC10 an empty registry prints the zero line, exit 0, with NO ps call" eq "$SUM_RC|$SUM|$SUM_PS" "0|$Z|0"
  export LOOMWRIGHT_PROC_REGISTRY_DIR="$WORK/missing-reg-$RANDOM"
  summ
  check "AC10 a missing registry prints the zero line, NO ps call, and creates nothing" eval '[ "$SUM_RC|$SUM|$SUM_PS" = "0|$Z|0" ] && [ ! -e "$LOOMWRIGHT_PROC_REGISTRY_DIR" ]'
  out="$(unset LOOMWRIGHT_PROC_REGISTRY_DIR; export HERMETIC_TEST_ENV=1 HERMETIC_SHIM_DIR=""; bash "$S" summary; echo "rc=$?"; bash "$S" summary --scan; echo "rc=$?")"
  check "AC10 hermetic with no shim dir: '$U', exit 0 (with and without --scan)" eq "$out" "$U
rc=0
$U
rc=0"
  : > "$WORK/reg-is-a-file"
  export LOOMWRIGHT_PROC_REGISTRY_DIR="$WORK/reg-is-a-file"
  summ
  check "AC10 a registry path that is not a directory is unavailable" eq "$SUM_RC|$SUM" "0|$U"
  new_reg
  sleeper; p=$SP; reg --pid "$p" --kind lane --purpose x 2>/dev/null
  if [ "$(id -u)" != 0 ]; then
    chmod 000 "$R"; summ; chmod 755 "$R"
    check "AC10 an unreadable registry dir is unavailable, exit 0" eq "$SUM_RC|$SUM" "0|$U"
  else
    [ "$QUIET" = 1 ] || echo "  skip: AC10 unreadable dir (running as root)"
  fi
  SUM_SNAP="$WORK/no-such-snapshot"; summ; SUM_SNAP=""
  check "AC10 a snapshot that cannot be read is unavailable (never a guess)" eq "$SUM_RC|$SUM" "0|$U"
  : > "$WORK/empty-snapshot"; SUM_SNAP="$WORK/empty-snapshot"; summ; SUM_SNAP=""
  check "AC10 an empty snapshot is unavailable" eq "$SUM_RC|$SUM" "0|$U"
  out="$(bash "$S" summary --bogus 2>/dev/null)"; rc=$?
  check "AC10 an unknown summary argument is a usage error (exit 2, no line)" eq "$rc|$out" "2|"
  leg_end
}

leg_summary_seam() {
  local p snap
  SUM_SNAP=""; SUM_MIN=""
  new_reg
  sleeper; p=$SP; reg --pid "$p" --kind lane --purpose seam --max-lifetime 3600 2>/dev/null
  snap="$WORK/seam-snap.$RANDOM"
  env TZ=UTC0 LC_ALL=C ps -A -ww -o pid=,ppid=,lstart=,etime=,command= > "$snap"
  kill_gone "$p"
  SUM_SNAP="$snap"; summ; SUM_SNAP=""
  check "AC10 LOOMWRIGHT_PROC_PS_SNAPSHOT replaces ps: the snapshot's (now dead) process reads running, 0 ps calls" eq "$SUM|$SUM_PS" "$(sline 1 1 0 0 0)|0"
  summ
  check "AC10 (control) without the seam the dead process reads finished (1 ps call)" eq "$SUM|$SUM_PS" "$(sline 1 0 0 0 1)|1"
  leg_end
}

leg_summary_scan() {
  local la lst lcmd fx gone exists before L="Mon Jan  1 00:00:00 2001" one
  SUM_SNAP=""; SUM_MIN=""
  new_reg
  # a live look-alike, registered (its snapshot row is a registered pid); argv[0] carries the plugin path
  spawn bash -c 'exec -a "$0" sleep 3010' /opt/lw-fixture/loomwright/scripts/registered.sh; la=$SP
  WAIT_LIB_WHAT="pid $la to exec its look-alike line" wait_for_cmd 5 cmd_is "$la" '/opt/lw-fixture/loomwright/scripts/registered.sh 3010'
  reg --pid "$la" --kind lane --purpose lookalike --max-lifetime 999999 2>/dev/null
  lst="$(env TZ=UTC0 LC_ALL=C ps -o lstart= -p "$la" | trimmed)"
  lcmd="$(env LC_ALL=C ps -ww -o command= -p "$la" | trimmed)"
  gone="$WORK/gone-$RANDOM/verify-fixture-app.py"
  exists="$WORK/exists-$RANDOM.py"; : > "$exists"
  fx="$WORK/scan-snap.$RANDOM"
  {
    printf '%s 1 %s 3-00:00:00 %s\n' "$la" "$lst" "$lcmd"                                   # registered: no
    printf '900001 1 %s 3-00:00:00 %s\n' "$lst" "$lcmd"                                       # same line, unregistered pid: YES
    printf '900002 1 %s 2-00:00:00 bash /opt/lw/loomwright/scripts/merge-watch.sh --pr 7\n' "$L"  # checkout path: YES
    printf '900003 1 %s 1-02:03:04 bash /opt/cache/atelier/loomwright/17.13.0/scripts/stray-watch.sh\n' "$L"  # versioned root: YES
    printf '900004 1 %s 05:00 bash /opt/lw/loomwright/scripts/young.sh\n' "$L"               # 300 s: no (default 3600)
    printf '900005 1 %s 1-00:00:00 python3 -u %s --port 5555\n' "$L" "$gone"                 # temp dir, script gone: YES
    printf '900006 1 %s 1-00:00:00 python3 %s --port 5556\n' "$L" "$exists"                  # script exists: no
    printf '900007 1 %s 1-00:00:00 python3 /opt/no-such-dir/app.py\n' "$L"                    # not a temp dir: no
    printf '900008 1 %s 1-00:00:00 python3 -m http.server 8000\n' "$L"                        # -m, no script: no
    printf '900009 1 %s 1-00:00:00 bash /opt/notloomwright/scripts/x.sh\n' "$L"               # not the plugin: no
    printf '900010 1 %s 1-00:00:00 bash /opt/loomwright/a/b/scripts/x.sh\n' "$L"              # two segments: no
    printf '900011 %s %s 1-00:00:00 bash /opt/lw/loomwright/scripts/registered-child.sh\n' "$la" "$L"   # child of a registered pid: no
    printf '900012 900011 %s 1-00:00:00 bash /opt/lw/loomwright/scripts/registered-grandchild.sh\n' "$L"  # its grandchild: no
    printf '900013 900001 %s 1-00:00:00 bash /opt/lw/loomwright/scripts/unregistered-child.sh\n' "$L"     # child of an UNregistered pid: YES
  } > "$fx"
  one="$(sline 1 1 0 0 0)"
  before="$(dirsum)"
  SUM_SNAP="$fx"; summ --scan
  check "AC11 --scan counts the 5 unregistered look-alikes (registered, its descendants, young, existing, non-temp, -m, non-plugin excluded)" eq "$SUM_RC|$SUM" "0|$one; 5 unregistered"
  check "AC11 ... reads only the snapshot (0 ps calls), writes nothing in the registry, signals nothing" eval '[ "$SUM_PS" = 0 ] && [ "$(dirsum)" = "$before" ] && alive "$la"'
  summ
  check "AC11 without --scan the line has no unregistered part" eq "$SUM" "$one"
  SUM_MIN=100; summ --scan
  check "AC11 LOOMWRIGHT_PROC_UNREG_MIN_S=100 also counts the 300 s look-alike" eq "$SUM" "$one; 6 unregistered"
  SUM_MIN=abc; summ --scan
  check "AC11 a non-numeric LOOMWRIGHT_PROC_UNREG_MIN_S falls back to the 3600 s default" eq "$SUM" "$one; 5 unregistered"
  SUM_MIN=""; SUM_SNAP=""
  # the caller and its parent (an ancestor chain in the snapshot) are excluded; the caller's OTHER child is not
  cat > "$WORK/anc.sh" <<'ANC'
p=$$
cp "$1" "$2"
printf '%s 900100 Mon Jan  1 00:00:00 2001 3-00:00:00 bash /opt/lw/loomwright/scripts/caller.sh\n' "$p" >> "$2"
printf '900100 900101 Mon Jan  1 00:00:00 2001 3-00:00:00 bash /opt/lw/loomwright/scripts/grandcaller.sh\n' >> "$2"
printf '900102 %s Mon Jan  1 00:00:00 2001 3-00:00:00 bash /opt/lw/loomwright/scripts/sibling.sh\n' "$p" >> "$2"
LOOMWRIGHT_PROC_PS_SNAPSHOT="$2" TZ=XST5 bash "$3" summary --scan
rc=$?
exit "$rc"
ANC
  check "AC11 the caller's ancestors are excluded, their other children are not (5 + the sibling)" eq "$(bash "$WORK/anc.sh" "$fx" "$fx.anc" "$S" 2>/dev/null)" "$one; 6 unregistered"
  check "AC11 ... and the registry is still unchanged" eq "$(dirsum)" "$before"
  leg_end
}

leg_summary_hermetic() {
  local sh la out
  sh="$(mktemp -d "$WORK/shim.XXXXXX")"
  # a LIVE look-alike older than the threshold (0 here): a live scan would count it
  spawn bash -c 'exec -a "$0" sleep 3011' /opt/lw-fixture/loomwright/scripts/live-lookalike.sh; la=$SP
  WAIT_LIB_WHAT="pid $la to age past 0 s" wait_for_cmd 10 etime_pos "$la"
  : > "$PS_COUNT"
  out="$(unset LOOMWRIGHT_PROC_REGISTRY_DIR LOOMWRIGHT_PROC_PS_SNAPSHOT; export HERMETIC_TEST_ENV=1 HERMETIC_SHIM_DIR="$sh" LOOMWRIGHT_PROC_UNREG_MIN_S=0 PS_COUNT
         PATH="$CNTBIN:$PATH" bash "$S" summary --scan 2>/dev/null)"
  check "AC11 HERMETIC_TEST_ENV=1 without LOOMWRIGHT_PROC_PS_SNAPSHOT: the scan is skipped (0 unregistered, no ps call)" eq "$out|$(lines "$PS_COUNT")" "$Z; 0 unregistered|0"
  printf '900200 1 Mon Jan  1 00:00:00 2001 3-00:00:00 bash /opt/lw/loomwright/scripts/x.sh\n' > "$WORK/herm-snap"
  out="$(unset LOOMWRIGHT_PROC_REGISTRY_DIR; export HERMETIC_TEST_ENV=1 HERMETIC_SHIM_DIR="$sh" LOOMWRIGHT_PROC_PS_SNAPSHOT="$WORK/herm-snap"
         bash "$S" summary --scan 2>/dev/null)"
  check "AC11 (control) hermetic WITH the snapshot seam: the scan runs" eq "$out" "$Z; 1 unregistered"
  check "AC11 ... and the hermetic summary created nothing in the shim dir" eq "$(find "$sh" -mindepth 1 | wc -l | tr -d ' ')" 0
  leg_end
}

# ==== list --scan / stop-unregistered ==================================================================
# thash <string> — the SUT's `<algo>:<hash>` of a command line (shasum → sha1sum → cksum)
thash() {
  if command -v shasum >/dev/null 2>&1; then printf 'sha1:%s' "$(printf '%s' "$1" | shasum | cut -d' ' -f1)"
  elif command -v sha1sum >/dev/null 2>&1; then printf 'sha1:%s' "$(printf '%s' "$1" | sha1sum | cut -d' ' -f1)"
  else printf 'cksum:%s' "$(printf '%s' "$1" | cksum | cut -d' ' -f1)"; fi
}
lstart_of() { env TZ=UTC0 LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | trimmed; }
cmd_of() { env LC_ALL=C ps -ww -o command= -p "$1" 2>/dev/null | trimmed; }
LIVE_SNAP="$WORK/live-snap"
live_snap() { env TZ=UTC0 LC_ALL=C ps -A -ww -o pid=,ppid=,lstart=,etime=,command= > "$LIVE_SNAP"; }
# scan_row <pid> — <pid>'s `list --scan` row over a fresh live snapshot (threshold 0 s); empty when not listed
scan_row() {
  live_snap
  LOOMWRIGHT_PROC_PS_SNAPSHOT="$LIVE_SNAP" LOOMWRIGHT_PROC_UNREG_MIN_S=0 bash "$S" list --scan 2>/dev/null \
    | awk -F'\t' -v p="$1" '$2 == "unregistered" && $3 == p'
}
row_lstart() { sed -n 's/.*; lstart=\(.*\); cmd_hash=.*/\1/p' <<<"$1"; }
row_hash() { sed -n 's/.*; cmd_hash=//p' <<<"$1"; }
# su_run [args] — stop-unregistered over a fresh live snapshot (threshold 0 s); sets SU (stdout) and SU_RC
su_run() {
  live_snap
  SU="$(LOOMWRIGHT_PROC_PS_SNAPSHOT="$LIVE_SNAP" LOOMWRIGHT_PROC_UNREG_MIN_S=0 bash "$S" stop-unregistered "$@" 2>"$ERR")"; SU_RC=$?
}
one_line() { [ "$(printf '%s\n' "$1" | awk 'END { print NR }')" = 1 ]; }
# lookalike <name> <n> — spawn `sleep <n>` whose argv[0] is a plugin script path, aged past 0 s (sets SP)
LW="$WORK/lw/loomwright/scripts"
lookalike() {
  spawn bash -c 'exec -a "$0" sleep "$1"' "$LW/$1" "$2"
  WAIT_LIB_WHAT="pid $SP to exec its look-alike line" wait_for_cmd 5 cmd_is "$SP" "$LW/$1 $2"
  WAIT_LIB_WHAT="pid $SP to age past 0 s" wait_for_cmd 10 etime_pos "$SP"
}

leg_list_scan() {
  local la lst lcmd fx gone out rc before nrows u L="Mon Jan  1 00:00:00 2001" c1 c3
  new_reg
  spawn bash -c 'exec -a "$0" sleep 3020' /opt/lw-fixture/loomwright/scripts/registered.sh; la=$SP
  WAIT_LIB_WHAT="pid $la to exec its look-alike line" wait_for_cmd 5 cmd_is "$la" '/opt/lw-fixture/loomwright/scripts/registered.sh 3020'
  reg --pid "$la" --kind lane --purpose lookalike --max-lifetime 999999 2>/dev/null
  lst="$(lstart_of "$la")"; lcmd="$(cmd_of "$la")"
  gone="$WORK/gone-$RANDOM/fixture-app.py"
  c1="bash /opt/lw/loomwright/scripts/merge-watch.sh --pr 7"
  c3="python3 -u $gone --port 5555"
  fx="$WORK/list-snap.$RANDOM"
  {
    printf '%s 1 %s 3-00:00:00 %s\n' "$la" "$lst" "$lcmd"                                     # registered: no
    printf '900301 1 %s 3-00:00:00 %s\n' "$L" "$c1"                                            # checkout path: YES
    printf '900302 1 %s 1-02:03:04 bash /opt/cache/atelier/loomwright/17.13.0/scripts/stray-watch.sh\n' "$L"  # versioned root: YES
    printf '900303 1 %s 1-00:00:00 %s\n' "$L" "$c3"                                            # temp python, script gone: YES
    printf '900304 1 %s 05:00 bash /opt/lw/loomwright/scripts/young.sh\n' "$L"                 # 300 s: no
    printf '900305 %s %s 1-00:00:00 bash /opt/lw/loomwright/scripts/child.sh\n' "$la" "$L"     # child of a registered pid: no
    printf '900306 1 %s 1-00:00:00 bash /opt/notloomwright/scripts/x.sh\n' "$L"                # not the plugin: no
  } > "$fx"
  before="$(dirsum)"
  out="$(LOOMWRIGHT_PROC_PS_SNAPSHOT="$fx" bash "$S" list --scan 2>"$ERR")"; rc=$?
  nrows="$(awk -F'\t' '$2 == "unregistered" { n++ } END { print n + 0 }' <<<"$out")"
  check "leg_list_scan list --scan exits 0 with exactly the fixture's 3 unregistered rows" eq "$rc|$nrows" "0|3"
  u="$(LOOMWRIGHT_PROC_PS_SNAPSHOT="$fx" bash "$S" summary --scan 2>/dev/null | sed -n 's/.*; \([0-9][0-9]*\) unregistered$/\1/p')"
  check "leg_list_scan ... the row count equals summary --scan's <u> on the same snapshot" eq "$nrows" "$u"
  check "leg_list_scan ... every unregistered row is unreg-<pid>/unregistered/<pid>/<age>/unregistered/<evidence>" \
    eq "$(awk -F'\t' '$2 == "unregistered" && !(NF == 6 && $1 == "unreg-" $3 && $5 == "unregistered" && $4 ~ /^[0-9]+s$/) { bad++ } END { print bad + 0 }' <<<"$out")" 0
  check "leg_list_scan ... the checkout row names its rule, the snapshot's lstart and the command-line hash" \
    has "$out" "$(printf 'unreg-900301\tunregistered\t900301\t259200s\tunregistered\tplugin script path /opt/lw/loomwright/scripts/merge-watch.sh; lstart=%s; cmd_hash=%s' "$L" "$(thash "$c1")")"
  check "leg_list_scan ... the versioned-root row names its script" \
    has "$out" "$(printf 'unreg-900302\tunregistered\t900302\t93784s\tunregistered\tplugin script path /opt/cache/atelier/loomwright/17.13.0/scripts/stray-watch.sh; lstart=')"
  check "leg_list_scan ... the python row names the gone temp script" \
    has "$out" "$(printf '\tunregistered\tgone temp python script %s; lstart=%s; cmd_hash=%s' "$gone" "$L" "$(thash "$c3")")"
  check "leg_list_scan ... the registry rows come first, classified from the SAME snapshot (the registered look-alike reads 259200s, not unregistered)" \
    eq "$(awk -F'\t' -v p="$la" '!/^#/ { k++ } $3 == p { print k ":" $2 ":" $4 ":" $5 }' <<<"$out")" "1:lane:259200s:running"
  check "leg_list_scan ... then ONE '# scan: 3 unregistered' line, last" eq "$(grep -c '^# scan:' <<<"$out")|$(tail -n 1 <<<"$out")" "1|# scan: 3 unregistered"
  check "leg_list_scan ... read-only: registry unchanged, nothing signalled" eval '[ "$(dirsum)" = "$before" ] && alive "$la"'
  out="$(LOOMWRIGHT_PROC_PS_SNAPSHOT="$fx" bash "$S" list 2>/dev/null)"
  check "leg_list_scan list without --scan: no scan row or line, one row per entry, the snapshot never read (live age)" \
    eval '! has "$out" unregistered && ! has "$out" "# scan:" && [ "$(grep -vc "^#" <<<"$out")" = 1 ] && ! has "$out" 259200s'
  out="$(LOOMWRIGHT_PROC_UNREG_MIN_S=0 bash "$S" list --scan 2>/dev/null)"
  check "leg_list_scan HERMETIC_TEST_ENV=1 without the seam: '# scan: skipped — …', no unregistered row, the registry row still prints" \
    eval 'has "$out" "# scan: skipped — " && ! has "$out" "$(printf "\tunregistered\t")" && has "$out" "$(printf "\t%s\t" "$la")"'
  out="$(LOOMWRIGHT_PROC_PS_SNAPSHOT="$WORK/no-such-snap" bash "$S" list --scan 2>/dev/null)"; rc=$?
  check "leg_list_scan an unreadable snapshot: '# scan: unavailable — …', exit 0" eval '[ "$rc" = 0 ] && has "$out" "# scan: unavailable — "'
  out="$(LOOMWRIGHT_PROC_PS_SNAPSHOT="$fx" bash "$S" list --scan bogus 2>"$ERR")"; rc=$?
  check "leg_list_scan an extra argument is warned about and ignored (the scan still runs)" \
    eval '[ "$rc" = 0 ] && [ "$(cat "$ERR")" = "proc-registry: list takes no arguments (ignored: bogus)" ] && has "$out" "# scan: 3 unregistered"'
  leg_end
}

leg_stop_unreg() {
  local a b w c row ls h before n0 rc out
  new_reg
  lookalike stray.sh 3021; a=$SP
  row="$(scan_row "$a")"; ls="$(row_lstart "$row")"; h="$(row_hash "$row")"
  check "leg_stop_unreg list --scan lists the live look-alike with its live lstart and command-line hash" \
    eq "$ls|$h" "$(lstart_of "$a")|$(thash "$LW/stray.sh 3021")"
  before="$(dirsum)"
  su_run --pid "$a" --start "$ls" --hash "$h"
  check "leg_stop_unreg without --apply: exit 0, says what it would do, no signal, nothing written" \
    eval '[ "$SU_RC" = 0 ] && has "$SU" "would stop unreg-$a (pid $a, unregistered)" && alive "$a" && [ "$(dirsum)" = "$before" ]'
  out="$(bash "$S" stop-unregistered --apply --pid "$a" --start "$ls" --hash "$h" 2>/dev/null)"; rc=$?
  check "leg_stop_unreg HERMETIC_TEST_ENV=1 without the seam: refused (one 'not signalled: skipped — …' line), alive" \
    eval '[ "$rc" = 0 ] && one_line "$out" && has "$out" "not signalled: skipped — " && alive "$a"'
  # a live registry entry (itself a look-alike) whose lstart + hash match
  lookalike registered.sh 3022; b=$SP
  reg --pid "$b" --kind lane --purpose live --max-lifetime 999999 2>/dev/null
  n0="$(lines "$R/reap.log" 2>/dev/null)"
  su_run --apply --pid "$b" --start "$(efield "$b" pid_start)" --hash "$(efield "$b" cmd_hash)"
  check "leg_stop_unreg a live registry entry's pid (lstart + hash match) is refused: ONE line naming the entry, exit 0, alive" \
    eq "$SU_RC|$SU|$(alive "$b" && echo alive)" "0|not signalled: pid $b is the live process of a registry entry|alive"
  check "leg_stop_unreg ... the --apply refusal appends one reap.log line" eq "$(lines "$R/reap.log")" "$(( ${n0:-0} + 1 ))"
  # a look-alike CHILD of a live entry (the wrapper W is registered; its child is not)
  ready_fixture "( exec -a '$LW/child.sh' sleep 3023 ) & echo \"\$!\" > \"\$1.c\"; : > \"\$1\"; wait"; w=$SP
  c="$(cat "$WORK"/ready.*.c 2>/dev/null | head -1)"; rm -f "$WORK"/ready.*.c
  [ -n "$c" ] && { env TZ=UTC0 LC_ALL=C ps -o lstart= -p "$c" > "$FIXDIR/$c" 2>/dev/null; LEG_PIDS="$LEG_PIDS $c"; }
  reg --pid "$w" --kind lane --purpose wrapper --max-lifetime 999999 2>/dev/null
  WAIT_LIB_WHAT="pid $c to exec its look-alike line" wait_for_cmd 5 cmd_is "$c" "$LW/child.sh 3023"
  WAIT_LIB_WHAT="pid $c to age past 0 s" wait_for_cmd 10 etime_pos "$c"
  su_run --apply --pid "$c" --start "$(lstart_of "$c")" --hash "$(thash "$LW/child.sh 3023")"
  check "leg_stop_unreg a look-alike descendant of a live entry is refused (fails the scan predicate), alive" \
    eval '[ -n "$c" ] && [ "$SU_RC" = 0 ] && one_line "$SU" && has "$SU" "not signalled: pid $c fails the scan predicate" && alive "$c"'
  # the matching unregistered look-alike, --apply
  n0="$(lines "$R/reap.log")"
  su_run --apply --pid "$a" --start "$ls" --hash "$h"
  WAIT_LIB_WHAT="pid $a to be reaped" wait_for_cmd 5 no_lstart "$a"
  check "leg_stop_unreg --apply stops the matching unregistered look-alike (TERM), exit 0" \
    eval '[ "$SU_RC" = 0 ] && one_line "$SU" && has "$SU" "unregistered unreg-$a (pid $a): stopped (TERM" && gone "$a"'
  check "leg_stop_unreg ... one reap.log line naming it" eval '[ "$(lines "$R/reap.log")" = "$((n0 + 1))" ] && tail -n 1 "$R/reap.log" | grep -qF "unreg-$a"'
  su_run --apply --pid "$a" --start "$ls" --hash "$h"
  check "leg_stop_unreg a gone pid is refused: 'not signalled: pid gone'" eq "$SU_RC|$SU" "0|not signalled: pid gone"
  check "leg_stop_unreg ... the other fixtures were never signalled" eval 'alive "$b" && alive "$c" && alive "$w"'
  # usage errors: exit 2, nothing signalled
  local bad=0 args
  for args in "--pid $b --start x" "--pid $b --hash y" "--start x --hash y" "--pid abc --start x --hash y" \
              "--pid 1 --start x --hash y" "--pid 0$b --start x --hash y" "--pid $b --start x --hash y --bogus" "--pid"; do
    # shellcheck disable=SC2086
    bash "$S" stop-unregistered --apply $args >/dev/null 2>&1; rc=$?
    [ "$rc" = 2 ] || { bad=1; [ "$QUIET" = 1 ] || echo "    usage case '$args' exited $rc"; }
  done
  bash "$S" stop-unregistered --apply --pid "$b" --start "$(printf 'x\ny')" --hash y >/dev/null 2>&1; rc=$?
  [ "$rc" = 2 ] || bad=1
  check "leg_stop_unreg a bad argument is a usage error (exit 2) and signals nothing" eval '[ "$bad" = 0 ] && alive "$b"'
  leg_end
}

leg_stop_unreg_recycled() {
  local p rf row ls h
  new_reg
  mkdir -p "$LW"
  # a look-alike that, on USR1, execs into a SECOND plugin-path command line: same pid + lstart, still a look-alike
  printf '%s\n' 'trap '"'"'exec -a "$2" sleep 3024'"'"' USR1' ': > "$1"' 'while :; do sleep 0.1; done' > "$LW/first.sh"
  rf="$WORK/ready.recycle.$RANDOM"
  spawn bash "$LW/first.sh" "$rf" "$LW/second.sh"; p=$SP
  WAIT_LIB_WHAT="fixture $p to install its trap" wait_for_cmd 5 test -f "$rf"
  WAIT_LIB_WHAT="pid $p to age past 0 s" wait_for_cmd 10 etime_pos "$p"
  row="$(scan_row "$p")"; ls="$(row_lstart "$row")"; h="$(row_hash "$row")"
  kill -USR1 "$p"
  WAIT_LIB_WHAT="pid $p to exec its second look-alike line" wait_for_cmd 5 cmd_is "$p" "$LW/second.sh 3024"
  check "leg_stop_unreg_recycled (control) before AND after the exec the pid is a listed look-alike" \
    eval '[ -n "$ls" ] && [ -n "$h" ] && [ -n "$(scan_row "$p")" ]'
  su_run --apply --pid "$p" --start "$ls" --hash "$h"
  check "leg_stop_unreg_recycled a pid recycled into another look-alike command line is not signalled (the hash re-check)" \
    eq "$SU_RC|$SU|$(alive "$p" && echo alive)" "0|not signalled: no longer matches (command line differs (pid recycled))|alive"
  leg_end
}

leg_stop_unreg_nonlookalike() {
  local p
  new_reg
  sleeper; p=$SP
  su_run --apply --pid "$p" --start "$(lstart_of "$p")" --hash "$(thash "$(cmd_of "$p")")"
  check "leg_stop_unreg_nonlookalike an unregistered pid with a matching lstart + hash that fails the scan predicate is refused, alive" \
    eval '[ "$SU_RC" = 0 ] && one_line "$SU" && has "$SU" "not signalled: pid $p fails the scan predicate" && alive "$p"'
  leg_end
}

# ==== run the legs against the real script =============================================================
echo "== proc-registry.sh =="
for leg in leg_keys leg_id leg_expect leg_failsafe leg_status_done leg_overdue_vs_running leg_classes \
           leg_dryrun leg_apply_classes leg_recheck_kill leg_session_entry leg_no_ppid_signal leg_owned_last leg_apply_more leg_recycled leg_hermetic \
           leg_hermetic_empty leg_default_location leg_header leg_summary_classes leg_summary_recycled leg_summary_zero \
           leg_summary_seam leg_summary_scan leg_summary_hermetic leg_list_scan leg_stop_unreg leg_stop_unreg_recycled \
           leg_stop_unreg_nonlookalike; do
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
mk_mutant ppidkill sub 'elif ! kill -KILL "$1" 2>/dev/null; then' 'elif ! { pkill -KILL -P "$1"; kill -KILL "$1"; } 2>/dev/null; then'
run_mutant "AC6 a ppid KILL of the wrapper's children re-added" leg_no_ppid_signal
mk_mutant ownedlast del '| _pr_owned_last)"'
run_mutant "AC6 owned-entries-last ordering deleted" leg_owned_last
mk_mutant ownerline sub '_pr_pre_exec "$cmd" || [ "$cmd" = "$ocmd" ] ||' '_pr_pre_exec "$cmd" ||'
run_mutant "AC2 --expect owner-line check deleted" leg_expect
mk_mutant preexec sub '_pr_pre_exec "$cmd" || [ "$cmd" = "$ocmd" ] || { matched=1; break; }' '[ "$cmd" = "$ocmd" ] || { matched=1; break; }'
run_mutant "AC2 --expect exec-past-launcher check deleted" leg_expect
mk_mutant widen sub 'overdue|orphaned) _pr_stop "$f" ;;' 'overdue|orphaned|running) _pr_stop "$f" ;;'
run_mutant "AC6 reap filter widened to running" leg_apply_classes
mk_mutant wrapgrace del "phase:|lane:|drain:) printf '120' ;;"
run_mutant "AC9 the GRACE table's WRAPPER row deleted (a wrapper falls back to the short grace)" leg_header
mk_mutant snaplstart del "summary: the snapshot's lstart"
run_mutant "AC10 summary's snapshot lstart lookup replaced by a live ps per entry (>1 ps call)" leg_summary_recycled
mk_mutant sumhash del 'command line differs (pid recycled)'
run_mutant "AC10 cmd-hash comparison deleted (summary reads the recycled pid running)" leg_summary_recycled
mk_mutant snaptz sub 'env TZ=UTC0 LC_ALL=C ps -A -ww' 'env LC_ALL=C ps -A -ww'
run_mutant "AC10 the snapshot's TZ pin dropped (every entry would read finished)" leg_summary_recycled
mk_mutant unavail sub "printf 'proc-registry: summary — unavailable" ": '"
run_mutant "AC10 the unavailable line silenced" leg_summary_zero
mk_mutant unregmin sub '[ "$age" -gt "$min" ] || continue' '[ "$age" -lt 0 ] || continue'
run_mutant "AC11 the --scan age comparison made never-true" leg_summary_scan
mk_mutant unregreg del '[ "$E_CLASS" = finished ] || PR_LIVE="$PR_LIVE$E_PID "'
run_mutant "AC11 the registered-pid exclusion deleted" leg_summary_scan
mk_mutant sumtouch sub 'local files f n=0 nr=0' ': > "$PR_DIR/.touched"; local files f n=0 nr=0'
run_mutant "AC11 summary touches a file in the registry dir (checksum)" leg_summary_scan
mk_mutant ancestors del 'ex="$ex$p "'
run_mutant "AC11 the ancestor walk deleted" leg_summary_scan
mk_mutant descendant del '! _pr_live_ancestor "$pid" "$live" || continue'
run_mutant "AC11 the registered-descendant exclusion deleted" leg_summary_scan
mk_mutant gonescript sub '_pr_in_tmp "$path" && [ ! -e "$path" ]' '_pr_in_tmp "$path"'
run_mutant "AC11 the gone-script check deleted (an existing temp script counts)" leg_summary_scan
mk_mutant hermscan range 'hermetic scan skip'
run_mutant "AC11 the hermetic scan skip deleted (a live look-alike is counted)" leg_summary_hermetic
mk_mutant listrow del "printf 'unreg-%s"
run_mutant "leg_list_scan list --scan's own unregistered row print deleted (0 rows, not 3)" leg_list_scan
mk_mutant suhash del '_pr_matches "$pid" "$start" "$hash" ||'
run_mutant "leg_stop_unreg_recycled stop-unregistered's identity re-check before TERM deleted (a recycled look-alike is TERMed)" leg_stop_unreg_recycled
mk_mutant sulive del 'case "$PR_LIVE" in *" $pid "*)'
run_mutant "leg_stop_unreg stop-unregistered's live-entry refusal deleted" leg_stop_unreg
mk_mutant supred del '_pr_su_counted "$pid" ||'
run_mutant "leg_stop_unreg_nonlookalike stop-unregistered's scan-predicate refusal deleted (a plain sleep is TERMed)" leg_stop_unreg_nonlookalike

echo
echo "test-proc-registry.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
