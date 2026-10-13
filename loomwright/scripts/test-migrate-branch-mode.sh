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
#   9. mutation control: after-merge without its put-back of the files `git pull` deleted MUST fail
#  10. rehearse: no harness -> exit 1 (not available); the harness gets `--root <checkout> --branch
#      <recorded name>` after init (team-meta, never loomwright-meta) and a disagreeing --branch is
#      refused; the REAL harness passes on a history fixture before init and never touches its origin
#  11. after-merge re-checks tracked managed paths: a managed file committed AFTER verify-pr and
#      before the owner's merge -> after-merge FAIL naming it; the named recovery (seed -> untrack-pr
#      -> verify-pr -> merge -> after-merge) completes; a re-run is idempotent; mutation control:
#      after-merge without the re-check MUST fail the leg
#      after the FAIL `state` points at seed and after-merge refuses until a round-2 verify-pr ran;
#      the round-2 seed / verify-pr say A ⊆ B (never "equal") and the PR body does too
#  12. a step with no recorded metadata branch (rollback) refuses before any push / branch / state
#  13. a half-migrated FIRST migration (mode line already `on <b>`, history still tracked, no recorded
#      after-merge) with an extra managed file on the branch that is NOT on this disk (another
#      checkout's push) -> seed FAIL (A + U = B required, never A ⊆ B); mutation control: subset
#      mode keyed on the mode line alone MUST turn it red
#  14. a re-cut untrack PR stales the earlier verify-pr PASS: `state` says next verify-pr and
#      after-merge refuses until verify-pr runs against the new PR
#  15. after-merge proves the untrack PR merged: on a half-migrated repo (exact A = B seed PASS) an
#      after-merge run BEFORE the owner merges refuses ("not merged yet"), records no followup and
#      keeps untrack_pr / verify_pr PASS; after the real merge it PASSes (and again on re-run), no
#      duplicate state keys; mutation control: dropping the merge proof MUST turn it red
#  16. followup lifecycle: a preflight while after_merge is FAIL keeps it (fresh-case recovery), a
#      preflight starting a new migration drops it, rollback drops it
#  17. after-merge checks branch paths verbatim: a managed path with a space PASSes when present and
#      FAILs naming it when missing after pull; "a b.md" missing while a_b.md is present FAILs (no
#      `?`-glob false PASS, run from inside the checkout); mutation control: the old
#      `tr ' ' '?'` word-split loop MUST turn the leg red
#  18. half-migrated init default (mode line `on team-meta`, history tracked): plan prints team-meta
#      as init's default; an explicit mismatching --branch is refused with nothing written; init with
#      no --branch records team-meta; the REAL rehearse passes on it (scratch reset to off) and never
#      touches the real remote; a fresh repo still defaults to loomwright-meta; mutation control:
#      init ignoring the mode line MUST turn the leg red
#  19. non-C locale (en_US UTF-8, when `locale -a` lists it; else a visible SKIP): with managed
#      names whose C and en_US collation differ (case, '-', '_'), seed lists only the real
#      non-managed path for the owner, verify-pr names EXACTLY the one managed path a stale PR
#      leaves tracked, and a re-cut PR verifies PASS; mutation control: the verify-pr `comm`
#      without `env LC_ALL=C` MUST turn the leg red
#  20. rollback of an untrack PR merged as a real 2-parent `--no-ff` merge commit keeps a
#      post-migration edit, add and delete; mutation control: dropping `-m 1` MUST turn it red
#  21. seed's A/B check: B is the WHOLE branch tree minus its learning-store paths — a consented
#      learning store on the branch still gives A = B (seed PASS), while three UNMANAGED strays of a
#      managed kind (NOTES.md, jobs/pending/, logs/) stay in B and fail it naming each; mutation
#      control: B = the run-history entries only MUST turn the stray leg red
#  22. a TRACKED learning store (.supervisor/eval/results.jsonl force-tracked on main), consent none
#      AND grant: seed PASS with A = B = 3 (A is run history only), the store named as an OWNER
#      DECISION extra, untrack-pr leaves it tracked, after-merge PASS, `plan` then reads `already`;
#      a rollback --commit of a hand-made commit that untracked it re-tracks it and never deletes it
#      from disk; mutation controls: tracked_managed without `--run-history` MUST turn seed red, and
#      gone.list without the staged learning-store filter MUST delete the store
#  23. rollback with consent granted and an UNTRACKED eval learning store on the branch: the store is
#      NOT in the rollback tree (never committed to the default branch) and stays on disk, while
#      the run history is re-tracked; mutation control: re-tracking every branch path (no
#      learning-store subtraction) MUST turn it red
#  24. the review's repro of a git-TRACKED learning store with two owners, consent none AND grant:
#      $EV force-tracked on main, seed PASS (A = B = 3), a teammate adds a line to $EV on the
#      metadata branch, untrack-pr -> verify-pr -> owner merge -> after-merge: after-merge PASS with
#      an empty porcelain, $EV byte-unchanged and still tracked (meta-sync names it
#      `learning_tracked`), the teammate's line still on the branch; mutation control: a meta-sync.sh
#      without the tracked-learning hold MUST turn both consent legs red
#  25. seed with GIT_INDEX_FILE=/nonexistent exported (a git shim lets it reach ONLY `ls-files`, the
#      tracked-set reads; every other git call sees the real index): $EV force-tracked on main is
#      still named on the OWNER DECISION line and seed PASSes; mutation control: ab_check's extra
#      read as a bare `g ls-files` (honouring the inherited index) MUST turn it red
#  26. the loomwright-studio field failure (A = 63, B = 66): the DEFAULT `/setup memory` block, 63
#      run-history files tracked through it, and three `.supervisor/automate/<run>.dismissed-decisions`
#      ledgers the block keeps ignored (porcelain empty). seed PASS naming U = 3 and B = A + U, state
#      seed_a=63 seed_u=3 seed_b=66, the untrack PR body states "A + U vs B" (never "A vs B"),
#      verify-pr PASS "B = A + U (66 = 63 + 3)", untrack PR leaves the ledgers alone, after-merge PASS
#      with an empty porcelain and the three ledgers still on disk; mutation control: ab_check
#      comparing B with A alone (the pre-fix relation) MUST reproduce the path-list failure naming the
#      3 ledgers
#  27. untrack-pr's readiness verify runs on the tree it commits: a history repo whose findings
#      ledger (.supervisor/postmortem/results.jsonl) is TRACKED -> untrack-pr prints apply's lines but
#      NO `WARNING` (the ledger is untracked before the branch-mode block is written, so `git
#      check-ignore` sees it as ignored), the untrack PR's head reads `Memory readiness: configured`
#      and untracks the ledger; mutation control: the old order (block written while the A set is
#      still tracked) MUST print `apply: WARNING — readiness is 'partial`; and when apply refuses AFTER
#      the untrack (a stubbed setup-memory.sh), the step restores the index, returns to main clean,
#      deletes the new branch, records FAIL and pushes nothing

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
# MB_LOCALE set -> the SUT runs under that locale (leg 19); empty -> the inherited environment
MB_LOCALE=""
mb() { local d="$1"; shift; OUT="$(${MB_LOCALE:+env LC_ALL=$MB_LOCALE} bash "$SCRIPT" "$@" --root "$W/$d" 2>&1)"; RC=$?; }
has() { grep -qF -- "$1" <<<"$OUT"; }
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
grep -qx "# loomwright-meta-branch: $BR" < <(git --git-dir="$W/origin.git" show "$NB:.gitignore"); check $? "the PR's .gitignore carries the mode line for $BR"
BK="$(st A backup_mode_pr)"
{ [ -f "$BK" ] && case "$BK" in "$(cd "$W/A" && pwd -P)/.supervisor/migrate-branch-mode/"*) true ;; *) false ;; esac && [ -z "$(ls "$W/A" | grep 'gitignore.backup' )" ] && ! grep -q '^.gitignore.backup' < <(ls -a "$W/A"); }; check $? "apply's .gitignore.backup.<ts> moved under .supervisor/migrate-branch-mode/ and recorded"
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
grep -q 'salvage' < <(git --git-dir="$W/origin.git" ls-tree -r --name-only "$BR") && no "salvage reached the branch" || ok "non-managed tracked path never reaches the branch"
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
# build_mutant <dir> <sed-expr> <must-appear> — copies every sibling script, seds the SUT; 0 = built.
# automate-helpers.sh sources its families from automate-helpers.d/ (preflight's resume-glob probe
# runs it whenever .supervisor/automate exists), so that folder is copied too.
build_mutant() {
  mkdir -p "$1"; for f in "$HERE"/*; do [ -f "$f" ] && cp "$f" "$1/"; done
  cp -R "$HERE/automate-helpers.d" "$1/" || return 1
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

echo "== 9. mutation control: after-merge without putting back what git pull deleted =="
# In the seeding checkout meta-base exists, so a file `git pull` deleted reads as a LOCAL deletion:
# meta-sync pull leaves it absent (and a later push would delete it from the branch).
MUT="$TROOT/mut-restore"
if build_mutant "$MUT" 's/^    mkdir -p "\$(dirname "\$ROOT\/\$p")" \&\& g cat-file blob/    : \&\& true || g cat-file blob/' ': && true || g cat-file blob'; then
  hist_to_untrack; mb A verify-pr "$(pr_n pr_untrack)"; owner_merge "$(st A untrack_branch)"
  SCRIPT="$MUT/migrate-branch-mode.sh"; mb A after-merge; SCRIPT="$SUT"
  if [ "$RC" -eq 0 ] && [ -f "$W/A/.supervisor/jobs/done/a.md" ]; then no "mutation control REFUTED: after-merge restored the files without the put-back step"; else ok "mutation control: without the put-back, after-merge fails closed (rc=$RC)"; fi
else no "mutation control (after-merge put-back) did not build — counts as FAIL"; fi

echo "== 10. rehearse: wired to meta-sync-rehearsal.sh with the recorded branch =="
RD="$TROOT/reh-none"; mkdir -p "$RD"; for f in "$HERE"/*; do [ -f "$f" ] && cp "$f" "$RD/"; done; rm -f "$RD/meta-sync-rehearsal.sh"
mkworld history; mb A preflight --repo owner/repo
SCRIPT="$RD/migrate-branch-mode.sh"; mb A rehearse; SCRIPT="$SUT"
{ [ "$RC" -eq 1 ] && has "not available" && [ "$(st A rehearse)" = FAIL ]; }; check $? "no harness -> rehearse exit 1, not available, FAIL recorded (rc=$RC)"
RL="$TROOT/reh-log"; mkdir -p "$RL"; for f in "$HERE"/*; do [ -f "$f" ] && cp "$f" "$RL/"; done
printf '#!/bin/bash\necho "$*" > "%s/args"\nexit 0\n' "$TROOT" > "$RL/meta-sync-rehearsal.sh"
mkworld history; mb A preflight --repo owner/repo; mb A scrub; mb A init --branch "$BR"
SCRIPT="$RL/migrate-branch-mode.sh"; mb A rehearse
{ [ "$RC" -eq 0 ] && [ "$(cat "$TROOT/args")" = "--root $(cd "$W/A" && pwd -P) --branch $BR" ] && [ "$(st A rehearse)" = PASS ]; }; check $? "after init: the harness gets --root <checkout> --branch $BR ($(cat "$TROOT/args" 2>/dev/null))"
rm -f "$TROOT/args"; mb A rehearse --branch loomwright-meta
{ [ "$RC" -eq 1 ] && has "disagrees" && [ ! -f "$TROOT/args" ]; }; check $? "a --branch disagreeing with the recorded name is refused, harness not run (rc=$RC)"
SCRIPT="$SUT"
mkworld history; mb A preflight --repo owner/repo; mb A scrub
O0="$(git --git-dir="$W/origin.git" for-each-ref --format='%(refname) %(objectname)')"
mb A rehearse --branch "$BR"
{ [ "$RC" -eq 0 ] && has "rehearse: PASS" && has "PASS: rollback-edit-kept" && has "PASS: twin-contracts" && ! has "FAIL:" && [ "$(st A rehearse)" = PASS ]; }; check $? "the real harness passes on a history fixture before init (rc=$RC)"
{ [ "$O0" = "$(git --git-dir="$W/origin.git" for-each-ref --format='%(refname) %(objectname)')" ] && ! remote_has "$BR" && [ -z "$(st A branch)" ]; }; check $? "rehearse never touches the real remote and records no branch"

echo "== 11. after-merge re-checks tracked managed paths (verify-pr -> merge race) =="
# race_late — verify-pr PASS, THEN a managed file lands on main, THEN the owner merges the (now
# stale) untrack PR; 0 = after-merge refused, naming the still-tracked path
race_late() {
  hist_to_untrack; mb A verify-pr "$(pr_n pr_untrack)"
  rm -rf "$W/O"; git clone -q "$W/origin.git" "$W/O" 2>/dev/null
  ( cd "$W/O" && echo '# late' > .supervisor/jobs/done/late.md && git add -f .supervisor/jobs/done/late.md && git commit -qm late && git push -q origin main )
  owner_merge "$(st A untrack_branch)"; mb A after-merge
  RACE_DETAIL="rc=$RC; tracked: $(bash "$HERE/meta-sync.sh" list-managed --tracked --root "$W/A" 2>/dev/null | tr '\n' ' ')"
  [ "$RC" -eq 1 ] && has "still tracked on main: .supervisor/jobs/done/late.md" && has "seed" && [ "$(st A after_merge)" = FAIL ]
}
race_late; check $? "after-merge FAILs naming a managed path committed after verify-pr ($RACE_DETAIL)"
mb A state; { has "next: seed" && [ "$(st A followup)" = 1 ] && [ "$(st A verify_pr)" = STALE ]; }; check $? "after the tracked-path FAIL, state points at seed (round 1's seed/untrack/verify are STALE)"
mb A after-merge; { [ "$RC" -eq 1 ] && has "refused: step 'verify_pr' is 'STALE'"; }; check $? "after-merge refuses on round 1's stale verify-pr PASS (rc=$RC)"
mb A seed; S1="$RC"; SEED2="$OUT"; mb A untrack-pr; S2="$RC"
mb A state; has "next: verify-pr"; check $? "round 2 after seed + untrack-pr: state says next: verify-pr"
mb A after-merge; { [ "$RC" -eq 1 ] && has "refused: step 'verify_pr'"; }; check $? "after-merge refuses until round-2 verify-pr has run (rc=$RC)"
{ grep -qF "A ⊆ B (B has 3 extra)" <<<"$SEED2" && ! grep -qF "path lists equal" <<<"$SEED2" && [ "$(st A seed_check)" = subset ]; }; check $? "round-2 seed reports A ⊆ B (B has 3 extra), never 'equal'"
B2="$STUBD/body.$(pr_n pr_untrack)"
{ grep -qF 'A ⊆ B (B has 3 extra' "$B2" && ! grep -qF 'path-list diff A vs B: empty' "$B2"; }; check $? "round-2 untrack PR body claims A ⊆ B, not an empty A/B diff"
mb A verify-pr "$(pr_n pr_untrack)"; S3="$RC"
{ has "A ⊆ B (A = 1, B = 4; B has 3 extra)" && ! has "A = B ="; }; check $? "round-2 verify-pr reports A ⊆ B, never A = B"
owner_merge "$(st A untrack_branch)"; mb A after-merge
{ [ "$S1$S2$S3" = 000 ] && [ "$RC" -eq 0 ] && [ -z "$(bash "$HERE/meta-sync.sh" list-managed --tracked --root "$W/A")" ] \
  && git --git-dir="$W/origin.git" cat-file -e "$BR:.supervisor/jobs/done/late.md" 2>/dev/null && [ -z "$(porcelain A)" ]; }
check $? "the named recovery (seed -> untrack-pr -> verify-pr -> merge -> after-merge) completes the migration (seed=$S1 untrack=$S2 verify=$S3 after=$RC)"
mb A after-merge; { [ "$RC" -eq 0 ] && [ "$(grep -c '^after_merge=' "$W/A/.supervisor/migrate-branch-mode/state")" = 1 ]; }; check $? "after-merge re-run is idempotent: PASS again, one state line (rc=$RC)"
MUT="$TROOT/mut-race"
if build_mutant "$MUT" 's/^  if \[ -n "\$tm" \]; then$/  if false \&\& [ -n "$tm" ]; then/' 'if false && [ -n "$tm" ]; then'; then
  SCRIPT="$MUT/migrate-branch-mode.sh"
  if race_late; then no "mutation control REFUTED: after-merge without the tracked re-check still refused"; else ok "mutation control: without the tracked re-check, after-merge passes an incomplete migration ($RACE_DETAIL)"; fi
  SCRIPT="$SUT"
else no "mutation control (after-merge tracked re-check) did not build — counts as FAIL"; fi

echo "== 12. a step with no recorded metadata branch refuses (rec_branch in a command substitution) =="
mkworld history; mb A preflight --repo owner/repo
O0="$(git --git-dir="$W/origin.git" for-each-ref --format='%(refname) %(objectname)')"
mb A rollback --commit HEAD
{ [ "$RC" -eq 1 ] && has "no metadata branch recorded" && [ -z "$(st A rollback)" ] && [ "$(git -C "$W/A" symbolic-ref --short HEAD)" = main ] \
  && [ "$O0" = "$(git --git-dir="$W/origin.git" for-each-ref --format='%(refname) %(objectname)')" ]; }
check $? "rollback with no recorded branch exits 1 before any push, branch or state write (rc=$RC)"

echo "== 13. half-migrated FIRST migration: A ⊆ B is never accepted on the mode line alone =="
# half_migrated — main already carries the branch-mode block (setup-memory apply committed) while the
# history is still tracked; after init another checkout puts a managed file on the branch that this
# disk never held (the earlier-round shape subset mode would accept). It is not in U — U is local
# files only — so it breaks B = A + U. 0 = seed refused (A != B)
half_migrated() {
  mkworld history
  rm -rf "$W/O"; git clone -q "$W/origin.git" "$W/O" 2>/dev/null
  ( cd "$W/O" && bash "$HERE/setup-memory.sh" --root "$W/O" apply --branch-mode "$BR" >/dev/null && git add .gitignore && git commit -qm mode && git push -q origin main )
  git -C "$W/A" pull -q --ff-only origin main
  to_protected A || { HALF_DETAIL="to_protected failed: $OUT"; return 2; }
  ( cd "$W/O" && git fetch -q origin && git checkout -q -b "$BR" "origin/$BR" && mkdir -p .supervisor/jobs/done \
    && echo '# remote only' > .supervisor/jobs/done/remote-only.md && git add -f .supervisor/jobs/done/remote-only.md \
    && git commit -qm remote-only && git push -q origin "$BR" ) >/dev/null 2>&1 || { HALF_DETAIL="could not put remote-only.md on $BR"; return 2; }
  mb A seed
  HALF_DETAIL="rc=$RC mode=$(bash "$HERE/setup-memory.sh" --root "$W/A" mode) followup=$(st A followup) seed=$(st A seed)"
  [ "$RC" -eq 1 ] && [ "$(st A seed)" = FAIL ] && has "A != B" && ! has "A ⊆ B"
}
half_migrated; check $? "mode line 'on $BR' + tracked history + a branch-only managed file, no recorded after-merge -> seed FAIL ($HALF_DETAIL)"
MUT="$TROOT/mut-subset-mode-line"
if build_mutant "$MUT" 's/^  if \[ "\$(state_get followup)" = 1 \] && \[ "\$(read_mode)" = "on \$b" \]; then$/  if [ "$(read_mode)" = "on $b" ]; then/' '  if [ "$(read_mode)" = "on $b" ]; then'; then
  SCRIPT="$MUT/migrate-branch-mode.sh"
  if half_migrated; then no "mutation control REFUTED: subset mode on the mode line alone still failed seed"; else ok "mutation control: subset mode keyed on the mode line alone passes the half-migrated seed ($HALF_DETAIL)"; fi
  SCRIPT="$SUT"
else no "mutation control (subset mode on the mode line) did not build — counts as FAIL"; fi

echo "== 14. a re-cut untrack PR stales the earlier verify-pr PASS =="
hist_to_untrack; mb A verify-pr "$(pr_n pr_untrack)"; V1="$RC"
mb A untrack-pr; U2="$RC"
mb A state; { [ "$V1$U2" = 00 ] && has "next: verify-pr" && [ "$(st A verify_pr)" = STALE ]; }; check $? "re-cut untrack-pr -> verify_pr STALE, state next: verify-pr (verify=$V1 untrack=$U2)"
owner_merge "$(st A untrack_branch)"; mb A after-merge
{ [ "$RC" -eq 1 ] && has "refused: step 'verify_pr' is 'STALE'"; }; check $? "after-merge refuses: the PASS was for the earlier PR (rc=$RC)"
mb A seed; { [ "$(st A untrack_pr)" = STALE ] && [ "$(st A verify_pr)" = STALE ]; }; check $? "a re-run seed stales untrack-pr and verify-pr"
[ "$(grep -c '^verify_pr=' "$W/A/.supervisor/migrate-branch-mode/state")" = 1 ]; check $? "state file keeps one verify_pr line"

echo "== 15. after-merge proves the untrack PR merged (half-migrated, premature after-merge) =="
# premature_after_merge — a half-migrated first migration (main already `on $BR`, history tracked,
# no extra local file) seeds A = B, cuts + verifies the untrack PR, then after-merge runs BEFORE the
# owner merges. 0 = refused, nothing recorded (no followup, untrack_pr/verify_pr still PASS)
premature_after_merge() {
  mkworld history
  rm -rf "$W/O"; git clone -q "$W/origin.git" "$W/O" 2>/dev/null
  ( cd "$W/O" && bash "$HERE/setup-memory.sh" --root "$W/O" apply --branch-mode "$BR" >/dev/null && git add .gitignore && git commit -qm mode && git push -q origin main )
  git -C "$W/A" pull -q --ff-only origin main
  to_protected A || { PREM_DETAIL="to_protected failed: $OUT"; return 2; }
  mb A seed; PREM_SEED="$RC"; PREM_SEED_OUT="$OUT"
  mb A untrack-pr; mb A verify-pr "$(pr_n pr_untrack)"; PREM_VERIFY="$RC"
  mb A after-merge
  PREM_DETAIL="seed=$PREM_SEED verify=$PREM_VERIFY after=$RC followup=$(st A followup) untrack_pr=$(st A untrack_pr) verify_pr=$(st A verify_pr) seed_state=$(st A seed)"
  [ "$RC" -ne 0 ] && has "untrack PR not merged yet" && [ -z "$(st A followup)" ] \
    && [ "$(st A untrack_pr)" = PASS ] && [ "$(st A verify_pr)" = PASS ] && [ "$(st A seed)" = PASS ] \
    && ! grep -q '^followup=' "$W/A/.supervisor/migrate-branch-mode/state"
}
premature_after_merge; check $? "premature after-merge on a half-migrated repo refuses, records no followup, keeps untrack_pr/verify_pr PASS ($PREM_DETAIL)"
{ [ "$PREM_SEED" = 0 ] && [ "$(st A seed_check)" = equal ] && grep -qF "path lists equal" <<<"$PREM_SEED_OUT" && ! grep -qF "A ⊆ B" <<<"$PREM_SEED_OUT"; }; check $? "a half-migrated first migration with exact A = B seeds PASS as 'equal' (seed=$PREM_SEED)"
owner_merge "$(st A untrack_branch)"; mb A after-merge
{ [ "$RC" -eq 0 ] && [ -z "$(st A followup)" ] && [ -z "$(bash "$HERE/meta-sync.sh" list-managed --tracked --root "$W/A")" ] && [ -z "$(porcelain A)" ]; }; check $? "after the owner's real merge, after-merge PASS (rc=$RC)"
mb A after-merge; [ "$RC" -eq 0 ]; check $? "after-merge re-run after the real merge PASSes again (rc=$RC)"
DUPS="$(sed 's/=.*//' "$W/A/.supervisor/migrate-branch-mode/state" | env LC_ALL=C sort | env LC_ALL=C uniq -d | tr '\n' ' ')"
[ -z "$DUPS" ]; check $? "state file has no duplicate keys (${DUPS:-none})"
MUT="$TROOT/mut-merge-proof"
if build_mutant "$MUT" 's/^    if \[ -n "\$open" \] \&\& ! untrack_head_merged; then$/    if false; then/' '    if false; then'; then
  SCRIPT="$MUT/migrate-branch-mode.sh"
  if premature_after_merge; then no "mutation control REFUTED: after-merge without the merge proof still refused"; else ok "mutation control: without the merge proof, a premature after-merge records a false follow-up ($PREM_DETAIL)"; fi
  SCRIPT="$SUT"
else no "mutation control (after-merge merge proof) did not build — counts as FAIL"; fi

echo "== 16. followup lifecycle: kept by a mid-round preflight, dropped by a new preflight and by rollback =="
race_late; R16="$RC"; M16="$MERGE_SHA"
mb A preflight --repo owner/repo; P16="$RC"
{ [ "$R16" = 1 ] && [ "$P16" = 0 ] && [ "$(st A followup)" = 1 ]; }; check $? "preflight while after_merge is FAIL keeps followup=1 (race=$R16 preflight=$P16 followup=$(st A followup))"
printf 'after_merge=PASS\n' >> "$W/A/.supervisor/migrate-branch-mode/state"
mb A preflight --repo owner/repo
{ [ "$RC" -eq 0 ] && ! grep -q '^followup=' "$W/A/.supervisor/migrate-branch-mode/state"; }; check $? "a preflight that starts a new migration drops followup (rc=$RC)"
printf 'followup=1\n' >> "$W/A/.supervisor/migrate-branch-mode/state"
mb A rollback --commit "$M16"
{ [ "$RC" -eq 0 ] && ! grep -q '^followup=' "$W/A/.supervisor/migrate-branch-mode/state"; }; check $? "rollback drops followup (rc=$RC)"

echo "== 17. after-merge checks managed paths containing a space verbatim =="
SP=".supervisor/jobs/done/my brief.md"; SG=".supervisor/jobs/done/a b.md"; SS=".supervisor/jobs/done/a_b.md"
# spaced_merged — a history migration whose run history holds spaced names (and a sibling a_b.md
# that a `?` glob of "a b.md" would match), run to the owner's merge; leaves verify_pr PASS
spaced_merged() {
  mkworld history
  ( cd "$W/A" && echo '# spaced' > "$SP" && echo '# a b' > "$SG" && echo '# a_b' > "$SS" \
    && git add -f -- "$SP" "$SG" "$SS" && git commit -qm spaced && git push -q origin main )
  to_protected A && mb A seed && mb A untrack-pr && mb A verify-pr "$(pr_n pr_untrack)" || return 1
  owner_merge "$(st A untrack_branch)"
}
# am_in_root — after-merge with cwd = the checkout, where an unquoted `?` word would glob
am_in_root() { local here="$PWD"; cd "$W/A" || return 1; mb A after-merge; cd "$here" || return 1; }
# spaced_leg — 0 = PASS with spaced names, FAIL naming a genuinely missing spaced path, FAIL on
# "a b.md" missing while its glob sibling a_b.md is present; detail in SPACED_DETAIL
spaced_leg() {
  local r1 r2 r3 r4 n2=no n3=no
  spaced_merged || { SPACED_DETAIL="setup failed (rc=$RC)"; return 1; }
  mb A after-merge; r1="$RC"
  rm -f "$W/A/$SP"; mb A after-merge; r2="$RC"; has "missing after pull: $SP" && n2=yes
  git -C "$W/A" cat-file blob "origin/$BR:$SP" > "$W/A/$SP"
  rm -f "$W/A/$SG"; am_in_root; r3="$RC"; has "missing after pull: $SG" && n3=yes
  git -C "$W/A" cat-file blob "origin/$BR:$SG" > "$W/A/$SG"
  mb A after-merge; r4="$RC"
  SPACED_DETAIL="pass=$r1 missing=$r2 named=$n2 sibling=$r3 named=$n3 recovered=$r4"
  [ "$r1" -eq 0 ] && [ "$r2" -eq 1 ] && [ "$n2" = yes ] && [ "$r3" -eq 1 ] && [ "$n3" = yes ] && [ "$r4" -eq 0 ]
}
spaced_leg; check $? "after-merge: spaced paths PASS when present, FAIL naming a missing one, no glob-sibling false PASS ($SPACED_DETAIL)"
MUT="$TROOT/mut-spaced"
# restores the pre-fix loop verbatim: for p in $(... | tr ' ' '?'); do ... done
MSED='/keeps .miss. in this shell/,/^  done < <(g ls-tree/{
s/^  while IFS= read -r p; do$/  for p in $(g ls-tree -r --name-only "refs\/remotes\/origin\/$b" | tr '\'' '\'' '\''?'\''); do/
/^    \[ -n "\$p" \] || continue$/d
s/^  done < <(g ls-tree.*$/  done/
}'
if build_mutant "$MUT" "$MSED" "| tr ' ' '?'); do"; then
  SCRIPT="$MUT/migrate-branch-mode.sh"
  if spaced_leg; then no "mutation control REFUTED: the old tr ' ' '?' loop still passed the spaced leg"; else ok "mutation control: the old tr ' ' '?' loop turns the spaced leg red ($SPACED_DETAIL)"; fi
  SCRIPT="$SUT"
else no "mutation control (after-merge spaced paths) did not build — counts as FAIL"; fi

echo "== 18. half-migrated: init defaults to the mode line's branch; rehearse works =="
# half_init — main already `on $BR`, history tracked; 0 = plan + init (+ refusal) behave; detail in HI_DETAIL
half_init() {
  mkworld history
  rm -rf "$W/O"; git clone -q "$W/origin.git" "$W/O" 2>/dev/null
  ( cd "$W/O" && bash "$HERE/setup-memory.sh" --root "$W/O" apply --branch-mode "$BR" >/dev/null && git add .gitignore && git commit -qm mode && git push -q origin main )
  git -C "$W/A" pull -q --ff-only origin main
  local p1 r1 r2 n1=no
  mb A plan; p1="$RC"; has "metadata branch: $BR (init's default, from the mode line 'on $BR'" || p1="no-default:$p1"
  mb A preflight --repo owner/repo; mb A scrub
  mb A init --branch other-meta; r1="$RC"; has "disagrees with the mode line 'on $BR'" && n1=yes
  { [ -z "$(st A branch)" ] && [ -z "$(st A init)" ] && ! remote_has other-meta; } || n1="wrote:$n1"
  mb A init; r2="$RC"
  HI_DETAIL="plan=$p1 mismatch=$r1 named=$n1 init=$r2 branch=$(st A branch)"
  [ "$p1" = 0 ] && [ "$r1" -eq 1 ] && [ "$n1" = yes ] && [ "$r2" -eq 0 ] && [ "$(st A branch)" = "$BR" ] && remote_has "$BR" && ! remote_has loomwright-meta
}
half_init; check $? "half-migrated: plan names $BR, a mismatching --branch is refused (nothing written), init records $BR ($HI_DETAIL)"
O0="$(git --git-dir="$W/origin.git" for-each-ref --format='%(refname) %(objectname)')"
mb A rehearse
{ [ "$RC" -eq 0 ] && has "rehearse: PASS" && has "info: half-migrated checkout" && ! has "FAIL:" && [ "$(st A rehearse)" = PASS ]; }; check $? "half-migrated: the real rehearse passes (scratch reset to off) with the recorded $BR (rc=$RC)"
[ "$O0" = "$(git --git-dir="$W/origin.git" for-each-ref --format='%(refname) %(objectname)')" ]; check $? "half-migrated rehearse never touches the real remote"
mkworld history; mb A plan; has "metadata branch: loomwright-meta (init's default"; check $? "no mode line: plan prints loomwright-meta as init's default"
MUT="$TROOT/mut-init-default"
if build_mutant "$MUT" 's/^  mb="\$(mode_branch)"; b="\${OPT_BRANCH:-\$(init_default_branch)}"$/  mb=""; b="${OPT_BRANCH:-loomwright-meta}"/' '  mb=""; b="${OPT_BRANCH:-loomwright-meta}"'; then
  SCRIPT="$MUT/migrate-branch-mode.sh"
  if half_init; then no "mutation control REFUTED: init ignoring the mode line still passed the leg"; else ok "mutation control: init ignoring the mode line turns the leg red ($HI_DETAIL)"; fi
  SCRIPT="$SUT"
else no "mutation control (init default) did not build — counts as FAIL"; fi

echo "== 19. A/B check + verify-pr under a non-C locale (every comm pinned to env LC_ALL=C) =="
NCL=""
for l in en_US.UTF-8 en_US.utf8; do grep -qx "$l" < <(locale -a 2>/dev/null) && { NCL="$l"; break; }; done
LX=".supervisor/jobs/done"
# locale_leg — the SUT runs under $NCL on managed names whose C and en_US order differ; 0 = seed
# PASS listing only the salvage path for the owner, verify-pr names exactly the one managed path the
# stale PR leaves tracked, and the re-cut PR verifies PASS. Detail in LOC_DETAIL.
locale_leg() {
  local s1 v1 v2 x1=no m1=no
  mkworld history
  ( cd "$W/A" && for n in B.md a-x.md a_x.md Zeta-1.md zeta_1.md; do echo "# $n" > "$LX/$n"; done \
    && git add -f -- "$LX" && git commit -qm names && git push -q origin main )
  MB_LOCALE="$NCL"
  to_protected A; mb A seed; s1="$RC"
  has "OWNER DECISION: 1 tracked .supervisor/ path(s)" && x1=yes
  mb A untrack-pr
  # Zz-new.md sorts before a-x.md in C but after it in en_US: an unguarded comm misaligns there and
  # reports a-x.md .. zeta_1.md (all untracked by the PR) as missing too
  rm -rf "$W/O"; git clone -q "$W/origin.git" "$W/O" 2>/dev/null
  ( cd "$W/O" && echo '# new' > "$LX/Zz-new.md" && git add -f -- "$LX/Zz-new.md" && git commit -qm new && git push -q origin main )
  mb A verify-pr "$(pr_n pr_untrack)"; v1="$RC"
  has "leaves tracked managed path(s) tracked: $LX/Zz-new.md — re-cut" && m1=yes
  mb A seed; mb A untrack-pr; mb A verify-pr "$(pr_n pr_untrack)"; v2="$RC"
  MB_LOCALE=""
  LOC_DETAIL="locale=$NCL seed=$s1 owner-list-salvage-only=$x1 stale-verify=$v1 named-exactly=$m1 recut-verify=$v2"
  [ "$s1" -eq 0 ] && [ "$x1" = yes ] && [ "$v1" -eq 1 ] && [ "$m1" = yes ] && [ "$v2" -eq 0 ]
}
if [ -z "$NCL" ]; then
  echo "  SKIP: no en_US UTF-8 locale in 'locale -a' — leg 19 and its mutation control are INCONCLUSIVE on this host"
else
  locale_leg; check $? "under $NCL: owner list, exact missing path and re-cut PASS all hold ($LOC_DETAIL)"
  MUT="$TROOT/mut-comm-locale"
  if build_mutant "$MUT" 's/env LC_ALL=C sort | env LC_ALL=C comm -13 - /env LC_ALL=C sort | comm -13 - /' 'env LC_ALL=C sort | comm -13 - '; then
    SCRIPT="$MUT/migrate-branch-mode.sh"
    if locale_leg; then no "mutation control REFUTED: the unguarded verify-pr comm still passed under $NCL"; else ok "mutation control: the verify-pr comm without env LC_ALL=C turns the leg red ($LOC_DETAIL)"; fi
    SCRIPT="$SUT"
  else no "mutation control (verify-pr comm locale) did not build — counts as FAIL"; fi
fi

echo "== 20. rollback of an untrack PR merged as a real 2-parent merge commit =="
# merge_rollback_leg — leg 5's flow (c.md lands on main mid-flight), the owner merges with --no-ff,
# then rollback --commit <the merge commit>; 0 = a 2-parent commit and nothing lost. Detail in MR_DETAIL.
merge_rollback_leg() {
  local am rb np=0
  hist_to_untrack; verify_newfile
  mb A seed; mb A untrack-pr; mb A verify-pr "$(pr_n pr_untrack)"
  owner_merge "$(st A untrack_branch)"; mb A after-merge; am="$RC"
  np="$(git --git-dir="$W/origin.git" rev-list --parents -n 1 "$MERGE_SHA" | wc -w | tr -d ' ')"
  rollback_scenario "$MERGE_SHA"; rb=$?
  MR_DETAIL="after-merge=$am parents=$((np - 1)) $ROLLBACK_DETAIL"
  [ "$am" -eq 0 ] && [ "$np" -eq 3 ] && [ "$rb" -eq 0 ]
}
merge_rollback_leg; check $? "rollback --commit <2-parent merge> keeps the edit, add and delete ($MR_DETAIL)"
MUT="$TROOT/mut-revert-m1"
if build_mutant "$MUT" 's/then g revert --no-commit -m 1 "\$c"; else/then g revert --no-commit "$c"; else/' 'then g revert --no-commit "$c"; else'; then
  SCRIPT="$MUT/migrate-branch-mode.sh"
  if merge_rollback_leg; then no "mutation control REFUTED: rollback without -m 1 still reverted the merge commit"; else ok "mutation control: rollback without -m 1 turns the 2-parent leg red ($MR_DETAIL)"; fi
  SCRIPT="$SUT"
else no "mutation control (rollback -m 1) did not build — counts as FAIL"; fi

echo "== 21. seed A/B: an unmanaged stray on the branch breaks A = B; consented learning stores do not =="
# stray_leg [strays] — history world, consent granted, one learning store (eval/results.jsonl) local,
# so the seed push publishes it to the branch; with "strays", three UNMANAGED entries of a managed
# KIND (NOTES.md, jobs/pending/stray.md, logs/stray.md) are put on the branch before seed.
# 0 = the expected outcome (strays: seed FAIL naming all three; none: seed PASS). Detail in STRAY_DETAIL.
stray_leg() {
  local learn
  mkworld history; to_protected A || { STRAY_DETAIL="to_protected failed: $OUT"; return 1; }
  mkdir -p "$W/A/.supervisor/eval"; echo '{"run":"r1","score":1}' > "$W/A/.supervisor/eval/results.jsonl"
  bash "$HERE/setup-memory.sh" --root "$W/A" consent grant >/dev/null 2>&1
  if [ "${1:-}" = strays ]; then
    rm -rf "$W/O"; git clone -q "$W/origin.git" "$W/O" 2>/dev/null
    ( cd "$W/O" && git checkout -q -b "$BR" "origin/$BR" && mkdir -p .supervisor/jobs/pending .supervisor/logs \
      && echo n > NOTES.md && echo '# p' > .supervisor/jobs/pending/stray.md && echo '# l' > .supervisor/logs/stray.md \
      && git add -f NOTES.md .supervisor && git commit -qm strays && git push -q origin "$BR" ) >/dev/null 2>&1 \
      || { STRAY_DETAIL="could not put the strays on $BR"; return 1; }
  fi
  mb A seed
  learn="$(git --git-dir="$W/origin.git" cat-file -e "$BR:.supervisor/eval/results.jsonl" 2>/dev/null && echo yes || echo no)"
  STRAY_DETAIL="rc=$RC seed=$(st A seed) learning-store-on-branch=$learn"
  [ "$learn" = yes ] || return 1
  if [ "${1:-}" = strays ]; then
    [ "$RC" -ne 0 ] && [ "$(st A seed)" = FAIL ] && has "A != B" \
      && has "NOTES.md" && has ".supervisor/jobs/pending/stray.md" && has ".supervisor/logs/stray.md"
  else
    [ "$RC" -eq 0 ] && [ "$(st A seed)" = PASS ] && has "path lists equal" && [ "$(st A seed_b)" = 3 ]
  fi
}
stray_leg; check $? "a consented learning store on the branch is subtracted from B: seed PASS, A = B = 3 ($STRAY_DETAIL)"
stray_leg strays; check $? "unmanaged strays on the branch stay in B: seed FAIL naming all three ($STRAY_DETAIL)"
# mutation control: the narrowing this leg guards against — B = the run-history entries only
MUT="$TROOT/mut-ab-narrow"
MSED="$(cat <<'SED'
s/^  env LC_ALL=C comm -23 "\$2\.all" "\$2\.rh" > "\$2" || return 1$/  cp "$2.rh" "$2" || return 1/
s/ !(\$2 in ls)' "\$SD\/b\.learn"/ ($2 in ls)' "$SD\/b.learn"/
SED
)"
if build_mutant "$MUT" "$MSED" 'cp "$2.rh" "$2" || return 1' && grep -qF "(\$2 in ls)' \"\$SD/b.learn\"" "$MUT/migrate-branch-mode.sh" \
   && ! grep -qF "!(\$2 in ls)" "$MUT/migrate-branch-mode.sh"; then
  SCRIPT="$MUT/migrate-branch-mode.sh"
  if stray_leg strays; then no "mutation control REFUTED: B = run history only still failed the stray seed"; else ok "mutation control: B = run history only drops the strays and turns the leg red ($STRAY_DETAIL)"; fi
  SCRIPT="$SUT"
else no "mutation control (A/B stray narrowing) did not build — counts as FAIL"; fi

echo "== 22. a tracked learning store stays tracked: run history alone is migrated =="
EV=".supervisor/eval/results.jsonl"
# tracked_learning_leg <none|grant> — history world plus $EV force-tracked on main; the full history
# flow to after-merge. 0 = seed PASS (A = B = 3), $EV named as an owner-decision extra and never
# untracked, after-merge PASS, plan reads `already`. Detail in TL_DETAIL.
tracked_learning_leg() {
  local ub
  mkworld history
  ( cd "$W/A" && mkdir -p .supervisor/eval && echo '{"run":"r1","score":1}' > "$EV" \
    && git add -f "$EV" && git commit -qm eval && git push -q origin main ) >/dev/null 2>&1 \
    || { TL_DETAIL="could not commit $EV"; return 1; }
  [ "$1" = grant ] && bash "$HERE/setup-memory.sh" --root "$W/A" consent grant >/dev/null 2>&1
  to_protected A || { TL_DETAIL="to_protected failed: $OUT"; return 1; }
  mb A seed
  TL_DETAIL="consent=$1 seed rc=$RC seed=$(st A seed) A=$(st A seed_a) B=$(st A seed_b)"
  { [ "$RC" -eq 0 ] && [ "$(st A seed)" = PASS ] && [ "$(st A seed_a)" = 3 ] && [ "$(st A seed_b)" = 3 ] \
    && has "OWNER DECISION: 2 tracked .supervisor/ path(s)" && grep -qx "  $EV" <<<"$OUT"; } || return 1
  mb A untrack-pr || { TL_DETAIL="$TL_DETAIL; untrack-pr rc=$RC"; return 1; }
  ub="$(st A untrack_branch)"
  git --git-dir="$W/origin.git" cat-file -e "$ub:$EV" 2>/dev/null || { TL_DETAIL="$TL_DETAIL; the untrack PR untracks $EV"; return 1; }
  mb A verify-pr "$(pr_n pr_untrack)" || { TL_DETAIL="$TL_DETAIL; verify-pr rc=$RC"; return 1; }
  owner_merge "$ub"; TL_MERGE="$MERGE_SHA"
  mb A after-merge
  TL_DETAIL="$TL_DETAIL; after-merge rc=$RC"
  { [ "$RC" -eq 0 ] && [ "$(st A after_merge)" = PASS ] && git -C "$W/A" ls-files --error-unmatch -- "$EV" >/dev/null 2>&1 \
    && [ -f "$W/A/$EV" ] && [ -z "$(porcelain A)" ]; } || return 1
  mb A plan
  TL_DETAIL="$TL_DETAIL; plan rc=$RC"
  [ "$RC" -eq 0 ] && has "already in branch mode on $BR"
}
tracked_learning_leg none; check $? "consent none: a tracked learning store is an owner-decision extra, seed PASS A = B = 3, kept tracked through after-merge, plan reads already ($TL_DETAIL)"
tracked_learning_leg grant; check $? "consent grant: the same, with the store also on the branch ($TL_DETAIL)"
# hand_rollback_leg — after leg 22 (grant): the OWNER untracks $EV in a hand-made commit on main, then
# rollback --commit <that commit>. 0 = $EV re-tracked by the revert, in the rollback tree with its
# bytes, still on disk (gone.list never deletes a learning store). Detail in HR_DETAIL.
hand_rollback_leg() {
  local c rb
  tracked_learning_leg grant || { HR_DETAIL="setup: $TL_DETAIL"; return 1; }
  ( cd "$W/A" && git rm -q --cached -- "$EV" && git commit -qm "untrack $EV" && git push -q origin main ) >/dev/null 2>&1 \
    || { HR_DETAIL="could not untrack $EV by hand"; return 1; }
  c="$(git -C "$W/A" rev-parse HEAD)"
  mb A rollback --commit "$c"; rb="$(st A rollback_branch)"
  HR_DETAIL="rc=$RC on-disk=$([ -f "$W/A/$EV" ] && echo yes || echo no) in-tree=$(git -C "$W/A" cat-file -e "$rb:$EV" 2>/dev/null && echo yes || echo no)"
  [ "$RC" -eq 0 ] && [ -f "$W/A/$EV" ] && [ "$(cat "$W/A/$EV")" = '{"run":"r1","score":1}' ] \
    && git -C "$W/A" cat-file -e "$rb:$EV" 2>/dev/null
}
hand_rollback_leg; check $? "rollback of a hand-made commit that untracked a learning store re-tracks it and never deletes it from disk ($HR_DETAIL)"
MUT="$TROOT/mut-tracked-rh"
if build_mutant "$MUT" 's/^tracked_managed() { bash "\$MS" list-managed --tracked --run-history --root "\$ROOT"; }$/tracked_managed() { bash "$MS" list-managed --tracked --root "$ROOT"; }/' \
   'tracked_managed() { bash "$MS" list-managed --tracked --root "$ROOT"; }'; then
  SCRIPT="$MUT/migrate-branch-mode.sh"
  for cs in none grant; do
    if tracked_learning_leg "$cs"; then no "mutation control REFUTED: tracked_managed without --run-history kept the consent-$cs leg green"
    else ok "mutation control: tracked_managed without --run-history turns the consent-$cs leg red ($TL_DETAIL)"; fi
  done
  SCRIPT="$SUT"
else no "mutation control (tracked_managed --run-history) did not build — counts as FAIL"; fi
MUT="$TROOT/mut-gone-learn"
if build_mutant "$MUT" 's/^    | grep -vxF -f "\$SD\/staged\.learn" > "\$SD\/gone\.list"$/    > "$SD\/gone.list"/' '    > "$SD/gone.list"'; then
  SCRIPT="$MUT/migrate-branch-mode.sh"
  if hand_rollback_leg; then no "mutation control REFUTED: gone.list without the learning-store filter kept the store"; else ok "mutation control: gone.list without the learning-store filter deletes the store ($HR_DETAIL)"; fi
  SCRIPT="$SUT"
else no "mutation control (gone.list learning filter) did not build — counts as FAIL"; fi

echo "== 23. rollback never commits a branch learning store to the default branch =="
# rollback_learning_leg — history flow with consent granted and an UNTRACKED $EV, so seed publishes
# it to the branch; after-merge, then rollback. 0 = $EV on the branch, NOT in the rollback tree,
# still on disk, while the run history is re-tracked and the tree is clean. Detail in RL_DETAIL.
rollback_learning_leg() {
  local rb
  mkworld history
  mkdir -p "$W/A/.supervisor/eval"; echo '{"run":"r1","score":1}' > "$W/A/$EV"
  bash "$HERE/setup-memory.sh" --root "$W/A" consent grant >/dev/null 2>&1
  to_protected A && mb A seed && mb A untrack-pr && mb A verify-pr "$(pr_n pr_untrack)" || { RL_DETAIL="flow failed at rc=$RC: $(printf '%s' "$OUT" | tail -n 2)"; return 1; }
  owner_merge "$(st A untrack_branch)"
  mb A after-merge || { RL_DETAIL="after-merge rc=$RC"; return 1; }
  git --git-dir="$W/origin.git" cat-file -e "$BR:$EV" 2>/dev/null || { RL_DETAIL="$EV never reached $BR"; return 1; }
  mb A rollback --commit "$MERGE_SHA"; rb="$(st A rollback_branch)"
  RL_DETAIL="rc=$RC in-rollback-tree=$(git -C "$W/A" cat-file -e "$rb:$EV" 2>/dev/null && echo yes || echo no) on-disk=$([ -f "$W/A/$EV" ] && echo yes || echo no)"
  [ "$RC" -eq 0 ] && remote_has "$rb" && ! git -C "$W/A" cat-file -e "$rb:$EV" 2>/dev/null && [ -f "$W/A/$EV" ] \
    && git -C "$W/A" cat-file -e "$rb:.supervisor/jobs/done/a.md" 2>/dev/null \
    && git -C "$W/A" cat-file -e "$rb:.supervisor/requirements/q/req.md" 2>/dev/null && [ -z "$(porcelain A)" ]
}
rollback_learning_leg; check $? "rollback re-tracks run history but never the branch's learning store, which stays on disk ($RL_DETAIL)"
MUT="$TROOT/mut-rb-learn"
if build_mutant "$MUT" 's/^  grep -vxF -f "\$SD\/onbranch\.learn" "\$SD\/onbranch\.all"/  grep -vxF -f \/dev\/null "$SD\/onbranch.all"/' 'grep -vxF -f /dev/null "$SD/onbranch.all"'; then
  SCRIPT="$MUT/migrate-branch-mode.sh"
  if rollback_learning_leg; then no "mutation control REFUTED: re-tracking every branch path kept the learning store out of the rollback tree"; else ok "mutation control: re-tracking every branch path commits the learning store and turns the leg red ($RL_DETAIL)"; fi
  SCRIPT="$SUT"
else no "mutation control (rollback learning subtraction) did not build — counts as FAIL"; fi

echo "== 24. a tracked learning store diverged on the branch: after-merge stays clean (git owns it) =="
# diverged_learning_leg <none|grant> — the review's repro: history world with $EV force-tracked on
# main, seed PASS (A = B = 3), then a TEAMMATE (a clone that does not track it) adds a line to $EV
# on $BR; untrack-pr -> verify-pr -> owner merge -> after-merge. 0 = after-merge PASS with an empty
# porcelain, $EV byte-unchanged and still tracked, meta-sync naming it `learning_tracked`, and the
# teammate's line still on $BR. Detail in DL_DETAIL.
diverged_learning_leg() {
  local ev0 brev
  mkworld history
  ( cd "$W/A" && mkdir -p .supervisor/eval && echo '{"run":"r1","score":1}' > "$EV" \
    && git add -f "$EV" && git commit -qm eval && git push -q origin main ) >/dev/null 2>&1 \
    || { DL_DETAIL="could not commit $EV"; return 1; }
  [ "$1" = grant ] && bash "$HERE/setup-memory.sh" --root "$W/A" consent grant >/dev/null 2>&1
  to_protected A || { DL_DETAIL="to_protected failed: $OUT"; return 1; }
  mb A seed
  DL_DETAIL="consent=$1 seed rc=$RC A=$(st A seed_a) B=$(st A seed_b)"
  { [ "$RC" -eq 0 ] && [ "$(st A seed)" = PASS ] && [ "$(st A seed_a)" = 3 ] && [ "$(st A seed_b)" = 3 ]; } || return 1
  rm -rf "$W/T"; git clone -q "$W/origin.git" "$W/T" 2>/dev/null
  ( cd "$W/T" && git checkout -q -b "$BR" "origin/$BR" && mkdir -p .supervisor/eval \
    && { git show "origin/$BR:$EV" 2>/dev/null || cat "$W/A/$EV"; } > "$EV.new" && mv "$EV.new" "$EV" \
    && echo '{"run":"teammate","score":2}' >> "$EV" && git add -f "$EV" && git commit -qm "teammate eval line" \
    && git push -q origin "$BR" ) >/dev/null 2>&1 || { DL_DETAIL="$DL_DETAIL; teammate push failed"; return 1; }
  brev="$(git --git-dir="$W/origin.git" show "$BR:$EV" 2>/dev/null)"
  ev0="$(cat "$W/A/$EV")"
  mb A untrack-pr || { DL_DETAIL="$DL_DETAIL; untrack-pr rc=$RC"; return 1; }
  mb A verify-pr "$(pr_n pr_untrack)" || { DL_DETAIL="$DL_DETAIL; verify-pr rc=$RC: $(printf '%s' "$OUT" | tail -n 2)"; return 1; }
  owner_merge "$(st A untrack_branch)"
  mb A after-merge
  DL_DETAIL="$DL_DETAIL; after-merge rc=$RC state=$(st A after_merge) porcelain='$(porcelain A | tr '\n' ' ')' ev-same=$([ "$(cat "$W/A/$EV")" = "$ev0" ] && echo yes || echo no)"
  [ "$RC" -eq 0 ] && [ "$(st A after_merge)" = PASS ] && [ -z "$(porcelain A)" ] && [ "$(cat "$W/A/$EV")" = "$ev0" ] \
    && git -C "$W/A" ls-files --error-unmatch -- "$EV" >/dev/null 2>&1 \
    && has "meta_sync: learning_tracked $EV — tracked by git, left to git" \
    && [ "$(git --git-dir="$W/origin.git" show "$BR:$EV" 2>/dev/null)" = "$brev" ]
}
diverged_learning_leg none; check $? "consent none: a tracked learning store the branch diverged on is left to git — after-merge PASS, clean, the store unchanged and tracked ($DL_DETAIL)"
diverged_learning_leg grant; check $? "consent grant: the same, and the branch's copy is never overwritten ($DL_DETAIL)"
# mutation control: meta-sync.sh WITHOUT the tracked-learning hold (the sibling the SUT calls)
MUT="$TROOT/mut-ms-tracked"
mkdir -p "$MUT"; for f in "$HERE"/*; do [ -f "$f" ] && cp "$f" "$MUT/"; done
sed -e 's/^tracked_learning_hold() {$/tracked_learning_hold() { TRACKED_N=0; return 0  # mutant tracked/' "$HERE/meta-sync.sh" > "$MUT/meta-sync.sh"
if ! cmp -s "$HERE/meta-sync.sh" "$MUT/meta-sync.sh" && grep -qF '# mutant tracked' "$MUT/meta-sync.sh" && bash -n "$MUT/meta-sync.sh"; then
  SCRIPT="$MUT/migrate-branch-mode.sh"
  for cs in none grant; do
    if diverged_learning_leg "$cs"; then no "mutation control REFUTED: meta-sync without the tracked-learning hold kept the consent-$cs leg green"
    else ok "mutation control: meta-sync without the tracked-learning hold dirties the tracked store and turns the consent-$cs leg red ($DL_DETAIL)"; fi
  done
  SCRIPT="$SUT"
else no "mutation control (meta-sync tracked-learning hold) did not build — counts as FAIL"; fi

echo "== 25. an inherited GIT_INDEX_FILE cannot empty seed's OWNER DECISION extra =="
# git shim: an inherited GIT_INDEX_FILE=/nonexistent reaches ONLY `ls-files` (the tracked-set reads);
# every other git call runs with it cleared, so on_default_clean's status and meta-sync's push see the
# real index and the leg isolates the reads under test. meta-sync's own per-run index values pass.
GSHIM="$TROOT/gitshim"; mkdir -p "$GSHIM"
REAL_GIT="$(command -v git)"
cat > "$GSHIM/git" <<SHIM
#!/bin/bash
if [ "\${GIT_INDEX_FILE:-}" = /nonexistent ]; then
  case " \$* " in *" ls-files "*) : ;; *) unset GIT_INDEX_FILE ;; esac
fi
exec "$REAL_GIT" "\$@"
SHIM
chmod +x "$GSHIM/git"
# index_env_leg — history world plus $EV force-tracked on main (outside the run-history set); seed
# runs with GIT_INDEX_FILE=/nonexistent exported through the shim. 0 = seed PASS and the OWNER
# DECISION line still counts and names $EV (a missing index read would report no extra). Detail in IE_DETAIL.
index_env_leg() {
  IE_DETAIL=""
  mkworld history
  ( cd "$W/A" && mkdir -p .supervisor/eval && echo '{"run":"r1","score":1}' > "$EV" \
    && git add -f "$EV" && git commit -qm eval && git push -q origin main ) >/dev/null 2>&1 \
    || { IE_DETAIL="could not commit $EV"; return 1; }
  to_protected A || { IE_DETAIL="to_protected failed: $OUT"; return 1; }
  OUT="$(export GIT_INDEX_FILE=/nonexistent PATH="$GSHIM:$PATH"; bash "$SCRIPT" seed --root "$W/A" 2>&1)"; RC=$?
  IE_DETAIL="seed rc=$RC seed=$(st A seed) owner-line=$(has "OWNER DECISION: 2 tracked .supervisor/ path(s)" && echo yes || echo no) ev-named=$(grep -qx "  $EV" <<<"$OUT" && echo yes || echo no)"
  [ "$RC" -eq 0 ] && [ "$(st A seed)" = PASS ] && has "OWNER DECISION: 2 tracked .supervisor/ path(s)" \
    && grep -qx "  $EV" <<<"$OUT"
}
index_env_leg; check $? "an exported GIT_INDEX_FILE=/nonexistent does not empty the OWNER DECISION extra: seed PASS, the tracked learning store still named ($IE_DETAIL)"
MUT="$TROOT/mut-ab-index-env"
if build_mutant "$MUT" 's/^  env -u GIT_INDEX_FILE -u GIT_DIR -u GIT_WORK_TREE git -C "\$ROOT" -c core\.quotepath=off ls-files -- \.supervisor | /  g ls-files -- .supervisor | /' \
   '  g ls-files -- .supervisor | '; then
  SCRIPT="$MUT/migrate-branch-mode.sh"
  if index_env_leg; then no "mutation control REFUTED: ab_check's bare g ls-files kept the leg green with the inherited index honoured ($IE_DETAIL)"
  else ok "mutation control: ab_check's extra read honouring the inherited GIT_INDEX_FILE reports no extra — (25) is load-bearing ($IE_DETAIL)"; fi
  SCRIPT="$SUT"
else no "mutation control (ab_check index env) did not build — counts as FAIL"; fi

echo "== 26. ignored dismissed-decisions ledgers (the A = 63, B = 66 field failure): B = A + U =="
# dd_leg — the DEFAULT block on main (setup-memory apply, no --branch-mode): 3 history files + 60
# automate/run-N.md committed through it (A = 63), then three ignored <run>.dismissed-decisions
# ledgers on A's disk only (U = 3). 0 = seed PASS with B = A + U (66 = 63 + 3). Detail in DD_DETAIL.
DDL=".supervisor/automate/automate-2026-10-12-000001.dismissed-decisions"
dd_leg() {
  local i
  DD_DETAIL=""
  mkworld history
  rm -rf "$W/O"; git clone -q "$W/origin.git" "$W/O" 2>/dev/null
  ( cd "$W/O" && printf '*.log\n' > .gitignore && bash "$HERE/setup-memory.sh" --root "$W/O" apply >/dev/null 2>&1 \
    && rm -f .gitignore.backup.* && mkdir -p .supervisor/automate \
    && i=1 && while [ "$i" -le 60 ]; do printf '# Automate Run: run-%s\n\n## Status: done\n' "$i" > ".supervisor/automate/run-$i.md"; i=$((i+1)); done \
    && git add .gitignore .supervisor/automate && git commit -qm "default block + run history" && git push -q origin main ) >/dev/null 2>&1 \
    || { DD_DETAIL="could not build the default-block world"; return 1; }
  git -C "$W/A" pull -q --ff-only origin main
  for i in 1 2 3; do
    printf 'automate-x--a-1--dismissed-%s.md\tdrop\t2026-10-12T00:00:0%sZ\n' "$i" "$i" > "$W/A/${DDL%000001.dismissed-decisions}00000$i.dismissed-decisions"
  done
  [ -z "$(porcelain A)" ] && git -C "$W/A" check-ignore -q -- "$DDL" || { DD_DETAIL="the default block does not keep the ledger ignored (porcelain: $(porcelain A | tr '\n' ' '))"; return 1; }
  to_protected A; [ "$(st A preflight)$(st A protect)" = PASSPASS ] || { DD_DETAIL="preflight=$(st A preflight) protect=$(st A protect): $OUT"; return 1; }
  mb A seed
  DD_DETAIL="seed rc=$RC seed=$(st A seed) a=$(st A seed_a) u=$(st A seed_u) b=$(st A seed_b)"
  [ "$RC" -eq 0 ] && [ "$(st A seed)" = PASS ] && [ "$(st A seed_a)" = 63 ] && [ "$(st A seed_u)" = 3 ] && [ "$(st A seed_b)" = 66 ] \
    && has "A (tracked managed on origin/main) = 63; U (managed run history on disk, gitignored) = 3; B (origin/$BR tree) = 66" \
    && has "B = A + U" && grep -qx "  $DDL" <<<"$OUT"
}
dd_leg; check $? "default block + 3 ignored dismissed-decisions ledgers: seed PASS, A = 63, U = 3, B = 66 ($DD_DETAIL)"
mb A untrack-pr; N26="$(pr_n pr_untrack)"
{ [ "$RC" -eq 0 ] && grep -qF -- "- U (managed run history on disk, gitignored" "$STUBD/body.$N26" && grep -qF -- "- path-list diff A + U vs B: empty" "$STUBD/body.$N26" \
  && ! grep -qF -- "diff A vs B" "$STUBD/body.$N26"; }; check $? "untrack PR body states the A + U relation, never 'A vs B' (rc=$RC)"
git -C "$W/A" fetch -q origin; DDR="$(git -C "$W/A" diff --name-only --diff-filter=D "origin/main" "origin/$(st A untrack_branch)" | wc -l | tr -d ' ')"
[ "$DDR" = 63 ]; check $? "the untrack PR untracks exactly A (63 paths; the ignored ledgers were never tracked) (got $DDR)"
mb A verify-pr "$N26"; { [ "$RC" -eq 0 ] && has "B = A + U (66 = 63 + 3)"; }; check $? "verify-pr PASS states B = A + U (66 = 63 + 3) (rc=$RC)"
owner_merge "$(st A untrack_branch)"; mb A after-merge
DDK=0; for i in 1 2 3; do [ -f "$W/A/${DDL%000001.dismissed-decisions}00000$i.dismissed-decisions" ] && DDK=$((DDK+1)); done
{ [ "$RC" -eq 0 ] && [ -z "$(porcelain A)" ] && [ "$DDK" = 3 ]; }; check $? "after-merge PASS, porcelain empty, the 3 ledgers still on disk (rc=$RC kept=$DDK)"
gh_never_writes; check $? "leg 26: gh never merges nor writes a ruleset"
MUT="$TROOT/mut-ab-no-u"
if build_mutant "$MUT" 's/^    diff "\$SD\/au\.list" "\$SD\/b\.list" > "\$SD\/ab-names\.diff"; diff "\$SD\/au\.ent" "\$SD\/b\.ent" > "\$SD\/ab-blobs\.diff"$/    diff "$SD\/a.list" "$SD\/b.list" > "$SD\/ab-names.diff"; diff "$SD\/a.ent" "$SD\/b.ent" > "$SD\/ab-blobs.diff"/' \
   '    diff "$SD/a.list" "$SD/b.list" > "$SD/ab-names.diff"; diff "$SD/a.ent" "$SD/b.ent"'; then
  SCRIPT="$MUT/migrate-branch-mode.sh"
  if dd_leg; then no "mutation control REFUTED: comparing B with A alone still passed the ignored-ledger seed ($DD_DETAIL)"
  elif [ "$(st A seed)" = FAIL ] && has "!= B — path lists differ" && has "> $DDL"; then ok "mutation control: B compared with A alone reproduces the field failure — seed FAIL, the path lists differ by the ledgers ($DD_DETAIL; $(grep '^migrate-branch-mode: A (' <<<"$OUT" | sed 's/^migrate-branch-mode: //'))"
  else no "mutation control: the pre-fix relation failed for another reason ($DD_DETAIL)"; printf '%s\n' "$OUT" | tail -n 6 | sed 's/^/    /'; fi
  SCRIPT="$SUT"
else no "mutation control (ab_check without U) did not build — counts as FAIL"; fi

echo "== 27. untrack-pr: no false readiness WARNING while the ledger is still tracked =="
LDG=".supervisor/postmortem/results.jsonl"
# ledger_leg — history world plus a TRACKED findings ledger (allowlisted record); seed, untrack-pr.
# 0 = untrack-pr PASS with no WARNING, its branch head reads `configured` and untracks the ledger.
ledger_leg() {
  local nb rd
  LG_DETAIL=""
  mkworld history
  ( cd "$W/A" && mkdir -p .supervisor/postmortem && echo '{"repo":"owner/repo","pr":1,"rounds":0}' > "$LDG" \
    && git add -f "$LDG" && git commit -qm ledger && git push -q origin main ) >/dev/null 2>&1 \
    || { LG_DETAIL="could not commit the ledger"; return 1; }
  to_protected A; mb A seed
  [ "$(st A seed)" = PASS ] && grep -qx "$LDG" "$W/A/.supervisor/migrate-branch-mode/a.list" \
    || { LG_DETAIL="seed=$(st A seed) (ledger in A: $(grep -cx "$LDG" "$W/A/.supervisor/migrate-branch-mode/a.list" 2>/dev/null)): $OUT"; return 1; }
  mb A untrack-pr; LG_OUT="$OUT"; nb="$(st A untrack_branch)"
  rm -rf "$W/R"; git clone -q "$W/origin.git" "$W/R" 2>/dev/null && git -C "$W/R" checkout -q "$nb" 2>/dev/null
  rd="$(bash "$HERE/setup-memory.sh" --root "$W/R" check 2>/dev/null | grep '^Memory readiness:')"
  LG_DETAIL="untrack rc=$RC state=$(st A untrack_pr) warning=$(grep -c 'WARNING' <<<"$LG_OUT") head: ${rd:-<none>} ledger-tracked-on-head=$(git -C "$W/R" ls-files -- "$LDG" | grep -c .)"
  [ "$RC" -eq 0 ] && [ "$(st A untrack_pr)" = PASS ] && grep -q '^  apply:' <<<"$LG_OUT" && ! grep -q 'WARNING' <<<"$LG_OUT" \
    && [ "$rd" = "Memory readiness: configured" ] && [ -z "$(git -C "$W/R" ls-files -- "$LDG")" ]
}
ledger_leg; check $? "tracked ledger: untrack-pr prints no readiness WARNING, its head reads configured and untracks the ledger ($LG_DETAIL)"
[ -f "$W/A/$LDG" ] && [ -z "$(porcelain A)" ]; check $? "the ledger stays on disk and the checkout is clean after untrack-pr"
MUT="$TROOT/mut-untrack-order"
MSED="$(cat <<'SED'
/^cmd_untrack_pr()/,/^}/s/^  untrack_a_set || { g reset .*$/  : # MUTANT-OLD-ORDER/
/^cmd_untrack_pr()/,/^}/s/^  g add -- \.gitignore$/  untrack_a_set; g add -- .gitignore/
SED
)"
if build_mutant "$MUT" "$MSED" 'MUTANT-OLD-ORDER' && grep -qF '  untrack_a_set; g add -- .gitignore' "$MUT/migrate-branch-mode.sh"; then
  SCRIPT="$MUT/migrate-branch-mode.sh"
  if ledger_leg; then no "mutation control REFUTED: the old order (block before untrack) printed no WARNING ($LG_DETAIL)"
  elif grep -qF "apply: WARNING — readiness is 'partial" <<<"$LG_OUT"; then ok "mutation control: the old order prints the false partial WARNING for a configured head ($LG_DETAIL)"
  else no "mutation control: the old order failed for another reason ($LG_DETAIL)"; fi
  SCRIPT="$SUT"
else no "mutation control (untrack-pr order) did not build — counts as FAIL"; fi
# apply refusing AFTER the untrack: the step restores the index (the A set tracked again), returns to
# main, deletes the new branch, records FAIL and pushes nothing — the reorder must not strand a
# half-untracked index. setup-memory.sh is stubbed in a copied scripts dir: only `apply` refuses.
STUBSM="$TROOT/stub-apply-refuses"; mkdir -p "$STUBSM"; for f in "$HERE"/*; do [ -f "$f" ] && cp "$f" "$STUBSM/"; done
cp -R "$HERE/automate-helpers.d" "$STUBSM/"
cat > "$STUBSM/setup-memory.sh" <<STUB
#!/bin/bash
for a in "\$@"; do [ "\$a" = apply ] && { echo "apply: refused (test stub)"; exit 1; }; done
exec bash "$HERE/setup-memory.sh" "\$@"
STUB
mkworld history
( cd "$W/A" && mkdir -p .supervisor/postmortem && echo '{"repo":"owner/repo","pr":1,"rounds":0}' > "$LDG" \
  && git add -f "$LDG" && git commit -qm ledger && git push -q origin main ) >/dev/null 2>&1
to_protected A; mb A seed; O0="$(git --git-dir="$W/origin.git" for-each-ref --format='%(refname)' | env LC_ALL=C sort)"
SCRIPT="$STUBSM/migrate-branch-mode.sh"; mb A untrack-pr; SCRIPT="$SUT"
{ [ "$RC" -eq 1 ] && has "apply did not write the branch-mode block" && [ "$(st A untrack_pr)" = FAIL ] \
  && [ "$(git -C "$W/A" symbolic-ref --short HEAD)" = main ] && [ -z "$(porcelain A)" ] \
  && [ -n "$(git -C "$W/A" ls-files -- "$LDG")" ] && [ -z "$(git -C "$W/A" branch --list 'chore/loomwright-untrack-run-history-*')" ] \
  && [ "$O0" = "$(git --git-dir="$W/origin.git" for-each-ref --format='%(refname)' | env LC_ALL=C sort)" ]; }
check $? "apply refusing after the untrack: index restored (ledger tracked again), back on main, clean, branch deleted, FAIL recorded, nothing pushed (rc=$RC; porcelain: $(porcelain A | tr '\n' ' '))"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
