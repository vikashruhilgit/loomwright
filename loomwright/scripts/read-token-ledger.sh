#!/usr/bin/env bash
# read-token-ledger.sh — fail-SAFE reader/summer for the `token_ledger` JSONL
# events emit-token-ledger.sh writes to `.supervisor/logs/<session_id>.jsonl`.
# NEVER blocks a caller and NEVER hard-errors: an unreadable/missing input
# always prints all-zero sums plus LEDGER_UNREADABLE=1 and exits 0.
#
# Usage:
#   read-token-ledger.sh --session <id>  [--root <checkout>]...
#   read-token-ledger.sh --run-id  <run_id | run-file path> [--root <checkout>]...
#
# Prints exactly ONE line to stdout:
#   INPUT=<n> OUTPUT=<n> CACHE_READ=<n> CACHE_CREATE=<n> TOTAL=<n> EVENTS=<n> [LEDGER_UNREADABLE=1]
# where TOTAL = INPUT + OUTPUT + CACHE_READ + CACHE_CREATE.
#
# --session <id>
#   Sums every `token_ledger` event in <root>/.supervisor/logs/<id>.jsonl.
#   A malformed (non-JSON) line is silently skipped, never a hard failure —
#   this reader never trusts the ledger file to be perfectly well-formed.
#
# --run-id <run_id>
#   An `/automate` run id (or a literal path to its run file). Resolves the
#   SET of session ids recorded in the run file's `## Progress` lines — see
#   `automate-loop/SKILL.md` §6 step 2, which appends a
#   `- <ts> session_id <id> (<item>)` line after each item's `/autonomous`
#   run — and sums across the UNION of those sessions' ledgers (i.e. this is
#   the `--session` sum, repeated per resolved id and added together).
#   `<run_id>` may be given bare (resolved to
#   `<root>/.supervisor/automate/<run_id>.md`) or as an existing path.
#
# --root <checkout>   (repeatable — parallel-automate/05, Scope 8)
#   Given more than once, every root is read and the sums are ADDED into the
#   same one line (a root named twice is read once). `--session` reads
#   `<root>/.supervisor/logs/<id>.jsonl` under each root; `--run-id` resolves
#   the run file under each root (a bare id: `<root>/.supervisor/automate/<id>.md`,
#   else — when that root is a lane clone whose `.supervisor/lane.json` names
#   `parent_run_id` = <id> — the lane's own `<lane run_id>.md`; a literal path
#   is one file whose sessions are read under every root) and sums that root's
#   sessions from that root's logs. So the parent total of a `--parallel` run is
#   `--run-id <parent> --root <primary> --root <lane1> …`. A root with nothing
#   readable contributes 0; LEDGER_UNREADABLE=1 only when NO root yielded a
#   readable ledger. With one (or no) --root the behavior is unchanged.
#   Overrides the checkout root `.supervisor/` is resolved under (mirrors
#   `automate-helpers.sh gate-eval`'s `--root`). Default: resolve the MAIN
#   worktree the same way `emit-token-ledger.sh` does (`git worktree list
#   --porcelain`'s first entry), falling back to `$PWD` when git resolution
#   is unavailable — so this reader and the emitter always agree on where
#   `.supervisor/logs/` lives.
#
# HONEST LIMITS (documented, not silently "fixed" by inventing a number):
#   - A `token_ledger` line written when the SubagentStop payload carried no
#     real usage fields is a PROXY line (`"proxy":true`, see
#     `emit-token-ledger.sh`'s `usage_present()`), carrying a
#     transcript-byte count instead of `input_tokens`/etc. This reader counts
#     a proxy line in EVENTS but its MISSING usage fields contribute exactly
#     0 to INPUT/OUTPUT/CACHE_READ/CACHE_CREATE/TOTAL — this is "no real
#     usage was ever recorded for that firing", NOT "0 tokens were spent".
#     There is no dollar or token estimate derived from transcript bytes
#     here — the plugin has no price table (see docs/PITFALLS.md).
#   - The ledger only knows what a SubagentStop hook actually saw. It does
#     NOT include the main thread's own tokens, and it does NOT include any
#     CI-side (GitHub Actions `claude-review`) spend.
#   - `--run-id` sums only the sessions the run file NAMED. A session whose
#     `session_id <id>` line was written but whose log file is missing is
#     silently skipped (contributes 0, does not itself set
#     LEDGER_UNREADABLE) — this is a genuine under-count risk if that
#     session legitimately spent tokens; LEDGER_UNREADABLE=1 is reserved for
#     "nothing at all could be read" (missing run file, zero resolved
#     session ids, or every resolved session's log file unreadable).
#
# Authoritative spec: docs/PITFALLS.md "Token ceiling" entry,
# docs/ARCHITECTURE_CONTRACTS.md §"Token ceiling".

set -u

JQ="${LOOMWRIGHT_JQ_BIN:-jq}"

die_usage() {
  echo "usage: read-token-ledger.sh --session <id> | --run-id <run_id> [--root <checkout>]..." >&2
  exit 1
}

MODE=""
ID=""
NL='
'
ROOT=""
ROOTS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --session) MODE="session"; ID="${2:-}"; shift 2 ;;
    --run-id)  MODE="run-id"; ID="${2:-}"; shift 2 ;;
    --root)    ROOT="${2:-}"
               case "$NL$ROOTS$NL" in *"$NL$ROOT$NL"*) ;; *) ROOTS="${ROOTS:+$ROOTS$NL}$ROOT" ;; esac
               shift 2 ;;
    -h|--help) die_usage ;;
    *) die_usage ;;
  esac
done

[ -n "$MODE" ] && [ -n "$ID" ] || die_usage

# ---- resolve root (mirrors emit-token-ledger.sh's worktree-safe anchoring) --
if [ -z "$ROOTS" ]; then
  main_root="$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
  if [ -n "$main_root" ] && [ -d "$main_root" ]; then
    top="$(git -C "$main_root" rev-parse --path-format=absolute --show-toplevel 2>/dev/null || true)"
    [ "$top" = "$main_root" ] || main_root=""
  fi
  [ -n "$main_root" ] || main_root="$PWD"
  ROOT="$main_root"
  ROOTS="$ROOT"
fi

LOG_DIR="${ROOT}/.supervisor/logs"

emit_zero() {
  echo "INPUT=0 OUTPUT=0 CACHE_READ=0 CACHE_CREATE=0 TOTAL=0 EVENTS=0 LEDGER_UNREADABLE=1"
  exit 0
}

# jq must be present AND functional (a jq on PATH that cannot execute would
# otherwise fall through to a hard failure — probe functionally, not with
# `command -v` alone, same discipline as emit-token-ledger.sh's log-owner probe).
command -v "$JQ" >/dev/null 2>&1 || emit_zero
printf '{}' | "$JQ" -e . >/dev/null 2>&1 || emit_zero

TOTAL_INPUT=0
TOTAL_OUTPUT=0
TOTAL_CACHE_READ=0
TOTAL_CACHE_CREATE=0
TOTAL_EVENTS=0
ANY_READABLE=0

# sum_session_file <path> — on success, adds that file's sums into the
# TOTAL_* accumulators and sets ANY_READABLE=1; returns 1 (no accumulation)
# when the file is missing/unreadable or jq fails to produce a line.
sum_session_file() {
  local f="$1" line
  [ -f "$f" ] && [ -r "$f" ] || return 1
  line="$("$JQ" -R -r -s '
    def numf(x): if (x|type)=="number" then x else 0 end;
    (split("\n")
      | map(select(length>0))
      | map(try fromjson catch empty)
      | map(select(type=="object" and .event=="token_ledger"))
    ) as $ev
    | [ ($ev | map(numf(.input_tokens)) | add // 0),
        ($ev | map(numf(.output_tokens)) | add // 0),
        ($ev | map(numf(.cache_read_input_tokens)) | add // 0),
        ($ev | map(numf(.cache_creation_input_tokens)) | add // 0),
        ($ev | length)
      ]
    | @tsv
  ' "$f" 2>/dev/null)"
  [ -n "$line" ] || return 1
  local i o cr cc ev
  IFS=$'\t' read -r i o cr cc ev <<< "$line"
  case "$i$o$cr$cc$ev" in
    *[!0-9]*) return 1 ;;   # any non-numeric field ⇒ treat the file as unreadable, never miscount
  esac
  TOTAL_INPUT=$((TOTAL_INPUT + i))
  TOTAL_OUTPUT=$((TOTAL_OUTPUT + o))
  TOTAL_CACHE_READ=$((TOTAL_CACHE_READ + cr))
  TOTAL_CACHE_CREATE=$((TOTAL_CACHE_CREATE + cc))
  TOTAL_EVENTS=$((TOTAL_EVENTS + ev))
  ANY_READABLE=1
  return 0
}

print_result() {
  local total=$((TOTAL_INPUT + TOTAL_OUTPUT + TOTAL_CACHE_READ + TOTAL_CACHE_CREATE))
  echo "INPUT=$TOTAL_INPUT OUTPUT=$TOTAL_OUTPUT CACHE_READ=$TOTAL_CACHE_READ CACHE_CREATE=$TOTAL_CACHE_CREATE TOTAL=$total EVENTS=$TOTAL_EVENTS"
}

# lane_run_file <root> <id> — parallel-automate/05: when <root> is a lane clone
# whose lane.json names parent_run_id = <id>, print the lane's own run file path.
lane_run_file() {
  local lj="$1/.supervisor/lane.json" par rid
  [ -f "$lj" ] || return 0
  par="$("$JQ" -r '.parent_run_id // empty | strings' "$lj" 2>/dev/null)"
  rid="$("$JQ" -r '.run_id // empty | strings' "$lj" 2>/dev/null)"
  [ -n "$par" ] && [ "$par" = "$2" ] && [ -n "$rid" ] || return 0
  case "$rid" in */*|.*) return 0 ;; esac
  printf '%s\n' "$1/.supervisor/automate/$rid.md"
}

while IFS= read -r ROOT; do
  [ -n "$ROOT" ] || continue
  LOG_DIR="${ROOT}/.supervisor/logs"
  case "$MODE" in
    session)
      sum_session_file "${LOG_DIR}/${ID}.jsonl" || true
      ;;
    run-id)
      RUNFILE=""
      if [ -f "$ID" ]; then
        RUNFILE="$ID"
      elif [ -f "${ROOT}/.supervisor/automate/${ID}.md" ]; then
        RUNFILE="${ROOT}/.supervisor/automate/${ID}.md"
      else
        RUNFILE="$(lane_run_file "$ROOT" "$ID")"
        [ -f "$RUNFILE" ] || RUNFILE=""
      fi
      [ -n "$RUNFILE" ] && [ -r "$RUNFILE" ] || continue
      SESSIONS="$(grep -oE 'session_id [A-Za-z0-9_-]+' "$RUNFILE" 2>/dev/null | awk '{print $2}' | env LC_ALL=C sort -u || true)"
      [ -n "$SESSIONS" ] || continue
      while IFS= read -r sid; do
        [ -n "$sid" ] || continue
        sum_session_file "${LOG_DIR}/${sid}.jsonl" || true
      done <<< "$SESSIONS"
      ;;
  esac
done <<< "$ROOTS"

if [ "$ANY_READABLE" -eq 1 ]; then
  print_result
else
  emit_zero
fi

exit 0
