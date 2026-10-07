#!/usr/bin/env bash
# test-migrate-branch-mode.sh — self-tests for migrate-branch-mode.sh (default mode -> branch mode).
# Hermetic: every fixture is a bare `origin` plus clones inside one mktemp -d (never GitHub), HOME
# and git identity are sandboxed, `gh` is a PATH stub (LOOMWRIGHT_GH_BIN) that logs every call, and
# the SUT always runs with --root on a fixture — never against the checkout running the test.
# Exit 0 = all pass. Run it under /bin/bash on macOS too.
#
# Covers:
#   1. plan: fresh / history / already in branch mode on <b> (read from the mode line, `team-meta`,
#      even with the run lock held and a dirty tree) / unknown -> refusal exit 1; plan writes nothing
#      (file, ref and index snapshot identical) in every case
#   2. preflight: each precondition failing in turn (not on default; dirty; ahead of origin; an
#      /automate run in flight; run lock LOCKED; open chore/*-trail-* PR; dirty linked worktree)
#      -> exit non-zero naming the [FAIL] check; a later step refuses while preflight is not PASS
#   3. scrub: a planted hit stops the flow before init with file, line and rule; nothing pushed
#   4. fresh end to end on `team-meta`: init (invalid name refused before any write), protect
#      prints the ruleset + gh api command, --verify FAIL then (resumed) PASS, mode-pr opens one
#      `.gitignore`-only PR, never merged, apply's backup moved under .supervisor/migrate-branch-mode/,
#      `git status --porcelain` empty, no untrack PR; after the owner's merge, after-merge PASS
#   5. history end to end on `team-meta`: seed A=B (+ owner-decision list of non-managed tracked
#      paths), untrack-pr body, verify-pr pushes a file added to the default branch since and
#      refuses the stale PR, re-cut + verify-pr PASS, after-merge restores every file, porcelain empty;
#      no meta-sync call ever falls back to loomwright-meta; gh never merges nor writes a ruleset
#   6. rollback after a post-migration edit, add and delete: nothing lost, .gitignore restored
#   7. mutation control: verify-pr without its re-check MUST fail (5)
#   8. mutation control: the old M1 rollback order (revert -> meta-sync pull -> git add) MUST fail (6)

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/migrate-branch-mode.sh"
SCRIPT="$SUT"
BR="team-meta"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }
check() { if [ "$1" -eq 0 ]; then ok "$2"; else no "$2"; fi; }

TROOT="$(mktemp -d)"
trap 'rm -rf "$TROOT"' EXIT
export HOME="$TROOT/home"; mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=tester GIT_AUTHOR_EMAIL=tester@test.invalid
export GIT_COMMITTER_NAME=tester GIT_COMMITTER_EMAIL=tester@test.invalid
export LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="owner/repo"

# ---- gh stub: logs every call; answers pr list / create / view and the rulesets reads ------------
STUBD="$TROOT/stub"; STUBBIN="$TROOT/bin"; mkdir -p "$STUBD" "$STUBBIN"
cat > "$STUBBIN/gh" <<'STUB'
#!/bin/bash
D="$GH_STUB_DIR"; echo "$*" >> "$D/log"
case "$1 $2" in
  "pr list") cat "$D/open_prs" 2>/dev/null; exit 0 ;;
  "pr create")
    n=$(( $(cat "$D/n" 2>/dev/null || echo 40) + 1 )); echo "$n" > "$D/n"
    while [ $# -gt 0 ]; do case "$1" in --head) echo "$2" > "$D/head.$n" ;; --body-file) cp "$2" "$D/body.$n" ;; esac; shift; done
    echo "https://github.com/owner/repo/pull/$n"; exit 0 ;;
  "pr view") n=""; for a in "$@"; do case "$a" in [0-9]*) n="$a"; break ;; esac; done
    echo "OPEN $(cat "$D/head.$n" 2>/dev/null)"; exit 0 ;;
  "api repos/owner/repo/rulesets")
    case "$(cat "$D/ruleset_mode" 2>/dev/null)" in none|'') echo '[]' ;; *) echo '[{"id":7,"name":"x","target":"branch","enforcement":"active"}]' ;; esac; exit 0 ;;
  "api repos/owner/repo/rulesets/7")
    b="$(cat "$D/ruleset_branch")"; by='[]'; [ "$(cat "$D/ruleset_mode")" = bypass ] && by='[{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"always"}]'
    printf '{"id":7,"target":"branch","enforcement":"active","conditions":{"ref_name":{"include":["refs/heads/%s"],"exclude":[]}},"rules":[{"type":"deletion"},{"type":"non_fast_forward"}],"bypass_actors":%s}\n' "$b" "$by"; exit 0 ;;
esac
echo "gh stub: unhandled: $*" >&2; exit 1
STUB
chmod +x "$STUBBIN/gh"
export LOOMWRIGHT_GH_BIN="$STUBBIN/gh" GH_STUB_DIR="$STUBD"
stub_reset() { rm -f "$STUBD"/*; echo none > "$STUBD/ruleset_mode"; echo "$BR" > "$STUBD/ruleset_branch"; }

# ---- fixtures ------------------------------------------------------------------------------------
W=""
# mkworld [history] — bare origin + main with code (.supervisor/ ignored); history = run history
# force-tracked on main plus one tracked NON-managed .supervisor/ path. Clones it as A.
mkworld() {
  stub_reset
  W="$(mktemp -d "$TROOT/w.XXXXXX")"
  git init -q --bare "$W/origin.git"
  git --git-dir="$W/origin.git" symbolic-ref HEAD refs/heads/main
  git init -q "$W/seed"
  (
    cd "$W/seed" || exit 1
    git symbolic-ref HEAD refs/heads/main
    printf '.supervisor/\n' > .gitignore; echo code > app.txt
    git add .gitignore app.txt
    if [ "${1:-}" = history ]; then
      mkdir -p .supervisor/requirements/q .supervisor/jobs/done .supervisor/salvage/x
      echo '# req' > .supervisor/requirements/q/req.md
      echo '# a v1' > .supervisor/jobs/done/a.md; echo '# b' > .supervisor/jobs/done/b.md
      echo 'echo salvage' > .supervisor/salvage/x/check.sh
      git add -f .supervisor
    fi
    git commit -qm code
    git remote add origin "$W/origin.git" && git push -q origin main
  )
  git clone -q "$W/origin.git" "$W/A" 2>/dev/null
}
mb() { local d="$1"; shift; OUT="$(bash "$SCRIPT" "$@" --root "$W/$d" 2>&1)"; RC=$?; }
has() { printf '%s' "$OUT" | grep -qF -- "$1"; }
st() { sed -n "s/^$2=//p" "$W/$1/.supervisor/migrate-branch-mode/state" 2>/dev/null | tail -n 1; }
porcelain() { git -C "$W/$1" status --porcelain 2>/dev/null; }
remote_has() { git --git-dir="$W/origin.git" rev-parse -q --verify "refs/heads/$1" >/dev/null 2>&1; }
snap() { (cd "$W/$1" && find . -path ./.git/objects -prune -o -type f -print | env LC_ALL=C sort | while IFS= read -r f; do cksum "$f"; done); }
gh_never_writes() { ! grep -qE 'pr merge|--method|-X ' "$STUBD/log" 2>/dev/null; }
# owner_merge <head> — the OWNER merges the PR in a separate clone (never the SUT); sets MERGE_SHA
owner_merge() {
  rm -rf "$W/O"; git clone -q "$W/origin.git" "$W/O" 2>/dev/null
  git -C "$W/O" merge -q --no-ff -m "Merge $1" "origin/$1" >/dev/null 2>&1 && git -C "$W/O" push -q origin main
  MERGE_SHA="$(git -C "$W/O" rev-parse HEAD)"
}
# to_protected <clone> — preflight -> scrub -> init --branch team-meta -> protect --verify PASS
to_protected() {
  mb "$1" preflight --repo owner/repo || return 1
  mb "$1" scrub || return 1
  mb "$1" init --branch "$BR" || return 1
  echo good > "$STUBD/ruleset_mode"; mb "$1" protect --verify
}
hist_to_untrack() { mkworld history; to_protected A && mb A seed && mb A untrack-pr; }
pr_n() { st A "$1" | sed 's|.*/||'; }

echo "== 1. plan: case detection, read-only =="
mkworld; S0="$(snap A)"; mb A plan
{ [ "$RC" -eq 0 ] && has "case: fresh" && has "mode-pr"; }; check $? "fresh repo -> case fresh (rc=$RC)"
[ "$S0" = "$(snap A)" ]; check $? "plan wrote nothing (fresh)"
mkworld history; S0="$(snap A)"; mb A plan
{ [ "$RC" -eq 0 ] && has "case: history" && has "seed -> untrack-pr -> verify-pr"; }; check $? "tracked managed paths -> case history with the full sequence"
[ "$S0" = "$(snap A)" ]; check $? "plan wrote nothing (history)"
mkworld
( cd "$W/A" && bash "$HERE/setup-memory.sh" --root "$W/A" apply --branch-mode "$BR" >/dev/null && git add .gitignore && git commit -qm mode && git push -q origin main )
bash "$HERE/run-lock.sh" acquire --owner test --root "$W/A" >/dev/null 2>&1; echo dirt >> "$W/A/app.txt"
S0="$(snap A)"; mb A plan
{ [ "$RC" -eq 0 ] && has "already in branch mode on $BR"; }; check $? "mode 'on $BR', nothing tracked, lock held + dirty tree -> already in branch mode on $BR"
[ "$S0" = "$(snap A)" ]; check $? "plan wrote nothing (already)"
sed 's/^# loomwright-meta-branch: .*/# loomwright-meta-branch: off/' "$W/A/.gitignore" > "$W/g.tmp" && mv "$W/g.tmp" "$W/A/.gitignore"
S0="$(snap A)"; mb A plan
{ [ "$RC" -eq 1 ] && has "unknown"; }; check $? "mode 'unknown <reason>' -> refusal exit 1 naming it (rc=$RC)"
[ "$S0" = "$(snap A)" ]; check $? "plan wrote nothing (unknown)"
bash "$HERE/run-lock.sh" release --owner test --root "$W/A" >/dev/null 2>&1

echo "== 2. preflight: each precondition failing in turn =="
mkworld history
pf_fail() { mb A preflight --repo owner/repo; { [ "$RC" -ne 0 ] && has "[FAIL] $1" && has "preflight: FAIL"; }; check $? "preflight FAILs on: $1 (rc=$RC)"; }
git -C "$W/A" checkout -q -b side; pf_fail "on the default branch"; git -C "$W/A" checkout -q main
mb A scrub; { [ "$RC" -eq 1 ] && has "refused"; }; check $? "scrub refuses while preflight is FAIL"
mb A init; { [ "$RC" -eq 1 ] && has "refused" && ! remote_has loomwright-meta; }; check $? "init refuses while preflight is FAIL, nothing created"
echo dirt >> "$W/A/app.txt"; pf_fail "working tree clean"; git -C "$W/A" checkout -q -- app.txt
echo more >> "$W/A/app.txt"; git -C "$W/A" commit -qam ahead; pf_fail "HEAD equals origin/main"; git -C "$W/A" reset -q --hard origin/main
mkdir -p "$W/A/.supervisor/automate"; printf '# Automate Run: r1\n\n## Status: running\n' > "$W/A/.supervisor/automate/r1.md"
pf_fail "no /automate run in flight"; rm -rf "$W/A/.supervisor/automate"
bash "$HERE/run-lock.sh" acquire --owner test --root "$W/A" >/dev/null 2>&1; pf_fail "run lock free"
bash "$HERE/run-lock.sh" release --owner test --root "$W/A" >/dev/null 2>&1
echo "chore/automate-r1-trail-1" > "$STUBD/open_prs"; pf_fail "no open chore/*-trail-* PR"; rm -f "$STUBD/open_prs"
git -C "$W/A" worktree add -q "$W/wt" -b wtb 2>/dev/null; echo x >> "$W/wt/app.txt"; pf_fail "no dirty linked worktree"
git -C "$W/A" worktree remove --force "$W/wt"
mb A preflight --repo owner/repo; { [ "$RC" -eq 0 ] && has "preflight: PASS" && [ "$(st A preflight)" = PASS ]; }; check $? "all clear -> preflight PASS recorded (rc=$RC)"

echo "== 3. scrub gate stops before init =="
mkworld history
echo 'contact jane.doe@acme-corp.com' >> "$W/A/.supervisor/jobs/done/a.md"
( cd "$W/A" && git commit -qam leak && git push -q origin main )
mb A preflight --repo owner/repo; mb A scrub
{ [ "$RC" -eq 1 ] && has "scrub-hit .supervisor/jobs/done/a.md:2: email" && [ "$(st A scrub)" = FAIL ]; }; check $? "planted hit -> scrub FAIL naming file:line: rule (rc=$RC)"
mb A init --branch "$BR"; { [ "$RC" -eq 1 ] && ! remote_has "$BR"; }; check $? "init refuses after a scrub hit; nothing pushed"

echo "== 4. fresh flow end to end on $BR =="
mkworld
mb A preflight --repo owner/repo; mb A scrub; [ "$RC" -eq 0 ]; check $? "fresh: preflight + scrub PASS"
mb A init --branch 'bad..name'; { [ "$RC" -eq 1 ] && has "not a valid metadata branch" && [ -z "$(st A branch)" ] && ! remote_has 'bad..name'; }; check $? "invalid branch name refused by valid-branch before anything is written"
mb A init --branch "$BR"; { [ "$RC" -eq 0 ] && remote_has "$BR" && [ "$(st A branch)" = "$BR" ]; }; check $? "init creates origin/$BR and records the name"
mb A mode-pr; { [ "$RC" -eq 1 ] && has "refused"; }; check $? "mode-pr refuses before protect --verify"
mb A protect
{ [ "$RC" -eq 0 ] && has '"refs/heads/team-meta"' && has '"deletion"' && has '"non_fast_forward"' && has '"bypass_actors": []' && has "gh api --method POST repos/owner/repo/rulesets"; }; check $? "protect prints the ruleset (branch, deletion, non-fast-forward, no bypass) and the gh api command"
mb A protect --verify; { [ "$RC" -eq 1 ] && [ "$(st A protect)" = FAIL ]; }; check $? "protect --verify with no ruleset -> FAIL"
mb A state; has "next: protect"; check $? "a flow stopped at protect resumes from protect (state: next: protect)"
echo bypass > "$STUBD/ruleset_mode"; mb A protect --verify; [ "$RC" -eq 1 ]; check $? "protect --verify refuses a ruleset with a bypass actor"
echo good > "$STUBD/ruleset_mode"; mb A protect --verify; { [ "$RC" -eq 0 ] && [ "$(st A protect)" = PASS ]; }; check $? "protect --verify PASS once the owner's ruleset exists"
MAIN0="$(git --git-dir="$W/origin.git" rev-parse main)"
mb A mode-pr
NB="$(st A mode_pr_branch)"
{ [ "$RC" -eq 0 ] && [ -n "$NB" ] && remote_has "$NB"; }; check $? "mode-pr pushes a NEW branch and opens a PR (rc=$RC, $NB)"
[ "$(git --git-dir="$W/origin.git" rev-list --count "main..$NB")" = 1 ] && [ "$(git --git-dir="$W/origin.git" diff --name-only "main" "$NB")" = ".gitignore" ]; check $? "the PR is one commit of .gitignore only"
[ "$(git --git-dir="$W/origin.git" rev-parse main)" = "$MAIN0" ]; check $? "the default branch is untouched (PR never merged)"
git --git-dir="$W/origin.git" show "$NB:.gitignore" | grep -qx "# loomwright-meta-branch: $BR"; check $? "the PR's .gitignore carries the mode line for $BR"
BK="$(st A backup_mode_pr)"
{ [ -f "$BK" ] && case "$BK" in "$(cd "$W/A" && pwd -P)/.supervisor/migrate-branch-mode/"*) true ;; *) false ;; esac && [ -z "$(ls "$W/A" | grep 'gitignore.backup' )" ] && ! ls -a "$W/A" | grep -q '^.gitignore.backup'; }; check $? "apply's .gitignore.backup.<ts> moved under .supervisor/migrate-branch-mode/ and recorded"
[ -z "$(porcelain A)" ]; check $? "git status --porcelain empty after mode-pr ($(porcelain A | tr '\n' ' '))"
{ [ "$(grep -c 'pr create' "$STUBD/log")" = 1 ] && gh_never_writes; }; check $? "exactly one PR opened (no untrack PR); gh never merges nor writes a ruleset"
has "merge"; check $? "the owner is told to merge it"
owner_merge "$NB"; mb A after-merge
{ [ "$RC" -eq 0 ] && [ -z "$(porcelain A)" ] && [ "$(bash "$HERE/setup-memory.sh" --root "$W/A" mode)" = "on $BR" ] && has "meta-sync.sh pull --branch $BR"; }; check $? "after the owner's merge: after-merge PASS, mode on $BR, clean (rc=$RC)"
! remote_has loomwright-meta; check $? "no call fell back to loomwright-meta (fresh)"

echo "== 5. history flow end to end on $BR =="
hist_to_untrack
{ [ "$(st A seed)" = PASS ] && [ "$(st A seed_a)" = 3 ] && [ "$(st A seed_b)" = 3 ]; }; check $? "seed PASS: A = B = 3"
UB="$(st A untrack_branch)"; N1="$(pr_n pr_untrack)"
git --git-dir="$W/origin.git" ls-tree -r --name-only "$BR" | grep -q 'salvage' && no "salvage reached the branch" || ok "non-managed tracked path never reaches the branch"
B1="$STUBD/body.$N1"
{ grep -q 'A (tracked managed paths on `main`): 3' "$B1" && grep -q 'B (`team-meta` tree): 3' "$B1" && grep -q 'path-list diff A vs B: empty' "$B1" && grep -q "pre-migration SHA: $(st A pre_migration_sha)" "$B1" && grep -q 'verify-pr' "$B1"; }; check $? "untrack PR body: A/B counts, empty diffs, pre-migration SHA, verify-pr instruction"
UD="$(git --git-dir="$W/origin.git" diff --name-status main "$UB" | env LC_ALL=C sort | tr '\t\n' ' ')"
[ "$UD" = "D .supervisor/jobs/done/a.md D .supervisor/jobs/done/b.md D .supervisor/requirements/q/req.md M .gitignore " ]; check $? "untrack PR: block + git rm --cached of the managed set only, salvage kept ($UD)"
{ [ -z "$(porcelain A)" ] && [ -z "$(ls -a "$W/A" | grep '^.gitignore.backup')" ] && [ -f "$(st A backup_untrack_pr)" ]; }; check $? "after untrack-pr: porcelain empty, backup moved and recorded"
# the default branch moves after the PR was cut: a new managed file lands on main
verify_newfile() { # 0 = verify-pr pushed c.md to the branch first AND refused the stale PR
  rm -rf "$W/O"; git clone -q "$W/origin.git" "$W/O" 2>/dev/null
  ( cd "$W/O" && echo '# c' > .supervisor/jobs/done/c.md && git add -f .supervisor/jobs/done/c.md && git commit -qm c && git push -q origin main )
  mb A verify-pr "$(pr_n pr_untrack)"
  VERIFY_DETAIL="rc=$RC; c.md on branch: $(git --git-dir="$W/origin.git" cat-file -e "$BR:.supervisor/jobs/done/c.md" 2>/dev/null && echo yes || echo no)"
  [ "$RC" -ne 0 ] && git --git-dir="$W/origin.git" cat-file -e "$BR:.supervisor/jobs/done/c.md" 2>/dev/null
}
verify_newfile; check $? "verify-pr pushes a file added to main since, then refuses the stale PR ($VERIFY_DETAIL)"
mb A seed; mb A untrack-pr; UB2="$(st A untrack_branch)"
mb A verify-pr "$(pr_n pr_untrack)"; { [ "$RC" -eq 0 ] && [ "$UB2" != "$UB" ]; }; check $? "re-cut untrack PR -> verify-pr PASS (rc=$RC)"
mb A state; has "next: after-merge"; check $? "state reports the resume point (next: after-merge)"
owner_merge "$UB2"; MERGED="$MERGE_SHA"
mb A after-merge
{ [ "$RC" -eq 0 ] && [ -f "$W/A/.supervisor/jobs/done/c.md" ] && [ "$(cat "$W/A/.supervisor/jobs/done/a.md")" = "# a v1" ] && [ -f "$W/A/.supervisor/requirements/q/req.md" ]; }; check $? "after-merge: every run-history file is back (rc=$RC)"
[ -z "$(porcelain A)" ]; check $? "after-merge: git status --porcelain empty ($(porcelain A | tr '\n' ' '))"
{ has "git pull" && has "meta-sync.sh pull --branch $BR"; }; check $? "after-merge prints the two commands for other checkouts"
{ ! remote_has loomwright-meta && gh_never_writes; }; check $? "no meta-sync call fell back to loomwright-meta; gh never merged nor wrote a ruleset"

echo "== 6. rollback keeps every post-migration change =="
rollback_scenario() { # on clone A after after-merge; 0 = nothing lost
  echo '# a v2 post-migration' > "$W/A/.supervisor/jobs/done/a.md"
  echo '# d new' > "$W/A/.supervisor/jobs/done/d.md"
  rm -f "$W/A/.supervisor/jobs/done/b.md"
  mb A rollback --commit "$1"
  local rb; rb="$(st A rollback_branch)"
  ROLLBACK_DETAIL="rc=$RC a=$(git -C "$W/A" show "$rb:.supervisor/jobs/done/a.md" 2>/dev/null)"
  [ "$RC" -eq 0 ] && remote_has "$rb" \
    && [ "$(git -C "$W/A" show "$rb:.supervisor/jobs/done/a.md" 2>/dev/null)" = "# a v2 post-migration" ] \
    && git -C "$W/A" cat-file -e "$rb:.supervisor/jobs/done/d.md" 2>/dev/null \
    && ! git -C "$W/A" cat-file -e "$rb:.supervisor/jobs/done/b.md" 2>/dev/null \
    && git -C "$W/A" cat-file -e "$rb:.supervisor/jobs/done/c.md" 2>/dev/null \
    && [ "$(git -C "$W/A" show "$rb:.gitignore")" = "$(git -C "$W/A" show "$(st A pre_migration_sha):.gitignore")" ] \
    && [ -z "$(porcelain A)" ]
}
rollback_scenario "$MERGED"; check $? "rollback re-tracks the CURRENT branch files: edit kept, add kept, delete honoured, .gitignore restored, clean ($ROLLBACK_DETAIL)"
gh_never_writes; check $? "rollback never merges"
grep -qE 'xargs +(-[a-zA-Z0-9]+ +)*-r( |$)' "$SUT" && no "SUT uses GNU-only xargs -r" || ok "no GNU-only xargs -r in the SUT"

# ---- mutation controls ---------------------------------------------------------------------------
# build_mutant <dir> <sed-expr> <must-appear> — copies every sibling script, seds the SUT; 0 = built
build_mutant() {
  mkdir -p "$1"; for f in "$HERE"/*; do [ -f "$f" ] && cp "$f" "$1/"; done
  sed -e "$2" "$SUT" > "$1/migrate-branch-mode.sh" || return 1
  cmp -s "$SUT" "$1/migrate-branch-mode.sh" && return 1
  grep -qF "$3" "$1/migrate-branch-mode.sh" || return 1
  bash -n "$1/migrate-branch-mode.sh" || return 1
}

echo "== 7. mutation control: verify-pr without its re-check =="
MUT="$TROOT/mut-verify"
if build_mutant "$MUT" 's/^  on_default_clean "\$d"$/  state_set verify_pr PASS; say "verify-pr: PASS (mutant)"; return 0; on_default_clean "$d"/' 'verify-pr: PASS (mutant)'; then
  hist_to_untrack; SCRIPT="$MUT/migrate-branch-mode.sh"
  if verify_newfile; then no "mutation control REFUTED: verify-pr without the re-check still passed the test"; else ok "mutation control: skipping the verify-pr re-check turns the test red ($VERIFY_DETAIL)"; fi
  SCRIPT="$SUT"
else no "mutation control (verify-pr) did not build — counts as FAIL"; fi

echo "== 8. mutation control: the old M1 rollback order =="
MUT="$TROOT/mut-m1"
if build_mutant "$MUT" 's/^  rb_retrack_from_branch "\$br_sha" || /  bash "$MS" pull --branch "$b" --root "$ROOT"; (cd "$ROOT" \&\& git add -u -- .supervisor) || /' 'git add -u -- .supervisor'; then
  hist_to_untrack; mb A verify-pr "$(pr_n pr_untrack)"; owner_merge "$(st A untrack_branch)"; mb A after-merge
  SCRIPT="$MUT/migrate-branch-mode.sh"
  if rollback_scenario "$MERGE_SHA"; then no "mutation control REFUTED: the M1 order kept the post-migration edit"; else ok "mutation control: the M1 order loses the post-migration edit ($ROLLBACK_DETAIL)"; fi
  SCRIPT="$SUT"
else no "mutation control (M1 rollback) did not build — counts as FAIL"; fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
