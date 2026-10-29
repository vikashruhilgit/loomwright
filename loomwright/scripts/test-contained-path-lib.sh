#!/usr/bin/env bash
# test-contained-path-lib.sh — self-test for contained-path-lib.sh (cpl_phys / cpl_inside /
# cpl_check_write), the physical-path containment every repo-relative config writer calls.
#
# Runs in mktemp -d fixtures only, HOME relocated, library SOURCED into this shell so CPL_REASON
# (a global) can be read after a refusal. Cases:
#   phys_*    existing file, relative input refused, missing file, missing parent dirs (nearest
#             existing ancestor re-appended), `.`/`..` tail refused, relative symlinks (leaf and
#             parent), a dangling parent symlink refused, 40-hop chain resolved / 41-hop refused
#   inside_*  inside / outside / the root itself; a walk that exhausts its cap fails CLOSED
#   check_*   allowed (silent, rc 0), leaf symlink ⇒ `symlink` or the caller's reason, symlinked
#             parent outside ⇒ path_outside_repo (headline, CPL_REASON), inside-pointing symlink
#             allowed, repo reached through a symlinked ancestor allowed, /tmp vs /private/tmp
#             (macOS only; a named skip elsewhere), relative target and root resolved against $PWD,
#             dangling parent and empty target refused
# Mutation controls (gated: non-empty + differs + bash -n, on a scratch copy of the library): the
# hop cap raised to 99 (the 41-hop case must go red), the leaf test pointed at a nonexistent path
# (the leaf-symlink case must go red), the cap's fail-closed return flipped to 0 (the capped-walk
# case must go red).
# Exit 0 = all pass, 1 = any failure, 2 = fixture setup broken.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE/contained-path-lib.sh"

pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; return 0; }
setup_fail() { printf 'SETUP FAILED: %s\n' "$1" >&2; exit 2; }
has() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

[ -r "$LIB" ] || setup_fail "library not readable: $LIB"
T="$(mktemp -d)" || setup_fail "mktemp -d failed"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME" || setup_fail "mkdir HOME"
# Physical spelling of the fixture root (macOS: /var -> /private/var).
TP="$(CDPATH='' cd -P -- "$T" && pwd -P)" || setup_fail "cd -P fixture root"

# ---- fixture ----------------------------------------------------------------------------------
REPO="$TP/repo"; OUT="$TP/outside"
mkdir -p "$REPO/real-dir" "$OUT" || setup_fail "mkdir fixture"
printf '{"keep":1}\n' > "$OUT/config.json"
printf 'x\n' > "$REPO/real-dir/file"

run_suite() {
  # run_suite <library path> — sources the library into THIS shell and runs the case functions
  # selected by $CASES (default: all). The mutation controls call it with a scratch copy.
  # shellcheck disable=SC1090
  . "$1" || setup_fail "cannot source $1"

  local fn
  for fn in $CASES; do "$fn"; done
}

# ---- cpl_phys ---------------------------------------------------------------------------------
phys_existing() {
  local got; got="$(cpl_phys "$REPO/real-dir/file")"
  [ "$got" = "$REPO/real-dir/file" ] && ok "phys: existing file prints its physical path" \
    || no "phys: existing file" "got '$got'"
}
phys_relative_refused() {
  if cpl_phys "real-dir/file" >/dev/null 2>&1; then no "phys: a relative path must fail"; else ok "phys: a relative path fails"; fi
}
phys_missing_file() {
  local got; got="$(cpl_phys "$REPO/real-dir/missing.json")"
  [ "$got" = "$REPO/real-dir/missing.json" ] && ok "phys: missing file in an existing dir" \
    || no "phys: missing file" "got '$got'"
}
phys_missing_parents() {
  local got; got="$(cpl_phys "$REPO/a/b/c.json")"
  [ "$got" = "$REPO/a/b/c.json" ] && ok "phys: missing parent dirs re-append to the nearest existing ancestor" \
    || no "phys: missing parents" "got '$got'"
}
phys_dot_tail_refused() {
  if cpl_phys "$REPO/missing/." >/dev/null 2>&1 || cpl_phys "$REPO/missing/../x" >/dev/null 2>&1 \
     || cpl_phys "$REPO/missing/./x" >/dev/null 2>&1; then
    no "phys: a '.'/'..' component in the missing tail must fail"
  else ok "phys: a '.'/'..' component in the missing tail fails"; fi
}
phys_relative_leaf_link() {
  ln -sfn "real-dir/file" "$REPO/rel-leaf" || return 0
  local got; got="$(cpl_phys "$REPO/rel-leaf")"
  [ "$got" = "$REPO/real-dir/file" ] && ok "phys: relative leaf symlink is followed" \
    || no "phys: relative leaf symlink" "got '$got'"
}
phys_relative_parent_link() {
  ln -sfn "real-dir" "$REPO/rel-parent" || return 0
  local got; got="$(cpl_phys "$REPO/rel-parent/new.json")"
  [ "$got" = "$REPO/real-dir/new.json" ] && ok "phys: relative parent symlink + missing leaf resolves under the target" \
    || no "phys: relative parent symlink" "got '$got'"
}
phys_dangling_parent_refused() {
  ln -sfn "$TP/does-not-exist" "$REPO/dangling" || return 0
  if cpl_phys "$REPO/dangling/config.json" >/dev/null 2>&1 || cpl_phys "$REPO/dangling/sub/config.json" >/dev/null 2>&1; then
    no "phys: a dangling parent symlink must fail"
  else ok "phys: a dangling parent symlink fails (never falls through to an existing ancestor)"; fi
}
phys_hop_cap() {
  local i prev="$REPO/real-dir/file"
  mkdir -p "$TP/chain"
  for i in $(seq 1 41); do ln -sfn "$prev" "$TP/chain/l$i"; prev="$TP/chain/l$i"; done
  if cpl_phys "$TP/chain/l40" >/dev/null 2>&1; then ok "phys: a 40-hop chain resolves"; else no "phys: a 40-hop chain should resolve"; fi
  if cpl_phys "$TP/chain/l41" >/dev/null 2>&1; then no "phys: a 41-hop chain must be refused"; else ok "phys: a 41-hop chain is refused"; fi
}

# ---- cpl_inside -------------------------------------------------------------------------------
inside_basic() {
  if cpl_inside "$REPO/real-dir/file" "$REPO"; then ok "inside: a path under the root"; else no "inside: under the root"; fi
  if cpl_inside "$REPO/x.json" "$REPO"; then ok "inside: a path whose directory is the root"; else no "inside: directory is the root"; fi
  if cpl_inside "$OUT/config.json" "$REPO"; then no "inside: a path outside the root must fail"; else ok "inside: a path outside the root fails"; fi
}
inside_cap_fails_closed() {
  # A path 300 components deep: the walk toward a root that IS an ancestor exhausts its 256-step
  # cap before arriving. The cap must answer "outside" (1), the inverse of the merge executor's.
  local deep="" i
  for i in $(seq 1 300); do deep="$deep/a"; done
  if cpl_inside "$deep/x" "/"; then no "inside: an exhausted cap must fail closed (returned inside)"
  else ok "inside: an exhausted 256-step cap fails closed"; fi
}

# ---- cpl_check_write --------------------------------------------------------------------------
# chk <label> <target> <root> [<reason>] — runs in THIS shell; sets CK_RC, CK_OUT, CK_REASON.
chk() {
  CK_OUT=""; CK_RC=0
  cpl_check_write "$@" > "$T/ck.out" 2>&1 || CK_RC=$?
  CK_REASON="$CPL_REASON"; CK_OUT="$(cat "$T/ck.out")"
}
check_allowed() {
  chk t "$REPO/real-dir/new.json" "$REPO"
  { [ "$CK_RC" = 0 ] && [ -z "$CK_OUT" ] && [ -z "$CK_REASON" ]; } && ok "check: an inside target is allowed, silently, CPL_REASON empty" \
    || no "check: inside target" "rc=$CK_RC out='$CK_OUT' reason='$CK_REASON'"
  chk t "$REPO/not/yet/there.json" "$REPO"
  [ "$CK_RC" = 0 ] && ok "check: a missing parent chain inside the repo is allowed" || no "check: missing parent chain" "rc=$CK_RC $CK_OUT"
}
check_leaf_symlink() {
  ln -sfn "$REPO/real-dir/file" "$REPO/leaf-in" || return 0
  chk lbl "$REPO/leaf-in" "$REPO"
  { [ "$CK_RC" = 1 ] && [ "$CK_REASON" = symlink ] && has "$CK_OUT" "lbl: ABORTED (symlink) — " && has "$CK_OUT" "Nothing was written."; } \
    && ok "check: a leaf symlink (even to an inside target) ⇒ reason symlink" || no "check: leaf symlink" "rc=$CK_RC reason='$CK_REASON' out='$CK_OUT'"
  chk lbl "$REPO/leaf-in" "$REPO" config_symlink
  { [ "$CK_RC" = 1 ] && [ "$CK_REASON" = config_symlink ] && has "$CK_OUT" "lbl: ABORTED (config_symlink) — "; } \
    && ok "check: a leaf symlink with a caller reason ⇒ that reason" || no "check: custom leaf reason" "rc=$CK_RC reason='$CK_REASON' out='$CK_OUT'"
  [ "$(printf '%s\n' "$CK_OUT" | wc -l | tr -d ' ')" = 1 ] && ok "check: the refusal is ONE headline line" || no "check: headline is not one line" "$CK_OUT"
}
check_parent_outside() {
  ln -sfn "$OUT" "$REPO/sup-out" || return 0
  local before after; before="$(ls -A "$OUT"; cksum < "$OUT/config.json")"
  chk lbl "$REPO/sup-out/config.json" "$REPO"
  { [ "$CK_RC" = 1 ] && [ "$CK_REASON" = path_outside_repo ] && has "$CK_OUT" "lbl: ABORTED (path_outside_repo) — " && has "$CK_OUT" "Nothing was written."; } \
    && ok "check: a symlinked parent pointing outside ⇒ path_outside_repo" || no "check: symlinked parent outside" "rc=$CK_RC reason='$CK_REASON' out='$CK_OUT'"
  chk lbl "$REPO/sup-out/new.json" "$REPO" config_symlink
  { [ "$CK_RC" = 1 ] && [ "$CK_REASON" = path_outside_repo ]; } \
    && ok "check: ... also when the leaf does not exist yet (and a caller leaf reason does not leak)" || no "check: outside, missing leaf" "reason='$CK_REASON'"
  after="$(ls -A "$OUT"; cksum < "$OUT/config.json")"
  [ "$before" = "$after" ] && ok "check: the checker itself never touches the outside folder" || no "check: outside folder changed"
}
check_parent_inside_link() {
  ln -sfn "./real-dir" "$REPO/sup-in" || return 0
  chk lbl "$REPO/sup-in/config.json" "$REPO"
  [ "$CK_RC" = 0 ] && ok "check: a parent symlink pointing back inside the repo is allowed" || no "check: inside-pointing parent" "rc=$CK_RC $CK_OUT"
}
check_symlinked_ancestor() {
  mkdir -p "$TP/realparent/repo2/real-sup"; ln -sfn "$TP/realparent" "$TP/parentlink"
  ln -sfn "real-sup" "$TP/realparent/repo2/.sup"
  chk lbl "$TP/parentlink/repo2/.sup/config.json" "$TP/parentlink/repo2"
  [ "$CK_RC" = 0 ] && ok "check: a repo reached through a symlinked ancestor is allowed" || no "check: symlinked ancestor" "rc=$CK_RC $CK_OUT"
  chk lbl "$TP/realparent/repo2/.sup/config.json" "$TP/parentlink/repo2"
  [ "$CK_RC" = 0 ] && ok "check: ... target and root may spell the same repo differently" || no "check: mixed spellings" "rc=$CK_RC $CK_OUT"
}
check_tmp_alias() {
  if [ -L /tmp ] && [ -d /private/tmp ]; then
    local d; d="$(mktemp -d /tmp/cpl-test.XXXXXX)" || { no "check: mktemp under /tmp"; return 0; }
    mkdir -p "$d/repo"
    chk lbl "$d/repo/config.json" "/private$d/repo"
    [ "$CK_RC" = 0 ] && ok "check: /tmp vs /private/tmp spellings are the same repo" || no "check: /tmp alias" "rc=$CK_RC $CK_OUT"
    rm -rf "$d"
  else
    printf '  skip check: /tmp vs /private/tmp — /tmp is not a symlink on this platform (macOS-only case)\n'
  fi
}
check_relative_paths() {
  mkdir -p "$TP/relrepo/sup"; ln -sfn "$OUT" "$TP/relrepo/sup-out"
  local here="$PWD"; cd "$TP/relrepo" || return 0
  chk lbl "sup/config.json" "."
  [ "$CK_RC" = 0 ] && ok "check: a relative target and relative root resolve against \$PWD (inside ⇒ allowed)" || no "check: relative inside" "rc=$CK_RC $CK_OUT"
  chk lbl "sup-out/config.json" "."
  { [ "$CK_RC" = 1 ] && [ "$CK_REASON" = path_outside_repo ]; } && ok "check: a relative symlinked parent outside ⇒ path_outside_repo" || no "check: relative outside" "rc=$CK_RC $CK_OUT"
  cd "$here" || true
}
check_unresolvable() {
  chk lbl "$REPO/dangling/config.json" "$REPO"
  { [ "$CK_RC" = 1 ] && [ "$CK_REASON" = path_outside_repo ]; } && ok "check: a dangling parent symlink is refused (unresolvable ⇒ refuse)" || no "check: dangling parent" "rc=$CK_RC reason='$CK_REASON'"
  chk lbl "" "$REPO"
  { [ "$CK_RC" = 1 ] && [ "$CK_REASON" = path_outside_repo ]; } && ok "check: an empty target is refused" || no "check: empty target" "rc=$CK_RC"
  chk lbl "$REPO/x.json" "$TP/no/such/root"
  { [ "$CK_RC" = 1 ] && [ "$CK_REASON" = path_outside_repo ]; } && ok "check: a root that does not exist refuses (nothing can be inside it)" || no "check: missing root" "rc=$CK_RC reason='$CK_REASON'"
}
check_reason_reset() {
  chk lbl "$REPO/sup-out/config.json" "$REPO"
  chk lbl "$REPO/real-dir/new.json" "$REPO"
  { [ "$CK_RC" = 0 ] && [ -z "$CK_REASON" ]; } && ok "check: CPL_REASON is cleared by a following allowed call" || no "check: stale CPL_REASON" "reason='$CK_REASON'"
}

CASES="phys_existing phys_relative_refused phys_missing_file phys_missing_parents phys_dot_tail_refused \
phys_relative_leaf_link phys_relative_parent_link phys_dangling_parent_refused phys_hop_cap \
inside_basic inside_cap_fails_closed \
check_allowed check_leaf_symlink check_parent_outside check_parent_inside_link check_symlinked_ancestor \
check_tmp_alias check_relative_paths check_unresolvable check_reason_reset"
echo "== contained-path-lib =="
run_suite "$LIB"

# ---- mutation controls ------------------------------------------------------------------------
# mutant <name> <sed expression> <case function...> — a scratch copy of the library with one
# line flipped; gated; the named cases are re-run against it in a SUBSHELL and at least one
# assertion must fail there (the subshell reports its failure count through its exit code).
mutant() {
  local name="$1" expr="$2" cases="$3" m="$T/mut-$1.sh" rc
  sed "$expr" "$LIB" > "$m" 2>/dev/null
  if [ ! -s "$m" ] || cmp -s "$m" "$LIB" || ! bash -n "$m" 2>/dev/null; then
    no "MUTATION CONTROL $name: mutant is empty, identical or does not parse — control inconclusive"; return 0
  fi
  rc=0
  ( pass=0; fail=0; ok() { :; }; no() { fail=$((fail+1)); }
    CASES="$cases"; run_suite "$m" >/dev/null 2>&1; exit "$fail" ) || rc=$?
  if [ "$rc" -gt 0 ]; then ok "MUTATION CONTROL $name: [$cases] is red against the mutant"
  else no "MUTATION CONTROL $name: [$cases] still PASSES against the mutant"; fi
}
echo "== mutation controls =="
mutant hop-cap-99 's/\[ "\$n" -le 40 \]/[ "$n" -le 99 ]/' "phys_hop_cap"
mutant leaf-test-neutralised 's|\[ -L "\$2" \]|[ -L "/nonexistent-cpl" ]|' "check_leaf_symlink"
mutant cap-fails-open '/n=\$((n + 1)); \[ "\$n" -le 256 \] || return 1/ s/return 1/return 0/' "inside_cap_fails_closed"

echo
printf 'contained-path-lib: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
