#!/usr/bin/env bash
# test-propose-common.sh - self-tests for propose-common.sh's pc_guarded_write(), the ONE
# blast-radius guard shared by all three `/propose` bases (propose-work.sh, propose-domain.sh,
# propose-from-verify.sh). Each caller's own self-test (test-propose-work.sh AC8,
# test-propose-domain.sh AC10) already exercises the guard THROUGH that caller's business logic
# (a hostile class/slug name), but neither one calls pc_guarded_write directly, so a defect
# reachable only via an input shape none of the three callers happens to construct (a bare
# symlink at a legal name, say) could ship uncaught. This file calls pc_guarded_write() itself,
# directly, with no caller in between.
#
# HERMETIC BY CONSTRUCTION: every fixture lives under a mktemp -d tree OUTSIDE the repo root.
# Nothing here depends on `.supervisor/` or any other runtime state existing.
#
# Cases:
#   AC1  a plain, legal name writes successfully and returns 0.
#   AC2  a pre-existing SYMLINK at the target name is refused (return 1, named on stderr) and the
#        symlink's target (outside the output dir) is left byte-unchanged - the write must not
#        follow the link.
#   AC3  a path-traversal name (`../evil.md`) is refused (return 1, named on stderr) and nothing
#        is created outside the output directory.
#   AC4  MUTATION CONTROL: with the guard's marked block sed-deleted out of a COPY of
#        propose-common.sh, the SAME traversal name from AC3 escapes the output directory - the
#        guard being deleted is observable, not merely assumed.
#
# Exit 0 = all pass, 1 = any failure. Registered automatically by ci.yml's test-*.sh glob.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/propose-common.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

[ -f "$SUT" ] || { echo "FATAL: required script missing: $SUT"; exit 1; }

ROOT="$(mktemp -d)"
trap 'chmod -R u+rwX "$ROOT" >/dev/null 2>&1; rm -rf "$ROOT" 2>/dev/null' EXIT
mktmp() { mktemp -d "$ROOT/d.XXXXXX"; }

# call_guard <sut> <out_dir_abs> <name> <content> - sources <sut>, calls pc_guarded_write with
# <content> on stdin, prints "<rc>" on its own last line of stdout is NOT relied on; instead this
# writes rc to $ROOT/rc and stderr to $ROOT/err, both read by the caller. A SEPARATE bash
# invocation per call, so sourcing one mutant never contaminates a later, intact call in the same
# process.
call_guard() {
  cg_sut="$1"; cg_out="$2"; cg_name="$3"; cg_content="$4"
  printf '%s' "$cg_content" | bash -c '
    . "$1"
    pc_guarded_write "$2" "test-propose-common" "$3"
  ' _ "$cg_sut" "$cg_out" "$cg_name" >"$ROOT/out.log" 2>"$ROOT/err.log"
  printf '%s' "$?" > "$ROOT/rc"
}

# ---------------------------------------------------------------------------
echo "== AC1: a plain, legal name writes successfully =="
A1="$(mktmp)/out"; mkdir -p "$A1"; A1_ABS="$(cd "$A1" && pwd)"
call_guard "$SUT" "$A1_ABS" "candidate.md" "hello world"
rc1="$(cat "$ROOT/rc")"
[ "$rc1" -eq 0 ] && ok "AC1: pc_guarded_write returns 0 on a legal plain name" || no "AC1: rc=$rc1 err=$(cat "$ROOT/err.log")"
[ -f "$A1_ABS/candidate.md" ] && ok "AC1: the file exists at the expected path" || no "AC1: candidate.md was not written"
[ "$(cat "$A1_ABS/candidate.md" 2>/dev/null)" = "hello world" ] && ok "AC1: the content round-trips byte-for-byte" || no "AC1: content mismatch"
tmp_left="$(find "$A1_ABS" -maxdepth 1 -name '.tmp.*' 2>/dev/null | wc -l | tr -d ' ')"
[ "$tmp_left" -eq 0 ] && ok "AC1: no staged temp entry survives" || no "AC1: $tmp_left staged temp entr(y/ies) left behind"

# ---------------------------------------------------------------------------
echo "== AC2: a pre-existing SYMLINK at the target name is refused, target left byte-unchanged =="
A2="$(mktmp)/out"; mkdir -p "$A2"; A2_ABS="$(cd "$A2" && pwd)"
A2_VICTIM="$(mktmp)/victim.md"; printf 'original victim content\n' > "$A2_VICTIM"
before2="$(wc -c < "$A2_VICTIM" | tr -d ' ')"
ln -s "$A2_VICTIM" "$A2_ABS/hostile.md" 2>/dev/null
[ -L "$A2_ABS/hostile.md" ] && ok "AC2: planted a symlink at the target name, pointing outside the output dir" \
  || no "AC2: could not plant the symlink - this control is inconclusive"
call_guard "$SUT" "$A2_ABS" "hostile.md" "attacker-controlled content"
rc2="$(cat "$ROOT/rc")"
[ "$rc2" -eq 1 ] && ok "AC2: pc_guarded_write refuses (rc=1) rather than writing through the symlink" || no "AC2: rc=$rc2 (expected 1)"
grep -Fq 'it is a symlink' "$ROOT/err.log" 2>/dev/null && ok "AC2: the refusal is NAMED as a symlink on stderr" \
  || no "AC2: refusal reason not named: $(cat "$ROOT/err.log")"
after2="$(wc -c < "$A2_VICTIM" | tr -d ' ')"
[ "$after2" = "$before2" ] && ok "AC2: the symlink's target is BYTE-UNCHANGED ($after2 bytes)" \
  || no "AC2: the target was written through: $before2 -> $after2 bytes"
[ -L "$A2_ABS/hostile.md" ] && ok "AC2: the symlink itself is still in place (not unlinked, not replaced)" \
  || no "AC2: the symlink at the target name is gone or replaced"

# ---------------------------------------------------------------------------
echo "== AC3: a path-traversal name is refused, nothing is created outside the output dir =="
A3="$(mktmp)/out"; mkdir -p "$A3"; A3_ABS="$(cd "$A3" && pwd)"
A3_ESCAPE="$(dirname "$A3_ABS")/evil.md"
rm -f "$A3_ESCAPE" 2>/dev/null
call_guard "$SUT" "$A3_ABS" "../evil.md" "path traversal payload"
rc3="$(cat "$ROOT/rc")"
[ "$rc3" -eq 1 ] && ok "AC3: pc_guarded_write refuses (rc=1) a '../evil.md' name" || no "AC3: rc=$rc3 (expected 1)"
grep -Fq "not a plain file name" "$ROOT/err.log" 2>/dev/null && ok "AC3: the refusal is NAMED as not-a-plain-file-name on stderr" \
  || no "AC3: refusal reason not named: $(cat "$ROOT/err.log")"
[ ! -e "$A3_ESCAPE" ] && ok "AC3: nothing was created at the escape path outside the output dir" \
  || no "AC3: a file WAS created outside the output dir at $A3_ESCAPE"
n3="$(find "$A3_ABS" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"
[ "$n3" -eq 0 ] && ok "AC3: nothing was created inside the output dir either" || no "AC3: $n3 unexpected file(s) inside the output dir"

# ---------------------------------------------------------------------------
echo "-- MUTATION CONTROL (AC4): sed-delete the guard block from a COPY of propose-common.sh, and the SAME traversal name from AC3 must escape --"
MUT="$ROOT/mutant-noguard-common.sh"
sed '/>>> WRITE-PATH GUARD/,/<<< END WRITE-PATH GUARD/d' "$SUT" > "$MUT" 2>/dev/null
if [ -s "$MUT" ] && ! cmp -s "$MUT" "$SUT" && bash -n "$MUT" 2>/dev/null; then
  ok "AC4: built a syntactically valid mutant propose-common.sh with the write-path guard deleted"
  A4="$(mktmp)/out"; mkdir -p "$A4"; A4_ABS="$(cd "$A4" && pwd)"
  A4_ESCAPE="$(dirname "$A4_ABS")/evil.md"
  rm -f "$A4_ESCAPE" 2>/dev/null
  call_guard "$MUT" "$A4_ABS" "../evil.md" "path traversal payload"
  rc4="$(cat "$ROOT/rc")"
  if [ -f "$A4_ESCAPE" ]; then
    ok "AC4: MUTATION CONTROL - without the guard, '../evil.md' escapes the output dir (mutant rc=$rc4) - AC3 turns RED against this mutant"
    [ "$(cat "$A4_ESCAPE" 2>/dev/null)" = "path traversal payload" ] \
      && ok "AC4: the escaped file carries the exact payload content, proving a real write and not a coincidental pre-existing file" \
      || no "AC4: a file exists at the escape path but its content does not match the payload - inconclusive"
    rm -f "$A4_ESCAPE" 2>/dev/null
  else
    no "AC4: the guard-deleted mutant still refused the traversal name (rc=$rc4) - AC3's mutation control is uncontrolled"
  fi
else
  no "AC4: could not build a valid write-guard mutant - the mutation control is uncontrolled"
fi

# ---------------------------------------------------------------------------
echo
echo "propose-common: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
