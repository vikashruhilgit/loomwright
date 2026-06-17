#!/usr/bin/env bash
# test-classify-bot-review.sh — self-tests for classify-bot-review.sh, the SINGLE
# SOURCE OF TRUTH for bot-authored review-comment classification. Mirrors the house
# convention (test-pr-postmortem-gather.sh): deterministic, NO real network, isolated
# temp fixtures. Exit 0 = all pass, 1 = any failure. Prints "RESULT: N passed, M
# failed". UNCOUNTED by the doc-currency gate (test-*.sh).
#
# The classifier's NEVER-CRASH invariant means every case also asserts rc == 0; the
# behavioral assertion is the SHAPE/CONTENT of the emitted JSON array.
#
# Covers:
#   1. positive (PR #64 shape) -> a claude[bot] comment whose body carries a review
#                  finding ("review" word, MEDIUM count/restated-list drift) => IN,
#                  and the full original object (incl. created_at/html_url) survives.
#   2. negative control (Deploy Preview) -> a vercel[bot] notice (bot author, body has
#                  NO word-bounded review marker — "preview" must not match) => OUT.
#                  Mirrors the negative control pinned in test-pr-postmortem-gather.sh.
#   3. human author with a review-ish body -> OUT (only bots are drain-blockers).
#   4. empty input [] -> output [], exit 0.
#   5. mixed array -> only the bot-review elements survive, in order; non-string
#                  hostile elements degrade to non-matches (never abort), and original
#                  metadata (id) is preserved on the survivors.
#   6. fail-safe non-array / invalid input -> [], exit 0 (never crash a caller).

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CLASSIFY="$HERE/classify-bot-review.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "test-classify-bot-review: jq not available — cannot exercise the classifier; skipping (treated as pass)."
  echo; echo "RESULT: 0 passed, 0 failed"; exit 0
fi

# run_classify <json-on-stdin> — capture stdout in RUN_OUT, rc in RUN_RC.
run_classify() {
  RUN_OUT="$( printf '%s' "$1" | bash "$CLASSIFY" 2>/dev/null )"
  RUN_RC=$?
}

# ---------------------------------------------------------------------------
echo "== 1. positive: claude[bot] review finding (PR #64 shape) => classified IN, original object preserved =="
POS='[
  {"id": 901, "user": {"login": "claude[bot]"}, "html_url": "https://github.com/o/r/pull/64#issuecomment-901", "created_at": "2026-01-01T10:00:00Z", "body": "## Code Review — PR #64\n\nMEDIUM: restated count/list drift — the brief lists 4 items but the canonical source has 5. Please reconcile this review finding."}
]'
run_classify "$POS"
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | jq -e '
    (type=="array") and (length==1)
    and (.[0].user.login=="claude[bot]")
    and (.[0].id==901)
    and (.[0].created_at=="2026-01-01T10:00:00Z")
    and (.[0].html_url | test("issuecomment-901"))
    and (.[0].body | test("review"; "i"))
  ' >/dev/null 2>&1; then
  ok "positive bot review finding classified IN with full original object preserved"
else
  no "(1) wrong (rc=$RUN_RC): $RUN_OUT"
fi

# ---------------------------------------------------------------------------
echo "== 2. negative control: vercel[bot] 'Deploy Preview' (bot, no review marker) => classified OUT =="
DEPLOY='[
  {"id": 902, "user": {"login": "vercel[bot]"}, "created_at": "2026-01-01T09:30:00Z", "body": "Deploy Preview for my-app ready!"}
]'
run_classify "$DEPLOY"
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | jq -e '(type=="array") and (length==0)' >/dev/null 2>&1; then
  ok "Deploy Preview bot notice classified OUT ('preview' does not match word-bounded review marker)"
else
  no "(2) wrong (rc=$RUN_RC): $RUN_OUT"
fi

# ---------------------------------------------------------------------------
echo "== 3. human author with review-ish body => classified OUT (only bots are drain-blockers) =="
HUMAN='[
  {"id": 903, "user": {"login": "alice"}, "created_at": "2026-01-01T11:00:00Z", "body": "Left a review comment above — please review the query shape."}
]'
run_classify "$HUMAN"
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | jq -e '(type=="array") and (length==0)' >/dev/null 2>&1; then
  ok "human author with review-ish body classified OUT"
else
  no "(3) wrong (rc=$RUN_RC): $RUN_OUT"
fi

# ---------------------------------------------------------------------------
echo "== 4. empty input [] => output [], exit 0 =="
run_classify '[]'
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | jq -e '(type=="array") and (length==0)' >/dev/null 2>&1; then
  ok "empty input => [], exit 0"
else
  no "(4) wrong (rc=$RUN_RC): $RUN_OUT"
fi

# ---------------------------------------------------------------------------
echo "== 5. mixed array => only bot-review elements survive (in order); hostile elements degrade, metadata preserved =="
# Two bot-review IN (b1, b3), a Deploy Preview OUT, a human OUT, a coverage bot with no
# review marker OUT, and two hostile-typed elements that must NOT abort the program.
MIXED='[
  {"id": 1, "user": {"login": "claude[bot]"}, "created_at": "2026-01-01T10:00:00Z", "body": "## Review round 1\n\nFindings below."},
  {"id": 2, "user": {"login": "vercel[bot]"}, "created_at": "2026-01-01T09:30:00Z", "body": "Deploy Preview ready!"},
  {"id": 3, "user": {"login": "github-actions[bot]"}, "created_at": "2026-01-02T10:00:00Z", "body": "Automated review: 2 issues remain."},
  {"id": 4, "user": {"login": "bob"}, "created_at": "2026-01-02T11:00:00Z", "body": "thanks, will review later"},
  {"id": 5, "user": {"login": "coverage[bot]"}, "created_at": "2026-01-01T09:00:00Z", "body": "Coverage: 92% (+0.3%)"},
  {"user": {"login": 123}, "body": 456, "created_at": 789},
  {"user": "just-a-string", "body": null, "created_at": "2026-01-01T09:45:00Z"}
]'
run_classify "$MIXED"
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | jq -e '
    (type=="array") and (length==2)
    and ([.[].id] == [1, 3])
    and (.[0].user.login=="claude[bot]")
    and (.[1].user.login=="github-actions[bot]")
  ' >/dev/null 2>&1; then
  ok "mixed array: only the 2 bot-review elements survive in order (ids 1,3); hostile elements degraded, metadata preserved"
else
  no "(5) wrong (rc=$RUN_RC): $RUN_OUT"
fi

# ---------------------------------------------------------------------------
echo "== 6. fail-safe: non-array / invalid input => [], exit 0 (never crash a caller) =="
fs_fail=0
for bad in '{"not":"an array"}' 'not json at all' '42' ''; do
  run_classify "$bad"
  if [ "$RUN_RC" -ne 0 ] || ! printf '%s' "$RUN_OUT" | jq -e '(type=="array") and (length==0)' >/dev/null 2>&1; then
    fs_fail=1
    echo "    sub-case failed for input: <<<$bad>>> (rc=$RUN_RC out=$RUN_OUT)"
  fi
done
if [ "$fs_fail" -eq 0 ]; then
  ok "non-array / invalid / empty inputs all degrade to [], exit 0"
else
  no "(6) one or more fail-safe sub-cases wrong"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
