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
#      unreferenced file, each FAIL the same check (each mutant gated on non-empty + differs);
#   F. CITED SUB-SECTION ANCHORS — the index ends with ONE `## Cited sub-section anchors` block
#      (a table: anchor text -> split file). Every section citation of this doc in the tracked
#      tree (`RESULT_SCHEMAS[.md]` then a section sign and a quoted or bare-identifier anchor; a
#      quoted anchor wrapped onto the next comment line is joined) whose anchor is not a top-level
#      index heading must have a row in that block naming a split file that holds a heading with
#      that text. Matching drops backticks and accepts a word-boundary prefix (an anchor
#      "`session_end` JSONL hard-signal fields" resolves to the heading that adds "(System Twin)").
#      CHANGELOG.md is excluded (frozen release history). Mutants: one row removed, one row
#      re-pointed to the wrong split file — each must FAIL. The anchors block is excluded from
#      checks A-D (it is the one index heading with no pointer line).
# Headings are detected fence-aware: a `## ` line inside a ``` / ~~~ fenced block is not a section.
# Read-only; scratch files live under `mktemp -d`. Exit 0 = all pass, 1 = any failure.

set -uo pipefail
export LC_ALL=C
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INDEX="$HERE/../docs/RESULT_SCHEMAS.md"
SPLIT_DIR="$HERE/../docs/result-schemas"
REPO="$(cd "$HERE/../.." && pwd)"
ANCHOR_H='## Cited sub-section anchors'

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

# strip_anchors <index> — the index without its `## Cited sub-section anchors` section (that
# heading up to the next top-level heading or EOF). Checks A-D run on this view.
strip_anchors() {
  awk -v A="$ANCHOR_H" '$0 == A {skip = 1; next} skip && /^## / {skip = 0} !skip {print}' "$1"
}

# check_split <index> <dir> — prints one line per problem; returns 0 iff none.
check_split() {
  local idx="$TMP/stripped.$$" dir="$2" probs=0 h n f first cnt
  local rows="$TMP/rows.$$" seen="$TMP/seen.$$"
  strip_anchors "$1" > "$idx"
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

# ---- F. cited sub-section anchors ------------------------------------------------------------
# norm — stdin lines: backticks dropped, whitespace runs collapsed, ends trimmed.
norm() { tr -d '`' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'; }

# all_headings <file> — every `##`..`######` heading text (hashes stripped), fence-aware, normalized.
all_headings() {
  awk '
    {
      if (match($0, /^[ ]{0,3}(```+|~~~+)/)) { infence = !infence; next }
      if (!infence && /^#{2,6} /) { sub(/^#+ /, ""); print }
    }' "$1" | norm
}

# CITE_RE — `RESULT_SCHEMAS[.md]`, an optional closing backtick and/or possessive, an optional
# space, the section sign, an optional space, then a quoted anchor or a bare identifier.
CITE_RE="RESULT_SCHEMAS(\\.md)?(\`|'s|\`'s)?[ ]?§[ ]?(\"[^\"]+\"|\`?[A-Za-z_][A-Za-z0-9_]*\`?)"

# cited_anchors — one "<normalized anchor>\t<file>" row per section citation of this doc in the
# tracked tree (CHANGELOG.md excluded). A quoted anchor left open at end of line is joined with
# the next line (its leading comment marker stripped), at most twice.
cited_anchors() {
  git -C "$REPO" grep -lE 'RESULT_SCHEMAS' -- . ':!CHANGELOG.md' | while IFS= read -r f; do
    awk '
      function open_quote(s,   t) { t = s; if (!sub(/.*§ ?"/, "", t)) return 0; return (index(t, "\"") == 0) }
      {
        buf = $0; k = 0
        while (open_quote(buf) && k < 2 && (getline nxt) > 0) {
          sub(/^[ \t]*(#|\/\/|\*|--|>)?[ \t]*/, "", nxt); buf = buf " " nxt; k++
        }
        print buf
      }' "$REPO/$f" \
      | grep -oE "$CITE_RE" \
      | sed -E 's/^[^§]*§ ?//; s/^"//; s/"$//' \
      | norm \
      | awk -v F="$f" 'NF {print $0 "\t" F}'
  done | sort -u
}

# anchor_rows <index> — one "<normalized anchor>\t<split file>" row per table row of the
# `## Cited sub-section anchors` block.
anchor_rows() {
  awk -v A="$ANCHOR_H" '$0 == A {in_a = 1; next} in_a && /^## / {in_a = 0} in_a && /^\| / {print}' "$1" \
    | sed -nE 's/^\| (.*[^ ]) +\| \[result-schemas\/([^]]+)\]\(result-schemas\/([^)]+)\) \|$/\1	\2	\3/p' \
    | while IFS="$(printf '\t')" read -r a l t; do
        if [ "$l" = "$t" ]; then printf '%s\t%s\n' "$(printf '%s\n' "$a" | norm)" "$l"
        else printf '%s\t%s\n' "$(printf '%s\n' "$a" | norm)" "$l|MISMATCH|$t"; fi
      done
}

# matches <text> <anchor> — 0 iff text equals the anchor or starts with it at a word boundary.
matches() { case "$1" in "$2"|"$2 "*) return 0 ;; esac; return 1; }

# check_cites <index> <dir> <cites-file> — one line per problem; returns 0 iff none.
check_cites() {
  local idx="$1" dir="$2" cites="$3" probs=0 x src h a f hit
  local ih="$TMP/cih.$$" rows="$TMP/crows.$$"
  strip_anchors "$idx" | grep -E '^## ' | sed 's/^## //' | norm > "$ih"
  anchor_rows "$idx" > "$rows"
  while IFS="$(printf '\t')" read -r x src; do
    hit=0
    while IFS= read -r h; do matches "$h" "$x" && { hit=1; break; }; done < "$ih"
    [ "$hit" = 1 ] && continue
    f=""
    while IFS="$(printf '\t')" read -r a f; do [ "$a" = "$x" ] && { hit=1; break; }; done < "$rows"
    if [ "$hit" != 1 ]; then
      echo "    '$x' (cited in $src) is not a top-level index heading and has no '$ANCHOR_H' row"; probs=$((probs+1)); continue
    fi
    case "$f" in *"|MISMATCH|"*) echo "    '$x': anchors row link text and target differ ($f)"; probs=$((probs+1)); continue ;; esac
    if [ ! -f "$dir/$f" ]; then echo "    '$x': anchors row names result-schemas/$f, which does not exist"; probs=$((probs+1)); continue; fi
    hit=0
    while IFS= read -r h; do matches "$h" "$x" && { hit=1; break; }; done < <(all_headings "$dir/$f")
    [ "$hit" = 1 ] || { echo "    '$x': result-schemas/$f holds no heading with that text"; probs=$((probs+1)); }
  done < "$cites"
  [ "$probs" -eq 0 ]
}

echo "== result-schemas split: real tree =="
[ -f "$INDEX" ] && ok "index exists: docs/RESULT_SCHEMAS.md" || no "index missing: $INDEX"
nfiles="$(bash -c 'shopt -s nullglob; set -- "$1"/*.md; echo $#' _ "$SPLIT_DIR")"
[ "$nfiles" -gt 0 ] && ok "split dir holds $nfiles file(s)" || no "split dir empty or missing: $SPLIT_DIR"
strip_anchors "$INDEX" > "$TMP/index-pointers.md"
nh="$(headings "$TMP/index-pointers.md" | wc -l | tr -d ' ')"
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

echo "== F. cited sub-section anchors =="
na="$(headings "$INDEX" | grep -cxF -- "$ANCHOR_H")"
last="$(headings "$INDEX" | tail -1)"
if [ "$na" = "1" ] && [ "$last" = "$ANCHOR_H" ]; then
  ok "F0: the index has exactly one '$ANCHOR_H' block, after every schema pointer"
else
  no "F0: '$ANCHOR_H' appears $na time(s); last top-level heading is '$last'"
fi
CITES="$TMP/cites.tsv"
if git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  cited_anchors > "$CITES"
  ncite="$(wc -l < "$CITES" | tr -d ' ')"
  [ "$ncite" -gt 0 ] && ok "F1: found $ncite distinct (anchor, file) section citations of RESULT_SCHEMAS in the tracked tree" \
    || no "F1: found no section citations of RESULT_SCHEMAS in the tracked tree - the scan is broken"
  nrows="$(anchor_rows "$INDEX" | wc -l | tr -d ' ')"
  [ "$nrows" -gt 0 ] && ok "F2: the anchors block holds $nrows parseable row(s)" || no "F2: the anchors block has no parseable rows"
  if out="$(check_cites "$INDEX" "$SPLIT_DIR" "$CITES")"; then
    ok "F3: every cited anchor is a top-level index heading or an anchors row naming a split file that holds it"
  else
    no "F3: cited anchors that do not resolve from the index:"; printf '%s\n' "$out"
  fi
  # Mutant 4 — the first anchors row removed.
  M4="$TMP/index-anchor-row-removed.md"
  awk -v A="$ANCHOR_H" '$0 == A {in_a = 1} in_a && !d && /^\| .*\[result-schemas\//{d = 1; next} {print}' "$INDEX" > "$M4"
  if [ -s "$M4" ] && ! cmp -s "$M4" "$INDEX" && [ "$(anchor_rows "$M4" | wc -l | tr -d ' ')" -lt "$nrows" ]; then
    if check_cites "$M4" "$SPLIT_DIR" "$CITES" >/dev/null; then
      no "MUTATION CONTROL: an anchors block with one row removed was ACCEPTED"
    else
      ok "MUTATION CONTROL: an anchors block with one row removed is REJECTED"
    fi
  else
    no "could not build the anchor-row-removed mutant - this control is inconclusive"
  fi
  # Mutant 5 — the first anchors row re-pointed to a split file that does not hold its anchor.
  M5="$TMP/index-anchor-row-repointed.md"
  awk -v A="$ANCHOR_H" '$0 == A {in_a = 1}
    in_a && !d && /^\| .*\[result-schemas\// {
      sub(/\[result-schemas\/[^]]+\]\(result-schemas\/[^)]+\)/, "[result-schemas/schema-versioning.md](result-schemas/schema-versioning.md)"); d = 1
    } {print}' "$INDEX" > "$M5"
  if [ -s "$M5" ] && ! cmp -s "$M5" "$INDEX"; then
    if check_cites "$M5" "$SPLIT_DIR" "$CITES" >/dev/null; then
      no "MUTATION CONTROL: an anchors row naming the wrong split file was ACCEPTED"
    else
      ok "MUTATION CONTROL: an anchors row naming the wrong split file is REJECTED"
    fi
  else
    no "could not build the anchor-row-repointed mutant - this control is inconclusive"
  fi
else
  no "F: $REPO is not a git work tree - cannot list tracked citations (never read as clean)"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
