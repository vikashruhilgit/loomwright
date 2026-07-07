#!/usr/bin/env bash
# test-insights.sh — self-tests for build-insights.sh (v14.7.0). Runs in isolated temp repos
# (never touches the real .supervisor). Exit 0 = all pass, 1 = any failure.
#
# Covers: no-logs no-op, dashboard aggregation (counts / completed-failed split / completion
# rate), per-run note generation, missing-field tolerance, the COST stub, the System Twin
# hard-signal aggregation (contract conformance + benchmark) including a backward-compat case
# where NO run carries the new flat fields, the per-version insights table (plugin_version
# present / absent-groups-under-"unknown" / mixed), the knowledge-sources aggregation
# (present / absent-suppressed / mixed-corpus, v14.33.0), and the Corpus health advisory
# section (churn-ledger + lessons counts, curation/retract records, staleness thresholds,
# absent-corpora degradation, malformed-line tolerance, CHURN_STALE_DAYS override).

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BUILD="$HERE/build-insights.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

echo "== 1. no logs (friendly no-op) =="
N="$(mktemp -d)"; ( cd "$N" && git init -q && git config user.email t@t && git config user.name t && echo x>f && git add f && git commit -qm i )
out="$( cd "$N" && bash "$BUILD" 2>&1 )"; rc=$?
{ [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "no session logs"; } && ok "exits 0 with friendly message" || no "no-logs case wrong (rc=$rc)"
[ ! -f "$N/.supervisor/insights/dashboard.md" ] && ok "no dashboard written when no logs" || no "dashboard written with no logs"
rm -rf "$N"

echo "== 2. dashboard aggregation + tolerance =="
T="$(mktemp -d)"; ( cd "$T" && git init -q && git config user.email t@t && git config user.name t && echo x>f && git add f && git commit -qm i )
mkdir -p "$T/.supervisor/logs"
printf '%s\n' '{"ts":"2026-06-01T10:00:00Z","event":"session_end","status":"completed","heal_decision":"PASS","heal_iterations":1,"rubric_score":"7/7","subtasks_completed":4,"files_changed":9,"pr_url":"https://x/1"}' > "$T/.supervisor/logs/sess-a.jsonl"
# sess-b deliberately omits rubric_score / subtasks_completed / files_changed (older-log shape)
printf '%s\n' '{"ts":"2026-06-02T10:00:00Z","event":"session_end","status":"failed","heal_decision":"PASS","heal_iterations":2}' > "$T/.supervisor/logs/sess-b.jsonl"
( cd "$T" && bash "$BUILD" >/dev/null 2>&1 )

# NOTE: sess-a and sess-b above carry NONE of the System Twin flat fields — so this whole "== 2 =="
# block doubles as the all-twin-fields-absent backward-compat case (asserted below).
d="$T/.supervisor/insights/dashboard.md"
[ -f "$d" ] && ok "dashboard.md created" || no "dashboard.md missing"
grep -qF "| Sessions | 2 |" "$d" 2>/dev/null && ok "counts 2 sessions" || no "session count wrong"
grep -qF "| Completed | 1 |" "$d" 2>/dev/null && grep -qF "| Failed | 1 |" "$d" 2>/dev/null && ok "completed/failed split correct" || no "completed/failed split wrong"
grep -q "50%" "$d" 2>/dev/null && ok "completion rate = 50%" || no "completion rate wrong"
grep -q "ccusage" "$d" 2>/dev/null && ok "cost stub points to ccusage" || no "cost stub missing"
[ -f "$T/.supervisor/insights/runs/sess-a.md" ] && [ -f "$T/.supervisor/insights/runs/sess-b.md" ] && ok "per-run notes written" || no "per-run notes missing"
grep -qF 'rubric_score: "7/7"' "$T/.supervisor/insights/runs/sess-a.md" 2>/dev/null && ok "run-A frontmatter carries rubric_score" || no "run-A frontmatter wrong"
# Per-run frontmatter always carries plugin_version; older logs (no plugin_version) render "unknown".
grep -qF 'plugin_version: unknown' "$T/.supervisor/insights/runs/sess-a.md" 2>/dev/null && ok "run-A (older log) frontmatter carries plugin_version: unknown" || no "run-A missing plugin_version: unknown"
if grep -q "^rubric_score:" "$T/.supervisor/insights/runs/sess-b.md" 2>/dev/null; then no "run-B invented an absent rubric field"; else ok "run-B omits absent fields (tolerant, no crash)"; fi
grep -q '```dataview' "$d" 2>/dev/null && ok "dashboard includes the Obsidian/Dataview fence" || no "dataview fence missing"
order="$(awk '/^\| Session \|/{t=1;next} t&&/sess-b/{print "b";exit} t&&/sess-a/{print "a";exit}' "$d")"
[ "$order" = "b" ] && ok "recent-sessions sorted newest-first (sess-b before sess-a)" || no "recent-sessions order wrong (got: ${order:-none})"
# Backward-compat: with NO run carrying twin fields, the optional hard-signal section must be SUPPRESSED
# (no fabricated zeros) yet the dashboard must still render fully.
if grep -q "## System Twin hard signal" "$d" 2>/dev/null; then no "twin section appeared with no twin fields present"; else ok "twin section suppressed when no run reports it (backward-compat)"; fi
grep -q "^## Summary" "$d" 2>/dev/null && grep -q "^## Recent sessions" "$d" 2>/dev/null && ok "dashboard still renders fully with zero twin fields" || no "dashboard incomplete in twin-absent case"
# Per-run notes for twin-absent runs must NOT invent the hard-signal frontmatter keys.
if grep -q "^contract_conformance_status:" "$T/.supervisor/insights/runs/sess-a.md" 2>/dev/null; then no "run-A invented absent contract_conformance_status"; else ok "run-A omits absent twin fields (tolerant)"; fi
# Knowledge sources: sess-a/sess-b carry NO knowledge_sources_used → section must be suppressed.
if grep -q "## Knowledge sources" "$d" 2>/dev/null; then no "ks section appeared with no sources"; else ok "ks section suppressed when no run reports a source"; fi
rm -rf "$T"

echo "== 3. System Twin hard-signal aggregation =="
S="$(mktemp -d)"; ( cd "$S" && git init -q && git config user.email t@t && git config user.name t && echo x>f && git add f && git commit -qm i )
mkdir -p "$S/.supervisor/logs"
# tw-a: clean conformance + improved benchmark (older ts)
printf '%s\n' '{"ts":"2026-06-01T09:00:00Z","event":"session_end","status":"completed","heal_decision":"PASS","heal_iterations":1,"rubric_score":"5/5","contract_conformance_status":"pass","contract_violations":0,"benchmark_status":"improved","benchmark_metric":"build_seconds","benchmark_value":42,"benchmark_delta":-3}' > "$S/.supervisor/logs/tw-a.jsonl"
# tw-b: advisory violations + regressed benchmark (newest ts → drives "latest" value/delta)
printf '%s\n' '{"ts":"2026-06-03T09:00:00Z","event":"session_end","status":"completed","heal_decision":"PASS","heal_iterations":0,"contract_conformance_status":"advisory_violations","contract_violations":2,"benchmark_status":"regressed","benchmark_metric":"build_seconds","benchmark_value":50,"benchmark_delta":5}' > "$S/.supervisor/logs/tw-b.jsonl"
# tw-c: an older-shape run with NONE of the twin fields (mixed corpus — must not break aggregation)
printf '%s\n' '{"ts":"2026-06-02T09:00:00Z","event":"session_end","status":"completed","heal_decision":"PASS","heal_iterations":1}' > "$S/.supervisor/logs/tw-c.jsonl"
( cd "$S" && bash "$BUILD" >/dev/null 2>&1 )
sd="$S/.supervisor/insights/dashboard.md"
grep -q "## System Twin hard signal" "$sd" 2>/dev/null && ok "twin section rendered when runs report it" || no "twin section missing"
grep -qF "| Runs reporting conformance | 2 |" "$sd" 2>/dev/null && ok "twin_runs counts only reporting runs (2 of 3)" || no "twin_runs wrong"
grep -qF "| Conformance = pass | 1 |" "$sd" 2>/dev/null && ok "conformance pass count = 1" || no "conformance pass count wrong"
grep -qF "| Contract violations (total, advisory) | 2 |" "$sd" 2>/dev/null && ok "total contract violations = 2" || no "contract violations sum wrong"
grep -qF "| Benchmark regressed / improved | 1 / 1 |" "$sd" 2>/dev/null && ok "benchmark regressed/improved = 1/1" || no "benchmark regressed/improved wrong"
grep -qF "| Latest benchmark value | 50 |" "$sd" 2>/dev/null && ok "latest benchmark value = newest run (50)" || no "latest benchmark value wrong"
grep -qF "| Latest benchmark delta | 5 |" "$sd" 2>/dev/null && ok "latest benchmark delta = newest run (5)" || no "latest benchmark delta wrong"
# Recent-sessions hard-signal column present and populated for a twin run, "—" for the absent one.
grep -qF "| pass / -3 |" "$sd" 2>/dev/null && ok "recent table shows conformance/Δ for a twin run" || no "recent twin column wrong"
grep -qE "tw-c .*\| — / — \|" "$sd" 2>/dev/null && ok "recent table shows — / — for the twin-absent run" || no "recent twin-absent column wrong"
# Per-run frontmatter carries the twin fields for a reporting run, omits them for the absent run.
grep -qF "contract_conformance_status: advisory_violations" "$S/.supervisor/insights/runs/tw-b.md" 2>/dev/null && ok "run-tw-b frontmatter carries contract_conformance_status" || no "run-tw-b twin frontmatter missing"
if grep -q "^contract_conformance_status:" "$S/.supervisor/insights/runs/tw-c.md" 2>/dev/null; then no "run-tw-c invented absent twin field"; else ok "run-tw-c omits absent twin fields"; fi
rm -rf "$S"

echo "== 4. Eval fitness + Twin growth sections (present) =="
E="$(mktemp -d)"; ( cd "$E" && git init -q && git config user.email t@t && git config user.name t && echo x>f && git add f && git commit -qm i )
mkdir -p "$E/.supervisor/logs"
printf '%s\n' '{"ts":"2026-06-01T10:00:00Z","event":"session_end","status":"completed","heal_decision":"PASS","heal_iterations":1}' > "$E/.supervisor/logs/sess-e.jsonl"
# eval results.jsonl: deliberately written OUT OF FILE ORDER + one unverified record, to exercise
# (a) the status=="ok" filter — the unverified 0/0 (emitted when an eval could not run) must NOT
#     pollute the fitness trend (it would misread as "everything failed" vs "not measured"); and
# (b) the recorded_at sort — the trend must read oldest→newest regardless of append/file order.
# Note status is "ok" (what run-eval.sh actually emits), not "verified".
mkdir -p "$E/.supervisor/eval"
{
  printf '%s\n' '{"schema_version":1,"pass_rate":"5/6","status":"ok","recorded_at":"2026-06-03T10:00:00Z"}'
  printf '%s\n' '{"schema_version":1,"pass_rate":"0/0","status":"unverified","recorded_at":"2026-06-03T12:00:00Z"}'
  printf '%s\n' '{"schema_version":1,"pass_rate":"4/4","status":"ok","recorded_at":"2026-06-02T10:00:00Z"}'
  printf '%s\n' '{"schema_version":1,"pass_rate":"6/6","status":"ok","recorded_at":"2026-06-04T10:00:00Z"}'
} > "$E/.supervisor/eval/results.jsonl"
# twin store: 3 contract files + provenance with adds across 2 dates
mkdir -p "$E/.supervisor/twin/contracts"
echo "a" > "$E/.supervisor/twin/contracts/sub-a.md"
echo "b" > "$E/.supervisor/twin/contracts/sub-b.md"
echo "c" > "$E/.supervisor/twin/contracts/sub-c.md"
{
  printf '%s\n' '{"action":"add","subsystem":"sub-a","written_at":"2026-06-01T09:00:00Z"}'
  printf '%s\n' '{"action":"add","subsystem":"sub-b","written_at":"2026-06-01T09:05:00Z"}'
  printf '%s\n' '{"action":"add","subsystem":"sub-c","written_at":"2026-06-02T09:00:00Z"}'
} > "$E/.supervisor/twin/.provenance.jsonl"
out="$( cd "$E" && bash "$BUILD" 2>&1 )"; rc=$?
ed="$E/.supervisor/insights/dashboard.md"
[ "$rc" -eq 0 ] && ok "build exits 0 (sections present case)" || no "build rc != 0 (present case, rc=$rc)"
grep -q "^## Eval fitness function" "$ed" 2>/dev/null && ok "Eval fitness section present" || no "Eval fitness section missing"
grep -qF "6/6" "$ed" 2>/dev/null && ok "latest pass-rate 6/6 appears" || no "latest pass-rate missing"
grep -qF "4/4 → 5/6 → 6/6" "$ed" 2>/dev/null && ok "eval trend arrow chain present (sorted oldest→newest by recorded_at, out-of-order file)" || no "eval trend chain wrong"
# the unverified 0/0 record must be filtered out of the Eval fitness section (status=="ok" only).
evsec="$(sed -n '/^## Eval fitness function/,/^## System Twin growth/p' "$ed" 2>/dev/null)"
printf '%s' "$evsec" | grep -qF "0/0" && no "unverified 0/0 leaked into the eval fitness trend" || ok "unverified 0/0 excluded from eval fitness trend (status==ok filter)"
printf '%s' "$evsec" | grep -qF "Latest pass-rate:** 6/6" && ok "latest pass-rate = newest by recorded_at (6/6)" || no "latest pass-rate not newest-by-recorded_at"
grep -q "^## System Twin growth" "$ed" 2>/dev/null && ok "System Twin growth section present" || no "Twin growth section missing"
grep -qF "3 contracts" "$ed" 2>/dev/null && ok "contract count (3) appears" || no "contract count wrong"
grep -qF "(2 → 3)" "$ed" 2>/dev/null && ok "twin growth cumulative arrow present" || no "twin growth arrow wrong"
rm -rf "$E"

echo "== 5. Eval + Twin sections degrade gracefully (absent) =="
A="$(mktemp -d)"; ( cd "$A" && git init -q && git config user.email t@t && git config user.name t && echo x>f && git add f && git commit -qm i )
mkdir -p "$A/.supervisor/logs"
printf '%s\n' '{"ts":"2026-06-01T10:00:00Z","event":"session_end","status":"completed","heal_decision":"PASS","heal_iterations":1}' > "$A/.supervisor/logs/sess-x.jsonl"
out="$( cd "$A" && bash "$BUILD" 2>&1 )"; rc=$?
ad="$A/.supervisor/insights/dashboard.md"
[ "$rc" -eq 0 ] && ok "build exits 0 (sections absent case)" || no "build rc != 0 (absent case, rc=$rc)"
grep -q "^## Eval fitness function" "$ad" 2>/dev/null && ok "Eval fitness heading present when absent" || no "Eval fitness heading missing (absent)"
grep -qF "No eval runs recorded yet" "$ad" 2>/dev/null && ok "Eval no-data line rendered" || no "Eval no-data line missing"
grep -q "^## System Twin growth" "$ad" 2>/dev/null && ok "Twin growth heading present when absent" || no "Twin growth heading missing (absent)"
grep -qF "No System Twin contracts recorded yet" "$ad" 2>/dev/null && ok "Twin no-data line rendered" || no "Twin no-data line missing"
grep -q "^## Summary" "$ad" 2>/dev/null && grep -q "^## Cost" "$ad" 2>/dev/null && ok "dashboard still renders fully (absent case)" || no "dashboard incomplete (absent case)"
rm -rf "$A"

echo "== 6. Per-version insights (plugin_version grouping) =="
V="$(mktemp -d)"; ( cd "$V" && git init -q && git config user.email t@t && git config user.name t && echo x>f && git add f && git commit -qm i )
mkdir -p "$V/.supervisor/logs"
# pv-a + pv-b: SAME plugin_version (14.24.0) — one heal-PASS rubric 5/5, one FAIL rubric 5/10
# → expected row: runs=2, heal-PASS rate=50%, avg heal=(1+3)/2=2, avg rubric=(100%+50%)/2=75%
printf '%s\n' '{"ts":"2026-06-01T10:00:00Z","event":"session_end","status":"completed","heal_decision":"PASS","heal_iterations":1,"rubric_score":"5/5","plugin_version":"14.24.0"}' > "$V/.supervisor/logs/pv-a.jsonl"
printf '%s\n' '{"ts":"2026-06-02T10:00:00Z","event":"session_end","status":"failed","heal_decision":"FAIL","heal_iterations":3,"rubric_score":"5/10","plugin_version":"14.24.0"}' > "$V/.supervisor/logs/pv-b.jsonl"
# pv-c: NO plugin_version (older-log shape) — MUST group under "unknown" (mixed corpus)
printf '%s\n' '{"ts":"2026-06-03T10:00:00Z","event":"session_end","status":"completed","heal_decision":"PASS","heal_iterations":2}' > "$V/.supervisor/logs/pv-c.jsonl"
( cd "$V" && bash "$BUILD" >/dev/null 2>&1 )
vd="$V/.supervisor/insights/dashboard.md"
grep -q "^## Per-version insights" "$vd" 2>/dev/null && ok "per-version section rendered" || no "per-version section missing"
grep -qF "| Version | Runs | Heal-PASS rate | Avg heal iterations | Avg rubric score |" "$vd" 2>/dev/null && ok "per-version table header present" || no "per-version table header wrong"
grep -qF "| 14.24.0 | 2 | 50% | 2 | 75% |" "$vd" 2>/dev/null && ok "14.24.0 row aggregates correctly (2 runs, 50% PASS, avg heal 2, avg rubric 75%)" || no "14.24.0 row wrong"
grep -qF "| unknown | 1 | 100% | 2 | — |" "$vd" 2>/dev/null && ok "absent plugin_version groups under \"unknown\"" || no "unknown row wrong"
grep -qF "plugin_version: 14.24.0" "$V/.supervisor/insights/runs/pv-a.md" 2>/dev/null && ok "run pv-a per-run frontmatter carries explicit plugin_version: 14.24.0" || no "pv-a per-run plugin_version wrong"
# Existing sections must be untouched by the additive per-version section.
grep -q "^## Summary" "$vd" 2>/dev/null && grep -q "^## Recent sessions" "$vd" 2>/dev/null && ok "dashboard still renders fully with per-version section" || no "dashboard incomplete with per-version section"
rm -rf "$V"

echo "== 7. Knowledge sources aggregation =="
K="$(mktemp -d)"; ( cd "$K" && git init -q && git config user.email t@t && git config user.name t && echo x>f && git add f && git commit -qm i )
mkdir -p "$K/.supervisor/logs"
# ks-a: three sources incl project_memory (14.33.0)
printf '%s\n' '{"ts":"2026-06-10T10:00:00Z","event":"session_end","status":"completed","heal_decision":"PASS","heal_iterations":1,"plugin_version":"14.33.0","knowledge_sources_used":["project_memory","lessons:testing","brain_context"]}' > "$K/.supervisor/logs/ks-a.jsonl"
# ks-b: one source, project_memory (14.33.0)
printf '%s\n' '{"ts":"2026-06-11T10:00:00Z","event":"session_end","status":"completed","heal_decision":"PASS","heal_iterations":0,"plugin_version":"14.33.0","knowledge_sources_used":["project_memory"]}' > "$K/.supervisor/logs/ks-b.jsonl"
# ks-c: old log — NO field, NO plugin_version (mixed corpus → "unknown", 0 with a source)
printf '%s\n' '{"ts":"2026-06-12T10:00:00Z","event":"session_end","status":"completed","heal_decision":"PASS","heal_iterations":1}' > "$K/.supervisor/logs/ks-c.jsonl"
( cd "$K" && bash "$BUILD" >/dev/null 2>&1 )
kd="$K/.supervisor/insights/dashboard.md"
grep -q "## Knowledge sources (memory APPLY)" "$kd" 2>/dev/null && ok "knowledge sources section rendered when runs report a source" || no "knowledge sources section missing"
grep -qF "**Runs reporting a knowledge source:** 2 of 3" "$kd" 2>/dev/null && ok "runs-reporting count = 2 of 3" || no "runs-reporting count wrong"
grep -qF "| project_memory | 2 |" "$kd" 2>/dev/null && ok "top tag project_memory counted across ks-a + ks-b (2)" || no "top tag project_memory wrong"
grep -qF -- "- **Knowledge sources:** project_memory, lessons:testing, brain_context" "$K/.supervisor/insights/runs/ks-a.md" 2>/dev/null && ok "ks-a per-run body lists its knowledge sources" || no "ks-a per-run body wrong"
if grep -q "^knowledge_sources_used:" "$K/.supervisor/insights/runs/ks-c.md" 2>/dev/null; then no "ks-c invented absent knowledge_sources_used frontmatter"; else ok "ks-c omits absent knowledge_sources_used frontmatter"; fi
grep -qF "| unknown | 0 |" "$kd" 2>/dev/null && ok "per-version usage shows 0 runs-with-a-source for unknown (ks-c)" || no "per-version unknown usage wrong"
rm -rf "$K"

echo "== 8. Heal-signal catch-rate (MEASURE leg, Local Twin Step 2) =="
# Rendered case: a session log (so a dashboard is written) + a heal-signal trend ledger carrying
# two SCORED matrices (recall 0 → 33) plus one n=0 record that MUST be filtered out of "latest".
H="$(mktemp -d)"; ( cd "$H" && git init -q && git config user.email t@t && git config user.name t && echo x>f && git add f && git commit -qm i )
mkdir -p "$H/.supervisor/logs" "$H/.supervisor/heal-signal"
printf '%s\n' '{"ts":"2026-06-19T10:00:00Z","event":"session_end","status":"completed","heal_decision":"PASS","heal_iterations":1}' > "$H/.supervisor/logs/h-a.jsonl"
{
  printf '%s\n' '{"schema_version":1,"recorded_at":"2026-06-18T00:00:00Z","repos":["x"],"n":8,"tp":0,"fp":0,"fn":6,"tn":2,"recall_pct":0,"false_positive_pct":0,"self_heal_share_pct":54,"coverage_pct":10}'
  printf '%s\n' '{"schema_version":1,"recorded_at":"2026-06-19T00:00:00Z","repos":["x"],"n":7,"tp":1,"fp":1,"fn":2,"tn":3,"recall_pct":33,"false_positive_pct":25,"self_heal_share_pct":40,"coverage_pct":50}'
  printf '%s\n' '{"schema_version":1,"recorded_at":"2026-06-20T00:00:00Z","repos":["x"],"n":0,"recall_pct":null}'
} > "$H/.supervisor/heal-signal/results.jsonl"
( cd "$H" && bash "$BUILD" >/dev/null 2>&1 )
hd="$H/.supervisor/insights/dashboard.md"
grep -q "## Heal-signal catch-rate (MEASURE)" "$hd" 2>/dev/null && ok "heal-signal section rendered when a scored matrix exists" || no "heal-signal section missing"
grep -qF "**Latest catch-rate (recall):** 33%" "$hd" 2>/dev/null && ok "latest catch-rate = 33% (n=0 record filtered out)" || no "latest catch-rate wrong"
grep -qF "**False-negatives (missed):** 2 of N=7" "$hd" 2>/dev/null && ok "latest FN = 2 of N=7" || no "latest FN wrong"
grep -qF "**Coverage:** 50%" "$hd" 2>/dev/null && ok "latest coverage = 50%" || no "latest coverage wrong"
grep -qF "0% → 33%" "$hd" 2>/dev/null && ok "catch-rate trend 0% → 33% (oldest → newest)" || no "trend wrong"
grep -q "^## Summary" "$hd" 2>/dev/null && ok "dashboard still renders fully with the heal-signal section" || no "dashboard incomplete with heal-signal section"
rm -rf "$H"

echo "== 9. Heal-signal section suppressed when no scored data =="
# (a) ledger with ONLY an n=0 record → no scored matrix → section suppressed.
H2="$(mktemp -d)"; ( cd "$H2" && git init -q && git config user.email t@t && git config user.name t && echo x>f && git add f && git commit -qm i )
mkdir -p "$H2/.supervisor/logs" "$H2/.supervisor/heal-signal"
printf '%s\n' '{"ts":"2026-06-19T10:00:00Z","event":"session_end","status":"completed","heal_decision":"PASS"}' > "$H2/.supervisor/logs/h-a.jsonl"
printf '%s\n' '{"schema_version":1,"recorded_at":"2026-06-20T00:00:00Z","repos":["x"],"n":0,"recall_pct":null}' > "$H2/.supervisor/heal-signal/results.jsonl"
( cd "$H2" && bash "$BUILD" >/dev/null 2>&1 )
if grep -q "## Heal-signal catch-rate" "$H2/.supervisor/insights/dashboard.md" 2>/dev/null; then no "section appeared with only an n=0 record"; else ok "section suppressed when only unscored (n=0) records exist"; fi
rm -rf "$H2"
# (b) no ledger file at all → section suppressed, dashboard still renders.
H3="$(mktemp -d)"; ( cd "$H3" && git init -q && git config user.email t@t && git config user.name t && echo x>f && git add f && git commit -qm i )
mkdir -p "$H3/.supervisor/logs"
printf '%s\n' '{"ts":"2026-06-19T10:00:00Z","event":"session_end","status":"completed","heal_decision":"PASS"}' > "$H3/.supervisor/logs/h-a.jsonl"
( cd "$H3" && bash "$BUILD" >/dev/null 2>&1 )
hd3="$H3/.supervisor/insights/dashboard.md"
if grep -q "## Heal-signal catch-rate" "$hd3" 2>/dev/null; then no "section appeared with no ledger file"; else ok "section suppressed when no ledger file exists"; fi
grep -q "^## Summary" "$hd3" 2>/dev/null && ok "dashboard renders normally with no heal-signal ledger" || no "dashboard broken with no ledger"
rm -rf "$H3"

echo "== 10. Heal-signal renders a SCORED matrix with recall=n/a (tp+fn=0, not dropped) =="
# A scored run (n>0) where NO joined PR had a self-heal miss → recall_pct is null. This IS data
# (coverage + self_heal_share are meaningful), so the section must render with recall "n/a" rather
# than be silently dropped (the PR #73 review #2 finding). Mixed with a normal scored run to also
# assert the trend shows the n/a point.
H4="$(mktemp -d)"; ( cd "$H4" && git init -q && git config user.email t@t && git config user.name t && echo x>f && git add f && git commit -qm i )
mkdir -p "$H4/.supervisor/logs" "$H4/.supervisor/heal-signal"
printf '%s\n' '{"ts":"2026-06-19T10:00:00Z","event":"session_end","status":"completed","heal_decision":"PASS"}' > "$H4/.supervisor/logs/h-a.jsonl"
{
  printf '%s\n' '{"schema_version":1,"recorded_at":"2026-06-18T00:00:00Z","repos":["x"],"n":7,"tp":1,"fp":1,"fn":2,"tn":3,"recall_pct":33,"self_heal_share_pct":40,"coverage_pct":50}'
  printf '%s\n' '{"schema_version":1,"recorded_at":"2026-06-19T00:00:00Z","repos":["x"],"n":5,"tp":0,"fp":1,"fn":0,"tn":4,"recall_pct":null,"self_heal_share_pct":20,"coverage_pct":60}'
} > "$H4/.supervisor/heal-signal/results.jsonl"
( cd "$H4" && bash "$BUILD" >/dev/null 2>&1 )
h4d="$H4/.supervisor/insights/dashboard.md"
grep -q "## Heal-signal catch-rate (MEASURE)" "$h4d" 2>/dev/null && ok "section renders for a scored recall-null matrix (not dropped)" || no "scored recall-null matrix suppressed the section"
grep -qF "**Latest catch-rate (recall):** n/a" "$h4d" 2>/dev/null && ok "latest recall shown as n/a (tp+fn=0)" || no "recall-null not rendered as n/a"
grep -qF "**Coverage:** 60%" "$h4d" 2>/dev/null && ok "latest coverage 60% still surfaced despite null recall" || no "coverage lost on null-recall run"
grep -qF "33% → n/a" "$h4d" 2>/dev/null && ok "trend shows the n/a point (33% → n/a)" || no "trend dropped/mangled the n/a point"
rm -rf "$H4"

echo "== 11. Missing-drain reconciliation (AC5) — renders + classifies =="
# A done-brief corpus with three heal-signal PRs:
#   pull/72 — HAS a matching dispatch marker         → reconciled (NOT listed)
#   pull/73 — NO marker, durable run-time opt-out evidence in its `## Outcome` block → opted_out
#   pull/74 — NO marker, NO durable evidence (the silent-drop incident)              → unknown_or_opted_out
# Also include pull/7 as a marker to prove `/pull/7` does NOT satisfy `/pull/72` (exact-URL join).
M="$(mktemp -d)"; ( cd "$M" && git init -q && git config user.email t@t && git config user.name t && echo x>f && git add f && git commit -qm i )
mkdir -p "$M/.supervisor/logs" "$M/.supervisor/jobs/done" "$M/.supervisor/review-dispatch"
printf '%s\n' '{"ts":"2026-06-19T10:00:00Z","event":"session_end","status":"completed","heal_decision":"PASS"}' > "$M/.supervisor/logs/sess-m.jsonl"
URL="https://github.com/o/r/pull"
# done-brief for pull/72 (has marker)
cat > "$M/.supervisor/jobs/done/job-72.md" <<EOF
# Job 72
## Outcome
- **Status:** completed
- **PR:** $URL/72 (base: main)
- **heal_decision:** PASS
EOF
# done-brief for pull/73 (no marker, durable opt-out evidence in Outcome)
cat > "$M/.supervisor/jobs/done/job-73.md" <<EOF
# Job 73
## Outcome
- **Status:** completed
- **PR:** $URL/73 (base: main)
- **heal_decision:** PASS
- **Note:** drain dispatch suppressed via --no-auto-review for this run
EOF
# done-brief for pull/74 (no marker, NO durable evidence — silent drop)
cat > "$M/.supervisor/jobs/done/job-74.md" <<EOF
# Job 74
## Outcome
- **Status:** completed
- **PR:** $URL/74 (base: main)
- **heal_decision:** PASS
EOF
# markers: pull/72 (matches job-72) + pull/7 (must NOT match pull/72)
printf '20260618T195030Z\t%s/72\n' "$URL" > "$M/.supervisor/review-dispatch/aaa"
printf '20260618T195031Z\t%s/7\n'  "$URL" > "$M/.supervisor/review-dispatch/bbb"
( cd "$M" && bash "$BUILD" >/dev/null 2>&1 )
md="$M/.supervisor/insights/dashboard.md"
grep -q "^## Missing-drain reconciliation" "$md" 2>/dev/null && ok "missing-drain section renders when a heal-signal PR has no marker" || no "missing-drain section missing"
# pull/72 has a marker → must NOT appear as a missing row.
mdsec="$(sed -n '/^## Missing-drain reconciliation/,/^## /p' "$md" 2>/dev/null)"
printf '%s' "$mdsec" | grep -qE "\| $URL/72 \|" && no "pull/72 listed despite having a matching marker" || ok "pull/72 reconciled (has marker, not listed)"
# pull/73 → opted_out (durable run-time evidence present).
printf '%s' "$mdsec" | grep -qE "\| $URL/73 \| opted_out \|" && ok "pull/73 classified opted_out (durable run-time evidence)" || no "pull/73 not classified opted_out"
# pull/74 → unknown_or_opted_out (silent drop, no evidence).
printf '%s' "$mdsec" | grep -qE "\| $URL/74 \| unknown_or_opted_out \|" && ok "pull/74 classified unknown_or_opted_out (silent drop, no evidence)" || no "pull/74 not classified unknown_or_opted_out"
# exact-URL join: pull/7 marker must NOT reconcile pull/72.
printf '%s' "$mdsec" | grep -qF "Missing a drain marker:** 2" && ok "exact-URL join: 2 missing (pull/7 marker did not satisfy pull/72)" || no "missing count wrong (exact-URL join failed)"
# never a blanket accusation.
printf '%s' "$mdsec" | grep -qiE "\bdropped\b" && no "section printed a blanket 'dropped' accusation" || ok "no blanket 'dropped' accusation in the section"
grep -q "^## Summary" "$md" 2>/dev/null && ok "dashboard still renders fully with the missing-drain section" || no "dashboard incomplete with missing-drain section"
rm -rf "$M"

echo "== 12. Missing-drain: opted_out NOT inferred from current config.json =="
# A markerless heal-signal PR with NO durable run-time evidence, but config.json says
# auto_review:false RIGHT NOW. The audit must NOT read config.json → still unknown_or_opted_out
# (config is mutable; reading it would mislabel a genuine later drop as a deliberate opt-out).
C="$(mktemp -d)"; ( cd "$C" && git init -q && git config user.email t@t && git config user.name t && echo x>f && git add f && git commit -qm i )
mkdir -p "$C/.supervisor/logs" "$C/.supervisor/jobs/done" "$C/.supervisor/review-dispatch"
printf '%s\n' '{"ts":"2026-06-19T10:00:00Z","event":"session_end","status":"completed","heal_decision":"PASS"}' > "$C/.supervisor/logs/sess-c.jsonl"
printf '%s\n' '{"auto_review": false}' > "$C/.supervisor/config.json"
URL="https://github.com/o/r/pull"
cat > "$C/.supervisor/jobs/done/job-80.md" <<EOF
# Job 80
## Outcome
- **Status:** completed
- **PR:** $URL/80 (base: main)
- **heal_decision:** PASS
EOF
# a marker for a DIFFERENT pr so the corpus is non-empty and the section renders.
printf '20260618T195030Z\t%s/81\n' "$URL" > "$C/.supervisor/review-dispatch/zzz"
( cd "$C" && bash "$BUILD" >/dev/null 2>&1 )
cd2="$C/.supervisor/insights/dashboard.md"
csec="$(sed -n '/^## Missing-drain reconciliation/,/^## /p' "$cd2" 2>/dev/null)"
printf '%s' "$csec" | grep -qE "\| $URL/80 \| unknown_or_opted_out \|" && ok "config.json auto_review:false does NOT yield opted_out (not inferred from current config)" || no "opted_out wrongly inferred from current config.json"
rm -rf "$C"

echo "== 13. Missing-drain section suppressed when no corpus =="
# No done-briefs with Outcome PRs AND no markers → section suppressed entirely (no fabricated zeros).
NS="$(mktemp -d)"; ( cd "$NS" && git init -q && git config user.email t@t && git config user.name t && echo x>f && git add f && git commit -qm i )
mkdir -p "$NS/.supervisor/logs"
printf '%s\n' '{"ts":"2026-06-19T10:00:00Z","event":"session_end","status":"completed","heal_decision":"PASS"}' > "$NS/.supervisor/logs/sess-ns.jsonl"
( cd "$NS" && bash "$BUILD" >/dev/null 2>&1 )
nsd="$NS/.supervisor/insights/dashboard.md"
if grep -q "## Missing-drain reconciliation" "$nsd" 2>/dev/null; then no "missing-drain section appeared with no corpus"; else ok "missing-drain section suppressed when no heal-signal/marker corpus exists"; fi
grep -q "^## Summary" "$nsd" 2>/dev/null && ok "dashboard renders normally with no missing-drain corpus" || no "dashboard broken with no missing-drain corpus"
rm -rf "$NS"

echo "== 14. Missing-drain: prose mention of auto_review/suppress is NOT opted_out (finding #2) =="
# A markerless heal-signal PR whose ## Outcome NARRATES the words "auto_review" and
# "suppress" in prose but records NO durable opt-out FORM (no `--no-auto-review`, no
# `auto_review ... false`). This is exactly the #74-class silent-drop shape — it MUST
# classify unknown_or_opted_out, not opted_out (the old bare-word match mislabeled it,
# hiding the very signal AC5 exists to surface). pull/77 (durable `auto_review == false`)
# must STILL classify opted_out, proving the tightening didn't over-correct.
P="$(mktemp -d)"; ( cd "$P" && git init -q && git config user.email t@t && git config user.name t && echo x>f && git add f && git commit -qm i )
mkdir -p "$P/.supervisor/logs" "$P/.supervisor/jobs/done" "$P/.supervisor/review-dispatch"
printf '%s\n' '{"ts":"2026-06-19T10:00:00Z","event":"session_end","status":"completed","heal_decision":"PASS"}' > "$P/.supervisor/logs/sess-p.jsonl"
URL="https://github.com/o/r/pull"
cat > "$P/.supervisor/jobs/done/job-76.md" <<EOF
# Job 76
## Outcome
- **Status:** completed
- **PR:** $URL/76 (base: main)
- **heal_decision:** PASS
- **Until-mergeable note:** the agent set auto_review then never re-dispatched; the drain was suppressed and the dispatch was missed (a silent drop to investigate).
EOF
cat > "$P/.supervisor/jobs/done/job-77.md" <<EOF
# Job 77
## Outcome
- **Status:** completed
- **PR:** $URL/77 (base: main)
- **heal_decision:** PASS
- **Note:** dispatch disabled (config .auto_review == false) for this run
EOF
printf '20260618T195030Z\t%s/78\n' "$URL" > "$P/.supervisor/review-dispatch/zzz"   # non-empty corpus
( cd "$P" && bash "$BUILD" >/dev/null 2>&1 )
psec="$(sed -n '/^## Missing-drain reconciliation/,/^## /p' "$P/.supervisor/insights/dashboard.md" 2>/dev/null)"
printf '%s' "$psec" | grep -qE "\| $URL/76 \| unknown_or_opted_out \|" && ok "prose mention of auto_review/suppress (no durable form) => unknown_or_opted_out (not mislabeled)" || no "prose mention wrongly classified opted_out (finding #2 regression)"
printf '%s' "$psec" | grep -qE "\| $URL/77 \| opted_out \|" && ok "durable 'auto_review == false' still => opted_out (tightening didn't over-correct)" || no "durable opt-out form no longer detected"
rm -rf "$P"

echo "== 15. Corpus health — renders with correct counts (both corpora present) =="
# Churn ledger fixture: 2 data lines (one with a hard-coded stale 2020 ts) + 2 curation records
# BOTH targeting the same data entry (curated must count DISTINCT target_key values → 1).
# Lessons fixture: 2 lesson lines (one fresh trailer computed at runtime so the fixture never ages,
# one hard-coded stale 2020 trailer) + a provenance file with 1 add + 1 retract.
CH="$(mktemp -d)"; ( cd "$CH" && git init -q && git config user.email t@t && git config user.name t && echo x>f && git add f && git commit -qm i )
mkdir -p "$CH/.supervisor/logs" "$CH/.supervisor/postmortem" "$CH/.supervisor/memory"
printf '%s\n' '{"ts":"2026-06-01T10:00:00Z","event":"session_end","status":"completed","heal_decision":"PASS"}' > "$CH/.supervisor/logs/sess-ch.jsonl"
{
  printf '%s\n' '{"ts":"2026-06-01T00:00:00Z","pr_url":"https://github.com/o/r/pull/1","changed_paths":["a"],"review_rounds":2}'
  printf '%s\n' '{"ts":"2020-01-01T00:00:00Z","pr_url":"https://github.com/o/r/pull/2","changed_paths":["b"],"review_rounds":1}'
  printf '%s\n' '{"ts":"2026-06-02T00:00:00Z","source":"curation","action":"retract","target_key":"https://github.com/o/r/pull/2"}'
  printf '%s\n' '{"ts":"2026-06-03T00:00:00Z","source":"curation","action":"supersede","target_key":"https://github.com/o/r/pull/2"}'
} > "$CH/.supervisor/postmortem/results.jsonl"
fresh_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
{
  printf '%s\n' "# Lessons"
  printf '%s\n' "## testing"
  printf '%s\n' "- [testing] run scripts via bash, never inline zsh <!-- last_verified=$fresh_iso -->"
  printf '%s\n' "- [process] an old lesson nobody re-verified <!-- last_verified=2020-01-01T00:00:00Z -->"
} > "$CH/.supervisor/memory/LESSONS.md"
{
  printf '%s\n' '{"action":"add","category":"testing","content_hash":"aaa","prev_hash":"GENESIS"}'
  printf '%s\n' '{"action":"retract","target_key":"testing run scripts via bash, never inline zsh","prev_hash":"bbb"}'
} > "$CH/.supervisor/memory/.lessons-provenance.jsonl"
out="$( cd "$CH" && bash "$BUILD" 2>&1 )"; rc=$?
chd="$CH/.supervisor/insights/dashboard.md"
[ "$rc" -eq 0 ] && ok "build exits 0 (corpus health present case)" || no "build rc != 0 (corpus health present, rc=$rc)"
grep -q "^## Corpus health" "$chd" 2>/dev/null && ok "corpus health section rendered" || no "corpus health section missing"
grep -qF -- "- churn ledger: 2 entries, 1 curated (retracted/superseded), 1 stale (>180d)" "$chd" 2>/dev/null && ok "churn line correct (2 entries, 1 DISTINCT curated across 2 records, 1 stale)" || no "churn line wrong"
grep -qF -- "- lessons: 2 entries, 1 retracted, 1 stale (>90d)" "$chd" 2>/dev/null && ok "lessons line correct (2 entries, 1 retracted, 1 stale)" || no "lessons line wrong"
# Additive: existing sections must be untouched, and the section sits before the Obsidian footer.
grep -q "^## Summary" "$chd" 2>/dev/null && grep -q "^## Recent sessions" "$chd" 2>/dev/null && grep -q "^## View in Obsidian" "$chd" 2>/dev/null && ok "dashboard still renders fully with corpus health" || no "dashboard incomplete with corpus health"
chorder="$(grep -n "^## Corpus health\|^## View in Obsidian" "$chd" 2>/dev/null | head -1)"
printf '%s' "$chorder" | grep -q "Corpus health" && ok "corpus health placed before the Obsidian footer" || no "corpus health placed after the footer"
rm -rf "$CH"

echo "== 16. Corpus health — absent corpora degrade gracefully =="
# (a) neither corpus exists → single "(no corpora found)" note, exit 0.
CA="$(mktemp -d)"; ( cd "$CA" && git init -q && git config user.email t@t && git config user.name t && echo x>f && git add f && git commit -qm i )
mkdir -p "$CA/.supervisor/logs"
printf '%s\n' '{"ts":"2026-06-01T10:00:00Z","event":"session_end","status":"completed","heal_decision":"PASS"}' > "$CA/.supervisor/logs/sess-ca.jsonl"
out="$( cd "$CA" && bash "$BUILD" 2>&1 )"; rc=$?
cad="$CA/.supervisor/insights/dashboard.md"
[ "$rc" -eq 0 ] && ok "build exits 0 (both corpora absent)" || no "build rc != 0 (both absent, rc=$rc)"
grep -q "^## Corpus health" "$cad" 2>/dev/null && ok "corpus health heading present when corpora absent" || no "corpus health heading missing (absent case)"
grep -qF "(no corpora found)" "$cad" 2>/dev/null && ok "no-corpora note rendered" || no "no-corpora note missing"
grep -q "^## Summary" "$cad" 2>/dev/null && grep -q "^## Cost" "$cad" 2>/dev/null && ok "dashboard still renders fully (corpora absent)" || no "dashboard incomplete (corpora absent)"
rm -rf "$CA"
# (b) ledger present, lessons absent → churn counts + per-corpus "absent" note.
CB="$(mktemp -d)"; ( cd "$CB" && git init -q && git config user.email t@t && git config user.name t && echo x>f && git add f && git commit -qm i )
mkdir -p "$CB/.supervisor/logs" "$CB/.supervisor/postmortem"
printf '%s\n' '{"ts":"2026-06-01T10:00:00Z","event":"session_end","status":"completed","heal_decision":"PASS"}' > "$CB/.supervisor/logs/sess-cb.jsonl"
printf '%s\n' '{"ts":"2026-06-01T00:00:00Z","pr_url":"https://github.com/o/r/pull/9","changed_paths":["c"]}' > "$CB/.supervisor/postmortem/results.jsonl"
( cd "$CB" && bash "$BUILD" >/dev/null 2>&1 )
cbd="$CB/.supervisor/insights/dashboard.md"
grep -qF -- "- churn ledger: 1 entries, 0 curated (retracted/superseded), 0 stale (>180d)" "$cbd" 2>/dev/null && ok "churn line renders alone (1 entry, zeros)" || no "churn-only line wrong"
grep -qF -- "- lessons: absent" "$cbd" 2>/dev/null && ok "lessons absent note rendered" || no "lessons absent note missing"
rm -rf "$CB"

echo "== 17. Corpus health — malformed JSONL lines skipped, presence discipline honored =="
# Ledger: 1 good data line + 2 malformed lines + curation records with explicit-null and MISSING
# target_key (jq has() presence discipline — neither may count as curated). Provenance: 1 retract
# + 1 malformed line. Nothing crashes; remaining counts stay correct.
CM="$(mktemp -d)"; ( cd "$CM" && git init -q && git config user.email t@t && git config user.name t && echo x>f && git add f && git commit -qm i )
mkdir -p "$CM/.supervisor/logs" "$CM/.supervisor/postmortem" "$CM/.supervisor/memory"
printf '%s\n' '{"ts":"2026-06-01T10:00:00Z","event":"session_end","status":"completed","heal_decision":"PASS"}' > "$CM/.supervisor/logs/sess-cm.jsonl"
{
  printf '%s\n' '{"ts":"2026-06-01T00:00:00Z","pr_url":"https://github.com/o/r/pull/3","changed_paths":["a"]}'
  printf '%s\n' '{not json at all'
  printf '%s\n' '{"source":"curation","action":"retract"'
  printf '%s\n' '{"source":"curation","action":"retract","target_key":null}'
  printf '%s\n' '{"source":"curation","action":"retract"}'
} > "$CM/.supervisor/postmortem/results.jsonl"
{
  printf '%s\n' "# Lessons"
  printf '%s\n' "## testing"
  printf '%s\n' "- [testing] a lesson with no trailer at all"
} > "$CM/.supervisor/memory/LESSONS.md"
{
  printf '%s\n' '{"action":"retract","target_key":"testing a lesson","prev_hash":"aaa"}'
  printf '%s\n' 'garbage not json'
} > "$CM/.supervisor/memory/.lessons-provenance.jsonl"
out="$( cd "$CM" && bash "$BUILD" 2>&1 )"; rc=$?
cmd2="$CM/.supervisor/insights/dashboard.md"
[ "$rc" -eq 0 ] && ok "build exits 0 despite malformed JSONL in both corpora" || no "build rc != 0 (malformed case, rc=$rc)"
grep -qF -- "- churn ledger: 1 entries, 0 curated (retracted/superseded), 0 stale (>180d)" "$cmd2" 2>/dev/null && ok "malformed + null/missing target_key skipped (1 entry, 0 curated)" || no "malformed-ledger counts wrong"
grep -qF -- "- lessons: 1 entries, 1 retracted, 0 stale (>90d)" "$cmd2" 2>/dev/null && ok "lessons: malformed provenance skipped, trailerless lesson counts fresh" || no "malformed-lessons counts wrong"
rm -rf "$CM"

echo "== 18. Corpus health — CHURN_STALE_DAYS override changes the stale count =="
# Same fixture 3× — default (2020 ts stale at >180d), a huge override (nothing stale, and the
# suffix reflects the override), and a NON-NUMERIC override (must fall back to 180).
CO="$(mktemp -d)"; ( cd "$CO" && git init -q && git config user.email t@t && git config user.name t && echo x>f && git add f && git commit -qm i )
mkdir -p "$CO/.supervisor/logs" "$CO/.supervisor/postmortem"
printf '%s\n' '{"ts":"2026-06-01T10:00:00Z","event":"session_end","status":"completed","heal_decision":"PASS"}' > "$CO/.supervisor/logs/sess-co.jsonl"
{
  printf '%s\n' '{"ts":"2026-06-01T00:00:00Z","pr_url":"https://github.com/o/r/pull/4","changed_paths":["a"]}'
  printf '%s\n' '{"ts":"2020-01-01T00:00:00Z","pr_url":"https://github.com/o/r/pull/5","changed_paths":["b"]}'
} > "$CO/.supervisor/postmortem/results.jsonl"
cod="$CO/.supervisor/insights/dashboard.md"
( cd "$CO" && bash "$BUILD" >/dev/null 2>&1 )
grep -qF -- "- churn ledger: 2 entries, 0 curated (retracted/superseded), 1 stale (>180d)" "$cod" 2>/dev/null && ok "default threshold: 1 stale (>180d)" || no "default-threshold stale count wrong"
( cd "$CO" && CHURN_STALE_DAYS=100000 bash "$BUILD" >/dev/null 2>&1 )
grep -qF -- "- churn ledger: 2 entries, 0 curated (retracted/superseded), 0 stale (>100000d)" "$cod" 2>/dev/null && ok "CHURN_STALE_DAYS=100000: 0 stale and suffix reflects override" || no "override stale count/suffix wrong"
( cd "$CO" && CHURN_STALE_DAYS=abc bash "$BUILD" >/dev/null 2>&1 )
grep -qF -- "- churn ledger: 2 entries, 0 curated (retracted/superseded), 1 stale (>180d)" "$cod" 2>/dev/null && ok "non-numeric CHURN_STALE_DAYS falls back to 180" || no "non-numeric override did not fall back to 180"
rm -rf "$CO"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
