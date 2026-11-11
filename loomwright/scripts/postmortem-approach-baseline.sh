#!/usr/bin/env bash
# postmortem-approach-baseline.sh — ONE-SHOT, READ-ONLY baseline estimate of the per-round
# `approach_challenged` flag over the postmortem churn ledger (.supervisor/postmortem/results.jsonl).
#
# WHY: `/pr-postmortem` records `approach_challenged` (the reviewer questioned the chosen approach,
# library, tool or mechanism rather than the code's correctness, in any one of the round's findings,
# even alongside correctness findings — skills/pr-postmortem/SKILL.md
# §"Optional `approach_challenged` flag") only on lines it writes from now on. Older lines carry no
# such signal, so this script prints a labelled GUESS for them: a case-insensitive phrase match of
# each round's `evidence`, OR-ed (unless --no-gh) with the same match over that PR's
# `review_comments[].snippet` from the read-only gather `pr-postmortem-gather.sh`.
#
# Usage:
#   postmortem-approach-baseline.sh [--ledger <path>] [--fixture <dir>] [--no-gh]
#     --ledger <path>  ledger to read (default: <git root or cwd>/.supervisor/postmortem/results.jsonl)
#     --fixture <dir>  test mode: the ledger is <dir>/results.jsonl (the gather still resolves `gh`
#                      from PATH, so a test places a stub `gh` first on PATH)
#     --no-gh          never run the gather and never call `gh`; evidence-only guess
#
# OUTPUT (stdout): one TSV row per categorized round, columns
#   pr <TAB> round <TAB> class <TAB> approach_challenged_guess <TAB> snippet
# where approach_challenged_guess is `true|false` (a guess) or `recorded:true|recorded:false` when the
# round already carries a boolean `approach_challenged` (a recorded flag always wins over the guess),
# and snippet is the round's `evidence` with tabs / newlines / CRs replaced by spaces (one row per
# round). The LAST line is the summary:
#   approach_challenged: N of M categorized rounds (guess; E entries, G gathered, U gather-unavailable)
# N / M count GUESSED rounds only; recorded rounds are never mixed into that rate — when any exist the
# parenthesis gains `; recorded: K of R rounds`. E counts live entries with at least one categorized
# round; G / U count the entries that needed a guess and whose PR comments were / were not gathered
# (`--no-gh`, no usable `pr_url`, `gh` or the gather missing, or the gather answering unavailable).
# Known over-count: a matching PR comment marks EVERY guessed round of that entry `true` (the gather
# has no per-round link), and a correctness question that happens to use a phrase also matches — the
# snippet column is there so a human can correct the number by hand.
#
# ENTRIES READ: every data line (any `source`) except curation records, minus the entries a
# well-formed curation record retracts or supersedes — the SAME exclusion read-postmortem.sh applies
# (target_key equals the entry's `automate_key` OR `pr_url`; a record whose target_key is missing,
# null, non-string or empty curates nothing). Reimplemented here by reading, never by sourcing a
# writer. No staleness window and no repo scoping: a baseline wants the whole history.
#
# WRITES NOTHING: no ledger write, no file write, no `gh` mutation. The ledger's writers stay
# `/pr-postmortem` (data lines, Step 5), `automate-helpers.sh learning-emit` (automate_drain lines)
# and `curate-postmortem.sh` (curation records); the guess is printed, never copied into the ledger.
# The only `gh` traffic is the gather's own read path (`gh pr view`, `gh api …/comments`, `gh api user`).
#
# FAIL-SAFE (bimodal-failure philosophy — this is a reader): ALWAYS exit 0.
#   - jq absent                      → nothing on stdout, reason on stderr
#   - ledger absent / not a file / unreadable
#                                    → no rows, summary `approach_challenged: 0 of 0 categorized
#                                      rounds (ledger unreadable: <reason>)`, reason on stderr
#   - a malformed JSONL line         → skipped element-locally (`fromjson?` per line)
#   - a non-object round / non-string evidence → skipped / stringified, never a crash
# jq-only parsing: ledger and gather text is never interpolated into a shell command or a jq
# program; it crosses into jq via --arg / --argjson only.

set -uo pipefail   # `set -e` intentionally omitted — a read must never fail its caller.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
GATHER="$HERE/pr-postmortem-gather.sh"

# The phrase heuristic — ONE array, case-insensitive jq regexes matched against a round's
# `evidence` and against gathered review-comment snippets. The human rule it approximates lives in
# skills/pr-postmortem/SKILL.md §"Optional `approach_challenged` flag".
APPROACH_PHRASES_JSON='["why not","\\buse\\b.{1,60}\\binstead\\b","already provides","simpler to","reinvent","\\b(platform|sdk|library|harness)\\b.{0,20}\\balready\\b"]'

usage() {
  cat <<'USAGE'
Usage: postmortem-approach-baseline.sh [--ledger <path>] [--fixture <dir>] [--no-gh]
  --ledger <path>  ledger to read (default: <git root or cwd>/.supervisor/postmortem/results.jsonl)
  --fixture <dir>  test mode: the ledger is <dir>/results.jsonl
  --no-gh          never run the gather and never call gh; evidence-only guess
Read-only; always exits 0. Prints one TSV row per categorized round, then a summary line.
USAGE
}

LEDGER=""; NO_GH=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --ledger)  [ "$#" -ge 2 ] || { echo "postmortem-approach-baseline: --ledger needs a path" >&2; exit 0; }
               LEDGER="$2"; shift 2 ;;
    --fixture) [ "$#" -ge 2 ] || { echo "postmortem-approach-baseline: --fixture needs a directory" >&2; exit 0; }
               LEDGER="${2%/}/results.jsonl"; shift 2 ;;
    --no-gh)   NO_GH=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)         echo "postmortem-approach-baseline: unknown argument: $1" >&2; usage >&2; exit 0 ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "postmortem-approach-baseline: jq unavailable — emitting nothing (fail-safe)" >&2
  exit 0
fi

if [ -z "$LEDGER" ]; then
  root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  LEDGER="$root/.supervisor/postmortem/results.jsonl"
fi

unreadable() {
  echo "postmortem-approach-baseline: ledger unreadable ($1): $LEDGER" >&2
  printf '%s\n' "approach_challenged: 0 of 0 categorized rounds (ledger unreadable: $1)"
  exit 0
}
[ -e "$LEDGER" ] || unreadable "absent"
[ -f "$LEDGER" ] || unreadable "not_a_file"
[ -r "$LEDGER" ] || unreadable "unreadable"

# 1. Live entries with their categorized rounds. Per-line `fromjson?` so one malformed line is
#    skipped without losing the rest. Curation exclusion mirrors read-postmortem.sh exactly.
ENTRIES_JSON="$(
  jq -R 'fromjson? // empty' "$LEDGER" 2>/dev/null | jq -s -c --argjson phrases "$APPROACH_PHRASES_JSON" '
    def str: if type == "string" then . elif . == null then "" else tostring end;
    def matches: str as $t | any($phrases[]; . as $p | $t | test($p; "i"));
    ([ .[]
       | select(type == "object")
       | select((.source // "") == "curation")
       | select(has("target_key") and ((.target_key | type) == "string") and (.target_key != ""))
       | .target_key
     ] | map({(.): true}) | add // {}) as $curated
    | [ .[]
        | select(type == "object")
        | . as $e
        | select((($e.source) // "") != "curation")
        | (((($e.automate_key) // "") | if type == "string" then . else "" end)) as $akey
        | (((($e.pr_url) // "") | if type == "string" then . else "" end)) as $purl
        | select((($curated[$akey] // false) or ($curated[$purl] // false)) | not)
        | ((($e.categories) // []) | if type == "array" then map(select(type == "object")) else [] end) as $cats
        | select(($cats | length) > 0)
        | { pr_url: $purl,
            pr: (if $purl != "" then $purl
                 else ((($e.repo // "") | str) + "#" + (($e.number // "") | str)) end),
            rounds: [ $cats[]
              | { round: ((.round // "") | str),
                  class: ((.class // "") | str),
                  recorded: (if has("approach_challenged") and ((.approach_challenged | type) == "boolean")
                             then .approach_challenged else null end),
                  ev_match: ((.evidence // "") | matches),
                  snippet: ((.evidence // "") | str) } ] } ]
  ' 2>/dev/null
)"
if [ -z "$ENTRIES_JSON" ]; then
  unreadable "query_failed"
fi

# 2. Gather OR (skipped under --no-gh). One read-only gather per distinct PR URL that still needs a
#    guess; the result is a jq object {pr_url: true|false} held in a shell variable — nothing is
#    written to disk. A PR the gather cannot read stays out of the map (counted gather-unavailable).
GMAP='{}'
if [ "$NO_GH" -eq 0 ] && command -v "${GH_BIN:-gh}" >/dev/null 2>&1 && [ -r "$GATHER" ]; then
  urls="$(printf '%s' "$ENTRIES_JSON" | jq -r '
    [ .[] | select(any(.rounds[]; .recorded == null)) | .pr_url
      | select(. != "" and (test("[\\r\\n\\t]") | not)) ] | unique | .[]' 2>/dev/null)"
  total="$(printf '%s\n' "$urls" | grep -c . 2>/dev/null || true)"
  i=0
  while IFS= read -r url; do
    [ -n "$url" ] || continue
    i=$((i + 1))
    case "$i" in *0) echo "postmortem-approach-baseline: gather $i/$total" >&2 ;; esac
    g="$(bash "$GATHER" "$url" 2>/dev/null)"
    m="$(printf '%s' "$g" | jq -c --argjson phrases "$APPROACH_PHRASES_JSON" '
      if type == "object" and (has("status") | not) then
        [ (.review_comments // [])[]? | .snippet? | strings ]
        | any(.[]; . as $s | any($phrases[]; . as $p | $s | test($p; "i")))
      else null end' 2>/dev/null)"
    case "$m" in
      true|false)
        GMAP="$(jq -cn --argjson m "$GMAP" --arg k "$url" --argjson v "$m" '$m + {($k): $v}' 2>/dev/null || printf '%s' "$GMAP")" ;;
    esac
  done <<EOF
$urls
EOF
fi

# 3. Rows + summary, built in jq from data only.
OUT="$(printf '%s' "$ENTRIES_JSON" | jq -r --argjson gmap "$GMAP" '
  def clean: gsub("[\t\n\r]"; " ");
  . as $entries
  | [ $entries[] | . as $e
      | (($e.pr_url != "") and ($gmap | has($e.pr_url))) as $gathered
      | (if $gathered then $gmap[$e.pr_url] else false end) as $gm
      | $e.rounds[]
      | { pr: $e.pr, round, class, snippet,
          recorded: .recorded,
          guess: (if .recorded == null then (.ev_match or $gm) else null end) } ] as $rows
  | ([ $entries[] | select(any(.rounds[]; .recorded == null)) ]) as $needing
  | ([ $needing[] | .pr_url as $u | select($u != "" and ($gmap | has($u))) ] | length) as $g
  | ([ $rows[] | select(.recorded == null) ]) as $guessed
  | ([ $rows[] | select(.recorded != null) ]) as $rec
  | ($rows[]
     | [ (.pr | clean), (.round | clean), (.class | clean),
         (if .recorded != null then "recorded:" + (.recorded | tostring) else (.guess | tostring) end),
         (.snippet | clean) ] | join("\t")),
    ("approach_challenged: "
     + ([ $guessed[] | select(.guess == true) ] | length | tostring)
     + " of " + ($guessed | length | tostring) + " categorized rounds (guess; "
     + ($entries | length | tostring) + " entries, "
     + ($g | tostring) + " gathered, "
     + (($needing | length) - $g | tostring) + " gather-unavailable"
     + (if ($rec | length) > 0
        then "; recorded: " + ([ $rec[] | select(.recorded == true) ] | length | tostring)
             + " of " + ($rec | length | tostring) + " rounds"
        else "" end)
     + ")")
' 2>/dev/null)"
if [ -z "$OUT" ]; then
  unreadable "query_failed"
fi
printf '%s\n' "$OUT"
exit 0
