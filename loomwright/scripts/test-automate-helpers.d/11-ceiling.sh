# ---------------------------------------------------------------------------
# I. ceiling-check — PICK-time token ceiling (red-team-hardening/06)
# ---------------------------------------------------------------------------

ck_root() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/.supervisor/logs" "$d/.supervisor/automate"
  printf '%s' "$d"
}

ck_runfile() {
  # ck_runfile <root> <session_id> -> writes a minimal run file naming <session_id>,
  # returns its path on stdout.
  local d="$1" sid="$2" f="$1/.supervisor/automate/run-ck.md"
  cat > "$f" <<EOF
# Automate Run: ck
## Progress
- ts picked item1
- ts session_id $sid (item1)
EOF
  printf '%s' "$f"
}

echo "== I1. ceiling-check: under max -> OK total=<n> max=<n> =="
R="$(ck_root)"
cat > "$R/.supervisor/logs/ckA.jsonl" <<'EOF'
{"event":"token_ledger","session_id":"ckA","input_tokens":100,"output_tokens":100,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}
EOF
RF="$(ck_runfile "$R" ckA)"
OUT="$(bash "$H" ceiling-check "$RF" 1000 --root "$R" 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && grep -qE '^OK total=200 max=1000$' < <(printf '%s' "$OUT"); then
  ok "I1 under-max: $OUT"
else
  no "I1 under-max wrong: rc=$RC out='$OUT'"
fi
rm -rf "$R"

echo "== I2. ceiling-check: over max -> PARK: token_ceiling total=<n> max=<n> =="
R="$(ck_root)"
cat > "$R/.supervisor/logs/ckB.jsonl" <<'EOF'
{"event":"token_ledger","session_id":"ckB","input_tokens":700,"output_tokens":700,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}
EOF
RF="$(ck_runfile "$R" ckB)"
OUT="$(bash "$H" ceiling-check "$RF" 1000 --root "$R" 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && grep -qE '^PARK: token_ceiling total=1400 max=1000$' < <(printf '%s' "$OUT"); then
  ok "I2 over-max parks (rc still 0, PARK is a normal outcome like gate-eval): $OUT"
else
  no "I2 over-max wrong: rc=$RC out='$OUT'"
fi
rm -rf "$R"

echo "== I3. ceiling-check: exactly at max is NOT a breach (only exceeding parks) =="
R="$(ck_root)"
cat > "$R/.supervisor/logs/ckC.jsonl" <<'EOF'
{"event":"token_ledger","session_id":"ckC","input_tokens":500,"output_tokens":500,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}
EOF
RF="$(ck_runfile "$R" ckC)"
OUT="$(bash "$H" ceiling-check "$RF" 1000 --root "$R" 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && grep -qE '^OK total=1000 max=1000$' < <(printf '%s' "$OUT"); then
  ok "I3 exactly-at-max is OK, not a breach: $OUT"
else
  no "I3 exactly-at-max wrong: rc=$RC out='$OUT'"
fi
rm -rf "$R"

echo "== I4. ceiling-check: LEDGER_UNREADABLE=1 reader answer PARKs (fail CLOSED) =="
R="$(ck_root)"
# No session log file at all for the named session -> reader returns LEDGER_UNREADABLE=1.
RF="$(ck_runfile "$R" ckMissing)"
OUT="$(bash "$H" ceiling-check "$RF" 1000 --root "$R" 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && grep -qE '^PARK: ledger_unreadable$' < <(printf '%s' "$OUT"); then
  ok "I4 unreadable ledger fails CLOSED: $OUT"
else
  no "I4 unreadable ledger wrong: rc=$RC out='$OUT'"
fi
rm -rf "$R"

echo "== I5. ceiling-check: missing run file -> die (non-zero, never a silent OK) =="
R="$(ck_root)"
OUT="$(bash "$H" ceiling-check "$R/.supervisor/automate/nope.md" 1000 --root "$R" 2>&1)"; RC=$?
if [ "$RC" -ne 0 ]; then
  ok "I5 missing run file dies: rc=$RC"
else
  no "I5 missing run file should not succeed: out='$OUT'"
fi
rm -rf "$R"

echo "== I6. ceiling-check: non-integer max_tokens -> die =="
R="$(ck_root)"
RF="$(ck_runfile "$R" ckD)"
OUT="$(bash "$H" ceiling-check "$RF" notanumber --root "$R" 2>&1)"; RC=$?
if [ "$RC" -ne 0 ]; then
  ok "I6 non-integer max_tokens dies: rc=$RC"
else
  no "I6 non-integer max_tokens should not succeed: out='$OUT'"
fi
rm -rf "$R"

echo "== I7. MUTATION CONTROL (AC-mandated): a ledger reader that always reports 0 real tokens makes the breach-parks fixture wrongly print OK =="
MUTDIR="$(mktemp -d)"
cp "$HERE/read-token-ledger.sh" "$MUTDIR/read-token-ledger.sh"
cp "$H" "$MUTDIR/automate-helpers.sh"
sed -i.bak 's/def numf(x): if (x|type)=="number" then x else 0 end;/def numf(x): 0;/' "$MUTDIR/read-token-ledger.sh"
if bash -n "$MUTDIR/read-token-ledger.sh" 2>/dev/null && ! diff -q "$MUTDIR/read-token-ledger.sh" "$HERE/read-token-ledger.sh" >/dev/null 2>&1; then
  R="$(ck_root)"
  cat > "$R/.supervisor/logs/ckE.jsonl" <<'EOF'
{"event":"token_ledger","session_id":"ckE","input_tokens":900,"output_tokens":900,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}
EOF
  RF="$(ck_runfile "$R" ckE)"
  # No real-reader baseline runs inside THIS case: $MUTDIR/automate-helpers.sh
  # is a plain copy of the real script, but it is co-located in $MUTDIR with
  # the mutant read-token-ledger.sh, so `$(dirname "$0")/read-token-ledger.sh`
  # resolves to the MUTANT reader, not the real one, for this very invocation
  # -- BASE_OUT below is already the mutant's output. The expected real-reader
  # outcome for this fixture (genuinely over the 1000 ceiling -> PARK) is
  # established separately by case I2's pattern, not re-run here. The
  # assertion in THIS case only checks that the mutant instead prints OK.
  BASE_OUT="$(bash "$MUTDIR/automate-helpers.sh" ceiling-check "$RF" 1000 --root "$R" 2>&1)"
  # Mutant output (same co-located resolution as above, restated for clarity
  # at the point of use).
  MUT_OUT="$BASE_OUT"
  rm -rf "$R"
  if grep -q '^OK' < <(printf '%s' "$MUT_OUT"); then
    ok "I7 mutation control: always-0 numf() flips a genuinely-over-ceiling fixture to OK -- proves ceiling-check's breach-parks behavior is load-bearing, not vacuous (mutant='$MUT_OUT')"
  else
    no "I7 mutation control REFUTED: mutant still parked -- ceiling-check may not actually depend on the reader's real-usage sums (mutant='$MUT_OUT')"
  fi
else
  no "I7 mutation control: could not build the mutant (sed did not apply or bash -n failed) -- control inconclusive"
fi
rm -rf "$MUTDIR"

