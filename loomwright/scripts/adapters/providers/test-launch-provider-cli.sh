#!/usr/bin/env bash
# test-launch-provider-cli.sh — self-tests for launch-provider-cli.sh, the one
# sourced launcher every provider CLI call goes through. Each scenario gets its
# OWN baked stub CLI that records what it observed (its HOME tree, its env, its
# pids) into fixed paths under this run's $TMP: the launcher scrubs the child
# env, so a stub can never be steered or read back through env vars.
#
# Covers:
#   A. isolated mode: the isolated HOME holds exactly the declared login files
#      that exist (a symlinked source is copied as a regular file), each
#      read-only and byte-identical to its source (a file declared twice is
#      still there); no symlink anywhere under it; undeclared files, a missing
#      declared file and refused declarations (absolute, `..`, empty, a
#      directory) never cross; the child env is only PATH / HOME /
#      TMPDIR plus the declared env vars that are set (no GH_TOKEN, no
#      undeclared provider key; HOME is refused as a declared name); the CLI's
#      exit status and output come back; the isolated HOME is gone after
#   B. shell mode: the real HOME, env still scrubbed, declared env still passed
#   C. timeout: a hung CLI (leader + child) is killed as a process group, the
#      call reports LPC_TIMED_OUT=1, and the isolated HOME is removed after the
#      kill
#   D. abort: a caller signalled mid-call (TERM) runs launch_provider_cli_abort
#      from its EXIT trap: CLI group killed, isolated HOME removed
#   E. a CLI that ends normally but leaves a background child: the child is
#      killed with its group before the HOME goes
#   F. a CLI that ends before the bound leaves no watchdog sleep behind
#   G. refused arguments (home mode, timeout, CLI name, cwd) return 1 with
#      LPC_ERROR set and start nothing
#   H. the timeout flag file: an entry planted at its TMPDIR path during the
#      call (a symlink to a victim file) is never followed — the victim is
#      untouched after a timeout — and never reads as a timeout on a normal
#      run; the flag file is gone after a normal end, a timeout and an abort
#   I. a CLI that makes dirs in its HOME 000 (including the one holding the
#      copied login): the HOME is still removed after a normal end and after a
#      timeout, and a symlink it planted is never chmod-ed through
#
# Exit 0 = all pass, 1 = any failure.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAUNCHER="$HERE/launch-provider-cli.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then ok "$label"; else no "$label (expected [$expected] got [$actual])"; fi
}

if [ ! -r "$LAUNCHER" ]; then
  echo "test-launch-provider-cli.sh: launcher not found at $LAUNCHER"; echo "RESULT: 0 passed, 1 failed"; exit 1
fi
# shellcheck disable=SC1090
. "$LAUNCHER"

TMP="$(mktemp -d)"
ABORT_CALLER_PID=""
cleanup() {
  if [ -n "$ABORT_CALLER_PID" ]; then
    kill "$ABORT_CALLER_PID" 2>/dev/null; wait "$ABORT_CALLER_PID" 2>/dev/null
  fi
  launch_provider_cli_abort
  chmod 0700 "$TMP/i-victim" "$TMP/i-target" 2>/dev/null
  launch_provider_cli_rmtree "$TMP"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
TEST_PGID="$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ')"
RUN_TAG="$$"
CLI="loomwright-test-launch-cli-$RUN_TAG"
CWD="$TMP/cwd"; mkdir -p "$CWD"

# ---- the caller's (parent's) HOME, with login files and a non-login file -----
export HOME="$TMP/home"
mkdir -p "$HOME/.fake" "$HOME/.other" "$TMP/elsewhere"
printf 'fake-login-%s\n' "$RUN_TAG" > "$HOME/.fake/auth.json"
printf 'linked-login-%s\n' "$RUN_TAG" > "$TMP/elsewhere/real.json"
ln -s "$TMP/elsewhere/real.json" "$HOME/.fake/linked.json"
printf 'not-a-login\n' > "$HOME/.other/secret.json"
printf 'outside\n' > "$TMP/outside.json"
chmod 600 "$HOME/.fake/auth.json"

# write_recorder_stub <dir> <record-prefix> <exit-code> — a stub that records
# its HOME path, its env, the regular files / symlinks under its HOME and the
# permission column of each file, prints one stdout and one stderr line, and
# exits <exit-code>. No heredoc inside the stub: TMPDIR is its HOME, and a
# heredoc's temp file would land in the tree it is listing.
write_recorder_stub() {
  local dir="$1" rec="$2" rc="$3"
  mkdir -p "$dir"
  cat > "$dir/$CLI" <<STUB
#!/usr/bin/env bash
printf '%s\\n' "\$HOME" > "$rec.home"
printf '%s\\n' "\$TMPDIR" > "$rec.tmpdir"
env > "$rec.env"
( cd "\$HOME" && find . -type f -print | sort ) > "$rec.files"
( cd "\$HOME" && find . -type l -print | sort ) > "$rec.links"
( cd "\$HOME" && find . -type f -exec ls -ln {} \\; | awk '{print substr(\$1, 1, 10)}' | sort -u ) > "$rec.modes"
if cmp -s "\$HOME/.fake/auth.json" "$HOME/.fake/auth.json"; then echo same; else echo differ; fi > "$rec.cmp"
echo "stub-stdout"
echo "stub-stderr" >&2
exit $rc
STUB
  chmod +x "$dir/$CLI"
}

# env_names <env-dump> — the variable names, minus the ones the stub's own
# shell sets on startup (PWD, SHLVL, _, OLDPWD), sorted, space-joined.
env_names() {
  sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' "$1" 2>/dev/null \
    | grep -vxE 'PWD|SHLVL|_|OLDPWD' | sort | tr '\n' ' ' | sed 's/ $//'
}

echo "==== A: isolated mode — exactly the declared files cross, read-only, no links; env allow-list ===="
STUB_A="$TMP/stub-a"; REC_A="$TMP/rec-a"
write_recorder_stub "$STUB_A" "$REC_A" 7
PROVIDER_LOGIN_FILES=(".fake/auth.json" ".fake/linked.json" ".fake/missing.json" \
  "/$TMP/outside.json" "../outside.json" ".fake/../.other/secret.json" "" ".fake/" \
  ".fake/auth.json")
PROVIDER_LOGIN_ENV=("FAKE_LOGIN_KEY" "FAKE_UNSET_KEY" "HOME" "bad-name")
unset FAKE_UNSET_KEY
RC_A=0
PATH="$STUB_A:$PATH" GH_TOKEN="gh-secret-$RUN_TAG" OTHER_PROVIDER_API_KEY="other-$RUN_TAG" \
  FAKE_LOGIN_KEY="v a=l" \
  launch_provider_cli isolated 30 "$CWD" "$TMP/out-a" "$TMP/err-a" "$CLI" || RC_A=$?
assert_eq "A launch returned 0" "0" "$RC_A"
assert_eq "A LPC_RC is the CLI's own exit status" "7" "$LPC_RC"
assert_eq "A LPC_TIMED_OUT=0" "0" "$LPC_TIMED_OUT"
assert_eq "A stdout captured" "stub-stdout" "$(cat "$TMP/out-a" 2>/dev/null)"
assert_eq "A stderr captured" "stub-stderr" "$(cat "$TMP/err-a" 2>/dev/null)"
ISO_A="$(cat "$REC_A.home" 2>/dev/null)"
if [ -z "$ISO_A" ]; then
  no "A stub never recorded its HOME — it did not run"
else
  assert_eq "A HOME is not the caller's HOME" "1" "$( [ "$ISO_A" != "$HOME" ] && echo 1 || echo 0 )"
  assert_eq "A TMPDIR is the isolated HOME" "$ISO_A" "$(cat "$REC_A.tmpdir" 2>/dev/null)"
  assert_eq "A isolated HOME holds exactly the declared files that exist" \
    "./.fake/auth.json ./.fake/linked.json" "$(tr '\n' ' ' < "$REC_A.files" | sed 's/ $//')"
  assert_eq "A isolated HOME holds no symlinks" "" "$(cat "$REC_A.links" 2>/dev/null)"
  assert_eq "A every copied login file is read-only (owner read only)" "-r--------" "$(cat "$REC_A.modes" 2>/dev/null)"
  assert_eq "A the copy is byte-identical to the declared source" "same" "$(cat "$REC_A.cmp" 2>/dev/null)"
  assert_eq "A the isolated HOME is removed after the call" "0" "$( [ -e "$ISO_A" ] && echo 1 || echo 0 )"
fi
assert_eq "A only declared env vars cross (allow-list + set declared vars)" \
  "FAKE_LOGIN_KEY HOME PATH TMPDIR" "$(env_names "$REC_A.env")"
assert_eq "A GH_TOKEN never reaches the CLI" "0" "$(grep -c '^GH_TOKEN=' "$REC_A.env" 2>/dev/null)"
assert_eq "A an undeclared provider key never reaches the CLI" "0" "$(grep -c '^OTHER_PROVIDER_API_KEY=' "$REC_A.env" 2>/dev/null)"
assert_eq "A a declared var's value crosses intact (spaces, '=')" "1" "$(grep -cx 'FAKE_LOGIN_KEY=v a=l' "$REC_A.env" 2>/dev/null)"
assert_eq "A the caller's own login file is untouched" "fake-login-$RUN_TAG" "$(cat "$HOME/.fake/auth.json")"
assert_eq "A the caller's symlinked login source is still a symlink" "1" "$( [ -L "$HOME/.fake/linked.json" ] && echo 1 || echo 0 )"

echo ""
echo "==== B: shell mode — the real HOME, env still scrubbed ===="
STUB_B="$TMP/stub-b"; REC_B="$TMP/rec-b"
write_recorder_stub "$STUB_B" "$REC_B" 0
PROVIDER_LOGIN_FILES=(".fake/auth.json")
PROVIDER_LOGIN_ENV=("FAKE_LOGIN_KEY")
RC_B=0
PATH="$STUB_B:$PATH" GH_TOKEN="gh-secret-$RUN_TAG" FAKE_LOGIN_KEY="k" \
  launch_provider_cli shell 30 "$CWD" "$TMP/out-b" "$TMP/err-b" "$CLI" || RC_B=$?
assert_eq "B launch returned 0, CLI rc 0" "0:0" "$RC_B:$LPC_RC"
assert_eq "B HOME is the caller's real HOME" "$HOME" "$(cat "$REC_B.home" 2>/dev/null)"
assert_eq "B env is still the allow-list plus declared vars" "FAKE_LOGIN_KEY HOME PATH TMPDIR" "$(env_names "$REC_B.env")"
assert_eq "B the real HOME was not modified" "./.fake/auth.json ./.other/secret.json" \
  "$( ( cd "$HOME" && find . -type f -print | sort ) | tr '\n' ' ' | sed 's/ $//')"

# write_hung_stub <dir> <record-prefix> — records HOME, pid and pgid FIRST, then
# hangs with a child.
write_hung_stub() {
  local dir="$1" rec="$2"
  mkdir -p "$dir"
  cat > "$dir/$CLI" <<STUB
#!/usr/bin/env bash
printf '%s\\n' "\$HOME" > "$rec.home"
printf '%s\\n' "\$\$" > "$rec.self"
ps -o pgid= -p "\$\$" 2>/dev/null | tr -d ' ' > "$rec.pgid"
sleep 120 &
printf '%s\\n' "\$!" > "$rec.child"
sleep 120
STUB
  chmod +x "$dir/$CLI"
}

# assert_gone <label> <record-prefix> — the stub's leader and child are not
# running and its own process group is empty (polled up to 10s). Scoped to the
# pids THIS run's stub recorded, never a machine-wide name match.
assert_gone() {
  local label="$1" rec="$2" self child pgid i=0
  self="$(cat "$rec.self" 2>/dev/null)"; child="$(cat "$rec.child" 2>/dev/null)"; pgid="$(cat "$rec.pgid" 2>/dev/null)"
  while [ "$i" -lt 50 ]; do
    { [ -n "$self" ] && kill -0 "$self" 2>/dev/null; } || { [ -n "$child" ] && kill -0 "$child" 2>/dev/null; } || break
    sleep 0.2; i=$((i+1))
  done
  if [ -z "$self" ] || [ -z "$child" ] || [ -z "$pgid" ]; then
    no "$label stub never recorded its pids"; return
  fi
  assert_eq "$label CLI leader gone" "0" "$( kill -0 "$self" 2>/dev/null && echo 1 || echo 0 )"
  assert_eq "$label CLI child gone (process-group kill)" "0" "$( kill -0 "$child" 2>/dev/null && echo 1 || echo 0 )"
  if [ "$pgid" != "$self" ]; then
    no "$label CLI pgid [$pgid] != pid [$self] — not its own process group"
  elif [ "$pgid" = "$TEST_PGID" ]; then
    no "$label CLI ran in the test's own process group"
  else
    assert_eq "$label CLI's own process group is empty" "" "$(pgrep -g "$pgid" 2>/dev/null | tr '\n' ' ')"
  fi
}

echo ""
echo "==== C: timeout — process group killed, isolated HOME removed after the kill ===="
STUB_C="$TMP/stub-c"; REC_C="$TMP/rec-c"
write_hung_stub "$STUB_C" "$REC_C"
PROVIDER_LOGIN_FILES=(".fake/auth.json")
PROVIDER_LOGIN_ENV=()
START_C="$(date +%s)"
RC_C=0
PATH="$STUB_C:$PATH" launch_provider_cli isolated 3 "$CWD" "$TMP/out-c" "$TMP/err-c" "$CLI" || RC_C=$?
ELAPSED_C=$(( $(date +%s) - START_C ))
assert_eq "C launch returned 0" "0" "$RC_C"
assert_eq "C LPC_TIMED_OUT=1" "1" "$LPC_TIMED_OUT"
assert_eq "C returned well inside the stub's sleep (elapsed ${ELAPSED_C}s < 20s)" "1" "$( [ "$ELAPSED_C" -lt 20 ] && echo 1 || echo 0 )"
ISO_C="$(cat "$REC_C.home" 2>/dev/null)"
if [ -n "$ISO_C" ]; then
  assert_eq "C isolated HOME removed after a timeout kill" "0" "$( [ -e "$ISO_C" ] && echo 1 || echo 0 )"
else
  no "C stub never recorded its HOME"
fi
assert_gone "C" "$REC_C"

echo ""
echo "==== D: abort — a caller TERMed mid-call kills the CLI group and removes the HOME ===="
STUB_D="$TMP/stub-d"; REC_D="$TMP/rec-d"
write_hung_stub "$STUB_D" "$REC_D"
CALLER_D="$TMP/caller-d.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '. %q\n' "$LAUNCHER"
  printf '%s\n' 'PROVIDER_LOGIN_FILES=(".fake/auth.json")'
  printf '%s\n' 'trap launch_provider_cli_abort EXIT'
  printf '%s\n' "trap 'exit 143' TERM"
  printf 'launch_provider_cli isolated 60 %q %q %q %q\n' "$CWD" "$TMP/out-d" "$TMP/err-d" "$CLI"
} > "$CALLER_D"
PATH="$STUB_D:$PATH" bash "$CALLER_D" >/dev/null 2>&1 &
ABORT_CALLER_PID=$!
i=0
while [ ! -s "$REC_D.child" ] && [ "$i" -lt 150 ]; do sleep 0.2; i=$((i+1)); done
ISO_D="$(cat "$REC_D.home" 2>/dev/null)"
if [ -z "$ISO_D" ]; then
  no "D stub never started under the caller"
else
  assert_eq "D isolated HOME exists while the CLI runs" "1" "$( [ -d "$ISO_D" ] && echo 1 || echo 0 )"
fi
kill -TERM "$ABORT_CALLER_PID" 2>/dev/null
wait "$ABORT_CALLER_PID" 2>/dev/null
ABORT_CALLER_PID=""
[ -n "$ISO_D" ] && assert_eq "D isolated HOME removed on the abort path" "0" "$( [ -e "$ISO_D" ] && echo 1 || echo 0 )"
assert_gone "D" "$REC_D"

echo ""
echo "==== E: a normal exit that leaves a background child — the child goes with its group ===="
STUB_E="$TMP/stub-e"; REC_E="$TMP/rec-e"; mkdir -p "$STUB_E"
cat > "$STUB_E/$CLI" <<STUB
#!/usr/bin/env bash
sleep 120 >/dev/null 2>&1 &
printf '%s\\n' "\$!" > "$REC_E.straggler"
exit 0
STUB
chmod +x "$STUB_E/$CLI"
PROVIDER_LOGIN_FILES=(); PROVIDER_LOGIN_ENV=()
PATH="$STUB_E:$PATH" launch_provider_cli isolated 30 "$CWD" "$TMP/out-e" "$TMP/err-e" "$CLI"
STRAGGLER_E="$(cat "$REC_E.straggler" 2>/dev/null)"
if [ -z "$STRAGGLER_E" ]; then
  no "E stub never recorded its background child"
else
  i=0; while kill -0 "$STRAGGLER_E" 2>/dev/null && [ "$i" -lt 25 ]; do sleep 0.2; i=$((i+1)); done
  assert_eq "E the leftover child is not running after the call" "0" "$( kill -0 "$STRAGGLER_E" 2>/dev/null && echo 1 || echo 0 )"
fi
assert_eq "E rc 0, not timed out" "0:0" "$LPC_RC:$LPC_TIMED_OUT"

echo ""
echo "==== F: a CLI that ends before the bound leaves no watchdog sleep behind ===="
F_BOUND=$(( 200000 + RUN_TAG ))
PATH="$STUB_B:$PATH" launch_provider_cli isolated "$F_BOUND" "$CWD" "$TMP/out-f" "$TMP/err-f" "$CLI"
f_left() { ps -axo command= 2>/dev/null | awk -v w="sleep $F_BOUND" '$0 == w' | wc -l | tr -d ' '; }
i=0; while [ "$(f_left)" != "0" ] && [ "$i" -lt 20 ]; do sleep 0.1; i=$((i+1)); done
assert_eq "F no 'sleep $F_BOUND' left running" "0" "$(f_left)"

echo ""
echo "==== G: refused arguments start nothing ===="
STUB_G="$TMP/stub-g"; RAN_G="$TMP/ran-g"; mkdir -p "$STUB_G"
cat > "$STUB_G/$CLI" <<STUB
#!/usr/bin/env bash
printf 'ran\\n' >> "$RAN_G"
STUB
chmod +x "$STUB_G/$CLI"
g_case() { # <label> <expected LPC_ERROR fragment> <args...>
  local label="$1" want="$2" rc=0
  shift 2
  PATH="$STUB_G:$PATH" launch_provider_cli "$@" || rc=$?
  assert_eq "G $label -> returns 1" "1" "$rc"
  case "$LPC_ERROR" in *"$want"*) ok "G $label -> LPC_ERROR names it" ;; *) no "G $label -> LPC_ERROR [$LPC_ERROR] lacks [$want]" ;; esac
}
g_case "unknown home mode" "home mode" real 5 "$CWD" "$TMP/o" "$TMP/e" "$CLI"
g_case "non-numeric timeout" "timeout" isolated 5s "$CWD" "$TMP/o" "$TMP/e" "$CLI"
g_case "zero timeout" "timeout" isolated 0 "$CWD" "$TMP/o" "$TMP/e" "$CLI"
g_case "CLI name with '='" "CLI name" isolated 5 "$CWD" "$TMP/o" "$TMP/e" "X=$CLI"
g_case "CLI name with a leading '-'" "CLI name" isolated 5 "$CWD" "$TMP/o" "$TMP/e" "-$CLI"
g_case "missing cwd" "cwd" isolated 5 "$TMP/no-such-dir" "$TMP/o" "$TMP/e" "$CLI"
g_case "too few arguments" "usage" isolated 5 "$CWD" "$TMP/o" "$TMP/e"
assert_eq "G the stub never ran" "0" "$( [ -e "$RAN_G" ] && echo 1 || echo 0 )"
assert_eq "G no refused call left an isolated HOME recorded" "" "$LPC_HOME"

echo ""
echo "==== H: the timeout flag file — a planted symlink is never followed, never a false timeout ===="
# The caller's TMPDIR is private to this scenario, so the flag file the
# launcher allocates is the only loomwright-provider-tmo-* entry in it. A
# mktemp wrapper records that path; the stub (running mid-call, as the same
# user) tries to plant a symlink to a victim file there with `ln -s` (no -f).
H_TMPDIR="$TMP/h-tmpdir"; mkdir -p "$H_TMPDIR"
H_FLAGREC="$TMP/h-flagpath"; H_VICTIM="$TMP/h-victim"
mktemp() {
  local p
  p="$(command mktemp "$@")" || return $?
  case "$p" in *loomwright-provider-tmo-*) printf '%s\n' "$p" > "$H_FLAGREC" ;; esac
  printf '%s\n' "$p"
}
# write_planter_stub <dir> <hang:0|1> — plants the symlink, then exits 0 or hangs.
write_planter_stub() {
  local dir="$1" hang="$2"
  mkdir -p "$dir"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf 'f="$(cat %q 2>/dev/null)"\n' "$H_FLAGREC"
    printf 'if [ -n "$f" ] && ln -s %q "$f" 2>/dev/null; then echo planted > %q; else echo refused > %q; fi\n' \
      "$H_VICTIM" "$TMP/h-plant" "$TMP/h-plant"
    [ "$hang" = "1" ] && printf '%s\n' 'sleep 120'
    printf '%s\n' 'exit 0'
  } > "$dir/$CLI"
  chmod +x "$dir/$CLI"
}
h_flag_left() { ( shopt -s nullglob; set -- "$H_TMPDIR"/loomwright-provider-tmo-*; echo $# ); }
PROVIDER_LOGIN_FILES=(); PROVIDER_LOGIN_ENV=()

printf 'victim-content-%s\n' "$RUN_TAG" > "$H_VICTIM"
H_VICTIM_BEFORE="$(cat "$H_VICTIM")"
STUB_H1="$TMP/stub-h1"; write_planter_stub "$STUB_H1" 1
rm -f "$H_FLAGREC" "$TMP/h-plant"
TMPDIR="$H_TMPDIR" PATH="$STUB_H1:$PATH" launch_provider_cli isolated 2 "$CWD" "$TMP/out-h1" "$TMP/err-h1" "$CLI"
assert_eq "H1 the bound fired (LPC_TIMED_OUT=1)" "1" "$LPC_TIMED_OUT"
assert_eq "H1 the flag path could not be replaced by a symlink mid-call" "refused" "$(cat "$TMP/h-plant" 2>/dev/null)"
assert_eq "H1 the victim file is untouched after the timeout" "$H_VICTIM_BEFORE" "$(cat "$H_VICTIM" 2>/dev/null)"
assert_eq "H1 the flag file is removed after a timeout" "0" "$(h_flag_left)"

STUB_H2="$TMP/stub-h2"; write_planter_stub "$STUB_H2" 0
rm -f "$H_FLAGREC" "$TMP/h-plant"
TMPDIR="$H_TMPDIR" PATH="$STUB_H2:$PATH" launch_provider_cli isolated 30 "$CWD" "$TMP/out-h2" "$TMP/err-h2" "$CLI"
assert_eq "H2 a normal run with a plant attempt is not a timeout" "0:0" "$LPC_RC:$LPC_TIMED_OUT"
assert_eq "H2 the flag path could not be replaced by a symlink mid-call" "refused" "$(cat "$TMP/h-plant" 2>/dev/null)"
assert_eq "H2 the flag file is removed after a normal end" "0" "$(h_flag_left)"
assert_eq "H2 the victim file is untouched" "$H_VICTIM_BEFORE" "$(cat "$H_VICTIM" 2>/dev/null)"
unset -f mktemp

# Abort path: a caller TERMed mid-call leaves no flag file in its TMPDIR.
STUB_H3="$TMP/stub-h3"; REC_H3="$TMP/rec-h3"
write_hung_stub "$STUB_H3" "$REC_H3"
CALLER_H3="$TMP/caller-h3.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '. %q\n' "$LAUNCHER"
  printf '%s\n' 'trap launch_provider_cli_abort EXIT'
  printf '%s\n' "trap 'exit 143' TERM"
  printf 'launch_provider_cli isolated 60 %q %q %q %q\n' "$CWD" "$TMP/out-h3" "$TMP/err-h3" "$CLI"
} > "$CALLER_H3"
TMPDIR="$H_TMPDIR" PATH="$STUB_H3:$PATH" bash "$CALLER_H3" >/dev/null 2>&1 &
ABORT_CALLER_PID=$!
i=0
while [ ! -s "$REC_H3.child" ] && [ "$i" -lt 150 ]; do sleep 0.2; i=$((i+1)); done
assert_eq "H3 the flag file exists while the CLI runs" "1" "$(h_flag_left)"
kill -TERM "$ABORT_CALLER_PID" 2>/dev/null
wait "$ABORT_CALLER_PID" 2>/dev/null
ABORT_CALLER_PID=""
assert_eq "H3 the flag file is removed on the abort path" "0" "$(h_flag_left)"
assert_gone "H3" "$REC_H3"

echo ""
echo "==== I: a CLI that strips owner r/x from dirs in its HOME — the HOME (and the copied login) still goes ===="
# The stub makes the dir holding the copied login 000 (and a nested dir under
# it), after planting a symlink there to a victim dir OUTSIDE the HOME. The
# cleanup must restore u+rwx on the HOME's own dirs only: the victim's mode is
# unchanged afterwards (a chmod through the link would have made it u+rwx).
I_VICTIM="$TMP/i-victim"; mkdir -p "$I_VICTIM"; chmod 0500 "$I_VICTIM"
I_VICTIM_MODE="$(ls -ld "$I_VICTIM" | cut -c1-10)"
# write_chmod_stub <dir> <record-prefix> <hang:0|1>
write_chmod_stub() {
  local dir="$1" rec="$2" hang="$3"
  mkdir -p "$dir"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf 'printf "%%s\\n" "$HOME" > %q\n' "$rec.home"
    printf '%s\n' 'mkdir -p "$HOME/.fake/deep/er"'
    printf 'ln -s %q "$HOME/.fake/outlink"\n' "$I_VICTIM"
    printf '%s\n' 'chmod 000 "$HOME/.fake/deep/er" "$HOME/.fake/deep" "$HOME/.fake"'
    [ "$hang" = "1" ] && printf '%s\n' 'sleep 120'
    printf '%s\n' 'exit 0'
  } > "$dir/$CLI"
  chmod +x "$dir/$CLI"
}
PROVIDER_LOGIN_FILES=(".fake/auth.json"); PROVIDER_LOGIN_ENV=()
for i_case in normal timeout; do
  STUB_I="$TMP/stub-i-$i_case"; REC_I="$TMP/rec-i-$i_case"
  if [ "$i_case" = "normal" ]; then
    write_chmod_stub "$STUB_I" "$REC_I" 0; I_BOUND=30
  else
    write_chmod_stub "$STUB_I" "$REC_I" 1; I_BOUND=3
  fi
  RC_I=0
  PATH="$STUB_I:$PATH" launch_provider_cli isolated "$I_BOUND" "$CWD" "$TMP/out-i" "$TMP/err-i" "$CLI" || RC_I=$?
  if [ "$i_case" = "normal" ]; then
    assert_eq "I($i_case) launch 0, CLI rc 0, not timed out" "0:0:0" "$RC_I:$LPC_RC:$LPC_TIMED_OUT"
  else
    assert_eq "I($i_case) launch 0, the bound fired" "0:1" "$RC_I:$LPC_TIMED_OUT"
  fi
  ISO_I="$(cat "$REC_I.home" 2>/dev/null)"
  if [ -z "$ISO_I" ]; then
    no "I($i_case) stub never recorded its HOME"
  else
    assert_eq "I($i_case) isolated HOME (with the copied login) removed despite a 000 dir" "0" \
      "$( [ -e "$ISO_I" ] || [ -L "$ISO_I" ] && echo 1 || echo 0 )"
  fi
  assert_eq "I($i_case) the victim dir behind a planted symlink keeps its mode" "$I_VICTIM_MODE" "$(ls -ld "$I_VICTIM" | cut -c1-10)"
done
chmod 0700 "$I_VICTIM"

# The helper on its own: a symlink as the root is removed as a link, its
# target dir (and mode) untouched.
I_TARGET="$TMP/i-target"; mkdir -p "$I_TARGET/keep"; chmod 0500 "$I_TARGET"
I_TARGET_MODE="$(ls -ld "$I_TARGET" | cut -c1-10)"
ln -s "$I_TARGET" "$TMP/i-rootlink"
launch_provider_cli_rmtree "$TMP/i-rootlink"
assert_eq "I rmtree on a symlink root removes only the link" "0:1" \
  "$( [ -L "$TMP/i-rootlink" ] && echo 1 || echo 0 ):$( [ -d "$I_TARGET/keep" ] && echo 1 || echo 0 )"
assert_eq "I rmtree on a symlink root leaves the target's mode alone" "$I_TARGET_MODE" "$(ls -ld "$I_TARGET" | cut -c1-10)"
chmod 0700 "$I_TARGET"

echo ""
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && exit 0 || exit 1
