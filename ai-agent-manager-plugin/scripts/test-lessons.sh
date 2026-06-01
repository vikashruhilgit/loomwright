#!/usr/bin/env bash
# test-lessons.sh — self-tests for the LESSONS bounded sole-writer (v14.5.0).
# Runs in isolated temp git repos (never touches the real .supervisor/memory). Mirrors the
# test-project-memory.sh convention. Exit 0 = all pass, 1 = any failure.
#
# Covers:
#   1. worktree-guard (MERGE BLOCKER — closes red-team F1)
#   2. round-trip (lesson appears under its `## <category>` heading)
#   3. <=3/category eviction (oldest evicted)
#   4. two categories independent (both sections coexist)
#   5. .gitignore coverage of .supervisor/memory/ (checked against the real repo)

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WRITE="$HERE/write-lessons.sh"
REAL_REPO="$(cd "$HERE/../.." && pwd)"
LFILE=".supervisor/memory/LESSONS.md"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" "$TMP-wt" 2>/dev/null' EXIT
( cd "$TMP" && git init -q && git config user.email t@t && git config user.name t \
    && echo init > f && git add f && git commit -qm init )

echo "== 1. worktree-guard (MERGE BLOCKER) =="
git -C "$TMP" worktree add -q "$TMP-wt" -b wt >/dev/null 2>&1
( cd "$TMP-wt" && bash "$WRITE" --category auth --lesson "should be refused" --source test ) >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 3 ]; then ok "writer refuses from a worktree (exit 3)"; else no "writer did NOT refuse worktree (exit $rc)"; fi
if [ ! -e "$TMP-wt/$LFILE" ]; then ok "no LESSONS written under the worktree"; else no "lessons leaked into the worktree"; fi
git -C "$TMP" worktree remove --force "$TMP-wt" >/dev/null 2>&1

echo "== 2. round-trip =="
( cd "$TMP" && bash "$WRITE" --category auth --lesson "auth is JWT in src/auth/guard.ts" --source s1 ) >/dev/null 2>&1
f="$TMP/$LFILE"
if grep -q '^## auth$' "$f" 2>/dev/null && grep -q "auth is JWT in src/auth/guard.ts" "$f" 2>/dev/null; then
  ok "lesson appears under ## auth"
else
  no "lesson not found under ## auth"
fi
grep -q "bounded <=3 active per category" "$f" 2>/dev/null && ok "advisory banner present" || no "advisory banner missing"

echo "== 3. <=3/category eviction =="
BDIR="$(mktemp -d)"; ( cd "$BDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$BDIR" && for i in 1 2 3 4; do bash "$WRITE" --category build --lesson "build lesson number $i" --source ev >/dev/null 2>&1; done )
bf="$BDIR/$LFILE"
# Count `- [` entries under the ## build section only.
cnt="$(awk '/^## build$/{f=1;next} /^## /{f=0} f && /^- \[/{c++} END{print c+0}' "$bf" 2>/dev/null)"
if [ "$cnt" -eq 3 ]; then ok "capped at 3 entries under ## build (wrote 4, evicted 1)"; else no "per-category cap not enforced (have $cnt, want 3)"; fi
if grep -q "build lesson number 1" "$bf" 2>/dev/null; then no "oldest entry not evicted"; else ok "oldest entry (build lesson number 1) evicted"; fi
rm -rf "$BDIR"

echo "== 4. two categories independent =="
CDIR="$(mktemp -d)"; ( cd "$CDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$CDIR" && bash "$WRITE" --category auth --lesson "auth uses sessions" --source s \
    && bash "$WRITE" --category db --lesson "db is postgres via drizzle" --source s ) >/dev/null 2>&1
cf="$CDIR/$LFILE"
ac="$(awk '/^## auth$/{f=1;next} /^## /{f=0} f && /^- \[/{c++} END{print c+0}' "$cf" 2>/dev/null)"
dc="$(awk '/^## db$/{f=1;next} /^## /{f=0} f && /^- \[/{c++} END{print c+0}' "$cf" 2>/dev/null)"
if grep -q '^## auth$' "$cf" && grep -q '^## db$' "$cf" && [ "$ac" -eq 1 ] && [ "$dc" -eq 1 ]; then
  ok "both categories coexist with their entries (auth=$ac, db=$dc)"
else
  no "categories not independent (auth=$ac, db=$dc)"
fi
rm -rf "$CDIR"

echo "== 5. .gitignore coverage (real repo) =="
if git -C "$REAL_REPO" check-ignore -q .supervisor/memory/LESSONS.md 2>/dev/null; then ok ".supervisor/memory/ is gitignored in the real repo"; else no ".supervisor/memory/ NOT gitignored"; fi

echo "== 6. backslash integrity (awk ENVIRON, not -v) =="
WDIR="$(mktemp -d)"; ( cd "$WDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$WDIR" && bash "$WRITE" --category paths --lesson 'windows path C:\Users\x and a \n literal' --source s ) >/dev/null 2>&1
wf="$WDIR/$LFILE"
# A lesson containing backslashes must be stored verbatim on ONE line. The old `awk -v lesson=`
# would interpret \n -> newline (splitting the entry) and mangle \U/\x — this guards the ENVIRON fix.
if grep -qF 'C:\Users\x and a \n literal' "$wf" 2>/dev/null; then ok "backslashes stored literally (no awk -v escape corruption)"; else no "lesson backslashes corrupted"; fi
pc="$(awk '/^## paths$/{f=1;next} /^## /{f=0} f && /^- \[/{c++} END{print c+0}' "$wf" 2>/dev/null)"
[ "$pc" -eq 1 ] && ok "lesson stored as a single entry line" || no "lesson split across lines (have $pc)"
rm -rf "$WDIR"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
