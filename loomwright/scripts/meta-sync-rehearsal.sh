#!/usr/bin/env bash
# meta-sync-rehearsal.sh — rehearse a branch-mode migration of a checkout on a SCRATCH copy before
# anything real happens. It clones the checkout's current branch into a fresh LOCAL bare repo, works
# in clones of that bare repo only, and drills the whole meta-sync.sh life cycle there:
#
#   init -> push -> verify -> migrate (scratch) -> second-checkout pull -> post-migration
#   edit / add / delete -> rollback (the SHIPPED `migrate-branch-mode.sh rollback`) -> twin count
#
# It prints one `PASS: <check>` or `FAIL: <check> — <detail>` line per check (plus `info:` lines),
# then `meta-sync-rehearsal: <n> passed, <m> failed`, and exits 1 on any FAIL.
#
# Usage:
#   meta-sync-rehearsal.sh [--root <checkout>] [--branch <name>] [--no-config]
#
#   --root       the checkout to rehearse (default: `git rev-parse --show-toplevel` of $PWD). It is
#                only READ: cloned, listed (`meta-sync.sh list-managed`, which writes nothing) and
#                copied from. Nothing is ever written to it, and its remotes are never contacted.
#   --branch     metadata branch name to rehearse with (default loomwright-meta; vetted with
#                `setup-memory.sh valid-branch` first). Every meta-sync.sh call passes it.
#   --no-config  rehearse WITHOUT the checkout's configuration: `.supervisor/config.json` (the repo
#                allowlist) and `.agent/meta-sync-deny.txt` (scrub deny patterns) are removed from
#                the scratch clone (a tracked copy is removed by a scratch-only commit) and
#                LOOMWRIGHT_MEMORY_REPO_ALLOWLIST is unset. Default: both files are carried over.
#
# CHECKS (stable names — the self-test greps them):
#   scratch-remote        the scratch clone's ONLY remote is `origin` = the local bare repo
#   scratch-mode-off      the scratch clone reads mode `off` (a migrated checkout cannot be rehearsed)
#   init                  `meta-sync.sh init --branch <b>` created origin/<b> (scratch bare repo)
#   push                  `meta-sync.sh push --branch <b>` succeeded
#   verify-present        every managed path (list-managed) is on the branch
#   verify-blobs          every branch blob equals the local file (hash-object)
#   verify-nothing-extra  the branch holds nothing outside the managed set
#   verify-types          every branch entry is a regular 100644 blob named *.md or results.jsonl
#                         under .supervisor/, and every local managed path is a regular file
#   migrate-clean         after the scratch migration commit (`setup-memory.sh apply --branch-mode`
#                         + `git rm -r --cached` of the tracked managed set, on the scratch default
#                         branch), mode reads `on <b>` and `git status --porcelain` is empty
#   pull-roundtrip        a SECOND clone runs `meta-sync.sh pull --branch <b>`: same managed list,
#                         every file byte-identical (cmp) to the first clone's
#   rollback-run          the shipped `migrate-branch-mode.sh rollback --commit <migration commit>`
#                         exits 0, pushes a NEW branch, opens a PR through a stub gh, never merges
#                         (the scratch default branch is unchanged)
#   rollback-edit-kept    the post-migration edit is in the rollback tree
#   rollback-add-kept     the post-migration addition is in the rollback tree
#   rollback-delete-kept  the post-migration deletion stays deleted in the rollback tree
#   rollback-all-kept     every file on the branch tip is in the rollback tree with the same blob
#   rollback-gitignore    the rollback tree's .gitignore equals the pre-migration .gitignore
#   twin-contracts        the System Twin reader (read-system-contract.sh) verifies EVERY contract
#                         file in .supervisor/twin/contracts/ (copied from the checkout), before and
#                         after the round trip, with the same count — a contract without provenance
#                         is dropped by the reader and therefore fails this check
#   source-untouched      the checkout's refs, remote config and `git status --porcelain` are
#                         identical before and after the run
#
# Run history the checkout holds UNTRACKED (gitignored) is copied into the scratch clone, as is the
# checkout's .git/info/exclude and .supervisor/twin/. When fewer than two managed *.md files exist,
# two synthetic ones are added (an `info:` line says so) so the edit / delete drill has material.
# `gh` is a stub inside the scratch dir (LOOMWRIGHT_GH_BIN + PATH); no real gh call is made. The
# scratch dir is removed on every exit path.
#
# Exit: 0 every check passed; 1 at least one FAIL (or the checkout could not be rehearsed);
#       2 usage error. Portability: bash 3.2 + BSD userland.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MS="$HERE/meta-sync.sh"
SM="$HERE/setup-memory.sh"
MB="$HERE/migrate-branch-mode.sh"
RSC="$HERE/read-system-contract.sh"

usage() { awk 'NR > 1 && !/^#/ { exit } NR > 1' "$0" | sed 's/^# \{0,1\}//'; }
die() { printf 'meta-sync-rehearsal: %s\n' "$*" >&2; exit 1; }

ROOT=""; B="loomwright-meta"; NOCFG=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root|--branch)
      [ $# -ge 2 ] && [ -n "$2" ] && [ "${2#-}" = "$2" ] || { echo "meta-sync-rehearsal: $1 needs a value" >&2; exit 2; }
      case "$1" in --root) ROOT="$2" ;; --branch) B="$2" ;; esac; shift 2 ;;
    --no-config) NOCFG=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "meta-sync-rehearsal: unknown argument $1" >&2; exit 2 ;;
  esac
done

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE
export GIT_TERMINAL_PROMPT=0
[ -n "$ROOT" ] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || true
[ -n "$ROOT" ] && [ -d "$ROOT" ] || die "not inside a git checkout (use --root)"
ROOT="$(cd "$ROOT" && pwd -P)"
bash "$SM" valid-branch "$B" >/dev/null 2>&1 || { echo "meta-sync-rehearsal: '$B' is not a valid metadata branch name" >&2; exit 2; }
DEF="$(git -C "$ROOT" symbolic-ref -q --short HEAD)" || die "the checkout is on a detached HEAD; check out its default branch first"
[ "$NOCFG" -eq 1 ] && unset LOOMWRIGHT_MEMORY_REPO_ALLOWLIST

src_fingerprint() {
  git -C "$ROOT" for-each-ref --format='%(refname) %(objectname)'
  git -C "$ROOT" config --get-regexp '^remote\.' 2>/dev/null
  git -C "$ROOT" status --porcelain 2>/dev/null
}
FP0="$(src_fingerprint)"

S="$(mktemp -d "${TMPDIR:-/tmp}/meta-sync-rehearsal.XXXXXX")" || die "mktemp failed"
S="$(cd "$S" && pwd -P)"
trap 'rm -rf "$S"' EXIT
trap 'exit 1' INT TERM HUP
O="$S/origin.git"; A="$S/A"; C="$S/B"
echo "info: scratch $S (removed on exit); branch $B; default $DEF; config $([ "$NOCFG" -eq 1 ] && echo off || echo on)"

pass=0; fail=0
res() { # res <rc> <check> [detail]
  if [ "$1" -eq 0 ]; then echo "PASS: $2"; pass=$((pass+1)); else echo "FAIL: $2${3:+ — $3}"; fail=$((fail+1)); fi
}
finish() {
  [ "$FP0" = "$(src_fingerprint)" ]; res $? source-untouched "the checkout's refs / remotes / status changed"
  echo "meta-sync-rehearsal: $pass passed, $fail failed"
  [ "$fail" -eq 0 ] && exit 0; exit 1
}
skip() { local c; for c in "$@"; do res 1 "$c" "not reached: $SKIPWHY"; done; finish; }
ga() { git -C "$A" -c core.quotepath=off "$@"; }
scratch_cfg() { # identity, no hooks, no signing — local config of a scratch clone only
  git -C "$1" config user.name "meta-sync-rehearsal"; git -C "$1" config user.email "rehearsal@example.invalid"
  git -C "$1" config commit.gpgsign false; git -C "$1" config core.hooksPath "$S/nohooks"
}
LATE="init push verify-present verify-blobs verify-nothing-extra verify-types migrate-clean pull-roundtrip rollback-run rollback-edit-kept rollback-add-kept rollback-delete-kept rollback-all-kept rollback-gitignore twin-contracts"

# ---- scratch world: bare remote + clone A ---------------------------------------------------------
mkdir -p "$S/nohooks" "$S/bin"
git clone -q --bare --no-hardlinks --single-branch --branch "$DEF" "$ROOT" "$O" 2>"$S/err" || die "could not clone the checkout into the scratch bare repo: $(tail -n 1 "$S/err")"
git clone -q "$O" "$A" 2>"$S/err" || die "could not clone the scratch bare repo: $(tail -n 1 "$S/err")"
scratch_cfg "$A"
[ "$(ga remote)" = origin ] && [ "$(ga remote get-url origin)" = "$O" ]; res $? scratch-remote "remotes: $(ga remote -v | tr '\t\n' '  ')"

EXC="$(ga rev-parse --git-path info/exclude)"; case "$EXC" in /*) ;; *) EXC="$A/$EXC" ;; esac
SEXC="$(git -C "$ROOT" rev-parse --git-path info/exclude 2>/dev/null)"; case "$SEXC" in /*) ;; *) SEXC="$ROOT/$SEXC" ;; esac
mkdir -p "$(dirname "$EXC")"
{ [ -f "$SEXC" ] && cat "$SEXC"; printf '/.supervisor/migrate-branch-mode/\n/.gitignore.backup.*\n'; } >> "$EXC"

# untracked run history, the twin store and (unless --no-config) the configuration
bash "$MS" list-managed --root "$ROOT" > "$S/src.list" 2>"$S/err" || die "meta-sync.sh list-managed failed on the checkout: $(tail -n 1 "$S/err")"
while IFS= read -r p; do
  [ -n "$p" ] || continue
  ga ls-files --error-unmatch -- "$p" >/dev/null 2>&1 && continue
  mkdir -p "$(dirname "$A/$p")" && cp -p "$ROOT/$p" "$A/$p" || die "could not copy $p"
done < "$S/src.list"
[ -d "$ROOT/.supervisor/twin" ] && { mkdir -p "$A/.supervisor" && cp -R -p "$ROOT/.supervisor/twin" "$A/.supervisor/" || die "could not copy .supervisor/twin"; }
for p in .supervisor/config.json .agent/meta-sync-deny.txt; do
  if [ "$NOCFG" -eq 1 ]; then
    if ga ls-files --error-unmatch -- "$p" >/dev/null 2>&1; then ga rm -q -- "$p" || die "could not remove $p"; else rm -f "$A/$p"; fi
  elif [ -f "$ROOT/$p" ] && [ ! -e "$A/$p" ]; then
    mkdir -p "$(dirname "$A/$p")" && cp -p "$ROOT/$p" "$A/$p" || die "could not copy $p"
  fi
done
if [ -n "$(ga diff --cached --name-only)" ]; then
  ga commit -q -m "rehearsal: --no-config" && ga push -q origin "$DEF" || die "could not commit the --no-config removal in the scratch clone"
fi
n_md="$(bash "$MS" list-managed --root "$A" 2>/dev/null | grep -c '\.md$')"
if [ "${n_md:-0}" -lt 2 ]; then
  mkdir -p "$A/.supervisor/jobs/done"
  for i in 1 2; do printf '# rehearsal seed %s\n' "$i" > "$A/.supervisor/jobs/done/rehearsal-seed-$i.md"; printf '/.supervisor/jobs/done/rehearsal-seed-%s.md\n' "$i" >> "$EXC"; done
  echo "info: fewer than two managed .md files — added two synthetic ones under .supervisor/jobs/done/"
fi

# twin store, before
twin_verified() { (cd "$A" && bash "$RSC" 2>/dev/null) | grep -c '^### contract:'; }
twin_files() { ls "$A/.supervisor/twin/contracts"/*.md 2>/dev/null | wc -l | tr -d ' '; }
TV0="$(twin_verified)"; TF0="$(twin_files)"

MODE="$(bash "$SM" --root "$A" mode 2>/dev/null | head -n 1)"
[ "$MODE" = off ]; res $? scratch-mode-off "mode is '${MODE:-<empty>}' — already migrated or unreadable; nothing to rehearse"
[ "$MODE" = off ] || { SKIPWHY="mode is not off"; skip $LATE; }

# ---- init, push --------------------------------------------------------------------------------------
bash "$MS" init --branch "$B" --root "$A" > "$S/init.out" 2>&1
rc=$?; [ "$rc" -eq 0 ] && git --git-dir="$O" rev-parse -q --verify "refs/heads/$B" >/dev/null
res $? init "rc=$rc: $(tail -n 1 "$S/init.out")"
bash "$MS" push --branch "$B" --root "$A" > "$S/push.out" 2>&1
res $? push "$(grep -E 'scrub|meta_sync' "$S/push.out" | tail -n 3 | tr '\n' ' ')"

# ---- verify --------------------------------------------------------------------------------------
ga fetch -q origin "+refs/heads/$B:refs/remotes/origin/$B" 2>/dev/null
bash "$MS" list-managed --root "$A" 2>/dev/null | env LC_ALL=C sort > "$S/L.list"
ga ls-tree -r "refs/remotes/origin/$B" 2>/dev/null > "$S/R.ent"
cut -f2 "$S/R.ent" | env LC_ALL=C sort > "$S/R.list"
miss="$(env LC_ALL=C comm -23 "$S/L.list" "$S/R.list" | tr '\n' ' ')"
[ -s "$S/L.list" ] && [ -z "$miss" ]; res $? verify-present "missing on $B: ${miss:-<no managed files>}"
bad=""
while IFS="$(printf '\t')" read -r meta p; do
  [ -f "$A/$p" ] || continue
  [ "$(ga hash-object --no-filters -- "$A/$p")" = "$(printf '%s' "$meta" | awk '{print $3}')" ] || bad="$bad$p "
done < "$S/R.ent"
[ -s "$S/R.ent" ] && [ -z "$bad" ]; res $? verify-blobs "blob differs: ${bad:-<empty branch>}"
extra="$(env LC_ALL=C comm -13 "$S/L.list" "$S/R.list" | tr '\n' ' ')"
[ -z "$extra" ]; res $? verify-nothing-extra "not managed: $extra"
badt="$(awk -F'\t' '{ split($1, m, " "); if (m[1] != "100644" || m[2] != "blob" || $2 !~ /^\.supervisor\// || ($2 !~ /\.md$/ && $2 !~ /(^|\/)results\.jsonl$/)) print $1 " " $2 }' "$S/R.ent" | tr '\n' ' ')"
while IFS= read -r p; do { [ -f "$A/$p" ] && [ ! -L "$A/$p" ]; } || badt="${badt}local:$p "; done < "$S/L.list"
[ -z "$badt" ]; res $? verify-types "$badt"

# ---- scratch migration commit (on the scratch default branch; stands in for the owner's merge) -----
PRE="$(ga rev-parse HEAD)"
bash "$SM" --root "$A" apply --branch-mode "$B" > "$S/apply.out" 2>&1
rm -f "$A"/.gitignore.backup.*
bash "$MS" list-managed --tracked --root "$A" > "$S/T.list" 2>/dev/null
[ -s "$S/T.list" ] && { tr '\n' '\0' < "$S/T.list" | (cd "$A" && xargs -0 git rm -r -q --cached --); }
ga add -- .gitignore 2>/dev/null
ga commit -q -m "rehearsal: branch mode on $B (untrack run history)" >/dev/null 2>&1 && ga push -q origin "$DEF" 2>/dev/null
MIG="$(ga rev-parse HEAD)"
MODE="$(bash "$SM" --root "$A" mode 2>/dev/null | head -n 1)"; dirty="$(ga status --porcelain | tr '\n' ' ')"
[ "$MIG" != "$PRE" ] && [ "$MODE" = "on $B" ] && [ -z "$dirty" ] && [ "$(git --git-dir="$O" rev-parse "refs/heads/$DEF")" = "$MIG" ]
res $? migrate-clean "mode '$MODE'; porcelain: ${dirty:-empty}; $(grep -E '^ *apply:' "$S/apply.out" | head -n 1)"

# ---- second checkout: pull round trip ------------------------------------------------------------
git clone -q "$O" "$C" 2>/dev/null && scratch_cfg "$C"
bash "$MS" pull --branch "$B" --root "$C" > "$S/pull.out" 2>&1; prc=$?
bash "$MS" list-managed --root "$C" 2>/dev/null | env LC_ALL=C sort > "$S/C.list"
diffp=""
while IFS= read -r p; do cmp -s "$A/$p" "$C/$p" || diffp="$diffp$p "; done < "$S/L.list"
[ "$prc" -eq 0 ] && cmp -s "$S/L.list" "$S/C.list" && [ -z "$diffp" ]
res $? pull-roundtrip "rc=$prc; differs: ${diffp:-none}; lists $(cmp -s "$S/L.list" "$S/C.list" && echo equal || echo differ)"

# ---- post-migration edit / add / delete, then the SHIPPED rollback --------------------------------
E="$(grep '\.md$' "$S/L.list" | head -n 1)"; D="$(grep '\.md$' "$S/L.list" | grep -vxF "$E" | tail -n 1)"
N=".supervisor/jobs/done/rehearsal-post-migration-add.md"; i=2
while [ -e "$A/$N" ]; do N=".supervisor/jobs/done/rehearsal-post-migration-add-$i.md"; i=$((i+1)); done
printf '\nrehearsal post-migration edit\n' >> "$A/$E"; cp "$A/$E" "$S/E.expect"
mkdir -p "$A/.supervisor/jobs/done"; printf '# rehearsal post-migration add\n' > "$A/$N"; cp "$A/$N" "$S/N.expect"
rm -f "$A/$D"

cat > "$S/bin/gh" <<'STUB'
#!/bin/bash
echo "$*" >> "$REHEARSAL_GH_LOG"
case "$1 $2" in "pr create") echo "https://example.invalid/rehearsal/scratch/pull/1"; exit 0 ;; esac
echo "gh stub: refused: $*" >&2; exit 1
STUB
chmod +x "$S/bin/gh"; : > "$S/gh.log"
mkdir -p "$A/.supervisor/migrate-branch-mode"
printf 'branch=%s\ndefault=%s\n' "$B" "$DEF" > "$A/.supervisor/migrate-branch-mode/state"
REHEARSAL_GH_LOG="$S/gh.log" LOOMWRIGHT_GH_BIN="$S/bin/gh" PATH="$S/bin:$PATH" \
  bash "$MB" rollback --commit "$MIG" --root "$A" > "$S/rollback.out" 2>&1; rrc=$?
RB="$(sed -n 's/^rollback_branch=//p' "$A/.supervisor/migrate-branch-mode/state" | tail -n 1)"
[ "$rrc" -eq 0 ] && [ -n "$RB" ] && git --git-dir="$O" rev-parse -q --verify "refs/heads/$RB" >/dev/null \
  && [ "$(git --git-dir="$O" rev-parse "refs/heads/$DEF")" = "$MIG" ] && grep -q '^pr create' "$S/gh.log" && ! grep -q 'merge' "$S/gh.log"
res $? rollback-run "rc=$rrc: $(tail -n 2 "$S/rollback.out" | tr '\n' ' ')"
RT="refs/remotes/origin/$RB"; ga fetch -q origin "+refs/heads/$RB:$RT" 2>/dev/null || RT="$RB"
blob_eq() { ga cat-file -e "$RT:$1" 2>/dev/null && ga show "$RT:$1" | cmp -s - "$2"; }
blob_eq "$E" "$S/E.expect"; res $? rollback-edit-kept "$E"
blob_eq "$N" "$S/N.expect"; res $? rollback-add-kept "$N"
[ -n "$RB" ] && ! ga cat-file -e "$RT:$D" 2>/dev/null; res $? rollback-delete-kept "$D"
ga fetch -q origin "+refs/heads/$B:refs/remotes/origin/$B" 2>/dev/null
lost=""
while IFS="$(printf '\t')" read -r meta p; do
  [ "$(ga rev-parse -q --verify "$RT:$p" 2>/dev/null)" = "$(printf '%s' "$meta" | awk '{print $3}')" ] || lost="$lost$p "
done < <(ga ls-tree -r "refs/remotes/origin/$B" 2>/dev/null)
[ -n "$RB" ] && [ -z "$lost" ]; res $? rollback-all-kept "not at branch bytes: ${lost:-<no rollback branch>}"
[ -n "$RB" ] && [ "$(ga show "$RT:.gitignore" 2>/dev/null)" = "$(ga show "$PRE:.gitignore" 2>/dev/null)" ]; res $? rollback-gitignore

# ---- twin reader contract count after the round trip --------------------------------------------
TV1="$(twin_verified)"; TF1="$(twin_files)"
[ "$TV1" = "$TV0" ] && [ "$TF1" = "$TF0" ] && [ "$TV1" = "$TF1" ]
res $? twin-contracts "verified $TV0 -> $TV1 of $TF0 -> $TF1 contract file(s)"
[ "$TF1" = 0 ] && echo "info: the checkout has no System Twin contracts — twin-contracts compared 0 = 0"

finish
