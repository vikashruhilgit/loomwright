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
#  13. scrub negative: risk-/task- prose, 40-hex SHA, sha256: stamp, allowlisted URL, a reserved-word
#      URL and a github.com/.../pull placeholder -> exit 0
#  13b. scrub case / quoting variants: a mixed- and upper-case forge host, a single-quoted and a
#      capitalised repo key, a lowercase /users/ home path -> each named, exit 2; the allowlisted
#      slug in mixed case / single quotes still passes
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
#  22. same-root concurrency: a `status` on the SAME root, injected (git shim) between a push's
#      read-tree and its first update-index, must not shrink the pushed tree; an index lost mid-push
#      trips tree_guard (exit 1, branch and meta-base unchanged)
#  23. per-root lock: a live holder -> exit 1 `locked`, nothing changed, lock not stolen; a dead
#      holder is reclaimed; the lock and no fixed-name scratch remain after success / conflict /
#      scrub exits; a same-root push + pull pair both succeed
#  24. untrusted tree paths: a mktree'd `.supervisor/requirements/../../README.md` entry on the branch
#      -> pull writes nothing outside .supervisor/ (tracked README.md intact, legit file arrives), push
#      fails closed; the same entry deleted again (history-derived deletion leg, fresh clone) is
#      not a managed path: no conflict, nothing outside .supervisor/ touched (the deletion branch
#      itself needs the path in the find-enumerated local list, so a '..' path never reaches it)
#  25. a clone's UNPUSHED ledger lines survive a pull of a sibling's push (pull hashes without -w,
#      so the union reads L from the working file); status then says local_ahead; a fresh no-base
#      clone's first pull keeps its own pre-existing ledger lines
#  26. symlinks where run history lives fail closed: a symlinked requirements folder -> pull and
#      push exit 1 naming it, nothing written outside .supervisor/, nothing deleted from the
#      branch, meta-base unchanged; a symlinked managed file and a symlinked .supervisor likewise;
#      an unmanaged symlink under .supervisor/logs and a --root reached through a symlink still sync
#  27. stale-lock reclaim under forced interleaving (dead holder + 3 contenders; PATH shims make
#      the stale reader act only after another waiter reclaimed and entered): never two holders
#  28. a DIRECTORY at a managed path the branch holds a file at: pull exits 1 `not_a_file`, writes
#      nothing (nothing renamed into the directory), meta-base unchanged; push exits 1 and never
#      deletes the branch file (both the never-pulled and the replaced-after-sync shapes)
#  29. enumeration scope: an unreadable (chmod 000) folder under .supervisor/logs and
#      .supervisor/worktrees, and a folder tree churning under .supervisor/worktrees, never block a
#      pull or push; an unreadable folder INSIDE a managed root, or an unsearchable folder on the
#      way to one, still refuses (nothing changed)
#  30. a newline in a name fails closed: a mktree'd branch entry whose name embeds a newline (and
#      would parse as a fabricated managed record) -> pull and push exit 1 `newline_in_path`,
#      nothing written, branch and meta-base unchanged; with the entry gone the same clone syncs
#      again; a fresh clone refuses while it is in R's history; a LOCAL newline name under a
#      managed root likewise refuses, one under unmanaged .supervisor/logs does not
#  31. --paths-from on pull / status / init -> usage error exit 1, nothing changed
#  32. project deny patterns: a matching ERE -> exit 2 `deny_pattern:<line>`; an invalid ERE ->
#      exit 2 `deny_pattern_invalid:<line>`; the deny file absent -> the push lands
#  33. scan_error(<rule>) (failing grep), ledger_unverifiable(jq missing) (a hermetic no-jq PATH)
#      and unreadable (failing cat-file) -> exit 2, branch and meta-base unchanged
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
# leg 29 chmod-000s folders; restore perms first so the temp dir can always be removed
trap 'chmod -R u+rwx "$TROOT" 2>/dev/null; rm -rf "$TROOT"' EXIT
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
{ [ "$RC" -ne 0 ] && grep -q 'meta_sync: no_remote_branch' < <(printf '%s' "$OUT") && grep -qi 'local path' < <(printf '%s' "$OUT"); }
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
  grep -qE '/\.supervisor/|jobs/pending/|\.supervisor/logs/' < <(br_names) && return 1
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
{ [ "$RC" -eq 0 ] && grep -q 'meta_sync: pushed' < <(printf '%s' "$OUT"); }; check $? "push exits 0 (rc=$RC: $OUT)"
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
{ [ "$RC" -eq 1 ] && grep -q "meta_sync: conflict $RQ/c.md" < <(printf '%s' "$OUT") && [ "$(br_tip)" = "$tip" ] && [ "$(base_of B)" = "$base_before" ]; }
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
# 12 = ten prose files + the foreign ledger record, which hits BOTH ledger_repo and forge_slug ("repo": field)
{ [ "$(printf '%s\n' "$OUT" | grep -c '^meta_sync: scrub ')" -eq 12 ] && grep -q '^meta_sync: aborted' < <(printf '%s\n' "$OUT"); }
check $? "exactly one 'meta_sync: scrub <path>: <rule>' line per hit (12); the summary line starts 'meta_sync: aborted' (got: $(printf '%s\n' "$OUT" | grep '^meta_sync: scrub ' | tr '\n' '|'))"
for pr in "s-email.md: email" "s-home.md: home_path" "s-home2.md: home_path" "s-slug.md: forge_slug" \
          "s-repofield.md: forge_slug" "s-ghp.md: token_github" "s-pat.md: token_github_pat" \
          "s-sk.md: token_sk" "s-slack.md: token_slack" "s-aws.md: token_aws"; do
  grep -qF "meta_sync: scrub $RQ/$pr" < <(printf '%s' "$OUT")
  check $? "named in the same run: $pr"
done
grep -qF "meta_sync: scrub .supervisor/postmortem/results.jsonl: ledger_repo" < <(printf '%s' "$OUT")
check $? "named in the same run: foreign ledger record (ledger_repo)"

echo "== 12. scrub with an EMPTY allowlist =="
synced_pair
put B "$RQ/ok-slug.md" "see https://github.com/owner/repo/pull/1"
tip="$(br_tip)"
OUT="$(env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST bash "$SCRIPT" push --root "$W/B" 2>&1)"; RC=$?
{ [ "$RC" -eq 2 ] && grep -qF "meta_sync: scrub $RQ/ok-slug.md: forge_slug" < <(printf '%s' "$OUT") && [ "$(br_tip)" = "$tip" ]; }
check $? "empty allowlist (local-path origin, no config) -> every forge slug is a hit (rc=$RC)"

echo "== 13. scrub negative =="
put B "$RQ/ok-slug.md" "$(printf '%s\n' 'A risk-based plan for the task-ledger and sk-short.' \
  'Merged at 0123456789abcdef0123456789abcdef01234567 (sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef).' \
  'See https://github.com/owner/repo/pull/1, https://github.com/apps/claude and github.com/.../pull.')"
ms B push
{ [ "$RC" -eq 0 ] && br_has "$RQ/ok-slug.md"; }; check $? "clean prose with risk-/task-, a 40-hex SHA, a sha256: stamp, an allowlisted URL, a reserved-word URL and a .../pull placeholder push (rc=$RC: $OUT)"

echo "== 13b. scrub case / quoting variants =="
synced_pair
put B "$RQ/v-host-mixed.md" "upstream https://GitHub.com/evilcorp/secret-repo/pull/3"
put B "$RQ/v-host-upper.md" "see HTTPS://GITHUB.COM/evilcorp/x for details"
put B "$RQ/v-repo-sq.md" "repo: 'evilcorp/x'"
put B "$RQ/v-repo-cap.md" '{"Repo": "evilcorp/x"}'
put B "$RQ/v-repo-sqkey.md" "{'REPO': 'evilcorp/y'}"
put B "$RQ/v-home-lc.md" "see /users/alice/project"
tip="$(br_tip)"; base_before="$(base_of B)"
ms B push
{ [ "$RC" -eq 2 ] && [ "$(br_tip)" = "$tip" ] && [ "$(base_of B)" = "$base_before" ]; }
check $? "case / quoting variants -> exit 2, branch tip and meta-base unchanged (rc=$RC)"
for pr in "v-host-mixed.md: forge_slug" "v-host-upper.md: forge_slug" "v-repo-sq.md: forge_slug" \
          "v-repo-cap.md: forge_slug" "v-repo-sqkey.md: forge_slug" "v-home-lc.md: home_path"; do
  grep -qF "meta_sync: scrub $RQ/$pr" < <(printf '%s' "$OUT")
  check $? "named in the same run: $pr"
done
rm -f "$W/B/$RQ"/v-*.md
put B "$RQ/v-ok.md" "$(printf '%s\n' 'See https://GitHub.com/Owner/Repo/pull/1' "repo: 'owner/repo-old'" '{"Repo": "Owner/Repo"}')"
ms B push
{ [ "$RC" -eq 0 ] && br_has "$RQ/v-ok.md"; }
check $? "allowlisted slugs in mixed case / single quotes / a capitalised key still push (rc=$RC: $OUT)"

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
{ [ "$RC" -eq 1 ] && grep -q "meta_sync: conflict $RQ/d.md" < <(printf '%s' "$OUT") && [ "$(br_tip)" = "$tip" ] && [ ! -e "$W/D/.git/meta-base" ]; }
check $? "fresh clone D with d.md edited away from history -> conflict, branch unchanged, no meta-base (rc=$RC)"
clone E
mkdir -p "$W/E/.supervisor/postmortem"
br_show .supervisor/postmortem/results.jsonl > "$W/E/.supervisor/postmortem/results.jsonl"
printf '%s\n' '{"repo":"owner/repo","n":77}' >> "$W/E/.supervisor/postmortem/results.jsonl"
ms E push
{ [ "$RC" -eq 0 ] && grep -q '"n":77' < <(br_show .supervisor/postmortem/results.jsonl) && grep -q '"n":1' < <(br_show .supervisor/postmortem/results.jsonl); }
check $? "fresh clone E whose ledger gained lines -> union, not conflict (rc=$RC: $OUT)"

echo "== 15. no meta-base + --paths-from: out-of-list conflict still aborts =="
synced_pair
clone F
put F "$RQ/x.md" "x edited away from every historical blob"
put F "$RQ/ynew.md" "listed new file"
printf '%s\n' "$RQ/ynew.md" > "$W/list.txt"
tip="$(br_tip)"; ms F push --paths-from "$W/list.txt"
{ [ "$RC" -ne 0 ] && grep -q "meta_sync: conflict $RQ/x.md" < <(printf '%s' "$OUT") && [ "$(br_tip)" = "$tip" ] && [ ! -e "$W/F/.git/meta-base" ]; }
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
ms B pull; { [ "$RC" -ne 0 ] && grep -q 'fetch_failed' < <(printf '%s' "$OUT"); }; check $? "pull with an unreachable origin exits non-zero (rc=$RC)"
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
{ [ "$RC" -eq 0 ] && grep -q 'rejected (attempt 1/5)' < <(printf '%s' "$OUT") && grep -q 'meta_sync: pushed' "$W/race-b.log" \
  && [ "$(br_show "$RQ/x.md")" = "x from A (loser)" ] && [ "$(br_show "$RQ/y.md")" = "y from B (raced in)" ]; }
check $? "the loser was rejected once, re-fetched, recomputed and landed; both changes on the branch (rc=$RC)"
{ [ -z "$(git --git-dir="$W/origin.git" rev-list --merges "refs/heads/$BR")" ] && [ "$(git --git-dir="$W/origin.git" rev-list --first-parent --count "refs/heads/$BR")" = "$(git --git-dir="$W/origin.git" rev-list --count "refs/heads/$BR")" ]; }
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
ms B push; grep -q 'meta_sync: no_changes' < <(printf '%s' "$OUT"); check $? "push with nothing to send -> meta_sync: no_changes, exit 0 (rc=$RC)"

echo "== 19. static: forbidden forms absent from meta-sync.sh =="
! grep -nE 'git (checkout|switch|merge)|push .*--force|add -f [^"$]*/( |$)' "$SUT"
check $? "no branch switching, no forced push, no directory add (requirement grep returns nothing)"

echo "== 22. same-root concurrency: a status racing a push =="
REAL_GIT="$(command -v git)"
# mkshim <dir> <mark> <action-sh> — a `git` shim that runs <action-sh> once, at the FIRST
# `git -C <root> update-index --add ...` (i.e. after the push's read-tree, before its first add).
mkshim() {
  mkdir -p "$1"
  cat > "$1/git" <<SHIM
#!/bin/sh
if [ -f "$2" ] && [ "\$3" = "update-index" ] && [ "\$4" = "--add" ]; then
  rm -f "$2"
  $3
fi
exec "$REAL_GIT" "\$@"
SHIM
  chmod +x "$1/git"
}
synced_pair
names_before="$(br_names | env LC_ALL=C sort)"
touch "$W/race1.mark"
mkshim "$W/shim1" "$W/race1.mark" "env -u GIT_INDEX_FILE PATH='$PATH' bash '$SUT' status --root '$W/A' > '$W/race-status.log' 2>&1"
put A "$RQ/x.md" "x raced"
OUT="$(PATH="$W/shim1:$PATH" bash "$SCRIPT" push --root "$W/A" 2>&1)"; RC=$?
{ [ ! -e "$W/race1.mark" ] && [ -s "$W/race-status.log" ]; }
check $? "the injected same-root status really ran mid-push (log: $(cat "$W/race-status.log" 2>/dev/null))"
{ [ "$RC" -eq 0 ] && [ "$(br_names | env LC_ALL=C sort)" = "$names_before" ] && [ "$(br_show "$RQ/x.md")" = "x raced" ]; }
check $? "push still publishes the full tree with only x.md changed (rc=$RC: $OUT; branch now: $(br_names | tr '\n' ' '))"
ms B pull
{ [ "$RC" -eq 0 ] && [ "$(get B "$RQ/y.md")" = "y v1" ] && [ "$(get B "$RQ/x.md")" = "x raced" ]; }
check $? "the sibling's pull writes x.md and deletes nothing (rc=$RC: $OUT)"
ms A status; [ "$OUT" = "synced $(br_tip)" ]; check $? "the pusher's own status -> synced (got '$OUT')"
echo "-- an index lost mid-push trips tree_guard --"
synced_pair
tip="$(br_tip)"; base_before="$(base_of A)"
touch "$W/race2.mark"
mkshim "$W/shim2" "$W/race2.mark" 'rm -f "$GIT_INDEX_FILE"'
put A "$RQ/x.md" "x after index loss"
OUT="$(PATH="$W/shim2:$PATH" bash "$SCRIPT" push --root "$W/A" 2>&1)"; RC=$?
{ [ ! -e "$W/race2.mark" ] && [ "$RC" -eq 1 ] && grep -q 'tree_guard' < <(printf '%s' "$OUT") && [ "$(br_tip)" = "$tip" ] && [ "$(base_of A)" = "$base_before" ]; }
check $? "tree_guard: the new tree would delete unplanned paths -> exit 1, branch tip and meta-base unchanged (rc=$RC: $OUT)"

echo "== 23. per-root lock =="
synced_pair
LOCK="$W/A/.git/meta-sync.lock"
sleep 60 & live_pid=$!
mkdir "$LOCK"; printf '%s\n' "$live_pid" > "$LOCK/pid"
put A "$RQ/x.md" "x while locked"
tip="$(br_tip)"; base_before="$(base_of A)"
OUT="$(META_SYNC_LOCK_WAIT_SECS=1 bash "$SCRIPT" push --root "$W/A" 2>&1)"; RC=$?
{ [ "$RC" -eq 1 ] && grep -q 'meta_sync: locked' < <(printf '%s' "$OUT") && [ "$(br_tip)" = "$tip" ] && [ "$(base_of A)" = "$base_before" ] && [ "$(cat "$LOCK/pid" 2>/dev/null)" = "$live_pid" ]; }
check $? "a live holder -> push exits 1 'locked', nothing changed, the holder's lock is not stolen (rc=$RC: $OUT)"
OUT="$(META_SYNC_LOCK_WAIT_SECS=1 bash "$SCRIPT" pull --root "$W/A" 2>&1)"; RC=$?
{ [ "$RC" -eq 1 ] && grep -q 'meta_sync: locked' < <(printf '%s' "$OUT"); }; check $? "a live holder -> pull exits 1 'locked' (rc=$RC)"
ms A status; { [ "$RC" -eq 0 ] && [ "$OUT" = "local_ahead 1" ]; }; check $? "status takes no lock (got '$OUT')"
kill "$live_pid" 2>/dev/null; wait "$live_pid" 2>/dev/null
( exit 0 ) & dead_pid=$!; wait "$dead_pid" 2>/dev/null
printf '%s\n' "$dead_pid" > "$LOCK/pid"
ms A push
{ [ "$RC" -eq 0 ] && grep -q 'reclaimed a stale lock' < <(printf '%s' "$OUT") && [ "$(br_show "$RQ/x.md")" = "x while locked" ] && [ ! -e "$LOCK" ]; }
check $? "a dead holder's lock is reclaimed, the push lands and the lock is released (rc=$RC: $OUT)"
no_leftovers() { [ ! -e "$W/$1/.git/meta-sync.lock" ] && [ ! -e "$W/$1/.git/meta-index" ] && [ ! -e "$W/$1/.git/meta-base-index" ] && [ -z "$(ls "$W/$1/.git" | grep -E '^meta-(base\.tmp|sync\.lock\.stale)')" ]; }
put B "$RQ/c.md" "c from B (conflict)"; put A "$RQ/c.md" "c from A"; ms A push; ms B push
{ [ "$RC" -eq 1 ] && no_leftovers B; }; check $? "after a conflict exit: no lock and no fixed-name scratch left in the gitdir (rc=$RC)"
put B "$RQ/c.md" "c v1"; ms B pull; put B "$RQ/s-mail.md" "mail someone@example.org"; ms B push
{ [ "$RC" -eq 2 ] && no_leftovers B; }; check $? "after a scrub exit: no lock and no fixed-name scratch left (rc=$RC)"
rm -f "$W/B/$RQ/s-mail.md"
put A "$RQ/w.md" "w same-root parallel"; put B "$RQ/z.md" "z for the same-root pull"; ms B push
( bash "$SUT" push --root "$W/A" > "$W/sr-push.log" 2>&1; echo $? > "$W/sr-push.rc" ) &
( bash "$SUT" pull --root "$W/A" > "$W/sr-pull.log" 2>&1; echo $? > "$W/sr-pull.rc" ) &
wait
{ [ "$(cat "$W/sr-push.rc")" = "0" ] && [ "$(cat "$W/sr-pull.rc")" = "0" ] && [ "$(br_show "$RQ/w.md")" = "w same-root parallel" ] && [ "$(get A "$RQ/z.md")" = "z for the same-root pull" ] && br_has "$RQ/y.md" && no_leftovers A; }
check $? "a same-root push + pull pair both succeed, serialised (push=$(cat "$W/sr-push.rc") pull=$(cat "$W/sr-pull.rc"))"
ms A pull; ms A status; [ "$OUT" = "synced $(br_tip)" ]; check $? "and the root converges to synced (got '$OUT')"

echo "== 24. untrusted tree paths (mktree '..' entries) =="
synced_pair
OG="$W/origin.git"
# the climb targets a TRACKED .md at the root (a .md, so the pre-fix requirements glob matched it)
printf 'readme\n' > "$W/B/README.md"; git -C "$W/B" add README.md; git -C "$W/B" commit -qm readme
# req1 = requirements + a '..'/'..'/README.md climb + legit.md (commit c1); req2 = without the climb (c2).
og() { git --git-dir="$OG" "$@"; }
tip0="$(br_tip)"
evil="$(printf 'pwned\n' | og hash-object -w --stdin)"
legit="$(printf 'legit\n' | og hash-object -w --stdin)"
t_app="$(printf '100644 blob %s\tREADME.md\n' "$evil" | og mktree)"
t_up="$(printf '040000 tree %s\t..\n' "$t_app" | og mktree)"
req0="$(og rev-parse "$tip0:.supervisor/requirements")"
req1="$({ og ls-tree "$req0"; printf '040000 tree %s\t..\n' "$t_up"; printf '100644 blob %s\tlegit.md\n' "$legit"; } | og mktree)"
req2="$({ og ls-tree "$req0"; printf '100644 blob %s\tlegit.md\n' "$legit"; } | og mktree)"
# swap_req <requirements-tree> — prints a root tree equal to tip0's with requirements replaced.
swap_req() {
  local sup1
  sup1="$({ og ls-tree "$tip0:.supervisor" | awk -F'\t' '$2 != "requirements"'; printf '040000 tree %s\trequirements\n' "$1"; } | og mktree)"
  { og ls-tree "$tip0^{tree}" | awk -F'\t' '$2 != ".supervisor"'; printf '040000 tree %s\t.supervisor\n' "$sup1"; } | og mktree
}
c1="$(printf 'hostile\n' | og commit-tree "$(swap_req "$req1")" -p "$tip0")"
og update-ref "refs/heads/$BR" "$c1"
grep -qF '.supervisor/requirements/../../README.md' < <(og ls-tree -r --name-only "$c1")
check $? "fixture: the branch tip really carries .supervisor/requirements/../../README.md"
ms B pull
{ [ "$RC" -eq 0 ] && [ "$(get B README.md)" = "readme" ] && [ -z "$(porcelain B)" ] && [ "$(get B "$RQ/../legit.md")" = "legit" ] && [ -z "$(ls "$W/B" | grep 'meta-sync')" ]; }
check $? "pull writes nothing outside .supervisor/: tracked README.md intact, the legit file arrives (rc=$RC: $OUT; README.md='$(get B README.md)')"
put B "$RQ/y.md" "y after hostile tip"; tip="$(br_tip)"; ms B push
{ [ "$RC" -ne 0 ] && [ "$(br_tip)" = "$tip" ] && [ "$(get B README.md)" = "readme" ]; }
check $? "push over a hostile tip fails closed, branch unchanged (rc=$RC)"
c2="$(printf 'cleanup\n' | og commit-tree "$(swap_req "$req2")" -p "$c1")"
og update-ref "refs/heads/$BR" "$c2"
ms B pull
{ [ "$RC" -eq 0 ] && [ "$(get B README.md)" = "readme" ] && [ -z "$(porcelain B)" ]; }
check $? "the '..' entry deleted on the branch: B's pull deletes nothing outside .supervisor/ (rc=$RC: $OUT)"
clone G
printf 'readme\n' > "$W/G/README.md"; git -C "$W/G" add README.md; git -C "$W/G" commit -qm readme
ms G pull
{ [ "$RC" -eq 0 ] && [ "$(get G README.md)" = "readme" ] && [ -z "$(porcelain G)" ] && ! grep -q 'conflict' < <(printf '%s' "$OUT"); }
check $? "fresh clone G (history-derived deletion leg): the '..' path in R's history is not managed — no conflict, README.md intact (rc=$RC: $OUT)"

echo "== 25. pull keeps a clone's UNPUSHED ledger lines (union reads L from the working file) =="
synced_pair
LG=".supervisor/postmortem/results.jsonl"
n1='{"repo":"owner/repo","n":1}'; n2='{"repo":"owner/repo","n":2}'
printf '%s\n' '{"repo":"owner/repo","n":5}' >> "$W/B/$LG"
printf '%s\n' '{"repo":"owner/repo","n":3}' >> "$W/A/$LG"; ms A push
ms B pull
want="$(printf '%s\n' "$n1" "$n2" '{"repo":"owner/repo","n":3}' '{"repo":"owner/repo","n":5}')"
{ [ "$RC" -eq 0 ] && [ "$(get B "$LG")" = "$want" ]; }
check $? "B's unpushed n:5 survives the pull of A's n:3 — ledger = R's lines then B's (rc=$RC: $OUT; ledger: $(get B "$LG" | tr '\n' ' '))"
: > "$W/B/.supervisor/postmortem/mode-ref"
[ "$(ls -l "$W/B/$LG" | cut -c1-10)" = "$(ls -l "$W/B/.supervisor/postmortem/mode-ref" | cut -c1-10)" ]
check $? "a pulled file gets the mode a plain redirect would give it (umask), not mktemp's 0600 ($(ls -l "$W/B/$LG" | cut -c1-10))"
rm -f "$W/B/.supervisor/postmortem/mode-ref"
ms B status; [ "$OUT" = "local_ahead 1" ]; check $? "after that pull status says local_ahead 1, never synced (got '$OUT')"
ms B push; { [ "$RC" -eq 0 ] && [ "$(br_show "$LG")" = "$want" ]; }; check $? "B's next push publishes the union (rc=$RC)"
clone H
mkdir -p "$W/H/.supervisor/postmortem"
printf '%s\n' '{"repo":"owner/repo","n":88}' "$n1" > "$W/H/$LG"
ms H pull
want_h="$(br_show "$LG"; printf '%s\n' '{"repo":"owner/repo","n":88}')"
{ [ "$RC" -eq 0 ] && [ "$(get H "$LG")" = "$want_h" ]; }
check $? "fresh no-base clone H: its first pull keeps its own pre-existing n:88 line (rc=$RC: $OUT; ledger: $(get H "$LG" | tr '\n' ' '))"

echo "== 26. symlinks where run history lives fail closed =="
synced_pair
OUTSIDE="$W/outside/reqdir"; mkdir -p "$OUTSIDE"
ln -s "$OUTSIDE" "$W/B/.supervisor/requirements/sub"
put A ".supervisor/requirements/sub/keep.md" "keep"; ms A push
tip="$(br_tip)"; base_before="$(base_of B)"
ms B pull
{ [ "$RC" -eq 1 ] && grep -q 'meta_sync: symlink .supervisor/requirements/sub' < <(printf '%s' "$OUT") && [ -z "$(ls -A "$OUTSIDE")" ] && [ "$(base_of B)" = "$base_before" ] && [ "$(get B "$RQ/x.md")" = "x v1" ]; }
check $? "pull with a symlinked requirements folder -> exit 1 naming it, nothing written outside .supervisor/, meta-base unchanged (rc=$RC: $OUT; outside: $(ls -A "$OUTSIDE" | tr '\n' ' '))"
put B "$RQ/y.md" "y v2 from B"; ms B push
{ [ "$RC" -eq 1 ] && [ "$(br_tip)" = "$tip" ] && [ "$(br_show .supervisor/requirements/sub/keep.md)" = "keep" ] && [ "$(base_of B)" = "$base_before" ]; }
check $? "push with the symlinked folder -> exit 1, branch unchanged (sub/keep.md NOT deleted), meta-base unchanged (rc=$RC: $OUT)"
rm -f "$W/B/.supervisor/requirements/sub"
ln -s "$OUTSIDE/victim.md" "$W/B/$RQ/link.md"
ms B push
{ [ "$RC" -eq 1 ] && grep -q "meta_sync: symlink $RQ/link.md" < <(printf '%s' "$OUT") && [ "$(br_tip)" = "$tip" ]; }
check $? "a symlinked managed FILE -> push exits 1 naming it, branch unchanged (rc=$RC)"
rm -f "$W/B/$RQ/link.md"
mv "$W/B/.supervisor" "$W/B-sup"; ln -s "$W/B-sup" "$W/B/.supervisor"
ms B push
{ [ "$RC" -eq 1 ] && [ "$(br_tip)" = "$tip" ]; }; check $? ".supervisor itself a symlink -> push exits 1, branch unchanged (rc=$RC)"
echo "-- no false refusal: unmanaged symlinks and a symlinked checkout path still sync --"
synced_pair
OUTSIDE="$W/outside/logdir"; mkdir -p "$OUTSIDE"
put A ".supervisor/requirements/sub/keep.md" "keep"; ms A push
mkdir -p "$W/B/.supervisor/logs"; ln -s "$OUTSIDE" "$W/B/.supervisor/logs/elsewhere"
ln -s "$W/B" "$W/B-link"
OUT="$(bash "$SCRIPT" pull --root "$W/B-link" 2>&1)"; RC=$?
{ [ "$RC" -eq 0 ] && [ "$(get B .supervisor/requirements/sub/keep.md)" = "keep" ] && [ -z "$(ls -A "$OUTSIDE")" ]; }
check $? "an unmanaged symlink under .supervisor/logs and a --root reached through a symlink still pull (rc=$RC: $OUT)"
put B "$RQ/y.md" "y via link"
OUT="$(bash "$SCRIPT" push --root "$W/B-link" 2>&1)"; RC=$?
{ [ "$RC" -eq 0 ] && [ "$(br_show "$RQ/y.md")" = "y via link" ]; }; check $? "... and push (rc=$RC: $OUT)"

echo "== 27. stale-lock reclaim under forced interleaving: never two holders =="
REAL_CAT="$(command -v cat)"; REAL_MV="$(command -v mv)"
# lock_race <script> — a dead holder plus three contenders, sequenced by condition (not by sleeps):
# P2 reads the dead pid, and its cat shim then blocks until P1 has reclaimed the lock and ENTERed;
# only then does P2 act on its stale read (the reviewer's interleaving). Any mv of the lock by P2
# then blocks until P3 has ENTERed, so a moved-aside live lock is visible to P3. P1 holds 6s.
# ENTER/LEAVE is logged at the first git call inside the lock (the remote probe). Sets LR_MAX (most
# simultaneous holders), LR_ENTERS, LR_RCS and LR_LOG.
lock_race() {
  local s="$1" d i
  synced_pair
  d="$W/lockrace"; mkdir -p "$d/common" "$d/p2"
  : > "$d/holders.log"
  cat > "$d/common/git" <<SHIM
#!/bin/sh
if [ "\$3" = "ls-remote" ]; then
  echo "ENTER \$MS_WHO" >> "$d/holders.log"; sleep "\$MS_HOLD"; echo "LEAVE \$MS_WHO" >> "$d/holders.log"
fi
exec "$REAL_GIT" "\$@"
SHIM
  cat > "$d/p2/cat" <<SHIM
#!/bin/sh
case "\$1" in
  */meta-sync.lock/pid)
    "$REAL_CAT" "\$@"; rc=\$?; : > "$d/p2.read"; i=0
    while ! grep -qx 'ENTER P1' "$d/holders.log" && [ \$i -lt 300 ]; do sleep 0.1; i=\$((i+1)); done
    exit \$rc ;;
esac
exec "$REAL_CAT" "\$@"
SHIM
  cat > "$d/p2/mv" <<SHIM
#!/bin/sh
case "\$1" in
  */meta-sync.lock)
    "$REAL_MV" "\$@"; rc=\$?; i=0
    while ! grep -qx 'ENTER P3' "$d/holders.log" && [ \$i -lt 100 ]; do sleep 0.1; i=\$((i+1)); done
    exit \$rc ;;
esac
exec "$REAL_MV" "\$@"
SHIM
  chmod +x "$d/common/git" "$d/p2/cat" "$d/p2/mv"
  ( exit 0 ) & local dead=$!; wait "$dead" 2>/dev/null
  mkdir "$W/A/.git/meta-sync.lock"; printf '%s\n' "$dead" > "$W/A/.git/meta-sync.lock/pid"
  ( MS_WHO=P2 MS_HOLD=1 PATH="$d/p2:$d/common:$PATH" bash "$s" pull --root "$W/A" > "$d/p2.out" 2>&1; echo $? > "$d/p2.rc" ) &
  i=0; while [ ! -e "$d/p2.read" ] && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i+1)); done
  ( MS_WHO=P1 MS_HOLD=6 PATH="$d/common:$PATH" bash "$s" pull --root "$W/A" > "$d/p1.out" 2>&1; echo $? > "$d/p1.rc" ) &
  i=0; while ! grep -qx 'ENTER P1' "$d/holders.log" && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i+1)); done
  ( MS_WHO=P3 MS_HOLD=1 PATH="$d/common:$PATH" bash "$s" pull --root "$W/A" > "$d/p3.out" 2>&1; echo $? > "$d/p3.rc" ) &
  wait
  LR_RCS="$(cat "$d/p1.rc" "$d/p2.rc" "$d/p3.rc" | tr '\n' ' ')"
  LR_LOG="$(tr '\n' ' ' < "$d/holders.log")"
  LR_ENTERS="$(grep -c ENTER "$d/holders.log")"
  # the interleaving really happened: P2 read the dead pid, and P1 (not P2) reclaimed it
  LR_SEQ=0; [ -e "$d/p2.read" ] && grep -q 'reclaimed a stale lock' "$d/p1.out" && LR_SEQ=1
  LR_MAX="$(awk '$1 == "ENTER" { n++; if (n > m) m = n } $1 == "LEAVE" { n-- } END { print m + 0 }' "$d/holders.log")"
}
LR_MAX=""; LR_RCS=""; LR_LOG=""; LR_ENTERS=""; LR_SEQ=0
lock_race "$SUT"
[ "$LR_SEQ" = "1" ]; check $? "fixture: P2 held a stale read of the dead pid while P1 reclaimed the lock (forced interleaving happened)"
{ [ "$LR_MAX" = "1" ] && [ "$LR_RCS" = "0 0 0 " ] && [ "$LR_ENTERS" = "3" ] && [ ! -e "$W/A/.git/meta-sync.lock" ]; }
check $? "dead holder + 3 contenders, P2 stalled between reading the dead pid and acting: at most ONE holder at a time, all three pulls succeed, lock released (max=$LR_MAX rcs=$LR_RCS log: $LR_LOG)"

echo "== 28. a directory at a managed path never swallows or deletes the branch file =="
synced_pair
put A "$RQ/dir.md" "branch file"; put A "$RQ/x.md" "x v2 from A"; ms A push
mkdir -p "$W/B/$RQ/dir.md"
tip="$(br_tip)"; base_before="$(base_of B)"
ms B pull
{ [ "$RC" -eq 1 ] && grep -q "meta_sync: not_a_file $RQ/dir.md" < <(printf '%s' "$OUT") && [ -d "$W/B/$RQ/dir.md" ] && [ -z "$(ls -A "$W/B/$RQ/dir.md")" ] \
  && [ "$(get B "$RQ/x.md")" = "x v1" ] && [ "$(base_of B)" = "$base_before" ]; }
check $? "pull with a directory where the branch holds a file -> exit 1 not_a_file, nothing written into it or elsewhere, meta-base unchanged (rc=$RC: $OUT; inside: $(ls -A "$W/B/$RQ/dir.md" | tr '\n' ' '))"
put B "$RQ/y.md" "y v2 from B"; ms B push
{ [ "$RC" -eq 1 ] && [ "$(br_tip)" = "$tip" ] && [ "$(br_show "$RQ/dir.md")" = "branch file" ] && [ "$(base_of B)" = "$base_before" ]; }
check $? "the next push refuses too and the branch file is NOT deleted (rc=$RC: $OUT)"
rmdir "$W/B/$RQ/dir.md"; ms B pull
{ [ "$RC" -eq 0 ] && [ "$(get B "$RQ/dir.md")" = "branch file" ]; }; check $? "with the directory gone the pull lands (rc=$RC: $OUT)"
rm -f "$W/B/$RQ/dir.md"; mkdir -p "$W/B/$RQ/dir.md"
tip="$(br_tip)"; base_before="$(base_of B)"
ms B push
{ [ "$RC" -eq 1 ] && grep -q "meta_sync: not_a_file $RQ/dir.md" < <(printf '%s' "$OUT") && [ "$(br_tip)" = "$tip" ] && [ "$(br_show "$RQ/dir.md")" = "branch file" ] && [ "$(base_of B)" = "$base_before" ]; }
check $? "a synced file replaced by a directory -> push exits 1 not_a_file, the branch file is NOT deleted (rc=$RC: $OUT)"

echo "== 29. enumeration scope: unmanaged churn never blocks; managed roots stay fail-closed =="
if [ "$(id -u)" = "0" ]; then
  echo "  SKIP: chmod-000 legs (running as root, permissions are not enforced)"
else
  synced_pair
  mkdir -p "$W/B/.supervisor/logs/locked" "$W/B/.supervisor/worktrees/wt1/locked"
  chmod 000 "$W/B/.supervisor/logs/locked" "$W/B/.supervisor/worktrees/wt1/locked"
  put A "$RQ/x.md" "x v2 from A"; ms A push
  ms B pull
  { [ "$RC" -eq 0 ] && [ "$(get B "$RQ/x.md")" = "x v2 from A" ]; }
  check $? "an unreadable folder under .supervisor/logs and .supervisor/worktrees does not block a pull (rc=$RC: $OUT)"
  put B "$RQ/y.md" "y v2 from B"; ms B push
  { [ "$RC" -eq 0 ] && [ "$(br_show "$RQ/y.md")" = "y v2 from B" ]; }; check $? "... nor a push (rc=$RC: $OUT)"
  chmod 755 "$W/B/.supervisor/logs/locked" "$W/B/.supervisor/worktrees/wt1/locked"
  mkdir -p "$W/B/$RQ/locked"; chmod 000 "$W/B/$RQ/locked"
  put A "$RQ/x.md" "x v3 from A"; ms A push
  put B "$RQ/y.md" "y v3 from B"
  tip="$(br_tip)"; base_before="$(base_of B)"
  ms B pull; rc_pull=$RC; out_pull="$OUT"
  ms B push
  { [ "$rc_pull" -eq 1 ] && [ "$RC" -eq 1 ] && grep -q 'could not enumerate' < <(printf '%s' "$out_pull") && [ "$(get B "$RQ/x.md")" = "x v2 from A" ] \
    && [ "$(br_tip)" = "$tip" ] && [ "$(base_of B)" = "$base_before" ]; }
  check $? "an unreadable folder INSIDE requirements/ -> pull and push exit 1, nothing written, branch and meta-base unchanged (pull rc=$rc_pull push rc=$RC: $out_pull)"
  chmod 755 "$W/B/$RQ/locked"
  chmod 000 "$W/B/.supervisor/jobs"
  ms B push
  { [ "$RC" -eq 1 ] && [ "$(br_tip)" = "$tip" ] && [ "$(br_show .supervisor/jobs/done/2026-01-01-brief.md)" = "brief" ] && [ "$(base_of B)" = "$base_before" ]; }
  check $? "an unsearchable .supervisor/jobs (on the way to jobs/done) -> push exits 1, the done brief is NOT deleted (rc=$RC: $OUT)"
  chmod 755 "$W/B/.supervisor/jobs"
fi
synced_pair
CHURN="$W/B/.supervisor/worktrees/churn"; CHURN_ON="$W/churn.on"; : > "$CHURN_ON"
( while [ -e "$CHURN_ON" ]; do
    mkdir -p "$CHURN/a/b/c" "$CHURN/d/e/f" "$CHURN/g/h"; : > "$CHURN/a/b/c/f1"; : > "$CHURN/d/e/f/f2"
    rm -rf "$CHURN"
  done ) &
churn_pid=$!
churn_bad=0; churn_rcs=""
for i in 1 2 3 4 5 6; do
  put A "$RQ/x.md" "x churn $i"; ms A push
  ms B pull; churn_rcs="$churn_rcs pull=$RC"; [ "$RC" -eq 0 ] || churn_bad=1
  put B "$RQ/y.md" "y churn $i"; ms B push; churn_rcs="$churn_rcs push=$RC"; [ "$RC" -eq 0 ] || churn_bad=1
done
rm -f "$CHURN_ON"; wait "$churn_pid" 2>/dev/null
{ [ "$churn_bad" -eq 0 ] && [ "$(get B "$RQ/x.md")" = "x churn 6" ] && [ "$(br_show "$RQ/y.md")" = "y churn 6" ]; }
check $? "a folder tree churning under .supervisor/worktrees never blocks a pull or push (rcs:$churn_rcs)"

echo "== 30. a newline in a name fails closed (remote tree, R's history, local find) =="
synced_pair
OG="$W/origin.git"
tip0="$(br_tip)"
fabblob="$(printf 'fabricated\n' | og hash-object -w --stdin)"
legit="$(printf 'legit\n' | og hash-object -w --stdin)"
# A directory named "x<LF>100644 blob <fabblob><TAB>.supervisor" holding requirements/fab.md: read
# line by line, its ls-tree record splits into `.supervisor/requirements/x` and a FABRICATED
# `100644 blob <fabblob><TAB>.supervisor/requirements/fab.md` record (fabblob is made reachable as
# fabsrc.md so a parser fooled by it can really write it). legit.md / fabsrc.md are pending take-Rs.
t_fab="$(printf '100644 blob %s\tfab.md\0' "$legit" | og mktree -z)"
t_mid="$(printf '040000 tree %s\trequirements\0' "$t_fab" | og mktree -z)"
nl_name="$(printf 'x\n100644 blob %s\t.supervisor' "$fabblob")"
req0="$(og rev-parse "$tip0:.supervisor/requirements")"
reqN="$({ og ls-tree -z "$req0"; printf '040000 tree %s\t%s\0' "$t_mid" "$nl_name"; printf '100644 blob %s\tlegit.md\0' "$legit"; printf '100644 blob %s\tfabsrc.md\0' "$fabblob"; } | og mktree -z)"
cN="$(printf 'newline name\n' | og commit-tree "$(swap_req "$reqN")" -p "$tip0")"
og update-ref "refs/heads/$BR" "$cN"
grep -qF "requirements/x|100644 blob $fabblob" < <(og ls-tree -r -z --name-only "$cN" | tr '\0\n' '\n|')
check $? "fixture: the branch tip really carries a tree entry whose name holds a newline"
base_before="$(base_of B)"
ms B pull
{ [ "$RC" -eq 1 ] && grep -q 'meta_sync: newline_in_path tree ' < <(printf '%s' "$OUT") && [ ! -e "$W/B/.supervisor/requirements/fab.md" ] \
  && [ ! -e "$W/B/.supervisor/requirements/legit.md" ] && [ ! -e "$W/B/.supervisor/requirements/fabsrc.md" ] && [ "$(base_of B)" = "$base_before" ] && [ -z "$(porcelain B)" ]; }
check $? "pull over a newline entry -> exit 1 newline_in_path, no fabricated fab.md, pending legit.md / fabsrc.md not written, meta-base unchanged (rc=$RC: $OUT)"
put B "$RQ/y.md" "y over a newline tip"; ms B push
{ [ "$RC" -eq 1 ] && grep -q 'meta_sync: newline_in_path tree ' < <(printf '%s' "$OUT") && [ "$(br_tip)" = "$cN" ] && [ "$(base_of B)" = "$base_before" ]; }
check $? "push over a newline entry -> exit 1 newline_in_path, branch tip and meta-base unchanged (rc=$RC: $OUT)"
cC="$(printf 'cleanup\n' | og commit-tree "$(swap_req "$(og rev-parse "$tip0:.supervisor/requirements")")" -p "$cN")"
og update-ref "refs/heads/$BR" "$cC"
ms B pull; rc_pull=$RC; out_pull="$OUT"
ms B push
{ [ "$rc_pull" -eq 0 ] && [ "$RC" -eq 0 ] && [ "$(br_show "$RQ/y.md")" = "y over a newline tip" ] && [ ! -e "$W/B/.supervisor/requirements/fab.md" ]; }
check $? "with the entry gone from the tip, the same clone (meta-base present) pulls and pushes again (pull rc=$rc_pull: $out_pull; push rc=$RC: $OUT)"
clone NL
ms NL pull
{ [ "$RC" -eq 1 ] && grep -q 'meta_sync: newline_in_path the history of ' < <(printf '%s' "$OUT") && [ ! -e "$W/NL/.git/meta-base" ] && [ ! -e "$W/NL/.supervisor" ]; }
check $? "a fresh clone (no meta-base) refuses the newline entry still in R's history: exit 1, nothing written, no meta-base (rc=$RC: $OUT)"
echo "-- a newline in a LOCAL name under a managed root --"
put A "$RQ/x.md" "x v2 from A"; ms A pull; ms A push
nl_local="$W/B/$RQ/$(printf 'a\nb.md')"
printf 'local newline\n' > "$nl_local"
tip="$(br_tip)"; base_before="$(base_of B)"
ms B pull
{ [ "$RC" -eq 1 ] && grep -q 'meta_sync: newline_in_path the local files' < <(printf '%s' "$OUT") && [ "$(get B "$RQ/x.md")" = "x v1" ] && [ "$(base_of B)" = "$base_before" ]; }
check $? "pull with a local newline name under requirements/ -> exit 1, pending x.md not written, meta-base unchanged (rc=$RC: $OUT)"
put B "$RQ/w.md" "w v2 from B"; ms B push
{ [ "$RC" -eq 1 ] && grep -q 'meta_sync: newline_in_path the local files' < <(printf '%s' "$OUT") && [ "$(br_tip)" = "$tip" ] && [ "$(base_of B)" = "$base_before" ]; }
check $? "push with a local newline name -> exit 1, branch tip and meta-base unchanged (rc=$RC: $OUT)"
rm -f "$nl_local"
mkdir -p "$W/B/.supervisor/logs"; printf 'x\n' > "$W/B/.supervisor/logs/$(printf 'n\nl.log')"
ms B pull; rc_pull=$RC; out_pull="$OUT"
ms B push
{ [ "$rc_pull" -eq 0 ] && [ "$RC" -eq 0 ] && [ "$(get B "$RQ/x.md")" = "x v2 from A" ] && [ "$(br_show "$RQ/w.md")" = "w v2 from B" ]; }
check $? "with it removed (a newline name under unmanaged .supervisor/logs is ignored) pull and push land (pull rc=$rc_pull: $out_pull; push rc=$RC: $OUT)"

echo "== 31. --paths-from is push-only (usage error elsewhere, nothing changed) =="
synced_pair
put A "$RQ/x.md" "x v2 from A"; ms A push
printf '%s\n' "$RQ/x.md" > "$W/pf.txt"
tip="$(br_tip)"; base_before="$(base_of B)"
for sc in pull status init; do
  ms B "$sc" --paths-from "$W/pf.txt"
  { [ "$RC" -eq 1 ] && grep -q "meta_sync: usage: --paths-from applies to push only, not '$sc'" < <(printf '%s' "$OUT") \
    && [ "$(get B "$RQ/x.md")" = "x v1" ] && [ "$(br_tip)" = "$tip" ] && [ "$(base_of B)" = "$base_before" ]; }
  check $? "$sc --paths-from -> usage error exit 1, nothing written, branch and meta-base unchanged (rc=$RC: $OUT)"
done
ms B pull --paths-from ""
{ [ "$RC" -eq 1 ] && [ "$(get B "$RQ/x.md")" = "x v1" ]; }; check $? "pull --paths-from '' (empty value) is rejected too (rc=$RC: $OUT)"
ms B pull; { [ "$RC" -eq 0 ] && [ "$(get B "$RQ/x.md")" = "x v2 from A" ]; }; check $? "pull without the flag still lands (rc=$RC: $OUT)"

echo "== 32. project deny patterns (.agent/meta-sync-deny.txt) =="
synced_pair
DENY="$W/B/.agent/meta-sync-deny.txt"
mkdir -p "$W/B/.agent"
printf '%s\n' '# project deny terms' '' 'ACME-SECRET-[0-9]+' > "$DENY"
git -C "$W/B" add .agent/meta-sync-deny.txt && git -C "$W/B" commit -qm 'deny patterns'
put B "$RQ/deny.md" "ticket ACME-SECRET-42 notes"
put B "$RQ/clean.md" "nothing to see here"
tip="$(br_tip)"; base_before="$(base_of B)"
ms B push
{ [ "$RC" -eq 2 ] && grep -qxF "meta_sync: scrub $RQ/deny.md: deny_pattern:3" < <(printf '%s\n' "$OUT") \
  && ! grep -qF "scrub $RQ/clean.md" < <(printf '%s' "$OUT") && [ "$(br_tip)" = "$tip" ] && [ "$(base_of B)" = "$base_before" ]; }
check $? "a matching deny ERE -> exit 2 naming deny_pattern:<line> (comment/blank lines counted), clean file not named, branch and meta-base unchanged (rc=$RC: $OUT)"
printf '%s\n' 'never-matches-zzz' '[unclosed' > "$DENY"
git -C "$W/B" commit -qam 'invalid deny pattern'
ms B push
{ [ "$RC" -eq 2 ] && grep -qxF "meta_sync: scrub $RQ/deny.md: deny_pattern_invalid:2" < <(printf '%s\n' "$OUT") \
  && grep -qxF "meta_sync: scrub $RQ/clean.md: deny_pattern_invalid:2" < <(printf '%s\n' "$OUT") && [ "$(br_tip)" = "$tip" ] && [ "$(base_of B)" = "$base_before" ]; }
check $? "an invalid deny ERE -> exit 2 deny_pattern_invalid:<line> for every candidate (fail closed), branch and meta-base unchanged (rc=$RC: $OUT)"
git -C "$W/B" rm -q .agent/meta-sync-deny.txt && git -C "$W/B" commit -qm 'drop deny patterns'
ms B push
{ [ "$RC" -eq 0 ] && [ "$(br_show "$RQ/deny.md")" = "ticket ACME-SECRET-42 notes" ] && [ "$(br_show "$RQ/clean.md")" = "nothing to see here" ]; }
check $? "with the deny file absent the extension is a no-op and the same push lands (rc=$RC: $OUT)"

echo "== 33. the other fail-closed scrub branches (scan_error, ledger_unverifiable, unreadable) =="
# scan_error and unreadable are only reachable through a failing tool: the built-in EREs are fixed
# and valid, and every candidate blob was written by hash-object -w earlier in the same run. Both
# are fault-injected with PATH shims (the technique legs 22 and 27 use).
REAL_GREP="$(command -v grep)"
synced_pair
mkdir -p "$W/gshim"
cat > "$W/gshim/grep" <<SHIM
#!/bin/sh
# fault injection: the built-in case-insensitive rule scan (grep -i -E -q -e <re> <file>) errors
if [ "\$1" = "-i" ] && [ "\$2" = "-E" ] && [ "\$3" = "-q" ]; then exit 2; fi
exec "$REAL_GREP" "\$@"
SHIM
chmod +x "$W/gshim/grep"
put B "$RQ/se.md" "plain clean text"
tip="$(br_tip)"; base_before="$(base_of B)"
OUT="$(PATH="$W/gshim:$PATH" bash "$SCRIPT" push --root "$W/B" 2>&1)"; RC=$?
{ [ "$RC" -eq 2 ] && grep -qxF "meta_sync: scrub $RQ/se.md: scan_error(email)" < <(printf '%s\n' "$OUT") \
  && grep -qxF "meta_sync: scrub $RQ/se.md: scan_error(home_path)" < <(printf '%s\n' "$OUT") && [ "$(br_tip)" = "$tip" ] && [ "$(base_of B)" = "$base_before" ]; }
check $? "a scan that errors -> exit 2 scan_error(<rule>), branch and meta-base unchanged (rc=$RC: $OUT)"
rm -f "$W/B/$RQ/se.md"
# a PATH with every tool the SUT and setup-memory.sh use EXCEPT jq (macOS ships /usr/bin/jq, so
# dropping one directory is not enough): a hermetic dir of symlinks, built here.
NOJQ="$W/nojq-bin"; mkdir -p "$NOJQ"
for t in bash sh git cat dirname basename sed awk mktemp rm mkdir rmdir ps find date sleep tr sort uniq \
         paste wc grep chmod mv cp ln touch cut env ls head tail id xargs cmp tee od stat readlink uname \
         expr true false printf test; do
  tp="$(command -v "$t" 2>/dev/null)"
  case "$tp" in /*) ln -sf "$tp" "$NOJQ/$t" ;; esac
done
NOJQ_PATH="${HERMETIC_SHIM_DIR:+$HERMETIC_SHIM_DIR:}$NOJQ"
[ -z "$(PATH="$NOJQ_PATH" command -v jq)" ] && [ -n "$(PATH="$NOJQ_PATH" command -v git)" ]
check $? "fixture: the no-jq PATH has git but no jq"
printf '%s\n' '{"repo":"owner/repo","n":3}' >> "$W/B/.supervisor/postmortem/results.jsonl"
tip="$(br_tip)"; base_before="$(base_of B)"
OUT="$(PATH="$NOJQ_PATH" "$NOJQ/bash" "$SCRIPT" push --root "$W/B" 2>&1)"; RC=$?
{ [ "$RC" -eq 2 ] && grep -qxF "meta_sync: scrub .supervisor/postmortem/results.jsonl: ledger_unverifiable(jq missing)" < <(printf '%s\n' "$OUT") \
  && [ "$(br_tip)" = "$tip" ] && [ "$(base_of B)" = "$base_before" ]; }
check $? "jq missing -> the ledger is unverifiable: exit 2 ledger_unverifiable(jq missing), branch and meta-base unchanged (rc=$RC: $OUT)"
ms B push; { [ "$RC" -eq 0 ] && grep -q '"n":3' < <(br_show .supervisor/postmortem/results.jsonl); }; check $? "... and with jq back the same ledger push lands (rc=$RC: $OUT)"
mkdir -p "$W/cshim"
cat > "$W/cshim/git" <<SHIM
#!/bin/sh
# fault injection: a candidate blob the scrub cannot read back (git -C <root> cat-file blob <sha>)
if [ "\$3" = "cat-file" ] && [ "\$4" = "blob" ]; then exit 128; fi
exec "$REAL_GIT" "\$@"
SHIM
chmod +x "$W/cshim/git"
put B "$RQ/ur.md" "plain clean text"
tip="$(br_tip)"; base_before="$(base_of B)"
OUT="$(PATH="$W/cshim:$PATH" bash "$SCRIPT" push --root "$W/B" 2>&1)"; RC=$?
{ [ "$RC" -eq 2 ] && grep -qxF "meta_sync: scrub $RQ/ur.md: unreadable" < <(printf '%s\n' "$OUT") && [ "$(br_tip)" = "$tip" ] && [ "$(base_of B)" = "$base_before" ]; }
check $? "a candidate the scrub cannot read -> exit 2 unreadable, branch and meta-base unchanged (rc=$RC: $OUT)"

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
