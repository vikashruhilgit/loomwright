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
#   7. learning stores (af36-03) on the history fixture (its provenanced twin store): with NO consent
#      recorded under the scratch HOME every check PASSes and the learning stores stay off the
#      branch; with consent GRANTED for the fixture every check PASSes, both twin paths reach the
#      branch and round-trip byte-identical, and the caller's record is not written for the scratch
#      clone; mutation controls: verify-present over the FULL list goes red without consent,
#      verify-types without .provenance.jsonl goes red with consent
#   8. run history vs learning stores in the rehearsal's own `--tracked` / count reads (each pinned by
#      a mutant dropping its `--run-history` or its tracked-learning term):
#      a TRACKED learning store (.supervisor/eval/results.jsonl) stays tracked through the scratch
#      migration, so the second clone gets it through git: every check PASSes with consent none and
#      granted (pull-roundtrip expects it); mode `on <b>` with ONLY a learning store tracked is
#      already migrated (no reset, FAIL scratch-mode-off — migrate-branch-mode.sh's `already`); a
#      fresh fixture whose only other .md is a twin contract still gets the two synthetic seeds;
#      a scratch migration that also untracks the learning store goes red at migrate-clean
#   9. seed-ab runs the SHIPPED seed A/B check: the history fixture plus three gitignored
#      `.supervisor/automate/<run>.dismissed-decisions` ledgers -> every check PASSes (B = A + U);
#      mutation control: a migrate-branch-mode.sh comparing B with A alone (the pre-fix relation,
#      which failed loomwright-studio's real seed at A = 63, B = 66) turns seed-ab red while every
#      verify-* check stays green — the gap that let rehearse pass; and the half-migrated run (6)
#      keeps the copied untracked file ignored in the reset scratch clone (an info/exclude line), so
#      the shipped seed does not see a dirty tree — mutation control: without that line seed-ab is red

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

CHECKS="scratch-remote scratch-mode-off init push verify-present verify-blobs verify-nothing-extra verify-types seed-ab migrate-clean pull-roundtrip rollback-run rollback-edit-kept rollback-add-kept rollback-delete-kept rollback-all-kept rollback-gitignore twin-contracts source-untouched"

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
[ "$(printf '%s\n' "$OUT" | grep -cE '^(PASS|FAIL): ')" = 19 ]; check $? "one PASS/FAIL line per check (19)"
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
# (automate-speed/20) meta-sync.sh is read as ONE file — its own _ms_bundle output in MSB, so a sed
# finds the code its modules hold and the mutant is self-contained; the copied entries source
# setup-memory.d/ and meta-sync.d/, so those are copied too.
MSB="$TROOT/meta-sync.bundle.sh"
( eval "$(awk '/^_ms_bundle\(\) \{$/,/^}$/' "$HERE/meta-sync.sh")"; _ms_bundle "$HERE/meta-sync.sh" ) > "$MSB"
build_mutant() {
  local src="$HERE/$2"; [ "$2" = meta-sync.sh ] && src="$MSB"
  mkdir -p "$1"; for f in "$HERE"/*; do [ -f "$f" ] && cp "$f" "$1/"; done
  cp -R "$HERE/setup-memory.d" "$HERE/meta-sync.d" "$1/" || return 1
  sed -f "$3" "$src" > "$1/$2" || return 1
  cmp -s "$src" "$1/$2" && return 1
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

echo "== 7. learning stores: consent decides what the push carries; every check passes either way =="
mkworld
run --branch "$BR"
{ [ "$RC" -eq 0 ] && all_pass && has "info: learning stores: consent 'none' — 0 learning-store path(s) on $BR (of 2 local)"; }
check $? "no consent: every named check PASSes and the learning stores stay off the branch (rc=$RC)"
[ "$RC" -eq 0 ] || printf '%s\n' "$OUT" | grep -E '^(FAIL|info)' | sed 's/^/    /'
mkworld
bash "$HERE/setup-memory.sh" --root "$W/src" consent grant >/dev/null 2>&1
[ "$(bash "$HERE/setup-memory.sh" --root "$W/src" consent status)" = granted ]; check $? "fixture: consent granted for the fixture under the scratch HOME"
home_sig() { (cd "$HOME" && find . -type f | env LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(cksum < "$f")"; done); }
CREC0="$(home_sig)"
run --branch "$BR"
{ [ "$RC" -eq 0 ] && all_pass && has "info: learning stores: consent 'granted' — 2 learning-store path(s) on $BR (of 2 local)" \
  && has "info: learning stores round-tripped: 2 of 2 byte-identical"; }
check $? "consent granted: every named check PASSes, the twin contract + .provenance.jsonl reach the branch and round-trip (rc=$RC)"
[ "$RC" -eq 0 ] || printf '%s\n' "$OUT" | grep -E '^(FAIL|info)' | sed 's/^/    /'
[ "$(home_sig)" = "$CREC0" ]; check $? "the caller's HOME (its consent record included) is byte-unchanged (the scratch clone's grant lives in the scratch HOME only)"
mutant verify-present-full meta-sync-rehearsal.sh 'MUTANT-FULL' verify-present <<'SED'
s|^bash "\$MS" list-managed --run-history --root "\$A" 2>/dev/null \| env LC_ALL=C sort > "\$S/L.list"$|bash "$MS" list-managed --root "$A" 2>/dev/null \| env LC_ALL=C sort > "$S/L.list"  # MUTANT-FULL|
SED
cat > "$TROOT/types.sed" <<'SED'
s| \&\& \$2 !~ /(^\|\\/)\\.provenance\\.jsonl\$/||
SED
if build_mutant "$TROOT/mut-types" meta-sync-rehearsal.sh "$TROOT/types.sed" 'brain-baseline\.jsonl$/ && $2 !~ /\.dismissed-decisions$/'; then
  mkworld; bash "$HERE/setup-memory.sh" --root "$W/src" consent grant >/dev/null 2>&1
  SCRIPT="$TROOT/mut-types/meta-sync-rehearsal.sh"; run --branch "$BR"; SCRIPT="$SUT"
  if [ "$RC" -eq 1 ] && red verify-types; then ok "mutation control: without .provenance.jsonl among the kinds a consented run goes red at verify-types"; else no "mutation control REFUTED: verify-types stayed green without .provenance.jsonl (rc=$RC)"; fi
else no "mutation control (types) did not build — counts as FAIL"; fi

echo "== 8. run history vs learning stores in the rehearsal's tracked / count reads =="
EV=".supervisor/eval/results.jsonl"
track_ev() { ( cd "$W/src" && mkdir -p .supervisor/eval && echo '{"run":"r1","score":1}' > "$EV" && git add -f "$EV" && git commit -qm eval && git push -q origin main ) >/dev/null 2>&1; }
# tl_run [grant] — history fixture with $EV force-tracked; 0 = every check PASSes
tl_run() { mkworld; track_ev; [ "${1:-}" = grant ] && bash "$HERE/setup-memory.sh" --root "$W/src" consent grant >/dev/null 2>&1; run --branch "$BR"; [ "$RC" -eq 0 ] && all_pass >/dev/null; }
tl_run; check $? "a tracked learning store, consent none: every check PASSes (it stays tracked; pull-roundtrip expects it) (rc=$RC)"
[ "$RC" -eq 0 ] || printf '%s\n' "$OUT" | grep -E '^(FAIL|info)' | sed 's/^/    /'
tl_run grant; check $? "a tracked learning store, consent granted: every check PASSes (rc=$RC)"
[ "$RC" -eq 0 ] || printf '%s\n' "$OUT" | grep -E '^(FAIL|info)' | sed 's/^/    /'
cat > "$TROOT/lx.sed" <<'SED'
s|^env LC_ALL=C sort -u "\$S/L.list" "\$S/LLB.list" "\$S/LT.list" > "\$S/LX.list"$|env LC_ALL=C sort -u "$S/L.list" "$S/LLB.list" > "$S/LX.list"  # MUTANT-LX|
SED
if build_mutant "$TROOT/mut-lx" meta-sync-rehearsal.sh "$TROOT/lx.sed" 'MUTANT-LX'; then
  SCRIPT="$TROOT/mut-lx/meta-sync-rehearsal.sh"; tl_run; SCRIPT="$SUT"
  if [ "$RC" -eq 1 ] && red pull-roundtrip; then ok "mutation control: without the tracked-learning term a tracked learning store turns pull-roundtrip red"; else no "mutation control REFUTED: pull-roundtrip stayed green without the tracked-learning term (rc=$RC)"; fi
else no "mutation control (LX) did not build — counts as FAIL"; fi
cat > "$TROOT/untrack-all.sed" <<'SED'
s|^bash "\$MS" list-managed --tracked --run-history --root "\$A" > "\$S/T.list" 2>/dev/null |bash "$MS" list-managed --tracked --root "$A" > "$S/T.list" 2>/dev/null  # MUTANT-UNTRACK-ALL |
SED
if build_mutant "$TROOT/mut-untrack-all" meta-sync-rehearsal.sh "$TROOT/untrack-all.sed" 'MUTANT-UNTRACK-ALL'; then
  SCRIPT="$TROOT/mut-untrack-all/meta-sync-rehearsal.sh"; tl_run; SCRIPT="$SUT"
  if [ "$RC" -eq 1 ] && red migrate-clean; then ok "mutation control: a scratch migration that untracks the learning store too turns migrate-clean red"; else no "mutation control REFUTED: untracking the learning store left migrate-clean green (rc=$RC)"; fi
else no "mutation control (untrack-all) did not build — counts as FAIL"; fi
# mode `on $BR` with only a learning store tracked = already migrated (no run history tracked)
ev_only_world() {
  mkworld fresh; track_ev
  ( cd "$W/src" && bash "$HERE/setup-memory.sh" --root "$W/src" apply --branch-mode "$BR" >/dev/null 2>&1 && rm -f .gitignore.backup.* && git commit -qam mode && git push -q origin main ) >/dev/null 2>&1
}
ev_only_world; run --branch "$BR"
{ [ "$RC" -eq 1 ] && red scratch-mode-off && ! has "info: half-migrated"; }; check $? "mode on $BR with only a learning store tracked -> already migrated: no reset, FAIL scratch-mode-off (rc=$RC)"
cat > "$TROOT/t0.sed" <<'SED'
s|list-managed --tracked --run-history --root "\$A" > "\$S/T0.list"|list-managed --tracked --root "$A" > "$S/T0.list"|
SED
if build_mutant "$TROOT/mut-t0" meta-sync-rehearsal.sh "$TROOT/t0.sed" 'list-managed --tracked --root "$A" > "$S/T0.list"'; then
  ev_only_world; SCRIPT="$TROOT/mut-t0/meta-sync-rehearsal.sh"; run --branch "$BR"; SCRIPT="$SUT"
  if has "info: half-migrated"; then ok "mutation control: counting the learning store as tracked run history rehearses an already-migrated checkout as half-migrated"; else no "mutation control REFUTED: no half-migrated reset without --run-history (rc=$RC)"; fi
else no "mutation control (T0) did not build — counts as FAIL"; fi
# a fresh fixture whose only other .md is a twin contract: the drill needs two RUN-HISTORY .md files
tw_world() { mkworld fresh; ( cd "$W/src" && printf 'SYSTEM_CONTRACT: app\ninvariants: [prints code]\n' | bash "$HERE/write-system-contract.sh" --subsystem app --source "session:fixture-0001" >/dev/null 2>&1 ); }
tw_world; run --branch "$BR"
{ [ "$RC" -eq 0 ] && all_pass && has "added two synthetic"; }; check $? "fresh + a twin contract: the synthetic seeds are still added, every check PASSes (rc=$RC)"
[ "$RC" -eq 0 ] || printf '%s\n' "$OUT" | grep -E '^(FAIL|info)' | sed 's/^/    /'
cat > "$TROOT/nmd.sed" <<'SED'
s|^n_md="\$(bash "\$MS" list-managed --run-history --root|n_md="$(bash "$MS" list-managed --root|
SED
if build_mutant "$TROOT/mut-nmd" meta-sync-rehearsal.sh "$TROOT/nmd.sed" 'n_md="$(bash "$MS" list-managed --root'; then
  tw_world; SCRIPT="$TROOT/mut-nmd/meta-sync-rehearsal.sh"; run --branch "$BR"; SCRIPT="$SUT"
  if [ "$RC" -eq 1 ] && ! has "added two synthetic"; then ok "mutation control: counting the twin contract as drill material skips the seeds and turns the run red ($(printf '%s\n' "$OUT" | grep '^FAIL' | cut -d' ' -f2 | tr '\n' ' '))"; else no "mutation control REFUTED: counting the twin contract left the run green (rc=$RC)"; fi
else no "mutation control (n_md) did not build — counts as FAIL"; fi

echo "== 9. seed-ab: the shipped seed check, with ignored dismissed-decisions ledgers =="
dd_world() {
  mkworld; local i
  mkdir -p "$W/src/.supervisor/automate"
  for i in 1 2 3; do printf 'd-%s.md\tdrop\t2026-10-12T00:00:0%sZ\n' "$i" "$i" > "$W/src/.supervisor/automate/automate-r$i.dismissed-decisions"; done
}
dd_world; run --branch "$BR"
{ [ "$RC" -eq 0 ] && all_pass && git -C "$W/src" check-ignore -q -- .supervisor/automate/automate-r1.dismissed-decisions; }
check $? "three ignored ledgers: every check PASSes, seed-ab included (rc=$RC)"
[ "$RC" -eq 0 ] || printf '%s\n' "$OUT" | grep -E '^(FAIL|info)' | sed 's/^/    /'
cat > "$TROOT/no-u.sed" <<'SED'
s|^    diff "\$SD/au\.list" "\$SD/b\.list" > "\$SD/ab-names\.diff"; diff "\$SD/au\.ent" "\$SD/b\.ent" > "\$SD/ab-blobs\.diff"$|    diff "$SD/a.list" "$SD/b.list" > "$SD/ab-names.diff"; diff "$SD/a.ent" "$SD/b.ent" > "$SD/ab-blobs.diff"|
SED
if build_mutant "$TROOT/mut-no-u" migrate-branch-mode.sh "$TROOT/no-u.sed" 'diff "$SD/a.list" "$SD/b.list" > "$SD/ab-names.diff"'; then
  dd_world; SCRIPT="$TROOT/mut-no-u/meta-sync-rehearsal.sh"; run --branch "$BR"; SCRIPT="$SUT"
  { [ "$RC" -eq 1 ] && red seed-ab && [ "$(grep -c '^FAIL' <<<"$OUT")" = 1 ] && grep -q '^PASS: verify-nothing-extra$' <<<"$OUT"; }
  check $? "mutation control: the pre-fix A = B relation turns ONLY seed-ab red — every verify-* check stays green (rc=$RC; $(grep '^FAIL' <<<"$OUT" | cut -c1-200 | tr '\n' ' '))"
else no "mutation control (seed A/B without U) did not build — counts as FAIL"; fi
cat > "$TROOT/no-exc.sed" <<'SED'
s|^    printf '/%s\\n' "\$(printf '%s' "\$p" \| sed 's/\[\]\[\*?\\\\\]/\\\\\&/g')" >> "\$EXC"$|    : # MUTANT-NO-EXCLUDE|
SED
if build_mutant "$TROOT/mut-no-exc" meta-sync-rehearsal.sh "$TROOT/no-exc.sed" 'MUTANT-NO-EXCLUDE'; then
  half_world "$BR"; SCRIPT="$TROOT/mut-no-exc/meta-sync-rehearsal.sh"; run --branch "$BR"; SCRIPT="$SUT"
  { [ "$RC" -eq 1 ] && red seed-ab && has "not clean"; }; check $? "mutation control: without keeping the copied file ignored, the half-migrated seed-ab reads a dirty tree (rc=$RC)"
else no "mutation control (half-migrated exclude) did not build — counts as FAIL"; fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
