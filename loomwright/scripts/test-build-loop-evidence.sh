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
#   (9) durable=no path: a follow-up `fix:`-subject commit within 14 days touching the
#       SAME file as the landed PR => `no (follow-up fix ... touched same files <14d)`
#       plus the hot-file-sensitivity Data-quality note.
#  (10) squash-merge path: a PR landed as a single non-merge "(#N)" commit => landed=yes,
#       drain-cycle commit signal degraded with the LABELED "squash-merged PRs collapse
#       branch history" Data-quality note (clean falls back to fix_cycles/heal_iterations).
#  (11) landed edge paths: a pr_url with NO matching commit in history => no(not_in_history)
#       (durable "-"); a run with NO pr_url at all => insufficient_data(no_pr_url).
#  (12) era_of branches (via --jsonl): plugin_version 15.12.0 => post_orientation_memos;
#       version-less run with a parseable ts in a fallback window => date_fallback:-labeled
#       era bucket; no version AND no parseable ts => unknown bucket — each with its
#       labeled Data-quality note.

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
# Fixture G: second temp git repo exercising the CLASSIFICATION branches the published
# SPIKE verdicts rest on (durable=no, squash-merge landing, not-in-history). Commit dates
# are PINNED via GIT_COMMITTER_DATE so the durable 14-day window is deterministic forever:
#   - PR #11 lands via a TRUE merge commit at 2026-06-01; a follow-up `fix:`-subject commit
#     at 2026-06-03 (inside the window) touches the SAME file (b.txt) => durable=no.
#   - PR #12 lands SQUASH-style: a single non-merge commit "feat: add c widget (#12)"
#     touching only c.txt (no overlap with the follow-up fix) => durable=yes, and the
#     drain-cycle commit signal is unavailable (labeled under Data quality).
#   - PR #99 has NO landing commit in this repo's history at all.
REPO2="$ROOT/repo2"
mkdir -p "$REPO2"
(
  cd "$REPO2" || exit 1
  git init -q
  git config user.email t@t
  git config user.name t
  export GIT_AUTHOR_DATE="2026-06-01T10:00:00Z" GIT_COMMITTER_DATE="2026-06-01T10:00:00Z"
  printf 'b1\nb2\n' > b.txt
  git add b.txt && git commit -qm "init"
  git checkout -q -b topic11
  echo "feature eleven" >> b.txt && git add b.txt && git commit -qm "feat: widget eleven"
  git checkout -q - >/dev/null 2>&1 || git checkout -q master 2>/dev/null || git checkout -q main
  git merge -q --no-ff -m "Merge pull request #11 from acme/topic11" topic11
  echo "c" > c.txt && git add c.txt && git commit -qm "feat: add c widget (#12)"
  export GIT_AUTHOR_DATE="2026-06-03T10:00:00Z" GIT_COMMITTER_DATE="2026-06-03T10:00:00Z"
  echo "hotfix" >> b.txt && git add b.txt && git commit -qm "fix: hotpatch widget eleven regression"
) >/dev/null 2>&1

SD_G="$REPO2/.supervisor"
mkdir -p "$SD_G/logs" "$SD_G/postmortem"
cat > "$SD_G/logs/g.jsonl" <<'EOF'
{"ts":"2026-06-01T12:00:00Z","event":"session_end","task_id":"g-eleven","status":"completed","pr_url":"https://github.com/acme/widgets/pull/11","heal_iterations":0,"plugin_version":"15.4.0"}
{"ts":"2026-06-01T13:00:00Z","event":"session_end","task_id":"g-twelve","status":"completed","pr_url":"https://github.com/acme/widgets/pull/12","heal_iterations":0,"plugin_version":"15.4.0"}
{"ts":"2026-06-01T14:00:00Z","event":"session_end","task_id":"g-ghost","status":"completed","pr_url":"https://github.com/acme/widgets/pull/99","heal_iterations":0,"plugin_version":"15.4.0"}
EOF
cat > "$SD_G/postmortem/results.jsonl" <<'EOF'
{"schema_version":1,"ts":"2026-06-02T12:00:00Z","repo":"acme/widgets","number":11,"review_rounds":0,"categories":[],"changed_paths":["b.txt"],"summary":"fixture"}
{"schema_version":1,"ts":"2026-06-02T12:00:00Z","repo":"acme/widgets","number":12,"review_rounds":0,"categories":[],"changed_paths":["c.txt"],"summary":"fixture"}
EOF

echo "== (9) durable=no: follow-up fix commit <14d touching the same file =="
run_builder --state-dir "$SD_G"
row11="$(printf '%s\n' "$OUT" | grep -F "| g-eleven |" | head -1)"
if [ "$RC" -eq 0 ] \
   && printf '%s\n' "$row11" | grep -Fq "no (follow-up fix " \
   && printf '%s\n' "$row11" | grep -Fq "touched same files <14d)"; then
  ok "PR #11 durable=no (follow-up fix ... touched same files <14d), rc=0"
else
  no "durable=no branch not taken — row: $row11 (rc=$RC)"
fi
if printf '%s\n' "$OUT" | grep -Fq "durable is a file-overlap heuristic and is SENSITIVE to hot shared files"; then
  ok "hot-file-sensitivity dq_once note present alongside durable=no"
else
  no "hot-file-sensitivity Data-quality note missing"
fi

# ============================================================================
echo "== (10) squash-merge landing: landed=yes, drain-cycle signal labeled unavailable =="
row12="$(printf '%s\n' "$OUT" | grep -F "| g-twelve |" | head -1)"
if printf '%s\n' "$row12" | grep -Fq "| yes | yes | yes |"; then
  ok "squash-landed PR #12: landed=yes, clean=yes, durable=yes (no file overlap with the fix)"
else
  no "squash-merge row wrong — row: $row12"
fi
if printf '%s\n' "$OUT" | grep -Fq "squash-merged PRs collapse branch history — drain-cycle commit signal unavailable there (clean relies on fix_cycles/heal_iterations for those)"; then
  ok "squash drain-cycle degradation LABELED under Data quality (exact builder string)"
else
  no "squash-merge Data-quality note missing"
fi

# ============================================================================
echo "== (11) landed edges: not-in-history and no-pr_url =="
row99="$(printf '%s\n' "$OUT" | grep -F "| g-ghost |" | head -1)"
if printf '%s\n' "$row99" | grep -Fq "| no(not_in_history) |" \
   && printf '%s\n' "$row99" | grep -Fq "| - |"; then
  ok "PR #99 with no landing commit => landed=no(not_in_history), durable '-'"
else
  no "not-in-history branch wrong — row: $row99"
fi

# ============================================================================
# Fixture H: era_of branches — three version/date shapes, parent deliberately NOT a git
# repo (era bucketing is git-independent; these runs also carry NO pr_url, which doubles
# as the landed=insufficient_data(no_pr_url) edge assertion).
SD_H="$ROOT/eras/.supervisor"
mkdir -p "$SD_H/logs"
cat > "$SD_H/logs/era-a.jsonl" <<'EOF'
{"ts":"2026-07-20T10:00:00Z","event":"session_end","task_id":"era-post-memos","status":"completed","plugin_version":"15.12.0"}
EOF
cat > "$SD_H/logs/era-b.jsonl" <<'EOF'
{"ts":"2026-07-10T10:00:00Z","event":"session_end","task_id":"era-datefallback","status":"completed"}
EOF
cat > "$SD_H/logs/era-c.jsonl" <<'EOF'
{"event":"session_end","task_id":"era-unknown","status":"completed"}
EOF

echo "== (12) era_of branches: version bucket, date fallback, unknown =="
run_builder --state-dir "$SD_H" --jsonl
if [ "$RC" -eq 0 ] \
   && [ "$(printf '%s\n' "$OUT" | jq -r 'select(.type=="run" and .run=="era-post-memos") | .era' 2>/dev/null)" = "post_orientation_memos" ]; then
  ok "plugin_version 15.12.0 bucketed post_orientation_memos (rc=0)"
else
  no "15.12.0 era bucket wrong (rc=$RC)"
fi
if [ "$(printf '%s\n' "$OUT" | jq -r 'select(.type=="run" and .run=="era-datefallback") | .era' 2>/dev/null)" = "post_rules_seams" ] \
   && [ "$(printf '%s\n' "$OUT" | jq -r 'select(.type=="run" and .run=="era-datefallback") | .version' 2>/dev/null)" = "date_fallback:2026-07-10" ]; then
  ok "version-less run bucketed by ship-date fallback (post_rules_seams, date_fallback: label)"
else
  no "date-fallback era branch wrong"
fi
if printf '%s\n' "$OUT" | jq -r 'select(.type=="data_quality") | .notes[]' 2>/dev/null | grep -Fq "bucketed by ship-date fallback (labeled date_fallback)"; then
  ok "date-fallback dq_once note present"
else
  no "date-fallback Data-quality note missing"
fi
if [ "$(printf '%s\n' "$OUT" | jq -r 'select(.type=="run" and .run=="era-unknown") | .era' 2>/dev/null)" = "unknown" ] \
   && [ "$(printf '%s\n' "$OUT" | jq -r 'select(.type=="run" and .run=="era-unknown") | .version' 2>/dev/null)" = "unknown" ]; then
  ok "no-version no-parseable-ts run lands in the unknown bucket (version unknown)"
else
  no "unknown era branch wrong"
fi
if printf '%s\n' "$OUT" | jq -r 'select(.type=="data_quality") | .notes[]' 2>/dev/null | grep -Fq "lack BOTH plugin_version and a parseable ts — era bucket unknown"; then
  ok "unknown-era dq_once note present"
else
  no "unknown-era Data-quality note missing"
fi
if [ "$(printf '%s\n' "$OUT" | jq -r 'select(.type=="run" and .run=="era-post-memos") | .landed' 2>/dev/null)" = "insufficient_data(no_pr_url)" ]; then
  ok "run with NO pr_url => landed=insufficient_data(no_pr_url)"
else
  no "no-pr_url landed label wrong"
fi

# ============================================================================
echo ""
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
