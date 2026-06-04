#!/usr/bin/env bash
# test-insights.sh — self-tests for build-insights.sh (v14.7.0). Runs in isolated temp repos
# (never touches the real .supervisor). Exit 0 = all pass, 1 = any failure.
#
# Covers: no-logs no-op, dashboard aggregation (counts / completed-failed split / completion
# rate), per-run note generation, missing-field tolerance, the COST stub, and the System Twin
# hard-signal aggregation (contract conformance + benchmark) including a backward-compat case
# where NO run carries the new flat fields.

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

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
