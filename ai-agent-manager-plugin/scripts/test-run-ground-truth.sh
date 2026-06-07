#!/usr/bin/env bash
# test-run-ground-truth.sh — self-tests for the System Twin GROUND-TRUTH runner (run-ground-truth.sh).
# Mirrors test-run-eval.sh: isolated, deterministic, no network. Runs from a temp CWD so it can
# never pollute the real .supervisor/ (the runner's ground-truth.json fallback resolves against the
# git root of the CWD). Exit 0 = all pass, 1 = any failure. Prints "RESULT: N passed, M failed".
#
# Covers the five core AC cases plus the corpus dogfood and edge cases — 11 assertions (a–j, incl. e2):
#   (a) passing check (--check 'cmd: true')          => status "pass", 1/1, exit 0.
#   (b) failing check (--check 'cmd: false')         => status "advisory_failures", per_check fail, exit 0.
#   (c) no source (temp CWD, no ground-truth.json)   => status "skipped", 0/0, exit 0.
#   (d) missing-jq simulation (GROUND_TRUTH_FORCE_NO_JQ=1) => status "unverified", exit 0.
#   (e) qa-executor check                            => per_check unverified + deferred reason, ran false, exit 0.
#   (e2) qa-executor coexisting with a passing cmd   => status "pass" (deferred never blocks).
#   (f) corpus-task: version-consistent              => executes the real check, hard pass/fail, 1/1 total.
#   (g) missing corpus-task                          => per_check fail, reason corpus_task_not_found, exit 0.
#   (h) corpus-task with path traversal              => per_check fail, reason corpus_task_invalid_id, exit 0.
#   (i) cmd: target with a leading dash              => target preserved verbatim (not bullet-stripped).
#   (j) --brief heading match is exact               => sibling "## Executable Acceptance Notes" ignored.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RUN="$HERE/run-ground-truth.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "test-run-ground-truth: jq not available — cannot exercise the runner; skipping (treated as pass)."
  echo; echo "RESULT: 0 passed, 0 failed"; exit 0
fi

# Pull the single GROUND_TRUTH_JSON object out of the runner output.
gt_json() { printf '%s\n' "$1" | sed -n 's/^GROUND_TRUTH_JSON: //p' | head -n1; }

# Isolated temp CWD so the ground-truth.json fallback can never see the real .supervisor/.
TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT
# A non-git temp dir (git rev-parse falls back to pwd; no .supervisor/twin/ground-truth.json here).
CWD="$TMP/work"
mkdir -p "$CWD"

echo "== (a) passing check (cmd: true) => status pass, 1/1 =="
oA="$( cd "$CWD" && bash "$RUN" --check 'cmd: true' 2>/dev/null )"; rcA=$?
jA="$(gt_json "$oA")"
if [ "$rcA" -eq 0 ] && printf '%s' "$jA" | jq -e '
    .status=="pass" and .ran==true and .checks_total==1 and .checks_passed==1
    and .pass_rate=="1/1" and (.per_check|length)==1 and .per_check[0].status=="pass"
  ' >/dev/null 2>&1; then
  ok "passing check: status pass, total/passed 1, pass_rate 1/1, exit 0"
else
  no "(a) wrong (rc=$rcA): $jA"
fi

echo "== (b) failing check (cmd: false) => advisory_failures, exit 0 =="
oB="$( cd "$CWD" && bash "$RUN" --check 'cmd: false' 2>/dev/null )"; rcB=$?
jB="$(gt_json "$oB")"
if [ "$rcB" -eq 0 ] && printf '%s' "$jB" | jq -e '
    .status=="advisory_failures" and .checks_total==1 and .checks_passed==0
    and .pass_rate=="0/1" and .per_check[0].status=="fail"
  ' >/dev/null 2>&1; then
  ok "failing check: status advisory_failures, per_check fail, exit 0"
else
  no "(b) wrong (rc=$rcB): $jB"
fi

echo "== (c) no source => skipped, 0/0, exit 0 =="
oC="$( cd "$CWD" && bash "$RUN" 2>/dev/null )"; rcC=$?
jC="$(gt_json "$oC")"
if [ "$rcC" -eq 0 ] && printf '%s' "$jC" | jq -e '
    .status=="skipped" and .ran==false and .checks_total==0
    and .pass_rate=="0/0" and (.per_check|length)==0
  ' >/dev/null 2>&1; then
  ok "no source: status skipped, 0/0, per_check [], exit 0"
else
  no "(c) wrong (rc=$rcC): $jC"
fi

echo "== (d) missing-jq simulation (GROUND_TRUTH_FORCE_NO_JQ=1) => unverified, exit 0 =="
oD="$( cd "$CWD" && GROUND_TRUTH_FORCE_NO_JQ=1 bash "$RUN" --check 'cmd: true' 2>/dev/null )"; rcD=$?
jD="$(gt_json "$oD")"
if [ "$rcD" -eq 0 ] && printf '%s' "$jD" | jq -e '
    .status=="unverified" and .ran==false and .checks_total==0 and .pass_rate=="0/0"
  ' >/dev/null 2>&1; then
  ok "no-jq path: status unverified, ran false, 0/0, exit 0"
else
  no "(d) wrong (rc=$rcD): $jD"
fi

echo "== (e) qa-executor check => per_check unverified + deferred reason, exit 0 =="
oE="$( cd "$CWD" && bash "$RUN" --check 'qa-executor: login-smoke' 2>/dev/null )"; rcE=$?
jE="$(gt_json "$oE")"
# only deferred check => zero pass, zero fail => status unverified (nothing actually verified),
# and ran==false (no check executed a verifiable pass/fail) — pins the ground_truth.checked mapping.
if [ "$rcE" -eq 0 ] && printf '%s' "$jE" | jq -e '
    .checks_total==1 and .checks_passed==0 and .ran==false
    and .per_check[0].kind=="qa-executor" and .per_check[0].status=="unverified"
    and .per_check[0].reason=="qa_executor_dispatch_deferred_m2b_1b"
    and .status=="unverified"
  ' >/dev/null 2>&1; then
  ok "qa-executor: per_check unverified, deferred reason, ran false, status unverified, exit 0"
else
  no "(e) wrong (rc=$rcE): $jE"
fi

echo "== (e2) qa-executor coexisting with a passing cmd => status pass (deferred never blocks) =="
oE2="$( cd "$CWD" && bash "$RUN" --check 'cmd: true' --check 'qa-executor: x' 2>/dev/null )"
jE2="$(gt_json "$oE2")"
if printf '%s' "$jE2" | jq -e '
    .status=="pass" and .checks_total==2 and .checks_passed==1
    and ([.per_check[].status] | sort) == (["pass","unverified"])
  ' >/dev/null 2>&1; then
  ok "deferred qa-executor + passing cmd => status pass, total 2, passed 1"
else
  no "(e2) wrong: $jE2"
fi

echo "== (f) corpus-task: version-consistent => executes real check, hard pass/fail, 1/1 total =="
oF="$( cd "$CWD" && bash "$RUN" --check 'corpus-task: version-consistent' 2>/dev/null )"; rcF=$?
jF="$(gt_json "$oF")"
if [ "$rcF" -eq 0 ] && printf '%s' "$jF" | jq -e '
    .checks_total==1 and .per_check[0].kind=="corpus-task"
    and .per_check[0].target=="version-consistent"
    and (.per_check[0].status | IN("pass","fail"))
    and (.status | IN("pass","advisory_failures"))
  ' >/dev/null 2>&1; then
  ok "corpus-task version-consistent executed: total 1, hard $(printf '%s' "$jF" | jq -r '.per_check[0].status'), exit 0"
else
  no "(f) wrong (rc=$rcF): $jF"
fi

echo "== (g) missing corpus-task => fail with corpus_task_not_found =="
oG="$( cd "$CWD" && bash "$RUN" --check 'corpus-task: does-not-exist-xyz' 2>/dev/null )"; rcG=$?
jG="$(gt_json "$oG")"
if [ "$rcG" -eq 0 ] && printf '%s' "$jG" | jq -e '
    .status=="advisory_failures" and .per_check[0].status=="fail"
    and .per_check[0].reason=="corpus_task_not_found"
  ' >/dev/null 2>&1; then
  ok "missing corpus-task => per_check fail, reason corpus_task_not_found, exit 0"
else
  no "(g) wrong (rc=$rcG): $jG"
fi

echo "== (h) corpus-task with path traversal => rejected as invalid id, exit 0 =="
oH="$( cd "$CWD" && bash "$RUN" --check 'corpus-task: ../version-consistent' 2>/dev/null )"; rcH=$?
jH="$(gt_json "$oH")"
if [ "$rcH" -eq 0 ] && printf '%s' "$jH" | jq -e '
    .status=="advisory_failures" and .per_check[0].status=="fail"
    and .per_check[0].reason=="corpus_task_invalid_id"
  ' >/dev/null 2>&1; then
  ok "path-traversal corpus-task => per_check fail, reason corpus_task_invalid_id, exit 0"
else
  no "(h) wrong (rc=$rcH): $jH"
fi

echo "== (i) cmd: target keeps a leading dash (not eaten by bullet-stripping) =="
# Regression for the strip_bullet-on-target bug: `cmd: -x foo` previously lost its leading dash.
# The fix is verified by the target being recorded VERBATIM (incl. the leading dash). We assert on the
# preserved target + exit 0, not on pass/fail — a leading-dash token is not a runnable command, so the
# tally is irrelevant; target preservation is the contract under test.
oI="$( cd "$CWD" && bash "$RUN" --check 'cmd: -x foo' 2>/dev/null )"; rcI=$?
jI="$(gt_json "$oI")"
if [ "$rcI" -eq 0 ] && printf '%s' "$jI" | jq -e '
    .per_check[0].kind=="cmd" and .per_check[0].target=="-x foo"
  ' >/dev/null 2>&1; then
  ok "cmd target preserves leading dash (target == '-x foo'), exit 0"
else
  no "(i) wrong (rc=$rcI): $jI"
fi

echo "== (j) --brief heading match is exact ('## Executable Acceptance Notes' must NOT open section) =="
BRF="$TMP/brief-notes.md"
printf '## Executable Acceptance Notes\n- cmd: false\n\n## Executable Acceptance\n- cmd: true\n' > "$BRF"
oJ="$( cd "$CWD" && bash "$RUN" --brief "$BRF" 2>/dev/null )"; rcJ=$?
jJ="$(gt_json "$oJ")"
# Only the real heading's `cmd: true` (pass) is collected; the "Notes" heading's `cmd: false` is ignored.
if [ "$rcJ" -eq 0 ] && printf '%s' "$jJ" | jq -e '
    .status=="pass" and .checks_total==1 and .per_check[0].target=="true"
  ' >/dev/null 2>&1; then
  ok "exact heading match: sibling '## Executable Acceptance Notes' ignored, only real section collected"
else
  no "(j) wrong (rc=$rcJ): $jJ"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
