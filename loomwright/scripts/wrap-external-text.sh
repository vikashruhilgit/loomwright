#!/usr/bin/env bash
# wrap-external-text.sh — MECHANIZED untrusted-text envelope (red-team-hardening
# item 01, decision R4). Wraps every externally-sourced review-channel body the
# review-heal drain reads (skills/review-heal/SKILL.md §U1) in a fixed
# `<<<EXTERNAL_TEXT …>>> … <<<END_EXTERNAL_TEXT>>>` envelope BEFORE it ever
# reaches the model — the envelope is produced by THIS SCRIPT, never typed by
# the model itself, so its shape cannot drift round to round.
#
# ============================== INTERFACE (PIN) ==============================
# Callers may rely on this contract WITHOUT reading the body:
#
#   USAGE: wrap-external-text.sh --channel <name> [--trusted-actors <file>]
#
#   INPUT  (stdin): a JSON ARRAY of channel items. Each element SHOULD carry a
#                   login at `.user.login` OR `.author.login`, and body text at
#                   `.body` OR `.output.text` OR `.message` OR `.title` (in that
#                   preference order — covers formal reviews / issue comments /
#                   review threads via the first two, check-run output/
#                   annotations via the rest). Extra fields are ignored (this
#                   script does not pass metadata through — callers that need
#                   the original object keep their own copy; this script only
#                   ever emits the enveloped TEXT).
#
#   OUTPUT (stdout): one envelope per input element THAT HAS non-empty body
#                   text (an element with no extractable body text is skipped
#                   — there is nothing to wrap):
#
#                     <<<EXTERNAL_TEXT channel=<c> actor=<login> trusted=<yes|no>>>>
#                     <body text, verbatim except delimiter-forgery defanging —
#                      see DELIMITER DEFENSE below>
#                     <<<END_EXTERNAL_TEXT>>>
#
#                   `channel` is the --channel value (required; defaults to
#                   "unknown" if omitted — never a fatal error, per the
#                   fail-safe contract below). `actor` is the extracted login,
#                   or the literal "unknown" when absent. `trusted` is "yes"
#                   ONLY when `actor` is an EXACT match in the resolved
#                   trusted-actors list (see TRUST RESOLUTION below); "no"
#                   otherwise — INCLUDING when no trusted-actors file exists at
#                   all (fail-CLOSED: an unclassifiable actor is never trusted).
#
#   TRUST RESOLUTION: --trusted-actors <file> overrides the default user-scope
#                   path `~/.claude/loomwright/trusted-actors.json` (a JSON
#                   array of exact GitHub logins). When the resolved file is
#                   missing or unreadable, EVERY actor is trusted=no (there is
#                   no bot_author_re fallback here — that regex lives ONLY in
#                   classify-bot-review.sh and governs FINDING classification,
#                   not envelope trust; a body can be wrapped and STILL
#                   dismissed downstream by validate-then-fix regardless of
#                   this field).
#
#   FAIL-SAFE: empty input, missing/blank stdin, non-array input, invalid JSON,
#              or a missing jq all degrade to EMPTY stdout and exit 0. This
#              helper NEVER crashes a caller and NEVER exits non-zero on a data
#              problem (mirrors classify-bot-review.sh's contract exactly).
#
#   NEVER-HANGS: the stdin read is BOUNDED (`read -t`, default 10s, overridable
#              via WRAP_STDIN_TIMEOUT) and the blank-check is an early-exit
#              `case` glob — NOT an O(n^2) ${//} pattern substitution (see
#              classify-bot-review.sh's header for the reproduced-hang history
#              this mirrors).
#
#   HOSTILE-TYPED ELEMENTS: a VALID array whose elements carry non-string
#              login/body values does not abort the program — every field
#              access is `strings`-guarded so a hostile element degrades to an
#              empty/absent extraction rather than a jq crash.
#
#   DELIMITER DEFENSE (PR #248 review finding #2): before a body is embedded
#              between the real markers, any LITERAL occurrence of the
#              envelope delimiter sequences `<<<EXTERNAL_TEXT` or
#              `<<<END_EXTERNAL_TEXT>>>` INSIDE the body is defanged — a
#              zero-width space (U+200B) is inserted immediately after the
#              `<<<` of either sequence. This stops a PR comment body that
#              contains a literal `<<<END_EXTERNAL_TEXT>>>` followed by a
#              fabricated `<<<EXTERNAL_TEXT channel=... actor=<other>
#              trusted=yes>>>` from forging a second, attacker-controlled
#              envelope with attribution the model would read as ground
#              truth — the fake markers no longer byte-match the real ones,
#              so only the boundaries THIS SCRIPT emits (the true start line
#              and the true `<<<END_EXTERNAL_TEXT>>>` line) survive as exact
#              matches. The rest of the body text is left intact and
#              readable — this narrows what a forged marker can claim to be,
#              it does not remove or rewrite the attacker's words.
# ============================================================================
#
# WHY THIS EXISTS (decision R4): untrusted-text handling is prose + mechanism,
# not prose alone. skills/review-heal/SKILL.md §U1 references this script by
# name for the wrap step — it does not hand-author the envelope format itself.
# See docs/HOOKS.md for the explicit non-goal: this is a TRIPWIRE + NARROWING,
# not a sandboxing/isolation claim, and it does not attempt to sanitize
# hidden-character tricks beyond the envelope itself (an honest limit).
# HONEST LIMIT (delimiter defense, PR #248 finding #2): the defanging above
# closes the exact-literal-delimiter forgery case; it is still a narrowing/
# tripwire, not a cryptographic guarantee — a sufficiently creative Unicode
# look-alike or homoglyph of the marker text is not defended against, only
# the literal ASCII delimiter strings this script itself emits.

set -u

log() { printf 'wrap-external-text: %s\n' "$1" >&2; }

CHANNEL="unknown"
TRUSTED_FILE="${HOME:-}/.claude/loomwright/trusted-actors.json"
while [ $# -gt 0 ]; do
  case "$1" in
    --channel)
      CHANNEL="${2:-unknown}"
      shift; [ $# -gt 0 ] && shift
      ;;
    --channel=*)
      CHANNEL="${1#--channel=}"
      shift
      ;;
    --trusted-actors)
      TRUSTED_FILE="${2:-}"
      shift; [ $# -gt 0 ] && shift
      ;;
    --trusted-actors=*)
      TRUSTED_FILE="${1#--trusted-actors=}"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

# jq absent -> fail-safe empty output, exit 0 (never crash a caller).
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Bounded stdin read — see classify-bot-review.sh's header for the reproduced
# hang history this mirrors (a plain `cat` blocks forever on a never-closing
# stdin; an O(n^2) whitespace-strip wedges bash 3.2 on large multibyte input).
INPUT=""
_read_rc=0
IFS= read -r -d '' -t "${WRAP_STDIN_TIMEOUT:-10}" INPUT || _read_rc=$?
[ "$_read_rc" -gt 128 ] 2>/dev/null && log "stdin read timed out after ${WRAP_STDIN_TIMEOUT:-10}s; degrading to empty output"

case "$INPUT" in
  *[![:space:]]*) : ;;                 # has a non-whitespace byte -> proceed
  *) exit 0 ;;                          # empty/whitespace-only -> empty output
esac

# Resolve the trusted-actors JSON array (empty array when the file is absent,
# unreadable, or not valid JSON — every actor then classifies trusted=no).
TRUSTED_JSON='[]'
if [ -n "$TRUSTED_FILE" ] && [ -r "$TRUSTED_FILE" ]; then
  _t="$(jq -c '.' "$TRUSTED_FILE" 2>/dev/null || true)"
  if [ -n "$_t" ] && printf '%s' "$_t" | jq -e 'type=="array"' >/dev/null 2>&1; then
    TRUSTED_JSON="$_t"
  fi
fi

printf '%s' "$INPUT" | jq -r \
  --arg channel "$CHANNEL" \
  --argjson trusted "$TRUSTED_JSON" '
  def s(v): (v? | strings) // "";
  # defang(body) — decision R4 follow-up (PR #248 review finding #2): neutralize
  # any LITERAL occurrence of the envelope delimiter sequences inside untrusted
  # body text, so a forged "<<<END_EXTERNAL_TEXT>>>" + fake re-opening
  # "<<<EXTERNAL_TEXT ...>>>" embedded in a comment cannot fabricate a second,
  # attacker-controlled envelope (with its own actor/trusted/channel) that the
  # model would read as ground truth. Inserts a zero-width space (U+200B)
  # immediately after the "<<<" of either sequence — invisible to a human/model
  # reading the text, but it breaks an EXACT string match against the real
  # boundary markers this script itself emits below, so only the true,
  # script-generated start/end markers survive intact. Narrowing/tripwire, not
  # a cryptographic guarantee — see the header INTERFACE note + docs/HOOKS.md.
  def defang(body): body | gsub("<<<(?<tag>EXTERNAL_TEXT|END_EXTERNAL_TEXT>>>)"; "<<<\u200b\(.tag)");
  if type=="array" then
    [ .[]?
      | ( (s(.user.login)) as $ul
          | (s(.author.login)) as $al
          | if ($ul != "") then $ul elif ($al != "") then $al else "unknown" end
        ) as $actor
      | ( (s(.body)) as $b
          | (s(.output.text)) as $ot
          | (s(.message)) as $m
          | (s(.title)) as $ti
          | if ($b != "") then $b
            elif ($ot != "") then $ot
            elif ($m != "") then $m
            elif ($ti != "") then $ti
            else "" end
        ) as $body_raw
      | select($body_raw != "")
      | defang($body_raw) as $body
      | ( ($trusted | index($actor)) != null ) as $is_trusted
      | "<<<EXTERNAL_TEXT channel=" + $channel + " actor=" + $actor + " trusted=" + (if $is_trusted then "yes" else "no" end) + ">>>\n" + $body + "\n<<<END_EXTERNAL_TEXT>>>"
    ] | join("\n\n")
  else
    empty
  end
' 2>/dev/null || true

exit 0
