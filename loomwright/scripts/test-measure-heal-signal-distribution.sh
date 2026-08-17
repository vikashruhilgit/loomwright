#!/usr/bin/env bash
# test-measure-heal-signal-distribution.sh — self-tests for `measure-heal-signal.sh
# --distribution` (the per-class findings/misses instrument behind docs/RULES_BASELINE.md).
# STATIC ONLY: no network, no Docker, no TTY — runs on the plugin's Ubuntu CI like every other
# test-*.sh (auto-registered by ci.yml's test-*.sh glob). Exit 0 = all pass, 1 = any failure.
#
# Sibling to test-measure-heal-signal.sh, which covers the confusion matrix; this file covers
# ONLY the second measurement and the wrapper's exit contract around it. Same convention:
# pass/fail counters, ok()/no() helpers, `mktemp -d` fixtures, a "RESULT: N passed, M failed"
# tail. The real repo's `.supervisor/` is never written to — every run is pointed at a fixture.
#
# Covers:
#   (a) ARITHMETIC — per-class findings and misses are counted over RAW records (no per-PR
#       dedup, unlike the matrix path), a miss is `self_heal_miss: true` and nothing else, and
#       the three shares (findings share, misses share, within-class miss-rate) are correct on a
#       fixture whose expected values are computed by hand in the test, not by the engine.
#   (b) NO SIDE EFFECTS — --distribution creates no --out dir, writes no artifact, appends no
#       trend line, and leaves the measured repo byte-identical.
#   (c) THE EXIT CONTRACT, UNCHANGED — the whole point of AC11 is that this mode does not
#       tighten or loosen what the wrapper already did:
#         * missing python3            -> skip line, exit 0
#         * missing engine             -> skip line, exit 0
#         * unknown arg                -> usage line on stderr, exit 0
#         * engine's own exit code     -> propagated verbatim (asserted with a stub engine)
#       Each is asserted for BOTH a --distribution invocation and a plain one, because a
#       contract that holds on only one path is not the contract.
#   (d) EMPTY / MALFORMED input is fail-safe — an absent ledger, an unparseable line, and a
#       record with no `categories` all produce a report and exit 0 rather than a traceback.
#
# MHS_WRAPPER exists ONLY for mutation control (point it at a deliberately-broken copy and
# confirm this suite goes RED). It DEFAULTS to the real wrapper, so it can never disarm an
# assertion here — the default is the thing under test, never a fixture stand-in.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAP="${MHS_WRAPPER:-$HERE/measure-heal-signal.sh}"
ENGINE="$HERE/measure-heal-signal.py"
PY="$(command -v python3 || command -v python || true)"
BASH_BIN="$(command -v bash || echo /bin/bash)"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

FIXTURES=()
mkfix() { local d; d="$(mktemp -d)"; FIXTURES+=("$d"); printf '%s' "$d"; }
cleanup() { local d; for d in "${FIXTURES[@]:-}"; do [ -n "$d" ] && rm -rf "$d" 2>/dev/null; done; }
trap cleanup EXIT

if [ -z "$PY" ]; then
  echo "test-measure-heal-signal-distribution: python3 absent — SKIPPING (the wrapper's own"
  echo "  missing-python3 path is exercised by (c) below, which does not need an interpreter)."
fi

# Capture stdout+stderr and the REAL exit status. Deliberately NOT `local out="$(...)"`:
# that form makes $? the status of `local`, which is always 0, and silently vacuums the
# exit-code assertions this file exists to make.
OUT=""; RC=0
run() { OUT="$("$@" 2>&1)"; RC=$?; }

# grep against a FILE, never `printf ... | grep -q`: under `set -o pipefail` a producer piped
# into an early-exiting `grep -q` can report 141 (SIGPIPE) even on a match.
GREPBUF=""
has() {  # has <pattern>  — regex match against the last captured output
  [ -n "$GREPBUF" ] || GREPBUF="$(mkfix)/out.txt"
  printf '%s\n' "$OUT" > "$GREPBUF"
  grep -qE "$1" "$GREPBUF"
}

# ---- fixture: a repo whose ledger has hand-computable class counts ----------------------
# 4 records / 3 distinct PRs (records 1 and 2 are re-gathers of the SAME PR, so a per-PR dedup
# would drop record 2 and change the answer — that is the point of the case).
#   findings: convention_mismatch 4, quality_gap 2, execution_bug 1  -> total 7
#   misses:   convention_mismatch 2, quality_gap 1, execution_bug 0  -> total 3
# `self_heal_miss` is absent on one finding and null on another: neither may count as a miss.
mkledger() {
  local root="$1"
  mkdir -p "$root/.supervisor/postmortem"
  cat > "$root/.supervisor/postmortem/results.jsonl" <<'EOF'
{"repo":"o/r","number":1,"agent_generated_guess":true,"categories":[{"class":"convention_mismatch","self_heal_miss":true},{"class":"quality_gap","self_heal_miss":false}]}
{"repo":"o/r","number":1,"agent_generated_guess":true,"categories":[{"class":"convention_mismatch","self_heal_miss":true},{"class":"execution_bug"}]}
{"repo":"o/r","number":2,"agent_generated_guess":true,"categories":[{"class":"convention_mismatch","self_heal_miss":null},{"class":"quality_gap","self_heal_miss":true}]}
{"repo":"o/other","number":3,"agent_generated_guess":false,"categories":[{"class":"convention_mismatch","self_heal_miss":false}]}
EOF
}

echo "== (a) arithmetic: per-class counts and the three shares =="
if [ -n "$PY" ]; then
  A="$(mkfix)"; mkledger "$A"
  run bash "$WRAP" --repo "$A" --distribution
  [ "$RC" -eq 0 ] && ok "(a) --distribution exits 0" || no "(a) --distribution exited $RC"
  has 'records: 4[[:space:]]+findings: 7[[:space:]]+misses: 3' \
    && ok "(a) totals counted over RAW records (4 records, 7 findings, 3 misses)" \
    || no "(a) wrong totals — expected 4 records / 7 findings / 3 misses; got: $OUT"
  # convention_mismatch: 4/7 findings = 57%, 2/3 misses = 67%, miss-rate 2/4 = 50%
  has '^ +convention_mismatch +4 +57% +2 +67% +50%$' \
    && ok "(a) convention_mismatch row: 4 / 57% / 2 / 67% / 50%" \
    || no "(a) convention_mismatch row wrong; got: $OUT"
  # quality_gap: 2/7 = 29%, 1/3 = 33%, 1/2 = 50%
  has '^ +quality_gap +2 +29% +1 +33% +50%$' \
    && ok "(a) quality_gap row: 2 / 29% / 1 / 33% / 50%" \
    || no "(a) quality_gap row wrong; got: $OUT"
  # execution_bug: a finding with NO self_heal_miss key at all -> 0 misses, 0% miss-rate.
  has '^ +execution_bug +1 +14% +0 +0% +0%$' \
    && ok "(a) an absent self_heal_miss is not a miss (execution_bug 1 / 0)" \
    || no "(a) absent self_heal_miss mis-counted; got: $OUT"
  # a null self_heal_miss is likewise not a miss: convention_mismatch would be 3 if it were.
  has 'convention_mismatch +4 +57% +2 ' \
    && ok "(a) a null self_heal_miss is not a miss" \
    || no "(a) null self_heal_miss mis-counted"
  # classes are ordered by findings desc, so the largest class reads first. Compared as a
  # SEQUENCE (grep is line-oriented and cannot express "this row before that one").
  order="$(printf '%s\n' "$OUT" \
           | awk '/^ +[a-z_]+ +[0-9]+ +[0-9]+% +[0-9]+ +[0-9]+% +[0-9]+%$/ {print $1}' \
           | tr '\n' ' ')"
  [ "$order" = "convention_mismatch quality_gap execution_bug " ] \
    && ok "(a) classes ordered by findings, descending" \
    || no "(a) class ordering is not findings-descending (got: '$order')"
  # label quality is stated in the output, not left to the reader.
  has 'label quality: 3 of 4 records \(75%\) carry agent_generated_guess: true' \
    && ok "(a) agent_generated_guess share is reported (3 of 4, 75%)" \
    || no "(a) agent_generated_guess share missing/wrong; got: $OUT"
  has 'no control arm' \
    && ok "(a) the output states its own limits (no control arm)" \
    || no "(a) the output does not state its limits"
  # every ledger .repo is NAMED rather than silently filtered (decision (a) of the brief).
  has 'ledger \.repo: o/other' \
    && ok "(a) every ledger .repo is named, none silently dropped" \
    || no "(a) a ledger .repo was not named in the output"
fi

echo "== (b) no side effects: --distribution writes nothing =="
if [ -n "$PY" ]; then
  B="$(mkfix)"; mkledger "$B"
  before="$(find "$B" -type f | sort | while IFS= read -r f; do
              printf '%s %s\n' "$f" "$(wc -c < "$f" | tr -d ' ')"; done)"
  OUTDIR="$(mkfix)/never-created"
  run bash "$WRAP" --repo "$B" --out "$OUTDIR" --distribution
  [ "$RC" -eq 0 ] && ok "(b) exits 0 with an --out that does not exist" || no "(b) exited $RC"
  [ ! -e "$OUTDIR" ] \
    && ok "(b) the --out dir was not created" \
    || no "(b) --distribution created the --out dir"
  after="$(find "$B" -type f | sort | while IFS= read -r f; do
             printf '%s %s\n' "$f" "$(wc -c < "$f" | tr -d ' ')"; done)"
  [ "$before" = "$after" ] \
    && ok "(b) the measured repo is unchanged (same files, same sizes)" \
    || no "(b) the measured repo changed under --distribution"
  [ ! -e "$B/.supervisor/heal-signal" ] \
    && ok "(b) no default heal-signal dir appeared in the measured repo" \
    || no "(b) a heal-signal dir was created in the measured repo"
fi

echo "== (c) the wrapper exit contract — unchanged by this mode =="
# Every case is asserted twice: once with --distribution, once without. A contract that holds
# on only the new path is not the contract AC11 says is preserved.
for extra in "--distribution" ""; do
  lab="${extra:-plain}"

  # c1 — missing python3: skip line, exit 0. PATH is emptied of any interpreter, which is why
  # this case runs even when python3 is absent from the host. $BASH_BIN is resolved ABSOLUTELY
  # up front: with an empty PATH, a bare `bash` is itself not found (127), which would fake a
  # failure of the assertion rather than test it.
  C1="$(mkfix)"; mkledger "$C1"
  # shellcheck disable=SC2086
  OUT="$(PATH="$(mkfix)" "$BASH_BIN" "$WRAP" --repo "$C1" $extra 2>&1)"; RC=$?
  [ "$RC" -eq 0 ] && ok "(c/$lab) missing python3 exits 0" \
                  || no "(c/$lab) missing python3 exited $RC (expected 0)"
  has 'python3 required — skipping' \
    && ok "(c/$lab) missing python3 prints the skip line" \
    || no "(c/$lab) missing python3 printed no skip line; got: $OUT"

  # c2 — missing engine: skip line, exit 0. A copy of the wrapper in a dir with no sibling .py.
  C2="$(mkfix)"; cp "$WRAP" "$C2/measure-heal-signal.sh"
  # shellcheck disable=SC2086
  OUT="$(bash "$C2/measure-heal-signal.sh" --repo "$C2" $extra 2>&1)"; RC=$?
  [ "$RC" -eq 0 ] && ok "(c/$lab) missing engine exits 0" \
                  || no "(c/$lab) missing engine exited $RC (expected 0)"
  has 'engine not found' \
    && ok "(c/$lab) missing engine prints the skip line" \
    || no "(c/$lab) missing engine printed no skip line; got: $OUT"

  # c3 — unknown arg: usage line, exit 0 (a measurement tool must never break its caller).
  # shellcheck disable=SC2086
  OUT="$(bash "$WRAP" $extra --no-such-flag 2>&1)"; RC=$?
  [ "$RC" -eq 0 ] && ok "(c/$lab) unknown arg exits 0" \
                  || no "(c/$lab) unknown arg exited $RC (expected 0)"
  has "unknown arg '--no-such-flag'" \
    && ok "(c/$lab) unknown arg names the offending flag" \
    || no "(c/$lab) unknown arg printed no usage line; got: $OUT"

  # c4 — the engine's own exit code is PROPAGATED, not swallowed. Stub engine exits 7 and,
  # for the distribution case, proves the flag actually reaches the engine argv.
  if [ -n "$PY" ]; then
    C4="$(mkfix)"; cp "$WRAP" "$C4/measure-heal-signal.sh"
    cat > "$C4/measure-heal-signal.py" <<'STUB'
import sys
print("STUB ENGINE argv: " + " ".join(sys.argv[1:]))
sys.exit(7)
STUB
    # shellcheck disable=SC2086
    OUT="$(bash "$C4/measure-heal-signal.sh" --repo "$C4" $extra 2>&1)"; RC=$?
    [ "$RC" -eq 7 ] \
      && ok "(c/$lab) the engine's exit code 7 is propagated verbatim" \
      || no "(c/$lab) engine exit 7 came back as $RC"
    if [ -n "$extra" ]; then
      has 'STUB ENGINE argv:.*--distribution' \
        && ok "(c/$lab) --distribution is forwarded to the engine argv" \
        || no "(c/$lab) --distribution never reached the engine; got: $OUT"
    else
      has 'STUB ENGINE argv:' && ! has 'STUB ENGINE argv:.*--distribution' \
        && ok "(c/$lab) a plain run forwards no --distribution" \
        || no "(c/$lab) a plain run leaked --distribution into the engine argv"
    fi
  fi
done

echo "== (d) fail-safe on empty / malformed input =="
if [ -n "$PY" ]; then
  D1="$(mkfix)"   # no ledger at all
  run bash "$WRAP" --repo "$D1" --distribution
  [ "$RC" -eq 0 ] && ok "(d) a repo with no ledger exits 0" || no "(d) no-ledger exited $RC"
  has 'records: 0' && ok "(d) no-ledger reports zero records" || no "(d) no-ledger miscounted"
  has 'nothing to distribute' \
    && ok "(d) the empty case is named as normal, not as an error" \
    || no "(d) the empty case is not explained"

  D2="$(mkfix)"; mkdir -p "$D2/.supervisor/postmortem"
  {
    printf '%s\n' '{ this is not json'
    printf '%s\n' ''
    printf '%s\n' '{"repo":"o/r","number":9,"agent_generated_guess":true}'
    printf '%s\n' '{"repo":"o/r","number":10,"categories":[{"class":"plan_gap","self_heal_miss":true}]}'
  } > "$D2/.supervisor/postmortem/results.jsonl"
  run bash "$WRAP" --repo "$D2" --distribution
  [ "$RC" -eq 0 ] && ok "(d) an unparseable line does not crash the run" || no "(d) exited $RC"
  has 'records: 2[[:space:]]+findings: 1[[:space:]]+misses: 1' \
    && ok "(d) the bad line is skipped; a record with no categories still counts as a record" \
    || no "(d) malformed-input counts wrong; got: $OUT"
fi

# ============================================================================
echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
