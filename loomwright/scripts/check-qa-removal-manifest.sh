#!/usr/bin/env bash
# check-qa-removal-manifest.sh — check the repo against the reviewed QA-removal manifest, row by row.
#
# WHY: the old QA system is removed in three PRs (items 11b1, 11b2, 12). "grep returns nothing" was the
# only done-check, which is how a reference gets missed or the wrong file goes. The manifest
# (loomwright/docs/qa-removal-manifest.md) is the reviewed list; this script turns it into a per-row
# pass/fail gate, so each removal PR is checked against an approved list rather than a one-off grep.
#
# USAGE
#   check-qa-removal-manifest.sh [--expect <11b1|11b2|12>] [--manifest <file>] [--root <dir>]
#     --expect    gate mode: check every row whose item is at or before <item> (order 11b1 < 11b2 < 12).
#                 Absent: report-only mode — every row is reported, nothing fails.
#     --manifest  the manifest file (default: loomwright/docs/qa-removal-manifest.md under the root;
#                 a relative value is read relative to the current directory).
#     --root      the tree the manifest's paths are checked in (default: the repo root this script
#                 lives in).
#
# MANIFEST FORMAT (the contract the manifest is written to; anything else is REFUSED, never skipped):
#   - exactly one column-0 line `Row count: <N>` outside a code fence, before the table; <N> must equal
#     the number of data rows.
#   - one table under the heading `## Rows`: header exactly `| path | reference | action | item | reason |`,
#     the next line a `|---|…` separator, then one data row per entry, every row starting and ending
#     with `|`. `\|` inside a cell reads as a literal `|`. The table ends at the first line that does
#     not start with `|`; a further `|` line before the next heading is refused.
#     path       repo-relative file or directory in backticks: no leading `/`, no `.` or `..` part
#                (so no leading `./`), no `//` — one spelling per path, so duplicates are caught.
#     reference  the named old string in backticks (a double-backtick code span may carry a backtick),
#                or `—` for a whole-path row.
#     action     delete | re-point | keep.
#     item       11b1 | 11b2 | 12.
#     reason     one non-empty line.
#   - refused rows: an unknown action or item; a wrong cell count; a malformed path or reference; an
#     empty reason; a `delete` row with a reference (a delete row removes the whole path); a `re-point`
#     row without one (there would be nothing to check); a duplicate (path, reference, action); and two
#     rows naming the same (path, reference) with different actions (a `keep` beside a `re-point` or a
#     `delete` is a contradiction). A path's trailing `/` is ignored when comparing rows. A table with
#     zero data rows is refused too: a fail-closed gate over nothing is a false green.
#
# PER ROW (a row is SELECTED when --expect is given and its item is at or before the --expect item):
#   delete    path exists ⇒ `pending` (`MISMATCH` when selected); absent ⇒ `done`.
#   keep      path present and (when a reference is given) the file, or any file under the directory,
#             still contains the reference (`grep -F`) ⇒ `ok`; otherwise `pending` (`MISMATCH` when
#             selected).
#   re-point  the file no longer contains the reference ⇒ `done`; it still does, or the file is
#             missing or unreadable ⇒ `pending` — `MISMATCH` only when selected at `--expect 12`
#             (re-point rows are checked at 12 alone, whatever their item).
#   A grep that cannot read the file never reads as "absent": fail closed toward `pending`.
#
# OUTPUT (stdout): one line per row in manifest order, `<status> <action> <item> <path>` plus
#   ` :: <reference>` when the row has one, then one summary line
#   `summary: <N> rows, expect <item|none>: <m> MISMATCH, <p> pending, <d> done, <o> ok`.
#   Each MISMATCH also gets a one-line reason on stderr.
# EXIT: 0 clean (or report-only mode), 1 at least one MISMATCH, 2 a refused manifest or bad usage — the
#   reason (and the offending manifest line number) named on stderr, no row output.
#
# HONEST LIMITS: existence is the filesystem's answer (`[ -e ]`), so an untracked leftover reads as
# present and, on a case-insensitive filesystem, a differently-cased file does too — both fail toward
# MISMATCH, never toward a false pass. A reference is a fixed string per line; a reference split across
# lines, or built at runtime from parts, is invisible to it (the manifest names such files by row).
#
# Self-test: test-check-qa-removal-manifest.sh (offline fixtures in a `mktemp -d` root).
# Portability: bash 3.2 / BSD userland safe. No mapfile, no associative arrays, no GNU-only flags.

set -uo pipefail
SELF="check-qa-removal-manifest"

usage() {
  printf 'usage: %s [--expect <11b1|11b2|12>] [--manifest <file>] [--root <dir>]\n' "$SELF"
}
die() { printf '%s: REFUSED — %s\n' "$SELF" "$1" >&2; exit 2; }

# rank <item> — the item's position in 11b1 < 11b2 < 12; 0 for anything else.
rank() {
  case "$1" in
    11b1) echo 1 ;;
    11b2) echo 2 ;;
    12) echo 3 ;;
    *) echo 0 ;;
  esac
}

expect=""; expect_set=0; manifest=""; root=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --expect)
      [ "$#" -ge 2 ] || die "--expect needs a value (11b1, 11b2 or 12)"
      expect="$2"; expect_set=1; shift 2 ;;
    --expect=*) expect="${1#--expect=}"; expect_set=1; shift ;;
    --manifest)
      [ "$#" -ge 2 ] || die "--manifest needs a file"
      manifest="$2"; shift 2 ;;
    --manifest=*) manifest="${1#--manifest=}"; shift ;;
    --root)
      [ "$#" -ge 2 ] || die "--root needs a directory"
      root="$2"; shift 2 ;;
    --root=*) root="${1#--root=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
done

if [ "$expect_set" = 1 ]; then
  case "$expect" in
    11b1|11b2|12) ;;
    *) die "unknown --expect value '$expect' (expected 11b1, 11b2 or 12)" ;;
  esac
fi
expect_rank="$(rank "$expect")"

if [ -z "$root" ]; then
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || die "cannot resolve the repo root"
fi
[ -d "$root" ] || die "root is not a directory: $root"
root="$(cd "$root" && pwd)" || die "cannot enter root: $root"
[ -n "$manifest" ] || manifest="$root/loomwright/docs/qa-removal-manifest.md"
[ -f "$manifest" ] || die "manifest not found: $manifest"
[ -r "$manifest" ] || die "manifest not readable: $manifest"

US="$(printf '\037')"

# ---- parse + validate (one awk pass) ---------------------------------------------------------------
# Emits `R<US><lineno><US><path><US><reference><US><action><US><item>` per data row, and
# `E<US><message>` per refusal. Any E line refuses the whole manifest.
parsed="$(env LC_ALL=C awk -v US="$US" '
  function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
  function err(msg) { print "E" US msg; nerr++ }
  # unspan(cell) — the inside of a backtick code span, or the sentinel "\002" when cell is not one.
  function unspan(c,    n, inner) {
    n = 0
    while (substr(c, n + 1, 1) == "`") n++
    if (n == 0 || length(c) <= 2 * n) return "\002"
    if (substr(c, length(c) - n + 1) != substr(c, 1, n)) return "\002"
    if (substr(c, length(c) - n, 1) == "`") return "\002"
    inner = substr(c, n + 1, length(c) - 2 * n)
    if (n == 1 && index(inner, "`")) return "\002"
    if (n > 1 && inner ~ /^ .* $/) inner = substr(inner, 2, length(inner) - 2)
    if (inner == "") return "\002"
    return inner
  }
  BEGIN { HDR = "| path | reference | action | item | reason |" }
  /^[ \t]*```/ { fence = !fence; if (state == 2) state = 3; next }
  fence { next }
  /^Row count:/ {
    nrc++
    if ($0 ~ /^Row count: [0-9]+[ \t]*$/) { rc = $3 + 0 } else { err("line " NR ": malformed row-count line (want `Row count: <N>`): " $0) }
    if (seen_table) err("line " NR ": the `Row count:` line must come before the table")
    next
  }
  /^##?[ \t]/ {
    if (state == 2 || state == 3) state = 4
    if ($0 ~ /^##[ \t]+Rows[ \t]*$/) {
      if (nrows_heading++) { err("line " NR ": a second `## Rows` heading") } else { state = 1 }
    }
    next
  }
  state == 1 {
    if ($0 ~ /^[ \t]*$/) next
    seen_table = 1
    if ($0 != HDR) { err("line " NR ": the `## Rows` table header must be exactly `" HDR "`, got: " $0); state = 4; next }
    state = 5; next
  }
  state == 5 {
    if ($0 !~ /^\|[ :|-]*-[ :|-]*\|[ \t]*$/) { err("line " NR ": the line after the table header must be a `|---|` separator, got: " $0); state = 4; next }
    state = 2; next
  }
  state == 2 && $0 !~ /^\|/ { state = 3; next }
  state == 3 && $0 ~ /^[ \t]*\|/ { err("line " NR ": a table row after the `## Rows` table ended (a blank or non-table line split it): " $0); next }
  state == 2 {
    nrows++
    line = $0
    gsub(/\\\|/, "\001", line)
    sub(/[ \t]+$/, "", line)
    if (line !~ /^\|.*\|$/) { err("line " NR ": a row must start and end with `|`: " $0); next }
    line = substr(line, 2, length(line) - 2)
    if (index(line, "\t")) { err("line " NR ": a row must not contain a tab: " $0); next }
    n = split(line, cell, "|")
    if (n != 5) { err("line " NR ": want 5 cells (path, reference, action, item, reason), got " n ": " $0); next }
    for (i = 1; i <= 5; i++) { cell[i] = trim(cell[i]); gsub(/\001/, "|", cell[i]) }
    path = unspan(cell[1])
    if (path == "\002") { err("line " NR ": path must be one backticked repo-relative path: " cell[1]); next }
    if (path ~ /^\// || path ~ /(^|\/)\.\.?(\/|$)/ || path ~ /\/\// || path ~ /^[ \t]|[ \t]$/) {
      err("line " NR ": path must be repo-relative with no leading `/`, no `.` or `..` part and no `//`: " path); next
    }
    if (cell[2] == "—") { ref = "" }
    else { ref = unspan(cell[2]); if (ref == "\002") { err("line " NR ": reference must be a backticked string or `—`: " cell[2]); next } }
    act = cell[3]; item = cell[4]
    if (act == "delete") { if (ref != "") { err("line " NR ": a `delete` row removes the whole path, so its reference must be `—`: " path " :: " ref); next } }
    else if (act == "re-point") { if (ref == "") { err("line " NR ": a `re-point` row needs a reference to check: " path); next } }
    else if (act == "keep") { }
    else { err("line " NR ": unknown action `" act "` (want delete, re-point or keep): " path); next }
    if (item == "11b1" || item == "11b2" || item == "12") { }
    else { err("line " NR ": unknown item `" item "` (want 11b1, 11b2 or 12): " path); next }
    if (cell[5] == "") { err("line " NR ": empty reason: " path); next }
    norm = path; sub(/\/+$/, "", norm)
    key = norm SUBSEP ref
    if ((key, act) in row_at) { err("line " NR ": duplicate (path, reference) row — same as line " row_at[key, act] ": " path (ref == "" ? "" : " :: " ref)); next }
    if (key in act_at && act_at[key] != act) { err("line " NR ": conflicting actions " act_at[key] "/" act " on the same (path, reference) as line " line_at[key] ": " path (ref == "" ? "" : " :: " ref)); next }
    row_at[key, act] = NR; act_at[key] = act; line_at[key] = NR
    print "R" US NR US path US ref US act US item
    next
  }
  END {
    if (fence) err("an unclosed code fence")
    if (!nrows_heading) err("no `## Rows` heading")
    else if (!seen_table) err("no table under `## Rows`")
    else if (state == 5) err("the `## Rows` table header has no `|---|` separator line")
    else if (nrows == 0) err("the `## Rows` table has no data rows")
    if (nrc == 0) err("no column-0 `Row count: <N>` line")
    else if (nrc > 1) err(nrc " `Row count:` lines (want exactly one)")
    else if (rc != nrows) err("header `Row count: " rc "` but the table has " nrows " data rows")
  }
' "$manifest" 2>&1)" || die "cannot parse manifest: $manifest"

refusals="$(grep "^E$US" <<<"$parsed" || true)"
if [ -n "$refusals" ]; then
  printf '%s\n' "$refusals" | while IFS= read -r r; do
    printf '%s: REFUSED manifest %s — %s\n' "$SELF" "$manifest" "${r#E"$US"}" >&2
  done
  exit 2
fi
grep -q "^R$US" <<<"$parsed" || die "no data rows parsed from manifest: $manifest"

# ---- check each row -------------------------------------------------------------------------------
# exists <abs> — the path is there (a dangling symlink counts: it is still a path to delete).
exists() { [ -e "$1" ] || [ -L "$1" ]; }
# has_ref <abs> <ref> — grep's own status for "<abs> contains <ref>" as a fixed string: 0 yes, 1 no,
# 2 unreadable. A directory is searched recursively through `<dir>/.`, so a symlinked directory is
# followed (BSD grep -r does not follow a symlink operand by default).
has_ref() {
  if [ -d "$1" ]; then grep -r -F -q -e "$2" -- "$1/." 2>/dev/null; return $?; fi
  grep -F -q -e "$2" -- "$1" 2>/dev/null
}

total=0; n_mis=0; n_pend=0; n_done=0; n_ok=0
while IFS="$US" read -r tag lineno path ref act item; do
  [ "$tag" = "R" ] || continue
  total=$((total + 1))
  abs="$root/$path"
  sel=0
  if [ "$expect_set" = 1 ] && [ "$(rank "$item")" -le "$expect_rank" ]; then sel=1; fi
  st=""; why=""
  case "$act" in
    delete)
      st="done"
      if exists "$abs"; then
        st=pending; why="path still exists"
        if [ "$sel" = 1 ]; then st=MISMATCH; fi
      fi ;;
    keep)
      st=ok
      if ! exists "$abs"; then
        st=pending; why="kept path is missing"
        if [ "$sel" = 1 ]; then st=MISMATCH; fi
      elif [ -n "$ref" ]; then
        grc=0; has_ref "$abs" "$ref" || grc=$?   # the keep row's grep -F reference check
        if [ "$grc" -ne 0 ]; then
          st=pending; why="no longer contains the kept reference (grep exit $grc)"
          if [ "$sel" = 1 ]; then st=MISMATCH; fi
        fi
      fi ;;
    re-point)
      st="done"; grc=1
      if ! exists "$abs"; then grc=3; why="re-point file is missing"; fi
      if [ "$grc" -eq 1 ]; then has_ref "$abs" "$ref"; grc=$?; fi   # the re-point row's grep -F reference check
      if [ "$grc" -eq 0 ]; then why="still names the reference"; fi
      if [ "$grc" -eq 2 ]; then why="re-point file is unreadable"; fi
      if [ "$grc" -ne 1 ]; then st=pending; fi
      if [ "$sel" = 1 ] && [ "$expect" = 12 ] && [ "$st" = pending ]; then st=MISMATCH; fi ;;
  esac
  case "$st" in
    MISMATCH) n_mis=$((n_mis + 1))
      printf '%s: MISMATCH %s %s %s%s — %s (manifest line %s)\n' "$SELF" "$act" "$item" "$path" \
        "${ref:+ :: $ref}" "$why" "$lineno" >&2 ;;
    pending) n_pend=$((n_pend + 1)) ;;
    done) n_done=$((n_done + 1)) ;;
    ok) n_ok=$((n_ok + 1)) ;;
  esac
  printf '%s %s %s %s%s\n' "$st" "$act" "$item" "$path" "${ref:+ :: $ref}"
done <<EOF
$parsed
EOF

printf 'summary: %s rows, expect %s: %s MISMATCH, %s pending, %s done, %s ok\n' \
  "$total" "${expect:-none}" "$n_mis" "$n_pend" "$n_done" "$n_ok"

if [ "$expect_set" = 0 ]; then exit 0; fi   # report-only mode never fails
if [ "$n_mis" -gt 0 ]; then exit 1; fi
exit 0
