#!/usr/bin/env bash
# check-prompt-history-refs.sh — CI gate (ratchet): history references in runtime prompts may
# only go down.
#
# WHY: a runtime prompt is read on every spawn or on-demand read, so a sentence about the past
# ("the case seen on <PR>", "fixed in <release>", "<queue>/<item> found …") is paid for on every
# run and tells the model nothing it can act on. The automate-speed diet moved that history out
# of the runtime prompts; nothing stopped the next fix PR from writing it back. This gate counts
# the references per runtime prompt against a committed baseline that may only go down. A story
# belongs in CHANGELOG.md or loomwright/docs/rationale/, never in a runtime prompt.
#
# SCANNED SET (runtime prompts) — every *.md under SCANNED_DIRS below, recursive, enumerated by
# a filesystem walk (`find`, never `git ls-files`), so a new UNTRACKED prompt is counted by a
# local pre-push run with no temp-index special case. loomwright/docs/command-parts/ IS scanned,
# on purpose: those files are on-demand reads of split commands, and check-token-budget.sh
# already counts them as part of a command's runtime weight; leaving them out would let a
# reference move from a command into its parts unseen. Nothing else under loomwright/docs/ is
# scanned (not docs/rationale/, not docs/evidence/), and neither is CHANGELOG.md or changelog.d/.
#
# REFERENCE PATTERNS — HISTORY_REF_PATTERNS below is the ONE definition (the self-test drives
# the gate and never restates it). Each match counts once, and only when the character after it
# is not in the alternative's trailing-guard class (so `#20B2AA` and `pending/2026` are not
# references). FROZEN_EXAMPLE_ERE lines count 0:
# a sample `session_end` record, a `"plugin_version"` key and a sample POSTMORTEM_RESULT record
# illustrate a FORMAT only (the convention check-doc-currency.sh documents under "FROZEN,
# VERSION-AGNOSTIC EXAMPLE VALUES ARE INTENTIONALLY LEFT ALONE").
#
# BASELINE — loomwright/docs/prompt-history-refs-baseline.json:
#   {"_comment": "<one line>", "files": {"<repo-relative path>": <non-negative integer>, …}}
# one entry per scanned file, zero-count files included. `--write-baseline` writes it from the
# live counts: used to create it and by a later PR that LOWERS counts, never by CI.
#
# VERDICTS (exit 0 / 1)
#   * count > entry ⇒ exit 1. The file is named and each reference printed as
#     `path:line: <token>`. When the base copy of the file can be read (the base ref resolves),
#     only the references the base copy lacks are printed (a file absent at base lacks them all).
#   * count < entry ⇒ exit 0, prints `lower the baseline: <path> <entry> -> <count>`.
#   * raise_check — the baseline itself may only go down. Base ref = $PROMPT_HISTORY_REFS_BASE
#     when set, else `git merge-base origin/main HEAD`, else `origin/main`; the base baseline is
#     read with `git show <base>:<baseline path>` (the object store, never the work tree). An
#     entry higher than the same entry at base ⇒ exit 1 (`baseline rose: <path> <base> -> <now>`).
#     A new entry is allowed only while the baseline TOTAL does not rise above the base total
#     (`baseline total rose: <base> -> <now>`), so a move-only split can redistribute references
#     but cannot add any. Three base cases, kept apart here and in the code:
#       (a) the base REF does not resolve (no origin/main, a failed fetch, not a git work tree,
#           a baseline outside the work tree) ⇒ `raise_check: skipped (<reason>)`, no failure;
#           PROMPT_HISTORY_REFS_REQUIRE_BASE=1 makes it an ERROR (CI sets it). Same design as
#           check-vendor-coupling.sh's raise_skip / VENDOR_COUPLING_REQUIRE_BASE.
#       (b) the base ref resolves but holds NO baseline file (bootstrap: the PR that creates the
#           file) ⇒ `raise_check: skipped (no baseline at base — bootstrap)` and exit 0 EVEN under
#           PROMPT_HISTORY_REFS_REQUIRE_BASE=1. This deliberately differs from vendor-coupling,
#           whose "manifest path does not exist at base" skip IS an error under require-base:
#           without the carve-out, the creating PR's own CI could never go green.
#       (c) the base baseline is malformed JSON, not {files:{…}}, or holds a non-integer entry ⇒
#           ERROR, exit 1 (fail CLOSED — an unreadable base never certifies a baseline).
#     HONEST LIMIT: CI's shallow checkout compares with main's TIP, not the true merge base, so a
#     branch whose baseline predates a later lowering on main reads as `baseline rose`; a rebase
#     clears it (the same limit as the vendor-coupling raise check). Locally the default base is
#     the merge base.
#   * fail-CLOSED ERRORs (exit 1): jq missing; the baseline missing, malformed JSON or not
#     {files:{…}} (validated with `jq -e` before any value is read); a non-integer or negative
#     entry; a scanned file with no entry; an entry naming a file outside the scanned set
#     (orphan); a scanned dir missing, empty of *.md, or holding a symlink (`find -type f` would
#     skip it silently). Zero scanned files is never green.
#   There is no third state and no `|| true`: a correctness gate (CLAUDE.md §"Failure-Mode
#   Invariants").
#
# USAGE
#   bash scripts/check-prompt-history-refs.sh [--root <dir>] [--baseline <file>] [--write-baseline]
#     --root <dir>       tree to scan (default: this repo's root); fixtures for the self-test
#     --baseline <file>  baseline JSON (default: <root>/loomwright/docs/prompt-history-refs-baseline.json)
#     --write-baseline   write the live counts to the baseline and exit (lowering PRs only)
# Env: PROMPT_HISTORY_REFS_BASE (base ref), PROMPT_HISTORY_REFS_REQUIRE_BASE (`1` = a skipped
# raise_check of case (a) is an ERROR).
# Self-test: scripts/test-check-prompt-history-refs.sh (offline fixture repos).
#
# Portability: bash 3.2 / BSD userland safe (macOS dev, GNU CI). No `timeout`, no GNU-only flags,
# no `${var//…}` on large strings. Matching is LC_ALL=C (bytes) with `grep -oE`, so BSD and GNU
# grep agree. Deterministic and fully offline.

set -uo pipefail
export LC_ALL=C

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

SCANNED_DIRS="loomwright/agents
loomwright/commands
loomwright/skills
loomwright/docs/command-parts"

# One alternative per line: `<trailing-guard class><TAB><ERE>`. ERE has no look-around, so
# both guards are emulated. LEADING: a guard char (`[^…]`) is part of the match, and every
# scanned line is prefixed with a space so it always has a char to match at line start; the
# token printed is the match with that guard char stripped. TRAILING: each alternative is
# searched on its own pass as `<ERE><class>*`, so a match runs on through any guard-class chars
# after it, and it counts only when that run is empty, i.e. the whole match still equals `<ERE>`
# anchored. The run consumes only guard-class chars, never the separator a following
# reference's leading guard needs, and a rejected run never hides another alternative's match
# (each alternative is its own pass).
#   #NNN          `#` + 2–5 digits, not after `&`, a letter, a digit or `_` (no entity, no
#                 anchor), not before a letter, a digit or `_` (no hex colour `#20B2AA`)
#   <queue>/<NN>  lowercase slug, `/`, two digits, optional letter suffix, not before a letter
#                 or a digit (no `pending/2026-…` date path)
#   YYYY-MM-DD    a date, not before a digit (an ISO timestamp `…-15T12:00` still counts)
#   item NN       case-insensitive `item`, two digits, optional letter suffix, not before a
#                 letter or a digit
#   vX.Y.Z        a version, not after a letter or a digit, not before a letter, a digit or `_`
HISTORY_REF_PATTERNS='[A-Za-z0-9_]	[^&A-Za-z0-9_]#[0-9]{2,5}
[A-Za-z0-9]	[a-z][a-z0-9-]*/[0-9]{2}[a-z]?
[0-9]	20[0-9]{2}-[0-9]{2}-[0-9]{2}
[A-Za-z0-9]	[Ii][Tt][Ee][Mm] [0-9]{2}[A-Za-z]?
[A-Za-z0-9_]	[^A-Za-z0-9]v[0-9]+\.[0-9]+\.[0-9]+'

# Frozen example values (count 0): a sample session_end record, a "plugin_version" key, a
# sample POSTMORTEM_RESULT record (its "review_rounds" key).
FROZEN_EXAMPLE_ERE='"event"[[:space:]]*:[[:space:]]*"session_end"|"plugin_version"[[:space:]]*:|"review_rounds"[[:space:]]*:'

ROOT="$repo_root"
BASELINE=""
MODE="check"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)     [ "$#" -ge 2 ] || { echo "check-prompt-history-refs: ERROR — --root needs a directory"; exit 1; }
                ROOT="$2"; shift 2 ;;
    --baseline) [ "$#" -ge 2 ] || { echo "check-prompt-history-refs: ERROR — --baseline needs a file"; exit 1; }
                BASELINE="$2"; shift 2 ;;
    --write-baseline) MODE="write"; shift ;;
    *) echo "check-prompt-history-refs: ERROR — unknown argument '$1' (expected --root <dir>, --baseline <file>, --write-baseline)"; exit 1 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "check-prompt-history-refs: ERROR — jq is required"; exit 1; }
[ -d "$ROOT" ] || { echo "check-prompt-history-refs: ERROR — root is not a directory: $ROOT"; exit 1; }
ROOT="$(cd "$ROOT" && pwd -P)"
[ -n "$BASELINE" ] || BASELINE="$ROOT/loomwright/docs/prompt-history-refs-baseline.json"
case "$BASELINE" in /*) ;; *) BASELINE="$(pwd -P)/$BASELINE" ;; esac
REQUIRE_BASE="${PROMPT_HISTORY_REFS_REQUIRE_BASE:-}"

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/prompt-history-refs.XXXXXX")" || { echo "check-prompt-history-refs: ERROR — mktemp failed"; exit 1; }
trap 'rm -rf "$TMPD"' EXIT

errors=0
violations=0
err() { echo "ERROR: $*"; errors=$((errors + 1)); }

# tokens_of <file> -> "<line>:<token>" per reference, frozen example lines excluded, in line
# order. Returns 1 when the file cannot be read or grep fails (exit 2) — never a silent 0.
tokens_of() {
  local pre="$TMPD/pre.txt" out="$TMPD/tok.out" raw="$TMPD/tok.raw" rc tail ere
  awk -v fz="$FROZEN_EXAMPLE_ERE" '
    $0 ~ fz { print ""; next }
    { print " " $0 }
  ' "$1" > "$pre" 2>/dev/null || return 1
  : > "$out"
  while IFS="$(printf '\t')" read -r tail ere; do
    [ -n "$ere" ] || continue
    grep -noE "$ere$tail*" "$pre" > "$raw"; rc=$?
    [ "$rc" -le 1 ] || return 1
    grep -E "^[0-9]+:($ere)\$" "$raw" >> "$out"; rc=$?
    [ "$rc" -le 1 ] || return 1
  done <<EOF
$HISTORY_REF_PATTERNS
EOF
  sort -t: -k1,1n "$out" | sed -E 's/^([0-9]+):[^A-Za-z0-9](#|v)/\1:\2/'
}

# valid_baseline <file> -> exit 0 when it is JSON {files: {…}} (jq -e, before any value is read).
valid_baseline() {
  jq -e 'type == "object" and (.files | type) == "object"' "$1" >/dev/null 2>&1
}

# bad_entries <file> -> the keys whose value is not a JSON integer in 0..999999999 (a string, a
# float, a negative, -0 and a huge value are all refused; the cap keeps shell arithmetic exact).
bad_entries() {
  jq -r '.files | to_entries[]
    | select((.value | type) != "number" or .value < 0 or .value != (.value | floor)
             or .value > 999999999 or (.value | tojson | startswith("-")))
    | .key' "$1"
}

# --- enumerate the scanned set -------------------------------------------------------------
SCAN_LIST="$TMPD/scan.lst"
: > "$SCAN_LIST.raw"
while IFS= read -r d; do
  [ -n "$d" ] || continue
  if [ ! -d "$ROOT/$d" ] || [ -L "$ROOT/$d" ]; then
    err "scanned dir missing (or a symlink): $d"
    continue
  fi
  links="$(cd "$ROOT" && find "$d" -type l 2>/dev/null)"
  if [ -n "$links" ]; then
    err "symlink under scanned dir $d cannot be counted (would be skipped silently): $(printf '%s' "$links" | tr '\n' ' ')"
  fi
  found="$(cd "$ROOT" && find "$d" -type f -name '*.md' 2>/dev/null)" || { err "could not list the *.md files under $d"; continue; }
  if [ -z "$found" ]; then
    err "scanned dir has no *.md files: $d (zero scanned files is never green)"
    continue
  fi
  printf '%s\n' "$found" >> "$SCAN_LIST.raw"
done <<EOF
$SCANNED_DIRS
EOF
sort -u "$SCAN_LIST.raw" > "$SCAN_LIST"

# --- count every scanned file ---------------------------------------------------------------
COUNTS="$TMPD/counts.tsv"   # path \t count \t token-file
: > "$COUNTS"
mkdir -p "$TMPD/tok"
i=0
total_now=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  i=$((i + 1))
  tf="$TMPD/tok/$i.txt"
  if ! tokens_of "$ROOT/$p" > "$tf"; then
    err "could not read scanned file: $p"
    continue
  fi
  n="$(wc -l < "$tf" | tr -d ' ')"
  total_now=$((total_now + n))
  printf '%s\t%s\t%s\n' "$p" "$n" "$tf" >> "$COUNTS"
done < "$SCAN_LIST"
nfiles="$(wc -l < "$COUNTS" | tr -d ' ')"

if [ "$MODE" = "write" ]; then
  if [ "$errors" -gt 0 ]; then
    echo "check-prompt-history-refs: FAILED — $errors error(s); baseline NOT written"
    exit 1
  fi
  mkdir -p "$(dirname "$BASELINE")" || exit 1
  cut -f1,2 "$COUNTS" | jq -Rn '
    {"_comment": "History references per runtime prompt, counted by scripts/check-prompt-history-refs.sh. Counts may only go down; regenerate with --write-baseline only to lower them.",
     "files": (reduce (inputs | split("\t")) as $r ({}; .[$r[0]] = ($r[1] | tonumber)))}' > "$BASELINE.tmp" \
    && mv "$BASELINE.tmp" "$BASELINE" || { echo "check-prompt-history-refs: ERROR — could not write $BASELINE"; exit 1; }
  echo "check-prompt-history-refs: wrote $BASELINE — scanned files: $nfiles | references: $total_now"
  exit 0
fi

# --- read the baseline (fail CLOSED) ---------------------------------------------------------
ENTRIES="$TMPD/entries.tsv"
: > "$ENTRIES"
baseline_ok=0
if [ ! -f "$BASELINE" ]; then
  err "baseline file missing: $BASELINE (create it with --write-baseline)"
elif ! valid_baseline "$BASELINE"; then
  err "baseline is malformed JSON or not {\"files\": {…}}: $BASELINE"
else
  bad="$(bad_entries "$BASELINE")"
  if [ -n "$bad" ]; then
    while IFS= read -r k; do err "non-integer or negative baseline entry: $k (must be a JSON integer >= 0)"; done <<EOF
$bad
EOF
  else
    jq -r '.files | to_entries[] | "\(.key)\t\(.value)"' "$BASELINE" > "$ENTRIES"
    baseline_ok=1
  fi
fi

# --- resolve the base (for the per-file new-reference filter and the raise check) -----------
BASE_STATE="unresolved"   # unresolved | resolved
BASE_WHY=""
BASE_DESC=""
base_sha=""
show_prefix=""
bl_rel=""
if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  BASE_WHY="root is not inside a git work tree"
else
  top="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null)"
  toplp="$(cd "$top" 2>/dev/null && pwd -P)" || toplp=""
  show_prefix="$(git -C "$ROOT" rev-parse --show-prefix 2>/dev/null)"
  bl_dir="$(cd "$(dirname "$BASELINE")" 2>/dev/null && pwd -P)" || bl_dir=""
  bl_abs="$bl_dir/$(basename "$BASELINE")"
  if [ -n "${PROMPT_HISTORY_REFS_BASE:-}" ]; then
    BASE_DESC="$PROMPT_HISTORY_REFS_BASE"
    base_sha="$(git -C "$ROOT" rev-parse --verify -q "$PROMPT_HISTORY_REFS_BASE^{commit}" 2>/dev/null)" || base_sha=""
  else
    base_sha="$(git -C "$ROOT" merge-base origin/main HEAD 2>/dev/null)" || base_sha=""
    BASE_DESC="merge-base origin/main HEAD"
    if [ -z "$base_sha" ]; then
      base_sha="$(git -C "$ROOT" rev-parse --verify -q "origin/main^{commit}" 2>/dev/null)" || base_sha=""
      BASE_DESC="origin/main"
    fi
  fi
  if [ -z "$base_sha" ]; then
    BASE_WHY="no base: '$BASE_DESC' does not resolve to a commit here (shallow clone, no remote, or a failed fetch — set PROMPT_HISTORY_REFS_BASE or fetch it)"
  else
    BASE_STATE="resolved"
    case "$bl_abs" in
      "$toplp/"*) bl_rel="${bl_abs#"$toplp"/}" ;;
      *) bl_rel="" ;;
    esac
  fi
fi

# --- per-file verdicts -----------------------------------------------------------------------
if [ "$baseline_ok" -eq 1 ]; then
  while IFS="$(printf '\t')" read -r p n tf; do
    [ -n "$p" ] || continue
    entry="$(awk -F'\t' -v k="$p" '$1 == k { print $2; exit }' "$ENTRIES")"
    if [ -z "$entry" ]; then
      err "no baseline entry for scanned file $p (count $n) — a new runtime prompt needs one; the raise check caps the total"
      continue
    fi
    if [ "$n" -gt "$entry" ]; then
      violations=$((violations + 1))
      echo "ABOVE BASELINE: $p has $n history reference(s), baseline $entry — move the story to CHANGELOG.md or loomwright/docs/rationale/"
      if [ "$BASE_STATE" = "resolved" ]; then
        bt="$TMPD/base-tokens.txt"
        if git -C "$ROOT" cat-file -e "$base_sha:$show_prefix$p" 2>/dev/null; then
          git -C "$ROOT" show "$base_sha:$show_prefix$p" > "$TMPD/base-copy.md" 2>/dev/null || : > "$TMPD/base-copy.md"
          echo "  references the base copy ($BASE_DESC) lacks:"
        else
          : > "$TMPD/base-copy.md"
          echo "  references the base copy lacks (the file is new since $BASE_DESC):"
        fi
        tokens_of "$TMPD/base-copy.md" | sed 's/^[0-9]*://' > "$bt" || : > "$bt"
        # The base tokens are loaded with getline, never `NR == FNR`: an EMPTY base file would
        # make that test true for every line of the head file and print nothing.
        awk -v p="$p" -v bf="$bt" '
          BEGIN { while ((getline l < bf) > 0) have[l]++ }
          { tok = $0; sub(/^[0-9]+:/, "", tok); ln = $0; sub(/:.*/, "", ln)
            if (have[tok] > 0) { have[tok]--; next }
            print "  " p ":" ln ": " tok }
        ' "$tf"
      else
        echo "  base unavailable — showing every reference, not only the added ones:"
        awk -v p="$p" '{ tok = $0; sub(/^[0-9]+:/, "", tok); ln = $0; sub(/:.*/, "", ln); print "  " p ":" ln ": " tok }' "$tf"
      fi
    elif [ "$n" -lt "$entry" ]; then
      echo "lower the baseline: $p $entry -> $n"
    fi
  done < "$COUNTS"

  # Orphan entries: a key naming a file outside the scanned set.
  while IFS="$(printf '\t')" read -r k v; do
    [ -n "$k" ] || continue
    if ! awk -v k="$k" '$0 == k { f = 1; exit } END { exit !f }' "$SCAN_LIST"; then
      err "orphan baseline entry: $k is not a scanned runtime prompt (remove the stale entry)"
    fi
  done < "$ENTRIES"
fi

# --- raise_check: the baseline may only go down ---------------------------------------------
raise_skip() { # raise_skip <reason> — case (a)
  echo "raise_check: skipped ($1)"
  if [ "$REQUIRE_BASE" = "1" ]; then
    err "raise_check — PROMPT_HISTORY_REFS_REQUIRE_BASE=1 demands the raise check run here, and it was skipped ($1)"
  fi
}

raise_check() {
  local bb="$TMPD/base-baseline.json" bad_base base_total now_total nraised=0 k v bv
  if [ "$BASE_STATE" != "resolved" ]; then raise_skip "$BASE_WHY"; return; fi
  if [ -z "$bl_rel" ]; then raise_skip "baseline is outside the root's git work tree"; return; fi
  # (b) bootstrap: the base resolves but holds no baseline file — never an error.
  if ! git -C "$ROOT" cat-file -e "$base_sha:$bl_rel" 2>/dev/null; then
    echo "raise_check: skipped (no baseline at base — bootstrap)"
    return
  fi
  # (c) the base baseline must be well-formed, exactly like the head's.
  git -C "$ROOT" show "$base_sha:$bl_rel" > "$bb" 2>/dev/null || : > "$bb"
  if ! valid_baseline "$bb"; then
    err "raise_check — the base baseline ($BASE_DESC:$bl_rel) could not be read as JSON {\"files\": {…}} (fail CLOSED — an unreadable base never certifies a baseline)"
    return
  fi
  bad_base="$(bad_entries "$bb")"
  if [ -n "$bad_base" ]; then
    err "raise_check — the base baseline ($BASE_DESC:$bl_rel) holds a non-integer or negative entry: $(printf '%s' "$bad_base" | tr '\n' ' ')"
    return
  fi
  jq -r '.files | to_entries[] | "\(.key)\t\(.value)"' "$bb" > "$TMPD/base-entries.tsv"
  while IFS="$(printf '\t')" read -r k v; do
    [ -n "$k" ] || continue
    bv="$(awk -F'\t' -v k="$k" '$1 == k { print $2; exit }' "$TMPD/base-entries.tsv")"
    if [ -n "$bv" ] && [ "$v" -gt "$bv" ]; then echo "baseline rose: $k $bv -> $v"; nraised=$((nraised + 1)); fi
  done < "$ENTRIES"
  violations=$((violations + nraised))
  base_total="$(awk -F'\t' '{ t += $2 } END { print t + 0 }' "$TMPD/base-entries.tsv")"
  now_total="$(awk -F'\t' '{ t += $2 } END { print t + 0 }' "$ENTRIES")"
  if [ "$now_total" -gt "$base_total" ]; then
    echo "baseline total rose: $base_total -> $now_total (new entries may only redistribute references, never add them)"
    violations=$((violations + 1))
  fi
  echo "raise_check: executed against $BASE_DESC ($(printf '%.12s' "$base_sha")) — entries raised: $nraised | baseline total $base_total -> $now_total"
}

if [ "$baseline_ok" -eq 1 ]; then
  raise_check
fi

echo "check-prompt-history-refs: scanned files: $nfiles | references: $total_now | violations: $violations | errors: $errors"
if [ "$violations" -gt 0 ] || [ "$errors" -gt 0 ]; then
  echo "check-prompt-history-refs: FAILED — history references in runtime prompts may only go down (a story goes to CHANGELOG.md or loomwright/docs/rationale/)."
  exit 1
fi
echo "check-prompt-history-refs: OK — no runtime prompt above its baseline, and the baseline did not rise."
exit 0
