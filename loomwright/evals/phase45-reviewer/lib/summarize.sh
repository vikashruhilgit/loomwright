#!/usr/bin/env bash
# summarize.sh — the phase45-reviewer report: which recorded misses the current reviewer catches.
#
#   bash summarize.sh <eval --json file> <suite dir> [<corpus tsv>]
#
# <corpus tsv> defaults to <repo root>/docs/evidence/phase45-reviewer-corpus.tsv (the expectation table, kept
# OUTSIDE the plugin under test and outside every sandbox). Each run of the eval JSON is mapped to its case by
# the kept sandbox's `.eval/case-id`: `claude plugin eval … --keep-temp` leaves each run's sandbox under the
# run's tracePath dir (out/trace.jsonl beside a sealed dir), and this script opens the sealed dir with
# `chmod u+rwx` (the operator's own temp dir), as coordinator-model's summarize.sh does. Each kept sandbox is
# then graded — AFTER the run, outside the sandbox — by the grader in PHASE45_GRADE (default: this suite's
# lib/grade.sh) against the case's corpus row; `.eval/unstageable` grades UNSTAGEABLE without the grader.
#
# Output: one table row per corpus case and kept run (CAUGHT / MISSED / MISSED (unparseable) / MISSED (no
# reply) / UNSTAGEABLE / CLEAN / NOISE, or `?` when the case has no kept sandbox or its grading failed), then
#   caught: X/Y       Y = every miss-case row except UNSTAGEABLE. A staged miss whose reviewer crashed, timed
#                     out or never replied stays in Y as MISSED (no reply); a `?` row stays in Y as not caught —
#                     so a failed spawn reads `caught: 0/<n>`, never `0/0`, and never a guessed number
#   unstageable: <n>  rows whose staging found an unreachable sha (any kind)
#   no_reply: <n>     staged rows with no reviewer reply (any kind)
#   noise: <sum> BLOCKING/HIGH on <m> controls   m = control rows whose reply was graded CLEAN / NOISE
#   model, wall_clock (PHASE45_WALL_S from run.sh, else `?`), turns, cost_usd (from the eval JSON)
# Exit codes: 0 the report printed; 2 usage, jq missing, or an unreadable JSON / corpus table.
# bash 3.2 + BSD userland + jq.
set -uo pipefail

J="${1:-}"; SUITE="${2:-}"
[ -n "$J" ] && [ -n "$SUITE" ] && [ -f "$J" ] && [ -d "$SUITE" ] \
  || { echo "usage: summarize.sh <eval --json file> <suite dir> [<corpus tsv>]" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "summarize: jq not on PATH" >&2; exit 2; }
SUITE="$(cd "$SUITE" && pwd)"
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORPUS="${3:-$SUITE/../../../docs/evidence/phase45-reviewer-corpus.tsv}"
[ -f "$CORPUS" ] || { echo "summarize: corpus table not found: $CORPUS" >&2; exit 2; }
GRADE="${PHASE45_GRADE:-$LIB/grade.sh}"
jq -e '.cases | type == "array"' "$J" >/dev/null 2>&1 || { echo "summarize: $J has no .cases array" >&2; exit 2; }
TAB="$(printf '\t')"
T="$(mktemp -d)" || { echo "summarize: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$T"' EXIT

# ---- every run → its kept sandbox (case_id, sandbox cwd, turns, cost) ---------------------------------------
: > "$T/map"; : > "$T/models"
jq -r '.cases[] | .name as $n | (.arms.with // []) | to_entries[] |
  [$n, (.key + 1), (.value.turns // ""), (.value.costUsd // ""), (.value.tracePath // "")] | @tsv' "$J" |
while IFS="$TAB" read -r name run turns cost tp; do
  [ -n "$tp" ] && [ -f "$tp" ] || continue
  kd="$(dirname "$(dirname "$tp")")"
  chmod u+rwx "$kd" "$kd/sealed" 2>/dev/null
  idf="$(find "$kd/sealed" -maxdepth 4 -path '*/cwd/.eval/case-id' 2>/dev/null | head -n 1)"
  jq -r 'select(.type == "system") | .model // empty' "$tp" 2>/dev/null >> "$T/models"
  if [ -z "$idf" ] || [ ! -f "$idf" ]; then
    printf '%s\n' "| ? ($name run $run) | ? | ? | ? (kept sandbox has no .eval/case-id) | - | $turns | $cost |" >> "$T/orphans"
    continue
  fi
  printf '%s\t%s\t%s\t%s\n' "$(head -n 1 "$idf")" "$(dirname "$(dirname "$idf")")" "$turns" "$cost" >> "$T/map"
done

# ---- one row per corpus case and kept run -------------------------------------------------------------------
caught=0; denom=0; unstageable=0; no_reply=0; noise_sum=0; controls=0
echo "| case | kind | pr | result | noise | turns | cost USD |"
echo "|---|---|---|---|---|---|---|"
while IFS="$TAB" read -r id pr kind _exp _floor; do
  [ -n "$id" ] && [ "$id" != case_id ] || continue
  awk -F "$TAB" -v id="$id" '$1 == id' "$T/map" > "$T/runs"
  if [ ! -s "$T/runs" ]; then
    echo "| $id | $kind | $pr | ? | - | - | - |"
    [ "$kind" != miss ] || denom=$((denom + 1))
    continue
  fi
  while IFS="$TAB" read -r _id sb turns cost; do
    noise="-"
    if [ -f "$sb/.eval/unstageable" ]; then
      result="UNSTAGEABLE"; unstageable=$((unstageable + 1))
    else
      g="$(bash "$GRADE" "$sb/.eval/reviewer-reply.md" "$id" "$CORPUS" 2>"$T/grade.err" </dev/null)"; grc=$?
      result="$(printf '%s\n' "$g" | sed -n 's/^RESULT: //p' | head -n 1)"
      if [ "$grc" -ne 0 ] || [ -z "$result" ]; then
        result="? (grade error: $(head -n 1 "$T/grade.err"))"
      fi
      n="$(printf '%s\n' "$g" | sed -n 's/^NOISE: //p' | head -n 1)"
      case "$result" in "MISSED (no reply)") no_reply=$((no_reply + 1)) ;; esac
      if [ "$kind" = miss ]; then
        denom=$((denom + 1))
        [ "$result" != CAUGHT ] || caught=$((caught + 1))
      elif [ "$kind" = control ]; then
        case "$result" in CLEAN|NOISE)
          case "$n" in ''|*[!0-9]*) n=0 ;; esac
          noise="$n"; controls=$((controls + 1)); noise_sum=$((noise_sum + n)) ;;
        esac
      fi
    fi
    echo "| $id | $kind | $pr | $result | $noise | ${turns:--} | ${cost:--} |"
  done < "$T/runs"
done < "$CORPUS"
awk -F "$TAB" 'NR == FNR { if ($1 != "case_id") known[$1] = 1; next } !($1 in known) { print $1 }' "$CORPUS" "$T/map" \
  | sort -u | while IFS= read -r id; do echo "| $id | ? | ? | NOT_IN_CORPUS (not counted) | - | - | - |"; done
[ ! -f "$T/orphans" ] || cat "$T/orphans"

model="$(jq -r '.model // empty' "$J" 2>/dev/null)"
[ -n "$model" ] || model="$(sort -u "$T/models" | tr '\n' ' ' | sed 's/ $//')"
echo
echo "caught: $caught/$denom"
echo "unstageable: $unstageable"
echo "no_reply: $no_reply"
echo "noise: $noise_sum BLOCKING/HIGH on $controls controls"
echo "model: ${model:-?}"
wall="${PHASE45_WALL_S:-}"; [ -z "$wall" ] || wall="${wall}s"
echo "wall_clock: ${wall:-?}"
echo "turns: $(jq -r '[.cases[] | (.arms.with // [])[] | .turns // 0] | add // 0' "$J")"
echo "cost_usd: $(jq -r '[.cases[] | (.arms.with // [])[] | .costUsd // 0] | add // 0' "$J")"
