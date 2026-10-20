#!/usr/bin/env bash
# summarize.sh — one markdown table per eval run of the coordinator-model suite (automate-speed/10).
#
#   bash summarize.sh <label> <eval --json file>
#
# One row per case run: the three graders (parity / no-wrong-question / no-skipped-instruction), the counts
# from the run's own .eval/verdict.txt (WRONG_QUESTIONS, SKIPPED, CALLS, LAST_DO), turns, cost and tokens,
# then a totals row. The counts and tokens need the run kept: `claude plugin eval … --keep-temp` leaves each
# run's sandbox under the run's tracePath dir (out/trace.jsonl beside a sealed home dir); this script opens the
# sealed dir (chmod u+rwx, the operator's own temp dir) to read the verdict. A run with no kept sandbox
# prints `?` for those columns — never a guessed number.
# TOKEN SOURCE: the eval child's own trace, its `result` line's `usage` (input + cache creation + cache read
# + output tokens) — the eval JSON carries cost and turns but no token counts. bash 3.2 + BSD userland + jq.
set -uo pipefail
LABEL="${1:-}"; J="${2:-}"
[ -n "$LABEL" ] && [ -f "$J" ] || { echo "usage: summarize.sh <label> <eval --json file>" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "summarize: jq not on PATH" >&2; exit 2; }

echo "| $LABEL — case | run | score | parity | no wrong question | no skipped | WRONG_QUESTIONS | SKIPPED | calls | last do | turns | cost USD | tokens in / cache-create / cache-read / out |"
echo "|---|---|---|---|---|---|---|---|---|---|---|---|---|"
jq -r '.cases[] | .name as $n | (.arms.with // []) | to_entries[] |
  [$n, (.key + 1), .value.score, ([.value.graders[]? | {(.name): .passed}] | add // {} | tojson),
   .value.turns, .value.costUsd, (.value.tracePath // ""), (.value.error // "")] | @tsv' "$J" |
while IFS="$(printf '\t')" read -r name run score g turns cost tp err; do
  pv() { printf '%s' "$g" | jq -r --arg k "$1" 'if has($k) then (if .[$k] then "PASS" else "FAIL" end) else "-" end'; }
  wq="?"; sk="?"; calls="?"; last="?"; tok="?"
  if [ -n "$tp" ] && [ -f "$tp" ]; then
    kd="$(dirname "$(dirname "$tp")")"
    chmod u+rwx "$kd" "$kd/sealed" 2>/dev/null
    vf="$(find "$kd/sealed" -path '*/cwd/.eval/verdict.txt' 2>/dev/null | head -n 1)"
    if [ -n "$vf" ] && [ -f "$vf" ]; then
      wq="$(sed -n 's/^WRONG_QUESTIONS: //p' "$vf")"; sk="$(sed -n 's/^SKIPPED: //p' "$vf")"
      calls="$(sed -n 's/^CALLS: //p' "$vf")"; last="$(sed -n 's/^LAST_DO: //p' "$vf")"
    fi
    tok="$(jq -r 'select(.type == "result") | .usage | "\(.input_tokens) / \(.cache_creation_input_tokens) / \(.cache_read_input_tokens) / \(.output_tokens)"' "$tp" 2>/dev/null | tail -n 1)"
    [ -n "$tok" ] || tok="?"
  fi
  [ -z "$err" ] || last="error: $(printf '%s' "$err" | head -c 60)"
  printf '| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n' "$name" "$run" "$score" "$(pv parity)" \
    "$(pv no-wrong-question)" "$(pv no-skipped-instruction)" "$wq" "$sk" "$calls" "$last" "$turns" "$cost" "$tok"
done
jq -r '[.cases[] | (.arms.with // [])[]] as $r |
  "| **total** | \($r | length) runs | passed \([$r[] | select(.passed)] | length)/\($r | length) | parity \([$r[] | select([.graders[]? | select(.name == "parity" and .passed)] | length > 0)] | length)/\($r | length) | | | | | | | turns \([$r[].turns] | add) | \([$r[].costUsd] | add) | |"' "$J"
