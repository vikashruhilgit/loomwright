#!/usr/bin/env bash
# build-insights.sh — generate a local, Obsidian-friendly INSIGHTS dashboard from the
# .supervisor/logs/*.jsonl session logs (v14.7.0). Read-only on the logs; writes derived
# markdown to .supervisor/insights/ (gitignored). Deterministic (jq), so the numbers are
# computed, not guessed.
#
# WORK + SESSION-PERFORMANCE + QUALITY come from the logs the plugin already writes.
# COST (tokens/$) is intentionally NOT computed here — this plugin never records token usage;
# that data lives in Claude Code's own transcripts. The dashboard prints a COST stub pointing
# to `npx ccusage@latest`. (Adding real cost capture is a separate, deferred enhancement.)
#
# Usage:  build-insights.sh
# Exit:   0 always — a reporting tool must never break its caller. Prints the output path.

set -uo pipefail

GITROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$GITROOT" 2>/dev/null || true

command -v jq >/dev/null 2>&1 || { echo "build-insights: jq required — skipping" >&2; exit 0; }

LOGS_DIR=".supervisor/logs"
OUT=".supervisor/insights"
RUNS="$OUT/runs"
ts_now="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"

shopt -s nullglob
files=("$LOGS_DIR"/*.jsonl)
if [ ${#files[@]} -eq 0 ]; then
  echo "build-insights: no session logs in $LOGS_DIR — run /supervisor first, then /insights."
  exit 0
fi
mkdir -p "$RUNS" 2>/dev/null || { echo "build-insights: cannot create $RUNS" >&2; exit 0; }

# 1) Collect ONE session_end record per log file (session_id = filename; tolerant of missing fields).
records="$(mktemp)"; trap 'rm -f "$records" 2>/dev/null' EXIT
for f in "${files[@]}"; do
  sid="$(basename "$f" .jsonl)"
  # tail -1 (below): a log normally holds one session_end (its final line); take the LAST one
  # in case a session was appended/replayed, so the newest record for that session wins.
  jq -c --arg sid "$sid" '
    select(.event=="session_end")
    | {sid:$sid, ts:(.ts//""), status:(.status//"unknown"), branch:(.branch//""),
       pr_url:(.pr_url//""), heal_decision:(.heal_decision//""),
       heal_iterations:(.heal_iterations//null), rubric_score:(.rubric_score//null),
       subtasks_completed:(.subtasks_completed//null), files_changed:(.files_changed//null),
       duration_seconds:(.duration_seconds//null)}
  ' "$f" 2>/dev/null | tail -1 >> "$records"
done

run_count="$(grep -c . "$records" 2>/dev/null)"; run_count="${run_count:-0}"
if [ "$run_count" -eq 0 ]; then
  echo "build-insights: logs present but no session_end events yet — nothing to summarize."
  exit 0
fi

# 2) One note per run, with Dataview-compatible YAML frontmatter (renders as a dashboard row in Obsidian).
while IFS= read -r r; do
  [ -n "$r" ] || continue
  sid="$(printf '%s' "$r" | jq -r '.sid')"
  {
    echo "---"
    printf '%s\n' "$r" | jq -r '
      "session_id: \(.sid)",
      (if .ts!="" then "created: \(.ts|split("T")[0])" else empty end),
      "status: \(.status)",
      (if .branch!=""        then "branch: \(.branch)"                   else empty end),
      (if .pr_url!=""         then "pr_url: \(.pr_url)"                   else empty end),
      (if .heal_decision!=""  then "heal_decision: \(.heal_decision)"    else empty end),
      (if .heal_iterations!=null   then "heal_iterations: \(.heal_iterations)"       else empty end),
      (if .rubric_score!=null      then "rubric_score: \"\(.rubric_score)\""         else empty end),
      (if .subtasks_completed!=null then "subtasks_completed: \(.subtasks_completed)" else empty end),
      (if .files_changed!=null     then "files_changed: \(.files_changed)"           else empty end),
      (if .duration_seconds!=null  then "duration_seconds: \(.duration_seconds)"     else empty end)
    '
    echo 'total_cost: "not captured — see Cost note (npx ccusage@latest)"'
    echo 'total_tokens: "not captured — see Cost note"'
    echo "tags: [type/session-log]"
    echo "---"
    echo
    echo "# Session $sid"
    echo
    printf '%s\n' "$r" | jq -r '
      "- **Status:** \(.status)",
      "- **Self-heal:** \(.heal_decision // "—") (\(.heal_iterations // "—") iterations)",
      "- **Rubric:** \(.rubric_score // "—")",
      "- **Subtasks completed:** \(.subtasks_completed // "—")",
      "- **Files changed:** \(.files_changed // "—")",
      (if .pr_url!="" then "- **PR:** \(.pr_url)" else empty end)
    '
  } > "$RUNS/$sid.md"
done < "$records"

# 3) Aggregate (computed, not guessed) + write the dashboard.
agg="$(jq -s '{
  total:     length,
  completed: (map(select(.status=="completed")) | length),
  failed:    (map(select(.status=="failed"))    | length),
  heal_pass: (map(select(.heal_decision=="PASS"))| length),
  healed:    (map(select(.heal_iterations != null)) | length),
  avg_heal:  ((map(select(.heal_iterations != null) | .heal_iterations) | add // 0)
              / ((map(select(.heal_iterations != null)) | length) | if . == 0 then 1 else . end)),
  subtasks:  (map(.subtasks_completed // 0) | add),
  files:     (map(.files_changed // 0) | add)
}' "$records")"
pass_rate="$(printf '%s' "$agg" | jq -r 'if .total>0 then ((.completed*100/.total)|floor) else 0 end')"

{
  echo "---"
  echo "tags: [type/insights-dashboard]"
  echo "generated: $ts_now"
  echo "---"
  echo
  echo "# AI Agent Manager — Insights"
  echo
  echo "_Generated $ts_now from \`$LOGS_DIR/*.jsonl\` ($run_count session(s)). Regenerate any time with \`/insights\`._"
  echo
  echo "## Summary (work · quality · session performance)"
  printf '%s\n' "$agg" | jq -r '
    "| Metric | Value |",
    "|---|---|",
    "| Sessions | \(.total) |",
    "| Completed | \(.completed) |",
    "| Failed | \(.failed) |",
    "| Self-heal PASS | \(.heal_pass) |",
    "| Self-heal runs (with heal data) | \(.healed) |",
    "| Avg heal iterations (per healed run) | \(if .healed>0 then ((.avg_heal*100|floor)/100) else "—" end) |",
    "| Subtasks completed (total) | \(.subtasks) |",
    "| Files changed (total) | \(.files) |"
  '
  echo "| **Completion rate** | **${pass_rate}%** |"
  echo
  echo "## Cost"
  echo "> **Not captured by this plugin.** Token/\$ usage lives in Claude Code's own transcripts, not in \`.supervisor/\`."
  echo "> For real figures run \`npx ccusage@latest\` (daily) or \`npx ccusage@latest session\` (per-session), or Claude Code's \`/cost\`."
  echo
  echo "## Recent sessions"
  echo "| Session | Status | Self-heal | Rubric | Subtasks | Files | PR |"
  echo "|---|---|---|---|---|---|---|"
  jq -s -r 'sort_by(.ts) | reverse | .[]
    | "| \(.sid) | \(.status) | \(.heal_decision // "—") (\(.heal_iterations // "—")) | \(.rubric_score // "—") | \(.subtasks_completed // "—") | \(.files_changed // "—") | \(if .pr_url!="" then "[PR](\(.pr_url))" else "—" end) |"' "$records"
  echo
  echo "## View in Obsidian (optional)"
  echo "Point an Obsidian vault at \`.supervisor/\` (or symlink \`.supervisor/insights\` into a vault). With the **Dataview** plugin this renders as a live, sortable board:"
  echo '```dataview'
  echo "TABLE status, rubric_score, heal_iterations, files_changed, pr_url"
  echo 'FROM "insights/runs"'
  echo "SORT created DESC"
  echo '```'
  echo
  echo "_These files are plain markdown — readable anywhere (GitHub, any editor); Obsidian just makes them interactive._"
} > "$OUT/dashboard.md"

echo "build-insights: wrote $OUT/dashboard.md + $run_count run note(s) under $RUNS/"
exit 0
