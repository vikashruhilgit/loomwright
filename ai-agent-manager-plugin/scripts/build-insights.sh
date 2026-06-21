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
       benchmark_delta:(.benchmark_delta//null),
       knowledge_sources_used:(.knowledge_sources_used//[])}
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
      (if .benchmark_delta!=null   then "benchmark_delta: \(.benchmark_delta)"        else empty end),
      (if (.knowledge_sources_used|length)>0 then "knowledge_sources_used: [\(.knowledge_sources_used|join(", "))]" else empty end)
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
      (if (.knowledge_sources_used|length)>0 then "- **Knowledge sources:** \(.knowledge_sources_used|join(", "))" else empty end),
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

  # --- Knowledge sources (memory APPLY) — additive; suppressed when no run reports one ---
  # knowledge_sources_used is the additive, flat, lowercase-tag array on the session_end event
  # (v14.28.0+; see docs/RESULT_SCHEMAS.md). Open set: project_memory, lessons:<category>,
  # agent_memory:<agent>, twin:<path>, brain_context. Older logs lack it → defaults to [] in the
  # projection. Mirror the System Twin hard-signal precedent: render ONLY when ≥1 run reports a
  # source (no fabricated zeros). Computed with jq, never guessed.
  ks_runs="$(jq -s '[.[]|select((.knowledge_sources_used|length)>0)]|length' "$records")"
  if [ "${ks_runs:-0}" -gt 0 ]; then
    echo "## Knowledge sources (memory APPLY)"
    echo "_Which memory sources runs reported consulting — the additive \`knowledge_sources_used\` array on \`session_end\` (v14.28.0+). Advisory only; absent ⇒ none used. Computed with jq, never guessed._"
    echo
    echo "- **Runs reporting a knowledge source:** $ks_runs of $run_count"
    echo
    echo "**Top source tags**"
    echo
    echo "| Source tag | Runs |"
    echo "|---|---|"
    jq -s -r '[.[]|.knowledge_sources_used[]?] | group_by(.) | map({tag:.[0], n:length}) | sort_by([(-.n), .tag]) | .[] | "| \(.tag) | \(.n) |"' "$records"
    echo
    echo "**Per-version usage**"
    echo
    echo "| Version | Runs with a source |"
    echo "|---|---|"
    jq -s -r 'group_by(.plugin_version // "unknown") | map({v:(.[0].plugin_version // "unknown"), n:([.[]|select((.knowledge_sources_used|length)>0)]|length)}) | sort_by(.v) | reverse | .[] | "| \(.v) | \(.n) |"' "$records"
    echo
  fi

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

  # --- Heal-signal catch-rate (MEASURE leg — Local Twin Step 2; SUPPRESSED when no data) ---
  # Sourced from .supervisor/heal-signal/results.jsonl (written by scripts/measure-heal-signal.sh,
  # the re-runnable READ-ONLY self-heal confusion-matrix instrument). One append-only trend line
  # per run carries recall_pct (catch-rate), fn/n, coverage_pct, self_heal_share_pct. Labels are
  # CHURN (/pr-postmortem) → the numbers are advisory / DIRECTIONAL, never gating. Mirrors the
  # System-Twin-hard-signal + knowledge-sources precedent: render ONLY when ≥1 run carries a SCORED
  # matrix; otherwise the section is suppressed ENTIRELY (no fabricated zeros, no "no data yet" stub).
  #
  # "Scored" = n>0 (a real matrix with cells), NOT "n>0 AND recall_pct!=null". recall_pct is null
  # whenever tp+fn==0 — a matrix where NO joined PR had a self-heal miss (all clean PASS / FP). That
  # run IS scored data (coverage + self_heal_share are meaningful), so it must still render with
  # recall shown as "n/a" rather than being silently dropped (which could suppress the whole section
  # despite real data). Only truly unscored n=0 rows (empty matrix) are excluded. Trend points are
  # pre-formatted per-record ("X%" or "n/a"), oldest→newest, bounded ~10 points.
  hsf=".supervisor/heal-signal/results.jsonl"
  if [ -f "$hsf" ] && [ -s "$hsf" ]; then
    # one pre-formatted recall token per SCORED (n>0) record, oldest→newest ("X%" | "n/a").
    hs_recalls="$(jq -rs 'map(select((.n // 0) > 0)) | sort_by(.recorded_at // "") | .[] | (if .recall_pct==null then "n/a" else "\(.recall_pct)%" end)' "$hsf" 2>/dev/null)"
    if [ -n "$hs_recalls" ]; then
      hs_latest="$(jq -rs 'map(select((.n // 0) > 0)) | sort_by(.recorded_at // "") | last' "$hsf" 2>/dev/null)"
      hs_recall="$(printf '%s' "$hs_latest" | jq -r 'if .recall_pct==null then "n/a" else "\(.recall_pct)%" end')"
      hs_fn="$(printf '%s' "$hs_latest" | jq -r '.fn // "—"')"
      hs_n="$(printf '%s' "$hs_latest" | jq -r '.n // "—"')"
      hs_cov="$(printf '%s' "$hs_latest" | jq -r 'if .coverage_pct!=null then "\(.coverage_pct)%" else "—" end')"
      hs_share="$(printf '%s' "$hs_latest" | jq -r 'if .self_heal_share_pct!=null then "\(.self_heal_share_pct)%" else "—" end')"
      hs_total="$(printf '%s\n' "$hs_recalls" | grep -c . 2>/dev/null)"; hs_total="${hs_total:-0}"
      hs_trend="$(printf '%s\n' "$hs_recalls" | tail -10 | awk 'BEGIN{ORS=""} {if(NR>1)printf " → "; printf "%s",$0}')"
      [ "$hs_total" -gt 10 ] && hs_trend="… → $hs_trend"
      echo "## Heal-signal catch-rate (MEASURE)"
      echo "_Self-heal confusion matrix on this repo's own PR history — sourced from \`$hsf\` (written by \`scripts/measure-heal-signal.sh\`). Labels are churn (\`/pr-postmortem\`), so these are **advisory / DIRECTIONAL** — they never gate a PR or change a heal decision. \`recall = n/a\` means a scored run had no ground-truth positives (tp+fn=0). Computed with jq, never guessed._"
      echo
      echo "- **Latest catch-rate (recall):** ${hs_recall}  ·  **False-negatives (missed):** ${hs_fn} of N=${hs_n}"
      echo "- **Coverage:** ${hs_cov} of heal-signal PRs labeled  ·  **Self-heal-lane churn share:** ${hs_share}"
      echo "- **Catch-rate trend (oldest → newest):** ${hs_trend}"
      echo
    fi
  fi

  # --- Missing-drain reconciliation (advisory; AC5 — SUPPRESSED when no corpus) ---
  # Surfaces PRs that carried a heal outcome (a `## Outcome` block with a `**PR:**` URL in the
  # done-brief corpus under .supervisor/jobs/done/) but have NO matching review-drain dispatch
  # marker under .supervisor/review-dispatch/ — a possible silently-dropped until-mergeable drain
  # (the #74 incident). READ-ONLY, advisory, NEVER gating. Mirrors the heal-signal / System-Twin
  # suppression precedent: render ONLY when a heal-signal/marker corpus exists; otherwise the
  # section is suppressed ENTIRELY (no fabricated zeros).
  #
  # Reason classification per markerless PR — deliberately NON-accusatory (never a blanket "dropped"):
  #   * opted_out            — ONLY when durable RUN-TIME-recorded opt-out evidence exists for THAT
  #                            PR: a `--no-auto-review` / `auto_review` / suppress line in that run's
  #                            dispatch log (.supervisor/logs/review-pr-dispatch-*<...>.log) OR in
  #                            the job's `## Outcome` block. NEVER inferred from the CURRENT
  #                            .supervisor/config.json (mutable; reflects NOW, not dispatch-time —
  #                            reading it would mislabel a genuine later drop as a deliberate opt-out).
  #                            config.json is NOT read here at all.
  #   * unknown_or_opted_out — the DEFAULT when no marker exists AND no durable run-time evidence is
  #                            available (could be a silent drop OR an unrecorded opt-out — not enough
  #                            to accuse). A genuine silent drop (#74) surfaces here → the signal to
  #                            investigate.
  #
  # Join is by EXACT PR URL — marker bodies are `<ts>\t<url>` lines; we match the full URL with
  # word boundaries so `/pull/7` is never confused with `/pull/72`.
  done_dir=".supervisor/jobs/done"
  dispatch_dir=".supervisor/review-dispatch"
  # Build the heal-signal corpus: (pr_url <TAB> brief_path) for each done-brief whose `## Outcome`
  # block carries a `**PR:**` URL. The `## Outcome` block is the heal-signal (it records
  # heal_decision / heal_iterations). Only briefs WITH such a block + URL are heal-signal PRs.
  md_corpus="$(mktemp)"; md_markers="$(mktemp)"
  # NOTE: do NOT glob into a bash array here — under `set -u` an empty nullglob array would be an
  # unbound-variable error (and without nullglob a no-match leaves a literal pattern). `find` is
  # both empty-safe and avoids polluting global shell options for the rest of the script.
  while IFS= read -r b; do
    [ -f "$b" ] || continue
    # Extract the `## Outcome` block (from the heading to the next `## ` or EOF), then the PR URL
    # on its `- **PR:**` line. awk keeps this tolerant of brief ordering.
    pr_url="$(awk '
      /^## Outcome[[:space:]]*$/ {in_o=1; next}
      in_o && /^## / {in_o=0}
      in_o && /\*\*PR:\*\*/ {
        if (match($0, /https?:\/\/[^ ()]+\/pull\/[0-9]+/)) { print substr($0, RSTART, RLENGTH); exit }
      }
    ' "$b" 2>/dev/null)"
    [ -n "$pr_url" ] && printf '%s\t%s\n' "$pr_url" "$b" >> "$md_corpus"
  done < <(find "$done_dir" -maxdepth 1 -type f -name '*.md' 2>/dev/null)
  # Marker bodies → one PR URL per marker (exact url tokens).
  while IFS= read -r m; do
    [ -f "$m" ] || continue
    grep -ohE 'https?://[^ ()[:space:]]+/pull/[0-9]+' "$m" 2>/dev/null >> "$md_markers"
  done < <(find "$dispatch_dir" -maxdepth 1 -type f 2>/dev/null)
  sort -u "$md_markers" -o "$md_markers" 2>/dev/null || true
  corpus_count="$(grep -c . "$md_corpus" 2>/dev/null)"; corpus_count="${corpus_count:-0}"
  marker_count="$(grep -c . "$md_markers" 2>/dev/null)"; marker_count="${marker_count:-0}"
  # SUPPRESS entirely when there is no heal-signal/marker corpus (no fabricated zeros).
  if [ "$corpus_count" -gt 0 ] || [ "$marker_count" -gt 0 ]; then
    # For each heal-signal PR, decide present/missing by EXACT url match against the marker set,
    # and (for the missing ones) classify the reason.
    md_rows="$(mktemp)"; md_missing=0
    while IFS="$(printf '\t')" read -r pr brief; do
      [ -n "$pr" ] || continue
      # Exact whole-URL match against the sorted marker set — `/pull/7` ≠ `/pull/72` because
      # grep -x anchors the WHOLE line and -F treats the URL literally.
      if grep -qxF -- "$pr" "$md_markers" 2>/dev/null; then
        continue  # has a dispatch marker → nothing to reconcile
      fi
      md_missing=$((md_missing+1))
      # Classify: opted_out ONLY on durable run-time opt-out evidence for THIS pr.
      reason="unknown_or_opted_out"
      # (a) the job's own `## Outcome` block recorded an opt-out / suppression.
      if awk '
        /^## Outcome[[:space:]]*$/ {in_o=1; next}
        in_o && /^## / {in_o=0}
        in_o && (index($0,"--no-auto-review")||index($0,"auto_review")||index($0,"suppress")) {found=1}
        END {exit (found?0:1)}
      ' "$brief" 2>/dev/null; then
        reason="opted_out"
      else
        # (b) that run's dispatch log recorded an opt-out / suppression line. Dispatch logs are
        # .supervisor/logs/review-pr-dispatch-*.log; match the ones that mention THIS exact PR url.
        while IFS= read -r lg; do
          [ -f "$lg" ] || continue
          if grep -qF -- "$pr" "$lg" 2>/dev/null && grep -qF -e '--no-auto-review' -e 'auto_review' -e 'suppress' "$lg" 2>/dev/null; then
            reason="opted_out"; break
          fi
        done < <(find "$LOGS_DIR" -maxdepth 1 -type f -name 'review-pr-dispatch-*.log' 2>/dev/null)
      fi
      printf '| %s | %s | %s |\n' "$pr" "$reason" "$(basename "$brief")" >> "$md_rows"
    done < "$md_corpus"
    echo "## Missing-drain reconciliation"
    echo "_Advisory only — READ-ONLY, never gates a PR or changes a heal decision. Heal-signal PRs (a \`## Outcome\` block in \`$done_dir/*.md\`) joined against review-drain dispatch markers under \`$dispatch_dir/\`. A markerless PR may be a silently-missed drain (the #74 incident) OR a deliberate opt-out — the reason is classified, never accused. \`opted_out\` requires durable run-time evidence; \`unknown_or_opted_out\` (the default) is the signal to investigate. \`config.json\` is intentionally NOT consulted (mutable; reflects now, not dispatch-time). Computed with grep/awk, never guessed._"
    echo
    echo "- **Heal-signal PRs:** $corpus_count  ·  **Dispatch markers:** $marker_count  ·  **Missing a drain marker:** $md_missing"
    echo
    if [ "$md_missing" -gt 0 ]; then
      echo "| PR (heal-signal, no drain marker) | Reason | Source brief |"
      echo "|---|---|---|"
      sort "$md_rows" 2>/dev/null
    else
      echo "_All heal-signal PRs have a matching review-drain dispatch marker — nothing to reconcile._"
    fi
    echo
    rm -f "$md_rows" 2>/dev/null
  fi
  rm -f "$md_corpus" "$md_markers" 2>/dev/null

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
