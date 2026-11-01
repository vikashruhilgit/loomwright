#!/usr/bin/env bash
# build-feature-scorecard.sh — READ-ONLY per-feature scorecard: which optional gates, lenses and
# advisories earn their cost.
#
# ADVISORY / READ-ONLY / FAIL-SAFE — this script NEVER gates anything and changes no config. For
# every feature in the registry (docs/feature-scorecard.json, the ONE list of scored features) it
# reads ONLY the records that feature names under the state dir and prints: runs available, ran,
# caught, catch rate, cost total, cost per catch, last fired and a SUGGESTED verdict. It writes
# nothing (except mktemp scratch) and ALWAYS exits 0 — the build-loop-evidence.sh convention.
# Numbers are never invented: a cost with no cost record prints `unknown`, never 0.
#
# USAGE
#   build-feature-scorecard.sh [--since <YYYY-MM-DD|ISO-8601 UTC|commit>] [--json]
#                              [--state-dir <dir>] [--registry <file>]
#
#   --state-dir  root of every record read (default ./.supervisor — same flag and default as
#                build-loop-evidence.sh). A commit given to --since resolves against the repo that
#                holds the state dir's parent, else the current directory.
#   --registry   the feature registry (default: the plugin's docs/feature-scorecard.json).
#   --since      count only records dated at/after this point. A record's date is the first
#                YYYY-MM-DD[-HHMMSS] in its file name, else its mtime; with --since set, a record
#                with no readable date is left out of the window.
#   --json       one JSON object instead of the markdown table (the contract below).
#
# RECORD FORMATS (the registry's record.format):
#   result_block  the last block of the file in either form — `<header>:` + 2-space-indented keys, or
#                 a `## <header>` heading + `- key: value` bullets; the value of key `field`,
#                 continuation lines joined. Neither form present ⇒ malformed.
#   text          the rest of the first line containing the literal `field` (leading `:`/`=`/space
#                 stripped); with `header` set, a file with neither header form is malformed.
#   json          getpath(field split on "."); a file jq cannot parse as an object is malformed.
#   tsv           column `field` of every non-empty row; a row whose column count differs from
#                 `columns` is malformed.
#   A value matching none of null / ~ / "" counts as present; `valid` (a jq regex) must match every
#   present value, else the record is malformed. One malformed in-window record makes THAT feature
#   unreadable — never another feature, never a verdict of keep.
#   One record file = one run opportunity (runs available). ran = files whose value hits the `ran`
#   rule; caught = ran files whose value also hits the `caught` rule.
#
# VERDICT PRECEDENCE (first match wins; the vocabulary is the V_* block below — its one home):
#   1 record none → V_NONE (no verdict)   2 a record that cannot be parsed → V_BAD_PREFIX<reason>
#   3 caught >= 1 → V_KEEP                4 runs available < min_sample → V_INSUF
#   5 caught unknown → V_INSUF            6 ran 0 → V_NEVER
#   7 ran >= min_sample and caught 0 → V_COST                 8 otherwise → V_INSUF
#   A critical: true feature that lands on 6 or 7 gets V_CRIT instead.
#
# --json CONTRACT (consumed by build-insights.sh and propose-scorecard.sh):
#   {"schema_version":1, "status":"ok"|"error", "error":<string|null>, "since":<string|null>,
#    "features":[{"id","critical","record_paths":[…],"runs_available","ran","caught","catch_rate",
#                 "cost_total","cost_per_catch","last_fired","verdict"}],
#    "needs_emitter":[ids], "unregistered":[ids]}
#   A missing/invalid registry, a bad --since or no jq ⇒ status "error", features [], one error
#   line on stderr, exit 0. For a record-none or unreadable feature every count is null.
#   "unregistered" = optional SUPERVISOR_RESULT fields (`# optional` keys of the first yaml block
#   of docs/result-schemas/supervisor-result.md; FEATURE_SCORECARD_SCHEMA_DOC overrides the path
#   for tests) in neither features[].record.field nor not_features.
#
# PORTABILITY: macOS bash 3.2 + Linux CI. No associative arrays, no stat(1) (`date -u -r <file>`
# reads an mtime on both BSD and GNU date), no ${var//…} over corpus-sized strings, date
# comparison in jq (codepoint order — never locale collation).
#
# Exit: ALWAYS 0.

set -uo pipefail   # `set -e` intentionally omitted — an advisory read must NEVER fail its caller.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="./.supervisor"
REGISTRY="$SCRIPT_DIR/../docs/feature-scorecard.json"
SCHEMA_DOC="${FEATURE_SCORECARD_SCHEMA_DOC:-$SCRIPT_DIR/../docs/result-schemas/supervisor-result.md}"
SINCE=""
SINCE_GIVEN=0
JSON=0

# ---------------------------------------------------------------------------- verdict vocabulary
# The closed verdict set lives HERE and only here; consumers render it or prefix-match "review:".
V_NONE="no record"
V_COST="review: costs without catching"
V_NEVER="review: never ran"
V_CRIT="keep (critical)"
V_INSUF="insufficient data"
V_KEEP="keep"
V_BAD_PREFIX="unreadable: "

usage() {
  cat <<EOF
build-feature-scorecard.sh — READ-ONLY feature scorecard (advisory, never gates, changes no config)

Usage: build-feature-scorecard.sh [--since <date|sha>] [--json] [--state-dir <dir>] [--registry <file>]

  --since <date|sha>  only records dated at/after a YYYY-MM-DD date, an ISO-8601 UTC time or a commit
  --json              one JSON object (schema_version 1) instead of the markdown table
  --state-dir <dir>   root of every record read (default ./.supervisor)
  --registry <file>   feature registry (default: the plugin's docs/feature-scorecard.json)
  --help              this help

Verdicts (suggestions only): $V_KEEP · $V_CRIT · $V_COST · $V_NEVER · $V_INSUF · $V_NONE · ${V_BAD_PREFIX}<reason>
Always exits 0.
EOF
}

ERR=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --since)
      SINCE_GIVEN=1
      case "${2:-}" in
        ''|--*) ERR="--since given without a value" ;;   # never swallow the next flag as the window
        *) SINCE="$2"; shift ;;
      esac
      ;;
    --state-dir)
      if [ "$#" -ge 2 ] && [ -n "${2:-}" ]; then STATE_DIR="$2"; shift
      else echo "build-feature-scorecard: --state-dir given without a value — keeping default ($STATE_DIR)" >&2; fi
      ;;
    --registry)
      if [ "$#" -ge 2 ] && [ -n "${2:-}" ]; then REGISTRY="$2"; shift
      else echo "build-feature-scorecard: --registry given without a value — keeping default" >&2; fi
      ;;
    --json) JSON=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "build-feature-scorecard: unknown flag '$1' ignored (fail-safe)" >&2 ;;
  esac
  shift
done

HAVE_JQ=0
command -v jq >/dev/null 2>&1 && HAVE_JQ=1

# emit_error <message> — one stderr line; --json prints the error object; no rows; exit 0.
emit_error() {
  echo "build-feature-scorecard: error: $1" >&2
  if [ "$JSON" -eq 1 ]; then
    if [ "$HAVE_JQ" -eq 1 ]; then
      jq -cn --arg e "$1" --arg s "$SINCE" \
        '{schema_version:1, status:"error", error:$e, since:(if $s == "" then null else $s end),
          features:[], needs_emitter:[], unregistered:[]}'
    else
      printf '%s\n' '{"schema_version":1,"status":"error","error":"jq unavailable","since":null,"features":[],"needs_emitter":[],"unregistered":[]}'
    fi
  fi
  exit 0
}

[ "$HAVE_JQ" -eq 1 ] || emit_error "jq unavailable — nothing can be read"
[ -z "$ERR" ] || emit_error "$ERR"

# ---------------------------------------------------------------------------- registry
if [ ! -f "$REGISTRY" ] || [ ! -r "$REGISTRY" ]; then
  emit_error "registry not found or unreadable: $REGISTRY"
fi
REG_CHECK="$(jq -r '
  if type != "object" then "top level is not an object"
  elif .schema_version != 1 then "schema_version is not 1"
  elif ((.min_sample | type) != "number") or (.min_sample != (.min_sample | floor)) or (.min_sample < 1)
    then "min_sample is not a positive integer"
  elif (.not_features | type) != "array" or ([.not_features[] | select(type != "string")] | length > 0)
    then "not_features is not an array of strings"
  elif (.features | type) != "array" then "features is not an array"
  elif ([.features[] | select(type != "object")] | length > 0) then "a features[] entry is not an object"
  elif ([.features[] | select(((.id | type) != "string") or ((.id | test("^[a-z0-9][a-z0-9_-]*$")) | not))] | length > 0)
    then "a features[] id is missing or not [a-z0-9][a-z0-9_-]*"
  elif ([.features[].id] | length) != ([.features[].id] | unique | length) then "duplicate feature id"
  elif ([.features[] | select((.critical | type) != "boolean")] | length > 0) then "a features[] critical is not a boolean"
  elif ([.features[] | select(.record != "none" and ((.record | type) != "object"))] | length > 0)
    then "a features[] record is neither \"none\" nor an object"
  else "ok" end' "$REGISTRY" 2>/dev/null)"
case "$REG_CHECK" in
  ok) : ;;
  "") emit_error "registry is not valid JSON: $REGISTRY" ;;
  *)  emit_error "registry invalid ($REG_CHECK): $REGISTRY" ;;
esac
MIN_SAMPLE="$(jq -r '.min_sample' "$REGISTRY" 2>/dev/null)"
case "$MIN_SAMPLE" in ''|*[!0-9]*) emit_error "registry invalid (min_sample unreadable): $REGISTRY" ;; esac

# ---------------------------------------------------------------------------- --since
SINCE_TS=""
if [ "$SINCE_GIVEN" -eq 1 ]; then
  case "$SINCE" in
    [0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9])
      SINCE_TS="${SINCE}T00:00:00Z" ;;
    [0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]Z)
      SINCE_TS="$SINCE" ;;
    -*) : ;;   # never hand an option-shaped value to git
    *)
      _repo=""
      if [ -d "$STATE_DIR/.." ] && git -C "$STATE_DIR/.." rev-parse --git-dir >/dev/null 2>&1; then
        _repo="$STATE_DIR/.."
      else
        _repo="."
      fi
      SINCE_TS="$(TZ=UTC git -C "$_repo" log -1 --date=format-local:%Y-%m-%dT%H:%M:%SZ --format=%cd \
        "${SINCE}^{commit}" -- 2>/dev/null | head -1)"
      ;;
  esac
  case "$SINCE_TS" in
    [0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]Z) : ;;
    *) emit_error "--since '$SINCE' is neither a YYYY-MM-DD date, an ISO-8601 UTC time (…T…Z) nor a resolvable commit" ;;
  esac
fi

# ---------------------------------------------------------------------------- scratch
WORK="$(mktemp -d 2>/dev/null || true)"
if [ -z "$WORK" ] || [ ! -d "$WORK" ]; then
  emit_error "scratch dir unavailable (mktemp failed)"
fi
trap 'rm -rf "$WORK" 2>/dev/null' EXIT
ROWS="$WORK/rows.jsonl"; : > "$ROWS"

# ---------------------------------------------------------------------------- token ledger (once)
# Every token_ledger event under logs/, reduced to {a: agent_type, id, ts, proxy, pb, rt}. Read only
# when some feature's cost names the ledger.
LEDGER="$WORK/ledger.jsonl"; : > "$LEDGER"
LEDGER_READ=0
read_ledger() {
  [ "$LEDGER_READ" -eq 1 ] && return 0
  LEDGER_READ=1
  [ -d "$STATE_DIR/logs" ] || return 0
  find "$STATE_DIR/logs" -maxdepth 1 -type f -name '*.jsonl' -exec grep -h 'token_ledger' {} + 2>/dev/null \
    | jq -R -c 'fromjson? | select(type == "object" and .event == "token_ledger")
        | { a: ((.agent_type // "") | tostring), id: ((.agent_id // "") | tostring),
            ts: ((.ts // "") | tostring), proxy: (.proxy == true),
            pb: ((.token_proxy_transcript_bytes // 0) | if type == "number" then . else 0 end),
            rt: ((.usage // {}) as $u
                 | if ($u | type) != "object" then 0
                   else ([ $u.input_tokens, $u.output_tokens, $u.cache_read_input_tokens,
                           $u.cache_creation_input_tokens ]
                         | map(if type == "number" then . else 0 end) | add) end) }' \
    > "$LEDGER" 2>/dev/null || true
  return 0
}

# ---------------------------------------------------------------------------- record helpers
# list_window <glob> <out.json> — in-window record files as [{f, ts}] (ts may be "").
list_window() {
  _glob="$1"; _out="$2"
  _tsv="$WORK/files.tsv"; : > "$_tsv"
  for _f in "$STATE_DIR"/$_glob; do
    [ -f "$_f" ] || continue
    printf '%s\n' "$_f"
  done | awk '
    { p = $0; n = p; sub(/.*\//, "", n); ts = ""
      if (match(n, /20[0-9][0-9]-[01][0-9]-[0-3][0-9]-[0-2][0-9][0-5][0-9][0-5][0-9]/)) {
        s = substr(n, RSTART, RLENGTH)
        ts = substr(s, 1, 10) "T" substr(s, 12, 2) ":" substr(s, 14, 2) ":" substr(s, 16, 2) "Z"
      } else if (match(n, /20[0-9][0-9]-[01][0-9]-[0-3][0-9]/)) {
        ts = substr(n, RSTART, 10) "T00:00:00Z"
      }
      print p "\t" ts }' > "$_tsv" 2>/dev/null
  _tsv2="$WORK/files2.tsv"; : > "$_tsv2"
  while IFS="$(printf '\t')" read -r _p _ts; do
    [ -n "$_p" ] || continue
    if [ -z "$_ts" ]; then
      _ts="$(date -u -r "$_p" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
    fi
    printf '%s\t%s\n' "$_p" "$_ts" >> "$_tsv2"
  done < "$_tsv"
  jq -R -s -c --arg since "$SINCE_TS" '
    [ split("\n")[] | select(. != "") | split("\t") | {f: .[0], ts: (.[1] // "")}
      | select($since == "" or (.ts != "" and .ts >= $since)) ]' "$_tsv2" > "$_out" 2>/dev/null \
    || printf '[]\n' > "$_out"
}

# extract <format> <field> <header> <columns> <files.json> <out.lines>
# Emits "<file>\tseen\t" (file parsed), "<file>\tval\t<value>" and "<file>\tbad\t<reason>" lines.
extract() {
  _fmt="$1"; _field="$2"; _hdr="$3"; _cols="$4"; _fj="$5"; _lo="$6"
  : > "$_lo"
  _n="$(jq 'length' "$_fj" 2>/dev/null)"
  case "$_n" in ''|*[!0-9]*|0) return 0 ;; esac
  _list="$WORK/list.txt"
  jq -r '.[].f' "$_fj" > "$_list" 2>/dev/null
  set --
  while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    if [ -r "$_p" ]; then set -- "$@" "$_p"
    else printf '%s\tbad\t%s\n' "$_p" "file not readable" >> "$_lo"; fi
  done < "$_list"
  [ "$#" -gt 0 ] || return 0
  case "$_fmt" in
    result_block)
      # Two block forms (result_block_parser.py reads the same two): (a) `<header>:` + 2-space
      # indented keys; (b) a `## <header>` heading + `- key: value` bullets. The LAST block wins.
      awk -v hdr="$_hdr" -v key="$_field" '
        function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
        function flush() {
          if (f == "") return
          if (seen) print f "\tseen\t"
          if (have) print f "\tval\t" substr(val, 1, 2000)
        }
        function open(prefix) { inb = 1; seen = 1; have = 0; val = ""; cur = ""; kp = prefix }
        FNR == 1 { flush(); f = FILENAME; inb = 0; seen = 0; have = 0; val = ""; cur = ""; kp = "" }
        { line = $0; sub(/\r$/, "", line); gsub(/\t/, " ", line); t = trim(line) }
        t == hdr ":" { open("  "); next }
        t ~ /^#+[ ]/ { h = t; sub(/^#+[ ]+/, "", h); if (h == hdr) { open("- "); next } }
        inb {
          if (substr(line, 1, 2) == kp && substr(line, 3) ~ /^[A-Za-z_][A-Za-z0-9_]*:/) {
            k = substr(line, 3); i = index(k, ":"); cur = substr(k, 1, i - 1)
            if (cur == key) { have = 1; val = trim(substr(k, i + 1)) }
            next
          }
          if (line ~ /^  /) { if (cur == key) val = val " " t; next }
          if (t == "") next
          inb = 0
        }
        END { flush() }' "$@" > "$_lo" 2>/dev/null || true
      ;;
    text)
      awk -v hdr="$_hdr" -v key="$_field" '
        function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
        function flush() {
          if (f == "") return
          if (seen) print f "\tseen\t"
          if (have) print f "\tval\t" val
        }
        FNR == 1 { flush(); f = FILENAME; seen = (hdr == ""); have = 0; val = "" }
        { line = $0; sub(/\r$/, "", line); gsub(/\t/, " ", line) }
        hdr != "" && trim(line) == hdr ":" { seen = 1 }
        hdr != "" && line ~ /^#+[ ]/ { h = trim(line); sub(/^#+[ ]+/, "", h); if (h == hdr) seen = 1 }
        !have && key != "" && (i = index(line, key)) > 0 {
          have = 1; val = substr(line, i + length(key)); sub(/^[:= ]+/, "", val)
          val = trim(substr(val, 1, 200))
        }
        END { flush() }' "$@" > "$_lo" 2>/dev/null || true
      ;;
    tsv)
      awk -F'\t' -v col="$_field" -v ncol="$_cols" '
        FNR == 1 { f = FILENAME; print f "\tseen\t" }
        { sub(/\r$/, "") }
        $0 == "" { next }
        ncol != "" && NF != ncol + 0 { print f "\tbad\tline " FNR ": " NF " columns, expected " ncol; next }
        NF < col + 0 { print f "\tbad\tline " FNR ": no column " col; next }
        { print f "\tval\t" $(col + 0) }' "$@" > "$_lo" 2>/dev/null || true
      ;;
    json)
      for _p in "$@"; do
        _o="$(jq -r --arg k "$_field" '
          if type != "object" then error("not an object") else . end
          | "seen", (getpath($k | split(".")) | if . == null then empty
                     elif type == "string" then "val\t" + gsub("[\t\r\n]"; " ")
                     else "val\t" + (tojson | gsub("[\t\r\n]"; " ")) end)' "$_p" 2>/dev/null)"
        if [ "$?" -ne 0 ]; then
          printf '%s\tbad\t%s\n' "$_p" "not a parseable JSON object" >> "$_lo"
        else
          printf '%s\n' "$_o" | while IFS= read -r _l; do
            [ -n "$_l" ] && printf '%s\t%s\n' "$_p" "$_l"
          done >> "$_lo"
        fi
      done
      ;;
  esac
  return 0
}

# aggregate <files.json> <lines> <record json> <ran rule> <caught rule> — one metrics object:
# {runs, bad: [...], ran, caught, last_fired}; exits non-zero when a registry rule cannot be evaluated.
aggregate() {
  jq -n -c --slurpfile fs "$1" --rawfile raw "$2" --argjson rec "$3" \
        --argjson ran "$4" --argjson caught "$5" '
    def norm: gsub("^\\s+|\\s+$"; "")
      | if (length >= 2 and startswith("\"") and endswith("\"")) then .[1:-1] else . end;
    def present: (. != "" and . != "null" and . != "~");
    def hit($r):
      if ($r | type) != "object" then false
      elif $r.present == true then true
      elif ($r.match | type) == "string" then test($r.match)
      elif $r.ratio_below_one == true then
        ((capture("^(?<n>[0-9]+)/(?<m>[0-9]+)$")? // null) as $c
         | $c != null and (($c.n | tonumber) < ($c.m | tonumber)))
      else false end;
    def base: split("/") | last;
    ($fs[0]) as $files
    | [ $raw | split("\n")[] | select(. != "") | split("\t")
        | {f: .[0], k: (.[1] // ""), v: (.[2:] | join("\t"))} ] as $L
    | [ $files[] | .f as $f | .ts as $ts
        | [ $L[] | select(.f == $f) ] as $mine
        | [ $mine[] | select(.k == "val") | .v | norm | select(present) ] as $vals
        | (([ $mine[] | select(.k == "seen") ] | length > 0)
           or ((($mine | length) == 0)
               and ($rec.format == "tsv" or ($rec.format == "text" and (($rec.header // "") == ""))))) as $seen
        | ([ $mine[] | select(.k == "bad") | .v ] | first // null) as $bad
        | (if ($rec.valid | type) == "string"
           then [ $vals[] | select(test($rec.valid) | not) ] else [] end) as $invalid
        | { f: $f, ts: $ts,
            why: (if $bad != null then $bad
                  elif ($seen | not) then
                    (if (($rec.header // "") | length) > 0 then "no " + $rec.header + ": block"
                     else "empty or unreadable file" end)
                  elif ($invalid | length) > 0 then
                    "value \"" + ($invalid[0] | .[0:60]) + "\" fails the registry valid pattern"
                  else null end),
            ran: ([ $vals[] | select(hit($ran)) ] | length > 0),
            caught: ([ $vals[] | select(hit($caught)) ] | length > 0) } ] as $ev
    | { runs: ($ev | length),
        bad: [ $ev[] | select(.why != null) | ((.f | base) + ": " + .why) ],
        ran: ([ $ev[] | select(.ran) ] | length),
        caught: (if $caught == "unknown" then "unknown"
                 else ([ $ev[] | select(.ran and .caught) ] | length) end),
        last_fired: ([ $ev[] | select(.ran) | .ts | select(. != "") ] | max) }'
}

# ---------------------------------------------------------------------------- per-feature loop
FEATURES="$WORK/features.jsonl"
jq -c '.features[]' "$REGISTRY" > "$FEATURES" 2>/dev/null || : > "$FEATURES"

# row <feature json> <verdict> [metrics json] [cost_total] [cost_per_catch] [record paths json]
row() {
  jq -n -c --argjson ft "$1" --arg v "$2" --argjson m "${3:-null}" \
           --arg ct "${4:-}" --arg cpc "${5:-}" --argjson rp "${6:-[]}" '
    ($m != null) as $ok
    | { id: $ft.id, critical: $ft.critical, record_paths: $rp,
        runs_available: (if $ok then $m.runs else null end),
        ran: (if $ok then $m.ran else null end),
        caught: (if $ok then $m.caught else null end),
        catch_rate: (if $ok | not then null
                     elif $m.ran == 0 then "n/a"
                     elif $m.caught == "unknown" then "unknown"
                     else ((($m.caught * 100 / $m.ran) | floor | tostring) + "%") end),
        cost_total: (if $ok then $ct else null end),
        cost_per_catch: (if $ok then $cpc else null end),
        last_fired: (if $ok then $m.last_fired else null end),
        verdict: $v }' >> "$ROWS" 2>/dev/null || true
}

FW="$WORK/window.json"; LINES="$WORK/lines.txt"; CLINES="$WORK/cost-lines.txt"
OLDEST=""   # oldest in-window record date across every feature (table header only)
while IFS= read -r ft; do
  [ -n "$ft" ] || continue
  is_none="$(printf '%s' "$ft" | jq -r 'if .record == "none" then "1" else "0" end' 2>/dev/null)"
  if [ "$is_none" = "1" ]; then
    row "$ft" "$V_NONE"
    continue
  fi

  # Field-level registry shape (a bad entry makes only this feature unreadable).
  shape="$(printf '%s' "$ft" | jq -r '
    .record as $r
    | if ($r.glob | type) != "string" or ($r.glob | length) == 0 then "record.glob missing"
      elif ($r.glob | startswith("/")) or ($r.glob | test("(^|/)\\.\\.(/|$)")) then "record.glob leaves the state dir"
      elif ($r.field | type) != "string" or ($r.field | length) == 0 then "record.field missing"
      elif (["result_block", "text", "json", "tsv"] | index([$r.format])) == null then "record.format unknown"
      elif $r.format == "result_block" and (($r.header | type) != "string" or ($r.header | length) == 0)
        then "record.header missing for result_block"
      elif $r.format == "tsv" and (($r.field | test("^[1-9][0-9]*$")) | not) then "record.field is not a column number"
      elif (.ran | type) != "object" then "ran rule is not an object"
      elif .caught != "unknown" and (.caught | type) != "object" then "caught rule is neither \"unknown\" nor an object"
      elif .cost != "none" and ((.cost | type) != "object"
            or (.cost.source as $s | (["token_ledger", "duration"] | index([$s])) == null))
        then "cost is neither none nor a known source"
      elif (.cost | type) == "object" and .cost.source == "token_ledger" and ((.cost.agent | type) != "string")
        then "cost.agent missing"
      elif (.cost | type) == "object" and .cost.source == "duration" and ((.cost.field | type) != "string")
        then "cost.field missing"
      else "ok" end' 2>/dev/null)"
  rec="$(printf '%s' "$ft" | jq -c '.record' 2>/dev/null)"
  glob="$(printf '%s' "$ft" | jq -r '.record.glob // ""' 2>/dev/null)"
  rp="$(jq -n -c --arg sd "$STATE_DIR" --arg g "$glob" --argjson ft "$ft" '
    [ ($sd + "/" + $g) ]
    + (if ($ft.cost | type) == "object" and $ft.cost.source == "token_ledger" then [ $sd + "/logs/*.jsonl" ] else [] end)' 2>/dev/null)"
  [ -n "$rp" ] || rp='[]'
  if [ "$shape" != "ok" ]; then
    row "$ft" "${V_BAD_PREFIX}registry entry: ${shape:-unparseable}" null "" "" "$rp"
    continue
  fi

  fmt="$(printf '%s' "$rec" | jq -r '.format')"
  field="$(printf '%s' "$rec" | jq -r '.field')"
  hdr="$(printf '%s' "$rec" | jq -r '.header // ""')"
  cols="$(printf '%s' "$rec" | jq -r '.columns // "" | tostring')"
  ranr="$(printf '%s' "$ft" | jq -c '.ran')"
  caughtr="$(printf '%s' "$ft" | jq -c '.caught')"

  list_window "$glob" "$FW"
  _old="$(jq -r '[ .[].ts | select(. != "") ] | min // empty' "$FW" 2>/dev/null)"
  if [ -n "$_old" ]; then
    if [ -z "$OLDEST" ]; then OLDEST="$_old"
    else OLDEST="$(jq -n -r --arg a "$OLDEST" --arg b "$_old" '[$a, $b] | min')"; fi
  fi
  extract "$fmt" "$field" "$hdr" "$cols" "$FW" "$LINES"
  m="$(aggregate "$FW" "$LINES" "$rec" "$ranr" "$caughtr" 2>/dev/null)"
  if [ -z "$m" ]; then
    row "$ft" "${V_BAD_PREFIX}registry rule could not be evaluated (check the ran/caught/valid patterns)" null "" "" "$rp"
    continue
  fi
  nbad="$(printf '%s' "$m" | jq '.bad | length')"
  if [ "${nbad:-0}" != "0" ]; then
    why="$(printf '%s' "$m" | jq -r '.bad[0] + (if (.bad | length) > 1 then " (+" + ((.bad | length) - 1 | tostring) + " more)" else "" end)')"
    row "$ft" "${V_BAD_PREFIX}${why}" null "" "" "$rp"
    continue
  fi

  # ---- cost (never 0: no cost record in the window ⇒ unknown)
  csrc="$(printf '%s' "$ft" | jq -r 'if (.cost | type) == "object" then .cost.source else "none" end')"
  cost_total="unknown"; cparts='null'
  case "$csrc" in
    token_ledger)
      read_ledger
      agent="$(printf '%s' "$ft" | jq -r '.cost.agent')"
      cparts="$(jq -s -c --arg ag "$agent" --arg since "$SINCE_TS" '
        [ .[] | select(.a == $ag or (.a | endswith(":" + $ag)))
              | select($since == "" or (.ts != "" and .ts >= $since)) ]
        | group_by(.id) | map(if .[0].id == "" then . else [ last ] end) | add // []
        | { n: length,
            real: ([ .[] | select(.proxy | not) | .rt ] | add // 0),
            proxy: ([ .[] | select(.proxy) | .pb ] | add // 0) }' "$LEDGER" 2>/dev/null)"
      [ -n "$cparts" ] || cparts='null'
      ;;
    duration)
      cfield="$(printf '%s' "$ft" | jq -r '.cost.field')"
      extract "$fmt" "$cfield" "$hdr" "$cols" "$FW" "$CLINES"
      cparts="$(jq -R -s -c '
        [ split("\n")[] | select(. != "") | split("\t") | select(.[1] == "val")
          | (.[2:] | join("\t")) | gsub("^[\\s\"]+|[\\s\"]+$"; "") | tonumber? | select(. >= 0) ]
        | { n: length, secs: (add // 0) }' "$CLINES" 2>/dev/null)"
      [ -n "$cparts" ] || cparts='null'
      ;;
  esac
  read -r cost_total cost_per_catch <<EOF
$(jq -n -r --argjson c "$cparts" --argjson m "$m" '
  def total:
    if $c == null or $c.n == 0 then null
    elif $c.secs != null then (if $c.secs > 0 then { s: $c.secs } else null end)
    else ({ r: $c.real, p: $c.proxy } | if .r == 0 and .p == 0 then null else . end) end;
  def fmt($d):
    if has("s") then ((.s / $d | floor | tostring) + "s")
    else ([ (if .r > 0 then "real:" + (.r / $d | floor | tostring) + "t" else empty end),
            (if .p > 0 then "proxy:" + (.p / $d | floor | tostring) + "B" else empty end) ] | join("+")) end;
  total as $t
  | (if $t == null then "unknown" else ($t | fmt(1)) end) as $tot
  | (if $m.caught == "unknown" then "unknown"
     elif $m.caught == 0 then "n/a"
     elif $t == null then "unknown"
     else ($t | fmt($m.caught)) end) as $per
  | $tot + " " + $per' 2>/dev/null)
EOF
  [ -n "${cost_total:-}" ] || cost_total="unknown"
  [ -n "${cost_per_catch:-}" ] || cost_per_catch="unknown"

  # ---- verdict (precedence in the header; steps 1-2 handled above)
  runs="$(printf '%s' "$m" | jq -r '.runs')"
  ran="$(printf '%s' "$m" | jq -r '.ran')"
  caught="$(printf '%s' "$m" | jq -r '.caught')"
  case "$runs" in ''|*[!0-9]*) runs=0 ;; esac
  case "$ran" in ''|*[!0-9]*) ran=0 ;; esac
  critical="$(printf '%s' "$ft" | jq -r '.critical')"
  if [ "$caught" != "unknown" ] && [ "$caught" -ge 1 ] 2>/dev/null; then
    v="$V_KEEP"
  elif [ "$runs" -lt "$MIN_SAMPLE" ]; then
    v="$V_INSUF"
  elif [ "$caught" = "unknown" ]; then
    v="$V_INSUF"
  elif [ "$ran" -eq 0 ]; then
    v="$V_NEVER"
  elif [ "$ran" -ge "$MIN_SAMPLE" ] && [ "$caught" = "0" ]; then
    v="$V_COST"
  else
    v="$V_INSUF"
  fi
  if [ "$critical" = "true" ]; then
    case "$v" in "$V_NEVER"|"$V_COST") v="$V_CRIT" ;; esac
  fi
  VERDICT="$v"
  row "$ft" "$VERDICT" "$m" "$cost_total" "$cost_per_catch" "$rp"
done < "$FEATURES"

# ---------------------------------------------------------------------------- drift lists
NEEDS="$(jq -c '[ .features[] | select(.record == "none") | .id ]' "$REGISTRY" 2>/dev/null)"
[ -n "$NEEDS" ] || NEEDS='[]'
SCHEMA_OK=0
OPTIONAL="$WORK/optional.txt"; : > "$OPTIONAL"
if [ -f "$SCHEMA_DOC" ] && [ -r "$SCHEMA_DOC" ]; then
  awk '
    !done && /^```yaml/ { inb = 1; next }
    inb && /^```/ { inb = 0; done = 1; next }
    inb && /^  [a-z_][a-z0-9_]*:.*#[ ]*optional/ { s = $0; sub(/^  /, "", s); sub(/:.*/, "", s); print s }
  ' "$SCHEMA_DOC" > "$OPTIONAL" 2>/dev/null && [ -s "$OPTIONAL" ] && SCHEMA_OK=1
fi
if [ "$SCHEMA_OK" -eq 1 ]; then
  UNREG="$(jq -R -s -c --slurpfile reg "$REGISTRY" '
    ($reg[0]) as $r
    | ([ $r.features[] | select((.record | type) == "object") | .record.field ] + $r.not_features) as $known
    | [ split("\n")[] | select(. != "") ] | unique | map(select(. as $o | ($known | index([$o])) == null))' \
    "$OPTIONAL" 2>/dev/null)"
else
  echo "build-feature-scorecard: schema doc unreadable or has no optional fields ($SCHEMA_DOC) — unregistered list not computed" >&2
fi
[ -n "${UNREG:-}" ] || UNREG='[]'

# ---------------------------------------------------------------------------- emission
if [ "$JSON" -eq 1 ]; then
  jq -s -c --arg s "$SINCE" --argjson needs "$NEEDS" --argjson unreg "$UNREG" '
    {schema_version: 1, status: "ok", error: null, since: (if $s == "" then null else $s end),
     features: ., needs_emitter: $needs, unregistered: $unreg}' "$ROWS" 2>/dev/null \
    || emit_error "could not assemble the JSON output"
  exit 0
fi

printf '%s\n' "# Feature scorecard (advisory, read-only — verdicts are suggestions; nothing is changed)"
printf '%s\n' ""
printf '%s\n' "State dir: $STATE_DIR · window: ${SINCE:-all retained records} (oldest record read: ${OLDEST:-none}) · min_sample: $MIN_SAMPLE"
printf '%s\n' "Counts cover only the records still on disk (logs/ is age-swept by retention-sweep.sh). One record file = one run opportunity."
printf '%s\n' ""
printf '%s\n' "| feature | critical | runs available | ran | caught | catch rate | cost total | cost per catch | last fired | verdict |"
printf '%s\n' "|---|---|---|---|---|---|---|---|---|---|"
jq -r '
  def cell: if . == null then "-" else tostring end;
  "| " + .id + " | " + (if .critical then "yes" else "no" end)
  + " | " + (.runs_available | cell) + " | " + (.ran | cell) + " | " + (.caught | cell)
  + " | " + (.catch_rate | cell) + " | " + (.cost_total | cell) + " | " + (.cost_per_catch | cell)
  + " | " + (.last_fired | cell) + " | " + .verdict + " |"' "$ROWS" 2>/dev/null
printf '%s\n' ""
printf '%s\n' "## Needs an emitter"
printf '%s' "$NEEDS" | jq -r 'if length == 0 then "- none" else .[] | "- " + . end' 2>/dev/null
printf '%s\n' ""
printf '%s\n' "## Unregistered (optional SUPERVISOR_RESULT fields in neither the registry nor not_features)"
if [ "$SCHEMA_OK" -eq 1 ]; then
  printf '%s' "$UNREG" | jq -r 'if length == 0 then "- none" else .[] | "- " + . end' 2>/dev/null
else
  printf '%s\n' "- unknown (schema doc unreadable: $SCHEMA_DOC)"
fi

exit 0
