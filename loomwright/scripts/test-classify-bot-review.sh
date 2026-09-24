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
#  10. PR #223 shape (REGRESSION, 2026-09-14) -> a claude[bot] issue comment opening
#                  "Reviewed <sha>. … Two minor findings, both low severity: 1. … 2. …"
#                  that NEVER contains the bare word "review" => IN. The fixture
#                  self-checks that it really lacks `\breview\b`, so the case cannot
#                  quietly turn into a re-run of case 1.
#  11. MUTATION CONTROL for 10 -> a copy of the classifier with review_marker_re
#                  reverted to the pre-fix `\breview\b` must classify the #223 body
#                  OUT (proves the fixture exercises the widening, not something
#                  else). Gated on "the mutant differs from the original" and on the
#                  mutant carrying the exact old line; otherwise reported UNPROVEN.
#  12. boundary negatives under the widened marker -> "Previewed the build",
#                  "Deploy Preview", "Coverage: 92%" and a human "Reviewed …" all
#                  stay OUT (no word boundary inside "preview"; author gate intact).
#  18-22. bot_author_re tightening (red-team-hardening item 08, Fix 2) -> 'claude'
#                  (human, no [bot] suffix) and 'github-actions-fan' (bare-prefix
#                  match only) are OUT; 'claude[bot]', 'github-actions[bot]' and
#                  'anything[bot]' (generic [bot]-suffix login) all stay IN.

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

# ---------------------------------------------------------------------------
echo "== 10. PR #223 shape: 'Reviewed <sha>. … Two minor findings …' with NO bare 'review' word => classified IN =="
# Verbatim opener + structure of the claude[bot] comment on
# https://github.com/vikashruhilgit/loomwright/pull/223 (issuecomment 5668703118,
# 2026-09-14) that the pre-fix `\breview\b` marker dropped. The body uses ONLY the
# inflected "Reviewed" and the noun "findings" — never the bare lexeme.
PR223_BODY='Reviewed 1d35b3f9fced6093b464b4c0bcb9e5e1665c497c. This is a large, carefully engineered PR (/verify, verify-run.sh, the VERIFY_RESULT schema/validator branch, the verify-walkthrough skill, and an unusually thorough seam test suite). I read verify-run.sh in full and verified the count/version bumps against the actual directories -- all consistent, no drift found.\n\nTwo minor findings, both low severity:\n\n1. Cross-reference precision drift -- attachment extension mapping (doc vs. implementation)\n- The doc lists four extension branches; the implementation has three more before the *) fallback.\n\n2. Missing branch coverage -- counts.* non-negative check in the new VERIFY_RESULT validator (rule V5)\n- No case supplies a negative count to hit the non-negative branch specifically.\n\nNothing else stood out as incorrect.'
PR223="$(jq -cn --arg b "$PR223_BODY" '[{id: 5668703118, user: {login: "claude[bot]"}, html_url: "https://github.com/vikashruhilgit/loomwright/pull/223#issuecomment-5668703118", created_at: "2026-09-14T18:25:57Z", body: ($b | gsub("\\\\n"; "\n"))}]')"
# Fixture self-check: it must NOT contain the bare word — otherwise this case is
# just case 1 again and proves nothing about the widening.
if printf '%s' "$PR223" | jq -e '.[0].body | test("\\breview\\b"; "i") | not' >/dev/null 2>&1; then
  run_classify "$PR223"
  if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | jq -e '
      (type=="array") and (length==1)
      and (.[0].id==5668703118)
      and (.[0].user.login=="claude[bot]")
      and (.[0].created_at=="2026-09-14T18:25:57Z")
      and (.[0].body | startswith("Reviewed 1d35b3f"))
    ' >/dev/null 2>&1; then
    ok "PR #223 shape ('Reviewed <sha>' + 'findings', no bare 'review') classified IN with original object preserved"
  else
    no "(10) wrong (rc=$RUN_RC): $(printf '%s' "$RUN_OUT" | head -c 200)"
  fi
else
  no "(10) fixture INVALID: body contains the bare word 'review' — the case would not exercise the widening"
fi

# ---------------------------------------------------------------------------
echo "== 11. MUTATION CONTROL: classifier with review_marker_re reverted to pre-fix '\\breview\\b' => #223 body OUT =="
# Build the mutant by rewriting ONLY the regex definition line back to the exact
# pre-fix form. Both gates are load-bearing: (a) the mutant must DIFFER from the
# original (a no-op sed would make this case vacuous — it would "pass" for the
# wrong reason), and (b) the mutant must carry the exact old line (so we know the
# rewrite landed where intended and nothing else moved). Either gate failing is
# reported as UNPROVEN, which is a FAILURE, not a skip.
MUTANT="$TMP/classify-mutant.sh"
sed -e 's|^  def review_marker_re: .*$|  def review_marker_re: "\\\\breview\\\\b";|' "$CLASSIFY" > "$MUTANT"
if cmp -s "$CLASSIFY" "$MUTANT"; then
  no "(11) UNPROVEN: mutant is byte-identical to the original — the regex line was not rewritten"
elif ! grep -qF 'def review_marker_re: "\\breview\\b";' "$MUTANT"; then
  no "(11) UNPROVEN: mutant does not carry the exact pre-fix regex line: $(grep -n 'def review_marker_re' "$MUTANT")"
else
  MUT_OUT="$( printf '%s' "$PR223" | bash "$MUTANT" 2>/dev/null )"; MUT_RC=$?
  ORIG_OUT="$( printf '%s' "$PR223" | bash "$CLASSIFY" 2>/dev/null )"
  if [ "$MUT_RC" -eq 0 ] \
     && printf '%s' "$MUT_OUT" | jq -e '(type=="array") and (length==0)' >/dev/null 2>&1 \
     && printf '%s' "$ORIG_OUT" | jq -e '(type=="array") and (length==1)' >/dev/null 2>&1; then
    ok "mutation control: pre-fix '\\breview\\b' drops the #223 body (OUT); widened marker keeps it (IN)"
  else
    no "(11) wrong: mutant rc=$MUT_RC out=$(printf '%s' "$MUT_OUT" | head -c 120) | original out=$(printf '%s' "$ORIG_OUT" | head -c 120)"
  fi
fi

# ---------------------------------------------------------------------------
echo "== 12. boundary negatives under the widened marker: preview/previewed/coverage/human-'Reviewed' all stay OUT =="
# The stem alternation must not reintroduce the false positives the word boundary
# was added to exclude, and the author gate must still drop a human "Reviewed …".
NEG='[
  {"id": 1201, "user": {"login": "vercel[bot]"},  "created_at": "2026-01-01T09:30:00Z", "body": "Deploy Preview for my-app ready!"},
  {"id": 1202, "user": {"login": "netlify[bot]"}, "created_at": "2026-01-01T09:31:00Z", "body": "Previewed the build at https://example.test — previews are live."},
  {"id": 1203, "user": {"login": "coverage[bot]"}, "created_at": "2026-01-01T09:00:00Z", "body": "Coverage: 92% (+0.3%)"},
  {"id": 1204, "user": {"login": "alice"},        "created_at": "2026-01-01T11:00:00Z", "body": "Reviewed abc123. Two findings: 1. nit 2. nit"}
]'
run_classify "$NEG"
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | jq -e '(type=="array") and (length==0)' >/dev/null 2>&1; then
  ok "preview / previewed / coverage bots and a human 'Reviewed …' all classified OUT under the widened marker"
else
  no "(12) wrong (rc=$RUN_RC): $RUN_OUT"
fi

# =============================================================================
# --trusted-actors (red-team-hardening item 01, decision R2)
# =============================================================================

echo "== 13. --trusted-actors: exact-listed login classified IN, bot_author_re NOT consulted =="
printf '["realbot"]' > "$TMP/trusted.json"
IN13='[{"id": 1301, "user": {"login": "realbot"}, "body": "This is a review finding: MEDIUM issue"}]'
OUT13="$( printf '%s' "$IN13" | bash "$CLASSIFY" --trusted-actors "$TMP/trusted.json" 2>/dev/null )"; RC13=$?
if [ "$RC13" -eq 0 ] && printf '%s' "$OUT13" | jq -e '(type=="array") and (length==1) and (.[0].user.login=="realbot")' >/dev/null 2>&1; then
  ok "--trusted-actors exact match: non-bot-looking but exact-listed login classified IN"
else
  no "(13) wrong (rc=$RC13): $OUT13"
fi

echo "== 14. --trusted-actors: a bot_author_re-matching login NOT on the list is classified OUT =="
IN14='[{"id": 1401, "user": {"login": "claude[bot]"}, "body": "This is a review finding: MEDIUM issue"}]'
OUT14="$( printf '%s' "$IN14" | bash "$CLASSIFY" --trusted-actors "$TMP/trusted.json" 2>/dev/null )"; RC14=$?
if [ "$RC14" -eq 0 ] && printf '%s' "$OUT14" | jq -e '(type=="array") and (length==0)' >/dev/null 2>&1; then
  ok "--trusted-actors exact-match mode: bot_author_re match alone is insufficient when the list is present"
else
  no "(14) wrong (rc=$RC14): $OUT14"
fi

echo "== 15. --trusted-actors with a MISSING file: falls back to bot_author_re + logs actor_allowlist_absent once =="
OUT15="$( printf '%s' "$IN14" | bash "$CLASSIFY" --trusted-actors "$TMP/does-not-exist.json" 2>"$TMP/stderr15.log" )"; RC15=$?
ERRTXT15="$(cat "$TMP/stderr15.log")"
if [ "$RC15" -eq 0 ] \
   && printf '%s' "$OUT15" | jq -e '(type=="array") and (length==1)' >/dev/null 2>&1 \
   && grep -q 'actor_allowlist_absent' < <(printf '%s' "$ERRTXT15") \
   && [ "$(printf '%s' "$ERRTXT15" | grep -c 'actor_allowlist_absent')" -eq 1 ]; then
  ok "--trusted-actors missing file: falls back to bot_author_re (claude[bot] IN), logs actor_allowlist_absent exactly once"
else
  no "(15) wrong (rc=$RC15 out=$OUT15 err='$ERRTXT15')"
fi

echo "== 16. --trusted-actors NEVER passed: behavior 100% unchanged, no log line =="
OUT16="$( printf '%s' "$IN14" | bash "$CLASSIFY" 2>"$TMP/stderr16.log" )"; RC16=$?
ERRTXT16="$(cat "$TMP/stderr16.log")"
if [ "$RC16" -eq 0 ] \
   && printf '%s' "$OUT16" | jq -e '(type=="array") and (length==1)' >/dev/null 2>&1 \
   && [ -z "$ERRTXT16" ]; then
  ok "no --trusted-actors flag: unchanged bot_author_re behavior, no actor_allowlist_absent log (not opted in)"
else
  no "(16) wrong (rc=$RC16 out=$OUT16 err='$ERRTXT16')"
fi

echo "== 17. --trusted-actors with an unreadable/malformed-JSON file: treated like missing (falls back) =="
printf 'not valid json' > "$TMP/malformed.json"
OUT17="$( printf '%s' "$IN14" | bash "$CLASSIFY" --trusted-actors "$TMP/malformed.json" 2>"$TMP/stderr17.log" )"; RC17=$?
ERRTXT17="$(cat "$TMP/stderr17.log")"
if [ "$RC17" -eq 0 ] \
   && printf '%s' "$OUT17" | jq -e '(type=="array") and (length==1)' >/dev/null 2>&1 \
   && grep -q 'actor_allowlist_absent' < <(printf '%s' "$ERRTXT17"); then
  ok "--trusted-actors malformed JSON: treated as absent, falls back to bot_author_re, logged"
else
  no "(17) wrong (rc=$RC17 out=$OUT17 err='$ERRTXT17')"
fi

# =============================================================================
# bot_author_re tightening (red-team-hardening item 08, Fix 2) — exact-login form
# =============================================================================

echo "== 18. tightened bot_author_re: 'claude' (human, no [bot] suffix) is classified OUT =="
IN18A='[{"id": 1801, "user": {"login": "claude"}, "body": "This is a review finding: MEDIUM issue"}]'
OUT18A="$( printf '%s' "$IN18A" | bash "$CLASSIFY" 2>/dev/null )"; RC18A=$?
if [ "$RC18A" -eq 0 ] && printf '%s' "$OUT18A" | jq -e '(type=="array") and (length==0)' >/dev/null 2>&1; then
  ok "bare login 'claude' (no [bot] suffix) classified OUT — no longer trusted as a human-typo bot"
else
  no "(18a) wrong (rc=$RC18A): $OUT18A"
fi

echo "== 19. tightened bot_author_re: 'github-actions-fan' (prefix match only) is classified OUT =="
IN18B='[{"id": 1802, "user": {"login": "github-actions-fan"}, "body": "This is a review finding: MEDIUM issue"}]'
OUT18B="$( printf '%s' "$IN18B" | bash "$CLASSIFY" 2>/dev/null )"; RC18B=$?
if [ "$RC18B" -eq 0 ] && printf '%s' "$OUT18B" | jq -e '(type=="array") and (length==0)' >/dev/null 2>&1; then
  ok "'github-actions-fan' (merely starts with github-actions) classified OUT — bare-prefix alternative dropped"
else
  no "(19) wrong (rc=$RC18B): $OUT18B"
fi

echo "== 20. tightened bot_author_re: 'claude[bot]' is still classified IN =="
IN18C='[{"id": 1803, "user": {"login": "claude[bot]"}, "body": "This is a review finding: MEDIUM issue"}]'
OUT18C="$( printf '%s' "$IN18C" | bash "$CLASSIFY" 2>/dev/null )"; RC18C=$?
if [ "$RC18C" -eq 0 ] && printf '%s' "$OUT18C" | jq -e '(type=="array") and (length==1) and (.[0].user.login=="claude[bot]")' >/dev/null 2>&1; then
  ok "'claude[bot]' still classified IN under the tightened regex"
else
  no "(20) wrong (rc=$RC18C): $OUT18C"
fi

echo "== 21. tightened bot_author_re: 'github-actions[bot]' is still classified IN =="
IN18D='[{"id": 1804, "user": {"login": "github-actions[bot]"}, "body": "This is a review finding: MEDIUM issue"}]'
OUT18D="$( printf '%s' "$IN18D" | bash "$CLASSIFY" 2>/dev/null )"; RC18D=$?
if [ "$RC18D" -eq 0 ] && printf '%s' "$OUT18D" | jq -e '(type=="array") and (length==1) and (.[0].user.login=="github-actions[bot]")' >/dev/null 2>&1; then
  ok "'github-actions[bot]' still classified IN under the tightened regex"
else
  no "(21) wrong (rc=$RC18D): $OUT18D"
fi

echo "== 22. tightened bot_author_re: any other login ending in [bot] ('anything[bot]') is still classified IN =="
IN18E='[{"id": 1805, "user": {"login": "anything[bot]"}, "body": "This is a review finding: MEDIUM issue"}]'
OUT18E="$( printf '%s' "$IN18E" | bash "$CLASSIFY" 2>/dev/null )"; RC18E=$?
if [ "$RC18E" -eq 0 ] && printf '%s' "$OUT18E" | jq -e '(type=="array") and (length==1) and (.[0].user.login=="anything[bot]")' >/dev/null 2>&1; then
  ok "'anything[bot]' (generic [bot]-suffix login) still classified IN under the tightened regex"
else
  no "(22) wrong (rc=$RC18E): $OUT18E"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
