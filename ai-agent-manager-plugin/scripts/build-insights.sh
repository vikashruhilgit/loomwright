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
  # The System Twin hard-signal fields (contract_conformance_status, contract_violations,
  # benchmark_status, benchmark_metric, benchmark_value, benchmark_delta) are FLAT scalars on
  # the session_end event (see docs/RESULT_SCHEMAS.md §"session_end JSONL hard-signal fields").
  # Field names are a hard contract with ST3 (writer) — do NOT rename. Older logs lack them, so
  # each defaults to null and renders as "not reported this session".
  jq -c --arg sid "$sid" '
    select(.event=="session_end")
    | {sid:$sid, ts:(.ts//""), status:(.status//"unknown"), branch:(.branch//""),
       pr_url:(.pr_url//""), heal_decision:(.heal_decision//""),
       heal_iterations:(.heal_iterations//null), rubric_score:(.rubric_score//null),
       subtasks_completed:(.subtasks_completed//null), files_changed:(.files_changed//null),
       duration_seconds:(.duration_seconds//null),
       plugin_version:(.plugin_version//"unknown"),
       contract_conformance_status:(.contract_conformance_status//null),
       contract_violations:(.contract_violations//null),
       benchmark_status:(.benchmark_status//null),
       benchmark_metric:(.benchmark_metric//null),
       benchmark_value:(.benchmark_value//null),
       benchmark_delta:(.benchmark_delta//null)}
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
      (if .duration_seconds!=null  then "duration_seconds: \(.duration_seconds)"     else empty end),
      "plugin_version: \(.plugin_version)",
      (if .contract_conformance_status!=null then "contract_conformance_status: \(.contract_conformance_status)" else empty end),
      (if .contract_violations!=null then "contract_violations: \(.contract_violations)" else empty end),
      (if .benchmark_status!=null  then "benchmark_status: \(.benchmark_status)"      else empty end),
      (if .benchmark_metric!=null  then "benchmark_metric: \(.benchmark_metric)"      else empty end),
      (if .benchmark_value!=null   then "benchmark_value: \(.benchmark_value)"        else empty end),
      (if .benchmark_delta!=null   then "benchmark_delta: \(.benchmark_delta)"        else empty end)
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
      (if .contract_conformance_status!=null
         then "- **Contract conformance:** \(.contract_conformance_status) (\(.contract_violations // 0) advisory violation(s))"
         else empty end),
      (if .benchmark_status!=null
         then "- **Benchmark:** \(.benchmark_status)\(if .benchmark_metric!=null then " — \(.benchmark_metric)" else "" end)\(if .benchmark_value!=null then "=\(.benchmark_value)" else "" end)\(if .benchmark_delta!=null then " (delta \(.benchmark_delta))" else "" end)"
         else empty end),
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
  files:     (map(.files_changed // 0) | add),
  # --- System Twin hard signal (additive; treats absent fields as null) ---
  twin_runs:            (map(select(.contract_conformance_status != null)) | length),
  contract_violations:  (map(.contract_violations // 0) | add),
  conformance_pass:     (map(select(.contract_conformance_status=="pass")) | length),
  bench_runs:           (map(select(.benchmark_status != null)) | length),
  bench_regressed:      (map(select(.benchmark_status=="regressed")) | length),
  bench_improved:       (map(select(.benchmark_status=="improved")) | length),
  # latest benchmark value/delta = newest run (by ts) that actually carries a benchmark_status
  bench_latest_value:   ((map(select(.benchmark_status != null)) | sort_by(.ts) | last | .benchmark_value) // null),
  bench_latest_delta:   ((map(select(.benchmark_status != null)) | sort_by(.ts) | last | .benchmark_delta) // null)
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
  # System Twin hard signal — only render the section when at least one run reported it.
  twin_runs="$(printf '%s' "$agg" | jq -r '.twin_runs')"
  if [ "${twin_runs:-0}" -gt 0 ]; then
    echo "## System Twin hard signal (contract conformance · benchmark)"
    echo "_Advisory only — never blocks a PR or changes a heal decision. Sourced from the \`session_end\` hard-signal fields; runs that did not report them are omitted from these counts._"
    echo
    printf '%s\n' "$agg" | jq -r '
      "| Metric | Value |",
      "|---|---|",
      "| Runs reporting conformance | \(.twin_runs) |",
      "| Conformance = pass | \(.conformance_pass) |",
      "| Contract violations (total, advisory) | \(.contract_violations) |",
      "| Runs reporting a benchmark | \(.bench_runs) |",
      "| Benchmark regressed / improved | \(.bench_regressed) / \(.bench_improved) |",
      "| Latest benchmark value | \(if .bench_latest_value!=null then (.bench_latest_value|tostring) else "—" end) |",
      "| Latest benchmark delta | \(if .bench_latest_delta!=null then (.bench_latest_delta|tostring) else "—" end) |"
    '
    echo
  fi

  # --- Per-version insights (additive; groups session_end by plugin_version) ---
  # plugin_version is the additive stamp on the session_end event (see
  # docs/RESULT_SCHEMAS.md §"session_end JSONL hard-signal fields"); events
  # without it (older logs) group under "unknown". Columns: runs, heal-PASS
  # rate, avg heal_iterations, avg rubric_score ("M/N" parsed to a percentage).
  echo "## Per-version insights"
  echo "_Sessions grouped by the additive \`plugin_version\` field on \`session_end\` (absent in older logs → \"unknown\"). Computed with jq, never guessed._"
  echo
  echo "| Version | Runs | Heal-PASS rate | Avg heal iterations | Avg rubric score |"
  echo "|---|---|---|---|---|"
  jq -s -r '
    group_by(.plugin_version // "unknown")
    | map({
        version:   (.[0].plugin_version // "unknown"),
        runs:      length,
        pass_rate: (((map(select(.heal_decision=="PASS")) | length) * 100 / length) | floor),
        healed:    (map(select(.heal_iterations != null)) | length),
        avg_heal:  ((map(select(.heal_iterations != null) | .heal_iterations) | add // 0)
                    / ((map(select(.heal_iterations != null)) | length) | if . == 0 then 1 else . end)),
        rubric_pcts: [ .[] | .rubric_score | select(. != null) | tostring
                       | capture("^(?<m>[0-9]+)\\s*/\\s*(?<n>[0-9]+)$")
                       | select((.n|tonumber) > 0)
                       | ((.m|tonumber) * 100 / (.n|tonumber)) ]
      })
    | sort_by(.version) | reverse
    | .[]
    | "| \(.version) | \(.runs) | \(.pass_rate)% | \(if .healed>0 then (((.avg_heal*100|floor)/100)|tostring) else "—" end) | \(if (.rubric_pcts|length)>0 then "\(((.rubric_pcts|add) / (.rubric_pcts|length))|floor)%" else "—" end) |"
  ' "$records"
  echo

  # --- Eval fitness function (ALWAYS rendered; "no data yet" when absent) ---
  # Reads .supervisor/eval/results.jsonl (one EVAL_RESULT-plus-recorded_at per line; written by
  # run-eval.sh in ST1). pass_rate is a string like "4/6". Only VERIFIED runs (status=="ok") feed the
  # fitness trend — unverified records (status=="unverified", pass_rate "0/0", emitted when the eval
  # could not run) carry a 0/0 that would otherwise misread in the trend as "everything failed"
  # rather than "not measured", so they are filtered out. Records are sorted by recorded_at ascending
  # (defensive — robust to manual reordering of the file), so latest = last line and the trend reads
  # oldest → newest, joined with " → ", bounded to the most recent ~10 points (prefix "… → " if cut).
  echo "## Eval fitness function"
  evf=".supervisor/eval/results.jsonl"
  if [ -f "$evf" ] && [ -s "$evf" ]; then
    eval_rates="$(jq -rs 'map(select(.status=="ok" and (.pass_rate // null))) | sort_by(.recorded_at // "") | .[].pass_rate' "$evf" 2>/dev/null)"
    if [ -n "$eval_rates" ]; then
      eval_latest="$(printf '%s\n' "$eval_rates" | tail -1)"
      eval_total="$(printf '%s\n' "$eval_rates" | grep -c . 2>/dev/null)"; eval_total="${eval_total:-0}"
      eval_trend="$(printf '%s\n' "$eval_rates" | tail -10 | awk 'BEGIN{ORS=""} {if(NR>1)printf " → "; printf "%s",$0}')"
      [ "$eval_total" -gt 10 ] && eval_trend="… → $eval_trend"
      echo "_Deterministic plugin **run scoreboard** — the eval corpus pass-rate, sourced from \`$evf\` (written by \`scripts/run-eval.sh\`). Advisory; computed with jq, never guessed._"
      echo
      echo "- **Latest pass-rate:** $eval_latest"
      echo "- **Trend (oldest → newest):** $eval_trend"
    else
      echo "_No eval runs recorded yet — run \`/supervisor\` or \`scripts/run-eval.sh\`._"
    fi
  else
    echo "_No eval runs recorded yet — run \`/supervisor\` or \`scripts/run-eval.sh\`._"
  fi
  echo

  # --- Brain Context Baseline (DORMANT in v1 — DO NOT wire into the fitness trend) ---
  # Phase 0 of the brain-integration arc emits a SEPARATE history file,
  # .supervisor/eval/brain-baseline.jsonl (written by scripts/brain-baseline-eval.sh), measuring
  # grep-first vs graph-first behavior. Per docs/SPIKES/BRAIN_INTEGRATION_EVOLUTION.md §"Phase 0 —
  # Baseline eval harness", /insights INTENTIONALLY IGNORES this file in v1 so the brain baseline
  # never pollutes the existing eval fitness-function trend above (which reads results.jsonl).
  #
  # This block is FULLY DORMANT in v1: both the heading AND any data render are gated behind the
  # permanently-false guard below, so /insights shows NO empty "Brain Context Baseline" section on
  # the common no-brain repo, and the existing results.jsonl section's behavior is unchanged. To
  # activate later, flip the guard — it then renders the heading + a trend from $brain_baseline —
  # but only once we've decided to surface a brain-lift panel.
  # shellcheck disable=SC2050  # v1: baseline intentionally dormant; guard is permanently false.
  if false; then
    # DEAD in v1 — nothing here runs. Left as the wiring point for a future brain-lift panel;
    # flipping `if false` to a real check is a deliberate, reviewed change, not an accident.
    echo "## Brain Context Baseline"
    echo "_Reserved for the brain-integration baseline (Phase 0). Sourced from a **separate** file"
    echo "(\`.supervisor/eval/brain-baseline.jsonl\`, written by \`scripts/brain-baseline-eval.sh\`)._"
    echo "_**v1: intentionally NOT wired into the eval fitness-function trend** — see"
    echo "\`docs/SPIKES/BRAIN_INTEGRATION_EVOLUTION.md\` §\"Phase 0 — Baseline eval harness\"._"
    brain_baseline=".supervisor/eval/brain-baseline.jsonl"
    : "$brain_baseline"  # placeholder reference only — not read into any trend in v1.
    echo
  fi

  # --- System Twin growth (ALWAYS rendered; "no data yet" when absent) ---
  # contract count = number of .supervisor/twin/contracts/*.md files.
  # growth = cumulative count of .action=="add" provenance entries, grouped by written_at date,
  # rendered as a running total oldest→newest, bounded to ~8 points (prefix "… → " if cut).
  echo "## System Twin growth"
  twin_dir=".supervisor/twin"
  twin_contracts="$twin_dir/contracts"
  twin_prov="$twin_dir/.provenance.jsonl"
  if [ -d "$twin_contracts" ] || [ -f "$twin_prov" ]; then
    contract_count="$(find "$twin_contracts" -maxdepth 1 -type f -name '*.md' 2>/dev/null | grep -c . 2>/dev/null)"; contract_count="${contract_count:-0}"
    growth=""
    if [ -f "$twin_prov" ] && [ -s "$twin_prov" ]; then
      # per-date add counts → cumulative running totals oldest→newest (sort by date defensively).
      growth="$(jq -r 'select(.action=="add")|(.written_at[0:10])' "$twin_prov" 2>/dev/null \
        | sort \
        | uniq -c \
        | awk '{cum+=$1; vals[NR]=cum; n=NR} END{
            start=(n>8 ? n-7 : 1);
            out="";
            for(i=start;i<=n;i++){ if(out!="") out=out" → "; out=out vals[i]; }
            if(n>8) out="… → " out;
            printf "%s", out;
          }')"
    fi
    echo "_System Twin contract store growth — sourced from \`$twin_contracts/*.md\` and \`$twin_prov\`. Computed with jq, never guessed._"
    echo
    if [ -n "$growth" ]; then
      echo "- **Contracts:** $contract_count contracts ($growth)"
    else
      echo "- **Contracts:** $contract_count contracts (no growth history)"
    fi
  else
    echo "_No System Twin contracts recorded yet — the twin store appears as you run \`/supervisor\`._"
  fi
  echo

  echo "## Cost"
  echo "> **Not captured by this plugin.** Token/\$ usage lives in Claude Code's own transcripts, not in \`.supervisor/\`."
  echo "> For real figures run \`npx ccusage@latest\` (daily) or \`npx ccusage@latest session\` (per-session), or Claude Code's \`/cost\`."
  echo
  echo "## Recent sessions"
  echo "| Session | Status | Self-heal | Rubric | Subtasks | Files | Twin (conformance / Δ) | PR |"
  echo "|---|---|---|---|---|---|---|---|"
  jq -s -r 'sort_by(.ts) | reverse | .[]
    | (if .contract_conformance_status!=null then .contract_conformance_status else "—" end) as $conf
    | (if .benchmark_delta!=null then (.benchmark_delta|tostring) else "—" end) as $delta
    | "| \(.sid) | \(.status) | \(.heal_decision // "—") (\(.heal_iterations // "—")) | \(.rubric_score // "—") | \(.subtasks_completed // "—") | \(.files_changed // "—") | \($conf) / \($delta) | \(if .pr_url!="" then "[PR](\(.pr_url))" else "—" end) |"' "$records"
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
