#!/usr/bin/env bash
# test-pr-postmortem-gather.sh — self-tests for the READ-ONLY PR gatherer
# (pr-postmortem-gather.sh, Subtask 1 of /pr-postmortem). Mirrors the house
# convention (test-run-ground-truth.sh / test-dispatch-pr-review.sh): isolated
# temp CWD, deterministic, NO real network. Exit 0 = all pass, 1 = any failure.
# Prints "RESULT: N passed, M failed". UNCOUNTED by the doc-currency gate (test-*.sh).
#
# The gatherer's ALWAYS-exit-0 invariant means every case also asserts rc == 0;
# the behavioral assertion is the SHAPE of the emitted JSON.
#
# Live `gh` is NEVER called: a stub `gh` is placed earlier on PATH inside a temp
# bindir. The stub emits canned `gh pr view ... --json ...` JSON from a heredoc, so
# the gatherer's single gh round-trip is fully deterministic and offline.
#
# Covers:
#   1. happy path  -> valid JSON, expected keys (repo,number,commits,review_rounds,
#                     ci_checks), NO `status` field, exit 0.
#   2. short-form input OWNER/REPO#N -> same happy shape, exit 0.
#   3. heuristics  -> agent_generated_guess true, is_review_fix true on the churn
#                     commit, review_rounds reflects the signal.
#   4. injection-safety -> a title/body/review body with quotes/backslashes/newlines
#                     round-trips as valid JSON (no parse break).
#   5. unavailable (stub gh fails / PR inaccessible) -> {"status":"unavailable",...}, exit 0.
#   6. bad input   -> {"status":"unavailable","reason":"bad_input"}, exit 0.
#   7. missing gh  -> {"status":"unavailable","reason":"gh_unavailable"}, exit 0.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
GATHER="$HERE/pr-postmortem-gather.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "test-pr-postmortem-gather: jq not available — cannot exercise the gatherer; skipping (treated as pass)."
  echo; echo "RESULT: 0 passed, 0 failed"; exit 0
fi

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

BIN="$TMP/bin"
mkdir -p "$BIN"

# Write the two PR fixtures to files using FULLY-QUOTED heredocs ('FIX'), so the
# shell performs no expansion — backslash escapes (\\, \") survive verbatim and the
# JSON stays valid. (A nested heredoc inside an unquoted outer heredoc would let the
# outer shell collapse \\ -> \ and corrupt the JSON, so we keep fixtures in files.)
FIX_OK="$TMP/fixture-ok.json"
FIX_INJECT="$TMP/fixture-inject.json"

cat > "$FIX_OK" <<'FIX'
{
  "number": 42,
  "title": "Add JWT guard",
  "body": "Implements the guard.\n\n🤖 Generated with Claude Code",
  "additions": 120,
  "deletions": 30,
  "changedFiles": 5,
  "commits": [
    {"messageHeadline": "feat: add JWT guard"},
    {"messageHeadline": "fix: address review feedback"}
  ],
  "reviews": [
    {"author": {"login": "alice"}, "body": "please rename this", "submittedAt": "2026-01-01T10:00:00Z"},
    {"author": {"login": "bob"}, "body": "LGTM after fix", "submittedAt": "2026-01-02T11:00:00Z"}
  ],
  "statusCheckRollup": [
    {"name": "ci/test", "state": "SUCCESS"},
    {"name": "lint", "state": "FAILURE"}
  ]
}
FIX

cat > "$FIX_INJECT" <<'FIX'
{
  "number": 42,
  "title": "Add \"auth\" guard \\ fix",
  "body": "line one\nGenerated with Claude Code\nbackslash \\ and \"quote\"",
  "additions": 10,
  "deletions": 2,
  "changedFiles": 3,
  "commits": [
    {"messageHeadline": "feat: add guard"}
  ],
  "reviews": [
    {"author": {"login": "rev\"er"}, "body": "needs a \"fix\" here\nsecond line", "submittedAt": "2026-01-01T00:00:00Z"}
  ],
  "statusCheckRollup": [
    {"name": "ci/test", "state": "SUCCESS"}
  ]
}
FIX

# make_gh_stub <mode> — write a fake `gh` to $BIN that, for `pr view`, cats the
# fixture file for <mode>; for any other args exits 0. The stub body is tiny and
# carries NO embedded JSON (the JSON lives in the files above), so the unquoted
# outer heredoc cannot corrupt any escapes. <mode>:
#   ok        — rich happy-path PR (agent-generated, one review-fix commit, 2 reviews, CI).
#   inject    — title/body/review carrying quotes, backslashes, and a newline.
#   fail      — `pr view` exits 1 (simulates private/not-found/unauthenticated).
make_gh_stub() {
  local mode="$1" fixture=""
  case "$mode" in
    ok)     fixture="$FIX_OK" ;;
    inject) fixture="$FIX_INJECT" ;;
    fail)   fixture="" ;;
  esac
  cat > "$BIN/gh" <<STUB
#!/usr/bin/env bash
# fake gh — fixture mode: $mode
if [ "\${1:-}" = "pr" ] && [ "\${2:-}" = "view" ]; then
  if [ "$mode" = "fail" ]; then exit 1; fi
  cat "$fixture"
  exit 0
fi
exit 0
STUB
  chmod +x "$BIN/gh"
}

# run_gather <args...> — run the gatherer with $BIN ahead of PATH (stub gh wins).
# Captures stdout in RUN_OUT, rc in RUN_RC.
run_gather() {
  RUN_OUT="$( PATH="$BIN:$PATH" bash "$GATHER" "$@" 2>/dev/null )"
  RUN_RC=$?
}

PR_URL="https://github.com/acme/widgets/pull/42"
PR_SHORT="acme/widgets#42"

echo "== 1. happy path => valid JSON, expected keys, no status, exit 0 =="
make_gh_stub ok
run_gather "$PR_URL"
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | jq -e '
    (has("status") | not)
    and .repo=="acme/widgets" and .number==42
    and (.commits | type=="array") and (.review_rounds | type=="number")
    and (.ci_checks | type=="array")
    and .additions==120 and .deletions==30 and .changed_files==5
  ' >/dev/null 2>&1; then
  ok "happy path: valid JSON with repo/number/commits/review_rounds/ci_checks, no status, exit 0"
else
  no "(1) wrong (rc=$RUN_RC): $RUN_OUT"
fi

echo "== 2. short-form OWNER/REPO#N => same happy shape, exit 0 =="
make_gh_stub ok
run_gather "$PR_SHORT"
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | jq -e '
    (has("status") | not) and .repo=="acme/widgets" and .number==42
  ' >/dev/null 2>&1; then
  ok "short form parsed: repo acme/widgets, number 42, exit 0"
else
  no "(2) wrong (rc=$RUN_RC): $RUN_OUT"
fi

echo "== 3. heuristics => agent_generated_guess true, is_review_fix true, review_rounds reflects signal =="
make_gh_stub ok
run_gather "$PR_URL"
if printf '%s' "$RUN_OUT" | jq -e '
    .agent_generated_guess==true
    and (.commits | length)==2
    and ([.commits[] | select(.is_review_fix)] | length)==1
    and (.commits[1].is_review_fix==true)
    and (.review_rounds >= 2)
    and (.review_comments | length)==2
    and (.ci_checks | length)==2
  ' >/dev/null 2>&1; then
  ok "heuristics: agent guess true, 1 review-fix commit, review_rounds>=2, 2 review_comments, 2 ci_checks"
else
  no "(3) wrong: $RUN_OUT"
fi

echo "== 4. injection-safety => quotes/backslashes/newlines round-trip as valid JSON =="
make_gh_stub inject
run_gather "$PR_URL"
# Must be valid JSON, must carry the agent guess from the body, and the snippet must
# have had its newline collapsed (control chars stripped) — no parse break.
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | jq -e '
    (has("status") | not)
    and (.title | test("auth"))
    and .agent_generated_guess==true
    and (.review_comments[0].snippet | test("\n") | not)
    and (.review_comments[0].author=="rev\"er")
  ' >/dev/null 2>&1; then
  ok "injection-safe: quotes/backslashes/newline round-trip, snippet de-newlined, valid JSON"
else
  no "(4) wrong (rc=$RUN_RC): $RUN_OUT"
fi

echo "== 5. unavailable (stub gh fails) => {\"status\":\"unavailable\",...}, exit 0 =="
make_gh_stub fail
run_gather "$PR_URL"
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | jq -e '
    .status=="unavailable" and (.reason | length > 0)
  ' >/dev/null 2>&1; then
  ok "gh failure => status unavailable (reason=$(printf '%s' "$RUN_OUT" | jq -r .reason)), exit 0"
else
  no "(5) wrong (rc=$RUN_RC): $RUN_OUT"
fi

echo "== 6. bad input => unavailable/bad_input, exit 0 =="
make_gh_stub ok
run_gather "this-is-not-a-pr-ref"
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | jq -e '
    .status=="unavailable" and .reason=="bad_input"
  ' >/dev/null 2>&1; then
  ok "bad input => status unavailable, reason bad_input, exit 0"
else
  no "(6) wrong (rc=$RUN_RC): $RUN_OUT"
fi

echo "== 6b. empty input => unavailable/bad_input, exit 0 =="
make_gh_stub ok
run_gather ""
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | jq -e '.status=="unavailable" and .reason=="bad_input"' >/dev/null 2>&1; then
  ok "empty input => status unavailable, reason bad_input, exit 0"
else
  no "(6b) wrong (rc=$RUN_RC): $RUN_OUT"
fi

echo "== 7. missing gh => unavailable/gh_unavailable, exit 0 =="
# Point GH_BIN at a command name that does not exist on PATH so the gatherer's
# `command -v "$GH_BIN"` check fails — exercising the gh-missing branch while jq
# (and bash/coreutils) stay reachable. Cleaner than mangling PATH (which would also
# hide bash and break the `bash "$GATHER"` launch itself).
RUN_OUT="$( GH_BIN="gh-does-not-exist-$$" bash "$GATHER" "$PR_URL" 2>/dev/null )"; RUN_RC=$?
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | jq -e '
    .status=="unavailable" and .reason=="gh_unavailable"
  ' >/dev/null 2>&1; then
  ok "missing gh => status unavailable, reason gh_unavailable, exit 0"
else
  no "(7) wrong (rc=$RUN_RC): $RUN_OUT"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
