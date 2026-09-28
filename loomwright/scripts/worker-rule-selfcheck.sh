#!/usr/bin/env bash
# worker-rule-selfcheck.sh — the worker's pre-WORKER_RESULT replay of its HUMAN-STAMPED `must`-rule
# checks, reduced to the exact `rule:` deviations lines to copy (automate-followups/06).
#
# WHAT IT IS: a thin, deterministic, FAIL-SAFE reader over rules-check.sh. The worker calls this and
# copies its stdout verbatim; the worker never parses rules-check.sh output itself (an LLM parsing raw
# checker output could not be CI-tested — this script can).
#
# Usage:  worker-rule-selfcheck.sh [--root <tree>]      (--root defaults to `.`)
#   The helper cds into <tree> (so rules-check.sh resolves THAT tree's git toplevel and its rules
#   store) and runs every delegated call with stdin </dev/null.
#
# STDOUT CONTRACT: EXACTLY the deviations lines to copy — 0..4 lines, nothing else. Diagnostics, if
# any, go to stderr. EXIT: ALWAYS 0 (an advisory, fail-safe emitter — CLAUDE.md §"Failure-Mode
# Invariants"). Every failure path — an unknown argument, a bad/missing --root, not a git work tree,
# no jq, no rules store, rules-check.sh absent, or a checker call that exits non-zero / prints
# nothing — prints NOTHING on stdout.
#
# DELEGATION (the trust boundary, skills/rules/SKILL.md §9 — rules-check.sh stays the SOLE executor
# of a rule `check`). This script never reads the rules store, never extracts a check string and never
# executes one. It resolves rules-check.sh as a SIBLING of itself (never from PATH) and makes AT MOST
# two calls:
#   (a)  `rules-check.sh --list-selected` once — the must+checkable ids, sorted. Empty ⇒ nothing to
#        replay: print nothing, and --if-stamped is never invoked.
#   (a2) RULES_CHECK_NO_CMD=1 in THIS script's environment ⇒ print nothing and exit WITHOUT invoking
#        --if-stamped. Decided from the environment, never by matching checker output.
#   (b)  otherwise `rules-check.sh --if-stamped` once, capturing stdout and the exit code. NEVER
#        --confirm, and RULES_CHECK_CONFIRM is unset below before any call (rules-check.sh already
#        ignores that variable under --if-stamped — PR #267 — this is belt and braces). --if-stamped
#        can only ever replay a set a human already confirmed on this machine.
#
# FAIL-CLOSED PARSE of (b) — the `rule:` resolution run-ground-truth.sh adopted in PR #292, including
# its trailer rule (its header step "(c)2"). Steps 2 and 3 are IMPLEMENTED in the sibling
# rules-replay-lib.sh (`rules_replay_trailer_ok`, `rules_replay_map_id`), shared with
# rules-gate-verdict.sh and sourced fail-safe below. rules-check.sh echoes raw check text on its
# `  [RUN ] <id>: <check>` lines, so a stamped check whose text embeds a newline can pre-print forged
# lines, and a check can pre-print a forged `  [PASS] <id>` and then kill its parent before the real
# result line. In order:
#   0. EMPTY stdout ⇒ the checker never reached its per-rule loop (it prints `  [RUN ] ` BEFORE it
#      executes any check), so nothing ran — the same fail-safe silence as an absent checker. This is
#      not a hiding path: a check can only run after its RUN line has reached stdout.
#   1. UNSTAMPED ⇒ silent, but ONLY when the output holds the exact whole line
#      `  [SKIP] all (unstamped)` AND no line starts with `  [RUN ] ` (nothing executed). Never a
#      substring test; a forged unstamped line alongside a RUN line falls through to step 2.
#   2. TRAILER RULE: otherwise the output MUST end with an exact `Checks passed: N/M` line whose M
#      equals the number of ids from (a), and the exit code must be 0 or 1 (1 is the EXPECTED rc when
#      any check fails). Missing / malformed / mismatched trailer, or any other rc ⇒ EVERY listed id is
#      `unresolved`. This closes pre-print-then-kill: the forged PASS survives, the trailer never comes.
#   3. PER ID, matched as literal strings (string equality / fixed-string grep, never a regex built
#      from the id): exactly one whole line `  [FAIL] <id>` and no other result line for it ⇒ failed;
#      exactly one `  [PASS] <id>` and no other ⇒ passed (silent); anything else — a PASS+FAIL pair, a
#      duplicate, a near-miss line containing `[PASS] <id>`/`[FAIL] <id>` that is not an exact result
#      line (an exact result line of ANOTHER listed id is not a near-miss), or no line at all ⇒
#      unresolved. Ids carrying a newline/CR are already omitted by --list-selected.
#
# STATED GUARANTEE (and its honest limit): a forged or truncated output can only ADD a report
# (`unresolved`), never hide a failing id — EXCEPT a stamped check that forges a complete, internally
# consistent run (its own PASS line, suppression of the real FAIL, and a matching trailer) from inside
# a single `[RUN ]` echo, which no line parser can distinguish. That residual needs the forging text to
# be in a check a human already confirmed (the stamp hashes `id\tcheck`), and every entry this script
# emits is REPORT-ONLY — the same residual run-ground-truth.sh documents for its `rule:` kind.
#
# OUTPUT FORMAT + BOUND (validate-worker-result.py rule 10: ≤12 deviations, each ≤200 characters).
# One line per failed/unresolved id, in --list-selected (sorted) order, at most 3:
#     rule: <id> — stamped must-check fails
#     rule: <id> — stamped must-check result unresolved
# and, when more than 3 ids failed or were unresolved, ONE 4th and final line:
#     rule: +<K> more failing stamped must-checks (<N> total)
# so at most 4 lines, leaving 8 of the 12 slots for the worker's other entries. Every line is at most
# 200 CHARACTERS: an id that would overflow is truncated to fit and ends with `…`. Characters, not
# bytes — the length and the cut are computed by jq (Unicode-codepoint strings, the same jq
# rules-check.sh already requires), with the id passed as --arg data, never as program text. Zero
# failed/unresolved ids ⇒ print nothing (no "all rules passed" noise entry).
#
# Portability: bash 3.2 (macOS) + Linux; no GNU-only flags, no `timeout`, no mapfile.

set -uo pipefail   # NO `set -e`: every failure path is an explicit, silent exit 0.

PROG="worker-rule-selfcheck.sh"
LINE_MAX=200
SHOW_MAX=3

# Resolve the sibling checker BEFORE any cd (a relative $0 would break afterwards). Never from PATH.
# CDPATH= + >/dev/null: an exported CDPATH makes `cd` echo the resolved dir to stdout, which would
# corrupt HERE (and, for --root below, the stdout contract).
HERE="$(CDPATH= cd -- "$(dirname "$0")" >/dev/null 2>&1 && pwd)" || exit 0
CHECKER="$HERE/rules-check.sh"

# The fail-closed replay PARSE (steps 2 and 3 below) lives in the sibling rules-replay-lib.sh, shared
# with rules-gate-verdict.sh so both consumers judge a replay by the SAME tested code. Sourced
# FAIL-SAFE: an absent/unsourceable lib is one more silent exit 0 (stdout empty, contract unchanged).
. "$HERE/rules-replay-lib.sh" 2>/dev/null || exit 0

# Never forward an ambient confirmation to the checker (see DELEGATION (b) above).
unset RULES_CHECK_CONFIRM

ROOT_ARG="."
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then
        echo "$PROG: --root needs a directory — nothing checked" >&2
        exit 0
      fi
      ROOT_ARG="$2"; shift 2 ;;
    -h|--help)
      # stderr, not stdout: stdout carries ONLY deviations lines, even here.
      grep -E '^# ' "$0" | sed -E 's/^# ?//' >&2
      exit 0 ;;
    *)
      # A mistyped flag (e.g. `--rot <tree>`) must not silently check the WRONG tree.
      echo "$PROG: unrecognized argument $1 — nothing checked" >&2
      exit 0 ;;
  esac
done

CDPATH= cd -- "$ROOT_ARG" >/dev/null 2>&1 || { echo "$PROG: cannot enter --root $ROOT_ARG — nothing checked" >&2; exit 0; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || { echo "$PROG: $ROOT_ARG is not inside a git work tree — nothing checked" >&2; exit 0; }
[ -f "$CHECKER" ] || { echo "$PROG: sibling rules-check.sh not found — nothing checked" >&2; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "$PROG: jq unavailable — nothing checked" >&2; exit 0; }

# ---- (a) the must+checkable ids --------------------------------------------------------------------
LISTED="$(bash "$CHECKER" --list-selected </dev/null 2>/dev/null)" || exit 0
LISTED_N=0
while IFS= read -r _l; do
  [ -n "$_l" ] && LISTED_N=$((LISTED_N + 1))
done <<EOF
$LISTED
EOF
[ "$LISTED_N" -gt 0 ] || exit 0

# ---- (a2) the unattended no-cmd valve reaches the helper: nothing executes ------------------------
[ "${RULES_CHECK_NO_CMD:-0}" = "1" ] && exit 0

# ---- (b) the ONE replay ----------------------------------------------------------------------------
RUN_OUT=""
RUN_RC=0
RUN_OUT="$(bash "$CHECKER" --if-stamped </dev/null 2>/dev/null)"; RUN_RC=$?

# Step 0: empty stdout — nothing ran (see header).
[ -n "$RUN_OUT" ] || exit 0

# Step 1: unstamped — silent only when nothing executed.
if grep -Fxq -- "  [SKIP] all (unstamped)" <<<"$RUN_OUT" \
   && ! grep -q '^  \[RUN \] ' <<<"$RUN_OUT"; then
  exit 0
fi

# Step 2: the trailer rule (rules_replay_trailer_ok — rules-replay-lib.sh).
MAPPED=0
if rules_replay_trailer_ok "$RUN_OUT" "$RUN_RC" "$LISTED_N"; then
  MAPPED=1
fi

# _emit_line <id> <suffix> — `rule: <id><suffix>`, id truncated with `…` to fit LINE_MAX characters.
_emit_line() {
  jq -rn --arg id "$1" --arg sfx "$2" --argjson max "$LINE_MAX" '
    ("rule: " + $id + $sfx) as $line
    | if ($line | length) <= $max then $line
      else ($max - ("rule: " | length) - ($sfx | length) - 1) as $keep
           | "rule: " + $id[0:$keep] + "…" + $sfx
      end' 2>/dev/null
}

# ---- step 3 + output ---------------------------------------------------------------------------------
REPORTED=0
while IFS= read -r id; do
  [ -n "$id" ] || continue
  if [ "$MAPPED" -eq 1 ]; then
    verdict="$(rules_replay_map_id "$id" "$RUN_OUT" "$LISTED")"   # step 3 — rules-replay-lib.sh
  else
    verdict="unresolved"
  fi
  case "$verdict" in
    fail)       sfx=" — stamped must-check fails" ;;
    unresolved) sfx=" — stamped must-check result unresolved" ;;
    *)          continue ;;
  esac
  REPORTED=$((REPORTED + 1))
  [ "$REPORTED" -le "$SHOW_MAX" ] && _emit_line "$id" "$sfx"
done <<EOF
$LISTED
EOF

if [ "$REPORTED" -gt "$SHOW_MAX" ]; then
  printf 'rule: +%d more failing stamped must-checks (%d total)\n' "$((REPORTED - SHOW_MAX))" "$REPORTED"
fi
exit 0
