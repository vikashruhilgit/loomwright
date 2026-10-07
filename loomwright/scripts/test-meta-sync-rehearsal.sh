#!/usr/bin/env bash
# test-meta-sync-rehearsal.sh — self-tests for meta-sync-rehearsal.sh.
# Hermetic: every fixture is a bare `origin.git` plus a `src` clone inside one mktemp -d (never
# GitHub), HOME and git identity are sandboxed, and the harness always runs with --root on a
# fixture — never against the checkout running the test. The harness brings its own gh stub.
# Exit 0 = all pass. Run it under /bin/bash on macOS too.
#
# Covers:
#   1. history fixture (tracked run history + an untracked file + a provenanced twin contract):
#      every named check PASSes, exit 0; the fixture's refs, remotes and origin are unchanged
#      (no metadata branch reaches the real remote) and the scratch dir is removed
#   2. --no-config: exit 0 and the deny config is not carried; with the config a planted deny
#      pattern turns `push` red, --no-config does not see it
#   3. fresh fixture (no tracked run history; fewer than two .md files -> synthetic seeds): exit 0
#   4. usage: an invalid branch name -> exit 2; a detached HEAD -> exit 1; already in branch mode
#      -> FAIL scratch-mode-off, exit 1
#   5. mutation controls — each check goes red under its mutant (and the run exits 1):
#      a dropped file (verify-present), a changed blob (verify-blobs), the old M1 rollback order
#      (rollback-edit-kept), a contract without provenance (twin-contracts)
#   6. half-migrated checkout (mode line `on <b>` committed, run history still tracked): the scratch
#      clone is reset to off, every check passes, the real remote is untouched; a mode line naming
#      ANOTHER branch -> FAIL scratch-mode-off; mutation control: without the reset the half-migrated
#      run goes red at scratch-mode-off

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/meta-sync-rehearsal.sh"
SCRIPT="$SUT"
BR="team-meta"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }
check() { if [ "$1" -eq 0 ]; then ok "$2"; else no "$2"; fi; }

TROOT="$(mktemp -d)"
trap 'rm -rf "$TROOT"' EXIT
export HOME="$TROOT/home"; mkdir -p "$HOME"
export TMPDIR="$TROOT/tmp"; mkdir -p "$TMPDIR"
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=tester GIT_AUTHOR_EMAIL=tester@test.invalid
export GIT_COMMITTER_NAME=tester GIT_COMMITTER_EMAIL=tester@test.invalid
export LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="owner/repo"

CHECKS="scratch-remote scratch-mode-off init push verify-present verify-blobs verify-nothing-extra verify-types migrate-clean pull-roundtrip rollback-run rollback-edit-kept rollback-add-kept rollback-delete-kept rollback-all-kept rollback-gitignore twin-contracts source-untouched"

# ---- fixtures ------------------------------------------------------------------------------------
W=""
# mkworld [fresh] — bare origin + `src` clone on main (.supervisor/ ignored). Default (history):
# run history force-tracked plus one UNTRACKED managed file, a provenanced twin contract and a
# deny config. fresh: one untracked managed file only.
mkworld() {
  W="$(mktemp -d "$TROOT/w.XXXXXX")"
  git init -q --bare "$W/origin.git"
  git --git-dir="$W/origin.git" symbolic-ref HEAD refs/heads/main
  git init -q "$W/src"
  (
    cd "$W/src" || exit 1
    git symbolic-ref HEAD refs/heads/main
    printf '.supervisor/\n' > .gitignore; echo code > app.txt
    git add .gitignore app.txt
    if [ "${1:-}" != fresh ]; then
      mkdir -p .supervisor/requirements/q .supervisor/jobs/done .agent
      echo '# req' > .supervisor/requirements/q/req.md
      echo '# a v1' > .supervisor/jobs/done/a.md; echo '# b' > .supervisor/jobs/done/b.md
      printf 'FORBIDDEN-MARKER\n' > .agent/meta-sync-deny.txt
      git add -f .supervisor .agent
    fi
    git commit -qm code
    git remote add origin "$W/origin.git" && git push -q origin main
    mkdir -p .supervisor/jobs/done; echo '# c untracked' > .supervisor/jobs/done/c.md
    if [ "${1:-}" != fresh ]; then
      printf 'SYSTEM_CONTRACT: app\ninvariants: [prints code]\n' | bash "$HERE/write-system-contract.sh" --subsystem app --source "session:fixture-0001" >/dev/null 2>&1
    fi
  )
}
fp() { git -C "$W/src" for-each-ref --format='%(refname) %(objectname)'; git -C "$W/src" config --get-regexp '^remote\.'; git --git-dir="$W/origin.git" for-each-ref --format='%(refname) %(objectname)'; }
run() { OUT="$(bash "$SCRIPT" --root "$W/src" "$@" 2>&1)"; RC=$?; }
has() { grep -qF -- "$1" <<<"$OUT"; }
all_pass() { local c; for c in $CHECKS; do grep -qx "PASS: $c" <<<"$OUT" || { echo "    missing PASS: $c"; return 1; }; done; ! grep -q '^FAIL' <<<"$OUT"; }
red() { grep -q "^FAIL: $1\( \|$\)" <<<"$OUT"; }
scratch_gone() { local d; d="$(printf '%s\n' "$OUT" | sed -n 's/^info: scratch \([^ ]*\) .*/\1/p')"; [ -n "$d" ] && [ ! -e "$d" ]; }

echo "== 1. history fixture: every check passes, the real remote is untouched =="
mkworld; FP0="$(fp)"
[ -f "$W/src/.supervisor/twin/contracts/app.md" ]; check $? "fixture: a provenanced twin contract exists"
run --branch "$BR"
all_pass; check $? "every named check PASSes (rc=$RC)"; [ "$RC" -eq 0 ] || printf '%s\n' "$OUT" | grep -E '^(FAIL|info)' | sed 's/^/    /'
[ "$RC" -eq 0 ]; check $? "exit 0 when every check passes"
[ "$(printf '%s\n' "$OUT" | grep -cE '^(PASS|FAIL): ')" = 18 ]; check $? "one PASS/FAIL line per check (18)"
[ "$FP0" = "$(fp)" ]; check $? "fixture refs, remotes and its origin are unchanged"
! git --git-dir="$W/origin.git" rev-parse -q --verify "refs/heads/$BR" >/dev/null; check $? "no metadata branch on the real remote"
[ -z "$(git -C "$W/src" status --porcelain)" ]; check $? "fixture working tree untouched"
scratch_gone; check $? "scratch dir removed on exit"
[ -z "$(ls "$TMPDIR" | grep meta-sync-rehearsal)" ]; check $? "nothing left under TMPDIR"

echo "== 2. --no-config =="
run --branch "$BR" --no-config
{ [ "$RC" -eq 0 ] && all_pass && has "config off"; }; check $? "--no-config: every check passes (rc=$RC)"
mkworld
( cd "$W/src" && echo 'FORBIDDEN-MARKER here' >> .supervisor/jobs/done/a.md && git commit -qam marker && git push -q origin main )
run --branch "$BR"
{ [ "$RC" -eq 1 ] && red push; }; check $? "with config: the deny pattern stops push (FAIL: push, rc=$RC)"
run --branch "$BR" --no-config
{ [ "$RC" -eq 0 ] && all_pass; }; check $? "--no-config: the deny config is not carried, every check passes (rc=$RC)"

echo "== 3. fresh fixture =="
mkworld fresh
run --branch "$BR"
{ [ "$RC" -eq 0 ] && all_pass && has "added two synthetic"; }; check $? "fresh: synthetic seeds, every check passes (rc=$RC)"

echo "== 4. usage and refusals =="
run --branch 'bad..name'; [ "$RC" -eq 2 ]; check $? "invalid branch name -> exit 2 (rc=$RC)"
git -C "$W/src" checkout -q --detach; run; [ "$RC" -eq 1 ] && has "detached"; check $? "detached HEAD -> exit 1"
git -C "$W/src" checkout -q main
( cd "$W/src" && bash "$HERE/setup-memory.sh" --root "$W/src" apply --branch-mode "$BR" >/dev/null 2>&1 && rm -f .gitignore.backup.* && git commit -qam mode && git push -q origin main )
run --branch "$BR"; { [ "$RC" -eq 1 ] && red scratch-mode-off && red init && ! has "info: half-migrated"; }; check $? "fully migrated (mode on, nothing tracked) -> FAIL scratch-mode-off, later checks not reached (rc=$RC)"

# ---- mutation controls ---------------------------------------------------------------------------
# build_mutant <dir> <file> <sed-script> <must-appear> — copies every sibling script, seds <file>
build_mutant() {
  mkdir -p "$1"; for f in "$HERE"/*; do [ -f "$f" ] && cp "$f" "$1/"; done
  sed -f "$3" "$HERE/$2" > "$1/$2" || return 1
  cmp -s "$HERE/$2" "$1/$2" && return 1
  grep -qF "$4" "$1/$2" || return 1
  bash -n "$1/$2" || return 1
}
mutant() { # mutant <name> <file> <marker> <red check> — sed script on stdin
  local d="$TROOT/mut-$1"; cat > "$TROOT/$1.sed"
  if build_mutant "$d" "$2" "$TROOT/$1.sed" "$3"; then
    mkworld; SCRIPT="$d/meta-sync-rehearsal.sh"; run --branch "$BR"; SCRIPT="$SUT"
    if [ "$RC" -eq 1 ] && red "$4"; then ok "mutation control: $1 turns '$4' red"; else no "mutation control REFUTED: $1 left '$4' green (rc=$RC)"; fi
  else no "mutation control ($1) did not build — counts as FAIL"; fi
}

echo "== 5. mutation controls =="
mutant dropped-file meta-sync.sh 'MUTANT-DROP' verify-present <<'SED'
s|^\( *\)GIT_INDEX_FILE="\$META_INDEX" g update-index --add --cacheinfo 100644 "\$l" "\$p" \|\| die "update-index failed for \$p"$|&; case "$p" in */b.md) GIT_INDEX_FILE="$META_INDEX" g update-index --force-remove -- "$p" ;; esac # MUTANT-DROP|
SED
mutant changed-blob meta-sync.sh 'MUTANT-BLOB' verify-blobs <<'SED'
s|^\( *\)GIT_INDEX_FILE="\$META_INDEX" g update-index --add --cacheinfo 100644 "\$l" "\$p" \|\| die "update-index failed for \$p"$|&; case "$p" in */a.md) GIT_INDEX_FILE="$META_INDEX" g update-index --add --cacheinfo 100644 "$(printf 'tampered\\n' \| g hash-object -w --stdin)" "$p" ;; esac # MUTANT-BLOB|
SED
mutant m1-rollback-order migrate-branch-mode.sh 'git add -u -- .supervisor' rollback-edit-kept <<'SED'
s|^  rb_retrack_from_branch "\$br_sha" \|\| |  bash "$MS" pull --branch "$b" --root "$ROOT"; (cd "$ROOT" \&\& git add -u -- .supervisor) \|\| |
SED
mkworld
printf 'SYSTEM_CONTRACT: rogue\ninvariants: [no provenance]\n' > "$W/src/.supervisor/twin/contracts/rogue.md"
run --branch "$BR"
{ [ "$RC" -eq 1 ] && red twin-contracts; }; check $? "mutation control: a contract without provenance turns 'twin-contracts' red (rc=$RC)"

echo "== 6. half-migrated checkout: mode line on <b>, run history still tracked =="
# half_world <b> — the history fixture with the branch-mode block for <b> committed and pushed while
# the run history stays tracked (the state setup-memory.sh apply --branch-mode alone leaves behind)
half_world() {
  mkworld
  ( cd "$W/src" && bash "$HERE/setup-memory.sh" --root "$W/src" apply --branch-mode "$1" >/dev/null 2>&1 && rm -f .gitignore.backup.* && git commit -qam mode && git push -q origin main )
}
half_world "$BR"; FP0="$(fp)"
[ "$(bash "$HERE/setup-memory.sh" --root "$W/src" mode)" = "on $BR" ] && [ -n "$(bash "$HERE/meta-sync.sh" list-managed --tracked --root "$W/src")" ]
check $? "fixture: mode line 'on $BR' with managed paths still tracked"
run --branch "$BR"
{ [ "$RC" -eq 0 ] && all_pass && has "info: half-migrated checkout"; }; check $? "half-migrated: scratch reset to off, every named check PASSes (rc=$RC)"
[ "$RC" -eq 0 ] || printf '%s\n' "$OUT" | grep -E '^(FAIL|info)' | sed 's/^/    /'
{ [ "$FP0" = "$(fp)" ] && ! git --git-dir="$W/origin.git" rev-parse -q --verify "refs/heads/$BR" >/dev/null && [ "$(bash "$HERE/setup-memory.sh" --root "$W/src" mode)" = "on $BR" ]; }
check $? "half-migrated: fixture refs, remotes, origin and mode line unchanged; no metadata branch on the real remote"
half_world other-meta
run --branch "$BR"; { [ "$RC" -eq 1 ] && red scratch-mode-off && red init && ! has "info: half-migrated"; }; check $? "mode line naming another branch -> FAIL scratch-mode-off, no reset (rc=$RC)"
cat > "$TROOT/no-reset.sed" <<'SED'
s|^if \[ "\$(bash "\$SM" --root "\$A" mode 2>/dev/null \| head -n 1)" = "on \$B" \] \\$|if false \&\& [ "$(bash "$SM" --root "$A" mode 2>/dev/null \| head -n 1)" = "on $B" ] \\|
SED
if build_mutant "$TROOT/mut-no-reset" meta-sync-rehearsal.sh "$TROOT/no-reset.sed" 'if false && [ "$(bash "$SM" --root "$A" mode'; then
  half_world "$BR"; SCRIPT="$TROOT/mut-no-reset/meta-sync-rehearsal.sh"; run --branch "$BR"; SCRIPT="$SUT"
  if [ "$RC" -eq 1 ] && red scratch-mode-off; then ok "mutation control: without the reset a half-migrated checkout goes red at scratch-mode-off"; else no "mutation control REFUTED: no-reset left scratch-mode-off green (rc=$RC)"; fi
else no "mutation control (no-reset) did not build — counts as FAIL"; fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
