#!/usr/bin/env bash
# curate-postmortem.sh — the SOLE CURATOR WRITER for the postmortem churn ledger.
# (New file — knowledge-corpus curation. Appends curation records to
#  .supervisor/postmortem/results.jsonl so read-postmortem.sh can hide retracted / superseded
#  entries. Mirrors the add-rule.sh human-gated writer precedent.)
#
# Curation records live IN the ledger as ordinary JSONL lines (additive — POSTMORTEM_RESULT
# schema_version stays 1; OLD readers fail-safe-skip these lines because they carry no
# changed_paths):
#   {"schema_version":1,"source":"curation","curation_action":"retract"|"supersede",
#    "target_key":"<automate_key or pr_url>","replacement":"<pr_url or null>",
#    "reason":"<string>","ts":"<iso8601Z>"}
# `target_key` matches a data line's `automate_key` OR `pr_url` by EXACT string equality
# (read-postmortem.sh then excludes the matched entry from churn hits).
#
# WRITE DISCIPLINE (all enforced here in code, never as prose):
#   1. Append-only: with --confirm, append exactly ONE line via `>>` — NEVER rewrite, edit,
#      or remove an existing ledger line.
#   2. Human gate: WITHOUT --confirm, print the exact would-append JSON line + a dry-run
#      notice and exit 1 — this writer NEVER writes unattended.
#   3. jq-only JSON construction (`jq -n --arg ...`) — user input is NEVER string-interpolated
#      into JSON.
#   4. Validate BEFORE writing (fail loud, exit 2): action must be retract|supersede; --target
#      non-empty (whitespace-only rejected) and newline-free; --reason non-empty; --replacement
#      REQUIRED for supersede (a supersede without a replacement would be an indistinguishable
#      synonym for retract) and rejected on retract.
#      `curation_action`/`replacement` are recorded for audit + future use — no reader consumes
#      the retract-vs-supersede distinction yet (both hide the target identically today).
#   5. Read-back verify: after the append, the ledger's tail line must parse and carry our
#      target_key.
#
# Usage:
#   curate-postmortem.sh retract   --target <key> --reason <text> [--confirm]
#   curate-postmortem.sh supersede --target <key> --reason <text> --replacement <pr_url> [--confirm]
# Exit: 0 = wrote ; 1 = dry-run (nothing written — pass --confirm to write) ;
#       2 = validation / write error ; 3 = refused (jq unavailable, OR run from a git worktree
#       — curate only from the repo main checkout; red-team F1, mirrors write-lessons.sh).
#
# This is a WRITER: unlike the fail-safe readers it MAY exit non-zero (bimodal failure
# philosophy — gates/writers fail LOUD, readers/emitters fail SAFE).

set -euo pipefail

PROG="curate-postmortem.sh"

die() { printf '%s: %s\n' "$PROG" "$1" >&2; exit "${2:-2}"; }

# ---------------------------------------------------------------------------
# Parse args. The action is the single positional word; everything else is flagged.
# ---------------------------------------------------------------------------
action=""
target=""
reason=""
replacement_set=0    # whether --replacement was supplied at all (null when unset)
replacement=""
confirm=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    retract|supersede)
      [ -z "$action" ] || die "action given twice ('$action' then '$1')"
      action="$1"; shift ;;
    --target)      [ "$#" -ge 2 ] || die "--target requires a value"; target="$2"; shift 2 ;;
    --reason)      [ "$#" -ge 2 ] || die "--reason requires a value"; reason="$2"; shift 2 ;;
    --replacement) [ "$#" -ge 2 ] || die "--replacement requires a value"; replacement_set=1; replacement="$2"; shift 2 ;;
    --confirm)     confirm=1; shift ;;
    -h|--help)
      grep -E '^# ' "$0" | sed -E 's/^# ?//'
      exit 0 ;;
    *) die "unknown argument: $1 — action must be retract or supersede (see --help)" ;;
  esac
done

# ---------------------------------------------------------------------------
# Validate BEFORE building/writing anything (fail loud, exit 2).
# ---------------------------------------------------------------------------
case "$action" in
  retract|supersede) : ;;
  '') die "action is required: retract|supersede (see --help)" ;;
  *)  die "action must be retract or supersede (got: $action)" ;;
esac

[ -n "$target" ] || die "rejected: --target is required and must be non-empty"
# A target_key with an embedded newline could never match a single JSONL data line's
# automate_key/pr_url and would only produce a confusing dead record — reject it outright
# (CR rejected too, same reasoning).
nl=$'\n'; cr=$'\r'
case "$target" in
  *"$nl"*) die "rejected: --target may not contain newline characters" ;;
  *"$cr"*) die "rejected: --target may not contain carriage-return characters" ;;
esac
# A whitespace-only target (e.g. "   ") passes the non-empty test above but could never equal a
# real automate_key/pr_url either — reject it too (bash-3.2-safe pattern match: require at least
# one non-whitespace character; no regex / no ${var//...} needed).
case "$target" in
  *[![:space:]]*) : ;;
  *) die "rejected: --target must contain at least one non-whitespace character (whitespace-only value)" ;;
esac

[ -n "$reason" ] || die "rejected: --reason is required and must be non-empty"

if [ "$action" = "retract" ] && [ "$replacement_set" -eq 1 ]; then
  die "rejected: --replacement is only meaningful for supersede (a retract has no replacement)"
fi
if [ "$action" = "supersede" ] && [ "$replacement_set" -ne 1 ]; then
  die "rejected: supersede requires --replacement <pr_url> (without one it is indistinguishable from retract — use retract instead)"
fi

command -v jq >/dev/null 2>&1 || die "jq is required but not available" 3

# ---------------------------------------------------------------------------
# Resolve the ledger path (repo-root anchored, matching read-postmortem.sh).
# ---------------------------------------------------------------------------
GITROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# ---- Worktree guard (red-team F1 — mirrors write-lessons.sh) ---------------
# A linked worktree's top-level has a `.git` FILE ("gitdir: ..."); the main checkout has a dir.
# A curation append from a worktree would land in that worktree's gitignored .supervisor/ and be
# silently lost on `git worktree remove` — a wrong-store no-op. This is a fail-LOUD writer: refuse.
if [ -f "$GITROOT/.git" ]; then
  die "refusing to write from a git worktree ($GITROOT) — curate only from the repo main checkout (red-team F1)" 3
fi

CORPUS="$GITROOT/.supervisor/postmortem/results.jsonl"

# ---------------------------------------------------------------------------
# Build the record with jq -n --arg (never string-interpolate user input into JSON).
# jq -c guarantees a single output line even when --reason carries embedded newlines
# (jq escapes them to \n inside the JSON string).
# ---------------------------------------------------------------------------
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [ "$replacement_set" -eq 1 ]; then
  line="$(jq -cn \
    --arg action "$action" \
    --arg target "$target" \
    --arg replacement "$replacement" \
    --arg reason "$reason" \
    --arg ts "$ts" \
    '{schema_version:1, source:"curation", curation_action:$action, target_key:$target,
      replacement:$replacement, reason:$reason, ts:$ts}')"
else
  line="$(jq -cn \
    --arg action "$action" \
    --arg target "$target" \
    --arg reason "$reason" \
    --arg ts "$ts" \
    '{schema_version:1, source:"curation", curation_action:$action, target_key:$target,
      replacement:null, reason:$reason, ts:$ts}')"
fi

# ---------------------------------------------------------------------------
# Human gate: without --confirm this is a DRY-RUN — print the exact would-append line
# (stdout, pipeable) + the notice (stderr) and exit 1. NEVER writes unattended.
# ---------------------------------------------------------------------------
if [ "$confirm" -ne 1 ]; then
  printf '%s\n' "$line"
  printf '%s: dry-run, pass --confirm to write (nothing appended to %s)\n' "$PROG" "$CORPUS" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Confirmed: append exactly ONE line (append-only — never rewrite existing lines).
# ---------------------------------------------------------------------------
mkdir -p "$(dirname "$CORPUS")" || die "could not create ledger dir: $(dirname "$CORPUS")"
printf '%s\n' "$line" >> "$CORPUS" || die "append failed: $CORPUS"

# Read-back verify: the ledger tail is our record (parses, curation-sourced, right target).
if ! tail -n 1 "$CORPUS" | jq -e --arg t "$target" \
     '(.source == "curation") and (.target_key == $t)' >/dev/null 2>&1; then
  die "read-back verify failed: appended line not parseable at ledger tail: $CORPUS"
fi

printf '%s: appended 1 curation record (%s target_key=%s) to %s\n' "$PROG" "$action" "$target" "$CORPUS"
exit 0
