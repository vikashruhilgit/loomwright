#!/usr/bin/env bash
# rules-replay-lib.sh — the ONE fail-CLOSED parser of a `rules-check.sh --if-stamped` replay, SOURCED
# by both of its consumers (rule-enforcement-at-review-and-merge, D-b: EXTRACT, not mirror):
#   - worker-rule-selfcheck.sh   sources it FAIL-SAFE  (`. "$HERE/rules-replay-lib.sh" 2>/dev/null || exit 0`)
#   - rules-gate-verdict.sh      sources it FAIL-CLOSED (absent / unsourceable ⇒ verdict `unreadable`)
# so a forged or truncated checker output is judged by the SAME tested code in both places. A second
# copy of a security parser kept honest only by a byte-equality pin is exactly the "second copy that
# drifts silently" defect house rule 3 names — hence a library, not a mirror.
#
# FUNCTIONS ONLY. This file has NO top-level side effects: no `set -e`/`set -u`, no argv parsing, no
# `exit`, no `cd`, no output. It defines two functions and nothing else. Sourcing it under the caller's
# own `set -uo pipefail` is safe (every expansion is bound). Portability: bash 3.2 (macOS) + Linux; no
# GNU-only flags, no `timeout`, no mapfile.
#
# THE RULES (the `rule:` resolution run-ground-truth.sh adopted in PR #292 and worker-rule-selfcheck.sh
# shipped in automate-followups/06 — item 06's tests are the proof of THIS code). rules-check.sh echoes
# raw check text on its `  [RUN ] <id>: <check>` lines, so a stamped check whose text embeds a newline
# can pre-print forged lines, and a check can pre-print a forged `  [PASS] <id>` and then kill its
# parent before the real result line. Callers apply, in order: (0) EMPTY stdout ⇒ nothing ran and
# (1) the exact whole line `  [SKIP] all (unstamped)` with no `  [RUN ] ` line ⇒ unstamped — both are
# the CALLER's decisions (they differ per consumer: silence vs a loud verdict). Then:
#
#   rules_replay_trailer_ok <run_out> <rc> <listed_n>
#     TRAILER RULE (step 2). Returns 0 iff <rc> is 0 or 1 (1 is the EXPECTED rc when any check fails)
#     AND the LAST line of <run_out> is an exact `Checks passed: N/M` with N and M all-digit AND
#     M == <listed_n> (the number of ids `--list-selected` printed). Anything else — a missing,
#     malformed or mismatched trailer, or any other rc (a signal death is 128+n) — returns 1, and the
#     caller must treat EVERY listed id as `unresolved`. This closes pre-print-then-kill (the forged
#     PASS survives, the trailer never comes) and a forged COMPLETE trailer after a kill (only the rc
#     reveals it). Prints nothing.
#
#   rules_replay_map_id <id> <run_out> <listed>
#     PER-ID MAP (step 3). Prints exactly one of `pass` / `fail` / `unresolved` for <id>, matching
#     LITERAL strings only (string equality / fixed-string tests — never a regex built from the id):
#     exactly one whole line `  [FAIL] <id>` and no other result line for it ⇒ `fail`; exactly one
#     `  [PASS] <id>` and no other ⇒ `pass`; anything else — a PASS+FAIL pair, a duplicate, a
#     near-miss line containing `[PASS] <id>` / `[FAIL] <id>` that is not an exact result line (an
#     exact result line of ANOTHER listed id is not a near-miss), or no line at all ⇒ `unresolved`.
#     <listed> is the newline-joined `--list-selected` output (ids carrying a newline/CR are already
#     omitted by that flag, so one id is one line). Only meaningful AFTER rules_replay_trailer_ok
#     returned 0 — a caller that skips the trailer rule has no business mapping ids.
#
# STATED GUARANTEE (and its honest limit): a forged or truncated output can only ADD a report
# (`unresolved`), never hide a failing id — EXCEPT a stamped check that forges a complete, internally
# consistent run (its own PASS line, suppression of the real FAIL, a matching trailer AND a 0/1 exit)
# from inside a single `[RUN ]` echo, which no line parser can distinguish. That residual needs the
# forging text to be in a check a human already confirmed (the stamp hashes it).

# rules_replay_trailer_ok <run_out> <rc> <listed_n> — see the header. Exit 0 = trailer rule holds.
rules_replay_trailer_ok() {
  local _out="${1:-}" _rc="${2:-}" _listed_n="${3:-}" _last _nm _n _m
  _last="${_out##*$'\n'}"
  case "$_listed_n" in ''|*[!0-9]*) return 1 ;; esac
  case "$_rc" in
    0|1)
      case "$_last" in
        "Checks passed: "*/*)
          _nm="${_last#Checks passed: }"
          _n="${_nm%%/*}"
          _m="${_nm#*/}"
          case "$_n$_m" in
            *[!0-9]*) : ;;
            *)
              if [ -n "$_n" ] && [ -n "$_m" ] && [ "$_m" -eq "$_listed_n" ]; then
                return 0
              fi
              ;;
          esac
          ;;
      esac
      ;;
  esac
  return 1
}

# _rules_replay_is_listed <id> <listed> — exit 0 iff <id> is exactly one of the listed ids (whole
# line, literal). Internal to rules_replay_map_id.
_rules_replay_is_listed() {
  [ -n "${1:-}" ] || return 1
  grep -Fxq -- "$1" <<EOF
${2:-}
EOF
}

# rules_replay_map_id <id> <run_out> <listed> — prints pass | fail | unresolved. See the header.
rules_replay_map_id() {
  local id="${1:-}" _out="${2:-}" _listed="${3:-}" l rest np=0 nf=0 nm=0
  while IFS= read -r l; do
    if [ "$l" = "  [PASS] $id" ]; then
      np=$((np + 1))
    elif [ "$l" = "  [FAIL] $id" ]; then
      nf=$((nf + 1))
    else
      case "$l" in
        *"[PASS] $id"*|*"[FAIL] $id"*)
          rest=""
          case "$l" in
            "  [PASS] "*) rest="${l#"  [PASS] "}" ;;
            "  [FAIL] "*) rest="${l#"  [FAIL] "}" ;;
          esac
          if [ -n "$rest" ] && [ "$rest" != "$id" ] && _rules_replay_is_listed "$rest" "$_listed"; then
            :
          else
            nm=$((nm + 1))
          fi
          ;;
      esac
    fi
  done <<EOF
$_out
EOF
  if [ "$np" -eq 1 ] && [ "$nf" -eq 0 ] && [ "$nm" -eq 0 ]; then
    printf 'pass\n'
  elif [ "$nf" -eq 1 ] && [ "$np" -eq 0 ] && [ "$nm" -eq 0 ]; then
    printf 'fail\n'
  else
    printf 'unresolved\n'
  fi
}
