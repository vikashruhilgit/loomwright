#!/usr/bin/env bash
# test-run-eval.sh — self-tests for the System Twin EVAL harness (run-eval.sh).
# Mirrors test-benchmark.sh: isolated, deterministic, no network. Builds temp-fixture corpora via
# mktemp -d + trap cleanup, points run-eval.sh at them via $EVAL_CORPUS_DIR (never touches the real
# corpus). Exit 0 = all pass, 1 = any failure. Prints "RESULT: N passed, M failed".
#
# Covers:
#   1. pass/fail tallying — 2 passing + 1 failing check => total=3, passed=2, pass_rate "2/3",
#      and correct per_task statuses.
#   2. deterministic-same-result — two runs over the same fixture yield identical
#      tasks_total/tasks_passed/pass_rate/per_task (commit/date stripped before compare).
#   3. missing-corpus fail-safe — a non-existent corpus dir => status "unverified", exit 0.
#   4. non-executable check.sh — a present-but-not-executable check.sh is counted as a FAIL
#      (included in tasks_total, with a stderr warning), never silently dropped.
#   5. results.jsonl append — default-on appends the EVAL_RESULT (+ recorded_at) as one JSON line to
#      $EVAL_RESULTS_FILE; a second run appends (not overwrites); --no-record suppresses entirely;
#      an explicit --project <non-git dir> records to <project>/.supervisor/eval/results.jsonl by
#      default, while a non-git CWD with no --project records nothing (control).
#   6. project root — every check.sh receives EVAL_PROJECT_ROOT = the CALLER's project: (a) the git
#      toplevel of the CWD (a hermetic fixture repo, NOT this checkout), (b) `--project <dir>` when
#      given, (c) `--project <non-directory>` => status "unverified", 0/0, exit 0. Regression for the
#      2026-09-13 marketplace-install incident (corpus outside any git repo; checks resolved the repo
#      from their own dir).
# Cases 1-4 and 6 pass --no-record so they never touch the real .supervisor/eval/; case 5 redirects the
# history file into $TMP via $EVAL_RESULTS_FILE.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RUN="$HERE/run-eval.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "test-run-eval: jq not available — cannot exercise the eval harness; skipping (treated as pass)."
  echo; echo "RESULT: 0 passed, 0 failed"; exit 0
fi

# Pull the single EVAL_RESULT JSON object out of run-eval.sh output.
eval_json() { printf '%s\n' "$1" | sed -n 's/^EVAL_RESULT: //p' | head -n1; }

# ---- temp fixtures --------------------------------------------------------
TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# Fixture A: 2 passing + 1 failing task.
CORPUS_A="$TMP/corpus-a"
mk_task() {  # mk_task <corpus> <id> <exit-code>
  local c="$1" id="$2" code="$3"
  mkdir -p "$c/$id"
  printf 'task %s\n' "$id" > "$c/$id/spec.md"
  printf '#!/usr/bin/env bash\nexit %s\n' "$code" > "$c/$id/check.sh"
  chmod +x "$c/$id/check.sh"
}
mk_task "$CORPUS_A" "alpha" 0
mk_task "$CORPUS_A" "beta"  0
mk_task "$CORPUS_A" "gamma" 1   # failing

echo "== 1. pass/fail tallying (2 pass + 1 fail => 2/3) =="
oA="$( EVAL_CORPUS_DIR="$CORPUS_A" bash "$RUN" --no-record 2>/dev/null )"
jA="$(eval_json "$oA")"
if printf '%s' "$jA" \
  | jq -e '.tasks_total==3 and .tasks_passed==2 and .pass_rate=="2/3" and .status=="ok"' >/dev/null 2>&1; then
  ok "tally: total=3, passed=2, pass_rate=2/3, status=ok"
else
  no "tally wrong: $jA"
fi
# per_task statuses correct + sorted by id
if printf '%s' "$jA" | jq -e '
    (.per_task | map({(.id):.status}) | add)
    == {"alpha":"pass","beta":"pass","gamma":"fail"}
    and (.per_task | map(.id)) == (["alpha","beta","gamma"])
  ' >/dev/null 2>&1; then
  ok "per_task statuses correct and sorted by id"
else
  no "per_task wrong: $(printf '%s' "$jA" | jq -c '.per_task')"
fi

echo "== 2. deterministic-same-result (two runs, ignore commit/date) =="
o1="$( EVAL_CORPUS_DIR="$CORPUS_A" bash "$RUN" --no-record 2>/dev/null )"
o2="$( EVAL_CORPUS_DIR="$CORPUS_A" bash "$RUN" --no-record 2>/dev/null )"
strip() {  # drop the contextual commit/date fields before comparing
  printf '%s' "$(eval_json "$1")" \
    | jq -cS '{schema_version,tasks_total,tasks_passed,pass_rate,per_task,status}'
}
s1="$(strip "$o1")"; s2="$(strip "$o2")"
[ -n "$s1" ] && [ "$s1" = "$s2" ] \
  && ok "identical determinism-invariant fields across two runs" \
  || no "non-deterministic: $s1 vs $s2"

echo "== 3. missing-corpus fail-safe =="
oM="$( EVAL_CORPUS_DIR="$TMP/does-not-exist" bash "$RUN" --no-record 2>/dev/null )"; rc=$?
jM="$(eval_json "$oM")"
if [ "$rc" -eq 0 ] && printf '%s' "$jM" \
  | jq -e '.status=="unverified" and .tasks_total==0 and .pass_rate=="0/0" and (.per_task|length)==0' >/dev/null 2>&1; then
  ok "missing corpus => status unverified, 0/0, per_task [], exit 0"
else
  no "fail-safe path wrong (rc=$rc): $jM"
fi

echo "== 4. non-executable check.sh => counted as FAIL (not silently dropped) =="
CORPUS_NX="$TMP/corpus-nx"
mk_task "$CORPUS_NX" "runs-ok" 0                                    # normal passing task (chmod +x)
mkdir -p "$CORPUS_NX/not-exec"
printf 'task not-exec\n' > "$CORPUS_NX/not-exec/spec.md"
printf '#!/usr/bin/env bash\nexit 0\n' > "$CORPUS_NX/not-exec/check.sh"   # deliberately NOT chmod +x
oNX="$( EVAL_CORPUS_DIR="$CORPUS_NX" bash "$RUN" --no-record 2>/dev/null )"
jNX="$(eval_json "$oNX")"
if printf '%s' "$jNX" | jq -e '
    .tasks_total==2 and .tasks_passed==1 and .pass_rate=="1/2"
    and ((.per_task | map({(.id):.status}) | add) == {"not-exec":"fail","runs-ok":"pass"})
  ' >/dev/null 2>&1; then
  ok "non-executable check.sh counted as FAIL (included in total, not dropped)"
else
  no "non-exec handling wrong: $jNX"
fi
# the warning must reach stderr (visibility is the whole point)
eNX="$( EVAL_CORPUS_DIR="$CORPUS_NX" bash "$RUN" --no-record 2>&1 >/dev/null )"
case "$eNX" in
  *"not executable"*) ok "emits a stderr warning for the non-executable task" ;;
  *) no "expected a stderr warning about non-executable check.sh, got: $eNX" ;;
esac

echo "== 5. results.jsonl append (default on; --no-record suppresses) =="
# a. Default-on: append the run's EVAL_RESULT line to EVAL_RESULTS_FILE => 1 valid line.
RF="$TMP/eval/results.jsonl"
EVAL_CORPUS_DIR="$CORPUS_A" EVAL_RESULTS_FILE="$RF" bash "$RUN" >/dev/null 2>&1
if [ -f "$RF" ] && [ "$(wc -l < "$RF" | tr -d ' ')" = "1" ] \
  && tail -n1 "$RF" | jq -e '.pass_rate=="2/3" and .status=="ok" and (.recorded_at|type=="string" and length>0)' >/dev/null 2>&1; then
  ok "default-on append: 1 line, valid JSON, pass_rate 2/3, status ok, non-empty recorded_at"
else
  no "default-on append wrong (lines=$( [ -f "$RF" ] && wc -l < "$RF" || echo MISSING )): $( [ -f "$RF" ] && tail -n1 "$RF" )"
fi

# b. Second run, same file, no --no-record => appends (2 lines, not overwrite).
EVAL_CORPUS_DIR="$CORPUS_A" EVAL_RESULTS_FILE="$RF" bash "$RUN" >/dev/null 2>&1
if [ "$(wc -l < "$RF" | tr -d ' ')" = "2" ]; then
  ok "second run appends (2 lines, not overwrite)"
else
  no "expected 2 lines after append, got $(wc -l < "$RF" | tr -d ' ')"
fi

# c. --no-record suppresses: fresh non-existent target must NOT be created; exit 0.
RF2="$TMP/eval-suppressed/results.jsonl"
EVAL_CORPUS_DIR="$CORPUS_A" EVAL_RESULTS_FILE="$RF2" bash "$RUN" --no-record >/dev/null 2>&1; rcS=$?
if [ ! -e "$RF2" ] && [ "$rcS" -eq 0 ]; then
  ok "--no-record suppresses the append (file not created) and exits 0"
else
  no "--no-record suppression wrong (exists=$( [ -e "$RF2" ] && echo yes || echo no ), rc=$rcS)"
fi

# d. Default recording target follows --project: an explicit --project that is NOT a git repo, with
#    no --no-record and no EVAL_RESULTS_FILE, records to <project>/.supervisor/eval/results.jsonl —
#    the caller named the project, so recording there is wanted. Mutation control: from the same
#    non-git CWD WITHOUT --project nothing is written anywhere under it (no git root, no flag ⇒ the
#    default target is skipped, exactly as before the flag existed).
PROJ_NG="$TMP/project-nongit"
mkdir -p "$PROJ_NG"
( cd "$TMP" && EVAL_CORPUS_DIR="$CORPUS_A" env -u EVAL_RESULTS_FILE bash "$RUN" --project "$PROJ_NG" >/dev/null 2>&1 ); rcD=$?
RFD="$PROJ_NG/.supervisor/eval/results.jsonl"
if [ "$rcD" -eq 0 ] && [ -f "$RFD" ] && [ "$(wc -l < "$RFD" | tr -d ' ')" = "1" ] \
  && tail -n1 "$RFD" | jq -e '.pass_rate=="2/3" and .status=="ok"' >/dev/null 2>&1; then
  ok "--project <non-git dir> (default recording): 1 line at <project>/.supervisor/eval/results.jsonl"
else
  no "--project default recording wrong (rc=$rcD, exists=$( [ -f "$RFD" ] && echo yes || echo no ))"
fi
CWD_NG="$TMP/cwd-nongit"
mkdir -p "$CWD_NG"
( cd "$CWD_NG" && EVAL_CORPUS_DIR="$CORPUS_A" env -u EVAL_RESULTS_FILE bash "$RUN" >/dev/null 2>&1 ); rcD2=$?
if [ "$rcD2" -eq 0 ] && [ ! -e "$CWD_NG/.supervisor" ]; then
  ok "control: non-git CWD without --project records nothing under it (default target skipped)"
else
  no "control wrong (rc=$rcD2): $(find "$CWD_NG" -type f 2>/dev/null | head -3)"
fi

echo "== 6. project root: EVAL_PROJECT_ROOT reaches check.sh (CWD git toplevel, --project, invalid) =="
# A recording check: it PASSES iff EVAL_PROJECT_ROOT is set, and writes the value it saw so the test
# can assert WHICH project it was told to verify.
CORPUS_P="$TMP/corpus-p"
mkdir -p "$CORPUS_P/probe"
cat > "$CORPUS_P/probe/check.sh" <<'EOF'
#!/usr/bin/env bash
[ -n "${EVAL_PROJECT_ROOT:-}" ] || exit 1
printf '%s' "$EVAL_PROJECT_ROOT" > "$(dirname "$0")/seen"
exit 0
EOF
chmod +x "$CORPUS_P/probe/check.sh"
# (a) A hermetic fixture git repo as the caller's CWD (a subdir of it, so the toplevel must be derived,
# not just the CWD echoed). Pinned config so the init never reads the user's git config.
FIX="$TMP/fixture-repo"
mkdir -p "$FIX/sub"
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git -C "$FIX" -c init.defaultBranch=main init -q
FIX_P="$(cd "$FIX" && pwd -P)"
rm -f "$CORPUS_P/probe/seen"
oP1="$( cd "$FIX/sub" && EVAL_CORPUS_DIR="$CORPUS_P" bash "$RUN" --no-record 2>/dev/null )"; rcP1=$?
seen1="$(cat "$CORPUS_P/probe/seen" 2>/dev/null || true)"
if [ "$rcP1" -eq 0 ] && [ "$seen1" = "$FIX_P" ] \
  && printf '%s' "$(eval_json "$oP1")" | jq -e '.tasks_total==1 and .tasks_passed==1 and .status=="ok"' >/dev/null 2>&1; then
  ok "6a. CWD inside a git repo: check.sh saw EVAL_PROJECT_ROOT == that repo's toplevel (not this checkout, not the task dir)"
else
  no "6a. wrong (rc=$rcP1): seen='$seen1' expected='$FIX_P'"
fi
# (b) --project overrides the CWD-derived root (CWD = non-git $TMP; project = the fixture repo).
rm -f "$CORPUS_P/probe/seen"
oP2="$( cd "$TMP" && EVAL_CORPUS_DIR="$CORPUS_P" bash "$RUN" --no-record --project "$FIX" 2>/dev/null )"; rcP2=$?
seen2="$(cat "$CORPUS_P/probe/seen" 2>/dev/null || true)"
if [ "$rcP2" -eq 0 ] && [ "$seen2" = "$FIX_P" ]; then
  ok "6b. --project <dir>: check.sh saw EVAL_PROJECT_ROOT == that dir"
else
  no "6b. wrong (rc=$rcP2): seen='$seen2' expected='$FIX_P'"
fi
# (c) --project naming a non-directory: fail-safe unverified, 0/0, exit 0; the check never runs.
rm -f "$CORPUS_P/probe/seen"
oP3="$( cd "$TMP" && EVAL_CORPUS_DIR="$CORPUS_P" bash "$RUN" --no-record --project "$TMP/does-not-exist" 2>/dev/null )"; rcP3=$?
if [ "$rcP3" -eq 0 ] && [ ! -e "$CORPUS_P/probe/seen" ] \
  && printf '%s' "$(eval_json "$oP3")" | jq -e '.status=="unverified" and .tasks_total==0 and .pass_rate=="0/0"' >/dev/null 2>&1; then
  ok "6c. --project <non-directory>: status unverified, 0/0, check never ran, exit 0"
else
  no "6c. wrong (rc=$rcP3): $(eval_json "$oP3")"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
