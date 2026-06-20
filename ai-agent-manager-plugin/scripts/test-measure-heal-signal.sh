#!/usr/bin/env bash
# test-measure-heal-signal.sh — self-tests for the heal-signal measurement instrument
# (measure-heal-signal.py + measure-heal-signal.sh; Local Twin Step 2). Mirrors
# test-twin-graph.sh convention: runs in isolated temp dirs, never touches the real
# .supervisor/heal-signal. Exit 0 = all pass, 1 = any failure.
#
# Covers:
#   1. matrix correctness on a synthetic fixture — TP/FP/FN/TN cells + recall + TN split.
#   2. floor-raising dedup — a JOINED PR with two re-gathers (rounds5/misses0 + rounds3/misses4)
#      uses the per-field MAX (rounds5/misses4) → flips TN→FN; floor_raised=1.
#   3. bold `**Heal decision:**` AND lowercase `**heal_decision:**` Outcome forms both harvest.
#   4. label-quality diagnostics — agent_guess / zero_signal counts surface in the summary.
#   5. bounded --backfill is a PLAN only — lists the unlabeled PR + cost, dispatches nothing.
#   6. READ-ONLY invariant — the measured repo tree is byte-identical before/after a run.
#   7. trend ledger — one appended line per run with recall_pct/fn; --no-ledger writes none.
#   8. fail-safe empty — a repo with no done briefs → n=0, exit 0, "No joined rows" report.
#   9. wrapper repo resolution — default-self + $AI_AGENT_MANAGER_HEAL_SIGNAL_REPOS override.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_ENGINE="$HERE/measure-heal-signal.py"
SH_WRAP="$HERE/measure-heal-signal.sh"
PY="$(command -v python3 || command -v python || true)"
JQ="$(command -v jq || true)"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

if [ -z "$PY" ]; then echo "python3 unavailable — cannot self-test"; exit 1; fi
if [ -z "$JQ" ]; then echo "jq unavailable — cannot self-test"; exit 1; fi

# ---- fixture builders -------------------------------------------------------
# write_brief <repo> <file> <heal_key> <decision> <iters> <owner/repo> <number>
write_brief() {
  local repo="$1" file="$2" key="$3" dec="$4" iters="$5" or="$6" num="$7"
  mkdir -p "$repo/.supervisor/jobs/done"
  {
    printf '# brief %s\n\n## Outcome\n' "$file"
    printf -- '- **%s:** %s\n' "$key" "$dec"
    printf -- '- **Heal iterations:** %s\n' "$iters"
    printf -- '- **PR:** https://github.com/%s/pull/%s\n' "$or" "$num"
  } > "$repo/.supervisor/jobs/done/$file"
}
# add_label <repo> <json-line>
add_label() {
  mkdir -p "$1/.supervisor/postmortem"
  printf '%s\n' "$2" >> "$1/.supervisor/postmortem/results.jsonl"
}

# Build the canonical fixture repo used by tests 1–7.
build_fixture() {
  local R="$1"
  # A — bold form, FN (PASS + misses>0), agent-guess
  write_brief "$R" "a.md" "Heal decision" "PASS" 1 "acme/app" 1
  add_label "$R" '{"schema_version":1,"ts":"2026-06-01T00:00:00Z","repo":"acme/app","number":1,"agent_generated_guess":true,"review_rounds":5,"self_heal_misses":3,"review_rounds_source":"bot_comments","flow_stages":{"self_heal":2,"worker":1},"summary":"FN fixture"}'
  # B — lowercase form, TN clean (misses 0, low rounds)
  write_brief "$R" "b.md" "heal_decision" "PASS" 1 "acme/app" 2
  add_label "$R" '{"schema_version":1,"ts":"2026-06-01T00:00:00Z","repo":"acme/app","number":2,"agent_generated_guess":false,"review_rounds":1,"self_heal_misses":0,"review_rounds_source":"fix_commits","flow_stages":{"worker":1},"summary":"TN clean"}'
  # C — TN churn_elsewhere (misses 0, high rounds)
  write_brief "$R" "c.md" "heal_decision" "PASS" 0 "acme/app" 3
  add_label "$R" '{"schema_version":1,"ts":"2026-06-01T00:00:00Z","repo":"acme/app","number":3,"agent_generated_guess":false,"review_rounds":5,"self_heal_misses":0,"review_rounds_source":"formal_reviews","flow_stages":{"worker":5},"summary":"TN churn"}'
  # D — TP (ESCALATED + misses>0), human label
  write_brief "$R" "d.md" "heal_decision" "ESCALATED" 2 "acme/app" 4
  add_label "$R" '{"schema_version":1,"ts":"2026-06-01T00:00:00Z","repo":"acme/app","number":4,"agent_generated_guess":false,"review_rounds":4,"self_heal_misses":2,"review_rounds_source":"fix_commits","flow_stages":{"self_heal":1,"worker":3},"summary":"TP"}'
  # E — FP (ESCALATED + misses 0)
  write_brief "$R" "e.md" "heal_decision" "ESCALATED" 1 "acme/app" 5
  add_label "$R" '{"schema_version":1,"ts":"2026-06-01T00:00:00Z","repo":"acme/app","number":5,"agent_generated_guess":false,"review_rounds":1,"self_heal_misses":0,"review_rounds_source":"formal_reviews","flow_stages":{"worker":1},"summary":"FP"}'
  # F — floor-raising: two re-gathers. rep=max-rounds entry (5/0); other entry (3/4).
  #     per-field max -> rounds5/misses4 -> FN; floor_raised=1.
  write_brief "$R" "f.md" "heal_decision" "PASS" 1 "acme/app" 6
  add_label "$R" '{"schema_version":1,"ts":"2026-06-02T00:00:00Z","repo":"acme/app","number":6,"agent_generated_guess":true,"review_rounds":5,"self_heal_misses":0,"review_rounds_source":"fix_commits","flow_stages":{"self_heal":3,"launch_pad":2},"summary":"regather hi-rounds lo-misses"}'
  add_label "$R" '{"schema_version":1,"ts":"2026-06-01T00:00:00Z","repo":"acme/app","number":6,"agent_generated_guess":true,"review_rounds":3,"self_heal_misses":4,"review_rounds_source":"fix_commits","flow_stages":{"self_heal":1,"worker":2},"summary":"regather lo-rounds hi-misses"}'
  # G — UNLABELED heal-signal PR (no postmortem line) -> backfill candidate.
  write_brief "$R" "g.md" "heal_decision" "PASS" 1 "acme/app" 7
  # H — zero-signal label (source none, rounds 0) -> TN clean + zero_signal diagnostic.
  write_brief "$R" "h.md" "heal_decision" "PASS" 0 "acme/app" 8
  add_label "$R" '{"schema_version":1,"ts":"2026-06-01T00:00:00Z","repo":"acme/app","number":8,"agent_generated_guess":false,"review_rounds":0,"self_heal_misses":0,"review_rounds_source":"none","flow_stages":{},"summary":"zero signal"}'
}

run_engine() {  # run_engine <repo> <out> [extra args...]
  local repo="$1" out="$2"; shift 2
  "$PY" "$PY_ENGINE" --repos "$repo" --self-repo "$repo" --out "$out" --quiet "$@"
}
S() { "$JQ" -r "$1" "$2"; }  # jq read helper

# ============================================================================
echo "== 1. matrix correctness (TP/FP/FN/TN + recall + TN split) =="
TMP1="$(mktemp -d)"; OUT1="$(mktemp -d)"
build_fixture "$TMP1"
run_engine "$TMP1" "$OUT1" --no-ledger >/dev/null 2>&1; rc=$?
sum="$OUT1/_summary.json"
TP=$(S '.pooled.TP' "$sum"); FP=$(S '.pooled.FP' "$sum")
FN=$(S '.pooled.FN' "$sum"); TN=$(S '.pooled.TN' "$sum")
NJ=$(S '.n_joined' "$sum"); REC=$(S '.pooled.recall' "$sum")
CLEAN=$(S '.pooled.tn_clean' "$sum"); CHURN=$(S '.pooled.tn_churn_elsewhere' "$sum")
if [ "$rc" -eq 0 ] && [ "$TP" = 1 ] && [ "$FP" = 1 ] && [ "$FN" = 2 ] && [ "$TN" = 3 ] \
   && [ "$NJ" = 7 ] && [ "$CLEAN" = 2 ] && [ "$CHURN" = 1 ]; then
  ok "cells TP=1 FP=1 FN=2 TN=3 (clean=2 churn=1), n=7"
else
  no "matrix wrong (rc=$rc TP=$TP FP=$FP FN=$FN TN=$TN n=$NJ clean=$CLEAN churn=$CHURN)"
fi
# recall = TP/(TP+FN) = 1/3 ≈ 0.333
if awk -v r="$REC" 'BEGIN{exit !(r>0.32 && r<0.34)}'; then ok "recall ≈ 33% (1/3)"; else no "recall wrong ($REC)"; fi

echo "== 2. floor-raising dedup (re-gather max flips TN→FN) =="
# acme/app#6 must be FN with review_rounds=5 AND self_heal_misses=4 (per-field max).
row6="$("$JQ" -c 'select(.number==6)' "$OUT1/joined.jsonl")"
cell6="$(printf '%s' "$row6" | "$JQ" -r '.cell')"
rr6="$(printf '%s' "$row6" | "$JQ" -r '.review_rounds')"
shm6="$(printf '%s' "$row6" | "$JQ" -r '.self_heal_misses')"
FR=$(S '.label_quality.floor_raised' "$sum")
if [ "$cell6" = FN ] && [ "$rr6" = 5 ] && [ "$shm6" = 4 ] && [ "$FR" = 1 ]; then
  ok "#6 floor-raised to rounds=5/misses=4 → FN; floor_raised=1"
else
  no "floor-raising wrong (cell=$cell6 rr=$rr6 shm=$shm6 floor_raised=$FR)"
fi

echo "== 3. bold + lowercase Outcome forms both harvest =="
sig1="$("$JQ" -sc '[.[].number]|sort' "$OUT1/signal.jsonl")"
if printf '%s' "$sig1" | grep -q '1' && printf '%s' "$sig1" | grep -q '2'; then
  ok "both #1 (bold **Heal decision:**) and #2 (lowercase) harvested ($sig1)"
else
  no "outcome-form harvest gap ($sig1)"
fi

echo "== 4. label-quality diagnostics (agent_guess / zero_signal) =="
AG=$(S '.label_quality.agent_guess' "$sum"); ZS=$(S '.label_quality.zero_signal' "$sum")
# joined agent-guess labels: A(#1) + F(#6) = 2; zero-signal: H(#8 source none) = 1
if [ "$AG" = 2 ] && [ "$ZS" = 1 ]; then ok "agent_guess=2, zero_signal=1"; else no "diagnostics wrong (agent_guess=$AG zero_signal=$ZS)"; fi

echo "== 5. --backfill is a PLAN only (lists unlabeled PR, dispatches nothing) =="
OUT5="$(mktemp -d)"
out5_console="$(run_engine "$TMP1" "$OUT5" --no-ledger --backfill 5 2>&1)"
# console is --quiet-suppressed; the plan rides in report.md §6 + _summary.backfill
bf_prs="$("$JQ" -r '.backfill.prs[].number' "$OUT5/_summary.json" 2>/dev/null | sort | tr '\n' ' ')"
if echo "$bf_prs" | grep -q '7' \
   && grep -q "Nothing was dispatched" "$OUT5/report.md" \
   && grep -q "a PLAN, not an action" "$OUT5/report.md"; then
  ok "backfill plan lists unlabeled #7 and is marked plan-only ($bf_prs)"
else
  no "backfill plan wrong (prs='$bf_prs')"
fi
# the planner must not have created a postmortem entry for the unlabeled PR
cnt7="$(grep -c '"number":7' "$TMP1/.supervisor/postmortem/results.jsonl" 2>/dev/null)"; cnt7="${cnt7:-0}"
if [ "$cnt7" = 0 ]; then
  ok "backfill dispatched no /pr-postmortem (no label written for #7)"
else
  no "backfill wrote a label — it executed instead of planning"
fi

echo "== 6. READ-ONLY toward the measured repo =="
TMP6="$(mktemp -d)"; OUT6="$(mktemp -d)"   # OUT outside the measured tree
build_fixture "$TMP6"
before="$(cd "$TMP6" && find . -type f -exec shasum {} \; | sort)"
run_engine "$TMP6" "$OUT6" --backfill 3 >/dev/null 2>&1
after="$(cd "$TMP6" && find . -type f -exec shasum {} \; | sort)"
if [ "$before" = "$after" ]; then ok "measured repo tree byte-identical after a run"; else no "measured repo MUTATED"; fi

echo "== 7. trend ledger append + --no-ledger suppression =="
TMP7="$(mktemp -d)"; OUT7="$(mktemp -d)"
build_fixture "$TMP7"
run_engine "$TMP7" "$OUT7" --recorded-at "2026-06-19T00:00:00Z" >/dev/null 2>&1
run_engine "$TMP7" "$OUT7" --recorded-at "2026-06-20T00:00:00Z" >/dev/null 2>&1
lines="$(grep -c . "$OUT7/results.jsonl" 2>/dev/null || echo 0)"
rp="$("$JQ" -r 'select(.recorded_at=="2026-06-20T00:00:00Z") | "\(.recall_pct)/\(.fn)/\(.n)"' "$OUT7/results.jsonl" 2>/dev/null)"
if [ "$lines" = 2 ] && [ "$rp" = "33/2/7" ]; then ok "ledger appended 2 lines; latest recall_pct=33 fn=2 n=7"; else no "ledger wrong (lines=$lines latest=$rp)"; fi
OUT7b="$(mktemp -d)"; run_engine "$TMP7" "$OUT7b" --no-ledger >/dev/null 2>&1
if [ ! -f "$OUT7b/results.jsonl" ]; then ok "--no-ledger writes no results.jsonl"; else no "--no-ledger still wrote the ledger"; fi

echo "== 8. fail-safe empty (no done briefs) =="
TMP8="$(mktemp -d)"; OUT8="$(mktemp -d)"
mkdir -p "$TMP8/.supervisor/jobs/done"
run_engine "$TMP8" "$OUT8" --no-ledger >/dev/null 2>&1; rc=$?
nj=$(S '.n_joined' "$OUT8/_summary.json")
if [ "$rc" -eq 0 ] && [ "$nj" = 0 ] && grep -q "No joined rows" "$OUT8/report.md"; then
  ok "empty repo → n_joined=0, exit 0, 'No joined rows' report"
else
  no "fail-safe empty wrong (rc=$rc n_joined=$nj)"
fi

echo "== 9. wrapper repo resolution (default-self + env override) =="
# default-self: run the wrapper INSIDE a git repo with fixtures, no --repo.
TMP9="$(mktemp -d)"; build_fixture "$TMP9"
( cd "$TMP9" && git init -q && git config user.email t@t && git config user.name t ) >/dev/null 2>&1
out9="$( cd "$TMP9" && bash "$SH_WRAP" --no-ledger 2>&1 )"
nj9="$(S '.n_joined' "$TMP9/.supervisor/heal-signal/_summary.json")"
if [ "$nj9" = 7 ]; then ok "wrapper default-self measured the current repo (n_joined=7)"; else no "wrapper default-self wrong (n_joined=$nj9 | $out9)"; fi
# env override: point at a DIFFERENT fixture repo from an empty cwd.
TMPe="$(mktemp -d)"; build_fixture "$TMPe"
TMP9b="$(mktemp -d)"; ( cd "$TMP9b" && git init -q && git config user.email t@t && git config user.name t ) >/dev/null 2>&1
( cd "$TMP9b" && AI_AGENT_MANAGER_HEAL_SIGNAL_REPOS="$TMPe" bash "$SH_WRAP" --no-ledger ) >/dev/null 2>&1
njE="$(S '.pooled.n' "$TMP9b/.supervisor/heal-signal/_summary.json")"
if [ "$njE" = 7 ]; then ok "wrapper honored \$AI_AGENT_MANAGER_HEAL_SIGNAL_REPOS override (n=7)"; else no "env override wrong (n=$njE)"; fi

# cleanup
rm -rf "$TMP1" "$OUT1" "$OUT5" "$TMP6" "$OUT6" "$TMP7" "$OUT7" "$OUT7b" "$TMP8" "$OUT8" \
       "$TMP9" "$TMPe" "$TMP9b" 2>/dev/null

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
