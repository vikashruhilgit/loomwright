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
#  PI1-PI20. --per-item (automate-speed/03) over token-ledger-fixtures/per-item/:
#      item + phase rows (PR #533's spans), message-id de-dup and its mutation
#      control, wall time = phase-timing.sh's, missing boundary / no park / two
#      drains, no_transcripts, lane attribution, unpicked item, env projects
#      dir, fail-safe exits, existing modes unchanged, no_usage_in_window (item
#      and phase), inverted window, sibling-lane 'picked in lane', an item
#      parked then resumed (work_after_park), phase row <= item row, and a
#      /bin/bash (3.2) parse check. PI21: a value-taking flag given last
#      (no value) ⇒ usage + exit 1, never a parse-loop hang.

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

# ---- --per-item (automate-speed/03) -----------------------------------------
# Fixture: token-ledger-fixtures/per-item/ — run.md (items a..e; a carries PR #533's
# exact Progress timestamps), session-logs/ (copied into a mktemp root's
# .supervisor/logs), projects/ (synthetic transcripts — every call passes
# --projects-dir or LOOMWRIGHT_CC_PROJECTS_DIR, so the real home dir is never read)
# and lane/ (a lane clone of run `run`).
PIF="$HERE/token-ledger-fixtures/per-item"
PIP="$PIF/projects"
PI="$(mktemp -d)"
mkdir -p "$PI/p/.supervisor/logs" "$PI/l/.supervisor/logs" "$PI/l/.supervisor/automate"
cp "$PIF/session-logs/"* "$PI/p/.supervisor/logs/"
cp "$PIF/lane/lane.json" "$PI/l/.supervisor/lane.json"
cp "$PIF/lane/run-L1.md" "$PI/l/.supervisor/automate/run-L1.md"
pi_run() {  # pi_run <sut> <args...> — stdout → PI_OUT, stderr → PI_ERR, rc → PI_RC
  local sut="$1"; shift
  PI_OUT="$(bash "$sut" "$@" 2>"$PI/err")"; PI_RC=$?
  PI_ERR="$(cat "$PI/err")"
}
pi_row() { printf '%s\n' "$PI_OUT" | grep -F -- "$1" | head -1; }
# pi_rows_after <item row marker> — the item row and the ↳ rows under it
pi_rows_after() { printf '%s\n' "$PI_OUT" | awk -v m="$1" 'index($0, m) {on=1; print; next} on && /^\| ↳/ {print; next} on {exit}'; }
fmt_wall() { local s="$1"; if [ "$s" -ge 3600 ]; then echo "$((s/3600))h $(((s%3600)/60))m $((s%60))s"; else echo "$((s/60))m $((s%60))s"; fi; }

echo "== PI1. --per-item: one row per item, phase rows under it, every token figure labelled real usage (AC1) =="
pi_run "$SUT" --per-item "$PIF/run.md" --root "$PI/p" --root "$PI/l" --projects-dir "$PIP"
[ "$PI_RC" -eq 0 ] && ok "per-item exits 0" || no "per-item rc=$PI_RC"
grep -qF "| Item / phase | Window (UTC) | Wall | Context tokens (real usage) | Output tokens (real usage) | Turns (main) | Peak context (real usage, main) | Subagent tokens by type (real usage, context/output) |" <<<"$PI_OUT" \
  && ok "header labels every token column real usage" || no "header wrong: $(printf '%s\n' "$PI_OUT" | grep -F '| Item / phase' )"
[ "$(pi_row '| **.supervisor/requirements/a.md** |')" = "| **.supervisor/requirements/a.md** | 10-13 15:33:58 → 10-14 01:00:27 | 9h 26m 29s | 29510 (main 28210) | 289 (main 276) | 8 | 7000 | code-reviewer 800/8; worker 500/5 |" ] \
  && ok "item row: context/output totals (main part), turns, peak, subagents by type" || no "item a row: $(pi_row '| **.supervisor/requirements/a.md** |')"
pi_a="$(pi_rows_after '| **.supervisor/requirements/a.md** |')"
[ "$(printf '%s\n' "$pi_a" | grep -c '^| ↳')" -eq 8 ] && ok "item a has 8 phase/sub rows under it" || no "item a phase rows: $pi_a"
grep -qxF "| ↳ Launch Pad | 10-13 15:33:58 → 15:46:53 | 12m 55s | 1110 (main 1110) | 5 (main 5) | 1 | 1110 | — |" <<<"$pi_a" \
  && ok "Launch Pad 12m 55s (picked → launch-pad saved)" || no "Launch Pad row: $(printf '%s\n' "$pi_a" | grep -F 'Launch Pad')"
grep -qxF "| ↳ Build | 10-13 15:46:53 → 16:27:01 | 40m 8s | 2500 (main 2000) | 25 (main 20) | 1 | 2000 | worker 500/5 |" <<<"$pi_a" \
  && ok "Build 40m 8s (launch-pad saved → FINALIZE:), worker subagent attributed" || no "Build row: $(printf '%s\n' "$pi_a" | grep -F '↳ Build')"
grep -qxF "| ↳ Phase 4.5 | 10-13 16:27:01 → 17:52:01 | 1h 25m 0s | 12900 (main 12100) | 129 (main 121) | 4 | 5000 | code-reviewer 800/8 |" <<<"$pi_a" \
  && ok "Phase 4.5 1h 25m 0s (FINALIZE: → ran /autonomous)" || no "Phase 4.5 row: $(printf '%s\n' "$pi_a" | grep -F '↳ Phase 4.5')"
grep -qxF "| ↳ ↳ iter 1 | 10-13 16:27:01 → 17:07:58 | 40m 57s | 3900 (main 3100) | 39 (main 31) | 2 | 3000 | code-reviewer 800/8 |" <<<"$pi_a" \
  && grep -qxF "| ↳ ↳ iter 2 | 10-13 17:07:58 → 17:29:56 | 21m 58s | 4000 (main 4000) | 40 (main 40) | 1 | 4000 | — |" <<<"$pi_a" \
  && grep -qxF "| ↳ ↳ after iter 2 (no iter line) | 10-13 17:29:56 → 17:52:01 | 22m 5s | 5000 (main 5000) | 50 (main 50) | 1 | 5000 | — |" <<<"$pi_a" \
  && ok "Phase 4.5 iter sub-rows: each iter line ENDS its iteration; the unlabelled rest is its own sub-row" || no "iter rows: $(printf '%s\n' "$pi_a" | grep -F 'iter')"
grep -qxF "| ↳ Drain 1 — READY | 10-13 17:52:42 → 20:03:50 | 2h 11m 8s | 6000 (main 6000) | 60 (main 60) | 1 | 6000 | — |" <<<"$pi_a" \
  && ok "Drain 2h 11m 8s (owned drain started → drain READY)" || no "Drain row: $(printf '%s\n' "$pi_a" | grep -F 'Drain')"
grep -qxF "| ↳ Decide | 10-13 20:03:50 → 10-14 01:00:27 | 4h 56m 37s | 7000 (main 7000) | 70 (main 70) | 1 | 7000 | — |" <<<"$pi_a" \
  && ok "Decide (drain READY → parked); the message after the park is excluded" || no "Decide row: $(printf '%s\n' "$pi_a" | grep -F 'Decide')"
grep -qF "9999999" <<<"$PI_OUT" && no "a message after the item's park leaked into a row" || ok "no message outside the item window is counted"
grep -qF -- "- \`.supervisor/requirements/a.md\`: session ids tried aaaaaaaa-0000-4000-8000-000000000001, sa, aaaaaaaa-0000-4000-8000-000000000002 — 4 transcript file(s)" <<<"$PI_OUT" \
  && ok "session resolution: .owner cc_session_id + the session log's cc_session_id values" || no "session line: $(printf '%s\n' "$PI_OUT" | grep -F 'a.md`:')"

echo "== PI2. --per-item: a message written 3 times (and copied into a fork) is counted ONCE (AC2) =="
# msg_a1 appears 3x in the main transcript (output 1, 1, final 5) + 1x in the second session:
# counted once ⇒ context 1110, output 5 (the stop_reason line). Counted per line it reads 4440/12.
grep -qF "| ↳ Launch Pad | 10-13 15:33:58 → 15:46:53 | 12m 55s | 1110 (main 1110) | 5 (main 5) | 1 |" <<<"$pi_a" \
  && ok "duplicate message id counted once (context 1110, output 5 from the final line, 1 turn)" || no "dedup: $(printf '%s\n' "$pi_a" | grep -F 'Launch Pad')"

echo "== PI3. MUTATION CONTROL: dropping the message-id de-duplication turns PI2 red (Validation 2) =="
PIM="$(mktemp -d)"
cp "$SUT" "$PIM/read-token-ledger.sh"; cp "$HERE/phase-timing.sh" "$HERE/progress-line-match.sh" "$PIM/"
sed -i.bak 's/^def dedup_by_msg_id: .*$/def dedup_by_msg_id: .;/' "$PIM/read-token-ledger.sh"
if [ -s "$PIM/read-token-ledger.sh" ] && bash -n "$PIM/read-token-ledger.sh" 2>/dev/null && ! diff -q "$PIM/read-token-ledger.sh" "$SUT" >/dev/null 2>&1; then
  pi_run "$PIM/read-token-ledger.sh" --per-item "$PIF/run.md" --root "$PI/p" --projects-dir "$PIP"
  mut_lp="$(pi_row '| ↳ Launch Pad | 10-13 15:33:58')"
  case "$mut_lp" in
    *"| 1110 (main 1110) | 5 (main 5) |"*) no "mutation control REFUTED: the dedup-less mutant still reports 1110/5 — the dedup step is not load-bearing ($mut_lp)" ;;
    *"| 4440 (main 4440) | 12 (main 12) |"*) ok "mutation control: the dedup-less mutant counts every line (4440/12) — the de-duplication is load-bearing" ;;
    *) no "mutation control inconclusive: mutant row '$mut_lp'" ;;
  esac
else
  no "mutation control: could not build a valid mutant (empty, identical, or bash -n failed)"
fi
rm -rf "$PIM"

echo "== PI3b. the plan-end matcher (progress-line-match.sh) unreadable ⇒ named note, Launch Pad not recorded =="
PIM="$(mktemp -d)"
cp "$SUT" "$PIM/read-token-ledger.sh"; cp "$HERE/phase-timing.sh" "$PIM/phase-timing.sh"
pi_run "$PIM/read-token-ledger.sh" --per-item "$PIF/run.md" --root "$PI/p" --projects-dir "$PIP"
{ [ "$PI_RC" -eq 0 ] && grep -qF 'per-item: progress_matcher_unreadable — ' <<<"$PI_ERR" \
    && [ -n "$(pi_row '| ↳ Launch Pad | not recorded |')" ]; } \
  && ok "no matcher beside the script ⇒ exit 0, a progress_matcher_unreadable note, Launch Pad 'not recorded' (never a wrong span)" \
  || no "unreadable matcher: rc=$PI_RC err='$(grep -F progress_matcher <<<"$PI_ERR")' row='$(pi_row '| ↳ Launch Pad |')'"
rm -rf "$PIM"

echo "== PI4. --per-item: item wall time IS phase-timing.sh's .item.pick_to_park.seconds =="
pt_secs="$(bash "$HERE/phase-timing.sh" --run "$PIF/run.md" --item .supervisor/requirements/a.md --logs-dir "$PI/p/.supervisor/logs" 2>/dev/null | jq -r '.item.pick_to_park.seconds')"
case "$pt_secs" in
  ''|*[!0-9]*) no "phase-timing gave no pick_to_park seconds ($pt_secs)" ;;
  *) case "$(pi_row '| **.supervisor/requirements/a.md** |')" in
       *"| $(fmt_wall "$pt_secs") |"*) ok "item wall $(fmt_wall "$pt_secs") = phase-timing pick_to_park ${pt_secs}s" ;;
       *) no "item wall differs from phase-timing's ${pt_secs}s: $(pi_row '| **.supervisor/requirements/a.md** |')" ;;
     esac ;;
esac

echo "== PI5. --per-item: missing boundary / no parked line / two drains (AC1) =="
pi_run "$SUT" --per-item "$PIF/run.md" --root "$PI/p" --projects-dir "$PIP"
pi_b="$(pi_rows_after '| **.supervisor/requirements/b.md** |')"
grep -qF "| **.supervisor/requirements/b.md** | 10-14 09:00:00 → 10:45:00 (no parked line — to drain READY) | not recorded | 1000 (main 1000) | 10 (main 10) |" < <(printf '%s\n' "$pi_b" | head -1) \
  && ok "no parked line ⇒ item wall 'not recorded' (never 0); total runs to the last recorded boundary, named" || no "item b row: $(printf '%s\n' "$pi_b" | head -1)"
grep -qxF "| ↳ Decide | not recorded | not recorded | not recorded | not recorded | not recorded | not recorded | not recorded |" <<<"$pi_b" \
  && ok "no parked line ⇒ Decide 'not recorded'" || no "item b Decide: $(printf '%s\n' "$pi_b" | grep -F Decide)"
grep -qxF "| ↳ Build | not recorded | not recorded | not recorded | not recorded | not recorded | not recorded | not recorded |" <<<"$pi_b" \
  && grep -qxF "| ↳ Phase 4.5 | not recorded | not recorded | not recorded | not recorded | not recorded | not recorded | not recorded |" <<<"$pi_b" \
  && ok "missing FINALIZE: ⇒ BOTH Build and Phase 4.5 'not recorded' (not 0, not merged)" || no "missing-boundary rows: $(printf '%s\n' "$pi_b" | grep -E 'Build|Phase 4.5')"
grep -qxF "| ↳ Launch Pad | 10-14 09:00:00 → 09:10:00 | 10m 0s | 100 (main 100) | 1 (main 1) | 1 | 100 | — |" <<<"$pi_b" \
  && ok "'Launch-Pad saved' (other case) still matches as the Launch Pad boundary" || no "item b Launch Pad: $(printf '%s\n' "$pi_b" | grep -F 'Launch Pad')"
grep -qxF "| ↳ Drain 1 — READY | 10-14 10:01:00 → 10:20:00 | 19m 0s | 300 (main 300) | 3 (main 3) | 1 | 300 | — |" <<<"$pi_b" \
  && grep -qxF "| ↳ Drain 2 (fix-now re-drain) — READY | 10-14 10:30:00 → 10:45:00 | 15m 0s | 400 (main 400) | 4 (main 4) | 1 | 400 | — |" <<<"$pi_b" \
  && ok "two owned drains ⇒ two Drain sub-rows, the second marked fix-now, each with its own usage" || no "drain rows: $(printf '%s\n' "$pi_b" | grep -F Drain)"

echo "== PI6. --per-item: no resolvable transcript ⇒ exit 0, named no_transcripts reason, no number (AC4) =="
pi_c="$(pi_rows_after '| **.supervisor/requirements/c.md** |')"
[ "$PI_RC" -eq 0 ] && ok "exit 0 with an item that has no transcripts" || no "rc=$PI_RC"
grep -q 'per-item: no_transcripts — .supervisor/requirements/c.md' <<<"$PI_ERR" && ok "stderr names no_transcripts for item c" || no "stderr: $PI_ERR"
[ "$(printf '%s\n' "$pi_c" | wc -l | tr -d ' ')" = 1 ] && [ "$(printf '%s\n' "$pi_c" | sed 's/^| \*\*[^|]*\*\* //' | tr -cd '0-9')" = "" ] \
  && grep -qF "| no transcripts |" <<<"$pi_c" \
  && ok "item c prints ONE row with no number in any cell" || no "item c rows: $pi_c"

echo "== PI7. --per-item: a lane root's sessions are attributed to the lane's item (AC3) =="
pi_run "$SUT" --per-item "$PIF/run.md" --root "$PI/p" --root "$PI/l" --projects-dir "$PIP"
[ "$(pi_row '| **[L1] .supervisor/requirements/e.md** |')" = "| **[L1] .supervisor/requirements/e.md** | 10-15 08:00:00 → 09:05:00 | 1h 5m 0s | 50 (main 50) | 5 (main 5) | 1 | 50 | — |" ] \
  && ok "lane item row carries the lane transcript's usage" || no "lane row: $(pi_row '[L1]')"
grep -qF "| **.supervisor/requirements/e.md** |" <<<"$PI_OUT" && no "the lane's item was also listed unattributed under the parent" || ok "the lane's Queue item is reported under its lane only"
grep -qxF "| ↳ Launch Pad | 10-15 08:00:00 → 08:10:00 | 10m 0s | 50 (main 50) | 5 (main 5) | 1 | 50 | — |" <<<"$(pi_rows_after '| **[L1] .supervisor/requirements/e.md** |')" \
  && ok "'launch pad: brief saved' variant matches as the Launch Pad boundary" || no "lane Launch Pad: $(pi_rows_after '[L1]')"
pi_run "$SUT" --per-item "$PIF/run.md" --root "$PI/p" --projects-dir "$PIP"
grep -qF "[L1]" <<<"$PI_OUT" && no "a lane row appeared without its lane root" || ok "without the lane root no lane row is printed"
grep -qF "| not picked |" < <(pi_row '| **.supervisor/requirements/e.md** |') && ok "without the lane root the item reads 'not picked'" || no "e without lane: $(pi_row 'e.md')"

echo "== PI8. --per-item: a never-picked Queue item has a row with no number =="
[ "$(pi_row '| **.supervisor/requirements/d.md** |')" = "| **.supervisor/requirements/d.md** | not picked | not recorded | not picked | not picked | not picked | not picked | not picked |" ] \
  && grep -q 'not_picked — .supervisor/requirements/d.md' <<<"$PI_ERR" && ok "unpicked item d: 'not picked' row + not_picked reason" || no "d row: $(pi_row 'd.md')"

echo "== PI9. --per-item: LOOMWRIGHT_CC_PROJECTS_DIR is the projects dir when no --projects-dir is given =="
PI_OUT="$(LOOMWRIGHT_CC_PROJECTS_DIR="$PIP" bash "$SUT" --per-item "$PIF/run.md" --root "$PI/p" 2>/dev/null)"
grep -qF "| 29510 (main 28210) |" < <(pi_row '| **.supervisor/requirements/a.md** |') && ok "env-resolved projects dir reads the same transcripts" || no "env projects dir: $(pi_row 'a.md')"

echo "== PI10. --per-item: fail SAFE (missing run file; jq unavailable) =="
pi_run "$SUT" --per-item "$PI/nope.md" --root "$PI/p" --projects-dir "$PIP"
[ "$PI_RC" -eq 0 ] && [ -z "$PI_OUT" ] && grep -q 'per-item: run_file_unreadable' <<<"$PI_ERR" && ok "missing run file ⇒ exit 0, named reason, no table" || no "missing run file: rc=$PI_RC out='$PI_OUT' err='$PI_ERR'"
PI_OUT="$(LOOMWRIGHT_JQ_BIN=/nonexistent/jq bash "$SUT" --per-item "$PIF/run.md" --root "$PI/p" --projects-dir "$PIP" 2>"$PI/err")"; PI_RC=$?
[ "$PI_RC" -eq 0 ] && [ -z "$PI_OUT" ] && grep -q 'per-item: jq_unavailable' "$PI/err" && ok "jq unavailable ⇒ exit 0, named reason, never the one-line zero sum" || no "no-jq per-item: rc=$PI_RC out='$PI_OUT'"

echo "== PI12. --per-item: phase-timing.sh absent ⇒ named reason, no-number rows, exit 0 =="
PIN="$(mktemp -d)"; cp "$SUT" "$PIN/read-token-ledger.sh"
pi_run "$PIN/read-token-ledger.sh" --per-item "$PIF/run.md" --root "$PI/p" --projects-dir "$PIP"
[ "$PI_RC" -eq 0 ] && grep -q 'per-item: phase_timing_unavailable — .supervisor/requirements/a.md' <<<"$PI_ERR" \
  && [ "$(pi_row '| **.supervisor/requirements/a.md** |')" = "| **.supervisor/requirements/a.md** | not recorded | not recorded | not recorded | not recorded | not recorded | not recorded | not recorded |" ] \
  && ok "no phase-timing.sh ⇒ phase_timing_unavailable + 'not recorded' row" || no "no phase-timing: rc=$PI_RC row=$(pi_row 'a.md') err=$PI_ERR"
rm -rf "$PIN"

echo "== PI13. --per-item: bare run id resolves under the first root; an item with no session id names that =="
mkdir -p "$PI/p/.supervisor/automate"; cp "$PIF/run.md" "$PI/p/.supervisor/automate/run.md"
pi_run "$SUT" --per-item run --root "$PI/p" --projects-dir "$PIP"
grep -qF "| 29510 (main 28210) |" < <(pi_row '| **.supervisor/requirements/a.md** |') && ok "--per-item <bare run id> reads <root>/.supervisor/automate/<id>.md" || no "bare run id: $(pi_row 'a.md') err=$PI_ERR"
printf '# Automate Run: x\n## Queue\n- [x] q.md\n## Progress\n- 2026-10-15T01:00:00Z picked q.md\n- 2026-10-15T01:10:00Z parked\n' > "$PI/nosess.md"
pi_run "$SUT" --per-item "$PI/nosess.md" --root "$PI/p" --projects-dir "$PIP"
[ "$PI_RC" -eq 0 ] && grep -qF 'no_transcripts — q.md (no session id recorded for the item' <<<"$PI_ERR" \
  && grep -qF '| no transcripts |' < <(pi_row '| **q.md** |') && ok "picked item with no session id ⇒ no_transcripts naming the missing id, no number" || no "no-session item: err=$PI_ERR row=$(pi_row 'q.md')"

echo "== PI14. --per-item: a transcript with no usage record in the item window ⇒ no_usage_in_window, no number =="
# A copy of the fixture projects dir (the tracked fixture keeps c.md transcript-less for PI6)
# plus a transcript for c's Claude Code session holding only a user line.
PIQ="$PI/projects-nousage"; cp -R "$PIP" "$PIQ"
printf '%s\n' '{"type":"user","timestamp":"2026-10-14T11:10:00Z","message":{"role":"user","content":"hi"}}' > "$PIQ/-fixture-proj/cccccccc-0000-4000-8000-000000000001.jsonl"
pi_run "$SUT" --per-item "$PIF/run.md" --root "$PI/p" --projects-dir "$PIQ"
pi_c="$(pi_rows_after '| **.supervisor/requirements/c.md** |')"
[ "$PI_RC" -eq 0 ] && grep -qF 'per-item: no_usage_in_window — .supervisor/requirements/c.md (1 transcript file(s) read' <<<"$PI_ERR" \
  && [ "$(printf '%s\n' "$pi_c" | wc -l | tr -d ' ')" = 1 ] && [ "$(printf '%s\n' "$pi_c" | sed 's/^| \*\*[^|]*\*\* //' | tr -cd '0-9')" = "" ] \
  && grep -qF "| no usage in window |" <<<"$pi_c" \
  && ok "transcript present, zero usage lines ⇒ named reason + ONE no-number row" || no "zero-usage transcript: err=$PI_ERR rows=$pi_c"
# usage only OUTSIDE the item window (after c's park) is still no usage in the window
printf '%s\n' '{"type":"assistant","timestamp":"2026-10-14T12:00:00Z","message":{"id":"msg_c_late","stop_reason":"end_turn","usage":{"input_tokens":9,"output_tokens":9}}}' >> "$PIQ/-fixture-proj/cccccccc-0000-4000-8000-000000000001.jsonl"
pi_run "$SUT" --per-item "$PIF/run.md" --root "$PI/p" --projects-dir "$PIQ"
pi_c="$(pi_rows_after '| **.supervisor/requirements/c.md** |')"
grep -qF 'per-item: no_usage_in_window — .supervisor/requirements/c.md' <<<"$PI_ERR" \
  && [ "$(printf '%s\n' "$pi_c" | sed 's/^| \*\*[^|]*\*\* //' | tr -cd '0-9')" = "" ] \
  && ok "usage only outside pick → park ⇒ no_usage_in_window, no number" || no "out-of-window usage: err=$PI_ERR rows=$pi_c"

echo "== PI15. --per-item: a phase window with no usage record prints 'no usage in window', never 0 =="
pi_run "$SUT" --per-item "$PIF/run.md" --root "$PI/p" --projects-dir "$PIP"
pi_b="$(pi_rows_after '| **.supervisor/requirements/b.md** |')"
grep -qxF "| ↳ ↳ after iter 1 (no iter line) | 10-14 09:40:00 → 10:00:00 | 20m 0s | no usage in window | no usage in window | no usage in window | — | — |" <<<"$pi_b" \
  && ok "empty phase window ⇒ 'no usage in window' (wall kept)" || no "empty phase row: $(printf '%s\n' "$pi_b" | grep -F 'after iter 1')"
grep -qF "| 0 (main 0) |" <<<"$PI_OUT" && no "a 0 (main 0) cell was rendered" || ok "no '0 (main 0)' cell anywhere in the report"

echo "== PI16. --per-item: an inverted phase window (drain ends after the park) is 'not recorded' =="
mkdir -p "$PI/inv/.supervisor/logs" "$PI/inv/proj/x"
printf '{"cc_session_id":"cccccccc-0000-4000-8000-000000000009"}\n' > "$PI/inv/.supervisor/logs/sq.jsonl"
printf '%s\n' '{"type":"assistant","timestamp":"2026-10-15T01:05:00Z","message":{"id":"m1","stop_reason":"end_turn","usage":{"input_tokens":5,"output_tokens":1}}}' > "$PI/inv/proj/x/cccccccc-0000-4000-8000-000000000009.jsonl"
printf '# Automate Run: x\n## Queue\n- [x] q.md\n## Progress\n- 2026-10-15T01:00:00Z picked q.md\n- 2026-10-15T01:10:00Z session_id sq (q.md)\n- 2026-10-15T01:10:00Z ran /autonomous → PR https://github.com/a/b/pull/1\n- 2026-10-15T01:30:00Z owned drain started — /review-pr https://github.com/a/b/pull/1 --until-mergeable\n- 2026-10-15T01:40:00Z drain READY (converged)\n- 2026-10-15T01:20:00Z parked awaiting_merge\n' > "$PI/inv/run.md"
pi_run "$SUT" --per-item "$PI/inv/run.md" --root "$PI/inv" --projects-dir "$PI/inv/proj"
grep -qxF "| ↳ Decide | not recorded | not recorded | not recorded | not recorded | not recorded | not recorded | not recorded |" < <(pi_row '| ↳ Decide |') \
  && ok "Decide with drain end > park ⇒ 'not recorded' (not an empty backwards window of 0s)" || no "inverted Decide: $(pi_row '| ↳ Decide |')"

echo "== PI17. --per-item: a parent item picked by a sibling <run_id>-L<n>.md lane file reads 'picked in lane' =="
mkdir -p "$PI/sib"; cp "$PIF/run.md" "$PI/sib/run.md"; cp "$PIF/lane/run-L1.md" "$PI/sib/run-L1.md"
printf '# Automate Run: run-L2\n## Queue\n- [x] other.md\n## Progress\n- 2026-10-15T07:00:00Z picked other.md\n' > "$PI/sib/run-L2.md"
pi_run "$SUT" --per-item "$PI/sib/run.md" --root "$PI/p" --projects-dir "$PIP"
[ "$(pi_row '| **.supervisor/requirements/e.md** |')" = "| **.supervisor/requirements/e.md** | picked in lane run-L1 | not recorded | see lane run run-L1 | see lane run run-L1 | see lane run run-L1 | see lane run run-L1 | see lane run run-L1 |" ] \
  && grep -qF 'picked_in_lane — .supervisor/requirements/e.md (run-L1)' <<<"$PI_ERR" \
  && ok "lane-picked parent item names its lane run, not 'not picked'" || no "sibling lane: row=$(pi_row 'e.md') err=$PI_ERR"
grep -qF "| not picked |" < <(pi_row '| **.supervisor/requirements/d.md** |') && ok "an item no lane picked still reads 'not picked'" || no "d with sibling lanes: $(pi_row 'd.md')"

echo "== PI18. --per-item: an item parked, then resumed in the same run, counts the resumed work =="
# picked → parked (escalated) → picked again (resume) → ran /autonomous → drain → parked.
# phase-timing's .item.park is the FIRST parked line; the resumed work (02:30, 03:10,
# 03:35) must still land in the item total. The 04:00 message is after the last park.
mkdir -p "$PI/res/.supervisor/logs" "$PI/res/proj/x"
printf '{"cc_session_id":"cccccccc-0000-4000-8000-00000000000a"}\n' > "$PI/res/.supervisor/logs/sr.jsonl"
for m in "m1 2026-10-15T01:05:00Z 10" "m2 2026-10-15T02:30:00Z 100" "m3 2026-10-15T03:10:00Z 1000" "m4 2026-10-15T03:35:00Z 10000" "m5 2026-10-15T04:00:00Z 99999"; do
  read -r m_id m_ts m_in <<< "$m"
  printf '{"type":"assistant","timestamp":"%s","message":{"id":"%s","stop_reason":"end_turn","usage":{"input_tokens":%s,"output_tokens":1}}}\n' "$m_ts" "$m_id" "$m_in"
done > "$PI/res/proj/x/cccccccc-0000-4000-8000-00000000000a.jsonl"
res_prog='- 2026-10-15T01:00:00Z picked q.md\n- 2026-10-15T01:10:00Z parked escalated (Launch Pad failed) — resume to re-run\n- 2026-10-15T02:00:00Z picked q.md (resume)\n- 2026-10-15T03:00:00Z session_id sr (q.md)\n- 2026-10-15T03:00:00Z ran /autonomous → PR https://github.com/a/b/pull/1\n- 2026-10-15T03:05:00Z owned drain started — /review-pr https://github.com/a/b/pull/1 --until-mergeable\n- 2026-10-15T03:30:00Z drain READY (converged)\n'
printf "# Automate Run: x\n## Queue\n- [x] q.md\n## Progress\n${res_prog}- 2026-10-15T03:40:00Z parked awaiting_merge — PR https://github.com/a/b/pull/1\n" > "$PI/res/run.md"
pi_run "$SUT" --per-item "$PI/res/run.md" --root "$PI/res" --projects-dir "$PI/res/proj"
[ "$(pi_row '| **q.md** |')" = "| **q.md** | 10-15 01:00:00 → 03:40:00 (resumed after park — to the later parked line; wall is pick → first park) | 10m 0s | 11110 (main 11110) | 4 (main 4) | 4 | 10000 | — |" ] \
  && ok "resumed item: token window runs to the later parked line (11110 = first attempt + resumed work); wall stays pick → first park" || no "resumed item row: $(pi_row '| **q.md** |')"
grep -qxF "| ↳ Decide | 10-15 03:30:00 → 03:40:00 | 10m 0s | 10000 (main 10000) | 1 (main 1) | 1 | 10000 | — |" < <(pi_row '| ↳ Decide |') \
  && ok "resumed item: Decide runs from the last drain to the later parked line (not inverted)" || no "resumed Decide: $(pi_row '| ↳ Decide |')"
grep -qF 'per-item: work_after_park — q.md (worked after its first parked line 2026-10-15T01:10:00Z; token window runs to 2026-10-15T03:40:00Z)' <<<"$PI_ERR" \
  && ok "stderr names work_after_park" || no "work_after_park reason missing: $PI_ERR"
grep -q '^WORK_AFTER_PARK' <<<"$PI_OUT" && no "the WORK_AFTER_PARK sentinel leaked to stdout" || ok "no sentinel on stdout"
# no later parked line: the window runs to the latest work boundary, named
printf "# Automate Run: x\n## Queue\n- [x] q.md\n## Progress\n${res_prog}" > "$PI/res/run.md"
pi_run "$SUT" --per-item "$PI/res/run.md" --root "$PI/res" --projects-dir "$PI/res/proj"
[ "$(pi_row '| **q.md** |')" = "| **q.md** | 10-15 01:00:00 → 03:30:00 (resumed after park — to drain READY; wall is pick → first park) | 10m 0s | 1110 (main 1110) | 3 (main 3) | 3 | 1000 | — |" ] \
  && grep -qxF "| ↳ Decide | not recorded | not recorded | not recorded | not recorded | not recorded | not recorded | not recorded |" < <(pi_row '| ↳ Decide |') \
  && ok "resumed, no later parked line: window to the last drain end (named), Decide 'not recorded'" || no "resumed no-repark: $(pi_row '| **q.md** |') / $(pi_row '| ↳ Decide |')"

echo "== PI19. invariant: no phase row's context tokens exceed its item row's =="
# pi_phase_le_item <out> <item row marker> — every ↳ row's context number <= the item row's
pi_phase_le_item() {
  printf '%s\n' "$1" | awk -v m="$2" -F' \\| ' '
    function num(c) { if (c ~ /^[0-9]+ \(main/) { sub(/ .*/, "", c); return c + 0 } return -1 }
    index($0, m) { on = 1; it = num($4); next }
    on && /^\| ↳/ { v = num($4); if (it >= 0 && v > it) { print "phase row exceeds item: " $0; bad = 1 } next }
    on { exit }
    END { exit bad }'
}
pi_run "$SUT" --per-item "$PIF/run.md" --root "$PI/p" --root "$PI/l" --projects-dir "$PIP"
pi_inv_out="$PI_OUT"
printf "# Automate Run: x\n## Queue\n- [x] q.md\n## Progress\n${res_prog}- 2026-10-15T03:40:00Z parked awaiting_merge — PR https://github.com/a/b/pull/1\n" > "$PI/res/run.md"
pi_run "$SUT" --per-item "$PI/res/run.md" --root "$PI/res" --projects-dir "$PI/res/proj"
pi_inv_bad=""
for mk in '| **.supervisor/requirements/a.md** |' '| **.supervisor/requirements/b.md** |' '| **[L1] .supervisor/requirements/e.md** |'; do
  pi_phase_le_item "$pi_inv_out" "$mk" >/dev/null || pi_inv_bad="$pi_inv_bad $mk"
done
pi_phase_le_item "$PI_OUT" '| **q.md** |' >/dev/null || pi_inv_bad="$pi_inv_bad q.md(resumed)"
[ -z "$pi_inv_bad" ] && ok "every phase row <= its item row (a, b, lane e, resumed q)" || no "phase row exceeds item row:$pi_inv_bad"
# control: the helper does fire on a phase row larger than its item row
pi_phase_le_item "$(printf '%s\n' '| **z** | w | 1m 0s | 5 (main 5) | 1 (main 1) | 1 | 5 | — |' '| ↳ Drain 1 | w | 1m 0s | 9 (main 9) | 1 (main 1) | 1 | 9 | — |')" '| **z** |' >/dev/null \
  && no "invariant control: helper missed a phase row larger than its item" || ok "invariant control: helper flags a phase row larger than its item"

echo "== PI18b. --per-item: ANY later item event after the first park extends the window (no silent under-count) =="
# Each run has a `ran /autonomous` at 01:08, parks at 01:10 and again at 03:50 with ONE
# later item event between the parks and no other work line; usage at 01:05/02:30/03:10/03:35 (11110) is all inside the item.
# Before the fix a resume re-pick / drain start with no end / lone session_id line left
# the window at the FIRST park (10) with an empty stderr.
res_cc='- 2026-10-15T00:59:00Z run created (session cccccccc-0000-4000-8000-00000000000a)\n'
res_want="| **q.md** | 10-15 01:00:00 → 03:50:00 (resumed after park — to the later parked line; wall is pick → first park) | 10m 0s | 11110 (main 11110) | 4 (main 4) | 4 | 10000 | — |"
for res_case in \
  "resume pick|- 2026-10-15T02:00:00Z picked q.md (resume)" \
  "drain start, no end|- 2026-10-15T02:00:00Z owned drain started (fix-now re-drain) — /review-pr https://github.com/a/b/pull/1 --until-mergeable @ abc" \
  "session_id line|- 2026-10-15T02:00:00Z session_id sr (q.md)" \
  "second ran /autonomous|- 2026-10-15T02:00:00Z ran /autonomous → PR https://github.com/a/b/pull/2"; do
  res_name="${res_case%%|*}"; res_line="${res_case#*|}"
  printf "# Automate Run: x\n## Queue\n- [x] q.md\n## Progress\n${res_cc}- 2026-10-15T01:00:00Z picked q.md\n- 2026-10-15T01:08:00Z ran /autonomous → PR https://github.com/a/b/pull/1\n- 2026-10-15T01:10:00Z parked escalated — resume to re-run\n%s\n- 2026-10-15T03:50:00Z parked awaiting_merge\n" "$res_line" > "$PI/res/run.md"
  pi_run "$SUT" --per-item "$PI/res/run.md" --root "$PI/res" --projects-dir "$PI/res/proj"
  [ "$(pi_row '| **q.md** |')" = "$res_want" ] \
    && grep -qF 'per-item: work_after_park — q.md (worked after its first parked line 2026-10-15T01:10:00Z; token window runs to 2026-10-15T03:50:00Z)' <<<"$PI_ERR" \
    && pi_phase_le_item "$PI_OUT" '| **q.md** |' >/dev/null \
    && ok "$res_name after the first park ⇒ window to the later parked line (11110) + work_after_park; phase <= item" \
    || no "$res_name after park: row=$(pi_row '| **q.md** |') err=$PI_ERR"
done

echo "== FP. fresh phases (automate-speed/09): the driver's three phase session_id lines — --run-id sums one ledger per phase, --per-item resolves all three ids =="
# The run file is WRITTEN BY automate-next-step.sh (its plan-result / run-record / drain-result steps, each run
# through the driver's FROM/UNTIL test seams), so a change to the driver's `session_id <sid> (<item>)
# phase=<phase>` shape reaches this leg; the reader itself is unchanged by automate-speed/09.
DRV="$HERE/automate-next-step.sh"
fp_leg() { # <driver> — 0 when --run-id sums the three phase ledgers and --per-item tries all three ids
  local drv="$1" d rf run=automate-2026-10-19-000000 out err lp
  d="$(fresh_root)"; rf="$d/.supervisor/automate/$run.md"; mkdir -p "$d/.supervisor/jobs/pending" "$d/projects"
  printf '%s\n' '# Automate Run: fp' '## Status: running' '## Run Config' '- mode: safe | limit: 5 | trust_unprotected: false' \
    '## Queue' '- [ ] fp.md' '## Current' '- item: fp.md | status: running | pr: https://github.com/o/r/pull/9 | branch: feature/fp' \
    '- pause_reason: null' '## Progress' '- 2026-10-19T10:00:00Z picked fp.md' > "$rf"
  printf '# Brief\n' > "$d/.supervisor/jobs/pending/fp.md"
  # the Supervisor phase spawn's freshness floor (the driver's run_spawn_epoch), taken BEFORE the phase
  # "rewrites" state.md — the driver trusts state.md's session_id only when it is at/after that floor
  local ep; ep="$(date +%s)"
  printf -- '- session_id: fp-sup-2\n' > "$d/.supervisor/state.md"
  lp="$(printf 'LAUNCH_PAD_RESULT:\n  schema_version: 1\n  status: saved\n  saved_brief_path: .supervisor/jobs/pending/fp.md\n  summary: PASS\n')"
  fp_step() { # <step> <sidecar json> <report json>
    printf '%s\n' "$2" > "$d/.supervisor/automate/$run.next-step.json"
    ( cd "$d" && NEXT_STEP_FROM="$1" NEXT_STEP_UNTIL="$1" bash "$drv" "$rf" --result "$3" ) >/dev/null 2>&1
  }
  fp_step plan-result '{}' "$(jq -cn --arg t "$lp" '{launch_pad_result: $t, session_id: "fp-lp-1"}')" || { FP_MSG="plan-result step failed"; return 1; }
  fp_step run-record "{\"run_fresh\":\"true\",\"run_spawn_epoch\":\"$ep\"}" '{"status_reason":"failed","no_pr_why":"fp","session_id":"cc-fp-9"}' || { FP_MSG="run-record step failed"; return 1; }
  fp_step drain-result '{"drain_fresh":"true","drain_kind":"first","item":"fp.md","pr":"https://github.com/o/r/pull/9"}' \
    "$(jq -cn '{review_heal_result: "REVIEW_HEAL_RESULT:\n  decision: READY\n  termination_reason: converged\n  rounds: 1\n  fix_cycles: 0\n", session_id: "fp-dr-3"}')" \
    || { FP_MSG="drain-result step failed"; return 1; }
  [ "$(grep -cE '^- [0-9TZ:-]+ session_id fp-(lp-1|sup-2|dr-3) \(fp\.md\) phase=(launch-pad|supervisor|drain)$' "$rf")" = 3 ] \
    || FP_MSG="the driver wrote no three phase lines: $(grep 'session_id' "$rf" | tr '\n' '|')"
  printf '{"event":"token_ledger","input_tokens":%s,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}\n' 100 > "$d/.supervisor/logs/fp-lp-1.jsonl"
  printf '{"event":"token_ledger","input_tokens":%s,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}\n' 200 > "$d/.supervisor/logs/fp-sup-2.jsonl"
  printf '{"event":"token_ledger","input_tokens":%s,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}\n' 400 > "$d/.supervisor/logs/fp-dr-3.jsonl"
  out="$(bash "$SUT" --run-id "$run" --root "$d" 2>/dev/null)"
  [ "$out" = "INPUT=700 OUTPUT=0 CACHE_READ=0 CACHE_CREATE=0 TOTAL=700 EVENTS=3" ] || { FP_MSG="${FP_MSG:+$FP_MSG; }--run-id: $out"; }
  # the ids --per-item resolved for the item (its no_transcripts note names them), one exact word each
  err="$(bash "$SUT" --per-item "$rf" --root "$d" --projects-dir "$d/projects" 2>&1 >/dev/null \
    | sed -n 's/.*no_transcripts — fp\.md (session ids tried: \([^;]*\);.*/\1/p' | tr ' ' '\n')"
  for lp in fp-lp-1 fp-sup-2 fp-dr-3; do
    grep -qxF -- "$lp" <<<"$err" || FP_MSG="${FP_MSG:+$FP_MSG; }--per-item did not resolve $lp (tried: $(tr '\n' ' ' <<<"$err"))"
  done
  rm -rf "$d"
  [ -z "${FP_MSG:-}" ]
}
FP_MSG=""
if fp_leg "$DRV"; then ok "FP: the driver's three phase lines (launch-pad / supervisor / drain) — --run-id sums one fake ledger per phase (700), --per-item tries all three ids"
else no "FP: $FP_MSG"; fi
# mutation control: a driver copy writing the phase suffix BEFORE the item (`session_id <sid> phase=<p> (<item>)`)
# ⇒ pi_cc_ids no longer finds `<item>)` after ` (` and --per-item misses the phase ids
FPM="$(mktemp -d)"
for e in "$HERE"/*; do [ "$e" = "$DRV" ] || ln -s "$e" "$FPM/$(basename "$e")"; done
sed -E 's/session_id \$sid \(\$ITEM\) phase=([a-z-]+)"/session_id $sid phase=\1 ($ITEM)"/' "$DRV" > "$FPM/automate-next-step.sh"
if [ "$(grep -c 'phase=[a-z-]* (\$ITEM)"' "$FPM/automate-next-step.sh")" = 3 ] && bash -n "$FPM/automate-next-step.sh"; then
  FP_MSG=""
  if fp_leg "$FPM/automate-next-step.sh"; then no "FP mutation control: the suffix-before-item mutant stayed green"
  else ok "FP mutation control: session_id <sid> phase=<p> (<item>) ⇒ the leg goes red ($FP_MSG)"; fi
else no "FP mutation control: mutant not built"; fi
rm -rf "$FPM"

echo "== PI20. read-token-ledger.sh parses under /bin/bash (stock macOS bash 3.2) =="
if [ -x /bin/bash ]; then
  /bin/bash -n "$SUT" 2>/dev/null && ok "/bin/bash -n read-token-ledger.sh" || no "read-token-ledger.sh does not parse under /bin/bash: $(/bin/bash -n "$SUT" 2>&1 | head -2)"
else
  ok "/bin/bash absent — parse check skipped"
fi

echo "== PI21. a value-taking flag given last (no value) ⇒ usage, non-zero exit — never a hang =="
# Before the shared need_value guard, a lone trailing --session/--run-id/--root ran a bare
# `shift 2` that failed without shifting, and the parse loop re-read the same flag forever.
# perl's alarm (no `timeout` on macOS) turns a regression back into that hang into rc 142.
if command -v perl >/dev/null 2>&1; then
  for tf in --session --run-id --per-item --projects-dir --root; do
    for pre in "" "--session sa"; do
      # shellcheck disable=SC2086
      tf_err="$(perl -e 'alarm 10; exec @ARGV' bash "$SUT" $pre "$tf" 2>&1 >/dev/null)"; tf_rc=$?
      case "$tf_err" in *"usage: read-token-ledger.sh"*) tf_use=1 ;; *) tf_use=0 ;; esac
      [ "$tf_rc" -eq 1 ] && [ "$tf_use" -eq 1 ] && ok "trailing $tf${pre:+ after '$pre'} ⇒ usage, exit 1" \
        || no "trailing $tf${pre:+ after '$pre'}: rc=$tf_rc err='$tf_err'"
    done
  done
else
  ok "perl absent — trailing-flag hang check skipped"
fi

echo "== PI22. --per-item: a fresh Supervisor phase (no FINALIZE:/iter Progress lines of its own) takes Build + iterations from the hook rows =="
# run-fresh.md: the Supervisor ran as its own session (phase=supervisor), so its boundaries
# exist only in sf.jsonl (pr_created + two code-reviewer spans); the one FINALIZE: line is
# hand-written at the WRONG time (10:30), so a reader preferring it would end Build early.
pi_run "$SUT" --per-item "$PIF/run-fresh.md" --root "$PI/p" --projects-dir "$PIP"
pi_f="$(pi_rows_after '| **.supervisor/requirements/f.md** |')"
grep -qxF "| ↳ Build | 10-20 10:10:00 → 10:40:00 | 30m 0s | 200 (main 200) | 2 (main 2) | 1 | 200 | — |" <<<"$pi_f" \
  && ok "Build ends at the hook-written pr_created (10:40), not the hand-written FINALIZE: (10:30)" || no "fresh Build row: $(printf '%s\n' "$pi_f" | grep -F '↳ Build')"
grep -qxF "| ↳ Phase 4.5 | 10-20 10:40:00 → 11:00:00 | 20m 0s | 1200 (main 1200) | 12 (main 12) | 3 | 500 | — |" <<<"$pi_f" \
  && grep -qxF "| ↳ ↳ iter 1 | 10-20 10:40:00 → 10:50:00 | 10m 0s | 300 (main 300) | 3 (main 3) | 1 | 300 | — |" <<<"$pi_f" \
  && grep -qxF "| ↳ ↳ iter 2 | 10-20 10:50:00 → 10:55:00 | 5m 0s | 400 (main 400) | 4 (main 4) | 1 | 400 | — |" <<<"$pi_f" \
  && grep -qxF "| ↳ ↳ after iter 2 review (last fix + wrap-up) | 10-20 10:55:00 → 11:00:00 | 5m 0s | 500 (main 500) | 5 (main 5) | 1 | 500 | — |" <<<"$pi_f" \
  && ok "one iteration per code-reviewer span: iter n runs to the next reviewer's start, the last to its reviewer's end, then the wrap-up row" \
  || no "fresh iter rows: $(printf '%s\n' "$pi_f" | grep -E 'Phase 4.5|iter')"
# fallback: the same run with no Supervisor session log ⇒ the Progress line is all there is
PIN="$(mktemp -d)"; mkdir -p "$PIN/.supervisor/logs"; cp "$PIF/session-logs/sf.owner" "$PIN/.supervisor/logs/"
pi_run "$SUT" --per-item "$PIF/run-fresh.md" --root "$PIN" --projects-dir "$PIP"
grep -qxF "| ↳ Build | 10-20 10:10:00 → 10:30:00 | 20m 0s | 200 (main 200) | 2 (main 2) | 1 | 200 | — |" < <(pi_rows_after '| **.supervisor/requirements/f.md** |') \
  && ok "no session-log rows ⇒ falls back to the FINALIZE: Progress line (older inline runs keep working)" \
  || no "fallback Build row: $(pi_rows_after '| **.supervisor/requirements/f.md** |' | grep -F '↳ Build')"
rm -rf "$PIN"

echo "== PI11. existing modes unchanged by the per-item flags (AC5) =="
mr_out="$(bash "$SUT" --session sa --root "$PI/p" --projects-dir "$PIP")"
[ "$mr_out" = "INPUT=0 OUTPUT=0 CACHE_READ=0 CACHE_CREATE=0 TOTAL=0 EVENTS=0" ] && ok "--session one-line output is the same shape (no token_ledger lines ⇒ zero sums, readable log)" || no "--session with --projects-dir: $mr_out"
rm -rf "$PI"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
