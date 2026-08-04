#!/usr/bin/env bash
# test-drain-rounds.sh — self-tests for drain-rounds.sh, the mechanized shared
# ceiling for the §U4 bounded drain loop (skills/review-heal/SKILL.md). Runs
# entirely inside an isolated `mktemp -d` working directory (the script writes
# its ledger under `.supervisor/drain-rounds/` relative to cwd), so it NEVER
# touches this repo's own `.supervisor/`. Auto-included by ci.yml's
# `loomwright/scripts/test-*.sh` glob — must be ubuntu-clean, not merely
# macOS-clean (machine lesson: BSD vs GNU userland).
#
# Covers:
#   (A) init/bump/check happy path across two different PR keys (no cross-key bleed).
#   (B) AC1 — driving the counter PAST the declared ceiling: check returns
#       BOUND_HIT (exit 1) at the ceiling AND stays BOUND_HIT on further bumps
#       past it (never silently resets, never "un-hits").
#   (C) AC5 — fail CLOSED on an unreadable/absent/garbage ledger for check AND
#       bump (never OK, never a silent pass, never a crash).
#   (D) init is idempotent / re-callable (a fresh drain run always starts at 0
#       even if a stale ledger exists from a prior run on the same PR).
#   (E) `read` introspection: absent ⇒ `{}`; present ⇒ echoes the ledger.
#   (F) usage/argument errors (missing subcommand, missing pr, non-integer
#       max_rounds) exit non-zero and never write a ledger.
#   (G) no hardcoded ceiling: init accepts ANY caller-supplied integer (3, 5,
#       8, 1) — the script itself asserts nothing about which value is "the"
#       default (that lives at review-heal/SKILL.md:365 only).

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DR="$SCRIPT_DIR/drain-rounds.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT" 2>/dev/null' EXIT

run() {  # run <cwd> <args...> -> sets OUT/RC
  local d="$1"; shift
  OUT="$(cd "$d" && bash "$DR" "$@" 2>&1)"; RC=$?
}

echo "== A. init/bump/check happy path, two independent PR keys =="
D="$ROOT/a"; mkdir -p "$D"

run "$D" init "https://github.com/o/r/pull/1" 5
[ "$RC" -eq 0 ] && [ "$OUT" = "OK" ] && ok "init pr1 max=5 -> OK" || no "init pr1 ($RC: $OUT)"

run "$D" init "https://github.com/o/r/pull/2" 3
[ "$RC" -eq 0 ] && [ "$OUT" = "OK" ] && ok "init pr2 max=3 -> OK" || no "init pr2 ($RC: $OUT)"

run "$D" check "https://github.com/o/r/pull/1"
[ "$RC" -eq 0 ] && [ "$OUT" = "OK" ] && ok "check pr1 round 0/5 -> OK" || no "check pr1 ($RC: $OUT)"

run "$D" bump "https://github.com/o/r/pull/1"
[ "$RC" -eq 0 ] && [ "$OUT" = "1" ] && ok "bump pr1 -> rounds=1" || no "bump pr1 ($RC: $OUT)"

# pr2's ledger must be untouched by pr1's bump (no cross-key bleed).
run "$D" check "https://github.com/o/r/pull/2"
[ "$RC" -eq 0 ] && [ "$OUT" = "OK" ] && ok "check pr2 still round 0/3 (no cross-key bleed)" || no "check pr2 ($RC: $OUT)"

echo "== B. AC1 — drive the counter PAST the ceiling =="
D="$ROOT/b"; mkdir -p "$D"
run "$D" init "pr-b" 3
[ "$RC" -eq 0 ] || no "init pr-b setup failed"

run "$D" bump "pr-b"; run "$D" bump "pr-b"; run "$D" bump "pr-b"   # rounds -> 3 == max
run "$D" check "pr-b"
[ "$RC" -eq 1 ] && [ "$OUT" = "BOUND_HIT" ] && ok "AC1: rounds==max_rounds -> BOUND_HIT (exit 1)" || no "AC1 at-ceiling ($RC: $OUT)"

run "$D" bump "pr-b"   # drive PAST the ceiling (rounds -> 4)
run "$D" check "pr-b"
[ "$RC" -eq 1 ] && [ "$OUT" = "BOUND_HIT" ] && ok "AC1: rounds PAST max_rounds -> still BOUND_HIT, never resets" || no "AC1 past-ceiling ($RC: $OUT)"

echo "== C. AC5 — fail CLOSED on unreadable/absent/garbage ledger =="
D="$ROOT/c"; mkdir -p "$D"

run "$D" check "never-initialized-pr"
[ "$RC" -eq 2 ] && [ "$OUT" = "ESCALATED: unreadable_round_ledger" ] && ok "AC5: check on never-init'd PR fails CLOSED (exit 2)" || no "AC5 check-absent ($RC: $OUT)"

run "$D" bump "never-initialized-pr"
[ "$RC" -eq 2 ] && [ "$OUT" = "ESCALATED: unreadable_round_ledger" ] && ok "AC5: bump on never-init'd PR fails CLOSED (exit 2)" || no "AC5 bump-absent ($RC: $OUT)"

mkdir -p "$D/.supervisor/drain-rounds"
# Compute the same hash the script would use, by initializing then corrupting.
run "$D" init "garbage-pr" 5
GLEDGER="$(cd "$D" && bash "$DR" read "garbage-pr")"
# Find the ledger file the script actually wrote and stomp it with garbage bytes.
LFILE="$(find "$D/.supervisor/drain-rounds" -name '*.json' | head -1)"
printf 'not valid json at all {{{' > "$LFILE"

run "$D" check "garbage-pr"
[ "$RC" -eq 2 ] && [ "$OUT" = "ESCALATED: unreadable_round_ledger" ] && ok "AC5: garbage ledger content -> check fails CLOSED" || no "AC5 check-garbage ($RC: $OUT)"

run "$D" bump "garbage-pr"
[ "$RC" -eq 2 ] && [ "$OUT" = "ESCALATED: unreadable_round_ledger" ] && ok "AC5: garbage ledger content -> bump fails CLOSED" || no "AC5 bump-garbage ($RC: $OUT)"

# Partial ledger — rounds present, max_rounds missing — must ALSO fail closed.
printf '{"rounds":1}' > "$LFILE"
run "$D" check "garbage-pr"
[ "$RC" -eq 2 ] && [ "$OUT" = "ESCALATED: unreadable_round_ledger" ] && ok "AC5: partial ledger (missing max_rounds) -> fails CLOSED" || no "AC5 check-partial ($RC: $OUT)"

echo "== D. init is idempotent / always resets to 0 =="
D="$ROOT/d"; mkdir -p "$D"
run "$D" init "pr-d" 4
run "$D" bump "pr-d"; run "$D" bump "pr-d"   # rounds -> 2
run "$D" init "pr-d" 4   # re-init: MUST reset to 0, not preserve stale rounds
run "$D" check "pr-d"
[ "$RC" -eq 0 ] && [ "$OUT" = "OK" ] && ok "init overwrites a stale ledger back to rounds=0" || no "D re-init ($RC: $OUT)"
run "$D" read "pr-d"
case "$OUT" in
  *'"rounds":0'*) ok "read confirms rounds reset to 0 after re-init" ;;
  *) no "read after re-init: $OUT" ;;
esac

echo "== E. read introspection =="
D="$ROOT/e"; mkdir -p "$D"
run "$D" read "never-seen-pr"
[ "$RC" -eq 0 ] && [ "$OUT" = "{}" ] && ok "read on absent ledger -> {} exit 0" || no "E read-absent ($RC: $OUT)"

run "$D" init "pr-e" 7
run "$D" read "pr-e"
case "$OUT" in
  *'"rounds":0'*'"max_rounds":7'*) ok "read on present ledger echoes rounds/max_rounds" ;;
  *) no "E read-present: $OUT" ;;
esac

echo "== F. usage / argument errors =="
D="$ROOT/f"; mkdir -p "$D"

run "$D"
[ "$RC" -ne 0 ] && ok "no subcommand -> non-zero exit" || no "F no-subcommand should fail ($RC)"

run "$D" init
[ "$RC" -ne 0 ] && ok "init with no args -> non-zero exit" || no "F init-no-args should fail ($RC)"

run "$D" init "pr-f"
[ "$RC" -ne 0 ] && ok "init missing max_rounds -> non-zero exit" || no "F init-no-max should fail ($RC)"

run "$D" init "pr-f" "not-a-number"
[ "$RC" -ne 0 ] && ok "init non-integer max_rounds -> non-zero exit" || no "F init-bad-max should fail ($RC)"
LEDGER_COUNT_F="$(find "$D/.supervisor/drain-rounds" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
[ "${LEDGER_COUNT_F:-0}" -eq 0 ] && ok "bad init never writes a ledger file" || no "bad init wrote a ledger anyway (count=$LEDGER_COUNT_F)"

run "$D" bogus-subcommand "pr-f"
[ "$RC" -ne 0 ] && ok "unknown subcommand -> non-zero exit" || no "F unknown-subcommand should fail ($RC)"

echo "== G. no hardcoded ceiling — script accepts any caller-supplied max =="
D="$ROOT/g"; mkdir -p "$D"
for m in 1 3 5 8; do
  run "$D" init "pr-g-$m" "$m"
  [ "$RC" -eq 0 ] || no "G init max=$m failed"
  run "$D" bump "pr-g-$m"
  [ "$OUT" = "1" ] || no "G bump max=$m unexpected output: $OUT"
  run "$D" check "pr-g-$m"
  if [ "$m" -eq 1 ]; then
    [ "$RC" -eq 1 ] && [ "$OUT" = "BOUND_HIT" ] && ok "G max=$m: round 1 already at ceiling -> BOUND_HIT" || no "G max=$m check wrong ($RC: $OUT)"
  else
    [ "$RC" -eq 0 ] && [ "$OUT" = "OK" ] && ok "G max=$m: round 1/$m -> OK" || no "G max=$m check wrong ($RC: $OUT)"
  fi
done

echo ""
echo "== SUMMARY: $pass passed, $fail failed =="
[ "$fail" -eq 0 ] || exit 1
exit 0
