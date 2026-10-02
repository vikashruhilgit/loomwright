#!/usr/bin/env bash
# rules-gate-verdict.sh — the ONE fail-CLOSED verdict over the human-stamped, gate-COUNTABLE
# `must`-rule checks, for the three enforcement seams (rule-enforcement-at-review-and-merge, D-b):
# Phase 4.5's BLOCKING finding synthesis, the `--until-mergeable` READY test, and `gate-eval`'s
# self-resolved condition 7. It is the INVERSE POSTURE of its sibling worker-rule-selfcheck.sh: that
# one is fail-SAFE and silent (an advisory emitter — any doubt ⇒ print nothing); this one is
# fail-CLOSED and LOUD (any doubt ⇒ a verdict a consumer must PARK/escalate on, never a quiet pass).
#
# Usage:  rules-gate-verdict.sh [--root <tree>]      (--root defaults to `.`)
#   The helper cds into <tree> (so rules-check.sh resolves THAT tree's git toplevel and its rules
#   store) and runs every delegated call with stdin </dev/null.
#
# STDOUT CONTRACT: EXACTLY ONE JSON object on ONE line (compact), always. EXIT: ALWAYS 0 — a verdict (including
# `unreadable`) is a normal outcome; the CONSUMER decides what to do with it (gate-eval PARKs, Phase
# 4.5 synthesizes a finding, the drain withholds READY). Diagnostics go to stderr.
#
#   {"verdict":"ok|none|fail|unresolved|unstamped|cmd_disabled|unreadable",
#    "selected":[ids], "countable":[ids], "advisory":[{"id":..,"reason":..}],
#    "passed":[ids], "failing":[ids], "unresolved":[ids], "checks_passed":"n/m"|null
#    [, "unstamped_reason":"never_confirmed|countable_set_drift|legacy_stamp"]}
#
#   unstamped_reason is OPTIONAL and ADDITIVE: present ONLY when verdict is `unstamped` (absent on every
#   other verdict, so the 8 keys above are unchanged for them). It is message text for the consumer
#   (gate-eval names WHY it parks) and never a decision input — a consumer keys on `verdict` alone, and a
#   missing / unknown reason must still be treated as `unstamped`. never_confirmed = the replay itself
#   said `[SKIP] all (unstamped)` (no stamp, or the stamp hash no longer matches); countable_set_drift =
#   the live countable set differs from the one recorded at the last confirm; legacy_stamp = the stamp
#   predates the recorded countable set and the live countable set is non-empty.
#
#   Every field is built with `jq -n --arg`/`--argjson`: ids and reasons are DATA, never program text.
#   selected  = every id `--list-selected` printed;  countable / advisory = `--list-gateable`'s split
#   (advisory carries the classification reason: binds_undeclared | binds_invalid | unbound:<p>[,<p>]);
#   passed / failing / unresolved = the per-id replay map of EVERY selected id (advisory ids included,
#   for the consumer's report line); checks_passed = the replay trailer's `n/m`, or null when no
#   trailer was accepted.
#
# DELEGATION (the trust boundary, skills/rules/SKILL.md §9 — rules-check.sh stays the SOLE executor of
# a rule `check`). This script never reads the rules store, never extracts or runs a check, resolves
# rules-check.sh as a SIBLING of itself (never from PATH), unsets RULES_CHECK_CONFIRM before any call,
# never passes --confirm, and runs every delegated call with </dev/null. It makes AT MOST four calls,
# in this order: `--list-selected`, `--list-gateable`, `--gate-state`, `--if-stamped`.
#
# THE COUNTABLE-SET BINDING (review iteration 1 — "the edit cannot turn a failing bound check into a
# counted pass without a human re-confirm" must hold for WHICH rules count, not only for their text).
# Which selected rules are countable is read from the PR-controlled tree, and several edits move it
# WITHOUT moving the stamp hash: dropping `binds: []` (hashes like absent), a non-array `binds`, a
# `chmod +x` on a data file a `binds: []` check reads (it turns `unbound`), or demoting/removing the
# last countable rule (`must`→anything else, a corrupted file). So a genuine `--confirm` also records
# the countable id set in the stamp (rules-check.sh "THE COUNTABLE SET"), and `--gate-state` reads it
# back: when the LIVE countable set differs from the RECORDED one in EITHER direction the verdict is
# `unstamped` (a human must re-confirm); a stamp written before that field existed (`legacy`) is
# `unstamped` whenever the live countable set is non-empty (the binds-free / all-advisory path, whose
# live set is empty, is unchanged). HONEST LIMIT: the binding is to the ID SET — an edit that keeps
# every countable id countable but changes a bound file's content or a check's text is caught by the
# hash instead (the replay says unstamped), so between them no edit to the PR tree can produce `ok`
# or `none` over a stamped failing countable check without a re-confirm.
#
# VERDICT DERIVATION (a state trace — evaluated top-down, first match wins):
#   unreadable    no jq / unknown or valueless argument / bad --root / not a git work tree / sibling
#                 rules-check.sh absent / sibling rules-replay-lib.sh absent or unsourceable /
#                 --list-selected, --list-gateable or --gate-state exits non-zero / --list-gateable
#                 output malformed (a line without `id<TAB>countable|advisory<TAB><reason>`) or its id
#                 multiset differs from --list-selected's / --gate-state output malformed (not exactly
#                 `store<TAB>ok|unreadable`, then `stamp<TAB>absent|legacy|recorded`, then only
#                 `countable<TAB><id>` lines and those only under `recorded`) / --gate-state says
#                 `store<TAB>unreadable` (a rules file that is not a parseable JSON array — a corrupted
#                 store is NEVER `none`) / --if-stamped prints NOTHING (the checker never reached its
#                 per-rule loop). Fail-CLOSED: a gate that cannot READ its input must not pass.
#   unstamped     (countable-set drift, ranked ABOVE none / cmd_disabled) --gate-state says `recorded`
#                 and the recorded countable set differs from the live one in either direction, OR says
#                 `legacy` and the live countable set is non-empty. See THE COUNTABLE-SET BINDING.
#   none          --list-selected is empty (no must+checkable rule), OR every selected id is advisory
#                 (countable == []) — the advisory ids are still listed so a consumer can REPORT them.
#                 In the all-advisory case the replay still runs (unless RULES_CHECK_NO_CMD=1) ONLY to
#                 fill passed / failing / checks_passed for the report line; whatever it prints
#                 (fail, unstamped, forged, empty) the verdict stays `none` — nothing uncounted gates.
#   cmd_disabled  RULES_CHECK_NO_CMD=1 in THIS script's environment (Phase 4.5 `--no-cmd`), decided
#                 from the environment, never from checker output; --if-stamped is NEVER invoked.
#   unstamped     the replay output holds the exact whole line `  [SKIP] all (unstamped)` AND no line
#                 starts with `  [RUN ] ` (nothing executed). Never a substring test: a forged
#                 unstamped line beside a RUN line falls through to the trailer rule.
#   unresolved    the TRAILER RULE fails (rules_replay_trailer_ok: rc ∉ {0,1}, or the last line is not
#                 an exact `Checks passed: N/M` with M == |selected|) ⇒ EVERY COUNTABLE id is listed in
#                 `unresolved` and checks_passed is null. Otherwise: no COUNTABLE id maps `fail` but ≥1
#                 COUNTABLE id maps `unresolved` (rules_replay_map_id: PASS+FAIL pair, duplicate,
#                 near-miss, no line).
#   fail          ≥1 COUNTABLE id maps `fail` (exactly one whole `  [FAIL] <id>` line, nothing else).
#   ok            every COUNTABLE id maps `pass`.
#   An ADVISORY id's pass/fail/unresolved is REPORTED in passed/failing/unresolved but NEVER changes
#   the verdict ("a check outside the chosen set is reported advisory, never counted").
#
# FORGERY POSTURE (item 06's fail-closed parse, now the shared rules-replay-lib.sh): a forged output
# can only ADD a blocker (`unresolved`), never remove one — a pre-printed `  [PASS] <id>`, a forged
# unstamped line beside a RUN line, a pre-print-then-kill with a forged complete trailer, or an
# `M ≠ |selected|` trailer all land on `unresolved`, never `ok`. Honest residual: a stamped check that
# forges a complete, internally consistent run (own PASS line, real FAIL suppressed, matching trailer,
# 0/1 exit) inside one `[RUN ]` echo — that text is in a check a human already confirmed.
#
# Portability: bash 3.2 (macOS) + Linux; no GNU-only flags, no `timeout`, no mapfile.

set -uo pipefail   # NO `set -e`: every failure path is an explicit verdict, exit 0.

PROG="rules-gate-verdict.sh"

# Never forward an ambient confirmation to the checker.
unset RULES_CHECK_CONFIRM

# ---- state that the emitter serializes ---------------------------------------------------------------
SELECTED=""      # newline-joined ids (--list-selected)
COUNTABLE=""     # newline-joined countable ids
ADVISORY=""      # newline-joined `id<TAB>reason` lines
PASSED=""        # newline-joined ids
FAILING=""       # newline-joined ids
UNRESOLVED=""    # newline-joined ids
CHECKS_PASSED="" # "n/m" or empty (⇒ null)
UNSTAMPED_REASON="" # set only just before `_emit unstamped` (serialized only for that verdict)

# _emit <verdict> — print the ONE JSON object and exit 0. Every value enters jq as --arg data.
_emit() {
  local verdict="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg v "$verdict" --arg sel "$SELECTED" --arg cnt "$COUNTABLE" --arg adv "$ADVISORY" \
          --arg pas "$PASSED" --arg fai "$FAILING" --arg unr "$UNRESOLVED" --arg cp "$CHECKS_PASSED" \
          --arg ur "$UNSTAMPED_REASON" '
      def ids: split("\n") | map(select(length > 0));
      def advs: split("\n") | map(select(length > 0)
                 | . as $l | ($l | rindex("\t")) as $i
                 | if $i == null then {id: $l, reason: ""} else {id: $l[0:$i], reason: $l[($i + 1):]} end);
      {verdict: $v, selected: ($sel | ids), countable: ($cnt | ids), advisory: ($adv | advs),
       passed: ($pas | ids), failing: ($fai | ids), unresolved: ($unr | ids),
       checks_passed: (if $cp == "" then null else $cp end)}
      + (if $v == "unstamped" and $ur != "" then {unstamped_reason: $ur} else {} end)' 2>/dev/null && exit 0
  fi
  # No jq (or jq itself failed): a static, data-free object — still one JSON object, still exit 0.
  printf '{"verdict":"unreadable","selected":[],"countable":[],"advisory":[],"passed":[],"failing":[],"unresolved":[],"checks_passed":null}\n'
  exit 0
}

# _unreadable <reason> — stderr diagnostic + the fail-closed verdict.
_unreadable() { echo "$PROG: $1 — verdict unreadable" >&2; _emit unreadable; }

command -v jq >/dev/null 2>&1 || _unreadable "jq unavailable"

# Resolve the siblings BEFORE any cd (a relative $0 would break afterwards). Never from PATH.
# CDPATH= + >/dev/null: an exported CDPATH makes `cd` echo the resolved dir to stdout.
HERE="$(CDPATH= cd -- "$(dirname "$0")" >/dev/null 2>&1 && pwd)" || _unreadable "cannot resolve own directory"
CHECKER="$HERE/rules-check.sh"
LIB="$HERE/rules-replay-lib.sh"

ROOT_ARG="."
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then _unreadable "--root needs a directory"; fi
      ROOT_ARG="$2"; shift 2 ;;
    -h|--help)
      grep -E '^# ' "$0" | sed -E 's/^# ?//' >&2   # stderr: stdout carries ONLY the JSON object
      _emit unreadable ;;
    *)
      # A mistyped flag (e.g. `--rot <tree>`) must not silently judge the WRONG tree.
      _unreadable "unrecognized argument $1" ;;
  esac
done

CDPATH= cd -- "$ROOT_ARG" >/dev/null 2>&1 || _unreadable "cannot enter --root $ROOT_ARG"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 </dev/null || _unreadable "$ROOT_ARG is not inside a git work tree"
[ -f "$CHECKER" ] || _unreadable "sibling rules-check.sh not found"
[ -r "$LIB" ] || _unreadable "sibling rules-replay-lib.sh not found"
# FAIL-CLOSED source (the opposite of worker-rule-selfcheck.sh's fail-safe `|| exit 0`).
. "$LIB" 2>/dev/null || _unreadable "sibling rules-replay-lib.sh not sourceable"
command -v rules_replay_trailer_ok >/dev/null 2>&1 && command -v rules_replay_map_id >/dev/null 2>&1 \
  || _unreadable "rules-replay-lib.sh did not define the replay functions"

# ---- (1) the must+checkable ids ----------------------------------------------------------------------
LISTED="$(bash "$CHECKER" --list-selected </dev/null 2>/dev/null)" || _unreadable "rules-check.sh --list-selected failed"
SELECTED=""
LISTED_N=0
while IFS= read -r _l; do
  [ -n "$_l" ] || continue
  SELECTED="$SELECTED$_l"$'\n'
  LISTED_N=$((LISTED_N + 1))
done <<EOF
$LISTED
EOF
# NO `none` short-circuit here any more: an EMPTY live selection is exactly what demoting the last
# countable rule (or corrupting its file) produces, so (3) must first check the store and the stamp's
# recorded countable set. --list-gateable over an empty selection prints nothing and exits 0.

# ---- (2) countable / advisory split ------------------------------------------------------------------
GATEABLE="$(bash "$CHECKER" --list-gateable </dev/null 2>/dev/null)" || _unreadable "rules-check.sh --list-gateable failed"
GATE_IDS=""
COUNTABLE_N=0
while IFS= read -r _l; do
  [ -n "$_l" ] || continue
  case "$_l" in *$'\t'*$'\t'*) : ;; *) _unreadable "malformed --list-gateable line" ;; esac
  _reason="${_l##*$'\t'}"
  _rest="${_l%$'\t'*}"
  _class="${_rest##*$'\t'}"
  _id="${_rest%$'\t'*}"
  [ -n "$_id" ] && [ -n "$_reason" ] || _unreadable "malformed --list-gateable line"
  case "$_class" in
    countable) COUNTABLE="$COUNTABLE$_id"$'\n'; COUNTABLE_N=$((COUNTABLE_N + 1)) ;;
    advisory)  ADVISORY="$ADVISORY$_id"$'\t'"$_reason"$'\n' ;;
    *)         _unreadable "malformed --list-gateable class" ;;
  esac
  GATE_IDS="$GATE_IDS$_id"$'\n'
done <<EOF
$GATEABLE
EOF
# The two listings must name the SAME multiset of ids — anything else is a parser or checker drift.
_sorted_sel="$(printf '%s' "$SELECTED" | env LC_ALL=C sort)"
_sorted_gate="$(printf '%s' "$GATE_IDS" | env LC_ALL=C sort)"
[ "$_sorted_sel" = "$_sorted_gate" ] || _unreadable "--list-gateable id set differs from --list-selected"

# ---- (3) store health + the countable-set binding (THE COUNTABLE-SET BINDING above) ------------------
# The format is ALLOW-LISTED line by line: anything this block does not recognise is unreadable.
GSTATE="$(bash "$CHECKER" --gate-state </dev/null 2>/dev/null)" || _unreadable "rules-check.sh --gate-state failed"
STORE_STATE=""
STAMP_STATE=""
RECORDED=""
_gi=0
while IFS= read -r _l; do
  _gi=$((_gi + 1))
  if [ "$_gi" -eq 1 ]; then
    case "$_l" in "store"$'\t'"ok"|"store"$'\t'"unreadable") STORE_STATE="${_l#store$'\t'}" ;;
      *) _unreadable "malformed --gate-state store line" ;; esac
  elif [ "$_gi" -eq 2 ]; then
    case "$_l" in "stamp"$'\t'"absent"|"stamp"$'\t'"legacy"|"stamp"$'\t'"recorded") STAMP_STATE="${_l#stamp$'\t'}" ;;
      *) _unreadable "malformed --gate-state stamp line" ;; esac
  else
    [ "$STAMP_STATE" = "recorded" ] || _unreadable "--gate-state countable line without a recorded stamp"
    case "$_l" in "countable"$'\t'?*) RECORDED="$RECORDED${_l#countable$'\t'}"$'\n' ;;
      *) _unreadable "malformed --gate-state countable line" ;; esac
  fi
done <<EOF
$GSTATE
EOF
[ -n "$STORE_STATE" ] && [ -n "$STAMP_STATE" ] || _unreadable "incomplete --gate-state output"
[ "$STORE_STATE" = "ok" ] || _unreadable "a .agent/rules/*.json file is not a parseable JSON array"
case "$STAMP_STATE" in
  recorded)
    _sorted_rec="$(printf '%s' "$RECORDED" | env LC_ALL=C sort -u)"
    _sorted_cnt="$(printf '%s' "$COUNTABLE" | env LC_ALL=C sort -u)"
    if [ "$_sorted_rec" != "$_sorted_cnt" ]; then
      echo "$PROG: the countable id set differs from the one recorded at the last /rules check --confirm — verdict unstamped" >&2
      UNSTAMPED_REASON="countable_set_drift"
      _emit unstamped
    fi ;;
  legacy)
    if [ "$COUNTABLE_N" -gt 0 ]; then
      echo "$PROG: the stamp predates the recorded countable set and $COUNTABLE_N id(s) are countable — verdict unstamped" >&2
      UNSTAMPED_REASON="legacy_stamp"
      _emit unstamped
    fi ;;
  absent) : ;;   # nothing recorded ⇒ nothing to drift from; the replay itself answers unstamped
esac
[ "$LISTED_N" -gt 0 ] || _emit none

# _is_countable <id> — exit 0 iff <id> is exactly one of the countable ids (whole line, literal).
_is_countable() {
  case $'\n'"$COUNTABLE" in *$'\n'"$1"$'\n'*) return 0 ;; esac
  return 1
}

# ADVISORY_ONLY=1 ⇒ the verdict is `none` whatever happens below (D-b: countable == [] ⇒ none, ranked
# ABOVE cmd_disabled / unstamped / unresolved). The replay still runs (unless the no-cmd valve is set)
# PURELY for the report line: an advisory id's pass/fail lands in passed/failing and checks_passed
# keeps today's `passed n/m`, but nothing the replay says — including a forged or unreadable output —
# can turn an advisory-only store into anything but `none`.
ADVISORY_ONLY=0
[ "$COUNTABLE_N" -gt 0 ] || ADVISORY_ONLY=1

# ---- (4) the unattended no-cmd valve: decided from the environment, --if-stamped never invoked -------
if [ "${RULES_CHECK_NO_CMD:-0}" = "1" ]; then
  [ "$ADVISORY_ONLY" -eq 1 ] && _emit none
  _emit cmd_disabled
fi

# _verdict_or_none <verdict> — emit <verdict>, or `none` when nothing selected is countable.
_verdict_or_none() {
  if [ "$ADVISORY_ONLY" -eq 1 ]; then _emit none; fi
  _emit "$1"
}

# ---- (5) the ONE replay ------------------------------------------------------------------------------
RUN_OUT="$(bash "$CHECKER" --if-stamped </dev/null 2>/dev/null)"; RUN_RC=$?

# Step 0: empty stdout — the checker never reached its per-rule loop.
if [ -z "$RUN_OUT" ]; then
  [ "$ADVISORY_ONLY" -eq 1 ] && _emit none
  _unreadable "rules-check.sh --if-stamped printed nothing"
fi

# Step 1: unstamped — only when nothing executed (exact whole line, and no RUN line).
if grep -Fxq -- "  [SKIP] all (unstamped)" <<<"$RUN_OUT" \
   && ! grep -q '^  \[RUN \] ' <<<"$RUN_OUT"; then
  UNSTAMPED_REASON="never_confirmed"
  _verdict_or_none unstamped
fi

# Step 2: the trailer rule (shared lib). Failure ⇒ every COUNTABLE id unresolved (D-b); the advisory
# ids are not listed — nothing about them could be resolved either, and they never decide.
if ! rules_replay_trailer_ok "$RUN_OUT" "$RUN_RC" "$LISTED_N"; then
  UNRESOLVED="$COUNTABLE"
  _verdict_or_none unresolved
fi
_last="${RUN_OUT##*$'\n'}"
CHECKS_PASSED="${_last#Checks passed: }"

# Step 3: per-id map (shared lib) of EVERY selected id. Only COUNTABLE ids decide; advisory ids are
# reported in passed / failing / unresolved for the consumer's report line and never change the verdict.
ANY_FAIL=0
ANY_UNRESOLVED=0
while IFS= read -r id; do
  [ -n "$id" ] || continue
  m="$(rules_replay_map_id "$id" "$RUN_OUT" "$LISTED")"
  case "$m" in
    pass) PASSED="$PASSED$id"$'\n' ;;
    fail) FAILING="$FAILING$id"$'\n'
          _is_countable "$id" && ANY_FAIL=1 ;;
    *)    UNRESOLVED="$UNRESOLVED$id"$'\n'
          _is_countable "$id" && ANY_UNRESOLVED=1 ;;
  esac
done <<EOF
$SELECTED
EOF

if [ "$ANY_FAIL" -eq 1 ]; then
  _verdict_or_none fail
elif [ "$ANY_UNRESOLVED" -eq 1 ]; then
  _verdict_or_none unresolved
fi
_verdict_or_none ok
