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
#      (legs 5 and 9: --paths names the local_ahead / conflict paths after the unchanged first line)
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
#  31. --paths-from on pull / status / init / list-managed -> usage error exit 1, nothing changed
#  32. project deny patterns: a matching ERE -> exit 2 `deny_pattern:<line>`; an invalid ERE ->
#      exit 2 `deny_pattern_invalid:<line>`; the deny file absent -> the push lands
#  33. scan_error(<rule>) (failing grep), ledger_unverifiable(jq missing) (a hermetic no-jq PATH)
#      and unreadable (failing cat-file) -> exit 2, branch and meta-base unchanged
#  34. push-retry exhaustion: an origin whose pre-receive rejects every push -> exit 1 `push_failed
#      — rejected <N> times`, N = meta-sync.sh's own MAX_ATTEMPTS (grep-read, never hard-coded); the
#      hook ran exactly N times; branch tip unchanged, meta-base byte-unchanged; a PATH git shim
#      logged exactly N push argvs, none with a force form (--force*, -f, a +refspec)
#  35. a meta-base tree object missing from the object store (a nonexistent 40-hex sha) -> the
#      `missing from the object store` warning and the no-base derivation: push does not re-add a
#      branch-deleted file and pushes a new one; pull deletes it locally; an unlisted conflict
#      still aborts a --paths-from push (branch tip and meta-base unchanged)
#  38. symlinks under requirements/: a symlinked non-managed FILE (requirements/q/design.png -> a
#      file outside .supervisor/) -> pull and push exit 0, no `meta_sync: symlink` line, no
#      design.png on the branch; a DANGLING symlink -> pull and push exit 1 naming it (branch tip,
#      branch names and meta-base unchanged); a symlinked managed .md -> pull exits 1 too (leg 26
#      keeps the symlinked-folder and push-side managed-file shapes)
#  39. fetch fallback: a PATH git shim rejecting any --no-write-fetch-head invocation (exit 129,
#      git's "unknown option" text) -> pull and push still succeed with the right content; the
#      shim log shows the flagged fetch, then the plain retry, for each
#  40. changed during the sync: the pull plans a UNION on the ledger and a TAKE_R on an automate
#      run file that sorts before it; a git shim appends a ledger line right after the planning
#      `hash-object --stdin-paths` returns -> pull exits non-zero `changed during the sync`, the
#      ledger = pre-pull bytes + the injected line, meta-base byte-unchanged, no other managed
#      file written or deleted (the take-R file keeps its bytes — the union now runs first)
#  41. nested reclaim: a dead holder's meta-sync.lock AND a dead reclaimer's lock.reclaim.<pid>
#      marker -> a concurrent push + pull reclaim both (no lock directory left), both exit 0, the
#      push lands, never two holders (leg 27's holder log)
#  42. a DIRECTORY at <gitdir>/meta-base: push (a local change) and pull (a remote change) refuse
#      UP FRONT — exit 1 naming meta-base `not a regular file (it is a directory)`, nothing
#      published, nothing written locally, the directory left empty in place
#  43. default branch from the mode line (setup-memory.sh mode): a clone whose mode line names a
#      throwaway branch inits / pushes / pulls it with no flag (the real loomwright-meta ref
#      untouched) and `status` prints `synced <sha> on <branch>`; a mismatched --branch ->
#      exit 1 `branch_mismatch` for pull / push / status / init, nothing changed; an equal
#      --branch proceeds; --allow-branch-mismatch overrides (and alone is a usage error); no mode
#      line -> loomwright-meta; a mode line naming loomwright-meta accepts --branch
#      loomwright-meta; an `unknown` mode -> exit 1 `mode_unknown` with no flag and with a bare
#      --branch (the override proceeds); a failed reader (no sibling setup-memory.sh, a non-zero
#      exit, a multi-line or unrecognised answer) -> `mode_unknown`, never the default branch
#  50. meta-base is bound to its branch (line 2 `branch <name>`): a clone synced on loomwright-meta
#      switches its mode line to lane-z (setup-memory.sh apply) and inits it -> status prints
#      `base_branch_mismatch`; a plain pull, a push and the forced --branch lane-z
#      --allow-branch-mismatch path each exit 1 `base_branch_mismatch` naming both branches, with
#      NOTHING deleted locally or on either branch and meta-base byte-unchanged; the base's own
#      branch still syncs; with meta-base removed by hand the lane-z pull deletes nothing and
#      rebinds meta-base to lane-z
#  51. legacy single-line meta-base: taken from the SAME branch it is adopted (a local edit pushes
#      as take-L) and the rewrite adds the branch line; taken from another branch (an entry the
#      target's history never held) pull / push exit 1 `base_branch_mismatch`, nothing changed,
#      status says so; a meta-base in no recognised format (a third line) is refused the same way
#  --- Mutation controls (sed-patched mutant copies in the temp dir; the shipped script has no
#      test seam) ---
#  20. (i) a mutant that drops the base comparison (any local difference is staged) MUST fail the
#      stale-copy assertion
#  21. (ii) a mutant whose managed-set predicate accepts every file under .supervisor/ (a directory
#      add) MUST fail the ignored-file assertion
#  36. (iii) a mutant whose exhausted-retry path exits 0 instead of dying `push_failed` MUST fail
#      the push-retry-exhaustion assertion (34)
#  37. (iv) a mutant whose load_base reads a missing base object as the EMPTY tree MUST fail the
#      missing-base push assertion (35) by re-adding the branch-deleted file
#  44. (v) a mutant restoring the unconditional `is_managed "$1" || is_managed "$1/x.md"` probe MUST
#      fail the design.png assertion (38) with `meta_sync: symlink`
#  45. (vi) a mutant whose fetch fallback returns 1 instead of retrying MUST fail the fetch-fallback
#      assertion (39) with fetch_failed
#  46. (vii) a mutant without the union's hash re-check MUST fail the changed-during-the-sync
#      assertion (40) — proves the hook fires inside the window
#  47. (viii) a mutant without the one-level-up reclaim MUST fail the nested-reclaim assertion (41)
#      by waiting out META_SYNC_LOCK_WAIT_SECS and dying `locked`
#  48. (ix) a mutant without the up-front meta-base check MUST fail the directory-meta-base
#      assertion (42) — it publishes before failing to write meta-base
#  49. (x) a mutant that ignores the mode line (the default stays loomwright-meta) MUST fail the
#      throwaway-clone assertion (43) by pushing the real loomwright-meta
#  52. (xi) a mutant without load_base's branch-binding check MUST fail the branch-switch
#      assertion (50) by deleting the switched clone's a.md + b.md
#  53. home_path is anchored: ten home-path forms hit; the S3 false positive /api/users/42/, a /v1 route,
#      a URL's /home/ segment and the angle-bracket placeholders do not, and push once the positives go
#  54. guard: no literal home-path example in loomwright/agents|commands|skills, read off the shipped rule
#  55. (xii) a mutant with the old unanchored home_path rule MUST fail the API-route assertion (53)
#  56. list-managed: prints exactly the managed local paths (no log / nested .supervisor/ / pending /
#      sidecar), equal to the set a whole-set push publishes, no lock / meta-base / publish;
#      --tracked prints only the tracked managed paths (force-added unmanaged ones excluded); a
#      symlinked folder under requirements/ fails closed like push; --tracked elsewhere and
#      --branch on list-managed are usage errors; under an UNKNOWN mode list-managed and scrub
#      still run (status still refuses), no lock, no meta-base, no branch created
#  57. scrub --paths-from: one stderr `meta_sync: scrub-hit <path>:<line>: <rule>` per hit — the
#      first matching line for email / home_path / token_github / deny_pattern:<n>, `-` for
#      forge_slug / ledger_repo / unreadable (a missing path, a directory) — exit 2; stdout empty,
#      no push-style `meta_sync: scrub ` line; nothing written; a `push` over the SAME planted
#      files names the same (path, rule) pairs; a clean list -> exit 0 `meta_sync: clean (<n>
#      file(s) scanned)`; no --paths-from / a missing list / --branch -> usage error exit 1
#  58. (xiii) a mutant whose line lookup always yields `-` MUST fail the line assertion (57)
#  59. parallel-automate/05 D9: a top-level `.supervisor/automate/<name>.dismissed-decisions` ledger is
#      managed (list-managed lists it; a whole-set push publishes it); a nested one, a bare
#      `.dismissed-decisions`, a `.lanes` sidecar and a `<name>.dismissed-decisions.bak` are not; a
#      ledger carrying a home path is refused by push's scrub (exit 2), nothing published
#  60. mutation control (xiv): a mutant without the D9 is_managed arm drops the ledger -> (59) turns red
#  61. an UNREADABLE meta-base (chmod 000; skipped under root like leg 29): pull and push exit 1
#      `base_branch_mismatch — meta-base <path> is unreadable`, nothing written locally, nothing
#      published, meta-base bytes unchanged (automate-followups/36 A6)
#  62. mutation control (xv): a mutant without load_base's unreadable arm no longer refuses as
#      unreadable -> (61) turns red
#  63. the tracked request file .agent/meta-allowlist.txt (af36-remainder/02): a fresh clone with
#      NO config.json and the file-level allowlist env scrubbed pulls, then pushes an old-slug
#      ledger line + an old-slug forge URL -> exit 0 (a gh stub answers the old slug with origin's
#      id; a git shim reports a GitHub-shaped origin while fetches still hit the local bare repo);
#      a failing gh -> the same push is refused (exit 2 ledger_repo); a requested slug that is a
#      DIFFERENT repository -> its record refused and the resolver names it on stderr
#  64. mutation control (xvi): a setup-memory.sh mutant without the request-file layer call turns
#      the A1 push (63) red
#  65. email exemption, exact: the scp-style git SSH remote at each forge_slug host (git@github.com:,
#      git@gitlab.com:, git@bitbucket.org: + an allowlisted owner/repo) passes the email rule — scrub
#      exit 0 per host, and a push of all three lands; refusals still exit 2 naming email at the right
#      line: a real address at a forge host, a non-forge git@ host, a look-alike forge host, a longer
#      user (xgit@), a colon-less git@github.com, an upper-case remote, and a line holding a forge
#      remote AND a real address (line 2, after an exempt-only line 1); an unallowlisted slug after
#      git@github.com: is still forge_slug (and not email); a push over the refusals exits 2
#  66. mutation control (xvii): a mutant exemption widened to any user, and one without the trailing
#      `:`, each turn a refusal leg of (65) green-when-it-must-be-red
#  --- af36-03: the learning stores (twin contracts + .provenance.jsonl, agent-memory proposals, the
#      two eval JSONL files) on the metadata branch; every leg builds its OWN world, so no fixture
#      that later calls assert_ignored_clean ever holds a learning store ---
#  67. managed set: list-managed lists the new paths and no look-alike (nested folders under the new
#      roots, other .jsonl, worker-summaries/); --run-history drops them; --tree lists a tree; a
#      consented whole-set push publishes exactly the set; a symlinked new root / managed file and
#      a newline name under a new root fail closed; --tree/--tracked, --run-history and --learning
#      outside their subcommand are usage errors
#  68. mutation control: worker-summaries/ added to is_managed is listed (67's exclusion is pinned)
#  69. twin pair rule: an unprovenanced contract -> push and pull exit 0 naming `twin_refused <path>:
#      no chain-valid add provenance entry`, the written side's twin set unchanged, run history synced
#  70. mutation control: a pair check that always passes publishes the rogue contract
#  71. provenance fork: both sides appended -> `twin_refused .provenance.jsonl: conflict` on pull and
#      push, no union, twin set unchanged, run history synced, exit 0; status's first line ignores
#      it and --learning reports it
#  72. mutation control: provenance in the union-path predicate is no longer reported as a conflict
#  73. meta-base after a refusal: per-path (previous provenance entry, no entry for the unreceived
#      contract, run history as R); a follow-up whole-set push re-refuses, branch twin set unchanged
#  74. mutation control: recording R's tree after the refused pull lets the push rewrite the branch
#  75. merge semantics: both eval files line-union; a .dismissed-decisions ledger ordered-merges so
#      the NEWER branch decision wins over an OLDER local one (pull side and push side)
#  76. mutation controls: a plain union for the ledger lets the older decision win; eval dropped
#      from the predicate conflicts
#  77. scrub per new type (consent granted): a home path / token in eval .jsonl, a .dismissed-decisions
#      ledger, a proposal and a provenanced twin contract -> exit 2 naming it, nothing pushed; a
#      clean twin pair lands; mutation control: scanning only .md candidates publishes the token
#  78. consent: no record and `declined` -> every learning path named `learning_skipped`, run history
#      pushed, exit 0 (a second push -> no_changes); `granted` -> they push; a --paths-from push
#      never mentions them; pull takes them regardless of consent
#  79. mutation control: an always-granted consent read publishes the learning stores
#  80. status split: learning-only local / remote changes leave the first line `synced` (with and
#      without --paths); --learning adds ONE last line; a run-history change still counts alone
#  81. mutation control: counting learning rows in the first line prints local_ahead
#  82. round trip: write-system-contract.sh contracts + proposals, eval files and a dismissed ledger
#      pushed with consent; read-system-contract.sh in a fresh clone prints the same
#      `twin_store_status: healthy (emitted 2, …)`; the other stores are byte-identical
#  83. a TRACKED learning store (owner decision a: git owns it): B force-tracks $EV with a local line
#      while a sibling appends another on the branch -> B's pull leaves the tracked file byte-unchanged
#      (no union written, porcelain empty) naming `learning_tracked <path> — tracked by git, left to
#      git`, run history still arrives, exit 0, meta-base keeps the previous $EV entry; B's push never
#      publishes it (branch copy unchanged) while its run history lands; status --learning ends
#      `; tracked 1`
#  84. mutation control: without the tracked-learning hold (83) turns red (the pull unions into the
#      tracked file)
#  85. (83)'s world pulled with GIT_INDEX_FILE=/nonexistent exported -> the hold reads the real index
#      anyway: the tracked file byte-unchanged and named `learning_tracked`, `git status` clean
#  86. mutation control: a hold whose ls-files honours the inherited GIT_INDEX_FILE (no `env -u`)
#      turns (85) red (a missing index reads as nothing tracked; the pull unions into the file)
#  87. list-managed --tracked with GIT_INDEX_FILE=/nonexistent exported -> still lists the committed
#      tracked managed path (the real index), exit 0
#  88. mutation control: a list-managed --tracked whose ls-files honours the inherited GIT_INDEX_FILE
#      (no `env -u`) turns (87) red (a missing index lists nothing tracked)

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

# ---- legs: test-meta-sync.d/<part>.sh (automate-speed/20) ------------------------------------
# The legs below moved verbatim, in base order, into test-meta-sync.d/. Each part is sourced BY
# NAME (never a glob) at top level, so it shares this file's setup, helpers and counters; a missing
# or unreadable part aborts the suite (exit 1, the part named) instead of silently dropping its legs.
# SUTB is meta-sync.sh as ONE file — its own _ms_bundle output (the entry with every meta-sync.d/
# module inlined), written once. Every TEXT read of the script reads it: the mutation-control
# helper's sed input and cmp gate, and the static greps (19, 34, 54). A mutant written from it is
# self-contained, so it runs without meta-sync.d/. Every RUN still runs the real entry ($SUT /
# $SCRIPT); HERE is unchanged.
SUTB="$TROOT/meta-sync.bundle.sh"
( eval "$(awk '/^_ms_bundle\(\) \{$/,/^}$/' "$SUT")"; _ms_bundle "$SUT" ) > "$SUTB" && [ -s "$SUTB" ] \
  || { echo "  FAIL: could not build the single-file meta-sync.sh bundle (_ms_bundle) into $SUTB"; exit 1; }
TMS_D="$HERE/test-meta-sync.d"
tms_part() { [ -f "$TMS_D/$1.sh" ] && [ -r "$TMS_D/$1.sh" ] || { echo "  FAIL: missing test part: test-meta-sync.d/$1.sh"; exit 1; }; }
tms_part 01-sync-core;                . "$TMS_D/01-sync-core.sh"
tms_part 02-guards-mode-base;         . "$TMS_D/02-guards-mode-base.sh"
tms_part 03-mutants-scrub-allowlist;  . "$TMS_D/03-mutants-scrub-allowlist.sh"
tms_part 04-learning-stores;          . "$TMS_D/04-learning-stores.sh"
echo
echo "test-meta-sync: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
