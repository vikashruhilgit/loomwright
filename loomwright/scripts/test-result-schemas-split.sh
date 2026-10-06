#!/usr/bin/env bash
# test-result-schemas-split.sh — structural self-test for the docs/RESULT_SCHEMAS.md split.
#
# docs/RESULT_SCHEMAS.md is an INDEX: its preamble, then every top-level `## ` heading in the
# original order, each followed by ONE pointer line `See [result-schemas/<f>](result-schemas/<f>).`
# Each section body lives verbatim in docs/result-schemas/<f>.md, which starts with the same
# `## ` heading. This test keeps the index and the split files from drifting apart:
#   A. every index heading carries exactly one pointer, to an existing split file whose first
#      `## ` heading equals the index heading (matched on the heading text, never the filename);
#   B. each split file holds exactly one top-level (fence-aware) `## ` heading;
#   C. no split file is unreferenced, and none is referenced twice;
#   D. the index's heading sequence equals the split files' heading sequence (read in pointer
#      order), and the sorted heading set over every split file equals the index's;
#   E. MUTATION CONTROLS — an index with one pointer removed, and a split dir with one extra
#      unreferenced file, each FAIL the same check (each mutant gated on non-empty + differs).
# Headings are detected fence-aware: a `## ` line inside a ``` / ~~~ fenced block is not a section.
# Read-only; scratch files live under `mktemp -d`. Exit 0 = all pass, 1 = any failure.

set -uo pipefail
export LC_ALL=C
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INDEX="$HERE/../docs/RESULT_SCHEMAS.md"
SPLIT_DIR="$HERE/../docs/result-schemas"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" 2>/dev/null' EXIT

# headings <file> — top-level `## ` lines outside fenced blocks, in order.
headings() {
  awk '
    {
      if (match($0, /^[ ]{0,3}(```+|~~~+)/)) {
        m = substr($0, RSTART, RLENGTH); sub(/^ +/, "", m)
        if (fence == "") { fence = m; next }
        rest = $0; sub(/^ +/, "", rest)
        if (substr(m, 1, 1) == substr(fence, 1, 1) && length(m) >= length(fence) && rest ~ /^[`~]+[ \t]*$/) { fence = ""; next }
        next
      }
      if (fence == "" && /^## /) print
    }' "$1"
}

# pointers <index> — one TAB-separated row per index heading: <heading>\t<pointer count>\t<file(s)>
pointers() {
  awk '
    function flush() { if (h != "") printf "%s\t%d\t%s\n", h, n, files }
    {
      if (match($0, /^[ ]{0,3}(```+|~~~+)/)) { infence = !infence; next }
      if (infence) next
      if (/^## /) { flush(); h = $0; n = 0; files = ""; next }
      if (h != "" && match($0, /^See \[result-schemas\/[^]]+\]\(result-schemas\/[^)]+\)\.$/)) {
        a = $0; sub(/^See \[result-schemas\//, "", a); sub(/\].*$/, "", a)
        b = $0; sub(/^.*\]\(result-schemas\//, "", b); sub(/\)\.$/, "", b)
        n++; files = files (files == "" ? "" : " ") (a == b ? a : a "|MISMATCH|" b)
      }
    }
    END { flush() }' "$1"
}

# check_split <index> <dir> — prints one line per problem; returns 0 iff none.
check_split() {
  local idx="$1" dir="$2" probs=0 h n f first cnt
  local rows="$TMP/rows.$$" seen="$TMP/seen.$$"
  : > "$seen"
  pointers "$idx" > "$rows"
  [ -s "$rows" ] || { echo "    no '## ' headings found in $idx"; return 1; }
  while IFS="$(printf '\t')" read -r h n f; do
    if [ "$n" != "1" ]; then echo "    '$h': $n pointer lines (want exactly 1)"; probs=$((probs+1)); continue; fi
    case "$f" in *"|MISMATCH|"*) echo "    '$h': link text and target differ ($f)"; probs=$((probs+1)); continue ;; esac
    if [ ! -f "$dir/$f" ]; then echo "    '$h': pointer target result-schemas/$f does not exist"; probs=$((probs+1)); continue; fi
    first="$(headings "$dir/$f" | head -1)"
    [ "$first" = "$h" ] || { echo "    '$h': result-schemas/$f starts with '$first'"; probs=$((probs+1)); }
    echo "$f" >> "$seen"
  done < "$rows"
  # B. one top-level heading per split file
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    cnt="$(headings "$f" | wc -l | tr -d ' ')"
    [ "$cnt" = "1" ] || { echo "    result-schemas/${f##*/}: $cnt top-level '## ' headings (want 1)"; probs=$((probs+1)); }
  done
  # C. every split file referenced exactly once
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    cnt="$(grep -cxF -- "${f##*/}" "$seen")"
    [ "$cnt" = "1" ] || { echo "    result-schemas/${f##*/}: referenced $cnt times from the index (want 1)"; probs=$((probs+1)); }
  done
  # D. heading sequence (pointer order) and sorted heading set (every split file)
  headings "$idx" > "$TMP/ih.$$"
  : > "$TMP/sh.$$"
  while IFS= read -r f; do [ -f "$dir/$f" ] && headings "$dir/$f" | head -1 >> "$TMP/sh.$$"; done < "$seen"
  cmp -s "$TMP/ih.$$" "$TMP/sh.$$" || { echo "    index heading sequence != split heading sequence (pointer order)"; probs=$((probs+1)); }
  : > "$TMP/all.$$"
  for f in "$dir"/*.md; do [ -f "$f" ] && headings "$f" | head -1 >> "$TMP/all.$$"; done
  if ! cmp -s <(sort "$TMP/ih.$$") <(sort "$TMP/all.$$"); then
    echo "    sorted index headings != sorted split-file headings"; probs=$((probs+1))
  fi
  [ "$probs" -eq 0 ]
}

echo "== result-schemas split: real tree =="
[ -f "$INDEX" ] && ok "index exists: docs/RESULT_SCHEMAS.md" || no "index missing: $INDEX"
nfiles="$(bash -c 'shopt -s nullglob; set -- "$1"/*.md; echo $#' _ "$SPLIT_DIR")"
[ "$nfiles" -gt 0 ] && ok "split dir holds $nfiles file(s)" || no "split dir empty or missing: $SPLIT_DIR"
nh="$(headings "$INDEX" | wc -l | tr -d ' ')"
[ "$nh" = "$nfiles" ] && ok "index heading count ($nh) == split file count ($nfiles)" || no "index headings=$nh split files=$nfiles"
pre="$(awk '/^## /{exit} {print}' "$INDEX")"
[ -n "$pre" ] && ok "index keeps a non-empty preamble before the first heading" || no "index preamble is empty"
if out="$(check_split "$INDEX" "$SPLIT_DIR")"; then
  ok "A-D: every heading has one pointer to a split file starting with that heading; none unreferenced; sequences equal"
else
  no "A-D: index/split drift:"; printf '%s\n' "$out"
fi

echo "== mutation controls =="
# Mutant 1 — the first pointer line removed from a copy of the index.
M1="$TMP/index-pointer-removed.md"
awk '!d && /^See \[result-schemas\//{d=1; next} {print}' "$INDEX" > "$M1"
if [ -s "$M1" ] && ! cmp -s "$M1" "$INDEX"; then
  if check_split "$M1" "$SPLIT_DIR" >/dev/null; then
    no "MUTATION CONTROL: an index with one pointer removed was ACCEPTED"
  else
    ok "MUTATION CONTROL: an index with one pointer removed is REJECTED"
  fi
else
  no "could not build the pointer-removed mutant - this control is inconclusive"
fi
# Mutant 2 — an extra, unreferenced split file in a copy of the split dir.
M2="$TMP/split-extra"
mkdir -p "$M2" && cp "$SPLIT_DIR"/*.md "$M2"/ 2>/dev/null
printf '## ORPHAN_RESULT\n\nunreferenced.\n' > "$M2/orphan-result.md"
if [ -s "$M2/orphan-result.md" ] && [ "$(ls "$M2" | wc -l | tr -d ' ')" -gt "$nfiles" ]; then
  if check_split "$INDEX" "$M2" >/dev/null; then
    no "MUTATION CONTROL: an unreferenced split file was ACCEPTED"
  else
    ok "MUTATION CONTROL: an unreferenced split file is REJECTED"
  fi
else
  no "could not build the unreferenced-file mutant - this control is inconclusive"
fi
# Mutant 3 — a split file whose first heading no longer matches its index heading.
M3="$TMP/split-renamed"
mkdir -p "$M3" && cp "$SPLIT_DIR"/*.md "$M3"/ 2>/dev/null
victim="$(ls "$M3" | head -1)"
if [ -n "$victim" ]; then
  awk 'NR==1 && /^## /{print $0 " (renamed)"; next} {print}' "$SPLIT_DIR/$victim" > "$M3/$victim"
fi
if [ -n "$victim" ] && [ -s "$M3/$victim" ] && ! cmp -s "$M3/$victim" "$SPLIT_DIR/$victim"; then
  if check_split "$INDEX" "$M3" >/dev/null; then
    no "MUTATION CONTROL: a split file with a drifted heading was ACCEPTED"
  else
    ok "MUTATION CONTROL: a split file with a drifted heading is REJECTED"
  fi
else
  no "could not build the drifted-heading mutant - this control is inconclusive"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
