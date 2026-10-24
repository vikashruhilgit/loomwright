#!/usr/bin/env bash
# test-telemetry-threads.sh — #508: telemetry parses with the shared parser, skips
# validator-rejected stops, counts from parsed findings, and posts ONE THREAD PER
# REVIEW TARGET (first non-pass round opens an issue, later rounds comment, a
# success closes it with `telemetry:healed-in-loop`), keyed in a user-scope map.
#
# WHAT IT PROVES (each against the real send-telemetry-core.sh):
#   T1  a stop the sibling validator rejects is skipped; its accepted retry posts
#       once (dry-run AND live with a recording gh stub)
#   T2  counts come from the PARSED result: a drift-only FAIL counts its drift
#       finding; a mixed FAIL counts HIGH/MEDIUM/LOW and new/nit separately; with
#       the validator unavailable, a FAIL with no parsed finding is recorded
#       with zero counts and an explicit line (no fake count)
#   T3  round 1 opens, round 2 comments, the PASS comments + labels + closes; the
#       next PASS is interest-skipped; the next FAIL opens a NEW thread
#   T4  a detached drain (LOOMWRIGHT_PR_HEAD_REF) shares the branch's thread; two
#       sessions on the default branch do not share one
#   T5  two concurrent posters on one target produce ONE issue (+ one comment)
#   T6  an unreadable map posts nothing (exit 1, local log line, map untouched)
#   T7  privacy: no repo slug, branch, PR, path, task id or thread key in any
#       posted title / body / comment
#   T8  mutation controls: removing the validator gate, the parsed counts, the
#       map lock or the unreadable-map refusal, or counting severities only at
#       BLOCKING/HIGH (the mixed fixture), each turns a case above RED
#   T9  /telemetry test (commands/telemetry.md) parses the fields the core's
#       dry-run prints and branches open -> comment -> close -> skip, in order
#
# HERMETIC: every run uses an isolated $HOME (user-scope egress.json + thread map)
# and a scratch git repo as $PWD; `gh` is a recording stub on PATH — no network.
# bash-3.2-safe.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE="$SCRIPT_DIR/send-telemetry-core.sh"
unset LOOMWRIGHT_TELEMETRY_REPO LOOMWRIGHT_PR_HEAD_REF 2>/dev/null || true

PASS_COUNT=0
FAIL_COUNT=0
ok()  { echo "PASS  $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
bad() { echo "FAIL  $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
assert_eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1  expected=$2  actual=$3"; fi; }
assert_match() { if grep -qF -- "$2" <<<"$3"; then ok "$1"; else bad "$1  needle='$2' not found"; fi; }
assert_not_match() { if ! grep -qF -- "$2" <<<"$3"; then ok "$1"; else bad "$1  unexpected '$2' present"; fi; }
would_exit() { sed -n 's/^WOULD_EXIT=//p' <<<"$1" | tail -1; }

SANDBOX="$(mktemp -d 2>/dev/null)" || { echo "FATAL  mktemp failed" >&2; exit 1; }
trap 'rm -rf "$SANDBOX" 2>/dev/null || true' EXIT INT TERM

SLUG="acme-private/hub"
BRANCH="feature/acme-secret-branch"
SB_HOME="$SANDBOX/home"
LW_USER_DIR="$SB_HOME/.claude/loomwright"   # user scope: egress.json + the thread map
MAP="$LW_USER_DIR/telemetry-threads.json"
REPO="$SANDBOX/repo"
FIX="$SANDBOX/fixtures"
STUB_DIR="$SANDBOX/bin"
GH_LOG="$SANDBOX/gh-calls.log"
GH_BODIES="$SANDBOX/gh-bodies"
mkdir -p "$LW_USER_DIR" "$REPO" "$FIX" "$STUB_DIR" "$GH_BODIES"
printf '{"schema_version":1,"repos":{"%s":{"telemetry":"always_allow","telemetry_repo":"example/sink"}}}' \
  "$SLUG" > "$LW_USER_DIR/egress.json"
git -C "$REPO" init -q
git -C "$REPO" remote add origin "https://github.com/$SLUG.git"
git -C "$REPO" -c user.email=t@example.invalid -c user.name=t commit -q --allow-empty -m init
git -C "$REPO" branch -M main
git -C "$REPO" checkout -q -b "$BRANCH"

# ---- Recording gh stub ---------------------------------------------------------
# Logs "<parent pid>\t<args>" per call, keeps every title/body it is handed, and
# prints an issue URL for `issue create` / `issue comment`. GH_BARRIER=1 makes
# `issue create` wait (bounded) until a SECOND poster process has called gh —
# with the map lock held that never happens, so the wait times out and one poster
# runs alone; without the lock both pass the barrier and both create.
cat > "$STUB_DIR/gh" <<'STUB'
#!/usr/bin/env bash
log="${GH_LOG:?}"; bodies="${GH_BODIES:?}"
printf '%s\t%s\n' "$PPID" "$*" >> "$log"
op="$1 ${2:-}"
body=""; title=""; prev=""
for a in "$@"; do
  [ "$prev" = "--body-file" ] && body="$a"
  [ "$prev" = "--title" ] && title="$a"
  prev="$a"
done
n="$(ls "$bodies" | wc -l | tr -d ' ')"
[ -n "$body" ] && cp "$body" "$bodies/$n-$(printf '%s' "$op" | tr ' ' '_').md"
[ -n "$title" ] && printf '%s\n' "$title" > "$bodies/$n-title.txt"
case "$op" in
  "issue create")
    if [ "${GH_BARRIER:-0}" = "1" ]; then
      end=$(( $(date +%s) + 8 ))
      while [ "$(cut -f1 "$log" | sort -u | wc -l | tr -d ' ')" -lt 2 ] && [ "$(date +%s)" -lt "$end" ]; do
        sleep 0.1
      done
    fi
    c="$(grep -c "	issue create" "$log")"
    printf 'https://github.com/example/sink/issues/%s\n' "$((100 + c))" ;;
  "issue comment") printf 'https://github.com/example/sink/issues/%s#issuecomment-1\n' "$3" ;;
  "issue close") [ "${GH_FAIL_CLOSE:-0}" = "1" ] && exit 1 ;;
esac
exit 0
STUB
chmod +x "$STUB_DIR/gh"

gh_reset() { : > "$GH_LOG"; rm -f "$GH_BODIES"/*; }
gh_count() { grep -c "	$1" "$GH_LOG" 2>/dev/null | tr -d ' ' || true; }

# run_core <cwd> <fixture> [--dry-run]  (env passes through: LOOMWRIGHT_PR_HEAD_REF, GH_*)
run_core() {
  local cwd="$1" fixture="$2"; shift 2
  ( cd "$cwd" && HOME="$SB_HOME" PATH="$STUB_DIR:$PATH" GH_LOG="$GH_LOG" GH_BODIES="$GH_BODIES" \
      bash "${CORE_UNDER_TEST:-$CORE}" "$@" < "$fixture" 2>&1 )
}

# ---- Fixtures ------------------------------------------------------------------
# Every finding is full of project content (paths, repo URL, PR, branch, task id)
# that must never reach a post.
python3 - "$FIX" <<'PY'
import json, sys
d = sys.argv[1]
def review(decision, issue_lines, summary="review"):
    return "\n".join(["Review done.", "", "```yaml", "CODE_REVIEW_RESULT:",
        "  schema_version: 3", "  review_mode: diff_review", "  audit_focus: []",
        "  trigger_paths_detected: []", "  scope_expanded: []",
        "  files_checked: [src/billing/charge_card.py]",
        "  decision: %s" % decision, "  issues:"] + issue_lines +
        ["  summary: %s" % summary, "```"])
NEW_HIGH = ["    - severity: HIGH", "      category: new", "      file: src/billing/charge_card.py",
            "      line: 214",
            "      description: charge_card() skips the idempotency key, see https://github.com/acme-private/hub/pull/88 on feature/acme-secret-branch task acme-task-77"]
FOLDED = ["    - severity: HIGH", "      category: new", "      file: src/billing/charge_card.py",
          "      description: >-", "        charge_card() skips the idempotency key", ""]
DRIFT = ["    - severity: HIGH", "      category: drift", "      drift_kind: mirrored_prompt",
         "      file: docs/acme.md", "      description: the acme mirror says the watcher is armed"]
MED = ["    - severity: MEDIUM", "      category: nit", "      file: src/billing/x.py",
       "      description: rename acme_helper"]
def write(name, text, sid="sess-1", aid="agent-1"):
    p = {"session_id": sid, "agent_id": aid, "agent_type": "loomwright:loomwright:code-reviewer",
         "result_block": text}
    json.dump(p, open("%s/%s.json" % (d, name), "w"))
write("rejected", review("FAIL", FOLDED), aid="agent-r1")
# Parseable but rejected on a RULE (v3 rule k: FAIL needs a new/drift
# BLOCKING|HIGH issue) — only the validator, not the parser, catches it.
write("rejected-rule", review("FAIL", MED), aid="agent-r1")
write("retry", review("FAIL", NEW_HIGH), aid="agent-r1")
write("drift", review("FAIL", DRIFT), aid="agent-d1")
# Mixed severities and categories, neutral placeholder text only: pins the
# MEDIUM/LOW severity split and the non-drift category counts (af/15).
def finding(sev, cat):
    return ["    - severity: %s" % sev, "      category: %s" % cat,
            "      file: placeholder", "      description: placeholder finding"]
write("mixed", review("FAIL", finding("HIGH", "new") + finding("MEDIUM", "new") +
                      finding("LOW", "new") + finding("LOW", "nit")), aid="agent-mx")
write("empty-fail", review("FAIL", ["    []"]), aid="agent-e1")
write("round1", review("FAIL", NEW_HIGH), aid="agent-1")
write("round2", review("FAIL", NEW_HIGH + MED), aid="agent-2")
write("pass3", review("PASS", MED), aid="agent-3")
write("pass4", review("PASS", MED), aid="agent-4")
write("round5", review("FAIL", NEW_HIGH), aid="agent-5")
write("main-a", review("FAIL", NEW_HIGH), sid="sess-main-a", aid="agent-ma")
write("main-b", review("FAIL", NEW_HIGH), sid="sess-main-b", aid="agent-mb")
write("drain2", review("FAIL", NEW_HIGH), sid="sess-drain", aid="agent-dr")
write("conc-a", review("FAIL", NEW_HIGH), sid="sess-ca", aid="agent-ca")
write("conc-b", review("FAIL", NEW_HIGH), sid="sess-cb", aid="agent-cb")
PY
# The empty-issues fixture needs a flow `[]`, not a block item.
python3 - "$FIX/empty-fail.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))
p["result_block"] = p["result_block"].replace("  issues:\n    []", "  issues: []")
json.dump(p, open(sys.argv[1], "w"))
PY

map_field() { # <python expr over the single thread dict t, or the doc d>
  python3 -c '
import json, sys
d = json.load(open(sys.argv[1])); ts = list(d["threads"].values())
t = ts[0] if len(ts) == 1 else None
print(eval(sys.argv[2]))' "$MAP" "$1" 2>/dev/null
}

echo "==== test-telemetry-threads ===="

# ---- T1 — validator-rejected stop is skipped; the retry posts once ----------
echo ""
echo "==== T1: a rejected attempt is skipped, its retry posts once ===="
rm -f "$MAP"; gh_reset
out="$(run_core "$REPO" "$FIX/rejected.json" --dry-run)"
assert_eq "T1_rejected_dry_would_exit=5" "5" "$(would_exit "$out")"
assert_match "T1_rejected_reason" "filter_skipped reason=validator_rejected schema=CODE_REVIEW_RESULT" "$out"
assert_not_match "T1_rejected_no_folded_indicator" "] >-" "$out"
out="$(run_core "$REPO" "$FIX/rejected-rule.json" --dry-run)"
assert_eq "T1_rule_rejected_dry_would_exit=5" "5" "$(would_exit "$out")"
assert_match "T1_rule_rejected_reason" "filter_skipped reason=validator_rejected" "$out"
out="$(run_core "$REPO" "$FIX/rejected.json")"; rc=$?
assert_eq "T1_rejected_live_exit=5" "5" "$rc"
out="$(run_core "$REPO" "$FIX/rejected-rule.json")"; rc=$?
assert_eq "T1_rule_rejected_live_exit=5" "5" "$rc"
assert_eq "T1_rejected_live_no_gh" "0" "$(gh_count 'issue create')"
out="$(run_core "$REPO" "$FIX/retry.json")"; rc=$?
assert_eq "T1_retry_live_exit=0" "0" "$rc"
assert_eq "T1_one_issue_for_the_pair" "1" "$(gh_count 'issue create')"
assert_eq "T1_no_comment_for_the_pair" "0" "$(gh_count 'issue comment')"
# A second delivery of the SAME accepted stop (same agent) is a dedup, not a round.
out="$(run_core "$REPO" "$FIX/retry.json")"; rc=$?
assert_eq "T1_same_stop_twice_exit=5" "5" "$rc"
assert_match "T1_same_stop_twice_dedup" "dedup_hit" "$out"
assert_eq "T1_still_one_issue" "1" "$(gh_count 'issue create')"

# ---- T2 — counts from the parsed result ---------------------------------------
echo ""
echo "==== T2: counts come from the parsed result (drift counted) ===="
rm -f "$MAP"
out="$(run_core "$REPO" "$FIX/drift.json" --dry-run)"
assert_eq "T2_drift_would_send" "0" "$(would_exit "$out")"
assert_match "T2_drift_high_counted" '"high": 1' "$out"
assert_match "T2_drift_category_counted" '"drift": 1' "$out"
assert_match "T2_drift_line_rendered" "[HIGH] drift finding (mirrored_prompt)" "$out"
assert_not_match "T2_drift_no_description" "watcher is armed" "$out"
# Mixed severities: every severity and category is counted, not just BLOCKING/HIGH.
out="$(run_core "$REPO" "$FIX/mixed.json" --dry-run)"
assert_eq "T2_mixed_would_send" "0" "$(would_exit "$out")"
assert_match "T2_mixed_high_counted" '"high": 1' "$out"
assert_match "T2_mixed_medium_counted" '"medium": 1' "$out"
assert_match "T2_mixed_low_counted" '"low": 2' "$out"
assert_match "T2_mixed_new_category_counted" '"new": 3' "$out"
assert_match "T2_mixed_nit_category_counted" '"nit": 1' "$out"
# Validator unavailable (a copy of the core with no sibling validator): a FAIL
# with zero parsed findings is still recorded — truthfully, zero counts.
NOVAL="$SANDBOX/core-noval"
mkdir -p "$NOVAL"
cp "$CORE" "$SCRIPT_DIR/resolve-egress-config.sh" "$SCRIPT_DIR/result_block_parser.py" "$NOVAL/"
out="$(CORE_UNDER_TEST="$NOVAL/send-telemetry-core.sh" run_core "$REPO" "$FIX/empty-fail.json" --dry-run)"
assert_eq "T2_empty_fail_recorded" "0" "$(would_exit "$out")"
assert_match "T2_empty_fail_validator_unavailable_logged" "validator_unavailable schema=CODE_REVIEW_RESULT" "$out"
assert_match "T2_empty_fail_explicit_line" "no BLOCKING/HIGH new or drift finding was parsed" "$out"
assert_match "T2_empty_fail_zero_high" '"high": 0' "$out"
assert_match "T2_empty_fail_zero_blocking" '"blocking": 0' "$out"
# ... and the real core (validator present) rejects that same block (rule l).
out="$(run_core "$REPO" "$FIX/empty-fail.json" --dry-run)"
assert_eq "T2_empty_fail_rejected_with_validator" "5" "$(would_exit "$out")"

# ---- T3 — one thread: open, comment, close ----------------------------------
echo ""
echo "==== T3: round 1 opens, round 2 comments, PASS closes + labels ===="
rm -f "$MAP"; gh_reset
out="$(run_core "$REPO" "$FIX/round1.json")"; rc=$?
assert_eq "T3_round1_exit=0" "0" "$rc"
assert_eq "T3_round1_creates" "1" "$(gh_count 'issue create')"
assert_eq "T3_map_open" "open" "$(map_field 't["state"]')"
assert_eq "T3_map_issue" "101" "$(map_field 't["issue"]')"
out="$(run_core "$REPO" "$FIX/round2.json" --dry-run)"
assert_match "T3_round2_dry_comment" "THREAD_ACTION=comment" "$out"
assert_match "T3_round2_dry_round" "THREAD_ROUND=2" "$out"
out="$(run_core "$REPO" "$FIX/round2.json")"; rc=$?
assert_eq "T3_round2_exit=0" "0" "$rc"
assert_eq "T3_round2_no_new_issue" "1" "$(gh_count 'issue create')"
assert_eq "T3_round2_comments" "1" "$(gh_count 'issue comment 101')"
out="$(run_core "$REPO" "$FIX/pass3.json" --dry-run)"
assert_match "T3_pass_dry_close" "THREAD_ACTION=close" "$out"
assert_match "T3_pass_dry_label" "telemetry:healed-in-loop" "$out"
out="$(run_core "$REPO" "$FIX/pass3.json")"; rc=$?
assert_eq "T3_pass_exit=0" "0" "$rc"
assert_eq "T3_pass_closing_comment" "2" "$(gh_count 'issue comment 101')"
assert_eq "T3_pass_label_created" "1" "$(gh_count 'label create telemetry:healed-in-loop')"
assert_eq "T3_pass_label_added" "1" "$(gh_count 'issue edit 101 --repo example/sink --add-label telemetry:healed-in-loop')"
assert_eq "T3_pass_issue_closed" "1" "$(gh_count 'issue close 101')"
assert_eq "T3_map_closed" "closed" "$(map_field 't["state"]')"
assert_eq "T3_map_rounds" "3" "$(map_field 't["rounds"]')"
CLOSE_BODY="$(cat "$GH_BODIES"/*issue_comment.md 2>/dev/null | tail -n 60)"
assert_match "T3_close_rounds" "Rounds recorded: 3" "$CLOSE_BODY"
assert_match "T3_close_series" "Findings per round (all severities): 1, 2, 1" "$CLOSE_BODY"
assert_match "T3_close_verdict" "Final verdict: pass" "$CLOSE_BODY"
assert_match "T3_close_outcomes_gap_stated" "Per-finding outcomes (fixed / dismissed / deferred): not recorded" "$CLOSE_BODY"
# Order of the close: comment, then label, then close.
order="$(grep -nE '	issue (comment|edit|close) 101' "$GH_LOG" | tail -3 | cut -f2 | cut -d' ' -f2 | tr '\n' ' ')"
assert_eq "T3_close_order" "comment edit close " "$order"
out="$(run_core "$REPO" "$FIX/pass4.json")"; rc=$?
assert_eq "T3_later_pass_interest_skipped" "5" "$rc"
assert_match "T3_later_pass_reason" "filter_skipped reason=interest_filter" "$out"
out="$(run_core "$REPO" "$FIX/round5.json")"; rc=$?
assert_eq "T3_new_loop_exit=0" "0" "$rc"
assert_eq "T3_new_loop_new_issue" "2" "$(gh_count 'issue create')"
# A failed close keeps the thread open so a later pass retries it.
rm -f "$MAP"; gh_reset
run_core "$REPO" "$FIX/round1.json" >/dev/null
out="$(GH_FAIL_CLOSE=1 run_core "$REPO" "$FIX/pass3.json")"; rc=$?
assert_eq "T3_close_failure_exit=1" "1" "$rc"
assert_eq "T3_close_failure_thread_stays_open" "open" "$(map_field 't["state"]')"
out="$(run_core "$REPO" "$FIX/pass4.json")"; rc=$?
assert_eq "T3_close_retried_by_next_pass" "0" "$rc"
assert_eq "T3_close_retry_closed" "closed" "$(map_field 't["state"]')"

# ---- T4 — the review target ---------------------------------------------------
echo ""
echo "==== T4: a detached drain shares the branch thread; default-branch sessions do not ===="
rm -f "$MAP"; gh_reset
run_core "$REPO" "$FIX/round1.json" >/dev/null
DRAIN_WT="$SANDBOX/drain-wt"
git -C "$REPO" worktree add -q --detach "$DRAIN_WT" HEAD
out="$(LOOMWRIGHT_PR_HEAD_REF="$BRANCH" run_core "$DRAIN_WT" "$FIX/drain2.json")"; rc=$?
assert_eq "T4_drain_exit=0" "0" "$rc"
assert_eq "T4_drain_comments_on_branch_thread" "1" "$(gh_count 'issue comment 101')"
assert_eq "T4_drain_no_second_issue" "1" "$(gh_count 'issue create')"
git -C "$REPO" worktree remove --force "$DRAIN_WT"
rm -f "$MAP"; gh_reset
git -C "$REPO" checkout -q main
run_core "$REPO" "$FIX/main-a.json" >/dev/null
run_core "$REPO" "$FIX/main-b.json" >/dev/null
assert_eq "T4_default_branch_sessions_separate" "2" "$(gh_count 'issue create')"
git -C "$REPO" checkout -q "$BRANCH"

# ---- T5 — two concurrent posters on one target ------------------------------
echo ""
echo "==== T5: two concurrent posters on one target -> one issue ===="
run_pair() { # <core> — both posters at once; prints "<creates> <comments>"
  rm -f "$MAP"; gh_reset
  ( CORE_UNDER_TEST="$1" GH_BARRIER=1 run_core "$REPO" "$FIX/conc-a.json" >/dev/null ) &
  local pa=$!
  ( CORE_UNDER_TEST="$1" GH_BARRIER=1 run_core "$REPO" "$FIX/conc-b.json" >/dev/null ) &
  local pb=$!
  wait "$pa"; wait "$pb"
  printf '%s %s\n' "$(gh_count 'issue create')" "$(gh_count 'issue comment')"
}
pair="$(run_pair "$CORE")"
assert_eq "T5_concurrent_one_issue_one_comment" "1 1" "$pair"
assert_eq "T5_map_rounds" "2" "$(map_field 't["rounds"]')"
assert_eq "T5_map_one_thread" "1" "$(map_field 'len(d["threads"])')"

# ---- T6 — unreadable map posts nothing --------------------------------------
echo ""
echo "==== T6: an unreadable map posts nothing ===="
for kind in garbage wrong-shape directory; do
  rm -rf "$MAP"; gh_reset
  case "$kind" in
    garbage)     printf '{not json' > "$MAP" ;;
    wrong-shape) printf '{"schema_version": 9, "threads": []}' > "$MAP" ;;
    directory)   mkdir -p "$MAP" ;;
  esac
  before="$(ls -ld "$MAP" | awk '{print $5}')$(cat "$MAP" 2>/dev/null)"
  out="$(run_core "$REPO" "$FIX/round1.json")"; rc=$?
  assert_eq "T6_${kind}_exit=1" "1" "$rc"
  assert_match "T6_${kind}_logged" "thread_map_unreadable" "$out"
  assert_eq "T6_${kind}_no_issue" "0" "$(gh_count 'issue create')"
  assert_eq "T6_${kind}_no_comment" "0" "$(gh_count 'issue comment')"
  after="$(ls -ld "$MAP" | awk '{print $5}')$(cat "$MAP" 2>/dev/null)"
  assert_eq "T6_${kind}_map_untouched" "$before" "$after"
  out="$(run_core "$REPO" "$FIX/round1.json" --dry-run)"
  assert_eq "T6_${kind}_dry_would_exit=1" "1" "$(would_exit "$out")"
done
rm -rf "$MAP"

# ---- T7 — privacy: nothing project-specific in any post -----------------------
echo ""
echo "==== T7: privacy — no repo / branch / PR / path / task id / key in any post ===="
rm -f "$MAP"; gh_reset
run_core "$REPO" "$FIX/round1.json" >/dev/null
run_core "$REPO" "$FIX/round2.json" >/dev/null
run_core "$REPO" "$FIX/drift.json" >/dev/null
run_core "$REPO" "$FIX/pass3.json" >/dev/null
POSTED="$(cat "$GH_BODIES"/* 2>/dev/null)"
assert_match "T7_bodies_captured" "## Raw Data" "$POSTED"
KEY="$(python3 -c 'import json,sys; print(list(json.load(open(sys.argv[1]))["threads"])[0])' "$MAP")"
for tok in "$SLUG" acme hub "$BRANCH" feature/ pull/88 "src/billing" charge_card ".py" ":214" acme-task-77 \
           sess-1 agent-1 "$KEY" "$SANDBOX" /Users/ /home/; do
  assert_not_match "T7_no[$tok]" "$tok" "$POSTED"
done
# The map is the only place the key lives, and it holds no repo/branch text either.
MAPTXT="$(cat "$MAP")"
assert_not_match "T7_map_no_slug" "$SLUG" "$MAPTXT"
assert_not_match "T7_map_no_branch" "$BRANCH" "$MAPTXT"

# ---- T8 — mutation controls ---------------------------------------------------
echo ""
echo "==== T8: mutation controls ===="
# mutant <name> <sentinel> <replacement-file> — a core copy with the code between
# the sentinel markers replaced, beside copies of its helpers.
mutant() {
  local name="$1" mark="$2" repl="$3" dir="$SANDBOX/mutant-$1" f
  mkdir -p "$dir"
  for f in resolve-egress-config.sh result_block_parser.py result_nested_keys.py validate-code-review-result.py \
           validate-qa-result.py validate-supervisor-result.py; do cp "$SCRIPT_DIR/$f" "$dir/"; done
  awk -v b="# MUTATION_CONTROL_BEGIN: $mark" -v e="# MUTATION_CONTROL_END: $mark" -v r="$repl" '
    index($0, b) { print; while ((getline line < r) > 0) print line; skip = 1; next }
    index($0, e) { skip = 0 }
    !skip { print }' "$CORE" > "$dir/send-telemetry-core.sh"
  if grep -qF "# MUTATION_CONTROL_BEGIN: $mark" "$CORE"; then ok "T8_${name}_sentinel_present"; else bad "T8_${name}_sentinel_present"; fi
  printf '%s\n' "$dir/send-telemetry-core.sh"
}
# (a) no validator gate -> the rejected attempt posts again
printf 'verdict = "accepted"\n' > "$SANDBOX/repl-a"
M="$(mutant gate sibling-validator-verdict "$SANDBOX/repl-a" | tail -1)"
rm -f "$MAP"
out="$(CORE_UNDER_TEST="$M" run_core "$REPO" "$FIX/rejected-rule.json" --dry-run)"
assert_eq "T8_gate_mutant_posts_rejected_attempt" "0" "$(would_exit "$out")"
assert_not_match "T8_gate_mutant_not_rejected" "validator_rejected" "$out"
# (b) counts from `new` findings only (the old effective behaviour) -> drift reads zero
cat > "$SANDBOX/repl-b" <<'REPL'
if schema == "CODE_REVIEW_RESULT":
    for issue in review_issues:
        if issue["category"] == "new" and issue["severity"] in SEVERITIES:
            issues_by_severity[issue["severity"].lower()] += 1
else:
    issues_by_severity["unspecified"] = len(issues)
REPL
M="$(mutant counts count-from-parsed-findings "$SANDBOX/repl-b" | tail -1)"
out="$(CORE_UNDER_TEST="$M" run_core "$REPO" "$FIX/drift.json" --dry-run)"
assert_match "T8_counts_mutant_drift_reads_zero" '"high": 0' "$out"
# (e) severities counted only at BLOCKING/HIGH (the shape that counted rendered
# lines only) -> the mixed fixture's MEDIUM/LOW counts vanish
cat > "$SANDBOX/repl-e" <<'REPL'
if schema == "CODE_REVIEW_RESULT":
    issues_by_category = {"new": 0, "pre_existing": 0, "nit": 0, "drift": 0, "other": 0}
    for issue in review_issues:
        if issue["severity"] in ("BLOCKING", "HIGH"):
            issues_by_severity[issue["severity"].lower()] += 1
        cat = issue["category"] if issue["category"] in CATEGORIES else "other"
        issues_by_category[cat] += 1
else:
    issues_by_severity["unspecified"] = len(issues)
REPL
M="$(mutant severities count-from-parsed-findings "$SANDBOX/repl-e" | tail -1)"
out="$(CORE_UNDER_TEST="$M" run_core "$REPO" "$FIX/mixed.json" --dry-run)"
assert_eq "T8_severities_mutant_still_sends" "0" "$(would_exit "$out")"
assert_match "T8_severities_mutant_high_kept" '"high": 1' "$out"
assert_not_match "T8_severities_mutant_drops_medium" '"medium": 1' "$out"
assert_not_match "T8_severities_mutant_drops_low" '"low": 2' "$out"
# (c) no map lock -> two concurrent posters open two issues
printf 'pass\n' > "$SANDBOX/repl-c"
M="$(mutant lock thread-map-lock "$SANDBOX/repl-c" | tail -1)"
pair="$(run_pair "$M")"
assert_eq "T8_lock_mutant_two_issues" "2 0" "$pair"
# (d) unreadable map read as empty -> a duplicate issue is opened
cat > "$SANDBOX/repl-d" <<'REPL'
def load_map():
    try:
        with open(MAP_PATH, "r", encoding="utf-8") as fh:
            doc = json.load(fh)
        if isinstance(doc, dict) and isinstance(doc.get("threads"), dict):
            return doc
    except Exception:
        pass
    return {"schema_version": 1, "threads": {}}
REPL
M="$(mutant unreadable thread-map-unreadable-fails-safe "$SANDBOX/repl-d" | tail -1)"
rm -rf "$MAP"; gh_reset; printf '{not json' > "$MAP"
CORE_UNDER_TEST="$M" run_core "$REPO" "$FIX/round1.json" >/dev/null
assert_eq "T8_unreadable_mutant_opens_issue" "1" "$(gh_count 'issue create')"
rm -rf "$MAP"

# ---- T9 — /telemetry test reads the fields the core prints, in order ---------
echo ""
echo "==== T9: commands/telemetry.md 'test' steps match the core's dry-run output ===="
CMD="$SCRIPT_DIR/../commands/telemetry.md"
# cmd_contract <file> — 0 when step 3 parses THREAD_ACTION/THREAD_ROUND, step 4
# forbids every gh call, and step 5 branches open -> comment -> close -> Else.
cmd_contract() {
  awk '
    /^## If subcommand == `test`/ { inT = 1; next }
    inT && /^## / { inT = 0 }
    !inT { next }
    /^3\. Parse stdout/ { step = 3 } /^4\. / { step = 4 } /^5\. Print final/ { step = 5 }
    step == 3 && index($0, "`THREAD_ACTION=<open|comment|close>`") && index($0, "`THREAD_ROUND=<n>`") { s3 = 1 }
    step == 4 && index($0, "Do NOT** call `gh`") { s4 = 1 }
    step == 5 && index($0, "`THREAD_ACTION=open`")    { if (seq == "") seq = "o" }
    step == 5 && index($0, "`THREAD_ACTION=comment`") { if (seq == "o") seq = "oc" }
    step == 5 && index($0, "`THREAD_ACTION=close`")   { if (seq == "oc") seq = "occ" }
    step == 5 && index($0, "- Else:")                 { if (seq == "occ") seq = "occe" }
    END { exit !(s3 && s4 && seq == "occe") }' "$1"
}
if cmd_contract "$CMD"; then ok "T9_command_contract_holds"; else bad "T9_command_contract_holds"; fi
rm -f "$MAP"
out="$(run_core "$REPO" "$FIX/round1.json" --dry-run)"
assert_eq "T9_core_prints_THREAD_ACTION" "1" "$(grep -c '^THREAD_ACTION=open$' <<<"$out")"
assert_eq "T9_core_prints_THREAD_ROUND" "1" "$(grep -c '^THREAD_ROUND=1$' <<<"$out")"
# Mutants: a renamed field, and the Else branch moved before close, must fail.
sed 's/THREAD_ROUND=<n>/THREAD_NUM=<n>/' "$CMD" > "$SANDBOX/cmd-m1.md"
if cmd_contract "$SANDBOX/cmd-m1.md"; then bad "T9_mutant_renamed_field_caught"; else ok "T9_mutant_renamed_field_caught"; fi
awk '/THREAD_ACTION=close`/ { held = $0; next } { print } /^   - Else:/ && held { print held; held = "" }' "$CMD" > "$SANDBOX/cmd-m2.md"
if cmd_contract "$SANDBOX/cmd-m2.md"; then bad "T9_mutant_reordered_branch_caught"; else ok "T9_mutant_reordered_branch_caught"; fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo ""
echo "=========================================="
echo "RESULT  total=$TOTAL  passed=$PASS_COUNT  failed=$FAIL_COUNT"
echo "=========================================="
[ "$FAIL_COUNT" -eq 0 ]
