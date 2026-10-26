#!/usr/bin/env bash
# module-shape-facts.sh — structural FACTS about a diff for the Phase 4.5 review lens (the
# MODULE-SHAPE ADVISORY line, `skills/self-heal-advisory/SKILL.md` step 1h). Facts only: it holds
# NO size threshold and judges nothing — "large" is `skills/supervisor-readiness/SKILL.md`
# §"Module layout" (or a house rule), and the judgement is `agents/code-reviewer.md` step 5d.
#
# Read-only, like classify-risk.sh: it never writes outside its own mktemp dir, never `cd`s into
# --root (every git call is `git -C "$root"`), and never executes content it reads (no eval /
# source; names are matched with awk and `grep -F` only).
#
# Usage:
#   module-shape-facts.sh <base_ref> [<head_ref>] [--root <dir>]   # head default HEAD, root default .
#
# Output (stdout, plain text; NOTHING when there are no facts):
#   module-shape facts (base <base>, head <head>; facts only — no size threshold applied):
#   lines: <path> <before> -> <after>        one per touched text file; <before> is `new` for an
#                                            added file; `wc -l` of the blob at the merge base / head
#   shared-name: <name> defined in <N> files: <f1>, <f2>, … (+K more)
#                                            one per name the diff ADDS a definition of that is
#                                            defined in 2+ files at <head>, repo-wide
#   Lists are capped (FILE_CAP / NAME_CAP / WHERE_CAP below), each with a visible `(+N more …)`
#   marker, so a conventional per-file harness helper defined in many files reads as what it is.
#   The diff is three-dot (`<base>...<head>`, i.e. merge base → head), the scope the reviewer judges.
#
# Failure mode: fail-SAFE emitter — ALWAYS exit 0. When it cannot produce facts it prints NOTHING on
# stdout and ONE line on stderr, `module-shape-facts.sh: no facts — <reason> (<detail>)`, with
# <reason> one of: bad_args | not_a_git_repo | bad_ref | git_failed | no_changes | binary_only |
# deleted_only | no_text_files. A consumer must read empty stdout as "facts unavailable", never as
# "no structural issue" (CLAUDE.md §"Failure-Mode Invariants": a fail-SAFE reader consumed by a lens).
# A failed repo-wide name scan keeps the line facts and adds `names_unavailable` on stderr.
#
# Definition detection — approximate and language-agnostic by design (a false positive costs
# reviewer judgement only, never a gate). A definition line is one of:
#   `function <name>` (shell, JS/TS; any non-identifier character or line start before `function`)
#   `def <name>` / `async def <name>` at line start (Python)
#   `const|let|var <name> = ` followed by `function`, `(`, `async` or `<param> =>` (JS/TS)
#   `<name>()` at line start — shell files only (`.sh`/`.bash`/`.zsh`/`.bats`/`.ksh` or no extension),
#     so a JS method or a call in another language is not read as a definition
# Names are `[A-Za-z_][A-Za-z0-9_]*`. Documentation files (`.md`/`.markdown`/`.mdx`/`.txt`/`.rst`/
# `.adoc`) never define a name. A name counts as ADDED by the diff when a `+` line defines it in a
# file and no `-` line of that same file defined it (a changed signature is not a new definition).
#
# HONEST LIMITS: regex, not a parser — a definition inside a string or a heredoc counts, a
# multi-line `const x =\n (` does not, methods/classes are not read, and two unrelated functions that
# share a name read as one. Line counts use `wc -l` (a last line with no newline is not counted).
# Renames read as delete + add (`--no-renames`). Submodules and other non-blob entries at <head> are
# skipped; a non-blob entry at the merge base (a directory, a submodule) reads `new`.
#
# Load-bearing lines carry a trailing `pin:` comment naming the behaviour, each on ONE
# self-contained line so deleting it keeps `bash -n` valid; test-module-shape-facts.sh turns red on
# each deletion (the brief's `## Pin mutations`).
#
# Co-located static suite: test-module-shape-facts.sh.

set -uo pipefail
export LC_ALL=C
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY 2>/dev/null || true

SELF="module-shape-facts.sh"
FILE_CAP=40    # touched files listed
NAME_CAP=20    # shared names listed
WHERE_CAP=5    # files listed per shared name

no_facts() {  # $1 = reason token (fixed literal), $2 = detail — stderr only, stdout stays empty
  printf '%s: no facts — %s (%s)\n' "$SELF" "$1" "$2" >&2
  exit 0
}

# ---------------------------------------------------------------------------
# Arg parse
# ---------------------------------------------------------------------------
base=""
head=""
root="."
npos=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      [ $# -ge 2 ] || no_facts "bad_args" "--root needs a directory argument"
      root="$2"; shift 2 ;;
    --root=*) root="${1#--root=}"; shift ;;
    -h|--help)
      printf 'usage: %s <base_ref> [<head_ref>] [--root <dir>]\n' "$SELF" >&2
      exit 0 ;;
    --*) no_facts "bad_args" "unknown option $1" ;;
    *)
      if [ "$npos" -eq 0 ]; then base="$1"; npos=1
      elif [ "$npos" -eq 1 ]; then head="$1"; npos=2
      else no_facts "bad_args" "unexpected argument"
      fi
      shift ;;
  esac
done
[ -n "$base" ] || no_facts "bad_args" "need <base_ref>"
[ -n "$head" ] || head="HEAD"
[ -n "$root" ] || no_facts "bad_args" "--root must not be empty"

# ---------------------------------------------------------------------------
# Guards (read-only, git -C — never cd)
# ---------------------------------------------------------------------------
git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || no_facts "not_a_git_repo" "root=$root"  # pin: not-a-repo-guard
git -C "$root" rev-parse --verify --quiet "$base^{commit}" >/dev/null 2>&1 || no_facts "bad_ref" "base ref not found: $base"  # pin: base-ref-guard
git -C "$root" rev-parse --verify --quiet "$head^{commit}" >/dev/null 2>&1 || no_facts "bad_ref" "head ref not found: $head"
mb="$(git -C "$root" merge-base "$base" "$head" 2>/dev/null)" || no_facts "git_failed" "no merge base for $base and $head"
# Every later call runs from the top level: a --root below it would scope the repo-wide name scan
# (git grep) to that subdirectory.
root="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)" || no_facts "git_failed" "cannot resolve the top level of the repo"

tmp="$(mktemp -d 2>/dev/null)" || no_facts "git_failed" "mktemp failed"
trap 'rm -rf "$tmp"' EXIT
: > "$tmp/binary"; : > "$tmp/text"; : > "$tmp/lines"; : > "$tmp/names"

G() { git -C "$root" -c core.quotePath=false "$@"; }

G diff --no-renames --no-ext-diff --name-status -z "$base...$head" > "$tmp/status" 2>"$tmp/err" || no_facts "git_failed" "$(head -c 200 "$tmp/err" | tr '\n' ' ')"  # pin: all-touched-paths
G diff --no-renames --no-ext-diff --numstat -z "$base...$head" > "$tmp/numstat" 2>"$tmp/err" || no_facts "git_failed" "$(head -c 200 "$tmp/err" | tr '\n' ' ')"

# Binary paths: numstat prints `-<TAB>-<TAB><path>` for them.
TAB="$(printf '\t')"
while IFS= read -r -d '' rec; do
  case "$rec" in "-${TAB}-${TAB}"*) printf '%s\n' "${rec#-${TAB}-${TAB}}" >> "$tmp/binary" ;; esac
done < "$tmp/numstat"

# ---------------------------------------------------------------------------
# Per touched file: skip deleted / binary / non-blob, record the line count before -> after.
# Two batched cat-file calls instead of several git processes per file.
# ---------------------------------------------------------------------------
n_files=0; n_del=0; n_bin=0; n_other=0
: > "$tmp/kept"
while IFS= read -r -d '' -u 3 st && IFS= read -r -d '' -u 3 p; do
  n_files=$((n_files + 1))
  [ "$st" = "D" ] && { n_del=$((n_del + 1)); continue; }  # pin: deleted-skip
  grep -qxF -- "$p" "$tmp/binary" && { n_bin=$((n_bin + 1)); continue; }  # pin: binary-skip
  printf '%s\n' "$p" >> "$tmp/kept"
done 3< "$tmp/status"

# Every cat-file spec below names <head> by its commit id, resolved once, so a branch that moves
# mid-run cannot hand the type check and the content stream two different trees.
hrev="$(G rev-parse --verify --quiet "$head^{commit}" 2>/dev/null)" || no_facts "git_failed" "cannot resolve head $head"

# Object type at <head>; anything but a blob (a submodule, a tree, a path gone at head) is skipped.
REV="$hrev" awk '{ print ENVIRON["REV"] ":" $0 }' "$tmp/kept" \
  | G cat-file --batch-check='%(objecttype)' 2>/dev/null > "$tmp/types"
OUT="$tmp" awk 'FILENAME == ARGV[1] { ty[FNR] = $0; next }
     { f = (ty[FNR] == "blob") ? "/text" : "/other"; print > (ENVIRON["OUT"] f) }' "$tmp/types" "$tmp/kept"
touch "$tmp/text" "$tmp/other"
n_other="$(grep -c . "$tmp/other" || true)"; n_other="${n_other:-0}"

# Object type at the merge base, so only blobs reach the content stream below: a tree (a directory
# at the base that is a file at head) or a gitlink's commit would print a payload the line counter
# reads as more records, shifting every later file's counts. A non-blob base entry reads `new`.
MB="$mb" awk '{ print ENVIRON["MB"] ":" $0 }' "$tmp/text" \
  | G cat-file --batch-check='%(objecttype)' 2>/dev/null > "$tmp/mbtypes"

# `wc -l` of each text path at the merge base and at head, from ONE `cat-file --batch` stream fed
# blob specs only: a blob's content is S bytes plus git's trailing LF, so lines are read until S+1
# bytes are consumed and the line count is the lines read minus one.
MB="$mb" HD="$hrev" awk 'FILENAME == ARGV[1] { ty[FNR] = $0; next }
     { if (ty[FNR] == "blob") print ENVIRON["MB"] ":" $0; print ENVIRON["HD"] ":" $0 }' "$tmp/mbtypes" "$tmp/text" \
  | G cat-file --batch='%(objecttype) %(objectsize)' 2>/dev/null \
  | awk '
      want > 0 { got += length($0) + 1; n++; if (got >= want) { print n - 1; want = 0 }; next }
      NF == 2 && $1 == "blob" { want = $2 + 1; got = 0; n = 0; next }
      { print "?" }
    ' > "$tmp/counts"
awk 'FILENAME == ARGV[1] { ty[FNR] = $0; next }
     FILENAME == ARGV[2] { c[FNR] = $0; next }
     { b = "new"; if (ty[FNR] == "blob") b = c[++k]; a = c[++k]; if (ty[FNR] == "") b = "?"
       if (b == "") b = "?"; if (a == "") a = "?"; print "lines: " $0 " " b " -> " a }' \
  "$tmp/mbtypes" "$tmp/counts" "$tmp/text" > "$tmp/lines"

if [ ! -s "$tmp/lines" ]; then
  if [ "$n_files" -eq 0 ]; then no_facts "no_changes" "diff $base...$head touches no file"
  elif [ "$n_bin" -gt 0 ] && [ "$n_del" -eq 0 ] && [ "$n_other" -eq 0 ]; then no_facts "binary_only" "every touched file is binary; no line count"
  elif [ "$n_del" -gt 0 ] && [ "$n_bin" -eq 0 ] && [ "$n_other" -eq 0 ]; then no_facts "deleted_only" "every touched file is deleted"
  else no_facts "no_text_files" "touched files are binary, deleted or not regular files"
  fi
fi

# ---------------------------------------------------------------------------
# Definition extraction — ONE awk program, used on diff lines and on the repo-wide scan alike.
# Each record is `<path><SOH><line text>`; prints `<path><TAB><name>` per definition (dedup later).
# ---------------------------------------------------------------------------
DEF_AWK='
function shellish(p) { return (p ~ /\.(sh|bash|zsh|bats|ksh)$/ || p !~ /\.[A-Za-z0-9]+$/) }
function docish(p) { return (p ~ /\.(md|markdown|mdx|txt|rst|adoc)$/) }
function defs(p, t,   s, r) {
  if (docish(p)) return
  r = t
  while (match(r, /(^|[^A-Za-z0-9_$.])function[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
    s = substr(r, RSTART, RLENGTH); sub(/^[^A-Za-z]*/, "", s); sub(/^function[ \t]+/, "", s)
    print p "\t" s
    r = substr(r, RSTART + RLENGTH)
  }
  if (match(t, /^[ \t]*(async[ \t]+)?def[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
    s = substr(t, RSTART, RLENGTH); sub(/^[ \t]*(async[ \t]+)?def[ \t]+/, "", s); print p "\t" s
  }
  if (match(t, /(^|[^A-Za-z0-9_$.])(const|let|var)[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*=[ \t]*(async[ \t(]|function|\(|[A-Za-z_$][A-Za-z0-9_$]*[ \t]*=>)/)) {
    s = substr(t, RSTART, RLENGTH); sub(/^[^A-Za-z]*/, "", s); sub(/^(const|let|var)[ \t]+/, "", s); sub(/[ \t]*=.*$/, "", s)
    print p "\t" s
  }
  if (shellish(p) && match(t, /^[ \t]*[A-Za-z_][A-Za-z0-9_]*[ \t]*\(\)/)) {
    s = substr(t, RSTART, RLENGTH); sub(/^[ \t]*/, "", s); sub(/[ \t]*\(\)$/, "", s)
    if (s != "function") print p "\t" s
  }
}
'

# Names the diff ADDS: `+` definitions per file, minus `-` definitions of the same file. The diff's
# header lines (between `diff --git` and the first `@@`) are skipped, so a content line that starts
# with `+++`/`---` is still read as content. Each line becomes `<A|R><path><SOH><text>`.
G diff --no-renames --no-ext-diff --no-color -U0 --src-prefix=a/ --dst-prefix=b/ "$base...$head" 2>/dev/null \
  | awk '
      /^diff --git / { hdr = 1; minus = ""; cur = ""; next }
      hdr && /^--- / { minus = substr($0, 5); sub(/^a\//, "", minus); next }
      hdr && /^\+\+\+ / { cur = substr($0, 5); sub(/^b\//, "", cur); if (cur == "/dev/null") cur = minus; next }
      /^@@/ { hdr = 0; next }
      hdr { next }
      /^\+/ { print "A" cur "\001" substr($0, 2); next }
      /^-/  { print "R" cur "\001" substr($0, 2); next }
    ' > "$tmp/diffdefs.in"
awk "$DEF_AWK"'{ i = index($0, "\001"); if (i > 1) defs(substr($0, 1, i - 1), substr($0, i + 1)) }' "$tmp/diffdefs.in" \
  | awk -F'\t' '
      { k = substr($1, 1, 1); p = substr($1, 2); key = p "\t" $2 }
      k == "A" { add[key] = $2 } k == "R" { rem[key] = 1 }
      END { for (key in add) if (!(key in rem)) print add[key] }
    ' | sort -u > "$tmp/added_names"

# Repo-wide definitions at <head>: one git grep prefilter, the SAME extractor, deduplicated.
names_ok=1
G -c grep.lineNumber=false -c grep.column=false grep -I -z --no-color -E \
  -e 'function[[:space:]]' -e '\(\)' -e '(const|let|var)[[:space:]]' -e 'def[[:space:]]' \
  "$head" -- ':(exclude)*.md' ':(exclude)*.markdown' ':(exclude)*.mdx' ':(exclude)*.txt' \
  ':(exclude)*.rst' ':(exclude)*.adoc' > "$tmp/grep" 2>/dev/null
grep_rc=$?
[ "$grep_rc" -le 1 ] || names_ok=0
tr '\000' '\001' < "$tmp/grep" \
  | HEADPFX="$head:" awk "$DEF_AWK"'{
      i = index($0, "\001"); if (i < 2) next
      p = substr($0, 1, i - 1); hp = ENVIRON["HEADPFX"]
      if (index(p, hp) == 1) p = substr(p, length(hp) + 1)
      defs(p, substr($0, i + 1))
    }' | sort -u > "$tmp/defs"

# Candidates: every name defined in a touched text file, indexed in ONE pass over the repo-wide
# definitions as `<name><TAB><added 1|0><TAB><file count><TAB><first WHERE_CAP files, comma-joined>`
# ($tmp/defs is sorted, so each name's files arrive sorted and deduplicated). The loop then keeps a
# candidate only when the diff ADDED it and 2+ files define it at <head>.
awk -F'\t' -v cap="$WHERE_CAP" '
  FILENAME == ARGV[1] { added[$0] = 1; next }
  FILENAME == ARGV[2] { t[$0] = 1; next }
  ($1 in t) { cand[$2] = 1 }
  { n[$2]++; if (n[$2] <= cap) w[$2] = (n[$2] > 1 ? w[$2] ", " : "") $1 }
  END { for (k in cand) print k "\t" ((k in added) ? 1 : 0) "\t" n[k] "\t" w[k] }
' "$tmp/added_names" "$tmp/text" "$tmp/defs" | sort > "$tmp/cand"
if [ "$names_ok" -eq 1 ]; then
  while IFS="$TAB" read -r name added nfiles shown; do
    [ -n "$name" ] || continue
    [ "$added" = "1" ] || continue  # pin: added-only
    [ "${nfiles:-0}" -ge 2 ] || continue  # pin: defined-in-2+
    more=""; [ "$nfiles" -gt "$WHERE_CAP" ] && more=" (+$((nfiles - WHERE_CAP)) more)"
    printf 'shared-name: %s defined in %s files: %s%s\n' "$name" "$nfiles" "$shown" "$more" >> "$tmp/names"
  done < "$tmp/cand"
else
  printf '%s: names_unavailable (git grep exit %s) — line facts only\n' "$SELF" "$grep_rc" >&2
fi

# ---------------------------------------------------------------------------
# Emit (capped, with visible markers)
# ---------------------------------------------------------------------------
printf 'module-shape facts (base %s, head %s; facts only — no size threshold applied):\n' "$base" "$head"
n_lines="$(grep -c . "$tmp/lines" || true)"
head -n "$FILE_CAP" "$tmp/lines"
[ "${n_lines:-0}" -gt "$FILE_CAP" ] && printf '(+%s more touched files)\n' "$((n_lines - FILE_CAP))"
n_names="$(grep -c . "$tmp/names" || true)"
head -n "$NAME_CAP" "$tmp/names"
[ "${n_names:-0}" -gt "$NAME_CAP" ] && printf '(+%s more shared names)\n' "$((n_names - NAME_CAP))"
exit 0
