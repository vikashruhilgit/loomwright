#!/usr/bin/env bash
# test-module-shape-facts.sh — static self-tests for module-shape-facts.sh (the facts behind the
# Phase 4.5 MODULE-SHAPE ADVISORY line) plus the wording pins of the module-layout standard.
# Builds fixture git repos in `mktemp -d` and runs the script from a DIFFERENT cwd with --root,
# proving the read-only / never-cd contract. No network; nothing outside the temp dir is touched
# (HOME is relocated into it). Exit 0 = all pass, 1 = any failure.
#
# Covers:
#   A. a helper the diff defines in 2 files is printed with its count and both files; a helper in
#      ONE file is not (the 2+ filter)
#   B. a name defined in 2+ files that the diff did NOT add is not printed (the added-only filter);
#      a changed signature of an existing definition is not an addition
#   C. AC10 — a diff whose touched files are all `*.test.*` / `test-*.sh` still gets line counts and
#      shared-name facts
#   D. language coverage (Python `def`, JS/TS `function` and `const x = (…) =>`), docs never define a
#      name, a JS method / call is not read as a shell definition, line counts before -> after
#   E. the per-name file list is capped with a visible `(+N more)` marker
#   F. AC11 — every no-facts case exits 0 with EMPTY stdout and its OWN stderr reason: bad args,
#      missing base ref (named), missing head ref, not a git repo, binary-only diff, deleted-only
#      diff, empty diff, mixed deleted+binary diff (no_text_files), no merge base (git_failed); and
#      a failed repo-wide name scan keeps the line facts with `names_unavailable` on stderr
#   G. wording pins: AC6 single home of the line threshold (exact AC6 pattern), AC4b
#      `deliberate per-file convention`, AC12 "facts unavailable", AC5 severities, step 1h's base
#      rule, and that the script itself holds no threshold
#   H. non-blob entries (a directory or gitlink at the merge base, a gitlink at head) never desync
#      the batched line counts of the files after them; nor does a text file whose awk record
#      length differs from its byte length (a NUL past numstat's 8 KB probe, multibyte UTF-8)
#
# The brief's `## Pin mutations` rows delete each `pin:` marker line of module-shape-facts.sh; each
# deletion turns at least one leg here red. This file's own ok()/no()/has()/lacks() are the
# conventional per-file harness helpers (the live negative case for AC4b).

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/module-shape-facts.sh"
PLUGIN="$(cd "$HERE/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN/.." && pwd)"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }   # has <text> <needle>
lacks() { if has "$1" "$2"; then return 1; fi; return 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$TMP"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE 2>/dev/null || true
ELSEWHERE="$TMP/elsewhere"; mkdir -p "$ELSEWHERE"

g() { local d="$1"; shift; git -C "$d" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }
mkrepo() { mkdir -p "$1" && g "$1" init -q . ; }
commit() { g "$1" add -A && g "$1" commit -qm "$2" --allow-empty; }

OUT=""; ERR=""; RC=0
run() {  # run <args…> — from ELSEWHERE, never inside the fixture
  ( cd "$ELSEWHERE" && bash "$S" "$@" ) > "$TMP/out" 2> "$TMP/err"; RC=$?
  OUT="$(cat "$TMP/out")"; ERR="$(cat "$TMP/err")"
}

# ---- A. 2+ filter ------------------------------------------------------------------------------
echo "== A. a helper defined in 2+ files is printed; a helper in 1 file is not =="
R="$TMP/a"; mkrepo "$R"; printf 'hi\n' > "$R/README"; commit "$R" base; BA="$(g "$R" rev-parse HEAD)"
printf 'helper() {\n  echo a\n}\n' > "$R/a.sh"
printf 'helper() {\n  echo b\n}\n' > "$R/b.sh"
printf 'solo() { :; }\n' > "$R/c.sh"
commit "$R" feature
run "$BA" --root "$R"
[ "$RC" -eq 0 ] && ok "A1 exit 0" || no "A1 exit $RC"
has "$OUT" 'shared-name: helper defined in 2 files: a.sh, b.sh' \
  && ok "A2 helper printed with its file count and both files" || no "A2 helper line missing: $OUT"
lacks "$OUT" 'solo' && ok "A3 a name defined in only one file is not printed" || no "A3 single-file name printed: $OUT"
has "$OUT" 'lines: a.sh new -> 3' && ok "A4 an added file reads new -> <lines>" || no "A4 line count for a.sh: $OUT"
has "$OUT" 'no size threshold applied' && ok "A5 header states that no threshold is applied" || no "A5 header"
mkdir -p "$R/sub"
run "$BA" --root "$R/sub"
has "$OUT" 'shared-name: helper defined in 2 files: a.sh, b.sh' \
  && ok "A6 a --root below the top level still scans the whole repo" || no "A6 subdirectory root narrowed the scan: $OUT"

# ---- B. added-only filter ----------------------------------------------------------------------
echo "== B. a name the diff did not add is not printed =="
R="$TMP/b"; mkrepo "$R"
printf 'legacy() {\n  :\n}\n' > "$R/x.sh"; cp "$R/x.sh" "$R/y.sh"
printf 'function fmt(a) {\n  return a\n}\n' > "$R/p.js"; cp "$R/p.js" "$R/q.js"
commit "$R" base; BB="$(g "$R" rev-parse HEAD)"
printf 'echo more\n' >> "$R/x.sh"
printf 'function fmt(a, b) {\n  return a\n}\n' > "$R/p.js"
commit "$R" feature
run "$BB" HEAD --root "$R"
[ "$RC" -eq 0 ] && ok "B1 exit 0" || no "B1 exit $RC"
has "$OUT" 'lines: x.sh 3 -> 4' && ok "B2 a touched file reads <before> -> <after>" || no "B2 x.sh count: $OUT"
lacks "$OUT" 'legacy' && ok "B3 a 2+-file name the diff did not add is not printed" || no "B3 unadded name printed: $OUT"
lacks "$OUT" 'shared-name: fmt' && ok "B4 a changed signature is not a new definition" || no "B4 fmt printed: $OUT"

# ---- C. AC10: test files only ------------------------------------------------------------------
echo "== C. AC10 — test-only diff gets the same facts =="
R="$TMP/c"; mkrepo "$R"; printf 'test("x", () => {});\n' > "$R/widget.test.js"; commit "$R" base; BC="$(g "$R" rev-parse HEAD)"
printf 'assert_eq() {\n  [ "$1" = "$2" ]\n}\n' > "$R/test-one.sh"
printf 'assert_eq() {\n  [ "$1" = "$2" ]\n}\n' > "$R/test-two.sh"
printf 'const clipped = (s) => s.slice(0, 3);\n' >> "$R/widget.test.js"
printf 'const clipped = (s) => s.slice(0, 3);\n' > "$R/gadget.test.js"
commit "$R" feature
run "$BC" --root "$R"
c_ok=1
for f in 'lines: test-one.sh new -> 3' 'lines: test-two.sh new -> 3' 'lines: widget.test.js 1 -> 2' 'lines: gadget.test.js new -> 1'; do
  has "$OUT" "$f" || { c_ok=0; no "C1 missing '$f'"; }
done
[ "$c_ok" -eq 1 ] && ok "C1 every test file gets a line count"
has "$OUT" 'shared-name: assert_eq defined in 2 files: test-one.sh, test-two.sh' \
  && ok "C2 shell test helper copied into 2 test files is printed" || no "C2 assert_eq: $OUT"
has "$OUT" 'shared-name: clipped defined in 2 files: gadget.test.js, widget.test.js' \
  && ok "C3 JS test helper copied into 2 test files is printed" || no "C3 clipped: $OUT"

# ---- D. language coverage ----------------------------------------------------------------------
echo "== D. language coverage and exclusions =="
R="$TMP/d"; mkrepo "$R"; printf 'x\n' > "$R/README"; commit "$R" base; BD="$(g "$R" rev-parse HEAD)"
printf 'def tidy(x):\n    return x\n' > "$R/util_a.py"
printf 'async def tidy(x):\n    return x\n' > "$R/util_b.py"
printf 'export function redact(s) {\n  return s\n}\n' > "$R/r1.js"
printf 'async function redact(s: string) {\n  return s\n}\n' > "$R/r2.ts"
printf 'class A {\n  render() {\n    go()\n  }\n}\n' > "$R/m1.js"
printf 'class B {\n  render() {\n    go()\n  }\n}\n' > "$R/m2.js"
printf '```sh\nmdonly() { :; }\nfunction mdonly2 {\n```\n' > "$R/notes.md"
cp "$R/notes.md" "$R/more.md"
commit "$R" feature
run "$BD" --root "$R"
has "$OUT" 'shared-name: tidy defined in 2 files: util_a.py, util_b.py' && ok "D1 Python def / async def" || no "D1 tidy: $OUT"
has "$OUT" 'shared-name: redact defined in 2 files: r1.js, r2.ts' && ok "D2 JS/TS function (export / async)" || no "D2 redact: $OUT"
lacks "$OUT" 'render' && lacks "$OUT" 'shared-name: go' && ok "D3 a JS method or call is not a definition" || no "D3 render/go printed: $OUT"
lacks "$OUT" 'mdonly' && ok "D4 documentation files never define a name" || no "D4 md name printed: $OUT"
has "$OUT" 'lines: notes.md new -> 4' && ok "D5 documentation files still get a line count" || no "D5 notes.md count: $OUT"

# ---- E. cap ------------------------------------------------------------------------------------
echo "== E. per-name file list is capped with a visible marker =="
R="$TMP/e"; mkrepo "$R"
for x in a b c d e f g; do printf 'ok() { :; }\n' > "$R/test-$x.sh"; done
commit "$R" base; BE="$(g "$R" rev-parse HEAD)"
printf 'ok() { :; }\n' > "$R/test-h.sh"; commit "$R" feature
run "$BE" --root "$R"
has "$OUT" 'shared-name: ok defined in 8 files: test-a.sh, test-b.sh, test-c.sh, test-d.sh, test-e.sh (+3 more)' \
  && ok "E1 a conventional helper shows its full file count and a (+N more) marker" || no "E1 cap line: $OUT"

# ---- F. AC11: no facts ⇒ exit 0, empty stdout, specific stderr reason -------------------------
echo "== F. AC11 — no-facts cases =="
nofacts() {  # nofacts <label> <reason> <extra stderr needle or ""> <args…>
  local label="$1" reason="$2" extra="$3"; shift 3
  run "$@"
  if [ "$RC" -eq 0 ] && [ -z "$OUT" ] && has "$ERR" "no facts — $reason" && { [ -z "$extra" ] || has "$ERR" "$extra"; }; then
    ok "$label ⇒ exit 0, empty stdout, stderr '$reason'${extra:+ naming '$extra'}"
  else
    no "$label (rc=$RC out='$OUT' err='$ERR')"
  fi
}
nofacts "F1 no arguments" "bad_args" ""
nofacts "F2 missing base ref" "bad_ref" "base ref not found: nope-ref" nope-ref --root "$TMP/a"
nofacts "F3 missing head ref" "bad_ref" "head ref not found: nope-head" "$BA" nope-head --root "$TMP/a"
mkdir -p "$TMP/plain"
nofacts "F4 outside a git repo" "not_a_git_repo" "root=$TMP/plain" HEAD --root "$TMP/plain"
R="$TMP/f5"; mkrepo "$R"; printf 'x\n' > "$R/README"; commit "$R" base; BF="$(g "$R" rev-parse HEAD)"
printf 'GIF\000\001\002\003\000binary\n' > "$R/blob.bin"; commit "$R" feature
nofacts "F5 binary-only diff" "binary_only" "" "$BF" --root "$R"
R="$TMP/f6"; mkrepo "$R"; printf 'gone() { :; }\n' > "$R/gone.sh"; printf 'x\n' > "$R/keep"; commit "$R" base; BG="$(g "$R" rev-parse HEAD)"
g "$R" rm -q gone.sh; commit "$R" feature
nofacts "F6 deleted-only diff" "deleted_only" "" "$BG" --root "$R"
nofacts "F7 empty diff" "no_changes" "" HEAD HEAD --root "$TMP/a"
nofacts "F8 unknown option" "bad_args" "" HEAD --bogus --root "$TMP/a"
R="$TMP/f9"; mkrepo "$R"; printf 'gone() { :; }\n' > "$R/gone.sh"; printf 'x\n' > "$R/keep"; commit "$R" base; BH="$(g "$R" rev-parse HEAD)"
g "$R" rm -q gone.sh; printf 'GIF\000\001\002\003\000binary\n' > "$R/blob.bin"; commit "$R" feature
nofacts "F9 deleted text + added binary (mixed, no text left)" "no_text_files" "" "$BH" --root "$R"
R="$TMP/f10"; mkrepo "$R"; printf 'x\n' > "$R/a"; commit "$R" base; BI="$(g "$R" rev-parse HEAD)"
g "$R" checkout -q --orphan unrelated; g "$R" rm -rqf .; printf 'y\n' > "$R/b"; commit "$R" orphan
nofacts "F10 unrelated histories (no merge base)" "git_failed" "no merge base" "$BI" unrelated --root "$R"
# F11 — the repo-wide name scan fails (an unchanged subtree's object is missing, so `git grep` exits
# 128 while the diff, which never opens an unchanged tree, still works): line facts stay, stderr says
# names_unavailable, exit 0.
R="$TMP/f11"; mkrepo "$R"; mkdir -p "$R/lib"; printf 'other() { :; }\n' > "$R/lib/other.sh"; printf 'x\n' > "$R/a"
commit "$R" base; BJ="$(g "$R" rev-parse HEAD)"; printf 'y\n' >> "$R/a"; commit "$R" feature
oid="$(g "$R" rev-parse HEAD:lib)"; rm -f "$R/.git/objects/${oid%"${oid#??}"}/${oid#??}"
run "$BJ" --root "$R"
if [ "$RC" -eq 0 ] && has "$OUT" 'lines: a 1 -> 2' && lacks "$OUT" 'shared-name' && has "$ERR" 'names_unavailable'; then
  ok "F11 failed name scan ⇒ exit 0, line facts kept, stderr 'names_unavailable'"
else
  no "F11 names_unavailable (rc=$RC out='$OUT' err='$ERR')"
fi

# ---- H. non-blob entries never desync the batched line counts ---------------------------------
echo "== H. non-blob entries at the merge base or head keep later files' counts exact =="
# H1 — a directory at the base that is a file at head, sorted BEFORE two modified files.
R="$TMP/h1"; mkrepo "$R"; mkdir -p "$R/thing"; printf 'i\n' > "$R/thing/inner.txt"
printf 'a\nb\n' > "$R/uni.txt"; printf 'z\n' > "$R/zz.txt"; commit "$R" base; BK="$(g "$R" rev-parse HEAD)"
rm -rf "$R/thing"; printf 'f\n' > "$R/thing"; printf 'c\n' >> "$R/uni.txt"; printf 'y\n' >> "$R/zz.txt"; commit "$R" feature
run "$BK" --root "$R"
if [ "$RC" -eq 0 ] && has "$OUT" 'lines: thing new -> 1' && has "$OUT" 'lines: uni.txt 2 -> 3' && has "$OUT" 'lines: zz.txt 1 -> 2'; then
  ok "H1 directory -> file reads new and later files keep exact counts"
else
  no "H1 directory -> file desynced the counts (rc=$RC out='$OUT')"
fi
# H2 — a gitlink at the base whose commit object IS in the repo (cat-file would print the commit).
R="$TMP/h2"; mkrepo "$R"; printf 'a\nb\n' > "$R/uni.txt"; printf 'z\n' > "$R/zz.txt"; commit "$R" b0
c0="$(g "$R" rev-parse HEAD)"; g "$R" update-index --add --cacheinfo "160000,$c0,mod"; g "$R" commit -qm base; BL="$(g "$R" rev-parse HEAD)"
[ "$(g "$R" cat-file -t "$BL:mod" 2>/dev/null)" = "commit" ] || no "H2 fixture: base has no gitlink with a present commit"
g "$R" rm -q --cached mod; printf 'f\n' > "$R/mod"; printf 'c\n' >> "$R/uni.txt"; printf 'y\n' >> "$R/zz.txt"; commit "$R" feature
run "$BL" --root "$R"
if [ "$RC" -eq 0 ] && has "$OUT" 'lines: mod new -> 1' && has "$OUT" 'lines: uni.txt 2 -> 3' && has "$OUT" 'lines: zz.txt 1 -> 2'; then
  ok "H2 gitlink -> file reads new and later files keep exact counts"
else
  no "H2 gitlink -> file desynced the counts (rc=$RC out='$OUT')"
fi
# H3 — a file at the base that is a gitlink at head (its commit present) is skipped, not counted.
R="$TMP/h3"; mkrepo "$R"; printf 'f\n' > "$R/mod"; printf 'a\nb\n' > "$R/uni.txt"; printf 'z\n' > "$R/zz.txt"; commit "$R" base
BM="$(g "$R" rev-parse HEAD)"; g "$R" rm -q --cached mod; rm -f "$R/mod"
g "$R" update-index --add --cacheinfo "160000,$BM,mod"; printf 'c\n' >> "$R/uni.txt"; printf 'y\n' >> "$R/zz.txt"
g "$R" add uni.txt zz.txt; g "$R" commit -qm feature
run "$BM" --root "$R"
if [ "$RC" -eq 0 ] && lacks "$OUT" 'lines: mod' && has "$OUT" 'lines: uni.txt 2 -> 3' && has "$OUT" 'lines: zz.txt 1 -> 2'; then
  ok "H3 file -> gitlink is skipped and later files keep exact counts"
else
  no "H3 file -> gitlink (rc=$RC out='$OUT')"
fi
# H4 — a NUL past numstat's 8000-byte binary probe keeps the file text; awk must not end the record
# at the NUL (macOS awk does), or the byte-framed counter reads into the files after it.
R="$TMP/h4"; mkrepo "$R"; printf 'a\n' > "$R/b.txt"; printf 'a\nb\n' > "$R/c.txt"; printf '1\n2\n3\n' > "$R/d.txt"
commit "$R" base; BN="$(g "$R" rev-parse HEAD)"
i=0; : > "$R/a.txt"; while [ "$i" -lt 1400 ]; do printf 'blob 2\n' >> "$R/a.txt"; i=$((i + 1)); done
printf '\000end\n' >> "$R/a.txt"; printf 'q\n' >> "$R/b.txt"; printf 'q\n' >> "$R/c.txt"; printf '4\n5\n6\n7\n' >> "$R/d.txt"; commit "$R" feature
[ "$(g "$R" diff --numstat "$BN" HEAD -- a.txt | cut -f1)" = "1401" ] || no "H4 fixture: a.txt is not read as text by numstat"
run "$BN" --root "$R"
if [ "$RC" -eq 0 ] && has "$OUT" 'lines: a.txt new -> 1401' && has "$OUT" 'lines: b.txt 1 -> 2' && has "$OUT" 'lines: c.txt 2 -> 3' && has "$OUT" 'lines: d.txt 3 -> 7'; then
  ok "H4 a NUL past 8 KB in a text file keeps its own and later files' counts exact"
else
  no "H4 a late NUL desynced the counts (rc=$RC out='$OUT')"
fi
# H5 — multibyte UTF-8 content under a UTF-8 caller locale: the counter must count bytes, not
# characters (gawk/mawk/newer awk count characters under a UTF-8 locale and would under-consume).
R="$TMP/h5"; mkrepo "$R"; printf 'a\n' > "$R/b.txt"; commit "$R" base; BO="$(g "$R" rev-parse HEAD)"
printf '\303\251\303\251\303\251\n\342\202\254\342\202\254\n' > "$R/a.txt"; printf 'q\n' >> "$R/b.txt"; commit "$R" feature
( cd "$ELSEWHERE" && LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 bash "$S" "$BO" --root "$R" ) > "$TMP/out" 2> "$TMP/err"; RC=$?; OUT="$(cat "$TMP/out")"
if [ "$RC" -eq 0 ] && has "$OUT" 'lines: a.txt new -> 2' && has "$OUT" 'lines: b.txt 1 -> 2'; then
  ok "H5 multibyte content under a UTF-8 locale keeps its own and later files' counts exact"
else
  no "H5 multibyte content desynced the counts (rc=$RC out='$OUT')"
fi

# ---- G. wording pins ---------------------------------------------------------------------------
echo "== G. wording pins =="
SR="$PLUGIN/skills/supervisor-readiness/SKILL.md"
CR="$PLUGIN/agents/code-reviewer.md"
SH="$PLUGIN/skills/self-heal-advisory/SKILL.md"
# AC6 — the exact pattern from the brief; every hit must sit inside §"Module layout".
hits="$(cd "$REPO_ROOT" && grep -rnE '500[ -]?lines?|500-line' loomwright/agents loomwright/commands loomwright/skills)"
sec="$(awk '/^## Module layout$/ { s = NR; next } s && !e && /^## / { e = NR } END { print s + 0, (e ? e : NR + 1) }' "$SR")"
s_start="${sec% *}"; s_end="${sec#* }"
g_ok=1; n_hits=0
while IFS= read -r h; do
  [ -n "$h" ] || continue
  n_hits=$((n_hits + 1))
  case "$h" in
    loomwright/skills/supervisor-readiness/SKILL.md:*)
      n="${h#loomwright/skills/supervisor-readiness/SKILL.md:}"; n="${n%%:*}"
      if [ "$s_start" -gt 0 ] && [ "$n" -gt "$s_start" ] && [ "$n" -lt "$s_end" ]; then :; else g_ok=0; no "G1 threshold outside §Module layout: $h"; fi ;;
    *) g_ok=0; no "G1 threshold restated outside its single home: $h" ;;
  esac
done <<EOF_HITS
$hits
EOF_HITS
if [ "$n_hits" -ge 1 ] && [ "$g_ok" -eq 1 ]; then ok "G1 the line threshold appears only in §\"Module layout\" ($n_hits hit(s))"
elif [ "$n_hits" -eq 0 ]; then no "G1 the threshold is stated nowhere (the section must phrase it so the AC6 pattern matches)"; fi
grep -qE '500' "$S" && no "G2 module-shape-facts.sh holds a threshold" || ok "G2 module-shape-facts.sh holds no threshold"
cr_text="$(cat "$CR")"
has "$cr_text" 'deliberate per-file convention' && ok "G3 code-reviewer names the deliberate per-file convention exclusion" \
  || no "G3 code-reviewer lost 'deliberate per-file convention'"
has "$cr_text" 'MODULE-SHAPE ADVISORY' && ok "G4 code-reviewer names the MODULE-SHAPE ADVISORY line" || no "G4 code-reviewer MODULE-SHAPE ADVISORY"
d5="$(awk '/^5d\. / { on = 1 } on && /^6\. / { exit } on { print }' "$CR")"
has "$d5" 'MEDIUM `category: new`' && has "$d5" 'LOW' && has "$d5" 'never BLOCKING or HIGH' \
  && ok "G5 step 5d: copied helper MEDIUM new, unrelated growth LOW, never BLOCKING/HIGH" || no "G5 step 5d severities"
sh_line="$(grep -F '**MODULE-SHAPE ADVISORY (' "$SH" | head -1)"
has "$sh_line" 'include this line ONLY when `module_shape` is non-empty' && has "$sh_line" 'facts unavailable' \
  && ok "G6 the prompt line is gated on non-empty output and says absent means facts unavailable" || no "G6 prompt line gate / facts unavailable"
step1h="$(grep -E '^1h\. ' "$SH" | head -1)"
has "$step1h" 'module-shape-facts.sh' && has "$step1h" '`origin/main` when `BASE_BRANCH` is `main`' && has "$step1h" 'EVERY iteration' \
  && ok "G7 step 1h runs the script every iteration against on-entry's base rule" || no "G7 step 1h"
# AC7 — the house-rule size override is stated only in §"Module layout"; every other surface points.
ov="$(cd "$REPO_ROOT" && grep -rnE '(different|another) size' loomwright/agents loomwright/commands loomwright/skills | grep -v '^loomwright/skills/supervisor-readiness/SKILL.md:')"
[ -z "$ov" ] && ok "G8 the house-rule size override is stated only in §\"Module layout\"" || no "G8 override restated outside its single home: $ov"
# AC12 — no surface reads an absent MODULE-SHAPE ADVISORY line as "the class does not apply".
qc_line="$(grep -F '**Module shape (`module_shape`' "$PLUGIN/skills/quality-checklist/SKILL.md" | head -1)"
dl_line="$(grep -F '`module_shape` — a helper copied' "$SH" | head -1)"
if [ -n "$qc_line" ] && lacks "$qc_line" 'does not apply' && has "$qc_line" 'never read absence as clean' \
   && [ -n "$dl_line" ] && lacks "$dl_line" 'checkable only when the MODULE-SHAPE'; then
  ok "G9 checklist and DIFFERENT-LENS item never treat an absent line as 'not applicable'"
else
  no "G9 an absent MODULE-SHAPE line is read as 'not applicable' somewhere"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
