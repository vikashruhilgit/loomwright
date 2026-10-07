#!/usr/bin/env bash
# test-read-token-ledger.sh — self-tests for scripts/read-token-ledger.sh.
# Isolated: every fixture lives under a fresh mktemp -d, the SUT is invoked
# as a subprocess (never sourced), and `--root` pins it to that fixture so
# the real repo's `.supervisor/` is never touched. Exit 0 = all pass.
#
# Covers:
#   1. --session: 3 well-formed token_ledger events sum correctly, EVENTS=3.
#   2. --session: a malformed (non-JSON) line is skipped, never a hard error.
#   3. --session: a proxy-only (`"proxy":true`, no usage fields) event
#      contributes 0 to INPUT/OUTPUT/CACHE_READ/CACHE_CREATE/TOTAL but is
#      still counted in EVENTS.
#   4. --session: a missing session file -> all-zero + LEDGER_UNREADABLE=1, rc=0.
#   5. --session: an unreadable (chmod 000) session file -> all-zero + LEDGER_UNREADABLE=1.
#   6. --run-id: resolves session ids from a run file's `## Progress`
#      `session_id <id>` lines and sums the UNION of those sessions.
#   7. --run-id: a run file naming TWO sessions sums BOTH.
#   8. --run-id: missing run file -> all-zero + LEDGER_UNREADABLE=1.
#   9. --run-id: run file with no `session_id` lines at all -> all-zero + LEDGER_UNREADABLE=1.
#  10. --run-id: one named session missing on disk, the other present -> sums
#      only the present one, does NOT set LEDGER_UNREADABLE (partial-sum honest limit).
#  11. --run-id accepts a literal existing path (not just a bare run id).
#  12. non-token_ledger events in the same file are ignored (not summed, not counted).
#  13. jq missing on PATH -> fail-safe all-zero + LEDGER_UNREADABLE=1, rc=0 (never a hard error).
#  14. bad usage (no --session/--run-id) -> non-zero exit (die_usage), never a silent success.
#  --- Mutation control ---
#  15. mutating the reader so numf() always returns 0 makes a KNOWN-non-zero
#      fixture report TOTAL=0 -- proving the normal (unmutated) script's
#      non-zero result in test 1 is load-bearing, not a fixture accident.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/read-token-ledger.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

fresh_root() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/.supervisor/logs" "$d/.supervisor/automate"
  printf '%s' "$d"
}

run_sut() {
  RUN_OUT="$(bash "$SUT" "$@" 2>/dev/null)"
  RUN_RC=$?
}

field() {
  # field <line> <NAME> -> numeric value after NAME=
  printf '%s' "$1" | grep -oE "$2=[0-9]+" | head -1 | cut -d= -f2
}

echo "== 1. --session: 3 well-formed events sum correctly =="
D1="$(fresh_root)"
cat > "$D1/.supervisor/logs/s1.jsonl" <<'EOF'
{"event":"token_ledger","session_id":"s1","input_tokens":100,"output_tokens":50,"cache_read_input_tokens":10,"cache_creation_input_tokens":5}
{"event":"token_ledger","session_id":"s1","input_tokens":20,"output_tokens":10,"cache_read_input_tokens":1,"cache_creation_input_tokens":1}
{"event":"token_ledger","session_id":"s1","input_tokens":5,"output_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}
EOF
run_sut --session s1 --root "$D1"
if [ "$RUN_RC" -eq 0 ] \
   && [ "$(field "$RUN_OUT" INPUT)" = "125" ] \
   && [ "$(field "$RUN_OUT" OUTPUT)" = "65" ] \
   && [ "$(field "$RUN_OUT" CACHE_READ)" = "11" ] \
   && [ "$(field "$RUN_OUT" CACHE_CREATE)" = "6" ] \
   && [ "$(field "$RUN_OUT" TOTAL)" = "207" ] \
   && [ "$(field "$RUN_OUT" EVENTS)" = "3" ]; then
  ok "3-event sum correct: $RUN_OUT"
else
  no "3-event sum wrong: $RUN_OUT"
fi

echo "== 2. --session: malformed line skipped, not a hard error =="
D2="$(fresh_root)"
cat > "$D2/.supervisor/logs/s2.jsonl" <<'EOF'
{"event":"token_ledger","session_id":"s2","input_tokens":10,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}
this is not json
{"event":"token_ledger","session_id":"s2","input_tokens":5,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}
EOF
run_sut --session s2 --root "$D2"
if [ "$RUN_RC" -eq 0 ] && [ "$(field "$RUN_OUT" INPUT)" = "15" ] && [ "$(field "$RUN_OUT" EVENTS)" = "2" ]; then
  ok "malformed line skipped, valid lines still summed: $RUN_OUT"
else
  no "malformed line handling wrong: $RUN_OUT"
fi

echo "== 3. --session: proxy-only event contributes 0 to real sums, still counted in EVENTS =="
D3="$(fresh_root)"
cat > "$D3/.supervisor/logs/s3.jsonl" <<'EOF'
{"event":"token_ledger","session_id":"s3","input_tokens":10,"output_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}
{"event":"token_ledger","session_id":"s3","proxy":true,"token_proxy_kind":"transcript_bytes","token_proxy_transcript_bytes":45000}
EOF
run_sut --session s3 --root "$D3"
if [ "$RUN_RC" -eq 0 ] && [ "$(field "$RUN_OUT" INPUT)" = "10" ] && [ "$(field "$RUN_OUT" OUTPUT)" = "5" ] \
   && [ "$(field "$RUN_OUT" TOTAL)" = "15" ] && [ "$(field "$RUN_OUT" EVENTS)" = "2" ]; then
  ok "proxy-only line contributes 0 to real sums but counts in EVENTS: $RUN_OUT"
else
  no "proxy-only handling wrong: $RUN_OUT"
fi

echo "== 4. --session: missing file -> all-zero + LEDGER_UNREADABLE=1, rc=0 =="
D4="$(fresh_root)"
run_sut --session nope --root "$D4"
if [ "$RUN_RC" -eq 0 ] && grep -q 'LEDGER_UNREADABLE=1' < <(printf '%s' "$RUN_OUT") \
   && [ "$(field "$RUN_OUT" TOTAL)" = "0" ] && [ "$(field "$RUN_OUT" EVENTS)" = "0" ]; then
  ok "missing session file fail-safe: $RUN_OUT"
else
  no "missing session file did not fail safe: $RUN_OUT (rc=$RUN_RC)"
fi

echo "== 5. --session: unreadable file -> all-zero + LEDGER_UNREADABLE=1 =="
D5="$(fresh_root)"
echo '{"event":"token_ledger","session_id":"s5","input_tokens":1,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}' > "$D5/.supervisor/logs/s5.jsonl"
chmod 000 "$D5/.supervisor/logs/s5.jsonl"
run_sut --session s5 --root "$D5"
if [ "$(id -u)" = "0" ]; then
  echo "  skip: running as root, chmod 000 has no effect"
elif [ "$RUN_RC" -eq 0 ] && grep -q 'LEDGER_UNREADABLE=1' < <(printf '%s' "$RUN_OUT"); then
  ok "unreadable session file fail-safe: $RUN_OUT"
else
  no "unreadable session file did not fail safe: $RUN_OUT (rc=$RUN_RC)"
fi
chmod 644 "$D5/.supervisor/logs/s5.jsonl" 2>/dev/null || true

echo "== 6. --run-id: resolves session ids from run file Progress lines =="
D6="$(fresh_root)"
cat > "$D6/.supervisor/logs/sA.jsonl" <<'EOF'
{"event":"token_ledger","session_id":"sA","input_tokens":100,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}
EOF
cat > "$D6/.supervisor/automate/run6.md" <<'EOF'
# Automate Run: t
## Progress
- ts picked item1
- ts session_id sA (item1)
EOF
run_sut --run-id run6 --root "$D6"
if [ "$RUN_RC" -eq 0 ] && [ "$(field "$RUN_OUT" INPUT)" = "100" ]; then
  ok "run-id resolves single named session: $RUN_OUT"
else
  no "run-id single-session resolution wrong: $RUN_OUT"
fi

echo "== 7. --run-id: two named sessions -> sums BOTH =="
D7="$(fresh_root)"
cat > "$D7/.supervisor/logs/sB.jsonl" <<'EOF'
{"event":"token_ledger","session_id":"sB","input_tokens":100,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}
EOF
cat > "$D7/.supervisor/logs/sC.jsonl" <<'EOF'
{"event":"token_ledger","session_id":"sC","input_tokens":50,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}
EOF
cat > "$D7/.supervisor/automate/run7.md" <<'EOF'
# Automate Run: t
## Progress
- ts picked item1
- ts session_id sB (item1)
- ts ran /autonomous -> PR https://github.com/acme/w/pull/1
- ts picked item2
- ts session_id sC (item2)
EOF
run_sut --run-id run7 --root "$D7"
if [ "$RUN_RC" -eq 0 ] && [ "$(field "$RUN_OUT" INPUT)" = "150" ]; then
  ok "run-id sums two named sessions: $RUN_OUT"
else
  no "run-id two-session sum wrong: $RUN_OUT"
fi

echo "== 8. --run-id: missing run file -> all-zero + LEDGER_UNREADABLE=1 =="
D8="$(fresh_root)"
run_sut --run-id nope --root "$D8"
if [ "$RUN_RC" -eq 0 ] && grep -q 'LEDGER_UNREADABLE=1' < <(printf '%s' "$RUN_OUT"); then
  ok "missing run file fail-safe: $RUN_OUT"
else
  no "missing run file did not fail safe: $RUN_OUT (rc=$RUN_RC)"
fi

echo "== 9. --run-id: run file with no session_id lines -> all-zero + LEDGER_UNREADABLE=1 =="
D9="$(fresh_root)"
cat > "$D9/.supervisor/automate/run9.md" <<'EOF'
# Automate Run: t
## Progress
- ts picked item1
EOF
run_sut --run-id run9 --root "$D9"
if [ "$RUN_RC" -eq 0 ] && grep -q 'LEDGER_UNREADABLE=1' < <(printf '%s' "$RUN_OUT"); then
  ok "no session_id lines fail-safe: $RUN_OUT"
else
  no "no session_id lines did not fail safe: $RUN_OUT (rc=$RUN_RC)"
fi

echo "== 10. --run-id: one named session missing on disk, other present -> partial sum, no LEDGER_UNREADABLE =="
D10="$(fresh_root)"
cat > "$D10/.supervisor/logs/sPresent.jsonl" <<'EOF'
{"event":"token_ledger","session_id":"sPresent","input_tokens":77,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}
EOF
cat > "$D10/.supervisor/automate/run10.md" <<'EOF'
# Automate Run: t
## Progress
- ts session_id sMissing (item1)
- ts session_id sPresent (item2)
EOF
run_sut --run-id run10 --root "$D10"
if [ "$RUN_RC" -eq 0 ] && [ "$(field "$RUN_OUT" INPUT)" = "77" ] && ! grep -q 'LEDGER_UNREADABLE' < <(printf '%s' "$RUN_OUT"); then
  ok "partial resolution sums the present session, no false-unreadable flag: $RUN_OUT"
else
  no "partial resolution wrong: $RUN_OUT"
fi

echo "== 11. --run-id accepts a literal existing path =="
D11="$(fresh_root)"
cat > "$D11/.supervisor/logs/sD.jsonl" <<'EOF'
{"event":"token_ledger","session_id":"sD","input_tokens":9,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}
EOF
cat > "$D11/myrun.md" <<'EOF'
## Progress
- ts session_id sD (item1)
EOF
run_sut --run-id "$D11/myrun.md" --root "$D11"
if [ "$RUN_RC" -eq 0 ] && [ "$(field "$RUN_OUT" INPUT)" = "9" ]; then
  ok "literal run-file path accepted: $RUN_OUT"
else
  no "literal run-file path rejected: $RUN_OUT"
fi

echo "== 12. non-token_ledger events ignored =="
D12="$(fresh_root)"
cat > "$D12/.supervisor/logs/s12.jsonl" <<'EOF'
{"event":"agent_lifecycle","session_id":"s12","state":"failed"}
{"event":"token_ledger","session_id":"s12","input_tokens":3,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}
{"event":"session_end","session_id":"s12"}
EOF
run_sut --session s12 --root "$D12"
if [ "$RUN_RC" -eq 0 ] && [ "$(field "$RUN_OUT" INPUT)" = "3" ] && [ "$(field "$RUN_OUT" EVENTS)" = "1" ]; then
  ok "non-token_ledger events ignored: $RUN_OUT"
else
  no "non-token_ledger events not ignored: $RUN_OUT"
fi

echo "== 13. jq missing on PATH -> fail-safe all-zero + LEDGER_UNREADABLE=1 =="
D13="$(fresh_root)"
cat > "$D13/.supervisor/logs/s13.jsonl" <<'EOF'
{"event":"token_ledger","session_id":"s13","input_tokens":3,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}
EOF
NO_JQ_OUT="$(LOOMWRIGHT_JQ_BIN=/nonexistent/jq bash "$SUT" --session s13 --root "$D13" 2>/dev/null)"
NO_JQ_RC=$?
if [ "$NO_JQ_RC" -eq 0 ] && grep -q 'LEDGER_UNREADABLE=1' < <(printf '%s' "$NO_JQ_OUT"); then
  ok "missing jq fail-safe: $NO_JQ_OUT"
else
  no "missing jq did not fail safe: $NO_JQ_OUT (rc=$NO_JQ_RC)"
fi

echo "== 14. bad usage -> non-zero exit, never a silent success =="
BAD_OUT="$(bash "$SUT" 2>&1)"; BAD_RC=$?
if [ "$BAD_RC" -ne 0 ]; then
  ok "no args -> non-zero exit ($BAD_RC)"
else
  no "no args should not exit 0: $BAD_OUT"
fi

echo "== 15. MUTATION CONTROL: numf() always-0 makes a known-non-zero fixture report TOTAL=0 =="
MUTDIR="$(mktemp -d)"
MUT="$MUTDIR/read-token-ledger.sh"
cp "$SUT" "$MUT"
# The guard under test: `def numf(x): if (x|type)=="number" then x else 0 end;`
# Replace it with an always-0 function -- if this mutant STILL reports the
# real (non-zero) sum, the numf() guard is not load-bearing (test would be vacuous).
sed -i.bak 's/def numf(x): if (x|type)=="number" then x else 0 end;/def numf(x): 0;/' "$MUT"
if bash -n "$MUT" 2>/dev/null && ! diff -q "$MUT" "$SUT" >/dev/null 2>&1; then
  D15="$(fresh_root)"
  cat > "$D15/.supervisor/logs/s15.jsonl" <<'EOF'
{"event":"token_ledger","session_id":"s15","input_tokens":42,"output_tokens":8,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}
EOF
  MUT_OUT="$(bash "$MUT" --session s15 --root "$D15" 2>/dev/null)"
  if [ "$(field "$MUT_OUT" TOTAL)" = "0" ]; then
    ok "mutation control: always-0 numf() flips a known 50-token fixture to TOTAL=0 -- the guard is load-bearing (mutant='$MUT_OUT')"
  else
    no "mutation control REFUTED: mutant still reported non-zero -- numf() may not be load-bearing (mutant='$MUT_OUT')"
  fi
else
  no "mutation control: could not build the mutant (sed did not apply or bash -n failed) -- control inconclusive"
fi
rm -rf "$MUTDIR"

echo "== 15. parallel-automate/05 Scope 8: --root repeated sums across roots (one line) =="
MR="$(mktemp -d)"
for mr_r in P L1 L2; do mkdir -p "$MR/$mr_r/.supervisor/logs" "$MR/$mr_r/.supervisor/automate"; done
mr_ev() { printf '{"event":"token_ledger","input_tokens":%s,"output_tokens":%s,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}\n' "$2" "$3" >> "$1"; }
mr_ev "$MR/P/.supervisor/logs/s9.jsonl" 100 10
mr_ev "$MR/L1/.supervisor/logs/s9.jsonl" 20 2
mr_out="$(bash "$SUT" --session s9 --root "$MR/P" --root "$MR/L1" --root "$MR/L2")"
[ "$mr_out" = "INPUT=120 OUTPUT=12 CACHE_READ=0 CACHE_CREATE=0 TOTAL=132 EVENTS=2" ] && ok "--session over three roots sums the two readable ledgers into ONE line (a root with no log adds 0)" || no "multi-root --session: $mr_out"
mr_out="$(bash "$SUT" --session s9 --root "$MR/P" --root "$MR/P")"
[ "$mr_out" = "INPUT=100 OUTPUT=10 CACHE_READ=0 CACHE_CREATE=0 TOTAL=110 EVENTS=1" ] && ok "a root named twice is read once (no double count)" || no "duplicate root: $mr_out"
# --run-id <parent>: the parent's run file in the primary + each lane's own <parent>-L<n>.md via lane.json.
printf '# Automate Run: par-7\n## Progress\n- t session_id sp (x)\n' > "$MR/P/.supervisor/automate/par-7.md"
mr_ev "$MR/P/.supervisor/logs/sp.jsonl" 1000 0
for mr_n in 1 2; do
  printf '{"schema_version":1,"lane":"L%s","run_id":"par-7-L%s","parent_run_id":"par-7"}\n' "$mr_n" "$mr_n" > "$MR/L$mr_n/.supervisor/lane.json"
  printf '# Automate Run: par-7-L%s — x\n## Progress\n- t session_id sl%s (x)\n' "$mr_n" "$mr_n" > "$MR/L$mr_n/.supervisor/automate/par-7-L$mr_n.md"
  mr_ev "$MR/L$mr_n/.supervisor/logs/sl$mr_n.jsonl" "${mr_n}00" 0
done
mr_out="$(bash "$SUT" --run-id par-7 --root "$MR/P" --root "$MR/L1" --root "$MR/L2")"
[ "$mr_out" = "INPUT=1300 OUTPUT=0 CACHE_READ=0 CACHE_CREATE=0 TOTAL=1300 EVENTS=3" ] && ok "--run-id <parent> over the primary + two lanes sums every lane's own run sessions (parent total)" || no "multi-root --run-id: $mr_out"
mr_out="$(bash "$SUT" --run-id par-7 --root "$MR/P")"
[ "$mr_out" = "INPUT=1000 OUTPUT=0 CACHE_READ=0 CACHE_CREATE=0 TOTAL=1000 EVENTS=1" ] && ok "one --root is unchanged: only that root's run is summed" || no "single root: $mr_out"
mr_out="$(bash "$SUT" --session nope --root "$MR/L1" --root "$MR/L2")"
[ "$mr_out" = "INPUT=0 OUTPUT=0 CACHE_READ=0 CACHE_CREATE=0 TOTAL=0 EVENTS=0 LEDGER_UNREADABLE=1" ] && ok "no root readable ⇒ LEDGER_UNREADABLE=1 (never a silent 0)" || no "none readable: $mr_out"
rm -rf "$MR"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
