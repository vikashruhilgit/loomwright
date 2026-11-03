#!/usr/bin/env bash
# gate-auto.sh — the deterministic answer seat for the `auto` tier of the lane gate catalog
# (`lane-policy.sh catalog`, the ONE authority; docs/LANE_GATES.md §"The `auto` tier" mirrors it).
#
# An `auto` gate is a routine question whose catalog-designated answer — the row's ONE label marked with
# a trailing `!` — is applied WITHOUT asking, unless an escalation trigger fires. Which gates are `auto`,
# and which label each applies, is read from the catalog every call; this script holds no copy of it.
# The engine calls `decide` only on a path that would otherwise ask the owner (an interactive main
# thread, or a phase session whose relay defers); a run that cannot ask keeps its own named can't-ask
# status, untouched by this script. Every trigger is a deterministic read — never a model's confidence.
#
#   decide <code> [--offered <label>]… [--recommended <label>]
#          [--max-severity BLOCKING|HIGH|MEDIUM|LOW|NONE] [--risk-paths <file>]
#          [--risk-diff <base> <head>] [--destructive] [--runfile <path>] [--off] [--root <dir>]
#             prints exactly ONE line: `answer <label>` (the row's `!` label, marker removed) or
#             `ask <trigger>`. Triggers, checked in this order (the first that fires is printed):
#               off         the off switch: `--off`; a `auto_gates: off` field in the run file's
#                           `## Run Config`; `auto_gates: false` in <root>/.supervisor/lane.json; or
#                           `{"auto_gates": false}` in <root>/.supervisor/config.json (read with
#                           `has("auto_gates")` — a `false` never collapses to "unset"; any present
#                           non-`true` value turns it off, fail toward asking)
#               not_auto    the code's catalog policy is not `auto` (`allowed` and `human-only` codes
#                           are never answered here)
#               label       the `--offered` labels, `(Recommended)` stripped, are not exactly the row's
#                           labels or its non-`?` core as a set (no `--offered` at all is a mismatch);
#                           or `--recommended` is not the row's `!` label; or the row has no single `!`
#               destructive `--destructive` (the answer would delete, discard, merge or push)
#               severity    `--max-severity` is MEDIUM or higher, or unparseable; for the codes in
#                           GA_SEVERITY_REQUIRED (LP-SAVE-NOTE) a missing value asks too
#               high_risk   classify-risk.sh reports `high_risk` anything but `false` (true, null, or
#                           no readable answer) over `--risk-paths` (its `--paths` mode) or
#                           `--risk-diff` (its refs mode); neither flag ⇒ no risk read
#             Errors fail toward asking: `ask jq_missing`, `ask catalog_unreadable`, `ask unknown_code`,
#             `ask root_unreadable`, `ask runfile_unreadable`, `ask lane_json_unreadable`,
#             `ask config_unreadable`.
#   record <runfile> <code> <label> <reason> [--item <item>]
#             appends ONE `## Progress` line through `automate-helpers.sh progress-append`:
#             `<ts> auto-answered <code>: <label> — <reason>[ (item <item>)]`.
#   record <runfile> <code> --escalated <trigger> [--item <item>]
#             appends `<ts> auto-escalated <code>: <trigger>[ (item <item>)]`. `--escalated off`
#             writes nothing: the off switch restores the behaviour before the tier, records included.
#             Fail-SAFE: always exit 0; a failed append is reported on stderr and the line is printed on
#             stdout instead, so it is never lost and never blocks the run. With no run file resolvable
#             (`<runfile>` empty or `-` and no LOOMWRIGHT_PHASE_DIR — a standalone /launch-pad) the line
#             is printed on stdout for the phase output. Newlines and tabs in any field become spaces
#             (one record is one line). NOT concurrency-safe: progress-append is an unlocked
#             read-modify-rename, so simultaneous records on one run file can lose lines silently (a
#             scratch run of 8 parallel records kept 1). Gates are asked one at a time, so record them
#             one at a time — never in parallel.
#   list <runfile>
#             prints the end-of-run / park block: `Auto-answered gates (<n>):` then one row
#             `- <code>: <label> — <reason>[ (item <item>)]` per `auto-answered` line of the run file's
#             `## Progress`; NOTHING at all when there are none (or no run file). Read-only, exit 0.
#
# Run-file resolution (decide's `--runfile`, record's and list's `<runfile>`): the given path; else
# $LOOMWRIGHT_PHASE_DIR (`<checkout>/.supervisor/automate/<run_id>.phase/<phase>` ⇒
# `<checkout>/.supervisor/automate/<run_id>.md`); else none. A given or derived run file that does not
# exist makes `decide` ask (`runfile_unreadable`): its off switch cannot be read.
#
# Usage:  gate-auto.sh decide … | record … | list … | --help
# Exit:   decide 0 (its stdout IS the decision) · 2 usage error (still prints `ask usage`) ·
#         record 0 always · list 0 always.
# Needs:  jq (absent ⇒ decide prints `ask jq_missing`); bash 3.2-safe.
# Seams:  LOOMWRIGHT_GATE_AUTO_LANE_POLICY (lane-policy.sh), LOOMWRIGHT_GATE_AUTO_CLASSIFY_RISK
#         (classify-risk.sh), LOOMWRIGHT_GATE_AUTO_HELPERS (automate-helpers.sh, for progress-append).
# Tests:  test-lane-policy.sh, group (ga).

set -uo pipefail   # NO `set -e`: every failure path is an explicit `ask` (decide) or a reported no-op.

PROG="gate-auto.sh"
GA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GA_LANE_POLICY="${LOOMWRIGHT_GATE_AUTO_LANE_POLICY:-$GA_DIR/lane-policy.sh}"
GA_CLASSIFY="${LOOMWRIGHT_GATE_AUTO_CLASSIFY_RISK:-$GA_DIR/classify-risk.sh}"
GA_HELPERS="${LOOMWRIGHT_GATE_AUTO_HELPERS:-$GA_DIR/automate-helpers.sh}"
# The codes whose decide needs an explicit --max-severity (D4: a noted PASS without one is asked).
GA_SEVERITY_REQUIRED="LP-SAVE-NOTE"

_ga_usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$GA_DIR/gate-auto.sh"; }
_ga_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
_ga_oneline() { printf '%s' "$1" | tr '\n\r\t' '   '; }

# _ga_runfile <given> — prints the resolved run file path (see header), or nothing.
_ga_runfile() {
  local pd
  if [ -n "${1:-}" ] && [ "$1" != "-" ]; then printf '%s' "$1"; return 0; fi
  [ -n "${LOOMWRIGHT_PHASE_DIR:-}" ] || return 0
  pd="${LOOMWRIGHT_PHASE_DIR%/}"; pd="${pd%/*}"
  case "$pd" in *.phase) printf '%s.md' "${pd%.phase}" ;; esac
}

# _ga_flag <json file> — prints the file's `auto_gates` value as JSON text, or nothing when the key is
# absent; returns 1 when the file is not readable JSON. `has` — never `.auto_gates // empty`, which
# collapses a `false` into "unset".
_ga_flag() {
  jq -r 'if has("auto_gates") then (.auto_gates | tojson) else empty end' "$1" 2>/dev/null
}

# _ga_runconfig_off <runfile> — 0 when the run file's `## Run Config` carries an `auto_gates: off` field
# (its own `- auto_gates: off` line, or a `| auto_gates: off` field of a joined line).
_ga_runconfig_off() {
  awk '/^## / { sec = $0; next }
    sec == "## Run Config" && /(^-[ \t]+|\|[ \t]*)auto_gates:[ \t]*off[ \t]*(\||$)/ { f = 1 }
    END { exit !f }' "$1" 2>/dev/null
}

# _ga_risk <classify-risk.sh args…> — prints classify-risk.sh's `high_risk` (`true` / `false` / `null`),
# or `unreadable` when no JSON came back.
_ga_risk() {
  local v
  v="$(bash "$GA_CLASSIFY" "$@" 2>/dev/null </dev/null | jq -r '.high_risk | tostring' 2>/dev/null)"
  [ -n "$v" ] || v="unreadable"
  printf '%s' "$v"
}

# ==================================================================================================
# decide
# ==================================================================================================
ga_decide() {
  local code="" off=0 destr=0 rec="" rec_set=0 sev="" sev_set=0 rpaths="" rbase="" rhead="" rf_arg=""
  local root="" rf v row rowj oj l risk r sev_uc
  local offered=()
  _ga_ask() { printf 'ask %s\n' "$1"; [ -z "${2:-}" ] || echo "$PROG: decide → ask $1 — $2" >&2; return 0; }
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --offered|--recommended|--max-severity|--risk-paths|--runfile|--root)
        [ "$#" -ge 2 ] || { _ga_ask usage "$1 needs a value"; return 2; }
        case "$1" in
          --offered) offered+=("$2") ;;
          --recommended) rec="$2"; rec_set=1 ;;
          --max-severity) sev="$2"; sev_set=1 ;;
          --risk-paths) rpaths="$2"; [ -n "$rpaths" ] || { _ga_ask usage "--risk-paths must not be empty"; return 2; } ;;
          --runfile) rf_arg="$2" ;;
          --root) root="$2" ;;
        esac
        shift 2 ;;
      --risk-diff)
        [ "$#" -ge 3 ] && [ -n "$2" ] && [ -n "$3" ] || { _ga_ask usage "--risk-diff needs <base> <head>"; return 2; }
        rbase="$2"; rhead="$3"; shift 3 ;;
      --destructive) destr=1; shift ;;
      --off) off=1; shift ;;
      --*) _ga_ask usage "unknown flag $1"; return 2 ;;
      *) [ -z "$code" ] || { _ga_ask usage "one <code> only"; return 2; }; code="$1"; shift ;;
    esac
  done
  [ -n "$code" ] || { _ga_ask usage "usage: decide <code> [flags…] (--help)"; return 2; }

  # off — the switch, from each of its four sources.
  [ "$off" = 1 ] && { _ga_ask off "--off"; return 0; }
  command -v jq >/dev/null 2>&1 || { _ga_ask jq_missing "jq unavailable"; return 0; }
  [ -n "$root" ] || root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  [ -d "$root" ] || { _ga_ask root_unreadable "--root is not a directory: $root"; return 0; }   # its switches are unreadable
  rf="$(_ga_runfile "$rf_arg")"
  if [ -n "$rf" ]; then
    [ -f "$rf" ] && [ -r "$rf" ] || { _ga_ask runfile_unreadable "run file not readable: $rf"; return 0; }
    _ga_runconfig_off "$rf" && { _ga_ask off "## Run Config auto_gates: off ($rf)"; return 0; }
  fi
  if [ -e "$root/.supervisor/lane.json" ]; then
    v="$(_ga_flag "$root/.supervisor/lane.json")" || { _ga_ask lane_json_unreadable "$root/.supervisor/lane.json"; return 0; }
    case "$v" in ""|true) ;; *) _ga_ask off "lane.json auto_gates: $v"; return 0 ;; esac
  fi
  if [ -e "$root/.supervisor/config.json" ]; then
    v="$(_ga_flag "$root/.supervisor/config.json")" || { _ga_ask config_unreadable "$root/.supervisor/config.json"; return 0; }
    case "$v" in ""|true) ;; *) _ga_ask off "config.json auto_gates: $v"; return 0 ;; esac
  fi

  # The catalog row — read from lane-policy.sh every call, never a second copy.
  row="$(bash "$GA_LANE_POLICY" catalog 2>/dev/null </dev/null)"
  [ -n "$row" ] || { _ga_ask catalog_unreadable "lane-policy.sh catalog printed nothing"; return 0; }
  row="$(printf '%s\n' "$row" | awk -F'\t' -v c="$code" '$1 == c { print; exit }')"
  [ -n "$row" ] || { _ga_ask unknown_code "$code is not a catalog code"; return 0; }
  rowj="$(jq -Rc 'split("\t") | (.[2] | split("|")) as $l
    | {policy: .[1], labels: ($l | map(sub("[?!]$"; ""))),
       core: ($l | map(select(endswith("?") | not) | sub("!$"; ""))),
       auto: ($l | map(select(endswith("!")) | sub("!$"; "")))}' <<<"$row" 2>/dev/null)"
  [ -n "$rowj" ] || { _ga_ask catalog_unreadable "cannot parse the $code row"; return 0; }

  # not_auto — the tier check.
  [ "$(jq -r '.policy' <<<"$rowj")" = "auto" ] || { _ga_ask not_auto "$code is $(jq -r '.policy' <<<"$rowj")"; return 0; }

  # label — exactly one `!` label; the offered set is the row's labels or its core; --recommended is it.
  [ "$(jq -r '.auto | length' <<<"$rowj")" = 1 ] || { _ga_ask label "$code has no single ! label in the catalog"; return 0; }
  oj='[]'
  for l in "${offered[@]+"${offered[@]}"}"; do oj="$(jq -c --arg l "$l" '. + [$l]' <<<"$oj")" || oj='null'; done
  jq -e --argjson o "$oj" 'def strip: gsub("\\s*\\(Recommended\\)"; "") | gsub("^\\s+|\\s+$"; "");
      ($o | type) == "array" and (($o | map(strip) | sort) as $s | $s == (.labels | sort) or $s == (.core | sort))' \
      <<<"$rowj" >/dev/null 2>&1 \
    || { _ga_ask label "offered labels are not the $code catalog labels"; return 0; }
  if [ "$rec_set" = 1 ]; then
    jq -e --arg r "$rec" '($r | gsub("\\s*\\(Recommended\\)"; "") | gsub("^\\s+|\\s+$"; "")) == .auto[0]' <<<"$rowj" >/dev/null 2>&1 \
      || { _ga_ask label "--recommended '$rec' is not the $code auto label"; return 0; }
  fi

  # destructive
  [ "$destr" = 1 ] && { _ga_ask destructive "--destructive"; return 0; }

  # severity — parse first (unparseable asks), then the MEDIUM-or-higher trigger on its own line.
  sev_uc="$(printf '%s' "$sev" | tr '[:lower:]' '[:upper:]')"
  if [ "$sev_set" = 1 ]; then
    case "$sev_uc" in BLOCKING|HIGH|MEDIUM|LOW|NONE) ;; *) _ga_ask severity "--max-severity '$sev' is unparseable"; return 0 ;; esac
    case "$sev_uc" in BLOCKING|HIGH|MEDIUM) _ga_ask severity "--max-severity $sev_uc"; return 0 ;; esac
  else
    case " $GA_SEVERITY_REQUIRED " in *" $code "*) _ga_ask severity "$code needs --max-severity"; return 0 ;; esac
  fi

  # high_risk — classify-risk.sh over the given paths and/or diff; anything but `false` asks.
  risk=""
  [ -n "$rpaths" ] && risk="$risk $(_ga_risk --paths "$rpaths" --root "$root")"
  [ -n "$rbase" ] && risk="$risk $(_ga_risk "$rbase" "$rhead" --root "$root")"
  for r in $risk; do [ "$r" = "false" ] || { _ga_ask high_risk "classify-risk.sh high_risk: $r"; return 0; }; done

  printf 'answer %s\n' "$(jq -r '.auto[0]' <<<"$rowj")"
}

# ==================================================================================================
# record
# ==================================================================================================
ga_record() {
  local rf_arg="${1-}" code="${2-}" label="${3-}" reason="${4-}" item="" rf line err
  if [ "$#" -lt 4 ]; then
    echo "$PROG: record: usage: record <runfile> <code> <label> <reason> [--item <item>] | record <runfile> <code> --escalated <trigger> [--item <item>] — nothing recorded" >&2
    return 0
  fi
  shift 4
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --item) [ "$#" -ge 2 ] || { echo "$PROG: record: --item needs a value — nothing recorded" >&2; return 0; }; item="$2"; shift 2 ;;
      *) echo "$PROG: record: unknown argument '$1' — nothing recorded" >&2; return 0 ;;
    esac
  done
  case "$code" in ""|*[!A-Z0-9-]*) echo "$PROG: record: '$code' is not a gate code — nothing recorded" >&2; return 0 ;; esac
  label="$(_ga_oneline "$label")"; reason="$(_ga_oneline "$reason")"; item="$(_ga_oneline "$item")"
  if [ "$label" = "--escalated" ]; then
    [ -n "$reason" ] || { echo "$PROG: record: --escalated needs a trigger — nothing recorded" >&2; return 0; }
    [ "$reason" = "off" ] && return 0   # the off switch: no record, exactly as before the tier
    line="$(_ga_now) auto-escalated $code: $reason${item:+ (item $item)}"
  else
    line="$(_ga_now) auto-answered $code: $label — $reason${item:+ (item $item)}"
  fi
  rf="$(_ga_runfile "$rf_arg")"
  if [ -z "$rf" ]; then printf '%s\n' "$line"; return 0; fi
  err="$(bash "$GA_HELPERS" progress-append "$rf" "$line" 2>&1 >/dev/null </dev/null)" || {
    echo "$PROG: record: progress-append on $rf failed — $(printf '%s' "$err" | head -1); the record is printed instead" >&2
    printf '%s\n' "$line"
  }
  return 0
}

# ==================================================================================================
# list
# ==================================================================================================
ga_list() {
  local rf rows n
  rf="$(_ga_runfile "${1-}")"
  [ -n "$rf" ] && [ -f "$rf" ] && [ -r "$rf" ] || return 0
  rows="$(awk '/^## / { sec = $0; next }
    sec == "## Progress" && /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z auto-answered / {
      print "- " substr($0, 38) }' "$rf" 2>/dev/null)"
  [ -n "$rows" ] || return 0
  n="$(printf '%s\n' "$rows" | grep -c .)"
  printf 'Auto-answered gates (%s):\n%s\n' "$n" "$rows"
  return 0
}

ga_main() {
  local sub="${1:-}"
  [ "$#" -gt 0 ] && shift
  case "$sub" in
    decide) ga_decide "$@" ;;
    record) ga_record "$@" ;;
    list)   ga_list "$@" ;;
    -h|--help|help) _ga_usage ;;
    *) echo "$PROG: unknown subcommand '${sub}' (decide | record | list; --help)" >&2; return 2 ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then ga_main "$@"; exit $?; fi
