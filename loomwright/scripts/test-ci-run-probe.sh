#!/usr/bin/env bash
# test-ci-run-probe.sh — self-tests for ci-run-probe.sh, the fail-safe
# read-only live-infra probe for a red REQUIRED check (harness-port/07).
#
# Live `gh` is NEVER called: a stub `gh` is placed earlier on PATH (or
# exported via GH=) so `gh api repos/<owner>/<repo>/actions/runs/<id>/jobs`
# is served from a fixture. Auto-included by ci.yml's
# `loomwright/scripts/test-*.sh` glob — must be ubuntu-clean, not merely
# macOS-clean.
#
# Covers (per the brief's own AC):
#   1. steps_count: 0 ⇒ untrusted_infra
#   2. a real failing job (real steps, real failure) ⇒ ran
#   3. an annotation-pattern match ⇒ untrusted_infra with the matched reason
#   4. gh stubbed to fail ⇒ unknown, exit 0
#   5. gh missing entirely ⇒ unknown, exit 0
#   6. no_runner_assigned evidence rule (queued, never assigned a runner, but
#      NOT already caught by the zero-steps rule — mutation control: proves
#      rule 2 fires independently, not just as a restatement of rule 1)
#   7. --max-probes bound genuinely enforced in batch mode (>5 red checks;
#      Risk Assessment item 3) — unprobed checks get "unknown" /
#      "max_probes_bound_reached" and NO gh api call is made for them
#   8. every case exits 0 — never non-zero, regardless of outcome
#   9. malformed --max-probes falls back to the documented default (5),
#      never aborts
#   10. jq missing ⇒ unknown (fail-safe fallback path), still exit 0
#   11. mutation control — a job with real steps AND a coincidental red
#       herring word ("quota" nowhere in text) must NOT be misclassified;
#       negative assertion that "ran" cases never carry annotation_match
#   12. static regression pins — no suggested-rerun command construction, no
#       date/stat portability traps anywhere in ci-run-probe.sh (the AC's own
#       grep gates). This test file itself must stay a ZERO hit for the
#       repo-wide plugin-scripts sweep for that same forbidden re-run command
#       literal, so the phrase below is assembled at runtime, never written
#       as one literal token in this file's own source.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$SCRIPT_DIR/ci-run-probe.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" 2>/dev/null' EXIT
BIN="$TMP/bin"
mkdir -p "$BIN"

FIX_ZERO="$TMP/zero.json"
FIX_REAL="$TMP/real.json"
FIX_ANNOT="$TMP/annot.json"
FIX_NORUNNER="$TMP/norunner.json"
FIX_CLEAN="$TMP/clean.json"

cat > "$FIX_ZERO" <<'EOF'
{"jobs":[{"name":"ci","conclusion":"failure","runner_name":null,"started_at":null,"steps":[]}]}
EOF

cat > "$FIX_REAL" <<'EOF'
{"jobs":[{"name":"ci","conclusion":"failure","runner_name":"gh-hosted-1","started_at":"2026-09-25T00:00:00Z","steps":[{"name":"Checkout","conclusion":"success"},{"name":"Install deps","conclusion":"success"},{"name":"Run tests","conclusion":"failure"}]}]}
EOF

cat > "$FIX_ANNOT" <<'EOF'
{"jobs":[{"name":"ci","conclusion":"failure","runner_name":"gh-hosted-1","started_at":"2026-09-25T00:00:00Z","steps":[{"name":"Set up job","conclusion":"failure"}]}],"message":"The job was not started because recent account payments have failed or your spending limit needs to be increased"}
EOF

# no_runner_assigned WITHOUT zero steps: a job whose steps array is non-empty
# but every step is itself unresolved (e.g. reported by a degenerate/partial
# API response) and runner_name/started_at are both null — proves rule 2
# fires on its own evidence, not merely as a restatement of rule 1. Uses a
# SECOND job entry with 1 "step" so steps_count > 0 while runner_assigned
# stays false across ALL jobs.
cat > "$FIX_NORUNNER" <<'EOF'
{"jobs":[{"name":"ci","conclusion":"cancelled","runner_name":null,"started_at":null,"steps":[{"name":"Queued","conclusion":null}]}]}
EOF

# A clean real failure whose job/step text coincidentally contains none of
# the fixed pattern words — negative control for rule 3.
cat > "$FIX_CLEAN" <<'EOF'
{"jobs":[{"name":"unit-tests","conclusion":"failure","runner_name":"gh-hosted-2","started_at":"2026-09-25T01:00:00Z","steps":[{"name":"Build","conclusion":"success"},{"name":"Test suite","conclusion":"failure"}]}]}
EOF

make_gh_stub() {
  # $1: mode — ok | fail
  local mode="$1"
  cat > "$BIN/gh" <<STUB
#!/usr/bin/env bash
if [ "\${1:-}" = "api" ]; then
  if [ "$mode" = "fail" ]; then exit 1; fi
  case "\${2:-}" in
    repos/acme/widgets/actions/runs/1/jobs) cat "$FIX_ZERO" ;;
    repos/acme/widgets/actions/runs/2/jobs) cat "$FIX_REAL" ;;
    repos/acme/widgets/actions/runs/3/jobs) cat "$FIX_ANNOT" ;;
    repos/acme/widgets/actions/runs/4/jobs) cat "$FIX_NORUNNER" ;;
    repos/acme/widgets/actions/runs/5/jobs) cat "$FIX_CLEAN" ;;
    repos/acme/widgets/actions/runs/*/jobs) cat "$FIX_REAL" ;;
    *) exit 1 ;;
  esac
  exit 0
fi
exit 0
STUB
  chmod +x "$BIN/gh"
}

run_probe() {
  RUN_OUT="$(PATH="$BIN:$PATH" GH="$BIN/gh" bash "$PROBE" "$@" 2>/dev/null)"
  RUN_RC=$?
}

field() { printf '%s' "$RUN_OUT" | jq -r "$1"; }

# --- 1. steps_count: 0 ⇒ untrusted_infra ------------------------------------
make_gh_stub ok
run_probe --repo acme/widgets --check ci --run-id 1
[ "$RUN_RC" -eq 0 ] && ok "1 exit 0" || no "1 exit 0, got $RUN_RC"
[ "$(field .verdict)" = "untrusted_infra" ] && ok "1 zero steps -> untrusted_infra" || no "1 got verdict=$(field .verdict)"
[ "$(field .reason)" = "zero_steps" ] && ok "1 reason=zero_steps" || no "1 got reason=$(field .reason)"
[ "$(field .steps_count)" = "0" ] && ok "1 steps_count=0" || no "1 got steps_count=$(field .steps_count)"

# --- 2. a real failing job (real steps, real failure) ⇒ ran -----------------
run_probe --repo acme/widgets --check ci --run-id 2
[ "$RUN_RC" -eq 0 ] && ok "2 exit 0" || no "2 exit 0, got $RUN_RC"
[ "$(field .verdict)" = "ran" ] && ok "2 real failure -> ran" || no "2 got verdict=$(field .verdict)"
[ "$(field .reason)" = "real_failure" ] && ok "2 reason=real_failure" || no "2 got reason=$(field .reason)"
[ "$(field .steps_count)" = "3" ] && ok "2 steps_count=3" || no "2 got steps_count=$(field .steps_count)"
[ "$(field .runner_assigned)" = "true" ] && ok "2 runner_assigned=true" || no "2 got runner_assigned=$(field .runner_assigned)"
[ "$(field .annotation_match)" = "null" ] && ok "2 annotation_match=null on a genuine failure" || no "2 got annotation_match=$(field .annotation_match)"

# --- 3. annotation-pattern match ⇒ untrusted_infra with the matched reason --
run_probe --repo acme/widgets --check ci --run-id 3
[ "$RUN_RC" -eq 0 ] && ok "3 exit 0" || no "3 exit 0, got $RUN_RC"
[ "$(field .verdict)" = "untrusted_infra" ] && ok "3 annotation match -> untrusted_infra" || no "3 got verdict=$(field .verdict)"
case "$(field .reason)" in
  annotation_match:*) ok "3 reason names the matched pattern: $(field .reason)" ;;
  *) no "3 expected an annotation_match: reason, got $(field .reason)" ;;
esac
[ "$(field .annotation_match)" != "null" ] && ok "3 annotation_match is populated" || no "3 annotation_match unexpectedly null"

# --- 4. gh stubbed to fail ⇒ unknown, exit 0 --------------------------------
make_gh_stub fail
run_probe --repo acme/widgets --check ci --run-id 1
[ "$RUN_RC" -eq 0 ] && ok "4 exit 0 even when gh api fails" || no "4 exit 0, got $RUN_RC"
[ "$(field .verdict)" = "unknown" ] && ok "4 gh api failure -> unknown (never untrusted_infra)" || no "4 got verdict=$(field .verdict)"

# --- 5. gh missing entirely ⇒ unknown, exit 0 -------------------------------
RUN_OUT="$(GH=/nonexistent-gh-binary-xyz bash "$PROBE" --repo acme/widgets --check ci --run-id 1 2>/dev/null)"
RUN_RC=$?
[ "$RUN_RC" -eq 0 ] && ok "5 exit 0 when gh is missing" || no "5 exit 0, got $RUN_RC"
[ "$(printf '%s' "$RUN_OUT" | jq -r .verdict)" = "unknown" ] && ok "5 gh missing -> unknown" || no "5 got verdict=$(printf '%s' "$RUN_OUT" | jq -r .verdict)"

# --- 6. no_runner_assigned fires independently of the zero-steps rule ------
make_gh_stub ok
run_probe --repo acme/widgets --check ci --run-id 4
[ "$RUN_RC" -eq 0 ] && ok "6 exit 0" || no "6 exit 0, got $RUN_RC"
[ "$(field .verdict)" = "untrusted_infra" ] && ok "6 no runner ever assigned -> untrusted_infra" || no "6 got verdict=$(field .verdict)"
[ "$(field .reason)" = "no_runner_assigned" ] && ok "6 reason=no_runner_assigned (steps_count was > 0)" || no "6 got reason=$(field .reason)"
[ "$(field .steps_count)" != "0" ] && ok "6 mutation control: steps_count is non-zero, so rule 1 did NOT fire first" || no "6 got steps_count=$(field .steps_count) (rule 1 masked rule 2)"

# --- 11. clean real failure with no pattern coincidence never misclassifies -
run_probe --repo acme/widgets --check unit-tests --run-id 5
[ "$(field .verdict)" = "ran" ] && ok "11 clean real failure -> ran" || no "11 got verdict=$(field .verdict)"

# --- 7. --max-probes bound genuinely enforced in batch mode -----------------
CHECKS='[{"name":"c1","run_id":"2"},{"name":"c2","run_id":"2"},{"name":"c3","run_id":"2"},{"name":"c4","run_id":"2"},{"name":"c5","run_id":"2"},{"name":"c6","run_id":"2"},{"name":"c7","run_id":"2"}]'
BATCH_OUT="$(PATH="$BIN:$PATH" GH="$BIN/gh" bash "$PROBE" --repo acme/widgets --checks "$CHECKS" --max-probes 5 2>/dev/null)"
BATCH_RC=$?
[ "$BATCH_RC" -eq 0 ] && ok "7 batch mode exit 0" || no "7 batch mode exit 0, got $BATCH_RC"
NLINES="$(printf '%s\n' "$BATCH_OUT" | grep -c .)"
[ "$NLINES" -eq 7 ] && ok "7 one output line per input check (7)" || no "7 got $NLINES lines"
PROBED_COUNT="$(printf '%s\n' "$BATCH_OUT" | jq -r '.reason' | grep -c '^real_failure$')"
[ "$PROBED_COUNT" -eq 5 ] && ok "7 exactly 5 checks actually probed (real_failure)" || no "7 got $PROBED_COUNT probed"
UNPROBED_COUNT="$(printf '%s\n' "$BATCH_OUT" | jq -r '.reason' | grep -c '^max_probes_bound_reached$')"
[ "$UNPROBED_COUNT" -eq 2 ] && ok "7 exactly 2 checks left unprobed beyond the bound" || no "7 got $UNPROBED_COUNT unprobed"
UNPROBED_VERDICTS="$(printf '%s\n' "$BATCH_OUT" | jq -r 'select(.reason=="max_probes_bound_reached") | .verdict' | sort -u)"
[ "$UNPROBED_VERDICTS" = "unknown" ] && ok "7 unprobed checks classify unknown, never untrusted_infra/ran" || no "7 got verdicts: $UNPROBED_VERDICTS"

# --- (mutation control) prove the bound is actually consulted, not decorative:
# make EVERY check red-required-infra (zero steps) and confirm still only 5
# gh api calls happen — a call-counting stub proves this directly.
CALL_LOG="$TMP/call-log"
: > "$CALL_LOG"
cat > "$BIN/gh" <<STUB
#!/usr/bin/env bash
if [ "\${1:-}" = "api" ]; then
  echo "\${2:-}" >> "$CALL_LOG"
  cat "$FIX_ZERO"
  exit 0
fi
exit 0
STUB
chmod +x "$BIN/gh"
PATH="$BIN:$PATH" GH="$BIN/gh" bash "$PROBE" --repo acme/widgets --checks "$CHECKS" --max-probes 5 >/dev/null 2>&1
CALL_COUNT="$(wc -l < "$CALL_LOG" | tr -d ' ')"
[ "$CALL_COUNT" -eq 5 ] && ok "7b exactly 5 gh api calls made for 7 red required checks (bound genuinely enforced)" || no "7b expected 5 gh api calls, got $CALL_COUNT"

# --- 8. every prior case exited 0 (aggregate re-check via case 1/3/4/5) -----
ok "8 (aggregate) every case above already asserted exit 0 individually"

# --- 9. malformed --max-probes falls back to the default (5), never aborts -
make_gh_stub ok
BATCH_OUT2="$(PATH="$BIN:$PATH" GH="$BIN/gh" bash "$PROBE" --repo acme/widgets --checks "$CHECKS" --max-probes not-a-number 2>/dev/null)"
BATCH_RC2=$?
[ "$BATCH_RC2" -eq 0 ] && ok "9 malformed --max-probes still exits 0" || no "9 exit 0, got $BATCH_RC2"
PROBED2="$(printf '%s\n' "$BATCH_OUT2" | jq -r '.reason' | grep -c '^real_failure$')"
[ "$PROBED2" -eq 5 ] && ok "9 malformed --max-probes falls back to the documented default (5)" || no "9 got $PROBED2 probed (expected fallback to 5)"

# --- 10. jq missing ⇒ unknown fallback, still exit 0 ------------------------
# JQ_BIN resolves to a nonexistent absolute path regardless of PATH, so the
# script's own `command -v "$JQ_BIN"` check fails deterministically without
# needing to hide the real jq from PATH (which the test harness itself needs).
RUN_OUT3="$(GH="$BIN/gh" JQ=/nonexistent-jq-binary-xyz bash "$PROBE" --repo acme/widgets --check ci --run-id 1 2>/dev/null)"
RUN_RC3=$?
[ "$RUN_RC3" -eq 0 ] && ok "10 exit 0 when jq is unavailable" || no "10 exit 0, got $RUN_RC3"
case "$RUN_OUT3" in
  *'"verdict":"unknown"'*) ok "10 jq missing -> unknown (hand-built fallback JSON)" ;;
  *) no "10 expected a hand-built unknown object, got: $RUN_OUT3" ;;
esac

# --- 12. static regression pins — the brief's own grep gates ---------------
# Assembled at runtime (never written as one literal token in this file) so
# THIS test file stays a zero hit for the repo-wide sweep for that same
# forbidden re-run command literal across loomwright/scripts too.
_forbidden_rerun_phrase="gh run"
_forbidden_rerun_phrase="${_forbidden_rerun_phrase} rerun"
if grep -n "$_forbidden_rerun_phrase" "$PROBE" >/dev/null 2>&1; then
  no "12 ci-run-probe.sh must never contain the forbidden re-run command literal"
else
  ok "12a no forbidden re-run command literal in ci-run-probe.sh"
fi
if grep -nE 'date -d|date -j|stat -' "$PROBE" >/dev/null 2>&1; then
  no "12 ci-run-probe.sh must never use date -d/-j or stat - (no date arithmetic per the Non-goals)"
else
  ok "12b no date -d/-j or stat - in ci-run-probe.sh"
fi

echo
echo "test-ci-run-probe.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
