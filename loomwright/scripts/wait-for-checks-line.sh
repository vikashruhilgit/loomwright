#!/usr/bin/env bash
# wait-for-checks-line.sh — the ONE reader of the line wait-for-checks.sh prints. Sourced, never
# run (deliberately not named test-*.sh). Consumers: automate-helpers.d/escalation.sh
# (escalation-cause) and drain-subfloor-decision.sh (decide). Self-test: the round-trip and
# mutation-control legs in test-wait-for-checks.sh; each consumer's suite has spaced-name legs.
#
# WHY ONE READER: check names are free text — matrix contexts such as `test (18.x)` or
# `build (ubuntu-latest)` carry spaces. Shell word-splitting the line cut a name at its first
# space: PR #440 fixed that in drain-subfloor-decision.sh by reading the names field as the
# line's remainder, while escalation.sh kept a `for w in $snap` copy and recorded `check=test`,
# so the merge watcher looked up a check that does not exist and never reported "now mergeable".
# A second hand-written parser of the same line is how the fix missed it; this file is the
# parser, and a consumer that needs another field adds it here.
#
# GRAMMAR (wait-for-checks.sh's printf lines; `--names` appends the last two fields):
#   SETTLED  sha=<sha> required=<r> review_producing=settled                [NAMES]
#   ELAPSED  sha=<sha> required=<r> review_producing=<rp> pending=<list>    [NAMES]
#   CONTINUE sha=<sha> remaining=<n> pending=<list>                         [NAMES]
#   NAMES  = ` pending_names=<list|none|sha_mismatch> red_names=<name@run_id,...|none>`
#   <list> = comma-separated check names (free text, may hold spaces); a red entry is
#            `<name>@<run_id>`, `-` for an absent run id (split on the LAST `@`).
# How it is read, never by whitespace splitting:
#   - kind is the first word; sha= / required= are single-word scalars printed BEFORE any
#     name field, so each comes from its FIRST occurrence (a name containing ` required=`
#     cannot override it), read from the part of the line before ` pending_names=`.
#   - pending= is everything between its first ` pending=` and ` pending_names=` (or the
#     end of the line).
#   - pending_names= is everything between its first occurrence and the next ` red_names=`;
#     red_names= is the REMAINDER of the line after that ` red_names=` (it is printed last).
#   Leading and trailing whitespace of the line is dropped.
# Honest limit: wait-for-checks.sh does not escape names, so a check name that itself contains
# `,` (splits into two list items) or the text ` red_names=` / ` pending_names=` (moves a field
# boundary) is still misread; GitHub check names in practice hold neither.
#
# wfc_line_parse <line> — sets, in the caller's shell:
#   WFC_KIND WFC_SHA WFC_REQUIRED WFC_PENDING WFC_PENDING_NAMES WFC_RED_NAMES  (empty when absent)
#   WFC_HAVE_PENDING_NAMES WFC_HAVE_RED_NAMES                                  (1 when the field is present, else 0)
# Always returns 0; never splits on IFS, never globs. Bash 3.2 / BSD safe.
wfc_line_parse() {
  local l="${1:-}" head v
  l="${l#"${l%%[![:space:]]*}"}"
  l="${l%"${l##*[![:space:]]}"}"
  WFC_KIND="${l%% *}"
  WFC_SHA=""; WFC_REQUIRED=""; WFC_PENDING=""; WFC_PENDING_NAMES=""; WFC_RED_NAMES=""
  WFC_HAVE_PENDING_NAMES=0; WFC_HAVE_RED_NAMES=0
  head="${l%% pending_names=*}"
  case "$head" in *' sha='*) v="${head#* sha=}"; WFC_SHA="${v%% *}" ;; esac
  case "$head" in *' required='*) v="${head#* required=}"; WFC_REQUIRED="${v%% *}" ;; esac
  case "$head" in *' pending='*) WFC_PENDING="${head#* pending=}" ;; esac
  case "$l" in
    *' pending_names='*)
      WFC_HAVE_PENDING_NAMES=1
      v="${l#* pending_names=}"
      case "$v" in
        *' red_names='*) WFC_HAVE_RED_NAMES=1; WFC_PENDING_NAMES="${v%% red_names=*}"; WFC_RED_NAMES="${v#* red_names=}" ;;
        *) WFC_PENDING_NAMES="$v" ;;
      esac ;;
    *' red_names='*) WFC_HAVE_RED_NAMES=1; WFC_RED_NAMES="${l#* red_names=}" ;;
  esac
  return 0
}
