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
#   AC5  SIZE LINE (parallel-automate/18b): a `*.md` written under a tree holding `.supervisor/`
#        prints exactly one `automate-helpers.sh right-size` line on STDERR; rc 0, stdout empty,
#        the written bytes unchanged.
#   AC6  no size line for `README.md`, a `_*` name, a non-`*.md` name, or an output dir with no
#        `.supervisor/` above it - each still written, rc 0.
#   AC7  a FAILING right-size (stub dispatcher, exit 1 with output on both streams) prints
#        nothing and the write still returns 0; a stub that exits 0 shows its line (the control
#        that keeps the failing leg live).
#   AC8  an ABSENT right-size (a copy of propose-common.sh with no sibling dispatcher) prints
#        nothing and the write still returns 0.
#   AC9  MUTATION CONTROLS on the ONE call line after the `mv -f`, each in a copy beside symlinks
#        to the real dispatcher: deleting it loses the stderr line (AC5 turns red); dropping its
#        `>&2` puts the line on stdout (AC5's stdout-empty assertion turns red).
#
# Exit 0 = all pass, 1 = any failure. Registered automatically by ci.yml's test-*.sh glob.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
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
# Size-line fixtures. sz_tree builds a checkout-shaped tree (`.supervisor/requirements/proposed/`
# plus one real file the draft's Touches names), so right-size reads `small (1 files, …)`.
# sz_dir <label> [<sed-expr>] copies propose-common.sh (optionally mutated) into its own dir beside
# symlinks to the REAL dispatcher and its families, so the copy's sibling lookup finds right-size.
SZ_DRAFT="$(printf '# Size fixture\n\n## Status: proposed\n\n## Depends on\nnone\n\n## Touches\nsrc/a.sh\n\n## Scope\n- one thing\n')"
sz_tree() {
  st_t="$(mktmp)"; mkdir -p "$st_t/.supervisor/requirements/proposed" "$st_t/src"; : > "$st_t/src/a.sh"
  (cd "$st_t/.supervisor/requirements/proposed" && pwd)
}
sz_dir() {
  sd_d="$(mktmp)/$1"; mkdir -p "$sd_d"
  if [ -n "${2:-}" ]; then sed "$2" "$SUT" > "$sd_d/propose-common.sh"; else cp "$SUT" "$sd_d/propose-common.sh"; fi
  ln -s "$HERE/automate-helpers.sh" "$sd_d/automate-helpers.sh"
  ln -s "$HERE/automate-helpers.d" "$sd_d/automate-helpers.d"
  printf '%s' "$sd_d"
}
SZ_WANT="proposed/cand: small (1 files, 1 scope items, 0 criteria) — merge candidates: none"
# sz_check <label> <out_dir_abs> <name> - rc 0, stdout empty, bytes unchanged (shared by every leg).
sz_check() {
  [ "$(cat "$ROOT/rc")" -eq 0 ] && ok "$1: rc 0" || no "$1: rc=$(cat "$ROOT/rc") err=$(cat "$ROOT/err.log")"
  [ ! -s "$ROOT/out.log" ] && ok "$1: stdout empty" || no "$1: stdout not empty: $(cat "$ROOT/out.log")"
  [ "$(cat "$2/$3" 2>/dev/null)" = "$SZ_DRAFT" ] && ok "$1: the written bytes are unchanged" || no "$1: content of $3 differs"
}

echo "== AC5: a *.md draft under a .supervisor/ tree gets ONE right-size line on stderr =="
A5="$(sz_tree)"
call_guard "$SUT" "$A5" "cand.md" "$SZ_DRAFT"
sz_check "AC5" "$A5" "cand.md"
[ "$(cat "$ROOT/err.log")" = "$SZ_WANT" ] && ok "AC5: stderr is exactly the one right-size line ($SZ_WANT)" \
  || no "AC5: stderr: $(cat "$ROOT/err.log")"

echo "== AC6: README.md, _* names, non-*.md names and a tree with no .supervisor/ print no size line =="
A6="$(sz_tree)"
for n in README.md _notes.md cand.txt; do
  call_guard "$SUT" "$A6" "$n" "$SZ_DRAFT"
  sz_check "AC6 $n" "$A6" "$n"
  [ ! -s "$ROOT/err.log" ] && ok "AC6 $n: no size line" || no "AC6 $n: stderr: $(cat "$ROOT/err.log")"
done
A6N="$(mktmp)/out"; mkdir -p "$A6N"; A6N="$(cd "$A6N" && pwd)"
call_guard "$SUT" "$A6N" "cand.md" "$SZ_DRAFT"
sz_check "AC6 no .supervisor/" "$A6N" "cand.md"
# The walk is unbounded by design, so a `.supervisor/` some other process left in an ANCESTOR of
# the temp dir (e.g. $TMPDIR itself) is a legitimate root; the no-root leg is then inconclusive here.
a6_anc="$A6N"; a6_hit=""
while [ "$a6_anc" != / ]; do [ -d "$a6_anc/.supervisor" ] && { a6_hit="$a6_anc"; break; }; a6_anc="$(dirname "$a6_anc")"; done
if [ -n "$a6_hit" ]; then
  ok "AC6 no-root leg inconclusive on this host: ancestor $a6_hit holds .supervisor/ (the walk correctly found it)"
else
  [ ! -s "$ROOT/err.log" ] && ok "AC6 no .supervisor/ above the output dir: the line is skipped silently" || no "AC6 no-root stderr: $(cat "$ROOT/err.log")"
fi

echo "== AC7: a FAILING right-size prints nothing; the write still returns 0 =="
A7D="$(mktmp)/stub"; mkdir -p "$A7D"; cp "$SUT" "$A7D/propose-common.sh"
printf '#!/usr/bin/env bash\necho "STUB-OUT $*"\necho "STUB-ERR" >&2\nexit 1\n' > "$A7D/automate-helpers.sh"
A7="$(sz_tree)"
call_guard "$A7D/propose-common.sh" "$A7" "cand.md" "$SZ_DRAFT"
sz_check "AC7 failing" "$A7" "cand.md"
[ ! -s "$ROOT/err.log" ] && ok "AC7: right-size exit 1 (output on both streams) prints nothing" || no "AC7 failing stderr: $(cat "$ROOT/err.log")"
printf '#!/usr/bin/env bash\nexit 0\n' > "$A7D/automate-helpers.sh"
call_guard "$A7D/propose-common.sh" "$A7" "cand.md" "$SZ_DRAFT"
sz_check "AC7 empty" "$A7" "cand.md"
[ ! -s "$ROOT/err.log" ] && ok "AC7: right-size exit 0 with no output prints nothing (no blank line)" || no "AC7 empty-output stderr: $(od -c < "$ROOT/err.log" | head -2)"
printf '#!/usr/bin/env bash\necho "STUB-OUT $1"\n' > "$A7D/automate-helpers.sh"
call_guard "$A7D/propose-common.sh" "$A7" "cand.md" "$SZ_DRAFT"
sz_check "AC7 control" "$A7" "cand.md"
[ "$(cat "$ROOT/err.log")" = "STUB-OUT right-size" ] && ok "AC7 control: the same stub exiting 0 IS shown, so the failing leg is live" \
  || no "AC7 control: stderr: $(cat "$ROOT/err.log")"

echo "== AC8: an ABSENT right-size prints nothing; the write still returns 0 =="
A8D="$(mktmp)/alone"; mkdir -p "$A8D"; cp "$SUT" "$A8D/propose-common.sh"
A8="$(sz_tree)"
call_guard "$A8D/propose-common.sh" "$A8" "cand.md" "$SZ_DRAFT"
sz_check "AC8" "$A8" "cand.md"
[ ! -s "$ROOT/err.log" ] && ok "AC8: no sibling dispatcher ⇒ no line" || no "AC8 stderr: $(cat "$ROOT/err.log")"

echo "-- MUTATION CONTROLS (AC9): the one right-size call line after the mv -f --"
CALL_RE='^  pc_size_line "\$pc_out_dir_abs" "\$pc_name" >&2$'
[ "$(grep -c "$CALL_RE" "$SUT")" = 1 ] && ok "AC9: exactly one size-line call line in propose-common.sh" || no "AC9: call line count $(grep -c "$CALL_RE" "$SUT")"
A9I="$(sz_dir intact)"; A9="$(sz_tree)"
call_guard "$A9I/propose-common.sh" "$A9" "cand.md" "$SZ_DRAFT"
[ "$(cat "$ROOT/err.log")" = "$SZ_WANT" ] && ok "AC9 control: an intact copy beside the symlinked dispatcher prints the line" \
  || no "AC9 control: intact copy stderr: $(cat "$ROOT/err.log")"
for m in nocall stdout; do
  case "$m" in
    nocall) A9M="$(sz_dir nocall "/$CALL_RE/d")" ;;
    stdout) A9M="$(sz_dir stdout 's/^\(  pc_size_line "\$pc_out_dir_abs" "\$pc_name"\) >&2$/\1/')" ;;
  esac
  if cmp -s "$A9M/propose-common.sh" "$SUT" || ! bash -n "$A9M/propose-common.sh" 2>/dev/null; then
    no "AC9 $m: could not build a valid mutant - control uncontrolled"; continue
  fi
  A9T="$(sz_tree)"
  call_guard "$A9M/propose-common.sh" "$A9T" "cand.md" "$SZ_DRAFT"
  case "$m" in
    nocall) [ "$(cat "$ROOT/rc")" -eq 0 ] && [ ! -s "$ROOT/err.log" ] \
              && ok "AC9 MUTATION CONTROL: the call line deleted ⇒ no stderr line (AC5 turns red)" \
              || no "AC9 nocall mutant still printed: $(cat "$ROOT/err.log")" ;;
    stdout) [ "$(cat "$ROOT/out.log")" = "$SZ_WANT" ] && [ ! -s "$ROOT/err.log" ] \
              && ok "AC9 MUTATION CONTROL: the call's >&2 dropped ⇒ the line lands on stdout (AC5's stdout-empty turns red)" \
              || no "AC9 stdout mutant: out=$(cat "$ROOT/out.log") err=$(cat "$ROOT/err.log")" ;;
  esac
done

# ---------------------------------------------------------------------------
echo
echo "propose-common: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
