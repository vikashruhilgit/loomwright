#!/usr/bin/env bash
# classify-bot-review.sh — SINGLE SOURCE OF TRUTH for bot-authored review-comment
# classification. Shared by pr-postmortem-gather.sh and (Subtask 2) the
# --until-mergeable drain loop, so the bot_author_re / review_marker_re patterns
# live in EXACTLY ONE place.
#
# ============================== INTERFACE (PIN) ==============================
# Callers may rely on this contract WITHOUT reading the body:
#
#   INPUT  (stdin): a JSON ARRAY of comment-like objects. Each element SHOULD
#                   carry at least `.user.login` and `.body`. Extra fields
#                   (id, html_url, created_at, …) are PRESERVED on output so
#                   downstream callers keep their metadata. The classifier works
#                   on ANY array of comment objects — PR issue comments, formal
#                   review bodies, or inline-thread comment bodies — because it
#                   classifies purely on the (.user.login, .body) pair. It does
#                   NOT hard-code any workflow filename (e.g. claude-code-review.yml);
#                   matching is generic via the two regexes below.
#
#   OUTPUT (stdout): a JSON ARRAY (compact, one line) containing ONLY the input
#                   elements classified as BOT-AUTHORED REVIEW FINDINGS — i.e.
#                   `.user.login` matches bot_author_re AND `.body` matches
#                   review_marker_re (both case-insensitive). Each retained
#                   element is passed through UNCHANGED (the full original object),
#                   so {id, user.login, body, html_url, created_at} survive when
#                   present.
#
#   FAIL-SAFE: empty input, missing/blank stdin, non-array input, invalid JSON,
#              or a missing jq all degrade to `[]` on stdout and exit 0. This
#              helper NEVER crashes a caller and NEVER exits non-zero on a data
#              problem (it only ever emits a JSON array + exit 0).
#
#   NEVER-HANGS: the stdin read is BOUNDED (`read -t`, default 10s, overridable via
#              CLASSIFY_STDIN_TIMEOUT) and the blank-check is an early-exit `case`
#              glob — NOT an O(n^2) ${//} pattern substitution. So a never-closing
#              stdin OR a large multibyte comment array degrades to `[]` quickly
#              instead of wedging, even under concurrent invocation. (Before this,
#              a plain `cat` could block forever on a missing stdin, and the O(n^2)
#              whitespace-strip wedged bash 3.2 for minutes on ~96KB arrays.) On a
#              read TIMEOUT a one-line breadcrumb is written to STDERR (stdout stays
#              `[]`), so a timeout is distinguishable from an empty endpoint in logs.
#
#   HOSTILE-TYPED ELEMENTS: a VALID array whose elements carry non-string
#              `.user.login` / `.body` values does not abort the program — every
#              field access is double-guarded (the error-suppressing (…)? form
#              absorbs path-access errors on non-object parents, and `| strings`
#              drops non-string VALUES so the // default applies). A hostile
#              element simply degrades to a non-match and is dropped.
# ============================================================================
#
# CLASSIFICATION REGEXES (the single source of truth — defined ONLY here):
#   bot_author_re  — author login looks like a review bot: an EXACT match on
#                    "claude[bot]", "github-actions[bot]", or "dependabot[bot]",
#                    or any login ending in "[bot]". A bare "claude" (human) or
#                    a "github-actions"-prefixed non-bot login is NOT matched
#                    (tightened red-team-hardening item 08). Case-insensitive.
#   review_marker_re — the RAW body carries, ANYWHERE, a word-bounded REVIEW STEM
#                    ("review", "reviews", "reviewed", "reviewer(s)", "reviewing")
#                    or "finding(s)" (Oniguruma \b). Case-insensitive. Widened from
#                    the bare lexeme `\breview\b` after PR #223 (2026-09-14): the
#                    claude[bot] issue comment opened "Reviewed <sha>. … Two minor
#                    findings, both low severity: 1. … 2. …" and never used the bare
#                    word, so a real finding was silently dropped by the
#                    --until-mergeable drain — the exact #64 class the issue-comment
#                    channel exists for. A marker that matches one inflection of a
#                    word a reviewer conjugates freely is a false negative waiting to
#                    happen; the stem closes the whole class, not one spelling. The
#                    word boundary is still load-bearing: "Deploy Preview"/"preview"/
#                    "previewed" can NEVER match (no boundary inside "preview").
#                    False-positive posture is unchanged and deliberate — the drain's
#                    validate-then-fix step dismisses an ungroundable candidate, so
#                    a looser marker costs a validation, a tighter one loses a finding.
#
# These mirror the patterns previously inlined in pr-postmortem-gather.sh; that
# script now pipes its fetched comments through this helper so the patterns are
# not duplicated.
#
# ACTOR ALLOWLIST (--trusted-actors <file>, red-team-hardening item 01, decision
# R2): OPTIONAL. When passed, the file is expected to be a JSON array of EXACT
# GitHub logins (user-scope, e.g. `~/.claude/loomwright/trusted-actors.json` —
# resolving that default path is the CALLER's job, not this script's). When the
# resolved file is present, readable, and a valid JSON array, `bot_author_re`
# is NOT consulted at all — author classification becomes an EXACT match
# against that list (the `review_marker_re` body-content gate still applies,
# unchanged, as an AND condition). When --trusted-actors is passed but the file
# is missing/unreadable/not-an-array, this script falls back to the built-in
# `bot_author_re` (unchanged pre-existing behavior) and logs ONE line to
# stderr: `classify-bot-review: actor_allowlist_absent`. When --trusted-actors
# is NOT passed at all, behavior is 100% unchanged (existing callers keep
# working exactly as before — no log line, no opt-in).

set -euo pipefail

TRUSTED_ACTORS_FILE=""
TRUSTED_ACTORS_GIVEN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --trusted-actors)
      TRUSTED_ACTORS_FILE="${2:-}"
      TRUSTED_ACTORS_GIVEN=1
      shift
      if [ $# -gt 0 ]; then shift; fi
      ;;
    --trusted-actors=*)
      TRUSTED_ACTORS_FILE="${1#--trusted-actors=}"
      TRUSTED_ACTORS_GIVEN=1
      shift
      ;;
    *)
      shift
      ;;
  esac
done

# jq absent → fail-safe empty array, exit 0 (never crash a caller).
if ! command -v jq >/dev/null 2>&1; then
  printf '[]\n'
  exit 0
fi

# Resolve the actor-allowlist mode. USE_TRUSTED_ACTORS=1 => exact-match mode
# (bot_author_re not consulted); =0 => existing bot_author_re path (either
# --trusted-actors was never passed, or its file is unusable — logged once).
USE_TRUSTED_ACTORS=0
TRUSTED_ACTORS_JSON='[]'
if [ "$TRUSTED_ACTORS_GIVEN" -eq 1 ]; then
  if [ -n "$TRUSTED_ACTORS_FILE" ] && [ -r "$TRUSTED_ACTORS_FILE" ]; then
    _ta="$(jq -c '.' "$TRUSTED_ACTORS_FILE" 2>/dev/null || true)"
    if [ -n "$_ta" ] && printf '%s' "$_ta" | jq -e 'type=="array"' >/dev/null 2>&1; then
      TRUSTED_ACTORS_JSON="$_ta"
      USE_TRUSTED_ACTORS=1
    fi
  fi
  if [ "$USE_TRUSTED_ACTORS" -eq 0 ]; then
    printf 'classify-bot-review: actor_allowlist_absent (falling back to bot_author_re)\n' >&2
  fi
fi

# Read all of stdin, but with a BOUNDED wait so a missing or never-closing stdin
# (no pipe at all, or a slow/stuck producer under concurrent load) can NEVER wedge
# this fail-safe helper — its contract is "always exit 0 QUICKLY". `-d ''` reads
# through to EOF (a NUL byte never appears in JSON comment text, so it is never an
# early stop); `-t` caps the wait at CLASSIFY_STDIN_TIMEOUT seconds (default 10;
# bash 3.2 accepts integer seconds only). Because no NUL delimiter is ever seen,
# `read` returns NON-ZERO on the normal EOF path too, so we deliberately ignore its
# rc (|| true) and act on the bytes captured in INPUT (empty/partial on timeout,
# which the blank-check below degrades to []). This replaces a plain `cat`, which
# blocks forever when stdin is never closed.
INPUT=""
_read_rc=0
_stdin_t0=$SECONDS
IFS= read -r -d '' -t "${CLASSIFY_STDIN_TIMEOUT:-10}" INPUT || _read_rc=$?

# Best-effort debug breadcrumb (advisory; NEVER changes the []-and-exit-0 fail-safe):
# distinguish a stdin TIMEOUT from a genuinely empty endpoint when debugging. bash 4+
# returns >128 from `read -t` on timeout; bash 3.2 returns 1 for BOTH timeout and clean
# EOF, so we also treat "waited ~the whole window" (integer SECONDS) as the timeout
# signal. Goes to STDERR only — stdout stays the JSON-array contract.
if [ "$_read_rc" -gt 128 ] || [ "$(( SECONDS - _stdin_t0 ))" -ge "${CLASSIFY_STDIN_TIMEOUT:-10}" ]; then
  printf 'classify-bot-review: stdin read timed out after %ss; degrading to []\n' "${CLASSIFY_STDIN_TIMEOUT:-10}" >&2
fi

# Blank / missing stdin → []. Use a `case` glob that EARLY-EXITS on the first
# non-whitespace byte. Do NOT use ${INPUT//[[:space:]]/} here: that is an O(n^2)
# pattern SUBSTITUTION (it rebuilds the entire string) that wedges bash 3.2 for
# MINUTES on large multibyte input — a real, reproduced hang on ~96KB issue-comment
# arrays (e.g. PR #54), non-deterministically triggered under concurrent CPU
# pressure. The case form scans only until the first non-space char, so a real JSON
# array returns in microseconds and even an all-whitespace input stays bounded.
case "$INPUT" in
  *[![:space:]]*) : ;;            # has a non-whitespace byte → proceed
  *) printf '[]\n'; exit 0 ;;     # empty or whitespace-only → []
esac

# The whole filter runs inside ONE jq program. A leading `if type=="array"`
# guard degrades non-array (and, via the outer 2>/dev/null fallback, invalid)
# JSON to []. Every per-element field access is strings-guarded so hostile-typed
# elements degrade to non-matches rather than aborting the program.
OUTPUT="$(printf '%s' "$INPUT" | jq -c \
  --argjson use_trusted "$( [ "$USE_TRUSTED_ACTORS" -eq 1 ] && echo true || echo false )" \
  --argjson trusted_actors "$TRUSTED_ACTORS_JSON" '
  # ---- SINGLE SOURCE OF TRUTH: bot-review classification regexes ----
  # EXACT-login match for the three known bot accounts, plus any login ending in
  # `[bot]` (GitHub App convention). Deliberately NOT "^claude$" (a human could
  # register that literal login) and NOT "^github-actions" as a bare prefix (that
  # matched "github-actions-fan", not just the real actor) — tightened 2026-09-23.
  def bot_author_re: "^(claude\\[bot\\]|github-actions\\[bot\\]|dependabot\\[bot\\])$|\\[bot\\]$";
  def review_marker_re: "\\b(review(s|ed|er|ers|ing)?|findings?)\\b";
  # Author gate: EXACT match against $trusted_actors when --trusted-actors
  # resolved a usable file ($use_trusted); otherwise the unchanged regex.
  # NOTE: the $login parameter is $-PREFIXED deliberately (jq VALUE-binding
  # semantics, jq 1.6+) -- a plain def author_ok(login): binds login as a
  # FILTER (call-by-name), so ($trusted_actors | index(login)) would silently
  # re-invoke that filter with . = $trusted_actors at the point of use (the
  # login extraction would then see an ARRAY, not the original comment
  # object, and always resolve to empty -- reproduced live: author_ok
  # returned false for an exact-listed login until this was fixed).
  def author_ok($login):
    if $use_trusted then
      (($trusted_actors | index($login)) != null)
    else
      ($login | test(bot_author_re; "i"))
    end;

  if type=="array" then
    [ .[]?
      | select(
          author_ok((((.user.login)? | strings) // ""))
          and (((((.body)? | strings) // "") | gsub("[[:space:]]+"; "")) != "")
          and ((((.body)? | strings) // "") | test(review_marker_re; "i"))
        ) ]
  else
    []
  end
' 2>/dev/null || true)"

# Defensive: empty / non-JSON jq output → [].
if [ -z "$OUTPUT" ] || ! printf '%s' "$OUTPUT" | jq -e . >/dev/null 2>&1; then
  printf '[]\n'
  exit 0
fi

printf '%s\n' "$OUTPUT"
exit 0
