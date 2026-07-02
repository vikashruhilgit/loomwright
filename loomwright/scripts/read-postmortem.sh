#!/usr/bin/env bash
# read-postmortem.sh — fail-safe ADVISORY read-back of the postmortem churn ledger.
# (New file — Learning Loop Phase 4 churn-ledger read side; parity with read-lessons.sh /
#  read-project-memory.sh advisory-reader convention.)
#
# Given a set of touched file paths, summarize prior churn from
# .supervisor/postmortem/results.jsonl so planning / self-heal can surface
# "this file churned before, with these root-cause classes." For each corpus line whose
# `changed_paths` array shares at least one EXACT path with the input set, that entry is
# treated as a prior-churn hit. Aggregates recurring root-cause `class` and `flow_stage`
# values (with counts), prior churn-round count, and whether any round was a self_heal_miss.
#
# REPO SCOPING: matches are scoped to the CURRENT repo when it can be derived from the git
# remote (`owner/repo` parsed from remote.origin.url). The repo match is CASE-INSENSITIVE
# (GitHub slugs are case-insensitive). The corpus may aggregate entries from
# multiple repos because `/pr-postmortem` can analyze an EXTERNAL PR and append its line
# (carrying that PR's `repo` field) to the single local results.jsonl — so a common path
# (README.md, package.json, src/index.ts) recorded from an unrelated repo would otherwise
# produce a FALSE "prior churn" hit. When the current repo is undeterminable (no remote / parse
# fails), matching falls back to UNSCOPED (fail-open) — same behavior as before this scoping.
#
# Output is ADVISORY and prefixed with a subordinate-to-CLAUDE.md banner. This helper NEVER
# gates anything; its output is always subordinate to CLAUDE.md (on conflict, CLAUDE.md wins).
#
# INPUT CONTRACT:
#   Touched paths are supplied as command-line ARGUMENTS or newline-separated on STDIN.
#   ARGS TAKE PRECEDENCE: when one or more path args are given, STDIN is NEVER read — so an
#   args-bearing call can NEVER block waiting on stdin, even in a non-TTY context (CI, a hook,
#   or an agent's inline Bash where stdin is an open-but-idle pipe). STDIN is consulted ONLY
#   when NO path args were given (and stdin is not a terminal). With no paths supplied at all
#   → exit 0, quiet (nothing to match against).
#     Examples:
#       read-postmortem.sh src/auth/guard.ts src/app.ts        # args (stdin ignored)
#       git diff --name-only origin/main...HEAD | read-postmortem.sh   # no args → reads stdin
#
# FAIL-SAFE (hard requirement): ALWAYS exit 0 — a read must never break its caller.
#   - corpus absent/empty            → exit 0 quiet
#   - jq unavailable                 → emit nothing, exit 0 (mirror read-lessons.sh)
#   - a malformed JSONL line         → skipped element-locally, never crashes the script
#   jq-only parsing — untrusted corpus text (paths/summary/evidence) is NEVER string-
#   interpolated into a shell command or another jq program; inputs cross the boundary via
#   --rawfile / --slurpfile / --argjson only.
#
# Exit: always 0; diagnostics go to stderr + .supervisor/logs/memory.log (mirrors read-lessons.sh).

set -uo pipefail   # `set -e` intentionally omitted — a read must NEVER fail its caller.

GITROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$GITROOT" 2>/dev/null || true

# Best-effort current-repo slug `owner/repo` from the git remote. Handles both
# git@host:owner/repo.git and https://host/owner/repo.git; empty if no remote / parse fails.
# When empty, the jq aggregation below stays UNSCOPED (fail-open) — see header REPO SCOPING.
CUR_REPO="$(git config --get remote.origin.url 2>/dev/null | sed -E 's#^(git@|https?://)[^/:]+[:/]+##; s#\.git$##' 2>/dev/null || true)"

CORPUS=".supervisor/postmortem/results.jsonl"
LOG=".supervisor/logs/memory.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

# Bounds so the advisory can never flood a prompt.
MAX_PATHS=5
MAX_CLASSES=8
MAX_STAGES=8

# 1. Collect touched paths. ARGS TAKE PRECEDENCE: when path args are present, STDIN is NEVER
#    read, so an args-bearing call can never block on an open-but-idle stdin in a non-TTY
#    context (the fail-safe "a read must never hang its caller" invariant). STDIN is consulted
#    ONLY when no args were given AND stdin is a pipe. Quiet exit if neither yields a path.
paths_file="$(mktemp)"; trap 'rm -f "$paths_file" 2>/dev/null' EXIT
if [ "$#" -gt 0 ]; then
  for a in "$@"; do
    [ -n "$a" ] && printf '%s\n' "$a" >> "$paths_file"
  done
elif [ ! -t 0 ]; then
  # No args — accept newline-separated paths piped on stdin. (When stdin is a terminal and no
  # args were given there is nothing to read, so this branch is skipped — no interactive hang.)
  while IFS= read -r line; do
    [ -n "$line" ] && printf '%s\n' "$line" >> "$paths_file"
  done
fi
# De-dup, drop blanks.
sort -u "$paths_file" -o "$paths_file" 2>/dev/null || true
[ -s "$paths_file" ] || exit 0   # no input paths → nothing to match against

# 2. Tooling + corpus presence (fail-safe, quiet).
if ! command -v jq >/dev/null 2>&1; then
  msg="read-postmortem: jq unavailable — churn ledger unreadable, emitting nothing (fail-safe)"
  echo "$msg" >&2
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" "$msg" >> "$LOG" 2>/dev/null || true
  exit 0
fi
[ -s "$CORPUS" ] || exit 0   # absent or empty corpus → emit nothing

# 3. jq aggregation. The query paths cross the boundary as a JSON array via --slurpfile of a
#    raw-string slurp; corpus is streamed line-by-line with `-R 'fromjson? // empty'` so a
#    malformed line is skipped element-locally (never aborts). No untrusted text is ever
#    interpolated into the program — everything flows through jq's data model.
#
#    `(.changed_paths // [])` tolerates OLD lines lacking the field (they contribute nothing);
#    we deliberately use `// []` (NOT `// empty`) so an explicit empty array is handled the
#    same as absent and a present non-empty array is honored verbatim (no falsy coercion).
query_json="$(jq -R . "$paths_file" 2>/dev/null | jq -s . 2>/dev/null)"
[ -n "$query_json" ] || exit 0

summary="$(
  jq -R 'fromjson? // empty' "$CORPUS" 2>/dev/null | jq -s \
    --argjson query "$query_json" \
    --arg cur_repo "$CUR_REPO" \
    --argjson max_paths "$MAX_PATHS" \
    --argjson max_classes "$MAX_CLASSES" \
    --argjson max_stages "$MAX_STAGES" '
    # Set of query paths for fast membership.
    ($query | map(select(. != null and . != "")) | unique) as $q
    | ($q | map({(.): true}) | add // {}) as $qset
    # Keep only entries whose changed_paths overlap the query set AND — when the current repo is
    # known ($cur_repo != "") — whose `repo` matches it. The match is CASE-INSENSITIVE (GitHub
    # slugs are case-insensitive, so a corpus repo:"Owner/Repo" must still match a CUR_REPO of
    # owner/repo, and vice-versa) — both sides are lowercased inside jq via ascii_downcase.
    # When $cur_repo == "" (undeterminable), the repo predicate is vacuously true
    # (fail-open / unscoped). Uses (.repo // "") falsy coercion (NOT // empty) for consistency
    # with the existing discipline.
    | [ .[]
        | . as $e
        | select($cur_repo == "" or ((($e.repo) // "") | ascii_downcase) == ($cur_repo | ascii_downcase))
        | ((($e.changed_paths) // []) | map(select($qset[.] == true))) as $overlap
        | select(($overlap | length) > 0)
        | {overlap: $overlap, cats: (($e.categories) // []), shm: (($e.self_heal_misses) // 0)}
      ] as $hits
    | if ($hits | length) == 0 then
        "EMPTY"
      else
        # Which query paths actually churned (bounded).
        ([ $hits[].overlap[] ] | group_by(.) | map({path: .[0], n: length})
         | sort_by(-.n) | .[0:$max_paths]) as $paths
        # Recurring root-cause classes across all hit rounds (bounded).
        | ([ $hits[].cats[]? | .class | select(. != null and . != "") ]
           | group_by(.) | map({class: .[0], n: length}) | sort_by(-.n)
           | .[0:$max_classes]) as $classes
        # Recurring flow stages across all hit rounds (bounded).
        | ([ $hits[].cats[]? | .flow_stage | select(. != null and . != "") ]
           | group_by(.) | map({stage: .[0], n: length}) | sort_by(-.n)
           | .[0:$max_stages]) as $stages
        # Total prior churn rounds and any self_heal_miss.
        | ([ $hits[].cats[]? ] | length) as $rounds
        | (([ $hits[].cats[]? | .self_heal_miss ] | any(. == true))
           or (([ $hits[].shm ] | add // 0) > 0)) as $any_shm
        | (($hits | length)) as $n_entries
        | "PATHS\t" + (($paths | map(.path + " (" + (.n|tostring) + ")")) | join(", "))
          + "\nCLASSES\t" + (if ($classes|length) > 0 then (($classes | map(.class + " (" + (.n|tostring) + ")")) | join(", ")) else "(none recorded)" end)
          + "\nSTAGES\t" + (if ($stages|length) > 0 then (($stages | map(.stage + " (" + (.n|tostring) + ")")) | join(", ")) else "(none recorded)" end)
          + "\nROUNDS\t" + ($rounds|tostring)
          + "\nENTRIES\t" + ($n_entries|tostring)
          + "\nSHM\t" + (if $any_shm then "yes" else "no" end)
      end
  ' -r 2>/dev/null
)"

# jq failure (whole-program) is treated as fail-safe quiet.
if [ -z "$summary" ]; then
  msg="read-postmortem: churn-ledger query produced no output (treating as quiet, fail-safe)"
  echo "$msg" >&2
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" "$msg" >> "$LOG" 2>/dev/null || true
  exit 0
fi

# 4. Emit the bounded advisory markdown.
# NO-HIT (corpus present but NO query-path overlap) is treated EXACTLY like an absent/empty
# corpus: emit NOTHING and exit 0 — do NOT print the banner or a "no prior churn" sentinel.
# Machine consumers (Supervisor Phase 4.5 `prior_churn`, Launch Pad action 0b) gate enrichment
# on NON-EMPTY stdout, so a no-hit MUST produce EMPTY output; otherwise a "no prior churn"
# sentinel line would be threaded into the reviewer prompt as if churn existed, violating the
# documented "empty string when no prior churn" contract. (A human running this directly simply
# gets no output on a no-hit — grep-with-no-match semantics.) So: EMPTY ⇒ silent, BEFORE the banner.
if [ "$summary" = "EMPTY" ]; then
  exit 0
fi
printf '%s\n' "## Advisory prior-churn signal — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)"

# Parse the tab-delimited summary lines emitted by jq (already bounded + sanitized through
# the jq data model — no re-interpolation risk).
churn_paths=""; churn_classes=""; churn_stages=""; churn_rounds=""; churn_entries=""; churn_shm=""
while IFS=$'\t' read -r key val; do
  case "$key" in
    PATHS)   churn_paths="$val" ;;
    CLASSES) churn_classes="$val" ;;
    STAGES)  churn_stages="$val" ;;
    ROUNDS)  churn_rounds="$val" ;;
    ENTRIES) churn_entries="$val" ;;
    SHM)     churn_shm="$val" ;;
  esac
done <<EOF
$summary
EOF

printf '%s\n' "Prior churn detected on touched path(s): $churn_paths"
printf '%s\n' "- recurring root-cause classes: $churn_classes"
printf '%s\n' "- recurring flow stages: $churn_stages"
printf '%s\n' "- prior churn rounds: $churn_rounds (across $churn_entries postmortem entr$( [ "$churn_entries" = "1" ] && printf 'y' || printf 'ies' ))"
printf '%s\n' "- any self_heal_miss in prior rounds: $churn_shm"
# Attribution caveat: the ledger records classes/stages per PR-REVIEW-ROUND, not per file, so the
# above are aggregated at the PR level for entries that touched this path — a directional hint
# that this AREA has historically churned, NOT file-precise per-path attribution.
printf '%s\n' "- (attribution: aggregated PR-level for entries that touched the path — the ledger records per-round, not per-file; treat as a directional hint, not file-precise)"

exit 0
