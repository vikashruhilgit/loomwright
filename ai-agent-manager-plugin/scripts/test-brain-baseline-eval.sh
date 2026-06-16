#!/usr/bin/env bash
# test-brain-baseline-eval.sh — self-tests for the Phase 0 brain baseline eval harness.
# Mirrors test-benchmark.sh / test-run-eval.sh: isolated, deterministic, no network, no writes
# outside a mktemp sandbox. Exit 0 = all pass, 1 = any failure. Prints "RESULT: N passed, M failed".
#
# Locks the fail-safe contract that PR #60 reviewers verified by hand:
#   1. fail-safe — missing corpus  => status "unverified", items 0, exit 0
#   2. happy path — present corpus => status "ok", items_total == fixture count, exit 0
#   3. leading-zero tool_calls (08/09) => valid JSON, tool_calls coerced to base-10 (NOT a broken marker)
#   4. records land ONLY in the (overridden) brain-baseline file; results.jsonl is never referenced/written
#   5. --no-record => no history file written, still status "ok" + exit 0
#   6. BRAIN_BASELINE_EVAL_RESULT line is valid JSON carrying the documented fields

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RUN="$HERE/brain-baseline-eval.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

marker() { printf '%s\n' "$1" | sed -n 's/^BRAIN_BASELINE_EVAL_RESULT: //p' | head -n1; }

if ! command -v jq >/dev/null 2>&1; then
  echo "test-brain-baseline-eval: jq not available — harness self-tests need jq; skipping (treated as pass)."
  echo; echo "RESULT: 0 passed, 0 failed"; exit 0
fi

SANDBOX="$(mktemp -d 2>/dev/null)" || { echo "cannot mktemp; skipping"; echo "RESULT: 0 passed, 0 failed"; exit 0; }
trap 'rm -rf "$SANDBOX"' EXIT

# ---- 1. fail-safe: missing corpus -----------------------------------------
out="$(BRAIN_BASELINE_CORPUS_DIR="$SANDBOX/does-not-exist" \
      BRAIN_BASELINE_RESULTS_FILE="$SANDBOX/r1.jsonl" \
      bash "$RUN" 2>/dev/null)"; rc=$?
m="$(marker "$out")"
[ "$rc" -eq 0 ] && ok "missing corpus exits 0" || no "missing corpus exit=$rc (want 0)"
[ "$(printf '%s' "$m" | jq -r '.status')" = "unverified" ] && ok "missing corpus => status unverified" || no "missing corpus status=$(printf '%s' "$m" | jq -r '.status')"
[ "$(printf '%s' "$m" | jq -r '.items_total')" = "0" ] && ok "missing corpus => items_total 0" || no "missing corpus items_total != 0"

# ---- build a 2-item sandbox corpus (README.md must be ignored) ------------
CORPUS="$SANDBOX/corpus"; mkdir -p "$CORPUS"
printf '# doc\n' > "$CORPUS/README.md"          # documentation, NOT an item
printf 'q: what calls foo?\n' > "$CORPUS/item-a.md"
printf 'q: blast radius of bar?\n' > "$CORPUS/item-b.md"

# ---- 2. happy path: present corpus ----------------------------------------
out="$(BRAIN_BASELINE_CORPUS_DIR="$CORPUS" \
      BRAIN_BASELINE_RESULTS_FILE="$SANDBOX/r2.jsonl" \
      bash "$RUN" 2>/dev/null)"; rc=$?
m="$(marker "$out")"
[ "$rc" -eq 0 ] && ok "present corpus exits 0" || no "present corpus exit=$rc"
[ "$(printf '%s' "$m" | jq -r '.status')" = "ok" ] && ok "present corpus => status ok" || no "present corpus status != ok"
[ "$(printf '%s' "$m" | jq -r '.items_total')" = "2" ] && ok "README ignored; items_total == 2" || no "items_total=$(printf '%s' "$m" | jq -r '.items_total') (want 2)"

# ---- 3. leading-zero tool_calls => valid JSON, base-10 coercion -----------
# item id 'item-a' sanitizes to 'item_a' for the env key.
out="$(BRAIN_BASELINE_CORPUS_DIR="$CORPUS" \
      BRAIN_BASELINE_RESULTS_FILE="$SANDBOX/r3.jsonl" \
      BRAIN_BASELINE_TOOLCALLS_item_a=08 \
      bash "$RUN" 2>/dev/null)"; rc=$?
m="$(marker "$out")"
if printf '%s' "$m" | jq -e . >/dev/null 2>&1; then
  ok "leading-zero (08) still yields valid JSON marker"
  tc="$(printf '%s' "$m" | jq -r '.records[] | select(.id=="item-a") | .tool_calls')"
  [ "$tc" = "8" ] && ok "tool_calls 08 coerced to 8" || no "tool_calls coerced to '$tc' (want 8)"
else
  no "leading-zero collapsed the marker to invalid JSON"
fi

# ---- 4. records land in the baseline file; results.jsonl never touched ----
R4="$SANDBOX/r4.jsonl"
BRAIN_BASELINE_CORPUS_DIR="$CORPUS" BRAIN_BASELINE_RESULTS_FILE="$R4" bash "$RUN" >/dev/null 2>&1
if [ -f "$R4" ] && [ "$(grep -c . "$R4")" = "2" ]; then ok "2 per-item records written to baseline file"; else no "baseline file missing or wrong line count"; fi
grep -Eq '>>[^#]*results\.jsonl' "$RUN" && no "script appears to write results.jsonl" || ok "script never writes results.jsonl"

# ---- 5. --no-record: no history file written ------------------------------
R5="$SANDBOX/r5.jsonl"
out="$(BRAIN_BASELINE_CORPUS_DIR="$CORPUS" BRAIN_BASELINE_RESULTS_FILE="$R5" bash "$RUN" --no-record 2>/dev/null)"; rc=$?
[ "$rc" -eq 0 ] && ok "--no-record exits 0" || no "--no-record exit=$rc"
[ ! -f "$R5" ] && ok "--no-record writes no history file" || no "--no-record wrote a history file"

# ---- 6. marker carries the documented fields ------------------------------
m="$(marker "$out")"
if printf '%s' "$m" | jq -e 'has("schema_version") and has("items_total") and has("mode") and has("records") and has("status")' >/dev/null 2>&1; then
  ok "marker JSON carries documented fields"
else
  no "marker JSON missing documented fields"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
