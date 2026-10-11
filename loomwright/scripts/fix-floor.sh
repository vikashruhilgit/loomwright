#!/usr/bin/env bash
# fix-floor.sh — the ONE severity fix threshold every review step reads.
#
# A finding at or above the fix floor is FIXED (or, at the plan step,
# refined); a finding below it PASSES and is dismissed as a follow-up.
# BLOCKING is always at or above any floor. Three steps consume it, and all
# three read it through this script so the rule lives in one place:
#   - Launch Pad plan review save (agents/launch-pad.md Phase 6),
#   - Supervisor Phase 4.5 review-and-fix (skills/self-heal-advisory/SKILL.md Part 2),
#   - /review-pr, both the diff-only loop and the --until-mergeable drain
#     (skills/review-heal/SKILL.md).
#
#   fix_floor   fixed                     passes (follow-up)
#   HIGH        BLOCKING, HIGH            MEDIUM, LOW
#   MEDIUM      BLOCKING, HIGH, MEDIUM    LOW            <- DEFAULT
#   LOW         every severity            nothing
#
# Not the drain's `--severity-floor`: that one is TERMINATION-only (whether a
# round whose whole fixed yield was below it starts another round,
# drain-subfloor-decision.sh). The two are independent.
#
# USAGE
#   fix-floor.sh resolve [--flag <level>] [--root <dir>]
#       Prints the effective floor: HIGH | MEDIUM | LOW.
#       Precedence: a non-empty --flag value > <root>/.supervisor/config.json
#       `.fix_floor` > MEDIUM. --root defaults to the current directory.
#       Values are case-insensitive. An absent file, an absent key or a JSON
#       null is "not configured" and falls through to the default.
#   fix-floor.sh meets <severity> <floor>
#       Prints `fix` when <severity> ranks at or above <floor>, else `pass`.
#       An absent or unrecognised severity prints `fix` — a finding whose
#       severity cannot be read fails TOWARD being fixed, never toward a
#       silent pass.
#   fix-floor.sh split <floor> <issues.json|->
#       Reads a JSON array of finding objects (each may carry `.severity`)
#       and prints ONE line: {"fix":[...],"pass":[...]} — the same per-item
#       rule as `meets`, input order kept. A non-object element goes to
#       `fix`.
#
# EXIT CODES
#   0  an answer was printed.
#   2  refused, nothing on stdout, reason on stderr: usage error, a --flag or
#      <floor> that is not HIGH/MEDIUM/LOW, a configured `.fix_floor` that is
#      not one of them (or not a string), an unparseable config.json, jq
#      absent when it is needed, or `split` input that is not a JSON array.
#      This is a correctness setting, so it fails CLOSED: an explicit value
#      the script cannot honour is never silently replaced by the default.
#      The caller stops with a named status (`fix_floor_invalid`).
#
# Bash 3.2 / BSD-safe; `set -u` only. jq via "${JQ:-jq}" (test seam).

set -u

JQ_BIN="${JQ:-jq}"
DEFAULT_FLOOR="MEDIUM"

refuse() { printf 'fix-floor: %s\n' "$1" >&2; exit 2; }

# norm_level <value> — prints the upper-cased level, or nothing if invalid.
norm_level() {
  local v
  v="$(printf '%s' "${1:-}" | tr '[:lower:]' '[:upper:]')"
  case "$v" in
    HIGH|MEDIUM|LOW) printf '%s' "$v" ;;
  esac
}

# rank <severity> — 4..1, or 0 for absent / unrecognised.
rank() {
  case "$(printf '%s' "${1:-}" | tr '[:lower:]' '[:upper:]')" in
    BLOCKING) echo 4 ;;
    HIGH) echo 3 ;;
    MEDIUM) echo 2 ;;
    LOW) echo 1 ;;
    *) echo 0 ;;
  esac
}

need_jq() {
  command -v "$JQ_BIN" >/dev/null 2>&1 || refuse "jq not found"
}

cmd_resolve() {
  local flag="" root="."
  while [ $# -gt 0 ]; do
    case "$1" in
      --flag) [ $# -ge 2 ] || refuse "--flag needs a value"; flag="$2"; shift 2 ;;
      --root) [ $# -ge 2 ] || refuse "--root needs a value"; root="$2"; shift 2 ;;
      *) refuse "resolve: unknown argument: $1" ;;
    esac
  done
  if [ -n "$flag" ]; then
    local f
    f="$(norm_level "$flag")"
    [ -n "$f" ] || refuse "--fix-floor '$flag' is not HIGH, MEDIUM or LOW"
    printf '%s\n' "$f"
    exit 0
  fi
  local cfg="$root/.supervisor/config.json"
  if [ ! -f "$cfg" ]; then
    printf '%s\n' "$DEFAULT_FLOOR"
    exit 0
  fi
  need_jq
  local kind
  # Slurped so the WHOLE file must parse as exactly one object; a trailing
  # parse error after a leading object would otherwise go unnoticed.
  kind="$("$JQ_BIN" -rse 'if length == 1 and (.[0] | type) == "object"
      then (.[0].fix_floor | if . == null then "null" elif type == "string" then "s:" + . else "bad" end)
      else "notobject" end' "$cfg" 2>/dev/null)" || refuse "$cfg is not valid JSON"
  case "$kind" in
    null) printf '%s\n' "$DEFAULT_FLOOR" ;;
    s:*)
      local c
      c="$(norm_level "${kind#s:}")"
      [ -n "$c" ] || refuse "$cfg .fix_floor '${kind#s:}' is not HIGH, MEDIUM or LOW"
      printf '%s\n' "$c" ;;
    notobject) refuse "$cfg is not a single JSON object" ;;
    *) refuse "$cfg .fix_floor is not a string" ;;
  esac
  exit 0
}

cmd_meets() {
  [ $# -eq 2 ] || refuse "usage: fix-floor.sh meets <severity> <floor>"
  local floor
  floor="$(norm_level "$2")"
  [ -n "$floor" ] || refuse "floor '$2' is not HIGH, MEDIUM or LOW"
  local r f
  r="$(rank "$1")"
  f="$(rank "$floor")"
  if [ "$r" -eq 0 ] || [ "$r" -ge "$f" ]; then echo fix; else echo pass; fi
  exit 0
}

cmd_split() {
  [ $# -eq 2 ] || refuse "usage: fix-floor.sh split <floor> <issues.json|->"
  local floor src body
  floor="$(norm_level "$1")"
  [ -n "$floor" ] || refuse "floor '$1' is not HIGH, MEDIUM or LOW"
  src="$2"
  need_jq
  case "$src" in
    -) body="$(cat)" ;;
    *) [ -r "$src" ] || refuse "cannot read $src"; body="$(cat "$src")" ;;
  esac
  printf '%s' "$body" | "$JQ_BIN" -cse --arg floor "$floor" '
    def rank: if type != "string" then 0 else ascii_upcase
      | if . == "BLOCKING" then 4 elif . == "HIGH" then 3
        elif . == "MEDIUM" then 2 elif . == "LOW" then 1 else 0 end end;
    ($floor | rank) as $f
    | if length == 1 and (.[0] | type) == "array" then .[0] else error("not an array") end
    | map(. as $i | (if ($i | type) == "object" then ($i.severity | rank) else 0 end) as $r
          | {i: $i, fix: ($r == 0 or $r >= $f)})
    | {fix: [.[] | select(.fix) | .i], pass: [.[] | select(.fix | not) | .i]}
  ' 2>/dev/null || refuse "split input is not a JSON array"
  exit 0
}

SUB="${1:-}"
[ $# -gt 0 ] && shift
case "$SUB" in
  resolve) cmd_resolve "$@" ;;
  meets) cmd_meets "$@" ;;
  split) cmd_split "$@" ;;
  *) refuse "usage: fix-floor.sh resolve|meets|split ..." ;;
esac
