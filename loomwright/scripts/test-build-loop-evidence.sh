#!/usr/bin/env bash
# test-build-loop-evidence.sh — fixture-driven self-tests for build-loop-evidence.sh, the
# READ-ONLY unattended-quality funnel builder. Builds ISOLATED temp fixture state-dirs
# (session logs + postmortem + heal-signal JSONL, and a temp git repo with a synthetic
# merged PR whose branch carries drain-cycle commits) so it NEVER touches real .supervisor/
# data. Mirrors the test-add-rule.sh harness convention. Exit 0 = all pass, 1 = any failure
# (the BUILDER is always-exit-0 fail-safe; this SELF-TEST is allowed to fail loudly).
#
# Covers:
#   (1) funnel table renders (header + fixture run row) against a full fixture state-dir.
#   (2) FALSE-ZERO RULE: a fixture PR with 0 GitHub review rounds but 3 consecutive
#       <=6-line drain-cycle commits on its (true-merge) PR branch is classified NOT clean.
#   (3) missing postmortem file => labeled insufficient_data present, exit 0.
#   (4) --state-dir pointing at a NONEXISTENT dir => graceful labeled output, exit 0.
#   (5) --jsonl emits parseable JSON lines (jq empty passes; a type:"run" line exists).
#   (6) a STRING-typed usage FIELD in a token_ledger line degrades to 0 (per-field type
#       guard) — the file's session_end run still renders, numeric fields still counted.
#   (7) a file the runs-extraction jq CANNOT process (non-object "usage") produces a
#       LABELED Data-quality note ("log file <name> unparseable ...") and exit 0 — its
#       runs are omitted but never silently dropped.
#   (8) a 2-run log file's ledger sum is counted ONCE in the era total (no N-fold inflation).

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDER="$SCRIPT_DIR/build-loop-evidence.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT" 2>/dev/null' EXIT

if ! command -v jq >/dev/null 2>&1; then
  echo "test-build-loop-evidence: jq absent on this host — builder degrades to a labeled skeleton; skipping data assertions."
  echo "RESULT: 0 passed, 0 failed (jq absent, vacuous)"
  exit 0
fi

run_builder() {
  # Usage: run_builder [args...] → sets OUT and RC. Always via `bash` (never inline-sourced).
  OUT="$(bash "$BUILDER" "$@" 2>/dev/null)"; RC=$?
}

# ---------------------------------------------------------------------------- fixture A: full
# Temp git repo with a synthetic PR #7 merged via a TRUE merge commit whose branch carries
# one feature commit + 3 consecutive tiny (<=6 line) drain-cycle-style fix commits.
REPO="$ROOT/repo"
mkdir -p "$REPO"
(
  cd "$REPO" || exit 1
  git init -q
  git config user.email t@t
  git config user.name t
  printf 'line1\nline2\nline3\n' > a.txt
  git add a.txt && git commit -qm "init"
  git checkout -q -b topic
  printf 'a lot of feature content\n%s\n' "$(seq 1 20)" > feature.txt
  git add feature.txt && git commit -qm "feat: add widget feature"
  echo "tweak1" >> a.txt && git add a.txt && git commit -qm "fix(review): address claude-bot finding round 1"
  echo "tweak2" >> a.txt && git add a.txt && git commit -qm "fix(review): address claude-bot finding round 2"
  echo "tweak3" >> a.txt && git add a.txt && git commit -qm "fix(review): drain cycle nit round 3"
  git checkout -q - >/dev/null 2>&1 || git checkout -q master 2>/dev/null || git checkout -q main
  git merge -q --no-ff -m "Merge pull request #7 from acme/topic" topic
) >/dev/null 2>&1

SD_A="$REPO/.supervisor"
mkdir -p "$SD_A/logs" "$SD_A/postmortem" "$SD_A/heal-signal"
cat > "$SD_A/logs/fixture-session.jsonl" <<'EOF'
{"ts":"2026-07-05T10:00:00Z","event":"session_start","session_id":"fixture-session"}
{"ts":"2026-07-05T10:30:00Z","event":"token_ledger","session_id":"fixture-session","proxy":true,"token_proxy_kind":"transcript_bytes","token_proxy_transcript_bytes":120000}
{"ts":"2026-07-05T11:00:00Z","event":"session_end","task_id":"fixture-run","status":"completed","branch":"feature/widget","pr_url":"https://github.com/acme/widgets/pull/7","heal_decision":"PASS","heal_iterations":1,"rubric_score":"5/5","plugin_version":"15.4.0"}
not-json-garbage-line-must-be-skipped
EOF
# GitHub review rounds = 0 for PR #7 — the false-zero case rests on the drain-cycle commits.
cat > "$SD_A/postmortem/results.jsonl" <<'EOF'
{"schema_version":1,"ts":"2026-07-05T12:00:00Z","repo":"acme/widgets","number":7,"review_rounds":0,"categories":[],"self_heal_misses":0,"changed_paths":["a.txt"],"summary":"fixture"}
EOF
cat > "$SD_A/heal-signal/results.jsonl" <<'EOF'
{"schema_version":1,"recorded_at":"2026-07-05T13:00:00Z","repos":["widgets"],"n":5,"tp":1,"fp":0,"fn":2,"tn":2,"recall_pct":33,"false_positive_pct":0,"coverage_pct":50}
EOF

# ============================================================================
echo "== (1) funnel table renders against the full fixture =="
run_builder --state-dir "$SD_A"
if [ "$RC" -eq 0 ] \
   && printf '%s\n' "$OUT" | grep -Fq "| run | version | landed | clean | durable | cheap |" \
   && printf '%s\n' "$OUT" | grep -Fq "fixture-run"; then
  ok "funnel table header + fixture run row rendered (rc=0)"
else
  no "funnel table did not render (rc=$RC)"
fi
if printf '%s\n' "$OUT" | grep -Fq "## Data quality"; then
  ok "Data quality section present"
else
  no "Data quality section missing"
fi

# ============================================================================
echo "== (2) FALSE-ZERO RULE: 0 review rounds + 3 drain-cycle commits => NOT clean =="
row="$(printf '%s\n' "$OUT" | grep -F "| fixture-run |" | head -1)"
if printf '%s\n' "$row" | grep -Fq "drain_cycle_commits" \
   && printf '%s\n' "$row" | grep -Eq '\| no \([^)]*drain_cycle_commits[^)]*\) \|'; then
  ok "fixture PR classified NOT clean via drain_cycle_commits despite 0 GitHub rounds"
else
  no "false-zero rule failed — row: $row"
fi
if printf '%s\n' "$row" | grep -Fq "| yes |"; then
  ok "fixture PR classified landed=yes (merge commit found)"
else
  no "fixture PR not detected as landed — row: $row"
fi

# ============================================================================
echo "== (3) missing postmortem file => insufficient_data label, exit 0 =="
# Fixture B: logs only, parent deliberately NOT a git repo, no postmortem/ at all.
SD_B="$ROOT/plain/.supervisor"
mkdir -p "$SD_B/logs"
cat > "$SD_B/logs/solo.jsonl" <<'EOF'
{"ts":"2026-06-10T11:00:00Z","event":"session_end","task_id":"solo-run","status":"completed","pr_url":"https://github.com/acme/widgets/pull/9","heal_decision":"PASS","heal_iterations":0,"plugin_version":"14.30.0"}
EOF
run_builder --state-dir "$SD_B"
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -Fq "insufficient_data"; then
  ok "missing postmortem => insufficient_data label present, rc=0"
else
  no "missing postmortem handling wrong (rc=$RC)"
fi
if printf '%s\n' "$OUT" | grep -q "postmortem/results.jsonl absent"; then
  ok "Data quality names the absent postmortem file"
else
  no "Data quality does not mention absent postmortem"
fi

# ============================================================================
echo "== (4) --state-dir at a NONEXISTENT dir => graceful labeled output, exit 0 =="
run_builder --state-dir "$ROOT/does/not/exist"
if [ "$RC" -eq 0 ] \
   && printf '%s\n' "$OUT" | grep -Fq "insufficient_data" \
   && printf '%s\n' "$OUT" | grep -Fq "state dir not found"; then
  ok "nonexistent state dir => labeled output, rc=0"
else
  no "nonexistent state dir not handled gracefully (rc=$RC)"
fi

# ============================================================================
echo "== (5) --jsonl emits parseable JSON lines =="
run_builder --state-dir "$SD_A" --jsonl
if [ "$RC" -eq 0 ] && [ -n "$OUT" ] && printf '%s\n' "$OUT" | jq empty >/dev/null 2>&1; then
  ok "--jsonl output parses (jq empty, rc=0)"
else
  no "--jsonl output does not parse (rc=$RC)"
fi
if printf '%s\n' "$OUT" | jq -r 'select(.type=="run") | .run' 2>/dev/null | grep -Fq "fixture-run"; then
  ok "--jsonl carries a type:run line for the fixture run"
else
  no "--jsonl missing the type:run line"
fi
if printf '%s\n' "$OUT" | jq -r 'select(.type=="run") | .clean' 2>/dev/null | grep -Fq "drain_cycle_commits"; then
  ok "--jsonl run line preserves the false-zero NOT-clean classification"
else
  no "--jsonl run line lost the NOT-clean classification"
fi

# ============================================================================
echo "== (6) string-typed usage FIELD => per-field guard, run still renders =="
# Fixture D: one ledger line whose input_tokens is a STRING — must degrade that field to 0,
# keep the numeric output_tokens (500), and still render the file's session_end run.
SD_D="$ROOT/strfield/.supervisor"
mkdir -p "$SD_D/logs"
cat > "$SD_D/logs/strfield.jsonl" <<'EOF'
{"ts":"2026-07-06T10:00:00Z","event":"token_ledger","session_id":"strfield","proxy":false,"usage":{"input_tokens":"not-a-number","output_tokens":500}}
{"ts":"2026-07-06T11:00:00Z","event":"session_end","task_id":"strfield-run","status":"completed","pr_url":"https://github.com/acme/widgets/pull/21","heal_iterations":0,"plugin_version":"15.4.0"}
EOF
run_builder --state-dir "$SD_D"
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -Fq "strfield-run"; then
  ok "session_end run renders despite string-typed usage field (rc=0)"
else
  no "string-typed usage field aborted the file's runs (rc=$RC)"
fi
if printf '%s\n' "$OUT" | grep -Fq "real:500t"; then
  ok "numeric usage field still counted (real:500t), string field degraded to 0"
else
  no "expected real:500t (string field->0, numeric field kept) not found"
fi

# ============================================================================
echo "== (7) pipeline-unparseable file => LABELED DQ note, runs omitted, exit 0 =="
# Fixture E: "usage" is a non-object STRING — indexing it aborts the extraction jq for the
# whole file. The abort must be LABELED under Data quality (never silent), rc still 0.
SD_E="$ROOT/badusage/.supervisor"
mkdir -p "$SD_E/logs"
cat > "$SD_E/logs/bad-usage.jsonl" <<'EOF'
{"ts":"2026-07-06T10:00:00Z","event":"token_ledger","session_id":"badusage","proxy":false,"usage":"corrupt-string-not-an-object"}
{"ts":"2026-07-06T11:00:00Z","event":"session_end","task_id":"ghost-run","status":"completed","pr_url":"https://github.com/acme/widgets/pull/22","heal_iterations":0,"plugin_version":"15.4.0"}
EOF
run_builder --state-dir "$SD_E"
if [ "$RC" -eq 0 ] \
   && printf '%s\n' "$OUT" | grep -Fq "log file bad-usage.jsonl unparseable"; then
  ok "abort is LABELED (log file bad-usage.jsonl unparseable ... runs omitted), rc=0"
else
  no "unparseable file not labeled in Data quality (rc=$RC)"
fi
if ! printf '%s\n' "$OUT" | grep -Fq "ghost-run"; then
  ok "unparseable file's runs omitted from the funnel (ghost-run absent)"
else
  no "ghost-run rendered despite the extraction abort"
fi

# ============================================================================
echo "== (8) 2-run file's ledger sum counted ONCE in era total =="
# Fixture F: ONE log file, ONE proxy ledger line (50000 bytes), TWO session_end runs
# (distinct PRs, same era). Era advisory_tokens must be proxy:50000B — NOT 100000.
SD_F="$ROOT/tworuns/.supervisor"
mkdir -p "$SD_F/logs"
cat > "$SD_F/logs/two-runs.jsonl" <<'EOF'
{"ts":"2026-07-06T09:00:00Z","event":"token_ledger","session_id":"tworuns","proxy":true,"token_proxy_kind":"transcript_bytes","token_proxy_transcript_bytes":50000}
{"ts":"2026-07-06T10:00:00Z","event":"session_end","task_id":"run-one","status":"completed","pr_url":"https://github.com/acme/widgets/pull/31","heal_iterations":0,"plugin_version":"15.4.0"}
{"ts":"2026-07-06T11:00:00Z","event":"session_end","task_id":"run-two","status":"completed","pr_url":"https://github.com/acme/widgets/pull/32","heal_iterations":0,"plugin_version":"15.4.0"}
EOF
run_builder --state-dir "$SD_F"
if [ "$RC" -eq 0 ] \
   && printf '%s\n' "$OUT" | grep -Fq "run-one" \
   && printf '%s\n' "$OUT" | grep -Fq "run-two"; then
  ok "both runs of the 2-run file render (rc=0)"
else
  no "2-run fixture rows missing (rc=$RC)"
fi
if printf '%s\n' "$OUT" | grep -Fq "proxy:50000B" \
   && ! printf '%s\n' "$OUT" | grep -Fq "proxy:100000B"; then
  ok "era total counts the file's 50000B exactly once (no 2x inflation)"
else
  no "era token total inflated or missing — expected proxy:50000B, not proxy:100000B"
fi
if printf '%s\n' "$OUT" | grep -Fq "era totals count each file's sum exactly ONCE"; then
  ok "Data quality note explains the once-per-file attribution"
else
  no "once-per-file attribution note missing from Data quality"
fi

# ============================================================================
echo ""
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
