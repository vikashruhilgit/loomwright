#!/usr/bin/env bash
# brain-baseline-eval.sh — Phase 0 BASELINE eval harness for the brain-integration arc.
#
# Measures current (grep-first) behavior against a small, version-controlled brain corpus so that
# "graph-first helps" is provable, not asserted (see docs/SPIKES/BRAIN_INTEGRATION_EVOLUTION.md
# §"Phase 0 — Baseline eval harness"). It records, per corpus item, the manually-supplied correctness
# rubric plus the self-captured tool-call / missed-context signals that /insights does NOT capture
# (that's ccusage's job).
#
# DISTINCT from run-eval.sh: that script is the output-quality fitness function over eval-corpus/ and
# writes .supervisor/eval/results.jsonl, which /insights' "Eval fitness function" section consumes.
# THIS script is the brain BASELINE instrument: it reads a SEPARATE, version-controlled corpus dir
# (scripts/brain-baseline-corpus/, a sibling of eval-corpus/ — checked in so runs are reproducible and
# the corpus is reviewable) and writes a SEPARATE history file
# (.supervisor/eval/brain-baseline.jsonl). It MUST NOT touch results.jsonl, and per the design doc's
# v1 rule /insights deliberately IGNORES the baseline file (so the brain baseline never pollutes the
# existing fitness-function trend). Keeping the files separate is the whole point.
#
# Output shape on stdout: a human/grep per-item block (one line per corpus item) AND exactly ONE
# machine-readable marker line:
#   BRAIN_BASELINE_EVAL_RESULT: {schema_version,items_total,mode,records,commit,date,status}
# The JSON line is jq-built for injection safety (values pass as --arg/--argjson, never interpolated).
#
# Per-item record schema (one object per corpus item, appended to brain-baseline.jsonl):
#   {id, mode (baseline|graph-first), correct (bool), tool_calls (int), missed_context (bool),
#    note, recorded_at}
# correct/tool_calls/missed_context are MANUALLY supplied by the human running the spike (no
# auto-grader in v1 — the corpus is small by design). Absent overrides default to a neutral
# placeholder (correct=false, tool_calls=0, missed_context=false) so an un-scored run is still a
# well-formed record rather than a crash.
#
# Fail-safe: this script ALWAYS exits 0. When the corpus dir is missing OR `jq` is unavailable, it
# emits BRAIN_BASELINE_EVAL_RESULT with status:"unverified", items_total 0, records [], and exits 0
# (mirroring run-eval.sh — a baseline that cannot run must never break its caller). Recording to the
# history file is BEST-EFFORT: any failure (no git root, cannot mkdir, cannot write) never changes
# the exit code or stdout.
#
# Usage:  brain-baseline-eval.sh [--no-record]
# Env:    BRAIN_BASELINE_CORPUS_DIR  — override corpus dir
#                                      (default: $SCRIPT_DIR/brain-baseline-corpus)
#         BRAIN_BASELINE_RESULTS_FILE — override history file
#                                      (default: <gitroot>/.supervisor/eval/brain-baseline.jsonl)
#         BRAIN_BASELINE_MODE         — "baseline" (default) | "graph-first"
# Exit:   always 0.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Resolve git root once (used for the default results-history path). Empty => recording skipped.
GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo '')"

# ---- corpus dir -----------------------------------------------------------
# Version-controlled fixtures live alongside this script (sibling of eval-corpus/), NOT under
# .supervisor/ — which is gitignored, so a corpus there would be neither checked in nor reviewable.
# Mirrors run-eval.sh's $SCRIPT_DIR/eval-corpus resolution. Override with BRAIN_BASELINE_CORPUS_DIR.
CORPUS="${BRAIN_BASELINE_CORPUS_DIR:-$SCRIPT_DIR/brain-baseline-corpus}"

# ---- mode -----------------------------------------------------------------
MODE="${BRAIN_BASELINE_MODE:-baseline}"
case "$MODE" in
  baseline|graph-first) ;;
  *) MODE="baseline" ;;   # unknown => safe default, never crash
esac

# ---- argv parse -----------------------------------------------------------
RECORD=1
for arg in "$@"; do
  case "$arg" in
    --no-record) RECORD=0 ;;
  esac
done

# ---- results history file (best-effort persistence target) ----------------
# Default to <gitroot>/.supervisor/eval/brain-baseline.jsonl — a SEPARATE file from results.jsonl.
if [ -n "${BRAIN_BASELINE_RESULTS_FILE:-}" ]; then
  RESULTS_FILE="$BRAIN_BASELINE_RESULTS_FILE"
elif [ -n "$GIT_ROOT" ]; then
  RESULTS_FILE="$GIT_ROOT/.supervisor/eval/brain-baseline.jsonl"
else
  RESULTS_FILE=""   # no git root — recording will be skipped (fail-safe)
fi

# ---- contextual fields (NOT part of any determinism invariant) ------------
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"

# record_records <records-json-array>: append EACH record object (already carrying recorded_at) as one
# JSON line to $RESULTS_FILE. Requires jq (callers guarantee it on this path). BEST-EFFORT: gated by
# --no-record and an empty target, and wrapped so any failure is swallowed — recording must NEVER
# change the exit code or stdout. Writes ONLY to the baseline file, never results.jsonl.
record_records() {
  [ "$RECORD" -eq 1 ] || return 0
  [ -n "$RESULTS_FILE" ] || return 0
  local arr="$1"
  {
    mkdir -p "$(dirname "$RESULTS_FILE")" \
      && printf '%s' "$arr" | jq -c '.[]' >> "$RESULTS_FILE"
  } 2>/dev/null || true
}

# emit_unverified: fail-safe path — no corpus or no jq. items 0, records [].
emit_unverified() {
  echo "Brain baseline: 0 items (unverified)"
  if command -v jq >/dev/null 2>&1; then
    local obj
    obj="$(jq -cn \
      --arg mode "$MODE" --arg commit "$COMMIT" --arg date "$DATE" \
      '{schema_version:1,items_total:0,mode:$mode,records:[],commit:$commit,date:$date,status:"unverified"}')"
    printf 'BRAIN_BASELINE_EVAL_RESULT: %s\n' "$obj"
  else
    # No jq: hand-built minimal JSON (only fixed/whitelisted values interpolated — injection-safe).
    printf 'BRAIN_BASELINE_EVAL_RESULT: {"schema_version":1,"items_total":0,"mode":"%s","records":[],"commit":"%s","date":"%s","status":"unverified"}\n' \
      "$MODE" "$COMMIT" "$DATE"
  fi
  # Fail-safe terminus (the rubric checks for a literal exit 0 on this path).
  exit 0
}

# Fail-safe: no jq available. Emit unverified and stop.
if ! command -v jq >/dev/null 2>&1; then
  echo "brain-baseline-eval: no jq available — cannot build result, fail-safe no-op" >&2
  emit_unverified
fi

# Fail-safe: corpus dir missing. Emit unverified and stop.
if [ ! -d "$CORPUS" ]; then
  echo "brain-baseline-eval: corpus dir '$CORPUS' not found — fail-safe no-op" >&2
  emit_unverified
fi

# ---- per-item override lookups (manual scoring, env-supplied) -------------
# A human running the spike supplies correctness/tool-call/missed-context per item via env vars keyed
# by a sanitized item id (non-alnum => _). Absent => neutral placeholder. All reads are defensive so a
# malformed value can never crash the run.
sanitize_id() { printf '%s' "$1" | tr -c '[:alnum:]' '_'; }

lookup_correct() {        # default false
  local key="BRAIN_BASELINE_CORRECT_$(sanitize_id "$1")"
  case "${!key:-}" in     # ${!key} indirect expansion — no eval; bash does not re-expand the result
    1|true|TRUE|True|yes|YES|Yes|y|Y) echo true ;;   # human-scored: accept common truthy hand-typed forms
    *) echo false ;;
  esac
}
lookup_tool_calls() {     # default 0
  local key="BRAIN_BASELINE_TOOLCALLS_$(sanitize_id "$1")"
  local v; v="${!key:-}"
  case "$v" in
    ''|*[!0-9]*) echo 0 ;;
    *) echo "$((10#$v))" ;;   # force base-10 so a leading-zero value (e.g. 08/09) never breaks jq --argjson
  esac
}
lookup_missed() {         # default false
  local key="BRAIN_BASELINE_MISSED_$(sanitize_id "$1")"
  case "${!key:-}" in     # ${!key} indirect expansion — no eval
    1|true|TRUE|True|yes|YES|Yes|y|Y) echo true ;;   # human-scored: accept common truthy hand-typed forms
    *) echo false ;;
  esac
}
lookup_note() {           # default ""
  local key="BRAIN_BASELINE_NOTE_$(sanitize_id "$1")"
  printf '%s' "${!key:-}"
}

# ---- discover corpus items (deterministic, sorted) ------------------------
# A corpus item is a .md fixture under $CORPUS (README.md is documentation, not an item — skipped).
records_json="[]"
items_total=0

item_files="$(find "$CORPUS" -mindepth 1 -maxdepth 1 -type f -name '*.md' 2>/dev/null | LC_ALL=C sort)"

if [ -n "$item_files" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    base="$(basename "$f")"
    [ "$base" = "README.md" ] && continue   # documentation, not a corpus item
    item_id="${base%.md}"
    items_total=$((items_total+1))

    correct="$(lookup_correct "$item_id")"
    tool_calls="$(lookup_tool_calls "$item_id")"
    missed="$(lookup_missed "$item_id")"
    note="$(lookup_note "$item_id")"

    echo "  [item] $item_id  mode=$MODE correct=$correct tool_calls=$tool_calls missed_context=$missed"

    records_json="$(printf '%s' "$records_json" | jq -c \
      --arg id "$item_id" \
      --arg mode "$MODE" \
      --argjson correct "$correct" \
      --argjson tool_calls "$tool_calls" \
      --argjson missed "$missed" \
      --arg note "$note" \
      --arg ra "$DATE" \
      '. + [{id:$id,mode:$mode,correct:$correct,tool_calls:$tool_calls,missed_context:$missed,note:$note,recorded_at:$ra}]')"
  done <<EOF
$item_files
EOF
fi

echo "Brain baseline: $items_total item(s)  mode=$MODE"

# ---- emit the single machine-readable result line -------------------------
result_json="$(jq -cn \
  --argjson total "$items_total" \
  --arg mode "$MODE" \
  --argjson records "$records_json" \
  --arg commit "$COMMIT" \
  --arg date "$DATE" \
  '{schema_version:1,items_total:$total,mode:$mode,records:$records,commit:$commit,date:$date,status:"ok"}')"
printf 'BRAIN_BASELINE_EVAL_RESULT: %s\n' "$result_json"

# Persist per-item records to the SEPARATE baseline history file (best-effort).
record_records "$records_json"

exit 0
