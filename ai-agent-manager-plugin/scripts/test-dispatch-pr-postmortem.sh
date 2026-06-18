#!/usr/bin/env bash
# test-dispatch-pr-postmortem.sh — self-tests for the churn-gated auto-postmortem
# dispatcher (review-heal). Runs in an isolated temp dir (never touches the real
# .supervisor/). Exit 0 = all pass, 1 = any failure. Mirrors test-dispatch-pr-review.sh
# convention. UNCOUNTED by the doc-currency gate (test-*.sh).
#
# The dispatcher's ALWAYS-exit-0 invariant (AC12) means every case below also asserts
# rc == 0; the behavioral assertion is the gating SIDE EFFECT (did/didn't write a
# marker, did/didn't emit DRY_RUN_DISPATCH). The real `claude` process is NEVER
# launched: AI_AGENT_MANAGER_POSTMORTEM_DISPATCH_DRY_RUN=1 short-circuits the launch
# path while still exercising all the gating + marker logic.
#
# Covers:
#   1.  clean PR (no churn triggers) -> no dispatch, exit 0 (AC9 no-op).
#   2.  fix_cycles > threshold -> dispatch (AC10/AC11).
#   3.  fix_cycles == threshold (default 2) -> no dispatch (boundary, AC9/AC11).
#   4.  decision == ESCALATED -> dispatch even with low fix_cycles (AC10).
#   5.  --repeat-check-failure -> dispatch (AC10).
#   6.  --unresolved-bot-feedback -> dispatch (AC10).
#   7.  --no-auto-postmortem suppresses even on heavy churn (AC13).
#   8.  config auto_postmortem:false suppresses even on heavy churn (AC13).
#   9.  configurable threshold: config .postmortem_churn_threshold raises the bar (AC11).
#   10. --postmortem-churn-threshold flag overrides config + default (AC11).
#   11. marker prevents re-dispatch (same PR twice); a different PR dispatches.
#   12. missing PR url -> graceful no-op, exit 0.
#   13. launch-form contract: emitted command is headless AND NAMESPACED
#       `claude -p "/ai-agent-manager-plugin:pr-postmortem <url>"` — two regression guards:
#       (a) bare `/pr-postmortem` (no namespace) is "Unknown command" under detached `claude -p`
#           (the PR #67 bug — bare plugin slash commands don't resolve in headless print mode);
#       (b) plain `claude "<prompt>"` without -p opens an interactive REPL that hangs when
#           detached (F2 review fix).
#   14. claude binary absent -> fail-safe no-op (non-dry-run; exit 0, no marker, no launch)
#       — exercises the binary-absent fallback the dry-run cases never reach.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DISPATCH="$HERE/dispatch-pr-postmortem.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

PR="https://github.com/acme/widgets/pull/42"
PR2="https://github.com/acme/widgets/pull/99"

# fresh_repo — make an isolated temp working dir with a .supervisor/ skeleton.
fresh_repo() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/.supervisor"
  printf '%s' "$d"
}

# run_dispatch <workdir> <args...> — run the dispatcher in DRY_RUN mode from inside
# <workdir>. Captures stdout in RUN_OUT, rc in RUN_RC.
run_dispatch() {
  local wd="$1"; shift
  RUN_OUT="$( cd "$wd" && AI_AGENT_MANAGER_POSTMORTEM_DISPATCH_DRY_RUN=1 bash "$DISPATCH" "$@" 2>/dev/null )"
  RUN_RC=$?
}

# marker_count <workdir> — number of marker files written under postmortem-dispatch.
marker_count() {
  local wd="$1"
  ls -1 "$wd/.supervisor/postmortem-dispatch" 2>/dev/null | grep -c . || true
}

echo "== 1. clean PR (no churn triggers) -> no-op (AC9) =="
WD="$(fresh_repo)"
run_dispatch "$WD" "$PR" --fix-cycles 1 --decision READY
if [ "$RUN_RC" -eq 0 ] && ! printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "clean-PR: exit 0, no dispatch, no marker"
else
  no "clean-PR wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 2. fix_cycles > threshold -> dispatch (AC10/AC11) =="
WD="$(fresh_repo)"
run_dispatch "$WD" "$PR" --fix-cycles 3 --decision PASS
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 1 ]; then
  ok "fix-cycles-over-threshold: dispatch emitted + 1 marker written"
else
  no "fix-cycles-over-threshold wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 3. fix_cycles == default threshold (2) -> no dispatch (boundary) =="
WD="$(fresh_repo)"
run_dispatch "$WD" "$PR" --fix-cycles 2 --decision PASS
if [ "$RUN_RC" -eq 0 ] && ! printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "boundary: fix_cycles==threshold does NOT dispatch (> not >=)"
else
  no "boundary wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 4. decision == ESCALATED -> dispatch despite low fix_cycles (AC10) =="
WD="$(fresh_repo)"
run_dispatch "$WD" "$PR" --fix-cycles 0 --decision ESCALATED
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 1 ]; then
  ok "escalated: dispatch emitted even with fix_cycles=0"
else
  no "escalated wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 5. --repeat-check-failure -> dispatch (AC10) =="
WD="$(fresh_repo)"
run_dispatch "$WD" "$PR" --fix-cycles 1 --decision PASS --repeat-check-failure
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 1 ]; then
  ok "repeat-check-failure: dispatch emitted"
else
  no "repeat-check-failure wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 6. --unresolved-bot-feedback -> dispatch (AC10) =="
WD="$(fresh_repo)"
run_dispatch "$WD" "$PR" --fix-cycles 1 --decision PASS --unresolved-bot-feedback
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 1 ]; then
  ok "unresolved-bot-feedback: dispatch emitted"
else
  no "unresolved-bot-feedback wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 7. --no-auto-postmortem suppresses even on heavy churn (AC13) =="
WD="$(fresh_repo)"
run_dispatch "$WD" "$PR" --fix-cycles 9 --decision ESCALATED --no-auto-postmortem
if [ "$RUN_RC" -eq 0 ] && ! printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "--no-auto-postmortem: suppressed despite heavy churn, no dispatch, no marker"
else
  no "--no-auto-postmortem wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 8. config auto_postmortem:false suppresses even on heavy churn (AC13) =="
WD="$(fresh_repo)"
printf '{"auto_postmortem": false}\n' > "$WD/.supervisor/config.json"
run_dispatch "$WD" "$PR" --fix-cycles 9 --decision ESCALATED
if [ "$RUN_RC" -eq 0 ] && ! printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "config auto_postmortem:false: suppressed despite heavy churn"
else
  no "config-opt-out wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 8b. legacy-path fallback: ONLY .supervisor/notify-config.json present -> read unchanged (AC1) =="
WD="$(fresh_repo)"
# Back-compat: an old install with ONLY the legacy file must still be read. The
# legacy file opts out via auto_postmortem:false; heavy churn would otherwise
# dispatch. Suppression proves the legacy fallback path is honored.
printf '{"auto_postmortem": false}\n' > "$WD/.supervisor/notify-config.json"
run_dispatch "$WD" "$PR" --fix-cycles 9 --decision ESCALATED
if [ "$RUN_RC" -eq 0 ] && ! printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "legacy-fallback: legacy notify-config.json honored (suppressed despite heavy churn)"
else
  no "legacy-fallback wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 8c. both files present -> new .supervisor/config.json wins (AC2) =="
WD="$(fresh_repo)"
# New file opts out (auto_postmortem:false); legacy file does NOT opt out
# (auto_postmortem:true). If new-wins holds, heavy churn is suppressed.
printf '{"auto_postmortem": false}\n' > "$WD/.supervisor/config.json"
printf '{"auto_postmortem": true}\n'  > "$WD/.supervisor/notify-config.json"
run_dispatch "$WD" "$PR" --fix-cycles 9 --decision ESCALATED
if [ "$RUN_RC" -eq 0 ] && ! printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "both-present: new config.json wins (suppressed), legacy true ignored"
else
  no "both-present wrong — new file should win (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 9. configurable threshold via config raises the bar (AC11) =="
WD="$(fresh_repo)"
printf '{"postmortem_churn_threshold": 5}\n' > "$WD/.supervisor/config.json"
run_dispatch "$WD" "$PR" --fix-cycles 3 --decision PASS    # 3 > default 2 but not > 5
if [ "$RUN_RC" -eq 0 ] && ! printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "config threshold 5: fix_cycles=3 below raised bar, no dispatch"
else
  no "config-threshold (below) wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
# now exceed the raised bar
run_dispatch "$WD" "$PR" --fix-cycles 6 --decision PASS    # 6 > 5
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 1 ]; then
  ok "config threshold 5: fix_cycles=6 exceeds raised bar, dispatch emitted"
else
  no "config-threshold (above) wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 10. --postmortem-churn-threshold flag overrides config + default (AC11) =="
WD="$(fresh_repo)"
printf '{"postmortem_churn_threshold": 5}\n' > "$WD/.supervisor/config.json"
run_dispatch "$WD" "$PR" --fix-cycles 2 --decision PASS --postmortem-churn-threshold 1   # 2 > 1 (flag beats config 5)
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 1 ]; then
  ok "--postmortem-churn-threshold 1: overrides config 5, fix_cycles=2 trips, dispatch emitted"
else
  no "flag-threshold-override wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 11. marker prevents re-dispatch (same PR twice) =="
WD="$(fresh_repo)"
run_dispatch "$WD" "$PR" --fix-cycles 3 --decision PASS          # first dispatch
FIRST_RC=$RUN_RC
run_dispatch "$WD" "$PR" --fix-cycles 3 --decision PASS          # second call, same PR
if [ "$FIRST_RC" -eq 0 ] && [ "$RUN_RC" -eq 0 ] \
   && ! printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' \
   && [ "$(marker_count "$WD")" -eq 1 ]; then
  ok "re-dispatch blocked: 2nd call no-op, still exactly 1 marker"
else
  no "re-dispatch guard wrong (2nd rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
# sanity: a DIFFERENT PR still dispatches (marker is per-PR)
run_dispatch "$WD" "$PR2" --fix-cycles 3 --decision PASS
if printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 2 ]; then
  ok "different PR dispatches independently (2 markers)"
else
  no "per-PR marker keying wrong (out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 12. missing PR url -> graceful no-op =="
WD="$(fresh_repo)"
run_dispatch "$WD" --fix-cycles 9 --decision ESCALATED          # heavy churn, but no PR url
if [ "$RUN_RC" -eq 0 ] && ! printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "missing-pr-url: exit 0, no dispatch"
else
  no "missing-pr-url wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 13. launch-form contract: headless NAMESPACED 'claude -p \"/ai-agent-manager-plugin:pr-postmortem <url>\"' (regression guards: bare-slash-command Unknown-command bug + interactive-REPL bug) =="
WD="$(fresh_repo)"
run_dispatch "$WD" "$PR" --fix-cycles 9 --decision ESCALATED          # force a dispatch so the form is emitted
LINE="$(printf '%s' "$RUN_OUT" | grep 'DRY_RUN_DISPATCH' || true)"
# Must be headless (-p present) AND invoke the NAMESPACED slash command with the PR url. Two
# regressions guarded: (a) bare `/pr-postmortem` is "Unknown command" under detached `claude -p`
# (the PR #67 bug); (b) plain `claude "<prompt>"` (no -p) opens an interactive REPL that hangs
# when detached. The namespaced match also fails the bare form: bare emits `"/pr-postmortem `
# (a `/` before the name) whereas the required form has `:pr-postmortem` (a `:` before it).
if [ "$RUN_RC" -eq 0 ] \
   && printf '%s' "$LINE" | grep -Eq '(^| )-p( |$)|(^| )--print( |$)' \
   && printf '%s' "$LINE" | grep -q "/ai-agent-manager-plugin:pr-postmortem $PR"; then
  ok "launch-form: headless -p + namespaced /ai-agent-manager-plugin:pr-postmortem <url> ($LINE)"
else
  no "launch-form missing -p or namespaced slash command (line='$LINE')"
fi
rm -rf "$WD"

echo "== 14. claude binary absent -> fail-safe no-op (NOT dry-run; exit 0, no marker, no launch) =="
WD="$(fresh_repo)"
# Real (non-dry-run) path with a claude binary that does not exist: the churn gate trips
# (heavy churn) but the 'claude not on PATH' check must exit 0 WITHOUT writing a marker or
# launching anything — so a later run that DOES have claude can still dispatch (marker not
# pre-consumed). Exercises the binary-absent fallback the dry-run cases never reach.
RUN_OUT="$( cd "$WD" && AI_AGENT_MANAGER_CLAUDE_BIN=claude-does-not-exist-xyz bash "$DISPATCH" "$PR" --fix-cycles 9 --decision ESCALATED 2>/dev/null )"; RUN_RC=$?
if [ "$RUN_RC" -eq 0 ] && ! printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "claude-absent: exit 0, no marker, no dispatch (fail-safe)"
else
  no "claude-absent fallback wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
