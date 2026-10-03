#!/usr/bin/env bash
# test-check-locale-prefix.sh — offline self-test for check-locale-prefix.sh.
#
# Builds fixture trees in a temp dir (never touches the real repo files) and asserts the gate's
# discrimination, fail-CLOSED:
#   1. green              — env-prefixed, script-scope export, comments, prose, plain statement -> exit 0
#   2. each crash shape   — one fixture per command position ($( ), pipe, ;, &&, if, while, !, then,
#                           do, `{`, line start, LANG=, LC_COLLATE=, quoted value, two assignments)
#                           -> red, offender named as file:line
#   3. *.bash + nested    — an offender in a nested dir and in a .bash file is named
#   4. pruned dirs        — an offender under .git/ or node_modules/ is NOT scanned
#   5. zero files         — an empty tree -> red (never green on nothing)
#   6. mutation control   — the real setup-memory.sh with its gitignore_gate `env` dropped -> red
#   7. argument errors    — `--root` with no value, an unknown flag, a non-directory root -> red
#   8. fix hint           — a flagged builtin (`read`) is pointed at `export LC_ALL=C`, not only env
#   9. the real tree      — green
#  10. git mode           — a git-repo root is enumerated the way CI sees it: an offender in a
#                           .gitignore'd path is NOT reported (control: the same line in a tracked
#                           file and in an untracked-unignored file IS); an index entry deleted from
#                           disk is skipped; a root nested below a work-tree top level walks instead
#
# The fixture lines below spell `@LC_ALL=` (stripped when written) so this file itself stays green
# under the gate it tests — test 9 scans the real tree, this file included.
# Portability: bash 3.2 safe (macOS) + Linux CI. No sed -i, no mapfile, offline.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../loomwright/scripts/hermetic-test-env.sh"
set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
CHECK="$script_dir/check-locale-prefix.sh"
[ -f "$CHECK" ] || { echo "test-check-locale-prefix: gate script not found: $CHECK" >&2; exit 1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-locale-prefix.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

run() { bash "$CHECK" --root "$tmp/r" > "$tmp/out" 2>&1; }

# fresh_tree — a green fixture: every allowed shape, one file.
fresh_tree() {
  rm -rf "$tmp/r"; mkdir -p "$tmp/r/scripts"
  cat > "$tmp/r/scripts/good.sh" <<'EOF'
#!/usr/bin/env bash
export LC_ALL=C
# a comment may say: x="$(ls | LC_ALL=C sort)"
    # an indented comment too: if LC_ALL=C grep -q x f; then :; fi
x="$(ls | env LC_ALL=C sort -u)"
if env LC_ALL=C grep -qiF -- x f; then :; fi
y="$(env LC_ALL="$L" LANG=C tr a b < f; echo z)"
echo "== items in LC_ALL=C sort order, done skipped =="
ok "(g10) cross-file duplicate id: LC_ALL=C path-sort first-file wins"
LC_ALL=C
LANG=C   # a plain statement, not a prefix
f() { local LC_ALL=C; sort; }
EOF
}

echo "== 1. green fixture tree =="
fresh_tree; run; rc=$?
[ "$rc" -eq 0 ] && grep -q '1/1 scanned shell files' "$tmp/out" && ok "1. every allowed shape is green (1/1)" || no "1. rc=$rc: $(cat "$tmp/out")"

echo "== 2. each crash shape is red, named as file:line =="
i=0
while IFS= read -r line; do
  i=$((i+1))
  fresh_tree
  printf '#!/usr/bin/env bash\n:\n%s\n' "${line//@/}" > "$tmp/r/scripts/bad.sh"
  run; rc=$?
  if [ "$rc" -ne 0 ] && grep -qF 'OFFENDER scripts/bad.sh:3: ' "$tmp/out" && ! grep -q 'OFFENDER scripts/good.sh' "$tmp/out"; then
    ok "2.$i red: ${line//@/}"
  else
    no "2.$i rc=$rc for [$line]: $(cat "$tmp/out")"
  fi
done <<'EOF'
x="$(ls | @LC_ALL=C sort -u)"
x="$(@LC_ALL=C sort f; echo y)"
x=`@LC_ALL=C sort f`
a | @LC_ALL=C sort | b
:; @LC_ALL=C sort f
true && @LC_ALL=C sort f
false || @LC_ALL=C sort f
if @LC_ALL=C grep -qF x f; then :; fi
  elif @LC_ALL=C grep -q x f; then :
while @LC_ALL=C read -r l; do :; done
if ! @LC_ALL=C tr -d '\000' < f | cmp -s - f; then :; fi
if true; then @LC_ALL=C sort f; fi
for i in 1; do @LC_ALL=C sort f; done
{ @LC_ALL=C sort f; }
    @LC_ALL=C sort f
@LANG=C grep -c x f
@LC_COLLATE=C sort f
@LC_ALL="$CORPUS_LOCALE" bash t.sh
@LC_ALL=C @LANG=C sort f
diff <(@LC_ALL=C sort a) b
EOF

echo "== 3. nested dirs and *.bash are scanned =="
fresh_tree; mkdir -p "$tmp/r/a/b"
printf 'x="$(@LC_ALL=C sort f; echo)"\n' | sed 's/@//' > "$tmp/r/a/b/deep.bash"
run; rc=$?
[ "$rc" -ne 0 ] && grep -qF 'OFFENDER a/b/deep.bash:1: ' "$tmp/out" && grep -q '2 scanned shell files' "$tmp/out" \
  && ok "3. an offender in a nested .bash file is named" || no "3. rc=$rc: $(cat "$tmp/out")"

echo "== 4. .git/ and node_modules/ are pruned =="
fresh_tree; mkdir -p "$tmp/r/.git/hooks" "$tmp/r/node_modules/pkg"
printf 'LC_ALL=C sort f\n' > "$tmp/r/.git/hooks/x.sh"
printf 'LC_ALL=C sort f\n' > "$tmp/r/node_modules/pkg/y.sh"
run; rc=$?
[ "$rc" -eq 0 ] && grep -q '1/1 scanned' "$tmp/out" && ok "4. pruned dirs are not scanned" || no "4. rc=$rc: $(cat "$tmp/out")"

echo "== 5. zero files => red =="
rm -rf "$tmp/r"; mkdir -p "$tmp/r/scripts"
run; rc=$?
[ "$rc" -ne 0 ] && grep -q 'matched nothing' "$tmp/out" && ok "5. an empty tree fails closed" || no "5. rc=$rc: $(cat "$tmp/out")"

echo "== 6. mutation control: the real gitignore_gate line with its env dropped => red =="
MEM="$script_dir/../loomwright/scripts/setup-memory.sh"
rm -rf "$tmp/r"; mkdir -p "$tmp/r"
if grep -qF '! env LC_ALL=C tr -d' "$MEM"; then
  sed 's/\(! \)env \(LC_ALL\)\(=C tr -d\)/\1\2\3/' "$MEM" > "$tmp/r/setup-memory.sh"
  run; rc=$?
  [ "$rc" -ne 0 ] && grep -qF 'OFFENDER setup-memory.sh:' "$tmp/out" && grep -q '1 temporary locale' "$tmp/out" \
    && ok "6. reverting gitignore_gate's env prefix turns the gate red" || no "6. rc=$rc: $(cat "$tmp/out")"
else
  no "6. setup-memory.sh no longer carries '! env LC_ALL=C tr -d' — re-point this mutation control"
fi

echo "== 7. argument errors fail closed, each with its own message =="
bash "$CHECK" --root > "$tmp/out" 2>&1; rc=$?
[ "$rc" -ne 0 ] && grep -q -- '--root needs a directory' "$tmp/out" && ok "7a. --root with no value is red" || no "7a. rc=$rc: $(cat "$tmp/out")"
bash "$CHECK" --bogus > "$tmp/out" 2>&1; rc=$?
[ "$rc" -ne 0 ] && grep -q 'unknown argument: --bogus' "$tmp/out" && ok "7b. an unknown argument is red" || no "7b. rc=$rc: $(cat "$tmp/out")"
: > "$tmp/notadir"
bash "$CHECK" --root "$tmp/notadir" > "$tmp/out" 2>&1; rc=$?
[ "$rc" -ne 0 ] && grep -q 'root is not a directory' "$tmp/out" && ok "7c. a non-directory --root is red" || no "7c. rc=$rc: $(cat "$tmp/out")"

echo "== 8. the fix hint separates external commands from builtins/functions =="
fresh_tree
printf 'while @LC_ALL=C read -r l; do :; done < f\n' | sed 's/@//' > "$tmp/r/scripts/bad.sh"
run; rc=$?
# `env LC_ALL=C read` is NOT a fix: it runs /usr/bin/read in its own process (exit 0, variable empty).
[ "$rc" -ne 0 ] && grep -q 'external command -> prefix it with env' "$tmp/out" \
  && grep -q 'builtin or shell function.*NOT env' "$tmp/out" && grep -qF 'export LC_ALL=C' "$tmp/out" \
  && ok "8. a flagged builtin gets the export remedy, not only env" || no "8. rc=$rc: $(cat "$tmp/out")"

echo "== 9. the real tree is green =="
bash "$CHECK" > "$tmp/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "9. real tree: $(cat "$tmp/out")" || no "9. real tree rc=$rc: $(cat "$tmp/out")"

echo "== 10. git mode: .gitignore'd files are not scanned, tracked + untracked-unignored are =="
# The real failure: a find walk read stale salvage copies under the ignored .supervisor/ that a CI
# checkout never has, so local runs went red where CI was green. Each sub-case below goes red if
# the enumeration reverts to the walk (10a) or over-narrows to tracked-only (10c).
if command -v git >/dev/null 2>&1; then
  bad_line="$(printf 'x="$(@LC_ALL=C sort f; echo)"' | sed 's/@//')"
  git_tree() {
    fresh_tree; mkdir -p "$tmp/r/ignored/deep" "$tmp/r/tracked"
    printf 'ignored/\n' > "$tmp/r/.gitignore"
    printf '%s\n' "$bad_line" > "$tmp/r/ignored/deep/stale.sh"
    git -C "$tmp/r" init -q && git -C "$tmp/r" add .gitignore scripts/good.sh
  }
  git_tree; run; rc=$?
  [ "$rc" -eq 0 ] && grep -q '1/1 scanned shell files (git mode)' "$tmp/out" \
    && ok "10a. an offender under a .gitignore'd path is not scanned (git mode, 1/1)" || no "10a. rc=$rc: $(cat "$tmp/out")"
  git_tree; printf '%s\n' "$bad_line" > "$tmp/r/tracked/live.sh"; git -C "$tmp/r" add tracked/live.sh; run; rc=$?
  [ "$rc" -ne 0 ] && grep -qF 'OFFENDER tracked/live.sh:1: ' "$tmp/out" && ! grep -q 'OFFENDER ignored/' "$tmp/out" \
    && ok "10b. control: the same line in a tracked file is named (and only it)" || no "10b. rc=$rc: $(cat "$tmp/out")"
  git_tree; printf '%s\n' "$bad_line" > "$tmp/r/tracked/new.sh"; run; rc=$?
  [ "$rc" -ne 0 ] && grep -qF 'OFFENDER tracked/new.sh:1: ' "$tmp/out" \
    && ok "10c. control: an untracked-but-not-ignored file is named before it is staged" || no "10c. rc=$rc: $(cat "$tmp/out")"
  git_tree; printf ':\n' > "$tmp/r/tracked/gone.sh"; git -C "$tmp/r" add tracked/gone.sh; rm -f "$tmp/r/tracked/gone.sh"; run; rc=$?
  [ "$rc" -eq 0 ] && grep -q '1/1 scanned shell files (git mode)' "$tmp/out" \
    && ok "10d. an index entry deleted from disk is skipped, not an error" || no "10d. rc=$rc: $(cat "$tmp/out")"
  git_tree; bash "$CHECK" --root "$tmp/r/ignored" > "$tmp/out" 2>&1; rc=$?
  [ "$rc" -ne 0 ] && grep -qF 'OFFENDER deep/stale.sh:1: ' "$tmp/out" \
    && ok "10e. a root below the work-tree top level walks (no inherited ignore rules scanning nothing)" || no "10e. rc=$rc: $(cat "$tmp/out")"
else
  no "10. git is not on PATH — cannot exercise git mode"
fi

echo
echo "test-check-locale-prefix: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
