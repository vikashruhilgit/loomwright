#!/usr/bin/env bash
# rules-audit-line.sh — the ONE deterministic reading of audit-rules.sh for Phase 4.5
# (automate-followups/09). The Phase 4.5 prose (skills/self-heal-advisory/SKILL.md §"Rules-store
# audit") calls THIS helper and never parses the audit report itself, so the three-state mapping and
# its mutation control are CI-testable (test-rules-audit-line.sh) instead of living in model prose.
#
# Usage:  rules-audit-line.sh [--root <tree>]      (--root defaults to `.`)
#
# POSTURE: a fail-SAFE advisory emitter wrapping a fail-CLOSED engine (CLAUDE.md §"Failure-Mode
# Invariants"). It ALWAYS exits 0 and NEVER writes. The engine it runs executes nothing either: a rule
# `check` is read by audit-rules.sh as text and statically linted, never run. This helper reads no
# rule file itself — it only reads the engine's report.
#
# STDOUT CONTRACT: exactly one or two lines, nothing else.
#   Line 1 — ALLOW-LISTED (never a deny-list):
#     rules_audit: clean                   ONLY when the engine exit code is 0 AND the report holds
#                                          exactly one whole line `## Findings — BLOCKING (0)`.
#     rules_audit: findings <n> (<kinds>)  ONLY when the exit code is 1 AND the report holds exactly
#                                          one whole line `## Findings — BLOCKING (<n>)`, n >= 1.
#                                          <kinds> = the sorted, de-duplicated `[kind]` tokens of the
#                                          BLOCKING section, joined with ", " (`unparsed` if none parse).
#     rules_audit: unexamined              EVERYTHING else: exit 2, any other exit code, the engine
#                                          absent or unreadable, empty output, the header missing or
#                                          duplicated, or exit code and header disagreeing. Could not
#                                          examine is NEVER reported as clean (skills/rules/SKILL.md §11).
#   Line 2 (optional) — the FIRST column-0 line of the report starting `rules_gate_trigger: `,
#     echoed verbatim, in any line-1 state. Absent otherwise.
#
# The engine is resolved as a SIBLING of this file (never from PATH) and run with stdin </dev/null;
# its stderr is discarded. Portability: bash 3.2 (macOS) + Linux; no GNU-only flags.
set -u

HDR_PREFIX='## Findings — BLOCKING ('

_emit_unexamined() {
  printf 'rules_audit: unexamined\n'
  exit 0
}

ROOT_ARG="."
while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      [ $# -ge 2 ] || _emit_unexamined
      ROOT_ARG="$2"; shift 2 ;;
    *) _emit_unexamined ;;
  esac
done

HERE="$(CDPATH= cd "$(dirname "$0")" 2>/dev/null && pwd)" || _emit_unexamined
ENGINE="$HERE/audit-rules.sh"
[ -f "$ENGINE" ] && [ -r "$ENGINE" ] || _emit_unexamined

REPORT="$(bash "$ENGINE" --root "$ROOT_ARG" </dev/null 2>/dev/null)"
RC=$?
# Empty output needs no special case: it holds no header, so it falls through to unexamined below.

# The BLOCKING header(s): every whole line starting with the prefix. Exactly one, with an integer
# count, or the header is treated as absent (HDR_N stays empty ⇒ neither clean nor findings).
HDRS="$(grep -c -- '^## Findings — BLOCKING (' <<<"$REPORT")"
HDR_N=""
if [ "$HDRS" = "1" ]; then
  _h="$(grep -- '^## Findings — BLOCKING (' <<<"$REPORT")"
  _n="${_h#"$HDR_PREFIX"}"
  if [ "$_h" != "$_n" ] && [ "${_n%)}" != "$_n" ]; then
    _n="${_n%)}"
    case "$_n" in ''|*[!0-9]*) : ;; *) HDR_N="$_n" ;; esac
  fi
fi

LINE1="rules_audit: unexamined"
if [ "$RC" -eq 0 ] && [ "$HDRS" = "1" ] && [ "$HDR_N" = "0" ]; then LINE1="rules_audit: clean"; fi   # CLEAN-PREDICATE
if [ "$RC" -eq 1 ] && [ "$HDRS" = "1" ] && [ -n "$HDR_N" ] && [ "$HDR_N" -ge 1 ] 2>/dev/null; then
  # The [kind] tokens between the BLOCKING header and the next `## ` line.
  KINDS="$(awk -v pfx="$HDR_PREFIX" '
    index($0, pfx) == 1 { inside = 1; next }
    inside && /^## / { inside = 0 }
    inside && /^  \[[a-z_]+\] / { k = $0; sub(/^  \[/, "", k); sub(/\].*$/, "", k); print k }
  ' <<<"$REPORT" | env LC_ALL=C sort -u | awk 'NR > 1 { printf ", " } { printf "%s", $0 }')"
  [ -n "$KINDS" ] || KINDS="unparsed"
  LINE1="rules_audit: findings $HDR_N ($KINDS)"
fi

printf '%s\n' "$LINE1"
TRIGGER="$(grep -m 1 -- '^rules_gate_trigger: ' <<<"$REPORT")"
[ -n "$TRIGGER" ] && printf '%s\n' "$TRIGGER"
exit 0
