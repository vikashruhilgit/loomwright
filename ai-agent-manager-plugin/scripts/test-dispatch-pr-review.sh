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
#   1. disabled-by-default no-op (no config, no flag) -> no marker, exit 0.
#   2. missing-config graceful exit 0 (no config file at all) -> no marker.
#   3. config auto_review:true -> dispatch (DRY_RUN line emitted, marker written).
#   4. --auto-review flag -> dispatch even without config.
#   5. marker-prevents-re-dispatch: 2nd call on same PR -> no new dispatch.
#   6. --no-auto-review suppression wins even with config auto_review:true.
#   7. --auto-review + --no-auto-review -> suppression wins (no dispatch).
#   8. missing PR url -> graceful no-op, exit 0.

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

echo "== 1. disabled by default (no config, no flag) -> no-op =="
WD="$(fresh_repo)"
run_dispatch "$WD" "$PR"
if [ "$RUN_RC" -eq 0 ] && ! printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "disabled-by-default: exit 0, no dispatch, no marker"
else
  no "disabled-by-default wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 2. missing config file -> graceful exit 0, no dispatch =="
WD="$(mktemp -d)"   # NO .supervisor at all
run_dispatch "$WD" "$PR"
if [ "$RUN_RC" -eq 0 ] && ! printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH'; then
  ok "missing-config: exit 0, no dispatch"
else
  no "missing-config wrong (rc=$RUN_RC out='$RUN_OUT')"
fi
rm -rf "$WD"

echo "== 3. config auto_review:true -> dispatch =="
WD="$(fresh_repo)"
printf '{"auto_review": true}\n' > "$WD/.supervisor/notify-config.json"
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
printf '{"auto_review": true}\n' > "$WD/.supervisor/notify-config.json"
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
printf '{"auto_review": true}\n' > "$WD/.supervisor/notify-config.json"
run_dispatch "$WD" "$PR" --no-auto-review
if [ "$RUN_RC" -eq 0 ] && ! printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "--no-auto-review: suppressed despite config, no dispatch, no marker"
else
  no "--no-auto-review wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
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
printf '{"auto_review": true}\n' > "$WD/.supervisor/notify-config.json"
run_dispatch "$WD" --auto-review            # enabled, but no PR url
if [ "$RUN_RC" -eq 0 ] && ! printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "missing-pr-url: exit 0, no dispatch"
else
  no "missing-pr-url wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
