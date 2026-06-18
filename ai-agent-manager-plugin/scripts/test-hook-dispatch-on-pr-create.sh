#!/usr/bin/env bash
# test-hook-dispatch-on-pr-create.sh — self-tests for the PostToolUse[Bash]
# PR-create backstop wrapper (hook-dispatch-on-pr-create.sh). Runs in isolated
# temp dirs (never touches the real .supervisor/). Exit 0 = all pass, 1 = any
# failure. Mirrors test-dispatch-pr-review.sh convention. UNCOUNTED by the
# doc-currency gate (test-*.sh).
#
# DETERMINISTIC, NO LIVE SIDE EFFECTS. The suite never runs a live `gh pr
# create` and never launches `claude`:
#   - AI_AGENT_MANAGER_REVIEW_DISPATCH_DRY_RUN=1 makes the chained
#     dispatch-pr-review.sh dry-run (emit DRY_RUN_DISPATCH + write the per-PR
#     marker) instead of launching claude.
#   - AI_AGENT_MANAGER_HOOK_CURRENT_BRANCH is the test seam controlling the
#     wrapper's "current branch" for the AC3 branch-match gate.
#
# REAL-PAYLOAD FIXTURE (AC7). $FIXTURE is captured from a REAL emitted
# PostToolUse[Bash] payload (top-level hook_event_name / tool_name / tool_input
# with the Bash command / tool_response with the gh pr create stdout + PR URL) —
# NOT hand-invented. Per-case payloads are derived by mutating the checked-in
# fixture with jq, so the whole suite is deterministic vs the checked-in fixture
# (AC8).
#
# Covers (each case also asserts rc == 0 — fail-safe exit, AC6):
#   AC1  dispatch: gate-passing fixture as-is -> 1 marker + DRY_RUN_DISPATCH, URL extracted.
#   AC2  non-PR Bash (no URL in response) -> 0 markers (no-op).
#   AC3  branch mismatch -> 0 markers.
#   AC3  in-progress EMPTY (stale state) -> 0 markers.
#   AC3  Status completed (stale state) -> 0 markers.
#   AC4  opt-out (.auto_review:false) -> 0 markers (wrapper delegates opt-out to dispatcher).
#   AC6  malformed JSON stdin -> rc 0, 0 markers.
#   AC6  empty stdin -> rc 0, 0 markers.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WRAPPER="$HERE/hook-dispatch-on-pr-create.sh"
FIXTURE="$HERE/fixtures/posttooluse-gh-pr-create.json"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

# The PR URL the checked-in fixture carries in tool_response.stdout.
PR="https://github.com/acme/widgets/pull/42"

# make_wd <status> <state_branch> [empty_inprogress] —
#   Build an isolated working dir with a .supervisor/ skeleton:
#     - .supervisor/jobs/in-progress/ (+ a dummy job file UNLESS empty_inprogress
#       == "empty").
#     - .supervisor/state.md with a controllable "## Status:" and "- branch:".
#   <state_branch> empty string => omit the "- branch:" line entirely.
make_wd() {
  local status="$1" sbranch="$2" empty="${3:-}"
  local d; d="$(mktemp -d)"
  mkdir -p "$d/.supervisor/jobs/in-progress"
  if [ "$empty" != "empty" ]; then
    printf 'dummy job\n' > "$d/.supervisor/jobs/in-progress/job.md"
  fi
  {
    printf '## Status: %s\n' "$status"
    if [ -n "$sbranch" ]; then
      printf -- '- branch: %s\n' "$sbranch"
    fi
  } > "$d/.supervisor/state.md"
  printf '%s' "$d"
}

# run_wrapper <workdir> <current_branch> <payload_file> —
#   Run the wrapper from inside <workdir> with the test seams set. Captures
#   stdout in RUN_OUT, rc in RUN_RC. No claude, no live gh.
run_wrapper() {
  local wd="$1" br="$2" payload="$3"
  RUN_OUT="$( cd "$wd" && AI_AGENT_MANAGER_REVIEW_DISPATCH_DRY_RUN=1 \
      AI_AGENT_MANAGER_HOOK_CURRENT_BRANCH="$br" \
      bash "$WRAPPER" < "$payload" 2>/dev/null )"
  RUN_RC=$?
}

# marker_count <workdir> — number of per-PR dispatch markers written.
marker_count() {
  local wd="$1"
  ls -1 "$wd/.supervisor/review-dispatch" 2>/dev/null | grep -c . || true
}

TMP_PAYLOADS="$(mktemp -d)"
cleanup() { rm -rf "$TMP_PAYLOADS"; }
trap cleanup EXIT

echo "== AC1. gate-passing fixture as-is -> dispatch (1 marker, DRY_RUN, URL extracted) =="
WD="$(make_wd "in-progress" "feature/example")"
run_wrapper "$WD" "feature/example" "$FIXTURE"
DRY_LINE="$(printf '%s' "$RUN_OUT" | grep 'DRY_RUN_DISPATCH' || true)"
if [ "$RUN_RC" -eq 0 ] \
   && [ -n "$DRY_LINE" ] \
   && [ "$(marker_count "$WD")" -eq 1 ] \
   && printf '%s' "$DRY_LINE" | grep -q -- "$PR"; then
  ok "dispatch: exit 0, 1 marker, DRY_RUN_DISPATCH carries $PR ($DRY_LINE)"
else
  no "dispatch wrong (rc=$RUN_RC markers=$(marker_count "$WD") line='$DRY_LINE')"
fi
rm -rf "$WD"

echo "== AC2. non-PR Bash (no URL in response) -> no-op, 0 markers =="
WD="$(make_wd "in-progress" "feature/example")"
P="$TMP_PAYLOADS/no-url.json"
jq '.tool_response.stdout="hello world no url"' "$FIXTURE" > "$P"
run_wrapper "$WD" "feature/example" "$P"
if [ "$RUN_RC" -eq 0 ] && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "non-PR: exit 0, no dispatch"
else
  no "non-PR wrong (rc=$RUN_RC markers=$(marker_count "$WD") out='$RUN_OUT')"
fi
rm -rf "$WD"

echo "== AC3. branch mismatch -> no-op, 0 markers =="
WD="$(make_wd "in-progress" "feature/example")"
run_wrapper "$WD" "feature/other" "$FIXTURE"
if [ "$RUN_RC" -eq 0 ] && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "branch-mismatch: exit 0, no dispatch"
else
  no "branch-mismatch wrong (rc=$RUN_RC markers=$(marker_count "$WD") out='$RUN_OUT')"
fi
rm -rf "$WD"

echo "== AC3. in-progress EMPTY (stale state) -> no-op, 0 markers =="
WD="$(make_wd "in-progress" "feature/example" "empty")"
run_wrapper "$WD" "feature/example" "$FIXTURE"
if [ "$RUN_RC" -eq 0 ] && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "in-progress-empty: exit 0, no dispatch"
else
  no "in-progress-empty wrong (rc=$RUN_RC markers=$(marker_count "$WD") out='$RUN_OUT')"
fi
rm -rf "$WD"

echo "== AC3. Status completed (stale state) -> no-op, 0 markers =="
WD="$(make_wd "completed" "feature/example")"
run_wrapper "$WD" "feature/example" "$FIXTURE"
if [ "$RUN_RC" -eq 0 ] && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "status-completed: exit 0, no dispatch"
else
  no "status-completed wrong (rc=$RUN_RC markers=$(marker_count "$WD") out='$RUN_OUT')"
fi
rm -rf "$WD"

echo "== AC4. opt-out (.auto_review:false) -> no-op, 0 markers (dispatcher honors opt-out) =="
WD="$(make_wd "in-progress" "feature/example")"
printf '{"auto_review": false}\n' > "$WD/.supervisor/notify-config.json"
run_wrapper "$WD" "feature/example" "$FIXTURE"
if [ "$RUN_RC" -eq 0 ] && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "opt-out: exit 0, dispatcher suppressed, no marker"
else
  no "opt-out wrong (rc=$RUN_RC markers=$(marker_count "$WD") out='$RUN_OUT')"
fi
rm -rf "$WD"

echo "== AC6. malformed JSON stdin -> rc 0, 0 markers =="
WD="$(make_wd "in-progress" "feature/example")"
P="$TMP_PAYLOADS/malformed.txt"
printf 'not json\n' > "$P"
run_wrapper "$WD" "feature/example" "$P"
if [ "$RUN_RC" -eq 0 ] && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "malformed: exit 0, no dispatch"
else
  no "malformed wrong (rc=$RUN_RC markers=$(marker_count "$WD") out='$RUN_OUT')"
fi
rm -rf "$WD"

echo "== AC6. empty stdin -> rc 0, 0 markers =="
WD="$(make_wd "in-progress" "feature/example")"
P="$TMP_PAYLOADS/empty.txt"
: > "$P"
run_wrapper "$WD" "feature/example" "$P"
if [ "$RUN_RC" -eq 0 ] && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "empty: exit 0, no dispatch"
else
  no "empty wrong (rc=$RUN_RC markers=$(marker_count "$WD") out='$RUN_OUT')"
fi
rm -rf "$WD"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
