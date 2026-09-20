#!/usr/bin/env bash
# lens-compare.sh — ADAPTER (loomwright/scripts/adapters/providers/). Composes
# TWO lens-run.sh calls against the SAME diff/prompt/commit and reports where
# they agree vs. where only one lens raised a finding. Source requirement:
# .supervisor/requirements/orca-derived/operator-run/08-multi-model-steps.md
# §"Compare mode" — "the disagreement set is the hard part and is what gets
# surfaced, not a merged list."
#
# USAGE
#   lens-compare.sh --providers <A>[:<model>],<B>[:<model>] --role <role> \
#       --diff <diff-file> --prompt <prompt-file> --out <output-json-file> \
#       [--commit <sha>]
#
#   --providers  REQUIRED. Exactly two provider[:model] specs separated by the
#                FIRST comma (a provider/model name never contains a comma).
#                Each half is passed to lens-run.sh's own --provider parsing
#                unchanged — this script does not re-implement or duplicate
#                that validation.
#   --role/--diff/--prompt/--commit  Forwarded byte-identical to BOTH
#                lens-run.sh calls, so the two lenses review the exact same
#                material. See lens-run.sh's own header for their meaning.
#   --out        REQUIRED. Path to write the comparison JSON to.
#
# THIS SCRIPT ADDS NO NEW SAFETY SURFACE. Every subprocess it runs is a plain
# `lens-run.sh` invocation — same throwaway independent sandbox, same env
# scrub, same mutation/integrity check, same wall-clock bound, per call. This
# file only sequences two such calls and diffs their normalized `issues[]`
# arrays. See lens-run.sh's own header SAFETY POSTURE section for the
# adapter's actual safety facts and honest limits; nothing here changes them.
#
# OUTPUT SHAPE (written to --out):
#   {
#     "compare_status": "ok" | "degraded_a" | "degraded_b" | "both_degraded",
#     "provider_a": {"provider", "model", "lens_status", "cost"},
#     "provider_b": {"provider", "model", "lens_status", "cost"},
#     "agree":   [ {file, line, a: <issue>, b: <issue>}, ... ],
#     "only_a":  [ <issue>, ... ],
#     "only_b":  [ <issue>, ... ]
#   }
# "agree" means both lenses raised a finding at the SAME (file, line) —
# `line: null` on both sides also counts as a match (a whole-file finding).
# It does NOT compare severity or description text: two lenses independently
# flagging the same location is the agreement signal itself (this item's
# source requirement, citing Orca's own rationale: "different agents make
# different mistakes... where they split, you've found the hard part"). Each
# entry keeps the FULL issue object from both sides (severity, category,
# description, suggestion) as evidence — callers needing tighter matching
# (e.g. same severity too) filter `agree` themselves; this script does not
# guess at a fuzzier heuristic than exact-location, per this repo's
# no-speculative-abstraction convention.
#
# A finding from a DEGRADED lens (lens_status != "ok") never appears — its
# issues[] is always [] per lens-run.sh's own emit_result contract — so
# compare_status alone tells a caller whether only_a/only_b are meaningful or
# just reflect one side's outage.
#
# Exit: ALWAYS 0, except a genuine CLI usage error (a required flag missing).

set +e   # FAIL-SAFE, same contract as lens-run.sh — see its header.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LENS_RUN="$SCRIPT_DIR/lens-run.sh"
JQ="${LOOMWRIGHT_JQ_BIN:-jq}"

usage_error() {
  printf 'lens-compare.sh: %s\n' "$1" >&2
  printf 'usage: lens-compare.sh --providers <A>[:<model>],<B>[:<model>] --role <role> --diff <file> --prompt <file> --out <file> [--commit <sha>]\n' >&2
  exit 64
}

PROVIDERS_ARG=""
ROLE=""
DIFF_FILE=""
PROMPT_FILE=""
OUT_FILE=""
COMMIT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --providers) PROVIDERS_ARG="${2:-}"; shift 2 ;;
    --role) ROLE="${2:-}"; shift 2 ;;
    --diff) DIFF_FILE="${2:-}"; shift 2 ;;
    --prompt) PROMPT_FILE="${2:-}"; shift 2 ;;
    --out) OUT_FILE="${2:-}"; shift 2 ;;
    --commit) COMMIT="${2:-}"; shift 2 ;;
    *) usage_error "unrecognized argument: $1" ;;
  esac
done

[ -n "$PROVIDERS_ARG" ] || usage_error "--providers is required"
[ -n "$ROLE" ] || usage_error "--role is required"
[ -n "$DIFF_FILE" ] || usage_error "--diff is required"
[ -n "$PROMPT_FILE" ] || usage_error "--prompt is required"
[ -n "$OUT_FILE" ] || usage_error "--out is required"
[ -f "$LENS_RUN" ] || usage_error "lens-run.sh not found next to this script at $LENS_RUN"

case "$PROVIDERS_ARG" in
  *,*) PROVIDER_A="${PROVIDERS_ARG%%,*}"; PROVIDER_B="${PROVIDERS_ARG#*,}" ;;
  *) usage_error "--providers must be TWO provider[:model] specs separated by a comma (got: $PROVIDERS_ARG)" ;;
esac
case "$PROVIDER_B" in
  *,*) usage_error "--providers takes exactly two specs; got a third comma-separated value in: $PROVIDERS_ARG" ;;
esac
[ -n "$PROVIDER_A" ] || usage_error "empty provider before the comma in --providers"
[ -n "$PROVIDER_B" ] || usage_error "empty provider after the comma in --providers"

command -v "$JQ" >/dev/null 2>&1 || usage_error "jq is required"

TMP_OUT_A="$(mktemp "${TMPDIR:-/tmp}/loomwright-lenscmp-a-XXXXXX")"
TMP_OUT_B="$(mktemp "${TMPDIR:-/tmp}/loomwright-lenscmp-b-XXXXXX")"
cleanup() { rm -f "$TMP_OUT_A" "$TMP_OUT_B" 2>/dev/null; }
trap cleanup EXIT

run_lens() {
  local provider="$1" out="$2"
  local args=(--provider "$provider" --role "$ROLE" --diff "$DIFF_FILE" --prompt "$PROMPT_FILE" --out "$out")
  [ -n "$COMMIT" ] && args+=(--commit "$COMMIT")
  bash "$LENS_RUN" "${args[@]}"
}

run_lens "$PROVIDER_A" "$TMP_OUT_A"
run_lens "$PROVIDER_B" "$TMP_OUT_B"

if [ ! -s "$TMP_OUT_A" ] || [ ! -s "$TMP_OUT_B" ]; then
  "$JQ" -n '{compare_status: "both_degraded", provider_a: null, provider_b: null, agree: [], only_a: [], only_b: []}' > "$OUT_FILE" 2>/dev/null
  exit 0
fi

"$JQ" -n --slurpfile av "$TMP_OUT_A" --slurpfile bv "$TMP_OUT_B" '
  def keyf: (.file // "unknown") + "|" + ((.line // null) | tostring);
  ($av[0]) as $A
  | ($bv[0]) as $B
  | (($A.issues // [])) as $ia
  | (($B.issues // [])) as $ib
  | (INDEX($ia[]; keyf)) as $ma
  | (INDEX($ib[]; keyf)) as $mb
  | ($ma | keys) as $ka
  | ($mb | keys) as $kb
  | ($ka - ($ka - $kb)) as $common
  | ($ka - $common) as $onlyA
  | ($kb - $common) as $onlyB
  | {
      compare_status: (
        if ($A.lens_status == "ok") and ($B.lens_status == "ok") then "ok"
        elif ($A.lens_status != "ok") and ($B.lens_status != "ok") then "both_degraded"
        elif ($A.lens_status != "ok") then "degraded_a"
        else "degraded_b" end
      ),
      provider_a: {provider: $A.provider, model: $A.model, lens_status: $A.lens_status, cost: $A.cost},
      provider_b: {provider: $B.provider, model: $B.model, lens_status: $B.lens_status, cost: $B.cost},
      agree: [ $common[] | {file: $ma[.].file, line: $ma[.].line, a: $ma[.], b: $mb[.]} ],
      only_a: [ $onlyA[] | $ma[.] ],
      only_b: [ $onlyB[] | $mb[.] ]
    }
' > "$OUT_FILE" 2>/dev/null

exit 0
