#!/usr/bin/env bash
# test-write-run.sh — stub-backed self-tests for write-run.sh (the isolated
# write-seat runner). Same conventions as test-lens-run.sh: the test writes its
# OWN provider-table entries into this directory (write-run.sh resolves
# provider-<name>.sh beside itself) and removes them in its EXIT trap; every
# per-run name carries RUN_TAG (this run's pid); each scenario gets its OWN
# baked stub CLI on a per-scenario PATH dir, because the launcher scrubs the
# child env (`env -i`), so a stub can never be steered by an env var.
#
# HARNESS (consent): write-run.sh reads both grants from the worktree's own
# repo through resolve-egress-config.sh, with no bypass. So HOME is a scratch
# dir whose user-scope egress.json grants the stub providers for a scratch
# repo's pinned slug (its origin URL). The worktree under test is a LINKED
# worktree of that repo (its `.git` is a file; the common dir is shared), and a
# second linked worktree is the "sibling".
#
# Covers:
#   P. each pre-launch refusal, none of which starts the CLI (its sentinel is
#      never written) or touches the tree, rc 0, changed_files [], no
#      tree_restored key: provider_unavailable (CLI not on PATH; bad name),
#      write_claude_is_task_path, provider_not_granted, write_not_granted,
#      write_unpinnable, write_tree_dirty (untracked file; modified file),
#      write_repo_settings_present (settings.local.json; settings.json with a
#      `permissions` key) — and a settings.json WITHOUT `permissions` launches
#   U. usage errors exit 2 (missing --out, a read seat, a home-mode flag, a
#      worktree subdir)
#   S. isolated-only launch: no `launch_provider_cli shell` in write-run.sh, a
#      `launch_provider_cli isolated` call present, and the stub's HOME is not
#      the caller's HOME
#   O. ok: edits stay, changed_files lists them, tree_restored false, no
#      notes, the reply text (which claims another status) is ignored; default
#      timeout 420; then `--restore` leaves a clean tree, and `--restore` is
#      refused (nothing changed) when HEAD moved
#   C. a commit made by the provider -> write_git_tampered, notes name head +
#      refs, HEAD and the branch back at the pre-launch commit, tree restored
#   H. a hook planted in the common hooks dir -> write_git_tampered, notes
#      name the hook, hook removed afterwards; a planted core.hooksPath ->
#      write_git_tampered, the config restored
#   B. a sibling worktree's branch committing during the launch -> still ok
#   T. a hung stub with partial edits under LOOMWRIGHT_WRITE_CLI_TIMEOUT=3 ->
#      write_timeout, tree_restored true, the partial edits gone
#   K. the timeout clamp: 9999 / 481 -> 480; abc / 0 / empty -> 420; 480 stays
#   F. a CLI exiting non-zero -> write_failed, tree restored, reply ignored
#   R. a restore that cannot complete -> write_git_tampered, tree_restored false
#   G. a planted smudge/clean filter never runs during the restore or the
#      owner's next git command: via a redirected commondir file (G1), via the
#      real config plus an in-tree .gitattributes (G2) or info/attributes (G3);
#      a redirect the restore cannot undo runs no index or tree command (G4)
#   W. a provider edit to a guard-protected path (pytest.ini, .husky/) ->
#      write_protected_path, tree restored, the guard's opt-out env ignored
#   X. provider-authored ignore rules: an ok launch planting a self-ignoring
#      sub/.gitignore beside a protected sub/pytest.ini -> write_protected_path,
#      both gone (X1); a new .gitignore alone never stays (X1b); a non-ok launch
#      planting the same -> both gone, tree_restored true (X2); a pre-existing
#      ignored file survives every restore; a new nested repo under an ignored
#      dir is left and the restore reads incomplete (X3)
#   SB. two overlapping runs in sibling worktrees: the later run restores the
#      shared files from the earlier run's baseline, so the hook the earlier
#      run's restore removed is never re-planted; the registry is removed
#
# Exit 0 = all pass, 1 = any failure.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRITE="$HERE/write-run.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then ok "$label"; else no "$label (expected [$expected] got [$actual])"; fi
}
assert_has() {
  local label="$1" hay="$2" needle="$3"
  case "$hay" in *"$needle"*) ok "$label" ;; *) no "$label ([$hay] lacks [$needle])" ;; esac
}

if ! command -v jq >/dev/null 2>&1; then
  echo "test-write-run.sh: jq is required to run this suite"; echo "RESULT: 0 passed, 1 failed"; exit 1
fi
if [ ! -f "$WRITE" ]; then
  echo "test-write-run.sh: write-run.sh not found at $WRITE"; echo "RESULT: 0 passed, 1 failed"; exit 1
fi

TMP="$(mktemp -d)"
TMP="$(cd "$TMP" && pwd -P)"
RUN_TAG="$$"
CLI="loomwright-test-write-cli-$RUN_TAG"
P_MAIN="teststub$RUN_TAG"
# Digits only, so every transient file matches the `provider-teststub<digits>.sh`
# shape a concurrent test-setup-providers.sh tolerates. The 8-digit suffixes make
# a name longer than any pid and differ from each other in the last digit, so no
# two concurrent runs can produce the same name.
P_NP="teststub${RUN_TAG}99000001"
P_NG="teststub${RUN_TAG}99000002"
F_MAIN="$HERE/provider-$P_MAIN.sh"
F_NP="$HERE/provider-$P_NP.sh"
F_NG="$HERE/provider-$P_NG.sh"
cleanup() {
  chmod -R u+rwx "$TMP" 2>/dev/null
  rm -rf "$TMP"
  rm -f "$F_MAIN" "$F_NP" "$F_NG"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# ---- scratch HOME, grants, repo + two linked worktrees ------------------------
export HOME="$TMP/home"
mkdir -p "$HOME"
printf '[user]\n\tname = write-test\n\temail = write-test@example.invalid\n[commit]\n\tgpgsign = false\n' > "$HOME/.gitconfig"
SLUG="write-test-owner/write-test-repo"
EGRESS_FILE="$HOME/.claude/loomwright/egress.json"
mkdir -p "$(dirname "$EGRESS_FILE")"
jq -n --arg s "$SLUG" --arg m "$P_MAIN" --arg np "$P_NP" \
  '{schema_version: 1, repos: {($s): {providers: [$m, $np], write_grants: {worker: [$m, $np]}}}}' > "$EGRESS_FILE"

REPO="$TMP/repo"
mkdir -p "$REPO/sub"
git -C "$REPO" init -q
git -C "$REPO" remote add origin "https://github.com/${SLUG}.git"
printf 'readme\n' > "$REPO/README.txt"
printf 'original\n' > "$REPO/src.txt"
printf 'a\n' > "$REPO/sub/a.txt"
git -C "$REPO" add -A
git -C "$REPO" commit -q -m "scratch commit"
# This repo ignores the harness settings dir, as the plugin's own repo does.
mkdir -p "$REPO/.git/info"; printf '.claude/\n' >> "$REPO/.git/info/exclude"
# An ignored dir the X cases use for pre-existing and new ignored content.
printf 'ignored-cache/\n' >> "$REPO/.git/info/exclude"
WT="$TMP/wt"; SIB="$TMP/wt-sib"
git -C "$REPO" worktree add -q -b feat "$WT" 2>/dev/null
git -C "$REPO" worktree add -q -b sib "$SIB" 2>/dev/null
PRE="$(git -C "$WT" rev-parse HEAD)"
COMMON="$(cd "$WT" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"
PROMPT="$TMP/prompt.txt"
printf 'Change src.txt.\n' > "$PROMPT"

# ---- provider-table entries ---------------------------------------------------
# write_provider <file> <with-write-argv:0|1>
write_provider() {
  {
    printf '%s\n' '#!/usr/bin/env bash' '# TEST-ONLY provider-table entry written by test-write-run.sh; removed in its EXIT trap.'
    printf 'PROVIDER_CLI_NAME="%s"\n' "$CLI"
    printf '%s\n' 'PROVIDER_WORKSPACE_FLAG=0' 'PROVIDER_HOME_SCRUB=1'
    printf '%s\n' 'provider_build_argv() { PROVIDER_ARGV=("$PROMPT_CONTENT"); }'
    [ "$2" = "1" ] && printf '%s\n' 'provider_write_argv() { PROVIDER_ARGV=("$PROMPT_CONTENT"); }'
    printf '%s\n' 'provider_extract_text() { PROVIDER_EXTRACTED="$(cat "$1")"; [ -n "$PROVIDER_EXTRACTED" ]; }'
  } > "$1"
}
write_provider "$F_MAIN" 1
write_provider "$F_NP" 0
write_provider "$F_NG" 1

# mkstub <label> <body-lines...> — a stub CLI in $TMP/stub-<label>/ that first
# appends to $TMP/ran-<label>, then runs the body (cwd = the worktree).
mkstub() {
  local label="$1"; shift
  mkdir -p "$TMP/stub-$label"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf 'echo ran >> %q\n' "$TMP/ran-$label"
    printf '%s\n' "$@"
  } > "$TMP/stub-$label/$CLI"
  chmod +x "$TMP/stub-$label/$CLI"
}
ran() { [ -e "$TMP/ran-$1" ] && echo yes || echo no; }

# run_write <label> <provider> <seat> [VAR=value ...] — write-run.sh with the
# label's stub dir first on PATH; result in $TMP/out-<label>.json, rc in RC.
RC=0
run_write() {
  local label="$1" prov="$2" seat="$3"; shift 3
  RC=0
  env "$@" PATH="$TMP/stub-$label:$PATH" bash "$WRITE" --provider "$prov" --seat "$seat" \
    --worktree "$WT" --prompt "$PROMPT" --out "$TMP/out-$label.json" >/dev/null 2>"$TMP/err-$label" || RC=$?
}
jf() { jq -r "$2" "$TMP/out-$1.json" 2>/dev/null; }
jfc() { jq -c "$2" "$TMP/out-$1.json" 2>/dev/null; }
tree_state() { git -C "$WT" status --porcelain --untracked-files=all 2>/dev/null | tr '\n' ' ' | sed 's/ $//'; }
reset_wt() {
  chmod -R u+rwx "$WT/sub" 2>/dev/null
  git -C "$WT" checkout -q feat 2>/dev/null
  git -C "$WT" reset -q --hard "$PRE"; git -C "$WT" clean -q -ffd
}

# assert_refusal <key> <label> <expected-status> — the shared refusal shape.
assert_refusal() {
  local key="$1" label="$2" want="$3"
  assert_eq "$label rc 0" "0" "$RC"
  assert_eq "$label write_status" "$want" "$(jf "$key" .write_status)"
  assert_eq "$label changed_files is []" "[]" "$(jfc "$key" .changed_files)"
  assert_eq "$label has no tree_restored key" "false" "$(jf "$key" 'has("tree_restored")')"
  assert_eq "$label carries notes" "true" "$(jf "$key" '(.notes // "") != ""')"
  assert_eq "$label cost unknown" "unknown" "$(jf "$key" .cost)"
  assert_eq "$label CLI never started" "no" "$(ran "$key")"
}

echo "==== P: pre-launch refusals start nothing and touch nothing ===="
mkstub p1 'exit 0'
RC=0; env PATH="$PATH" bash "$WRITE" --provider "$P_MAIN" --seat worker --worktree "$WT" \
  --prompt "$PROMPT" --out "$TMP/out-p1.json" >/dev/null 2>&1 || RC=$?
assert_refusal p1 "P1 CLI not on PATH" "provider_unavailable"
mkstub p1b 'exit 0'
run_write p1b "../$P_MAIN" worker
assert_refusal p1b "P1b bad provider name" "provider_unavailable"
mkstub p2 'exit 0'; cp "$TMP/stub-p2/$CLI" "$TMP/stub-p2/claude"
run_write p2 claude worker
assert_refusal p2 "P2 provider claude" "write_claude_is_task_path"
mkstub p3 'exit 0'
run_write p3 "$P_NG" worker
assert_refusal p3 "P3 no read grant" "provider_not_granted"
mkstub p4 'exit 0'
run_write p4 "$P_MAIN" heal_fix
assert_refusal p4 "P4 read grant, no write grant for the seat" "write_not_granted"
mkstub p5 'exit 0'
run_write p5 "$P_NP" worker
assert_refusal p5 "P5 no provider_write_argv" "write_unpinnable"
mkstub p6 'exit 0'
printf 'x\n' > "$WT/untracked.txt"
run_write p6 "$P_MAIN" worker
assert_refusal p6 "P6 untracked file" "write_tree_dirty"
assert_eq "P6 the caller's untracked file is untouched" "x" "$(cat "$WT/untracked.txt" 2>/dev/null)"
rm -f "$WT/untracked.txt"
mkstub p6b 'exit 0'
printf 'caller edit\n' > "$WT/src.txt"
run_write p6b "$P_MAIN" worker
assert_refusal p6b "P6b modified tracked file" "write_tree_dirty"
assert_eq "P6b the caller's edit is untouched" "caller edit" "$(cat "$WT/src.txt")"
reset_wt
mkdir -p "$WT/.claude"
mkstub p7 'exit 0'
printf '{}\n' > "$WT/.claude/settings.local.json"
run_write p7 "$P_MAIN" worker
assert_refusal p7 "P7 settings.local.json present (gitignored)" "write_repo_settings_present"
rm -f "$WT/.claude/settings.local.json"
mkstub p7b 'exit 0'
printf '%s\n' '{"permissions":{"allow":["Bash"]}}' > "$WT/.claude/settings.json"
run_write p7b "$P_MAIN" worker
assert_refusal p7b "P7b settings.json with a permissions key" "write_repo_settings_present"
mkstub p7c 'exit 0'
printf '%s\n' '{"env":{"A":"b"}}' > "$WT/.claude/settings.json"
run_write p7c "$P_MAIN" worker
assert_eq "P7c settings.json without permissions launches (ok)" "ok:yes" "$(jf p7c .write_status):$(ran p7c)"
rm -rf "$WT/.claude"
assert_eq "P the tree is clean after every refusal" "" "$(tree_state)"

echo ""
echo "==== U: usage errors exit 2 ===="
u_rc() { local rc=0; bash "$WRITE" "$@" >/dev/null 2>&1 || rc=$?; echo "$rc"; }
assert_eq "U missing --out" "2" "$(u_rc --provider "$P_MAIN" --seat worker --worktree "$WT" --prompt "$PROMPT")"
assert_eq "U a read seat is not a write seat" "2" "$(u_rc --provider "$P_MAIN" --seat red_team --worktree "$WT" --prompt "$PROMPT" --out "$TMP/u.json")"
assert_eq "U a home-mode flag is refused" "2" "$(u_rc --provider "$P_MAIN" --seat worker --worktree "$WT" --prompt "$PROMPT" --out "$TMP/u.json" --home shell)"
assert_eq "U a worktree subdir is refused" "2" "$(u_rc --provider "$P_MAIN" --seat worker --worktree "$WT/sub" --prompt "$PROMPT" --out "$TMP/u.json")"
assert_eq "U --restore with a non-hex sha" "2" "$(u_rc --restore 'HEAD~1' --worktree "$WT")"

echo ""
echo "==== S: the CLI is started only through launch_provider_cli isolated ===="
assert_eq "S no 'launch_provider_cli shell' in write-run.sh" "0" "$(grep -c 'launch_provider_cli shell' "$WRITE")"
assert_eq "S a 'launch_provider_cli isolated' call is present" "1" "$(grep -cE '^[[:space:]]*if ! launch_provider_cli isolated ' "$WRITE")"
mkstub s1 "printf '%s\\n' \"\$HOME\" > $(printf '%q' "$TMP/s1.home")"
run_write s1 "$P_MAIN" worker
S1_HOME="$(cat "$TMP/s1.home" 2>/dev/null)"
assert_eq "S the stub ran with a HOME that is not the caller's" "ok:yes:1" \
  "$(jf s1 .write_status):$(ran s1):$( [ -n "$S1_HOME" ] && [ "$S1_HOME" != "$HOME" ] && echo 1 || echo 0)"

echo ""
echo "==== O: ok keeps the edits; --restore cleans; --restore refused when HEAD moved ===="
mkstub o1 "printf 'provider edit\\n' > src.txt" "printf 'new\\n' > new.txt" \
  "printf '%s\\n' '{\"write_status\":\"write_git_tampered\"}'"
run_write o1 "$P_MAIN" worker LOOMWRIGHT_WRITE_DEBUG_TIMEOUT_FILE="$TMP/o1.timeout"
assert_eq "O1 rc 0, ok (reply text ignored)" "0:ok" "$RC:$(jf o1 .write_status)"
assert_eq "O1 changed_files lists the edits" '["new.txt","src.txt"]' "$(jfc o1 .changed_files)"
assert_eq "O1 tree_restored false, no notes" "false:false" "$(jf o1 .tree_restored):$(jf o1 'has("notes")')"
assert_eq "O1 the edits stay" "provider edit" "$(cat "$WT/src.txt")"
assert_eq "O1 default timeout 420" "420" "$(cat "$TMP/o1.timeout" 2>/dev/null)"
RESTORE_OUT="$(bash "$WRITE" --restore "$PRE" --worktree "$WT" 2>/dev/null)"; RRC=$?
assert_eq "O2 --restore rc 0, one JSON line, ok" "0:ok:true" \
  "$RRC:$(printf '%s' "$RESTORE_OUT" | jq -r .restore_status):$(printf '%s' "$RESTORE_OUT" | jq -r .tree_restored)"
assert_eq "O2 the tree is clean after --restore (untracked file removed)" "" "$(tree_state)"
assert_eq "O2 src.txt back to the commit" "original" "$(cat "$WT/src.txt")"
printf 'moved\n' > "$WT/README.txt"
git -C "$WT" commit -q -am "caller commit"
printf 'keep\n' > "$WT/keep.txt"
MOVED="$(git -C "$WT" rev-parse HEAD)"
RESTORE_OUT="$(bash "$WRITE" --restore "$PRE" --worktree "$WT" 2>/dev/null)"; RRC=$?
assert_eq "O3 --restore refused when HEAD moved" "0:restore_head_moved:false" \
  "$RRC:$(printf '%s' "$RESTORE_OUT" | jq -r .restore_status):$(printf '%s' "$RESTORE_OUT" | jq -r .tree_restored)"
assert_eq "O3 nothing changed (HEAD, untracked file)" "$MOVED:keep" "$(git -C "$WT" rev-parse HEAD):$(cat "$WT/keep.txt" 2>/dev/null)"
reset_wt

echo ""
echo "==== C: a commit made by the provider ===="
mkstub c1 "printf 'committed\\n' > src.txt" "git add -A" \
  "git -c user.name=p -c user.email=p@example.invalid -c commit.gpgsign=false commit -q -m provider"
run_write c1 "$P_MAIN" worker
assert_eq "C1 write_git_tampered, tree_restored true" "write_git_tampered:true" "$(jf c1 .write_status):$(jf c1 .tree_restored)"
assert_has "C1 notes name head" "$(jf c1 .notes)" "head [HEAD]"
assert_has "C1 notes name the own branch ref" "$(jf c1 .notes)" "refs/heads/feat"
assert_eq "C1 HEAD and the branch back at the pre-launch commit" "$PRE:$PRE" \
  "$(git -C "$WT" rev-parse HEAD):$(git -C "$WT" rev-parse refs/heads/feat)"
assert_eq "C1 the committed edit is gone, tree clean" "original:" "$(cat "$WT/src.txt"):$(tree_state)"
assert_eq "C1 changed_files names the committed file" '["src.txt"]' "$(jfc c1 .changed_files)"
reset_wt

echo ""
echo "==== H: a hook planted in the common hooks dir; a planted core.hooksPath ===="
mkstub h1 'd="$(git rev-parse --git-common-dir)"' 'mkdir -p "$d/hooks"' \
  "printf '#!/bin/sh\\necho pwned\\n' > \"\$d/hooks/post-commit\"" 'chmod +x "$d/hooks/post-commit"'
run_write h1 "$P_MAIN" worker
assert_eq "H1 write_git_tampered, tree_restored true" "write_git_tampered:true" "$(jf h1 .write_status):$(jf h1 .tree_restored)"
assert_has "H1 notes name the hook" "$(jf h1 .notes)" "hooks/post-commit"
assert_eq "H1 the planted hook is removed" "absent" "$( [ -e "$COMMON/hooks/post-commit" ] && echo present || echo absent)"
mkstub h2 'git config core.hooksPath /tmp/loomwright-evil-hooks'
run_write h2 "$P_MAIN" worker
assert_eq "H2 write_git_tampered, tree_restored true" "write_git_tampered:true" "$(jf h2 .write_status):$(jf h2 .tree_restored)"
assert_has "H2 notes name the config key" "$(jf h2 .notes)" "core.hookspath"
assert_eq "H2 notes never carry the value" "0" "$(jf h2 .notes | grep -c 'loomwright-evil-hooks')"
assert_eq "H2 core.hooksPath restored (unset)" "" "$(git -C "$WT" config --get core.hooksPath)"
reset_wt

echo ""
echo "==== B: a sibling worktree's branch commits during the launch ===="
SIB_BEFORE="$(git -C "$SIB" rev-parse HEAD)"
mkstub b1 "printf 'edit\\n' > src.txt" \
  "git -C $(printf '%q' "$SIB") -c user.name=s -c user.email=s@example.invalid -c commit.gpgsign=false commit -q --allow-empty -m sibling"
run_write b1 "$P_MAIN" worker
assert_eq "B1 the sibling branch moved during the launch" "1" "$( [ "$(git -C "$SIB" rev-parse HEAD)" != "$SIB_BEFORE" ] && echo 1 || echo 0)"
assert_eq "B1 still ok" "ok" "$(jf b1 .write_status)"
reset_wt

echo ""
echo "==== T: partial edits on a timeout are restored ===="
mkstub t1 "printf 'partial\\n' > src.txt" "printf 'half\\n' > partial.txt" 'sleep 120'
T_START="$(date +%s)"
run_write t1 "$P_MAIN" worker LOOMWRIGHT_WRITE_CLI_TIMEOUT=3 LOOMWRIGHT_WRITE_DEBUG_TIMEOUT_FILE="$TMP/t1.timeout"
T_ELAPSED=$(( $(date +%s) - T_START ))
assert_eq "T1 write_timeout, tree_restored true" "write_timeout:true" "$(jf t1 .write_status):$(jf t1 .tree_restored)"
assert_eq "T1 the short bound was used" "3" "$(cat "$TMP/t1.timeout" 2>/dev/null)"
assert_eq "T1 returned well inside the stub's sleep (${T_ELAPSED}s < 30s)" "1" "$( [ "$T_ELAPSED" -lt 30 ] && echo 1 || echo 0)"
assert_eq "T1 partial edits gone, tree clean" "original:" "$(cat "$WT/src.txt"):$(tree_state)"
assert_eq "T1 changed_files names the partial edits" '["partial.txt","src.txt"]' "$(jfc t1 .changed_files)"
reset_wt

echo ""
echo "==== K: the timeout default and the 480 clamp ===="
mkstub k1 'exit 0'
for kv in "9999:480" "481:480" "480:480" "00060:60" "abc:420" "0:420" ":420"; do
  rm -f "$TMP/k.timeout"
  run_write k1 "$P_MAIN" worker LOOMWRIGHT_WRITE_CLI_TIMEOUT="${kv%%:*}" LOOMWRIGHT_WRITE_DEBUG_TIMEOUT_FILE="$TMP/k.timeout"
  assert_eq "K LOOMWRIGHT_WRITE_CLI_TIMEOUT='${kv%%:*}' -> ${kv#*:}s" "${kv#*:}" "$(cat "$TMP/k.timeout" 2>/dev/null)"
done

echo ""
echo "==== F: a CLI exiting non-zero ===="
mkstub f1 "printf 'broken\\n' > src.txt" "printf 'ok\\n'" 'exit 3'
run_write f1 "$P_MAIN" worker
assert_eq "F1 write_failed, tree_restored true (reply ignored)" "write_failed:true" "$(jf f1 .write_status):$(jf f1 .tree_restored)"
assert_has "F1 notes name the exit status" "$(jf f1 .notes)" "exited 3"
assert_eq "F1 the edit is gone" "original:" "$(cat "$WT/src.txt"):$(tree_state)"
reset_wt

echo ""
echo "==== R: a restore that cannot complete is write_git_tampered, tree_restored false ===="
if [ "$(id -u)" = "0" ]; then
  ok "R1 skipped: running as root, a read-only dir cannot block the restore"
else
  mkstub r1 "printf 'changed\\n' > sub/a.txt" 'chmod 555 sub' 'exit 3'
  run_write r1 "$P_MAIN" worker
  assert_eq "R1 write_git_tampered, tree_restored false" "write_git_tampered:false" "$(jf r1 .write_status):$(jf r1 .tree_restored)"
  assert_has "R1 notes say restored: false" "$(jf r1 .notes)" "restored: false"
  reset_wt
fi
assert_eq "R the tree is clean after the suite's own reset" "" "$(tree_state)"

echo ""
echo "==== G: a redirected commondir or a planted filter driver never runs during the restore ===="
# G1: the provider copies the common dir, gives the copy a smudge/clean filter
# bound to every path, edits a tracked file and points this worktree's
# commondir file at the copy. git would load the copy's config on the restore's
# reset; the pinned, pointer-first restore must not.
PWN_G1="$TMP/pwned-g1"
EVIL_G1="$TMP/evil-common-g1"
mkstub g1 'gd="$(git rev-parse --absolute-git-dir)"' 'cd_="$(cd "$(git rev-parse --git-common-dir)" && pwd -P)"' \
  "cp -R \"\$cd_\" $(printf '%q' "$EVIL_G1")" \
  "git config --file $(printf '%q' "$EVIL_G1/config") filter.pw.smudge $(printf '%q' "touch $PWN_G1; cat")" \
  "git config --file $(printf '%q' "$EVIL_G1/config") filter.pw.clean $(printf '%q' "touch $PWN_G1; cat")" \
  "mkdir -p $(printf '%q' "$EVIL_G1/info")" "printf '* filter=pw\\n' > $(printf '%q' "$EVIL_G1/info/attributes")" \
  "printf 'evil\\n' > src.txt" "printf '%s\\n' $(printf '%q' "$EVIL_G1") > \"\$gd/commondir\"" 'exit 3'
G1_COMMONDIR_BEFORE="$(cat "$(git -C "$WT" rev-parse --absolute-git-dir)/commondir")"
run_write g1 "$P_MAIN" worker
assert_eq "G1 write_git_tampered, tree_restored true" "write_git_tampered:true" "$(jf g1 .write_status):$(jf g1 .tree_restored)"
assert_has "G1 notes name the redirected common dir" "$(jf g1 .notes)" "commondir"
assert_eq "G1 the planted filter never ran during the restore" "absent" "$( [ -e "$PWN_G1" ] && echo present || echo absent)"
assert_eq "G1 the commondir file is back" "$G1_COMMONDIR_BEFORE" "$(cat "$(git -C "$WT" rev-parse --absolute-git-dir)/commondir")"
assert_eq "G1 git resolves the real common dir again" "$COMMON" "$(cd "$WT" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"
assert_eq "G1 the edit is gone, tree clean" "original:" "$(cat "$WT/src.txt"):$(tree_state)"
git -C "$WT" status --porcelain >/dev/null 2>&1
assert_eq "G1 the owner's next git status runs no planted filter" "absent" "$( [ -e "$PWN_G1" ] && echo present || echo absent)"
reset_wt

# G2: no redirect — a filter driver in the real config plus an in-tree
# .gitattributes binding every path to it. The config goes back before reset.
PWN_G2="$TMP/pwned-g2"
mkstub g2 "git config filter.pw.smudge $(printf '%q' "touch $PWN_G2; cat")" \
  "git config filter.pw.clean $(printf '%q' "touch $PWN_G2; cat")" \
  "printf '* filter=pw\\n' > .gitattributes" "printf 'evil\\n' > src.txt" 'exit 3'
run_write g2 "$P_MAIN" worker
assert_eq "G2 write_git_tampered, tree_restored true" "write_git_tampered:true" "$(jf g2 .write_status):$(jf g2 .tree_restored)"
assert_has "G2 notes name the filter key" "$(jf g2 .notes)" "filter.pw.smudge"
assert_eq "G2 the planted filter never ran" "absent" "$( [ -e "$PWN_G2" ] && echo present || echo absent)"
assert_eq "G2 the filter config is gone" "" "$(git -C "$WT" config --get filter.pw.smudge)"
assert_eq "G2 .gitattributes and the edit are gone, tree clean" "original:" "$(cat "$WT/src.txt"):$(tree_state)"
reset_wt

# G3: the same filter in config, info/attributes in the real common dir (no
# tree file at all): the restore puts both back before the reset.
PWN_G3="$TMP/pwned-g3"
mkstub g3 'cd_="$(git rev-parse --git-common-dir)"' \
  "git config filter.pw.smudge $(printf '%q' "touch $PWN_G3; cat")" \
  "git config filter.pw.clean $(printf '%q' "touch $PWN_G3; cat")" \
  'mkdir -p "$cd_/info"' "printf '* filter=pw\\n' > \"\$cd_/info/attributes\"" "printf 'evil\\n' > src.txt" 'exit 3'
run_write g3 "$P_MAIN" worker
assert_eq "G3 write_git_tampered, tree_restored true" "write_git_tampered:true" "$(jf g3 .write_status):$(jf g3 .tree_restored)"
assert_has "G3 notes name info/attributes" "$(jf g3 .notes)" "info/attributes"
assert_eq "G3 the planted filter never ran" "absent" "$( [ -e "$PWN_G3" ] && echo present || echo absent)"
assert_eq "G3 info/attributes removed" "absent" "$( [ -e "$COMMON/info/attributes" ] && echo present || echo absent)"
reset_wt

# G4: a redirect the restore cannot undo (the commondir file and the git dir
# made read-only after the write) runs NO index or tree command: changed_files [], tree left.
if [ "$(id -u)" = "0" ]; then
  ok "G4 skipped: running as root, a read-only dir cannot block the restore"
else
  PWN_G4="$TMP/pwned-g4"
  EVIL_G4="$TMP/evil-common-g4"
  G4_GD="$(git -C "$WT" rev-parse --absolute-git-dir)"
  mkstub g4 'gd="$(git rev-parse --absolute-git-dir)"' 'cd_="$(cd "$(git rev-parse --git-common-dir)" && pwd -P)"' \
    "cp -R \"\$cd_\" $(printf '%q' "$EVIL_G4")" \
    "git config --file $(printf '%q' "$EVIL_G4/config") filter.pw.smudge $(printf '%q' "touch $PWN_G4; cat")" \
    "git config --file $(printf '%q' "$EVIL_G4/config") filter.pw.clean $(printf '%q' "touch $PWN_G4; cat")" \
    "mkdir -p $(printf '%q' "$EVIL_G4/info")" "printf '* filter=pw\\n' > $(printf '%q' "$EVIL_G4/info/attributes")" \
    "printf 'evil\\n' > src.txt" "printf '%s\\n' $(printf '%q' "$EVIL_G4") > \"\$gd/commondir\"" 'chmod 444 "$gd/commondir"' 'chmod 555 "$gd"' 'exit 3'
  run_write g4 "$P_MAIN" worker
  assert_eq "G4 write_git_tampered, tree_restored false" "write_git_tampered:false" "$(jf g4 .write_status):$(jf g4 .tree_restored)"
  assert_eq "G4 changed_files not measured" "[]" "$(jfc g4 .changed_files)"
  assert_has "G4 notes say no index or tree command ran" "$(jf g4 .notes)" "no index or tree command was run"
  assert_eq "G4 the planted filter never ran" "absent" "$( [ -e "$PWN_G4" ] && echo present || echo absent)"
  chmod u+rwx "$G4_GD"; chmod u+rw "$G4_GD/commondir"
  printf '%s\n' "$G1_COMMONDIR_BEFORE" > "$G4_GD/commondir"
  reset_wt
fi

echo ""
echo "==== W: a provider edit to a path the test-integrity guard protects ===="
mkstub w1 "printf 'edit\\n' > src.txt" "printf '[pytest]\\n' > pytest.ini"
run_write w1 "$P_MAIN" worker LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS=1
assert_eq "W1 write_protected_path, tree_restored true (opt-out env not honoured)" "write_protected_path:true" \
  "$(jf w1 .write_status):$(jf w1 .tree_restored)"
assert_has "W1 notes name the protected path" "$(jf w1 .notes)" "pytest.ini"
assert_eq "W1 changed_files lists both paths" '["pytest.ini","src.txt"]' "$(jfc w1 .changed_files)"
assert_eq "W1 the edits are gone, tree clean" "original:" "$(cat "$WT/src.txt"):$(tree_state)"
reset_wt
mkstub w2 "mkdir -p .husky" "printf 'exit 0\\n' > .husky/pre-commit"
run_write w2 "$P_MAIN" worker
assert_eq "W2 a .husky/ file is protected too" "write_protected_path:true" "$(jf w2 .write_status):$(jf w2 .tree_restored)"
reset_wt

echo ""
echo "==== X: provider-authored ignore rules hide nothing from detection or restore ===="
# A pre-existing ignored file (the repo's info/exclude ignores ignored-cache/) must
# survive every restore below; only paths absent from the launch snapshot go.
mkdir -p "$WT/ignored-cache"; printf 'keep\n' > "$WT/ignored-cache/pre-existing.txt"
ut_all() { git -C "$WT" ls-files --others 2>/dev/null | tr '\n' ' ' | sed 's/ $//'; }
# X1: an ok launch that plants sub/.gitignore ('*', which also ignores itself)
# next to a guard-protected sub/pytest.ini.
mkstub x1 "printf 'edit\\n' > src.txt" "printf '*\\n' > sub/.gitignore" "printf '[pytest]\\n' > sub/pytest.ini" \
  "printf 'x\\n' > ignored-cache/new-in-ignored-dir.txt"
run_write x1 "$P_MAIN" worker
assert_eq "X1 write_protected_path, tree_restored true" "write_protected_path:true" "$(jf x1 .write_status):$(jf x1 .tree_restored)"
assert_has "X1 notes name the guard-protected file" "$(jf x1 .notes)" "sub/pytest.ini"
assert_has "X1 notes name the planted .gitignore" "$(jf x1 .notes)" "sub/.gitignore"
assert_eq "X1 changed_files lists the ignored new files too" \
  '["ignored-cache/new-in-ignored-dir.txt","src.txt","sub/.gitignore","sub/pytest.ini"]' "$(jfc x1 .changed_files)"
assert_eq "X1 neither planted file is left" "absent:absent" \
  "$( [ -e "$WT/sub/.gitignore" ] && echo present || echo absent):$( [ -e "$WT/sub/pytest.ini" ] && echo present || echo absent)"
assert_eq "X1 only the pre-existing ignored file remains untracked" "ignored-cache/pre-existing.txt" "$(ut_all)"
assert_eq "X1 the edit is gone, tree clean" "original:" "$(cat "$WT/src.txt"):$(tree_state)"
# X1b: a .gitignore alone (no protected path) still never stays on ok.
mkstub x1b "printf 'edit\\n' > src.txt" "printf 'hidden.txt\\n' > .gitignore" "printf 'h\\n' > hidden.txt"
run_write x1b "$P_MAIN" worker
assert_eq "X1b a new .gitignore reads write_protected_path, restored" "write_protected_path:true" "$(jf x1b .write_status):$(jf x1b .tree_restored)"
assert_eq "X1b changed_files lists the hidden file" '[".gitignore","hidden.txt","src.txt"]' "$(jfc x1b .changed_files)"
assert_eq "X1b only the pre-existing ignored file remains untracked" "ignored-cache/pre-existing.txt" "$(ut_all)"
# X2: a non-ok launch (exit 3) that plants the same .gitignore plus a conftest.
mkstub x2 "printf 'edit\\n' > src.txt" "printf '*\\n' > sub/.gitignore" "printf 'x = 1\\n' > sub/conftest.py" 'exit 3'
run_write x2 "$P_MAIN" worker
assert_eq "X2 write_failed, tree_restored true" "write_failed:true" "$(jf x2 .write_status):$(jf x2 .tree_restored)"
assert_eq "X2 changed_files lists the ignored new files" '["src.txt","sub/.gitignore","sub/conftest.py"]' "$(jfc x2 .changed_files)"
assert_eq "X2 neither planted file is left" "absent:absent" \
  "$( [ -e "$WT/sub/.gitignore" ] && echo present || echo absent):$( [ -e "$WT/sub/conftest.py" ] && echo present || echo absent)"
assert_eq "X2 the pre-existing ignored file is untouched" "keep:ignored-cache/pre-existing.txt" "$(cat "$WT/ignored-cache/pre-existing.txt" 2>/dev/null):$(ut_all)"
# X3: a new nested repository under an ignored dir is never removed (it may be
# another process's worktree); the restore then reads incomplete, never true.
mkstub x3 "mkdir -p ignored-cache/nested" "git -C ignored-cache/nested init -q" "printf 'n\\n' > ignored-cache/nested/f.txt" 'exit 3'
run_write x3 "$P_MAIN" worker
assert_eq "X3 write_git_tampered, tree_restored false" "write_git_tampered:false" "$(jf x3 .write_status):$(jf x3 .tree_restored)"
assert_has "X3 notes name the nested repository left in place" "$(jf x3 .notes)" "ignored-cache/nested/"
assert_eq "X3 the nested repository is left" "present" "$( [ -e "$WT/ignored-cache/nested/f.txt" ] && echo present || echo absent)"
rm -rf "$WT/ignored-cache"
reset_wt

echo ""
echo "==== Y: a path holding a newline never forges a line of a listing ===="
# Y1: a pre-existing nested repo under the ignored dir (the snapshot lists only
# its `dir/` line). The provider makes a dir named "q<LF>ignored-cache/nestedpre"
# holding keep.txt: split on the newline, the listing would carry the forged
# line ignored-cache/nestedpre/keep.txt and the restore would delete it.
mkdir -p "$WT/ignored-cache/nestedpre"; git -C "$WT/ignored-cache/nestedpre" init -q
printf 'keep\n' > "$WT/ignored-cache/nestedpre/keep.txt"
mkstub y1 "d=\$'q\\nignored-cache/nestedpre'" 'mkdir -p "$d"' "printf 'x\\n' > \"\$d/keep.txt\"" 'exit 3'
run_write y1 "$P_MAIN" worker
assert_eq "Y1 the pre-existing file inside the nested repo survives" "keep" "$(cat "$WT/ignored-cache/nestedpre/keep.txt" 2>/dev/null)"
assert_eq "Y1 changed_files never names the forged path" "false" "$(jf y1 '.changed_files | index("ignored-cache/nestedpre/keep.txt") != null')"
Y1_LEFT="$(cd "$WT" && ls -d q* 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "Y1 tree_restored true only when the newline dir is really gone" \
  "$(jf y1 .tree_restored)" "$( [ "$Y1_LEFT" = "0" ] && echo true || echo false)"
assert_eq "Y1 the run is not ok" "false" "$(jf y1 '.write_status == "ok"')"
(cd "$WT" && rm -rf q*)
rm -rf "$WT/ignored-cache"
reset_wt
# Y2: a pre-existing ignored symlink ignored-cache/ext pointing OUTSIDE the
# tree; the dir "q<LF>ignored-cache/ext" holding victim.txt would forge the line
# ignored-cache/ext/victim.txt, and `rm` would follow the link out of the tree.
mkdir -p "$TMP/y2-outside" "$WT/ignored-cache"; printf 'outside\n' > "$TMP/y2-outside/victim.txt"
ln -s "$TMP/y2-outside" "$WT/ignored-cache/ext"
mkstub y2 "d=\$'q\\nignored-cache/ext'" 'mkdir -p "$d"' "printf 'x\\n' > \"\$d/victim.txt\"" 'exit 3'
run_write y2 "$P_MAIN" worker
assert_eq "Y2 the file outside the tree survives" "outside" "$(cat "$TMP/y2-outside/victim.txt" 2>/dev/null)"
assert_eq "Y2 the pre-existing ignored symlink survives" "present" "$( [ -L "$WT/ignored-cache/ext" ] && echo present || echo absent)"
Y2_LEFT="$(cd "$WT" && ls -d q* 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "Y2 tree_restored true only when the newline dir is really gone" \
  "$(jf y2 .tree_restored)" "$( [ "$Y2_LEFT" = "0" ] && echo true || echo false)"
(cd "$WT" && rm -rf q*)
rm -rf "$WT/ignored-cache"
reset_wt
# Y3: the diff listing. An ok launch adds an intent-to-add file named
# "z<LF>src.txt": split, it would read as the unprotected src.txt plus "z" and
# stay; a newline in the listing reads as "cannot judge" instead.
mkstub y3 "f=\$'z\\nsrc.txt'" "printf 'x\\n' > \"\$f\"" 'git add -N "$f"'
run_write y3 "$P_MAIN" worker
assert_eq "Y3 an unjudgeable diff listing is never ok" "false" "$(jf y3 '.write_status == "ok"')"
assert_has "Y3 notes say the files could not be listed" "$(jf y3 .notes)" "could not be listed"
Y3_LEFT="$(cd "$WT" && ls -d z* 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "Y3 the newline-named file is not kept" "0" "$Y3_LEFT"
assert_eq "Y3 tree_restored true, tree clean" "true:" "$(jf y3 .tree_restored):$(tree_state)"
(cd "$WT" && rm -rf z*)
git -C "$WT" reset -q 2>/dev/null
reset_wt

echo ""
echo "==== SB: a sibling's launch snapshot never re-plants what the first run's restore removed ===="
# A plants a hook and fails after a while; B launches in the sibling worktree
# while A runs (so B's own snapshot would hold A's hook) and fails after A's
# restore. B restores the shared files from the baseline A published.
git -C "$SIB" reset -q --hard; git -C "$SIB" clean -q -ffd
mkstub sba 'd="$(git rev-parse --git-common-dir)"' 'mkdir -p "$d/hooks"' \
  "printf '#!/bin/sh\\necho pwned\\n' > \"\$d/hooks/pre-commit\"" 'chmod +x "$d/hooks/pre-commit"' 'sleep 6' 'exit 3'
mkstub sbb 'sleep 10' 'exit 3'
( env PATH="$TMP/stub-sba:$PATH" bash "$WRITE" --provider "$P_MAIN" --seat worker \
    --worktree "$WT" --prompt "$PROMPT" --out "$TMP/out-sba.json" >/dev/null 2>&1 ) &
SBA_PID=$!
# B launches only once A's CLI has planted the hook (A registered before it
# launched), so B is the overlapping run whatever the machine's speed.
for _i in $(seq 1 150); do [ -x "$COMMON/hooks/pre-commit" ] && break; sleep 0.2; done
env PATH="$TMP/stub-sbb:$PATH" bash "$WRITE" --provider "$P_MAIN" --seat worker \
  --worktree "$SIB" --prompt "$PROMPT" --out "$TMP/out-sbb.json" >/dev/null 2>&1
wait "$SBA_PID"
assert_eq "SB A tampered and restored" "write_git_tampered:true" "$(jf sba .write_status):$(jf sba .tree_restored)"
assert_eq "SB B saw the shared change, restored from the baseline" "write_git_tampered:true" "$(jf sbb .write_status):$(jf sbb .tree_restored)"
assert_eq "SB the planted hook is not re-planted" "absent" "$( [ -e "$COMMON/hooks/pre-commit" ] && echo present || echo absent)"
assert_eq "SB the registry is removed by the last run out" "absent" "$( [ -e "$COMMON/loomwright-write-runs" ] && echo present || echo absent)"
reset_wt

echo ""
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && exit 0 || exit 1
