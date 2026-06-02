#!/usr/bin/env bash
# test-insights.sh — self-tests for build-insights.sh (v14.7.0). Runs in isolated temp repos
# (never touches the real .supervisor). Exit 0 = all pass, 1 = any failure.
#
# Covers: no-logs no-op, dashboard aggregation (counts / completed-failed split / completion
# rate), per-run note generation, missing-field tolerance, and the COST stub.

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
rm -rf "$T"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
