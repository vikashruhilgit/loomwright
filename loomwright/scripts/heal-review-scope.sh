#!/usr/bin/env bash
# heal-review-scope.sh — the deterministic half of Phase 4.5's converging re-review: which files a
# heal round >= 2 reviews, which repeat findings it may drop, and the per-round record that measures
# both. THIS HEADER IS THE SINGLE AUTHORITY for every subcommand, closed value set and record field
# below; the loop (skills/self-heal-advisory/SKILL.md) and the schema doc
# (docs/result-schemas/supervisor-result.md) point here and never restate them.
#
# WHY: every heal round re-reviewed the whole PR, so rounds kept finding new nits in code no fix had
# touched. The owner's rules: a round >= 2 reviews every file the previous round's fix commit(s)
# changed, each read whole, and nothing else (round 1 is always the full PR diff); only a finding
# DISMISSED earlier in the same run may be dropped as a repeat — a re-reported FIXED finding is a fix
# that did not hold, so it stays a normal finding and is only counted. Shipped behind a config key
# whose default (shadow) changes nothing and records what `files` would have done.
#
# CLOSED SETS (defined here once):
#   mode            shadow | files | full     (absent key/file => shadow; anything else => full)
#                     shadow  review and fix exactly like full; records carry would_scope /
#                             in_would_scope / would_suppress for the --shadow-report
#                     files   round >= 2 reviews only the scope files; same-run dismissed repeats
#                             are dropped
#                     full    the kill switch: the loop calls neither `scope` nor `suppress`
#   scope           full | files              (line 1 of `scope`'s output)
#   scope_fallback  the reason a round >= 2 ran full — the FB_* values declared just below this
#                   header ARE the list (each literal lives on exactly one line, so callers and
#                   pin mutations find one home). FB_HELPER_ERROR is never printed by this script:
#                   the CALLER records it when this helper is missing, exits non-zero, or prints
#                   output it cannot parse.
#   outcome         fixed | dismissed | remaining   (finding records; `remaining` = left at the floor
#                   when the loop ended on PASS / ESCALATED / the round cap)
#   severity rank   BLOCKING > HIGH > MEDIUM > LOW  (anything else ranks lowest and is never dropped)
#   record kind     round | finding
#
# FINGERPRINT {file, issue_category, rule} of one CODE_REVIEW_RESULT issue (that issue key set has no
# `rule` field, so one is derived): file = issue.file; issue_category = issue.category, or
# "drift:<drift_kind>" when category is "drift"; rule = the first 12 hex chars of
# `git hash-object --stdin` over the description lower-cased (ASCII), whitespace runs collapsed to one
# space, leading/trailing space trimmed. Exact repeats only: a reworded repeat does not match, which
# only makes a review report MORE. No finding prose is ever stored — only this hash.
#
# RECORD FILE  .supervisor/heal-rounds/<brief basename without .md>.jsonl, one JSON object per line.
# Every record carries run_id (the run's state.md `## Session` session_id, stable on --continue), so a
# re-run of the same brief appends under a new run_id and `prev-sha` / `suppress` read only their own
# run. Closed key sets (any other key — e.g. description, suggestion, finding — is refused):
#   kind: "round"    kind, run_id, iteration, reviewed_sha, pr, mode, scope, scope_files, full_files,
#                    would_scope, scope_fallback, would_suppress, suppressed_repeat, repeat_of_fixed,
#                    review_started_at, review_ended_at
#   kind: "finding"  kind, run_id, iteration, reviewed_sha, pr, file, issue_category, rule, severity,
#                    outcome, fix_commit, in_would_scope
# Required: kind, run_id (non-empty string). When present: iteration is an integer >= 1; mode, scope,
# scope_fallback (or null) and outcome are members of their closed sets; scope_files / full_files /
# suppressed_repeat are numbers >= 0 (scope_files = files a files-scoped review covers or would cover,
# full_files = files in the full PR diff, suppressed_repeat = issues `files` mode dropped);
# would_scope is an array of repo-relative paths; would_suppress and repeat_of_fixed are arrays of
# fingerprint objects (keys file / issue_category / rule only); in_would_scope is a boolean;
# review_started_at / review_ended_at are ISO-8601 UTC strings (YYYY-MM-DDTHH:MM:SSZ).
#
# USAGE
#   heal-review-scope.sh mode [--root <dir>]
#       One line: shadow | files | full, from <root>/.supervisor/config.json `.heal_review_scope`
#       (--root defaults to "."). Never refuses: a config error may only WIDEN a review, so an unknown
#       string, a non-string (null included), a non-object or unparseable config, or jq absent => full.
#   heal-review-scope.sh scope --round <N> --head <sha> [--prev <sha|->] [--root <dir>]
#       Line 1 `scope: full` or `scope: files`. Under files, one repo-relative path per following line:
#       every file `<prev>..<head>` changed and did not delete (sorted, unique; the comparison is the
#       two commits, independent of any base branch, so stacked PRs need no special case). Under a
#       fallback, line 2 is `scope_fallback: <reason>`. Round 1 => `scope: full` and NO fallback line.
#       Checks for round >= 2, in order: --prev `-` / absent / not a commit => missing prev;
#       <prev> not an ancestor of <head> => not ancestor; any merge commit in <prev>..<head> => merge
#       commit; no file left to scope => empty scope.
#   heal-review-scope.sh fingerprint            stdin: one issue JSON object => one fingerprint object.
#   heal-review-scope.sh record --file <jsonl>  stdin: JSON lines. Validates every line against the
#       closed key sets above and appends the valid ones (creating the parent dir). On ANY failure —
#       a refused line, jq absent, a mkdir / append error — prints ONE stderr line
#       `heal_round_record_failed: <reason>` and still exits 0 (fail-SAFE: the loop continues).
#   heal-review-scope.sh prev-sha --file <jsonl> --run-id <id>
#       The reviewed_sha of run <id>'s LAST round record, or nothing (other runs' records and
#       unparseable lines are ignored; a missing file prints nothing).
#   heal-review-scope.sh suppress --file <jsonl> --run-id <id> [--count-only]
#       stdin: a JSON array of issues. stdout: ONE JSON object
#         {"kept":[issues...],"suppressed":[fingerprint...],"count":N,"repeat_of_fixed":[fingerprint...]}
#       An issue is a suppressible repeat when its fingerprint equals a finding record of the SAME run
#       with outcome dismissed AND its severity ranks no higher than that record's (the highest such
#       record counts; an unranked issue severity is never suppressible). An issue matching a same-run
#       outcome-fixed record is NEVER suppressed: it stays in `kept` and is listed in
#       `repeat_of_fixed`. --count-only (shadow) keeps every issue; `suppressed` / `count` then name
#       the would-suppress set. Fails toward reporting MORE: a missing records file means no
#       records; an unreadable one, jq absent, or a fingerprint error keeps every issue with count 0
#       plus one stderr line `heal_review_suppress_failed: <reason>`; stdin that is not a JSON array
#       prints NOTHING on stdout plus that stderr line (the caller keeps its own unfiltered list).
#   heal-review-scope.sh --shadow-report [--since <sha>] [--dir <dir>] [--root <dir>]
#       READ-ONLY promotion evidence over every *.jsonl in --dir (default .supervisor/heal-rounds):
#       every round record with mode shadow and iteration >= 2 (with --since, only rounds whose
#       reviewed_sha descends from <sha> in the --root repo; a reviewed_sha that is not a commit there
#       is counted as `unreachable: N`). Prints rounds, findings_total (finding records of those
#       rounds), outside_scope (in_would_scope false; one line each: fingerprint + PR),
#       would_suppress (count, one line each: fingerprint + PR), repeat_of_fixed (one line each:
#       fingerprint + PR), skipped_review_minutes_est (sum of review minutes x (1 - scope_files /
#       full_files) over non-fallback rounds — an ESTIMATE) and fallbacks by reason. Writes nothing.
#
# EXIT: 0 for every answer and every fail-safe path above; 2 for a usage error only (unknown
# subcommand or argument, a missing / malformed required argument, a `scope --head` that is not a
# commit in --root, fingerprint stdin that is not one JSON object, an unresolvable --since), with the
# reason on stderr and nothing on stdout. The caller treats any non-zero exit as FB_HELPER_ERROR.
#
# Bash 3.2 / BSD-safe; `set -uo pipefail`; jq + git only; jq via "${JQ:-jq}" (test seam).

set -uo pipefail

FB_NOT_ANCESTOR=not_ancestor
FB_EMPTY_SCOPE=empty_scope
FB_MERGE_COMMIT=merge_commit
FB_MISSING_PREV=missing_prev_sha
FB_HELPER_ERROR=helper_error

JQ_BIN="${JQ:-jq}"

usage_error() { printf 'heal-review-scope: %s\n' "$1" >&2; exit 2; }
have_jq() { command -v "$JQ_BIN" >/dev/null 2>&1; }

# The jq definitions every reader shares: severity rank and the fingerprint key.
JQ_DEFS='
  def rank: if type != "string" then 0 else ascii_upcase
    | if . == "BLOCKING" then 4 elif . == "HIGH" then 3
      elif . == "MEDIUM" then 2 elif . == "LOW" then 1 else 0 end end;
  def fpkey: [(.file // ""), (.issue_category // ""), (.rule // "")] | map(tostring) | join("\u0001");
  def fptext: "\(.file // "")|\(.issue_category // "")|\(.rule // "")";
'

# ---------------------------------------------------------------- mode
cmd_mode() {
  local root="." cfg kind
  while [ $# -gt 0 ]; do
    case "$1" in
      --root) [ $# -ge 2 ] || usage_error "--root needs a value"; root="$2"; shift 2 ;;
      *) usage_error "mode: unknown argument: $1" ;;
    esac
  done
  cfg="$root/.supervisor/config.json"
  if [ ! -f "$cfg" ]; then echo shadow; exit 0; fi
  have_jq || { echo full; exit 0; }
  # Slurped, so the WHOLE file must parse as exactly one object.
  kind="$("$JQ_BIN" -rse 'if length == 1 and (.[0] | type) == "object" then .[0]
      | if has("heal_review_scope")
        then (.heal_review_scope | if type == "string" then "s:" + . else "bad" end)
        else "absent" end
    else "bad" end' "$cfg" 2>/dev/null)" || kind="bad"
  case "$kind" in
    s:shadow) echo shadow ;;
    s:files) echo files ;;
    s:full) echo full ;;
    absent) echo shadow ;;
    *) echo full ;;
  esac
  exit 0
}

# ---------------------------------------------------------------- scope
fallback() { printf 'scope: full\nscope_fallback: %s\n' "$1"; exit 0; }

cmd_scope() {
  local round="" PREV="-" head_in="" HEAD_SHA="" ROOT="." files=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --round) [ $# -ge 2 ] || usage_error "--round needs a value"; round="$2"; shift 2 ;;
      --prev) [ $# -ge 2 ] || usage_error "--prev needs a value"; PREV="$2"; shift 2 ;;
      --head) [ $# -ge 2 ] || usage_error "--head needs a value"; head_in="$2"; shift 2 ;;
      --root) [ $# -ge 2 ] || usage_error "--root needs a value"; ROOT="$2"; shift 2 ;;
      *) usage_error "scope: unknown argument: $1" ;;
    esac
  done
  case "$round" in ''|*[!0-9]*) usage_error "scope: --round must be a positive integer" ;; esac
  [ "$round" -ge 1 ] || usage_error "scope: --round must be a positive integer"
  [ -n "$head_in" ] || usage_error "scope: --head is required"
  if [ "$round" -eq 1 ]; then echo "scope: full"; exit 0; fi
  HEAD_SHA="$(git -C "$ROOT" rev-parse --verify --quiet "$head_in^{commit}" 2>/dev/null)" \
    || usage_error "scope: --head '$head_in' is not a commit in $ROOT"
  if [ -z "$PREV" ] || [ "$PREV" = "-" ]; then fallback "$FB_MISSING_PREV"; fi
  PREV="$(git -C "$ROOT" rev-parse --verify --quiet "$PREV^{commit}" 2>/dev/null)" || fallback "$FB_MISSING_PREV"
  git -C "$ROOT" merge-base --is-ancestor "$PREV" "$HEAD_SHA" 2>/dev/null || fallback "$FB_NOT_ANCESTOR"
  [ -z "$(git -C "$ROOT" rev-list --merges "$PREV..$HEAD_SHA" 2>/dev/null)" ] || fallback "$FB_MERGE_COMMIT"
  files="$(git -C "$ROOT" -c core.quotepath=off diff --name-only --diff-filter=d "$PREV" "$HEAD_SHA" 2>/dev/null | env LC_ALL=C sort -u)"
  [ -n "$files" ] || fallback "$FB_EMPTY_SCOPE"
  echo "scope: files"
  printf '%s\n' "$files"
  exit 0
}

# ---------------------------------------------------------------- fingerprint
# fingerprints_of — stdin: a JSON array; stdout: a JSON array of the same length holding each
# element's fingerprint object, or null for a non-object element. Returns 1 on any error.
fingerprints_of() {
  local arr norms line h hashes=""
  arr="$(cat)"
  norms="$(printf '%s' "$arr" | "$JQ_BIN" -r '.[] | if type == "object"
      then "O " + ((.description // "") | tostring | ascii_downcase | gsub("\\s+"; " ")
                   | sub("^ "; "") | sub(" $"; ""))
      else "N" end' 2>/dev/null)" || return 1
  if [ -n "$norms" ]; then
    while IFS= read -r line; do
      case "$line" in
        N) h="null" ;;
        "O "*)
          h="$(printf '%s' "${line#O }" | git hash-object --stdin 2>/dev/null)" || return 1
          [ ${#h} -ge 12 ] || return 1
          h="\"${h:0:12}\"" ;;
        *) return 1 ;;
      esac
      hashes="${hashes:+$hashes,}$h"
    done <<EOF
$norms
EOF
  fi
  printf '%s' "$arr" | "$JQ_BIN" -c --argjson h "[$hashes]" '
    if length != ($h | length) then error("misaligned") else . end
    | [range(0; length) as $i | .[$i]
       | if type == "object" then
           {file: ((.file // "") | tostring),
            issue_category: (if .category == "drift"
                             then "drift:" + ((.drift_kind // "") | tostring)
                             else ((.category // "") | tostring) end),
            rule: $h[$i]}
         else null end]' 2>/dev/null || return 1
}

cmd_fingerprint() {
  local body out
  [ $# -eq 0 ] || usage_error "fingerprint: takes no arguments (the issue JSON is read from stdin)"
  have_jq || usage_error "fingerprint: jq not found"
  body="$(cat)"
  printf '%s' "$body" | "$JQ_BIN" -se 'length == 1 and (.[0] | type) == "object"' >/dev/null 2>&1 \
    || usage_error "fingerprint: stdin must be exactly one JSON object"
  out="$(printf '[%s]' "$body" | fingerprints_of)" || usage_error "fingerprint: could not hash the description"
  printf '%s' "$out" | "$JQ_BIN" -c '.[0]'
  exit 0
}

# ---------------------------------------------------------------- record
record_failed() { printf 'heal_round_record_failed: %s\n' "$1" >&2; exit 0; }

cmd_record() {
  local file="" body verdicts valid nbad first err=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --file) [ $# -ge 2 ] || usage_error "--file needs a value"; file="$2"; shift 2 ;;
      *) usage_error "record: unknown argument: $1" ;;
    esac
  done
  [ -n "$file" ] || usage_error "record: --file is required"
  body="$(cat)"
  [ -n "$body" ] || exit 0
  have_jq || record_failed "jq not found"
  verdicts="$(printf '%s\n' "$body" | "$JQ_BIN" -R -r \
      --arg fbs "$FB_NOT_ANCESTOR $FB_EMPTY_SCOPE $FB_MERGE_COMMIT $FB_MISSING_PREV $FB_HELPER_ERROR" '
    def round_keys: ["kind","run_id","iteration","reviewed_sha","pr","mode","scope","scope_files",
      "full_files","would_scope","scope_fallback","would_suppress","suppressed_repeat",
      "repeat_of_fixed","review_started_at","review_ended_at"];
    def finding_keys: ["kind","run_id","iteration","reviewed_sha","pr","file","issue_category",
      "rule","severity","outcome","fix_commit","in_would_scope"];
    def fp_ok: type == "object" and ((keys - ["file","issue_category","rule"]) | length) == 0;
    def count_ok($k): (has($k) | not) or (.[$k] | type == "number" and . >= 0);
    def common:
      if (has("iteration") | not) or (.iteration | type == "number" and . >= 1 and . == floor) then ""
      else "iteration is not an integer >= 1" end;
    def why_round:
      ((keys - round_keys) | join(",")) as $x
      | if $x != "" then "unknown key(s): " + $x
        elif common != "" then common
        elif has("mode") and (.mode | IN("shadow", "files", "full") | not) then "mode outside its closed set"
        elif has("scope") and (.scope | IN("full", "files") | not) then "scope outside its closed set"
        elif has("scope_fallback") and .scope_fallback != null
             and ((.scope_fallback | type) != "string"
                  or (.scope_fallback as $f | $fbs | split(" ") | index([$f]) | not))
          then "scope_fallback outside its closed set"
        elif (count_ok("scope_files") and count_ok("full_files") and count_ok("suppressed_repeat")) | not
          then "a count field is not a number >= 0"
        elif has("would_scope") and (.would_scope | type != "array" or any(.[]; type != "string"))
          then "would_scope is not an array of paths"
        elif has("would_suppress") and (.would_suppress | type != "array" or any(.[]; fp_ok | not))
          then "would_suppress is not an array of fingerprints"
        elif has("repeat_of_fixed") and (.repeat_of_fixed | type != "array" or any(.[]; fp_ok | not))
          then "repeat_of_fixed is not an array of fingerprints"
        else "" end;
    def why_finding:
      ((keys - finding_keys) | join(",")) as $x
      | if $x != "" then "unknown key(s): " + $x
        elif common != "" then common
        elif has("outcome") and (.outcome | IN("fixed", "dismissed", "remaining") | not)
          then "outcome outside its closed set"
        elif has("in_would_scope") and (.in_would_scope | type != "boolean") then "in_would_scope is not a boolean"
        else "" end;
    select(length > 0)
    | (try fromjson catch null) as $r
    | if ($r | type) != "object" then "ERR line is not a JSON object"
      elif ($r.run_id | type) != "string" or $r.run_id == "" then "ERR missing run_id"
      elif $r.kind == "round" then ($r | why_round) as $w
        | if $w == "" then "OK " + ($r | tojson) else "ERR round: " + $w end
      elif $r.kind == "finding" then ($r | why_finding) as $w
        | if $w == "" then "OK " + ($r | tojson) else "ERR finding: " + $w end
      else "ERR kind is not round or finding" end
  ' 2>/dev/null)" || record_failed "could not parse the input"
  valid="$(printf '%s\n' "$verdicts" | sed -n 's/^OK //p')"
  nbad="$(printf '%s\n' "$verdicts" | grep -c '^ERR ' || true)"
  first="$(printf '%s\n' "$verdicts" | sed -n 's/^ERR //p' | head -n 1)"
  if [ "${nbad:-0}" -gt 0 ]; then err="$nbad record(s) refused (first: $first)"; fi
  if [ -n "$valid" ]; then
    if ! mkdir -p "$(dirname "$file")" 2>/dev/null; then
      err="cannot create the directory of $file${err:+; $err}"
    elif ! printf '%s\n' "$valid" >> "$file" 2>/dev/null; then
      err="cannot append to $file${err:+; $err}"
    fi
  fi
  [ -z "$err" ] || record_failed "$err"
  exit 0
}

# ---------------------------------------------------------------- prev-sha
cmd_prev_sha() {
  local file="" rid=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --file) [ $# -ge 2 ] || usage_error "--file needs a value"; file="$2"; shift 2 ;;
      --run-id) [ $# -ge 2 ] || usage_error "--run-id needs a value"; rid="$2"; shift 2 ;;
      *) usage_error "prev-sha: unknown argument: $1" ;;
    esac
  done
  [ -n "$file" ] && [ -n "$rid" ] || usage_error "prev-sha: --file and --run-id are required"
  [ -r "$file" ] && have_jq || exit 0
  "$JQ_BIN" -R -r --arg rid "$rid" '(try fromjson catch null)
    | select(type == "object" and .kind == "round" and .run_id == $rid)
    | .reviewed_sha | select(type == "string" and . != "")' "$file" 2>/dev/null | tail -n 1
  exit 0
}

# ---------------------------------------------------------------- suppress
suppress_failed() { printf 'heal_review_suppress_failed: %s\n' "$1" >&2; }

# keep_all <issues-json> <reason> — the fail-safe answer: every issue kept, nothing suppressed.
keep_all() {
  suppress_failed "$2"
  printf '{"kept":%s,"suppressed":[],"count":0,"repeat_of_fixed":[]}\n' "$1"
  exit 0
}

cmd_suppress() {
  local file="" run="" countonly=0 input fps recfile out
  while [ $# -gt 0 ]; do
    case "$1" in
      --file) [ $# -ge 2 ] || usage_error "--file needs a value"; file="$2"; shift 2 ;;
      --run-id) [ $# -ge 2 ] || usage_error "--run-id needs a value"; run="$2"; shift 2 ;;
      --count-only) countonly=1; shift ;;
      *) usage_error "suppress: unknown argument: $1" ;;
    esac
  done
  [ -n "$file" ] && [ -n "$run" ] || usage_error "suppress: --file and --run-id are required"
  input="$(cat)"
  if ! have_jq; then
    # Without jq the input cannot be checked; echo it back only if it at least looks like an array.
    case "$input" in
      \[*\]) keep_all "$input" "jq not found" ;;
      *) suppress_failed "jq not found"; exit 0 ;;
    esac
  fi
  if ! printf '%s' "$input" | "$JQ_BIN" -se 'length == 1 and (.[0] | type) == "array"' >/dev/null 2>&1; then
    suppress_failed "stdin is not a JSON array"
    exit 0
  fi
  input="$(printf '%s' "$input" | "$JQ_BIN" -c '.')"
  recfile="/dev/null"
  if [ -e "$file" ]; then
    [ -r "$file" ] || keep_all "$input" "cannot read $file"
    recfile="$file"
  fi
  fps="$(printf '%s' "$input" | fingerprints_of)" || keep_all "$input" "could not fingerprint the issues"
  out="$(printf '%s' "$input" | "$JQ_BIN" -c --rawfile raw "$recfile" --argjson fps "$fps" \
      --arg run "$run" --arg countonly "$countonly" "$JQ_DEFS"'
    . as $issues
    | [ $raw | split("\n")[] | select(length > 0) | (try fromjson catch null)
        | select(type == "object" and .kind == "finding")
        | select(.run_id == $run)
      ] as $mine
    | ([ $mine[] | select(.outcome == "dismissed") ]
        | group_by(fpkey) | map({key: (.[0] | fpkey), value: (map(.severity | rank) | max)})
        | from_entries) as $dis
    | ([ $mine[] | select(.outcome == "fixed") | fpkey ] | unique) as $fixed
    | [ range(0; $issues | length) as $i
        | {issue: $issues[$i], fp: $fps[$i]}
        | .cls = (if .fp == null then "keep"
                  else (.fp | fpkey) as $k | (.issue.severity | rank) as $r
                    | if any($fixed[]; . == $k) then "fixed"
                      elif ($dis | has($k)) and $r >= 1 and $r <= $dis[$k] then "suppress"
                      else "keep" end end) ] as $rows
    | {kept: [ $rows[] | select(.cls != "suppress" or $countonly == "1") | .issue ],
       suppressed: [ $rows[] | select(.cls == "suppress") | .fp ],
       count: ([ $rows[] | select(.cls == "suppress") ] | length),
       repeat_of_fixed: [ $rows[] | select(.cls == "fixed") | .fp ]}
  ' 2>/dev/null)" || keep_all "$input" "could not evaluate the records in $file"
  printf '%s\n' "$out"
  exit 0
}

# ---------------------------------------------------------------- --shadow-report
cmd_shadow_report() {
  local DIR=".supervisor/heal-rounds" since="" ROOT="." since_sha="" recs shas sha
  local keep="" unreach="" f n=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --since) [ $# -ge 2 ] || usage_error "--since needs a value"; since="$2"; shift 2 ;;
      --dir) [ $# -ge 2 ] || usage_error "--dir needs a value"; DIR="$2"; shift 2 ;;
      --root) [ $# -ge 2 ] || usage_error "--root needs a value"; ROOT="$2"; shift 2 ;;
      *) usage_error "--shadow-report: unknown argument: $1" ;;
    esac
  done
  have_jq || usage_error "--shadow-report: jq not found"
  if [ -n "$since" ]; then
    since_sha="$(git -C "$ROOT" rev-parse --verify --quiet "$since^{commit}" 2>/dev/null)" \
      || usage_error "--shadow-report: --since '$since' is not a commit in $ROOT"
  fi
  recs="[]"
  if [ -d "$DIR" ]; then
    for f in "$DIR"/*.jsonl; do [ -f "$f" ] && n=$((n + 1)); done
    if [ "$n" -gt 0 ]; then
      recs="$(for f in "$DIR"/*.jsonl; do
          [ -f "$f" ] || continue
          "$JQ_BIN" -R -c --arg src "$f" '(try fromjson catch null)
            | select(type == "object") | . + {_src: $src}' "$f" 2>/dev/null
        done | "$JQ_BIN" -s -c '.')" || recs="[]"
    fi
  fi
  if [ -n "$since_sha" ]; then
    shas="$(printf '%s' "$recs" | "$JQ_BIN" -r '.[] | select(.kind == "round" and .mode == "shadow"
        and ((.iteration // 0) | type == "number" and . >= 2)) | (.reviewed_sha // "") | tostring' \
        | env LC_ALL=C sort -u)"
    while IFS= read -r sha; do
      [ -n "$sha" ] || continue
      if ! git -C "$ROOT" cat-file -e "$sha^{commit}" 2>/dev/null; then
        unreach="${unreach:+$unreach,}\"$sha\""
      elif git -C "$ROOT" merge-base --is-ancestor "$since_sha" "$sha" 2>/dev/null; then
        keep="${keep:+$keep,}\"$sha\""
      fi
    done <<EOF
$shas
EOF
  fi
  printf '%s' "$recs" | "$JQ_BIN" -r --arg dir "$DIR" --arg since "$since_sha" \
      --argjson keep "[$keep]" --argjson unreach "[$unreach]" "$JQ_DEFS"'
    def prtext: if .pr == null then "-" else (.pr | tostring) end;
    def rkey: "\(._src)\u0001\(.run_id)\u0001\(.iteration)";
    def minutes: (try ((.review_ended_at | fromdateiso8601) - (.review_started_at | fromdateiso8601)) catch null)
      | if type == "number" and . > 0 then . / 60 else 0 end;
    . as $all
    | [ $all[] | select(.kind == "round" and .mode == "shadow"
          and ((.iteration // 0) | type == "number" and . >= 2)) ] as $r0
    | (if $since == "" then $r0
       else [ $r0[] | select((.reviewed_sha // "" | tostring) as $s
                              | any($keep[]; . == $s)) ] end) as $rounds
    | ([ $rounds[] | {key: rkey, value: prtext} ] | from_entries) as $pr_of
    | [ $all[] | select(.kind == "finding") | select($pr_of[rkey] != null) ] as $findings
    | [ $findings[] | select(.in_would_scope == false) ] as $outside
    | [ $rounds[] | prtext as $p | (.would_suppress // [] | if type == "array" then .[] else empty end)
        | "  - \(fptext) pr=\($p)" ] as $ws_lines
    | ([ $rounds[] | .would_suppress // [] | if type == "array" then length
                                             elif type == "number" then . else 0 end ] | add // 0) as $ws_n
    | [ $rounds[] | prtext as $p | (.repeat_of_fixed // [] | if type == "array" then .[] else empty end)
        | "  - \(fptext) pr=\($p)" ] as $rf_lines
    | ([ $rounds[] | select(.scope_fallback == null)
         | select((.full_files | type) == "number" and .full_files > 0 and (.scope_files | type) == "number")
         | minutes * (1 - ([.scope_files / .full_files, 1] | min)) ] | add // 0) as $mins
    | ([ $rounds[] | select(.scope_fallback != null) | .scope_fallback | tostring ]
        | group_by(.) | map("\(.[0])=\(length)") | join(" ")) as $fb
    | "heal-review-scope shadow report (read-only)",
      "dir: \($dir)",
      "rounds: \($rounds | length)",
      "findings_total: \($findings | length)",
      "outside_scope: \($outside | length)",
      ($outside[] | "  - \(fptext) pr=\($pr_of[rkey])"),
      "would_suppress: \($ws_n)",
      $ws_lines[],
      "repeat_of_fixed: \($rf_lines | length)",
      $rf_lines[],
      "skipped_review_minutes_est: \((($mins * 10 + 0.5) | floor) / 10) (estimate: sum of review minutes x (1 - scope_files / full_files) over non-fallback rounds)",
      "fallbacks: \(if $fb == "" then "none" else $fb end)",
      (if $since == "" then empty else "unreachable: \($unreach | length)" end)
  '
  exit 0
}

SUB="${1:-}"
[ $# -gt 0 ] && shift
case "$SUB" in
  mode) cmd_mode "$@" ;;
  scope) cmd_scope "$@" ;;
  fingerprint) cmd_fingerprint "$@" ;;
  record) cmd_record "$@" ;;
  prev-sha) cmd_prev_sha "$@" ;;
  suppress) cmd_suppress "$@" ;;
  --shadow-report) cmd_shadow_report "$@" ;;
  *) usage_error "usage: heal-review-scope.sh mode|scope|fingerprint|record|prev-sha|suppress|--shadow-report ..." ;;
esac
