#!/usr/bin/env bash
# test-meta-sync.sh — self-tests for meta-sync.sh (3-way run-history sync on a metadata branch).
# Hermetic: every fixture is a bare `origin` plus clones inside one mktemp -d (never GitHub), HOME
# and git identity are sandboxed, the SUT runs as a subprocess with --root. Exit 0 = all pass.
# Run it under /bin/bash on macOS too: the scrub's token cases exist to catch a BSD-regex fail-OPEN.
#
# Covers (requirement Scope 8 + brief AC9):
#   1. missing branch -> pull non-zero `no_remote_branch`, status says so; init creates it; a
#      second init refuses and changes nothing
#   2. round trip: push from A, pull in B; code-branch `git status --porcelain` empty after both;
#      push leaves A's index/HEAD/working tree byte-identical; absent jobs/failed/ is not an error
#   3. ignored file: a *.log, a nested requirements/<q>/.supervisor/ tree, pending briefs and
#      session logs never reach the branch (`git ls-tree -r` holds only .md + the ledger)
#   4. stale copy: A changes X and pushes; B (old X untouched) changes Y and pushes -> A's X is still
#      on the branch; B's next pull gets it
#   5. local edit survives pull
#   6. post-push base (agreed-state meta-base): B pushes twice while A's newer X and new Z are on the
#      branch and NOT applied in B -> neither push reverts X or deletes Z; B's next pull gets both
#   7. deletion propagates and does not come back
#   8. rename: old gone, new present, branch and both clones
#   9. conflict -> non-zero, `meta_sync: conflict <path>`, nothing changed (branch tip, meta-base,
#      local files — including a pending take-R path)
#  10. results.jsonl both-append -> union with no duplicate line, R's order first
#  11. scrub positives: e-mail, home path, foreign slug, foreign ledger record and EACH of the five
#      token shapes -> exit 2, branch tip unchanged, every offending path named in one run
#  12. scrub with an EMPTY allowlist -> every forge slug is a hit (fail closed)
#  13. scrub negative: risk-/task- prose, 40-hex SHA, sha256: stamp, allowlisted URL -> exit 0
#  14. fresh-clone deletion (no meta-base): a stale deleted file is not re-added; the clone's pull
#      deletes it; its next push still does not re-add it; a stale OLDER copy of a live file is not
#      pushed; an edit away from every historical blob -> conflict; a grown ledger -> union
#  15. no meta-base + --paths-from: an out-of-list conflict still aborts (whole-set derivation),
#      branch and meta-base unchanged
#  16. fetch failure -> pull non-zero; status says unreachable (exit 0)
#  17. concurrent pushes: the loser is rejected, re-fetches, recomputes and lands — never forced
#      (origin has receive.denyNonFastForwards); a truly parallel pair both land
#  18. status vocabulary: synced / local_ahead / remote_ahead / conflict / never_synced, exit 0
#  19. static: the requirement's forbidden-forms grep over meta-sync.sh returns nothing
#  --- Mutation controls (sed-patched mutant copies in the temp dir; the shipped script has no
#      test seam) ---
#  20. (i) a mutant that drops the base comparison (any local difference is staged) MUST fail the
#      stale-copy assertion
#  21. (ii) a mutant whose managed-set predicate accepts every file under .supervisor/ (a directory
#      add) MUST fail the ignored-file assertion

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/meta-sync.sh"
SCRIPT="$SUT"
BR="loomwright-meta"

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
export LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="owner/repo,owner/repo-old"

W=""
# mkworld — a bare origin whose main carries a code commit (.supervisor/ ignored, as in a real repo).
mkworld() {
  W="$(mktemp -d "$TROOT/w.XXXXXX")"
  git init -q --bare "$W/origin.git"
  git --git-dir="$W/origin.git" symbolic-ref HEAD refs/heads/main
  git init -q "$W/seed"
  (
    cd "$W/seed" || exit 1
    git symbolic-ref HEAD refs/heads/main
    printf '.supervisor/\n' > .gitignore; echo code > app.txt
    git add .gitignore app.txt && git commit -qm code
    git remote add origin "$W/origin.git" && git push -q origin main
  )
}
clone() { git clone -q "$W/origin.git" "$W/$1" 2>/dev/null; }
# ms <clone> <args...> — run the SUT (or the current mutant) against a clone; sets OUT / RC.
ms() { local d="$1"; shift; OUT="$(bash "$SCRIPT" "$@" --root "$W/$d" 2>&1)"; RC=$?; }
put() { mkdir -p "$(dirname "$W/$1/$2")"; printf '%s\n' "$3" > "$W/$1/$2"; }
get() { cat "$W/$1/$2" 2>/dev/null; }
br_tip() { git --git-dir="$W/origin.git" rev-parse -q --verify "refs/heads/$BR" 2>/dev/null; }
br_show() { git --git-dir="$W/origin.git" show "refs/heads/$BR:$1" 2>/dev/null; }
br_has() { git --git-dir="$W/origin.git" cat-file -e "refs/heads/$BR:$1" 2>/dev/null; }
br_names() { git --git-dir="$W/origin.git" ls-tree -r --name-only "refs/heads/$BR" 2>/dev/null; }
base_of() { cat "$W/$1/.git/meta-base" 2>/dev/null; }
porcelain() { git -C "$W/$1" status --porcelain 2>/dev/null; }

RQ=".supervisor/requirements/q"

# synced_pair — world with branch initialised, A and B cloned and both synced on a seeded set.
synced_pair() {
  mkworld; clone A; clone B
  ms A init
  put A "$RQ/x.md" "x v1"; put A "$RQ/y.md" "y v1"; put A "$RQ/c.md" "c v1"
  put A "$RQ/d.md" "d v1"; put A "$RQ/r1.md" "rename me"; put A "$RQ/w.md" "w v1"
  put A ".supervisor/jobs/done/2026-01-01-brief.md" "brief"
  put A ".supervisor/automate/automate-2026-01-01-000000.md" "run"
  printf '%s\n' '{"repo":"owner/repo","n":1}' '{"repo":"owner/repo","n":2}' > "$W/A/.supervisor/postmortem.tmp"
  mkdir -p "$W/A/.supervisor/postmortem"; mv "$W/A/.supervisor/postmortem.tmp" "$W/A/.supervisor/postmortem/results.jsonl"
  ms A push
  ms B pull
}

# ---------------------------------------------------------------------------------------------
echo "== 1. missing branch / init =="
mkworld; clone A
ms A pull
{ [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'meta_sync: no_remote_branch' && printf '%s' "$OUT" | grep -qi 'local path'; }
check $? "pull without the branch exits non-zero with no_remote_branch naming a local-path origin (rc=$RC)"
ms A status
{ [ "$RC" -eq 0 ] && [ "$OUT" = "no_remote_branch" ]; }; check $? "status -> no_remote_branch, exit 0 (got '$OUT' rc=$RC)"
ms A init
{ [ "$RC" -eq 0 ] && [ -n "$(br_tip)" ] && [ -z "$(br_names)" ] && [ "$(git --git-dir="$W/origin.git" rev-list --parents -n1 "refs/heads/$BR" | awk '{print NF}')" = "1" ]; }
check $? "init creates an empty orphan commit on origin (rc=$RC)"
tip="$(br_tip)"; ms A init
{ [ "$RC" -ne 0 ] && [ "$(br_tip)" = "$tip" ]; }; check $? "second init refuses and leaves the branch unchanged (rc=$RC)"
ms A pull
{ [ "$RC" -eq 0 ] && [ -f "$W/A/.git/meta-base" ]; }; check $? "pull on an empty branch with no managed dirs succeeds and records meta-base (rc=$RC: $OUT)"

echo "== 2/3. round trip, code branch untouched, ignored files never published =="
# assert_ignored_clean — branch holds only .md + the ledger and none of the ignored fixtures.
assert_ignored_clean() {
  local extra
  extra="$(br_names | grep -vE '\.md$|(^|/)results\.jsonl$')"
  [ -z "$extra" ] || return 1
  br_names | grep -qE '/\.supervisor/|jobs/pending/|\.supervisor/logs/' && return 1
  return 0
}
roundtrip_world() {
  mkworld; clone A; clone B
  ms A init
  put A "$RQ/x.md" "x v1"; put A "$RQ/sub/deep.md" "deep"
  put A ".supervisor/jobs/done/2026-01-01-brief.md" "brief"
  put A ".supervisor/automate/automate-2026-01-01-000000.md" "run"
  mkdir -p "$W/A/.supervisor/postmortem"; printf '%s\n' '{"repo":"owner/repo","n":1}' > "$W/A/.supervisor/postmortem/results.jsonl"
  # ignored / unmanaged fixtures
  put A "$RQ/notes.log" "log line"
  put A "$RQ/.supervisor/logs/telemetry.log" "nested log"
  put A "$RQ/.supervisor/logs/nested.md" "nested md"
  put A ".supervisor/requirements/.supervisor/logs/notifications.log" "nested log 2"
  put A ".supervisor/jobs/pending/2026-01-02-pending.md" "pending"
  put A ".supervisor/logs/session.jsonl" "{}"
  put A ".supervisor/postmortem/other.json" "{}"
  put A ".supervisor/automate/automate-x.config-backup.json" "{}"
}
roundtrip_world
# make A's code branch dirty + staged so "untouched" is meaningful
echo staged > "$W/A/staged.txt"; git -C "$W/A" add staged.txt; echo dirty >> "$W/A/app.txt"
before_status="$(porcelain A)"; before_head="$(git -C "$W/A" rev-parse HEAD)"; before_index="$(git -C "$W/A" ls-files -s | cksum)"
ms A push
{ [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'meta_sync: pushed'; }; check $? "push exits 0 (rc=$RC: $OUT)"
{ [ "$(porcelain A)" = "$before_status" ] && [ "$(git -C "$W/A" rev-parse HEAD)" = "$before_head" ] && [ "$(git -C "$W/A" ls-files -s | cksum)" = "$before_index" ] && [ "$(get A app.txt)" = "$(printf 'code\ndirty')" ]; }
check $? "push leaves the code branch's status, HEAD, index and working tree byte-identical"
git -C "$W/A" reset -q --hard; rm -f "$W/A/staged.txt"
[ -z "$(porcelain A)" ]; check $? "code-branch git status --porcelain empty after push"
assert_ignored_clean; check $? "ignored file: branch holds only .md + the ledger; no *.log, nested .supervisor/, pending or logs"
[ "$(br_show "$RQ/sub/deep.md")" = "deep" ]; check $? "nested requirement folder file published"
ms B pull
{ [ "$RC" -eq 0 ] && [ -z "$(porcelain B)" ]; }; check $? "pull in B exits 0 and B's code-branch status is empty (rc=$RC: $OUT)"
diff -r "$W/A/.supervisor/requirements/q/x.md" "$W/B/.supervisor/requirements/q/x.md" >/dev/null \
  && [ "$(get B .supervisor/postmortem/results.jsonl)" = '{"repo":"owner/repo","n":1}' ] \
  && [ "$(get B .supervisor/jobs/done/2026-01-01-brief.md)" = "brief" ] \
  && [ ! -e "$W/B/$RQ/notes.log" ] && [ ! -e "$W/B/.supervisor/jobs/failed" ]
check $? "B received the managed files (and only those); absent jobs/failed/ was not an error"
ms A status; { [ "$RC" -eq 0 ] && [ "$OUT" = "synced $(br_tip)" ]; }; check $? "status after push -> synced <tip> (got '$OUT')"
ms B status; [ "$OUT" = "synced $(br_tip)" ]; check $? "status after pull -> synced <tip> (got '$OUT')"

echo "== 4. stale copy =="
STALE_DETAIL=""
# scenario_stale — returns 0 when A's newer X survives B's push and reaches B by pull.
scenario_stale() {
  synced_pair
  put A "$RQ/x.md" "x v2 from A"; ms A push || true
  put B "$RQ/y.md" "y v2 from B"; ms B push
  local branch_x branch_y
  branch_x="$(br_show "$RQ/x.md")"; branch_y="$(br_show "$RQ/y.md")"
  STALE_DETAIL="branch x.md after B's push = '$branch_x' (A pushed 'x v2 from A')"
  [ "$branch_x" = "x v2 from A" ] || return 1
  [ "$branch_y" = "y v2 from B" ] || return 1
  ms B pull
  [ "$(get B "$RQ/x.md")" = "x v2 from A" ] || return 1
  return 0
}
scenario_stale; check $? "A's X stays on the branch after B's push, and B's next pull gets it"

echo "== 5. local edit survives pull =="
synced_pair
put B "$RQ/y.md" "y local edit in B"
put A "$RQ/z.md" "z new from A"; ms A push
ms B pull
{ [ "$RC" -eq 0 ] && [ "$(get B "$RQ/y.md")" = "y local edit in B" ] && [ "$(get B "$RQ/z.md")" = "z new from A" ]; }
check $? "B's unpushed edit to Y survives pull; A's Z arrives (rc=$RC)"
ms B status; [ "$OUT" = "local_ahead 1" ]; check $? "status -> local_ahead 1 (got '$OUT')"

echo "== 6. post-push base (agreed-state meta-base) =="
synced_pair
put A "$RQ/x.md" "x v2 from A"; put A "$RQ/z.md" "z sibling new"; ms A push
put B "$RQ/y.md" "y v2"; ms B push; rc1=$RC
put B "$RQ/y.md" "y v3"; ms B push; rc2=$RC
{ [ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ] && [ "$(br_show "$RQ/x.md")" = "x v2 from A" ] && [ "$(br_show "$RQ/z.md")" = "z sibling new" ] && [ "$(br_show "$RQ/y.md")" = "y v3" ]; }
check $? "B's two pushes neither revert A's X nor delete Z (rc1=$rc1 rc2=$rc2)"
ms B status; [ "$OUT" = "remote_ahead" ]; check $? "status in B -> remote_ahead (got '$OUT')"
ms B pull
{ [ "$(get B "$RQ/x.md")" = "x v2 from A" ] && [ "$(get B "$RQ/z.md")" = "z sibling new" ] && [ "$(get B "$RQ/y.md")" = "y v3" ]; }
check $? "B's next pull writes A's X and Z and keeps its own Y"

echo "== 7. deletion =="
synced_pair
rm "$W/A/$RQ/d.md"; ms A push
! br_has "$RQ/d.md"; check $? "A's deletion removes the path from the branch"
ms B pull; [ ! -e "$W/B/$RQ/d.md" ]; check $? "B's pull deletes it locally"
put B "$RQ/y.md" "y from B"; ms B push; ms A pull
{ ! br_has "$RQ/d.md" && [ ! -e "$W/A/$RQ/d.md" ] && [ ! -e "$W/B/$RQ/d.md" ]; }
check $? "the deleted path does not come back after further pushes/pulls"

echo "== 8. rename =="
synced_pair
mv "$W/A/$RQ/r1.md" "$W/A/$RQ/r2.md"; ms A push; ms B pull
{ ! br_has "$RQ/r1.md" && br_has "$RQ/r2.md" && [ ! -e "$W/A/$RQ/r1.md" ] && [ -e "$W/A/$RQ/r2.md" ] && [ ! -e "$W/B/$RQ/r1.md" ] && [ "$(get B "$RQ/r2.md")" = "rename me" ]; }
check $? "old path gone and new path present on the branch and in both clones"

echo "== 9. conflict =="
synced_pair
put A "$RQ/c.md" "c from A"; put A "$RQ/w.md" "w v2 from A"; ms A push
put B "$RQ/c.md" "c from B"
tip="$(br_tip)"; base_before="$(base_of B)"
ms B push
{ [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q "meta_sync: conflict $RQ/c.md" && [ "$(br_tip)" = "$tip" ] && [ "$(base_of B)" = "$base_before" ]; }
check $? "push: both-edited c.md -> exit 1 'meta_sync: conflict', branch tip and meta-base unchanged (rc=$RC)"
ms B pull
{ [ "$RC" -eq 1 ] && [ "$(get B "$RQ/c.md")" = "c from B" ] && [ "$(get B "$RQ/w.md")" = "w v1" ] && [ "$(base_of B)" = "$base_before" ]; }
check $? "pull: conflict -> exit 1 and NOTHING written (pending take-R w.md untouched), meta-base unchanged (rc=$RC)"
ms B status; [ "$OUT" = "conflict 1" ]; check $? "status -> conflict 1 (got '$OUT')"

echo "== 10. results.jsonl both-append -> union =="
synced_pair
L="$(printf '%s' .supervisor/postmortem/results.jsonl)"
printf '%s\n' '{"repo":"owner/repo","n":3}' >> "$W/A/$L"; ms A push
printf '%s\n' '{"repo":"owner/repo","n":4}' '{"repo":"owner/repo","n":4}' >> "$W/B/$L"; ms B push
want="$(printf '%s\n' '{"repo":"owner/repo","n":1}' '{"repo":"owner/repo","n":2}' '{"repo":"owner/repo","n":3}' '{"repo":"owner/repo","n":4}')"
{ [ "$RC" -eq 0 ] && [ "$(br_show "$L")" = "$want" ]; }; check $? "branch ledger = R's lines then B's new lines, no duplicate (rc=$RC)"
ms A pull; ms B pull
{ [ "$(get A "$L")" = "$want" ] && [ "$(get B "$L")" = "$want" ] && [ -z "$(get B "$L" | sort | uniq -d)" ]; }
check $? "both clones converge on the union after pull"

echo "== 11. scrub positives (exit 2, branch unchanged, every path named) =="
synced_pair
put B "$RQ/s-email.md" "contact someone@example.org for access"
put B "$RQ/s-home.md" "see /Users/alice/project/notes"
put B "$RQ/s-home2.md" "see /home/bob/src"
put B "$RQ/s-slug.md" "upstream https://github.com/evilcorp/secret-repo/pull/3"
put B "$RQ/s-repofield.md" "repo: evilcorp/other"
put B "$RQ/s-ghp.md" "token ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij"
put B "$RQ/s-pat.md" "token github_pat_ABCDEFGHIJKLMNOPQRSTUV_wxyz"
put B "$RQ/s-sk.md" "key sk-ABCDEFGHIJKLMNOPQRSTUVWX"
put B "$RQ/s-slack.md" "hook xoxb-1234567890-abc"
put B "$RQ/s-aws.md" "id AKIAABCDEFGHIJKLMNOP end"
printf '%s\n' '{"repo":"evilcorp/private","n":9}' >> "$W/B/.supervisor/postmortem/results.jsonl"
tip="$(br_tip)"; base_before="$(base_of B)"
ms B push
{ [ "$RC" -eq 2 ] && [ "$(br_tip)" = "$tip" ] && [ "$(base_of B)" = "$base_before" ]; }
check $? "scrub hit -> exit 2, branch tip and meta-base unchanged (rc=$RC)"
for pr in "s-email.md: email" "s-home.md: home_path" "s-home2.md: home_path" "s-slug.md: forge_slug" \
          "s-repofield.md: forge_slug" "s-ghp.md: token_github" "s-pat.md: token_github_pat" \
          "s-sk.md: token_sk" "s-slack.md: token_slack" "s-aws.md: token_aws"; do
  printf '%s' "$OUT" | grep -qF "meta_sync: scrub $RQ/$pr"
  check $? "named in the same run: $pr"
done
printf '%s' "$OUT" | grep -qF "meta_sync: scrub .supervisor/postmortem/results.jsonl: ledger_repo"
check $? "named in the same run: foreign ledger record (ledger_repo)"

echo "== 12. scrub with an EMPTY allowlist =="
synced_pair
put B "$RQ/ok-slug.md" "see https://github.com/owner/repo/pull/1"
tip="$(br_tip)"
OUT="$(env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST bash "$SCRIPT" push --root "$W/B" 2>&1)"; RC=$?
{ [ "$RC" -eq 2 ] && printf '%s' "$OUT" | grep -qF "meta_sync: scrub $RQ/ok-slug.md: forge_slug" && [ "$(br_tip)" = "$tip" ]; }
check $? "empty allowlist (local-path origin, no config) -> every forge slug is a hit (rc=$RC)"

echo "== 13. scrub negative =="
put B "$RQ/ok-slug.md" "$(printf '%s\n' 'A risk-based plan for the task-ledger and sk-short.' \
  'Merged at 0123456789abcdef0123456789abcdef01234567 (sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef).' \
  'See https://github.com/owner/repo/pull/1 and https://github.com/apps/claude.')"
ms B push
{ [ "$RC" -eq 0 ] && br_has "$RQ/ok-slug.md"; }; check $? "clean prose with risk-/task-, a 40-hex SHA, a sha256: stamp and an allowlisted URL pushes (rc=$RC: $OUT)"

echo "== 14. fresh-clone deletion (no meta-base) =="
synced_pair
old_d="$(get A "$RQ/d.md")"; old_x="$(get A "$RQ/x.md")"
rm "$W/A/$RQ/d.md"; put A "$RQ/x.md" "x v2"; ms A push
clone C
put C "$RQ/d.md" "$old_d"; put C "$RQ/x.md" "$old_x"; put C "$RQ/newc.md" "brand new from C"
ms C status; [ "$OUT" = "never_synced" ]; check $? "status with no meta-base -> never_synced (got '$OUT')"
ms C push
{ [ "$RC" -eq 0 ] && ! br_has "$RQ/d.md" && [ "$(br_show "$RQ/x.md")" = "x v2" ] && [ "$(br_show "$RQ/newc.md")" = "brand new from C" ] && [ -f "$W/C/.git/meta-base" ]; }
check $? "fresh clone C: stale deleted d.md not re-added, stale older x.md not pushed, new file pushed, meta-base written (rc=$RC: $OUT)"
ms C pull
{ [ "$RC" -eq 0 ] && [ ! -e "$W/C/$RQ/d.md" ] && [ "$(get C "$RQ/x.md")" = "x v2" ]; }; check $? "C's pull deletes d.md and updates x.md (rc=$RC)"
put C "$RQ/y.md" "y from C"; ms C push
{ [ "$RC" -eq 0 ] && ! br_has "$RQ/d.md"; }; check $? "C's next push still does not re-add d.md"
clone D
put D "$RQ/d.md" "d edited away from every historical blob"
tip="$(br_tip)"; ms D push
{ [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q "meta_sync: conflict $RQ/d.md" && [ "$(br_tip)" = "$tip" ] && [ ! -e "$W/D/.git/meta-base" ]; }
check $? "fresh clone D with d.md edited away from history -> conflict, branch unchanged, no meta-base (rc=$RC)"
clone E
mkdir -p "$W/E/.supervisor/postmortem"
br_show .supervisor/postmortem/results.jsonl > "$W/E/.supervisor/postmortem/results.jsonl"
printf '%s\n' '{"repo":"owner/repo","n":77}' >> "$W/E/.supervisor/postmortem/results.jsonl"
ms E push
{ [ "$RC" -eq 0 ] && br_show .supervisor/postmortem/results.jsonl | grep -q '"n":77' && br_show .supervisor/postmortem/results.jsonl | grep -q '"n":1'; }
check $? "fresh clone E whose ledger gained lines -> union, not conflict (rc=$RC: $OUT)"

echo "== 15. no meta-base + --paths-from: out-of-list conflict still aborts =="
synced_pair
clone F
put F "$RQ/x.md" "x edited away from every historical blob"
put F "$RQ/ynew.md" "listed new file"
printf '%s\n' "$RQ/ynew.md" > "$W/list.txt"
tip="$(br_tip)"; ms F push --paths-from "$W/list.txt"
{ [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q "meta_sync: conflict $RQ/x.md" && [ "$(br_tip)" = "$tip" ] && [ ! -e "$W/F/.git/meta-base" ]; }
check $? "no base: unlisted X conflict aborts the --paths-from push; branch and meta-base unchanged (rc=$RC)"
echo "-- with a base, --paths-from restricts the push --"
put A "$RQ/x.md" "x listed"; put A "$RQ/y.md" "y unlisted"
printf '%s\n' "$RQ/x.md" "loomwright/not-managed.md" > "$W/list2.txt"
ms A push --paths-from "$W/list2.txt"
{ [ "$RC" -eq 0 ] && [ "$(br_show "$RQ/x.md")" = "x listed" ] && [ "$(br_show "$RQ/y.md")" = "y v1" ]; }
check $? "with a base, only listed managed paths are pushed (rc=$RC)"
ms A push
[ "$(br_show "$RQ/y.md")" = "y unlisted" ]; check $? "the unlisted path is pushed by a later unrestricted push (meta-base kept its old B)"

echo "== 16. fetch failure =="
synced_pair
git -C "$W/B" remote set-url origin "$W/does-not-exist.git"
ms B pull; { [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'fetch_failed'; }; check $? "pull with an unreachable origin exits non-zero (rc=$RC)"
ms B status; { [ "$RC" -eq 0 ] && [ "$OUT" = "unreachable" ]; }; check $? "status -> unreachable, exit 0 (got '$OUT')"

echo "== 17. concurrent pushes =="
synced_pair
git --git-dir="$W/origin.git" config receive.denyNonFastForwards true
MARK="$W/race.mark"; touch "$MARK"
put B "$RQ/y.md" "y from B (raced in)"
cat > "$W/origin.git/hooks/pre-receive" <<HOOK
#!/bin/sh
# First invocation only: land B's push while A's push is in flight, so A's ref update is rejected.
if [ -f "$MARK" ]; then
  rm -f "$MARK"
  ( unset GIT_DIR GIT_QUARANTINE_PATH GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PUSH_OPTION_COUNT
    bash "$SCRIPT" push --root "$W/B" ) < /dev/null > "$W/race-b.log" 2>&1
fi
cat > /dev/null
exit 0
HOOK
chmod +x "$W/origin.git/hooks/pre-receive"
put A "$RQ/x.md" "x from A (loser)"
ms A push
rm -f "$W/origin.git/hooks/pre-receive"
{ [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'rejected (attempt 1/5)' && grep -q 'meta_sync: pushed' "$W/race-b.log" \
  && [ "$(br_show "$RQ/x.md")" = "x from A (loser)" ] && [ "$(br_show "$RQ/y.md")" = "y from B (raced in)" ]; }
check $? "the loser was rejected once, re-fetched, recomputed and landed; both changes on the branch (rc=$RC)"
git --git-dir="$W/origin.git" rev-list --first-parent "refs/heads/$BR" | grep -q "$(git --git-dir="$W/origin.git" rev-parse "refs/heads/$BR~1")"
check $? "history is linear (fast-forward only; origin denies non-fast-forward)"
put A "$RQ/c.md" "c parallel A"; put B "$RQ/w.md" "w parallel B"
( bash "$SCRIPT" push --root "$W/A" > "$W/par-a.log" 2>&1; echo $? > "$W/par-a.rc" ) &
( bash "$SCRIPT" push --root "$W/B" > "$W/par-b.log" 2>&1; echo $? > "$W/par-b.rc" ) &
wait
{ [ "$(cat "$W/par-a.rc")" = "0" ] && [ "$(cat "$W/par-b.rc")" = "0" ] && [ "$(br_show "$RQ/c.md")" = "c parallel A" ] && [ "$(br_show "$RQ/w.md")" = "w parallel B" ]; }
check $? "a truly parallel pair of pushes both land (a=$(cat "$W/par-a.rc") b=$(cat "$W/par-b.rc"))"

echo "== 18. status vocabulary always exits 0 =="
synced_pair
ms A status; { [ "$RC" -eq 0 ] && [ "$OUT" = "synced $(br_tip)" ]; }; check $? "synced (got '$OUT')"
ms B push; ms A status; { [ "$RC" -eq 0 ] && [ "$OUT" = "synced $(br_tip)" ]; }; check $? "push with nothing to send -> still synced"
ms B push; printf '%s' "$OUT" | grep -q 'meta_sync: no_changes'; check $? "push with nothing to send -> meta_sync: no_changes, exit 0 (rc=$RC)"

echo "== 19. static: forbidden forms absent from meta-sync.sh =="
! grep -nE 'git (checkout|switch|merge)|push .*--force|add -f [^"$]*/( |$)' "$SUT"
check $? "no branch switching, no forced push, no directory add (requirement grep returns nothing)"

# ---------------------------------------------------------------------------------------------
# Mutation controls — sed-patched copies; the sibling setup-memory.sh is copied beside each.
# build_mutant <dir> <sed-expr> <must-appear> — 0 = mutant built and differs; 1 = inconclusive.
build_mutant() {
  mkdir -p "$1"; cp "$HERE/setup-memory.sh" "$1/"
  sed -e "$2" "$SUT" > "$1/meta-sync.sh" || return 1
  cmp -s "$SUT" "$1/meta-sync.sh" && return 1
  grep -qF "$3" "$1/meta-sync.sh" || return 1
  bash -n "$1/meta-sync.sh" || return 1
  return 0
}

echo "== 20. mutation control (i): drop the base comparison -> stale-copy assertion must turn red =="
MUT_I="$TROOT/mutant-i"
if build_mutant "$MUT_I" 's/else if (l == b) {/else if (0) {/; s/else if (r == b) {/else if (l != r) {/' 'else if (l != r) {'; then
  SCRIPT="$MUT_I/meta-sync.sh"
  if scenario_stale; then
    no "mutation control (i) REFUTED: the base-less mutant kept A's X — the stale-copy assertion is not load-bearing"
  else
    ok "mutation control (i): the base-less mutant turns the stale-copy assertion red — $STALE_DETAIL"
  fi
  SCRIPT="$SUT"
else
  no "mutation control (i): could not build the mutant (sed did not apply or bash -n failed) — control inconclusive"
fi

echo "== 21. mutation control (ii): directory add -> ignored-file assertion must turn red =="
MUT_II="$TROOT/mutant-ii"
if build_mutant "$MUT_II" 's/^is_managed() {$/is_managed() { return 0/' 'is_managed() { return 0'; then
  SCRIPT="$MUT_II/meta-sync.sh"
  roundtrip_world
  ms A push
  if [ "$RC" -eq 0 ] && assert_ignored_clean; then
    no "mutation control (ii) REFUTED: the directory-add mutant published nothing extra — the ignored-file assertion is not load-bearing"
  elif [ "$RC" -ne 0 ]; then
    no "mutation control (ii): the mutant push itself failed (rc=$RC: $OUT) — control inconclusive"
  else
    ok "mutation control (ii): the directory-add mutant turns the ignored-file assertion red — leaked: $(br_names | grep -vE '\.md$|(^|/)results\.jsonl$' | tr '\n' ' ')$(br_names | grep -E '/\.supervisor/|jobs/pending/' | tr '\n' ' ')"
  fi
  SCRIPT="$SUT"
else
  no "mutation control (ii): could not build the mutant (sed did not apply or bash -n failed) — control inconclusive"
fi

echo
echo "test-meta-sync: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
