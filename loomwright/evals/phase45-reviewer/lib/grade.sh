#!/usr/bin/env bash
# grade.sh — the phase45-reviewer suite's ONE grader: did the replayed reviewer catch the recorded miss?
#
#   bash grade.sh <reply file> <case_id> <corpus tsv>
#
# Deterministic, no LLM, run AFTER the eval and OUTSIDE the sandbox (lib/summarize.sh calls it once per kept
# sandbox, through PHASE45_GRADE). The expectation is read from the corpus table, never from the sandbox:
#   <corpus tsv>  case_id<TAB>pr<TAB>kind<TAB>expected_file<TAB>severity_floor, an optional `case_id` header
#                 line; kind is `miss` (expected_file and severity_floor set) or `control` (both empty).
#
# Output — ONE result line, plus a NOISE line for a control:
#   no reply file                  RESULT: MISSED (no reply)
#   no parseable CODE_REVIEW_RESULT RESULT: MISSED (unparseable)
#   miss case                      RESULT: CAUGHT when some issue has severity at or above the floor
#                                  (BLOCKING > HIGH > MEDIUM > LOW) AND `file` equal to expected_file;
#                                  otherwise RESULT: MISSED
#   control                        RESULT: CLEAN | RESULT: NOISE, then NOISE: <count of BLOCKING/HIGH issues>
# CAUGHT is reachable only with expected_file set; CLEAN / NOISE only with it empty.
#
# The block is located and parsed by the plugin's own result_block_parser.py (the parser the Code Reviewer's
# result validator uses — never a second parser), so "parseable" means what the real Phase 4.5 consumer
# can read: the LAST CODE_REVIEW_RESULT block, no parse errors, a PASS / FAIL / NEEDS_HUMAN `decision`, and an
# `issues` field that is a list (absent or null = [], as the validator's own issue reader treats it).
#
# Exit codes: 0 a result printed; 2 usage error, the case missing from the table, an inconsistent row, or
# python3 / the parser unavailable — nothing graded (the caller reports the case as `?`, never caught).
# bash 3.2 + BSD userland + python3.
set -uo pipefail

REPLY="${1:-}"; CASE_ID="${2:-}"; CORPUS="${3:-}"
[ -n "$REPLY" ] && [ -n "$CASE_ID" ] && [ -n "$CORPUS" ] || { echo "usage: grade.sh <reply file> <case_id> <corpus tsv>" >&2; exit 2; }
[ -f "$CORPUS" ] || { echo "grade: corpus table not found: $CORPUS" >&2; exit 2; }
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSER_DIR="$(cd "$LIB/../../../scripts" 2>/dev/null && pwd)"
[ -n "$PARSER_DIR" ] && [ -f "$PARSER_DIR/result_block_parser.py" ] || { echo "grade: result_block_parser.py not found under the plugin's scripts/" >&2; exit 2; }

# ---- the expectation (from the table, outside the sandbox) -------------------------------------------------
TAB="$(printf '\t')"
row="$(awk -F "$TAB" -v id="$CASE_ID" '$1 == id { print; n++ } END { if (n != 1) exit 1 }' "$CORPUS")" \
  || { echo "grade: case '$CASE_ID' is not exactly one row of $CORPUS" >&2; exit 2; }
KIND="$(printf '%s\n' "$row" | cut -f3)"
EXPECTED_FILE="$(printf '%s\n' "$row" | cut -f4)"
SEVERITY_FLOOR="$(printf '%s\n' "$row" | cut -f5 | tr -d '\r')"
rank() { case "$1" in BLOCKING) echo 4 ;; HIGH) echo 3 ;; MEDIUM) echo 2 ;; LOW) echo 1 ;; *) echo 0 ;; esac; }
case "$KIND" in
  miss)
    [ -n "$EXPECTED_FILE" ] && [ "$(rank "$SEVERITY_FLOOR")" -gt 0 ] \
      || { echo "grade: miss case '$CASE_ID' needs expected_file and a BLOCKING|HIGH|MEDIUM|LOW severity_floor" >&2; exit 2; } ;;
  control)
    [ -z "$EXPECTED_FILE" ] && [ -z "$SEVERITY_FLOOR" ] \
      || { echo "grade: control '$CASE_ID' must have empty expected_file and severity_floor" >&2; exit 2; } ;;
  *) echo "grade: case '$CASE_ID' has kind '$KIND' (want miss | control)" >&2; exit 2 ;;
esac

# ---- the reply ---------------------------------------------------------------------------------------------
if [ ! -f "$REPLY" ]; then
  echo "RESULT: MISSED (no reply)"
  [ -n "$EXPECTED_FILE" ] || echo "NOISE: 0"
  exit 0
fi
# One `<SEVERITY>\t<file>` line per issue; the single line UNPARSEABLE when no usable block; exit 3 = no python
issues="$(python3 -I -c 'import sys
sys.path.insert(0, sys.argv[1])
from result_block_parser import find_last_block, parse_block
with open(sys.argv[2], encoding="utf-8", errors="replace") as fh:
    block = find_last_block(fh.read(), "CODE_REVIEW_RESULT")
fields, errors = parse_block(block) if block else ({}, ["no block"])
if errors or str(fields.get("decision") or "").strip() not in ("PASS", "FAIL", "NEEDS_HUMAN"):
    print("UNPARSEABLE"); sys.exit(0)
raw = fields.get("issues")
if raw is None:
    raw = []
if not isinstance(raw, list):
    print("UNPARSEABLE"); sys.exit(0)
for i in raw:
    if isinstance(i, dict):
        sev = str(i.get("severity") or "").strip().upper()
        f = str(i.get("file") or "").strip()
        print(sev + "\t" + f.replace("\t", " ").replace("\n", " "))' "$PARSER_DIR" "$REPLY" 2>/dev/null)" \
  || { echo "grade: python3 / result_block_parser.py could not run — '$CASE_ID' is ungraded" >&2; exit 2; }

if [ "$issues" = "UNPARSEABLE" ]; then
  echo "RESULT: MISSED (unparseable)"
  [ -n "$EXPECTED_FILE" ] || echo "NOISE: 0"
  exit 0
fi

if [ -n "$EXPECTED_FILE" ]; then
  floor="$(rank "$SEVERITY_FLOOR")"
  while IFS="$TAB" read -r sev file; do
    [ -n "$sev" ] || continue
    if [ "$(rank "$sev")" -ge "$floor" ] && [ "$file" = "$EXPECTED_FILE" ]; then
      echo "RESULT: CAUGHT"; exit 0
    fi
  done <<EOF
$issues
EOF
  echo "RESULT: MISSED"
else
  noise=0
  while IFS="$TAB" read -r sev file; do
    case "$sev" in BLOCKING|HIGH) noise=$((noise + 1)) ;; esac
  done <<EOF
$issues
EOF
  if [ "$noise" -gt 0 ]; then echo "RESULT: NOISE"; else echo "RESULT: CLEAN"; fi
  echo "NOISE: $noise"
fi
exit 0
