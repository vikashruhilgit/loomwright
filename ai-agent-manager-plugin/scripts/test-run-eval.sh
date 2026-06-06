#!/usr/bin/env bash
# test-run-eval.sh — self-tests for the System Twin EVAL harness (run-eval.sh).
# Mirrors test-benchmark.sh: isolated, deterministic, no network. Builds temp-fixture corpora via
# mktemp -d + trap cleanup, points run-eval.sh at them via $EVAL_CORPUS_DIR (never touches the real
# corpus). Exit 0 = all pass, 1 = any failure. Prints "RESULT: N passed, M failed".
#
# Covers:
#   1. pass/fail tallying — 2 passing + 1 failing check => total=3, passed=2, pass_rate "2/3",
#      and correct per_task statuses.
#   2. deterministic-same-result — two runs over the same fixture yield identical
#      tasks_total/tasks_passed/pass_rate/per_task (commit/date stripped before compare).
#   3. missing-corpus fail-safe — a non-existent corpus dir => status "unverified", exit 0.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RUN="$HERE/run-eval.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "test-run-eval: jq not available — cannot exercise the eval harness; skipping (treated as pass)."
  echo; echo "RESULT: 0 passed, 0 failed"; exit 0
fi

# Pull the single EVAL_RESULT JSON object out of run-eval.sh output.
eval_json() { printf '%s\n' "$1" | sed -n 's/^EVAL_RESULT: //p' | head -n1; }

# ---- temp fixtures --------------------------------------------------------
TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# Fixture A: 2 passing + 1 failing task.
CORPUS_A="$TMP/corpus-a"
mk_task() {  # mk_task <corpus> <id> <exit-code>
  local c="$1" id="$2" code="$3"
  mkdir -p "$c/$id"
  printf 'task %s\n' "$id" > "$c/$id/spec.md"
  printf '#!/usr/bin/env bash\nexit %s\n' "$code" > "$c/$id/check.sh"
  chmod +x "$c/$id/check.sh"
}
mk_task "$CORPUS_A" "alpha" 0
mk_task "$CORPUS_A" "beta"  0
mk_task "$CORPUS_A" "gamma" 1   # failing

echo "== 1. pass/fail tallying (2 pass + 1 fail => 2/3) =="
oA="$( EVAL_CORPUS_DIR="$CORPUS_A" bash "$RUN" 2>/dev/null )"
jA="$(eval_json "$oA")"
if printf '%s' "$jA" \
  | jq -e '.tasks_total==3 and .tasks_passed==2 and .pass_rate=="2/3" and .status=="ok"' >/dev/null 2>&1; then
  ok "tally: total=3, passed=2, pass_rate=2/3, status=ok"
else
  no "tally wrong: $jA"
fi
# per_task statuses correct + sorted by id
if printf '%s' "$jA" | jq -e '
    (.per_task | map({(.id):.status}) | add)
    == {"alpha":"pass","beta":"pass","gamma":"fail"}
    and (.per_task | map(.id)) == (["alpha","beta","gamma"])
  ' >/dev/null 2>&1; then
  ok "per_task statuses correct and sorted by id"
else
  no "per_task wrong: $(printf '%s' "$jA" | jq -c '.per_task')"
fi

echo "== 2. deterministic-same-result (two runs, ignore commit/date) =="
o1="$( EVAL_CORPUS_DIR="$CORPUS_A" bash "$RUN" 2>/dev/null )"
o2="$( EVAL_CORPUS_DIR="$CORPUS_A" bash "$RUN" 2>/dev/null )"
strip() {  # drop the contextual commit/date fields before comparing
  printf '%s' "$(eval_json "$1")" \
    | jq -cS '{schema_version,tasks_total,tasks_passed,pass_rate,per_task,status}'
}
s1="$(strip "$o1")"; s2="$(strip "$o2")"
[ -n "$s1" ] && [ "$s1" = "$s2" ] \
  && ok "identical determinism-invariant fields across two runs" \
  || no "non-deterministic: $s1 vs $s2"

echo "== 3. missing-corpus fail-safe =="
oM="$( EVAL_CORPUS_DIR="$TMP/does-not-exist" bash "$RUN" 2>/dev/null )"; rc=$?
jM="$(eval_json "$oM")"
if [ "$rc" -eq 0 ] && printf '%s' "$jM" \
  | jq -e '.status=="unverified" and .tasks_total==0 and .pass_rate=="0/0" and (.per_task|length)==0' >/dev/null 2>&1; then
  ok "missing corpus => status unverified, 0/0, per_task [], exit 0"
else
  no "fail-safe path wrong (rc=$rc): $jM"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
