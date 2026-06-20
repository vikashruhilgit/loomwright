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
#   7. large multibyte array (REGRESSION for the ${//[[:space:]]/} wedge) -> a
#                  ~160KB array with em-dash/emoji bodies classifies correctly and
#                  completes FAST under a hard watchdog. Before the fix, the O(n^2)
#                  bash-3.2 pattern SUBSTITUTION wedged for minutes on such input
#                  (a real hang reproduced on ~96KB PR-comment arrays).
#   8. never-closing stdin -> the BOUNDED read (CLASSIFY_STDIN_TIMEOUT) self-exits
#                  to [] at the timeout and writes a one-line STDERR breadcrumb; the
#                  outer watchdog never has to fire. A plain `cat` would block forever
#                  here. Case 7 also asserts a fast read emits NO false breadcrumb.
#   9. slow / incomplete stdin -> a producer that dribbles a partial fragment and
#                  never closes degrades to [] under the bounded read (no hang).

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

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# bounded_sh <outer_secs> <out_file> <shell-string> — run a shell command in the
# background under a HARD wall-clock watchdog (portable; stock macOS has no
# `timeout`/`gtimeout`). Sets B_RC (exit/kill code) and B_TIMEDOUT (1 IFF the
# watchdog had to kill it — i.e. the command HUNG past <outer_secs>). This is how
# the never-hangs cases below PROVE their contract: a correct classify always
# self-terminates well inside the bound, so B_TIMEDOUT must stay 0.
bounded_sh() {
  local secs="$1" outf="$2" cmd="$3"
  local errf="${outf%.out}.err"   # per-case stderr capture (for the timeout breadcrumb)
  rm -f "$TMP/timedout"
  bash -c "$cmd" >"$outf" 2>"$errf" &
  local cpid=$!
  ( sleep "$secs"; kill -0 "$cpid" 2>/dev/null && { : >"$TMP/timedout"; kill -TERM "$cpid" 2>/dev/null; sleep 1; kill -KILL "$cpid" 2>/dev/null; }; ) &
  local wpid=$!
  wait "$cpid" 2>/dev/null; B_RC=$?
  kill "$wpid" 2>/dev/null; wait "$wpid" 2>/dev/null
  if [ -f "$TMP/timedout" ]; then B_TIMEDOUT=1; else B_TIMEDOUT=0; fi
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

# ---------------------------------------------------------------------------
echo "== 7. large multibyte array => classified correctly AND fast (regression: the O(n^2) \${//} wedge) =="
# ~200-element array with multibyte bodies (em-dash —, robot emoji) so the OLD
# ${INPUT//[[:space:]]/} whitespace-strip wedged bash 3.2 for MINUTES; the fixed
# early-exit `case` + bounded read must classify it in well under the watchdog.
# Every 5th element is a claude[bot] review comment (40 of 200) => 40 classified IN;
# the human-authored ones are dropped on the author test regardless of body.
BIG="$TMP/big.json"
jq -cn '
  ("—") as $emdash | ("🤖") as $bot |
  [ range(0;200) as $i
  | { id: $i,
      user: { login: (if ($i % 5) == 0 then "claude[bot]" else "human\($i)" end) },
      created_at: "2026-01-01T00:00:00Z",
      html_url: "https://github.com/o/r/pull/1#issuecomment-\($i)",
      body: ("## Code Review \($emdash) finding \($i) \($bot). "
             + ([range(0;30)] | map("\($emdash) padding lorem ipsum \($emdash) review note \($bot) ") | add)) } ]' \
  > "$BIG"
BIG_BYTES=$(wc -c < "$BIG" | tr -d ' ')
bounded_sh 20 "$TMP/c7.out" "cat '$BIG' | bash '$CLASSIFY'"
# A fast read must NOT emit the timeout breadcrumb (no false positive on healthy input).
if [ "$B_TIMEDOUT" -eq 0 ] && [ "$B_RC" -eq 0 ] \
   && ! grep -q 'timed out' "$TMP/c7.err" 2>/dev/null \
   && printf '%s' "$(cat "$TMP/c7.out")" | jq -e '
    (type=="array") and (length==40) and (all(.[]; .user.login=="claude[bot]"))
  ' >/dev/null 2>&1; then
  ok "large (~${BIG_BYTES}B) multibyte array classified (40 bot-review IN) without wedging (no false timeout breadcrumb)"
else
  no "(7) wrong (B_TIMEDOUT=$B_TIMEDOUT B_RC=$B_RC bytes=$BIG_BYTES): $(head -c 200 "$TMP/c7.out") err=$(head -c 120 "$TMP/c7.err" 2>/dev/null)"
fi

# ---------------------------------------------------------------------------
echo "== 8. never-closing stdin => bounded read self-exits to [] (does NOT hang) =="
# A producer that holds the pipe open WITHOUT sending EOF for longer than the inner
# read timeout. With CLASSIFY_STDIN_TIMEOUT=1 the read gives up at ~1s and degrades
# to []; the outer 8s watchdog must NOT have to fire. A plain `cat` would block here
# until the producer finally closed (the latent hang this fix also closes).
bounded_sh 8 "$TMP/c8.out" "( sleep 3 ) | CLASSIFY_STDIN_TIMEOUT=1 bash '$CLASSIFY'"
# On timeout: stdout is [], outer watchdog never fires, AND the stderr breadcrumb fires
# (so a timeout is distinguishable from an empty endpoint in logs).
if [ "$B_TIMEDOUT" -eq 0 ] && [ "$B_RC" -eq 0 ] \
   && printf '%s' "$(cat "$TMP/c8.out")" | jq -e '(type=="array") and (length==0)' >/dev/null 2>&1 \
   && grep -q 'timed out' "$TMP/c8.err" 2>/dev/null; then
  ok "never-closing stdin: bounded read times out at ~1s => [], watchdog never fired, stderr breadcrumb emitted"
else
  no "(8) wrong (B_TIMEDOUT=$B_TIMEDOUT B_RC=$B_RC): out=$(head -c 120 "$TMP/c8.out") err=$(head -c 120 "$TMP/c8.err" 2>/dev/null)"
fi

# ---------------------------------------------------------------------------
echo "== 9. slow / incomplete stdin => partial fragment degrades to [] (does NOT hang) =="
# Producer dribbles an incomplete, non-array fragment then stalls without closing.
# The bounded read gives up at ~1s; the fragment is not a valid JSON array, so jq
# + the defensive fallback degrade to []. No hang, exit 0.
bounded_sh 8 "$TMP/c9.out" "( printf 'partial-fragment-no-eof' ; sleep 3 ) | CLASSIFY_STDIN_TIMEOUT=1 bash '$CLASSIFY'"
if [ "$B_TIMEDOUT" -eq 0 ] && [ "$B_RC" -eq 0 ] && printf '%s' "$(cat "$TMP/c9.out")" | jq -e '(type=="array") and (length==0)' >/dev/null 2>&1; then
  ok "slow/incomplete stdin: partial fragment degrades to [] under the bounded read, no hang"
else
  no "(9) wrong (B_TIMEDOUT=$B_TIMEDOUT B_RC=$B_RC): $(head -c 120 "$TMP/c9.out")"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
