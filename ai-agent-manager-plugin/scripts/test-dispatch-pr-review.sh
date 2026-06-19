#!/usr/bin/env bash
# test-dispatch-pr-review.sh — self-tests for the post-/supervisor auto-review
# dispatcher (review-heal). Runs in an isolated temp dir (never touches the real
# .supervisor/). Exit 0 = all pass, 1 = any failure. Mirrors test-twin-graph.sh
# convention. UNCOUNTED by the doc-currency gate (test-*.sh).
#
# The dispatcher's ALWAYS-exit-0 invariant means every case below also asserts
# rc == 0; the behavioral assertion is the gating SIDE EFFECT (did/didn't write a
# marker, did/didn't emit DRY_RUN_DISPATCH). The real `claude` process is NEVER
# launched: AI_AGENT_MANAGER_REVIEW_DISPATCH_DRY_RUN=1 short-circuits the launch
# path while still exercising all the gating + marker logic.
#
# Covers:
#   1. ENABLED-by-default dispatch (no config, no flag) -> marker + DRY_RUN, exit 0
#      (AC7 — the review drain now dispatches by default after PR creation).
#   2. missing-config dispatch (no config file at all) -> still dispatches (default ON).
#   3. config auto_review:true -> dispatch (DRY_RUN line emitted, marker written).
#   4. --auto-review flag -> dispatch even without config.
#   5. marker-prevents-re-dispatch: 2nd call on same PR -> no new dispatch.
#   6. --no-auto-review suppression wins even with config auto_review:true -> no dispatch.
#   6b. config auto_review:false suppresses the default-ON dispatch -> no dispatch.
#   7. --auto-review + --no-auto-review -> suppression wins (no dispatch).
#   8. missing PR url -> graceful no-op, exit 0.
#   9. launch-form contract: emitted command is headless `nohup claude -p --agent <runner> <url>`
#      (regression guard — `claude --agent <runner> "<prompt>"` WITHOUT -p starts an
#      interactive session that hangs when detached; --agent does NOT imply headless).
#  10. until-mergeable signal present BY DEFAULT (AC7): AI_AGENT_MANAGER_UNTIL_MERGEABLE=1
#      is exported into the dispatched invocation by default.
#  11. --no-until-mergeable opt-out: the signal env var is NOT set (plain diff-only run).
#  11b. config auto_until_mergeable:false opt-out: the signal env var is NOT set.
#  12. optional tuning forwarded only when set: --check-wait-timeout / --review-check-pattern
#      thread AI_AGENT_MANAGER_CHECK_WAIT_TIMEOUT / AI_AGENT_MANAGER_REVIEW_CHECK_PATTERN.
#  13. real-launch RUN_LOG header: a stubbed-claude (non-dry-run) launch writes a
#      synchronous, non-empty, self-documenting header (DISPATCHED + url + until_mergeable)
#      BEFORE detaching — so an in-flight drain no longer looks like a 0-byte no-op.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DISPATCH="$HERE/dispatch-pr-review.sh"

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

# run_dispatch <workdir> <args...> — run the dispatcher in DRY_RUN mode from
# inside <workdir>. Captures stdout in RUN_OUT, rc in RUN_RC.
run_dispatch() {
  local wd="$1"; shift
  RUN_OUT="$( cd "$wd" && AI_AGENT_MANAGER_REVIEW_DISPATCH_DRY_RUN=1 bash "$DISPATCH" "$@" 2>/dev/null )"
  RUN_RC=$?
}

# marker_count <workdir> — number of marker files written under review-dispatch.
marker_count() {
  local wd="$1"
  ls -1 "$wd/.supervisor/review-dispatch" 2>/dev/null | grep -c . || true
}

echo "== 1. ENABLED by default (no config, no flag) -> dispatch (AC7) =="
WD="$(fresh_repo)"
run_dispatch "$WD" "$PR"
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 1 ]; then
  ok "enabled-by-default: exit 0, dispatch emitted, 1 marker"
else
  no "enabled-by-default wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 2. missing config file -> still dispatches (default ON), exit 0 =="
WD="$(mktemp -d)"   # NO .supervisor at all
run_dispatch "$WD" "$PR"
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH'; then
  ok "missing-config: exit 0, dispatch emitted (default ON)"
else
  no "missing-config wrong (rc=$RUN_RC out='$RUN_OUT')"
fi
rm -rf "$WD"

echo "== 3. config auto_review:true -> dispatch =="
WD="$(fresh_repo)"
printf '{"auto_review": true}\n' > "$WD/.supervisor/config.json"
run_dispatch "$WD" "$PR"
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 1 ]; then
  ok "config-enabled: dispatch emitted + 1 marker written"
else
  no "config-enabled wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 4. --auto-review flag (no config) -> dispatch =="
WD="$(fresh_repo)"
run_dispatch "$WD" "$PR" --auto-review
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 1 ]; then
  ok "--auto-review: dispatch emitted + marker written without config"
else
  no "--auto-review wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 5. marker prevents re-dispatch (same PR twice) =="
WD="$(fresh_repo)"
printf '{"auto_review": true}\n' > "$WD/.supervisor/config.json"
run_dispatch "$WD" "$PR"                       # first dispatch
FIRST_RC=$RUN_RC
run_dispatch "$WD" "$PR"                        # second call, same PR
if [ "$FIRST_RC" -eq 0 ] && [ "$RUN_RC" -eq 0 ] \
   && ! printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' \
   && [ "$(marker_count "$WD")" -eq 1 ]; then
  ok "re-dispatch blocked: 2nd call no-op, still exactly 1 marker"
else
  no "re-dispatch guard wrong (2nd rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
# sanity: a DIFFERENT PR still dispatches (marker is per-PR)
run_dispatch "$WD" "$PR2"
if printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 2 ]; then
  ok "different PR dispatches independently (2 markers)"
else
  no "per-PR marker keying wrong (out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 6. --no-auto-review suppresses even with config auto_review:true =="
WD="$(fresh_repo)"
printf '{"auto_review": true}\n' > "$WD/.supervisor/config.json"
run_dispatch "$WD" "$PR" --no-auto-review
if [ "$RUN_RC" -eq 0 ] && ! printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "--no-auto-review: suppressed despite config, no dispatch, no marker"
else
  no "--no-auto-review wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 6b. config auto_review:false suppresses the default-ON dispatch =="
WD="$(fresh_repo)"
printf '{"auto_review": false}\n' > "$WD/.supervisor/config.json"
run_dispatch "$WD" "$PR"          # no flag — config false must suppress the default ON
if [ "$RUN_RC" -eq 0 ] && ! printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "config auto_review:false: suppressed despite default-ON, no dispatch, no marker"
else
  no "config-false-suppress wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 6c. legacy-path fallback: ONLY .supervisor/notify-config.json present -> read unchanged (AC1) =="
WD="$(fresh_repo)"
# Back-compat: an old install with ONLY the legacy file must still be read. Here
# the legacy file opts out via auto_review:false; if the legacy path were ignored
# the default-ON dispatch would fire (marker written). Suppression proves fallback.
printf '{"auto_review": false}\n' > "$WD/.supervisor/notify-config.json"
run_dispatch "$WD" "$PR"
if [ "$RUN_RC" -eq 0 ] && ! printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "legacy-fallback: legacy notify-config.json honored (suppressed), no dispatch, no marker"
else
  no "legacy-fallback wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 6d. both files present -> new .supervisor/config.json wins (AC2) =="
WD="$(fresh_repo)"
# New file opts out (auto_review:false); legacy file would enable (auto_review:true).
# If new-wins holds, the dispatch is suppressed (legacy true is ignored).
printf '{"auto_review": false}\n' > "$WD/.supervisor/config.json"
printf '{"auto_review": true}\n'  > "$WD/.supervisor/notify-config.json"
run_dispatch "$WD" "$PR"
if [ "$RUN_RC" -eq 0 ] && ! printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "both-present: new config.json wins (suppressed), legacy true ignored"
else
  no "both-present wrong — new file should win (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 7. --no-auto-review beats --auto-review (suppress wins) =="
WD="$(fresh_repo)"
run_dispatch "$WD" "$PR" --auto-review --no-auto-review
if [ "$RUN_RC" -eq 0 ] && ! printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "suppress beats force: no dispatch"
else
  no "suppress-vs-force wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 8. missing PR url -> graceful no-op =="
WD="$(fresh_repo)"
printf '{"auto_review": true}\n' > "$WD/.supervisor/config.json"
run_dispatch "$WD" --auto-review            # enabled, but no PR url
if [ "$RUN_RC" -eq 0 ] && ! printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "missing-pr-url: exit 0, no dispatch"
else
  no "missing-pr-url wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 9. launch-form contract: headless 'nohup claude -p --agent <runner> <url>' (regression guard for the interactive-session bug) =="
WD="$(fresh_repo)"
run_dispatch "$WD" "$PR"          # default dispatch so the form is emitted
LINE="$(printf '%s' "$RUN_OUT" | grep 'DRY_RUN_DISPATCH' || true)"
# Must be the --agent runner form: headless (-p present) AND select the review-pr-runner
# agent AND carry the PR url AND NOT be a /review-pr slash string (the 11.1.1 spawn-depth
# trap). `claude --agent <runner> "<prompt>"` WITHOUT -p starts an interactive session
# (--agent only selects the agent, it does NOT switch to headless) that hangs when detached.
if [ "$RUN_RC" -eq 0 ] \
   && printf '%s' "$LINE" | grep -Eq '(^| )-p( |$)|(^| )--print( |$)' \
   && printf '%s' "$LINE" | grep -q -- '--agent ai-agent-manager-plugin:review-pr-runner' \
   && printf '%s' "$LINE" | grep -q -- "$PR" \
   && ! printf '%s' "$LINE" | grep -q -- '/review-pr'; then
  ok "launch-form: headless -p + --agent <runner> + <url>, no slash string ($LINE)"
else
  no "launch-form wrong (missing -p / --agent <runner> / url, or a /review-pr slash present) (line='$LINE')"
fi
rm -rf "$WD"

echo "== 10. until-mergeable signal present BY DEFAULT (AC7) =="
WD="$(fresh_repo)"
run_dispatch "$WD" "$PR"          # no flag — until-mergeable must be ON by default
LINE="$(printf '%s' "$RUN_OUT" | grep 'DRY_RUN_DISPATCH' || true)"
if [ "$RUN_RC" -eq 0 ] \
   && printf '%s' "$LINE" | grep -q -- 'AI_AGENT_MANAGER_UNTIL_MERGEABLE=1'; then
  ok "default until-mergeable: AI_AGENT_MANAGER_UNTIL_MERGEABLE=1 present ($LINE)"
else
  no "default until-mergeable signal missing (line='$LINE')"
fi
rm -rf "$WD"

echo "== 11. --no-until-mergeable opt-out: signal env var NOT set =="
WD="$(fresh_repo)"
run_dispatch "$WD" "$PR" --no-until-mergeable
LINE="$(printf '%s' "$RUN_OUT" | grep 'DRY_RUN_DISPATCH' || true)"
# Dispatch still fires (auto-review default ON) but WITHOUT the until-mergeable signal.
if [ "$RUN_RC" -eq 0 ] \
   && printf '%s' "$LINE" | grep -q 'DRY_RUN_DISPATCH' \
   && ! printf '%s' "$LINE" | grep -q -- 'AI_AGENT_MANAGER_UNTIL_MERGEABLE'; then
  ok "--no-until-mergeable: dispatch fires, signal NOT set ($LINE)"
else
  no "--no-until-mergeable wrong (signal should be absent) (line='$LINE')"
fi
rm -rf "$WD"

echo "== 11b. config auto_until_mergeable:false opt-out: signal env var NOT set =="
WD="$(fresh_repo)"
printf '{"auto_until_mergeable": false}\n' > "$WD/.supervisor/config.json"
run_dispatch "$WD" "$PR"          # no flag — config opts out of until-mergeable only
LINE="$(printf '%s' "$RUN_OUT" | grep 'DRY_RUN_DISPATCH' || true)"
if [ "$RUN_RC" -eq 0 ] \
   && printf '%s' "$LINE" | grep -q 'DRY_RUN_DISPATCH' \
   && ! printf '%s' "$LINE" | grep -q -- 'AI_AGENT_MANAGER_UNTIL_MERGEABLE'; then
  ok "config auto_until_mergeable:false: dispatch fires, signal NOT set ($LINE)"
else
  no "config-until-mergeable-false wrong (signal should be absent) (line='$LINE')"
fi
rm -rf "$WD"

echo "== 12. optional tuning forwarded only when set (timeout + pattern) =="
WD="$(fresh_repo)"
run_dispatch "$WD" "$PR" --check-wait-timeout 300 --review-check-pattern 'claude*'
LINE="$(printf '%s' "$RUN_OUT" | grep 'DRY_RUN_DISPATCH' || true)"
if [ "$RUN_RC" -eq 0 ] \
   && printf '%s' "$LINE" | grep -q -- 'AI_AGENT_MANAGER_UNTIL_MERGEABLE=1' \
   && printf '%s' "$LINE" | grep -q -- 'AI_AGENT_MANAGER_CHECK_WAIT_TIMEOUT=300' \
   && printf '%s' "$LINE" | grep -q -- 'AI_AGENT_MANAGER_REVIEW_CHECK_PATTERN=claude\*'; then
  ok "tuning forwarded: timeout + pattern present ($LINE)"
else
  no "tuning forwarding wrong (line='$LINE')"
fi
# sanity: tuning vars ABSENT by default (only forwarded when set)
WD2="$(fresh_repo)"
run_dispatch "$WD2" "$PR"
LINE2="$(printf '%s' "$RUN_OUT" | grep 'DRY_RUN_DISPATCH' || true)"
if ! printf '%s' "$LINE2" | grep -q -- 'AI_AGENT_MANAGER_CHECK_WAIT_TIMEOUT' \
   && ! printf '%s' "$LINE2" | grep -q -- 'AI_AGENT_MANAGER_REVIEW_CHECK_PATTERN'; then
  ok "tuning absent by default (only forwarded when set) ($LINE2)"
else
  no "tuning leaked when unset (line='$LINE2')"
fi
rm -rf "$WD" "$WD2"

echo "== 13. real-launch RUN_LOG header: synchronous, non-empty, self-documenting (0-byte-log fix) =="
# NOT dry-run: exercise the actual launch path with a stub `claude` (via
# AI_AGENT_MANAGER_CLAUDE_BIN) so the synchronous RUN_LOG header is written. The
# header is emitted BEFORE the detached launch, so it is present regardless of what
# the stub does — proving an in-flight drain no longer looks like a 0-byte no-op.
WD="$(fresh_repo)"
STUB="$WD/stub-claude"
printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB"
chmod +x "$STUB"
( cd "$WD" && AI_AGENT_MANAGER_CLAUDE_BIN="$STUB" bash "$DISPATCH" "$PR" >/dev/null 2>&1 )
RC13=$?
HDR="$(cat "$WD"/.supervisor/logs/review-pr-dispatch-*.log 2>/dev/null || true)"
if [ "$RC13" -eq 0 ] \
   && [ -n "$HDR" ] \
   && printf '%s' "$HDR" | grep -q 'DISPATCHED' \
   && printf '%s' "$HDR" | grep -q -- 'until_mergeable=1' \
   && printf '%s' "$HDR" | grep -qF "url=$PR"; then
  ok "real-launch RUN_LOG header present + greppable (DISPATCHED + until_mergeable=1 + url)"
else
  no "real-launch RUN_LOG header missing/wrong (rc=$RC13 hdr='$HDR')"
fi
# opt-out path: header records until_mergeable=0 (drain dispatched plain diff-only)
WD2="$(fresh_repo)"
STUB2="$WD2/stub-claude"
printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB2"
chmod +x "$STUB2"
( cd "$WD2" && AI_AGENT_MANAGER_CLAUDE_BIN="$STUB2" bash "$DISPATCH" "$PR" --no-until-mergeable >/dev/null 2>&1 )
HDR2="$(cat "$WD2"/.supervisor/logs/review-pr-dispatch-*.log 2>/dev/null || true)"
if printf '%s' "$HDR2" | grep -q 'DISPATCHED' && printf '%s' "$HDR2" | grep -q -- 'until_mergeable=0'; then
  ok "opt-out header records until_mergeable=0"
else
  no "opt-out header wrong (hdr='$HDR2')"
fi
rm -rf "$WD" "$WD2"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
