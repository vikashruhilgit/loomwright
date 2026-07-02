#!/usr/bin/env bash
# measure-heal-signal.sh — re-runnable READ-ONLY self-heal catch-rate dial (Local Twin Step 2).
#
# WHAT: makes "what is the self-heal catch-rate?" a dial you can re-run anytime, across repos.
# It harvests the heal signal from done-brief `## Outcome` blocks, joins it to the
# `/pr-postmortem` churn labels, and emits a confusion matrix (recall / FP / FN) + a trend line.
# Graduated from the Step-1 scratch spike (.supervisor/scratch/local-twin-step1/) into a shipped
# tool. The heavy lifting lives in the sibling measure-heal-signal.py; this wrapper resolves the
# repo list + output dir and invokes it. Read docs/SPIKES/LOCAL_TWIN_PATH.md §1 Step 2.
#
# READ-ONLY toward the repos it measures: it only READS their `.supervisor/jobs/done/*.md` +
# `.supervisor/postmortem/results.jsonl`. It WRITES only under --out (default the CURRENT repo's
# `.supervisor/heal-signal/`, which is gitignored). Advisory / directional — never gating-grade,
# never blocks a run, never changes a heal_decision (LOCAL_TWIN_PATH.md §5).
#
# Repo-list resolution (first match wins), so the default ships machine-agnostic:
#   1. --repo PATH        (repeatable; or --repos "PATH PATH ...")
#   2. $LOOMWRIGHT_HEAL_SIGNAL_REPOS   (newline- or colon-separated)
#   3. .supervisor/config.json  .measure_heal_signal.repos[]   (if jq present)
#   4. default: the current git repo (reproduces the Step-1 baseline — the join only ever
#      resolved within the self repo; other repos contribute signal but zero joined labels)
# To reproduce the Step-1 6-repo HARVEST, pass those 6 paths via --repo / the env / config.
#
# Usage:
#   measure-heal-signal.sh                       # measure the current repo
#   measure-heal-signal.sh --repo A --repo B     # measure a custom set
#   measure-heal-signal.sh --backfill 10         # + print a bounded backfill PLAN (no dispatch)
#   measure-heal-signal.sh --out /tmp/hs --no-ledger
#
# Exit: 0 in every normal path (a measurement tool must never break its caller). A missing
# python3 prints a skip line and exits 0; the engine's own exit code is otherwise propagated.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$HERE/measure-heal-signal.py"
GITROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# ---- parse args -------------------------------------------------------------
REPOS=()
OUT=""
BACKFILL=""
GATHER_SECS=""
LOW_ROUNDS=""
NO_LEDGER=""
QUIET=""
RECORDED_AT=""

usage() {
  sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)        REPOS+=("$2"); shift 2 ;;
    --repos)       # space-separated list in one arg
                   # shellcheck disable=SC2206
                   read -r -a _rs <<< "$2"; REPOS+=("${_rs[@]}"); shift 2 ;;
    --out)         OUT="$2"; shift 2 ;;
    --backfill)    BACKFILL="$2"; shift 2 ;;
    --gather-secs) GATHER_SECS="$2"; shift 2 ;;
    --low-rounds)  LOW_ROUNDS="$2"; shift 2 ;;
    --no-ledger)   NO_LEDGER=1; shift ;;
    --quiet)       QUIET=1; shift ;;
    --recorded-at) RECORDED_AT="$2"; shift 2 ;;
    -h|--help)     usage ;;
    *) echo "measure-heal-signal: unknown arg '$1' (try --help)" >&2; exit 0 ;;
  esac
done

# ---- python3 (fail-safe: skip, never break the caller) ----------------------
PY="$(command -v python3 || command -v python || true)"
if [ -z "$PY" ]; then
  echo "measure-heal-signal: python3 required — skipping (no measurement written)." >&2
  exit 0
fi
if [ ! -f "$ENGINE" ]; then
  echo "measure-heal-signal: engine not found at $ENGINE — skipping." >&2
  exit 0
fi

# ---- resolve repo list (precedence: flags > env > config > default-self) ----
if [ "${#REPOS[@]}" -eq 0 ] && [ -n "${LOOMWRIGHT_HEAL_SIGNAL_REPOS:-}" ]; then
  # split on newline OR colon (trailing \n so a single un-terminated path is not dropped)
  while IFS= read -r _r; do
    [ -n "$_r" ] && REPOS+=("$_r")
  done < <(printf '%s\n' "$LOOMWRIGHT_HEAL_SIGNAL_REPOS" | tr ':\n' '\n\n')
fi
if [ "${#REPOS[@]}" -eq 0 ] && command -v jq >/dev/null 2>&1 \
   && [ -f "$GITROOT/.supervisor/config.json" ]; then
  while IFS= read -r _r; do
    [ -n "$_r" ] && REPOS+=("$_r")
  done < <(jq -r '(.measure_heal_signal.repos // [])[]' \
             "$GITROOT/.supervisor/config.json" 2>/dev/null)
fi
if [ "${#REPOS[@]}" -eq 0 ]; then
  REPOS=("$GITROOT")
fi

# ---- build engine argv ------------------------------------------------------
ARGS=(--self-repo "$GITROOT" --repos)
for r in "${REPOS[@]}"; do ARGS+=("$r"); done
[ -n "$OUT" ]         && ARGS+=(--out "$OUT")
[ -n "$BACKFILL" ]    && ARGS+=(--backfill "$BACKFILL")
[ -n "$GATHER_SECS" ] && ARGS+=(--gather-secs "$GATHER_SECS")
[ -n "$LOW_ROUNDS" ]  && ARGS+=(--low-rounds "$LOW_ROUNDS")
[ -n "$NO_LEDGER" ]   && ARGS+=(--no-ledger)
[ -n "$QUIET" ]       && ARGS+=(--quiet)
[ -n "$RECORDED_AT" ] && ARGS+=(--recorded-at "$RECORDED_AT")

"$PY" "$ENGINE" "${ARGS[@]}"
exit $?
