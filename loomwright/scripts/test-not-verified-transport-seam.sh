#!/usr/bin/env bash
# test-not-verified-transport-seam.sh — static wiring test for the `not_verified` transport chain
# (harness-port/04): worker -> Context-Keeper's `record_worker_result` -> `state.md`'s `## Worker
# Results` -> the FINALIZE PR body's optional `## Not verified` section AND the done brief's own
# `## Not verified` section -> `verify-run.sh acs`'s `not_verified` key (covered separately, with
# real script fixtures, by test-verify-walkthrough.sh's (NV-*) arms).
#
# Every surface asserted here EXCEPT verify-run.sh is MARKDOWN — prompt text an agent executes — so
# there is nothing to run; a grep is the only thing that can hold the wiring. Modelled on
# test-deviations-advisory-seam.sh: pass/fail counters, ok()/no() DEFINED here (test-suite-helpers-
# defined.sh scans every suite), a "RESULT: N passed, M failed" tail, exit 1 on any failure, paths
# from $BASH_SOURCE so it runs from any CWD under ci.yml's `loomwright/scripts/test-*.sh` glob.
# bash 3.2 / BSD userland safe (no gawk-only `match($0, re, arr)`, no GNU-only sed/date flags).
#
# Asserts:
#   (a) agents/context-keeper.md's `record_worker_result` operation row's Key Input Fields carries
#       `not_verified` immediately after `deviations` (mirrors out_of_lane/deviations exactly).
#   (b) skills/state-management/SKILL.md's `## Worker Results` row template documents `not_verified`
#       as OMITTED ENTIRELY when n=0/absent (UNLIKE out_of_lane/deviations, which always show `[]`)
#       and present-as-a-count-plus-sub-list only when n>0 — the asymmetry the brief's AC calls out.
#   (c) agents/execute-manager.md's parallel-path `record_worker_result` Task call forwards
#       `not_verified` in its `result: {...}` payload, immediately after `deviations`.
#   (d) agents/supervisor.md's Single-Agent Path step 2 AND Sequential Path step both name
#       `not_verified` in the "including the worker's ... fields" sentence (the ACTUAL location of
#       this prose — see (e) for the accurate cross-reference the brief expected in
#       async-orchestration/SKILL.md instead).
#   (e) skills/async-orchestration/SKILL.md: the FINALIZE PR Body Template's `## Not verified`
#       section sits AFTER `## Test Plan` and BEFORE `## Task` (order-checked, not just presence);
#       the explanatory sentence states the aggregation source, the bullet shape, and the
#       omitted-entirely-when-empty rule; AND a cross-reference sentence exists naming
#       `agents/supervisor.md` as the actual Sequential/Single-Agent recording site.
#   (f) skills/self-heal-advisory/SKILL.md step 2 (the step that appends `## Outcome` to the BRIEF,
#       NOT step 2.5 which stamps the separate REQUIREMENT file) appends the same `## Not verified`
#       section to the brief, on both the PASS/loop-skipped and ESCALATED outcomes, omitted when
#       empty, and states it (not the PR body) is what `/verify` reads.
#   (g) docs/RESULT_SCHEMAS.md's §EXECUTE_RESULT blockquote states `not_verified` is NOT an
#       EXECUTE_RESULT field and reaches state.md via Context-Keeper, mirroring the `out_of_lane`
#       blockquote already there.
#   (r1) FIXTURE (row-write): a TEST-ONLY encoding of the documented row-write algorithm — a worker
#       result WITH one not_verified item writes a `not_verified: 1` count line + one indented
#       sub-list bullet; a worker result WITHOUT one writes a row with NO not_verified line at all
#       (byte-identical to a pre-item-04 row).
#   (r2) FIXTURE (PR-body aggregation): a TEST-ONLY encoding of the documented aggregation algorithm
#       — a two-worker `## Worker Results` fixture (one worker carrying one not_verified item, one
#       carrying none) renders EXACTLY one `## Not verified` bullet; the same fixture with NEITHER
#       worker carrying one renders NO such heading at all.
#   (m) MUTATION CONTROL: delete the state-management `not_verified` template line from a COPY of
#       the skill; assertion (b) MUST fail against the mutant. Without this, (b) could be green
#       while asserting nothing.
#
# EXPLICIT LIMIT (same class as test-deviations-advisory-seam.sh): (r1)/(r2) prove the DOCUMENTED
# algorithm is unambiguous and produces the exact promised byte output — they encode the spec text
# in a small bash renderer FOR TESTABILITY ONLY, because record_worker_result and the FINALIZE
# PR-body assembly are prompt-executed behaviors with no production script to invoke directly. They
# do NOT prove the live LLM Context-Keeper/Supervisor actually implements it that way — that is
# observable only on the NEXT job's real run.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$HERE/.." && pwd)"

CTXKEEPER="$PLUGIN_ROOT/agents/context-keeper.md"
STATEMGMT="$PLUGIN_ROOT/skills/state-management/SKILL.md"
EXECMGR="$PLUGIN_ROOT/agents/execute-manager.md"
SUPERVISOR="$PLUGIN_ROOT/agents/supervisor.md"
ASYNCORCH="$PLUGIN_ROOT/skills/async-orchestration/SKILL.md"
SELFHEAL="$PLUGIN_ROOT/skills/self-heal-advisory/SKILL.md"
SCHEMAS="$PLUGIN_ROOT/docs/RESULT_SCHEMAS.md"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

for f in "$CTXKEEPER" "$STATEMGMT" "$EXECMGR" "$SUPERVISOR" "$ASYNCORCH" "$SELFHEAL" "$SCHEMAS"; do
  if [ ! -f "$f" ]; then
    no "MISSING surface: $f"
  fi
done
if [ "$fail" -ne 0 ]; then
  echo
  echo "RESULT: $pass passed, $fail failed"
  exit 1
fi
command -v jq >/dev/null 2>&1 || { echo "  FAIL: jq is required by this suite"; echo "RESULT: 0 passed, 1 failed"; exit 1; }

# ---- (a) context-keeper.md operations table row -----------------------------------------------
rwr_row="$(grep -F '`record_worker_result`' "$CTXKEEPER" | head -1)"
case "$rwr_row" in
  *'out_of_lane, deviations, not_verified'*) ok "(a) record_worker_result row lists not_verified immediately after deviations" ;;
  *) no "(a) record_worker_result row does not list not_verified after deviations: $rwr_row" ;;
esac

# ---- (b) state-management/SKILL.md Worker Results row template -------------------------------
nv_tmpl_line() { grep -E '^- not_verified: ' "$1" 2>/dev/null | head -1; }
b_line="$(nv_tmpl_line "$STATEMGMT")"
if [ -n "$b_line" ]; then
  ok "(b) state-management/SKILL.md carries a not_verified template line"
else
  no "(b) state-management/SKILL.md is MISSING a not_verified template line"
fi
case "$b_line" in
  *'OMITTED ENTIRELY'*) ok "(b) template line states OMITTED ENTIRELY when n=0/absent" ;;
  *) no "(b) template line does not state the omitted-entirely rule" ;;
esac
case "$b_line" in
  *'UNLIKE out_of_lane/deviations'*'always show'*) ok "(b) template line names the asymmetry vs out_of_lane/deviations" ;;
  *) no "(b) template line does not name the out_of_lane/deviations asymmetry" ;;
esac
case "$b_line" in
  *'present ONLY when n>0'*'count'*'indented sub-list'*) ok "(b) template line states the count + indented sub-list shape" ;;
  *) no "(b) template line does not state the count + sub-list shape" ;;
esac

# ---- (c) execute-manager.md parallel-path Task call payload -----------------------------------
em_result_line="$(grep -F 'result: {files_modified, lines_added, lines_removed, tests_run, tests_passed, status, error,' "$EXECMGR" | head -1)"
case "$em_result_line" in
  *'out_of_lane, deviations, not_verified'*) ok "(c) execute-manager.md record_worker_result payload forwards not_verified after deviations" ;;
  *) no "(c) execute-manager.md payload missing not_verified: $em_result_line" ;;
esac

# ---- (d) supervisor.md Single-Agent Path + Sequential Path sentences --------------------------
single_agent_sec="$(awk '/^#### Single-Agent Path/{flag=1} flag{print; if (/^#### Sequential Path/) exit}' "$SUPERVISOR")"
case "$single_agent_sec" in
  *'`out_of_lane`, `deviations`,'*$'\n'*'and `not_verified` fields'*) ok "(d) Single-Agent Path step 2 names not_verified in the recording sentence" ;;
  *) no "(d) Single-Agent Path step 2 does not name not_verified in the recording sentence" ;;
esac
sequential_sec="$(awk '/^#### Sequential Path/{flag=1} flag{print}' "$SUPERVISOR")"
case "$sequential_sec" in
  *'`out_of_lane`, `deviations`,'*$'\n'*'and `not_verified` fields'*) ok "(d) Sequential Path step names not_verified in the recording sentence" ;;
  *) no "(d) Sequential Path step does not name not_verified in the recording sentence" ;;
esac

# ---- (e) async-orchestration/SKILL.md PR Body Template + cross-reference ----------------------
pr_template="$(awk '/^\*\*PR Body Template:\*\*/{flag=1} flag{print; if (/^```$/ && count++) exit}' "$ASYNCORCH")"
order_check="$(printf '%s\n' "$pr_template" | grep -nE '^## (Test Plan|Not verified|Task)$' | awk -F: '{print $2}')"
if [ "$order_check" = "## Test Plan
## Not verified
## Task" ]; then
  ok "(e) PR Body Template: ## Not verified sits between ## Test Plan and ## Task"
else
  no "(e) PR Body Template heading order wrong: $(printf '%s' "$order_check" | tr '\n' '|')"
fi
nv_explainer="$(grep -F '**`## Not verified` section (optional, harness-port/04):**' "$ASYNCORCH" | head -1)"
case "$nv_explainer" in
  *"state.md"*"## Worker Results"*) ok "(e) PR-body explainer names state.md's ## Worker Results as the aggregation source" ;;
  *) no "(e) PR-body explainer does not name the aggregation source" ;;
esac
case "$nv_explainer" in
  *'OMITTED ENTIRELY'*'no "none" line'*) ok "(e) PR-body explainer states the omitted-entirely-when-empty rule" ;;
  *) no "(e) PR-body explainer does not state the omitted-entirely rule" ;;
esac
xref="$(grep -F '**Recording `not_verified` on the Sequential and Single-Agent paths' "$ASYNCORCH" | head -1)"
case "$xref" in
  *'`agents/supervisor.md`'*) ok "(e) cross-reference sentence correctly names agents/supervisor.md as the recording site" ;;
  *) no "(e) cross-reference sentence missing or does not name agents/supervisor.md: $xref" ;;
esac

# ---- (f) self-heal-advisory/SKILL.md step 2 (brief-touching step, not step 2.5) ----------------
step2_sec="$(awk '/^2\. \*\*Job lifecycle completion\*\*/{flag=1} flag{print; if (/^2\.5\. /) exit}' "$SELFHEAL")"
if [ -n "$step2_sec" ]; then
  ok "(f) self-heal-advisory step 2 (Job lifecycle completion) section found"
else
  no "(f) self-heal-advisory step 2 section MISSING"
fi
case "$step2_sec" in
  *'appended to the brief itself, on BOTH the PASS/loop-skipped and ESCALATED outcomes'*) ok "(f) step 2 states the Not-verified section is appended on BOTH outcomes" ;;
  *) no "(f) step 2 does not state the both-outcomes rule" ;;
esac
case "$step2_sec" in
  *'OMITTED ENTIRELY'*'no "none" line'*) ok "(f) step 2 states the omitted-entirely-when-empty rule" ;;
  *) no "(f) step 2 does not state the omitted-entirely rule" ;;
esac
case "$step2_sec" in
  *'/verify'*'acs <ticket>'*'the PR body'*'is for the human only'*) ok "(f) step 2 states /verify reads the brief, the PR body is human-only" ;;
  *) no "(f) step 2 does not distinguish /verify's brief-read from the human-only PR body" ;;
esac

# ---- (g) RESULT_SCHEMAS.md §EXECUTE_RESULT blockquote ------------------------------------------
execres_block="$(awk '/^## EXECUTE_RESULT/{flag=1} flag{print; if (/^```yaml/) exit}' "$SCHEMAS")"
case "$execres_block" in
  *'`not_verified` is likewise NOT an `EXECUTE_RESULT` field'*) ok "(g) §EXECUTE_RESULT blockquote states not_verified is NOT an EXECUTE_RESULT field" ;;
  *) no "(g) §EXECUTE_RESULT blockquote missing the not_verified note" ;;
esac
case "$execres_block" in
  *'record_worker_result'*'## Worker'*'Results'*) ok "(g) blockquote names record_worker_result / ## Worker Results as the actual transport" ;;
  *) no "(g) blockquote does not name the actual transport path" ;;
esac

# ================================================================================================
# (r1) FIXTURE: row-write algorithm (TEST-ONLY encoding — see EXPLICIT LIMIT above)
# ================================================================================================
echo "== (r1) row-write fixture: not_verified count+sub-list when n>0, no line at all when n=0 =="

# render_worker_result_row <worker_id> <subtask_id> <not_verified_json_array>
# Encodes the documented state-management/SKILL.md row template: the not_verified line is present
# ONLY when the array is non-empty, as `not_verified: <n>` plus one indented `  - <surface> —
# <reason>` bullet per entry; otherwise the line (and its sub-list) is entirely absent.
render_worker_result_row() {
  local worker_id="$1" subtask_id="$2" nv_json="$3" n
  n="$(printf '%s' "$nv_json" | jq 'length')"
  printf '### %s (%s)\n' "$worker_id" "$subtask_id"
  printf -- '- files_modified: []\n'
  printf -- '- lines: +0 -0\n'
  printf -- '- tests: pass (0)\n'
  printf -- '- review: --\n'
  printf -- '- out_of_lane: []\n'
  printf -- '- deviations: []\n'
  if [ "$n" -gt 0 ]; then
    printf -- '- not_verified: %s\n' "$n"
    printf '%s' "$nv_json" | jq -r '.[] | "  - " + .surface + " — " + .reason'
  fi
}

WITH_NV='[{"surface":"CLI dispatcher","reason":"never exercised the fallback path"}]'
row_with="$(render_worker_result_row "worker-a" "1" "$WITH_NV")"
case "$row_with" in
  *$'\n- not_verified: 1\n  - CLI dispatcher — never exercised the fallback path'*) ok "(r1) a result WITH one not_verified item writes the count + sub-list bullet" ;;
  *) no "(r1) row_with did not render the expected not_verified line: $row_with" ;;
esac

row_without="$(render_worker_result_row "worker-b" "2" '[]')"
case "$row_without" in
  *'not_verified'*) no "(r1) a result WITHOUT any not_verified item still emitted a not_verified line (byte-identity broken): $row_without" ;;
  *) ok "(r1) a result WITHOUT any not_verified item writes NO not_verified line at all (byte-identical to a pre-item-04 row)" ;;
esac

# ================================================================================================
# (r2) FIXTURE: PR-body / done-brief aggregation algorithm (TEST-ONLY encoding)
# ================================================================================================
echo "== (r2) PR-body aggregation fixture: one bullet across two workers when one carries an item, none when neither does =="

# render_not_verified_section <state_md_worker_results_text> — encodes the documented aggregation:
# read every worker's row, collect each `  - <surface> — <reason>` bullet under a `- not_verified:`
# line, and re-render it in the PR-body / done-brief bullet shape `- **<surface>** — <reason>
# (subtask <id>)`. Prints NOTHING when no worker contributed a bullet (the omit-entirely rule).
render_not_verified_section() {
  local subtask="" in_nv=0 entry surface reason line
  while IFS= read -r line; do
    case "$line" in
      '### '*)
        subtask="${line##*\(}"
        subtask="${subtask%\)*}"
        in_nv=0
        ;;
      '- not_verified: '*)
        in_nv=1
        ;;
      '  - '*)
        if [ "$in_nv" -eq 1 ]; then
          entry="${line#  - }"
          surface="${entry%% — *}"
          reason="${entry#* — }"
          printf -- '- **%s** — %s (subtask %s)\n' "$surface" "$reason" "$subtask"
        fi
        ;;
      '- '*)
        in_nv=0
        ;;
    esac
  done
}

# Two-worker fixture: worker-a/subtask 1 carries one not_verified item; worker-b/subtask 2 carries none.
FIXTURE_WITH="$(render_worker_result_row "worker-a" "1" "$WITH_NV"; render_worker_result_row "worker-b" "2" '[]')"
section_with="$(printf '%s\n' "$FIXTURE_WITH" | render_not_verified_section)"
n_bullets="$(printf '%s\n' "$section_with" | grep -c '^- \*\*' || true)"
[ "$n_bullets" -eq 1 ] && ok "(r2) two-worker fixture (one carrying an item) renders EXACTLY one bullet" \
  || no "(r2) expected exactly 1 bullet, got $n_bullets: $section_with"
[ "$section_with" = "- **CLI dispatcher** — never exercised the fallback path (subtask 1)" ] \
  && ok "(r2) the rendered bullet matches the documented shape exactly" \
  || no "(r2) bullet shape mismatch: $section_with"

# Same two workers, NEITHER carrying a not_verified item -> no heading, no bullets at all.
FIXTURE_EMPTY="$(render_worker_result_row "worker-a" "1" '[]'; render_worker_result_row "worker-b" "2" '[]')"
section_empty="$(printf '%s\n' "$FIXTURE_EMPTY" | render_not_verified_section)"
[ -z "$section_empty" ] && ok "(r2) two-worker fixture with NEITHER carrying an item renders NOTHING (omit-entirely rule holds)" \
  || no "(r2) expected empty output, got: $section_empty"

# ================================================================================================
# (m) MUTATION CONTROL: (b) must go RED when the not_verified template line is deleted
# ================================================================================================
echo "== (m) mutation control =="
MUT="$(mktemp)"
trap 'rm -f "$MUT" 2>/dev/null' EXIT
sed -E '/^- not_verified: /d' "$STATEMGMT" > "$MUT"
if [ -s "$MUT" ] && ! cmp -s "$STATEMGMT" "$MUT"; then
  ok "(m) mutant is non-empty and differs from the original (a valid mutant)"
  mut_line="$(nv_tmpl_line "$MUT")"
  if [ -z "$mut_line" ]; then
    ok "(m) the not_verified template line is absent from the mutant (assertion (b) would fail against it)"
  else
    no "(m) the template line survived the mutation — the mutant did not mutate what it claims: $mut_line"
  fi
else
  no "(m) mutant invalid (empty, or identical to the original) — the mutation control cannot be trusted"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
