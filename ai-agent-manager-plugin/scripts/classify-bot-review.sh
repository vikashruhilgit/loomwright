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
#   HOSTILE-TYPED ELEMENTS: a VALID array whose elements carry non-string
#              `.user.login` / `.body` values does not abort the program — every
#              field access is double-guarded (the error-suppressing (…)? form
#              absorbs path-access errors on non-object parents, and `| strings`
#              drops non-string VALUES so the // default applies). A hostile
#              element simply degrades to a non-match and is dropped.
# ============================================================================
#
# CLASSIFICATION REGEXES (the single source of truth — defined ONLY here):
#   bot_author_re  — author login looks like a review bot: literal "claude" or
#                    "claude[bot]", any "*[bot]" suffix, or a "github-actions"
#                    prefix. Case-insensitive.
#   review_marker_re — the RAW body carries a word-bounded "review" ANYWHERE
#                    (Oniguruma \b), so "Deploy Preview"/"preview" can NEVER
#                    match (no word boundary inside "preview"). Case-insensitive.
#
# These mirror the patterns previously inlined in pr-postmortem-gather.sh; that
# script now pipes its fetched comments through this helper so the patterns are
# not duplicated.

set -euo pipefail

# jq absent → fail-safe empty array, exit 0 (never crash a caller).
if ! command -v jq >/dev/null 2>&1; then
  printf '[]\n'
  exit 0
fi

INPUT="$(cat 2>/dev/null || true)"

# Blank / missing stdin → [].
if [ -z "${INPUT//[[:space:]]/}" ]; then
  printf '[]\n'
  exit 0
fi

# The whole filter runs inside ONE jq program. A leading `if type=="array"`
# guard degrades non-array (and, via the outer 2>/dev/null fallback, invalid)
# JSON to []. Every per-element field access is strings-guarded so hostile-typed
# elements degrade to non-matches rather than aborting the program.
OUTPUT="$(printf '%s' "$INPUT" | jq -c '
  # ---- SINGLE SOURCE OF TRUTH: bot-review classification regexes ----
  def bot_author_re: "^claude(\\[bot\\])?$|\\[bot\\]$|^github-actions";
  def review_marker_re: "\\breview\\b";

  if type=="array" then
    [ .[]?
      | select(
          ((((.user.login)? | strings) // "") | test(bot_author_re; "i"))
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
