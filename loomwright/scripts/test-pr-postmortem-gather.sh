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
# bindir. The stub serves BOTH gh paths from fixture files — the load-bearing
# `gh pr view ... --json ...` call AND the second, best-effort
# `gh api repos/{owner}/{repo}/issues/{number}/comments` fetch — so the gatherer's
# round-trips are fully deterministic and offline.
#
# Covers:
#   1. happy path  -> valid JSON, expected keys (repo,number,commits,review_rounds,
#                     ci_checks), NO `status` field, exit 0.
#   2. short-form input OWNER/REPO#N -> same happy shape, exit 0.
#   3. heuristics  -> agent_generated_guess true, is_review_fix true on the churn
#                     commit, review_rounds reflects the signal; an APPROVED/LGTM
#                     review does NOT inflate review_rounds.
#   3b. human PR   -> commit subjects with utf-8/sha-256 tokens do NOT flip
#                     agent_generated_guess; approval-only review => 0 rounds.
#   3c. task-id PR -> a subject-LEADING task-id prefix ("bd-15a: ...") DOES flip
#                     agent_generated_guess.
#   3d. bot-review PR (the PR #47 shape) -> 0 review OBJECTS but bot-review ISSUE
#                     comments (served via the SEPARATE `gh api .../issues/N/comments`
#                     stub path, REST shape) => review_rounds counts ONLY the
#                     timestamp-ANCHORED rounds (>=1 commit committedDate after the
#                     comment created_at); the trailing "clean / recommend merge"
#                     comment with no commits after it does NOT count; a vercel[bot]
#                     "Deploy Preview" comment does NOT match the word-bounded review
#                     marker (no phantom round, absent from review_comments); the
#                     narrow legacy is_review_fix regex does NOT match
#                     "round-N"/"nit"/"reconcil" subjects; human chatter and
#                     non-review bot comments count nowhere.
#   3e. comments-fetch degrade -> `gh pr view` succeeds but `gh api .../comments`
#                     fails => success-shaped object (NOT unavailable), review_rounds
#                     falls back to the two legacy signals, exit 0.
#   3f. hostile-typed comment elements -> a VALID comments array containing elements
#                     with non-string user.login/body/created_at values must NOT abort
#                     the single jq invocation (NEVER unavailable because of comments,
#                     element-level): hostile elements degrade to non-matches, the
#                     well-formed bot comments still produce the same anchored
#                     review_rounds as 3d, exit 0.
#   3g. HUB-shape PR (vendsy/hub#146) -> 0 review objects, claude-bot comments headed
#                     "## Overview" (NO review heading — the widened word-bounded
#                     anywhere-in-body marker must match their running text), commit
#                     headlines using the EXPLICIT anchored forms "PR #42 review — …" /
#                     "review #2 — …" (the narrow regex's two new alternations) =>
#                     review_rounds==3 with both signals independently counting 3;
#                     a "deploy preview #2" headline and a vercel[bot] "Deploy
#                     Preview" comment stay non-matching (word-bounded, re-pinned
#                     against the widened marker); the trailing all-clear bot comment
#                     with no later push does not anchor a 4th round.
#   3h. hub#139 shape -> "address code review findings …" commit headlines (the
#                     intervening "code" broke the old "address(es)? review"
#                     adjacency requirement) must flag is_review_fix via the widened
#                     "address(es)? (code )?review" alternative => review_rounds==2
#                     (source fix_commits) instead of the live undercount of 1
#                     (formal_reviews); "add audit findings export" — a verified
#                     false-positive of the REJECTED broadened churn-word class —
#                     stays non-matching.
#   3i. provenance -> happy-path success JSON carries pr_url (string), branch (string),
#                     and changed_paths (array of paths), sourced jq-natively from the
#                     PR JSON's url/headRefName/files (Learning Loop Phase 4, additive).
#                     The 3c task-id fixture (no url/headRefName/files) also asserts the
#                     `// null` / `(.files // [])` tolerance: pr_url/branch == null,
#                     changed_paths == [] with no jq error.
#   3j. large multibyte comments array (PRODUCTION-wedge regression) -> a ~100KB
#                     issue-comment array (the #54/#59/#37 shape that hung the gather
#                     for minutes inside classify-bot-review.sh's bash-3.2 O(n^2)
#                     whitespace-strip) => the gather completes well inside a HARD
#                     watchdog (RUN_TIMEDOUT==0) and emits a SUCCESS object with all
#                     60 claude[bot] comments classified and bot-sourced review_rounds.
#   4. injection-safety -> a title/body/review body AND provenance branch/changed_paths
#                     with quotes/backslashes/newlines round-trip as valid JSON (no parse break).
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
    {"author": {"login": "alice"}, "body": "please rename this", "state": "CHANGES_REQUESTED", "submittedAt": "2026-01-01T10:00:00Z"},
    {"author": {"login": "bob"}, "body": "LGTM after fix", "state": "APPROVED", "submittedAt": "2026-01-02T11:00:00Z"}
  ],
  "statusCheckRollup": [
    {"name": "ci/test", "state": "SUCCESS"},
    {"name": "lint", "state": "FAILURE"},
    {"name": "build", "status": "IN_PROGRESS", "conclusion": ""}
  ],
  "url": "https://github.com/acme/widgets/pull/42",
  "headRefName": "feature/jwt-guard",
  "files": [
    {"path": "src/auth/jwt.guard.ts"},
    {"path": "src/auth/jwt.guard.spec.ts"}
  ]
}
FIX

# Human-PR fixture (3b): subjects carry word-dash-number tokens (utf-8, sha-256) that
# the pre-fix bare pattern false-positived on; the only review is an approval.
FIX_HUMAN="$TMP/fixture-human.json"
cat > "$FIX_HUMAN" <<'FIX'
{
  "number": 42,
  "title": "Fix encoding bugs",
  "body": "Plain human PR fixing two encoding issues.",
  "additions": 8,
  "deletions": 4,
  "changedFiles": 2,
  "commits": [
    {"messageHeadline": "fix utf-8 encoding in importer"},
    {"messageHeadline": "feat: sha-256 checksum support"}
  ],
  "reviews": [
    {"author": {"login": "bob"}, "body": "LGTM", "state": "APPROVED", "submittedAt": "2026-01-03T09:00:00Z"}
  ],
  "statusCheckRollup": []
}
FIX

# Task-id-PR fixture (3c): plain body, but a subject-LEADING "id:" prefix — the one
# task-id shape the anchored pattern is meant to keep matching.
FIX_TASKID="$TMP/fixture-taskid.json"
cat > "$FIX_TASKID" <<'FIX'
{
  "number": 42,
  "title": "Cookie service",
  "body": "Implements the cookie service.",
  "additions": 20,
  "deletions": 0,
  "changedFiles": 1,
  "commits": [
    {"messageHeadline": "bd-15a: implement cookie service"}
  ],
  "reviews": [],
  "statusCheckRollup": []
}
FIX

# Bot-review fixture (3d): the PR #47 shape — the repo's review feedback arrives as
# claude-bot ISSUE comments (CI review workflow), with ZERO review objects. The PR-view
# blob carries committedDate on every commit (the anchoring data); the comments live in
# a SEPARATE REST-shaped fixture served via the `gh api` stub path below. The commit
# subjects carry "round-N"/"nit"/"reconcil" tokens that the REJECTED broadened regex
# matched — the narrow legacy is_review_fix regex must NOT match them.
FIX_BOTREVIEW="$TMP/fixture-botreview.json"
cat > "$FIX_BOTREVIEW" <<'FIX'
{
  "number": 42,
  "title": "Supervisor diet + parity guard",
  "body": "Structural quality levers.\n\n🤖 Generated with Claude Code",
  "additions": 60,
  "deletions": 10,
  "changedFiles": 6,
  "commits": [
    {"messageHeadline": "feat(structure): supervisor diet + parity guard", "committedDate": "2026-01-01T08:00:00Z"},
    {"messageHeadline": "fix(docs): tighten skill description (round-2 review nit 5)", "committedDate": "2026-01-01T12:00:00Z"},
    {"messageHeadline": "fix(docs): round-5 reconciliations — roadmap framing", "committedDate": "2026-01-02T12:00:00Z"}
  ],
  "reviews": [],
  "statusCheckRollup": []
}
FIX

# REST-shaped issue comments for 3d (served by the stub's `gh api` path: user.login /
# created_at / body — snake_case, NOT the gh-pr-view author/createdAt shape). Anchored
# rounds: c1 (2026-01-01T10) and c2 (2026-01-02T10) each have a commit landing after
# them => count; the trailing "round 3 — clean / Recommend merge" (2026-01-03T10) has
# NO commit after it => must NOT count. Negative controls: human chatter, a coverage
# bot with no review marker, and a vercel[bot] "Deploy Preview" notice ("preview"
# contains "review" as a substring — the word-bounded marker must not match it).
FIX_BOTREVIEW_COMMENTS="$TMP/fixture-botreview-comments.json"
cat > "$FIX_BOTREVIEW_COMMENTS" <<'FIX'
[
  {"user": {"login": "claude[bot]"}, "created_at": "2026-01-01T10:00:00Z", "body": "## Code Review — PR #42\n\nFindings below."},
  {"user": {"login": "claude[bot]"}, "created_at": "2026-01-02T10:00:00Z", "body": "## Review round 2\n\nRemaining nits."},
  {"user": {"login": "claude[bot]"}, "created_at": "2026-01-03T10:00:00Z", "body": "## Review round 3 — clean\n\nRecommend merge."},
  {"user": {"login": "alice"}, "created_at": "2026-01-03T11:00:00Z", "body": "thanks, merging!"},
  {"user": {"login": "coverage[bot]"}, "created_at": "2026-01-01T09:00:00Z", "body": "Coverage: 92% (+0.3%)"},
  {"user": {"login": "vercel[bot]"}, "created_at": "2026-01-01T09:30:00Z", "body": "Deploy Preview for my-app ready!"}
]
FIX

# Hostile-typed comments fixture (3f): a VALID JSON array whose elements carry
# non-string values where strings are expected. {"user":{"login":123}} survives a
# bare ((.user.login)? // "") access — the value exists and is truthy, so // keeps
# 123 — and then type-errors in test()/gsub(), aborting the gatherer's SINGLE jq
# invocation => normalize_failed (unavailable), violating the
# never-unavailable-from-comments invariant at the element level. The strings-guarded
# accesses must instead degrade each hostile element to a non-match. Elements:
#   - the fully hostile element (number login/body/created_at) — the abort repro;
#   - a string `user` (path-access error on .user.login — the (…)? control case);
#   - a marker-matching hostile[bot] comment whose created_at is a NUMBER — must NOT
#     become a round (strings guard empties $cat, the anchor check drops it), though
#     its well-typed body still lands in review_comments;
#   - the 3 well-formed claude[bot] comments from 3d, so the anchored count (2) is
#     still derivable from the surviving elements.
FIX_BOTREVIEW_COMMENTS_HOSTILE="$TMP/fixture-botreview-comments-hostile.json"
cat > "$FIX_BOTREVIEW_COMMENTS_HOSTILE" <<'FIX'
[
  {"user": {"login": 123}, "body": 456, "created_at": 789},
  {"user": "just-a-string", "body": null, "created_at": "2026-01-01T09:45:00Z"},
  {"user": {"login": "hostile[bot]"}, "created_at": 42, "body": "## Code Review — bad timestamp\n\nNon-string created_at must not anchor a round."},
  {"user": {"login": "claude[bot]"}, "created_at": "2026-01-01T10:00:00Z", "body": "## Code Review — PR #42\n\nFindings below."},
  {"user": {"login": "claude[bot]"}, "created_at": "2026-01-02T10:00:00Z", "body": "## Review round 2\n\nRemaining nits."},
  {"user": {"login": "claude[bot]"}, "created_at": "2026-01-03T10:00:00Z", "body": "## Review round 3 — clean\n\nRecommend merge."}
]
FIX

# HUB-shape fixture (3g): the vendsy/hub#146 shape (verified live 2026-06-10) that
# BOTH v14.23.1 signals missed — zero review objects, bot review comments headed
# "## Overview" (no review heading for the old marker), and review-fix commits using
# the EXPLICIT "PR #N review — …" / "review #N — …" headline forms the narrow regex
# omitted. The "deploy preview #2" subject is the word-boundary negative control for
# the new "review #N" alternation ("preview #2" contains "review #2" as a substring).
FIX_HUBSHAPE="$TMP/fixture-hubshape.json"
cat > "$FIX_HUBSHAPE" <<'FIX'
{
  "number": 42,
  "title": "Auto-emit taxMappings on E-Invoice provisioning",
  "body": "Auto-populates taxMappings at provisioning time.\n\n🤖 Generated with Claude Code",
  "additions": 700,
  "deletions": 2,
  "changedFiles": 8,
  "commits": [
    {"messageHeadline": "feat(ENT-1): auto-emit taxMappings on provisioning (R7)", "committedDate": "2026-01-01T08:00:00Z"},
    {"messageHeadline": "chore: deploy preview #2 tweaks", "committedDate": "2026-01-01T08:30:00Z"},
    {"messageHeadline": "fix(ENT-1): PR #42 review — use findActiveByVenue convention", "committedDate": "2026-01-01T10:30:00Z"},
    {"messageHeadline": "fix(ENT-1): review #2 — skip FIXED-rate domain rule", "committedDate": "2026-01-01T12:30:00Z"},
    {"messageHeadline": "fix(ENT-1): review #3 — type-safe taxRateType + coverage", "committedDate": "2026-01-01T14:30:00Z"}
  ],
  "reviews": [],
  "statusCheckRollup": []
}
FIX

# REST-shaped issue comments for 3g: four claude[bot] review comments, every body
# headed "## Overview" — the OLD heading-anchored marker matches NONE of them; the
# widened word-bounded anywhere-in-body marker must match all four via "review" in
# the running text. Anchoring: c1/c2/c3 each have a commit landing after => 3 rounds;
# the trailing all-clear c4 (15:00, no commit after) must NOT count. vercel[bot]
# "Deploy Preview" re-pins the word-boundary guarantee against the widened marker.
FIX_HUBSHAPE_COMMENTS="$TMP/fixture-hubshape-comments.json"
cat > "$FIX_HUBSHAPE_COMMENTS" <<'FIX'
[
  {"user": {"login": "vercel[bot]"}, "created_at": "2026-01-01T09:00:00Z", "body": "Deploy Preview for my-app ready!"},
  {"user": {"login": "claude[bot]"}, "created_at": "2026-01-01T10:00:00Z", "body": "## Overview\n\nThe fix premise is accurate; addresses issues raised in prior review rounds."},
  {"user": {"login": "claude[bot]"}, "created_at": "2026-01-01T12:00:00Z", "body": "## Overview\n\nFollow-up verification; remaining review concern: FIXED-rate rows."},
  {"user": {"login": "claude[bot]"}, "created_at": "2026-01-01T14:00:00Z", "body": "## Overview\n\nResidual review nit: taxRateType cast loses type safety."},
  {"user": {"login": "claude[bot]"}, "created_at": "2026-01-01T15:00:00Z", "body": "## Overview\n\nAll prior review findings resolved. Recommend merge."}
]
FIX

# hub#139-shape fixture (3h): "address code review findings …" headlines (verified
# live 2026-06-12) — the old first alternative required "address(es)? review"
# ADJACENCY, so the intervening word "code" left both explicit fix commits uncounted
# and review_rounds stuck at 1 (the single formal churn review). The widened
# "address(es)? (code )?review" must match both; "findings" ALONE stays rejected —
# "add audit findings export" is a verified false-positive of the REJECTED broadened
# churn-word class and is the in-fixture negative control.
FIX_HUB139="$TMP/fixture-hub139.json"
cat > "$FIX_HUB139" <<'FIX'
{
  "number": 42,
  "title": "Favorite reports",
  "body": "Adds favorite-reports.\n\n🤖 Generated with Claude Code",
  "additions": 300,
  "deletions": 12,
  "changedFiles": 9,
  "commits": [
    {"messageHeadline": "feat(reports): favorite reports feature", "committedDate": "2026-01-01T08:00:00Z"},
    {"messageHeadline": "fix(reports): address code review findings on favorite-reports feature", "committedDate": "2026-01-01T10:00:00Z"},
    {"messageHeadline": "fix(reporting): address code review findings #3 #5 #7 #10", "committedDate": "2026-01-01T12:00:00Z"},
    {"messageHeadline": "chore: add audit findings export", "committedDate": "2026-01-01T13:00:00Z"}
  ],
  "reviews": [
    {"author": {"login": "alice"}, "body": "please fix the query shape", "state": "CHANGES_REQUESTED", "submittedAt": "2026-01-01T09:00:00Z"}
  ],
  "statusCheckRollup": []
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
  ],
  "url": "https://github.com/acme/widgets/pull/42",
  "headRefName": "feature/\"weird\" \\ branch",
  "files": [
    {"path": "src/\"quoted\".ts"},
    {"path": "src/back\\slash.ts"}
  ]
}
FIX

# make_gh_stub <mode> [api_mode] — write a fake `gh` to $BIN that serves BOTH gh
# paths the gatherer makes; for any other args exits 0. The stub body is tiny and
# carries NO embedded JSON (the JSON lives in the files above), so the unquoted
# outer heredoc cannot corrupt any escapes. <mode> drives `gh pr view`:
#   ok        — rich happy-path PR (agent-generated, one review-fix commit, 2 reviews, CI).
#   human     — human PR: utf-8/sha-256 commit tokens, approval-only review (3b).
#   taskid    — subject-leading "bd-15a:" task-id prefix, plain body (3c).
#   botreview — PR #47 shape: zero review objects, committedDate-stamped commits (3d/3e).
#   hubshape  — vendsy/hub#146 shape: zero review objects, "PR #N review"/"review #N"
#               fix headlines, "## Overview"-headed bot comments (3g).
#   hub139    — vendsy/hub#139 shape: "address code review findings" fix headlines,
#               one formal churn review, no bot comments (3h).
#   inject    — title/body/review carrying quotes, backslashes, and a newline.
#   fail      — `pr view` exits 1 (simulates private/not-found/unauthenticated).
# [api_mode] drives the SECOND fetch (`gh api repos/.../issues/.../comments`; the stub
# pins the exact endpoint path — any other api path exits 1, exercising degrade):
#   empty (default) — emit "[]" (no issue comments).
#   comments        — cat the REST-shaped bot-review comments fixture (3d).
#   hubcomments     — cat the "## Overview"-headed bot comments fixture (3g).
#   hostile         — cat the hostile-typed comments fixture (3f): VALID array,
#                     non-string user.login/body/created_at elements.
#   bigcomments     — cat the ~100KB multibyte comments fixture (3j): the production
#                     wedge repro (large array that hung classify-bot-review.sh).
#   fail            — exit 1 (comments endpoint failing — the degrade path, 3e).
# Large multibyte comments fixture (3j): a ~100KB REST-shaped array — 60 claude[bot]
# review comments with em-dash/emoji bodies — that reproduces the PRODUCTION wedge the
# gather hit on real >64KB issue-comment arrays (#54/#59/#37): bash-3.2's O(n^2)
# whitespace-strip in classify-bot-review.sh hung for minutes. Generated with jq (too
# large for a heredoc); multibyte is emitted via \uXXXX escapes so this file stays
# ASCII. Every created_at precedes the botreview fixture's first commit (08:00), so all
# 60 anchor a bot review round.
FIX_BIGCOMMENTS="$TMP/fixture-bigcomments.json"
jq -cn '
  "\u2014" as $emdash | "\ud83e\udd16" as $bot |
  [ range(0;60) as $i
  | { user: { login: "claude[bot]" },
      created_at: "2026-01-01T07:00:00Z",
      html_url: "https://github.com/acme/widgets/pull/42#issuecomment-\($i)",
      body: ("## Code Review \($emdash) round \($i) \($bot). "
             + ([range(0;25)] | map("\($emdash) review finding lorem ipsum \($bot) ") | add)) } ]' \
  > "$FIX_BIGCOMMENTS"

make_gh_stub() {
  local mode="$1" api_mode="${2:-empty}" fixture="" api_fixture=""
  case "$mode" in
    ok)        fixture="$FIX_OK" ;;
    human)     fixture="$FIX_HUMAN" ;;
    taskid)    fixture="$FIX_TASKID" ;;
    botreview) fixture="$FIX_BOTREVIEW" ;;
    hubshape)  fixture="$FIX_HUBSHAPE" ;;
    hub139)    fixture="$FIX_HUB139" ;;
    inject)    fixture="$FIX_INJECT" ;;
    fail)      fixture="" ;;
  esac
  case "$api_mode" in
    comments)    api_fixture="$FIX_BOTREVIEW_COMMENTS" ;;
    hubcomments) api_fixture="$FIX_HUBSHAPE_COMMENTS" ;;
    hostile)     api_fixture="$FIX_BOTREVIEW_COMMENTS_HOSTILE" ;;
    bigcomments) api_fixture="$FIX_BIGCOMMENTS" ;;
  esac
  cat > "$BIN/gh" <<STUB
#!/usr/bin/env bash
# fake gh — fixture mode: $mode / api mode: $api_mode
if [ "\${1:-}" = "pr" ] && [ "\${2:-}" = "view" ]; then
  if [ "$mode" = "fail" ]; then exit 1; fi
  cat "$fixture"
  exit 0
fi
if [ "\${1:-}" = "api" ]; then
  if [ "$api_mode" = "fail" ]; then exit 1; fi
  # Pinned endpoint INCLUDING the bounded-page query: a fetch without ?per_page=100
  # (REST default 30 — silently drops bot rounds on heavy-churn PRs) exits 1 and
  # degrades, which 3d/3f catch via their review_rounds==2 assertions.
  case "\${2:-}" in
    'repos/acme/widgets/issues/42/comments?per_page=100') : ;;
    *) exit 1 ;;
  esac
  if [ -n "$api_fixture" ]; then cat "$api_fixture"; exit 0; fi
  echo "[]"
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

# run_gather_bounded <secs> <args...> — like run_gather, but under a HARD wall-clock
# watchdog (stock macOS has no `timeout`/`gtimeout`). Sets RUN_OUT, RUN_RC, and
# RUN_TIMEDOUT (1 IFF the gather HUNG past <secs> and had to be killed). This is how
# the large-comments regression PROVES the "gather never wedges" contract: a healthy
# gather finishes far inside the bound, so RUN_TIMEDOUT must stay 0.
run_gather_bounded() {
  local secs="$1"; shift
  rm -f "$TMP/gtimedout"
  PATH="$BIN:$PATH" bash "$GATHER" "$@" >"$TMP/gb.out" 2>/dev/null &
  local cpid=$!
  ( sleep "$secs"; kill -0 "$cpid" 2>/dev/null && { : >"$TMP/gtimedout"; kill -TERM "$cpid" 2>/dev/null; sleep 1; kill -KILL "$cpid" 2>/dev/null; }; ) &
  local wpid=$!
  wait "$cpid" 2>/dev/null; RUN_RC=$?
  kill "$wpid" 2>/dev/null; wait "$wpid" 2>/dev/null
  RUN_OUT="$(cat "$TMP/gb.out" 2>/dev/null)"
  if [ -f "$TMP/gtimedout" ]; then RUN_TIMEDOUT=1; else RUN_TIMEDOUT=0; fi
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

echo "== 3. heuristics => agent guess true, is_review_fix true, APPROVED does not inflate rounds =="
make_gh_stub ok
run_gather "$PR_URL"
# One CHANGES_REQUESTED review + one is_review_fix commit = 1 churn round; the
# APPROVED "LGTM after fix" review must NOT bump review_rounds to 2.
if printf '%s' "$RUN_OUT" | jq -e '
    .agent_generated_guess==true
    and (.commits | length)==2
    and ([.commits[] | select(.is_review_fix)] | length)==1
    and (.commits[1].is_review_fix==true)
    and (.review_rounds == 1)
    and (.review_rounds_source == "fix_commits")
    and (.review_comments | length)==2
    and (.ci_checks | length)==3
    and (.ci_checks[2].state=="IN_PROGRESS")
  ' >/dev/null 2>&1; then
  ok "heuristics: agent guess true, 1 review-fix commit, review_rounds==1 (approval not counted, source fix_commits wins the tie), 2 review_comments, in-progress CheckRun (conclusion:\"\") maps to IN_PROGRESS"
else
  no "(3) wrong: $RUN_OUT"
fi

echo "== 3b. human PR => utf-8/sha-256 tokens do NOT flip agent guess; approval-only => 0 rounds =="
make_gh_stub human
run_gather "$PR_URL"
if printf '%s' "$RUN_OUT" | jq -e '
    .agent_generated_guess==false
    and ([.commits[] | select(.is_review_fix)] | length)==0
    and (.review_rounds == 0)
    and (.review_rounds_source == "none")
  ' >/dev/null 2>&1; then
  ok "human PR: agent guess false despite utf-8/sha-256 subjects, review_rounds==0 (source none) with approval-only review"
else
  no "(3b) wrong: $RUN_OUT"
fi

echo "== 3c. task-id PR => subject-leading 'bd-15a:' prefix DOES flip agent guess =="
make_gh_stub taskid
run_gather "$PR_URL"
if printf '%s' "$RUN_OUT" | jq -e '
    .agent_generated_guess==true and (.review_rounds == 0)
    and (.pr_url == null) and (.branch == null) and (.changed_paths == [])
  ' >/dev/null 2>&1; then
  ok "task-id PR: subject-leading id prefix flips agent guess true; absent url/headRefName/files degrade to null/null/[] (no jq error)"
else
  no "(3c) wrong: $RUN_OUT"
fi

echo "== 3d. bot-review PR (PR #47 shape) => timestamp-ANCHORED bot rounds only; preview/chatter/trailing-clean do not count =="
make_gh_stub botreview comments
run_gather "$PR_URL"
# 0 review objects, 0 narrow-regex fix commits (the "round-2 review nit"/"round-5
# reconciliations" subjects must NOT match — the broadened regex was rejected), and
# 3 marker-matching claude-bot review comments of which only 2 have a commit landing
# after them => review_rounds == MAX(0, 0, 2) == 2. The trailing "round 3 — clean /
# Recommend merge" comment (no commits after) must NOT count as a round; the
# vercel[bot] "Deploy Preview" comment must not count anywhere (word-bounded marker);
# human "thanks, merging!" and the coverage bot count nowhere. review_comments keeps
# all 3 marker-matching bot review comments (snippets are context, rounds are counts).
if printf '%s' "$RUN_OUT" | jq -e '
    (.review_rounds == 2)
    and (.review_rounds_source == "bot_comments")
    and ([.commits[] | select(.is_review_fix)] | length)==0
    and (.review_comments | length)==3
    and ([.review_comments[] | select(.author=="claude[bot]")] | length)==3
    and ([.review_comments[] | select(.snippet | test("Deploy Preview"))] | length)==0
    and .agent_generated_guess==true
  ' >/dev/null 2>&1; then
  ok "bot-review PR: review_rounds==2 anchored bot rounds (trailing clean comment excluded), 0 narrow-regex fix commits, Deploy-Preview/chatter/non-review-bot excluded"
else
  no "(3d) wrong: $RUN_OUT"
fi

echo "== 3e. comments-fetch degrade => gh api fails but emit stays success-shaped, legacy signals only =="
make_gh_stub botreview fail
run_gather "$PR_URL"
# `gh pr view` succeeds; `gh api .../issues/42/comments` exits 1. The gatherer must
# NOT emit unavailable — it degrades to the two legacy signals: 0 narrow-regex fix
# commits + 0 churn review objects => review_rounds == 0, no bot review_comments.
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | jq -e '
    (has("status") | not)
    and .repo=="acme/widgets" and .number==42
    and (.review_rounds == 0)
    and (.review_rounds_source == "none")
    and (.review_comments | length)==0
  ' >/dev/null 2>&1; then
  ok "comments fetch failure degrades to legacy signals: success shape, review_rounds==0 (source none), exit 0"
else
  no "(3e) wrong (rc=$RUN_RC): $RUN_OUT"
fi

echo "== 3f. hostile-typed comment elements => success shape (NEVER unavailable from comments), anchored rounds intact =="
make_gh_stub botreview hostile
run_gather "$PR_URL"
# The comments array is VALID but carries hostile-typed elements (non-string
# user.login/body/created_at). Pre-fix, {"user":{"login":123}} survived the bare
# ((.user.login)? // "") access and type-error-aborted the single jq invocation =>
# {"status":"unavailable","reason":"normalize_failed"} — violating the
# never-unavailable-from-comments invariant at the element level. With the
# strings-guarded accesses every hostile element degrades to a non-match: the 3
# well-formed claude[bot] comments still yield the same 2 anchored rounds as 3d; the
# marker-matching hostile[bot] comment with a NUMBER created_at must NOT add a third
# round (the strings guard empties $cat, so the anchor check drops it), though its
# well-typed body still appears in review_comments alongside the 3 claude[bot] ones.
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | jq -e '
    (has("status") | not)
    and .repo=="acme/widgets" and .number==42
    and (.review_rounds == 2)
    and (.review_rounds_source == "bot_comments")
    and (.review_comments | length)==4
    and ([.review_comments[] | select(.author=="claude[bot]")] | length)==3
    and ([.review_comments[] | select(.author=="hostile[bot]")] | length)==1
  ' >/dev/null 2>&1; then
  ok "hostile-typed comment elements degrade to non-matches: success shape, review_rounds==2 (number created_at not anchored), exit 0"
else
  no "(3f) wrong (rc=$RUN_RC): $RUN_OUT"
fi

echo "== 3g. HUB-shape PR (hub#146) => explicit 'PR #N review'/'review #N' headlines + Overview-headed bot comments both count 3 =="
make_gh_stub hubshape hubcomments
run_gather "$PR_URL"
# Both v14.23.1-missed signals must now independently land on 3: the three explicit
# "PR #42 review — …" / "review #2/#3 — …" headlines match the two new anchored
# review_fix_re alternations (=> 3 fix commits; tie order makes fix_commits the
# source), and the three "## Overview"-headed claude-bot comments with a later push
# match the widened anywhere-in-body marker (the 15:00 all-clear has no commit after
# it — no 4th round). Word-boundary negatives re-pinned against the new alternation
# AND the widened marker: the "deploy preview #2" commit must NOT flag is_review_fix,
# and the vercel[bot] "Deploy Preview" comment must match nowhere. review_comments
# carries all 4 marker-matching claude-bot comments (superset-of-rounds contract).
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | jq -e '
    (has("status") | not)
    and (.review_rounds == 3)
    and (.review_rounds_source == "fix_commits")
    and ([.commits[] | select(.is_review_fix)] | length)==3
    and ([.commits[] | select(.headline | test("preview"; "i")) | .is_review_fix] == [false])
    and (.review_comments | length)==4
    and ([.review_comments[] | select(.author=="claude[bot]")] | length)==4
    and ([.review_comments[] | select(.snippet | test("Deploy Preview"))] | length)==0
    and .agent_generated_guess==true
  ' >/dev/null 2>&1; then
  ok "HUB shape: review_rounds==3 (explicit fix headlines + anchored Overview-headed bot rounds agree), preview #2 commit and Deploy-Preview comment stay non-matching"
else
  no "(3g) wrong (rc=$RUN_RC): $RUN_OUT"
fi

echo "== 3h. hub#139 shape => 'address code review' headlines count; 'findings' alone stays rejected =="
make_gh_stub hub139
run_gather "$PR_URL"
# Pre-widening, the intervening "code" broke the "address(es)? review" adjacency:
# both explicit fix commits read is_review_fix:false and review_rounds fell back to
# the single formal churn review — the live hub#139 undercount of 1 (verified
# 2026-06-12, true ≈3). The widened "address(es)? (code )?review" must flag both
# (=> 2 fix commits, review_rounds == MAX(2, 1, 0) == 2, source fix_commits); the
# "add audit findings export" subject — a verified false-positive of the REJECTED
# broadened churn-word class — must stay non-matching.
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | jq -e '
    (has("status") | not)
    and ([.commits[] | select(.is_review_fix)] | length)==2
    and ([.commits[] | select(.headline | test("address code review"; "i")) | .is_review_fix] == [true, true])
    and ([.commits[] | select(.headline | test("audit findings"; "i")) | .is_review_fix] == [false])
    and (.review_rounds == 2)
    and (.review_rounds_source == "fix_commits")
  ' >/dev/null 2>&1; then
  ok "hub#139 shape: both 'address code review findings' commits flagged, review_rounds==2 (source fix_commits, was 1 via formal_reviews), 'findings' alone still rejected"
else
  no "(3h) wrong (rc=$RUN_RC): $RUN_OUT"
fi

echo "== 3i. provenance enrichment => pr_url (string), branch (string), changed_paths (array) on happy path =="
make_gh_stub ok
run_gather "$PR_URL"
# Learning Loop Phase 4 additive provenance: the gather now requests url/headRefName/files
# and emits pr_url/branch/changed_paths jq-natively. Happy-path fixture carries all three.
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | jq -e '
    (has("status") | not)
    and (.pr_url | type=="string") and (.pr_url == "https://github.com/acme/widgets/pull/42")
    and (.branch | type=="string") and (.branch == "feature/jwt-guard")
    and (.changed_paths | type=="array")
    and (.changed_paths == ["src/auth/jwt.guard.ts", "src/auth/jwt.guard.spec.ts"])
  ' >/dev/null 2>&1; then
  ok "provenance: pr_url string, branch string, changed_paths array of paths, all sourced jq-natively"
else
  no "(3i) wrong (rc=$RUN_RC): $RUN_OUT"
fi

echo "== 3j. large multibyte comments array => gather completes (NO wedge), success object, all bot rounds classified =="
make_gh_stub botreview bigcomments
run_gather_bounded 25 "$PR_URL"
# Production-wedge regression: a real >64KB issue-comment array hung the gather for
# MINUTES inside classify-bot-review.sh (bash-3.2 O(n^2) ${//[[:space:]]/}). The gather
# must now finish far inside the 25s watchdog (RUN_TIMEDOUT==0) and emit a SUCCESS
# object. All 60 claude[bot] comments classify IN (each carries the word-bounded
# "review" marker) and anchor a round (created_at 07:00 precedes the 08:00 first
# commit), so review_rounds is bot_comments-sourced and review_comments lists all 60.
if [ "$RUN_TIMEDOUT" -eq 0 ] && [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | jq -e '
    (has("status") | not)
    and (.review_comments | length)==60
    and ([.review_comments[] | select(.author=="claude[bot]")] | length)==60
    and (.review_rounds >= 1)
    and (.review_rounds_source == "bot_comments")
  ' >/dev/null 2>&1; then
  ok "large multibyte comments array: gather emits success object, 60 bot rounds classified, no wedge (watchdog never fired)"
else
  no "(3j) wrong (RUN_TIMEDOUT=${RUN_TIMEDOUT:-?} RUN_RC=$RUN_RC): $(printf '%s' "$RUN_OUT" | head -c 220)"
fi

echo "== 4. injection-safety => quotes/backslashes/newlines round-trip as valid JSON =="
make_gh_stub inject
run_gather "$PR_URL"
# Must be valid JSON, must carry the agent guess from the body, and the snippet must
# have had its newline collapsed (control chars stripped) — no parse break. The
# provenance fields carry quotes/backslashes too: branch + changed_paths must round-trip
# as valid JSON (no parse break, no interpolation hazard).
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | jq -e '
    (has("status") | not)
    and (.title | test("auth"))
    and .agent_generated_guess==true
    and (.review_comments[0].snippet | test("\n") | not)
    and (.review_comments[0].author=="rev\"er")
    and (.branch == "feature/\"weird\" \\ branch")
    and (.changed_paths == ["src/\"quoted\".ts", "src/back\\slash.ts"])
  ' >/dev/null 2>&1; then
  ok "injection-safe: quotes/backslashes/newline round-trip (incl. provenance branch/changed_paths), snippet de-newlined, valid JSON"
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
