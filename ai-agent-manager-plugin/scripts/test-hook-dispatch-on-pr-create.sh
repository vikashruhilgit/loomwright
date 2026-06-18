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
#   AC2b non-create command (URL present but command is `gh pr view`) -> 0 markers.
#   AC3  branch mismatch -> 0 markers.
#   AC3  in-progress EMPTY (stale state) -> 0 markers.
#   AC3  Status completed (stale state) -> 0 markers.
#   AC3  Status completed_with_escalation (terminal/stale) -> 0 markers.
#   AC2  bold-format MATCH (- **Branch:** / - **Status:**) -> dispatch (format-tolerant parse).
#   AC2  bold-format branch-MISMATCH -> 0 markers (anti-hijack preserved in bold form).
#   AC2  bold-format Status completed -> 0 markers (stale fail-close in bold form).
#   AC2  bold-format Status completed_with_escalation -> 0 markers (terminal fail-close in bold form).
#   AC5  state.md present but NO `- branch:` line -> NO dispatch (gate iii fail-closed; no fallback).
#   AC5  state.md ENTIRELY ABSENT -> NO dispatch (gate iii fail-closed; branch unconfirmable).
#   AC4  opt-out (.auto_review:false) -> 0 markers (wrapper delegates opt-out to dispatcher).
#   AC6  malformed JSON stdin -> rc 0, 0 markers.
#   AC6  empty stdin -> rc 0, 0 markers.
#   AC6  non-Bash tool_name (e.g. "Read") -> rc 0, 0 markers (matcher-defensive no-op).
#   AC6  jq absent on PATH -> rc 0, 0 markers (fail-safe missing-jq branch).

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
#     - .supervisor/state.md in the REAL canonical schema: a `## Session` heading
#       with a controllable `- status:` and `- branch:` (lowercase bullets).
#   <state_branch> empty string => omit the "- branch:" line entirely.
make_wd() {
  local status="$1" sbranch="$2" empty="${3:-}"
  local d; d="$(mktemp -d)"
  mkdir -p "$d/.supervisor/jobs/in-progress"
  if [ "$empty" != "empty" ]; then
    printf 'dummy job\n' > "$d/.supervisor/jobs/in-progress/job.md"
  fi
  {
    printf '## Session\n'
    printf -- '- status: %s\n' "$status"
    if [ -n "$sbranch" ]; then
      printf -- '- branch: %s\n' "$sbranch"
    fi
  } > "$d/.supervisor/state.md"
  printf '%s' "$d"
}

# make_wd_bold <status> <state_branch> —
#   Like make_wd, but writes .supervisor/state.md in the INLINE-SUPERVISOR BOLD
#   display style (`- **Status:** X` / `- **Branch:** Y`) instead of the canonical
#   lowercase bullets. Exercises the wrapper's format-tolerant parsing. Always
#   writes a dummy in-progress job. <state_branch> empty => omit the branch line.
make_wd_bold() {
  local status="$1" sbranch="$2"
  local d; d="$(mktemp -d)"
  mkdir -p "$d/.supervisor/jobs/in-progress"
  printf 'dummy job\n' > "$d/.supervisor/jobs/in-progress/job.md"
  {
    printf '## Session\n'
    printf -- '- **Status:** %s\n' "$status"
    if [ -n "$sbranch" ]; then
      printf -- '- **Branch:** %s\n' "$sbranch"
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
WD="$(make_wd "running" "feature/example")"
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
WD="$(make_wd "running" "feature/example")"
P="$TMP_PAYLOADS/no-url.json"
jq '.tool_response.stdout="hello world no url"' "$FIXTURE" > "$P"
run_wrapper "$WD" "feature/example" "$P"
if [ "$RUN_RC" -eq 0 ] && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "non-PR: exit 0, no dispatch"
else
  no "non-PR wrong (rc=$RUN_RC markers=$(marker_count "$WD") out='$RUN_OUT')"
fi
rm -rf "$WD"

echo "== AC2b. non-create command (URL in response but command is 'gh pr view') -> no-op, 0 markers =="
WD="$(make_wd "running" "feature/example")"
P="$TMP_PAYLOADS/pr-view.json"
# Keep the PR URL in the response, but the command is a read-only `gh pr view` —
# the command guard must prevent a drain against a foreign PR merely mentioned in output.
jq '.tool_input.command="gh pr view 42 --json url"' "$FIXTURE" > "$P"
run_wrapper "$WD" "feature/example" "$P"
if [ "$RUN_RC" -eq 0 ] && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "non-create-command: exit 0, no dispatch (command guard)"
else
  no "non-create-command wrong (rc=$RUN_RC markers=$(marker_count "$WD") out='$RUN_OUT')"
fi
rm -rf "$WD"

echo "== AC3. branch mismatch -> no-op, 0 markers =="
WD="$(make_wd "running" "feature/example")"
run_wrapper "$WD" "feature/other" "$FIXTURE"
if [ "$RUN_RC" -eq 0 ] && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "branch-mismatch: exit 0, no dispatch"
else
  no "branch-mismatch wrong (rc=$RUN_RC markers=$(marker_count "$WD") out='$RUN_OUT')"
fi
rm -rf "$WD"

echo "== AC3. in-progress EMPTY (stale state) -> no-op, 0 markers =="
WD="$(make_wd "running" "feature/example" "empty")"
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

echo "== AC3. Status completed_with_escalation (terminal/stale) -> no-op, 0 markers =="
# The Supervisor Phase 4.5 ESCALATED completion tail flips `- status:` to
# `completed_with_escalation`; it is terminal and must fail-close the stale-guard
# exactly like `completed`/`completed_with_escalation`/`failed` (else a later unrelated PR on the same branch
# could re-trigger a dispatch on a finished session).
WD="$(make_wd "completed_with_escalation" "feature/example")"
run_wrapper "$WD" "feature/example" "$FIXTURE"
if [ "$RUN_RC" -eq 0 ] && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "status-completed_with_escalation: exit 0, no dispatch (terminal fail-close)"
else
  no "status-completed_with_escalation wrong (rc=$RUN_RC markers=$(marker_count "$WD") out='$RUN_OUT')"
fi
rm -rf "$WD"

echo "== AC5. state.md present, no '- branch:' line -> NO dispatch (gate iii fail-closed) =="
WD="$(make_wd "running" "")"        # empty sbranch => no '- branch:' line
run_wrapper "$WD" "feature/example" "$FIXTURE"
# Branch unconfirmable (no '- branch:' to match) -> fail-closed, no fallback.
if [ "$RUN_RC" -eq 0 ] && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "no-branch-line: exit 0, no dispatch (fail-closed on unconfirmable branch)"
else
  no "no-branch-line wrong (rc=$RUN_RC markers=$(marker_count "$WD") out='$RUN_OUT')"
fi
rm -rf "$WD"

echo "== AC5. state.md absent -> NO dispatch (gate iii fail-closed: branch unconfirmable) =="
WD="$(make_wd "running" "feature/example")"
rm -f "$WD/.supervisor/state.md"        # state.md entirely absent
run_wrapper "$WD" "feature/example" "$FIXTURE"
# No state.md => no resolvable session branch => fail-closed (anti-hijack).
if [ "$RUN_RC" -eq 0 ] && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "no-state-file: exit 0, no dispatch (fail-closed on unconfirmable branch)"
else
  no "no-state-file wrong (rc=$RUN_RC markers=$(marker_count "$WD") out='$RUN_OUT')"
fi
rm -rf "$WD"

echo "== AC2. bold-format MATCH (- **Branch:** / - **Status:**) -> dispatch (1 marker, DRY_RUN) =="
WD="$(make_wd_bold "running" "feature/example")"
run_wrapper "$WD" "feature/example" "$FIXTURE"
DRY_LINE="$(printf '%s' "$RUN_OUT" | grep 'DRY_RUN_DISPATCH' || true)"
if [ "$RUN_RC" -eq 0 ] \
   && [ -n "$DRY_LINE" ] \
   && [ "$(marker_count "$WD")" -eq 1 ] \
   && printf '%s' "$DRY_LINE" | grep -q -- "$PR"; then
  ok "bold-match: exit 0, 1 marker, branch resolved from bold line ($DRY_LINE)"
else
  no "bold-match wrong (rc=$RUN_RC markers=$(marker_count "$WD") line='$DRY_LINE')"
fi
rm -rf "$WD"

echo "== AC2. bold-format branch-MISMATCH (- **Branch:** feature/example vs current feature/other) -> no-op =="
WD="$(make_wd_bold "running" "feature/example")"
run_wrapper "$WD" "feature/other" "$FIXTURE"
# Anti-hijack preserved: a bold-format branch that does not match current branch must skip.
if [ "$RUN_RC" -eq 0 ] && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "bold-branch-mismatch: exit 0, no dispatch (anti-hijack preserved in bold form)"
else
  no "bold-branch-mismatch wrong (rc=$RUN_RC markers=$(marker_count "$WD") out='$RUN_OUT')"
fi
rm -rf "$WD"

echo "== AC2. bold-format Status completed (- **Status:** completed) -> no-op (stale fail-close in bold form) =="
WD="$(make_wd_bold "completed" "feature/example")"
run_wrapper "$WD" "feature/example" "$FIXTURE"
# Stale-status fail-close must work for the bold form too.
if [ "$RUN_RC" -eq 0 ] && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "bold-status-completed: exit 0, no dispatch (stale fail-close in bold form)"
else
  no "bold-status-completed wrong (rc=$RUN_RC markers=$(marker_count "$WD") out='$RUN_OUT')"
fi
rm -rf "$WD"

echo "== AC2. bold-format Status completed_with_escalation (- **Status:** completed_with_escalation) -> no-op (terminal fail-close in bold form) =="
WD="$(make_wd_bold "completed_with_escalation" "feature/example")"
run_wrapper "$WD" "feature/example" "$FIXTURE"
# Terminal-status fail-close must work for the bold form too (mirrors the lowercase
# completed_with_escalation terminal case): a finished/escalated session must not re-dispatch.
if [ "$RUN_RC" -eq 0 ] && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "bold-status-completed_with_escalation: exit 0, no dispatch (terminal fail-close in bold form)"
else
  no "bold-status-completed_with_escalation wrong (rc=$RUN_RC markers=$(marker_count "$WD") out='$RUN_OUT')"
fi
rm -rf "$WD"

echo "== AC4. opt-out (.auto_review:false) -> no-op, 0 markers (dispatcher honors opt-out) =="
WD="$(make_wd "running" "feature/example")"
printf '{"auto_review": false}\n' > "$WD/.supervisor/config.json"
run_wrapper "$WD" "feature/example" "$FIXTURE"
if [ "$RUN_RC" -eq 0 ] && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "opt-out: exit 0, dispatcher suppressed, no marker"
else
  no "opt-out wrong (rc=$RUN_RC markers=$(marker_count "$WD") out='$RUN_OUT')"
fi
rm -rf "$WD"

echo "== AC6. malformed JSON stdin -> rc 0, 0 markers =="
WD="$(make_wd "running" "feature/example")"
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
WD="$(make_wd "running" "feature/example")"
P="$TMP_PAYLOADS/empty.txt"
: > "$P"
run_wrapper "$WD" "feature/example" "$P"
if [ "$RUN_RC" -eq 0 ] && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "empty: exit 0, no dispatch"
else
  no "empty wrong (rc=$RUN_RC markers=$(marker_count "$WD") out='$RUN_OUT')"
fi
rm -rf "$WD"

echo "== AC6. non-Bash tool_name (e.g. 'Read') -> no-op, 0 markers (matcher-defensive) =="
WD="$(make_wd "running" "feature/example")"
P="$TMP_PAYLOADS/non-bash.json"
# Even a gate-passing fixture must no-op when the tool is not Bash (the wrapper's
# TOOL_NAME != "Bash" early return — defends the matcher:"Bash" registration).
jq '.tool_name="Read"' "$FIXTURE" > "$P"
run_wrapper "$WD" "feature/example" "$P"
if [ "$RUN_RC" -eq 0 ] && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "non-Bash: exit 0, no dispatch"
else
  no "non-Bash wrong (rc=$RUN_RC markers=$(marker_count "$WD") out='$RUN_OUT')"
fi
rm -rf "$WD"

echo "== AC6. jq absent on PATH -> rc 0, 0 markers (fail-safe missing-jq branch) =="
# Build a minimal bin dir with symlinks to everything the wrapper touches BEFORE
# the `command -v jq` check (cat, plus dirname/cd/pwd for SCRIPT_DIR) but NOT jq,
# then run the wrapper with PATH pointed only at it so `command -v jq` fails and
# the wrapper hits its missing-jq exit-0 branch. We do NOT use run_wrapper here
# (it would inherit the harness PATH that still has jq).
NOJQ_BIN="$(mktemp -d)"
for b in bash cat dirname pwd; do
  src="$(command -v "$b" 2>/dev/null || true)"
  [ -n "$src" ] && ln -s "$src" "$NOJQ_BIN/$b"
done
WD="$(make_wd "running" "feature/example")"
RUN_OUT="$( cd "$WD" && AI_AGENT_MANAGER_REVIEW_DISPATCH_DRY_RUN=1 \
    AI_AGENT_MANAGER_HOOK_CURRENT_BRANCH="feature/example" \
    PATH="$NOJQ_BIN" "$NOJQ_BIN/bash" "$WRAPPER" < "$FIXTURE" 2>/dev/null )"
RUN_RC=$?
# The wrapper's missing-jq branch exits 0 BEFORE writing any marker; assert both.
if [ "$RUN_RC" -eq 0 ] && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "jq-absent: exit 0, no dispatch (missing-jq fail-safe branch)"
else
  no "jq-absent wrong (rc=$RUN_RC markers=$(marker_count "$WD") out='$RUN_OUT')"
fi
rm -rf "$WD" "$NOJQ_BIN"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
