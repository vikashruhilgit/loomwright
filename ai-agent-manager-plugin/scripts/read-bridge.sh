#!/usr/bin/env bash
# read-bridge.sh — fail-safe ADVISORY read-back of the findings→community BRIDGE index.
# (New file — Local Twin Step 5 reader side; parity with read-postmortem.sh / read-lessons.sh
#  advisory-reader convention. Pure-READ, NO side effects, NEVER triggers a build.)
#
# Given a set of touched file paths, summarize what we ALREADY KNOW about the graph
# COMMUNITIES those paths fall in, by reading the pre-built index at
# .supervisor/bridge/bridge.json (produced by build-bridge.{sh,py}). This is the
# community-level companion to read-postmortem.sh's EXACT-path churn read: it joins by
# graph community (finding.changed_paths -> node.source_file -> node.community), so a
# near-miss path that EXACT-path matching drops still surfaces AREA knowledge when it
# falls in a community with prior recorded misses / lessons.
#
# For each touched path, file_to_communities[path] resolves to community ids; each
# community's findings (recurring miss-classes, prior-miss count, self_heal_miss) and
# attached lessons (id/category/summary TEXT) are aggregated into a BOUNDED advisory.
#
# CANONICAL PATH FORM (load-bearing): the bridge keys file_to_communities by the RAW
# source_file EXACTLY as the graph stores it — repo-root-relative WITH the
# "ai-agent-manager-plugin/" prefix (root files like CHANGELOG.md carry no prefix). That
# is byte-identical to `git diff --name-only` output (the reader's input), so input paths
# are looked up VERBATIM — this reader NEVER strips or rewrites them before lookup.
#
# GOD-NODE (ubiquitous-community) SUPPRESSION — deterministic, documented:
#   Broadly-connected "god-node" communities attach to nearly every diff and carry findings
#   from almost every PR; surfacing them as "this area churned" is noise that trains
#   reviewers to ignore the advisory. The builder stamps each community with `ubiquitous`
#   (true iff member_file_count >= the builder's threshold) and `member_file_count`. This
#   reader DROPS any community where `ubiquitous == true` (the builder-stamped flag is the
#   cheap deterministic input — no graph recomputation here). Surviving communities are then
#   RANKED by finding-specificity (prior-miss total desc, then finding count desc, then
#   smaller member_file_count first) BEFORE the MAX_COMMUNITIES cap is applied, so the most
#   specific area knowledge wins the bounded output. This is advisory tuning, never a gate.
#
# STALENESS (emit-with-HINT, NOT a no-op): the bridge records `built_at_commit` (copied
#   from graph.json) and `head_commit`. When the current git HEAD has advanced past
#   built_at_commit, the advisory STILL emits but appends a one-line "treat as a hint — graph
#   may be stale" caveat. Only an ABSENT graph/bridge (or missing jq) is a silent no-op — a
#   STALE graph is NOT (silent-on-stale would gut the feature, since the gitignored graph is
#   rebuilt only on /graphify runs and an active repo's graph is almost always stale-vs-HEAD).
#   Per the brain-context staleness rule, the graph is authoritative for COMMITTED structure
#   only — never for the files the session is currently editing — hence the directional-hint framing.
#
# Output is ADVISORY and prefixed with a subordinate-to-CLAUDE.md banner, labeled distinctly
# as AREA-KNOWLEDGE (graph-community bridge) so it reads as a SEPARATE signal from prior-churn.
# This helper NEVER gates anything; its output is always subordinate to CLAUDE.md (on conflict,
# CLAUDE.md wins).
#
# INPUT CONTRACT:
#   Touched paths are supplied as command-line ARGUMENTS or newline-separated on STDIN.
#   ARGS TAKE PRECEDENCE: when one or more path args are given, STDIN is NEVER read — so an
#   args-bearing call can NEVER block waiting on stdin, even in a non-TTY context (CI, a hook,
#   or an agent's inline Bash where stdin is an open-but-idle pipe). STDIN is consulted ONLY
#   when NO path args were given (and stdin is not a terminal). With no paths supplied at all
#   → exit 0, quiet (nothing to match against).
#     Examples:
#       read-bridge.sh ai-agent-manager-plugin/agents/supervisor.md          # args (stdin ignored)
#       git diff --name-only origin/main...HEAD | read-bridge.sh             # no args → reads stdin
#
# FAIL-SAFE (hard requirement): ALWAYS exit 0 — a read must never break its caller.
#   - bridge.json absent/empty       → exit 0 quiet
#   - graphify-out/graph.json absent  → exit 0 quiet (no graph means the bridge is meaningless)
#   - jq unavailable                  → emit nothing, exit 0 (mirror read-postmortem.sh)
#   - malformed bridge.json           → fail-safe quiet (exit 0)
#   - no touched-path overlaps any finding-bearing (surviving) community → EMPTY, exit 0
#   jq-only parsing — untrusted corpus text (paths/labels/lesson summaries) is NEVER string-
#   interpolated into a shell command or another jq program; inputs cross the boundary via
#   --rawfile / --slurpfile / --argjson / --arg ONLY.
#
# Exit: always 0; diagnostics go to stderr + .supervisor/logs/memory.log (mirrors read-postmortem.sh).

set -uo pipefail   # `set -e` intentionally omitted — a read must NEVER fail its caller.

GITROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$GITROOT" 2>/dev/null || true

BRIDGE=".supervisor/bridge/bridge.json"
GRAPH="graphify-out/graph.json"
LOG=".supervisor/logs/memory.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

# Bounds so the advisory can never flood a prompt.
MAX_PATHS=5
MAX_COMMUNITIES=4
MAX_CLASSES=8
MAX_LESSONS=4

log_skip() {
  # $1 = message; emit to stderr + memory.log, never to stdout.
  echo "$1" >&2
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" "$1" >> "$LOG" 2>/dev/null || true
}

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
# De-dup, drop blanks. Paths are looked up VERBATIM (canonical repo-root-relative form) —
# never stripped/rewritten, or every join key silently misses.
sort -u "$paths_file" -o "$paths_file" 2>/dev/null || true
[ -s "$paths_file" ] || exit 0   # no input paths → nothing to match against

# 2. Tooling + corpus presence (fail-safe, quiet).
#    - jq is REQUIRED by this reader (the builder is jq-free; only the reader needs it).
#    - bridge.json absent/empty → no-op. graph.json absent → no-op (a bridge without a graph is
#      meaningless; matches the builder's own no-graph silent-skip).
if ! command -v jq >/dev/null 2>&1; then
  log_skip "read-bridge: jq unavailable — bridge unreadable, emitting nothing (fail-safe)"
  exit 0
fi
[ -s "$BRIDGE" ] || exit 0   # absent or empty bridge index → emit nothing
[ -s "$GRAPH" ]  || exit 0   # no graph → bridge is meaningless → emit nothing

# 3. Resolve staleness. The bridge carries built_at_commit (copied from graph.json) + head_commit;
#    we re-read the CURRENT HEAD here (the bridge's head_commit is the build-time HEAD, which may
#    itself be stale). Stale ⇒ emit-with-hint (NOT a no-op). All values cross into jq via --arg only.
BUILT_AT="$(jq -r '.built_at_commit // empty' "$BRIDGE" 2>/dev/null || true)"
if [ -z "$BUILT_AT" ]; then
  # Fall back to the graph's own built_at_commit if the bridge omitted it.
  BUILT_AT="$(jq -r '.built_at_commit // empty' "$GRAPH" 2>/dev/null || true)"
fi
CUR_HEAD="$(git rev-parse HEAD 2>/dev/null || true)"
STALE="no"
if [ -n "$BUILT_AT" ] && [ -n "$CUR_HEAD" ] && [ "$BUILT_AT" != "$CUR_HEAD" ]; then
  STALE="yes"
fi

# 4. Build the query-path JSON array (raw strings → jq array; no interpolation).
query_json="$(jq -R . "$paths_file" 2>/dev/null | jq -s . 2>/dev/null)"
[ -n "$query_json" ] || exit 0

# 5. jq aggregation. bridge.json is read whole (a single JSON object) via the program's input.
#    Untrusted text (labels, lesson summaries, paths) NEVER leaves the jq data model. The program
#    is fixed text; only data crosses via --argjson / --arg. A malformed bridge yields no output
#    (the `?`-guarded reads + the outer `|| true` keep it fail-safe quiet).
#
#    Algorithm:
#      a. For each query path, look up file_to_communities[path] → community ids (VERBATIM key).
#      b. Collect the union of touched community ids; for each, O(1) .communities[idstr] lookup.
#      c. DROP ubiquitous communities (god-node suppression) — builder-stamped flag.
#      d. RANK survivors by finding-specificity (prior-miss total desc, finding count desc,
#         smaller member_file_count first); cap at MAX_COMMUNITIES.
#      e. If no surviving finding-bearing community remains → "EMPTY".
#      f. Otherwise emit tab-delimited summary lines parsed by the shell below.
summary="$(
  jq -r \
    --argjson query "$query_json" \
    --argjson max_paths "$MAX_PATHS" \
    --argjson max_comms "$MAX_COMMUNITIES" \
    --argjson max_classes "$MAX_CLASSES" \
    --argjson max_lessons "$MAX_LESSONS" '
    ($query | map(select(. != null and . != "")) | unique) as $q
    | (.file_to_communities // {}) as $f2c
    | (.communities // {}) as $comm
    # a. touched-path → community ids (verbatim key lookup), keep only paths that actually hit.
    | [ $q[] | { path: ., comms: (($f2c[.]) // []) } | select((.comms | length) > 0) ] as $touched
    | if ($touched | length) == 0 then "EMPTY"
      else
        # b. union of touched community ids (as strings, for the O(1) .communities[$id] lookup).
        ([ $touched[].comms[] ] | map(tostring) | unique) as $cids
        # c+d. resolve each id to its community object, DROP ubiquitous (god-node), keep
        #      finding-bearing survivors, RANK by finding-specificity, cap.
        | ([ $cids[]
             | $comm[.] // empty
             | select((.ubiquitous // false) | not)          # god-node suppression
             | select(((.findings) // []) | length > 0)      # finding-bearing only
             | { community: (.community),
                 label: (.label // ("community " + (.community|tostring))),
                 member_file_count: (.member_file_count // 0),
                 findings: ((.findings) // []),
                 lessons: ((.lessons) // []),
                 miss_total: ([ ((.findings) // [])[] | (.miss // 0) ] | add // 0),
                 finding_n: (((.findings) // []) | length),
                 any_shm: ([ ((.findings) // [])[] | (.self_heal_miss // false) ] | any(. == true)) }
           ]
           # rank: most prior-misses first, then most findings, then most SPECIFIC (fewest members).
           | sort_by([ (- .miss_total), (- .finding_n), (.member_file_count) ])
           | .[0:$max_comms]) as $survivors
        | if ($survivors | length) == 0 then "EMPTY"
          else
            # Which touched paths landed in a SURVIVING community (bounded) — so the advisory names
            # the paths that actually carry area knowledge, not god-node/empty ones.
            ([ ($survivors | map(.community)) as $surv_ids
               | $touched[]
               | select(.comms | map(tostring) | any(. as $c | ($surv_ids | map(tostring) | index($c)) != null))
               | .path ] | unique | .[0:$max_paths]) as $hit_paths
            # Recurring miss-classes aggregated across all surviving communities (bounded).
            | ([ $survivors[].findings[]? | (.miss_classes // {}) | to_entries[]
                 | { class: .key, n: (.value // 0) } ]
               | group_by(.class)
               | map({ class: .[0].class, n: ([ .[].n ] | add // 0) })
               | sort_by(- .n) | .[0:$max_classes]) as $classes
            # Attached lessons across survivors (de-dup by id, bounded, summary TEXT carried).
            | ([ $survivors[].lessons[]?
                 | select((.summary // "") != "")
                 | { id: (.id // ""), category: (.category // ""), summary: (.summary) } ]
               | unique_by(.id) | .[0:$max_lessons]) as $lessons
            | ([ $survivors[].miss_total ] | add // 0) as $miss_total
            | ([ $survivors[].any_shm ] | any(. == true)) as $any_shm
            | ($survivors | length) as $n_comm
            # Tab-delimited lines. Multi-valued fields use " | "-joined cells; every value has
            # already passed through the jq data model (no shell re-interpolation risk).
            | "PATHS\t"   + (($hit_paths) | join(", "))
              + "\nCOMMS\t"   + (($survivors | map(.label + (if .any_shm then " [self_heal_miss recurred]" else "" end))) | join(" | "))
              + "\nCLASSES\t" + (if ($classes|length) > 0 then (($classes | map(.class + " (" + (.n|tostring) + ")")) | join(", ")) else "(none recorded)" end)
              + "\nMISS\t"    + ($miss_total|tostring)
              + "\nNCOMM\t"   + ($n_comm|tostring)
              + "\nSHM\t"     + (if $any_shm then "yes" else "no" end)
              + (if ($lessons|length) > 0
                 then ([ $lessons[] | "\nLESSON\t" + (.category) + "\t" + (.summary) ] | join(""))
                 else "" end)
          end
      end
  ' "$BRIDGE" 2>/dev/null || true
)"

# jq failure (whole-program / malformed bridge) is treated as fail-safe quiet.
if [ -z "$summary" ]; then
  log_skip "read-bridge: bridge query produced no output (treating as quiet, fail-safe)"
  exit 0
fi

# 6. EMPTY on NO-HIT — bridge present but no touched-path overlaps any finding-bearing (surviving,
#    non-ubiquitous) community ⇒ emit NOTHING (no banner, no sentinel), exit 0 — exactly like
#    read-postmortem.sh, so machine consumers gate enrichment on NON-EMPTY stdout.
if [ "$summary" = "EMPTY" ]; then
  exit 0
fi

# 7. Emit the bounded advisory markdown. Parse the tab-delimited summary (already bounded +
#    sanitized through the jq data model — no re-interpolation risk).
area_paths=""; area_comms=""; area_classes=""; area_miss=""; area_ncomm=""; area_shm=""
lessons_lines=""
while IFS=$'\t' read -r key val extra; do
  case "$key" in
    PATHS)   area_paths="$val" ;;
    COMMS)   area_comms="$val" ;;
    CLASSES) area_classes="$val" ;;
    MISS)    area_miss="$val" ;;
    NCOMM)   area_ncomm="$val" ;;
    SHM)     area_shm="$val" ;;
    LESSON)  lessons_lines="${lessons_lines}- [${val}] ${extra}"$'\n' ;;
  esac
done <<EOF
$summary
EOF

printf '%s\n' "## Advisory area-knowledge signal (graph-community bridge) — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)"
printf '%s\n' "Area knowledge for the graph-communities the touched path(s) fall in: $area_paths"
printf '%s\n' "- touched communities ($area_ncomm shown, ranked by finding-specificity): $area_comms"
printf '%s\n' "- recurring root-cause miss-classes: $area_classes"
printf '%s\n' "- prior self-heal misses in these communities: $area_miss"
printf '%s\n' "- any self_heal_miss recurred in a touched community: $area_shm"
if [ -n "$lessons_lines" ]; then
  printf '%s\n' "- related lessons (area-anchored):"
  printf '%s' "$lessons_lines"
fi
# Attribution caveat: this is COMMUNITY-level area knowledge (join via the code graph), not
# file-precise attribution — a directional hint that this AREA has historically churned. It is a
# SEPARATE lens from the exact-path prior-churn signal; bias WHERE you look, not WHETHER the diff passes.
printf '%s\n' "- (attribution: aggregated at the graph-COMMUNITY level — ubiquitous god-node communities suppressed; treat as directional area knowledge, not file-precise)"
if [ "$STALE" = "yes" ]; then
  printf '%s\n' "- (staleness: the graph is at $BUILT_AT but HEAD is $CUR_HEAD — treat as a HINT, the graph may be stale; never authoritative for files this session is editing)"
fi

exit 0
