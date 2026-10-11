#!/usr/bin/env bash
# assemble.sh — print the documented-order text of a split /automate engine surface
# (parallel-automate/22). Test support for scripts/test-automate-loop-split.sh and the
# tests that read the split surfaces; nothing at runtime calls it.
#
#   bash assemble.sh <index-file> [<out-file>]   # the assembled text (stdout, or <out-file>)
#   bash assemble.sh --files <index-file>        # the split files, one path per line, in order
#
# The three split surfaces — skills/automate-loop/SKILL.md, commands/automate.md and
# docs/result-schemas/automate-run.md — each stay an INDEX at their old path. An index holds
# two kinds of marker block, each marker alone on its line:
#
#   <!-- split:begin <file> -->  …index entries…  <!-- split:end <file> -->
#       The section(s) moved verbatim to <file> (a path relative to the index's directory).
#       Assembling replaces the whole block, both marker lines included, with <file>'s bytes.
#   <!-- index-only:begin -->  …  <!-- index-only:end -->
#       Prose that exists only in the index (a note, a Step 0 read list). Assembling drops it.
#
# Every other line of the index is copied through unchanged. The DOCUMENTED ORDER is the order
# of the split:begin markers in the index, so the assembled text is the index's own segments
# and the split files, interleaved where the sections sat before the split.
#
# SPLIT FILE PATHS: a relative *.md path of [A-Za-z0-9._/-] characters — no leading `/`, no `//`,
# no `.` segment. A `..` segment is allowed ONLY as one or more LEADING `../` segments (so
# commands/automate.md can name ../skills/automate-loop/command-lanes.md); a `..` anywhere after a
# named segment (`foo/../bar.md`) is refused. A path that climbs is BOUNDED: the directory it climbs
# to (physical, symlinks resolved) must stay inside the PLUGIN ROOT — the nearest ancestor of the
# index's directory holding .claude-plugin/plugin.json (loomwright/ for every index in this repo).
# An index with no such ancestor may not climb at all. A path that does not climb stays under the
# index's own directory by construction.
#
# Fail-CLOSED: an unreadable index; a split:begin inside another block; a split:end that does
# not close the open split:begin of the same file; an index-only marker out of place; a block
# left open at EOF; a split file path that breaks the rule above (a `..` past the plugin root
# included); a split file that is missing, unreadable, empty or does not end with a newline — each prints one
# `assemble: <reason>` line to stderr and exits 1 with NOTHING on stdout and no <out-file>
# written, so a caller can never grep a half-assembled text and read it as clean.
# bash 3.2 + BSD awk compatible. Read-only toward the repo; one mktemp scratch file.
set -uo pipefail
export LC_ALL=C

die() { echo "assemble: $*" >&2; exit 1; }

mode=text
if [ "${1:-}" = "--files" ]; then mode=files; shift; fi
idx="${1:-}"
out="${2:-}"
[ -n "$idx" ] || die "usage: assemble.sh [--files] <index-file> [<out-file>]"
[ -f "$idx" ] && [ -r "$idx" ] || die "index not readable: $idx"
dir="$(cd "$(dirname "$idx")" && pwd)" || die "index directory not readable: $idx"
pdir="$(cd "$dir" && pwd -P)" || die "index directory not readable: $idx"
# The plugin root that bounds a climbing (`../`) split path; empty = the index may not climb.
root="$pdir"
while [ ! -f "$root/.claude-plugin/plugin.json" ]; do
  [ "$root" = "/" ] && { root=""; break; }
  root="$(dirname "$root")"
done

tmp="$(mktemp "${TMPDIR:-/tmp}/assemble.XXXXXX")" || die "mktemp failed"
trap 'rm -f "$tmp"' EXIT

# One awk pass. In --files mode it prints each resolved split-file path instead of its bytes.
# A split file's last byte is checked before it is read: awk's getline drops the final newline
# and print adds one back, so a file without one would gain a byte here.
awk -v dir="$dir" -v pdir="$pdir" -v root="$root" -v mode="$mode" '
  function fail(msg) { print "assemble: " FILENAME ":" NR ": " msg > "/dev/stderr"; bad = 1; exit 1 }
  function emit(f,   p, line, r, n, cmd, last, rest, ups, base) {
    if (f !~ /^[A-Za-z0-9._\/-]+\.md$/ || f ~ /^\// || f ~ /(^|\/)\.\// || f ~ /\/\//) fail("not a plain relative *.md path: " f)
    # `..` only as leading `../` segments, and the climb must stay inside the plugin root.
    rest = f; ups = 0
    while (substr(rest, 1, 3) == "../") { rest = substr(rest, 4); ups++ }
    if (rest ~ /(^|\/)\.\.(\/|$)/) fail("a .. segment after a named segment: " f)
    if (ups > 0) {
      if (root == "") fail("climbing split path but no plugin root (.claude-plugin/plugin.json) above the index: " f)
      base = pdir
      while (ups-- > 0) { if (base == "/" || base == "") fail("split path climbs past /: " f); sub(/\/[^\/]*$/, "", base); if (base == "") base = "/" }
      if (base != root && index(base "/", root "/") != 1) fail("split path climbs out of the plugin root " root ": " f)
    }
    p = dir "/" f
    if (mode == "files") { print p; return }
    cmd = "tail -c 1 \"" p "\" 2>/dev/null | od -An -c"
    last = ""; cmd | getline last; close(cmd)
    gsub(/[ \t]/, "", last)
    if (last != "\\n") fail("split file missing, empty or without a final newline: " f)
    n = 0
    while ((r = (getline line < p)) > 0) { print line; n++ }
    close(p)
    if (r < 0 || n == 0) fail("split file unreadable or empty: " f)
  }
  {
    if ($0 ~ /^<!-- split:begin [^ ]+ -->$/) {
      if (state != "") fail("split:begin inside an open " state " block")
      open = $3; state = "split"; emit(open); next
    }
    if ($0 ~ /^<!-- split:end [^ ]+ -->$/) {
      if (state != "split" || $3 != open) fail("split:end " $3 " does not close the open block (" (state == "" ? "none" : state " " open) ")")
      state = ""; next
    }
    if ($0 == "<!-- index-only:begin -->") { if (state != "") fail("index-only:begin inside an open " state " block"); state = "index-only"; next }
    if ($0 == "<!-- index-only:end -->") { if (state != "index-only") fail("index-only:end with no open index-only block"); state = ""; next }
    if (state != "") next
    if (mode == "text") print
  }
  END { if (bad) exit 1; if (state != "") { print "assemble: " FILENAME ": " state " block left open at EOF" > "/dev/stderr"; exit 1 } }
' "$idx" > "$tmp" || exit 1

[ -s "$tmp" ] || [ "$mode" = "files" ] || die "assembled text is empty: $idx"
if [ -n "$out" ]; then
  cp "$tmp" "$out" || die "cannot write $out"
else
  cat "$tmp"
fi
