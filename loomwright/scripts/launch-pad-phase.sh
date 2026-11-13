#!/usr/bin/env bash
# launch-pad-phase.sh — prints Launch Pad's one-line phase marker.
#
# Each Launch Pad phase ends by running this script, and its stdout is the
# phase's marker line:
#
#   ## Phase 2.5: FEASIBILITY — CAUTION
#
# Why a script and not prose: the prompt's per-phase `**Output:**` blocks were
# printed in none of three headless runs (2026-11-12), and a rule telling the
# model to print them changed nothing. A Bash call's stdout is always in the
# transcript (the tool result), so the line no longer depends on the model
# choosing to write it. The phase's full `**Output:**` block stays a template
# the model may print; this line is the part a reader can count on.
#
# USAGE
#   launch-pad-phase.sh <phase> <verdict...>
#       <phase>    one id from PHASES below (e.g. 1, 2.5, 5.5).
#       <verdict>  the phase's result in a few words (remaining args are
#                  joined with one space): e.g. `GO`, `PASS (attempt 1/3)`,
#                  `saved .supervisor/jobs/pending/x.md`. One line, at most
#                  160 characters after whitespace is collapsed.
#   launch-pad-phase.sh --list
#       Prints the phase table, one `<id> <NAME>` per line.
#
# EXIT CODES
#   0  the marker line was printed.
#   2  refused, nothing on stdout, reason on stderr: an unknown phase id, an
#      empty verdict, or a verdict over 160 characters. The caller fixes the
#      call and runs it again — a phase is never marked with a made-up id.
#
# Bash 3.2 / BSD-safe; no external tools beyond printf.
set -u

# The closed phase table: `<id>|<NAME>`, in run order. A new Launch Pad phase
# adds its row here and to test-launch-pad-phase.sh in the same change.
PHASES='1|VALIDATE
2|DISCOVER
2.5|FEASIBILITY
2.7|APPROACH
3|ANALYZE
4|DECOMPOSE
5|PACKAGE
5.5|PLAN REVIEW
6|SAVE
7|RESULT'

usage() {
  printf 'usage: launch-pad-phase.sh <phase> <verdict...> | --list\n' >&2
  exit 2
}

[ "$#" -ge 1 ] || usage

if [ "$1" = "--list" ]; then
  [ "$#" -eq 1 ] || usage
  printf '%s\n' "$PHASES" | while IFS='|' read -r id name; do
    printf '%s %s\n' "$id" "$name"
  done
  exit 0
fi

phase=$1
shift
name=''
known=''
while IFS='|' read -r id n; do
  if [ "$id" = "$phase" ]; then
    name=$n
    break
  fi
  known="$known $id"
done <<EOF
$PHASES
EOF

if [ -z "$name" ]; then
  # `known` is every id in PHASES (the loop ran to the end without a match).
  printf 'launch-pad-phase: unknown phase "%s" (known:%s)\n' "$phase" "$known" >&2
  exit 2
fi

# Collapse every whitespace run (newlines and tabs included) to one space.
# `set -f` keeps a `*` in a verdict literal; the unquoted expansion splits.
set -f
# shellcheck disable=SC2048,SC2086
set -- $*
set +f
verdict="$*"

if [ -z "$verdict" ]; then
  printf 'launch-pad-phase: phase %s needs a verdict\n' "$phase" >&2
  exit 2
fi
if [ "${#verdict}" -gt 160 ]; then
  printf 'launch-pad-phase: verdict is %s characters; the limit is 160\n' "${#verdict}" >&2
  exit 2
fi

printf '## Phase %s: %s — %s\n' "$phase" "$name" "$verdict"
